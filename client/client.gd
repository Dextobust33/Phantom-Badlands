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
@onready var resource_bar = $RootContainer/MainContainer/RightPanel/ResourceBar
@onready var player_xp_bar = $RootContainer/MainContainer/RightPanel/PlayerXPBar
@onready var player_level_label = $RootContainer/MainContainer/RightPanel/LevelRow/PlayerLevel
@onready var gold_label = $RootContainer/MainContainer/RightPanel/CurrencyDisplay/GoldContainer/GoldLabel
@onready var gem_label = $RootContainer/MainContainer/RightPanel/CurrencyDisplay/GemContainer/GemLabel
@onready var music_toggle = $RootContainer/MainContainer/RightPanel/LevelRow/MusicToggle
@onready var online_players_list = $RootContainer/MainContainer/RightPanel/OnlinePlayersList
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
const GAME_OUTPUT_MAX_FONT_SIZE = 32

# Combat state
var in_combat = false
var flock_pending = false
var flock_monster_name = ""
var combat_item_mode = false  # Selecting item to use in combat

# Action bar
var action_buttons: Array[Button] = []
var action_cost_labels: Array[Label] = []  # Labels showing resource cost below hotkey
# Spacebar is first action, then Q, W, E, R, 1, 2, 3, 4 (removed 5)
var action_hotkeys = [KEY_SPACE, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_1, KEY_2, KEY_3, KEY_4]
var current_actions: Array[Dictionary] = []

# Inventory mode
var inventory_mode: bool = false
var selected_item_index: int = -1  # Currently selected inventory item (0-based, -1 = none)
var pending_inventory_action: String = ""  # Action waiting for item selection

# Pending continue state (prevents output clearing until player acknowledges)
var pending_continue: bool = false

# XP tracking for two-color bar
var xp_before_combat: int = 0  # XP before starting combat
var recent_xp_gain: int = 0    # XP gained in most recent combat

# Merchant mode
var at_merchant: bool = false
var merchant_data: Dictionary = {}
var pending_merchant_action: String = ""

# Password change mode
var changing_password: bool = false
var password_change_step: int = 0  # 0=old, 1=new, 2=confirm
var temp_old_password: String = ""
var temp_new_password: String = ""

# Enemy tracking
var known_enemy_hp: Dictionary = {}
var current_enemy_name: String = ""
var current_enemy_level: int = 0
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

