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
@onready var pending_update_button = $VBox/ButtonRow/PendingUpdateButton
@onready var cancel_update_button = $VBox/ButtonRow/CancelUpdateButton
@onready var confirm_dialog = $ConfirmDialog
@onready var broadcast_input = $VBox/BroadcastRow/BroadcastInput
@onready var broadcast_button = $VBox/BroadcastRow/BroadcastButton

# Pending update shutdown state
var pending_update_active: bool = false
var pending_update_seconds_remaining: float = 0.0
var pending_update_last_announcement: int = -1  # Track which announcement was last sent
const PersistenceManagerScript = preload("res://server/persistence_manager.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const QuestDatabaseScript = preload("res://shared/quest_database.gd")
const QuestManagerScript = preload("res://shared/quest_manager.gd")
const TradingPostDatabaseScript = preload("res://shared/trading_post_database.gd")
const TitlesScript = preload("res://shared/titles.gd")
const CraftingDatabaseScript = preload("res://shared/crafting_database.gd")
const DungeonDatabaseScript = preload("res://shared/dungeon_database.gd")

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
var current_knight_peer_id: int = -1       # peer_id of current Knight (-1 if none)
var current_mentee_peer_ids: Dictionary = {}  # {elder_peer_id: mentee_peer_id} - each Elder can have one Mentee
var eternal_flame_location: Vector2i = Vector2i(0, 0)  # Hidden location, moves when found
# realm_treasury is now persisted via persistence.get_realm_treasury() / persistence.add_to_realm_treasury()
var pilgrimage_shrines: Dictionary = {}    # {peer_id: {blood: Vector2i, mind: Vector2i, wealth: Vector2i}}

# Dungeon system state
var active_dungeons: Dictionary = {}  # instance_id -> dungeon_instance data
var dungeon_floors: Dictionary = {}   # instance_id -> {floor_num: grid_data}
var next_dungeon_id: int = 1
const MAX_ACTIVE_DUNGEONS = 10
const DUNGEON_SPAWN_CHECK_INTERVAL = 1800.0  # 30 minutes
var dungeon_spawn_timer: float = 0.0

# Tax collector cooldown tracking (peer_id -> steps since last encounter)
var tax_collector_cooldowns: Dictionary = {}  # peer_id -> steps remaining
const TAX_COLLECTOR_COOLDOWN_STEPS = 50  # Minimum steps between tax encounters

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

	# Spawn initial dungeons
	log_message("Spawning initial dungeons...")
	_check_dungeon_spawns()

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

	# Connect pending update buttons
	if pending_update_button:
		pending_update_button.pressed.connect(_on_pending_update_pressed)
	if cancel_update_button:
		cancel_update_button.pressed.connect(_on_cancel_update_pressed)

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

func _on_pending_update_pressed():
	"""Start the 5-minute shutdown countdown."""
	if pending_update_active:
		return  # Already counting down

	pending_update_active = true
	pending_update_seconds_remaining = 300.0  # 5 minutes
	pending_update_last_announcement = -1

	# Update button visibility
	if pending_update_button:
		pending_update_button.visible = false
	if cancel_update_button:
		cancel_update_button.visible = true

	log_message("[SHUTDOWN] Pending update initiated - server will shut down in 5 minutes")
	_send_broadcast("⚠️ SERVER SHUTDOWN: The server will shut down for updates in 5 minutes. Please find a safe place!")

func _on_cancel_update_pressed():
	"""Cancel the pending shutdown."""
	if not pending_update_active:
		return

	pending_update_active = false
	pending_update_seconds_remaining = 0.0
	pending_update_last_announcement = -1

	# Update button visibility
	if pending_update_button:
		pending_update_button.visible = true
	if cancel_update_button:
		cancel_update_button.visible = false

	log_message("[SHUTDOWN] Pending update cancelled")
	_send_broadcast("✅ SERVER UPDATE CANCELLED: The scheduled shutdown has been cancelled. Carry on adventuring!")

func _check_pending_update_announcements():
	"""Check if we need to send a countdown announcement."""
	var seconds = int(pending_update_seconds_remaining)

	# Define announcement points (in seconds)
	# 5min=300, 4min=240, 3min=180, 2min=120, 1min=60, 30sec=30
	var announcement_made = false

	if seconds <= 30 and pending_update_last_announcement != 30:
		_send_broadcast("⚠️ SERVER SHUTDOWN IN 30 SECONDS! Find safety NOW!")
		pending_update_last_announcement = 30
		announcement_made = true
	elif seconds <= 60 and seconds > 30 and pending_update_last_announcement != 60:
		_send_broadcast("⚠️ SERVER SHUTDOWN: 1 minute remaining!")
		pending_update_last_announcement = 60
		announcement_made = true
	elif seconds <= 120 and seconds > 60 and pending_update_last_announcement != 120:
		_send_broadcast("⚠️ SERVER SHUTDOWN: 2 minutes remaining. Find a safe place!")
		pending_update_last_announcement = 120
		announcement_made = true
	elif seconds <= 180 and seconds > 120 and pending_update_last_announcement != 180:
		_send_broadcast("⚠️ SERVER SHUTDOWN: 3 minutes remaining.")
		pending_update_last_announcement = 180
		announcement_made = true
	elif seconds <= 240 and seconds > 180 and pending_update_last_announcement != 240:
		_send_broadcast("⚠️ SERVER SHUTDOWN: 4 minutes remaining.")
		pending_update_last_announcement = 240
		announcement_made = true

	# Update button text to show countdown
	if pending_update_button and announcement_made:
		var mins = seconds / 60
		var secs = seconds % 60
		log_message("[SHUTDOWN] %d:%02d remaining" % [mins, secs])

func _execute_pending_shutdown():
	"""Execute the server shutdown after countdown expires."""
	log_message("[SHUTDOWN] Executing server shutdown...")
	_send_broadcast("🔌 SERVER SHUTTING DOWN NOW. See you after the update!")

	# Save all characters before shutdown
	save_all_active_characters()

	# Give a moment for the broadcast to be sent
	await get_tree().create_timer(1.0).timeout

	# Disconnect all peers gracefully
	for peer_id in peers.keys():
		var peer = peers[peer_id]
		if peer.connection:
			peer.connection.disconnect_from_host()

	# Close the server
	server.stop()

	# Quit the application
	get_tree().quit()

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

	# Process pending update countdown
	if pending_update_active:
		pending_update_seconds_remaining -= delta
		_check_pending_update_announcements()
		if pending_update_seconds_remaining <= 0:
			_execute_pending_shutdown()

	# Dungeon spawn timer - periodically spawn new dungeons
	dungeon_spawn_timer += delta
	if dungeon_spawn_timer >= DUNGEON_SPAWN_CHECK_INTERVAL:
		dungeon_spawn_timer = 0.0
		_check_dungeon_spawns()

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
		"get_monster_kills_leaderboard":
			handle_get_monster_kills_leaderboard(peer_id, message)
		"get_trophy_leaderboard":
			handle_get_trophy_leaderboard(peer_id)
		"chat":
			handle_chat(peer_id, message)
		"private_message":
			handle_private_message(peer_id, message)
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
		"toggle_swap_attack":
			handle_toggle_swap_attack(peer_id, message)
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
		# Companion system handlers
		"activate_companion":
			handle_activate_companion(peer_id, message)
		"dismiss_companion":
			handle_dismiss_companion(peer_id)
		# Fishing system handlers
		"fish_start":
			handle_fish_start(peer_id)
		"fish_catch":
			handle_fish_catch(peer_id, message)
		# Mining system handlers
		"mine_start":
			handle_mine_start(peer_id)
		"mine_catch":
			handle_mine_catch(peer_id, message)
		# Logging system handlers
		"log_start":
			handle_log_start(peer_id)
		"log_catch":
			handle_log_catch(peer_id, message)
		# Crafting system handlers
		"craft_list":
			handle_craft_list(peer_id, message)
		"craft_item":
			handle_craft_item(peer_id, message)
		# Dungeon system handlers
		"dungeon_list":
			handle_dungeon_list(peer_id)
		"dungeon_enter":
			handle_dungeon_enter(peer_id, message)
		"dungeon_move":
			handle_dungeon_move(peer_id, message)
		"dungeon_exit":
			handle_dungeon_exit(peer_id)
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
		# Pilgrimage system handlers
		"pilgrimage_donate":
			handle_pilgrimage_donate(peer_id, message)
		"summon_response":
			handle_summon_response(peer_id, message)
		"start_crucible":
			handle_start_crucible(peer_id)
		# Wandering NPC encounter handlers
		"blacksmith_choice":
			handle_blacksmith_choice(peer_id, message)
		"healer_choice":
			handle_healer_choice(peer_id, message)
		# Bug report handler
		"bug_report":
			handle_bug_report(peer_id, message)
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
		"max_characters": 6
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

	# === BALANCE MIGRATION v0.8.5 ===
	# Move existing characters to safety on first login after balance changes
	if not character.balance_migrated_v085:
		var old_x = character.x
		var old_y = character.y
		# Teleport to a safe spot near 0,0 (within the expanded safe zone)
		character.x = randi_range(-5, 5)
		character.y = randi_range(-5, 5)  # Start near Crossroads trading post
		character.balance_migrated_v085 = true
		# Recalculate stats with new formulas
		character.calculate_derived_stats()
		log_message("Balance migration: %s moved from (%d,%d) to (%d,%d)" % [char_name, old_x, old_y, character.x, character.y])
		# Save the character immediately with migration flag
		persistence.save_character(account_id, character)

	# === TITLE ITEM MIGRATION ===
	# Fix any corrupted title items (e.g., Jarl's Ring themed as "Jarl's Band" with stats)
	if _migrate_title_items(character):
		persistence.save_character(account_id, character)

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
			"message": "Maximum characters reached (6)"
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
	var valid_races = ["Dwarf", "Elf", "Gnome", "Halfling", "Human", "Ogre", "Orc", "Undead"]
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

func handle_get_monster_kills_leaderboard(peer_id: int, message: Dictionary):
	var limit = message.get("limit", 20)
	limit = clamp(limit, 1, 100)

	var entries = persistence.get_monster_kills_leaderboard(limit)

	send_to_peer(peer_id, {
		"type": "monster_kills_leaderboard",
		"entries": entries
	})

func handle_get_trophy_leaderboard(peer_id: int):
	var entries = persistence.get_trophy_leaderboard()

	send_to_peer(peer_id, {
		"type": "trophy_leaderboard",
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

	# Check if requester has a title (for location viewing privilege)
	var requester_has_title = false
	if characters.has(peer_id):
		var requester = characters[peer_id]
		requester_has_title = requester.title in ["jarl", "high_king"]

	# Find the target player
	for pid in characters.keys():
		var char = characters[pid]
		if char.name.to_lower() == target_name.to_lower():
			var bonuses = char.get_equipment_bonuses()
			var is_cloaked = char.has_buff("cloak") or char.has_buff("invisibility")
			var result = {
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
				"in_combat": combat_mgr.is_in_combat(pid),
				"cloak_active": is_cloaked,
				"gold": char.gold,
				"gems": char.gems,
				"title": char.title,
				"deaths": char.deaths,
				"quests_completed": char.quests_completed.size() if char.quests_completed else 0,
				"play_time": char.play_time
			}
			# Title holders can see player locations (unless cloaked)
			if requester_has_title:
				result["viewer_has_title"] = true
				if not is_cloaked:
					result["location_x"] = char.x
					result["location_y"] = char.y
				else:
					result["location_hidden"] = true
			send_to_peer(peer_id, result)
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

func handle_private_message(peer_id: int, message: Dictionary):
	"""Handle sending a private message to another player"""
	if not peers[peer_id].authenticated:
		return

	if not characters.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You must have a character to send messages!"})
		return

	var target_name = message.get("target", "")
	var text = message.get("message", "")

	if target_name.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "No target specified!"})
		return

	if text.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Message cannot be empty!"})
		return

	# Get sender's character name
	var sender_name = characters[peer_id].name

	# Can't message yourself
	if target_name.to_lower() == sender_name.to_lower():
		send_to_peer(peer_id, {"type": "error", "message": "You cannot whisper to yourself!"})
		return

	# Find the target player (case-insensitive match)
	var target_peer_id = -1
	for other_peer_id in characters.keys():
		if characters[other_peer_id].name.to_lower() == target_name.to_lower():
			target_peer_id = other_peer_id
			target_name = characters[other_peer_id].name  # Get actual name with correct casing
			break

	if target_peer_id == -1:
		send_to_peer(peer_id, {"type": "error", "message": "%s is not online!" % target_name})
		return

	# Get sender's title prefix if they have one
	var sender_display = sender_name
	if not characters[peer_id].title.is_empty():
		sender_display = TitlesScript.format_titled_name(sender_name, characters[peer_id].title)

	# Send to target
	send_to_peer(target_peer_id, {
		"type": "private_message",
		"sender": sender_display,
		"sender_name": sender_name,
		"message": text
	})

	# Send confirmation to sender
	send_to_peer(peer_id, {
		"type": "private_message_sent",
		"target": target_name,
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
	# Resource regen is DISABLED while cloaked - cloak drains resources
	var regen_percent = 0.02  # 2% per move for resources
	var hp_regen_percent = 0.01  # 1% per move for health
	var total_max_mana = character.get_total_max_mana()
	var total_max_stamina = character.get_total_max_stamina()
	var total_max_energy = character.get_total_max_energy()
	character.current_hp = min(character.get_total_max_hp(), character.current_hp + max(1, int(character.get_total_max_hp() * hp_regen_percent)))
	if not character.cloak_active:
		# Only regenerate resources when NOT cloaked
		character.current_mana = min(total_max_mana, character.current_mana + max(1, int(total_max_mana * regen_percent)))
		character.current_stamina = min(total_max_stamina, character.current_stamina + max(1, int(total_max_stamina * regen_percent)))
		character.current_energy = min(total_max_energy, character.current_energy + max(1, int(total_max_energy * regen_percent)))

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
		if poison_dmg != 0:
			var turns_left = character.poison_turns_remaining
			var poison_msg = ""
			if poison_dmg < 0:
				# Undead: poison heals instead of damages
				var heal_amount = -poison_dmg
				character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
				poison_msg = "[color=#708090]Your undead form absorbs the poison, healing [color=#00FF00]%d HP[/color][/color]" % heal_amount
			else:
				character.current_hp -= poison_dmg
				character.current_hp = max(1, character.current_hp)  # Poison can't kill
				poison_msg = "[color=#00FF00]Poison[/color] deals [color=#FF4444]%d damage[/color]" % poison_dmg
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

	# Process egg incubation - each movement step counts toward hatching
	if character.incubating_eggs.size() > 0:
		var hatched = character.process_egg_steps(1)
		for companion in hatched:
			send_to_peer(peer_id, {
				"type": "egg_hatched",
				"companion": companion,
				"message": "[color=#A335EE]✦ Your %s Egg has hatched! ✦[/color]" % companion.name
			})
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FF00]%s is now your companion![/color] Use /companion to manage companions." % companion.name
			})

	# Send location and character updates
	send_location_update(peer_id)
	send_character_update(peer_id)

	# Notify nearby players of the movement (so they see us on their map)
	send_nearby_players_map_update(peer_id, old_x, old_y)

	# Check for tax collector encounter (before trading post - can happen anywhere)
	if check_tax_collector_encounter(peer_id):
		send_character_update(peer_id)  # Update gold display

	# Check for wandering blacksmith encounter (3% when player has damaged gear)
	if check_blacksmith_encounter(peer_id):
		return  # Wait for player response before continuing

	# Check for wandering healer encounter (4% when HP < 80%)
	if check_healer_encounter(peer_id):
		return  # Wait for player response before continuing

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
		if poison_dmg != 0:
			var turns_left = character.poison_turns_remaining
			var poison_msg = ""
			if poison_dmg < 0:
				# Undead: poison heals instead of damages
				var heal_amount = -poison_dmg
				character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
				poison_msg = "[color=#708090]Your undead form absorbs the poison, healing [color=#00FF00]%d HP[/color][/color]" % heal_amount
			else:
				character.current_hp -= poison_dmg
				character.current_hp = max(1, character.current_hp)  # Poison can't kill
				poison_msg = "[color=#00FF00]Poison[/color] deals [color=#FF4444]%d damage[/color]" % poison_dmg
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

	# Tax collector check removed from hunting - only happens on movement
	# to prevent double-checking (was causing excessive encounters)

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

	# Track if cloak was dropped for message combining
	var cloak_was_dropped = false

	# Break cloak if active - resting reveals you
	if character.cloak_active:
		character.cloak_active = false
		cloak_was_dropped = true
		# Send status_effect to update client cloak state and action bar
		send_to_peer(peer_id, {
			"type": "status_effect",
			"effect": "cloak_dropped",
			"message": ""  # Message will be combined with rest message below
		})

	# Mages use Meditate instead of Rest
	if is_mage:
		_handle_meditate(peer_id, character, cloak_was_dropped)
		return

	# Regenerate primary resource on rest (same as movement - 2%, min 1)
	var regen_percent = 0.02
	var total_max_stamina = character.get_total_max_stamina()
	var total_max_energy = character.get_total_max_energy()
	var stamina_regen = max(1, int(total_max_stamina * regen_percent))
	var energy_regen = max(1, int(total_max_energy * regen_percent))
	character.current_stamina = min(total_max_stamina, character.current_stamina + stamina_regen)
	character.current_energy = min(total_max_energy, character.current_energy + energy_regen)

	# Non-mages: Check if HP is already full
	var hp_full = character.current_hp >= character.get_total_max_hp()
	var heal_amount = 0

	if not hp_full:
		# Restore 10-25% of max HP
		var heal_percent = randf_range(0.10, 0.25)
		heal_amount = int(character.get_total_max_hp() * heal_percent)
		heal_amount = max(1, heal_amount)  # At least 1 HP
		character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)

	# Build rest message with resource info
	var rest_msg = ""
	# Include cloak drop message if applicable
	if cloak_was_dropped:
		rest_msg = "[color=#9932CC]Your cloak fades as you rest.[/color]\n"
	if hp_full:
		rest_msg += "[color=#00FF00]You rest"
	else:
		rest_msg += "[color=#00FF00]You rest and recover %d HP" % heal_amount

	# Show resource regen based on class path
	if class_type in ["Fighter", "Barbarian", "Paladin"]:
		rest_msg += " and %d Stamina" % stamina_regen
	elif class_type in ["Thief", "Ranger", "Ninja", "Trickster"]:
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

