# client.gd
# Client with account system, character selection, and permadeath handling
extends Control

var connection = StreamPeerTCP.new()
var connected = false
var buffer = ""

# Game states
enum GameState {
	DISCONNECTED,
	CONNECTED,
	LOGIN_SCREEN,
	CHARACTER_SELECT,
	PLAYING,
	DEAD
}
var game_state = GameState.DISCONNECTED

# UI References - Main game
@onready var game_output = $RootContainer/MainContainer/LeftPanel/GameOutput
@onready var chat_output = $RootContainer/MainContainer/LeftPanel/ChatOutput
@onready var map_display = $RootContainer/MainContainer/RightPanel/MapDisplay
@onready var input_field = $RootContainer/BottomBar/InputField
@onready var send_button = $RootContainer/BottomBar/SendButton
@onready var action_bar = $RootContainer/MainContainer/LeftPanel/ActionBar
@onready var enemy_health_bar = $RootContainer/MainContainer/LeftPanel/EnemyHealthBar
@onready var player_health_bar = $RootContainer/MainContainer/RightPanel/PlayerHealthBar
@onready var player_level_label = $RootContainer/MainContainer/RightPanel/PlayerLevel

# UI References - Login Panel
@onready var login_panel = $LoginPanel
@onready var username_field = $LoginPanel/VBox/UsernameField
@onready var password_field = $LoginPanel/VBox/PasswordField
@onready var login_button = $LoginPanel/VBox/ButtonContainer/LoginButton
@onready var register_button = $LoginPanel/VBox/ButtonContainer/RegisterButton
@onready var login_status = $LoginPanel/VBox/StatusLabel

# UI References - Character Select Panel
@onready var char_select_panel = $CharacterSelectPanel
@onready var char_list_container = $CharacterSelectPanel/VBox/CharacterList
@onready var create_char_button = $CharacterSelectPanel/VBox/ButtonContainer/CreateButton
@onready var char_select_status = $CharacterSelectPanel/VBox/StatusLabel
@onready var leaderboard_button = $CharacterSelectPanel/VBox/ButtonContainer/LeaderboardButton

# UI References - Character Creation Panel
@onready var char_create_panel = $CharacterCreatePanel
@onready var new_char_name_field = $CharacterCreatePanel/VBox/NameField
@onready var class_option = $CharacterCreatePanel/VBox/ClassOption
@onready var confirm_create_button = $CharacterCreatePanel/VBox/ButtonContainer/ConfirmButton
@onready var cancel_create_button = $CharacterCreatePanel/VBox/ButtonContainer/CancelButton
@onready var char_create_status = $CharacterCreatePanel/VBox/StatusLabel

# UI References - Death Panel
@onready var death_panel = $DeathPanel
@onready var death_message = $DeathPanel/VBox/DeathMessage
@onready var death_stats = $DeathPanel/VBox/DeathStats
@onready var continue_button = $DeathPanel/VBox/ContinueButton

# UI References - Leaderboard Panel
@onready var leaderboard_panel = $LeaderboardPanel
@onready var leaderboard_list = $LeaderboardPanel/VBox/LeaderboardList
@onready var close_leaderboard_button = $LeaderboardPanel/VBox/CloseButton

# Account data
var username = ""
var account_id = ""
var character_list = []
var can_create_character = true

# Character data
var character_data = {}
var has_character = false
var last_move_time = 0.0
const MOVE_COOLDOWN = 0.5

# Combat state
var in_combat = false

