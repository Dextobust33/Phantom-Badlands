# client.gd
# Client with account system, character selection, and permadeath handling
extends Control

var connection = StreamPeerTCP.new()
var connected = false
var buffer = ""

# Connection settings
var server_ip: String = "localhost"
var server_port: int = 9080
var saved_connections: Array = []  # Array of {name, ip, port}
const CONNECTION_CONFIG_PATH = "user://connection_settings.json"
const KEYBIND_CONFIG_PATH = "user://keybinds.json"

# Keybind configuration
var default_keybinds = {
	# Action bar (indices 0-9)
	"action_0": KEY_SPACE,  # Primary action
	"action_1": KEY_Q,
	"action_2": KEY_W,
	"action_3": KEY_E,
	"action_4": KEY_R,
	"action_5": KEY_1,
	"action_6": KEY_2,
	"action_7": KEY_3,
	"action_8": KEY_4,
	"action_9": KEY_5,
	# Movement (8 directions + hunt)
	"move_1": KEY_KP_1,      # SW
	"move_2": KEY_KP_2,      # S
	"move_3": KEY_KP_3,      # SE
	"move_4": KEY_KP_4,      # W
	"move_6": KEY_KP_6,      # E
	"move_7": KEY_KP_7,      # NW
	"move_8": KEY_KP_8,      # N
	"move_9": KEY_KP_9,      # NE
	"hunt": KEY_KP_5,        # Hunt
	# Alternative movement (arrow keys)
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
	# Chat
	"chat_focus": KEY_ENTER
}
var keybinds: Dictionary = {}  # Active keybinds (loaded from file or defaults)

# Settings mode
var settings_mode: bool = false
var settings_submenu: String = ""  # "", "action_keys", "movement_keys"
var rebinding_action: String = ""  # Key being rebound (empty = not rebinding)

# Combat background color
var default_game_output_stylebox: StyleBox = null
var current_combat_bg_color: String = ""
var pending_combat_bg_color: String = ""  # Color to apply after ASCII art clears

# Connection panel (created dynamically)
var connection_panel: Panel = null
var server_ip_field: LineEdit = null
var server_port_field: LineEdit = null
var saved_connections_list: ItemList = null
var connect_button: Button = null
var save_connection_button: Button = null
var delete_connection_button: Button = null

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
@onready var game_output = $RootContainer/MainContainer/LeftPanel/GameOutputContainer/GameOutput
@onready var game_output_container = $RootContainer/MainContainer/LeftPanel/GameOutputContainer
@onready var buff_display_label = $RootContainer/MainContainer/LeftPanel/GameOutputContainer/BuffDisplayLabel
@onready var chat_output = $RootContainer/MainContainer/LeftPanel/ChatOutput
@onready var map_display = $RootContainer/MainContainer/RightPanel/MapDisplay
@onready var input_field = $RootContainer/BottomBar/InputField
@onready var send_button = $RootContainer/BottomBar/SendButton
@onready var action_bar = $RootContainer/MainContainer/LeftPanel/ActionBar
@onready var enemy_health_bar = $RootContainer/MainContainer/LeftPanel/EnemyHealthBar
@onready var player_health_bar = $RootContainer/MainContainer/RightPanel/PlayerHealthBar
@onready var resource_bar = $RootContainer/MainContainer/RightPanel/ResourceBar
@onready var player_xp_bar = $RootContainer/MainContainer/RightPanel/PlayerXPBar
@onready var player_level_label = $RootContainer/MainContainer/RightPanel/LevelRow/PlayerLevel
@onready var gold_label = $RootContainer/MainContainer/RightPanel/CurrencyDisplay/GoldContainer/GoldLabel
@onready var gem_label = $RootContainer/MainContainer/RightPanel/CurrencyDisplay/GemContainer/GemLabel
@onready var music_toggle = $RootContainer/MainContainer/RightPanel/LevelRow/MusicToggle
@onready var online_players_list = $RootContainer/MainContainer/RightPanel/OnlinePlayersList
@onready var online_players_label = $RootContainer/MainContainer/RightPanel/OnlinePlayersLabel
@onready var movement_pad = $RootContainer/MainContainer/RightPanel/MovementPad

# UI References - Login Panel
@onready var login_panel = $LoginPanel
@onready var username_field = $LoginPanel/VBox/UsernameField
@onready var password_field = $LoginPanel/VBox/PasswordField
@onready var confirm_password_field = $LoginPanel/VBox/ConfirmPasswordField
@onready var login_button = $LoginPanel/VBox/ButtonContainer/LoginButton
@onready var register_button = $LoginPanel/VBox/ButtonContainer/RegisterButton
@onready var login_status = $LoginPanel/VBox/StatusLabel

# UI References - Character Select Panel
@onready var char_select_panel = $CharacterSelectPanel
@onready var char_list_container = $CharacterSelectPanel/VBox/CharacterList
@onready var create_char_button = $CharacterSelectPanel/VBox/ButtonContainer/CreateButton
@onready var char_select_status = $CharacterSelectPanel/VBox/StatusLabel
@onready var leaderboard_button = $CharacterSelectPanel/VBox/ButtonContainer/LeaderboardButton
@onready var change_password_button = $CharacterSelectPanel/VBox/AccountContainer/ChangePasswordButton
@onready var char_select_logout_button = $CharacterSelectPanel/VBox/AccountContainer/LogoutButton

# UI References - Character Creation Panel
@onready var char_create_panel = $CharacterCreatePanel
@onready var new_char_name_field = $CharacterCreatePanel/VBox/NameField
@onready var race_option = $CharacterCreatePanel/VBox/RaceOption
@onready var race_description = $CharacterCreatePanel/VBox/RaceDescription
@onready var class_option = $CharacterCreatePanel/VBox/ClassOption
@onready var class_description = $CharacterCreatePanel/VBox/ClassDescription
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

# UI References - Player Info Popup
@onready var player_info_panel = $PlayerInfoPanel
@onready var player_info_content = $PlayerInfoPanel/VBox/PlayerInfoContent
@onready var close_player_info_button = $PlayerInfoPanel/VBox/CloseButton

# UI References - Ability Input Popup (created dynamically)
var ability_popup: Panel = null
var ability_popup_title: Label = null
var ability_popup_description: Label = null
var ability_popup_resource_label: Label = null
var ability_popup_input: LineEdit = null
var ability_popup_confirm: Button = null
var ability_popup_cancel: Button = null

# UI References - Gambling Popup (created dynamically)
var gamble_popup: Panel = null
var gamble_popup_title: Label = null
var gamble_popup_gold_label: Label = null
var gamble_popup_range_label: Label = null
var gamble_popup_input: LineEdit = null
var gamble_popup_confirm: Button = null
var gamble_popup_cancel: Button = null
var gamble_min_bet: int = 0
var gamble_max_bet: int = 0

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
const MAP_BASE_FONT_SIZE = 14  # Base font size at 720p height
const MAP_MIN_FONT_SIZE = 10
const MAP_MAX_FONT_SIZE = 64  # Allow larger scaling for fullscreen
const GAME_OUTPUT_BASE_FONT_SIZE = 14
const GAME_OUTPUT_MIN_FONT_SIZE = 12
const GAME_OUTPUT_MAX_FONT_SIZE = 20

# Combat state
var in_combat = false
var flock_pending = false
var flock_monster_name = ""
var combat_item_mode = false  # Selecting item to use in combat
var combat_outsmart_failed = false  # Track if outsmart already failed this combat
var pending_variable_ability: String = ""  # Ability waiting for resource amount input
var pending_variable_resource: String = ""  # Resource type for pending ability (mana/stamina/energy)

# Action bar
var action_buttons: Array[Button] = []
var action_cost_labels: Array[Label] = []  # Labels showing resource cost below hotkey
var action_hotkey_labels: Array[Label] = []  # Labels showing the hotkey name below button
# Spacebar is first action, then Q, W, E, R, 1, 2, 3, 4, 5
var action_hotkeys = [KEY_SPACE, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
var current_actions: Array[Dictionary] = []

# Inventory mode
var inventory_mode: bool = false
var inventory_page: int = 0  # Current page (0-indexed)
const INVENTORY_PAGE_SIZE: int = 9  # Items per page (keys 1-9)
var selected_item_index: int = -1  # Currently selected inventory item (0-based, -1 = none)
var pending_inventory_action: String = ""  # Action waiting for item selection
var last_item_use_result: String = ""  # Store last item use result to display after inventory refresh
var awaiting_item_use_result: bool = false  # Flag to capture next text message as item use result

# Pending continue state (prevents output clearing until player acknowledges)
var pending_continue: bool = false

# Remember last used amounts for variable cost abilities (e.g., Bolt)
var last_ability_amounts: Dictionary = {}  # ability_name -> last_amount
var last_gamble_bet: int = 0  # Remember last gambling bet for quick repeat

# XP tracking for two-color bar
var xp_before_combat: int = 0  # XP before starting combat
var recent_xp_gain: int = 0    # XP gained in most recent combat

# Merchant mode
var at_merchant: bool = false
var merchant_data: Dictionary = {}
var pending_merchant_action: String = ""
var selected_shop_item: int = -1  # Currently selected shop item for inspection (-1 = none)
var bought_item_pending_equip: Dictionary = {}  # Item just bought that can be equipped
var bought_item_inventory_index: int = -1  # Index of the bought item in inventory

# Trading Post mode
var at_trading_post: bool = false
var trading_post_data: Dictionary = {}
var pending_trading_post_action: String = ""

# Watch/Inspect mode - observe another player's game output
var watching_player: String = ""  # Name of player we're watching (empty = not watching)
var watch_request_pending: String = ""  # Player who requested to watch us (waiting for approval)
var watchers: Array = []  # Players currently watching us

# Font size constants for responsive scaling
const CHAT_BASE_FONT_SIZE = 12  # Base size in windowed mode
const CHAT_FULLSCREEN_FONT_SIZE = 14  # Size in fullscreen
const ONLINE_PLAYERS_BASE_FONT_SIZE = 11  # Base size in windowed mode
const ONLINE_PLAYERS_FULLSCREEN_FONT_SIZE = 14  # Size in fullscreen
const FULLSCREEN_HEIGHT_THRESHOLD = 900  # Window height above which we use fullscreen sizes

# Quest mode
var quest_view_mode: bool = false
var available_quests: Array = []
var quests_to_turn_in: Array = []

# Password change mode
var changing_password: bool = false
var password_change_step: int = 0  # 0=old, 1=new, 2=confirm
var temp_old_password: String = ""
var temp_new_password: String = ""

# Enemy tracking
var known_enemy_hp: Dictionary = {}
var current_enemy_name: String = ""
var current_enemy_level: int = 0
var current_enemy_color: String = "#FFFFFF"  # Monster name color based on class affinity
var damage_dealt_to_current_enemy: int = 0

# Player list auto-refresh
var player_list_refresh_timer: float = 0.0
const PLAYER_LIST_REFRESH_INTERVAL: float = 60.0  # Refresh every 60 seconds

# Player name click tracking for double-click
var last_player_click_name: String = ""
var last_player_click_time: float = 0.0
const DOUBLE_CLICK_THRESHOLD: float = 0.4  # 400ms for double-click
var pending_player_info_request: String = ""  # Track pending popup request

# Rare drop sound effect
var last_rare_sound_time: float = 0.0
const RARE_SOUND_COOLDOWN: float = 120.0  # 2 minute cooldown
var rare_sound_threshold: int = 0  # Increases if sound played recently
var rare_drop_player: AudioStreamPlayer = null

# Background music
var music_player: AudioStreamPlayer = null
var music_muted: bool = true  # Start with music off
const MUSIC_VOLUME_DB: float = -46.0  # Very quiet background

# Level up sound
var levelup_player: AudioStreamPlayer = null
var last_known_level: int = 0  # Track level changes for sound

# Top 5 leaderboard sound
var top5_player: AudioStreamPlayer = null

# Quest complete sound
var quest_complete_player: AudioStreamPlayer = null
var quests_sound_played: Dictionary = {}  # Track which quests have played completion sound

# ===== RACE DESCRIPTIONS =====
const RACE_DESCRIPTIONS = {
	"Human": "Adaptable and ambitious. Gains +10% bonus experience from all sources.",
	"Elf": "Ancient and resilient. 50% reduced poison damage, immune to poison debuffs.",
	"Dwarf": "Sturdy and determined. 25% chance to survive lethal damage with 1 HP (once per combat).",
	"Ogre": "Massive and regenerative. All healing effects are doubled."
}

const CLASS_DESCRIPTIONS = {
	"Fighter": "Warrior Path. Balanced melee fighter with solid defense and offense. Uses Stamina for powerful physical abilities.",
	"Barbarian": "Warrior Path. Aggressive berserker trading defense for raw damage. Uses Stamina for devastating attacks.",
	"Wizard": "Mage Path. Pure spellcaster with high magic damage. Uses Mana for versatile magical abilities.",
	"Sage": "Mage Path. Wise scholar balancing offense and utility. Uses Mana with improved regeneration.",
	"Thief": "Trickster Path. Cunning rogue excelling at evasion and critical hits. Uses Energy for tricks and ambushes.",
	"Ranger": "Trickster Path. Versatile scout with balanced combat and survival skills. Uses Energy efficiently."
}

# ===== ABILITY SYSTEM CONSTANTS =====
const PATH_STAT_THRESHOLD = 10  # Stat must be > 10 to unlock path abilities

# Ability slots: [command, display_name, required_level, resource_cost, resource_type]
# resource_type: "mana", "stamina", "energy"
const MAGE_ABILITY_SLOTS = [
	["magic_bolt", "Bolt", 1, 0, "mana"],
	["shield", "Shield", 10, 20, "mana"],
	["cloak", "Cloak", 25, 30, "mana"],
	["blast", "Blast", 40, 50, "mana"],
	["forcefield", "Field", 60, 75, "mana"],
	["teleport", "Teleport", 80, 40, "mana"],
]

const WARRIOR_ABILITY_SLOTS = [
	["power_strike", "Strike", 1, 10, "stamina"],
	["war_cry", "Cry", 10, 15, "stamina"],
	["shield_bash", "Bash", 25, 20, "stamina"],
	["cleave", "Cleave", 40, 30, "stamina"],
	["berserk", "Berserk", 60, 40, "stamina"],
	["iron_skin", "Iron", 80, 35, "stamina"],
]

const TRICKSTER_ABILITY_SLOTS = [
	["analyze", "Analyze", 1, 5, "energy"],
	["distract", "Distract", 10, 15, "energy"],
	["pickpocket", "Steal", 25, 20, "energy"],
	["ambush", "Ambush", 40, 30, "energy"],
	["vanish", "Vanish", 60, 40, "energy"],
	["exploit", "Exploit", 80, 35, "energy"],
]

func _ready():
	# Load keybind configuration
	_load_keybinds()

	# Save default game output stylebox for combat background changes
	if game_output:
		var existing_style = game_output.get_theme_stylebox("normal")
		if existing_style:
			default_game_output_stylebox = existing_style.duplicate()
		else:
			# Create a default black stylebox
			default_game_output_stylebox = StyleBoxFlat.new()
			default_game_output_stylebox.bg_color = Color("#000000")
			default_game_output_stylebox.set_corner_radius_all(4)
			default_game_output_stylebox.set_content_margin_all(8)

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
	if change_password_button:
		change_password_button.pressed.connect(_on_change_password_button_pressed)
	if char_select_logout_button:
		char_select_logout_button.pressed.connect(_on_char_select_logout_pressed)

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

	# Connect player info panel signals
	if close_player_info_button:
		close_player_info_button.pressed.connect(_on_close_player_info_pressed)

	# Create ability input popup
	_create_ability_popup()

	# Connect online players list for clickable names
	if online_players_list:
		online_players_list.meta_clicked.connect(_on_player_name_clicked)

	# Setup race options
	if race_option:
		race_option.clear()
		for r in ["Human", "Elf", "Dwarf", "Ogre"]:
			race_option.add_item(r)
		race_option.item_selected.connect(_on_race_selected)
		_update_race_description()  # Set initial description

	# Setup class options (6 classes: 2 Warrior, 2 Mage, 2 Trickster)
	if class_option:
		class_option.clear()
		for cls in ["Fighter", "Barbarian", "Wizard", "Sage", "Thief", "Ranger"]:
			class_option.add_item(cls)
		class_option.item_selected.connect(_on_class_selected)
		_update_class_description()  # Set initial description

	# Initialize rare drop sound player
	rare_drop_player = AudioStreamPlayer.new()
	rare_drop_player.volume_db = -17.0  # Quiet but audible
	add_child(rare_drop_player)
	_generate_rare_drop_sound()

	# Initialize level up sound player
	levelup_player = AudioStreamPlayer.new()
	levelup_player.volume_db = -19.0  # 20% quieter than before
	add_child(levelup_player)
	_generate_levelup_sound()

	# Initialize top 5 leaderboard sound player
	top5_player = AudioStreamPlayer.new()
	top5_player.volume_db = -19.0  # Match level up volume
	add_child(top5_player)
	_generate_top5_sound()

	# Initialize quest complete sound player
	quest_complete_player = AudioStreamPlayer.new()
	quest_complete_player.volume_db = -15.0  # Quiet but noticeable
	add_child(quest_complete_player)
	_generate_quest_complete_sound()

	# Initialize background music player
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = MUSIC_VOLUME_DB
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)

	# Connect music toggle button
	if music_toggle:
		music_toggle.pressed.connect(_on_music_toggle_pressed)
		# Set initial muted appearance
		music_toggle.text = "♪"
		music_toggle.modulate = Color(0.5, 0.5, 0.5)

	# Connect movement pad buttons
	if movement_pad:
		movement_pad.get_node("NW").pressed.connect(_on_move_button.bind(7))
		movement_pad.get_node("N").pressed.connect(_on_move_button.bind(8))
		movement_pad.get_node("NE").pressed.connect(_on_move_button.bind(9))
		movement_pad.get_node("W").pressed.connect(_on_move_button.bind(4))
		movement_pad.get_node("Hunt").pressed.connect(_on_hunt_button)
		movement_pad.get_node("E").pressed.connect(_on_move_button.bind(6))
		movement_pad.get_node("SW").pressed.connect(_on_move_button.bind(1))
		movement_pad.get_node("S").pressed.connect(_on_move_button.bind(2))
		movement_pad.get_node("SE").pressed.connect(_on_move_button.bind(3))

	# Defer music generation to not block startup
	call_deferred("_start_background_music")

	# Connect window resize for map scaling
	get_tree().root.size_changed.connect(_on_window_resized)
	# Initial map scale
	call_deferred("_on_window_resized")

	# Load connection settings
	_load_connection_settings()

	# Initial display
	display_game("[b][color=#FFFF00]Welcome to Phantasia Revival[/color][/b]")
	display_game("Select a server to connect to...")

	# Initialize UI state
	update_action_bar()

	# Show connection panel instead of auto-connect
	call_deferred("show_connection_panel")

func _generate_rare_drop_sound():
	"""Generate a pleasant chime sound for rare drops"""
	var sample_rate = 44100
	var duration = 0.4
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(samples * 2)

	# Create a pleasant rising chime (C5 -> E5 -> G5)
	var frequencies = [523.25, 659.25, 783.99]  # C5, E5, G5
	for i in range(samples):
		var t = float(i) / sample_rate
		var envelope = 1.0 - (t / duration)  # Fade out
		envelope = envelope * envelope  # Exponential fade

		var sample_val = 0.0
		for j in range(frequencies.size()):
			var freq = frequencies[j]
			var note_start = j * 0.08  # Stagger notes
			if t >= note_start:
				var note_t = t - note_start
				var note_env = max(0.0, 1.0 - (note_t / (duration - note_start)))
				sample_val += sin(TAU * freq * t) * note_env * 0.3

		var int_val = int(clamp(sample_val * envelope * 32767, -32768, 32767))
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data
	rare_drop_player.stream = audio

func play_rare_drop_sound(drop_value: int):
	"""Play sound for rare drops if cooldown allows and value is high enough"""
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_last = current_time - last_rare_sound_time

	# Reset threshold if enough time has passed
	if time_since_last >= RARE_SOUND_COOLDOWN:
		rare_sound_threshold = 0

	# Threshold increases each time sound plays within cooldown
	# Value needed: base 1 + threshold (so first is 1, then 2, then 3, etc.)
	var required_value = 1 + rare_sound_threshold

	if drop_value >= required_value:
		if rare_drop_player and rare_drop_player.stream:
			rare_drop_player.play()
		last_rare_sound_time = current_time
		rare_sound_threshold += 1

func _generate_levelup_sound():
	"""Generate Diablo 2 style level up sound - triumphant fanfare"""
	var sample_rate = 44100
	var duration = 1.2
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = true

	var data = PackedByteArray()
	data.resize(samples * 4)

	# Diablo 2 level up has a rising triumphant tone with choir-like quality
	# Notes: Rising arpeggio C-E-G-C (octave up)
	var notes = [
		{"freq": 262, "start": 0.0, "dur": 0.4},    # C4
		{"freq": 330, "start": 0.1, "dur": 0.4},    # E4
		{"freq": 392, "start": 0.2, "dur": 0.5},    # G4
		{"freq": 523, "start": 0.3, "dur": 0.7},    # C5
		{"freq": 659, "start": 0.5, "dur": 0.6},    # E5 (high shimmer)
	]

	for i in range(samples):
		var t = float(i) / sample_rate
		var sample_l = 0.0
		var sample_r = 0.0

		# Layer each note
		for note in notes:
			var freq = note.freq
			var start = note.start
			var dur = note.dur

			if t >= start and t < start + dur:
				var note_t = t - start
				# Envelope: quick attack, long sustain, fade out
				var env = 0.0
				var attack = 0.05
				var release_start = dur - 0.3

				if note_t < attack:
					env = note_t / attack
				elif note_t < release_start:
					env = 1.0
				else:
					env = 1.0 - ((note_t - release_start) / 0.3)

				env = max(0.0, env)

				# Rich harmonic content (choir-like)
				var wave = sin(TAU * freq * t) * 0.4
				wave += sin(TAU * freq * 2.0 * t) * 0.2
				wave += sin(TAU * freq * 3.0 * t) * 0.1
				wave += sin(TAU * freq * 4.0 * t) * 0.05

				# Slight stereo spread
				sample_l += wave * env * 0.25
				sample_r += wave * env * 0.25 * (1.0 + sin(TAU * 2.0 * t) * 0.1)

		# Add shimmer/sparkle overlay
		if t > 0.4 and t < 1.1:
			var shimmer_env = 0.0
			if t < 0.6:
				shimmer_env = (t - 0.4) / 0.2
			elif t < 0.9:
				shimmer_env = 1.0
			else:
				shimmer_env = (1.1 - t) / 0.2

			var shimmer = sin(TAU * 1047 * t) * 0.08  # C6
			shimmer += sin(TAU * 1319 * t) * 0.05     # E6
			sample_l += shimmer * shimmer_env
			sample_r += shimmer * shimmer_env

		# Soft limit
		sample_l = clamp(sample_l, -0.9, 0.9)
		sample_r = clamp(sample_r, -0.9, 0.9)

		var int_l = int(sample_l * 32767)
		var int_r = int(sample_r * 32767)

		data[i * 4] = int_l & 0xFF
		data[i * 4 + 1] = (int_l >> 8) & 0xFF
		data[i * 4 + 2] = int_r & 0xFF
		data[i * 4 + 3] = (int_r >> 8) & 0xFF

	audio.data = data
	levelup_player.stream = audio

func play_levelup_sound():
	"""Play the level up sound effect"""
	if levelup_player and levelup_player.stream:
		levelup_player.play()

func _generate_top5_sound():
	"""Generate heroic fanfare for top 5 leaderboard entry (D major: D-F#-A-D-F#5)"""
	var sample_rate = 44100
	var duration = 1.5
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = true

	var data = PackedByteArray()
	data.resize(samples * 4)

	# Heroic D major fanfare: D4, F#4, A4, D5, F#5
	var notes = [
		{"freq": 293.66, "start": 0.0, "dur": 0.5},   # D4
		{"freq": 369.99, "start": 0.15, "dur": 0.5},  # F#4
		{"freq": 440.00, "start": 0.30, "dur": 0.6},  # A4
		{"freq": 587.33, "start": 0.45, "dur": 0.7},  # D5
		{"freq": 739.99, "start": 0.65, "dur": 0.8},  # F#5 (high triumphant note)
	]

	for i in range(samples):
		var t = float(i) / sample_rate
		var sample_l = 0.0
		var sample_r = 0.0

		# Layer each note
		for note in notes:
			var freq = note.freq
			var start = note.start
			var dur = note.dur

			if t >= start and t < start + dur:
				var note_t = t - start
				# Envelope: quick attack, sustain, fade out
				var env = 0.0
				var attack = 0.04
				var release_start = dur - 0.25

				if note_t < attack:
					env = note_t / attack
				elif note_t < release_start:
					env = 1.0
				else:
					env = 1.0 - ((note_t - release_start) / 0.25)

				env = max(0.0, env)

				# Brass-like harmonic content
				var wave = sin(TAU * freq * t) * 0.35
				wave += sin(TAU * freq * 2.0 * t) * 0.25
				wave += sin(TAU * freq * 3.0 * t) * 0.15
				wave += sin(TAU * freq * 4.0 * t) * 0.08

				# Stereo spread (slightly wider for heroic feel)
				sample_l += wave * env * 0.3
				sample_r += wave * env * 0.3 * (1.0 + sin(TAU * 3.0 * t) * 0.12)

		# Add shimmer/sparkle at the peak
		if t > 0.6 and t < 1.4:
			var shimmer_env = 0.0
			if t < 0.8:
				shimmer_env = (t - 0.6) / 0.2
			elif t < 1.2:
				shimmer_env = 1.0
			else:
				shimmer_env = (1.4 - t) / 0.2

			var shimmer = sin(TAU * 1175 * t) * 0.06  # D6
			shimmer += sin(TAU * 1480 * t) * 0.04     # F#6
			sample_l += shimmer * shimmer_env
			sample_r += shimmer * shimmer_env

		# Soft limit
		sample_l = clamp(sample_l, -0.9, 0.9)
		sample_r = clamp(sample_r, -0.9, 0.9)

		var int_l = int(sample_l * 32767)
		var int_r = int(sample_r * 32767)

		data[i * 4] = int_l & 0xFF
		data[i * 4 + 1] = (int_l >> 8) & 0xFF
		data[i * 4 + 2] = int_r & 0xFF
		data[i * 4 + 3] = (int_r >> 8) & 0xFF

	audio.data = data
	top5_player.stream = audio

func play_top5_sound():
	"""Play the top 5 leaderboard fanfare"""
	if top5_player and top5_player.stream:
		top5_player.play()

func _generate_quest_complete_sound():
	"""Generate a quick, pleasant chime for quest completion"""
	var sample_rate = 44100
	var duration = 0.4  # Short and quick
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = true

	var data = PackedByteArray()
	data.resize(samples * 4)

	# Two quick ascending notes (G5 -> C6) - bright and cheerful
	var notes = [
		{"freq": 784.0, "start": 0.0, "dur": 0.2},    # G5
		{"freq": 1046.5, "start": 0.1, "dur": 0.3},   # C6
	]

	for i in range(samples):
		var t = float(i) / sample_rate
		var sample_l = 0.0
		var sample_r = 0.0

		for note in notes:
			var freq = note.freq
			var start = note.start
			var dur = note.dur

			if t >= start and t < start + dur:
				var note_t = t - start
				# Quick attack, gentle decay
				var env = 0.0
				var attack = 0.01
				var decay_start = 0.05

				if note_t < attack:
					env = note_t / attack
				elif note_t < decay_start:
					env = 1.0
				else:
					env = pow(1.0 - ((note_t - decay_start) / (dur - decay_start)), 1.5)

				env = max(0.0, env)

				# Bell-like tone
				var wave = sin(TAU * freq * t) * 0.4
				wave += sin(TAU * freq * 2.0 * t) * 0.2
				wave += sin(TAU * freq * 3.0 * t) * 0.1

				sample_l += wave * env * 0.25
				sample_r += wave * env * 0.25

		# Soft limit
		sample_l = clamp(sample_l, -0.9, 0.9)
		sample_r = clamp(sample_r, -0.9, 0.9)

		var int_l = int(sample_l * 32767)
		var int_r = int(sample_r * 32767)

		data[i * 4] = int_l & 0xFF
		data[i * 4 + 1] = (int_l >> 8) & 0xFF
		data[i * 4 + 2] = int_r & 0xFF
		data[i * 4 + 3] = (int_r >> 8) & 0xFF

	audio.data = data
	quest_complete_player.stream = audio