func _handle_meditate(peer_id: int, character: Character, cloak_was_dropped: bool = false):
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

	var total_max_mana = character.get_total_max_mana()
	var mana_regen = int(total_max_mana * mana_percent)
	mana_regen = max(1, mana_regen)
	character.current_mana = min(total_max_mana, character.current_mana + mana_regen)

	var meditate_msg = ""
	var bonus_text = ""
	if meditate_bonus > 0 and sage_meditate_bonus > 0:
		bonus_text = " [color=#66CCCC](+%d%% from gear)[/color][color=#20B2AA](+%d%% Mana Mastery)[/color]" % [meditate_bonus, int(sage_meditate_bonus * 100)]
	elif meditate_bonus > 0:
		bonus_text = " [color=#66CCCC](+%d%% from gear)[/color]" % meditate_bonus
	elif sage_meditate_bonus > 0:
		bonus_text = " [color=#20B2AA](+%d%% Mana Mastery)[/color]" % int(sage_meditate_bonus * 100)

	# Include cloak drop message if applicable
	var cloak_prefix = ""
	if cloak_was_dropped:
		cloak_prefix = "[color=#9932CC]Your cloak fades as you meditate.[/color]\n"

	if at_full_hp:
		# Full HP: focus entirely on mana
		meditate_msg = "%s[color=#66CCCC]You meditate deeply and recover %d Mana.%s[/color]" % [cloak_prefix, mana_regen, bonus_text]
	else:
		# Not full HP: also heal
		var heal_percent = randf_range(0.10, 0.25)
		var heal_amount = int(character.get_total_max_hp() * heal_percent)
		heal_amount = max(1, heal_amount)
		character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
		meditate_msg = "%s[color=#66CCCC]You meditate and recover %d HP and %d Mana.%s[/color]" % [cloak_prefix, heal_amount, mana_regen, bonus_text]

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

			# Track pilgrimage progress for Elders
			var char = characters[peer_id]
			if char.title == "elder" and not char.pilgrimage_progress.is_empty():
				var monster_lvl = result.get("monster_level", 1)
				var monster_tier = drop_tables.get_tier_for_level(monster_lvl)
				var was_outsmart = result.get("victory_type", "") == "outsmart"

				# Track kills for awakening stage
				char.add_pilgrimage_kills(1)

				# Track tier 8+ kills for Trial of Blood
				if monster_tier >= 8:
					char.add_pilgrimage_tier8_kills(1)

				# Track outsmarts for Trial of Mind
				if was_outsmart:
					char.add_pilgrimage_outsmarts(1)

				# Roll for ember drops (Stage 3: Ember Hunt)
				if char.get_pilgrimage_stage() == "ember_hunt":
					var ember_roll = randf()
					var embers_earned = 0
					var is_rare = result.get("is_rare_variant", false)
					var is_boss = result.get("is_boss", false)

					if is_boss and monster_tier >= 9:
						# Boss T9+: guaranteed 5 embers
						embers_earned = 5
					elif is_rare:
						# Rare variants: guaranteed 2 embers
						embers_earned = 2
					elif monster_tier >= 9 and ember_roll < TitlesScript.EMBER_DROP_RATES.tier9.chance:
						embers_earned = randi_range(TitlesScript.EMBER_DROP_RATES.tier9.min, TitlesScript.EMBER_DROP_RATES.tier9.max)
					elif monster_tier >= 8 and ember_roll < TitlesScript.EMBER_DROP_RATES.tier8.chance:
						embers_earned = TitlesScript.EMBER_DROP_RATES.tier8.min

					if embers_earned > 0:
						char.add_pilgrimage_embers(embers_earned)
						send_to_peer(peer_id, {
							"type": "text",
							"message": "[color=#FF6600]You found %d Flame Ember%s! (%d/%d)[/color]" % [
								embers_earned,
								"s" if embers_earned > 1 else "",
								char.pilgrimage_progress.get("embers", 0),
								TitlesScript.PILGRIMAGE_STAGES["ember_hunt"].requirement
							]
						})

			# Handle crucible victory (Stage 4)
			if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
				var monster_data = result.get("monster", {})
				if monster_data.get("is_crucible", false):
					handle_crucible_victory(peer_id)

			# Record monster knowledge (player now knows this monster type's HP at this level)
			var killed_monster_name = result.get("monster_name", "")
			var killed_monster_level = result.get("monster_level", 1)
			if killed_monster_name != "":
				characters[peer_id].record_monster_kill(killed_monster_name, killed_monster_level)

			# Check quest progress for kill-based quests
			var monster_level_for_quest = result.get("monster_level", 1)
			check_kill_quest_progress(peer_id, monster_level_for_quest, killed_monster_name)

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

				# Roll for companion egg drop
				var egg_drop = drop_tables.roll_egg_drop(killed_monster_name, _get_monster_tier(killed_monster_level))
				if not egg_drop.is_empty():
					all_drops.append({
						"type": "companion_egg",
						"name": egg_drop.get("name", "Mysterious Egg"),
						"egg_data": egg_drop,
						"rarity": "epic"  # Eggs are always epic rarity for display
					})

				# Roll for crafting material drop
				var material_drop = drop_tables.roll_crafting_material_drop(_get_monster_tier(killed_monster_level))
				if not material_drop.is_empty():
					all_drops.append({
						"type": "crafting_material",
						"material_id": material_drop.material_id,
						"quantity": material_drop.quantity,
						"rarity": "uncommon"
					})

				# Give all drops to player now
				var drop_messages = []
				var drop_data = []  # For client sound effects
				var player_level = characters[peer_id].level
				for item in all_drops:
					# Special handling for companion eggs
					if item.get("type", "") == "companion_egg":
						var egg_data = item.get("egg_data", {})
						var egg_result = characters[peer_id].add_egg(egg_data)
						if egg_result.success:
							drop_messages.append("[color=#A335EE]✦ COMPANION EGG: %s[/color]" % egg_data.get("name", "Mysterious Egg"))
							drop_messages.append("[color=#808080]  Walk %d steps to hatch it![/color]" % egg_data.get("hatch_steps", 100))
							drop_data.append({"rarity": "epic", "level": 1, "level_diff": 0, "is_egg": true})
						else:
							drop_messages.append("[color=#FF4444]Egg Lost: %s (%s)[/color]" % [egg_data.get("name", "Egg"), egg_result.message])
					# Special handling for crafting materials
					elif item.get("type", "") == "crafting_material":
						var mat_id = item.get("material_id", "")
						var quantity = item.get("quantity", 1)
						var mat_info = CraftingDatabaseScript.get_material(mat_id)
						var mat_name = mat_info.get("name", mat_id) if not mat_info.is_empty() else mat_id
						characters[peer_id].add_crafting_material(mat_id, quantity)
						var qty_text = " x%d" % quantity if quantity > 1 else ""
						drop_messages.append("[color=#1EFF00]◆ MATERIAL: %s%s[/color]" % [mat_name, qty_text])
						drop_data.append({"rarity": "uncommon", "level": 1, "level_diff": 0, "is_material": true})
					elif characters[peer_id].can_add_item():
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

				# Handle dungeon combat victory - clear tile and send updated state
				var combat_state = combat_mgr.get_active_combat(peer_id)
				if combat_state and combat_state.get("is_dungeon_combat", false):
					var character = characters[peer_id]
					if character.in_dungeon:
						var is_boss = combat_state.get("is_boss_fight", false)
						_clear_dungeon_tile(peer_id)
						if is_boss:
							# Boss defeated - complete dungeon
							_complete_dungeon(peer_id)
						else:
							# Regular encounter - send updated dungeon state
							_send_dungeon_state(peer_id)

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

			# Always send combat_end for flee
			send_to_peer(peer_id, {
				"type": "combat_end",
				"fled": true,
				"new_x": characters[peer_id].x,
				"new_y": characters[peer_id].y
			})

			# Check if fleeing from dungeon - also eject from dungeon
			var character = characters[peer_id]
			if character.in_dungeon:
				var dungeon_name = ""
				var instance_id = character.current_dungeon_id
				if active_dungeons.has(instance_id):
					dungeon_name = active_dungeons[instance_id].get("name", "Dungeon")
				character.exit_dungeon()
				save_character(peer_id)
				send_to_peer(peer_id, {
					"type": "dungeon_exit",
					"reason": "fled",
					"dungeon_name": dungeon_name
				})
		elif result.get("monster_fled", false):
			# Monster fled - check if it summoned a replacement (Shrieker behavior)
			var summon_next = result.get("summon_next_fight", "")
			if summon_next != "":
				# Summoner fled but called reinforcements - queue flock encounter
				var monster_level = result.get("monster_level", characters[peer_id].level)

				# Track flock count for visual variety
				if not flock_counts.has(peer_id):
					flock_counts[peer_id] = 1
				else:
					flock_counts[peer_id] += 1

				# Queue the summoned monster as a pending flock
				pending_flocks[peer_id] = {
					"monster_name": summon_next,
					"monster_level": monster_level,
					"flock_count": flock_counts[peer_id]
				}

				# End current combat and notify about incoming monster
				send_to_peer(peer_id, {
					"type": "combat_end",
					"monster_fled": true,
					"character": characters[peer_id].to_dict(),
					"flock_incoming": true,
					"flock_message": "[color=#FF4444]A %s answers the call! Press Continue to face it.[/color]" % summon_next
				})
				save_character(peer_id)
			else:
				# Regular monster fled (coward ability) - combat ends, no loot
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

	# Check for Guardian death save (granted by Eternal)
	if character.guardian_death_save:
		character.guardian_death_save = false
		character.guardian_granted_by = ""
		character.current_hp = int(character.get_total_max_hp() * 0.25)  # Survive with 25% HP
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]The Guardian's blessing protects you from death![/color]"
		})
		# Handle crucible death if in crucible - reset progress
		if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
			handle_crucible_death(peer_id)
		send_character_update(peer_id)
		save_character(peer_id)
		return  # Don't actually die

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
		# Handle crucible death if in crucible - reset progress
		if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
			handle_crucible_death(peer_id)
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
			# Handle crucible death if in crucible - reset progress
			if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
				handle_crucible_death(peer_id)
			send_character_update(peer_id)
			save_character(peer_id)
			return  # Don't actually die

	# Handle crucible death if in crucible before actual permadeath
	if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
		handle_crucible_death(peer_id)

	# Handle title loss on death
	if not character.title.is_empty():
		var lost_title = character.title
		broadcast_title_change(character.name, lost_title, "lost")
		_update_title_holders_on_logout(peer_id)
		character.title = ""
		character.title_data = {}

	# Clear dungeon state if player was in a dungeon
	if character.in_dungeon:
		character.exit_dungeon()

	print("PERMADEATH: %s (Level %d) killed by %s" % [character.name, character.level, cause_of_death])

	# Record monster kill for Monster Kills leaderboard
	persistence.record_monster_kill(cause_of_death)

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

	# Get nearby dungeon entrances for map display
	var dungeon_locations = get_visible_dungeons(character.x, character.y, vision_radius)

	# Get complete map display (includes location info at top)
	var map_display = world_system.generate_map_display(character.x, character.y, vision_radius, nearby_players, dungeon_locations)

	# Check if player is at a fishable water tile
	var is_at_water = world_system.is_fishing_spot(character.x, character.y)
	var water_type = world_system.get_fishing_type(character.x, character.y) if is_at_water else ""

	# Check if player is at an ore deposit (mining)
	var is_at_ore = world_system.is_ore_deposit(character.x, character.y)
	var current_ore_tier = world_system.get_ore_tier(character.x, character.y) if is_at_ore else 1

	# Check if player is at a dense forest (logging)
	var is_at_forest = world_system.is_dense_forest(character.x, character.y)
	var current_wood_tier = world_system.get_wood_tier(character.x, character.y) if is_at_forest else 1

	# Check if player is at a dungeon entrance
	var dungeon_entrance = _get_dungeon_at_location(character.x, character.y)
	var at_dungeon = not dungeon_entrance.is_empty()

	# Send map display as description
	send_to_peer(peer_id, {
		"type": "location",
		"x": character.x,
		"y": character.y,
		"description": map_display,
		"at_water": is_at_water,
		"water_type": water_type,
		"at_ore_deposit": is_at_ore,
		"ore_tier": current_ore_tier,
		"at_dense_forest": is_at_forest,
		"wood_tier": current_wood_tier,
		"at_dungeon": at_dungeon,
		"dungeon_info": dungeon_entrance
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

func _trigger_specific_encounter(peer_id: int, monster_name: String, monster_level: int):
	"""Trigger an encounter with a specific monster (used for summoner abilities like Shrieker)"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Generate the specific monster at the given level
	var monster = monster_db.generate_monster_by_name(monster_name, monster_level)

	var result = combat_mgr.start_combat(peer_id, character, monster)

	if result.success:
		var combat_monster_name = result.combat_state.get("monster_name", "")
		var combat_bg_color = combat_mgr.get_monster_combat_bg_color(combat_monster_name)

		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": result.message,
			"combat_state": result.combat_state,
			"combat_bg_color": combat_bg_color,
			"use_client_art": true
		})
		forward_combat_start_to_watchers(peer_id, result.message, combat_monster_name, combat_bg_color)

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

	save_character(peer_id)

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

func check_tax_collector_encounter(peer_id: int) -> bool:
	"""Check for and handle a tax collector encounter. Returns true if encounter occurred."""
	if not characters.has(peer_id):
		return false

	var character = characters[peer_id]

	# Check cooldown first - decrement and skip if still on cooldown
	if tax_collector_cooldowns.has(peer_id):
		tax_collector_cooldowns[peer_id] -= 1
		if tax_collector_cooldowns[peer_id] > 0:
			return false
		else:
			tax_collector_cooldowns.erase(peer_id)

	# Check if player is tax-immune (Jarl or High King)
	if TitlesScript.is_title_tax_immune(character.title):
		# Small chance to show immunity flavor
		if randf() < 0.02:  # 2% chance to show message
			var title_name = TitlesScript.get_title_name(character.title)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#808080]A Tax Collector approaches... then recognizes your sigil.[/color]"
			})
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#C0C0C0]'My %s! Forgive my intrusion. The realm prospers under your rule.'[/color]" % title_name
			})
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FF00]He bows and leaves without collecting.[/color]"
			})
		return false

	# Check encounter rate (halved from 5% to 2.5% and only on movement now)
	if randf() >= TitlesScript.TAX_COLLECTOR.encounter_rate * 0.5:
		return false

	# Check minimum gold
	if character.gold < TitlesScript.TAX_COLLECTOR.minimum_gold:
		return false

	# Select a random encounter type
	var encounters = TitlesScript.TAX_ENCOUNTERS
	var encounter = encounters[randi() % encounters.size()]
	var encounter_type = encounter.get("type", "quick")

	# Calculate tax amount
	var tax_rate = TitlesScript.TAX_COLLECTOR.tax_rate
	if encounter.has("tax_modifier"):
		tax_rate *= encounter.tax_modifier
	var tax_amount = max(TitlesScript.TAX_COLLECTOR.minimum_tax, int(character.gold * tax_rate))

	# Deduct gold and add to treasury (persisted)
	character.gold -= tax_amount
	persistence.add_to_realm_treasury(tax_amount)

	# Build encounter message
	var full_message = ""
	var messages = encounter.get("messages", [])
	for i in range(messages.size()):
		var msg = messages[i]
		# Replace %d placeholder with tax amount
		if "%d" in msg:
			msg = msg % tax_amount
		full_message += "[color=#DAA520]%s[/color]\n" % msg

	# Handle special bonuses (like the negotiator's gold find buff)
	if encounter.has("bonus"):
		var bonus = encounter.bonus
		if bonus.type == "gold_find":
			character.add_persistent_buff("gold_find", bonus.value, bonus.battles)
			full_message += "[color=#00FF00]+%d%% gold find for %d battles![/color]\n" % [bonus.value, bonus.battles]

	# Send as NPC encounter that requires acknowledgment
	send_to_peer(peer_id, {
		"type": "npc_encounter",
		"npc_type": "tax_collector",
		"message": full_message.strip_edges(),
		"character": character.to_dict()
	})

	log_message("Tax collector: %s paid %d gold (treasury now %d)" % [character.name, tax_amount, persistence.get_realm_treasury()])
	save_character(peer_id)

	# Set cooldown to prevent back-to-back encounters
	tax_collector_cooldowns[peer_id] = TAX_COLLECTOR_COOLDOWN_STEPS

	return true

# Track pending blacksmith/healer encounters (peer_id -> repair costs/heal costs)
var pending_blacksmith_encounters: Dictionary = {}
var pending_healer_encounters: Dictionary = {}

func check_blacksmith_encounter(peer_id: int) -> bool:
	"""Check for a wandering blacksmith encounter. Returns true if encounter occurred."""
	if not characters.has(peer_id):
		return false

	var character = characters[peer_id]

	# 3% encounter rate
	if randf() >= 0.03:
		return false

	# Check if player has damaged gear
	var damaged_items = []
	var total_repair_cost = 0

	for slot_name in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = character.equipped.get(slot_name)
		if item and item.has("wear"):
			var wear = item.get("wear", 0)
			if wear > 0:
				var item_level = item.get("level", 1)
				var repair_cost = int(wear * item_level * 5)
				damaged_items.append({
					"slot": slot_name,
					"name": item.get("name", slot_name.capitalize()),
					"wear": wear,
					"cost": repair_cost
				})
				total_repair_cost += repair_cost

	# No damaged gear - no encounter
	if damaged_items.size() == 0:
		return false

	# Store encounter data for when player responds
	var repair_all_cost = int(total_repair_cost * 0.9)  # 10% discount for full repair
	pending_blacksmith_encounters[peer_id] = {
		"items": damaged_items,
		"total_cost": total_repair_cost,
		"repair_all_cost": repair_all_cost
	}

	# Send encounter message
	send_to_peer(peer_id, {
		"type": "blacksmith_encounter",
		"message": "[color=#DAA520]A wandering Blacksmith stops you on the road.[/color]\n'I can fix up that gear for you, traveler. Fair prices.'",
		"items": damaged_items,
		"repair_all_cost": repair_all_cost,
		"player_gold": character.gold
	})

	return true

func handle_blacksmith_choice(peer_id: int, message: Dictionary):
	"""Handle player's choice for blacksmith encounter."""
	if not characters.has(peer_id):
		return
	if not pending_blacksmith_encounters.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "No blacksmith encounter pending."})
		return

	var character = characters[peer_id]
	var encounter = pending_blacksmith_encounters[peer_id]
	var choice = message.get("choice", "decline")

	if choice == "decline":
		pending_blacksmith_encounters.erase(peer_id)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]The Blacksmith nods and continues on his way.[/color]"
		})
		send_to_peer(peer_id, {"type": "blacksmith_done"})
		return

	if choice == "repair_all":
		var cost = encounter.repair_all_cost
		if character.gold < cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough gold! (Need %d)" % cost})
			return

		character.gold -= cost
		# Repair all items
		for item_data in encounter.items:
			var slot = item_data.slot
			if character.equipped.has(slot):
				character.equipped[slot]["wear"] = 0

		pending_blacksmith_encounters.erase(peer_id)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]The Blacksmith repairs all your gear for %d gold (10%% discount!).[/color]" % cost
		})
		send_to_peer(peer_id, {"type": "blacksmith_done"})
		save_character(peer_id)
		send_character_update(peer_id)
		return

	if choice == "repair_single":
		var slot = message.get("slot", "")
		var item_data = null
		for item in encounter.items:
			if item.slot == slot:
				item_data = item
				break

		if not item_data:
			send_to_peer(peer_id, {"type": "error", "message": "Invalid item slot."})
			return

		var cost = item_data.cost
		if character.gold < cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough gold! (Need %d)" % cost})
			return

		character.gold -= cost
		character.equipped[slot]["wear"] = 0

		# Update encounter data
		encounter.items.erase(item_data)
		encounter.total_cost -= cost
		encounter.repair_all_cost = int(encounter.total_cost * 0.9)

		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]The Blacksmith repairs your %s for %d gold.[/color]" % [item_data.name, cost]
		})

		if encounter.items.size() == 0:
			# All items repaired
			pending_blacksmith_encounters.erase(peer_id)
			send_to_peer(peer_id, {"type": "blacksmith_done"})
		else:
			# Send updated encounter
			send_to_peer(peer_id, {
				"type": "blacksmith_encounter",
				"message": "[color=#DAA520]'Anything else need fixing?'[/color]",
				"items": encounter.items,
				"repair_all_cost": encounter.repair_all_cost,
				"player_gold": character.gold
			})

		save_character(peer_id)
		send_character_update(peer_id)