# ===== RACE DESCRIPTIONS =====
const RACE_DESCRIPTIONS = {
	"Human": "Adaptable and ambitious. Gains +10% bonus experience from all sources.",
	"Elf": "Ancient and resilient. 50% reduced poison damage, immune to poison debuffs.",
	"Dwarf": "Sturdy and determined. 25% chance to survive lethal damage with 1 HP (once per combat)."
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

	# Connect online players list for clickable names
	if online_players_list:
		online_players_list.meta_clicked.connect(_on_player_name_clicked)

	# Setup race options
	if race_option:
		race_option.clear()
		for r in ["Human", "Elf", "Dwarf"]:
			race_option.add_item(r)
		race_option.item_selected.connect(_on_race_selected)
		_update_race_description()  # Set initial description

	# Setup class options (6 classes: 2 Warrior, 2 Mage, 2 Trickster)
	if class_option:
		class_option.clear()
		for cls in ["Fighter", "Barbarian", "Wizard", "Sage", "Thief", "Ranger"]:
			class_option.add_item(cls)

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

	# Initial display
	display_game("[b][color=#4A90E2]Welcome to Phantasia Revival[/color][/b]")
	display_game("Connecting to server...")

	# Initialize UI state
	update_action_bar()
	show_login_panel()

	# Auto-connect
	connect_to_server()

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
					select_inventory_item(i)  # 0-based index
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

	# Action bar hotkeys (only when input NOT focused and playing)
	# Allow hotkeys during merchant modes and inventory modes (for Cancel buttons)
	var merchant_blocks_hotkeys = pending_merchant_action != "" and pending_merchant_action not in ["sell_gems", "upgrade", "buy", "sell", "gamble"]
	if game_state == GameState.PLAYING and not input_field.has_focus() and not merchant_blocks_hotkeys:
		for i in range(action_hotkeys.size()):
			if Input.is_physical_key_pressed(action_hotkeys[i]) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("hotkey_%d_pressed" % i, false):
					set_meta("hotkey_%d_pressed" % i, true)
					trigger_action(i)
			else:
				set_meta("hotkey_%d_pressed" % i, false)

	# Numpad movement and hunt (only when playing and not in combat, flock, pending continue, inventory, or merchant)
	if connected and has_character and not input_field.has_focus() and not in_combat and not flock_pending and not pending_continue and not inventory_mode and not at_merchant:
		if game_state == GameState.PLAYING:
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_move_time >= MOVE_COOLDOWN:
				var move_dir = 0
				var is_hunt = false
				if Input.is_physical_key_pressed(KEY_KP_1):
					move_dir = 1
				elif Input.is_physical_key_pressed(KEY_KP_2):
					move_dir = 2
				elif Input.is_physical_key_pressed(KEY_KP_3):
					move_dir = 3
				elif Input.is_physical_key_pressed(KEY_KP_4):
					move_dir = 4
				elif Input.is_physical_key_pressed(KEY_KP_5):
					is_hunt = true
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
			display_game("[color=#2ECC71]Connected to server![/color]")

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

func update_online_players(players: Array):
	"""Update the online players list display with clickable names"""
	if not online_players_list:
		return

	online_players_list.clear()

	if players.is_empty():
		online_players_list.append_text("[color=#666666]No players online[/color]")
		return

	for player in players:
		var pname = player.get("name", "Unknown")
		var plevel = player.get("level", 1)
		var pclass = player.get("class", "Unknown")
		# Use URL tags to make names clickable (double-click shows stats)
		online_players_list.append_text("[url=%s][color=#90EE90]%s[/color][/url] Lv%d %s\n" % [pname, pname, plevel, pclass])

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

	var status = "[color=#90EE90]Exploring[/color]" if not in_combat_flag else "[color=#FF6B6B]In Combat[/color]"

	display_game("[color=#FFD700]===== %s =====[/color]" % pname)
	display_game("Level %d %s %s - %s" % [level, char_race, cls, status])
	display_game("[color=#9B59B6]XP:[/color] %d / %d ([color=#FFD700]%d to next level[/color])" % [current_xp, xp_needed, xp_remaining])
	display_game("HP: %d/%d" % [hp, max_hp])

	# Stats with bonuses
	var stats_line = "STR:%d" % str_stat
	if bonuses.get("strength", 0) > 0:
		stats_line += "[color=#90EE90](+%d)[/color]" % bonuses.strength
	stats_line += " CON:%d" % con_stat
	if bonuses.get("constitution", 0) > 0:
		stats_line += "[color=#90EE90](+%d)[/color]" % bonuses.constitution
	stats_line += " DEX:%d" % dex_stat
	if bonuses.get("dexterity", 0) > 0:
		stats_line += "[color=#90EE90](+%d)[/color]" % bonuses.dexterity
	display_game(stats_line)

	stats_line = "INT:%d" % int_stat
	if bonuses.get("intelligence", 0) > 0:
		stats_line += "[color=#90EE90](+%d)[/color]" % bonuses.intelligence
	stats_line += " WIS:%d" % wis_stat
	if bonuses.get("wisdom", 0) > 0:
		stats_line += "[color=#90EE90](+%d)[/color]" % bonuses.wisdom
	stats_line += " WIT:%d" % wit_stat
	if bonuses.get("wits", 0) > 0:
		stats_line += "[color=#90EE90](+%d)[/color]" % bonuses.wits
	display_game(stats_line)

	# Combat stats
	display_game("[color=#FF6666]Attack:[/color] %d  [color=#66FFFF]Defense:[/color] %d" % [total_attack, total_defense])

	# Equipment
	var equip_text = ""
	for slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			equip_text += "[color=%s]%s[/color] " % [rarity_color, item.get("name", "Unknown")]
	if equip_text != "":
		display_game("[color=#E67E22]Gear:[/color] %s" % equip_text.strip_edges())

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
	var confirm_passwd = confirm_password_field.text

	if user.is_empty() or passwd.is_empty():
		if login_status:
			login_status.text = "[color=#E74C3C]Enter username and password[/color]"
		return

	if confirm_passwd.is_empty():
		if login_status:
			login_status.text = "[color=#E74C3C]Please confirm your password[/color]"
		return

	if passwd != confirm_passwd:
		if login_status:
			login_status.text = "[color=#E74C3C]Passwords do not match[/color]"
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

func _on_confirm_create_pressed():
	var char_name = new_char_name_field.text.strip_edges()
	var char_race = race_option.get_item_text(race_option.selected) if race_option else "Human"
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

	var status_text = "[color=#90EE90]Exploring[/color]" if not in_combat_status else "[color=#FF6B6B]In Combat[/color]"

	var xp_needed = data.get("experience_to_next_level", 100)
	var xp_remaining = xp_needed - exp

	var char_race = data.get("race", "Human")
	player_info_content.clear()
	player_info_content.append_text("[center][color=#FFD700][b]%s[/b][/color][/center]\n" % pname)
	player_info_content.append_text("[center]Level %d %s %s[/center]\n" % [level, char_race, cls])
	player_info_content.append_text("[center][color=#9B59B6]XP:[/color] %d / %d[/center]\n" % [exp, xp_needed])
	player_info_content.append_text("[center][color=#FFD700]%d XP to next level[/color][/center]\n" % xp_remaining)
	player_info_content.append_text("[center]%s[/center]\n\n" % status_text)
	player_info_content.append_text("[color=#4A90E2]HP:[/color] %d / %d\n\n" % [hp, max_hp])

	# Stats with equipment bonuses
	player_info_content.append_text("[color=#9B59B6]Stats:[/color]\n")
	var line1 = "  STR: %d" % str_stat
	if bonuses.get("strength", 0) > 0:
		line1 += "[color=#90EE90](+%d)[/color]" % bonuses.strength
	line1 += "  CON: %d" % con_stat
	if bonuses.get("constitution", 0) > 0:
		line1 += "[color=#90EE90](+%d)[/color]" % bonuses.constitution
	line1 += "  DEX: %d" % dex_stat
	if bonuses.get("dexterity", 0) > 0:
		line1 += "[color=#90EE90](+%d)[/color]" % bonuses.dexterity
	player_info_content.append_text(line1 + "\n")

	var line2 = "  INT: %d" % int_stat
	if bonuses.get("intelligence", 0) > 0:
		line2 += "[color=#90EE90](+%d)[/color]" % bonuses.intelligence
	line2 += "  WIS: %d" % wis_stat
	if bonuses.get("wisdom", 0) > 0:
		line2 += "[color=#90EE90](+%d)[/color]" % bonuses.wisdom
	line2 += "  WIT: %d" % wit_stat
	if bonuses.get("wits", 0) > 0:
		line2 += "[color=#90EE90](+%d)[/color]" % bonuses.wits
	player_info_content.append_text(line2 + "\n\n")

	# Combat stats
	player_info_content.append_text("[color=#FF6666]Attack:[/color] %d  [color=#66FFFF]Defense:[/color] %d\n\n" % [total_attack, total_defense])

	# Equipment
	var has_equipment = false
	for slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			if not has_equipment:
				player_info_content.append_text("[color=#E67E22]Equipment:[/color]\n")
				has_equipment = true
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			player_info_content.append_text("  %s: [color=%s]%s[/color] (Lv%d)\n" % [
				slot.capitalize(), rarity_color, item.get("name", "Unknown"), item.get("level", 1)
			])

	if has_equipment:
		player_info_content.append_text("\n")

	player_info_content.append_text("[color=#E67E22]Monsters Slain:[/color] %d" % kills)

	player_info_panel.visible = true

# ===== ACTION BAR FUNCTIONS =====

func setup_action_bar():
	action_buttons.clear()
	action_cost_labels.clear()
	for i in range(9):
		var action_container = action_bar.get_node("Action%d" % (i + 1))
		if action_container:
			var button = action_container.get_node("Button")
			if button:
				action_buttons.append(button)
				button.pressed.connect(_on_action_button_pressed.bind(i))

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

func update_action_bar():
	current_actions.clear()

	if combat_item_mode:
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
		]
	elif in_combat:
		# Combat mode: Space=Attack, Q=Defend, W=Flee, E/R/1-4=Path abilities
		var ability_actions = _get_combat_ability_actions()
		current_actions = [
			{"label": "Attack", "action_type": "combat", "action_data": "attack", "enabled": true},
			{"label": "Defend", "action_type": "combat", "action_data": "defend", "enabled": true},
			{"label": "Flee", "action_type": "combat", "action_data": "flee", "enabled": true},
		]
		# Add 6 ability slots (E, R, 1, 2, 3, 4)
		for ability in ability_actions:
			current_actions.append(ability)
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
			]
		elif pending_merchant_action == "upgrade":
			# Show equipment slots as action bar options
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "Weapon", "action_type": "local", "action_data": "upgrade_weapon", "enabled": equipped.get("weapon") != null},
				{"label": "Armor", "action_type": "local", "action_data": "upgrade_armor", "enabled": equipped.get("armor") != null},
				{"label": "Helm", "action_type": "local", "action_data": "upgrade_helm", "enabled": equipped.get("helm") != null},
				{"label": "Shield", "action_type": "local", "action_data": "upgrade_shield", "enabled": equipped.get("shield") != null},
				{"label": "Ring", "action_type": "local", "action_data": "upgrade_ring", "enabled": equipped.get("ring") != null},
				{"label": "Amulet", "action_type": "local", "action_data": "upgrade_amulet", "enabled": equipped.get("amulet") != null},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_merchant_action == "gamble":
			# Waiting for bet amount input
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
			]
		else:
			current_actions = [
				{"label": "Leave", "action_type": "local", "action_data": "merchant_leave", "enabled": true},
				{"label": "Sell", "action_type": "local", "action_data": "merchant_sell", "enabled": "sell" in services},
				{"label": "Upgrade", "action_type": "local", "action_data": "merchant_upgrade", "enabled": "upgrade" in services},
				{"label": "Gamble", "action_type": "local", "action_data": "merchant_gamble", "enabled": "gamble" in services},
				{"label": "Buy", "action_type": "local", "action_data": "merchant_buy", "enabled": shop_items.size() > 0},
				{"label": "SellGems", "action_type": "local", "action_data": "merchant_sell_gems", "enabled": player_gems > 0},
				{"label": "Recharge", "action_type": "local", "action_data": "merchant_recharge", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif inventory_mode:
		if pending_inventory_action != "":
			# Waiting for item selection - show cancel option
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "inventory_cancel", "enabled": true},
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
			# Inventory sub-menu: Spacebar=Back, Q-R for inventory actions
			# Discard moved to end (KEY_4) to prevent accidental use
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "inventory_back", "enabled": true},
				{"label": "Inspect", "action_type": "local", "action_data": "inventory_inspect", "enabled": true},
				{"label": "Use", "action_type": "local", "action_data": "inventory_use", "enabled": true},
				{"label": "Equip", "action_type": "local", "action_data": "inventory_equip", "enabled": true},
				{"label": "Unequip", "action_type": "local", "action_data": "inventory_unequip", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Discard", "action_type": "local", "action_data": "inventory_discard", "enabled": true},
			]
	elif has_character:
		# Normal movement mode: Spacebar=Status
		current_actions = [
			{"label": "Status", "action_type": "local", "action_data": "status", "enabled": true},
			{"label": "Inventory", "action_type": "local", "action_data": "inventory", "enabled": true},
			{"label": "Rest", "action_type": "server", "action_data": "rest", "enabled": true},
			{"label": "Help", "action_type": "local", "action_data": "help", "enabled": true},
			{"label": "Players", "action_type": "server", "action_data": "get_players", "enabled": true},
			{"label": "Leaders", "action_type": "local", "action_data": "leaderboard", "enabled": true},
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
			send_combat_command(action.action_data)
		"local":
			execute_local_action(action.action_data)
		"server":
			send_to_server({"type": action.action_data})
		"flock":
			continue_flock_encounter()

func send_combat_command(command: String):
	if not connected:
		display_game("[color=#E74C3C]Not connected![/color]")
		return
	if not in_combat:
		display_game("[color=#E74C3C]You are not in combat![/color]")
		return

	display_game("[color=#F39C12]> %s[/color]" % command)
	send_to_server({"type": "combat", "command": command})

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
		display_game("[color=#E74C3C]You have no usable items![/color]")
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
	display_game("[color=#95A5A6]Press 1-%d to use an item, or Space to cancel.[/color]" % usable_items.size())

func cancel_combat_item_mode():
	"""Cancel combat item selection mode."""
	combat_item_mode = false
	update_action_bar()
	display_game("[color=#95A5A6]Item use cancelled.[/color]")

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
		display_game("[color=#E74C3C]Invalid item number![/color]")
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
		"upgrade_ring":
			send_upgrade_slot("ring")
		"upgrade_amulet":
			send_upgrade_slot("amulet")
		"combat_item":
			show_combat_item_menu()
		"combat_item_cancel":
			cancel_combat_item_mode()

func acknowledge_continue():
	"""Clear pending continue state and allow game to proceed"""
	pending_continue = false
	# Keep recent XP gain highlight visible until next XP gain
	game_output.clear()
	update_action_bar()

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

# ===== MERCHANT FUNCTIONS =====

func leave_merchant():
	"""Leave the current merchant"""
	send_to_server({"type": "merchant_leave"})
	at_merchant = false
	merchant_data = {}
	pending_merchant_action = ""
	update_action_bar()

func prompt_merchant_action(action_type: String):
	"""Prompt for merchant action selection"""
	var inventory = character_data.get("inventory", [])
	var equipped = character_data.get("equipped", {})

	match action_type:
		"sell":
			if inventory.is_empty():
				display_game("[color=#E74C3C]You have nothing to sell.[/color]")
				return
			pending_merchant_action = "sell"
			display_merchant_sell_list()
			display_game("[color=#FFD700]Press 1-%d to sell an item:[/color]" % inventory.size())
			update_action_bar()

		"upgrade":
			var slots_with_items = []
			for slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
				if equipped.get(slot) != null:
					slots_with_items.append(slot)
			if slots_with_items.is_empty():
				display_game("[color=#E74C3C]You have nothing equipped to upgrade.[/color]")
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
				display_game("[color=#FF6B6B]You need at least %d gold to gamble at your level![/color]" % (min_bet * 2))
				return

			pending_merchant_action = "gamble"
			display_game("[color=#FFD700]===== GAMBLING - DICE GAME =====[/color]")
			display_game("Your gold: %d" % gold)
			display_game("Bet range: %d - %d gold" % [min_bet, max_bet])
			display_game("")
			display_game("[color=#95A5A6]Rules: Both roll 3 dice. Higher total wins![/color]")
			display_game("  Lose by 6+: Lose full bet")
			display_game("  Lose by 1-5: Lose half bet")
			display_game("  Tie: Bet returned")
			display_game("  Win by 1-5: Win 1.5x")
			display_game("  Win by 6-10: Win 2.5x")
			display_game("  Win by 11+: Win 3x")
			display_game("  Triple 6s: JACKPOT (item or 5x)!")
			display_game("")
			display_game("[color=#FFD700]Enter bet amount (%d-%d):[/color]" % [min_bet, max_bet])
			input_field.placeholder_text = "Bet amount..."
			input_field.grab_focus()
			update_action_bar()

		"buy":
			var shop_items = merchant_data.get("shop_items", [])
			if shop_items.is_empty():
				display_game("[color=#E74C3C]The merchant has nothing for sale.[/color]")
				return
			pending_merchant_action = "buy"
			display_shop_inventory()
			update_action_bar()

		"sell_gems":
			var gems = character_data.get("gems", 0)
			if gems <= 0:
				display_game("[color=#E74C3C]You have no gems to sell.[/color]")
				return
			pending_merchant_action = "sell_gems"
			display_game("[color=#FFD700]===== SELL GEMS =====[/color]")
			display_game("[color=#00FFFF]Your gems: %d[/color]" % gems)
			display_game("Value: [color=#FFD700]1000 gold per gem[/color]")
			display_game("")
			display_game("[color=#95A5A6]Total value: %d gold[/color]" % (gems * 1000))
			display_game("")
			display_game("[color=#FFD700]Enter amount to sell (or press [Q] to sell all):[/color]")
			input_field.placeholder_text = "Gems to sell..."
			input_field.grab_focus()
			update_action_bar()

func sell_all_gems():
	"""Sell all gems to merchant"""
	var gems = character_data.get("gems", 0)
	if gems <= 0:
		display_game("[color=#E74C3C]You have no gems to sell.[/color]")
		return
	pending_merchant_action = ""
	send_to_server({"type": "merchant_sell_gems", "amount": gems})
	update_action_bar()

func sell_all_items():
	"""Sell all inventory items to merchant"""
	var inventory = character_data.get("inventory", [])
	if inventory.is_empty():
		display_game("[color=#E74C3C]You have no items to sell.[/color]")
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
		display_game("[color=#666666](nothing for sale)[/color]")
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
						compare_text = " [color=#90EE90]↑[/color]"
					elif level < equipped_level:
						compare_text = " [color=#FF6666]↓[/color]"
					else:
						compare_text = " [color=#FFFF66]=[/color]"
				else:
					compare_text = " [color=#90EE90]NEW[/color]"

			display_game("[%d] [color=%s]%s[/color] (Lv%d)%s - %d gold (or %d gems)" % [i + 1, color, item.get("name", "Unknown"), level, compare_text, price, gem_price])

	display_game("")
	display_game("[color=#95A5A6]Press 1-%d to buy with gold[/color]" % shop_items.size())

func handle_shop_inventory(message: Dictionary):
	"""Handle shop inventory update from server"""
	var items = message.get("items", [])
	# Update local merchant data with shop items
	if not merchant_data.is_empty():
		var shop_items = []
		for item in items:
			shop_items.append({
				"name": item.get("name", "Unknown"),
				"type": item.get("type", ""),
				"level": item.get("level", 1),
				"rarity": item.get("rarity", "common"),
				"shop_price": item.get("price", 100)
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

	if max_bet >= min_bet:
		display_game("[color=#95A5A6]Enter another bet (%d-%d) or press Space to stop:[/color]" % [min_bet, max_bet])
		pending_merchant_action = "gamble"
		input_field.placeholder_text = "Bet amount..."
		input_field.grab_focus()
	else:
		display_game("[color=#FF6B6B]You don't have enough gold to continue gambling.[/color]")
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
	input_field.placeholder_text = ""  # Reset placeholder
	display_game("[color=#95A5A6]Action cancelled.[/color]")
	show_merchant_menu()
	update_action_bar()

func select_merchant_sell_item(index: int):
	"""Sell item at index to merchant"""
	var inventory = character_data.get("inventory", [])

	if index < 0 or index >= inventory.size():
		display_game("[color=#E74C3C]Invalid item number.[/color]")
		return

	pending_merchant_action = ""
	send_to_server({"type": "merchant_sell", "index": index})
	update_action_bar()

func select_merchant_buy_item(index: int):
	"""Buy item at index from merchant shop"""
	var shop_items = merchant_data.get("shop_items", [])

	if index < 0 or index >= shop_items.size():
		display_game("[color=#E74C3C]Invalid item number.[/color]")
		return

	pending_merchant_action = ""
	send_to_server({"type": "merchant_buy", "index": index})
	update_action_bar()

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
		display_game("[color=#666666](no items to sell)[/color]")
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

	for slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
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
			display_game("%s: [color=#666666](empty)[/color]" % slot.capitalize())

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
				display_game("[color=#E74C3C]Invalid bet amount.[/color]")
				show_merchant_menu()

		"sell_gems":
			if input_text.is_valid_int():
				var amount = int(input_text)
				if amount > 0:
					send_to_server({"type": "merchant_sell_gems", "amount": amount})
				else:
					display_game("[color=#E74C3C]Invalid gem amount.[/color]")
					show_merchant_menu()
			else:
				display_game("[color=#E74C3C]Invalid gem amount. Enter a number.[/color]")
				show_merchant_menu()

		"buy":
			if input_text.is_valid_int():
				var index = int(input_text) - 1  # Convert to 0-based
				var shop_items = merchant_data.get("shop_items", [])
				if index >= 0 and index < shop_items.size():
					send_to_server({"type": "merchant_buy", "index": index})
				else:
					display_game("[color=#E74C3C]Invalid item number.[/color]")
					display_shop_inventory()
					pending_merchant_action = "buy"  # Keep in buy mode
			else:
				display_game("[color=#E74C3C]Invalid item number. Enter 1-%d.[/color]" % merchant_data.get("shop_items", []).size())
				display_shop_inventory()
				pending_merchant_action = "buy"  # Keep in buy mode

		_:
			# Other actions use action bar, not text input
			display_game("[color=#E74C3C]Use the action bar to select.[/color]")
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
			char_select_status.text = "[color=#95A5A6]Password change cancelled.[/color]"

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
				char_select_status.text = "[color=#2ECC71]%s[/color]" % message
			else:
				char_select_status.text = "[color=#E74C3C]%s[/color]" % message

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
					char_select_status.text = "[color=#E74C3C]Password must be at least 4 characters. Try again:[/color]"
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
					char_select_status.text = "[color=#E74C3C]Passwords do not match. Enter new password again:[/color]"
				password_change_step = 1
				temp_new_password = ""
				input_field.placeholder_text = "New password..."
				input_field.grab_focus()
				return

			if char_select_status:
				char_select_status.text = "[color=#95A5A6]Changing password...[/color]"

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
	update_action_bar()
	display_inventory()

func close_inventory():
	"""Close inventory view and return to normal mode"""
	inventory_mode = false
	update_action_bar()
	display_game("[color=#95A5A6]Inventory closed.[/color]")

func display_inventory():
	"""Display the player's inventory and equipped items"""
	if not has_character:
		return

	var inventory = character_data.get("inventory", [])
	var equipped = character_data.get("equipped", {})

	display_game("[color=#FFD700]===== INVENTORY =====[/color]")

	# Show equipped items with level and stats
	display_game("[color=#4A90E2]Equipped:[/color]")
	for slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var item_level = item.get("level", 1)
			var bonus_text = _get_item_bonus_summary(item)
			display_game("  %s: [color=%s]%s[/color] (Lv%d) %s" % [
				slot.capitalize(), rarity_color, item.get("name", "Unknown"), item_level, bonus_text
			])
		else:
			display_game("  %s: [color=#666666](empty)[/color]" % slot.capitalize())

	# Show total equipment bonuses
	var bonuses = _calculate_equipment_bonuses(equipped)
	if bonuses.attack > 0 or bonuses.defense > 0:
		display_game("")
		display_game("[color=#90EE90]Total Gear Bonuses: +%d Attack, +%d Defense[/color]" % [bonuses.attack, bonuses.defense])

	# Show inventory items with comparison hints
	display_game("")
	display_game("[color=#4A90E2]Backpack (%d/20):[/color]" % inventory.size())
	if inventory.is_empty():
		display_game("  [color=#666666](empty)[/color]")
	else:
		for i in range(inventory.size()):
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
						compare_text = "[color=#90EE90]↑[/color]"
					elif item_level < equipped_level:
						compare_text = "[color=#FF6666]↓[/color]"
					else:
						compare_text = "[color=#FFFF66]=[/color]"
				else:
					compare_text = "[color=#90EE90]NEW[/color]"

			display_game("  %d. [color=%s]%s[/color] (Lv%d) %s" % [
				i + 1, rarity_color, item.get("name", "Unknown"), item_level, compare_text
			])

	display_game("")
	display_game("[color=#95A5A6]Q=Inspect, W=Use, E=Equip, R=Unequip, 1=Discard, Space=Back[/color]")
	display_game("[color=#95A5A6]Inspect equipped: type slot name (e.g., 'weapon')[/color]")

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
				display_game("[color=#E74C3C]No items to inspect.[/color]")
				return
			pending_inventory_action = "inspect_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Press 1-%d to inspect an item, or type slot name (weapon, armor, etc.):[/color]" % max(1, inventory.size()))
			update_action_bar()  # Show cancel option

		"use":
			if inventory.is_empty():
				display_game("[color=#E74C3C]No items to use.[/color]")
				return
			pending_inventory_action = "use_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Press 1-%d to use an item:[/color]" % inventory.size())
			update_action_bar()

		"equip":
			if inventory.is_empty():
				display_game("[color=#E74C3C]No items to equip.[/color]")
				return
			pending_inventory_action = "equip_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Press 1-%d to equip an item:[/color]" % inventory.size())
			update_action_bar()

		"unequip":
			var slots_with_items = []
			for slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
				if equipped.get(slot) != null:
					slots_with_items.append(slot)
			if slots_with_items.is_empty():
				display_game("[color=#E74C3C]No items equipped.[/color]")
				return
			pending_inventory_action = "unequip_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Type slot to unequip (%s):[/color]" % ", ".join(slots_with_items))
			input_field.placeholder_text = "Slot name..."
			input_field.grab_focus()

		"discard":
			if inventory.is_empty():
				display_game("[color=#E74C3C]No items to discard.[/color]")
				return
			pending_inventory_action = "discard_item"
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]Press 1-%d to discard an item:[/color]" % inventory.size())
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

	if index < 0 or index >= inventory.size():
		display_game("[color=#E74C3C]Invalid item number.[/color]")
		display_inventory()  # Re-show inventory on error
		return

	var action = pending_inventory_action
	pending_inventory_action = ""

	# Process the action with the selected item
	match action:
		"inspect_item":
			inspect_item(str(index + 1))  # Convert to 1-based for existing function
			# Don't re-display inventory - let player read the item details
			# Stay in inventory mode for further actions
			update_action_bar()
			return
		"use_item":
			send_to_server({"type": "inventory_use", "index": index})
			# Server will send character_update which triggers inventory refresh
		"equip_item":
			send_to_server({"type": "inventory_equip", "index": index})
			# Server will send character_update which triggers inventory refresh
		"discard_item":
			var item = inventory[index]
			send_to_server({"type": "inventory_discard", "index": index})
			# Server will send character_update which triggers inventory refresh

	# Exit inventory mode after use/equip/discard to return to movement
	inventory_mode = false
	update_action_bar()