func play_quest_complete_sound():
	"""Play the quest complete chime"""
	if quest_complete_player and quest_complete_player.stream:
		quest_complete_player.play()

func _start_background_music():
	"""Deferred music startup"""
	_generate_ambient_music()
	if not music_muted:
		music_player.play()

func _generate_ambient_music():
	"""Generate Terraria-style chiptune adventure music"""
	var sample_rate = 22050
	var duration = 24.0  # 24 second loop
	var samples = int(sample_rate * duration)
	var bpm = 70.0  # Slow, ambient tempo
	var beat_duration = 60.0 / bpm

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = true
	audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	audio.loop_end = samples

	var data = PackedByteArray()
	data.resize(samples * 4)

	# C major / A minor for mellow adventure feel
	# Melody notes (C major pentatonic - lower octave, no high notes)
	var melody = [
		196, 220, 247, 294, 330,  # G3, A3, B3, D4, E4
		294, 247, 220, 196, 220,  # D4, B3, A3, G3, A3
		247, 294, 330, 392, 330,  # B3, D4, E4, G4, E4
		294, 247, 220, 247, 196   # D4, B3, A3, B3, G3
	]

	# Bass pattern (root notes)
	var bass_notes = [131, 131, 175, 175, 196, 196, 165, 165]  # C3, C3, F3, F3, G3, G3, E3, E3

	for i in range(samples):
		var t = float(i) / sample_rate
		var beat = t / beat_duration
		var beat_16th = beat * 4.0

		var sample_l = 0.0
		var sample_r = 0.0

		# Layer 1: Triangle wave bass (Terraria-style)
		var bass_idx = int(beat / 2.0) % bass_notes.size()
		var bass_freq = float(bass_notes[bass_idx])
		var bass_phase = fmod(t * bass_freq, 1.0)
		var bass_wave = abs(bass_phase - 0.5) * 4.0 - 1.0  # Triangle
		sample_l += bass_wave * 0.15
		sample_r += bass_wave * 0.15

		# Layer 2: Square wave melody (main chiptune sound)
		var melody_idx = int(beat_16th / 2.0) % melody.size()
		var melody_freq = float(melody[melody_idx])

		# Melody envelope (slight attack/decay per note)
		var note_phase = fmod(beat_16th / 2.0, 1.0)
		var melody_env = 1.0 - note_phase * 0.3

		# Square wave (sign of sine)
		var melody_wave = sign(sin(TAU * melody_freq * t))
		# Soften the square wave slightly
		melody_wave = melody_wave * 0.7 + sin(TAU * melody_freq * t) * 0.3
		sample_l += melody_wave * 0.08 * melody_env
		sample_r += melody_wave * 0.08 * melody_env

		# Layer 3: Arpeggio accompaniment (mellow arps - lower octave)
		var arp_notes = [131, 165, 196, 262]  # C3, E3, G3, C4
		var arp_idx = int(beat_16th) % arp_notes.size()
		var arp_freq = float(arp_notes[arp_idx])

		var arp_env = exp(-fmod(beat_16th, 1.0) * 6.0)
		var arp_wave = sin(TAU * arp_freq * t) * 0.6  # Pure sine, no high harmonics
		sample_l += arp_wave * 0.03 * arp_env
		sample_r += arp_wave * 0.035 * arp_env

		# Layer 4: Noise percussion (simple hi-hat style on 8ths)
		var perc_phase = fmod(beat * 2.0, 1.0)
		if perc_phase < 0.1:
			var noise = (randf() - 0.5) * 0.06 * (1.0 - perc_phase * 10.0)
			sample_l += noise
			sample_r += noise

		# Layer 5: Kick drum on beats
		var kick_phase = fmod(beat, 1.0)
		if kick_phase < 0.15:
			var kick_freq = 80.0 * (1.0 - kick_phase * 4.0)
			var kick = sin(TAU * kick_freq * t) * (1.0 - kick_phase * 6.0) * 0.12
			sample_l += kick
			sample_r += kick

		# Soft limiting
		sample_l = clamp(sample_l, -0.9, 0.9)
		sample_r = clamp(sample_r, -0.9, 0.9)

		var int_l = int(sample_l * 32767)
		var int_r = int(sample_r * 32767)

		data[i * 4] = int_l & 0xFF
		data[i * 4 + 1] = (int_l >> 8) & 0xFF
		data[i * 4 + 2] = int_r & 0xFF
		data[i * 4 + 3] = (int_r >> 8) & 0xFF

	audio.data = data
	music_player.stream = audio

func _on_music_finished():
	"""Restart music when it finishes (backup for loop)"""
	if not music_muted and music_player:
		music_player.play()

func _on_music_toggle_pressed():
	"""Toggle background music on/off"""
	music_muted = not music_muted
	if music_muted:
		music_player.stop()
		if music_toggle:
			music_toggle.text = "♪"
			music_toggle.modulate = Color(0.5, 0.5, 0.5)
	else:
		music_player.play()
		if music_toggle:
			music_toggle.text = "♫"
			music_toggle.modulate = Color(1, 1, 1)
	# Release focus so spacebar works for action bar
	if music_toggle:
		music_toggle.release_focus()

func _on_window_resized():
	"""Scale font sizes based on window height"""
	var window_height = get_viewport().get_visible_rect().size.y
	# Scale based on 720p as baseline
	var scale_factor = window_height / 720.0
	var is_large_window = window_height >= FULLSCREEN_HEIGHT_THRESHOLD

	# Scale map display (more aggressive scaling with 1.3x multiplier)
	if map_display:
		var map_font_size = int(MAP_BASE_FONT_SIZE * scale_factor * 1.3)
		map_font_size = clampi(map_font_size, MAP_MIN_FONT_SIZE, MAP_MAX_FONT_SIZE)
		map_display.add_theme_font_size_override("normal_font_size", map_font_size)
		map_display.add_theme_font_size_override("bold_font_size", map_font_size)
		map_display.add_theme_font_size_override("italics_font_size", map_font_size)
		map_display.add_theme_font_size_override("bold_italics_font_size", map_font_size)

	# Scale game output
	if game_output:
		var game_font_size = int(GAME_OUTPUT_BASE_FONT_SIZE * scale_factor)
		game_font_size = clampi(game_font_size, GAME_OUTPUT_MIN_FONT_SIZE, GAME_OUTPUT_MAX_FONT_SIZE)
		game_output.add_theme_font_size_override("normal_font_size", game_font_size)
		game_output.add_theme_font_size_override("bold_font_size", game_font_size)
		game_output.add_theme_font_size_override("italics_font_size", game_font_size)
		game_output.add_theme_font_size_override("bold_italics_font_size", game_font_size)

	# Chat output - smaller in windowed, normal in fullscreen
	if chat_output:
		var chat_size = CHAT_FULLSCREEN_FONT_SIZE if is_large_window else CHAT_BASE_FONT_SIZE
		chat_output.add_theme_font_size_override("normal_font_size", chat_size)

	# Online players list - normal in windowed, larger in fullscreen
	if online_players_list:
		var online_size = ONLINE_PLAYERS_FULLSCREEN_FONT_SIZE if is_large_window else ONLINE_PLAYERS_BASE_FONT_SIZE
		online_players_list.add_theme_font_size_override("normal_font_size", online_size)

	if online_players_label:
		var label_size = (ONLINE_PLAYERS_FULLSCREEN_FONT_SIZE + 1) if is_large_window else 12
		online_players_label.add_theme_font_size_override("font_size", label_size)

func _process(_delta):
	connection.poll()
	var status = connection.get_status()

	# Escape handling (only in playing state)
	if game_state == GameState.PLAYING:
		if Input.is_action_just_pressed("ui_cancel"):
			# If rebinding a key, cancel the rebind
			if rebinding_action != "":
				rebinding_action = ""
				game_output.clear()
				if settings_submenu == "action_keys":
					display_action_keybinds()
				elif settings_submenu == "movement_keys":
					display_movement_keybinds()
				else:
					display_settings_menu()
			# If in settings mode, close it
			elif settings_mode:
				close_settings()
			# If watching another player, escape stops watching
			elif watching_player != "":
				stop_watching()
			# If there's a pending watch request, escape denies it
			elif watch_request_pending != "":
				deny_watch_request()
			# Otherwise toggle input focus
			elif input_field.has_focus():
				input_field.release_focus()
			else:
				input_field.grab_focus()

	# Inventory item selection with number keys (1-9) when action is pending
	if game_state == GameState.PLAYING and not input_field.has_focus() and inventory_mode and pending_inventory_action != "":
		var item_keys = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
		for i in range(item_keys.size()):
			if Input.is_physical_key_pressed(item_keys[i]) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("itemkey_%d_pressed" % i, false):
					set_meta("itemkey_%d_pressed" % i, true)
					# Also mark action hotkeys as pressed to prevent double-trigger
					# KEY_1-4 map to hotkey indices 5-8
					if i < 4:
						set_meta("hotkey_%d_pressed" % (i + 5), true)
					# Convert page-relative index to absolute inventory index
					var absolute_index = inventory_page * INVENTORY_PAGE_SIZE + i
					select_inventory_item(absolute_index)
			else:
				set_meta("itemkey_%d_pressed" % i, false)

	# Merchant item selection with number keys (1-9) when action is pending
	if game_state == GameState.PLAYING and not input_field.has_focus() and at_merchant and pending_merchant_action == "sell":
		var item_keys = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
		for i in range(item_keys.size()):
			if Input.is_physical_key_pressed(item_keys[i]) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("merchantkey_%d_pressed" % i, false):
					set_meta("merchantkey_%d_pressed" % i, true)
					select_merchant_sell_item(i)  # 0-based index
			else:
				set_meta("merchantkey_%d_pressed" % i, false)

	# Merchant shop buy selection with number keys (1-9)
	if game_state == GameState.PLAYING and not input_field.has_focus() and at_merchant and pending_merchant_action == "buy":
		var item_keys = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
		for i in range(item_keys.size()):
			if Input.is_physical_key_pressed(item_keys[i]) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("buykey_%d_pressed" % i, false):
					set_meta("buykey_%d_pressed" % i, true)
					select_merchant_buy_item(i)  # 0-based index
			else:
				set_meta("buykey_%d_pressed" % i, false)

	# Quest selection with number keys (1-9) when in quest view mode
	if game_state == GameState.PLAYING and not input_field.has_focus() and at_trading_post and quest_view_mode:
		var quest_keys = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
		for i in range(quest_keys.size()):
			if Input.is_physical_key_pressed(quest_keys[i]) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("questkey_%d_pressed" % i, false):
					set_meta("questkey_%d_pressed" % i, true)
					select_quest_option(i)  # 0-based index
			else:
				set_meta("questkey_%d_pressed" % i, false)

	# Combat item selection with number keys (1-9)
	if game_state == GameState.PLAYING and not input_field.has_focus() and combat_item_mode:
		var item_keys = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
		for i in range(item_keys.size()):
			if Input.is_physical_key_pressed(item_keys[i]) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("combatitemkey_%d_pressed" % i, false):
					set_meta("combatitemkey_%d_pressed" % i, true)
					use_combat_item_by_number(i + 1)  # 1-based for user
			else:
				set_meta("combatitemkey_%d_pressed" % i, false)

	# Watch request approval (Q = approve, W = deny) - skip other hotkeys this frame
	var watch_request_handled = false
	if game_state == GameState.PLAYING and not input_field.has_focus() and watch_request_pending != "":
		if Input.is_physical_key_pressed(KEY_Q):
			if not get_meta("watch_q_pressed", false):
				set_meta("watch_q_pressed", true)
				set_meta("hotkey_1_pressed", true)  # Q is index 1 in action_hotkeys
				approve_watch_request()
				watch_request_handled = true
		else:
			set_meta("watch_q_pressed", false)

		if Input.is_physical_key_pressed(KEY_W):
			if not get_meta("watch_w_pressed", false):
				set_meta("watch_w_pressed", true)
				set_meta("hotkey_2_pressed", true)  # W is index 2 in action_hotkeys
				deny_watch_request()
				watch_request_handled = true
		else:
			set_meta("watch_w_pressed", false)

	# Action bar hotkeys (only when input NOT focused and playing)
	# Allow hotkeys during merchant modes and inventory modes (for Cancel buttons)
	# Skip if in settings mode (settings has its own input handling)
	var merchant_blocks_hotkeys = pending_merchant_action != "" and pending_merchant_action not in ["sell_gems", "upgrade", "buy", "buy_inspect", "buy_equip_prompt", "sell", "gamble", "gamble_again"]
	if game_state == GameState.PLAYING and not input_field.has_focus() and not merchant_blocks_hotkeys and watch_request_pending == "" and not watch_request_handled and not settings_mode:
		for i in range(10):  # 0-9 action slots
			var action_key = "action_%d" % i
			var key = keybinds.get(action_key, default_keybinds.get(action_key, KEY_SPACE))
			if Input.is_physical_key_pressed(key) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("hotkey_%d_pressed" % i, false):
					set_meta("hotkey_%d_pressed" % i, true)
					trigger_action(i)
			else:
				set_meta("hotkey_%d_pressed" % i, false)

	# Enter key to focus chat input (only in movement mode)
	if game_state == GameState.PLAYING and not input_field.has_focus() and not in_combat and not flock_pending and not pending_continue and not inventory_mode and not at_merchant and not at_trading_post:
		if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
			if not get_meta("enter_pressed", false):
				set_meta("enter_pressed", true)
				input_field.grab_focus()
		else:
			set_meta("enter_pressed", false)

	# Movement and hunt (only when playing and not in combat, flock, pending continue, inventory, merchant, or settings)
	if connected and has_character and not input_field.has_focus() and not in_combat and not flock_pending and not pending_continue and not inventory_mode and not at_merchant and not settings_mode:
		if game_state == GameState.PLAYING:
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_move_time >= MOVE_COOLDOWN:
				var move_dir = 0
				var is_hunt = false

				# Check numpad/configured movement keys
				for dir in [1, 2, 3, 4, 6, 7, 8, 9]:
					var move_key = "move_%d" % dir
					var key = keybinds.get(move_key, default_keybinds.get(move_key, 0))
					if key != 0 and Input.is_physical_key_pressed(key):
						move_dir = dir
						break

				# Check hunt key
				if move_dir == 0:
					var hunt_key = keybinds.get("hunt", default_keybinds.get("hunt", KEY_KP_5))
					if Input.is_physical_key_pressed(hunt_key):
						is_hunt = true

				# Check arrow keys as alternative movement (4-direction)
				if move_dir == 0 and not is_hunt:
					var up_key = keybinds.get("move_up", default_keybinds.get("move_up", KEY_UP))
					var down_key = keybinds.get("move_down", default_keybinds.get("move_down", KEY_DOWN))
					var left_key = keybinds.get("move_left", default_keybinds.get("move_left", KEY_LEFT))
					var right_key = keybinds.get("move_right", default_keybinds.get("move_right", KEY_RIGHT))

					if Input.is_physical_key_pressed(up_key):
						move_dir = 8  # North
					elif Input.is_physical_key_pressed(down_key):
						move_dir = 2  # South
					elif Input.is_physical_key_pressed(left_key):
						move_dir = 4  # West
					elif Input.is_physical_key_pressed(right_key):
						move_dir = 6  # East

				if move_dir > 0:
					send_move(move_dir)
					game_output.clear()
					last_move_time = current_time
				elif is_hunt:
					game_output.clear()
					send_to_server({"type": "hunt"})
					last_move_time = current_time

	# Connection state
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not connected:
			connected = true
			game_state = GameState.CONNECTED
			display_game("[color=#00FF00]Connected to server![/color]")
			# Hide connection panel and show login panel
			if connection_panel:
				connection_panel.visible = false
			show_login_panel()

		var available = connection.get_available_bytes()
		if available > 0:
			var data = connection.get_data(available)
			if data[0] == OK:
				buffer += data[1].get_string_from_utf8()
				process_buffer()

		# Auto-refresh player list every 60 seconds while playing
		if game_state == GameState.PLAYING and has_character:
			player_list_refresh_timer += _delta
			if player_list_refresh_timer >= PLAYER_LIST_REFRESH_INTERVAL:
				player_list_refresh_timer = 0.0
				request_player_list()

	elif status == StreamPeerTCP.STATUS_ERROR:
		if connected:
			display_game("[color=#FF0000]Connection error![/color]")
			reset_connection_state()

func _input(event):
	# Handle key input for rebinding mode
	if rebinding_action != "" and event is InputEventKey and event.pressed:
		# Capture the key for rebinding
		var keycode = event.keycode
		if keycode == KEY_ESCAPE:
			# Cancel rebinding
			rebinding_action = ""
			game_output.clear()
			if settings_submenu == "action_keys":
				display_action_keybinds()
			elif settings_submenu == "movement_keys":
				display_movement_keybinds()
			else:
				display_settings_menu()
		else:
			complete_rebinding(keycode)
		get_viewport().set_input_as_handled()
		return

	# Handle settings mode input
	if settings_mode and not rebinding_action and event is InputEventKey and event.pressed and not event.echo:
		var keycode = event.keycode
		if settings_submenu == "":
			# Main settings menu
			match keycode:
				KEY_Q:
					settings_submenu = "action_keys"
					game_output.clear()
					display_action_keybinds()
					update_action_bar()
				KEY_W:
					settings_submenu = "movement_keys"
					game_output.clear()
					display_movement_keybinds()
					update_action_bar()
				KEY_E:
					reset_keybinds_to_defaults()
				KEY_SPACE:
					close_settings()
			get_viewport().set_input_as_handled()
		elif settings_submenu == "action_keys":
			# Action keybinds submenu - 0-9 to rebind actions
			if keycode >= KEY_0 and keycode <= KEY_9:
				var index = keycode - KEY_0
				start_rebinding("action_%d" % index)
			elif keycode == KEY_SPACE:
				settings_submenu = ""
				game_output.clear()
				display_settings_menu()
				update_action_bar()
			get_viewport().set_input_as_handled()
		elif settings_submenu == "movement_keys":
			# Movement keybinds submenu
			match keycode:
				KEY_1:
					start_rebinding("move_7")  # NW
				KEY_2:
					start_rebinding("move_8")  # N
				KEY_3:
					start_rebinding("move_9")  # NE
				KEY_4:
					start_rebinding("move_4")  # W
				KEY_5:
					start_rebinding("hunt")
				KEY_6:
					start_rebinding("move_6")  # E
				KEY_7:
					start_rebinding("move_1")  # SW
				KEY_8:
					start_rebinding("move_2")  # S
				KEY_9:
					start_rebinding("move_3")  # SE
				KEY_Q:
					start_rebinding("move_up")
				KEY_W:
					start_rebinding("move_down")
				KEY_E:
					start_rebinding("move_left")
				KEY_R:
					start_rebinding("move_right")
				KEY_SPACE:
					settings_submenu = ""
					game_output.clear()
					display_settings_menu()
					update_action_bar()
			get_viewport().set_input_as_handled()

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
	if player_info_panel:
		player_info_panel.visible = false

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
		var char_race = char_info.get("race", "Human")
		btn.text = "%s - Level %d %s %s" % [char_info.name, char_info.level, char_race, char_info["class"]]
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
		leaderboard_list.append_text("[center][color=#555555]No entries yet. Be the first![/color][/center]")
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
		leaderboard_list.append_text("   [color=#555555]Slain by: %s[/color]\n\n" % cause)

func update_online_players(players: Array):
	"""Update the online players list display with clickable names"""
	if not online_players_list:
		return

	online_players_list.clear()

	if players.is_empty():
		online_players_list.append_text("[color=#555555]No players online[/color]")
		return

	for player in players:
		var pname = player.get("name", "Unknown")
		var plevel = player.get("level", 1)
		var pclass = player.get("class", "Unknown")
		# Use URL tags to make names clickable (double-click shows stats)
		online_players_list.append_text("[url=%s][color=#00FF00]%s[/color][/url] Lv%d %s\n" % [pname, pname, plevel, pclass])

