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
const TitlesScript = preload("res://shared/titles.gd")

var server = TCPServer.new()
var peers = {}
var next_peer_id = 1
var characters = {}
var pending_flocks = {}  # peer_id -> {monster_name, monster_level}
var pending_flock_drops = {}  # peer_id -> Array of accumulated drops during flock
var pending_flock_gems = {}   # peer_id -> Total gems earned during flock
var flock_counts = {}  # peer_id -> int (how many monsters in current flock chain)
var pending_wishes = {}  # peer_id -> {wish_options, drop_messages, total_gems, drop_data}
var at_merchant = {}  # peer_id -> merchant_info dictionary
var at_trading_post = {}  # peer_id -> trading_post_data dictionary

# Persistent merchant inventory storage
# merchant_id -> {items: Array, generated_at: float, player_level: int}
var merchant_inventories = {}
const INVENTORY_REFRESH_INTERVAL = 300.0  # 5 minutes
const STARTER_INVENTORY_REFRESH_INTERVAL = 60.0  # 1 minute for starter trading posts
const STARTER_TRADING_POSTS = ["haven", "crossroads", "south_gate", "east_market", "west_shrine"]
var watchers = {}  # peer_id -> Array of peer_ids watching this player
var watching = {}  # peer_id -> peer_id of player being watched (or -1 if not watching)

# Trading system - tracks active trades between players
# active_trades: {peer_id: {partner_id, my_items: [], partner_items: [], my_ready: bool, partner_ready: bool}}
var active_trades = {}
var pending_trade_requests = {}  # {peer_id: requesting_peer_id} - pending incoming trade requests

