# test_combined.gd
# Combined test mode with combat, movement, and action bar support
extends Control

# Server components
var server = TCPServer.new()
var server_peers = {}
var next_peer_id = 1
var server_characters = {}

# Game systems (server-side)
var world_system: WorldSystem
var monster_db: MonsterDatabase
var combat_mgr: CombatManager

# Client components
var client_connection = StreamPeerTCP.new()
var client_connected = false
var client_buffer = ""
var client_logged_in = false
var client_has_character = false
var client_character_data = {}
var client_in_combat = false

# Movement
var last_move_time = 0.0
const MOVE_COOLDOWN = 0.3

# UI References
var server_output: RichTextLabel
var client_output: RichTextLabel
var client_input: LineEdit
var send_button: Button
var auto_connect_button: Button
var action_bar: HBoxContainer
var map_display: RichTextLabel

# Action bar
var action_buttons: Array[Button] = []
var action_hotkeys = [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_1]
var current_actions: Array[Dictionary] = []

const PORT = 9080

func _ready():
	print("=== Combined Test Mode - Full Combat Support ===")

	# Initialize game systems
	world_system = WorldSystem.new()
	add_child(world_system)

	monster_db = MonsterDatabase.new()
	add_child(monster_db)

	combat_mgr = CombatManager.new()
	add_child(combat_mgr)

	# Find UI nodes
	server_output = get_node_or_null("HBoxContainer/ServerPanel/VBoxContainer/ServerOutput")
	client_output = get_node_or_null("HBoxContainer/ClientPanel/VBoxContainer/ClientOutput")
	client_input = get_node_or_null("HBoxContainer/ClientPanel/VBoxContainer/InputContainer/ClientInput")
	send_button = get_node_or_null("HBoxContainer/ClientPanel/VBoxContainer/InputContainer/SendButton")
	auto_connect_button = get_node_or_null("HBoxContainer/ClientPanel/VBoxContainer/AutoConnectButton")
	action_bar = get_node_or_null("HBoxContainer/ClientPanel/VBoxContainer/ActionBar")
	map_display = get_node_or_null("HBoxContainer/ClientPanel/VBoxContainer/MapDisplay")

	if not (server_output and client_output and client_input and send_button and auto_connect_button):
		print("ERROR: Missing UI nodes!")
		return

	print("All UI nodes found")

	# Setup action bar
	setup_action_bar()

	# Connect signals
	send_button.pressed.connect(_on_send_pressed)
	client_input.text_submitted.connect(_on_input_submitted)
	auto_connect_button.pressed.connect(_on_auto_connect)
	client_input.focus_entered.connect(_on_input_focus_entered)
	client_input.focus_exited.connect(_on_input_focus_exited)

	# Configure
	server_output.bbcode_enabled = true
	client_output.bbcode_enabled = true
	server_output.scroll_following = true
	client_output.scroll_following = true

	# Start server
	start_server()

	# Welcome
	client_display("[b][color=#4A90E2]Phantasia Revival - Combat Test[/color][/b]")
	client_display("")
	client_display("Click 'Auto Connect & Setup' to start")
	client_display("Use [b]NUMPAD[/b] to move (click outside input first)")
	client_display("Use [b]Q/W/E/R[/b] for actions or click buttons")
	client_display("")

	update_action_bar()
	client_input.grab_focus()

func start_server():
	server_display("========================================")
	server_display("Server Starting...")

	var error = server.listen(PORT)
	if error != OK:
		server_display("ERROR: Failed to start! Error: %d" % error)
		return

	server_display("Server started on port %d" % PORT)
	server_display("World system initialized")
	server_display("Monster database loaded")
	server_display("Combat manager ready")
	server_display("========================================")

func _process(_delta):
	process_server()
	process_client()
	process_hotkeys()
	process_movement()

# ===== ACTION BAR =====

func setup_action_bar():
	if not action_bar:
		return
	action_buttons.clear()
	for i in range(5):
		var action_container = action_bar.get_node_or_null("Action%d" % (i + 1))
		if action_container:
			var button = action_container.get_node_or_null("Button")
			if button:
				action_buttons.append(button)
				button.pressed.connect(_on_action_button_pressed.bind(i))
	print("Action bar setup: %d buttons" % action_buttons.size())