# Action bar
var action_buttons: Array[Button] = []
var action_hotkeys = [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
var current_actions: Array[Dictionary] = []

# Enemy tracking
var known_enemy_hp: Dictionary = {}
var current_enemy_name: String = ""
var current_enemy_level: int = 0
var damage_dealt_to_current_enemy: int = 0

func _ready():
	# Setup action bar
	if action_bar:
		setup_action_bar()

	# Connect main UI signals
	send_button.pressed.connect(_on_send_button_pressed)
	input_field.gui_input.connect(_on_input_gui_input)
	input_field.focus_entered.connect(_on_input_focus_entered)
	input_field.focus_exited.connect(_on_input_focus_exited)

	# Clickable areas release focus
	if game_output:
		game_output.gui_input.connect(_on_clickable_area_clicked)
	if chat_output:
		chat_output.gui_input.connect(_on_clickable_area_clicked)
	if map_display:
		map_display.gui_input.connect(_on_clickable_area_clicked)

	# Connect login panel signals
	if login_button:
		login_button.pressed.connect(_on_login_button_pressed)
	if register_button:
		register_button.pressed.connect(_on_register_button_pressed)
	if password_field:
		password_field.text_submitted.connect(_on_password_submitted)

	# Connect character select signals
	if create_char_button:
		create_char_button.pressed.connect(_on_create_char_button_pressed)
	if leaderboard_button:
		leaderboard_button.pressed.connect(_on_leaderboard_button_pressed)

	# Connect character creation signals
	if confirm_create_button:
		confirm_create_button.pressed.connect(_on_confirm_create_pressed)
	if cancel_create_button:
		cancel_create_button.pressed.connect(_on_cancel_create_pressed)

	# Connect death panel signals
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)

	# Connect leaderboard signals
	if close_leaderboard_button:
		close_leaderboard_button.pressed.connect(_on_close_leaderboard_pressed)

	# Setup class options
	if class_option:
		class_option.clear()
		for cls in ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]:
			class_option.add_item(cls)

	# Initial display
	display_game("[b][color=#4A90E2]Welcome to Phantasia Revival[/color][/b]")
	display_game("Connecting to server...")

	# Initialize UI state
	update_action_bar()
	show_login_panel()

	# Auto-connect
	connect_to_server()

func _process(_delta):
	connection.poll()
	var status = connection.get_status()

	# Escape to toggle focus (only in playing state)
	if game_state == GameState.PLAYING:
		if Input.is_action_just_pressed("ui_cancel"):
			if input_field.has_focus():
				input_field.release_focus()
			else:
				input_field.grab_focus()

	# Action bar hotkeys (only when input NOT focused and playing)
	if game_state == GameState.PLAYING and not input_field.has_focus():
		for i in range(action_hotkeys.size()):
			if Input.is_physical_key_pressed(action_hotkeys[i]) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("hotkey_%d_pressed" % i, false):
					set_meta("hotkey_%d_pressed" % i, true)
					trigger_action(i)
			else:
				set_meta("hotkey_%d_pressed" % i, false)

	# Numpad movement (only when playing and not in combat)
	if connected and has_character and not input_field.has_focus() and not in_combat:
		if game_state == GameState.PLAYING:
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
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not connected:
			connected = true
			game_state = GameState.CONNECTED
			display_game("[color=#2ECC71]Connected to server![/color]")

		var available = connection.get_available_bytes()
		if available > 0:
			var data = connection.get_data(available)
			if data[0] == OK:
				buffer += data[1].get_string_from_utf8()
				process_buffer()

	elif status == StreamPeerTCP.STATUS_ERROR:
		if connected:
			display_game("[color=#E74C3C]Connection error![/color]")
			reset_connection_state()

# ===== UI PANEL MANAGEMENT =====

func hide_all_panels():
	if login_panel:
		login_panel.visible = false
	if char_select_panel:
		char_select_panel.visible = false
	if char_create_panel:
		char_create_panel.visible = false
	if death_panel:
		death_panel.visible = false
	if leaderboard_panel:
		leaderboard_panel.visible = false

func show_login_panel():
	hide_all_panels()
	if login_panel:
		login_panel.visible = true
		if username_field:
			username_field.grab_focus()

func show_character_select_panel():
	hide_all_panels()
	if char_select_panel:
		char_select_panel.visible = true
	update_character_list_display()

func show_character_create_panel():
	hide_all_panels()
	if char_create_panel:
		char_create_panel.visible = true
		if new_char_name_field:
			new_char_name_field.clear()
			new_char_name_field.grab_focus()
		if char_create_status:
			char_create_status.text = ""

func show_death_panel(char_name: String, level: int, experience: int, cause: String, rank: int):
	hide_all_panels()
	if death_panel:
		death_panel.visible = true
	if death_message:
		death_message.text = "[center][color=#FF0000][b]%s HAS FALLEN[/b][/color]\n\nSlain by %s[/center]" % [char_name.to_upper(), cause]
	if death_stats:
		death_stats.text = "[center]Level: %d\nExperience: %d\nLeaderboard Rank: #%d[/center]" % [level, experience, rank]

func show_leaderboard_panel():
	if leaderboard_panel:
		leaderboard_panel.visible = true
	send_to_server({"type": "get_leaderboard", "limit": 20})