func display_examine_result(data: Dictionary):
	"""Display examined player info in game output"""
	var pname = data.get("name", "Unknown")
	var level = data.get("level", 1)
	var char_race = data.get("race", "Human")
	var cls = data.get("class", "Unknown")
	var hp = data.get("hp", 0)
	var max_hp = data.get("max_hp", 1)
	var in_combat_flag = data.get("in_combat", false)
	var kills = data.get("monsters_killed", 0)
	var current_xp = data.get("experience", 0)
	var xp_needed = data.get("experience_to_next_level", 100)
	var xp_remaining = xp_needed - current_xp

	var str_stat = data.get("strength", 0)
	var con_stat = data.get("constitution", 0)
	var dex_stat = data.get("dexterity", 0)
	var int_stat = data.get("intelligence", 0)
	var wis_stat = data.get("wisdom", 0)
	var wit_stat = data.get("wits", data.get("charisma", 0))  # Support legacy

	var bonuses = data.get("equipment_bonuses", {})
	var equipped = data.get("equipped", {})
	var total_attack = data.get("total_attack", str_stat)
	var total_defense = data.get("total_defense", con_stat / 2)

	var status = "[color=#00FF00]Exploring[/color]" if not in_combat_flag else "[color=#FF4444]In Combat[/color]"

	display_game("[color=#FFD700]===== %s =====[/color]" % pname)
	display_game("Level %d %s %s - %s" % [level, char_race, cls, status])
	display_game("[color=#FF00FF]XP:[/color] %d / %d ([color=#FFD700]%d to next level[/color])" % [current_xp, xp_needed, xp_remaining])
	display_game("HP: %d/%d" % [hp, max_hp])

	# Stats with bonuses
	var stats_line = "STR:%d" % str_stat
	if bonuses.get("strength", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.strength
	stats_line += " CON:%d" % con_stat
	if bonuses.get("constitution", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.constitution
	stats_line += " DEX:%d" % dex_stat
	if bonuses.get("dexterity", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.dexterity
	display_game(stats_line)

	stats_line = "INT:%d" % int_stat
	if bonuses.get("intelligence", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.intelligence
	stats_line += " WIS:%d" % wis_stat
	if bonuses.get("wisdom", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.wisdom
	stats_line += " WIT:%d" % wit_stat
	if bonuses.get("wits", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.wits
	display_game(stats_line)

	# Combat stats
	display_game("[color=#FF6666]Attack:[/color] %d  [color=#66FFFF]Defense:[/color] %d" % [total_attack, total_defense])

	# Equipment
	var equip_text = ""
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			equip_text += "[color=%s]%s[/color] " % [rarity_color, item.get("name", "Unknown")]
	if equip_text != "":
		display_game("[color=#FFA500]Gear:[/color] %s" % equip_text.strip_edges())

	display_game("Monsters Slain: %d" % kills)

func request_player_list():
	"""Request updated player list from server"""
	if connected:
		send_to_server({"type": "get_players"})

# ===== LOGIN/REGISTER HANDLERS =====

func _on_login_button_pressed():
	var user = username_field.text.strip_edges()
	var passwd = password_field.text

	if user.is_empty() or passwd.is_empty():
		if login_status:
			login_status.text = "[color=#FF0000]Enter username and password[/color]"
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
	var confirm_passwd = confirm_password_field.text

	if user.is_empty() or passwd.is_empty():
		if login_status:
			login_status.text = "[color=#FF0000]Enter username and password[/color]"
		return

	if confirm_passwd.is_empty():
		if login_status:
			login_status.text = "[color=#FF0000]Please confirm your password[/color]"
		return

	if passwd != confirm_passwd:
		if login_status:
			login_status.text = "[color=#FF0000]Passwords do not match[/color]"
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

func _on_change_password_button_pressed():
	# Hide character select, show password change UI
	char_select_panel.visible = false
	start_password_change()

func _on_char_select_logout_pressed():
	logout_account()

# ===== CHARACTER CREATION HANDLERS =====

func _on_race_selected(_index: int):
	_update_race_description()

func _update_race_description():
	if not race_option or not race_description:
		return
	var selected_race = race_option.get_item_text(race_option.selected)
	race_description.text = RACE_DESCRIPTIONS.get(selected_race, "")

func _on_class_selected(_index: int):
	_update_class_description()

func _update_class_description():
	if not class_option or not class_description:
		return
	var selected_class = class_option.get_item_text(class_option.selected)
	class_description.text = CLASS_DESCRIPTIONS.get(selected_class, "")

func _on_confirm_create_pressed():
	var char_name = new_char_name_field.text.strip_edges()
	var char_race = race_option.get_item_text(race_option.selected) if race_option else "Human"
	var char_class = class_option.get_item_text(class_option.selected)

	if char_name.is_empty():
		if char_create_status:
			char_create_status.text = "[color=#FF0000]Enter a character name[/color]"
		return

	if char_create_status:
		char_create_status.text = "Creating character..."

	send_to_server({
		"type": "create_character",
		"name": char_name,
		"race": char_race,
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

# ===== PLAYER INFO POPUP HANDLERS =====

func _on_player_name_clicked(meta):
	"""Handle click on player name in online players list - double-click shows popup"""
	var player_name = str(meta)
	var current_time = Time.get_ticks_msec() / 1000.0

	# Check for double-click
	if player_name == last_player_click_name and (current_time - last_player_click_time) <= DOUBLE_CLICK_THRESHOLD:
		# Double-click detected - request player info for popup
		pending_player_info_request = player_name
		send_to_server({"type": "examine_player", "name": player_name})
		last_player_click_name = ""
		last_player_click_time = 0.0
	else:
		# First click - store for potential double-click
		last_player_click_name = player_name
		last_player_click_time = current_time

func _on_close_player_info_pressed():
	if player_info_panel:
		player_info_panel.visible = false

func show_player_info_popup(data: Dictionary):
	"""Display player stats in a popup panel"""
	if not player_info_panel or not player_info_content:
		return

	var pname = data.get("name", "Unknown")
	var level = data.get("level", 1)
	var exp = data.get("experience", 1)
	var cls = data.get("class", "Unknown")
	var hp = data.get("hp", 0)
	var max_hp = data.get("max_hp", 1)
	var in_combat_status = data.get("in_combat", false)
	var kills = data.get("monsters_killed", 0)

	var str_stat = data.get("strength", 0)
	var con_stat = data.get("constitution", 0)
	var dex_stat = data.get("dexterity", 0)
	var int_stat = data.get("intelligence", 0)
	var wis_stat = data.get("wisdom", 0)
	var wit_stat = data.get("wits", data.get("charisma", 0))  # Support legacy

	var bonuses = data.get("equipment_bonuses", {})
	var equipped = data.get("equipped", {})
	var total_attack = data.get("total_attack", str_stat)
	var total_defense = data.get("total_defense", con_stat / 2)

	var status_text = "[color=#00FF00]Exploring[/color]" if not in_combat_status else "[color=#FF4444]In Combat[/color]"

	var xp_needed = data.get("experience_to_next_level", 100)
	var xp_remaining = xp_needed - exp

	var char_race = data.get("race", "Human")
	player_info_content.clear()
	player_info_content.append_text("[center][color=#FFD700][b]%s[/b][/color][/center]\n" % pname)
	player_info_content.append_text("[center]Level %d %s %s[/center]\n" % [level, char_race, cls])
	player_info_content.append_text("[center][color=#FF00FF]XP:[/color] %d / %d[/center]\n" % [exp, xp_needed])
	player_info_content.append_text("[center][color=#FFD700]%d XP to next level[/color][/center]\n" % xp_remaining)
	player_info_content.append_text("[center]%s[/center]\n\n" % status_text)
	player_info_content.append_text("[color=#00FFFF]HP:[/color] %d / %d\n\n" % [hp, max_hp])

	# Stats with equipment bonuses
	player_info_content.append_text("[color=#FF00FF]Stats:[/color]\n")
	var line1 = "  STR: %d" % str_stat
	if bonuses.get("strength", 0) > 0:
		line1 += "[color=#00FF00](+%d)[/color]" % bonuses.strength
	line1 += "  CON: %d" % con_stat
	if bonuses.get("constitution", 0) > 0:
		line1 += "[color=#00FF00](+%d)[/color]" % bonuses.constitution
	line1 += "  DEX: %d" % dex_stat
	if bonuses.get("dexterity", 0) > 0:
		line1 += "[color=#00FF00](+%d)[/color]" % bonuses.dexterity
	player_info_content.append_text(line1 + "\n")

	var line2 = "  INT: %d" % int_stat
	if bonuses.get("intelligence", 0) > 0:
		line2 += "[color=#00FF00](+%d)[/color]" % bonuses.intelligence
	line2 += "  WIS: %d" % wis_stat
	if bonuses.get("wisdom", 0) > 0:
		line2 += "[color=#00FF00](+%d)[/color]" % bonuses.wisdom
	line2 += "  WIT: %d" % wit_stat
	if bonuses.get("wits", 0) > 0:
		line2 += "[color=#00FF00](+%d)[/color]" % bonuses.wits
	player_info_content.append_text(line2 + "\n\n")

	# Combat stats
	player_info_content.append_text("[color=#FF6666]Attack:[/color] %d  [color=#66FFFF]Defense:[/color] %d\n\n" % [total_attack, total_defense])

	# Equipment
	var has_equipment = false
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			if not has_equipment:
				player_info_content.append_text("[color=#FFA500]Equipment:[/color]\n")
				has_equipment = true
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			player_info_content.append_text("  %s: [color=%s]%s[/color] (Lv%d)\n" % [
				slot.capitalize(), rarity_color, item.get("name", "Unknown"), item.get("level", 1)
			])

	if has_equipment:
		player_info_content.append_text("\n")

	player_info_content.append_text("[color=#FFA500]Monsters Slain:[/color] %d" % kills)

	player_info_panel.visible = true

# ===== ACTION BAR FUNCTIONS =====

func setup_action_bar():
	action_buttons.clear()
	action_cost_labels.clear()
	action_hotkey_labels.clear()
	for i in range(10):
		var action_container = action_bar.get_node("Action%d" % (i + 1))
		if action_container:
			var button = action_container.get_node("Button")
			if button:
				action_buttons.append(button)
				button.pressed.connect(_on_action_button_pressed.bind(i))
				# Reduce font size for ability bar buttons
				button.add_theme_font_size_override("font_size", 11)

			# Get hotkey label reference
			var hotkey_label = action_container.get_node_or_null("Hotkey")
			if hotkey_label:
				action_hotkey_labels.append(hotkey_label)
			else:
				action_hotkey_labels.append(null)

			# Create cost label dynamically if it doesn't exist
			var cost_label = action_container.get_node_or_null("Cost")
			if cost_label == null:
				cost_label = Label.new()
				cost_label.name = "Cost"
				cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cost_label.add_theme_font_size_override("font_size", 9)
				cost_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
				action_container.add_child(cost_label)
			action_cost_labels.append(cost_label)

	# Initialize hotkey labels with current keybinds
	update_action_bar_hotkeys()

func update_action_bar():
	current_actions.clear()

	if settings_mode:
		# Settings mode - actions handled by _input(), show info only
		if rebinding_action != "":
			current_actions = [
				{"label": "Press Key", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Cancel", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif settings_submenu == "action_keys":
			current_actions = [
				{"label": "Back", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Press 0-9", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "to rebind", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif settings_submenu == "movement_keys":
			current_actions = [
				{"label": "Back", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Up", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Down", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Left", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Right", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			current_actions = [
				{"label": "Back", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Actions", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Movement", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Reset", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif combat_item_mode:
		# Combat item selection mode - show cancel only, use number keys to select
		current_actions = [
			{"label": "Cancel", "action_type": "local", "action_data": "combat_item_cancel", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif in_combat:
		# Combat mode: Space=Attack, Q=Use Item, W=Flee, E=Outsmart, R/1-5=Path abilities
		var ability_actions = _get_combat_ability_actions()
		var has_items = _has_usable_combat_items()
		var can_outsmart = not combat_outsmart_failed  # Track if outsmart already failed this combat
		current_actions = [
			{"label": "Attack", "action_type": "combat", "action_data": "attack", "enabled": true},
			{"label": "Use Item", "action_type": "local", "action_data": "combat_item", "enabled": has_items},
			{"label": "Flee", "action_type": "combat", "action_data": "flee", "enabled": true},
			{"label": "Outsmart", "action_type": "combat", "action_data": "outsmart", "enabled": can_outsmart},
		]
		# Add 6 ability slots (R, 1, 2, 3, 4, 5)
		for i in range(min(6, ability_actions.size())):
			current_actions.append(ability_actions[i])
	elif flock_pending:
		current_actions = [
			{"label": "Continue", "action_type": "flock", "action_data": "continue", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif pending_continue:
		# Waiting for player to acknowledge combat results
		current_actions = [
			{"label": "Continue", "action_type": "local", "action_data": "acknowledge_continue", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif at_merchant:
		# Merchant mode
		var services = merchant_data.get("services", [])
		var equipped = character_data.get("equipped", {})
		var player_gems = character_data.get("gems", 0)
		var shop_items = merchant_data.get("shop_items", [])
		if pending_merchant_action == "sell":
			# Waiting for item selection (use number keys)
			var has_items = character_data.get("inventory", []).size() > 0
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "Sell All", "action_type": "local", "action_data": "sell_all_items", "enabled": has_items},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_merchant_action == "buy":
			# Waiting for item selection from shop (use number keys)
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_merchant_action == "buy_inspect":
			# Inspecting a shop item before purchase
			var can_afford = false
			if selected_shop_item >= 0 and selected_shop_item < shop_items.size():
				var item = shop_items[selected_shop_item]
				var price = item.get("shop_price", 0)
				can_afford = character_data.get("gold", 0) >= price
			current_actions = [
				{"label": "Buy", "action_type": "local", "action_data": "confirm_shop_buy", "enabled": can_afford},
				{"label": "Back", "action_type": "local", "action_data": "cancel_shop_inspect", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_merchant_action == "buy_equip_prompt":
			# After buying an equippable item - offer to equip now
			current_actions = [
				{"label": "Equip Now", "action_type": "local", "action_data": "equip_bought_item", "enabled": true},
				{"label": "Keep", "action_type": "local", "action_data": "skip_equip_bought", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_merchant_action == "upgrade":
			# Show equipment slots as action bar options
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "Weapon", "action_type": "local", "action_data": "upgrade_weapon", "enabled": equipped.get("weapon") != null},
				{"label": "Armor", "action_type": "local", "action_data": "upgrade_armor", "enabled": equipped.get("armor") != null},
				{"label": "Helm", "action_type": "local", "action_data": "upgrade_helm", "enabled": equipped.get("helm") != null},
				{"label": "Shield", "action_type": "local", "action_data": "upgrade_shield", "enabled": equipped.get("shield") != null},
				{"label": "Boots", "action_type": "local", "action_data": "upgrade_boots", "enabled": equipped.get("boots") != null},
				{"label": "Ring", "action_type": "local", "action_data": "upgrade_ring", "enabled": equipped.get("ring") != null},
				{"label": "Amulet", "action_type": "local", "action_data": "upgrade_amulet", "enabled": equipped.get("amulet") != null},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_merchant_action == "gamble":
			# Initial gamble - popup is open, just show cancel
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_merchant_action == "gamble_again":
			# After a gamble result - offer bet again or cancel
			var bet_label = "Bet Again (%d)" % last_gamble_bet if last_gamble_bet > 0 else "Bet Again"
			current_actions = [
				{"label": bet_label, "action_type": "local", "action_data": "merchant_gamble_again", "enabled": last_gamble_bet > 0},
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_merchant_action == "sell_gems":
			# Waiting for gem amount input
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "Sell All", "action_type": "local", "action_data": "sell_all_gems", "enabled": player_gems > 0},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			current_actions = [
				{"label": "Leave", "action_type": "local", "action_data": "merchant_leave", "enabled": true},
				{"label": "Sell", "action_type": "local", "action_data": "merchant_sell", "enabled": "sell" in services},
				{"label": "Upgrade", "action_type": "local", "action_data": "merchant_upgrade", "enabled": "upgrade" in services},
				{"label": "Gamble", "action_type": "local", "action_data": "merchant_gamble", "enabled": "gamble" in services},
				{"label": "Buy", "action_type": "local", "action_data": "merchant_buy", "enabled": shop_items.size() > 0},
				{"label": "SellGems", "action_type": "local", "action_data": "merchant_sell_gems", "enabled": player_gems > 0},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif inventory_mode:
		if pending_inventory_action != "":
			# Waiting for item selection - show cancel and page navigation
			var inv = character_data.get("inventory", [])
			var total_pages = max(1, int(ceil(float(inv.size()) / INVENTORY_PAGE_SIZE)))
			var has_prev = inventory_page > 0
			var has_next = inventory_page < total_pages - 1
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "inventory_cancel", "enabled": true},
				{"label": "Prev Pg", "action_type": "local", "action_data": "inventory_prev_page", "enabled": has_prev},
				{"label": "Next Pg", "action_type": "local", "action_data": "inventory_next_page", "enabled": has_next},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Inventory sub-menu: Spacebar=Back, Q-R for inventory actions
			# Discard moved to end (KEY_5) to prevent accidental use
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "inventory_back", "enabled": true},
				{"label": "Inspect", "action_type": "local", "action_data": "inventory_inspect", "enabled": true},
				{"label": "Use", "action_type": "local", "action_data": "inventory_use", "enabled": true},
				{"label": "Equip", "action_type": "local", "action_data": "inventory_equip", "enabled": true},
				{"label": "Unequip", "action_type": "local", "action_data": "inventory_unequip", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Discard", "action_type": "local", "action_data": "inventory_discard", "enabled": true},
			]
	elif at_trading_post:
		# Trading Post mode
		if quest_view_mode:
			# Quest selection sub-menu
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "trading_post_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Main Trading Post menu
			var quests_available = trading_post_data.get("available_quests", 0) > 0
			var quests_ready = trading_post_data.get("quests_to_turn_in", 0) > 0
			# Calculate recharge cost (50 + level*10, then 50% off at Trading Post)
			var player_level = character_data.get("level", 1)
			var recharge_cost = int((50 + player_level * 10) * 0.5)
			current_actions = [
				{"label": "Leave", "action_type": "local", "action_data": "trading_post_leave", "enabled": true},
				{"label": "Shop", "action_type": "local", "action_data": "trading_post_shop", "enabled": true},
				{"label": "Quests", "action_type": "local", "action_data": "trading_post_quests", "enabled": quests_available or quests_ready},
				{"label": "Heal(%dg)" % recharge_cost, "action_type": "local", "action_data": "trading_post_recharge", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif has_character:
		# Normal movement mode: Spacebar=Status
		current_actions = [
			{"label": "Status", "action_type": "local", "action_data": "status", "enabled": true},
			{"label": "Inventory", "action_type": "local", "action_data": "inventory", "enabled": true},
			{"label": "Rest", "action_type": "server", "action_data": "rest", "enabled": true},
			{"label": "Help", "action_type": "local", "action_data": "help", "enabled": true},
			{"label": "Quests", "action_type": "local", "action_data": "show_quests", "enabled": true},
			{"label": "Leaders", "action_type": "local", "action_data": "leaderboard", "enabled": true},
			{"label": "Settings", "action_type": "local", "action_data": "settings", "enabled": true},
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
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]

	for i in range(min(action_buttons.size(), current_actions.size())):
		var button = action_buttons[i]
		var action = current_actions[i]
		button.text = action.label
		button.disabled = not action.enabled

		# Update cost label if it exists
		if i < action_cost_labels.size():
			var cost_label = action_cost_labels[i]
			var cost = action.get("cost", 0)
			var resource_type = action.get("resource_type", "")
			if cost > 0 and resource_type != "":
				cost_label.text = "%d" % cost
				# Color based on resource type
				match resource_type:
					"stamina":
						cost_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.1, 1))  # Yellow
					"mana":
						cost_label.add_theme_color_override("font_color", Color(0.2, 0.7, 0.8, 1))  # Teal
					"energy":
						cost_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3, 1))  # Green
					_:
						cost_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
				cost_label.visible = true
			else:
				cost_label.text = ""
				cost_label.visible = false

func _on_action_button_pressed(index: int):
	# Release button focus so Space key works correctly
	var focused = get_viewport().gui_get_focus_owner()
	if focused and focused is Button:
		focused.release_focus()
	trigger_action(index)

func trigger_action(index: int):
	if index < 0 or index >= current_actions.size():
		return

	var action = current_actions[index]
	if not action.enabled:
		return

	match action.action_type:
		"combat":
			# Check for variable cost ability (cost = 0 means variable)
			if action.get("cost", -1) == 0 and action.get("resource_type", "") != "":
				prompt_variable_cost_ability(action.action_data, action.get("resource_type", "mana"))
			else:
				send_combat_command(action.action_data)
		"local":
			execute_local_action(action.action_data)
		"server":
			send_to_server({"type": action.action_data})
		"flock":
			continue_flock_encounter()

func send_combat_command(command: String):
	if not connected:
		display_game("[color=#FF0000]Not connected![/color]")
		return
	if not in_combat:
		display_game("[color=#FF0000]You are not in combat![/color]")
		return

	display_game("[color=#00FFFF]> %s[/color]" % command)
	send_to_server({"type": "combat", "command": command})

func prompt_variable_cost_ability(ability: String, resource_type: String):
	"""Prompt player to enter resource amount for variable cost ability via popup."""
	pending_variable_ability = ability
	pending_variable_resource = resource_type

	# Get current resource amount
	var current_resource = 0
	var resource_name = resource_type.capitalize()
	match resource_type:
		"mana":
			current_resource = character_data.get("current_mana", 0)
		"stamina":
			current_resource = character_data.get("current_stamina", 0)
		"energy":
			current_resource = character_data.get("current_energy", 0)

	# Show the popup
	_show_ability_popup(ability, resource_name, current_resource)

func cancel_variable_cost_ability():
	"""Cancel pending variable cost ability."""
	pending_variable_ability = ""
	pending_variable_resource = ""
	_hide_ability_popup()
	update_action_bar()

func execute_variable_cost_ability(amount: int):
	"""Execute the pending variable cost ability with specified amount."""
	if pending_variable_ability.is_empty():
		return

	var ability = pending_variable_ability

	# Remember this amount for next time
	last_ability_amounts[ability] = amount

	pending_variable_ability = ""
	pending_variable_resource = ""

	# Hide popup and send command
	_hide_ability_popup()
	send_combat_command("%s %d" % [ability, amount])
	update_action_bar()

func _create_ability_popup():
	"""Create the ability input popup panel."""
	ability_popup = Panel.new()
	ability_popup.name = "AbilityPopup"
	ability_popup.visible = false
	ability_popup.custom_minimum_size = Vector2(300, 200)
	ability_popup.size = Vector2(300, 200)

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.6, 0.5, 0.2, 1.0)  # Gold border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	ability_popup.add_theme_stylebox_override("panel", style)

	# Create VBox container
	var vbox = VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 15)
	vbox.add_theme_constant_override("separation", 10)
	ability_popup.add_child(vbox)

	# Title label
	ability_popup_title = Label.new()
	ability_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_popup_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold
	ability_popup_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(ability_popup_title)

	# Description label
	ability_popup_description = Label.new()
	ability_popup_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_popup_description.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ability_popup_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(ability_popup_description)

	# Resource label
	ability_popup_resource_label = Label.new()
	ability_popup_resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_popup_resource_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.8))  # Purple for mana
	ability_popup_resource_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(ability_popup_resource_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 5)
	vbox.add_child(spacer)

	# Input field
	ability_popup_input = LineEdit.new()
	ability_popup_input.placeholder_text = "Enter amount..."
	ability_popup_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_popup_input.custom_minimum_size = Vector2(0, 35)
	ability_popup_input.text_submitted.connect(_on_ability_popup_input_submitted)
	vbox.add_child(ability_popup_input)

	# Button container
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 20)
	vbox.add_child(button_container)

	# Confirm button
	ability_popup_confirm = Button.new()
	ability_popup_confirm.text = "Confirm"
	ability_popup_confirm.custom_minimum_size = Vector2(80, 30)
	ability_popup_confirm.pressed.connect(_on_ability_popup_confirm)
	button_container.add_child(ability_popup_confirm)

	# Cancel button
	ability_popup_cancel = Button.new()
	ability_popup_cancel.text = "Cancel"
	ability_popup_cancel.custom_minimum_size = Vector2(80, 30)
	ability_popup_cancel.pressed.connect(_on_ability_popup_cancel)
	button_container.add_child(ability_popup_cancel)

	# Add popup to the root
	add_child(ability_popup)

func _show_ability_popup(ability: String, resource_name: String, current_resource: int):
	"""Show the ability input popup with the given information."""
	if not ability_popup:
		return

	# Set popup content
	ability_popup_title.text = ability.to_upper().replace("_", " ")
	ability_popup_description.text = "Damage dealt equals %s spent." % resource_name.to_lower()
	ability_popup_resource_label.text = "Current %s: %d" % [resource_name, current_resource]

	# Color the resource label based on type
	match pending_variable_resource:
		"mana":
			ability_popup_resource_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.8))
		"stamina":
			ability_popup_resource_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3))
		"energy":
			ability_popup_resource_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))

	# Pre-populate with last used amount for this ability, or empty
	var last_amount = last_ability_amounts.get(ability, 0)
	if last_amount > 0 and last_amount <= current_resource:
		ability_popup_input.text = str(last_amount)
		ability_popup_input.placeholder_text = ""
	else:
		ability_popup_input.text = ""
		ability_popup_input.placeholder_text = "Enter amount..."

	# Center the popup on screen
	var viewport_size = get_viewport().get_visible_rect().size
	ability_popup.position = (viewport_size - ability_popup.size) / 2

	ability_popup.visible = true
	ability_popup_input.grab_focus()

func _hide_ability_popup():
	"""Hide the ability input popup."""
	if ability_popup:
		ability_popup.visible = false
		ability_popup_input.release_focus()

func _on_ability_popup_input_submitted(text: String):
	"""Handle Enter key in ability popup input field."""
	_on_ability_popup_confirm()

func _on_ability_popup_confirm():
	"""Handle confirm button in ability popup."""
	var text = ability_popup_input.text.strip_edges()

	if not text.is_valid_int():
		ability_popup_input.text = ""
		ability_popup_input.placeholder_text = "Enter a number!"
		return

	var amount = int(text)
	if amount <= 0:
		ability_popup_input.text = ""
		ability_popup_input.placeholder_text = "Must be > 0!"
		return

	# Check if player has enough resource
	var current_resource = 0
	match pending_variable_resource:
		"mana":
			current_resource = character_data.get("current_mana", 0)
		"stamina":
			current_resource = character_data.get("current_stamina", 0)
		"energy":
			current_resource = character_data.get("current_energy", 0)

	if amount > current_resource:
		ability_popup_input.text = ""
		ability_popup_input.placeholder_text = "Not enough! Max: %d" % current_resource
		return

	execute_variable_cost_ability(amount)

func _on_ability_popup_cancel():
	"""Handle cancel button in ability popup."""
	cancel_variable_cost_ability()

# ===== GAMBLING POPUP =====

func _create_gamble_popup():
	"""Create the gambling input popup panel."""
	gamble_popup = Panel.new()
	gamble_popup.name = "GamblePopup"
	gamble_popup.visible = false
	gamble_popup.custom_minimum_size = Vector2(380, 380)

	# Style the popup
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	style.border_color = Color(0.9, 0.8, 0.2, 1)  # Gold border
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	gamble_popup.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	vbox.offset_left = 20
	vbox.offset_right = -20
	vbox.offset_top = 15
	vbox.offset_bottom = -15
	gamble_popup.add_child(vbox)

	# Title
	gamble_popup_title = Label.new()
	gamble_popup_title.text = "GAMBLING - DICE GAME"
	gamble_popup_title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	gamble_popup_title.add_theme_font_size_override("font_size", 18)
	gamble_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gamble_popup_title)

	# Gold display
	gamble_popup_gold_label = Label.new()
	gamble_popup_gold_label.text = "Your gold: 0"
	gamble_popup_gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	gamble_popup_gold_label.add_theme_font_size_override("font_size", 14)
	gamble_popup_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gamble_popup_gold_label)

	# Bet range
	gamble_popup_range_label = Label.new()
	gamble_popup_range_label.text = "Bet range: 10 - 1000"
	gamble_popup_range_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	gamble_popup_range_label.add_theme_font_size_override("font_size", 13)
	gamble_popup_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gamble_popup_range_label)

	# Rules header
	var rules_header = Label.new()
	rules_header.text = "Roll 3 dice vs merchant. Higher wins!"
	rules_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	rules_header.add_theme_font_size_override("font_size", 12)
	rules_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rules_header)

	# Payout table
	var payout_rtl = RichTextLabel.new()
	payout_rtl.bbcode_enabled = true
	payout_rtl.fit_content = true
	payout_rtl.custom_minimum_size = Vector2(0, 100)
	payout_rtl.add_theme_font_size_override("normal_font_size", 11)
	payout_rtl.text = """[center][color=#FF6666]Lose 6+: Lose bet[/color]   [color=#FFAA66]Lose 1-5: Lose half[/color]
[color=#AAAAAA]Tie: Bet returned[/color]
[color=#66FF66]Win 1-5: 1.5x[/color]   [color=#66FFAA]Win 6-10: 2.5x[/color]
[color=#66FFFF]Win 11+: 3x[/color]   [color=#FFD700]Triple 6s: JACKPOT![/color][/center]"""
	vbox.add_child(payout_rtl)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 5)
	vbox.add_child(spacer)

	# Input field
	gamble_popup_input = LineEdit.new()
	gamble_popup_input.placeholder_text = "Enter bet amount..."
	gamble_popup_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	gamble_popup_input.custom_minimum_size = Vector2(0, 40)
	gamble_popup_input.add_theme_font_size_override("font_size", 16)
	gamble_popup_input.text_submitted.connect(_on_gamble_popup_input_submitted)
	vbox.add_child(gamble_popup_input)

	# Button container
	var btn_container = HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 15)
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)

	# Cancel button
	gamble_popup_cancel = Button.new()
	gamble_popup_cancel.text = "Cancel"
	gamble_popup_cancel.custom_minimum_size = Vector2(100, 35)
	gamble_popup_cancel.pressed.connect(_on_gamble_popup_cancel)
	btn_container.add_child(gamble_popup_cancel)

	# Confirm button
	gamble_popup_confirm = Button.new()
	gamble_popup_confirm.text = "Bet!"
	gamble_popup_confirm.custom_minimum_size = Vector2(100, 35)
	gamble_popup_confirm.pressed.connect(_on_gamble_popup_confirm)
	btn_container.add_child(gamble_popup_confirm)

	# Add to root
	add_child(gamble_popup)

func _show_gamble_popup(gold: int, min_bet: int, max_bet: int):
	"""Show the gambling popup with current gold and bet range."""
	if not gamble_popup:
		_create_gamble_popup()

	gamble_min_bet = min_bet
	gamble_max_bet = max_bet

	gamble_popup_gold_label.text = "Your gold: %d" % gold
	gamble_popup_range_label.text = "Bet range: %d - %d gold" % [min_bet, max_bet]

	# Pre-populate with last bet if valid, otherwise empty
	if last_gamble_bet >= min_bet and last_gamble_bet <= max_bet and last_gamble_bet <= gold:
		gamble_popup_input.text = str(last_gamble_bet)
		gamble_popup_input.placeholder_text = ""
	else:
		gamble_popup_input.text = ""
		gamble_popup_input.placeholder_text = "Enter bet amount..."

	# Center the popup on screen
	gamble_popup.position = (get_viewport().get_visible_rect().size - gamble_popup.size) / 2

	gamble_popup.visible = true
	gamble_popup_input.grab_focus()
	gamble_popup_input.select_all()

func _hide_gamble_popup():
	"""Hide the gambling popup."""
	if gamble_popup:
		gamble_popup.visible = false
		gamble_popup_input.release_focus()

func _on_gamble_popup_input_submitted(_text: String):
	"""Handle Enter key in gamble popup input field."""
	_on_gamble_popup_confirm()

func _on_gamble_popup_confirm():
	"""Handle confirm button in gamble popup."""
	var text = gamble_popup_input.text.strip_edges()

	if not text.is_valid_int():
		gamble_popup_input.text = ""
		gamble_popup_input.placeholder_text = "Enter a number!"
		return

	var amount = int(text)
	if amount < gamble_min_bet:
		gamble_popup_input.text = ""
		gamble_popup_input.placeholder_text = "Min bet: %d" % gamble_min_bet
		return

	if amount > gamble_max_bet:
		gamble_popup_input.text = ""
		gamble_popup_input.placeholder_text = "Max bet: %d" % gamble_max_bet
		return

	var gold = character_data.get("gold", 0)
	if amount > gold:
		gamble_popup_input.text = ""
		gamble_popup_input.placeholder_text = "Not enough gold!"
		return

	# Remember this bet for next time
	last_gamble_bet = amount
	pending_merchant_action = ""

	_hide_gamble_popup()
	send_to_server({"type": "merchant_gamble", "amount": amount})
	update_action_bar()

func _on_gamble_popup_cancel():
	"""Handle cancel button in gamble popup."""
	pending_merchant_action = ""
	_hide_gamble_popup()
	show_merchant_menu()
	update_action_bar()

func _has_usable_combat_items() -> bool:
	"""Check if player has any usable items for combat (potions/elixirs)."""
	var inventory = character_data.get("inventory", [])
	for item in inventory:
		var item_type = item.get("type", "")
		if "potion" in item_type or "elixir" in item_type:
			return true
	return false

func _get_player_active_path() -> String:
	"""Determine player's active path based on highest stat > threshold."""
	var stats = character_data.get("stats", {})
	var str_stat = stats.get("strength", 0)
	var int_stat = stats.get("intelligence", 0)
	var wits_stat = stats.get("wits", stats.get("charisma", 0))

	# Find highest stat above threshold
	var highest_stat = 0
	var active_path = ""

	if str_stat > PATH_STAT_THRESHOLD and str_stat > highest_stat:
		highest_stat = str_stat
		active_path = "warrior"
	if int_stat > PATH_STAT_THRESHOLD and int_stat > highest_stat:
		highest_stat = int_stat
		active_path = "mage"
	if wits_stat > PATH_STAT_THRESHOLD and wits_stat > highest_stat:
		highest_stat = wits_stat
		active_path = "trickster"

	return active_path

func _get_ability_slots_for_path(path: String) -> Array:
	"""Get ability slots for a given path."""
	match path:
		"mage":
			return MAGE_ABILITY_SLOTS
		"warrior":
			return WARRIOR_ABILITY_SLOTS
		"trickster":
			return TRICKSTER_ABILITY_SLOTS
	return []

func _get_combat_ability_actions() -> Array:
	"""Build combat ability actions based on player's path and level."""
	var abilities = []
	var player_level = character_data.get("level", 1)
	var path = _get_player_active_path()
	var ability_slots = _get_ability_slots_for_path(path)

	# Get current resources
	var current_mana = character_data.get("current_mana", 0)
	var current_stamina = character_data.get("current_stamina", 0)
	var current_energy = character_data.get("current_energy", 0)

	# Build 6 ability slots (E, R, 1, 2, 3, 4)
	for i in range(6):
		if i < ability_slots.size():
			var slot = ability_slots[i]
			var command = slot[0]
			var display_name = slot[1]
			var required_level = slot[2]
			var cost = slot[3]
			var resource_type = slot[4]

			if player_level >= required_level:
				# Check if player has enough resources
				var has_resource = true
				if resource_type == "mana" and cost > 0:
					has_resource = current_mana >= cost
				elif resource_type == "stamina":
					has_resource = current_stamina >= cost
				elif resource_type == "energy":
					has_resource = current_energy >= cost

				abilities.append({
					"label": display_name,
					"action_type": "combat",
					"action_data": command,
					"enabled": has_resource,
					"cost": cost,
					"resource_type": resource_type
				})
			else:
				# Ability not unlocked yet - show locked
				abilities.append({
					"label": "Lv%d" % required_level,
					"action_type": "none",
					"action_data": "",
					"enabled": false,
					"cost": 0,
					"resource_type": ""
				})
		else:
			# No ability for this slot
			abilities.append({
				"label": "---",
				"action_type": "none",
				"action_data": "",
				"enabled": false,
				"cost": 0,
				"resource_type": ""
			})

	return abilities

func show_combat_item_menu():
	"""Display usable items for combat selection."""
	combat_item_mode = true
	update_action_bar()

	var inventory = character_data.get("inventory", [])
	var usable_items = []

	for i in range(inventory.size()):
		var item = inventory[i]
		var item_type = item.get("type", "")
		if "potion" in item_type or "elixir" in item_type:
			usable_items.append({"index": i, "item": item})

	if usable_items.is_empty():
		display_game("[color=#FF0000]You have no usable items![/color]")
		combat_item_mode = false
		update_action_bar()
		return

	display_game("[color=#FFD700]===== USABLE ITEMS =====[/color]")
	for j in range(usable_items.size()):
		var entry = usable_items[j]
		var item = entry.item
		var item_name = item.get("name", "Unknown")
		var rarity = item.get("rarity", "common")
		var color = _get_rarity_color(rarity)
		display_game("[%d] [color=%s]%s[/color]" % [j + 1, color, item_name])
	display_game("[color=#808080]Press 1-%d to use an item, or Space to cancel.[/color]" % usable_items.size())

func cancel_combat_item_mode():
	"""Cancel combat item selection mode."""
	combat_item_mode = false
	update_action_bar()
	display_game("[color=#808080]Item use cancelled.[/color]")

func use_combat_item_by_number(number: int):
	"""Use a combat item by its display number (1-indexed)."""
	var inventory = character_data.get("inventory", [])
	var usable_items = []

	for i in range(inventory.size()):
		var item = inventory[i]
		var item_type = item.get("type", "")
		if "potion" in item_type or "elixir" in item_type:
			usable_items.append(i)  # Store actual inventory index

	if number < 1 or number > usable_items.size():
		display_game("[color=#FF0000]Invalid item number![/color]")
		return

	var actual_index = usable_items[number - 1]
	combat_item_mode = false
	update_action_bar()

	send_to_server({"type": "combat_use_item", "index": actual_index})

func continue_flock_encounter():
	"""Continue into a pending flock encounter"""
	if not flock_pending:
		return

	flock_pending = false
	flock_monster_name = ""
	send_to_server({"type": "continue_flock"})

func execute_local_action(action: String):
	match action:
		"status":
			display_character_status()
		"help":
			show_help()
		"settings":
			open_settings()
		"leaderboard":
			show_leaderboard_panel()
		"logout_character":
			logout_character()
		"logout_account":
			logout_account()
		"inventory":
			open_inventory()
		"inventory_back":
			close_inventory()
		"inventory_inspect":
			prompt_inventory_action("inspect")
		"inventory_use":
			prompt_inventory_action("use")
		"inventory_equip":
			prompt_inventory_action("equip")
		"inventory_unequip":
			prompt_inventory_action("unequip")
		"inventory_discard":
			prompt_inventory_action("discard")
		"inventory_cancel":
			cancel_inventory_action()
		"inventory_prev_page":
			if inventory_page > 0:
				inventory_page -= 1
				display_inventory()
				# Re-prompt for current action
				_reprompt_inventory_action()
				update_action_bar()
		"inventory_next_page":
			var inv = character_data.get("inventory", [])
			var total_pages = max(1, int(ceil(float(inv.size()) / INVENTORY_PAGE_SIZE)))
			if inventory_page < total_pages - 1:
				inventory_page += 1
				display_inventory()
				# Re-prompt for current action
				_reprompt_inventory_action()
				update_action_bar()
		"acknowledge_continue":
			acknowledge_continue()
		"merchant_leave":
			leave_merchant()
		"merchant_sell":
			prompt_merchant_action("sell")
		"merchant_upgrade":
			prompt_merchant_action("upgrade")
		"merchant_gamble":
			prompt_merchant_action("gamble")
		"merchant_gamble_again":
			# Repeat last bet
			if last_gamble_bet > 0:
				send_to_server({"type": "merchant_gamble", "amount": last_gamble_bet})
		"merchant_buy":
			prompt_merchant_action("buy")
		"merchant_sell_gems":
			prompt_merchant_action("sell_gems")
		"merchant_recharge":
			send_to_server({"type": "merchant_recharge"})
		"sell_all_gems":
			sell_all_gems()
		"sell_all_items":
			sell_all_items()
		"merchant_cancel":
			cancel_merchant_action()
		"upgrade_weapon":
			send_upgrade_slot("weapon")
		"upgrade_armor":
			send_upgrade_slot("armor")
		"upgrade_helm":
			send_upgrade_slot("helm")
		"upgrade_shield":
			send_upgrade_slot("shield")
		"upgrade_boots":
			send_upgrade_slot("boots")
		"upgrade_ring":
			send_upgrade_slot("ring")
		"upgrade_amulet":
			send_upgrade_slot("amulet")
		"confirm_shop_buy":
			confirm_shop_purchase()
		"cancel_shop_inspect":
			cancel_shop_inspection()
		"equip_bought_item":
			equip_bought_item()
		"skip_equip_bought":
			skip_equip_bought_item()
		"combat_item":
			show_combat_item_menu()
		"combat_item_cancel":
			cancel_combat_item_mode()
		# Trading Post actions
		"trading_post_shop":
			send_to_server({"type": "trading_post_shop"})
		"trading_post_quests":
			send_to_server({"type": "trading_post_quests"})
		"trading_post_recharge":
			send_to_server({"type": "trading_post_recharge"})
		"trading_post_leave":
			leave_trading_post()
		"trading_post_cancel":
			cancel_trading_post_action()
		# Quest actions
		"show_quests":
			send_to_server({"type": "get_quest_log"})
		"quest_cancel":
			cancel_quest_action()

func acknowledge_continue():
	"""Clear pending continue state and allow game to proceed"""
	pending_continue = false
	# Keep recent XP gain highlight visible until next XP gain
	game_output.clear()
	# Reset combat background when player continues (not during flock)
	if not flock_pending:
		reset_combat_background()
	update_action_bar()

func logout_character():
	"""Logout of current character, return to character select"""
	if not connected:
		return
	display_game("[color=#00FFFF]Switching character...[/color]")
	send_to_server({"type": "logout_character"})

func logout_account():
	"""Logout of account completely"""
	if not connected:
		return
	display_game("[color=#00FFFF]Logging out...[/color]")
	send_to_server({"type": "logout_account"})

# ===== MERCHANT FUNCTIONS =====

func leave_merchant():
	"""Leave the current merchant"""
	send_to_server({"type": "merchant_leave"})
	at_merchant = false
	merchant_data = {}
	pending_merchant_action = ""
	selected_shop_item = -1
	update_action_bar()

func prompt_merchant_action(action_type: String):
	"""Prompt for merchant action selection"""
	var inventory = character_data.get("inventory", [])
	var equipped = character_data.get("equipped", {})

	match action_type:
		"sell":
			if inventory.is_empty():
				display_game("[color=#FF0000]You have nothing to sell.[/color]")
				return
			pending_merchant_action = "sell"
			display_merchant_sell_list()
			display_game("[color=#FFD700]Press 1-%d to sell an item:[/color]" % inventory.size())
			update_action_bar()

		"upgrade":
			var slots_with_items = []
			for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
				if equipped.get(slot) != null:
					slots_with_items.append(slot)
			if slots_with_items.is_empty():
				display_game("[color=#FF0000]You have nothing equipped to upgrade.[/color]")
				return
			pending_merchant_action = "upgrade"
			display_upgrade_options()
			display_game("[color=#FFD700]Select a slot to upgrade from the action bar:[/color]")
			update_action_bar()

		"gamble":
			var gold = character_data.get("gold", 0)
			var level = character_data.get("level", 1)
			var min_bet = maxi(10, level * 10)  # Level-based minimum
			var max_bet = gold / 2

			if max_bet < min_bet:
				display_game("[color=#FF4444]You need at least %d gold to gamble at your level![/color]" % (min_bet * 2))
				return

			pending_merchant_action = "gamble"
			# Show gambling popup instead of text input
			_show_gamble_popup(gold, min_bet, max_bet)
			update_action_bar()

		"buy":
			var shop_items = merchant_data.get("shop_items", [])
			if shop_items.is_empty():
				display_game("[color=#FF0000]The merchant has nothing for sale.[/color]")
				return
			pending_merchant_action = "buy"
			display_shop_inventory()
			update_action_bar()

		"sell_gems":
			var gems = character_data.get("gems", 0)
			if gems <= 0:
				display_game("[color=#FF0000]You have no gems to sell.[/color]")
				return
			pending_merchant_action = "sell_gems"
			display_game("[color=#FFD700]===== SELL GEMS =====[/color]")
			display_game("[color=#00FFFF]Your gems: %d[/color]" % gems)
			display_game("Value: [color=#FFD700]1000 gold per gem[/color]")
			display_game("")
			display_game("[color=#808080]Total value: %d gold[/color]" % (gems * 1000))
			display_game("")
			display_game("[color=#FFD700]Enter amount to sell (or press [Q] to sell all):[/color]")
			input_field.placeholder_text = "Gems to sell..."
			input_field.grab_focus()
			update_action_bar()

func sell_all_gems():
	"""Sell all gems to merchant"""
	var gems = character_data.get("gems", 0)
	if gems <= 0:
		display_game("[color=#FF0000]You have no gems to sell.[/color]")
		return
	pending_merchant_action = ""
	send_to_server({"type": "merchant_sell_gems", "amount": gems})
	update_action_bar()

func sell_all_items():
	"""Sell all inventory items to merchant"""
	var inventory = character_data.get("inventory", [])
	if inventory.is_empty():
		display_game("[color=#FF0000]You have no items to sell.[/color]")
		return
	pending_merchant_action = ""
	send_to_server({"type": "merchant_sell_all"})
	update_action_bar()

func display_shop_inventory():
	"""Display merchant's shop inventory for purchase"""
	var shop_items = merchant_data.get("shop_items", [])
	var gold = character_data.get("gold", 0)
	var gems = character_data.get("gems", 0)
	var equipped = character_data.get("equipped", {})

	display_game("[color=#FFD700]===== MERCHANT SHOP =====[/color]")
	display_game("Your gold: %d  |  Your gems: %d" % [gold, gems])
	display_game("")

	if shop_items.is_empty():
		display_game("[color=#555555](nothing for sale)[/color]")
	else:
		for i in range(shop_items.size()):
			var item = shop_items[i]
			var rarity = item.get("rarity", "common")
			var color = _get_item_rarity_color(rarity)
			var level = item.get("level", 1)
			var price = item.get("shop_price", 100)
			var gem_price = int(ceil(price / 1000.0))
			var item_type = item.get("type", "")

			# Show comparison indicator if it's an equippable item
			var compare_text = ""
			var slot = _get_slot_for_item_type(item_type)
			if slot != "":
				var equipped_item = equipped.get(slot)
				if equipped_item != null and equipped_item is Dictionary:
					var equipped_level = equipped_item.get("level", 1)
					if level > equipped_level:
						compare_text = " [color=#00FF00]↑[/color]"
					elif level < equipped_level:
						compare_text = " [color=#FF6666]↓[/color]"
					else:
						compare_text = " [color=#FFFF66]=[/color]"
				else:
					compare_text = " [color=#00FF00]NEW[/color]"

			# Build stats string
			var stats_parts = []
			if item.get("attack", 0) > 0:
				stats_parts.append("[color=#FF6666]ATK %d[/color]" % item.attack)
			if item.get("defense", 0) > 0:
				stats_parts.append("[color=#66FFFF]DEF %d[/color]" % item.defense)
			if item.get("attack_bonus", 0) > 0:
				stats_parts.append("[color=#FF6666]+%d ATK[/color]" % item.attack_bonus)
			if item.get("defense_bonus", 0) > 0:
				stats_parts.append("[color=#66FFFF]+%d DEF[/color]" % item.defense_bonus)
			if item.get("hp_bonus", 0) > 0:
				stats_parts.append("[color=#00FF00]+%d HP[/color]" % item.hp_bonus)
			if item.get("str_bonus", 0) > 0:
				stats_parts.append("+%d STR" % item.str_bonus)
			if item.get("con_bonus", 0) > 0:
				stats_parts.append("+%d CON" % item.con_bonus)
			if item.get("dex_bonus", 0) > 0:
				stats_parts.append("+%d DEX" % item.dex_bonus)
			if item.get("int_bonus", 0) > 0:
				stats_parts.append("+%d INT" % item.int_bonus)
			if item.get("wis_bonus", 0) > 0:
				stats_parts.append("+%d WIS" % item.wis_bonus)
			if item.get("wits_bonus", 0) > 0:
				stats_parts.append("+%d WIT" % item.wits_bonus)

			var stats_str = " | ".join(stats_parts) if stats_parts.size() > 0 else ""

			display_game("[%d] [color=%s]%s[/color] (Lv%d)%s - %d gold" % [i + 1, color, item.get("name", "Unknown"), level, compare_text, price])
			if stats_str != "":
				display_game("    %s" % stats_str)

	display_game("")
	display_game("[color=#808080]Press 1-%d to buy with gold[/color]" % shop_items.size())

func handle_shop_inventory(message: Dictionary):
	"""Handle shop inventory update from server"""
	var items = message.get("items", [])
	# Update local merchant data with shop items (include full stats)
	if not merchant_data.is_empty():
		var shop_items = []
		for item in items:
			shop_items.append({
				"name": item.get("name", "Unknown"),
				"type": item.get("type", ""),
				"level": item.get("level", 1),
				"rarity": item.get("rarity", "common"),
				"shop_price": item.get("price", 100),
				# Stats for inspection
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
		merchant_data["shop_items"] = shop_items

	# Update currency display
	character_data["gold"] = message.get("gold", character_data.get("gold", 0))
	character_data["gems"] = message.get("gems", character_data.get("gems", 0))
	update_currency_display()

	# Show updated shop if still in buy mode
	if pending_merchant_action == "buy":
		display_shop_inventory()
	update_action_bar()

func handle_merchant_buy_success(message: Dictionary):
	"""Handle successful item purchase with equip option"""
	var item = message.get("item", {})
	var inv_index = message.get("inventory_index", -1)
	var is_equippable = message.get("is_equippable", false)

	if is_equippable and not item.is_empty():
		bought_item_pending_equip = item
		bought_item_inventory_index = inv_index
		pending_merchant_action = "buy_equip_prompt"

		game_output.clear()
		var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
		display_game("[color=#00FF00]Purchase successful![/color]")
		display_game("")
		display_game("[color=%s]%s[/color] added to inventory." % [rarity_color, item.get("name", "Unknown")])
		display_game("")
		display_game("[color=#FFD700]Would you like to equip it now?[/color]")
		display_game("")
		display_game("[color=#808080][Space] Equip Now  |  [Q] Keep in Inventory[/color]")
		update_action_bar()

func equip_bought_item():
	"""Equip the item that was just bought"""
	if bought_item_inventory_index < 0 or bought_item_pending_equip.is_empty():
		return

	send_to_server({"type": "equip", "index": bought_item_inventory_index})
	bought_item_pending_equip = {}
	bought_item_inventory_index = -1
	pending_merchant_action = ""
	update_action_bar()

func skip_equip_bought_item():
	"""Skip equipping and return to shop"""
	bought_item_pending_equip = {}
	bought_item_inventory_index = -1
	pending_merchant_action = ""
	game_output.clear()
	show_merchant_menu()
	update_action_bar()

func handle_gamble_result(message: Dictionary):
	"""Handle gambling result from server"""
	var success = message.get("success", false)
	var gold = message.get("gold", 0)
	var min_bet = message.get("min_bet", 10)
	var max_bet = message.get("max_bet", gold / 2)

	# Update local gold
	character_data["gold"] = gold
	update_currency_display()

	if not success:
		# Failed to gamble (not enough gold, etc.)
		display_game(message.get("message", "Gambling failed."))
		pending_merchant_action = ""
		show_merchant_menu()
		update_action_bar()
		return

	# Show dice rolls
	display_game("")
	display_game("[color=#FFD700]===== DICE ROLL =====[/color]")
	display_game(message.get("dice_message", ""))
	display_game(message.get("result_message", ""))

	# Check if won an item (play rare sound)
	var item_won = message.get("item_won")
	if item_won != null:
		var rarity = item_won.get("rarity", "common")
		var drop_value = _get_rarity_value(rarity) + 1  # +1 for gambling jackpot
		play_rare_drop_sound(drop_value)

	# Show current gold and prompt for next bet
	display_game("")
	display_game("[color=#FFD700]Your gold: %d[/color]" % gold)

	if max_bet >= min_bet and last_gamble_bet <= gold:
		display_game("[color=#808080]Press Space to bet again (%d gold) or Q to stop.[/color]" % last_gamble_bet)
		pending_merchant_action = "gamble_again"
	else:
		display_game("[color=#FF4444]You don't have enough gold to continue gambling.[/color]")
		pending_merchant_action = ""
		show_merchant_menu()

	update_action_bar()

func _get_rarity_value(rarity: String) -> int:
	"""Get numeric value for rarity (for sound threshold)"""
	match rarity:
		"common": return 0
		"uncommon": return 1
		"rare": return 2
		"epic": return 3
		"legendary": return 4
		"artifact": return 5
		_: return 0

func _calculate_drop_value(message: Dictionary) -> int:
	"""Calculate the 'rarity value' of drops for sound effect threshold"""
	var total_value = 0

	# Gems are valuable - each gem adds 1 value
	var gems = message.get("total_gems", 0)
	if gems >= 3:
		total_value += gems  # 3+ gems is significant

	# Check item drops
	var drop_data = message.get("drop_data", [])
	for item in drop_data:
		var rarity = item.get("rarity", "common")
		var rarity_val = _get_rarity_value(rarity)

		# Rare+ items are significant
		if rarity_val >= 2:  # rare or better
			total_value += rarity_val

		# Items way above level are significant (20+ levels)
		var level_diff = item.get("level_diff", 0)
		if level_diff >= 20:
			total_value += 2
		elif level_diff >= 10:
			total_value += 1

	return total_value

func cancel_merchant_action():
	"""Cancel pending merchant action"""
	pending_merchant_action = ""
	selected_shop_item = -1  # Reset shop item selection
	input_field.placeholder_text = ""  # Reset placeholder
	display_game("[color=#808080]Action cancelled.[/color]")
	show_merchant_menu()
	update_action_bar()

func select_merchant_sell_item(index: int):
	"""Sell item at index to merchant"""
	var inventory = character_data.get("inventory", [])

	if index < 0 or index >= inventory.size():
		display_game("[color=#FF0000]Invalid item number.[/color]")
		return

	# Keep in sell mode for quick multiple sales
	# pending_merchant_action stays as "sell"
	send_to_server({"type": "merchant_sell", "index": index})
	# Server will send character_update, then we refresh the sell list

func select_merchant_buy_item(index: int):
	"""Select item at index from merchant shop for inspection"""
	var shop_items = merchant_data.get("shop_items", [])

	if index < 0 or index >= shop_items.size():
		display_game("[color=#FF0000]Invalid item number.[/color]")
		return

	selected_shop_item = index
	pending_merchant_action = "buy_inspect"
	game_output.clear()
	display_shop_item_details(shop_items[index])
	update_action_bar()

func confirm_shop_purchase():
	"""Confirm purchase of the selected shop item"""
	if selected_shop_item < 0:
		display_game("[color=#FF0000]No item selected.[/color]")
		return

	var shop_items = merchant_data.get("shop_items", [])
	if selected_shop_item >= shop_items.size():
		display_game("[color=#FF0000]Invalid item selection.[/color]")
		selected_shop_item = -1
		pending_merchant_action = "buy"
		display_shop_inventory()
		update_action_bar()
		return

	var item = shop_items[selected_shop_item]
	var price = item.get("shop_price", 0)
	var gold = character_data.get("gold", 0)

	if gold < price:
		display_game("[color=#FF0000]You don't have enough gold![/color]")
		return

	send_to_server({"type": "merchant_buy", "index": selected_shop_item})
	selected_shop_item = -1
	pending_merchant_action = ""
	update_action_bar()

func cancel_shop_inspection():
	"""Cancel shop item inspection and return to shop list"""
	selected_shop_item = -1
	pending_merchant_action = "buy"
	game_output.clear()
	display_shop_inventory()
	update_action_bar()

func display_shop_item_details(item: Dictionary):
	"""Display detailed stats for a shop item"""
	var name = item.get("name", "Unknown Item")
	var item_type = item.get("type", "unknown")
	var rarity = item.get("rarity", "common")
	var level = item.get("level", 1)
	var price = item.get("shop_price", 0)
	var gem_price = int(ceil(price / 1000.0))
	var gold = character_data.get("gold", 0)
	var rarity_color = _get_item_rarity_color(rarity)

	display_game("")
	display_game("[color=%s]===== %s =====[/color]" % [rarity_color, name])
	display_game("")
	display_game("[color=#00FFFF]Type:[/color] %s" % _get_item_type_description(item_type))
	display_game("[color=#00FFFF]Rarity:[/color] [color=%s]%s[/color]" % [rarity_color, rarity.capitalize()])
	display_game("[color=#00FFFF]Level:[/color] %d" % level)
	display_game("[color=#00FFFF]Price:[/color] %d gold (%d gems)" % [price, gem_price])
	display_game("")

	# Display all stats
	var stats_shown = false
	if item.get("attack", 0) > 0:
		display_game("[color=#FF6666]+%d Attack[/color]" % item.attack)
		stats_shown = true
	if item.get("defense", 0) > 0:
		display_game("[color=#66FFFF]+%d Defense[/color]" % item.defense)
		stats_shown = true
	if item.get("attack_bonus", 0) > 0:
		display_game("[color=#FF6666]+%d Attack Bonus[/color]" % item.attack_bonus)
		stats_shown = true
	if item.get("defense_bonus", 0) > 0:
		display_game("[color=#66FFFF]+%d Defense Bonus[/color]" % item.defense_bonus)
		stats_shown = true
	if item.get("hp_bonus", 0) > 0:
		display_game("[color=#00FF00]+%d Max HP[/color]" % item.hp_bonus)
		stats_shown = true
	if item.get("str_bonus", 0) > 0:
		display_game("+%d Strength" % item.str_bonus)
		stats_shown = true
	if item.get("con_bonus", 0) > 0:
		display_game("+%d Constitution" % item.con_bonus)
		stats_shown = true
	if item.get("dex_bonus", 0) > 0:
		display_game("+%d Dexterity" % item.dex_bonus)
		stats_shown = true
	if item.get("int_bonus", 0) > 0:
		display_game("+%d Intelligence" % item.int_bonus)
		stats_shown = true
	if item.get("wis_bonus", 0) > 0:
		display_game("+%d Wisdom" % item.wis_bonus)
		stats_shown = true
	if item.get("wits_bonus", 0) > 0:
		display_game("+%d Wits" % item.wits_bonus)
		stats_shown = true

	if not stats_shown:
		display_game("[color=#808080](No stat bonuses)[/color]")

	display_game("")

	# Show comparison with equipped item
	var slot = _get_slot_for_item_type(item_type)
	if slot != "":
		var equipped = character_data.get("equipped", {})
		var equipped_item = equipped.get(slot)
		if equipped_item != null and equipped_item is Dictionary:
			display_game("[color=#E6CC80]Compared to equipped %s:[/color]" % equipped_item.get("name", "item"))
			_display_item_comparison(item, equipped_item)
		else:
			display_game("[color=#00FF00]You have nothing equipped in this slot.[/color]")
	display_game("")

	# Show affordability
	if gold >= price:
		display_game("[color=#00FF00]You can afford this item.[/color]")
	else:
		display_game("[color=#FF0000]You need %d more gold![/color]" % (price - gold))

	display_game("")
	display_game("[color=#808080][Space] Buy  |  [Q] Back to list[/color]")

func _compute_item_bonuses(item: Dictionary) -> Dictionary:
	"""Compute the actual bonuses an item provides (mirrors character.gd logic)"""
	var bonuses = {
		"attack": 0,
		"defense": 0,
		"strength": 0,
		"constitution": 0,
		"dexterity": 0,
		"intelligence": 0,
		"wisdom": 0,
		"wits": 0,
		"max_hp": 0,
		"max_mana": 0,
		"speed": 0
	}

	var item_level = item.get("level", 1)
	var item_type = item.get("type", "")
	var rarity_mult = _get_rarity_multiplier_for_status(item.get("rarity", "common"))

	# Base bonus scales with item level and rarity
	var base_bonus = int(item_level * rarity_mult)

	# Apply bonuses based on item type (mirrors character.gd)
	if "weapon" in item_type:
		bonuses.attack += base_bonus * 2
		bonuses.strength += int(base_bonus * 0.3)
	elif "armor" in item_type:
		bonuses.defense += base_bonus * 2
		bonuses.constitution += int(base_bonus * 0.3)
		bonuses.max_hp += base_bonus * 3
	elif "helm" in item_type:
		bonuses.defense += base_bonus
		bonuses.wisdom += int(base_bonus * 0.2)
	elif "shield" in item_type:
		bonuses.defense += int(base_bonus * 1.5)
		bonuses.constitution += int(base_bonus * 0.2)
	elif "ring" in item_type:
		bonuses.attack += int(base_bonus * 0.5)
		bonuses.dexterity += int(base_bonus * 0.3)
		bonuses.intelligence += int(base_bonus * 0.2)
	elif "amulet" in item_type:
		bonuses.max_mana += base_bonus * 2
		bonuses.wisdom += int(base_bonus * 0.3)
		bonuses.wits += int(base_bonus * 0.2)
	elif "boots" in item_type:
		bonuses.speed += base_bonus
		bonuses.dexterity += int(base_bonus * 0.3)
		bonuses.defense += int(base_bonus * 0.5)

	# Apply affix bonuses
	var affixes = item.get("affixes", {})
	if affixes.has("hp_bonus"):
		bonuses.max_hp += affixes.hp_bonus
	if affixes.has("attack_bonus"):
		bonuses.attack += affixes.attack_bonus
	if affixes.has("defense_bonus"):
		bonuses.defense += affixes.defense_bonus
	if affixes.has("str_bonus"):
		bonuses.strength += affixes.str_bonus
	if affixes.has("con_bonus"):
		bonuses.constitution += affixes.con_bonus
	if affixes.has("dex_bonus"):
		bonuses.dexterity += affixes.dex_bonus
	if affixes.has("int_bonus"):
		bonuses.intelligence += affixes.int_bonus
	if affixes.has("wis_bonus"):
		bonuses.wisdom += affixes.wis_bonus
	if affixes.has("wits_bonus"):
		bonuses.wits += affixes.wits_bonus

	return bonuses

func _display_item_comparison(new_item: Dictionary, old_item: Dictionary):
	"""Display stat comparison between two items using computed bonuses"""
	var new_bonuses = _compute_item_bonuses(new_item)
	var old_bonuses = _compute_item_bonuses(old_item)
	var comparisons = []

	# Compare all stats
	var stat_labels = {
		"attack": "ATK",
		"defense": "DEF",
		"max_hp": "HP",
		"max_mana": "Mana",
		"strength": "STR",
		"constitution": "CON",
		"dexterity": "DEX",
		"intelligence": "INT",
		"wisdom": "WIS",
		"wits": "WIT",
		"speed": "SPD"
	}

	for stat in stat_labels.keys():
		var new_val = new_bonuses.get(stat, 0)
		var old_val = old_bonuses.get(stat, 0)
		if new_val != old_val:
			var diff = new_val - old_val
			var color = "#00FF00" if diff > 0 else "#FF6666"
			comparisons.append("[color=%s]%+d %s[/color]" % [color, diff, stat_labels[stat]])

	# Compare level
	var new_lvl = new_item.get("level", 1)
	var old_lvl = old_item.get("level", 1)
	if new_lvl != old_lvl:
		var diff = new_lvl - old_lvl
		var color = "#00FF00" if diff > 0 else "#FF6666"
		comparisons.append("[color=%s]%+d Level[/color]" % [color, diff])

	if comparisons.size() > 0:
		display_game("  " + " | ".join(comparisons))
	else:
		display_game("  [color=#808080](No stat difference)[/color]")

	# Compare effects using computed effect descriptions
	var new_type = new_item.get("type", "")
	var old_type = old_item.get("type", "")
	var new_effect = _get_item_effect_description(new_type, new_item.get("level", 1), new_item.get("rarity", "common"))
	var old_effect = _get_item_effect_description(old_type, old_item.get("level", 1), old_item.get("rarity", "common"))

	if new_effect != old_effect:
		display_game("  [color=#FF6666]Current:[/color] %s" % old_effect)
		display_game("  [color=#00FF00]New:[/color] %s" % new_effect)

func send_upgrade_slot(slot: String):
	"""Send upgrade request for a specific equipment slot"""
	pending_merchant_action = ""
	send_to_server({"type": "merchant_upgrade", "slot": slot})
	update_action_bar()

func show_merchant_menu():
	"""Show merchant services menu"""
	var services = merchant_data.get("services", [])
	var name = merchant_data.get("name", "Merchant")
	var shop_items = merchant_data.get("shop_items", [])
	var gems = character_data.get("gems", 0)

	display_game("[color=#FFD700]===== %s =====[/color]" % name.to_upper())
	display_game("\"What can I do for you, traveler?\"")
	display_game("")

	if "sell" in services:
		display_game("[Q] Sell items")
	if "upgrade" in services:
		display_game("[W] Upgrade equipment")
	if "gamble" in services:
		display_game("[E] Gamble")
	if shop_items.size() > 0:
		display_game("[R] Buy items (%d available)" % shop_items.size())
	if gems > 0:
		display_game("[1] Sell gems (%d @ 1000g each)" % gems)
	display_game("[Space] Leave")

func display_merchant_sell_list():
	"""Display items available for sale"""
	var inventory = character_data.get("inventory", [])

	display_game("[color=#FFD700]===== SELL ITEMS =====[/color]")
	display_game("Your gold: %d" % character_data.get("gold", 0))
	display_game("")

	if inventory.is_empty():
		display_game("[color=#555555](no items to sell)[/color]")
	else:
		for i in range(inventory.size()):
			var item = inventory[i]
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var sell_price = item.get("value", 10) / 2
			display_game("%d. [color=%s]%s[/color] - [color=#FFD700]%d gold[/color]" % [
				i + 1, rarity_color, item.get("name", "Unknown"), sell_price
			])

func display_upgrade_options():
	"""Display equipped items that can be upgraded"""
	var equipped = character_data.get("equipped", {})

	display_game("[color=#FFD700]===== UPGRADE EQUIPMENT =====[/color]")
	display_game("Your gold: %d" % character_data.get("gold", 0))
	display_game("")

	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var current_level = item.get("level", 1)
			var upgrade_cost = int(pow(current_level + 1, 2) * 10)
			display_game("%s: [color=%s]%s[/color] (Lv%d)" % [
				slot.capitalize(), rarity_color, item.get("name", "Unknown"), current_level
			])
			display_game("  [color=#FFD700]Upgrade to Lv%d: %d gold[/color]" % [current_level + 1, upgrade_cost])
		else:
			display_game("%s: [color=#555555](empty)[/color]" % slot.capitalize())

func display_merchant_inventory(message: Dictionary):
	"""Display inventory sent by server for merchant interaction"""
	var items = message.get("items", [])
	var gold = message.get("gold", 0)

	display_game("[color=#FFD700]Your items for sale:[/color]")
	display_game("Gold: %d" % gold)

	for item in items:
		var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
		display_game("%d. [color=%s]%s[/color] - %d gold" % [
			item.get("index", 0) + 1,
			rarity_color,
			item.get("name", "Unknown"),
			item.get("value", 0)
		])

func process_merchant_input(input_text: String):
	"""Process input during merchant interaction (gamble bet, gem amount, buy item)"""
	var action = pending_merchant_action
	pending_merchant_action = ""
	input_field.placeholder_text = ""  # Reset placeholder

	match action:
		"gamble":
			if input_text.is_valid_int():
				var amount = int(input_text)
				send_to_server({"type": "merchant_gamble", "amount": amount})
			else:
				display_game("[color=#FF0000]Invalid bet amount.[/color]")
				show_merchant_menu()

		"sell_gems":
			if input_text.is_valid_int():
				var amount = int(input_text)
				if amount > 0:
					send_to_server({"type": "merchant_sell_gems", "amount": amount})
				else:
					display_game("[color=#FF0000]Invalid gem amount.[/color]")
					show_merchant_menu()
			else:
				display_game("[color=#FF0000]Invalid gem amount. Enter a number.[/color]")
				show_merchant_menu()

		"buy":
			if input_text.is_valid_int():
				var index = int(input_text) - 1  # Convert to 0-based
				var shop_items = merchant_data.get("shop_items", [])
				if index >= 0 and index < shop_items.size():
					send_to_server({"type": "merchant_buy", "index": index})
				else:
					display_game("[color=#FF0000]Invalid item number.[/color]")
					display_shop_inventory()
					pending_merchant_action = "buy"  # Keep in buy mode
			else:
				display_game("[color=#FF0000]Invalid item number. Enter 1-%d.[/color]" % merchant_data.get("shop_items", []).size())
				display_shop_inventory()
				pending_merchant_action = "buy"  # Keep in buy mode

		_:
			# Other actions use action bar, not text input
			display_game("[color=#FF0000]Use the action bar to select.[/color]")
			show_merchant_menu()

	update_action_bar()

# ===== PASSWORD CHANGE FUNCTIONS =====

func start_password_change():
	"""Start the password change process"""
	changing_password = true
	password_change_step = 0
	temp_old_password = ""
	temp_new_password = ""

	# Update status to show password change prompts
	if char_select_status:
		char_select_status.text = "[color=#FFD700]Enter your current password (or type 'cancel' to abort):[/color]"
	input_field.placeholder_text = "Current password..."
	input_field.secret = true
	input_field.grab_focus()

func cancel_password_change():
	"""Cancel password change process"""
	changing_password = false
	password_change_step = 0
	temp_old_password = ""
	temp_new_password = ""
	input_field.secret = false
	input_field.placeholder_text = ""

	# Return to character select if not in game
	if not has_character:
		char_select_panel.visible = true
		if char_select_status:
			char_select_status.text = "[color=#808080]Password change cancelled.[/color]"

func finish_password_change(success: bool, message: String):
	"""Complete the password change process and return to appropriate screen"""
	changing_password = false
	password_change_step = 0
	temp_old_password = ""
	temp_new_password = ""
	input_field.secret = false
	input_field.placeholder_text = ""

	# Return to character select if not in game
	if not has_character:
		char_select_panel.visible = true
		if char_select_status:
			if success:
				char_select_status.text = "[color=#00FF00]%s[/color]" % message
			else:
				char_select_status.text = "[color=#FF0000]%s[/color]" % message

func process_password_change_input(input_text: String):
	"""Process input during password change"""
	# Check for cancel
	if input_text.to_lower() == "cancel":
		cancel_password_change()
		return

	match password_change_step:
		0:  # Entered old password
			temp_old_password = input_text
			password_change_step = 1
			if char_select_status:
				char_select_status.text = "[color=#FFD700]Enter your new password (min 4 characters):[/color]"
			input_field.placeholder_text = "New password..."
			input_field.grab_focus()

		1:  # Entered new password
			if input_text.length() < 4:
				if char_select_status:
					char_select_status.text = "[color=#FF0000]Password must be at least 4 characters. Try again:[/color]"
				input_field.grab_focus()
				return

			temp_new_password = input_text
			password_change_step = 2
			if char_select_status:
				char_select_status.text = "[color=#FFD700]Confirm your new password:[/color]"
			input_field.placeholder_text = "Confirm password..."
			input_field.grab_focus()

		2:  # Entered confirm password
			if input_text != temp_new_password:
				if char_select_status:
					char_select_status.text = "[color=#FF0000]Passwords do not match. Enter new password again:[/color]"
				password_change_step = 1
				temp_new_password = ""
				input_field.placeholder_text = "New password..."
				input_field.grab_focus()
				return

			if char_select_status:
				char_select_status.text = "[color=#808080]Changing password...[/color]"

			# Send password change request
			send_to_server({
				"type": "change_password",
				"old_password": temp_old_password,
				"new_password": temp_new_password
			})

# ===== INVENTORY FUNCTIONS =====

func open_inventory():
	"""Open inventory view and switch to inventory mode"""
	inventory_mode = true
	inventory_page = 0  # Reset to first page when opening
	last_item_use_result = ""  # Clear any previous item use result
	update_action_bar()
	display_inventory()

func close_inventory():
	"""Close inventory view and return to normal mode"""
	inventory_mode = false
	update_action_bar()
	display_game("[color=#808080]Inventory closed.[/color]")

func display_inventory():
	"""Display the player's inventory and equipped items"""
	if not has_character:
		return

	var inventory = character_data.get("inventory", [])
	var equipped = character_data.get("equipped", {})

	display_game("[color=#FFD700]===== INVENTORY =====[/color]")

	# Show equipped items with level and stats
	display_game("[color=#00FFFF]Equipped:[/color]")
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var item_level = item.get("level", 1)
			var bonus_text = _get_item_bonus_summary(item)
			display_game("  %s: [color=%s]%s[/color] (Lv%d) %s" % [
				slot.capitalize(), rarity_color, item.get("name", "Unknown"), item_level, bonus_text
			])
		else:
			display_game("  %s: [color=#555555](empty)[/color]" % slot.capitalize())

	# Show total equipment bonuses
	var bonuses = _calculate_equipment_bonuses(equipped)
	if bonuses.attack > 0 or bonuses.defense > 0 or bonuses.speed > 0:
		display_game("")
		var bonus_text = "[color=#00FF00]Total Gear Bonuses: +%d Attack, +%d Defense" % [bonuses.attack, bonuses.defense]
		if bonuses.speed > 0:
			bonus_text += ", +%d Speed" % bonuses.speed
		bonus_text += "[/color]"
		display_game(bonus_text)

	# Show inventory items with comparison hints (paginated)
	display_game("")
	var total_pages = max(1, int(ceil(float(inventory.size()) / INVENTORY_PAGE_SIZE)))
	# Clamp page to valid range
	inventory_page = clamp(inventory_page, 0, total_pages - 1)

	display_game("[color=#00FFFF]Backpack (%d/20) - Page %d/%d:[/color]" % [inventory.size(), inventory_page + 1, total_pages])
	if inventory.is_empty():
		display_game("  [color=#555555](empty)[/color]")
	else:
		var start_idx = inventory_page * INVENTORY_PAGE_SIZE
		var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, inventory.size())

		for i in range(start_idx, end_idx):
			var item = inventory[i]
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var item_level = item.get("level", 1)
			var item_type = item.get("type", "")

			# Show comparison indicator if it's an equippable item
			var compare_text = ""
			var slot = _get_slot_for_item_type(item_type)
			if slot != "":
				var equipped_item = equipped.get(slot)
				if equipped_item != null and equipped_item is Dictionary:
					var equipped_level = equipped_item.get("level", 1)
					if item_level > equipped_level:
						compare_text = "[color=#00FF00]↑[/color]"
					elif item_level < equipped_level:
						compare_text = "[color=#FF6666]↓[/color]"
					else:
						compare_text = "[color=#FFFF66]=[/color]"
				else:
					compare_text = "[color=#00FF00]NEW[/color]"

			# Display number is 1-9 for current page
			var display_num = (i - start_idx) + 1
			display_game("  %d. [color=%s]%s[/color] (Lv%d) %s" % [
				display_num, rarity_color, item.get("name", "Unknown"), item_level, compare_text
			])

	display_game("")
	display_game("[color=#808080]Q=Inspect, W=Use, E=Equip, R=Unequip, 1=Discard, Space=Back[/color]")
	if total_pages > 1:
		display_game("[color=#808080]2=Prev Page, 3=Next Page[/color]")
	display_game("[color=#808080]Inspect equipped: type slot name (e.g., 'weapon')[/color]")

	# Show last item use result if any
	if last_item_use_result != "":
		display_game("")
		display_game(last_item_use_result)

func _get_item_bonus_summary(item: Dictionary) -> String:
	"""Get a short summary of item bonuses"""
	var item_type = item.get("type", "")
	var level = item.get("level", 1)
	var rarity = item.get("rarity", "common")
	var rarity_mult = _get_rarity_multiplier_for_status(rarity)
	var base = int(level * rarity_mult)

	if "weapon" in item_type:
		return "[color=#FF6666]+%d Atk[/color]" % (base * 2)
	elif "armor" in item_type:
		return "[color=#66FFFF]+%d Def[/color]" % (base * 2)
	elif "helm" in item_type:
		return "[color=#66FFFF]+%d Def[/color]" % base
	elif "shield" in item_type:
		return "[color=#66FFFF]+%d Def[/color]" % int(base * 1.5)
	elif "ring" in item_type:
		return "[color=#FF6666]+%d Atk[/color]" % int(base * 0.5)
	elif "amulet" in item_type:
		return "[color=#FF66FF]+%d Mana[/color]" % (base * 2)
	return ""

func _get_slot_for_item_type(item_type: String) -> String:
	"""Get equipment slot for an item type"""
	if "weapon" in item_type:
		return "weapon"
	elif "armor" in item_type:
		return "armor"
	elif "helm" in item_type:
		return "helm"
	elif "shield" in item_type:
		return "shield"
	elif "boots" in item_type:
		return "boots"
	elif "ring" in item_type:
		return "ring"
	elif "amulet" in item_type:
		return "amulet"
	return ""

func prompt_inventory_action(action_type: String):
	"""Prompt user for item selection for inventory action"""
	var inventory = character_data.get("inventory", [])
	var equipped = character_data.get("equipped", {})

	match action_type:
		"inspect":
			if inventory.is_empty() and _count_equipped_items(equipped) == 0:
				display_game("[color=#FF0000]No items to inspect.[/color]")
				return
			pending_inventory_action = "inspect_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Press 1-%d to inspect an item, or type slot name (weapon, armor, etc.):[/color]" % max(1, inventory.size()))
			update_action_bar()  # Show cancel option

		"use":
			if inventory.is_empty():
				display_game("[color=#FF0000]No items to use.[/color]")
				return
			pending_inventory_action = "use_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Press 1-%d to use an item:[/color]" % inventory.size())
			update_action_bar()

		"equip":
			if inventory.is_empty():
				display_game("[color=#FF0000]No items to equip.[/color]")
				return
			pending_inventory_action = "equip_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Press 1-%d to equip an item:[/color]" % inventory.size())
			update_action_bar()

		"unequip":
			var slots_with_items = []
			for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
				if equipped.get(slot) != null:
					slots_with_items.append(slot)
			if slots_with_items.is_empty():
				display_game("[color=#FF0000]No items equipped.[/color]")
				return
			pending_inventory_action = "unequip_item"
			# Display equipped items with numbers
			display_game("[color=#FFD700]===== UNEQUIP ITEM =====[/color]")
			for i in range(slots_with_items.size()):
				var slot = slots_with_items[i]
				var item = equipped.get(slot)
				var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
				display_game("%d. [color=#AAAAAA]%s:[/color] [color=%s]%s[/color]" % [i + 1, slot.capitalize(), rarity_color, item.get("name", "Unknown")])
			display_game("")
			display_game("[color=#FFD700]Press 1-%d to unequip an item:[/color]" % slots_with_items.size())
			# Store slots for number key selection
			set_meta("unequip_slots", slots_with_items)
			update_action_bar()

		"discard":
			if inventory.is_empty():
				display_game("[color=#FF0000]No items to discard.[/color]")
				return
			pending_inventory_action = "discard_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Press 1-%d to discard an item:[/color]" % inventory.size())
			update_action_bar()