func cancel_inventory_action():
	"""Cancel pending inventory action"""
	if pending_inventory_action != "":
		pending_inventory_action = ""
		display_game("[color=#95A5A6]Action cancelled.[/color]")
		display_inventory()  # Re-show inventory
		update_action_bar()

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
			bar_color = Color(0.2, 0.8, 0.3)  # Green
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
			# Clear password fields after successful registration
			if password_field:
				password_field.text = ""
			if confirm_password_field:
				confirm_password_field.text = ""

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
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", ""))
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
			display_game("[color=#2ECC71]%s[/color]" % message.get("message", ""))
			display_character_status()
			request_player_list()

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
			if not in_combat and not pending_continue:
				game_output.clear()
			update_map(desc)

		"chat":
			var sender = message.get("sender", "Unknown")
			var text = message.get("message", "")
			display_chat("[color=#4A90E2]%s:[/color] %s" % [sender, text])
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
			display_game(message.get("message", ""))

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
					display_inventory()

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
			flock_pending = false
			flock_monster_name = ""
			combat_item_mode = false
			update_action_bar()

			# Track XP before combat for two-color XP bar
			# Only record at start of combat chain (not flock continuations)
			if xp_before_combat == 0:
				xp_before_combat = character_data.get("experience", 0)

			# Always clear game output for fresh combat display
			game_output.clear()

			display_game(message.get("message", ""))

			var combat_state = message.get("combat_state", {})
			current_enemy_name = combat_state.get("monster_name", "Enemy")
			current_enemy_level = combat_state.get("monster_level", 1)
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
				update_player_hp_bar()
				update_resource_bar()
				update_action_bar()  # Refresh action bar for ability availability

		"combat_end":
			in_combat = false
			combat_item_mode = false

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
					display_game("[color=#FF6B6B]But wait... you hear more %ss approaching![/color]" % flock_monster_name)
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
					display_game("[color=#95A5A6]Press Space to continue...[/color]")
			elif message.get("fled", false):
				# Fled - reset combat XP tracking but keep previous XP gain highlight
				xp_before_combat = 0
				display_game("[color=#FFD700]You escaped from combat![/color]")
				pending_continue = true
				display_game("[color=#95A5A6]Press Space to continue...[/color]")
			else:
				# Defeat handled by permadeath message
				pass

			update_action_bar()
			show_enemy_hp_bar(false)
			current_enemy_name = ""
			current_enemy_level = 0
			damage_dealt_to_current_enemy = 0

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

		"gamble_result":
			handle_gamble_result(message)

		"password_changed":
			finish_password_change(true, message.get("message", "Password changed successfully!"))

		"password_change_failed":
			finish_password_change(false, message.get("reason", "Password change failed"))

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
	var command_keywords = ["help", "clear", "status", "who", "players", "examine", "ex", "inventory", "inv", "i"]
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
				display_game("[color=#E74C3C]Invalid item number.[/color]")

		"equip_item":
			if input_text.is_valid_int():
				var index = int(input_text) - 1
				send_to_server({"type": "inventory_equip", "index": index})
			else:
				display_game("[color=#E74C3C]Invalid item number.[/color]")

		"unequip_item":
			var slot = input_text.to_lower().strip_edges()
			if slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
				send_to_server({"type": "inventory_unequip", "slot": slot})
			else:
				display_game("[color=#E74C3C]Invalid slot. Use: weapon, armor, helm, shield, ring, amulet[/color]")

		"discard_item":
			if input_text.is_valid_int():
				var index = int(input_text) - 1
				send_to_server({"type": "inventory_discard", "index": index})
			else:
				display_game("[color=#E74C3C]Invalid item number.[/color]")