# Title system state - only one Jarl and one High King allowed, up to 3 Eternals
var current_jarl_id: int = -1              # peer_id of current Jarl (-1 if none)
var current_high_king_id: int = -1         # peer_id of current High King (-1 if none)
var current_eternal_ids: Array = []        # peer_ids of current Eternals (max 3)
var eternal_flame_location: Vector2i = Vector2i(0, 0)  # Hidden location, moves when found
var realm_treasury: int = 0                # Gold collected from tribute

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
const AUTH_TIMEOUT = 90.0  # Kick unauthenticated connections after 90 seconds (time to enter login)
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

	# Initialize title system - randomize Eternal Flame location
	_randomize_eternal_flame_location()

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
	flock_counts.clear()
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
		"inventory_sort":
			handle_inventory_sort(peer_id, message)
		"inventory_salvage":
			handle_inventory_salvage(peer_id, message)
		"monster_select_confirm":
			handle_monster_select_confirm(peer_id, message)
		"target_farm_select":
			handle_target_farm_select(peer_id, message)
		"merchant_sell":
			handle_merchant_sell(peer_id, message)
		"merchant_sell_all":
			handle_merchant_sell_all(peer_id)
		"merchant_sell_gems":
			handle_merchant_sell_gems(peer_id, message)
		"merchant_upgrade":
			handle_merchant_upgrade(peer_id, message)
		"merchant_upgrade_all":
			handle_merchant_upgrade_all(peer_id)
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
		"toggle_cloak":
			handle_toggle_cloak(peer_id)
		"teleport":
			handle_teleport(peer_id, message)
		"get_abilities":
			handle_get_abilities(peer_id)
		"equip_ability":
			handle_equip_ability(peer_id, message)
		"unequip_ability":
			handle_unequip_ability(peer_id, message)
		"set_ability_keybind":
			handle_set_ability_keybind(peer_id, message)
		# Title system handlers
		"claim_title":
			handle_claim_title(peer_id, message)
		"title_ability":
			handle_title_ability(peer_id, message)
		"get_title_menu":
			handle_get_title_menu(peer_id)
		"forge_crown":
			handle_forge_crown(peer_id)
		# Trading system handlers
		"trade_request":
			handle_trade_request(peer_id, message)
		"trade_response":
			handle_trade_response(peer_id, message)
		"trade_offer":
			handle_trade_offer(peer_id, message)
		"trade_remove":
			handle_trade_remove(peer_id, message)
		"trade_ready":
			handle_trade_ready(peer_id)
		"trade_cancel":
			handle_trade_cancel(peer_id)
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

	# Update title holder tracking
	_update_title_holders_on_login(peer_id)

	var username = peers[peer_id].username
	log_message("Character loaded: %s (Account: %s) for peer %d" % [char_name, username, peer_id])
	update_player_list()

	send_to_peer(peer_id, {
		"type": "character_loaded",
		"character": character.to_dict(),
		"message": "Welcome back, %s!" % char_name,
		"title_holders": _get_current_title_holders()
	})

	# Broadcast join message to other players (include title if present)
	var display_name = char_name
	if not character.title.is_empty():
		display_name = TitlesScript.format_titled_name(char_name, character.title)
	broadcast_chat("[color=#00FF00]%s has entered the realm.[/color]" % display_name)

	send_location_update(peer_id)

	# Check if spawning at a Trading Post and trigger the encounter
	if world_system.is_trading_post_tile(character.x, character.y):
		trigger_trading_post_encounter(peer_id)

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

	# Validate class (9 available classes: 3 Warrior, 3 Mage, 3 Trickster)
	var valid_classes = ["Fighter", "Barbarian", "Paladin", "Wizard", "Sage", "Sorcerer", "Thief", "Ranger", "Ninja"]
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
		"message": "Welcome to the world, %s!" % char_name,
		"title_holders": _get_current_title_holders()
	})

	# Broadcast join message to other players
	broadcast_chat("[color=#00FF00]%s has entered the realm.[/color]" % char_name)

	send_location_update(peer_id)

	# Check if spawning at a Trading Post and trigger the encounter
	if world_system.is_trading_post_tile(character.x, character.y):
		trigger_trading_post_encounter(peer_id)

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
			"class": char.class_type,
			"title": char.title
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
	if flock_counts.has(peer_id):
		flock_counts.erase(peer_id)
	# Clear pending wish if any
	if pending_wishes.has(peer_id):
		pending_wishes.erase(peer_id)

	# Remove character from active characters
	if characters.has(peer_id):
		var char_name = characters[peer_id].name
		var char_title = characters[peer_id].title
		print("Character logout: %s" % char_name)
		# Update title holder tracking before removing
		_update_title_holders_on_logout(peer_id)
		characters.erase(peer_id)
		# Broadcast after removal (include title if present)
		var display_name = char_name
		if not char_title.is_empty():
			display_name = TitlesScript.format_titled_name(char_name, char_title)
		broadcast_chat("[color=#FF0000]%s has left the realm.[/color]" % display_name)

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
	if flock_counts.has(peer_id):
		flock_counts.erase(peer_id)
	# Clear pending wish if any
	if pending_wishes.has(peer_id):
		pending_wishes.erase(peer_id)

	# Remove character
	if characters.has(peer_id):
		var char_name = characters[peer_id].name
		var char_title = characters[peer_id].title
		print("Character logout: %s" % char_name)
		# Update title holder tracking before removing
		_update_title_holders_on_logout(peer_id)
		characters.erase(peer_id)
		# Broadcast after removal (include title if present)
		var display_name = char_name
		if not char_title.is_empty():
			display_name = TitlesScript.format_titled_name(char_name, char_title)
		broadcast_chat("[color=#FF0000]%s has left the realm.[/color]" % display_name)

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

	# Get title prefix if character has one
	var display_name = username
	if characters.has(peer_id):
		var character = characters[peer_id]
		if not character.title.is_empty():
			display_name = TitlesScript.format_titled_name(username, character.title)

	# Broadcast to ALL peers EXCEPT the sender
	for other_peer_id in peers.keys():
		if peers[other_peer_id].authenticated and other_peer_id != peer_id:
			send_to_peer(other_peer_id, {
				"type": "chat",
				"sender": display_name,
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

	# Cancel any active trade (moving breaks trade)
	if active_trades.has(peer_id):
		_cancel_trade(peer_id, "Trade cancelled - you moved away.")

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
	character.current_mana = min(character.get_total_max_mana(), character.current_mana + int(character.max_mana * regen_percent))
	character.current_stamina = min(character.max_stamina, character.current_stamina + int(character.max_stamina * regen_percent))
	character.current_energy = min(character.max_energy, character.current_energy + int(character.max_energy * regen_percent))

	# Process cloak drain (costs resource per movement, happens AFTER regen so cost > regen)
	var cloak_result = character.process_cloak_on_move()
	if cloak_result.dropped:
		send_to_peer(peer_id, {
			"type": "status_effect",
			"effect": "cloak_dropped",
			"message": "[color=#9932CC]%s[/color]" % cloak_result.message
		})

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

	# Tick blind on movement (counts as a round)
	if character.blind_active:
		var still_blind = character.tick_blind()
		var turns_left = character.blind_turns_remaining
		if still_blind:
			send_to_peer(peer_id, {
				"type": "status_effect",
				"effect": "blind",
				"message": "[color=#808080]You are blinded! (%d rounds remaining)[/color]" % turns_left,
				"turns_remaining": turns_left
			})
		else:
			send_to_peer(peer_id, {
				"type": "status_effect",
				"effect": "blind_cured",
				"message": "[color=#00FF00]Your vision clears![/color]"
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

	# Check for Infernal Forge (Fire Mountain) with Unforged Crown
	if new_pos.x == -400 and new_pos.y == 0:
		if _has_title_item(character, "unforged_crown"):
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF4500]The Infernal Forge burns before you. Your Unforged Crown trembles with power.[/color]"
			})
			send_to_peer(peer_id, {
				"type": "forge_available",
				"message": "[color=#FFD700]You may FORGE the Crown of the North here.[/color]"
			})

	# Check for Eternal Flame (Elder can become Eternal)
	if new_pos.x == eternal_flame_location.x and new_pos.y == eternal_flame_location.y:
		if character.title == "elder":
			_grant_eternal_title(peer_id)
			return  # Don't trigger encounters after finding the flame

	# Check for merchant first (merchants can still be encountered while cloaked)
	if world_system.check_merchant_encounter(new_pos.x, new_pos.y):
		trigger_merchant_encounter(peer_id)
	# Check for monster encounter (only if no merchant and not cloaked)
	elif not character.cloak_active and world_system.check_encounter(new_pos.x, new_pos.y):
		trigger_encounter(peer_id)

func handle_hunt(peer_id: int):
	"""Handle hunt action - actively search for monsters with increased encounter chance"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Check if cloaked - hunting breaks cloak
	if character.cloak_active:
		character.cloak_active = false
		send_to_peer(peer_id, {
			"type": "status_effect",
			"effect": "cloak_dropped",
			"message": "[color=#9932CC]Your cloak drops as you begin hunting![/color]"
		})

	# Check if in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot hunt while in combat!"})
		return

	# Check if flock encounter pending
	if pending_flocks.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "More enemies are approaching! Press Space to continue."})
		return

	# Cancel any active trade (hunting breaks trade)
	if active_trades.has(peer_id):
		_cancel_trade(peer_id, "Trade cancelled - you started hunting.")

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
	"""Handle rest action to restore HP (or Meditate for mages)"""
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
	var class_type = character.class_type
	var is_mage = class_type in ["Wizard", "Sorcerer", "Sage"]

	# Break cloak if active - resting reveals you
	if character.cloak_active:
		character.cloak_active = false
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#9932CC]Your cloak fades as you rest.[/color]"
		})

	# Mages use Meditate instead of Rest
	if is_mage:
		_handle_meditate(peer_id, character)
		return

	# Non-mages: Already at full HP
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
	var stamina_regen = int(character.max_stamina * regen_percent)
	var energy_regen = int(character.max_energy * regen_percent)
	character.current_stamina = min(character.max_stamina, character.current_stamina + stamina_regen)
	character.current_energy = min(character.max_energy, character.current_energy + energy_regen)

	# Build rest message with resource info
	var rest_msg = "[color=#00FF00]You rest and recover %d HP" % heal_amount

	# Show resource regen based on class path
	if class_type in ["Fighter", "Barbarian", "Paladin"] and stamina_regen > 0:
		rest_msg += " and %d Stamina" % stamina_regen
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

func _handle_meditate(peer_id: int, character: Character):
	"""Handle Meditate action for mages - restores HP and mana, always works"""
	var at_full_hp = character.current_hp >= character.get_total_max_hp()

	# Get equipment meditate bonus (from Mystic Amulets)
	var meditate_bonus = character.get_equipment_bonuses().get("meditate_bonus", 0)
	var bonus_mult = 1.0 + (meditate_bonus / 100.0)

	# === CLASS PASSIVE: Sage Mana Mastery ===
	# Meditate restores 50% more
	var passive = character.get_class_passive()
	var passive_effects = passive.get("effects", {})
	var sage_meditate_bonus = 0
	if passive_effects.has("meditate_bonus"):
		sage_meditate_bonus = passive_effects.get("meditate_bonus", 0)
		bonus_mult += sage_meditate_bonus

	# Mana regeneration: 4% of max mana (2x movement), double if at full HP
	var base_mana_percent = 0.04  # 2x the 2% movement regen
	var mana_percent = base_mana_percent
	if at_full_hp:
		mana_percent *= 2.0  # 8% when HP is full
	mana_percent *= bonus_mult  # Apply equipment + class meditate bonus

	var mana_regen = int(character.max_mana * mana_percent)
	mana_regen = max(1, mana_regen)
	character.current_mana = min(character.get_total_max_mana(), character.current_mana + mana_regen)

	var meditate_msg = ""
	var bonus_text = ""
	if meditate_bonus > 0 and sage_meditate_bonus > 0:
		bonus_text = " [color=#66CCCC](+%d%% from gear)[/color][color=#20B2AA](+%d%% Mana Mastery)[/color]" % [meditate_bonus, int(sage_meditate_bonus * 100)]
	elif meditate_bonus > 0:
		bonus_text = " [color=#66CCCC](+%d%% from gear)[/color]" % meditate_bonus
	elif sage_meditate_bonus > 0:
		bonus_text = " [color=#20B2AA](+%d%% Mana Mastery)[/color]" % int(sage_meditate_bonus * 100)

	if at_full_hp:
		# Full HP: focus entirely on mana
		meditate_msg = "[color=#66CCCC]You meditate deeply and recover %d Mana.%s[/color]" % [mana_regen, bonus_text]
	else:
		# Not full HP: also heal
		var heal_percent = randf_range(0.10, 0.25)
		var heal_amount = int(character.get_total_max_hp() * heal_percent)
		heal_amount = max(1, heal_amount)
		character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
		meditate_msg = "[color=#66CCCC]You meditate and recover %d HP and %d Mana.%s[/color]" % [heal_amount, mana_regen, bonus_text]

	send_to_peer(peer_id, {
		"type": "text",
		"message": meditate_msg,
		"clear_output": true
	})

	# Send updated character data
	send_to_peer(peer_id, {
		"type": "character_update",
		"character": character.to_dict()
	})

	# Chance to be ambushed while meditating (15%)
	var ambush_roll = randi() % 100
	if ambush_roll < 15:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]Your meditation is interrupted by an ambush![/color]"
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

			# Record monster knowledge (player now knows this monster type's HP at this level)
			var killed_monster_name = result.get("monster_name", "")
			var killed_monster_level = result.get("monster_level", 1)
			if killed_monster_name != "":
				characters[peer_id].record_monster_kill(killed_monster_name, killed_monster_level)

			# Check quest progress for kill-based quests
			var monster_level_for_quest = result.get("monster_level", 1)
			check_kill_quest_progress(peer_id, monster_level_for_quest)

			# Get current drops
			var current_drops = result.get("dropped_items", [])
			print("[DEBUG] Victory drops received: ", current_drops.size(), " items: ", current_drops)

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

				# Track flock count for visual variety (summoner counts as flock)
				if not flock_counts.has(peer_id):
					flock_counts[peer_id] = 1
				else:
					flock_counts[peer_id] += 1

				# Queue the summoned monster
				pending_flocks[peer_id] = {
					"monster_name": summon_next,
					"monster_level": monster_level,
					"flock_count": flock_counts[peer_id]  # For visual variety
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
				# Use base_name for flock generation (variants like "Minotaur Shield Guardian" -> "Minotaur")
				var monster_base_name = result.get("monster_base_name", monster_name)
				var monster_level = result.get("monster_level", 1)

				# Track flock count for visual variety
				if not flock_counts.has(peer_id):
					flock_counts[peer_id] = 1
				else:
					flock_counts[peer_id] += 1

				# Accumulate drops for this flock
				if not pending_flock_drops.has(peer_id):
					pending_flock_drops[peer_id] = []
				pending_flock_drops[peer_id].append_array(current_drops)

				# Accumulate gems for this flock
				if not pending_flock_gems.has(peer_id):
					pending_flock_gems[peer_id] = 0
				pending_flock_gems[peer_id] += gems_this_combat

				# Store pending flock data for this peer (including analyze bonus carry-over)
				# Use base_name so flock correctly generates same monster type (may still roll variant)
				pending_flocks[peer_id] = {
					"monster_name": monster_base_name,
					"monster_level": monster_level,
					"analyze_bonus": combat_mgr.get_analyze_bonus(peer_id),
					"flock_count": flock_counts[peer_id]  # For visual variety
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

				# Reset flock count
				if flock_counts.has(peer_id):
					flock_counts.erase(peer_id)

				# Give all drops to player now
				var drop_messages = []
				var drop_data = []  # For client sound effects
				var player_level = characters[peer_id].level
				for item in all_drops:
					if characters[peer_id].can_add_item():
						characters[peer_id].add_item(item)
						# Format with rarity symbol for visual distinction
						var rarity = item.get("rarity", "common")
						var color = _get_rarity_color(rarity)
						var symbol = _get_rarity_symbol(rarity)
						var name = item.get("name", "Unknown Item")
						drop_messages.append("[color=%s]%s %s[/color]" % [color, symbol, name])
						# Track rarity and level for sound effects
						drop_data.append({
							"rarity": rarity,
							"level": item.get("level", 1),
							"level_diff": item.get("level", 1) - player_level
						})
					else:
						# Inventory full - item lost!
						drop_messages.append("[color=#FF4444]X LOST: %s[/color]" % item.get("name", "Unknown Item"))

				# Check if wish granter gave pending wish choice (from result, not combat state)
				var wish_pending = result.get("wish_pending", false)
				var wish_options = result.get("wish_options", [])

				if wish_pending and wish_options.size() > 0:
					# Store wish data for when player selects (combat state may be cleared)
					pending_wishes[peer_id] = {
						"wish_options": wish_options,
						"drop_messages": drop_messages,
						"total_gems": total_gems,
						"drop_data": drop_data
					}
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

				# Check for Elder auto-grant (level 1000)
				check_elder_auto_grant(peer_id)

				# Save character after combat and notify of expired buffs
				save_character(peer_id)
				send_buff_expiration_notifications(peer_id)

		elif result.has("fled") and result.fled:
			# Fled successfully - lose any pending flock drops and gems
			if pending_flock_drops.has(peer_id):
				pending_flock_drops.erase(peer_id)
			if pending_flock_gems.has(peer_id):
				pending_flock_gems.erase(peer_id)
			if flock_counts.has(peer_id):
				flock_counts.erase(peer_id)

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
			if flock_counts.has(peer_id):
				flock_counts.erase(peer_id)
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
			if flock_counts.has(peer_id):
				flock_counts.erase(peer_id)
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

	# Check for pending wish in our separate storage first (more reliable)
	if not pending_wishes.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "No wish pending!"})
		return

	var wish_data = pending_wishes[peer_id]
	var wish_options = wish_data.get("wish_options", [])

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
			var rarity = gear_item.get("rarity", "common")
			result_msg += "\n[color=%s]%s %s[/color]" % [
				_get_rarity_color(rarity),
				_get_rarity_symbol(rarity),
				gear_item.get("name", "Unknown Item")
			]
		else:
			result_msg += "\n[color=#FF0000]X LOST: %s[/color]" % gear_item.get("name", "Unknown Item")

	# If upgrade was chosen, upgrade a random equipped item
	if chosen_wish.type == "upgrade":
		var upgrade_count = chosen_wish.get("upgrades", 1)
		var upgrade_result = _apply_wish_upgrades(character, upgrade_count)
		result_msg += "\n" + upgrade_result

	# Clear pending wish
	pending_wishes.erase(peer_id)

	# End combat if still active
	if combat_mgr.is_in_combat(peer_id):
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

func _apply_wish_upgrades(character: Character, upgrade_count: int) -> String:
	"""Apply multiple upgrades to a random equipped item from a wish.
	Returns a message describing what was upgraded."""
	var equipped = character.equipped
	var upgradeable_slots = []

	# Find all equipped slots with items that can be upgraded
	for slot in equipped:
		var item = equipped[slot]
		if item != null and not item.is_empty():
			# Check if item can be upgraded (has level and stats)
			if item.has("level"):
				upgradeable_slots.append(slot)

	if upgradeable_slots.is_empty():
		return "[color=#FF0000]No equipped items to upgrade![/color]"

	# Pick a random equipped item
	var chosen_slot = upgradeable_slots[randi() % upgradeable_slots.size()]
	var item = equipped[chosen_slot]
	var old_level = item.get("level", 1)

	# Apply all upgrades to this one item
	for i in range(upgrade_count):
		item = _upgrade_single_item(item)
		equipped[chosen_slot] = item

	var new_level = item.get("level", 1)
	var levels_gained = new_level - old_level

	return "[color=#FF8000]%s upgraded from Lv%d to Lv%d! (+%d levels)[/color]" % [
		item.get("name", "Equipment"),
		old_level,
		new_level,
		levels_gained
	]

func _upgrade_single_item(item: Dictionary) -> Dictionary:
	"""Apply a single upgrade to an item"""
	var current_level = item.get("level", 1)
	var new_level = current_level + 1
	item["level"] = new_level

	# Upgrade stats based on item type
	var item_type = item.get("item_type", "")

	if "weapon" in item_type:
		var current_dmg = item.get("damage", 10)
		item["damage"] = current_dmg + max(1, int(current_dmg * 0.08))
	elif "armor" in item_type:
		var current_def = item.get("defense", 5)
		item["defense"] = current_def + max(1, int(current_def * 0.08))
	elif "shield" in item_type:
		var current_def = item.get("defense", 3)
		item["defense"] = current_def + max(1, int(current_def * 0.08))
	elif "helm" in item_type:
		var current_def = item.get("defense", 2)
		item["defense"] = current_def + max(1, int(current_def * 0.08))
	elif "boots" in item_type:
		var current_speed = item.get("speed", 5)
		item["speed"] = current_speed + max(1, int(current_speed * 0.08))

	# Update name to reflect new level
	var base_name = item.get("base_name", "")
	if base_name == "":
		# Extract base name by stripping any existing "+X" suffix
		var current_name = item.get("name", "Item")
		var plus_idx = current_name.rfind(" +")
		if plus_idx > 0:
			base_name = current_name.substr(0, plus_idx)
		else:
			base_name = current_name
		# Store the base_name for future upgrades
		item["base_name"] = base_name
	item["name"] = "%s +%d" % [base_name, new_level - 1] if new_level > 1 else base_name

	return item

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

	# Check for High King "Escape Death" ability
	if character.title == "high_king" and not character.title_data.get("escape_death_used", false):
		character.title_data["escape_death_used"] = true
		character.current_hp = int(character.get_total_max_hp() * 0.1)  # Survive with 10% HP
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFD700]The Crown of the North saves you from death! But its power is now spent...[/color]"
		})
		broadcast_title_change(character.name, "high_king", "lost")
		character.title = ""
		character.title_data = {}
		current_high_king_id = -1
		send_character_update(peer_id)
		save_character(peer_id)
		return  # Don't actually die

	# Check for Eternal lives
	if character.title == "eternal":
		var lives = character.title_data.get("lives", 3)
		if lives > 1:
			character.title_data["lives"] = lives - 1
			character.current_hp = int(character.get_total_max_hp() * 0.1)  # Survive with 10% HP
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FFFF]Your eternal essence prevents death! Lives remaining: %d[/color]" % (lives - 1)
			})
			send_character_update(peer_id)
			save_character(peer_id)
			return  # Don't actually die

	# Handle title loss on death
	if not character.title.is_empty():
		var lost_title = character.title
		broadcast_title_change(character.name, lost_title, "lost")
		_update_title_holders_on_logout(peer_id)
		character.title = ""
		character.title_data = {}

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

	# Vision radius is reduced when blinded
	var vision_radius = 2 if character.blind_active else 6

	# Get nearby players for map display (within map radius)
	var nearby_players = get_nearby_players(peer_id, vision_radius)

	# Get complete map display (includes location info at top)
	var map_display = world_system.generate_map_display(character.x, character.y, vision_radius, nearby_players)

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
			"class": char.class_type,
			"title": char.title
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
	if flock_counts.has(peer_id):
		flock_counts.erase(peer_id)
	# Clear pending wish if any
	if pending_wishes.has(peer_id):
		pending_wishes.erase(peer_id)

	# Clean up merchant position tracking
	var player_key = "p_%d" % peer_id
	if last_merchant_cache_positions.has(player_key):
		last_merchant_cache_positions.erase(player_key)

	# Clean up watch relationships before erasing character
	cleanup_watcher_on_disconnect(peer_id)

	# Clean up active trades
	if active_trades.has(peer_id):
		_cancel_trade(peer_id, "Player disconnected.")
	if pending_trade_requests.has(peer_id):
		pending_trade_requests.erase(peer_id)
	# Also clean up if this player was requesting a trade with someone
	for target_id in pending_trade_requests.keys():
		if pending_trade_requests[target_id] == peer_id:
			pending_trade_requests.erase(target_id)

	# Update title holder tracking before removing
	_update_title_holders_on_logout(peer_id)

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

	# Apply target farming ability if active (from Scroll of Finding)
	if character.target_farm_ability != "" and character.target_farm_remaining > 0:
		var target_ability = character.target_farm_ability
		if not monster.get("abilities", []).has(target_ability):
			if not monster.has("abilities"):
				monster["abilities"] = []
			monster.abilities.append(target_ability)

		character.target_farm_remaining -= 1
		if character.target_farm_remaining <= 0:
			# Scroll effect expired
			character.target_farm_ability = ""
			debuff_messages.append("[color=#808080]Your Scroll of Finding's magic has faded.[/color]")
		else:
			debuff_messages.append("[color=#FFD700]Scroll of Finding: %d encounters remaining[/color]" % character.target_farm_remaining)
		save_character(peer_id)

	var result = combat_mgr.start_combat(peer_id, character, monster)

	if result.success:
		# Get contrasting background color for the monster's art
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
			"combat_bg_color": combat_bg_color,
			"use_client_art": true  # Client should render ASCII art locally
		})
		# Forward combat start to watchers with monster info for proper art display
		forward_combat_start_to_watchers(peer_id, full_message, monster_name, combat_bg_color)

func trigger_loot_find(peer_id: int, character: Character, area_level: int):
	"""Trigger a rare loot find instead of combat"""
	# Generate loot scaled to area difficulty - use drop table tier names
	var loot_tier = "tier1"
	if area_level >= 5000:
		loot_tier = "tier9"
	elif area_level >= 2500:
		loot_tier = "tier8"
	elif area_level >= 1000:
		loot_tier = "tier7"
	elif area_level >= 500:
		loot_tier = "tier6"
	elif area_level >= 250:
		loot_tier = "tier5"
	elif area_level >= 100:
		loot_tier = "tier4"
	elif area_level >= 50:
		loot_tier = "tier3"
	elif area_level >= 20:
		loot_tier = "tier2"

	# Roll for item using drop tables
	var items = drop_tables.roll_drops(loot_tier, 100, area_level)  # 100% drop chance

	var msg = ""
	var item_data = null

	if items.is_empty():
		# Fallback to gold
		var gold_amount = max(10, area_level * (randi() % 10 + 5))
		character.gold += gold_amount
		# Pad gold text to fit in box (34 chars inner width, plus 2 spaces = 36 total)
		var gold_text = "Found %d gold!" % gold_amount
		if gold_text.length() < 34:
			gold_text = gold_text + " ".repeat(34 - gold_text.length())
		msg = "[color=#FFD700]+====================================+[/color]\n"
		msg += "[color=#FFD700]|[/color]          [color=#00FF00]* LUCKY FIND! *[/color]           [color=#FFD700]|[/color]\n"
		msg += "[color=#FFD700]+====================================+[/color]\n"
		msg += "[color=#FFD700]|[/color] You discover a hidden cache!       [color=#FFD700]|[/color]\n"
		msg += "[color=#FFD700]|[/color] [color=#FFD700]%s[/color] [color=#FFD700]|[/color]\n" % gold_text
		msg += "[color=#FFD700]+====================================+[/color]"
	else:
		# Add items to inventory
		var item = items[0]
		if character.can_add_item():
			character.add_item(item)
			item_data = item
		var rarity_color = _get_rarity_color(item.get("rarity", "common"))
		var item_name = item.get("name", "Unknown Item")
		# Pad item name to fit in box (34 chars inner width, plus 2 spaces = 36 total)
		var padded_name = item_name
		if padded_name.length() < 34:
			padded_name = padded_name + " ".repeat(34 - padded_name.length())
		msg = "[color=#FFD700]+====================================+[/color]\n"
		msg += "[color=#FFD700]|[/color]          [color=#00FF00]* LUCKY FIND! *[/color]           [color=#FFD700]|[/color]\n"
		msg += "[color=#FFD700]+====================================+[/color]\n"
		msg += "[color=#FFD700]|[/color] You discover something valuable!   [color=#FFD700]|[/color]\n"
		msg += "[color=#FFD700]|[/color] [color=%s]%s[/color] [color=#FFD700]|[/color]\n" % [rarity_color, padded_name]
		msg += "[color=#FFD700]+====================================+[/color]"
		if not character.can_add_item() and items.size() > 0:
			msg += "\n[color=#FF4444]INVENTORY FULL! Item was lost![/color]"

	# Send lucky_find message that requires acknowledgment
	send_to_peer(peer_id, {
		"type": "lucky_find",
		"message": msg,
		"character": character.to_dict(),
		"item": item_data
	})

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

	# Pad content lines to 46 chars (48 inner - 2 for side spaces)
	var adventurer_line = adventurer
	if adventurer_line.length() < 46:
		adventurer_line += " ".repeat(46 - adventurer_line.length())
	var training_line = training_msgs[stat] + "!"
	if training_line.length() < 46:
		training_line += " ".repeat(46 - training_line.length())
	var bonus_line = "+%d %s permanently!" % [bonus, stat_name]
	if bonus_line.length() < 46:
		bonus_line += " ".repeat(46 - bonus_line.length())

	var msg = "[color=#FFD700]+================================================+[/color]\n"
	msg += "[color=#FFD700]|[/color]            [color=#FF69B4]* LEGENDARY ENCOUNTER *[/color]            [color=#FFD700]|[/color]\n"
	msg += "[color=#FFD700]+================================================+[/color]\n"
	msg += "[color=#FFD700]|[/color] [color=#E6CC80]%s[/color] [color=#FFD700]|[/color]\n" % adventurer_line
	msg += "[color=#FFD700]|[/color] %s [color=#FFD700]|[/color]\n" % training_line
	msg += "[color=#FFD700]+================================================+[/color]\n"
	msg += "[color=#FFD700]|[/color] [color=#00FF00]%s[/color] [color=#FFD700]|[/color]\n" % bonus_line
	msg += "[color=#FFD700]+================================================+[/color]"

	# Send special encounter message that requires acknowledgment
	send_to_peer(peer_id, {
		"type": "special_encounter",
		"message": msg,
		"character": character.to_dict()
	})

	persistence.save_character(character)
	log_message("Legendary training: %s gained +%d %s from %s" % [character.name, bonus, stat_name, adventurer])

func trigger_flock_encounter(peer_id: int, monster_name: String, monster_level: int, analyze_bonus: int = 0, flock_count: int = 1):
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
		var flock_msg = "[color=#FF4444]Another %s appears! (Pack #%d)[/color]\n%s" % [monster.name, flock_count + 1, result.message]
		# Get varied colors for flock visual variety
		var varied_colors = combat_mgr.get_flock_varied_colors(monster.name, flock_count)
		# Send flock encounter message with clear_output flag
		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": flock_msg,
			"combat_state": result.combat_state,
			"is_flock": true,
			"flock_count": flock_count,
			"clear_output": true,
			"combat_bg_color": varied_colors.bg_color,
			"flock_art_color": varied_colors.art_color,  # Client uses this to recolor ASCII art
			"use_client_art": true  # Client should render ASCII art locally
		})
		# Forward to watchers
		forward_to_watchers(peer_id, flock_msg)

func handle_continue_flock(peer_id: int):
	"""Handle player continuing into a flock encounter"""
	if not pending_flocks.has(peer_id):
		return

	var flock_data = pending_flocks[peer_id]
	pending_flocks.erase(peer_id)

	# Pass analyze bonus and flock count for visual variety
	var analyze_bonus = flock_data.get("analyze_bonus", 0)
	var flock_count = flock_data.get("flock_count", 1)
	trigger_flock_encounter(peer_id, flock_data.monster_name, flock_data.monster_level, analyze_bonus, flock_count)

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
	var item_tier = item.get("tier", 0)  # 0 means old-style item
	var is_consumable = item.get("is_consumable", false)

	# Normalize item type for consumables (e.g., mana_minor -> mana_potion)
	var normalized_type = drop_tables._normalize_consumable_type(item_type)
	if normalized_type != item_type:
		item_type = normalized_type

	# Infer tier from item name for legacy tier-based consumables
	if item_tier == 0 and _is_tier_based_consumable(item_type):
		item_tier = _infer_tier_from_name(item_name)

	# Get potion effect from drop tables
	var effect = drop_tables.get_potion_effect(item_type)

	if effect.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]This item cannot be used directly. Try equipping it.[/color]"
		})
		return

	# For consumables with stacking, use the stack function
	if is_consumable:
		var used_item = character.use_consumable_stack(index)
		if used_item.is_empty():
			send_to_peer(peer_id, {
				"type": "error",
				"message": "Failed to use item"
			})
			return
		# Get remaining quantity for display
		var remaining = 0
		var new_inventory = character.inventory
		for inv_item in new_inventory:
			if inv_item.get("type", "") == item_type and inv_item.get("tier", 0) == item_tier:
				remaining = inv_item.get("quantity", 0)
				break
	else:
		# Old-style item - remove directly
		character.remove_item(index)

	# Get values based on tier system (if available) or legacy level system
	var tier_data = {}
	if item_tier > 0 and drop_tables.CONSUMABLE_TIERS.has(item_tier):
		tier_data = drop_tables.CONSUMABLE_TIERS[item_tier]

	# Apply effect
	if effect.has("heal"):
		# Healing potion - use tier healing value if available
		var heal_amount: int
		if tier_data.has("healing"):
			heal_amount = tier_data.healing
		else:
			heal_amount = effect.base + (effect.per_level * item_level)
		var actual_heal = character.heal(heal_amount)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]You use %s and restore %d HP![/color]" % [item_name, actual_heal]
		})
	elif effect.has("mana"):
		# Mana potion - use tier healing value if available (mana uses similar scaling)
		var mana_amount: int
		if tier_data.has("healing"):
			mana_amount = int(tier_data.healing * 0.6)  # Mana is roughly 60% of HP healing
		else:
			mana_amount = effect.base + (effect.per_level * item_level)
		var old_mana = character.current_mana
		character.current_mana = min(character.get_total_max_mana(), character.current_mana + mana_amount)
		var actual_restore = character.current_mana - old_mana
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]You use %s and restore %d mana![/color]" % [item_name, actual_restore]
		})
	elif effect.has("stamina"):
		# Stamina potion
		var stamina_amount: int
		if tier_data.has("healing"):
			stamina_amount = int(tier_data.healing * 0.5)
		else:
			stamina_amount = effect.base + (effect.per_level * item_level)
		var old_stamina = character.current_stamina
		character.current_stamina = min(character.max_stamina, character.current_stamina + stamina_amount)
		var actual_restore = character.current_stamina - old_stamina
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFCC00]You use %s and restore %d stamina![/color]" % [item_name, actual_restore]
		})
	elif effect.has("energy"):
		# Energy potion
		var energy_amount: int
		if tier_data.has("healing"):
			energy_amount = int(tier_data.healing * 0.5)
		else:
			energy_amount = effect.base + (effect.per_level * item_level)
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
		var buff_value: int
		# Use forcefield_value for forcefield buffs (shields need much higher values)
		if buff_type == "forcefield" and tier_data.has("forcefield_value"):
			buff_value = tier_data.forcefield_value
		elif tier_data.has("buff_value"):
			buff_value = tier_data.buff_value
		else:
			buff_value = effect.base + (effect.per_level * item_level)
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
	elif effect.has("gems"):
		# Gem item - grants gems (premium currency) based on tier
		var gem_amount = effect.base + (effect.get("per_tier", 1) * max(0, item_tier - 1))
		character.gems += gem_amount
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]You appraise %s and receive %d gem%s![/color]" % [item_name, gem_amount, "s" if gem_amount > 1 else ""]
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
	elif effect.has("target_farm"):
		# Target Farming Scroll (Scroll of Finding) - let player select ability to farm
		var encounters = effect.get("encounters", 5)
		var options = ["weapon_master", "shield_bearer", "gem_bearer", "arcane_hoarder", "cunning_prey", "warrior_hoarder"]
		var option_names = {
			"weapon_master": "Weapon Master (weapon drops)",
			"shield_bearer": "Shield Guardian (shield drops)",
			"gem_bearer": "Gem Bearer (gem drops)",
			"arcane_hoarder": "Arcane Hoarder (mage gear drops)",
			"cunning_prey": "Cunning Prey (trickster gear drops)",
			"warrior_hoarder": "Warrior Hoarder (warrior gear drops)"
		}
		send_to_peer(peer_id, {
			"type": "target_farm_select",
			"options": options,
			"option_names": option_names,
			"encounters": encounters,
			"message": "[color=#FF00FF]The %s glows with mystical energy...[/color]\n[color=#FFD700]Choose a trait to hunt for the next %d encounters![/color]" % [item_name, encounters]
		})
		# Don't update character yet - wait for selection
		return
	elif effect.has("time_stop"):
		# Time Stop Scroll - Skip monster's next turn (lasts 1 battle)
		var battles = effect.get("battles", 1)
		character.add_persistent_buff("time_stop", 1, battles)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#9932CC]You read the %s![/color]\n[color=#FFD700]Time itself bends to your will! Your next enemy will be frozen in place for one turn![/color]" % item_name
		})
	elif effect.has("monster_bane"):
		# Monster Bane Potion - +damage vs specific monster type
		var bane_type = effect.monster_bane
		var damage_bonus = effect.damage_bonus
		var battles = effect.get("battles", 3)
		# Use a special buff type format: monster_bane_<type>
		var buff_key = "monster_bane_" + bane_type
		character.add_persistent_buff(buff_key, damage_bonus, battles)
		var type_display = bane_type.capitalize()
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4500]You drink the %s![/color]\n[color=#FFD700]For the next %d battles, you deal +%d%% damage to %s creatures![/color]" % [item_name, battles, damage_bonus, type_display]
		})
	elif effect.has("resurrect"):
		# Resurrect Scroll - Death prevention
		var revive_percent = effect.get("revive_percent", 25)
		var battles = effect.get("battles", 1)
		# Store the revive percent as the buff value
		# -1 battles = permanent until death (greater scroll)
		character.add_persistent_buff("resurrect", revive_percent, battles)
		var duration_msg: String
		if battles == -1:
			duration_msg = "If you would die, you will be resurrected at %d%% HP instead! (Persists until triggered)" % revive_percent
		else:
			duration_msg = "If you would die in the next battle, you will be resurrected at %d%% HP instead!" % revive_percent
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFD700]You read the %s![/color]\n[color=#00FF00]A divine aura surrounds you! %s[/color]" % [item_name, duration_msg]
		})
	elif effect.has("mystery_box"):
		# Mysterious Box - Opens to random item from same tier or +1 higher
		var box_tier = item_tier if item_tier > 0 else drop_tables.get_tier_for_level(item_level)
		var generated_item = drop_tables.generate_mystery_box_item(box_tier)
		if generated_item.is_empty():
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#808080]The %s crumbles to dust... nothing inside.[/color]" % item_name
			})
		else:
			# Try to add to inventory
			if character.add_item(generated_item):
				var item_color = drop_tables.get_rarity_color(generated_item.get("rarity", "common"))
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FF00FF]You open the %s...[/color]\n[color=#FFD700]A bright flash reveals:[/color] [color=%s]%s[/color]!" % [item_name, item_color, generated_item.get("name", "Unknown Item")]
				})
			else:
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FF00FF]You open the %s...[/color]\n[color=#FF0000]But your inventory is full! The item is lost![/color]" % item_name
				})
	elif effect.has("cursed_coin"):
		# Cursed Coin - 50% double gold, 50% lose half gold
		var current_gold = character.gold
		if randf() < 0.5:
			# Win! Double gold
			character.gold *= 2
			var gained = character.gold - current_gold
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FFD700]You flip the %s...[/color]\n[color=#00FF00][b]FORTUNE SMILES![/b] Your gold DOUBLES![/color]\n[color=#FFD700]+%d gold! (Total: %d)[/color]" % [item_name, gained, character.gold]
			})
		else:
			# Lose! Halve gold
			var lost = current_gold / 2
			character.gold = current_gold - lost
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#9932CC]You flip the %s...[/color]\n[color=#FF0000][b]MISFORTUNE STRIKES![/b] Half your gold vanishes![/color]\n[color=#FF4444]-%d gold! (Total: %d)[/color]" % [item_name, lost, character.gold]
			})
	elif effect.has("permanent_stat"):
		# Stat Tome - Permanently increase a stat
		var stat_name = effect.permanent_stat
		var amount = effect.get("amount", 1)
		var new_total = character.apply_permanent_stat_bonus(stat_name, amount)
		var stat_display = stat_name.capitalize()
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFD700]You study the %s![/color]\n[color=#00FF00][b]PERMANENT BONUS![/b] +%d %s![/color]\n[color=#00FFFF](Total permanent %s bonus: +%d)[/color]" % [item_name, amount, stat_display, stat_display, new_total]
		})
	elif effect.has("skill_enhance"):
		# Skill Enhancer Tome - Permanently enhance an ability
		var ability_name = effect.skill_enhance
		var enhance_effect = effect.get("effect", "damage_bonus")
		var value = effect.get("value", 10)
		var new_total = character.enhance_skill(ability_name, enhance_effect, value)
		# Format effect for display
		var effect_display = ""
		match enhance_effect:
			"damage_bonus":
				effect_display = "+%d%% damage" % int(value)
			"cost_reduction":
				effect_display = "-%d%% cost" % int(value)
			_:
				effect_display = "+%d %s" % [int(value), enhance_effect]
		var ability_display = ability_name.replace("_", " ").capitalize()
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF00FF]You master the secrets of the %s![/color]\n[color=#00FF00][b]SKILL ENHANCED![/b] %s: %s![/color]\n[color=#00FFFF](Total %s %s: +%d%%)[/color]" % [item_name, ability_display, effect_display, ability_display, enhance_effect.replace("_", " "), int(new_total)]
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

func handle_target_farm_select(peer_id: int, message: Dictionary):
	"""Handle player selecting a target farming ability from the scroll selection"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var ability = message.get("ability", "")
	var encounters = message.get("encounters", 5)

	var valid_abilities = ["weapon_master", "shield_bearer", "gem_bearer", "arcane_hoarder", "cunning_prey"]
	if ability not in valid_abilities:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid ability selection"
		})
		return

	# Set the target farming ability on character
	character.target_farm_ability = ability
	character.target_farm_remaining = encounters

	var ability_names = {
		"weapon_master": "Weapon Masters",
		"shield_bearer": "Shield Guardians",
		"gem_bearer": "Gem Bearers",
		"arcane_hoarder": "Arcane Hoarders",
		"cunning_prey": "Cunning Prey",
		"warrior_hoarder": "Warrior Hoarders"
	}

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF00FF]The scroll crumbles as its magic takes hold...[/color]\n[color=#FFD700]Your next %d encounters will attract %s![/color]" % [encounters, ability_names.get(ability, ability)]
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

func _compute_item_stat(item: Dictionary, stat: String) -> int:
	"""Compute the actual stat bonus an item provides (used for sorting/comparing)"""
	var item_level = item.get("level", 1)
	var item_type = item.get("type", "")
	var rarity = item.get("rarity", "common")

	# Rarity multipliers
	var rarity_mult = 1.0
	match rarity:
		"uncommon": rarity_mult = 1.25
		"rare": rarity_mult = 1.5
		"epic": rarity_mult = 2.0
		"legendary": rarity_mult = 3.0

	var base_bonus = int(item_level * rarity_mult)
	var value = 0

	# Compute based on item type (mirrors client _compute_item_bonuses logic)
	match stat:
		"hp":
			if "armor" in item_type:
				value = base_bonus * 3
			elif "shield" in item_type:
				value = base_bonus * 5
			# Add direct hp_bonus if present
			value += item.get("hp_bonus", 0)
		"atk":
			if "weapon" in item_type:
				value = base_bonus * 3
			elif "ring" in item_type:
				value = max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			value += item.get("attack_bonus", 0)
		"def":
			if "armor" in item_type:
				value = base_bonus * 2
			elif "helm" in item_type:
				value = base_bonus
			elif "shield" in item_type:
				value = max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			elif "boots" in item_type:
				value = max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			value += item.get("defense_bonus", 0)
		"wit":
			if "ring_shadow" in item_type:
				value = max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			elif "amulet" in item_type:
				value = max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			elif "boots_swift" in item_type:
				value = max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			value += item.get("wits_bonus", 0)
		"mana":
			if "amulet_mystic" in item_type:
				value = base_bonus * 3
			elif "amulet" in item_type:
				value = base_bonus * 2
			value += item.get("mana_bonus", 0)
		"speed":
			if "boots_swift" in item_type:
				value = int(base_bonus * 1.5)
			elif "boots" in item_type:
				value = base_bonus
			elif "amulet_evasion" in item_type:
				value = base_bonus
			value += item.get("speed_bonus", 0)

	return value

func handle_inventory_sort(peer_id: int, message: Dictionary):
	"""Handle sorting inventory by a specified criterion"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var sort_by = message.get("sort_by", "level")
	var inventory = character.inventory

	if inventory.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]No items to sort.[/color]"
		})
		return

	# Define sort comparators - use computed stats for accurate sorting
	match sort_by:
		"level":
			inventory.sort_custom(func(a, b): return a.get("level", 1) > b.get("level", 1))
		"hp":
			inventory.sort_custom(func(a, b):
				var a_hp = _compute_item_stat(a, "hp")
				var b_hp = _compute_item_stat(b, "hp")
				return a_hp > b_hp
			)
		"atk":
			inventory.sort_custom(func(a, b):
				var a_atk = _compute_item_stat(a, "atk")
				var b_atk = _compute_item_stat(b, "atk")
				return a_atk > b_atk
			)
		"def":
			inventory.sort_custom(func(a, b):
				var a_def = _compute_item_stat(a, "def")
				var b_def = _compute_item_stat(b, "def")
				return a_def > b_def
			)
		"wit":
			inventory.sort_custom(func(a, b):
				var a_wit = _compute_item_stat(a, "wit")
				var b_wit = _compute_item_stat(b, "wit")
				return a_wit > b_wit
			)
		"mana":
			inventory.sort_custom(func(a, b):
				var a_mana = _compute_item_stat(a, "mana")
				var b_mana = _compute_item_stat(b, "mana")
				return a_mana > b_mana
			)
		"speed":
			inventory.sort_custom(func(a, b):
				var a_speed = _compute_item_stat(a, "speed")
				var b_speed = _compute_item_stat(b, "speed")
				return a_speed > b_speed
			)
		"slot":
			# Sort by slot type: weapon, armor, helm, shield, boots, ring, amulet
			var slot_order = {"weapon": 0, "armor": 1, "helm": 2, "shield": 3, "boots": 4, "ring": 5, "amulet": 6}
			inventory.sort_custom(func(a, b):
				var a_slot = slot_order.get(a.get("type", ""), 99)
				var b_slot = slot_order.get(b.get("type", ""), 99)
				if a_slot != b_slot:
					return a_slot < b_slot
				return a.get("level", 1) > b.get("level", 1)
			)
		"rarity":
			var rarity_order = {"legendary": 0, "epic": 1, "rare": 2, "uncommon": 3, "common": 4}
			inventory.sort_custom(func(a, b):
				var a_rarity = rarity_order.get(a.get("rarity", "common"), 99)
				var b_rarity = rarity_order.get(b.get("rarity", "common"), 99)
				if a_rarity != b_rarity:
					return a_rarity < b_rarity
				return a.get("level", 1) > b.get("level", 1)
			)

	var sort_names = {
		"level": "Level",
		"hp": "HP bonus",
		"atk": "Attack bonus",
		"def": "Defense bonus",
		"wit": "Wits bonus",
		"mana": "Mana bonus",
		"speed": "Speed bonus",
		"slot": "equipment slot",
		"rarity": "Rarity"
	}

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FF00]Inventory sorted by %s.[/color]" % sort_names.get(sort_by, sort_by)
	})

	save_character(peer_id)
	send_character_update(peer_id)

func handle_inventory_salvage(peer_id: int, message: Dictionary):
	"""Handle bulk salvaging items for gold"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var mode = message.get("mode", "below_level")
	var inventory = character.inventory

	if inventory.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]No items to salvage.[/color]"
		})
		return

	var threshold = max(1, character.level - 5)
	var items_to_remove = []
	var total_gold = 0

	# Identify items to salvage based on mode
	for i in range(inventory.size()):
		var item = inventory[i]
		var item_level = item.get("level", 1)
		var should_salvage = false

		match mode:
			"below_level":
				should_salvage = item_level < threshold
			"all":
				should_salvage = true

		if should_salvage:
			# Calculate salvage value (25% of item value)
			var base_value = item_level * 10
			var rarity_mult = {"common": 1.0, "uncommon": 1.5, "rare": 2.0, "epic": 3.0, "legendary": 5.0}
			var mult = rarity_mult.get(item.get("rarity", "common"), 1.0)
			var salvage_value = int(base_value * mult * 0.25)
			total_gold += salvage_value
			items_to_remove.append(i)

	if items_to_remove.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]No items match the salvage criteria.[/color]"
		})
		return

	# Remove items in reverse order to preserve indices
	var salvaged_count = items_to_remove.size()
	items_to_remove.reverse()
	for idx in items_to_remove:
		character.remove_item(idx)

	# Add gold
	character.gold += total_gold

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]Salvaged %d items for %d gold![/color]" % [salvaged_count, total_gold]
	})

	save_character(peer_id)
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
	Starter trading posts refresh every 1 minute, others every 5 minutes."""
	var current_time = Time.get_unix_time_from_system()

	# Check if this is a starter trading post (faster refresh, starter items)
	var is_starter_post = false
	for starter_id in STARTER_TRADING_POSTS:
		if ("trading_post_" + starter_id) == merchant_id:
			is_starter_post = true
			break

	var refresh_interval = STARTER_INVENTORY_REFRESH_INTERVAL if is_starter_post else INVENTORY_REFRESH_INTERVAL

	# Check if we have valid cached inventory
	if merchant_inventories.has(merchant_id):
		var cached = merchant_inventories[merchant_id]
		var age = current_time - cached.generated_at

		# Return cached inventory if not expired and same player level tier
		# (regenerate if player level changed significantly to show level-appropriate items)
		var level_tier = player_level / 10
		var cached_tier = cached.player_level / 10
		if age < refresh_interval and level_tier == cached_tier:
			return cached.items

	# Generate new inventory (starter posts get starter items)
	var items = generate_shop_inventory(player_level, seed_hash, specialty, is_starter_post)
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
	var item_type = item.get("type", "")
	var item_level = item.get("level", 1)
	var sell_price = item.get("value", 10) / 2  # Default: Sell for half value

	# Special handling for gold pouches - sell for their gold content
	if item_type == "gold_pouch":
		# Match Effect description: level * 10 to level * 50, average = level * 30
		sell_price = item_level * 30
	# Special handling for gems - always worth 1000 gold
	elif item_type.begins_with("gem_"):
		sell_price = 1000

	# Remove item and give gold
	character.remove_item(index)
	character.gold += sell_price

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]You sell %s for %d gold.[/color]" % [item.get("name", "Unknown"), sell_price]
	})

	send_character_update(peer_id)
	# Note: Don't call _send_merchant_inventory here - client handles pagination via display_merchant_sell_list()

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
		var item_type = item.get("type", "")
		var item_level = item.get("level", 1)
		var sell_price = item.get("value", 10) / 2  # Default: Sell for half value

		# Special handling for gold pouches - sell for their gold content
		if item_type == "gold_pouch":
			sell_price = item_level * 30
		# Special handling for gems - always worth 1000 gold
		elif item_type.begins_with("gem_"):
			sell_price = 1000

		total_gold += sell_price

	character.inventory.clear()
	character.gold += total_gold

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]You sell %d items for %d gold![/color]" % [item_count, total_gold]
	})

	send_character_update(peer_id)
	# Note: Don't call _send_merchant_inventory here - client handles pagination via display_merchant_sell_list()

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

func handle_merchant_upgrade_all(peer_id: int):
	"""Handle upgrading all equipped items by 1 level each"""
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

	# Calculate total cost for all equipped items
	var total_cost = 0
	var items_to_upgrade = []
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = character.equipped.get(slot)
		if item != null:
			var current_level = item.get("level", 1)
			var upgrade_cost = int(pow(current_level + 1, 2) * 10)
			total_cost += upgrade_cost
			items_to_upgrade.append({"slot": slot, "item": item, "cost": upgrade_cost})

	if items_to_upgrade.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]No items equipped to upgrade.[/color]"
		})
		return

	if character.gold < total_cost:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]You need %d gold to upgrade all items. You have %d gold.[/color]" % [total_cost, character.gold]
		})
		return

	# Perform all upgrades
	character.gold -= total_cost
	var upgraded_names = []
	for entry in items_to_upgrade:
		var item = entry.item
		var current_level = item.get("level", 1)
		item["level"] = current_level + 1
		item["value"] = int(item.get("value", 100) * 1.5)
		var rarity = item.get("rarity", "common")
		item["name"] = _get_upgraded_item_name(item.get("type", ""), rarity, item["level"])
		upgraded_names.append("%s +%d" % [entry.slot.capitalize(), item["level"] - 1])

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FF00]Upgraded %d items for %d gold![/color]\n[color=#808080]%s[/color]" % [items_to_upgrade.size(), total_cost, ", ".join(upgraded_names)]
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

	# Check if already at full resources and not poisoned/blinded
	var needs_recharge = (character.current_hp < character.get_total_max_hp() or
						  character.current_mana < character.max_mana or
						  character.current_stamina < character.max_stamina or
						  character.current_energy < character.max_energy or
						  character.poison_active or
						  character.blind_active)

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

	# Cure blindness if active
	if character.blind_active:
		character.cure_blind()
		restored.append("blindness cured")

	# Deduct gold and restore resources
	character.gold -= cost
	character.current_hp = character.get_total_max_hp()
	character.current_mana = character.get_total_max_mana()
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

func _infer_tier_from_name(item_name: String) -> int:
	"""Infer consumable tier from item name for legacy items without tier field"""
	var name_lower = item_name.to_lower()
	if "divine" in name_lower: return 7
	if "master" in name_lower: return 6
	if "superior" in name_lower: return 5
	if "greater" in name_lower: return 4
	if "standard" in name_lower: return 3
	if "lesser" in name_lower: return 2
	if "minor" in name_lower: return 1
	# Default to tier 1 for consumables with no tier indicator
	return 1

func _is_tier_based_consumable(item_type: String) -> bool:
	"""Check if item type uses the tier system for scaling"""
	# Health, mana, stamina, energy potions and scrolls use tier-based values
	if item_type in ["health_potion", "mana_potion", "stamina_potion", "energy_potion"]:
		return true
	# Scrolls also use tier system
	if item_type.begins_with("scroll_"):
		return true
	return false

func _get_rarity_symbol(rarity: String) -> String:
	"""Get visual symbol prefix for item rarity - makes drops stand out"""
	match rarity:
		"common": return "+"
		"uncommon": return "++"
		"rare": return "+++"
		"epic": return "[b]>>>[/b]"
		"legendary": return "[b]***[/b]"
		"artifact": return "[b]<<<>>>[/b]"
		_: return "+"

func generate_shop_inventory(player_level: int, merchant_hash: int, specialty: String = "all", is_starter_post: bool = false) -> Array:
	"""Generate purchasable items for merchant shop based on specialty.
	Specialty: 'weapons', 'armor', 'jewelry', 'potions', 'scrolls', 'elite', or 'all'
	Starter posts have more items, lower levels, and cheaper prices.
	Elite merchants have better quality items at higher prices."""
	var items = []

	# Use merchant hash + time for varied inventory at starter posts
	var rng = RandomNumberGenerator.new()
	if is_starter_post:
		# Starter posts use time-based seed for more variety
		rng.seed = merchant_hash + int(Time.get_unix_time_from_system() / STARTER_INVENTORY_REFRESH_INTERVAL)
	else:
		rng.seed = merchant_hash

	# Determine item count based on merchant type
	var item_count: int
	if is_starter_post:
		item_count = 6 + rng.randi() % 3  # 6-8 items
	elif specialty == "elite":
		item_count = 8 + rng.randi() % 5  # 8-12 items (elite has more selection)
	elif specialty != "all":
		item_count = 4 + rng.randi() % 4  # 4-7 items
	else:
		item_count = 3 + rng.randi() % 3  # 3-5 items

	var attempts = 0
	var max_attempts = item_count * 5  # Prevent infinite loops

	while items.size() < item_count and attempts < max_attempts:
		attempts += 1

		var item_level: int

		if is_starter_post:
			# Starter posts: focus on level 1-15 items
			var level_roll = rng.randi() % 100
			if level_roll < 60:
				# Basic starter: level 1-5
				item_level = 1 + rng.randi() % 5
			elif level_roll < 90:
				# Intermediate: level 5-10
				item_level = 5 + rng.randi() % 6
			else:
				# Aspirational: level 10-15
				item_level = 10 + rng.randi() % 6
		elif specialty == "elite":
			# Elite merchants: higher quality items, biased toward premium/legendary
			var level_roll = rng.randi() % 100
			if level_roll < 20:
				# Standard tier (rare): player level to +10
				item_level = maxi(1, player_level + rng.randi_range(0, 10))
			elif level_roll < 60:
				# Premium tier: player level +10 to +30
				item_level = player_level + rng.randi_range(10, 30)
			else:
				# Legendary tier: player level +30 to +75
				item_level = player_level + rng.randi_range(30, 75)
		else:
			# Normal shop: item level ranges around player level
			var level_roll = rng.randi() % 100
			if level_roll < 50:
				# Standard tier: player level -5 to +5
				item_level = maxi(1, player_level + rng.randi_range(-5, 5))
			elif level_roll < 80:
				# Premium tier: player level +5 to +20
				item_level = player_level + rng.randi_range(5, 20)
			else:
				# Legendary tier: player level +20 to +50
				item_level = player_level + rng.randi_range(20, 50)

		# Check if this is an affix-focused merchant
		var is_affix_specialty = drop_tables.is_affix_specialty(specialty)

		var item: Dictionary
		if is_affix_specialty:
			# Affix-focused merchants: generate equipment with guaranteed specialty affixes
			var equipment_types = _get_equipment_types_for_level(item_level, rng)
			var item_type = equipment_types[rng.randi() % equipment_types.size()]
			var rarity = _get_shop_rarity(item_level, rng)
			item = drop_tables.generate_shop_item_with_specialty(item_type, rarity, item_level, specialty)
		else:
			# Normal drop table rolling
			var tier = _level_to_tier(item_level)
			var drops = drop_tables.roll_drops(tier, 100, item_level)
			if drops.size() == 0:
				continue
			item = drops[0]

		var item_type = item.get("type", "")

		# Filter by specialty (starter posts accept all types)
		if not is_starter_post and not _item_matches_specialty(item_type, specialty):
			continue

		# Shop markup varies by merchant type
		# Starter posts: 1.5x (affordable), Elite: 4x (expensive but quality)
		# Affix merchants: 3.5x (guaranteed good affixes worth premium), Normal: 2.5x
		var markup: float
		if is_starter_post:
			markup = 1.5
		elif specialty == "elite":
			markup = 4.0  # Elite merchants charge premium prices
		elif is_affix_specialty:
			markup = 3.5  # Affix merchants charge a premium for guaranteed stats
		else:
			markup = 2.5
		item["shop_price"] = int(item.get("value", 100) * markup)
		items.append(item)

	return items

func _item_matches_specialty(item_type: String, specialty: String) -> bool:
	"""Check if an item type matches the merchant's specialty."""
	if specialty == "all" or specialty == "elite":
		return true  # Elite merchants sell everything

	match specialty:
		"weapons":
			return item_type.begins_with("weapon_")
		"armor":
			# Armor specialty includes all defensive gear
			return item_type.begins_with("armor_") or item_type.begins_with("helm_") or item_type.begins_with("shield_") or item_type.begins_with("boots_")
		"jewelry":
			return item_type.begins_with("ring_") or item_type.begins_with("amulet_") or item_type == "artifact"
		"potions":
			# Potions, elixirs, and resource restorers
			return item_type.begins_with("potion_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_") or item_type.begins_with("elixir_")
		"scrolls":
			return item_type.begins_with("scroll_")
		# Affix-focused merchants sell equipment (weapons, armor, jewelry)
		"warrior_affixes", "mage_affixes", "trickster_affixes", "tank_affixes", "dps_affixes":
			return _is_equipment_type(item_type)
		_:
			return true

