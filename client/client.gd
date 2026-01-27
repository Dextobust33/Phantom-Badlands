# client.gd
# Client with account system, character selection, and permadeath handling
extends Control

# Monster art helper - loaded lazily to avoid initialization issues
var _monster_art_script = null
func _get_monster_art():
	if _monster_art_script == null:
		_monster_art_script = load("res://client/monster_art.gd")
	return _monster_art_script

var connection = StreamPeerTCP.new()
var connected = false
var buffer = ""

# Connection settings
var server_ip: String = "localhost"
var server_port: int = 9080
var last_username: String = ""  # Remember last logged-in username
var saved_connections: Array = []  # Array of {name, ip, port}
const CONNECTION_CONFIG_PATH = "user://connection_settings.json"
const KEYBIND_CONFIG_PATH = "user://keybinds.json"

# Keybind configuration
var default_keybinds = {
	# Action bar (10 slots total)
	"action_0": KEY_SPACE,  # Primary action
	"action_1": KEY_Q,
	"action_2": KEY_W,
	"action_3": KEY_E,
	"action_4": KEY_R,
	"action_5": KEY_6,      # Extended action bar
	"action_6": KEY_7,
	"action_7": KEY_8,
	"action_8": KEY_9,
	"action_9": KEY_0,
	# Item selection keys (separate from action bar, always 1-9 by default)
	"item_1": KEY_1,
	"item_2": KEY_2,
	"item_3": KEY_3,
	"item_4": KEY_4,
	"item_5": KEY_5,
	"item_6": KEY_6,
	"item_7": KEY_7,
	"item_8": KEY_8,
	"item_9": KEY_9,
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
var settings_submenu: String = ""  # "", "action_keys", "movement_keys", "item_keys"
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
var ability_popup_description: RichTextLabel = null
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
# Action bar: 10 slots using action_0 through action_9
# Default keys: Space, Q, W, E, R, 6, 7, 8, 9, 0
# Item selection: separate system using item_1 through item_9 (keys 1-9 by default)
var current_actions: Array[Dictionary] = []

# Inventory mode
var inventory_mode: bool = false
var inventory_page: int = 0  # Current page (0-indexed)
var equip_page: int = 0  # Current page for filtered equip list (0-indexed)
var use_page: int = 0  # Current page for filtered usable items list (0-indexed)
var combat_use_page: int = 0  # Current page for combat usable items list (0-indexed)
const INVENTORY_PAGE_SIZE: int = 9  # Items per page (keys 1-9)

# Consumable tier system for display purposes (matches server calculations)
# mana = healing * 0.6, stamina/energy = healing * 0.5
const CONSUMABLE_TIERS = {
	1: {"name": "Minor", "healing": 50, "buff_value": 3, "mana": 30, "resource": 25},
	2: {"name": "Lesser", "healing": 100, "buff_value": 5, "mana": 60, "resource": 50},
	3: {"name": "Standard", "healing": 200, "buff_value": 8, "mana": 120, "resource": 100},
	4: {"name": "Greater", "healing": 400, "buff_value": 12, "mana": 240, "resource": 200},
	5: {"name": "Superior", "healing": 800, "buff_value": 18, "mana": 480, "resource": 400},
	6: {"name": "Master", "healing": 1600, "buff_value": 25, "mana": 960, "resource": 800},
	7: {"name": "Divine", "healing": 3000, "buff_value": 35, "mana": 1800, "resource": 1500}
}

var selected_item_index: int = -1  # Currently selected inventory item (0-based, -1 = none)
var pending_inventory_action: String = ""  # Action waiting for item selection
var last_item_use_result: String = ""  # Store last item use result to display after inventory refresh
var awaiting_item_use_result: bool = false  # Flag to capture next text message as item use result

# Ability management mode
var ability_mode: bool = false
var ability_data: Dictionary = {}  # Cached ability data from server
var pending_ability_action: String = ""  # "equip", "unequip", "keybind"
var selected_ability_slot: int = -1  # Slot being modified

# Pending continue state (prevents output clearing until player acknowledges)
var pending_continue: bool = false

# Track which action bar indices triggered actions this frame (to block item selection for same key)
var action_triggered_this_frame: Array = []

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
var sell_page: int = 0  # Current page in merchant sell list

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
var active_quests_display: Array = []  # Active quests shown in unified menu
var current_quest_tp_id: String = ""  # Trading post ID for quest menu

# Quest log abandonment mode
var quest_log_mode: bool = false
var quest_log_quests: Array = []  # Array of {id, name, progress, target}

# Wish selection mode (from wish_granter monsters)
var wish_selection_mode: bool = false
var wish_options: Array = []  # Array of wish dictionaries from server

# Monster selection mode (from Monster Selection Scroll)
var monster_select_mode: bool = false
var monster_select_list: Array = []  # Array of monster names
var monster_select_page: int = 0  # Current page in monster selection
var monster_select_confirm_mode: bool = false  # Waiting for confirmation
var monster_select_pending: String = ""  # Monster name pending confirmation
const MONSTER_SELECT_PAGE_SIZE: int = 9  # Items per page (keys 1-9)

# Target farm selection mode (from Scroll of Finding)
var target_farm_mode: bool = false
var target_farm_options: Array = []  # Array of ability IDs
var target_farm_names: Dictionary = {}  # Ability ID -> display name
var target_farm_encounters: int = 5

# Title system mode
var title_mode: bool = false  # Whether in title menu
var title_menu_data: Dictionary = {}  # Title menu data from server
var title_ability_mode: bool = false  # Whether selecting an ability
var title_target_mode: bool = false  # Whether selecting a target for ability
var pending_title_ability: String = ""  # Ability waiting for target selection
var title_online_players: Array = []  # List of online players for targeting
var title_broadcast_mode: bool = false  # Whether entering broadcast text
var forge_available: bool = false  # Whether at Infernal Forge with Unforged Crown

# Password change mode
var changing_password: bool = false
var password_change_step: int = 0  # 0=old, 1=new, 2=confirm
var temp_old_password: String = ""
var temp_new_password: String = ""

# Enemy tracking
var known_enemy_hp: Dictionary = {}
var discovered_monster_types: Dictionary = {}  # Tracks monster types by base name (first encounter)
var current_enemy_name: String = ""
var current_enemy_level: int = 0
var current_enemy_color: String = "#FFFFFF"  # Monster name color based on class affinity
var damage_dealt_to_current_enemy: int = 0
var current_enemy_hp: int = -1  # Actual HP from server (-1 = unknown)
var current_enemy_max_hp: int = -1  # Actual max HP from server
var current_forcefield: int = 0  # Current forcefield/shield value from combat

# Shield bar overlay (created dynamically)
var shield_fill_panel: Panel = null

# Combat animation system
var combat_spinner_frames = ["[", "|", "/", "-", "\\", "|", "/", "-"]
var combat_spinner_index: int = 0
var combat_animation_active: bool = false
var combat_animation_text: String = ""
var combat_animation_color: String = "#FFFF00"
var combat_animation_timer: float = 0.0
const SPINNER_SPEED: float = 0.08
const ANIMATION_DURATION: float = 0.6

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

# Danger warning sound (heavy damage taken)
var danger_player: AudioStreamPlayer = null
var last_known_hp_before_round: int = 0  # Track HP to detect heavy damage

# Combat sound effects (subtle, not overwhelming)
var combat_hit_player: AudioStreamPlayer = null  # Player lands an attack
var combat_crit_player: AudioStreamPlayer = null  # Critical hit
var combat_victory_player: AudioStreamPlayer = null  # Monster defeated (plays on first-time discoveries)
var combat_ability_player: AudioStreamPlayer = null  # Ability use
var last_combat_sound_time: float = 0.0
const COMBAT_SOUND_COOLDOWN: float = 0.15  # Minimum time between combat sounds

# ===== RACE DESCRIPTIONS =====
const RACE_DESCRIPTIONS = {
	"Human": "Adaptable and ambitious. Gains +10% bonus experience from all sources.",
	"Elf": "Ancient and resilient. 50% reduced poison damage, immune to poison debuffs.",
	"Dwarf": "Sturdy and determined. 25% chance to survive lethal damage with 1 HP (once per combat).",
	"Ogre": "Massive and regenerative. All healing effects are doubled."
}

const CLASS_DESCRIPTIONS = {
	"Fighter": "Warrior Path. Balanced melee fighter with solid defense and offense. Uses Stamina.\n[color=#C0C0C0]Passive - Tactical Discipline:[/color] 20% reduced stamina costs, +15% defense",
	"Barbarian": "Warrior Path. Aggressive berserker trading defense for raw damage. Uses Stamina.\n[color=#8B0000]Passive - Blood Rage:[/color] +3% damage per 10% HP missing (max +30%), abilities cost 25% more",
	"Paladin": "Warrior Path. Holy knight with sustain and bonus damage vs evil. Uses Stamina.\n[color=#FFD700]Passive - Divine Favor:[/color] Heal 3% max HP per round, +25% damage vs undead/demons",
	"Wizard": "Mage Path. Pure spellcaster with high magic damage. Uses Mana.\n[color=#4169E1]Passive - Arcane Precision:[/color] +15% spell damage, +10% spell crit chance",
	"Sorcerer": "Mage Path. Chaotic mage with high-risk, high-reward magic. Uses Mana.\n[color=#9400D3]Passive - Chaos Magic:[/color] 25% chance for double spell damage, 10% chance to backfire",
	"Sage": "Mage Path. Wise scholar with efficient mana use. Uses Mana.\n[color=#20B2AA]Passive - Mana Mastery:[/color] 25% reduced mana costs, Meditate restores 50% more",
	"Thief": "Trickster Path. Cunning rogue excelling at critical hits. Uses Energy.\n[color=#2F4F4F]Passive - Backstab:[/color] +50% crit damage, +15% base crit chance",
	"Ranger": "Trickster Path. Hunter with bonuses vs beasts and extra rewards. Uses Energy.\n[color=#228B22]Passive - Hunter's Mark:[/color] +25% damage vs beasts, +30% gold/XP from kills",
	"Ninja": "Trickster Path. Shadow warrior with superior escape abilities. Uses Energy.\n[color=#191970]Passive - Shadow Step:[/color] +40% flee success, take no damage when fleeing"
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

	# Setup class options (9 classes: 3 Warrior, 3 Mage, 3 Trickster)
	if class_option:
		class_option.clear()
		for cls in ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]:
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

	# Initialize danger warning sound player
	danger_player = AudioStreamPlayer.new()
	danger_player.volume_db = -18.0  # Quiet but noticeable
	add_child(danger_player)
	_generate_danger_sound()

	# Initialize combat sound players (subtle, not overwhelming)
	combat_hit_player = AudioStreamPlayer.new()
	combat_hit_player.volume_db = -22.0  # Very subtle
	add_child(combat_hit_player)
	_generate_combat_hit_sound()

	combat_crit_player = AudioStreamPlayer.new()
	combat_crit_player.volume_db = -18.0  # Slightly louder for impact
	add_child(combat_crit_player)
	_generate_combat_crit_sound()

	combat_victory_player = AudioStreamPlayer.new()
	combat_victory_player.volume_db = -20.0  # Subtle victory chime
	add_child(combat_victory_player)
	_generate_combat_victory_sound()

	combat_ability_player = AudioStreamPlayer.new()
	combat_ability_player.volume_db = -24.0  # Very subtle magical sound
	add_child(combat_ability_player)
	_generate_combat_ability_sound()

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

func _generate_danger_sound():
	"""Generate a low warning tone for heavy damage taken"""
	var sample_rate = 44100
	var duration = 0.35  # Short warning
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.mix_rate = sample_rate
	audio.stereo = true
	audio.format = AudioStreamWAV.FORMAT_16_BITS

	var data = PackedByteArray()
	data.resize(samples * 4)

	# Low warning tones descending (D3 → B2)
	var frequencies = [146.83, 123.47]  # D3, B2 - ominous low tones
	var durations = [0.2, 0.15]
	var time_offset = 0.0

	for n in range(frequencies.size()):
		var freq = frequencies[n]
		var note_duration = durations[n]
		var note_samples = int(sample_rate * note_duration)
		var start_sample = int(time_offset * sample_rate)

		for i in range(note_samples):
			var sample_idx = start_sample + i
			if sample_idx >= samples:
				break

			var t = float(i) / sample_rate
			var envelope = 1.0
			var attack = 0.01
			var release = 0.05

			if t < attack:
				envelope = t / attack
			elif t > note_duration - release:
				envelope = (note_duration - t) / release

			envelope = clamp(envelope, 0.0, 1.0)

			# Low rumbling tone with slight dissonance
			var sample = sin(t * freq * TAU) * 0.5
			sample += sin(t * freq * TAU * 1.01) * 0.3  # Slight detune for tension
			sample += sin(t * freq * TAU * 0.5) * 0.2  # Sub-bass
			sample *= envelope * 0.5

			var int_sample = int(clamp(sample, -1.0, 1.0) * 32767)
			var int_l = int_sample
			var int_r = int_sample

			data[sample_idx * 4] = int_l & 0xFF
			data[sample_idx * 4 + 1] = (int_l >> 8) & 0xFF
			data[sample_idx * 4 + 2] = int_r & 0xFF
			data[sample_idx * 4 + 3] = (int_r >> 8) & 0xFF

		time_offset += note_duration

	audio.data = data
	danger_player.stream = audio

func play_danger_sound():
	"""Play the danger warning sound"""
	if danger_player and danger_player.stream:
		danger_player.play()

# ===== COMBAT SOUND EFFECTS =====

func _generate_combat_hit_sound():
	"""Generate a subtle click/thump for landing an attack - very short"""
	var sample_rate = 44100
	var duration = 0.08  # Very short
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(samples * 2)

	for i in range(samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 50)  # Very fast decay

		# Low-mid click with some body
		var sample = sin(t * 180 * TAU) * 0.4  # Low thump
		sample += sin(t * 350 * TAU) * 0.3  # Mid click
		sample *= envelope * 0.25  # Keep it subtle

		var int_val = int(clamp(sample, -1.0, 1.0) * 32767)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data
	combat_hit_player.stream = audio

func _generate_combat_crit_sound():
	"""Generate a satisfying critical hit sound - short impact"""
	var sample_rate = 44100
	var duration = 0.15  # Short but impactful
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(samples * 2)

	for i in range(samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 25)  # Fast decay but slightly longer

		# Impact with bright overtone
		var sample = sin(t * 100 * TAU) * 0.5  # Deep impact
		sample += sin(t * 400 * TAU) * 0.3  # Bright tone
		sample += sin(t * 600 * TAU) * 0.2  # Shimmer
		sample *= envelope * 0.35  # Slightly louder than normal hit

		var int_val = int(clamp(sample, -1.0, 1.0) * 32767)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data
	combat_crit_player.stream = audio

func _generate_combat_victory_sound():
	"""Generate a short satisfying victory chime"""
	var sample_rate = 44100
	var duration = 0.25  # Short celebration
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(samples * 2)

	# Quick ascending notes (G4 -> C5)
	var notes = [392.0, 523.25]  # G4, C5
	var note_starts = [0.0, 0.08]
	var note_durs = [0.12, 0.17]

	for i in range(samples):
		var t = float(i) / sample_rate
		var sample = 0.0

		for n in range(notes.size()):
			var freq = notes[n]
			var start = note_starts[n]
			var dur = note_durs[n]
			if t >= start and t < start + dur:
				var note_t = t - start
				var envelope = 1.0 - (note_t / dur)
				envelope = envelope * envelope
				sample += sin(note_t * freq * TAU) * envelope * 0.25

		var int_val = int(clamp(sample, -1.0, 1.0) * 32767)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data
	combat_victory_player.stream = audio

func _generate_combat_ability_sound():
	"""Generate a subtle magical whoosh for ability use"""
	var sample_rate = 44100
	var duration = 0.12  # Very short
	var samples = int(sample_rate * duration)

	var audio = AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data = PackedByteArray()
	data.resize(samples * 2)

	for i in range(samples):
		var t = float(i) / sample_rate
		# Sweep from higher to lower frequency
		var freq = 800 - (t / duration) * 400  # 800Hz -> 400Hz sweep
		var envelope = sin(t / duration * PI)  # Bell curve

		var sample = sin(t * freq * TAU) * 0.2
		sample += sin(t * freq * 2 * TAU) * 0.1  # Harmonic
		sample *= envelope * 0.2  # Keep it subtle

		var int_val = int(clamp(sample, -1.0, 1.0) * 32767)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	audio.data = data
	combat_ability_player.stream = audio

func _can_play_combat_sound() -> bool:
	"""Check if enough time has passed since last combat sound"""
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_time - last_combat_sound_time >= COMBAT_SOUND_COOLDOWN

func play_combat_hit_sound():
	"""Play subtle hit sound if cooldown allows"""
	if not _can_play_combat_sound():
		return
	if combat_hit_player and combat_hit_player.stream:
		combat_hit_player.play()
		last_combat_sound_time = Time.get_ticks_msec() / 1000.0

func play_combat_crit_sound():
	"""Play critical hit sound - bypasses cooldown"""
	if combat_crit_player and combat_crit_player.stream:
		combat_crit_player.play()
		last_combat_sound_time = Time.get_ticks_msec() / 1000.0

func play_combat_victory_sound(force: bool = false):
	"""Play victory chime - only plays for first-time monster discoveries unless forced"""
	if not force:
		return  # Only play when discovering new monster types
	if combat_victory_player and combat_victory_player.stream:
		combat_victory_player.play()

func play_combat_ability_sound():
	"""Play ability use sound if cooldown allows"""
	if not _can_play_combat_sound():
		return
	if combat_ability_player and combat_ability_player.stream:
		combat_ability_player.play()
		last_combat_sound_time = Time.get_ticks_msec() / 1000.0

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

func _process(delta):
	# Clear action triggers from previous frame
	action_triggered_this_frame.clear()

	connection.poll()
	var status = connection.get_status()

	# Update combat animation
	if combat_animation_active:
		combat_animation_timer -= delta
		if combat_animation_timer <= 0:
			stop_combat_animation()
		else:
			# Update spinner frame
			var frame_time = fmod(ANIMATION_DURATION - combat_animation_timer, SPINNER_SPEED * combat_spinner_frames.size())
			combat_spinner_index = int(frame_time / SPINNER_SPEED) % combat_spinner_frames.size()

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
				elif settings_submenu == "item_keys":
					display_item_keybinds()
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

	# Inventory item selection with keybinds (items 1-9) when action is pending
	# Skip when in equip_confirm mode (that state uses action bar buttons, not item selection)
	# Skip when in monster_select_mode (scroll selection takes priority)
	if game_state == GameState.PLAYING and not input_field.has_focus() and inventory_mode and pending_inventory_action != "" and pending_inventory_action != "equip_confirm" and not monster_select_mode:
		for i in range(9):
			if is_item_select_key_pressed(i):
				# Skip if this key conflicts with a held action bar key
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("itemkey_%d_pressed" % i, false):
					set_meta("itemkey_%d_pressed" % i, true)
					var selection_index = i
					if pending_inventory_action == "equip_item":
						# Equip uses its own page for filtered list
						selection_index = equip_page * INVENTORY_PAGE_SIZE + i
					elif pending_inventory_action == "use_item":
						# Use item uses its own page for filtered list
						selection_index = use_page * INVENTORY_PAGE_SIZE + i
					else:
						# Regular inventory uses inventory_page
						selection_index = inventory_page * INVENTORY_PAGE_SIZE + i
					select_inventory_item(selection_index)
			else:
				set_meta("itemkey_%d_pressed" % i, false)

	# Merchant item selection with keybinds when action is pending
	if game_state == GameState.PLAYING and not input_field.has_focus() and at_merchant and pending_merchant_action == "sell":
		for i in range(9):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("merchantkey_%d_pressed" % i, false):
					set_meta("merchantkey_%d_pressed" % i, true)
					select_merchant_sell_item(i)  # 0-based index
			else:
				set_meta("merchantkey_%d_pressed" % i, false)

	# Merchant shop buy selection with keybinds
	if game_state == GameState.PLAYING and not input_field.has_focus() and at_merchant and pending_merchant_action == "buy":
		for i in range(9):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("buykey_%d_pressed" % i, false):
					set_meta("buykey_%d_pressed" % i, true)
					select_merchant_buy_item(i)  # 0-based index
			else:
				set_meta("buykey_%d_pressed" % i, false)

	# Quest selection with keybinds when in quest view mode
	if game_state == GameState.PLAYING and not input_field.has_focus() and at_trading_post and quest_view_mode:
		for i in range(9):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("questkey_%d_pressed" % i, false):
					set_meta("questkey_%d_pressed" % i, true)
					select_quest_option(i)  # 0-based index
			else:
				set_meta("questkey_%d_pressed" % i, false)

	# Quest log abandonment with keybinds when viewing quest log
	if game_state == GameState.PLAYING and not input_field.has_focus() and quest_log_mode and pending_continue:
		for i in range(min(quest_log_quests.size(), 9)):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("questlogkey_%d_pressed" % i, false):
					set_meta("questlogkey_%d_pressed" % i, true)
					abandon_quest_by_index(i)  # 0-based index
			else:
				set_meta("questlogkey_%d_pressed" % i, false)

	# Combat item selection with keybinds
	if game_state == GameState.PLAYING and not input_field.has_focus() and combat_item_mode:
		for i in range(9):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("combatitemkey_%d_pressed" % i, false):
					set_meta("combatitemkey_%d_pressed" % i, true)
					use_combat_item_by_number(i + 1)  # 1-based for user
			else:
				set_meta("combatitemkey_%d_pressed" % i, false)
		# Space key (action_0) cancels combat item mode
		var cancel_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
		if Input.is_physical_key_pressed(cancel_key):
			if not get_meta("combatitem_cancel_pressed", false):
				set_meta("combatitem_cancel_pressed", true)
				# Mark hotkey_0 as pressed to prevent attack on same frame
				# (action bar checks hotkey_0_pressed, not combatitem_cancel_pressed)
				set_meta("hotkey_0_pressed", true)
				cancel_combat_item_mode()
		else:
			set_meta("combatitem_cancel_pressed", false)

	# Monster selection with keybinds (from Monster Selection Scroll)
	if game_state == GameState.PLAYING and not input_field.has_focus() and monster_select_mode:
		if monster_select_confirm_mode:
			# Confirmation mode - Space=Confirm, Q=Back
			var confirm_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
			if Input.is_physical_key_pressed(confirm_key):
				if not get_meta("monsterselect_confirm_pressed", false):
					set_meta("monsterselect_confirm_pressed", true)
					confirm_monster_select()
			else:
				set_meta("monsterselect_confirm_pressed", false)

			var back_key = keybinds.get("action_1", default_keybinds.get("action_1", KEY_Q))
			if Input.is_physical_key_pressed(back_key):
				if not get_meta("monsterselect_back_pressed", false):
					set_meta("monsterselect_back_pressed", true)
					cancel_monster_select()  # Goes back to list in confirm mode
			else:
				set_meta("monsterselect_back_pressed", false)
		else:
			# Selection mode - Space=Cancel, Q=Prev, W=Next, 1-9=Select
			# Handle Cancel (Space/action_0)
			var cancel_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
			if Input.is_physical_key_pressed(cancel_key):
				if not get_meta("monsterselect_cancel_pressed", false):
					set_meta("monsterselect_cancel_pressed", true)
					cancel_monster_select()
			else:
				set_meta("monsterselect_cancel_pressed", false)

			# Handle Prev Page (Q/action_1)
			var prev_key = keybinds.get("action_1", default_keybinds.get("action_1", KEY_Q))
			if Input.is_physical_key_pressed(prev_key):
				if not get_meta("monsterselect_prev_pressed", false):
					set_meta("monsterselect_prev_pressed", true)
					if monster_select_page > 0:
						monster_select_page -= 1
						display_monster_select_page()
			else:
				set_meta("monsterselect_prev_pressed", false)

			# Handle Next Page (W/action_2)
			var next_key = keybinds.get("action_2", default_keybinds.get("action_2", KEY_W))
			if Input.is_physical_key_pressed(next_key):
				if not get_meta("monsterselect_next_pressed", false):
					set_meta("monsterselect_next_pressed", true)
					var total_pages = max(1, ceili(float(monster_select_list.size()) / MONSTER_SELECT_PAGE_SIZE))
					if monster_select_page < total_pages - 1:
						monster_select_page += 1
						display_monster_select_page()
			else:
				set_meta("monsterselect_next_pressed", false)

			# Handle number key selection (1-9 and numpad 1-9)
			for i in range(9):
				var regular_key_pressed = is_item_select_key_pressed(i)
				var numpad_key_pressed = Input.is_physical_key_pressed(KEY_KP_1 + i) and not Input.is_key_pressed(KEY_SHIFT)
				if regular_key_pressed or numpad_key_pressed:
					if not get_meta("monsterselectkey_%d_pressed" % i, false):
						set_meta("monsterselectkey_%d_pressed" % i, true)
						select_monster_from_scroll(i)  # 0-based index on current page
				else:
					set_meta("monsterselectkey_%d_pressed" % i, false)

	# Target farm selection with keybinds (from Scroll of Finding)
	if game_state == GameState.PLAYING and not input_field.has_focus() and target_farm_mode:
		for i in range(5):  # Only 5 options (1-5)
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("targetfarmkey_%d_pressed" % i, false):
					set_meta("targetfarmkey_%d_pressed" % i, true)
					select_target_farm_ability(i)  # 0-based index
			else:
				set_meta("targetfarmkey_%d_pressed" % i, false)

	# Inventory page navigation with item keys 2 and 3 (when no pending action)
	if game_state == GameState.PLAYING and not input_field.has_focus() and inventory_mode and pending_inventory_action == "":
		var inv = character_data.get("inventory", [])
		var total_pages = max(1, int(ceil(float(inv.size()) / INVENTORY_PAGE_SIZE)))

		# Item key 2 = Previous Page
		var prev_key = keybinds.get("item_2", default_keybinds.get("item_2", KEY_2))
		if Input.is_physical_key_pressed(prev_key) and not Input.is_key_pressed(KEY_SHIFT):
			if not get_meta("invpage_prev_pressed", false):
				set_meta("invpage_prev_pressed", true)
				if inventory_page > 0:
					inventory_page -= 1
					display_inventory()
		else:
			set_meta("invpage_prev_pressed", false)

		# Item key 3 = Next Page
		var next_key = keybinds.get("item_3", default_keybinds.get("item_3", KEY_3))
		if Input.is_physical_key_pressed(next_key) and not Input.is_key_pressed(KEY_SHIFT):
			if not get_meta("invpage_next_pressed", false):
				set_meta("invpage_next_pressed", true)
				if inventory_page < total_pages - 1:
					inventory_page += 1
					display_inventory()
		else:
			set_meta("invpage_next_pressed", false)

	# Watch request approval (action_1 = approve, action_2 = deny) - skip other hotkeys this frame
	var watch_request_handled = false
	if game_state == GameState.PLAYING and not input_field.has_focus() and watch_request_pending != "":
		var approve_key = keybinds.get("action_1", default_keybinds.get("action_1", KEY_Q))
		if Input.is_physical_key_pressed(approve_key):
			if not get_meta("watch_approve_pressed", false):
				set_meta("watch_approve_pressed", true)
				set_meta("hotkey_1_pressed", true)
				approve_watch_request()
				watch_request_handled = true
		else:
			set_meta("watch_approve_pressed", false)

		var deny_key = keybinds.get("action_2", default_keybinds.get("action_2", KEY_W))
		if Input.is_physical_key_pressed(deny_key):
			if not get_meta("watch_deny_pressed", false):
				set_meta("watch_deny_pressed", true)
				set_meta("hotkey_2_pressed", true)
				deny_watch_request()
				watch_request_handled = true
		else:
			set_meta("watch_deny_pressed", false)

	# Action bar hotkeys (only when input NOT focused and playing)
	# Allow hotkeys during merchant modes and inventory modes (for Cancel buttons)
	# Skip if in settings mode (settings has its own input handling)
	# Skip if in combat_item_mode (to prevent item selection from also triggering combat abilities)
	# Skip if in monster_select_mode (to prevent monster selection from also triggering action bar)
	# Skip if ability_popup is visible (typing in the input field)
	# Note: quest_log_mode handled separately below to allow Space (Continue) but block number keys
	var merchant_blocks_hotkeys = pending_merchant_action != "" and pending_merchant_action not in ["sell_gems", "upgrade", "buy", "buy_inspect", "buy_equip_prompt", "sell", "gamble", "gamble_again"]
	var ability_popup_open = ability_popup != null and ability_popup.visible
	if game_state == GameState.PLAYING and not input_field.has_focus() and not merchant_blocks_hotkeys and watch_request_pending == "" and not watch_request_handled and not settings_mode and not combat_item_mode and not monster_select_mode and not ability_popup_open:
		for i in range(10):  # All 10 action bar slots
			var action_key = "action_%d" % i
			var key = keybinds.get(action_key, default_keybinds.get(action_key, KEY_SPACE))
			if Input.is_physical_key_pressed(key) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("hotkey_%d_pressed" % i, false):
					set_meta("hotkey_%d_pressed" % i, true)
					# Only mark as triggered if this slot has an enabled action
					# (prevents blocking item selection when action bar slot is empty)
					if i < current_actions.size():
						var action = current_actions[i]
						if action.get("enabled", false) and action.get("action_type", "none") != "none":
							action_triggered_this_frame.append(i)
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

	# Movement and hunt (only when playing and not in combat, flock, pending continue, inventory, merchant, settings, or monster select)
	if connected and has_character and not input_field.has_focus() and not in_combat and not flock_pending and not pending_continue and not inventory_mode and not at_merchant and not settings_mode and not monster_select_mode:
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
					clear_game_output()
					last_move_time = current_time
				elif is_hunt:
					clear_game_output()
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
			player_list_refresh_timer += delta
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
			elif settings_submenu == "item_keys":
				display_item_keybinds()
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
			# Main settings menu - use actual keybinds
			var key_action_1 = keybinds.get("action_1", default_keybinds.get("action_1", KEY_Q))
			var key_action_2 = keybinds.get("action_2", default_keybinds.get("action_2", KEY_W))
			var key_action_3 = keybinds.get("action_3", default_keybinds.get("action_3", KEY_E))
			var key_action_4 = keybinds.get("action_4", default_keybinds.get("action_4", KEY_R))
			var key_action_0 = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))

			if keycode == key_action_1:
				settings_submenu = "action_keys"
				game_output.clear()
				display_action_keybinds()
				update_action_bar()
			elif keycode == key_action_2:
				settings_submenu = "movement_keys"
				game_output.clear()
				display_movement_keybinds()
				update_action_bar()
			elif keycode == key_action_3:
				settings_submenu = "item_keys"
				game_output.clear()
				display_item_keybinds()
				update_action_bar()
			elif keycode == key_action_4:
				reset_keybinds_to_defaults()
			elif keycode == key_action_0:
				close_settings()
			get_viewport().set_input_as_handled()
		elif settings_submenu == "action_keys":
			# Action keybinds submenu - 0-9 to rebind action bar keys
			var back_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
			if keycode >= KEY_0 and keycode <= KEY_9:
				var index = keycode - KEY_0
				start_rebinding("action_%d" % index)
			elif keycode == back_key:
				settings_submenu = ""
				game_output.clear()
				display_settings_menu()
				update_action_bar()
			get_viewport().set_input_as_handled()
		elif settings_submenu == "item_keys":
			# Item selection keybinds submenu - 1-9 to rebind item keys
			var back_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
			if keycode >= KEY_1 and keycode <= KEY_9:
				var index = keycode - KEY_1  # 0-8
				start_rebinding("item_%d" % (index + 1))  # item_1 through item_9
			elif keycode == back_key:
				settings_submenu = ""
				game_output.clear()
				display_settings_menu()
				update_action_bar()
			get_viewport().set_input_as_handled()
		elif settings_submenu == "movement_keys":
			# Movement keybinds submenu
			var back_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
			var key_1 = keybinds.get("action_1", default_keybinds.get("action_1", KEY_Q))
			var key_2 = keybinds.get("action_2", default_keybinds.get("action_2", KEY_W))
			var key_3 = keybinds.get("action_3", default_keybinds.get("action_3", KEY_E))
			var key_4 = keybinds.get("action_4", default_keybinds.get("action_4", KEY_R))

			if keycode == KEY_1:
				start_rebinding("move_7")  # NW
			elif keycode == KEY_2:
				start_rebinding("move_8")  # N
			elif keycode == KEY_3:
				start_rebinding("move_9")  # NE
			elif keycode == KEY_4:
				start_rebinding("move_4")  # W
			elif keycode == KEY_5:
				start_rebinding("hunt")
			elif keycode == KEY_6:
				start_rebinding("move_6")  # E
			elif keycode == KEY_7:
				start_rebinding("move_1")  # SW
			elif keycode == KEY_8:
				start_rebinding("move_2")  # S
			elif keycode == KEY_9:
				start_rebinding("move_3")  # SE
			elif keycode == key_1:
				start_rebinding("move_up")
			elif keycode == key_2:
				start_rebinding("move_down")
			elif keycode == key_3:
				start_rebinding("move_left")
			elif keycode == key_4:
				start_rebinding("move_right")
			elif keycode == back_key:
				settings_submenu = ""
				game_output.clear()
				display_settings_menu()
				update_action_bar()
			get_viewport().set_input_as_handled()

	# Handle ability mode input
	if ability_mode and event is InputEventKey and event.pressed and not event.echo:
		var keycode = event.keycode

		if pending_ability_action == "press_keybind":
			# Waiting for a key to set as keybind
			if keycode == KEY_ESCAPE or keycode == KEY_SPACE:
				# Cancel
				pending_ability_action = ""
				selected_ability_slot = -1
				display_ability_menu()
				update_action_bar()
			elif keycode >= KEY_A and keycode <= KEY_Z:
				# Accept letter keys
				var key_char = char(keycode)
				handle_keybind_press(key_char)
			get_viewport().set_input_as_handled()
			return

		if pending_ability_action == "choose_ability":
			# Choosing from ability list
			if keycode >= KEY_1 and keycode <= KEY_9:
				var choice = keycode - KEY_0
				handle_ability_choice(choice)
				get_viewport().set_input_as_handled()
				return
			elif keycode == KEY_SPACE or keycode == KEY_ESCAPE:
				pending_ability_action = ""
				selected_ability_slot = -1
				display_ability_menu()
				update_action_bar()
				get_viewport().set_input_as_handled()
				return

		if pending_ability_action in ["select_ability", "select_unequip_slot", "select_keybind_slot"]:
			# Selecting a slot (1-4)
			if keycode >= KEY_1 and keycode <= KEY_4:
				var slot_num = keycode - KEY_0
				handle_ability_slot_selection(slot_num)
				get_viewport().set_input_as_handled()
				return
			elif keycode == KEY_SPACE or keycode == KEY_ESCAPE:
				pending_ability_action = ""
				display_ability_menu()
				update_action_bar()
				get_viewport().set_input_as_handled()
				return

		# Main ability menu (no pending action) - handle Q/W/E/R for menu actions
		if pending_ability_action == "":
			if keycode == KEY_SPACE or keycode == KEY_ESCAPE:
				# Exit ability mode
				exit_ability_mode()
				get_viewport().set_input_as_handled()
				return
			elif keycode == KEY_Q:
				# Equip
				show_ability_equip_prompt()
				get_viewport().set_input_as_handled()
				return
			elif keycode == KEY_W:
				# Unequip
				show_ability_unequip_prompt()
				get_viewport().set_input_as_handled()
				return
			elif keycode == KEY_E:
				# Keybinds
				show_keybind_prompt()
				get_viewport().set_input_as_handled()
				return

	# Handle title mode input
	if title_mode and event is InputEventKey and event.pressed and not event.echo:
		var keycode = event.keycode
		if handle_title_key_input(keycode):
			get_viewport().set_input_as_handled()
			return

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
			# Populate with last used username if available
			if last_username != "" and username_field.text == "":
				username_field.text = last_username
				# Focus password field since username is already filled
				if password_field:
					password_field.grab_focus()
			else:
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
		var ptitle = player.get("title", "")

		# Format name with title prefix if present
		var display_name = pname
		if not ptitle.is_empty():
			var title_info = _get_title_display_info(ptitle)
			display_name = "[color=%s]%s[/color] %s" % [title_info.color, title_info.prefix, pname]

		# Use URL tags to make names clickable (double-click shows stats)
		online_players_list.append_text("[url=%s]%s[/url] Lv%d %s\n" % [pname, display_name if ptitle.is_empty() else display_name, plevel, pclass])