func inspect_item(input_text: String):
	"""Inspect an item to see its details"""
	var inventory = character_data.get("inventory", [])
	var equipped = character_data.get("equipped", {})
	var item = null
	var source = ""

	# Check if it's a slot name
	var slot = input_text.to_lower().strip_edges()
	if slot in ["weapon", "armor", "helm", "shield", "ring", "amulet"]:
		item = equipped.get(slot)
		source = "equipped in %s slot" % slot
		if item == null:
			display_game("[color=#E74C3C]Nothing equipped in %s slot.[/color]" % slot)
			return
	elif input_text.is_valid_int():
		var index = int(input_text) - 1
		if index < 0 or index >= inventory.size():
			display_game("[color=#E74C3C]Invalid item number.[/color]")
			return
		item = inventory[index]
		source = "in backpack"
	else:
		display_game("[color=#E74C3C]Enter a number (1-%d) or slot name.[/color]" % inventory.size())
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
	display_game("[color=#95A5A6]%s[/color]" % source.capitalize())
	display_game("")
	display_game("[color=#4A90E2]Type:[/color] %s" % _get_item_type_description(item_type))
	display_game("[color=#4A90E2]Rarity:[/color] [color=%s]%s[/color]" % [rarity_color, rarity.capitalize()])
	display_game("[color=#4A90E2]Level:[/color] %d" % level)
	display_game("[color=#4A90E2]Value:[/color] %d gold" % value)
	display_game("")
	display_game("[color=#E6CC80]Effect:[/color] %s" % _get_item_effect_description(item_type, level, rarity))
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

	if "potion" in item_type or "elixir" in item_type:
		var heal = level * 10
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
			display_game("[color=#95A5A6]Refreshing player list...[/color]")
		"examine", "ex":
			if parts.size() > 1:
				var target = parts[1]
				send_to_server({"type": "examine_player", "name": target})
			else:
				display_game("[color=#E74C3C]Usage: examine <playername>[/color]")
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
#changed from 127.0.0.1
	display_game("Connecting to 24.158.80.95:9080...")