func _is_equipment_type(item_type: String) -> bool:
	"""Check if item type is equipment (can have affixes)."""
	return (item_type.begins_with("weapon_") or item_type.begins_with("armor_") or
		item_type.begins_with("helm_") or item_type.begins_with("shield_") or
		item_type.begins_with("boots_") or item_type.begins_with("ring_") or
		item_type.begins_with("amulet_") or item_type == "artifact")

func _get_equipment_types_for_level(item_level: int, rng: RandomNumberGenerator) -> Array:
	"""Get array of equipment types appropriate for a given level."""
	var types = []

	# Weapons scale with level
	if item_level >= 2000:
		types.append("weapon_mythic")
	elif item_level >= 500:
		types.append("weapon_legendary")
	elif item_level >= 100:
		types.append("weapon_elemental")
	elif item_level >= 50:
		types.append("weapon_magical")
	elif item_level >= 30:
		types.append("weapon_enchanted")
	elif item_level >= 15:
		types.append("weapon_steel")
	elif item_level >= 5:
		types.append("weapon_iron")
	else:
		types.append("weapon_rusty")

	# Armor scales with level
	if item_level >= 2000:
		types.append("armor_mythic")
	elif item_level >= 500:
		types.append("armor_legendary")
	elif item_level >= 100:
		types.append("armor_elemental")
	elif item_level >= 50:
		types.append("armor_magical")
	elif item_level >= 30:
		types.append("armor_enchanted")
	elif item_level >= 15:
		types.append("armor_plate")
	elif item_level >= 5:
		types.append("armor_chain")
	else:
		types.append("armor_leather")

	# Add helms, shields, boots, rings, amulets scaled to level
	if item_level >= 50:
		types.append_array(["helm_magical", "shield_magical", "boots_magical", "ring_gold", "amulet_silver"])
	elif item_level >= 15:
		types.append_array(["helm_chain", "shield_steel", "boots_chain", "ring_silver", "amulet_bronze"])
	else:
		types.append_array(["helm_leather", "shield_iron", "boots_leather", "ring_copper"])

	return types