func update_action_bar():
	current_actions.clear()

	if client_in_combat:
		current_actions = [
			{"label": "Attack", "action": "attack", "enabled": true},
			{"label": "Defend", "action": "defend", "enabled": true},
			{"label": "Flee", "action": "flee", "enabled": true},
			{"label": "Special", "action": "special", "enabled": false},
			{"label": "---", "action": "", "enabled": false},
		]
	elif client_has_character:
		current_actions = [
			{"label": "Status", "action": "status", "enabled": true},
			{"label": "Help", "action": "help", "enabled": true},
			{"label": "---", "action": "", "enabled": false},
			{"label": "---", "action": "", "enabled": false},
			{"label": "---", "action": "", "enabled": false},
		]
	else:
		current_actions = [
			{"label": "Help", "action": "help", "enabled": true},
			{"label": "---", "action": "", "enabled": false},
			{"label": "---", "action": "", "enabled": false},
			{"label": "---", "action": "", "enabled": false},
			{"label": "---", "action": "", "enabled": false},
		]

	for i in range(min(action_buttons.size(), current_actions.size())):
		action_buttons[i].text = current_actions[i].label
		action_buttons[i].disabled = not current_actions[i].enabled

func _on_action_button_pressed(index: int):
	trigger_action(index)

func trigger_action(index: int):
	if index < 0 or index >= current_actions.size():
		return
	var action = current_actions[index]
	if not action.enabled:
		return

	match action.action:
		"attack", "defend", "flee", "special":
			if client_in_combat:
				client_display("[color=#F39C12]> %s[/color]" % action.action)
				client_send({"type": "combat", "command": action.action})
		"status":
			client_show_status()
		"help":
			client_show_help()

func process_hotkeys():
	if client_input.has_focus():
		return

	for i in range(action_hotkeys.size()):
		if Input.is_physical_key_pressed(action_hotkeys[i]):
			if not get_meta("hotkey_%d_pressed" % i, false):
				set_meta("hotkey_%d_pressed" % i, true)
				trigger_action(i)
		else:
			set_meta("hotkey_%d_pressed" % i, false)

func process_movement():
	if not client_connected or not client_has_character:
		return
	if client_input.has_focus():
		return
	if client_in_combat:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_move_time < MOVE_COOLDOWN:
		return

	var move_dir = 0
	if Input.is_physical_key_pressed(KEY_KP_1):
		move_dir = 1
	elif Input.is_physical_key_pressed(KEY_KP_2):
		move_dir = 2
	elif Input.is_physical_key_pressed(KEY_KP_3):
		move_dir = 3
	elif Input.is_physical_key_pressed(KEY_KP_4):
		move_dir = 4
	elif Input.is_physical_key_pressed(KEY_KP_5):
		move_dir = 5
	elif Input.is_physical_key_pressed(KEY_KP_6):
		move_dir = 6
	elif Input.is_physical_key_pressed(KEY_KP_7):
		move_dir = 7
	elif Input.is_physical_key_pressed(KEY_KP_8):
		move_dir = 8
	elif Input.is_physical_key_pressed(KEY_KP_9):
		move_dir = 9

	if move_dir > 0:
		client_send({"type": "move", "direction": move_dir})
		last_move_time = current_time

func _on_input_focus_entered():
	if client_has_character:
		client_display("[color=#95A5A6]Chat mode[/color]")

func _on_input_focus_exited():
	if client_has_character:
		client_display("[color=#95A5A6]Movement mode (numpad)[/color]")

# ===== SERVER =====

func process_server():
	# Accept new connections
	if server.is_connection_available():
		var peer = server.take_connection()
		var peer_id = next_peer_id
		next_peer_id += 1

		server_peers[peer_id] = {
			"connection": peer,
			"authenticated": false,
			"username": "",
			"buffer": ""
		}

		server_display("[color=#2ECC71]New connection: Peer %d[/color]" % peer_id)

		server_send_to_peer(peer_id, {
			"type": "welcome",
			"message": "Welcome to Phantasia Revival!"
		})

	# Process existing connections
	var to_remove = []
	for peer_id in server_peers.keys():
		var peer_data = server_peers[peer_id]
		var conn = peer_data.connection

		conn.poll()

		if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			to_remove.append(peer_id)
			continue

		var available = conn.get_available_bytes()
		if available > 0:
			var data = conn.get_data(available)
			if data[0] == OK:
				peer_data.buffer += data[1].get_string_from_utf8()
				server_process_buffer(peer_id)

	for peer_id in to_remove:
		server_display("[color=#F39C12]Peer %d disconnected[/color]" % peer_id)
		server_peers.erase(peer_id)
		server_characters.erase(peer_id)