func show_game_ui():
	hide_all_panels()
	game_state = GameState.PLAYING

func update_character_list_display():
	if not char_list_container:
		return

	# Clear existing character buttons
	for child in char_list_container.get_children():
		child.queue_free()

	# Add character buttons
	for char_info in character_list:
		var btn = Button.new()
		btn.text = "%s - Level %d %s" % [char_info.name, char_info.level, char_info["class"]]
		btn.custom_minimum_size = Vector2(0, 40)
		btn.pressed.connect(_on_character_selected.bind(char_info.name))
		char_list_container.add_child(btn)

	# Update create button state
	if create_char_button:
		create_char_button.disabled = not can_create_character
		if not can_create_character:
			create_char_button.text = "Max Characters (3)"
		else:
			create_char_button.text = "Create New Character"

func update_leaderboard_display(entries: Array):
	if not leaderboard_list:
		return

	leaderboard_list.clear()
	leaderboard_list.append_text("[center][b]HALL OF FALLEN HEROES[/b][/center]\n\n")

	if entries.is_empty():
		leaderboard_list.append_text("[center][color=#666666]No entries yet. Be the first![/color][/center]")
		return

	for entry in entries:
		var rank = entry.get("rank", 0)
		var name = entry.get("character_name", "Unknown")
		var cls = entry.get("class", "Unknown")
		var level = entry.get("level", 1)
		var exp = entry.get("experience", 0)
		var cause = entry.get("cause_of_death", "Unknown")

		var color = "#FFFFFF"
		if rank == 1:
			color = "#FFD700"  # Gold
		elif rank == 2:
			color = "#C0C0C0"  # Silver
		elif rank == 3:
			color = "#CD7F32"  # Bronze

		leaderboard_list.append_text("[color=%s]#%d %s[/color]\n" % [color, rank, name])
		leaderboard_list.append_text("   Level %d %s - %d XP\n" % [level, cls, exp])
		leaderboard_list.append_text("   [color=#666666]Slain by: %s[/color]\n\n" % cause)

# ===== LOGIN/REGISTER HANDLERS =====

func _on_login_button_pressed():
	var user = username_field.text.strip_edges()
	var passwd = password_field.text

	if user.is_empty() or passwd.is_empty():
		if login_status:
			login_status.text = "[color=#E74C3C]Enter username and password[/color]"
		return

	if login_status:
		login_status.text = "Logging in..."

	send_to_server({
		"type": "login",
		"username": user,
		"password": passwd
	})

func _on_register_button_pressed():
	var user = username_field.text.strip_edges()
	var passwd = password_field.text

	if user.is_empty() or passwd.is_empty():
		if login_status:
			login_status.text = "[color=#E74C3C]Enter username and password[/color]"
		return

	if login_status:
		login_status.text = "Creating account..."

	send_to_server({
		"type": "register",
		"username": user,
		"password": passwd
	})

func _on_password_submitted(_text: String):
	_on_login_button_pressed()

# ===== CHARACTER SELECT HANDLERS =====

func _on_character_selected(char_name: String):
	if char_select_status:
		char_select_status.text = "Loading %s..." % char_name

	send_to_server({
		"type": "select_character",
		"name": char_name
	})

func _on_create_char_button_pressed():
	show_character_create_panel()

func _on_leaderboard_button_pressed():
	show_leaderboard_panel()

# ===== CHARACTER CREATION HANDLERS =====

func _on_confirm_create_pressed():
	var char_name = new_char_name_field.text.strip_edges()
	var char_class = class_option.get_item_text(class_option.selected)

	if char_name.is_empty():
		if char_create_status:
			char_create_status.text = "[color=#E74C3C]Enter a character name[/color]"
		return

	if char_create_status:
		char_create_status.text = "Creating character..."

	send_to_server({
		"type": "create_character",
		"name": char_name,
		"class": char_class
	})

func _on_cancel_create_pressed():
	show_character_select_panel()

# ===== DEATH PANEL HANDLERS =====

func _on_continue_pressed():
	game_state = GameState.CHARACTER_SELECT
	show_character_select_panel()

# ===== LEADERBOARD HANDLERS =====

func _on_close_leaderboard_pressed():
	if leaderboard_panel:
		leaderboard_panel.visible = false

# ===== ACTION BAR FUNCTIONS =====

