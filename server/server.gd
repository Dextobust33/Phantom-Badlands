# server.gd
# Server with persistence, account system, and permadeath
extends Control

const DEFAULT_PORT = 9080
var PORT = DEFAULT_PORT  # Can be overridden by command line arg --port=XXXX

# UI References
@onready var player_count_label = $VBox/StatusRow/PlayerCountLabel
@onready var player_list = $VBox/PlayerList
@onready var server_log = $VBox/ServerLog
@onready var restart_button = $VBox/ButtonRow/RestartButton
@onready var confirm_dialog = $ConfirmDialog
@onready var broadcast_input = $VBox/BroadcastRow/BroadcastInput
@onready var broadcast_button = $VBox/BroadcastRow/BroadcastButton
const PersistenceManagerScript = preload("res://server/persistence_manager.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const QuestDatabaseScript = preload("res://shared/quest_database.gd")
const QuestManagerScript = preload("res://shared/quest_manager.gd")
const TradingPostDatabaseScript = preload("res://shared/trading_post_database.gd")

var server = TCPServer.new()
var peers = {}
var next_peer_id = 1
var characters = {}
var pending_flocks = {}  # peer_id -> {monster_name, monster_level}
var pending_flock_drops = {}  # peer_id -> Array of accumulated drops during flock
var pending_flock_gems = {}   # peer_id -> Total gems earned during flock
var at_merchant = {}  # peer_id -> merchant_info dictionary
var at_trading_post = {}  # peer_id -> trading_post_data dictionary

# Persistent merchant inventory storage
# merchant_id -> {items: Array, generated_at: float, player_level: int}
var merchant_inventories = {}
const INVENTORY_REFRESH_INTERVAL = 300.0  # 5 minutes
var watchers = {}  # peer_id -> Array of peer_ids watching this player
var watching = {}  # peer_id -> peer_id of player being watched (or -1 if not watching)
var monster_db: MonsterDatabase
var combat_mgr: CombatManager
var world_system: WorldSystem
var persistence: Node
var drop_tables: Node
var quest_db: Node
var quest_mgr: Node
var trading_post_db: Node
var balance_config: Dictionary = {}

# Auto-save timer
const AUTO_SAVE_INTERVAL = 60.0  # Save every 60 seconds
var auto_save_timer = 0.0

# Connection security
const AUTH_TIMEOUT = 30.0  # Kick unauthenticated connections after 30 seconds
const MAX_CONNECTIONS_PER_IP = 3  # Max simultaneous connections from one IP
const CONNECTION_RATE_LIMIT = 5.0  # Seconds between connection attempts from same IP
var ip_connection_times: Dictionary = {}  # IP -> last connection timestamp
var ip_connection_counts: Dictionary = {}  # IP -> current connection count
var security_check_timer: float = 0.0
const SECURITY_CHECK_INTERVAL = 5.0  # Check for stale connections every 5 seconds

# Player list update timer (refreshes connected players display)
const PLAYER_LIST_UPDATE_INTERVAL = 180.0  # Update every 3 minutes
var player_list_update_timer = 0.0

# Merchant movement update timer (refreshes maps to show merchant movement)
const MERCHANT_UPDATE_INTERVAL = 10.0  # Check every 10 seconds
var merchant_update_timer = 0.0
var last_merchant_cache_positions: Dictionary = {}  # Tracks merchant positions for change detection

func _ready():
	# Parse command line arguments for port
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--port="):
			var port_str = arg.substr(7)
			if port_str.is_valid_int():
				PORT = int(port_str)
				print("Using custom port from command line: %d" % PORT)

	print("========================================")
	print("Phantasia Revival Server Starting...")
	print("========================================")

	# Initialize persistence system
	persistence = PersistenceManagerScript.new()
	add_child(persistence)

	# Initialize world system
	world_system = WorldSystem.new()
	add_child(world_system)

	# Initialize combat systems
	monster_db = MonsterDatabase.new()
	add_child(monster_db)

	combat_mgr = CombatManager.new()
	add_child(combat_mgr)

	# Initialize drop tables and connect to combat manager
	drop_tables = DropTablesScript.new()
	add_child(drop_tables)
	combat_mgr.set_drop_tables(drop_tables)
	combat_mgr.set_monster_database(monster_db)

	# Initialize quest systems
	quest_db = QuestDatabaseScript.new()
	add_child(quest_db)
	quest_mgr = QuestManagerScript.new()
	add_child(quest_mgr)

	# Initialize trading post database
	trading_post_db = TradingPostDatabaseScript.new()
	add_child(trading_post_db)

	# Load and apply balance configuration
	load_balance_config()
	combat_mgr.set_balance_config(balance_config)
	monster_db.set_balance_config(balance_config)

	var error = server.listen(PORT)
	if error != OK:
		print("ERROR: Failed to start server on port %d" % PORT)
		print("Error code: %d" % error)
		return

	log_message("Persistence system loaded")
	log_message("Server started successfully!")
	log_message("Listening on port: %d" % PORT)
	log_message("Waiting for connections...")
	update_player_list()

	# Connect restart button and confirmation dialog
	if restart_button:
		restart_button.pressed.connect(_on_restart_button_pressed)
	if confirm_dialog:
		confirm_dialog.confirmed.connect(_on_restart_confirmed)

	# Connect broadcast button and input
	if broadcast_button:
		broadcast_button.pressed.connect(_on_broadcast_button_pressed)
	if broadcast_input:
		broadcast_input.text_submitted.connect(_on_broadcast_submitted)

func log_message(msg: String):
	"""Log a message to console and server UI."""
	print(msg)
	if server_log:
		var timestamp = Time.get_time_string_from_system()
		server_log.append_text("[color=#808080][%s][/color] %s\n" % [timestamp, msg])

func _on_restart_button_pressed():
	"""Show confirmation dialog before restarting."""
	if confirm_dialog:
		confirm_dialog.popup_centered()

func _on_broadcast_button_pressed():
	"""Send broadcast message from button press."""
	if broadcast_input and broadcast_input.text.strip_edges() != "":
		_send_broadcast(broadcast_input.text.strip_edges())
		broadcast_input.text = ""

func _on_broadcast_submitted(text: String):
	"""Send broadcast message from Enter key."""
	if text.strip_edges() != "":
		_send_broadcast(text.strip_edges())
		broadcast_input.text = ""

func _send_broadcast(message: String):
	"""Broadcast a server announcement to all connected players."""
	log_message("[BROADCAST] %s" % message)

	var broadcast_msg = {
		"type": "server_broadcast",
		"message": message
	}

	for peer_id in peers.keys():
		send_to_peer(peer_id, broadcast_msg)

func load_balance_config():
	"""Load balance configuration from JSON file. Falls back to defaults if missing."""
	var config_path = "res://server/balance_config.json"

	if not FileAccess.file_exists(config_path):
		log_message("[BALANCE] Config file not found, using defaults")
		balance_config = _get_default_balance_config()
		return

	var file = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		log_message("[BALANCE] Failed to open config file, using defaults")
		balance_config = _get_default_balance_config()
		return

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)

	if parse_result != OK:
		log_message("[BALANCE] Failed to parse config JSON: %s" % json.get_error_message())
		balance_config = _get_default_balance_config()
		return

	balance_config = json.get_data()
	var profile = balance_config.get("profile", "unknown")
	var version = balance_config.get("version", "unknown")
	log_message("[BALANCE] Loaded config profile: %s (v%s)" % [profile, version])

func _get_default_balance_config() -> Dictionary:
	"""Return default balance configuration (legacy behavior)"""
	return {
		"profile": "legacy",
		"version": "1.0",
		"combat": {
			"player_str_multiplier": 0.02,
			"player_crit_base": 5,
			"player_crit_per_dex": 0.5,
			"player_crit_max": 25,
			"player_crit_damage": 1.5,
			"monster_level_diff_base": 1.05,
			"monster_level_diff_cap": 50,
			"defense_formula_constant": 100,
			"defense_max_reduction": 0.6,
			"equipment_defense_cap": 0.0,
			"equipment_defense_divisor": 500
		},
		"lethality": {
			"hp_weight": 1.0,
			"str_weight": 3.0,
			"def_weight": 1.0,
			"speed_weight": 2.0,
			"ability_modifiers": {}
		},
		"rewards": {
			"xp_level_diff_multiplier": 0.10,
			"xp_high_level_base": 6.0,
			"xp_high_level_bonus": 0.05,
			"gold_lethality_multiplier": 0.0,
			"gold_lethality_cap": 1.0,
			"gem_lethality_divisor": 1000,
			"gem_level_divisor": 100
		},
		"drops": {
			"quality_bonus_thresholds": [500, 1000, 5000],
			"quality_bonus_values": [1, 2, 3]
		}
	}

func _on_restart_confirmed():
	"""Restart the server after confirmation."""
	log_message("Server restart initiated...")

	# Save all active characters
	save_all_active_characters()

	# Notify all connected players
	for peer_id in peers.keys():
		send_to_peer(peer_id, {
			"type": "server_message",
			"message": "[color=#FFFF00]Server is restarting...[/color]"
		})

	# Disconnect all peers
	var peer_ids = peers.keys().duplicate()
	for peer_id in peer_ids:
		handle_disconnect(peer_id)

	# Stop the server
	server.stop()
	log_message("Server stopped.")

	# Clear all state
	peers.clear()
	characters.clear()
	pending_flocks.clear()
	pending_flock_drops.clear()
	pending_flock_gems.clear()
	at_merchant.clear()
	at_trading_post.clear()
	next_peer_id = 1
	auto_save_timer = 0.0

	# Restart the server
	var error = server.listen(PORT)
	if error != OK:
		log_message("ERROR: Failed to restart server on port %d" % PORT)
		return

	log_message("Server restarted successfully!")
	log_message("Listening on port: %d" % PORT)
	log_message("Waiting for connections...")
	update_player_list()

func update_player_list():
	"""Update the player list UI with connected players."""
	if player_count_label:
		player_count_label.text = "Players: %d" % characters.size()

	if player_list:
		player_list.clear()
		if characters.size() == 0:
			player_list.append_text("[color=#555555]No players connected[/color]")
		else:
			for peer_id in characters:
				var char = characters[peer_id]
				var peer_info = peers.get(peer_id, {})
				var username = peer_info.get("username", "Unknown")
				var char_name = char.name
				var level = char.level
				var race = char.race
				var cls = char.class_type
				player_list.append_text("[color=#00FFFF]%s[/color] - %s %s Lv.%d [color=#555555](%s)[/color]\n" % [
					char_name, race, cls, level, username
				])

func _process(delta):
	# Auto-save timer
	auto_save_timer += delta
	if auto_save_timer >= AUTO_SAVE_INTERVAL:
		auto_save_timer = 0.0
		save_all_active_characters()

	# Player list update timer (refresh display periodically)
	player_list_update_timer += delta
	if player_list_update_timer >= PLAYER_LIST_UPDATE_INTERVAL:
		player_list_update_timer = 0.0
		update_player_list()

	# Update traveling merchants and send map updates to players when merchants move
	if world_system:
		world_system.update_merchants(delta)

		# Check for merchant position changes and update player maps
		merchant_update_timer += delta
		if merchant_update_timer >= MERCHANT_UPDATE_INTERVAL:
			merchant_update_timer = 0.0
			send_merchant_movement_updates()

	# Check for new connections
	if server.is_connection_available():
		var peer = server.take_connection()
		var peer_ip = peer.get_connected_host()
		var current_time = Time.get_unix_time_from_system()

		# Security: Rate limiting - check if IP is connecting too fast
		if ip_connection_times.has(peer_ip):
			var last_connect = ip_connection_times[peer_ip]
			if current_time - last_connect < CONNECTION_RATE_LIMIT:
				log_message("Rate limit: Rejecting rapid connection from %s" % peer_ip)
				peer.disconnect_from_host()
				return

		# Security: Check max connections per IP
		var current_count = ip_connection_counts.get(peer_ip, 0)
		if current_count >= MAX_CONNECTIONS_PER_IP:
			log_message("Connection limit: Rejecting connection from %s (max %d)" % [peer_ip, MAX_CONNECTIONS_PER_IP])
			peer.disconnect_from_host()
			return

		# Accept connection
		var peer_id = next_peer_id
		next_peer_id += 1

		peers[peer_id] = {
			"connection": peer,
			"authenticated": false,
			"account_id": "",
			"username": "",
			"character_name": "",
			"buffer": "",
			"connect_time": current_time,
			"ip": peer_ip
		}

		# Track IP connection
		ip_connection_times[peer_ip] = current_time
		ip_connection_counts[peer_ip] = current_count + 1

		log_message("New connection! Peer ID: %d from %s" % [peer_id, peer_ip])

		# Send welcome message
		send_to_peer(peer_id, {
			"type": "welcome",
			"message": "Welcome to Phantasia Revival!",
			"server_version": "0.1.0"
		})

	# Process existing connections
	var disconnected_peers = []
	for peer_id in peers.keys():
		var peer_data = peers[peer_id]
		var connection = peer_data.connection

		# CRITICAL: Poll each connection to advance its state!
		connection.poll()

		# Check if still connected
		if connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			disconnected_peers.append(peer_id)
			continue

		# Read available data
		var available = connection.get_available_bytes()
		if available > 0:
			var data = connection.get_data(available)
			if data[0] == OK:
				var message = data[1].get_string_from_utf8()
				peer_data.buffer += message

				# Try to parse complete JSON messages
				process_buffer(peer_id)

	# Clean up disconnected peers
	for peer_id in disconnected_peers:
		handle_disconnect(peer_id)

	# Security: Periodically check for stale unauthenticated connections
	security_check_timer += delta
	if security_check_timer >= SECURITY_CHECK_INTERVAL:
		security_check_timer = 0.0
		_check_stale_connections()

func process_buffer(peer_id: int):
	var peer_data = peers[peer_id]
	var buffer = peer_data.buffer

	while "\n" in buffer:
		var newline_pos = buffer.find("\n")
		var message_str = buffer.substr(0, newline_pos)
		buffer = buffer.substr(newline_pos + 1)

		var json = JSON.new()
		var error = json.parse(message_str)

		if error == OK:
			var message = json.data
			handle_message(peer_id, message)
		else:
			print("JSON parse error from peer %d: %s" % [peer_id, message_str])

	peer_data.buffer = buffer