func check_healer_encounter(peer_id: int) -> bool:
	"""Check for a wandering healer encounter. Returns true if encounter occurred."""
	if not characters.has(peer_id):
		return false

	var character = characters[peer_id]

	# 4% encounter rate
	if randf() >= 0.04:
		return false

	# Only trigger if HP < 80%
	var hp_percent = float(character.current_hp) / float(character.max_hp)
	if hp_percent >= 0.80:
		return false

	# Calculate heal costs based on player level (reduced 10% for economy balance)
	var level = character.level
	var quick_heal_cost = level * 22
	var full_heal_cost = level * 90
	var cure_all_cost = level * 180

	# Check for debuffs
	var has_debuffs = character.persistent_buffs.size() > 0

	# Store encounter data
	pending_healer_encounters[peer_id] = {
		"quick_heal_cost": quick_heal_cost,
		"full_heal_cost": full_heal_cost,
		"cure_all_cost": cure_all_cost,
		"has_debuffs": has_debuffs
	}

	# Send encounter message
	send_to_peer(peer_id, {
		"type": "healer_encounter",
		"message": "[color=#00FF00]A wandering Healer approaches, their staff glowing softly.[/color]\n'You look injured, traveler. Let me help.'",
		"quick_heal_cost": quick_heal_cost,
		"full_heal_cost": full_heal_cost,
		"cure_all_cost": cure_all_cost,
		"has_debuffs": has_debuffs,
		"player_gold": character.gold,
		"current_hp": character.hp,
		"max_hp": character.max_hp
	})

	return true

func handle_healer_choice(peer_id: int, message: Dictionary):
	"""Handle player's choice for healer encounter."""
	if not characters.has(peer_id):
		return
	if not pending_healer_encounters.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "No healer encounter pending."})
		return

	var character = characters[peer_id]
	var encounter = pending_healer_encounters[peer_id]
	var choice = message.get("choice", "decline")

	pending_healer_encounters.erase(peer_id)

	if choice == "decline":
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]The Healer bows and fades into the distance.[/color]"
		})
		send_to_peer(peer_id, {"type": "healer_done"})
		return

	var cost = 0
	var heal_amount = 0
	var heal_percent = 0
	var cure_debuffs = false

	match choice:
		"quick":
			cost = encounter.quick_heal_cost
			heal_percent = 25
		"full":
			cost = encounter.full_heal_cost
			heal_percent = 100
		"cure_all":
			cost = encounter.cure_all_cost
			heal_percent = 100
			cure_debuffs = true

	if character.gold < cost:
		send_to_peer(peer_id, {"type": "error", "message": "Not enough gold! (Need %d)" % cost})
		send_to_peer(peer_id, {"type": "healer_done"})
		return

	character.gold -= cost
	heal_amount = int(character.max_hp * heal_percent / 100.0)
	character.hp = mini(character.hp + heal_amount, character.max_hp)

	var msg = "[color=#00FF00]The Healer channels their magic. You are healed for %d HP! (-%d gold)[/color]" % [heal_amount, cost]

	if cure_debuffs:
		character.persistent_buffs.clear()
		msg += "\n[color=#00FFFF]All ailments have been purged![/color]"

	send_to_peer(peer_id, {"type": "text", "message": msg})
	send_to_peer(peer_id, {"type": "healer_done"})
	save_character(peer_id)
	send_character_update(peer_id)

# ===== BUG REPORT HANDLER =====

const BUG_REPORT_FOLDER = "C:/Users/Dexto/Desktop/Bug Reports"

func handle_bug_report(peer_id: int, message: Dictionary):
	"""Save bug report from client to desktop folder"""
	var report_text = message.get("report", "")
	var player_name = message.get("player", "Unknown")
	var description = message.get("description", "")

	if report_text.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Empty bug report."})
		return

	# Create folder if it doesn't exist
	var dir = DirAccess.open("C:/Users/Dexto/Desktop")
	if dir:
		if not dir.dir_exists("Bug Reports"):
			dir.make_dir("Bug Reports")

	# Generate unique filename with timestamp
	var timestamp = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace("T", "_")
	var safe_player_name = player_name.validate_filename() if player_name else "Unknown"
	var filename = "%s/%s_%s.txt" % [BUG_REPORT_FOLDER, timestamp, safe_player_name]

	# Save report
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file:
		file.store_string(report_text)
		file.close()
		print("[Bug Report] Saved from %s to: %s" % [player_name, filename])
		send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00]Bug report saved successfully! Thank you for your feedback.[/color]"})
	else:
		print("[Bug Report] ERROR: Failed to save report from %s" % player_name)
		send_to_peer(peer_id, {"type": "error", "message": "Failed to save bug report on server."})

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
	elif effect.has("mana") or effect.has("stamina") or effect.has("energy") or effect.has("resource"):
		# Resource potion - restores the player's PRIMARY resource based on class path
		# Mana/Stamina/Energy potions are unified: they all restore your class's primary resource
		var resource_amount: int
		if tier_data.has("resource"):
			resource_amount = tier_data.resource
		elif tier_data.has("healing"):
			# Fallback to calculated value from healing
			resource_amount = int(tier_data.healing * 0.6)
		else:
			# Legacy calculation - use the effect that exists
			if effect.has("mana"):
				resource_amount = effect.base + (effect.per_level * item_level)
			elif effect.has("stamina"):
				resource_amount = effect.base + (effect.per_level * item_level)
			elif effect.has("energy"):
				resource_amount = effect.base + (effect.per_level * item_level)
			else:
				resource_amount = effect.base + (effect.per_level * item_level)

		# Restore the player's primary resource based on their class path
		var primary_resource = character.get_primary_resource()
		var old_value: int
		var actual_restore: int
		var color: String

		match primary_resource:
			"mana":
				old_value = character.current_mana
				character.current_mana = min(character.get_total_max_mana(), character.current_mana + resource_amount)
				actual_restore = character.current_mana - old_value
				color = "#00FFFF"
			"stamina":
				old_value = character.current_stamina
				character.current_stamina = min(character.get_total_max_stamina(), character.current_stamina + resource_amount)
				actual_restore = character.current_stamina - old_value
				color = "#FFCC00"
			"energy":
				old_value = character.current_energy
				character.current_energy = min(character.get_total_max_energy(), character.current_energy + resource_amount)
				actual_restore = character.current_energy - old_value
				color = "#66FF66"
			_:
				# Fallback to mana
				old_value = character.current_mana
				character.current_mana = min(character.get_total_max_mana(), character.current_mana + resource_amount)
				actual_restore = character.current_mana - old_value
				color = "#00FFFF"
				primary_resource = "mana"

		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=%s]You use %s and restore %d %s![/color]" % [color, item_name, actual_restore, primary_resource]
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

	# Title items cannot be equipped - they're turn-in items
	if item.get("is_title_item", false):
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFD700]%s[/color] cannot be worn. %s" % [item.get("name", "This item"), item.get("description", "Check the item for instructions.")]
		})
		return

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
	"""Handle bulk salvaging items for salvage essence"""
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
	var total_essence = 0
	var materials_gained: Dictionary = {}  # {material_id: quantity}

	# Identify items to salvage based on mode
	for i in range(inventory.size()):
		var item = inventory[i]
		var item_level = item.get("level", 1)
		var item_type = item.get("type", "")
		var should_salvage = false

		# Never salvage title items or locked items
		if item.get("is_title_item", false):
			continue
		if item.get("locked", false):
			continue

		# Check if item is a consumable
		var is_consumable = _is_consumable_type(item_type)

		match mode:
			"below_level":
				# Below level mode excludes consumables
				should_salvage = item_level < threshold and not is_consumable
			"all":
				# All mode excludes consumables (use "consumables" mode for those)
				should_salvage = not is_consumable
			"consumables":
				# Consumables-only mode
				should_salvage = is_consumable

		if should_salvage:
			# Calculate salvage value using drop_tables
			var salvage_result = drop_tables.get_salvage_value(item)
			total_essence += salvage_result.essence

			# Check for material bonus
			if salvage_result.material_bonus != null:
				var mat_id = salvage_result.material_bonus.material_id
				var mat_qty = salvage_result.material_bonus.quantity
				if not materials_gained.has(mat_id):
					materials_gained[mat_id] = 0
				materials_gained[mat_id] += mat_qty

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

	# Add salvage essence
	character.add_salvage_essence(total_essence)

	# Add any bonus materials
	for mat_id in materials_gained:
		character.add_crafting_material(mat_id, materials_gained[mat_id])

	# Build result message
	var result_msg = "[color=#AA66FF]Salvaged %d items for %d essence![/color]" % [salvaged_count, total_essence]
	if not materials_gained.is_empty():
		var mat_strings = []
		for mat_id in materials_gained:
			var mat_name = CraftingDatabaseScript.get_material_name(mat_id)
			mat_strings.append("%dx %s" % [materials_gained[mat_id], mat_name])
		result_msg += "\n[color=#00FF00]Bonus materials: %s[/color]" % ", ".join(mat_strings)

	send_to_peer(peer_id, {
		"type": "text",
		"message": result_msg
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

func _is_consumable_type(item_type: String) -> bool:
	"""Check if an item type is a consumable (potion, scroll, etc.)"""
	return (item_type.begins_with("potion_") or item_type.begins_with("mana_") or
			item_type.begins_with("stamina_") or item_type.begins_with("energy_") or
			item_type.begins_with("scroll_") or item_type.begins_with("tome_") or
			item_type == "gold_pouch" or item_type.begins_with("gem_") or
			item_type == "mysterious_box" or item_type == "cursed_coin" or
			item_type == "soul_gem")

func handle_merchant_sell_all(peer_id: int):
	"""Handle selling all EQUIPMENT items to a merchant (skips consumables and title items)"""
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
	var items_sold = 0
	var items_to_remove = []

	# Identify equipment items to sell (skip consumables, title items, and locked items)
	for i in range(character.inventory.size()):
		var item = character.inventory[i]
		var item_type = item.get("type", "")

		# Skip title items
		if item.get("is_title_item", false):
			continue

		# Skip locked/protected items
		if item.get("locked", false):
			continue

		# Only sell equipment
		if not _is_equipment_type(item_type):
			continue

		var sell_price = item.get("value", 10) / 2
		total_gold += sell_price
		items_sold += 1
		items_to_remove.append(i)

	if items_to_remove.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "No equipment to sell! (Use Sell to sell individual items)"})
		return

	# Remove items in reverse order to preserve indices
	items_to_remove.reverse()
	for idx in items_to_remove:
		character.remove_item(idx)

	character.gold += total_gold

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]You sell %d equipment items for %d gold![/color]" % [items_sold, total_gold]
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
	"""Calculate recharge cost based on player level (reduced 10% for economy balance)"""
	# Base cost 45 gold, scales with level
	return 45 + (player_level * 9)

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
						  character.current_mana < character.get_total_max_mana() or
						  character.current_stamina < character.get_total_max_stamina() or
						  character.current_energy < character.get_total_max_energy() or
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
	character.current_stamina = character.get_total_max_stamina()
	character.current_energy = character.get_total_max_energy()
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