func _show_unequip_slots():
	"""Display equipped items for unequipping (used after unequip to show remaining)"""
	var equipped = character_data.get("equipped", {})
	var slots_with_items = []
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		if equipped.get(slot) != null:
			slots_with_items.append(slot)

	if slots_with_items.is_empty():
		display_game("[color=#808080]No more items equipped.[/color]")
		pending_inventory_action = ""
		display_inventory()
		return

	# Display equipped items with numbers
	display_game("[color=#FFD700]===== UNEQUIP ITEM =====[/color]")
	for i in range(slots_with_items.size()):
		var slot = slots_with_items[i]
		var item = equipped.get(slot)
		var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
		display_game("%d. [color=#AAAAAA]%s:[/color] [color=%s]%s[/color]" % [i + 1, slot.capitalize(), rarity_color, item.get("name", "Unknown")])
	display_game("")
	display_game("[color=#FFD700]Press 1-%d to unequip another item, or [Space] to go back:[/color]" % slots_with_items.size())
	# Store slots for number key selection
	set_meta("unequip_slots", slots_with_items)
	update_action_bar()

func _count_equipped_items(equipped: Dictionary) -> int:
	"""Count number of equipped items"""
	var count = 0
	for slot in equipped.keys():
		if equipped.get(slot) != null:
			count += 1
	return count