func _get_title_display_info(title_id: String) -> Dictionary:
	"""Get display info for a title (color, prefix, name)"""
	var title_data = {
		"jarl": {"name": "Jarl", "color": "#C0C0C0", "prefix": "[Jarl]"},
		"high_king": {"name": "High King", "color": "#FFD700", "prefix": "[High King]"},
		"elder": {"name": "Elder", "color": "#9400D3", "prefix": "[Elder]"},
		"eternal": {"name": "Eternal", "color": "#00FFFF", "prefix": "[Eternal]"}
	}
	return title_data.get(title_id, {"name": title_id.capitalize(), "color": "#FFFFFF", "prefix": ""})

func display_examine_result(data: Dictionary):
	"""Display examined player info in game output"""
	var pname = data.get("name", "Unknown")
	var level = data.get("level", 1)
	var char_race = data.get("race", "Human")
	var cls = data.get("class", "Unknown")
	var hp = data.get("hp", 0)
	var max_hp = data.get("total_max_hp", data.get("max_hp", 1))  # Use equipment-boosted HP
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
	# Add cloak indicator if active
	var cloak_active = data.get("cloak_active", false)
	if cloak_active and not in_combat_flag:
		status = "[color=#9932CC]Cloaked[/color]"

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
	class_description.clear()
	class_description.append_text(CLASS_DESCRIPTIONS.get(selected_class, ""))

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
	var max_hp = data.get("total_max_hp", data.get("max_hp", 1))  # Use equipment-boosted HP
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
	# Add cloak indicator if active
	var cloak_active = data.get("cloak_active", false)
	if cloak_active and not in_combat_status:
		status_text = "[color=#9932CC]Cloaked[/color]"

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

	# Reset status page background if active (gets set in display_character_status)
	_reset_game_output_background()

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
				{"label": "Back", "action_type": "local", "action_data": "settings_back_to_main", "enabled": true},
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
		elif settings_submenu == "item_keys":
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "settings_back_to_main", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Press 1-9", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "to rebind", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif settings_submenu == "movement_keys":
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "settings_back_to_main", "enabled": true},
				{"label": "Up", "action_type": "local", "action_data": "settings_rebind_move_up", "enabled": true},
				{"label": "Down", "action_type": "local", "action_data": "settings_rebind_move_down", "enabled": true},
				{"label": "Left", "action_type": "local", "action_data": "settings_rebind_move_left", "enabled": true},
				{"label": "Right", "action_type": "local", "action_data": "settings_rebind_move_right", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "settings_close", "enabled": true},
				{"label": "Actions", "action_type": "local", "action_data": "settings_action_keys", "enabled": true},
				{"label": "Movement", "action_type": "local", "action_data": "settings_movement_keys", "enabled": true},
				{"label": "Items", "action_type": "local", "action_data": "settings_item_keys", "enabled": true},
				{"label": "Reset", "action_type": "local", "action_data": "settings_reset", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif wish_selection_mode:
		# Wish granter reward selection - Q/W/E for 3 options
		current_actions = [
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "Wish 1", "action_type": "local", "action_data": "wish_select_0", "enabled": wish_options.size() > 0},
			{"label": "Wish 2", "action_type": "local", "action_data": "wish_select_1", "enabled": wish_options.size() > 1},
			{"label": "Wish 3", "action_type": "local", "action_data": "wish_select_2", "enabled": wish_options.size() > 2},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif monster_select_mode:
		if monster_select_confirm_mode:
			# Confirmation mode - Space=Confirm, Q=Back to list
			current_actions = [
				{"label": "Confirm", "action_type": "local", "action_data": "monster_select_confirm", "enabled": true},
				{"label": "Back", "action_type": "local", "action_data": "monster_select_back", "enabled": true},
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
			# Monster selection from scroll - Space=Cancel, Q=Prev, W=Next, 1-9=Select
			var total_pages = max(1, ceili(float(monster_select_list.size()) / MONSTER_SELECT_PAGE_SIZE))
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "monster_select_cancel", "enabled": true},
				{"label": "Prev Pg", "action_type": "local", "action_data": "monster_select_prev", "enabled": monster_select_page > 0},
				{"label": "Next Pg", "action_type": "local", "action_data": "monster_select_next", "enabled": monster_select_page < total_pages - 1},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-9 Select", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif target_farm_mode:
		# Target farm selection from scroll - Space=Cancel, 1-5=Select
		current_actions = [
			{"label": "Cancel", "action_type": "local", "action_data": "target_farm_cancel", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "1-5 Select", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif ability_mode:
		# Ability management mode
		if pending_ability_action == "choose_ability":
			# Choosing an ability from list
			var unlocked = ability_data.get("unlocked_abilities", [])
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "ability_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-%d Select" % unlocked.size(), "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_ability_action == "press_keybind":
			# Waiting for keybind press
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "ability_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Press Key", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_ability_action in ["select_ability", "select_unequip_slot", "select_keybind_slot"]:
			# Selecting a slot (1-4)
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "ability_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-4 Slot", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Main ability menu
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "ability_exit", "enabled": true},
				{"label": "Equip", "action_type": "local", "action_data": "ability_equip", "enabled": true},
				{"label": "Unequip", "action_type": "local", "action_data": "ability_unequip", "enabled": true},
				{"label": "Keybinds", "action_type": "local", "action_data": "ability_keybinds", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif title_mode:
		# Title menu mode
		var abilities = title_menu_data.get("abilities", {})
		var claimable = title_menu_data.get("claimable", [])
		if title_target_mode:
			# Target selection
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "title_exit", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-9 Select", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Main title menu - show abilities as Q/W/E/R
			var ability_labels = []
			var ability_ids = abilities.keys()
			for i in range(4):
				if i < ability_ids.size():
					var ability = abilities[ability_ids[i]]
					ability_labels.append({"label": ability.get("name", "?"), "action_type": "none", "action_data": "", "enabled": true})
				else:
					ability_labels.append({"label": "---", "action_type": "none", "action_data": "", "enabled": false})
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "title_exit", "enabled": true},
				ability_labels[0],
				ability_labels[1],
				ability_labels[2],
				ability_labels[3],
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif combat_item_mode:
		# Combat item selection mode - show cancel and page navigation
		var usable_items = get_meta("combat_usable_items", [])
		var total_pages = max(1, int(ceil(float(usable_items.size()) / INVENTORY_PAGE_SIZE)))
		var has_prev = combat_use_page > 0
		var has_next = combat_use_page < total_pages - 1
		current_actions = [
			{"label": "Cancel", "action_type": "local", "action_data": "combat_item_cancel", "enabled": true},
			{"label": "Prev Pg", "action_type": "local", "action_data": "combat_use_prev_page", "enabled": has_prev},
			{"label": "Next Pg", "action_type": "local", "action_data": "combat_use_next_page", "enabled": has_next},
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
			# Waiting for item selection (use number keys) with pagination
			var inventory = character_data.get("inventory", [])
			var has_items = inventory.size() > 0
			var total_pages = max(1, ceili(float(inventory.size()) / INVENTORY_PAGE_SIZE))
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "Prev", "action_type": "local", "action_data": "sell_prev_page", "enabled": sell_page > 0},
				{"label": "Next", "action_type": "local", "action_data": "sell_next_page", "enabled": sell_page < total_pages - 1},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Sell All", "action_type": "local", "action_data": "sell_all_items", "enabled": has_items},
				{"label": "1-9 Sell", "action_type": "none", "action_data": "", "enabled": false},
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
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Sell All", "action_type": "local", "action_data": "sell_all_gems", "enabled": player_gems > 0},
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
		if pending_inventory_action == "equip_confirm":
			# Confirming equip - show equip/cancel options
			current_actions = [
				{"label": "Equip", "action_type": "local", "action_data": "confirm_equip", "enabled": true},
				{"label": "Cancel", "action_type": "local", "action_data": "cancel_equip_confirm", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_inventory_action == "equip_item":
			# Equip mode uses filtered equippable items list with its own pagination
			var equippable_items = get_meta("equippable_items", [])
			var total_pages = max(1, int(ceil(float(equippable_items.size()) / INVENTORY_PAGE_SIZE)))
			var has_prev = equip_page > 0
			var has_next = equip_page < total_pages - 1
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "inventory_cancel", "enabled": true},
				{"label": "Prev Pg", "action_type": "local", "action_data": "equip_prev_page", "enabled": has_prev},
				{"label": "Next Pg", "action_type": "local", "action_data": "equip_next_page", "enabled": has_next},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_inventory_action == "use_item":
			# Use mode uses filtered usable items list with its own pagination
			var usable_items = get_meta("usable_items", [])
			var total_pages = max(1, int(ceil(float(usable_items.size()) / INVENTORY_PAGE_SIZE)))
			var has_prev = use_page > 0
			var has_next = use_page < total_pages - 1
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "inventory_cancel", "enabled": true},
				{"label": "Prev Pg", "action_type": "local", "action_data": "use_prev_page", "enabled": has_prev},
				{"label": "Next Pg", "action_type": "local", "action_data": "use_next_page", "enabled": has_next},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_inventory_action != "":
			# Waiting for item selection - show cancel and page navigation
			var inv = character_data.get("inventory", [])
			var total_pages = max(1, int(ceil(float(inv.size()) / INVENTORY_PAGE_SIZE)))
			var has_prev = inventory_page > 0
			var has_next = inventory_page < total_pages - 1
			# Show Equipped option in inspect modes
			var show_equipped = pending_inventory_action in ["inspect_item", "inspect_equipped_item"]
			var equipped = character_data.get("equipped", {})
			var has_equipped = show_equipped and _count_equipped_items(equipped) > 0
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "inventory_cancel", "enabled": true},
				{"label": "Prev Pg", "action_type": "local", "action_data": "inventory_prev_page", "enabled": has_prev},
				{"label": "Next Pg", "action_type": "local", "action_data": "inventory_next_page", "enabled": has_next},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Equipped", "action_type": "local", "action_data": "inspect_equipped_switch", "enabled": has_equipped},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Inventory sub-menu: Spacebar=Back, Q-R for inventory actions
			# Discard moved to end (KEY_5) to prevent accidental use
			var equipped = character_data.get("equipped", {})
			var has_equipped = _count_equipped_items(equipped) > 0
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "inventory_back", "enabled": true},
				{"label": "Inspect", "action_type": "local", "action_data": "inventory_inspect", "enabled": true},
				{"label": "Use", "action_type": "local", "action_data": "inventory_use", "enabled": true},
				{"label": "Equip", "action_type": "local", "action_data": "inventory_equip", "enabled": true},
				{"label": "Unequip", "action_type": "local", "action_data": "inventory_unequip", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "InspEquip", "action_type": "local", "action_data": "inventory_inspect_equipped", "enabled": has_equipped},
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
		# Mages use "Meditate" instead of "Rest"
		var rest_label = "Rest"
		var char_class = character_data.get("class", "")
		if char_class in ["Wizard", "Sorcerer", "Sage"]:
			rest_label = "Meditate"
		# Cloak availability (level 20+)
		var player_level = character_data.get("level", 1)
		var cloak_unlocked = player_level >= 20
		var cloak_active = character_data.get("cloak_active", false)
		var cloak_label = "Uncloak" if cloak_active else "Cloak"
		# Title button if player has a title
		var player_title = character_data.get("title", "")
		var has_title = not player_title.is_empty()
		# Use "Title" button for titled players, otherwise "Help"
		var fourth_action = {"label": "Title", "action_type": "local", "action_data": "title", "enabled": true} if has_title else {"label": "Help", "action_type": "local", "action_data": "help", "enabled": true}
		# Forge button if at Infernal Forge with Unforged Crown
		var fifth_action = {"label": "Forge", "action_type": "local", "action_data": "forge_crown", "enabled": true} if forge_available else {"label": "Quests", "action_type": "local", "action_data": "show_quests", "enabled": true}
		# Cloak button only shows if unlocked (level 20+), otherwise blank slot
		var cloak_action = {"label": cloak_label, "action_type": "server", "action_data": "toggle_cloak", "enabled": true} if cloak_unlocked else {"label": "---", "action_type": "none", "action_data": "", "enabled": false}
		current_actions = [
			{"label": "Status", "action_type": "local", "action_data": "status", "enabled": true},
			{"label": "Inventory", "action_type": "local", "action_data": "inventory", "enabled": true},
			{"label": rest_label, "action_type": "server", "action_data": "rest", "enabled": true},
			fourth_action,
			fifth_action,
			{"label": "Abilities", "action_type": "local", "action_data": "abilities", "enabled": true},
			{"label": "Settings", "action_type": "local", "action_data": "settings", "enabled": true},
			cloak_action,
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

	# Start combat animation based on command
	_start_combat_command_animation(command)

	display_game("[color=#00FFFF]> %s[/color]" % command)
	send_to_server({"type": "combat", "command": command})

func _start_combat_command_animation(command: String):
	"""Start an animation based on the combat command"""
	match command.to_lower():
		"attack", "a":
			start_combat_animation("Attacking...", "#FFFF00")
		"flee", "f", "run":
			start_combat_animation("Fleeing...", "#808080")
		"outsmart", "o":
			start_combat_animation("Outsmarting...", "#00FFFF")
		"defend", "d":
			start_combat_animation("Defending...", "#00FF00")
		# Mage abilities
		"bolt", "magic_bolt":
			start_combat_animation("Casting Bolt...", "#00BFFF")
		"shield":
			start_combat_animation("Casting Shield...", "#00FF00")
		"cloak":
			start_combat_animation("Casting Cloak...", "#9932CC")
		"blast":
			start_combat_animation("Casting Blast...", "#FF4500")
		"forcefield":
			start_combat_animation("Casting Forcefield...", "#00CED1")
		"teleport":
			start_combat_animation("Teleporting...", "#DA70D6")
		"meteor":
			start_combat_animation("Casting Meteor...", "#FF6347")
		# Warrior abilities
		"power_strike", "strike":
			start_combat_animation("Power Strike...", "#FF4500")
		"war_cry", "warcry":
			start_combat_animation("War Cry...", "#FFD700")
		"shield_bash", "bash":
			start_combat_animation("Shield Bash...", "#C0C0C0")
		"cleave":
			start_combat_animation("Cleave...", "#DC143C")
		"berserk":
			start_combat_animation("Going Berserk...", "#8B0000")
		"iron_skin", "ironskin":
			start_combat_animation("Iron Skin...", "#708090")
		"devastate":
			start_combat_animation("Devastating...", "#FF0000")
		# Trickster abilities
		"analyze":
			start_combat_animation("Analyzing...", "#32CD32")
		"distract":
			start_combat_animation("Distracting...", "#FFD700")
		"pickpocket":
			start_combat_animation("Pickpocketing...", "#DAA520")
		"ambush":
			start_combat_animation("Ambushing...", "#8B4513")
		"vanish":
			start_combat_animation("Vanishing...", "#4B0082")
		"exploit":
			start_combat_animation("Exploiting...", "#FF6600")
		"perfect_heist", "heist":
			start_combat_animation("Perfect Heist...", "#FFD700")
		_:
			# Generic ability animation
			start_combat_animation("Using ability...", "#00FFFF")

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

	# Description label (RichTextLabel for BBCode support)
	ability_popup_description = RichTextLabel.new()
	ability_popup_description.bbcode_enabled = true
	ability_popup_description.fit_content = true
	ability_popup_description.scroll_active = false
	ability_popup_description.custom_minimum_size = Vector2(0, 40)
	ability_popup_description.add_theme_color_override("default_color", Color(0.7, 0.7, 0.7))
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
	ability_popup_description.text = "[center]Damage dealt equals %s spent.[/center]" % resource_name.to_lower()
	ability_popup_resource_label.text = "Current %s: %d" % [resource_name, current_resource]

	# Color the resource label based on type
	match pending_variable_resource:
		"mana":
			ability_popup_resource_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.8))
		"stamina":
			ability_popup_resource_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3))
		"energy":
			ability_popup_resource_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))

	# For Magic Bolt: auto-suggest mana needed to kill monster based on INT and class passives
	var suggested_amount = 0
	if ability == "magic_bolt" and current_enemy_max_hp > 0 and current_enemy_hp > 0:
		# Magic Bolt damage = mana * (1 + INT/50) * damage_buff, reduced by monster WIS
		# Calculate mana needed based on player INT
		var stats = character_data.get("stats", {})
		var int_stat = stats.get("intelligence", 10)
		var int_multiplier = 1.0 + (float(int_stat) / 50.0)  # INT 50 = 2x damage per mana

		# Apply damage buff (War Cry, potions, etc.) - from active_buffs and persistent_buffs
		var damage_buff = _get_buff_value("damage")
		var buff_multiplier = 1.0 + (float(damage_buff) / 100.0)

		# Estimate monster WIS reduction based on level (formula: min(0.30, monster_int / 300))
		# Monster INT by level tier: 1-5=5, 6-15=10, 16-30=18, 31-50=25, 51-100=35, 101-500=45, 500+=55+
		var estimated_monster_int = 10  # Default for low level
		if current_enemy_level <= 5:
			estimated_monster_int = 5
		elif current_enemy_level <= 15:
			estimated_monster_int = 10
		elif current_enemy_level <= 30:
			estimated_monster_int = 18
		elif current_enemy_level <= 50:
			estimated_monster_int = 25
		elif current_enemy_level <= 100:
			estimated_monster_int = 35
		elif current_enemy_level <= 500:
			estimated_monster_int = 45
		else:
			estimated_monster_int = 55
		var wis_reduction = minf(0.30, float(estimated_monster_int) / 300.0)
		var effective_multiplier = int_multiplier * buff_multiplier * (1.0 - wis_reduction)

		# Apply class passive bonuses
		var class_type = character_data.get("class", "")
		var bonus_parts = []
		match class_type:
			"Wizard":
				# Arcane Precision: +15% spell damage, +10% crit (avg +5% more)
				effective_multiplier *= 1.15 * 1.05  # Include average crit bonus
				bonus_parts.append("[color=#4169E1]+15% Arcane[/color]")
			"Sorcerer":
				# Chaos Magic: average ~10% bonus (25% double, 10% backfire)
				effective_multiplier *= 1.10
				bonus_parts.append("[color=#9400D3]+10% Chaos[/color]")

		if damage_buff > 0:
			bonus_parts.append("[color=#FFD700]+%d%% buff[/color]" % damage_buff)

		# Calculate mana needed (add 15% buffer to account for variance and ensure kill)
		var mana_needed = ceili(float(current_enemy_hp) / effective_multiplier * 1.15)
		suggested_amount = mini(mana_needed, current_resource)

		var damage_per_mana = snapped(effective_multiplier, 0.1)
		var bonus_text = " ".join(bonus_parts) if bonus_parts.size() > 0 else ""
		if bonus_text != "":
			bonus_text = " " + bonus_text
		ability_popup_description.text = "[center]~%.1f dmg/mana (INT %d)%s\nEnemy HP: %d[/center]" % [damage_per_mana, int_stat, bonus_text, current_enemy_hp]

	if suggested_amount > 0:
		ability_popup_input.text = str(suggested_amount)
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
	"""Build combat ability actions based on player's equipped abilities."""
	var abilities = []
	var player_level = character_data.get("level", 1)
	var path = _get_player_active_path()

	# Get current resources
	var current_mana = character_data.get("current_mana", 0)
	var current_stamina = character_data.get("current_stamina", 0)
	var current_energy = character_data.get("current_energy", 0)

	# Get equipped abilities from character data
	var equipped_abilities = character_data.get("equipped_abilities", [])

	# If no equipped abilities, fall back to hardcoded slots (backward compatibility)
	if equipped_abilities.is_empty():
		var ability_slots = _get_ability_slots_for_path(path)
		# Build using old method
		for i in range(6):
			if i < ability_slots.size():
				var slot = ability_slots[i]
				var command = slot[0]
				var display_name = slot[1]
				var required_level = slot[2]
				var cost = slot[3]
				var resource_type = slot[4]

				if player_level >= required_level:
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
					abilities.append({
						"label": "Lv%d" % required_level,
						"action_type": "none",
						"action_data": "",
						"enabled": false,
						"cost": 0,
						"resource_type": ""
					})
			else:
				abilities.append({
					"label": "---",
					"action_type": "none",
					"action_data": "",
					"enabled": false,
					"cost": 0,
					"resource_type": ""
				})
		return abilities

	# Build ability actions from equipped abilities (4 slots + 2 empty for expansion)
	for i in range(6):
		if i < equipped_abilities.size() and equipped_abilities[i] != "" and equipped_abilities[i] != null:
			var ability_name = equipped_abilities[i]
			var ability_info = _get_ability_combat_info(ability_name, path)

			if ability_info.is_empty():
				abilities.append({
					"label": "---",
					"action_type": "none",
					"action_data": "",
					"enabled": false,
					"cost": 0,
					"resource_type": ""
				})
				continue

			var cost = ability_info.cost
			var resource_type = ability_info.resource_type

			# Check if player has enough resources
			var has_resource = true
			if resource_type == "mana" and cost > 0:
				has_resource = current_mana >= cost
			elif resource_type == "stamina":
				has_resource = current_stamina >= cost
			elif resource_type == "energy":
				has_resource = current_energy >= cost

			abilities.append({
				"label": ability_info.display,
				"action_type": "combat",
				"action_data": ability_name,
				"enabled": has_resource,
				"cost": cost,
				"resource_type": resource_type
			})
		else:
			abilities.append({
				"label": "---",
				"action_type": "none",
				"action_data": "",
				"enabled": false,
				"cost": 0,
				"resource_type": ""
			})

	return abilities