func _get_monster_tier(level: int) -> int:
	"""Convert level to tier number for egg drops"""
	if level <= 5: return 1
	if level <= 15: return 2
	if level <= 30: return 3
	if level <= 50: return 4
	if level <= 100: return 5
	if level <= 500: return 6
	if level <= 2000: return 7
	if level <= 5000: return 8
	return 9

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
			# Elite merchants: VERY RARE (only 4 in the world), slightly better items
			# Caps: 1.1x / 1.2x / 1.35x (heavily nerfed from original 2x/3x/5x)
			var level_roll = rng.randi() % 100
			if level_roll < 20:
				# Standard tier (20%): player level to +8 (capped at 1.1x)
				item_level = mini(int(player_level * 1.1), maxi(1, player_level + rng.randi_range(0, 8)))
			elif level_roll < 60:
				# Premium tier (40%): player level +8 to +15 (capped at 1.2x)
				item_level = mini(int(player_level * 1.2), player_level + rng.randi_range(8, 15))
			else:
				# Legendary tier (40%): player level +15 to +20 (capped at 1.35x)
				item_level = mini(int(player_level * 1.35), player_level + rng.randi_range(15, 20))
			item_level = maxi(1, item_level)
		else:
			# Normal shop: item level ranges around player level with tight caps
			# Caps: 1.1x / 1.15x (heavily nerfed from original 2x/3x)
			var level_roll = rng.randi() % 100
			if level_roll < 86:
				# Standard tier (86%): player level -5 to +5
				item_level = maxi(1, player_level + rng.randi_range(-5, 5))
			elif level_roll < 96:
				# Premium tier (10%): player level +5 to +8 (capped at 1.1x player level)
				item_level = mini(int(player_level * 1.1), player_level + rng.randi_range(5, 8))
			else:
				# Aspirational tier (4%): player level +8 to +12 (capped at 1.15x player level)
				item_level = mini(int(player_level * 1.15), player_level + rng.randi_range(8, 12))
			item_level = maxi(1, item_level)

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

	# Record discovery of this trading post
	var newly_discovered = character.discover_trading_post(tp.name, tp.center.x, tp.center.y)
	if newly_discovered:
		save_character(peer_id)

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

	# Calculate recharge cost to send to client
	var is_starter_post = tp.id in STARTER_TRADING_POSTS
	var tp_x = tp.center.x
	var tp_y = tp.center.y
	var recharge_cost: int
	if is_starter_post:
		recharge_cost = 20
	else:
		var base_cost = _get_recharge_cost(character.level)
		var distance_from_origin = sqrt(tp_x * tp_x + tp_y * tp_y)
		var distance_multiplier = 3.5 + (distance_from_origin / 50.0) * 7.0  # 3.5x base at origin, +7x per 50 distance
		recharge_cost = int(base_cost * distance_multiplier)

	send_to_peer(peer_id, {
		"type": "trading_post_start",
		"id": tp.id,
		"name": tp.name,
		"description": tp.description,
		"quest_giver": tp.quest_giver,
		"services": ["shop", "quests", "recharge"],
		"available_quests": available_quests.size(),
		"quests_to_turn_in": quests_to_turn_in.size(),
		"recharge_cost": recharge_cost,
		"x": tp_x,
		"y": tp_y
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
		"services": ["buy", "sell", "gamble"],
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
	services_text.append("[W] Gamble")
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

	# Get locked quests (unmet prerequisites)
	var locked_quests = quest_db.get_locked_quests_for_player(
		tp.id, character.completed_quests, active_quest_ids, character.daily_quest_cooldowns)

	# Add progression quest if player is high enough level for next post
	var progression_quest = _generate_progression_quest(tp.id, character.level, character.completed_quests, active_quest_ids)
	if not progression_quest.is_empty():
		available_quests.append(progression_quest)

	# Add dungeon direction hints to dungeon quests
	var tp_x = tp.center.x
	var tp_y = tp.center.y
	available_quests = _add_dungeon_directions_to_quests(available_quests, tp_x, tp_y)

	# Get quests ready to turn in at this Trading Post
	var quests_to_turn_in = []
	for quest_data in character.active_quests:
		var quest = quest_db.get_quest(quest_data.quest_id)
		if quest.is_empty():
			continue

		# Check if quest can be turned in here
		var can_turn_in = false
		if quest.trading_post == tp.id:
			# Normal case: at the origin trading post
			can_turn_in = true
		elif quest_data.quest_id.begins_with("progression_to_"):
			# Progression quests can also be turned in at their destination
			var dest_post_id = quest_data.quest_id.replace("progression_to_", "")
			if tp.id == dest_post_id:
				can_turn_in = true

		if can_turn_in and quest_data.progress >= quest_data.target:
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
			var description = quest.get("description", "")

			# Add dungeon direction hints for dungeon quests
			if quest.get("type") == quest_db.QuestType.DUNGEON_CLEAR:
				var dungeon_type = quest.get("dungeon_type", "")
				var tier = 1 if quest_data.quest_id.begins_with("haven_") else 0
				var nearest = _find_nearest_dungeon_for_quest(tp_x, tp_y, dungeon_type, tier)
				if not nearest.is_empty():
					description += "\n\n[color=#00FFFF]Nearest dungeon:[/color] %s (%s)" % [
						nearest.dungeon_name, nearest.direction_text
					]

			active_quests_display.append({
				"id": quest_data.quest_id,
				"name": quest.name,
				"progress": quest_data.progress,
				"target": quest_data.target,
				"description": description,
				"is_complete": quest_data.progress >= quest_data.target,
				"trading_post": quest.trading_post
			})

	send_to_peer(peer_id, {
		"type": "quest_list",
		"quest_giver": tp.quest_giver,
		"trading_post": tp.name,
		"trading_post_id": tp.id,
		"available_quests": available_quests,
		"locked_quests": locked_quests,
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
	var tp_id = tp.get("id", "")

	# Starter trading posts have flat low cost to help new players
	var is_starter_post = tp_id in STARTER_TRADING_POSTS
	var cost: int
	if is_starter_post:
		# Flat 20 gold for starter areas regardless of level
		cost = 20
	else:
		# Calculate cost based on level and trading post distance from origin
		# Remote trading posts charge more for their services
		var base_cost = _get_recharge_cost(character.level)
		var tp_x = tp.center.x
		var tp_y = tp.center.y
		var distance_from_origin = sqrt(tp_x * tp_x + tp_y * tp_y)
		var distance_multiplier = 3.5 + (distance_from_origin / 50.0) * 7.0  # 3.5x base at origin, +7x per 50 distance
		cost = int(base_cost * distance_multiplier)

	# Check if already at full resources and not poisoned/blinded
	var needs_recharge = (character.current_hp < character.get_total_max_hp() or
						  character.current_mana < character.get_total_max_mana() or
						  character.current_stamina < character.get_total_max_stamina() or
						  character.current_energy < character.get_total_max_energy() or
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
	character.current_stamina = character.get_total_max_stamina()
	character.current_energy = character.get_total_max_energy()
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

		# For the starter dungeon quest, ensure a tier 1 dungeon exists near spawn
		if quest_id == "haven_first_dungeon":
			_ensure_starter_dungeon_exists()
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
		var can_turn_in = false

		# Check if quest can be turned in at current location
		if quest.trading_post == tp.id:
			# Normal case: at the origin trading post
			can_turn_in = true
		elif quest_id.begins_with("progression_to_"):
			# Progression quests can also be turned in at their destination
			var dest_post_id = quest_id.replace("progression_to_", "")
			if tp.id == dest_post_id:
				can_turn_in = true

		if not can_turn_in:
			var required_tp = trading_post_db.TRADING_POSTS.get(quest.trading_post, {})
			# For progression quests, give helpful message about both locations
			if quest_id.begins_with("progression_to_"):
				var dest_post_id = quest_id.replace("progression_to_", "")
				var dest_tp = trading_post_db.TRADING_POSTS.get(dest_post_id, {})
				send_to_peer(peer_id, {
					"type": "error",
					"message": "Turn in this quest at %s (origin) or %s (destination)." % [
						required_tp.get("name", "the quest giver"),
						dest_tp.get("name", "the destination")
					]
				})
			else:
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
		var description = quest_data.get("description", "") if quest_data else ""

		# Add dungeon direction hints for dungeon quests
		if quest_data and quest_data.get("type") == quest_db.QuestType.DUNGEON_CLEAR:
			var dungeon_type = quest_data.get("dungeon_type", "")
			var tier = 1 if qid.begins_with("haven_") else 0
			var nearest = _find_nearest_dungeon_for_quest(character.x, character.y, dungeon_type, tier)
			if not nearest.is_empty():
				description += "\n\n[color=#00FFFF]Nearest dungeon:[/color] %s (%s)" % [
					nearest.dungeon_name, nearest.direction_text
				]

		active_quests_info.append({
			"id": qid,
			"name": quest_data.get("name", "Unknown Quest") if quest_data else "Unknown Quest",
			"progress": quest.get("progress", 0),
			"target": quest.get("target", 1),
			"description": description
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

func check_kill_quest_progress(peer_id: int, monster_level: int, monster_name: String = ""):
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
		character, monster_level, character.x, character.y, hotzone_intensity, world_system, monster_name)

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

func handle_toggle_swap_attack(peer_id: int, message: Dictionary):
	"""Handle toggle for swapping Attack with first ability on action bar"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var enabled = message.get("enabled", false)
	character.swap_attack_with_ability = enabled
	save_character(peer_id)
	send_character_update(peer_id)

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

	# Calculate cost based on distance: base 10 + 1 per tile distance
	var distance = sqrt(pow(target_x - character.x, 2) + pow(target_y - character.y, 2))
	var cost = int(10 + distance)

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

# ===== COMPANION SYSTEM =====

func handle_activate_companion(peer_id: int, message: Dictionary):
	"""Handle activating a companion from soul gems or hatched companions"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var companion_name_input = message.get("name", "").strip_edges()

	if companion_name_input.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Please specify a companion name."})
		return

	# First check hatched companions (new egg system)
	var hatched_companions = character.get_collected_companions()
	var matched_hatched = {}

	for comp in hatched_companions:
		var name = comp.get("name", "")
		if name.to_lower() == companion_name_input.to_lower():
			matched_hatched = comp
			break
		elif name.to_lower().begins_with(companion_name_input.to_lower()):
			matched_hatched = comp

	if not matched_hatched.is_empty():
		var comp_id = matched_hatched.get("id", "")
		if character.activate_hatched_companion(comp_id):
			var companion_name = matched_hatched.get("name", "Unknown")
			send_to_peer(peer_id, {"type": "text", "message": "[color=#00FFFF]%s is now your active companion![/color]" % companion_name})
			send_character_update(peer_id)
			save_character(peer_id)
			return
		else:
			send_to_peer(peer_id, {"type": "error", "message": "Could not activate companion."})
			return

	# Fall back to soul gems (legacy system)
	var soul_gems = character.get_all_soul_gems()
	var matched_gem = {}

	for gem in soul_gems:
		var name = gem.get("name", "")
		if name.to_lower() == companion_name_input.to_lower():
			matched_gem = gem
			break
		elif name.to_lower().begins_with(companion_name_input.to_lower()):
			matched_gem = gem

	if matched_gem.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000]No companion found matching '%s'.[/color]" % companion_name_input})
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Use /companion to see your companions.[/color]"})
		return

	var gem_id = matched_gem.get("id", "")
	if character.activate_companion(gem_id):
		var companion_name = matched_gem.get("name", "Unknown")
		send_to_peer(peer_id, {"type": "text", "message": "[color=#00FFFF]%s is now your active companion![/color]" % companion_name})
		send_character_update(peer_id)
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {"type": "error", "message": "Could not activate companion."})

func handle_dismiss_companion(peer_id: int):
	"""Handle dismissing the active companion"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	if not character.has_active_companion():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]You don't have an active companion.[/color]"})
		return

	var old_companion = character.get_active_companion()
	var companion_name = old_companion.get("name", "Unknown")
	character.dismiss_companion()
	send_to_peer(peer_id, {"type": "text", "message": "[color=#FFA500]%s has been dismissed.[/color]" % companion_name})
	send_character_update(peer_id)
	save_character(peer_id)

# ===== TITLE SYSTEM =====

# ===== FISHING SYSTEM =====

func handle_fish_start(peer_id: int):
	"""Handle player starting to fish"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Check if in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot fish while in combat!"})
		return

	# Check if at a water tile
	if not world_system.is_fishing_spot(character.x, character.y):
		send_to_peer(peer_id, {"type": "error", "message": "You need to be at water to fish!"})
		return

	# Get water type and fishing data
	var water_type = world_system.get_fishing_type(character.x, character.y)
	var wait_time = drop_tables.get_fishing_wait_time(character.fishing_skill)
	var reaction_window = drop_tables.get_fishing_reaction_window(character.fishing_skill)

	send_to_peer(peer_id, {
		"type": "fish_start",
		"water_type": water_type,
		"wait_time": wait_time,
		"reaction_window": reaction_window,
		"fishing_skill": character.fishing_skill,
		"message": "[color=#4169E1]You cast your line into the %s water...[/color]" % water_type
	})

func handle_fish_catch(peer_id: int, message: Dictionary):
	"""Handle player attempting to catch a fish"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var success = message.get("success", false)
	var water_type = message.get("water_type", "shallow")

	if not success:
		send_to_peer(peer_id, {
			"type": "fish_result",
			"success": false,
			"message": "[color=#FF4444]The fish got away![/color]"
		})
		return

	# Roll for catch
	var catch_result = drop_tables.roll_fishing_catch(water_type, character.fishing_skill)

	# Add XP
	var xp_result = character.add_fishing_xp(catch_result.xp)
	character.record_fish_caught()

	# Handle different catch types
	var catch_message = ""
	var extra_messages = []

	match catch_result.type:
		"fish":
			# Add as crafting material
			character.add_crafting_material(catch_result.item_id, 1)
			catch_message = "[color=#00FF00]You caught a %s![/color]" % catch_result.name
		"material":
			character.add_crafting_material(catch_result.item_id, 1)
			catch_message = "[color=#00BFFF]You found %s![/color]" % catch_result.name
		"treasure":
			# Give gold based on value
			var gold_amount = catch_result.value + randi() % (catch_result.value / 2)
			character.gold += gold_amount
			catch_message = "[color=#FFD700]You found a %s containing %d gold![/color]" % [catch_result.name, gold_amount]
		"egg":
			# Try to add a random egg
			var egg_tiers = [1, 2, 3] if catch_result.item_id == "companion_egg_random" else [4, 5, 6]
			var tier = egg_tiers[randi() % egg_tiers.size()]
			var monster_names = []
			for monster_name in drop_tables.COMPANION_DATA:
				if drop_tables.COMPANION_DATA[monster_name].tier == tier:
					monster_names.append(monster_name)
			if monster_names.size() > 0:
				var random_monster = monster_names[randi() % monster_names.size()]
				var egg_data = drop_tables.get_egg_for_monster(random_monster)
				var egg_result = character.add_egg(egg_data)
				if egg_result.success:
					catch_message = "[color=#A335EE]★ You found a %s! ★[/color]" % egg_data.name
					extra_messages.append("[color=#808080]Walk %d steps to hatch it.[/color]" % egg_data.hatch_steps)
				else:
					# Failed to add egg, give gold instead
					character.gold += catch_result.value
					catch_message = "[color=#FFD700]You found treasure worth %d gold![/color]" % catch_result.value
			else:
				character.gold += catch_result.value
				catch_message = "[color=#FFD700]You found treasure worth %d gold![/color]" % catch_result.value

	# Build level up message if applicable
	if xp_result.leveled_up:
		extra_messages.append("[color=#FFFF00]★ Fishing skill increased to %d! ★[/color]" % xp_result.new_level)

	send_to_peer(peer_id, {
		"type": "fish_result",
		"success": true,
		"catch": catch_result,
		"xp_gained": catch_result.xp,
		"leveled_up": xp_result.leveled_up,
		"new_level": xp_result.new_level,
		"message": catch_message,
		"extra_messages": extra_messages
	})

	send_character_update(peer_id)
	save_character(peer_id)

# ===== MINING SYSTEM =====

func handle_mine_start(peer_id: int):
	"""Handle player starting to mine"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Check if in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot mine while in combat!"})
		return

	# Check if at an ore deposit
	if not world_system.is_ore_deposit(character.x, character.y):
		send_to_peer(peer_id, {"type": "error", "message": "You need to be at an ore deposit to mine!"})
		return

	# Get ore tier and mining data
	var ore_tier = world_system.get_ore_tier(character.x, character.y)
	var wait_time = drop_tables.get_mining_wait_time(character.mining_skill)
	var reaction_window = drop_tables.get_mining_reaction_window(character.mining_skill)
	var reactions_required = drop_tables.get_mining_reactions_required(ore_tier)

	send_to_peer(peer_id, {
		"type": "mine_start",
		"ore_tier": ore_tier,
		"wait_time": wait_time,
		"reaction_window": reaction_window,
		"reactions_required": reactions_required,
		"mining_skill": character.mining_skill,
		"message": "[color=#C0C0C0]You begin mining the ore vein (Tier %d)...[/color]" % ore_tier
	})

func handle_mine_catch(peer_id: int, message: Dictionary):
	"""Handle player completing a mining attempt"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var success = message.get("success", false)
	var partial_success = message.get("partial_success", 0)  # Number of successful reactions
	var ore_tier = message.get("ore_tier", 1)

	if not success and partial_success == 0:
		send_to_peer(peer_id, {
			"type": "mine_result",
			"success": false,
			"message": "[color=#FF4444]The vein crumbles - you got nothing![/color]"
		})
		return

	# Roll for catch (reduced rewards on partial success)
	var catch_result = drop_tables.roll_mining_catch(ore_tier, character.mining_skill)

	# Calculate quantity based on success level
	var quantity = 1
	if success:
		quantity = 1 + randi() % 2  # 1-2 on full success
	# Partial success: 1 item but reduced XP

	# Add XP (reduced on partial success)
	var xp_multiplier = 1.0 if success else (float(partial_success) / drop_tables.get_mining_reactions_required(ore_tier))
	var xp_gained = int(catch_result.xp * xp_multiplier)
	var xp_result = character.add_mining_xp(xp_gained)
	character.record_ore_gathered()

	# Handle different catch types
	var catch_message = ""
	var extra_messages = []

	match catch_result.type:
		"ore":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#C0C0C0]You mined %dx %s![/color]" % [quantity, catch_result.name]
		"mineral":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#708090]You found %dx %s![/color]" % [quantity, catch_result.name]
		"gem":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#00CED1]★ You found %dx %s! ★[/color]" % [quantity, catch_result.name]
		"enchant", "essence":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#9400D3]You discovered %dx %s![/color]" % [quantity, catch_result.name]
		"herb":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#32CD32]You found %dx %s growing in the cave![/color]" % [quantity, catch_result.name]
		"treasure":
			var gold_amount = catch_result.value + randi() % (catch_result.value / 2)
			character.gold += gold_amount
			catch_message = "[color=#FFD700]You unearthed a %s containing %d gold![/color]" % [catch_result.name, gold_amount]
		"egg":
			var egg_tiers = [1, 2, 3] if catch_result.item_id == "companion_egg_random" else ([4, 5] if catch_result.item_id == "companion_egg_rare" else [6, 7])
			var tier = egg_tiers[randi() % egg_tiers.size()]
			var monster_names = []
			for monster_name in drop_tables.COMPANION_DATA:
				if drop_tables.COMPANION_DATA[monster_name].tier == tier:
					monster_names.append(monster_name)
			if monster_names.size() > 0:
				var random_monster = monster_names[randi() % monster_names.size()]
				var egg_data = drop_tables.get_egg_for_monster(random_monster)
				var egg_result = character.add_egg(egg_data)
				if egg_result.success:
					catch_message = "[color=#A335EE]★ You unearthed a %s! ★[/color]" % egg_data.name
					extra_messages.append("[color=#808080]Walk %d steps to hatch it.[/color]" % egg_data.hatch_steps)
				else:
					character.gold += catch_result.value
					catch_message = "[color=#FFD700]You found treasure worth %d gold![/color]" % catch_result.value
			else:
				character.gold += catch_result.value
				catch_message = "[color=#FFD700]You found treasure worth %d gold![/color]" % catch_result.value

	if xp_result.leveled_up:
		extra_messages.append("[color=#FFFF00]★ Mining skill increased to %d! ★[/color]" % xp_result.new_level)

	send_to_peer(peer_id, {
		"type": "mine_result",
		"success": true,
		"catch": catch_result,
		"quantity": quantity,
		"xp_gained": xp_gained,
		"leveled_up": xp_result.leveled_up,
		"new_level": xp_result.new_level,
		"message": catch_message,
		"extra_messages": extra_messages
	})

	send_character_update(peer_id)
	save_character(peer_id)

# ===== LOGGING SYSTEM =====

func handle_log_start(peer_id: int):
	"""Handle player starting to log (chop wood)"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Check if in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot chop wood while in combat!"})
		return

	# Check if at a dense forest
	if not world_system.is_dense_forest(character.x, character.y):
		send_to_peer(peer_id, {"type": "error", "message": "You need to be at a harvestable tree to chop!"})
		return

	# Get wood tier and logging data
	var wood_tier = world_system.get_wood_tier(character.x, character.y)
	var wait_time = drop_tables.get_logging_wait_time(character.logging_skill)
	var reaction_window = drop_tables.get_logging_reaction_window(character.logging_skill)
	var reactions_required = drop_tables.get_logging_reactions_required(wood_tier)

	send_to_peer(peer_id, {
		"type": "log_start",
		"wood_tier": wood_tier,
		"wait_time": wait_time,
		"reaction_window": reaction_window,
		"reactions_required": reactions_required,
		"logging_skill": character.logging_skill,
		"message": "[color=#8B4513]You begin chopping the tree (Tier %d)...[/color]" % wood_tier
	})

