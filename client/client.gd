# client.gd
# Client with action bar and hotkey support
extends Control

var connection = StreamPeerTCP.new()
var connected = false
var buffer = ""

@onready var game_output = $RootContainer/MainContainer/LeftPanel/GameOutput
@onready var chat_output = $RootContainer/MainContainer/LeftPanel/ChatOutput
@onready var map_display = $RootContainer/MainContainer/RightPanel/MapDisplay
@onready var input_field = $RootContainer/BottomBar/InputField
@onready var send_button = $RootContainer/BottomBar/SendButton
@onready var action_bar = $RootContainer/MainContainer/LeftPanel/ActionBar

var logged_in = false
var has_character = false
var character_data = {}
var username = ""
var last_move_time = 0.0
const MOVE_COOLDOWN = 0.5  # 2 moves per second

# Combat state
var in_combat = false

# Action bar configuration
var action_buttons: Array[Button] = []
var action_hotkeys = [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
var action_hotkey_labels = ["Q", "W", "E", "R", "1", "2", "3", "4", "5"]

# Action definitions - changes based on game state
# Each action has: {label, action_type, action_data, enabled}
var current_actions: Array[Dictionary] = []

func _ready():
	print("Client starting...")

	# Verify all UI nodes loaded
	print("Checking UI nodes...")
	if not game_output:
		print("ERROR: game_output not found!")
	else:
		print("✓ game_output found")

	if not chat_output:
		print("ERROR: chat_output not found!")
	else:
		print("✓ chat_output found")

	if not map_display:
		print("ERROR: map_display not found!")
	else:
		print("✓ map_display found")

	if not input_field:
		print("ERROR: input_field not found!")
	else:
		print("✓ input_field found")

	if not send_button:
		print("ERROR: send_button not found!")
	else:
		print("✓ send_button found")

	if not action_bar:
		print("ERROR: action_bar not found!")
	else:
		print("✓ action_bar found")
		setup_action_bar()

	send_button.pressed.connect(_on_send_button_pressed)
	# DON'T connect text_submitted - it fires on every character with Keep_editing_on_text_submit
	# input_field.text_submitted.connect(_on_input_submitted)

	# Instead, detect Enter key manually
	input_field.gui_input.connect(_on_input_gui_input)

	# Connect focus signals to show mode changes
	input_field.focus_entered.connect(_on_input_focus_entered)
	input_field.focus_exited.connect(_on_input_focus_exited)

	# Make clickable areas release focus when clicked
	if game_output:
		game_output.gui_input.connect(_on_clickable_area_clicked)
	if chat_output:
		chat_output.gui_input.connect(_on_clickable_area_clicked)
	if map_display:
		map_display.gui_input.connect(_on_clickable_area_clicked)

	display_game("[b][color=#4A90E2]Welcome to Phantasia Revival[/color][/b]")
	display_game("Type 'connect' to connect to the server")
	display_game("Type 'help' for commands")
	display_game("")
	display_game("[color=#95A5A6]Click in text box to chat/command - Click outside to move[/color]")
	display_game("[color=#95A5A6]Press Escape to toggle between modes[/color]")
	display_game("")

	# Initialize action bar to default state
	update_action_bar()

	# Inspector setting: Keep_editing_on_text_submit = true handles focus
	input_field.grab_focus()

func _process(_delta):
	# Poll connection
	connection.poll()

	var status = connection.get_status()

	# Escape to toggle focus
	if Input.is_action_just_pressed("ui_cancel"):
		if input_field.has_focus():
			input_field.release_focus()  # This will trigger focus_exited signal
		else:
			input_field.grab_focus()  # This will trigger focus_entered signal

	# Action bar hotkeys (only when input NOT focused)
	if not input_field.has_focus():
		for i in range(action_hotkeys.size()):
			if Input.is_physical_key_pressed(action_hotkeys[i]) and not Input.is_key_pressed(KEY_SHIFT):
				# Prevent repeated triggers
				if not get_meta("hotkey_%d_pressed" % i, false):
					set_meta("hotkey_%d_pressed" % i, true)
					trigger_action(i)
			else:
				set_meta("hotkey_%d_pressed" % i, false)

	# Numpad movement (only when input NOT focused and NOT in combat)
	if connected and has_character and not input_field.has_focus() and not in_combat:
		var current_time = Time.get_ticks_msec() / 1000.0

		if current_time - last_move_time >= MOVE_COOLDOWN:
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
				send_move(move_dir)
				last_move_time = current_time
	
	# Connection state
	if status == StreamPeerTCP.STATUS_CONNECTING:
		pass
	elif status == StreamPeerTCP.STATUS_CONNECTED:
		if not connected:
			connected = true
			display_game("[color=#2ECC71]✓ Connected to server![/color]")
		
		var available = connection.get_available_bytes()
		if available > 0:
			var data = connection.get_data(available)
			if data[0] == OK:
				buffer += data[1].get_string_from_utf8()
				process_buffer()
	elif status == StreamPeerTCP.STATUS_ERROR:
		if connected:
			display_game("[color=#E74C3C]Connection error![/color]")
			connected = false
			logged_in = false
			has_character = false
			in_combat = false
			update_action_bar()

# ===== ACTION BAR FUNCTIONS =====

func setup_action_bar():
	"""Initialize action bar buttons and connect signals"""
	action_buttons.clear()
	for i in range(9):
		var action_container = action_bar.get_node("Action%d" % (i + 1))
		if action_container:
			var button = action_container.get_node("Button")
			if button:
				action_buttons.append(button)
				# Connect button press with index
				button.pressed.connect(_on_action_button_pressed.bind(i))
	print("✓ Action bar setup complete: %d buttons" % action_buttons.size())

func update_action_bar():
	"""Update action bar based on current game state"""
	current_actions.clear()

	if in_combat:
		# Combat actions
		current_actions = [
			{"label": "Attack", "action_type": "combat", "action_data": "attack", "enabled": true},
			{"label": "Defend", "action_type": "combat", "action_data": "defend", "enabled": true},
			{"label": "Flee", "action_type": "combat", "action_data": "flee", "enabled": true},
			{"label": "Special", "action_type": "combat", "action_data": "special", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif has_character:
		# Exploration actions
		current_actions = [
			{"label": "Status", "action_type": "local", "action_data": "status", "enabled": true},
			{"label": "Help", "action_type": "local", "action_data": "help", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	else:
		# No character yet - minimal actions
		current_actions = [
			{"label": "Help", "action_type": "local", "action_data": "help", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]

	# Update button labels and enabled state
	for i in range(min(action_buttons.size(), current_actions.size())):
		var button = action_buttons[i]
		var action = current_actions[i]
		button.text = action.label
		button.disabled = not action.enabled

func _on_action_button_pressed(index: int):
	"""Handle action button click"""
	trigger_action(index)

func trigger_action(index: int):
	"""Execute an action by index"""
	if index < 0 or index >= current_actions.size():
		return

	var action = current_actions[index]
	if not action.enabled:
		return

	match action.action_type:
		"combat":
			send_combat_command(action.action_data)
		"local":
			execute_local_action(action.action_data)
		"server":
			send_to_server({"type": action.action_data})

func send_combat_command(command: String):
	"""Send a combat command to the server"""
	if not connected:
		display_game("[color=#E74C3C]Not connected![/color]")
		return
	if not in_combat:
		display_game("[color=#E74C3C]You are not in combat![/color]")
		return

	display_game("[color=#F39C12]> %s[/color]" % command)
	print("DEBUG: Sending combat command: %s" % command)
	send_to_server({"type": "combat", "command": command})

func execute_local_action(action: String):
	"""Execute a local action (doesn't require server)"""
	match action:
		"status":
			display_character_status()
		"help":
			show_help()

# ===== END ACTION BAR FUNCTIONS =====

func process_buffer():
	while "\n" in buffer:
		var pos = buffer.find("\n")
		var msg_str = buffer.substr(0, pos)
		buffer = buffer.substr(pos + 1)
		
		var json = JSON.new()
		if json.parse(msg_str) == OK:
			handle_server_message(json.data)

func handle_server_message(message: Dictionary):
	var msg_type = message.get("type", "")
	print("Received message type: %s" % msg_type)  # DEBUG
	
	match msg_type:
		"welcome":
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", ""))
			display_game("Type 'login <username>' to log in")
		
		"login_success":
			logged_in = true
			username = message.get("username", "")
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", ""))
			display_game("Type 'create <n> <class>' to create character")
			display_game("Classes: Fighter, Wizard, Thief, Ranger, Barbarian, Paladin")
		
		"character_created":
			has_character = true
			character_data = message.get("character", {})
			update_action_bar()
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", ""))
			display_game("")
			display_character_status()
		
		"location":
			# Location updates go directly to map display
			var desc = message.get("description", "")
			print("Location description length: %d" % desc.length())  # DEBUG
			
			# Display entire location message in map panel
			update_map(desc)
		
		"chat":
			# Chat messages go to chat output only
			var sender = message.get("sender", "Unknown")
			var text = message.get("message", "")
			print("Chat from %s: %s" % [sender, text])  # DEBUG
			display_chat("[color=#4A90E2]%s:[/color] %s" % [sender, text])
		
		"text":
			# Game events
			display_game(message.get("message", ""))
		
		"error":
			display_game("[color=#E74C3C]Error: %s[/color]" % message.get("message", ""))

		"combat_start":
			in_combat = true
			update_action_bar()
			display_game(message.get("message", ""))
			display_game("[color=#FF6B6B]═══════════════════[/color]")
			display_game("[color=#95A5A6]Use Attack (Q), Defend (W), or Flee (E)[/color]")

		"combat_message":
			display_game(message.get("message", ""))

		"combat_update":
			var state = message.get("combat_state", {})
			if not state.is_empty():
				var combat_status = "[color=#87CEEB]%s:[/color] %d/%d HP | [color=#FF6B6B]%s:[/color] %d/%d HP" % [
					state.player_name, state.player_hp, state.player_max_hp,
					state.monster_name, state.monster_hp, state.monster_max_hp
				]
				display_game(combat_status)

		"combat_end":
			in_combat = false
			update_action_bar()
			if message.get("victory", false):
				display_game("[color=#00FF00]═══ VICTORY! ═══[/color]")
				# Update character data
				if message.has("character"):
					character_data = message.character
			elif message.get("fled", false):
				display_game("[color=#FFD700]You escaped from combat![/color]")
			else:
				display_game("[color=#FF0000]You have been defeated![/color]")
				display_game("[color=#95A5A6]You awaken at the Sanctuary...[/color]")
			display_game("[color=#FF6B6B]═══════════════════[/color]")
		
func _on_send_button_pressed():
	send_input()

func _on_input_submitted(_text: String):
	# Not used anymore - causes issues with Keep_editing_on_text_submit
	pass

func _on_input_focus_entered():
	"""Input field gained focus - chat/command mode"""
	if has_character:
		display_game("[color=#95A5A6]Chat mode - type to send messages[/color]")

func _on_input_focus_exited():
	"""Input field lost focus - movement mode"""
	if has_character:
		display_game("[color=#95A5A6]Movement mode - use numpad to move[/color]")

func _on_clickable_area_clicked(event: InputEvent):
	"""When clicking on game output, chat output, or map - release focus from input"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if input_field and input_field.has_focus():
			input_field.release_focus()

func _on_input_gui_input(event: InputEvent):
	"""Detect Enter key press in input field"""
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			send_input()

func send_input():
	var text = input_field.text.strip_edges()
	input_field.clear()

	if text.is_empty():
		return

	# Determine if command or chat
	var command_keywords = ["help", "connect", "disconnect", "clear", "status", "login", "create"]
	var combat_keywords = ["attack", "a", "defend", "d", "flee", "f", "run"]
	var first_word = text.split(" ", false)[0].to_lower() if text.length() > 0 else ""
	var is_command = first_word in command_keywords
	var is_combat_command = first_word in combat_keywords

	# Handle combat commands when in combat
	if in_combat and is_combat_command:
		display_game("[color=#F39C12]> %s[/color]" % text)
		process_command(text)
		return

	# If connected and has character and not a command = chat
	if connected and has_character and not is_command and not is_combat_command:
		# Display locally immediately (your own message)
		display_chat("[color=#FFD700]%s:[/color] %s" % [username, text])
		# Send to server (will echo to others only)
		send_to_server({"type": "chat", "message": text})
		return

	# It's a command
	display_game("[color=#F39C12]> %s[/color]" % text)
	process_command(text)

func process_command(text: String):
	var parts = text.split(" ", false)
	if parts.is_empty():
		return
	
	var command = parts[0].to_lower()
	
	match command:
		
		"help":
			show_help()
		"connect":
			connect_to_server()
		"disconnect":
			disconnect_from_server()
		"clear":
			game_output.clear()
			chat_output.clear()
		"status":
			if has_character:
				display_character_status()
			else:
				display_game("You don't have a character yet")
		_:
			if not connected:
				display_game("[color=#E74C3C]Not connected. Type 'connect' first.[/color]")
				return
			
			match command:
				"login":
					if parts.size() < 2:
						display_game("Usage: login <username>")
						return
					send_to_server({"type": "login", "username": parts[1]})
				
				"create":
					if parts.size() < 3:
						display_game("Usage: create <n> <class>")
						display_game("Classes: Fighter, Wizard, Thief, Ranger, Barbarian, Paladin")
						return
					send_to_server({"type": "create_character", "name": parts[1], "class": parts[2]})
				"attack", "a":
					print("DEBUG: Typed attack, sending to server")
					send_to_server({"type": "combat", "command": "attack"})
				
				"defend", "d":
					send_to_server({"type": "combat", "command": "defend"})
				
				"flee", "f", "run":
					send_to_server({"type": "combat", "command": "flee"})
					
				_:
					display_game("Unknown command: %s (type 'help')" % command)

func connect_to_server():
	var status = connection.get_status()
	
	if status == StreamPeerTCP.STATUS_CONNECTED:
		display_game("[color=#F39C12]Already connected![/color]")
		return
	
	if status == StreamPeerTCP.STATUS_CONNECTING:
		display_game("[color=#F39C12]Connection in progress...[/color]")
		return
	
	display_game("Connecting to 127.0.0.1:9080...")
	
	var error = connection.connect_to_host("127.0.0.1", 9080)
	if error != OK:
		display_game("[color=#E74C3C]Failed! Error: %d[/color]" % error)
		return
	
	display_game("Waiting for connection...")

func disconnect_from_server():
	connection.disconnect_from_host()
	connected = false
	logged_in = false
	has_character = false
	username = ""
	display_game("[color=#95A5A6]Disconnected[/color]")

func send_to_server(data: Dictionary):
	if not connected:
		display_game("[color=#E74C3C]Not connected![/color]")
		return
	
	var json_str = JSON.stringify(data) + "\n"
	connection.put_data(json_str.to_utf8_buffer())

func send_move(direction: int):
	if not connected or not has_character:
		return
	
	send_to_server({"type": "move", "direction": direction})

func display_character_status():
	if not has_character:
		return
	
	var char = character_data
	var stats = char.get("stats", {})
	var text = """
[b]Character Status[/b]
Name: %s
Class: %s
Level: %d
HP: %d/%d (%s)
Mana: %d/%d
Gold: %d
Position: (%d, %d)

Stats:
  STR: %d  CON: %d  DEX: %d
  INT: %d  WIS: %d  CHA: %d
""" % [
		char.get("name", "Unknown"),
		char.get("class", "Unknown"),
		char.get("level", 1),
		char.get("current_hp", 0),
		char.get("max_hp", 0),
		char.get("health_state", "Unknown"),
		char.get("current_mana", 0),
		char.get("max_mana", 0),
		char.get("gold", 0),
		char.get("x", 0),
		char.get("y", 0),
		stats.get("strength", 0),
		stats.get("constitution", 0),
		stats.get("dexterity", 0),
		stats.get("intelligence", 0),
		stats.get("wisdom", 0),
		stats.get("charisma", 0)
	]
	
	display_game(text)

func show_help():
	var help_text = """
[b]Available Commands:[/b]

[color=#4A90E2]Connection:[/color]
  connect - Connect to server
  disconnect - Disconnect
  login <username> - Log in
  
[color=#4A90E2]Character:[/color]
  create <n> <class> - Create character
  status - Show stats
  
[color=#4A90E2]Movement:[/color]
  Press Escape to toggle movement mode
  Use NUMPAD: 7 8 9 = NW N NE
              4 5 6 = W stay E
              1 2 3 = SW S SE
  
[color=#4A90E2]Chat:[/color]
  Just type and press Enter!
  Numbers 1-9 can be typed in chat
  
[color=#4A90E2]Other:[/color]
  help - This help
  clear - Clear screens

[b][color=#90EE90]TIP:[/color][/b] Press Escape to switch between chat and movement!
"""
	display_game(help_text)

func display_game(text: String):
	"""Display game events and system messages"""
	print("display_game called: %s" % text.substr(0, 50))  # DEBUG - first 50 chars
	if game_output:
		game_output.append_text(text + "\n")
	else:
		print("ERROR: game_output is null!")

func display_chat(text: String):
	"""Display chat messages"""
	print("display_chat called: %s" % text)  # DEBUG
	if chat_output:
		chat_output.append_text(text + "\n")
	else:
		print("ERROR: chat_output is null!")

func update_map(map_text: String):
	"""Update the map display"""
	print("update_map called, text length: %d" % map_text.length())  # DEBUG
	if map_display:
		map_display.clear()
		map_display.append_text(map_text)
	else:
		print("ERROR: map_display is null!")