func _get_ability_combat_info(ability_name: String, path: String) -> Dictionary:
	"""Get combat info for an ability (display name, cost, resource type)"""
	var resource_type = "mana" if path == "mage" else ("stamina" if path == "warrior" else "energy")

	# Ability definitions with display name and cost
	var ability_defs = {
		# Mage abilities
		"magic_bolt": {"display": "Bolt", "cost": 0, "resource_type": "mana"},
		"shield": {"display": "Shield", "cost": 20, "resource_type": "mana"},
		"blast": {"display": "Blast", "cost": 50, "resource_type": "mana"},
		"forcefield": {"display": "Field", "cost": 75, "resource_type": "mana"},
		"teleport": {"display": "Teleport", "cost": 40, "resource_type": "mana"},
		"meteor": {"display": "Meteor", "cost": 100, "resource_type": "mana"},
		"haste": {"display": "Haste", "cost": 35, "resource_type": "mana"},
		"paralyze": {"display": "Paralyze", "cost": 60, "resource_type": "mana"},
		"banish": {"display": "Banish", "cost": 80, "resource_type": "mana"},
		# Warrior abilities
		"power_strike": {"display": "Strike", "cost": 10, "resource_type": "stamina"},
		"war_cry": {"display": "Cry", "cost": 15, "resource_type": "stamina"},
		"shield_bash": {"display": "Bash", "cost": 20, "resource_type": "stamina"},
		"cleave": {"display": "Cleave", "cost": 30, "resource_type": "stamina"},
		"berserk": {"display": "Berserk", "cost": 40, "resource_type": "stamina"},
		"iron_skin": {"display": "Iron", "cost": 35, "resource_type": "stamina"},
		"devastate": {"display": "Devastate", "cost": 60, "resource_type": "stamina"},
		"fortify": {"display": "Fortify", "cost": 25, "resource_type": "stamina"},
		"rally": {"display": "Rally", "cost": 45, "resource_type": "stamina"},
		# Trickster abilities
		"analyze": {"display": "Analyze", "cost": 5, "resource_type": "energy"},
		"distract": {"display": "Distract", "cost": 15, "resource_type": "energy"},
		"pickpocket": {"display": "Steal", "cost": 20, "resource_type": "energy"},
		"ambush": {"display": "Ambush", "cost": 30, "resource_type": "energy"},
		"vanish": {"display": "Vanish", "cost": 40, "resource_type": "energy"},
		"exploit": {"display": "Exploit", "cost": 35, "resource_type": "energy"},
		"perfect_heist": {"display": "Heist", "cost": 50, "resource_type": "energy"},
		"sabotage": {"display": "Sabotage", "cost": 25, "resource_type": "energy"},
		"gambit": {"display": "Gambit", "cost": 35, "resource_type": "energy"},
		# Universal abilities
		"cloak": {"display": "Cloak", "cost": 30, "resource_type": resource_type},
	}

	return ability_defs.get(ability_name, {})

func show_combat_item_menu():
	"""Display usable items for combat selection."""
	combat_item_mode = true

	var inventory = character_data.get("inventory", [])
	var usable_items = []

	for i in range(inventory.size()):
		var item = inventory[i]
		var item_type = item.get("type", "")
		# Include all consumable types: potions, elixirs, gold pouches, gems, scrolls, resource potions
		if "potion" in item_type or "elixir" in item_type or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("scroll_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_"):
			usable_items.append({"index": i, "item": item})

	if usable_items.is_empty():
		display_game("[color=#FF0000]You have no usable items![/color]")
		combat_item_mode = false
		update_action_bar()
		return

	combat_use_page = 0  # Reset to first page
	set_meta("combat_usable_items", usable_items)
	_display_combat_usable_items_page()
	update_action_bar()

func _display_combat_usable_items_page():
	"""Display current page of combat usable items"""
	var usable_items = get_meta("combat_usable_items", [])

	var total_pages = int(ceil(float(usable_items.size()) / INVENTORY_PAGE_SIZE))
	var start_idx = combat_use_page * INVENTORY_PAGE_SIZE
	var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, usable_items.size())

	if total_pages > 1:
		display_game("[color=#FFD700]===== USABLE ITEMS (Page %d/%d) =====[/color]" % [combat_use_page + 1, total_pages])
	else:
		display_game("[color=#FFD700]===== USABLE ITEMS =====[/color]")

	for j in range(start_idx, end_idx):
		var entry = usable_items[j]
		var item = entry.item
		var item_name = item.get("name", "Unknown")
		var rarity = item.get("rarity", "common")
		var color = _get_rarity_color(rarity)
		var display_num = (j - start_idx) + 1
		display_game("[%d] [color=%s]%s[/color]" % [display_num, color, item_name])

	var items_on_page = end_idx - start_idx
	if total_pages > 1:
		display_game("[color=#808080]%s to use | Prev/Next Page to navigate[/color]" % get_selection_keys_text(items_on_page))
	else:
		display_game("[color=#808080]%s to use an item, or %s to cancel.[/color]" % [get_selection_keys_text(items_on_page), get_action_key_name(0)])

func cancel_combat_item_mode():
	"""Cancel combat item selection mode."""
	combat_item_mode = false
	update_action_bar()
	display_game("[color=#808080]Item use cancelled.[/color]")

func use_combat_item_by_number(number: int):
	"""Use a combat item by its display number (1-indexed, page-relative)."""
	var usable_items = get_meta("combat_usable_items", [])

	# Convert page-relative number to absolute index in filtered list
	var absolute_index = combat_use_page * INVENTORY_PAGE_SIZE + (number - 1)

	if absolute_index < 0 or absolute_index >= usable_items.size():
		display_game("[color=#FF0000]Invalid item number![/color]")
		return

	var actual_index = usable_items[absolute_index].index
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
		"inventory_inspect_equipped":
			prompt_inventory_action("inspect_equipped")
		"inspect_equipped_switch":
			# Switch from backpack inspect to equipped items inspect
			prompt_inventory_action("inspect_equipped")
		"inventory_discard":
			prompt_inventory_action("discard")
		"inventory_cancel":
			cancel_inventory_action()
		"confirm_equip":
			confirm_equip_item()
		"cancel_equip_confirm":
			cancel_equip_confirmation()
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
		"equip_prev_page":
			if equip_page > 0:
				equip_page -= 1
				_display_equippable_items_page()
				update_action_bar()
		"equip_next_page":
			var equippable_items = get_meta("equippable_items", [])
			var total_pages = max(1, int(ceil(float(equippable_items.size()) / INVENTORY_PAGE_SIZE)))
			if equip_page < total_pages - 1:
				equip_page += 1
				_display_equippable_items_page()
				update_action_bar()
		"use_prev_page":
			if use_page > 0:
				use_page -= 1
				_display_usable_items_page()
				update_action_bar()
		"use_next_page":
			var usable_items = get_meta("usable_items", [])
			var total_pages = max(1, int(ceil(float(usable_items.size()) / INVENTORY_PAGE_SIZE)))
			if use_page < total_pages - 1:
				use_page += 1
				_display_usable_items_page()
				update_action_bar()
		"combat_use_prev_page":
			if combat_use_page > 0:
				combat_use_page -= 1
				_display_combat_usable_items_page()
				update_action_bar()
		"combat_use_next_page":
			var combat_usable_items = get_meta("combat_usable_items", [])
			var total_pages = max(1, int(ceil(float(combat_usable_items.size()) / INVENTORY_PAGE_SIZE)))
			if combat_use_page < total_pages - 1:
				combat_use_page += 1
				_display_combat_usable_items_page()
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
		"sell_prev_page":
			if sell_page > 0:
				sell_page -= 1
				display_merchant_sell_list()
				update_action_bar()  # Refresh button states after page change
		"sell_next_page":
			var inventory = character_data.get("inventory", [])
			var total_pages = max(1, ceili(float(inventory.size()) / INVENTORY_PAGE_SIZE))
			if sell_page < total_pages - 1:
				sell_page += 1
				display_merchant_sell_list()
				update_action_bar()  # Refresh button states after page change
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
		# Wish selection actions
		"wish_select_0":
			select_wish(0)
		"wish_select_1":
			select_wish(1)
		"wish_select_2":
			select_wish(2)
		# Monster selection scroll actions
		"monster_select_cancel":
			cancel_monster_select()
		"monster_select_confirm":
			confirm_monster_select()
		"monster_select_back":
			cancel_monster_select()  # Goes back to list when in confirm mode
		"monster_select_prev":
			if monster_select_page > 0:
				monster_select_page -= 1
				display_monster_select_page()
		"monster_select_next":
			var total_pages = max(1, ceili(float(monster_select_list.size()) / MONSTER_SELECT_PAGE_SIZE))
			if monster_select_page < total_pages - 1:
				monster_select_page += 1
				display_monster_select_page()
		# Target farm scroll actions
		"target_farm_cancel":
			cancel_target_farm()
		# Ability management actions
		"abilities":
			enter_ability_mode()
		"ability_exit":
			exit_ability_mode()
		# Title system actions
		"title":
			open_title_menu()
		"title_exit":
			title_mode = false
			title_ability_mode = false
			title_target_mode = false
			title_broadcast_mode = false
			update_action_bar()
		"forge_crown":
			# Forge the Unforged Crown at the Infernal Forge
			send_to_server({"type": "forge_crown"})
			forge_available = false
			update_action_bar()
		"ability_equip":
			show_ability_equip_prompt()
		"ability_unequip":
			show_ability_unequip_prompt()
		"ability_keybinds":
			show_keybind_prompt()
		"ability_cancel":
			pending_ability_action = ""
			selected_ability_slot = -1
			display_ability_menu()
			update_action_bar()
		# Settings actions
		"settings_close":
			close_settings()
		"settings_action_keys":
			settings_submenu = "action_keys"
			game_output.clear()
			display_action_keybinds()
			update_action_bar()
		"settings_movement_keys":
			settings_submenu = "movement_keys"
			game_output.clear()
			display_movement_keybinds()
			update_action_bar()
		"settings_item_keys":
			settings_submenu = "item_keys"
			game_output.clear()
			display_item_keybinds()
			update_action_bar()
		"settings_reset":
			reset_keybinds_to_defaults()
		"settings_back_to_main":
			settings_submenu = ""
			game_output.clear()
			display_settings_menu()
			update_action_bar()
		"settings_rebind_move_up":
			start_rebinding("move_up")
			update_action_bar()
		"settings_rebind_move_down":
			start_rebinding("move_down")
			update_action_bar()
		"settings_rebind_move_left":
			start_rebinding("move_left")
			update_action_bar()
		"settings_rebind_move_right":
			start_rebinding("move_right")
			update_action_bar()

func select_wish(index: int):
	"""Send wish selection to server"""
	if not wish_selection_mode or index >= wish_options.size():
		return
	send_to_server({"type": "wish_select", "choice": index})
	wish_selection_mode = false
	display_game("[color=#808080]Making your wish...[/color]")

func acknowledge_continue():
	"""Clear pending continue state and allow game to proceed"""
	pending_continue = false
	# Reset quest log mode if active
	quest_log_mode = false
	quest_log_quests = []
	# Keep recent XP gain highlight visible until next XP gain
	game_output.clear()
	# Reset combat background when player continues (not during flock)
	if not flock_pending:
		reset_combat_background()

	# If at trading post, go back to quest menu so player can turn in more
	if at_trading_post:
		send_to_server({"type": "trading_post_quests"})
		return

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
			sell_page = 0  # Reset to first page
			display_merchant_sell_list()
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
			display_game("[color=#FFD700]Press [%s] to sell all, or type amount in chat:[/color]" % get_action_key_name(4))
			input_field.placeholder_text = "Gems to sell..."
			# Don't auto-focus input - user can press Q to sell all or click input to type amount
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

			# Build stats string using computed bonuses
			var stats_parts = []
			var bonuses = _compute_item_bonuses(item)
			if bonuses.get("attack", 0) > 0:
				stats_parts.append("[color=#FF6666]ATK %d[/color]" % bonuses.attack)
			if bonuses.get("defense", 0) > 0:
				stats_parts.append("[color=#66FFFF]DEF %d[/color]" % bonuses.defense)
			if bonuses.get("max_hp", 0) > 0:
				stats_parts.append("[color=#00FF00]+%d HP[/color]" % bonuses.max_hp)
			if bonuses.get("max_mana", 0) > 0:
				stats_parts.append("[color=#9999FF]+%d Mana[/color]" % bonuses.max_mana)
			if bonuses.get("strength", 0) > 0:
				stats_parts.append("+%d STR" % bonuses.strength)
			if bonuses.get("constitution", 0) > 0:
				stats_parts.append("+%d CON" % bonuses.constitution)
			if bonuses.get("dexterity", 0) > 0:
				stats_parts.append("+%d DEX" % bonuses.dexterity)
			if bonuses.get("intelligence", 0) > 0:
				stats_parts.append("+%d INT" % bonuses.intelligence)
			if bonuses.get("wisdom", 0) > 0:
				stats_parts.append("+%d WIS" % bonuses.wisdom)
			if bonuses.get("wits", 0) > 0:
				stats_parts.append("+%d WIT" % bonuses.wits)
			if bonuses.get("speed", 0) > 0:
				stats_parts.append("[color=#FFFF00]+%d SPD[/color]" % bonuses.speed)

			var stats_str = " | ".join(stats_parts) if stats_parts.size() > 0 else ""

			display_game("[%d] [color=%s]%s[/color] (Lv%d)%s - %d gold" % [i + 1, color, item.get("name", "Unknown"), level, compare_text, price])
			if stats_str != "":
				display_game("    %s" % stats_str)

	display_game("")
	display_game("[color=#808080]%s to buy with gold[/color]" % get_selection_keys_text(shop_items.size()))

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
				# Store affixes for client-side stat computation
				"affixes": item.get("affixes", {})
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
		display_game("[color=#808080][%s] Equip Now  |  [%s] Keep in Inventory[/color]" % [get_action_key_name(0), get_action_key_name(1)])
		update_action_bar()

func equip_bought_item():
	"""Equip the item that was just bought"""
	if bought_item_inventory_index < 0 or bought_item_pending_equip.is_empty():
		return

	send_to_server({"type": "inventory_equip", "index": bought_item_inventory_index})
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
		display_game("[color=#808080]Press [%s] to bet again (%d gold) or [%s] to stop.[/color]" % [get_action_key_name(0), last_gamble_bet, get_action_key_name(1)])
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

func select_merchant_sell_item(page_index: int):
	"""Sell item at page-relative index to merchant"""
	var inventory = character_data.get("inventory", [])

	# Convert page-relative index to absolute index
	var absolute_index = sell_page * INVENTORY_PAGE_SIZE + page_index

	if absolute_index < 0 or absolute_index >= inventory.size():
		display_game("[color=#FF0000]Invalid item number.[/color]")
		return

	# Keep in sell mode for quick multiple sales
	# pending_merchant_action stays as "sell"
	send_to_server({"type": "merchant_sell", "index": absolute_index})
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

	# Display all computed stats
	var stats_shown = _display_computed_item_bonuses(item)
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
	display_game("[color=#808080][%s] Buy  |  [%s] Back to list[/color]" % [get_action_key_name(0), get_action_key_name(1)])

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
		"speed": 0,
		# Class-specific bonuses
		"mana_regen": 0,      # Flat mana per combat round (Mage gear)
		"meditate_bonus": 0,  # % bonus to Meditate effectiveness (Mage gear)
		"energy_regen": 0,    # Flat energy per combat round (Trickster gear)
		"flee_bonus": 0,      # % bonus to flee chance (Trickster gear)
		"stamina_regen": 0    # Flat stamina per combat round (Warrior gear)
	}

	var item_level = item.get("level", 1)
	var item_type = item.get("type", "")
	var rarity_mult = _get_rarity_multiplier_for_status(item.get("rarity", "common"))

	# Check for item wear/damage (0-100, 100 = fully damaged/broken)
	var wear = item.get("wear", 0)
	var wear_penalty = 1.0 - (float(wear) / 100.0)  # 0% wear = 100% effectiveness

	# Base bonus scales with item level, rarity, and wear
	var base_bonus = int(item_level * rarity_mult * wear_penalty)

	# Check class-specific gear FIRST (before generic types)
	if "ring_arcane" in item_type:
		# Arcane ring (Mage): INT + mana_regen
		bonuses.intelligence += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		bonuses.mana_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
	elif "ring_shadow" in item_type:
		# Shadow ring (Trickster): WITS + energy_regen
		bonuses.wits += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		bonuses.energy_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
	elif "amulet_mystic" in item_type:
		# Mystic amulet (Mage): max_mana + meditate_bonus
		bonuses.max_mana += base_bonus * 3
		bonuses.meditate_bonus += max(1, int(item_level / 2)) if item_level > 0 else 0
	elif "amulet_evasion" in item_type:
		# Evasion amulet (Trickster): speed + flee_bonus
		bonuses.speed += base_bonus
		bonuses.flee_bonus += max(1, int(item_level / 3)) if item_level > 0 else 0
	elif "boots_swift" in item_type:
		# Swift boots (Trickster): Speed + WITS + energy_regen
		bonuses.speed += int(base_bonus * 1.5)
		bonuses.wits += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		bonuses.energy_regen += max(1, int(base_bonus * 0.1)) if base_bonus > 0 else 0
	elif "weapon_warlord" in item_type:
		# Warlord weapon (Warrior): ATK + stamina_regen
		bonuses.attack += base_bonus * 3
		bonuses.strength += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		bonuses.stamina_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
	elif "shield_bulwark" in item_type:
		# Bulwark shield (Warrior): DEF + HP + stamina_regen
		bonuses.defense += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		bonuses.max_hp += base_bonus * 5
		bonuses.constitution += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		bonuses.stamina_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
	# Generic item types (if not class-specific)
	elif "weapon" in item_type:
		bonuses.attack += base_bonus * 3  # Weapons are THE attack item
		bonuses.strength += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
	elif "armor" in item_type:
		bonuses.defense += base_bonus * 2
		bonuses.constitution += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		bonuses.max_hp += base_bonus * 3
	elif "helm" in item_type:
		bonuses.defense += base_bonus
		bonuses.wisdom += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
	elif "shield" in item_type:
		bonuses.defense += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		bonuses.max_hp += base_bonus * 5  # Shields are THE HP item
		bonuses.constitution += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
	elif "ring" in item_type:
		bonuses.attack += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		bonuses.dexterity += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		bonuses.intelligence += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
	elif "amulet" in item_type:
		bonuses.max_mana += base_bonus * 2
		bonuses.wisdom += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		bonuses.wits += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
	elif "boots" in item_type:
		bonuses.speed += base_bonus
		bonuses.dexterity += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		bonuses.defense += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0

	# Apply affix bonuses (also affected by wear)
	var affixes = item.get("affixes", {})
	if affixes.has("hp_bonus"):
		bonuses.max_hp += int(affixes.hp_bonus * wear_penalty)
	if affixes.has("attack_bonus"):
		bonuses.attack += int(affixes.attack_bonus * wear_penalty)
	if affixes.has("defense_bonus"):
		bonuses.defense += int(affixes.defense_bonus * wear_penalty)
	if affixes.has("str_bonus"):
		bonuses.strength += int(affixes.str_bonus * wear_penalty)
	if affixes.has("con_bonus"):
		bonuses.constitution += int(affixes.con_bonus * wear_penalty)
	if affixes.has("dex_bonus"):
		bonuses.dexterity += int(affixes.dex_bonus * wear_penalty)
	if affixes.has("int_bonus"):
		bonuses.intelligence += int(affixes.int_bonus * wear_penalty)
	if affixes.has("wis_bonus"):
		bonuses.wisdom += int(affixes.wis_bonus * wear_penalty)
	if affixes.has("wits_bonus"):
		bonuses.wits += int(affixes.wits_bonus * wear_penalty)

	return bonuses

