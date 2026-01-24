# server.gd
# Server with persistence, account system, and permadeath
extends Control

const PORT = 9080

# UI References
@onready var player_count_label = $VBox/StatusRow/PlayerCountLabel
@onready var player_list = $VBox/PlayerList
@onready var server_log = $VBox/ServerLog
const PersistenceManagerScript = preload("res://server/persistence_manager.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")

var server = TCPServer.new()
var peers = {}
var next_peer_id = 1
var characters = {}
var pending_flocks = {}  # peer_id -> {monster_name, monster_level}
var pending_flock_drops = {}  # peer_id -> Array of accumulated drops during flock
var pending_flock_gems = {}   # peer_id -> Total gems earned during flock
var at_merchant = {}  # peer_id -> merchant_info dictionary
var monster_db: MonsterDatabase
var combat_mgr: CombatManager
var world_system: WorldSystem
var persistence: Node
var drop_tables: Node

# Auto-save timer
const AUTO_SAVE_INTERVAL = 60.0  # Save every 60 seconds
var auto_save_timer = 0.0

func _ready():
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

func log_message(msg: String):
	"""Log a message to console and server UI."""
	print(msg)
	if server_log:
		var timestamp = Time.get_time_string_from_system()
		server_log.append_text("[color=#888888][%s][/color] %s\n" % [timestamp, msg])

func update_player_list():
	"""Update the player list UI with connected players."""
	if player_count_label:
		player_count_label.text = "Players: %d" % characters.size()

	if player_list:
		player_list.clear()
		if characters.size() == 0:
			player_list.append_text("[color=#666666]No players connected[/color]")
		else:
			for peer_id in characters:
				var char = characters[peer_id]
				var peer_info = peers.get(peer_id, {})
				var username = peer_info.get("username", "Unknown")
				var char_name = char.name
				var level = char.level
				var race = char.race
				var cls = char.class_type
				player_list.append_text("[color=#4A90E2]%s[/color] - %s %s Lv.%d [color=#666666](%s)[/color]\n" % [
					char_name, race, cls, level, username
				])