func select_inventory_item(index: int):
	"""Process inventory action with selected item index (0-based)"""
	var inventory = character_data.get("inventory", [])
	var action = pending_inventory_action

	# Special handling for unequip - uses slot list instead of inventory
	if action == "unequip_item":
		var slots = get_meta("unequip_slots", [])
		if index < 0 or index >= slots.size():
			display_game("[color=#FF0000]Invalid slot number.[/color]")
			return
		var slot = slots[index]
		send_to_server({"type": "inventory_unequip", "slot": slot})
		# Stay in unequip mode for quick multiple unequips
		# pending_inventory_action stays as "unequip_item"
		# The character_update will refresh and re-show equipped items
		update_action_bar()
		return

	if index < 0 or index >= inventory.size():
		display_game("[color=#FF0000]Invalid item number.[/color]")
		display_inventory()  # Re-show inventory on error
		return

	# Process the action with the selected item
	match action:
		"inspect_item":
			inspect_item(str(index + 1))  # Convert to 1-based for existing function
			# Stay in inspect mode for inspecting more items
			pending_inventory_action = "inspect_item"
			display_game("")
			# Show page-relative item count
			var start_idx = inventory_page * INVENTORY_PAGE_SIZE
			var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, inventory.size())
			var items_on_page = end_idx - start_idx
			display_game("[color=#FFD700]Press 1-%d to inspect another item, or [Space] to go back:[/color]" % max(1, items_on_page))
			update_action_bar()
			return
		"use_item":
			awaiting_item_use_result = true  # Capture the result message
			send_to_server({"type": "inventory_use", "index": index})
			# Stay in inventory mode - character_update will refresh display
			update_action_bar()
			return
		"equip_item":
			send_to_server({"type": "inventory_equip", "index": index})
			# Stay in equip mode for quick multiple equips
			# pending_inventory_action stays as "equip_item"
			# The character_update will refresh and re-show inventory
			update_action_bar()
			return
		"discard_item":
			pending_inventory_action = ""
			var item = inventory[index]
			send_to_server({"type": "inventory_discard", "index": index})
			# Exit inventory mode after discard
			inventory_mode = false
			update_action_bar()
			return

	# Fallback - exit inventory mode
	pending_inventory_action = ""
	inventory_mode = false
	update_action_bar()

func cancel_inventory_action():
	"""Cancel pending inventory action"""
	if pending_inventory_action != "":
		pending_inventory_action = ""
		display_game("[color=#808080]Action cancelled.[/color]")
		display_inventory()  # Re-show inventory
		update_action_bar()

func _reprompt_inventory_action():
	"""Re-display the prompt for current pending inventory action after page change"""
	var inv = character_data.get("inventory", [])
	var start_idx = inventory_page * INVENTORY_PAGE_SIZE
	var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, inv.size())
	var items_on_page = end_idx - start_idx

	match pending_inventory_action:
		"inspect_item":
			display_game("[color=#FFD700]Press 1-%d to inspect an item:[/color]" % items_on_page)
		"use_item":
			display_game("[color=#FFD700]Press 1-%d to use an item:[/color]" % items_on_page)
		"equip_item":
			display_game("[color=#FFD700]Press 1-%d to equip an item:[/color]" % items_on_page)
		"discard_item":
			display_game("[color=#FFD700]Press 1-%d to discard an item:[/color]" % items_on_page)

func _get_item_rarity_color(rarity: String) -> String:
	"""Get display color for item rarity"""
	match rarity:
		"common": return "#FFFFFF"
		"uncommon": return "#1EFF00"
		"rare": return "#0070DD"
		"epic": return "#A335EE"
		"legendary": return "#FF8000"
		"artifact": return "#E6CC80"
		_: return "#FFFFFF"

# ===== COMBAT BACKGROUND FUNCTIONS =====

func set_combat_background(hex_color: String):
	"""Set the GameOutput background to a combat-themed color"""
	if not game_output or hex_color == "":
		return

	current_combat_bg_color = hex_color

	# Parse hex color and create StyleBox for RichTextLabel's "normal" style
	var color = Color(hex_color)
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = color
	stylebox.set_corner_radius_all(4)
	stylebox.set_content_margin_all(8)  # Add some padding
	game_output.add_theme_stylebox_override("normal", stylebox)

func reset_combat_background():
	"""Reset the GameOutput background to its default color"""
	if not game_output:
		return

	current_combat_bg_color = ""

	if default_game_output_stylebox:
		game_output.add_theme_stylebox_override("normal", default_game_output_stylebox)
	else:
		# Fallback to black if no default saved
		var stylebox = StyleBoxFlat.new()
		stylebox.bg_color = Color("#000000")
		stylebox.set_corner_radius_all(4)
		stylebox.set_content_margin_all(8)
		game_output.add_theme_stylebox_override("normal", stylebox)

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

	# Play level up sound if level increased
	if last_known_level > 0 and level > last_known_level:
		play_levelup_sound()
	last_known_level = level

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

	# Update the buff display panel
	update_buff_display()

func update_buff_display():
	"""Update the buff/debuff display panel in the bottom right of GameOutput"""
	if not buff_display_label:
		return

	var parts = []

	# Poison (debuff) - purple/magenta
	if character_data.get("poison_active", false):
		var poison_dmg = character_data.get("poison_damage", 0)
		var poison_turns = character_data.get("poison_turns_remaining", 0)
		parts.append("[color=#FF00FF][P%d:%d][/color]" % [poison_dmg, poison_turns])

	# Active combat buffs (round-based)
	var active_buffs = character_data.get("active_buffs", [])
	for buff in active_buffs:
		var buff_type = buff.get("type", "")
		var buff_value = buff.get("value", 0)
		var buff_dur = buff.get("duration", 0)
		var color = _get_buff_color(buff_type)
		var letter = _get_buff_letter(buff_type)
		parts.append("[color=%s][%s+%d:%d][/color]" % [color, letter, buff_value, buff_dur])

	# Persistent buffs (battle-based)
	var persistent_buffs = character_data.get("persistent_buffs", [])
	for buff in persistent_buffs:
		var buff_type = buff.get("type", "")
		var buff_value = buff.get("value", 0)
		var battles = buff.get("battles_remaining", 0)
		var color = _get_buff_color(buff_type)
		var letter = _get_buff_letter(buff_type)
		parts.append("[color=%s][%s+%d:%dB][/color]" % [color, letter, buff_value, battles])

	if parts.is_empty():
		buff_display_label.text = ""
	else:
		buff_display_label.text = "".join(parts)

func _get_buff_color(buff_type: String) -> String:
	"""Get color for buff type display"""
	match buff_type.to_lower():
		"strength": return "#FF6666"  # Red
		"defense": return "#6666FF"   # Blue
		"speed": return "#66FF66"     # Green
		"damage": return "#FF6666"    # Red
		"damage_penalty": return "#FF4444"  # Dark red (debuff)
		"defense_penalty": return "#4444FF" # Dark blue (debuff)
		_: return "#FFFFFF"  # White default

func _get_buff_letter(buff_type: String) -> String:
	"""Get short letter code for buff type"""
	match buff_type.to_lower():
		"strength": return "S"
		"defense": return "D"
		"speed": return "V"  # Velocity
		"damage": return "A"  # Attack
		"damage_penalty": return "A-"
		"defense_penalty": return "D-"
		_: return buff_type.substr(0, 1).to_upper()

func update_resource_bar():
	if not resource_bar or not has_character:
		return

	var path = _get_player_active_path()
	var current_val = 0
	var max_val = 1
	var resource_name = ""
	var bar_color = Color(0.5, 0.5, 0.5)

	match path:
		"warrior":
			current_val = character_data.get("current_stamina", 0)
			max_val = max(character_data.get("max_stamina", 1), 1)
			resource_name = "Stamina"
			bar_color = Color(0.9, 0.75, 0.1)  # Yellow
		"mage":
			current_val = character_data.get("current_mana", 0)
			max_val = max(character_data.get("max_mana", 1), 1)
			resource_name = "Mana"
			bar_color = Color(0.2, 0.7, 0.8)  # Teal
		"trickster":
			current_val = character_data.get("current_energy", 0)
			max_val = max(character_data.get("max_energy", 1), 1)
			resource_name = "Energy"
			bar_color = Color(0.1, 0.5, 0.15)  # Dark Green
		_:
			# No path - show mana by default
			current_val = character_data.get("current_mana", 0)
			max_val = max(character_data.get("max_mana", 1), 1)
			resource_name = "Mana"
			bar_color = Color(0.2, 0.7, 0.8)

	var percent = (float(current_val) / float(max_val)) * 100.0

	var fill = resource_bar.get_node("Fill")
	var label = resource_bar.get_node("ResourceLabel")

	if fill:
		fill.anchor_right = percent / 100.0
		var style = fill.get_theme_stylebox("panel").duplicate()
		style.bg_color = bar_color
		fill.add_theme_stylebox_override("panel", style)

	if label:
		label.text = "%s: %d/%d" % [resource_name, current_val, max_val]

func update_currency_display():
	if not has_character:
		return

	var gold = int(character_data.get("gold", 0))
	var gems = int(character_data.get("gems", 0))

	if gold_label:
		gold_label.text = format_number(gold)

	if gem_label:
		gem_label.text = "%d" % gems

func format_number(num: int) -> String:
	"""Format large numbers with K/M suffixes for readability"""
	if num >= 1000000:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 10000:
		return "%.1fK" % (num / 1000.0)
	else:
		return str(num)

func update_player_xp_bar():
	if not player_xp_bar or not has_character:
		return

	var current_xp = character_data.get("experience", 0)
	var xp_needed = character_data.get("experience_to_next_level", 100)
	var xp_remaining = xp_needed - current_xp
	var total_percent = (float(current_xp) / float(max(xp_needed, 1))) * 100.0

	var fill = player_xp_bar.get_node("Fill")
	if fill:
		fill.anchor_right = total_percent / 100.0
		# Set grey color for existing XP
		fill.self_modulate = Color(0.5, 0.5, 0.5, 1.0)

	# Handle recent XP gain highlight (yellow portion)
	var recent_fill = player_xp_bar.get_node_or_null("RecentFill")
	if recent_xp_gain > 0:
		# Calculate where the recent gain starts and ends
		var old_xp = current_xp - recent_xp_gain
		var old_percent = (float(old_xp) / float(max(xp_needed, 1)))
		var new_percent = total_percent / 100.0

		# Create RecentFill bar if it doesn't exist
		if recent_fill == null and fill:
			recent_fill = fill.duplicate()
			recent_fill.name = "RecentFill"
			player_xp_bar.add_child(recent_fill)
			# Move it above the grey fill
			player_xp_bar.move_child(recent_fill, fill.get_index() + 1)

		if recent_fill:
			recent_fill.visible = true
			recent_fill.anchor_left = old_percent
			recent_fill.anchor_right = new_percent
			# Yellow color for recent XP
			recent_fill.self_modulate = Color(1.0, 0.85, 0.0, 1.0)
	else:
		# No recent gain - hide the yellow bar
		if recent_fill:
			recent_fill.visible = false

	# Update XP label to show progress
	var xp_label = player_xp_bar.get_node("XPLabel")
	if xp_label:
		if recent_xp_gain > 0:
			xp_label.text = "XP: %d / %d (+%d)" % [current_xp, xp_needed, recent_xp_gain]
		else:
			xp_label.text = "XP: %d / %d (-%d to lvl)" % [current_xp, xp_needed, xp_remaining]