func _display_computed_item_bonuses(item: Dictionary) -> bool:
	"""Display all computed bonuses for an item. Returns true if any bonuses were shown."""
	var bonuses = _compute_item_bonuses(item)
	var stats_shown = false

	if bonuses.get("attack", 0) > 0:
		display_game("[color=#FF6666]+%d Attack[/color]" % bonuses.attack)
		stats_shown = true
	if bonuses.get("defense", 0) > 0:
		display_game("[color=#66FFFF]+%d Defense[/color]" % bonuses.defense)
		stats_shown = true
	if bonuses.get("max_hp", 0) > 0:
		display_game("[color=#00FF00]+%d Max HP[/color]" % bonuses.max_hp)
		stats_shown = true
	if bonuses.get("max_mana", 0) > 0:
		display_game("[color=#9999FF]+%d Max Mana[/color]" % bonuses.max_mana)
		stats_shown = true
	if bonuses.get("strength", 0) > 0:
		display_game("+%d Strength" % bonuses.strength)
		stats_shown = true
	if bonuses.get("constitution", 0) > 0:
		display_game("+%d Constitution" % bonuses.constitution)
		stats_shown = true
	if bonuses.get("dexterity", 0) > 0:
		display_game("+%d Dexterity" % bonuses.dexterity)
		stats_shown = true
	if bonuses.get("intelligence", 0) > 0:
		display_game("+%d Intelligence" % bonuses.intelligence)
		stats_shown = true
	if bonuses.get("wisdom", 0) > 0:
		display_game("+%d Wisdom" % bonuses.wisdom)
		stats_shown = true
	if bonuses.get("wits", 0) > 0:
		display_game("+%d Wits" % bonuses.wits)
		stats_shown = true
	if bonuses.get("speed", 0) > 0:
		display_game("[color=#FFFF00]+%d Speed[/color]" % bonuses.speed)
		stats_shown = true

	# Class-specific bonuses
	if bonuses.get("mana_regen", 0) > 0:
		display_game("[color=#66CCFF]+%d Mana/round[/color] [color=#808080](Mage)[/color]" % bonuses.mana_regen)
		stats_shown = true
	if bonuses.get("meditate_bonus", 0) > 0:
		display_game("[color=#66CCFF]+%d%% Meditate[/color] [color=#808080](Mage)[/color]" % bonuses.meditate_bonus)
		stats_shown = true
	if bonuses.get("energy_regen", 0) > 0:
		display_game("[color=#66FF66]+%d Energy/round[/color] [color=#808080](Trickster)[/color]" % bonuses.energy_regen)
		stats_shown = true
	if bonuses.get("flee_bonus", 0) > 0:
		display_game("[color=#66FF66]+%d%% Flee[/color] [color=#808080](Trickster)[/color]" % bonuses.flee_bonus)
		stats_shown = true
	if bonuses.get("stamina_regen", 0) > 0:
		display_game("[color=#FFCC00]+%d Stamina/round[/color] [color=#808080](Warrior)[/color]" % bonuses.stamina_regen)
		stats_shown = true

	return stats_shown

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
		"speed": "SPD",
		# Class-specific bonuses
		"mana_regen": "Mana/rnd",
		"meditate_bonus": "Meditate%",
		"energy_regen": "Energy/rnd",
		"flee_bonus": "Flee%",
		"stamina_regen": "Stam/rnd"
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
		# Items have same stats - show what both provide for clarity
		var shared_stats = []
		for stat in stat_labels.keys():
			var val = new_bonuses.get(stat, 0)
			if val > 0:
				shared_stats.append("+%d %s" % [val, stat_labels[stat]])
		if shared_stats.size() > 0:
			display_game("  [color=#808080](Same stats: %s)[/color]" % " | ".join(shared_stats))
		else:
			display_game("  [color=#808080](No stat bonuses)[/color]")

	# Compare effects using computed effect descriptions
	var new_type = new_item.get("type", "")
	var old_type = old_item.get("type", "")
	var new_effect = _get_item_effect_description(new_type, new_item.get("level", 1), new_item.get("rarity", "common"))
	var old_effect = _get_item_effect_description(old_type, old_item.get("level", 1), old_item.get("rarity", "common"))

	# Always show effect comparison so users can see what items do
	if new_effect != old_effect:
		display_game("  [color=#FF6666]Current:[/color] %s" % old_effect)
		display_game("  [color=#00FF00]New:[/color] %s" % new_effect)
	elif new_effect != "" and new_effect != "Unknown effect":
		display_game("  [color=#808080]Effect:[/color] %s" % new_effect)

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
		display_game("[%s] Sell items" % get_action_key_name(1))
	if "upgrade" in services:
		display_game("[%s] Upgrade equipment" % get_action_key_name(2))
	if "gamble" in services:
		display_game("[%s] Gamble" % get_action_key_name(3))
	if shop_items.size() > 0:
		display_game("[%s] Buy items (%d available)" % [get_action_key_name(4), shop_items.size()])
	if gems > 0:
		display_game("[%s] Sell gems (%d @ 1000g each)" % [get_action_key_name(5), gems])
	display_game("[%s] Leave" % get_action_key_name(0))

func display_merchant_sell_list():
	"""Display items available for sale with pagination"""
	var inventory = character_data.get("inventory", [])
	var total_items = inventory.size()
	var total_pages = max(1, ceili(float(total_items) / INVENTORY_PAGE_SIZE))
	sell_page = clamp(sell_page, 0, total_pages - 1)

	display_game("[color=#FFD700]===== SELL ITEMS =====[/color]")
	display_game("Your gold: %d" % character_data.get("gold", 0))
	if total_pages > 1:
		display_game("[color=#808080]Page %d/%d (%d items)[/color]" % [sell_page + 1, total_pages, total_items])
	display_game("")

	if inventory.is_empty():
		display_game("[color=#555555](no items to sell)[/color]")
	else:
		var start_idx = sell_page * INVENTORY_PAGE_SIZE
		var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, total_items)
		for i in range(start_idx, end_idx):
			var item = inventory[i]
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var sell_price = item.get("value", 10) / 2
			var key_index = i - start_idx  # 0-8 for key lookup
			var key_name = get_item_select_key_name(key_index)
			display_game("[%s] [color=%s]%s[/color] - [color=#FFD700]%d gold[/color]" % [
				key_name, rarity_color, item.get("name", "Unknown"), sell_price
			])
		if total_pages > 1:
			display_game("")
			display_game("[color=#808080][%s] Prev Page  [%s] Next Page[/color]" % [get_action_key_name(1), get_action_key_name(2)])

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
	set_inventory_background("base")
	update_action_bar()
	display_inventory()

func close_inventory():
	"""Close inventory view and return to normal mode"""
	inventory_mode = false
	pending_inventory_action = ""
	selected_item_index = -1
	reset_combat_background()  # Reset to default black background
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

			# Check if consumable (show quantity) vs equipment (show level)
			var is_consumable = item.get("is_consumable", false)
			if is_consumable:
				var quantity = item.get("quantity", 1)
				var qty_text = " x%d" % quantity if quantity > 1 else ""
				display_game("  %d. [color=%s]%s[/color]%s" % [
					display_num, rarity_color, item.get("name", "Unknown"), qty_text
				])
			else:
				display_game("  %d. [color=%s]%s[/color] (Lv%d) %s" % [
					display_num, rarity_color, item.get("name", "Unknown"), item_level, compare_text
				])

	display_game("")
	display_game("[color=#808080]%s=Inspect, %s=Use, %s=Equip, %s=Unequip, %s=Discard, %s=Back[/color]" % [
		get_action_key_name(1), get_action_key_name(2), get_action_key_name(3),
		get_action_key_name(4), get_action_key_name(5), get_action_key_name(0)])
	if _count_equipped_items(equipped) > 0:
		display_game("[color=#808080]%s=Inspect Equipped[/color]" % get_action_key_name(8))
	if total_pages > 1:
		display_game("[color=#808080]%s=Prev Page, %s=Next Page[/color]" % [get_action_key_name(1), get_action_key_name(2)])

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
			set_inventory_background("inspect")
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]%s to inspect an item, or type slot name (weapon, armor, etc.):[/color]" % get_selection_keys_text(max(1, inventory.size())))
			update_action_bar()  # Show cancel option

		"use":
			# Filter for usable items only (all consumables)
			var usable_items = []
			for i in range(inventory.size()):
				var item = inventory[i]
				var item_type = item.get("type", "")
				# Include all consumable types: potions, elixirs, gold pouches, gems, scrolls, resource potions
				if "potion" in item_type or "elixir" in item_type or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("scroll_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_"):
					usable_items.append({"index": i, "item": item})
			if usable_items.is_empty():
				display_game("[color=#FF0000]No usable items in inventory.[/color]")
				return
			pending_inventory_action = "use_item"
			set_inventory_background("use")
			use_page = 0  # Reset to first page
			set_meta("usable_items", usable_items)
			_display_usable_items_page()
			update_action_bar()

		"equip":
			# Filter for equippable items only (exclude all consumables)
			var equippable_items = []
			for i in range(inventory.size()):
				var item = inventory[i]
				var item_type = item.get("type", "")
				# Equippable items have types like: weapon_*, armor_*, helm_*, shield_*, boots_*, ring_*, amulet_*
				# Consumables have types like: potion_*, elixir_*, scroll_*, gold_*, gem_*, mana_*, stamina_*, energy_*
				var is_consumable = "potion" in item_type or "elixir" in item_type or "scroll" in item_type or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_")
				if not is_consumable:
					equippable_items.append({"index": i, "item": item})
			if equippable_items.is_empty():
				display_game("[color=#FF0000]No equippable items in inventory.[/color]")
				return
			pending_inventory_action = "equip_item"
			set_inventory_background("equip")
			equip_page = 0  # Reset to first page
			set_meta("equippable_items", equippable_items)
			_display_equippable_items_page()
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
			set_inventory_background("unequip")
			# Display equipped items with numbers
			display_game("[color=#FFD700]===== UNEQUIP ITEM =====[/color]")
			for i in range(slots_with_items.size()):
				var slot = slots_with_items[i]
				var item = equipped.get(slot)
				var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
				display_game("%d. [color=#AAAAAA]%s:[/color] [color=%s]%s[/color]" % [i + 1, slot.capitalize(), rarity_color, item.get("name", "Unknown")])
			display_game("")
			display_game("[color=#FFD700]%s to unequip an item:[/color]" % get_selection_keys_text(slots_with_items.size()))
			# Store slots for number key selection
			set_meta("unequip_slots", slots_with_items)
			update_action_bar()

		"inspect_equipped":
			var slots_with_items = []
			for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
				if equipped.get(slot) != null:
					slots_with_items.append(slot)
			if slots_with_items.is_empty():
				display_game("[color=#FF0000]No items equipped.[/color]")
				return
			pending_inventory_action = "inspect_equipped_item"
			set_inventory_background("inspect")
			# Display equipped items with numbers
			display_game("[color=#FFD700]===== INSPECT EQUIPPED =====[/color]")
			for i in range(slots_with_items.size()):
				var slot = slots_with_items[i]
				var item = equipped.get(slot)
				var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
				display_game("%d. [color=#AAAAAA]%s:[/color] [color=%s]%s[/color]" % [i + 1, slot.capitalize(), rarity_color, item.get("name", "Unknown")])
			display_game("")
			display_game("[color=#FFD700]%s to inspect an equipped item:[/color]" % get_selection_keys_text(slots_with_items.size()))
			# Store slots for number key selection
			set_meta("inspect_equipped_slots", slots_with_items)
			update_action_bar()

		"discard":
			if inventory.is_empty():
				display_game("[color=#FF0000]No items to discard.[/color]")
				return
			pending_inventory_action = "discard_item"
			set_inventory_background("discard")
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]%s to discard an item:[/color]" % get_selection_keys_text(inventory.size()))
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
	display_game("[color=#FFD700]%s to unequip another item, or [%s] to go back:[/color]" % [get_selection_keys_text(slots_with_items.size()), get_action_key_name(0)])
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

# ===== ABILITY MANAGEMENT UI =====

func enter_ability_mode():
	"""Enter ability management mode"""
	ability_mode = true
	pending_ability_action = ""
	selected_ability_slot = -1
	# Request ability data from server
	send_to_server({"type": "get_abilities"})
	update_action_bar()

func exit_ability_mode():
	"""Exit ability management mode"""
	ability_mode = false
	pending_ability_action = ""
	selected_ability_slot = -1
	ability_data.clear()
	display_game("[color=#808080]Exited ability management.[/color]")
	update_action_bar()

func display_ability_menu():
	"""Display the ability loadout management screen"""
	if not ability_mode or ability_data.is_empty():
		return

	game_output.clear()
	display_game("[color=#FFD700]===== ABILITY LOADOUT =====[/color]")
	display_game("")

	var equipped = ability_data.get("equipped_abilities", [])
	var keybinds = ability_data.get("ability_keybinds", {})
	var unlocked = ability_data.get("unlocked_abilities", [])
	var all_abilities = ability_data.get("all_abilities", [])

	# Show currently equipped abilities in 4 slots
	display_game("[color=#00FFFF]Combat Slots:[/color]")
	for i in range(4):
		var ability_name = equipped[i] if i < equipped.size() else ""
		var keybind = keybinds.get(str(i), keybinds.get(i, "?"))
		if ability_name != "" and ability_name != null:
			var ability_info = _get_ability_info_from_list(ability_name, all_abilities)
			var display_name = ability_info.get("display", ability_name.capitalize().replace("_", " "))
			var cost_text = _get_ability_cost_text(ability_name)
			display_game("  [%s] Slot %d: [color=#00FF00]%s[/color] %s" % [keybind, i + 1, display_name, cost_text])
		else:
			display_game("  [%s] Slot %d: [color=#555555](empty)[/color]" % [keybind, i + 1])

	display_game("")

	# Show available abilities
	display_game("[color=#00FFFF]Available Abilities:[/color]")
	var player_level = character_data.get("level", 1)
	for ability in all_abilities:
		var name = ability.get("name", "")
		var display_name = ability.get("display", name.capitalize())
		var req_level = ability.get("level", 1)
		var is_unlocked = player_level >= req_level
		var is_equipped = name in equipped

		if is_unlocked:
			var status = "[color=#00FF00]EQUIPPED[/color]" if is_equipped else ""
			var cost_text = _get_ability_cost_text(name)
			display_game("  [color=#FFFFFF]%s[/color] %s %s" % [display_name, cost_text, status])
		else:
			display_game("  [color=#555555]%s (Lv %d)[/color]" % [display_name, req_level])

	display_game("")
	display_game("[color=#FFD700]How to use:[/color]")
	display_game("  1. Press [%s] Equip to add abilities to combat slots" % get_action_key_name(1))
	display_game("  2. Select a slot (1-4), then select an ability from the list")
	display_game("  3. Press [%s] Keybinds to change slot hotkeys" % get_action_key_name(3))
	display_game("")
	display_game("[color=#808080][%s]=Back  [%s]=Equip  [%s]=Unequip  [%s]=Keybinds[/color]" % [
		get_action_key_name(0), get_action_key_name(1), get_action_key_name(2), get_action_key_name(3)])

func _get_ability_info_from_list(ability_name: String, ability_list: Array) -> Dictionary:
	"""Find ability info from the ability list"""
	for ability in ability_list:
		if ability.get("name", "") == ability_name:
			return ability
	return {}

func _get_ability_cost_text(ability_name: String) -> String:
	"""Get cost text for an ability"""
	var path = _get_player_active_path()
	var resource_type = "mana" if path == "mage" else ("stamina" if path == "warrior" else "energy")
	var resource_color = "#66CCFF" if path == "mage" else ("#FFCC66" if path == "warrior" else "#66FF66")

	# Get cost from ability info
	var cost = 0
	match ability_name:
		# Mage abilities
		"magic_bolt": cost = 0  # Variable
		"shield": cost = 20
		"blast": cost = 50
		"forcefield": cost = 75
		"teleport": cost = 40
		"meteor": cost = 100
		"haste": cost = 35
		"paralyze": cost = 60
		"banish": cost = 80
		# Warrior abilities
		"power_strike": cost = 10
		"war_cry": cost = 15
		"shield_bash": cost = 20
		"cleave": cost = 30
		"berserk": cost = 40
		"iron_skin": cost = 35
		"devastate": cost = 60
		"fortify": cost = 25
		"rally": cost = 45
		# Trickster abilities
		"analyze": cost = 5
		"distract": cost = 15
		"pickpocket": cost = 20
		"ambush": cost = 30
		"vanish": cost = 40
		"exploit": cost = 35
		"perfect_heist": cost = 50
		"sabotage": cost = 25
		"gambit": cost = 35
		# Universal
		"cloak": cost = 0  # % based

	if ability_name == "magic_bolt":
		return "[color=%s](variable mana)[/color]" % resource_color
	elif ability_name == "cloak":
		return "[color=#9932CC](8%% per move)[/color]"
	elif cost > 0:
		return "[color=%s](%d %s)[/color]" % [resource_color, cost, resource_type.substr(0, 3)]
	return ""

func show_ability_equip_prompt():
	"""Show prompt to select an ability to equip"""
	pending_ability_action = "select_ability"
	display_game("")
	display_game("[color=#FFD700]Select slot (1-4) to equip to:[/color]")
	update_action_bar()

func show_ability_unequip_prompt():
	"""Show prompt to select slot to unequip"""
	pending_ability_action = "select_unequip_slot"
	display_game("")
	display_game("[color=#FFD700]Select slot (1-4) to unequip:[/color]")
	update_action_bar()

func show_keybind_prompt():
	"""Show prompt to change keybinds"""
	pending_ability_action = "select_keybind_slot"
	display_game("")
	display_game("[color=#FFD700]Select slot (1-4) to change keybind:[/color]")
	update_action_bar()

func handle_ability_slot_selection(slot_num: int):
	"""Handle when a slot number is selected in ability mode"""
	if slot_num < 1 or slot_num > 4:
		display_game("[color=#FF0000]Invalid slot. Use 1-4.[/color]")
		return

	var slot_index = slot_num - 1

	match pending_ability_action:
		"select_ability":
			# Show list of abilities to choose from
			selected_ability_slot = slot_index
			pending_ability_action = "choose_ability"
			display_game("")
			display_game("[color=#FFD700]Select ability for slot %d:[/color]" % slot_num)
			var unlocked = ability_data.get("unlocked_abilities", [])
			for i in range(unlocked.size()):
				var ability = unlocked[i]
				var display_name = ability.get("display", ability.name.capitalize())
				display_game("  %d. %s" % [i + 1, display_name])
			display_game("[color=#808080]Press 1-%d to select, %s to cancel[/color]" % [unlocked.size(), get_action_key_name(0)])
			update_action_bar()

		"select_unequip_slot":
			send_to_server({"type": "unequip_ability", "slot": slot_index})
			pending_ability_action = ""

		"select_keybind_slot":
			selected_ability_slot = slot_index
			pending_ability_action = "press_keybind"
			display_game("")
			display_game("[color=#FFD700]Press a key for slot %d (Q/W/E/R or any letter):[/color]" % slot_num)
			update_action_bar()

func handle_ability_choice(choice_num: int):
	"""Handle when an ability is chosen from the list"""
	var unlocked = ability_data.get("unlocked_abilities", [])
	if choice_num < 1 or choice_num > unlocked.size():
		display_game("[color=#FF0000]Invalid choice.[/color]")
		return

	var ability = unlocked[choice_num - 1]
	send_to_server({"type": "equip_ability", "slot": selected_ability_slot, "ability": ability.name})
	pending_ability_action = ""
	selected_ability_slot = -1

func handle_keybind_press(key: String):
	"""Handle a keybind press when setting keybind"""
	if key.length() != 1 or not key.is_valid_identifier():
		display_game("[color=#FF0000]Invalid key. Use a single letter.[/color]")
		return

	send_to_server({"type": "set_ability_keybind", "slot": selected_ability_slot, "key": key})
	pending_ability_action = ""
	selected_ability_slot = -1

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

	# Special handling for inspect equipped - uses slot list instead of inventory
	if action == "inspect_equipped_item":
		var slots = get_meta("inspect_equipped_slots", [])
		var equipped = character_data.get("equipped", {})
		if index < 0 or index >= slots.size():
			display_game("[color=#FF0000]Invalid slot number.[/color]")
			return
		var slot = slots[index]
		var item = equipped.get(slot)
		if item != null:
			display_item_details(item, "equipped in %s slot" % slot)
		# Stay in inspect equipped mode
		display_game("")
		display_game("[color=#FFD700]%s to inspect another equipped item, or [%s] to go back:[/color]" % [get_selection_keys_text(slots.size()), get_action_key_name(0)])
		update_action_bar()
		return

	# Special handling for use_item - uses filtered usable_items list
	if action == "use_item":
		var usable_items = get_meta("usable_items", [])
		if index < 0 or index >= usable_items.size():
			display_game("[color=#FF0000]Invalid item number.[/color]")
			return
		var actual_index = usable_items[index].index
		awaiting_item_use_result = true
		send_to_server({"type": "inventory_use", "index": actual_index})
		update_action_bar()
		return

	# Special handling for equip_item - uses filtered equippable_items list
	if action == "equip_item":
		var equippable_items = get_meta("equippable_items", [])
		if index < 0 or index >= equippable_items.size():
			display_game("[color=#FF0000]Invalid item number.[/color]")
			return
		var actual_index = equippable_items[index].index
		var item = inventory[actual_index]
		selected_item_index = actual_index
		pending_inventory_action = "equip_confirm"
		game_output.clear()
		display_equip_comparison(item, actual_index)
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
			display_game("[color=#FFD700]%s to inspect another item, or [%s] to go back:[/color]" % [get_selection_keys_text(max(1, items_on_page)), get_action_key_name(0)])
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
	selected_item_index = -1
	inventory_mode = false
	update_action_bar()

func cancel_inventory_action():
	"""Cancel pending inventory action"""
	if pending_inventory_action != "":
		pending_inventory_action = ""
		selected_item_index = -1
		set_inventory_background("base")  # Reset to base inventory background
		display_game("[color=#808080]Action cancelled.[/color]")
		display_inventory()  # Re-show inventory
		update_action_bar()

func confirm_equip_item():
	"""Confirm equipping the selected item"""
	if selected_item_index < 0:
		display_game("[color=#FF0000]No item selected.[/color]")
		pending_inventory_action = ""
		display_inventory()
		update_action_bar()
		return

	send_to_server({"type": "inventory_equip", "index": selected_item_index})
	selected_item_index = -1
	pending_inventory_action = ""
	set_inventory_background("base")
	# The character_update will refresh and re-show inventory
	update_action_bar()

func _display_equippable_items_page():
	"""Display current page of equippable items with stats and comparison"""
	var equippable_items = get_meta("equippable_items", [])
	var equipped = character_data.get("equipped", {})

	var total_pages = int(ceil(float(equippable_items.size()) / INVENTORY_PAGE_SIZE))
	var start_idx = equip_page * INVENTORY_PAGE_SIZE
	var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, equippable_items.size())

	game_output.clear()
	if total_pages > 1:
		display_game("[color=#FFD700]===== EQUIPPABLE ITEMS (Page %d/%d) =====[/color]" % [equip_page + 1, total_pages])
	else:
		display_game("[color=#FFD700]===== EQUIPPABLE ITEMS =====[/color]")

	for j in range(start_idx, end_idx):
		var entry = equippable_items[j]
		var item = entry.item
		var item_name = item.get("name", "Unknown")
		var item_type = item.get("type", "")
		var rarity = item.get("rarity", "common")
		var level = item.get("level", 1)
		var color = _get_rarity_color(rarity)

		# Build stats string
		var stats_parts = []
		var bonuses = _compute_item_bonuses(item)
		if bonuses.get("attack", 0) > 0:
			stats_parts.append("[color=#FF6666]ATK %d[/color]" % bonuses.attack)
		if bonuses.get("defense", 0) > 0:
			stats_parts.append("[color=#66FFFF]DEF %d[/color]" % bonuses.defense)
		if bonuses.get("max_hp", 0) > 0:
			stats_parts.append("[color=#00FF00]+%d HP[/color]" % bonuses.max_hp)
		if bonuses.get("max_mana", 0) > 0:
			stats_parts.append("[color=#9999FF]+%d MP[/color]" % bonuses.max_mana)
		var stats_str = " ".join(stats_parts) if stats_parts.size() > 0 else ""

		# Comparison with equipped item
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

		# Display number is 1-9 for current page
		var display_num = (j - start_idx) + 1

		# Display item with stats
		if stats_str != "":
			display_game("[%d] [color=%s]%s[/color] (Lv%d)%s - %s" % [display_num, color, item_name, level, compare_text, stats_str])
		else:
			display_game("[%d] [color=%s]%s[/color] (Lv%d)%s" % [display_num, color, item_name, level, compare_text])

	var items_on_page = end_idx - start_idx
	if total_pages > 1:
		display_game("[color=#808080]%s to equip | Prev/Next Page to navigate[/color]" % get_selection_keys_text(items_on_page))
	else:
		display_game("[color=#808080]%s to equip an item:[/color]" % get_selection_keys_text(items_on_page))

func _display_usable_items_page():
	"""Display current page of usable items"""
	var usable_items = get_meta("usable_items", [])

	var total_pages = int(ceil(float(usable_items.size()) / INVENTORY_PAGE_SIZE))
	var start_idx = use_page * INVENTORY_PAGE_SIZE
	var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, usable_items.size())

	game_output.clear()
	if total_pages > 1:
		display_game("[color=#FFD700]===== USABLE ITEMS (Page %d/%d) =====[/color]" % [use_page + 1, total_pages])
	else:
		display_game("[color=#FFD700]===== USABLE ITEMS =====[/color]")

	for j in range(start_idx, end_idx):
		var entry = usable_items[j]
		var item = entry.item
		var item_name = item.get("name", "Unknown")
		var rarity = item.get("rarity", "common")
		var color = _get_rarity_color(rarity)
		var display_num = (j - start_idx) + 1
		display_game("[%d] [color=%s]%s[/color]" % [display_num, color, item_name])

	var items_on_page = end_idx - start_idx
	if total_pages > 1:
		display_game("[color=#808080]%s to use | Prev/Next Page to navigate[/color]" % get_selection_keys_text(items_on_page))
	else:
		display_game("[color=#808080]%s to use an item:[/color]" % get_selection_keys_text(items_on_page))

func cancel_equip_confirmation():
	"""Cancel equip confirmation and return to equip item selection"""
	selected_item_index = -1
	pending_inventory_action = "equip_item"
	set_inventory_background("equip")
	_display_equippable_items_page()
	update_action_bar()

func _reprompt_inventory_action():
	"""Re-display the prompt for current pending inventory action after page change"""
	var inv = character_data.get("inventory", [])
	var start_idx = inventory_page * INVENTORY_PAGE_SIZE
	var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, inv.size())
	var items_on_page = end_idx - start_idx

	match pending_inventory_action:
		"inspect_item":
			display_game("[color=#FFD700]%s to inspect an item:[/color]" % get_selection_keys_text(items_on_page))
		"use_item":
			display_game("[color=#FFD700]%s to use an item:[/color]" % get_selection_keys_text(items_on_page))
		"equip_item":
			display_game("[color=#FFD700]%s to equip an item:[/color]" % get_selection_keys_text(items_on_page))
		"discard_item":
			display_game("[color=#FFD700]%s to discard an item:[/color]" % get_selection_keys_text(items_on_page))

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

# Inventory mode background colors
const INVENTORY_BG_COLORS = {
	"base": "#1A1208",      # Dark brown - base inventory
	"equip": "#0D1A0D",     # Dark green tint - equip mode
	"unequip": "#1A0D0D",   # Dark red tint - unequip mode
	"inspect": "#0D0D1A",   # Dark blue tint - inspect mode
	"use": "#1A1A0D",       # Dark yellow tint - use mode
	"discard": "#1A0808",   # Darker red - discard mode
}

func set_inventory_background(mode: String = "base"):
	"""Set the GameOutput background to an inventory-themed color"""
	if not game_output:
		return

	var hex_color = INVENTORY_BG_COLORS.get(mode, INVENTORY_BG_COLORS.base)
	var color = Color(hex_color)
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = color
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
	var max_hp = character_data.get("total_max_hp", character_data.get("max_hp", 1))  # Use equipment-boosted HP
	var percent = (float(current_hp) / float(max_hp)) * 100.0

	var fill = player_health_bar.get_node("Fill")
	var label = player_health_bar.get_node("HPLabel")

	if fill:
		fill.anchor_right = percent / 100.0
		var style = fill.get_theme_stylebox("panel").duplicate()
		style.bg_color = get_hp_color(percent)
		fill.add_theme_stylebox_override("panel", style)

	# Update shield/forcefield overlay
	_update_shield_bar(max_hp)

	if label:
		if current_forcefield > 0:
			label.text = "HP: %d/%d (+%d Shield)" % [current_hp, max_hp, current_forcefield]
		else:
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
		"crit_chance": return "#FFD700"  # Gold
		"lifesteal": return "#FF00FF"    # Magenta
		"thorns": return "#FF4444"       # Dark red
		"forcefield": return "#00FFFF"   # Cyan
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
		"crit_chance": return "C"  # Crit
		"lifesteal": return "L"    # Lifesteal
		"thorns": return "T"       # Thorns
		"forcefield": return "F"   # Forcefield
		"damage_penalty": return "A-"
		"defense_penalty": return "D-"
		_: return buff_type.substr(0, 1).to_upper()