func handle_message(peer_id: int, message: Dictionary):
	var msg_type = message.get("type", "")

	match msg_type:
		"register":
			handle_register(peer_id, message)
		"login":
			handle_login(peer_id, message)
		"list_characters":
			handle_list_characters(peer_id)
		"select_character":
			handle_select_character(peer_id, message)
		"create_character":
			handle_create_character(peer_id, message)
		"delete_character":
			handle_delete_character(peer_id, message)
		"get_leaderboard":
			handle_get_leaderboard(peer_id, message)
		"chat":
			handle_chat(peer_id, message)
		"move":
			handle_move(peer_id, message)
		"hunt":
			handle_hunt(peer_id)
		"combat":
			handle_combat_command(peer_id, message)
		"combat_use_item":
			handle_combat_use_item(peer_id, message)
		"wish_select":
			handle_wish_select(peer_id, message)
		"continue_flock":
			handle_continue_flock(peer_id)
		"rest":
			handle_rest(peer_id)
		"get_players":
			handle_get_players(peer_id)
		"examine_player":
			handle_examine_player(peer_id, message)
		"logout_character":
			handle_logout_character(peer_id)
		"logout_account":
			handle_logout_account(peer_id)
		"inventory_use":
			handle_inventory_use(peer_id, message)
		"inventory_equip":
			handle_inventory_equip(peer_id, message)
		"inventory_unequip":
			handle_inventory_unequip(peer_id, message)
		"inventory_discard":
			handle_inventory_discard(peer_id, message)
		"monster_select_confirm":
			handle_monster_select_confirm(peer_id, message)
		"merchant_sell":
			handle_merchant_sell(peer_id, message)
		"merchant_sell_all":
			handle_merchant_sell_all(peer_id)
		"merchant_sell_gems":
			handle_merchant_sell_gems(peer_id, message)
		"merchant_upgrade":
			handle_merchant_upgrade(peer_id, message)
		"merchant_gamble":
			handle_merchant_gamble(peer_id, message)
		"merchant_buy":
			handle_merchant_buy(peer_id, message)
		"merchant_recharge":
			handle_merchant_recharge(peer_id)
		"merchant_leave":
			handle_merchant_leave(peer_id)
		"change_password":
			handle_change_password(peer_id, message)
		# Trading Post handlers
		"trading_post_shop":
			handle_trading_post_shop(peer_id)
		"trading_post_quests":
			handle_trading_post_quests(peer_id)
		"trading_post_recharge":
			handle_trading_post_recharge(peer_id)
		"trading_post_leave":
			handle_trading_post_leave(peer_id)
		# Quest handlers
		"quest_accept":
			handle_quest_accept(peer_id, message)
		"quest_abandon":
			handle_quest_abandon(peer_id, message)
		"quest_turn_in":
			handle_quest_turn_in(peer_id, message)
		"get_quest_log":
			handle_get_quest_log(peer_id)
		# Watch/Inspect handlers
		"watch_request":
			handle_watch_request(peer_id, message)
		"watch_approve":
			handle_watch_approve(peer_id, message)
		"watch_deny":
			handle_watch_deny(peer_id, message)
		"watch_stop":
			handle_watch_stop(peer_id)
		_:
			pass

# ===== ACCOUNT HANDLERS =====

func handle_register(peer_id: int, message: Dictionary):
	var username = message.get("username", "")
	var password = message.get("password", "")

	var result = persistence.create_account(username, password)

	if result.success:
		send_to_peer(peer_id, {
			"type": "register_success",
			"username": result.username,
			"message": "Account created successfully! Please log in."
		})
	else:
		send_to_peer(peer_id, {
			"type": "register_failed",
			"reason": result.reason
		})

func handle_login(peer_id: int, message: Dictionary):
	var username = message.get("username", "")
	var password = message.get("password", "")

	var result = persistence.authenticate(username, password)

	if result.success:
		peers[peer_id].authenticated = true
		peers[peer_id].account_id = result.account_id
		peers[peer_id].username = result.username

		log_message("Account authenticated: %s (Peer %d)" % [username, peer_id])

		send_to_peer(peer_id, {
			"type": "login_success",
			"username": result.username,
			"message": "Login successful!"
		})

		# Automatically send character list
		handle_list_characters(peer_id)
	else:
		send_to_peer(peer_id, {
			"type": "login_failed",
			"reason": result.reason
		})

func handle_list_characters(peer_id: int):
	if not peers[peer_id].authenticated:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "You must be logged in"
		})
		return

	var account_id = peers[peer_id].account_id
	var char_list = persistence.get_account_characters(account_id)
	var can_create = persistence.can_create_character(account_id)

	send_to_peer(peer_id, {
		"type": "character_list",
		"characters": char_list,
		"can_create": can_create,
		"max_characters": 3
	})

func handle_select_character(peer_id: int, message: Dictionary):
	if not peers[peer_id].authenticated:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "You must be logged in"
		})
		return

	var char_name = message.get("name", "")
	var account_id = peers[peer_id].account_id

	# Check if this character is already logged in on another client
	for other_peer_id in characters.keys():
		if other_peer_id != peer_id:
			var other_char = characters[other_peer_id]
			if other_char.name.to_lower() == char_name.to_lower():
				var other_account = peers.get(other_peer_id, {}).get("account_id", "")
				if other_account == account_id:
					send_to_peer(peer_id, {
						"type": "error",
						"message": "This character is already logged in on another client!"
					})
					return

	# Load character from persistence
	var character = persistence.load_character_as_object(account_id, char_name)

	if character == null:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Character not found"
		})
		return

	# Set character ID to peer ID for combat tracking
	character.character_id = peer_id

	# Store character in active characters
	characters[peer_id] = character
	peers[peer_id].character_name = char_name

	var username = peers[peer_id].username
	log_message("Character loaded: %s (Account: %s) for peer %d" % [char_name, username, peer_id])
	update_player_list()

	send_to_peer(peer_id, {
		"type": "character_loaded",
		"character": character.to_dict(),
		"message": "Welcome back, %s!" % char_name
	})

	# Broadcast join message to other players
	broadcast_chat("[color=#00FF00]%s has entered the realm.[/color]" % char_name)

	send_location_update(peer_id)

func handle_create_character(peer_id: int, message: Dictionary):
	if not peers[peer_id].authenticated:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "You must be logged in"
		})
		return

	var account_id = peers[peer_id].account_id

	# Check if can create more characters
	if not persistence.can_create_character(account_id):
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Maximum characters reached (3)"
		})
		return

	var char_name = message.get("name", "")
	var char_class = message.get("class", "Fighter")

	# Validate character name
	if char_name.is_empty():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Character name cannot be empty"
		})
		return

	if char_name.length() < 2:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Character name must be at least 2 characters"
		})
		return

	if char_name.length() > 16:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Character name cannot exceed 16 characters"
		})
		return

	# Check for valid characters
	var valid_regex = RegEx.new()
	valid_regex.compile("^[a-zA-Z0-9_]+$")
	if not valid_regex.search(char_name):
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Character name can only contain letters, numbers, and underscores"
		})
		return

	# Check if name already exists
	if persistence.character_name_exists(char_name):
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Character name already taken"
		})
		return

	# Validate class (6 available classes: 2 Warrior, 2 Mage, 2 Trickster)
	var valid_classes = ["Fighter", "Barbarian", "Wizard", "Sage", "Thief", "Ranger"]
	if char_class not in valid_classes:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid class. Choose: " + ", ".join(valid_classes)
		})
		return

	# Validate race
	var char_race = message.get("race", "Human")
	var valid_races = ["Human", "Elf", "Dwarf", "Ogre"]
	if char_race not in valid_races:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid race. Choose: " + ", ".join(valid_races)
		})
		return

	# Create character
	var character = Character.new()
	character.initialize(char_name, char_class, char_race)
	character.character_id = peer_id

	# Save character to persistence
	persistence.save_character(account_id, character)
	persistence.add_character_to_account(account_id, char_name)

	# Store in active characters
	characters[peer_id] = character
	peers[peer_id].character_name = char_name

	log_message("Character created: %s (%s %s) for peer %d" % [char_name, char_race, char_class, peer_id])
	update_player_list()

	send_to_peer(peer_id, {
		"type": "character_created",
		"character": character.to_dict(),
		"message": "Welcome to the world, %s!" % char_name
	})

	# Broadcast join message to other players
	broadcast_chat("[color=#00FF00]%s has entered the realm.[/color]" % char_name)

	send_location_update(peer_id)

func handle_delete_character(peer_id: int, message: Dictionary):
	if not peers[peer_id].authenticated:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "You must be logged in"
		})
		return

	var char_name = message.get("name", "")
	var account_id = peers[peer_id].account_id

	# Check if this character is currently active
	if characters.has(peer_id) and characters[peer_id].name == char_name:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Cannot delete active character. Select a different one first."
		})
		return

	# Delete from persistence
	var success = persistence.delete_character(account_id, char_name)

	if success:
		send_to_peer(peer_id, {
			"type": "character_deleted",
			"name": char_name,
			"message": "%s has been deleted." % char_name
		})

		# Send updated character list
		handle_list_characters(peer_id)
	else:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Failed to delete character"
		})

func handle_get_leaderboard(peer_id: int, message: Dictionary):
	var limit = message.get("limit", 10)
	limit = clamp(limit, 1, 100)

	var entries = persistence.get_leaderboard(limit)

	send_to_peer(peer_id, {
		"type": "leaderboard",
		"entries": entries
	})

func handle_get_players(peer_id: int):
	"""Get list of all online players"""
	var player_list = []

	for pid in characters.keys():
		var char = characters[pid]
		player_list.append({
			"name": char.name,
			"level": char.level,
			"class": char.class_type
		})

	send_to_peer(peer_id, {
		"type": "player_list",
		"players": player_list,
		"count": player_list.size()
	})

func handle_examine_player(peer_id: int, message: Dictionary):
	"""Examine another player's character"""
	var target_name = message.get("name", "")

	if target_name.is_empty():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Specify a player name to examine"
		})
		return

	# Find the target player
	for pid in characters.keys():
		var char = characters[pid]
		if char.name.to_lower() == target_name.to_lower():
			var bonuses = char.get_equipment_bonuses()
			send_to_peer(peer_id, {
				"type": "examine_result",
				"name": char.name,
				"race": char.race,
				"level": char.level,
				"experience": char.experience,
				"experience_to_next_level": char.experience_to_next_level,
				"class": char.class_type,
				"hp": char.current_hp,
				"max_hp": char.get_total_max_hp(),
				"strength": char.get_stat("strength"),
				"constitution": char.get_stat("constitution"),
				"dexterity": char.get_stat("dexterity"),
				"intelligence": char.get_stat("intelligence"),
				"wisdom": char.get_stat("wisdom"),
				"wits": char.get_stat("wits"),
				"equipment_bonuses": bonuses,
				"equipped": char.equipped,
				"total_attack": char.get_total_attack(),
				"total_defense": char.get_total_defense(),
				"monsters_killed": char.monsters_killed,
				"in_combat": combat_mgr.is_in_combat(pid)
			})
			return

	send_to_peer(peer_id, {
		"type": "error",
		"message": "Player '%s' not found online" % target_name
	})

func handle_logout_character(peer_id: int):
	"""Logout of current character, return to character select"""
	if not peers[peer_id].authenticated:
		return

	# Save character before logout
	save_character(peer_id)

	# Remove from combat if needed
	if combat_mgr.is_in_combat(peer_id):
		combat_mgr.end_combat(peer_id, false)

	# Clear pending flock if any
	if pending_flocks.has(peer_id):
		pending_flocks.erase(peer_id)

	# Remove character from active characters
	if characters.has(peer_id):
		var char_name = characters[peer_id].name
		print("Character logout: %s" % char_name)
		characters.erase(peer_id)
		# Broadcast after removal
		broadcast_chat("[color=#FF0000]%s has left the realm.[/color]" % char_name)

	peers[peer_id].character_name = ""

	# Send acknowledgment and character list
	send_to_peer(peer_id, {
		"type": "logout_character_success",
		"message": "Logged out of character"
	})

	# Send updated character list
	handle_list_characters(peer_id)

func handle_logout_account(peer_id: int):
	"""Logout of account completely, return to login screen"""
	# Save character first if active
	save_character(peer_id)

	# Remove from combat if needed
	if combat_mgr.is_in_combat(peer_id):
		combat_mgr.end_combat(peer_id, false)

	# Clear pending flock if any
	if pending_flocks.has(peer_id):
		pending_flocks.erase(peer_id)

	# Remove character
	if characters.has(peer_id):
		var char_name = characters[peer_id].name
		print("Character logout: %s" % char_name)
		characters.erase(peer_id)
		# Broadcast after removal
		broadcast_chat("[color=#FF0000]%s has left the realm.[/color]" % char_name)

	var username = peers[peer_id].username
	print("Account logout: %s" % username)

	# Reset peer state
	peers[peer_id].authenticated = false
	peers[peer_id].account_id = ""
	peers[peer_id].username = ""
	peers[peer_id].character_name = ""

	# Send acknowledgment
	send_to_peer(peer_id, {
		"type": "logout_account_success",
		"message": "Logged out of account"
	})

# ===== GAME HANDLERS =====

func handle_chat(peer_id: int, message: Dictionary):
	if not peers[peer_id].authenticated:
		return

	var text = message.get("message", "")
	if text.is_empty():
		return

	var username = peers[peer_id].username
	print("Chat from %s: %s" % [username, text])

	# Broadcast to ALL peers EXCEPT the sender
	for other_peer_id in peers.keys():
		if peers[other_peer_id].authenticated and other_peer_id != peer_id:
			send_to_peer(other_peer_id, {
				"type": "chat",
				"sender": username,
				"message": text
			})

func handle_move(peer_id: int, message: Dictionary):
	if not characters.has(peer_id):
		return

	# Check if in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {
			"type": "error",
			"message": "You cannot move while in combat!"
		})
		return

	# Check if flock encounter pending
	if pending_flocks.has(peer_id):
		send_to_peer(peer_id, {
			"type": "error",
			"message": "More enemies are approaching! Press Space to continue."
		})
		return

	var direction = message.get("direction", 5)
	var character = characters[peer_id]

	# Get old position
	var old_x = character.x
	var old_y = character.y

	# Calculate new position
	var new_pos = world_system.move_player(old_x, old_y, direction)

	# Check for player collision (can't move onto another player's space)
	if is_player_at(new_pos.x, new_pos.y, peer_id):
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Another player is blocking that path!"
		})
		return

	character.x = new_pos.x
	character.y = new_pos.y

	# Regenerate health and resources on movement (small amount per step)
	var regen_percent = 0.02  # 2% per move for resources
	var hp_regen_percent = 0.01  # 1% per move for health
	character.current_hp = min(character.get_total_max_hp(), character.current_hp + max(1, int(character.get_total_max_hp() * hp_regen_percent)))
	character.current_mana = min(character.max_mana, character.current_mana + int(character.max_mana * regen_percent))
	character.current_stamina = min(character.max_stamina, character.current_stamina + int(character.max_stamina * regen_percent))
	character.current_energy = min(character.max_energy, character.current_energy + int(character.max_energy * regen_percent))

	# Tick poison on movement (counts as a round)
	if character.poison_active:
		var poison_dmg = character.tick_poison()
		if poison_dmg > 0:
			character.current_hp -= poison_dmg
			character.current_hp = max(1, character.current_hp)  # Poison can't kill
			var turns_left = character.poison_turns_remaining
			var poison_msg = "[color=#00FF00]Poison[/color] deals [color=#FF4444]%d damage[/color]" % poison_dmg
			if turns_left > 0:
				poison_msg += " (%d rounds remaining)" % turns_left
			else:
				poison_msg += " - [color=#00FF00]Poison has worn off![/color]"
			send_to_peer(peer_id, {
				"type": "status_effect",
				"effect": "poison",
				"message": poison_msg,
				"damage": poison_dmg,
				"turns_remaining": turns_left
			})

	# Tick active buffs on movement (for any non-combat buffs)
	if not character.active_buffs.is_empty():
		var expired = character.tick_buffs()
		for buff in expired:
			send_to_peer(peer_id, {
				"type": "status_effect",
				"effect": "buff_expired",
				"message": "[color=#808080]%s buff has worn off.[/color]" % buff.type
			})

	# Send location and character updates
	send_location_update(peer_id)
	send_character_update(peer_id)

	# Notify nearby players of the movement (so they see us on their map)
	send_nearby_players_map_update(peer_id, old_x, old_y)

	# Check for Trading Post first (safe zone with services)
	if world_system.is_trading_post_tile(new_pos.x, new_pos.y):
		# Check exploration quest progress
		check_exploration_quest_progress(peer_id, new_pos.x, new_pos.y)

		# Auto-trigger Trading Post encounter if entering
		if not at_trading_post.has(peer_id):
			trigger_trading_post_encounter(peer_id)
		return  # No other encounters in Trading Posts

	# Leaving Trading Post
	if at_trading_post.has(peer_id):
		at_trading_post.erase(peer_id)
		send_to_peer(peer_id, {"type": "trading_post_end"})

	# Check for merchant first
	if world_system.check_merchant_encounter(new_pos.x, new_pos.y):
		trigger_merchant_encounter(peer_id)
	# Check for monster encounter (only if no merchant)
	elif world_system.check_encounter(new_pos.x, new_pos.y):
		trigger_encounter(peer_id)