func update_enemy_hp_bar(enemy_name: String, enemy_level: int, damage_dealt: int):
	if not enemy_health_bar:
		return

	var enemy_key = "%s_%d" % [enemy_name, enemy_level]
	var label_node = enemy_health_bar.get_node("Label")
	var bar_container = enemy_health_bar.get_node("BarContainer")

	if label_node:
		# Display enemy name with level (color is shown in main combat text)
		label_node.text = "%s (Lvl %d):" % [enemy_name, enemy_level]
		# Set label color based on class affinity
		match current_enemy_color:
			"#FFFF00":  # Yellow - Physical
				label_node.add_theme_color_override("font_color", Color(1, 1, 0))
			"#00BFFF":  # Blue - Magical
				label_node.add_theme_color_override("font_color", Color(0, 0.75, 1))
			"#00FF00":  # Green - Cunning
				label_node.add_theme_color_override("font_color", Color(0, 1, 0))
			_:  # White - Neutral
				label_node.add_theme_color_override("font_color", Color(1, 1, 1))

	if not bar_container:
		return

	var fill = bar_container.get_node("Fill")
	var hp_label = bar_container.get_node("HPLabel")

	# Check for exact match first
	var suspected_max = 0
	var is_estimate = false
	if known_enemy_hp.has(enemy_key):
		suspected_max = known_enemy_hp[enemy_key]
	else:
		# Try to estimate based on known data from similar monsters
		suspected_max = estimate_enemy_hp(enemy_name, enemy_level)
		is_estimate = suspected_max > 0

	if suspected_max > 0:
		var suspected_current = max(0, suspected_max - damage_dealt)
		var percent = (float(suspected_current) / float(suspected_max)) * 100.0

		if fill:
			fill.anchor_right = percent / 100.0
		if hp_label:
			if is_estimate:
				hp_label.text = "~%d/%d" % [suspected_current, suspected_max]
			else:
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
	# Also store by monster name only for level-based estimation
	var monster_key = "monster_%s" % enemy_name
	if not known_enemy_hp.has(monster_key):
		known_enemy_hp[monster_key] = {}
	known_enemy_hp[monster_key][enemy_level] = total_damage

func estimate_enemy_hp(enemy_name: String, enemy_level: int) -> int:
	"""Estimate enemy HP based on knowledge from killing similar monsters.
	Returns 0 if no estimate available."""
	# First check exact match
	var enemy_key = "%s_%d" % [enemy_name, enemy_level]
	if known_enemy_hp.has(enemy_key):
		return known_enemy_hp[enemy_key]

	# Check if we have any data for this monster type
	var monster_key = "monster_%s" % enemy_name
	if known_enemy_hp.has(monster_key) and known_enemy_hp[monster_key] is Dictionary:
		var known_levels = known_enemy_hp[monster_key] as Dictionary

		# Find the closest level we have data for (prefer higher levels)
		var best_level = -1
		var best_hp = 0
		for known_level in known_levels.keys():
			if known_level is int:
				# Prefer exact match or higher level
				if known_level >= enemy_level:
					if best_level == -1 or known_level < best_level:
						best_level = known_level
						best_hp = known_levels[known_level]
				elif best_level == -1:
					# Use lower level if no higher available
					if known_level > best_level:
						best_level = known_level
						best_hp = known_levels[known_level]

		if best_level > 0 and best_hp > 0:
			# Scale HP estimate based on level difference
			# Rough formula: HP scales with level (higher level = more HP)
			var level_ratio = float(enemy_level) / float(best_level)
			return int(best_hp * level_ratio)

	return 0

func parse_damage_dealt(msg: String) -> int:
	"""Parse damage dealt by PLAYER to enemy from combat messages.
	Handles various formats with color codes. Excludes monster damage to player."""
	# First strip all BBCode tags to get clean text
	var clean_msg = msg
	var bbcode_regex = RegEx.new()
	bbcode_regex.compile("\\[/?[a-z]+[^\\]]*\\]")
	clean_msg = bbcode_regex.sub(clean_msg, "", true)

	# EXCLUDE monster damage messages (these are damage TO player, not FROM player)
	# Monster attacks: "The X attacks and deals", "X hits N times for", "to you"
	# Poison/thorns/reflect: "Poison deals", "Thorns deal", "death curse deals", "reflects X damage"
	if "attacks and deals" in clean_msg:
		return 0
	if "hits" in clean_msg and "times for" in clean_msg:
		return 0
	if "to you" in clean_msg:
		return 0
	if "Poison deals" in clean_msg:
		return 0
	if "death curse deals" in clean_msg:
		return 0
	if "reflects" in clean_msg and "damage" in clean_msg:
		return 0

	# Now look for player damage patterns
	var regex = RegEx.new()

	# Player basic attack: "You deal X damage"
	regex.compile("You deal (\\d+) damage")
	var result = regex.search(clean_msg)
	if result:
		return int(result.get_string(1))

	# Ability damage patterns: "deals X damage" (after ability name)
	# e.g., "The explosion deals 50 damage", "Your swing deals 100 damage"
	regex.compile("deals (\\d+) damage")
	result = regex.search(clean_msg)
	if result:
		return int(result.get_string(1))

	# Alternative pattern: "for X damage" (e.g., Exploit: "exploit a weakness for X damage")
	regex.compile("for (\\d+) damage")
	result = regex.search(clean_msg)
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
			display_game("[color=#00FF00]%s[/color]" % message.get("message", ""))
			game_state = GameState.LOGIN_SCREEN

		"register_success":
			if login_status:
				login_status.text = "[color=#00FF00]Account created! Please log in.[/color]"
			# Clear password fields after successful registration
			if password_field:
				password_field.text = ""
			if confirm_password_field:
				confirm_password_field.text = ""

		"register_failed":
			if login_status:
				login_status.text = "[color=#FF0000]%s[/color]" % message.get("reason", "Registration failed")

		"login_success":
			username = message.get("username", "")
			display_game("[color=#00FF00]Logged in as %s[/color]" % username)
			game_state = GameState.CHARACTER_SELECT

		"login_failed":
			if login_status:
				login_status.text = "[color=#FF0000]%s[/color]" % message.get("reason", "Login failed")

		"character_list":
			character_list = message.get("characters", [])
			can_create_character = message.get("can_create", true)
			show_character_select_panel()

		"character_loaded":
			has_character = true
			character_data = message.get("character", {})
			# Reset XP tracking for loaded character
			recent_xp_gain = 0
			xp_before_combat = 0
			show_game_ui()
			update_action_bar()
			update_player_level()
			update_player_hp_bar()
			update_resource_bar()
			update_player_xp_bar()
			update_currency_display()
			display_game("[color=#00FF00]%s[/color]" % message.get("message", ""))
			display_character_status()
			request_player_list()

		"character_created":
			has_character = true
			character_data = message.get("character", {})
			# Reset XP tracking for new character
			recent_xp_gain = 0
			xp_before_combat = 0
			show_game_ui()
			update_action_bar()
			update_player_level()
			update_player_hp_bar()
			update_resource_bar()
			update_player_xp_bar()
			update_currency_display()
			display_game("[color=#00FF00]%s[/color]" % message.get("message", ""))
			display_character_status()
			request_player_list()

		"character_deleted":
			display_game("[color=#00FFFF]%s[/color]" % message.get("message", "Character deleted"))

		"logout_character_success":
			has_character = false
			in_combat = false
			character_data = {}
			game_state = GameState.CHARACTER_SELECT
			update_action_bar()
			show_enemy_hp_bar(false)
			display_game("[color=#00FF00]%s[/color]" % message.get("message", "Logged out of character"))

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
			display_game("[color=#00FF00]%s[/color]" % message.get("message", "Logged out"))

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

		"leaderboard_top5":
			# A player entered the Hall of Heroes (top 5)
			var char_name = message.get("character_name", "Unknown")
			var level = message.get("level", 1)
			var hero_rank = message.get("rank", 1)
			display_game("[color=#FFD700]*** %s (Level %d) has entered the Hall of Heroes at #%d! ***[/color]" % [char_name, level, hero_rank])
			display_chat("[color=#FFD700]*** %s has entered the Hall of Heroes at #%d! ***[/color]" % [char_name, hero_rank])
			play_top5_sound()

		"player_list":
			update_online_players(message.get("players", []))

		"examine_result":
			# Check if this was triggered by double-click on player list
			var examined_name = message.get("name", "")
			if pending_player_info_request != "" and examined_name.to_lower() == pending_player_info_request.to_lower():
				show_player_info_popup(message)
				pending_player_info_request = ""
			else:
				display_examine_result(message)

		"location":
			var desc = message.get("description", "")
			# Don't clear game_output on location updates - map is displayed separately
			# Only update the map display panel
			update_map(desc)

		"chat":
			var sender = message.get("sender", "Unknown")
			var text = message.get("message", "")
			display_chat("[color=#00FFFF]%s:[/color] %s" % [sender, text])
			# Refresh player list when someone joins, leaves, or dies
			if "entered the realm" in text or "left the realm" in text or "has fallen" in text:
				request_player_list()
			# Show death announcements prominently everywhere
			if sender == "World" and "has fallen" in text:
				# Show on character select screen
				if char_select_panel and char_select_panel.visible and char_select_status:
					char_select_status.text = text
				# Also show in game output for players in the world
				display_game(text)

		"text":
			# Clear game output if requested (e.g., rest command)
			if message.get("clear_output", false):
				game_output.clear()
			var text_msg = message.get("message", "")
			# If awaiting item use result, store it instead of displaying immediately
			if awaiting_item_use_result:
				last_item_use_result = text_msg
				awaiting_item_use_result = false
			else:
				display_game(text_msg)

		"character_update":
			if message.has("character"):
				character_data = message.character
				update_player_level()
				update_player_hp_bar()
				update_resource_bar()
				update_player_xp_bar()
				update_currency_display()
				# Re-display inventory if in inventory mode (after use/equip/discard)
				if inventory_mode:
					# Handle pending equip/unequip actions
					if pending_inventory_action == "equip_item":
						display_inventory()
						var inv = character_data.get("inventory", [])
						var start_idx = inventory_page * INVENTORY_PAGE_SIZE
						var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, inv.size())
						var items_on_page = end_idx - start_idx
						if items_on_page > 0:
							display_game("[color=#FFD700]Press 1-%d to equip another item, or [Space] to go back:[/color]" % items_on_page)
						else:
							display_game("[color=#808080]No more items to equip.[/color]")
							pending_inventory_action = ""
					elif pending_inventory_action == "unequip_item":
						_show_unequip_slots()
					else:
						display_inventory()
				# Re-display sell list if in merchant sell mode (after selling an item)
				if at_merchant and pending_merchant_action == "sell":
					var inventory = character_data.get("inventory", [])
					if inventory.is_empty():
						display_game("[color=#808080]No more items to sell.[/color]")
						pending_merchant_action = ""
						show_merchant_menu()
					else:
						display_merchant_sell_list()
						display_game("[color=#FFD700]Press 1-%d to sell another item, or [Space] to cancel:[/color]" % inventory.size())
					update_action_bar()

		"error":
			var error_msg = message.get("message", "Unknown error")
			display_game("[color=#FF0000]Error: %s[/color]" % error_msg)
			# Update status labels if on relevant screen
			if char_create_status and char_create_panel.visible:
				char_create_status.text = "[color=#FF0000]%s[/color]" % error_msg
			if char_select_status and char_select_panel.visible:
				char_select_status.text = "[color=#FF0000]%s[/color]" % error_msg

		"status_effect":
			# Handle status effect messages (poison tick on movement, buff expiration, etc.)
			var effect_msg = message.get("message", "")
			if effect_msg != "":
				display_game(effect_msg)
			# Update HP bar since poison may have dealt damage
			if message.get("effect", "") == "poison":
				update_player_hp_bar()

		"combat_start":
			in_combat = true
			flock_pending = false
			flock_monster_name = ""
			combat_item_mode = false
			combat_outsmart_failed = false  # Reset outsmart for new combat
			update_action_bar()

			# Track XP before combat for two-color XP bar
			# Only record at start of combat chain (not flock continuations)
			if xp_before_combat == 0:
				xp_before_combat = character_data.get("experience", 0)

			# Always clear game output for fresh combat display
			game_output.clear()

			# Apply combat background color immediately
			var combat_bg_color = message.get("combat_bg_color", "")
			if combat_bg_color != "":
				set_combat_background(combat_bg_color)

			display_game(message.get("message", ""))

			var combat_state = message.get("combat_state", {})
			current_enemy_name = combat_state.get("monster_name", "Enemy")
			current_enemy_level = combat_state.get("monster_level", 1)
			current_enemy_color = combat_state.get("monster_name_color", "#FFFFFF")
			damage_dealt_to_current_enemy = 0

			# Sync resources from combat state for ability availability
			if combat_state.has("player_mana"):
				character_data["current_mana"] = combat_state.get("player_mana", 0)
				character_data["max_mana"] = combat_state.get("player_max_mana", 0)
			if combat_state.has("player_stamina"):
				character_data["current_stamina"] = combat_state.get("player_stamina", 0)
				character_data["max_stamina"] = combat_state.get("player_max_stamina", 0)
			if combat_state.has("player_energy"):
				character_data["current_energy"] = combat_state.get("player_energy", 0)
				character_data["max_energy"] = combat_state.get("player_max_energy", 0)

			show_enemy_hp_bar(true)
			update_enemy_hp_bar(current_enemy_name, current_enemy_level, 0)

		"combat_message":
			var combat_msg = message.get("message", "")
			display_game(combat_msg)

			var damage = parse_damage_dealt(combat_msg)
			if damage > 0:
				damage_dealt_to_current_enemy += damage
				update_enemy_hp_bar(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy)

		"enemy_hp_revealed":
			# Analyze ability revealed enemy HP - update the health bar
			var max_hp = message.get("max_hp", 0)
			var current_hp = message.get("current_hp", max_hp)
			if max_hp > 0 and current_enemy_name != "":
				var enemy_key = "%s_%d" % [current_enemy_name, current_enemy_level]
				known_enemy_hp[enemy_key] = max_hp
				# Also store for level-based estimation
				var monster_key = "monster_%s" % current_enemy_name
				if not known_enemy_hp.has(monster_key):
					known_enemy_hp[monster_key] = {}
				known_enemy_hp[monster_key][current_enemy_level] = max_hp
				# Calculate damage dealt from revealed HP
				damage_dealt_to_current_enemy = max_hp - current_hp
				update_enemy_hp_bar(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy)

		"combat_update":
			var state = message.get("combat_state", {})
			if not state.is_empty():
				character_data["current_hp"] = state.get("player_hp", character_data.get("current_hp", 0))
				character_data["max_hp"] = state.get("player_max_hp", character_data.get("max_hp", 1))
				# Update resources for ability availability
				character_data["current_mana"] = state.get("player_mana", character_data.get("current_mana", 0))
				character_data["max_mana"] = state.get("player_max_mana", character_data.get("max_mana", 0))
				character_data["current_stamina"] = state.get("player_stamina", character_data.get("current_stamina", 0))
				character_data["max_stamina"] = state.get("player_max_stamina", character_data.get("max_stamina", 0))
				character_data["current_energy"] = state.get("player_energy", character_data.get("current_energy", 0))
				character_data["max_energy"] = state.get("player_max_energy", character_data.get("max_energy", 0))
				# Track if outsmart failed (can't try again this combat)
				if state.get("outsmart_failed", false):
					combat_outsmart_failed = true
				update_player_hp_bar()
				update_resource_bar()
				update_action_bar()  # Refresh action bar for ability availability

		"combat_end":
			in_combat = false
			combat_item_mode = false
			combat_outsmart_failed = false  # Reset for next combat

			if message.get("victory", false):
				if damage_dealt_to_current_enemy > 0:
					record_enemy_defeated(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy)
				if message.has("character"):
					character_data = message.character
					update_player_level()
					update_player_hp_bar()
					update_resource_bar()
					update_player_xp_bar()
					update_currency_display()
				# Check for incoming flock encounter
				if message.get("flock_incoming", false):
					flock_pending = true
					flock_monster_name = message.get("flock_monster", "enemy")
					display_game("[color=#FF4444]But wait... you hear more %ss approaching![/color]" % flock_monster_name)
					display_game("[color=#FFD700]Press Space to continue...[/color]")
				else:
					# Combat chain complete - calculate total XP gain for bar display
					var current_xp = character_data.get("experience", 0)
					recent_xp_gain = current_xp - xp_before_combat
					xp_before_combat = 0  # Reset for next combat
					update_player_xp_bar()  # Update bar with new gain highlight

					# Victory without flock - show all accumulated drops
					var flock_drops = message.get("flock_drops", [])
					if flock_drops.size() > 0:
						display_game("[color=#FFD700]===== LOOT =====[/color]")
						for drop_msg in flock_drops:
							display_game(drop_msg)

					# Check for rare drops and play sound effect
					var drop_value = _calculate_drop_value(message)
					if drop_value > 0:
						play_rare_drop_sound(drop_value)

					# Pause to let player read rewards
					pending_continue = true
					display_game("[color=#808080]Press Space to continue...[/color]")
			elif message.get("fled", false):
				# Fled - reset combat XP tracking but keep previous XP gain highlight
				xp_before_combat = 0
				display_game("[color=#FFD700]You escaped from combat![/color]")
				pending_continue = true
				display_game("[color=#808080]Press Space to continue...[/color]")
			else:
				# Defeat handled by permadeath message
				pass

			update_action_bar()
			show_enemy_hp_bar(false)
			current_enemy_name = ""
			current_enemy_level = 0
			damage_dealt_to_current_enemy = 0

			# Note: Background reset is handled in acknowledge_continue() when player presses Space

		"merchant_start":
			at_merchant = true
			merchant_data = message.get("merchant", {})
			display_game(message.get("message", "A merchant appears!"))
			update_action_bar()

		"merchant_end":
			at_merchant = false
			merchant_data = {}
			pending_merchant_action = ""
			display_game(message.get("message", "The merchant departs."))
			update_action_bar()

		"merchant_inventory":
			display_merchant_inventory(message)

		"shop_inventory":
			handle_shop_inventory(message)

		"merchant_buy_success":
			handle_merchant_buy_success(message)

		"gamble_result":
			handle_gamble_result(message)

		"password_changed":
			finish_password_change(true, message.get("message", "Password changed successfully!"))

		"password_change_failed":
			finish_password_change(false, message.get("reason", "Password change failed"))

		# Trading Post messages
		"trading_post_start":
			handle_trading_post_start(message)

		"trading_post_end":
			handle_trading_post_end(message)

		"trading_post_message":
			display_game(message.get("message", ""))

		# Quest messages
		"quest_list":
			handle_quest_list(message)

		"quest_accepted":
			display_game("[color=#00FF00]%s[/color]" % message.get("message", "Quest accepted!"))
			update_action_bar()

		"quest_abandoned":
			display_game("[color=#00FFFF]%s[/color]" % message.get("message", "Quest abandoned."))

		"quest_turned_in":
			handle_quest_turned_in(message)

		"quest_progress":
			display_game(message.get("message", ""))
			# Play sound if quest is now complete (only once per quest)
			var quest_id = message.get("quest_id", "")
			if message.get("completed", false) and quest_id != "" and not quests_sound_played.has(quest_id):
				quests_sound_played[quest_id] = true
				play_quest_complete_sound()

		"quest_log":
			handle_quest_log(message)

		# Watch/Inspect messages
		"watch_request":
			handle_watch_request(message)

		"watch_approved":
			handle_watch_approved(message)

		"watch_denied":
			handle_watch_denied(message)

		"watch_output":
			handle_watch_output(message)

		"watch_location":
			handle_watch_location(message)

		"watch_character":
			handle_watch_character(message)

		"watcher_left":
			handle_watcher_left(message)

		"watched_player_left":
			handle_watched_player_left(message)

# ===== INPUT HANDLING =====

func _on_send_button_pressed():
	send_input()

func _on_input_focus_entered():
	if has_character and game_state == GameState.PLAYING:
		display_game("[color=#808080]Chat mode - type to send messages[/color]")

func _on_input_focus_exited():
	if has_character and game_state == GameState.PLAYING:
		display_game("[color=#808080]Movement mode - use numpad to move[/color]")

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
	input_field.placeholder_text = ""

	if text.is_empty():
		return

	# Check for pending inventory action (text-based fallback for unequip)
	if pending_inventory_action != "":
		var action = pending_inventory_action
		pending_inventory_action = ""
		process_inventory_action(action, text)
		# Exit inventory mode after action (except inspect which stays in inventory)
		if action != "inspect_item":
			inventory_mode = false
		update_action_bar()
		return

	# Check for pending merchant action (upgrade slot or gamble amount)
	if pending_merchant_action != "":
		process_merchant_input(text)
		return

	# Check for password change in progress
	if changing_password:
		process_password_change_input(text)
		return

	# Commands
	var command_keywords = ["help", "clear", "status", "who", "players", "examine", "ex", "inventory", "inv", "i", "watch", "unwatch"]
	var combat_keywords = ["attack", "a", "defend", "d", "flee", "f", "run"]
	var first_word = text.split(" ", false)[0].to_lower() if text.length() > 0 else ""
	var is_command = first_word in command_keywords
	var is_combat_command = first_word in combat_keywords

	if in_combat and is_combat_command:
		display_game("[color=#00FFFF]> %s[/color]" % text)
		process_command(text)
		return

	if connected and has_character and not is_command and not is_combat_command:
		display_chat("[color=#FFD700]%s:[/color] %s" % [username, text])
		send_to_server({"type": "chat", "message": text})
		return

	display_game("[color=#00FFFF]> %s[/color]" % text)
	process_command(text)

func process_inventory_action(action: String, input_text: String):
	"""Process a pending inventory action with user input (text-based fallback)"""
	match action:
		"inspect_item":
			inspect_item(input_text)

		"use_item":
			if input_text.is_valid_int():
				var index = int(input_text) - 1  # Convert to 0-based
				send_to_server({"type": "inventory_use", "index": index})
			else:
				display_game("[color=#FF0000]Invalid item number.[/color]")

		"equip_item":
			if input_text.is_valid_int():
				var index = int(input_text) - 1
				send_to_server({"type": "inventory_equip", "index": index})
			else:
				display_game("[color=#FF0000]Invalid item number.[/color]")

		"unequip_item":
			# Support both number keys and slot names for unequip
			var slots = get_meta("unequip_slots", [])
			if input_text.is_valid_int():
				var index = int(input_text) - 1
				if index >= 0 and index < slots.size():
					send_to_server({"type": "inventory_unequip", "slot": slots[index]})
				else:
					display_game("[color=#FF0000]Invalid slot number.[/color]")
			else:
				var slot = input_text.to_lower().strip_edges()
				if slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
					send_to_server({"type": "inventory_unequip", "slot": slot})
				else:
					display_game("[color=#FF0000]Invalid slot. Use: weapon, armor, helm, shield, boots, ring, amulet[/color]")

		"discard_item":
			if input_text.is_valid_int():
				var index = int(input_text) - 1
				send_to_server({"type": "inventory_discard", "index": index})
			else:
				display_game("[color=#FF0000]Invalid item number.[/color]")

func inspect_item(input_text: String):
	"""Inspect an item to see its details"""
	var inventory = character_data.get("inventory", [])
	var equipped = character_data.get("equipped", {})
	var item = null
	var source = ""

	# Check if it's a slot name
	var slot = input_text.to_lower().strip_edges()
	if slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		item = equipped.get(slot)
		source = "equipped in %s slot" % slot
		if item == null:
			display_game("[color=#FF0000]Nothing equipped in %s slot.[/color]" % slot)
			return
	elif input_text.is_valid_int():
		var index = int(input_text) - 1
		if index < 0 or index >= inventory.size():
			display_game("[color=#FF0000]Invalid item number.[/color]")
			return
		item = inventory[index]
		source = "in backpack"
	else:
		display_game("[color=#FF0000]Enter a number (1-%d) or slot name.[/color]" % inventory.size())
		return

	# Display item details
	display_item_details(item, source)

func display_item_details(item: Dictionary, source: String):
	"""Display detailed information about an item"""
	var name = item.get("name", "Unknown Item")
	var item_type = item.get("type", "unknown")
	var rarity = item.get("rarity", "common")
	var level = item.get("level", 1)
	var value = item.get("value", 0)
	var rarity_color = _get_item_rarity_color(rarity)

	display_game("")
	display_game("[color=%s]===== %s =====[/color]" % [rarity_color, name])
	display_game("[color=#808080]%s[/color]" % source.capitalize())
	display_game("")
	display_game("[color=#00FFFF]Type:[/color] %s" % _get_item_type_description(item_type))
	display_game("[color=#00FFFF]Rarity:[/color] [color=%s]%s[/color]" % [rarity_color, rarity.capitalize()])
	display_game("[color=#00FFFF]Level:[/color] %d" % level)
	display_game("[color=#00FFFF]Value:[/color] %d gold" % value)
	display_game("")
	display_game("[color=#E6CC80]Effect:[/color] %s" % _get_item_effect_description(item_type, level, rarity))

	# Show comparison with equipped item for equipment types
	var slot = _get_slot_for_item_type(item_type)
	if slot != "":
		display_game("")
		var equipped = character_data.get("equipped", {})
		var equipped_item = equipped.get(slot)
		if equipped_item != null and equipped_item is Dictionary:
			display_game("[color=#E6CC80]Compared to equipped %s:[/color]" % equipped_item.get("name", "item"))
			_display_item_comparison(item, equipped_item)
		else:
			display_game("[color=#00FF00]You have nothing equipped in this slot.[/color]")

	display_game("")

func _get_item_type_description(item_type: String) -> String:
	"""Get a readable description of the item type"""
	if "potion" in item_type:
		return "Consumable - Healing Potion"
	elif "elixir" in item_type:
		return "Consumable - Powerful Elixir"
	elif "weapon" in item_type:
		return "Weapon - Increases attack damage"
	elif "armor" in item_type:
		return "Armor - Reduces damage taken"
	elif "helm" in item_type:
		return "Helm - Head protection"
	elif "shield" in item_type:
		return "Shield - Improves defense"
	elif "ring" in item_type:
		return "Ring - Magical accessory"
	elif "amulet" in item_type:
		return "Amulet - Enchanted necklace"
	elif "gold_pouch" in item_type:
		return "Currency - Contains gold"
	elif "gem" in item_type:
		return "Treasure - Valuable gem"
	else:
		return item_type.replace("_", " ").capitalize()