#changed from 127.0.0.1
	var error = connection.connect_to_host("24.158.80.95", 9080)
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
	text += "[color=#9B59B6]Experience:[/color] %d / %d ([color=#FFD700]%d to next level[/color])\n" % [current_xp, xp_needed, xp_remaining]
	text += "HP: %d/%d (%s)\n" % [char.get("current_hp", 0), char.get("max_hp", 0), char.get("health_state", "Unknown")]
	text += "[color=#FFD700]Mana:[/color] %d/%d  [color=#FF6B6B]Stamina:[/color] %d/%d  [color=#90EE90]Energy:[/color] %d/%d\n" % [
		char.get("current_mana", 0), char.get("max_mana", 0),
		char.get("current_stamina", 0), char.get("max_stamina", 0),
		char.get("current_energy", 0), char.get("max_energy", 0)
	]
	text += "Gold: %d\n" % char.get("gold", 0)
	text += "Position: (%d, %d)\n" % [char.get("x", 0), char.get("y", 0)]
	text += "Monsters Killed: %d\n\n" % char.get("monsters_killed", 0)

	# Base stats with equipment bonuses shown
	text += "[color=#4A90E2]Base Stats:[/color]\n"
	text += "  STR: %d" % stats.get("strength", 0)
	if bonuses.strength > 0:
		text += " [color=#90EE90](+%d)[/color]" % bonuses.strength
	text += "  CON: %d" % stats.get("constitution", 0)
	if bonuses.constitution > 0:
		text += " [color=#90EE90](+%d)[/color]" % bonuses.constitution
	text += "  DEX: %d" % stats.get("dexterity", 0)
	if bonuses.dexterity > 0:
		text += " [color=#90EE90](+%d)[/color]" % bonuses.dexterity
	text += "\n"
	text += "  INT: %d" % stats.get("intelligence", 0)
	if bonuses.intelligence > 0:
		text += " [color=#90EE90](+%d)[/color]" % bonuses.intelligence
	text += "  WIS: %d" % stats.get("wisdom", 0)
	if bonuses.wisdom > 0:
		text += " [color=#90EE90](+%d)[/color]" % bonuses.wisdom
	text += "  WIT: %d" % stats.get("wits", stats.get("charisma", 0))
	if bonuses.wits > 0:
		text += " [color=#90EE90](+%d)[/color]" % bonuses.wits
	text += "\n\n"

	# Combat stats
	var total_attack = stats.get("strength", 0) + bonuses.strength + bonuses.attack
	var total_defense = (stats.get("constitution", 0) + bonuses.constitution) / 2 + bonuses.defense

	text += "[color=#FF6666]Combat Stats:[/color]\n"
	text += "  Attack Power: %d" % total_attack
	if bonuses.attack > 0:
		text += " [color=#90EE90](+%d from gear)[/color]" % bonuses.attack
	text += "\n"
	text += "  Defense: %d" % total_defense
	if bonuses.defense > 0:
		text += " [color=#90EE90](+%d from gear)[/color]" % bonuses.defense
	text += "\n"
	text += "  Damage: %d-%d\n" % [int(total_attack * 0.8), int(total_attack * 1.2)]

	display_game(text)

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
		"max_mana": 0
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