func handle_hunt(peer_id: int):
	"""Handle hunt action - actively search for monsters with increased encounter chance"""
	if not characters.has(peer_id):
		return

	# Check if in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot hunt while in combat!"})
		return

	# Check if flock encounter pending
	if pending_flocks.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "More enemies are approaching! Press Space to continue."})
		return

	var character = characters[peer_id]

	# Tick poison on hunt (counts as a round)
	if character.poison_active:
		var poison_dmg = character.tick_poison()
		if poison_dmg > 0:
			character.current_hp -= poison_dmg
			character.current_hp = max(1, character.current_hp)  # Poison can't kill
			var turns_left = character.poison_turns_remaining
			var poison_msg = "[color=#00FF00]Poison[/color] deals [color=#FF4444]%d damage[/color]" % poison_dmg
			if turns_left > 0:
				poison_msg += " (%d rounds remaining)" % turns_left
			else:
				poison_msg += " - [color=#00FF00]Poison has worn off![/color]"
			send_to_peer(peer_id, {
				"type": "status_effect",
				"effect": "poison",
				"message": poison_msg,
				"damage": poison_dmg,
				"turns_remaining": turns_left
			})
			send_character_update(peer_id)

	# Tick active buffs on hunt (for any non-combat buffs)
	if not character.active_buffs.is_empty():
		var expired = character.tick_buffs()
		for buff in expired:
			send_to_peer(peer_id, {
				"type": "status_effect",
				"effect": "buff_expired",
				"message": "[color=#808080]%s buff has worn off.[/color]" % buff.type
			})
		if not expired.is_empty():
			send_character_update(peer_id)

	# Check if in safe zone (can't hunt there)
	var terrain = world_system.get_terrain_at(character.x, character.y)
	var terrain_info = world_system.get_terrain_info(terrain)
	if terrain_info.safe:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]This is a safe area. No monsters can be found here.[/color]",
			"clear_output": true
		})
		send_location_update(peer_id)
		return

	# Hunt has 60% base encounter chance (vs normal ~15-25%)
	var hunt_roll = randi() % 100
	var hunt_chance = 60

	# Bonus chance based on location danger (hotspots)
	var hotspot_info = world_system.get_hotspot_at(character.x, character.y)
	if hotspot_info.in_hotspot:
		hunt_chance += 20  # 80% in hotspots

	if hunt_roll < hunt_chance:
		trigger_encounter(peer_id)
	else:
		# Don't send location update - player hasn't moved, keep the message visible
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]You search the area but are unable to locate any monsters.[/color]",
			"clear_output": true
		})

func handle_rest(peer_id: int):
	"""Handle rest action to restore HP"""
	if not characters.has(peer_id):
		return

	# Can't rest in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {
			"type": "error",
			"message": "You cannot rest while in combat!"
		})
		return

	var character = characters[peer_id]

	# Already at full HP
	if character.current_hp >= character.get_total_max_hp():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]You are already at full health.[/color]",
			"clear_output": true
		})
		return

	# Restore 10-25% of max HP
	var heal_percent = randf_range(0.10, 0.25)
	var heal_amount = int(character.get_total_max_hp() * heal_percent)
	heal_amount = max(1, heal_amount)  # At least 1 HP

	character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)

	# Regenerate primary resource on rest (same as movement - 2%)
	var regen_percent = 0.02
	var mana_regen = int(character.max_mana * regen_percent)
	var stamina_regen = int(character.max_stamina * regen_percent)
	var energy_regen = int(character.max_energy * regen_percent)
	character.current_mana = min(character.max_mana, character.current_mana + mana_regen)
	character.current_stamina = min(character.max_stamina, character.current_stamina + stamina_regen)
	character.current_energy = min(character.max_energy, character.current_energy + energy_regen)

	# Build rest message with resource info
	var rest_msg = "[color=#00FF00]You rest and recover %d HP" % heal_amount

	# Show resource regen based on class path
	var class_type = character.class_type
	if class_type in ["Fighter", "Barbarian", "Paladin"] and stamina_regen > 0:
		rest_msg += " and %d Stamina" % stamina_regen
	elif class_type in ["Wizard", "Sorcerer", "Sage"] and mana_regen > 0:
		rest_msg += " and %d Mana" % mana_regen
	elif class_type in ["Thief", "Ranger", "Ninja"] and energy_regen > 0:
		rest_msg += " and %d Energy" % energy_regen
	rest_msg += ".[/color]"

	send_to_peer(peer_id, {
		"type": "text",
		"message": rest_msg,
		"clear_output": true
	})

	# Send updated character data
	send_to_peer(peer_id, {
		"type": "character_update",
		"character": character.to_dict()
	})

	# Chance to be ambushed while resting (15%)
	var ambush_roll = randi() % 100
	if ambush_roll < 15:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]You are ambushed while resting![/color]"
		})
		trigger_encounter(peer_id)

func handle_combat_command(peer_id: int, message: Dictionary):
	"""Handle combat commands from player"""
	var command = message.get("command", "")

	if command.is_empty():
		return

	# Process combat action
	var result = combat_mgr.process_combat_command(peer_id, command)

	if not result.success:
		# Send all error messages
		for msg in result.get("messages", []):
			send_combat_message(peer_id, msg)
		return

	# Send all combat messages
	for msg in result.messages:
		send_combat_message(peer_id, msg)

	# If Analyze revealed enemy HP, send that to update the health bar
	if result.has("revealed_enemy_hp"):
		send_to_peer(peer_id, {
			"type": "enemy_hp_revealed",
			"max_hp": result.revealed_enemy_hp,
			"current_hp": result.get("revealed_enemy_current_hp", result.revealed_enemy_hp)
		})

	# If combat ended
	if result.has("combat_ended") and result.combat_ended:
		if result.has("victory") and result.victory:
			# Victory - increment monster kill count
			characters[peer_id].monsters_killed += 1

			# Check quest progress for kill-based quests
			var monster_level_for_quest = result.get("monster_level", 1)
			check_kill_quest_progress(peer_id, monster_level_for_quest)

			# Get current drops
			var current_drops = result.get("dropped_items", [])

			# Check for summoner ability - force a follow-up encounter
			var summon_next = result.get("summon_next_fight", "")
			if summon_next != "":
				# Summoner called reinforcements - force a flock encounter
				var monster_level = result.get("monster_level", 1)
				# Store drops for later (current_drops already defined above)
				if not pending_flock_drops.has(peer_id):
					pending_flock_drops[peer_id] = []
				pending_flock_drops[peer_id].append_array(current_drops)

				# Store gems
				var gems_this_combat = result.get("gems_earned", 0)
				if not pending_flock_gems.has(peer_id):
					pending_flock_gems[peer_id] = 0
				pending_flock_gems[peer_id] += gems_this_combat

				# Queue the summoned monster
				pending_flocks[peer_id] = {
					"monster_name": summon_next,
					"monster_level": monster_level
				}

				send_to_peer(peer_id, {
					"type": "combat_end",
					"victory": true,
					"character": characters[peer_id].to_dict(),
					"flock_incoming": true,
					"flock_monster": summon_next,
					"drops_pending": true,
					"summoned": true  # Flag to show different message
				})
				save_character(peer_id)
				return

			# Check for flock encounter (chain combat)
			var flock_chance = result.get("flock_chance", 0)
			var flock_roll = randi() % 100

			# Track gems earned this combat
			var gems_this_combat = result.get("gems_earned", 0)

			if flock_chance > 0 and flock_roll < flock_chance:
				# Flock triggered! Store drops for later, don't give items yet
				var monster_name = result.get("monster_name", "")
				var monster_level = result.get("monster_level", 1)

				# Accumulate drops for this flock
				if not pending_flock_drops.has(peer_id):
					pending_flock_drops[peer_id] = []
				pending_flock_drops[peer_id].append_array(current_drops)

				# Accumulate gems for this flock
				if not pending_flock_gems.has(peer_id):
					pending_flock_gems[peer_id] = 0
				pending_flock_gems[peer_id] += gems_this_combat

				# Store pending flock data for this peer (including analyze bonus carry-over)
				pending_flocks[peer_id] = {
					"monster_name": monster_name,
					"monster_level": monster_level,
					"analyze_bonus": combat_mgr.get_analyze_bonus(peer_id)
				}

				send_to_peer(peer_id, {
					"type": "combat_end",
					"victory": true,
					"character": characters[peer_id].to_dict(),
					"flock_incoming": true,
					"flock_monster": monster_name,
					"drops_pending": true  # Indicate drops will come later
				})

				# Save character
				save_character(peer_id)
			else:
				# Flock ended or no flock - collect all accumulated drops
				var all_drops = []
				if pending_flock_drops.has(peer_id):
					all_drops = pending_flock_drops[peer_id]
					pending_flock_drops.erase(peer_id)
				all_drops.append_array(current_drops)

				# Collect total gems from flock
				var total_gems = gems_this_combat
				if pending_flock_gems.has(peer_id):
					total_gems += pending_flock_gems[peer_id]
					pending_flock_gems.erase(peer_id)

				# Give all drops to player now
				var drop_messages = []
				var drop_data = []  # For client sound effects
				var player_level = characters[peer_id].level
				for item in all_drops:
					if characters[peer_id].can_add_item():
						characters[peer_id].add_item(item)
						drop_messages.append("[color=%s]Received: %s[/color]" % [
							_get_rarity_color(item.get("rarity", "common")),
							item.get("name", "Unknown Item")
						])
						# Track rarity and level for sound effects
						drop_data.append({
							"rarity": item.get("rarity", "common"),
							"level": item.get("level", 1),
							"level_diff": item.get("level", 1) - player_level
						})

					# Check if wish granter gave pending wish choice
				var combat_state = combat_mgr.get_active_combat(peer_id)
				var wish_pending = combat_state.get("wish_pending", false) if combat_state else false
				var wish_options = combat_state.get("wish_options", []) if combat_state else []

				if wish_pending and wish_options.size() > 0:
					# Send wish choice to client
					send_to_peer(peer_id, {
						"type": "wish_choice",
						"options": wish_options,
						"character": characters[peer_id].to_dict(),
						"flock_drops": drop_messages,
						"total_gems": total_gems,
						"drop_data": drop_data
					})
				else:
					send_to_peer(peer_id, {
						"type": "combat_end",
						"victory": true,
						"character": characters[peer_id].to_dict(),
						"flock_drops": drop_messages,  # Send all drop messages at once
						"total_gems": total_gems,       # Total gems earned for sound
						"drop_data": drop_data          # Item data for sound effects
					})

				# Save character after combat and notify of expired buffs
				save_character(peer_id)
				send_buff_expiration_notifications(peer_id)

		elif result.has("fled") and result.fled:
			# Fled successfully - lose any pending flock drops and gems
			if pending_flock_drops.has(peer_id):
				pending_flock_drops.erase(peer_id)
			if pending_flock_gems.has(peer_id):
				pending_flock_gems.erase(peer_id)

			# Move character to an adjacent empty tile (no encounter triggered)
			var flee_pos = _find_flee_destination(peer_id)
			if flee_pos != null:
				characters[peer_id].x = flee_pos.x
				characters[peer_id].y = flee_pos.y
				save_character(peer_id)

			send_to_peer(peer_id, {
				"type": "combat_end",
				"fled": true,
				"new_x": characters[peer_id].x,
				"new_y": characters[peer_id].y
			})
		elif result.get("monster_fled", false):
			# Monster fled (coward ability) - combat ends, no loot
			if pending_flock_drops.has(peer_id):
				pending_flock_drops.erase(peer_id)
			if pending_flock_gems.has(peer_id):
				pending_flock_gems.erase(peer_id)
			send_to_peer(peer_id, {
				"type": "combat_end",
				"monster_fled": true,
				"character": characters[peer_id].to_dict()
			})
			save_character(peer_id)
		else:
			# Defeated - PERMADEATH! Clear any pending drops and gems
			if pending_flock_drops.has(peer_id):
				pending_flock_drops.erase(peer_id)
			if pending_flock_gems.has(peer_id):
				pending_flock_gems.erase(peer_id)
			handle_permadeath(peer_id, result.get("monster_name", "Unknown"))
	else:
		# Combat continues - send updated state
		send_to_peer(peer_id, {
			"type": "combat_update",
			"combat_state": combat_mgr.get_combat_display(peer_id)
		})

func handle_combat_use_item(peer_id: int, message: Dictionary):
	"""Handle using an item during combat"""
	var item_index = message.get("index", -1)

	if item_index < 0:
		send_to_peer(peer_id, {"type": "error", "message": "Invalid item!"})
		return

	var result = combat_mgr.process_use_item(peer_id, item_index)

	if not result.success:
		send_to_peer(peer_id, {"type": "error", "message": result.message})
		return

	# Send all combat messages
	for msg in result.messages:
		send_combat_message(peer_id, msg)

	# Check if combat ended (player died)
	if result.has("combat_ended") and result.combat_ended:
		if not result.get("victory", false):
			# Player died after using item
			if pending_flock_drops.has(peer_id):
				pending_flock_drops.erase(peer_id)
			if pending_flock_gems.has(peer_id):
				pending_flock_gems.erase(peer_id)
			handle_permadeath(peer_id, result.get("monster_name", "Unknown"))
	else:
		# Combat continues - send updated state
		send_to_peer(peer_id, {
			"type": "combat_update",
			"combat_state": combat_mgr.get_combat_display(peer_id)
		})
		# Also send character update for HP/inventory changes
		send_character_update(peer_id)