func _get_item_effect_description(item_type: String, level: int, rarity: String) -> String:
	"""Get a description of what the item does (matches character.gd bonuses)"""
	var rarity_mult = _get_rarity_multiplier_for_status(rarity)
	var base_bonus = int(level * rarity_mult)

	# Check for specific buff potions first (before generic potion check)
	if "potion_speed" in item_type:
		var buff_val = 5 + level * 2
		var duration = 5 + (level / 10) * 2
		return "+%d Speed for %d rounds" % [buff_val, duration]
	elif "potion_strength" in item_type:
		var buff_val = 3 + level
		var duration = 5 + (level / 10) * 2
		return "+%d Strength for %d rounds" % [buff_val, duration]
	elif "potion_defense" in item_type:
		var buff_val = 3 + level
		var duration = 5 + (level / 10) * 2
		return "+%d Defense for %d rounds" % [buff_val, duration]
	elif "potion_power" in item_type:
		var buff_val = 8 + level * 2
		var duration = 2 + (level / 10)
		return "+%d Strength for %d battles" % [buff_val, duration]
	elif "potion_iron" in item_type:
		var buff_val = 8 + level * 2
		var duration = 2 + (level / 10)
		return "+%d Defense for %d battles" % [buff_val, duration]
	elif "potion_haste" in item_type:
		var buff_val = 15 + level * 3
		var duration = 2 + (level / 10)
		return "+%d Speed for %d battles" % [buff_val, duration]
	elif "elixir_might" in item_type:
		var buff_val = 15 + level * 3
		var duration = 5 + (level / 10) * 2
		return "+%d Strength for %d battles" % [buff_val, duration]
	elif "elixir_fortress" in item_type:
		var buff_val = 15 + level * 3
		var duration = 5 + (level / 10) * 2
		return "+%d Defense for %d battles" % [buff_val, duration]
	elif "elixir_swiftness" in item_type:
		var buff_val = 25 + level * 5
		var duration = 5 + (level / 10) * 2
		return "+%d Speed for %d battles" % [buff_val, duration]
	elif "mana" in item_type:
		# Mana potions
		var mana_amounts = {
			"mana_minor": 15 + level * 8,
			"mana_lesser": 30 + level * 10,
			"mana_standard": 50 + level * 12,
			"mana_greater": 100 + level * 15,
			"mana_superior": 200 + level * 20,
			"mana_master": 400 + level * 25
		}
		var mana = mana_amounts.get(item_type, 50 + level * 10)
		return "Restores %d Mana when used" % mana
	elif "potion" in item_type or "elixir" in item_type:
		# Healing potions/elixirs (general case)
		var heal_amounts = {
			"potion_minor": 10 + level * 10,
			"potion_lesser": 20 + level * 12,
			"potion_standard": 40 + level * 15,
			"potion_greater": 80 + level * 20,
			"potion_superior": 150 + level * 25,
			"potion_master": 300 + level * 30,
			"elixir_minor": 500 + level * 40,
			"elixir_greater": 1000 + level * 60,
			"elixir_divine": 2000 + level * 100
		}
		var heal = heal_amounts.get(item_type, level * 10)
		return "Restores %d HP when used" % heal
	elif "weapon" in item_type:
		var atk = base_bonus * 2
		var str_bonus = int(base_bonus * 0.3)
		return "+%d Attack, +%d STR" % [atk, str_bonus]
	elif "armor" in item_type:
		var def = base_bonus * 2
		var con_bonus = int(base_bonus * 0.3)
		var hp_bonus = base_bonus * 3
		return "+%d Defense, +%d CON, +%d Max HP" % [def, con_bonus, hp_bonus]
	elif "helm" in item_type:
		var def = base_bonus
		var wis_bonus = int(base_bonus * 0.2)
		return "+%d Defense, +%d WIS" % [def, wis_bonus]
	elif "shield" in item_type:
		var def = int(base_bonus * 1.5)
		var con_bonus = int(base_bonus * 0.2)
		return "+%d Defense, +%d CON" % [def, con_bonus]
	elif "ring" in item_type:
		var atk = int(base_bonus * 0.5)
		var dex_bonus = int(base_bonus * 0.3)
		var int_bonus = int(base_bonus * 0.2)
		return "+%d Attack, +%d DEX, +%d INT" % [atk, dex_bonus, int_bonus]
	elif "amulet" in item_type:
		var mana_bonus = base_bonus * 2
		var wis_bonus = int(base_bonus * 0.3)
		var wit_bonus = int(base_bonus * 0.2)
		return "+%d Max Mana, +%d WIS, +%d WIT" % [mana_bonus, wis_bonus, wit_bonus]
	elif "gold_pouch" in item_type:
		return "Contains %d-%d gold" % [level * 10, level * 50]
	elif "gem" in item_type:
		return "Worth %d gold when sold" % int(level * 100 * rarity_mult)
	else:
		return "Unknown effect"

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
		"inventory", "inv", "i":
			if has_character:
				open_inventory()
			else:
				display_game("You don't have a character yet")
		"attack", "a":
			send_to_server({"type": "combat", "command": "attack"})
		"defend", "d":
			send_to_server({"type": "combat", "command": "defend"})
		"flee", "f", "run":
			send_to_server({"type": "combat", "command": "flee"})
		"who", "players":
			request_player_list()
			display_game("[color=#808080]Refreshing player list...[/color]")
		"examine", "ex":
			if parts.size() > 1:
				var target = parts[1]
				send_to_server({"type": "examine_player", "name": target})
			else:
				display_game("[color=#FF0000]Usage: examine <playername>[/color]")
		"watch":
			if parts.size() > 1:
				var target = parts[1]
				request_watch_player(target)
			else:
				display_game("[color=#FF0000]Usage: watch <playername>[/color]")
				display_game("[color=#808080]Watch another player's game output (requires their approval).[/color]")
		"unwatch":
			stop_watching()
		"settings", "keybinds", "keys":
			if has_character:
				open_settings()
			else:
				display_game("You don't have a character yet")
		_:
			display_game("Unknown command: %s (type 'help')" % command)

# ===== CONNECTION FUNCTIONS =====

func _load_connection_settings():
	"""Load saved connection settings from config file"""
	if FileAccess.file_exists(CONNECTION_CONFIG_PATH):
		var file = FileAccess.open(CONNECTION_CONFIG_PATH, FileAccess.READ)
		if file:
			var json_str = file.get_as_text()
			file.close()
			var json = JSON.new()
			var result = json.parse(json_str)
			if result == OK:
				var data = json.data
				server_ip = data.get("last_ip", "localhost")
				server_port = int(data.get("last_port", 9080))
				saved_connections = data.get("saved_connections", [])
				# Ensure all saved connection ports are integers
				for conn in saved_connections:
					if conn.has("port"):
						conn.port = int(conn.port)
				return
	# Default values if no config
	server_ip = "localhost"
	server_port = 9080
	saved_connections = [
		{"name": "Local Server", "ip": "localhost", "port": 9080}
	]

func _save_connection_settings():
	"""Save connection settings to config file"""
	var data = {
		"last_ip": server_ip,
		"last_port": server_port,
		"saved_connections": saved_connections
	}
	var file = FileAccess.open(CONNECTION_CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

# ===== KEYBIND CONFIGURATION =====

func _load_keybinds():
	"""Load keybind configuration from config file"""
	keybinds = default_keybinds.duplicate()  # Start with defaults
	if FileAccess.file_exists(KEYBIND_CONFIG_PATH):
		var file = FileAccess.open(KEYBIND_CONFIG_PATH, FileAccess.READ)
		if file:
			var json_str = file.get_as_text()
			file.close()
			var json = JSON.new()
			var result = json.parse(json_str)
			if result == OK:
				var data = json.data
				# Merge loaded keybinds over defaults
				for key in data:
					if default_keybinds.has(key):
						keybinds[key] = int(data[key])

func _save_keybinds():
	"""Save keybind configuration to config file"""
	var file = FileAccess.open(KEYBIND_CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(keybinds, "\t"))
		file.close()
	# Update action bar hotkey labels
	update_action_bar_hotkeys()

func update_action_bar_hotkeys():
	"""Update the hotkey labels on action bar buttons to reflect current keybinds"""
	if action_hotkey_labels.is_empty():
		return

	for i in range(min(action_hotkey_labels.size(), 10)):
		var label = action_hotkey_labels[i]
		if label != null:
			var action_key = "action_%d" % i
			var keycode = keybinds.get(action_key, default_keybinds.get(action_key, KEY_SPACE))
			label.text = get_key_name(keycode)

func get_key_name(keycode: int) -> String:
	"""Convert keycode to human-readable name"""
	match keycode:
		KEY_SPACE: return "Space"
		KEY_ENTER: return "Enter"
		KEY_KP_ENTER: return "NumEnter"
		KEY_KP_0: return "Num0"
		KEY_KP_1: return "Num1"
		KEY_KP_2: return "Num2"
		KEY_KP_3: return "Num3"
		KEY_KP_4: return "Num4"
		KEY_KP_5: return "Num5"
		KEY_KP_6: return "Num6"
		KEY_KP_7: return "Num7"
		KEY_KP_8: return "Num8"
		KEY_KP_9: return "Num9"
		KEY_UP: return "Up"
		KEY_DOWN: return "Down"
		KEY_LEFT: return "Left"
		KEY_RIGHT: return "Right"
		KEY_TAB: return "Tab"
		KEY_BACKSPACE: return "Backspace"
		KEY_1: return "1"
		KEY_2: return "2"
		KEY_3: return "3"
		KEY_4: return "4"
		KEY_5: return "5"
		KEY_6: return "6"
		KEY_7: return "7"
		KEY_8: return "8"
		KEY_9: return "9"
		KEY_0: return "0"
		_: return OS.get_keycode_string(keycode)

func is_reserved_key(keycode: int) -> bool:
	"""Check if a key is reserved and cannot be rebound"""
	return keycode in [KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_TAB]

func get_keybind_conflicts(keycode: int, exclude_action: String) -> Array:
	"""Find any other actions bound to the same key"""
	var conflicts = []
	for action in keybinds:
		if action != exclude_action and keybinds[action] == keycode:
			conflicts.append(action)
	return conflicts

func open_settings():
	"""Open the settings menu"""
	settings_mode = true
	settings_submenu = ""
	rebinding_action = ""
	game_output.clear()
	display_settings_menu()
	update_action_bar()

func close_settings():
	"""Close settings and return to normal mode"""
	settings_mode = false
	settings_submenu = ""
	rebinding_action = ""
	game_output.clear()
	update_action_bar()

func display_settings_menu():
	"""Display the main settings menu"""
	display_game("[color=#FFD700]===== SETTINGS =====[/color]")
	display_game("")
	display_game("[Q] Configure Action Bar Keys")
	display_game("[W] Configure Movement Keys")
	display_game("[E] Reset All to Defaults")
	display_game("[Space] Back to Game")
	display_game("")
	display_game("[color=#808080]Current Keybinds Summary:[/color]")
	display_game("  Primary Action: [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("action_0", KEY_SPACE)))
	display_game("  Move North: [color=#00FFFF]%s[/color] / [color=#00FFFF]%s[/color]" % [get_key_name(keybinds.get("move_8", KEY_KP_8)), get_key_name(keybinds.get("move_up", KEY_UP))])
	display_game("  Hunt: [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("hunt", KEY_KP_5)))

func display_action_keybinds():
	"""Display action bar keybinds for editing"""
	display_game("[color=#FFD700]===== ACTION BAR KEYBINDS =====[/color]")
	display_game("")
	var action_names = ["Primary (Space)", "Action 1 (Q)", "Action 2 (W)", "Action 3 (E)", "Action 4 (R)", "Action 5 (1)", "Action 6 (2)", "Action 7 (3)", "Action 8 (4)", "Action 9 (5)"]
	for i in range(10):
		var action_key = "action_%d" % i
		var current_key = keybinds.get(action_key, default_keybinds[action_key])
		display_game("[%d] %s: [color=#00FFFF]%s[/color]" % [i, action_names[i], get_key_name(current_key)])
	display_game("")
	display_game("[color=#808080]Press 0-9 to rebind, or Space to go back[/color]")

func display_movement_keybinds():
	"""Display movement keybinds for editing"""
	display_game("[color=#FFD700]===== MOVEMENT KEYBINDS =====[/color]")
	display_game("")
	display_game("[color=#E6CC80]Numpad Movement:[/color]")
	display_game("[1] Northwest (7): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_7", KEY_KP_7)))
	display_game("[2] North (8): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_8", KEY_KP_8)))
	display_game("[3] Northeast (9): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_9", KEY_KP_9)))
	display_game("[4] West (4): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_4", KEY_KP_4)))
	display_game("[5] Hunt (5): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("hunt", KEY_KP_5)))
	display_game("[6] East (6): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_6", KEY_KP_6)))
	display_game("[7] Southwest (1): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_1", KEY_KP_1)))
	display_game("[8] South (2): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_2", KEY_KP_2)))
	display_game("[9] Southeast (3): [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_3", KEY_KP_3)))
	display_game("")
	display_game("[color=#E6CC80]Arrow Key Movement:[/color]")
	display_game("[Q] Up: [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_up", KEY_UP)))
	display_game("[W] Down: [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_down", KEY_DOWN)))
	display_game("[E] Left: [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_left", KEY_LEFT)))
	display_game("[R] Right: [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("move_right", KEY_RIGHT)))
	display_game("")
	display_game("[color=#808080]Press a key to rebind, or Space to go back[/color]")

func start_rebinding(action: String):
	"""Start the rebinding process for an action"""
	rebinding_action = action
	game_output.clear()
	display_game("[color=#FFD700]===== REBINDING =====[/color]")
	display_game("")
	var action_display = action.replace("_", " ").capitalize()
	display_game("Rebinding: [color=#00FFFF]%s[/color]" % action_display)
	display_game("Current key: [color=#FFD700]%s[/color]" % get_key_name(keybinds.get(action, 0)))
	display_game("")
	display_game("[color=#00FF00]Press the new key...[/color]")
	display_game("[color=#808080](Press Escape to cancel)[/color]")

func complete_rebinding(new_keycode: int):
	"""Complete the rebinding with the new key"""
	if rebinding_action.is_empty():
		return

	# Check for reserved keys
	if is_reserved_key(new_keycode):
		display_game("[color=#FF0000]That key is reserved and cannot be used.[/color]")
		await get_tree().create_timer(1.0).timeout
		start_rebinding(rebinding_action)
		return

	# Check for conflicts
	var conflicts = get_keybind_conflicts(new_keycode, rebinding_action)
	if conflicts.size() > 0:
		display_game("[color=#FFA500]Warning: This key is also bound to: %s[/color]" % ", ".join(conflicts))
		display_game("[color=#808080]The other binding will be cleared.[/color]")
		# Clear conflicting bindings
		for conflict in conflicts:
			keybinds[conflict] = 0  # Unbind

	# Set the new binding
	keybinds[rebinding_action] = new_keycode
	_save_keybinds()

	display_game("[color=#00FF00]Bound %s to %s[/color]" % [rebinding_action.replace("_", " ").capitalize(), get_key_name(new_keycode)])

	await get_tree().create_timer(0.5).timeout

	# Return to appropriate submenu
	rebinding_action = ""
	game_output.clear()
	if settings_submenu == "action_keys":
		display_action_keybinds()
	elif settings_submenu == "movement_keys":
		display_movement_keybinds()
	else:
		display_settings_menu()

func reset_keybinds_to_defaults():
	"""Reset all keybinds to default values"""
	keybinds = default_keybinds.duplicate()
	_save_keybinds()
	game_output.clear()
	display_game("[color=#00FF00]All keybinds reset to defaults![/color]")
	await get_tree().create_timer(1.0).timeout
	display_settings_menu()

func _create_connection_panel():
	"""Create the connection panel UI dynamically"""
	if connection_panel:
		return  # Already created

	connection_panel = Panel.new()
	connection_panel.name = "ConnectionPanel"
	connection_panel.custom_minimum_size = Vector2(400, 350)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	style.border_color = Color(0.0, 0.5, 0.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	connection_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 15)
	connection_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Connect to Server"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(Control.new())  # Spacer

	# Saved connections list
	var list_label = Label.new()
	list_label.text = "Saved Connections:"
	list_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(list_label)

	saved_connections_list = ItemList.new()
	saved_connections_list.custom_minimum_size = Vector2(0, 100)
	saved_connections_list.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	saved_connections_list.item_selected.connect(_on_saved_connection_selected)
	vbox.add_child(saved_connections_list)

	vbox.add_child(Control.new())  # Spacer

	# IP input
	var ip_label = Label.new()
	ip_label.text = "Server IP / Hostname:"
	ip_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(ip_label)

	server_ip_field = LineEdit.new()
	server_ip_field.placeholder_text = "e.g., localhost or 192.168.1.100"
	server_ip_field.text = server_ip
	vbox.add_child(server_ip_field)

	# Port input
	var port_label = Label.new()
	port_label.text = "Port:"
	port_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(port_label)

	server_port_field = LineEdit.new()
	server_port_field.placeholder_text = "e.g., 9080"
	server_port_field.text = str(server_port)
	vbox.add_child(server_port_field)

	vbox.add_child(Control.new())  # Spacer

	# Buttons row 1
	var btn_row1 = HBoxContainer.new()
	btn_row1.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row1)

	connect_button = Button.new()
	connect_button.text = "Connect"
	connect_button.custom_minimum_size = Vector2(120, 35)
	connect_button.pressed.connect(_on_connect_button_pressed)
	btn_row1.add_child(connect_button)

	btn_row1.add_child(Control.new())  # Spacer

	save_connection_button = Button.new()
	save_connection_button.text = "Save"
	save_connection_button.custom_minimum_size = Vector2(80, 35)
	save_connection_button.pressed.connect(_on_save_connection_pressed)
	btn_row1.add_child(save_connection_button)

	btn_row1.add_child(Control.new())  # Spacer

	delete_connection_button = Button.new()
	delete_connection_button.text = "Delete"
	delete_connection_button.custom_minimum_size = Vector2(80, 35)
	delete_connection_button.pressed.connect(_on_delete_connection_pressed)
	btn_row1.add_child(delete_connection_button)

	add_child(connection_panel)

	# Center the panel
	connection_panel.set_anchors_preset(Control.PRESET_CENTER)
	connection_panel.position = (get_viewport().get_visible_rect().size - connection_panel.size) / 2

func _refresh_saved_connections_list():
	"""Refresh the saved connections list display"""
	if not saved_connections_list:
		return
	saved_connections_list.clear()
	for conn in saved_connections:
		saved_connections_list.add_item("%s (%s:%d)" % [conn.name, conn.ip, conn.port])

func _on_saved_connection_selected(index: int):
	"""Handle selecting a saved connection"""
	if index >= 0 and index < saved_connections.size():
		var conn = saved_connections[index]
		server_ip_field.text = conn.ip
		server_port_field.text = str(conn.port)

func _on_connect_button_pressed():
	"""Handle connect button press"""
	server_ip = server_ip_field.text.strip_edges()
	var port_text = server_port_field.text.strip_edges()

	if server_ip == "":
		display_game("[color=#FF0000]Please enter a server IP or hostname.[/color]")
		return

	if not port_text.is_valid_int():
		display_game("[color=#FF0000]Please enter a valid port number.[/color]")
		return

	server_port = int(port_text)

	# Save as last used
	_save_connection_settings()

	# Hide connection panel and connect
	connection_panel.visible = false
	connect_to_server()

func _on_save_connection_pressed():
	"""Save current connection to saved list"""
	var ip = server_ip_field.text.strip_edges()
	var port_text = server_port_field.text.strip_edges()

	if ip == "" or not port_text.is_valid_int():
		display_game("[color=#FF0000]Enter valid IP and port first.[/color]")
		return

	var port = int(port_text)

	# Check if already exists
	for conn in saved_connections:
		if conn.ip == ip and conn.port == port:
			display_game("[color=#808080]Connection already saved.[/color]")
			return

	# Generate a name
	var name = ip
	if ip == "localhost" or ip == "127.0.0.1":
		name = "Local Server"

	saved_connections.append({"name": name, "ip": ip, "port": port})
	_save_connection_settings()
	_refresh_saved_connections_list()
	display_game("[color=#00FF00]Connection saved![/color]")

func _on_delete_connection_pressed():
	"""Delete selected connection from saved list"""
	var selected = saved_connections_list.get_selected_items()
	if selected.is_empty():
		display_game("[color=#808080]Select a connection to delete.[/color]")
		return

	var index = selected[0]
	if index >= 0 and index < saved_connections.size():
		saved_connections.remove_at(index)
		_save_connection_settings()
		_refresh_saved_connections_list()
		display_game("[color=#808080]Connection deleted.[/color]")

func show_connection_panel():
	"""Show the connection panel"""
	if not connection_panel:
		_create_connection_panel()

	_refresh_saved_connections_list()
	server_ip_field.text = server_ip
	server_port_field.text = str(server_port)

	# Center the panel
	connection_panel.position = (get_viewport().get_visible_rect().size - connection_panel.size) / 2
	connection_panel.visible = true

	# Hide other panels
	if login_panel:
		login_panel.visible = false
	if char_select_panel:
		char_select_panel.visible = false

func connect_to_server():
	var status = connection.get_status()

	if status == StreamPeerTCP.STATUS_CONNECTED:
		display_game("[color=#00FFFF]Already connected![/color]")
		return

	if status == StreamPeerTCP.STATUS_CONNECTING:
		display_game("[color=#00FFFF]Connection in progress...[/color]")
		return

	display_game("Connecting to %s:%d..." % [server_ip, server_port])
	var error = connection.connect_to_host(server_ip, server_port)
	if error != OK:
		display_game("[color=#FF0000]Failed to connect! Error: %d[/color]" % error)
		display_game("[color=#808080]Press Enter to try again or change server.[/color]")
		# Show connection panel again on failure
		call_deferred("show_connection_panel")
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
	show_connection_panel()

func send_to_server(data: Dictionary):
	if not connected:
		display_game("[color=#FF0000]Not connected![/color]")
		return

	var json_str = JSON.stringify(data) + "\n"
	connection.put_data(json_str.to_utf8_buffer())

func send_move(direction: int):
	if not connected or not has_character:
		return

	send_to_server({"type": "move", "direction": direction})

func _on_move_button(direction: int):
	"""Handle movement pad button press"""
	if not connected or not has_character:
		return
	if in_combat or flock_pending or pending_continue or inventory_mode or at_merchant:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_move_time >= MOVE_COOLDOWN:
		send_move(direction)
		game_output.clear()
		last_move_time = current_time

func _on_hunt_button():
	"""Handle Hunt button press - searches for monsters with increased encounter chance"""
	if not connected or not has_character:
		return
	if in_combat or flock_pending or pending_continue or inventory_mode or at_merchant:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_move_time >= MOVE_COOLDOWN:
		game_output.clear()
		send_to_server({"type": "hunt"})
		last_move_time = current_time

# ===== DISPLAY FUNCTIONS =====

func display_character_status():
	if not has_character:
		return

	var char = character_data
	var stats = char.get("stats", {})
	var equipped = char.get("equipped", {})
	var bonuses = _calculate_equipment_bonuses(equipped)

	var current_xp = char.get("experience", 0)
	var xp_needed = char.get("experience_to_next_level", 100)
	var xp_remaining = xp_needed - current_xp

	var text = "[b][color=#FFD700]Character Status[/color][/b]\n"
	text += "Name: %s\n" % char.get("name", "Unknown")
	text += "Race: %s\n" % char.get("race", "Human")
	text += "Class: %s\n" % char.get("class", "Unknown")
	text += "Level: %d\n" % char.get("level", 1)
	text += "[color=#FF00FF]Experience:[/color] %d / %d ([color=#FFD700]%d to next level[/color])\n" % [current_xp, xp_needed, xp_remaining]
	text += "HP: %d/%d (%s)\n" % [char.get("current_hp", 0), char.get("max_hp", 0), char.get("health_state", "Unknown")]
	text += "[color=#FFD700]Mana:[/color] %d/%d  [color=#FF4444]Stamina:[/color] %d/%d  [color=#00FF00]Energy:[/color] %d/%d\n" % [
		char.get("current_mana", 0), char.get("max_mana", 0),
		char.get("current_stamina", 0), char.get("max_stamina", 0),
		char.get("current_energy", 0), char.get("max_energy", 0)
	]
	text += "Gold: %d\n" % char.get("gold", 0)
	text += "Position: (%d, %d)\n" % [char.get("x", 0), char.get("y", 0)]
	text += "Monsters Killed: %d\n\n" % char.get("monsters_killed", 0)

	# Base stats with equipment bonuses shown
	text += "[color=#00FFFF]Base Stats:[/color]\n"
	text += "  STR: %d" % stats.get("strength", 0)
	if bonuses.strength > 0:
		text += " [color=#00FF00](+%d)[/color]" % bonuses.strength
	text += "  CON: %d" % stats.get("constitution", 0)
	if bonuses.constitution > 0:
		text += " [color=#00FF00](+%d)[/color]" % bonuses.constitution
	text += "  DEX: %d" % stats.get("dexterity", 0)
	if bonuses.dexterity > 0:
		text += " [color=#00FF00](+%d)[/color]" % bonuses.dexterity
	text += "\n"
	text += "  INT: %d" % stats.get("intelligence", 0)
	if bonuses.intelligence > 0:
		text += " [color=#00FF00](+%d)[/color]" % bonuses.intelligence
	text += "  WIS: %d" % stats.get("wisdom", 0)
	if bonuses.wisdom > 0:
		text += " [color=#00FF00](+%d)[/color]" % bonuses.wisdom
	text += "  WIT: %d" % stats.get("wits", stats.get("charisma", 0))
	if bonuses.wits > 0:
		text += " [color=#00FF00](+%d)[/color]" % bonuses.wits
	text += "\n\n"

	# Combat stats
	var total_attack = stats.get("strength", 0) + bonuses.strength + bonuses.attack
	var total_defense = (stats.get("constitution", 0) + bonuses.constitution) / 2 + bonuses.defense

	text += "[color=#FF6666]Combat Stats:[/color]\n"
	text += "  Attack Power: %d" % total_attack
	if bonuses.attack > 0:
		text += " [color=#00FF00](+%d from gear)[/color]" % bonuses.attack
	text += "\n"
	text += "  Defense: %d" % total_defense
	if bonuses.defense > 0:
		text += " [color=#00FF00](+%d from gear)[/color]" % bonuses.defense
	text += "\n"
	text += "  Damage: %d-%d\n" % [int(total_attack * 0.8), int(total_attack * 1.2)]
	if bonuses.speed > 0:
		text += "  [color=#00FFFF]Speed: +%d (flee bonus from boots)[/color]\n" % bonuses.speed

	# Active Effects section
	var effects_text = _get_status_effects_text()
	if effects_text != "":
		text += "\n" + effects_text

	display_game(text)

func _get_status_effects_text() -> String:
	"""Generate status effects section for character status display"""
	var lines = []

	# Poison (debuff)
	if character_data.get("poison_active", false):
		var poison_dmg = character_data.get("poison_damage", 0)
		var poison_turns = character_data.get("poison_turns_remaining", 0)
		lines.append("  [color=#FF00FF]Poisoned[/color] - %d damage/round, %d rounds remaining" % [poison_dmg, poison_turns])

	# Active combat buffs (round-based)
	var active_buffs = character_data.get("active_buffs", [])
	for buff in active_buffs:
		var buff_type = buff.get("type", "").capitalize()
		var buff_value = buff.get("value", 0)
		var buff_dur = buff.get("duration", 0)
		var color = _get_buff_color(buff_type.to_lower())
		lines.append("  [color=%s]%s +%d[/color] - %d rounds remaining" % [color, buff_type, buff_value, buff_dur])

	# Persistent buffs (battle-based)
	var persistent_buffs = character_data.get("persistent_buffs", [])
	for buff in persistent_buffs:
		var buff_type = buff.get("type", "").capitalize()
		var buff_value = buff.get("value", 0)
		var battles = buff.get("battles_remaining", 0)
		var color = _get_buff_color(buff_type.to_lower())
		lines.append("  [color=%s]%s +%d[/color] - %d battles remaining" % [color, buff_type, buff_value, battles])

	if lines.is_empty():
		return ""

	return "[color=#AAFFAA]Active Effects:[/color]\n" + "\n".join(lines)

func _calculate_equipment_bonuses(equipped: Dictionary) -> Dictionary:
	"""Calculate total bonuses from equipped items (client-side mirror of Character method)"""
	var bonuses = {
		"attack": 0,
		"defense": 0,
		"strength": 0,
		"constitution": 0,
		"dexterity": 0,
		"intelligence": 0,
		"wisdom": 0,
		"wits": 0,
		"max_hp": 0,
		"max_mana": 0,
		"speed": 0
	}

	for slot in equipped.keys():
		var item = equipped.get(slot)
		if item == null or not item is Dictionary:
			continue

		var item_level = item.get("level", 1)
		var item_type = item.get("type", "")
		var rarity_mult = _get_rarity_multiplier_for_status(item.get("rarity", "common"))

		var base_bonus = int(item_level * rarity_mult)

		if "weapon" in item_type:
			bonuses.attack += base_bonus * 2
			bonuses.strength += int(base_bonus * 0.3)
		elif "armor" in item_type:
			bonuses.defense += base_bonus * 2
			bonuses.constitution += int(base_bonus * 0.3)
			bonuses.max_hp += base_bonus * 3
		elif "helm" in item_type:
			bonuses.defense += base_bonus
			bonuses.wisdom += int(base_bonus * 0.2)
		elif "shield" in item_type:
			bonuses.defense += int(base_bonus * 1.5)
			bonuses.constitution += int(base_bonus * 0.2)
		elif "ring" in item_type:
			bonuses.attack += int(base_bonus * 0.5)
			bonuses.dexterity += int(base_bonus * 0.3)
			bonuses.intelligence += int(base_bonus * 0.2)
		elif "amulet" in item_type:
			bonuses.max_mana += base_bonus * 2
			bonuses.wisdom += int(base_bonus * 0.3)
			bonuses.wits += int(base_bonus * 0.2)
		elif "boots" in item_type:
			bonuses.speed += base_bonus
			bonuses.dexterity += int(base_bonus * 0.3)
			bonuses.defense += int(base_bonus * 0.5)

	return bonuses