func _get_shop_rarity(item_level: int, rng: RandomNumberGenerator) -> String:
	"""Get a rarity for shop items based on item level."""
	var roll = rng.randi() % 100

	if item_level >= 500:
		# High level: better rarities
		if roll < 10:
			return "legendary"
		elif roll < 40:
			return "epic"
		elif roll < 80:
			return "rare"
		else:
			return "uncommon"
	elif item_level >= 100:
		# Mid level
		if roll < 5:
			return "legendary"
		elif roll < 25:
			return "epic"
		elif roll < 60:
			return "rare"
		else:
			return "uncommon"
	elif item_level >= 30:
		# Lower mid
		if roll < 10:
			return "epic"
		elif roll < 40:
			return "rare"
		elif roll < 75:
			return "uncommon"
		else:
			return "common"
	else:
		# Low level
		if roll < 5:
			return "rare"
		elif roll < 30:
			return "uncommon"
		else:
			return "common"

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
			# Include affixes for client-side stat computation
			"affixes": item.get("affixes", {})
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
		tp.id, character.completed_quests, active_quest_ids, character.daily_quest_cooldowns, character.level)

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

	# Get available quests scaled to player level
	var available_quests = quest_db.get_available_quests_for_player(
		tp.id, character.completed_quests, active_quest_ids, character.daily_quest_cooldowns, character.level)

	# Add progression quest if player is high enough level for next post
	var progression_quest = _generate_progression_quest(tp.id, character.level, character.completed_quests, active_quest_ids)
	if not progression_quest.is_empty():
		available_quests.append(progression_quest)

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

	# Build active quests list for unified display (with abandon option)
	var active_quests_display = []
	for quest_data in character.active_quests:
		var quest = quest_db.get_quest(quest_data.quest_id)
		if not quest.is_empty():
			active_quests_display.append({
				"id": quest_data.quest_id,
				"name": quest.name,
				"progress": quest_data.progress,
				"target": quest_data.target,
				"description": quest.get("description", ""),
				"is_complete": quest_data.progress >= quest_data.target,
				"trading_post": quest.trading_post
			})

	send_to_peer(peer_id, {
		"type": "quest_list",
		"quest_giver": tp.quest_giver,
		"trading_post": tp.name,
		"trading_post_id": tp.id,
		"available_quests": available_quests,
		"quests_to_turn_in": quests_to_turn_in,
		"active_quests": active_quests_display,
		"active_count": character.active_quests.size(),
		"max_quests": Character.MAX_ACTIVE_QUESTS
	})