func server_process_buffer(peer_id: int):
	var peer_data = server_peers[peer_id]
	var buffer = peer_data.buffer

	while "\n" in buffer:
		var pos = buffer.find("\n")
		var msg = buffer.substr(0, pos)
		buffer = buffer.substr(pos + 1)

		var json = JSON.new()
		if json.parse(msg) == OK:
			server_handle_message(peer_id, json.data)

	peer_data.buffer = buffer

func server_handle_message(peer_id: int, msg: Dictionary):
	var type = msg.get("type", "")
	server_display("<- [color=#4A90E2]%s[/color]" % type)

	match type:
		"login":
			var username = msg.get("username", "")
			server_peers[peer_id].authenticated = true
			server_peers[peer_id].username = username
			server_display("   Login: [b]%s[/b]" % username)
			server_send_to_peer(peer_id, {
				"type": "login_success",
				"username": username,
				"message": "Logged in as %s" % username
			})

		"create_character":
			var char_name = msg.get("name", "")
			var char_class = msg.get("class", "Fighter")

			var character = Character.new()
			character.initialize(char_name, char_class)
			character.character_id = peer_id
			server_characters[peer_id] = character

			server_display("   Character: [b]%s[/b] (%s)" % [char_name, char_class])

			server_send_to_peer(peer_id, {
				"type": "character_created",
				"character": character.to_dict(),
				"message": "Character created!"
			})

			# Send initial location
			server_send_location_update(peer_id)

		"move":
			server_handle_move(peer_id, msg)

		"combat":
			server_handle_combat(peer_id, msg)

		"chat":
			var text = msg.get("message", "")
			var username = server_peers[peer_id].username
			server_display("   Chat: %s: %s" % [username, text])

			for other_id in server_peers.keys():
				if server_peers[other_id].authenticated and other_id != peer_id:
					server_send_to_peer(other_id, {
						"type": "chat",
						"sender": username,
						"message": text
					})

func server_handle_move(peer_id: int, msg: Dictionary):
	if not server_characters.has(peer_id):
		return

	if combat_mgr.is_in_combat(peer_id):
		server_send_to_peer(peer_id, {
			"type": "error",
			"message": "Cannot move while in combat!"
		})
		return

	var direction = msg.get("direction", 5)
	var character = server_characters[peer_id]

	var old_x = character.x
	var old_y = character.y

	var new_pos = world_system.move_player(old_x, old_y, direction)
	character.x = new_pos.x
	character.y = new_pos.y

	var dir_name = world_system.get_direction_name(direction)
	server_display("   Move: %s -> (%d, %d)" % [dir_name, new_pos.x, new_pos.y])

	server_send_location_update(peer_id)

	# Check for encounter
	if world_system.check_encounter(new_pos.x, new_pos.y):
		server_trigger_encounter(peer_id)

func server_trigger_encounter(peer_id: int):
	if not server_characters.has(peer_id):
		return

	var character = server_characters[peer_id]
	var level_range = world_system.get_monster_level_range(character.x, character.y)
	var monster = monster_db.generate_monster(level_range.min, level_range.max)

	var result = combat_mgr.start_combat(peer_id, character, monster)

	if result.success:
		server_display("[color=#FF6B6B]   COMBAT: %s vs %s[/color]" % [character.name, monster.name])
		server_send_to_peer(peer_id, {
			"type": "combat_start",
			"message": result.message,
			"combat_state": result.combat_state
		})

func server_handle_combat(peer_id: int, msg: Dictionary):
	var command = msg.get("command", "")
	if command.is_empty():
		return

	var result = combat_mgr.process_combat_command(peer_id, command)

	if not result.success:
		server_send_to_peer(peer_id, {
			"type": "error",
			"message": result.message
		})
		return

	# Send combat messages
	for combat_msg in result.messages:
		server_send_to_peer(peer_id, {
			"type": "combat_message",
			"message": combat_msg
		})

	# Check if combat ended
	if result.get("combat_ended", false):
		if result.get("victory", false):
			server_display("[color=#00FF00]   Victory![/color]")
			server_send_to_peer(peer_id, {
				"type": "combat_end",
				"victory": true,
				"character": server_characters[peer_id].to_dict()
			})
		elif result.get("fled", false):
			server_display("[color=#FFD700]   Fled![/color]")
			server_send_to_peer(peer_id, {
				"type": "combat_end",
				"fled": true
			})
		else:
			server_display("[color=#FF0000]   Defeated![/color]")
			server_send_to_peer(peer_id, {
				"type": "combat_end",
				"victory": false
			})
			# Respawn
			server_characters[peer_id].x = 0
			server_characters[peer_id].y = 10
			server_characters[peer_id].current_hp = server_characters[peer_id].max_hp
			server_send_location_update(peer_id)
	else:
		server_send_to_peer(peer_id, {
			"type": "combat_update",
			"combat_state": combat_mgr.get_combat_display(peer_id)
		})

