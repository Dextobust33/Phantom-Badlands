# server_WORKING.gd
# Fixed server - polls connections properly in Godot 4
extends Node

const PORT = 9080
var server = TCPServer.new()
var peers = {}
var next_peer_id = 1
var characters = {}
var monster_db: MonsterDatabase
var combat_mgr: CombatManager
var world_system: WorldSystem  # World map system

func _ready():
	print("========================================")
	print("Phantasia Revival Server Starting...")
	print("========================================")
	
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
	
	print("✓ Server started successfully!")
	print("✓ Listening on port: %d" % PORT)
	print("✓ Waiting for connections...")
	print("========================================")

func _process(_delta):
	# Check for new connections
	if server.is_connection_available():
		var peer = server.take_connection()
		var peer_id = next_peer_id
		next_peer_id += 1
		
		peers[peer_id] = {
			"connection": peer,
			"authenticated": false,
			"username": "",
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
	print("Received message from peer %d: %s" % [peer_id, msg_type])
	
	match msg_type:
		"login":
			handle_login(peer_id, message)
		"create_character":
			handle_create_character(peer_id, message)
		"chat":
			handle_chat(peer_id, message)
		"move":
			handle_move(peer_id, message)
		"combat":
			handle_combat_command(peer_id, message)
		_:
			print("Unknown message type: %s" % msg_type)

func handle_login(peer_id: int, message: Dictionary):
	var username = message.get("username", "")
	
	if username.is_empty():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Username cannot be empty"
		})
		return
	
	peers[peer_id].authenticated = true
	peers[peer_id].username = username
	
	print("Player logged in: %s (Peer %d)" % [username, peer_id])
	
	send_to_peer(peer_id, {
		"type": "login_success",
		"username": username,
		"message": "Login successful! Please create a character."
	})

func handle_create_character(peer_id: int, message: Dictionary):
	var char_name = message.get("name", "")
	var char_class = message.get("class", "Fighter")
	
	if char_name.is_empty():
		send_to_peer(peer_id, {
			"type": "error",
			"message": "Character name cannot be empty"
		})
		return
	
	var character = Character.new()
	character.initialize(char_name, char_class)
	character.character_id = peer_id
	
	characters[peer_id] = character
	
	print("Character created: %s (%s) for peer %d" % [char_name, char_class, peer_id])
	
	send_to_peer(peer_id, {
		"type": "character_created",
		"character": character.to_dict(),
		"message": "Welcome to the world, %s!" % char_name
	})
	
	send_location_update(peer_id)

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
	
	var dir_name = world_system.get_direction_name(direction)
	print("%s moves %s to (%d, %d)" % [character.name, dir_name, new_pos.x, new_pos.y])
	
	# Send location update
	send_location_update(peer_id)
	
	# Check for encounter
	if world_system.check_encounter(new_pos.x, new_pos.y):
		trigger_encounter(peer_id)

func handle_combat_command(peer_id: int, message: Dictionary):
	"""Handle combat commands from player"""
	var command = message.get("command", "")
	print("DEBUG SERVER: Received combat command '%s' from peer %d" % [command, peer_id])

	if command.is_empty():
		print("DEBUG SERVER: Command is empty, returning")
		return

	# Process combat action
	print("DEBUG SERVER: Processing combat command, in_combat=%s" % combat_mgr.is_in_combat(peer_id))
	var result = combat_mgr.process_combat_command(peer_id, command)
	print("DEBUG SERVER: Combat result: %s" % result)
	
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
			# Victory - send updated character
			send_to_peer(peer_id, {
				"type": "combat_end",
				"victory": true,
				"character": characters[peer_id].to_dict()
			})
		elif result.has("fled") and result.fled:
			# Fled successfully
			send_to_peer(peer_id, {
				"type": "combat_end",
				"fled": true
			})
		else:
			# Defeated
			send_to_peer(peer_id, {
				"type": "combat_end",
				"victory": false,
				"message": "[color=#FF0000]You have been defeated![/color]"
			})
			# Respawn at sanctuary
			characters[peer_id].x = 0
			characters[peer_id].y = 10
			characters[peer_id].current_hp = characters[peer_id].max_hp
			send_location_update(peer_id)
	else:
		# Combat continues - send updated state
		send_to_peer(peer_id, {
			"type": "combat_update",
			"combat_state": combat_mgr.get_combat_display(peer_id)
		})

func send_location_update(peer_id: int):
	if not characters.has(peer_id):
		return
	
	var character = characters[peer_id]
	
	# Get complete map display (includes location info at top)
	var map_display = world_system.generate_map_display(character.x, character.y, 7)
	
	# Also get just the description for game events if needed
	var description = world_system.get_location_description(character.x, character.y)
	
	# Send map display as description
	send_to_peer(peer_id, {
		"type": "location",
		"x": character.x,
		"y": character.y,
		"description": map_display  # This now has everything for the map panel
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

func handle_disconnect(peer_id: int):
	var username = peers[peer_id].get("username", "Unknown")
	print("Peer %d (%s) disconnected" % [peer_id, username])
	
	if characters.has(peer_id):
		characters.erase(peer_id)
	
	peers.erase(peer_id)

func _exit_tree():
	print("Server shutting down...")
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