func _generate_progression_quest(current_post_id: String, player_level: int, completed_quests: Array, active_quest_ids: Array) -> Dictionary:
	"""Generate a dynamic exploration quest to guide player to the next trading post."""
	# Check if player already has a progression quest active
	for quest_id in active_quest_ids:
		if quest_id.begins_with("progression_to_"):
			return {}

	# Check if player has recently completed a progression quest to this destination
	# (prevents spam by requiring them to actually go there)
	for quest_id in completed_quests:
		if quest_id.begins_with("progression_to_"):
			# Already completed a progression quest, don't offer another from same post
			# until they visit the destination
			pass

	# Get the next recommended trading post
	var next_post = trading_post_db.get_next_progression_post(current_post_id, player_level)
	if next_post.is_empty():
		return {}

	var next_post_id = next_post.get("id", "")
	var next_post_name = next_post.get("name", "Unknown")
	var recommended_level = next_post.get("recommended_level", player_level)
	var distance = next_post.get("distance_from_origin", 0)

	# Generate quest ID
	var quest_id = "progression_to_" + next_post_id

	# Skip if already completed this specific progression quest
	if quest_id in completed_quests:
		return {}

	# Calculate rewards based on distance (further = better rewards)
	var base_xp = int(distance * 2)
	var base_gold = int(distance)
	var gems = max(0, int(distance / 100))

	return {
		"id": quest_id,
		"name": "Journey to " + next_post_name,
		"description": "Travel to %s to expand your horizons. (Recommended Level: %d)" % [next_post_name, recommended_level],
		"type": 4,  # QuestType.EXPLORATION
		"trading_post": current_post_id,
		"target": 1,
		"destinations": [next_post_id],
		"rewards": {"xp": base_xp, "gold": base_gold, "gems": gems},
		"is_daily": false,
		"prerequisite": "",
		"is_progression": true  # Flag to identify progression quests
	}