func handle_wish_select(peer_id: int, message: Dictionary):
	"""Handle player selecting a wish reward from a Wish Granter monster"""
	if not characters.has(peer_id):
		return

	var choice_index = message.get("choice", -1)
	var combat_state = combat_mgr.get_active_combat(peer_id)

	if not combat_state.get("wish_pending", false):
		send_to_peer(peer_id, {"type": "error", "message": "No wish pending!"})
		return

	var wish_options = combat_state.get("wish_options", [])
	if choice_index < 0 or choice_index >= wish_options.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid wish choice!"})
		return

	var chosen_wish = wish_options[choice_index]
	var character = characters[peer_id]

	# Apply the wish
	var result_msg = combat_mgr.apply_wish_choice(character, chosen_wish)

	# If gear was chosen, generate and give the item
	if chosen_wish.type == "gear":
		var gear_item = _generate_wish_gear(chosen_wish)
		if character.can_add_item():
			character.add_item(gear_item)
			result_msg += "\n[color=%s]Received: %s[/color]" % [
				_get_rarity_color(gear_item.get("rarity", "common")),
				gear_item.get("name", "Unknown Item")
			]
		else:
			result_msg += "\n[color=#FF0000]Inventory full! Gear was lost![/color]"

	# Clear wish pending state
	combat_state["wish_pending"] = false
	combat_state["wish_options"] = []

	# End combat now
	combat_mgr.end_combat(peer_id, true)

	# Send result to client
	send_to_peer(peer_id, {
		"type": "wish_granted",
		"message": result_msg,
		"character": character.to_dict()
	})

	save_character(peer_id)
	send_buff_expiration_notifications(peer_id)

func _generate_wish_gear(wish: Dictionary) -> Dictionary:
	"""Generate a gear item from a wish choice"""
	var gear_level = wish.get("level", 10)
	var rarity = wish.get("rarity", "rare")

	# Pick random equipment type
	var types = ["weapon_enchanted", "armor_enchanted", "shield_enchanted", "helm_enchanted", "boots_enchanted"]
	var item_type = types[randi() % types.size()]

	return drop_tables._generate_item({"item_type": item_type, "rarity": rarity}, gear_level)

func _find_flee_destination(peer_id: int):
	"""Find an adjacent tile without another player for flee movement"""
	if not characters.has(peer_id):
		return null

	var character = characters[peer_id]
	var current_x = character.x
	var current_y = character.y

	# Get all occupied positions
	var occupied = {}
	for pid in characters:
		if pid != peer_id:
			var other = characters[pid]
			occupied[Vector2i(other.x, other.y)] = true

	# Direction offsets: N, S, E, W, NE, NW, SE, SW
	var directions = [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	directions.shuffle()  # Randomize flee direction

	for dir in directions:
		var new_pos = Vector2i(current_x + dir.x, current_y + dir.y)
		# Check if not occupied by another player
		if not occupied.has(new_pos):
			# Check world bounds (-1000 to 1000)
			if new_pos.x >= -1000 and new_pos.x <= 1000 and new_pos.y >= -1000 and new_pos.y <= 1000:
				return {"x": new_pos.x, "y": new_pos.y}

	return null  # No valid flee destination (very rare)

# ===== PERMADEATH =====

func handle_permadeath(peer_id: int, cause_of_death: String):
	"""Handle character death - add to leaderboard and delete"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var account_id = peers[peer_id].account_id
	var username = peers[peer_id].username

	print("PERMADEATH: %s (Level %d) killed by %s" % [character.name, character.level, cause_of_death])

	# Add to leaderboard
	var rank = persistence.add_to_leaderboard(character, cause_of_death, username)

	# Broadcast top 5 achievement to all connected players
	if rank <= 5:
		for pid in peers.keys():
			send_to_peer(pid, {
				"type": "leaderboard_top5",
				"character_name": character.name,
				"level": character.level,
				"rank": rank
			})

	# Send permadeath message to the player who died
	send_to_peer(peer_id, {
		"type": "permadeath",
		"character_name": character.name,
		"level": character.level,
		"experience": character.experience,
		"cause_of_death": cause_of_death,
		"leaderboard_rank": rank,
		"message": "[color=#FF0000]%s has fallen! Slain by %s.[/color]" % [character.name, cause_of_death]
	})

	# Broadcast death announcement to ALL connected players (including those on character select)
	var death_message = "[color=#FF4444]%s (Level %d) has fallen to %s![/color]" % [character.name, character.level, cause_of_death]
	for pid in peers.keys():
		send_to_peer(pid, {
			"type": "chat",
			"sender": "World",
			"message": death_message
		})

	# Delete character from persistence
	persistence.delete_character(account_id, character.name)

	# Remove from active characters
	characters.erase(peer_id)
	peers[peer_id].character_name = ""

	# Broadcast updated player list to all online players
	broadcast_player_list()

	# Send updated character list so they can choose another or create new
	handle_list_characters(peer_id)

# ===== UTILITY FUNCTIONS =====

func send_location_update(peer_id: int):
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get nearby players for map display (within map radius of 6)
	var nearby_players = get_nearby_players(peer_id, 6)

	# Get complete map display (includes location info at top)
	var map_display = world_system.generate_map_display(character.x, character.y, 6, nearby_players)

	# Send map display as description
	send_to_peer(peer_id, {
		"type": "location",
		"x": character.x,
		"y": character.y,
		"description": map_display
	})

	# Forward location/map to watchers
	if watchers.has(peer_id) and not watchers[peer_id].is_empty():
		for watcher_id in watchers[peer_id]:
			send_to_peer(watcher_id, {
				"type": "watch_location",
				"x": character.x,
				"y": character.y,
				"description": map_display
			})

func get_nearby_players(peer_id: int, radius: int = 7) -> Array:
	"""Get list of other players within radius of the given peer's character."""
	var result = []
	if not characters.has(peer_id):
		return result

	var character = characters[peer_id]
	var my_x = character.x
	var my_y = character.y

	for other_peer_id in characters.keys():
		if other_peer_id == peer_id:
			continue  # Skip self

		var other_char = characters[other_peer_id]
		var dx = abs(other_char.x - my_x)
		var dy = abs(other_char.y - my_y)

		# Check if within map view radius
		if dx <= radius and dy <= radius:
			result.append({
				"x": other_char.x,
				"y": other_char.y,
				"name": other_char.name,
				"level": other_char.level
			})

	return result

func is_player_at(x: int, y: int, exclude_peer_id: int = -1) -> bool:
	"""Check if any player (other than excluded peer) is at the given coordinates."""
	for other_peer_id in characters.keys():
		if other_peer_id == exclude_peer_id:
			continue  # Skip excluded peer
		var other_char = characters[other_peer_id]
		if other_char.x == x and other_char.y == y:
			return true
	return false

func send_nearby_players_map_update(peer_id: int, old_x: int, old_y: int, radius: int = 6):
	"""Send map updates to players who could see this player move."""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var new_x = character.x
	var new_y = character.y

	for other_peer_id in characters.keys():
		if other_peer_id == peer_id:
			continue  # Skip self

		var other_char = characters[other_peer_id]

		# Check if other player could see either old or new position
		var saw_old = abs(other_char.x - old_x) <= radius and abs(other_char.y - old_y) <= radius
		var sees_new = abs(other_char.x - new_x) <= radius and abs(other_char.y - new_y) <= radius

		# Send update if they could see the movement
		if saw_old or sees_new:
			send_location_update(other_peer_id)

func send_merchant_movement_updates():
	"""Send map updates to players when merchants move in/out of their visible area.
	Only sends to players who are in movement mode (not in combat, menus, etc.)"""
	var map_radius = 6  # Same radius as normal map display

	# For each active player in movement mode
	for peer_id in characters.keys():
		# Skip players in combat
		if combat_mgr.is_in_combat(peer_id):
			continue

		# Skip players at merchant or trading post (in menu)
		if at_merchant.has(peer_id) or at_trading_post.has(peer_id):
			continue

		var character = characters[peer_id]
		var player_key = "p_%d" % peer_id

		# Get merchants visible to this player using the public API
		var nearby_merchants = world_system.get_merchants_near(character.x, character.y, map_radius)

		# Build sorted list of position keys for comparison
		var visible_merchants: Array = []
		for merchant in nearby_merchants:
			visible_merchants.append("%d,%d" % [merchant.x, merchant.y])
		visible_merchants.sort()

		# Check if visible merchants changed since last update
		var last_visible = last_merchant_cache_positions.get(player_key, [])

		# Compare arrays - if different, send map update
		var changed = false
		if visible_merchants.size() != last_visible.size():
			changed = true
		else:
			for i in range(visible_merchants.size()):
				if visible_merchants[i] != last_visible[i]:
					changed = true
					break

		if changed:
			# Store new visible merchants
			last_merchant_cache_positions[player_key] = visible_merchants.duplicate()
			# Send map-only update (location type doesn't affect GameOutput)
			send_location_update(peer_id)

func send_to_peer(peer_id: int, data: Dictionary):
	if not peers.has(peer_id):
		return

	var connection = peers[peer_id].connection
	if connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	var json_str = JSON.stringify(data) + "\n"
	var bytes = json_str.to_utf8_buffer()

	connection.put_data(bytes)

func broadcast_chat(message: String, sender: String = "System"):
	"""Send a chat message to all connected players with characters"""
	for peer_id in characters.keys():
		send_to_peer(peer_id, {
			"type": "chat",
			"sender": sender,
			"message": message
		})

func broadcast_player_list():
	"""Send updated player list to all connected players"""
	var player_list = []
	for pid in characters.keys():
		var char = characters[pid]
		player_list.append({
			"name": char.name,
			"level": char.level,
			"class": char.class_type
		})

	for peer_id in characters.keys():
		send_to_peer(peer_id, {
			"type": "player_list",
			"players": player_list,
			"count": player_list.size()
		})

func send_buff_expiration_notifications(peer_id: int):
	"""Send notifications for any persistent buffs that expired after combat."""
	var expired = combat_mgr.get_expired_persistent_buffs(peer_id)
	for buff in expired:
		var buff_name = buff.type.capitalize()
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]Your %s buff has worn off. (%d battles)[/color]" % [buff_name, 0]
		})

func save_character(peer_id: int):
	"""Save a single character"""
	if not characters.has(peer_id):
		return
	if not peers.has(peer_id):
		return

	var account_id = peers[peer_id].account_id
	if account_id.is_empty():
		return

	persistence.save_character(account_id, characters[peer_id])

func save_all_active_characters():
	"""Save all currently active characters (called by auto-save timer)"""
	for peer_id in characters.keys():
		save_character(peer_id)

func handle_disconnect(peer_id: int):
	if not peers.has(peer_id):
		return

	var peer_data = peers[peer_id]
	var username = peer_data.get("username", "Unknown")
	var peer_ip = peer_data.get("ip", "")
	var char_name = ""
	if characters.has(peer_id):
		char_name = characters[peer_id].name

	# Decrement IP connection count
	if peer_ip != "" and ip_connection_counts.has(peer_ip):
		ip_connection_counts[peer_ip] = max(0, ip_connection_counts[peer_ip] - 1)
		if ip_connection_counts[peer_ip] == 0:
			ip_connection_counts.erase(peer_ip)

	log_message("Peer %d (%s) disconnected" % [peer_id, username])

	# Save character before removing
	save_character(peer_id)

	# Remove from combat if needed
	if combat_mgr.is_in_combat(peer_id):
		combat_mgr.end_combat(peer_id, false)

	# Clear pending flock if any
	if pending_flocks.has(peer_id):
		pending_flocks.erase(peer_id)

	# Clean up merchant position tracking
	var player_key = "p_%d" % peer_id
	if last_merchant_cache_positions.has(player_key):
		last_merchant_cache_positions.erase(player_key)

	# Clean up watch relationships before erasing character
	cleanup_watcher_on_disconnect(peer_id)

	if characters.has(peer_id):
		characters.erase(peer_id)

	peers.erase(peer_id)

	# Update UI
	update_player_list()

	# Broadcast disconnect message (after cleanup so they don't get their own message)
	if char_name != "":
		broadcast_chat("[color=#FF0000]%s has left the realm.[/color]" % char_name)

func _check_stale_connections():
	"""Kick connections that haven't authenticated within AUTH_TIMEOUT seconds"""
	var current_time = Time.get_unix_time_from_system()
	var stale_peers = []

	for peer_id in peers.keys():
		var peer_data = peers[peer_id]
		# Skip authenticated connections
		if peer_data.get("authenticated", false):
			continue

		var connect_time = peer_data.get("connect_time", current_time)
		if current_time - connect_time > AUTH_TIMEOUT:
			var peer_ip = peer_data.get("ip", "unknown")
			log_message("Security: Kicking unauthenticated connection %d from %s (timeout)" % [peer_id, peer_ip])
			stale_peers.append(peer_id)

	# Disconnect stale peers
	for peer_id in stale_peers:
		if peers.has(peer_id):
			var connection = peers[peer_id].connection
			if connection:
				connection.disconnect_from_host()
			handle_disconnect(peer_id)

func _exit_tree():
	print("Server shutting down...")
	# Save all characters before exit
	save_all_active_characters()
	server.stop()