func handle_log_catch(peer_id: int, message: Dictionary):
	"""Handle player completing a logging attempt"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var success = message.get("success", false)
	var partial_success = message.get("partial_success", 0)
	var wood_tier = message.get("wood_tier", 1)

	if not success and partial_success == 0:
		send_to_peer(peer_id, {
			"type": "log_result",
			"success": false,
			"message": "[color=#FF4444]The branch breaks - you got nothing![/color]"
		})
		return

	# Roll for catch
	var catch_result = drop_tables.roll_logging_catch(wood_tier, character.logging_skill)

	# Calculate quantity based on success level
	var quantity = 1
	if success:
		quantity = 1 + randi() % 2

	# Add XP (reduced on partial success)
	var xp_multiplier = 1.0 if success else (float(partial_success) / drop_tables.get_logging_reactions_required(wood_tier))
	var xp_gained = int(catch_result.xp * xp_multiplier)
	var xp_result = character.add_logging_xp(xp_gained)
	character.record_wood_gathered()

	# Handle different catch types
	var catch_message = ""
	var extra_messages = []

	match catch_result.type:
		"wood":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#8B4513]You gathered %dx %s![/color]" % [quantity, catch_result.name]
		"plant":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#228B22]You found %dx %s![/color]" % [quantity, catch_result.name]
		"herb":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#32CD32]You harvested %dx %s![/color]" % [quantity, catch_result.name]
		"enchant", "essence":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#9400D3]You discovered %dx %s![/color]" % [quantity, catch_result.name]
		"treasure":
			var gold_amount = catch_result.value + randi() % (catch_result.value / 2)
			character.gold += gold_amount
			catch_message = "[color=#FFD700]You found a %s hidden in the trunk containing %d gold![/color]" % [catch_result.name, gold_amount]
		"egg":
			var egg_tiers = [1, 2, 3] if catch_result.item_id == "companion_egg_random" else ([4, 5] if catch_result.item_id == "companion_egg_rare" else [6, 7])
			var tier = egg_tiers[randi() % egg_tiers.size()]
			var monster_names = []
			for monster_name in drop_tables.COMPANION_DATA:
				if drop_tables.COMPANION_DATA[monster_name].tier == tier:
					monster_names.append(monster_name)
			if monster_names.size() > 0:
				var random_monster = monster_names[randi() % monster_names.size()]
				var egg_data = drop_tables.get_egg_for_monster(random_monster)
				var egg_result = character.add_egg(egg_data)
				if egg_result.success:
					catch_message = "[color=#A335EE]★ You found a %s in a nest! ★[/color]" % egg_data.name
					extra_messages.append("[color=#808080]Walk %d steps to hatch it.[/color]" % egg_data.hatch_steps)
				else:
					character.gold += catch_result.value
					catch_message = "[color=#FFD700]You found treasure worth %d gold![/color]" % catch_result.value
			else:
				character.gold += catch_result.value
				catch_message = "[color=#FFD700]You found treasure worth %d gold![/color]" % catch_result.value

	if xp_result.leveled_up:
		extra_messages.append("[color=#FFFF00]★ Logging skill increased to %d! ★[/color]" % xp_result.new_level)

	send_to_peer(peer_id, {
		"type": "log_result",
		"success": true,
		"catch": catch_result,
		"quantity": quantity,
		"xp_gained": xp_gained,
		"leveled_up": xp_result.leveled_up,
		"new_level": xp_result.new_level,
		"message": catch_message,
		"extra_messages": extra_messages
	})

	send_character_update(peer_id)
	save_character(peer_id)

# ===== CRAFTING SYSTEM =====

func handle_craft_list(peer_id: int, message: Dictionary):
	"""Send list of available recipes to player"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Must be at a trading post to craft
	if not at_trading_post.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You must be at a Trading Post to craft!"})
		return

	var skill_name = message.get("skill", "blacksmithing").to_lower()
	var skill_enum: int
	match skill_name:
		"blacksmithing":
			skill_enum = CraftingDatabaseScript.CraftingSkill.BLACKSMITHING
		"alchemy":
			skill_enum = CraftingDatabaseScript.CraftingSkill.ALCHEMY
		"enchanting":
			skill_enum = CraftingDatabaseScript.CraftingSkill.ENCHANTING
		_:
			send_to_peer(peer_id, {"type": "error", "message": "Unknown crafting skill: %s" % skill_name})
			return

	var skill_level = character.get_crafting_skill(skill_name)
	var recipes = CraftingDatabaseScript.get_available_recipes(skill_enum, skill_level)

	# Get trading post bonus
	var tp_data = at_trading_post[peer_id]
	var tp_id = tp_data.get("id", "")
	var post_bonus = CraftingDatabaseScript.get_post_specialization_bonus(tp_id, skill_name)

	# Build recipe list with player's materials
	var recipe_list = []
	for recipe_entry in recipes:
		var recipe_id = recipe_entry.id
		var recipe = recipe_entry.data
		var can_craft = character.has_crafting_materials(recipe.materials)
		var success_chance = CraftingDatabaseScript.calculate_success_chance(skill_level, recipe.difficulty, post_bonus)

		recipe_list.append({
			"id": recipe_id,
			"name": recipe.name,
			"skill_required": recipe.skill_required,
			"difficulty": recipe.difficulty,
			"materials": recipe.materials,
			"can_craft": can_craft,
			"success_chance": success_chance,
			"output_type": recipe.output_type
		})

	send_to_peer(peer_id, {
		"type": "craft_list",
		"skill": skill_name,
		"skill_level": skill_level,
		"post_bonus": post_bonus,
		"recipes": recipe_list,
		"materials": character.crafting_materials
	})

func handle_craft_item(peer_id: int, message: Dictionary):
	"""Attempt to craft an item"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Must be at a trading post
	if not at_trading_post.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You must be at a Trading Post to craft!"})
		return

	var recipe_id = message.get("recipe_id", "")
	var recipe = CraftingDatabaseScript.get_recipe(recipe_id)
	if recipe.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Unknown recipe: %s" % recipe_id})
		return

	# Get skill info
	var skill_name = CraftingDatabaseScript.get_skill_name(recipe.skill)
	var skill_level = character.get_crafting_skill(skill_name)

	# Check skill requirement
	if skill_level < recipe.skill_required:
		send_to_peer(peer_id, {"type": "error", "message": "Requires %s level %d (you have %d)" % [skill_name.capitalize(), recipe.skill_required, skill_level]})
		return

	# Check materials
	if not character.has_crafting_materials(recipe.materials):
		send_to_peer(peer_id, {"type": "error", "message": "You don't have the required materials!"})
		return

	# Consume materials
	for mat_id in recipe.materials:
		character.remove_crafting_material(mat_id, recipe.materials[mat_id])

	# Get trading post bonus
	var tp_data = at_trading_post[peer_id]
	var tp_id = tp_data.get("id", "")
	var post_bonus = CraftingDatabaseScript.get_post_specialization_bonus(tp_id, skill_name)

	# Roll for quality
	var quality = CraftingDatabaseScript.roll_quality(skill_level, recipe.difficulty, post_bonus)
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var quality_color = CraftingDatabaseScript.QUALITY_COLORS[quality]

	# Calculate XP
	var xp_gained = CraftingDatabaseScript.calculate_craft_xp(recipe.difficulty, quality)
	var xp_result = character.add_crafting_xp(skill_name, xp_gained)

	# Build result message
	var result_message = ""
	var crafted_item = {}

	if quality == CraftingDatabaseScript.CraftingQuality.FAILED:
		result_message = "[color=#FF4444]Crafting failed! Materials lost.[/color]"
	else:
		# Create the item based on output type
		match recipe.output_type:
			"weapon", "armor":
				crafted_item = _create_crafted_equipment(recipe, quality)
				if crafted_item.is_empty():
					result_message = "[color=#FF4444]Failed to create item![/color]"
				else:
					# Add to inventory
					character.inventory.append(crafted_item)
					result_message = "[color=%s]Created %s %s![/color]" % [quality_color, quality_name, recipe.name]
			"consumable":
				crafted_item = _create_crafted_consumable(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s %s![/color]" % [quality_color, quality_name, recipe.name]
			"enhancement":
				# Enhancements are applied directly to equipment - not implemented yet
				result_message = "[color=#FFFF00]Enhancement scrolls coming soon![/color]"
				# For now, give gold equivalent
				var gold_value = recipe.difficulty * 10
				character.gold += gold_value
				result_message = "[color=#FFD700]Received %d gold instead.[/color]" % gold_value
			"material":
				# Creates crafting materials - add directly to materials inventory
				var output_item = recipe.get("output_item", "")
				var base_quantity = recipe.get("output_quantity", 1)
				var multiplier = CraftingDatabaseScript.QUALITY_MULTIPLIERS[quality]
				var final_quantity = int(base_quantity * multiplier)
				if output_item != "" and final_quantity > 0:
					character.add_crafting_material(output_item, final_quantity)
					result_message = "[color=%s]Created %d %s %s![/color]" % [quality_color, final_quantity, quality_name, recipe.name.replace("Refine ", "")]
				else:
					result_message = "[color=#FF4444]Failed to create materials![/color]"

	# Send result
	send_to_peer(peer_id, {
		"type": "craft_result",
		"success": quality != CraftingDatabaseScript.CraftingQuality.FAILED,
		"recipe_id": recipe_id,
		"recipe_name": recipe.name,
		"quality": quality,
		"quality_name": quality_name,
		"quality_color": quality_color,
		"xp_gained": xp_gained,
		"leveled_up": xp_result.leveled_up,
		"new_level": xp_result.new_level,
		"skill_name": skill_name,
		"message": result_message,
		"crafted_item": crafted_item
	})

	send_character_update(peer_id)
	save_character(peer_id)

func _create_crafted_equipment(recipe: Dictionary, quality: int) -> Dictionary:
	"""Create a crafted equipment item"""
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var base_stats = recipe.get("base_stats", {})
	var scaled_stats = CraftingDatabaseScript.apply_quality_to_stats(base_stats, quality)

	# Generate unique ID
	var item_id = "crafted_%s_%d" % [recipe.name.to_lower().replace(" ", "_"), randi()]

	# For armor pieces, use the slot as the type (helm, boots, armor, shield)
	# This ensures _get_slot_for_item_type works correctly
	var output_slot = recipe.get("output_slot", "")
	var item_type = recipe.output_type
	if recipe.output_type == "armor" and output_slot != "":
		item_type = output_slot + "_crafted"  # e.g., "helm_crafted", "boots_crafted"

	var item = {
		"id": item_id,
		"name": "%s %s" % [quality_name, recipe.name] if quality != CraftingDatabaseScript.CraftingQuality.STANDARD else recipe.name,
		"type": item_type,
		"slot": output_slot,
		"level": scaled_stats.get("level", 1),
		"rarity": _quality_to_rarity(quality),
		"crafted": true,
		"quality": quality
	}

	# Add stats
	if scaled_stats.has("attack"):
		item["attack"] = scaled_stats["attack"]
	if scaled_stats.has("defense"):
		item["defense"] = scaled_stats["defense"]
	if scaled_stats.has("hp"):
		item["hp"] = scaled_stats["hp"]
	if scaled_stats.has("speed"):
		item["speed"] = scaled_stats["speed"]
	if scaled_stats.has("mana"):
		item["mana"] = scaled_stats["mana"]

	return item

func _create_crafted_consumable(recipe: Dictionary, quality: int) -> Dictionary:
	"""Create a crafted consumable item"""
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var effect = recipe.get("effect", {})
	var multiplier = CraftingDatabaseScript.QUALITY_MULTIPLIERS[quality]

	# Scale effect by quality
	var scaled_effect = effect.duplicate()
	if scaled_effect.has("amount"):
		scaled_effect["amount"] = int(scaled_effect["amount"] * multiplier)

	var item_id = "crafted_%s_%d" % [recipe.name.to_lower().replace(" ", "_"), randi()]

	var item = {
		"id": item_id,
		"name": "%s %s" % [quality_name, recipe.name] if quality != CraftingDatabaseScript.CraftingQuality.STANDARD else recipe.name,
		"type": "consumable",
		"slot": "",
		"level": 1,
		"rarity": _quality_to_rarity(quality),
		"crafted": true,
		"quality": quality,
		"effect": scaled_effect
	}

	return item

func _quality_to_rarity(quality: int) -> String:
	"""Convert crafting quality to item rarity"""
	match quality:
		CraftingDatabaseScript.CraftingQuality.POOR:
			return "common"
		CraftingDatabaseScript.CraftingQuality.STANDARD:
			return "uncommon"
		CraftingDatabaseScript.CraftingQuality.FINE:
			return "rare"
		CraftingDatabaseScript.CraftingQuality.MASTERWORK:
			return "epic"
		_:
			return "common"

# ===== DUNGEON SYSTEM =====

func handle_dungeon_list(peer_id: int):
	"""Send list of available dungeons to player"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get dungeons appropriate for player level
	var available_types = DungeonDatabaseScript.get_dungeons_for_level(character.level)

	# Build list with cooldown info
	var dungeon_list = []
	for dungeon_type in available_types:
		var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
		var on_cooldown = character.is_dungeon_on_cooldown(dungeon_type)
		var cooldown_remaining = character.get_dungeon_cooldown_remaining(dungeon_type)
		var completions = character.get_dungeon_completions(dungeon_type)

		# Find active instance of this type
		var active_instance = ""
		var instance_location = Vector2i(0, 0)
		for inst_id in active_dungeons:
			var inst = active_dungeons[inst_id]
			if inst.dungeon_type == dungeon_type:
				active_instance = inst_id
				instance_location = Vector2i(inst.world_x, inst.world_y)
				break

		dungeon_list.append({
			"type": dungeon_type,
			"name": dungeon_data.name,
			"description": dungeon_data.description,
			"tier": dungeon_data.tier,
			"min_level": dungeon_data.min_level,
			"max_level": dungeon_data.max_level,
			"floors": dungeon_data.floors,
			"on_cooldown": on_cooldown,
			"cooldown_remaining": cooldown_remaining,
			"completions": completions,
			"active_instance": active_instance,
			"location": {"x": instance_location.x, "y": instance_location.y} if active_instance != "" else null,
			"color": dungeon_data.color
		})

	send_to_peer(peer_id, {
		"type": "dungeon_list",
		"dungeons": dungeon_list,
		"player_level": character.level,
		"in_dungeon": character.in_dungeon
	})

func handle_dungeon_enter(peer_id: int, message: Dictionary):
	"""Handle player entering a dungeon"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Already in dungeon?
	if character.in_dungeon:
		send_to_peer(peer_id, {"type": "error", "message": "You are already in a dungeon!"})
		return

	# In combat?
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot enter a dungeon while in combat!"})
		return

	# Accept either dungeon_type directly or find type from provided instance_id
	var dungeon_type = message.get("dungeon_type", "")
	var provided_instance_id = message.get("instance_id", "")

	if dungeon_type == "" and provided_instance_id != "":
		# Look up type from instance
		if active_dungeons.has(provided_instance_id):
			dungeon_type = active_dungeons[provided_instance_id].dungeon_type

	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	if dungeon_data.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Unknown dungeon type!"})
		return

	# Check level requirement
	if character.level < dungeon_data.min_level:
		send_to_peer(peer_id, {"type": "error", "message": "You need to be level %d to enter this dungeon!" % dungeon_data.min_level})
		return

	# Check cooldown
	if character.is_dungeon_on_cooldown(dungeon_type):
		var remaining = character.get_dungeon_cooldown_remaining(dungeon_type)
		var hours = remaining / 3600
		var minutes = (remaining % 3600) / 60
		send_to_peer(peer_id, {"type": "error", "message": "Dungeon on cooldown! Available in %dh %dm" % [hours, minutes]})
		return

	# Find existing instance or create new one
	var instance_id = ""
	# First check if provided instance_id is valid
	if provided_instance_id != "" and active_dungeons.has(provided_instance_id):
		instance_id = provided_instance_id
	else:
		# Look for any active instance of this dungeon type
		for inst_id in active_dungeons:
			if active_dungeons[inst_id].dungeon_type == dungeon_type:
				instance_id = inst_id
				break

	if instance_id == "":
		# Create new instance
		instance_id = _create_dungeon_instance(dungeon_type)
		if instance_id == "":
			send_to_peer(peer_id, {"type": "error", "message": "Failed to create dungeon instance!"})
			return

	var instance = active_dungeons[instance_id]

	# Get starting position (entrance tile)
	var floor_grid = dungeon_floors[instance_id][0]
	var start_pos = _find_tile_position(floor_grid, DungeonDatabaseScript.TileType.ENTRANCE)

	# Enter dungeon
	character.enter_dungeon(instance_id, dungeon_type, start_pos.x, start_pos.y)

	# Add to active players
	if not instance.active_players.has(peer_id):
		instance.active_players.append(peer_id)

	# Send dungeon state to player
	_send_dungeon_state(peer_id)
	save_character(peer_id)

	log_message("Player %s entered dungeon %s (instance %s)" % [character.name, dungeon_data.name, instance_id])

func handle_dungeon_move(peer_id: int, message: Dictionary):
	"""Handle player movement within dungeon"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	if not character.in_dungeon:
		send_to_peer(peer_id, {"type": "error", "message": "You are not in a dungeon!"})
		return

	# In combat?
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot move while in combat!"})
		return

	# Accept direction strings from client
	var direction = message.get("direction", "")
	var dx = 0
	var dy = 0

	match direction:
		"n":
			dy = -1
		"s":
			dy = 1
		"w":
			dx = -1
		"e":
			dx = 1
		"none":
			# Just refresh state, no movement
			_send_dungeon_state(peer_id)
			return
		_:
			# Try dx/dy format
			dx = message.get("dx", 0)
			dy = message.get("dy", 0)

	# Clamp movement to one tile
	dx = clampi(dx, -1, 1)
	dy = clampi(dy, -1, 1)

	if dx == 0 and dy == 0:
		_send_dungeon_state(peer_id)
		return

	var new_x = character.dungeon_x + dx
	var new_y = character.dungeon_y + dy

	# Get current floor grid
	var instance_id = character.current_dungeon_id
	if not dungeon_floors.has(instance_id):
		send_to_peer(peer_id, {"type": "error", "message": "Dungeon instance not found!"})
		character.exit_dungeon()
		return

	var floor_grids = dungeon_floors[instance_id]
	if character.dungeon_floor >= floor_grids.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid floor!"})
		return

	var grid = floor_grids[character.dungeon_floor]

	# Check bounds
	if new_y < 0 or new_y >= grid.size() or new_x < 0 or new_x >= grid[0].size():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]You can't go that way.[/color]"})
		return

	# Check for wall
	var tile = grid[new_y][new_x]
	if tile == DungeonDatabaseScript.TileType.WALL:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]A wall blocks your path.[/color]"})
		return

	# Move player
	character.dungeon_x = new_x
	character.dungeon_y = new_y

	# Handle tile interaction
	match tile:
		DungeonDatabaseScript.TileType.ENCOUNTER:
			_start_dungeon_encounter(peer_id, false)
		DungeonDatabaseScript.TileType.BOSS:
			_start_dungeon_encounter(peer_id, true)
		DungeonDatabaseScript.TileType.TREASURE:
			_open_dungeon_treasure(peer_id)
		DungeonDatabaseScript.TileType.EXIT:
			_advance_dungeon_floor(peer_id)
		_:
			_send_dungeon_state(peer_id)