[color=#4A90E2]Movement:[/color]
  Press Escape to toggle movement mode
  Use NUMPAD: 7 8 9 = NW N NE
              4 5 6 = W stay E
              1 2 3 = SW S SE

[color=#4A90E2]Chat:[/color]
  Just type and press Enter!

[color=#4A90E2]Action Bar:[/color]
  [Space] = Primary action (Status/Attack)
  [Q][W][E][R] = Quick actions
  [1][2][3][4] = Additional actions

[color=#4A90E2]Inventory:[/color]
  inventory/inv/i - Open inventory
  [Q] Inventory in movement mode

[color=#4A90E2]Social:[/color]
  who/players - Refresh player list
  examine <name> - View player stats

[color=#4A90E2]Other:[/color]
  help - This help
  status - Show stats
  clear - Clear screens

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

[color=#4A90E2]Attack Damage:[/color]
  Base damage = STR × weapon modifier
  Final damage = Base × (1 + level/50) - enemy defense
  Critical hits deal 1.5x damage (chance based on DEX)

[color=#4A90E2]Defense:[/color]
  Damage reduction = CON% (max 30%)
  Armor adds flat reduction
  Block chance when defending = 25% + DEX/2

[color=#4A90E2]Hit Chance:[/color]
  Base hit = 75% + (your DEX - enemy DEX)
  Minimum 50%, maximum 95%

[color=#4A90E2]Flee Chance:[/color]
  Base flee = 40% + (your DEX × 2) - (enemy level / 10)
  Defending enemies: +20% flee chance
  Failed flee = enemy gets free attack

[color=#4A90E2]Combat Tips:[/color]
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

[b][color=#FFD700]== WARRIOR ABILITIES (STR Path) ==[/color][/b]
Uses [color=#FFCC00]Stamina[/color] = STR×4 + CON×4, regens 10% when defending

[color=#FF6666]Lv 1 - Power Strike[/color] (10 Stamina)
  Deal STR × 1.5 damage

[color=#FF6666]Lv 10 - War Cry[/color] (15 Stamina)
  +25% damage for 3 rounds

[color=#FF6666]Lv 25 - Shield Bash[/color] (20 Stamina)
  Deal STR damage + stun (enemy skips turn)

[color=#FF6666]Lv 40 - Cleave[/color] (30 Stamina)
  Deal STR × 2 damage

[color=#FF6666]Lv 60 - Berserk[/color] (40 Stamina)
  +100% damage, -50% defense for 3 rounds

[color=#FF6666]Lv 80 - Iron Skin[/color] (35 Stamina)
  Block 50% damage for 3 rounds

[color=#FF6666]Lv 100 - Devastate[/color] (50 Stamina)
  Deal STR × 4 damage

[b][color=#FFD700]== MAGE ABILITIES (INT Path) ==[/color][/b]
Uses [color=#66CCCC]Mana[/color] = INT×8 + WIS×4

[color=#66FFFF]Lv 1 - Magic Bolt[/color] (Variable Mana)
  Deal damage equal to mana spent (1:1 ratio)

[color=#66FFFF]Lv 10 - Shield[/color] (20 Mana)
  +50% defense for 3 rounds

[color=#66FFFF]Lv 25 - Cloak[/color] (30 Mana)
  50% chance enemy misses next attack

[color=#66FFFF]Lv 40 - Blast[/color] (50 Mana)
  Deal INT × 2 damage

[color=#66FFFF]Lv 60 - Forcefield[/color] (75 Mana)
  Block next 2 attacks completely

[color=#66FFFF]Lv 80 - Teleport[/color] (40 Mana)
  Guaranteed flee (always succeeds)

[color=#66FFFF]Lv 100 - Meteor[/color] (100 Mana)
  Deal INT × 5 damage

[b][color=#FFD700]== TRICKSTER ABILITIES (WITS Path) ==[/color][/b]
Uses [color=#66FF66]Energy[/color] = WITS×4 + DEX×4, regens 15% per round

[color=#FFA500]Lv 1 - Analyze[/color] (5 Energy)
  Reveal monster stats (HP, damage, intelligence)

[color=#FFA500]Lv 10 - Distract[/color] (15 Energy)
  Enemy has -50% accuracy on next attack

[color=#FFA500]Lv 25 - Pickpocket[/color] (20 Energy)
  Steal WITS × 10 gold (fail = monster attacks)

[color=#FFA500]Lv 40 - Ambush[/color] (30 Energy)
  Deal WITS × 1.5 damage + 50% crit chance

[color=#FFA500]Lv 60 - Vanish[/color] (40 Energy)
  Invisible, guaranteed crit on next attack

[color=#FFA500]Lv 80 - Exploit[/color] (35 Energy)
  Deal 10% of monster's current HP as damage

[color=#FFA500]Lv 100 - Perfect Heist[/color] (50 Energy)
  Instant win + double gold/gems

[b][color=#FFD700]== OUTSMART (WITS-based) ==[/color][/b]

[color=#FFA500]Outsmart[/color] - Trick dumb monsters
  Success = (Your WITS - Monster INT) × 5 + 30%
  Clamped between 5% and 95%
  Success: Instant win with full rewards
  Failure: Monster gets free attack, can't retry

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