func trigger_encounter(peer_id: int):
	"""Trigger a random encounter - usually monster, but rarely loot or legendary adventurer"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get monster level range for this location (indicates danger level)
	var level_range = world_system.get_monster_level_range(character.x, character.y)
	var area_level = (level_range.min + level_range.max) / 2

	# Roll for rare encounters (checked before normal combat)
	var rare_roll = randi() % 1000  # 0-999 for finer control

	# 1% chance (10/1000) for legendary adventurer training
	if rare_roll < 10:
		trigger_legendary_adventurer(peer_id, character, area_level)
		return

	# 3% chance (30/1000) for loot find
	if rare_roll < 40:  # 10-39 = 30/1000
		trigger_loot_find(peer_id, character, area_level)
		return

	# Check for forced next monster (from Monster Selection Scroll)
	var monster: Dictionary
	if character.forced_next_monster != "":
		# Generate the forced monster at the area's level
		monster = monster_db.generate_monster_by_name(character.forced_next_monster, area_level)
		# Clear the forced monster after use
		character.forced_next_monster = ""
		save_character(peer_id)
	else:
		# Normal random monster encounter
		monster = monster_db.generate_monster(level_range.min, level_range.max)

	# Apply pending monster debuffs from scrolls
	var debuff_messages = []
	if character.pending_monster_debuffs.size() > 0:
		for debuff in character.pending_monster_debuffs:
			var debuff_type = debuff.get("type", "")
			var debuff_value = debuff.get("value", 0)
			var reduction = float(debuff_value) / 100.0

			match debuff_type:
				"weakness":
					monster.strength = max(1, int(monster.strength * (1.0 - reduction)))
					debuff_messages.append("[color=#FF00FF]Weakness curse: -%d%% attack![/color]" % debuff_value)
				"vulnerability":
					monster.defense = max(0, int(monster.defense * (1.0 - reduction)))
					debuff_messages.append("[color=#FF00FF]Vulnerability curse: -%d%% defense![/color]" % debuff_value)
				"slow":
					monster["speed"] = max(1, int(monster.get("speed", 10) * (1.0 - reduction)))
					debuff_messages.append("[color=#FF00FF]Slow curse: -%d%% speed![/color]" % debuff_value)
				"doom":
					var hp_loss = int(monster.max_hp * reduction)
					monster.max_hp = max(1, monster.max_hp - hp_loss)
					monster.current_hp = min(monster.current_hp, monster.max_hp)
					debuff_messages.append("[color=#FF00FF]Doom curse: -%d HP![/color]" % hp_loss)

		# Clear the pending debuffs after applying
		character.pending_monster_debuffs.clear()
		save_character(peer_id)

	var result = combat_mgr.start_combat(peer_id, character, monster)

	if result.success:
		# Get monster's combat background color
		var monster_name = result.combat_state.get("monster_name", "")
		var combat_bg_color = combat_mgr.get_monster_combat_bg_color(monster_name)

		# Prepend debuff messages if any were applied
		var full_message = result.message
		if debuff_messages.size() > 0:
			full_message = "\n".join(debuff_messages) + "\n\n" + result.message

		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": full_message,
			"combat_state": result.combat_state,
			"combat_bg_color": combat_bg_color
		})
		# Forward encounter to watchers
		forward_to_watchers(peer_id, result.message)

func trigger_loot_find(peer_id: int, character: Character, area_level: int):
	"""Trigger a rare loot find instead of combat"""
	# Generate loot scaled to area difficulty
	var loot_tier = "common"
	if area_level >= 5000:
		loot_tier = "legendary"
	elif area_level >= 2000:
		loot_tier = "epic"
	elif area_level >= 500:
		loot_tier = "rare"
	elif area_level >= 100:
		loot_tier = "uncommon"

	# Roll for item using drop tables
	var items = drop_tables.roll_drops(loot_tier, 100, area_level)  # 100% drop chance

	if items.is_empty():
		# Fallback to gold
		var gold_amount = max(10, area_level * (randi() % 10 + 5))
		character.gold += gold_amount
		# Pad gold text to fit in box (34 chars inner width)
		var gold_text = "Found %d gold!" % gold_amount
		if gold_text.length() < 34:
			gold_text = gold_text + " ".repeat(34 - gold_text.length())
		var msg = "[color=#FFD700]╔════════════════════════════════════╗[/color]\n"
		msg += "[color=#FFD700]║[/color]       [color=#00FF00]✦ LUCKY FIND! ✦[/color]       [color=#FFD700]║[/color]\n"
		msg += "[color=#FFD700]╠════════════════════════════════════╣[/color]\n"
		msg += "[color=#FFD700]║[/color] You discover a hidden cache!      [color=#FFD700]║[/color]\n"
		msg += "[color=#FFD700]║[/color] [color=#FFD700]%s[/color] [color=#FFD700]║[/color]\n" % gold_text
		msg += "[color=#FFD700]╚════════════════════════════════════╝[/color]"
		send_to_peer(peer_id, {
			"type": "text",
			"message": msg,
			"clear_output": true
		})
	else:
		# Add items to inventory
		var item = items[0]
		character.add_item(item)
		var rarity_color = _get_rarity_color(item.get("rarity", "common"))
		var item_name = item.get("name", "Unknown Item")
		# Pad item name to fit in box (34 chars inner width)
		var padded_name = item_name
		if padded_name.length() < 34:
			padded_name = padded_name + " ".repeat(34 - padded_name.length())
		var msg = "[color=#FFD700]╔════════════════════════════════════╗[/color]\n"
		msg += "[color=#FFD700]║[/color]       [color=#00FF00]✦ LUCKY FIND! ✦[/color]       [color=#FFD700]║[/color]\n"
		msg += "[color=#FFD700]╠════════════════════════════════════╣[/color]\n"
		msg += "[color=#FFD700]║[/color] You discover something valuable!  [color=#FFD700]║[/color]\n"
		msg += "[color=#FFD700]║[/color] [color=%s]%s[/color] [color=#FFD700]║[/color]\n" % [rarity_color, padded_name]
		msg += "[color=#FFD700]╚════════════════════════════════════╝[/color]"
		send_to_peer(peer_id, {
			"type": "text",
			"message": msg,
			"clear_output": true
		})

	# Send updated character data
	send_character_update(peer_id)
	send_location_update(peer_id)
	persistence.save_character(character)

func trigger_legendary_adventurer(peer_id: int, character: Character, area_level: int):
	"""Trigger a legendary adventurer training encounter"""
	# Pick a random stat to train
	var stats = ["str", "con", "dex", "int", "wis", "wits"]
	var stat_names = {
		"str": "Strength",
		"con": "Constitution",
		"dex": "Dexterity",
		"int": "Intelligence",
		"wis": "Wisdom",
		"wits": "Wits"
	}
	var stat = stats[randi() % stats.size()]
	var stat_name = stat_names[stat]

	# Bonus scales with area difficulty (1-5 points)
	var bonus = max(1, min(5, area_level / 500 + 1))

	# Apply the bonus
	match stat:
		"str":
			character.strength += bonus
		"con":
			character.constitution += bonus
			character.update_derived_stats()
		"dex":
			character.dexterity += bonus
		"int":
			character.intelligence += bonus
			character.update_derived_stats()
		"wis":
			character.wisdom += bonus
			character.update_derived_stats()
		"wits":
			character.wits += bonus

	# Legendary adventurer names
	var adventurer_names = [
		"Gandrik the Wise",
		"Lady Seraphina",
		"Thorin Ironfoot",
		"Zephyr Shadowblade",
		"Magnus the Eternal",
		"Lyra Starweaver",
		"Orin Battleborn",
		"Celeste Moonwhisper"
	]
	var adventurer = adventurer_names[randi() % adventurer_names.size()]

	# Training descriptions
	var training_msgs = {
		"str": "teaches you ancient combat techniques",
		"con": "shares secrets of endurance and resilience",
		"dex": "demonstrates masterful footwork and reflexes",
		"int": "reveals arcane knowledge long forgotten",
		"wis": "imparts spiritual wisdom and insight",
		"wits": "shows you how to read your opponents"
	}

	var msg = "[color=#FFD700]╔════════════════════════════════════════╗[/color]\n"
	msg += "[color=#FFD700]║[/color]  [color=#FF69B4]✦ LEGENDARY ENCOUNTER ✦[/color]  [color=#FFD700]║[/color]\n"
	msg += "[color=#FFD700]╠════════════════════════════════════════╣[/color]\n"
	msg += "[color=#FFD700]║[/color] [color=#E6CC80]%s[/color] [color=#FFD700]║[/color]\n" % adventurer
	msg += "[color=#FFD700]║[/color] %s! [color=#FFD700]║[/color]\n" % training_msgs[stat]
	msg += "[color=#FFD700]╠════════════════════════════════════════╣[/color]\n"
	msg += "[color=#FFD700]║[/color] [color=#00FF00]+%d %s permanently![/color] [color=#FFD700]║[/color]\n" % [bonus, stat_name]
	msg += "[color=#FFD700]╚════════════════════════════════════════╝[/color]"

	send_to_peer(peer_id, {
		"type": "text",
		"message": msg,
		"clear_output": true
	})

	# Send updated character data
	send_character_update(peer_id)
	send_location_update(peer_id)
	persistence.save_character(character)
	log_message("Legendary training: %s gained +%d %s from %s" % [character.name, bonus, stat_name, adventurer])

func trigger_flock_encounter(peer_id: int, monster_name: String, monster_level: int, analyze_bonus: int = 0):
	"""Trigger a flock encounter with the same monster type"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Generate another monster of the same type at the same level
	var monster = monster_db.generate_monster_by_name(monster_name, monster_level)

	# Start combat
	var result = combat_mgr.start_combat(peer_id, character, monster)

	# Apply analyze bonus from previous combat (carry-over for flock chain)
	if analyze_bonus > 0:
		combat_mgr.set_analyze_bonus(peer_id, analyze_bonus)

	if result.success:
		var flock_msg = "[color=#FF4444]Another %s appears![/color]\n%s" % [monster.name, result.message]
		# Get monster's combat background color
		var combat_bg_color = combat_mgr.get_monster_combat_bg_color(monster.name)
		# Send flock encounter message with clear_output flag
		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": flock_msg,
			"combat_state": result.combat_state,
			"is_flock": true,
			"clear_output": true,
			"combat_bg_color": combat_bg_color
		})
		# Forward to watchers
		forward_to_watchers(peer_id, flock_msg)

func handle_continue_flock(peer_id: int):
	"""Handle player continuing into a flock encounter"""
	if not pending_flocks.has(peer_id):
		return

	var flock_data = pending_flocks[peer_id]
	pending_flocks.erase(peer_id)

	# Pass analyze bonus to carry over damage bonus from previous combat
	var analyze_bonus = flock_data.get("analyze_bonus", 0)
	trigger_flock_encounter(peer_id, flock_data.monster_name, flock_data.monster_level, analyze_bonus)

# ===== INVENTORY HANDLERS =====

func handle_inventory_use(peer_id: int, message: Dictionary):
	"""Handle using an item from inventory"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var index = message.get("index", -1)
	var inventory = character.inventory

	if index < 0 or index >= inventory.size():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid item index"
		})
		return

	var item = inventory[index]
	var item_type = item.get("type", "")
	var item_name = item.get("name", "item")
	var item_level = item.get("level", 1)

	# Get potion effect from drop tables
	var effect = drop_tables.get_potion_effect(item_type)

	if effect.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]This item cannot be used directly. Try equipping it.[/color]"
		})
		return

	# Remove from inventory first
	character.remove_item(index)

	# Apply effect
	if effect.has("heal"):
		# Healing potion
		var heal_amount = effect.base + (effect.per_level * item_level)
		var actual_heal = character.heal(heal_amount)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]You use %s and restore %d HP![/color]" % [item_name, actual_heal]
		})
	elif effect.has("mana"):
		# Mana potion
		var mana_amount = effect.base + (effect.per_level * item_level)
		var old_mana = character.current_mana
		character.current_mana = min(character.max_mana, character.current_mana + mana_amount)
		var actual_restore = character.current_mana - old_mana
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]You use %s and restore %d mana![/color]" % [item_name, actual_restore]
		})
	elif effect.has("stamina"):
		# Stamina potion
		var stamina_amount = effect.base + (effect.per_level * item_level)
		var old_stamina = character.current_stamina
		character.current_stamina = min(character.max_stamina, character.current_stamina + stamina_amount)
		var actual_restore = character.current_stamina - old_stamina
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFCC00]You use %s and restore %d stamina![/color]" % [item_name, actual_restore]
		})
	elif effect.has("energy"):
		# Energy potion
		var energy_amount = effect.base + (effect.per_level * item_level)
		var old_energy = character.current_energy
		character.current_energy = min(character.max_energy, character.current_energy + energy_amount)
		var actual_restore = character.current_energy - old_energy
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#66FF66]You use %s and restore %d energy![/color]" % [item_name, actual_restore]
		})
	elif effect.has("buff"):
		# Buff potion
		var buff_type = effect.buff
		var buff_value = effect.base + (effect.per_level * item_level)
		var base_duration = effect.get("base_duration", 5)
		var duration_per_10 = effect.get("duration_per_10_levels", 1)
		var duration = base_duration + (item_level / 10) * duration_per_10

		if effect.get("battles", false):
			# Battle-based buff
			character.add_persistent_buff(buff_type, buff_value, duration)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FFFF]You use %s! +%d %s for %d battles![/color]" % [item_name, buff_value, buff_type, duration]
			})
		else:
			# Round-based buff (only effective in combat)
			character.add_buff(buff_type, buff_value, duration)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FFFF]You use %s! +%d %s for %d rounds (in combat)![/color]" % [item_name, buff_value, buff_type, duration]
			})
	elif effect.has("gold"):
		# Gold pouch - grants variable gold based on level
		var base_gold = effect.base + (effect.per_level * item_level)
		var variance = effect.get("variance", 0.5)  # ±50% by default
		var min_gold = int(base_gold * (1.0 - variance))
		var max_gold = int(base_gold * (1.0 + variance))
		var gold_amount = randi_range(min_gold, max_gold)
		character.gold += gold_amount
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFD700]You open %s and find %d gold![/color]" % [item_name, gold_amount]
		})
	elif effect.has("monster_select"):
		# Monster Selection Scroll - let player pick next encounter
		# Get list of all monster names from monster database
		var monster_names = monster_db.get_all_monster_names()
		send_to_peer(peer_id, {
			"type": "monster_select_prompt",
			"monsters": monster_names,
			"message": "[color=#FF00FF]The %s glows with arcane power...[/color]\n[color=#FFD700]Choose a creature to summon for your next encounter![/color]" % item_name
		})
		# Don't update character yet - wait for confirmation
		return
	elif effect.has("monster_debuff"):
		# Debuff scroll - apply to next monster encountered
		var debuff_type = effect.monster_debuff
		var debuff_value = effect.base + (effect.per_level * item_level)
		character.pending_monster_debuffs.append({"type": debuff_type, "value": debuff_value})

		var debuff_messages = {
			"weakness": "Your next foe will strike with weakened blows! (-%d%% attack)" % debuff_value,
			"vulnerability": "Your next foe's defenses will crumble! (-%d%% defense)" % debuff_value,
			"slow": "Your next foe will be sluggish and slow! (-%d%% speed)" % debuff_value,
			"doom": "Your next foe is marked for death! (-%d%% max HP)" % debuff_value
		}
		var msg = debuff_messages.get(debuff_type, "A dark curse awaits your next foe...")
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF00FF]You use %s![/color]\n[color=#FFD700]%s[/color]" % [item_name, msg]
		})

	# Update character data
	send_character_update(peer_id)

func handle_monster_select_confirm(peer_id: int, message: Dictionary):
	"""Handle player selecting a monster from the scroll selection"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var monster_name = message.get("monster_name", "")

	if monster_name.is_empty():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid monster selection"
		})
		return

	# Verify this is a valid monster name
	var valid_names = monster_db.get_all_monster_names()
	if monster_name not in valid_names:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Unknown monster type"
		})
		return

	# Set the forced next monster on character
	character.forced_next_monster = monster_name

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF00FF]The scroll crumbles to dust as the summoning circle forms...[/color]\n[color=#FFD700]Your next encounter will be with: %s[/color]" % monster_name
	})

	save_character(peer_id)
	send_character_update(peer_id)