func handle_dungeon_exit(peer_id: int):
	"""Handle player exiting dungeon"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	if not character.in_dungeon:
		send_to_peer(peer_id, {"type": "error", "message": "You are not in a dungeon!"})
		return

	# Remove from dungeon
	var instance_id = character.current_dungeon_id
	if active_dungeons.has(instance_id):
		var instance = active_dungeons[instance_id]
		instance.active_players.erase(peer_id)

	# Exit dungeon
	character.exit_dungeon()

	send_to_peer(peer_id, {
		"type": "dungeon_exit",
		"message": "[color=#FFD700]You leave the dungeon.[/color]"
	})

	send_location_update(peer_id)
	send_character_update(peer_id)
	save_character(peer_id)

func _create_dungeon_instance(dungeon_type: String) -> String:
	"""Create a new dungeon instance. Returns instance ID."""
	if active_dungeons.size() >= MAX_ACTIVE_DUNGEONS:
		return ""

	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	if dungeon_data.is_empty():
		return ""

	var instance_id = "dungeon_%d" % next_dungeon_id
	next_dungeon_id += 1

	# Get spawn location
	var spawn_loc = DungeonDatabaseScript.get_spawn_location_for_tier(dungeon_data.tier)

	# Create instance
	active_dungeons[instance_id] = {
		"instance_id": instance_id,
		"dungeon_type": dungeon_type,
		"world_x": spawn_loc.x,
		"world_y": spawn_loc.y,
		"spawned_at": int(Time.get_unix_time_from_system()),
		"active_players": [],
		"dungeon_level": dungeon_data.min_level + randi() % (dungeon_data.max_level - dungeon_data.min_level + 1)
	}

	# Generate all floor grids
	var floor_grids = []
	for floor_num in range(dungeon_data.floors):
		var is_boss_floor = floor_num == dungeon_data.floors - 1
		var grid = DungeonDatabaseScript.generate_floor_grid(dungeon_type, floor_num, is_boss_floor)
		floor_grids.append(grid)

	dungeon_floors[instance_id] = floor_grids

	log_message("Created dungeon instance: %s (%s)" % [instance_id, dungeon_data.name])
	return instance_id

func _ensure_starter_dungeon_exists():
	"""Ensure a tier 1 dungeon exists near the starting area for new players"""
	var STARTER_AREA_RADIUS = 40  # Check within this distance of origin
	var SPAWN_DISTANCE = 30  # Spawn around this distance from origin

	# Check if there's already a tier 1 dungeon near the origin
	for instance_id in active_dungeons:
		var instance = active_dungeons[instance_id]
		var dungeon_data = DungeonDatabaseScript.get_dungeon(instance.dungeon_type)
		if dungeon_data.tier == 1:
			var distance = sqrt(instance.world_x * instance.world_x + instance.world_y * instance.world_y)
			if distance <= STARTER_AREA_RADIUS:
				# Already have a tier 1 dungeon near spawn
				return

	# No tier 1 dungeon near origin - spawn one
	if active_dungeons.size() >= MAX_ACTIVE_DUNGEONS:
		return  # Can't spawn more

	# Pick a random tier 1 dungeon type
	var tier1_dungeons = ["goblin_caves", "wolf_den"]
	var dungeon_type = tier1_dungeons[randi() % tier1_dungeons.size()]

	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	if dungeon_data.is_empty():
		return

	var instance_id = "dungeon_%d" % next_dungeon_id
	next_dungeon_id += 1

	# Spawn at a specific distance from origin (around 30 tiles)
	var angle = randf() * TAU
	var spawn_x = int(cos(angle) * SPAWN_DISTANCE)
	var spawn_y = int(sin(angle) * SPAWN_DISTANCE)

	# Create instance
	active_dungeons[instance_id] = {
		"instance_id": instance_id,
		"dungeon_type": dungeon_type,
		"world_x": spawn_x,
		"world_y": spawn_y,
		"spawned_at": int(Time.get_unix_time_from_system()),
		"active_players": [],
		"dungeon_level": dungeon_data.min_level + randi() % (dungeon_data.max_level - dungeon_data.min_level + 1)
	}

	# Generate all floor grids
	var floor_grids = []
	for floor_num in range(dungeon_data.floors):
		var is_boss_floor = floor_num == dungeon_data.floors - 1
		var grid = DungeonDatabaseScript.generate_floor_grid(dungeon_type, floor_num, is_boss_floor)
		floor_grids.append(grid)

	dungeon_floors[instance_id] = floor_grids

	log_message("Spawned starter dungeon: %s (%s) at (%d, %d)" % [instance_id, dungeon_data.name, spawn_x, spawn_y])

func _check_dungeon_spawns():
	"""Periodically check and spawn new dungeons at random locations"""
	# Don't spawn if at max
	if active_dungeons.size() >= MAX_ACTIVE_DUNGEONS:
		return

	# Clean up expired dungeons first
	var current_time = int(Time.get_unix_time_from_system())
	var dungeons_to_remove = []
	for instance_id in active_dungeons:
		var instance = active_dungeons[instance_id]
		var dungeon_data = DungeonDatabaseScript.get_dungeon(instance.dungeon_type)
		var duration_hours = dungeon_data.get("cooldown_hours", 24)
		var max_age = duration_hours * 3600
		if current_time - instance.spawned_at > max_age and instance.active_players.is_empty():
			dungeons_to_remove.append(instance_id)

	for instance_id in dungeons_to_remove:
		log_message("Dungeon expired: %s" % instance_id)
		active_dungeons.erase(instance_id)
		dungeon_floors.erase(instance_id)

	# Spawn new dungeons based on what's missing
	var dungeon_types = DungeonDatabaseScript.DUNGEON_TYPES.keys()
	for dungeon_type in dungeon_types:
		# Check if this type already has an active instance
		var has_instance = false
		for instance_id in active_dungeons:
			if active_dungeons[instance_id].dungeon_type == dungeon_type:
				has_instance = true
				break

		if not has_instance and active_dungeons.size() < MAX_ACTIVE_DUNGEONS:
			# Roll spawn chance based on dungeon weight
			var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
			var spawn_chance = dungeon_data.get("spawn_weight", 10)
			if randi() % 100 < spawn_chance:
				_create_dungeon_instance(dungeon_type)

func _get_dungeon_at_location(x: int, y: int) -> Dictionary:
	"""Check if there's a dungeon entrance at the given coordinates"""
	for instance_id in active_dungeons:
		var instance = active_dungeons[instance_id]
		if instance.world_x == x and instance.world_y == y:
			var dungeon_data = DungeonDatabaseScript.get_dungeon(instance.dungeon_type)
			return {
				"instance_id": instance_id,
				"dungeon_type": instance.dungeon_type,
				"name": dungeon_data.name,
				"tier": dungeon_data.tier,
				"min_level": dungeon_data.min_level,
				"max_level": dungeon_data.max_level,
				"color": dungeon_data.color
			}
	return {}

func get_visible_dungeons(center_x: int, center_y: int, radius: int) -> Array:
	"""Get all dungeon entrances visible within the given radius"""
	var visible = []
	for instance_id in active_dungeons:
		var instance = active_dungeons[instance_id]
		var dx = abs(instance.world_x - center_x)
		var dy = abs(instance.world_y - center_y)
		if dx <= radius and dy <= radius:
			var dungeon_data = DungeonDatabaseScript.get_dungeon(instance.dungeon_type)
			visible.append({
				"x": instance.world_x,
				"y": instance.world_y,
				"color": dungeon_data.color
			})
	return visible

func _get_direction_text(from_x: int, from_y: int, to_x: int, to_y: int) -> String:
	"""Get a compass direction text from one point to another"""
	var dx = to_x - from_x
	var dy = to_y - from_y
	var distance = int(sqrt(dx * dx + dy * dy))

	# Determine direction based on angle
	var direction = ""
	if abs(dy) < abs(dx) / 3:
		# Mostly horizontal
		direction = "east" if dx > 0 else "west"
	elif abs(dx) < abs(dy) / 3:
		# Mostly vertical
		direction = "north" if dy > 0 else "south"
	else:
		# Diagonal
		var ns = "north" if dy > 0 else "south"
		var ew = "east" if dx > 0 else "west"
		direction = ns + ew

	return "%d tiles %s" % [distance, direction]

func _find_nearest_dungeon_for_quest(from_x: int, from_y: int, dungeon_type: String, tier: int) -> Dictionary:
	"""Find the nearest dungeon matching the quest requirements. Returns {x, y, distance, direction_text} or empty dict."""
	var nearest = {}
	var nearest_dist = 999999

	for instance_id in active_dungeons:
		var instance = active_dungeons[instance_id]
		var dungeon_data = DungeonDatabaseScript.get_dungeon(instance.dungeon_type)

		# Check if this dungeon matches the quest requirements
		var matches = false
		if dungeon_type.is_empty():
			# Any dungeon - check tier matches (tier 1 dungeons for early quests)
			if tier <= 0 or dungeon_data.tier <= tier:
				matches = true
		else:
			# Specific dungeon type required
			if instance.dungeon_type == dungeon_type:
				matches = true

		if matches:
			var dx = instance.world_x - from_x
			var dy = instance.world_y - from_y
			var dist = sqrt(dx * dx + dy * dy)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = {
					"x": instance.world_x,
					"y": instance.world_y,
					"distance": int(dist),
					"direction_text": _get_direction_text(from_x, from_y, instance.world_x, instance.world_y),
					"dungeon_type": instance.dungeon_type,
					"dungeon_name": dungeon_data.name
				}

	return nearest

func _add_dungeon_directions_to_quests(quests: Array, tp_x: int, tp_y: int) -> Array:
	"""Add direction info to dungeon quests"""
	var updated_quests = []
	for quest in quests:
		var updated_quest = quest.duplicate()

		# Check if this is a dungeon quest
		if quest.get("type") == quest_db.QuestType.DUNGEON_CLEAR:
			var dungeon_type = quest.get("dungeon_type", "")
			# For starter quest, use tier 1; for dynamic quests, extract tier from quest
			var tier = 1 if quest.get("id", "").begins_with("haven_") else 0

			var nearest = _find_nearest_dungeon_for_quest(tp_x, tp_y, dungeon_type, tier)
			if not nearest.is_empty():
				# Add direction info to description
				var direction_hint = "\n\n[color=#00FFFF]Nearest dungeon:[/color] %s (%s)" % [
					nearest.dungeon_name, nearest.direction_text
				]
				updated_quest["description"] = quest.get("description", "") + direction_hint

		updated_quests.append(updated_quest)

	return updated_quests

func _send_dungeon_state(peer_id: int):
	"""Send current dungeon state to player"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	if not character.in_dungeon:
		return

	var instance_id = character.current_dungeon_id
	if not active_dungeons.has(instance_id) or not dungeon_floors.has(instance_id):
		return

	var instance = active_dungeons[instance_id]
	var dungeon_data = DungeonDatabaseScript.get_dungeon(character.current_dungeon_type)
	var floor_grids = dungeon_floors[instance_id]
	var grid = floor_grids[character.dungeon_floor]

	# Get current tile
	var current_tile = grid[character.dungeon_y][character.dungeon_x]

	send_to_peer(peer_id, {
		"type": "dungeon_state",
		"dungeon_type": character.current_dungeon_type,
		"dungeon_name": dungeon_data.name,
		"floor": character.dungeon_floor + 1,
		"total_floors": dungeon_data.floors,
		"grid": grid,
		"player_x": character.dungeon_x,
		"player_y": character.dungeon_y,
		"current_tile": current_tile,
		"encounters_cleared": character.dungeon_encounters_cleared,
		"color": dungeon_data.color
	})

func _find_tile_position(grid: Array, tile_type: int) -> Vector2i:
	"""Find position of a tile type in grid"""
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == tile_type:
				return Vector2i(x, y)
	return Vector2i(1, grid.size() - 2)  # Default to bottom-left interior

func _start_dungeon_encounter(peer_id: int, is_boss: bool):
	"""Start a dungeon combat encounter"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var instance_id = character.current_dungeon_id
	if not active_dungeons.has(instance_id):
		return

	var instance = active_dungeons[instance_id]
	var dungeon_data = DungeonDatabaseScript.get_dungeon(character.current_dungeon_type)

	# Generate monster
	var monster_info: Dictionary
	if is_boss:
		monster_info = DungeonDatabaseScript.get_boss_for_dungeon(character.current_dungeon_type, instance.dungeon_level)
	else:
		monster_info = DungeonDatabaseScript.get_monster_for_encounter(character.current_dungeon_type, character.dungeon_floor, instance.dungeon_level)

	if monster_info.is_empty():
		_send_dungeon_state(peer_id)
		return

	# Create combat
	var monster = monster_db.get_monster_for_level(monster_info.level)
	monster.name = monster_info.name
	monster.level = monster_info.level
	monster.is_dungeon_monster = true

	# Apply boss multipliers
	if is_boss:
		monster.max_hp = int(monster.max_hp * monster_info.get("hp_mult", 2.0))
		monster.current_hp = monster.max_hp
		monster.attack = int(monster.attack * monster_info.get("attack_mult", 1.5))
		monster.is_boss = true

	# Start combat
	combat_mgr.start_combat(peer_id, character, monster)
	var combat_state = combat_mgr.get_active_combat(peer_id)

	# Mark as dungeon combat for special handling
	combat_state["is_dungeon_combat"] = true
	combat_state["is_boss_fight"] = is_boss

	send_to_peer(peer_id, {
		"type": "combat_start",
		"monster_name": monster.name,
		"monster_level": monster.level,
		"monster_hp": monster.max_hp if character.knows_monster(monster.name, monster.level) else -1,
		"combat_state": combat_state,
		"is_dungeon_combat": true,
		"is_boss": is_boss,
		"combat_bg_color": dungeon_data.color
	})

func _open_dungeon_treasure(peer_id: int):
	"""Open a treasure chest in dungeon"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var instance_id = character.current_dungeon_id

	# Get treasure
	var treasure = DungeonDatabaseScript.roll_treasure(character.current_dungeon_type, character.dungeon_floor)

	# Give rewards
	var reward_messages = []

	# Gold
	if treasure.gold > 0:
		character.gold += treasure.gold
		reward_messages.append("[color=#FFD700]+%d Gold[/color]" % treasure.gold)

	# Materials
	for mat in treasure.get("materials", []):
		character.add_crafting_material(mat.id, mat.quantity)
		var qty_text = " x%d" % mat.quantity if mat.quantity > 1 else ""
		reward_messages.append("[color=#1EFF00]+%s%s[/color]" % [mat.id.capitalize().replace("_", " "), qty_text])

	# Egg
	var egg_info = treasure.get("egg", {})
	if not egg_info.is_empty():
		var egg_data = drop_tables.get_egg_for_monster(egg_info.monster)
		if not egg_data.is_empty():
			var egg_result = character.add_egg(egg_data)
			if egg_result.success:
				reward_messages.append("[color=#A335EE]★ %s ★[/color]" % egg_data.name)

	# Mark tile as cleared
	_clear_dungeon_tile(peer_id)

	send_to_peer(peer_id, {
		"type": "dungeon_treasure",
		"rewards": reward_messages,
		"message": "[color=#FFD700]You open the treasure chest![/color]"
	})

	_send_dungeon_state(peer_id)
	send_character_update(peer_id)
	save_character(peer_id)

func _advance_dungeon_floor(peer_id: int):
	"""Move player to next floor of dungeon"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var instance_id = character.current_dungeon_id
	var dungeon_data = DungeonDatabaseScript.get_dungeon(character.current_dungeon_type)

	# Check if this was the last floor
	if character.dungeon_floor >= dungeon_data.floors - 1:
		# Dungeon complete!
		_complete_dungeon(peer_id)
		return

	# Get next floor grid
	var floor_grids = dungeon_floors[instance_id]
	var next_floor = character.dungeon_floor + 1

	if next_floor >= floor_grids.size():
		_complete_dungeon(peer_id)
		return

	# Find entrance on next floor
	var next_grid = floor_grids[next_floor]
	var entrance_pos = _find_tile_position(next_grid, DungeonDatabaseScript.TileType.ENTRANCE)

	# Advance floor
	character.advance_dungeon_floor(entrance_pos.x, entrance_pos.y)

	send_to_peer(peer_id, {
		"type": "dungeon_floor_change",
		"floor": character.dungeon_floor + 1,
		"total_floors": dungeon_data.floors,
		"message": "[color=#FFFF00]You descend to floor %d...[/color]" % (character.dungeon_floor + 1)
	})

	_send_dungeon_state(peer_id)
	save_character(peer_id)

func _complete_dungeon(peer_id: int):
	"""Handle dungeon completion"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var dungeon_type = character.current_dungeon_type
	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	var instance_id = character.current_dungeon_id

	# Calculate rewards
	var rewards = DungeonDatabaseScript.calculate_completion_rewards(dungeon_type, character.dungeon_floor + 1)

	# Give rewards
	character.gold += rewards.gold
	var xp_result = character.gain_experience(rewards.xp, character.level)

	# Give GUARANTEED boss egg!
	var boss_egg_given = false
	var boss_egg_name = ""
	var boss_egg_monster = rewards.get("boss_egg", "")
	if boss_egg_monster != "":
		var egg_data = drop_tables.get_egg_for_monster(boss_egg_monster)
		if not egg_data.is_empty():
			var egg_result = character.add_egg(egg_data)
			if egg_result.success:
				boss_egg_given = true
				boss_egg_name = egg_data.get("name", boss_egg_monster + " Egg")

	# Set cooldown
	character.set_dungeon_cooldown(dungeon_type, dungeon_data.cooldown_hours)
	character.record_dungeon_completion(dungeon_type)

	# Check dungeon quest progress
	var quest_updates = quest_mgr.check_dungeon_progress(character, dungeon_type)
	for update in quest_updates:
		send_to_peer(peer_id, {
			"type": "quest_progress",
			"quest_id": update.quest_id,
			"progress": update.progress,
			"target": update.target,
			"completed": update.completed,
			"message": update.message
		})

	# Remove from dungeon
	if active_dungeons.has(instance_id):
		active_dungeons[instance_id].active_players.erase(peer_id)

	character.exit_dungeon()

	# Build completion message
	var completion_msg = "[color=#FFD700]===== DUNGEON COMPLETE! =====[/color]\n"
	completion_msg += "[color=#00FF00]%s Cleared![/color]\n\n" % dungeon_data.name
	completion_msg += "Floors Cleared: %d/%d\n" % [rewards.floors_cleared, rewards.total_floors]
	completion_msg += "[color=#FFD700]+%d Gold[/color]\n" % rewards.gold
	completion_msg += "[color=#00BFFF]+%d XP[/color]\n" % rewards.xp

	# Show boss egg reward!
	if boss_egg_given:
		completion_msg += "[color=#FF69B4]★ %s obtained! ★[/color]" % boss_egg_name
	elif boss_egg_monster != "":
		completion_msg += "[color=#808080](Egg storage full - %s Egg not collected)[/color]" % boss_egg_monster

	if xp_result.leveled_up:
		completion_msg += "\n[color=#FFFF00]★ LEVEL UP! Now level %d ★[/color]" % character.level

	send_to_peer(peer_id, {
		"type": "dungeon_complete",
		"dungeon_name": dungeon_data.name,
		"rewards": rewards,
		"leveled_up": xp_result.leveled_up,
		"new_level": character.level,
		"message": completion_msg
	})

	send_location_update(peer_id)
	send_character_update(peer_id)
	save_character(peer_id)

	log_message("Player %s completed dungeon %s!" % [character.name, dungeon_data.name])

func _clear_dungeon_tile(peer_id: int):
	"""Mark current dungeon tile as cleared"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var instance_id = character.current_dungeon_id

	if not dungeon_floors.has(instance_id):
		return

	var floor_grids = dungeon_floors[instance_id]
	if character.dungeon_floor >= floor_grids.size():
		return

	var grid = floor_grids[character.dungeon_floor]
	var current_tile = grid[character.dungeon_y][character.dungeon_x]

	# Only clear encounter/treasure tiles
	if current_tile in [DungeonDatabaseScript.TileType.ENCOUNTER, DungeonDatabaseScript.TileType.TREASURE, DungeonDatabaseScript.TileType.BOSS]:
		grid[character.dungeon_y][character.dungeon_x] = DungeonDatabaseScript.TileType.CLEARED
		character.dungeon_encounters_cleared += 1

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