func setup_action_bar():
	action_buttons.clear()
	for i in range(9):
		var action_container = action_bar.get_node("Action%d" % (i + 1))
		if action_container:
			var button = action_container.get_node("Button")
			if button:
				action_buttons.append(button)
				button.pressed.connect(_on_action_button_pressed.bind(i))

func update_action_bar():
	current_actions.clear()

	if in_combat:
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
		current_actions = [
			{"label": "Status", "action_type": "local", "action_data": "status", "enabled": true},
			{"label": "Help", "action_type": "local", "action_data": "help", "enabled": true},
			{"label": "Rest", "action_type": "server", "action_data": "rest", "enabled": true},
			{"label": "Leaders", "action_type": "local", "action_data": "leaderboard", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "SwitchChr", "action_type": "local", "action_data": "logout_character", "enabled": true},
			{"label": "Logout", "action_type": "local", "action_data": "logout_account", "enabled": true},
		]
	else:
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

	for i in range(min(action_buttons.size(), current_actions.size())):
		var button = action_buttons[i]
		var action = current_actions[i]
		button.text = action.label
		button.disabled = not action.enabled

func _on_action_button_pressed(index: int):
	trigger_action(index)

func trigger_action(index: int):
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
	if not connected:
		display_game("[color=#E74C3C]Not connected![/color]")
		return
	if not in_combat:
		display_game("[color=#E74C3C]You are not in combat![/color]")
		return

	display_game("[color=#F39C12]> %s[/color]" % command)
	send_to_server({"type": "combat", "command": command})

func execute_local_action(action: String):
	match action:
		"status":
			display_character_status()
		"help":
			show_help()
		"leaderboard":
			show_leaderboard_panel()
		"logout_character":
			logout_character()
		"logout_account":
			logout_account()

func logout_character():
	"""Logout of current character, return to character select"""
	if not connected:
		return
	display_game("[color=#F39C12]Switching character...[/color]")
	send_to_server({"type": "logout_character"})

func logout_account():
	"""Logout of account completely"""
	if not connected:
		return
	display_game("[color=#F39C12]Logging out...[/color]")
	send_to_server({"type": "logout_account"})

# ===== HP BAR FUNCTIONS =====

func get_hp_color(percent: float) -> Color:
	if percent > 50:
		var t = (percent - 50) / 50.0
		return Color(1.0 - t * 0.8, 0.8, 0.2, 1.0)
	else:
		var t = percent / 50.0
		return Color(0.8, 0.1 + t * 0.7, 0.1, 1.0)

func update_player_level():
	if not player_level_label or not has_character:
		return
	var level = character_data.get("level", 1)
	player_level_label.text = "Level %d" % level

func update_player_hp_bar():
	if not player_health_bar or not has_character:
		return

	var current_hp = character_data.get("current_hp", 0)
	var max_hp = character_data.get("max_hp", 1)
	var percent = (float(current_hp) / float(max_hp)) * 100.0

	var fill = player_health_bar.get_node("Fill")
	var label = player_health_bar.get_node("HPLabel")

	if fill:
		fill.anchor_right = percent / 100.0
		var style = fill.get_theme_stylebox("panel").duplicate()
		style.bg_color = get_hp_color(percent)
		fill.add_theme_stylebox_override("panel", style)

	if label:
		label.text = "HP: %d/%d" % [current_hp, max_hp]

func update_enemy_hp_bar(enemy_name: String, enemy_level: int, damage_dealt: int):
	if not enemy_health_bar:
		return

	var enemy_key = "%s_%d" % [enemy_name, enemy_level]
	var label_node = enemy_health_bar.get_node("Label")
	var bar_container = enemy_health_bar.get_node("BarContainer")

	if label_node:
		label_node.text = "%s:" % enemy_name

	if not bar_container:
		return

	var fill = bar_container.get_node("Fill")
	var hp_label = bar_container.get_node("HPLabel")

	if known_enemy_hp.has(enemy_key):
		var suspected_max = known_enemy_hp[enemy_key]
		var suspected_current = max(0, suspected_max - damage_dealt)
		var percent = (float(suspected_current) / float(suspected_max)) * 100.0

		if fill:
			fill.anchor_right = percent / 100.0
		if hp_label:
			hp_label.text = "%d/%d" % [suspected_current, suspected_max]
	else:
		if fill:
			fill.anchor_right = 1.0
		if hp_label:
			hp_label.text = "???"