func _update_shield_bar(max_hp: int):
	"""Update the purple shield/forcefield overlay on the HP bar"""
	if not player_health_bar:
		return

	# Create shield fill panel if it doesn't exist
	if shield_fill_panel == null:
		shield_fill_panel = Panel.new()
		shield_fill_panel.name = "ShieldFill"
		# Position it after Fill but before HPLabel
		var fill_node = player_health_bar.get_node_or_null("Fill")
		if fill_node:
			player_health_bar.add_child(shield_fill_panel)
			player_health_bar.move_child(shield_fill_panel, fill_node.get_index() + 1)
		else:
			player_health_bar.add_child(shield_fill_panel)

		# Set up anchors for dynamic sizing (same as Fill)
		shield_fill_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		shield_fill_panel.anchor_left = 0
		shield_fill_panel.anchor_top = 0
		shield_fill_panel.anchor_bottom = 1
		shield_fill_panel.offset_left = 0
		shield_fill_panel.offset_top = 0
		shield_fill_panel.offset_bottom = 0

		# Create purple style
		var shield_style = StyleBoxFlat.new()
		shield_style.bg_color = Color(0.6, 0.2, 0.8, 0.7)  # Purple, semi-transparent
		shield_fill_panel.add_theme_stylebox_override("panel", shield_style)

	# Update shield bar visibility and size
	if current_forcefield > 0 and max_hp > 0:
		shield_fill_panel.visible = true
		# Shield shows as percentage of max HP (can exceed 100% if shield > max_hp)
		var shield_percent = min(1.0, float(current_forcefield) / float(max_hp))
		shield_fill_panel.anchor_right = shield_percent
		shield_fill_panel.offset_right = 0
	else:
		shield_fill_panel.visible = false

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
		# Clamp old_percent to 0 minimum (can go negative after leveling up)
		var old_percent = max(0.0, float(old_xp) / float(max(xp_needed, 1)))
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

func update_enemy_hp_bar(enemy_name: String, enemy_level: int, damage_dealt: int, actual_hp: int = -1, actual_max_hp: int = -1):
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

	# Use actual HP values if provided (from server), otherwise estimate
	if actual_hp >= 0 and actual_max_hp > 0:
		# Actual HP values from server - always accurate
		var percent = (float(actual_hp) / float(actual_max_hp)) * 100.0
		if fill:
			fill.anchor_right = percent / 100.0
		if hp_label:
			hp_label.text = "%d/%d" % [actual_hp, actual_max_hp]
		# Store for future reference
		known_enemy_hp[enemy_key] = actual_max_hp
		return

	# Fallback to estimation (only used if server doesn't send HP)
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

func _get_base_monster_name(monster_name: String) -> String:
	"""Strip variant prefixes from monster name to get the base type.
	Used for tracking unique monster types discovered."""
	# Known variant prefixes (monster ability variants)
	var variant_prefixes = [
		"Corrosive ", "Shield Guardian ", "Weapon Master ", "Gem Bearer ",
		"Arcane Hoarder ", "Cunning Prey ", "Warrior Hoarder ", "Wish Granter ",
		"Gold Hoarder ", "Pack Leader ", "Alpha ", "Ancient ", "Elder ",
		"Young ", "Frenzied ", "Cursed ", "Ethereal ", "Armored ",
		"Venomous ", "Savage ", "Feral "
	]
	var result = monster_name
	for prefix in variant_prefixes:
		if result.begins_with(prefix):
			result = result.substr(prefix.length())
			break  # Only strip one prefix
	return result

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
			last_username = username
			_save_connection_settings()
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
			display_title_holders(message.get("title_holders", []))
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
			display_title_holders(message.get("title_holders", []))
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
			# A player entered the Hall of Heroes (top 5) - show in chat only
			var char_name = message.get("character_name", "Unknown")
			var level = message.get("level", 1)
			var hero_rank = message.get("rank", 1)
			display_chat("[color=#FFD700]*** %s (Level %d) has entered the Hall of Heroes at #%d! ***[/color]" % [char_name, level, hero_rank])
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

		"lucky_find":
			# Lucky find requires acknowledgment before moving again
			game_output.clear()
			var find_msg = message.get("message", "You found something!")
			display_game(find_msg)
			display_game("")
			display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
			# Update character data (gold/items were added)
			if message.has("character"):
				character_data = message.character
				update_player_level()
				update_player_hp_bar()
				update_resource_bar()
				update_player_xp_bar()
				update_currency_display()
			# Play item drop sound if an item was found
			var item = message.get("item")
			if item != null:
				var drop_value = _get_rarity_value(item.get("rarity", "common"))
				play_rare_drop_sound(drop_value)
			pending_continue = true
			update_action_bar()

		"special_encounter":
			# Special encounters (legendary adventurer, etc.) require acknowledgment
			game_output.clear()
			var encounter_msg = message.get("message", "Something special happened!")
			display_game(encounter_msg)
			display_game("")
			display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
			# Update character data (stats were modified)
			if message.has("character"):
				character_data = message.character
				update_player_level()
				update_player_hp_bar()
				update_resource_bar()
				update_player_xp_bar()
				update_currency_display()
			# Play a special sound for legendary encounters
			if levelup_player and levelup_player.stream:
				levelup_player.play()
			pending_continue = true
			update_action_bar()

		"character_update":
			if message.has("character"):
				character_data = message.character
				update_player_level()
				update_player_hp_bar()
				update_resource_bar()
				update_player_xp_bar()
				update_currency_display()
				# Reset forge_available if not at Fire Mountain (-400, 0)
				if forge_available:
					var px = character_data.get("x", 0)
					var py = character_data.get("y", 0)
					if px != -400 or py != 0:
						forge_available = false
				# Re-display inventory if in inventory mode (after use/equip/discard)
				if inventory_mode:
					# Handle pending equip/unequip actions
					if pending_inventory_action == "equip_item":
						# Regenerate filtered equippable items list
						var inv = character_data.get("inventory", [])
						var equipped = character_data.get("equipped", {})
						var equippable_items = []
						for ii in range(inv.size()):
							var itm = inv[ii]
							var itm_type = itm.get("type", "")
							var is_consumable = "potion" in itm_type or "elixir" in itm_type or "scroll" in itm_type or itm_type.begins_with("gold_") or itm_type.begins_with("gem_") or itm_type.begins_with("mana_") or itm_type.begins_with("stamina_") or itm_type.begins_with("energy_")
							if not is_consumable:
								equippable_items.append({"index": ii, "item": itm})
						set_meta("equippable_items", equippable_items)
						if equippable_items.size() > 0:
							game_output.clear()
							display_game("[color=#FFD700]===== EQUIPPABLE ITEMS =====[/color]")
							for j in range(equippable_items.size()):
								var entry = equippable_items[j]
								var item = entry.item
								var item_name = item.get("name", "Unknown")
								var item_type = item.get("type", "")
								var rarity = item.get("rarity", "common")
								var level = item.get("level", 1)
								var color = _get_rarity_color(rarity)

								# Build stats string
								var stats_parts = []
								var bonuses = _compute_item_bonuses(item)
								if bonuses.get("attack", 0) > 0:
									stats_parts.append("[color=#FF6666]ATK %d[/color]" % bonuses.attack)
								if bonuses.get("defense", 0) > 0:
									stats_parts.append("[color=#66FFFF]DEF %d[/color]" % bonuses.defense)
								if bonuses.get("max_hp", 0) > 0:
									stats_parts.append("[color=#00FF00]+%d HP[/color]" % bonuses.max_hp)
								if bonuses.get("max_mana", 0) > 0:
									stats_parts.append("[color=#9999FF]+%d MP[/color]" % bonuses.max_mana)
								var stats_str = " ".join(stats_parts) if stats_parts.size() > 0 else ""

								# Comparison with equipped item
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

								if stats_str != "":
									display_game("[%d] [color=%s]%s[/color] (Lv%d)%s - %s" % [j + 1, color, item_name, level, compare_text, stats_str])
								else:
									display_game("[%d] [color=%s]%s[/color] (Lv%d)%s" % [j + 1, color, item_name, level, compare_text])
							display_game("[color=#FFD700]%s to equip another item, or [%s] to go back:[/color]" % [get_selection_keys_text(equippable_items.size()), get_action_key_name(0)])
						else:
							display_game("[color=#808080]No more items to equip.[/color]")
							pending_inventory_action = ""
							update_action_bar()  # Update to show main inventory menu with Back option
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
						sell_page = 0
						show_merchant_menu()
					else:
						# Adjust page if we were on the last page and it's now empty
						var total_pages = max(1, ceili(float(inventory.size()) / INVENTORY_PAGE_SIZE))
						if sell_page >= total_pages:
							sell_page = total_pages - 1
						display_merchant_sell_list()
					update_action_bar()

		"server_broadcast":
			# Server admin broadcast message
			var broadcast_msg = message.get("message", "")
			if broadcast_msg != "":
				display_game("")
				display_game("[color=#FF4444]========================================[/color]")
				display_game("[color=#FF4444]SERVER ANNOUNCEMENT:[/color]")
				display_game("[color=#FFFF00]%s[/color]" % broadcast_msg)
				display_game("[color=#FF4444]========================================[/color]")
				display_game("")
				# Also show in chat
				display_chat("[color=#FF4444][SERVER] %s[/color]" % broadcast_msg)

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
			# Update action bar if cloak dropped (to reflect new state)
			if message.get("effect", "") == "cloak_dropped":
				update_action_bar()

		"cloak_toggle":
			# Handle cloak toggle response
			var cloak_msg = message.get("message", "")
			var cloak_active = message.get("active", false)
			if cloak_msg != "":
				display_game(cloak_msg)
			# Update character_data with new cloak state
			character_data["cloak_active"] = cloak_active
			update_action_bar()

		"ability_data":
			# Received ability loadout data from server
			ability_data = {
				"all_abilities": message.get("all_abilities", []),
				"unlocked_abilities": message.get("unlocked_abilities", []),
				"equipped_abilities": message.get("equipped_abilities", []),
				"ability_keybinds": message.get("ability_keybinds", {})
			}
			# Also update character_data
			character_data["equipped_abilities"] = ability_data.equipped_abilities
			character_data["ability_keybinds"] = ability_data.ability_keybinds
			# Display ability management screen
			display_ability_menu()

		"ability_equipped":
			var equip_msg = message.get("message", "")
			if equip_msg != "":
				display_game(equip_msg)
			# Refresh ability display
			if ability_mode:
				send_to_server({"type": "get_abilities"})

		"ability_unequipped":
			var unequip_msg = message.get("message", "")
			if unequip_msg != "":
				display_game(unequip_msg)
			# Refresh ability display
			if ability_mode:
				send_to_server({"type": "get_abilities"})

		"keybind_changed":
			var keybind_msg = message.get("message", "")
			if keybind_msg != "":
				display_game(keybind_msg)
			# Refresh ability display
			if ability_mode:
				send_to_server({"type": "get_abilities"})

		"combat_start":
			in_combat = true
			flock_pending = false
			flock_monster_name = ""
			combat_item_mode = false
			combat_outsmart_failed = false  # Reset outsmart for new combat
			last_known_hp_before_round = character_data.get("current_hp", 0)  # Track HP for danger sound
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

			# Check if we should render ASCII art client-side
			var combat_state = message.get("combat_state", {})
			var display_msg = message.get("message", "")
			if message.get("use_client_art", false):
				var monster_name = combat_state.get("monster_name", "")
				# Use base_name for art lookup (strips variant prefixes like "Corrosive")
				var monster_base_name = combat_state.get("monster_base_name", monster_name)
				if monster_name != "":
					# Render art locally using MonsterArt class (use base name for art lookup)
					var local_art = _get_monster_art().get_bordered_art_with_font(monster_base_name)
					# Build encounter text with traits
					var encounter_text = _build_encounter_text(combat_state)
					# For flock, prepend the "Another X appears!" message
					if message.get("is_flock", false):
						display_msg = "[color=#FF4444]Another %s appears![/color]\n%s\n%s" % [monster_name, local_art, encounter_text]
					else:
						display_msg = local_art + "\n" + encounter_text
			display_game(display_msg)

			# combat_state already fetched above for client-side art
			current_enemy_name = combat_state.get("monster_name", "Enemy")
			current_enemy_level = combat_state.get("monster_level", 1)
			current_enemy_color = combat_state.get("monster_name_color", "#FFFFFF")
			damage_dealt_to_current_enemy = 0
			# Get actual monster HP from server
			current_enemy_hp = combat_state.get("monster_hp", -1)
			current_enemy_max_hp = combat_state.get("monster_max_hp", -1)

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

			# Track forcefield/shield value for visual display
			current_forcefield = combat_state.get("forcefield_shield", 0)
			update_player_hp_bar()  # Refresh HP bar with shield overlay

			show_enemy_hp_bar(true)
			update_enemy_hp_bar(current_enemy_name, current_enemy_level, 0, current_enemy_hp, current_enemy_max_hp)

		"combat_message":
			var combat_msg = message.get("message", "")
			# Add visual flair to damage messages
			var enhanced_msg = _enhance_combat_message(combat_msg)
			display_game(enhanced_msg)
			# Stop any ongoing animation when we receive combat feedback
			stop_combat_animation()

			# Trigger combat sounds based on message content
			_trigger_combat_sounds(combat_msg)

			var damage = parse_damage_dealt(combat_msg)
			if damage > 0:
				damage_dealt_to_current_enemy += damage
				update_enemy_hp_bar(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy, current_enemy_hp, current_enemy_max_hp)

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
				var new_hp = state.get("player_hp", character_data.get("current_hp", 0))
				var max_hp = state.get("player_max_hp", character_data.get("max_hp", 1))

				# Check for heavy damage (>35% of max HP lost in one round)
				if last_known_hp_before_round > 0 and max_hp > 0:
					var damage_taken = last_known_hp_before_round - new_hp
					var damage_percent = float(damage_taken) / float(max_hp)
					if damage_percent > 0.35:
						play_danger_sound()

				# Update HP tracking for next round
				last_known_hp_before_round = new_hp

				character_data["current_hp"] = new_hp
				character_data["max_hp"] = max_hp
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
				# Update monster HP from server (accurate values)
				current_enemy_hp = state.get("monster_hp", current_enemy_hp)
				current_enemy_max_hp = state.get("monster_max_hp", current_enemy_max_hp)
				# Track forcefield/shield for visual display
				current_forcefield = state.get("forcefield_shield", 0)
				update_enemy_hp_bar(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy, current_enemy_hp, current_enemy_max_hp)
				update_player_hp_bar()
				update_resource_bar()
				update_action_bar()  # Refresh action bar for ability availability

		"combat_end":
			in_combat = false
			combat_item_mode = false
			combat_outsmart_failed = false  # Reset for next combat
			current_forcefield = 0  # Reset forcefield display
			update_player_hp_bar()  # Refresh HP bar to hide shield

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
					display_game("[color=#FFD700]Press [%s] to continue...[/color]" % get_action_key_name(0))
				else:
					# Combat chain complete - calculate total XP gain for bar display
					var current_xp = character_data.get("experience", 0)
					recent_xp_gain = current_xp - xp_before_combat
					xp_before_combat = 0  # Reset for next combat
					update_player_xp_bar()  # Update bar with new gain highlight

					# Play victory sound only on first kill of a monster at this specific level
					# e.g., "Giant Rat" level 4 and level 5 are tracked separately
					var enemy_key = "%s_%d" % [current_enemy_name, current_enemy_level]
					if not discovered_monster_types.has(enemy_key):
						discovered_monster_types[enemy_key] = true
						play_combat_victory_sound(true)  # Play for new discovery

					# Victory without flock - show all accumulated drops
					var flock_drops = message.get("flock_drops", [])
					if flock_drops.size() > 0:
						display_game("")
						display_game("[color=#FFD700].-=[ LOOT ]=-.[/color]")
						for drop_msg in flock_drops:
							display_game("  " + drop_msg)
						display_game("")

					# Check for rare drops and play sound effect
					var drop_value = _calculate_drop_value(message)
					if drop_value > 0:
						play_rare_drop_sound(drop_value)

					# Pause to let player read rewards
					pending_continue = true
					display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
			elif message.get("fled", false):
				# Fled - reset combat XP tracking but keep previous XP gain highlight
				xp_before_combat = 0
				# Update position if server moved us
				if message.has("new_x") and message.has("new_y"):
					character_data["x"] = message.new_x
					character_data["y"] = message.new_y
					display_game("[color=#FFD700]You fled to (%d, %d)![/color]" % [message.new_x, message.new_y])
				else:
					display_game("[color=#FFD700]You escaped from combat![/color]")
				pending_continue = true
				display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
			else:
				# Defeat handled by permadeath message
				pass

			update_action_bar()
			show_enemy_hp_bar(false)
			current_enemy_name = ""
			current_enemy_level = 0
			damage_dealt_to_current_enemy = 0

			# Note: Background reset is handled in acknowledge_continue() when player presses Space

		"wish_choice":
			# Wish granter defeated - show player reward options
			wish_options = message.get("options", [])
			if wish_options.size() > 0:
				wish_selection_mode = true
				display_game("")
				display_game("[color=#FFD700]═══════════════════════════════════════════════[/color]")
				display_game("[color=#FF00FF]  ★ The creature grants you a wish! ★[/color]")
				display_game("[color=#FFD700]═══════════════════════════════════════════════[/color]")
				display_game("")
				for i in range(wish_options.size()):
					var wish = wish_options[i]
					var key = ["Q", "W", "E"][i] if i < 3 else str(i + 1)
					var desc = _format_wish_description(wish)
					display_game("[color=#FFFF00][%s][/color] %s" % [key, desc])
				display_game("")
				display_game("[color=#808080]Choose your reward...[/color]")
				update_action_bar()

		"wish_granted":
			# Wish selection result
			wish_selection_mode = false
			wish_options = []
			in_combat = false  # End combat state so action bar shows Continue
			var result_msg = message.get("message", "Your wish has been granted!")
			display_game("")
			display_game("[color=#FF00FF]%s[/color]" % result_msg)
			# Update character data if items were added
			if message.has("character"):
				character_data = message.character
				update_player_level()
				update_player_hp_bar()
				update_resource_bar()
				update_player_xp_bar()
				update_currency_display()
			pending_continue = true
			display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
			update_action_bar()

		"monster_select_prompt":
			# Monster Selection Scroll used - show monster list
			monster_select_list = message.get("monsters", [])
			if monster_select_list.size() > 0:
				# Exit inventory mode to prevent double-trigger on number keys
				inventory_mode = false
				pending_inventory_action = ""
				selected_item_index = -1
				monster_select_mode = true
				monster_select_page = 0
				display_game(message.get("message", "Choose a monster to summon:"))
				display_monster_select_page()
				update_action_bar()

		"target_farm_select":
			# Scroll of Finding used - show ability selection
			target_farm_options = message.get("options", [])
			target_farm_names = message.get("option_names", {})
			target_farm_encounters = message.get("encounters", 5)
			if target_farm_options.size() > 0:
				# Exit inventory mode
				inventory_mode = false
				pending_inventory_action = ""
				selected_item_index = -1
				target_farm_mode = true
				display_game(message.get("message", "Choose a trait to hunt:"))
				display_target_farm_options()
				update_action_bar()

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

		# Title system messages
		"title_menu":
			handle_title_menu(message)

		"title_claimed":
			display_game(message.get("message", ""))
			if message.has("character"):
				character_data = message.character
				update_player_level()
			# Request updated player list to show new title
			send_to_server({"type": "get_player_list"})
			update_action_bar()

		"title_lost":
			display_game(message.get("message", ""))
			if message.has("character"):
				character_data = message.character
				update_player_level()
			update_action_bar()

		"title_achieved":
			display_game(message.get("message", ""))
			if message.has("character"):
				character_data = message.character
				update_player_level()
			# Request updated player list to show new title
			send_to_server({"type": "get_player_list"})
			update_action_bar()

		"forge_available":
			display_game(message.get("message", ""))
			forge_available = true
			update_action_bar()

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

	# Check for title broadcast mode
	if title_broadcast_mode:
		process_title_broadcast(text)
		return

	# Commands
	var command_keywords = ["help", "clear", "status", "who", "players", "examine", "ex", "inventory", "inv", "i", "watch", "unwatch", "abilities", "loadout", "leaders", "leaderboard", "bug", "report", "title"]
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
	var is_consumable = item.get("is_consumable", false)

	display_game("")
	display_game("[color=%s]===== %s =====[/color]" % [rarity_color, name])
	display_game("[color=#808080]%s[/color]" % source.capitalize())
	display_game("")
	display_game("[color=#00FFFF]Type:[/color] %s" % _get_item_type_description(item_type))
	display_game("[color=#00FFFF]Rarity:[/color] [color=%s]%s[/color]" % [rarity_color, rarity.capitalize()])

	# Show tier and quantity for consumables, level for equipment
	if is_consumable:
		var tier = item.get("tier", 1)
		var quantity = item.get("quantity", 1)
		display_game("[color=#00FFFF]Tier:[/color] %d" % tier)
		display_game("[color=#00FFFF]Quantity:[/color] %d" % quantity)
	else:
		display_game("[color=#00FFFF]Level:[/color] %d" % level)

	display_game("[color=#00FFFF]Value:[/color] %d gold" % value)
	display_game("")

	# For equipment, show computed stats; for consumables, show effect description
	var slot = _get_slot_for_item_type(item_type)
	if slot != "":
		# Equipment: show computed bonuses
		display_game("[color=#E6CC80]Stats:[/color]")
		var stats_shown = _display_computed_item_bonuses(item)
		if not stats_shown:
			display_game("[color=#808080](No stat bonuses)[/color]")

		# Show comparison with equipped item
		display_game("")
		var equipped = character_data.get("equipped", {})
		var equipped_item = equipped.get(slot)
		if equipped_item != null and equipped_item is Dictionary:
			display_game("[color=#E6CC80]Compared to equipped %s:[/color]" % equipped_item.get("name", "item"))
			_display_item_comparison(item, equipped_item)
		else:
			display_game("[color=#00FF00]You have nothing equipped in this slot.[/color]")
	else:
		# Consumables: show effect description based on tier
		var tier = item.get("tier", 1) if is_consumable else level
		display_game("[color=#E6CC80]Effect:[/color] %s" % _get_item_effect_description(item_type, tier, rarity))

	display_game("")