func _migrate_title_items(character: Character) -> bool:
	"""Migrate any corrupted title items in inventory to proper format.
	Returns true if any items were fixed."""
	var fixed_any = false
	var title_items_data = TitlesScript.TITLE_ITEMS

	for i in range(character.inventory.size()):
		var item = character.inventory[i]
		var item_name = item.get("name", "").to_lower()
		var item_type = item.get("type", "")

		# Check for Jarl's Ring variants (including themed "Band" versions)
		if ("jarl" in item_name and ("ring" in item_name or "band" in item_name)) or item_type == "jarls_ring":
			var proper_item = title_items_data.get("jarls_ring", {})
			if not proper_item.is_empty():
				# Only fix if item is corrupted (has stats, wrong type, missing is_title_item)
				if item.get("is_title_item", false) == false or item.has("level") or item.has("attack_bonus") or item.has("str_bonus") or item.has("dex_bonus"):
					character.inventory[i] = {
						"type": "jarls_ring",
						"name": proper_item.get("name", "Jarl's Ring"),
						"rarity": proper_item.get("rarity", "legendary"),
						"description": proper_item.get("description", ""),
						"is_title_item": true
					}
					fixed_any = true
					log_message("Fixed corrupted Jarl's Ring for %s" % character.name)

		# Check for Unforged Crown variants
		elif "unforged" in item_name and "crown" in item_name or item_type == "unforged_crown":
			var proper_item = title_items_data.get("unforged_crown", {})
			if not proper_item.is_empty():
				if item.get("is_title_item", false) == false or item.has("level") or item.has("attack_bonus"):
					character.inventory[i] = {
						"type": "unforged_crown",
						"name": proper_item.get("name", "Unforged Crown"),
						"rarity": proper_item.get("rarity", "legendary"),
						"description": proper_item.get("description", ""),
						"is_title_item": true
					}
					fixed_any = true
					log_message("Fixed corrupted Unforged Crown for %s" % character.name)

		# Check for Crown of the North variants
		elif ("crown" in item_name and "north" in item_name) or item_type == "crown_of_north":
			var proper_item = title_items_data.get("crown_of_north", {})
			if not proper_item.is_empty():
				if item.get("is_title_item", false) == false or item.has("level") or item.has("attack_bonus"):
					character.inventory[i] = {
						"type": "crown_of_north",
						"name": proper_item.get("name", "Crown of the North"),
						"rarity": proper_item.get("rarity", "artifact"),
						"description": proper_item.get("description", ""),
						"is_title_item": true
					}
					fixed_any = true
					log_message("Fixed corrupted Crown of the North for %s" % character.name)

	return fixed_any

func _has_title_item(character: Character, item_type: String) -> bool:
	"""Check if character has a specific title item in inventory"""
	for item in character.inventory:
		if item.get("type", "") == item_type:
			return true
	return false

func _convert_bugged_title_items(character: Character) -> bool:
	"""Convert bugged title items (rings/crowns with stats) to proper title items.
	Returns true if any conversion was made."""
	var converted = false

	for i in range(character.inventory.size()):
		var item = character.inventory[i]
		var item_name = item.get("name", "").to_lower()
		var item_type = item.get("type", "")

		# Check for bugged Jarl's Ring (has stats, wrong type)
		if "jarl" in item_name and "ring" in item_name and item_type != "jarls_ring":
			character.inventory[i] = {
				"type": "jarls_ring",
				"name": "Jarl's Ring",
				"rarity": "legendary",
				"description": "An arm ring of silver and oath. Claim The High Seat at (0,0).",
				"is_title_item": true
			}
			converted = true
			print("[TITLE] Converted bugged Jarl's Ring for %s" % character.name)

		# Check for bugged Unforged Crown
		if "unforged" in item_name and "crown" in item_name and item_type != "unforged_crown":
			character.inventory[i] = {
				"type": "unforged_crown",
				"name": "Unforged Crown",
				"rarity": "legendary",
				"description": "Take this to the Infernal Forge at Fire Mountain (-400,0).",
				"is_title_item": true
			}
			converted = true
			print("[TITLE] Converted bugged Unforged Crown for %s" % character.name)

		# Check for bugged Crown of the North
		if "crown" in item_name and "north" in item_name and item_type != "crown_of_north":
			character.inventory[i] = {
				"type": "crown_of_north",
				"name": "Crown of the North",
				"rarity": "artifact",
				"description": "Forged in flame. Claim the throne of the High King at (0,0).",
				"is_title_item": true
			}
			converted = true
			print("[TITLE] Converted bugged Crown of the North for %s" % character.name)

	return converted

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
		character.init_pilgrimage()  # Start the Eternal Pilgrimage journey
		broadcast_title_change(character.name, "elder", "achieved")
		send_to_peer(peer_id, {
			"type": "title_achieved",
			"title": "elder",
			"message": "[color=#9400D3]You have reached level 1000 and become an Elder of the realm![/color]\n[color=#FFD700]Your journey to become Eternal begins... Use Seek Flame to check your progress.[/color]"
		})
		save_character(peer_id)

func handle_title_ability(peer_id: int, message: Dictionary):
	"""Handle using a title ability"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var ability_id = message.get("ability", "")
	var target_name = message.get("target", "")
	var stat_choice = message.get("stat_choice", "")  # For Bless ability

	if character.title.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "You don't have a title."})
		return

	var abilities = TitlesScript.get_title_abilities(character.title)
	if not abilities.has(ability_id):
		send_to_peer(peer_id, {"type": "error", "message": "You don't have that ability."})
		return

	var ability = abilities[ability_id]

	# Check cooldown
	if ability.has("cooldown") and character.is_ability_on_cooldown(ability_id):
		var remaining = character.get_ability_cooldown_remaining(ability_id)
		var hours = remaining / 3600
		var minutes = (remaining % 3600) / 60
		var time_str = ""
		if hours > 0:
			time_str = "%dh %dm" % [hours, minutes]
		else:
			time_str = "%dm" % minutes
		send_to_peer(peer_id, {"type": "error", "message": "Ability on cooldown (%s remaining)." % time_str})
		return

	# Check and consume gold cost
	var gold_cost = ability.get("gold_cost", 0)
	if ability.has("gold_cost_percent"):
		gold_cost = int(character.gold * ability.gold_cost_percent / 100.0)
	if gold_cost > 0:
		if character.gold < gold_cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough gold (%d required)." % gold_cost})
			return

	# Check gem cost
	var gem_cost = ability.get("gem_cost", 0)
	if gem_cost > 0:
		if character.gems < gem_cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough gems (%d required)." % gem_cost})
			return

	# Find target if needed
	var target_peer_id = -1
	var target: Character = null
	if ability.get("target", "self") == "player" and not target_name.is_empty():
		target_peer_id = _get_peer_id_for_character_name(target_name)
		if target_peer_id == -1:
			send_to_peer(peer_id, {"type": "error", "message": "Player '%s' not found online." % target_name})
			return
		target = characters.get(target_peer_id)

		# Check max target level for Mentor
		if ability.has("max_target_level") and target.level > ability.max_target_level:
			send_to_peer(peer_id, {"type": "error", "message": "Target must be below level %d." % ability.max_target_level})
			return

	# Deduct costs after all checks pass
	if gold_cost > 0:
		character.gold -= gold_cost
	if gem_cost > 0:
		character.gems -= gem_cost

	# Set cooldown
	if ability.has("cooldown"):
		character.set_ability_cooldown(ability_id, ability.cooldown)

	# Track abuse for negative abilities
	if ability.get("is_negative", false) and target:
		_track_title_abuse(peer_id, character, target_peer_id, target)

	# Execute ability
	_execute_title_ability(peer_id, character, ability_id, target_peer_id, target, stat_choice)
	send_character_update(peer_id)
	save_character(peer_id)

func _track_title_abuse(peer_id: int, character: Character, target_peer_id: int, target: Character):
	"""Track abuse points for negative title abilities"""
	# Decay existing points first
	character.decay_abuse_points()

	# Check for same target within window
	var same_target_count = character.count_recent_targets(target.name)
	if same_target_count > 0:
		character.add_abuse_points(TitlesScript.ABUSE_SETTINGS.same_target_points)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]Warning: Targeting the same player repeatedly (+%d abuse points)[/color]" % TitlesScript.ABUSE_SETTINGS.same_target_points
		})

	# Check for punching down (level difference)
	var level_diff = character.level - target.level
	if level_diff >= TitlesScript.ABUSE_SETTINGS.level_diff_threshold:
		character.add_abuse_points(TitlesScript.ABUSE_SETTINGS.level_diff_points)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]Warning: Targeting much lower level player (+%d abuse points)[/color]" % TitlesScript.ABUSE_SETTINGS.level_diff_points
		})

	# Check if target is in combat
	if combat_mgr.is_in_combat(target_peer_id):
		character.add_abuse_points(TitlesScript.ABUSE_SETTINGS.combat_interference_points)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]Warning: Interfering with player in combat (+%d abuse points)[/color]" % TitlesScript.ABUSE_SETTINGS.combat_interference_points
		})

	# Record this target
	character.record_ability_target(target.name)
	character.record_ability_use()

	# Check for spam
	var recent_uses = character.count_recent_ability_uses()
	if recent_uses >= TitlesScript.ABUSE_SETTINGS.spam_threshold:
		character.add_abuse_points(TitlesScript.ABUSE_SETTINGS.spam_points)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]Warning: Spamming abilities (+%d abuse points)[/color]" % TitlesScript.ABUSE_SETTINGS.spam_points
		})

	# Check if over threshold - lose title
	var threshold = TitlesScript.get_abuse_threshold(character.title)
	if character.get_abuse_points() >= threshold:
		_revoke_title_for_abuse(peer_id, character)

func _revoke_title_for_abuse(peer_id: int, character: Character):
	"""Revoke a title due to abuse"""
	var old_title = character.title
	var title_name = TitlesScript.get_title_name(old_title)

	# Clear title
	character.title = ""
	character.title_data = {}
	character.clear_abuse_tracking()
	character.clear_ability_cooldowns()

	# Update tracking
	if old_title == "jarl":
		current_jarl_id = -1
	elif old_title == "high_king":
		current_high_king_id = -1
		# Also clear knight status
		if current_knight_peer_id != -1 and characters.has(current_knight_peer_id):
			var knight = characters[current_knight_peer_id]
			knight.clear_knight_status()
			send_to_peer(current_knight_peer_id, {
				"type": "text",
				"message": "[color=#FF4444]Your Knight status has been revoked - the High King has fallen![/color]"
			})
			save_character(current_knight_peer_id)
		current_knight_peer_id = -1

	# Notify player
	send_to_peer(peer_id, {
		"type": "title_lost",
		"title": old_title,
		"message": "[color=#FF4444]You have abused your powers as %s! Your title has been REVOKED![/color]" % title_name
	})

	# Broadcast to realm
	broadcast_title_change(character.name, old_title, "revoked for abuse")
	save_character(peer_id)

func _execute_title_ability(peer_id: int, character: Character, ability_id: String, target_peer_id: int, target: Character, stat_choice: String):
	"""Execute a specific title ability"""
	var title_color = TitlesScript.get_title_color(character.title)
	var title_name = TitlesScript.get_title_name(character.title)

	match ability_id:
		# ===== JARL ABILITIES =====
		"summon":
			if target:
				# Send summon request to target (requires consent)
				pending_summons[target_peer_id] = {
					"from_peer_id": peer_id,
					"from_name": character.name,
					"x": character.x,
					"y": character.y,
					"timestamp": Time.get_unix_time_from_system()
				}
				send_to_peer(target_peer_id, {
					"type": "summon_request",
					"from_name": character.name,
					"x": character.x,
					"y": character.y
				})
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#C0C0C0]Summon request sent to %s. Awaiting response...[/color]" % target.name
				})

		"tax_player":
			if target:
				var tax_amount = mini(10000, int(target.gold * 0.10))
				target.gold -= tax_amount
				character.gold += tax_amount
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#C0C0C0]The Jarl has taxed you %d gold![/color]" % tax_amount
				})
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You collected %d gold in taxes from %s.[/color]" % [tax_amount, target.name]
				})
				_broadcast_chat_from_title(character.name, character.title, "has taxed %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"gift_silver":
			if target:
				var gift_amount = int(character.gold * 0.08)  # They already paid 5%, give 8%
				target.gold += gift_amount
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#FFD700]The Jarl has gifted you %d gold![/color]" % gift_amount
				})
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You gifted %d gold to %s.[/color]" % [gift_amount, target.name]
				})
				_broadcast_chat_from_title(character.name, character.title, "has gifted %s with silver!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"collect_tribute":
			var abilities = TitlesScript.get_title_abilities(character.title)
			var treasury_percent = abilities["collect_tribute"].get("treasury_percent", 15)
			var current_treasury = persistence.get_realm_treasury()
			var tribute = int(current_treasury * treasury_percent / 100.0)
			if tribute > 0:
				var withdrawn = persistence.withdraw_from_realm_treasury(tribute)
				character.gold += withdrawn
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You claim %d gold from the realm treasury (%d%% of %d).[/color]" % [withdrawn, treasury_percent, current_treasury]
				})
			else:
				send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]The realm treasury is empty.[/color]"})

		# ===== HIGH KING ABILITIES =====
		"knight":
			if target:
				# Remove previous knight if exists
				if current_knight_peer_id != -1 and characters.has(current_knight_peer_id):
					var old_knight = characters[current_knight_peer_id]
					old_knight.clear_knight_status()
					send_to_peer(current_knight_peer_id, {
						"type": "text",
						"message": "[color=#808080]Your Knight status has ended - a new Knight has been appointed.[/color]"
					})
					send_character_update(current_knight_peer_id)
					save_character(current_knight_peer_id)

				# Set new knight
				target.set_knight_status(character.name, peer_id)
				current_knight_peer_id = target_peer_id
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#87CEEB]The High King has knighted you! You gain +15%% damage and +10%% gold permanently![/color]"
				})
				_broadcast_chat_from_title(character.name, character.title, "has knighted %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"cure":
			if target:
				target.cure_poison()
				target.cure_blind()
				# Only clear negative buffs, not positive ones
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FF00]The High King has cured all your ailments![/color]"
				})
				_broadcast_chat_from_title(character.name, character.title, "has cured %s of all ailments!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"exile":
			if target:
				var angle = randf() * TAU
				var offset_x = int(cos(angle) * 100)
				var offset_y = int(sin(angle) * 100)
				target.x = clampi(target.x + offset_x, -1000, 1000)
				target.y = clampi(target.y + offset_y, -1000, 1000)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#FFD700]The High King has exiled you! You find yourself at (%d, %d).[/color]" % [target.x, target.y]
				})
				_broadcast_chat_from_title(character.name, character.title, "has exiled %s!" % target.name)
				send_location_update(target_peer_id)
				save_character(target_peer_id)

		"royal_treasury":
			var abilities = TitlesScript.get_title_abilities(character.title)
			var treasury_percent = abilities["royal_treasury"].get("treasury_percent", 30)
			var current_treasury = persistence.get_realm_treasury()
			var tribute = int(current_treasury * treasury_percent / 100.0)
			if tribute > 0:
				var withdrawn = persistence.withdraw_from_realm_treasury(tribute)
				character.gold += withdrawn
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You claim %d gold from the royal treasury (%d%% of %d).[/color]" % [withdrawn, treasury_percent, current_treasury]
				})
			else:
				send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]The realm treasury is empty.[/color]"})

		# ===== ELDER ABILITIES =====
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

		"mentor":
			if target:
				# Remove previous mentee if exists for this elder
				if current_mentee_peer_ids.has(peer_id):
					var old_mentee_id = current_mentee_peer_ids[peer_id]
					if characters.has(old_mentee_id):
						var old_mentee = characters[old_mentee_id]
						old_mentee.clear_mentee_status()
						send_to_peer(old_mentee_id, {
							"type": "text",
							"message": "[color=#808080]Your Mentee status has ended - your Elder has taken a new student.[/color]"
						})
						send_character_update(old_mentee_id)
						save_character(old_mentee_id)

				# Set new mentee
				target.set_mentee_status(character.name, peer_id)
				current_mentee_peer_ids[peer_id] = target_peer_id
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#DDA0DD]Elder %s has taken you as their Mentee! You gain +30%% XP and +20%% gold permanently![/color]" % character.name
				})
				_broadcast_chat_from_title(character.name, character.title, "has taken %s as their Mentee!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"seek_flame":
			# Show pilgrimage progress instead of just flame location
			_show_pilgrimage_progress(peer_id, character)

		# ===== ETERNAL ABILITIES =====
		"restore":
			if target:
				target.current_hp = target.get_total_max_hp()
				target.current_mana = target.get_total_max_mana()
				target.current_stamina = target.get_total_max_stamina()
				target.current_energy = target.get_total_max_energy()
				target.cure_poison()
				target.cure_blind()
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FFFF]Eternal %s has fully restored you![/color]" % character.name
				})
				_broadcast_chat_from_title(character.name, character.title, "has fully restored %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"bless":
			if target:
				# Use chosen stat if provided, otherwise random
				var valid_stats = ["strength", "constitution", "dexterity", "intelligence", "wisdom", "wits"]
				var chosen_stat = stat_choice.to_lower() if stat_choice.to_lower() in valid_stats else valid_stats[randi() % valid_stats.size()]
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

		"smite":
			if target:
				target.apply_poison(25, 10)  # 25 poison for 10 rounds
				target.add_buff("smite_debuff", 25, 10)  # -25% damage for 10 rounds
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FFFF]Eternal %s has SMITED you! You are cursed.[/color]" % character.name
				})
				_broadcast_chat_from_title(character.name, character.title, "has unleashed divine wrath upon %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"guardian":
			if target:
				target.grant_guardian_death_save(character.name)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#00FFFF]Eternal %s has granted you the Guardian's blessing! You will survive one fatal blow.[/color]" % character.name
				})
				_broadcast_chat_from_title(character.name, character.title, "has blessed %s with the Guardian's protection!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

func _show_pilgrimage_progress(peer_id: int, character: Character):
	"""Show the Elder's progress towards becoming Eternal"""
	if character.pilgrimage_progress.is_empty():
		character.init_pilgrimage()

	var stage = character.get_pilgrimage_stage()
	var progress = character.pilgrimage_progress
	var msg = "[color=#9400D3]═══ ETERNAL PILGRIMAGE ═══[/color]\n"

	match stage:
		"awakening":
			var kills = progress.get("kills", 0)
			var required = TitlesScript.PILGRIMAGE_STAGES["awakening"].requirement
			msg += "[color=#FFD700]Stage 1: The Awakening[/color]\n"
			msg += "Slay monsters to awaken the flame within.\n"
			msg += "[color=#00FF00]Progress: %d / %d kills[/color]" % [kills, required]
			if kills >= required:
				msg += "\n[color=#00FFFF]COMPLETE! Beginning the Three Trials...[/color]"
				character.advance_pilgrimage_stage("trial_blood")

		"trial_blood", "trial_mind", "trial_wealth":
			msg += "[color=#FFD700]Stage 2: The Three Trials[/color]\n\n"

			# Blood
			var t8_kills = progress.get("tier8_kills", 0)
			var t8_req = TitlesScript.PILGRIMAGE_STAGES["trial_blood"].requirement
			var blood_done = character.is_pilgrimage_shrine_complete("blood")
			if blood_done:
				msg += "[color=#00FF00][X] Shrine of Blood - COMPLETE[/color]\n"
			else:
				msg += "[color=#FF6666][ ] Shrine of Blood: %d / %d Tier 8+ kills[/color]\n" % [t8_kills, t8_req]

			# Mind
			var outsmarts = progress.get("outsmarts", 0)
			var out_req = TitlesScript.PILGRIMAGE_STAGES["trial_mind"].requirement
			var mind_done = character.is_pilgrimage_shrine_complete("mind")
			if mind_done:
				msg += "[color=#00FF00][X] Shrine of Mind - COMPLETE[/color]\n"
			else:
				msg += "[color=#6666FF][ ] Shrine of Mind: %d / %d outsmarts[/color]\n" % [outsmarts, out_req]

			# Wealth
			var donated = progress.get("gold_donated", 0)
			var gold_req = TitlesScript.PILGRIMAGE_STAGES["trial_wealth"].requirement
			var wealth_done = character.is_pilgrimage_shrine_complete("wealth")
			if wealth_done:
				msg += "[color=#00FF00][X] Shrine of Wealth - COMPLETE[/color]\n"
			else:
				msg += "[color=#FFD700][ ] Shrine of Wealth: %d / %d gold donated[/color]\n" % [donated, gold_req]
				msg += "[color=#808080]    Use /donate <amount> to donate gold[/color]"

			# Check if all done
			if blood_done and mind_done and wealth_done:
				msg += "\n\n[color=#00FFFF]ALL TRIALS COMPLETE! Beginning the Ember Hunt...[/color]"
				character.advance_pilgrimage_stage("ember_hunt")

		"ember_hunt":
			var embers = progress.get("embers", 0)
			var required = TitlesScript.PILGRIMAGE_STAGES["ember_hunt"].requirement
			msg += "[color=#FFD700]Stage 3: The Ember Hunt[/color]\n"
			msg += "Collect Flame Embers from powerful monsters.\n"
			msg += "[color=#FF6600]Progress: %d / %d embers[/color]" % [embers, required]
			if embers >= required:
				msg += "\n[color=#00FFFF]COMPLETE! The Crucible awaits...[/color]"
				character.advance_pilgrimage_stage("crucible")

		"crucible":
			var bosses = progress.get("crucible_progress", 0)
			var required = TitlesScript.PILGRIMAGE_STAGES["crucible"].requirement
			msg += "[color=#FFD700]Stage 4: The Crucible[/color]\n"
			msg += "Defeat 10 Tier 9 bosses in succession.\n"
			msg += "[color=#FF4444]Progress: %d / %d bosses[/color]" % [bosses, required]
			msg += "\n[color=#808080]Death resets progress. Use /crucible to begin in a T9 zone.[/color]"
			if bosses >= required:
				msg += "\n[color=#00FFFF]THE CRUCIBLE IS COMPLETE![/color]"
				msg += "\n[color=#FFD700]The Eternal Flame reveals itself...[/color]"
				# Reveal flame location
				var dx = eternal_flame_location.x - character.x
				var dy = eternal_flame_location.y - character.y
				var distance = sqrt(dx * dx + dy * dy)
				var direction = ""
				if abs(dx) > abs(dy):
					direction = "east" if dx > 0 else "west"
				else:
					direction = "north" if dy > 0 else "south"
				msg += "\n[color=#00FFFF]The Eternal Flame burns %d-%d tiles to the %s![/color]" % [int(distance * 0.9), int(distance * 1.1), direction]

	send_to_peer(peer_id, {"type": "text", "message": msg})
	save_character(peer_id)