func show_enemy_hp_bar(show: bool):
	if enemy_health_bar:
		enemy_health_bar.visible = show

func record_enemy_defeated(enemy_name: String, enemy_level: int, total_damage: int):
	var enemy_key = "%s_%d" % [enemy_name, enemy_level]
	known_enemy_hp[enemy_key] = total_damage

func parse_damage_dealt(msg: String) -> int:
	var regex = RegEx.new()
	regex.compile("deal (\\d+) damage")
	var result = regex.search(msg)
	if result:
		return int(result.get_string(1))
	return 0

# ===== MESSAGE PROCESSING =====

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

	match msg_type:
		"welcome":
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", ""))
			game_state = GameState.LOGIN_SCREEN

		"register_success":
			if login_status:
				login_status.text = "[color=#2ECC71]Account created! Please log in.[/color]"

		"register_failed":
			if login_status:
				login_status.text = "[color=#E74C3C]%s[/color]" % message.get("reason", "Registration failed")

		"login_success":
			username = message.get("username", "")
			display_game("[color=#2ECC71]Logged in as %s[/color]" % username)
			game_state = GameState.CHARACTER_SELECT

		"login_failed":
			if login_status:
				login_status.text = "[color=#E74C3C]%s[/color]" % message.get("reason", "Login failed")

		"character_list":
			character_list = message.get("characters", [])
			can_create_character = message.get("can_create", true)
			show_character_select_panel()

		"character_loaded":
			has_character = true
			character_data = message.get("character", {})
			show_game_ui()
			update_action_bar()
			update_player_level()
			update_player_hp_bar()
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", ""))
			display_character_status()

		"character_created":
			has_character = true
			character_data = message.get("character", {})
			show_game_ui()
			update_action_bar()
			update_player_level()
			update_player_hp_bar()
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", ""))
			display_character_status()

		"character_deleted":
			display_game("[color=#F39C12]%s[/color]" % message.get("message", "Character deleted"))

		"logout_character_success":
			has_character = false
			in_combat = false
			character_data = {}
			game_state = GameState.CHARACTER_SELECT
			update_action_bar()
			show_enemy_hp_bar(false)
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", "Logged out of character"))

		"logout_account_success":
			has_character = false
			in_combat = false
			character_data = {}
			character_list = []
			username = ""
			game_state = GameState.LOGIN_SCREEN
			update_action_bar()
			show_enemy_hp_bar(false)
			show_login_panel()
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", "Logged out"))

		"permadeath":
			game_state = GameState.DEAD
			has_character = false
			in_combat = false
			character_data = {}
			show_death_panel(
				message.get("character_name", "Unknown"),
				message.get("level", 1),
				message.get("experience", 0),
				message.get("cause_of_death", "Unknown"),
				message.get("leaderboard_rank", 0)
			)
			update_action_bar()
			show_enemy_hp_bar(false)

		"leaderboard":
			update_leaderboard_display(message.get("entries", []))

		"location":
			var desc = message.get("description", "")
			if not in_combat:
				game_output.clear()
			update_map(desc)

		"chat":
			var sender = message.get("sender", "Unknown")
			var text = message.get("message", "")
			display_chat("[color=#4A90E2]%s:[/color] %s" % [sender, text])

		"text":
			display_game(message.get("message", ""))

		"character_update":
			if message.has("character"):
				character_data = message.character
				update_player_level()
				update_player_hp_bar()

		"error":
			var error_msg = message.get("message", "Unknown error")
			display_game("[color=#E74C3C]Error: %s[/color]" % error_msg)
			# Update status labels if on relevant screen
			if char_create_status and char_create_panel.visible:
				char_create_status.text = "[color=#E74C3C]%s[/color]" % error_msg
			if char_select_status and char_select_panel.visible:
				char_select_status.text = "[color=#E74C3C]%s[/color]" % error_msg

		"combat_start":
			in_combat = true
			update_action_bar()
			display_game(message.get("message", ""))

			var combat_state = message.get("combat_state", {})
			current_enemy_name = combat_state.get("monster_name", "Enemy")
			current_enemy_level = combat_state.get("monster_level", 1)
			damage_dealt_to_current_enemy = 0

			show_enemy_hp_bar(true)
			update_enemy_hp_bar(current_enemy_name, current_enemy_level, 0)

		"combat_message":
			var combat_msg = message.get("message", "")
			display_game(combat_msg)

			var damage = parse_damage_dealt(combat_msg)
			if damage > 0:
				damage_dealt_to_current_enemy += damage
				update_enemy_hp_bar(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy)

		"combat_update":
			var state = message.get("combat_state", {})
			if not state.is_empty():
				character_data["current_hp"] = state.get("player_hp", character_data.get("current_hp", 0))
				character_data["max_hp"] = state.get("player_max_hp", character_data.get("max_hp", 1))
				update_player_hp_bar()

		"combat_end":
			in_combat = false
			update_action_bar()

			if message.get("victory", false):
				if damage_dealt_to_current_enemy > 0:
					record_enemy_defeated(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy)
				if message.has("character"):
					character_data = message.character
					update_player_level()
					update_player_hp_bar()
			elif message.get("fled", false):
				display_game("[color=#FFD700]You escaped from combat![/color]")
			else:
				# Defeat handled by permadeath message
				pass

			show_enemy_hp_bar(false)
			current_enemy_name = ""
			current_enemy_level = 0
			damage_dealt_to_current_enemy = 0