func handle_inventory_equip(peer_id: int, message: Dictionary):
	"""Handle equipping an item"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var index = message.get("index", -1)
	var inventory = character.inventory

	if index < 0 or index >= inventory.size():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid item index"
		})
		return

	var item = inventory[index]
	var item_type = item.get("type", "")

	# Determine slot based on item type
	var slot = ""
	if "weapon" in item_type:
		slot = "weapon"
	elif "armor" in item_type:
		slot = "armor"
	elif "helm" in item_type:
		slot = "helm"
	elif "shield" in item_type:
		slot = "shield"
	elif "boots" in item_type:
		slot = "boots"
	elif "ring" in item_type:
		slot = "ring"
	elif "amulet" in item_type:
		slot = "amulet"
	else:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF0000]This item cannot be equipped.[/color]"
		})
		return

	# Remove from inventory
	var equip_item = character.remove_item(index)

	# Equip and get old item
	var old_item = character.equip_item(equip_item, slot)

	# If there was an old item, add to inventory
	if old_item != null and old_item.has("name"):
		character.add_item(old_item)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]You equip %s and unequip %s.[/color]" % [equip_item.get("name", "item"), old_item.get("name", "item")]
		})
	else:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]You equip %s.[/color]" % equip_item.get("name", "item")
		})

	send_character_update(peer_id)

func handle_inventory_unequip(peer_id: int, message: Dictionary):
	"""Handle unequipping an item"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var slot = message.get("slot", "")

	if not character.equipped.has(slot):
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid equipment slot"
		})
		return

	if character.equipped[slot] == null:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]Nothing equipped in that slot.[/color]"
		})
		return

	# Check inventory space
	if not character.can_add_item():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Inventory is full!"
		})
		return

	# Unequip and add to inventory
	var item = character.unequip_slot(slot)
	character.add_item(item)

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FF00]You unequip %s.[/color]" % item.get("name", "item")
	})

	send_character_update(peer_id)

func handle_inventory_discard(peer_id: int, message: Dictionary):
	"""Handle discarding an item"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var index = message.get("index", -1)
	var inventory = character.inventory

	if index < 0 or index >= inventory.size():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid item index"
		})
		return

	var item = character.remove_item(index)

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF4444]You discard %s.[/color]" % item.get("name", "Unknown")
	})

	send_character_update(peer_id)

func send_character_update(peer_id: int):
	"""Send character data update to client"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var char_dict = character.to_dict()
	send_to_peer(peer_id, {
		"type": "character_update",
		"character": char_dict
	})

	# Forward character update to watchers
	if watchers.has(peer_id) and not watchers[peer_id].is_empty():
		for watcher_id in watchers[peer_id]:
			send_to_peer(watcher_id, {
				"type": "watch_character",
				"character": char_dict
			})

# ===== MERCHANT HANDLERS =====

func get_or_generate_merchant_inventory(merchant_id: String, player_level: int, seed_hash: int, specialty: String) -> Array:
	"""Get existing merchant inventory or generate new one if expired/missing.
	Inventory persists for 5 minutes before regenerating."""
	var current_time = Time.get_unix_time_from_system()

	# Check if we have valid cached inventory
	if merchant_inventories.has(merchant_id):
		var cached = merchant_inventories[merchant_id]
		var age = current_time - cached.generated_at

		# Return cached inventory if not expired and same player level tier
		# (regenerate if player level changed significantly to show level-appropriate items)
		var level_tier = player_level / 10
		var cached_tier = cached.player_level / 10
		if age < INVENTORY_REFRESH_INTERVAL and level_tier == cached_tier:
			return cached.items

	# Generate new inventory
	var items = generate_shop_inventory(player_level, seed_hash, specialty)
	merchant_inventories[merchant_id] = {
		"items": items,
		"generated_at": current_time,
		"player_level": player_level
	}
	return items

func trigger_merchant_encounter(peer_id: int):
	"""Trigger a merchant encounter for the player"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var merchant = world_system.get_merchant_at(character.x, character.y)

	if merchant.is_empty():
		return

	# Get or generate persistent shop inventory
	var merchant_id = merchant.get("id", "unknown")
	var shop_items = get_or_generate_merchant_inventory(
		merchant_id,
		character.level,
		merchant.get("hash", 0),
		merchant.get("specialty", "all")
	)
	merchant["shop_items"] = shop_items

	# Store merchant state
	at_merchant[peer_id] = merchant

	# Build services message
	var services_text = []
	if shop_items.size() > 0:
		var specialty_label = ""
		match merchant.get("specialty", "all"):
			"weapons":
				specialty_label = "weapons"
			"armor":
				specialty_label = "armor"
			"jewelry":
				specialty_label = "jewelry"
			_:
				specialty_label = "items"
		services_text.append("[R] Buy %s (%d available)" % [specialty_label, shop_items.size()])
	if "sell" in merchant.services:
		services_text.append("[Q] Sell items")
	if character.gems > 0:
		services_text.append("[1] Sell gems (%d @ 1000g each)" % character.gems)
	if "upgrade" in merchant.services:
		services_text.append("[W] Upgrade equipment")
	if "gamble" in merchant.services:
		services_text.append("[E] Gamble")
	services_text.append("[Space] Leave")

	# Build greeting with destination info
	var greeting = "[color=#FFD700]A %s approaches you![/color]\n" % merchant.name
	if merchant.has("destination") and merchant.destination != "":
		greeting += "[color=#808080]\"I'm headed to %s, then on to %s. Care to trade?\"[/color]\n\n" % [merchant.destination, merchant.get("next_destination", "parts unknown")]
	else:
		greeting += "\"Greetings, traveler! Care to do business?\"\n\n"

	send_to_peer(peer_id, {
		"type": "merchant_start",
		"merchant": merchant,
		"message": greeting + "\n".join(services_text)
	})

func handle_merchant_sell(peer_id: int, message: Dictionary):
	"""Handle selling an item to a merchant"""
	if not at_merchant.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a merchant!"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var index = message.get("index", -1)

	if index < 0 or index >= character.inventory.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid item index"})
		return

	var item = character.inventory[index]
	var sell_price = item.get("value", 10) / 2  # Sell for half value

	# Remove item and give gold
	character.remove_item(index)
	character.gold += sell_price

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]You sell %s for %d gold.[/color]" % [item.get("name", "Unknown"), sell_price]
	})

	send_character_update(peer_id)
	_send_merchant_inventory(peer_id)

func handle_merchant_sell_all(peer_id: int):
	"""Handle selling all inventory items to a merchant"""
	if not at_merchant.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a merchant!"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	if character.inventory.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "You have nothing to sell!"})
		return

	var total_gold = 0
	var item_count = character.inventory.size()

	# Calculate total value and clear inventory
	for item in character.inventory:
		var sell_price = item.get("value", 10) / 2  # Sell for half value
		total_gold += sell_price

	character.inventory.clear()
	character.gold += total_gold

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]You sell %d items for %d gold![/color]" % [item_count, total_gold]
	})

	send_character_update(peer_id)
	_send_merchant_inventory(peer_id)

func handle_merchant_sell_gems(peer_id: int, message: Dictionary):
	"""Handle selling gems to a merchant"""
	if not at_merchant.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a merchant!"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var amount = message.get("amount", 1)

	# Can't sell more than you have
	amount = mini(amount, character.gems)

	if amount <= 0:
		send_to_peer(peer_id, {"type": "error", "message": "You don't have any gems to sell!"})
		return

	# 1000 gold per gem
	var gold_value = amount * 1000

	character.gems -= amount
	character.gold += gold_value

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]You sell %d gem%s for %d gold![/color]" % [amount, "s" if amount > 1 else "", gold_value]
	})

	send_character_update(peer_id)

func handle_merchant_upgrade(peer_id: int, message: Dictionary):
	"""Handle upgrading an equipped item (supports multi-upgrade)"""
	if not at_merchant.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a merchant!"})
		return

	var merchant = at_merchant[peer_id]
	if not "upgrade" in merchant.services:
		send_to_peer(peer_id, {"type": "error", "message": "This merchant doesn't offer upgrades."})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var slot = message.get("slot", "")
	var count = message.get("count", 1)  # Number of upgrades to perform
	var use_gems = message.get("use_gems", false)  # Pay with gems instead of gold

	count = clampi(count, 1, 100)  # Limit to 100 upgrades at once

	if not slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		send_to_peer(peer_id, {"type": "error", "message": "Invalid equipment slot"})
		return

	var item = character.equipped.get(slot)
	if item == null:
		send_to_peer(peer_id, {"type": "error", "message": "Nothing equipped in that slot"})
		return

	# Calculate total upgrade cost for all requested upgrades
	var current_level = item.get("level", 1)
	var total_cost = 0
	for i in range(count):
		total_cost += int(pow(current_level + i + 1, 2) * 10)

	# Check if paying with gems
	if use_gems:
		var gem_cost = int(ceil(total_cost / 1000.0))
		if character.gems < gem_cost:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF4444]You need %d gems for %d upgrade%s. You have %d gems.[/color]" % [gem_cost, count, "s" if count > 1 else "", character.gems]
			})
			return

		# Perform upgrades with gem payment
		character.gems -= gem_cost
		item["level"] = current_level + count
		item["value"] = int(item.get("value", 100) * pow(1.5, count))

		var rarity = item.get("rarity", "common")
		item["name"] = _get_upgraded_item_name(item.get("type", ""), rarity, item["level"])

		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]%s upgraded %d level%s (now +%d) for %d gems![/color]" % [item.get("name", "Item"), count, "s" if count > 1 else "", item["level"] - 1, gem_cost]
		})
	else:
		# Standard gold payment
		if character.gold < total_cost:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF4444]You need %d gold for %d upgrade%s. You have %d gold.[/color]" % [total_cost, count, "s" if count > 1 else "", character.gold]
			})
			return

		# Perform upgrades
		character.gold -= total_cost
		item["level"] = current_level + count
		item["value"] = int(item.get("value", 100) * pow(1.5, count))

		var rarity = item.get("rarity", "common")
		item["name"] = _get_upgraded_item_name(item.get("type", ""), rarity, item["level"])

		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]%s upgraded %d level%s (now +%d) for %d gold![/color]" % [item.get("name", "Item"), count, "s" if count > 1 else "", item["level"] - 1, total_cost]
		})

	send_character_update(peer_id)

func handle_merchant_gamble(peer_id: int, message: Dictionary):
	"""Handle gambling with a merchant"""
	if not at_merchant.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a merchant!"})
		return

	var merchant = at_merchant[peer_id]
	if not "gamble" in merchant.services:
		send_to_peer(peer_id, {"type": "error", "message": "This merchant doesn't offer gambling."})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var bet_amount = message.get("amount", 100)

	# Minimum bet scales with level: level * 10 (level 1 = 10g, level 100 = 1000g)
	var min_bet = maxi(10, character.level * 10)
	var max_bet = character.gold / 2

	if max_bet < min_bet:
		send_to_peer(peer_id, {
			"type": "gamble_result",
			"success": false,
			"message": "[color=#FF4444]You need at least %d gold to gamble at your level![/color]" % (min_bet * 2),
			"gold": character.gold
		})
		return

	bet_amount = clampi(bet_amount, min_bet, max_bet)

	if character.gold < bet_amount or bet_amount < min_bet:
		send_to_peer(peer_id, {
			"type": "gamble_result",
			"success": false,
			"message": "[color=#FF4444]Invalid bet! Min: %d, Max: %d gold[/color]" % [min_bet, max_bet],
			"gold": character.gold
		})
		return

	# Simulate dice rolls for both merchant and player
	# House edge: merchant gets a hidden +2 bonus, making player wins harder
	var merchant_dice = [randi() % 6 + 1, randi() % 6 + 1, randi() % 6 + 1]
	var player_dice = [randi() % 6 + 1, randi() % 6 + 1, randi() % 6 + 1]
	var merchant_total = merchant_dice[0] + merchant_dice[1] + merchant_dice[2]
	var player_total = player_dice[0] + player_dice[1] + player_dice[2]

	# House edge - merchant effectively rolls 2 higher (hidden from player)
	var adjusted_merchant_total = merchant_total + 2

	# Build dice display (shows raw dice, not the house edge)
	var dice_msg = "[color=#FF4444]Merchant:[/color] [%d][%d][%d] = %d\n" % [merchant_dice[0], merchant_dice[1], merchant_dice[2], merchant_total]
	dice_msg += "[color=#00FF00]You:[/color] [%d][%d][%d] = %d\n" % [player_dice[0], player_dice[1], player_dice[2], player_total]

	var result_msg = ""
	var won = false
	var item_won = null

	# Check for triple 6s first - JACKPOT! (rare big win, ~0.46% chance)
	if player_dice[0] == 6 and player_dice[1] == 6 and player_dice[2] == 6:
		# Triple 6s - guaranteed item or massive gold!
		var item_level = max(1, character.level + randi() % 30)
		var tier = _level_to_tier(item_level)
		var items = drop_tables.roll_drops(tier, 100, item_level)

		if items.size() > 0 and character.can_add_item():
			character.add_item(items[0])
			item_won = items[0]
			var rarity_color = _get_rarity_color(items[0].get("rarity", "common"))
			result_msg = "[color=#FFD700]★★★ TRIPLE SIXES! JACKPOT! ★★★[/color]\n[color=%s]You won: %s![/color]" % [rarity_color, items[0].get("name", "Unknown")]
		else:
			var winnings = bet_amount * 10
			character.gold += winnings - bet_amount
			result_msg = "[color=#FFD700]★★★ TRIPLE SIXES! You win %d gold! ★★★[/color]" % winnings
		won = true
	# Check for any triple (other than 6s) - nice bonus (~2.3% chance)
	elif player_dice[0] == player_dice[1] and player_dice[1] == player_dice[2]:
		var winnings = bet_amount * 3
		character.gold += winnings - bet_amount
		result_msg = "[color=#FFD700]TRIPLE %ds! Lucky roll! You win %d gold![/color]" % [player_dice[0], winnings]
		won = true
	else:
		# Normal outcome based on dice difference (vs adjusted merchant total)
		var diff = player_total - adjusted_merchant_total

		if diff < -6:
			# Crushing loss - lose full bet
			character.gold -= bet_amount
			result_msg = "[color=#FF4444]Crushing defeat! You lose %d gold.[/color]" % bet_amount
		elif diff < -2:
			# Bad loss - lose 75% bet
			var loss = int(bet_amount * 0.75)
			character.gold -= loss
			result_msg = "[color=#FF4444]The merchant outrolls you! You lose %d gold.[/color]" % loss
		elif diff < 0:
			# Small loss - lose half bet
			var loss = int(bet_amount * 0.5)
			character.gold -= loss
			result_msg = "[color=#FF4444]Close, but not enough. You lose %d gold.[/color]" % loss
		elif diff == 0:
			# Near-tie - lose small ante (house always wins ties)
			var loss = int(bet_amount * 0.25)
			character.gold -= loss
			result_msg = "[color=#FFAA00]Too close to call... house takes a small cut: %d gold.[/color]" % loss
		elif diff <= 3:
			# Small win - win 1.25x (net +25%)
			var winnings = int(bet_amount * 1.25)
			character.gold += winnings - bet_amount
			result_msg = "[color=#00FF00]Victory! You win %d gold![/color]" % winnings
			won = true
		elif diff <= 6:
			# Good win - win 1.75x
			var winnings = int(bet_amount * 1.75)
			character.gold += winnings - bet_amount
			result_msg = "[color=#00FF00]Strong roll! You win %d gold![/color]" % winnings
			won = true
		else:
			# Dominating win - win 2.5x
			var winnings = int(bet_amount * 2.5)
			character.gold += winnings - bet_amount
			result_msg = "[color=#FFD700]DOMINATING! You win %d gold![/color]" % winnings
			won = true

	# Send gamble result with prompt to continue
	send_to_peer(peer_id, {
		"type": "gamble_result",
		"success": true,
		"dice_message": dice_msg,
		"result_message": result_msg,
		"won": won,
		"gold": character.gold,
		"min_bet": min_bet,
		"max_bet": character.gold / 2,
		"item_won": item_won.duplicate() if item_won else null
	})

	send_character_update(peer_id)

func handle_merchant_leave(peer_id: int):
	"""Handle leaving a merchant"""
	if at_merchant.has(peer_id):
		var merchant_name = at_merchant[peer_id].get("name", "The merchant")
		at_merchant.erase(peer_id)
		send_to_peer(peer_id, {
			"type": "merchant_end",
			"message": "[color=#808080]%s waves goodbye. \"Safe travels, adventurer!\"[/color]" % merchant_name
		})

func _get_recharge_cost(player_level: int) -> int:
	"""Calculate recharge cost based on player level"""
	# Base cost 50 gold, scales with level
	return 50 + (player_level * 10)

func handle_merchant_recharge(peer_id: int):
	"""Handle recharging resources at a merchant"""
	if not at_merchant.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a merchant!"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var cost = _get_recharge_cost(character.level)

	# Check if already at full resources and not poisoned
	var needs_recharge = (character.current_hp < character.get_total_max_hp() or
						  character.current_mana < character.max_mana or
						  character.current_stamina < character.max_stamina or
						  character.current_energy < character.max_energy or
						  character.poison_active)

	if not needs_recharge:
		send_to_peer(peer_id, {
			"type": "merchant_message",
			"message": "[color=#808080]\"You look fully rested already, traveler!\"[/color]"
		})
		return

	# Check if player has enough gold
	if character.gold < cost:
		send_to_peer(peer_id, {
			"type": "merchant_message",
			"message": "[color=#FF0000]\"You don't have enough gold! Recharge costs %d gold.\"[/color]" % cost
		})
		return

	# Track what was restored
	var restored = []

	# Cure poison if active
	if character.poison_active:
		character.cure_poison()
		restored.append("poison cured")

	# Deduct gold and restore resources
	character.gold -= cost
	character.current_hp = character.get_total_max_hp()
	character.current_mana = character.max_mana
	character.current_stamina = character.max_stamina
	character.current_energy = character.max_energy
	restored.append("HP and resources restored")

	send_to_peer(peer_id, {
		"type": "merchant_message",
		"message": "[color=#00FF00]The merchant provides you with a revitalizing tonic![/color]\n[color=#00FF00]%s! (-%d gold)[/color]" % [", ".join(restored).capitalize(), cost]
	})

	send_character_update(peer_id)
	persistence.save_character(character)

func _send_merchant_inventory(peer_id: int):
	"""Send inventory list to player at merchant"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var items = []
	for i in range(character.inventory.size()):
		var item = character.inventory[i]
		items.append({
			"index": i,
			"name": item.get("name", "Unknown"),
			"value": item.get("value", 10) / 2,  # Sell price
			"rarity": item.get("rarity", "common")
		})

	send_to_peer(peer_id, {
		"type": "merchant_inventory",
		"items": items,
		"gold": character.gold
	})