func _broadcast_chat_from_title(player_name: String, title_id: String, action_text: String):
	"""Broadcast a chat message for a title action"""
	var title_color = TitlesScript.get_title_color(title_id)
	var title_prefix = TitlesScript.get_title_prefix(title_id)
	var msg = "[color=%s]%s %s %s[/color]" % [title_color, title_prefix, player_name, action_text]

	for peer_id in characters.keys():
		send_to_peer(peer_id, {"type": "chat", "sender": "Realm", "message": msg})

# ===== PILGRIMAGE SYSTEM HANDLERS =====

func handle_pilgrimage_donate(peer_id: int, message: Dictionary):
	"""Handle gold donation for Trial of Wealth"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var amount = message.get("amount", 0)

	# Validate Elder status
	if character.title != "elder":
		send_to_peer(peer_id, {"type": "error", "message": "Only Elders can donate to the Shrine of Wealth."})
		return

	# Validate pilgrimage stage
	var stage = character.get_pilgrimage_stage()
	if stage not in ["trial_blood", "trial_mind", "trial_wealth"]:
		send_to_peer(peer_id, {"type": "error", "message": "You must complete The Awakening before donating."})
		return

	# Check if wealth shrine already complete
	if character.is_pilgrimage_shrine_complete("wealth"):
		send_to_peer(peer_id, {"type": "error", "message": "You have already completed the Trial of Wealth."})
		return

	# Validate amount
	if amount <= 0:
		send_to_peer(peer_id, {"type": "error", "message": "Invalid donation amount."})
		return

	if character.gold < amount:
		send_to_peer(peer_id, {"type": "error", "message": "You don't have enough gold."})
		return

	# Process donation
	character.gold -= amount
	character.add_pilgrimage_gold_donation(amount)

	var total_donated = character.pilgrimage_progress.get("gold_donated", 0)
	var required = TitlesScript.PILGRIMAGE_STAGES["trial_wealth"].requirement

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]You donate %d gold to the Shrine of Wealth.[/color]\n[color=#808080]Total donated: %d / %d gold[/color]" % [amount, total_donated, required]
	})

	# Check if shrine complete
	if total_donated >= required and not character.is_pilgrimage_shrine_complete("wealth"):
		character.complete_pilgrimage_shrine("wealth")
		# Award wisdom bonus
		var bonus = TitlesScript.PILGRIMAGE_STAGES["trial_wealth"].get("shrine_reward_amount", 3)
		character.wisdom += bonus
		character.calculate_derived_stats()
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]The Shrine of Wealth glows with acceptance![/color]\n[color=#00FF00]+%d Wisdom! The Trial of Wealth is COMPLETE![/color]" % bonus
		})

	send_character_update(peer_id)
	save_character(peer_id)

# Pending summon requests: {target_peer_id: {from_peer_id, from_name, x, y, timestamp}}
var pending_summons: Dictionary = {}

func handle_summon_response(peer_id: int, message: Dictionary):
	"""Handle player's response to a summon request"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var accept = message.get("accept", false)

	# Check for pending summon
	if not pending_summons.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "No pending summon request."})
		return

	var summon = pending_summons[peer_id]
	pending_summons.erase(peer_id)
	var from_peer_id = summon.from_peer_id

	if accept:
		# Teleport player to summoner's location
		character.x = summon.x
		character.y = summon.y
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#C0C0C0]You accept the summon and appear at (%d, %d)![/color]" % [character.x, character.y]
		})
		if characters.has(from_peer_id):
			send_to_peer(from_peer_id, {
				"type": "text",
				"message": "[color=#00FF00]%s has accepted your summon![/color]" % character.name
			})
		_broadcast_chat_from_title(characters[from_peer_id].name if characters.has(from_peer_id) else "A Jarl", "jarl", "has summoned %s!" % character.name)
		send_location_update(peer_id)
		send_character_update(peer_id)
		save_character(peer_id)
	else:
		# Decline
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]You decline the summon.[/color]"})
		if characters.has(from_peer_id):
			send_to_peer(from_peer_id, {
				"type": "text",
				"message": "[color=#FF4444]%s has declined your summon.[/color]" % character.name
			})
			# Refund costs
			var abilities = TitlesScript.get_title_abilities("jarl")
			var gold_cost = abilities.get("summon", {}).get("gold_cost", 500)
			characters[from_peer_id].gold += gold_cost
			send_to_peer(from_peer_id, {
				"type": "text",
				"message": "[color=#FFD700]%d gold refunded.[/color]" % gold_cost
			})
			send_character_update(from_peer_id)
			save_character(from_peer_id)

# Crucible state tracking: {peer_id: {in_crucible: bool, progress: int, current_boss: int}}
var crucible_state: Dictionary = {}

func handle_start_crucible(peer_id: int):
	"""Handle player starting the Crucible gauntlet"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Validate Elder status and pilgrimage stage
	if character.title != "elder":
		send_to_peer(peer_id, {"type": "error", "message": "Only Elders can attempt the Crucible."})
		return

	var stage = character.get_pilgrimage_stage()
	if stage != "crucible":
		send_to_peer(peer_id, {"type": "error", "message": "You must complete the Ember Hunt before the Crucible."})
		return

	# Check if already in crucible
	if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
		send_to_peer(peer_id, {"type": "error", "message": "You are already in the Crucible."})
		return

	# Check location - must be in a T9 zone
	var loc_info = world_system.get_location_info(Vector2i(character.x, character.y))
	var terrain = loc_info.get("terrain", "Plains")
	var terrain_data = world_system.get_terrain_info(terrain)
	var monster_level_range = terrain_data.get("monster_level_range", [1, 10])
	if monster_level_range[1] < 300:  # T9 monsters are level 300+
		send_to_peer(peer_id, {"type": "error", "message": "You must be in a high-level zone to start the Crucible."})
		return

	# Initialize crucible state
	crucible_state[peer_id] = {
		"in_crucible": true,
		"progress": character.pilgrimage_progress.get("crucible_progress", 0),
		"current_boss": character.pilgrimage_progress.get("crucible_progress", 0) + 1
	}

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF4444]═══ THE CRUCIBLE BEGINS ═══[/color]\n\n[color=#FFD700]Face 10 consecutive Tier 9 bosses![/color]\n[color=#FF0000]Death will reset all progress.[/color]\n\n[color=#00FFFF]Progress: %d/10[/color]\n\nThe first champion approaches..." % crucible_state[peer_id].progress
	})

	# Spawn first crucible boss
	_spawn_crucible_boss(peer_id)

func _spawn_crucible_boss(peer_id: int):
	"""Spawn a crucible boss for the player"""
	if not characters.has(peer_id) or not crucible_state.has(peer_id):
		return

	var character = characters[peer_id]
	var state = crucible_state[peer_id]
	var boss_num = state.current_boss

	# Get a T9 boss monster
	var boss_names = ["Ancient Dragon", "Void Lord", "Titan", "Arch-Demon", "Elder God"]
	var boss_name = boss_names[(boss_num - 1) % boss_names.size()]
	var boss_level = 350 + (boss_num * 10)  # Scales with progress

	var monster = monster_db.generate_monster_for_level(boss_level)
	if monster == null:
		monster = monster_db.create_specific_monster(boss_name, boss_level)

	# Enhance for crucible
	monster["is_boss"] = true
	monster["is_crucible"] = true
	monster["crucible_number"] = boss_num
	monster["current_hp"] = int(monster.get("hp", 1000) * 1.5)  # 50% more HP
	monster["hp"] = int(monster.get("hp", 1000) * 1.5)
	monster["strength"] = int(monster.get("strength", 50) * 1.25)  # 25% more strength

	# Start combat
	var result = combat_mgr.start_combat(peer_id, character, monster)
	if result.success:
		send_to_peer(peer_id, {
			"type": "combat_start",
			"monster": monster,
			"enemy_hp": monster.hp,
			"enemy_max_hp": monster.hp,
			"player_hp": character.current_hp,
			"player_max_hp": character.get_total_max_hp(),
			"special_message": "[color=#FF4444]CRUCIBLE BOSS %d/10: %s (Lv.%d)[/color]" % [boss_num, monster.name, boss_level]
		})

func handle_crucible_victory(peer_id: int):
	"""Handle player defeating a crucible boss"""
	if not characters.has(peer_id) or not crucible_state.has(peer_id):
		return

	var character = characters[peer_id]
	var state = crucible_state[peer_id]

	state.progress += 1
	state.current_boss += 1
	character.add_pilgrimage_crucible_progress()

	if state.progress >= 10:
		# Crucible complete!
		crucible_state.erase(peer_id)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]═══ THE CRUCIBLE IS COMPLETE! ═══[/color]\n\n[color=#FFD700]You have proven your worth![/color]\n[color=#00FF00]The Eternal Flame's location is now revealed.[/color]\n\nUse [Seek Flame] to find it."
		})
	else:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]Boss defeated! Progress: %d/10[/color]\n\nThe next champion approaches..." % state.progress
		})
		# Spawn next boss after brief delay (handled in _process or via timer)
		_spawn_crucible_boss(peer_id)

	save_character(peer_id)

func handle_crucible_death(peer_id: int):
	"""Handle player dying in the Crucible"""
	if not characters.has(peer_id) or not crucible_state.has(peer_id):
		return

	var character = characters[peer_id]

	# Reset crucible progress
	character.reset_pilgrimage_crucible()
	crucible_state.erase(peer_id)

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF4444]═══ THE CRUCIBLE FAILED ═══[/color]\n\n[color=#808080]Your progress has been reset.[/color]\n[color=#FFD700]Return when you are stronger.[/color]"
	})

	save_character(peer_id)

func handle_get_title_menu(peer_id: int):
	"""Send title menu data to client"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Convert any bugged title items first
	if _convert_bugged_title_items(character):
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]Your title items have been fixed![/color]"
		})
		send_character_update(peer_id)
		save_character(peer_id)

	# Get available claimable titles
	var claimable = []
	var title_hints = []  # Hints about what's needed to claim titles
	if character.x == 0 and character.y == 0:
		# At The High Seat - check for claimable titles
		var has_jarls_ring = _has_title_item(character, "jarls_ring")
		var has_crown = _has_title_item(character, "crown_of_north")

		# Jarl claim check
		if has_jarls_ring:
			if current_jarl_id != -1 and current_high_king_id == -1:
				title_hints.append("Jarl position already held")
			elif current_high_king_id != -1:
				title_hints.append("A High King rules - no Jarl needed")
			elif character.level < 50:
				title_hints.append("Jarl requires level 50+")
			elif character.level > 500:
				title_hints.append("Jarl max level is 500")
			else:
				claimable.append({"id": "jarl", "name": "Jarl"})
		else:
			title_hints.append("Need Jarl's Ring (drops from Lv50+ monsters)")

		# High King claim check
		if has_crown:
			if character.level < 200:
				title_hints.append("High King requires level 200+")
			elif character.level > 1000:
				title_hints.append("High King max level is 1000")
			else:
				claimable.append({"id": "high_king", "name": "High King"})
		else:
			title_hints.append("Need Crown of the North (forge Unforged Crown at Fire Mountain)")
	else:
		title_hints.append("Travel to The High Seat (0,0) to claim titles")

	# Get current title abilities
	var abilities = {}
	if not character.title.is_empty():
		abilities = TitlesScript.get_title_abilities(character.title)

	# Get online players for targeting
	var online_players = []
	for pid in characters.keys():
		if pid != peer_id:
			online_players.append(characters[pid].name)

	# Get abuse tracking info for Jarl/High King
	var abuse_points = 0
	var abuse_threshold = 999
	if character.title in ["jarl", "high_king"]:
		character.decay_abuse_points()  # Decay points before displaying
		abuse_points = character.get_abuse_points()
		abuse_threshold = TitlesScript.get_abuse_threshold(character.title)

	send_to_peer(peer_id, {
		"type": "title_menu",
		"current_title": character.title,
		"title_data": character.title_data,
		"claimable": claimable,
		"abilities": abilities,
		"online_players": online_players,
		"realm_treasury": persistence.get_realm_treasury() if character.title in ["jarl", "high_king"] else 0,
		"abuse_points": abuse_points,
		"abuse_threshold": abuse_threshold,
		"title_hints": title_hints
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