func handle_trading_post_recharge(peer_id: int):
	"""Recharge resources at Trading Post (cost scales with distance from origin, cures poison)"""
	if not at_trading_post.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a Trading Post!"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var tp = at_trading_post[peer_id]

	# Calculate cost based on level and trading post distance from origin
	# Remote trading posts charge more for their services
	var base_cost = _get_recharge_cost(character.level)
	var tp_x = tp.get("x", 0)
	var tp_y = tp.get("y", 0)
	var distance_from_origin = sqrt(tp_x * tp_x + tp_y * tp_y)
	var distance_multiplier = 1.0 + (distance_from_origin / 200.0)  # +1x per 200 distance
	var cost = int(base_cost * distance_multiplier)

	# Check if already at full resources and not poisoned/blinded
	var needs_recharge = (character.current_hp < character.get_total_max_hp() or
						  character.current_mana < character.max_mana or
						  character.current_stamina < character.max_stamina or
						  character.current_energy < character.max_energy or
						  character.poison_active or
						  character.blind_active)

	if not needs_recharge:
		send_to_peer(peer_id, {
			"type": "trading_post_message",
			"message": "[color=#808080]You are already fully rested.[/color]"
		})
		return

	if character.gold < cost:
		send_to_peer(peer_id, {
			"type": "trading_post_message",
			"message": "[color=#FF0000]You don't have enough gold! Recharge costs %d gold.[/color]" % cost
		})
		return

	# Track what was restored
	var restored = []

	# Cure poison if active
	if character.poison_active:
		character.cure_poison()
		restored.append("poison cured")

	# Cure blindness if active
	if character.blind_active:
		character.cure_blind()
		restored.append("blindness cured")

	# Deduct gold and restore ALL resources including HP
	character.gold -= cost
	character.current_hp = character.get_total_max_hp()
	character.current_mana = character.get_total_max_mana()
	character.current_stamina = character.max_stamina
	character.current_energy = character.max_energy
	restored.append("HP and resources restored")

	send_to_peer(peer_id, {
		"type": "trading_post_message",
		"message": "[color=#00FF00]The healers at %s restore you completely![/color]\n[color=#00FF00]%s! (-%d gold)[/color]" % [tp.name, ", ".join(restored).capitalize(), cost]
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

	# Get the scaled description if at a trading post (quests are scaled at display time)
	# For dynamic quests, pass player_level to regenerate with same scaling as when displayed
	var description = ""
	var completed_at_post = 0
	if at_trading_post.has(peer_id):
		var tp = at_trading_post[peer_id]
		# Count static quests completed at this post
		for qid in quest_db.QUESTS:
			if quest_db.QUESTS[qid].trading_post == tp.id and qid in character.completed_quests:
				completed_at_post += 1
		# Count dynamic quests completed at this post
		for qid in character.completed_quests:
			if qid.begins_with(tp.id + "_dynamic_"):
				completed_at_post += 1
		# Get quest with player-level scaling (for dynamic quests, this uses the same
		# generation function as when the quest was displayed to the player)
		var scaled_quest = quest_db.get_quest(quest_id, character.level, completed_at_post)
		description = scaled_quest.get("description", "")

	var result = quest_mgr.accept_quest(character, quest_id, origin_x, origin_y, description, character.level, completed_at_post)

	if result.success:
		var quest = quest_db.get_quest(quest_id, character.level, completed_at_post)
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

	var old_level = character.level
	var result = quest_mgr.turn_in_quest(character, quest_id)

	if result.success:
		# Check for newly unlocked abilities
		var unlocked_abilities = []
		if result.leveled_up:
			unlocked_abilities = character.get_newly_unlocked_abilities(old_level, result.new_level)

		send_to_peer(peer_id, {
			"type": "quest_turned_in",
			"quest_id": quest_id,
			"quest_name": quest.get("name", "Quest"),
			"message": result.message,
			"rewards": result.rewards,
			"leveled_up": result.leveled_up,
			"new_level": result.new_level,
			"unlocked_abilities": unlocked_abilities
		})
		# Check for Elder auto-grant (level 1000)
		check_elder_auto_grant(peer_id)
		send_character_update(peer_id)
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {"type": "error", "message": result.message})

func handle_get_quest_log(peer_id: int):
	"""Send quest log to player with quest IDs for abandonment"""
	if not characters.has(peer_id):
		return

	# If at a trading post, show the full quest menu instead
	if at_trading_post.has(peer_id):
		handle_trading_post_quests(peer_id)
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

	# Send initial map (vision reduced if character is blind)
	var vision_radius = 2 if character.blind_active else 6
	var nearby_players = get_nearby_players(peer_id, vision_radius)
	var map_display = world_system.generate_map_display(character.x, character.y, vision_radius, nearby_players)
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

func forward_combat_start_to_watchers(peer_id: int, message: String, monster_name: String, combat_bg_color: String):
	"""Forward combat start to watchers with monster info for proper art display"""
	if not watchers.has(peer_id) or watchers[peer_id].is_empty():
		return

	for watcher_id in watchers[peer_id]:
		send_to_peer(watcher_id, {
			"type": "watch_combat_start",
			"message": message,
			"monster_name": monster_name,
			"combat_bg_color": combat_bg_color,
			"use_client_art": true
		})

func send_combat_message(peer_id: int, message: String):
	"""Send a combat message and forward to watchers"""
	send_to_peer(peer_id, {"type": "combat_message", "message": message})
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

func handle_toggle_cloak(peer_id: int):
	"""Handle cloak toggle - allows player to cloak/uncloak outside combat"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Can't toggle cloak in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot toggle cloak while in combat!"})
		return

	# Check if character has unlocked cloak (level 20)
	if character.level < 20:
		send_to_peer(peer_id, {"type": "error", "message": "Cloak unlocks at level 20."})
		return

	# Toggle cloak
	var result = character.toggle_cloak()
	send_to_peer(peer_id, {
		"type": "cloak_toggle",
		"active": result.active,
		"message": "[color=#9932CC]%s[/color]" % result.message
	})

	# Update character state
	send_character_update(peer_id)
	save_character(peer_id)

func handle_teleport(peer_id: int, message: Dictionary):
	"""Handle teleport ability - allows player to teleport to coordinates"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Can't teleport in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot teleport while in combat!"})
		return

	# Check if character has unlocked teleport based on class path
	var teleport_level = 60  # Default (warrior)
	var path = character.get_class_path()
	match path:
		"mage":
			teleport_level = 30
		"trickster":
			teleport_level = 45
		"warrior":
			teleport_level = 60

	if character.level < teleport_level:
		send_to_peer(peer_id, {"type": "error", "message": "Teleport unlocks at level %d for your class." % teleport_level})
		return

	var target_x = message.get("x", 0)
	var target_y = message.get("y", 0)

	# Validate bounds
	if target_x < -1000 or target_x > 1000 or target_y < -1000 or target_y > 1000:
		send_to_peer(peer_id, {"type": "error", "message": "Coordinates must be between -1000 and 1000."})
		return

	# Calculate cost based on distance (25x multiplier for significant mana investment)
	var distance = sqrt(pow(target_x - character.x, 2) + pow(target_y - character.y, 2))
	var cost = int((10 + distance) * 25)

	# Determine resource type based on class path
	var resource_name = "mana"
	var current_resource = 0
	match path:
		"mage":
			resource_name = "mana"
			current_resource = character.current_mana
		"trickster":
			resource_name = "energy"
			current_resource = character.current_energy
		"warrior":
			resource_name = "stamina"
			current_resource = character.current_stamina
		_:
			resource_name = "mana"
			current_resource = character.current_mana

	if current_resource < cost:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]Not enough %s! Need %d, have %d.[/color]" % [resource_name.capitalize(), cost, current_resource]
		})
		return

	# Deduct cost
	match path:
		"mage":
			character.current_mana -= cost
		"trickster":
			character.current_energy -= cost
		"warrior":
			character.current_stamina -= cost
		_:
			character.current_mana -= cost

	# Store old position for message
	var old_x = character.x
	var old_y = character.y

	# Teleport
	character.x = target_x
	character.y = target_y

	# Break cloak if active
	if character.cloak_active:
		character.cloak_active = false
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#9932CC]Your cloak drops as you teleport.[/color]"
		})

	# Send teleport message
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#AA66FF]You channel your power and teleport from (%d, %d) to (%d, %d)! (-%d %s)[/color]" % [old_x, old_y, target_x, target_y, cost, resource_name]
	})

	# Update character and send location
	send_character_update(peer_id)
	send_location_update(peer_id)
	save_character(peer_id)

# ===== ABILITY LOADOUT HANDLERS =====

func handle_get_abilities(peer_id: int):
	"""Send ability loadout data to client"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var all_abilities = character.get_all_available_abilities()
	var unlocked = character.get_unlocked_abilities()

	send_to_peer(peer_id, {
		"type": "ability_data",
		"all_abilities": all_abilities,
		"unlocked_abilities": unlocked,
		"equipped_abilities": character.equipped_abilities,
		"ability_keybinds": character.ability_keybinds
	})

func handle_equip_ability(peer_id: int, message: Dictionary):
	"""Handle equipping an ability to a slot"""
	if not characters.has(peer_id):
		return

	# Can't change abilities in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot change abilities while in combat!"})
		return

	var slot = message.get("slot", -1)
	var ability_name = message.get("ability", "")

	if slot < 0 or slot >= Character.MAX_ABILITY_SLOTS:
		send_to_peer(peer_id, {"type": "error", "message": "Invalid ability slot."})
		return

	var character = characters[peer_id]

	if character.equip_ability(slot, ability_name):
		var ability_display = ability_name.capitalize().replace("_", " ")
		send_to_peer(peer_id, {
			"type": "ability_equipped",
			"slot": slot,
			"ability": ability_name,
			"message": "[color=#00FF00]%s equipped to slot %d.[/color]" % [ability_display, slot + 1]
		})
		send_character_update(peer_id)
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {"type": "error", "message": "Cannot equip that ability. You may not have unlocked it yet."})

func handle_unequip_ability(peer_id: int, message: Dictionary):
	"""Handle unequipping an ability from a slot"""
	if not characters.has(peer_id):
		return

	# Can't change abilities in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot change abilities while in combat!"})
		return

	var slot = message.get("slot", -1)

	if slot < 0 or slot >= Character.MAX_ABILITY_SLOTS:
		send_to_peer(peer_id, {"type": "error", "message": "Invalid ability slot."})
		return

	var character = characters[peer_id]
	var old_ability = character.get_ability_in_slot(slot)

	if character.unequip_ability(slot):
		var ability_display = old_ability.capitalize().replace("_", " ") if old_ability != "" else "Ability"
		send_to_peer(peer_id, {
			"type": "ability_unequipped",
			"slot": slot,
			"message": "[color=#FFA500]%s removed from slot %d.[/color]" % [ability_display, slot + 1]
		})
		send_character_update(peer_id)
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {"type": "error", "message": "Could not unequip ability from that slot."})

func handle_set_ability_keybind(peer_id: int, message: Dictionary):
	"""Handle changing a keybind for an ability slot"""
	if not characters.has(peer_id):
		return

	var slot = message.get("slot", -1)
	var key = message.get("key", "")

	if slot < 0 or slot >= Character.MAX_ABILITY_SLOTS:
		send_to_peer(peer_id, {"type": "error", "message": "Invalid ability slot."})
		return

	if key.length() == 0 or key.length() > 1:
		send_to_peer(peer_id, {"type": "error", "message": "Invalid keybind. Use a single key."})
		return

	var character = characters[peer_id]

	if character.set_ability_keybind(slot, key):
		send_to_peer(peer_id, {
			"type": "keybind_changed",
			"slot": slot,
			"key": key.to_upper(),
			"message": "[color=#00FFFF]Slot %d keybind set to [%s].[/color]" % [slot + 1, key.to_upper()]
		})
		send_character_update(peer_id)
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {"type": "error", "message": "Could not set keybind."})

# ===== TITLE SYSTEM =====

func _randomize_eternal_flame_location():
	"""Set the Eternal Flame to a random location within 500 distance from origin"""
	var angle = randf() * TAU  # Random angle in radians
	var distance = randf_range(100, 500)  # Random distance between 100-500
	eternal_flame_location = Vector2i(
		int(cos(angle) * distance),
		int(sin(angle) * distance)
	)
	log_message("Eternal Flame location has been randomized")

func _grant_eternal_title(peer_id: int):
	"""Grant the Eternal title to an Elder who found the Eternal Flame"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Must be an Elder to become Eternal
	if character.title != "elder":
		return

	# If 3 Eternals exist, remove the oldest one
	if current_eternal_ids.size() >= 3:
		var oldest_eternal_id = current_eternal_ids[0]
		if characters.has(oldest_eternal_id):
			var old_eternal = characters[oldest_eternal_id]
			old_eternal.title = "elder"  # Demote back to Elder
			old_eternal.title_data = {}
			broadcast_title_change(old_eternal.name, "eternal", "lost")
			send_to_peer(oldest_eternal_id, {
				"type": "title_lost",
				"title": "eternal",
				"message": "[color=#808080]A new Eternal has risen. You return to the rank of Elder.[/color]"
			})
			send_character_update(oldest_eternal_id)
			save_character(oldest_eternal_id)
		current_eternal_ids.remove_at(0)

	# Grant Eternal title
	character.title = "eternal"
	character.title_data = {"lives": 3}  # Eternals have 3 lives
	current_eternal_ids.append(peer_id)

	# Announce the ascension
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]═══════════════════════════════════════════════════════════════════════════[/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]★★★ THE ETERNAL FLAME EMBRACES YOU! ★★★[/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]You have transcended mortality. You are now ETERNAL.[/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#808080]You have 3 lives. Use them wisely.[/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]═══════════════════════════════════════════════════════════════════════════[/color]"
	})

	send_to_peer(peer_id, {
		"type": "title_achieved",
		"title": "eternal",
		"message": "[color=#00FFFF]You have become an Eternal![/color]"
	})

	broadcast_title_change(character.name, "eternal", "achieved")
	send_character_update(peer_id)
	save_character(peer_id)

	# Move the Eternal Flame to a new location
	_randomize_eternal_flame_location()
	broadcast_chat("[color=#00FFFF]The Eternal Flame has moved to a new location...[/color]")

