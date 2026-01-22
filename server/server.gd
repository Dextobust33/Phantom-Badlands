# server.gd
# Server with persistence, account system, and permadeath
extends Node

const PORT = 9080
const PersistenceManagerScript = preload("res://server/persistence_manager.gd")

var server = TCPServer.new()
var peers = {}
var next_peer_id = 1
var characters = {}
var monster_db: MonsterDatabase
var combat_mgr: CombatManager
var world_system: WorldSystem
var persistence: Node

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

	var error = server.listen(PORT)
	if error != OK:
		print("ERROR: Failed to start server on port %d" % PORT)
		print("Error code: %d" % error)
		return

	print("Persistence system loaded")
	print("Server started successfully!")
	print("Listening on port: %d" % PORT)
	print("Waiting for connections...")
	print("========================================")

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

		print("New connection! Peer ID: %d" % peer_id)

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
		"combat":
			handle_combat_command(peer_id, message)
		"rest":
			handle_rest(peer_id)
		"logout_character":
			handle_logout_character(peer_id)
		"logout_account":
			handle_logout_account(peer_id)
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

	print("Character loaded: %s for peer %d" % [char_name, peer_id])

	send_to_peer(peer_id, {
		"type": "character_loaded",
		"character": character.to_dict(),
		"message": "Welcome back, %s!" % char_name
	})

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

	# Validate class
	var valid_classes = ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]
	if char_class not in valid_classes:
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Invalid class. Choose: " + ", ".join(valid_classes)
		})
		return

	# Create character
	var character = Character.new()
	character.initialize(char_name, char_class)
	character.character_id = peer_id

	# Save character to persistence
	persistence.save_character(account_id, character)
	persistence.add_character_to_account(account_id, char_name)

	# Store in active characters
	characters[peer_id] = character
	peers[peer_id].character_name = char_name

	print("Character created: %s (%s) for peer %d" % [char_name, char_class, peer_id])

	send_to_peer(peer_id, {
		"type": "character_created",
		"character": character.to_dict(),
		"message": "Welcome to the world, %s!" % char_name
	})

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

func handle_logout_character(peer_id: int):
	"""Logout of current character, return to character select"""
	if not peers[peer_id].authenticated:
		return

	# Save character before logout
	save_character(peer_id)

	# Remove from combat if needed
	if combat_mgr.is_in_combat(peer_id):
		combat_mgr.end_combat(peer_id, false)

	# Remove character from active characters
	if characters.has(peer_id):
		print("Character logout: %s" % characters[peer_id].name)
		characters.erase(peer_id)

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

	# Remove character
	if characters.has(peer_id):
		print("Character logout: %s" % characters[peer_id].name)
		characters.erase(peer_id)

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

	var direction = message.get("direction", 5)
	var character = characters[peer_id]

	# Get old position
	var old_x = character.x
	var old_y = character.y

	# Calculate new position
	var new_pos = world_system.move_player(old_x, old_y, direction)
	character.x = new_pos.x
	character.y = new_pos.y

	# Send location update
	send_location_update(peer_id)

	# Check for encounter
	if world_system.check_encounter(new_pos.x, new_pos.y):
		trigger_encounter(peer_id)

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
			"message": "[color=#95A5A6]You are already at full health.[/color]"
		})
		return

	# Restore 10-25% of max HP
	var heal_percent = randf_range(0.10, 0.25)
	var heal_amount = int(character.max_hp * heal_percent)
	heal_amount = max(1, heal_amount)  # At least 1 HP

	character.current_hp = min(character.max_hp, character.current_hp + heal_amount)

	send_to_peer(peer_id, {
		"type": "text",
		"message": "[color=#90EE90]You rest and recover %d HP.[/color]" % heal_amount
	})

	# Send updated character data
	send_to_peer(peer_id, {
		"type": "character_update",
		"character": character.to_dict()
	})

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

			# Send updated character
			send_to_peer(peer_id, {
				"type": "combat_end",
				"victory": true,
				"character": characters[peer_id].to_dict()
			})

			# Save character after combat
			save_character(peer_id)

		elif result.has("fled") and result.fled:
			# Fled successfully
			send_to_peer(peer_id, {
				"type": "combat_end",
				"fled": true
			})
		else:
			# Defeated - PERMADEATH!
			handle_permadeath(peer_id, result.get("monster_name", "Unknown"))
	else:
		# Combat continues - send updated state
		send_to_peer(peer_id, {
			"type": "combat_update",
			"combat_state": combat_mgr.get_combat_display(peer_id)
		})

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

	# Send permadeath message
	send_to_peer(peer_id, {
		"type": "permadeath",
		"character_name": character.name,
		"level": character.level,
		"experience": character.experience,
		"cause_of_death": cause_of_death,
		"leaderboard_rank": rank,
		"message": "[color=#FF0000]%s has fallen! Slain by %s.[/color]" % [character.name, cause_of_death]
	})

	# Delete character from persistence
	persistence.delete_character(account_id, character.name)

	# Remove from active characters
	characters.erase(peer_id)
	peers[peer_id].character_name = ""

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
	print("Peer %d (%s) disconnected" % [peer_id, username])

	# Save character before removing
	save_character(peer_id)

	# Remove from combat if needed
	if combat_mgr.is_in_combat(peer_id):
		combat_mgr.end_combat(peer_id, false)

	if characters.has(peer_id):
		characters.erase(peer_id)

	peers.erase(peer_id)

func _exit_tree():
	print("Server shutting down...")
	# Save all characters before exit
	save_all_active_characters()
	server.stop()

func trigger_encounter(peer_id: int):
	"""Trigger a random monster encounter"""
	if not characters.has(peer_id):
		return

	var character = characters[peer_id]

	# Get monster level range for this location
	var level_range = world_system.get_monster_level_range(character.x, character.y)

	# Generate random monster
	var monster = monster_db.generate_monster(level_range.min, level_range.max)

	# Start combat
	var result = combat_mgr.start_combat(peer_id, character, monster)

	if result.success:
		# Send combat start message
		send_to_peer(peer_id, {
			"type": "combat_start",
			"message": result.message,
			"combat_state": result.combat_state
		})