func _get_rarity_multiplier_for_status(rarity: String) -> float:
	"""Get multiplier for item rarity"""
	match rarity:
		"common": return 1.0
		"uncommon": return 1.5
		"rare": return 2.0
		"epic": return 3.0
		"legendary": return 4.5
		"artifact": return 6.0
		_: return 1.0

func show_help():
	var help_text = """
[b]Available Commands:[/b]

[color=#00FFFF]Movement:[/color]
  Press Escape to toggle movement mode
  Use NUMPAD: 7 8 9 = NW N NE
              4 5 6 = W stay E
              1 2 3 = SW S SE

[color=#00FFFF]Chat:[/color]
  Just type and press Enter!

[color=#00FFFF]Action Bar:[/color]
  [Space] = Primary action (Status/Attack)
  [Q][W][E][R] = Quick actions
  [1][2][3][4] = Additional actions

[color=#00FFFF]Inventory:[/color]
  inventory/inv/i - Open inventory
  [Q] Inventory in movement mode
  Equip/Unequip stays in mode for quick multi-select

[color=#00FFFF]Social:[/color]
  who/players - Refresh player list
  examine <name> - View player stats
  watch <name> - Watch another player's game
  unwatch - Stop watching

[color=#00FFFF]Other:[/color]
  help - This help
  status - Show stats
  clear - Clear screens

[color=#00FFFF]Gems (Premium Currency):[/color]
  • Drop from monsters 5+ levels higher than you
  • Higher level difference = better drop chance
  • Sell to merchants for 1000 gold each
  • Pay for equipment upgrades (1 gem = 1000g)
  • Multiply quest rewards in danger zones

[color=#FF6600]! = Danger Zone[/color] (hotspot with boosted monster levels)

[b][color=#FFD700]== CHARACTER STATS ==[/color][/b]

[color=#FF6666]STR (Strength)[/color] - Primary damage stat
  • Increases physical attack damage (+2% per point)
  • Higher STR = hit harder in combat

[color=#66FF66]CON (Constitution)[/color] - Health and defense
  • Determines max HP (base 50 + CON × 5)
  • Reduces damage taken (-1% per point, up to 30%)
  • Essential for survival against tough monsters

[color=#66FFFF]DEX (Dexterity)[/color] - Speed and evasion
  • Increases hit chance (+1% per point)
  • Improves flee success rate (+2% per point)
  • Affects who strikes first in combat

[color=#FF66FF]INT (Intelligence)[/color] - Magic power
  • Increases spell damage (+3% per point)
  • Determines max Mana (base 20 + INT × 3)
  • Used for special abilities

[color=#FFFF66]WIS (Wisdom)[/color] - Magic defense
  • Reduces magic damage taken (-1.5% per point)
  • Improves mana regeneration
  • Helps resist special attacks

[color=#FFA500]WIT (Wits)[/color] - Outsmarting enemies
  • Enables the Outsmart combat action
  • Higher Wits vs monster Intelligence = more success
  • Essential stat for Trickster builds

[b][color=#FFD700]== COMBAT MECHANICS ==[/color][/b]

[color=#00FFFF]Attack Damage:[/color]
  Base damage = STR × weapon modifier
  Final damage = Base × (1 + level/50) - enemy defense
  Critical hits deal 1.5x damage (chance based on DEX)

[color=#00FFFF]Defense:[/color]
  Damage reduction = CON% (max 30%)
  Armor adds flat reduction
  Block chance when defending = 25% + DEX/2

[color=#00FFFF]Hit Chance:[/color]
  Base hit = 75% + (your DEX - enemy DEX)
  Minimum 50%, maximum 95%

[color=#00FFFF]Flee Chance:[/color]
  Base flee = 40% + (your DEX × 2) - (enemy level / 10)
  Defending enemies: +20% flee chance
  Failed flee = enemy gets free attack

[color=#00FFFF]Combat Tips:[/color]
  • Defend reduces damage by 50% and boosts next attack
  • Special attacks cost mana but deal bonus damage
  • Monster level affects all their stats
  • Higher tier monsters are tougher but give better rewards

[b][color=#FFD700]== RACE PASSIVES ==[/color][/b]

[color=#FFFFFF]Human[/color] - Adaptable and ambitious
  • +10% bonus XP from all sources
  • Best for leveling quickly

[color=#66FF99]Elf[/color] - Ancient and resilient
  • 50% reduced poison damage
  • Immune to poison debuffs
  • Good against venomous creatures

[color=#FFA366]Dwarf[/color] - Sturdy and determined
  • Last Stand: 25% chance to survive lethal damage with 1 HP
  • Triggers once per combat
  • Great for risky fights

[color=#8B4513]Ogre[/color] - Massive and regenerative
  • All healing effects are doubled (2x)
  • Includes potions, regen, and other heals
  • Great for sustained combat

[b][color=#FFD700]== CLASS OVERVIEW ==[/color][/b]

[color=#FF6666]Warrior Path[/color] (STR > 10) - Uses Stamina
  [color=#FFCC00]Fighter[/color] - Balanced melee with solid defense/offense
  [color=#FFCC00]Barbarian[/color] - Aggressive berserker, high damage, low defense

[color=#66FFFF]Mage Path[/color] (INT > 10) - Uses Mana
  [color=#66CCCC]Wizard[/color] - Pure spellcaster, high magic damage
  [color=#66CCCC]Sage[/color] - Balanced scholar with utility focus

[color=#66FF66]Trickster Path[/color] (WITS > 10) - Uses Energy
  [color=#90EE90]Thief[/color] - Cunning rogue, evasion and crits
  [color=#90EE90]Ranger[/color] - Versatile scout, balanced combat

[b][color=#FFD700]== WATCH FEATURE ==[/color][/b]

Watch another player's game in real-time!
  • Type [color=#FFFF00]watch <name>[/color] to request watching a player
  • Watched player presses [Q] to approve, [W] to deny
  • While watching, you see their game, map, and stats
  • Press [color=#FFFF00][Escape][/color] to stop watching
  • Type [color=#FFFF00]unwatch[/color] to stop watching

[b][color=#FFD700]== WARRIOR ABILITIES (STR Path) ==[/color][/b]
Uses [color=#FFCC00]Stamina[/color] = STR×4 + CON×4, regens 10% when defending
Damage abilities use [color=#FFCC00]Attack[/color] = STR + weapon bonuses

[color=#FF6666]Lv 1 - Power Strike[/color] (10 Stamina)
  Deal Attack × 1.5 damage

[color=#FF6666]Lv 10 - War Cry[/color] (15 Stamina)
  +25% damage for 3 rounds

[color=#FF6666]Lv 25 - Shield Bash[/color] (20 Stamina)
  Deal Attack damage + stun (enemy skips turn)

[color=#FF6666]Lv 40 - Cleave[/color] (30 Stamina)
  Deal Attack × 2 damage

[color=#FF6666]Lv 60 - Berserk[/color] (40 Stamina)
  +100% damage, -50% defense for 3 rounds

[color=#FF6666]Lv 80 - Iron Skin[/color] (35 Stamina)
  Block 50% damage for 3 rounds

[color=#FF6666]Lv 100 - Devastate[/color] (50 Stamina)
  Deal Attack × 4 damage

[b][color=#FFD700]== MAGE ABILITIES (INT Path) ==[/color][/b]
Uses [color=#66CCCC]Mana[/color] = INT×8 + WIS×4
Damage abilities use [color=#66CCCC]Magic[/color] = INT + equipment bonuses

[color=#66FFFF]Lv 1 - Magic Bolt[/color] (Variable Mana)
  Deal damage equal to mana spent (1:1 ratio)

[color=#66FFFF]Lv 10 - Shield[/color] (20 Mana)
  +50% defense for 3 rounds

[color=#66FFFF]Lv 25 - Cloak[/color] (30 Mana)
  50% chance enemy misses next attack

[color=#66FFFF]Lv 40 - Blast[/color] (50 Mana)
  Deal Magic × 2 damage

[color=#66FFFF]Lv 60 - Forcefield[/color] (75 Mana)
  Block next 2 attacks completely

[color=#66FFFF]Lv 80 - Teleport[/color] (40 Mana)
  Guaranteed flee (always succeeds)

[color=#66FFFF]Lv 100 - Meteor[/color] (100 Mana)
  Deal Magic × 5 damage

[b][color=#FFD700]== TRICKSTER ABILITIES (WITS Path) ==[/color][/b]
Uses [color=#66FF66]Energy[/color] = WITS×4 + DEX×4, regens 15% per round
WITS abilities include equipment bonuses

[color=#FFA500]Lv 1 - Analyze[/color] (5 Energy)
  Reveal monster stats (HP, damage, intelligence)

[color=#FFA500]Lv 10 - Distract[/color] (15 Energy)
  Enemy has -50% accuracy on next attack

[color=#FFA500]Lv 25 - Pickpocket[/color] (20 Energy)
  Steal WITS × 10 gold (fail = monster attacks)

[color=#FFA500]Lv 40 - Ambush[/color] (30 Energy)
  Deal (Attack + WITS/2) × 1.5 damage + 50% crit chance

[color=#FFA500]Lv 60 - Vanish[/color] (40 Energy)
  Invisible, guaranteed crit on next attack

[color=#FFA500]Lv 80 - Exploit[/color] (35 Energy)
  Deal 10% of monster's current HP as damage

[color=#FFA500]Lv 100 - Perfect Heist[/color] (50 Energy)
  Instant win + double gold/gems

[b][color=#FFD700]== OUTSMART (WITS-based) ==[/color][/b]

[color=#FFA500]Outsmart[/color] - Trick dumb monsters
  Base chance: 5%
  +5% per WITS above 10 (main factor!)
  +15% bonus for Trickster classes
  +8% per monster INT below 10 (dumb = easy)
  -8% per monster INT above 10 (smart = hard)
  -5% if monster INT exceeds your WITS
  Clamped 2-85% (Tricksters: 2-95%)

  [color=#00FF00]Best against:[/color] Low INT monsters (beasts, undead)
  [color=#FF4444]Worst against:[/color] High INT monsters (mages, dragons)

  Success: Instant win with full rewards
  Failure: Monster gets free attack, can't retry

[b][color=#FFD700]== TRADING POSTS (58 Total) ==[/color][/b]

Safe zones with services and quests:
  • [color=#00FF00]Haven[/color] (0,10) - Starting area, beginner quests
  • [color=#00FF00]Crossroads[/color] (0,0) - Hotzone quests, dailies
  • [color=#00FF00]Frostgate[/color] (0,-100) - Boss hunts, exploration
  • And 55 more across the world!

Posts are [color=#FFFF00]denser near the center[/color], sparser at edges.
World's Edge posts (700+ distance) for extreme challenges.
Services: Shop, Quests, Recharge (action bar [2])

[b][color=#FFD700]== WANDERING MERCHANTS (110 Total) ==[/color][/b]

Traveling merchants roam between Trading Posts:
  • [color=#FFFF00]More common near center[/color] (40% in core zone)
  • Move slowly with rest breaks (catchable!)
  • Inventories refresh every 5 minutes
  • Offer: Buy, Sell, Upgrade, Gamble
  • [color=#FFD700]$[/color] symbol on map shows merchants

[b][color=#FFD700]== BUFFS & DEBUFFS ==[/color][/b]

Active effects shown in bottom-right overlay:
  • [color=#FF6666][S+15:5][/color] = Strength +15, 5 rounds
  • [color=#6666FF][D+10:3B][/color] = Defense +10, 3 battles
  • [color=#FF00FF][P5:2][/color] = Poison 5 dmg, 2 rounds

[color=#FF00FF]Poison[/color] ticks on [color=#FFFF00]movement and hunting[/color]:
  • Each step or hunt deals poison damage
  • Poison cannot kill you (stops at 1 HP)
  • Elves take 50% reduced poison damage

View details: [Space] Status in movement mode

[b][color=#FFD700]== QUESTS ==[/color][/b]

Accept quests at Trading Posts:
  • Kill quests - Slay X monsters
  • Hotzone quests - Hunt in danger zones for bonus rewards
  • Exploration - Visit specific locations
  • Boss hunts - Defeat high-level monsters

Press [R] Quests in movement mode to view quest log.

[b][color=#FFD700]== GAMBLING ==[/color][/b]

Dice game at merchants (use with caution!):
  • Roll 3d6 vs merchant's 3d6
  • House has a slight edge
  • Triples pay big! Triple 6s = JACKPOT
  • Long-term: expect to lose money
  • Short-term: can get lucky!

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

func update_map(map_text: String):
	if map_display:
		map_display.clear()
		map_display.append_text(map_text)

# ===== TRADING POST FUNCTIONS =====

func handle_trading_post_start(message: Dictionary):
	"""Handle entering a Trading Post"""
	at_trading_post = true
	trading_post_data = message
	quest_view_mode = false
	pending_trading_post_action = ""

	var tp_name = message.get("name", "Trading Post")
	var quest_giver = message.get("quest_giver", "Quest Giver")
	var avail_quests = message.get("available_quests", 0)
	var ready_quests = message.get("quests_to_turn_in", 0)

	game_output.clear()
	display_game("[color=#FFD700]===== %s =====[/color]" % tp_name)
	display_game("[color=#87CEEB]%s greets you.[/color]" % quest_giver)
	display_game("")
	display_game("Services: [Q] Shop | [W] Quests")
	if avail_quests > 0:
		display_game("[color=#00FF00]%d quest(s) available[/color]" % avail_quests)
	if ready_quests > 0:
		display_game("[color=#FFD700]%d quest(s) ready to turn in![/color]" % ready_quests)
	display_game("")
	display_game("[Space] Leave")

	update_action_bar()

func handle_trading_post_end(message: Dictionary):
	"""Handle leaving a Trading Post"""
	at_trading_post = false
	trading_post_data = {}
	quest_view_mode = false
	pending_trading_post_action = ""
	available_quests = []
	quests_to_turn_in = []

	var msg = message.get("message", "")
	if msg != "":
		display_game(msg)

	update_action_bar()

func leave_trading_post():
	"""Leave a Trading Post"""
	send_to_server({"type": "trading_post_leave"})

func cancel_trading_post_action():
	"""Cancel pending Trading Post action and return to main menu"""
	quest_view_mode = false
	pending_trading_post_action = ""
	available_quests = []
	quests_to_turn_in = []
	update_action_bar()

	# Re-display Trading Post menu
	var tp_name = trading_post_data.get("name", "Trading Post")
	game_output.clear()
	display_game("[color=#FFD700]===== %s =====[/color]" % tp_name)
	display_game("")
	display_game("Services: [Q] Shop | [W] Quests")
	display_game("")
	display_game("[Space] Leave")

# ===== QUEST FUNCTIONS =====

func handle_quest_list(message: Dictionary):
	"""Handle quest list from quest giver"""
	var quest_giver = message.get("quest_giver", "Quest Giver")
	var tp_name = message.get("trading_post", "Trading Post")
	available_quests = message.get("available_quests", [])
	quests_to_turn_in = message.get("quests_to_turn_in", [])
	var active_count = message.get("active_count", 0)
	var max_quests = message.get("max_quests", 5)

	quest_view_mode = true
	update_action_bar()

	game_output.clear()
	display_game("[color=#FFD700]===== %s - %s =====[/color]" % [quest_giver, tp_name])
	display_game("[color=#808080]Active Quests: %d / %d[/color]" % [active_count, max_quests])
	display_game("")

	# Show quests ready to turn in first
	if quests_to_turn_in.size() > 0:
		display_game("[color=#FFD700]=== Ready to Turn In ===[/color]")
		for i in range(quests_to_turn_in.size()):
			var quest = quests_to_turn_in[i]
			var rewards = quest.get("rewards", {})
			var reward_str = _format_rewards(rewards)
			display_game("[%d] [color=#00FF00]%s[/color] - %s" % [i + 1, quest.get("name", "Quest"), reward_str])
		display_game("")
		display_game("Type number to turn in quest")
		display_game("")

	# Show available quests
	if available_quests.size() > 0:
		display_game("[color=#00FF00]=== Available Quests ===[/color]")
		var offset = quests_to_turn_in.size()
		for i in range(available_quests.size()):
			var quest = available_quests[i]
			var daily_tag = " [color=#00FFFF][DAILY][/color]" if quest.get("is_daily", false) else ""
			var rewards = quest.get("rewards", {})
			var reward_str = _format_rewards(rewards)
			display_game("[%d] [color=#FFD700]%s[/color]%s" % [offset + i + 1, quest.get("name", "Quest"), daily_tag])
			display_game("    %s" % quest.get("description", ""))
			display_game("    [color=#00FF00]Rewards: %s[/color]" % reward_str)
			display_game("")
		display_game("Type number to accept quest")
	elif quests_to_turn_in.size() == 0:
		display_game("[color=#808080]No quests available at this time.[/color]")

	display_game("")
	display_game("[Space] Back")

func _format_rewards(rewards: Dictionary) -> String:
	"""Format rewards dictionary for display"""
	var parts = []
	if rewards.get("xp", 0) > 0:
		parts.append("%d XP" % rewards.xp)
	if rewards.get("gold", 0) > 0:
		parts.append("%d Gold" % rewards.gold)
	if rewards.get("gems", 0) > 0:
		parts.append("%d Gems" % rewards.gems)
	return ", ".join(parts) if parts.size() > 0 else "None"

func handle_quest_turned_in(message: Dictionary):
	"""Handle quest turn-in result"""
	var quest_id = message.get("quest_id", "")
	var quest_name = message.get("quest_name", "Quest")
	var rewards = message.get("rewards", {})
	var leveled_up = message.get("leveled_up", false)
	var new_level = message.get("new_level", 0)
	var multiplier = rewards.get("multiplier", 1.0)

	# Clear sound tracking for this quest
	if quest_id != "" and quests_sound_played.has(quest_id):
		quests_sound_played.erase(quest_id)

	game_output.clear()
	display_game("[color=#FFD700]===== Quest Complete! =====[/color]")
	display_game("[color=#00FF00]%s[/color]" % message.get("message", "Quest turned in!"))
	display_game("")

	if multiplier > 1.0:
		display_game("[color=#FF6600]Hotzone Bonus: x%.1f[/color]" % multiplier)

	display_game("[color=#FF00FF]+%d XP[/color]" % rewards.get("xp", 0))
	display_game("[color=#FFD700]+%d Gold[/color]" % rewards.get("gold", 0))
	if rewards.get("gems", 0) > 0:
		display_game("[color=#00FFFF]+%d Gems[/color]" % rewards.gems)

	if leveled_up:
		display_game("")
		display_game("[color=#FFD700][b]LEVEL UP! You are now level %d![/b][/color]" % new_level)
		if levelup_player and levelup_player.stream:
			levelup_player.play()

	# Update UI
	update_currency_display()
	update_player_xp_bar()
	update_player_level()

	# Go back to Trading Post menu if still there
	if at_trading_post:
		display_game("")
		display_game("[Space] Continue")
		quest_view_mode = false
		update_action_bar()

func handle_quest_log(message: Dictionary):
	"""Handle quest log display"""
	var log_text = message.get("log", "No quests.")
	var active_count = message.get("active_count", 0)
	var max_quests = message.get("max_quests", 5)

	game_output.clear()
	display_game(log_text)
	display_game("")
	display_game("[color=#808080]Press [Space] to continue[/color]")

	pending_continue = true
	update_action_bar()

func cancel_quest_action():
	"""Cancel quest selection"""
	quest_view_mode = false
	update_action_bar()

func select_quest_option(index: int):
	"""Handle quest selection by number key"""
	# First, check if selecting a quest to turn in
	var turn_in_count = quests_to_turn_in.size()
	var available_count = available_quests.size()

	if index < turn_in_count:
		# Turn in quest
		var quest = quests_to_turn_in[index]
		var quest_id = quest.get("quest_id", "")
		if quest_id != "":
			send_to_server({"type": "quest_turn_in", "quest_id": quest_id})
	elif index < turn_in_count + available_count:
		# Accept quest
		var quest_index = index - turn_in_count
		var quest = available_quests[quest_index]
		var quest_id = quest.get("id", "")
		if quest_id != "":
			send_to_server({"type": "quest_accept", "quest_id": quest_id})
	else:
		display_game("[color=#FF0000]Invalid selection[/color]")

# ===== WATCH/INSPECT MODE =====

func request_watch_player(player_name: String):
	"""Request to watch another player's game output"""
	var my_name = character_data.get("name", "")
	if player_name.to_lower() == my_name.to_lower():
		display_game("[color=#FF4444]You can't watch yourself![/color]")
		return

	if watching_player != "":
		display_game("[color=#FF4444]Already watching %s. Use 'unwatch' to stop first.[/color]" % watching_player)
		return

	send_to_server({"type": "watch_request", "target": player_name})
	display_game("[color=#00FFFF]Requesting to watch %s...[/color]" % player_name)

func stop_watching():
	"""Stop watching the current player"""
	if watching_player == "":
		display_game("[color=#808080]You're not watching anyone.[/color]")
		return

	send_to_server({"type": "watch_stop"})
	display_game("[color=#00FFFF]Stopped watching %s.[/color]" % watching_player)
	watching_player = ""
	game_output.clear()
	display_game("[color=#00FF00]Returned to your own game.[/color]")
	update_action_bar()
	# Restore own character UI
	restore_own_character_ui()

func handle_watch_request(message: Dictionary):
	"""Handle incoming watch request from another player"""
	var requester = message.get("requester", "")
	if requester == "":
		return

	watch_request_pending = requester
	display_game("")
	display_game("[color=#FFD700]===== Watch Request =====[/color]")
	display_game("[color=#00FFFF]%s wants to watch your game.[/color]" % requester)
	display_game("[color=#808080]They will see your GameOutput in real-time.[/color]")
	display_game("")
	display_game("[color=#00FF00][Q] Allow[/color]  [color=#FF4444][W] Deny[/color]")
	update_action_bar()

func approve_watch_request():
	"""Allow the pending watch request"""
	if watch_request_pending == "":
		return

	send_to_server({"type": "watch_approve", "requester": watch_request_pending})
	display_game("[color=#00FF00]%s is now watching your game.[/color]" % watch_request_pending)
	watchers.append(watch_request_pending)
	watch_request_pending = ""
	update_action_bar()

func deny_watch_request():
	"""Deny the pending watch request"""
	if watch_request_pending == "":
		return

	send_to_server({"type": "watch_deny", "requester": watch_request_pending})
	display_game("[color=#FF4444]Denied watch request from %s.[/color]" % watch_request_pending)
	watch_request_pending = ""
	update_action_bar()

func handle_watch_approved(message: Dictionary):
	"""Handle approval of our watch request"""
	var target = message.get("target", "")
	if target == "":
		return

	watching_player = target
	game_output.clear()
	display_game("[color=#FFD700]===== Watching %s =====[/color]" % target)
	display_game("[color=#808080]You are now observing their game. Press [Escape] or type 'unwatch' to stop.[/color]")
	display_game("")
	update_action_bar()

func handle_watch_denied(message: Dictionary):
	"""Handle denial of our watch request"""
	var target = message.get("target", "")
	display_game("[color=#FF4444]%s declined your watch request.[/color]" % target)

func handle_watch_output(message: Dictionary):
	"""Handle forwarded game output from watched player"""
	if watching_player == "":
		return

	var output = message.get("output", "")
	if output != "":
		display_game(output)

func handle_watcher_left(message: Dictionary):
	"""Handle notification that a watcher stopped watching us"""
	var watcher = message.get("watcher", "")
	if watcher in watchers:
		watchers.erase(watcher)
		display_game("[color=#808080]%s stopped watching your game.[/color]" % watcher)

func handle_watched_player_left(message: Dictionary):
	"""Handle notification that the player we're watching disconnected"""
	var player = message.get("player", watching_player)
	if watching_player != "":
		display_game("[color=#FF4444]%s has disconnected.[/color]" % player)
		watching_player = ""
		game_output.clear()
		display_game("[color=#00FF00]Returned to your own game.[/color]")
		update_action_bar()
		restore_own_character_ui()

func restore_own_character_ui():
	"""Restore UI to show own character data after stopping watch"""
	if not has_character or character_data.is_empty():
		return

	# Restore all bars using existing functions that read from character_data
	update_player_hp_bar()
	update_resource_bar()
	update_player_xp_bar()

	# Restore level label
	var level = character_data.get("level", 1)
	if player_level_label:
		player_level_label.text = "Level %d" % level

	# Restore currency
	update_currency_display()

	# Request location update to restore own map
	send_to_server({"type": "move", "direction": 0})

func handle_watch_location(message: Dictionary):
	"""Handle location/map update from watched player"""
	if watching_player == "":
		return

	var description = message.get("description", "")
	if map_display and description != "":
		map_display.text = description

func handle_watch_character(message: Dictionary):
	"""Handle character data update from watched player - update health/resource/XP bars"""
	if watching_player == "":
		return

	var char_data = message.get("character", {})
	if char_data.is_empty():
		return

	# Update health bar directly with watched player's data
	var current_hp = char_data.get("current_hp", 0)
	var max_hp = char_data.get("max_hp", 1)
	if player_health_bar:
		var percent = (float(current_hp) / float(max(max_hp, 1))) * 100.0
		var fill = player_health_bar.get_node_or_null("Fill")
		var label = player_health_bar.get_node_or_null("HPLabel")
		if fill:
			fill.anchor_right = percent / 100.0
			var style = fill.get_theme_stylebox("panel").duplicate()
			style.bg_color = get_hp_color(percent)
			fill.add_theme_stylebox_override("panel", style)
		if label:
			label.text = "HP: %d/%d" % [current_hp, max_hp]

	# Update resource bar with watched player's class and resources
	var char_class = char_data.get("class", "Fighter")
	var current_val = 0
	var max_val = 1
	var resource_name = ""
	var bar_color = Color(0.5, 0.5, 0.5)

	# Determine resource type based on class
	if char_class in ["Fighter", "Barbarian", "Paladin"]:
		current_val = char_data.get("current_stamina", 0)
		max_val = max(char_data.get("max_stamina", 1), 1)
		resource_name = "Stamina"
		bar_color = Color(0.9, 0.75, 0.1)  # Yellow
	elif char_class in ["Wizard", "Sorcerer", "Sage"]:
		current_val = char_data.get("current_mana", 0)
		max_val = max(char_data.get("max_mana", 1), 1)
		resource_name = "Mana"
		bar_color = Color(0.2, 0.7, 0.8)  # Teal
	else:  # Trickster classes: Thief, Ranger, Ninja
		current_val = char_data.get("current_energy", 0)
		max_val = max(char_data.get("max_energy", 1), 1)
		resource_name = "Energy"
		bar_color = Color(0.1, 0.5, 0.15)  # Dark Green

	if resource_bar:
		var percent = (float(current_val) / float(max_val)) * 100.0
		var fill = resource_bar.get_node_or_null("Fill")
		var label = resource_bar.get_node_or_null("ResourceLabel")
		if fill:
			fill.anchor_right = percent / 100.0
			var style = fill.get_theme_stylebox("panel").duplicate()
			style.bg_color = bar_color
			fill.add_theme_stylebox_override("panel", style)
		if label:
			label.text = "%s: %d/%d" % [resource_name, current_val, max_val]

	# Update XP bar with watched player's data
	var experience = char_data.get("experience", 0)
	var exp_to_next = char_data.get("experience_to_next_level", 100)
	if player_xp_bar:
		var total_percent = (float(experience) / float(max(exp_to_next, 1))) * 100.0
		var fill = player_xp_bar.get_node_or_null("Fill")
		if fill:
			fill.anchor_right = total_percent / 100.0
		var label = player_xp_bar.get_node_or_null("XPLabel")
		if label:
			label.text = "XP: %d/%d" % [experience, exp_to_next]

	# Update level label
	var level = char_data.get("level", 1)
	if player_level_label:
		player_level_label.text = "[Watching] Lv %d" % level

	# Update currency display
	var gold = char_data.get("gold", 0)
	var gems = char_data.get("gems", 0)
	if gold_label:
		gold_label.text = str(gold)
	if gem_label:
		gem_label.text = str(gems)