func _update_title_holders_on_login(peer_id: int):
	"""Update title holder tracking when a character logs in"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	if character.title.is_empty():
		return

	match character.title:
		"jarl":
			# Only one Jarl allowed
			if current_jarl_id == -1:
				current_jarl_id = peer_id
				log_message("Jarl logged in: %s" % character.name)
			else:
				# Someone else is already Jarl - this shouldn't happen
				# Strip the title from the newly logged in player
				character.title = ""
				character.title_data = {}
				log_message("Warning: Duplicate Jarl detected, stripping title from %s" % character.name)
		"high_king":
			if current_high_king_id == -1:
				current_high_king_id = peer_id
				log_message("High King logged in: %s" % character.name)
			else:
				character.title = ""
				character.title_data = {}
				log_message("Warning: Duplicate High King detected, stripping title from %s" % character.name)
		"eternal":
			if not current_eternal_ids.has(peer_id) and current_eternal_ids.size() < 3:
				current_eternal_ids.append(peer_id)
				log_message("Eternal logged in: %s" % character.name)

func _update_title_holders_on_logout(peer_id: int):
	"""Update title holder tracking when a character logs out"""
	if current_jarl_id == peer_id:
		current_jarl_id = -1
		log_message("Jarl logged out")
	if current_high_king_id == peer_id:
		current_high_king_id = -1
		log_message("High King logged out")
	if current_eternal_ids.has(peer_id):
		current_eternal_ids.erase(peer_id)
		log_message("Eternal logged out")

func _get_current_title_holders() -> Array:
	"""Get list of current title holders for display on login"""
	var holders = []

	# High King (highest rank)
	if current_high_king_id != -1 and characters.has(current_high_king_id):
		var king = characters[current_high_king_id]
		holders.append({
			"title": "high_king",
			"name": king.name,
			"level": king.level
		})

	# Jarl (only if no High King)
	if current_jarl_id != -1 and characters.has(current_jarl_id):
		var jarl = characters[current_jarl_id]
		holders.append({
			"title": "jarl",
			"name": jarl.name,
			"level": jarl.level
		})

	# Eternals (up to 3)
	for eternal_id in current_eternal_ids:
		if characters.has(eternal_id):
			var eternal = characters[eternal_id]
			holders.append({
				"title": "eternal",
				"name": eternal.name,
				"level": eternal.level
			})

	# Count Elders (all level 1000+ players with "elder" title online)
	var elder_count = 0
	for peer_id in characters.keys():
		var char = characters[peer_id]
		if char.title == "elder":
			elder_count += 1

	if elder_count > 0:
		holders.append({
			"title": "elder",
			"count": elder_count
		})

	return holders

func broadcast_title_change(player_name: String, title_id: String, action: String):
	"""Broadcast a title change to all players"""
	var title_info = TitlesScript.TITLE_DATA.get(title_id, {})
	var color = title_info.get("color", "#FFD700")
	var title_name = title_info.get("name", title_id.capitalize())

	var msg = ""
	match action:
		"claimed":
			msg = "[color=%s]%s has claimed the title of %s![/color]" % [color, player_name, title_name]
		"lost":
			msg = "[color=#808080]%s is no longer %s.[/color]" % [player_name, title_name]
		"achieved":
			msg = "[color=%s]%s has achieved the rank of %s![/color]" % [color, player_name, title_name]
		"usurped":
			msg = "[color=%s]%s has usurped the throne and become %s![/color]" % [color, player_name, title_name]

	# Send to both game output and chat
	for other_peer_id in characters.keys():
		send_to_peer(other_peer_id, {"type": "text", "message": msg})
		send_to_peer(other_peer_id, {"type": "chat", "sender": "Realm", "message": msg})

	log_message("Title change: %s %s %s" % [player_name, action, title_id])

func _has_title_item(character: Character, item_type: String) -> bool:
	"""Check if character has a specific title item in inventory"""
	for item in character.inventory:
		if item.get("type", "") == item_type:
			return true
	return false

func _remove_title_item(character: Character, item_type: String) -> bool:
	"""Remove a title item from character inventory. Returns true if found and removed."""
	for i in range(character.inventory.size()):
		if character.inventory[i].get("type", "") == item_type:
			character.inventory.remove_at(i)
			return true
	return false

func _get_peer_id_for_character_name(char_name: String) -> int:
	"""Find peer_id for a character by name. Returns -1 if not found."""
	for peer_id in characters.keys():
		if characters[peer_id].name.to_lower() == char_name.to_lower():
			return peer_id
	return -1

func handle_claim_title(peer_id: int, message: Dictionary):
	"""Handle claiming a title at The High Seat"""
	if not characters.has(peer_id):
		return

	var title_type = message.get("title", "")
	var character = characters[peer_id]

	if title_type == "jarl":
		# Check if High King exists
		if current_high_king_id != -1:
			send_to_peer(peer_id, {"type": "error", "message": "A High King rules. The Jarl position is vacant."})
			return

		# Check if someone else is already Jarl
		if current_jarl_id != -1 and current_jarl_id != peer_id:
			var current_jarl = characters.get(current_jarl_id)
			var jarl_name = current_jarl.name if current_jarl else "Unknown"
			send_to_peer(peer_id, {"type": "error", "message": "%s already holds the title of Jarl." % jarl_name})
			return

		# Check level requirements
		if character.level < 50:
			send_to_peer(peer_id, {"type": "error", "message": "Jarls must be at least level 50."})
			return
		if character.level > 500:
			send_to_peer(peer_id, {"type": "error", "message": "You are too powerful for this title (max level 500)."})
			return

		# Check for Jarl's Ring
		if not _has_title_item(character, "jarls_ring"):
			send_to_peer(peer_id, {"type": "error", "message": "You need a Jarl's Ring to claim The High Seat."})
			return

		# Check location
		if character.x != 0 or character.y != 0:
			send_to_peer(peer_id, {"type": "error", "message": "You must be at The High Seat (0,0)."})
			return

		# Grant title
		_remove_title_item(character, "jarls_ring")  # Consume ring
		character.title = "jarl"
		character.title_data = {}
		current_jarl_id = peer_id

		broadcast_title_change(character.name, "jarl", "claimed")
		send_to_peer(peer_id, {
			"type": "title_claimed",
			"title": "jarl",
			"message": "[color=#C0C0C0]You claim The High Seat. You are now Jarl![/color]"
		})
		send_character_update(peer_id)
		save_character(peer_id)

	elif title_type == "high_king":
		# Check level requirements
		if character.level < 200:
			send_to_peer(peer_id, {"type": "error", "message": "The High King must be at least level 200."})
			return
		if character.level > 1000:
			send_to_peer(peer_id, {"type": "error", "message": "You are too powerful for this title (max level 1000)."})
			return

		# Check for Crown of the North
		if not _has_title_item(character, "crown_of_north"):
			send_to_peer(peer_id, {"type": "error", "message": "You need the Crown of the North to claim the throne."})
			return

		# Check location
		if character.x != 0 or character.y != 0:
			send_to_peer(peer_id, {"type": "error", "message": "You must be at The High Seat (0,0)."})
			return

		# If there's a current Jarl, they lose their title
		if current_jarl_id != -1 and current_jarl_id != peer_id:
			var old_jarl = characters.get(current_jarl_id)
			if old_jarl:
				old_jarl.title = ""
				old_jarl.title_data = {}
				broadcast_title_change(old_jarl.name, "jarl", "lost")
				send_to_peer(current_jarl_id, {
					"type": "title_lost",
					"title": "jarl",
					"message": "[color=#808080]A new High King has risen. You are no longer Jarl.[/color]"
				})
				send_character_update(current_jarl_id)
				save_character(current_jarl_id)
			current_jarl_id = -1

		# If there's a current High King, they lose their title
		if current_high_king_id != -1 and current_high_king_id != peer_id:
			var old_king = characters.get(current_high_king_id)
			if old_king:
				old_king.title = ""
				old_king.title_data = {}
				broadcast_title_change(old_king.name, "high_king", "lost")
				send_to_peer(current_high_king_id, {
					"type": "title_lost",
					"title": "high_king",
					"message": "[color=#808080]You have been usurped! You are no longer High King.[/color]"
				})
				send_character_update(current_high_king_id)
				save_character(current_high_king_id)

		# Grant title
		_remove_title_item(character, "crown_of_north")  # Consume crown
		character.title = "high_king"
		character.title_data = {"escape_death_used": false}
		current_high_king_id = peer_id

		broadcast_title_change(character.name, "high_king", "usurped")
		send_to_peer(peer_id, {
			"type": "title_claimed",
			"title": "high_king",
			"message": "[color=#FFD700]You claim the Crown of the North. You are now High King![/color]"
		})
		send_character_update(peer_id)
		save_character(peer_id)

	else:
		send_to_peer(peer_id, {"type": "error", "message": "Unknown title."})

func handle_forge_crown(peer_id: int):
	"""Handle forging the Unforged Crown into Crown of the North at Fire Mountain"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Check location (Fire Mountain / Infernal Forge at -400, 0)
	if character.x != -400 or character.y != 0:
		send_to_peer(peer_id, {"type": "error", "message": "You must be at the Infernal Forge at Fire Mountain (-400, 0)."})
		return

	# Check for Unforged Crown
	if not _has_title_item(character, "unforged_crown"):
		send_to_peer(peer_id, {"type": "error", "message": "You need an Unforged Crown to forge at the Infernal Forge."})
		return

	# Remove Unforged Crown and add Crown of the North
	_remove_title_item(character, "unforged_crown")

	var crown_of_north = TitlesScript.TITLE_ITEMS.get("crown_of_north", {})
	var new_crown = {
		"type": "crown_of_north",
		"name": crown_of_north.get("name", "Crown of the North"),
		"rarity": crown_of_north.get("rarity", "artifact"),
		"description": crown_of_north.get("description", ""),
		"is_title_item": true
	}
	character.inventory.append(new_crown)

	# Announce the forging
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]═══════════════════════════════════════════════════════════════════════════[/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF4500]The flames of the Infernal Forge roar to life![/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]Your Unforged Crown is consumed by the fire...[/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]★★★ THE CROWN OF THE NORTH HAS BEEN FORGED! ★★★[/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#C0C0C0]Take it to The High Seat at (0,0) to claim the throne of the High King.[/color]"
	})
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]═══════════════════════════════════════════════════════════════════════════[/color]"
	})

	# Broadcast to all players
	var forge_msg = "[color=#FFD700]%s has forged the Crown of the North at the Infernal Forge![/color]" % character.name
	for other_peer_id in characters.keys():
		if other_peer_id != peer_id:
			send_to_peer(other_peer_id, {
				"type": "chat",
				"sender": "Realm",
				"message": forge_msg
			})

	send_character_update(peer_id)
	save_character(peer_id)

func check_elder_auto_grant(peer_id: int):
	"""Check if character should be auto-granted Elder title at level 1000"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Already has a title? Skip (Elder doesn't override other titles)
	if not character.title.is_empty():
		return

	# Check level threshold
	if character.level >= 1000:
		character.title = "elder"
		character.title_data = {}
		broadcast_title_change(character.name, "elder", "achieved")
		send_to_peer(peer_id, {
			"type": "title_achieved",
			"title": "elder",
			"message": "[color=#9400D3]You have reached level 1000 and become an Elder of the realm![/color]"
		})
		save_character(peer_id)

func handle_title_ability(peer_id: int, message: Dictionary):
	"""Handle using a title ability"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var ability_id = message.get("ability", "")
	var target_name = message.get("target", "")
	var broadcast_text = message.get("broadcast_text", "")

	if character.title.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "You don't have a title."})
		return

	var abilities = TitlesScript.get_title_abilities(character.title)
	if not abilities.has(ability_id):
		send_to_peer(peer_id, {"type": "error", "message": "You don't have that ability."})
		return

	var ability = abilities[ability_id]
	var cost = ability.get("cost", 0)
	var resource = ability.get("resource", "none")

	# Check and consume resource cost
	if resource == "mana":
		if character.current_mana < cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough mana (%d required)." % cost})
			return
		character.current_mana -= cost
	elif resource == "mana_percent":
		var mana_cost = int(character.max_mana * cost / 100.0)
		if character.current_mana < mana_cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough mana (%d%% required)." % cost})
			return
		character.current_mana -= mana_cost
	elif resource == "gems":
		if character.gems < cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough gems (%d required)." % cost})
			return
		character.gems -= cost
	elif resource == "lives":
		var lives = character.title_data.get("lives", 3)
		if lives < cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough lives (%d required)." % cost})
			return
		character.title_data["lives"] = lives - cost

	# Find target if needed
	var target_peer_id = -1
	var target: Character = null
	if ability.get("target", "self") == "player" and not target_name.is_empty():
		target_peer_id = _get_peer_id_for_character_name(target_name)
		if target_peer_id == -1:
			send_to_peer(peer_id, {"type": "error", "message": "Player '%s' not found online." % target_name})
			return
		target = characters.get(target_peer_id)

	# Execute ability
	_execute_title_ability(peer_id, character, ability_id, target_peer_id, target, broadcast_text)
	send_character_update(peer_id)
	save_character(peer_id)