func server_send_location_update(peer_id: int):
	if not server_characters.has(peer_id):
		return

	var character = server_characters[peer_id]
	var map_display_text = world_system.generate_map_display(character.x, character.y, 5)

	server_send_to_peer(peer_id, {
		"type": "location",
		"x": character.x,
		"y": character.y,
		"description": map_display_text
	})

func server_send_to_peer(peer_id: int, data: Dictionary):
	if not server_peers.has(peer_id):
		return
	var conn = server_peers[peer_id].connection
	if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	var json_str = JSON.stringify(data) + "\n"
	conn.put_data(json_str.to_utf8_buffer())

# ===== CLIENT =====

func process_client():
	client_connection.poll()

	var status = client_connection.get_status()

	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not client_connected:
			client_connected = true
			client_display("[color=#2ECC71]Connected![/color]")

		var available = client_connection.get_available_bytes()
		if available > 0:
			var data = client_connection.get_data(available)
			if data[0] == OK:
				client_buffer += data[1].get_string_from_utf8()
				client_process_buffer()

	elif status == StreamPeerTCP.STATUS_ERROR:
		if client_connected:
			client_display("[color=#E74C3C]Connection error[/color]")
			client_connected = false
			client_in_combat = false
			update_action_bar()

func client_process_buffer():
	while "\n" in client_buffer:
		var pos = client_buffer.find("\n")
		var msg = client_buffer.substr(0, pos)
		client_buffer = client_buffer.substr(pos + 1)

		var json = JSON.new()
		if json.parse(msg) == OK:
			client_handle_message(json.data)

func client_handle_message(msg: Dictionary):
	var type = msg.get("type", "")

	match type:
		"welcome":
			client_display("[color=#2ECC71]%s[/color]" % msg.get("message", ""))

		"login_success":
			client_logged_in = true
			client_display("[color=#2ECC71]%s[/color]" % msg.get("message", ""))

		"character_created":
			client_has_character = true
			client_character_data = msg.get("character", {})
			update_action_bar()
			client_display("[color=#2ECC71]Character created![/color]")
			client_show_status()

		"location":
			var desc = msg.get("description", "")
			if map_display:
				map_display.clear()
				map_display.append_text(desc)

		"chat":
			client_display("[color=#4A90E2]%s:[/color] %s" % [msg.get("sender", ""), msg.get("message", "")])

		"error":
			client_display("[color=#E74C3C]Error: %s[/color]" % msg.get("message", ""))

		"combat_start":
			client_in_combat = true
			update_action_bar()
			client_display(msg.get("message", ""))
			client_display("[color=#FF6B6B]═══════════════════[/color]")
			client_display("[color=#95A5A6]Use Attack(Q), Defend(W), Flee(E)[/color]")

		"combat_message":
			client_display(msg.get("message", ""))

		"combat_update":
			var state = msg.get("combat_state", {})
			if not state.is_empty():
				var combat_status = "[color=#87CEEB]You:[/color] %d/%d HP | [color=#FF6B6B]%s:[/color] %d/%d HP" % [
					state.get("player_hp", 0), state.get("player_max_hp", 0),
					state.get("monster_name", "Enemy"), state.get("monster_hp", 0), state.get("monster_max_hp", 0)
				]
				client_display(combat_status)

		"combat_end":
			client_in_combat = false
			update_action_bar()
			if msg.get("victory", false):
				client_display("[color=#00FF00]═══ VICTORY! ═══[/color]")
				if msg.has("character"):
					client_character_data = msg.character
			elif msg.get("fled", false):
				client_display("[color=#FFD700]You escaped![/color]")
			else:
				client_display("[color=#FF0000]You were defeated![/color]")
				client_display("[color=#95A5A6]Respawning at Sanctuary...[/color]")
			client_display("[color=#FF6B6B]═══════════════════[/color]")