func display_equip_comparison(item: Dictionary, inv_index: int):
	"""Display item details with comparison to equipped item for equip confirmation"""
	var name = item.get("name", "Unknown Item")
	var item_type = item.get("type", "unknown")
	var rarity = item.get("rarity", "common")
	var level = item.get("level", 1)
	var rarity_color = _get_item_rarity_color(rarity)

	display_game("")
	display_game("[color=#FFD700]===== EQUIP ITEM =====[/color]")
	display_game("")
	display_game("[color=%s]%s[/color]" % [rarity_color, name])
	display_game("")
	display_game("[color=#00FFFF]Type:[/color] %s" % _get_item_type_description(item_type))
	display_game("[color=#00FFFF]Rarity:[/color] [color=%s]%s[/color]" % [rarity_color, rarity.capitalize()])
	display_game("[color=#00FFFF]Level:[/color] %d" % level)
	display_game("")

	# Display all computed stats
	var stats_shown = _display_computed_item_bonuses(item)
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
			display_game("")
			display_game("[color=#808080]Currently equipped item will be unequipped.[/color]")
		else:
			display_game("[color=#00FF00]You have nothing equipped in this slot.[/color]")

	display_game("")
	display_game("[color=#FFD700]Equip this item?[/color]")
	display_game("")
	display_game("[color=#808080][%s] Equip  |  [%s] Cancel[/color]" % [get_action_key_name(0), get_action_key_name(1)])

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

	# TIER-BASED CONSUMABLES (level parameter contains tier 1-7 when is_consumable)
	# Check if this is a tier value (1-7) which means tier-based item
	var is_tier_value = level >= 1 and level <= 7

	# Health potions (potion_minor, potion_lesser, etc. or health_potion)
	if is_tier_value and (item_type == "health_potion" or (item_type.begins_with("potion_") and "speed" not in item_type and "strength" not in item_type and "defense" not in item_type and "power" not in item_type and "iron" not in item_type and "haste" not in item_type) or item_type.begins_with("elixir_")):
		var tier_data = CONSUMABLE_TIERS.get(level, CONSUMABLE_TIERS[1])
		return "Restores %d HP when used" % tier_data.healing
	# Mana potions (mana_minor, mana_lesser, etc. or mana_potion)
	elif is_tier_value and (item_type == "mana_potion" or item_type.begins_with("mana_")):
		var tier_data = CONSUMABLE_TIERS.get(level, CONSUMABLE_TIERS[1])
		return "Restores %d Mana when used" % tier_data.mana
	# Stamina potions
	elif is_tier_value and (item_type == "stamina_potion" or item_type.begins_with("stamina_")):
		var tier_data = CONSUMABLE_TIERS.get(level, CONSUMABLE_TIERS[1])
		return "Restores %d Stamina when used" % tier_data.resource
	# Energy potions
	elif is_tier_value and (item_type == "energy_potion" or item_type.begins_with("energy_")):
		var tier_data = CONSUMABLE_TIERS.get(level, CONSUMABLE_TIERS[1])
		return "Restores %d Energy when used" % tier_data.resource
	# Buff potions (check tier versions)
	elif is_tier_value and (item_type == "strength_potion" or "potion_strength" in item_type or "potion_power" in item_type or "elixir_might" in item_type):
		var tier_data = CONSUMABLE_TIERS.get(level, CONSUMABLE_TIERS[1])
		return "+%d Strength for 5 battles" % tier_data.buff_value
	elif is_tier_value and (item_type == "defense_potion" or "potion_defense" in item_type or "potion_iron" in item_type or "elixir_fortress" in item_type):
		var tier_data = CONSUMABLE_TIERS.get(level, CONSUMABLE_TIERS[1])
		return "+%d Defense for 5 battles" % tier_data.buff_value
	elif is_tier_value and (item_type == "speed_potion" or "potion_speed" in item_type or "potion_haste" in item_type or "elixir_swiftness" in item_type):
		var tier_data = CONSUMABLE_TIERS.get(level, CONSUMABLE_TIERS[1])
		return "+%d Speed for 5 battles" % tier_data.buff_value

	# LEGACY: Check for specific buff potions first (before generic potion check)
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
	elif "stamina" in item_type:
		# Stamina potions (Warriors)
		var stamina_amounts = {
			"stamina_minor": 15 + level * 8,
			"stamina_lesser": 30 + level * 10,
			"stamina_standard": 50 + level * 12,
			"stamina_greater": 100 + level * 15
		}
		var stamina = stamina_amounts.get(item_type, 50 + level * 10)
		return "Restores %d Stamina when used" % stamina
	elif "energy" in item_type:
		# Energy potions (Tricksters)
		var energy_amounts = {
			"energy_minor": 15 + level * 8,
			"energy_lesser": 30 + level * 10,
			"energy_standard": 50 + level * 12,
			"energy_greater": 100 + level * 15
		}
		var energy = energy_amounts.get(item_type, 50 + level * 10)
		return "Restores %d Energy when used" % energy
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
		var atk = base_bonus * 3  # Weapons are THE attack item
		var str_bonus = int(base_bonus * 0.5)
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
		var def = int(base_bonus * 0.5)  # Shields give less defense
		var hp_bonus = base_bonus * 5  # Shields are THE HP item
		var con_bonus = int(base_bonus * 0.3)
		return "+%d Defense, +%d Max HP, +%d CON" % [def, hp_bonus, con_bonus]
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
		return "Worth 1000 gold when sold"
	# Scroll effects - buff scrolls
	elif "scroll_forcefield" in item_type:
		var shield_amount = 50 + level * 10
		return "Creates a %d HP shield that absorbs damage (1 battle)" % shield_amount
	elif "scroll_rage" in item_type:
		var buff_val = 20 + level * 4
		return "+%d Strength for next combat" % buff_val
	elif "scroll_stone_skin" in item_type:
		var buff_val = 20 + level * 4
		return "+%d Defense for next combat" % buff_val
	elif "scroll_haste" in item_type:
		var buff_val = 30 + level * 5
		return "+%d Speed for next combat" % buff_val
	elif "scroll_vampirism" in item_type:
		var lifesteal = 25 + level * 3
		return "%d%% Lifesteal for next combat" % lifesteal
	elif "scroll_thorns" in item_type:
		var reflect = 30 + level * 4
		return "Reflect %d%% damage for next combat" % reflect
	elif "scroll_precision" in item_type:
		var crit = 25 + level * 2
		return "+%d%% Critical chance for next combat" % crit
	# Scroll effects - debuff scrolls (affect next monster)
	elif "scroll_weakness" in item_type:
		var debuff = 25 + level * 2
		return "Next monster has -%d%% Attack" % debuff
	elif "scroll_vulnerability" in item_type:
		var debuff = 25 + level * 2
		return "Next monster has -%d%% Defense" % debuff
	elif "scroll_slow" in item_type:
		var debuff = 30 + level * 3
		return "Next monster has -%d%% Speed" % debuff
	elif "scroll_doom" in item_type:
		var debuff = 10 + level * 2
		return "Next monster loses %d%% Max HP at combat start" % debuff
	# Scroll effects - special
	elif "scroll_monster_select" in item_type:
		return "Choose your next monster encounter"
	elif "scroll" in item_type:
		return "Magical scroll with unknown power"
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
		"abilities", "loadout":
			if has_character:
				enter_ability_mode()
			else:
				display_game("You don't have a character yet")
		"title":
			if has_character:
				open_title_menu()
			else:
				display_game("You don't have a character yet")
		"leaders", "leaderboard":
			if has_character:
				show_leaderboard_panel()
			else:
				display_game("You don't have a character yet")
		"bug", "report":
			# Get optional description from rest of command
			var description = ""
			if parts.size() > 1:
				description = " ".join(parts.slice(1))
			generate_bug_report(description)
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
				last_username = data.get("last_username", "")
				saved_connections = data.get("saved_connections", [])
				# Ensure all saved connection ports are integers
				for conn in saved_connections:
					if conn.has("port"):
						conn.port = int(conn.port)
				return
	# Default values if no config
	server_ip = "localhost"
	server_port = 9080
	last_username = ""
	saved_connections = [
		{"name": "Local Server", "ip": "localhost", "port": 9080}
	]