func _process(delta):
	# Auto-save timer
	auto_save_timer += delta
	if auto_save_timer >= AUTO_SAVE_INTERVAL:
		auto_save_timer = 0.0
		save_all_active_characters()

	# Check for new connections
	if server.is_connection_available():
		var peer = server.take_connection()
		var peer_id = next_peer_id
		next_peer_id += 1

		peers[peer_id] = {
			"connection": peer,
			"authenticated": false,
			"account_id": "",
			"username": "",
			"character_name": "",
			"buffer": ""
		}

		log_message("New connection! Peer ID: %d" % peer_id)

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

		print("Player logged in: %s (Peer %d)" % [username, peer_id])

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
	broadcast_chat("[color=#90EE90]%s has entered the realm.[/color]" % char_name)

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
	var valid_races = ["Human", "Elf", "Dwarf"]
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
	broadcast_chat("[color=#90EE90]%s has entered the realm.[/color]" % char_name)

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
				"max_hp": char.max_hp,
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
		broadcast_chat("[color=#E74C3C]%s has left the realm.[/color]" % char_name)

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
		broadcast_chat("[color=#E74C3C]%s has left the realm.[/color]" % char_name)

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
	character.x = new_pos.x
	character.y = new_pos.y

	# Regenerate health and resources on movement (small amount per step)
	var regen_percent = 0.02  # 2% per move for resources
	var hp_regen_percent = 0.01  # 1% per move for health
	character.current_hp = min(character.max_hp, character.current_hp + max(1, int(character.max_hp * hp_regen_percent)))
	character.current_mana = min(character.max_mana, character.current_mana + int(character.max_mana * regen_percent))
	character.current_stamina = min(character.max_stamina, character.current_stamina + int(character.max_stamina * regen_percent))
	character.current_energy = min(character.max_energy, character.current_energy + int(character.max_energy * regen_percent))

	# Send location and character updates
	send_location_update(peer_id)
	send_character_update(peer_id)

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

	# Check if in safe zone (can't hunt there)
	var terrain = world_system.get_terrain_at(character.x, character.y)
	var terrain_info = world_system.get_terrain_info(terrain)
	if terrain_info.safe:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#95A5A6]This is a safe area. No monsters can be found here.[/color]",
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
			"message": "[color=#95A5A6]You search the area but are unable to locate any monsters.[/color]",
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
	if character.current_hp >= character.max_hp:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#95A5A6]You are already at full health.[/color]",
			"clear_output": true
		})
		return

	# Restore 10-25% of max HP
	var heal_percent = randf_range(0.10, 0.25)
	var heal_amount = int(character.max_hp * heal_percent)
	heal_amount = max(1, heal_amount)  # At least 1 HP

	character.current_hp = min(character.max_hp, character.current_hp + heal_amount)

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#90EE90]You rest and recover %d HP.[/color]" % heal_amount,
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
			"message": "[color=#FF6B6B]You are ambushed while resting![/color]"
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
		send_to_peer(peer_id, {
			"type": "error",
			"message": result.message
		})
		return

	# Send all combat messages
	for msg in result.messages:
		send_to_peer(peer_id, {
			"type": "combat_message",
			"message": msg
		})

	# If combat ended
	if result.has("combat_ended") and result.combat_ended:
		if result.has("victory") and result.victory:
			# Victory - increment monster kill count
			characters[peer_id].monsters_killed += 1

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

				# Store pending flock data for this peer
				pending_flocks[peer_id] = {
					"monster_name": monster_name,
					"monster_level": monster_level
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

				send_to_peer(peer_id, {
					"type": "combat_end",
					"victory": true,
					"character": characters[peer_id].to_dict(),
					"flock_drops": drop_messages,  # Send all drop messages at once
					"total_gems": total_gems,       # Total gems earned for sound
					"drop_data": drop_data          # Item data for sound effects
				})

				# Save character after combat
				save_character(peer_id)

		elif result.has("fled") and result.fled:
			# Fled successfully - lose any pending flock drops and gems
			if pending_flock_drops.has(peer_id):
				pending_flock_drops.erase(peer_id)
			if pending_flock_gems.has(peer_id):
				pending_flock_gems.erase(peer_id)
			send_to_peer(peer_id, {
				"type": "combat_end",
				"fled": true
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
		send_to_peer(peer_id, {"type": "combat_message", "message": msg})

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
	var death_message = "[color=#FF6B6B]%s (Level %d) has fallen to %s![/color]" % [character.name, character.level, cause_of_death]
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

	# Get complete map display (includes location info at top)
	var map_display = world_system.generate_map_display(character.x, character.y, 7)

	# Send map display as description
	send_to_peer(peer_id, {
		"type": "location",
		"x": character.x,
		"y": character.y,
		"description": map_display
	})

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
	var username = peers[peer_id].get("username", "Unknown")
	var char_name = ""
	if characters.has(peer_id):
		char_name = characters[peer_id].name

	log_message("Peer %d (%s) disconnected" % [peer_id, username])

	# Save character before removing
	save_character(peer_id)

	# Remove from combat if needed
	if combat_mgr.is_in_combat(peer_id):
		combat_mgr.end_combat(peer_id, false)

	# Clear pending flock if any
	if pending_flocks.has(peer_id):
		pending_flocks.erase(peer_id)

	if characters.has(peer_id):
		characters.erase(peer_id)

	peers.erase(peer_id)

	# Update UI
	update_player_list()

	# Broadcast disconnect message (after cleanup so they don't get their own message)
	if char_name != "":
		broadcast_chat("[color=#E74C3C]%s has left the realm.[/color]" % char_name)

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

	# Normal monster encounter
	var monster = monster_db.generate_monster(level_range.min, level_range.max)
	var result = combat_mgr.start_combat(peer_id, character, monster)

	if result.success:
		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": result.message,
			"combat_state": result.combat_state
		})

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
		var msg = "[color=#FFD700]╔════════════════════════════════════╗[/color]\n"
		msg += "[color=#FFD700]║[/color]     [color=#90EE90]✦ LUCKY FIND! ✦[/color]     [color=#FFD700]║[/color]\n"
		msg += "[color=#FFD700]╠════════════════════════════════════╣[/color]\n"
		msg += "[color=#FFD700]║[/color] You discover a hidden cache!       [color=#FFD700]║[/color]\n"
		msg += "[color=#FFD700]║[/color] [color=#FFD700]Found %d gold![/color]            [color=#FFD700]║[/color]\n" % gold_amount
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
		var msg = "[color=#FFD700]╔════════════════════════════════════╗[/color]\n"
		msg += "[color=#FFD700]║[/color]     [color=#90EE90]✦ LUCKY FIND! ✦[/color]     [color=#FFD700]║[/color]\n"
		msg += "[color=#FFD700]╠════════════════════════════════════╣[/color]\n"
		msg += "[color=#FFD700]║[/color] You discover something valuable!   [color=#FFD700]║[/color]\n"
		msg += "[color=#FFD700]║[/color] [color=%s]%s[/color] [color=#FFD700]║[/color]\n" % [rarity_color, item.get("name", "Unknown Item")]
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
	msg += "[color=#FFD700]║[/color] [color=#90EE90]+%d %s permanently![/color] [color=#FFD700]║[/color]\n" % [bonus, stat_name]
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

func trigger_flock_encounter(peer_id: int, monster_name: String, monster_level: int):
	"""Trigger a flock encounter with the same monster type"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Generate another monster of the same type at the same level
	var monster = monster_db.generate_monster_by_name(monster_name, monster_level)

	# Start combat
	var result = combat_mgr.start_combat(peer_id, character, monster)

	if result.success:
		# Send flock encounter message with clear_output flag
		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": "[color=#FF6B6B]Another %s appears![/color]\n%s" % [monster.name, result.message],
			"combat_state": result.combat_state,
			"is_flock": true,
			"clear_output": true
		})

func handle_continue_flock(peer_id: int):
	"""Handle player continuing into a flock encounter"""
	if not pending_flocks.has(peer_id):
		return

	var flock_data = pending_flocks[peer_id]
	pending_flocks.erase(peer_id)

	trigger_flock_encounter(peer_id, flock_data.monster_name, flock_data.monster_level)

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

	# Handle consumables (potions, etc.)
	if "potion" in item_type or "elixir" in item_type:
		# Heal based on item level
		var heal_amount = item.get("level", 1) * 10
		var actual_heal = character.heal(heal_amount)

		# Remove from inventory
		character.remove_item(index)

		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#90EE90]You use %s and restore %d HP![/color]" % [item.get("name", "item"), actual_heal]
		})

		# Update character data
		send_character_update(peer_id)
	else:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#95A5A6]This item cannot be used directly. Try equipping it.[/color]"
		})

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
	elif "ring" in item_type:
		slot = "ring"
	elif "amulet" in item_type:
		slot = "amulet"
	else:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#E74C3C]This item cannot be equipped.[/color]"
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
			"message": "[color=#90EE90]You equip %s and unequip %s.[/color]" % [equip_item.get("name", "item"), old_item.get("name", "item")]
		})
	else:
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#90EE90]You equip %s.[/color]" % equip_item.get("name", "item")
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
			"message": "[color=#95A5A6]Nothing equipped in that slot.[/color]"
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
		"message": "[color=#90EE90]You unequip %s.[/color]" % item.get("name", "item")
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
		"message": "[color=#FF6B6B]You discard %s.[/color]" % item.get("name", "Unknown")
	})

	send_character_update(peer_id)

func send_character_update(peer_id: int):
	"""Send character data update to client"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	send_to_peer(peer_id, {
		"type": "character_update",
		"character": character.to_dict()
	})