func _on_auto_connect():
	client_display("")
	client_display("[color=#F39C12]═══ Auto Setup ═══[/color]")

	client_connect()
	await get_tree().create_timer(0.5).timeout

	if not client_connected:
		client_display("[color=#E74C3C]Failed to connect[/color]")
		return

	client_display("Logging in...")
	client_send({"type": "login", "username": "TestPlayer"})
	await get_tree().create_timer(0.3).timeout

	client_display("Creating character...")
	client_send({"type": "create_character", "name": "Hero", "class": "Fighter"})
	await get_tree().create_timer(0.3).timeout

	client_display("")
	client_display("[color=#2ECC71]═══ Ready! ═══[/color]")
	client_display("Click outside input box, then use NUMPAD to move")
	client_display("Encounters will start combat automatically")

func _on_send_pressed():
	send_input()

func _on_input_submitted(_text: String):
	send_input()

func send_input():
	var text = client_input.text.strip_edges()
	client_input.clear()

	if text.is_empty():
		return

	client_display("[color=#F39C12]> %s[/color]" % text)

	var parts = text.split(" ", false)
	var cmd = parts[0].to_lower()

	# Combat commands
	if client_in_combat:
		match cmd:
			"attack", "a":
				client_send({"type": "combat", "command": "attack"})
				return
			"defend", "d":
				client_send({"type": "combat", "command": "defend"})
				return
			"flee", "f", "run":
				client_send({"type": "combat", "command": "flee"})
				return

	match cmd:
		"connect":
			client_connect()
		"login":
			if parts.size() > 1:
				client_send({"type": "login", "username": parts[1]})
		"create":
			if parts.size() > 2:
				client_send({"type": "create_character", "name": parts[1], "class": parts[2]})
		"say":
			if parts.size() > 1:
				client_send({"type": "chat", "message": " ".join(parts.slice(1))})
		"status":
			client_show_status()
		"help":
			client_show_help()
		"clear":
			client_output.clear()
		_:
			# If has character and not a known command, treat as chat
			if client_has_character and client_connected:
				client_send({"type": "chat", "message": text})
			else:
				client_display("Unknown: %s" % cmd)

func client_connect():
	var status = client_connection.get_status()

	if status == StreamPeerTCP.STATUS_CONNECTED:
		client_display("[color=#F39C12]Already connected[/color]")
		return

	if status == StreamPeerTCP.STATUS_CONNECTING:
		client_display("[color=#F39C12]Connecting...[/color]")
		return

	client_display("Connecting to localhost:%d..." % PORT)

	var err = client_connection.connect_to_host("127.0.0.1", PORT)
	if err != OK:
		client_display("[color=#E74C3C]Failed: %d[/color]" % err)

func client_send(data: Dictionary):
	if not client_connected:
		client_display("[color=#E74C3C]Not connected![/color]")
		return

	var json_str = JSON.stringify(data) + "\n"
	client_connection.put_data(json_str.to_utf8_buffer())

func client_show_status():
	if not client_has_character:
		client_display("No character")
		return

	var c = client_character_data
	var s = c.get("stats", {})
	client_display("""
[b][color=#4A90E2]%s[/color][/b] the %s (Lv %d)
HP: %d/%d | Mana: %d/%d | Gold: %d
STR:%d CON:%d DEX:%d INT:%d WIS:%d CHA:%d
""" % [
		c.get("name", "?"), c.get("class", "?"), c.get("level", 1),
		c.get("current_hp", 0), c.get("max_hp", 0),
		c.get("current_mana", 0), c.get("max_mana", 0), c.get("gold", 0),
		s.get("strength", 0), s.get("constitution", 0), s.get("dexterity", 0),
		s.get("intelligence", 0), s.get("wisdom", 0), s.get("charisma", 0)
	])

func client_show_help():
	client_display("""[b]Commands:[/b]
connect, login <name>, create <name> <class>
say <msg>, status, help, clear

[b]Movement:[/b] NUMPAD 1-9 (click outside input first)
[b]Combat:[/b] Q=Attack, W=Defend, E=Flee (or click buttons)
[b]Classes:[/b] Fighter, Wizard, Thief, Ranger, Barbarian, Paladin
""")

func server_display(text: String):
	if server_output:
		server_output.append_text(text + "\n")

func client_display(text: String):
	if client_output:
		client_output.append_text(text + "\n")
