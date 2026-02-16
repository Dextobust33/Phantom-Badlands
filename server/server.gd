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
const NpcPostDatabaseScript = preload("res://shared/npc_post_database.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

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
var at_player_station = {}  # peer_id -> {stations: [station_types], has_inn: bool, has_storage: bool}
var player_in_hotzone = {}  # peer_id -> true when player has confirmed hotzone entry

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

# Party system - tracks active player parties
var active_parties = {}          # leader_peer_id -> PartyData dict {leader, members[], formed_at}
var party_membership = {}        # peer_id -> leader_peer_id (quick lookup)
var pending_party_invites = {}   # target_peer_id -> {from_peer_id, timestamp}
var party_invite_cooldowns = {}  # peer_id -> last_invite_time_msec
const PARTY_INVITE_COOLDOWN_MS = 10000  # 10 sec anti-spam
const PARTY_MAX_SIZE = 4

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
var dungeon_floors: Dictionary = {}   # instance_id -> [grid_floor_0, grid_floor_1, ...]
var dungeon_floor_rooms: Dictionary = {}  # instance_id -> [[rooms_floor_0], [rooms_floor_1], ...]
var dungeon_monsters: Dictionary = {}     # instance_id -> {floor_num: [monster_entity, ...]}
var next_dungeon_monster_id: int = 0
var dungeon_combat_breather: Dictionary = {}  # peer_id -> true: skip monster movement on next move after combat
var player_dungeon_instances: Dictionary = {}  # peer_id -> {quest_id: instance_id} - personal dungeons for quests

# Bounty system tracking
var active_bounties: Dictionary = {}  # quest_id -> {x, y, monster_type, level, name, peer_id}
# Gathering session tracking (3-choice until-fail)
var active_gathering: Dictionary = {}  # peer_id -> {job_type, node_type, tier, chain_count, chain_materials, correct_id, options, risky_available}
var gathering_cooldown: Dictionary = {}  # peer_id -> true — prevents encounter on first move after gathering
# Soldier harvest session tracking (post-combat 3-choice)
var active_harvests: Dictionary = {}  # peer_id -> {monster_name, monster_tier, round, max_rounds, parts_gained}
var active_crafts: Dictionary = {}  # peer_id -> {recipe_id, skill_name, post_bonus, job_bonus, questions, correct_answers}
# Rescue system tracking
var dungeon_npcs: Dictionary = {}  # instance_id -> {floor_num: npc_data}
var pending_rescue_encounters: Dictionary = {}  # peer_id -> npc_data
var next_dungeon_id: int = 1
const MAX_ACTIVE_DUNGEONS = 300  # Support many world + player dungeons
const DUNGEON_SPAWN_CHECK_INTERVAL = 30.0  # Check every 30 seconds
const DUNGEON_DESPAWN_DELAY = 60.0  # Despawn completed dungeons after 60 seconds
const MIN_WORLD_DUNGEONS = 150  # Minimum world dungeons - expect 1 per ~50 tiles of travel
const MAX_WORLD_DUNGEONS = 200  # Maximum number of world dungeons
var dungeon_spawn_timer: float = 0.0


# Combat command rate limiting (peer_id -> last command time in msec)
var combat_command_cooldown: Dictionary = {}

var monster_db: MonsterDatabase
var combat_mgr: CombatManager
var world_system: WorldSystem
var chunk_manager: Node  # ChunkManager
var persistence: Node
var drop_tables: Node
var quest_db: Node
var quest_mgr: Node
var trading_post_db: Node
var balance_config: Dictionary = {}

# Pending home stone companion choice (peer_id -> item data for returning on cancel)
var pending_home_stone_companion: Dictionary = {}  # peer_id -> {"item_type": str, "item_name": str}

# Pending scroll use (peer_id -> {item: consumed item data, time: msec}) for cancel restoration
var pending_scroll_use: Dictionary = {}

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

# ===== GUARD SYSTEM =====
# Active guards: "x,y" -> {owner, hired_at, last_fed, food_remaining, in_tower, radius}
var active_guards: Dictionary = {}
const GUARD_HIRE_VALOR_COST = 50
const GUARD_HIRE_FOOD_COST = 5
const GUARD_FEED_FOOD_COST = 3
const GUARD_FEED_DAYS_ADDED = 3
const GUARD_MAX_FOOD_DAYS = 14
const GUARD_BASE_RADIUS = 5
const GUARD_TOWER_RADIUS = 15
const GUARD_FOOD_MATERIALS = ["minnow", "trout", "pike", "swordfish", "leviathan", "abyssal_eel",
	"clover", "sage", "moonpetal", "bloodroot", "starbloom", "voidpetal"]
const GUARD_DECAY_CHECK_INTERVAL = 60.0  # Check guard decay every 60 seconds
var guard_decay_timer: float = 0.0
const WALL_DECAY_CHECK_INTERVAL = 300.0  # Check wall decay every 5 minutes
var wall_decay_timer: float = 0.0
const WALL_DECAY_GRACE_PERIOD = 259200  # 72 hours in seconds

# ===== GATHERING NODE SYSTEM =====
# Simplified node tracking for performance - nodes are deterministic so we only track depleted ones
# Key format: "x,y" -> respawn_timestamp (Unix time when node respawns)
var depleted_nodes: Dictionary = {}
const NODE_RESPAWN_TIME = 300.0  # 5 minutes to respawn
const NODE_RESPAWN_CHECK_INTERVAL = 10.0  # Only check respawns every 10 seconds
var node_respawn_timer: float = 0.0

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
	print("Phantom Badlands Server Starting...")
	print("========================================")

	# Initialize persistence system
	persistence = PersistenceManagerScript.new()
	add_child(persistence)

	# Initialize chunk-based world system
	chunk_manager = ChunkManagerScript.new()
	add_child(chunk_manager)
	chunk_manager.load_world_seed()

	world_system = WorldSystem.new()
	add_child(world_system)

	# Connect chunk manager to world system (bidirectional)
	world_system.chunk_manager = chunk_manager
	chunk_manager.terrain_generator = world_system

	# Load or generate NPC posts
	var npc_posts = chunk_manager.load_npc_posts()
	if npc_posts.is_empty():
		log_message("Generating NPC posts from world seed...")
		npc_posts = NpcPostDatabaseScript.generate_posts(chunk_manager.world_seed)
		chunk_manager.save_npc_posts(npc_posts)
		log_message("Generated %d NPC posts" % npc_posts.size())
	else:
		log_message("Loaded %d NPC posts" % npc_posts.size())
	# Always re-stamp post layouts into chunks (ensures walls/floors exist after wipes)
	for post in npc_posts:
		NpcPostDatabaseScript.stamp_post_into_chunks(post, chunk_manager)
	# Rebuild player enclosures from persisted tile data
	_rebuild_all_player_enclosures()
	chunk_manager.save_dirty_chunks()

	# Load persistent depleted nodes
	chunk_manager.load_depleted_nodes()

	# Load guard data and initialize cache
	active_guards = persistence.load_guards()
	_update_guard_cache()
	log_message("Loaded %d active guards" % active_guards.size())

	# Initialize geological event timer
	chunk_manager.initialize_geo_timer()

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

func _broadcast_geological_event(event: Dictionary):
	"""Broadcast a geological event to nearby players."""
	var msg = event.get("message", "")
	var event_x = event.get("x", 0)
	var event_y = event.get("y", 0)
	var radius = event.get("radius", 64)
	var announce_radius = radius * 3  # Announce to players within 3x the event radius

	log_message("[GEO EVENT] %s" % msg)

	for peer_id in characters:
		var character = characters[peer_id]
		var dx = character.x - event_x
		var dy = character.y - event_y
		var dist = sqrt(dx * dx + dy * dy)
		if dist <= announce_radius:
			send_to_peer(peer_id, {"type": "text", "message": msg})
			# Refresh their map to show the regenerated nodes
			send_location_update(peer_id)

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

	# Process gathering node respawns and chunk manager ticks
	if chunk_manager:
		chunk_manager.process_node_respawns(delta)

		# Geological events (resource respawning in depleted areas)
		var geo_events = chunk_manager.process_geological_events(delta)
		for event in geo_events:
			_broadcast_geological_event(event)

		# Periodic chunk save (piggyback on auto-save)
		if auto_save_timer < 0.1:  # Just after auto-save reset
			chunk_manager.save_dirty_chunks()
	else:
		process_node_respawns(delta)

	# Guard decay timer
	guard_decay_timer += delta
	if guard_decay_timer >= GUARD_DECAY_CHECK_INTERVAL:
		guard_decay_timer = 0.0
		_tick_guard_decay()

	# Wall decay timer
	wall_decay_timer += delta
	if wall_decay_timer >= WALL_DECAY_CHECK_INTERVAL:
		wall_decay_timer = 0.0
		_tick_wall_decay()

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
			"message": "Welcome to Phantom Badlands!",
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
		"inventory_lock":
			handle_inventory_lock(peer_id, message)
		"inventory_salvage":
			handle_inventory_salvage(peer_id, message)
		"auto_salvage_settings":
			handle_auto_salvage_settings(peer_id, message)
		"auto_salvage_affix_settings":
			handle_auto_salvage_affix_settings(peer_id, message)
		"monster_select_confirm":
			handle_monster_select_confirm(peer_id, message)
		"home_stone_select":
			handle_home_stone_select(peer_id, message)
		"home_stone_cancel":
			handle_home_stone_cancel(peer_id, message)
		"target_farm_select":
			handle_target_farm_select(peer_id, message)
		"target_farm_cancel":
			handle_scroll_cancel(peer_id)
		"monster_select_cancel":
			handle_scroll_cancel(peer_id)
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
		"trading_post_wits_training":
			handle_trading_post_wits_training(peer_id)
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
		"release_companion":
			handle_release_companion(peer_id, message)
		"release_all_companions":
			handle_release_all_companions(peer_id)
		"toggle_egg_freeze":
			handle_toggle_egg_freeze(peer_id, message)
		"debug_hatch":
			handle_debug_hatch(peer_id)
		# Unified gathering system handlers
		"gathering_start":
			handle_gathering_start(peer_id, message)
		"gathering_choice":
			handle_gathering_choice(peer_id, message)
		"gathering_end":
			handle_gathering_end(peer_id, message)
		# Soldier harvest handlers
		"harvest_start":
			handle_harvest_start(peer_id)
		"harvest_choice":
			handle_harvest_choice(peer_id, message)
		# Tool equip/unequip
		"equip_tool":
			handle_equip_tool(peer_id, message)
		"unequip_tool":
			handle_unequip_tool(peer_id, message)
		# Job system handlers
		"job_info":
			handle_job_info(peer_id)
		"job_commit":
			handle_job_commit(peer_id, message)
		# Crafting system handlers
		"craft_list":
			handle_craft_list(peer_id, message)
		"craft_item":
			handle_craft_item(peer_id, message)
		"craft_challenge_answer":
			handle_craft_challenge_answer(peer_id, message)
		"use_rune":
			handle_use_rune(peer_id, message)
		# Building system handlers
		"build_place":
			handle_build_place(peer_id, message)
		"build_demolish":
			handle_build_demolish(peer_id, message)
		"name_post":
			handle_name_post(peer_id, message)
		"inn_rest":
			handle_inn_rest(peer_id)
		"storage_access":
			handle_storage_access(peer_id)
		"storage_deposit":
			handle_storage_deposit(peer_id, message)
		"storage_withdraw":
			handle_storage_withdraw(peer_id, message)
		# Guard system handlers
		"guard_hire":
			handle_guard_hire(peer_id, message)
		"guard_feed":
			handle_guard_feed(peer_id, message)
		"guard_dismiss":
			handle_guard_dismiss(peer_id, message)
		# Dungeon system handlers
		"dungeon_list":
			handle_dungeon_list(peer_id)
		"hotzone_confirm":
			handle_hotzone_confirm(peer_id, message)
		"dungeon_enter":
			handle_dungeon_enter(peer_id, message)
		"dungeon_move":
			handle_dungeon_move(peer_id, message)
		"dungeon_exit":
			handle_dungeon_exit(peer_id)
		"dungeon_go_back":
			handle_dungeon_go_back(peer_id)
		"dungeon_rest":
			handle_dungeon_rest(peer_id)
		"dungeon_state":
			# Client requesting current dungeon state (after combat continue)
			if characters.has(peer_id) and characters[peer_id].current_dungeon_id != "":
				_send_dungeon_state(peer_id)
		# Corpse looting
		"loot_corpse":
			handle_loot_corpse(peer_id, message)
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
		"trade_add_companion":
			handle_trade_add_companion(peer_id, message)
		"trade_remove_companion":
			handle_trade_remove_companion(peer_id, message)
		"trade_add_egg":
			handle_trade_add_egg(peer_id, message)
		"trade_remove_egg":
			handle_trade_remove_egg(peer_id, message)
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
		"rescue_npc_response":
			handle_rescue_npc_response(peer_id, message)
		"engage_bounty":
			# Player clicks Engage button at bounty location
			if characters.has(peer_id):
				var character = characters[peer_id]
				_check_bounty_at_location(peer_id, character.x, character.y)
		# Bug report handler
		"bug_report":
			handle_bug_report(peer_id, message)
		# House (Sanctuary) system handlers
		"house_request":
			handle_house_request(peer_id)
		"house_upgrade":
			handle_house_upgrade(peer_id, message)
		"house_discard_item":
			handle_house_discard_item(peer_id, message)
		"house_unregister_companion":
			handle_house_unregister_companion(peer_id, message)
		"house_register_from_storage":
			handle_house_register_companion_from_storage(peer_id, message)
		"home_stone_companion_response":
			handle_home_stone_companion_response(peer_id, message)
		"house_kennel_release":
			handle_house_kennel_release(peer_id, message)
		"house_kennel_register":
			handle_house_kennel_register(peer_id, message)
		"house_fusion":
			handle_house_fusion(peer_id, message)
		"request_character_list":
			handle_list_characters(peer_id)
		# Party system handlers
		"party_invite":
			handle_party_invite(peer_id, message)
		"party_invite_response":
			handle_party_invite_response(peer_id, message)
		"party_lead_choice_response":
			handle_party_lead_choice_response(peer_id, message)
		"party_disband":
			handle_party_disband(peer_id)
		"party_leave":
			handle_party_leave(peer_id)
		"party_appoint_leader":
			handle_party_appoint_leader(peer_id, message)
		# GM/Admin command handlers
		"gm_setlevel":
			handle_gm_setlevel(peer_id, message)
		"gm_setvalor":
			handle_gm_setvalor(peer_id, message)
		"gm_setmonstergems":
			handle_gm_setmonstergems(peer_id, message)
		"gm_setxp":
			handle_gm_setxp(peer_id, message)
		"gm_godmode":
			handle_gm_godmode(peer_id)
		"gm_setbp":
			handle_gm_setbp(peer_id, message)
		"gm_giveitem":
			handle_gm_giveitem(peer_id, message)
		"gm_giveegg":
			handle_gm_giveegg(peer_id, message)
		"gm_givecompanion":
			handle_gm_givecompanion(peer_id, message)
		"gm_spawnmonster":
			handle_gm_spawnmonster(peer_id, message)
		"gm_givemats":
			handle_gm_givemats(peer_id, message)
		"gm_giveall":
			handle_gm_giveall(peer_id)
		"gm_teleport":
			handle_gm_teleport(peer_id, message)
		"gm_completequest":
			handle_gm_completequest(peer_id, message)
		"gm_resetquests":
			handle_gm_resetquests(peer_id)
		"gm_heal":
			handle_gm_heal(peer_id)
		"gm_broadcast":
			handle_gm_broadcast(peer_id, message)
		"gm_giveconsumable":
			handle_gm_giveconsumable(peer_id, message)
		"gm_spawnwish":
			handle_gm_spawnwish(peer_id)
		"gm_fullwipe":
			handle_gm_fullwipe(peer_id, message)
		"gm_mapwipe":
			handle_gm_mapwipe(peer_id, message)
		"gm_setjob":
			handle_gm_setjob(peer_id, message)
		"gm_givetool":
			handle_gm_givetool(peer_id, message)
		# Open Market handlers
		"market_browse":
			handle_market_browse(peer_id, message)
		"market_list_item":
			handle_market_list_item(peer_id, message)
		"market_list_material":
			handle_market_list_material(peer_id, message)
		"market_buy":
			handle_market_buy(peer_id, message)
		"market_my_listings":
			handle_market_my_listings(peer_id, message)
		"market_cancel":
			handle_market_cancel(peer_id, message)
		"market_cancel_all":
			handle_market_cancel_all(peer_id, message)
		"market_list_all":
			handle_market_list_all(peer_id, message)
		"market_list_egg":
			handle_market_list_egg(peer_id, message)
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
		peers[peer_id].is_admin = persistence.is_admin_account(result.account_id)

		log_message("Account authenticated: %s (Peer %d)%s" % [username, peer_id, " [ADMIN]" if peers[peer_id].is_admin else ""])

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

	# Refresh house bonuses from current Sanctuary upgrades (in case they upgraded since last login)
	var house_bonuses = _get_house_bonuses_for_character(account_id)
	if character.house_bonuses != house_bonuses:
		character.house_bonuses = house_bonuses
		persistence.save_character(account_id, character)

	# === HP/MANA REPAIR (v0.9.98) ===
	# Fix characters whose current_hp/mana got crushed to base max by end_combat() bug
	# The bug capped current_hp to character.max_hp (base) instead of get_total_max_hp()
	character.calculate_derived_stats()
	var total_hp = character.get_total_max_hp()
	var total_mana = character.get_total_max_mana()
	if character.current_hp > 0 and character.current_hp <= character.max_hp and total_hp > character.max_hp * 1.5:
		# Current HP is suspiciously at or below base max while total is much higher — likely hit by the bug
		character.current_hp = total_hp
		character.current_mana = total_mana
		log_message("HP/Mana repair: %s healed to full (%d HP, %d mana)" % [char_name, total_hp, total_mana])
		persistence.save_character(account_id, character)

	# === GOLD → VALOR MIGRATION ===
	# One-time conversion of legacy character gold to account Valor (50 gold = 1 Valor)
	if character.gold > 0:
		var converted_valor = maxi(1, character.gold / 50)
		persistence.add_valor(account_id, converted_valor)
		log_message("Gold migration: %s converted %d gold → %d Valor" % [char_name, character.gold, converted_valor])
		character.gold = 0
		persistence.save_character(account_id, character)
		# Queue migration message to send after character is fully loaded
		call_deferred("_send_gold_migration_message", peer_id, converted_valor)

	# Checkout companion from house kennel if requested (and character doesn't already have one)
	var checkout_slot = message.get("checkout_companion_slot", -1)
	if checkout_slot >= 0 and not character.using_registered_companion and character.active_companion.is_empty():
		_checkout_companion_for_character(account_id, character, checkout_slot, char_name)
		persistence.save_character(account_id, character)

	# Withdraw items from house storage if requested
	var withdraw_indices = message.get("withdraw_indices", [])
	if withdraw_indices.size() > 0:
		_withdraw_house_storage_items(account_id, character, withdraw_indices, peer_id)
		persistence.save_character(account_id, character)

	# Consolidate fragmented consumable stacks (one-time cleanup on login)
	var pre_size = character.inventory.size()
	character.consolidate_consumable_stacks()
	if character.inventory.size() < pre_size:
		log_message("Stack consolidation: %s inventory %d → %d slots" % [char_name, pre_size, character.inventory.size()])
		persistence.save_character(account_id, character)

	# Store character in active characters
	characters[peer_id] = character
	peers[peer_id].character_name = char_name

	# Update title holder tracking
	_update_title_holders_on_login(peer_id)

	var username = peers[peer_id].username
	log_message("Character loaded: %s (Account: %s) for peer %d" % [char_name, username, peer_id])
	update_player_list()

	# Check for saved dungeon state (disconnect recovery) BEFORE sending character_loaded
	var dungeon_restored = false
	if character.in_dungeon:
		var instance_id = character.current_dungeon_id
		# Try to find the dungeon instance — check by instance_id first
		if active_dungeons.has(instance_id) and dungeon_floors.has(instance_id):
			# Instance still exists! Rebuild the mapping
			var instance = active_dungeons[instance_id]
			if not instance.active_players.has(peer_id):
				instance.active_players.append(peer_id)
			# Update owner_peer_id to new peer_id
			if instance.has("owner_peer_id"):
				instance["owner_peer_id"] = peer_id
			# Rebuild player_dungeon_instances mapping
			if not player_dungeon_instances.has(peer_id):
				player_dungeon_instances[peer_id] = {}
			var quest_id = instance.get("quest_id", "")
			if quest_id == "":
				quest_id = "_free_run_" + instance_id
			player_dungeon_instances[peer_id][quest_id] = instance_id
			dungeon_restored = true
			log_message("DUNGEON RECONNECT: Restored %s to dungeon %s (floor %d)" % [char_name, instance_id, character.dungeon_floor])
		else:
			# Dungeon instance expired (server restarted or timed out)
			character.exit_dungeon()
			save_character(peer_id)
			log_message("DUNGEON RECONNECT: Dungeon %s expired for %s, returning to overworld" % [instance_id, char_name])

	var char_dict_loaded = character.to_dict()
	# Add account-level valor and projected rank (same as send_character_update)
	char_dict_loaded["valor"] = persistence.get_valor(account_id)
	char_dict_loaded["projected_rank"] = _calculate_projected_rank(character)
	var char_loaded_msg = {
		"type": "character_loaded",
		"character": char_dict_loaded,
		"message": "Welcome back, %s!" % char_name,
		"title_holders": _get_current_title_holders(),
		"dungeon_restore": dungeon_restored
	}
	send_to_peer(peer_id, char_loaded_msg)

	# Broadcast join message to other players (include title if present)
	var display_name = char_name
	if not character.title.is_empty():
		display_name = TitlesScript.format_titled_name(char_name, character.title)
	broadcast_chat("[color=#00FF00]%s has entered the realm.[/color]" % display_name)

	if dungeon_restored:
		# Send dungeon state to client (replaces location update)
		_send_dungeon_state(peer_id)
		send_to_peer(peer_id, {"type": "text", "message": "[color=#00FFFF]You have been returned to your dungeon.[/color]"})
	else:
		send_location_update(peer_id)

		# Check if spawning at a Trading Post and trigger the encounter
		if world_system.is_trading_post_tile(character.x, character.y):
			trigger_trading_post_encounter(peer_id)

	# Check for saved combat state (disconnect recovery)
	if not character.saved_combat_state.is_empty():
		var saved_state = character.saved_combat_state
		var result = combat_mgr.restore_combat(peer_id, character, saved_state)
		if result.get("success", false):
			print("COMBAT PERSISTENCE: Restored combat for %s" % character.name)
			# Restore flock count if it was saved
			var flock_remaining = saved_state.get("flock_remaining", 0)
			if flock_remaining > 0:
				flock_counts[peer_id] = flock_remaining
			# Clear saved state now that it's restored
			character.saved_combat_state = {}
			save_character(peer_id)
			# Send combat start to client
			var monster = saved_state.get("monster", {})
			send_to_peer(peer_id, {
				"type": "combat_start",
				"message": result.message,
				"combat_state": result.combat_state,
				"monster_name": monster.get("name", "Unknown"),
				"monster_level": monster.get("level", 1),
				"use_client_art": true,
				"combat_restored": true,
				"extra_combat_text": result.get("extra_combat_text", "")
			})
		else:
			# Failed to restore - clear invalid state
			character.saved_combat_state = {}
			save_character(peer_id)

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

	# Give starter gathering tools — equip directly to tool slots
	var starter_tools = DropTables.generate_starter_tools()
	for tool in starter_tools:
		var st = tool.get("subtype", "")
		if character.equipped_tools.has(st) and character.equipped_tools[st].is_empty():
			character.equipped_tools[st] = tool
		else:
			character.add_item(tool)

	# Apply house bonuses from Sanctuary upgrades
	var house_bonuses = _get_house_bonuses_for_character(account_id)
	character.house_bonuses = house_bonuses
	# Apply starting valor bonus
	if house_bonuses.get("starting_valor", 0) > 0:
		persistence.add_valor(account_id, house_bonuses.starting_valor)

	# Checkout companion from house kennel if requested
	var checkout_slot = message.get("checkout_companion_slot", -1)
	if checkout_slot >= 0:
		_checkout_companion_for_character(account_id, character, checkout_slot, char_name)

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
	var result = persistence.get_trophy_leaderboard()

	send_to_peer(peer_id, {
		"type": "trophy_leaderboard",
		"entries": result.get("first_discoveries", []),
		"top_collectors": result.get("top_collectors", [])
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

	# Get requester info for location viewing privilege
	var requester_has_title = false
	var requester_x = 0
	var requester_y = 0
	if characters.has(peer_id):
		var requester = characters[peer_id]
		requester_has_title = not requester.title.is_empty()
		requester_x = requester.x
		requester_y = requester.y

	# Find the target player
	for pid in characters.keys():
		var char = characters[pid]
		if char.name.to_lower() == target_name.to_lower():
			var bonuses = char.get_equipment_bonuses()
			var is_cloaked = char.has_buff("cloak") or char.has_buff("invisibility")

			# Calculate distance for proximity-based location viewing
			var distance = abs(char.x - requester_x) + abs(char.y - requester_y)
			var is_nearby = distance <= 100

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
				"current_mana": char.current_mana,
				"total_max_mana": char.get_total_max_mana(),
				"current_stamina": char.current_stamina,
				"total_max_stamina": char.get_total_max_stamina(),
				"current_energy": char.current_energy,
				"total_max_energy": char.get_total_max_energy(),
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
				"valor": persistence.get_valor(peers[pid].account_id) if peers.has(pid) else 0,
				"title": char.title,
				"deaths": char.deaths,
				"quests_completed": char.completed_quests.size() if char.completed_quests else 0,
				"play_time": char.played_time_seconds
			}

			# Location visibility: title holders see all (unless cloaked), nearby players see each other
			if requester_has_title:
				result["viewer_has_title"] = true
				if not is_cloaked:
					result["location_x"] = char.x
					result["location_y"] = char.y
				else:
					result["location_hidden"] = true
			elif is_nearby and not is_cloaked:
				# Players within 100 tiles can see each other's location
				result["location_x"] = char.x
				result["location_y"] = char.y
			else:
				# Location unknown - too far away or cloaked
				result["location_unknown"] = true

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
	# Reset connect_time so stale connection check gives a fresh auth window
	peers[peer_id].connect_time = Time.get_unix_time_from_system()

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

	# Party followers can't move independently
	if party_membership.has(peer_id) and not _is_party_leader(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Your party leader controls movement.[/color]"})
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

	# Cannot use world movement while in a dungeon
	var character_check = characters[peer_id]
	if character_check.in_dungeon:
		return

	# Cannot move while gathering or harvesting
	if active_gathering.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot move while gathering!"})
		return
	if active_harvests.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot move while harvesting!"})
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

	# If blocked and not resting (direction 5), check what we bumped into
	if new_pos.x == old_x and new_pos.y == old_y and direction != 5:
		var target_pos = world_system.get_direction_offset(old_x, old_y, direction)
		if target_pos.x != old_x or target_pos.y != old_y:
			# Check gathering nodes first
			var bump_node = get_gathering_node_at(target_pos.x, target_pos.y)
			if not bump_node.is_empty():
				bump_node["node_x"] = target_pos.x
				bump_node["node_y"] = target_pos.y
				_start_bump_gathering(peer_id, character, bump_node)
				return

			# Check NPC post tiles (stations, quest board, market, inn, throne)
			if chunk_manager:
				var bump_tile = chunk_manager.get_tile(target_pos.x, target_pos.y)
				var bump_type = bump_tile.get("type", "")
				if bump_type in CraftingDatabaseScript.STATION_SKILL_MAP:
					var skill = CraftingDatabaseScript.STATION_SKILL_MAP[bump_type]
					send_to_peer(peer_id, {"type": "station_interact", "station": bump_type, "skill": skill})
					return
				elif bump_type == "quest_board":
					send_to_peer(peer_id, {"type": "quest_board_interact"})
					return
				elif bump_type == "market":
					_handle_market_interact(peer_id, character)
					return
				elif bump_type == "inn":
					_handle_inn_interact(peer_id, character)
					return
				elif bump_type == "blacksmith":
					_handle_blacksmith_station(peer_id, character)
					return
				elif bump_type == "healer":
					_handle_healer_station(peer_id, character)
					return
				elif bump_type == "guard":
					_handle_guard_post_interact(peer_id, character, target_pos.x, target_pos.y)
					return
				elif bump_type == "throne":
					send_to_peer(peer_id, {"type": "throne_interact"})
					return

	# Check for player collision (can't move onto another player's space)
	# Party members don't block each other (handled by snake movement)
	if _is_non_party_player_at(new_pos.x, new_pos.y, peer_id):
		# Check if bumped player is a valid party invite target
		var bumped_peer_id = _get_player_at(new_pos.x, new_pos.y, peer_id)
		if bumped_peer_id != -1:
			var bumped_char = characters[bumped_peer_id]
			var can_invite = false
			# Can invite if: we're not in a party, or we're the party leader with room
			if not party_membership.has(peer_id):
				can_invite = true
			elif _is_party_leader(peer_id) and _get_party_size(peer_id) < PARTY_MAX_SIZE:
				can_invite = true
			# Target must not be in a party, combat, or dungeon
			if can_invite and not party_membership.has(bumped_peer_id) \
					and not combat_mgr.is_in_combat(bumped_peer_id) \
					and not bumped_char.in_dungeon:
				send_to_peer(peer_id, {
					"type": "party_bump",
					"target_name": bumped_char.name,
					"target_level": bumped_char.level,
					"target_class": bumped_char.class_type
				})
				return
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Another player is blocking that path!"
		})
		return

	character.x = new_pos.x
	character.y = new_pos.y

	# Regenerate health and resources on movement (small amount per step)
	# Resource regen is DISABLED while cloaked - cloak drains resources
	# Early game bonus: 2x regen at level 1, scaling down to 1x by level 25
	# House bonus: +5% regen per level of resource_regen upgrade
	var early_game_mult = _get_early_game_regen_multiplier(character.level)
	var house_regen_mult = 1.0 + (character.house_bonuses.get("resource_regen", 0) / 100.0)
	var regen_percent = 0.02 * early_game_mult * house_regen_mult  # 2% per move for resources
	var hp_regen_percent = 0.01 * early_game_mult * house_regen_mult  # 1% per move for health
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
				"message": "[color=#00FF00]%s is now your companion![/color] Visit [color=#00FFFF]More → Companions[/color] to manage." % companion.name
			})

	# Party snake movement: move followers in chain behind leader
	if _is_party_leader(peer_id):
		_move_party_followers(peer_id, old_x, old_y)

	# Send location and character updates
	send_location_update(peer_id)
	send_character_update(peer_id)

	# If in party, send updates to all party members too
	if _is_party_leader(peer_id):
		var party = active_parties[peer_id]
		for pid in party.members:
			if pid != peer_id:
				send_location_update(pid)
				send_character_update(pid)

	# Notify nearby players of the movement (so they see us on their map)
	send_nearby_players_map_update(peer_id, old_x, old_y)

	# Periodic check for nearby player posts (compass hint)
	if characters.has(peer_id):
		var mc = characters[peer_id].get_meta("move_count", 0) + 1
		characters[peer_id].set_meta("move_count", mc)
		if mc % 20 == 0:
			_check_nearby_player_posts(peer_id, new_pos.x, new_pos.y)

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

	# Check for entering/leaving any player enclosure (own or others)
	var move_username = _get_username(peer_id)
	var now_in_enclosure = false
	var enclosure_owner = ""
	var lookup_key = Vector2i(new_pos.x, new_pos.y)
	if enclosure_tile_lookup.has(lookup_key):
		now_in_enclosure = true
		enclosure_owner = enclosure_tile_lookup[lookup_key].owner
	if now_in_enclosure:
		var is_own = (enclosure_owner == move_username)
		if not at_player_station.has(peer_id) or at_player_station[peer_id].get("owner", "") != enclosure_owner:
			# Entering enclosure — find stations
			var enc_idx = enclosure_tile_lookup[lookup_key].enclosure_idx
			var enclosure = player_enclosures.get(enclosure_owner, [])
			var stations: Array = []
			var has_inn = false
			var has_storage = false
			if enc_idx < enclosure.size():
				for epos in enclosure[enc_idx]:
					var tile = chunk_manager.get_tile(int(epos.x), int(epos.y))
					var tile_type = tile.get("type", "")
					if tile_type in CraftingDatabaseScript.STATION_SKILL_MAP and tile_type not in stations:
						stations.append(tile_type)
					if tile_type == "inn":
						has_inn = true
					if tile_type == "storage":
						has_storage = true
			at_player_station[peer_id] = {"stations": stations, "has_inn": has_inn, "has_storage": has_storage and is_own, "owner": enclosure_owner, "is_own": is_own}
	if not now_in_enclosure and at_player_station.has(peer_id):
		at_player_station.erase(peer_id)

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

	# Check if entering a hotzone for the first time (warn before proceeding)
	var hotspot_check = world_system.get_hotspot_at(new_pos.x, new_pos.y)
	if hotspot_check.in_hotspot and not player_in_hotzone.has(peer_id):
		# Use the actual monster level calculation for accurate estimate
		var level_range = world_system.get_monster_level_range(new_pos.x, new_pos.y)
		var estimated_level = level_range.base_level
		send_to_peer(peer_id, {
			"type": "hotzone_warning",
			"intensity": hotspot_check.intensity,
			"estimated_level": estimated_level,
			"x": new_pos.x, "y": new_pos.y
		})
		# Move player back to previous position
		character.x = old_x
		character.y = old_y
		send_location_update(peer_id)
		return
	# Clear hotzone tracking if player has left the hotzone
	if not hotspot_check.in_hotspot and player_in_hotzone.has(peer_id):
		player_in_hotzone.erase(peer_id)

	# Check for bounty target at this location
	if _check_bounty_at_location(peer_id, new_pos.x, new_pos.y):
		return  # Bounty combat started

	# Skip encounter check if just finished gathering (one-move cooldown)
	if gathering_cooldown.has(peer_id):
		gathering_cooldown.erase(peer_id)
		return

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

	# Skip if just finished gathering (prevents post-gathering encounter)
	if gathering_cooldown.has(peer_id):
		gathering_cooldown.erase(peer_id)
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

	# Party members can't hunt independently — only leader triggers encounters
	if party_membership.has(peer_id) and not _is_party_leader(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Your party leader controls encounters.[/color]"})
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

	# Tick blind on hunt
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
	if world_system.is_safe_zone(character.x, character.y):
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

func handle_rest(peer_id: int, _is_party_follower: bool = false):
	"""Handle rest action to restore HP (or Meditate for mages)"""
	if not characters.has(peer_id):
		return

	# Party check: non-leader members can't rest independently
	if not _is_party_follower and party_membership.has(peer_id) and not _is_party_leader(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Your party leader controls resting.[/color]"})
		return

	# If party leader, rest all followers too
	if not _is_party_follower and _is_party_leader(peer_id):
		var party = active_parties.get(peer_id, {})
		for follower_pid in party.get("members", []):
			if follower_pid != peer_id and characters.has(follower_pid):
				handle_rest(follower_pid, true)

	# Skip ambush if just finished gathering (prevents post-gathering encounter)
	var _gathering_immune = false
	if gathering_cooldown.has(peer_id):
		gathering_cooldown.erase(peer_id)
		_gathering_immune = true

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
		_handle_meditate(peer_id, character, cloak_was_dropped, _gathering_immune, _is_party_follower)
		return

	# Regenerate primary resource on rest (same as movement - 2%, min 1)
	# Early game bonus: 2x regen at level 1, scaling down to 1x by level 25
	# House bonus: +5% regen per level of resource_regen upgrade
	var early_game_mult = _get_early_game_regen_multiplier(character.level)
	var house_regen_mult = 1.0 + (character.house_bonuses.get("resource_regen", 0) / 100.0)
	var regen_percent = 0.02 * early_game_mult * house_regen_mult
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

	# Tick poison on rest
	if character.poison_active:
		var poison_dmg = character.tick_poison()
		if poison_dmg != 0:
			var turns_left = character.poison_turns_remaining
			var poison_msg = ""
			if poison_dmg < 0:
				var heal_amount2 = -poison_dmg
				character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount2)
				poison_msg = "[color=#708090]Your undead form absorbs the poison, healing [color=#00FF00]%d HP[/color][/color]" % heal_amount2
			else:
				character.current_hp -= poison_dmg
				character.current_hp = max(1, character.current_hp)
				poison_msg = "[color=#00FF00]Poison[/color] deals [color=#FF4444]%d damage[/color]" % poison_dmg
			if turns_left > 0:
				poison_msg += " (%d rounds remaining)" % turns_left
			else:
				poison_msg += " - [color=#00FF00]Poison has worn off![/color]"
			send_to_peer(peer_id, {"type": "status_effect", "effect": "poison", "message": poison_msg, "damage": poison_dmg, "turns_remaining": turns_left})

	# Tick blind on rest
	if character.blind_active:
		var still_blind = character.tick_blind()
		var turns_left = character.blind_turns_remaining
		if still_blind:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "blind", "message": "[color=#808080]You are blinded! (%d rounds remaining)[/color]" % turns_left, "turns_remaining": turns_left})
		else:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "blind_cured", "message": "[color=#00FF00]Your vision clears![/color]"})

	# Tick active buffs on rest
	if not character.active_buffs.is_empty():
		var expired = character.tick_buffs()
		for buff in expired:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "buff_expired", "message": "[color=#808080]%s buff has worn off.[/color]" % buff.type})

	# Re-send character update after ticking effects
	send_to_peer(peer_id, {"type": "character_update", "character": character.to_dict()})

	# Chance to be ambushed while resting (15%) — not in safe zones
	# Only the leader (or solo player) can trigger ambush, not party followers
	if not _is_party_follower and not _gathering_immune and not world_system.is_safe_zone(character.x, character.y):
		var ambush_roll = randi() % 100
		if ambush_roll < 15:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF4444]You are ambushed while resting![/color]"
			})
			trigger_encounter(peer_id)

func _get_early_game_regen_multiplier(level: int) -> float:
	"""Returns a multiplier for resource regen that's higher at low levels.
	Level 1: 2.0x, Level 25+: 1.0x, linear interpolation between."""
	if level >= 25:
		return 1.0
	# Linear interpolation: 2.0 at level 1, 1.0 at level 25
	var t = float(level - 1) / 24.0  # 0.0 at level 1, 1.0 at level 25
	return 2.0 - t  # 2.0 at level 1, 1.0 at level 25

func _handle_meditate(peer_id: int, character: Character, cloak_was_dropped: bool = false, gathering_immune: bool = false, is_party_follower: bool = false):
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

	# Early game bonus: 2x regen at level 1, scaling down to 1x by level 25
	# House bonus: +5% regen per level of resource_regen upgrade
	var early_game_mult = _get_early_game_regen_multiplier(character.level)
	var house_regen_mult = 1.0 + (character.house_bonuses.get("resource_regen", 0) / 100.0)

	# Mana regeneration: 4% of max mana (2x movement), double if at full HP
	var base_mana_percent = 0.04 * early_game_mult * house_regen_mult  # 2x the 2% movement regen, with early game + house bonus
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

	# Tick poison on meditate
	if character.poison_active:
		var poison_dmg = character.tick_poison()
		if poison_dmg != 0:
			var turns_left = character.poison_turns_remaining
			var poison_msg = ""
			if poison_dmg < 0:
				var heal_amount2 = -poison_dmg
				character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount2)
				poison_msg = "[color=#708090]Your undead form absorbs the poison, healing [color=#00FF00]%d HP[/color][/color]" % heal_amount2
			else:
				character.current_hp -= poison_dmg
				character.current_hp = max(1, character.current_hp)
				poison_msg = "[color=#00FF00]Poison[/color] deals [color=#FF4444]%d damage[/color]" % poison_dmg
			if turns_left > 0:
				poison_msg += " (%d rounds remaining)" % turns_left
			else:
				poison_msg += " - [color=#00FF00]Poison has worn off![/color]"
			send_to_peer(peer_id, {"type": "status_effect", "effect": "poison", "message": poison_msg, "damage": poison_dmg, "turns_remaining": turns_left})

	# Tick blind on meditate
	if character.blind_active:
		var still_blind = character.tick_blind()
		var turns_left = character.blind_turns_remaining
		if still_blind:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "blind", "message": "[color=#808080]You are blinded! (%d rounds remaining)[/color]" % turns_left, "turns_remaining": turns_left})
		else:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "blind_cured", "message": "[color=#00FF00]Your vision clears![/color]"})

	# Tick active buffs on meditate
	if not character.active_buffs.is_empty():
		var expired = character.tick_buffs()
		for buff in expired:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "buff_expired", "message": "[color=#808080]%s buff has worn off.[/color]" % buff.type})

	# Re-send character update after ticking effects
	send_to_peer(peer_id, {"type": "character_update", "character": character.to_dict()})

	# Chance to be ambushed while meditating (15%) — not in safe zones
	# Only the leader (or solo player) can trigger ambush, not party followers
	if not is_party_follower and not gathering_immune and not world_system.is_safe_zone(character.x, character.y):
		var ambush_roll = randi() % 100
		if ambush_roll < 15:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF4444]Your meditation is interrupted by an ambush![/color]"
			})
			trigger_encounter(peer_id)

func handle_combat_command(peer_id: int, message: Dictionary):
	"""Handle combat commands from player"""
	# Rate limit: 150ms minimum between combat commands
	var now = Time.get_ticks_msec()
	var last = combat_command_cooldown.get(peer_id, 0)
	if now - last < 150:
		return
	combat_command_cooldown[peer_id] = now

	var command = message.get("command", "")

	if command.is_empty():
		return

	# Check if player is in party combat — route to party combat handler
	if combat_mgr.party_combat_membership.has(peer_id):
		_handle_party_combat_command(peer_id, command)
		return

	# Process combat action
	var result = combat_mgr.process_combat_command(peer_id, command)

	if not result.get("success", false):
		# Send all error messages
		for msg in result.get("messages", []):
			send_combat_message(peer_id, msg)
		return

	# Send all combat messages
	for msg in result.get("messages", []):
		send_combat_message(peer_id, msg)

	# Accumulate messages in combat log for death screen
	if combat_mgr.active_combats.has(peer_id):
		combat_mgr.active_combats[peer_id].combat_log.append_array(result.messages)

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
			# Use base_name so variants (Weapon Master, Corrosive, etc.) share knowledge with base type
			var killed_monster_name = result.get("monster_name", "")
			var killed_monster_base_name = result.get("monster_base_name", killed_monster_name)
			var killed_monster_level = result.get("monster_level", 1)
			if killed_monster_base_name != "":
				characters[peer_id].record_monster_kill(killed_monster_base_name, killed_monster_level)

			# Check quest progress for kill-based quests (uses full name for variant-specific quests)
			var monster_level_for_quest = result.get("monster_level", 1)
			check_kill_quest_progress(peer_id, monster_level_for_quest, killed_monster_name)

			# Check if this was a bounty kill
			if characters[peer_id].has_meta("bounty_quest_id"):
				var bounty_qid = characters[peer_id].get_meta("bounty_quest_id")
				_on_bounty_kill(peer_id, bounty_qid)
				characters[peer_id].remove_meta("bounty_quest_id")

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

				# Track flock count for visual variety (summoner counts as flock)
				if not flock_counts.has(peer_id):
					flock_counts[peer_id] = 1
				else:
					flock_counts[peer_id] += 1

				# Queue the summoned monster (preserve dungeon flags for tile clearing)
				pending_flocks[peer_id] = {
					"monster_name": summon_next,
					"monster_level": monster_level,
					"flock_count": flock_counts[peer_id],  # For visual variety
					"is_dungeon_combat": result.get("is_dungeon_combat", false),
					"is_boss_fight": result.get("is_boss_fight", false),
					"dungeon_monster_id": result.get("dungeon_monster_id", -1)
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
				# Preserve dungeon combat flags so tile gets cleared after final flock monster
				pending_flocks[peer_id] = {
					"monster_name": monster_base_name,
					"monster_level": monster_level,
					"analyze_bonus": combat_mgr.get_analyze_bonus(peer_id),
					"flock_count": flock_counts[peer_id],  # For visual variety
					"is_dungeon_combat": result.get("is_dungeon_combat", false),
					"is_boss_fight": result.get("is_boss_fight", false),
					"dungeon_monster_id": result.get("dungeon_monster_id", -1)
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

				# Roll for monster part drop
				var soldier_level = characters[peer_id].job_levels.get("soldier", 0)
				var part_drop = drop_tables.roll_monster_part_drop(killed_monster_name, _get_monster_tier(killed_monster_level), soldier_level)
				if not part_drop.is_empty():
					all_drops.append({
						"type": "monster_part",
						"material_id": part_drop["id"],
						"material_name": part_drop["name"],
						"quantity": part_drop["qty"],
						"rarity": "common"
					})

				# Roll for tool drop
				var tool_drop = drop_tables.roll_tool_drop(_get_monster_tier(killed_monster_level))
				if not tool_drop.is_empty():
					all_drops.append(tool_drop)

				# Set pending harvest data — available to all players
				# Base 20% chance, scales up with soldier level (max ~70% at Lv100)
				var _soldier_lvl = characters[peer_id].job_levels.get("soldier", 1)
				var _harvest_chance = 0.20 + (_soldier_lvl * 0.005)  # 20% base + 0.5% per level
				if randf() < _harvest_chance:
					characters[peer_id].set_meta("pending_harvest", {
						"monster_name": killed_monster_base_name,
						"monster_tier": _get_monster_tier(killed_monster_level)
					})

				# Give all drops to player now
				var drop_messages = []
				var drop_data = []  # For client sound effects
				var player_level = characters[peer_id].level
				for item in all_drops:
					# Special handling for companion eggs
					if item.get("type", "") == "companion_egg":
						var egg_data = item.get("egg_data", {})
						var _egg_cap = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
						var egg_result = characters[peer_id].add_egg(egg_data, _egg_cap)
						if egg_result.success:
							drop_messages.append("[color=#A335EE]✦ COMPANION EGG: %s[/color]" % egg_data.get("name", "Mysterious Egg"))
							drop_messages.append("[color=#808080]  Walk %d steps to hatch it![/color]" % egg_data.get("hatch_steps", 100))
							drop_data.append({"rarity": "epic", "level": 1, "level_diff": 0, "is_egg": true})
						else:
							drop_messages.append("[color=#FF6666]★ %s found but eggs full! (%d/%d) ★[/color]" % [egg_data.get("name", "Egg"), characters[peer_id].incubating_eggs.size(), _egg_cap])
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
					# Monster part drops go into Material Pouch
					elif item.get("type", "") == "monster_part":
						var mp_id = item.get("material_id", "")
						var mp_name = item.get("material_name", mp_id)
						var mp_qty = item.get("quantity", 1)
						characters[peer_id].add_crafting_material(mp_id, mp_qty)
						var mp_qty_text = " x%d" % mp_qty if mp_qty > 1 else ""
						drop_messages.append("[color=#FF6600]◆ PART: %s%s[/color]" % [mp_name, mp_qty_text])
						drop_data.append({"rarity": "common", "level": 1, "level_diff": 0, "is_material": true})
					elif characters[peer_id].can_add_item() or _try_auto_salvage(peer_id):
						# Check if this item should be immediately auto-salvaged on obtain
						if _should_auto_salvage_item(peer_id, item):
							var salvage_result = drop_tables.get_salvage_value(item)
							var sal_mats = salvage_result.get("materials", {})
							for _mat_id in sal_mats:
								characters[peer_id].add_crafting_material(_mat_id, sal_mats[_mat_id])
							var sal_parts = []
							for _mat_id2 in sal_mats:
								sal_parts.append("%dx %s" % [sal_mats[_mat_id2], CraftingDatabaseScript.get_material_name(_mat_id2)])
							drop_messages.append("[color=#AA66FF]Auto-salvaged %s → %s[/color]" % [item.get("name", "item"), ", ".join(sal_parts) if not sal_parts.is_empty() else "nothing"])
						else:
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

				# Check if harvest is available for Soldier
				var _harvest_avail = characters[peer_id].has_meta("pending_harvest") and not characters[peer_id].get_meta("pending_harvest", {}).is_empty()

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
						"flock_drops": drop_messages,
						"total_gems": total_gems,
						"drop_data": drop_data,
						"harvest_available": _harvest_avail
					})

				# Check for Elder auto-grant (level 1000)
				check_elder_auto_grant(peer_id)

				# Save character after combat and notify of expired buffs
				save_character(peer_id)
				send_buff_expiration_notifications(peer_id)

				# Handle dungeon combat victory - mark monster dead and send updated state
				# Note: Combat state is erased by now, so we use result flags instead
				if result.get("is_dungeon_combat", false):
					var character = characters[peer_id]
					if character.in_dungeon:
						var is_boss = result.get("is_boss_fight", false)
						# Kill the monster entity if it was entity-based combat
						var dead_monster_id = result.get("dungeon_monster_id", -1)
						if dead_monster_id >= 0:
							_kill_dungeon_monster(character.current_dungeon_id, character.dungeon_floor, dead_monster_id)
						else:
							# Legacy tile-based encounter
							_clear_dungeon_tile(peer_id)
						character.dungeon_encounters_cleared += 1
						# Give player a breather - skip monster movement on next move
						dungeon_combat_breather[peer_id] = true
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
				# Send location update to refresh map with player's position outside dungeon
				send_location_update(peer_id)
			else:
				# Non-dungeon flee: send location update to refresh map at new position
				send_location_update(peer_id)
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

				# Queue the summoned monster as a pending flock (preserve dungeon flags)
				pending_flocks[peer_id] = {
					"monster_name": summon_next,
					"monster_level": monster_level,
					"flock_count": flock_counts[peer_id],
					"is_dungeon_combat": result.get("is_dungeon_combat", false),
					"is_boss_fight": result.get("is_boss_fight", false)
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
			# Defeated - check for death saves before permadeath
			var character = characters[peer_id]
			var was_saved = _check_death_saves_in_combat(peer_id, character)

			# Extract combat data BEFORE end_combat erases it
			var combat_data = combat_mgr.get_combat_summary(peer_id)

			# End combat either way - player escapes or dies
			combat_mgr.end_combat(peer_id, false)
			if pending_flock_drops.has(peer_id):
				pending_flock_drops.erase(peer_id)
			if pending_flock_gems.has(peer_id):
				pending_flock_gems.erase(peer_id)
			if flock_counts.has(peer_id):
				flock_counts.erase(peer_id)

			if was_saved:
				# Death save triggered - combat ends but player survives
				send_to_peer(peer_id, {
					"type": "combat_end",
					"victory": false,
					"death_saved": true,
					"character": character.to_dict()
				})
				send_location_update(peer_id)
			else:
				# Actually dead - handle permadeath
				handle_permadeath(peer_id, result.get("monster_name", "Unknown"), combat_data)
	else:
		# Combat continues - send updated state
		send_to_peer(peer_id, {
			"type": "combat_update",
			"combat_state": combat_mgr.get_combat_display(peer_id)
		})

func handle_combat_use_item(peer_id: int, message: Dictionary):
	"""Handle using an item during combat"""
	# Items not supported in party combat
	if combat_mgr.party_combat_membership.has(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Items cannot be used in party combat.[/color]"})
		return

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

	# Accumulate messages in combat log for death screen
	if combat_mgr.active_combats.has(peer_id):
		combat_mgr.active_combats[peer_id].combat_log.append_array(result.messages)

	# Check if combat ended (player died)
	if result.has("combat_ended") and result.combat_ended:
		if not result.get("victory", false):
			# Player died after using item - check for death saves
			var character = characters[peer_id]
			var was_saved = _check_death_saves_in_combat(peer_id, character)

			# Extract combat data BEFORE end_combat erases it
			var combat_data = combat_mgr.get_combat_summary(peer_id)

			# End combat either way
			combat_mgr.end_combat(peer_id, false)
			if pending_flock_drops.has(peer_id):
				pending_flock_drops.erase(peer_id)
			if pending_flock_gems.has(peer_id):
				pending_flock_gems.erase(peer_id)
			if flock_counts.has(peer_id):
				flock_counts.erase(peer_id)

			if was_saved:
				# Death save triggered - combat ends but player survives
				send_to_peer(peer_id, {
					"type": "combat_end",
					"victory": false,
					"death_saved": true,
					"character": character.to_dict()
				})
				send_location_update(peer_id)
			else:
				# Actually dead - handle permadeath
				handle_permadeath(peer_id, result.get("monster_name", "Unknown"), combat_data)
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

	# If in hotzone, prefer directions that leave the hotzone
	var in_hotzone = world_system.get_hotspot_at(current_x, current_y).in_hotspot
	if in_hotzone:
		var safe_dirs = []
		var zone_dirs = []
		for dir in directions:
			var test_pos = Vector2i(current_x + dir.x, current_y + dir.y)
			if not world_system.get_hotspot_at(test_pos.x, test_pos.y).in_hotspot:
				safe_dirs.append(dir)
			else:
				zone_dirs.append(dir)
		directions = safe_dirs + zone_dirs  # Try safe first, then zone
		# Clear hotzone tracking on flee
		if player_in_hotzone.has(peer_id):
			player_in_hotzone.erase(peer_id)

	for dir in directions:
		var new_pos = Vector2i(current_x + dir.x, current_y + dir.y)
		# Check if not occupied by another player
		if not occupied.has(new_pos):
			# Check world bounds (-1000 to 1000)
			if new_pos.x >= -1000 and new_pos.x <= 1000 and new_pos.y >= -1000 and new_pos.y <= 1000:
				# Check if tile blocks movement (walls, deep water, etc.)
				if chunk_manager:
					var tile = chunk_manager.get_tile(new_pos.x, new_pos.y)
					if tile.get("blocks_move", false):
						# Allow fleeing through depleted gathering nodes
						var tile_type = tile.get("type", "")
						if not (tile_type in world_system.GATHERABLE_TYPES and chunk_manager.is_node_depleted(new_pos.x, new_pos.y)):
							continue  # Tile is impassable, try next direction
				return {"x": new_pos.x, "y": new_pos.y}

	return null  # No valid flee destination (very rare)

func _check_death_saves_in_combat(peer_id: int, character: Character) -> bool:
	"""Check for death saves (guardian, eternal, high king) and restore HP if saved.
	Returns true if player was saved and combat should continue, false if actually dead."""

	# Check for Guardian death save (granted by Eternal)
	if character.guardian_death_save:
		character.guardian_death_save = false
		character.guardian_granted_by = ""
		character.current_hp = int(character.get_total_max_hp() * 0.25)  # Survive with 25% HP
		character.deaths += 1
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]The Guardian's blessing protects you from death![/color]"
		})
		if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
			handle_crucible_death(peer_id)
		send_character_update(peer_id)
		save_character(peer_id)
		return true

	# Check for High King crown protection
	if character.title == "high_king":
		character.current_hp = int(character.get_total_max_hp() * 0.25)  # Survive with 25% HP
		character.deaths += 1
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFD700]The Crown of the North saves you from death! But its power is now spent...[/color]"
		})
		broadcast_title_change(character.name, "high_king", "lost")
		character.title = ""
		character.title_data = {}
		current_high_king_id = -1
		if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
			handle_crucible_death(peer_id)
		send_character_update(peer_id)
		save_character(peer_id)
		return true

	# Check for Eternal lives
	if character.title == "eternal":
		var lives = character.title_data.get("lives", 3)
		if lives > 1:
			character.title_data["lives"] = lives - 1
			character.current_hp = int(character.get_total_max_hp() * 0.1)  # Survive with 10% HP
			character.deaths += 1
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FFFF]Your eternal essence prevents death! Lives remaining: %d[/color]" % (lives - 1)
			})
			if crucible_state.has(peer_id) and crucible_state[peer_id].get("in_crucible", false):
				handle_crucible_death(peer_id)
			send_character_update(peer_id)
			save_character(peer_id)
			return true

	return false  # No death save - player actually dies

# ===== PERMADEATH =====

func handle_permadeath(peer_id: int, cause_of_death: String, combat_data: Dictionary = {}):
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
		character.deaths += 1  # Track near-death
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
		character.deaths += 1  # Track near-death
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
			character.deaths += 1  # Track near-death
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

	# Create corpse BEFORE clearing dungeon state (need in_dungeon flag for location)
	var corpse = _create_corpse_from_character(character, cause_of_death)

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

	# Award baddie points to house before deleting character (need value for permadeath message)
	var baddie_points_earned = _award_baddie_points_on_death(peer_id, character, account_id, cause_of_death)

	# Send enriched permadeath message with full character snapshot
	send_to_peer(peer_id, {
		"type": "permadeath",
		"character_name": character.name,
		"level": character.level,
		"experience": character.experience,
		"cause_of_death": cause_of_death,
		"leaderboard_rank": rank,
		"baddie_points_earned": baddie_points_earned,
		"message": "[color=#FF0000]%s has fallen! Slain by %s.[/color]" % [character.name, cause_of_death],
		# Character snapshot
		"race": character.race,
		"class_type": character.class_type,
		"stats": {
			"strength": character.strength,
			"constitution": character.constitution,
			"dexterity": character.dexterity,
			"intelligence": character.intelligence,
			"wisdom": character.wisdom,
			"wits": character.wits
		},
		"equipped": character.equipped.duplicate(true),
		"gold": character.gold,
		"valor": persistence.get_valor(peers[peer_id].account_id) if peers.has(peer_id) else 0,
		"monsters_killed": character.monsters_killed,
		"active_companion": character.get_active_companion(),
		"collected_companions": character.get_collected_companions(),
		"incubating_eggs": character.incubating_eggs.duplicate(true),
		# Combat data from final fight
		"combat_log": combat_data.get("combat_log", []),
		"rounds_fought": combat_data.get("rounds", 0),
		"monster_base_name": combat_data.get("monster_base_name", ""),
		"monster_max_hp": combat_data.get("monster_max_hp", 0),
		"total_damage_dealt": combat_data.get("total_damage_dealt", 0),
		"total_damage_taken": combat_data.get("total_damage_taken", 0),
		"player_hp": character.current_hp,
		"player_max_hp": character.get_total_max_hp(),
		"player_hp_at_start": combat_data.get("player_hp_at_start", 0),
	})

	# Broadcast death announcement to ALL connected players (including those on character select)
	var death_message = "[color=#FF4444]%s (Level %d) has fallen to %s![/color]" % [character.name, character.level, cause_of_death]
	for pid in peers.keys():
		send_to_peer(pid, {
			"type": "chat",
			"sender": "World",
			"message": death_message
		})

	# Save corpse (created earlier before dungeon state was cleared)
	if not corpse.is_empty():
		persistence.add_corpse(corpse)
		_broadcast_corpse_spawn(corpse)

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

	# Vision radius — expanded in new chunk system, reduced when blinded
	var base_vision = WorldSystem.DEFAULT_VISION_RADIUS if chunk_manager else 6
	var vision_radius = WorldSystem.BLIND_VISION_RADIUS if character.blind_active else base_vision

	# Get nearby players for map display (within map radius)
	var nearby_players = get_nearby_players(peer_id, vision_radius)

	# Get nearby dungeon entrances for map display
	var dungeon_locations = get_visible_dungeons(character.x, character.y, vision_radius)

	# Get depleted node keys for map display (shows dim markers for depleted nodes)
	var depleted_keys = chunk_manager.get_depleted_keys() if chunk_manager else depleted_nodes.keys()

	# Get visible corpses for map display
	var visible_corpses = persistence.get_visible_corpses(character.x, character.y, vision_radius)

	# Gather bounty locations for this player's active bounty quests
	var bounty_locs = []
	for quest_id in active_bounties:
		var b = active_bounties[quest_id]
		if b.peer_id == peer_id:
			bounty_locs.append({"x": b.x, "y": b.y})

	# Get complete map display (includes location info at top)
	var map_display = world_system.generate_map_display(character.x, character.y, vision_radius, nearby_players, dungeon_locations, depleted_keys, visible_corpses, bounty_locs)

	# Check for gathering node at this location OR adjacent tiles
	var gathering_node = get_gathering_node_nearby(character.x, character.y)
	var is_at_water = false
	var water_type = ""
	var is_at_ore = false
	var current_ore_tier = 1
	var is_at_forest = false
	var current_wood_tier = 1

	# Suppress gathering nodes inside player enclosures (posts are safe zones, no resource harvesting)
	var loc_in_enclosure = enclosure_tile_lookup.has(Vector2i(character.x, character.y))
	if not gathering_node.is_empty() and not loc_in_enclosure:
		var node_type = gathering_node.get("type", "")
		var node_job = gathering_node.get("job", "")
		match node_type:
			"fishing", "water":
				is_at_water = true
				water_type = world_system.get_fishing_type(character.x, character.y) if world_system.has_method("get_fishing_type") else "shallow"
			"mining", "stone", "ore_vein":
				is_at_ore = true
				current_ore_tier = gathering_node.get("tier", 1)
			"logging", "tree", "dense_brush":
				is_at_forest = true
				current_wood_tier = gathering_node.get("tier", 1)
			_:
				# New node types (herb, flower, mushroom, bush, reed) — handled by gathering_node dict
				pass
	if loc_in_enclosure:
		gathering_node = {}  # Clear gathering node data for enclosure tiles

	# Check if player is at a dungeon entrance
	var dungeon_entrance = _get_dungeon_at_location(character.x, character.y, peer_id)
	var at_dungeon = not dungeon_entrance.is_empty()

	# Check if player is at a corpse
	var corpse_at_location = persistence.get_corpse_at(character.x, character.y)

	# Check if at a bounty location
	var at_bounty = false
	var bounty_quest_id_at_loc = ""
	for qid in active_bounties:
		var b = active_bounties[qid]
		if b.peer_id == peer_id and b.x == character.x and b.y == character.y:
			at_bounty = true
			bounty_quest_id_at_loc = qid
			break

	# Check if player is in any player enclosure (own or others) via fast lookup
	var in_own_enclosure = false
	var in_player_post = false
	var player_post_name = ""
	var player_post_is_own = false
	var enclosure_stations: Array = []
	var enclosure_has_inn = false
	var enclosure_has_storage = false
	var username = _get_username(peer_id)
	var loc_lookup_key = Vector2i(character.x, character.y)
	if enclosure_tile_lookup.has(loc_lookup_key):
		in_player_post = true
		var enc_owner = enclosure_tile_lookup[loc_lookup_key].owner
		var enc_idx = enclosure_tile_lookup[loc_lookup_key].enclosure_idx
		player_post_is_own = (enc_owner == username)
		in_own_enclosure = player_post_is_own
		# Get post name
		if player_post_names.has(enc_owner) and enc_idx < player_post_names[enc_owner].size():
			player_post_name = player_post_names[enc_owner][enc_idx].get("name", "")
		# Scan stations in this enclosure
		var enc_list = player_enclosures.get(enc_owner, [])
		if enc_idx < enc_list.size():
			for pos in enc_list[enc_idx]:
				var tile = chunk_manager.get_tile(int(pos.x), int(pos.y))
				var tile_type = tile.get("type", "")
				if tile_type in CraftingDatabaseScript.STATION_SKILL_MAP and tile_type not in enclosure_stations:
					enclosure_stations.append(tile_type)
				if tile_type == "inn":
					enclosure_has_inn = true
				if tile_type == "storage":
					enclosure_has_storage = true

	# Send map display as description
	var location_msg = {
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
		"dungeon_info": dungeon_entrance,
		"gathering_node": gathering_node,
		"at_corpse": not corpse_at_location.is_empty(),
		"corpse_info": corpse_at_location,
		"at_bounty": at_bounty,
		"bounty_quest_id": bounty_quest_id_at_loc
	}
	if in_player_post:
		location_msg["in_own_enclosure"] = player_post_is_own
		location_msg["in_player_post"] = true
		location_msg["player_post_name"] = player_post_name
		location_msg["player_post_is_own"] = player_post_is_own
		location_msg["enclosure_stations"] = enclosure_stations
		location_msg["enclosure_has_inn"] = enclosure_has_inn
		location_msg["enclosure_has_storage"] = enclosure_has_storage and player_post_is_own
	send_to_peer(peer_id, location_msg)

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
	var my_party_leader = party_membership.get(peer_id, -1)

	for other_peer_id in characters.keys():
		if other_peer_id == peer_id:
			continue  # Skip self

		var other_char = characters[other_peer_id]
		var dx = abs(other_char.x - my_x)
		var dy = abs(other_char.y - my_y)

		# Check if within map view radius
		if dx <= radius and dy <= radius:
			var is_party_mate = (my_party_leader != -1 and party_membership.get(other_peer_id, -1) == my_party_leader)
			result.append({
				"x": other_char.x,
				"y": other_char.y,
				"name": other_char.name,
				"level": other_char.level,
				"in_my_party": is_party_mate
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

func _send_gold_migration_message(peer_id: int, converted_valor: int):
	if not peers.has(peer_id):
		return
	send_to_peer(peer_id, {
		"type": "text",
		"message": "\n[color=#FFD700]══════════════════════════════════════[/color]\n[color=#FFD700]  CURRENCY CHANGE: Gold → Valor[/color]\n[color=#FFD700]══════════════════════════════════════[/color]\n\nGold has been replaced by [color=#FFD700]Valor[/color], an account-level\ncurrency that persists through death.\n\nYour old gold has been converted:\n  [color=#FFD700]→ %d Valor[/color] added to your account\n\nEarn Valor by listing items on the [color=#00FF00]Open Market[/color]\nat any Trading Post (walk to the $ tile).\n" % converted_valor
	})

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

	# Save combat state to character BEFORE ending combat (for disconnect recovery)
	# Only save if player has HP > 0 (if they died, don't restore combat)
	if combat_mgr.is_in_combat(peer_id) and characters.has(peer_id):
		var character = characters[peer_id]
		if character.current_hp > 0:
			var combat_state = combat_mgr.serialize_combat_state(peer_id)
			# Include flock info if player was in a flock fight
			if flock_counts.has(peer_id):
				combat_state["flock_remaining"] = flock_counts[peer_id]
			character.saved_combat_state = combat_state
			print("COMBAT PERSISTENCE: Saved combat state for %s - fighting %s" % [
				character.name, combat_state.get("monster", {}).get("name", "Unknown")])
		else:
			print("COMBAT PERSISTENCE: Not saving combat for %s - player HP is 0" % character.name)

	# Save character before removing (now includes combat state)
	save_character(peer_id)

	# Remove from combat (don't count as loss since we saved state)
	if combat_mgr.is_in_combat(peer_id):
		combat_mgr.end_combat(peer_id, false)

	# Clear pending flock if any (saved to character already)
	if pending_flocks.has(peer_id):
		pending_flocks.erase(peer_id)
	if flock_counts.has(peer_id):
		flock_counts.erase(peer_id)
	# Clear pending wish if any
	if pending_wishes.has(peer_id):
		pending_wishes.erase(peer_id)
	# Clear pending scroll use (item is lost on disconnect)
	pending_scroll_use.erase(peer_id)
	# Clear combat command cooldown
	combat_command_cooldown.erase(peer_id)
	# Clear station tracking
	at_player_station.erase(peer_id)
	# Clear pending craft challenge (materials already consumed, lost on disconnect)
	active_crafts.erase(peer_id)
	# Clear active gathering/harvest sessions
	active_gathering.erase(peer_id)
	active_harvests.erase(peer_id)
	gathering_cooldown.erase(peer_id)

	# Clean up merchant position tracking
	var player_key = "p_%d" % peer_id
	if last_merchant_cache_positions.has(player_key):
		last_merchant_cache_positions.erase(player_key)

	# Clean up watch relationships before erasing character
	cleanup_watcher_on_disconnect(peer_id)

	# Clean up party state
	_cleanup_party_on_disconnect(peer_id)

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

	# Clean up dungeon active_players tracking (but preserve dungeon state for reconnect)
	if characters.has(peer_id):
		var character = characters[peer_id]
		if character.in_dungeon:
			var instance_id = character.current_dungeon_id
			# Remove from dungeon's active players list
			if active_dungeons.has(instance_id):
				var instance = active_dungeons[instance_id]
				instance.active_players.erase(peer_id)
				# Store owner username for reconnect lookup
				if not instance.has("owner_username"):
					instance["owner_username"] = username
			# DON'T call exit_dungeon() — dungeon state is saved to character for reconnect

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

	# Check if player is a party leader — start party combat instead
	if _is_party_leader(peer_id):
		_start_party_combat_encounter(peer_id, monster, debuff_messages)
		return

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
			"use_client_art": true,  # Client should render ASCII art locally
			"extra_combat_text": result.get("extra_combat_text", "")
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
			"use_client_art": true,
			"extra_combat_text": result.get("extra_combat_text", "")
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
		# Fallback to tier-appropriate materials
		var tier = clampi(int(area_level / 15), 0, 8)
		var ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
		var ore_id = ore_tiers[mini(tier, ore_tiers.size() - 1)]
		var qty = maxi(1, randi_range(2, 4) + tier)
		character.add_crafting_material(ore_id, qty)
		var mat_name = CraftingDatabaseScript.get_material_name(ore_id)
		var find_text = "Found %dx %s!" % [qty, mat_name]
		if find_text.length() < 34:
			find_text = find_text + " ".repeat(34 - find_text.length())
		msg = "[color=#FFD700]+====================================+[/color]\n"
		msg += "[color=#FFD700]|[/color]          [color=#00FF00]* LUCKY FIND! *[/color]           [color=#FFD700]|[/color]\n"
		msg += "[color=#FFD700]+====================================+[/color]\n"
		msg += "[color=#FFD700]|[/color] You discover a hidden cache!       [color=#FFD700]|[/color]\n"
		msg += "[color=#FFD700]|[/color] [color=#8B5CF6]%s[/color] [color=#FFD700]|[/color]\n" % find_text
		msg += "[color=#FFD700]+====================================+[/color]"
	else:
		# Add items to inventory (with auto-salvage check)
		var item = items[0]
		var was_auto_salvaged = false
		var auto_salvage_mats: Dictionary = {}
		if character.can_add_item():
			if _should_auto_salvage_item(peer_id, item):
				var salvage_result = drop_tables.get_salvage_value(item)
				auto_salvage_mats = salvage_result.get("materials", {})
				for mat_id in auto_salvage_mats:
					character.add_crafting_material(mat_id, auto_salvage_mats[mat_id])
				was_auto_salvaged = true
			else:
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
		if was_auto_salvaged:
			var sal_parts = []
			for mat_id in auto_salvage_mats:
				var mat_name = CraftingDatabaseScript.get_material_name(mat_id)
				sal_parts.append("%dx %s" % [auto_salvage_mats[mat_id], mat_name])
			if not sal_parts.is_empty():
				msg += "\n[color=#AA66FF]Auto-salvaged: %s[/color]" % ", ".join(sal_parts)
		elif not character.can_add_item() and items.size() > 0:
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


# Track pending blacksmith/healer encounters (peer_id -> repair costs/heal costs)
var pending_blacksmith_encounters: Dictionary = {}
var pending_blacksmith_upgrades: Dictionary = {}  # Track upgrade state
var pending_healer_encounters: Dictionary = {}

func _handle_blacksmith_station(peer_id: int, character):
	"""Handle bump into blacksmith station tile — open repair/upgrade menu."""
	var bs_account_id = peers[peer_id].account_id if peers.has(peer_id) else ""

	# Check if player has damaged gear
	var damaged_items = []
	var total_repair_cost = 0

	for slot_name in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = character.equipped.get(slot_name)
		if item and item.has("wear"):
			var wear = item.get("wear", 0)
			if wear > 0:
				var item_level = item.get("level", 1)
				var repair_cost = int(wear * item_level * 25)
				var valor_cost = max(1, repair_cost / 10)
				damaged_items.append({
					"slot": slot_name,
					"name": item.get("name", slot_name.capitalize()),
					"wear": wear,
					"cost": valor_cost
				})
				total_repair_cost += valor_cost

	# Check for items with upgradeable affixes
	var upgradeable_items = []
	for slot_name in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = character.equipped.get(slot_name)
		if item and item.has("affixes"):
			var affixes = item.get("affixes", {})
			var stat_affixes = []
			for key in affixes.keys():
				if key not in ["prefix_name", "suffix_name", "roll_quality", "proc_type", "proc_value", "proc_chance", "proc_name"]:
					stat_affixes.append(key)
			if stat_affixes.size() > 0:
				upgradeable_items.append({
					"slot": slot_name,
					"name": item.get("name", slot_name.capitalize()),
					"level": item.get("level", 1),
					"affixes": affixes
				})

	# Store encounter data (costs are already in valor)
	var repair_all_cost = int(total_repair_cost * 0.9) if total_repair_cost > 0 else 0
	pending_blacksmith_encounters[peer_id] = {
		"items": damaged_items,
		"total_cost": total_repair_cost,
		"repair_all_cost": repair_all_cost,
		"upgradeable_items": upgradeable_items
	}

	# Build message
	var msg = "[color=#DAA520]═══════ BLACKSMITH ═══════[/color]\n"
	if damaged_items.size() > 0:
		msg += "'I can fix up that gear for you, traveler.'"
	else:
		msg += "[color=#808080]Your gear is in good shape.[/color]"
	if upgradeable_items.size() > 0:
		msg += "\n[color=#FFD700]'I can also enhance your equipment... for a price.'[/color]"

	send_to_peer(peer_id, {
		"type": "blacksmith_encounter",
		"message": msg,
		"items": damaged_items,
		"repair_all_cost": repair_all_cost,
		"can_upgrade": upgradeable_items.size() > 0,
		"player_valor": persistence.get_valor(bs_account_id),
		"player_materials": character.crafting_materials.duplicate()
	})

func check_blacksmith_encounter(_peer_id: int) -> bool:
	"""Blacksmith is now a station — random encounters disabled."""
	return false

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
			"message": "[color=#808080]You step away from the anvil.[/color]"
		})
		send_to_peer(peer_id, {"type": "blacksmith_done"})
		return

	if choice == "repair_all":
		var valor_cost = encounter.repair_all_cost
		var account_id = peers[peer_id].account_id
		if not persistence.spend_valor(account_id, valor_cost):
			send_to_peer(peer_id, {"type": "error", "message": "Not enough valor! (Need %d)" % valor_cost})
			return

		# Repair all items
		for item_data in encounter.items:
			var slot = item_data.slot
			if character.equipped.has(slot):
				character.equipped[slot]["wear"] = 0

		pending_blacksmith_encounters.erase(peer_id)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]The Blacksmith repairs all your gear for %d valor (10%% discount!).[/color]" % valor_cost
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

		var valor_cost = item_data.cost
		var account_id = peers[peer_id].account_id
		if not persistence.spend_valor(account_id, valor_cost):
			send_to_peer(peer_id, {"type": "error", "message": "Not enough valor! (Need %d)" % valor_cost})
			return

		character.equipped[slot]["wear"] = 0

		# Update encounter data
		encounter.items.erase(item_data)
		encounter.total_cost -= valor_cost
		encounter.repair_all_cost = int(encounter.total_cost * 0.9)

		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]The Blacksmith repairs your %s for %d valor.[/color]" % [item_data.name, valor_cost]
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
				"player_valor": persistence.get_valor(account_id)
			})

		save_character(peer_id)
		send_character_update(peer_id)
		return

	# === UPGRADE FLOW ===
	if choice == "upgrade":
		# Show items available for upgrade
		var upgradeable = encounter.get("upgradeable_items", [])
		if upgradeable.size() == 0:
			send_to_peer(peer_id, {"type": "error", "message": "No upgradeable items!"})
			return

		send_to_peer(peer_id, {
			"type": "blacksmith_upgrade_select_item",
			"message": "[color=#FFD700]'Which piece needs enhancing?'[/color]",
			"items": upgradeable,
			"player_valor": persistence.get_valor(peers[peer_id].account_id) if peers.has(peer_id) else 0,
			"player_materials": character.crafting_materials.duplicate()
		})
		return

	if choice == "select_upgrade_item":
		var slot = message.get("slot", "")
		var upgradeable = encounter.get("upgradeable_items", [])
		var selected_item = null

		for item in upgradeable:
			if item.slot == slot:
				selected_item = item
				break

		if not selected_item:
			send_to_peer(peer_id, {"type": "error", "message": "Invalid item slot."})
			return

		# Get the actual item from equipped
		var equipped_item = character.equipped.get(slot)
		if not equipped_item:
			send_to_peer(peer_id, {"type": "error", "message": "Item not equipped."})
			return

		# Build list of upgradeable affixes with costs
		var affix_options = []
		var item_level = equipped_item.get("level", 1)
		var affixes = equipped_item.get("affixes", {})

		for affix_key in affixes.keys():
			if affix_key in ["prefix_name", "suffix_name", "roll_quality", "proc_type", "proc_value", "proc_chance", "proc_name"]:
				continue

			var current_value = affixes[affix_key]
			var upgrade_amount = _calculate_affix_upgrade_amount(affix_key, item_level)
			var costs = _calculate_affix_upgrade_cost(affix_key, current_value, item_level)

			affix_options.append({
				"affix_key": affix_key,
				"affix_name": _get_affix_display_name(affix_key),
				"current_value": current_value,
				"upgrade_amount": upgrade_amount,
				"valor_cost": costs.valor,
				"material_costs": costs.get("materials", {})
			})

		# Store pending upgrade state
		pending_blacksmith_upgrades[peer_id] = {
			"slot": slot,
			"item_name": selected_item.name,
			"affixes": affix_options
		}

		var upgrade_account_id = peers[peer_id].account_id
		send_to_peer(peer_id, {
			"type": "blacksmith_upgrade_select_affix",
			"message": "[color=#FFD700]'Which enchantment shall I strengthen on your %s?'[/color]" % selected_item.name,
			"item_name": selected_item.name,
			"affixes": affix_options,
			"player_valor": persistence.get_valor(upgrade_account_id),
			"player_materials": character.crafting_materials.duplicate()
		})
		return

	if choice == "confirm_upgrade":
		if not pending_blacksmith_upgrades.has(peer_id):
			send_to_peer(peer_id, {"type": "error", "message": "No upgrade pending."})
			return

		var upgrade_state = pending_blacksmith_upgrades[peer_id]
		var affix_key = message.get("affix_key", "")
		var slot = upgrade_state.slot

		# Find the affix in the options
		var selected_affix = null
		for affix in upgrade_state.affixes:
			if affix.affix_key == affix_key:
				selected_affix = affix
				break

		if not selected_affix:
			send_to_peer(peer_id, {"type": "error", "message": "Invalid affix selected."})
			return

		# Check costs
		var valor_cost = selected_affix.get("valor_cost", 50)
		var mat_costs = selected_affix.get("material_costs", {})
		var account_id = peers[peer_id].account_id

		if not persistence.spend_valor(account_id, valor_cost):
			send_to_peer(peer_id, {"type": "error", "message": "Not enough valor! (Need %d)" % valor_cost})
			return
		if not character.has_crafting_materials(mat_costs):
			persistence.add_valor(account_id, valor_cost)  # Refund valor
			send_to_peer(peer_id, {"type": "error", "message": "Not enough materials for this upgrade!"})
			return

		# Apply upgrade — spend materials
		for mat_id in mat_costs:
			character.remove_crafting_material(mat_id, mat_costs[mat_id])

		var equipped_item = character.equipped.get(slot)
		if equipped_item and equipped_item.has("affixes"):
			var old_value = equipped_item["affixes"].get(affix_key, 0)
			equipped_item["affixes"][affix_key] = old_value + selected_affix.upgrade_amount

		pending_blacksmith_upgrades.erase(peer_id)
		pending_blacksmith_encounters.erase(peer_id)

		# Build material cost string
		var mat_parts = []
		for mat_id in mat_costs:
			var mat_name = mat_id.replace("_", " ").capitalize()
			mat_parts.append("%d %s" % [mat_costs[mat_id], mat_name])
		var cost_str = "%d valor" % valor_cost
		if not mat_parts.is_empty():
			cost_str += ", " + ", ".join(mat_parts)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFD700]The Blacksmith enhances your %s![/color]\n[color=#00FF00]%s: %d → %d[/color]\n[color=#808080](Cost: %s)[/color]" % [
				upgrade_state.item_name,
				selected_affix.affix_name,
				selected_affix.current_value,
				selected_affix.current_value + selected_affix.upgrade_amount,
				cost_str
			]
		})
		send_to_peer(peer_id, {"type": "blacksmith_done"})
		save_character(peer_id)
		send_character_update(peer_id)
		return

	if choice == "cancel_upgrade":
		pending_blacksmith_upgrades.erase(peer_id)
		# Return to main blacksmith menu
		send_to_peer(peer_id, {
			"type": "blacksmith_encounter",
			"message": "[color=#DAA520]'Changed your mind? Anything else?'[/color]",
			"items": encounter.get("items", []),
			"repair_all_cost": encounter.get("repair_all_cost", 0),
			"can_upgrade": encounter.get("upgradeable_items", []).size() > 0,
			"player_valor": persistence.get_valor(peers[peer_id].account_id) if peers.has(peer_id) else 0,
			"player_materials": character.crafting_materials.duplicate()
		})
		return

func _calculate_affix_upgrade_amount(affix_key: String, item_level: int) -> int:
	"""Calculate how much an affix increases when upgraded."""
	# Base upgrade amounts by affix type
	var base_amounts = {
		"str_bonus": 5, "con_bonus": 5, "dex_bonus": 5, "int_bonus": 5, "wis_bonus": 5, "wits_bonus": 5,
		"attack_bonus": 10, "defense_bonus": 10, "speed_bonus": 5,
		"hp_bonus": 50, "mana_bonus": 25, "stamina_bonus": 15, "energy_bonus": 15
	}
	var base = base_amounts.get(affix_key, 5)
	# Scale with item level: +5 per 50 levels
	var level_bonus = int(item_level / 50) * 5
	return base + level_bonus

func _calculate_affix_upgrade_cost(affix_key: String, current_value: int, item_level: int) -> Dictionary:
	"""Calculate the cost to upgrade an affix. Costs: Valor + tier-appropriate materials."""
	var level_mult = 1.0 + (item_level / 10.0)
	var value_mult = 1.0 + (current_value / 10.0)

	var valor_base = 50

	# Determine tier-appropriate materials based on item level
	var tier = clampi(int(item_level / 15), 0, 8)
	var ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
	var enchant_tiers = ["magic_dust", "magic_dust", "arcane_crystal", "arcane_crystal", "soul_shard", "soul_shard", "void_essence", "void_essence", "primordial_spark"]
	var ore_id = ore_tiers[mini(tier, ore_tiers.size() - 1)]
	var enchant_id = enchant_tiers[mini(tier, enchant_tiers.size() - 1)]

	var ore_qty = maxi(1, int(2 * level_mult * value_mult))
	var enchant_qty = maxi(1, int(1 * level_mult * value_mult))

	return {
		"valor": int(valor_base * level_mult * value_mult),
		"materials": {ore_id: ore_qty, enchant_id: enchant_qty}
	}

func _get_affix_display_name(affix_key: String) -> String:
	"""Get a human-readable name for an affix key."""
	var names = {
		"str_bonus": "Strength",
		"con_bonus": "Constitution",
		"dex_bonus": "Dexterity",
		"int_bonus": "Intelligence",
		"wis_bonus": "Wisdom",
		"wits_bonus": "Wits",
		"attack_bonus": "Attack",
		"defense_bonus": "Defense",
		"speed_bonus": "Speed",
		"hp_bonus": "Max HP",
		"mana_bonus": "Max Mana",
		"stamina_bonus": "Max Stamina",
		"energy_bonus": "Max Energy"
	}
	return names.get(affix_key, affix_key.capitalize())

func _handle_healer_station(peer_id: int, character):
	"""Handle bump into healer station tile — open heal menu."""
	# Calculate heal costs in valor (gold / 10)
	var level = character.level
	var quick_heal_cost = max(1, level * 22 / 10)
	var full_heal_cost = max(1, level * 90 / 10)
	var cure_all_cost = max(1, level * 180 / 10)

	var has_debuffs = character.poison_active or character.blind_active or character.has_debuff("weakness")

	# Store encounter data
	pending_healer_encounters[peer_id] = {
		"quick_heal_cost": quick_heal_cost,
		"full_heal_cost": full_heal_cost,
		"cure_all_cost": cure_all_cost,
		"has_debuffs": has_debuffs
	}

	# Build message
	var msg = "[color=#00FF88]═══════ HEALER ═══════[/color]\n"
	var hp_ratio = float(character.current_hp) / max(1, character.get_total_max_hp())
	if hp_ratio < 0.80 or has_debuffs:
		msg += "'You look injured, traveler. Let me help.'"
	else:
		msg += "'You look healthy! But I'm here if you need me.'"

	send_to_peer(peer_id, {
		"type": "healer_encounter",
		"message": msg,
		"quick_heal_cost": quick_heal_cost,
		"full_heal_cost": full_heal_cost,
		"cure_all_cost": cure_all_cost,
		"has_debuffs": has_debuffs,
		"player_valor": persistence.get_valor(peers[peer_id].account_id) if peers.has(peer_id) else 0,
		"current_hp": character.current_hp,
		"max_hp": character.get_total_max_hp()
	})

func check_healer_encounter(_peer_id: int) -> bool:
	"""Healer is now a station — random encounters disabled."""
	return false

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
			"message": "[color=#808080]You step away from the healer's shrine.[/color]"
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

	var valor_cost = cost  # Already in valor
	var healer_account_id = peers[peer_id].account_id
	if not persistence.spend_valor(healer_account_id, valor_cost):
		send_to_peer(peer_id, {"type": "error", "message": "Not enough valor! (Need %d)" % valor_cost})
		send_to_peer(peer_id, {"type": "healer_done"})
		return

	var total_max_hp = character.get_total_max_hp()
	heal_amount = int(total_max_hp * heal_percent / 100.0)
	character.current_hp = mini(character.current_hp + heal_amount, total_max_hp)

	var msg = "[color=#00FF00]The Healer channels their magic. You are healed for %d HP! (-%d valor)[/color]" % [heal_amount, valor_cost]

	if cure_debuffs:
		character.persistent_buffs.clear()
		character.cure_poison()
		character.cure_blind()
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

func trigger_flock_encounter(peer_id: int, monster_name: String, monster_level: int, analyze_bonus: int = 0, flock_count: int = 1, is_dungeon_combat: bool = false, is_boss_fight: bool = false, dungeon_monster_id: int = -1):
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

	# Preserve flock count and dungeon combat flags for tile clearing after final flock monster
	var internal_state = combat_mgr.get_active_combat(peer_id)
	if internal_state:
		internal_state["flock_count"] = flock_count  # Store flock count for flee bonus calculation
		if is_dungeon_combat:
			internal_state["is_dungeon_combat"] = true
			internal_state["is_boss_fight"] = is_boss_fight
			# Propagate monster entity ID for cleanup after flock chain
			if dungeon_monster_id >= 0:
				internal_state["dungeon_monster_id"] = dungeon_monster_id

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
			"use_client_art": true,  # Client should render ASCII art locally
			"is_dungeon_combat": is_dungeon_combat,  # Pass to client for UI state
			"extra_combat_text": result.get("extra_combat_text", "")
		})
		# Forward to watchers
		forward_to_watchers(peer_id, flock_msg)

func handle_continue_flock(peer_id: int):
	"""Handle player continuing into a flock encounter"""
	if not pending_flocks.has(peer_id):
		return

	var flock_data = pending_flocks[peer_id]
	pending_flocks.erase(peer_id)

	# Pass analyze bonus, flock count, and dungeon combat flags
	var analyze_bonus = flock_data.get("analyze_bonus", 0)
	var flock_count = flock_data.get("flock_count", 1)
	var is_dungeon_combat = flock_data.get("is_dungeon_combat", false)
	var is_boss_fight = flock_data.get("is_boss_fight", false)
	var dungeon_mid = flock_data.get("dungeon_monster_id", -1)
	trigger_flock_encounter(peer_id, flock_data.monster_name, flock_data.monster_level, analyze_bonus, flock_count, is_dungeon_combat, is_boss_fight, dungeon_mid)

# ===== INVENTORY HANDLERS =====

func _open_treasure_chest(peer_id: int, item_index: int):
	"""Open a treasure chest for random materials and gold."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	if item_index < 0 or item_index >= character.inventory.size():
		return
	var item = character.inventory[item_index]
	var tier = int(item.get("tier", 1))
	var chest_name = item.get("name", "Treasure Chest")

	# Remove chest from inventory
	character.inventory.remove_at(item_index)

	# Roll 2-4 random materials appropriate to the tier
	var num_rewards = randi_range(2, 4)
	var reward_materials = {}
	var material_pool = _get_chest_material_pool(tier)
	for _i in range(num_rewards):
		if material_pool.is_empty():
			break
		var mat_id = material_pool[randi() % material_pool.size()]
		var qty = randi_range(1, 2 + tier)
		if reward_materials.has(mat_id):
			reward_materials[mat_id] += qty
		else:
			reward_materials[mat_id] = qty

	# Grant materials
	for mat_id in reward_materials:
		character.add_crafting_material(mat_id, reward_materials[mat_id])

	# Gold bonus scaled by tier
	var gold_bonus = randi_range(25 + tier * 25, 100 + tier * 50)
	character.gold += gold_bonus

	# Build result message
	var msg = "[color=#FFD700]You open the %s![/color]\n" % chest_name
	msg += "[color=#00FF00]Found:[/color]\n"
	for mat_id in reward_materials:
		var mat_name = mat_id.replace("_", " ").capitalize()
		msg += "  [color=#00BFFF]%s x%d[/color]\n" % [mat_name, reward_materials[mat_id]]
	msg += "  [color=#FFD700]%d Gold[/color]" % gold_bonus

	send_to_peer(peer_id, {"type": "text", "message": msg})
	save_character(peer_id)
	send_character_update(peer_id)

func _get_chest_material_pool(tier: int) -> Array:
	"""Get a pool of possible materials for a treasure chest of given tier."""
	var pool = []
	match tier:
		1:
			pool = ["small_fish", "medium_fish", "seaweed", "copper_ore", "coal", "rough_gem", "oak_log", "pine_log", "healing_herb"]
		2:
			pool = ["freshwater_pearl", "iron_ore", "tin_ore", "birch_log", "maple_log", "leather", "healing_herb", "mana_blossom"]
		3:
			pool = ["steel_ore", "silver_ore", "polished_gem", "ironwood", "enchanted_hide", "arcane_crystal", "shadowleaf"]
		4:
			pool = ["mithril_ore", "gold_ore", "ebonwood", "flawless_gem", "dragon_scale", "phoenix_feather", "soul_shard"]
		_:
			pool = ["copper_ore", "coal", "oak_log", "small_fish"]
	return pool

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
	var item_tier = int(item.get("tier", 0))  # 0 means old-style item, int() ensures proper dict key lookup
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

	# For crafted consumables, effect is stored in the item itself
	if effect.is_empty() and item.has("effect"):
		var crafted_effect = item.get("effect", {})
		# Convert crafted format to expected format
		var effect_type = crafted_effect.get("type", "")
		match effect_type:
			"heal":
				effect = {"heal": true, "base": crafted_effect.get("amount", 50), "per_level": 0}
			"restore_mana":
				effect = {"mana": true, "base": crafted_effect.get("amount", 30), "per_level": 0}
			"restore_stamina":
				effect = {"stamina": true, "base": crafted_effect.get("amount", 30), "per_level": 0}
			"restore_energy":
				effect = {"energy": true, "base": crafted_effect.get("amount", 30), "per_level": 0}
			"buff":
				# Crafted buff format: {"type": "buff", "stat": "attack", "amount": 15, "duration": 10}
				var buff_stat = crafted_effect.get("stat", "attack")
				var buff_amount = crafted_effect.get("amount", 10)
				var buff_duration = crafted_effect.get("duration", 5)
				effect = {"buff": buff_stat, "base": buff_amount, "per_level": 0, "base_duration": buff_duration, "duration_per_10_levels": 0}
				# Crafted buffs are round-based (single combat) by default
				if crafted_effect.get("battles", false):
					effect["battles"] = true

	# Treasure chest — open for random materials and gold
	if item_type == "treasure_chest":
		_open_treasure_chest(peer_id, index)
		return

	# Check for enhancement scroll (special item type that applies permanent enchantments)
	if item_type == "enhancement_scroll":
		var scroll_slot = item.get("slot", "weapon")
		var scroll_effect = item.get("effect", {})
		var stat = scroll_effect.get("stat", "attack")
		var bonus = scroll_effect.get("bonus", 3)

		# For "all" stat scrolls, can be applied to any equipped item
		var target_item = null
		var target_slot = ""

		if scroll_slot == "any" or stat == "all":
			# Find first equipped item (prefer weapon, then armor)
			for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
				if character.equipped.get(slot, null) != null:
					target_item = character.equipped[slot]
					target_slot = slot
					break
		else:
			target_item = character.equipped.get(scroll_slot, null)
			target_slot = scroll_slot

		if target_item == null:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF4444]No equipment to enhance![/color]"
			})
			return

		# Initialize enchantments if needed
		if not target_item.has("enchantments"):
			target_item["enchantments"] = {}

		# Apply enhancement (respects enchantment caps)
		var enhance_name = target_item.get("name", "item")
		if stat == "all":
			# Apply bonus to all 10 stats (capped individually)
			var all_stats = ["attack", "defense", "speed", "max_hp", "strength", "constitution", "dexterity", "intelligence", "wisdom", "wits"]
			var applied_count = 0
			for s in all_stats:
				var cap = CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(s, 60)
				var current = target_item["enchantments"].get(s, 0)
				if current < cap:
					var actual_bonus = mini(bonus, cap - current)
					target_item["enchantments"][s] = current + actual_bonus
					applied_count += 1
			if applied_count > 0:
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#A335EE]Enhanced %s with +%d to ALL stats! (capped at limits)[/color]" % [enhance_name, bonus]
				})
			else:
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFFF00]%s is already at enchantment cap for all stats![/color]" % enhance_name
				})
				# Don't consume scroll — put it back
				character.inventory.insert(index, item)
				send_character_update(peer_id)
				return
		else:
			var cap = CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(stat, 60)
			var current = target_item["enchantments"].get(stat, 0)
			if current >= cap:
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFFF00]%s has reached the %s enchantment cap (+%d)![/color]" % [enhance_name, stat, cap]
				})
				character.inventory.insert(index, item)
				send_character_update(peer_id)
				return
			var actual_bonus = mini(bonus, cap - current)
			target_item["enchantments"][stat] = current + actual_bonus
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FF00]Enhanced %s with +%d %s! (%d/%d cap)[/color]" % [enhance_name, actual_bonus, stat, current + actual_bonus, cap]
			})

		# Remove scroll from inventory
		character.remove_item(index)
		send_character_update(peer_id)
		save_character(peer_id)
		return

	if effect.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]This item cannot be used directly. Try equipping it.[/color]"
		})
		return

	# Home Stone selection: if egg/equipment needs player choice, send selection instead of auto-using
	if effect.has("home_stone"):
		var stone_type = effect.home_stone
		if stone_type == "supplies":
			# Always show selection UI so player can choose which items to send
			var sendable_items = []
			for ci in range(character.inventory.size()):
				var inv_item = character.inventory[ci]
				sendable_items.append({"index": ci, "item": inv_item})
			if sendable_items.size() > 0:
				if not _home_stone_pre_validate(peer_id, character, stone_type):
					return
				var options = []
				for ci2 in range(sendable_items.size()):
					var entry = sendable_items[ci2]
					var itm = entry.item
					var qty = itm.get("quantity", 1)
					var qty_text = " x%d" % qty if qty > 1 else ""
					options.append({
						"index": ci2,
						"inv_index": entry.index,
						"quantity": qty,
						"label": "%s%s" % [itm.get("name", "Unknown"), qty_text]
					})
				character.set_meta("pending_home_stone_index", index)
				send_to_peer(peer_id, {
					"type": "home_stone_select",
					"stone_type": "supplies",
					"options": options,
					"message": "[color=#00FFFF]Choose supplies to send to your Sanctuary (up to 10):[/color]"
				})
				return
			else:
				send_to_peer(peer_id, {"type": "error", "message": "You have no items to send home!"})
				return
		elif stone_type == "egg":
			if character.incubating_eggs.is_empty():
				send_to_peer(peer_id, {"type": "error", "message": "You have no eggs to send home!"})
				return
			# Multiple eggs - ask player to choose
			if not _home_stone_pre_validate(peer_id, character, stone_type):
				return
			var options = []
			for i in range(character.incubating_eggs.size()):
				var egg = character.incubating_eggs[i]
				var steps_done = egg.get("hatch_steps", 100) - egg.get("steps_remaining", 0)
				var steps_total = egg.get("hatch_steps", 100)
				var frozen_tag = " [FROZEN]" if egg.get("frozen", false) else ""
				options.append({
					"index": i,
					"label": "%s (Tier %d) - %d/%d steps%s" % [egg.get("monster_type", "Unknown") + " Egg", egg.get("tier", 1), steps_done, steps_total, frozen_tag]
				})
			character.set_meta("pending_home_stone_index", index)
			send_to_peer(peer_id, {
				"type": "home_stone_select",
				"stone_type": "egg",
				"options": options,
				"message": "[color=#00FFFF]Choose an egg to send to your Sanctuary:[/color]"
			})
			return
		elif stone_type == "equipment":
			# Show selection UI for inventory equipment items
			var equipment_items = []
			for ei in range(character.inventory.size()):
				var inv_item = character.inventory[ei]
				var inv_slot = Character.get_item_slot_from_type(inv_item.get("type", ""))
				if inv_slot != "":
					equipment_items.append({"index": ei, "item": inv_item})
			if equipment_items.size() > 0:
				if not _home_stone_pre_validate(peer_id, character, stone_type):
					return
				var options = []
				for i in range(equipment_items.size()):
					var entry = equipment_items[i]
					var itm = entry.item
					options.append({
						"index": i,
						"inv_index": entry.index,
						"label": itm.get("name", "Unknown"),
						"item": itm
					})
				character.set_meta("pending_home_stone_index", index)
				send_to_peer(peer_id, {
					"type": "home_stone_select",
					"stone_type": "equipment",
					"options": options,
					"message": "[color=#00FFFF]Choose equipment to send to your Sanctuary:[/color]"
				})
				return
			else:
				send_to_peer(peer_id, {"type": "error", "message": "You have no equipment in your inventory to send home!"})
				return

	# Handle new scribing item types (scroll, map, tome, bestiary)
	if item_type == "scroll":
		# Scroll: apply buff effect
		var scroll_effect = item.get("effect", {})
		var eff_type = scroll_effect.get("type", "buff")
		var stat = scroll_effect.get("stat", "attack")
		var bonus_pct = scroll_effect.get("bonus_pct", 0)
		var dur = scroll_effect.get("duration_battles", 3)
		var amount = scroll_effect.get("amount", 0)

		# Remove item
		if is_consumable:
			character.use_consumable_stack(index)
		else:
			character.remove_item(index)

		if stat == "time_stop":
			character.add_persistent_buff("time_stop", 1, 1)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#9932CC]You read the %s![/color]\n[color=#FFD700]Time bends to your will! Next enemy frozen for one turn![/color]" % item_name
			})
		elif eff_type == "debuff":
			var penalty = scroll_effect.get("penalty_pct", 20)
			character.pending_monster_debuffs.append({"type": "weakness", "value": penalty})
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#9932CC]You read the %s![/color]\n[color=#FFD700]Next enemy's %s reduced by %d%%![/color]" % [item_name, stat.replace("_", " "), penalty]
			})
		elif bonus_pct > 0:
			character.add_persistent_buff(stat, bonus_pct, dur)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#87CEEB]You read the %s![/color]\n[color=#00FF00]+%d%% %s for %d battles![/color]" % [item_name, bonus_pct, stat.replace("_", " "), dur]
			})
		elif amount > 0:
			character.add_persistent_buff(stat, amount, dur)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#87CEEB]You read the %s![/color]\n[color=#00FF00]+%d %s for %d battles![/color]" % [item_name, amount, stat.replace("_", " "), dur]
			})
		send_character_update(peer_id)
		save_character(peer_id)
		return

	if item_type == "area_map":
		# Area map: reveal tiles around player
		var radius = int(item.get("reveal_radius", 50))
		if is_consumable:
			character.use_consumable_stack(index)
		else:
			character.remove_item(index)
		# Mark tiles as discovered (client side will re-request location data)
		var px = character.x
		var py = character.y
		var revealed = 0
		if world_system and world_system.chunk_manager:
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					if dx * dx + dy * dy <= radius * radius:
						var tile = world_system.chunk_manager.get_tile(px + dx, py + dy)
						if not tile.is_empty():
							revealed += 1
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#87CEEB]You study the %s![/color]\n[color=#00FF00]Revealed the area within %d tiles![/color]" % [item_name, radius]
		})
		# Force location update to reveal map
		send_location_update(peer_id)
		send_character_update(peer_id)
		save_character(peer_id)
		return

	if item_type == "spell_tome":
		# Spell tome: permanent +stat (capped at 10 total)
		var stat = item.get("stat", "strength")
		var amount = int(item.get("amount", 1))
		var total_tomes = 0
		for k in character.tome_bonuses:
			total_tomes += int(character.tome_bonuses[k])
		if total_tomes + amount > 10:
			send_to_peer(peer_id, {
				"type": "error",
				"message": "You've already gained %d/10 tome points! Cannot use more." % total_tomes
			})
			return
		if is_consumable:
			character.use_consumable_stack(index)
		else:
			character.remove_item(index)
		character.tome_bonuses[stat] = character.tome_bonuses.get(stat, 0) + amount
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFD700]You study the %s![/color]\n[color=#00FF00][b]PERMANENT BONUS![/b] +%d %s![/color]\n[color=#00FFFF](Tome points used: %d/10)[/color]" % [item_name, amount, stat.capitalize(), total_tomes + amount]
		})
		send_character_update(peer_id)
		save_character(peer_id)
		return

	if item_type == "bestiary_page":
		# Bestiary page: reveal monster HP for a random type the player doesn't know
		if is_consumable:
			character.use_consumable_stack(index)
		else:
			character.remove_item(index)
		# Find a monster type the player doesn't fully know
		var all_monsters = monster_db.get_all_monster_names()
		var unknown = []
		for mname in all_monsters:
			if not character.knows_monster(mname, 9999):
				unknown.append(mname)
		if unknown.is_empty():
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#87CEEB]You read the %s, but you already know all monsters![/color]" % item_name
			})
		else:
			var chosen = unknown[randi() % unknown.size()]
			character.record_monster_kill(chosen, 9999)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#87CEEB]You study the %s![/color]\n[color=#00FF00]You now know the true HP of [color=#FFD700]%s[/color]![/color]" % [item_name, chosen]
			})
		send_character_update(peer_id)
		save_character(peer_id)
		return

	# For consumables with stacking, use the stack function
	var used_item: Dictionary = {}
	if is_consumable:
		used_item = character.use_consumable_stack(index)
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

	# Apply rarity potency multiplier to consumable effects
	var potency_mult = 1.0
	var item_rb = item.get("rarity_bonuses", {})
	if item_rb.has("potency_mult"):
		potency_mult = float(item_rb["potency_mult"])

	# Apply effect
	if effect.has("heal"):
		# Healing potion - hybrid flat + % max HP
		var heal_amount: int
		if effect.get("heal_pct_only", false):
			# Elixir: pure % max HP heal
			var elixir_pct = effect.get("elixir_pct", drop_tables.ELIXIR_HEAL_PCT.get(item_tier, 50))
			heal_amount = int(character.get_total_max_hp() * elixir_pct / 100.0)
		elif tier_data.has("healing"):
			# Tier-based: flat + % max HP
			heal_amount = tier_data.healing + int(character.get_total_max_hp() * tier_data.get("heal_pct", 0) / 100.0)
		else:
			heal_amount = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)
		heal_amount = int(heal_amount * potency_mult)
		var actual_heal = character.heal(heal_amount)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]You use %s and restore %d HP![/color]" % [item_name, actual_heal]
		})
	elif effect.has("mana") or effect.has("stamina") or effect.has("energy") or effect.has("resource"):
		# Resource potion - restores the player's PRIMARY resource based on class path
		var primary_resource = character.get_primary_resource()
		var max_resource: int
		match primary_resource:
			"mana": max_resource = character.get_total_max_mana()
			"stamina": max_resource = character.get_total_max_stamina()
			"energy": max_resource = character.get_total_max_energy()
			_: max_resource = character.get_total_max_mana()

		# Hybrid flat + % max resource
		var resource_amount: int
		if tier_data.has("resource"):
			resource_amount = tier_data.resource + int(max_resource * tier_data.get("resource_pct", 0) / 100.0)
		elif tier_data.has("healing"):
			resource_amount = int(tier_data.healing * 0.6)
		else:
			resource_amount = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)
		resource_amount = int(resource_amount * potency_mult)

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
		# Buff scroll - tier-based values
		var buff_type = effect.buff
		var buff_value: int
		var duration: int

		if effect.get("tier_forcefield", false):
			buff_value = tier_data.get("forcefield_value", 1500)
			duration = tier_data.get("scroll_duration", 1)
		elif effect.get("stat_pct", false):
			var stat_pct = tier_data.get("scroll_stat_pct", 10)
			match buff_type:
				"strength": buff_value = maxi(1, int(character.get_total_strength() * stat_pct / 100.0))
				"defense": buff_value = maxi(1, int(character.get_total_defense() * stat_pct / 100.0))
				"speed": buff_value = maxi(1, int(character.get_total_speed() * stat_pct / 100.0))
				_: buff_value = maxi(1, int(character.get_total_strength() * stat_pct / 100.0))
			duration = tier_data.get("scroll_duration", 1)
		elif effect.get("tier_value", false):
			buff_value = tier_data.get("buff_value", 3)
			duration = tier_data.get("scroll_duration", 1)
		elif tier_data.has("buff_value"):
			if buff_type == "forcefield" and tier_data.has("forcefield_value"):
				buff_value = tier_data.forcefield_value
			else:
				buff_value = tier_data.buff_value
			var base_duration = effect.get("base_duration", 5)
			var duration_per_10 = effect.get("duration_per_10_levels", 1)
			duration = base_duration + (item_level / 10) * duration_per_10
		else:
			buff_value = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)
			var base_duration = effect.get("base_duration", 5)
			var duration_per_10 = effect.get("duration_per_10_levels", 1)
			duration = base_duration + (item_level / 10) * duration_per_10

		var value_suffix = "%%" if buff_type in ["lifesteal", "thorns", "crit_chance"] else ""

		if effect.get("battles", false):
			character.add_persistent_buff(buff_type, buff_value, duration)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FFFF]You use %s! +%d%s %s for %d battle%s![/color]" % [item_name, buff_value, value_suffix, buff_type, duration, "s" if duration != 1 else ""]
			})
		else:
			character.add_buff(buff_type, buff_value, duration)
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#00FFFF]You use %s! +%d%s %s for %d rounds (in combat)![/color]" % [item_name, buff_value, value_suffix, buff_type, duration]
			})
	elif effect.has("essence") or effect.has("gold"):
		# Material Pouch — grants random tier-appropriate materials
		var tier = clampi(int(item_level / 15), 0, 8)
		var ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
		var ore_id = ore_tiers[mini(tier, ore_tiers.size() - 1)]
		var qty = maxi(1, randi_range(2, 4) + tier)
		character.add_crafting_material(ore_id, qty)
		var mat_name = CraftingDatabaseScript.get_material_name(ore_id)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#8B5CF6]You open %s and find %dx %s![/color]" % [item_name, qty, mat_name]
		})
	elif effect.has("gems"):
		# Gem item → Monster Gem material
		var gem_amount = effect.base + (effect.get("per_tier", 1) * max(0, item_tier - 1))
		character.add_crafting_material("monster_gem", gem_amount)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]You appraise %s and receive %d Monster Gem%s![/color]" % [item_name, gem_amount, "s" if gem_amount > 1 else ""]
		})
	elif effect.has("monster_select"):
		# Monster Selection Scroll - let player pick next encounter
		# Save consumed item for cancel restoration (copy full item data so name is preserved)
		var restore_item = used_item.duplicate() if is_consumable else item.duplicate()
		restore_item["quantity"] = 1
		pending_scroll_use[peer_id] = {"item": restore_item, "time": Time.get_ticks_msec()}
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
		var debuff_value: int
		if effect.get("debuff_pct", false) and tier_data.has("scroll_debuff_pct"):
			debuff_value = tier_data.scroll_debuff_pct
		else:
			debuff_value = effect.get("base", 0) + (effect.get("per_level", 0) * item_level)
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
		# Save consumed item for cancel restoration (copy full item data so name is preserved)
		var restore_item = used_item.duplicate() if is_consumable else item.duplicate()
		restore_item["quantity"] = 1
		pending_scroll_use[peer_id] = {"item": restore_item, "time": Time.get_ticks_msec()}
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
		# Cursed Coin - no longer functional (gold system removed)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]The cursed coin crumbles to dust in your hands. Its dark magic has faded.[/color]"
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
	elif effect.has("home_stone"):
		# Home Stone items - send items/companions/eggs to house storage
		var account_id = peers[peer_id].account_id
		var stone_type = effect.home_stone

		# Validate: can't use in combat or dungeons
		if character.in_combat:
			send_to_peer(peer_id, {"type": "error", "message": "Cannot use Home Stones in combat!"})
			return
		if character.in_dungeon:
			send_to_peer(peer_id, {"type": "error", "message": "Cannot use Home Stones in dungeons!"})
			return

		match stone_type:
			"egg":
				# Hatch egg and send companion to house storage (single egg auto-selects)
				if character.incubating_eggs.is_empty():
					send_to_peer(peer_id, {"type": "error", "message": "You have no eggs to send home!"})
					return
				_process_home_stone_egg(peer_id, character, 0, item_name)

			"supplies":
				# Send inventory items to house storage (auto-send for <=10, >10 handled by initial interceptor)
				var sendable = []
				for i in range(character.inventory.size()):
					sendable.append({"index": i, "item": character.inventory[i]})
				if sendable.is_empty():
					send_to_peer(peer_id, {"type": "error", "message": "You have no items to send home!"})
					return
				_process_home_stone_supplies(peer_id, character, sendable, item_name)

			"equipment":
				# Send one inventory equipment item to house storage (single item auto-selects)
				var equipment_items = []
				for ei in range(character.inventory.size()):
					var inv_item = character.inventory[ei]
					if Character.get_item_slot_from_type(inv_item.get("type", "")) != "":
						equipment_items.append({"index": ei, "item": inv_item})
				if equipment_items.is_empty():
					send_to_peer(peer_id, {"type": "error", "message": "You have no equipment in your inventory to send home!"})
					return
				_process_home_stone_equipment(peer_id, character, equipment_items[0].index, item_name)

			"companion":
				# Send choice to player: Register or Store in Kennel
				if character.active_companion.is_empty():
					send_to_peer(peer_id, {"type": "error", "message": "You have no active companion to register!"})
					return
				if character.active_companion.get("house_slot", -1) >= 0:
					send_to_peer(peer_id, {"type": "error", "message": "This companion is already registered to your house!"})
					return
				var house = persistence.get_house(account_id)
				if house == null:
					send_to_peer(peer_id, {"type": "error", "message": "No house found for your account!"})
					return
				var companion_capacity = persistence.get_house_companion_capacity(account_id)
				var kennel_capacity = persistence.get_kennel_capacity(account_id)
				var can_register = house.registered_companions.companions.size() < companion_capacity
				var can_kennel = house.companion_kennel.companions.size() < kennel_capacity
				if not can_register and not can_kennel:
					send_to_peer(peer_id, {"type": "error", "message": "Both registered slots and kennel are full! Upgrade for more space."})
					return
				# Store pending state (item already consumed at this point)
				pending_home_stone_companion[peer_id] = {"item_type": item_type, "item_name": item_name, "item_tier": item_tier}
				send_to_peer(peer_id, {
					"type": "home_stone_companion_choice",
					"companion_name": character.active_companion.get("name", "Companion"),
					"can_register": can_register,
					"can_kennel": can_kennel,
				})

	# Update character data
	send_character_update(peer_id)
	save_character(peer_id)

func _get_equipment_slot_abbr(item_type: String) -> String:
	"""Get short slot abbreviation for equipment display"""
	if "weapon" in item_type: return "[WPN]"
	elif "armor" in item_type: return "[ARM]"
	elif "helm" in item_type: return "[HLM]"
	elif "shield" in item_type: return "[SHD]"
	elif "boots" in item_type: return "[BOT]"
	elif "ring" in item_type: return "[RNG]"
	elif "amulet" in item_type: return "[AMU]"
	return ""

func _get_equipment_affix_summary(item: Dictionary) -> String:
	"""Build a short affix summary like +50ATK, +33DEX, -2WIT"""
	var affixes = item.get("affixes", {})
	if affixes.is_empty():
		return ""
	var parts = []
	var affix_abbrevs = {
		"strength": "STR", "attack": "ATK", "defense": "DEF", "speed": "SPD",
		"intelligence": "INT", "dexterity": "DEX", "wits": "WIT",
		"constitution": "CON", "wisdom": "WIS",
		"max_hp": "HP", "max_mana": "MP", "max_stamina": "STA", "max_energy": "EN",
		"hp_regen": "HP/rnd", "mana_regen": "MP/rnd", "stamina_regen": "STA/rnd", "energy_regen": "EN/rnd",
		"crit_chance": "CRT%", "crit_damage": "CRTD", "lifesteal": "LS%",
		"dodge": "DDG%", "block": "BLK%", "thorns": "THN", "flee_chance": "FLE%"
	}
	# Affixes is a Dictionary: {"strength": 50, "dexterity": 33, "prefix_name": "...", "roll_quality": 50, ...}
	for stat in affixes:
		if stat in ["prefix_name", "suffix_name", "roll_quality", "proc_type", "proc_value", "proc_chance", "proc_name"]:
			continue
		var value = affixes[stat]
		if not (value is int or value is float):
			continue
		var abbr = affix_abbrevs.get(stat, stat.to_upper().left(3))
		var sign = "+" if value >= 0 else ""
		parts.append("%s%d%s" % [sign, int(value), abbr])
	return ", ".join(parts)

func _get_equipment_base_stat(item: Dictionary) -> String:
	"""Get the base stat bonus text like '+51 Atk' for display"""
	var item_type = item.get("type", "")
	var level = item.get("level", 1)
	var rarity = item.get("rarity", "common")
	var rarity_mults = {"common": 1.0, "uncommon": 1.15, "rare": 1.3, "epic": 1.5, "legendary": 1.75, "artifact": 2.0}
	var rarity_mult = rarity_mults.get(rarity, 1.0)
	var base = int(level * rarity_mult)
	if "weapon" in item_type:
		return "+%d Atk" % (base * 2)
	elif "armor" in item_type:
		return "+%d Def" % (base * 2)
	elif "helm" in item_type:
		return "+%d Def" % base
	elif "shield" in item_type:
		return "+%d Def" % int(base * 1.5)
	elif "ring" in item_type:
		return "+%d Atk" % int(base * 0.5)
	elif "amulet" in item_type:
		return "+%d Resource" % (base * 2)
	elif "boots" in item_type:
		return "+%d Spd" % base
	return ""

func _home_stone_pre_validate(peer_id: int, character, stone_type: String) -> bool:
	"""Pre-validate home stone usage (combat/dungeon check + house storage check)"""
	if character.in_combat:
		send_to_peer(peer_id, {"type": "error", "message": "Cannot use Home Stones in combat!"})
		return false
	if character.in_dungeon:
		send_to_peer(peer_id, {"type": "error", "message": "Cannot use Home Stones in dungeons!"})
		return false
	var account_id = peers[peer_id].account_id
	var house = persistence.get_house(account_id)
	if house == null:
		send_to_peer(peer_id, {"type": "error", "message": "No house found for your account!"})
		return false
	var storage_capacity = persistence.get_house_storage_capacity(account_id)
	if house.storage.items.size() >= storage_capacity:
		send_to_peer(peer_id, {"type": "error", "message": "House storage is full!"})
		return false
	return true

func _process_home_stone_egg(peer_id: int, character, egg_index: int, item_name: String):
	"""Process hatching an egg and sending the companion to house kennel via Home Stone"""
	var account_id = peers[peer_id].account_id
	if egg_index < 0 or egg_index >= character.incubating_eggs.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid egg selection!"})
		return
	var egg = character.incubating_eggs[egg_index]
	var house = persistence.get_house(account_id)
	if house == null:
		send_to_peer(peer_id, {"type": "error", "message": "No house found for your account!"})
		return
	var kennel_capacity = persistence.get_kennel_capacity(account_id)
	if house.companion_kennel.companions.size() >= kennel_capacity:
		send_to_peer(peer_id, {"type": "error", "message": "Kennel is full! Upgrade for more slots."})
		return
	# Remove egg from character
	character.incubating_eggs.remove_at(egg_index)
	# Hatch the egg into a companion (matching normal _hatch_egg format)
	var companion = {
		"id": "companion_" + egg.monster_type.to_lower().replace(" ", "_") + "_" + str(randi()),
		"monster_type": egg.monster_type,
		"name": egg.get("companion_name", egg.get("name", "Unknown")),
		"tier": egg.get("tier", 1),
		"sub_tier": egg.get("sub_tier", 1),
		"bonuses": egg.bonuses.duplicate() if egg.has("bonuses") else {},
		"obtained_at": int(Time.get_unix_time_from_system()),
		"battles_fought": 0,
		"variant": egg.get("variant", "Normal"),
		"variant_color": egg.get("variant_color", "#FFFFFF"),
		"variant_color2": egg.get("variant_color2", ""),
		"variant_pattern": egg.get("variant_pattern", "solid"),
		"level": 1,
		"xp": 0
	}
	persistence.add_companion_to_kennel(account_id, companion)
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]The %s glows and your %s egg hatches in a flash of light![/color]\n[color=#A335EE]%s has been sent to your Sanctuary's Kennel![/color]" % [item_name, egg.get("monster_type", "Unknown"), companion.name]
	})

func _process_home_stone_supplies(peer_id: int, character, items_to_send: Array, item_name: String):
	"""Process sending inventory items to house storage via Home Stone"""
	var account_id = peers[peer_id].account_id
	var house = persistence.get_house(account_id)
	if house == null:
		send_to_peer(peer_id, {"type": "error", "message": "No house found for your account!"})
		return
	var storage_capacity = persistence.get_house_storage_capacity(account_id)
	var available_space = storage_capacity - house.storage.items.size()
	if available_space <= 0:
		send_to_peer(peer_id, {"type": "error", "message": "House storage is full!"})
		return
	# Send up to 10 items (or available space, whichever is less)
	var to_send = min(10, min(items_to_send.size(), available_space))
	var indices_to_remove = []  # Indices where the entire item is removed
	var indices_to_reduce = {}  # Index → qty to subtract (for partial stack sends)
	var sent_count = 0
	for i in range(to_send):
		var entry = items_to_send[i]
		var send_qty = int(entry.get("send_qty", entry.item.get("quantity", 1)))
		var item_qty = int(entry.item.get("quantity", 1))
		# Create a copy of the item with the send quantity
		var item_to_store = entry.item.duplicate(true)
		item_to_store["quantity"] = send_qty
		persistence.add_item_to_house_storage(account_id, item_to_store)
		if send_qty >= item_qty:
			# Sending entire stack — remove from inventory
			indices_to_remove.append(entry.index)
		else:
			# Partial stack — reduce quantity in inventory
			indices_to_reduce[entry.index] = send_qty
		sent_count += 1
	# Reduce partial stacks first (doesn't affect indices)
	for idx in indices_to_reduce:
		var inv_item = character.inventory[idx]
		inv_item["quantity"] = int(inv_item.get("quantity", 1)) - indices_to_reduce[idx]
	# Remove full items in reverse order to maintain indices
	indices_to_remove.sort()
	indices_to_remove.reverse()
	for idx in indices_to_remove:
		character.inventory.remove_at(idx)
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]The %s glows and %d supplies vanish in a flash of light![/color]\n[color=#00FF00]Items safely stored at your house![/color]" % [item_name, sent_count]
	})

func _process_home_stone_equipment(peer_id: int, character, inv_index: int, item_name: String):
	"""Process sending inventory equipment item to house storage via Home Stone"""
	var account_id = peers[peer_id].account_id
	if inv_index < 0 or inv_index >= character.inventory.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid item index!"})
		return
	var equip_item = character.inventory[inv_index]
	if Character.get_item_slot_from_type(equip_item.get("type", "")) == "":
		send_to_peer(peer_id, {"type": "error", "message": "That item is not equipment!"})
		return
	var house = persistence.get_house(account_id)
	if house == null:
		send_to_peer(peer_id, {"type": "error", "message": "No house found for your account!"})
		return
	var storage_capacity = persistence.get_house_storage_capacity(account_id)
	if house.storage.items.size() >= storage_capacity:
		send_to_peer(peer_id, {"type": "error", "message": "House storage is full!"})
		return
	persistence.add_item_to_house_storage(account_id, equip_item)
	character.inventory.remove_at(inv_index)
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]The %s glows and your %s vanishes in a flash of light![/color]\n[color=#00FF00]Equipment safely stored at your house![/color]" % [item_name, equip_item.get("name", "equipment")]
	})

func handle_home_stone_select(peer_id: int, message: Dictionary):
	"""Handle player selecting a target for Home Stone"""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var stone_type = message.get("stone_type", "")
	var selection_index = message.get("selection_index", -1)

	# Retrieve pending item index
	if not character.has_meta("pending_home_stone_index"):
		send_to_peer(peer_id, {"type": "error", "message": "No Home Stone in use."})
		return
	var item_index = character.get_meta("pending_home_stone_index")
	character.remove_meta("pending_home_stone_index")

	# Validate item still exists and is a home stone
	if item_index < 0 or item_index >= character.inventory.size():
		send_to_peer(peer_id, {"type": "error", "message": "Home Stone no longer in inventory."})
		return
	var item = character.inventory[item_index]
	var item_name = item.get("name", "Home Stone")
	var item_type = item.get("type", "")
	if not item_type.begins_with("home_stone_"):
		send_to_peer(peer_id, {"type": "error", "message": "Item is not a Home Stone."})
		return

	# Process selection
	match stone_type:
		"egg":
			_process_home_stone_egg(peer_id, character, selection_index, item_name)
		"equipment":
			# Resolve inventory index from selection index
			var equipment_items = []
			for ei in range(character.inventory.size()):
				var inv_item = character.inventory[ei]
				if Character.get_item_slot_from_type(inv_item.get("type", "")) != "":
					equipment_items.append({"index": ei, "item": inv_item})
			if selection_index < 0 or selection_index >= equipment_items.size():
				send_to_peer(peer_id, {"type": "error", "message": "Invalid equipment selection."})
				return
			var inv_index = equipment_items[selection_index].index
			_process_home_stone_equipment(peer_id, character, inv_index, item_name)
		"supplies":
			# Multi-select: client sends selection_indices array + optional quantities
			var selection_indices = message.get("selection_indices", [])
			var selection_quantities = message.get("selection_quantities", {})
			if selection_indices.is_empty():
				send_to_peer(peer_id, {"type": "error", "message": "No items selected."})
				return
			# Rebuild inventory list to resolve option indices to inventory indices
			var all_items = []
			for i in range(character.inventory.size()):
				all_items.append({"index": i, "item": character.inventory[i]})
			# Resolve selected option indices to actual inventory entries with quantities
			var selected_items = []
			for opt_idx in selection_indices:
				var idx = int(opt_idx)
				if idx >= 0 and idx < all_items.size():
					var entry = all_items[idx].duplicate(true)
					# Get requested quantity (default to full stack)
					var send_qty = int(selection_quantities.get(str(idx), entry.item.get("quantity", 1)))
					var max_qty = int(entry.item.get("quantity", 1))
					entry["send_qty"] = clampi(send_qty, 1, max_qty)
					selected_items.append(entry)
			if selected_items.is_empty():
				send_to_peer(peer_id, {"type": "error", "message": "Invalid selection."})
				return
			# Limit to 10
			if selected_items.size() > 10:
				selected_items = selected_items.slice(0, 10)
			_process_home_stone_supplies(peer_id, character, selected_items, item_name)
		_:
			send_to_peer(peer_id, {"type": "error", "message": "Invalid Home Stone type."})
			return

	# Consume the Home Stone item
	character.use_consumable_stack(item_index)
	send_character_update(peer_id)
	save_character(peer_id)

func handle_home_stone_cancel(peer_id: int, _message: Dictionary):
	"""Handle player cancelling Home Stone selection"""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	if character.has_meta("pending_home_stone_index"):
		character.remove_meta("pending_home_stone_index")
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#808080]Home Stone use cancelled.[/color]"
	})
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

	# Scroll successfully used - clear pending (item stays consumed)
	pending_scroll_use.erase(peer_id)

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

	var valid_abilities = ["weapon_master", "shield_bearer", "gem_bearer", "arcane_hoarder", "cunning_prey", "warrior_hoarder"]
	if ability not in valid_abilities:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid ability selection"
		})
		return

	# Set the target farming ability on character
	character.target_farm_ability = ability
	character.target_farm_remaining = encounters

	# Scroll successfully used - clear pending (item stays consumed)
	pending_scroll_use.erase(peer_id)

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

func handle_scroll_cancel(peer_id: int):
	"""Handle player cancelling a scroll selection (Monster Select or Target Farm).
	Restores the consumed scroll back to inventory."""
	if not characters.has(peer_id):
		return

	if not pending_scroll_use.has(peer_id):
		return

	var character = characters[peer_id]
	var pending = pending_scroll_use[peer_id]
	var item = pending.get("item", {})

	# Restore the scroll to inventory
	if not item.is_empty():
		character.add_item(item)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#808080]The scroll's magic fades unused. It has been returned to your inventory.[/color]"
		})
	pending_scroll_use.erase(peer_id)
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

	var item = inventory[index]
	if item.get("locked", false):
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]That item is locked! Unlock it first.[/color]"
		})
		return

	var item_name = item.get("name", "Unknown")
	# For consumable stacks, discard one at a time
	if item.get("is_consumable", false) and item.get("quantity", 1) > 1:
		item["quantity"] -= 1
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]You discard 1x %s. (%d remaining)[/color]" % [item_name, item.quantity]
		})
	else:
		character.remove_item(index)
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]You discard %s.[/color]" % item_name
		})

	send_character_update(peer_id)

func handle_inventory_lock(peer_id: int, message: Dictionary):
	"""Handle toggling item lock status"""
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
	var was_locked = item.get("locked", false)
	item["locked"] = not was_locked

	var status = "locked" if item["locked"] else "unlocked"
	var color = "#FF4444" if item["locked"] else "#00FF00"
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=%s]%s has been %s.[/color]" % [color, item.get("name", "Unknown"), status]
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

		# Never salvage title items, locked items, tools, runes, or structures
		if item.get("is_title_item", false):
			continue
		if item.get("locked", false):
			continue
		if item_type == "tool" or item_type == "rune" or item_type == "structure" or item_type == "treasure_chest":
			continue

		# Check if item is a consumable (use item flag first, then type check as fallback)
		var is_consumable = item.get("is_consumable", false) or _is_consumable_type(item_type)

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
			# Calculate salvage materials using drop_tables
			var salvage_result = drop_tables.get_salvage_value(item)
			var sal_mats = salvage_result.get("materials", {})
			for mat_id in sal_mats:
				if not materials_gained.has(mat_id):
					materials_gained[mat_id] = 0
				materials_gained[mat_id] += sal_mats[mat_id]

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

	# Add salvage materials
	for mat_id in materials_gained:
		character.add_crafting_material(mat_id, materials_gained[mat_id])

	# Build result message
	var mat_strings = []
	for mat_id in materials_gained:
		var mat_name = CraftingDatabaseScript.get_material_name(mat_id)
		mat_strings.append("%dx %s" % [materials_gained[mat_id], mat_name])
	var result_msg = "[color=#AA66FF]Salvaged %d items![/color]" % salvaged_count
	if not mat_strings.is_empty():
		result_msg += "\n[color=#00FF00]Materials: %s[/color]" % ", ".join(mat_strings)

	send_to_peer(peer_id, {
		"type": "text",
		"message": result_msg
	})

	save_character(peer_id)
	send_character_update(peer_id)

func handle_auto_salvage_settings(peer_id: int, message: Dictionary):
	"""Handle auto-salvage settings change"""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var max_rarity = int(message.get("max_rarity", 0))
	max_rarity = clampi(max_rarity, 0, 5)

	if max_rarity == 0:
		character.auto_salvage_enabled = false
		character.auto_salvage_max_rarity = 0
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Auto-salvage disabled.[/color]"})
	else:
		character.auto_salvage_enabled = true
		character.auto_salvage_max_rarity = max_rarity
		var rarity_names = {1: "Common", 2: "Uncommon", 3: "Rare", 4: "Epic", 5: "Legendary"}
		send_to_peer(peer_id, {"type": "text", "message": "[color=#AA66FF]Auto-salvage enabled: will salvage %s and below on pickup.[/color]" % rarity_names[max_rarity]})

	save_character(peer_id)
	send_character_update(peer_id)

func _should_auto_salvage_item(peer_id: int, item: Dictionary) -> bool:
	"""Check if a newly obtained item should be immediately auto-salvaged.
	Returns true if the item matches auto-salvage criteria."""
	if not characters.has(peer_id):
		return false
	var character = characters[peer_id]
	if not character.auto_salvage_enabled or character.auto_salvage_max_rarity <= 0:
		return false
	# Don't auto-salvage consumables, locked items, title items, tools, or runes
	if item.get("is_consumable", false) or _is_consumable_type(item.get("type", "")):
		return false
	if item.get("locked", false) or item.get("is_title_item", false):
		return false
	var itype = item.get("type", "")
	if itype == "tool" or itype == "rune" or itype == "structure" or itype == "treasure_chest":
		return false

	var rarity = item.get("rarity", "common")
	var rarity_order = ["common", "uncommon", "rare", "epic", "legendary"]
	var max_idx = character.auto_salvage_max_rarity
	var allowed_rarities = rarity_order.slice(0, max_idx)

	# Item must be in the salvageable rarity range
	if rarity not in allowed_rarities:
		return false

	# Check affix filter — selected affixes are KEPT (protected from salvage)
	if character.auto_salvage_affixes.size() > 0:
		var affixes = item.get("affixes", {})
		var prefix = affixes.get("prefix_name", "")
		var suffix = affixes.get("suffix_name", "")
		for affix_name in character.auto_salvage_affixes:
			if (prefix != "" and prefix == affix_name) or (suffix != "" and suffix == affix_name):
				return false  # Has a kept affix — don't salvage

	return true

func _try_auto_salvage(peer_id: int) -> bool:
	"""Try to auto-salvage an item to make room. Returns true if space was made.
	Checks both rarity-based and affix-based filters."""
	if not characters.has(peer_id):
		return false
	var character = characters[peer_id]

	var has_rarity_filter = character.auto_salvage_enabled and character.auto_salvage_max_rarity > 0
	var has_affix_filter = character.auto_salvage_affixes.size() > 0

	if not has_rarity_filter and not has_affix_filter:
		return false

	var rarity_order = ["common", "uncommon", "rare"]
	var max_idx = character.auto_salvage_max_rarity  # 1=common, 2=uncommon, 3=rare
	var allowed_rarities = rarity_order.slice(0, max_idx) if has_rarity_filter else []

	# Find lowest rarity non-equipped, non-locked item to salvage
	# Items with a KEPT affix (in auto_salvage_affixes) are protected from salvage
	var best_idx = -1
	var best_rarity_rank = 999
	var best_level = 999999

	for i in range(character.inventory.size()):
		var item = character.inventory[i]
		if item.get("locked", false):
			continue
		if item.get("is_title_item", false):
			continue
		if item.get("is_consumable", false) or _is_consumable_type(item.get("type", "")):
			continue
		var itype = item.get("type", "")
		if itype == "tool" or itype == "rune" or itype == "structure":
			continue

		var rarity = item.get("rarity", "common")
		var rarity_match = rarity in allowed_rarities

		# Check affix filter — selected affixes are KEPT (protected from salvage)
		if has_affix_filter:
			var affixes = item.get("affixes", {})
			var prefix = affixes.get("prefix_name", "")
			var suffix = affixes.get("suffix_name", "")
			var has_kept_affix = false
			for affix_name in character.auto_salvage_affixes:
				if (prefix != "" and prefix == affix_name) or (suffix != "" and suffix == affix_name):
					has_kept_affix = true
					break
			if has_kept_affix:
				continue  # Skip — this item is protected

		if not rarity_match:
			continue

		var rarity_rank = rarity_order.find(rarity) if rarity_order.has(rarity) else 999
		var item_level = item.get("level", 1)
		# Prefer lowest rarity first, then lowest level
		if rarity_rank < best_rarity_rank or (rarity_rank == best_rarity_rank and item_level < best_level):
			best_idx = i
			best_rarity_rank = rarity_rank
			best_level = item_level

	if best_idx < 0:
		return false

	# Salvage the item → materials
	var item = character.inventory[best_idx]
	var salvage_result = drop_tables.get_salvage_value(item)
	var sal_mats = salvage_result.get("materials", {})
	character.remove_item(best_idx)
	for _mid in sal_mats:
		character.add_crafting_material(_mid, sal_mats[_mid])
	var sal_parts = []
	for _mid2 in sal_mats:
		sal_parts.append("%dx %s" % [sal_mats[_mid2], CraftingDatabaseScript.get_material_name(_mid2)])
	send_to_peer(peer_id, {"type": "text", "message": "[color=#AA66FF]Auto-salvaged %s → %s[/color]" % [item.get("name", "item"), ", ".join(sal_parts) if not sal_parts.is_empty() else "nothing"]})
	return true

func handle_auto_salvage_affix_settings(peer_id: int, message: Dictionary):
	"""Handle auto-salvage affix filter settings"""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var affixes = message.get("affixes", [])

	# Validate: max 5 affixes per stat category, must be valid affix names
	var valid_affix_names = {}  # name -> stat
	for prefix in drop_tables.PREFIX_POOL:
		valid_affix_names[prefix.name] = prefix.get("stat", "")
	for suffix in drop_tables.SUFFIX_POOL:
		valid_affix_names[suffix.name] = suffix.get("stat", "")
	for proc in drop_tables.PROC_SUFFIX_POOL:
		valid_affix_names[proc.name] = "proc_" + proc.get("proc_type", "")

	var validated = []
	var per_category_count = {}  # stat -> count
	for affix in affixes:
		if affix in valid_affix_names and affix not in validated:
			var stat = valid_affix_names[affix]
			var count = per_category_count.get(stat, 0)
			if count < 5:
				validated.append(affix)
				per_category_count[stat] = count + 1

	character.auto_salvage_affixes = validated
	# Auto-enable salvage if affix filter is set
	if validated.size() > 0 and not character.auto_salvage_enabled:
		character.auto_salvage_enabled = true

	if validated.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Affix auto-salvage filter cleared.[/color]"})
	else:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#AA66FF]Affix auto-salvage filter set: %s[/color]" % ", ".join(validated)})

	save_character(peer_id)
	send_character_update(peer_id)

func send_character_update(peer_id: int):
	"""Send character data update to client"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var char_dict = character.to_dict()
	# Add egg capacity from house upgrades
	var egg_cap = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
	char_dict["egg_capacity"] = egg_cap
	# Add valor from account-level storage
	char_dict["valor"] = persistence.get_valor(peers[peer_id].account_id) if peers.has(peer_id) else 0
	# Projected leaderboard rank — where would this character place if they died now?
	char_dict["projected_rank"] = _calculate_projected_rank(character)
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

func _calculate_projected_rank(character: Character) -> int:
	"""Calculate where this character would rank on the leaderboard if they died now.
	Leaderboard is sorted by experience descending. Returns 1-based rank, 0 if off-board (>100)."""
	var entries = persistence.leaderboard_data.get("entries", [])
	if entries.is_empty():
		return 1
	var xp = character.experience
	var rank = 1
	for entry in entries:
		if xp >= entry.get("experience", 0):
			return rank
		rank += 1
	if rank > 100:
		return 0
	return rank

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
	if "upgrade" in merchant.services:
		services_text.append("[W] Upgrade equipment")
	if "gamble" in merchant.services:
		services_text.append("[E] Gamble")
	services_text.append("[Space] Leave")

	# Build greeting with destination info and voice text
	var greeting = "[color=#FFD700]A %s approaches you![/color]\n" % merchant.name
	var merchant_hash = merchant.get("hash", 0)
	var voice_text = _get_merchant_voice(merchant_hash)
	if merchant.has("destination") and merchant.destination != "":
		greeting += "[color=#808080]\"I'm headed to %s, then on to %s. Care to trade?\"[/color]\n\n" % [merchant.destination, merchant.get("next_destination", "parts unknown")]
	else:
		greeting += voice_text + "\n\n"

	send_to_peer(peer_id, {
		"type": "merchant_start",
		"merchant": merchant,
		"message": greeting + "\n".join(services_text)
	})

func _get_merchant_voice(merchant_hash: int) -> String:
	"""Get a voice line for a merchant based on their hash. Trader 21 (art index 20) gets a unique line."""
	# 21 traders total, art_index = abs(hash) % 21
	var art_index = abs(merchant_hash) % 21
	if art_index == 20:
		return "[color=#808080]*coughs and chokes on his own spit* \"Ah-- *hack* --excuse me! I swear I'm a professional. Now, what'll it be?\"[/color]"
	var voices = [
		"\"Greetings, traveler! Care to do business?\"",
		"\"Fine wares for a fine adventurer!\"",
		"\"You look like someone who appreciates quality goods.\"",
		"\"Step right up! Best prices this side of the realm.\"",
		"\"Ah, a customer! Let me show you what I've got.\"",
		"\"Looking to buy or sell? Either way, you've come to the right place.\"",
		"\"I've traveled far and wide to bring you these goods.\"",
		"\"Don't be shy! Everything's for sale... for the right price.\"",
	]
	var voice_index = abs(merchant_hash / 3) % voices.size()
	return "[color=#808080]%s[/color]" % voices[voice_index]

func handle_merchant_sell(peer_id: int, _message: Dictionary):
	"""Merchant sell removed — redirect to Open Market"""
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]Items can only be sold via the Open Market at trading posts.[/color]"
	})

func _is_consumable_type(item_type: String) -> bool:
	"""Check if an item type is a consumable (potion, scroll, etc.)"""
	return (item_type.begins_with("potion_") or item_type.begins_with("mana_") or
			item_type.begins_with("stamina_") or item_type.begins_with("energy_") or
			item_type.begins_with("scroll_") or item_type.begins_with("tome_") or
			item_type.begins_with("elixir_") or
			item_type == "essence_pouch" or item_type.begins_with("gem_") or
			item_type == "mysterious_box" or item_type == "cursed_coin" or
			item_type == "soul_gem" or item_type.begins_with("home_stone_") or
			item_type == "health_potion" or item_type == "mana_potion" or
			item_type == "stamina_potion" or item_type == "energy_potion" or
			item_type == "elixir" or
			item_type == "scroll" or item_type == "area_map" or
			item_type == "spell_tome" or item_type == "bestiary_page")

func handle_merchant_sell_all(_peer_id: int):
	"""Merchant sell-all removed — redirect to Open Market"""
	send_to_peer(_peer_id, {
		"type": "text",
		"message": "[color=#FFD700]Items can only be sold via the Open Market at trading posts.[/color]"
	})

func handle_merchant_sell_gems(_peer_id: int, _message: Dictionary):
	"""Gem selling removed — gems cannot be sold"""
	send_to_peer(_peer_id, {
		"type": "text",
		"message": "[color=#FF4444]Gems cannot be sold.[/color]"
	})

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
	var gamble_account_id = peers[peer_id].account_id
	var current_valor = persistence.get_valor(gamble_account_id)
	var bet_amount = message.get("amount", 1)

	# Minimum bet scales with level
	var min_bet = maxi(1, character.level)
	var max_bet = current_valor / 4

	if max_bet < min_bet:
		send_to_peer(peer_id, {
			"type": "gamble_result",
			"success": false,
			"message": "[color=#FF4444]You need at least %d valor to gamble at your level![/color]" % (min_bet * 4),
			"gold": 0,
			"valor": current_valor
		})
		return

	bet_amount = clampi(bet_amount, min_bet, max_bet)

	if current_valor < bet_amount or bet_amount < min_bet:
		send_to_peer(peer_id, {
			"type": "gamble_result",
			"success": false,
			"message": "[color=#FF4444]Invalid bet! Min: %d, Max: %d valor[/color]" % [min_bet, max_bet],
			"gold": 0,
			"valor": current_valor
		})
		return

	# Simulate dice rolls for both merchant and player
	# House edge: merchant gets a hidden +1 bonus (reduced from +2 for better player odds)
	var merchant_dice = [randi() % 6 + 1, randi() % 6 + 1, randi() % 6 + 1]
	var player_dice = [randi() % 6 + 1, randi() % 6 + 1, randi() % 6 + 1]
	var merchant_total = merchant_dice[0] + merchant_dice[1] + merchant_dice[2]
	var player_total = player_dice[0] + player_dice[1] + player_dice[2]

	# House edge - merchant effectively rolls 1 higher (hidden from player)
	var adjusted_merchant_total = merchant_total + 1

	# Player gets +1 bonus if they roll any pair (encourages gambling, ~42% chance)
	var has_pair = (player_dice[0] == player_dice[1] or player_dice[1] == player_dice[2] or player_dice[0] == player_dice[2])
	if has_pair:
		player_total += 1

	# Build dice display (shows raw dice, not the house edge)
	var dice_msg = "[color=#FF4444]Merchant:[/color] [%d][%d][%d] = %d\n" % [merchant_dice[0], merchant_dice[1], merchant_dice[2], merchant_total]
	dice_msg += "[color=#00FF00]You:[/color] [%d][%d][%d] = %d\n" % [player_dice[0], player_dice[1], player_dice[2], player_total]

	var result_msg = ""
	var won = false
	var item_won = null

	# Check for triple 6s first - JACKPOT! (rare big win, ~0.46% chance)
	if player_dice[0] == 6 and player_dice[1] == 6 and player_dice[2] == 6:
		# Triple 6s - guaranteed item or massive valor!
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
			persistence.add_valor(gamble_account_id, winnings - bet_amount)
			result_msg = "[color=#FFD700]★★★ TRIPLE SIXES! You win %d valor! ★★★[/color]" % winnings
		won = true
	# Check for any triple (other than 6s) - nice bonus (~2.3% chance)
	elif player_dice[0] == player_dice[1] and player_dice[1] == player_dice[2]:
		var winnings = bet_amount * 3
		persistence.add_valor(gamble_account_id, winnings - bet_amount)
		result_msg = "[color=#FFD700]TRIPLE %ds! Lucky roll! You win %d valor![/color]" % [player_dice[0], winnings]
		won = true
	else:
		# Normal outcome based on dice difference (vs adjusted merchant total)
		var diff = player_total - adjusted_merchant_total

		if diff < -6:
			# Crushing loss - lose full bet
			persistence.spend_valor(gamble_account_id, bet_amount)
			result_msg = "[color=#FF4444]Crushing defeat! You lose %d valor.[/color]" % bet_amount
		elif diff < -2:
			# Bad loss - lose 75% bet
			var loss = int(bet_amount * 0.75)
			persistence.spend_valor(gamble_account_id, loss)
			result_msg = "[color=#FF4444]The merchant outrolls you! You lose %d valor.[/color]" % loss
		elif diff < 0:
			# Small loss - lose half bet
			var loss = int(bet_amount * 0.5)
			persistence.spend_valor(gamble_account_id, loss)
			result_msg = "[color=#FF4444]Close, but not enough. You lose %d valor.[/color]" % loss
		elif diff == 0:
			# Near-tie - lose small ante (house always wins ties)
			var loss = int(bet_amount * 0.25)
			persistence.spend_valor(gamble_account_id, loss)
			result_msg = "[color=#FFAA00]Too close to call... house takes a small cut: %d valor.[/color]" % loss
		elif diff <= 3:
			# Small win - win 1.25x (net +25%)
			var winnings = int(bet_amount * 1.25)
			persistence.add_valor(gamble_account_id, winnings - bet_amount)
			result_msg = "[color=#00FF00]Victory! You win %d valor![/color]" % winnings
			won = true
		elif diff <= 6:
			# Good win - win 1.75x
			var winnings = int(bet_amount * 1.75)
			persistence.add_valor(gamble_account_id, winnings - bet_amount)
			result_msg = "[color=#00FF00]Strong roll! You win %d valor![/color]" % winnings
			won = true
		else:
			# Dominating win - win 2.5x
			var winnings = int(bet_amount * 2.5)
			persistence.add_valor(gamble_account_id, winnings - bet_amount)
			result_msg = "[color=#FFD700]DOMINATING! You win %d valor![/color]" % winnings
			won = true

	# Bonus: Any winning roll has a 10% chance to also win a random item
	if won and item_won == null and randf() < 0.10 and character.can_add_item():
		var item_level = max(1, character.level + randi() % 15)
		var tier = _level_to_tier(item_level)
		var bonus_items = drop_tables.roll_drops(tier, 50, item_level)  # Lower quality than jackpot
		if bonus_items.size() > 0:
			character.add_item(bonus_items[0])
			item_won = bonus_items[0]
			var rarity_color = _get_rarity_color(bonus_items[0].get("rarity", "common"))
			result_msg += "\n[color=#FFD700]BONUS![/color] [color=%s]You also found: %s![/color]" % [rarity_color, bonus_items[0].get("name", "Unknown")]

	var updated_valor = persistence.get_valor(gamble_account_id)
	# Send gamble result with prompt to continue
	send_to_peer(peer_id, {
		"type": "gamble_result",
		"success": true,
		"dice_message": dice_msg,
		"result_message": result_msg,
		"won": won,
		"gold": 0,
		"valor": updated_valor,
		"min_bet": min_bet,
		"max_bet": updated_valor / 4,
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
	"""Calculate recharge cost in valor based on player level"""
	return 5 + player_level

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

	# Check if player has enough valor
	var recharge_account_id = peers[peer_id].account_id
	if not persistence.spend_valor(recharge_account_id, cost):
		send_to_peer(peer_id, {
			"type": "merchant_message",
			"message": "[color=#FF0000]\"You don't have enough valor! Recharge costs %d valor.\"[/color]" % cost
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

	# Restore resources (valor already deducted)
	character.current_hp = character.get_total_max_hp()
	character.current_mana = character.get_total_max_mana()
	character.current_stamina = character.get_total_max_stamina()
	character.current_energy = character.get_total_max_energy()
	restored.append("HP and resources restored")

	send_to_peer(peer_id, {
		"type": "merchant_message",
		"message": "[color=#00FF00]The merchant provides you with a revitalizing tonic![/color]\n[color=#00FF00]%s! (-%d valor)[/color]" % [", ".join(restored).capitalize(), cost]
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
		"gold": character.gold,
		"valor": persistence.get_valor(peers[peer_id].account_id) if peers.has(peer_id) else 0
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
	var max_attempts = item_count * 10  # Increased to reduce empty inventories

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

	# Fallback: If merchant has no items after all attempts, generate guaranteed fallback items
	# This prevents the frustrating "merchant has nothing to sell" situation
	if items.size() == 0:
		var fallback_count = 2 + rng.randi() % 2  # 2-3 fallback items
		for _i in range(fallback_count):
			var fallback_level = maxi(1, player_level + rng.randi_range(-3, 3))
			var fallback_item: Dictionary

			# Generate appropriate fallback based on specialty
			if specialty == "weapons" or specialty == "warrior_affixes" or specialty == "dps_affixes":
				fallback_item = drop_tables.generate_fallback_item("weapon", fallback_level)
			elif specialty == "armor" or specialty == "tank_affixes":
				fallback_item = drop_tables.generate_fallback_item("armor", fallback_level)
			elif specialty == "jewelry" or specialty == "mage_affixes" or specialty == "trickster_affixes":
				fallback_item = drop_tables.generate_fallback_item("ring", fallback_level)
			elif specialty == "potions":
				fallback_item = drop_tables.generate_fallback_item("potion", fallback_level)
			else:
				# General fallback - mix of equipment
				var fallback_types = ["weapon", "armor", "potion"]
				fallback_item = drop_tables.generate_fallback_item(fallback_types[rng.randi() % fallback_types.size()], fallback_level)

			if not fallback_item.is_empty():
				var markup = 2.0  # Standard markup for fallback items
				fallback_item["shop_price"] = int(fallback_item.get("value", 100) * markup)
				items.append(fallback_item)

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

func handle_merchant_buy(peer_id: int, _message: Dictionary):
	"""Merchant purchase removed — redirect to Open Market"""
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]Items can only be purchased via the Open Market at trading posts.[/color]"
	})

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
		"valor": persistence.get_valor(peers[peer_id].account_id) if peers.has(peer_id) else 0
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

# ===== HOUSE (SANCTUARY) HANDLERS =====

func handle_house_request(peer_id: int):
	"""Send house data to authenticated user"""
	if not peers.has(peer_id) or not peers[peer_id].authenticated:
		send_to_peer(peer_id, {"type": "error", "message": "Not authenticated."})
		return

	var account_id = peers[peer_id].account_id
	var house = persistence.get_house(account_id)

	# Include upgrade definitions so client knows costs
	send_to_peer(peer_id, {
		"type": "house_data",
		"house": house,
		"upgrade_costs": persistence.HOUSE_UPGRADES
	})

func handle_house_upgrade(peer_id: int, message: Dictionary):
	"""Handle house upgrade purchase"""
	if not peers.has(peer_id) or not peers[peer_id].authenticated:
		send_to_peer(peer_id, {"type": "error", "message": "Not authenticated."})
		return

	var account_id = peers[peer_id].account_id
	var upgrade_id = message.get("upgrade_id", "")

	var result = persistence.purchase_house_upgrade(account_id, upgrade_id)

	if result.success:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]%s[/color]" % result.message
		})
		# Send updated house data
		var house = persistence.get_house(account_id)
		send_to_peer(peer_id, {
			"type": "house_update",
			"house": house,
			"upgrade_costs": persistence.HOUSE_UPGRADES
		})
	else:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF0000]%s[/color]" % result.message
		})

func handle_house_discard_item(peer_id: int, message: Dictionary):
	"""Handle discarding an item from house storage"""
	if not peers.has(peer_id) or not peers[peer_id].authenticated:
		send_to_peer(peer_id, {"type": "error", "message": "Not authenticated."})
		return

	var account_id = peers[peer_id].account_id
	var item_index = message.get("index", -1)

	var house = persistence.get_house(account_id)
	if house == null:
		send_to_peer(peer_id, {"type": "error", "message": "No house found."})
		return

	if item_index < 0 or item_index >= house.storage.items.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid item index."})
		return

	var item = house.storage.items[item_index]
	var item_name = item.get("name", item.get("monster_type", "Unknown Item"))

	# Remove the item
	persistence.remove_item_from_house_storage(account_id, item_index)

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF6666]%s has been discarded from your Sanctuary storage.[/color]" % item_name
	})

	# Send updated house data
	var updated_house = persistence.get_house(account_id)
	send_to_peer(peer_id, {
		"type": "house_update",
		"house": updated_house,
		"upgrade_costs": persistence.HOUSE_UPGRADES
	})

func _withdraw_house_storage_items(account_id: String, character, indices: Array, peer_id: int):
	"""Move items from house storage to character inventory during character select"""
	var house = persistence.get_house(account_id)
	if house == null:
		return

	var items = house.storage.items
	# Validate, deduplicate, and sort indices in descending order (remove from end first to preserve indices)
	var valid_indices = []
	var seen = {}
	for idx in indices:
		var i = int(idx)
		if i >= 0 and i < items.size() and not seen.has(i):
			valid_indices.append(i)
			seen[i] = true
	valid_indices.sort()
	valid_indices.reverse()

	# Check inventory capacity
	var available_space = Character.MAX_INVENTORY_SIZE - character.inventory.size()
	if available_space <= 0:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF6666]Your inventory is full! Cannot withdraw items.[/color]"})
		return

	var withdrawn = []
	for idx in valid_indices:
		if withdrawn.size() >= available_space:
			break
		var item = items[idx]
		character.inventory.append(item.duplicate(true))
		withdrawn.append(item.get("name", "Unknown"))
		persistence.remove_item_from_house_storage(account_id, idx)

	if withdrawn.size() > 0:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FFFF]Withdrew %d item(s) from Sanctuary storage:[/color] %s" % [withdrawn.size(), ", ".join(withdrawn)]
		})

func handle_house_unregister_companion(peer_id: int, message: Dictionary):
	"""Handle unregistering a companion (move to kennel instead of storage)"""
	if not peers.has(peer_id) or not peers[peer_id].authenticated:
		send_to_peer(peer_id, {"type": "error", "message": "Not authenticated."})
		return

	var account_id = peers[peer_id].account_id
	var companion_slot = message.get("slot", -1)

	var house = persistence.get_house(account_id)
	if house == null:
		send_to_peer(peer_id, {"type": "error", "message": "No house found."})
		return

	if companion_slot < 0 or companion_slot >= house.registered_companions.companions.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid companion slot."})
		return

	var companion = house.registered_companions.companions[companion_slot]

	# Check if companion is currently checked out
	if companion.get("checked_out_by", null) != null:
		send_to_peer(peer_id, {"type": "error", "message": "Cannot unregister - companion is currently checked out by %s!" % companion.checked_out_by})
		return

	# Check if kennel has room
	var kennel_capacity = persistence.get_kennel_capacity(account_id)
	if house.companion_kennel.companions.size() >= kennel_capacity:
		send_to_peer(peer_id, {"type": "error", "message": "Kennel is full! Upgrade for more space."})
		return

	var companion_name = companion.get("name", "Unknown")

	# Remove from registered companions
	var unregistered = persistence.unregister_companion_from_house(account_id, companion_slot)
	if unregistered.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Failed to unregister companion."})
		return

	# Clean up registration metadata before adding to kennel
	unregistered.erase("registered_at")
	unregistered.erase("checked_out_by")
	unregistered.erase("checkout_time")

	# Add to kennel
	persistence.add_companion_to_kennel(account_id, unregistered)

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF8800]%s unregistered and moved to kennel.[/color]" % companion_name
	})

	# Send updated house data
	var updated_house = persistence.get_house(account_id)
	send_to_peer(peer_id, {
		"type": "house_update",
		"house": updated_house,
		"upgrade_costs": persistence.HOUSE_UPGRADES
	})

func handle_house_register_companion_from_storage(peer_id: int, message: Dictionary):
	"""Handle registering a companion from storage to registered companions"""
	if not peers.has(peer_id) or not peers[peer_id].authenticated:
		send_to_peer(peer_id, {"type": "error", "message": "Not authenticated."})
		return

	var account_id = peers[peer_id].account_id
	var item_index = message.get("index", -1)

	var house = persistence.get_house(account_id)
	if house == null:
		send_to_peer(peer_id, {"type": "error", "message": "No house found."})
		return

	if item_index < 0 or item_index >= house.storage.items.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid item index."})
		return

	var item = house.storage.items[item_index]

	# Check if it's a stored companion
	if item.get("type") != "stored_companion":
		send_to_peer(peer_id, {"type": "error", "message": "This item is not a companion."})
		return

	# Check if kennel has room
	var companion_capacity = persistence.get_house_companion_capacity(account_id)
	if house.registered_companions.companions.size() >= companion_capacity:
		send_to_peer(peer_id, {"type": "error", "message": "Registered companion slots are full! Upgrade to register more companions."})
		return

	var companion_name = item.get("name", "Unknown")

	# Remove from storage
	persistence.remove_item_from_house_storage(account_id, item_index)

	# Register to kennel (remove the "type" field as it's not needed in kennel)
	var companion_data = item.duplicate()
	companion_data.erase("type")
	var slot = persistence.register_companion_to_house(account_id, companion_data, null)

	if slot == -1:
		# Failed - put it back in storage
		persistence.add_item_to_house_storage(account_id, item)
		send_to_peer(peer_id, {"type": "error", "message": "Failed to register companion."})
		return

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FF00]%s has been registered to your Sanctuary kennel![/color]" % companion_name
	})

	# Send updated house data
	var updated_house = persistence.get_house(account_id)
	send_to_peer(peer_id, {
		"type": "house_update",
		"house": updated_house,
		"upgrade_costs": persistence.HOUSE_UPGRADES
	})

func handle_home_stone_companion_response(peer_id: int, message: Dictionary):
	"""Handle player's choice for Home Stone (Companion) - Register or Kennel"""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	if character.active_companion.is_empty():
		return
	var choice = message.get("choice", "")
	var account_id = peers[peer_id].account_id
	var companion = character.active_companion.duplicate(true)

	if choice == "register":
		var house = persistence.get_house(account_id)
		var companion_capacity = persistence.get_house_companion_capacity(account_id)
		if house.registered_companions.companions.size() >= companion_capacity:
			send_to_peer(peer_id, {"type": "error", "message": "Registered companion slots full!"})
			return
		var slot = persistence.register_companion_to_house(account_id, companion, character.name)
		if slot == -1:
			send_to_peer(peer_id, {"type": "error", "message": "Failed to register companion!"})
			return
		# Store house_slot on the companion itself (per-companion registration)
		character.active_companion["house_slot"] = slot
		character.set_companion_field(companion.get("id", ""), "house_slot", slot)
		# Keep legacy flags for backward compat
		character.using_registered_companion = true
		character.registered_companion_slot = slot
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00FF00]%s registered to your Sanctuary! Returns home if you fall.[/color]" % companion.get("name", "Companion")
		})
	elif choice == "kennel":
		var result = persistence.add_companion_to_kennel(account_id, companion)
		if result == -1:
			send_to_peer(peer_id, {"type": "error", "message": "Kennel is full! Upgrade for more slots."})
			return
		character.dismiss_companion()
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#A335EE]%s stored in kennel for fusion![/color]" % companion.get("name", "Companion")
		})
	else:
		# Cancel — return the Home Stone to inventory
		if pending_home_stone_companion.has(peer_id):
			var pending = pending_home_stone_companion[peer_id]
			var restored_item = {
				"id": randi(),
				"type": pending.get("item_type", "home_stone_companion"),
				"name": pending.get("item_name", "Home Stone (Companion)"),
				"is_consumable": true,
				"quantity": 1,
				"tier": int(pending.get("item_tier", 0)),
				"rarity": "common",
				"level": 1,
				"value": 0,
				"affixes": {}
			}
			character.add_item(restored_item)
		pending_home_stone_companion.erase(peer_id)
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Cancelled.[/color]"})
		send_character_update(peer_id)
		save_character(peer_id)
		return

	pending_home_stone_companion.erase(peer_id)
	send_character_update(peer_id)
	save_character(peer_id)

func handle_house_kennel_release(peer_id: int, message: Dictionary):
	"""Release a companion from the kennel (permanently removes it)"""
	if not peers.has(peer_id) or not peers[peer_id].authenticated:
		send_to_peer(peer_id, {"type": "error", "message": "Not authenticated."})
		return
	var account_id = peers[peer_id].account_id
	var index = int(message.get("index", -1))
	var companion = persistence.remove_companion_from_kennel(account_id, index)
	if companion.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid kennel index!"})
		return
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FF8800]Released %s from kennel.[/color]" % companion.get("name", "companion")
	})
	var updated_house = persistence.get_house(account_id)
	send_to_peer(peer_id, {
		"type": "house_update",
		"house": updated_house,
		"upgrade_costs": persistence.HOUSE_UPGRADES
	})

func handle_house_kennel_register(peer_id: int, message: Dictionary):
	"""Move a companion from kennel to registered_companions"""
	if not peers.has(peer_id) or not peers[peer_id].authenticated:
		send_to_peer(peer_id, {"type": "error", "message": "Not authenticated."})
		return
	var account_id = peers[peer_id].account_id
	var index = int(message.get("index", -1))
	var house = persistence.get_house(account_id)
	var kennel = house.companion_kennel.companions
	if index < 0 or index >= kennel.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid kennel index!"})
		return
	var capacity = persistence.get_house_companion_capacity(account_id)
	if house.registered_companions.companions.size() >= capacity:
		send_to_peer(peer_id, {"type": "error", "message": "Registered companion slots full!"})
		return
	var companion = persistence.remove_companion_from_kennel(account_id, index)
	if companion.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Failed to remove from kennel."})
		return
	persistence.register_companion_to_house(account_id, companion, null)
	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FF00]%s registered! Will survive death.[/color]" % companion.get("name", "companion")
	})
	var updated_house = persistence.get_house(account_id)
	send_to_peer(peer_id, {
		"type": "house_update",
		"house": updated_house,
		"upgrade_costs": persistence.HOUSE_UPGRADES
	})

func handle_house_fusion(peer_id: int, message: Dictionary):
	"""Handle companion fusion request"""
	if not peers.has(peer_id) or not peers[peer_id].authenticated:
		send_to_peer(peer_id, {"type": "error", "message": "Not authenticated."})
		return
	var account_id = peers[peer_id].account_id
	var fusion_type = message.get("fusion_type", "same")
	var indices = message.get("indices", [])
	var house = persistence.get_house(account_id)
	var kennel = house.companion_kennel.companions

	# Validate all indices (range + uniqueness)
	var seen_indices = {}
	for idx in indices:
		var int_idx = int(idx)
		if int_idx < 0 or int_idx >= kennel.size():
			send_to_peer(peer_id, {"type": "error", "message": "Invalid companion selection!"})
			return
		if seen_indices.has(int_idx):
			send_to_peer(peer_id, {"type": "error", "message": "Duplicate companion selected!"})
			return
		seen_indices[int_idx] = true

	if fusion_type == "same":
		if indices.size() != 3:
			send_to_peer(peer_id, {"type": "error", "message": "Same-type fusion requires exactly 3 companions!"})
			return
		var first = kennel[int(indices[0])]
		for idx in indices:
			var comp = kennel[int(idx)]
			if comp.get("monster_type") != first.get("monster_type") or int(comp.get("sub_tier", 1)) != int(first.get("sub_tier", 1)):
				send_to_peer(peer_id, {"type": "error", "message": "All 3 must be same type and sub-tier!"})
				return
		var current_sub_tier = int(first.get("sub_tier", 1))
		var new_sub_tier = mini(current_sub_tier + 1, 9)
		var inherited = _check_variant_inheritance(kennel, indices)
		var output = drop_tables.create_fusion_companion(first.monster_type, new_sub_tier, inherited)
		if output.is_empty():
			send_to_peer(peer_id, {"type": "error", "message": "Fusion failed — unknown monster type!"})
			return
		var int_indices = []
		for idx in indices:
			int_indices.append(int(idx))
		if persistence.fuse_companions(account_id, int_indices, output):
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FFD700]Fusion complete! Created %s (T%d-%d)![/color]" % [output.name, output.tier, new_sub_tier]
			})
			var updated_house = persistence.get_house(account_id)
			send_to_peer(peer_id, {
				"type": "house_update",
				"house": updated_house,
				"upgrade_costs": persistence.HOUSE_UPGRADES
			})

	elif fusion_type == "mixed":
		if indices.size() != 8:
			send_to_peer(peer_id, {"type": "error", "message": "Mixed T9 fusion requires exactly 8 companions!"})
			return
		for idx in indices:
			if int(kennel[int(idx)].get("sub_tier", 1)) != 8:
				send_to_peer(peer_id, {"type": "error", "message": "All 8 must be sub-tier 8!"})
				return
		var random_type = kennel[int(indices[randi() % indices.size()])].get("monster_type")
		var inherited = _check_variant_inheritance(kennel, indices)
		var output = drop_tables.create_fusion_companion(random_type, 9, inherited)
		if output.is_empty():
			send_to_peer(peer_id, {"type": "error", "message": "Fusion failed!"})
			return
		var int_indices = []
		for idx in indices:
			int_indices.append(int(idx))
		if persistence.fuse_companions(account_id, int_indices, output):
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF00FF]T9 Fusion! Created %s (T%d-9)![/color]" % [output.name, output.tier]
			})
			var updated_house = persistence.get_house(account_id)
			send_to_peer(peer_id, {
				"type": "house_update",
				"house": updated_house,
				"upgrade_costs": persistence.HOUSE_UPGRADES
			})

func _check_variant_inheritance(kennel: Array, indices: Array) -> Dictionary:
	"""Check if all companions in the fusion share the same variant for inheritance."""
	var first_variant = kennel[int(indices[0])].get("variant", "")
	for idx in indices:
		if kennel[int(idx)].get("variant", "") != first_variant:
			return {}
	return {
		"name": first_variant,
		"color": kennel[int(indices[0])].get("variant_color", ""),
		"color2": kennel[int(indices[0])].get("variant_color2", ""),
		"pattern": kennel[int(indices[0])].get("variant_pattern", "solid"),
	}

func _award_baddie_points_on_death(peer_id: int, character: Character, account_id: String, cause_of_death: String) -> int:
	"""Calculate and award baddie points to house on character death"""
	var bp = persistence.calculate_baddie_points(character)

	if bp > 0:
		persistence.add_baddie_points(account_id, bp)

		# Update house stats
		persistence.update_house_stats(account_id, {
			"characters_lost": 1,
			"highest_level_reached": character.level,
			"total_xp_earned": character.experience,
			"total_monsters_killed": character.monsters_killed,
			"total_gold_earned": character.gold
		})

		print("Awarded %d Baddie Points to account %s from character %s" % [bp, account_id, character.name])

	# Return ALL registered companions to house (per-companion house_slot tracking)
	var returned_slots = {}
	for comp in character.collected_companions:
		var house_slot = comp.get("house_slot", -1)
		if house_slot >= 0 and not returned_slots.has(house_slot):
			persistence.return_companion_to_house(account_id, house_slot, comp)
			returned_slots[house_slot] = true
	# Also check active companion (may have newer data than collected_companions entry)
	var active_slot = character.active_companion.get("house_slot", -1)
	if active_slot >= 0 and not returned_slots.has(active_slot):
		persistence.return_companion_to_house(account_id, active_slot, character.active_companion)
	# Legacy fallback: if old character has flag but no house_slot on companions
	if returned_slots.is_empty() and character.using_registered_companion and character.registered_companion_slot >= 0:
		persistence.return_companion_to_house(account_id, character.registered_companion_slot, character.active_companion)

	return bp

func _checkout_companion_for_character(account_id: String, character: Character, slot: int, char_name: String):
	"""Checkout a registered companion from house kennel and assign to character"""
	var companion_data = persistence.checkout_companion_from_house(account_id, slot, char_name)
	if companion_data.is_empty():
		log_message("Failed to checkout companion slot %d for %s" % [slot, char_name])
		return

	# Build active companion dict (strip registration metadata)
	var companion = companion_data.duplicate()
	companion.erase("registered_at")
	companion.erase("checked_out_by")
	companion.erase("checkout_time")

	# Store house_slot on companion dict for per-companion registration tracking
	companion["house_slot"] = slot
	character.active_companion = companion
	# Only add to collected_companions if not already there (prevent duplicates)
	var already_has = false
	for comp in character.collected_companions:
		if comp.get("id", "") == companion.get("id", ""):
			# Update the existing entry with house_slot
			comp["house_slot"] = slot
			already_has = true
			break
	if not already_has:
		character.collected_companions.append(companion)
	character.using_registered_companion = true
	character.registered_companion_slot = slot
	log_message("Companion '%s' checked out from kennel slot %d for %s" % [companion.get("name", "Unknown"), slot, char_name])

func _get_house_bonuses_for_character(account_id: String) -> Dictionary:
	"""Get house upgrade bonuses to apply to a new character"""
	return persistence.get_house_bonuses(account_id)

# ===== TRADING POST HANDLERS =====

func trigger_trading_post_encounter(peer_id: int):
	"""Trigger Trading Post encounter when player enters"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var tp = world_system.get_trading_post_at(character.x, character.y)

	if tp.is_empty():
		return

	# Extract normalized fields
	var tp_id = tp.get("id", "")
	var tp_name = tp.get("name", "Trading Post")
	var tp_center = tp.get("center", {"x": character.x, "y": character.y})
	var tp_x = tp_center.get("x", character.x) if tp_center is Dictionary else character.x
	var tp_y = tp_center.get("y", character.y) if tp_center is Dictionary else character.y

	# Record discovery of this trading post
	var newly_discovered = character.discover_trading_post(tp_name, tp_x, tp_y)
	if newly_discovered:
		save_character(peer_id)

	# Store Trading Post data for this player
	at_trading_post[peer_id] = tp

	# Get available quests at this Trading Post
	var active_quest_ids = []
	for q in character.active_quests:
		active_quest_ids.append(q.quest_id)

	var available_quests = quest_db.get_available_quests_for_player(
		tp_id, character.completed_quests, active_quest_ids, character.daily_quest_cooldowns, character.level, character.name)

	# Check for quests ready to turn in
	var quests_to_turn_in = []
	for quest_data in character.active_quests:
		var quest = quest_db.get_quest(quest_data.quest_id)
		if not quest.is_empty() and quest.get("trading_post", "") == tp_id:
			if quest_data.progress >= quest_data.target:
				quests_to_turn_in.append(quest_data.quest_id)

	# Calculate recharge cost to send to client
	var is_starter_post = tp_id in STARTER_TRADING_POSTS
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
		"id": tp_id,
		"name": tp_name,
		"description": tp.get("description", ""),
		"quest_giver": tp.get("quest_giver", ""),
		"services": ["shop", "quests", "recharge"],
		"available_quests": available_quests.size(),
		"quests_to_turn_in": quests_to_turn_in.size(),
		"recharge_cost": recharge_cost,
		"x": tp_x,
		"y": tp_y
	})

func _handle_market_interact(peer_id: int, _character):
	"""Handle bump into market tile — open market (list/buy items for Valor)."""
	send_to_peer(peer_id, {"type": "market_start"})

func _handle_inn_interact(peer_id: int, character):
	"""Handle bump into inn tile — open heal/recharge."""
	handle_trading_post_recharge(peer_id)

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
	services_text.append("[Space] Leave shop")

	send_to_peer(peer_id, {
		"type": "merchant_start",
		"merchant": merchant_info,
		"message": "[color=#FFD700]===== %s MARKETPLACE =====[/color]\n\n%s" % [tp.name.to_upper(), "\n".join(services_text)]
	})

	_send_merchant_inventory(peer_id)
	_send_shop_inventory(peer_id)

func handle_trading_post_quests(peer_id: int):
	"""Access quest giver at a Trading Post or player post quest board"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var tp: Dictionary

	if at_trading_post.has(peer_id):
		tp = at_trading_post[peer_id]
	elif at_player_station.has(peer_id):
		# At a player post — use nearest NPC post for quest generation
		var nearest = chunk_manager.get_nearest_npc_post(character.x, character.y) if chunk_manager else {}
		if nearest.is_empty():
			send_to_peer(peer_id, {"type": "error", "message": "No quest board available!"})
			return
		tp = nearest
	else:
		send_to_peer(peer_id, {"type": "error", "message": "You are not at a Trading Post!"})
		return

	# Get active quest IDs
	var active_quest_ids = []
	for q in character.active_quests:
		active_quest_ids.append(q.quest_id)

	# Get available quests scaled to player level
	var available_quests = quest_db.get_available_quests_for_player(
		tp.id, character.completed_quests, active_quest_ids, character.daily_quest_cooldowns, character.level, character.name)

	# No locked quests with dynamic-only system (no static prerequisite chains)
	var locked_quests = []

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
				# Check for player's personal dungeon first
				var dungeon_info = _get_player_dungeon_info(peer_id, quest_data.quest_id, tp_x, tp_y)
				if not dungeon_info.is_empty():
					description += "\n\n[color=#00FFFF]Your dungeon:[/color] %s (%s)" % [
						dungeon_info.dungeon_name, dungeon_info.direction_text
					]
				else:
					# Fall back to showing nearest world dungeon
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
	var gems = max(0, int(distance / 100))

	return {
		"id": quest_id,
		"name": "Journey to " + next_post_name,
		"description": "Travel to %s to expand your horizons. (Recommended Level: %d)" % [next_post_name, recommended_level],
		"type": 4,  # QuestType.EXPLORATION
		"trading_post": current_post_id,
		"target": 1,
		"destinations": [next_post_id],
		"rewards": {"xp": base_xp, "gems": gems},
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
		# Flat 20 base for starter areas regardless of level (divided by 10 for valor)
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

	var valor_cost = max(1, cost / 10)
	var tp_heal_account_id = peers[peer_id].account_id
	if not persistence.spend_valor(tp_heal_account_id, valor_cost):
		send_to_peer(peer_id, {
			"type": "trading_post_message",
			"message": "[color=#FF0000]You don't have enough valor! Recharge costs %d valor.[/color]" % valor_cost
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

	# Restore ALL resources including HP (valor already deducted)
	character.current_hp = character.get_total_max_hp()
	character.current_mana = character.get_total_max_mana()
	character.current_stamina = character.get_total_max_stamina()
	character.current_energy = character.get_total_max_energy()
	restored.append("HP and resources restored")

	send_to_peer(peer_id, {
		"type": "trading_post_message",
		"message": "[color=#00FF00]The healers at %s restore you completely![/color]\n[color=#00FF00]%s! (-%d valor)[/color]" % [tp.name, ", ".join(restored).capitalize(), valor_cost]
	})

	send_character_update(peer_id)
	save_character(peer_id)

func handle_trading_post_wits_training(peer_id: int):
	"""Sharpen Wits - Trickster-only WITS training at Trading Posts.
	Costs valor scaling with current bonus. +1 permanent WITS per purchase, cap +10."""
	if not at_trading_post.has(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You must be at a Trading Post![/color]"})
		return

	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Trickster-only
	if character.class_type not in ["Thief", "Ranger", "Ninja"]:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Only Tricksters can train their wits here.[/color]"})
		return

	# Check cap
	if character.wits_training_bonus >= 10:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FFA500]Your wits are already honed to their peak! (10/10)[/color]"})
		return

	# Cost scales: 5 + bonus * 10 valor
	var valor_cost = 5 + character.wits_training_bonus * 10
	var wits_account_id = peers[peer_id].account_id

	if not persistence.spend_valor(wits_account_id, valor_cost):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Not enough valor! Training costs %d valor. (You have %d)[/color]" % [valor_cost, persistence.get_valor(wits_account_id)]})
		return

	# Apply training
	character.wits_training_bonus += 1
	var effective_wits = character.get_effective_stat("wits")

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#00FFFF]The masters sharpen your mind![/color]\n[color=#00FF00]+1 permanent WITS! (%d/10 training) Effective WITS: %d (-%d valor)[/color]" % [character.wits_training_bonus, effective_wits, valor_cost]
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

# ===== OPEN MARKET HANDLERS =====

func _get_player_post_id(peer_id: int) -> String:
	"""Get a post_id string if the player is at a player post (enclosure), or empty string."""
	if not characters.has(peer_id):
		return ""
	var character = characters[peer_id]
	var loc_key = Vector2i(character.x, character.y)
	if enclosure_tile_lookup.has(loc_key):
		var enc_owner = enclosure_tile_lookup[loc_key].owner
		var enc_idx = enclosure_tile_lookup[loc_key].enclosure_idx
		return "player_" + enc_owner + "_" + str(enc_idx)
	return ""

func _get_market_post_id(peer_id: int) -> String:
	"""Get the market post_id for the player's current location (trading post or player post)."""
	if at_trading_post.has(peer_id):
		var tp = at_trading_post[peer_id]
		return str(tp.get("post_id", tp.get("name", "unknown")))
	var player_post = _get_player_post_id(peer_id)
	if not player_post.is_empty():
		return player_post
	return ""

func handle_market_browse(peer_id: int, message: Dictionary):
	"""Browse market listings at current trading post or player post."""
	if not characters.has(peer_id):
		return

	var post_id = _get_market_post_id(peer_id)
	if post_id.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "You must be at a trading post to browse the market."})
		return

	var category = message.get("category", "all")
	var sort_mode = message.get("sort", "category")
	var page = int(message.get("page", 0))
	var per_page = 9  # Show 9 items per page (selectable with 1-9)

	var all_listings = persistence.get_market_listings(post_id)

	# Filter by category
	var filtered = []
	for listing in all_listings:
		var supply_cat = listing.get("supply_category", "")
		if category == "all":
			filtered.append(listing)
		elif category == "material":
			if supply_cat.begins_with("material"):
				filtered.append(listing)
		elif category == "rune":
			if supply_cat == "rune":
				filtered.append(listing)
		elif category == "egg":
			if supply_cat == "egg":
				filtered.append(listing)
		elif supply_cat == category:
			filtered.append(listing)

	# Calculate markup prices
	for listing in filtered:
		var cat = listing.get("supply_category", "equipment")
		var markup = persistence.calculate_markup(post_id, cat)
		listing["markup_price"] = int(listing.get("base_valor", 0) * markup)
		listing["markup"] = markup

	# Stack compatible listings (same item name + same price + same seller = one stack)
	var stacks: Array = []
	var stack_map: Dictionary = {}

	for listing in filtered:
		var supply_cat = listing.get("supply_category", "")
		var is_unique = supply_cat == "equipment" or supply_cat == "egg" or supply_cat == "tool"

		if is_unique:
			var entry = listing.duplicate()
			entry["stack_listing_ids"] = [listing.get("listing_id", "")]
			entry["total_quantity"] = int(listing.get("quantity", 1))
			entry["display_category"] = _get_display_category(supply_cat)
			stacks.append(entry)
		else:
			var item = listing.get("item", {})
			var key = "%s|%d|%s" % [item.get("name", ""), int(listing.get("markup_price", 0)), listing.get("seller_name", "")]
			if stack_map.has(key):
				var idx = stack_map[key]
				stacks[idx]["stack_listing_ids"].append(listing.get("listing_id", ""))
				stacks[idx]["total_quantity"] += int(listing.get("quantity", 1))
			else:
				var entry = listing.duplicate()
				entry["stack_listing_ids"] = [listing.get("listing_id", "")]
				entry["total_quantity"] = int(listing.get("quantity", 1))
				entry["display_category"] = _get_display_category(supply_cat)
				stack_map[key] = stacks.size()
				stacks.append(entry)

	# Sort stacks
	match sort_mode:
		"category":
			stacks.sort_custom(_sort_stacks_by_category)
		"price_asc":
			stacks.sort_custom(func(a, b): return int(a.get("markup_price", 0)) < int(b.get("markup_price", 0)))
		"price_desc":
			stacks.sort_custom(func(a, b): return int(a.get("markup_price", 0)) > int(b.get("markup_price", 0)))
		"name_asc":
			stacks.sort_custom(func(a, b): return a.get("item", {}).get("name", "") < b.get("item", {}).get("name", ""))
		"newest":
			stacks.sort_custom(func(a, b): return int(a.get("listed_at", 0)) > int(b.get("listed_at", 0)))

	var total_pages = max(1, ceili(float(stacks.size()) / per_page))
	page = clampi(page, 0, total_pages - 1)

	var start = page * per_page
	var end_idx = mini(start + per_page, stacks.size())
	var page_listings = stacks.slice(start, end_idx)

	send_to_peer(peer_id, {
		"type": "market_browse_result",
		"listings": page_listings,
		"page": page,
		"total_pages": total_pages,
		"total_listings": stacks.size(),
		"category": category,
		"sort": sort_mode,
		"post_id": post_id
	})

func _get_display_category(supply_cat: String) -> String:
	if supply_cat == "equipment": return "Equipment"
	if supply_cat == "egg": return "Companion Eggs"
	if supply_cat == "consumable": return "Consumables"
	if supply_cat == "tool": return "Tools"
	if supply_cat == "rune": return "Runes"
	if supply_cat.begins_with("material"): return "Materials"
	if supply_cat == "monster_part": return "Monster Parts"
	return "Other"

func _sort_stacks_by_category(a: Dictionary, b: Dictionary) -> bool:
	var order = {"Equipment": 0, "Companion Eggs": 1, "Consumables": 2, "Tools": 3, "Runes": 4, "Materials": 5, "Monster Parts": 6, "Other": 7}
	var a_o = order.get(a.get("display_category", "Other"), 5)
	var b_o = order.get(b.get("display_category", "Other"), 5)
	if a_o != b_o: return a_o < b_o
	return int(a.get("markup_price", 0)) < int(b.get("markup_price", 0))

func handle_market_list_item(peer_id: int, message: Dictionary):
	"""List an inventory item on the market. Awards base valor immediately."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var account_id = peers[peer_id].account_id

	var post_id = _get_market_post_id(peer_id)
	if post_id.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "You must be at a trading post."})
		return

	var index = int(message.get("index", -1))
	if index < 0 or index >= character.inventory.size():
		send_to_peer(peer_id, {"type": "market_error", "message": "Invalid item."})
		return

	var item = character.inventory[index]

	# Can't list equipped items
	if item.get("equipped", false):
		send_to_peer(peer_id, {"type": "market_error", "message": "Unequip the item first."})
		return

	# Calculate base valor
	var base_valor = drop_tables.calculate_base_valor(item)

	# Apply market bonuses (Halfling +15%, Knight +10%)
	var bonus = character.get_market_bonus() + character.get_knight_market_bonus()
	if bonus > 0:
		base_valor = int(base_valor * (1.0 + bonus))

	# Create listing
	var listing = {
		"account_id": account_id,
		"seller_name": character.name,
		"item": item.duplicate(),
		"base_valor": base_valor,
		"supply_category": drop_tables.get_supply_category(item),
		"listed_at": int(Time.get_unix_time_from_system()),
		"quantity": 1
	}

	# Remove item from inventory
	character.inventory.remove_at(index)

	# Add listing and award valor
	var listing_id = persistence.add_market_listing(post_id, listing)
	persistence.add_valor(account_id, base_valor)

	save_character(peer_id)

	send_to_peer(peer_id, {
		"type": "market_list_success",
		"listing_id": listing_id,
		"base_valor": base_valor,
		"item_name": item.get("name", "item"),
		"total_valor": persistence.get_valor(account_id)
	})
	send_character_update(peer_id)

func handle_market_list_material(peer_id: int, message: Dictionary):
	"""List materials on the market. Awards base valor immediately."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var account_id = peers[peer_id].account_id

	var post_id = _get_market_post_id(peer_id)
	if post_id.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "You must be at a trading post."})
		return

	var material_name = message.get("material_name", "")
	var quantity = int(message.get("quantity", 1))

	if material_name.is_empty() or quantity <= 0:
		send_to_peer(peer_id, {"type": "market_error", "message": "Invalid material or quantity."})
		return

	# Check character has enough materials
	var available = int(character.crafting_materials.get(material_name, 0))
	if available < quantity:
		send_to_peer(peer_id, {"type": "market_error", "message": "Not enough %s. Have %d, need %d." % [material_name, available, quantity]})
		return

	# Calculate base valor per unit using actual material value (reflects gathering difficulty)
	var mat_info = CraftingDatabaseScript.MATERIALS.get(material_name, {})
	var mat_value = int(mat_info.get("value", 5))
	var per_unit_valor = maxi(1, int(mat_value / 3.0))
	var material_tier = int(mat_info.get("tier", _get_material_tier(material_name)))
	var total_valor = per_unit_valor * quantity

	# Apply market bonuses
	var bonus = character.get_market_bonus() + character.get_knight_market_bonus()
	if bonus > 0:
		total_valor = int(total_valor * (1.0 + bonus))

	# Remove materials
	character.crafting_materials[material_name] = available - quantity
	if character.crafting_materials[material_name] <= 0:
		character.crafting_materials.erase(material_name)

	# Create listing
	var listing = {
		"account_id": account_id,
		"seller_name": character.name,
		"item": {"type": "material", "name": material_name, "material_type": material_name, "tier": material_tier},
		"base_valor": total_valor,
		"supply_category": "material_t%d" % material_tier,
		"listed_at": int(Time.get_unix_time_from_system()),
		"quantity": quantity
	}

	persistence.add_market_listing(post_id, listing)
	persistence.add_valor(account_id, total_valor)

	save_character(peer_id)

	send_to_peer(peer_id, {
		"type": "market_list_success",
		"base_valor": total_valor,
		"item_name": "%dx %s" % [quantity, material_name],
		"total_valor": persistence.get_valor(account_id)
	})
	send_character_update(peer_id)

func _get_material_tier(material_name: String) -> int:
	"""Determine material tier from name."""
	var t1 = ["wood", "stone", "clay", "fiber", "bone_fragment", "slime_residue", "iron_ore", "copper_ore", "rough_hide"]
	var t2 = ["hardwood", "granite", "iron_ingot", "copper_ingot", "leather", "silk_thread", "coal", "tin_ore", "wolf_pelt"]
	var t3 = ["ironwood", "marble", "steel_ingot", "silver_ore", "silver_ingot", "enchanted_hide", "mithril_ore", "spider_silk"]
	var t4 = ["ebonwood", "obsidian", "mithril_ingot", "gold_ore", "gold_ingot", "dragon_scale", "phoenix_feather", "demon_hide"]
	var t5 = ["worldtree_wood", "adamantine_ore", "adamantine_ingot", "celestial_silk", "void_crystal", "titan_bone"]
	var t6 = ["primordial_essence", "divine_metal", "astral_thread", "chaos_crystal"]

	if material_name in t1: return 1
	if material_name in t2: return 2
	if material_name in t3: return 3
	if material_name in t4: return 4
	if material_name in t5: return 5
	if material_name in t6: return 6

	# Check crafting-specific materials
	if material_name.begins_with("parchment") or material_name.begins_with("ink"):
		return 2

	return 1  # Default to tier 1

func handle_market_list_egg(peer_id: int, message: Dictionary):
	"""List an incubating egg on the market. Awards base valor immediately."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var account_id = peers[peer_id].account_id

	var post_id = _get_market_post_id(peer_id)
	if post_id.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "You must be at a trading post."})
		return

	var index = int(message.get("index", -1))
	if index < 0 or index >= character.incubating_eggs.size():
		send_to_peer(peer_id, {"type": "market_error", "message": "Invalid egg."})
		return

	var egg = character.incubating_eggs[index].duplicate(true)
	egg["type"] = "egg"
	egg["is_consumable"] = false

	# Calculate valor
	var base_valor = drop_tables.calculate_egg_valor(egg)

	# Apply market bonuses (Halfling +15%, Knight +10%)
	var bonus = character.get_market_bonus() + character.get_knight_market_bonus()
	if bonus > 0:
		base_valor = int(base_valor * (1.0 + bonus))

	# Create listing
	var listing = {
		"account_id": account_id,
		"seller_name": character.name,
		"item": egg,
		"base_valor": base_valor,
		"supply_category": "egg",
		"listed_at": int(Time.get_unix_time_from_system()),
		"quantity": 1
	}

	# Remove egg from incubator
	character.incubating_eggs.remove_at(index)

	# Add listing and award valor
	var listing_id = persistence.add_market_listing(post_id, listing)
	persistence.add_valor(account_id, base_valor)

	save_character(peer_id)

	send_to_peer(peer_id, {
		"type": "market_list_success",
		"listing_id": listing_id,
		"base_valor": base_valor,
		"item_name": egg.get("name", "Egg"),
		"total_valor": persistence.get_valor(account_id),
		"listed_type": "egg"
	})
	send_character_update(peer_id)

func handle_market_buy(peer_id: int, message: Dictionary):
	"""Buy a listing from the market. Supports partial quantity for material stacks."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var buyer_account_id = peers[peer_id].account_id

	var post_id = _get_market_post_id(peer_id)
	if post_id.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "You must be at a trading post."})
		return

	# Support both single listing_id and array of listing_ids (for stacked buys)
	var listing_ids: Array = []
	var single_id = message.get("listing_id", "")
	if not single_id.is_empty():
		listing_ids = [single_id]
	else:
		listing_ids = message.get("listing_ids", [])
	if listing_ids.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "Invalid listing."})
		return

	# Find first valid listing (use it for item info and pricing)
	var listing = {}
	var listing_post_id = post_id
	var listings = persistence.get_market_listings(post_id)
	for l in listings:
		if l.get("listing_id", "") == listing_ids[0]:
			listing = l
			break

	if listing.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "Listing not found."})
		return

	var item = listing.get("item", {})

	# Calculate total available across all listed IDs
	var total_available = 0
	var valid_listings: Array = []
	for lid in listing_ids:
		for l in listings:
			if l.get("listing_id", "") == lid:
				valid_listings.append(l)
				total_available += int(l.get("quantity", 1))
				break

	var buy_qty = int(message.get("quantity", 0))
	if buy_qty <= 0:
		buy_qty = total_available
	buy_qty = mini(buy_qty, total_available)

	# Calculate price using first listing's per-unit rate
	var first_listing_qty = int(listing.get("quantity", 1))
	var base_valor = int(listing.get("base_valor", 0))
	var seller_account_id = listing.get("account_id", "")
	var per_unit_valor = int(base_valor / maxi(first_listing_qty, 1))
	var partial_base = per_unit_valor * buy_qty
	var price = partial_base

	if buyer_account_id != seller_account_id:
		var cat = listing.get("supply_category", "equipment")
		var markup = persistence.calculate_markup(post_id, cat)
		price = int(partial_base * markup)

	# Check buyer has enough valor
	var buyer_valor = persistence.get_valor(buyer_account_id)
	if buyer_valor < price:
		send_to_peer(peer_id, {"type": "market_error", "message": "Not enough Valor. Need %d, have %d." % [price, buyer_valor]})
		return

	# Check inventory/egg space
	if item.get("type", "") == "material":
		pass  # Materials go to crafting pouch, always has space
	elif item.get("type", "") == "egg":
		var egg_cap = persistence.get_egg_capacity(buyer_account_id)
		if character.incubating_eggs.size() >= egg_cap:
			send_to_peer(peer_id, {"type": "market_error", "message": "Your egg incubator is full! (%d/%d)" % [character.incubating_eggs.size(), egg_cap]})
			return
	elif character.inventory.size() >= Character.MAX_INVENTORY_SIZE:
		send_to_peer(peer_id, {"type": "market_error", "message": "Inventory full."})
		return

	# Process purchase
	persistence.spend_valor(buyer_account_id, price)

	# If cross-player purchase, seller gets half the markup as bonus
	if buyer_account_id != seller_account_id and price > partial_base:
		var markup_total = price - partial_base
		var seller_bonus = int(markup_total / 2)
		var treasury_cut = markup_total - seller_bonus
		if seller_bonus > 0:
			persistence.add_valor(seller_account_id, seller_bonus)
			for pid in peers.keys():
				if peers[pid].account_id == seller_account_id and characters.has(pid):
					var qty_text = " x%d" % buy_qty if buy_qty > 1 else ""
					send_to_peer(pid, {"type": "text", "message": "[color=#FFD700]Market sale! Someone bought your %s%s — you earned %d bonus Valor![/color]" % [
						item.get("name", "item"), qty_text, seller_bonus]})
					break
		if treasury_cut > 0:
			persistence.add_to_realm_treasury(treasury_cut)

	# Add item to buyer
	if item.get("type", "") == "material":
		var mat_name = item.get("material_type", item.get("name", ""))
		if not character.crafting_materials.has(mat_name):
			character.crafting_materials[mat_name] = 0
		character.crafting_materials[mat_name] += buy_qty
	elif item.get("type", "") == "egg":
		character.incubating_eggs.append(item)
	else:
		character.inventory.append(item)

	# Consume from listings in order until buy_qty is fulfilled
	var remaining_to_buy = buy_qty
	for vl in valid_listings:
		if remaining_to_buy <= 0:
			break
		var vl_id = vl.get("listing_id", "")
		var vl_qty = int(vl.get("quantity", 1))
		var vl_base = int(vl.get("base_valor", 0))
		var vl_per_unit = int(vl_base / maxi(vl_qty, 1))
		if remaining_to_buy >= vl_qty:
			# Consume entire listing
			persistence.remove_market_listing(listing_post_id, vl_id)
			remaining_to_buy -= vl_qty
		else:
			# Partial consume
			var rem = vl_qty - remaining_to_buy
			persistence.update_market_listing_quantity(listing_post_id, vl_id, rem, vl_per_unit * rem)
			remaining_to_buy = 0

	save_character(peer_id)

	var qty_text = " x%d" % buy_qty if buy_qty > 1 else ""
	send_to_peer(peer_id, {
		"type": "market_buy_success",
		"item_name": item.get("name", "item") + qty_text,
		"price": price,
		"new_valor": persistence.get_valor(buyer_account_id)
	})
	send_character_update(peer_id)

func handle_market_my_listings(peer_id: int, message: Dictionary):
	"""Get all listings by this account across all posts."""
	if not peers.has(peer_id):
		return
	var account_id = peers[peer_id].account_id
	var my_listings = persistence.get_all_listings_by_account(account_id)

	send_to_peer(peer_id, {
		"type": "market_my_listings_result",
		"listings": my_listings
	})

func handle_market_cancel(peer_id: int, message: Dictionary):
	"""Cancel own listing and return item to inventory."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var account_id = peers[peer_id].account_id

	var listing_id = message.get("listing_id", "")
	var post_id = message.get("post_id", "")

	if listing_id.is_empty() or post_id.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "Invalid listing."})
		return

	# Find and verify listing belongs to this account
	var listings = persistence.get_market_listings(post_id)
	var listing = {}
	for l in listings:
		if l.get("listing_id", "") == listing_id:
			listing = l
			break

	if listing.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "Listing not found."})
		return

	if listing.get("account_id", "") != account_id:
		send_to_peer(peer_id, {"type": "market_error", "message": "That's not your listing."})
		return

	# Check inventory/egg space
	var item = listing.get("item", {})
	if item.get("type", "") == "egg":
		var egg_cap = persistence.get_egg_capacity(account_id)
		if character.incubating_eggs.size() >= egg_cap:
			send_to_peer(peer_id, {"type": "market_error", "message": "Egg incubator full! (%d/%d)" % [character.incubating_eggs.size(), egg_cap]})
			return
	elif item.get("type", "") != "material" and character.inventory.size() >= Character.MAX_INVENTORY_SIZE:
		send_to_peer(peer_id, {"type": "market_error", "message": "Inventory full."})
		return

	# Deduct the valor that was awarded on listing (they got paid upfront)
	var base_valor = int(listing.get("base_valor", 0))
	var current_valor = persistence.get_valor(account_id)
	if current_valor < base_valor:
		send_to_peer(peer_id, {"type": "market_error", "message": "Not enough Valor to cancel (you were paid %d on listing)." % base_valor})
		return

	persistence.spend_valor(account_id, base_valor)

	# Return item
	if item.get("type", "") == "material":
		var mat_name = item.get("material_type", item.get("name", ""))
		var qty = int(listing.get("quantity", 1))
		if not character.crafting_materials.has(mat_name):
			character.crafting_materials[mat_name] = 0
		character.crafting_materials[mat_name] += qty
	elif item.get("type", "") == "egg":
		character.incubating_eggs.append(item)
	else:
		character.inventory.append(item)

	# Remove listing
	persistence.remove_market_listing(post_id, listing_id)

	save_character(peer_id)

	send_to_peer(peer_id, {
		"type": "market_cancel_success",
		"item_name": item.get("name", "item"),
		"item_type": item.get("type", ""),
		"valor_deducted": base_valor,
		"total_valor": persistence.get_valor(account_id)
	})
	send_character_update(peer_id)

func handle_market_cancel_all(peer_id: int, message: Dictionary):
	"""Pull all own listings back to inventory, limited by free space."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var account_id = peers[peer_id].account_id

	var my_listings = persistence.get_all_listings_by_account(account_id)
	if my_listings.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "You have no active listings."})
		return

	var current_valor = persistence.get_valor(account_id)
	var free_slots = Character.MAX_INVENTORY_SIZE - character.inventory.size()
	var egg_cap = persistence.get_egg_capacity(account_id)
	var free_egg_slots = egg_cap - character.incubating_eggs.size()
	var pulled_count = 0
	var total_valor_deducted = 0
	var skipped_no_space = 0
	var skipped_no_valor = 0

	for listing in my_listings:
		var item = listing.get("item", {})
		var base_valor = int(listing.get("base_valor", 0))
		var listing_id = listing.get("listing_id", "")
		var post_id = listing.get("post_id", "")
		var is_material = item.get("type", "") == "material" or item.has("material_type")
		var is_egg = item.get("type", "") == "egg"

		# Check if we can afford to cancel (valor was paid upfront)
		if current_valor < base_valor:
			skipped_no_valor += 1
			continue

		# Materials go to crafting_materials (no inventory slot needed)
		if is_material:
			var mat_name = item.get("material_type", item.get("name", ""))
			var qty = int(listing.get("quantity", 1))
			if not character.crafting_materials.has(mat_name):
				character.crafting_materials[mat_name] = 0
			character.crafting_materials[mat_name] += qty
		elif is_egg:
			if free_egg_slots <= 0:
				skipped_no_space += 1
				continue
			character.incubating_eggs.append(item)
			free_egg_slots -= 1
		else:
			# Non-materials need inventory space
			if free_slots <= 0:
				skipped_no_space += 1
				continue
			character.inventory.append(item)
			free_slots -= 1

		# Deduct valor and remove listing
		persistence.spend_valor(account_id, base_valor)
		current_valor -= base_valor
		total_valor_deducted += base_valor
		persistence.remove_market_listing(post_id, listing_id)
		pulled_count += 1

	if pulled_count == 0:
		var reason = "Not enough Valor to cancel listings." if skipped_no_valor > 0 else "Inventory full."
		send_to_peer(peer_id, {"type": "market_error", "message": reason})
		return

	save_character(peer_id)

	var msg = "[color=#00FF00]Pulled %d listing%s back.[/color]" % [pulled_count, "s" if pulled_count != 1 else ""]
	if total_valor_deducted > 0:
		msg += " [color=#FF8800](-%d Valor refunded to market)[/color]" % total_valor_deducted
	if skipped_no_space > 0:
		msg += "\n[color=#FF4444]%d item%s skipped — inventory full.[/color]" % [skipped_no_space, "s" if skipped_no_space != 1 else ""]
	if skipped_no_valor > 0:
		msg += "\n[color=#FF4444]%d listing%s skipped — not enough Valor.[/color]" % [skipped_no_valor, "s" if skipped_no_valor != 1 else ""]

	send_to_peer(peer_id, {
		"type": "market_cancel_all_success",
		"pulled_count": pulled_count,
		"valor_deducted": total_valor_deducted,
		"total_valor": persistence.get_valor(account_id),
		"message": msg
	})
	send_character_update(peer_id)

func handle_market_list_all(peer_id: int, message: Dictionary):
	"""Bulk-list all items of a type on the market. Awards valor immediately."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var account_id = peers[peer_id].account_id

	var post_id = _get_market_post_id(peer_id)
	if post_id.is_empty():
		send_to_peer(peer_id, {"type": "market_error", "message": "You must be at a trading post."})
		return

	var list_type = message.get("list_type", "")
	var bonus = character.get_market_bonus() + character.get_knight_market_bonus()
	var total_valor = 0
	var count = 0
	var now = int(Time.get_unix_time_from_system())

	if list_type == "equipment":
		# List all unequipped, unlocked equipment from inventory
		var to_remove: Array = []
		for i in range(character.inventory.size() - 1, -1, -1):
			var item = character.inventory[i]
			if item.get("locked", false) or item.get("equipped", false):
				continue
			var itype = item.get("type", "")
			if itype == "tool" or itype == "rune" or itype == "structure" or itype == "treasure_chest":
				continue
			if item.get("is_consumable", false) or _is_consumable_type(itype):
				continue
			if not item.has("slot") and not item.has("rarity"):
				continue  # Not equipment

			var base_valor = drop_tables.calculate_base_valor(item)
			if bonus > 0:
				base_valor = int(base_valor * (1.0 + bonus))
			var listing = {
				"account_id": account_id,
				"seller_name": character.name,
				"item": item.duplicate(),
				"base_valor": base_valor,
				"supply_category": drop_tables.get_supply_category(item),
				"listed_at": now,
				"quantity": 1
			}
			persistence.add_market_listing(post_id, listing)
			total_valor += base_valor
			count += 1
			to_remove.append(i)
		for i in to_remove:
			character.inventory.remove_at(i)

	elif list_type == "items":
		# List all unlocked consumables + tools
		var to_remove: Array = []
		for i in range(character.inventory.size() - 1, -1, -1):
			var item = character.inventory[i]
			if item.get("locked", false) or item.get("equipped", false):
				continue
			var itype = item.get("type", "")
			var is_listable = item.get("is_consumable", false) or _is_consumable_type(itype) or itype == "tool"
			if not is_listable:
				continue
			if itype == "treasure_chest":
				continue  # Don't bulk-list treasure chests

			var base_valor = drop_tables.calculate_base_valor(item)
			if bonus > 0:
				base_valor = int(base_valor * (1.0 + bonus))
			var listing = {
				"account_id": account_id,
				"seller_name": character.name,
				"item": item.duplicate(),
				"base_valor": base_valor,
				"supply_category": drop_tables.get_supply_category(item),
				"listed_at": now,
				"quantity": 1
			}
			persistence.add_market_listing(post_id, listing)
			total_valor += base_valor
			count += 1
			to_remove.append(i)
		for i in to_remove:
			character.inventory.remove_at(i)

	elif list_type == "materials":
		# List all crafting materials
		var mat_keys = character.crafting_materials.keys().duplicate()
		for mat_name in mat_keys:
			var qty = int(character.crafting_materials.get(mat_name, 0))
			if qty <= 0:
				continue
			var mat_info = CraftingDatabaseScript.MATERIALS.get(mat_name, {})
			var mat_value = int(mat_info.get("value", 5))
			var per_unit_valor = maxi(1, int(mat_value / 3.0))
			var material_tier = int(mat_info.get("tier", _get_material_tier(mat_name)))
			var mat_total = per_unit_valor * qty
			if bonus > 0:
				mat_total = int(mat_total * (1.0 + bonus))
			var listing = {
				"account_id": account_id,
				"seller_name": character.name,
				"item": {"type": "material", "name": mat_name, "material_type": mat_name, "tier": material_tier},
				"base_valor": mat_total,
				"supply_category": "material_t%d" % material_tier,
				"listed_at": now,
				"quantity": qty
			}
			persistence.add_market_listing(post_id, listing)
			total_valor += mat_total
			count += 1
			character.crafting_materials[mat_name] = 0
		# Clean up zero entries
		for mat_name in mat_keys:
			if int(character.crafting_materials.get(mat_name, 0)) <= 0:
				character.crafting_materials.erase(mat_name)
	else:
		send_to_peer(peer_id, {"type": "market_error", "message": "Invalid list type."})
		return

	if count == 0:
		send_to_peer(peer_id, {"type": "market_error", "message": "Nothing to list!"})
		return

	persistence.add_valor(account_id, total_valor)
	save_character(peer_id)

	send_to_peer(peer_id, {
		"type": "market_list_all_success",
		"count": count,
		"total_valor": total_valor,
		"new_valor": persistence.get_valor(account_id)
	})
	send_character_update(peer_id)

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
		var scaled_quest = quest_db.get_quest(quest_id, character.level, completed_at_post, character.name)
		description = scaled_quest.get("description", "")

	var result = quest_mgr.accept_quest(character, quest_id, origin_x, origin_y, description, character.level, completed_at_post)

	if result.success:
		var quest = quest_db.get_quest(quest_id, character.level, completed_at_post, character.name)

		# For BOSS_HUNT quests with named bounty, register the bounty
		if quest.get("type") == quest_db.QuestType.BOSS_HUNT and quest.has("bounty_name"):
			active_bounties[quest_id] = {
				"x": int(quest.get("bounty_x", 0)),
				"y": int(quest.get("bounty_y", 0)),
				"monster_type": quest.get("bounty_monster_type", ""),
				"level": int(quest.get("bounty_level", character.level)),
				"name": quest.get("bounty_name", ""),
				"peer_id": peer_id,
			}
			log_message("Registered bounty '%s' at (%d, %d) for player %s" % [
				quest.get("bounty_name", ""), int(quest.get("bounty_x", 0)), int(quest.get("bounty_y", 0)), character.name])

		# For RESCUE quests, create a personal dungeon with rescue NPC
		if quest.get("type") == quest_db.QuestType.RESCUE:
			var rescue_dungeon_type = quest.get("dungeon_type", "")
			var rescue_instance_id = _create_player_dungeon_instance(peer_id, quest_id, rescue_dungeon_type, character.level)
			if rescue_instance_id != "":
				if not player_dungeon_instances.has(peer_id):
					player_dungeon_instances[peer_id] = {}
				player_dungeon_instances[peer_id][quest_id] = rescue_instance_id
				# Spawn rescue NPC on the designated floor
				var rescue_floor = int(quest.get("rescue_floor", 1))
				var rescue_npc_type = quest.get("rescue_npc_type", "merchant")
				_spawn_rescue_npc(rescue_instance_id, rescue_floor, rescue_npc_type, quest_id)
				log_message("Created rescue dungeon %s with %s NPC on floor %d for player %s" % [
					rescue_instance_id, rescue_npc_type, rescue_floor, character.name])

		# For DUNGEON_CLEAR quests, create a personal dungeon instance for this player
		if quest.get("type") == quest_db.QuestType.DUNGEON_CLEAR:
			var dungeon_type = quest.get("dungeon_type", "")
			var instance_id = _create_player_dungeon_instance(peer_id, quest_id, dungeon_type, character.level)
			if instance_id != "":
				# Store mapping of quest to dungeon instance for this player
				if not player_dungeon_instances.has(peer_id):
					player_dungeon_instances[peer_id] = {}
				player_dungeon_instances[peer_id][quest_id] = instance_id
				log_message("Created personal dungeon %s for player %s quest %s" % [instance_id, character.name, quest_id])

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
		# Clean up bounty if this was a bounty quest
		if active_bounties.has(quest_id):
			active_bounties.erase(quest_id)
		# Clean up rescue NPC data
		if player_dungeon_instances.has(peer_id) and player_dungeon_instances[peer_id].has(quest_id):
			var inst_id = player_dungeon_instances[peer_id][quest_id]
			if dungeon_npcs.has(inst_id):
				dungeon_npcs.erase(inst_id)
		# Clean up personal dungeon if this was a dungeon/rescue quest
		_cleanup_player_dungeon(peer_id, quest_id)

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
		elif quest.get("type") == quest_db.QuestType.EXPLORATION:
			# Exploration quests can be turned in at their destination too
			var destinations = quest.get("destinations", [])
			if tp.id in destinations:
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
			elif quest.get("type") == quest_db.QuestType.EXPLORATION:
				var destinations = quest.get("destinations", [])
				var dest_names = []
				for d in destinations:
					var dtp = trading_post_db.TRADING_POSTS.get(d, {})
					dest_names.append(dtp.get("name", d.replace("_", " ").capitalize()))
				send_to_peer(peer_id, {
					"type": "error",
					"message": "Turn in at %s or %s." % [
						required_tp.get("name", "the quest giver"),
						" / ".join(dest_names)
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
		# Party quest sync: auto-turn-in for members with same completed quest
		if _is_party_leader(peer_id):
			_sync_party_quest_turn_in(peer_id, quest_id, quest)
	else:
		send_to_peer(peer_id, {"type": "error", "message": result.message})

func handle_get_quest_log(peer_id: int):
	"""Send quest log to player with quest IDs for abandonment"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Build dungeon direction info for dungeon quests
	var extra_info = {}
	var active_quests_info = []
	for quest in character.active_quests:
		var qid = quest.get("quest_id", "")

		# Use stored data when available (prevents regeneration issues for random quests)
		var quest_name = quest.get("quest_name", "")
		var quest_type = quest.get("quest_type", -1)
		var description = quest.get("description", "")

		# Fall back to regeneration only if stored data is missing (legacy quests)
		if quest_name.is_empty() or quest_type < 0:
			var player_level = quest.get("player_level_at_accept", 1)
			var completed_at_post = quest.get("completed_at_post", 0)
			var quest_data = quest_db.get_quest(qid, player_level, completed_at_post)
			if quest_data:
				quest_name = quest_data.get("name", "Unknown Quest")
				quest_type = quest_data.get("type", -1)
				if description.is_empty():
					description = quest_data.get("description", "")

		# Add dungeon direction hints for dungeon quests
		if quest_type == quest_db.QuestType.DUNGEON_CLEAR:
			var direction_text = ""
			# Check for player's personal dungeon first
			var dungeon_info = _get_player_dungeon_info(peer_id, qid, character.x, character.y)
			if not dungeon_info.is_empty():
				direction_text = "[color=#00FFFF]Your dungeon:[/color] %s (%s)" % [
					dungeon_info.dungeon_name, dungeon_info.direction_text
				]
			else:
				# Use stored dungeon_type if available, otherwise try to get from quest data
				var dungeon_type = quest.get("dungeon_type", "")
				if dungeon_type.is_empty():
					var player_level = quest.get("player_level_at_accept", 1)
					var completed_at_post = quest.get("completed_at_post", 0)
					var quest_data = quest_db.get_quest(qid, player_level, completed_at_post)
					dungeon_type = quest_data.get("dungeon_type", "") if quest_data else ""

				if not dungeon_type.is_empty():
					var tier = 1 if qid.begins_with("haven_") else 0
					var nearest = _find_nearest_dungeon_for_quest(character.x, character.y, dungeon_type, tier)
					if not nearest.is_empty():
						direction_text = "[color=#00FFFF]Nearest dungeon:[/color] %s (%s)" % [
							nearest.dungeon_name, nearest.direction_text
						]
					else:
						direction_text = "[color=#808080]No matching dungeon found nearby. Explore the wilderness![/color]"

			if not direction_text.is_empty():
				extra_info[qid] = direction_text
				description += "\n\n" + direction_text

		# Add direction hints for exploration quests
		if quest_type == quest_db.QuestType.EXPLORATION:
			var destinations = quest.get("destinations", [])
			if destinations.is_empty():
				# Try to get from quest data
				var player_level_e = quest.get("player_level_at_accept", 1)
				var completed_at_post_e = quest.get("completed_at_post", 0)
				var quest_data_e = quest_db.get_quest(qid, player_level_e, completed_at_post_e)
				if quest_data_e:
					destinations = quest_data_e.get("destinations", [])
			if not destinations.is_empty():
				var direction_parts = []
				for dest_id in destinations:
					# Check if already visited (progress tracking)
					var visited_list = quest.get("visited", [])
					var already_visited = dest_id in visited_list
					if already_visited:
						continue
					var dest_coords = quest_db.TRADING_POST_COORDS.get(dest_id, Vector2i.ZERO)
					var dest_name = dest_id.replace("_", " ").capitalize()
					var dir_text = _get_direction_text(character.x, character.y, dest_coords.x, dest_coords.y)
					direction_parts.append("[color=#00FFFF]%s[/color] at (%d, %d) — %s" % [dest_name, dest_coords.x, dest_coords.y, dir_text])
				if not direction_parts.is_empty():
					description += "\n\n" + "\n".join(direction_parts)

		active_quests_info.append({
			"id": qid,
			"name": quest_name if not quest_name.is_empty() else "Unknown Quest",
			"progress": quest.get("progress", 0),
			"target": quest.get("target", 1),
			"description": description
		})

	var quest_log = quest_mgr.format_quest_log(character, extra_info)

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

# ===== BOUNTY & RESCUE SYSTEM =====

func _check_bounty_at_location(peer_id: int, x: int, y: int) -> bool:
	"""Check if player is at a bounty location. If so, start bounty combat. Returns true if combat started."""
	for quest_id in active_bounties:
		var bounty = active_bounties[quest_id]
		if bounty.peer_id == peer_id and bounty.x == x and bounty.y == y:
			_start_bounty_combat(peer_id, quest_id, bounty)
			return true
	return false

func _start_bounty_combat(peer_id: int, quest_id: String, bounty: Dictionary):
	"""Start combat with a named bounty target."""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var monster_type = bounty.get("monster_type", "Goblin")
	var bounty_level = int(bounty.get("level", character.level))
	var bounty_name = bounty.get("name", "Unknown")

	# Generate monster based on type and level
	var monster = monster_db.generate_monster_by_name(monster_type, bounty_level)

	# Apply elite variant bonuses: +25% HP, +15% ATK/DEF
	monster.max_hp = int(monster.max_hp * 1.25)
	monster.current_hp = monster.max_hp
	monster.strength = int(monster.strength * 1.15)
	monster.defense = int(monster.defense * 1.15)

	# Set the named bounty name
	monster["name"] = bounty_name
	monster["is_bounty"] = true

	# Track bounty quest ID in character for combat result processing
	character.set_meta("bounty_quest_id", quest_id)

	var result = combat_mgr.start_combat(peer_id, character, monster)

	if result.success:
		var monster_display_name = result.combat_state.get("monster_name", bounty_name)
		var combat_bg_color = combat_mgr.get_monster_combat_bg_color(monster_type)

		var intro_msg = "[color=#FF4500][b]You've found your bounty target![/b][/color]\n"
		intro_msg += "[color=#FFD700]%s stands before you, ready to fight![/color]\n\n" % bounty_name

		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": intro_msg + result.message,
			"combat_state": result.combat_state,
			"combat_bg_color": combat_bg_color,
			"use_client_art": true,
			"extra_combat_text": result.get("extra_combat_text", "")
		})

func _on_bounty_kill(peer_id: int, quest_id: String):
	"""Called when a bounty target is killed. Advances quest progress and cleans up."""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get the bounty name for cleanup logging
	var bounty_name = ""
	if active_bounties.has(quest_id):
		bounty_name = active_bounties[quest_id].get("name", "")

	# NOTE: Quest progress is already updated by check_kill_quest_progress() in the
	# combat victory handler (line ~2311). Do NOT call it again here or progress
	# will be double-counted (e.g. 2/1 instead of 1/1).

	# Remove from active bounties
	if active_bounties.has(quest_id):
		active_bounties.erase(quest_id)
		log_message("Bounty '%s' killed by %s" % [bounty_name, character.name])

func _spawn_rescue_npc(instance_id: String, floor_num: int, npc_type: String, quest_id: String):
	"""Spawn a rescue NPC on a specific floor of a dungeon instance."""
	if not dungeon_floors.has(instance_id) or not dungeon_floor_rooms.has(instance_id):
		return

	var floor_grids = dungeon_floors[instance_id]
	if floor_num >= floor_grids.size():
		floor_num = max(0, floor_grids.size() - 2)

	var grid = floor_grids[floor_num]
	var rooms = dungeon_floor_rooms[instance_id][floor_num]

	# Find a room position far from the entrance for the NPC
	var pos = _find_npc_spawn_position(grid, rooms)

	if not dungeon_npcs.has(instance_id):
		dungeon_npcs[instance_id] = {}

	dungeon_npcs[instance_id][floor_num] = {
		"x": pos.x, "y": pos.y,
		"npc_type": npc_type,
		"display_char": "?",
		"display_color": "#00FF00",
		"quest_id": quest_id,
		"rescued": false,
	}

func _find_npc_spawn_position(grid: Array, rooms: Array) -> Vector2i:
	"""Find a good spawn position for a rescue NPC (preferably in a room far from entrance)."""
	# Find entrance position
	var entrance_pos = _find_tile_position(grid, DungeonDatabaseScript.TileType.ENTRANCE)

	# Try to find a room center far from entrance
	var best_pos = Vector2i(1, 1)
	var best_dist = 0.0

	for room in rooms:
		var center_x = room.get("x", 0) + room.get("width", 2) / 2
		var center_y = room.get("y", 0) + room.get("height", 2) / 2
		# Ensure it's a walkable tile
		if center_y >= 0 and center_y < grid.size() and center_x >= 0 and center_x < grid[0].size():
			if grid[center_y][center_x] != DungeonDatabaseScript.TileType.WALL:
				var dx = center_x - entrance_pos.x
				var dy = center_y - entrance_pos.y
				var dist = sqrt(float(dx * dx + dy * dy))
				if dist > best_dist:
					best_dist = dist
					best_pos = Vector2i(center_x, center_y)

	return best_pos

func _get_dungeon_npc_at(instance_id: String, floor_num: int, x: int, y: int) -> Dictionary:
	"""Get rescue NPC at a specific position in a dungeon, or empty dict if none."""
	if not dungeon_npcs.has(instance_id):
		return {}
	var floor_npc = dungeon_npcs[instance_id].get(floor_num, {})
	if floor_npc.is_empty():
		return {}
	if floor_npc.x == x and floor_npc.y == y:
		return floor_npc
	return {}

func _trigger_rescue_encounter(peer_id: int, npc: Dictionary, instance_id: String):
	"""Trigger a rescue NPC encounter in a dungeon."""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	npc["rescued"] = true  # Mark so it won't re-trigger

	pending_rescue_encounters[peer_id] = npc
	var npc_type = npc.get("npc_type", "merchant")
	var quest_id = npc.get("quest_id", "")

	match npc_type:
		"merchant":
			var items = _generate_rescue_merchant_gear(character)
			npc["merchant_items"] = items  # Store for response handler
			send_to_peer(peer_id, {"type": "rescue_npc_encounter", "npc_type": "merchant",
				"message": "[color=#FFD700]A grateful merchant emerges from the shadows![/color]\n[color=#FFFFFF]\"Thank you for finding me! Please, take one of my finest wares as thanks!\"[/color]",
				"items": items, "player_valor": persistence.get_valor(peers[peer_id].account_id) if peers.has(peer_id) else 0})
		"healer":
			character.current_hp = character.get_total_max_hp()
			character.current_mana = character.get_total_max_mana()
			character.poison_active = false
			character.blind_active = false
			send_to_peer(peer_id, {"type": "rescue_npc_encounter", "npc_type": "healer",
				"message": "[color=#00FF00]A healer steps forward and fully restores you![/color]\n[color=#FFFFFF]\"You saved me! Let me heal all your wounds in return.\"[/color]"})
			send_character_update(peer_id)
		"blacksmith":
			_repair_all_equipment(peer_id)
			send_to_peer(peer_id, {"type": "rescue_npc_encounter", "npc_type": "blacksmith",
				"message": "[color=#FFA500]A blacksmith offers free repairs![/color]\n[color=#FFFFFF]\"I owe you my life! Let me fix all your gear for free.\"[/color]"})
			send_character_update(peer_id)
		"scholar":
			var bonus_xp = int(character.xp_to_next_level() * 0.5)
			character.add_experience(bonus_xp)
			send_to_peer(peer_id, {"type": "rescue_npc_encounter", "npc_type": "scholar",
				"message": "[color=#9966FF]A scholar shares ancient knowledge![/color]\n[color=#FFFFFF]\"For saving me, let me share what I've learned. +%d XP!\"[/color]" % bonus_xp})
			send_character_update(peer_id)
		"breeder":
			send_to_peer(peer_id, {"type": "rescue_npc_encounter", "npc_type": "breeder",
				"message": "[color=#A335EE]A companion breeder offers a rare egg![/color]\n[color=#FFFFFF]\"I was studying creatures here when I got trapped. Take this egg as thanks!\"[/color]"})

	# Mark quest progress
	if quest_id != "":
		var update = quest_mgr.check_rescue_progress(character, quest_id)
		if update.get("updated", false):
			send_to_peer(peer_id, {
				"type": "quest_progress",
				"quest_id": quest_id,
				"progress": update.progress,
				"target": update.target,
				"completed": update.completed,
				"message": update.message
			})

	save_character(peer_id)

func _generate_rescue_merchant_gear(character) -> Array:
	"""Generate 3 class-appropriate items for rescue merchant reward."""
	var items = []
	var level = character.level
	var tier = _get_tier_from_player_level(level)
	var tier_key = "tier%d" % tier
	for _i in range(3):
		var item_level = maxi(1, level + randi_range(-3, 3))
		# Try rolling from the tier drop table first
		var rolled = drop_tables.roll_drops(tier_key, 100, item_level)
		var item: Dictionary = {}
		if rolled.size() > 0:
			item = rolled[0]
		else:
			# Fallback - generate based on class
			var class_type = character.class_type if character.class_type else "Fighter"
			if class_type in ["Fighter", "Barbarian", "Paladin"]:
				item = drop_tables.generate_fallback_item("weapon", item_level)
			elif class_type in ["Wizard", "Sorcerer", "Sage"]:
				item = drop_tables.generate_fallback_item("ring", item_level)
			else:
				item = drop_tables.generate_fallback_item("armor", item_level)
		if not item.is_empty():
			# Boost quality - guaranteed rare or better
			if item.get("rarity", "common") in ["common", "uncommon"]:
				item["rarity"] = "rare"
			items.append(item)
	return items

func _get_tier_from_player_level(level: int) -> int:
	"""Get monster tier from player level."""
	if level <= 5: return 1
	elif level <= 15: return 2
	elif level <= 30: return 3
	elif level <= 50: return 4
	elif level <= 100: return 5
	elif level <= 500: return 6
	elif level <= 2000: return 7
	elif level <= 5000: return 8
	else: return 9

func _repair_all_equipment(peer_id: int):
	"""Repair all equipped items for a player (free)."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	for slot in ["weapon", "shield", "helm", "chest", "legs", "ring", "amulet"]:
		var item = character.get_equipped(slot)
		if item and item is Dictionary and item.has("durability"):
			var max_dur = item.get("max_durability", item.get("durability", 100))
			item["durability"] = max_dur

func handle_rescue_npc_response(peer_id: int, message: Dictionary):
	"""Handle player's response to rescue NPC encounter."""
	if not characters.has(peer_id):
		return
	if not pending_rescue_encounters.has(peer_id):
		return

	var npc = pending_rescue_encounters[peer_id]
	var npc_type = npc.get("npc_type", "")
	var action = message.get("action", "accept")
	var character = characters[peer_id]

	match npc_type:
		"merchant":
			if action == "accept":
				var item_index = int(message.get("item_index", 0))
				# Use stored items from the encounter trigger
				var merchant_items = npc.get("merchant_items", [])
				if merchant_items.is_empty():
					merchant_items = _generate_rescue_merchant_gear(character)
				if item_index >= 0 and item_index < merchant_items.size():
					var selected_item = merchant_items[item_index]
					if character.add_item(selected_item):
						send_to_peer(peer_id, {"type": "text",
							"message": "[color=#00FF00]You received: %s[/color]" % selected_item.get("name", "item")})
					else:
						send_to_peer(peer_id, {"type": "text",
							"message": "[color=#FF4444]Your inventory is full![/color]"})
		"breeder":
			if action == "accept":
				# Pick a random monster from the player's tier and generate an egg
				var tier = _get_tier_from_player_level(character.level)
				var tier_monsters = []
				for monster_name in drop_tables.COMPANION_DATA:
					if drop_tables.COMPANION_DATA[monster_name].get("tier", 0) == tier:
						tier_monsters.append(monster_name)
				if tier_monsters.size() > 0:
					var chosen = tier_monsters[randi() % tier_monsters.size()]
					var egg = drop_tables.get_egg_for_monster(chosen)
					if not egg.is_empty():
						character.incubating_eggs.append(egg)
						send_to_peer(peer_id, {"type": "text",
							"message": "[color=#A335EE]You received a %s Egg![/color]" % egg.get("monster_type", "Mystery")})
					else:
						send_to_peer(peer_id, {"type": "text",
							"message": "[color=#FF4444]The breeder had no eggs to offer.[/color]"})
				else:
					send_to_peer(peer_id, {"type": "text",
						"message": "[color=#FF4444]The breeder had no eggs to offer.[/color]"})

	pending_rescue_encounters.erase(peer_id)
	save_character(peer_id)

	# Send dungeon state to continue exploration
	if character.in_dungeon:
		_send_dungeon_state(peer_id)
	send_character_update(peer_id)

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
	var companion_id_input = message.get("id", "").strip_edges()
	var companion_name_input = message.get("name", "").strip_edges()

	if companion_id_input.is_empty() and companion_name_input.is_empty():
		send_to_peer(peer_id, {"type": "error", "message": "Please specify a companion to activate."})
		return

	# First check hatched companions (new egg system)
	var hatched_companions = character.get_collected_companions()
	var matched_hatched = {}

	# Priority 1: Match by unique ID (handles duplicates correctly)
	if not companion_id_input.is_empty():
		for comp in hatched_companions:
			if comp.get("id", "") == companion_id_input:
				matched_hatched = comp
				break

	# Priority 2: Fall back to name matching (legacy/command support)
	if matched_hatched.is_empty() and not companion_name_input.is_empty():
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
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Visit More → Companions to see your companions.[/color]"})
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

func handle_debug_hatch(peer_id: int):
	"""Debug command to hatch a random companion with a random variant pattern"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Pick a random monster type from COMPANION_DATA
	var companion_types = DropTables.COMPANION_DATA.keys()
	var random_type = companion_types[randi() % companion_types.size()]
	var companion_info = DropTables.COMPANION_DATA[random_type]

	# Create a fake egg and hatch it
	var fake_egg = {
		"monster_type": random_type,
		"companion_name": companion_info.companion_name,
		"tier": companion_info.tier,
		"bonuses": companion_info.bonuses.duplicate()
	}

	var hatched = character._hatch_egg(fake_egg)

	# Auto-activate the new companion
	character.activate_hatched_companion(hatched.id)

	var pattern_desc = hatched.get("variant_pattern", "solid")
	var color2 = hatched.get("variant_color2", "")
	if color2 != "":
		pattern_desc += " (%s + %s)" % [hatched.variant_color, color2]

	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00]DEBUG: Hatched %s (%s) with %s variant![/color]\nPattern: %s" % [hatched.name, random_type, hatched.variant, pattern_desc]})
	send_character_update(peer_id)
	save_character(peer_id)

func handle_release_companion(peer_id: int, message: Dictionary):
	"""Handle permanently releasing (deleting) a companion"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var companion_id = message.get("id", "")

	if companion_id == "":
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000]Invalid companion.[/color]"})
		return

	# Check if trying to release the active companion
	var active = character.get_active_companion()
	if not active.is_empty() and active.get("id", "") == companion_id:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000]Cannot release your active companion! Dismiss it first.[/color]"})
		return

	# Find and remove the companion
	var released_name = ""
	var released_variant = ""
	for i in range(character.collected_companions.size()):
		if character.collected_companions[i].get("id", "") == companion_id:
			released_name = character.collected_companions[i].get("name", "Unknown")
			released_variant = character.collected_companions[i].get("variant", "Normal")
			character.collected_companions.remove_at(i)
			break

	if released_name != "":
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FFA500]Released %s %s. Farewell, friend.[/color]" % [released_variant, released_name]})
		send_character_update(peer_id)
		save_character(peer_id)
	else:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000]Companion not found.[/color]"})

func handle_release_all_companions(peer_id: int):
	"""Handle releasing ALL companions at once"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Dismiss active companion first if any
	if character.has_active_companion():
		character.dismiss_companion()

	# Count companions before release
	var count = character.collected_companions.size()

	if count == 0:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]No companions to release.[/color]"})
		return

	# Clear all companions
	character.collected_companions.clear()

	send_to_peer(peer_id, {"type": "text", "message": "[color=#FF6666]Released all %d companions. They have been set free.[/color]" % count})
	send_character_update(peer_id)
	save_character(peer_id)

func handle_toggle_egg_freeze(peer_id: int, message: Dictionary):
	"""Handle toggling the frozen state of an egg"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var egg_index = message.get("index", -1)

	if egg_index < 0 or egg_index >= character.incubating_eggs.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid egg index."})
		return

	var egg = character.incubating_eggs[egg_index]
	var is_frozen = egg.get("frozen", false)

	# Toggle frozen state
	egg["frozen"] = not is_frozen
	var new_state = egg["frozen"]

	var monster_type = egg.get("monster_type", "Unknown")
	if new_state:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#00BFFF]You freeze your %s egg. It will no longer hatch until unfrozen.[/color]" % monster_type
		})
	else:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FFA500]You unfreeze your %s egg. It will resume hatching when you walk.[/color]" % monster_type
		})

	send_character_update(peer_id)
	save_character(peer_id)

# ===== TITLE SYSTEM =====

# ===== UNIFIED GATHERING SYSTEM (3-Choice Until-Fail) =====

const GATHERING_NODE_TO_JOB = {
	"water": "fishing", "fishing": "fishing",
	"stone": "mining", "ore_vein": "mining", "mining": "mining",
	"tree": "logging", "dense_brush": "logging", "logging": "logging",
	"herb": "foraging", "flower": "foraging", "mushroom": "foraging",
	"bush": "foraging", "reed": "foraging", "foraging": "foraging",
}

const GATHERING_OPTION_LABELS = {
	"mining": [
		["Strike the fault line", "Use the wedge tool", "Try the softer seam"],
		["Chisel the vein", "Hammer the crack", "Pick the edge"],
		["Drill deep", "Score the surface", "Pry the slab"],
	],
	"logging": [
		["Cut from the north side", "Score the bark first", "Fell toward the clearing"],
		["Use the crosscut", "Chop the knot", "Saw the base"],
		["Split along the grain", "Notch the trunk", "Trim the branch"],
	],
	"foraging": [
		["Pick from the base", "Trim the upper leaves", "Dig around the roots"],
		["Check under the canopy", "Pull the stems", "Brush the soil"],
		["Snip the bud", "Uproot gently", "Shake the stalk"],
	],
	"fishing": [
		["Cast toward the ripple", "Try deeper water", "Switch to live bait"],
		["Jig the line", "Float downstream", "Troll the shallows"],
		["Set the hook fast", "Wait for the pull", "Use a different lure"],
	],
}

# Plant names for foraging discovery system — 10 per tier, used as option labels
const FORAGING_PLANT_NAMES = {
	1: ["River Mint", "Clover Tuft", "Dandelion Root", "Wild Garlic", "Meadow Sage",
		"Chickweed", "Lamb's Ear", "Shepherd's Purse", "Yarrow", "Plantain Leaf",
		"Foxglove", "Nightshade Bud", "Bitter Root", "Thorn Berry", "Dead Nettle",
		"Swamp Moss", "Crab Grass", "Milkweed Pod", "Ragwort", "Stinkhorn"],
	2: ["Fire Blossom", "Cave Moss", "Thornberry", "Ghost Lily", "Iron Fern",
		"Moon Petal", "Silverleaf", "Stoneflower", "Amber Root", "Dustcap Shroom",
		"Witch Hazel", "Bogbean", "Rust Lichen", "Sour Stem", "Blister Vine",
		"Deadman's Finger", "Rot Blossom", "Ash Fungus", "Cracked Cap", "Dry Thistle"],
	3: ["Sunstone Herb", "Crystal Moss", "Windbloom", "Frost Fern", "Thunder Root",
		"Storm Petal", "Glowcap", "Starleaf", "Ember Moss", "Twilight Orchid",
		"False Prophet", "Mirror Vine", "Phantom Grass", "Echo Bloom", "Shade Thorn",
		"Hollow Reed", "Mirage Petal", "Fools Gold Flower", "Wilt Weed", "Pale Spore"],
	4: ["Dragon Tongue", "Mithril Bloom", "Arcane Thistle", "Shadow Fern", "Phoenix Petal",
		"Runic Clover", "Essence Vine", "Spirit Moss", "Warden's Herb", "Void Blossom",
		"Demon Thorn", "Blood Orchid", "Cursed Root", "Bane Berry", "Lich Moss",
		"Soul Weed", "Grave Bloom", "Wraith Fern", "Plague Stem", "Hex Flower"],
	5: ["Celestial Sage", "Titan Root", "Astral Bloom", "Elder Moss", "Mythic Fern",
		"Primal Orchid", "Ancient Vine", "Divine Petal", "Eternal Herb", "Radiant Leaf",
		"Fallen Star Bloom", "Abyssal Spore", "Chaos Vine", "Nether Root", "Doom Petal",
		"Corrupt Moss", "Void Fern", "Oblivion Herb", "Shadow Bloom", "Dark Sage"],
	6: ["Godtear Bloom", "World Root", "Primordial Fern", "Genesis Flower", "Omega Moss",
		"Creation Vine", "Eternity Petal", "Infinity Herb", "Transcendent Leaf", "Ascendant Bloom",
		"Entropy Spore", "Cataclysm Root", "Annihilation Fern", "Void Heart", "Ruin Blossom",
		"Collapse Vine", "Extinction Moss", "Decay Petal", "Blight Root", "End Bloom"],
}

# Size categories for fishing trophy catch system
const FISHING_SIZE_WEIGHTS = {
	"small": 40,
	"medium": 35,
	"large": 20,
	"trophy": 5,
}
const FISHING_SIZE_QTY_MULT = {"small": 1, "medium": 1, "large": 2, "trophy": 3}

# Logging momentum milestone thresholds
const LOGGING_MOMENTUM_MILESTONES = {3: 1, 5: 2, 7: 3}

func handle_gathering_start(peer_id: int, message: Dictionary):
	"""Handle player starting a gathering session at a node."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]

	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You cannot gather while in combat![/color]"})
		return

	if active_gathering.has(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You are already gathering![/color]"})
		return

	var node_type = message.get("node_type", "")
	var gathering_node = get_gathering_node_nearby(character.x, character.y)
	if gathering_node.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]No gathering node nearby![/color]"})
		return

	var job_type = GATHERING_NODE_TO_JOB.get(node_type, GATHERING_NODE_TO_JOB.get(gathering_node.get("type", ""), ""))
	if job_type == "":
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Unknown gathering type![/color]"})
		return

	var tier = gathering_node.get("tier", 1)
	var job_level = character.job_levels.get(job_type, 1)
	var hint_strength = minf(1.0, float(job_level) / 100.0)

	# Apply companion gathering_hint bonus (additive percentage)
	var companion_hint = character.get_companion_bonus("gathering_hint")
	if companion_hint > 0:
		hint_strength = minf(1.0, hint_strength + (companion_hint / 100.0))

	# Check tool availability
	var tool_subtype = _get_tool_subtype_for_job(job_type)
	var tool = _find_tool_in_inventory(character, tool_subtype)
	var has_tool = not tool.is_empty()

	# Generate first round
	var session = _generate_gathering_round(job_type, tier, hint_strength, 0, [])
	session["job_type"] = job_type
	session["node_type"] = gathering_node.get("type", node_type)
	session["tier"] = tier
	session["chain_count"] = 0
	session["chain_materials"] = []
	session["has_tool"] = has_tool
	var tool_bonuses = tool.get("tool_bonuses", {}) if has_tool else {}
	# Reveals: int count (new) or boolean (old tools backwards compat)
	var max_reveals = tool_bonuses.get("reveals", 1 if tool_bonuses.get("reveal", false) else 0) if has_tool else 0
	session["reveals_remaining"] = max_reveals
	session["max_reveals"] = max_reveals
	var max_saves = tool.get("max_saves", 1) if has_tool else 0
	session["saves_remaining"] = max_saves
	session["max_saves"] = max_saves
	# Store actual node coordinates (may differ from player position for adjacent gathering)
	session["node_x"] = gathering_node.get("node_x", character.x)
	session["node_y"] = gathering_node.get("node_y", character.y)
	# Per-type bonus tracking
	session["momentum"] = 0          # Logging: consecutive correct picks
	session["discoveries"] = []      # Foraging: discovered plant names this session
	active_gathering[peer_id] = session

	send_to_peer(peer_id, {
		"type": "gathering_round",
		"options": session["client_options"],
		"risky_available": session["risky_available"],
		"hint_strength": hint_strength,
		"chain_count": 0,
		"job_type": job_type,
		"node_type": session["node_type"],
		"tier": tier,
		"tool_available": has_tool and max_reveals > 0,
		"saves_remaining": max_saves,
		"reveals_remaining": max_reveals,
		"momentum": 0,
		"discoveries": [],
	})

func _start_bump_gathering(peer_id: int, character, gathering_node: Dictionary):
	"""Start gathering when player bumps into a blocking gathering node."""
	if combat_mgr.is_in_combat(peer_id):
		return
	if active_gathering.has(peer_id):
		return

	var node_type = gathering_node.get("type", "")
	var job_type = GATHERING_NODE_TO_JOB.get(node_type, gathering_node.get("job", ""))
	if job_type == "":
		return

	var tier = gathering_node.get("tier", 1)
	var job_level = character.job_levels.get(job_type, 1)
	var hint_strength = minf(1.0, float(job_level) / 100.0)

	var companion_hint = character.get_companion_bonus("gathering_hint")
	if companion_hint > 0:
		hint_strength = minf(1.0, hint_strength + (companion_hint / 100.0))

	var tool_subtype = _get_tool_subtype_for_job(job_type)
	var tool = _find_tool_in_inventory(character, tool_subtype)
	var has_tool = not tool.is_empty()

	var session = _generate_gathering_round(job_type, tier, hint_strength, 0, [])
	session["job_type"] = job_type
	session["node_type"] = node_type
	session["tier"] = tier
	session["chain_count"] = 0
	session["chain_materials"] = []
	session["has_tool"] = has_tool
	var bump_tool_bonuses = tool.get("tool_bonuses", {}) if has_tool else {}
	var bump_max_reveals = bump_tool_bonuses.get("reveals", 1 if bump_tool_bonuses.get("reveal", false) else 0) if has_tool else 0
	session["reveals_remaining"] = bump_max_reveals
	session["max_reveals"] = bump_max_reveals
	var bump_max_saves = tool.get("max_saves", 1) if has_tool else 0
	session["saves_remaining"] = bump_max_saves
	session["max_saves"] = bump_max_saves
	session["node_x"] = gathering_node.get("node_x", character.x)
	session["node_y"] = gathering_node.get("node_y", character.y)
	# Per-type bonus tracking
	session["momentum"] = 0
	session["discoveries"] = []
	active_gathering[peer_id] = session

	send_to_peer(peer_id, {
		"type": "gathering_round",
		"options": session["client_options"],
		"risky_available": session["risky_available"],
		"hint_strength": hint_strength,
		"chain_count": 0,
		"job_type": job_type,
		"node_type": node_type,
		"tier": tier,
		"tool_available": has_tool and bump_max_reveals > 0,
		"saves_remaining": bump_max_saves,
		"reveals_remaining": bump_max_reveals,
		"momentum": 0,
		"discoveries": [],
	})

func _generate_gathering_round(job_type: String, tier: int, hint_strength: float, chain: int, discoveries: Array = []) -> Dictionary:
	"""Generate a gathering round with 3 options (1 correct, 2 wrong) + optional risky."""
	var correct_idx = randi() % 3

	# Foraging uses plant names from discovery system
	var shuffled: Array = []
	var correct_plant_name: String = ""
	if job_type == "foraging" and FORAGING_PLANT_NAMES.has(tier):
		var all_plants = FORAGING_PLANT_NAMES[tier]
		# First 10 are "correct" plants, rest are decoys
		var correct_pool = all_plants.slice(0, 10)
		var decoy_pool = all_plants.slice(10)
		# Pick 1 correct and 2 decoy, avoiding repeats
		var correct_pick = correct_pool[randi() % correct_pool.size()]
		correct_plant_name = correct_pick
		var decoys = decoy_pool.duplicate()
		decoys.shuffle()
		var picked_decoys = [decoys[0], decoys[1]]
		# Build labels array with correct at the right index
		for i in range(3):
			if i == correct_idx:
				shuffled.append(correct_pick)
			else:
				shuffled.append(picked_decoys.pop_back())
	else:
		var labels_pool = GATHERING_OPTION_LABELS.get(job_type, [["Option A", "Option B", "Option C"]])
		var label_set = labels_pool[chain % labels_pool.size()]
		shuffled = label_set.duplicate()
		shuffled.shuffle()

	var options = []
	for i in range(3):
		var opt_data = {
			"label": shuffled[i],
			"id": i,
			"correct": i == correct_idx,
			"risky": false,
			"hint": 1.0 if i == correct_idx else 0.0,
		}
		# For foraging, mark if this plant was previously discovered
		if job_type == "foraging" and shuffled[i] in discoveries:
			opt_data["known"] = true
		options.append(opt_data)

	# 10% chance for risky 4th option
	var risky_available = randf() < 0.10
	if risky_available:
		var risky_correct = randf() < 0.35  # 35% chance risky is correct
		options.append({
			"label": "Risky Gamble",
			"id": 3,
			"correct": risky_correct,
			"risky": true,
			"hint": 0.0,
		})

	# Build client-safe options (no correct/hint data)
	var client_options = []
	for opt in options:
		var co = {"label": opt["label"], "id": opt["id"]}
		if opt["risky"]:
			co["risky"] = true
		if opt.get("known", false):
			co["known"] = true
		client_options.append(co)

	var result = {
		"options": options,
		"client_options": client_options,
		"correct_id": correct_idx,
		"risky_available": risky_available,
	}
	if correct_plant_name != "":
		result["correct_plant_name"] = correct_plant_name
	return result

func handle_gathering_choice(peer_id: int, message: Dictionary):
	"""Handle player picking an option during gathering."""
	if not characters.has(peer_id):
		return
	if not active_gathering.has(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You are not gathering![/color]"})
		return

	var character = characters[peer_id]
	var session = active_gathering[peer_id]
	var choice_id = message.get("choice_id", -1)

	# Handle string commands first (JSON may send numbers as float)
	var choice_str = str(choice_id)  # Safe string conversion for comparison
	if choice_str == "continue":
		var job_type = session["job_type"]
		var tier = session["tier"]
		var job_level = character.job_levels.get(job_type, 1)
		var hint_strength = minf(1.0, float(job_level) / 100.0)
		var chain = session["chain_count"]

		# After a tool save, narrow options: remove the wrong choice player picked, keep correct answer
		if session.has("last_wrong_id"):
			var wrong_id = session["last_wrong_id"]
			var remaining_options = []
			var remaining_client = []
			for opt in session["options"]:
				if int(opt["id"]) != wrong_id:
					remaining_options.append(opt)
			for opt in session["client_options"]:
				if int(opt["id"]) != wrong_id:
					remaining_client.append(opt)
			session["options"] = remaining_options
			session["client_options"] = remaining_client
			session.erase("last_wrong_id")
			# Update correct_id to match new array index after filtering
			for i in range(remaining_options.size()):
				if remaining_options[i].get("correct", false):
					session["correct_id"] = i
					break

			send_to_peer(peer_id, {
				"type": "gathering_round",
				"options": remaining_client,
				"risky_available": session["risky_available"],
				"hint_strength": hint_strength,
				"chain_count": chain,
				"job_type": session["job_type"],
				"node_type": session["node_type"],
				"tier": tier,
				"tool_available": session.get("has_tool", false) and session.get("reveals_remaining", 0) > 0,
				"saves_remaining": session.get("saves_remaining", 0),
				"reveals_remaining": session.get("reveals_remaining", 0),
				"momentum": session.get("momentum", 0),
				"discoveries": session.get("discoveries", []),
			})
		else:
			# Normal continue after correct answer — generate fresh round
			var disc = session.get("discoveries", [])
			var new_round = _generate_gathering_round(job_type, tier, hint_strength, chain, disc)
			session["options"] = new_round["options"]
			session["client_options"] = new_round["client_options"]
			session["correct_id"] = new_round["correct_id"]
			session["risky_available"] = new_round["risky_available"]
			if new_round.has("correct_plant_name"):
				session["correct_plant_name"] = new_round["correct_plant_name"]

			send_to_peer(peer_id, {
				"type": "gathering_round",
				"options": new_round["client_options"],
				"risky_available": new_round["risky_available"],
				"hint_strength": hint_strength,
				"chain_count": chain,
				"job_type": session["job_type"],
				"node_type": session["node_type"],
				"tier": tier,
				"tool_available": session.get("has_tool", false) and session.get("reveals_remaining", 0) > 0,
				"saves_remaining": session.get("saves_remaining", 0),
				"reveals_remaining": session.get("reveals_remaining", 0),
				"momentum": session.get("momentum", 0),
				"discoveries": disc,
			})
		return

	# Handle "reveal" (tool use)
	if choice_str == "reveal":
		var reveals_left = session.get("reveals_remaining", 0)
		if session.get("has_tool", false) and reveals_left > 0:
			session["reveals_remaining"] = reveals_left - 1
			var correct_id = session["correct_id"]
			send_to_peer(peer_id, {
				"type": "gathering_round",
				"options": session["client_options"],
				"risky_available": session["risky_available"],
				"hint_strength": 1.0,
				"chain_count": session["chain_count"],
				"job_type": session["job_type"],
				"node_type": session["node_type"],
				"tier": session["tier"],
				"tool_available": session["reveals_remaining"] > 0,
				"reveals_remaining": session["reveals_remaining"],
				"revealed_correct": correct_id,
			})
		return

	# Normal choice — always cast to int (JSON sends numbers as float)
	choice_id = int(choice_id)

	var options = session.get("options", [])
	var chosen_option = null
	for opt in options:
		if int(opt["id"]) == choice_id:
			chosen_option = opt
			break

	if chosen_option == null:
		return

	var correct = chosen_option.get("correct", false)
	var is_risky = chosen_option.get("risky", false)
	var job_type = session["job_type"]
	var tier = session["tier"]

	if correct:
		# Roll reward
		var job_level = character.job_levels.get(job_type, 1)
		var depth_bonus = false
		var catch_size = ""
		var momentum_bonus_qty = 0
		var is_discovery = false

		# === MINING: Deep Vein — higher tier chance at depth 3+ ===
		var effective_tier = tier
		if job_type == "mining":
			var depth = session["chain_count"] + 1  # This round counts
			if depth >= 5 and randf() < 0.50 and tier < 9:
				effective_tier = tier + 1
				depth_bonus = true
			elif depth >= 3 and randf() < 0.25 and tier < 9:
				effective_tier = tier + 1
				depth_bonus = true

		var reward = _roll_gathering_reward(job_type, effective_tier, job_level, is_risky)
		var qty = reward.get("qty", 1)

		# === FISHING: Trophy Catch — size roll affects quantity ===
		if job_type == "fishing":
			var trophy_chance = mini(15, 5 + int(job_level / 20))
			var size_roll = randi() % 100
			if size_roll < trophy_chance:
				catch_size = "trophy"
			elif size_roll < trophy_chance + 20:
				catch_size = "large"
			elif size_roll < trophy_chance + 20 + 35:
				catch_size = "medium"
			else:
				catch_size = "small"
			qty *= FISHING_SIZE_QTY_MULT.get(catch_size, 1)
			# Trophy gives bonus rare material from same tier
			if catch_size == "trophy":
				var bonus_reward = _roll_gathering_reward("fishing", tier, job_level, false)
				var bonus_qty = 1
				_add_gathering_reward(character, bonus_reward, bonus_qty)
				session["chain_materials"].append({"id": bonus_reward["id"], "name": bonus_reward["name"], "qty": bonus_qty, "type": bonus_reward.get("type", "")})

		# === LOGGING: Momentum — track consecutive correct ===
		if job_type == "logging":
			session["momentum"] = session.get("momentum", 0) + 1
			var mom = session["momentum"]
			# Check milestones: 3=1, 5=2, 7=3 bonus materials
			if LOGGING_MOMENTUM_MILESTONES.has(mom):
				momentum_bonus_qty = LOGGING_MOMENTUM_MILESTONES[mom]
				# Auto-award bonus materials (same type as current reward)
				var bonus_added = _add_gathering_reward(character, reward, momentum_bonus_qty)
				session["chain_materials"].append({"id": reward["id"], "name": reward["name"], "qty": momentum_bonus_qty, "type": reward.get("type", "")})
				# At momentum 7, also chance for next-tier material
				if mom >= 7 and tier < 9 and randf() < 0.30:
					var high_reward = _roll_gathering_reward("logging", tier + 1, job_level, false)
					_add_gathering_reward(character, high_reward, 1)
					session["chain_materials"].append({"id": high_reward["id"], "name": high_reward["name"], "qty": 1, "type": high_reward.get("type", "")})

		# === FORAGING: Discovery — track first-time plant finds ===
		if job_type == "foraging":
			var plant_name = session.get("correct_plant_name", "")
			if plant_name != "" and plant_name not in session.get("discoveries", []):
				is_discovery = true
				session["discoveries"].append(plant_name)
				qty += 1  # Bonus qty for new discovery

		# Apply house gathering bonus
		var gathering_bonus = character.house_bonuses.get("gathering_bonus", 0)
		if gathering_bonus > 0:
			qty += maxi(1, int(qty * gathering_bonus))

		# Apply companion gathering_yield bonus (% chance for +1)
		var companion_yield = character.get_companion_bonus("gathering_yield")
		var companion_extra = false
		if companion_yield > 0 and randf() * 100.0 < companion_yield:
			qty += 1
			companion_extra = true

		# Add to material pouch (or inventory for treasure chests)
		var actually_added = _add_gathering_reward(character, reward, qty)
		var pouch_overflow = actually_added < qty

		session["chain_count"] += 1
		session["chain_materials"].append({"id": reward["id"], "name": reward["name"], "qty": qty, "type": reward.get("type", "")})

		var msg = "[color=#1EFF00]Correct![/color]"
		if is_risky:
			msg = "[color=#FFD700]★ Risky Gamble pays off! Double reward! ★[/color]"
		if companion_extra:
			var comp_name = character.get_active_companion().get("name", "Companion")
			msg += "\n[color=#A335EE]%s found extra materials! +1[/color]" % comp_name
		if pouch_overflow:
			msg += "\n[color=#FF4444]Pouch full! Some materials lost (cap: 999)[/color]"

		var result_msg = {
			"type": "gathering_result",
			"correct": true,
			"material": {"id": reward["id"], "name": reward["name"], "qty": qty},
			"chain_count": session["chain_count"],
			"chain_materials": session["chain_materials"],
			"continue": true,
			"message": msg,
			"tool_saved": false,
			"momentum": session.get("momentum", 0),
			"discoveries": session.get("discoveries", []),
			"correct_index": session.get("correct_id", -1),
		}
		# Per-type bonus flags
		if depth_bonus:
			result_msg["depth_bonus"] = true
		if catch_size != "":
			result_msg["catch_size"] = catch_size
		if momentum_bonus_qty > 0:
			result_msg["momentum_bonus"] = momentum_bonus_qty
		if is_discovery:
			result_msg["is_discovery"] = true
		send_to_peer(peer_id, result_msg)
	else:
		# Wrong answer — reset logging momentum (even on tool save)
		if job_type == "logging":
			session["momentum"] = 0
		var tool_saved = false

		# Check tool save (only if not risky and saves remaining)
		if not is_risky and session.get("has_tool", false) and session.get("saves_remaining", 0) > 0:
			session["saves_remaining"] -= 1
			tool_saved = true

		if tool_saved:
			# Store which option was wrong so "continue" can narrow options
			session["last_wrong_id"] = choice_id
			var remaining = session.get("saves_remaining", 0)
			var save_msg = "[color=#00FFFF]Your tool absorbed the mistake![/color]"
			if remaining > 0:
				save_msg += " [color=#808080](%d save(s) left)[/color]" % remaining
			send_to_peer(peer_id, {
				"type": "gathering_result",
				"correct": false,
				"material": {},
				"chain_count": session["chain_count"],
				"chain_materials": session["chain_materials"],
				"continue": true,
				"message": save_msg,
				"tool_saved": true,
				"saves_remaining": remaining,
				"correct_index": session.get("correct_id", -1),
			})
		else:
			# Check risky penalty
			if is_risky and session["chain_materials"].size() > 0:
				var lost_count = max(1, session["chain_materials"].size() / 2)
				var lost_materials = []
				for i in range(lost_count):
					if session["chain_materials"].size() > 0:
						var lost = session["chain_materials"].pop_back()
						lost_materials.append(lost)
						# Remove from character (inventory for treasure chests, materials for everything else)
						_remove_gathering_reward(character, lost["id"], lost["qty"], lost.get("type", ""))

				var msg = "[color=#FF4444]Risky Gamble failed! Lost %d materials from your chain![/color]" % lost_count
				# End session
				_end_gathering_session(peer_id, msg)
			else:
				# Still give a base reward (1x material) on failure
				var fail_reward = _roll_gathering_reward(job_type, tier, character.job_levels.get(job_type, 1), false)
				var fail_qty = 1
				_add_gathering_reward(character, fail_reward, fail_qty)
				session["chain_materials"].append({"id": fail_reward["id"], "name": fail_reward["name"], "qty": fail_qty, "type": fail_reward.get("type", "")})
				_end_gathering_session(peer_id, "[color=#FF4444]Wrong choice! Your gathering chain ends.[/color]\n[color=#808080]You still managed to gather 1x %s.[/color]" % fail_reward["name"])

func _end_gathering_session(peer_id: int, fail_message: String = ""):
	"""End a gathering session and send complete summary."""
	if not active_gathering.has(peer_id):
		return
	if not characters.has(peer_id):
		active_gathering.erase(peer_id)
		return

	var character = characters[peer_id]
	var session = active_gathering[peer_id]
	var chain_materials = session.get("chain_materials", [])
	var job_type = session.get("job_type", "")
	var tier = session.get("tier", 1)
	var chain_count = session.get("chain_count", 0)

	# Calculate job XP: base per round * tier multiplier
	var base_xp_per_round = 35 + (tier - 1) * 25  # T1=35, T2=60, ... T6=160
	var total_job_xp = base_xp_per_round * chain_count
	var job_result = character.add_job_xp(job_type, total_job_xp)
	var char_xp = job_result.get("char_xp_gained", 0)
	if char_xp > 0:
		character.add_experience(char_xp)

	# Consume tool durability if tool was used
	var saves_used = session.get("max_saves", 1) - session.get("saves_remaining", 0)
	var reveals_used = session.get("max_reveals", 0) - session.get("reveals_remaining", 0)
	if session.get("has_tool", false) and (reveals_used > 0 or saves_used > 0):
		var tool_subtype = _get_tool_subtype_for_job(job_type)
		_consume_tool_durability(peer_id, character, tool_subtype)

	# Deplete gathering node (use stored node coordinates for adjacent gathering)
	deplete_gathering_node(session.get("node_x", character.x), session.get("node_y", character.y), session.get("node_type", ""))

	# Aggregate materials for display
	var mat_summary = {}
	for mat in chain_materials:
		var mid = mat["id"]
		if not mat_summary.has(mid):
			mat_summary[mid] = {"name": mat["name"], "qty": 0}
		mat_summary[mid]["qty"] += mat["qty"]
	var total_materials = []
	for mid in mat_summary:
		total_materials.append({"id": mid, "name": mat_summary[mid]["name"], "qty": mat_summary[mid]["qty"]})

	if fail_message != "":
		send_to_peer(peer_id, {
			"type": "gathering_result",
			"correct": false,
			"material": {},
			"chain_count": chain_count,
			"chain_materials": chain_materials,
			"continue": false,
			"message": fail_message,
			"tool_saved": false,
			"correct_index": session.get("correct_id", -1),
		})

	send_to_peer(peer_id, {
		"type": "gathering_complete",
		"total_materials": total_materials,
		"job_xp_gained": total_job_xp,
		"char_xp_gained": char_xp,
		"job_leveled_up": job_result.get("leveled_up", false),
		"new_job_level": job_result.get("new_level", 1),
		"character": character.to_dict(),
	})

	active_gathering.erase(peer_id)
	gathering_cooldown[peer_id] = true  # Prevent encounter on next move
	send_location_update(peer_id)
	save_character(peer_id)

func _end_gathering_session_no_deplete(peer_id: int):
	"""End gathering without depleting the node (player stopped before any rounds)."""
	if not active_gathering.has(peer_id):
		return
	send_to_peer(peer_id, {
		"type": "gathering_complete",
		"total_materials": [],
		"job_xp_gained": 0,
		"char_xp_gained": 0,
		"job_leveled_up": false,
		"new_job_level": 1,
		"character": characters[peer_id].to_dict() if characters.has(peer_id) else {},
	})
	active_gathering.erase(peer_id)
	send_location_update(peer_id)

func handle_gathering_end(peer_id: int, message: Dictionary):
	"""Handle player voluntarily ending gathering."""
	if not active_gathering.has(peer_id):
		return
	var session = active_gathering[peer_id]
	if session.get("chain_count", 0) == 0:
		# Player stopped before completing any rounds — don't deplete the node
		_end_gathering_session_no_deplete(peer_id)
	else:
		_end_gathering_session(peer_id)

func _roll_gathering_reward(job_type: String, tier: int, job_level: int, is_risky: bool) -> Dictionary:
	"""Roll a material reward for a successful gathering round."""
	var reward = {}
	match job_type:
		"fishing":
			reward = drop_tables.roll_fishing_catch("shallow", job_level)
			if reward.has("item_id"):
				reward["id"] = reward["item_id"]
			reward["qty"] = (2 if is_risky else 1) + (1 if randi() % 100 < job_level else 0)
		"mining":
			reward = drop_tables.roll_mining_catch(tier, job_level)
			if reward.has("item_id"):
				reward["id"] = reward["item_id"]
			reward["qty"] = (2 if is_risky else 1) + (1 if randi() % 100 < job_level else 0)
		"logging":
			reward = drop_tables.roll_logging_catch(tier, job_level)
			if reward.has("item_id"):
				reward["id"] = reward["item_id"]
			reward["qty"] = (2 if is_risky else 1) + (1 if randi() % 100 < job_level else 0)
		"foraging":
			# Use foraging catches if available, otherwise mining as fallback
			if drop_tables.has_method("roll_foraging_catch"):
				reward = drop_tables.roll_foraging_catch(tier, job_level)
			else:
				reward = drop_tables.roll_mining_catch(tier, job_level)
			if reward.has("item_id"):
				reward["id"] = reward["item_id"]
			reward["qty"] = (2 if is_risky else 1) + (1 if randi() % 100 < job_level else 0)

	# Ensure reward has required fields
	if not reward.has("id"):
		reward["id"] = "unknown_material"
	if not reward.has("name"):
		reward["name"] = "Unknown Material"
	if not reward.has("qty"):
		reward["qty"] = 1

	return reward

func _add_gathering_reward(character: Character, reward: Dictionary, qty: int) -> int:
	"""Add a gathering reward — treasure chests go to inventory, everything else to materials pouch.
	Returns quantity actually added."""
	if reward.get("type", "") == "treasure_chest":
		# Treasure chests are inventory items, not materials
		for _i in range(qty):
			if character.inventory.size() >= character.MAX_INVENTORY_SIZE:
				return _i  # Inventory full — return how many we added
			character.inventory.append({
				"name": reward.get("name", "Treasure Chest"),
				"type": "treasure_chest",
				"is_consumable": true,
				"tier": int(reward.get("tier", 1)),
				"value": int(reward.get("value", 50)),
			})
		return qty
	else:
		return character.add_crafting_material(reward["id"], qty)

func _remove_gathering_reward(character: Character, mat_id: String, qty: int, mat_type: String = ""):
	"""Remove a gathering reward — treasure chests from inventory, everything else from materials."""
	if mat_type == "treasure_chest":
		var removed = 0
		for i in range(character.inventory.size() - 1, -1, -1):
			if removed >= qty:
				break
			if character.inventory[i].get("type", "") == "treasure_chest" and character.inventory[i].get("name", "") == mat_id:
				character.inventory.remove_at(i)
				removed += 1
		# Fall back to checking item field name
		if removed < qty:
			for i in range(character.inventory.size() - 1, -1, -1):
				if removed >= qty:
					break
				if character.inventory[i].get("type", "") == "treasure_chest":
					character.inventory.remove_at(i)
					removed += 1
	else:
		character.remove_crafting_material(mat_id, qty)

func handle_equip_tool(peer_id: int, message: Dictionary):
	"""Equip a tool from inventory to the tool slot."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var inv_index = int(message.get("index", -1))
	if inv_index < 0 or inv_index >= character.inventory.size():
		return
	var item = character.inventory[inv_index]
	if item.get("type", "") != "tool":
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]That's not a tool![/color]"})
		return
	var subtype = item.get("subtype", "")
	if not character.equipped_tools.has(subtype):
		return
	# Swap: if a tool is already equipped, put it back in inventory
	var old_tool = character.equipped_tools[subtype]
	character.equipped_tools[subtype] = item
	character.inventory.remove_at(inv_index)
	if not old_tool.is_empty():
		character.inventory.append(old_tool)
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00]Equipped %s.[/color]" % item.get("name", "Tool")})

func handle_unequip_tool(peer_id: int, message: Dictionary):
	"""Unequip a tool from the tool slot back to inventory."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var subtype = message.get("subtype", "")
	if not character.equipped_tools.has(subtype):
		return
	var tool = character.equipped_tools[subtype]
	if tool.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]No tool equipped in that slot![/color]"})
		return
	if character.inventory.size() >= character.MAX_INVENTORY_SIZE:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Inventory full![/color]"})
		return
	character.inventory.append(tool)
	character.equipped_tools[subtype] = {}
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00]Unequipped %s.[/color]" % tool.get("name", "Tool")})

func _get_tool_subtype_for_job(job_type: String) -> String:
	match job_type:
		"mining": return "pickaxe"
		"logging": return "axe"
		"foraging": return "sickle"
		"fishing": return "rod"
		_: return ""

func _find_tool_in_inventory(character, tool_subtype: String) -> Dictionary:
	"""Find a tool of the given subtype — checks equipped slot first, then inventory."""
	if tool_subtype == "":
		return {}
	# Check equipped tool slot
	var equipped = character.equipped_tools.get(tool_subtype, {})
	if not equipped.is_empty() and equipped.get("durability", 0) > 0:
		return equipped
	# Fallback: check inventory (shouldn't normally have tools here anymore)
	for item in character.inventory:
		if item.get("type", "") == "tool" and item.get("subtype", "") == tool_subtype:
			if item.get("durability", 0) > 0:
				return item
	return {}

func _consume_tool_durability(peer_id: int, character, tool_subtype: String):
	"""Reduce durability of a tool by 1. Remove if broken and notify player."""
	# Check equipped tool slot first
	var equipped = character.equipped_tools.get(tool_subtype, {})
	if not equipped.is_empty():
		equipped["durability"] = equipped.get("durability", 1) - 1
		if equipped["durability"] <= 0:
			var tool_name = equipped.get("name", tool_subtype.capitalize())
			character.equipped_tools[tool_subtype] = {}
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Your %s has broken![/color]" % tool_name})
		return
	# Fallback: check inventory
	for i in range(character.inventory.size()):
		var item = character.inventory[i]
		if item.get("type", "") == "tool" and item.get("subtype", "") == tool_subtype:
			item["durability"] = item.get("durability", 1) - 1
			if item["durability"] <= 0:
				var tool_name = item.get("name", tool_subtype.capitalize())
				character.inventory.remove_at(i)
				send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Your %s has broken![/color]" % tool_name})
			break

# ===== SOLDIER HARVEST SYSTEM =====

func handle_harvest_start(peer_id: int):
	"""Start a harvest session after combat victory (Soldier job)."""
	if not characters.has(peer_id):
		return
	if active_harvests.has(peer_id):
		return

	var character = characters[peer_id]
	var soldier_level = character.job_levels.get("soldier", 1)

	# Get last killed monster info from pending harvest data
	var harvest_data = character.get_meta("pending_harvest", {}) if character.has_meta("pending_harvest") else {}
	if harvest_data.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]No monster to harvest![/color]"})
		return

	var monster_name = harvest_data.get("monster_name", "")
	var monster_tier = harvest_data.get("monster_tier", 1)
	var max_rounds = 1
	if monster_tier >= 7:
		max_rounds = 3
	elif monster_tier >= 4:
		max_rounds = 2

	# Calculate soldier saves (level-based)
	var harvest_saves = 0
	if soldier_level >= 80:
		harvest_saves = 3
	elif soldier_level >= 50:
		harvest_saves = 2
	elif soldier_level >= 20:
		harvest_saves = 1

	# Check harvest mastery for this monster type
	var mastery_count = int(character.harvest_mastery.get(monster_name, 0))
	var mastery_label = ""
	var mastery_auto_round = false
	var mastery_bonus_parts = 0
	if mastery_count >= 15:
		mastery_label = "Master"
		mastery_bonus_parts = 3  # +3 parts per correct round
		mastery_auto_round = true  # Round 1 auto-succeeds
	elif mastery_count >= 7:
		mastery_label = "Expert"
		mastery_auto_round = true
	elif mastery_count >= 3:
		mastery_label = "Familiar"

	var session = _generate_harvest_round(monster_name, monster_tier)
	session["monster_name"] = monster_name
	session["monster_tier"] = monster_tier
	session["round"] = 1
	session["max_rounds"] = max_rounds
	session["parts_gained"] = []
	session["saves_remaining"] = harvest_saves
	session["mastery_count"] = mastery_count
	session["mastery_label"] = mastery_label
	session["mastery_bonus_parts"] = mastery_bonus_parts
	active_harvests[peer_id] = session

	# If Expert/Master, auto-succeed round 1
	if mastery_auto_round:
		_handle_harvest_auto_success(peer_id, session, character)
		return

	var _hint_str = minf(1.0, float(soldier_level) / 100.0)
	# Familiar mastery adds +0.3 hint strength
	if mastery_count >= 3:
		_hint_str = minf(1.0, _hint_str + 0.3)
	var _harvest_msg = {
		"type": "harvest_round",
		"options": session["client_options"],
		"hint_strength": _hint_str,
		"round": 1,
		"max_rounds": max_rounds,
		"monster_name": monster_name,
		"saves_remaining": harvest_saves,
		"mastery_label": mastery_label,
		"mastery_count": mastery_count,
	}
	# Reveal correct answer as hint if hint_strength > 0.5
	if _hint_str > 0.5 and randf() < _hint_str:
		_harvest_msg["hint_id"] = session["correct_id"]
	send_to_peer(peer_id, _harvest_msg)

func _handle_harvest_auto_success(peer_id: int, session: Dictionary, character):
	"""Auto-succeed a harvest round due to Expert/Master mastery."""
	var monster_name = session["monster_name"]
	var parts = drop_tables.get_monster_parts(monster_name)
	if not parts.is_empty():
		var adjusted = parts.duplicate(true)
		for p in adjusted:
			p["weight"] = maxi(p["weight"], 20)
		var total_w = 0
		for p in adjusted:
			total_w += p["weight"]
		var roll = randi() % total_w
		var cum = 0
		for p in adjusted:
			cum += p["weight"]
			if roll < cum:
				var qty = 5 + session.get("mastery_bonus_parts", 0)
				character.add_crafting_material(p["id"], qty)
				session["parts_gained"].append({"id": p["id"], "name": p["name"], "qty": qty})
				break

	send_to_peer(peer_id, {
		"type": "harvest_result",
		"correct": true,
		"part_gained": session["parts_gained"][-1] if session["parts_gained"].size() > 0 else {},
		"round": 1,
		"continue": session["max_rounds"] > 1,
		"auto_success": true,
		"mastery_label": session.get("mastery_label", ""),
	})

	if session["max_rounds"] > 1:
		session["round"] = 2
		var new_round = _generate_harvest_round(monster_name, session["monster_tier"])
		session["options"] = new_round["options"]
		session["client_options"] = new_round["client_options"]
		session["correct_id"] = new_round["correct_id"]
		var soldier_level = character.job_levels.get("soldier", 0)
		var _h_hint = minf(1.0, float(soldier_level) / 100.0)
		if session.get("mastery_count", 0) >= 3:
			_h_hint = minf(1.0, _h_hint + 0.3)
		var _h_msg = {
			"type": "harvest_round",
			"options": new_round["client_options"],
			"hint_strength": _h_hint,
			"round": 2,
			"max_rounds": session["max_rounds"],
			"monster_name": monster_name,
			"saves_remaining": session.get("saves_remaining", 0),
			"mastery_label": session.get("mastery_label", ""),
			"mastery_count": session.get("mastery_count", 0),
		}
		if _h_hint > 0.5 and randf() < _h_hint:
			_h_msg["hint_id"] = new_round["correct_id"]
		send_to_peer(peer_id, _h_msg)
	else:
		_end_harvest_session(peer_id, true)

func _generate_harvest_round(monster_name: String, monster_tier: int) -> Dictionary:
	"""Generate a harvest round — reuses gathering 3-choice pattern."""
	var labels = [
		["Carve the hide", "Extract the organ", "Collect the bone"],
		["Slice the tendon", "Drain the ichor", "Pry the scale"],
		["Sever the limb", "Harvest the gland", "Chip the claw"],
	]
	var label_set = labels[randi() % labels.size()]
	var shuffled = label_set.duplicate()
	shuffled.shuffle()
	var correct_idx = randi() % 3
	var options = []
	for i in range(3):
		options.append({"label": shuffled[i], "id": i, "correct": i == correct_idx})
	var client_options = []
	for opt in options:
		client_options.append({"label": opt["label"], "id": opt["id"]})
	return {"options": options, "client_options": client_options, "correct_id": correct_idx}

func handle_harvest_choice(peer_id: int, message: Dictionary):
	"""Handle player making a harvest choice."""
	if not characters.has(peer_id):
		return
	if not active_harvests.has(peer_id):
		return

	var character = characters[peer_id]
	var session = active_harvests[peer_id]
	var choice_id = int(message.get("choice_id", -1))

	var options = session.get("options", [])
	var chosen = null
	for opt in options:
		if int(opt["id"]) == choice_id:
			chosen = opt
			break
	if chosen == null:
		return

	var correct = chosen.get("correct", false)
	var monster_name = session["monster_name"]
	var monster_tier = session["monster_tier"]

	if correct:
		# Track mastery for this monster type
		character.harvest_mastery[monster_name] = int(character.harvest_mastery.get(monster_name, 0)) + 1

		# Roll a part with higher rare weights
		var parts = drop_tables.get_monster_parts(monster_name)
		if not parts.is_empty():
			# Bias toward rarer parts for harvest
			var adjusted = parts.duplicate(true)
			for p in adjusted:
				p["weight"] = maxi(p["weight"], 20)  # Flatten weights
			var total_w = 0
			for p in adjusted:
				total_w += p["weight"]
			var roll = randi() % total_w
			var cum = 0
			for p in adjusted:
				cum += p["weight"]
				if roll < cum:
					var qty = 5 + session.get("mastery_bonus_parts", 0)
					character.add_crafting_material(p["id"], qty)
					session["parts_gained"].append({"id": p["id"], "name": p["name"], "qty": qty})
					break

		if session["round"] < session["max_rounds"]:
			# More rounds available
			session["round"] += 1
			var new_round = _generate_harvest_round(monster_name, monster_tier)
			session["options"] = new_round["options"]
			session["client_options"] = new_round["client_options"]
			session["correct_id"] = new_round["correct_id"]
			var soldier_level = character.job_levels.get("soldier", 0)
			send_to_peer(peer_id, {
				"type": "harvest_result",
				"correct": true,
				"part_gained": session["parts_gained"][-1] if session["parts_gained"].size() > 0 else {},
				"round": session["round"],
				"continue": true,
			})
			var _h_hint = minf(1.0, float(soldier_level) / 100.0)
			if session.get("mastery_count", 0) >= 3:
				_h_hint = minf(1.0, _h_hint + 0.3)
			var _h_msg = {
				"type": "harvest_round",
				"options": new_round["client_options"],
				"hint_strength": _h_hint,
				"round": session["round"],
				"max_rounds": session["max_rounds"],
				"monster_name": monster_name,
				"saves_remaining": session.get("saves_remaining", 0),
				"mastery_label": session.get("mastery_label", ""),
				"mastery_count": session.get("mastery_count", 0),
			}
			if _h_hint > 0.5 and randf() < _h_hint:
				_h_msg["hint_id"] = new_round["correct_id"]
			send_to_peer(peer_id, _h_msg)
		else:
			# All rounds done - send final result then complete
			send_to_peer(peer_id, {
				"type": "harvest_result",
				"correct": true,
				"part_gained": session["parts_gained"][-1] if session["parts_gained"].size() > 0 else {},
				"round": session["round"],
				"continue": false,
			})
			_end_harvest_session(peer_id, true)
	else:
		# Wrong — check for soldier saves
		var saves_left = session.get("saves_remaining", 0)
		if saves_left > 0:
			session["saves_remaining"] -= 1
			# Re-roll the round (new options)
			var new_round = _generate_harvest_round(monster_name, monster_tier)
			session["options"] = new_round["options"]
			session["client_options"] = new_round["client_options"]
			session["correct_id"] = new_round["correct_id"]
			send_to_peer(peer_id, {
				"type": "harvest_result",
				"correct": false,
				"part_gained": {},
				"round": session["round"],
				"continue": true,
				"harvest_saved": true,
				"saves_remaining": session["saves_remaining"],
			})
			var soldier_level = character.job_levels.get("soldier", 0)
			var _h_hint = minf(1.0, float(soldier_level) / 100.0)
			if session.get("mastery_count", 0) >= 3:
				_h_hint = minf(1.0, _h_hint + 0.3)
			var _h_msg = {
				"type": "harvest_round",
				"options": new_round["client_options"],
				"hint_strength": _h_hint,
				"round": session["round"],
				"max_rounds": session["max_rounds"],
				"monster_name": monster_name,
				"saves_remaining": session["saves_remaining"],
				"mastery_label": session.get("mastery_label", ""),
				"mastery_count": session.get("mastery_count", 0),
			}
			if _h_hint > 0.5 and randf() < _h_hint:
				_h_msg["hint_id"] = new_round["correct_id"]
			send_to_peer(peer_id, _h_msg)
		else:
			# No saves — harvest ends but still give 1 base part
			var fail_part = {}
			var parts = drop_tables.get_monster_parts(monster_name)
			if not parts.is_empty():
				var p = parts[0]
				var qty = 1
				character.add_crafting_material(p["id"], qty)
				session["parts_gained"].append({"id": p["id"], "name": p["name"], "qty": qty})
				fail_part = {"id": p["id"], "name": p["name"], "qty": qty}
			send_to_peer(peer_id, {
				"type": "harvest_result",
				"correct": false,
				"part_gained": fail_part,
				"round": session["round"],
				"continue": false,
			})
			_end_harvest_session(peer_id, false)

func _end_harvest_session(peer_id: int, all_correct: bool = false):
	"""End a harvest session and give job XP."""
	if not active_harvests.has(peer_id):
		return
	if not characters.has(peer_id):
		active_harvests.erase(peer_id)
		return

	var character = characters[peer_id]
	var session = active_harvests[peer_id]
	var parts = session.get("parts_gained", [])
	var monster_tier = session.get("monster_tier", 1)

	# Soldier job XP
	var xp_per_round = 15 + (monster_tier - 1) * 10
	var total_xp = xp_per_round * parts.size()
	var job_result = character.add_job_xp("soldier", total_xp)
	var char_xp = job_result.get("char_xp_gained", 0)
	if char_xp > 0:
		character.add_experience(char_xp)

	send_to_peer(peer_id, {
		"type": "harvest_complete",
		"total_parts": parts,
		"job_xp_gained": total_xp,
		"job_leveled_up": job_result.get("leveled_up", false),
		"new_job_level": job_result.get("new_level", 1),
	})

	# Clear pending harvest
	if character.has_meta("pending_harvest"):
		character.remove_meta("pending_harvest")
	active_harvests.erase(peer_id)
	send_character_update(peer_id)
	save_character(peer_id)

# ===== OLD GATHERING HANDLERS (kept for reference, unreachable) =====

func handle_fish_start(peer_id: int):
	"""Handle player starting to fish"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Check if in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot fish while in combat!"})
		return

	# Check for gathering node at this location
	var gathering_node = get_gathering_node_at(character.x, character.y)
	if gathering_node.is_empty() or gathering_node.type != "fishing":
		send_to_peer(peer_id, {"type": "error", "message": "No fishing spot here! Look for fish splashing in water nearby."})
		return

	# Get water type and fishing data
	var water_type = world_system.get_fishing_type(character.x, character.y)
	var base_wait_time = drop_tables.get_fishing_wait_time(character.fishing_skill)
	var base_reaction_window = drop_tables.get_fishing_reaction_window(character.fishing_skill)

	# Apply tool speed bonus (reduces wait time)
	var tool_speed_bonus = character.equipped_fishing_rod.get("bonuses", {}).get("speed_bonus", 0.0)
	var wait_time = base_wait_time * (1.0 - tool_speed_bonus)
	var reaction_window = base_reaction_window * (1.0 + tool_speed_bonus * 0.5)  # Slightly more time too

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

	# Handle different catch types
	var catch_message = ""
	var extra_messages = []

	# Get tool bonuses
	var tool_yield_bonus = character.equipped_fishing_rod.get("bonuses", {}).get("yield_bonus", 0)

	# Calculate quantity - base 1-2, with skill bonus, tool bonus, and critical chance
	var quantity = 1 + randi() % 2 + tool_yield_bonus  # 1-2 base + tool bonus
	var crit_chance = mini(character.fishing_skill, 50)  # Up to 50% crit chance at skill 50
	if randi() % 100 < crit_chance:
		quantity *= 2  # Double on crit
		extra_messages.append("[color=#FFD700]★ Critical Catch! ★[/color]")

	# Apply house gathering bonus
	var gathering_bonus = character.house_bonuses.get("gathering_bonus", 0)
	if gathering_bonus > 0:
		quantity += int(quantity * gathering_bonus)

	# Add XP
	var xp_result = character.add_fishing_xp(catch_result.xp)
	character.record_fish_caught()

	match catch_result.type:
		"fish":
			# Add as crafting material
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#00FF00]You caught %dx %s![/color]" % [quantity, catch_result.name]
		"material":
			character.add_crafting_material(catch_result.item_id, quantity)
			catch_message = "[color=#00BFFF]You found %dx %s![/color]" % [quantity, catch_result.name]
		"treasure":
			# Give tier-appropriate ore based on value
			var t_tier = clampi(character.fishing_skill / 3, 0, 8)
			var t_ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
			var t_ore_id = t_ore_tiers[mini(t_tier, t_ore_tiers.size() - 1)]
			var t_qty = maxi(1, catch_result.value / 20)
			character.add_crafting_material(t_ore_id, t_qty)
			catch_message = "[color=#8B5CF6]You found a %s containing %dx %s![/color]" % [catch_result.name, t_qty, CraftingDatabaseScript.get_material_name(t_ore_id)]
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
				var _egg_cap = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
				var egg_result = character.add_egg(egg_data, _egg_cap)
				if egg_result.success:
					catch_message = "[color=#A335EE]★ You found a %s! ★[/color]" % egg_data.name
					extra_messages.append("[color=#808080]Walk %d steps to hatch it.[/color]" % egg_data.hatch_steps)
				else:
					catch_message = "[color=#FF6666]★ %s found but eggs full! (%d/%d) ★[/color]" % [egg_data.name, character.incubating_eggs.size(), _egg_cap]
					extra_messages.append("[color=#808080]Upgrade Incubation Chamber at your Sanctuary for more slots.[/color]")
			else:
				var ess_tier = clampi(character.fishing_skill / 3, 0, 8)
				var ess_ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
				var ess_ore_id = ess_ore_tiers[mini(ess_tier, ess_ore_tiers.size() - 1)]
				var ess_qty = maxi(1, catch_result.value / 20)
				character.add_crafting_material(ess_ore_id, ess_qty)
				catch_message = "[color=#8B5CF6]You found %dx %s![/color]" % [ess_qty, CraftingDatabaseScript.get_material_name(ess_ore_id)]

	# Build level up message if applicable
	if xp_result.leveled_up:
		extra_messages.append("[color=#FFFF00]★ Fishing skill increased to %d! ★[/color]" % xp_result.new_level)

	# Deplete the gathering node (fishing = water, respawns)
	deplete_gathering_node(character.x, character.y, "water")

	# Check if node is now depleted
	var node = get_gathering_node_at(character.x, character.y)
	var node_depleted = node.is_empty()

	send_to_peer(peer_id, {
		"type": "fish_result",
		"success": true,
		"catch": catch_result,
		"xp_gained": catch_result.xp,
		"leveled_up": xp_result.leveled_up,
		"new_level": xp_result.new_level,
		"message": catch_message,
		"extra_messages": extra_messages,
		"node_depleted": node_depleted
	})

	send_character_update(peer_id)
	send_location_update(peer_id)  # Refresh location to update node status
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

	# Check for gathering node at this location
	var gathering_node = get_gathering_node_at(character.x, character.y)
	if gathering_node.is_empty() or gathering_node.type != "mining":
		send_to_peer(peer_id, {"type": "error", "message": "No ore vein here! Search the mountains for exposed ore."})
		return

	# Get ore tier from the node
	var base_ore_tier = gathering_node.tier
	var base_wait_time = drop_tables.get_mining_wait_time(character.mining_skill)
	var base_reaction_window = drop_tables.get_mining_reaction_window(character.mining_skill)

	# Apply tool bonuses
	var tool_bonuses = character.equipped_pickaxe.get("bonuses", {})
	var tool_speed_bonus = tool_bonuses.get("speed_bonus", 0.0)
	var tool_tier_bonus = tool_bonuses.get("tier_bonus", 0)

	var ore_tier = mini(9, base_ore_tier + tool_tier_bonus)  # Cap at tier 9
	var wait_time = base_wait_time * (1.0 - tool_speed_bonus)
	var reaction_window = base_reaction_window * (1.0 + tool_speed_bonus * 0.5)
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

	# Handle different catch types
	var catch_message = ""
	var extra_messages = []

	# Calculate quantity based on success level - increased base yields
	# Apply tool yield bonus from equipped pickaxe
	var tool_yield_bonus = character.equipped_pickaxe.get("bonuses", {}).get("yield_bonus", 0)

	var quantity = 1
	if success:
		quantity = 2 + randi() % 2  # 2-3 on full success (up from 1-2)
		# Critical chance based on skill
		var crit_chance = mini(character.mining_skill, 50)
		if randi() % 100 < crit_chance:
			quantity *= 2
			extra_messages.append("[color=#FFD700]★ Rich Vein! ★[/color]")
	else:
		quantity = 1 + (partial_success / 2)  # 1-2 on partial based on strikes completed

	# Add tool yield bonus
	quantity += tool_yield_bonus

	# Apply house gathering bonus
	var gathering_bonus_m = character.house_bonuses.get("gathering_bonus", 0)
	if gathering_bonus_m > 0:
		quantity += int(quantity * gathering_bonus_m)

	# Add XP (reduced on partial success)
	var xp_multiplier = 1.0 if success else (float(partial_success) / drop_tables.get_mining_reactions_required(ore_tier))
	var xp_gained = int(catch_result.xp * xp_multiplier)
	var xp_result = character.add_mining_xp(xp_gained)
	character.record_ore_gathered()

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
			var m_tier = clampi(character.mining_skill / 3, 0, 8)
			var m_ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
			var m_ore_id = m_ore_tiers[mini(m_tier, m_ore_tiers.size() - 1)]
			var m_qty = maxi(1, catch_result.value / 20)
			character.add_crafting_material(m_ore_id, m_qty)
			catch_message = "[color=#8B5CF6]You unearthed a %s containing %dx %s![/color]" % [catch_result.name, m_qty, CraftingDatabaseScript.get_material_name(m_ore_id)]
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
				var _egg_cap = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
				var egg_result = character.add_egg(egg_data, _egg_cap)
				if egg_result.success:
					catch_message = "[color=#A335EE]★ You unearthed a %s! ★[/color]" % egg_data.name
					extra_messages.append("[color=#808080]Walk %d steps to hatch it.[/color]" % egg_data.hatch_steps)
				else:
					catch_message = "[color=#FF6666]★ %s found but eggs full! (%d/%d) ★[/color]" % [egg_data.name, character.incubating_eggs.size(), _egg_cap]
					extra_messages.append("[color=#808080]Upgrade Incubation Chamber at your Sanctuary for more slots.[/color]")
			else:
				var em_tier = clampi(character.mining_skill / 3, 0, 8)
				var em_ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
				var em_ore_id = em_ore_tiers[mini(em_tier, em_ore_tiers.size() - 1)]
				var em_qty = maxi(1, catch_result.value / 20)
				character.add_crafting_material(em_ore_id, em_qty)
				catch_message = "[color=#8B5CF6]You found %dx %s![/color]" % [em_qty, CraftingDatabaseScript.get_material_name(em_ore_id)]

	if xp_result.leveled_up:
		extra_messages.append("[color=#FFFF00]★ Mining skill increased to %d! ★[/color]" % xp_result.new_level)

	# Deplete the gathering node (mining = permanent)
	deplete_gathering_node(character.x, character.y, "ore_vein")

	# Check if node is now depleted
	var node = get_gathering_node_at(character.x, character.y)
	var node_depleted = node.is_empty()

	send_to_peer(peer_id, {
		"type": "mine_result",
		"success": true,
		"catch": catch_result,
		"quantity": quantity,
		"xp_gained": xp_gained,
		"leveled_up": xp_result.leveled_up,
		"new_level": xp_result.new_level,
		"message": catch_message,
		"extra_messages": extra_messages,
		"node_depleted": node_depleted
	})

	send_character_update(peer_id)
	send_location_update(peer_id)  # Refresh location to update node status
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

	# Check for gathering node at this location
	var gathering_node = get_gathering_node_at(character.x, character.y)
	if gathering_node.is_empty() or gathering_node.type != "logging":
		send_to_peer(peer_id, {"type": "error", "message": "No harvestable tree here! Search the forest for fallen logs."})
		return

	# Get wood tier from the node
	var base_wood_tier = gathering_node.tier
	var base_wait_time = drop_tables.get_logging_wait_time(character.logging_skill)
	var base_reaction_window = drop_tables.get_logging_reaction_window(character.logging_skill)

	# Apply tool bonuses from equipped axe
	var tool_bonuses = character.equipped_axe.get("bonuses", {})
	var tool_speed_bonus = tool_bonuses.get("speed_bonus", 0.0)
	var tool_tier_bonus = tool_bonuses.get("tier_bonus", 0)

	# Calculate final values with tool bonuses
	var wood_tier = mini(6, base_wood_tier + tool_tier_bonus)  # Cap at max tier 6
	var wait_time = base_wait_time * (1.0 - tool_speed_bonus)  # Faster wait with better tools
	var reaction_window = base_reaction_window * (1.0 + tool_speed_bonus * 0.5)  # Slightly longer window

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

	# Handle different catch types
	var catch_message = ""
	var extra_messages = []

	# Calculate quantity based on success level - increased base yields
	# Apply tool yield bonus from equipped axe
	var tool_yield_bonus = character.equipped_axe.get("bonuses", {}).get("yield_bonus", 0)

	var quantity = 1
	if success:
		quantity = 2 + randi() % 2  # 2-3 on full success (up from 1-2)
		# Critical chance based on skill
		var crit_chance = mini(character.logging_skill, 50)
		if randi() % 100 < crit_chance:
			quantity *= 2
			extra_messages.append("[color=#FFD700]★ Perfect Cut! ★[/color]")
	else:
		quantity = 1 + (partial_success / 2)  # 1-2 on partial based on chops completed

	# Add tool yield bonus
	quantity += tool_yield_bonus

	# Apply house gathering bonus
	var gathering_bonus_l = character.house_bonuses.get("gathering_bonus", 0)
	if gathering_bonus_l > 0:
		quantity += int(quantity * gathering_bonus_l)

	# Add XP (reduced on partial success)
	var xp_multiplier = 1.0 if success else (float(partial_success) / drop_tables.get_logging_reactions_required(wood_tier))
	var xp_gained = int(catch_result.xp * xp_multiplier)
	var xp_result = character.add_logging_xp(xp_gained)
	character.record_wood_gathered()

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
			var l_tier = clampi(character.logging_skill / 3, 0, 5)
			var l_wood_tiers = ["common_wood", "oak_wood", "ash_wood", "ironwood", "darkwood", "worldtree_branch"]
			var l_wood_id = l_wood_tiers[mini(l_tier, l_wood_tiers.size() - 1)]
			var l_qty = maxi(1, catch_result.value / 20)
			character.add_crafting_material(l_wood_id, l_qty)
			catch_message = "[color=#8B5CF6]You found a %s hidden in the trunk containing %dx %s![/color]" % [catch_result.name, l_qty, CraftingDatabaseScript.get_material_name(l_wood_id)]
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
				var _egg_cap = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
				var egg_result = character.add_egg(egg_data, _egg_cap)
				if egg_result.success:
					catch_message = "[color=#A335EE]★ You found a %s in a nest! ★[/color]" % egg_data.name
					extra_messages.append("[color=#808080]Walk %d steps to hatch it.[/color]" % egg_data.hatch_steps)
				else:
					catch_message = "[color=#FF6666]★ %s found but eggs full! (%d/%d) ★[/color]" % [egg_data.name, character.incubating_eggs.size(), _egg_cap]
					extra_messages.append("[color=#808080]Upgrade Incubation Chamber at your Sanctuary for more slots.[/color]")
			else:
				var el_tier = clampi(character.logging_skill / 3, 0, 5)
				var el_wood_tiers = ["common_wood", "oak_wood", "ash_wood", "ironwood", "darkwood", "worldtree_branch"]
				var el_wood_id = el_wood_tiers[mini(el_tier, el_wood_tiers.size() - 1)]
				var el_qty = maxi(1, catch_result.value / 20)
				character.add_crafting_material(el_wood_id, el_qty)
				catch_message = "[color=#8B5CF6]You found %dx %s![/color]" % [el_qty, CraftingDatabaseScript.get_material_name(el_wood_id)]

	if xp_result.leveled_up:
		extra_messages.append("[color=#FFFF00]★ Logging skill increased to %d! ★[/color]" % xp_result.new_level)

	# Deplete the gathering node (logging = permanent)
	deplete_gathering_node(character.x, character.y, "tree")

	# Check if node is now depleted
	var node = get_gathering_node_at(character.x, character.y)
	var node_depleted = node.is_empty()

	send_to_peer(peer_id, {
		"type": "log_result",
		"success": true,
		"catch": catch_result,
		"quantity": quantity,
		"xp_gained": xp_gained,
		"leveled_up": xp_result.leveled_up,
		"new_level": xp_result.new_level,
		"message": catch_message,
		"extra_messages": extra_messages,
		"node_depleted": node_depleted
	})

	send_character_update(peer_id)
	send_location_update(peer_id)  # Refresh location to update node status
	save_character(peer_id)

# ===== GATHERING NODE SYSTEM =====
# Simplified for performance - nodes are deterministic, we only track depleted ones

func get_coord_key(x: int, y: int) -> String:
	"""Generate a coordinate key for node dictionaries"""
	return "%d,%d" % [x, y]

func get_gathering_node_at(x: int, y: int) -> Dictionary:
	"""Check if there's an active gathering node at the given coordinates."""
	# New chunk-based system: use world_system's unified function
	if chunk_manager:
		return world_system.get_gathering_node_at(x, y)

	# Legacy fallback
	var coord_key = get_coord_key(x, y)
	if depleted_nodes.has(coord_key):
		var respawn_time = depleted_nodes[coord_key]
		if Time.get_unix_time_from_system() < respawn_time:
			return {}
		else:
			depleted_nodes.erase(coord_key)
	return _determine_node_type_at(x, y)

func get_gathering_node_nearby(x: int, y: int) -> Dictionary:
	"""Check for gathering node at position first, then check adjacent tiles.
	This allows gathering from blocking tiles (trees, ore, water) by standing next to them."""
	# First check the tile the player is standing on
	var node = get_gathering_node_at(x, y)
	if not node.is_empty():
		return node
	# Check 4 cardinal adjacent tiles
	for offset in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
		var nx = x + offset[0]
		var ny = y + offset[1]
		var adj_node = get_gathering_node_at(nx, ny)
		if not adj_node.is_empty():
			# Store the actual node coordinates for depletion
			adj_node["node_x"] = nx
			adj_node["node_y"] = ny
			return adj_node
	return {}

func _determine_node_type_at(x: int, y: int) -> Dictionary:
	"""Legacy: Determine gathering node type using old world_system functions."""
	var terrain = world_system.get_terrain_at(x, y)
	var terrain_info = world_system.get_terrain_info(terrain)
	if terrain_info.safe:
		return {}
	if world_system.is_fishing_spot(x, y):
		return {"type": "fishing", "tier": world_system.get_fishing_tier(x, y)}
	if world_system.is_ore_deposit(x, y):
		return {"type": "mining", "tier": world_system.get_ore_tier(x, y)}
	if world_system.is_dense_forest(x, y):
		return {"type": "logging", "tier": world_system.get_wood_tier(x, y)}
	return {}

func deplete_gathering_node(x: int, y: int, tile_type: String = ""):
	"""Mark a gathering node as depleted. Water nodes respawn, others are permanent."""
	if chunk_manager:
		chunk_manager.deplete_node(x, y, tile_type)
	else:
		var coord_key = get_coord_key(x, y)
		if tile_type == "water":
			depleted_nodes[coord_key] = Time.get_unix_time_from_system() + NODE_RESPAWN_TIME
		else:
			depleted_nodes[coord_key] = -1  # Permanent

func process_node_respawns(delta: float):
	"""Legacy: Periodically clean up expired depleted nodes."""
	node_respawn_timer += delta
	if node_respawn_timer < NODE_RESPAWN_CHECK_INTERVAL:
		return
	node_respawn_timer = 0.0
	var current_time = Time.get_unix_time_from_system()
	var to_remove = []
	for coord_key in depleted_nodes:
		if depleted_nodes[coord_key] <= current_time:
			to_remove.append(coord_key)
	for coord_key in to_remove:
		depleted_nodes.erase(coord_key)

# ===== JOB SYSTEM =====

func handle_job_info(peer_id: int):
	"""Send all job data to the client."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	send_to_peer(peer_id, {
		"type": "job_info_response",
		"gathering_job": character.gathering_job,
		"specialty_job": character.specialty_job,
		"gathering_job_committed": character.gathering_job_committed,
		"specialty_job_committed": character.specialty_job_committed,
		"job_levels": character.job_levels,
		"job_xp": character.job_xp,
		"crafting_skills": character.crafting_skills,
		"crafting_xp": character.crafting_xp
	})

func handle_job_commit(peer_id: int, message: Dictionary):
	"""Handle player committing to a job."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var category = message.get("category", "")
	var job_name = message.get("job_name", "")

	if category == "gathering":
		if character.gathering_job_committed:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You have already committed to %s![/color]" % character.gathering_job.capitalize()})
			return
		if job_name not in character.GATHERING_JOBS:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Invalid gathering job.[/color]"})
			return
		if character.job_levels.get(job_name, 1) < character.JOB_TRIAL_CAP:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You must reach level %d in %s before committing.[/color]" % [character.JOB_TRIAL_CAP, job_name.capitalize()]})
			return
		character.commit_gathering_job(job_name)
		save_character(peer_id)
		send_to_peer(peer_id, {
			"type": "job_committed",
			"category": "gathering",
			"job_name": job_name,
			"message": "[color=#00FF00]You have committed to [color=#FFD700]%s[/color]! You can now level it beyond %d.[/color]" % [job_name.capitalize(), character.JOB_TRIAL_CAP]
		})
	elif category == "specialty":
		if character.specialty_job_committed:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You have already committed to %s![/color]" % character.specialty_job.capitalize()})
			return
		if job_name not in character.SPECIALTY_JOBS:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Invalid specialty job.[/color]"})
			return
		if character.job_levels.get(job_name, 1) < character.JOB_TRIAL_CAP:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You must reach level %d in %s before committing.[/color]" % [character.JOB_TRIAL_CAP, job_name.capitalize()]})
			return
		character.commit_specialty_job(job_name)
		save_character(peer_id)
		send_to_peer(peer_id, {
			"type": "job_committed",
			"category": "specialty",
			"job_name": job_name,
			"message": "[color=#00FF00]You have committed to [color=#FFD700]%s[/color]! You can now level it beyond %d.[/color]" % [job_name.capitalize(), character.JOB_TRIAL_CAP]
		})
	else:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Invalid job category.[/color]"})

# ===== CRAFTING SYSTEM =====

func handle_craft_list(peer_id: int, message: Dictionary):
	"""Send list of available recipes to player"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Must be at a trading post OR player station to craft
	var crafting_at_player_station = false
	if not at_trading_post.has(peer_id):
		if at_player_station.has(peer_id):
			crafting_at_player_station = true
		else:
			send_to_peer(peer_id, {"type": "error", "message": "You must be at a Trading Post or your own crafting station!"})
			return

	var skill_name = message.get("skill", "blacksmithing").to_lower()
	var skill_enum: int = CraftingDatabaseScript.get_skill_enum(skill_name)
	if skill_enum == -1:
		send_to_peer(peer_id, {"type": "error", "message": "Unknown crafting skill: %s" % skill_name})
		return

	# At player station, verify the matching station exists
	if crafting_at_player_station:
		var station_data = at_player_station[peer_id]
		var needed_station = CraftingDatabaseScript.SKILL_STATION_MAP.get(skill_name, "")
		if needed_station != "" and needed_station not in station_data.get("stations", []):
			var station_name = CraftingDatabaseScript.SKILL_STATION_NAMES.get(skill_name, "station")
			send_to_peer(peer_id, {"type": "error", "message": "You need a %s to craft %s!" % [station_name, skill_name.capitalize()]})
			return

	var skill_level = character.get_crafting_skill(skill_name)
	# Get ALL recipes for the skill (including locked ones) so players can see what's coming
	var recipes = CraftingDatabaseScript.get_recipes_for_skill(skill_enum)

	# Get trading post bonus (0 at player stations)
	var post_bonus = 0
	if not crafting_at_player_station:
		var tp_data = at_trading_post[peer_id]
		var tp_id = tp_data.get("id", "")
		post_bonus = CraftingDatabaseScript.get_post_specialization_bonus(tp_id, skill_name)

	# Get specialty job crafting bonus
	var job_bonus = character.get_specialty_crafting_bonus(skill_name)
	var total_success_bonus = post_bonus + job_bonus.success_bonus

	# Build recipe list with player's materials
	var recipe_list = []
	for recipe_entry in recipes:
		var recipe_id = recipe_entry.id
		var recipe = recipe_entry.data
		var is_locked = recipe.skill_required > skill_level
		var is_specialist_only = recipe.get("specialist_only", false)
		var specialist_gated = is_specialist_only and not character.can_use_specialist_recipe(skill_name)
		var can_craft = not is_locked and not specialist_gated and character.has_crafting_materials(recipe.materials)
		var success_chance = CraftingDatabaseScript.calculate_success_chance(skill_level, recipe.difficulty, total_success_bonus) if not is_locked and not specialist_gated else 0

		# Build a description of what this recipe does
		var description = _get_recipe_description(recipe)

		recipe_list.append({
			"id": recipe_id,
			"name": recipe.name,
			"skill_required": recipe.skill_required,
			"difficulty": recipe.difficulty,
			"materials": recipe.materials,
			"can_craft": can_craft,
			"success_chance": success_chance,
			"output_type": recipe.output_type,
			"locked": is_locked,
			"specialist_only": is_specialist_only,
			"specialist_gated": specialist_gated,
			"description": description
		})

	send_to_peer(peer_id, {
		"type": "craft_list",
		"skill": skill_name,
		"skill_level": skill_level,
		"post_bonus": post_bonus,
		"job_bonus": job_bonus,
		"recipes": recipe_list,
		"materials": character.crafting_materials
	})

func _get_recipe_description(recipe: Dictionary) -> String:
	"""Generate a human-readable description of what a recipe produces"""
	var output_type = recipe.get("output_type", "")
	var effect = recipe.get("effect", {})

	match output_type:
		"consumable":
			var effect_type = effect.get("type", "")
			match effect_type:
				"buff":
					var stat = effect.get("stat", "").replace("_", " ")
					var amount = effect.get("amount", 0)
					var duration = effect.get("duration", 0)
					return "Buff: +%d %s for %ds" % [amount, stat, duration]
				"heal":
					return "Heals %d HP" % effect.get("amount", 0)
				"restore_mana":
					return "Restores %d mana" % effect.get("amount", 0)
				"restore_stamina":
					return "Restores %d stamina" % effect.get("amount", 0)
				_:
					return "Consumable item"
		"weapon", "armor":
			var slot = recipe.get("output_slot", "")
			return "Crafted %s equipment" % slot
		"enchantment":
			var stat = effect.get("stat", "attack")
			var bonus = effect.get("bonus", 0)
			var target = recipe.get("target_slot", "gear")
			var recipe_max = recipe.get("max_enchant_value", CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(stat, 60))
			return "+%d %s to %s (up to +%d)" % [bonus, stat, target, recipe_max]
		"enhancement":
			var stat = effect.get("stat", "attack")
			var bonus = effect.get("bonus", 0)
			if stat == "all":
				return "+%d to all stats (scroll)" % bonus
			return "+%d %s (scroll)" % [bonus, stat]
		"tool":
			var bonuses = recipe.get("bonuses", {})
			var tool_type = recipe.get("tool_type", "")
			var parts = []
			if bonuses.get("yield_bonus", 0) > 0:
				parts.append("+%d yield" % bonuses.get("yield_bonus", 0))
			if bonuses.get("speed_bonus", 0.0) > 0:
				parts.append("+%d%% speed" % int(bonuses.get("speed_bonus", 0.0) * 100))
			if bonuses.get("tier_bonus", 0) > 0:
				parts.append("+%d tier access" % bonuses.get("tier_bonus", 0))
			var type_name = tool_type.replace("_", " ").capitalize()
			if parts.is_empty():
				return "Basic %s" % type_name
			return "%s: %s" % [type_name, ", ".join(parts)]
		"self_repair":
			return "Repair most-worn equipped item by 25%"
		"reforge":
			var slot = recipe.get("reforge_slot", "weapon")
			return "Reroll equipped %s stats ±10%%" % slot
		"transmute":
			var mat_type = recipe.get("transmute_type", "ore")
			return "Convert 5x T(N) %s → 2x T(N+1)" % mat_type
		"extract":
			return "Convert 3x leather/cloth → enchanting essence"
		"disenchant":
			return "Destroy inventory item → recover 30-60%% materials"
		"scroll":
			var stat = effect.get("stat", "")
			var bonus = effect.get("bonus_pct", 0)
			var dur = effect.get("duration_battles", 0)
			if stat == "time_stop":
				return "Stun enemy for 1 turn in combat"
			if bonus > 0:
				return "+%d%% %s for %d battles" % [bonus, stat.replace("_", " "), dur]
			var amount = effect.get("amount", 0)
			if amount > 0:
				return "+%d %s for %d battles" % [amount, stat.replace("_", " "), dur]
			return "Combat scroll"
		"map":
			var radius = effect.get("reveal_radius", 50)
			return "Reveals %d-tile radius on map" % radius
		"tome":
			var stat = effect.get("stat", "strength")
			var amount = effect.get("amount", 1)
			return "Permanently gain +%d %s (max 10 total)" % [amount, stat]
		"bestiary":
			return "Reveals true HP for one monster type"
		"material":
			var output_item = recipe.get("output_item", "")
			var output_qty = recipe.get("output_quantity", 1)
			var mat_name = CraftingDatabaseScript.get_material_name(output_item)
			if mat_name != "":
				return "Produces %dx %s" % [output_qty, mat_name]
			return "Produces crafting materials"
		"upgrade":
			var levels = effect.get("levels", 1)
			var target = recipe.get("target_slot", "gear")
			var recipe_max = recipe.get("max_upgrades", CraftingDatabaseScript.MAX_UPGRADE_LEVELS)
			return "+%d level to equipped %s (works up to +%d)" % [levels, target, recipe_max]
		"affix":
			var affix_pool = effect.get("affix_pool", [])
			if affix_pool.size() > 0:
				var names = []
				for a in affix_pool:
					names.append(a.capitalize())
				return "Adds random affix (%s) to gear" % "/".join(names)
			return "Adds random affix to gear"
		"structure":
			return "Placeable structure for player posts"
		"proc_enchant":
			var proc_type = effect.get("proc_type", "")
			match proc_type:
				"lifesteal": return "Adds %d%% lifesteal to equipped weapon" % effect.get("percent", 10)
				"shocking": return "Adds %d%% bonus lightning damage (%d%% chance)" % [effect.get("percent", 15), int(effect.get("proc_chance", 0.25) * 100)]
				"damage_reflect": return "Reflects %d%% damage back to attacker" % effect.get("percent", 15)
				"execute": return "+%d%% damage vs enemies below 30%% HP" % effect.get("bonus_damage", 50)
			return "Adds special effect to equipment"
		"rune":
			if recipe.has("rune_proc"):
				var rune_proc = recipe.get("rune_proc", "")
				return "Creates a Rune that adds %s to equipped gear" % rune_proc.replace("_", " ")
			var stat_display = recipe.get("rune_stat", "").replace("_bonus", "").replace("_", " ").capitalize()
			return "Creates a %s Rune of %s (max +%d)" % [recipe.get("rune_tier", "minor").capitalize(), stat_display, recipe.get("rune_cap", 0)]
		_:
			return ""

func handle_craft_item(peer_id: int, message: Dictionary):
	"""Attempt to craft an item"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Must be at a trading post or player station
	if not at_trading_post.has(peer_id) and not at_player_station.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You must be at a Trading Post or your own crafting station!"})
		return

	var recipe_id = message.get("recipe_id", "")
	# Check regular recipes first, then gathering tools
	var recipe = CraftingDatabaseScript.get_recipe(recipe_id)
	if recipe.is_empty():
		recipe = CraftingDatabaseScript.get_tool(recipe_id)
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

	# Check specialist-only gating
	if recipe.get("specialist_only", false) and not character.can_use_specialist_recipe(skill_name):
		var required_job = character.CRAFT_SKILL_TO_JOB.get(skill_name, "specialist")
		send_to_peer(peer_id, {"type": "error", "message": "This recipe requires committing as a %s!" % required_job.capitalize()})
		return

	# Check materials
	if not character.has_crafting_materials(recipe.materials):
		send_to_peer(peer_id, {"type": "error", "message": "You don't have the required materials!"})
		return

	# Consume materials (@ prefixed keys are monster part groups)
	for mat_id in recipe.materials:
		if mat_id.begins_with("@"):
			character.remove_group_materials(mat_id, recipe.materials[mat_id])
		else:
			character.remove_crafting_material(mat_id, recipe.materials[mat_id])

	# Get trading post bonus (0 at player stations) + specialty job bonus
	var post_bonus = 0
	if at_trading_post.has(peer_id):
		var tp_data = at_trading_post[peer_id]
		var tp_id = tp_data.get("id", "")
		post_bonus = CraftingDatabaseScript.get_post_specialization_bonus(tp_id, skill_name)
	var job_bonus = character.get_specialty_crafting_bonus(skill_name)
	var total_bonus = post_bonus + job_bonus.success_bonus

	# Check auto-skip: if skill - difficulty >= threshold, skip minigame with score 3
	var skill_gap = skill_level - recipe.difficulty
	if skill_gap < CraftingDatabaseScript.CRAFT_CHALLENGE_AUTO_SKIP:
		# Send crafting challenge minigame
		var is_specialist = character.can_use_specialist_recipe(skill_name)
		var job_level = character.job_levels.get(character.CRAFT_SKILL_TO_JOB.get(skill_name, ""), 0)
		var challenge = _generate_craft_challenge(skill_name, job_level, is_specialist)
		active_crafts[peer_id] = {
			"recipe_id": recipe_id,
			"recipe": recipe,
			"skill_name": skill_name,
			"skill_level": skill_level,
			"post_bonus": post_bonus,
			"total_bonus": total_bonus,
			"correct_answers": challenge["correct_answers"],
			"is_specialist": is_specialist,
			"job_level": job_level,
		}
		send_to_peer(peer_id, {
			"type": "craft_challenge",
			"rounds": challenge["client_rounds"],
			"skill_name": skill_name,
		})
		return

	# Auto-skip: trivially easy recipe, score = 3
	var quality = CraftingDatabaseScript.roll_quality(skill_level, recipe.difficulty, total_bonus, 3)
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var quality_color = CraftingDatabaseScript.QUALITY_COLORS[quality]

	# Calculate crafting XP (existing full path — enhancement/enchantment handled below)
	var xp_gained = CraftingDatabaseScript.calculate_craft_xp(recipe.difficulty, quality)
	var xp_result = character.add_crafting_xp(skill_name, xp_gained)

	# Award character XP from crafting
	var craft_char_xp = xp_result.get("char_xp_gained", 0)
	if craft_char_xp > 0:
		character.add_experience(craft_char_xp)

	# Award matching specialty job XP (50% of craft XP)
	var job_xp_gained = 0
	var job_leveled_up = false
	var job_new_level = 0
	var matching_job = character.CRAFT_SKILL_TO_JOB.get(skill_name, "")
	if matching_job != "" and character.can_gain_job_xp(matching_job):
		job_xp_gained = int(xp_gained * 0.5)
		if job_xp_gained > 0:
			var job_result = character.add_job_xp(matching_job, job_xp_gained)
			job_leveled_up = job_result.leveled_up
			job_new_level = job_result.new_level

	# Build result message
	var result_message = ""
	var crafted_item = {}

	# Create the item based on output type
	match recipe.output_type:
			"weapon", "armor":
				crafted_item = _create_crafted_equipment(recipe, quality)
				if crafted_item.is_empty():
					# Refund materials on creation failure
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message = "[color=#FF4444]Failed to create item! Materials refunded.[/color]"
				else:
					crafted_item["crafted_by"] = character.name
					character.inventory.append(crafted_item)
					result_message = "[color=%s]Created %s %s![/color]" % [quality_color, quality_name, recipe.name]
			"consumable":
				crafted_item = _create_crafted_consumable(recipe, quality)
				crafted_item["crafted_by"] = character.name
				character.add_item(crafted_item)
				result_message = "[color=%s]Created %s %s![/color]" % [quality_color, quality_name, recipe.name]
			"enhancement":
				# Create enhancement scroll as inventory item
				var effect = recipe.get("effect", {})
				var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
				var stat_type = effect.get("stat", "attack")

				# Special handling for "all" stat (Void Enhancement)
				# Uses +3 base instead of +5, applies to all 10 stats
				var base_bonus = 3 if stat_type == "all" else effect.get("bonus", 3)
				var scaled_bonus = int(base_bonus * quality_mult)

				var scroll = {
					"id": "scroll_%d" % randi(),
					"name": "%s %s" % [quality_name, recipe.name] if quality != CraftingDatabaseScript.CraftingQuality.STANDARD else recipe.name,
					"type": "enhancement_scroll",
					"slot": recipe.get("output_slot", "any"),  # "any" for void enhancement
					"effect": {
						"stat": stat_type,  # "attack", "defense", or "all"
						"bonus": scaled_bonus
					},
					"rarity": _quality_to_rarity(quality),
					"level": 1,
					"is_consumable": true,
					"quantity": 1
				}

				character.inventory.append(scroll)
				crafted_item = scroll
				result_message = "[color=%s]Created %s![/color]" % [quality_color, scroll.name]
			"enchantment":
				# Enchantments add permanent stat bonuses to equipped gear
				# Parse target slots (can be comma-separated)
				var target_slots = recipe.get("target_slot", "").split(",")
				var target_item = null
				var target_slot = ""

				# Find first equipped item matching target slots
				for slot in target_slots:
					slot = slot.strip_edges()
					if character.equipped.has(slot) and character.equipped[slot] != null:
						target_item = character.equipped[slot]
						target_slot = slot
						break

				if target_item == null:
					result_message = "[color=#FF4444]No equipment in %s slot to enchant![/color]" % recipe.get("target_slot", "")
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
				else:
					var effect = recipe.get("effect", {})
					var stat = effect.get("stat", "attack")
					var bonus = effect.get("bonus", 5)

					# Apply quality scaling to bonus
					var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
					bonus = int(bonus * quality_mult)

					# Initialize enchantments dict if needed
					if not target_item.has("enchantments"):
						target_item["enchantments"] = {}

					# Check per-recipe bracket cap (minor enchants can't reach high values)
					var current_value = target_item["enchantments"].get(stat, 0)
					var recipe_enchant_max = recipe.get("max_enchant_value", 9999)
					if current_value >= recipe_enchant_max:
						result_message = "[color=#FFFF00]%s already has +%d %s — this recipe only works up to +%d. Use a higher-tier enchantment![/color]" % [target_item.get("name", "item"), current_value, stat, recipe_enchant_max]
						for mat_id in recipe.materials:
							character.add_crafting_material(mat_id, recipe.materials[mat_id])
						result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
					# Check global per-stat cap
					elif current_value >= CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(stat, 60):
						var stat_cap = CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(stat, 60)
						result_message = "[color=#FFFF00]%s has reached the %s enchantment cap (+%d)![/color]" % [target_item.get("name", "item"), stat, stat_cap]
						for mat_id in recipe.materials:
							character.add_crafting_material(mat_id, recipe.materials[mat_id])
						result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
					else:
						# Check max enchantment types (3 different stats per item)
						var max_types = CraftingDatabaseScript.MAX_ENCHANTMENT_TYPES
						if not target_item["enchantments"].has(stat) and target_item["enchantments"].size() >= max_types:
							result_message = "[color=#FFFF00]%s already has %d enchantment types (max %d)! Remove one first.[/color]" % [target_item.get("name", "item"), target_item["enchantments"].size(), max_types]
							for mat_id in recipe.materials:
								character.add_crafting_material(mat_id, recipe.materials[mat_id])
							result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
						else:
							# Clamp bonus to tightest of recipe bracket and global cap
							var stat_cap_val = CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(stat, 60)
							var effective_cap = mini(recipe_enchant_max, stat_cap_val)
							var remaining = effective_cap - current_value
							if bonus > remaining:
								bonus = remaining
							target_item["enchantments"][stat] = current_value + bonus
							target_item["enchanted_by"] = character.name
							result_message = "[color=%s]Enchanted %s with +%d %s! (%d/%d cap)[/color]" % [quality_color, target_item.get("name", "item"), bonus, stat, current_value + bonus, stat_cap_val]
			"upgrade":
				# Upgrades increase equipment level
				var target_slots = recipe.get("target_slot", "").split(",")
				var target_item = null
				var target_slot = ""

				for slot in target_slots:
					slot = slot.strip_edges()
					if character.equipped.has(slot) and character.equipped[slot] != null:
						target_item = character.equipped[slot]
						target_slot = slot
						break

				if target_item == null:
					result_message = "[color=#FF4444]No equipment in %s slot to upgrade![/color]" % recipe.get("target_slot", "")
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
				else:
					var effect = recipe.get("effect", {})
					var levels_to_add = effect.get("levels", 1)

					# Apply quality scaling (masterwork = more levels)
					if quality == CraftingDatabaseScript.CraftingQuality.MASTERWORK:
						levels_to_add = int(levels_to_add * 1.5)
					elif quality == CraftingDatabaseScript.CraftingQuality.FINE:
						levels_to_add = int(levels_to_add * 1.25)
					elif quality == CraftingDatabaseScript.CraftingQuality.POOR:
						levels_to_add = max(1, int(levels_to_add * 0.5))

					# Check per-recipe bracket cap (e.g. +1 only works up to 10 total)
					var upgrades_applied = target_item.get("upgrades_applied", 0)
					var recipe_max = recipe.get("max_upgrades", CraftingDatabaseScript.MAX_UPGRADE_LEVELS)
					if upgrades_applied >= recipe_max:
						result_message = "[color=#FFFF00]%s has %d upgrades — this recipe only works up to +%d. Use a higher-tier upgrade recipe![/color]" % [target_item.get("name", "item"), upgrades_applied, recipe_max]
						for mat_id in recipe.materials:
							character.add_crafting_material(mat_id, recipe.materials[mat_id])
						result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
					# Check global upgrade cap (max +50 levels from crafting per item)
					elif upgrades_applied >= CraftingDatabaseScript.MAX_UPGRADE_LEVELS:
						result_message = "[color=#FFFF00]%s has reached the upgrade cap (+%d levels)![/color]" % [target_item.get("name", "item"), CraftingDatabaseScript.MAX_UPGRADE_LEVELS]
						for mat_id in recipe.materials:
							character.add_crafting_material(mat_id, recipe.materials[mat_id])
						result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
					else:
						# Clamp to remaining upgrade room (tightest of recipe bracket and global cap)
						var global_max = CraftingDatabaseScript.MAX_UPGRADE_LEVELS
						var remaining = mini(recipe_max, global_max) - upgrades_applied
						if levels_to_add > remaining:
							levels_to_add = remaining

						var old_level = target_item.get("level", 1)
						target_item["level"] = old_level + levels_to_add
						target_item["upgrades_applied"] = upgrades_applied + levels_to_add
						result_message = "[color=%s]Upgraded %s from level %d to %d! (%d/%d upgrade cap)[/color]" % [quality_color, target_item.get("name", "item"), old_level, old_level + levels_to_add, upgrades_applied + levels_to_add, global_max]
			"affix":
				# Affix infusion adds/replaces affixes on equipment
				var target_slots = recipe.get("target_slot", "").split(",")
				var target_item = null
				var target_slot = ""

				for slot in target_slots:
					slot = slot.strip_edges()
					if character.equipped.has(slot) and character.equipped[slot] != null:
						target_item = character.equipped[slot]
						target_slot = slot
						break

				if target_item == null:
					result_message = "[color=#FF4444]No equipment in %s slot for affix![/color]" % recipe.get("target_slot", "")
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
				else:
					var effect = recipe.get("effect", {})
					var affix_pool = effect.get("affix_pool", ["attack"])

					# Pick random affix from pool
					var chosen_affix = affix_pool[randi() % affix_pool.size()]

					# Calculate affix value based on item level and quality
					var item_level = target_item.get("level", 1)
					var base_value = 5 + int(item_level * 0.5)  # Scales with item level
					var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
					var affix_value = int(base_value * quality_mult)

					# Map affix pool names to actual affix keys
					var affix_key_map = {
						"strength": "str_bonus",
						"constitution": "con_bonus",
						"dexterity": "dex_bonus",
						"intelligence": "int_bonus",
						"wisdom": "wis_bonus",
						"wits": "wits_bonus",
						"attack": "attack_bonus",
						"defense": "defense_bonus",
						"speed": "speed_bonus",
						"mana": "mana_bonus"
					}
					var affix_key = affix_key_map.get(chosen_affix, chosen_affix + "_bonus")

					# Initialize affixes dict if needed
					if not target_item.has("affixes"):
						target_item["affixes"] = {}

					# Add or replace affix (only if new value is higher)
					var old_value = target_item["affixes"].get(affix_key, 0)
					var affix_display = chosen_affix.capitalize()
					var item_name = target_item.get("name", "item")

					if affix_value > old_value:
						target_item["affixes"][affix_key] = affix_value
						if old_value > 0:
							result_message = "[color=%s]Upgraded %s affix on %s: %d → %d![/color]" % [quality_color, affix_display, item_name, old_value, affix_value]
						else:
							result_message = "[color=%s]Added +%d %s affix to %s![/color]" % [quality_color, affix_value, affix_display, item_name]
					else:
						result_message = "[color=#FFFF00]Rolled +%d %s, but %s already has +%d. No change.[/color]" % [affix_value, affix_display, item_name, old_value]
			"tool":
				# Create a gathering tool using the standard tool format
				var tool_type = recipe.get("tool_type", "")
				var tool_tier = recipe.get("tier", 1)
				var subtype_map = {"fishing_rod": "rod", "pickaxe": "pickaxe", "axe": "axe", "sickle": "sickle"}
				var subtype = subtype_map.get(tool_type, tool_type)
				var tool_rarity = _quality_to_rarity(quality)

				var tool_data = DropTables.generate_tool(subtype, tool_tier, tool_rarity)
				if not tool_data.is_empty():
					if quality != CraftingDatabaseScript.CraftingQuality.STANDARD:
						tool_data["name"] = "%s %s" % [quality_name, recipe.name]
					tool_data["crafted"] = true
					character.inventory.append(tool_data)
					crafted_item = tool_data
					result_message = "[color=%s]Crafted %s! Check your inventory to equip it.[/color]" % [quality_color, tool_data.get("name", recipe.name)]
				else:
					# Refund materials on creation failure
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message = "[color=#FF4444]Failed to create tool! Materials refunded.[/color]"
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
					# Refund materials on creation failure
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message = "[color=#FF4444]Failed to create materials! Materials refunded.[/color]"
			"self_repair":
				result_message = _craft_self_repair(character, recipe, quality)
			"reforge":
				result_message = _craft_reforge(character, recipe, quality, quality_color)
			"transmute":
				result_message = _craft_transmute(character, recipe, quality, quality_color)
			"extract":
				result_message = _craft_extract(character, recipe, quality, quality_color)
			"disenchant":
				result_message = _craft_disenchant(character, recipe, quality, quality_color)
			"scroll":
				crafted_item = _craft_scroll(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", "scroll")]
			"map":
				crafted_item = _craft_map(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", "map")]
			"tome":
				crafted_item = _craft_tome(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", "tome")]
			"bestiary":
				crafted_item = _craft_bestiary(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", "bestiary page")]
			"structure":
				crafted_item = _craft_structure(recipe, quality)
				character.inventory.append(crafted_item)
				# Structures always show as standard quality regardless of roll
				quality = CraftingDatabaseScript.CraftingQuality.STANDARD
				quality_name = "Standard"
				quality_color = "#FFFFFF"
				result_message = "[color=#00FF00]Built %s![/color]" % crafted_item.get("name", "structure")
			"proc_enchant":
				var target_slots = recipe.get("target_slot", "").split(",")
				var target_item = null
				var target_slot = ""
				for slot in target_slots:
					slot = slot.strip_edges()
					if character.equipped.has(slot) and character.equipped[slot] != null:
						target_item = character.equipped[slot]
						target_slot = slot
						break
				if target_item == null:
					result_message = "[color=#FF4444]No equipment in %s slot to enchant![/color]" % recipe.get("target_slot", "")
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
				else:
					var effect = recipe.get("effect", {})
					var proc_type = effect.get("proc_type", "")
					if not target_item.has("proc_effects"):
						target_item["proc_effects"] = {}
					# Apply quality scaling to proc values
					var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
					var proc_data = {}
					var proc_item_name = target_item.get("name", "item")
					match proc_type:
						"lifesteal":
							var pct = effect.get("percent", 10) * quality_mult
							proc_data = {"percent": pct, "proc_chance": effect.get("proc_chance", 1.0)}
							result_message = "[color=%s]Enchanted %s with %d%% Lifesteal![/color]" % [quality_color, proc_item_name, int(pct)]
						"shocking":
							var pct = effect.get("percent", 15) * quality_mult
							proc_data = {"percent": pct, "proc_chance": effect.get("proc_chance", 0.25)}
							result_message = "[color=%s]Enchanted %s with Shocking (+%d%% damage, %d%% chance)![/color]" % [quality_color, proc_item_name, int(pct), int(effect.get("proc_chance", 0.25) * 100)]
						"damage_reflect":
							var pct = effect.get("percent", 15) * quality_mult
							proc_data = {"percent": pct, "proc_chance": effect.get("proc_chance", 1.0)}
							result_message = "[color=%s]Enchanted %s with %d%% Damage Reflect![/color]" % [quality_color, proc_item_name, int(pct)]
						"execute":
							var bonus = effect.get("bonus_damage", 50) * quality_mult
							proc_data = {"bonus_damage": bonus, "proc_chance": effect.get("proc_chance", 0.25), "threshold": effect.get("threshold", 0.3)}
							result_message = "[color=%s]Enchanted %s with Execute (+%d%% damage below 30%% HP)![/color]" % [quality_color, proc_item_name, int(bonus)]
					target_item["proc_effects"][proc_type] = proc_data
			"rune":
				# Runes are tradeable inventory items — create and add to inventory
				crafted_item = _create_crafted_rune(recipe, quality, character.name)
				character.add_item(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", recipe.name)]

	# Send result (include updated materials so client can check can_craft_another)
	send_to_peer(peer_id, {
		"type": "craft_result",
		"success": true,
		"recipe_id": recipe_id,
		"recipe_name": recipe.name,
		"quality": quality,
		"quality_name": quality_name,
		"quality_color": quality_color,
		"xp_gained": xp_gained,
		"char_xp_gained": craft_char_xp,
		"leveled_up": xp_result.leveled_up,
		"new_level": xp_result.new_level,
		"skill_name": skill_name,
		"message": result_message,
		"crafted_item": crafted_item,
		"materials": character.crafting_materials,
		"job_xp_gained": job_xp_gained,
		"job_leveled_up": job_leveled_up,
		"job_new_level": job_new_level,
		"job_name": matching_job
	})

	send_character_update(peer_id)
	save_character(peer_id)

func _craft_self_repair(character, recipe: Dictionary, quality: int) -> String:
	"""Blacksmith specialist: repair most-worn equipped item by 25% (quality scales)."""
	var repair_pct = 0.25 * CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
	var worst_item = null
	var worst_slot = ""
	var worst_wear = 0.0
	for slot in character.equipped:
		var item = character.equipped[slot]
		if item == null or item.is_empty():
			continue
		var wear = item.get("wear", 0.0)
		if wear > worst_wear:
			worst_wear = wear
			worst_item = item
			worst_slot = slot
	if worst_item == null or worst_wear <= 0:
		# Refund materials since nothing needs repair
		for mat_id in recipe.materials:
			character.add_crafting_material(mat_id, recipe.materials[mat_id])
		return "[color=#FFFF00]No equipped items need repair. Materials refunded.[/color]"
	var old_wear = worst_item.get("wear", 0.0)
	var new_wear = maxf(0.0, old_wear - repair_pct)
	worst_item["wear"] = new_wear
	var repaired_pct = int((old_wear - new_wear) * 100)
	return "[color=#00FF00]Repaired %s by %d%%! Wear: %d%% → %d%%[/color]" % [worst_item.get("name", "item"), repaired_pct, int(old_wear * 100), int(new_wear * 100)]

func _craft_reforge(character, recipe: Dictionary, quality: int, quality_color: String) -> String:
	"""Blacksmith specialist: reroll weapon/armor stats ±10% (quality improves range)."""
	var target_slot = recipe.get("reforge_slot", "weapon")
	var target_item = character.equipped.get(target_slot, null)
	if target_item == null or target_item.is_empty():
		# Refund materials since we can't reforge
		for mat_id in recipe.materials:
			character.add_crafting_material(mat_id, recipe.materials[mat_id])
		return "[color=#FF4444]No %s equipped to reforge! Materials refunded.[/color]" % target_slot

	var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
	var reforge_range = 0.10 * quality_mult  # Better quality = wider range (upward bias)

	# Reroll attack/defense stats
	var changes = []
	for stat_key in ["attack", "defense"]:
		if target_item.has(stat_key):
			var old_val = int(target_item[stat_key])
			if old_val <= 0:
				continue
			var min_val = int(old_val * (1.0 - 0.10))
			var max_val = int(old_val * (1.0 + reforge_range))
			var new_val = max(1, min_val + randi() % max(1, max_val - min_val + 1))
			target_item[stat_key] = new_val
			var diff = new_val - old_val
			var diff_str = ("+%d" % diff) if diff >= 0 else ("%d" % diff)
			changes.append("%s: %d → %d (%s)" % [stat_key.capitalize(), old_val, new_val, diff_str])

	if changes.is_empty():
		# Refund materials since item had nothing to reforge
		for mat_id in recipe.materials:
			character.add_crafting_material(mat_id, recipe.materials[mat_id])
		return "[color=#FFFF00]Item has no stats to reforge. Materials refunded.[/color]"
	return "[color=%s]Reforged %s!\n%s[/color]" % [quality_color, target_item.get("name", "item"), "\n".join(changes)]

func _craft_transmute(character, recipe: Dictionary, quality: int, quality_color: String) -> String:
	"""Alchemist specialist: convert 5x T(N) material → 2x T(N+1) of same type."""
	var transmute_type = recipe.get("transmute_type", "ore")
	var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)

	# Find the lowest-tier material of this type that player has 5+ of
	var best_mat_id = ""
	var best_tier = 999
	for mat_id in character.crafting_materials:
		var count = character.crafting_materials[mat_id]
		if count < 5:
			continue
		var mat_data = CraftingDatabaseScript.get_material(mat_id)
		if mat_data.is_empty():
			continue
		var mat_type = mat_data.get("type", "")
		if mat_type != transmute_type:
			continue
		var tier = int(mat_data.get("tier", 0))
		if tier < best_tier and tier < 9:  # Can't transmute T9
			best_tier = tier
			best_mat_id = mat_id

	if best_mat_id == "":
		# Refund recipe materials
		for mat_id in recipe.materials:
			character.add_crafting_material(mat_id, recipe.materials[mat_id])
		return "[color=#FF4444]No %s materials with 5+ quantity to transmute! Materials refunded.[/color]" % transmute_type

	# Find the next tier material of same type
	var target_tier = best_tier + 1
	var target_mat_id = ""
	for mat_id in CraftingDatabaseScript.MATERIALS:
		var mat_data = CraftingDatabaseScript.MATERIALS[mat_id]
		if mat_data.get("type", "") == transmute_type and int(mat_data.get("tier", 0)) == target_tier:
			target_mat_id = mat_id
			break

	if target_mat_id == "":
		# Refund recipe materials
		for mat_id in recipe.materials:
			character.add_crafting_material(mat_id, recipe.materials[mat_id])
		return "[color=#FF4444]No higher-tier %s material exists! Materials refunded.[/color]" % transmute_type

	# Consume 5, produce 2 (quality can increase output)
	character.remove_crafting_material(best_mat_id, 5)
	var output_qty = max(1, int(2 * quality_mult))
	character.add_crafting_material(target_mat_id, output_qty)

	var source_name = CraftingDatabaseScript.get_material_name(best_mat_id)
	var target_name = CraftingDatabaseScript.get_material_name(target_mat_id)
	return "[color=%s]Transmuted 5x %s → %dx %s![/color]" % [quality_color, source_name, output_qty, target_name]

func _craft_extract(character, recipe: Dictionary, quality: int, quality_color: String) -> String:
	"""Alchemist specialist: convert lowest-tier monster parts into crafting essence."""
	var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)

	# Monster parts are leather/hide type materials - find lowest tier one with 3+
	var best_mat_id = ""
	var best_tier = 999
	for mat_id in character.crafting_materials:
		var count = character.crafting_materials[mat_id]
		if count < 3:
			continue
		var mat_data = CraftingDatabaseScript.get_material(mat_id)
		if mat_data.is_empty():
			continue
		var mat_type = mat_data.get("type", "")
		if mat_type not in ["leather", "cloth"]:
			continue
		var tier = int(mat_data.get("tier", 0))
		if tier < best_tier:
			best_tier = tier
			best_mat_id = mat_id

	if best_mat_id == "":
		# Refund recipe materials
		for mat_id in recipe.materials:
			character.add_crafting_material(mat_id, recipe.materials[mat_id])
		return "[color=#FF4444]No leather/cloth materials with 3+ quantity to extract! Materials refunded.[/color]"

	# Convert to tier-appropriate enchant material
	var essence_map = {1: "magic_dust", 2: "magic_dust", 3: "arcane_crystal", 4: "soul_shard", 5: "soul_shard", 6: "void_essence", 7: "void_essence", 8: "primordial_spark", 9: "primordial_spark"}
	var target_mat = essence_map.get(best_tier, "magic_dust")

	character.remove_crafting_material(best_mat_id, 3)
	var output_qty = max(1, int(2 * quality_mult))
	character.add_crafting_material(target_mat, output_qty)

	var source_name = CraftingDatabaseScript.get_material_name(best_mat_id)
	var target_name = CraftingDatabaseScript.get_material_name(target_mat)
	return "[color=%s]Extracted %dx %s from 3x %s![/color]" % [quality_color, output_qty, target_name, source_name]

func _craft_disenchant(character, recipe: Dictionary, quality: int, quality_color: String) -> String:
	"""Enchanter specialist: destroy lowest-level inventory item, recover partial materials."""
	var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)

	# Find lowest-level non-quest equipment item in inventory
	var worst_idx = -1
	var worst_level = 999999
	for i in range(character.inventory.size()):
		var item = character.inventory[i]
		if item.get("type", "") in ["enhancement_scroll", "quest_item"]:
			continue
		if item.get("is_consumable", false):
			continue
		var item_level = int(item.get("level", 1))
		if item_level < worst_level:
			worst_level = item_level
			worst_idx = i

	if worst_idx == -1:
		# Refund recipe materials
		for mat_id in recipe.materials:
			character.add_crafting_material(mat_id, recipe.materials[mat_id])
		return "[color=#FF4444]No equipment in inventory to disenchant! Materials refunded.[/color]"

	var item = character.inventory[worst_idx]
	var item_name = item.get("name", "Unknown")

	# Calculate material recovery: 30-60% based on quality
	var recovery_pct = 0.30 + (quality_mult - 0.5) * 0.3  # Poor=15%, Standard=30%, Fine=52%, Master=60%
	recovery_pct = clampf(recovery_pct, 0.15, 0.70)

	# Generate materials based on item level/tier
	var item_level = int(item.get("level", 1))
	var tier = clampi(int(item_level / 10) + 1, 1, 9)
	var ore_tiers = ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"]
	var base_amount = max(1, int(3 * recovery_pct))
	var ore_id = ore_tiers[clampi(tier - 1, 0, 8)]
	character.add_crafting_material(ore_id, base_amount)

	# Bonus: chance for enchant material
	var bonus_mat = ""
	if randf() < recovery_pct:
		bonus_mat = "magic_dust" if tier <= 3 else ("arcane_crystal" if tier <= 5 else "void_essence")
		character.add_crafting_material(bonus_mat, 1)

	# Remove item
	character.inventory.remove_at(worst_idx)

	var result = "[color=%s]Disenchanted %s!\nRecovered: %dx %s[/color]" % [quality_color, item_name, base_amount, CraftingDatabaseScript.get_material_name(ore_id)]
	if bonus_mat != "":
		result += "\n[color=#A335EE]Bonus: 1x %s[/color]" % CraftingDatabaseScript.get_material_name(bonus_mat)
	return result

func _craft_scroll(recipe: Dictionary, quality: int) -> Dictionary:
	"""Create a scroll consumable item from a scribing recipe."""
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var effect = recipe.get("effect", {})
	var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)

	# Scale effect by quality
	var scaled_effect = effect.duplicate()
	if scaled_effect.has("bonus_pct"):
		scaled_effect["bonus_pct"] = int(scaled_effect["bonus_pct"] * quality_mult)
	if scaled_effect.has("amount"):
		scaled_effect["amount"] = int(scaled_effect["amount"] * quality_mult)
	if scaled_effect.has("duration_battles"):
		scaled_effect["duration_battles"] = max(1, int(scaled_effect["duration_battles"] * quality_mult))

	var display_name = recipe.name if quality == CraftingDatabaseScript.CraftingQuality.STANDARD else "%s %s" % [quality_name, recipe.name]
	return {
		"id": "scroll_%d" % randi(),
		"name": display_name,
		"type": "scroll",
		"is_consumable": true,
		"quantity": 1,
		"effect": scaled_effect,
		"rarity": _quality_to_rarity(quality),
		"level": 1
	}

func _craft_map(recipe: Dictionary, quality: int) -> Dictionary:
	"""Create an area map consumable."""
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
	var effect = recipe.get("effect", {})
	var base_radius = effect.get("reveal_radius", 50)
	var radius = int(base_radius * quality_mult)

	var display_name = recipe.name if quality == CraftingDatabaseScript.CraftingQuality.STANDARD else "%s %s" % [quality_name, recipe.name]
	return {
		"id": "map_%d" % randi(),
		"name": display_name,
		"type": "area_map",
		"is_consumable": true,
		"quantity": 1,
		"reveal_radius": radius,
		"rarity": _quality_to_rarity(quality),
		"level": 1
	}

func _craft_tome(recipe: Dictionary, quality: int) -> Dictionary:
	"""Create a spell tome consumable (permanent +1 stat)."""
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var effect = recipe.get("effect", {})
	var stat = effect.get("stat", "strength")
	var amount = effect.get("amount", 1)
	# Masterwork gives +2 instead of +1
	if quality == CraftingDatabaseScript.CraftingQuality.MASTERWORK:
		amount = 2

	var display_name = recipe.name if quality == CraftingDatabaseScript.CraftingQuality.STANDARD else "%s %s" % [quality_name, recipe.name]
	return {
		"id": "tome_%d" % randi(),
		"name": display_name,
		"type": "spell_tome",
		"is_consumable": true,
		"quantity": 1,
		"stat": stat,
		"amount": amount,
		"rarity": _quality_to_rarity(quality),
		"level": 1
	}

func _craft_bestiary(recipe: Dictionary, quality: int) -> Dictionary:
	"""Create a bestiary page consumable (reveals monster HP)."""
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var display_name = recipe.name if quality == CraftingDatabaseScript.CraftingQuality.STANDARD else "%s %s" % [quality_name, recipe.name]
	return {
		"id": "bestiary_%d" % randi(),
		"name": display_name,
		"type": "bestiary_page",
		"is_consumable": true,
		"quantity": 1,
		"rarity": _quality_to_rarity(quality),
		"level": 1
	}

func _craft_structure(recipe: Dictionary, quality: int) -> Dictionary:
	"""Create a structure item for player posts."""
	var structure_type = recipe.get("structure_type", "workbench")
	return {
		"id": "structure_%d" % randi(),
		"name": recipe.name,
		"type": "structure",
		"structure_type": structure_type,
		"is_consumable": false,
		"quantity": 1,
		"rarity": "common",
	}

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
		"quality": quality,
		"crafted_by": ""
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

	# Apply rarity bonuses (crit, dodge, damage reduction, etc.)
	item = drop_tables.apply_rarity_bonuses(item, item.get("rarity", "common"))

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

	# Map crafted effect type to a recognized POTION_EFFECTS key so combat can use the item
	var effect_type = scaled_effect.get("type", "")
	var consumable_type = "consumable"
	match effect_type:
		"heal":
			consumable_type = "health_potion"
		"restore_mana":
			consumable_type = "mana_potion"
		"restore_stamina":
			consumable_type = "stamina_potion"
		"restore_energy":
			consumable_type = "energy_potion"
		"buff":
			var buff_stat = scaled_effect.get("stat", "")
			match buff_stat:
				"attack":
					consumable_type = "scroll_rage"
				"defense":
					consumable_type = "scroll_stone_skin"
				"speed":
					consumable_type = "scroll_haste"

	var item = {
		"id": item_id,
		"name": "%s %s" % [quality_name, recipe.name] if quality != CraftingDatabaseScript.CraftingQuality.STANDARD else recipe.name,
		"type": consumable_type,
		"slot": "",
		"level": 1,
		"rarity": _quality_to_rarity(quality),
		"crafted": true,
		"quality": quality,
		"effect": scaled_effect,
		"is_consumable": true,
		"quantity": 1
	}

	# Apply rarity bonuses (potency, extra uses)
	item = drop_tables.apply_rarity_bonuses(item, item.get("rarity", "common"))

	return item

func _create_crafted_rune(recipe: Dictionary, quality: int, crafter_name: String) -> Dictionary:
	"""Create a crafted rune item with proper stacking fields"""
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
	var rune_name = "%s %s" % [quality_name, recipe.name] if quality != CraftingDatabaseScript.CraftingQuality.STANDARD else recipe.name
	var rune_item = {
		"id": "rune_%d" % randi(),
		"type": "rune",
		"name": rune_name,
		"target_slot": recipe.get("target_slot", ""),
		"crafted_by": crafter_name,
		"rarity": _quality_to_rarity(quality),
		"value": recipe.difficulty * 10,
		"is_consumable": true,
		"quantity": 1,
	}
	if recipe.has("rune_proc"):
		rune_item["rune_proc"] = recipe.get("rune_proc", "")
		rune_item["rune_proc_value"] = int(recipe.get("rune_proc_value", 10) * quality_mult)
		rune_item["rune_proc_chance"] = recipe.get("rune_proc_chance", 1.0)
	else:
		rune_item["rune_stat"] = recipe.get("rune_stat", "")
		rune_item["rune_tier"] = recipe.get("rune_tier", "minor")
		rune_item["rune_cap"] = int(recipe.get("rune_cap", 0) * quality_mult)
	return rune_item

func _consume_one_from_stack(character, index: int) -> void:
	"""Remove one item from a consumable stack, or remove the slot if quantity reaches 0"""
	var item = character.inventory[index]
	var qty = item.get("quantity", 1)
	if qty <= 1:
		character.inventory.remove_at(index)
	else:
		item["quantity"] = qty - 1

func handle_use_rune(peer_id: int, message: Dictionary):
	"""Apply a Rune from inventory to an equipped gear slot"""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var rune_index = int(message.get("rune_index", -1))
	var target_slot = message.get("target_slot", "")

	# Validate rune index
	if rune_index < 0 or rune_index >= character.inventory.size():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Invalid rune selection.[/color]"})
		return
	var rune = character.inventory[rune_index]
	if rune.get("type", "") != "rune":
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]That item is not a Rune.[/color]"})
		return

	# Validate target slot is allowed by the rune
	var allowed_slots = rune.get("target_slot", "").split(",")
	var slot_valid = false
	for s in allowed_slots:
		if s.strip_edges() == target_slot:
			slot_valid = true
			break
	if not slot_valid:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]This Rune cannot be applied to that slot.[/color]"})
		return

	# Validate equipped item exists
	if not character.equipped.has(target_slot) or character.equipped[target_slot] == null:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]No item equipped in %s slot.[/color]" % target_slot})
		return

	var target_item = character.equipped[target_slot]

	if rune.has("rune_proc"):
		# Proc rune — set proc effect on item
		var proc_type = rune.get("rune_proc", "")
		if not target_item.has("proc_effects"):
			target_item["proc_effects"] = {}
		var proc_data = {}
		match proc_type:
			"lifesteal":
				proc_data = {"percent": rune.get("rune_proc_value", 10), "proc_chance": rune.get("rune_proc_chance", 1.0)}
			"shocking":
				proc_data = {"percent": rune.get("rune_proc_value", 15), "proc_chance": rune.get("rune_proc_chance", 0.25)}
			"damage_reflect":
				proc_data = {"percent": rune.get("rune_proc_value", 15), "proc_chance": rune.get("rune_proc_chance", 1.0)}
			"execute":
				proc_data = {"bonus_damage": rune.get("rune_proc_value", 50), "proc_chance": rune.get("rune_proc_chance", 0.25), "threshold": 0.3}
		target_item["proc_effects"][proc_type] = proc_data
		_consume_one_from_stack(character, rune_index)
		send_to_peer(peer_id, {"type": "text", "message": "[color=#A335EE]Applied %s to your %s! Added %s effect.[/color]" % [rune.get("name", "Rune"), target_item.get("name", "item"), proc_type.replace("_", " ")]})
	else:
		# Stat rune — set affix value (upgrade only, refuse if no improvement)
		var stat_key = rune.get("rune_stat", "")
		var rune_cap = int(rune.get("rune_cap", 0))
		if stat_key == "" or rune_cap <= 0:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Invalid Rune data.[/color]"})
			return
		if not target_item.has("affixes"):
			target_item["affixes"] = {}
		var current_value = int(target_item["affixes"].get(stat_key, 0))
		if current_value >= rune_cap:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]No improvement possible — %s already has +%d %s (Rune cap: +%d).[/color]" % [target_item.get("name", "item"), current_value, stat_key.replace("_", " "), rune_cap]})
			return
		target_item["affixes"][stat_key] = rune_cap
		_consume_one_from_stack(character, rune_index)
		send_to_peer(peer_id, {"type": "text", "message": "[color=#A335EE]Applied %s to your %s! %s: +%d → +%d[/color]" % [rune.get("name", "Rune"), target_item.get("name", "item"), stat_key.replace("_", " ").capitalize(), current_value, rune_cap]})

	send_character_update(peer_id)
	save_character(peer_id)

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

func _generate_craft_challenge(skill_name: String, job_level: int, is_specialist: bool) -> Dictionary:
	"""Generate a 3-round crafting challenge. Returns client_rounds and correct_answers."""
	var questions = CraftingDatabaseScript.CRAFT_CHALLENGE_QUESTIONS.get(skill_name, [])
	if questions.is_empty():
		# Fallback to blacksmithing if skill not found
		questions = CraftingDatabaseScript.CRAFT_CHALLENGE_QUESTIONS.get("blacksmithing", [])

	# Pick 3 random question sets (non-repeating)
	var indices = range(questions.size())
	var shuffled_indices = []
	for idx in indices:
		shuffled_indices.append(idx)
	shuffled_indices.shuffle()
	var picked = shuffled_indices.slice(0, 3)

	var client_rounds = []
	var correct_answers = []

	# Specialist hints: Lv1-19 = 1 hint (round 1), Lv20-39 = 2 hints, Lv40+ = all 3
	var hints_available = 0
	if is_specialist:
		if job_level >= 40:
			hints_available = 3
		elif job_level >= 20:
			hints_available = 2
		else:
			hints_available = 1

	for round_idx in range(3):
		var q_data = questions[picked[round_idx]]
		var opts = q_data["opts"].duplicate()
		# opts[0] is always correct. Shuffle and track where correct ended up.
		var correct_label = opts[0]
		opts.shuffle()
		var correct_idx = opts.find(correct_label)
		correct_answers.append(correct_idx)

		# Build client round data
		var hint_index = -1
		if round_idx < hints_available:
			# Mark one WRONG answer as "[Risky]"
			var wrong_indices = []
			for i in range(3):
				if i != correct_idx:
					wrong_indices.append(i)
			hint_index = wrong_indices[randi() % wrong_indices.size()]

		client_rounds.append({
			"question": q_data["q"],
			"options": opts,
			"hint_index": hint_index,
		})

	return {
		"client_rounds": client_rounds,
		"correct_answers": correct_answers,
	}

func handle_craft_challenge_answer(peer_id: int, message: Dictionary):
	"""Handle player's answers to the crafting challenge minigame."""
	if not characters.has(peer_id):
		return
	if not active_crafts.has(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "No active crafting challenge!"})
		return

	var character = characters[peer_id]
	var craft = active_crafts[peer_id]
	var answers = message.get("answers", [])
	var correct_answers = craft.get("correct_answers", [])

	# Score the answers
	var score = 0
	for i in range(mini(answers.size(), correct_answers.size())):
		if int(answers[i]) == int(correct_answers[i]):
			score += 1

	# Specialist save: if score is 0, chance to become 1
	if score == 0 and craft.get("is_specialist", false):
		var save_chance = mini(50, craft.get("job_level", 0))
		if randi() % 100 < save_chance:
			score = 1

	# Roll quality with score
	var recipe = craft["recipe"]
	var skill_level = craft["skill_level"]
	var total_bonus = craft["total_bonus"]
	var skill_name = craft["skill_name"]
	var quality = CraftingDatabaseScript.roll_quality(skill_level, recipe.difficulty, total_bonus, score)

	# Clean up pending craft
	active_crafts.erase(peer_id)

	# Re-inject into the crafting pipeline by calling the result handler
	_finalize_craft(peer_id, character, craft["recipe_id"], recipe, quality, skill_name, skill_level, total_bonus, score)

func _finalize_craft(peer_id: int, character, recipe_id: String, recipe: Dictionary, quality: int, skill_name: String, skill_level: int, total_bonus: int, score: int = -1):
	"""Finalize a craft after quality is determined. Handles all output types."""
	var quality_name = CraftingDatabaseScript.QUALITY_NAMES[quality]
	var quality_color = CraftingDatabaseScript.QUALITY_COLORS[quality]

	var xp_gained = CraftingDatabaseScript.calculate_craft_xp(recipe.difficulty, quality)
	var xp_result = character.add_crafting_xp(skill_name, xp_gained)

	# Award character XP from crafting
	var craft_char_xp = xp_result.get("char_xp_gained", 0)
	if craft_char_xp > 0:
		character.add_experience(craft_char_xp)

	var job_xp_gained = 0
	var job_leveled_up = false
	var job_new_level = 0
	var matching_job = character.CRAFT_SKILL_TO_JOB.get(skill_name, "")
	if matching_job != "" and character.can_gain_job_xp(matching_job):
		job_xp_gained = int(xp_gained * 0.5)
		if job_xp_gained > 0:
			var job_result = character.add_job_xp(matching_job, job_xp_gained)
			job_leveled_up = job_result.leveled_up
			job_new_level = job_result.new_level

	var result_message = ""
	var crafted_item = {}

	match recipe.output_type:
			"weapon", "armor":
				crafted_item = _create_crafted_equipment(recipe, quality)
				if crafted_item.is_empty():
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message = "[color=#FF4444]Failed to create item! Materials refunded.[/color]"
				else:
					crafted_item["crafted_by"] = character.name
					character.inventory.append(crafted_item)
					result_message = "[color=%s]Created %s %s![/color]" % [quality_color, quality_name, recipe.name]
			"consumable":
				crafted_item = _create_crafted_consumable(recipe, quality)
				crafted_item["crafted_by"] = character.name
				character.add_item(crafted_item)
				result_message = "[color=%s]Created %s %s![/color]" % [quality_color, quality_name, recipe.name]
			"rune":
				crafted_item = _create_crafted_rune(recipe, quality, character.name)
				character.add_item(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", recipe.name)]
			"enhancement":
				var effect = recipe.get("effect", {})
				var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
				var stat_type = effect.get("stat", "attack")
				var base_bonus = 3 if stat_type == "all" else effect.get("bonus", 3)
				var scaled_bonus = int(base_bonus * quality_mult)
				var scroll = {
					"id": "scroll_%d" % randi(),
					"name": "%s %s" % [quality_name, recipe.name] if quality != CraftingDatabaseScript.CraftingQuality.STANDARD else recipe.name,
					"type": "enhancement_scroll",
					"slot": recipe.get("output_slot", "any"),
					"effect": {"stat": stat_type, "bonus": scaled_bonus},
					"rarity": _quality_to_rarity(quality),
					"level": 1, "is_consumable": true, "quantity": 1,
					"crafted_by": character.name
				}
				character.add_item(scroll)
				crafted_item = scroll
				result_message = "[color=%s]Created %s![/color]" % [quality_color, scroll.name]
			"enchantment":
				var target_slots = recipe.get("target_slot", "").split(",")
				var target_item = null
				for slot in target_slots:
					slot = slot.strip_edges()
					if character.equipped.has(slot) and character.equipped[slot] != null:
						target_item = character.equipped[slot]
						break
				if target_item == null:
					result_message = "[color=#FF4444]No equipment in %s slot to enchant![/color]" % recipe.get("target_slot", "")
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
				else:
					var effect = recipe.get("effect", {})
					var stat = effect.get("stat", "attack")
					var bonus = effect.get("bonus", 5)
					var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
					bonus = int(bonus * quality_mult)
					if not target_item.has("enchantments"):
						target_item["enchantments"] = {}
					var current_value = target_item["enchantments"].get(stat, 0)
					var recipe_enchant_max = recipe.get("max_enchant_value", 9999)
					if current_value >= recipe_enchant_max:
						result_message = "[color=#FFFF00]%s already has +%d %s — this recipe only works up to +%d. Use a higher-tier enchantment![/color]" % [target_item.get("name", "item"), current_value, stat, recipe_enchant_max]
						for mat_id in recipe.materials:
							character.add_crafting_material(mat_id, recipe.materials[mat_id])
						result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
					elif current_value >= CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(stat, 60):
						var stat_cap = CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(stat, 60)
						result_message = "[color=#FFFF00]%s has reached the %s enchantment cap (+%d)![/color]" % [target_item.get("name", "item"), stat, stat_cap]
						for mat_id in recipe.materials:
							character.add_crafting_material(mat_id, recipe.materials[mat_id])
						result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
					else:
						var max_types = CraftingDatabaseScript.MAX_ENCHANTMENT_TYPES
						if not target_item["enchantments"].has(stat) and target_item["enchantments"].size() >= max_types:
							result_message = "[color=#FFFF00]%s already has %d enchantment types (max %d)! Remove one first.[/color]" % [target_item.get("name", "item"), target_item["enchantments"].size(), max_types]
							for mat_id in recipe.materials:
								character.add_crafting_material(mat_id, recipe.materials[mat_id])
							result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
						else:
							var stat_cap_val = CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get(stat, 60)
							var effective_cap = mini(recipe_enchant_max, stat_cap_val)
							var remaining = effective_cap - current_value
							if bonus > remaining:
								bonus = remaining
							target_item["enchantments"][stat] = current_value + bonus
							target_item["enchanted_by"] = character.name
							result_message = "[color=%s]Enchanted %s with +%d %s! (%d/%d cap)[/color]" % [quality_color, target_item.get("name", "item"), bonus, stat, current_value + bonus, stat_cap_val]
			"upgrade":
				var target_slots = recipe.get("target_slot", "").split(",")
				var target_item = null
				for slot in target_slots:
					slot = slot.strip_edges()
					if character.equipped.has(slot) and character.equipped[slot] != null:
						target_item = character.equipped[slot]
						break
				if target_item == null:
					result_message = "[color=#FF4444]No equipment in %s slot to upgrade![/color]" % recipe.get("target_slot", "")
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
				else:
					var effect = recipe.get("effect", {})
					var levels_to_add = effect.get("levels", 1)
					if quality == CraftingDatabaseScript.CraftingQuality.MASTERWORK:
						levels_to_add = int(levels_to_add * 1.5)
					elif quality == CraftingDatabaseScript.CraftingQuality.FINE:
						levels_to_add = int(levels_to_add * 1.25)
					elif quality == CraftingDatabaseScript.CraftingQuality.POOR:
						levels_to_add = max(1, int(levels_to_add * 0.5))
					var upgrades_applied = target_item.get("upgrades_applied", 0)
					var recipe_max = recipe.get("max_upgrades", CraftingDatabaseScript.MAX_UPGRADE_LEVELS)
					if upgrades_applied >= recipe_max:
						result_message = "[color=#FFFF00]%s has %d upgrades — this recipe only works up to +%d. Use a higher-tier upgrade recipe![/color]" % [target_item.get("name", "item"), upgrades_applied, recipe_max]
						for mat_id in recipe.materials:
							character.add_crafting_material(mat_id, recipe.materials[mat_id])
						result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
					elif upgrades_applied >= CraftingDatabaseScript.MAX_UPGRADE_LEVELS:
						result_message = "[color=#FFFF00]%s has reached the upgrade cap (+%d levels)![/color]" % [target_item.get("name", "item"), CraftingDatabaseScript.MAX_UPGRADE_LEVELS]
						for mat_id in recipe.materials:
							character.add_crafting_material(mat_id, recipe.materials[mat_id])
						result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
					else:
						var global_max = CraftingDatabaseScript.MAX_UPGRADE_LEVELS
						var remaining = mini(recipe_max, global_max) - upgrades_applied
						if levels_to_add > remaining:
							levels_to_add = remaining
						var old_level = target_item.get("level", 1)
						target_item["level"] = old_level + levels_to_add
						target_item["upgrades_applied"] = upgrades_applied + levels_to_add
						result_message = "[color=%s]Upgraded %s from level %d to %d! (%d/%d upgrade cap)[/color]" % [quality_color, target_item.get("name", "item"), old_level, old_level + levels_to_add, upgrades_applied + levels_to_add, global_max]
			"affix":
				var target_slots = recipe.get("target_slot", "").split(",")
				var target_item = null
				for slot in target_slots:
					slot = slot.strip_edges()
					if character.equipped.has(slot) and character.equipped[slot] != null:
						target_item = character.equipped[slot]
						break
				if target_item == null:
					result_message = "[color=#FF4444]No equipment in %s slot for affix![/color]" % recipe.get("target_slot", "")
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
				else:
					var effect = recipe.get("effect", {})
					var affix_pool = effect.get("affix_pool", ["attack"])
					var chosen_affix = affix_pool[randi() % affix_pool.size()]
					var item_level = target_item.get("level", 1)
					var base_value = 5 + int(item_level * 0.5)
					var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
					var affix_value = int(base_value * quality_mult)
					var affix_key_map = {
						"strength": "str_bonus", "constitution": "con_bonus",
						"dexterity": "dex_bonus", "intelligence": "int_bonus",
						"wisdom": "wis_bonus", "wits": "wits_bonus",
						"attack": "attack_bonus", "defense": "defense_bonus",
						"speed": "speed_bonus", "mana": "mana_bonus"
					}
					var affix_key = affix_key_map.get(chosen_affix, chosen_affix + "_bonus")
					if not target_item.has("affixes"):
						target_item["affixes"] = {}
					var old_value = target_item["affixes"].get(affix_key, 0)
					var affix_display = chosen_affix.capitalize()
					var item_name = target_item.get("name", "item")
					if affix_value > old_value:
						target_item["affixes"][affix_key] = affix_value
						if old_value > 0:
							result_message = "[color=%s]Upgraded %s affix on %s: %d → %d![/color]" % [quality_color, affix_display, item_name, old_value, affix_value]
						else:
							result_message = "[color=%s]Added +%d %s affix to %s![/color]" % [quality_color, affix_value, affix_display, item_name]
					else:
						result_message = "[color=#FFFF00]Rolled +%d %s, but %s already has +%d. No change.[/color]" % [affix_value, affix_display, item_name, old_value]
			"tool":
				var tool_type = recipe.get("tool_type", "")
				var tool_tier = recipe.get("tier", 1)
				var subtype_map = {"fishing_rod": "rod", "pickaxe": "pickaxe", "axe": "axe", "sickle": "sickle"}
				var subtype = subtype_map.get(tool_type, tool_type)
				var tool_rarity = _quality_to_rarity(quality)
				var tool_data = DropTables.generate_tool(subtype, tool_tier, tool_rarity)
				if not tool_data.is_empty():
					if quality != CraftingDatabaseScript.CraftingQuality.STANDARD:
						tool_data["name"] = "%s %s" % [quality_name, recipe.name]
					tool_data["crafted"] = true
					character.inventory.append(tool_data)
					crafted_item = tool_data
					result_message = "[color=%s]Crafted %s! Check your inventory to equip it.[/color]" % [quality_color, tool_data.get("name", recipe.name)]
				else:
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message = "[color=#FF4444]Failed to create tool! Materials refunded.[/color]"
			"material":
				var output_item = recipe.get("output_item", "")
				var base_quantity = recipe.get("output_quantity", 1)
				var multiplier = CraftingDatabaseScript.QUALITY_MULTIPLIERS[quality]
				var final_quantity = int(base_quantity * multiplier)
				if output_item != "" and final_quantity > 0:
					character.add_crafting_material(output_item, final_quantity)
					result_message = "[color=%s]Created %d %s %s![/color]" % [quality_color, final_quantity, quality_name, recipe.name.replace("Refine ", "")]
				else:
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message = "[color=#FF4444]Failed to create materials! Materials refunded.[/color]"
			"self_repair":
				result_message = _craft_self_repair(character, recipe, quality)
			"reforge":
				result_message = _craft_reforge(character, recipe, quality, quality_color)
			"transmute":
				result_message = _craft_transmute(character, recipe, quality, quality_color)
			"extract":
				result_message = _craft_extract(character, recipe, quality, quality_color)
			"disenchant":
				result_message = _craft_disenchant(character, recipe, quality, quality_color)
			"scroll":
				crafted_item = _craft_scroll(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", "scroll")]
			"map":
				crafted_item = _craft_map(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", "map")]
			"tome":
				crafted_item = _craft_tome(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", "tome")]
			"bestiary":
				crafted_item = _craft_bestiary(recipe, quality)
				character.inventory.append(crafted_item)
				result_message = "[color=%s]Created %s![/color]" % [quality_color, crafted_item.get("name", "bestiary page")]
			"structure":
				crafted_item = _craft_structure(recipe, quality)
				character.inventory.append(crafted_item)
				quality = CraftingDatabaseScript.CraftingQuality.STANDARD
				quality_name = "Standard"
				quality_color = "#FFFFFF"
				result_message = "[color=#00FF00]Built %s![/color]" % crafted_item.get("name", "structure")
			"proc_enchant":
				var target_slots = recipe.get("target_slot", "").split(",")
				var target_item = null
				for slot in target_slots:
					slot = slot.strip_edges()
					if character.equipped.has(slot) and character.equipped[slot] != null:
						target_item = character.equipped[slot]
						break
				if target_item == null:
					result_message = "[color=#FF4444]No equipment in %s slot to enchant![/color]" % recipe.get("target_slot", "")
					for mat_id in recipe.materials:
						character.add_crafting_material(mat_id, recipe.materials[mat_id])
					result_message += "\n[color=#FFFF00]Materials refunded.[/color]"
				else:
					var effect = recipe.get("effect", {})
					var proc_type = effect.get("proc_type", "")
					if not target_item.has("proc_effects"):
						target_item["proc_effects"] = {}
					var quality_mult = CraftingDatabaseScript.QUALITY_MULTIPLIERS.get(quality, 1.0)
					var proc_data = {}
					var proc_item_name = target_item.get("name", "item")
					match proc_type:
						"lifesteal":
							var pct = effect.get("percent", 10) * quality_mult
							proc_data = {"percent": pct, "proc_chance": effect.get("proc_chance", 1.0)}
							result_message = "[color=%s]Enchanted %s with %d%% Lifesteal![/color]" % [quality_color, proc_item_name, int(pct)]
						"shocking":
							var pct = effect.get("percent", 15) * quality_mult
							proc_data = {"percent": pct, "proc_chance": effect.get("proc_chance", 0.25)}
							result_message = "[color=%s]Enchanted %s with Shocking (+%d%% damage, %d%% chance)![/color]" % [quality_color, proc_item_name, int(pct), int(effect.get("proc_chance", 0.25) * 100)]
						"damage_reflect":
							var pct = effect.get("percent", 15) * quality_mult
							proc_data = {"percent": pct, "proc_chance": effect.get("proc_chance", 1.0)}
							result_message = "[color=%s]Enchanted %s with %d%% Damage Reflect![/color]" % [quality_color, proc_item_name, int(pct)]
						"execute":
							var bonus = effect.get("bonus_damage", 50) * quality_mult
							proc_data = {"bonus_damage": bonus, "proc_chance": effect.get("proc_chance", 0.25), "threshold": effect.get("threshold", 0.3)}
							result_message = "[color=%s]Enchanted %s with Execute (+%d%% damage below 30%% HP)![/color]" % [quality_color, proc_item_name, int(bonus)]
					target_item["proc_effects"][proc_type] = proc_data
			_:
				result_message = "[color=%s]Crafted %s %s![/color]" % [quality_color, quality_name, recipe.name]

	send_to_peer(peer_id, {
		"type": "craft_result",
		"success": true,
		"recipe_id": recipe_id,
		"quality": quality,
		"quality_name": quality_name,
		"quality_color": quality_color,
		"recipe_name": recipe.name,
		"crafted_item": crafted_item,
		"message": result_message,
		"materials": character.crafting_materials,
		"xp_gained": xp_gained,
		"char_xp_gained": craft_char_xp,
		"skill_name": skill_name,
		"leveled_up": xp_result.get("leveled_up", false),
		"new_level": xp_result.get("new_level", skill_level),
		"job_xp_gained": job_xp_gained,
		"job_leveled_up": job_leveled_up,
		"job_new_level": job_new_level,
		"job_name": matching_job,
		"score": score,
	})

	send_character_update(peer_id)
	save_character(peer_id)

# ===== BUILDING SYSTEM =====

const DEFAULT_MAX_PLAYER_ENCLOSURES = 5
const MAX_ENCLOSURE_SIZE = 11  # 11x11 bounding box max
const MAX_PLAYER_TILES = 200
const BUILDING_TYPES = ["wall", "door", "forge", "apothecary", "workbench", "enchant_table", "writing_desk", "tower", "inn", "quest_board", "storage", "blacksmith", "healer", "market", "guard"]
const ENCLOSURE_WALL_TYPES = ["wall", "door"]  # Types that form enclosure boundaries

# In-memory enclosure tracking: {username: [Array of interior tile positions]}
var player_enclosures: Dictionary = {}
# Player post naming: {username: [{name, center, created_at}]} — index-aligned with player_enclosures
var player_post_names: Dictionary = {}
# Fast lookup for enclosure tile checks: Vector2i -> {owner: String, enclosure_idx: int}
var enclosure_tile_lookup: Dictionary = {}

func _get_max_post_count(peer_id: int) -> int:
	"""Get max enclosure/post count for a player (base 5 + post_slots upgrade)."""
	if not peers.has(peer_id):
		return DEFAULT_MAX_PLAYER_ENCLOSURES
	var account_id = peers[peer_id].get("account_id", "")
	if account_id == "":
		return DEFAULT_MAX_PLAYER_ENCLOSURES
	var house = persistence.get_house(account_id)
	var upgrade_level = house.get("upgrades", {}).get("post_slots", 0)
	return DEFAULT_MAX_PLAYER_ENCLOSURES + upgrade_level

func _get_max_post_count_for_username(username: String) -> int:
	"""Get max post count by username (used during rebuild when peer_id unavailable)."""
	for pid in peers:
		if _get_username(pid) == username:
			return _get_max_post_count(pid)
	# Player not online — use max possible to avoid losing enclosures during rebuild.
	# Actual limit is enforced when building new ones (via _get_max_post_count with peer_id).
	var max_upgrade = PersistenceManager.HOUSE_UPGRADES.get("post_slots", {}).get("max", 5)
	return DEFAULT_MAX_PLAYER_ENCLOSURES + max_upgrade

func handle_build_place(peer_id: int, message: Dictionary):
	"""Handle player placing a structure tile in a direction."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var username = _get_username(peer_id)

	var item_index = int(message.get("item_index", -1))
	var direction = int(message.get("direction", 0))

	# Validate item
	if item_index < 0 or item_index >= character.inventory.size():
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Invalid item!"})
		return
	var item = character.inventory[item_index]
	if item.get("type", "") != "structure":
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "That's not a buildable item!"})
		return

	var structure_type = item.get("structure_type", "")
	if structure_type not in BUILDING_TYPES:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Cannot place that item!"})
		return

	# Calculate target position from direction
	var target = world_system.get_direction_offset(character.x, character.y, direction)
	var tx = target.x
	var ty = target.y

	# Can't place on self
	if tx == character.x and ty == character.y:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Select a direction to place!"})
		return

	# Check world bounds
	if tx < -1000 or tx > 1000 or ty < -1000 or ty > 1000:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Out of bounds!"})
		return

	# Check target tile is placeable (not water, not already a player tile, not NPC post)
	if not chunk_manager:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "World not ready!"})
		return

	var existing_tile = chunk_manager.get_tile(tx, ty)
	var existing_type = existing_tile.get("type", "")
	if existing_tile.get("owner", "") != "":
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Someone already built here!"})
		return
	if existing_type in ["wall", "door", "void", "forge", "apothecary", "workbench", "enchant_table", "writing_desk", "post_marker", "market", "inn", "quest_board", "throne"]:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Cannot build on this tile!"})
		return
	if world_system:
		var terrain = world_system.get_terrain_at(tx, ty)
		if terrain in [world_system.Terrain.WATER, world_system.Terrain.DEEP_WATER, world_system.Terrain.VOID]:
			send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Cannot build on water or void!"})
			return

	# Check NPC post proximity (3 tile buffer)
	if chunk_manager:
		for post in chunk_manager.get_npc_posts():
			var post_half = int(post.get("size", 15)) / 2 + 3
			if abs(tx - int(post.get("x", 0))) <= post_half and abs(ty - int(post.get("y", 0))) <= post_half:
				send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Too close to a town. Must be 3+ tiles away."})
				return

	# Check dungeon entrance proximity (3 tile buffer)
	for instance in active_dungeons.values():
		if abs(tx - int(instance.get("world_x", 0))) <= 3 and abs(ty - int(instance.get("world_y", 0))) <= 3:
			send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Too close to a dungeon entrance."})
			return

	# Check another player isn't standing there (for walls)
	if structure_type == "wall" and is_player_at(tx, ty, -1):
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "A player is standing there!"})
		return

	# Guard posts can be placed anywhere (not just inside enclosures) but need 10-tile spacing
	if structure_type == "guard":
		if _has_nearby_guard_post(tx, ty, 10):
			send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Too close to another guard post! Must be 10+ tiles away."})
			return
	# Structures (non-wall/door/guard) can only be placed inside an enclosure you own
	elif structure_type not in ENCLOSURE_WALL_TYPES:
		if not _is_in_own_enclosure(tx, ty, username):
			send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Structures must be placed inside your enclosure!"})
			return

	# Check tile limit
	var placed_tiles = persistence.get_player_tiles(username)
	if placed_tiles.size() >= MAX_PLAYER_TILES:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Tile limit reached (%d max)!" % MAX_PLAYER_TILES})
		return

	# Consume item
	character.inventory.remove_at(item_index)

	# Determine tile properties
	var blocks_move = structure_type == "wall"
	var blocks_los = structure_type == "wall"

	# Place tile in chunk manager
	var tile_data = {
		"type": structure_type,
		"owner": username,
		"blocks_move": blocks_move,
		"blocks_los": blocks_los,
	}
	if structure_type == "wall":
		tile_data["placed_at"] = Time.get_unix_time_from_system()
	chunk_manager.set_tile(tx, ty, tile_data)

	# Track placed tile (include placed_at for wall decay tracking)
	var tile_meta = {}
	if structure_type == "wall":
		tile_meta["placed_at"] = tile_data["placed_at"]
	persistence.add_player_tile(username, tx, ty, structure_type, tile_meta)

	# Check for new enclosures after placing wall/door
	var enclosure_msg = ""
	if structure_type in ENCLOSURE_WALL_TYPES:
		enclosure_msg = _check_enclosures_after_build(username, peer_id)

	chunk_manager.save_dirty_chunks()

	var display_name = item.get("name", structure_type.replace("_", " ").capitalize())
	var msg = "[color=#00FF00]Placed %s![/color]" % display_name
	if enclosure_msg != "":
		msg += "\n" + enclosure_msg

	send_to_peer(peer_id, {"type": "build_result", "success": true, "message": msg})
	send_character_update(peer_id)
	send_location_update(peer_id)
	save_character(peer_id)

func handle_build_demolish(peer_id: int, message: Dictionary):
	"""Handle player demolishing a tile they placed."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var username = _get_username(peer_id)

	var direction = int(message.get("direction", 0))
	var target = world_system.get_direction_offset(character.x, character.y, direction)
	var tx = target.x
	var ty = target.y

	if tx == character.x and ty == character.y:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "Select a direction to demolish!"})
		return

	if not chunk_manager:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "World not ready!"})
		return

	var tile = chunk_manager.get_tile(tx, ty)
	var tile_owner = tile.get("owner", "")
	if tile_owner != username:
		send_to_peer(peer_id, {"type": "build_result", "success": false, "message": "You can only demolish your own structures!"})
		return

	var tile_type = tile.get("type", "")

	# If demolishing a guard post, remove any active guard
	if tile_type == "guard":
		var pos_key = "%d,%d" % [tx, ty]
		if active_guards.has(pos_key):
			active_guards.erase(pos_key)
			_update_guard_cache()
			persistence.save_guards(active_guards)

	# Remove the tile (revert to procedural)
	chunk_manager.remove_tile_modification(tx, ty)

	# Remove from tracking
	persistence.remove_player_tile(username, tx, ty)

	# Re-check enclosures if wall/door was removed (may break an enclosure)
	var enclosure_msg = ""
	if tile_type in ENCLOSURE_WALL_TYPES:
		enclosure_msg = _recheck_enclosures_after_demolish(username)

	chunk_manager.save_dirty_chunks()

	var msg = "[color=#FFFF00]Demolished %s.[/color]" % tile_type.replace("_", " ").capitalize()
	if enclosure_msg != "":
		msg += "\n" + enclosure_msg

	send_to_peer(peer_id, {"type": "build_result", "success": true, "message": msg})
	send_location_update(peer_id)

func _is_in_own_enclosure(x: int, y: int, username: String) -> bool:
	"""Check if a position is inside one of the player's enclosures."""
	if not player_enclosures.has(username):
		return false
	for enclosure in player_enclosures[username]:
		for pos in enclosure:
			if int(pos.x) == x and int(pos.y) == y:
				return true
	return false

func _has_nearby_guard_post(x: int, y: int, min_distance: int) -> bool:
	"""Check if there's another guard post within min_distance tiles (Manhattan distance)."""
	if not chunk_manager:
		return false
	# Check all player tiles for guard posts
	var all_tiles = persistence.player_tiles_data.get("tiles", {})
	for username_key in all_tiles:
		for td in all_tiles[username_key]:
			if td.get("type", "") == "guard":
				var gx = int(td.get("x", 0))
				var gy = int(td.get("y", 0))
				if abs(x - gx) + abs(y - gy) < min_distance:
					return true
	return false

func _check_enclosures_after_build(username: String, peer_id: int = -1) -> String:
	"""After placing a wall/door, detect any new enclosures. Returns status message."""
	var placed = persistence.get_player_tiles(username)
	# Find all wall/door tiles for this player
	var wall_positions = []
	for td in placed:
		if td.get("type", "") in ENCLOSURE_WALL_TYPES:
			wall_positions.append(Vector2i(int(td.x), int(td.y)))

	if wall_positions.size() < 4:
		return ""  # Need at least 4 walls to make an enclosure

	# Check each non-wall neighbor of each wall for potential enclosed regions
	var checked_regions: Array = []
	var new_enclosures: Array = []

	for wall_pos in wall_positions:
		for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var check_pos = wall_pos + offset
			# Skip if already part of a checked region
			var already_checked = false
			for region in checked_regions:
				if check_pos in region:
					already_checked = true
					break
			if already_checked:
				continue

			# Skip if this is a wall/door tile
			var check_tile = chunk_manager.get_tile(check_pos.x, check_pos.y)
			if check_tile.get("blocks_move", false):
				continue
			if check_tile.get("type", "") in ENCLOSURE_WALL_TYPES and check_tile.get("owner", "") == username:
				continue

			# Try to detect enclosure via BFS
			var result = _detect_enclosure_bfs(check_pos, username)
			if result.size() > 0:
				checked_regions.append(result)
				# Check if this enclosure is already known
				var is_new = true
				if player_enclosures.has(username):
					for existing in player_enclosures[username]:
						if existing.size() == result.size():
							var match_count = 0
							for p in result:
								if p in existing:
									match_count += 1
							if match_count == result.size():
								is_new = false
								break
				if is_new:
					new_enclosures.append(result)

	if new_enclosures.is_empty():
		return ""

	# Check enclosure limit (dynamic based on house upgrade)
	var max_posts = _get_max_post_count(peer_id) if peer_id >= 0 else _get_max_post_count_for_username(username)
	var current_count = player_enclosures.get(username, []).size()
	var added = 0
	for enclosure in new_enclosures:
		if current_count + added >= max_posts:
			break
		if not player_enclosures.has(username):
			player_enclosures[username] = []
		player_enclosures[username].append(enclosure)
		_mark_enclosure_safe(enclosure, username)
		# Calculate center and create post metadata
		var center = _calculate_enclosure_center(enclosure)
		var enc_idx = player_enclosures[username].size() - 1
		_update_enclosure_tile_lookup(enclosure, username, enc_idx)
		if not player_post_names.has(username):
			player_post_names[username] = []
		player_post_names[username].append({"name": "", "center": center, "created_at": int(Time.get_unix_time_from_system())})
		# Send naming prompt to player
		if peer_id >= 0:
			send_to_peer(peer_id, {"type": "name_post_prompt", "enclosure_index": enc_idx})
		added += 1

	if added > 0:
		return "[color=#00FFFF]Enclosure formed! (%d/%d)[/color]" % [current_count + added, max_posts]
	elif new_enclosures.size() > 0:
		return "[color=#FF8800]Enclosure limit reached (%d/%d)![/color]" % [max_posts, max_posts]
	return ""

func _calculate_enclosure_center(positions: Array) -> Vector2i:
	"""Calculate the center tile of an enclosure."""
	var sum_x = 0
	var sum_y = 0
	for pos in positions:
		sum_x += int(pos.x)
		sum_y += int(pos.y)
	return Vector2i(sum_x / positions.size(), sum_y / positions.size())

func _update_enclosure_tile_lookup(positions: Array, owner: String, enclosure_idx: int):
	"""Add enclosure interior tiles to the fast lookup dict."""
	for pos in positions:
		enclosure_tile_lookup[Vector2i(int(pos.x), int(pos.y))] = {"owner": owner, "enclosure_idx": enclosure_idx}

func _remove_enclosure_from_tile_lookup(positions: Array):
	"""Remove enclosure interior tiles from the fast lookup dict."""
	for pos in positions:
		enclosure_tile_lookup.erase(Vector2i(int(pos.x), int(pos.y)))

func _recheck_enclosures_after_demolish(username: String) -> String:
	"""After demolishing a wall/door, re-validate all enclosures for this player."""
	if not player_enclosures.has(username):
		return ""

	var broken_count = 0
	var remaining: Array = []
	var remaining_names: Array = []
	var old_names = player_post_names.get(username, [])

	for idx in range(player_enclosures[username].size()):
		var enclosure = player_enclosures[username][idx]
		# Remove old lookup entries
		_remove_enclosure_from_tile_lookup(enclosure)
		# Re-check if this enclosure is still valid
		if enclosure.size() > 0:
			var still_valid = _detect_enclosure_bfs(enclosure[0], username)
			if still_valid.size() > 0:
				var new_idx = remaining.size()
				remaining.append(still_valid)
				_update_enclosure_tile_lookup(still_valid, username, new_idx)
				# Preserve post name
				if idx < old_names.size():
					remaining_names.append(old_names[idx])
				else:
					remaining_names.append({"name": "", "center": _calculate_enclosure_center(still_valid), "created_at": 0})
			else:
				# Enclosure broken - unmark interior tiles
				_unmark_enclosure_safe(enclosure)
				broken_count += 1

	player_enclosures[username] = remaining
	player_post_names[username] = remaining_names

	if broken_count > 0:
		# Re-persist the entire remaining post list (cleaner than index-based removal during iteration)
		if not persistence.player_posts_data.has("posts"):
			persistence.player_posts_data["posts"] = {}
		persistence.player_posts_data.posts[username] = []
		for i in range(remaining_names.size()):
			var meta = remaining_names[i]
			var cx = int(meta.center.x) if meta.center is Vector2i else int(meta.get("center", {}).get("x", 0))
			var cy = int(meta.center.y) if meta.center is Vector2i else int(meta.get("center", {}).get("y", 0))
			persistence.set_player_post(username, i, {
				"name": meta.get("name", ""),
				"center_x": cx,
				"center_y": cy,
				"created_at": int(meta.get("created_at", 0))
			})
		var max_posts = _get_max_post_count_for_username(username)
		return "[color=#FF8800]Enclosure broken! (%d/%d remaining)[/color]" % [remaining.size(), max_posts]
	return ""

func _detect_enclosure_bfs(start: Vector2i, owner: String) -> Array:
	"""BFS flood fill from start position. Returns interior tile positions if enclosed
	by walls/doors owned by owner. Returns empty array if not enclosed."""
	if not chunk_manager:
		return []

	var queue: Array = [start]
	var visited: Dictionary = {start: true}
	var interior: Array = [start]
	var has_player_wall = false
	var has_player_door = false
	var min_x = start.x
	var max_x = start.x
	var min_y = start.y
	var max_y = start.y

	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1

		for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var neighbor = current + offset
			if visited.has(neighbor):
				continue
			visited[neighbor] = true

			var tile = chunk_manager.get_tile(neighbor.x, neighbor.y)
			var tile_type = tile.get("type", "")
			var tile_owner = tile.get("owner", "")

			# Check if this is a boundary wall/door
			if tile.get("blocks_move", false) or (tile_type in ENCLOSURE_WALL_TYPES and tile_owner == owner):
				if tile_owner == owner:
					if tile_type == "wall":
						has_player_wall = true
					elif tile_type == "door":
						has_player_door = true
				continue  # Don't expand through walls

			# Passable tile - add to interior
			interior.append(neighbor)

			# Check bounding box
			min_x = min(min_x, neighbor.x)
			max_x = max(max_x, neighbor.x)
			min_y = min(min_y, neighbor.y)
			max_y = max(max_y, neighbor.y)

			# Check size limits
			if max_x - min_x >= MAX_ENCLOSURE_SIZE or max_y - min_y >= MAX_ENCLOSURE_SIZE:
				return []  # Too big
			if interior.size() > MAX_ENCLOSURE_SIZE * MAX_ENCLOSURE_SIZE:
				return []  # Too many tiles

			queue.append(neighbor)

	# BFS completed - check if valid enclosure
	if not has_player_wall or not has_player_door:
		return []  # Must have at least one player wall and one door
	if interior.size() < 1:
		return []

	return interior

func _mark_enclosure_safe(positions: Array, owner: String):
	"""Mark interior tiles as safe zone by setting enclosure_owner."""
	if not chunk_manager:
		return
	for pos in positions:
		var tile = chunk_manager.get_tile(pos.x, pos.y)
		tile["enclosure_owner"] = owner
		chunk_manager.set_tile(pos.x, pos.y, tile)

func _unmark_enclosure_safe(positions: Array):
	"""Remove safe zone marking from tiles."""
	if not chunk_manager:
		return
	for pos in positions:
		var tile = chunk_manager.get_tile(pos.x, pos.y)
		if tile.has("enclosure_owner"):
			if tile.has("owner"):
				# Player-placed tile - keep it, just remove enclosure marking
				tile.erase("enclosure_owner")
				chunk_manager.set_tile(pos.x, pos.y, tile)
			else:
				# Natural tile - revert to procedural
				chunk_manager.remove_tile_modification(pos.x, pos.y)

func _rebuild_all_player_enclosures():
	"""Rebuild enclosure data from persisted tile tracking. Called on server startup."""
	player_enclosures.clear()
	player_post_names.clear()
	enclosure_tile_lookup.clear()
	var all_tiles = persistence.get_all_player_tiles()
	for username in all_tiles:
		var tiles = all_tiles[username]
		# Re-stamp all player tiles into chunks (they should already be there from chunk save, but ensure)
		for td in tiles:
			var tx = int(td.get("x", 0))
			var ty = int(td.get("y", 0))
			var tile_type = td.get("type", "wall")
			var blocks_move = tile_type == "wall"
			var blocks_los = tile_type == "wall"
			chunk_manager.set_tile(tx, ty, {
				"type": tile_type,
				"owner": username,
				"blocks_move": blocks_move,
				"blocks_los": blocks_los,
			})
		# Now detect enclosures
		_rebuild_enclosures_for_player(username)

func _rebuild_enclosures_for_player(username: String):
	"""Detect all enclosures for a player from their placed tiles."""
	var placed = persistence.get_player_tiles(username)
	var wall_positions: Array = []
	for td in placed:
		if td.get("type", "") in ENCLOSURE_WALL_TYPES:
			wall_positions.append(Vector2i(int(td.x), int(td.y)))

	if wall_positions.size() < 4:
		return

	var max_posts = _get_max_post_count_for_username(username)
	var found_enclosures: Array = []
	var all_interior_tiles: Dictionary = {}  # Track to avoid duplicate detection

	for wall_pos in wall_positions:
		for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var check_pos = wall_pos + offset
			if all_interior_tiles.has(check_pos):
				continue
			var check_tile = chunk_manager.get_tile(check_pos.x, check_pos.y)
			if check_tile.get("blocks_move", false):
				continue
			if check_tile.get("type", "") in ENCLOSURE_WALL_TYPES and check_tile.get("owner", "") == username:
				continue

			var result = _detect_enclosure_bfs(check_pos, username)
			if result.size() > 0 and found_enclosures.size() < max_posts:
				var enc_idx = found_enclosures.size()
				found_enclosures.append(result)
				for pos in result:
					all_interior_tiles[pos] = true
				_mark_enclosure_safe(result, username)
				_update_enclosure_tile_lookup(result, username, enc_idx)

	if found_enclosures.size() > 0:
		player_enclosures[username] = found_enclosures
		# Restore post names from persistence by matching center coordinates
		var saved_posts = persistence.get_player_posts(username)
		var rebuilt_names: Array = []
		for enc in found_enclosures:
			var center = _calculate_enclosure_center(enc)
			var matched_name = ""
			var matched_at = 0
			for sp in saved_posts:
				var sc = Vector2i(int(sp.get("center_x", sp.get("center", {}).get("x", 0))), int(sp.get("center_y", sp.get("center", {}).get("y", 0))))
				if abs(center.x - sc.x) <= 1 and abs(center.y - sc.y) <= 1:
					matched_name = sp.get("name", "")
					matched_at = int(sp.get("created_at", 0))
					break
			rebuilt_names.append({"name": matched_name, "center": center, "created_at": matched_at})
		player_post_names[username] = rebuilt_names
		log_message("Rebuilt %d enclosures for %s" % [found_enclosures.size(), username])

func handle_name_post(peer_id: int, message: Dictionary):
	"""Handle player naming a newly formed enclosure/post."""
	var username = _get_username(peer_id)
	if username.is_empty():
		return
	var enc_index = int(message.get("enclosure_index", -1))
	var name_text = str(message.get("name", "")).strip_edges()

	if enc_index < 0 or not player_post_names.has(username) or enc_index >= player_post_names[username].size():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000]Invalid enclosure.[/color]"})
		return

	# Validate name
	if name_text.is_empty() or name_text.length() > 30:
		name_text = "%s's Post" % username
	# Strip BBCode tags for safety
	var regex = RegEx.new()
	regex.compile("\\[.*?\\]")
	name_text = regex.sub(name_text, "", true)
	if name_text.is_empty():
		name_text = "%s's Post" % username

	player_post_names[username][enc_index].name = name_text
	# Persist
	var meta = player_post_names[username][enc_index]
	persistence.set_player_post(username, enc_index, {
		"name": meta.name,
		"center_x": int(meta.center.x),
		"center_y": int(meta.center.y),
		"created_at": meta.created_at
	})
	send_to_peer(peer_id, {"type": "post_named", "name": name_text})
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FFFF]Post established: %s[/color]" % name_text})

func _check_nearby_player_posts(peer_id: int, px: int, py: int):
	"""Check for nearby named player posts and send a compass hint."""
	var username = _get_username(peer_id)
	for owner in player_post_names:
		if owner == username:
			continue
		for meta in player_post_names[owner]:
			if meta.get("name", "").is_empty():
				continue
			var cx = int(meta.center.x) if meta.center is Vector2i else int(meta.get("center", {}).get("x", 0))
			var cy = int(meta.center.y) if meta.center is Vector2i else int(meta.get("center", {}).get("y", 0))
			var dist = max(abs(px - cx), abs(py - cy))
			if dist <= 50 and dist > 0:
				var dir = _get_compass_direction(px, py, cx, cy)
				send_to_peer(peer_id, {"type": "text", "message": "[color=#888888]You sense a player post to the %s...[/color]" % dir})
				return  # One hint per check

func _get_compass_direction(from_x: int, from_y: int, to_x: int, to_y: int) -> String:
	"""Get compass direction string from one position to another."""
	var dx = to_x - from_x
	var dy = to_y - from_y
	var dir = ""
	if dy < 0: dir += "N"
	elif dy > 0: dir += "S"
	if dx > 0: dir += "E"
	elif dx < 0: dir += "W"
	if dir.is_empty(): dir = "nearby"
	return dir

func _get_username(peer_id: int) -> String:
	"""Get username for a peer_id."""
	if peers.has(peer_id):
		return peers[peer_id].get("username", "")
	return ""

# ===== GUARD SYSTEM HANDLERS =====

func _handle_guard_post_interact(peer_id: int, character, gx: int, gy: int):
	"""Handle player bumping into a guard post tile."""
	var pos_key = "%d,%d" % [gx, gy]
	var username = _get_username(peer_id)
	var guard = active_guards.get(pos_key, {})

	if guard.is_empty():
		# No guard hired — show hire option
		send_to_peer(peer_id, {
			"type": "guard_post_interact",
			"guard_x": gx, "guard_y": gy,
			"has_guard": false,
			"hire_valor_cost": GUARD_HIRE_VALOR_COST,
			"hire_food_cost": GUARD_HIRE_FOOD_COST,
		})
	else:
		# Guard exists — show status
		var is_owner = guard.get("owner", "") == username
		var now = Time.get_unix_time_from_system()
		var days_remaining = guard.get("food_remaining", 0) - (now - guard.get("last_fed", now)) / 86400.0
		days_remaining = max(0.0, days_remaining)
		send_to_peer(peer_id, {
			"type": "guard_post_interact",
			"guard_x": gx, "guard_y": gy,
			"has_guard": true,
			"is_owner": is_owner,
			"owner": guard.get("owner", ""),
			"days_remaining": snapped(days_remaining, 0.1),
			"radius": guard.get("radius", GUARD_BASE_RADIUS),
			"in_tower": guard.get("in_tower", false),
			"feed_food_cost": GUARD_FEED_FOOD_COST,
		})

func handle_guard_hire(peer_id: int, message: Dictionary):
	"""Handle hiring a guard at a guard post."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var username = _get_username(peer_id)
	var gx = int(message.get("guard_x", 0))
	var gy = int(message.get("guard_y", 0))
	var pos_key = "%d,%d" % [gx, gy]

	# Verify guard post exists
	if not chunk_manager:
		return
	var tile = chunk_manager.get_tile(gx, gy)
	if tile.get("type", "") != "guard":
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "No guard post here!"})
		return

	# Check not already hired
	if active_guards.has(pos_key):
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "A guard is already stationed here!"})
		return

	# Check Valor (stored on account, not character)
	var account_id = peers[peer_id].get("account_id", "")
	var current_valor = persistence.get_valor(account_id) if account_id != "" else 0
	if current_valor < GUARD_HIRE_VALOR_COST:
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "Not enough Valor! Need %d, have %d." % [GUARD_HIRE_VALOR_COST, current_valor]})
		return

	# Check food materials
	var food_count = _count_guard_food(character)
	if food_count < GUARD_HIRE_FOOD_COST:
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "Not enough food! Need %d food materials, have %d.\nAccepted: fish, herbs." % [GUARD_HIRE_FOOD_COST, food_count]})
		return

	# Deduct costs
	persistence.add_valor(account_id, -GUARD_HIRE_VALOR_COST)
	_consume_guard_food(character, GUARD_HIRE_FOOD_COST)

	# Check for nearby tower
	var in_tower = _find_nearby_tower(gx, gy, 2)
	var radius = GUARD_TOWER_RADIUS if in_tower else GUARD_BASE_RADIUS

	# Hire guard
	var now = Time.get_unix_time_from_system()
	active_guards[pos_key] = {
		"owner": username,
		"hired_at": now,
		"last_fed": now,
		"food_remaining": 7,
		"in_tower": in_tower,
		"radius": radius,
	}

	_update_guard_cache()
	persistence.save_guards(active_guards)

	var tower_msg = " (Tower boosted! Radius: %d)" % radius if in_tower else " (Radius: %d)" % radius
	send_to_peer(peer_id, {"type": "guard_result", "success": true, "message": "[color=#00FF00]Guard hired!%s\nFood for 7 days.[/color]" % tower_msg})
	send_character_update(peer_id)
	send_location_update(peer_id)
	save_character(peer_id)

func handle_guard_feed(peer_id: int, message: Dictionary):
	"""Handle feeding an existing guard."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var username = _get_username(peer_id)
	var gx = int(message.get("guard_x", 0))
	var gy = int(message.get("guard_y", 0))
	var pos_key = "%d,%d" % [gx, gy]

	if not active_guards.has(pos_key):
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "No guard stationed here!"})
		return

	var guard = active_guards[pos_key]
	if guard.get("owner", "") != username:
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "This is not your guard!"})
		return

	# Check food
	var food_count = _count_guard_food(character)
	if food_count < GUARD_FEED_FOOD_COST:
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "Not enough food! Need %d food materials, have %d." % [GUARD_FEED_FOOD_COST, food_count]})
		return

	# Check cap
	var now = Time.get_unix_time_from_system()
	var days_elapsed = (now - guard.get("last_fed", now)) / 86400.0
	var current_days = guard.get("food_remaining", 0) - days_elapsed
	if current_days >= GUARD_MAX_FOOD_DAYS:
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "Guard is already fully fed! (Max %d days)" % GUARD_MAX_FOOD_DAYS})
		return

	# Consume food and extend
	_consume_guard_food(character, GUARD_FEED_FOOD_COST)
	var new_days = min(current_days + GUARD_FEED_DAYS_ADDED, float(GUARD_MAX_FOOD_DAYS))
	guard["last_fed"] = now
	guard["food_remaining"] = new_days

	persistence.save_guards(active_guards)

	send_to_peer(peer_id, {"type": "guard_result", "success": true, "message": "[color=#00FF00]Guard fed! %.1f days remaining.[/color]" % new_days})
	send_character_update(peer_id)
	save_character(peer_id)

func handle_guard_dismiss(peer_id: int, message: Dictionary):
	"""Handle dismissing a guard from a post."""
	if not characters.has(peer_id):
		return
	var username = _get_username(peer_id)
	var gx = int(message.get("guard_x", 0))
	var gy = int(message.get("guard_y", 0))
	var pos_key = "%d,%d" % [gx, gy]

	if not active_guards.has(pos_key):
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "No guard stationed here!"})
		return

	var guard = active_guards[pos_key]
	if guard.get("owner", "") != username:
		send_to_peer(peer_id, {"type": "guard_result", "success": false, "message": "This is not your guard!"})
		return

	active_guards.erase(pos_key)
	_update_guard_cache()
	persistence.save_guards(active_guards)

	send_to_peer(peer_id, {"type": "guard_result", "success": true, "message": "[color=#FFFF00]Guard dismissed.[/color]"})
	send_location_update(peer_id)

func _count_guard_food(character) -> int:
	"""Count total food materials in player crafting_materials."""
	var count = 0
	for mat_name in GUARD_FOOD_MATERIALS:
		count += int(character.crafting_materials.get(mat_name, 0))
	return count

func _consume_guard_food(character, amount: int):
	"""Consume food materials from player crafting_materials. Tries cheapest first."""
	var remaining = amount
	for mat_name in GUARD_FOOD_MATERIALS:
		if remaining <= 0:
			break
		var have = int(character.crafting_materials.get(mat_name, 0))
		if have > 0:
			var take = mini(have, remaining)
			character.crafting_materials[mat_name] = have - take
			if character.crafting_materials[mat_name] <= 0:
				character.crafting_materials.erase(mat_name)
			remaining -= take

func _find_nearby_tower(gx: int, gy: int, search_radius: int = 2) -> bool:
	"""Check if there's a tower within search_radius tiles of the given position."""
	if not chunk_manager:
		return false
	for dx in range(-search_radius, search_radius + 1):
		for dy in range(-search_radius, search_radius + 1):
			if dx == 0 and dy == 0:
				continue
			var tile = chunk_manager.get_tile(gx + dx, gy + dy)
			if tile.get("type", "") == "tower":
				return true
	return false

func _tick_guard_decay():
	"""Check all active guards for food expiry. Remove expired guards."""
	if active_guards.is_empty():
		return
	var now = Time.get_unix_time_from_system()
	var expired = []
	for pos_key in active_guards:
		var guard = active_guards[pos_key]
		var days_since_fed = (now - guard.get("last_fed", now)) / 86400.0
		if days_since_fed >= guard.get("food_remaining", 0):
			expired.append(pos_key)

	if expired.is_empty():
		return

	for pos_key in expired:
		var guard = active_guards[pos_key]
		var owner = guard.get("owner", "")
		active_guards.erase(pos_key)
		# Notify owner if online
		for pid in peers:
			if _get_username(pid) == owner:
				send_to_peer(pid, {
					"type": "text",
					"message": "[color=#FF8800]Your guard at %s has left — out of food![/color]" % pos_key
				})
				break

	_update_guard_cache()
	persistence.save_guards(active_guards)
	log_message("Guard decay: %d guards expired" % expired.size())

func _tick_wall_decay():
	"""Remove orphan walls (not part of any enclosure) after grace period."""
	if not chunk_manager:
		return
	var now = Time.get_unix_time_from_system()
	var walls_to_remove = []

	var all_tiles = persistence.player_tiles_data.get("tiles", {})
	for username_key in all_tiles:
		for td in all_tiles[username_key]:
			if td.get("type", "") != "wall":
				continue
			var wx = int(td.get("x", 0))
			var wy = int(td.get("y", 0))
			# Skip if wall is part of a valid enclosure
			if enclosure_tile_lookup.has(Vector2i(wx, wy)):
				continue
			# Also skip if this wall is adjacent to an enclosure interior tile
			# (it's a boundary wall of an enclosure)
			var is_boundary = false
			for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if enclosure_tile_lookup.has(Vector2i(wx + offset.x, wy + offset.y)):
					is_boundary = true
					break
			if is_boundary:
				continue
			# Check grace period
			var placed_at = td.get("placed_at", 0)
			if placed_at == 0:
				# Old walls without timestamp — set one now and skip
				td["placed_at"] = now
				continue
			if now - placed_at < WALL_DECAY_GRACE_PERIOD:
				continue
			walls_to_remove.append({"x": wx, "y": wy, "owner": username_key})

	# Remove up to 5 walls per tick
	var removed = 0
	for wd in walls_to_remove:
		if removed >= 5:
			break
		chunk_manager.remove_tile_modification(wd.x, wd.y)
		persistence.remove_player_tile(wd.owner, wd.x, wd.y)
		removed += 1
		# Notify owner if online
		for pid in peers:
			if _get_username(pid) == wd.owner:
				send_to_peer(pid, {
					"type": "text",
					"message": "[color=#808080]A wall at (%d, %d) has crumbled from neglect.[/color]" % [wd.x, wd.y]
				})
				break

	if removed > 0:
		chunk_manager.save_dirty_chunks()
		persistence.save_player_tiles()
		log_message("Wall decay: removed %d orphan walls" % removed)

func _update_guard_cache():
	"""Update the guard position cache in world_system for encounter suppression."""
	if not world_system:
		return
	var positions = []
	for pos_key in active_guards:
		var guard = active_guards[pos_key]
		var parts = pos_key.split(",")
		if parts.size() == 2:
			positions.append({
				"x": int(parts[0]),
				"y": int(parts[1]),
				"radius": guard.get("radius", GUARD_BASE_RADIUS),
			})
	world_system.update_guard_positions(positions)

# ===== INN & STORAGE (Player Enclosure Structures) =====

func handle_inn_rest(peer_id: int):
	"""Handle resting at player-built inn. Free full heal."""
	if not characters.has(peer_id):
		return
	if not at_player_station.has(peer_id) or not at_player_station[peer_id].get("has_inn", false):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You need to be at an Inn to rest![/color]"})
		return
	var character = characters[peer_id]
	var healed_hp = character.max_hp - character.current_hp
	var healed_mana = character.max_mana - character.current_mana
	character.current_hp = character.max_hp
	character.current_mana = character.max_mana
	character.current_stamina = character.max_stamina
	character.current_energy = character.max_energy
	save_character(peer_id)
	send_character_update(peer_id)
	var msg = "[color=#00FF00]You rest at the inn and recover fully.[/color]"
	if healed_hp > 0:
		msg += "\n[color=#88FF88]Restored %d HP, %d Mana.[/color]" % [healed_hp, healed_mana]
	else:
		msg += "\n[color=#888888]You were already at full health.[/color]"
	send_to_peer(peer_id, {"type": "inn_rest_result", "message": msg})

const STORAGE_CHEST_SLOTS = 10

func handle_storage_access(peer_id: int):
	"""Send storage chest contents to player."""
	if not characters.has(peer_id):
		return
	if not at_player_station.has(peer_id) or not at_player_station[peer_id].get("has_storage", false):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You need to be at a Storage Chest![/color]"})
		return
	var username = _get_username(peer_id)
	var storage = persistence.get_player_storage(username)
	send_to_peer(peer_id, {
		"type": "storage_contents",
		"items": storage,
		"max_slots": STORAGE_CHEST_SLOTS
	})

func handle_storage_deposit(peer_id: int, message: Dictionary):
	"""Deposit an item from inventory into storage."""
	if not characters.has(peer_id):
		return
	if not at_player_station.has(peer_id) or not at_player_station[peer_id].get("has_storage", false):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You need to be at a Storage Chest![/color]"})
		return
	var character = characters[peer_id]
	var username = _get_username(peer_id)
	var item_index = int(message.get("item_index", -1))
	if item_index < 0 or item_index >= character.inventory.size():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Invalid item![/color]"})
		return
	var storage = persistence.get_player_storage(username)
	if storage.size() >= STORAGE_CHEST_SLOTS:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Storage is full! (%d/%d)[/color]" % [storage.size(), STORAGE_CHEST_SLOTS]})
		return
	var item = character.inventory[item_index]
	character.inventory.remove_at(item_index)
	storage.append(item)
	persistence.set_player_storage(username, storage)
	save_character(peer_id)
	send_character_update(peer_id)
	send_to_peer(peer_id, {
		"type": "storage_contents",
		"items": storage,
		"max_slots": STORAGE_CHEST_SLOTS,
		"message": "[color=#00FF00]Deposited %s.[/color]" % item.get("name", "item")
	})

func handle_storage_withdraw(peer_id: int, message: Dictionary):
	"""Withdraw an item from storage into inventory."""
	if not characters.has(peer_id):
		return
	if not at_player_station.has(peer_id) or not at_player_station[peer_id].get("has_storage", false):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You need to be at a Storage Chest![/color]"})
		return
	var character = characters[peer_id]
	var username = _get_username(peer_id)
	var storage_index = int(message.get("storage_index", -1))
	var storage = persistence.get_player_storage(username)
	if storage_index < 0 or storage_index >= storage.size():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Invalid storage slot![/color]"})
		return
	if character.inventory.size() >= character.max_inventory:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Inventory is full![/color]"})
		return
	var item = storage[storage_index]
	storage.remove_at(storage_index)
	character.inventory.append(item)
	persistence.set_player_storage(username, storage)
	save_character(peer_id)
	send_character_update(peer_id)
	send_to_peer(peer_id, {
		"type": "storage_contents",
		"items": storage,
		"max_slots": STORAGE_CHEST_SLOTS,
		"message": "[color=#00FF00]Withdrew %s.[/color]" % item.get("name", "item")
	})

# ===== DUNGEON SYSTEM =====

func handle_dungeon_list(peer_id: int):
	"""Send list of available dungeons to player"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get dungeons appropriate for player level
	var available_types = DungeonDatabaseScript.get_dungeons_for_level(character.level)

	# Build dungeon list
	var dungeon_list = []
	for dungeon_type in available_types:
		var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
		var completions = character.get_dungeon_completions(dungeon_type)

		# Find active instance of this type
		var active_instance = ""
		var instance_location = Vector2i(0, 0)
		var inst_sub_tier = 1
		for inst_id in active_dungeons:
			var inst = active_dungeons[inst_id]
			if inst.dungeon_type == dungeon_type:
				active_instance = inst_id
				instance_location = Vector2i(inst.world_x, inst.world_y)
				inst_sub_tier = inst.get("sub_tier", 1)
				break

		# Use sub-tier level range if instance exists, otherwise use dungeon defaults
		var display_min = dungeon_data.min_level
		var display_max = dungeon_data.max_level
		var display_name = dungeon_data.name
		if active_instance != "":
			var sub_range = DungeonDatabaseScript.get_sub_tier_level_range(dungeon_data.tier, inst_sub_tier)
			display_min = sub_range.min_level
			display_max = sub_range.max_level
			display_name = DungeonDatabaseScript.get_dungeon_display_name(dungeon_type, dungeon_data.tier, inst_sub_tier)

		dungeon_list.append({
			"type": dungeon_type,
			"name": display_name,
			"description": dungeon_data.description,
			"tier": dungeon_data.tier,
			"sub_tier": inst_sub_tier,
			"min_level": display_min,
			"max_level": display_max,
			"floors": dungeon_data.floors,
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

func handle_hotzone_confirm(peer_id: int, message: Dictionary):
	"""Handle player confirming hotzone entry after warning."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	player_in_hotzone[peer_id] = true
	# Move player to the hotzone tile they wanted to enter
	var target_x = int(message.get("x", character.x))
	var target_y = int(message.get("y", character.y))
	character.x = target_x
	character.y = target_y
	send_location_update(peer_id)
	send_character_update(peer_id)
	# Now check for encounter at the new position
	if not character.cloak_active and world_system.check_encounter(target_x, target_y):
		trigger_encounter(peer_id)

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

	# Check level - warn but don't block if player hasn't confirmed
	var confirmed = message.get("confirmed", false)
	if character.level < dungeon_data.min_level and not confirmed:
		# Send warning and require confirmation
		var level_diff = dungeon_data.min_level - character.level
		send_to_peer(peer_id, {
			"type": "dungeon_level_warning",
			"dungeon_type": dungeon_type,
			"dungeon_name": dungeon_data.name,
			"min_level": dungeon_data.min_level,
			"player_level": character.level,
			"message": "WARNING: This dungeon is designed for level %d+ players. You are %d levels below the recommended level. Monsters here may be too powerful for you. Are you sure you want to enter?" % [dungeon_data.min_level, level_diff]
		})
		return

	# Find instance to enter - prioritize player's personal dungeon for quests
	var instance_id = ""

	# First check if provided instance_id is valid
	if provided_instance_id != "" and active_dungeons.has(provided_instance_id):
		var inst = active_dungeons[provided_instance_id]
		if inst.has("owner_peer_id") and inst.owner_peer_id != peer_id:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF6666]This dungeon belongs to another player. You cannot enter it.[/color]"})
			return
		instance_id = provided_instance_id
	else:
		# Check if player has a personal dungeon instance for an active quest
		if player_dungeon_instances.has(peer_id):
			for quest_id in player_dungeon_instances[peer_id]:
				var inst_id = player_dungeon_instances[peer_id][quest_id]
				if active_dungeons.has(inst_id):
					var inst = active_dungeons[inst_id]
					# Match by dungeon_type or accept any if dungeon_type is empty
					if dungeon_type == "" or inst.dungeon_type == dungeon_type:
						instance_id = inst_id
						dungeon_type = inst.dungeon_type  # Update type if was empty
						break

	# If no personal dungeon found, create a new personal instance
	if instance_id == "":
		# Players always get their own dungeon instance now
		instance_id = _create_player_dungeon_instance(peer_id, "", dungeon_type, character.level)
		if instance_id == "":
			send_to_peer(peer_id, {"type": "error", "message": "Failed to create dungeon instance!"})
			return
		# Track this as a non-quest dungeon run
		if not player_dungeon_instances.has(peer_id):
			player_dungeon_instances[peer_id] = {}
		player_dungeon_instances[peer_id]["_free_run_" + instance_id] = instance_id

	var instance = active_dungeons[instance_id]

	# Get starting position (entrance tile)
	var floor_grid = dungeon_floors[instance_id][0]
	var start_pos = _find_tile_position(floor_grid, DungeonDatabaseScript.TileType.ENTRANCE)

	# Safety: ensure start is on a walkable tile
	if start_pos.y < floor_grid.size() and start_pos.x < floor_grid[0].size():
		if floor_grid[start_pos.y][start_pos.x] == DungeonDatabaseScript.TileType.WALL:
			start_pos = _find_any_walkable_tile(floor_grid)

	# Enter dungeon — if party leader, bring all party members
	if _is_party_leader(peer_id):
		var party = active_parties[peer_id]
		var party_members = party.members.duplicate()
		# Validate all members can enter
		for pid in party_members:
			if not characters.has(pid):
				continue
			if characters[pid].in_dungeon:
				send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]%s is already in a dungeon![/color]" % characters[pid].name})
				return
			if combat_mgr.is_in_combat(pid):
				send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]%s is in combat![/color]" % characters[pid].name})
				return
		# Enter leader at start position
		character.enter_dungeon(instance_id, dungeon_type, start_pos.x, start_pos.y)
		if not instance.active_players.has(peer_id):
			instance.active_players.append(peer_id)
		_send_dungeon_state(peer_id)
		save_character(peer_id)
		# Enter followers at nearby positions
		for i in range(1, party_members.size()):
			var pid = party_members[i]
			if not characters.has(pid):
				continue
			# Place followers offset from leader (or at same position if no room)
			var follower_x = start_pos.x
			var follower_y = start_pos.y + i  # Below leader
			# Bounds check
			if follower_y >= floor_grid.size() or floor_grid[follower_y][follower_x] == DungeonDatabaseScript.TileType.WALL:
				follower_x = start_pos.x
				follower_y = start_pos.y  # Fallback: same position
			characters[pid].enter_dungeon(instance_id, dungeon_type, follower_x, follower_y)
			if not instance.active_players.has(pid):
				instance.active_players.append(pid)
			_send_dungeon_state(pid)
			save_character(pid)
		log_message("Party led by %s entered dungeon %s" % [character.name, dungeon_data.name])
	else:
		# Solo entry
		character.enter_dungeon(instance_id, dungeon_type, start_pos.x, start_pos.y)
		if not instance.active_players.has(peer_id):
			instance.active_players.append(peer_id)
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

	# Party followers can't move independently in dungeons
	if party_membership.has(peer_id) and not _is_party_leader(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Your party leader controls movement.[/color]"})
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
	var old_x = character.dungeon_x
	var old_y = character.dungeon_y
	character.dungeon_x = new_x
	character.dungeon_y = new_y

	# Move party followers in snake formation (dungeon)
	if _is_party_leader(peer_id):
		_move_party_followers_dungeon(peer_id, old_x, old_y)

	# Regenerate health and resources on dungeon movement (reduced rate vs overworld)
	var early_game_mult = _get_early_game_regen_multiplier(character.level)
	var house_regen_mult = 1.0 + (character.house_bonuses.get("resource_regen", 0) / 100.0)
	var dungeon_regen_percent = 0.01 * early_game_mult * house_regen_mult  # 1% per move for resources (half of overworld)
	var dungeon_hp_regen_percent = 0.005 * early_game_mult * house_regen_mult  # 0.5% per move for health (half of overworld)
	var total_max_hp = character.get_total_max_hp()
	var total_max_mana = character.get_total_max_mana()
	var total_max_stamina = character.get_total_max_stamina()
	var total_max_energy = character.get_total_max_energy()
	character.current_hp = min(total_max_hp, character.current_hp + max(1, int(total_max_hp * dungeon_hp_regen_percent)))
	if not character.cloak_active:
		character.current_mana = min(total_max_mana, character.current_mana + max(1, int(total_max_mana * dungeon_regen_percent)))
		character.current_stamina = min(total_max_stamina, character.current_stamina + max(1, int(total_max_stamina * dungeon_regen_percent)))
		character.current_energy = min(total_max_energy, character.current_energy + max(1, int(total_max_energy * dungeon_regen_percent)))

	# Process egg incubation - dungeon steps also count toward hatching
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
				"message": "[color=#00FF00]%s is now your companion![/color] Visit [color=#00FFFF]More → Companions[/color] to manage." % companion.name
			})

	# Tick poison on dungeon movement
	if character.poison_active:
		var poison_dmg = character.tick_poison()
		if poison_dmg != 0:
			var turns_left = character.poison_turns_remaining
			var poison_msg = ""
			if poison_dmg < 0:
				var heal_amount = -poison_dmg
				character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount)
				poison_msg = "[color=#708090]Your undead form absorbs the poison, healing [color=#00FF00]%d HP[/color][/color]" % heal_amount
			else:
				character.current_hp -= poison_dmg
				character.current_hp = max(1, character.current_hp)
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

	# Tick blind on dungeon movement
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

	# Tick active buffs on dungeon movement
	if not character.active_buffs.is_empty():
		var expired = character.tick_buffs()
		for buff in expired:
			send_to_peer(peer_id, {
				"type": "status_effect",
				"effect": "buff_expired",
				"message": "[color=#808080]%s buff has worn off.[/color]" % buff.type
			})

	# Check tile interaction FIRST (treasure, exit)
	var tile_int = int(tile)
	if tile_int == int(DungeonDatabaseScript.TileType.TREASURE):
		_open_dungeon_treasure(peer_id)
		return
	elif tile_int == int(DungeonDatabaseScript.TileType.EXIT):
		_advance_dungeon_floor(peer_id)
		return

	# Check if player walked onto a rescue NPC
	var rescue_npc = _get_dungeon_npc_at(instance_id, character.dungeon_floor, new_x, new_y)
	if not rescue_npc.is_empty() and not rescue_npc.get("rescued", false):
		_trigger_rescue_encounter(peer_id, rescue_npc, instance_id)
		return

	# Check if player walked onto a monster entity
	var stepped_monster = _get_monster_at_position(instance_id, character.dungeon_floor, new_x, new_y)
	if stepped_monster != null:
		_start_dungeon_monster_combat(peer_id, stepped_monster)
		return

	# Move all monsters (they react to player movement)
	# Skip monster movement if player just finished combat (breather turn)
	if dungeon_combat_breather.has(peer_id):
		dungeon_combat_breather.erase(peer_id)
	else:
		var monster_combat = _move_dungeon_monsters(peer_id)
		if monster_combat:
			return  # Combat was triggered by a monster reaching the player

	# Legacy tile-based encounters (backward compat for old dungeon instances)
	if tile_int == int(DungeonDatabaseScript.TileType.ENCOUNTER):
		_start_dungeon_encounter(peer_id, false)
		return
	elif tile_int == int(DungeonDatabaseScript.TileType.BOSS):
		_start_dungeon_encounter(peer_id, true)
		return

	# Send updated dungeon state
	_send_dungeon_state(peer_id)

func handle_dungeon_exit(peer_id: int):
	"""Handle player exiting dungeon"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	if not character.in_dungeon:
		send_to_peer(peer_id, {"type": "error", "message": "You are not in a dungeon!"})
		return

	# Cannot exit during combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot exit while in combat!"})
		return

	# Party followers can't exit independently
	if party_membership.has(peer_id) and not _is_party_leader(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Your party leader controls dungeon navigation.[/color]"})
		return

	# Must be on entrance tile to exit
	var instance_id_check = character.current_dungeon_id
	if dungeon_floors.has(instance_id_check):
		var floor_grids = dungeon_floors[instance_id_check]
		var grid = floor_grids[character.dungeon_floor]
		if grid[character.dungeon_y][character.dungeon_x] != int(DungeonDatabaseScript.TileType.ENTRANCE):
			send_to_peer(peer_id, {"type": "error", "message": "You must return to the dungeon entrance (E) to exit."})
			return

	# Clear any pending flock encounters
	if pending_flocks.has(peer_id):
		pending_flocks.erase(peer_id)
	if pending_flock_drops.has(peer_id):
		pending_flock_drops.erase(peer_id)
	if pending_flock_gems.has(peer_id):
		pending_flock_gems.erase(peer_id)
	if flock_counts.has(peer_id):
		flock_counts.erase(peer_id)

	# Remove from dungeon
	var instance_id = character.current_dungeon_id
	if active_dungeons.has(instance_id):
		var instance = active_dungeons[instance_id]
		instance.active_players.erase(peer_id)

	# Clean up free-run (non-quest) dungeons when exiting
	# Quest dungeons are kept so player can return
	if player_dungeon_instances.has(peer_id):
		var free_run_key = "_free_run_" + instance_id
		if player_dungeon_instances[peer_id].has(free_run_key):
			player_dungeon_instances[peer_id].erase(free_run_key)
			# Clean up the instance itself
			if active_dungeons.has(instance_id):
				active_dungeons.erase(instance_id)
			if dungeon_floors.has(instance_id):
				dungeon_floors.erase(instance_id)
			if dungeon_floor_rooms.has(instance_id):
				dungeon_floor_rooms.erase(instance_id)
			if dungeon_monsters.has(instance_id):
				dungeon_monsters.erase(instance_id)

	# Exit dungeon — including party members
	character.exit_dungeon()

	send_to_peer(peer_id, {
		"type": "dungeon_exit",
		"message": "[color=#FFD700]You leave the dungeon.[/color]"
	})

	send_location_update(peer_id)
	send_character_update(peer_id)
	save_character(peer_id)

	# Exit party followers from dungeon too
	if _is_party_leader(peer_id):
		var party = active_parties[peer_id]
		for i in range(1, party.members.size()):
			var pid = party.members[i]
			if not characters.has(pid) or not characters[pid].in_dungeon:
				continue
			# Remove from dungeon active players
			if active_dungeons.has(instance_id):
				active_dungeons[instance_id].active_players.erase(pid)
			characters[pid].exit_dungeon()
			send_to_peer(pid, {
				"type": "dungeon_exit",
				"message": "[color=#FFD700]Your party leaves the dungeon.[/color]"
			})
			# Place follower near leader
			characters[pid].x = character.x
			characters[pid].y = character.y
			send_location_update(pid)
			send_character_update(pid)
			save_character(pid)

func handle_dungeon_go_back(peer_id: int):
	"""Handle player going back to previous dungeon floor"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	if not character.in_dungeon:
		send_to_peer(peer_id, {"type": "error", "message": "You are not in a dungeon!"})
		return

	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot go back while in combat!"})
		return

	# Party followers can't navigate independently
	if party_membership.has(peer_id) and not _is_party_leader(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Your party leader controls dungeon navigation.[/color]"})
		return

	if character.dungeon_floor <= 0:
		send_to_peer(peer_id, {"type": "error", "message": "You are already on the first floor!"})
		return

	# Must be on entrance tile to go back
	var instance_id = character.current_dungeon_id
	if dungeon_floors.has(instance_id):
		var floor_grids = dungeon_floors[instance_id]
		var grid = floor_grids[character.dungeon_floor]
		if grid[character.dungeon_y][character.dungeon_x] != int(DungeonDatabaseScript.TileType.ENTRANCE):
			send_to_peer(peer_id, {"type": "error", "message": "You must be at the entrance (E) to go back a floor."})
			return

		# Go back one floor and place player at the EXIT tile of the previous floor
		var prev_floor = character.dungeon_floor - 1
		var prev_grid = floor_grids[prev_floor]
		var exit_pos = _find_tile_position(prev_grid, DungeonDatabaseScript.TileType.EXIT)

		character.dungeon_floor = prev_floor
		character.dungeon_x = exit_pos.x
		character.dungeon_y = exit_pos.y

		send_to_peer(peer_id, {
			"type": "dungeon_floor_change",
			"floor": character.dungeon_floor + 1,
			"total_floors": DungeonDatabaseScript.get_dungeon(character.current_dungeon_type).floors,
			"message": "[color=#FFFF00]You ascend back to floor %d...[/color]" % (character.dungeon_floor + 1)
		})

		_send_dungeon_state(peer_id)
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

	# Get spawn location - avoid trading posts
	var spawn_x = 0
	var spawn_y = 0
	var max_attempts = 20

	for _attempt in range(max_attempts):
		var spawn_loc = DungeonDatabaseScript.get_spawn_location_for_tier(dungeon_data.tier)
		spawn_x = spawn_loc.x
		spawn_y = spawn_loc.y
		if not trading_post_db.is_trading_post_tile(spawn_x, spawn_y) and not world_system.is_safe_zone(spawn_x, spawn_y):
			break

	# Calculate sub-tier based on distance from origin
	var distance = sqrt(float(spawn_x * spawn_x + spawn_y * spawn_y))
	var sub_tier = DungeonDatabaseScript.get_sub_tier_for_distance(dungeon_data.tier, distance)
	var sub_range = DungeonDatabaseScript.get_sub_tier_level_range(dungeon_data.tier, sub_tier)
	var dungeon_level = sub_range.min_level + randi() % maxi(1, sub_range.max_level - sub_range.min_level + 1)

	# Create instance
	active_dungeons[instance_id] = {
		"instance_id": instance_id,
		"dungeon_type": dungeon_type,
		"world_x": spawn_x,
		"world_y": spawn_y,
		"spawned_at": int(Time.get_unix_time_from_system()),
		"active_players": [],
		"dungeon_level": dungeon_level,
		"sub_tier": sub_tier
	}

	# Generate all floor grids (BSP rooms + corridors)
	var floor_grids = []
	var floor_rooms = []
	for floor_num in range(dungeon_data.floors):
		var is_boss_floor = floor_num == dungeon_data.floors - 1
		var floor_data = DungeonDatabaseScript.generate_floor_grid(dungeon_type, floor_num, is_boss_floor)
		floor_grids.append(floor_data.grid)
		floor_rooms.append(floor_data.rooms)

	dungeon_floors[instance_id] = floor_grids
	dungeon_floor_rooms[instance_id] = floor_rooms

	# Spawn monsters on all floors
	_spawn_all_dungeon_monsters(instance_id, dungeon_type, dungeon_level)

	log_message("Created dungeon instance: %s (%s) [T%d-%d]" % [instance_id, dungeon_data.name, dungeon_data.tier, sub_tier])
	return instance_id

func _create_player_dungeon_instance(peer_id: int, quest_id: String, dungeon_type: String, player_level: int) -> String:
	"""Create a personal dungeon instance for a player's quest. Returns instance ID."""
	if active_dungeons.size() >= MAX_ACTIVE_DUNGEONS:
		log_message("Cannot create player dungeon - max dungeons reached")
		return ""

	# If dungeon_type is empty (any dungeon), pick an appropriate one based on player level
	if dungeon_type == "":
		var available = DungeonDatabaseScript.get_dungeons_for_level(player_level)
		if available.is_empty():
			# Default to goblin_caves for low level
			dungeon_type = "goblin_caves"
		else:
			dungeon_type = available[randi() % available.size()]

	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	if dungeon_data.is_empty():
		log_message("Cannot create player dungeon - invalid dungeon type: %s" % dungeon_type)
		return ""

	var instance_id = "player_dungeon_%d_%d" % [peer_id, next_dungeon_id]
	next_dungeon_id += 1

	# Get character for spawn location calculation - avoid trading posts
	var character = characters.get(peer_id)
	var spawn_x = 0
	var spawn_y = 0
	var max_attempts = 20

	for _attempt in range(max_attempts):
		if character:
			# Spawn dungeon 25-40 tiles from the player's current location
			var distance = 25 + randi() % 16  # 25-40 tiles
			var angle = randf() * TAU  # Random direction
			spawn_x = int(character.x + cos(angle) * distance)
			spawn_y = int(character.y + sin(angle) * distance)
		else:
			# Fallback to standard spawn location
			var spawn_loc = DungeonDatabaseScript.get_spawn_location_for_tier(dungeon_data.tier)
			spawn_x = spawn_loc.x
			spawn_y = spawn_loc.y

		# Check if location is valid (not on a trading post or NPC post)
		if not trading_post_db.is_trading_post_tile(spawn_x, spawn_y) and not world_system.is_safe_zone(spawn_x, spawn_y):
			break

	# Calculate sub-tier based on distance from origin
	var distance = sqrt(float(spawn_x * spawn_x + spawn_y * spawn_y))
	var sub_tier = DungeonDatabaseScript.get_sub_tier_for_distance(dungeon_data.tier, distance)
	var sub_range = DungeonDatabaseScript.get_sub_tier_level_range(dungeon_data.tier, sub_tier)

	# Scale dungeon level to player, clamped to sub-tier range
	var dungeon_level = clampi(player_level, sub_range.min_level, sub_range.max_level)

	# Create instance
	active_dungeons[instance_id] = {
		"instance_id": instance_id,
		"dungeon_type": dungeon_type,
		"world_x": spawn_x,
		"world_y": spawn_y,
		"spawned_at": int(Time.get_unix_time_from_system()),
		"active_players": [],
		"dungeon_level": dungeon_level,
		"sub_tier": sub_tier,
		"owner_peer_id": peer_id,  # Track who owns this instance
		"owner_username": peers.get(peer_id, {}).get("username", ""),  # For reconnect lookup
		"quest_id": quest_id  # Track which quest this is for
	}

	# Generate all floor grids (BSP rooms + corridors)
	var floor_grids = []
	var floor_rooms = []
	for floor_num in range(dungeon_data.floors):
		var is_boss_floor = floor_num == dungeon_data.floors - 1
		var floor_data = DungeonDatabaseScript.generate_floor_grid(dungeon_type, floor_num, is_boss_floor)
		floor_grids.append(floor_data.grid)
		floor_rooms.append(floor_data.rooms)

	dungeon_floors[instance_id] = floor_grids
	dungeon_floor_rooms[instance_id] = floor_rooms

	# Spawn monsters on all floors
	_spawn_all_dungeon_monsters(instance_id, dungeon_type, dungeon_level)

	log_message("Created player dungeon instance: %s (%s) for peer %d at (%d, %d)" % [instance_id, dungeon_data.name, peer_id, spawn_x, spawn_y])
	return instance_id

func _cleanup_player_dungeon(peer_id: int, quest_id: String):
	"""Clean up a player's personal dungeon instance when quest is completed/abandoned"""
	if not player_dungeon_instances.has(peer_id):
		return

	if not player_dungeon_instances[peer_id].has(quest_id):
		return

	var instance_id = player_dungeon_instances[peer_id][quest_id]

	# Remove from active dungeons
	if active_dungeons.has(instance_id):
		active_dungeons.erase(instance_id)
	if dungeon_floors.has(instance_id):
		dungeon_floors.erase(instance_id)
	if dungeon_floor_rooms.has(instance_id):
		dungeon_floor_rooms.erase(instance_id)
	if dungeon_monsters.has(instance_id):
		dungeon_monsters.erase(instance_id)

	# Remove from player's tracking
	player_dungeon_instances[peer_id].erase(quest_id)
	if player_dungeon_instances[peer_id].is_empty():
		player_dungeon_instances.erase(peer_id)

	log_message("Cleaned up player dungeon %s for peer %d quest %s" % [instance_id, peer_id, quest_id])

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

	# Starter dungeons always get sub-tier 1 (easiest)
	var sub_range = DungeonDatabaseScript.get_sub_tier_level_range(dungeon_data.tier, 1)
	var dungeon_level = sub_range.min_level + randi() % maxi(1, sub_range.max_level - sub_range.min_level + 1)

	# Create instance
	active_dungeons[instance_id] = {
		"instance_id": instance_id,
		"dungeon_type": dungeon_type,
		"world_x": spawn_x,
		"world_y": spawn_y,
		"spawned_at": int(Time.get_unix_time_from_system()),
		"active_players": [],
		"dungeon_level": dungeon_level,
		"sub_tier": 1
	}

	# Generate all floor grids (BSP rooms + corridors)
	var floor_grids = []
	var floor_rooms = []
	for floor_num in range(dungeon_data.floors):
		var is_boss_floor = floor_num == dungeon_data.floors - 1
		var floor_data = DungeonDatabaseScript.generate_floor_grid(dungeon_type, floor_num, is_boss_floor)
		floor_grids.append(floor_data.grid)
		floor_rooms.append(floor_data.rooms)

	dungeon_floors[instance_id] = floor_grids
	dungeon_floor_rooms[instance_id] = floor_rooms

	# Spawn monsters on all floors
	_spawn_all_dungeon_monsters(instance_id, dungeon_type, dungeon_level)

	log_message("Spawned starter dungeon: %s (%s) [T%d-1] at (%d, %d)" % [instance_id, dungeon_data.name, dungeon_data.tier, spawn_x, spawn_y])

func _check_dungeon_spawns():
	"""Periodically check and spawn new world dungeons, despawn completed ones"""
	var current_time = int(Time.get_unix_time_from_system())
	var dungeons_to_remove = []

	# Count world dungeons (excluding player quest dungeons)
	var world_dungeon_count = 0
	for instance_id in active_dungeons:
		var instance = active_dungeons[instance_id]
		# Skip player-owned dungeons (quest dungeons)
		if instance.get("owner_peer_id", -1) >= 0:
			continue
		world_dungeon_count += 1

		# Check if dungeon is completed and should despawn
		var completed_at = instance.get("completed_at", 0)
		if completed_at > 0 and instance.active_players.is_empty():
			if current_time - completed_at >= DUNGEON_DESPAWN_DELAY:
				dungeons_to_remove.append(instance_id)
				log_message("Despawning completed dungeon: %s" % instance_id)

		# Also check for very old dungeons (24+ hours) with no players
		var age = current_time - instance.spawned_at
		if age > 86400 and instance.active_players.is_empty():  # 24 hours
			dungeons_to_remove.append(instance_id)
			log_message("Despawning old dungeon: %s (age: %d hours)" % [instance_id, age / 3600])

	# Remove dungeons marked for removal
	for instance_id in dungeons_to_remove:
		active_dungeons.erase(instance_id)
		dungeon_floors.erase(instance_id)
		dungeon_floor_rooms.erase(instance_id)
		dungeon_monsters.erase(instance_id)
		world_dungeon_count -= 1

	# Spawn new world dungeons if below minimum
	var dungeon_types = DungeonDatabaseScript.DUNGEON_TYPES.keys()
	while world_dungeon_count < MIN_WORLD_DUNGEONS and active_dungeons.size() < MAX_ACTIVE_DUNGEONS:
		# Pick a random dungeon type
		var dungeon_type = dungeon_types[randi() % dungeon_types.size()]
		var instance_id = _create_world_dungeon(dungeon_type)
		if instance_id != "":
			world_dungeon_count += 1
			log_message("Spawned new world dungeon: %s" % instance_id)
		else:
			break  # Failed to create, stop trying

	# Spawn extra dungeons up to max (spawn multiple per check to fill up faster)
	while world_dungeon_count < MAX_WORLD_DUNGEONS and active_dungeons.size() < MAX_ACTIVE_DUNGEONS:
		if randf() < 0.5:  # 50% chance per dungeon
			var dungeon_type = dungeon_types[randi() % dungeon_types.size()]
			var instance_id = _create_world_dungeon(dungeon_type)
			if instance_id != "":
				world_dungeon_count += 1
				log_message("Spawned bonus world dungeon: %s" % instance_id)
			else:
				break
		else:
			break  # Stop if random check fails

func _create_world_dungeon(dungeon_type: String) -> String:
	"""Create a random world dungeon at a random location"""
	if active_dungeons.size() >= MAX_ACTIVE_DUNGEONS:
		return ""

	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	if dungeon_data.is_empty():
		return ""

	var instance_id = "world_dungeon_%d" % next_dungeon_id
	next_dungeon_id += 1

	# Get spawn location based on tier - higher tiers spawn further from origin
	var spawn_loc = DungeonDatabaseScript.get_spawn_location_for_tier(dungeon_data.tier)

	# Try to find a valid spawn location (not on a trading post)
	var world_x = 0
	var world_y = 0
	var max_attempts = 20
	var found_valid = false

	for _attempt in range(max_attempts):
		# Add more randomness to position (within 100 tiles of tier's base location)
		# This creates a wider spread of dungeons across the map
		var offset_x = (randi() % 201) - 100
		var offset_y = (randi() % 201) - 100
		world_x = spawn_loc.x + offset_x
		world_y = spawn_loc.y + offset_y

		# Check if this location overlaps with a trading post or NPC post
		if not trading_post_db.is_trading_post_tile(world_x, world_y) and not world_system.is_safe_zone(world_x, world_y):
			found_valid = true
			break

	if not found_valid:
		# Couldn't find a valid location after max attempts, skip this dungeon
		next_dungeon_id -= 1  # Reclaim the ID
		return ""

	# Calculate sub-tier based on distance from origin
	var distance = sqrt(float(world_x * world_x + world_y * world_y))
	var sub_tier = DungeonDatabaseScript.get_sub_tier_for_distance(dungeon_data.tier, distance)
	var sub_range = DungeonDatabaseScript.get_sub_tier_level_range(dungeon_data.tier, sub_tier)
	var dungeon_level = sub_range.min_level + randi() % maxi(1, sub_range.max_level - sub_range.min_level + 1)

	# Create instance
	active_dungeons[instance_id] = {
		"instance_id": instance_id,
		"dungeon_type": dungeon_type,
		"world_x": world_x,
		"world_y": world_y,
		"spawned_at": int(Time.get_unix_time_from_system()),
		"active_players": [],
		"dungeon_level": dungeon_level,
		"sub_tier": sub_tier,
		"completed_at": 0  # 0 means not completed yet
	}

	# Generate all floor grids (BSP rooms + corridors)
	var floor_grids = []
	var floor_rooms = []
	for floor_num in range(dungeon_data.floors):
		var is_boss_floor = floor_num == dungeon_data.floors - 1
		var floor_data = DungeonDatabaseScript.generate_floor_grid(dungeon_type, floor_num, is_boss_floor)
		floor_grids.append(floor_data.grid)
		floor_rooms.append(floor_data.rooms)

	dungeon_floors[instance_id] = floor_grids
	dungeon_floor_rooms[instance_id] = floor_rooms

	# Spawn monsters on all floors
	_spawn_all_dungeon_monsters(instance_id, dungeon_type, dungeon_level)

	return instance_id

func _get_dungeon_at_location(x: int, y: int, peer_id: int = -1) -> Dictionary:
	"""Check if there's a dungeon entrance at the given coordinates.
	Excludes completed dungeons and other players' personal quest dungeons."""
	for instance_id in active_dungeons:
		var instance = active_dungeons[instance_id]
		# Skip completed dungeons - they're waiting to despawn
		if instance.get("completed_at", 0) > 0:
			continue
		# Skip other players' personal quest dungeons
		if peer_id >= 0 and instance.has("owner_peer_id") and instance.owner_peer_id != peer_id:
			continue
		if instance.world_x == x and instance.world_y == y:
			var dungeon_data = DungeonDatabaseScript.get_dungeon(instance.dungeon_type)
			var inst_sub_tier = instance.get("sub_tier", 1)
			var sub_range = DungeonDatabaseScript.get_sub_tier_level_range(dungeon_data.tier, inst_sub_tier)
			return {
				"instance_id": instance_id,
				"dungeon_type": instance.dungeon_type,
				"name": DungeonDatabaseScript.get_dungeon_display_name(instance.dungeon_type, dungeon_data.tier, inst_sub_tier),
				"tier": dungeon_data.tier,
				"sub_tier": inst_sub_tier,
				"min_level": sub_range.min_level,
				"max_level": sub_range.max_level,
				"color": dungeon_data.color
			}
	return {}

func get_visible_dungeons(center_x: int, center_y: int, radius: int) -> Array:
	"""Get all dungeon entrances visible within the given radius.
	Excludes completed dungeons (waiting to despawn)."""
	var visible = []
	for instance_id in active_dungeons:
		var instance = active_dungeons[instance_id]
		# Skip completed dungeons - they're waiting to despawn
		if instance.get("completed_at", 0) > 0:
			continue
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

func _add_dungeon_directions_to_quests(quests: Array, _tp_x: int, _tp_y: int) -> Array:
	"""Add info to dungeon quests about personal dungeon creation"""
	var updated_quests = []
	for quest in quests:
		var updated_quest = quest.duplicate()

		# Check if this is a dungeon quest
		if quest.get("type") == quest_db.QuestType.DUNGEON_CLEAR:
			# Add note about personal dungeon being created
			var dungeon_hint = "\n\n[color=#00FFFF]A personal dungeon will be created for you nearby when you accept this quest.[/color]"
			updated_quest["description"] = quest.get("description", "") + dungeon_hint

		updated_quests.append(updated_quest)

	return updated_quests

func _get_player_dungeon_info(peer_id: int, quest_id: String, from_x: int, from_y: int) -> Dictionary:
	"""Get info about a player's personal dungeon for a quest. Returns {x, y, direction_text, dungeon_name} or empty."""
	# Check if player has a personal dungeon for this quest
	if not player_dungeon_instances.has(peer_id):
		return {}
	if not player_dungeon_instances[peer_id].has(quest_id):
		return {}

	var instance_id = player_dungeon_instances[peer_id][quest_id]
	if not active_dungeons.has(instance_id):
		return {}

	var instance = active_dungeons[instance_id]
	var dungeon_data = DungeonDatabaseScript.get_dungeon(instance.dungeon_type)

	return {
		"x": instance.world_x,
		"y": instance.world_y,
		"direction_text": _get_direction_text(from_x, from_y, instance.world_x, instance.world_y),
		"dungeon_name": dungeon_data.name,
		"dungeon_type": instance.dungeon_type,
		"instance_id": instance_id
	}

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

	# Find entrance position on current floor
	var entrance_pos = _find_tile_position(grid, DungeonDatabaseScript.TileType.ENTRANCE)

	# Get alive monsters on current floor
	var monster_list = []
	if dungeon_monsters.has(instance_id):
		var floor_monsters = dungeon_monsters[instance_id].get(character.dungeon_floor, [])
		for m in floor_monsters:
			if m.alive:
				monster_list.append({
					"id": m.id, "x": m.x, "y": m.y,
					"char": m.display_char, "color": m.display_color,
					"alert": m.alert, "is_boss": m.is_boss,
					"type": m.monster_type
				})

	# Get rescue NPCs on current floor
	var npc_list = []
	if dungeon_npcs.has(instance_id):
		var floor_npc = dungeon_npcs[instance_id].get(character.dungeon_floor, {})
		if not floor_npc.is_empty() and not floor_npc.get("rescued", false):
			npc_list.append({
				"x": floor_npc.x, "y": floor_npc.y,
				"char": floor_npc.get("display_char", "?"),
				"color": floor_npc.get("display_color", "#00FF00"),
				"npc_type": floor_npc.get("npc_type", "merchant")
			})

	var inst_sub_tier = instance.get("sub_tier", 1)
	var display_name = DungeonDatabaseScript.get_dungeon_display_name(character.current_dungeon_type, dungeon_data.tier, inst_sub_tier)

	send_to_peer(peer_id, {
		"type": "dungeon_state",
		"dungeon_type": character.current_dungeon_type,
		"dungeon_name": display_name,
		"sub_tier": inst_sub_tier,
		"floor": character.dungeon_floor + 1,
		"total_floors": dungeon_data.floors,
		"grid": grid,
		"player_x": character.dungeon_x,
		"player_y": character.dungeon_y,
		"current_tile": current_tile,
		"entrance_x": entrance_pos.x,
		"entrance_y": entrance_pos.y,
		"encounters_cleared": character.dungeon_encounters_cleared,
		"color": dungeon_data.color,
		"monsters": monster_list,
		"npcs": npc_list
	})

func _find_tile_position(grid: Array, tile_type: int) -> Vector2i:
	"""Find position of a tile type in grid"""
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == tile_type:
				return Vector2i(x, y)
	return Vector2i(1, grid.size() - 2)  # Default to bottom-left interior

func _find_any_walkable_tile(grid: Array) -> Vector2i:
	"""Find any non-wall tile in the grid (fallback for bad entrance placement)"""
	for y in range(1, grid.size() - 1):
		for x in range(1, grid[y].size() - 1):
			if grid[y][x] != DungeonDatabaseScript.TileType.WALL:
				return Vector2i(x, y)
	return Vector2i(grid.size() / 2, grid.size() / 2)

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

	# Create combat - use monster_type for boss, name for regular encounters
	var monster_lookup_name = monster_info.get("monster_type", monster_info.name) if is_boss else monster_info.name
	var monster = monster_db.generate_monster_by_name(monster_lookup_name, monster_info.level)
	if monster.is_empty():
		# Fallback: generate a generic monster for the level
		monster = monster_db.generate_monster(monster_info.level, monster_info.level)
	monster.is_dungeon_monster = true

	# Apply boss multipliers and rename to boss display name
	if is_boss:
		monster.max_hp = int(monster.max_hp * monster_info.get("hp_mult", 2.0))
		monster.current_hp = monster.max_hp
		monster.strength = int(monster.strength * monster_info.get("attack_mult", 1.5))
		monster.is_boss = true
		# Use boss display name (e.g., "Orc Warlord" instead of just "Orc")
		monster.name = monster_info.name

	# Party dungeon combat?
	if _is_party_leader(peer_id):
		_start_party_combat_encounter(peer_id, monster, [])
		return

	# Start combat
	var result = combat_mgr.start_combat(peer_id, character, monster)

	# Mark internal combat state for dungeon-specific handling
	var internal_state = combat_mgr.get_active_combat(peer_id)
	internal_state["is_dungeon_combat"] = true
	internal_state["is_boss_fight"] = is_boss

	# Get display-ready combat state (flattened with monster_name, etc.)
	var display_state = combat_mgr.get_combat_display(peer_id)
	display_state["is_dungeon_combat"] = true
	display_state["is_boss_fight"] = is_boss

	# Build encounter message
	var boss_text = " [BOSS]" if is_boss else ""
	var encounter_msg = "[color=#FF4444]A %s%s appears![/color]" % [monster.name, boss_text]

	send_to_peer(peer_id, {
		"type": "combat_start",
		"message": encounter_msg,
		"combat_state": display_state,
		"is_dungeon_combat": true,
		"is_boss": is_boss,
		"use_client_art": true,  # Client renders ASCII art locally
		"extra_combat_text": result.get("extra_combat_text", "")
	})

func _open_dungeon_treasure(peer_id: int):
	"""Open a treasure chest in dungeon"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var instance_id = character.current_dungeon_id
	var inst_sub_tier = 1
	if active_dungeons.has(instance_id):
		inst_sub_tier = active_dungeons[instance_id].get("sub_tier", 1)

	# Get treasure (sub-tier scales gold)
	var treasure = DungeonDatabaseScript.roll_treasure(character.current_dungeon_type, character.dungeon_floor, inst_sub_tier)

	# Give rewards
	var reward_messages = []

	# Materials
	for mat in treasure.get("materials", []):
		character.add_crafting_material(mat.id, mat.quantity)
		var qty_text = " x%d" % mat.quantity if mat.quantity > 1 else ""
		reward_messages.append("[color=#1EFF00]+%s%s[/color]" % [mat.id.capitalize().replace("_", " "), qty_text])

	# Egg (inherits dungeon sub-tier)
	var egg_info = treasure.get("egg", {})
	if not egg_info.is_empty():
		var egg_sub_tier = egg_info.get("sub_tier", inst_sub_tier)
		var egg_data = drop_tables.get_egg_for_monster(egg_info.monster, {}, egg_sub_tier)
		if not egg_data.is_empty():
			var _egg_cap = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
			var egg_result = character.add_egg(egg_data, _egg_cap)
			if egg_result.success:
				reward_messages.append("[color=#A335EE]★ %s ★[/color]" % egg_data.name)
			else:
				reward_messages.append("[color=#FF6666]★ %s found but eggs full! (%d/%d) ★[/color]" % [egg_data.name, character.incubating_eggs.size(), _egg_cap])

	# Mark tile as cleared
	_clear_dungeon_tile(peer_id)

	send_to_peer(peer_id, {
		"type": "dungeon_treasure",
		"rewards": reward_messages,
		"message": "[color=#FFD700]You open the treasure chest![/color]",
		"materials": treasure.get("materials", []),
		"egg": egg_info,
		"player_x": character.dungeon_x,
		"player_y": character.dungeon_y
	})

	# Don't send dungeon_state here - it would wipe the treasure text from game_output
	# Client updates map panel from player position in treasure message
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

	# Safety: ensure entrance is on a walkable tile (not a wall)
	if entrance_pos.y < next_grid.size() and entrance_pos.x < next_grid[0].size():
		if next_grid[entrance_pos.y][entrance_pos.x] == DungeonDatabaseScript.TileType.WALL:
			entrance_pos = _find_any_walkable_tile(next_grid)

	# Advance floor — including party members
	character.advance_dungeon_floor(entrance_pos.x, entrance_pos.y)

	send_to_peer(peer_id, {
		"type": "dungeon_floor_change",
		"floor": character.dungeon_floor + 1,
		"total_floors": dungeon_data.floors,
		"message": "[color=#FFFF00]You descend to floor %d...[/color]" % (character.dungeon_floor + 1)
	})

	_send_dungeon_state(peer_id)
	save_character(peer_id)

	# Move party followers to next floor too
	if _is_party_leader(peer_id):
		var party = active_parties[peer_id]
		for i in range(1, party.members.size()):
			var pid = party.members[i]
			if not characters.has(pid) or not characters[pid].in_dungeon:
				continue
			# Place followers offset from entrance
			var fy = entrance_pos.y + i
			var fx = entrance_pos.x
			if fy >= next_grid.size() or next_grid[fy][fx] == DungeonDatabaseScript.TileType.WALL:
				fy = entrance_pos.y
				fx = entrance_pos.x
			characters[pid].advance_dungeon_floor(fx, fy)
			send_to_peer(pid, {
				"type": "dungeon_floor_change",
				"floor": characters[pid].dungeon_floor + 1,
				"total_floors": dungeon_data.floors,
				"message": "[color=#FFFF00]Your party descends to floor %d...[/color]" % (characters[pid].dungeon_floor + 1)
			})
			_send_dungeon_state(pid)
			save_character(pid)

func _complete_dungeon(peer_id: int):
	"""Handle dungeon completion"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var dungeon_type = character.current_dungeon_type
	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	var instance_id = character.current_dungeon_id
	var inst_sub_tier = 1
	if active_dungeons.has(instance_id):
		inst_sub_tier = active_dungeons[instance_id].get("sub_tier", 1)

	# Calculate rewards (sub-tier scales XP)
	var rewards = DungeonDatabaseScript.calculate_completion_rewards(dungeon_type, character.dungeon_floor + 1, inst_sub_tier)

	# Give rewards
	var xp_result = character.add_experience(rewards.xp)

	# Give GUARANTEED boss egg (inherits dungeon sub-tier)!
	var boss_egg_given = false
	var boss_egg_name = ""
	var boss_egg_lost_to_full = false
	var boss_egg_monster = rewards.get("boss_egg", "")
	if boss_egg_monster != "":
		var egg_data = drop_tables.get_egg_for_monster(boss_egg_monster, {}, inst_sub_tier)
		if not egg_data.is_empty():
			var _egg_cap = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
			var egg_result = character.add_egg(egg_data, _egg_cap)
			if egg_result.success:
				boss_egg_given = true
				boss_egg_name = egg_data.get("name", boss_egg_monster + " Egg")
			else:
				boss_egg_lost_to_full = true
				boss_egg_name = egg_data.get("name", boss_egg_monster + " Egg")

	# Record completion (cooldowns removed)
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

	# Clear any pending flock encounters
	if pending_flocks.has(peer_id):
		pending_flocks.erase(peer_id)
	if pending_flock_drops.has(peer_id):
		pending_flock_drops.erase(peer_id)
	if pending_flock_gems.has(peer_id):
		pending_flock_gems.erase(peer_id)
	if flock_counts.has(peer_id):
		flock_counts.erase(peer_id)

	# Mark the dungeon as completed for despawn timer (world dungeons only)
	if active_dungeons.has(instance_id):
		var instance = active_dungeons[instance_id]
		# Only set completed_at for world dungeons, not player quest dungeons
		if instance.get("owner_peer_id", -1) < 0:
			instance["completed_at"] = int(Time.get_unix_time_from_system())
			log_message("World dungeon %s marked as completed, will despawn in %d seconds" % [instance_id, DUNGEON_DESPAWN_DELAY])

	# Remove from dungeon
	if active_dungeons.has(instance_id):
		active_dungeons[instance_id].active_players.erase(peer_id)

	# Clean up personal dungeon instances for completed quests
	for update in quest_updates:
		if update.completed:
			_cleanup_player_dungeon(peer_id, update.quest_id)

	# Also clean up if this was a free run (non-quest) dungeon
	if player_dungeon_instances.has(peer_id):
		var free_run_key = "_free_run_" + instance_id
		if player_dungeon_instances[peer_id].has(free_run_key):
			player_dungeon_instances[peer_id].erase(free_run_key)
			# Clean up the instance itself
			if active_dungeons.has(instance_id):
				active_dungeons.erase(instance_id)
			if dungeon_floors.has(instance_id):
				dungeon_floors.erase(instance_id)
			if dungeon_floor_rooms.has(instance_id):
				dungeon_floor_rooms.erase(instance_id)
			if dungeon_monsters.has(instance_id):
				dungeon_monsters.erase(instance_id)

	character.exit_dungeon()

	# Build completion message
	var completion_msg = "[color=#FFD700]===== DUNGEON COMPLETE! =====[/color]\n"
	completion_msg += "[color=#00FF00]%s Cleared![/color]\n\n" % dungeon_data.name
	completion_msg += "Floors Cleared: %d/%d\n" % [rewards.floors_cleared, rewards.total_floors]
	completion_msg += "[color=#00BFFF]+%d XP[/color]\n" % rewards.xp

	# Show boss egg reward!
	if boss_egg_given:
		completion_msg += "[color=#FF69B4]★ %s obtained! ★[/color]" % boss_egg_name
	elif boss_egg_lost_to_full:
		var _egg_cap2 = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
		completion_msg += "[color=#FF6666]★ %s found but eggs full! (%d/%d) ★[/color]" % [boss_egg_name, character.incubating_eggs.size(), _egg_cap2]

	if xp_result.leveled_up:
		completion_msg += "\n[color=#FFFF00]★ LEVEL UP! Now level %d ★[/color]" % character.level

	send_to_peer(peer_id, {
		"type": "dungeon_complete",
		"dungeon_name": dungeon_data.name,
		"rewards": rewards,
		"leveled_up": xp_result.leveled_up,
		"new_level": character.level,
		"message": completion_msg,
		"boss_egg_obtained": boss_egg_given,
		"boss_egg_name": boss_egg_name,
		"boss_egg_lost_to_full": boss_egg_lost_to_full
	})

	send_location_update(peer_id)
	send_character_update(peer_id)
	save_character(peer_id)

	# Complete dungeon for party followers too
	if _is_party_leader(peer_id):
		var party = active_parties[peer_id]
		for i in range(1, party.members.size()):
			var pid = party.members[i]
			if not characters.has(pid) or not characters[pid].in_dungeon:
				continue

			var follower = characters[pid]

			# Give same rewards (full duplication, not split)
			var f_rewards = DungeonDatabaseScript.calculate_completion_rewards(dungeon_type, follower.dungeon_floor + 1, inst_sub_tier)
			var f_xp_result = follower.add_experience(f_rewards.xp)

			# Boss egg for each member
			var f_egg_given = false
			var f_egg_name = ""
			var f_egg_lost = false
			if boss_egg_monster != "":
				var f_egg_data = drop_tables.get_egg_for_monster(boss_egg_monster, {}, inst_sub_tier)
				if not f_egg_data.is_empty():
					var f_egg_cap = persistence.get_egg_capacity(peers[pid].account_id) if peers.has(pid) else Character.MAX_INCUBATING_EGGS
					var f_egg_result = follower.add_egg(f_egg_data, f_egg_cap)
					if f_egg_result.success:
						f_egg_given = true
						f_egg_name = f_egg_data.get("name", boss_egg_monster + " Egg")
					else:
						f_egg_lost = true
						f_egg_name = f_egg_data.get("name", boss_egg_monster + " Egg")

			follower.record_dungeon_completion(dungeon_type)

			# Quest progress for follower
			var f_quest_updates = quest_mgr.check_dungeon_progress(follower, dungeon_type)
			for update in f_quest_updates:
				send_to_peer(pid, {
					"type": "quest_progress",
					"quest_id": update.quest_id,
					"progress": update.progress,
					"target": update.target,
					"completed": update.completed,
					"message": update.message
				})

			# Remove from dungeon
			if active_dungeons.has(instance_id):
				active_dungeons[instance_id].active_players.erase(pid)

			follower.exit_dungeon()

			# Build follower completion message
			var f_msg = "[color=#FFD700]===== DUNGEON COMPLETE! =====[/color]\n"
			f_msg += "[color=#00FF00]%s Cleared![/color]\n\n" % dungeon_data.name
			f_msg += "[color=#00BFFF]+%d XP[/color]\n" % f_rewards.xp
			if f_egg_given:
				f_msg += "[color=#FF69B4]★ %s obtained! ★[/color]" % f_egg_name
			elif f_egg_lost:
				f_msg += "[color=#FF6666]★ %s found but eggs full! ★[/color]" % f_egg_name
			if f_xp_result.leveled_up:
				f_msg += "\n[color=#FFFF00]★ LEVEL UP! Now level %d ★[/color]" % follower.level

			send_to_peer(pid, {
				"type": "dungeon_complete",
				"dungeon_name": dungeon_data.name,
				"rewards": f_rewards,
				"leveled_up": f_xp_result.leveled_up,
				"new_level": follower.level,
				"message": f_msg,
				"boss_egg_obtained": f_egg_given,
				"boss_egg_name": f_egg_name,
				"boss_egg_lost_to_full": f_egg_lost
			})

			# Place follower near leader's overworld position
			follower.x = character.x
			follower.y = character.y
			send_location_update(pid)
			send_character_update(pid)
			save_character(pid)

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

# ===== DUNGEON MONSTER ENTITY SYSTEM =====

# Rest material costs by dungeon tier
const DUNGEON_REST_COSTS = {
	1: {"wild_berries": 2},
	2: {"healing_herb": 1},
	3: {"sage": 1},
	4: {"cave_mushroom": 1},
	5: {"moonpetal": 1},
	6: {"glowing_mushroom": 1},
	7: {"bloodroot": 1},
	8: {"spirit_blossom": 1},
	9: {"starbloom": 1}
}

func _spawn_all_dungeon_monsters(instance_id: String, dungeon_type: String, dungeon_level: int):
	"""Spawn monsters on all floors of a dungeon instance"""
	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	if dungeon_data.is_empty():
		return

	if not dungeon_floors.has(instance_id) or not dungeon_floor_rooms.has(instance_id):
		return

	dungeon_monsters[instance_id] = {}
	var floor_grids = dungeon_floors[instance_id]
	var all_rooms = dungeon_floor_rooms[instance_id]

	for floor_num in range(floor_grids.size()):
		var is_boss_floor = floor_num == floor_grids.size() - 1
		var grid = floor_grids[floor_num]
		var rooms = all_rooms[floor_num] if floor_num < all_rooms.size() else []
		_spawn_dungeon_floor_monsters(instance_id, floor_num, dungeon_type, dungeon_level, rooms, grid, is_boss_floor)

func _spawn_dungeon_floor_monsters(instance_id: String, floor_num: int, dungeon_type: String, dungeon_level: int, rooms: Array, grid: Array, is_boss_floor: bool):
	"""Spawn monster entities on a single dungeon floor"""
	var dungeon_data = DungeonDatabaseScript.get_dungeon(dungeon_type)
	if dungeon_data.is_empty():
		return

	var monsters_count = dungeon_data.get("monsters_per_floor", 3)
	var tier = dungeon_data.tier
	var boss_data = dungeon_data.get("boss", {})
	var monster_type = boss_data.get("monster_type", "Goblin")
	var display_color = DungeonDatabaseScript.MONSTER_DISPLAY_COLORS.get(tier, "#FF4444")
	var level_mult = 1.0 + (floor_num * 0.1)
	var monster_level = int(dungeon_level * level_mult)

	# Find entrance and exit positions for distance checks
	var entrance_pos = Vector2i(-1, -1)
	var exit_pos = Vector2i(-1, -1)
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == DungeonDatabaseScript.TileType.ENTRANCE:
				entrance_pos = Vector2i(x, y)
			elif grid[y][x] == DungeonDatabaseScript.TileType.EXIT:
				exit_pos = Vector2i(x, y)

	if not dungeon_monsters[instance_id].has(floor_num):
		dungeon_monsters[instance_id][floor_num] = []

	var floor_monsters = dungeon_monsters[instance_id][floor_num]
	var occupied_positions = []

	# Spawn regular monsters
	for _i in range(monsters_count):
		var pos = _find_monster_spawn_position(grid, entrance_pos, exit_pos, occupied_positions)
		if pos.x < 0:
			continue  # Couldn't find valid position

		occupied_positions.append(pos)
		var display_char = monster_type[0].to_upper() if monster_type.length() > 0 else "M"

		var monster_entity = {
			"id": next_dungeon_monster_id,
			"x": pos.x, "y": pos.y,
			"monster_type": monster_type,
			"level": monster_level,
			"display_char": display_char,
			"display_color": display_color,
			"alive": true,
			"alert": false,
			"is_boss": false,
			"boss_data": {}
		}
		floor_monsters.append(monster_entity)
		next_dungeon_monster_id += 1

	# Spawn boss on boss floor
	if is_boss_floor and not boss_data.is_empty():
		# Place boss in room farthest from entrance
		var boss_pos = Vector2i(-1, -1)
		if rooms.size() > 0:
			var farthest_idx = DungeonDatabaseScript._find_farthest_room(rooms, entrance_pos)
			boss_pos = DungeonDatabaseScript._get_room_center(rooms[farthest_idx])
			# Make sure boss position is walkable
			if boss_pos.x < 0 or boss_pos.y < 0 or boss_pos.x >= grid[0].size() or boss_pos.y >= grid.size():
				boss_pos = _find_monster_spawn_position(grid, entrance_pos, exit_pos, occupied_positions)
			elif grid[boss_pos.y][boss_pos.x] != DungeonDatabaseScript.TileType.EMPTY:
				boss_pos = _find_monster_spawn_position(grid, entrance_pos, exit_pos, occupied_positions)
		else:
			boss_pos = _find_monster_spawn_position(grid, entrance_pos, exit_pos, occupied_positions)

		if boss_pos.x >= 0:
			var boss_entity = {
				"id": next_dungeon_monster_id,
				"x": boss_pos.x, "y": boss_pos.y,
				"monster_type": monster_type,
				"level": int(dungeon_level * boss_data.get("level_mult", 1.5)),
				"display_char": "B",
				"display_color": "#FF0000",
				"alive": true,
				"alert": false,
				"is_boss": true,
				"boss_data": boss_data.duplicate()
			}
			floor_monsters.append(boss_entity)
			next_dungeon_monster_id += 1

func _find_monster_spawn_position(grid: Array, entrance_pos: Vector2i, exit_pos: Vector2i, occupied: Array) -> Vector2i:
	"""Find a valid position to spawn a monster entity"""
	var attempts = 0
	while attempts < 100:
		var x = 1 + randi() % (grid[0].size() - 2)
		var y = 1 + randi() % (grid.size() - 2)

		# Must be walkable
		if grid[y][x] != DungeonDatabaseScript.TileType.EMPTY:
			attempts += 1
			continue

		# Must be >= 4 tiles from entrance and exit (Manhattan distance)
		if entrance_pos.x >= 0:
			var dist_entrance = abs(x - entrance_pos.x) + abs(y - entrance_pos.y)
			if dist_entrance < 4:
				attempts += 1
				continue
		if exit_pos.x >= 0:
			var dist_exit = abs(x - exit_pos.x) + abs(y - exit_pos.y)
			if dist_exit < 4:
				attempts += 1
				continue

		# No overlap with other monsters
		var overlap = false
		for pos in occupied:
			if pos.x == x and pos.y == y:
				overlap = true
				break
		if overlap:
			attempts += 1
			continue

		return Vector2i(x, y)

	return Vector2i(-1, -1)  # Failed to find position

func _get_monster_at_position(instance_id: String, floor_num: int, x: int, y: int):
	"""Get alive monster entity at position, or null"""
	if not dungeon_monsters.has(instance_id):
		return null
	var floor_monsters = dungeon_monsters[instance_id].get(floor_num, [])
	for m in floor_monsters:
		if m.alive and m.x == x and m.y == y:
			return m
	return null

func _kill_dungeon_monster(instance_id: String, floor_num: int, monster_id: int):
	"""Mark a monster entity as dead"""
	if not dungeon_monsters.has(instance_id):
		return
	var floor_monsters = dungeon_monsters[instance_id].get(floor_num, [])
	for m in floor_monsters:
		if m.id == monster_id:
			m.alive = false
			return

func _move_dungeon_monsters(peer_id: int) -> bool:
	"""Move all monsters on the player's current floor. Returns true if combat triggered."""
	if not characters.has(peer_id):
		return false

	var character = characters[peer_id]
	var instance_id = character.current_dungeon_id
	if not dungeon_monsters.has(instance_id) or not dungeon_floors.has(instance_id):
		return false

	var floor_num = character.dungeon_floor
	var floor_monsters = dungeon_monsters[instance_id].get(floor_num, [])
	if floor_monsters.is_empty():
		return false

	var floor_grids = dungeon_floors[instance_id]
	if floor_num >= floor_grids.size():
		return false
	var grid = floor_grids[floor_num]
	var player_pos = Vector2i(character.dungeon_x, character.dungeon_y)

	for m in floor_monsters:
		if not m.alive:
			continue

		# Bosses are stationary — they stay in their room and don't block hallways
		if m.get("is_boss", false):
			var monster_pos = Vector2i(m.x, m.y)
			var dist = abs(monster_pos.x - player_pos.x) + abs(monster_pos.y - player_pos.y)
			if dist <= 3 and _has_line_of_sight(grid, monster_pos, player_pos):
				m.alert = true
			else:
				m.alert = false
			# Check if player walked onto boss
			if m.alive and m.x == player_pos.x and m.y == player_pos.y:
				_start_dungeon_monster_combat(peer_id, m)
				return true
			continue

		var monster_pos = Vector2i(m.x, m.y)
		var dist = abs(monster_pos.x - player_pos.x) + abs(monster_pos.y - player_pos.y)

		# Detection: within 3 tiles AND has line of sight
		if dist <= 3 and _has_line_of_sight(grid, monster_pos, player_pos):
			m.alert = true
			# Chase toward player
			_move_monster_toward(m, player_pos, grid, floor_monsters)
		else:
			m.alert = false
			# Wander randomly (25% stay still)
			_move_monster_random(m, grid, floor_monsters)

		# Check if monster landed on player
		if m.alive and m.x == player_pos.x and m.y == player_pos.y:
			_start_dungeon_monster_combat(peer_id, m)
			return true

	return false

func _has_line_of_sight(grid: Array, from: Vector2i, to: Vector2i) -> bool:
	"""Check line of sight using Bresenham's line algorithm"""
	var x0 = from.x
	var y0 = from.y
	var x1 = to.x
	var y1 = to.y

	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy

	while true:
		# Don't check start and end positions
		if not (x0 == from.x and y0 == from.y) and not (x0 == to.x and y0 == to.y):
			if y0 >= 0 and y0 < grid.size() and x0 >= 0 and x0 < grid[0].size():
				if grid[y0][x0] == DungeonDatabaseScript.TileType.WALL:
					return false

		if x0 == x1 and y0 == y1:
			break

		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

	return true

func _move_monster_toward(monster: Dictionary, target: Vector2i, grid: Array, all_monsters: Array):
	"""Move monster one step toward target"""
	var dx = target.x - monster.x
	var dy = target.y - monster.y

	# Try primary axis first (greater distance), then secondary
	var moves_to_try = []
	if abs(dx) >= abs(dy):
		if dx != 0:
			moves_to_try.append(Vector2i(sign(dx), 0))
		if dy != 0:
			moves_to_try.append(Vector2i(0, sign(dy)))
	else:
		if dy != 0:
			moves_to_try.append(Vector2i(0, sign(dy)))
		if dx != 0:
			moves_to_try.append(Vector2i(sign(dx), 0))

	for move in moves_to_try:
		var nx = monster.x + move.x
		var ny = monster.y + move.y
		if _is_valid_monster_move(nx, ny, grid, all_monsters, monster.id):
			monster.x = nx
			monster.y = ny
			return

func _move_monster_random(monster: Dictionary, grid: Array, all_monsters: Array):
	"""Move monster in a random direction (25% stay still)"""
	if randi() % 4 == 0:
		return  # 25% stay still

	var directions = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	directions.shuffle()

	for dir in directions:
		var nx = monster.x + dir.x
		var ny = monster.y + dir.y
		if _is_valid_monster_move(nx, ny, grid, all_monsters, monster.id):
			monster.x = nx
			monster.y = ny
			return

func _is_valid_monster_move(x: int, y: int, grid: Array, all_monsters: Array, self_id: int) -> bool:
	"""Check if a monster can move to position"""
	# Bounds check
	if y < 0 or y >= grid.size() or x < 0 or x >= grid[0].size():
		return false

	# Can't walk through walls
	var tile = grid[y][x]
	if tile == DungeonDatabaseScript.TileType.WALL:
		return false

	# Don't step on entrance/exit/treasure tiles
	if tile == DungeonDatabaseScript.TileType.ENTRANCE or tile == DungeonDatabaseScript.TileType.EXIT or tile == DungeonDatabaseScript.TileType.TREASURE:
		return false

	# No overlap with other alive monsters
	for m in all_monsters:
		if m.alive and m.id != self_id and m.x == x and m.y == y:
			return false

	return true

func _start_dungeon_monster_combat(peer_id: int, monster_entity: Dictionary):
	"""Start combat with a dungeon monster entity"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var instance_id = character.current_dungeon_id
	if not active_dungeons.has(instance_id):
		return

	# Send dungeon state first so client map shows current positions before combat
	_send_dungeon_state(peer_id)

	var instance = active_dungeons[instance_id]
	var dungeon_data = DungeonDatabaseScript.get_dungeon(character.current_dungeon_type)

	# Generate the combat monster from entity data
	var monster_lookup = monster_entity.monster_type
	var monster = monster_db.generate_monster_by_name(monster_lookup, monster_entity.level)
	if monster.is_empty():
		monster = monster_db.generate_monster(monster_entity.level, monster_entity.level)
	monster.is_dungeon_monster = true

	# Apply boss multipliers if boss
	var is_boss = monster_entity.is_boss
	if is_boss and not monster_entity.boss_data.is_empty():
		var boss_info = monster_entity.boss_data
		monster.max_hp = int(monster.max_hp * boss_info.get("hp_mult", 2.0))
		monster.current_hp = monster.max_hp
		monster.strength = int(monster.strength * boss_info.get("attack_mult", 1.5))
		monster.is_boss = true
		monster.name = boss_info.get("name", monster.name)

	# Party dungeon combat?
	if _is_party_leader(peer_id):
		_start_party_combat_encounter(peer_id, monster, [])
		return

	# Start combat
	var result = combat_mgr.start_combat(peer_id, character, monster)

	# Mark internal combat state for dungeon-specific handling
	var internal_state = combat_mgr.get_active_combat(peer_id)
	internal_state["is_dungeon_combat"] = true
	internal_state["is_boss_fight"] = is_boss
	internal_state["dungeon_monster_id"] = monster_entity.id

	# Get display-ready combat state
	var display_state = combat_mgr.get_combat_display(peer_id)
	display_state["is_dungeon_combat"] = true
	display_state["is_boss_fight"] = is_boss

	var boss_text = " [BOSS]" if is_boss else ""
	var encounter_msg = "[color=#FF4444]A %s%s appears![/color]" % [monster.name, boss_text]

	send_to_peer(peer_id, {
		"type": "combat_start",
		"message": encounter_msg,
		"combat_state": display_state,
		"is_dungeon_combat": true,
		"is_boss": is_boss,
		"use_client_art": true,
		"extra_combat_text": result.get("extra_combat_text", "")
	})

func handle_dungeon_rest(peer_id: int):
	"""Handle player resting in a dungeon to recover HP/mana"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	if not character.in_dungeon:
		send_to_peer(peer_id, {"type": "error", "message": "You are not in a dungeon!"})
		return

	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "error", "message": "You cannot rest while in combat!"})
		return

	var instance_id = character.current_dungeon_id
	if not active_dungeons.has(instance_id):
		return

	var dungeon_data = DungeonDatabaseScript.get_dungeon(character.current_dungeon_type)
	var tier = dungeon_data.get("tier", 1)

	# Check material cost
	var cost = DUNGEON_REST_COSTS.get(tier, {"wild_berries": 2})
	var missing_materials = []
	for mat_id in cost:
		var needed = cost[mat_id]
		var have = character.crafting_materials.get(mat_id, 0)
		if have < needed:
			var mat_name = mat_id.capitalize().replace("_", " ")
			missing_materials.append("%d %s (have %d)" % [needed, mat_name, have])

	if not missing_materials.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF6666]Not enough materials to rest! Need: %s[/color]" % ", ".join(missing_materials)
		})
		return

	# Consume materials
	for mat_id in cost:
		character.crafting_materials[mat_id] -= cost[mat_id]
		if character.crafting_materials[mat_id] <= 0:
			character.crafting_materials.erase(mat_id)

	# Heal based on class
	var heal_messages = []
	var is_mage = character.character_class in ["Wizard", "Sorcerer", "Sage"]

	if is_mage:
		# Mages recover mana (5-12.5%) and some HP (3-5%)
		var mana_restore = int(character.max_mana * randf_range(0.05, 0.125))
		character.current_mana = min(character.max_mana, character.current_mana + mana_restore)
		var hp_restore = int(character.max_hp * randf_range(0.03, 0.05))
		character.current_hp = min(character.max_hp, character.current_hp + hp_restore)
		heal_messages.append("[color=#00BFFF]+%d Mana[/color]" % mana_restore)
		heal_messages.append("[color=#00FF00]+%d HP[/color]" % hp_restore)
	else:
		# Non-mages recover HP (5-12.5%)
		var hp_restore = int(character.max_hp * randf_range(0.05, 0.125))
		character.current_hp = min(character.max_hp, character.current_hp + hp_restore)
		heal_messages.append("[color=#00FF00]+%d HP[/color]" % hp_restore)

	# Tick poison on dungeon rest
	if character.poison_active:
		var poison_dmg = character.tick_poison()
		if poison_dmg != 0:
			var turns_left = character.poison_turns_remaining
			var poison_msg = ""
			if poison_dmg < 0:
				var heal_amount2 = -poison_dmg
				character.current_hp = min(character.get_total_max_hp(), character.current_hp + heal_amount2)
				poison_msg = "[color=#708090]Undead absorbs poison, healing [color=#00FF00]%d HP[/color][/color]" % heal_amount2
			else:
				character.current_hp -= poison_dmg
				character.current_hp = max(1, character.current_hp)
				poison_msg = "[color=#00FF00]Poison[/color] deals [color=#FF4444]%d damage[/color]" % poison_dmg
			if turns_left > 0:
				poison_msg += " (%d rounds remaining)" % turns_left
			else:
				poison_msg += " - [color=#00FF00]Poison has worn off![/color]"
			send_to_peer(peer_id, {"type": "status_effect", "effect": "poison", "message": poison_msg, "damage": poison_dmg, "turns_remaining": turns_left})

	# Tick blind on dungeon rest
	if character.blind_active:
		var still_blind = character.tick_blind()
		var turns_left = character.blind_turns_remaining
		if still_blind:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "blind", "message": "[color=#808080]You are blinded! (%d rounds remaining)[/color]" % turns_left, "turns_remaining": turns_left})
		else:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "blind_cured", "message": "[color=#00FF00]Your vision clears![/color]"})

	# Tick active buffs on dungeon rest
	if not character.active_buffs.is_empty():
		var expired = character.tick_buffs()
		for buff in expired:
			send_to_peer(peer_id, {"type": "status_effect", "effect": "buff_expired", "message": "[color=#808080]%s buff has worn off.[/color]" % buff.type})

	# Move all monsters (rest is not free!)
	var monster_combat = _move_dungeon_monsters(peer_id)
	if monster_combat:
		# A monster found the player during rest!
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF4444]Your rest is interrupted![/color] " + " ".join(heal_messages)
		})
		send_character_update(peer_id)
		save_character(peer_id)
		return

	# Send dungeon state FIRST (this redraws game_output), then rest result text AFTER
	# so the rest message appears below the dungeon floor status
	_send_dungeon_state(peer_id)

	var cost_text = []
	for mat_id in cost:
		cost_text.append("%d %s" % [cost[mat_id], mat_id.capitalize().replace("_", " ")])

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#87CEEB]You rest briefly...[/color] %s [color=#808080](-%s)[/color]" % [" ".join(heal_messages), ", ".join(cost_text)]
	})

	send_character_update(peer_id)
	save_character(peer_id)

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
		"revoked for abuse":
			msg = "[color=#FF4444]%s has had their title of %s revoked![/color]" % [player_name, title_name]

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

	# Check and consume valor cost
	var valor_cost = ability.get("valor_cost", 0)
	var title_account_id = peers[peer_id].account_id
	if ability.has("valor_cost_percent"):
		valor_cost = int(persistence.get_valor(title_account_id) * ability.valor_cost_percent / 100.0)
	if valor_cost > 0:
		if persistence.get_valor(title_account_id) < valor_cost:
			send_to_peer(peer_id, {"type": "error", "message": "Not enough valor (%d required)." % valor_cost})
			return

	# Check gem cost (now uses Monster Gem crafting material)
	var gem_cost = ability.get("gem_cost", 0)
	if gem_cost > 0:
		if not character.has_crafting_materials({"monster_gem": gem_cost}):
			send_to_peer(peer_id, {"type": "error", "message": "Not enough Monster Gems (%d required)." % gem_cost})
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
		if target == null:
			send_to_peer(peer_id, {"type": "error", "message": "Player is no longer online."})
			return

		# Check max target level for Mentor
		if ability.has("max_target_level") and target.level > ability.max_target_level:
			send_to_peer(peer_id, {"type": "error", "message": "Target must be below level %d." % ability.max_target_level})
			return

	# Deduct costs after all checks pass
	if valor_cost > 0:
		persistence.spend_valor(title_account_id, valor_cost)
	if gem_cost > 0:
		character.remove_crafting_material("monster_gem", gem_cost)

	# Set cooldown
	if ability.has("cooldown"):
		character.set_ability_cooldown(ability_id, ability.cooldown)

	# Track abuse for negative abilities
	if ability.get("is_negative", false):
		if target:
			_track_title_abuse(peer_id, character, target_peer_id, target)
		else:
			_track_title_abuse_self(peer_id, character)

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

func _track_title_abuse_self(peer_id: int, character: Character):
	"""Track abuse points for self-targeted negative title abilities (e.g., Collect Tribute)"""
	character.decay_abuse_points()
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
	var title_account_id = peers[peer_id].account_id if peers.has(peer_id) else ""

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
			if target and peers.has(target_peer_id):
				var target_account_id = peers[target_peer_id].account_id
				var tax_amount = mini(500, int(persistence.get_valor(target_account_id) * 0.05))
				persistence.spend_valor(target_account_id, tax_amount)
				persistence.add_valor(title_account_id, tax_amount)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#C0C0C0]The Jarl has taxed you %d valor![/color]" % tax_amount
				})
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You collected %d valor in taxes from %s.[/color]" % [tax_amount, target.name]
				})
				_broadcast_chat_from_title(character.name, character.title, "has taxed %s!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"gift_silver":
			if target and peers.has(target_peer_id):
				var gift_amount = int(persistence.get_valor(title_account_id) * 0.08)  # They already paid 5%, give 8%
				persistence.add_valor(peers[target_peer_id].account_id, gift_amount)
				send_to_peer(target_peer_id, {
					"type": "text",
					"message": "[color=#FFD700]The Jarl has gifted you %d valor![/color]" % gift_amount
				})
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You gifted %d valor to %s.[/color]" % [gift_amount, target.name]
				})
				_broadcast_chat_from_title(character.name, character.title, "has gifted %s with valor!" % target.name)
				send_character_update(target_peer_id)
				save_character(target_peer_id)

		"collect_tribute":
			var abilities = TitlesScript.get_title_abilities(character.title)
			var treasury_percent = abilities["collect_tribute"].get("treasury_percent", 15)
			var current_treasury = persistence.get_realm_treasury()
			var tribute = int(current_treasury * treasury_percent / 100.0)
			if tribute > 0:
				var withdrawn = persistence.withdraw_from_realm_treasury(tribute)
				persistence.add_valor(title_account_id, withdrawn)
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You claim %d valor from the realm treasury (%d%% of %d).[/color]" % [withdrawn, treasury_percent, current_treasury]
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
					"message": "[color=#87CEEB]The High King has knighted you! You gain +15%% damage and +10%% market bonus permanently![/color]"
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
				persistence.add_valor(title_account_id, withdrawn)
				send_to_peer(peer_id, {
					"type": "text",
					"message": "[color=#FFD700]You claim %d valor from the royal treasury (%d%% of %d).[/color]" % [withdrawn, treasury_percent, current_treasury]
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
					"message": "[color=#DDA0DD]Elder %s has taken you as their Mentee! You gain +50%% XP permanently![/color]" % character.name
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
				msg += "[color=#FFD700][ ] Shrine of Wealth: %d / %d valor donated[/color]\n" % [donated, gold_req]
				msg += "[color=#808080]    Use /donate <amount> to donate valor[/color]"

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
	"""Handle valor donation for Trial of Wealth"""
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

	var pilgrim_account_id = peers[peer_id].account_id
	if persistence.get_valor(pilgrim_account_id) < amount:
		send_to_peer(peer_id, {"type": "error", "message": "You don't have enough valor."})
		return

	# Process donation
	persistence.spend_valor(pilgrim_account_id, amount)
	character.add_pilgrimage_gold_donation(amount)

	var total_donated = character.pilgrimage_progress.get("gold_donated", 0)
	var required = TitlesScript.PILGRIMAGE_STAGES["trial_wealth"].requirement

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#FFD700]You donate %d valor to the Shrine of Wealth.[/color]\n[color=#808080]Total donated: %d / %d valor[/color]" % [amount, total_donated, required]
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
			var refund_valor_cost = abilities.get("summon", {}).get("valor_cost", 50)
			if peers.has(from_peer_id):
				persistence.add_valor(peers[from_peer_id].account_id, refund_valor_cost)
			send_to_peer(from_peer_id, {
				"type": "text",
				"message": "[color=#FFD700]%d valor refunded.[/color]" % refund_valor_cost
			})
			send_character_update(from_peer_id)

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
			"special_message": "[color=#FF4444]CRUCIBLE BOSS %d/10: %s (Lv.%d)[/color]" % [boss_num, monster.name, boss_level],
			"extra_combat_text": result.get("extra_combat_text", "")
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
	if abs(character.x) <= 1 and abs(character.y) <= 1:
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
	var partner_companions_data = []
	var partner_eggs_data = []
	if characters.has(partner_id):
		var partner_char = characters[partner_id]
		partner_name = partner_char.name
		partner_class = partner_char.class_type
		# Convert partner's item indices to actual item data
		var partner_inventory = partner_char.inventory
		for idx in partner_trade.get("my_items", []):
			if idx >= 0 and idx < partner_inventory.size():
				partner_items_data.append(partner_inventory[idx])
		# Convert partner's companion indices to actual companion data
		for idx in partner_trade.get("my_companions", []):
			if idx >= 0 and idx < partner_char.collected_companions.size():
				partner_companions_data.append(partner_char.collected_companions[idx])
		# Convert partner's egg indices to actual egg data
		for idx in partner_trade.get("my_eggs", []):
			if idx >= 0 and idx < partner_char.incubating_eggs.size():
				partner_eggs_data.append(partner_char.incubating_eggs[idx])

	# Get my character info and data
	var my_class = ""
	var my_companions_data = []
	var my_eggs_data = []
	if characters.has(peer_id):
		var my_char = characters[peer_id]
		my_class = my_char.class_type
		# Convert my companion indices to actual companion data
		for idx in trade.get("my_companions", []):
			if idx >= 0 and idx < my_char.collected_companions.size():
				my_companions_data.append(my_char.collected_companions[idx])
		# Convert my egg indices to actual egg data
		for idx in trade.get("my_eggs", []):
			if idx >= 0 and idx < my_char.incubating_eggs.size():
				my_eggs_data.append(my_char.incubating_eggs[idx])

	send_to_peer(peer_id, {
		"type": "trade_update",
		"partner_name": partner_name,
		"partner_class": partner_class,
		"my_class": my_class,
		"my_items": trade.my_items,
		"partner_items": partner_items_data,  # Send actual item data, not indices
		"my_companions": trade.get("my_companions", []),
		"my_companions_data": my_companions_data,
		"partner_companions": partner_companions_data,
		"my_eggs": trade.get("my_eggs", []),
		"my_eggs_data": my_eggs_data,
		"partner_eggs": partner_eggs_data,
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
		"my_companions": [],  # Array of companion indices
		"my_eggs": [],  # Array of egg indices
		"my_ready": false
	}
	active_trades[requester_id] = {
		"partner_id": peer_id,
		"my_items": [],
		"my_companions": [],
		"my_eggs": [],
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

func handle_trade_add_companion(peer_id: int, message: Dictionary):
	"""Handle adding a companion to trade offer."""
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
	if index < 0 or index >= character.collected_companions.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid companion index."})
		return

	# Check if already in offer
	if index in trade.my_companions:
		send_to_peer(peer_id, {"type": "error", "message": "Companion already in trade offer."})
		return

	# Check if this is the active companion or a registered companion
	var companion = character.collected_companions[index]
	if companion.get("house_slot", -1) >= 0:
		send_to_peer(peer_id, {"type": "error", "message": "Cannot trade a registered house companion."})
		return
	if not character.active_companion.is_empty() and character.active_companion.get("id") == companion.get("id"):
		send_to_peer(peer_id, {"type": "error", "message": "Cannot trade your active companion. Dismiss it first."})
		return

	# Add to offer
	trade.my_companions.append(index)

	# Update both players
	_send_trade_update(peer_id)
	_send_trade_update(trade.partner_id)

func handle_trade_remove_companion(peer_id: int, message: Dictionary):
	"""Handle removing a companion from trade offer."""
	if not characters.has(peer_id) or not active_trades.has(peer_id):
		return

	var trade = active_trades[peer_id]
	var index = message.get("index", -1)

	# Reset ready status when offer changes
	trade.my_ready = false
	if active_trades.has(trade.partner_id):
		active_trades[trade.partner_id].my_ready = false

	# Remove from offer
	var offer_index = trade.my_companions.find(index)
	if offer_index != -1:
		trade.my_companions.remove_at(offer_index)

	# Update both players
	_send_trade_update(peer_id)
	_send_trade_update(trade.partner_id)

func handle_trade_add_egg(peer_id: int, message: Dictionary):
	"""Handle adding an egg to trade offer."""
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
	if index < 0 or index >= character.incubating_eggs.size():
		send_to_peer(peer_id, {"type": "error", "message": "Invalid egg index."})
		return

	# Check if already in offer
	if index in trade.my_eggs:
		send_to_peer(peer_id, {"type": "error", "message": "Egg already in trade offer."})
		return

	# Add to offer
	trade.my_eggs.append(index)

	# Update both players
	_send_trade_update(peer_id)
	_send_trade_update(trade.partner_id)

func handle_trade_remove_egg(peer_id: int, message: Dictionary):
	"""Handle removing an egg from trade offer."""
	if not characters.has(peer_id) or not active_trades.has(peer_id):
		return

	var trade = active_trades[peer_id]
	var index = message.get("index", -1)

	# Reset ready status when offer changes
	trade.my_ready = false
	if active_trades.has(trade.partner_id):
		active_trades[trade.partner_id].my_ready = false

	# Remove from offer
	var offer_index = trade.my_eggs.find(index)
	if offer_index != -1:
		trade.my_eggs.remove_at(offer_index)

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
	var companions_from_a = []
	var companions_from_b = []
	var eggs_from_a = []
	var eggs_from_b = []

	# Sort indices in descending order so we can remove without index shifting issues
	var indices_a = trade_a.my_items.duplicate()
	var indices_b = trade_b.my_items.duplicate()
	indices_a.sort()
	indices_a.reverse()
	indices_b.sort()
	indices_b.reverse()

	var companion_indices_a = trade_a.get("my_companions", []).duplicate()
	var companion_indices_b = trade_b.get("my_companions", []).duplicate()
	companion_indices_a.sort()
	companion_indices_a.reverse()
	companion_indices_b.sort()
	companion_indices_b.reverse()

	var egg_indices_a = trade_a.get("my_eggs", []).duplicate()
	var egg_indices_b = trade_b.get("my_eggs", []).duplicate()
	egg_indices_a.sort()
	egg_indices_a.reverse()
	egg_indices_b.sort()
	egg_indices_b.reverse()

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

	# Validate companion space (max 5 companions per character)
	var companion_space_a = 5 - char_a.collected_companions.size() + companion_indices_a.size()
	var companion_space_b = 5 - char_b.collected_companions.size() + companion_indices_b.size()
	if companion_space_a < companion_indices_b.size():
		_cancel_trade(peer_id_a, "%s doesn't have enough companion space." % char_a.name)
		return
	if companion_space_b < companion_indices_a.size():
		_cancel_trade(peer_id_a, "%s doesn't have enough companion space." % char_b.name)
		return

	# Validate egg space (base 3 + egg_slots upgrade)
	var _egg_cap_a = persistence.get_egg_capacity(peers[peer_id_a].account_id) if peers.has(peer_id_a) else Character.MAX_INCUBATING_EGGS
	var _egg_cap_b = persistence.get_egg_capacity(peers[peer_id_b].account_id) if peers.has(peer_id_b) else Character.MAX_INCUBATING_EGGS
	var egg_space_a = _egg_cap_a - char_a.incubating_eggs.size() + egg_indices_a.size()
	var egg_space_b = _egg_cap_b - char_b.incubating_eggs.size() + egg_indices_b.size()
	if egg_space_a < egg_indices_b.size():
		_cancel_trade(peer_id_a, "%s doesn't have enough egg space." % char_a.name)
		return
	if egg_space_b < egg_indices_a.size():
		_cancel_trade(peer_id_a, "%s doesn't have enough egg space." % char_b.name)
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

	# Extract companions from A
	for idx in companion_indices_a:
		if idx >= 0 and idx < char_a.collected_companions.size():
			companions_from_a.append(char_a.collected_companions[idx].duplicate(true))
			char_a.collected_companions.remove_at(idx)

	# Extract companions from B
	for idx in companion_indices_b:
		if idx >= 0 and idx < char_b.collected_companions.size():
			companions_from_b.append(char_b.collected_companions[idx].duplicate(true))
			char_b.collected_companions.remove_at(idx)

	# Extract eggs from A
	for idx in egg_indices_a:
		if idx >= 0 and idx < char_a.incubating_eggs.size():
			eggs_from_a.append(char_a.incubating_eggs[idx].duplicate(true))
			char_a.incubating_eggs.remove_at(idx)

	# Extract eggs from B
	for idx in egg_indices_b:
		if idx >= 0 and idx < char_b.incubating_eggs.size():
			eggs_from_b.append(char_b.incubating_eggs[idx].duplicate(true))
			char_b.incubating_eggs.remove_at(idx)

	# Give items to each player
	for item in items_from_b:
		char_a.add_item(item)
	for item in items_from_a:
		char_b.add_item(item)

	# Give companions to each player
	for companion in companions_from_b:
		char_a.collected_companions.append(companion)
	for companion in companions_from_a:
		char_b.collected_companions.append(companion)

	# Give eggs to each player
	for egg in eggs_from_b:
		char_a.incubating_eggs.append(egg)
	for egg in eggs_from_a:
		char_b.incubating_eggs.append(egg)

	# Clear trade state
	active_trades.erase(peer_id_a)
	active_trades.erase(peer_id_b)

	# Save both characters
	save_character(peer_id_a)
	save_character(peer_id_b)

	# Calculate total counts for display
	var total_received_a = items_from_b.size() + companions_from_b.size() + eggs_from_b.size()
	var total_gave_a = items_from_a.size() + companions_from_a.size() + eggs_from_a.size()
	var total_received_b = items_from_a.size() + companions_from_a.size() + eggs_from_a.size()
	var total_gave_b = items_from_b.size() + companions_from_b.size() + eggs_from_b.size()

	# Notify both players
	send_to_peer(peer_id_a, {
		"type": "trade_complete",
		"received_count": total_received_a,
		"gave_count": total_gave_a,
		"received_items": items_from_b.size(),
		"received_companions": companions_from_b.size(),
		"received_eggs": eggs_from_b.size()
	})
	send_to_peer(peer_id_b, {
		"type": "trade_complete",
		"received_count": total_received_b,
		"gave_count": total_gave_b,
		"received_items": items_from_a.size(),
		"received_companions": companions_from_a.size(),
		"received_eggs": eggs_from_a.size()
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

# ===== CORPSE SYSTEM =====

func _create_corpse_from_character(character: Character, cause_of_death: String) -> Dictionary:
	"""Create a corpse from a dead character's possessions."""
	# Determine death location
	var death_x = character.x
	var death_y = character.y

	# If in dungeon, use dungeon entrance coordinates
	if character.in_dungeon and active_dungeons.has(character.current_dungeon_id):
		var dungeon = active_dungeons[character.current_dungeon_id]
		death_x = dungeon.get("world_x", character.x)
		death_y = dungeon.get("world_y", character.y)

	# Calculate distance from origin - corpse spawns at HALF distance
	var distance = sqrt(float(death_x * death_x + death_y * death_y))
	var spawn_location = _generate_random_location_at_distance(distance * 0.5)

	# Avoid spawning corpse on trading post tiles or inside player enclosures
	for _attempt in range(10):
		if not trading_post_db.is_trading_post_tile(spawn_location.x, spawn_location.y) and not enclosure_tile_lookup.has(Vector2i(spawn_location.x, spawn_location.y)):
			break
		spawn_location = _generate_random_location_at_distance(distance * 0.5)

	# Build corpse contents
	var contents = {
		"items": [],  # Now holds up to 2 equipment pieces
		"active_companion": null,
		"other_companion": null,
		"egg": null,
		"monster_gems": 0
	}

	# Select TWO random equipped items
	var equipped_slots = []
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		if character.equipped.get(slot) != null:
			equipped_slots.append(slot)

	equipped_slots.shuffle()
	for i in range(mini(2, equipped_slots.size())):
		contents["items"].append(character.equipped[equipped_slots[i]].duplicate(true))

	# Copy active companion (full persistence) - skip registered companions (they return to house)
	if not character.active_companion.is_empty() and character.active_companion.get("house_slot", -1) < 0:
		contents["active_companion"] = character.active_companion.duplicate(true)

	# Select one random OTHER owned companion (not the active one, not registered to house)
	var other_companions = []
	for comp in character.collected_companions:
		if comp.get("id", "") != character.active_companion.get("id", "") and comp.get("house_slot", -1) < 0:
			other_companions.append(comp)
	if not other_companions.is_empty():
		var random_idx = randi() % other_companions.size()
		contents["other_companion"] = other_companions[random_idx].duplicate(true)

	# Include an egg if player has one
	if not character.incubating_eggs.is_empty():
		var random_idx = randi() % character.incubating_eggs.size()
		contents["egg"] = character.incubating_eggs[random_idx].duplicate(true)

	# Random percentage of monster gems (10-50%)
	var player_monster_gems = character.crafting_materials.get("monster_gem", 0)
	if player_monster_gems > 0:
		var gem_percent = randf_range(0.1, 0.5)
		contents["monster_gems"] = int(player_monster_gems * gem_percent)

	# Don't create empty corpses
	if contents["items"].is_empty() and contents["active_companion"] == null and contents["other_companion"] == null and contents["egg"] == null and contents["monster_gems"] == 0:
		return {}

	# Generate unique corpse ID
	var corpse_id = "corpse_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 10000]

	return {
		"id": corpse_id,
		"character_name": character.name,
		"x": spawn_location.x,
		"y": spawn_location.y,
		"death_x": death_x,
		"death_y": death_y,
		"created_at": int(Time.get_unix_time_from_system()),
		"cause_of_death": cause_of_death,
		"contents": contents
	}

func _generate_random_location_at_distance(distance: float) -> Vector2i:
	"""Generate a random location at approximately the same distance from origin."""
	# Apply ±10% distance variation
	var varied_distance = distance * randf_range(0.9, 1.1)
	# Clamp to world bounds
	varied_distance = clamp(varied_distance, 1.0, 1000.0)

	# Random angle
	var angle = randf() * TAU

	# Calculate coordinates
	var x = int(round(cos(angle) * varied_distance))
	var y = int(round(sin(angle) * varied_distance))

	# Clamp to world bounds
	x = clampi(x, -1000, 1000)
	y = clampi(y, -1000, 1000)

	return Vector2i(x, y)

func _broadcast_corpse_spawn(corpse: Dictionary):
	"""Notify nearby players of a new corpse."""
	var corpse_x = corpse.get("x", 0)
	var corpse_y = corpse.get("y", 0)
	var view_radius = 6

	for peer_id in characters.keys():
		var char = characters[peer_id]
		if abs(char.x - corpse_x) <= view_radius and abs(char.y - corpse_y) <= view_radius:
			send_location_update(peer_id)

func _broadcast_corpse_despawn(corpse: Dictionary):
	"""Notify nearby players that a corpse was looted."""
	_broadcast_corpse_spawn(corpse)  # Same effect - refresh location for nearby players

func handle_loot_corpse(peer_id: int, message: Dictionary):
	"""Handle a player looting a corpse."""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var corpse_id = message.get("corpse_id", "")

	# Get corpse at player's location
	var corpse = persistence.get_corpse_at(character.x, character.y)
	if corpse.is_empty():
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF0000]There is no corpse here.[/color]"
		})
		return

	# Verify corpse ID matches (prevents race conditions)
	if corpse.get("id", "") != corpse_id:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#FF0000]That corpse is no longer here.[/color]"
		})
		return

	var contents = corpse.get("contents", {})
	var loot_summary = []
	var warnings = []

	# Transfer items (up to 2 equipment pieces)
	var items = contents.get("items", [])
	# Support legacy single-item format
	var legacy_item = contents.get("item")
	if legacy_item != null and legacy_item is Dictionary and not legacy_item.is_empty():
		items.append(legacy_item)
	for item in items:
		if item != null and item is Dictionary and not item.is_empty():
			if character.inventory.size() < Character.MAX_INVENTORY_SIZE:
				character.inventory.append(item)
				var item_name = item.get("name", "Unknown Item")
				var rarity = item.get("rarity", "common")
				var rarity_color = _get_rarity_color(rarity)
				loot_summary.append("[color=%s]%s[/color]" % [rarity_color, item_name])
			else:
				warnings.append("[color=#FF8800]Inventory full - item lost![/color]")

	# Build set of companion IDs the player already owns (prevent duplicates)
	var owned_companion_ids = {}
	for comp in character.collected_companions:
		owned_companion_ids[comp.get("id", "")] = true

	# Transfer active companion
	var active_companion = contents.get("active_companion")
	# Support legacy format
	if active_companion == null:
		active_companion = contents.get("companion")
	if active_companion != null and active_companion is Dictionary and not active_companion.is_empty():
		if not owned_companion_ids.has(active_companion.get("id", "")):
			character.collected_companions.append(active_companion)
			var comp_name = active_companion.get("name", "Unknown")
			var comp_variant = active_companion.get("variant", "")
			var comp_level = active_companion.get("level", 1)
			loot_summary.append("[color=#00FF00]%s %s (Lv.%d)[/color]" % [comp_variant, comp_name, comp_level])

	# Transfer other companion
	var other_companion = contents.get("other_companion")
	if other_companion != null and other_companion is Dictionary and not other_companion.is_empty():
		if not owned_companion_ids.has(other_companion.get("id", "")):
			character.collected_companions.append(other_companion)
			var comp_name = other_companion.get("name", "Unknown")
			var comp_variant = other_companion.get("variant", "")
			var comp_level = other_companion.get("level", 1)
			loot_summary.append("[color=#00FF00]%s %s (Lv.%d)[/color]" % [comp_variant, comp_name, comp_level])

	# Transfer egg
	var egg = contents.get("egg")
	if egg != null and egg is Dictionary and not egg.is_empty():
		var _mbox_egg_cap = persistence.get_egg_capacity(peers[peer_id].account_id) if peers.has(peer_id) else Character.MAX_INCUBATING_EGGS
		if character.incubating_eggs.size() < _mbox_egg_cap:
			character.incubating_eggs.append(egg)
			var egg_type = egg.get("monster_type", "Unknown")
			loot_summary.append("[color=#FFD700]%s Egg[/color]" % egg_type)
		else:
			var egg_type = egg.get("monster_type", "Unknown")
			warnings.append("[color=#FF6666]★ %s Egg found but eggs full! (%d/%d) ★[/color]" % [egg_type, character.incubating_eggs.size(), _mbox_egg_cap])

	# Transfer monster gems
	var corpse_gems = contents.get("monster_gems", contents.get("gems", 0))
	if corpse_gems > 0:
		character.add_crafting_material("monster_gem", corpse_gems)
		loot_summary.append("[color=#00BFFF]%d Monster Gem%s[/color]" % [corpse_gems, "s" if corpse_gems > 1 else ""])

	# Remove corpse from persistence
	persistence.remove_corpse(corpse_id)

	# Build loot message
	var corpse_name = corpse.get("character_name", "Unknown")
	var loot_message = "[color=#FF6666]═══════ LOOTED CORPSE ═══════[/color]\n"
	loot_message += "[color=#AAAAAA]The remains of [/color][color=#FFFFFF]%s[/color]\n\n" % corpse_name

	if not loot_summary.is_empty():
		loot_message += "[color=#00FF00]You obtained:[/color]\n"
		for item_desc in loot_summary:
			loot_message += "  • %s\n" % item_desc
	else:
		loot_message += "[color=#808080]The corpse was empty.[/color]\n"

	for warning in warnings:
		loot_message += "\n%s" % warning

	# Send loot result to player
	send_to_peer(peer_id, {
		"type": "corpse_looted",
		"message": loot_message,
		"corpse_name": corpse_name
	})

	# Save character and send updates
	send_character_update(peer_id)
	save_character(peer_id)
	send_location_update(peer_id)

	# Notify nearby players that corpse is gone
	_broadcast_corpse_despawn(corpse)

# ===== GM / ADMIN COMMANDS =====

func _is_admin(peer_id: int) -> bool:
	"""Check if a peer has admin privileges"""
	return peers.has(peer_id) and peers[peer_id].get("is_admin", false)

func _gm_deny(peer_id: int):
	"""Send admin access denied message"""
	send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000]Admin access required.[/color]"})

func handle_gm_setlevel(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var target_level = clampi(int(message.get("level", 1)), 1, 99999)
	var ch = characters[peer_id]
	# Reset to base stats and re-level
	var base_stats = ch.get_starting_stats_for_class(ch.class_type)
	ch.strength = base_stats.strength
	ch.constitution = base_stats.constitution
	ch.dexterity = base_stats.dexterity
	ch.intelligence = base_stats.intelligence
	ch.wisdom = base_stats.wisdom
	ch.wits = base_stats.wits
	ch.level = 1
	# Level up to target
	for i in range(target_level - 1):
		ch.level_up()
	ch.calculate_derived_stats()
	ch.current_hp = ch.get_total_max_hp()
	ch.current_mana = ch.get_total_max_mana()
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_energy = ch.get_total_max_energy()
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Level set to %d[/color]" % ch.level})

func handle_gm_setvalor(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not peers.has(peer_id):
		return
	var amount = clampi(int(message.get("amount", 0)), 0, 99999999)
	var account_id = peers[peer_id].account_id
	persistence.set_valor(account_id, amount)
	send_character_update(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Valor set to %d[/color]" % amount})

func handle_gm_setmonstergems(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var amount = clampi(int(message.get("amount", 0)), 0, 999)
	characters[peer_id].crafting_materials["monster_gem"] = amount
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Monster Gems set to %d[/color]" % amount})

func handle_gm_setxp(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var amount = clampi(int(message.get("amount", 0)), 0, 999999999)
	characters[peer_id].experience = amount
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] XP set to %d[/color]" % amount})

func handle_gm_godmode(peer_id: int):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	# Toggle godmode using meta (not a defined property on Character)
	var current = ch.get_meta("gm_godmode", false)
	ch.set_meta("gm_godmode", not current)
	var enabled = ch.get_meta("gm_godmode", false)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] God Mode %s[/color]" % ("ENABLED" if enabled else "DISABLED")})

func handle_gm_setbp(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not peers.has(peer_id):
		return
	var amount = clampi(int(message.get("amount", 0)), 0, 99999999)
	var account_id = peers[peer_id].account_id
	var house = persistence.get_house(account_id)
	house["baddie_points"] = amount
	persistence.save_house(account_id, house)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Baddie Points set to %d[/color]" % amount})

func handle_gm_giveitem(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	var tier = clampi(int(message.get("tier", 5)), 1, 9)
	var slot = message.get("slot", "")
	# Determine item level from tier
	var tier_levels = {1: 3, 2: 10, 3: 25, 4: 40, 5: 60, 6: 100, 7: 300, 8: 1000, 9: 3000}
	var item_level = tier_levels.get(tier, 50)
	# Generate item based on slot preference
	var item: Dictionary
	var drop_table_id = "tier%d" % tier
	if slot == "weapon":
		item = drop_tables.generate_weapon(item_level)
	elif slot == "shield":
		item = drop_tables.generate_shield(item_level)
	else:
		# Roll from tier drop table with guaranteed drop
		var table = drop_tables.get_drop_table(drop_table_id)
		if table.is_empty():
			item = drop_tables.generate_fallback_item("weapon", item_level)
		else:
			var drop_entry = drop_tables._roll_item_from_table(table)
			if drop_entry.is_empty():
				item = drop_tables.generate_fallback_item("weapon", item_level)
			else:
				item = drop_tables._generate_item(drop_entry, item_level)
	if item.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Failed to generate item.[/color]"})
		return
	ch.inventory.append(item)
	send_character_update(peer_id)
	save_character(peer_id)
	var item_name = item.get("name", "Unknown Item")
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Received: %s (Tier %d)[/color]" % [item_name, tier]})

func handle_gm_giveegg(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	var monster_type = message.get("monster_type", "")
	# If no type specified, pick a random one from COMPANION_DATA
	if monster_type.is_empty():
		var all_types = DropTables.COMPANION_DATA.keys()
		monster_type = all_types[randi() % all_types.size()]
	var egg = drop_tables.get_egg_for_monster(monster_type)
	if egg.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Unknown monster type: %s[/color]" % monster_type})
		return
	ch.incubating_eggs.append(egg)
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Received egg: %s (%s)[/color]" % [egg.get("name", "?"), egg.get("variant", "?")]})

func handle_gm_givecompanion(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	var monster_type = message.get("monster_type", "")
	if monster_type.is_empty():
		var all_types = DropTables.COMPANION_DATA.keys()
		monster_type = all_types[randi() % all_types.size()]
	var companion_data = DropTables.COMPANION_DATA.get(monster_type, {})
	if companion_data.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Unknown monster type: %s[/color]" % monster_type})
		return
	var tier = int(message.get("tier", companion_data.get("tier", 1)))
	var variant = drop_tables._roll_egg_variant()
	var companion = {
		"id": "gm_" + monster_type.to_lower().replace(" ", "_") + "_" + str(randi()),
		"monster_type": monster_type,
		"name": companion_data.get("companion_name", monster_type + " Companion"),
		"tier": tier,
		"sub_tier": 1,
		"level": 1,
		"xp": 0,
		"bonuses": companion_data.get("bonuses", {}).duplicate(),
		"battles_fought": 0,
		"variant": variant.get("name", "Normal"),
		"variant_color": variant.get("color", "#FFFFFF"),
		"variant_color2": variant.get("color2", ""),
		"variant_pattern": variant.get("pattern", "solid"),
		"variant_rarity": variant.get("rarity", 10),
		"obtained_at": int(Time.get_unix_time_from_system())
	}
	ch.collected_companions.append(companion)
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Received companion: %s (Tier %d, %s)[/color]" % [companion.name, tier, variant.get("name", "Normal")]})

func handle_gm_spawnmonster(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	# Don't allow if already in combat
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Already in combat![/color]"})
		return
	var monster_name = message.get("monster_name", "")
	var monster_level = int(message.get("level", ch.level))
	if monster_name.is_empty():
		# Spawn random monster at character level
		var monster = monster_db.generate_monster(monster_level, monster_level)
		_start_gm_combat(peer_id, monster)
	else:
		var monster = monster_db.generate_monster_by_name(monster_name, monster_level)
		_start_gm_combat(peer_id, monster)

func _start_gm_combat(peer_id: int, monster: Dictionary):
	"""Start combat with a GM-spawned monster"""
	var character = characters[peer_id]
	var result = combat_mgr.start_combat(peer_id, character, monster)
	if result.success:
		var monster_name = result.combat_state.get("monster_name", "")
		var combat_bg_color = combat_mgr.get_monster_combat_bg_color(monster_name)
		var full_message = "[color=#00FF00][GM] Spawned encounter![/color]\n\n" + result.message
		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": full_message,
			"combat_state": result.combat_state,
			"combat_bg_color": combat_bg_color,
			"use_client_art": true,
			"extra_combat_text": result.get("extra_combat_text", "")
		})
		forward_combat_start_to_watchers(peer_id, full_message, monster_name, combat_bg_color)
	else:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Failed to start combat.[/color]"})

func handle_gm_givemats(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var material_id = message.get("material_id", "")
	var amount = clampi(int(message.get("amount", 10)), 1, 9999)
	if material_id.is_empty() or not CraftingDatabase.MATERIALS.has(material_id):
		# List some valid material IDs
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Unknown material: '%s'. Examples: copper_ore, iron_ore, small_fish, healing_herb, common_wood[/color]" % material_id})
		return
	var added = characters[peer_id].add_crafting_material(material_id, amount)
	var new_total = characters[peer_id].crafting_materials.get(material_id, 0)
	var mat_name = CraftingDatabase.MATERIALS[material_id].get("name", material_id)
	send_character_update(peer_id)
	save_character(peer_id)
	var msg = "[color=#00FF00][GM] Received %d %s (total: %d)[/color]" % [added, mat_name, new_total]
	if added < amount:
		msg += "\n[color=#FFAA00]Pouch full! %d %s lost (cap: 999)[/color]" % [amount - added, mat_name]
	send_to_peer(peer_id, {"type": "text", "message": msg})

func handle_gm_giveall(peer_id: int):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	# Valor and materials
	persistence.add_valor(peers[peer_id].account_id, 5000)
	ch.add_crafting_material("monster_gem", 100)
	# Give a set of materials
	var mats_to_give = {"copper_ore": 50, "iron_ore": 50, "steel_ore": 30, "mithril_ore": 20,
		"small_fish": 30, "medium_fish": 20, "healing_herb": 30, "mana_blossom": 20,
		"common_wood": 30, "oak_wood": 20, "ragged_leather": 30, "leather_scraps": 20,
		"magic_dust": 20}
	for mat_id in mats_to_give:
		ch.add_crafting_material(mat_id, mats_to_give[mat_id])
	# Give some items from various tiers
	var tiers_to_give = [3, 4, 5, 6]
	for tier in tiers_to_give:
		var tier_levels = {3: 25, 4: 40, 5: 60, 6: 100}
		var item_level = tier_levels.get(tier, 50)
		var table = drop_tables.get_drop_table("tier%d" % tier)
		if not table.is_empty():
			var drop_entry = drop_tables._roll_item_from_table(table)
			if not drop_entry.is_empty():
				var item = drop_tables._generate_item(drop_entry, item_level)
				if not item.is_empty():
					ch.inventory.append(item)
	# Give a random egg
	var all_types = DropTables.COMPANION_DATA.keys()
	var random_type = all_types[randi() % all_types.size()]
	var egg = drop_tables.get_egg_for_monster(random_type)
	if not egg.is_empty():
		ch.incubating_eggs.append(egg)
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Starter kit received: 5k valor, 100 gems, 5k ESS, materials, items, and an egg![/color]"})

func handle_gm_teleport(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	var target_x = int(message.get("x", 0))
	var target_y = int(message.get("y", 0))
	ch.x = target_x
	ch.y = target_y
	# Exit dungeon if in one
	if ch.in_dungeon:
		ch.exit_dungeon()
	send_character_update(peer_id)
	send_location_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Teleported to (%d, %d)[/color]" % [target_x, target_y]})

func handle_gm_completequest(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	var quest_index = int(message.get("index", -1))
	if ch.active_quests.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] No active quests.[/color]"})
		return
	if quest_index >= 0 and quest_index < ch.active_quests.size():
		# Complete specific quest
		var quest = ch.active_quests[quest_index]
		quest["progress"] = quest.get("target", 1)
		quest["completed"] = true
		send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Quest '%s' marked complete. Turn in at a Trading Post.[/color]" % quest.get("name", "?")})
	else:
		# Complete all active quests
		for quest in ch.active_quests:
			quest["progress"] = quest.get("target", 1)
			quest["completed"] = true
		send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] All %d quests marked complete. Turn in at a Trading Post.[/color]" % ch.active_quests.size()})
	send_character_update(peer_id)
	save_character(peer_id)

func handle_gm_resetquests(peer_id: int):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	var count = ch.active_quests.size()
	ch.active_quests.clear()
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Cleared %d active quests.[/color]" % count})

func handle_gm_heal(peer_id: int):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	ch.current_hp = ch.get_total_max_hp()
	ch.current_mana = ch.get_total_max_mana()
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_energy = ch.get_total_max_energy()
	# Clear debuffs
	ch.poison_active = false
	ch.blind_active = false
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Fully healed! HP, mana, stamina, and energy restored.[/color]"})

func handle_gm_broadcast(peer_id: int, message: Dictionary):
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	var text = message.get("message", "")
	if text.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Usage: /broadcast <message>[/color]"})
		return
	_send_broadcast(text)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Broadcast sent.[/color]"})

func handle_gm_giveconsumable(peer_id: int, message: Dictionary):
	"""Give a specific consumable item by type name"""
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var ch = characters[peer_id]
	var item_type = message.get("item_type", "")
	var tier = clampi(int(message.get("tier", 5)), 1, 9)

	if item_type.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Usage: /giveconsumable <type> [tier][/color]"})
		return

	# Shorthand name mapping for convenience
	var shorthands = {
		"potion": "health_potion", "health": "health_potion",
		"mana": "mana_potion", "stamina": "stamina_potion", "energy": "energy_potion",
		"elixir": "elixir_minor", "scroll": "scroll_forcefield",
		"home": "home_stone_supplies", "tome": "tome_strength",
		"rage": "scroll_rage", "haste": "scroll_haste",
		"forcefield": "scroll_forcefield", "precision": "scroll_precision",
		"vampirism": "scroll_vampirism", "thorns": "scroll_thorns",
		"weakness": "scroll_weakness", "vulnerability": "scroll_vulnerability",
		"slow": "scroll_slow", "doom": "scroll_doom",
		"resurrect": "scroll_resurrect_lesser", "timestop": "scroll_time_stop",
		"bane": "potion_dragon_bane",
	}
	if shorthands.has(item_type):
		item_type = shorthands[item_type]

	# Generate the consumable using drop_tables
	var tier_levels = {1: 3, 2: 10, 3: 25, 4: 40, 5: 60, 6: 100, 7: 300, 8: 1000, 9: 3000}
	var item_level = tier_levels.get(tier, 60)
	var drop_entry = {"item_type": item_type, "rarity": "common"}
	var item = drop_tables._generate_item(drop_entry, item_level)

	if item.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Failed to generate consumable '%s'.[/color]" % item_type})
		return

	ch.add_item(item)
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Received: %s (Tier %d)[/color]" % [item.get("name", item_type), tier]})

func handle_gm_spawnwish(peer_id: int):
	"""Spawn a weak monster with guaranteed wish granter ability"""
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	if combat_mgr.is_in_combat(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Already in combat![/color]"})
		return

	var ch = characters[peer_id]
	# Generate a weak monster with wish_granter ability
	var monster = monster_db.generate_monster(ch.level, ch.level)
	monster["abilities"] = ["wish_granter"]
	monster["current_hp"] = 1  # 1 HP so it dies in one hit
	monster["max_hp"] = 1
	monster["name"] = "Wish Granter (GM)"

	var result = combat_mgr.start_combat(peer_id, ch, monster)
	if result.success:
		# Force the wish to be 100% guaranteed by setting a flag on the combat
		if combat_mgr.active_combats.has(peer_id):
			combat_mgr.active_combats[peer_id]["gm_wish_guaranteed"] = true
		var monster_name = result.combat_state.get("monster_name", "")
		var combat_bg_color = combat_mgr.get_monster_combat_bg_color(monster_name)
		var full_message = "[color=#00FF00][GM] Spawned Wish Granter! Kill it for a guaranteed wish.[/color]\n\n" + result.message
		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": full_message,
			"combat_state": result.combat_state,
			"combat_bg_color": combat_bg_color,
			"use_client_art": true,
			"extra_combat_text": result.get("extra_combat_text", "")
		})
		forward_combat_start_to_watchers(peer_id, full_message, monster_name, combat_bg_color)
	else:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Failed to start combat.[/color]"})

# ===== WIPE COMMANDS =====

var pending_wipe_confirmations: Dictionary = {}  # peer_id -> {type, step}

const FULLWIPE_PASSPHRASES = ["DESTROY", "EVERYTHING", "CONFIRM"]
const MAPWIPE_PASSPHRASES = ["RESET", "WORLD"]

func handle_gm_fullwipe(peer_id: int, message: Dictionary):
	"""Full wipe: Delete everything. Requires 3 confirmation passphrases."""
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	var passphrase = message.get("passphrase", "")
	if not pending_wipe_confirmations.has(peer_id) or pending_wipe_confirmations[peer_id].get("type", "") != "full":
		pending_wipe_confirmations[peer_id] = {"type": "full", "step": 0}
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][WIPE] Full wipe will delete ALL data: characters, houses, world, market, leaderboards.[/color]\n[color=#FFD700]Type DESTROY to confirm step 1/3.[/color]"})
		return
	var state = pending_wipe_confirmations[peer_id]
	var expected = FULLWIPE_PASSPHRASES[state.step]
	if passphrase != expected:
		pending_wipe_confirmations.erase(peer_id)
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][WIPE] Incorrect passphrase. Wipe cancelled.[/color]"})
		return
	state.step += 1
	if state.step < FULLWIPE_PASSPHRASES.size():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][WIPE] Step %d/%d confirmed. Type %s to continue.[/color]" % [state.step, FULLWIPE_PASSPHRASES.size(), FULLWIPE_PASSPHRASES[state.step]]})
		return
	pending_wipe_confirmations.erase(peer_id)
	log_message("[WIPE] Full wipe initiated by admin (peer %d)" % peer_id)
	_execute_full_wipe(peer_id)

func handle_gm_mapwipe(peer_id: int, message: Dictionary):
	"""Map-only wipe: Delete world chunks, keep characters and houses."""
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	var passphrase = message.get("passphrase", "")
	if not pending_wipe_confirmations.has(peer_id) or pending_wipe_confirmations[peer_id].get("type", "") != "map":
		pending_wipe_confirmations[peer_id] = {"type": "map", "step": 0}
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF8800][WIPE] Map wipe will delete: world chunks, guards, player posts, market.\n[color=#00FF00]Preserved:[/color] Characters, Sanctuary, inventories, companions.[/color]\n[color=#FFD700]Type RESET to confirm step 1/2.[/color]"})
		return
	var state = pending_wipe_confirmations[peer_id]
	var expected = MAPWIPE_PASSPHRASES[state.step]
	if passphrase != expected:
		pending_wipe_confirmations.erase(peer_id)
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][WIPE] Incorrect passphrase. Wipe cancelled.[/color]"})
		return
	state.step += 1
	if state.step < MAPWIPE_PASSPHRASES.size():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF8800][WIPE] Step %d/%d confirmed. Type %s to continue.[/color]" % [state.step, MAPWIPE_PASSPHRASES.size(), MAPWIPE_PASSPHRASES[state.step]]})
		return
	pending_wipe_confirmations.erase(peer_id)
	log_message("[WIPE] Map wipe initiated by admin (peer %d)" % peer_id)
	_execute_map_wipe(peer_id)

func handle_gm_setjob(peer_id: int, message: Dictionary):
	"""Set a job's level and XP for testing."""
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var job_name = message.get("job_name", "")
	var level = clampi(int(message.get("level", 1)), 1, character.JOB_LEVEL_CAP)

	if not character.job_levels.has(job_name):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Unknown job: %s. Valid: mining, logging, foraging, soldier, fishing, blacksmith, builder, alchemist, scribe, enchanter[/color]" % job_name})
		return

	character.job_levels[job_name] = level
	character.job_xp[job_name] = 0
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Set %s job to level %d.[/color]" % [job_name, level]})

func handle_gm_givetool(peer_id: int, message: Dictionary):
	"""Give a gathering tool to the player."""
	if not _is_admin(peer_id):
		_gm_deny(peer_id)
		return
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var subtype = message.get("subtype", "")
	var tier = clampi(int(message.get("tier", 1)), 1, 5)
	var valid_subtypes = ["pickaxe", "axe", "sickle", "rod"]
	if subtype not in valid_subtypes:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Invalid subtype: %s. Valid: pickaxe, axe, sickle, rod[/color]" % subtype})
		return
	var tool_item = DropTables.generate_tool(subtype, tier)
	if tool_item.is_empty():
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF0000][GM] Failed to generate tool.[/color]"})
		return
	character.inventory.append(tool_item)
	send_character_update(peer_id)
	save_character(peer_id)
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00FF00][GM] Gave %s (T%d, %d durability).[/color]" % [tool_item.name, tier, tool_item.durability]})

func _execute_full_wipe(admin_peer_id: int):
	"""Execute full wipe — delete everything."""
	for pid in peers.keys():
		send_to_peer(pid, {"type": "text", "message": "[color=#FF0000][SERVER] Full wipe in progress. All data will be deleted.[/color]"})
	if chunk_manager:
		chunk_manager.wipe_all_chunks()
		var npc_posts = NpcPostDatabaseScript.generate_posts(chunk_manager.world_seed)
		chunk_manager.save_npc_posts(npc_posts)
		for post in npc_posts:
			NpcPostDatabaseScript.stamp_post_into_chunks(post, chunk_manager)
		chunk_manager.save_dirty_chunks()
	var char_dir = DirAccess.open("user://data/characters/")
	if char_dir:
		char_dir.list_dir_begin()
		var fname = char_dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				char_dir.remove(fname)
			fname = char_dir.get_next()
		char_dir.list_dir_end()
	for filepath in ["user://data/accounts.json", "user://data/accounts.json.bak",
		"user://data/leaderboard.json", "user://data/leaderboard.json.bak",
		"user://data/monster_kills_leaderboard.json", "user://data/monster_kills_leaderboard.json.bak",
		"user://data/realm_state.json", "user://data/realm_state.json.bak",
		"user://data/corpses.json", "user://data/corpses.json.bak",
		"user://data/houses.json", "user://data/houses.json.bak",
		"user://data/player_posts.json", "user://data/player_posts.json.bak"]:
		if FileAccess.file_exists(filepath):
			DirAccess.remove_absolute(filepath)
	characters.clear()
	active_trades.clear()
	pending_trade_requests.clear()
	active_bounties.clear()
	active_dungeons.clear()
	player_enclosures.clear()
	player_post_names.clear()
	enclosure_tile_lookup.clear()
	persistence.clear_all_market_data()
	persistence.clear_all_valor()
	log_message("[WIPE] Full wipe complete. Server restart recommended.")
	send_to_peer(admin_peer_id, {"type": "text", "message": "[color=#00FF00][WIPE] Full wipe complete. Restart the server.[/color]"})

func _execute_map_wipe(admin_peer_id: int):
	"""Execute map-only wipe — keep characters and houses."""
	for pid in peers.keys():
		send_to_peer(pid, {"type": "text", "message": "[color=#FF8800][SERVER] Map wipe in progress. The world is being reset.[/color]"})
	if chunk_manager:
		chunk_manager.wipe_all_chunks()
		var npc_posts = NpcPostDatabaseScript.generate_posts(chunk_manager.world_seed)
		chunk_manager.save_npc_posts(npc_posts)
		for post in npc_posts:
			NpcPostDatabaseScript.stamp_post_into_chunks(post, chunk_manager)
		chunk_manager.save_dirty_chunks()
		# Clear all player-built tiles (they don't survive map wipe)
		persistence.clear_all_player_tiles()
		persistence.clear_all_player_posts()
		player_enclosures.clear()
		player_post_names.clear()
		enclosure_tile_lookup.clear()
	else:
		depleted_nodes.clear()
	active_bounties.clear()
	active_dungeons.clear()
	dungeon_floors.clear()
	dungeon_floor_rooms.clear()
	dungeon_monsters.clear()
	player_dungeon_instances.clear()
	persistence.clear_all_market_data()
	if FileAccess.file_exists("user://data/corpses.json"):
		DirAccess.remove_absolute("user://data/corpses.json")
	_check_dungeon_spawns()
	for pid in characters:
		send_location_update(pid)
	log_message("[WIPE] Map wipe complete. World regenerated from seed.")
	send_to_peer(admin_peer_id, {"type": "text", "message": "[color=#00FF00][WIPE] Map wipe complete. World regenerated from seed.[/color]"})

# ===== PARTY QUEST SYNC =====

func _sync_party_quest_turn_in(leader_pid: int, quest_id: String, quest: Dictionary):
	"""Auto-turn-in a quest for party members who also have it completed."""
	if not active_parties.has(leader_pid):
		return
	var party = active_parties[leader_pid]

	for pid in party.members:
		if pid == leader_pid:
			continue
		if not characters.has(pid):
			continue
		var member = characters[pid]

		# Check if member has this quest AND it's complete
		if not quest_mgr.is_quest_complete(member, quest_id):
			continue

		var old_level = member.level
		var turn_in_result = quest_mgr.turn_in_quest(member, quest_id)
		if not turn_in_result.success:
			continue

		var unlocked = []
		if turn_in_result.leveled_up:
			unlocked = member.get_newly_unlocked_abilities(old_level, turn_in_result.new_level)

		send_to_peer(pid, {
			"type": "quest_turned_in",
			"quest_id": quest_id,
			"quest_name": quest.get("name", "Quest"),
			"message": "[color=#00FFFF](Party) [/color]" + turn_in_result.message,
			"rewards": turn_in_result.rewards,
			"leveled_up": turn_in_result.leveled_up,
			"new_level": turn_in_result.new_level,
			"unlocked_abilities": unlocked
		})
		check_elder_auto_grant(pid)
		send_character_update(pid)
		save_character(pid)

# ===== PARTY SYSTEM =====

func _is_non_party_player_at(x: int, y: int, peer_id: int) -> bool:
	"""Check if any non-party player is at the given coordinates."""
	var my_party_leader = party_membership.get(peer_id, -1)
	for other_peer_id in characters.keys():
		if other_peer_id == peer_id:
			continue
		var other_char = characters[other_peer_id]
		if other_char.x == x and other_char.y == y:
			# If both in same party, don't block
			if my_party_leader != -1 and party_membership.get(other_peer_id, -1) == my_party_leader:
				continue
			return true
	return false

func _get_player_at(x: int, y: int, exclude_peer_id: int = -1) -> int:
	"""Get the peer_id of a player at given coordinates, or -1 if none."""
	for other_peer_id in characters.keys():
		if other_peer_id == exclude_peer_id:
			continue
		var other_char = characters[other_peer_id]
		if other_char.x == x and other_char.y == y:
			return other_peer_id
	return -1

func _is_party_leader(peer_id: int) -> bool:
	return active_parties.has(peer_id)

func _get_party_size(peer_id: int) -> int:
	var leader_id = party_membership.get(peer_id, peer_id)
	if active_parties.has(leader_id):
		return active_parties[leader_id].members.size()
	return 0

func _get_party_members(peer_id: int) -> Array:
	"""Get all party member peer_ids for the party this peer belongs to."""
	var leader_id = party_membership.get(peer_id, -1)
	if leader_id == -1:
		return []
	if active_parties.has(leader_id):
		return active_parties[leader_id].members.duplicate()
	return []

func _build_party_member_info(peer_id: int) -> Dictionary:
	"""Build member info dict for a party member."""
	if not characters.has(peer_id):
		return {}
	var ch = characters[peer_id]
	return {
		"name": ch.name,
		"level": ch.level,
		"class_type": ch.class_type,
		"is_leader": _is_party_leader(peer_id)
	}

func _send_party_update(leader_id: int):
	"""Send full party state to all members."""
	if not active_parties.has(leader_id):
		return
	var party = active_parties[leader_id]
	var members_info = []
	for pid in party.members:
		members_info.append(_build_party_member_info(pid))
	var update_msg = {
		"type": "party_update",
		"leader": characters[leader_id].name if characters.has(leader_id) else "",
		"members": members_info
	}
	for pid in party.members:
		send_to_peer(pid, update_msg)

func _disband_party(leader_id: int, reason: String = "Party disbanded."):
	"""Disband a party and notify all members."""
	if not active_parties.has(leader_id):
		return
	var party = active_parties[leader_id]
	var disband_msg = {"type": "party_disbanded", "reason": reason}
	for pid in party.members:
		send_to_peer(pid, disband_msg)
		party_membership.erase(pid)
	active_parties.erase(leader_id)
	log_message("Party led by peer %d disbanded: %s" % [leader_id, reason])

func _remove_party_member(leader_id: int, member_peer_id: int):
	"""Remove a member from a party. Auto-disbands if only 1 left."""
	if not active_parties.has(leader_id):
		return
	var party = active_parties[leader_id]
	party.members.erase(member_peer_id)
	party_membership.erase(member_peer_id)
	if party.members.size() <= 1:
		_disband_party(leader_id, "Not enough members to maintain the party.")
	else:
		_send_party_update(leader_id)

func _find_adjacent_empty(x: int, y: int, exclude_peers: Array) -> Vector2i:
	"""Find an empty adjacent tile near the given position."""
	var offsets = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
					Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for off in offsets:
		var tx = x + off.x
		var ty = y + off.y
		# Check if tile blocks movement via chunk_manager
		if chunk_manager:
			var tile = chunk_manager.get_tile(tx, ty)
			if tile.get("blocks_move", false):
				continue
		var occupied = false
		for other_pid in characters.keys():
			if other_pid in exclude_peers:
				continue
			if characters[other_pid].x == tx and characters[other_pid].y == ty:
				occupied = true
				break
		if not occupied:
			return Vector2i(tx, ty)
	return Vector2i(x, y)  # Fallback: same position

func handle_party_invite(peer_id: int, message: Dictionary):
	"""Handle a party invite request from a player."""
	if not characters.has(peer_id):
		return
	var character = characters[peer_id]
	var target_name = message.get("target", "")
	if target_name == "":
		return

	# Anti-spam cooldown
	var now = Time.get_ticks_msec()
	if party_invite_cooldowns.has(peer_id) and now - party_invite_cooldowns[peer_id] < PARTY_INVITE_COOLDOWN_MS:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Please wait before sending another party invite.[/color]"})
		return
	party_invite_cooldowns[peer_id] = now

	# Validate inviter state
	if combat_mgr.is_in_combat(peer_id) or character.in_dungeon:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]You can't invite while in combat or a dungeon.[/color]"})
		return
	# If in a party, must be leader with room
	if party_membership.has(peer_id):
		if not _is_party_leader(peer_id):
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Only the party leader can invite new members.[/color]"})
			return
		if _get_party_size(peer_id) >= PARTY_MAX_SIZE:
			send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Party is full (%d/%d members).[/color]" % [PARTY_MAX_SIZE, PARTY_MAX_SIZE]})
			return

	# Find target player
	var target_peer_id = -1
	for other_pid in characters.keys():
		if characters[other_pid].name.to_lower() == target_name.to_lower():
			target_peer_id = other_pid
			target_name = characters[other_pid].name
			break
	if target_peer_id == -1:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]%s is not online.[/color]" % target_name})
		return
	if target_peer_id == peer_id:
		return

	# Validate target state
	if party_membership.has(target_peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]%s is already in a party.[/color]" % target_name})
		return
	if combat_mgr.is_in_combat(target_peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]%s is in combat.[/color]" % target_name})
		return
	if characters[target_peer_id].in_dungeon:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]%s is in a dungeon.[/color]" % target_name})
		return
	# Check for existing pending invite to this target
	if pending_party_invites.has(target_peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]%s already has a pending party invite.[/color]" % target_name})
		return

	# Store pending invite and notify both players
	pending_party_invites[target_peer_id] = {"from_peer_id": peer_id, "timestamp": now}
	send_to_peer(target_peer_id, {
		"type": "party_invite_received",
		"from_name": character.name,
		"from_level": character.level,
		"from_class": character.class_type
	})
	send_to_peer(peer_id, {"type": "text", "message": "[color=#00BFFF]Party invite sent to %s.[/color]" % target_name})

func handle_party_invite_response(peer_id: int, message: Dictionary):
	"""Handle accept/decline of a party invite."""
	if not pending_party_invites.has(peer_id):
		return
	var invite = pending_party_invites[peer_id]
	pending_party_invites.erase(peer_id)
	var accept = message.get("accept", false)
	var inviter_id = invite.from_peer_id

	if not characters.has(inviter_id) or not characters.has(peer_id):
		return

	if not accept:
		send_to_peer(inviter_id, {"type": "text", "message": "[color=#FF4444]%s declined your party invite.[/color]" % characters[peer_id].name})
		return

	# Accepted — check if inviter is already in a party
	if party_membership.has(inviter_id) and _is_party_leader(inviter_id):
		# Joining existing party — skip lead/follow, join as follower
		_add_member_to_party(inviter_id, peer_id)
	else:
		# New party — ask inviter for Lead/Follow choice
		send_to_peer(inviter_id, {
			"type": "party_lead_choice",
			"partner_name": characters[peer_id].name,
			"partner_peer_id": peer_id
		})

func handle_party_lead_choice_response(peer_id: int, message: Dictionary):
	"""Handle the Lead/Follow choice when forming a new party."""
	if not characters.has(peer_id):
		return
	var choice = message.get("choice", "lead")
	var partner_id = int(message.get("partner_peer_id", -1))
	if not characters.has(partner_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Partner is no longer available.[/color]"})
		return
	# Verify partner isn't already in a party (race condition check)
	if party_membership.has(partner_id) or party_membership.has(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]One of you already joined a party.[/color]"})
		return

	var leader_id: int
	var follower_id: int
	if choice == "follow":
		leader_id = partner_id
		follower_id = peer_id
	else:
		leader_id = peer_id
		follower_id = partner_id

	# Create the party
	active_parties[leader_id] = {
		"leader": leader_id,
		"members": [leader_id, follower_id],
		"formed_at": Time.get_ticks_msec()
	}
	party_membership[leader_id] = leader_id
	party_membership[follower_id] = leader_id

	# Teleport follower to adjacent tile near leader
	var leader_char = characters[leader_id]
	var adj = _find_adjacent_empty(leader_char.x, leader_char.y, [leader_id, follower_id])
	characters[follower_id].x = adj.x
	characters[follower_id].y = adj.y

	# Send party_formed to both
	var members_info = []
	for pid in [leader_id, follower_id]:
		members_info.append(_build_party_member_info(pid))

	var formed_msg = {
		"type": "party_formed",
		"leader": characters[leader_id].name,
		"members": members_info
	}
	send_to_peer(leader_id, formed_msg)
	send_to_peer(follower_id, formed_msg)

	# Send location updates so both see each other
	send_location_update(leader_id)
	send_location_update(follower_id)
	send_character_update(follower_id)

	log_message("Party formed: %s (leader) + %s" % [characters[leader_id].name, characters[follower_id].name])

func _add_member_to_party(leader_id: int, new_member_id: int):
	"""Add a new member to an existing party."""
	if not active_parties.has(leader_id):
		return
	var party = active_parties[leader_id]
	if party.members.size() >= PARTY_MAX_SIZE:
		send_to_peer(new_member_id, {"type": "text", "message": "[color=#FF4444]Party is full.[/color]"})
		return

	party.members.append(new_member_id)
	party_membership[new_member_id] = leader_id

	# Teleport new member to adjacent tile near last member
	var last_member_id = party.members[party.members.size() - 2]
	var last_char = characters[last_member_id]
	var adj = _find_adjacent_empty(last_char.x, last_char.y, party.members)
	characters[new_member_id].x = adj.x
	characters[new_member_id].y = adj.y

	# Notify all members
	var new_member_info = _build_party_member_info(new_member_id)
	for pid in party.members:
		if pid != new_member_id:
			send_to_peer(pid, {
				"type": "party_member_joined",
				"member": new_member_info
			})

	# Send full party update to all (including new member)
	_send_party_update(leader_id)

	# Send location updates
	for pid in party.members:
		send_location_update(pid)
	send_character_update(new_member_id)

	log_message("Player %s joined party led by %s" % [
		characters[new_member_id].name, characters[leader_id].name])

func handle_party_disband(peer_id: int):
	"""Handle party disband request (leader only)."""
	if not _is_party_leader(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Only the party leader can disband.[/color]"})
		return
	_disband_party(peer_id, "Leader disbanded the party.")

func handle_party_leave(peer_id: int):
	"""Handle a member leaving the party."""
	if not party_membership.has(peer_id):
		return
	var leader_id = party_membership[peer_id]
	if peer_id == leader_id:
		# Leader leaving — appoint next member or disband
		var party = active_parties[leader_id]
		if party.members.size() <= 2:
			_disband_party(leader_id, "%s left the party." % characters[peer_id].name)
		else:
			# Appoint next member as leader
			var new_leader_id = -1
			for pid in party.members:
				if pid != peer_id:
					new_leader_id = pid
					break
			if new_leader_id != -1:
				_transfer_leadership(leader_id, new_leader_id)
				_remove_party_member(new_leader_id, peer_id)
				send_to_peer(peer_id, {"type": "party_disbanded", "reason": "You left the party."})
		return

	# Regular member leaving
	var char_name = characters[peer_id].name if characters.has(peer_id) else "Unknown"
	# Notify remaining members before removal
	var party = active_parties[leader_id]
	for pid in party.members:
		if pid != peer_id:
			send_to_peer(pid, {"type": "party_member_left", "name": char_name})
	send_to_peer(peer_id, {"type": "party_disbanded", "reason": "You left the party."})
	_remove_party_member(leader_id, peer_id)

func handle_party_appoint_leader(peer_id: int, message: Dictionary):
	"""Handle appointing a new party leader."""
	if not _is_party_leader(peer_id):
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]Only the party leader can appoint a new leader.[/color]"})
		return
	var target_name = message.get("target", "")
	if target_name == "":
		return

	var party = active_parties[peer_id]
	var target_pid = -1
	for pid in party.members:
		if pid != peer_id and characters.has(pid) and characters[pid].name.to_lower() == target_name.to_lower():
			target_pid = pid
			break
	if target_pid == -1:
		send_to_peer(peer_id, {"type": "text", "message": "[color=#FF4444]%s is not in your party.[/color]" % target_name})
		return

	_transfer_leadership(peer_id, target_pid)

func _transfer_leadership(old_leader_id: int, new_leader_id: int):
	"""Transfer party leadership from one member to another."""
	if not active_parties.has(old_leader_id):
		return
	var party = active_parties[old_leader_id]

	# Reorder members: new leader first
	var new_members = [new_leader_id]
	for pid in party.members:
		if pid != new_leader_id:
			new_members.append(pid)
	party.members = new_members
	party.leader = new_leader_id

	# Move party data to new leader's key
	active_parties.erase(old_leader_id)
	active_parties[new_leader_id] = party

	# Update all membership lookups
	for pid in party.members:
		party_membership[pid] = new_leader_id

	# Notify all members
	var new_leader_name = characters[new_leader_id].name if characters.has(new_leader_id) else "Unknown"
	for pid in party.members:
		send_to_peer(pid, {"type": "party_leader_changed", "new_leader": new_leader_name})
	_send_party_update(new_leader_id)

	log_message("Party leadership transferred to %s" % new_leader_name)

func _move_party_followers(leader_peer_id: int, old_leader_x: int, old_leader_y: int):
	"""Move party followers in snake formation behind the leader."""
	if not active_parties.has(leader_peer_id):
		return
	var party = active_parties[leader_peer_id]
	if party.members.size() <= 1:
		return

	# Build old positions BEFORE moving anyone (leader already moved)
	var old_positions = []
	old_positions.append(Vector2i(old_leader_x, old_leader_y))  # Leader's old position
	for i in range(1, party.members.size()):
		var follower = characters[party.members[i]]
		old_positions.append(Vector2i(follower.x, follower.y))

	# Each follower takes the position of the person ahead of them
	for i in range(1, party.members.size()):
		var follower_pid = party.members[i]
		if not characters.has(follower_pid):
			continue
		var follower = characters[follower_pid]
		# Regen for followers (same as leader gets from walking)
		var early_game_mult = _get_early_game_regen_multiplier(follower.level)
		var house_regen_mult = 1.0 + (follower.house_bonuses.get("resource_regen", 0) / 100.0)
		var hp_regen_percent = 0.01 * early_game_mult * house_regen_mult
		var regen_percent = 0.02 * early_game_mult * house_regen_mult
		follower.current_hp = min(follower.get_total_max_hp(), follower.current_hp + max(1, int(follower.get_total_max_hp() * hp_regen_percent)))
		if not follower.cloak_active:
			follower.current_mana = min(follower.get_total_max_mana(), follower.current_mana + max(1, int(follower.get_total_max_mana() * regen_percent)))
			follower.current_stamina = min(follower.get_total_max_stamina(), follower.current_stamina + max(1, int(follower.get_total_max_stamina() * regen_percent)))
			follower.current_energy = min(follower.get_total_max_energy(), follower.current_energy + max(1, int(follower.get_total_max_energy() * regen_percent)))
		# Move to previous person's old position
		follower.x = old_positions[i - 1].x
		follower.y = old_positions[i - 1].y
		# Process egg steps for followers too
		follower.process_egg_steps(1)
		# Check exploration quest progress at new position
		if world_system.is_trading_post_tile(follower.x, follower.y):
			check_exploration_quest_progress(follower_pid, follower.x, follower.y)

func _cleanup_party_combat_on_disconnect(peer_id: int):
	"""Clean up party combat state when a player disconnects during party combat."""
	if not combat_mgr.party_combat_membership.has(peer_id):
		return
	var leader_id = combat_mgr.party_combat_membership[peer_id]
	if not combat_mgr.active_party_combats.has(leader_id):
		combat_mgr.party_combat_membership.erase(peer_id)
		return
	var combat = combat_mgr.active_party_combats[leader_id]
	# Mark as dead in the combat
	if peer_id not in combat.dead_members and peer_id not in combat.fled_members:
		combat.dead_members.append(peer_id)
	# Remove from membership tracking
	combat_mgr.party_combat_membership.erase(peer_id)
	# If all members are now inactive, end combat
	if combat_mgr._all_members_inactive(combat):
		combat_mgr._end_party_combat(leader_id, false)
		# Notify remaining party members
		for pid in combat.members:
			if pid != peer_id and characters.has(pid):
				send_to_peer(pid, {
					"type": "party_combat_end",
					"messages": ["[color=#FF4444]The party has been defeated![/color]"],
					"victory": false,
					"your_death": false
				})
	else:
		# Continue combat — advance turn if it was this player's turn
		var current_pid = combat_mgr._get_current_turn_peer_id(combat)
		if current_pid == peer_id or current_pid == -1:
			# Advance to next player
			combat.current_turn_index += 1
			combat_mgr._skip_inactive_members(combat)
			if combat.current_turn_index >= combat.members.size():
				# Monster phase
				var monster_results = combat_mgr._process_party_monster_phase(combat)
				combat_mgr._check_party_deaths(combat)
				combat.round += 1
				combat.current_turn_index = 0
				combat_mgr._skip_inactive_members(combat)
				# Send update to remaining members
				var next_pid = combat_mgr._get_current_turn_peer_id(combat)
				var next_name = characters[next_pid].name if characters.has(next_pid) else ""
				var cs = combat_mgr.get_party_combat_state(leader_id)
				var msgs = monster_results.get("messages", [])
				msgs.insert(0, "[color=#FF8800]%s disconnected from combat![/color]" % (characters[peer_id].name if characters.has(peer_id) else "A party member"))
				for pid in combat.members:
					if pid != peer_id and characters.has(pid) and pid not in combat.dead_members:
						send_to_peer(pid, {
							"type": "party_combat_update",
							"messages": msgs,
							"combat_state": cs,
							"is_your_turn": (pid == next_pid),
							"current_turn_name": next_name
						})
			else:
				var next_pid = combat_mgr._get_current_turn_peer_id(combat)
				var next_name = characters[next_pid].name if characters.has(next_pid) else ""
				var cs = combat_mgr.get_party_combat_state(leader_id)
				var msgs = ["[color=#FF8800]%s disconnected from combat![/color]" % (characters[peer_id].name if characters.has(peer_id) else "A party member")]
				for pid in combat.members:
					if pid != peer_id and characters.has(pid) and pid not in combat.dead_members:
						send_to_peer(pid, {
							"type": "party_combat_update",
							"messages": msgs,
							"combat_state": cs,
							"is_your_turn": (pid == next_pid),
							"current_turn_name": next_name
						})

func _cleanup_party_on_disconnect(peer_id: int):
	"""Clean up party state when a player disconnects."""
	# First handle party combat disconnect
	_cleanup_party_combat_on_disconnect(peer_id)

	# Clean up pending invites FROM this player
	for target_pid in pending_party_invites.keys():
		if pending_party_invites[target_pid].from_peer_id == peer_id:
			pending_party_invites.erase(target_pid)
			send_to_peer(target_pid, {"type": "party_disbanded", "reason": "Inviter disconnected."})
	# Clean up pending invite TO this player
	pending_party_invites.erase(peer_id)
	party_invite_cooldowns.erase(peer_id)

	if not party_membership.has(peer_id):
		return

	var leader_id = party_membership[peer_id]
	if not active_parties.has(leader_id):
		party_membership.erase(peer_id)
		return

	var char_name = characters[peer_id].name if characters.has(peer_id) else "Unknown"

	if peer_id == leader_id:
		# Leader disconnected
		var party = active_parties[leader_id]
		if party.members.size() <= 2:
			_disband_party(leader_id, "%s disconnected." % char_name)
		else:
			# Appoint next member as leader
			var new_leader_id = -1
			for pid in party.members:
				if pid != peer_id:
					new_leader_id = pid
					break
			if new_leader_id != -1:
				_transfer_leadership(leader_id, new_leader_id)
				_remove_party_member(new_leader_id, peer_id)
			else:
				_disband_party(leader_id, "%s disconnected." % char_name)
	else:
		# Regular member disconnected
		for pid in active_parties[leader_id].members:
			if pid != peer_id:
				send_to_peer(pid, {"type": "party_member_left", "name": char_name})
		_remove_party_member(leader_id, peer_id)

# ═══════════════════════════════════════════════
# Party Combat
# ═══════════════════════════════════════════════

func _start_party_combat_encounter(leader_peer_id: int, monster: Dictionary, debuff_messages: Array):
	"""Start a party combat encounter when the party leader triggers an encounter."""
	if not active_parties.has(leader_peer_id):
		return

	var party = active_parties[leader_peer_id]
	var party_members = party.members.duplicate()

	# Build characters dict for combat manager
	var party_characters = {}
	for pid in party_members:
		if characters.has(pid):
			party_characters[pid] = characters[pid]

	# Start party combat in combat manager
	var result = combat_mgr.start_party_combat(party_members, party_characters, monster)

	if not result.get("success", false):
		# Clean up in_combat flags that may have been set before the error
		for pid in party_members:
			if characters.has(pid):
				characters[pid].in_combat = false
		send_to_peer(leader_peer_id, {"type": "text", "message": "[color=#FF4444]Failed to start party combat![/color]"})
		return

	var monster_name = monster.get("name", "Monster")
	var combat_bg_color = combat_mgr.get_monster_combat_bg_color(monster_name)
	var first_turn_pid = result.get("first_turn_peer_id", leader_peer_id)

	# Prepend debuff messages
	var start_messages = result.get("messages", [])
	if debuff_messages.size() > 0:
		start_messages = debuff_messages + start_messages

	# Get party combat state for display
	var combat_state = combat_mgr.get_party_combat_state(leader_peer_id)

	# Send party_combat_start to ALL party members
	for pid in party_members:
		var is_first_turn = (pid == first_turn_pid)
		send_to_peer(pid, {
			"type": "party_combat_start",
			"messages": start_messages,
			"monster_name": monster_name,
			"monster_level": monster.get("level", 1),
			"combat_bg_color": combat_bg_color,
			"use_client_art": true,
			"combat_state": combat_state,
			"is_your_turn": is_first_turn,
			"current_turn_name": characters[first_turn_pid].name if characters.has(first_turn_pid) else ""
		})

func _handle_party_combat_command(peer_id: int, command: String):
	"""Handle a combat command from a player in party combat."""
	var leader_id = combat_mgr.party_combat_membership.get(peer_id, -1)
	if leader_id == -1:
		return

	# Parse command string (may include args like "magic_bolt 50")
	var parts = command.to_lower().split(" ", false)
	var cmd = parts[0] if parts.size() > 0 else ""
	var arg = parts[1] if parts.size() > 1 else ""

	var result: Dictionary

	# Map command string to CombatAction or ability
	match cmd:
		"attack", "a":
			result = combat_mgr.process_party_combat_action(leader_id, peer_id, CombatManager.CombatAction.ATTACK)
		"flee", "f", "run":
			result = combat_mgr.process_party_combat_action(leader_id, peer_id, CombatManager.CombatAction.FLEE)
		"outsmart", "o":
			result = combat_mgr.process_party_combat_action(leader_id, peer_id, CombatManager.CombatAction.OUTSMART)
		_:
			# Check if it's an ability command
			if cmd in CombatManager.MAGE_ABILITY_COMMANDS or cmd in CombatManager.WARRIOR_ABILITY_COMMANDS or cmd in CombatManager.TRICKSTER_ABILITY_COMMANDS or cmd in CombatManager.UNIVERSAL_ABILITY_COMMANDS:
				result = combat_mgr.process_party_combat_ability(leader_id, peer_id, cmd, arg)
			else:
				send_to_peer(peer_id, {"type": "text", "message": "[color=#808080]Unknown combat command.[/color]"})
				return

	if not result.get("success", false):
		send_to_peer(peer_id, {"type": "text", "message": result.get("message", "Not your turn!")})
		return

	var messages = result.get("messages", [])
	var combat_ended = result.get("combat_ended", false)
	var victory = result.get("victory", false)

	# Get all party members from the combat (before it might be cleaned up)
	var party_members = []
	if combat_mgr.active_party_combats.has(leader_id):
		party_members = combat_mgr.active_party_combats[leader_id].members.duplicate()
	elif active_parties.has(leader_id):
		party_members = active_parties[leader_id].members.duplicate()

	if combat_ended:
		if victory:
			_handle_party_combat_victory(leader_id, peer_id, result, messages, party_members)
		else:
			_handle_party_combat_defeat(leader_id, messages, party_members)
	else:
		# Combat continues — send update to all members
		var next_turn_pid = result.get("next_turn_peer_id", -1)
		var next_turn_name = characters[next_turn_pid].name if characters.has(next_turn_pid) else ""
		var combat_state = combat_mgr.get_party_combat_state(leader_id)

		for pid in party_members:
			if not characters.has(pid):
				continue
			send_to_peer(pid, {
				"type": "party_combat_update",
				"messages": messages,
				"combat_state": combat_state,
				"is_your_turn": (pid == next_turn_pid),
				"current_turn_name": next_turn_name
			})

func _handle_party_combat_victory(leader_id: int, acting_peer_id: int, result: Dictionary, messages: Array, party_members: Array):
	"""Handle party combat victory — distribute rewards to all surviving members."""
	var member_rewards = result.get("member_rewards", {})
	var monster = {}
	if combat_mgr.active_party_combats.has(leader_id):
		monster = combat_mgr.active_party_combats[leader_id].monster

	var monster_name = monster.get("name", "Monster")
	var monster_level = monster.get("level", 1)
	var monster_base_name = monster.get("base_name", monster_name)

	# Process drops for each surviving member (similar to solo combat victory)
	for pid in party_members:
		if not characters.has(pid):
			continue

		var rewards = member_rewards.get(pid, {})
		var is_dead = rewards.is_empty()  # Dead members don't get rewards

		if is_dead:
			# Dead member — handle permadeath
			var combat_data = {"monster_name": monster_name, "monster_level": monster_level}
			# End their party combat state
			send_to_peer(pid, {
				"type": "party_combat_end",
				"messages": messages,
				"victory": true,
				"your_death": true
			})
			continue

		# Record monster knowledge
		characters[pid].record_monster_kill(monster_base_name, monster_level)
		characters[pid].monsters_killed += 1

		# Check quest progress
		check_kill_quest_progress(pid, monster_level, monster_name)

		# Roll for additional drops per member
		var drop_messages = []
		var drop_data = []
		var all_drops = rewards.get("drops", [])

		# Roll for companion egg
		var egg_drop = drop_tables.roll_egg_drop(monster_name, _get_monster_tier(monster_level))
		if not egg_drop.is_empty():
			all_drops.append({"type": "companion_egg", "name": egg_drop.get("name", "Mysterious Egg"), "egg_data": egg_drop, "rarity": "epic"})

		# Roll for crafting materials
		var material_drop = drop_tables.roll_crafting_material_drop(_get_monster_tier(monster_level))
		if not material_drop.is_empty():
			all_drops.append({"type": "crafting_material", "material_id": material_drop.material_id, "quantity": material_drop.quantity, "rarity": "uncommon"})

		# Roll for monster parts
		var soldier_level = characters[pid].job_levels.get("soldier", 0)
		var part_drop = drop_tables.roll_monster_part_drop(monster_name, _get_monster_tier(monster_level), soldier_level)
		if not part_drop.is_empty():
			all_drops.append({"type": "monster_part", "material_id": part_drop["id"], "material_name": part_drop["name"], "quantity": part_drop["qty"], "rarity": "common"})

		# Roll for tool drop
		var tool_drop = drop_tables.roll_tool_drop(_get_monster_tier(monster_level))
		if not tool_drop.is_empty():
			all_drops.append(tool_drop)

		# Give drops to player
		var player_level = characters[pid].level
		for item in all_drops:
			if item.get("type", "") == "companion_egg":
				var egg_data = item.get("egg_data", {})
				var _egg_cap = persistence.get_egg_capacity(peers[pid].account_id) if peers.has(pid) else Character.MAX_INCUBATING_EGGS
				var egg_result = characters[pid].add_egg(egg_data, _egg_cap)
				if egg_result.success:
					drop_messages.append("[color=#A335EE]✦ COMPANION EGG: %s[/color]" % egg_data.get("name", "Mysterious Egg"))
					drop_data.append({"rarity": "epic", "level": 1, "level_diff": 0, "is_egg": true})
				else:
					drop_messages.append("[color=#FF6666]★ %s found but eggs full! ★[/color]" % egg_data.get("name", "Egg"))
			elif item.get("type", "") == "crafting_material":
				var mat_id = item.get("material_id", "")
				var quantity = item.get("quantity", 1)
				var mat_info = CraftingDatabaseScript.get_material(mat_id)
				var mat_name = mat_info.get("name", mat_id) if not mat_info.is_empty() else mat_id
				characters[pid].add_crafting_material(mat_id, quantity)
				var qty_text = " x%d" % quantity if quantity > 1 else ""
				drop_messages.append("[color=#1EFF00]◆ MATERIAL: %s%s[/color]" % [mat_name, qty_text])
				drop_data.append({"rarity": "uncommon", "level": 1, "level_diff": 0, "is_material": true})
			elif item.get("type", "") == "monster_part":
				var mp_id = item.get("material_id", "")
				var mp_name = item.get("material_name", mp_id)
				var mp_qty = item.get("quantity", 1)
				characters[pid].add_crafting_material(mp_id, mp_qty)
				var mp_qty_text = " x%d" % mp_qty if mp_qty > 1 else ""
				drop_messages.append("[color=#FF6600]◆ PART: %s%s[/color]" % [mp_name, mp_qty_text])
				drop_data.append({"rarity": "common", "level": 1, "level_diff": 0, "is_material": true})
			elif characters[pid].can_add_item() or _try_auto_salvage(pid):
				if _should_auto_salvage_item(pid, item):
					var salvage_result = drop_tables.get_salvage_value(item)
					var p_sal_mats = salvage_result.get("materials", {})
					for p_mid in p_sal_mats:
						characters[pid].add_crafting_material(p_mid, p_sal_mats[p_mid])
					var p_sal_parts = []
					for p_mid2 in p_sal_mats:
						p_sal_parts.append("%dx %s" % [p_sal_mats[p_mid2], CraftingDatabaseScript.get_material_name(p_mid2)])
					drop_messages.append("[color=#AA66FF]Auto-salvaged %s → %s[/color]" % [item.get("name", "item"), ", ".join(p_sal_parts) if not p_sal_parts.is_empty() else "nothing"])
				else:
					characters[pid].add_item(item)
					var rarity = item.get("rarity", "common")
					var color = _get_rarity_color(rarity)
					var symbol = _get_rarity_symbol(rarity)
					var name = item.get("name", "Unknown Item")
					drop_messages.append("[color=%s]%s %s[/color]" % [color, symbol, name])
					drop_data.append({"rarity": rarity, "level": item.get("level", 1), "level_diff": item.get("level", 1) - player_level})
			else:
				drop_messages.append("[color=#FF4444]X LOST: %s[/color]" % item.get("name", "Unknown Item"))

		# Gems
		var total_gems = rewards.get("gems", 0)

		save_character(pid)

		send_to_peer(pid, {
			"type": "party_combat_end",
			"messages": messages,
			"victory": true,
			"your_death": false,
			"character": characters[pid].to_dict(),
			"flock_drops": drop_messages,
			"total_gems": total_gems,
			"drop_data": drop_data,
			"xp_earned": rewards.get("xp", 0),
			"gold_earned": 0
		})

	# End party combat (cleans up combat state)
	combat_mgr._end_party_combat(leader_id, true)

	# Handle permadeath for dead members AFTER combat cleanup
	for pid in party_members:
		if not characters.has(pid):
			continue
		if characters[pid].current_hp <= 0:
			var was_saved = _check_death_saves_in_combat(pid, characters[pid])
			if was_saved:
				send_to_peer(pid, {
					"type": "combat_end",
					"victory": false,
					"death_saved": true,
					"character": characters[pid].to_dict()
				})
				send_location_update(pid)
				save_character(pid)
			else:
				# Remove from party before permadeath
				if party_membership.has(pid):
					var pid_leader = party_membership[pid]
					_remove_party_member(pid_leader, pid)
				handle_permadeath(pid, monster_name, {"monster_name": monster_name, "monster_level": monster_level})

func _handle_party_combat_defeat(leader_id: int, messages: Array, party_members: Array):
	"""Handle party combat defeat — all members dead or fled."""
	# End party combat
	combat_mgr._end_party_combat(leader_id, false)

	for pid in party_members:
		if not characters.has(pid):
			continue

		var is_dead = characters[pid].current_hp <= 0

		if is_dead:
			var was_saved = _check_death_saves_in_combat(pid, characters[pid])
			if was_saved:
				send_to_peer(pid, {
					"type": "party_combat_end",
					"messages": messages,
					"victory": false,
					"your_death": false,
					"death_saved": true,
					"character": characters[pid].to_dict()
				})
				send_location_update(pid)
				save_character(pid)
			else:
				# Remove from party before permadeath
				if party_membership.has(pid):
					var pid_leader = party_membership[pid]
					_remove_party_member(pid_leader, pid)
				handle_permadeath(pid, "combat", {})
		else:
			# Fled or survived
			send_to_peer(pid, {
				"type": "party_combat_end",
				"messages": messages,
				"victory": false,
				"your_death": false,
				"character": characters[pid].to_dict()
			})
			save_character(pid)

func _move_party_followers_dungeon(leader_peer_id: int, old_leader_x: int, old_leader_y: int):
	"""Move party followers in snake formation within a dungeon."""
	if not active_parties.has(leader_peer_id):
		return
	var party = active_parties[leader_peer_id]
	var members = party.members

	# Build old positions BEFORE moving anyone
	var old_positions = []
	for pid in members:
		if characters.has(pid):
			old_positions.append(Vector2i(characters[pid].dungeon_x, characters[pid].dungeon_y))
		else:
			old_positions.append(Vector2i(0, 0))

	# Override leader's old position (we already moved the leader)
	old_positions[0] = Vector2i(old_leader_x, old_leader_y)

	# Move each follower to the previous person's old position
	for i in range(1, members.size()):
		var pid = members[i]
		if not characters.has(pid) or not characters[pid].in_dungeon:
			continue
		var follower = characters[pid]

		# Regen for follower (same rate as dungeon movement)
		var early_game_mult = _get_early_game_regen_multiplier(follower.level)
		var house_regen_mult = 1.0 + (follower.house_bonuses.get("resource_regen", 0) / 100.0)
		var dungeon_hp_regen_percent = 0.005 * early_game_mult * house_regen_mult
		var dungeon_regen_percent = 0.01 * early_game_mult * house_regen_mult
		follower.current_hp = min(follower.get_total_max_hp(), follower.current_hp + max(1, int(follower.get_total_max_hp() * dungeon_hp_regen_percent)))
		if not follower.cloak_active:
			follower.current_mana = min(follower.get_total_max_mana(), follower.current_mana + max(1, int(follower.get_total_max_mana() * dungeon_regen_percent)))
			follower.current_stamina = min(follower.get_total_max_stamina(), follower.current_stamina + max(1, int(follower.get_total_max_stamina() * dungeon_regen_percent)))
			follower.current_energy = min(follower.get_total_max_energy(), follower.current_energy + max(1, int(follower.get_total_max_energy() * dungeon_regen_percent)))

		follower.dungeon_x = old_positions[i - 1].x
		follower.dungeon_y = old_positions[i - 1].y

		# Egg steps
		follower.process_egg_steps(1)

		# Send dungeon state to follower
		_send_dungeon_state(pid)