func _get_upgraded_item_name(item_type: String, rarity: String, level: int) -> String:
	"""Generate name for upgraded item"""
	var parts = item_type.split("_")
	var name_parts = []
	for i in range(parts.size() - 1, -1, -1):
		name_parts.append(parts[i].capitalize())
	var base_name = " ".join(name_parts)

	var prefixes = {
		"epic": ["Masterwork", "Pristine", "Exquisite", "Superior"],
		"legendary": ["Ancient", "Mythical", "Heroic", "Fabled"],
		"artifact": ["Divine", "Celestial", "Primordial", "Eternal"]
	}

	if prefixes.has(rarity):
		var prefix_list = prefixes[rarity]
		var prefix = prefix_list[randi() % prefix_list.size()]
		return prefix + " " + base_name + " +%d" % (level - 1)
	elif level > 1:
		return base_name + " +%d" % (level - 1)

	return base_name

func _level_to_tier(level: int) -> String:
	"""Convert level to drop table tier"""
	if level <= 5: return "tier1"
	if level <= 15: return "tier2"
	if level <= 30: return "tier3"
	if level <= 50: return "tier4"
	if level <= 100: return "tier5"
	if level <= 500: return "tier6"
	if level <= 2000: return "tier7"
	if level <= 5000: return "tier8"
	return "tier9"

func _get_rarity_color(rarity: String) -> String:
	"""Get display color for item rarity"""
	match rarity:
		"common": return "#FFFFFF"
		"uncommon": return "#1EFF00"
		"rare": return "#0070DD"
		"epic": return "#A335EE"
		"legendary": return "#FF8000"
		"artifact": return "#E6CC80"
		_: return "#FFFFFF"

func generate_shop_inventory(player_level: int, merchant_hash: int, specialty: String = "all") -> Array:
	"""Generate purchasable items for merchant shop based on specialty.
	Specialty: 'weapons', 'armor', 'jewelry', or 'all'"""
	var items = []

	# Use merchant hash for consistent inventory
	var rng = RandomNumberGenerator.new()
	rng.seed = merchant_hash

	# Specialized merchants have more focused inventory (4-7 items)
	# General merchants have variety (3-5 items)
	var item_count = 4 + rng.randi() % 4 if specialty != "all" else 3 + rng.randi() % 3

	var attempts = 0
	var max_attempts = item_count * 5  # Prevent infinite loops

	while items.size() < item_count and attempts < max_attempts:
		attempts += 1

		# Item level ranges around player level
		var level_roll = rng.randi() % 100
		var item_level = player_level

		if level_roll < 50:
			# Standard tier: player level -5 to +5
			item_level = maxi(1, player_level + rng.randi_range(-5, 5))
		elif level_roll < 80:
			# Premium tier: player level +5 to +20
			item_level = player_level + rng.randi_range(5, 20)
		else:
			# Legendary tier: player level +20 to +50
			item_level = player_level + rng.randi_range(20, 50)

		# Determine tier for drop tables
		var tier = _level_to_tier(item_level)

		# Roll for item (100% drop rate for shop)
		var drops = drop_tables.roll_drops(tier, 100, item_level)
		if drops.size() > 0:
			var item = drops[0]
			var item_type = item.get("type", "")

			# Filter by specialty
			if not _item_matches_specialty(item_type, specialty):
				continue

			# Shop markup: 2.5x base value
			item["shop_price"] = int(item.get("value", 100) * 2.5)
			items.append(item)

	return items

func _item_matches_specialty(item_type: String, specialty: String) -> bool:
	"""Check if an item type matches the merchant's specialty."""
	if specialty == "all":
		return true

	match specialty:
		"weapons":
			return item_type.begins_with("weapon_")
		"armor":
			# Armor specialty includes all defensive gear
			return item_type.begins_with("armor_") or item_type.begins_with("helm_") or item_type.begins_with("shield_") or item_type.begins_with("boots_")
		"jewelry":
			return item_type.begins_with("ring_") or item_type.begins_with("amulet_") or item_type == "artifact"
		_:
			return true

func handle_merchant_buy(peer_id: int, message: Dictionary):
	"""Handle buying an item from the merchant shop"""
	if not at_merchant.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a merchant!"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var item_index = message.get("index", -1)
	var use_gems = message.get("use_gems", false)

	# Get shop inventory
	var merchant = at_merchant[peer_id]
	var shop_items = merchant.get("shop_items", [])

	if item_index < 0 or item_index >= shop_items.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid item selection"})
		return

	var item = shop_items[item_index].duplicate(true)  # Deep copy
	var price = item.get("shop_price", 100)

	# Check inventory space
	if not character.can_add_item():
		send_to_peer(peer_id, {"type": "error", "message": "Your inventory is full!"})
		return

	var bought_item = null
	if use_gems:
		var gem_price = int(ceil(price / 1000.0))
		if character.gems < gem_price:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF4444]You need %d gems. You have %d gems.[/color]" % [gem_price, character.gems]
			})
			return

		character.gems -= gem_price
		item.erase("shop_price")  # Remove shop metadata
		bought_item = item.duplicate()
		character.add_item(item)

		var rarity_color = _get_rarity_color(item.get("rarity", "common"))
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]You purchased [/color][color=%s]%s[/color][color=#00FF00] for %d gems![/color]" % [rarity_color, item.get("name", "Unknown"), gem_price]
		})
	else:
		if character.gold < price:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF4444]You need %d gold. You have %d gold.[/color]" % [price, character.gold]
			})
			return

		character.gold -= price
		item.erase("shop_price")  # Remove shop metadata
		bought_item = item.duplicate()
		character.add_item(item)

		var rarity_color = _get_rarity_color(item.get("rarity", "common"))
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]You purchased [/color][color=%s]%s[/color][color=#00FF00] for %d gold![/color]" % [rarity_color, item.get("name", "Unknown"), price]
		})

	# Send buy success with item data for equip prompt
	if bought_item != null:
		var item_type = bought_item.get("type", "")
		var is_equippable = (item_type.begins_with("weapon_") or
							item_type.begins_with("armor_") or
							item_type.begins_with("helm_") or
							item_type.begins_with("shield_") or
							item_type.begins_with("boots_") or
							item_type.begins_with("ring_") or
							item_type.begins_with("amulet_"))
		if is_equippable:
			# Find the item's index in inventory (it's the last item added)
			var inv_index = character.inventory.size() - 1
			send_to_peer(peer_id, {
				"type": "merchant_buy_success",
				"item": bought_item,
				"inventory_index": inv_index,
				"is_equippable": true
			})

	# Remove item from shop (one-time purchase)
	shop_items.remove_at(item_index)
	merchant["shop_items"] = shop_items

	# Also update persistent inventory storage
	var merchant_id = merchant.get("id", "")
	if merchant_id != "" and merchant_inventories.has(merchant_id):
		merchant_inventories[merchant_id].items = shop_items

	send_character_update(peer_id)
	_send_shop_inventory(peer_id)

func _send_shop_inventory(peer_id: int):
	"""Send shop inventory to player"""
	if not at_merchant.has(peer_id):
		return

	var merchant = at_merchant[peer_id]
	var shop_items = merchant.get("shop_items", [])
	var items = []

	for i in range(shop_items.size()):
		var item = shop_items[i]
		items.append({
			"index": i,
			"name": item.get("name", "Unknown"),
			"type": item.get("type", ""),
			"level": item.get("level", 1),
			"rarity": item.get("rarity", "common"),
			"price": item.get("shop_price", 100),
			"gem_price": int(ceil(item.get("shop_price", 100) / 1000.0)),
			# Include full stats for inspection
			"attack": item.get("attack", 0),
			"defense": item.get("defense", 0),
			"attack_bonus": item.get("attack_bonus", 0),
			"defense_bonus": item.get("defense_bonus", 0),
			"hp_bonus": item.get("hp_bonus", 0),
			"str_bonus": item.get("str_bonus", 0),
			"con_bonus": item.get("con_bonus", 0),
			"dex_bonus": item.get("dex_bonus", 0),
			"int_bonus": item.get("int_bonus", 0),
			"wis_bonus": item.get("wis_bonus", 0),
			"wits_bonus": item.get("wits_bonus", 0)
		})

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	send_to_peer(peer_id, {
		"type": "shop_inventory",
		"items": items,
		"gold": character.gold,
		"gems": character.gems
	})

# ===== ACCOUNT MANAGEMENT =====

func handle_change_password(peer_id: int, message: Dictionary):
	"""Handle password change request"""
	if not peers[peer_id].authenticated:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "You must be logged in to change your password"
		})
		return

	var account_id = peers[peer_id].account_id
	var old_password = message.get("old_password", "")
	var new_password = message.get("new_password", "")

	var result = persistence.change_password(account_id, old_password, new_password)

	if result.success:
		send_to_peer(peer_id, {
			"type": "password_changed",
			"message": "Your password has been changed successfully!"
		})
	else:
		send_to_peer(peer_id, {
			"type": "password_change_failed",
			"reason": result.reason
		})

# ===== TRADING POST HANDLERS =====