func _save_connection_settings():
	"""Save connection settings to config file"""
	var data = {
		"last_ip": server_ip,
		"last_port": server_port,
		"last_username": last_username,
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
			# All 10 action bar slots use action_0 through action_9
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

func get_item_select_keycode(index: int) -> int:
	"""Get the keycode for item selection (index 0-8 for items 1-9)"""
	# Item selection keys are separate from action bar keys
	var item_key = "item_%d" % (index + 1)  # item_1 through item_9
	return keybinds.get(item_key, default_keybinds.get(item_key, KEY_1 + index))

func get_item_select_key_name(index: int) -> String:
	"""Get the display name for item selection key (index 0-8 for items 1-9)"""
	return get_key_name(get_item_select_keycode(index))

func is_item_key_blocked_by_action_bar(index: int) -> bool:
	"""Check if item selection key conflicts with a currently-held action bar key that has an enabled action"""
	var item_keycode = get_item_select_keycode(index)
	for j in range(10):
		var action_key = "action_%d" % j
		var action_keycode = keybinds.get(action_key, default_keybinds.get(action_key, KEY_SPACE))
		if item_keycode == action_keycode and get_meta("hotkey_%d_pressed" % j, false):
			# Block if this action bar key triggered an action THIS frame
			# (prevents item selection when action changes state, like Equip showing item list)
			if j in action_triggered_this_frame:
				return true
			# Also block if that action bar slot currently has an enabled action
			if j < current_actions.size():
				var action = current_actions[j]
				if action.get("enabled", false) and action.get("action_type", "none") != "none":
					return true
			# If no action in slot and didn't trigger this frame, allow item selection
	return false

func is_item_select_key_pressed(index: int) -> bool:
	"""Check if the item selection key is pressed (index 0-8 for items 1-9)"""
	var keycode = get_item_select_keycode(index)
	return Input.is_physical_key_pressed(keycode) and not Input.is_key_pressed(KEY_SHIFT)

func _key_to_selection_index(key: int) -> int:
	"""Convert a keycode to a selection index (0-8). Returns -1 if not a selection key."""
	for i in range(9):
		if key == get_item_select_keycode(i):
			return i
	return -1

func get_action_key_name(action_index: int) -> String:
	"""Get the display name for an action bar key (index 0-9)"""
	var action_key = "action_%d" % action_index
	var keycode = keybinds.get(action_key, default_keybinds.get(action_key, KEY_SPACE))
	return get_key_name(keycode)

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

func get_selection_keys_text(count: int) -> String:
	"""Generate text showing selection key range (e.g., 'Press 1-5' or 'Press Q-R')"""
	if count <= 0:
		return ""
	# Cap at 9 since we only have keybinds for 1-9
	var capped_count = min(count, 9)
	if capped_count == 1:
		return "Press %s" % get_item_select_key_name(0)
	return "Press %s-%s" % [get_item_select_key_name(0), get_item_select_key_name(capped_count - 1)]

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
	display_game("[%s] Configure Action Bar Keys" % get_action_key_name(1))
	display_game("[%s] Configure Movement Keys" % get_action_key_name(2))
	display_game("[%s] Configure Item Selection Keys" % get_action_key_name(3))
	display_game("[%s] Reset All to Defaults" % get_action_key_name(4))
	display_game("[%s] Back to Game" % get_action_key_name(0))
	display_game("")
	display_game("[color=#808080]Current Keybinds Summary:[/color]")
	display_game("  Primary Action: [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("action_0", KEY_SPACE)))
	display_game("  Item Selection: [color=#00FFFF]%s[/color]-[color=#00FFFF]%s[/color]" % [get_item_select_key_name(0), get_item_select_key_name(8)])
	display_game("  Move North: [color=#00FFFF]%s[/color] / [color=#00FFFF]%s[/color]" % [get_key_name(keybinds.get("move_8", KEY_KP_8)), get_key_name(keybinds.get("move_up", KEY_UP))])
	display_game("  Hunt: [color=#00FFFF]%s[/color]" % get_key_name(keybinds.get("hunt", KEY_KP_5)))

func display_action_keybinds():
	"""Display action bar keybinds for editing"""
	display_game("[color=#FFD700]===== ACTION BAR KEYBINDS =====[/color]")
	display_game("")
	var action_names = ["Primary (Space)", "Action 1 (Q)", "Action 2 (W)", "Action 3 (E)", "Action 4 (R)", "Action 5 (6)", "Action 6 (7)", "Action 7 (8)", "Action 8 (9)", "Action 9 (0)"]
	for i in range(10):  # Show all 10 action bar keys
		var action_key = "action_%d" % i
		var current_key = keybinds.get(action_key, default_keybinds[action_key])
		display_game("[%d] %s: [color=#00FFFF]%s[/color]" % [i, action_names[i], get_key_name(current_key)])
	display_game("")
	display_game("[color=#808080]Press 0-9 to rebind, or %s to go back[/color]" % get_action_key_name(0))

func display_item_keybinds():
	"""Display item selection keybinds for editing (used in inventory, merchant, quests)"""
	display_game("[color=#FFD700]===== ITEM SELECTION KEYBINDS =====[/color]")
	display_game("[color=#808080]These keys are used to select items in inventory, merchant, and quest menus.[/color]")
	display_game("")
	for i in range(9):
		var item_key = "item_%d" % (i + 1)  # item_1 through item_9
		var current_key = keybinds.get(item_key, default_keybinds.get(item_key, KEY_1 + i))
		display_game("[%d] Item %d: [color=#00FFFF]%s[/color]" % [i + 1, i + 1, get_key_name(current_key)])
	display_game("")
	display_game("[color=#808080]Press 1-9 to rebind, or %s to go back[/color]" % get_action_key_name(0))

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
	display_game("[%s] Up: [color=#00FFFF]%s[/color]" % [get_action_key_name(1), get_key_name(keybinds.get("move_up", KEY_UP))])
	display_game("[%s] Down: [color=#00FFFF]%s[/color]" % [get_action_key_name(2), get_key_name(keybinds.get("move_down", KEY_DOWN))])
	display_game("[%s] Left: [color=#00FFFF]%s[/color]" % [get_action_key_name(3), get_key_name(keybinds.get("move_left", KEY_LEFT))])
	display_game("[%s] Right: [color=#00FFFF]%s[/color]" % [get_action_key_name(4), get_key_name(keybinds.get("move_right", KEY_RIGHT))])
	display_game("")
	display_game("[color=#808080]Press a key to rebind, or %s to go back[/color]" % get_action_key_name(0))

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
	elif settings_submenu == "item_keys":
		display_item_keybinds()
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
		clear_game_output()
		last_move_time = current_time

func _on_hunt_button():
	"""Handle Hunt button press - searches for monsters with increased encounter chance"""
	if not connected or not has_character:
		return
	if in_combat or flock_pending or pending_continue or inventory_mode or at_merchant:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_move_time >= MOVE_COOLDOWN:
		clear_game_output()
		send_to_server({"type": "hunt"})
		last_move_time = current_time

# ===== DISPLAY FUNCTIONS =====

func display_title_holders(holders: Array):
	"""Display current realm title holders on login"""
	if holders.is_empty():
		display_game("[color=#808080]═══ The realm has no titled rulers ═══[/color]")
		return

	display_game("[color=#FFD700]═══════════════════ REALM TITLES ═══════════════════[/color]")

	for holder in holders:
		var title = holder.get("title", "")
		var name = holder.get("name", "")
		var level = holder.get("level", 0)
		var count = holder.get("count", 0)

		match title:
			"high_king":
				display_game("[color=#FFD700]  [High King] %s (Level %d) - Supreme Ruler[/color]" % [name, level])
			"jarl":
				display_game("[color=#C0C0C0]  [Jarl] %s (Level %d) - Chieftain[/color]" % [name, level])
			"eternal":
				display_game("[color=#00FFFF]  [Eternal] %s (Level %d) - Immortal Legend[/color]" % [name, level])
			"elder":
				if count > 0:
					display_game("[color=#9400D3]  %d Elder%s walk the realm[/color]" % [count, "s" if count > 1 else ""])

	display_game("[color=#FFD700]════════════════════════════════════════════════════[/color]")

func display_character_status():
	if not has_character:
		return

	# Set contrasting background for status page (dark blue-gray)
	_set_game_output_background(Color(0.05, 0.08, 0.12, 1.0))

	var char = character_data
	var stats = char.get("stats", {})
	var equipped = char.get("equipped", {})
	var bonuses = _calculate_equipment_bonuses(equipped)

	var current_xp = char.get("experience", 0)
	var xp_needed = char.get("experience_to_next_level", 100)
	var xp_remaining = xp_needed - current_xp

	var text = "[b][color=#FFD700]═══════ Character Status ═══════[/color][/b]\n"
	text += "Name: %s\n" % char.get("name", "Unknown")
	text += "Race: %s  |  Class: %s  |  Level: %d\n" % [char.get("race", "Human"), char.get("class", "Unknown"), char.get("level", 1)]

	# === CLASS PASSIVE ===
	var class_passive = _get_class_passive(char.get("class", ""))
	if class_passive.name != "None":
		text += "[color=%s]%s:[/color] %s\n" % [class_passive.color, class_passive.name, class_passive.description]

	text += "[color=#FF00FF]Experience:[/color] %d / %d ([color=#FFD700]%d to next level[/color])\n" % [current_xp, xp_needed, xp_remaining]
	text += "Gold: %d  |  Position: (%d, %d)  |  Kills: %d\n\n" % [char.get("gold", 0), char.get("x", 0), char.get("y", 0), char.get("monsters_killed", 0)]

	# === HEALTH & RESOURCES ===
	var base_hp = char.get("max_hp", 0)
	var total_hp = char.get("total_max_hp", base_hp)
	var hp_from_gear = total_hp - base_hp

	text += "[color=#FF6666]═══ Health & Resources ═══[/color]\n"
	text += "  [color=#FF4444]HP:[/color] %d / %d" % [char.get("current_hp", 0), total_hp]
	if hp_from_gear > 0:
		text += " [color=#00FF00](Base: %d + %d from gear)[/color]" % [base_hp, hp_from_gear]
	text += " (%s)\n" % char.get("health_state", "Unknown")

	var base_mana = char.get("max_mana", 0)
	var total_mana = char.get("total_max_mana", base_mana)
	var mana_from_gear = total_mana - base_mana
	text += "  [color=#00BFFF]Mana:[/color] %d / %d" % [char.get("current_mana", 0), total_mana]
	if mana_from_gear > 0:
		text += " [color=#00FF00](+%d from gear)[/color]" % mana_from_gear
	text += "\n"

	text += "  [color=#FF8C00]Stamina:[/color] %d / %d\n" % [char.get("current_stamina", 0), char.get("max_stamina", 0)]
	text += "  [color=#00FF00]Energy:[/color] %d / %d\n\n" % [char.get("current_energy", 0), char.get("max_energy", 0)]

	# === BASE STATS ===
	text += "[color=#00FFFF]═══ Base Stats ═══[/color]\n"
	var stat_names = [
		["STR", "strength"], ["CON", "constitution"], ["DEX", "dexterity"],
		["INT", "intelligence"], ["WIS", "wisdom"], ["WIT", "wits"]
	]
	var line1 = "  "
	var line2 = "  "
	for i in range(stat_names.size()):
		var stat_abbr = stat_names[i][0]
		var stat_key = stat_names[i][1]
		var base_val = stats.get(stat_key, 0)
		var bonus_val = bonuses.get(stat_key, 0)
		var stat_text = "%s: %d" % [stat_abbr, base_val]
		if bonus_val > 0:
			stat_text += "[color=#00FF00](+%d)[/color]" % bonus_val
		stat_text += "  "
		if i < 3:
			line1 += stat_text
		else:
			line2 += stat_text
	text += line1 + "\n" + line2 + "\n\n"

	# === COMBAT STATS ===
	var base_str = stats.get("strength", 0)
	var total_attack = base_str + bonuses.strength + bonuses.attack
	var attack_from_str = base_str + bonuses.strength
	var attack_from_gear = bonuses.attack

	var base_con = stats.get("constitution", 0)
	var total_defense = (base_con + bonuses.constitution) / 2 + bonuses.defense
	var base_defense = base_con / 2
	var defense_from_gear = bonuses.defense + bonuses.constitution / 2

	# Calculate damage reduction percentage (same formula as combat)
	var defense_ratio = float(total_defense) / (float(total_defense) + 100.0)
	var damage_reduction_pct = int(defense_ratio * 60)  # Max 60% reduction

	text += "[color=#FF6666]═══ Combat Stats ═══[/color]\n"
	text += "  [color=#FF4444]Attack Power:[/color] %d" % total_attack
	text += " [color=#808080](STR: %d" % attack_from_str
	if attack_from_gear > 0:
		text += " + Gear: %d" % attack_from_gear
	text += ")[/color]\n"

	text += "  [color=#00BFFF]Defense:[/color] %d" % total_defense
	text += " [color=#808080](Base: %d" % base_defense
	if defense_from_gear > 0:
		text += " + Gear: %d" % defense_from_gear
	text += ")[/color]\n"

	text += "  [color=#FFD700]Damage Reduction:[/color] %d%%" % damage_reduction_pct
	text += " [color=#808080](Higher defense = more reduction, max 60%%)[/color]\n"

	text += "  [color=#FFFFFF]Damage Range:[/color] %d - %d\n" % [int(total_attack * 0.8), int(total_attack * 1.2)]

	if bonuses.speed > 0:
		text += "  [color=#00FFFF]Speed Bonus:[/color] +%d (improves flee chance)\n" % bonuses.speed

	# === CLASS-SPECIFIC BONUSES ===
	var has_class_bonus = bonuses.mana_regen > 0 or bonuses.meditate_bonus > 0 or bonuses.energy_regen > 0 or bonuses.flee_bonus > 0
	if has_class_bonus:
		text += "\n[color=#FF00FF]═══ Class Gear Bonuses ═══[/color]\n"
		if bonuses.mana_regen > 0:
			text += "  [color=#66CCCC]Mana Regen:[/color] +%d per combat round (Arcane Ring)\n" % bonuses.mana_regen
		if bonuses.meditate_bonus > 0:
			text += "  [color=#66CCCC]Meditate Bonus:[/color] +%d%% effectiveness (Mystic Amulet)\n" % bonuses.meditate_bonus
		if bonuses.energy_regen > 0:
			text += "  [color=#66FF66]Energy Regen:[/color] +%d per combat round (Trickster Gear)\n" % bonuses.energy_regen
		if bonuses.flee_bonus > 0:
			text += "  [color=#66FF66]Flee Bonus:[/color] +%d%% flee chance (Evasion Amulet)\n" % bonuses.flee_bonus
	text += "\n"

	# === EQUIPMENT STATUS ===
	text += "[color=#FFA500]═══ Equipment Condition ═══[/color]\n"
	var has_equipment = false
	for slot in ["weapon", "shield", "armor", "helm", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			has_equipment = true
			var wear = item.get("wear", 0)
			var condition = _get_condition_string(wear)
			var effectiveness = 100 - wear
			var condition_color = _get_condition_color(wear)
			var item_name = item.get("name", "Unknown")
			if item_name.length() > 25:
				item_name = item_name.substr(0, 22) + "..."
			text += "  %s: [color=%s]%s[/color] (%d%% effective)\n" % [item_name, condition_color, condition, effectiveness]

	if not has_equipment:
		text += "  [color=#808080]No equipment worn[/color]\n"
	text += "\n"

	# Active Effects section
	var effects_text = _get_status_effects_text()
	if effects_text != "":
		text += effects_text

	display_game(text)

func _get_condition_string(wear: int) -> String:
	"""Get a human-readable condition string from wear percentage"""
	if wear == 0:
		return "Pristine"
	elif wear <= 10:
		return "Excellent"
	elif wear <= 25:
		return "Good"
	elif wear <= 50:
		return "Worn"
	elif wear <= 75:
		return "Damaged"
	elif wear < 100:
		return "Nearly Broken"
	else:
		return "BROKEN"

func _get_condition_color(wear: int) -> String:
	"""Get color for equipment condition"""
	if wear == 0:
		return "#00FF00"  # Green - Pristine
	elif wear <= 10:
		return "#7FFF00"  # Light green - Excellent
	elif wear <= 25:
		return "#FFFF00"  # Yellow - Good
	elif wear <= 50:
		return "#FFA500"  # Orange - Worn
	elif wear <= 75:
		return "#FF4444"  # Red - Damaged
	elif wear < 100:
		return "#FF0000"  # Bright red - Nearly Broken
	else:
		return "#808080"  # Gray - Broken

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

func _get_class_passive(class_type: String) -> Dictionary:
	"""Get class passive info (client-side mirror of Character.get_class_passive)"""
	match class_type:
		"Fighter":
			return {"name": "Tactical Discipline", "description": "20% reduced stamina costs, +15% defense", "color": "#C0C0C0"}
		"Barbarian":
			return {"name": "Blood Rage", "description": "+3% damage per 10% HP missing (max +30%), abilities cost 25% more", "color": "#8B0000"}
		"Paladin":
			return {"name": "Divine Favor", "description": "Heal 3% max HP per round, +25% damage vs undead/demons", "color": "#FFD700"}
		"Wizard":
			return {"name": "Arcane Precision", "description": "+15% spell damage, +10% spell crit chance", "color": "#4169E1"}
		"Sorcerer":
			return {"name": "Chaos Magic", "description": "25% chance for double spell damage, 10% chance to backfire", "color": "#9400D3"}
		"Sage":
			return {"name": "Mana Mastery", "description": "25% reduced mana costs, Meditate restores 50% more", "color": "#20B2AA"}
		"Thief":
			return {"name": "Backstab", "description": "+50% crit damage, +15% base crit chance", "color": "#2F4F4F"}
		"Ranger":
			return {"name": "Hunter's Mark", "description": "+25% damage vs beasts, +30% gold/XP from kills", "color": "#228B22"}
		"Ninja":
			return {"name": "Shadow Step", "description": "+40% flee success, take no damage when fleeing", "color": "#191970"}
		_:
			return {"name": "None", "description": "No passive ability", "color": "#808080"}

func _get_buff_value(buff_type: String) -> int:
	"""Get the current value of a buff type from character_data (combines active and persistent buffs)"""
	var total = 0
	var active_buffs = character_data.get("active_buffs", [])
	var persistent_buffs = character_data.get("persistent_buffs", [])

	for buff in active_buffs:
		if buff is Dictionary and buff.get("type", "") == buff_type:
			total += buff.get("value", 0)
	for buff in persistent_buffs:
		if buff is Dictionary and buff.get("type", "") == buff_type:
			total += buff.get("value", 0)
	return total

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
		"speed": 0,
		# Class-specific bonuses
		"mana_regen": 0,
		"meditate_bonus": 0,
		"energy_regen": 0,
		"flee_bonus": 0
	}

	for slot in equipped.keys():
		var item = equipped.get(slot)
		if item == null or not item is Dictionary:
			continue

		var item_level = item.get("level", 1)
		var item_type = item.get("type", "")
		var rarity_mult = _get_rarity_multiplier_for_status(item.get("rarity", "common"))

		# Check for item wear/damage (0-100, 100 = fully damaged/broken)
		var wear = item.get("wear", 0)
		var wear_penalty = 1.0 - (float(wear) / 100.0)  # 0% wear = 100% effectiveness

		# Base bonus scales with item level, rarity, and wear
		var base_bonus = int(item_level * rarity_mult * wear_penalty)

		# Apply bonuses based on item type (matches server character.gd)
		# Use max(1, ...) for fractional multipliers to ensure even low-level items show stats
		if "weapon" in item_type:
			bonuses.attack += base_bonus * 3  # Weapons are THE attack item
			bonuses.strength += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		elif "armor" in item_type:
			bonuses.defense += base_bonus * 2
			bonuses.constitution += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.max_hp += base_bonus * 3
		elif "helm" in item_type:
			bonuses.defense += base_bonus
			bonuses.wisdom += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "shield" in item_type:
			bonuses.defense += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.max_hp += base_bonus * 5  # Shields are THE HP item
			bonuses.constitution += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		elif item_type == "ring_arcane":
			# Mage ring: INT + mana regen
			bonuses.intelligence += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.mana_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif item_type == "ring_shadow":
			# Trickster ring: WITS + energy regen
			bonuses.wits += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.energy_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "ring" in item_type:
			bonuses.attack += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.dexterity += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.intelligence += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif item_type == "amulet_mystic":
			# Mage amulet: max mana + meditate bonus
			bonuses.max_mana += base_bonus * 3
			bonuses.meditate_bonus += max(1, int(item_level / 2)) if item_level > 0 else 0
		elif item_type == "amulet_evasion":
			# Trickster amulet: speed + flee bonus
			bonuses.speed += base_bonus
			bonuses.flee_bonus += max(1, int(item_level / 3)) if item_level > 0 else 0
		elif "amulet" in item_type:
			bonuses.max_mana += base_bonus * 2
			bonuses.wisdom += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.wits += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif item_type == "boots_swift":
			# Trickster boots: extra speed + WITS + energy_regen
			bonuses.speed += int(base_bonus * 1.5)
			bonuses.wits += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.energy_regen += max(1, int(base_bonus * 0.1)) if base_bonus > 0 else 0
		elif "boots" in item_type:
			bonuses.speed += base_bonus
			bonuses.dexterity += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.defense += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0

		# Apply affix bonuses (also affected by wear)
		var affixes = item.get("affixes", {})
		if affixes.has("hp_bonus"):
			bonuses.max_hp += int(affixes.hp_bonus * wear_penalty)
		if affixes.has("attack_bonus"):
			bonuses.attack += int(affixes.attack_bonus * wear_penalty)
		if affixes.has("defense_bonus"):
			bonuses.defense += int(affixes.defense_bonus * wear_penalty)
		if affixes.has("dex_bonus"):
			bonuses.dexterity += int(affixes.dex_bonus * wear_penalty)
		if affixes.has("wis_bonus"):
			bonuses.wisdom += int(affixes.wis_bonus * wear_penalty)

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
	# Build action key names dynamically for help text
	var k0 = get_action_key_name(0)  # Primary (default: Space)
	var k1 = get_action_key_name(1)  # Quick 1 (default: Q)
	var k2 = get_action_key_name(2)  # Quick 2 (default: W)
	var k3 = get_action_key_name(3)  # Quick 3 (default: E)
	var k4 = get_action_key_name(4)  # Quick 4 (default: R)
	var k5 = get_action_key_name(5)  # Additional 1 (default: 1)
	var k6 = get_action_key_name(6)  # Additional 2 (default: 2)
	var k7 = get_action_key_name(7)  # Additional 3 (default: 3)
	var k8 = get_action_key_name(8)  # Additional 4 (default: 4)

	var help_text = """
[b][color=#FF6666]WARNING: PERMADEATH IS ENABLED![/color][/b]
If you die, your character is gone forever! Play smart!

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 1: GETTING STARTED
═══════════════════════════════════════════════[/color][/b]

[color=#00FFFF]Controls:[/color]
  [Escape] Toggle movement mode
  [NUMPAD] 7 8 9 = NW N NE
           4 5 6 = W stay E
           1 2 3 = SW S SE
  Just type and press Enter to chat!

[color=#00FFFF]Action Bar:[/color]
  [%s] = Primary action (Status/Attack)
  [%s][%s][%s][%s] = Quick actions
  [%s][%s][%s][%s] = Additional actions

[color=#00FFFF]Basic Commands:[/color]
  inventory/inv/i - Open inventory ([%s] in movement)
  abilities/loadout - Manage abilities ([%s] in movement)
  status - Show detailed stats
  who/players - See online players
  examine <name> - View another player
  help - This help screen
  clear - Clear screens

[color=#00FFFF]Map Legend:[/color]
  [color=#FF6600]![/color] = Danger Zone (hotspot - stronger monsters)
  [color=#FFFF00]P[/color] = Trading Post (safe zone)
  [color=#FFD700]$[/color] = Wandering Merchant
  [color=#00FF00]@[/color] = You

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 2: CHARACTER BUILDING
═══════════════════════════════════════════════[/color][/b]

[color=#AAAAAA]-- PRIMARY STATS --[/color]

[color=#FF6666]STR (Strength)[/color] - Physical power
  • +2%% attack damage per point
  • Powers Warrior abilities

[color=#66FF66]CON (Constitution)[/color] - Survivability
  • Max HP = 50 + CON × 5
  • Defense = CON/2 + gear

[color=#66FFFF]DEX (Dexterity)[/color] - Speed and precision
  • +1%% hit chance per point
  • +2%% flee chance per point
  • Crit chance: 5%% + 0.5%% per point (max 25%%)

[color=#FF66FF]INT (Intelligence)[/color] - Magic power
  • +3%% spell damage per point
  • Mana = INT×8 + WIS×4
  • Powers Mage abilities

[color=#FFFF66]WIS (Wisdom)[/color] - Magic support
  • Contributes to max mana
  • High enemy WIS resists spells

[color=#FFA500]WIT (Wits)[/color] - Cunning
  • Powers Outsmart action
  • +5%% outsmart per point above 10
  • Powers Trickster abilities

[color=#AAAAAA]-- RACE PASSIVES --[/color]

[color=#FFFFFF]Human[/color] - +10%% XP from all sources
[color=#66FF99]Elf[/color] - 50%% reduced poison, immune to poison debuffs
[color=#FFA366]Dwarf[/color] - 25%% chance to survive lethal hit with 1 HP
[color=#8B4513]Ogre[/color] - All healing doubled (2x)

[color=#AAAAAA]-- CLASS PATHS --[/color]

[color=#FF6666]WARRIOR PATH[/color] (STR > 10) - Uses Stamina
  [color=#C0C0C0]Fighter[/color] - 20%% reduced stamina, +15%% defense
  [color=#8B0000]Barbarian[/color] - +3%% dmg per 10%% HP missing (max +30%%)
  [color=#FFD700]Paladin[/color] - Heal 3%% HP/round, +25%% vs undead/demons

[color=#66FFFF]MAGE PATH[/color] (INT > 10) - Uses Mana
  [color=#4169E1]Wizard[/color] - +15%% spell dmg, +10%% spell crit
  [color=#9400D3]Sorcerer[/color] - 25%% double dmg, 10%% backfire
  [color=#20B2AA]Sage[/color] - 25%% reduced mana, +50%% Meditate

[color=#66FF66]TRICKSTER PATH[/color] (WITS > 10) - Uses Energy
  [color=#2F4F4F]Thief[/color] - +50%% crit damage, +15%% base crit
  [color=#228B22]Ranger[/color] - +25%% vs beasts, +30%% gold/XP
  [color=#191970]Ninja[/color] - +40%% flee, no damage when fleeing

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 3: COMBAT
═══════════════════════════════════════════════[/color][/b]

[color=#AAAAAA]-- DAMAGE FORMULAS --[/color]

[color=#00FFFF]Physical Attack:[/color]
  Base = STR + weapon bonuses
  Multiplied by: 1.0 + (STR × 0.02)
  Critical: 1.5x damage (chance from DEX)

[color=#00FFFF]Defense Reduction:[/color]
  Reduction = Defense / (Defense + 100) × 60%%
  50 DEF = 23%%, 200 DEF = 40%%, 500 DEF = 50%%

[color=#00FFFF]Level Difference Penalty:[/color]
  vs higher level monsters, your damage is reduced:
  Attacks: -3%% per level (max -50%%)
  Abilities: -1.5%% per level (max -40%%)
  Example: 10 levels above = -30%% attack / -15%% ability

[color=#00FFFF]Hit/Flee Chance:[/color]
  Hit = 75%% + (your DEX - enemy speed), clamped 50-95%%
  Flee = 50%% + DEX×2 + speed bonuses - level diff×3, clamped 5-95%%

[color=#AAAAAA]-- WARRIOR ABILITIES --[/color]
Uses [color=#FFCC00]Stamina[/color] = STR×4 + CON×4 (refills between combats)

Lv1  [color=#FF6666]Power Strike[/color] (10) - 1.5x Attack
Lv10 [color=#FF6666]War Cry[/color] (15) - +25%% dmg, 3 rounds
Lv25 [color=#FF6666]Shield Bash[/color] (20) - Attack + stun
Lv40 [color=#FF6666]Cleave[/color] (30) - 2x Attack
Lv60 [color=#FF6666]Berserk[/color] (40) - +100%% dmg, -50%% def, 3 rounds
Lv80 [color=#FF6666]Iron Skin[/color] (35) - Block 50%% dmg, 3 rounds
Lv100 [color=#FF6666]Devastate[/color] (50) - 4x Attack

[color=#AAAAAA]-- MAGE ABILITIES --[/color]
Uses [color=#66CCCC]Mana[/color] = INT×12 + WIS×6 (use Meditate to restore)

[color=#66FFFF]Meditate[/color] - Restores HP + 4%% mana (8%% if full HP)

Lv1  [color=#66FFFF]Magic Bolt[/color] (var) - Mana × (1 + INT/50) damage
Lv10 [color=#66FFFF]Shield[/color] (20) - +50%% def, 3 rounds
Lv25 [color=#66FFFF]Cloak[/color] (30) - 50%% miss next attack
Lv40 [color=#66FFFF]Blast[/color] (50) - 2x Magic
Lv60 [color=#66FFFF]Forcefield[/color] (75) - Block 2 attacks
Lv80 [color=#66FFFF]Teleport[/color] (40) - Guaranteed flee
Lv100 [color=#66FFFF]Meteor[/color] (100) - 5x Magic

[color=#AAAAAA]-- TRICKSTER ABILITIES --[/color]
Uses [color=#66FF66]Energy[/color] = WITS×4 + DEX×4 (refills between combats)

Lv1  [color=#FFA500]Analyze[/color] (5) - Reveal monster stats
Lv10 [color=#FFA500]Distract[/color] (15) - -50%% enemy accuracy
Lv25 [color=#FFA500]Pickpocket[/color] (20) - Steal WITS×10 gold
Lv40 [color=#FFA500]Ambush[/color] (30) - 1.5x (Attack+WITS/2), +50%% crit
Lv60 [color=#FFA500]Vanish[/color] (40) - Invisible, next attack crits
Lv80 [color=#FFA500]Exploit[/color] (35) - 10%% monster HP as damage
Lv100 [color=#FFA500]Perfect Heist[/color] (50) - Instant win, 2x rewards

[color=#AAAAAA]-- OUTSMART --[/color]

[color=#FFA500]Outsmart[/color] - Trick dumb monsters for instant win
  Base 5%% + 5%% per WITS above 10
  +15%% for Tricksters
  +8%% per monster INT below 10
  -8%% per monster INT above 10
  Clamped 2-85%% (Tricksters: 2-95%%)
  [color=#00FF00]Best:[/color] Beasts, undead | [color=#FF4444]Worst:[/color] Mages, dragons
  Failure = enemy free attack, can't retry

[color=#AAAAAA]-- UNIVERSAL ABILITIES --[/color]

[color=#9932CC]Cloak[/color] (Level 20+) - Stealth movement
  • 8%% resource drain per step
  • No monster encounters while cloaked
  • Toggle with [%s] in movement mode

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 4: MONSTERS
═══════════════════════════════════════════════[/color][/b]

[color=#FF4444]Offensive Abilities:[/color]
  Poison - DoT persists outside combat
  Bleed - Stacking DoT (up to 3)
  Multi-Strike - 2-3 attacks per turn
  Berserker - +dmg when wounded
  Enrage - Stronger each round
  Life Steal - Heals from damage
  Glass Cannon - 3x dmg, half HP

[color=#808080]Debuffs:[/color]
  Curse - Reduces defense
  Disarm - Reduces damage
  Blind - Reduces hit chance
  Slow Aura - Reduces flee chance
  Drain - Steals mana/stamina/energy

[color=#6666FF]Defensive:[/color]
  Armored - +50%% defense
  Ethereal - 50%% dodge
  Regeneration - Heals per turn
  Damage Reflect - Returns 25%%
  Thorns - Damages you on hit

[color=#FFD700]Special:[/color]
  Death Curse - Damages on death
  Summoner - Calls reinforcements
  Corrosive/Sunder - Damages gear

[color=#00FF00]Reward Abilities:[/color]
  Wish Granter - 10%% chance for wish
  Weapon Master - 35%% weapon drop
  Shield Bearer - 35%% shield drop
  Arcane Hoarder - 35%% mage gear
  Cunning Prey - 35%% trickster gear
  Gem Bearer - Always extra gems
  Gold Hoarder - 3x gold

[color=#AAAAAA]-- WISH REWARDS --[/color]

When Wish Granter offers a wish (10%% chance):
  [color=#00FFFF]Gems[/color] - Precious gems
  [color=#A335EE]Gear[/color] - High-quality equipment
  [color=#FFD700]Buff[/color] - Powerful temp combat buff
  [color=#FF8000]Equipment Upgrade[/color] - Up to 12 upgrades!
  [color=#FF00FF]Permanent Stats[/color] - Rare stat boost

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 5: ITEMS & EQUIPMENT
═══════════════════════════════════════════════[/color][/b]

[color=#AAAAAA]-- CONSUMABLES --[/color]

[color=#00FFFF]Potions:[/color] Use with [%s] from inventory
  Health - Restore HP (Minor to Divine)
  Mana/Stamina/Energy - Restore resources
  Strength/Defense/Speed - Temp stat boost
  Crit/Lifesteal/Thorns - Combat effects

[color=#FF00FF]Buff Scrolls (apply before combat):[/color]
  Forcefield, Rage, Stone Skin, Haste
  Vampirism, Thorns, Precision

[color=#A335EE]Debuff Scrolls (weaken next monster):[/color]
  Weakness, Vulnerability, Slow, Doom

[color=#A335EE]Special Scrolls:[/color]
  Scroll of Summoning - Choose your next monster!
  Scroll of Finding - Next 5 monsters have chosen trait

[color=#AAAAAA]-- EQUIPMENT WEAR --[/color]

Some monsters (Corrosive, Sundering) damage gear.
Worn equipment = reduced bonuses.
100%% wear = broken, no bonuses!
Repair at merchants.

[color=#AAAAAA]-- GEAR HUNTING BY CLASS --[/color]

Hunt these monsters for class-specific equipment (35%% drop):

[color=#FF6666]WARRIOR GEAR[/color] (Warrior Hoarder trait):
  Minotaur (tier 3), Iron Golem (tier 6), Death Incarnate (tier 8)

[color=#66CCCC]MAGE GEAR[/color] (Arcane Hoarder trait):
  Wraith (tier 3), Lich (tier 5), Elemental (tier 6)
  Sphinx (tier 6), Elder Lich (tier 7), Time Weaver (tier 8)

[color=#66FF66]TRICKSTER GEAR[/color] (Cunning Prey trait):
  Goblin (tier 1), Hobgoblin (tier 2), Giant Spider (tier 2)
  Void Walker (tier 7)

[color=#FFD700]WEAPONS/SHIELDS[/color] (Rare variants, 4%% spawn chance):
  Any monster Lv5+ can spawn as "Weapon Master" or "Shield Guardian"
  35%% guaranteed drop of that item type!
  Scroll of Finding can force these to appear.

[color=#AAAAAA]-- BUFFS & DEBUFFS --[/color]

Shown in overlay: [Letter+Value:Duration]
  [color=#FF6666]S[/color]=STR [color=#6666FF]D[/color]=DEF [color=#66FF66]V[/color]=SPD [color=#FFD700]C[/color]=Crit
  [color=#FF00FF]L[/color]=Lifesteal [color=#FF4444]T[/color]=Thorns [color=#00FFFF]F[/color]=Forcefield
  Number = rounds, Number+B = battles

[color=#FF00FF]Poison[/color] ticks on movement/hunting (can't kill).

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 6: THE WORLD
═══════════════════════════════════════════════[/color][/b]

[color=#AAAAAA]-- TRADING POSTS (58 Total) --[/color]

Safe zones with shops, quests, recharge ([%s]).
  [color=#00FF00]Haven[/color] (0,10) - Spawn, beginner quests
  [color=#00FF00]Crossroads[/color] (0,0) - The High Seat, hotzone quests
  [color=#00FF00]Frostgate[/color] (0,-100) - Boss hunts
  +55 more across the world!

Denser near center, sparser at edges.

[color=#AAAAAA]-- WANDERING MERCHANTS (110) --[/color]

Roam between posts. Buy, sell, upgrade, gamble.
[color=#FF4444]$[/color]=Weaponsmith [color=#4488FF]$[/color]=Armorer [color=#AA44FF]$[/color]=Jeweler [color=#FFD700]$[/color]=General

[color=#AAAAAA]-- DANGER ZONES --[/color]

[color=#FF6600]![/color] = Hotspot with 50-150%% level bonus!
Higher risk, higher rewards.

[color=#AAAAAA]-- QUESTS --[/color]

Accept at Trading Posts. View with [%s] Quests.
  Kill quests - Slay X monsters
  Hotzone quests - Hunt in danger zones (bonus rewards!)
  Exploration - Visit specific locations
  Boss hunts - Defeat high-level monsters

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 7: GEMS & PROGRESSION
═══════════════════════════════════════════════[/color][/b]

[color=#00FFFF]Gems (Premium Currency):[/color]
  • Drop from monsters 5+ levels ABOVE you
  • Higher level diff = better drop chance
  • Sell to merchants: 1 gem = 1000 gold
  • Pay for upgrades (1 gem = 1000g value)

[color=#FFD700]Lucky Finds:[/color]
Rarely while moving/hunting:
  • Hidden treasure (gold or items)
  • [color=#FF69B4]Legendary Adventurer[/color] - Permanent stat boost!

Press [%s] to continue when these appear.

[color=#00FFFF]Level Up:[/color]
  • Fully healed (HP, mana/stamina/energy)
  • Stats increase based on class

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 8: CHASE ITEMS & ENDGAME
═══════════════════════════════════════════════[/color][/b]

Long-term goals for dedicated players!

[color=#AAAAAA]-- CHASE ITEMS --[/color]

[color=#C0C0C0]Jarl's Ring[/color]
  • Rare drop from Lv100+ monsters
  • Required to become [color=#C0C0C0]Jarl[/color]
  • Consumed when claiming title

[color=#A335EE]Unforged Crown[/color]
  • Very rare drop from Lv200+ monsters
  • Forge at [color=#FF6600]Fire Mountain[/color] (-400,0)
  • Survive the trial to create Crown of the North

[color=#FFD700]Crown of the North[/color]
  • Created from Unforged Crown
  • Required to become [color=#FFD700]High King[/color]
  • Consumed when claiming title

[color=#00FFFF]Eternal Flame[/color]
  • Hidden location in the world
  • Only [color=#9400D3]Elders[/color] can seek it
  • Reach it to become [color=#00FFFF]Eternal[/color]

[color=#AAAAAA]-- TITLE SYSTEM --[/color]

Prestigious titles grant realm-shaping abilities!

[color=#C0C0C0]Jarl[/color] (Level 50-500) - Chieftain
  • Requires: Jarl's Ring + claim at (0,0)
  • Only ONE at a time
  • Abilities: Banish, Curse, Gift of Silver
  • Lost on death or exceeding Lv500

[color=#FFD700]High King[/color] (Level 200-1000) - Supreme Ruler
  • Requires: Crown of the North + claim at (0,0)
  • Only ONE at a time (replaces Jarl)
  • Abilities: Exile, Knight, Cure, Royal Decree
  • Survives one lethal blow (loses title instead)

[color=#9400D3]Elder[/color] (Level 1000+) - Ancient Wisdom
  • Automatic at level 1000
  • Multiple can exist
  • Abilities: Heal, Seek Flame, Slap
  • Can seek the Eternal Flame

[color=#00FFFF]Eternal[/color] - Immortal Legend
  • Requires: Elder who finds Eternal Flame
  • Up to THREE at a time
  • Has 3 lives (survives death 3x)
  • Abilities: Smite, Restore, Bless, Proclaim

[b][color=#FFD700]═══════════════════════════════════════════════
           SECTION 9: SOCIAL & MISC
═══════════════════════════════════════════════[/color][/b]

[color=#AAAAAA]-- WATCH FEATURE --[/color]

Watch another player's game live!
  watch <name> - Request to watch
  Player presses [%s] approve, [%s] deny
  [Escape] or unwatch to stop

[color=#AAAAAA]-- GAMBLING --[/color]

Dice game at merchants (risky!):
  Roll 3d6 vs merchant's 3d6
  House has slight edge
  Triples pay big! Triple 6s = JACKPOT

[color=#AAAAAA]-- BUG REPORTING --[/color]

  bug <description> - Generate report
  Copy and paste to developer!
""" % [k0, k1, k2, k3, k4, k5, k6, k7, k8, k1, k5, k8, k1, k4, k4, k0, k1, k2]
	display_game(help_text)

func display_game(text: String):
	if game_output:
		game_output.append_text(text + "\n")

var _status_background_active: bool = false

func _set_game_output_background(color: Color):
	"""Set the game output background color (for status page contrast)"""
	if game_output:
		var style = StyleBoxFlat.new()
		style.bg_color = color
		game_output.add_theme_stylebox_override("normal", style)
		_status_background_active = true

func _reset_game_output_background():
	"""Reset game output background to default black"""
	if _status_background_active and game_output:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 1)
		game_output.add_theme_stylebox_override("normal", style)
		_status_background_active = false

func clear_game_output():
	"""Clear game output and reset any special background"""
	_reset_game_output_background()
	if game_output:
		game_output.clear()

func start_combat_animation(text: String, color: String = "#FFFF00"):
	"""Start a combat animation with spinner effect"""
	combat_animation_active = true
	combat_animation_text = text
	combat_animation_color = color
	combat_animation_timer = ANIMATION_DURATION
	combat_spinner_index = 0

func stop_combat_animation():
	"""Stop any active combat animation"""
	combat_animation_active = false
	combat_animation_text = ""
	combat_animation_timer = 0.0

func _build_encounter_text(combat_state: Dictionary) -> String:
	"""Build encounter text with monster name and traits (for client-side art rendering)"""
	var monster_name = combat_state.get("monster_name", "Enemy")
	var monster_level = combat_state.get("monster_level", 1)
	var name_color = combat_state.get("monster_name_color", "#FFFFFF")

	# Build encounter message with colored monster name
	var msg = "[color=#FFD700]You encounter a [/color][color=%s]%s[/color][color=#FFD700] (Lvl %d)![/color]" % [name_color, monster_name, monster_level]

	# Show notable abilities from combat_state
	var abilities = combat_state.get("monster_abilities", [])
	var notable_abilities = []
	if "glass_cannon" in abilities:
		notable_abilities.append("[color=#FF4444]Glass Cannon[/color]")
	if "regeneration" in abilities:
		notable_abilities.append("[color=#00FF00]Regenerates[/color]")
	if "poison" in abilities:
		notable_abilities.append("[color=#FF00FF]Venomous[/color]")
	if "life_steal" in abilities:
		notable_abilities.append("[color=#FF4444]Life Stealer[/color]")
	if "gem_bearer" in abilities:
		notable_abilities.append("[color=#00FFFF]Gem Bearer[/color]")
	if "wish_granter" in abilities:
		notable_abilities.append("[color=#FFD700]Wish Granter[/color]")
	if "weapon_master" in abilities:
		notable_abilities.append("[color=#FF8000]★ WEAPON MASTER ★[/color]")
	if "shield_bearer" in abilities:
		notable_abilities.append("[color=#00FFFF]★ SHIELD GUARDIAN ★[/color]")
	if "arcane_hoarder" in abilities:
		notable_abilities.append("[color=#66CCCC]★ ARCANE HOARDER ★[/color]")
	if "cunning_prey" in abilities:
		notable_abilities.append("[color=#66FF66]★ CUNNING PREY ★[/color]")
	if "corrosive" in abilities:
		notable_abilities.append("[color=#FFFF00]⚠ CORROSIVE ⚠[/color]")
	if "sunder" in abilities:
		notable_abilities.append("[color=#FF4444]⚠ SUNDERING ⚠[/color]")

	if notable_abilities.size() > 0:
		msg += "\n[color=#808080]Traits: %s[/color]" % ", ".join(notable_abilities)

	return msg

func _enhance_combat_message(msg: String) -> String:
	"""Add visual flair and BBCode effects to combat messages"""
	var enhanced = msg
	var upper_msg = msg.to_upper()

	# Critical hit gets shaking text effect - multiple possible formats
	if "CRITICAL" in upper_msg:
		# Try various critical hit text formats
		enhanced = enhanced.replace("CRITICAL HIT", "[shake rate=25 level=8][color=#FF0000]CRITICAL HIT[/color][/shake]")
		enhanced = enhanced.replace("Critical Hit", "[shake rate=25 level=8][color=#FF0000]CRITICAL HIT[/color][/shake]")
		enhanced = enhanced.replace("critical hit", "[shake rate=25 level=8][color=#FF0000]CRITICAL HIT[/color][/shake]")
		enhanced = enhanced.replace("Critical!", "[shake rate=25 level=8][color=#FF0000]CRITICAL![/color][/shake]")
		enhanced = enhanced.replace("CRITICAL!", "[shake rate=25 level=8][color=#FF0000]CRITICAL![/color][/shake]")

	# Devastating/massive damage gets wave effect
	if "DEVASTAT" in upper_msg or "MASSIVE" in upper_msg:
		enhanced = enhanced.replace("Devastating", "[wave amp=30 freq=5][color=#FF4500]Devastating[/color][/wave]")
		enhanced = enhanced.replace("devastating", "[wave amp=30 freq=5][color=#FF4500]devastating[/color][/wave]")
		enhanced = enhanced.replace("Massive", "[wave amp=30 freq=5][color=#FF4500]Massive[/color][/wave]")

	# Monster death gets rainbow effect
	if "DEFEATED" in upper_msg or "SLAIN" in upper_msg or "DIES" in upper_msg:
		enhanced = enhanced.replace("defeated", "[rainbow freq=1.0 sat=0.8 val=0.8]defeated[/rainbow]")
		enhanced = enhanced.replace("Defeated", "[rainbow freq=1.0 sat=0.8 val=0.8]Defeated[/rainbow]")
		enhanced = enhanced.replace("slain", "[rainbow freq=1.0 sat=0.8 val=0.8]slain[/rainbow]")
		enhanced = enhanced.replace("dies", "[rainbow freq=1.0 sat=0.8 val=0.8]dies[/rainbow]")

	# Healing gets pulse effect
	if "HEAL" in upper_msg and ("+" in msg or "RESTORE" in upper_msg):
		enhanced = enhanced.replace("healed", "[pulse freq=2.0 color=#00FF00 ease=-2.0]healed[/pulse]")
		enhanced = enhanced.replace("Healed", "[pulse freq=2.0 color=#00FF00 ease=-2.0]Healed[/pulse]")
		enhanced = enhanced.replace("restored", "[pulse freq=2.0 color=#00FF00 ease=-2.0]restored[/pulse]")

	# Flee success gets fade effect
	if "ESCAPED" in upper_msg or "FLED" in upper_msg:
		enhanced = enhanced.replace("escaped", "[fade start=0 length=10]escaped[/fade]")
		enhanced = enhanced.replace("Escaped", "[fade start=0 length=10]Escaped[/fade]")
		enhanced = enhanced.replace("fled", "[fade start=0 length=10]fled[/fade]")

	# Add impact symbols to large damage numbers
	var regex = RegEx.new()
	regex.compile("(\\d{3,}) damage")  # 3+ digit damage
	var result = regex.search(enhanced)
	if result:
		var dmg_num = result.get_string(1)
		var dmg_int = int(dmg_num)
		if dmg_int >= 10000:
			# Massive damage - wave effect on the number
			enhanced = enhanced.replace(dmg_num + " damage", "[wave amp=20 freq=6][color=#FF0000]" + dmg_num + "[/color][/wave] damage!!!")
		elif dmg_int >= 1000:
			enhanced = enhanced.replace(dmg_num + " damage", "[color=#FF4500]" + dmg_num + "[/color] damage!!")
		elif dmg_int >= 100:
			enhanced = enhanced.replace(dmg_num + " damage", dmg_num + " damage!")

	return enhanced

func _trigger_combat_sounds(msg: String):
	"""Trigger appropriate combat sounds based on message content"""
	var upper_msg = msg.to_upper()

	# Critical hit gets priority - special impactful sound
	if "CRITICAL" in upper_msg:
		play_combat_crit_sound()
		return

	# Player deals damage - check for "deal" or player attacking
	# Messages like "You deal X damage" or "deals X damage"
	if "DEAL" in upper_msg and "DAMAGE" in upper_msg:
		play_combat_hit_sound()
		return

	# Ability use indicators - cast, unleash, invoke, channel
	if "CAST" in upper_msg or "UNLEASH" in upper_msg or "INVOKE" in upper_msg or "CHANNEL" in upper_msg:
		play_combat_ability_sound()
		return

	# Shield/buff activation
	if "SHIELD" in upper_msg or "FORCEFIELD" in upper_msg or "BARRIER" in upper_msg:
		play_combat_ability_sound()
		return

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
	display_game("Services: [%s] Shop | [%s] Quests" % [get_action_key_name(1), get_action_key_name(2)])
	if avail_quests > 0:
		display_game("[color=#00FF00]%d quest(s) available[/color]" % avail_quests)
	if ready_quests > 0:
		display_game("[color=#FFD700]%d quest(s) ready to turn in![/color]" % ready_quests)
	display_game("")
	display_game("[%s] Leave" % get_action_key_name(0))

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
	display_game("Services: [%s] Shop | [%s] Quests" % [get_action_key_name(1), get_action_key_name(2)])
	display_game("")
	display_game("[%s] Leave" % get_action_key_name(0))

# ===== QUEST FUNCTIONS =====

func handle_quest_list(message: Dictionary):
	"""Handle unified quest list from quest giver - shows turn-ins, active, and available"""
	var quest_giver = message.get("quest_giver", "Quest Giver")
	var tp_name = message.get("trading_post", "Trading Post")
	current_quest_tp_id = message.get("trading_post_id", "")
	available_quests = message.get("available_quests", [])
	quests_to_turn_in = message.get("quests_to_turn_in", [])
	active_quests_display = message.get("active_quests", [])
	var active_count = message.get("active_count", 0)
	var max_quests = message.get("max_quests", 5)

	quest_view_mode = true
	update_action_bar()

	game_output.clear()
	display_game("[color=#FFD700]===== %s - %s =====[/color]" % [quest_giver, tp_name])

	# Show area level info if available (from scaled quests)
	var area_level = 0
	if available_quests.size() > 0:
		area_level = available_quests[0].get("area_level", 0)
	elif quests_to_turn_in.size() > 0:
		area_level = quests_to_turn_in[0].get("area_level", 0)

	if area_level > 0:
		display_game("[color=#808080]Area Level: ~%d | Active Quests: %d / %d[/color]" % [area_level, active_count, max_quests])
	else:
		display_game("[color=#808080]Active Quests: %d / %d[/color]" % [active_count, max_quests])
	display_game("")

	var key_index = 0  # Track which key to use next

	# SECTION 1: Quests ready to turn in (highest priority)
	if quests_to_turn_in.size() > 0:
		display_game("[color=#FFD700]=== Ready to Turn In ===[/color]")
		for i in range(quests_to_turn_in.size()):
			var quest = quests_to_turn_in[i]
			var rewards = quest.get("rewards", {})
			var reward_str = _format_rewards(rewards)
			var key_name = get_item_select_key_name(key_index)
			display_game("[%s] [color=#00FF00]✓ %s[/color] - %s" % [key_name, quest.get("name", "Quest"), reward_str])
			key_index += 1
		display_game("")

	# SECTION 2: Your Active Quests (with progress and abandon option)
	if active_quests_display.size() > 0:
		display_game("[color=#00FFFF]=== Your Active Quests ===[/color]")
		for quest in active_quests_display:
			var progress = quest.get("progress", 0)
			var target = quest.get("target", 1)
			var is_complete = quest.get("is_complete", false)
			var quest_tp = quest.get("trading_post", "")

			# Color based on completion and location
			var status_color = "#00FF00" if is_complete else "#FFFF00"
			var turn_in_hint = ""
			if is_complete:
				if quest_tp == current_quest_tp_id:
					turn_in_hint = " [color=#00FF00](Turn in above!)[/color]"
				else:
					turn_in_hint = " [color=#808080](Turn in elsewhere)[/color]"

			display_game("  [color=%s]%s[/color] - %d/%d%s" % [status_color, quest.get("name", "Quest"), progress, target, turn_in_hint])

		display_game("")
		display_game("[color=#808080]To abandon a quest, use [R] Quests from the world map[/color]")
		display_game("")

	# SECTION 3: Available quests to accept
	if available_quests.size() > 0:
		display_game("[color=#00FF00]=== Available Quests ===[/color]")
		for i in range(available_quests.size()):
			var quest = available_quests[i]
			var daily_tag = " [color=#00FFFF][DAILY][/color]" if quest.get("is_daily", false) else ""
			var tier_tag = _get_quest_tier_tag(quest)
			var rewards = quest.get("rewards", {})
			var reward_str = _format_rewards(rewards)
			var key_name = get_item_select_key_name(key_index)
			display_game("[%s] [color=#FFD700]%s[/color]%s%s" % [key_name, quest.get("name", "Quest"), daily_tag, tier_tag])
			display_game("    %s" % quest.get("description", ""))
			display_game("    [color=#00FF00]Rewards: %s[/color]" % reward_str)
			display_game("")
			key_index += 1

	# Show message if nothing available
	if quests_to_turn_in.size() == 0 and available_quests.size() == 0 and active_quests_display.size() == 0:
		display_game("[color=#808080]No quests available at this time.[/color]")

	display_game("")
	display_game("[%s] Back" % get_action_key_name(0))

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

func _get_quest_tier_tag(quest: Dictionary) -> String:
	"""Get a visual tag indicating quest tier/difficulty relative to area level"""
	var tier = quest.get("reward_tier", "")
	var area_level = quest.get("area_level", 0)

	# Color-coded tier tags for visual distinction
	match tier:
		"beginner":
			# Only show EASY tag if we're in a non-beginner area (level > 10)
			if area_level > 10:
				return " [color=#808080][EASY][/color]"
			return ""
		"standard":
			return ""  # Standard quests don't need a tag
		"veteran":
			return " [color=#FFA500][VETERAN][/color]"
		"elite":
			return " [color=#A335EE][ELITE][/color]"
		"legendary":
			return " [color=#FF8000][LEGENDARY][/color]"

	return ""

func _format_wish_description(wish: Dictionary) -> String:
	"""Format a wish option for display"""
	var wish_type = wish.get("type", "unknown")
	match wish_type:
		"gems":
			var amount = wish.get("amount", 0)
			return "[color=#00FFFF]%d Gems[/color] - Precious magical currency" % amount
		"gear":
			var slot = wish.get("slot", "weapon").capitalize()
			var rarity = wish.get("rarity", "common").capitalize()
			var level = wish.get("level", 1)
			var rarity_color = _get_rarity_color(rarity.to_lower())
			return "[color=%s]%s %s[/color] (Lv.%d) - Powerful equipment" % [rarity_color, rarity, slot, level]
		"buff":
			var buff_name = wish.get("buff_name", "Unknown").capitalize().replace("_", " ")
			var duration = wish.get("duration", 10)
			return "[color=#FF00FF]%s[/color] (%d battles) - Magical enhancement" % [buff_name, duration]
		"gold":
			var amount = wish.get("amount", 0)
			return "[color=#FFD700]%d Gold[/color] - A pile of treasure" % amount
		"stat":
			var stat_name = wish.get("stat", "strength").capitalize()
			var amount = wish.get("amount", 1)
			return "[color=#00FF00]+%d %s[/color] - Permanent power increase!" % [amount, stat_name]
		_:
			return "[color=#808080]Unknown Wish[/color]"

func display_monster_select_page():
	"""Display current page of monster selection list"""
	var total_monsters = monster_select_list.size()
	var total_pages = max(1, ceili(float(total_monsters) / MONSTER_SELECT_PAGE_SIZE))
	monster_select_page = clamp(monster_select_page, 0, total_pages - 1)

	game_output.clear()
	display_game("[color=#FF00FF]===== SCROLL OF SUMMONING =====[/color]")
	display_game("[color=#FFD700]Select a creature to summon for your next encounter![/color]")
	display_game("[color=#808080]The chosen monster will appear at your level when you next hunt or move.[/color]")
	display_game("")
	display_game("[color=#808080]Page %d/%d (%d monsters available)[/color]" % [monster_select_page + 1, total_pages, total_monsters])
	display_game("")

	var start_idx = monster_select_page * MONSTER_SELECT_PAGE_SIZE
	var end_idx = min(start_idx + MONSTER_SELECT_PAGE_SIZE, total_monsters)

	for i in range(start_idx, end_idx):
		var monster_name = monster_select_list[i]
		var key_num = i - start_idx + 1
		display_game("[color=#FFFF00][%d][/color] %s" % [key_num, monster_name])

	display_game("")
	display_game("[color=#808080]Press 1-9 or Numpad 1-9 to select a monster[/color]")
	if total_pages > 1:
		display_game("[color=#808080][%s] Prev Page  [%s] Next Page  [%s] Cancel[/color]" % [get_action_key_name(1), get_action_key_name(2), get_action_key_name(0)])
	else:
		display_game("[color=#808080][%s] Cancel[/color]" % get_action_key_name(0))
	update_action_bar()

func select_monster_from_scroll(index: int):
	"""Show confirmation for selected monster"""
	var absolute_idx = monster_select_page * MONSTER_SELECT_PAGE_SIZE + index
	if absolute_idx < 0 or absolute_idx >= monster_select_list.size():
		return

	var monster_name = monster_select_list[absolute_idx]
	monster_select_pending = monster_name
	monster_select_confirm_mode = true

	game_output.clear()
	display_game("[color=#FF00FF]===== CONFIRM SUMMON =====[/color]")
	display_game("")
	display_game("[color=#FFD700]You have selected: [color=#FFFFFF]%s[/color][/color]" % monster_name)
	display_game("")
	display_game("[color=#808080]This creature will appear at your level when you next[/color]")
	display_game("[color=#808080]hunt or move into a non-safe zone.[/color]")
	display_game("")
	display_game("[color=#00FF00][%s] Confirm[/color]  [color=#FF6666][%s] Cancel[/color]" % [get_action_key_name(0), get_action_key_name(1)])
	update_action_bar()

func confirm_monster_select():
	"""Confirm the monster selection and send to server"""
	if monster_select_pending.is_empty():
		cancel_monster_select()
		return

	var monster_name = monster_select_pending
	monster_select_mode = false
	monster_select_confirm_mode = false
	monster_select_pending = ""
	monster_select_list = []
	send_to_server({"type": "monster_select_confirm", "monster_name": monster_name})
	game_output.clear()
	display_game("[color=#FF00FF]The scroll glows brightly![/color]")
	display_game("[color=#FFD700]A %s will appear on your next encounter![/color]" % monster_name)
	update_action_bar()

func cancel_monster_select():
	"""Cancel monster selection"""
	if monster_select_confirm_mode:
		# Go back to selection list
		monster_select_confirm_mode = false
		monster_select_pending = ""
		display_monster_select_page()
		return

	monster_select_mode = false
	monster_select_confirm_mode = false
	monster_select_pending = ""
	monster_select_list = []
	display_game("[color=#808080]The scroll's magic fades unused...[/color]")
	update_action_bar()

func display_target_farm_options():
	"""Display target farming ability options"""
	display_game("")
	display_game("[color=#FF00FF]===== SCROLL OF FINDING =====[/color]")
	display_game("[color=#808080]Choose a trait to hunt for the next %d encounters:[/color]" % target_farm_encounters)
	display_game("")

	for i in range(target_farm_options.size()):
		var ability = target_farm_options[i]
		var display_name = target_farm_names.get(ability, ability)
		display_game("[color=#FFFF00][%d][/color] %s" % [i + 1, display_name])

	display_game("")
	display_game("[color=#808080][%s] Cancel[/color]" % get_action_key_name(0))

func select_target_farm_ability(index: int):
	"""Send selected ability to server"""
	if index < 0 or index >= target_farm_options.size():
		return

	var ability = target_farm_options[index]
	target_farm_mode = false
	target_farm_options = []
	target_farm_names = {}
	send_to_server({"type": "target_farm_select", "ability": ability, "encounters": target_farm_encounters})
	game_output.clear()
	update_action_bar()

func cancel_target_farm():
	"""Cancel target farm selection"""
	target_farm_mode = false
	target_farm_options = []
	target_farm_names = {}
	display_game("[color=#808080]The scroll's magic fades unused...[/color]")
	update_action_bar()

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

	# Go back to Trading Post quest menu if still there
	if at_trading_post:
		display_game("")
		display_game("[%s] Continue" % get_action_key_name(0))
		quest_view_mode = false
		pending_continue = true
		update_action_bar()

func handle_quest_log(message: Dictionary):
	"""Handle quest log display with abandonment option"""
	var log_text = message.get("log", "No quests.")
	var active_count = message.get("active_count", 0)
	var max_quests = message.get("max_quests", 5)
	var active_quests = message.get("active_quests", [])

	# Store quests for abandonment
	quest_log_quests = active_quests
	quest_log_mode = active_quests.size() > 0

	game_output.clear()
	display_game(log_text)
	display_game("")

	if quest_log_mode:
		display_game("[color=#808080]─────────────────────────────────[/color]")
		display_game("[color=#FF4444]Abandon a Quest:[/color]")
		for i in range(quest_log_quests.size()):
			var q = quest_log_quests[i]
			var prog_text = "%d/%d" % [q.get("progress", 0), q.get("target", 1)]
			var key_name = get_item_select_key_name(i)
			display_game("  [color=#FFFF00][%s][/color] %s (%s)" % [key_name, q.get("name", "Unknown"), prog_text])
		display_game("")
		display_game("[color=#808080]Press [%s] to close | Press shown key to abandon quest[/color]" % get_action_key_name(0))
	else:
		display_game("[color=#808080]Press [%s] to continue[/color]" % get_action_key_name(0))

	pending_continue = true
	update_action_bar()

func cancel_quest_action():
	"""Cancel quest selection"""
	quest_view_mode = false
	update_action_bar()

func abandon_quest_by_index(index: int):
	"""Abandon a quest from the quest log by index"""
	if index < 0 or index >= quest_log_quests.size():
		return

	var quest = quest_log_quests[index]
	var quest_id = quest.get("id", "")
	var quest_name = quest.get("name", "Unknown")

	if quest_id == "":
		display_game("[color=#FF0000]Invalid quest selection[/color]")
		return

	# Send abandon request to server
	send_to_server({"type": "quest_abandon", "quest_id": quest_id})

	# Clear the quest log mode
	quest_log_mode = false
	quest_log_quests = []
	pending_continue = false

	display_game("[color=#FFFF00]Abandoning: %s...[/color]" % quest_name)
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
	display_game("[color=#00FF00][%s] Allow[/color]  [color=#FF4444][%s] Deny[/color]" % [get_action_key_name(1), get_action_key_name(2)])
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
	var max_hp = char_data.get("total_max_hp", char_data.get("max_hp", 1))  # Use equipment-boosted HP
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

# ===== BUG REPORTING =====

const BUG_REPORT_PATH = "user://bug_reports.txt"

func generate_bug_report(description: String = ""):
	"""Generate a bug report with client state for troubleshooting"""
	var timestamp = Time.get_datetime_string_from_system(false, true)
	var report_lines = []

	# Header
	report_lines.append("===== BUG REPORT =====")
	report_lines.append("Timestamp: %s" % timestamp)
	report_lines.append("Version: %s" % get_version())

	# Player info
	if has_character:
		var char_name = character_data.get("name", "Unknown")
		var char_level = character_data.get("level", 1)
		var char_race = character_data.get("race", "Unknown")
		var char_class = character_data.get("class", "Unknown")
		report_lines.append("Player: %s (Level %d %s %s)" % [char_name, char_level, char_race, char_class])
		var x = character_data.get("x", 0)
		var y = character_data.get("y", 0)
		report_lines.append("Location: (%d, %d)" % [x, y])
	else:
		report_lines.append("Player: No character loaded")

	# Game state flags
	report_lines.append("")
	report_lines.append("== Client State ==")
	report_lines.append("Game State: %s" % GameState.keys()[game_state])
	report_lines.append("Connected: %s" % str(connected))
	report_lines.append("Has Character: %s" % str(has_character))
	report_lines.append("In Combat: %s" % str(in_combat))
	report_lines.append("Inventory Mode: %s" % str(inventory_mode))
	report_lines.append("Settings Mode: %s" % str(settings_mode))
	report_lines.append("Ability Mode: %s" % str(ability_mode))
	report_lines.append("At Merchant: %s" % str(at_merchant))
	report_lines.append("At Trading Post: %s" % str(at_trading_post))
	report_lines.append("Combat Item Mode: %s" % str(combat_item_mode))
	report_lines.append("Monster Select Mode: %s" % str(monster_select_mode))
	report_lines.append("Flock Pending: %s" % str(flock_pending))
	report_lines.append("Pending Continue: %s" % str(pending_continue))

	# Pending actions
	if pending_inventory_action != "":
		report_lines.append("Pending Inventory Action: %s" % pending_inventory_action)
	if pending_merchant_action != "":
		report_lines.append("Pending Merchant Action: %s" % pending_merchant_action)
	if pending_ability_action != "":
		report_lines.append("Pending Ability Action: %s" % pending_ability_action)
	if rebinding_action != "":
		report_lines.append("Rebinding Action: %s" % rebinding_action)

	# Keybind info (show non-default keybinds)
	var rebound_keys = []
	for key in keybinds:
		if default_keybinds.has(key) and keybinds[key] != default_keybinds[key]:
			rebound_keys.append("%s: %s (was %s)" % [key, get_key_name(keybinds[key]), get_key_name(default_keybinds[key])])
	if rebound_keys.size() > 0:
		report_lines.append("")
		report_lines.append("== Rebound Keys ==")
		for rebound in rebound_keys:
			report_lines.append(rebound)

	# Combat info if in combat
	if in_combat and current_enemy_name != "":
		report_lines.append("")
		report_lines.append("== Combat Info ==")
		report_lines.append("Enemy: %s (Level %d)" % [current_enemy_name, current_enemy_level])
		report_lines.append("Enemy HP: %d / %d" % [current_enemy_hp, current_enemy_max_hp])
		report_lines.append("Damage Dealt: %d" % damage_dealt_to_current_enemy)

	# Player resources if has character
	if has_character:
		report_lines.append("")
		report_lines.append("== Resources ==")
		report_lines.append("HP: %d / %d" % [character_data.get("current_hp", 0), character_data.get("total_max_hp", character_data.get("max_hp", 0))])
		report_lines.append("Mana: %d / %d" % [character_data.get("current_mana", 0), character_data.get("total_max_mana", character_data.get("max_mana", 0))])
		report_lines.append("Stamina: %d / %d" % [character_data.get("current_stamina", 0), character_data.get("max_stamina", 0)])
		report_lines.append("Energy: %d / %d" % [character_data.get("current_energy", 0), character_data.get("max_energy", 0)])
		report_lines.append("Gold: %d | Gems: %d" % [character_data.get("gold", 0), character_data.get("gems", 0)])

		# Active buffs
		var active_buffs = character_data.get("active_buffs", [])
		var persistent_buffs = character_data.get("persistent_buffs", [])
		if active_buffs.size() > 0 or persistent_buffs.size() > 0:
			report_lines.append("")
			report_lines.append("== Active Buffs ==")
			for buff in active_buffs:
				report_lines.append("- %s: +%d (%d rounds)" % [buff.get("type", "?"), buff.get("value", 0), buff.get("rounds", 0)])
			for buff in persistent_buffs:
				report_lines.append("- %s: +%d (%d battles)" % [buff.get("type", "?"), buff.get("value", 0), buff.get("battles", 0)])

	# Description
	report_lines.append("")
	report_lines.append("== Bug Description ==")
	if description != "":
		report_lines.append(description)
	else:
		report_lines.append("[No description provided - use: bug <description>]")

	report_lines.append("===== END REPORT =====")
	report_lines.append("")

	var report_text = "\n".join(report_lines)

	# Save to file
	var file = FileAccess.open(BUG_REPORT_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(BUG_REPORT_PATH) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_string(report_text + "\n")
		file.close()

	# Display to user
	display_game("[color=#FFD700]===== BUG REPORT GENERATED =====[/color]")
	display_game("[color=#808080]Saved to: %s[/color]" % ProjectSettings.globalize_path(BUG_REPORT_PATH))
	display_game("")
	display_game("[color=#00FFFF]Copy the report below and paste it to Claude:[/color]")
	display_game("")
	for line in report_lines:
		if line.begins_with("====="):
			display_game("[color=#FFD700]%s[/color]" % line)
		elif line.begins_with("=="):
			display_game("[color=#00FF00]%s[/color]" % line)
		else:
			display_game("[color=#FFFFFF]%s[/color]" % line)

func get_version() -> String:
	"""Get current game version from VERSION.txt"""
	if FileAccess.file_exists("res://VERSION.txt"):
		var file = FileAccess.open("res://VERSION.txt", FileAccess.READ)
		if file:
			var version = file.get_line().strip_edges()
			file.close()
			return version
	return "Unknown"

# ===== TITLE SYSTEM =====

func handle_title_menu(message: Dictionary):
	"""Handle title menu data from server"""
	title_menu_data = message
	title_mode = true
	title_ability_mode = false
	title_target_mode = false
	title_broadcast_mode = false
	pending_title_ability = ""
	title_online_players = message.get("online_players", [])
	display_title_menu()
	update_action_bar()

func display_title_menu():
	"""Display the title menu"""
	game_output.clear()

	var current_title = title_menu_data.get("current_title", "")
	var claimable = title_menu_data.get("claimable", [])
	var abilities = title_menu_data.get("abilities", {})

	display_game("[color=#FFD700]===== TITLE MENU =====[/color]")
	display_game("")

	# Show current title
	if current_title.is_empty():
		display_game("[color=#808080]You hold no title.[/color]")
	else:
		var title_info = _get_title_display_info(current_title)
		display_game("Current Title: [color=%s]%s[/color]" % [title_info.color, title_info.name])

		# Show Eternal lives if applicable
		if current_title == "eternal":
			var lives = title_menu_data.get("title_data", {}).get("lives", 3)
			display_game("Lives remaining: [color=#00FFFF]%d[/color]" % lives)

		# Show realm treasury for Jarl
		if current_title == "jarl":
			var treasury = title_menu_data.get("realm_treasury", 0)
			display_game("Realm Treasury: [color=#FFD700]%d gold[/color]" % treasury)

	display_game("")

	# Show claimable titles
	if not claimable.is_empty():
		display_game("[color=#00FF00]Available Titles:[/color]")
		var idx = 1
		for title in claimable:
			display_game("  [%d] %s" % [idx, title.get("name", "Unknown")])
			idx += 1
		display_game("")

	# Show abilities
	if not abilities.is_empty():
		display_game("[color=#00FFFF]Title Abilities:[/color]")
		var idx = 1
		for ability_id in abilities.keys():
			var ability = abilities[ability_id]
			var cost_text = ""
			if ability.get("cost", 0) > 0:
				var resource = ability.get("resource", "mana")
				if resource == "mana_percent":
					cost_text = " (%d%% Mana)" % ability.cost
				elif resource == "gems":
					cost_text = " (%d Gems)" % ability.cost
				elif resource == "lives":
					cost_text = " (%d Lives)" % ability.cost
				else:
					cost_text = " (%d %s)" % [ability.cost, resource.capitalize()]
			display_game("  [%s] %s%s - %s" % [get_action_key_name(idx), ability.get("name", ability_id), cost_text, ability.get("description", "")])
			idx += 1
		display_game("")

	display_game("[color=#808080]Press [%s] to exit[/color]" % get_action_key_name(0))

func handle_title_key_input(key: int) -> bool:
	"""Handle key input in title mode. Returns true if handled."""
	if not title_mode:
		return false

	if title_broadcast_mode:
		# Wait for text input from command line
		return true

	if title_target_mode:
		# Handle target selection
		if key == KEY_SPACE:
			# Cancel target selection
			title_target_mode = false
			pending_title_ability = ""
			display_title_menu()
			update_action_bar()
			return true

		var target_idx = _key_to_selection_index(key)
		if target_idx >= 0 and target_idx < title_online_players.size():
			var target_name = title_online_players[target_idx]
			send_to_server({
				"type": "title_ability",
				"ability": pending_title_ability,
				"target": target_name
			})
			title_target_mode = false
			title_mode = false
			pending_title_ability = ""
			update_action_bar()
			return true
		return true

	# Space to exit
	if key == KEY_SPACE:
		title_mode = false
		title_ability_mode = false
		display_game("")
		update_action_bar()
		return true

	var claimable = title_menu_data.get("claimable", [])
	var abilities = title_menu_data.get("abilities", {})

	# Number keys for claiming titles
	if not claimable.is_empty():
		var idx = _key_to_selection_index(key)
		if idx >= 0 and idx < claimable.size():
			var title_to_claim = claimable[idx]
			send_to_server({"type": "claim_title", "title": title_to_claim.get("id", "")})
			title_mode = false
			return true

	# Q/W/E/R keys for abilities (if has title)
	if not abilities.is_empty():
		var ability_keys = [KEY_Q, KEY_W, KEY_E, KEY_R]
		var ability_idx = ability_keys.find(key)
		if ability_idx >= 0:
			var ability_ids = abilities.keys()
			if ability_idx < ability_ids.size():
				var ability_id = ability_ids[ability_idx]
				var ability = abilities[ability_id]

				# Check if ability needs target
				if ability.get("target", "self") == "player":
					# Enter target selection mode
					pending_title_ability = ability_id
					title_target_mode = true
					_display_target_selection()
					update_action_bar()
					return true

				# Check if ability is a broadcast (royal_decree, proclaim)
				if ability_id in ["royal_decree", "proclaim"]:
					title_broadcast_mode = true
					pending_title_ability = ability_id
					display_game("")
					display_game("[color=#FFD700]Enter your message:[/color]")
					if input_field:
						input_field.placeholder_text = "Type your message and press Enter"
						input_field.grab_focus()
					return true

				# Self-target ability, use immediately
				send_to_server({
					"type": "title_ability",
					"ability": ability_id
				})
				title_mode = false
				update_action_bar()
				return true

	return true

func _display_target_selection():
	"""Display list of online players for targeting"""
	game_output.clear()
	display_game("[color=#FFD700]Select a target:[/color]")
	display_game("")

	if title_online_players.is_empty():
		display_game("[color=#808080]No other players online.[/color]")
	else:
		for i in range(title_online_players.size()):
			if i < 9:
				display_game("  [%d] %s" % [i + 1, title_online_players[i]])

	display_game("")
	display_game("[color=#808080]Press [%s] to cancel[/color]" % get_action_key_name(0))

func process_title_broadcast(text: String):
	"""Process broadcast text input for royal_decree or proclaim"""
	if not title_broadcast_mode or pending_title_ability.is_empty():
		return

	send_to_server({
		"type": "title_ability",
		"ability": pending_title_ability,
		"broadcast_text": text
	})

	title_broadcast_mode = false
	title_mode = false
	pending_title_ability = ""
	update_action_bar()

func open_title_menu():
	"""Request title menu from server"""
	send_to_server({"type": "get_title_menu"})