# ===== MERCHANT HANDLERS =====

func trigger_merchant_encounter(peer_id: int):
	"""Trigger a merchant encounter for the player"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]
	var merchant = world_system.get_merchant_at(character.x, character.y)

	if merchant.is_empty():
		return

	# Generate shop inventory based on player level and merchant specialty
	var shop_items = generate_shop_inventory(character.level, merchant.get("hash", 0), merchant.get("specialty", "all"))
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
	# Recharge option - show cost based on player level
	var recharge_cost = _get_recharge_cost(character.level)
	services_text.append("[2] Recharge resources (%d gold)" % recharge_cost)
	services_text.append("[Space] Leave")

	send_to_peer(peer_id, {
		"type": "merchant_start",
		"merchant": merchant,
		"message": "[color=#FFD700]A %s approaches you![/color]\n\"Greetings, traveler! Care to do business?\"\n\n%s" % [merchant.name, "\n".join(services_text)]
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

	if not slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
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
				"message": "[color=#FF6B6B]You need %d gems for %d upgrade%s. You have %d gems.[/color]" % [gem_cost, count, "s" if count > 1 else "", character.gems]
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
			"message": "[color=#90EE90]%s upgraded %d level%s (now +%d) for %d gems![/color]" % [item.get("name", "Item"), count, "s" if count > 1 else "", item["level"] - 1, gem_cost]
		})
	else:
		# Standard gold payment
		if character.gold < total_cost:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF6B6B]You need %d gold for %d upgrade%s. You have %d gold.[/color]" % [total_cost, count, "s" if count > 1 else "", character.gold]
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
			"message": "[color=#90EE90]%s upgraded %d level%s (now +%d) for %d gold![/color]" % [item.get("name", "Item"), count, "s" if count > 1 else "", item["level"] - 1, total_cost]
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
			"message": "[color=#FF6B6B]You need at least %d gold to gamble at your level![/color]" % (min_bet * 2),
			"gold": character.gold
		})
		return

	bet_amount = clampi(bet_amount, min_bet, max_bet)

	if character.gold < bet_amount or bet_amount < min_bet:
		send_to_peer(peer_id, {
			"type": "gamble_result",
			"success": false,
			"message": "[color=#FF6B6B]Invalid bet! Min: %d, Max: %d gold[/color]" % [min_bet, max_bet],
			"gold": character.gold
		})
		return

	# Simulate dice rolls for both merchant and player
	var merchant_dice = [randi() % 6 + 1, randi() % 6 + 1, randi() % 6 + 1]
	var player_dice = [randi() % 6 + 1, randi() % 6 + 1, randi() % 6 + 1]
	var merchant_total = merchant_dice[0] + merchant_dice[1] + merchant_dice[2]
	var player_total = player_dice[0] + player_dice[1] + player_dice[2]

	# Build dice display
	var dice_msg = "[color=#FF6B6B]Merchant:[/color] [%d][%d][%d] = %d\n" % [merchant_dice[0], merchant_dice[1], merchant_dice[2], merchant_total]
	dice_msg += "[color=#90EE90]You:[/color] [%d][%d][%d] = %d\n" % [player_dice[0], player_dice[1], player_dice[2], player_total]

	var result_msg = ""
	var won = false
	var item_won = null

	# Determine outcome based on dice difference
	var diff = player_total - merchant_total

	if diff < -5:
		# Bad loss - lose bet
		character.gold -= bet_amount
		result_msg = "[color=#FF6B6B]Crushing defeat! You lose %d gold.[/color]" % bet_amount
	elif diff < 0:
		# Small loss - lose half bet
		var loss = bet_amount / 2
		character.gold -= loss
		result_msg = "[color=#FF6B6B]Close, but not enough. You lose %d gold.[/color]" % loss
	elif diff == 0:
		# Tie - push (no change)
		result_msg = "[color=#FFD700]A tie! Your bet is returned.[/color]"
	elif diff <= 5:
		# Small win - win 1.5x
		var winnings = int(bet_amount * 1.5)
		character.gold += winnings - bet_amount
		result_msg = "[color=#90EE90]Victory! You win %d gold![/color]" % winnings
		won = true
	elif diff <= 10:
		# Big win - win 2.5x
		var winnings = int(bet_amount * 2.5)
		character.gold += winnings - bet_amount
		result_msg = "[color=#FFD700]Dominating! You win %d gold![/color]" % winnings
		won = true
	else:
		# Jackpot - triple 6s or huge margin, win item or 5x
		if player_dice[0] == 6 and player_dice[1] == 6 and player_dice[2] == 6:
			# Triple 6s - guaranteed item!
			var item_level = max(1, character.level + randi() % 20)
			var tier = _level_to_tier(item_level)
			var items = drop_tables.roll_drops(tier, 100, item_level)

			if items.size() > 0 and character.can_add_item():
				character.add_item(items[0])
				item_won = items[0]
				var rarity_color = _get_rarity_color(items[0].get("rarity", "common"))
				result_msg = "[color=#FFD700]TRIPLE SIXES! JACKPOT![/color]\n[color=%s]You won: %s![/color]" % [rarity_color, items[0].get("name", "Unknown")]
			else:
				var winnings = bet_amount * 5
				character.gold += winnings - bet_amount
				result_msg = "[color=#FFD700]TRIPLE SIXES! You win %d gold![/color]" % winnings
			won = true
		else:
			# Big margin win - 3x
			var winnings = bet_amount * 3
			character.gold += winnings - bet_amount
			result_msg = "[color=#FFD700]CRUSHING VICTORY! You win %d gold![/color]" % winnings
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
			"message": "[color=#95A5A6]%s waves goodbye. \"Safe travels, adventurer!\"[/color]" % merchant_name
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

	# Check if already at full resources
	var needs_recharge = (character.current_mana < character.max_mana or
						  character.current_stamina < character.max_stamina or
						  character.current_energy < character.max_energy)

	if not needs_recharge:
		send_to_peer(peer_id, {
			"type": "merchant_message",
			"message": "[color=#95A5A6]\"You look fully rested already, traveler!\"[/color]"
		})
		return

	# Check if player has enough gold
	if character.gold < cost:
		send_to_peer(peer_id, {
			"type": "merchant_message",
			"message": "[color=#E74C3C]\"You don't have enough gold! Recharge costs %d gold.\"[/color]" % cost
		})
		return

	# Deduct gold and restore resources
	character.gold -= cost
	character.current_mana = character.max_mana
	character.current_stamina = character.max_stamina
	character.current_energy = character.max_energy

	send_to_peer(peer_id, {
		"type": "merchant_message",
		"message": "[color=#2ECC71]The merchant provides you with a revitalizing tonic![/color]\n[color=#90EE90]All resources fully restored! (-%d gold)[/color]" % cost
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
			return item_type.begins_with("armor_")
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

	if use_gems:
		var gem_price = int(ceil(price / 1000.0))
		if character.gems < gem_price:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF6B6B]You need %d gems. You have %d gems.[/color]" % [gem_price, character.gems]
			})
			return

		character.gems -= gem_price
		item.erase("shop_price")  # Remove shop metadata
		character.add_item(item)

		var rarity_color = _get_rarity_color(item.get("rarity", "common"))
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#90EE90]You purchased [/color][color=%s]%s[/color][color=#90EE90] for %d gems![/color]" % [rarity_color, item.get("name", "Unknown"), gem_price]
		})
	else:
		if character.gold < price:
			send_to_peer(peer_id, {
				"type": "text",
				"message": "[color=#FF6B6B]You need %d gold. You have %d gold.[/color]" % [price, character.gold]
			})
			return

		character.gold -= price
		item.erase("shop_price")  # Remove shop metadata
		character.add_item(item)

		var rarity_color = _get_rarity_color(item.get("rarity", "common"))
		send_to_peer(peer_id, {
			"type": "text",
			"message": "[color=#90EE90]You purchased [/color][color=%s]%s[/color][color=#90EE90] for %d gold![/color]" % [rarity_color, item.get("name", "Unknown"), price]
		})

	# Remove item from shop (one-time purchase)
	shop_items.remove_at(item_index)
	merchant["shop_items"] = shop_items

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
			"gem_price": int(ceil(item.get("shop_price", 100) / 1000.0))
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