func _execute_title_ability(peer_id: int, character: Character, ability_id: String, target_peer_id: int, target: Character, broadcast_text: String):
	"""Execute a specific title ability"""
	var title_color = TitlesScript.get_title_color(character.title)
	var title_prefix = TitlesScript.get_title_prefix(character.title)

	match ability_id:
		# Jarl abilities
		"banish":
			if target:
				var offset_x = randi_range(-50, 50)
				var offset_y = randi_range(-50, 50)
				target.x = clampi(target.x + offset_x, -1000, 1000)
				target.y = clampi(target.y + offset_y, -1000, 1000)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#C0C0C0]The Jarl has banished you! You find yourself at (%d, %d).[/color]" % [target.x, target.y]
				})
				_broadcast_chat_from_title(character.name, character.title, "has banished %s!" % target.name)
				send_location_update(target_peer_id)
				save_character(target_peer_id)

		"curse":
			if target:
				target.apply_poison(5, 10)
				target.current_energy = max(0, int(target.current_energy * 0.8))
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#C0C0C0]The Jarl has cursed you! Poison courses through your veins.[/color]"
				})
				_broadcast_chat_from_title(character.name, character.title, "has cursed %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"gift_silver":
			if target:
				target.gold += 5000
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#FFD700]The Jarl has gifted you 5000 gold![/color]"
				})
				_broadcast_chat_from_title(character.name, character.title, "has gifted %s with silver!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"claim_tribute":
			var tribute = int(realm_treasury * 0.1)
			if tribute > 0:
				character.gold += tribute
				realm_treasury -= tribute
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You claim %d gold from the realm treasury.[/color]" % tribute
				})
			else:
				send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]The realm treasury is empty.[/color]"})

		# High King abilities
		"exile":
			if target:
				var angle = randf() * TAU
				var edge_dist = 200
				target.x = clampi(int(cos(angle) * edge_dist), -1000, 1000)
				target.y = clampi(int(sin(angle) * edge_dist), -1000, 1000)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#FFD700]The High King has exiled you to the edge of the realm! You find yourself at (%d, %d).[/color]" % [target.x, target.y]
				})
				_broadcast_chat_from_title(character.name, character.title, "has exiled %s from the kingdom!" % target.name)
				send_location_update(target_peer_id)
				save_character(target_peer_id)

		"knight":
			if target:
				target.add_persistent_buff("knighted", 25, 10)  # +25% damage for 10 battles
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#FFD700]The High King has knighted you! +25% damage for 10 battles.[/color]"
				})
				_broadcast_chat_from_title(character.name, character.title, "has knighted %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"cure":
			if target:
				target.cure_poison()
				target.cure_blind()
				target.active_buffs.clear()  # Clear debuffs (they're stored as negative buffs)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FF00]The High King has cured all your ailments![/color]"
				})
				_broadcast_chat_from_title(character.name, character.title, "has cured %s of all ailments!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"royal_decree":
			if not broadcast_text.is_empty():
				var decree_msg = "[color=#FFD700][ROYAL DECREE] %s[/color]" % broadcast_text
				for other_peer_id in characters.keys():
					send_to_peer(other_peer_id, {"type": "text", "message": decree_msg})
					send_to_peer(other_peer_id, {"type": "chat", "sender": "High King %s" % character.name, "message": broadcast_text})

		# Elder abilities
		"heal_other":
			if target:
				var heal_amount = int(target.get_total_max_hp() * 0.5)
				var healed = target.heal(heal_amount)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FF00]Elder %s has healed you for %d HP![/color]" % [character.name, healed]
				})
				_broadcast_chat_from_title(character.name, character.title, "has healed %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"seek_flame":
			var dx = eternal_flame_location.x - character.x
			var dy = eternal_flame_location.y - character.y
			var distance = sqrt(dx * dx + dy * dy)
			var direction = ""
			if abs(dx) > abs(dy):
				direction = "east" if dx > 0 else "west"
			else:
				direction = "north" if dy > 0 else "south"
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FFFF]The Eternal Flame calls from %d tiles to the %s...[/color]" % [int(distance), direction]
			})

		"slap":
			if target:
				var offset_x = randi_range(-20, 20)
				var offset_y = randi_range(-20, 20)
				target.x = clampi(target.x + offset_x, -1000, 1000)
				target.y = clampi(target.y + offset_y, -1000, 1000)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#9400D3]Elder %s has slapped you across the realm! You find yourself at (%d, %d).[/color]" % [character.name, target.x, target.y]
				})
				_broadcast_chat_from_title(character.name, character.title, "has slapped %s!" % target.name)
				send_location_update(target_peer_id)
				save_character(target_peer_id)

		# Eternal abilities
		"smite":
			if target:
				target.apply_poison(50, 5)
				# -50% stats debuff stored in title_data temporarily
				target.add_buff("smite_debuff", 50, 5)  # 50% stat reduction for 5 rounds
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FFFF]Eternal %s has SMITED you! Devastating curse applied.[/color]" % character.name
				})
				_broadcast_chat_from_title(character.name, character.title, "has unleashed divine wrath upon %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"restore":
			if target:
				target.current_hp = target.get_total_max_hp()
				target.current_mana = target.get_total_max_mana()
				target.current_stamina = target.max_stamina
				target.current_energy = target.max_energy
				target.cure_poison()
				target.cure_blind()
				target.active_buffs.clear()
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FFFF]Eternal %s has fully restored you![/color]" % character.name
				})
				_broadcast_chat_from_title(character.name, character.title, "has fully restored %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"bless":
			if target:
				var stats = ["strength", "constitution", "dexterity", "intelligence", "wisdom", "wits"]
				var chosen_stat = stats[randi() % stats.size()]
				match chosen_stat:
					"strength": target.strength += 5
					"constitution": target.constitution += 5
					"dexterity": target.dexterity += 5
					"intelligence": target.intelligence += 5
					"wisdom": target.wisdom += 5
					"wits": target.wits += 5
				target.calculate_derived_stats()
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FFFF]Eternal %s has blessed you with +5 %s![/color]" % [character.name, chosen_stat.capitalize()]
				})
				_broadcast_chat_from_title(character.name, character.title, "has blessed %s with divine power!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"proclaim":
			if not broadcast_text.is_empty():
				var proclaim_msg = "[color=#00FFFF][ETERNAL PROCLAMATION] %s[/color]" % broadcast_text
				for other_peer_id in characters.keys():
					send_to_peer(other_peer_id, {"type": "text", "message": proclaim_msg})
					send_to_peer(other_peer_id, {"type": "chat", "sender": "Eternal %s" % character.name, "message": broadcast_text})

func _broadcast_chat_from_title(player_name: String, title_id: String, action_text: String):
	"""Broadcast a chat message for a title action"""
	var title_color = TitlesScript.get_title_color(title_id)
	var title_prefix = TitlesScript.get_title_prefix(title_id)
	var msg = "[color=%s]%s %s %s[/color]" % [title_color, title_prefix, player_name, action_text]

	for peer_id in characters.keys():
		send_to_peer(peer_id, {"type": "chat", "sender": "Realm", "message": msg})

func handle_get_title_menu(peer_id: int):
	"""Send title menu data to client"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get available claimable titles
	var claimable = []
	if character.x == 0 and character.y == 0:
		# At The High Seat - check for claimable titles
		if _has_title_item(character, "jarls_ring") and current_high_king_id == -1:
			if character.level >= 50 and character.level <= 500:
				claimable.append({"id": "jarl", "name": "Jarl"})
		if _has_title_item(character, "crown_of_north"):
			if character.level >= 200 and character.level <= 1000:
				claimable.append({"id": "high_king", "name": "High King"})

	# Get current title abilities
	var abilities = {}
	if not character.title.is_empty():
		abilities = TitlesScript.get_title_abilities(character.title)

	# Get online players for targeting
	var online_players = []
	for pid in characters.keys():
		if pid != peer_id:
			online_players.append(characters[pid].name)

	send_to_peer(peer_id, {
		"type": "title_menu",
		"current_title": character.title,
		"title_data": character.title_data,
		"claimable": claimable,
		"abilities": abilities,
		"online_players": online_players,
		"realm_treasury": realm_treasury if character.title == "jarl" else 0
	})

# ===== TRADING SYSTEM HANDLERS =====

func _get_peer_by_name(target_name: String) -> int:
	"""Find peer_id by character name (case-insensitive). Returns -1 if not found."""
	for pid in characters.keys():
		if characters[pid].name.to_lower() == target_name.to_lower():
			return pid
	return -1

func _cancel_trade(peer_id: int, reason: String = ""):
	"""Cancel an active trade for a player and notify both parties."""
	if not active_trades.has(peer_id):
		return

	var trade = active_trades[peer_id]
	var partner_id = trade.partner_id

	# Remove trade from both players
	active_trades.erase(peer_id)
	if active_trades.has(partner_id):
		active_trades.erase(partner_id)

	# Notify both players
	var cancel_msg = {"type": "trade_cancelled", "reason": reason}
	send_to_peer(peer_id, cancel_msg)
	if peers.has(partner_id):
		send_to_peer(partner_id, cancel_msg)

func _send_trade_update(peer_id: int):
	"""Send current trade state to a player."""
	if not active_trades.has(peer_id):
		return

	var trade = active_trades[peer_id]
	var partner_id = trade.partner_id
	var partner_trade = active_trades.get(partner_id, {})

	# Get partner info
	var partner_name = ""
	var partner_class = ""
	var partner_items_data = []
	if characters.has(partner_id):
		partner_name = characters[partner_id].name
		partner_class = characters[partner_id].class_type
		# Convert partner's item indices to actual item data
		var partner_inventory = characters[partner_id].inventory
		for idx in partner_trade.get("my_items", []):
			if idx >= 0 and idx < partner_inventory.size():
				partner_items_data.append(partner_inventory[idx])

	# Get my character info
	var my_class = ""
	if characters.has(peer_id):
		my_class = characters[peer_id].class_type

	send_to_peer(peer_id, {
		"type": "trade_update",
		"partner_name": partner_name,
		"partner_class": partner_class,
		"my_class": my_class,
		"my_items": trade.my_items,
		"partner_items": partner_items_data,  # Send actual item data, not indices
		"my_ready": trade.my_ready,
		"partner_ready": partner_trade.get("my_ready", false)
	})

func handle_trade_request(peer_id: int, message: Dictionary):
	"""Handle a player requesting to trade with another player."""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var target_name = message.get("target", "").strip_edges()

	# Validation checks
	if character.in_combat:
		send_to_peer(peer_id, {"type": "error", "message": "Cannot trade while in combat."})
		return

	if active_trades.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You are already in a trade."})
		return

	if target_name.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Usage: /trade <player_name>"})
		return

	# Find target player
	var target_id = _get_peer_by_name(target_name)
	if target_id == -1:
		send_to_peer(peer_id, {"type": "error", "message": "Player '%s' is not online." % target_name})
		return

	if target_id == peer_id:
		send_to_peer(peer_id, {"type": "error", "message": "You cannot trade with yourself."})
		return

	var target = characters[target_id]

	if target.in_combat:
		send_to_peer(peer_id, {"type": "error", "message": "%s is in combat and cannot trade." % target.name})
		return

	if active_trades.has(target_id):
		send_to_peer(peer_id, {"type": "error", "message": "%s is already in a trade." % target.name})
		return

	if pending_trade_requests.has(target_id):
		send_to_peer(peer_id, {"type": "error", "message": "%s already has a pending trade request." % target.name})
		return

	# Store pending request
	pending_trade_requests[target_id] = peer_id

	# Notify requester
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]Trade request sent to %s. Waiting for response...[/color]" % target.name
	})

	# Send request to target
	send_to_peer(target_id, {
		"type": "trade_request_received",
		"from_name": character.name,
		"from_id": peer_id
	})

func handle_trade_response(peer_id: int, message: Dictionary):
	"""Handle accepting or declining a trade request."""
	if not characters.has(peer_id):
		return

	var accept = message.get("accept", false)

	if not pending_trade_requests.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "No pending trade request."})
		return

	var requester_id = pending_trade_requests[peer_id]
	pending_trade_requests.erase(peer_id)

	if not characters.has(requester_id):
		send_to_peer(peer_id, {"type": "error", "message": "The other player is no longer online."})
		return

	var requester = characters[requester_id]
	var responder = characters[peer_id]

	if not accept:
		# Declined
		send_to_peer(requester_id, {
			"type": "text",
			"message": "[color=#FF8800]%s declined your trade request.[/color]" % responder.name
		})
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]Trade request declined.[/color]"
		})
		return

	# Accepted - check if either player is now in combat or trading
	if requester.in_combat or responder.in_combat:
		send_to_peer(peer_id, {"type": "error", "message": "Trade cancelled - a player entered combat."})
		send_to_peer(requester_id, {"type": "error", "message": "Trade cancelled - a player entered combat."})
		return

	if active_trades.has(requester_id) or active_trades.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "Trade cancelled - a player is already trading."})
		send_to_peer(requester_id, {"type": "error", "message": "Trade cancelled - a player is already trading."})
		return

	# Create trade session for both players
	active_trades[peer_id] = {
		"partner_id": requester_id,
		"my_items": [],  # Array of inventory indices
		"my_ready": false
	}
	active_trades[requester_id] = {
		"partner_id": peer_id,
		"my_items": [],
		"my_ready": false
	}

	# Notify both players trade has started
	send_to_peer(peer_id, {
		"type": "trade_started",
		"partner_name": requester.name,
		"partner_class": requester.class_type
	})
	send_to_peer(requester_id, {
		"type": "trade_started",
		"partner_name": responder.name,
		"partner_class": responder.class_type
	})

	# Send initial trade state
	_send_trade_update(peer_id)
	_send_trade_update(requester_id)

func handle_trade_offer(peer_id: int, message: Dictionary):
	"""Handle adding an item to trade offer."""
	if not characters.has(peer_id) or not active_trades.has(peer_id):
		return

	var character = characters[peer_id]
	var trade = active_trades[peer_id]
	var index = message.get("index", -1)

	# Reset ready status when offer changes
	trade.my_ready = false
	if active_trades.has(trade.partner_id):
		active_trades[trade.partner_id].my_ready = false

	# Validate index
	if index < 0 or index >= character.inventory.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid item index."})
		return

	# Check if already in offer
	if index in trade.my_items:
		send_to_peer(peer_id, {"type": "error", "message": "Item already in trade offer."})
		return

	# Check if item is equipped (can't trade equipped items)
	var item = character.inventory[index]
	var item_type = item.get("type", "")

	# Add to offer
	trade.my_items.append(index)

	# Update both players
	_send_trade_update(peer_id)
	_send_trade_update(trade.partner_id)

func handle_trade_remove(peer_id: int, message: Dictionary):
	"""Handle removing an item from trade offer."""
	if not characters.has(peer_id) or not active_trades.has(peer_id):
		return

	var trade = active_trades[peer_id]
	var index = message.get("index", -1)

	# Reset ready status when offer changes
	trade.my_ready = false
	if active_trades.has(trade.partner_id):
		active_trades[trade.partner_id].my_ready = false

	# Remove from offer
	var offer_index = trade.my_items.find(index)
	if offer_index != -1:
		trade.my_items.remove_at(offer_index)

	# Update both players
	_send_trade_update(peer_id)
	_send_trade_update(trade.partner_id)

func handle_trade_ready(peer_id: int):
	"""Handle a player marking themselves as ready to complete trade."""
	if not characters.has(peer_id) or not active_trades.has(peer_id):
		return

	var trade = active_trades[peer_id]
	var partner_id = trade.partner_id

	if not active_trades.has(partner_id):
		_cancel_trade(peer_id, "Partner disconnected.")
		return

	var partner_trade = active_trades[partner_id]

	# Toggle ready status
	trade.my_ready = not trade.my_ready

	# Check if both ready - execute trade
	if trade.my_ready and partner_trade.my_ready:
		_execute_trade(peer_id, partner_id)
	else:
		# Just update status
		_send_trade_update(peer_id)
		_send_trade_update(partner_id)

func _execute_trade(peer_id_a: int, peer_id_b: int):
	"""Execute a trade between two players."""
	var char_a = characters[peer_id_a]
	var char_b = characters[peer_id_b]
	var trade_a = active_trades[peer_id_a]
	var trade_b = active_trades[peer_id_b]

	# Collect items to trade (make copies before modifying inventories)
	var items_from_a = []
	var items_from_b = []

	# Sort indices in descending order so we can remove without index shifting issues
	var indices_a = trade_a.my_items.duplicate()
	var indices_b = trade_b.my_items.duplicate()
	indices_a.sort()
	indices_a.reverse()
	indices_b.sort()
	indices_b.reverse()

	# Validate both players have space for incoming items
	var space_needed_a = indices_b.size()
	var space_needed_b = indices_a.size()
	var space_available_a = char_a.MAX_INVENTORY_SIZE - char_a.inventory.size() + indices_a.size()
	var space_available_b = char_b.MAX_INVENTORY_SIZE - char_b.inventory.size() + indices_b.size()

	if space_available_a < space_needed_a:
		_cancel_trade(peer_id_a, "%s doesn't have enough inventory space." % char_a.name)
		return
	if space_available_b < space_needed_b:
		_cancel_trade(peer_id_a, "%s doesn't have enough inventory space." % char_b.name)
		return

	# Extract items from A
	for idx in indices_a:
		if idx >= 0 and idx < char_a.inventory.size():
			items_from_a.append(char_a.inventory[idx].duplicate(true))
			char_a.inventory.remove_at(idx)

	# Extract items from B
	for idx in indices_b:
		if idx >= 0 and idx < char_b.inventory.size():
			items_from_b.append(char_b.inventory[idx].duplicate(true))
			char_b.inventory.remove_at(idx)

	# Give items to each player
	for item in items_from_b:
		char_a.add_item(item)
	for item in items_from_a:
		char_b.add_item(item)

	# Clear trade state
	active_trades.erase(peer_id_a)
	active_trades.erase(peer_id_b)

	# Save both characters
	save_character(peer_id_a)
	save_character(peer_id_b)

	# Notify both players
	send_to_peer(peer_id_a, {
		"type": "trade_complete",
		"received_count": items_from_b.size(),
		"gave_count": items_from_a.size()
	})
	send_to_peer(peer_id_b, {
		"type": "trade_complete",
		"received_count": items_from_a.size(),
		"gave_count": items_from_b.size()
	})

	# Send character updates
	send_character_update(peer_id_a)
	send_character_update(peer_id_b)

func handle_trade_cancel(peer_id: int):
	"""Handle a player cancelling a trade."""
	if pending_trade_requests.has(peer_id):
		var requester_id = pending_trade_requests[peer_id]
		pending_trade_requests.erase(peer_id)
		if peers.has(requester_id):
			send_to_peer(requester_id, {
				"type": "text",
				"message": "[color=#FF8800]Trade request cancelled.[/color]"
			})

	if active_trades.has(peer_id):
		_cancel_trade(peer_id, "Trade cancelled.")