# ===== INPUT HANDLING =====

func _on_send_button_pressed():
	send_input()

func _on_input_focus_entered():
	if has_character and game_state == GameState.PLAYING:
		display_game("[color=#95A5A6]Chat mode - type to send messages[/color]")

func _on_input_focus_exited():
	if has_character and game_state == GameState.PLAYING:
		display_game("[color=#95A5A6]Movement mode - use numpad to move[/color]")

func _on_clickable_area_clicked(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if input_field and input_field.has_focus():
			input_field.release_focus()

func _on_input_gui_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			send_input()

func send_input():
	var text = input_field.text.strip_edges()
	input_field.clear()

	if text.is_empty():
		return

	# Commands
	var command_keywords = ["help", "clear", "status"]
	var combat_keywords = ["attack", "a", "defend", "d", "flee", "f", "run"]
	var first_word = text.split(" ", false)[0].to_lower() if text.length() > 0 else ""
	var is_command = first_word in command_keywords
	var is_combat_command = first_word in combat_keywords

	if in_combat and is_combat_command:
		display_game("[color=#F39C12]> %s[/color]" % text)
		process_command(text)
		return

	if connected and has_character and not is_command and not is_combat_command:
		display_chat("[color=#FFD700]%s:[/color] %s" % [username, text])
		send_to_server({"type": "chat", "message": text})
		return

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
		"clear":
			game_output.clear()
			chat_output.clear()
		"status":
			if has_character:
				display_character_status()
			else:
				display_game("You don't have a character yet")
		"attack", "a":
			send_to_server({"type": "combat", "command": "attack"})
		"defend", "d":
			send_to_server({"type": "combat", "command": "defend"})
		"flee", "f", "run":
			send_to_server({"type": "combat", "command": "flee"})
		_:
			display_game("Unknown command: %s (type 'help')" % command)

# ===== CONNECTION FUNCTIONS =====

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

func reset_connection_state():
	connected = false
	has_character = false
	in_combat = false
	username = ""
	character_data = {}
	character_list = []
	game_state = GameState.DISCONNECTED
	update_action_bar()
	show_login_panel()

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

# ===== DISPLAY FUNCTIONS =====

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
Monsters Killed: %d

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
		char.get("monsters_killed", 0),
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

[color=#4A90E2]Movement:[/color]
  Press Escape to toggle movement mode
  Use NUMPAD: 7 8 9 = NW N NE
              4 5 6 = W stay E
              1 2 3 = SW S SE

[color=#4A90E2]Chat:[/color]
  Just type and press Enter!

[color=#4A90E2]Actions:[/color]
  Q/W/E/R or 1-5 for action bar

[color=#4A90E2]Other:[/color]
  help - This help
  status - Show stats
  clear - Clear screens

[b][color=#FF6666]WARNING: PERMADEATH IS ENABLED![/color][/b]
If you die, your character is gone forever!
"""
	display_game(help_text)

func display_game(text: String):
	if game_output:
		game_output.append_text(text + "\n")

func display_chat(text: String):
	if chat_output:
		chat_output.append_text(text + "\n")

func update_map(map_text: String):
	if map_display:
		map_display.clear()
		map_display.append_text(map_text)