func trigger_trading_post_encounter(peer_id: int):
	"""Trigger Trading Post encounter when player enters"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var tp = world_system.get_trading_post_at(character.x, character.y)

	if tp.is_empty():
		return

	# Store Trading Post data for this player
	at_trading_post[peer_id] = tp

	# Get available quests at this Trading Post
	var active_quest_ids = []
	for q in character.active_quests:
		active_quest_ids.append(q.quest_id)

	var available_quests = quest_db.get_available_quests_for_player(
		tp.id, character.completed_quests, active_quest_ids, character.daily_quest_cooldowns)

	# Check for quests ready to turn in
	var quests_to_turn_in = []
	for quest_data in character.active_quests:
		var quest = quest_db.get_quest(quest_data.quest_id)
		if not quest.is_empty() and quest.trading_post == tp.id:
			if quest_data.progress >= quest_data.target:
				quests_to_turn_in.append(quest_data.quest_id)

	send_to_peer(peer_id, {
		"type": "trading_post_start",
		"name": tp.name,
		"description": tp.description,
		"quest_giver": tp.quest_giver,
		"services": ["shop", "quests", "recharge"],
		"available_quests": available_quests.size(),
		"quests_to_turn_in": quests_to_turn_in.size()
	})

func handle_trading_post_shop(peer_id: int):
	"""Access shop services at a Trading Post"""
	if not at_trading_post.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a Trading Post!"})
		return

	var tp = at_trading_post[peer_id]

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get or generate persistent shop inventory for this Trading Post
	var merchant_id = "trading_post_" + tp.id
	var inventory_seed = hash(tp.id)
	var shop_items = get_or_generate_merchant_inventory(
		merchant_id,
		character.level,
		inventory_seed,
		"all"
	)

	# Create a merchant-like experience using the Trading Post
	var merchant_info = {
		"id": merchant_id,  # For persistent inventory tracking
		"name": tp.name + " Merchant",
		"services": ["buy", "sell", "upgrade", "gamble"],
		"specialty": "all",
		"x": tp.center.x,
		"y": tp.center.y,
		"hash": inventory_seed,
		"is_trading_post": true,
		"shop_items": shop_items
	}

	at_merchant[peer_id] = merchant_info

	# Build services message similar to regular merchants
	var services_text = []
	services_text.append("[Q] Sell items")
	services_text.append("[W] Upgrade equipment")
	services_text.append("[E] Gamble")
	if shop_items.size() > 0:
		services_text.append("[R] Buy items (%d available)" % shop_items.size())
	if character.gems > 0:
		services_text.append("[1] Sell gems (%d @ 1000g each)" % character.gems)
	services_text.append("[Space] Leave shop")

	send_to_peer(peer_id, {
		"type": "merchant_start",
		"merchant": merchant_info,
		"message": "[color=#FFD700]===== %s MARKETPLACE =====[/color]\n\n%s" % [tp.name.to_upper(), "\n".join(services_text)]
	})

	_send_merchant_inventory(peer_id)
	_send_shop_inventory(peer_id)

func handle_trading_post_quests(peer_id: int):
	"""Access quest giver at a Trading Post"""
	if not at_trading_post.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a Trading Post!"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var tp = at_trading_post[peer_id]

	# Get active quest IDs
	var active_quest_ids = []
	for q in character.active_quests:
		active_quest_ids.append(q.quest_id)

	# Get available quests
	var available_quests = quest_db.get_available_quests_for_player(
		tp.id, character.completed_quests, active_quest_ids, character.daily_quest_cooldowns)

	# Get quests ready to turn in at this Trading Post
	var quests_to_turn_in = []
	for quest_data in character.active_quests:
		var quest = quest_db.get_quest(quest_data.quest_id)
		if not quest.is_empty() and quest.trading_post == tp.id:
			if quest_data.progress >= quest_data.target:
				var rewards = quest_mgr.calculate_rewards(character, quest_data.quest_id)
				quests_to_turn_in.append({
					"quest_id": quest_data.quest_id,
					"name": quest.name,
					"rewards": rewards
				})

	send_to_peer(peer_id, {
		"type": "quest_list",
		"quest_giver": tp.quest_giver,
		"trading_post": tp.name,
		"available_quests": available_quests,
		"quests_to_turn_in": quests_to_turn_in,
		"active_count": character.active_quests.size(),
		"max_quests": Character.MAX_ACTIVE_QUESTS
	})

func handle_trading_post_recharge(peer_id: int):
	"""Recharge resources at Trading Post (50% discount, cures poison)"""
	if not at_trading_post.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a Trading Post!"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var tp = at_trading_post[peer_id]

	# Trading Posts give 50% discount on recharge
	var base_cost = _get_recharge_cost(character.level)
	var cost = int(base_cost * 0.5)

	# Check if already at full resources and not poisoned
	var needs_recharge = (character.current_hp < character.get_total_max_hp() or
						  character.current_mana < character.max_mana or
						  character.current_stamina < character.max_stamina or
						  character.current_energy < character.max_energy or
						  character.poison_active)

	if not needs_recharge:
		send_to_peer(peer_id, {
			"type": "trading_post_message",
			"message": "[color=#808080]You are already fully rested.[/color]"
		})
		return

	if character.gold < cost:
		send_to_peer(peer_id, {
			"type": "trading_post_message",
			"message": "[color=#FF0000]You don't have enough gold! Recharge costs %d gold (50%% off).[/color]" % cost
		})
		return

	# Track what was restored
	var restored = []

	# Cure poison if active
	if character.poison_active:
		character.cure_poison()
		restored.append("poison cured")

	# Deduct gold and restore ALL resources including HP
	character.gold -= cost
	character.current_hp = character.get_total_max_hp()
	character.current_mana = character.max_mana
	character.current_stamina = character.max_stamina
	character.current_energy = character.max_energy
	restored.append("HP and resources restored")

	send_to_peer(peer_id, {
		"type": "trading_post_message",
		"message": "[color=#00FF00]The healers at %s restore you completely![/color]\n[color=#00FF00]%s! (-%d gold, 50%% discount)[/color]" % [tp.name, ", ".join(restored).capitalize(), cost]
	})

	send_character_update(peer_id)
	save_character(peer_id)

func handle_trading_post_leave(peer_id: int):
	"""Leave a Trading Post"""
	if at_trading_post.has(peer_id):
		var tp_name = at_trading_post[peer_id].get("name", "The Trading Post")
		at_trading_post.erase(peer_id)
		# Also clear merchant state if they were shopping
		if at_merchant.has(peer_id):
			at_merchant.erase(peer_id)
		send_to_peer(peer_id, {
			"type": "trading_post_end",
			"message": "[color=#808080]You leave %s behind.[/color]" % tp_name
		})

# ===== QUEST HANDLERS =====

func handle_quest_accept(peer_id: int, message: Dictionary):
	"""Handle quest acceptance"""
	if not characters.has(peer_id):
		return

	var quest_id = message.get("quest_id", "")
	if quest_id.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid quest"})
		return

	var character = characters[peer_id]

	# Get origin coordinates (Trading Post location)
	var origin_x = character.x
	var origin_y = character.y

	var result = quest_mgr.accept_quest(character, quest_id, origin_x, origin_y)

	if result.success:
		var quest = quest_db.get_quest(quest_id)
		send_to_peer(peer_id, {
			"type": "quest_accepted",
			"quest_id": quest_id,
			"quest_name": quest.get("name", "Quest"),
			"message": result.message
		})
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {
			"type": "error",
			"message": result.message
		})

func handle_quest_abandon(peer_id: int, message: Dictionary):
	"""Handle quest abandonment"""
	if not characters.has(peer_id):
		return

	var quest_id = message.get("quest_id", "")
	if quest_id.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid quest"})
		return

	var character = characters[peer_id]
	var quest = quest_db.get_quest(quest_id)

	if character.abandon_quest(quest_id):
		send_to_peer(peer_id, {
			"type": "quest_abandoned",
			"quest_id": quest_id,
			"message": "Quest '%s' abandoned." % quest.get("name", "Quest")
		})
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {"type": "error", "message": "Quest not found in your active quests"})

func handle_quest_turn_in(peer_id: int, message: Dictionary):
	"""Handle quest turn-in"""
	if not characters.has(peer_id):
		return

	var quest_id = message.get("quest_id", "")
	if quest_id.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid quest"})
		return

	var character = characters[peer_id]

	# Check if at the right Trading Post
	var quest = quest_db.get_quest(quest_id)
	if quest.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Quest not found"})
		return

	if at_trading_post.has(peer_id):
		var tp = at_trading_post[peer_id]
		if quest.trading_post != tp.id:
			var required_tp = trading_post_db.TRADING_POSTS.get(quest.trading_post, {})
			send_to_peer(peer_id, {
				"type": "error",
				"message": "You must return to %s to turn in this quest." % required_tp.get("name", "the quest giver")
			})
			return
	else:
		send_to_peer(peer_id, {"type": "error", "message": "You must be at a Trading Post to turn in quests"})
		return

	var result = quest_mgr.turn_in_quest(character, quest_id)

	if result.success:
		send_to_peer(peer_id, {
			"type": "quest_turned_in",
			"quest_id": quest_id,
			"quest_name": quest.get("name", "Quest"),
			"message": result.message,
			"rewards": result.rewards,
			"leveled_up": result.leveled_up,
			"new_level": result.new_level
		})
		send_character_update(peer_id)
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {"type": "error", "message": result.message})

func handle_get_quest_log(peer_id: int):
	"""Send quest log to player with quest IDs for abandonment"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var quest_log = quest_mgr.format_quest_log(character)

	# Build array of active quest info for client-side abandonment
	var active_quests_info = []
	for quest in character.active_quests:
		var qid = quest.get("quest_id", "")
		var quest_data = quest_db.get_quest(qid)
		active_quests_info.append({
			"id": qid,
			"name": quest_data.get("name", "Unknown Quest") if quest_data else "Unknown Quest",
			"progress": quest.get("progress", 0),
			"target": quest.get("target", 1)
		})

	send_to_peer(peer_id, {
		"type": "quest_log",
		"log": quest_log,
		"active_count": character.active_quests.size(),
		"max_quests": Character.MAX_ACTIVE_QUESTS,
		"active_quests": active_quests_info
	})

func check_exploration_quest_progress(peer_id: int, x: int, y: int):
	"""Check and update exploration quest progress when entering a location"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var updates = quest_mgr.check_exploration_progress(character, x, y, world_system)

	for update in updates:
		send_to_peer(peer_id, {
			"type": "quest_progress",
			"quest_id": update.quest_id,
			"progress": update.progress,
			"target": update.target,
			"completed": update.completed,
			"message": update.message
		})

	if not updates.is_empty():
		save_character(peer_id)

func check_kill_quest_progress(peer_id: int, monster_level: int):
	"""Check and update kill quest progress after combat victory"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get hotzone info for the player's location
	var hotspot_info = world_system.get_hotspot_at(character.x, character.y)
	var hotzone_intensity = 0.0
	if hotspot_info.in_hotspot:
		hotzone_intensity = hotspot_info.intensity

	var updates = quest_mgr.check_kill_progress(
		character, monster_level, character.x, character.y, hotzone_intensity, world_system)

	for update in updates:
		send_to_peer(peer_id, {
			"type": "quest_progress",
			"quest_id": update.quest_id,
			"progress": update.progress,
			"target": update.target,
			"completed": update.completed,
			"message": update.message
		})

	if not updates.is_empty():
		save_character(peer_id)

# ===== WATCH/INSPECT HANDLERS =====

func handle_watch_request(peer_id: int, message: Dictionary):
	"""Handle request to watch another player"""
	var target_name = message.get("target", "")
	if target_name.is_empty():
		return

	# Find target player by name
	var target_peer_id = -1
	for pid in characters:
		if characters[pid].name.to_lower() == target_name.to_lower():
			target_peer_id = pid
			break

	if target_peer_id == -1:
		send_to_peer(peer_id, {"type": "error", "message": "Player '%s' not found or offline." % target_name})
		return

	if target_peer_id == peer_id:
		send_to_peer(peer_id, {"type": "error", "message": "You can't watch yourself!"})
		return

	# Check if already watching someone
	if watching.has(peer_id) and watching[peer_id] != -1:
		send_to_peer(peer_id, {"type": "error", "message": "Already watching someone. Use 'unwatch' first."})
		return

	# Send request to target player
	var requester_name = characters[peer_id].name
	send_to_peer(target_peer_id, {
		"type": "watch_request",
		"requester": requester_name,
		"requester_id": peer_id
	})

	log_message("Watch request: %s -> %s" % [requester_name, target_name])

func handle_watch_approve(peer_id: int, message: Dictionary):
	"""Handle approval of a watch request"""
	var requester_name = message.get("requester", "")
	if requester_name.is_empty():
		return

	# Find requester by name
	var requester_peer_id = -1
	for pid in characters:
		if characters[pid].name.to_lower() == requester_name.to_lower():
			requester_peer_id = pid
			break

	if requester_peer_id == -1:
		send_to_peer(peer_id, {"type": "error", "message": "Player no longer online."})
		return

	# Set up watching relationship
	watching[requester_peer_id] = peer_id
	if not watchers.has(peer_id):
		watchers[peer_id] = []
	watchers[peer_id].append(requester_peer_id)

	# Notify requester
	var target_name = characters[peer_id].name
	send_to_peer(requester_peer_id, {
		"type": "watch_approved",
		"target": target_name
	})

	# Send initial character and location data to watcher
	var character = characters[peer_id]
	var char_dict = character.to_dict()
	send_to_peer(requester_peer_id, {
		"type": "watch_character",
		"character": char_dict
	})

	# Send initial map
	var nearby_players = get_nearby_players(peer_id, 6)
	var map_display = world_system.generate_map_display(character.x, character.y, 6, nearby_players)
	send_to_peer(requester_peer_id, {
		"type": "watch_location",
		"x": character.x,
		"y": character.y,
		"description": map_display
	})

	log_message("Watch approved: %s now watching %s" % [requester_name, target_name])

func handle_watch_deny(peer_id: int, message: Dictionary):
	"""Handle denial of a watch request"""
	var requester_name = message.get("requester", "")
	if requester_name.is_empty():
		return

	# Find requester by name
	var requester_peer_id = -1
	for pid in characters:
		if characters[pid].name.to_lower() == requester_name.to_lower():
			requester_peer_id = pid
			break

	if requester_peer_id != -1:
		var target_name = characters[peer_id].name
		send_to_peer(requester_peer_id, {
			"type": "watch_denied",
			"target": target_name
		})

	log_message("Watch denied: %s denied %s" % [characters[peer_id].name, requester_name])

func handle_watch_stop(peer_id: int):
	"""Handle stopping watching another player"""
	if not watching.has(peer_id) or watching[peer_id] == -1:
		return

	var watched_peer_id = watching[peer_id]
	watching[peer_id] = -1

	# Remove from watchers list
	if watchers.has(watched_peer_id):
		watchers[watched_peer_id].erase(peer_id)

	# Notify watched player
	if characters.has(watched_peer_id):
		var watcher_name = characters[peer_id].name if characters.has(peer_id) else "Unknown"
		send_to_peer(watched_peer_id, {
			"type": "watcher_left",
			"watcher": watcher_name
		})

	log_message("Watch stopped: %s stopped watching" % (characters[peer_id].name if characters.has(peer_id) else "Unknown"))

func forward_to_watchers(peer_id: int, output: String):
	"""Forward game output to all players watching this peer"""
	if not watchers.has(peer_id) or watchers[peer_id].is_empty():
		return

	for watcher_id in watchers[peer_id]:
		send_to_peer(watcher_id, {
			"type": "watch_output",
			"output": output
		})

func send_combat_message(peer_id: int, message: String):
	"""Send a combat message and forward to watchers"""
	send_to_peer(peer_id, {"type": "combat_message", "message": message})
	forward_to_watchers(peer_id, message)

func send_game_text(peer_id: int, message: String):
	"""Send a text message and forward to watchers"""
	send_to_peer(peer_id, {"type": "text", "message": message})
	forward_to_watchers(peer_id, message)

func cleanup_watcher_on_disconnect(peer_id: int):
	"""Clean up watch relationships when a player disconnects"""
	# If this player was watching someone, notify them
	if watching.has(peer_id) and watching[peer_id] != -1:
		var watched_peer_id = watching[peer_id]
		if watchers.has(watched_peer_id):
			watchers[watched_peer_id].erase(peer_id)
			if characters.has(watched_peer_id):
				var watcher_name = characters[peer_id].name if characters.has(peer_id) else "Unknown"
				send_to_peer(watched_peer_id, {
					"type": "watcher_left",
					"watcher": watcher_name
				})
		watching.erase(peer_id)

	# If players were watching this player, notify them
	if watchers.has(peer_id):
		var player_name = characters[peer_id].name if characters.has(peer_id) else "Unknown"
		for watcher_id in watchers[peer_id]:
			send_to_peer(watcher_id, {
				"type": "watched_player_left",
				"player": player_name
			})
			if watching.has(watcher_id):
				watching[watcher_id] = -1
		watchers.erase(peer_id)
