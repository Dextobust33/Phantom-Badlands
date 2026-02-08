# client.gd
# Client with account system, character selection, and permadeath handling
extends Control

# Monster art helper - loaded lazily to avoid initialization issues
var _monster_art_script = null
func _get_monster_art():
	if _monster_art_script == null:
		_monster_art_script = load("res://client/monster_art.gd")
	return _monster_art_script

# Trader art helper - for wandering NPCs (blacksmith, healer)
var _trader_art_script = null
func _get_trader_art():
	if _trader_art_script == null:
		_trader_art_script = load("res://client/trader_art.gd")
	return _trader_art_script

# Trading post art helper - for trading post buildings
var _trading_post_art_script = null
func _get_trading_post_art():
	if _trading_post_art_script == null:
		_trading_post_art_script = load("res://client/trading_post_art.gd")
	return _trading_post_art_script

# Character script for thematic item display
const CharacterScript = preload("res://shared/character.gd")

func _recolor_ascii_art(art: String, new_color: String) -> String:
	"""Replace ALL color tags in ASCII art with a new color for variety"""
	# ASCII art uses [color=#HEXCODE]...[/color] format
	# Replace all color tags with the new color using regex substitution
	var color_regex = RegEx.new()
	color_regex.compile("\\[color=#[0-9A-Fa-f]{6}\\]")
	var new_tag = "[color=%s]" % new_color
	return color_regex.sub(art, new_tag, true)  # true = replace all matches

func _recolor_ascii_art_pattern(art: String, color1: String, color2: String, pattern: String) -> String:
	"""Apply pattern-based coloring to ASCII art for visual variety.
	Patterns: solid, gradient_down, gradient_up, middle, striped, edges,
	          diagonal_down, diagonal_up, split_v, checker, radial

	NOTE: Art from monster_art.gd has structure: [color=#XXX] on first line,
	art text on middle lines, [/color] on last line. We must wrap each line
	in its own color tags for patterns to work."""
	# Safety check - if color2 is empty or pattern is solid, use simple recolor
	if pattern == "solid" or color2 == "" or color2 == null:
		return _recolor_ascii_art(art, color1)

	# Split art into lines for pattern application
	var lines = art.split("\n")
	var total_lines = lines.size()
	if total_lines == 0:
		return art

	# Strip opening/closing color tags from art structure
	# Art format: line 0 = "[color=#XXXXXX]", lines 1-N = art, last line = "[/color]"
	var art_lines = []
	var tag_regex = RegEx.new()
	tag_regex.compile("\\[/?color[^\\]]*\\]")

	for line in lines:
		# Strip any color tags from the line to get raw art
		var stripped = tag_regex.sub(line, "", true)
		if stripped.strip_edges() != "" or stripped.length() > 5:  # Keep non-empty lines and lines with whitespace
			art_lines.append(stripped)

	total_lines = art_lines.size()
	if total_lines == 0:
		return art

	# Find max line width for diagonal/horizontal patterns
	var max_width = 1
	for line in art_lines:
		max_width = max(max_width, line.length())

	var result_lines = []
	var center = max(1.0, total_lines / 2.0)

	for i in range(total_lines):
		var line = art_lines[i]
		var use_color = color1

		match pattern:
			"gradient_down":
				# Top half = color1, bottom half = color2
				if i >= total_lines / 2:
					use_color = color2
			"gradient_up":
				# Bottom half = color1, top half = color2
				if i < total_lines / 2:
					use_color = color2
			"middle":
				# Outer thirds = color1, middle third = color2
				var third = max(1, total_lines / 3)
				if i >= third and i < total_lines - third:
					use_color = color2
			"striped":
				# Alternating every 3-4 lines
				if (i / 3) % 2 == 1:
					use_color = color2
			"edges":
				# First 15% and last 15% = color2, middle = color1
				var edge_size = max(2, total_lines / 7)
				if i < edge_size or i >= total_lines - edge_size:
					use_color = color2
			"diagonal_down":
				# Diagonal from top-left to bottom-right - process per character
				result_lines.append(_recolor_line_diagonal_raw(line, color1, color2, i, total_lines, max_width, true))
				continue
			"diagonal_up":
				# Diagonal from bottom-left to top-right - process per character
				result_lines.append(_recolor_line_diagonal_raw(line, color1, color2, i, total_lines, max_width, false))
				continue
			"split_v":
				# Vertical split - left half color1, right half color2
				result_lines.append(_recolor_line_split_vertical_raw(line, color1, color2, max_width))
				continue
			"checker":
				# Checkerboard pattern based on line groups
				if ((i / 5) + (i % 2)) % 2 == 1:
					use_color = color2
			"radial":
				# Center bright, edges darker - approximated by distance from middle row
				var dist = abs(float(i) - center) / center
				if dist > 0.5:
					use_color = color2
			"thirds":
				# Three horizontal bands: color1 / color2 / color1
				var third = max(1, total_lines / 3)
				if i >= third and i < total_lines - third:
					use_color = color2
				# Same as middle but swapped colors conceptually
			"bands":
				# Thick alternating horizontal bands (5-6 lines each)
				if (i / 5) % 2 == 1:
					use_color = color2
			"columns":
				# Vertical stripes - process per character
				result_lines.append(_recolor_line_columns_raw(line, color1, color2, max_width))
				continue
			"corners":
				# Corners in color2, center in color1
				var corner_size = max(3, total_lines / 4)
				if i < corner_size or i >= total_lines - corner_size:
					# Top or bottom section - use per-char coloring for corners
					result_lines.append(_recolor_line_corners_raw(line, color1, color2, max_width, i, total_lines))
					continue
			"cross":
				# X pattern through center - per character
				result_lines.append(_recolor_line_cross_raw(line, color1, color2, i, total_lines, max_width))
				continue
			"wave":
				# Wavy horizontal pattern based on sine
				var wave_offset = int(sin(float(i) * 0.5) * (max_width * 0.15))
				result_lines.append(_recolor_line_wave_raw(line, color1, color2, max_width, wave_offset))
				continue
			"scatter":
				# Pseudo-random scatter based on position
				result_lines.append(_recolor_line_scatter_raw(line, color1, color2, i))
				continue
			"ring":
				# Ring pattern - edges and very center are color2, middle ring is color1
				var dist_from_center = abs(float(i) - center) / center
				if dist_from_center > 0.7 or dist_from_center < 0.2:
					use_color = color2
			"fade":
				# Gradual 3-step fade from color1 to mixed to color2
				var section = int(float(i) / float(total_lines) * 3)
				if section == 1:
					# Middle section - alternate between colors
					use_color = color1 if i % 2 == 0 else color2
				elif section >= 2:
					use_color = color2

		# Wrap the raw art line in color tags
		result_lines.append("[color=%s]%s[/color]" % [use_color, line])

	return "\n".join(result_lines)

func _recolor_line_diagonal_raw(line: String, color1: String, color2: String, row: int, total_rows: int, max_width: int, down: bool) -> String:
	"""Recolor a raw art line (no existing tags) with diagonal pattern.
	Splits line at diagonal threshold, wrapping each section in color tags."""
	# Calculate where the diagonal crosses this row
	var threshold: int
	if down:
		# Top-left to bottom-right: threshold increases with row
		threshold = int((float(row) / float(max(1, total_rows))) * max_width)
	else:
		# Bottom-left to top-right: threshold decreases with row
		threshold = int((1.0 - float(row) / float(max(1, total_rows))) * max_width)

	# Split line at threshold
	if threshold <= 0:
		return "[color=%s]%s[/color]" % [color2, line]
	elif threshold >= line.length():
		return "[color=%s]%s[/color]" % [color1, line]
	else:
		var left = line.substr(0, threshold)
		var right = line.substr(threshold)
		return "[color=%s]%s[/color][color=%s]%s[/color]" % [color1, left, color2, right]

func _recolor_line_split_vertical_raw(line: String, color1: String, color2: String, max_width: int) -> String:
	"""Recolor a raw art line (no existing tags) with vertical split.
	Left half = color1, right half = color2."""
	var threshold = max_width / 2

	if threshold <= 0:
		return "[color=%s]%s[/color]" % [color2, line]
	elif threshold >= line.length():
		return "[color=%s]%s[/color]" % [color1, line]
	else:
		var left = line.substr(0, threshold)
		var right = line.substr(threshold)
		return "[color=%s]%s[/color][color=%s]%s[/color]" % [color1, left, color2, right]

func _recolor_line_columns_raw(line: String, color1: String, color2: String, max_width: int) -> String:
	"""Recolor a raw art line with vertical stripes (alternating columns)."""
	var stripe_width = max(5, max_width / 8)  # 8 stripes across
	var result = ""
	var current_color = color1
	var col_count = 0

	for c in line:
		if col_count % stripe_width == 0:
			if result != "":
				result += "[/color]"
			current_color = color1 if (col_count / stripe_width) % 2 == 0 else color2
			result += "[color=%s]" % current_color
		result += c
		col_count += 1

	if result != "":
		result += "[/color]"
	return result

func _recolor_line_corners_raw(line: String, color1: String, color2: String, max_width: int, row: int, total_rows: int) -> String:
	"""Recolor a raw art line for corner pattern - corners are color2."""
	var corner_h = max(3, total_rows / 4)
	var corner_w = max(10, max_width / 4)
	var is_top = row < corner_h
	var is_bottom = row >= total_rows - corner_h

	if not is_top and not is_bottom:
		return "[color=%s]%s[/color]" % [color1, line]

	# Color corners only
	var result = ""
	for i in range(line.length()):
		var is_left_corner = i < corner_w
		var is_right_corner = i >= max_width - corner_w
		var use_color = color2 if (is_left_corner or is_right_corner) else color1
		result += "[color=%s]%s[/color]" % [use_color, line[i]]
	return result

func _recolor_line_cross_raw(line: String, color1: String, color2: String, row: int, total_rows: int, max_width: int) -> String:
	"""Recolor a raw art line with X/cross pattern through center."""
	# Calculate both diagonal thresholds
	var threshold_down = int((float(row) / float(max(1, total_rows))) * max_width)
	var threshold_up = int((1.0 - float(row) / float(max(1, total_rows))) * max_width)

	var result = ""
	for i in range(line.length()):
		# Check if near either diagonal
		var near_down = abs(i - threshold_down) < 8
		var near_up = abs(i - threshold_up) < 8
		var use_color = color2 if (near_down or near_up) else color1
		result += "[color=%s]%s[/color]" % [use_color, line[i]]
	return result

func _recolor_line_wave_raw(line: String, color1: String, color2: String, max_width: int, wave_offset: int) -> String:
	"""Recolor a raw art line with wave pattern - threshold shifts by wave offset."""
	var threshold = (max_width / 2) + wave_offset

	if threshold <= 0:
		return "[color=%s]%s[/color]" % [color2, line]
	elif threshold >= line.length():
		return "[color=%s]%s[/color]" % [color1, line]
	else:
		var left = line.substr(0, threshold)
		var right = line.substr(threshold)
		return "[color=%s]%s[/color][color=%s]%s[/color]" % [color1, left, color2, right]

func _recolor_line_scatter_raw(line: String, color1: String, color2: String, row: int) -> String:
	"""Recolor a raw art line with pseudo-random scatter pattern."""
	var result = ""
	for i in range(line.length()):
		# Pseudo-random based on position (deterministic so same pattern each render)
		var hash_val = (row * 31 + i * 17) % 100
		var use_color = color2 if hash_val < 25 else color1  # ~25% scatter
		result += "[color=%s]%s[/color]" % [use_color, line[i]]
	return result

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

# UI Scale settings (multipliers on top of automatic resolution scaling)
var ui_scale_monster_art: float = 1.0  # Monster ASCII art in combat
var ui_scale_map: float = 1.0          # World map display
var ui_scale_game_output: float = 1.0  # Main game text output
var ui_scale_buttons: float = 1.0      # Action bar buttons
var ui_scale_chat: float = 1.0         # Chat and online players
var ui_scale_right_panel: float = 1.0  # Right panel stats, map controls, send/bug buttons

# Keybind configuration
var default_keybinds = {
	# Action bar (10 slots total)
	"action_0": KEY_SPACE,  # Primary action
	"action_1": KEY_Q,
	"action_2": KEY_W,
	"action_3": KEY_E,
	"action_4": KEY_R,
	"action_5": KEY_1,      # Extended action bar (shares with item keys intentionally)
	"action_6": KEY_2,
	"action_7": KEY_3,
	"action_8": KEY_4,
	"action_9": KEY_5,
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

# Inventory comparison stat setting (what the ↑↓ arrows compare)
var inventory_compare_stat: String = "level"  # Options: level, hp, atk, def, wit, mana, speed, str, con, dex, int, wis
const COMPARE_STAT_OPTIONS = ["level", "hp", "atk", "def", "wit", "mana", "stamina", "energy", "speed", "str", "con", "dex", "int", "wis"]
var sort_menu_page: int = 0  # 0 = main sorts, 1 = more options (rarity, compare)

# Combat action bar swap settings (per-client)
var swap_attack_outsmart: bool = false  # Swap Attack (slot 0) with Outsmart (slot 3)

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
	HOUSE_SCREEN,      # Roguelite home screen between login and character select
	CHARACTER_SELECT,
	PLAYING,
	DEAD
}
var game_state = GameState.DISCONNECTED

# UI References - Main game
@onready var game_output = $RootContainer/MainContainer/LeftPanel/GameOutputContainer/GameOutput
@onready var game_output_container = $RootContainer/MainContainer/LeftPanel/GameOutputContainer
@onready var buff_display_label = $RootContainer/MainContainer/LeftPanel/GameOutputContainer/BuffDisplayLabel
@onready var companion_art_overlay = $RootContainer/MainContainer/LeftPanel/GameOutputContainer/CompanionArtOverlay
@onready var chat_output = $RootContainer/MainContainer/LeftPanel/ChatOutput
@onready var map_display = $RootContainer/MainContainer/RightPanel/MapDisplay
@onready var input_field = $RootContainer/BottomBar/InputField
@onready var send_button = $RootContainer/BottomBar/SendButton
@onready var bug_button = $RootContainer/BottomBar/BugButton
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
@onready var char_select_sanctuary_button = $CharacterSelectPanel/VBox/AccountContainer/SanctuaryButton
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
var ability_popup_active: bool = false  # Flag to track popup state for input handling

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

# UI References - Upgrade Popup (created dynamically)
var upgrade_popup: Panel = null
var upgrade_popup_title: Label = null
var upgrade_popup_item_label: Label = null
var upgrade_popup_gold_label: Label = null
var upgrade_popup_cost_label: Label = null
var upgrade_popup_input: LineEdit = null
var upgrade_popup_btn_1: Button = null
var upgrade_popup_btn_5: Button = null
var upgrade_popup_btn_10: Button = null
var upgrade_popup_btn_max: Button = null
var upgrade_popup_confirm: Button = null
var upgrade_popup_cancel: Button = null
var upgrade_pending_slot: String = ""
var upgrade_max_affordable: int = 0

# UI References - Teleport Popup (created dynamically)
var teleport_popup: Panel = null
var teleport_popup_title: Label = null
var teleport_popup_resource_label: Label = null
var teleport_popup_cost_label: Label = null
var teleport_popup_x_input: LineEdit = null
var teleport_popup_y_input: LineEdit = null
var teleport_popup_confirm: Button = null
var teleport_popup_cancel: Button = null
var teleport_mode: bool = false

# Account data
var username = ""
var account_id = ""
var character_list = []
var can_create_character = true
var last_whisper_from = ""  # For /reply command

# House (Sanctuary) data - roguelite meta-progression
var house_data: Dictionary = {}
var house_mode: String = ""  # "", "main", "storage", "companions", "upgrades"
var pending_house_action: String = ""  # For sub-menus like withdraw_select, checkout_select, etc.
var house_storage_page: int = 0
var house_upgrades_page: int = 0  # 0=Base, 1=Combat, 2=Stats
var house_storage_withdraw_items: Array = []  # Items to withdraw on character creation
var house_checkout_companion_slot: int = -1  # Companion slot to checkout on character creation
var house_storage_discard_index: int = -1  # Item index selected for discard
var house_storage_register_index: int = -1  # Stored companion index selected to register to kennel
var house_unregister_companion_slot: int = -1  # Companion slot to unregister (move to storage)

# House grid system - player moves in ASCII house
var house_player_x: int = 4  # Player X position in house grid
var house_player_y: int = 3  # Player Y position in house grid
var house_interactable_at: String = ""  # What interactable the player is standing on

# House tile characters (simple ASCII for uniform spacing)
const HOUSE_TILE_FLOOR = " "
const HOUSE_TILE_WALL_H = "-"
const HOUSE_TILE_WALL_V = "|"
const HOUSE_TILE_CORNER = "+"
const HOUSE_TILE_COMPANION = "C"  # Companion slot
const HOUSE_TILE_STORAGE = "S"    # Storage chest
const HOUSE_TILE_UPGRADE = "U"    # Upgrades altar
const HOUSE_TILE_EXIT = "D"       # Door/Exit to play
const HOUSE_TILE_PLAYER = "@"     # Player marker

# House layouts by upgrade level (array of strings, each string is a row)
# Legend: # = wall, . = floor, C = companion slot, S = storage, U = upgrades, D = door
# Player spawn is always in center of floor area
# C tiles match base capacity (2) + companion_slots upgrades can add more
const HOUSE_LAYOUTS = {
	0: [  # Starter cottage (9 wide x 6 tall) - 2 companion slots
		"#########",
		"#  C C  #",
		"#       #",
		"#       #",
		"# S   U #",
		"####D####"
	],
	1: [  # Small house (11 wide x 7 tall) - 3 companion slots
		"###########",
		"#  C C C  #",
		"#         #",
		"#         #",
		"#         #",
		"# S     U #",
		"#####D#####"
	],
	2: [  # Medium house (13 wide x 8 tall) - 4 companion slots
		"#############",
		"#  C C C C  #",
		"#           #",
		"#           #",
		"#           #",
		"#           #",
		"# S       U #",
		"######D######"
	],
	3: [  # Large house (15 wide x 9 tall) - 5 companion slots
		"###############",
		"#  C C C C C  #",
		"#             #",
		"#             #",
		"#             #",
		"#             #",
		"#             #",
		"# S         U #",
		"#######D#######"
	]
}

# Character data
var character_data = {}
var has_character = false
var last_move_time = 0.0
const MOVE_COOLDOWN = 0.5
const MAP_BASE_FONT_SIZE = 14  # Base font size at 720p height
const MAP_MIN_FONT_SIZE = 10
const MAP_MAX_FONT_SIZE = 64  # Allow larger scaling for 4K
const GAME_OUTPUT_BASE_FONT_SIZE = 14
const GAME_OUTPUT_MIN_FONT_SIZE = 10
const GAME_OUTPUT_MAX_FONT_SIZE = 56  # Allow larger scaling for 4K
const BUTTON_BASE_FONT_SIZE = 11  # Base font size for action bar buttons at 720p
const BUTTON_MIN_FONT_SIZE = 9
const BUTTON_MAX_FONT_SIZE = 44
const CHAT_BASE_FONT_SIZE = 12  # Base size for chat at 720p
const CHAT_MIN_FONT_SIZE = 10
const CHAT_MAX_FONT_SIZE = 48

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
# resource = 60% of healing for all classes
const CONSUMABLE_TIERS = {
	1: {"name": "Minor", "healing": 50, "buff_value": 3, "resource": 30, "forcefield_value": 1500},
	2: {"name": "Lesser", "healing": 100, "buff_value": 5, "resource": 60, "forcefield_value": 2500},
	3: {"name": "Standard", "healing": 200, "buff_value": 8, "resource": 120, "forcefield_value": 4000},
	4: {"name": "Greater", "healing": 400, "buff_value": 12, "resource": 240, "forcefield_value": 6000},
	5: {"name": "Superior", "healing": 800, "buff_value": 18, "resource": 480, "forcefield_value": 10000},
	6: {"name": "Master", "healing": 1600, "buff_value": 25, "resource": 960, "forcefield_value": 15000},
	7: {"name": "Divine", "healing": 3000, "buff_value": 35, "resource": 1800, "forcefield_value": 25000}
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
var ability_choice_page: int = 0  # Page for ability selection (0-indexed)
const ABILITY_PAGE_SIZE: int = 9  # Abilities per page (keys 1-9)

# Pending continue state (prevents output clearing until player acknowledges)
var pending_continue: bool = false
var pending_dungeon_continue: bool = false  # Request fresh dungeon state when continuing
var queued_combat_message: Dictionary = {}  # Combat that arrived during pending_continue (e.g., egg hatching)
var queued_dungeon_complete: Dictionary = {}  # Dungeon completion that arrived during pending_continue (e.g., after boss kill)

# Wandering NPC encounter states
var pending_blacksmith: bool = false
var blacksmith_items: Array = []  # Items available to repair
var blacksmith_repair_all_cost: int = 0
var blacksmith_can_upgrade: bool = false
var blacksmith_upgrade_mode: String = ""  # "", "select_item", "select_affix"
var blacksmith_upgrade_items: Array = []  # Items available for upgrade
var blacksmith_upgrade_affixes: Array = []  # Affixes available on selected item
var blacksmith_upgrade_item_name: String = ""  # Name of selected item
var blacksmith_trader_art: String = ""  # Persisted ASCII art for the encounter
var pending_healer: bool = false
var healer_costs: Dictionary = {}  # quick_heal_cost, full_heal_cost, cure_all_cost

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

# Crafting mode (only at trading posts)
var crafting_mode: bool = false
var crafting_skill: String = ""  # "blacksmithing", "alchemy", "enchanting"
var crafting_recipes: Array = []  # Available recipes from server
var crafting_materials: Dictionary = {}  # Player's materials
var crafting_skill_level: int = 1  # Current skill level
var crafting_post_bonus: int = 0  # Trading post specialization bonus
var crafting_selected_recipe: int = -1  # Index of selected recipe
var crafting_page: int = 0  # Page for recipe list
var awaiting_craft_result: bool = false  # Waiting for player to acknowledge craft result
const CRAFTING_PAGE_SIZE = 5

# More menu mode
var more_mode: bool = false

# Companions mode
var companions_mode: bool = false
var companions_page: int = 0
var pending_companion_action: String = ""  # "", "release_select", "release_confirm", "release_all_warn", "release_all_confirm", "inspect"
var release_target_companion: Dictionary = {}  # Companion being released
var inspecting_companion: Dictionary = {}  # Companion being inspected
const COMPANIONS_PAGE_SIZE = 5
var companion_sort_option: String = "level"  # Sort options: "level", "tier", "variant", "damage", "name", "type"
var companion_sort_ascending: bool = false  # false = descending (highest first)

# Eggs mode (separate page from companions)
var eggs_mode: bool = false
var eggs_page: int = 0
const EGGS_PAGE_SIZE = 3  # Fewer per page since eggs have ASCII art

# Water/Fishing location
var at_water: bool = false  # Whether player is at a fishable water tile

# Ore/Mining location
var at_ore_deposit: bool = false  # Whether player is at a mineable ore deposit
var ore_tier: int = 1  # Tier of the ore deposit (1-9)

# Forest/Logging location
var at_dense_forest: bool = false  # Whether player is at a harvestable forest
var wood_tier: int = 1  # Tier of the wood (1-6)

# Dungeon entrance location
var at_dungeon_entrance: bool = false  # Whether player is at a dungeon entrance
var dungeon_entrance_info: Dictionary = {}  # Info about the dungeon at this location
var pending_dungeon_warning: Dictionary = {}  # Pending dungeon entry warning awaiting confirmation

# Corpse location
var at_corpse: bool = false  # Whether player is at a corpse
var corpse_info: Dictionary = {}  # Info about the corpse at this location
var pending_corpse_loot: Dictionary = {}  # Pending corpse loot awaiting confirmation

# Watch/Inspect mode - observe another player's game output
var watching_player: String = ""  # Name of player we're watching (empty = not watching)
var watch_request_pending: String = ""  # Player who requested to watch us (waiting for approval)
var watchers: Array = []  # Players currently watching us

# Trading mode - trade items with another player
var in_trade: bool = false
var trade_partner_name: String = ""
var trade_partner_class: String = ""
var trade_my_items: Array = []  # Inventory indices of items I'm offering
var trade_partner_items: Array = []  # Items partner is offering (full item data)
var trade_my_companions: Array = []  # Companion indices I'm offering
var trade_my_companions_data: Array = []  # Full companion data for display
var trade_partner_companions: Array = []  # Companions partner is offering (full data)
var trade_my_eggs: Array = []  # Egg indices I'm offering
var trade_my_eggs_data: Array = []  # Full egg data for display
var trade_partner_eggs: Array = []  # Eggs partner is offering (full data)
var trade_my_ready: bool = false
var trade_partner_ready: bool = false
var pending_trade_request: String = ""  # Name of player requesting to trade with us
var trade_pending_add: bool = false  # Waiting for player to select item to add
var trade_tab: String = "items"  # Current trade tab: "items", "companions", "eggs"
var trade_pending_add_companion: bool = false  # Waiting for companion selection
var trade_pending_add_egg: bool = false  # Waiting for egg selection

# Summon consent system
var pending_summon_from: String = ""  # Name of Jarl requesting to summon us
var pending_summon_location: Vector2i = Vector2i(0, 0)  # Location we'd be summoned to

# Bless stat selection
var title_stat_selection_mode: bool = false  # Waiting for stat selection for Bless
var pending_bless_target: String = ""  # Target player for Bless

# Font size constants for responsive scaling (main constants defined near line 520)
const ONLINE_PLAYERS_BASE_FONT_SIZE = 11  # Base size at 720p

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

# Home Stone selection mode
var home_stone_mode: bool = false
var home_stone_type: String = ""
var home_stone_options: Array = []

# Title system mode
var title_mode: bool = false  # Whether in title menu
var title_menu_data: Dictionary = {}  # Title menu data from server
var title_ability_mode: bool = false  # Whether selecting an ability
var title_target_mode: bool = false  # Whether selecting a target for ability
var pending_title_ability: String = ""  # Ability waiting for target selection
var title_online_players: Array = []  # List of online players for targeting
var title_broadcast_mode: bool = false  # Whether entering broadcast text
var forge_available: bool = false  # Whether at Infernal Forge with Unforged Crown

# Ability mode entry tracking
var ability_entered_from_settings: bool = false

# Leaderboard mode
var leaderboard_mode: String = "fallen_heroes"  # "fallen_heroes", "monster_kills", or "trophy_hall"

# Fishing mode
var fishing_mode: bool = false
var fishing_phase: String = ""  # "waiting", "reaction"
var fishing_wait_timer: float = 0.0
var fishing_reaction_timer: float = 0.0
var fishing_reaction_window: float = 1.5  # How long player has to react (from server)
var fishing_target_slot: int = -1  # Which slot to press (0-4 mapped to action bar 5-9)
var fishing_water_type: String = "shallow"  # "shallow" or "deep"

# Mining mode
var mining_mode: bool = false
var mining_phase: String = ""  # "waiting", "reaction"
var mining_wait_timer: float = 0.0
var mining_reaction_timer: float = 0.0
var mining_reaction_window: float = 1.2
var mining_target_slot: int = -1
var mining_current_tier: int = 1
var mining_reactions_required: int = 1  # How many successful reactions needed
var mining_reactions_completed: int = 0  # How many we've done

# Logging mode
var logging_mode: bool = false
var logging_phase: String = ""  # "waiting", "reaction"
var logging_wait_timer: float = 0.0
var logging_reaction_timer: float = 0.0
var logging_reaction_window: float = 1.2
var logging_target_slot: int = -1
var logging_current_tier: int = 1
var logging_reactions_required: int = 1
var logging_reactions_completed: int = 0

# Gathering pattern system (DDR-style sequences)
const GATHERING_PATTERN_KEYS = ["Q", "W", "E", "R"]  # Keys used for patterns
var gathering_pattern: Array = []  # Current pattern sequence e.g., ["W", "E", "Q", "W"]
var gathering_pattern_index: int = 0  # Current position in pattern (0-indexed)
var gathering_pattern_tier: int = 1  # Tier being gathered (affects pattern length)

# Dungeon mode
var dungeon_mode: bool = false
var dungeon_data: Dictionary = {}  # Current dungeon state from server
var dungeon_floor_grid: Array = []  # 2D array of tile types
var dungeon_available: Array = []  # List of available dungeons to enter
var dungeon_list_mode: bool = false  # Viewing dungeon list

# Password change mode
var changing_password: bool = false
var password_change_step: int = 0  # 0=old, 1=new, 2=confirm
var temp_old_password: String = ""
var temp_new_password: String = ""

# Bug report mode
var bug_report_mode: bool = false  # Waiting for optional description

# Enemy tracking
var known_enemy_hp: Dictionary = {}
var discovered_monster_types: Dictionary = {}  # Tracks monster types by base name (first encounter)
var current_enemy_name: String = ""
var current_enemy_level: int = 0
var current_enemy_color: String = "#FFFFFF"  # Monster name color based on class affinity
var current_enemy_abilities: Array = []  # Monster abilities for damage calculation
var current_enemy_is_rare_variant: bool = false  # For visual indicator on rare monsters
var damage_dealt_to_current_enemy: int = 0
var current_enemy_hp: int = -1  # Actual HP from server (-1 = unknown)
var current_enemy_max_hp: int = -1  # Actual max HP from server
var analyze_revealed_max_hp: int = -1  # Actual max HP revealed by Analyze ability this combat
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

# Player name click tracking
var pending_player_info_request: String = ""  # Track pending popup request
var player_info_equipped: Dictionary = {}  # Cached equipment for clicked player info
var last_death_message: Dictionary = {}  # Cached permadeath data for save-to-file
var online_players_names: Array = []  # Cache player names for click detection
var last_online_click_time: float = 0.0  # Track double-click timing
const DOUBLE_CLICK_TIME: float = 0.4  # 400ms for double-click

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

# Whisper notification sound
var whisper_player: AudioStreamPlayer = null

# Server announcement sound
var server_announcement_player: AudioStreamPlayer = null

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

# Egg hatch celebration sound
var egg_hatch_player: AudioStreamPlayer = null

# New WAV-based sound effects
var death_player: AudioStreamPlayer = null
var egg_found_player: AudioStreamPlayer = null
var fire1_player: AudioStreamPlayer = null  # Meteor
var fire2_player: AudioStreamPlayer = null  # Blast
var gem_gain_player: AudioStreamPlayer = null
var loot_vanish_player: AudioStreamPlayer = null
var player_buffed_player: AudioStreamPlayer = null
var player_healed_player: AudioStreamPlayer = null

# Volume control
var sfx_volume: float = 1.0   # 0.0 to 1.0 multiplier for all SFX
var music_volume: float = 1.0  # 0.0 to 1.0 multiplier for music
var sfx_muted: bool = false

# Base volume levels for each sound (used with volume multiplier)
const SFX_BASE_VOLUMES: Dictionary = {
	"rare_drop": -23.0,
	"levelup": -25.0,
	"top5": -25.0,
	"quest_complete": -21.0,
	"whisper": -22.0,
	"server_announcement": -19.5,
	"danger": -24.0,
	"combat_hit": -23.0,
	"combat_crit": -20.0,
	"combat_victory": -22.0,
	"combat_ability": -26.0,
	"egg_hatch": -20.0,
	"death": -21.0,
	"egg_found": -21.0,
	"fire1": -23.0,
	"fire2": -23.0,
	"gem_gain": -22.0,
	"loot_vanish": -22.0,
	"player_buffed": -22.0,
	"player_healed": -22.0,
}

# ===== COMPANION ABILITIES (mirrored from drop_tables.gd) =====
const COMPANION_ABILITIES = {
	1: {  # Tier 1 (Weakest companions)
		10: {"name": "Encouraging Presence", "type": "passive", "effect": "attack", "value": 2},
		25: {"name": "Distraction", "type": "chance", "chance": 15, "effect": "enemy_miss"},
		50: {"name": "Protective Instinct", "type": "threshold", "hp_percent": 50, "effect": "defense_buff", "value": 10, "duration": 3}
	},
	2: {  # Tier 2
		10: {"name": "Battle Focus", "type": "passive", "effect": "attack", "value": 3},
		25: {"name": "Harrying Strike", "type": "chance", "chance": 18, "effect": "bonus_damage", "value": 12},
		50: {"name": "Guardian Shield", "type": "threshold", "hp_percent": 50, "effect": "defense_buff", "value": 12, "duration": 3}
	},
	3: {  # Tier 3
		10: {"name": "Predator's Eye", "type": "passive", "effect": "attack", "value": 3, "effect2": "defense", "value2": 2},
		25: {"name": "Savage Bite", "type": "chance", "chance": 20, "effect": "bonus_damage", "value": 15},
		50: {"name": "Emergency Heal", "type": "threshold", "hp_percent": 50, "effect": "heal", "value": 10}
	},
	4: {  # Tier 4
		10: {"name": "Primal Fury", "type": "passive", "effect": "attack", "value": 4, "effect2": "speed", "value2": 3},
		25: {"name": "Vicious Assault", "type": "chance", "chance": 20, "effect": "bonus_damage", "value": 18},
		50: {"name": "Life Bond", "type": "threshold", "hp_percent": 40, "effect": "heal", "value": 12}
	},
	5: {  # Tier 5
		10: {"name": "Battle Synergy", "type": "passive", "effect": "attack", "value": 4, "effect2": "defense", "value2": 3},
		25: {"name": "Devastating Strike", "type": "chance", "chance": 22, "effect": "bonus_damage", "value": 22, "effect2": "stun", "chance2": 10},
		50: {"name": "Desperate Recovery", "type": "threshold", "hp_percent": 35, "effect": "heal", "value": 15}
	},
	6: {  # Tier 6
		10: {"name": "Elemental Fury", "type": "passive", "effect": "attack", "value": 5, "effect2": "defense", "value2": 4},
		25: {"name": "Elemental Burst", "type": "chance", "chance": 22, "effect": "bonus_damage", "value": 25},
		50: {"name": "Phoenix Gift", "type": "threshold", "hp_percent": 30, "effect": "heal", "value": 18}
	},
	7: {  # Tier 7 (Elite)
		10: {"name": "Void Resonance", "type": "passive", "effect": "attack", "value": 6, "effect2": "defense", "value2": 4, "effect3": "speed", "value3": 3},
		25: {"name": "Void Strike", "type": "chance", "chance": 23, "effect": "bonus_damage", "value": 30, "effect2": "lifesteal", "value2": 15},
		50: {"name": "Elder's Blessing", "type": "threshold", "hp_percent": 30, "effect": "heal", "value": 22}
	},
	8: {  # Tier 8 (Legendary)
		10: {"name": "Cosmic Alignment", "type": "passive", "effect": "attack", "value": 7, "effect2": "defense", "value2": 5, "effect3": "crit_chance", "value3": 3},
		25: {"name": "Time Rend", "type": "chance", "chance": 25, "effect": "bonus_damage", "value": 35, "effect2": "stun", "chance2": 20},
		50: {"name": "Death's Reprieve", "type": "threshold", "hp_percent": 25, "effect": "heal", "value": 30}
	},
	9: {  # Tier 9 (Mythic)
		10: {"name": "Divine Presence", "type": "passive", "effect": "attack", "value": 10, "effect2": "defense", "value2": 6, "effect3": "speed", "value3": 5},
		25: {"name": "Godslayer's Wrath", "type": "chance", "chance": 25, "effect": "bonus_damage", "value": 50, "effect2": "lifesteal", "value2": 25},
		50: {"name": "Immortal's Gift", "type": "threshold", "hp_percent": 20, "effect": "full_heal"}
	}
}

# ===== MONSTER-SPECIFIC COMPANION ABILITIES (mirrored from drop_tables.gd) =====
# Each monster type has unique abilities that scale with companion level
# base + (scaling * companion_level) = final value
const COMPANION_MONSTER_ABILITIES = {
	# ===== TIER 1 =====
	"Goblin": {
		"passive": {"name": "Sneaky Support", "effect": "attack", "base": 1, "scaling": 0.03, "description": "+Attack damage"},
		"active": {"name": "Dirty Trick", "base_chance": 8, "chance_scaling": 0.1, "effect": "enemy_miss", "description": "Chance to make enemy miss"},
		"threshold": {"name": "Cowardly Retreat", "hp_percent": 40, "effect": "flee_bonus", "base": 10, "scaling": 0.2, "description": "Boosts flee chance when low HP"}
	},
	"Giant Rat": {
		"passive": {"name": "Scurrying Assistance", "effect": "speed", "base": 2, "scaling": 0.04, "description": "+Speed"},
		"active": {"name": "Gnaw", "base_chance": 10, "chance_scaling": 0.1, "effect": "bleed", "base_damage": 2, "damage_scaling": 0.05, "description": "Chance to cause bleeding"},
		"threshold": {"name": "Survival Instinct", "hp_percent": 35, "effect": "speed_buff", "base": 15, "scaling": 0.2, "description": "Speed boost when low HP"}
	},
	"Kobold": {
		"passive": {"name": "Treasure Sense", "effect": "gold_find", "base": 3, "scaling": 0.05, "description": "+Gold find"},
		"active": {"name": "Trap Trigger", "base_chance": 8, "chance_scaling": 0.08, "effect": "bonus_damage", "base_damage": 5, "damage_scaling": 0.1, "description": "Chance for bonus damage"},
		"threshold": {"name": "Hoard Guard", "hp_percent": 45, "effect": "defense_buff", "base": 8, "scaling": 0.15, "description": "Defense boost when low HP"}
	},
	"Skeleton": {
		"passive": {"name": "Bone Guard", "effect": "defense", "base": 2, "scaling": 0.03, "description": "+Defense"},
		"active": {"name": "Rattle", "base_chance": 10, "chance_scaling": 0.1, "effect": "enemy_miss", "description": "Chance to distract enemy"},
		"threshold": {"name": "Undying Will", "hp_percent": 25, "effect": "absorb", "base": 5, "scaling": 0.15, "description": "Absorbs damage when critical"}
	},
	"Wolf": {
		"passive": {"name": "Pack Instinct", "effect": "attack", "base": 2, "scaling": 0.04, "description": "+Attack damage"},
		"active": {"name": "Ambush Strike", "base_chance": 12, "chance_scaling": 0.12, "effect": "crit", "description": "Chance to critically strike"},
		"threshold": {"name": "Alpha Howl", "hp_percent": 35, "effect": "attack_buff", "base": 12, "scaling": 0.2, "description": "Attack boost when low HP"}
	},
	# ===== TIER 2 =====
	"Orc": {
		"passive": {"name": "Brute Force", "effect": "attack", "base": 3, "scaling": 0.05, "description": "+Attack damage"},
		"active": {"name": "Battle Rage", "base_chance": 12, "chance_scaling": 0.12, "effect": "bonus_damage", "base_damage": 8, "damage_scaling": 0.15, "description": "Chance for bonus damage"},
		"threshold": {"name": "Berserker Fury", "hp_percent": 30, "effect": "attack_buff", "base": 20, "scaling": 0.3, "description": "Major attack boost when low HP"}
	},
	"Hobgoblin": {
		"passive": {"name": "Tactical Mind", "effect": "attack", "base": 2, "scaling": 0.04, "effect2": "speed", "base2": 1, "scaling2": 0.02, "description": "+Attack and speed"},
		"active": {"name": "Coordinated Strike", "base_chance": 15, "chance_scaling": 0.1, "effect": "bonus_damage", "base_damage": 6, "damage_scaling": 0.12, "description": "Chance for bonus damage"},
		"threshold": {"name": "Rally Cry", "hp_percent": 40, "effect": "all_buff", "base": 8, "scaling": 0.15, "description": "Buffs all stats when low HP"}
	},
	"Gnoll": {
		"passive": {"name": "Savage Strength", "effect": "attack", "base": 4, "scaling": 0.06, "description": "+Significant attack"},
		"active": {"name": "Rending Claws", "base_chance": 14, "chance_scaling": 0.1, "effect": "bleed", "base_damage": 4, "damage_scaling": 0.08, "description": "Chance to cause bleeding"},
		"threshold": {"name": "Pack Frenzy", "hp_percent": 35, "effect": "attack_buff", "base": 15, "scaling": 0.25, "description": "Attack boost when low HP"}
	},
	"Spider": {
		"passive": {"name": "Web Weaver", "effect": "speed", "base": 3, "scaling": 0.05, "description": "+Speed"},
		"active": {"name": "Venomous Bite", "base_chance": 15, "chance_scaling": 0.12, "effect": "poison", "base_damage": 3, "damage_scaling": 0.06, "description": "Chance to poison"},
		"threshold": {"name": "Silk Cocoon", "hp_percent": 30, "effect": "defense_buff", "base": 15, "scaling": 0.2, "description": "Defense boost when low HP"}
	},
	# ===== TIER 3+ (abbreviated for common types) =====
	"Troll": {
		"passive": {"name": "Regeneration", "effect": "regen", "base": 3, "scaling": 0.08, "description": "+HP regen per turn"},
		"active": {"name": "Crushing Blow", "base_chance": 15, "chance_scaling": 0.1, "effect": "bonus_damage", "base_damage": 12, "damage_scaling": 0.2, "description": "Chance for heavy damage"},
		"threshold": {"name": "Troll's Resilience", "hp_percent": 25, "effect": "heal", "base": 20, "scaling": 0.4, "description": "Heals when critical"}
	},
	"Wyvern": {
		"passive": {"name": "Aerial Superiority", "effect": "speed", "base": 5, "scaling": 0.08, "effect2": "attack", "base2": 2, "scaling2": 0.04, "description": "+Speed and attack"},
		"active": {"name": "Dive Attack", "base_chance": 18, "chance_scaling": 0.12, "effect": "bonus_damage", "base_damage": 15, "damage_scaling": 0.25, "description": "Chance for bonus damage"},
		"threshold": {"name": "Screech", "hp_percent": 40, "effect": "enemy_miss", "base": 30, "scaling": 0.3, "description": "Enemy misses when low HP"}
	},
	"Giant": {
		"passive": {"name": "Towering Might", "effect": "attack", "base": 6, "scaling": 0.1, "effect2": "defense", "base2": 3, "scaling2": 0.05, "description": "+Attack and defense"},
		"active": {"name": "Ground Slam", "base_chance": 16, "chance_scaling": 0.1, "effect": "stun", "description": "Chance to stun enemy"},
		"threshold": {"name": "Last Stand", "hp_percent": 25, "effect": "damage_reduction", "base": 25, "scaling": 0.3, "description": "Reduces damage when critical"}
	},
	"Dragon": {
		"passive": {"name": "Dragon's Presence", "effect": "attack", "base": 8, "scaling": 0.15, "effect2": "defense", "base2": 5, "scaling2": 0.1, "description": "+Major attack and defense"},
		"active": {"name": "Flame Breath", "base_chance": 20, "chance_scaling": 0.15, "effect": "bonus_damage", "base_damage": 25, "damage_scaling": 0.4, "description": "Chance for massive damage"},
		"threshold": {"name": "Ancient Fury", "hp_percent": 30, "effect": "attack_buff", "base": 35, "scaling": 0.5, "description": "Huge attack boost when low HP"}
	}
}

# ===== RACE DESCRIPTIONS =====
const RACE_DESCRIPTIONS = {
	"Human": "Adaptable and ambitious. Gains +10% bonus experience from all sources.",
	"Elf": "Ancient and resilient. 50% reduced poison damage, +20% magic resistance, +25% mana.",
	"Dwarf": "Sturdy and determined. 25% chance to survive lethal damage with 1 HP (once per combat).",
	"Ogre": "Massive and regenerative. All healing effects are doubled.",
	"Halfling": "Lucky and nimble. +10% dodge chance, +15% gold from monster kills.",
	"Orc": "Fierce and relentless. +20% damage when below 50% HP.",
	"Gnome": "Clever and efficient. All ability costs reduced by 15%.",
	"Undead": "Deathless and cursed. Immune to death curses, poison heals instead of damages."
}

const CLASS_DESCRIPTIONS = {
	"Fighter": "Warrior Path. Balanced melee fighter with solid defense and offense. Uses Stamina.\n[color=#C0C0C0]Passive - Tactical Discipline:[/color] 20% reduced stamina costs, +15% defense",
	"Barbarian": "Warrior Path. Aggressive berserker trading defense for raw damage. Uses Stamina.\n[color=#8B0000]Passive - Blood Rage:[/color] +3% damage per 10% HP missing (max +30%), abilities cost 25% more",
	"Paladin": "Warrior Path. Holy knight with sustain and bonus damage vs evil. Uses Stamina.\n[color=#FFD700]Passive - Divine Favor:[/color] Heal 3% max HP per round, +25% damage vs undead/demons",
	"Wizard": "Mage Path. Pure spellcaster with high magic damage. Uses Mana.\n[color=#4169E1]Passive - Arcane Precision:[/color] +15% spell damage, +10% spell crit chance",
	"Sorcerer": "Mage Path. Chaotic mage with high-risk, high-reward magic. Uses Mana.\n[color=#9400D3]Passive - Chaos Magic:[/color] 25% chance for double spell damage, 5% chance to backfire",
	"Sage": "Mage Path. Wise scholar with efficient mana use. Uses Mana.\n[color=#20B2AA]Passive - Mana Mastery:[/color] 25% reduced mana costs, Meditate restores 50% more",
	"Thief": "Trickster Path. Cunning rogue excelling at critical hits. Uses Energy.\n[color=#2F4F4F]Passive - Backstab:[/color] +50% crit damage, +15% base crit chance",
	"Ranger": "Trickster Path. Hunter with bonuses vs beasts and extra rewards. Uses Energy.\n[color=#228B22]Passive - Hunter's Mark:[/color] +25% damage vs beasts, +30% gold/XP from kills",
	"Ninja": "Trickster Path. Shadow warrior with superior escape abilities. Uses Energy.\n[color=#191970]Passive - Shadow Step:[/color] +40% flee success, take no damage when fleeing"
}

# ===== ABILITY SYSTEM CONSTANTS =====

# Ability slots: [command, display_name, required_level, resource_cost, resource_type]
# resource_type: "mana", "stamina", "energy"
const MAGE_ABILITY_SLOTS = [
	["magic_bolt", "Bolt", 1, 0, "mana"],
	["forcefield", "Field", 15, 20, "mana"],  # Replaces Shield, unlocks at L15
	["cloak", "Cloak", 25, 30, "mana"],
	["blast", "Blast", 40, 50, "mana"],
	["teleport", "Teleport", 60, 1000, "mana"],  # Moved from L80
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
	if bug_button:
		bug_button.pressed.connect(_on_bug_button_pressed)
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
	if char_select_sanctuary_button:
		char_select_sanctuary_button.pressed.connect(_on_char_select_sanctuary_pressed)

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
	# Connect leaderboard toggle button
	var leaderboard_toggle = leaderboard_panel.get_node_or_null("VBox/ToggleButton") if leaderboard_panel else null
	if leaderboard_toggle:
		leaderboard_toggle.pressed.connect(_on_leaderboard_toggle_pressed)

	# Connect player info panel signals
	if close_player_info_button:
		close_player_info_button.pressed.connect(_on_close_player_info_pressed)

	# Create ability input popup
	_create_ability_popup()

	# Connect online players list for clickable names (click shows player info)
	# Uses push_meta/pop + meta_clicked signal - the only supported API in Godot 4.6
	if online_players_list:
		if not online_players_list.meta_clicked.is_connected(_on_player_name_clicked):
			online_players_list.meta_clicked.connect(_on_player_name_clicked)

	# Connect player info popup for clickable equipment
	if player_info_content:
		if not player_info_content.meta_clicked.is_connected(_on_player_info_meta_clicked):
			player_info_content.meta_clicked.connect(_on_player_info_meta_clicked)

	# Setup race options
	if race_option:
		race_option.clear()
		for r in ["Dwarf", "Elf", "Gnome", "Halfling", "Human", "Ogre", "Orc", "Undead"]:
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

	# Initialize all sound players with WAV files
	_init_sound_players()

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

func _init_sound_players():
	"""Initialize all sound effect players with WAV files"""
	# Helper: create player, load WAV, set volume, add as child
	rare_drop_player = _create_sfx_player("res://audio/GemGain.wav", "rare_drop")
	levelup_player = _create_sfx_player("res://audio/PowerUp01.wav", "levelup")
	top5_player = _create_sfx_player("res://audio/PowerUp01.wav", "top5")
	quest_complete_player = _create_sfx_player("res://audio/UI03.wav", "quest_complete")
	whisper_player = _create_sfx_player("res://audio/SciFi02.wav", "whisper")
	server_announcement_player = _create_sfx_player("res://audio/SciFi01.wav", "server_announcement")
	danger_player = _create_sfx_player("res://audio/Damage01.wav", "danger")
	combat_hit_player = _create_sfx_player("res://audio/Hit.wav", "combat_hit")
	combat_crit_player = _create_sfx_player("res://audio/Slash01.wav", "combat_crit")
	combat_victory_player = _create_sfx_player("res://audio/UI06.wav", "combat_victory")
	combat_ability_player = _create_sfx_player("res://audio/SciFi01.wav", "combat_ability")
	egg_hatch_player = _create_sfx_player("res://audio/PowerUp01.wav", "egg_hatch")
	# New sound effects
	death_player = _create_sfx_player("res://audio/Death.wav", "death")
	egg_found_player = _create_sfx_player("res://audio/EggFound.wav", "egg_found")
	fire1_player = _create_sfx_player("res://audio/Fire01.wav", "fire1")
	fire2_player = _create_sfx_player("res://audio/Fire02.wav", "fire2")
	gem_gain_player = _create_sfx_player("res://audio/GemGain.wav", "gem_gain")
	loot_vanish_player = _create_sfx_player("res://audio/LootVanish.wav", "loot_vanish")
	player_buffed_player = _create_sfx_player("res://audio/PlayerBuffed.wav", "player_buffed")
	player_healed_player = _create_sfx_player("res://audio/PlayerHealed.wav", "player_healed")

func _create_sfx_player(wav_path: String, volume_key: String) -> AudioStreamPlayer:
	"""Create an AudioStreamPlayer with a WAV file and base volume"""
	var player = AudioStreamPlayer.new()
	var base_vol = SFX_BASE_VOLUMES.get(volume_key, -16.0)
	if sfx_volume <= 0.0 or sfx_muted:
		player.volume_db = -80.0
	else:
		player.volume_db = base_vol + (20.0 * log(sfx_volume) / log(10.0))
	var stream = load(wav_path)
	if stream:
		player.stream = stream
	else:
		push_error("Failed to load sound: %s" % wav_path)
	add_child(player)
	return player

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

func play_levelup_sound():
	"""Play the level up sound effect"""
	if levelup_player and levelup_player.stream:
		levelup_player.play()

func play_top5_sound():
	"""Play the top 5 leaderboard fanfare"""
	if top5_player and top5_player.stream:
		top5_player.play()

func play_quest_complete_sound():
	"""Play the quest complete chime"""
	if quest_complete_player and quest_complete_player.stream:
		quest_complete_player.play()

func play_whisper_notification():
	"""Play the whisper notification sound"""
	if whisper_player and whisper_player.stream:
		whisper_player.play()

func play_server_announcement():
	"""Play the server announcement sound"""
	if server_announcement_player and server_announcement_player.stream:
		server_announcement_player.play()

func play_danger_sound():
	"""Play the danger warning sound"""
	if danger_player and danger_player.stream:
		danger_player.play()

# ===== COMBAT SOUND EFFECTS =====

func play_egg_hatch_sound():
	"""Play the egg hatch celebration sound"""
	if egg_hatch_player and egg_hatch_player.stream:
		egg_hatch_player.play()

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

# ===== NEW WAV-BASED SOUND PLAY FUNCTIONS =====

func play_death_sound():
	"""Play the death/permadeath sound"""
	if death_player and death_player.stream:
		death_player.play()

func play_egg_found_sound():
	"""Play the egg found sound"""
	if egg_found_player and egg_found_player.stream:
		egg_found_player.play()

func play_fire1_sound():
	"""Play Meteor fire sound"""
	if fire1_player and fire1_player.stream:
		fire1_player.play()

func play_fire2_sound():
	"""Play Blast fire sound"""
	if fire2_player and fire2_player.stream:
		fire2_player.play()

func play_gem_gain_sound():
	"""Play gem gain sound"""
	if gem_gain_player and gem_gain_player.stream:
		gem_gain_player.play()

func play_loot_vanish_sound():
	"""Play loot vanish sound (failed special drop)"""
	if loot_vanish_player and loot_vanish_player.stream:
		loot_vanish_player.play()

func play_player_buffed_sound():
	"""Play buff activation sound"""
	if player_buffed_player and player_buffed_player.stream:
		player_buffed_player.play()

func play_player_healed_sound():
	"""Play healing sound"""
	if player_healed_player and player_healed_player.stream:
		player_healed_player.play()

# ===== VOLUME CONTROL =====

func _apply_volume_settings():
	"""Apply current volume settings to all audio players"""
	# SFX players
	var sfx_players = {
		"rare_drop": rare_drop_player,
		"levelup": levelup_player,
		"top5": top5_player,
		"quest_complete": quest_complete_player,
		"whisper": whisper_player,
		"server_announcement": server_announcement_player,
		"danger": danger_player,
		"combat_hit": combat_hit_player,
		"combat_crit": combat_crit_player,
		"combat_victory": combat_victory_player,
		"combat_ability": combat_ability_player,
		"egg_hatch": egg_hatch_player,
		"death": death_player,
		"egg_found": egg_found_player,
		"fire1": fire1_player,
		"fire2": fire2_player,
		"gem_gain": gem_gain_player,
		"loot_vanish": loot_vanish_player,
		"player_buffed": player_buffed_player,
		"player_healed": player_healed_player,
	}
	for key in sfx_players:
		var player = sfx_players[key]
		if player:
			var base_vol = SFX_BASE_VOLUMES.get(key, -16.0)
			if sfx_volume <= 0.0 or sfx_muted:
				player.volume_db = -80.0
			else:
				player.volume_db = base_vol + (20.0 * log(sfx_volume) / log(10.0))
	# Music player
	if music_player:
		if music_volume <= 0.0:
			music_player.volume_db = -80.0
		else:
			music_player.volume_db = MUSIC_VOLUME_DB + (20.0 * log(music_volume) / log(10.0))

func _start_background_music():
	"""Deferred music startup - load WAV file"""
	var stream = load("res://audio/Out of my dreams NES.wav")
	if stream:
		music_player.stream = stream
	# Apply music volume
	if music_volume <= 0.0:
		music_player.volume_db = -80.0
	else:
		music_player.volume_db = MUSIC_VOLUME_DB + (20.0 * log(music_volume) / log(10.0))
	if not music_muted:
		music_player.play()

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
	"""Scale font sizes based on window height and user UI scale preferences"""
	var window_height = get_viewport().get_visible_rect().size.y
	# Scale based on 720p as baseline
	var base_scale = window_height / 720.0

	# Scale map display (includes ASCII terrain)
	if map_display:
		var map_font_size = int(MAP_BASE_FONT_SIZE * base_scale * ui_scale_map)
		map_font_size = clampi(map_font_size, MAP_MIN_FONT_SIZE, MAP_MAX_FONT_SIZE)
		map_display.add_theme_font_size_override("normal_font_size", map_font_size)
		map_display.add_theme_font_size_override("bold_font_size", map_font_size)
		map_display.add_theme_font_size_override("italics_font_size", map_font_size)
		map_display.add_theme_font_size_override("bold_italics_font_size", map_font_size)

	# Scale game output (includes monster ASCII art)
	if game_output:
		var game_font_size = int(GAME_OUTPUT_BASE_FONT_SIZE * base_scale * ui_scale_game_output)
		game_font_size = clampi(game_font_size, GAME_OUTPUT_MIN_FONT_SIZE, GAME_OUTPUT_MAX_FONT_SIZE)
		game_output.add_theme_font_size_override("normal_font_size", game_font_size)
		game_output.add_theme_font_size_override("bold_font_size", game_font_size)
		game_output.add_theme_font_size_override("italics_font_size", game_font_size)
		game_output.add_theme_font_size_override("bold_italics_font_size", game_font_size)

	# Scale chat output
	if chat_output:
		var chat_size = int(CHAT_BASE_FONT_SIZE * base_scale * ui_scale_chat)
		chat_size = clampi(chat_size, CHAT_MIN_FONT_SIZE, CHAT_MAX_FONT_SIZE)
		chat_output.add_theme_font_size_override("normal_font_size", chat_size)

	# Scale online players list
	if online_players_list:
		var online_size = int(ONLINE_PLAYERS_BASE_FONT_SIZE * base_scale * ui_scale_right_panel)
		online_size = clampi(online_size, CHAT_MIN_FONT_SIZE, CHAT_MAX_FONT_SIZE)
		online_players_list.add_theme_font_size_override("normal_font_size", online_size)

	if online_players_label:
		var label_size = int(12 * base_scale * ui_scale_right_panel)
		label_size = clampi(label_size, CHAT_MIN_FONT_SIZE, CHAT_MAX_FONT_SIZE)
		online_players_label.add_theme_font_size_override("font_size", label_size)

	# Scale right panel elements (stats, map controls, send button)
	_scale_right_panel_fonts(base_scale)

	# Scale action bar buttons
	_scale_action_bar_fonts(base_scale)

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

	# Update fishing timers
	if fishing_mode:
		if fishing_phase == "waiting":
			fishing_wait_timer -= delta
			if fishing_wait_timer <= 0:
				start_fishing_reaction_phase()
		elif fishing_phase == "reaction":
			fishing_reaction_timer -= delta
			if fishing_reaction_timer <= 0:
				# Timeout - fish escaped
				send_to_server({"type": "fish_catch", "success": false, "water_type": fishing_water_type})

	# Update mining timers
	if mining_mode:
		if mining_phase == "waiting":
			mining_wait_timer -= delta
			if mining_wait_timer <= 0:
				start_mining_reaction_phase()
		elif mining_phase == "reaction":
			mining_reaction_timer -= delta
			if mining_reaction_timer <= 0:
				# Timeout - partial success based on reactions completed
				send_to_server({"type": "mine_catch", "success": false, "partial_success": mining_reactions_completed, "ore_tier": mining_current_tier})

	# Update logging timers
	if logging_mode:
		if logging_phase == "waiting":
			logging_wait_timer -= delta
			if logging_wait_timer <= 0:
				start_logging_reaction_phase()
		elif logging_phase == "reaction":
			logging_reaction_timer -= delta
			if logging_reaction_timer <= 0:
				# Timeout - partial success based on reactions completed
				send_to_server({"type": "log_catch", "success": false, "partial_success": logging_reactions_completed, "wood_tier": logging_current_tier})

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

	# House screen escape handling (settings only)
	if game_state == GameState.HOUSE_SCREEN:
		if Input.is_action_just_pressed("ui_cancel"):
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
			elif settings_mode:
				close_settings()

	# Inventory item selection with keybinds (items 1-9) when action is pending
	# Skip when in equip_confirm mode (that state uses action bar buttons, not item selection)
	# Skip when in monster_select_mode (scroll selection takes priority)
	# Skip sort_select and salvage_select (those use action bar buttons, not item selection)
	if game_state == GameState.PLAYING and not input_field.has_focus() and inventory_mode and pending_inventory_action != "" and pending_inventory_action not in ["equip_confirm", "sort_select", "salvage_select", "viewing_materials", "awaiting_salvage_result", "salvage_consumables_confirm"] and not monster_select_mode:
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
						# Regular inventory uses display_order mapping (equipment first, consumables last)
						var inv_display_order = get_meta("inventory_display_order", [])
						var display_idx = inventory_page * INVENTORY_PAGE_SIZE + i
						if display_idx < inv_display_order.size():
							selection_index = inv_display_order[display_idx].index
						else:
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

	# Trade item selection with keybinds when adding items to trade
	if game_state == GameState.PLAYING and not input_field.has_focus() and in_trade and trade_pending_add:
		for i in range(9):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("tradekey_%d_pressed" % i, false):
					set_meta("tradekey_%d_pressed" % i, true)
					select_trade_item(i)
			else:
				set_meta("tradekey_%d_pressed" % i, false)

	# Trade companion selection with keybinds (1-5)
	if game_state == GameState.PLAYING and not input_field.has_focus() and in_trade and trade_pending_add_companion:
		for i in range(5):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("tradecompkey_%d_pressed" % i, false):
					set_meta("tradecompkey_%d_pressed" % i, true)
					select_trade_companion(i)
			else:
				set_meta("tradecompkey_%d_pressed" % i, false)

	# Trade egg selection with keybinds (1-3)
	if game_state == GameState.PLAYING and not input_field.has_focus() and in_trade and trade_pending_add_egg:
		for i in range(3):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("tradeeggkey_%d_pressed" % i, false):
					set_meta("tradeeggkey_%d_pressed" % i, true)
					select_trade_egg(i)
			else:
				set_meta("tradeeggkey_%d_pressed" % i, false)

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

	# Crafting recipe selection with keybinds (1-5 for recipes on current page)
	if game_state == GameState.PLAYING and not input_field.has_focus() and crafting_mode and crafting_skill != "" and crafting_selected_recipe < 0:
		for i in range(5):  # Only 5 recipes per page
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("craftkey_%d_pressed" % i, false):
					set_meta("craftkey_%d_pressed" % i, true)
					select_craft_recipe(i)  # 0-based index
			else:
				set_meta("craftkey_%d_pressed" % i, false)

	# Dungeon selection with keybinds when viewing dungeon list
	if game_state == GameState.PLAYING and not input_field.has_focus() and dungeon_list_mode:
		for i in range(min(dungeon_available.size(), 9)):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("dungeonkey_%d_pressed" % i, false):
					set_meta("dungeonkey_%d_pressed" % i, true)
					select_dungeon(i)  # 0-based index
			else:
				set_meta("dungeonkey_%d_pressed" % i, false)

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
				set_meta("hotkey_0_pressed", true)
				cancel_combat_item_mode()
		else:
			set_meta("combatitem_cancel_pressed", false)
		# Q key (action_1) = Prev Pg, W key (action_2) = Next Pg
		var prev_key = keybinds.get("action_1", default_keybinds.get("action_1", KEY_Q))
		if Input.is_physical_key_pressed(prev_key):
			if not get_meta("combatitem_prev_pressed", false):
				set_meta("combatitem_prev_pressed", true)
				if combat_use_page > 0:
					combat_use_page -= 1
					_display_combat_usable_items_page()
					update_action_bar()
		else:
			set_meta("combatitem_prev_pressed", false)
		var next_key = keybinds.get("action_2", default_keybinds.get("action_2", KEY_W))
		if Input.is_physical_key_pressed(next_key):
			if not get_meta("combatitem_next_pressed", false):
				set_meta("combatitem_next_pressed", true)
				var combat_usable_items = get_meta("combat_usable_items", [])
				var total_pages = max(1, int(ceil(float(combat_usable_items.size()) / INVENTORY_PAGE_SIZE)))
				if combat_use_page < total_pages - 1:
					combat_use_page += 1
					_display_combat_usable_items_page()
					update_action_bar()
		else:
			set_meta("combatitem_next_pressed", false)

	# Companion activation with keybinds (1-5)
	# Note: Don't check is_item_key_blocked_by_action_bar here - in companions_mode,
	# number keys should ALWAYS select companions, not trigger action bar slots 5-9
	if game_state == GameState.PLAYING and not input_field.has_focus() and companions_mode:
		var sorted_list = get_meta("sorted_companions", character_data.get("collected_companions", []))
		for i in range(min(sorted_list.size(), 5)):
			if is_item_select_key_pressed(i):
				if not get_meta("companionkey_%d_pressed" % i, false):
					set_meta("companionkey_%d_pressed" % i, true)
					activate_companion_by_index(i)
			else:
				set_meta("companionkey_%d_pressed" % i, false)

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

	# Home Stone selection with number keys
	if game_state == GameState.PLAYING and not input_field.has_focus() and home_stone_mode:
		for i in range(min(9, home_stone_options.size())):
			if is_item_select_key_pressed(i):
				if is_item_key_blocked_by_action_bar(i):
					continue
				if not get_meta("homestonekey_%d_pressed" % i, false):
					set_meta("homestonekey_%d_pressed" % i, true)
					_select_home_stone_option(i)
			else:
				set_meta("homestonekey_%d_pressed" % i, false)

	# Blacksmith item selection with number keys (1-9)
	if game_state == GameState.PLAYING and not input_field.has_focus() and pending_blacksmith:
		if blacksmith_upgrade_mode == "select_item":
			# Selecting item for upgrade
			for i in range(min(9, blacksmith_upgrade_items.size())):
				var regular_key_pressed = is_item_select_key_pressed(i)
				var numpad_key_pressed = Input.is_physical_key_pressed(KEY_KP_1 + i) and not Input.is_key_pressed(KEY_SHIFT)
				if regular_key_pressed or numpad_key_pressed:
					if not get_meta("blacksmithkey_%d_pressed" % i, false):
						set_meta("blacksmithkey_%d_pressed" % i, true)
						if i < blacksmith_upgrade_items.size():
							var slot = blacksmith_upgrade_items[i].get("slot", "")
							send_blacksmith_choice("select_upgrade_item", slot)
				else:
					set_meta("blacksmithkey_%d_pressed" % i, false)
		elif blacksmith_upgrade_mode == "select_affix":
			# Selecting affix to upgrade
			for i in range(min(9, blacksmith_upgrade_affixes.size())):
				var regular_key_pressed = is_item_select_key_pressed(i)
				var numpad_key_pressed = Input.is_physical_key_pressed(KEY_KP_1 + i) and not Input.is_key_pressed(KEY_SHIFT)
				if regular_key_pressed or numpad_key_pressed:
					if not get_meta("blacksmithkey_%d_pressed" % i, false):
						set_meta("blacksmithkey_%d_pressed" % i, true)
						if i < blacksmith_upgrade_affixes.size():
							var affix_key = blacksmith_upgrade_affixes[i].get("affix_key", "")
							send_blacksmith_choice("confirm_upgrade", "", affix_key)
				else:
					set_meta("blacksmithkey_%d_pressed" % i, false)
		else:
			# Normal repair mode
			for i in range(min(9, blacksmith_items.size())):  # Up to 9 items
				var regular_key_pressed = is_item_select_key_pressed(i)
				var numpad_key_pressed = Input.is_physical_key_pressed(KEY_KP_1 + i) and not Input.is_key_pressed(KEY_SHIFT)
				if regular_key_pressed or numpad_key_pressed:
					if not get_meta("blacksmithkey_%d_pressed" % i, false):
						set_meta("blacksmithkey_%d_pressed" % i, true)
						# Get the slot name from the item at this index
						if i < blacksmith_items.size():
							var slot = blacksmith_items[i].get("slot", "")
							send_blacksmith_choice("repair_single", slot)
				else:
					set_meta("blacksmithkey_%d_pressed" % i, false)

	# NOTE: Inventory page navigation removed from here - now handled via action bar buttons
	# to avoid conflicts with Sort (key 2) and Salvage (key 3) action bar buttons

	# House screen item selection with number keys (1-6 for upgrades, 1-5 for storage/companions)
	if game_state == GameState.HOUSE_SCREEN and not input_field.has_focus():
		if house_mode == "upgrades":
			# Keys 1-6 to purchase upgrades
			for i in range(6):
				if is_item_select_key_pressed(i):
					if not get_meta("houseupgrade_%d_pressed" % i, false):
						set_meta("houseupgrade_%d_pressed" % i, true)
						_purchase_house_upgrade(i)
				else:
					set_meta("houseupgrade_%d_pressed" % i, false)
		elif house_mode == "storage" and pending_house_action == "withdraw_select":
			# Keys 1-5 to toggle withdraw selection
			for i in range(5):
				if is_item_select_key_pressed(i):
					if not get_meta("housestorage_%d_pressed" % i, false):
						set_meta("housestorage_%d_pressed" % i, true)
						_toggle_storage_withdraw_item(i)
				else:
					set_meta("housestorage_%d_pressed" % i, false)
		elif house_mode == "companions" and pending_house_action == "checkout_select":
			# Keys 1-5 to select companion for checkout
			for i in range(5):
				if is_item_select_key_pressed(i):
					if not get_meta("housecompanion_%d_pressed" % i, false):
						set_meta("housecompanion_%d_pressed" % i, true)
						_toggle_companion_checkout(i)
				else:
					set_meta("housecompanion_%d_pressed" % i, false)
		elif house_mode == "storage" and pending_house_action == "discard_select":
			# Keys 1-5 to select item for discard
			for i in range(5):
				if is_item_select_key_pressed(i):
					if not get_meta("housediscard_%d_pressed" % i, false):
						set_meta("housediscard_%d_pressed" % i, true)
						_select_storage_discard_item(i)
				else:
					set_meta("housediscard_%d_pressed" % i, false)
		elif house_mode == "storage" and pending_house_action == "register_select":
			# Keys 1-5 to select stored companion to register
			for i in range(5):
				if is_item_select_key_pressed(i):
					if not get_meta("houseregister_%d_pressed" % i, false):
						set_meta("houseregister_%d_pressed" % i, true)
						_select_storage_register_companion(i)
				else:
					set_meta("houseregister_%d_pressed" % i, false)
		elif house_mode == "companions" and pending_house_action == "unregister_select":
			# Keys 1-5 to select companion for unregister
			for i in range(5):
				if is_item_select_key_pressed(i):
					if not get_meta("houseunregister_%d_pressed" % i, false):
						set_meta("houseunregister_%d_pressed" % i, true)
						_select_companion_unregister(i)
				else:
					set_meta("houseunregister_%d_pressed" % i, false)

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
	# Note: quest_log_mode only blocks slots 5-9 (number keys 1-5 used for abandonment), not slot 0 (Continue)
	var merchant_blocks_hotkeys = pending_merchant_action != "" and pending_merchant_action not in ["sell_gems", "upgrade", "buy", "buy_inspect", "buy_equip_prompt", "sell", "gamble", "gamble_again"]
	# Use flag for ability popup (more reliable than visibility alone)
	var ability_popup_open = ability_popup_active
	var gamble_popup_open = gamble_popup != null and gamble_popup.visible
	var upgrade_popup_open = upgrade_popup != null and upgrade_popup.visible
	var teleport_popup_open = teleport_popup != null and teleport_popup.visible
	var any_popup_open = ability_popup_open or gamble_popup_open or upgrade_popup_open or teleport_popup_open
	var should_process_action_bar = (game_state == GameState.PLAYING or game_state == GameState.HOUSE_SCREEN or game_state == GameState.DEAD) and not input_field.has_focus() and not merchant_blocks_hotkeys and watch_request_pending == "" and not watch_request_handled and not settings_mode and not combat_item_mode and not monster_select_mode and not target_farm_mode and not home_stone_mode and not any_popup_open and not title_mode
	if should_process_action_bar:
		# Determine if we're in item selection mode (need to let item keys through)
		var in_item_selection_mode = inventory_mode and pending_inventory_action != "" and pending_inventory_action not in ["equip_confirm", "sort_select", "salvage_select"]

		for i in range(10):  # All 10 action bar slots
			# In quest_log_mode, only allow slots 0-4 (Continue button and others)
			# Slots 5-9 are blocked because number keys 1-5 are used for quest abandonment
			# Same for companions_mode - number keys 1-5 are used for companion selection
			if (quest_log_mode or companions_mode) and i >= 5:
				continue
			var action_key = "action_%d" % i
			var key = keybinds.get(action_key, default_keybinds.get(action_key, KEY_SPACE))

			# In item selection mode, skip action bar slots whose keys conflict with item selection keys
			# This allows number keys to be used for item selection even if bound to action bar
			if in_item_selection_mode:
				var key_conflicts_with_item_select = false
				for item_idx in range(9):
					if key == get_item_select_keycode(item_idx):
						key_conflicts_with_item_select = true
						break
				if key_conflicts_with_item_select:
					set_meta("hotkey_%d_pressed" % i, false)
					continue

			if Input.is_physical_key_pressed(key) and not Input.is_key_pressed(KEY_SHIFT):
				if not get_meta("hotkey_%d_pressed" % i, false):
					set_meta("hotkey_%d_pressed" % i, true)
					# Only trigger if this slot has an enabled action
					# (prevents blocking item selection when action bar slot is empty,
					# and prevents wrong key presses from succeeding in gathering minigames)
					if i < current_actions.size():
						var action = current_actions[i]
						if action.get("enabled", false) and action.get("action_type", "none") != "none":
							action_triggered_this_frame.append(i)
							trigger_action(i)
						# Note: Pattern-based gathering input is now handled in _input()
						# with Q, W, E, R keys - no longer uses action bar slots 5-9
			else:
				set_meta("hotkey_%d_pressed" % i, false)

	# Enter key to focus chat input (only in movement mode, not when popups are open)
	if game_state == GameState.PLAYING and not input_field.has_focus() and not in_combat and not flock_pending and not pending_continue and not inventory_mode and not at_merchant and not at_trading_post and not any_popup_open:
		if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
			if not get_meta("enter_pressed", false):
				set_meta("enter_pressed", true)
				input_field.grab_focus()
		else:
			set_meta("enter_pressed", false)

	# Dungeon movement with numpad/arrow keys (only when in dungeon_mode)
	if connected and has_character and not input_field.has_focus() and dungeon_mode and not in_combat and not pending_continue and not any_popup_open:
		if game_state == GameState.PLAYING:
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_move_time >= MOVE_COOLDOWN:
				var dungeon_dir = ""

				# Check numpad keys for 4-direction movement
				var north_key = keybinds.get("move_8", default_keybinds.get("move_8", KEY_KP_8))
				var south_key = keybinds.get("move_2", default_keybinds.get("move_2", KEY_KP_2))
				var west_key = keybinds.get("move_4", default_keybinds.get("move_4", KEY_KP_4))
				var east_key = keybinds.get("move_6", default_keybinds.get("move_6", KEY_KP_6))

				if Input.is_physical_key_pressed(north_key):
					dungeon_dir = "n"
				elif Input.is_physical_key_pressed(south_key):
					dungeon_dir = "s"
				elif Input.is_physical_key_pressed(west_key):
					dungeon_dir = "w"
				elif Input.is_physical_key_pressed(east_key):
					dungeon_dir = "e"

				# Check arrow keys as alternative
				if dungeon_dir == "":
					var up_key = keybinds.get("move_up", default_keybinds.get("move_up", KEY_UP))
					var down_key = keybinds.get("move_down", default_keybinds.get("move_down", KEY_DOWN))
					var left_key = keybinds.get("move_left", default_keybinds.get("move_left", KEY_LEFT))
					var right_key = keybinds.get("move_right", default_keybinds.get("move_right", KEY_RIGHT))

					if Input.is_physical_key_pressed(up_key):
						dungeon_dir = "n"
					elif Input.is_physical_key_pressed(down_key):
						dungeon_dir = "s"
					elif Input.is_physical_key_pressed(left_key):
						dungeon_dir = "w"
					elif Input.is_physical_key_pressed(right_key):
						dungeon_dir = "e"

				if dungeon_dir != "":
					send_to_server({"type": "dungeon_move", "direction": dungeon_dir})
					last_move_time = current_time

	# House movement with numpad/arrow keys (only when in house screen)
	if game_state == GameState.HOUSE_SCREEN and not input_field.has_focus() and house_mode == "main":
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_move_time >= MOVE_COOLDOWN * 0.5:  # Faster movement in house
			var house_dx = 0
			var house_dy = 0

			# Check numpad keys for 4-direction movement
			var north_key = keybinds.get("move_8", default_keybinds.get("move_8", KEY_KP_8))
			var south_key = keybinds.get("move_2", default_keybinds.get("move_2", KEY_KP_2))
			var west_key = keybinds.get("move_4", default_keybinds.get("move_4", KEY_KP_4))
			var east_key = keybinds.get("move_6", default_keybinds.get("move_6", KEY_KP_6))

			if Input.is_physical_key_pressed(north_key):
				house_dy = -1
			elif Input.is_physical_key_pressed(south_key):
				house_dy = 1
			elif Input.is_physical_key_pressed(west_key):
				house_dx = -1
			elif Input.is_physical_key_pressed(east_key):
				house_dx = 1

			# Check arrow keys as alternative
			if house_dx == 0 and house_dy == 0:
				var up_key = keybinds.get("move_up", default_keybinds.get("move_up", KEY_UP))
				var down_key = keybinds.get("move_down", default_keybinds.get("move_down", KEY_DOWN))
				var left_key = keybinds.get("move_left", default_keybinds.get("move_left", KEY_LEFT))
				var right_key = keybinds.get("move_right", default_keybinds.get("move_right", KEY_RIGHT))

				if Input.is_physical_key_pressed(up_key):
					house_dy = -1
				elif Input.is_physical_key_pressed(down_key):
					house_dy = 1
				elif Input.is_physical_key_pressed(left_key):
					house_dx = -1
				elif Input.is_physical_key_pressed(right_key):
					house_dx = 1

			if house_dx != 0 or house_dy != 0:
				if _move_house_player(house_dx, house_dy):
					_update_house_map()
					update_action_bar()  # Update to show what we're standing on
				last_move_time = current_time

	# Movement and hunt (only when playing and not in combat, flock, pending continue, inventory, merchant, settings, abilities, monster select, dungeon, more, companions, eggs, or popups)
	if connected and has_character and not input_field.has_focus() and not in_combat and not flock_pending and not pending_continue and not inventory_mode and not at_merchant and not settings_mode and not monster_select_mode and not ability_mode and not dungeon_mode and not more_mode and not companions_mode and not eggs_mode and not any_popup_open and not pending_blacksmith and not pending_healer:
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
					# Don't clear trading post UI - server will notify if we leave
					if at_trading_post:
						_display_trading_post_ui()
					else:
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
			display_game("[color=#00FF00]Connected to server![/color]")
			# Hide connection panel and show login panel (only if not already showing)
			if connection_panel:
				connection_panel.visible = false
			if game_state != GameState.LOGIN_SCREEN:
				game_state = GameState.CONNECTED
				show_login_panel()
			else:
				# Already on login screen (e.g., after account logout + reconnect)
				# Just make sure login panel is visible without clearing fields
				if login_panel and not login_panel.visible:
					login_panel.visible = true

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
	# Handle numpad input for popup LineEdits (higher priority than other handlers)
	# NOTE: Use active flags instead of just visibility - more reliable for input handling
	if event is InputEventKey and event.pressed and not event.echo:
		var popup_input: LineEdit = null
		# Check ability popup using flag (more reliable than visibility alone)
		if ability_popup_active and ability_popup_input != null:
			popup_input = ability_popup_input
			# Ensure focus is grabbed if not already
			if not ability_popup_input.has_focus():
				ability_popup_input.grab_focus()
		elif gamble_popup != null and gamble_popup.visible and gamble_popup_input != null:
			popup_input = gamble_popup_input
			if not gamble_popup_input.has_focus():
				gamble_popup_input.grab_focus()
		elif upgrade_popup != null and upgrade_popup.visible and upgrade_popup_input != null:
			popup_input = upgrade_popup_input
			if not upgrade_popup_input.has_focus():
				upgrade_popup_input.grab_focus()
		elif teleport_popup != null and teleport_popup.visible:
			if teleport_popup_x_input != null and teleport_popup_x_input.has_focus():
				popup_input = teleport_popup_x_input
			elif teleport_popup_y_input != null and teleport_popup_y_input.has_focus():
				popup_input = teleport_popup_y_input
			elif teleport_popup_x_input != null:
				# Default to X input if no focus
				popup_input = teleport_popup_x_input
				teleport_popup_x_input.grab_focus()

		if popup_input != null:
			var numpad_map = {
				KEY_KP_0: "0", KEY_KP_1: "1", KEY_KP_2: "2", KEY_KP_3: "3", KEY_KP_4: "4",
				KEY_KP_5: "5", KEY_KP_6: "6", KEY_KP_7: "7", KEY_KP_8: "8", KEY_KP_9: "9",
				KEY_KP_SUBTRACT: "-", KEY_KP_PERIOD: "."
			}
			if numpad_map.has(event.keycode):
				var char_to_insert = numpad_map[event.keycode]
				# Check if text is selected - if so, replace the selection
				if popup_input.has_selection():
					var sel_from = popup_input.get_selection_from_column()
					var sel_to = popup_input.get_selection_to_column()
					var text_before = popup_input.text.substr(0, sel_from)
					var text_after = popup_input.text.substr(sel_to)
					popup_input.text = text_before + char_to_insert + text_after
					popup_input.caret_column = sel_from + 1
				else:
					var caret_pos = popup_input.caret_column
					var current_text = popup_input.text
					popup_input.text = current_text.substr(0, caret_pos) + char_to_insert + current_text.substr(caret_pos)
					popup_input.caret_column = caret_pos + 1
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_KP_ENTER:
				popup_input.text_submitted.emit(popup_input.text)
				get_viewport().set_input_as_handled()
				return

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

	# Handle gathering pattern key presses (Q, W, E, R during reaction phase)
	if event is InputEventKey and event.pressed and not event.echo:
		var keycode = event.keycode
		var key_name = ""
		match keycode:
			KEY_Q: key_name = "Q"
			KEY_W: key_name = "W"
			KEY_E: key_name = "E"
			KEY_R: key_name = "R"

		if key_name != "":
			# Check if we're in a gathering reaction phase
			if fishing_mode and fishing_phase == "reaction":
				handle_fishing_pattern_key(key_name)
				get_viewport().set_input_as_handled()
				return
			elif mining_mode and mining_phase == "reaction":
				handle_mining_pattern_key(key_name)
				get_viewport().set_input_as_handled()
				return
			elif logging_mode and logging_phase == "reaction":
				handle_logging_pattern_key(key_name)
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
			var key_action_5 = keybinds.get("action_5", default_keybinds.get("action_5", KEY_1))
			var key_action_6 = keybinds.get("action_6", default_keybinds.get("action_6", KEY_2))
			var key_action_7 = keybinds.get("action_7", default_keybinds.get("action_7", KEY_3))
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
			elif keycode == key_action_5:
				toggle_swap_attack_setting()
			elif keycode == key_action_6:
				toggle_swap_outsmart_setting()
			elif keycode == key_action_7:
				# Open Abilities from Settings
				ability_entered_from_settings = true
				# Mark hotkey as pressed to prevent double-trigger
				set_meta("hotkey_7_pressed", true)
				settings_mode = false
				enter_ability_mode()
			elif keycode == keybinds.get("action_8", default_keybinds.get("action_8", KEY_4)):
				settings_submenu = "ui_scale"
				game_output.clear()
				display_ui_scale_settings()
				update_action_bar()
			elif keycode == keybinds.get("action_9", default_keybinds.get("action_9", KEY_5)):
				settings_submenu = "sound"
				game_output.clear()
				display_sound_settings()
				update_action_bar()
			elif keycode == key_action_0:
				# Mark action_0 hotkey as pressed to prevent double-trigger
				set_meta("hotkey_0_pressed", true)
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
		elif settings_submenu == "ui_scale":
			# UI Scale settings submenu
			var back_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
			if keycode == KEY_1:
				adjust_ui_scale("map", 0.1)
			elif keycode == KEY_2:
				adjust_ui_scale("map", -0.1)
			elif keycode == KEY_3:
				adjust_ui_scale("monster_art", 0.1)
			elif keycode == KEY_4:
				adjust_ui_scale("monster_art", -0.1)
			elif keycode == KEY_5:
				adjust_ui_scale("game_output", 0.1)
			elif keycode == KEY_6:
				adjust_ui_scale("game_output", -0.1)
			elif keycode == KEY_7:
				adjust_ui_scale("buttons", 0.1)
			elif keycode == KEY_8:
				adjust_ui_scale("buttons", -0.1)
			elif keycode == KEY_Q:
				adjust_ui_scale("chat", 0.1)
			elif keycode == KEY_W:
				adjust_ui_scale("chat", -0.1)
			elif keycode == KEY_E:
				adjust_ui_scale("right_panel", 0.1)
			elif keycode == KEY_R:
				adjust_ui_scale("right_panel", -0.1)
			elif keycode == KEY_9:
				reset_ui_scales()
			elif keycode == back_key:
				settings_submenu = ""
				game_output.clear()
				display_settings_menu()
				update_action_bar()
			get_viewport().set_input_as_handled()
		elif settings_submenu == "sound":
			# Sound settings submenu
			var back_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
			if keycode == KEY_1:
				adjust_sound_volume("sfx", 0.1)
			elif keycode == KEY_2:
				adjust_sound_volume("sfx", -0.1)
			elif keycode == KEY_3:
				adjust_sound_volume("music", 0.1)
			elif keycode == KEY_4:
				adjust_sound_volume("music", -0.1)
			elif keycode == KEY_5:
				sfx_muted = not sfx_muted
				_apply_volume_settings()
				_save_keybinds()
				game_output.clear()
				display_sound_settings()
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
			# Choosing from ability list with pagination
			var unlocked = ability_data.get("unlocked_abilities", [])
			var total_pages = max(1, (unlocked.size() + ABILITY_PAGE_SIZE - 1) / ABILITY_PAGE_SIZE)

			# Page navigation
			var action_1_key = keybinds.get("action_1", default_keybinds.get("action_1", KEY_Q))
			var action_2_key = keybinds.get("action_2", default_keybinds.get("action_2", KEY_W))
			if keycode == action_1_key and total_pages > 1:
				# Previous page
				ability_choice_page = max(0, ability_choice_page - 1)
				display_ability_choice_list()
				update_action_bar()
				get_viewport().set_input_as_handled()
				return
			elif keycode == action_2_key and total_pages > 1:
				# Next page
				ability_choice_page = min(total_pages - 1, ability_choice_page + 1)
				display_ability_choice_list()
				update_action_bar()
				get_viewport().set_input_as_handled()
				return

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
			# Selecting a slot (1-6)
			if keycode >= KEY_1 and keycode <= KEY_6:
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
				# Mark action_0 hotkey as pressed to prevent double-trigger in _process
				set_meta("hotkey_0_pressed", true)
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
		# Clear password field for security
		if password_field:
			password_field.clear()
		# Clear confirm password field if exists
		if confirm_password_field:
			confirm_password_field.clear()
		# Clear any previous status messages
		if login_status:
			login_status.text = ""
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
	game_state = GameState.CHARACTER_SELECT
	if char_select_panel:
		char_select_panel.visible = true
	update_character_list_display()

func show_house_panel():
	"""Show the house/sanctuary screen - roguelite meta-progression hub"""
	hide_all_panels()
	# House uses the main game UI with game_output for display
	# Note: Don't call show_game_ui() as it sets game_state to PLAYING
	game_state = GameState.HOUSE_SCREEN

func show_character_create_panel():
	hide_all_panels()
	if char_create_panel:
		char_create_panel.visible = true
		if new_char_name_field:
			new_char_name_field.clear()
			new_char_name_field.grab_focus()
		if char_create_status:
			char_create_status.text = ""

func show_death_panel(char_name: String, level: int, experience: int, cause: String, rank: int, baddie_points: int = 0):
	hide_all_panels()
	if death_panel:
		death_panel.visible = true
	if death_message:
		death_message.text = "[center][color=#FF0000][b]%s HAS FALLEN[/b][/color]\n\nSlain by %s[/center]" % [char_name.to_upper(), cause]
	if death_stats:
		var stats_text = "[center]Level: %d\nExperience: %d\nLeaderboard Rank: #%d" % [level, experience, rank]
		if baddie_points > 0:
			stats_text += "\n\n[color=#FF6600]Baddie Points Earned: %d[/color]" % baddie_points
			stats_text += "\n[color=#808080]Return to your Sanctuary to spend them![/color]"
		stats_text += "[/center]"
		death_stats.text = stats_text

func display_death_screen(message: Dictionary):
	"""Render the enhanced death screen into game_output with full character eulogy."""
	if not game_output:
		return
	game_output.clear()

	var char_name = message.get("character_name", "Unknown")
	var level = int(message.get("level", 1))
	var experience = int(message.get("experience", 0))
	var cause = message.get("cause_of_death", "Unknown")
	var rank = int(message.get("leaderboard_rank", 0))
	var baddie_points = int(message.get("baddie_points_earned", 0))
	var race = message.get("race", "Unknown")
	var class_type = message.get("class_type", "Unknown")
	var stats = message.get("stats", {})
	var equipped = message.get("equipped", {})
	var gold = int(message.get("gold", 0))
	var gems = int(message.get("gems", 0))
	var kills = int(message.get("monsters_killed", 0))
	var active_companion = message.get("active_companion", {})
	var collected_companions = message.get("collected_companions", [])
	var incubating_eggs = message.get("incubating_eggs", [])
	var combat_log = message.get("combat_log", [])
	var rounds_fought = int(message.get("rounds_fought", 0))
	var monster_max_hp = int(message.get("monster_max_hp", 0))
	var total_damage_dealt = int(message.get("total_damage_dealt", 0))
	var total_damage_taken = int(message.get("total_damage_taken", 0))

	# === HEADER ===
	display_game("[color=#FF0000]═══════════════════════════════════════════════[/color]")
	display_game("[center][color=#FF0000][b]%s HAS FALLEN[/b][/color][/center]" % char_name.to_upper())
	display_game("[center][color=#FF6666]Slain by %s[/color][/center]" % cause)
	display_game("[color=#FF0000]═══════════════════════════════════════════════[/color]")
	display_game("")

	# === CHARACTER INFO ===
	display_game("[color=#FFD700]── Character ──[/color]")
	display_game("%s %s  |  Level %d  |  XP: %s" % [race, class_type, level, format_number(experience)])
	display_game("Gold: %s  |  Gems: %d  |  Kills: %s" % [format_number(gold), gems, format_number(kills)])
	display_game("")

	# === STATS ===
	if not stats.is_empty():
		display_game("[color=#FFD700]── Stats ──[/color]")
		display_game("STR: %d  |  CON: %d  |  DEX: %d  |  INT: %d  |  WIS: %d  |  WIT: %d" % [
			stats.get("strength", 0), stats.get("constitution", 0), stats.get("dexterity", 0),
			stats.get("intelligence", 0), stats.get("wisdom", 0), stats.get("wits", 0)
		])
		display_game("")

	# === EQUIPMENT ===
	var has_equipment = false
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary and not item.is_empty():
			has_equipment = true
			break

	if has_equipment:
		display_game("[color=#FFD700]── Equipment ──[/color]")
		for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
			var item = equipped.get(slot)
			if item != null and item is Dictionary and not item.is_empty():
				var item_name = item.get("name", "Unknown")
				var rarity = item.get("rarity", "common")
				var item_level = item.get("level", 1)
				var color = _get_rarity_color(rarity)
				display_game("  %s: [color=%s]%s[/color] (Lv %d)" % [slot.capitalize(), color, item_name, item_level])
		display_game("")

	# === COMPANIONS ===
	var has_companions = not active_companion.is_empty() or collected_companions.size() > 0
	if has_companions:
		display_game("[color=#FFD700]── Companions ──[/color]")
		if not active_companion.is_empty():
			var comp_name = active_companion.get("name", "Unknown")
			var comp_level = active_companion.get("level", 1)
			var comp_variant = active_companion.get("variant", "")
			var variant_text = " %s" % comp_variant if comp_variant != "" and comp_variant != "Normal" else ""
			display_game("  [color=#00FF00][ACTIVE][/color] %s%s (Lv %d)" % [comp_name, variant_text, comp_level])
		for comp in collected_companions:
			if comp.get("name", "") == active_companion.get("name", "__none__") and comp.get("level", 0) == active_companion.get("level", -1):
				continue  # Skip active companion (already shown)
			var comp_name = comp.get("name", "Unknown")
			var comp_level = comp.get("level", 1)
			var comp_variant = comp.get("variant", "")
			var variant_text = " %s" % comp_variant if comp_variant != "" and comp_variant != "Normal" else ""
			display_game("  %s%s (Lv %d)" % [comp_name, variant_text, comp_level])
		display_game("")

	# === EGGS ===
	if incubating_eggs.size() > 0:
		display_game("[color=#FFD700]── Eggs ──[/color]")
		for egg in incubating_eggs:
			var egg_name = egg.get("name", "Unknown Egg")
			var steps = egg.get("steps", 0)
			var hatch_at = egg.get("hatch_steps", 500)
			var frozen = egg.get("frozen", false)
			var frozen_text = " [color=#00BFFF][FROZEN][/color]" if frozen else ""
			display_game("  %s (%d/%d steps)%s" % [egg_name, steps, hatch_at, frozen_text])
		display_game("")

	# === COMBAT SUMMARY ===
	if rounds_fought > 0 or combat_log.size() > 0:
		display_game("[color=#FF4444]═══════════════════════════════════════════════[/color]")
		var round_text = "%d Round%s" % [rounds_fought, "s" if rounds_fought != 1 else ""]
		display_game("[center][color=#FF4444][b]FINAL BATTLE - %s[/b][/color][/center]" % round_text)
		display_game("[color=#FF4444]═══════════════════════════════════════════════[/color]")

		# Render monster art client-side (uses base name for correct art lookup)
		var monster_base_name = message.get("monster_base_name", "")
		if monster_base_name != "":
			var local_art = _get_monster_art().get_bordered_art_with_font(monster_base_name, ui_scale_monster_art)
			if local_art != "":
				display_game("[center]" + local_art + "[/center]")
				display_game("")

		var player_max_hp = int(message.get("player_max_hp", 0))
		var player_hp_start = int(message.get("player_hp_at_start", player_max_hp))
		if player_hp_start > 0:
			display_game("[color=#FF6666]Your HP: %s/%s → Killed[/color]" % [format_number(player_hp_start), format_number(player_max_hp)])

		if total_damage_dealt > 0 or total_damage_taken > 0:
			display_game("[color=#00FF00]Damage Dealt: %s[/color]  |  [color=#FF6666]Damage Taken: %s[/color]" % [format_number(total_damage_dealt), format_number(total_damage_taken)])
			if monster_max_hp > 0:
				display_game("[color=#808080]Monster HP: %s[/color]" % format_number(monster_max_hp))
			display_game("")

		# Full combat log
		for entry in combat_log:
			if entry is String:
				display_game(entry)
		display_game("")

	# === BADDIE POINTS ===
	display_game("[color=#FF6600]═══════════════════════════════════════════════[/color]")
	if rank > 0:
		display_game("[center][color=#FFFFFF]Leaderboard Rank: #%d[/color][/center]" % rank)
	if baddie_points > 0:
		display_game("[center][color=#FF6600][b]Baddie Points Earned: %d[/b][/color][/center]" % baddie_points)
		display_game("[center][color=#808080]Return to your Sanctuary to spend them![/color][/center]")
	display_game("[color=#FF6600]═══════════════════════════════════════════════[/color]")
	display_game("")
	display_game("[center][color=#FFD700]Press %s to continue  |  %s to save log[/color][/center]" % [get_action_key_name(0), get_action_key_name(1)])

func _save_death_log():
	"""Save the death screen content to a text file."""
	if last_death_message.is_empty():
		display_game("[color=#FF6666]No death data to save.[/color]")
		return

	var msg = last_death_message
	var char_name = msg.get("character_name", "Unknown")
	var time_str = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var filename = "%s_%s.txt" % [char_name, time_str]
	var dir_path = "user://death_logs"

	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("death_logs"):
		dir.make_dir("death_logs")

	var path = "%s/%s" % [dir_path, filename]
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		display_game("[color=#FF6666]Failed to save death log.[/color]")
		return

	# Build plain text death log
	var bbcode_regex = RegEx.new()
	bbcode_regex.compile("\\[/?[^\\]]+\\]")

	file.store_line("═══════════════════════════════════════════════")
	file.store_line("  %s HAS FALLEN" % char_name.to_upper())
	file.store_line("  Slain by %s" % msg.get("cause_of_death", "Unknown"))
	file.store_line("═══════════════════════════════════════════════")
	file.store_line("")
	file.store_line("── Character ──")
	file.store_line("%s %s  |  Level %d  |  XP: %s" % [msg.get("race", ""), msg.get("class_type", ""), int(msg.get("level", 1)), format_number(int(msg.get("experience", 0)))])
	file.store_line("Gold: %s  |  Gems: %d  |  Kills: %s" % [format_number(int(msg.get("gold", 0))), int(msg.get("gems", 0)), format_number(int(msg.get("monsters_killed", 0)))])
	file.store_line("")

	var stats = msg.get("stats", {})
	if not stats.is_empty():
		file.store_line("── Stats ──")
		file.store_line("STR: %d  |  CON: %d  |  DEX: %d  |  INT: %d  |  WIS: %d  |  WIT: %d" % [
			stats.get("strength", 0), stats.get("constitution", 0), stats.get("dexterity", 0),
			stats.get("intelligence", 0), stats.get("wisdom", 0), stats.get("wits", 0)
		])
		file.store_line("")

	var equipped = msg.get("equipped", {})
	var has_equipment = false
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary and not item.is_empty():
			if not has_equipment:
				file.store_line("── Equipment ──")
				has_equipment = true
			file.store_line("  %s: %s (Lv %d, %s)" % [slot.capitalize(), item.get("name", "Unknown"), item.get("level", 1), item.get("rarity", "common")])
	if has_equipment:
		file.store_line("")

	var combat_log = msg.get("combat_log", [])
	var rounds_fought = int(msg.get("rounds_fought", 0))
	if rounds_fought > 0 or combat_log.size() > 0:
		file.store_line("═══════════════════════════════════════════════")
		file.store_line("  FINAL BATTLE - %d Round%s" % [rounds_fought, "s" if rounds_fought != 1 else ""])
		file.store_line("═══════════════════════════════════════════════")
		var player_max_hp = int(msg.get("player_max_hp", 0))
		var player_hp_start = int(msg.get("player_hp_at_start", player_max_hp))
		if player_hp_start > 0:
			file.store_line("Your HP: %s/%s -> Killed" % [format_number(player_hp_start), format_number(player_max_hp)])
		var total_dmg_dealt = int(msg.get("total_damage_dealt", 0))
		var total_dmg_taken = int(msg.get("total_damage_taken", 0))
		if total_dmg_dealt > 0 or total_dmg_taken > 0:
			file.store_line("Damage Dealt: %s  |  Damage Taken: %s" % [format_number(total_dmg_dealt), format_number(total_dmg_taken)])
		file.store_line("")
		for entry in combat_log:
			if entry is String:
				file.store_line(bbcode_regex.sub(entry, "", true))
		file.store_line("")

	var baddie_points = int(msg.get("baddie_points_earned", 0))
	if baddie_points > 0:
		file.store_line("Baddie Points Earned: %d" % baddie_points)

	file.close()

	var global_path = ProjectSettings.globalize_path(path)
	display_game("[color=#00FF00]Death log saved to: %s[/color]" % global_path)

func show_leaderboard_panel():
	if leaderboard_panel:
		leaderboard_panel.visible = true
	# Request data based on current mode
	if leaderboard_mode == "monster_kills":
		send_to_server({"type": "get_monster_kills_leaderboard", "limit": 20})
	elif leaderboard_mode == "trophy_hall":
		send_to_server({"type": "get_trophy_leaderboard"})
	else:
		send_to_server({"type": "get_leaderboard", "limit": 20})
	# Update toggle button text
	_update_leaderboard_toggle_button()

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
			create_char_button.text = "Max Characters (6)"
		else:
			create_char_button.text = "Create New Character"

func update_leaderboard_display(entries: Array):
	if not leaderboard_list:
		return

	leaderboard_list.clear()
	leaderboard_list.append_text("[center][b]HALL OF FALLEN HEROES[/b][/center]\n\n")

	if entries.is_empty():
		leaderboard_list.append_text("[center][color=#555555]No entries yet. Be the first![/color][/center]")
		_reset_leaderboard_scroll.call_deferred()
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

	# Reset scroll to top after layout updates
	_reset_leaderboard_scroll.call_deferred()

func update_monster_kills_display(entries: Array):
	"""Display the monster kills leaderboard"""
	if not leaderboard_list:
		return

	leaderboard_list.clear()
	leaderboard_list.append_text("[center][b]DEADLIEST MONSTERS[/b][/center]\n\n")

	if entries.is_empty():
		leaderboard_list.append_text("[center][color=#555555]No kills recorded yet.[/color][/center]")
		_reset_leaderboard_scroll.call_deferred()
		return

	var rank = 1
	for entry in entries:
		var monster_name = entry.get("monster_name", "Unknown")
		var kills = entry.get("kills", 0)

		var color = "#FFFFFF"
		if rank == 1:
			color = "#FF0000"  # Red for deadliest
		elif rank == 2:
			color = "#FF6600"  # Orange
		elif rank == 3:
			color = "#FF9900"  # Light orange

		var kill_text = "kill" if kills == 1 else "kills"
		leaderboard_list.append_text("[color=%s]#%d %s[/color]\n" % [color, rank, monster_name])
		leaderboard_list.append_text("   [color=#FF4444]%d player %s[/color]\n\n" % [kills, kill_text])
		rank += 1

	# Reset scroll to top after layout updates
	_reset_leaderboard_scroll.call_deferred()

func update_trophy_leaderboard_display(entries: Array):
	"""Display the trophy hall leaderboard - first collectors of each trophy type"""
	if not leaderboard_list:
		return

	leaderboard_list.clear()
	leaderboard_list.append_text("[center][b]TROPHY HALL OF FAME[/b][/center]\n\n")

	if entries.is_empty():
		leaderboard_list.append_text("[center][color=#555555]No trophies collected yet.[/color][/center]")
		_reset_leaderboard_scroll.call_deferred()
		return

	for entry in entries:
		var trophy_name = entry.get("trophy_name", "Unknown")
		var monster_name = entry.get("monster_name", "Unknown")
		var first_collector = entry.get("collector", "Unknown")
		var total_collectors = entry.get("total_collectors", 0)

		# Color based on trophy rarity (more collectors = more common)
		var color = "#A335EE"  # Purple for rare
		if total_collectors >= 10:
			color = "#FFFFFF"  # White for common
		elif total_collectors >= 5:
			color = "#0070DD"  # Blue for uncommon
		elif total_collectors >= 2:
			color = "#A335EE"  # Purple for rare
		else:
			color = "#FF8000"  # Orange for unique (only 1 collector)

		leaderboard_list.append_text("[color=%s]%s[/color]\n" % [color, trophy_name])
		leaderboard_list.append_text("   [color=#555555]From: %s[/color]\n" % monster_name)
		leaderboard_list.append_text("   [color=#FFD700]First: %s[/color]\n" % first_collector)
		leaderboard_list.append_text("   [color=#555555]Total collectors: %d[/color]\n\n" % total_collectors)

	# Reset scroll to top after layout updates
	_reset_leaderboard_scroll.call_deferred()

func _reset_leaderboard_scroll():
	"""Reset leaderboard scroll to top (called deferred after layout update)"""
	if leaderboard_list:
		leaderboard_list.get_v_scroll_bar().value = 0

func _update_leaderboard_toggle_button():
	"""Update the toggle button text based on current mode"""
	var toggle_button = leaderboard_panel.get_node_or_null("VBox/ToggleButton")
	if toggle_button:
		if leaderboard_mode == "fallen_heroes":
			toggle_button.text = "Show Deadliest Monsters"
		elif leaderboard_mode == "monster_kills":
			toggle_button.text = "Show Trophy Hall"
		else:  # trophy_hall
			toggle_button.text = "Show Fallen Heroes"

func _on_leaderboard_toggle_pressed():
	"""Toggle between Fallen Heroes, Monster Kills, and Trophy Hall views"""
	if leaderboard_mode == "fallen_heroes":
		leaderboard_mode = "monster_kills"
		send_to_server({"type": "get_monster_kills_leaderboard", "limit": 20})
	elif leaderboard_mode == "monster_kills":
		leaderboard_mode = "trophy_hall"
		send_to_server({"type": "get_trophy_leaderboard"})
	else:  # trophy_hall
		leaderboard_mode = "fallen_heroes"
		send_to_server({"type": "get_leaderboard", "limit": 20})
	_update_leaderboard_toggle_button()

func update_online_players(players: Array):
	"""Update the online players list display with clickable names (click to view info)"""
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

		# Use push_meta/pop for reliable click detection (Godot 4.x uses pop() not pop_meta())
		online_players_list.push_meta(pname)
		if not ptitle.is_empty():
			var title_info = _get_title_display_info(ptitle)
			online_players_list.append_text("[color=%s]%s[/color] %s" % [title_info.color, title_info.prefix, pname])
		else:
			online_players_list.append_text(pname)
		online_players_list.pop()
		online_players_list.append_text(" Lv%d %s\n" % [plevel, pclass])

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
	display_game("[color=#FF6666]HP:[/color] %d/%d" % [hp, max_hp])

	# Stats with bonuses (color-coded)
	var stats_line = "[color=#FF6666]STR:[/color]%d" % str_stat
	if bonuses.get("strength", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.strength
	stats_line += " [color=#00FF00]CON:[/color]%d" % con_stat
	if bonuses.get("constitution", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.constitution
	stats_line += " [color=#FFFF00]DEX:[/color]%d" % dex_stat
	if bonuses.get("dexterity", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.dexterity
	display_game(stats_line)

	stats_line = "[color=#9999FF]INT:[/color]%d" % int_stat
	if bonuses.get("intelligence", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.intelligence
	stats_line += " [color=#66CCFF]WIS:[/color]%d" % wis_stat
	if bonuses.get("wisdom", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.wisdom
	stats_line += " [color=#FF00FF]WIT:[/color]%d" % wit_stat
	if bonuses.get("wits", 0) > 0:
		stats_line += "[color=#00FF00](+%d)[/color]" % bonuses.wits
	display_game(stats_line)

	# Combat stats
	display_game("[color=#FFFF00]Attack:[/color] %d  [color=#00FF00]Defense:[/color] %d" % [total_attack, total_defense])

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

	var select_msg = {
		"type": "select_character",
		"name": char_name
	}
	if house_checkout_companion_slot >= 0:
		select_msg["checkout_companion_slot"] = house_checkout_companion_slot
	send_to_server(select_msg)

func _on_create_char_button_pressed():
	show_character_create_panel()

func _on_leaderboard_button_pressed():
	show_leaderboard_panel()

func _on_change_password_button_pressed():
	# Hide character select, show password change UI
	char_select_panel.visible = false
	start_password_change()

func _on_char_select_sanctuary_pressed():
	"""Return to Sanctuary from character select screen"""
	hide_all_panels()
	send_to_server({"type": "house_request"})
	game_state = GameState.HOUSE_SCREEN

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

	var create_msg = {
		"type": "create_character",
		"name": char_name,
		"race": char_race,
		"class": char_class
	}
	if house_checkout_companion_slot >= 0:
		create_msg["checkout_companion_slot"] = house_checkout_companion_slot
	send_to_server(create_msg)

func _on_cancel_create_pressed():
	show_character_select_panel()

# ===== DEATH PANEL HANDLERS =====

func _on_continue_pressed():
	# Reset all game state from the dead character
	_reset_character_state()
	# Return to house (Sanctuary) instead of character select
	send_to_server({"type": "house_request"})
	game_state = GameState.HOUSE_SCREEN

func _reset_character_state():
	"""Reset all character-related state when dying or logging out"""
	has_character = false
	in_combat = false
	character_data = {}
	# Reset dungeon state
	dungeon_mode = false
	dungeon_data = {}
	dungeon_floor_grid = []
	dungeon_available = []
	dungeon_list_mode = false
	# Reset other modes
	inventory_mode = false
	at_merchant = false
	at_trading_post = false
	companions_mode = false
	eggs_mode = false
	more_mode = false
	settings_mode = false
	ability_mode = false
	flock_pending = false
	pending_continue = false
	combat_item_mode = false
	monster_select_mode = false
	# Clear monster HP knowledge (per-character, not shared across characters)
	known_enemy_hp = {}
	# Clear the character stats HUD so old values don't linger
	_clear_character_hud()

func _clear_character_hud():
	"""Clear all character-related HUD elements (level, HP, XP, currency, resource bar)"""
	if player_level_label:
		player_level_label.text = ""
	if player_health_bar:
		var fill = player_health_bar.get_node_or_null("Fill")
		if fill:
			fill.anchor_right = 0.0
		var label = player_health_bar.get_node_or_null("HPLabel")
		if label:
			label.text = ""
		var shield_fill = player_health_bar.get_node_or_null("ShieldFill")
		if shield_fill:
			shield_fill.anchor_right = 0.0
	if player_xp_bar:
		var fill = player_xp_bar.get_node_or_null("Fill")
		if fill:
			fill.anchor_right = 0.0
		var label = player_xp_bar.get_node_or_null("XPLabel")
		if label:
			label.text = ""
		var recent_fill = player_xp_bar.get_node_or_null("RecentFill")
		if recent_fill:
			recent_fill.anchor_right = 0.0
	if resource_bar:
		var fill = resource_bar.get_node_or_null("Fill")
		if fill:
			fill.anchor_right = 0.0
		var label = resource_bar.get_node_or_null("ResourceLabel")
		if label:
			label.text = ""
	if gold_label:
		gold_label.text = ""
	if gem_label:
		gem_label.text = ""
	stop_low_hp_pulse()

# ===== LEADERBOARD HANDLERS =====

func _on_close_leaderboard_pressed():
	if leaderboard_panel:
		leaderboard_panel.visible = false

# ===== PLAYER INFO POPUP HANDLERS =====

func _on_player_name_clicked(meta):
	"""Handle click on player name in online players list - shows player info popup"""
	var player_name = str(meta)
	pending_player_info_request = player_name
	send_to_server({"type": "examine_player", "name": player_name})

func _on_close_player_info_pressed():
	if player_info_panel:
		player_info_panel.visible = false

func _on_player_info_meta_clicked(meta):
	"""Handle click on equipment in player info popup"""
	var meta_str = str(meta)
	if meta_str.begins_with("equip_"):
		var slot = meta_str.substr(6)
		if player_info_equipped.has(slot):
			_show_equipment_detail_in_popup(player_info_equipped[slot], slot)

func _show_equipment_detail_in_popup(item: Dictionary, slot: String):
	"""Append item stats to the player info popup"""
	if not player_info_content:
		return
	var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
	player_info_content.append_text("\n[color=#FF4444]─── Item Details ───[/color]\n")
	player_info_content.append_text("[color=%s][b]%s[/b][/color] (Lv%d %s)\n" % [
		rarity_color, item.get("name", "Unknown"), item.get("level", 1), item.get("rarity", "common").capitalize()
	])
	player_info_content.append_text("[color=#808080]Slot: %s[/color]\n" % slot.capitalize())

	# Show item bonuses
	var bonuses = _compute_item_bonuses(item)
	if bonuses.get("attack", 0) > 0:
		player_info_content.append_text("[color=#FFFF00]+%d Attack[/color]\n" % bonuses.attack)
	if bonuses.get("defense", 0) > 0:
		player_info_content.append_text("[color=#00FF00]+%d Defense[/color]\n" % bonuses.defense)
	if bonuses.get("max_hp", 0) > 0:
		player_info_content.append_text("[color=#FF6666]+%d Max HP[/color]\n" % bonuses.max_hp)
	if bonuses.get("strength", 0) > 0:
		player_info_content.append_text("[color=#FF6666]+%d Strength[/color]\n" % bonuses.strength)
	if bonuses.get("constitution", 0) > 0:
		player_info_content.append_text("[color=#00FF00]+%d Constitution[/color]\n" % bonuses.constitution)
	if bonuses.get("dexterity", 0) > 0:
		player_info_content.append_text("[color=#FFFF00]+%d Dexterity[/color]\n" % bonuses.dexterity)
	if bonuses.get("intelligence", 0) > 0:
		player_info_content.append_text("[color=#9999FF]+%d Intelligence[/color]\n" % bonuses.intelligence)
	if bonuses.get("wisdom", 0) > 0:
		player_info_content.append_text("[color=#66CCFF]+%d Wisdom[/color]\n" % bonuses.wisdom)
	if bonuses.get("wits", 0) > 0:
		player_info_content.append_text("[color=#FF00FF]+%d Wits[/color]\n" % bonuses.wits)
	if bonuses.get("speed", 0) > 0:
		player_info_content.append_text("[color=#FFA500]+%d Speed[/color]\n" % bonuses.speed)
	var mana_bonus = bonuses.get("max_mana", 0)
	var stam_bonus = bonuses.get("max_stamina", 0)
	var energy_bonus = bonuses.get("max_energy", 0)
	if mana_bonus > 0:
		player_info_content.append_text("[color=#9999FF]+%d Max Mana[/color]\n" % mana_bonus)
	if stam_bonus > 0:
		player_info_content.append_text("[color=#FFCC00]+%d Max Stamina[/color]\n" % stam_bonus)
	if energy_bonus > 0:
		player_info_content.append_text("[color=#66FF66]+%d Max Energy[/color]\n" % energy_bonus)

	# Show proc effects
	var procs = item.get("proc_effects", [])
	for proc in procs:
		var proc_name = proc.get("type", "")
		var proc_chance = proc.get("chance", 0)
		var proc_value = proc.get("value", 0)
		if proc_name == "lifesteal":
			player_info_content.append_text("[color=#00FF00]%d%% chance: Lifesteal %d%%[/color]\n" % [proc_chance, proc_value])
		elif proc_name == "execute":
			player_info_content.append_text("[color=#FF4444]%d%% chance: Execute +%d%% damage[/color]\n" % [proc_chance, proc_value])
		elif proc_name == "shocking":
			player_info_content.append_text("[color=#FFFF00]%d%% chance: Shocking (stun)[/color]\n" % proc_chance)

	# Show wear if any
	var wear = item.get("wear", 0)
	if wear > 0:
		player_info_content.append_text("[color=#FF6666]Wear: %d%%[/color]\n" % wear)

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
	player_info_equipped = equipped.duplicate(true)
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
	var title = data.get("title", "")
	var gold = data.get("gold", 0)
	var gems = data.get("gems", 0)
	var deaths = data.get("deaths", 0)
	var quests_done = data.get("quests_completed", 0)
	var play_time = int(data.get("play_time", 0))

	player_info_content.clear()

	# Name with title if present
	if not title.is_empty():
		var title_display = title.capitalize().replace("_", " ")
		player_info_content.append_text("[center][color=#FFD700][b]%s[/b][/color]\n[color=#FF00FF]%s[/color][/center]\n" % [pname, title_display])
	else:
		player_info_content.append_text("[center][color=#FFD700][b]%s[/b][/color][/center]\n" % pname)

	player_info_content.append_text("[center]Level %d %s %s[/center]\n" % [level, char_race, cls])
	player_info_content.append_text("[center][color=#FF00FF]XP:[/color] %d / %d[/center]\n" % [exp, xp_needed])
	player_info_content.append_text("[center][color=#FFD700]%d XP to next level[/color][/center]\n" % xp_remaining)
	player_info_content.append_text("[center]%s[/center]\n\n" % status_text)
	player_info_content.append_text("[color=#FF6666]HP:[/color] %d / %d\n" % [hp, max_hp])

	# Resource based on class path
	if cls in ["Wizard", "Sorcerer", "Sage"]:
		var cur = data.get("current_mana", 0)
		var total = data.get("total_max_mana", 1)
		player_info_content.append_text("[color=#9999FF]Mana:[/color] %d / %d\n" % [cur, total])
	elif cls in ["Thief", "Ranger", "Ninja"]:
		var cur = data.get("current_energy", 0)
		var total = data.get("total_max_energy", 1)
		player_info_content.append_text("[color=#66FF66]Energy:[/color] %d / %d\n" % [cur, total])
	elif cls in ["Fighter", "Barbarian", "Paladin"]:
		var cur = data.get("current_stamina", 0)
		var total = data.get("total_max_stamina", 1)
		player_info_content.append_text("[color=#FFCC00]Stamina:[/color] %d / %d\n" % [cur, total])
	player_info_content.append_text("\n")

	# Stats with equipment bonuses (color-coded)
	player_info_content.append_text("[color=#FF00FF]Stats:[/color]\n")
	var line1 = "  [color=#FF6666]STR:[/color] %d" % str_stat
	if bonuses.get("strength", 0) > 0:
		line1 += "[color=#00FF00](+%d)[/color]" % bonuses.strength
	line1 += "  [color=#00FF00]CON:[/color] %d" % con_stat
	if bonuses.get("constitution", 0) > 0:
		line1 += "[color=#00FF00](+%d)[/color]" % bonuses.constitution
	line1 += "  [color=#FFFF00]DEX:[/color] %d" % dex_stat
	if bonuses.get("dexterity", 0) > 0:
		line1 += "[color=#00FF00](+%d)[/color]" % bonuses.dexterity
	player_info_content.append_text(line1 + "\n")

	var line2 = "  [color=#9999FF]INT:[/color] %d" % int_stat
	if bonuses.get("intelligence", 0) > 0:
		line2 += "[color=#00FF00](+%d)[/color]" % bonuses.intelligence
	line2 += "  [color=#66CCFF]WIS:[/color] %d" % wis_stat
	if bonuses.get("wisdom", 0) > 0:
		line2 += "[color=#00FF00](+%d)[/color]" % bonuses.wisdom
	line2 += "  [color=#FF00FF]WIT:[/color] %d" % wit_stat
	if bonuses.get("wits", 0) > 0:
		line2 += "[color=#00FF00](+%d)[/color]" % bonuses.wits
	player_info_content.append_text(line2 + "\n\n")

	# Combat stats
	player_info_content.append_text("[color=#FFFF00]Attack:[/color] %d  [color=#00FF00]Defense:[/color] %d\n\n" % [total_attack, total_defense])

	# Equipment (clickable for details)
	var has_equipment = false
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			if not has_equipment:
				player_info_content.append_text("[color=#FFA500]Equipment:[/color] [color=#808080](click for details)[/color]\n")
				has_equipment = true
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			player_info_content.append_text("  %s: " % slot.capitalize())
			player_info_content.push_meta("equip_%s" % slot)
			player_info_content.append_text("[color=%s]%s[/color] (Lv%d)" % [rarity_color, item.get("name", "Unknown"), item.get("level", 1)])
			player_info_content.pop()
			player_info_content.append_text("\n")

	if has_equipment:
		player_info_content.append_text("\n")

	# Wealth
	player_info_content.append_text("[color=#FFD700]Gold:[/color] %s  [color=#00FFFF]Gems:[/color] %d\n\n" % [format_number(gold), gems])

	# Statistics
	player_info_content.append_text("[color=#FFA500]Statistics:[/color]\n")
	player_info_content.append_text("  Monsters Slain: %d\n" % kills)
	player_info_content.append_text("  Deaths: %d\n" % deaths)
	player_info_content.append_text("  Quests Completed: %d\n" % quests_done)

	# Format play time
	var hours = play_time / 3600
	var minutes = (play_time % 3600) / 60
	if hours > 0:
		player_info_content.append_text("  Time Played: %dh %dm\n" % [hours, minutes])
	else:
		player_info_content.append_text("  Time Played: %dm\n" % minutes)

	# Location display - visible to title holders and nearby players
	player_info_content.append_text("\n[color=#FFA500]Location:[/color] ")
	if data.get("location_hidden", false):
		# Cloaked player - title holders see "Hidden", others see "???"
		if data.get("viewer_has_title", false):
			player_info_content.append_text("[color=#9932CC]Hidden (Cloaked)[/color]")
		else:
			player_info_content.append_text("[color=#808080]???[/color]")
	elif data.has("location_x") and data.has("location_y"):
		# Location visible (title holder or nearby)
		var loc_x = data.get("location_x", 0)
		var loc_y = data.get("location_y", 0)
		player_info_content.append_text("[color=#00FFFF](%d, %d)[/color]" % [loc_x, loc_y])
	else:
		# Location unknown (too far away)
		player_info_content.append_text("[color=#808080]???[/color]")

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
				# Font size will be set by _scale_action_bar_fonts()

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
				cost_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
				action_container.add_child(cost_label)
			action_cost_labels.append(cost_label)

func _scale_right_panel_fonts(base_scale: float):
	"""Scale right panel fonts (stats, map controls, send button) based on window size and user preference"""
	var stats_size = int(14 * base_scale * ui_scale_right_panel)
	stats_size = clampi(stats_size, 8, 36)

	var small_stats_size = int(12 * base_scale * ui_scale_right_panel)
	small_stats_size = clampi(small_stats_size, 7, 32)

	var movement_size = int(12 * base_scale * ui_scale_right_panel)
	movement_size = clampi(movement_size, 8, 28)

	# Scale level label
	if player_level_label:
		player_level_label.add_theme_font_size_override("font_size", stats_size)

	# Scale gold and gem labels
	if gold_label:
		gold_label.add_theme_font_size_override("font_size", small_stats_size)
	if gem_label:
		gem_label.add_theme_font_size_override("font_size", small_stats_size)

	# Scale movement pad buttons
	if movement_pad:
		for child in movement_pad.get_children():
			if child is Button:
				child.add_theme_font_size_override("font_size", movement_size)

	# Scale send button
	if send_button:
		send_button.add_theme_font_size_override("font_size", movement_size)

	# Scale health bar label
	if player_health_bar:
		var hp_label = player_health_bar.get_node_or_null("HPLabel")
		if hp_label:
			hp_label.add_theme_font_size_override("font_size", stats_size)

	# Scale XP bar label
	if player_xp_bar:
		var xp_label = player_xp_bar.get_node_or_null("XPLabel")
		if xp_label:
			xp_label.add_theme_font_size_override("font_size", stats_size)

	# Scale enemy HP bar label
	if enemy_health_bar:
		var hp_label = enemy_health_bar.get_node_or_null("BarContainer/HPLabel")
		if hp_label:
			hp_label.add_theme_font_size_override("font_size", stats_size)

func _scale_action_bar_fonts(base_scale: float):
	"""Scale action bar button and label fonts based on window size and user preference"""
	var button_size = int(BUTTON_BASE_FONT_SIZE * base_scale * ui_scale_buttons)
	button_size = clampi(button_size, BUTTON_MIN_FONT_SIZE, BUTTON_MAX_FONT_SIZE)

	var cost_size = int(9 * base_scale * ui_scale_buttons)
	cost_size = clampi(cost_size, 7, 36)

	var hotkey_size = int(9 * base_scale * ui_scale_buttons)
	hotkey_size = clampi(hotkey_size, 7, 36)

	for button in action_buttons:
		if button:
			button.add_theme_font_size_override("font_size", button_size)

	for cost_label in action_cost_labels:
		if cost_label:
			cost_label.add_theme_font_size_override("font_size", cost_size)

	for hotkey_label in action_hotkey_labels:
		if hotkey_label:
			hotkey_label.add_theme_font_size_override("font_size", hotkey_size)

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
		elif settings_submenu == "ui_scale":
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "settings_back_to_main", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Press 1-9", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "to adjust", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif settings_submenu == "sound":
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "settings_back_to_main", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Press 1-5", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "to adjust", "action_type": "none", "action_data": "", "enabled": false},
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
				{"label": "Abilities", "action_type": "local", "action_data": "settings_abilities", "enabled": true},
				{"label": "UI Scale", "action_type": "local", "action_data": "settings_ui_scale", "enabled": true},
				{"label": "Sound", "action_type": "local", "action_data": "settings_sound", "enabled": true},
			]
	elif game_state == GameState.DEAD:
		current_actions = [
			{"label": "Continue", "action_type": "local", "action_data": "death_continue", "enabled": true},
			{"label": "Save Log", "action_type": "local", "action_data": "save_death_log", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif game_state == GameState.HOUSE_SCREEN:
		# House/Sanctuary screen - roguelite hub
		if house_mode == "storage":
			var storage_items = house_data.get("storage", {}).get("items", [])
			var has_stored_companions = false
			for item in storage_items:
				if item.get("type") == "stored_companion":
					has_stored_companions = true
					break
			var kennel_has_space = house_data.get("registered_companions", {}).get("companions", []).size() < _get_house_companion_capacity()

			if pending_house_action == "withdraw_select":
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "house_storage_back", "enabled": true},
					{"label": "Prev", "action_type": "local", "action_data": "house_storage_prev", "enabled": house_storage_page > 0},
					{"label": "Next", "action_type": "local", "action_data": "house_storage_next", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "Clear", "action_type": "local", "action_data": "house_withdraw_clear", "enabled": house_storage_withdraw_items.size() > 0},
					{"label": "1-5=Mark", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
			elif pending_house_action == "discard_select":
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "house_storage_back", "enabled": true},
					{"label": "Prev", "action_type": "local", "action_data": "house_storage_prev", "enabled": house_storage_page > 0},
					{"label": "Next", "action_type": "local", "action_data": "house_storage_next", "enabled": true},
					{"label": "Confirm", "action_type": "local", "action_data": "house_discard_confirm", "enabled": house_storage_discard_index >= 0},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "1-5=Pick", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
			elif pending_house_action == "register_select":
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "house_storage_back", "enabled": true},
					{"label": "Prev", "action_type": "local", "action_data": "house_storage_prev", "enabled": house_storage_page > 0},
					{"label": "Next", "action_type": "local", "action_data": "house_storage_next", "enabled": true},
					{"label": "Confirm", "action_type": "local", "action_data": "house_register_confirm", "enabled": house_storage_register_index >= 0},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "1-5=Pick", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
			else:
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "house_main", "enabled": true},
					{"label": "Prev", "action_type": "local", "action_data": "house_storage_prev", "enabled": house_storage_page > 0},
					{"label": "Next", "action_type": "local", "action_data": "house_storage_next", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "Withdraw", "action_type": "local", "action_data": "house_withdraw_start", "enabled": storage_items.size() > 0},
					{"label": "Discard", "action_type": "local", "action_data": "house_discard_start", "enabled": storage_items.size() > 0},
					{"label": "Register", "action_type": "local", "action_data": "house_register_start", "enabled": has_stored_companions and kennel_has_space},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
		elif house_mode == "companions":
			var companions = house_data.get("registered_companions", {}).get("companions", [])
			var has_available = false
			for comp in companions:
				if comp.get("checked_out_by") == null:
					has_available = true
					break

			if pending_house_action == "checkout_select":
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "house_companions_back", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "Clear", "action_type": "local", "action_data": "house_checkout_clear", "enabled": house_checkout_companion_slot >= 0},
					{"label": "1-5=Mark", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
			elif pending_house_action == "unregister_select":
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "house_companions_back", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "Confirm", "action_type": "local", "action_data": "house_unregister_confirm", "enabled": house_unregister_companion_slot >= 0},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "1-5=Pick", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
			else:
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "house_main", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "Checkout", "action_type": "local", "action_data": "house_checkout_start", "enabled": has_available},
					{"label": "Unregist", "action_type": "local", "action_data": "house_unregister_start", "enabled": has_available},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
		elif house_mode == "upgrades":
			var page_labels = ["Base", "Combat", "Stats"]
			var page_buy_labels = ["1-6=Buy", "1-3=Buy", "1-6=Buy"]
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "house_main", "enabled": true},
				{"label": "< Prev", "action_type": "local", "action_data": "upgrades_prev", "enabled": house_upgrades_page > 0},
				{"label": "Next >", "action_type": "local", "action_data": "upgrades_next", "enabled": house_upgrades_page < 2},
				{"label": page_labels[house_upgrades_page], "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": page_buy_labels[house_upgrades_page], "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:  # house_mode == "main" or ""
			# Context-sensitive action bar based on what player is standing on
			var interact_label = "---"
			var interact_action = ""
			var interact_enabled = false

			match house_interactable_at:
				"C":
					interact_label = "Companion"
					interact_action = "house_companions"
					interact_enabled = true
				"S":
					interact_label = "Storage"
					interact_action = "house_storage"
					interact_enabled = true
				"U":
					interact_label = "Upgrades"
					interact_action = "house_upgrades"
					interact_enabled = true
				"D":
					interact_label = "Play"
					interact_action = "house_play"
					interact_enabled = true

			current_actions = [
				{"label": interact_label, "action_type": "local", "action_data": interact_action, "enabled": interact_enabled},
				{"label": "Logout", "action_type": "local", "action_data": "house_logout", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Settings", "action_type": "local", "action_data": "settings", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif pending_summon_from != "":
		# Incoming summon request - Decline (slot 0), Accept (slot 1)
		current_actions = [
			{"label": "Decline", "action_type": "local", "action_data": "summon_decline", "enabled": true},
			{"label": "Accept", "action_type": "local", "action_data": "summon_accept", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif title_stat_selection_mode:
		# Bless stat selection - Choose which stat to give +5 to
		current_actions = [
			{"label": "Cancel", "action_type": "local", "action_data": "bless_cancel", "enabled": true},
			{"label": "STR", "action_type": "local", "action_data": "bless_stat_str", "enabled": true},
			{"label": "CON", "action_type": "local", "action_data": "bless_stat_con", "enabled": true},
			{"label": "DEX", "action_type": "local", "action_data": "bless_stat_dex", "enabled": true},
			{"label": "INT", "action_type": "local", "action_data": "bless_stat_int", "enabled": true},
			{"label": "WIS", "action_type": "local", "action_data": "bless_stat_wis", "enabled": true},
			{"label": "WIT", "action_type": "local", "action_data": "bless_stat_wit", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif pending_trade_request != "":
		# Incoming trade request - Decline (slot 0), Accept (slot 1)
		current_actions = [
			{"label": "Decline", "action_type": "local", "action_data": "trade_decline", "enabled": true},
			{"label": "Accept", "action_type": "local", "action_data": "trade_accept", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif pending_blacksmith:
		# Wandering blacksmith encounter - different modes
		if blacksmith_upgrade_mode == "select_item":
			# Selecting item for upgrade
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "blacksmith_cancel_upgrade", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-9=Item", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif blacksmith_upgrade_mode == "select_affix":
			# Selecting affix to upgrade
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "blacksmith_cancel_upgrade", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-9=Affix", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Main repair/upgrade menu
			current_actions = [
				{"label": "Decline", "action_type": "local", "action_data": "blacksmith_decline", "enabled": true},
				{"label": "All", "action_type": "local", "action_data": "blacksmith_repair_all", "enabled": blacksmith_items.size() > 0},
				{"label": "Enhance", "action_type": "local", "action_data": "blacksmith_upgrade", "enabled": blacksmith_can_upgrade},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-9=Item", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif pending_healer:
		# Wandering healer encounter - Heal options
		current_actions = [
			{"label": "Decline", "action_type": "local", "action_data": "healer_decline", "enabled": true},
			{"label": "Quick", "action_type": "local", "action_data": "healer_quick", "enabled": true},
			{"label": "Full", "action_type": "local", "action_data": "healer_full", "enabled": true},
			{"label": "Cure", "action_type": "local", "action_data": "healer_cure_all", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif fishing_mode:
		# Fishing minigame
		if fishing_phase == "waiting":
			# Waiting for bite - only cancel option
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "fishing_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Wait...", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Reaction phase - show pattern keys (Q, W, E, R) with current key highlighted
			var current_key = gathering_pattern[gathering_pattern_index] if gathering_pattern_index < gathering_pattern.size() else ""
			current_actions = [
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "[Q]" if current_key == "Q" else "Q", "action_type": "none", "action_data": "", "enabled": current_key == "Q"},
				{"label": "[W]" if current_key == "W" else "W", "action_type": "none", "action_data": "", "enabled": current_key == "W"},
				{"label": "[E]" if current_key == "E" else "E", "action_type": "none", "action_data": "", "enabled": current_key == "E"},
				{"label": "[R]" if current_key == "R" else "R", "action_type": "none", "action_data": "", "enabled": current_key == "R"},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif mining_mode:
		# Mining minigame
		if mining_phase == "waiting":
			var progress = "%d/%d" % [mining_reactions_completed, mining_reactions_required] if mining_reactions_required > 1 else ""
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "mining_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Mining..." + progress, "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Reaction phase - show pattern keys (Q, W, E, R) with current key highlighted
			var current_key = gathering_pattern[gathering_pattern_index] if gathering_pattern_index < gathering_pattern.size() else ""
			current_actions = [
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "[Q]" if current_key == "Q" else "Q", "action_type": "none", "action_data": "", "enabled": current_key == "Q"},
				{"label": "[W]" if current_key == "W" else "W", "action_type": "none", "action_data": "", "enabled": current_key == "W"},
				{"label": "[E]" if current_key == "E" else "E", "action_type": "none", "action_data": "", "enabled": current_key == "E"},
				{"label": "[R]" if current_key == "R" else "R", "action_type": "none", "action_data": "", "enabled": current_key == "R"},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif logging_mode:
		# Logging minigame
		if logging_phase == "waiting":
			var progress = "%d/%d" % [logging_reactions_completed, logging_reactions_required] if logging_reactions_required > 1 else ""
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "logging_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Chopping..." + progress, "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		else:
			# Reaction phase - show pattern keys (Q, W, E, R) with current key highlighted
			var current_key = gathering_pattern[gathering_pattern_index] if gathering_pattern_index < gathering_pattern.size() else ""
			current_actions = [
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "[Q]" if current_key == "Q" else "Q", "action_type": "none", "action_data": "", "enabled": current_key == "Q"},
				{"label": "[W]" if current_key == "W" else "W", "action_type": "none", "action_data": "", "enabled": current_key == "W"},
				{"label": "[E]" if current_key == "E" else "E", "action_type": "none", "action_data": "", "enabled": current_key == "E"},
				{"label": "[R]" if current_key == "R" else "R", "action_type": "none", "action_data": "", "enabled": current_key == "R"},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
	elif dungeon_list_mode:
		# Viewing list of available dungeons - select with 1-9
		var total_pages = max(1, ceili(float(dungeon_available.size()) / 5.0))
		var current_page = 0  # Always page 0 for now
		current_actions = [
			{"label": "Back", "action_type": "local", "action_data": "dungeon_list_cancel", "enabled": true},
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
	elif dungeon_mode and pending_continue:
		# In dungeon, waiting for player to continue after combat/event
		current_actions = [
			{"label": "Continue", "action_type": "local", "action_data": "dungeon_continue", "enabled": true},
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
	elif dungeon_mode and not in_combat and not pending_continue and not flock_pending and not inventory_mode:
		# In dungeon (not fighting, not waiting for continue/flock) - movement and actions
		# Exit is on slot 5 (key 1), Inventory on slot 6 (key 2) for item use
		current_actions = [
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "N", "action_type": "local", "action_data": "dungeon_move_n", "enabled": true},
			{"label": "S", "action_type": "local", "action_data": "dungeon_move_s", "enabled": true},
			{"label": "W", "action_type": "local", "action_data": "dungeon_move_w", "enabled": true},
			{"label": "E", "action_type": "local", "action_data": "dungeon_move_e", "enabled": true},
			{"label": "Exit", "action_type": "local", "action_data": "dungeon_exit", "enabled": true},
			{"label": "Items", "action_type": "local", "action_data": "inventory", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif in_trade:
		# Active trade session
		if trade_pending_add:
			# Selecting item to add - show Back button, items selected via number keys
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "trade_cancel_add", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Prev", "action_type": "local", "action_data": "trade_page_prev", "enabled": inventory_page > 0},
				{"label": "Next", "action_type": "local", "action_data": "trade_page_next", "enabled": true},
			]
		elif trade_pending_add_companion:
			# Selecting companion to add
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "trade_cancel_add", "enabled": true},
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
		elif trade_pending_add_egg:
			# Selecting egg to add
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "trade_cancel_add", "enabled": true},
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
			# Main trade window - buttons depend on current tab
			var ready_label = "Unready" if trade_my_ready else "Ready"
			var add_label = "Add"
			var has_items_to_remove = false
			match trade_tab:
				"items":
					add_label = "Add Item"
					has_items_to_remove = trade_my_items.size() > 0
				"companions":
					add_label = "Add Comp"
					has_items_to_remove = trade_my_companions.size() > 0
				"eggs":
					add_label = "Add Egg"
					has_items_to_remove = trade_my_eggs.size() > 0
			current_actions = [
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": add_label, "action_type": "local", "action_data": "trade_add", "enabled": true},
				{"label": "Remove", "action_type": "local", "action_data": "trade_remove", "enabled": has_items_to_remove},
				{"label": ready_label, "action_type": "local", "action_data": "trade_toggle_ready", "enabled": true},
				{"label": "Cancel", "action_type": "local", "action_data": "trade_cancel", "enabled": true},
				{"label": "Items", "action_type": "local", "action_data": "trade_tab_items", "enabled": trade_tab != "items"},
				{"label": "Comps", "action_type": "local", "action_data": "trade_tab_companions", "enabled": trade_tab != "companions"},
				{"label": "Eggs", "action_type": "local", "action_data": "trade_tab_eggs", "enabled": trade_tab != "eggs"},
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
			# Confirmation mode - Back (slot 0), Confirm (slot 1)
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "monster_select_back", "enabled": true},
				{"label": "Confirm", "action_type": "local", "action_data": "monster_select_confirm", "enabled": true},
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
	elif home_stone_mode:
		# Home Stone selection - Space=Cancel, 1-N=Select
		current_actions = [
			{"label": "Cancel", "action_type": "local", "action_data": "home_stone_cancel", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "1-%d Select" % home_stone_options.size(), "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif ability_mode:
		# Ability management mode
		if pending_ability_action == "choose_ability":
			# Choosing an ability from list (with pagination)
			var unlocked = ability_data.get("unlocked_abilities", [])
			var total_pages = max(1, (unlocked.size() + ABILITY_PAGE_SIZE - 1) / ABILITY_PAGE_SIZE)
			var start_idx = ability_choice_page * ABILITY_PAGE_SIZE
			var end_idx = min(start_idx + ABILITY_PAGE_SIZE, unlocked.size())
			var items_on_page = end_idx - start_idx

			var prev_label = "Prev" if ability_choice_page > 0 else "---"
			var prev_action = "ability_prev_page" if ability_choice_page > 0 else ""
			var next_label = "Next" if ability_choice_page < total_pages - 1 else "---"
			var next_action = "ability_next_page" if ability_choice_page < total_pages - 1 else ""

			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "ability_cancel", "enabled": true},
				{"label": prev_label, "action_type": "local" if prev_action else "none", "action_data": prev_action, "enabled": prev_action != ""},
				{"label": next_label, "action_type": "local" if next_action else "none", "action_data": next_action, "enabled": next_action != ""},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-%d Select" % items_on_page, "action_type": "none", "action_data": "", "enabled": false},
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
			# Selecting a slot (1-6)
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "ability_cancel", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-6 Slot", "action_type": "none", "action_data": "", "enabled": false},
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
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
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
		var swap_attack = character_data.get("swap_attack_with_ability", false)

		# Build base combat actions
		var attack_action = {"label": "Attack", "action_type": "combat", "action_data": "attack", "enabled": true}
		var first_ability = ability_actions[0] if ability_actions.size() > 0 else {"label": "---", "action_type": "none", "action_data": "", "enabled": false}

		if swap_attack and ability_actions.size() > 0:
			# Swap: First ability on Space, Attack on slot 5 (R key)
			current_actions = [
				first_ability,
				{"label": "Use Item", "action_type": "local", "action_data": "combat_item", "enabled": has_items},
				{"label": "Flee", "action_type": "combat", "action_data": "flee", "enabled": true},
				{"label": "Outsmart", "action_type": "combat", "action_data": "outsmart", "enabled": can_outsmart},
				attack_action,  # Attack moves to slot 5
			]
			# Add remaining abilities (skip first since it's on slot 1)
			for i in range(1, min(6, ability_actions.size())):
				current_actions.append(ability_actions[i])
		else:
			# Normal layout (with optional Attack/Outsmart swap)
			var outsmart_action = {"label": "Outsmart", "action_type": "combat", "action_data": "outsmart", "enabled": can_outsmart}
			if swap_attack_outsmart:
				# Swap: Outsmart on Space, Attack on E
				current_actions = [
					outsmart_action,
					{"label": "Use Item", "action_type": "local", "action_data": "combat_item", "enabled": has_items},
					{"label": "Flee", "action_type": "combat", "action_data": "flee", "enabled": true},
					attack_action,
				]
			else:
				# Default: Attack on Space
				current_actions = [
					attack_action,
					{"label": "Use Item", "action_type": "local", "action_data": "combat_item", "enabled": has_items},
					{"label": "Flee", "action_type": "combat", "action_data": "flee", "enabled": true},
					outsmart_action,
				]
			# Add all ability slots
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
	elif not pending_dungeon_warning.is_empty():
		# Dungeon level warning - awaiting confirmation
		current_actions = [
			{"label": "Enter Anyway", "action_type": "local", "action_data": "dungeon_warning_confirm", "enabled": true},
			{"label": "Cancel", "action_type": "local", "action_data": "dungeon_warning_cancel", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif not pending_corpse_loot.is_empty():
		# Corpse loot confirmation - awaiting confirmation
		current_actions = [
			{"label": "Loot All", "action_type": "local", "action_data": "corpse_loot_confirm", "enabled": true},
			{"label": "Cancel", "action_type": "local", "action_data": "corpse_loot_cancel", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif more_mode:
		# More menu - contains Companions, Eggs, Leaders, etc.
		current_actions = [
			{"label": "Back", "action_type": "local", "action_data": "more_close", "enabled": true},
			{"label": "Companions", "action_type": "local", "action_data": "companions", "enabled": true},
			{"label": "Eggs", "action_type": "local", "action_data": "eggs_menu", "enabled": true},
			{"label": "Leaders", "action_type": "local", "action_data": "leaderboard", "enabled": true},
			{"label": "Changes", "action_type": "local", "action_data": "changelog", "enabled": true},
			{"label": "Bestiary", "action_type": "local", "action_data": "bestiary", "enabled": true},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
		]
	elif companions_mode:
		# Companions viewing mode with pagination and release
		var collected = character_data.get("collected_companions", [])
		var total_pages = int(ceil(float(collected.size()) / float(COMPANIONS_PAGE_SIZE))) if collected.size() > 0 else 1
		var has_prev = companions_page > 0
		var has_next = companions_page < total_pages - 1

		if pending_companion_action == "release_all_confirm":
			# FINAL confirmation for releasing ALL companions
			current_actions = [
				{"label": "CANCEL", "action_type": "local", "action_data": "release_cancel", "enabled": true},
				{"label": "DELETE ALL", "action_type": "local", "action_data": "release_all_final", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_companion_action == "release_all_warn":
			# First warning for releasing ALL companions
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "release_cancel", "enabled": true},
				{"label": "Continue", "action_type": "local", "action_data": "release_all_continue", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_companion_action == "release_confirm":
			# Confirmation screen for releasing a companion
			var comp_name = release_target_companion.get("name", "Unknown")
			var variant = release_target_companion.get("variant", "Normal")
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "release_cancel", "enabled": true},
				{"label": "CONFIRM", "action_type": "local", "action_data": "release_confirm", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_companion_action == "release_select":
			# Selecting which companion to release
			var page_count = min(COMPANIONS_PAGE_SIZE, collected.size() - companions_page * COMPANIONS_PAGE_SIZE)
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "release_cancel", "enabled": true},
				{"label": "< Prev", "action_type": "local", "action_data": "companions_prev", "enabled": has_prev},
				{"label": "Next >", "action_type": "local", "action_data": "companions_next", "enabled": has_next},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "1-%d Select" % page_count, "action_type": "none", "action_data": "", "enabled": false} if page_count > 0 else {"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_companion_action == "inspect":
			# Inspecting a companion's details
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "inspect_back", "enabled": true},
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
			# Normal companions menu
			var page_count = min(COMPANIONS_PAGE_SIZE, collected.size() - companions_page * COMPANIONS_PAGE_SIZE) if collected.size() > 0 else 0
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "companions_close", "enabled": true},
				{"label": "< Prev", "action_type": "local", "action_data": "companions_prev", "enabled": has_prev},
				{"label": "Next >", "action_type": "local", "action_data": "companions_next", "enabled": has_next},
				{"label": "Inspect", "action_type": "local", "action_data": "companions_inspect", "enabled": collected.size() > 0},
				{"label": "Release", "action_type": "local", "action_data": "companions_release", "enabled": collected.size() > 0},
				{"label": "1-%d Select" % page_count, "action_type": "none", "action_data": "", "enabled": false} if page_count > 0 else {"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "Dismiss", "action_type": "local", "action_data": "companions_dismiss", "enabled": not character_data.get("active_companion", {}).is_empty()},
				{"label": "Sort", "action_type": "local", "action_data": "companions_sort", "enabled": collected.size() > 1},
				{"label": "Asc/Desc", "action_type": "local", "action_data": "companions_sort_dir", "enabled": collected.size() > 1},
				{"label": "Rel. All", "action_type": "local", "action_data": "companions_release_all", "enabled": collected.size() > 1},
			]
	elif eggs_mode:
		# Eggs viewing mode with pagination
		var eggs = character_data.get("incubating_eggs", [])
		var total_pages = int(ceil(float(eggs.size()) / float(EGGS_PAGE_SIZE))) if eggs.size() > 0 else 1
		var has_prev = eggs_page > 0
		var has_next = eggs_page < total_pages - 1
		# Build freeze toggle buttons for visible eggs (1-3 based on current page)
		var start_idx = eggs_page * EGGS_PAGE_SIZE
		var freeze_buttons = []
		for i in range(EGGS_PAGE_SIZE):
			var egg_idx = start_idx + i
			if egg_idx < eggs.size():
				var egg = eggs[egg_idx]
				var is_frozen = egg.get("frozen", false)
				var label = "Unfrz %d" % (i + 1) if is_frozen else "Freeze %d" % (i + 1)
				freeze_buttons.append({"label": label, "action_type": "local", "action_data": "egg_toggle_freeze_%d" % egg_idx, "enabled": true})
			else:
				freeze_buttons.append({"label": "---", "action_type": "none", "action_data": "", "enabled": false})
		current_actions = [
			{"label": "Back", "action_type": "local", "action_data": "eggs_close", "enabled": true},
			{"label": "< Prev", "action_type": "local", "action_data": "eggs_prev", "enabled": has_prev},
			{"label": "Next >", "action_type": "local", "action_data": "eggs_next", "enabled": has_next},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			freeze_buttons[0],
			freeze_buttons[1],
			freeze_buttons[2],
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
				{"label": "Sell Equip", "action_type": "local", "action_data": "sell_all_items", "enabled": has_items},
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
			# Calculate if Upgrade All is affordable
			var upgrade_all_cost = _calculate_upgrade_all_cost()
			var can_upgrade_all = upgrade_all_cost > 0 and character_data.get("gold", 0) >= upgrade_all_cost
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "merchant_cancel", "enabled": true},
				{"label": "Weapon", "action_type": "local", "action_data": "upgrade_weapon", "enabled": equipped.get("weapon") != null},
				{"label": "Armor", "action_type": "local", "action_data": "upgrade_armor", "enabled": equipped.get("armor") != null},
				{"label": "Helm", "action_type": "local", "action_data": "upgrade_helm", "enabled": equipped.get("helm") != null},
				{"label": "Shield", "action_type": "local", "action_data": "upgrade_shield", "enabled": equipped.get("shield") != null},
				{"label": "Boots", "action_type": "local", "action_data": "upgrade_boots", "enabled": equipped.get("boots") != null},
				{"label": "Ring", "action_type": "local", "action_data": "upgrade_ring", "enabled": equipped.get("ring") != null},
				{"label": "Amulet", "action_type": "local", "action_data": "upgrade_amulet", "enabled": equipped.get("amulet") != null},
				{"label": "All+1(%dg)" % upgrade_all_cost if upgrade_all_cost > 0 else "All+1", "action_type": "local", "action_data": "upgrade_all", "enabled": can_upgrade_all},
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
		if pending_inventory_action == "sort_select":
			# Sort submenu - show sort options (2 pages)
			if sort_menu_page == 0:
				# Page 1: Main sort options
				current_actions = [
					{"label": "Cancel", "action_type": "local", "action_data": "sort_cancel", "enabled": true},
					{"label": "Level", "action_type": "local", "action_data": "sort_by_level", "enabled": true},
					{"label": "HP", "action_type": "local", "action_data": "sort_by_hp", "enabled": true},
					{"label": "ATK", "action_type": "local", "action_data": "sort_by_atk", "enabled": true},
					{"label": "DEF", "action_type": "local", "action_data": "sort_by_def", "enabled": true},
					{"label": "WIT", "action_type": "local", "action_data": "sort_by_wit", "enabled": true},
					{"label": "Mana", "action_type": "local", "action_data": "sort_by_mana", "enabled": true},
					{"label": "Speed", "action_type": "local", "action_data": "sort_by_speed", "enabled": true},
					{"label": "Slot", "action_type": "local", "action_data": "sort_by_slot", "enabled": true},
					{"label": "More...", "action_type": "local", "action_data": "sort_more", "enabled": true},
				]
			else:
				# Page 2: Rarity and Compare options
				var cmp_label = "Cmp:%s" % inventory_compare_stat.to_upper().left(3)
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "sort_back", "enabled": true},
					{"label": "Rarity", "action_type": "local", "action_data": "sort_by_rarity", "enabled": true},
					{"label": cmp_label, "action_type": "local", "action_data": "cycle_compare_stat", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
		elif pending_inventory_action == "viewing_materials":
			# Materials view - show back button
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "materials_back", "enabled": true},
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
		elif pending_inventory_action == "salvage_select":
			# Salvage submenu - show salvage and discard options
			var player_level = character_data.get("level", 1)
			var threshold = max(1, player_level - 5)
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "salvage_cancel", "enabled": true},
				{"label": "All(<Lv%d)" % threshold, "action_type": "local", "action_data": "salvage_below_level", "enabled": true},
				{"label": "All Equipment", "action_type": "local", "action_data": "salvage_all", "enabled": true},
				{"label": "Consumables", "action_type": "local", "action_data": "salvage_consumables_prompt", "enabled": true},
				{"label": "Discard", "action_type": "local", "action_data": "inventory_discard", "enabled": true},
				{"label": "Materials", "action_type": "local", "action_data": "view_materials", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_inventory_action == "salvage_consumables_confirm":
			# Confirmation prompt for salvaging consumables
			current_actions = [
				{"label": "Cancel", "action_type": "local", "action_data": "salvage_cancel", "enabled": true},
				{"label": "Confirm", "action_type": "local", "action_data": "salvage_consumables", "enabled": true},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
			]
		elif pending_inventory_action == "equip_confirm":
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
			var equipped = character_data.get("equipped", {})
			var has_equipped = _count_equipped_items(equipped) > 0
			var inv = character_data.get("inventory", [])
			var total_pages = max(1, int(ceil(float(inv.size()) / INVENTORY_PAGE_SIZE)))
			var has_prev = inventory_page > 0
			var has_next = inventory_page < total_pages - 1
			current_actions = [
				{"label": "Back", "action_type": "local", "action_data": "inventory_back", "enabled": true},
				{"label": "Inspect", "action_type": "local", "action_data": "inventory_inspect", "enabled": true},
				{"label": "Use", "action_type": "local", "action_data": "inventory_use", "enabled": true},
				{"label": "Equip", "action_type": "local", "action_data": "inventory_equip", "enabled": true},
				{"label": "Unequip", "action_type": "local", "action_data": "inventory_unequip", "enabled": true},
				{"label": "Sort", "action_type": "local", "action_data": "inventory_sort", "enabled": true},
				{"label": "Salvage", "action_type": "local", "action_data": "inventory_salvage", "enabled": true},
				{"label": "Lock", "action_type": "local", "action_data": "inventory_lock", "enabled": true},
				{"label": "Prev Pg", "action_type": "local", "action_data": "inventory_prev_page", "enabled": has_prev},
				{"label": "Next Pg", "action_type": "local", "action_data": "inventory_next_page", "enabled": has_next},
			]
	elif at_trading_post:
		# Trading Post mode
		if crafting_mode:
			# Crafting sub-menu
			if crafting_skill == "":
				# Skill selection
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "crafting_cancel", "enabled": true},
					{"label": "Smith", "action_type": "local", "action_data": "crafting_skill_blacksmithing", "enabled": true},
					{"label": "Alchemy", "action_type": "local", "action_data": "crafting_skill_alchemy", "enabled": true},
					{"label": "Enchant", "action_type": "local", "action_data": "crafting_skill_enchanting", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
			elif crafting_selected_recipe >= 0:
				# Recipe confirm
				current_actions = [
					{"label": "Cancel", "action_type": "local", "action_data": "crafting_recipe_cancel", "enabled": true},
					{"label": "Craft!", "action_type": "local", "action_data": "crafting_confirm", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
				]
			elif awaiting_craft_result:
				# Showing craft result - wait for player to continue
				current_actions = [
					{"label": "Continue", "action_type": "local", "action_data": "crafting_continue", "enabled": true},
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
				# Recipe list
				var total_pages = max(1, ceili(float(crafting_recipes.size()) / CRAFTING_PAGE_SIZE))
				var has_prev = crafting_page > 0
				var has_next = crafting_page < total_pages - 1
				current_actions = [
					{"label": "Back", "action_type": "local", "action_data": "crafting_skill_cancel", "enabled": true},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "1-5 Select", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "---", "action_type": "none", "action_data": "", "enabled": false},
					{"label": "Prev Pg", "action_type": "local", "action_data": "crafting_prev_page", "enabled": has_prev},
					{"label": "Next Pg", "action_type": "local", "action_data": "crafting_next_page", "enabled": has_next},
				]
		elif quest_view_mode:
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
			# Main Trading Post menu (player walks out to leave)
			# Get recharge cost from server (includes distance scaling)
			var recharge_cost = trading_post_data.get("recharge_cost", 100)
			# Check if at special title locations (use trading post position)
			var tp_x = trading_post_data.get("x", -999)
			var tp_y = trading_post_data.get("y", -999)
			var at_high_seat = (tp_x == 0 and tp_y == 0)
			var player_title = character_data.get("title", "")
			var has_title = not player_title.is_empty()
			# Fifth slot: High Seat at (0,0) or Title if has title, else Craft
			var fifth_action: Dictionary
			if has_title:
				fifth_action = {"label": "Title", "action_type": "local", "action_data": "title", "enabled": true}
			elif at_high_seat:
				fifth_action = {"label": "High Seat", "action_type": "local", "action_data": "title", "enabled": true}
			else:
				fifth_action = {"label": "Craft", "action_type": "local", "action_data": "open_crafting", "enabled": true}
			# Sixth slot: Craft if fifth slot is Title/High Seat, otherwise placeholder
			var sixth_action: Dictionary
			if has_title or at_high_seat:
				sixth_action = {"label": "Craft", "action_type": "local", "action_data": "open_crafting", "enabled": true}
			else:
				sixth_action = {"label": "---", "action_type": "none", "action_data": "", "enabled": false}
			current_actions = [
				{"label": "Status", "action_type": "local", "action_data": "show_status", "enabled": true},
				{"label": "Shop", "action_type": "local", "action_data": "trading_post_shop", "enabled": true},
				{"label": "Quests", "action_type": "local", "action_data": "trading_post_quests", "enabled": true},
				{"label": "Heal(%dg)" % recharge_cost, "action_type": "local", "action_data": "trading_post_recharge", "enabled": true},
				fifth_action,
				sixth_action,
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
		# Check if at special title locations
		var player_x = character_data.get("x", 0)
		var player_y = character_data.get("y", 0)
		var at_high_seat = (player_x == 0 and player_y == 0)
		var at_fire_mountain = (player_x == -400 and player_y == 0)
		# Use "Title" button for titled players, "High Seat" at (0,0), otherwise "Help"
		var fourth_action: Dictionary
		if has_title:
			fourth_action = {"label": "Title", "action_type": "local", "action_data": "title", "enabled": true}
		elif at_high_seat:
			fourth_action = {"label": "High Seat", "action_type": "local", "action_data": "title", "enabled": true}
		else:
			fourth_action = {"label": "Help", "action_type": "local", "action_data": "help", "enabled": true}
		# Forge button if at Infernal Forge with Unforged Crown, or "Fire Mt" at fire mountain
		# Or gathering actions (Fish/Mine/Chop) at appropriate tiles, or Dungeon at dungeon entrances
		var fifth_action: Dictionary
		if forge_available:
			fifth_action = {"label": "Forge", "action_type": "local", "action_data": "forge_crown", "enabled": true}
		elif at_fire_mountain:
			fifth_action = {"label": "Fire Mt", "action_type": "local", "action_data": "check_forge", "enabled": true}
		elif at_dungeon_entrance:
			fifth_action = {"label": "Dungeon", "action_type": "local", "action_data": "enter_dungeon", "enabled": true}
		elif at_corpse:
			fifth_action = {"label": "Loot", "action_type": "local", "action_data": "corpse_loot", "enabled": true}
		elif at_water:
			var water_label = "Deep Fish" if fishing_water_type == "deep" else "Fish"
			fifth_action = {"label": water_label, "action_type": "local", "action_data": "start_fishing", "enabled": true}
		elif at_ore_deposit:
			fifth_action = {"label": "Mine T%d" % ore_tier, "action_type": "local", "action_data": "start_mining", "enabled": true}
		elif at_dense_forest:
			fifth_action = {"label": "Chop T%d" % wood_tier, "action_type": "local", "action_data": "start_logging", "enabled": true}
		else:
			fifth_action = {"label": "Quests", "action_type": "local", "action_data": "show_quests", "enabled": true}
		# Cloak button only shows if unlocked (level 20+), otherwise blank slot
		var cloak_action = {"label": cloak_label, "action_type": "server", "action_data": "toggle_cloak", "enabled": true} if cloak_unlocked else {"label": "---", "action_type": "none", "action_data": "", "enabled": false}
		# Teleport unlocks at different levels: Mage 30, Trickster 45, Warrior 60
		var teleport_unlock_level = _get_teleport_unlock_level()
		var teleport_unlocked = player_level >= teleport_unlock_level
		var teleport_action = {"label": "Teleport", "action_type": "local", "action_data": "teleport", "enabled": true} if teleport_unlocked else {"label": "---", "action_type": "none", "action_data": "", "enabled": false}
		current_actions = [
			{"label": rest_label, "action_type": "server", "action_data": "rest", "enabled": true},
			{"label": "Inventory", "action_type": "local", "action_data": "inventory", "enabled": true},
			{"label": "Status", "action_type": "local", "action_data": "status", "enabled": true},
			fourth_action,
			fifth_action,
			{"label": "More", "action_type": "local", "action_data": "more_menu", "enabled": true},
			{"label": "Settings", "action_type": "local", "action_data": "settings", "enabled": true},
			cloak_action,
			teleport_action,
			{"label": "Char Select", "action_type": "local", "action_data": "logout_character", "enabled": true},
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
	ability_popup_input.select_all_on_focus = true  # Auto-select text when focused so typing replaces it
	ability_popup_input.text_submitted.connect(_on_ability_popup_input_submitted)
	ability_popup_input.gui_input.connect(_on_popup_input_gui_input.bind(ability_popup_input))
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
	# IMPORTANT: Only use client's damage-based HP tracking, not server's actual HP
	# This ensures suggestions are based on player knowledge (damage dealt in past fights)
	var suggested_amount = 0
	var using_estimated_hp = false
	var target_hp = 0

	# Check client's HP knowledge based on previous kills (damage dealt)
	# Use base name so variant knowledge is shared with base type
	if current_enemy_name != "" and current_enemy_level > 0:
		var base_name = _get_base_monster_name(current_enemy_name)
		# First try exact match (known HP for this monster at this level)
		var enemy_key = "%s_%d" % [base_name, current_enemy_level]
		if known_enemy_hp.has(enemy_key):
			target_hp = known_enemy_hp[enemy_key]
		else:
			# Try to estimate from kills at other levels
			var estimated = estimate_enemy_hp(base_name, current_enemy_level)
			if estimated > 0:
				target_hp = estimated
				using_estimated_hp = true

	if ability == "magic_bolt" and target_hp > 0:
		# Simulate Magic Bolt damage formula to suggest accurate mana amount
		# Server formula: damage = bolt_amount * (1 + sqrt(INT)/5) * buffs * passives * reductions
		var stats = character_data.get("stats", {})
		var base_int = stats.get("intelligence", 10)
		var equipped = character_data.get("equipped", {})
		var equip_bonuses = _calculate_equipment_bonuses(equipped)
		var int_stat = base_int + equip_bonuses.get("intelligence", 0)
		var int_multiplier = 1.0 + max(sqrt(float(int_stat)) / 5.0, float(int_stat) / 75.0)  # Hybrid: max of sqrt and linear scaling

		# Damage buff (War Cry, potions, etc.)
		var damage_buff = _get_buff_value("damage")
		var buff_multiplier = 1.0 + (float(damage_buff) / 100.0)

		# Estimate monster WIS reduction (formula: min(0.30, monster_int / 300))
		var estimated_monster_int = 10
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

		# Skill enhancement damage bonus (from character_data)
		var skill_enhancements = character_data.get("skill_enhancements", {})
		var bolt_enhancements = skill_enhancements.get("magic_bolt", {})
		var skill_damage_bonus = bolt_enhancements.get("damage_bonus", 0.0)
		if skill_damage_bonus > 0:
			effective_multiplier *= (1.0 + skill_damage_bonus / 100.0)

		# Class passive bonuses
		var class_type = character_data.get("class", "")
		var bonus_parts = []
		match class_type:
			"Wizard":
				# Arcane Precision: +15% spell damage (deterministic, always applied)
				effective_multiplier *= 1.15
				bonus_parts.append("[color=#4169E1]+15% Arcane[/color]")
			"Sorcerer":
				# Chaos Magic: 25% double, 5% backfire - random, don't assume either
				bonus_parts.append("[color=#9400D3]Chaos (variable)[/color]")

		# Class affinity bonus
		var is_mage_path = class_type in ["Wizard", "Sage", "Sorcerer"]
		if is_mage_path and current_enemy_color == "#00BFFF":
			effective_multiplier *= 1.25
			bonus_parts.append("[color=#00BFFF]+25% vs Magic[/color]")
		elif is_mage_path and (current_enemy_color == "#FFFF00" or current_enemy_color == "#00FF00"):
			effective_multiplier *= 0.85
			bonus_parts.append("[color=#FF6666]-15% resist[/color]")

		if damage_buff > 0:
			bonus_parts.append("[color=#FFD700]+%d%% buff[/color]" % damage_buff)
		if skill_damage_bonus > 0:
			bonus_parts.append("[color=#00FFFF]+%d%% skill[/color]" % int(skill_damage_bonus))

		# Estimate monster defense reduction (matches apply_ability_damage_modifiers)
		var estimated_defense = 5
		if current_enemy_level <= 5:
			estimated_defense = 8
		elif current_enemy_level <= 15:
			estimated_defense = 15
		elif current_enemy_level <= 30:
			estimated_defense = 25
		elif current_enemy_level <= 50:
			estimated_defense = 40
		elif current_enemy_level <= 100:
			estimated_defense = 60
		elif current_enemy_level <= 500:
			estimated_defense = 100
		else:
			estimated_defense = 150
		estimated_defense += int(current_enemy_level / 10)
		if "armored" in current_enemy_abilities:
			estimated_defense = int(estimated_defense * 1.5)
			bonus_parts.append("[color=#6666FF]Armored[/color]")
		var def_ratio = float(estimated_defense) / (float(estimated_defense) + 100.0)
		var defense_reduction = def_ratio * 0.6 * 0.5
		effective_multiplier *= (1.0 - defense_reduction)

		# Level penalty (matches server: 1.5% per level, max 40%)
		var player_level = character_data.get("level", 1)
		var level_diff = current_enemy_level - player_level
		if level_diff > 0:
			var level_penalty = minf(0.40, level_diff * 0.015)
			effective_multiplier *= (1.0 - level_penalty)
			if level_penalty >= 0.05:
				bonus_parts.append("[color=#FF6666]-%d%% lvl[/color]" % int(level_penalty * 100))

		# Account for damage already dealt in this fight
		var remaining_hp = max(1, target_hp - damage_dealt_to_current_enemy)

		# Calculate mana needed with 18% buffer to cover ±15% damage variance
		var mana_needed = ceili(float(remaining_hp) / effective_multiplier * 1.18)
		suggested_amount = mini(mana_needed, current_resource)

		var bonus_text = " ".join(bonus_parts) if bonus_parts.size() > 0 else ""
		if bonus_text != "":
			bonus_text = bonus_text + "\n"
		var hp_label = "~HP" if using_estimated_hp else "HP"
		var remaining_note = ""
		if damage_dealt_to_current_enemy > 0:
			remaining_note = " [color=#808080](~%d remaining)[/color]" % remaining_hp
		ability_popup_description.text = "[center]%s%s: %d%s[/center]" % [bonus_text, hp_label, target_hp, remaining_note]

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
	ability_popup_active = true  # Set flag for input handling
	ability_popup_input.grab_focus()
	# Use deferred call to ensure selection happens after focus is fully established
	ability_popup_input.call_deferred("select_all")

func _hide_ability_popup():
	"""Hide the ability input popup."""
	ability_popup_active = false  # Clear flag for input handling
	# Mark enter as pressed to prevent _process from grabbing chat focus on the same frame
	set_meta("enter_pressed", true)
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

func _on_popup_input_gui_input(event: InputEvent, line_edit: LineEdit):
	"""Handle numpad input for popup LineEdits since Godot doesn't automatically convert them."""
	if event is InputEventKey and event.pressed and not event.echo:
		var numpad_map = {
			KEY_KP_0: "0", KEY_KP_1: "1", KEY_KP_2: "2", KEY_KP_3: "3", KEY_KP_4: "4",
			KEY_KP_5: "5", KEY_KP_6: "6", KEY_KP_7: "7", KEY_KP_8: "8", KEY_KP_9: "9",
			KEY_KP_SUBTRACT: "-", KEY_KP_PERIOD: "."
		}
		if numpad_map.has(event.keycode):
			var char_to_insert = numpad_map[event.keycode]
			# Check if text is selected - if so, replace the selection
			if line_edit.has_selection():
				var sel_from = line_edit.get_selection_from_column()
				var sel_to = line_edit.get_selection_to_column()
				var text_before = line_edit.text.substr(0, sel_from)
				var text_after = line_edit.text.substr(sel_to)
				line_edit.text = text_before + char_to_insert + text_after
				line_edit.caret_column = sel_from + 1
			else:
				var caret_pos = line_edit.caret_column
				var current_text = line_edit.text
				line_edit.text = current_text.substr(0, caret_pos) + char_to_insert + current_text.substr(caret_pos)
				line_edit.caret_column = caret_pos + 1
			line_edit.accept_event()
		elif event.keycode == KEY_KP_ENTER:
			# Treat numpad enter same as regular enter
			line_edit.text_submitted.emit(line_edit.text)
			line_edit.accept_event()

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
	gamble_popup_input.gui_input.connect(_on_popup_input_gui_input.bind(gamble_popup_input))
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

# ===== UPGRADE POPUP =====

func _create_upgrade_popup():
	"""Create the upgrade amount input popup panel."""
	upgrade_popup = Panel.new()
	upgrade_popup.name = "UpgradePopup"
	upgrade_popup.visible = false
	upgrade_popup.custom_minimum_size = Vector2(400, 320)

	# Style the popup
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.98)
	style.border_color = Color(0.2, 0.8, 0.2, 1)  # Green border
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	upgrade_popup.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	vbox.offset_left = 20
	vbox.offset_right = -20
	vbox.offset_top = 15
	vbox.offset_bottom = -15
	upgrade_popup.add_child(vbox)

	# Title
	upgrade_popup_title = Label.new()
	upgrade_popup_title.text = "UPGRADE EQUIPMENT"
	upgrade_popup_title.add_theme_color_override("font_color", Color(0.2, 1, 0.2))
	upgrade_popup_title.add_theme_font_size_override("font_size", 18)
	upgrade_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(upgrade_popup_title)

	# Item display
	upgrade_popup_item_label = Label.new()
	upgrade_popup_item_label.text = "Item: Weapon +5"
	upgrade_popup_item_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	upgrade_popup_item_label.add_theme_font_size_override("font_size", 14)
	upgrade_popup_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(upgrade_popup_item_label)

	# Gold display
	upgrade_popup_gold_label = Label.new()
	upgrade_popup_gold_label.text = "Your gold: 0"
	upgrade_popup_gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	upgrade_popup_gold_label.add_theme_font_size_override("font_size", 14)
	upgrade_popup_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(upgrade_popup_gold_label)

	# Cost display
	upgrade_popup_cost_label = Label.new()
	upgrade_popup_cost_label.text = "Cost for 1 upgrade: 100 gold"
	upgrade_popup_cost_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	upgrade_popup_cost_label.add_theme_font_size_override("font_size", 13)
	upgrade_popup_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(upgrade_popup_cost_label)

	# Quick upgrade buttons
	var quick_btn_container = HBoxContainer.new()
	quick_btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	quick_btn_container.add_theme_constant_override("separation", 10)
	vbox.add_child(quick_btn_container)

	upgrade_popup_btn_1 = Button.new()
	upgrade_popup_btn_1.text = "+1"
	upgrade_popup_btn_1.custom_minimum_size = Vector2(60, 35)
	upgrade_popup_btn_1.pressed.connect(_on_upgrade_quick.bind(1))
	quick_btn_container.add_child(upgrade_popup_btn_1)

	upgrade_popup_btn_5 = Button.new()
	upgrade_popup_btn_5.text = "+5"
	upgrade_popup_btn_5.custom_minimum_size = Vector2(60, 35)
	upgrade_popup_btn_5.pressed.connect(_on_upgrade_quick.bind(5))
	quick_btn_container.add_child(upgrade_popup_btn_5)

	upgrade_popup_btn_10 = Button.new()
	upgrade_popup_btn_10.text = "+10"
	upgrade_popup_btn_10.custom_minimum_size = Vector2(60, 35)
	upgrade_popup_btn_10.pressed.connect(_on_upgrade_quick.bind(10))
	quick_btn_container.add_child(upgrade_popup_btn_10)

	upgrade_popup_btn_max = Button.new()
	upgrade_popup_btn_max.text = "MAX"
	upgrade_popup_btn_max.custom_minimum_size = Vector2(70, 35)
	upgrade_popup_btn_max.pressed.connect(_on_upgrade_max)
	quick_btn_container.add_child(upgrade_popup_btn_max)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 5)
	vbox.add_child(spacer)

	# Custom input label
	var input_label = Label.new()
	input_label.text = "Or enter custom amount:"
	input_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	input_label.add_theme_font_size_override("font_size", 12)
	input_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(input_label)

	# Input field
	upgrade_popup_input = LineEdit.new()
	upgrade_popup_input.placeholder_text = "Enter number of upgrades..."
	upgrade_popup_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_popup_input.custom_minimum_size = Vector2(0, 35)
	upgrade_popup_input.add_theme_font_size_override("font_size", 14)
	upgrade_popup_input.text_submitted.connect(_on_upgrade_popup_input_submitted)
	upgrade_popup_input.text_changed.connect(_on_upgrade_input_changed)
	upgrade_popup_input.gui_input.connect(_on_popup_input_gui_input.bind(upgrade_popup_input))
	vbox.add_child(upgrade_popup_input)

	# Button container
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_container)

	# Cancel button
	upgrade_popup_cancel = Button.new()
	upgrade_popup_cancel.text = "Cancel"
	upgrade_popup_cancel.custom_minimum_size = Vector2(100, 35)
	upgrade_popup_cancel.pressed.connect(_on_upgrade_popup_cancel)
	btn_container.add_child(upgrade_popup_cancel)

	# Confirm button
	upgrade_popup_confirm = Button.new()
	upgrade_popup_confirm.text = "Upgrade!"
	upgrade_popup_confirm.custom_minimum_size = Vector2(100, 35)
	upgrade_popup_confirm.pressed.connect(_on_upgrade_popup_confirm)
	btn_container.add_child(upgrade_popup_confirm)

	# Add to root
	add_child(upgrade_popup)

func _calculate_upgrade_cost(current_level: int, count: int) -> int:
	"""Calculate total cost for upgrading an item multiple levels."""
	var total = 0
	for i in range(count):
		total += int(pow(current_level + i + 1, 2) * 10)
	return total

func _calculate_max_affordable_upgrades(current_level: int, gold: int) -> int:
	"""Calculate maximum number of upgrades affordable with current gold."""
	var count = 0
	var total_cost = 0
	while count < 100:  # Max 100 upgrades at once
		var next_cost = int(pow(current_level + count + 1, 2) * 10)
		if total_cost + next_cost > gold:
			break
		total_cost += next_cost
		count += 1
	return count

func _show_upgrade_popup(slot: String):
	"""Show the upgrade popup for a specific equipment slot."""
	if not upgrade_popup:
		_create_upgrade_popup()

	var equipped = character_data.get("equipped", {})
	var item = equipped.get(slot)
	if item == null:
		return

	upgrade_pending_slot = slot
	var current_level = item.get("level", 1)
	var gold = character_data.get("gold", 0)
	var item_name = item.get("name", "Unknown")
	var rarity = item.get("rarity", "common")

	# Calculate max affordable
	upgrade_max_affordable = _calculate_max_affordable_upgrades(current_level, gold)

	# Update labels
	upgrade_popup_item_label.text = "%s: %s (Lv%d)" % [slot.capitalize(), item_name, current_level]
	upgrade_popup_gold_label.text = "Your gold: %d" % gold
	upgrade_popup_cost_label.text = "Cost for 1 upgrade: %d gold" % _calculate_upgrade_cost(current_level, 1)

	# Update quick button states
	upgrade_popup_btn_1.disabled = upgrade_max_affordable < 1
	upgrade_popup_btn_1.text = "+1 (%dg)" % _calculate_upgrade_cost(current_level, 1) if upgrade_max_affordable >= 1 else "+1"

	upgrade_popup_btn_5.disabled = upgrade_max_affordable < 5
	upgrade_popup_btn_5.text = "+5 (%dg)" % _calculate_upgrade_cost(current_level, 5) if upgrade_max_affordable >= 5 else "+5"

	upgrade_popup_btn_10.disabled = upgrade_max_affordable < 10
	upgrade_popup_btn_10.text = "+10 (%dg)" % _calculate_upgrade_cost(current_level, 10) if upgrade_max_affordable >= 10 else "+10"

	upgrade_popup_btn_max.disabled = upgrade_max_affordable < 1
	upgrade_popup_btn_max.text = "MAX (+%d)" % upgrade_max_affordable if upgrade_max_affordable >= 1 else "MAX"

	# Clear input
	upgrade_popup_input.text = ""
	upgrade_popup_input.placeholder_text = "1-%d upgrades" % upgrade_max_affordable if upgrade_max_affordable > 0 else "Not enough gold!"

	# Center the popup on screen
	upgrade_popup.position = (get_viewport().get_visible_rect().size - upgrade_popup.size) / 2

	upgrade_popup.visible = true
	upgrade_popup_input.grab_focus()

func _hide_upgrade_popup():
	"""Hide the upgrade popup."""
	if upgrade_popup:
		upgrade_popup.visible = false
		upgrade_popup_input.release_focus()

func _on_upgrade_input_changed(new_text: String):
	"""Update cost display when input changes."""
	if not upgrade_popup or upgrade_pending_slot == "":
		return

	var equipped = character_data.get("equipped", {})
	var item = equipped.get(upgrade_pending_slot)
	if item == null:
		return

	var current_level = item.get("level", 1)

	if new_text.is_valid_int():
		var count = clampi(int(new_text), 1, 100)
		var cost = _calculate_upgrade_cost(current_level, count)
		upgrade_popup_cost_label.text = "Cost for %d upgrade%s: %d gold" % [count, "s" if count > 1 else "", cost]
	else:
		upgrade_popup_cost_label.text = "Cost for 1 upgrade: %d gold" % _calculate_upgrade_cost(current_level, 1)

func _on_upgrade_popup_input_submitted(_text: String):
	"""Handle Enter key in upgrade popup input field."""
	_on_upgrade_popup_confirm()

func _on_upgrade_quick(count: int):
	"""Handle quick upgrade button click."""
	if upgrade_max_affordable < count:
		return
	_do_upgrade(count)

func _on_upgrade_max():
	"""Handle max upgrade button click."""
	if upgrade_max_affordable < 1:
		return
	_do_upgrade(upgrade_max_affordable)

func _on_upgrade_popup_confirm():
	"""Handle confirm button in upgrade popup."""
	var text = upgrade_popup_input.text.strip_edges()

	if text == "":
		# Default to 1 upgrade if no input
		_do_upgrade(1)
		return

	if not text.is_valid_int():
		upgrade_popup_input.text = ""
		upgrade_popup_input.placeholder_text = "Enter a number!"
		return

	var count = int(text)
	if count < 1:
		upgrade_popup_input.text = ""
		upgrade_popup_input.placeholder_text = "Minimum: 1"
		return

	if count > upgrade_max_affordable:
		upgrade_popup_input.text = ""
		upgrade_popup_input.placeholder_text = "Max affordable: %d" % upgrade_max_affordable
		return

	_do_upgrade(count)

func _do_upgrade(count: int):
	"""Perform the upgrade."""
	_hide_upgrade_popup()
	pending_merchant_action = ""
	send_to_server({"type": "merchant_upgrade", "slot": upgrade_pending_slot, "count": count})
	upgrade_pending_slot = ""
	update_action_bar()

func _on_upgrade_popup_cancel():
	"""Handle cancel button in upgrade popup."""
	_hide_upgrade_popup()
	upgrade_pending_slot = ""
	# Return to upgrade slot selection
	pending_merchant_action = "upgrade"
	display_upgrade_options()
	update_action_bar()

# ===== TELEPORT POPUP =====

func _create_teleport_popup():
	"""Create the teleport coordinate input popup panel."""
	teleport_popup = Panel.new()
	teleport_popup.name = "TeleportPopup"
	teleport_popup.visible = false
	teleport_popup.custom_minimum_size = Vector2(380, 320)

	# Style the popup
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.98)
	style.border_color = Color(0.6, 0.2, 0.8, 1)  # Purple border for magic
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	teleport_popup.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.offset_left = 20
	vbox.offset_right = -20
	vbox.offset_top = 15
	vbox.offset_bottom = -15
	teleport_popup.add_child(vbox)

	# Title
	teleport_popup_title = Label.new()
	teleport_popup_title.text = "TELEPORT"
	teleport_popup_title.add_theme_color_override("font_color", Color(0.8, 0.4, 1))
	teleport_popup_title.add_theme_font_size_override("font_size", 18)
	teleport_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(teleport_popup_title)

	# Current position
	var pos_label = Label.new()
	var px = character_data.get("x", 0)
	var py = character_data.get("y", 0)
	pos_label.text = "Current position: (%d, %d)" % [px, py]
	pos_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	pos_label.add_theme_font_size_override("font_size", 13)
	pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pos_label.name = "PosLabel"
	vbox.add_child(pos_label)

	# Resource display
	teleport_popup_resource_label = Label.new()
	teleport_popup_resource_label.text = "Mana: 100/100"
	teleport_popup_resource_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1))
	teleport_popup_resource_label.add_theme_font_size_override("font_size", 14)
	teleport_popup_resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(teleport_popup_resource_label)

	# Cost display
	teleport_popup_cost_label = Label.new()
	teleport_popup_cost_label.text = "Cost: 10 + 1 per tile distance"
	teleport_popup_cost_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	teleport_popup_cost_label.add_theme_font_size_override("font_size", 13)
	teleport_popup_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(teleport_popup_cost_label)

	# Coordinate inputs container
	var coord_container = HBoxContainer.new()
	coord_container.alignment = BoxContainer.ALIGNMENT_CENTER
	coord_container.add_theme_constant_override("separation", 15)
	vbox.add_child(coord_container)

	# X input
	var x_container = VBoxContainer.new()
	coord_container.add_child(x_container)

	var x_label = Label.new()
	x_label.text = "X Coordinate"
	x_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	x_label.add_theme_font_size_override("font_size", 12)
	x_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	x_container.add_child(x_label)

	teleport_popup_x_input = LineEdit.new()
	teleport_popup_x_input.placeholder_text = "-1000 to 1000"
	teleport_popup_x_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	teleport_popup_x_input.custom_minimum_size = Vector2(120, 35)
	teleport_popup_x_input.add_theme_font_size_override("font_size", 14)
	teleport_popup_x_input.text_changed.connect(_on_teleport_coords_changed)
	teleport_popup_x_input.gui_input.connect(_on_popup_input_gui_input.bind(teleport_popup_x_input))
	x_container.add_child(teleport_popup_x_input)

	# Y input
	var y_container = VBoxContainer.new()
	coord_container.add_child(y_container)

	var y_label = Label.new()
	y_label.text = "Y Coordinate"
	y_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	y_label.add_theme_font_size_override("font_size", 12)
	y_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	y_container.add_child(y_label)

	teleport_popup_y_input = LineEdit.new()
	teleport_popup_y_input.placeholder_text = "-1000 to 1000"
	teleport_popup_y_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	teleport_popup_y_input.custom_minimum_size = Vector2(120, 35)
	teleport_popup_y_input.add_theme_font_size_override("font_size", 14)
	teleport_popup_y_input.text_changed.connect(_on_teleport_coords_changed)
	teleport_popup_y_input.text_submitted.connect(_on_teleport_y_submitted)
	teleport_popup_y_input.gui_input.connect(_on_popup_input_gui_input.bind(teleport_popup_y_input))
	y_container.add_child(teleport_popup_y_input)

	# World bounds note
	var bounds_label = Label.new()
	bounds_label.text = "World bounds: -1000 to +1000"
	bounds_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	bounds_label.add_theme_font_size_override("font_size", 11)
	bounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(bounds_label)

	# Button container
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_container.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_container)

	# Cancel button
	teleport_popup_cancel = Button.new()
	teleport_popup_cancel.text = "Cancel"
	teleport_popup_cancel.custom_minimum_size = Vector2(100, 35)
	teleport_popup_cancel.pressed.connect(_on_teleport_popup_cancel)
	btn_container.add_child(teleport_popup_cancel)

	# Confirm button
	teleport_popup_confirm = Button.new()
	teleport_popup_confirm.text = "Teleport!"
	teleport_popup_confirm.custom_minimum_size = Vector2(100, 35)
	teleport_popup_confirm.pressed.connect(_on_teleport_popup_confirm)
	btn_container.add_child(teleport_popup_confirm)

	# Add to root
	add_child(teleport_popup)

func _calculate_teleport_cost(target_x: int, target_y: int) -> int:
	"""Calculate resource cost for teleporting to target coordinates."""
	var px = character_data.get("x", 0)
	var py = character_data.get("y", 0)
	var distance = sqrt(pow(target_x - px, 2) + pow(target_y - py, 2))
	# Base cost of 10 + 1 per tile distance
	return int(10 + distance)

func _get_player_primary_resource() -> Dictionary:
	"""Get the player's primary resource name, current, and max values."""
	var path = _get_player_active_path()
	match path:
		"mage":
			return {
				"name": "Mana",
				"current": character_data.get("current_mana", 0),
				"max": character_data.get("max_mana", 100)
			}
		"trickster":
			return {
				"name": "Energy",
				"current": character_data.get("current_energy", 0),
				"max": character_data.get("max_energy", 100)
			}
		"warrior":
			return {
				"name": "Stamina",
				"current": character_data.get("current_stamina", 0),
				"max": character_data.get("max_stamina", 100)
			}
		_:
			# Default to mana if no path determined
			return {
				"name": "Mana",
				"current": character_data.get("current_mana", 0),
				"max": character_data.get("max_mana", 100)
			}

func open_teleport_popup():
	"""Show the teleport popup."""
	if in_combat:
		display_game("[color=#FF0000]Cannot teleport during combat![/color]")
		return

	if not teleport_popup:
		_create_teleport_popup()

	teleport_mode = true

	var px = character_data.get("x", 0)
	var py = character_data.get("y", 0)
	var resource = _get_player_primary_resource()

	# Update position label
	var pos_label = teleport_popup.get_node("VBoxContainer/PosLabel")
	if pos_label:
		pos_label.text = "Current position: (%d, %d)" % [px, py]

	# Update resource label
	teleport_popup_resource_label.text = "%s: %d/%d" % [resource.name, resource.current, resource.max]

	# Clear inputs
	teleport_popup_x_input.text = ""
	teleport_popup_y_input.text = ""
	teleport_popup_cost_label.text = "Cost: 10 + 1 per tile distance"

	# Center the popup on screen
	teleport_popup.position = (get_viewport().get_visible_rect().size - teleport_popup.size) / 2

	teleport_popup.visible = true
	teleport_popup_x_input.grab_focus()

func _hide_teleport_popup():
	"""Hide the teleport popup."""
	teleport_mode = false
	if teleport_popup:
		teleport_popup.visible = false
		teleport_popup_x_input.release_focus()
		teleport_popup_y_input.release_focus()
	# Ensure the main input field doesn't steal focus after teleport
	if input_field and input_field.has_focus():
		input_field.release_focus()
	update_action_bar()

func _on_teleport_coords_changed(_new_text: String):
	"""Update cost display when coordinates change."""
	var x_text = teleport_popup_x_input.text.strip_edges()
	var y_text = teleport_popup_y_input.text.strip_edges()

	if x_text.lstrip("-").is_valid_int() and y_text.lstrip("-").is_valid_int():
		var target_x = int(x_text)
		var target_y = int(y_text)
		var cost = _calculate_teleport_cost(target_x, target_y)
		var resource = _get_player_primary_resource()
		var color = "#00FF00" if resource.current >= cost else "#FF0000"
		teleport_popup_cost_label.text = "Cost: [color=%s]%d %s[/color]" % [color, cost, resource.name]
	else:
		teleport_popup_cost_label.text = "Cost: 10 + 1 per tile distance"

func _on_teleport_y_submitted(_text: String):
	"""Handle Enter key in Y input field."""
	_on_teleport_popup_confirm()

func _on_teleport_popup_confirm():
	"""Handle confirm button in teleport popup."""
	var x_text = teleport_popup_x_input.text.strip_edges()
	var y_text = teleport_popup_y_input.text.strip_edges()

	# Validate X coordinate
	if not x_text.lstrip("-").is_valid_int():
		teleport_popup_x_input.text = ""
		teleport_popup_x_input.placeholder_text = "Enter a number!"
		teleport_popup_x_input.grab_focus()
		return

	# Validate Y coordinate
	if not y_text.lstrip("-").is_valid_int():
		teleport_popup_y_input.text = ""
		teleport_popup_y_input.placeholder_text = "Enter a number!"
		teleport_popup_y_input.grab_focus()
		return

	var target_x = int(x_text)
	var target_y = int(y_text)

	# Validate bounds
	if target_x < -1000 or target_x > 1000:
		teleport_popup_x_input.text = ""
		teleport_popup_x_input.placeholder_text = "Range: -1000 to 1000"
		teleport_popup_x_input.grab_focus()
		return

	if target_y < -1000 or target_y > 1000:
		teleport_popup_y_input.text = ""
		teleport_popup_y_input.placeholder_text = "Range: -1000 to 1000"
		teleport_popup_y_input.grab_focus()
		return

	# Check resource cost
	var cost = _calculate_teleport_cost(target_x, target_y)
	var resource = _get_player_primary_resource()

	if resource.current < cost:
		display_game("[color=#FF0000]Not enough %s! Need %d, have %d.[/color]" % [resource.name, cost, resource.current])
		return

	# Send teleport request
	_hide_teleport_popup()
	send_to_server({"type": "teleport", "x": target_x, "y": target_y})

func _on_teleport_popup_cancel():
	"""Handle cancel button in teleport popup."""
	_hide_teleport_popup()

func _has_usable_combat_items() -> bool:
	"""Check if player has any usable items for combat (potions/elixirs)."""
	var inventory = character_data.get("inventory", [])
	for item in inventory:
		var item_type = item.get("type", "")
		if item.get("is_consumable", false) or "potion" in item_type or "elixir" in item_type:
			return true
	return false

func _get_player_active_path() -> String:
	"""Determine player's active path based on class type."""
	var char_class = character_data.get("class", "Fighter")
	match char_class:
		"Fighter", "Barbarian", "Paladin":
			return "warrior"
		"Wizard", "Sorcerer", "Sage":
			return "mage"
		"Thief", "Ranger", "Ninja":
			return "trickster"
		_:
			return "warrior"

func _get_teleport_unlock_level() -> int:
	"""Get the level at which teleport unlocks based on class path."""
	var path = _get_player_active_path()
	match path:
		"mage":
			return 30
		"trickster":
			return 45
		"warrior":
			return 60
		_:
			return 60  # Default to warrior level if no path yet

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

	# Ability definitions with display name, base cost, and cost percentage (for mage scaling)
	var ability_defs = {
		# Mage abilities - use percentage-based scaling
		"magic_bolt": {"display": "Bolt", "cost": 0, "cost_percent": 0, "resource_type": "mana"},
		"blast": {"display": "Blast", "cost": 50, "cost_percent": 5, "resource_type": "mana"},
		"shield": {"display": "Shield", "cost": 20, "cost_percent": 2, "resource_type": "mana"},  # Alias for forcefield
		"forcefield": {"display": "Field", "cost": 20, "cost_percent": 2, "resource_type": "mana"},  # Buffed, replaces Shield
		"teleport": {"display": "Teleport", "cost": 1000, "cost_percent": 0, "resource_type": "mana"},
		"meteor": {"display": "Meteor", "cost": 100, "cost_percent": 8, "resource_type": "mana"},
		"haste": {"display": "Haste", "cost": 35, "cost_percent": 3, "resource_type": "mana"},
		"paralyze": {"display": "Paralyze", "cost": 60, "cost_percent": 6, "resource_type": "mana"},
		"banish": {"display": "Banish", "cost": 80, "cost_percent": 10, "resource_type": "mana"},
		# Warrior abilities
		"power_strike": {"display": "Strike", "cost": 10, "cost_percent": 0, "resource_type": "stamina"},
		"war_cry": {"display": "Cry", "cost": 15, "cost_percent": 0, "resource_type": "stamina"},
		"shield_bash": {"display": "Bash", "cost": 20, "cost_percent": 0, "resource_type": "stamina"},
		"cleave": {"display": "Cleave", "cost": 30, "cost_percent": 0, "resource_type": "stamina"},
		"berserk": {"display": "Berserk", "cost": 40, "cost_percent": 0, "resource_type": "stamina"},
		"iron_skin": {"display": "Iron", "cost": 35, "cost_percent": 0, "resource_type": "stamina"},
		"devastate": {"display": "Devastate", "cost": 60, "cost_percent": 0, "resource_type": "stamina"},
		"fortify": {"display": "Fortify", "cost": 25, "cost_percent": 0, "resource_type": "stamina"},
		"rally": {"display": "Rally", "cost": 45, "cost_percent": 0, "resource_type": "stamina"},
		# Trickster abilities
		"analyze": {"display": "Analyze", "cost": 5, "cost_percent": 0, "resource_type": "energy"},
		"distract": {"display": "Distract", "cost": 15, "cost_percent": 0, "resource_type": "energy"},
		"pickpocket": {"display": "Steal", "cost": 20, "cost_percent": 0, "resource_type": "energy"},
		"ambush": {"display": "Ambush", "cost": 30, "cost_percent": 0, "resource_type": "energy"},
		"vanish": {"display": "Vanish", "cost": 40, "cost_percent": 0, "resource_type": "energy"},
		"exploit": {"display": "Exploit", "cost": 35, "cost_percent": 0, "resource_type": "energy"},
		"perfect_heist": {"display": "Heist", "cost": 50, "cost_percent": 0, "resource_type": "energy"},
		"sabotage": {"display": "Sabotage", "cost": 25, "cost_percent": 0, "resource_type": "energy"},
		"gambit": {"display": "Gambit", "cost": 35, "cost_percent": 0, "resource_type": "energy"},
		# Universal abilities
		"cloak": {"display": "Cloak", "cost": 30, "cost_percent": 0, "resource_type": resource_type},
		"all_or_nothing": {"display": "A/N %d%%" % int(3.0 + min(25.0, character_data.get("all_or_nothing_uses", 0) * 0.1)), "cost": 1, "cost_percent": 0, "resource_type": resource_type},
	}

	var result = ability_defs.get(ability_name, {})
	if result.is_empty():
		return result

	# Calculate actual cost for mage abilities with percentage scaling
	var base_cost = result.cost
	var cost_percent = result.get("cost_percent", 0)
	if path == "mage" and cost_percent > 0:
		var max_mana = character_data.get("total_max_mana", character_data.get("max_mana", 100))
		var percent_cost = int(max_mana * cost_percent / 100.0)
		base_cost = max(base_cost, percent_cost)

	# Apply race and class cost modifiers to match server calculations
	var final_cost = base_cost
	var player_race = character_data.get("race", "")
	var player_class = character_data.get("class", "")
	var ability_resource_type = result.resource_type

	# Gnome racial: -15% ability costs (all resource types)
	if player_race == "Gnome":
		final_cost = int(final_cost * 0.85)

	# Class-specific cost modifiers
	if ability_resource_type == "stamina":
		# Fighter: 20% reduced stamina costs
		if player_class == "Fighter":
			final_cost = int(final_cost * 0.80)
		# Barbarian: 25% increased stamina costs
		elif player_class == "Barbarian":
			final_cost = int(final_cost * 1.25)
	elif ability_resource_type == "mana":
		# Sage: 25% reduced mana costs
		if player_class == "Sage":
			final_cost = int(final_cost * 0.75)

	# Minimum cost of 1 (unless base was 0)
	if base_cost > 0 and final_cost < 1:
		final_cost = 1

	result.cost = final_cost
	return result

func show_combat_item_menu():
	"""Display usable items for combat selection."""
	combat_item_mode = true

	var inventory = character_data.get("inventory", [])
	var usable_items = []

	for i in range(inventory.size()):
		var item = inventory[i]
		var item_type = item.get("type", "")
		# Include all consumable types: potions, elixirs, gold pouches, gems, scrolls, resource potions
		# Also check the is_consumable flag as a fallback
		if item.get("is_consumable", false) or "potion" in item_type or "elixir" in item_type or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("scroll_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_"):
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

	# Mark the corresponding action bar hotkey as pressed to prevent it from
	# triggering later in this same _process frame (item 1 = action_5, etc.)
	var action_index = (number - 1) + 5
	if action_index < 10:
		set_meta("hotkey_%d_pressed" % action_index, true)

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
	# Handle dynamic egg freeze toggle actions before match
	if action.begins_with("egg_toggle_freeze_"):
		var egg_index = int(action.replace("egg_toggle_freeze_", ""))
		send_to_server({"type": "toggle_egg_freeze", "index": egg_index})
		return

	match action:
		"status":
			display_character_status()
		"help":
			show_help()
		"settings":
			open_settings()
		"leaderboard":
			more_mode = false
			show_leaderboard_panel()
		"changelog":
			display_changelog()
		"bestiary":
			display_bestiary()
		"more_menu":
			open_more_menu()
		"more_close":
			close_more_menu()
		"companions":
			show_companion_info()
		"companions_close":
			close_companions()
		"companions_dismiss":
			send_to_server({"type": "dismiss_companion"})
			display_companions()
		"companions_prev":
			companions_page = max(0, companions_page - 1)
			_refresh_companions_display()
			update_action_bar()
		"companions_next":
			var collected = character_data.get("collected_companions", [])
			var total_pages = int(ceil(float(collected.size()) / float(COMPANIONS_PAGE_SIZE)))
			companions_page = min(total_pages - 1, companions_page + 1)
			_refresh_companions_display()
			update_action_bar()
		"companions_release":
			# Enter release selection mode
			pending_companion_action = "release_select"
			game_output.clear()
			display_game("[color=#FF6666]═══════ RELEASE COMPANION ═══════[/color]")
			display_game("")
			display_game("[color=#FFAA00]Select a companion to release (PERMANENTLY DELETE):[/color]")
			display_game("")
			_display_companions_for_release()
			update_action_bar()
		"release_cancel":
			pending_companion_action = ""
			release_target_companion = {}
			display_companions()
			update_action_bar()
		"release_confirm":
			if not release_target_companion.is_empty():
				send_to_server({"type": "release_companion", "id": release_target_companion.get("id", "")})
				pending_companion_action = ""
				release_target_companion = {}
		"companions_release_all":
			# First warning for releasing all companions
			var collected = character_data.get("collected_companions", [])
			if collected.size() <= 1:
				display_game("[color=#FF0000]You need more than 1 companion to use Release All.[/color]")
				return
			pending_companion_action = "release_all_warn"
			game_output.clear()
			display_game("[color=#FF0000]══════ WARNING ══════[/color]")
			display_game("")
			display_game("[color=#FFAA00]You are about to release ALL %d companions![/color]" % collected.size())
			display_game("")
			display_game("[color=#FF6666]This will PERMANENTLY DELETE all your companions.[/color]")
			display_game("[color=#FF6666]Your active companion will be dismissed first.[/color]")
			display_game("")
			display_game("[color=#808080]Press Continue to proceed to final confirmation.[/color]")
			display_game("[color=#808080]Press Cancel to go back.[/color]")
			update_action_bar()
		"release_all_continue":
			# Second/final confirmation
			var collected = character_data.get("collected_companions", [])
			pending_companion_action = "release_all_confirm"
			game_output.clear()
			display_game("[color=#FF0000]══════ FINAL CONFIRMATION ══════[/color]")
			display_game("")
			display_game("[color=#FF0000]ARE YOU ABSOLUTELY SURE?[/color]")
			display_game("")
			display_game("[color=#FFAA00]This will delete ALL %d companions:[/color]" % collected.size())
			for i in range(min(5, collected.size())):
				var comp = collected[i]
				display_game("  - %s %s Lv.%d" % [comp.get("variant", ""), comp.get("name", "Unknown"), comp.get("level", 1)])
			if collected.size() > 5:
				display_game("  ... and %d more" % (collected.size() - 5))
			display_game("")
			display_game("[color=#FF0000]THIS CANNOT BE UNDONE![/color]")
			display_game("")
			update_action_bar()
		"release_all_final":
			# Actually release all companions
			send_to_server({"type": "release_all_companions"})
			pending_companion_action = ""
		"companions_inspect":
			# Enter inspect selection mode - use number keys to select companion
			pending_companion_action = "inspect_select"
			game_output.clear()
			display_game("[color=#00FFFF]═══════ INSPECT COMPANION ═══════[/color]")
			display_game("")
			display_game("[color=#AAAAAA]Select a companion to inspect (1-%d):[/color]" % min(COMPANIONS_PAGE_SIZE, character_data.get("collected_companions", []).size()))
			display_game("")
			_display_companions_for_selection()
			update_action_bar()
		"inspect_back":
			pending_companion_action = ""
			inspecting_companion = {}
			display_companions()
			update_action_bar()
		"companions_sort":
			# Cycle through sort options
			var sort_options = ["level", "tier", "variant", "damage", "name", "type"]
			var current_idx = sort_options.find(companion_sort_option)
			companion_sort_option = sort_options[(current_idx + 1) % sort_options.size()]
			companions_page = 0  # Reset to first page when changing sort
			display_companions()
			update_action_bar()
		"companions_sort_dir":
			# Toggle ascending/descending
			companion_sort_ascending = not companion_sort_ascending
			companions_page = 0  # Reset to first page when changing direction
			display_companions()
			update_action_bar()
		"eggs_menu":
			# Open eggs page
			more_mode = false
			eggs_mode = true
			eggs_page = 0
			display_eggs()
			update_action_bar()
		"eggs_close":
			eggs_mode = false
			more_mode = true
			display_more_menu()
			update_action_bar()
		"eggs_prev":
			eggs_page = max(0, eggs_page - 1)
			display_eggs()
			update_action_bar()
		"eggs_next":
			var eggs = character_data.get("incubating_eggs", [])
			var total_pages = int(ceil(float(eggs.size()) / float(EGGS_PAGE_SIZE)))
			eggs_page = min(total_pages - 1, eggs_page + 1)
			display_eggs()
			update_action_bar()
		"death_continue":
			_on_continue_pressed()
		"save_death_log":
			_save_death_log()
		"logout_character":
			logout_character()
		"logout_account":
			logout_account()
		"teleport":
			open_teleport_popup()
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
		"inventory_lock":
			prompt_inventory_action("lock")
		"inventory_sort":
			open_sort_menu()
		"inventory_salvage":
			open_salvage_menu()
		"sort_by_level":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "level"})
			update_action_bar()
		"sort_by_hp":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "hp"})
			update_action_bar()
		"sort_by_atk":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "atk"})
			update_action_bar()
		"sort_by_def":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "def"})
			update_action_bar()
		"sort_by_wit":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "wit"})
			update_action_bar()
		"sort_by_slot":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "slot"})
			update_action_bar()
		"sort_by_rarity":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "rarity"})
			update_action_bar()
		"sort_by_mana":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "mana"})
			update_action_bar()
		"sort_by_speed":
			pending_inventory_action = ""
			send_to_server({"type": "inventory_sort", "sort_by": "speed"})
			update_action_bar()
		"sort_cancel":
			pending_inventory_action = ""
			sort_menu_page = 0
			display_inventory()
			update_action_bar()
		"sort_more":
			# Go to page 2 of sort menu
			sort_menu_page = 1
			_display_sort_menu()
		"sort_back":
			# Go back to page 1 of sort menu
			sort_menu_page = 0
			_display_sort_menu()
		"cycle_compare_stat":
			# Cycle to next compare stat
			var current_idx = COMPARE_STAT_OPTIONS.find(inventory_compare_stat)
			var next_idx = (current_idx + 1) % COMPARE_STAT_OPTIONS.size()
			inventory_compare_stat = COMPARE_STAT_OPTIONS[next_idx]
			display_game("[color=#00FF00]Compare stat changed to: %s[/color]" % _get_compare_stat_label(inventory_compare_stat))
			_save_keybinds()  # Persist the setting
			update_action_bar()  # Update button label
		"view_materials":
			# Display crafting materials - exit sort menu and show materials
			pending_inventory_action = "viewing_materials"
			display_materials()
			update_action_bar()
		"materials_back":
			# Return to inventory from materials view
			pending_inventory_action = ""
			display_inventory()
			update_action_bar()
		"salvage_all":
			pending_inventory_action = "awaiting_salvage_result"
			send_to_server({"type": "inventory_salvage", "mode": "all"})
			game_output.clear()
			display_game("[color=#AA66FF]Salvaging all items...[/color]")
			update_action_bar()
		"salvage_below_level":
			pending_inventory_action = "awaiting_salvage_result"
			send_to_server({"type": "inventory_salvage", "mode": "below_level"})
			game_output.clear()
			display_game("[color=#AA66FF]Salvaging items below level threshold...[/color]")
			update_action_bar()
		"salvage_cancel":
			pending_inventory_action = ""
			display_inventory()
			update_action_bar()
		"salvage_consumables_prompt":
			# Mark the hotkey as pressed to prevent double-trigger
			set_meta("hotkey_8_pressed", true)  # Slot 3 = key_action_8 in salvage mode
			pending_inventory_action = "salvage_consumables_confirm"
			display_game("[color=#FF4444]WARNING: This will salvage ALL consumables![/color]")
			display_game("[color=#FFD700]Press Confirm to proceed or Cancel to abort.[/color]")
			update_action_bar()
		"salvage_consumables":
			pending_inventory_action = "awaiting_salvage_result"
			send_to_server({"type": "inventory_salvage", "mode": "consumables"})
			game_output.clear()
			display_game("[color=#AA66FF]Salvaging consumables...[/color]")
			update_action_bar()
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
		"upgrade_all":
			send_upgrade_all()
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
		"home_stone_cancel":
			_cancel_home_stone()
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
		"check_forge":
			# Check if player can forge at Fire Mountain
			send_to_server({"type": "forge_crown"})
		"start_fishing":
			# Start the fishing minigame
			start_fishing()
		"start_mining":
			# Start the mining minigame
			start_mining()
		"start_logging":
			# Start the logging minigame
			start_logging()
		"enter_dungeon":
			# Enter a dungeon at this location
			enter_dungeon_at_location()
		"dungeon_warning_confirm":
			# Confirm entering dungeon despite low level warning
			if not pending_dungeon_warning.is_empty():
				var dungeon_type = pending_dungeon_warning.get("dungeon_type", "")
				pending_dungeon_warning = {}
				send_to_server({"type": "dungeon_enter", "dungeon_type": dungeon_type, "confirmed": true})
			update_action_bar()
		"dungeon_warning_cancel":
			# Cancel entering dungeon
			pending_dungeon_warning = {}
			game_output.clear()
			display_game("[color=#808080]Dungeon entry cancelled.[/color]")
			update_action_bar()
		"corpse_loot":
			# Start corpse looting - show confirmation
			if at_corpse and not corpse_info.is_empty():
				pending_corpse_loot = corpse_info.duplicate(true)
				_display_corpse_loot_confirmation()
				update_action_bar()
		"corpse_loot_confirm":
			# Confirm looting the corpse
			if not pending_corpse_loot.is_empty():
				send_to_server({
					"type": "loot_corpse",
					"corpse_id": pending_corpse_loot.get("id", "")
				})
				pending_corpse_loot = {}
				update_action_bar()
		"corpse_loot_cancel":
			# Cancel looting
			pending_corpse_loot = {}
			game_output.clear()
			display_game("[color=#808080]Loot cancelled.[/color]")
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
		"ability_prev_page":
			ability_choice_page = max(0, ability_choice_page - 1)
			display_ability_choice_list()
			update_action_bar()
		"ability_next_page":
			var unlocked = ability_data.get("unlocked_abilities", [])
			var total_pages = max(1, (unlocked.size() + ABILITY_PAGE_SIZE - 1) / ABILITY_PAGE_SIZE)
			ability_choice_page = min(total_pages - 1, ability_choice_page + 1)
			display_ability_choice_list()
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
		"settings_ui_scale":
			settings_submenu = "ui_scale"
			game_output.clear()
			display_ui_scale_settings()
			update_action_bar()
		"settings_sound":
			settings_submenu = "sound"
			game_output.clear()
			display_sound_settings()
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
		"settings_abilities":
			ability_entered_from_settings = true
			settings_mode = false
			enter_ability_mode()
		# Trade actions
		"trade_accept":
			send_to_server({"type": "trade_response", "accept": true})
			pending_trade_request = ""
		"trade_decline":
			send_to_server({"type": "trade_response", "accept": false})
			pending_trade_request = ""
			update_action_bar()
		"trade_add_item":
			trade_pending_add = true
			inventory_page = 0
			display_trade_window()
			update_action_bar()
		"trade_add":
			# Add based on current tab
			match trade_tab:
				"items":
					trade_pending_add = true
					inventory_page = 0
				"companions":
					trade_pending_add_companion = true
				"eggs":
					trade_pending_add_egg = true
			display_trade_window()
			update_action_bar()
		"trade_cancel_add":
			trade_pending_add = false
			trade_pending_add_companion = false
			trade_pending_add_egg = false
			display_trade_window()
			update_action_bar()
		"trade_page_prev":
			if inventory_page > 0:
				inventory_page -= 1
				display_trade_window()
		"trade_page_next":
			var total_pages = max(1, int(ceil(float(character_data.get("inventory", []).size()) / INVENTORY_PAGE_SIZE)))
			if inventory_page < total_pages - 1:
				inventory_page += 1
				display_trade_window()
		"trade_remove_item":
			# Remove last added item
			if trade_my_items.size() > 0:
				var last_idx = trade_my_items[-1]
				send_to_server({"type": "trade_remove", "index": last_idx})
		"trade_remove":
			# Remove last added item/companion/egg based on current tab
			match trade_tab:
				"items":
					if trade_my_items.size() > 0:
						var last_idx = trade_my_items[-1]
						send_to_server({"type": "trade_remove", "index": last_idx})
				"companions":
					if trade_my_companions.size() > 0:
						var last_idx = trade_my_companions[-1]
						send_to_server({"type": "trade_remove_companion", "index": last_idx})
				"eggs":
					if trade_my_eggs.size() > 0:
						var last_idx = trade_my_eggs[-1]
						send_to_server({"type": "trade_remove_egg", "index": last_idx})
		"trade_toggle_ready":
			send_to_server({"type": "trade_ready"})
		"trade_cancel":
			send_to_server({"type": "trade_cancel"})
			_exit_trade_mode()
			update_action_bar()
		"trade_tab_items":
			trade_tab = "items"
			display_trade_window()
			update_action_bar()
		"trade_tab_companions":
			trade_tab = "companions"
			display_trade_window()
			update_action_bar()
		"trade_tab_eggs":
			trade_tab = "eggs"
			display_trade_window()
			update_action_bar()
		# Summon response actions
		"summon_accept":
			send_to_server({"type": "summon_response", "accept": true})
			pending_summon_from = ""
			update_action_bar()
		"summon_decline":
			send_to_server({"type": "summon_response", "accept": false})
			pending_summon_from = ""
			update_action_bar()
		# Blacksmith encounter actions
		"blacksmith_decline":
			send_blacksmith_choice("decline")
		"blacksmith_repair_all":
			send_blacksmith_choice("repair_all")
		"blacksmith_upgrade":
			send_blacksmith_choice("upgrade")
		"blacksmith_cancel_upgrade":
			send_blacksmith_choice("cancel_upgrade")
		# Healer encounter actions
		"healer_decline":
			send_healer_choice("decline")
		"healer_quick":
			send_healer_choice("quick")
		"healer_full":
			send_healer_choice("full")
		"healer_cure_all":
			send_healer_choice("cure_all")
		# Fishing actions (pattern input is handled in _input, only cancel uses action bar)
		"fishing_cancel":
			end_fishing(false, "You stopped fishing.")
		# Mining actions (pattern input is handled in _input, only cancel uses action bar)
		"mining_cancel":
			end_mining(false, "You stopped mining.")
		# Logging actions (pattern input is handled in _input, only cancel uses action bar)
		"logging_cancel":
			end_logging(false, "You stopped chopping.")
		# Crafting actions
		"open_crafting":
			open_crafting()
		"crafting_cancel":
			close_crafting()
		"crafting_skill_blacksmithing":
			request_craft_list("blacksmithing")
		"crafting_skill_alchemy":
			request_craft_list("alchemy")
		"crafting_skill_enchanting":
			request_craft_list("enchanting")
		"crafting_skill_cancel":
			crafting_skill = ""
			open_crafting()
		"crafting_recipe_cancel":
			crafting_selected_recipe = -1
			display_craft_recipe_list()
			update_action_bar()
		"crafting_confirm":
			confirm_craft()
		"crafting_prev_page":
			crafting_page = max(0, crafting_page - 1)
			display_craft_recipe_list()
			update_action_bar()
		"crafting_next_page":
			var total_pages = max(1, ceili(float(crafting_recipes.size()) / CRAFTING_PAGE_SIZE))
			crafting_page = min(total_pages - 1, crafting_page + 1)
			display_craft_recipe_list()
			update_action_bar()
		"crafting_continue":
			# Player acknowledged craft result, refresh recipe list
			awaiting_craft_result = false
			request_craft_list(crafting_skill)
		# Dungeon actions
		"dungeon_list_cancel":
			dungeon_list_mode = false
			dungeon_available = []
			game_output.clear()
			update_action_bar()
		"dungeon_exit":
			send_to_server({"type": "dungeon_exit"})
		"dungeon_continue":
			# Continue after combat/event in dungeon
			pending_continue = false

			# CRITICAL: Check for queued combat (e.g., egg hatched right before combat started)
			if not queued_combat_message.is_empty():
				var combat_msg = queued_combat_message.duplicate(true)
				queued_combat_message = {}
				_process_combat_start(combat_msg)
				return

			# Check for queued dungeon completion (e.g., boss with flock ability)
			if not queued_dungeon_complete.is_empty():
				var complete_msg = queued_dungeon_complete.duplicate(true)
				queued_dungeon_complete = {}
				_display_dungeon_complete(complete_msg)
				return

			send_to_server({"type": "dungeon_state"})  # Request fresh dungeon state
			update_action_bar()
		"dungeon_move_n":
			send_to_server({"type": "dungeon_move", "direction": "n"})
		"dungeon_move_s":
			send_to_server({"type": "dungeon_move", "direction": "s"})
		"dungeon_move_w":
			send_to_server({"type": "dungeon_move", "direction": "w"})
		"dungeon_move_e":
			send_to_server({"type": "dungeon_move", "direction": "e"})
		# Bless stat selection actions
		"bless_stat_str":
			_send_bless_with_stat("strength")
		"bless_stat_con":
			_send_bless_with_stat("constitution")
		"bless_stat_dex":
			_send_bless_with_stat("dexterity")
		"bless_stat_int":
			_send_bless_with_stat("intelligence")
		"bless_stat_wis":
			_send_bless_with_stat("wisdom")
		"bless_stat_wit":
			_send_bless_with_stat("wits")
		"bless_cancel":
			title_stat_selection_mode = false
			pending_bless_target = ""
			display_title_menu()
			update_action_bar()
		# Crucible action
		"start_crucible":
			send_to_server({"type": "start_crucible"})
		# House/Sanctuary actions
		"house_logout":
			send_to_server({"type": "logout_account"})
		"house_storage":
			house_mode = "storage"
			pending_house_action = ""
			house_storage_page = 0
			display_house_storage()
			update_action_bar()
		"house_companions":
			house_mode = "companions"
			pending_house_action = ""
			display_house_companions()
			update_action_bar()
		"house_upgrades":
			house_mode = "upgrades"
			pending_house_action = ""
			display_house_upgrades()
			update_action_bar()
		"upgrades_prev":
			house_upgrades_page = max(0, house_upgrades_page - 1)
			display_house_upgrades()
			update_action_bar()
		"upgrades_next":
			house_upgrades_page = min(2, house_upgrades_page + 1)
			display_house_upgrades()
			update_action_bar()
		"house_main":
			house_mode = "main"
			pending_house_action = ""
			display_house_main()
			update_action_bar()
		"house_play":
			# Go to character select to pick or create a character
			# Transition out of HOUSE_SCREEN so character_list handler shows select panel
			game_state = GameState.CHARACTER_SELECT
			send_to_server({"type": "request_character_list"})
		"house_storage_prev":
			house_storage_page = max(0, house_storage_page - 1)
			display_house_storage()
			update_action_bar()
		"house_storage_next":
			var items = house_data.get("storage", {}).get("items", [])
			var total_pages = max(1, int(ceil(float(items.size()) / 5.0)))
			house_storage_page = min(total_pages - 1, house_storage_page + 1)
			display_house_storage()
			update_action_bar()
		"house_storage_back":
			pending_house_action = ""
			house_storage_discard_index = -1
			house_storage_register_index = -1
			display_house_storage()
			update_action_bar()
		"house_withdraw_start":
			pending_house_action = "withdraw_select"
			house_storage_withdraw_items = []
			display_house_storage()
			update_action_bar()
		"house_withdraw_clear":
			house_storage_withdraw_items = []
			display_house_storage()
			update_action_bar()
		"house_companions_back":
			pending_house_action = ""
			house_unregister_companion_slot = -1
			display_house_companions()
			update_action_bar()
		"house_checkout_start":
			pending_house_action = "checkout_select"
			house_checkout_companion_slot = -1
			display_house_companions()
			update_action_bar()
		"house_checkout_clear":
			house_checkout_companion_slot = -1
			display_house_companions()
			update_action_bar()
		# Discard item from house storage
		"house_discard_start":
			pending_house_action = "discard_select"
			house_storage_discard_index = -1
			display_house_storage()
			update_action_bar()
		"house_discard_confirm":
			if house_storage_discard_index >= 0:
				send_to_server({"type": "house_discard_item", "index": house_storage_discard_index})
			pending_house_action = ""
			house_storage_discard_index = -1
			# Server will send updated house_data
		# Register stored companion to kennel
		"house_register_start":
			pending_house_action = "register_select"
			house_storage_register_index = -1
			display_house_storage()
			update_action_bar()
		"house_register_confirm":
			if house_storage_register_index >= 0:
				send_to_server({"type": "house_register_from_storage", "index": house_storage_register_index})
			pending_house_action = ""
			house_storage_register_index = -1
			# Server will send updated house_data
		# Unregister companion from kennel (move to storage)
		"house_unregister_start":
			pending_house_action = "unregister_select"
			house_unregister_companion_slot = -1
			display_house_companions()
			update_action_bar()
		"house_unregister_confirm":
			if house_unregister_companion_slot >= 0:
				send_to_server({"type": "house_unregister_companion", "slot": house_unregister_companion_slot})
			pending_house_action = ""
			house_unregister_companion_slot = -1
			# Server will send updated house_data

func _send_bless_with_stat(stat: String):
	"""Send bless ability with chosen stat"""
	send_to_server({
		"type": "title_ability",
		"ability": "bless",
		"target": pending_bless_target,
		"stat_choice": stat
	})
	title_stat_selection_mode = false
	title_mode = false
	pending_bless_target = ""
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

	# If combat was queued while showing egg hatch celebration, start it now
	if not queued_combat_message.is_empty():
		var combat_msg = queued_combat_message.duplicate(true)
		queued_combat_message = {}
		_process_combat_start(combat_msg)
		return

	# If dungeon completion was queued while showing boss kill results, show it now
	if not queued_dungeon_complete.is_empty():
		var complete_msg = queued_dungeon_complete.duplicate(true)
		queued_dungeon_complete = {}
		_display_dungeon_complete(complete_msg)
		return

	var need_dungeon_refresh = pending_dungeon_continue
	pending_dungeon_continue = false
	# Reset quest log mode if active
	quest_log_mode = false
	quest_log_quests = []
	# Keep recent XP gain highlight visible until next XP gain
	game_output.clear()
	# Reset combat background when player continues (not during flock)
	if not flock_pending:
		reset_combat_background()

	# Ensure we're in movement mode, not chat mode (e.g., after Teleport)
	if input_field and input_field.has_focus():
		input_field.release_focus()

	# If at trading post, go back to quest menu so player can turn in more
	if at_trading_post:
		send_to_server({"type": "trading_post_quests"})
		return

	# If at dungeon entrance in overworld (not in dungeon), show dungeon info
	if at_dungeon_entrance and not dungeon_mode and not dungeon_entrance_info.is_empty():
		_display_dungeon_entrance_info()

	# If standing on a corpse after combat, show corpse info so player can loot
	if at_corpse and not corpse_info.is_empty() and not dungeon_mode:
		_display_corpse_info()

	# If in dungeon, refresh the dungeon display
	if dungeon_mode:
		if need_dungeon_refresh:
			# Request fresh state from server (e.g., after treasure collection cleared tile)
			send_to_server({"type": "dungeon_move", "direction": "none"})
		else:
			display_dungeon_floor()

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
	var player_class = character_data.get("class", "")

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
			var compare_arrow = ""
			var compare_text = ""
			var slot = _get_slot_for_item_type(item_type)
			if slot != "":
				var equipped_item = equipped.get(slot)
				compare_arrow = _get_compare_arrow(item, equipped_item)
				var diff_parts = _get_item_comparison_parts(item, equipped_item)
				if diff_parts.size() > 0:
					compare_text = " [%s]" % ", ".join(diff_parts)
				else:
					compare_text = ""

			var themed_name = _get_themed_item_name(item, player_class)
			var is_consumable = item.get("is_consumable", false) or "potion" in item_type or "elixir" in item_type or "scroll" in item_type or "home_stone" in item_type or "gold_pouch" in item_type or "tome" in item_type
			if is_consumable:
				display_game("[%d] %s [color=%s]%s[/color]%s - [color=#FFD700]%d gold[/color]" % [i + 1, compare_arrow, color, themed_name, compare_text, price])
			else:
				display_game("[%d] %s [color=%s]%s[/color] (Lv%d)%s - [color=#FFD700]%d gold[/color]" % [i + 1, compare_arrow, color, themed_name, level, compare_text, price])

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

	var sell_item = inventory[absolute_index]
	if sell_item.get("locked", false):
		display_game("[color=#FF4444]That item is locked! Unlock it first.[/color]")
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
	var item_type = item.get("type", "unknown")
	var rarity = item.get("rarity", "common")
	var level = item.get("level", 1)
	var price = item.get("shop_price", 0)
	var gem_price = int(ceil(price / 1000.0))
	var gold = character_data.get("gold", 0)
	var rarity_color = _get_item_rarity_color(rarity)
	var player_class = character_data.get("class", "")
	var themed_name = _get_themed_item_name(item, player_class)

	display_game("")
	display_game("[color=%s]===== %s =====[/color]" % [rarity_color, themed_name])
	display_game("")
	display_game("[color=#00FFFF]Type:[/color] %s" % _get_item_type_description(item_type))
	display_game("[color=#00FFFF]Rarity:[/color] [color=%s]%s[/color]" % [rarity_color, rarity.capitalize()])
	var is_consumable_item = item.get("is_consumable", false) or "potion" in item_type or "elixir" in item_type or "scroll" in item_type or "home_stone" in item_type or "tome" in item_type
	if is_consumable_item:
		var tier = item.get("tier", level)
		display_game("[color=#00FFFF]Tier:[/color] %d" % tier)
	else:
		display_game("[color=#00FFFF]Level:[/color] %d" % level)
	display_game("[color=#00FFFF]Price:[/color] %d gold (%d gems)" % [price, gem_price])
	display_game("")

	# Display computed stats for equipment, or effect description for consumables
	if is_consumable_item:
		var effect_desc = _get_item_effect_description(item_type, item.get("tier", level), rarity)
		display_game("[color=#E6CC80]Effect:[/color] %s" % effect_desc)
	else:
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
			var equipped_themed = _get_themed_item_name(equipped_item, player_class)
			display_game("[color=#E6CC80]Compared to equipped %s:[/color]" % equipped_themed)
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

func _get_effective_item_level_for_display(item_level: int) -> float:
	"""Apply diminishing returns for items above level 50.
	   Items 1-50: Full linear scaling
	   Items 51+: Logarithmic scaling (50 + 15 * log2(level - 49))
	   This mirrors the server's _get_effective_item_level in character.gd"""
	if item_level <= 50:
		return float(item_level)
	# Above 50: diminishing returns using log scaling
	var excess = item_level - 49
	return 50.0 + 15.0 * log(excess) / log(2.0)

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
		"max_stamina": 0,     # Stamina bonus from affixes
		"max_energy": 0,      # Energy bonus from affixes
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

	# Apply diminishing returns for items above level 50 (matches server character.gd)
	var effective_level = _get_effective_item_level_for_display(item_level)

	# Base bonus scales with effective item level, rarity, and wear
	var base_bonus = int(effective_level * rarity_mult * wear_penalty)

	# STEP 1: Apply base item type bonuses (all items get these)
	# Note: Multipliers match server's character.gd NERFED values exactly
	if "weapon" in item_type:
		bonuses.attack += int(base_bonus * 1.5)  # Nerfed from 2.5x
		bonuses.strength += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
	elif "armor" in item_type:
		bonuses.defense += int(base_bonus * 1.0)  # Nerfed from 1.75x
		bonuses.constitution += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		bonuses.max_hp += int(base_bonus * 1.5)  # Nerfed from 2.5x
	elif "helm" in item_type:
		bonuses.defense += int(base_bonus * 0.6)  # Nerfed from 1.0x
		bonuses.wisdom += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
	elif "shield" in item_type:
		bonuses.defense += max(1, int(base_bonus * 0.4)) if base_bonus > 0 else 0
		bonuses.max_hp += int(base_bonus * 2.0)  # Nerfed from 4x
		bonuses.constitution += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
	elif "ring" in item_type:
		bonuses.attack += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		bonuses.dexterity += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		bonuses.intelligence += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
	elif "amulet" in item_type:
		bonuses.max_mana += int(base_bonus * 1.0)  # Nerfed from 1.75x
		bonuses.wisdom += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		bonuses.wits += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
	elif "boots" in item_type:
		bonuses.speed += int(base_bonus * 0.6)  # Nerfed from 1.0x
		bonuses.dexterity += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		bonuses.defense += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0

	# STEP 2: Apply class-specific gear bonuses (IN ADDITION to base type bonuses)
	if "ring_arcane" in item_type:
		# Arcane ring (Mage): extra INT + mana_regen
		bonuses.intelligence += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		bonuses.mana_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
	elif "ring_shadow" in item_type:
		# Shadow ring (Trickster): extra WITS + energy_regen
		bonuses.wits += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		bonuses.energy_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
	elif "amulet_mystic" in item_type:
		# Mystic amulet (Mage): extra max_mana + meditate_bonus
		bonuses.max_mana += base_bonus  # Extra mana on top of base
		bonuses.meditate_bonus += max(1, int(item_level / 2)) if item_level > 0 else 0
	elif "amulet_evasion" in item_type:
		# Evasion amulet (Trickster): extra speed + flee_bonus
		bonuses.speed += base_bonus
		bonuses.flee_bonus += max(1, int(item_level / 3)) if item_level > 0 else 0
	elif "boots_swift" in item_type:
		# Swift boots (Trickster): extra Speed + WITS + energy_regen
		bonuses.speed += int(base_bonus * 0.5)  # Extra speed on top of base
		bonuses.wits += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		bonuses.energy_regen += max(1, int(base_bonus * 0.1)) if base_bonus > 0 else 0
	elif "weapon_warlord" in item_type:
		# Warlord weapon (Warrior): extra stamina_regen (base weapon stats already applied)
		bonuses.stamina_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
	elif "shield_bulwark" in item_type:
		# Bulwark shield (Warrior): extra stamina_regen (base shield stats already applied)
		bonuses.stamina_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0

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
	if affixes.has("mana_bonus"):
		bonuses.max_mana += int(affixes.mana_bonus * wear_penalty)
	if affixes.has("stamina_bonus"):
		bonuses.max_stamina += int(affixes.stamina_bonus * wear_penalty)
	if affixes.has("energy_bonus"):
		bonuses.max_energy += int(affixes.energy_bonus * wear_penalty)
	if affixes.has("speed_bonus"):
		bonuses.speed += int(affixes.speed_bonus * wear_penalty)

	# Also check for direct item properties (some items store bonuses directly)
	# These are the same properties the server uses for sorting
	if item.has("hp_bonus"):
		bonuses.max_hp += int(item.hp_bonus * wear_penalty)
	if item.has("attack_bonus"):
		bonuses.attack += int(item.attack_bonus * wear_penalty)
	if item.has("defense_bonus"):
		bonuses.defense += int(item.defense_bonus * wear_penalty)
	if item.has("wits_bonus"):
		bonuses.wits += int(item.wits_bonus * wear_penalty)
	if item.has("mana_bonus"):
		bonuses.max_mana += int(item.mana_bonus * wear_penalty)
	if item.has("stamina_bonus"):
		bonuses.max_stamina += int(item.stamina_bonus * wear_penalty)
	if item.has("energy_bonus"):
		bonuses.max_energy += int(item.energy_bonus * wear_penalty)
	if item.has("speed_bonus"):
		bonuses.speed += int(item.speed_bonus * wear_penalty)

	return bonuses

func _display_computed_item_bonuses(item: Dictionary) -> bool:
	"""Display all computed bonuses for an item. Returns true if any bonuses were shown."""
	var bonuses = _compute_item_bonuses(item)
	var stats_shown = false

	if bonuses.get("attack", 0) > 0:
		display_game("[color=#FFFF00]+%d Attack[/color]" % bonuses.attack)
		stats_shown = true
	if bonuses.get("defense", 0) > 0:
		display_game("[color=#00FF00]+%d Defense[/color]" % bonuses.defense)
		stats_shown = true
	if bonuses.get("max_hp", 0) > 0:
		display_game("[color=#FF6666]+%d Max HP[/color]" % bonuses.max_hp)
		stats_shown = true
	# Universal resource display - combine all resource bonuses with scaling
	# Mana bonuses are ~2x larger, so: mana→stam/energy at 0.5x, stam/energy→mana at 2x
	var mana_bonus = bonuses.get("max_mana", 0)
	var stam_energy_bonus = bonuses.get("max_stamina", 0) + bonuses.get("max_energy", 0)
	if mana_bonus > 0 or stam_energy_bonus > 0:
		var player_class = character_data.get("class", "")
		var resource_name = "Resource"
		var resource_color = "#9999FF"
		var scaled_total = 0
		match player_class:
			"Wizard", "Sorcerer", "Sage":
				resource_name = "Mana"
				resource_color = "#9999FF"
				scaled_total = mana_bonus + (stam_energy_bonus * 2)
			"Fighter", "Barbarian", "Paladin":
				resource_name = "Stamina"
				resource_color = "#FFCC00"
				scaled_total = int(mana_bonus * 0.5) + stam_energy_bonus
			"Thief", "Ranger", "Ninja", "Trickster":
				resource_name = "Energy"
				resource_color = "#66FF66"
				scaled_total = int(mana_bonus * 0.5) + stam_energy_bonus
		if scaled_total > 0:
			display_game("[color=%s]+%d Max %s[/color]" % [resource_color, scaled_total, resource_name])
			stats_shown = true
	if bonuses.get("strength", 0) > 0:
		display_game("[color=#FF6666]+%d Strength[/color]" % bonuses.strength)
		stats_shown = true
	if bonuses.get("constitution", 0) > 0:
		display_game("[color=#00FF00]+%d Constitution[/color]" % bonuses.constitution)
		stats_shown = true
	if bonuses.get("dexterity", 0) > 0:
		display_game("[color=#FFFF00]+%d Dexterity[/color]" % bonuses.dexterity)
		stats_shown = true
	if bonuses.get("intelligence", 0) > 0:
		display_game("[color=#9999FF]+%d Intelligence[/color]" % bonuses.intelligence)
		stats_shown = true
	if bonuses.get("wisdom", 0) > 0:
		display_game("[color=#66CCFF]+%d Wisdom[/color]" % bonuses.wisdom)
		stats_shown = true
	if bonuses.get("wits", 0) > 0:
		display_game("[color=#FF00FF]+%d Wits[/color]" % bonuses.wits)
		stats_shown = true
	if bonuses.get("speed", 0) > 0:
		display_game("[color=#FFA500]+%d Speed[/color]" % bonuses.speed)
		stats_shown = true
	# Note: max_stamina and max_energy are combined with max_mana above as universal resource

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

func _get_item_compare_value(item: Dictionary, stat: String) -> int:
	"""Get the comparison value for an item based on the chosen stat"""
	match stat:
		"level":
			return item.get("level", 1)
		"hp":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("max_hp", 0)
		"atk":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("attack", 0)
		"def":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("defense", 0)
		"wit":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("wits", 0)
		"mana", "stamina", "energy", "resource":
			# Universal resource - combined with scaling (mana is 2x larger)
			var bonuses = _compute_item_bonuses(item)
			var mana_val = bonuses.get("max_mana", 0)
			var stam_energy_val = bonuses.get("max_stamina", 0) + bonuses.get("max_energy", 0)
			var player_class = character_data.get("class", "")
			match player_class:
				"Wizard", "Sorcerer", "Sage":
					return mana_val + (stam_energy_val * 2)
				"Fighter", "Barbarian", "Paladin", "Thief", "Ranger", "Ninja", "Trickster":
					return int(mana_val * 0.5) + stam_energy_val
				_:
					return mana_val + stam_energy_val
		"speed":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("speed", 0)
		"str":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("strength", 0)
		"con":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("constitution", 0)
		"dex":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("dexterity", 0)
		"int":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("intelligence", 0)
		"wis":
			var bonuses = _compute_item_bonuses(item)
			return bonuses.get("wisdom", 0)
		_:
			return item.get("level", 1)

func _get_compare_arrow(new_item: Dictionary, equipped_item) -> String:
	"""Get the comparison arrow text based on inventory_compare_stat setting"""
	if equipped_item == null or not (equipped_item is Dictionary):
		return "[color=#00FF00]NEW[/color]"

	var new_val = _get_item_compare_value(new_item, inventory_compare_stat)
	var old_val = _get_item_compare_value(equipped_item, inventory_compare_stat)

	if new_val > old_val:
		return "[color=#00FF00]↑[/color]"
	elif new_val < old_val:
		return "[color=#FF6666]↓[/color]"
	else:
		return "[color=#FFFF66]=[/color]"

func _get_item_comparison_parts(new_item: Dictionary, old_item) -> Array:
	"""Get array of stat difference strings for inline comparison display.
	   If old_item is null, shows new item's stats as gains."""
	var new_bonuses = _compute_item_bonuses(new_item)
	var old_bonuses = {}
	if old_item != null and old_item is Dictionary:
		old_bonuses = _compute_item_bonuses(old_item)
	var diff_parts = []

	# Stats to compare with their display labels and colors (ordered by importance)
	# Note: resource stats (mana/stamina/energy) are handled separately below
	var stats_to_compare = [
		["attack", "ATK", "#FFFF00"],      # Yellow
		["defense", "DEF", "#00FF00"],     # Green
		["max_hp", "HP", "#FF6666"],       # Light red
		["speed", "SPD", "#FFA500"],       # Orange
		["strength", "STR", "#FF6666"],    # Red
		["constitution", "CON", "#00FF00"], # Green
		["dexterity", "DEX", "#FFFF00"],   # Yellow
		["intelligence", "INT", "#9999FF"], # Purple
		["wisdom", "WIS", "#66CCFF"],      # Cyan
		["wits", "WIT", "#FF00FF"]         # Magenta
	]

	for stat_info in stats_to_compare:
		var stat = stat_info[0]
		var label = stat_info[1]
		var stat_color = stat_info[2]
		var new_val = new_bonuses.get(stat, 0)
		var old_val = old_bonuses.get(stat, 0)
		var diff = new_val - old_val
		if diff != 0:
			# Use stat color but dim it for negative values
			var c = stat_color if diff > 0 else "#808080"
			diff_parts.append("[color=%s]%+d%s[/color]" % [c, diff, label])

	# Universal resource comparison with scaling (mana is 2x larger than stam/energy)
	var new_mana = new_bonuses.get("max_mana", 0)
	var new_stam_energy = new_bonuses.get("max_stamina", 0) + new_bonuses.get("max_energy", 0)
	var old_mana = old_bonuses.get("max_mana", 0)
	var old_stam_energy = old_bonuses.get("max_stamina", 0) + old_bonuses.get("max_energy", 0)

	var player_class = character_data.get("class", "")
	var resource_label = "RES"
	var resource_color = "#9999FF"
	var new_scaled = 0
	var old_scaled = 0

	match player_class:
		"Wizard", "Sorcerer", "Sage":
			resource_label = "MP"
			resource_color = "#9999FF"
			new_scaled = new_mana + (new_stam_energy * 2)
			old_scaled = old_mana + (old_stam_energy * 2)
		"Fighter", "Barbarian", "Paladin":
			resource_label = "STA"
			resource_color = "#FFCC00"
			new_scaled = int(new_mana * 0.5) + new_stam_energy
			old_scaled = int(old_mana * 0.5) + old_stam_energy
		"Thief", "Ranger", "Ninja", "Trickster":
			resource_label = "EN"
			resource_color = "#66FF66"
			new_scaled = int(new_mana * 0.5) + new_stam_energy
			old_scaled = int(old_mana * 0.5) + old_stam_energy

	var resource_diff = new_scaled - old_scaled
	if resource_diff != 0:
		var c = resource_color if resource_diff > 0 else "#808080"
		diff_parts.append("[color=%s]%+d%s[/color]" % [c, resource_diff, resource_label])

	# Class-specific gear bonuses comparison
	var class_bonuses_to_compare = [
		["mana_regen", "MP/rnd", "#66CCCC"],       # Mage mana per round
		["meditate_bonus", "%Med", "#66CCCC"],     # Mage meditate bonus
		["energy_regen", "EN/rnd", "#66FF66"],     # Trickster energy per round
		["flee_bonus", "%Flee", "#66FF66"],        # Trickster flee bonus
		["stamina_regen", "STA/rnd", "#FFCC00"]    # Warrior stamina per round
	]

	for bonus_info in class_bonuses_to_compare:
		var stat = bonus_info[0]
		var label = bonus_info[1]
		var stat_color = bonus_info[2]
		var new_val = new_bonuses.get(stat, 0)
		var old_val = old_bonuses.get(stat, 0)
		var diff = new_val - old_val
		if diff != 0:
			var c = stat_color if diff > 0 else "#808080"
			diff_parts.append("[color=%s]%+d%s[/color]" % [c, diff, label])

	return diff_parts

func _get_compare_stat_label(stat: String) -> String:
	"""Get display label for a comparison stat"""
	match stat:
		"level": return "Level"
		"hp": return "HP"
		"atk": return "Attack"
		"def": return "Defense"
		"wit": return "Wits"
		"mana": return "Mana"
		"stamina": return "Stamina"
		"energy": return "Energy"
		"speed": return "Speed"
		"str": return "Strength"
		"con": return "Constitution"
		"dex": return "Dexterity"
		"int": return "Intelligence"
		"wis": return "Wisdom"
		_: return stat.capitalize()

func _display_item_comparison(new_item: Dictionary, old_item: Dictionary):
	"""Display stat comparison between two items using computed bonuses"""
	var new_bonuses = _compute_item_bonuses(new_item)
	var old_bonuses = _compute_item_bonuses(old_item)
	var comparisons = []

	# Compare all stats (excluding resource pools which are combined below)
	var stat_labels = {
		"attack": "ATK",
		"defense": "DEF",
		"max_hp": "HP",
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

	# Universal resource comparison - combine with scaling (mana is 2x larger than stam/energy)
	var player_class = character_data.get("class", "")
	var resource_label = "Resource"
	var new_scaled = 0
	var old_scaled = 0

	var new_mana = new_bonuses.get("max_mana", 0)
	var new_stam_energy = new_bonuses.get("max_stamina", 0) + new_bonuses.get("max_energy", 0)
	var old_mana = old_bonuses.get("max_mana", 0)
	var old_stam_energy = old_bonuses.get("max_stamina", 0) + old_bonuses.get("max_energy", 0)

	match player_class:
		"Wizard", "Sorcerer", "Sage":
			resource_label = "Mana"
			new_scaled = new_mana + (new_stam_energy * 2)
			old_scaled = old_mana + (old_stam_energy * 2)
		"Fighter", "Barbarian", "Paladin":
			resource_label = "Stamina"
			new_scaled = int(new_mana * 0.5) + new_stam_energy
			old_scaled = int(old_mana * 0.5) + old_stam_energy
		"Thief", "Ranger", "Ninja", "Trickster":
			resource_label = "Energy"
			new_scaled = int(new_mana * 0.5) + new_stam_energy
			old_scaled = int(old_mana * 0.5) + old_stam_energy

	if new_scaled != old_scaled:
		var diff = new_scaled - old_scaled
		var color = "#00FF00" if diff > 0 else "#FF6666"
		comparisons.append("[color=%s]%+d %s[/color]" % [color, diff, resource_label])

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

	# Compare effects using computed effect descriptions - ONLY for consumables
	# Equipment stats are already compared via computed bonuses above
	var new_type = new_item.get("type", "")
	var new_slot = _get_slot_for_item_type(new_type)

	# Skip effect description for equipment - stats are already shown above
	if new_slot == "":
		# Consumable - show effect description
		var old_type = old_item.get("type", "")
		var new_effect = _get_item_effect_description(new_type, new_item.get("level", 1), new_item.get("rarity", "common"))
		var old_effect = _get_item_effect_description(old_type, old_item.get("level", 1), old_item.get("rarity", "common"))

		if new_effect != old_effect:
			display_game("  [color=#FF6666]Current:[/color] %s" % old_effect)
			display_game("  [color=#00FF00]New:[/color] %s" % new_effect)
		elif new_effect != "" and new_effect != "Unknown effect":
			display_game("  [color=#808080]Effect:[/color] %s" % new_effect)

func send_upgrade_slot(slot: String):
	"""Show upgrade popup for a specific equipment slot"""
	# Show the upgrade popup instead of upgrading immediately
	_show_upgrade_popup(slot)

func _calculate_upgrade_all_cost() -> int:
	"""Calculate total cost to upgrade all equipped items by 1 level each."""
	var equipped = character_data.get("equipped", {})
	var total = 0
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		if item != null and item is Dictionary:
			var current_level = item.get("level", 1)
			total += int(pow(current_level + 1, 2) * 10)
	return total

func send_upgrade_all():
	"""Send upgrade request for all equipped items (+1 each)."""
	var cost = _calculate_upgrade_all_cost()
	var gold = character_data.get("gold", 0)

	if cost <= 0:
		display_game("[color=#FF0000]No items equipped to upgrade.[/color]")
		return

	if gold < cost:
		display_game("[color=#FF0000]Not enough gold! Need %d, have %d.[/color]" % [cost, gold])
		return

	pending_merchant_action = ""
	send_to_server({"type": "merchant_upgrade_all"})
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
			var sell_lock_text = "[color=#FF4444][L][/color] " if item.get("locked", false) else ""
			display_game("[%s] %s[color=%s]%s[/color] - [color=#FFD700]%d gold[/color]" % [
				key_name, sell_lock_text, rarity_color, item.get("name", "Unknown"), sell_price
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

# ===== TRADING FUNCTIONS =====

func _exit_trade_mode():
	"""Exit trading mode and reset all trade state."""
	in_trade = false
	trade_partner_name = ""
	trade_partner_class = ""
	trade_my_items = []
	trade_partner_items = []
	trade_my_companions = []
	trade_my_companions_data = []
	trade_partner_companions = []
	trade_my_eggs = []
	trade_my_eggs_data = []
	trade_partner_eggs = []
	trade_my_ready = false
	trade_partner_ready = false
	pending_trade_request = ""
	trade_pending_add = false
	trade_pending_add_companion = false
	trade_pending_add_egg = false
	trade_tab = "items"

func display_trade_window():
	"""Display the trade window showing both offers."""
	game_output.clear()

	var my_class = character_data.get("class", "")
	var inventory = character_data.get("inventory", [])
	var companions = character_data.get("collected_companions", [])
	var eggs = character_data.get("incubating_eggs", [])

	display_game("[color=#FFD700]═══════════════════════════════════════════════════[/color]")
	display_game("[color=#FFD700]           TRADING WITH %s[/color]" % trade_partner_name.to_upper())
	display_game("[color=#FFD700]═══════════════════════════════════════════════════[/color]")
	display_game("")

	# Tab bar
	var items_tab = "[color=#00FF00]> ITEMS <[/color]" if trade_tab == "items" else "[color=#808080]ITEMS[/color]"
	var companions_tab = "[color=#00FF00]> COMPANIONS <[/color]" if trade_tab == "companions" else "[color=#808080]COMPANIONS[/color]"
	var eggs_tab = "[color=#00FF00]> EGGS <[/color]" if trade_tab == "eggs" else "[color=#808080]EGGS[/color]"
	display_game("  [1] %s    [2] %s    [3] %s" % [items_tab, companions_tab, eggs_tab])
	display_game("")

	if trade_tab == "items":
		_display_trade_items_tab(inventory, my_class)
	elif trade_tab == "companions":
		_display_trade_companions_tab(companions)
	elif trade_tab == "eggs":
		_display_trade_eggs_tab(eggs)

	display_game("")

	# Status
	var my_status = "[color=#00FF00]READY[/color]" if trade_my_ready else "[color=#808080]Not Ready[/color]"
	var their_status = "[color=#00FF00]READY[/color]" if trade_partner_ready else "[color=#808080]Not Ready[/color]"
	display_game("Your Status: %s    |    %s's Status: %s" % [my_status, trade_partner_name, their_status])
	display_game("")

	# Instructions based on current state
	if trade_pending_add:
		_display_trade_item_selection(inventory, my_class)
	elif trade_pending_add_companion:
		_display_trade_companion_selection(companions)
	elif trade_pending_add_egg:
		_display_trade_egg_selection(eggs)
	else:
		display_game("[color=#808080][Q] Add  |  [W] Remove  |  [E] Ready/Unready  |  [R] Cancel  |  [1-3] Switch Tab[/color]")

func _display_trade_items_tab(inventory: Array, my_class: String):
	"""Display the items tab in trade window."""
	# Your Offer section
	display_game("[color=#00FF00]── YOUR OFFER ──[/color]")
	if trade_my_items.is_empty():
		display_game("  [color=#555555](no items offered)[/color]")
	else:
		for i in range(trade_my_items.size()):
			var inv_idx = trade_my_items[i]
			if inv_idx >= 0 and inv_idx < inventory.size():
				var item = inventory[inv_idx]
				var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
				var themed_name = _get_themed_item_name(item, my_class)
				display_game("  %d. [color=%s]%s[/color]" % [i + 1, rarity_color, themed_name])
	display_game("")

	# Their Offer section
	display_game("[color=#00FFFF]── %s'S OFFER ──[/color]" % trade_partner_name.to_upper())
	if trade_partner_items.is_empty():
		display_game("  [color=#555555](no items offered)[/color]")
	else:
		for i in range(trade_partner_items.size()):
			var item = trade_partner_items[i]
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var themed_name = _get_themed_item_name(item, trade_partner_class)
			display_game("  %d. [color=%s]%s[/color]" % [i + 1, rarity_color, themed_name])

func _display_trade_companions_tab(companions: Array):
	"""Display the companions tab in trade window."""
	# Your Offer section
	display_game("[color=#00FF00]── YOUR OFFER ──[/color]")
	if trade_my_companions_data.is_empty():
		display_game("  [color=#555555](no companions offered)[/color]")
	else:
		for i in range(trade_my_companions_data.size()):
			var comp = trade_my_companions_data[i]
			var variant = comp.get("variant", "")
			var variant_color = comp.get("variant_color", "#FFFFFF")
			var name_str = comp.get("name", "Unknown")
			if not variant.is_empty():
				name_str = "[color=%s]%s[/color] %s" % [variant_color, variant, name_str]
			display_game("  %d. %s (Lv.%d)" % [i + 1, name_str, comp.get("level", 1)])
	display_game("")

	# Their Offer section
	display_game("[color=#00FFFF]── %s'S OFFER ──[/color]" % trade_partner_name.to_upper())
	if trade_partner_companions.is_empty():
		display_game("  [color=#555555](no companions offered)[/color]")
	else:
		for i in range(trade_partner_companions.size()):
			var comp = trade_partner_companions[i]
			var variant = comp.get("variant", "")
			var variant_color = comp.get("variant_color", "#FFFFFF")
			var name_str = comp.get("name", "Unknown")
			if not variant.is_empty():
				name_str = "[color=%s]%s[/color] %s" % [variant_color, variant, name_str]
			display_game("  %d. %s (Lv.%d)" % [i + 1, name_str, comp.get("level", 1)])

func _display_trade_eggs_tab(eggs: Array):
	"""Display the eggs tab in trade window."""
	# Your Offer section
	display_game("[color=#00FF00]── YOUR OFFER ──[/color]")
	if trade_my_eggs_data.is_empty():
		display_game("  [color=#555555](no eggs offered)[/color]")
	else:
		for i in range(trade_my_eggs_data.size()):
			var egg = trade_my_eggs_data[i]
			var monster_type = egg.get("monster_type", "Unknown")
			var steps = egg.get("steps_remaining", 0)
			var frozen = egg.get("frozen", false)
			var frozen_str = " [color=#00BFFF][FROZEN][/color]" if frozen else ""
			display_game("  %d. %s Egg (%d steps)%s" % [i + 1, monster_type, steps, frozen_str])
	display_game("")

	# Their Offer section
	display_game("[color=#00FFFF]── %s'S OFFER ──[/color]" % trade_partner_name.to_upper())
	if trade_partner_eggs.is_empty():
		display_game("  [color=#555555](no eggs offered)[/color]")
	else:
		for i in range(trade_partner_eggs.size()):
			var egg = trade_partner_eggs[i]
			var monster_type = egg.get("monster_type", "Unknown")
			var steps = egg.get("steps_remaining", 0)
			var frozen = egg.get("frozen", false)
			var frozen_str = " [color=#00BFFF][FROZEN][/color]" if frozen else ""
			display_game("  %d. %s Egg (%d steps)%s" % [i + 1, monster_type, steps, frozen_str])

func _display_trade_item_selection(inventory: Array, my_class: String):
	"""Display inventory items for selection during trade."""
	display_game("[color=#FFFF00]Select an item from your inventory to add (1-9):[/color]")
	var start_idx = inventory_page * INVENTORY_PAGE_SIZE
	var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, inventory.size())
	for i in range(start_idx, end_idx):
		var item = inventory[i]
		var display_num = (i - start_idx) + 1
		var in_offer = i in trade_my_items
		var prefix = "[color=#00FF00]✓[/color] " if in_offer else "  "
		var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
		var themed_name = _get_themed_item_name(item, my_class)
		display_game("%s%d. [color=%s]%s[/color]" % [prefix, display_num, rarity_color, themed_name])

func _display_trade_companion_selection(companions: Array):
	"""Display companions for selection during trade."""
	display_game("[color=#FFFF00]Select a companion to add (1-5):[/color]")
	var active_companion = character_data.get("active_companion", null)
	for i in range(companions.size()):
		var comp = companions[i]
		var display_num = i + 1
		var in_offer = i in trade_my_companions
		var is_active = active_companion != null and active_companion.get("id") == comp.get("id")
		var prefix = "[color=#00FF00]✓[/color] " if in_offer else "  "
		var active_str = " [color=#FFFF00](ACTIVE)[/color]" if is_active else ""
		var variant = comp.get("variant", "")
		var variant_color = comp.get("variant_color", "#FFFFFF")
		var name_str = comp.get("name", "Unknown")
		if not variant.is_empty():
			name_str = "[color=%s]%s[/color] %s" % [variant_color, variant, name_str]
		display_game("%s%d. %s (Lv.%d)%s" % [prefix, display_num, name_str, comp.get("level", 1), active_str])

func _display_trade_egg_selection(eggs: Array):
	"""Display eggs for selection during trade."""
	display_game("[color=#FFFF00]Select an egg to add (1-3):[/color]")
	for i in range(eggs.size()):
		var egg = eggs[i]
		var display_num = i + 1
		var in_offer = i in trade_my_eggs
		var prefix = "[color=#00FF00]✓[/color] " if in_offer else "  "
		var monster_type = egg.get("monster_type", "Unknown")
		var steps = egg.get("steps_remaining", 0)
		var frozen = egg.get("frozen", false)
		var frozen_str = " [color=#00BFFF][FROZEN][/color]" if frozen else ""
		display_game("%s%d. %s Egg (%d steps)%s" % [prefix, display_num, monster_type, steps, frozen_str])

func handle_trade_command(target_name: String):
	"""Send a trade request to another player."""
	if in_trade:
		display_game("[color=#FF0000]You are already in a trade.[/color]")
		return
	if in_combat:
		display_game("[color=#FF0000]Cannot trade while in combat.[/color]")
		return

	send_to_server({
		"type": "trade_request",
		"target": target_name
	})

func select_trade_item(display_index: int):
	"""Add an item to the trade offer by its display index (0-8)."""
	var inventory = character_data.get("inventory", [])
	var actual_index = inventory_page * INVENTORY_PAGE_SIZE + display_index

	if actual_index < 0 or actual_index >= inventory.size():
		display_game("[color=#FF0000]Invalid item.[/color]")
		return

	# Check if already in offer
	if actual_index in trade_my_items:
		# Remove it instead
		send_to_server({"type": "trade_remove", "index": actual_index})
	else:
		# Add it
		send_to_server({"type": "trade_offer", "index": actual_index})

	# Go back to main trade view
	trade_pending_add = false
	display_trade_window()
	update_action_bar()

func select_trade_companion(display_index: int):
	"""Add a companion to the trade offer by its display index (0-4)."""
	var companions = character_data.get("collected_companions", [])

	if display_index < 0 or display_index >= companions.size():
		display_game("[color=#FF0000]Invalid companion.[/color]")
		return

	# Check if already in offer
	if display_index in trade_my_companions:
		# Remove it instead
		send_to_server({"type": "trade_remove_companion", "index": display_index})
	else:
		# Add it
		send_to_server({"type": "trade_add_companion", "index": display_index})

	# Go back to main trade view
	trade_pending_add_companion = false
	display_trade_window()
	update_action_bar()

func select_trade_egg(display_index: int):
	"""Add an egg to the trade offer by its display index (0-2)."""
	var eggs = character_data.get("incubating_eggs", [])

	if display_index < 0 or display_index >= eggs.size():
		display_game("[color=#FF0000]Invalid egg.[/color]")
		return

	# Check if already in offer
	if display_index in trade_my_eggs:
		# Remove it instead
		send_to_server({"type": "trade_remove_egg", "index": display_index})
	else:
		# Add it
		send_to_server({"type": "trade_add_egg", "index": display_index})

	# Go back to main trade view
	trade_pending_add_egg = false
	display_trade_window()
	update_action_bar()

# ===== INVENTORY FUNCTIONS =====

func open_inventory():
	"""Open inventory view and switch to inventory mode"""
	inventory_mode = true
	inventory_page = 0  # Reset to first page when opening
	last_item_use_result = ""  # Clear any previous item use result
	set_inventory_background("base")

	# In dungeon (out of combat), auto-enter use mode for quick item access
	if dungeon_mode and not in_combat:
		var inventory = character_data.get("inventory", [])
		var usable_items = []
		for i in range(inventory.size()):
			var item = inventory[i]
			var item_type = item.get("type", "")
			if item.get("is_consumable", false) or "potion" in item_type or "elixir" in item_type or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("scroll_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_"):
				usable_items.append({"index": i, "item": item})
		if not usable_items.is_empty():
			pending_inventory_action = "use_item"
			set_inventory_background("use")
			use_page = 0
			set_meta("usable_items", usable_items)
			_display_usable_items_page()
			update_action_bar()
			return

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

func open_sort_menu():
	"""Open sort submenu for inventory"""
	pending_inventory_action = "sort_select"
	sort_menu_page = 0  # Reset to first page
	_display_sort_menu()

func _display_sort_menu():
	"""Display the sort menu based on current page"""
	game_output.clear()
	display_game("[color=#FFD700]===== SORT INVENTORY =====[/color]")
	display_game("")
	if sort_menu_page == 0:
		display_game("Choose how to sort your inventory:")
		display_game("")
		display_game("  [color=#00FFFF]Level[/color] - Sort by item level (highest first)")
		display_game("  [color=#FF6666]HP[/color] - Sort by HP bonus (highest first)")
		display_game("  [color=#FFFF00]ATK[/color] - Sort by Attack bonus (highest first)")
		display_game("  [color=#00FF00]DEF[/color] - Sort by Defense bonus (highest first)")
		display_game("  [color=#FF00FF]WIT[/color] - Sort by Wits bonus (highest first)")
		display_game("  [color=#66CCFF]Mana[/color] - Sort by Mana bonus (highest first)")
		display_game("  [color=#FFA500]Speed[/color] - Sort by Speed bonus (highest first)")
		display_game("  [color=#808080]Slot[/color] - Group by equipment slot")
		display_game("")
		display_game("[color=#808080]Press [%s] More... for Compare Stat setting[/color]" % get_action_key_name(9))
	else:
		display_game("Additional sort and display options:")
		display_game("")
		display_game("  [color=#A335EE]Rarity[/color] - Sort by rarity (legendary first)")
		display_game("")
		display_game("[color=#00FFFF]Compare Stat:[/color] [color=#FFFF00]%s[/color]" % _get_compare_stat_label(inventory_compare_stat))
		display_game("[color=#808080]The compare stat determines what the ↑↓ arrows next to items compare.[/color]")
		display_game("[color=#808080]Press Cmp button to cycle: Level → HP → ATK → DEF → WIT → Mana → Speed[/color]")
	display_game("")
	update_action_bar()

func open_salvage_menu():
	"""Open salvage submenu for bulk item disposal"""
	pending_inventory_action = "salvage_select"
	var inventory = character_data.get("inventory", [])
	var player_level = character_data.get("level", 1)
	var threshold = max(1, player_level - 5)

	# Count items that would be salvaged and estimate essence
	var below_level_count = 0
	var total_count = 0
	var below_level_essence = 0
	var total_essence = 0
	for item in inventory:
		var item_level = item.get("level", 1)
		var rarity = item.get("rarity", "common")
		var is_consumable = _is_consumable_type(item.get("type", ""))
		var is_locked = item.get("locked", false) or item.get("is_title_item", false)

		if is_locked:
			continue

		# Calculate essence using salvage formula: base + (level * per_level)
		var salvage_values = {"common": [5, 1], "uncommon": [10, 2], "rare": [25, 3], "epic": [50, 5], "legendary": [100, 8], "artifact": [200, 12]}
		var sv = salvage_values.get(rarity, [5, 1])
		var essence = sv[0] + (item_level * sv[1])

		if not is_consumable:
			total_count += 1
			total_essence += essence
			if item_level < threshold:
				below_level_count += 1
				below_level_essence += essence

	var current_essence = character_data.get("salvage_essence", 0)

	game_output.clear()
	display_game("[color=#FFD700]===== SALVAGE ITEMS =====[/color]")
	display_game("")
	display_game("Convert items to [color=#AA66FF]Salvage Essence[/color], used for crafting upgrades.")
	display_game("Current Essence: [color=#AA66FF]%d[/color]" % current_essence)
	display_game("")
	display_game("[color=#FFA500]All (<Lv%d)[/color] - %d items → ~%d essence" % [threshold, below_level_count, below_level_essence])
	display_game("[color=#FF0000]All Items[/color] - %d items → ~%d essence (use with caution!)" % [total_count, total_essence])
	display_game("")
	display_game("[color=#808080]Note: Equipped items, locked items, and consumables not affected.[/color]")
	display_game("[color=#808080]Bonus materials may drop based on item type![/color]")
	display_game("")
	display_game("[color=#808080]Use Discard to destroy a single item without salvaging.[/color]")
	display_game("")
	update_action_bar()

func display_inventory():
	"""Display the player's inventory and equipped items"""
	if not has_character:
		return

	# Clear output to show fresh inventory view
	game_output.clear()

	var inventory = character_data.get("inventory", [])
	var equipped = character_data.get("equipped", {})

	# Show crafting resources summary above inventory header
	var resources_line = _get_resources_summary()
	if resources_line != "":
		display_game(resources_line)
		display_game("")

	display_game("[color=#FFD700]===== INVENTORY =====[/color]")

	# Show equipped items with level and stats (using themed names)
	var player_class = character_data.get("class", "")
	display_game("[color=#00FFFF]Equipped:[/color]")
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var item = equipped.get(slot)
		var slot_display = _get_themed_slot_name(slot, player_class)
		if item != null and item is Dictionary:
			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var item_level = item.get("level", 1)
			var bonus_text = _get_item_bonus_summary(item)
			var themed_name = _get_themed_item_name(item, player_class)
			# Show wear condition
			var wear = item.get("wear", 0)
			var wear_text = ""
			if wear > 0:
				var condition_color = _get_condition_color(wear)
				wear_text = " [color=%s](%d%% worn)[/color]" % [condition_color, wear]
			display_game("  %s: [color=%s]%s[/color] (Lv%d) %s%s" % [
				slot_display, rarity_color, themed_name, item_level, bonus_text, wear_text
			])
		else:
			display_game("  %s: [color=#555555](empty)[/color]" % slot_display)

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
	# Partition items: equipment first, consumables last
	display_game("")
	var equipment_items: Array = []
	var consumable_items: Array = []
	for idx in range(inventory.size()):
		var itm = inventory[idx]
		if itm.get("is_consumable", false):
			consumable_items.append({"index": idx, "item": itm})
		else:
			equipment_items.append({"index": idx, "item": itm})
	var display_order: Array = equipment_items + consumable_items
	set_meta("inventory_display_order", display_order)

	var total_pages = max(1, int(ceil(float(display_order.size()) / INVENTORY_PAGE_SIZE)))
	# Clamp page to valid range
	inventory_page = clamp(inventory_page, 0, total_pages - 1)

	display_game("[color=#00FFFF]Backpack (%d/40) - Page %d/%d:[/color]" % [inventory.size(), inventory_page + 1, total_pages])
	if inventory.is_empty():
		display_game("  [color=#555555](empty)[/color]")
	else:
		var start_idx = inventory_page * INVENTORY_PAGE_SIZE
		var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, display_order.size())
		var showed_separator = false

		for di in range(start_idx, end_idx):
			var entry = display_order[di]
			var abs_idx = entry.index
			var item = entry.item

			# Show separator when transitioning from equipment to consumables on this page
			if not showed_separator and item.get("is_consumable", false):
				# Only show separator if there were equipment items before this point
				if equipment_items.size() > 0 and di > 0 and not display_order[di - 1].item.get("is_consumable", false):
					display_game("  [color=#808080]--- Consumables ---[/color]")
				elif di == start_idx and equipment_items.size() > 0:
					# First item on page is consumable but equipment exists on prior pages
					display_game("  [color=#808080]--- Consumables ---[/color]")
				showed_separator = true

			var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
			var item_level = item.get("level", 1)
			var item_type = item.get("type", "")

			# Show comparison arrow on left and detailed stats on right for equippable items
			var compare_arrow = ""
			var compare_text = ""
			var slot = _get_slot_for_item_type(item_type)
			if slot != "":
				var equipped_item = equipped.get(slot)
				compare_arrow = _get_compare_arrow(item, equipped_item) + " "
				var diff_parts = _get_item_comparison_parts(item, equipped_item)
				if diff_parts.size() > 0:
					compare_text = " [%s]" % ", ".join(diff_parts)

			# Display number is 1-9 for current page
			var display_num = (di - start_idx) + 1

			# Lock indicator
			var lock_text = "[color=#FF4444][L][/color] " if item.get("locked", false) else ""

			# Check if consumable (show quantity) vs equipment (show level + stats)
			var is_consumable = item.get("is_consumable", false)
			if is_consumable:
				var quantity = item.get("quantity", 1)
				var qty_text = " x%d" % quantity if quantity > 1 else ""
				display_game("  %d. %s[color=%s]%s[/color]%s" % [
					display_num, lock_text, rarity_color, item.get("name", "Unknown"), qty_text
				])
			else:
				# Show equipment with arrow on left, stats on right (using themed names)
				var bonus_text = _get_item_bonus_summary(item)
				var slot_abbr = _get_slot_abbreviation(item_type)
				var themed_name = _get_themed_item_name(item, player_class)
				# Show wear condition if damaged
				var wear = item.get("wear", 0)
				var wear_text = ""
				if wear > 0:
					var condition_color = _get_condition_color(wear)
					wear_text = " [color=%s]%d%%[/color]" % [condition_color, wear]
				display_game("  %d. %s%s[color=%s]%s[/color] Lv%d %s %s%s%s" % [
					display_num, lock_text, compare_arrow, rarity_color, themed_name, item_level, bonus_text, slot_abbr, wear_text, compare_text
				])

	display_game("")
	display_game("[color=#808080]%s=Back  %s=Inspect  %s=Use  %s=Equip  %s=Unequip[/color]" % [
		get_action_key_name(0), get_action_key_name(1), get_action_key_name(2),
		get_action_key_name(3), get_action_key_name(4)])
	display_game("[color=#808080]%s=Sort  %s=Salvage  %s=Lock[/color]" % [
		get_action_key_name(5), get_action_key_name(6), get_action_key_name(7)])
	display_game("[color=#808080]↑↓ arrows compare: %s (change in Sort menu)[/color]" % _get_compare_stat_label(inventory_compare_stat))
	if total_pages > 1:
		display_game("[color=#808080]%s/%s=Prev/Next Page[/color]" % [get_action_key_name(8), get_action_key_name(9)])

	# Show last item use result if any
	if last_item_use_result != "":
		display_game("")
		display_game(last_item_use_result)

func display_materials():
	"""Display the player's crafting materials organized by type"""
	if not has_character:
		return

	game_output.clear()
	var materials = character_data.get("crafting_materials", {})
	var salvage_essence = character_data.get("salvage_essence", 0)

	display_game("[color=#FFD700]===== CRAFTING MATERIALS =====[/color]")
	display_game("")
	display_game("[color=#AA66FF]Salvage Essence:[/color] %d" % salvage_essence)
	display_game("")

	if materials.is_empty():
		display_game("[color=#808080]No materials collected yet.[/color]")
		display_game("")
		display_game("[color=#808080]Gather materials by:[/color]")
		display_game("  - Fishing at water tiles")
		display_game("  - Mining at ore deposits")
		display_game("  - Chopping at dense forests")
		display_game("  - Monster drops")
		display_game("  - Salvaging items (bonus materials)")
		return

	# Material definitions for display (type -> display name and color)
	var type_info = {
		"ore": {"name": "Ores", "color": "#C0C0C0"},
		"wood": {"name": "Wood", "color": "#8B4513"},
		"leather": {"name": "Leather", "color": "#CD853F"},
		"cloth": {"name": "Cloth", "color": "#DDA0DD"},
		"herb": {"name": "Herbs", "color": "#32CD32"},
		"fish": {"name": "Fish", "color": "#4169E1"},
		"enchant": {"name": "Enchanting", "color": "#9400D3"},
		"gem": {"name": "Gems", "color": "#00CED1"},
		"essence": {"name": "Essences", "color": "#FF69B4"},
		"plant": {"name": "Plants", "color": "#228B22"},
		"mineral": {"name": "Minerals", "color": "#708090"}
	}

	# Group materials by type
	var grouped: Dictionary = {}
	for mat_id in materials:
		var mat_data = CraftingDatabase.get_material(mat_id)
		var mat_type = mat_data.get("type", "misc")
		if not grouped.has(mat_type):
			grouped[mat_type] = []
		grouped[mat_type].append({
			"id": mat_id,
			"name": mat_data.get("name", mat_id),
			"tier": mat_data.get("tier", 1),
			"quantity": materials[mat_id]
		})

	# Sort each group by tier
	for mat_type in grouped:
		grouped[mat_type].sort_custom(func(a, b): return a.tier < b.tier)

	# Display in order
	var display_order = ["ore", "wood", "leather", "cloth", "herb", "fish", "enchant", "gem", "essence", "plant", "mineral"]
	for mat_type in display_order:
		if grouped.has(mat_type):
			var info = type_info.get(mat_type, {"name": mat_type.capitalize(), "color": "#FFFFFF"})
			display_game("[color=%s]%s:[/color]" % [info.color, info.name])
			for mat in grouped[mat_type]:
				display_game("  [color=#AAAAAA]T%d[/color] %s x%d" % [mat.tier, mat.name, mat.quantity])
			display_game("")

	# Show any ungrouped materials
	for mat_type in grouped:
		if mat_type not in display_order:
			display_game("[color=#FFFFFF]%s:[/color]" % mat_type.capitalize())
			for mat in grouped[mat_type]:
				display_game("  [color=#AAAAAA]T%d[/color] %s x%d" % [mat.tier, mat.name, mat.quantity])
			display_game("")

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
		# Amulets give mana, but display as class resource with scaling
		var mana_val = base * 2
		var player_class = character_data.get("class", "")
		var resource_name = "Resource"
		var resource_color = "#FF66FF"
		var scaled_val = mana_val
		match player_class:
			"Wizard", "Sorcerer", "Sage":
				resource_name = "Mana"
				resource_color = "#9999FF"
			"Fighter", "Barbarian", "Paladin":
				resource_name = "Stamina"
				resource_color = "#FFCC00"
				scaled_val = int(mana_val * 0.5)
			"Thief", "Ranger", "Ninja", "Trickster":
				resource_name = "Energy"
				resource_color = "#66FF66"
				scaled_val = int(mana_val * 0.5)
		return "[color=%s]+%d %s[/color]" % [resource_color, scaled_val, resource_name]
	return ""

func _is_consumable_type(item_type: String) -> bool:
	"""Check if an item type is a consumable (potion, scroll, crafted consumable, etc.)"""
	return (item_type == "consumable" or  # Crafted consumables (Enchanted Kindling, etc.)
			item_type.begins_with("potion_") or item_type.begins_with("mana_") or
			item_type.begins_with("stamina_") or item_type.begins_with("energy_") or
			item_type.begins_with("scroll_") or item_type.begins_with("tome_") or
			item_type == "gold_pouch" or item_type.begins_with("gem_") or
			item_type == "mysterious_box" or item_type == "cursed_coin" or
			item_type == "soul_gem")

func _get_slot_for_item_type(item_type: String) -> String:
	"""Get equipment slot for an item type"""
	# Title items are never equipment (jarls_ring, unforged_crown, crown_of_north)
	if item_type in ["jarls_ring", "unforged_crown", "crown_of_north"]:
		return ""
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

func _get_slot_abbreviation(item_type: String) -> String:
	"""Get a short slot indicator for inventory display"""
	# Title items are not equipment
	if item_type in ["jarls_ring", "unforged_crown", "crown_of_north"]:
		return "[color=#FFD700][QST][/color]"
	if "weapon" in item_type:
		return "[color=#666666][WPN][/color]"
	elif "armor" in item_type:
		return "[color=#666666][ARM][/color]"
	elif "helm" in item_type:
		return "[color=#666666][HLM][/color]"
	elif "shield" in item_type:
		return "[color=#666666][SHD][/color]"
	elif "boots" in item_type:
		return "[color=#666666][BOT][/color]"
	elif "ring" in item_type:
		return "[color=#666666][RNG][/color]"
	elif "amulet" in item_type:
		return "[color=#666666][AMU][/color]"
	return ""

func _get_themed_item_name(item: Dictionary, owner_class: String = "") -> String:
	"""Get the item name themed for a specific class.
	If owner_class is empty, uses the current player's class.
	Title items are never themed - they keep their original names."""
	var item_name = item.get("name", "Unknown")

	# Title items should never be themed - they keep their original names
	if item.get("is_title_item", false):
		return item_name

	var item_type = item.get("type", "")
	var slot = _get_slot_for_item_type(item_type)

	if slot == "":
		return item_name  # Not an equipment item

	var class_type = owner_class if owner_class != "" else character_data.get("class", "")
	if class_type == "":
		return item_name

	return CharacterScript.get_themed_item_name(item_name, slot, class_type)

func _get_resources_summary() -> String:
	"""Get a compact summary line of crafting resources for inventory header"""
	var parts = []

	# Salvage Essence
	var essence = character_data.get("salvage_essence", 0)
	if essence > 0:
		parts.append("[color=#AA66FF]ESS:%d[/color]" % essence)

	# Count materials by type
	var materials = character_data.get("crafting_materials", {})
	var type_counts = {"ore": 0, "wood": 0, "leather": 0, "fish": 0, "herb": 0, "gem": 0, "enchant": 0}

	for mat_id in materials:
		var mat_data = CraftingDatabase.get_material(mat_id)
		var mat_type = mat_data.get("type", "misc")
		if type_counts.has(mat_type):
			type_counts[mat_type] += materials[mat_id]

	# Add non-zero counts with abbreviations and colors
	if type_counts["ore"] > 0:
		parts.append("[color=#C0C0C0]ORE:%d[/color]" % type_counts["ore"])
	if type_counts["wood"] > 0:
		parts.append("[color=#8B4513]WD:%d[/color]" % type_counts["wood"])
	if type_counts["leather"] > 0:
		parts.append("[color=#CD853F]LTH:%d[/color]" % type_counts["leather"])
	if type_counts["fish"] > 0:
		parts.append("[color=#4169E1]FSH:%d[/color]" % type_counts["fish"])
	if type_counts["herb"] > 0:
		parts.append("[color=#32CD32]HRB:%d[/color]" % type_counts["herb"])
	if type_counts["gem"] > 0:
		parts.append("[color=#00CED1]GEM:%d[/color]" % type_counts["gem"])
	if type_counts["enchant"] > 0:
		parts.append("[color=#9400D3]ENC:%d[/color]" % type_counts["enchant"])

	if parts.is_empty():
		return ""

	return " ".join(parts)

func _get_themed_slot_name(slot: String, class_type: String = "") -> String:
	"""Get the themed name for an equipment slot based on class."""
	if class_type == "":
		class_type = character_data.get("class", "")
	if class_type == "" or not CharacterScript.CLASS_EQUIPMENT_THEMES.has(class_type):
		return slot.capitalize()
	return CharacterScript.CLASS_EQUIPMENT_THEMES[class_type].get(slot, slot.capitalize())

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
				# Also check the is_consumable flag as a fallback
				if item.get("is_consumable", false) or "potion" in item_type or "elixir" in item_type or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("scroll_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_"):
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
				# Consumables have types like: potion_*, elixir_*, scroll_*, gold_*, gem_*, mana_*, stamina_*, energy_*, tome_*, consumable (crafted)
				var is_consumable = _is_consumable_type(item_type) or "potion" in item_type or "elixir" in item_type
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
			var player_class = character_data.get("class", "")
			# Display equipped items with numbers
			display_game("[color=#FFD700]===== UNEQUIP ITEM =====[/color]")
			for i in range(slots_with_items.size()):
				var slot = slots_with_items[i]
				var item = equipped.get(slot)
				var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
				var themed_name = _get_themed_item_name(item, player_class)
				var slot_display = _get_themed_slot_name(slot, player_class)
				display_game("%d. [color=#AAAAAA]%s:[/color] [color=%s]%s[/color]" % [i + 1, slot_display, rarity_color, themed_name])
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
			var player_class = character_data.get("class", "")
			# Display equipped items with numbers
			display_game("[color=#FFD700]===== INSPECT EQUIPPED =====[/color]")
			for i in range(slots_with_items.size()):
				var slot = slots_with_items[i]
				var item = equipped.get(slot)
				var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
				var themed_name = _get_themed_item_name(item, player_class)
				var slot_display = _get_themed_slot_name(slot, player_class)
				display_game("%d. [color=#AAAAAA]%s:[/color] [color=%s]%s[/color]" % [i + 1, slot_display, rarity_color, themed_name])
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

		"lock":
			if inventory.is_empty():
				display_game("[color=#FF0000]No items to lock/unlock.[/color]")
				return
			pending_inventory_action = "lock_item"
			# Mark all item keys as pressed to prevent the held key from
			# also triggering item selection on the same keypress
			for k in range(9):
				set_meta("itemkey_%d_pressed" % k, true)
			display_inventory()  # Show inventory for selection
			display_game("[color=#FFD700]%s to lock/unlock an item:[/color]" % get_selection_keys_text(inventory.size()))
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

	var player_class = character_data.get("class", "")
	# Display equipped items with numbers
	display_game("[color=#FFD700]===== UNEQUIP ITEM =====[/color]")
	for i in range(slots_with_items.size()):
		var slot = slots_with_items[i]
		var item = equipped.get(slot)
		var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
		var themed_name = _get_themed_item_name(item, player_class)
		var slot_display = _get_themed_slot_name(slot, player_class)
		display_game("%d. [color=#AAAAAA]%s:[/color] [color=%s]%s[/color]" % [i + 1, slot_display, rarity_color, themed_name])
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

	# Return to settings if we entered from there
	if ability_entered_from_settings:
		ability_entered_from_settings = false
		open_settings()
	else:
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

	# Show currently equipped abilities in 6 slots
	# Combat action bar: indices 0-3 are Attack/UseItem/Flee/Outsmart, indices 4-9 are ability slots
	# So ability slot i maps to action bar index (4 + i)
	display_game("[color=#00FFFF]Your Combat Slots:[/color] (press these keys during combat)")
	display_game("")
	for i in range(6):
		var ability_name = equipped[i] if i < equipped.size() else ""
		var combat_key = get_action_key_name(4 + i)  # Ability slots start at action bar index 4
		if ability_name != "" and ability_name != null:
			var ability_info = _get_ability_info_from_list(ability_name, all_abilities)
			var display_name = ability_info.get("display", ability_name.capitalize().replace("_", " "))
			var cost_text = _get_ability_cost_text(ability_name)
			display_game("  Slot %d: [color=#00FF00]%s[/color] %s  [color=#AAAAAA]→ Press [%s] in combat[/color]" % [i + 1, display_name, cost_text, combat_key])
		else:
			display_game("  Slot %d: [color=#555555](empty)[/color]  [color=#555555]→ Key: %s[/color]" % [i + 1, combat_key])

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
	display_game("[color=#FFD700]Menu Controls:[/color]")
	display_game("  [%s] Equip - Add an ability to a slot" % get_action_key_name(1))
	display_game("  [%s] Unequip - Remove an ability from a slot" % get_action_key_name(2))
	display_game("  [%s] Back - Return to game" % get_action_key_name(0))
	display_game("")
	display_game("[color=#808080]Tip: Change combat keybinds in Settings (action_4 through action_7)[/color]")

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

	# Get base cost and cost percentage for mage abilities
	var base_cost = 0
	var cost_percent = 0
	match ability_name:
		# Mage abilities - use percentage-based scaling
		"magic_bolt":
			base_cost = 0  # Variable
			cost_percent = 0
		"shield":
			base_cost = 20
			cost_percent = 2
		"blast":
			base_cost = 50
			cost_percent = 5
		"forcefield":
			base_cost = 75
			cost_percent = 7
		"teleport":
			base_cost = 40
			cost_percent = 0  # Distance-based
		"meteor":
			base_cost = 100
			cost_percent = 8
		"haste":
			base_cost = 35
			cost_percent = 3
		"paralyze":
			base_cost = 60
			cost_percent = 6
		"banish":
			base_cost = 80
			cost_percent = 10
		# Warrior abilities
		"power_strike": base_cost = 10
		"war_cry": base_cost = 15
		"shield_bash": base_cost = 20
		"cleave": base_cost = 30
		"berserk": base_cost = 40
		"iron_skin": base_cost = 35
		"devastate": base_cost = 60
		"fortify": base_cost = 25
		"rally": base_cost = 45
		# Trickster abilities
		"analyze": base_cost = 5
		"distract": base_cost = 15
		"pickpocket": base_cost = 20
		"ambush": base_cost = 30
		"vanish": base_cost = 40
		"exploit": base_cost = 35
		"perfect_heist": base_cost = 50
		"sabotage": base_cost = 25
		"gambit": base_cost = 35
		# Universal
		"cloak": base_cost = 0  # % based

	# Calculate actual cost for mage abilities (max of base or percentage)
	var cost = base_cost
	if path == "mage" and cost_percent > 0:
		var max_mana = character_data.get("total_max_mana", character_data.get("max_mana", 100))
		var percent_cost = int(max_mana * cost_percent / 100.0)
		cost = max(base_cost, percent_cost)

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
	display_game("[color=#FFD700]Select slot (1-6) to equip to:[/color]")
	update_action_bar()

func show_ability_unequip_prompt():
	"""Show prompt to select slot to unequip"""
	pending_ability_action = "select_unequip_slot"
	display_game("")
	display_game("[color=#FFD700]Select slot (1-6) to unequip:[/color]")
	update_action_bar()

func show_keybind_prompt():
	"""Show prompt to change keybinds"""
	pending_ability_action = "select_keybind_slot"
	display_game("")
	display_game("[color=#FFD700]Select slot (1-6) to change keybind:[/color]")
	update_action_bar()

func handle_ability_slot_selection(slot_num: int):
	"""Handle when a slot number is selected in ability mode"""
	if slot_num < 1 or slot_num > 6:
		display_game("[color=#FF0000]Invalid slot. Use 1-6.[/color]")
		return

	var slot_index = slot_num - 1

	match pending_ability_action:
		"select_ability":
			# Show list of abilities to choose from
			selected_ability_slot = slot_index
			pending_ability_action = "choose_ability"
			ability_choice_page = 0  # Reset to first page
			display_ability_choice_list()
			update_action_bar()

		"select_unequip_slot":
			send_to_server({"type": "unequip_ability", "slot": slot_index})
			pending_ability_action = ""
			display_ability_menu()
			update_action_bar()

		"select_keybind_slot":
			selected_ability_slot = slot_index
			pending_ability_action = "press_keybind"
			display_game("")
			display_game("[color=#FFD700]Press a key for slot %d (Q/W/E/R or any letter):[/color]" % slot_num)
			update_action_bar()

func display_ability_choice_list():
	"""Display paginated list of abilities to choose from"""
	var unlocked = ability_data.get("unlocked_abilities", [])
	var total_pages = max(1, (unlocked.size() + ABILITY_PAGE_SIZE - 1) / ABILITY_PAGE_SIZE)
	ability_choice_page = clamp(ability_choice_page, 0, total_pages - 1)

	var start_idx = ability_choice_page * ABILITY_PAGE_SIZE
	var end_idx = min(start_idx + ABILITY_PAGE_SIZE, unlocked.size())

	display_game("")
	display_game("[color=#FFD700]Select ability for slot %d:[/color]" % (selected_ability_slot + 1))

	for i in range(start_idx, end_idx):
		var ability = unlocked[i]
		var display_name = ability.get("display", ability.name.capitalize())
		var display_num = (i - start_idx) + 1  # 1-9 on screen
		display_game("  %d. %s" % [display_num, display_name])

	if total_pages > 1:
		display_game("[color=#808080]Page %d/%d - [%s] Prev [%s] Next[/color]" % [ability_choice_page + 1, total_pages, get_action_key_name(1), get_action_key_name(2)])
	display_game("[color=#808080]Press 1-%d to select, %s to cancel[/color]" % [end_idx - start_idx, get_action_key_name(0)])

func handle_ability_choice(choice_num: int):
	"""Handle when an ability is chosen from the list (1-9 on current page)"""
	var unlocked = ability_data.get("unlocked_abilities", [])
	var start_idx = ability_choice_page * ABILITY_PAGE_SIZE
	var actual_index = start_idx + choice_num - 1  # Convert page-relative to actual index

	if actual_index < 0 or actual_index >= unlocked.size():
		display_game("[color=#FF0000]Invalid choice.[/color]")
		return

	var ability = unlocked[actual_index]
	send_to_server({"type": "equip_ability", "slot": selected_ability_slot, "ability": ability.name})
	pending_ability_action = ""
	selected_ability_slot = -1
	display_ability_menu()
	update_action_bar()

func handle_keybind_press(key: String):
	"""Handle a keybind press when setting keybind"""
	if key.length() != 1 or not key.is_valid_identifier():
		display_game("[color=#FF0000]Invalid key. Use a single letter.[/color]")
		return

	send_to_server({"type": "set_ability_keybind", "slot": selected_ability_slot, "key": key})
	pending_ability_action = ""
	selected_ability_slot = -1
	display_ability_menu()
	update_action_bar()

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
			# Show page-relative item count (using display_order for correct page size)
			var inv_display_order = get_meta("inventory_display_order", [])
			var display_total = inv_display_order.size() if inv_display_order.size() > 0 else inventory.size()
			var start_idx = inventory_page * INVENTORY_PAGE_SIZE
			var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, display_total)
			var items_on_page = end_idx - start_idx
			display_game("[color=#FFD700]%s to inspect another item, or [%s] to go back:[/color]" % [get_selection_keys_text(max(1, items_on_page)), get_action_key_name(0)])
			update_action_bar()
			return
		"discard_item":
			var discard_item = inventory[index]
			if discard_item.get("locked", false):
				display_game("[color=#FF4444]That item is locked! Unlock it first.[/color]")
				return
			pending_inventory_action = ""
			send_to_server({"type": "inventory_discard", "index": index})
			# Exit inventory mode after discard
			inventory_mode = false
			update_action_bar()
			return
		"lock_item":
			# Send lock toggle to server, stay in lock mode
			send_to_server({"type": "inventory_lock", "index": index})
			# Stay in lock_item mode for quick multiple locks
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
	var player_class = character_data.get("class", "")

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
		var item_name = _get_themed_item_name(item, player_class)
		var item_type = item.get("type", "")
		var rarity = item.get("rarity", "common")
		var level = item.get("level", 1)
		var color = _get_rarity_color(rarity)

		# Get bonus summary and slot abbreviation (matching Backpack format)
		var bonus_text = _get_item_bonus_summary(item)
		var slot_abbr = _get_slot_abbreviation(item_type)

		# Comparison with equipped item - show arrow on left and stat differences on right
		var compare_arrow = ""
		var compare_text = ""
		var slot = _get_slot_for_item_type(item_type)
		if slot != "":
			var equipped_item = equipped.get(slot)
			compare_arrow = _get_compare_arrow(item, equipped_item)
			var diff_parts = _get_item_comparison_parts(item, equipped_item)
			if diff_parts.size() > 0:
				compare_text = " [%s]" % ", ".join(diff_parts)

		# Display number is 1-9 for current page
		var display_num = (j - start_idx) + 1

		# Display item matching Backpack format: arrow + name + Lv# + bonus + slot + comparison
		display_game("[%d] %s [color=%s]%s[/color] Lv%d %s %s%s" % [display_num, compare_arrow, color, item_name, level, bonus_text, slot_abbr, compare_text])

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
	var inv_display_order = get_meta("inventory_display_order", [])
	var display_total = inv_display_order.size() if inv_display_order.size() > 0 else character_data.get("inventory", []).size()
	var start_idx = inventory_page * INVENTORY_PAGE_SIZE
	var end_idx = min(start_idx + INVENTORY_PAGE_SIZE, display_total)
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

# Health bar animation variables
var last_player_hp_percent: float = 100.0
var last_enemy_hp_percent: float = 100.0
var hp_bar_tween: Tween = null
var enemy_hp_bar_tween: Tween = null
var low_hp_pulse_active: bool = false

func animate_hp_bar_change(fill_node: Control, target_percent: float, is_player: bool = true):
	"""Animate HP bar changes with smooth tweening"""
	if not fill_node:
		return

	# Kill existing tween if any
	var tween_ref = hp_bar_tween if is_player else enemy_hp_bar_tween
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()

	# Create new tween for smooth transition
	var new_tween = create_tween()
	new_tween.tween_property(fill_node, "anchor_right", target_percent / 100.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	if is_player:
		hp_bar_tween = new_tween
	else:
		enemy_hp_bar_tween = new_tween

	# Flash effect on damage taken
	var current_percent = last_player_hp_percent if is_player else last_enemy_hp_percent
	if target_percent < current_percent:
		# Taking damage - flash red
		flash_hp_bar(fill_node, Color(1, 0, 0, 0.5))
	elif target_percent > current_percent:
		# Healing - flash green
		flash_hp_bar(fill_node, Color(0, 1, 0, 0.5))

	# Update tracking
	if is_player:
		last_player_hp_percent = target_percent
		# Start low HP pulse if below 25%
		if target_percent < 25.0 and not low_hp_pulse_active:
			start_low_hp_pulse()
		elif target_percent >= 25.0 and low_hp_pulse_active:
			stop_low_hp_pulse()
	else:
		last_enemy_hp_percent = target_percent

func flash_hp_bar(fill_node: Control, flash_color: Color):
	"""Quick flash effect on HP bar"""
	if not fill_node:
		return
	var flash_tween = create_tween()
	var original_modulate = fill_node.modulate
	fill_node.modulate = flash_color
	flash_tween.tween_property(fill_node, "modulate", original_modulate, 0.2)

func start_low_hp_pulse():
	"""Start pulsing effect when player HP is critically low"""
	low_hp_pulse_active = true
	_pulse_low_hp()

func stop_low_hp_pulse():
	"""Stop the low HP pulse effect"""
	low_hp_pulse_active = false
	if player_health_bar:
		var fill = player_health_bar.get_node("Fill")
		if fill:
			fill.modulate = Color(1, 1, 1, 1)

func _pulse_low_hp():
	"""Create pulsing effect for low HP"""
	if not low_hp_pulse_active or not player_health_bar:
		return
	var fill = player_health_bar.get_node("Fill")
	if not fill:
		return

	var pulse_tween = create_tween()
	pulse_tween.tween_property(fill, "modulate", Color(1.5, 0.5, 0.5, 1), 0.4)
	pulse_tween.tween_property(fill, "modulate", Color(1, 1, 1, 1), 0.4)
	pulse_tween.tween_callback(_pulse_low_hp)

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
		# Animate the HP bar change - clamp visual fill at 0% (no negative bar width)
		animate_hp_bar_change(fill, max(0.0, percent), true)
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

	# Blind (debuff) - gray
	if character_data.get("blind_active", false):
		var blind_turns = character_data.get("blind_turns_remaining", 0)
		parts.append("[color=#808080][BL:%d][/color]" % blind_turns)

	# Forcefield/Shield (combat) - cyan
	if current_forcefield > 0:
		parts.append("[color=#00FFFF][FF:%d][/color]" % current_forcefield)

	# Cloak (world movement) - purple
	if character_data.get("cloak_active", false):
		parts.append("[color=#9932CC][CLK][/color]")

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

func _get_buff_display_name(buff_type: String) -> String:
	"""Get display name for a buff type"""
	match buff_type.to_lower():
		"strength": return "Strength"
		"defense": return "Defense"
		"speed": return "Speed"
		"damage": return "Damage"
		"crit", "crit_chance": return "Crit Chance"
		"lifesteal": return "Lifesteal"
		"thorns": return "Thorns"
		"forcefield": return "Forcefield"
		"damage_reduction": return "Damage Reduction"
		"damage_penalty": return "Damage Penalty"
		"defense_penalty": return "Defense Penalty"
		"gold_find": return "Gold Find"
		"xp_bonus": return "XP Bonus"
		"war_cry": return "War Cry"
		"berserk": return "Berserk"
		"iron_skin": return "Iron Skin"
		"haste": return "Haste"
		"vanish": return "Vanish"
		"cloak", "invisibility": return "Invisibility"
		"shield": return "Shield"
		"rally": return "Rally"
		"fortify": return "Fortify"
		_: return buff_type.replace("_", " ").capitalize()

func _get_buff_color(buff_type: String) -> String:
	"""Get color for buff type display"""
	match buff_type.to_lower():
		"strength": return "#FF6666"  # Red
		"defense": return "#6666FF"   # Blue
		"speed": return "#66FF66"     # Green
		"damage": return "#FF6666"    # Red
		"crit", "crit_chance": return "#FFD700"  # Gold
		"lifesteal": return "#FF00FF"    # Magenta
		"thorns": return "#FF4444"       # Dark red
		"forcefield": return "#00FFFF"   # Cyan
		"damage_reduction": return "#00CED1"  # Dark cyan (Iron Skin)
		"damage_penalty": return "#FF4444"  # Dark red (debuff)
		"defense_penalty": return "#4444FF" # Dark blue (debuff)
		"gold_find": return "#FFD700"    # Gold
		"xp_bonus": return "#9B59B6"     # Purple (XP color)
		"war_cry": return "#FF6666"      # Red (warrior)
		"berserk": return "#8B0000"      # Dark red
		"iron_skin": return "#C0C0C0"    # Silver
		"haste": return "#00FF00"        # Bright green
		"vanish", "cloak", "invisibility": return "#9932CC"  # Purple (cloak color)
		"shield": return "#87CEEB"       # Light blue
		"rally": return "#FFD700"        # Gold
		"fortify": return "#C0C0C0"      # Silver
		_: return "#FFFFFF"  # White default

func _get_buff_letter(buff_type: String) -> String:
	"""Get short letter code for buff type"""
	match buff_type.to_lower():
		"strength": return "S"
		"defense": return "D"
		"speed": return "V"  # Velocity
		"damage": return "A"  # Attack
		"crit", "crit_chance": return "C"  # Crit
		"lifesteal": return "L"    # Lifesteal
		"thorns": return "T"       # Thorns
		"forcefield": return "F"   # Forcefield
		"damage_reduction": return "DR"  # Damage Reduction (Iron Skin)
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
			max_val = max(character_data.get("total_max_stamina", character_data.get("max_stamina", 1)), 1)
			resource_name = "Stamina"
			bar_color = Color(1.0, 0.8, 0.0)  # #FFCC00 Orange-yellow
		"mage":
			current_val = character_data.get("current_mana", 0)
			max_val = max(character_data.get("total_max_mana", character_data.get("max_mana", 1)), 1)
			resource_name = "Mana"
			bar_color = Color(0.6, 0.6, 1.0)  # #9999FF Purple
		"trickster":
			current_val = character_data.get("current_energy", 0)
			max_val = max(character_data.get("total_max_energy", character_data.get("max_energy", 1)), 1)
			resource_name = "Energy"
			bar_color = Color(0.4, 1.0, 0.4)  # #66FF66 Light green
		_:
			# No path - show mana by default
			current_val = character_data.get("current_mana", 0)
			max_val = max(character_data.get("total_max_mana", character_data.get("max_mana", 1)), 1)
			resource_name = "Mana"
			bar_color = Color(0.6, 0.6, 1.0)  # #9999FF Purple

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

	# Use base name for HP knowledge lookup so variants share data with base type
	var base_name = _get_base_monster_name(enemy_name)
	var enemy_key = "%s_%d" % [base_name, enemy_level]
	var label_node = enemy_health_bar.get_node("Label")
	var bar_container = enemy_health_bar.get_node("BarContainer")

	if label_node:
		# Display enemy name with level (color is shown in main combat text)
		# Add star indicator for rare variants (more XP/drops)
		if current_enemy_is_rare_variant:
			label_node.text = "★ %s (Lvl %d):" % [enemy_name, enemy_level]
		else:
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

	# DISCOVERY SYSTEM: Player discovers HP by defeating monsters, not from server.
	# Server actual HP is intentionally ignored - players only know what they've observed.
	# Only exception: Analyze ability reveals actual HP for the current combat.

	# Check if Analyze revealed actual HP this combat
	if analyze_revealed_max_hp > 0:
		# Analyze revealed true HP - use actual values for this combat
		var current_hp = max(0, analyze_revealed_max_hp - damage_dealt)
		if current_hp == 0 and in_combat:
			current_hp = 1  # Monster still alive
		var percent = (float(current_hp) / float(analyze_revealed_max_hp)) * 100.0
		if fill:
			animate_hp_bar_change(fill, percent, false)
		if hp_label:
			hp_label.text = "%d/%d" % [current_hp, analyze_revealed_max_hp]
		return

	# Use player's discovered knowledge (from previous kills - damage dealt)
	var suspected_max = 0
	var is_estimate = false
	if known_enemy_hp.has(enemy_key):
		# Player has killed this exact monster+level before
		suspected_max = known_enemy_hp[enemy_key]
	else:
		# Try to estimate based on known data from similar monsters at other levels
		suspected_max = estimate_enemy_hp(base_name, enemy_level)
		is_estimate = suspected_max > 0

	if suspected_max > 0:
		var suspected_current = max(0, suspected_max - damage_dealt)
		# If estimate shows 0 but monster is still alive (combat hasn't ended),
		# show at least 1 HP to indicate monster isn't dead yet
		if suspected_current == 0 and in_combat:
			suspected_current = 1  # Monster still alive, estimate was too low
		var percent = (float(suspected_current) / float(suspected_max)) * 100.0

		if fill:
			animate_hp_bar_change(fill, percent, false)
		if hp_label:
			if is_estimate:
				hp_label.text = "~%d/%d" % [suspected_current, suspected_max]
			else:
				hp_label.text = "%d/%d" % [suspected_current, suspected_max]
	else:
		# No knowledge at all - show unknown
		if fill:
			animate_hp_bar_change(fill, 100.0, false)
		if hp_label:
			hp_label.text = "???"

func show_enemy_hp_bar(show: bool):
	if enemy_health_bar:
		enemy_health_bar.visible = show

func record_enemy_defeated(enemy_name: String, enemy_level: int, total_damage: int):
	"""Record enemy defeat and update known HP.

	If Analyze was used this combat, store the actual max HP revealed by Analyze.
	Otherwise, use discovery system: known HP = damage dealt, and can only go DOWN.
	Uses base monster name so variants share HP knowledge with the base type."""
	var base_name = _get_base_monster_name(enemy_name)
	var enemy_key = "%s_%d" % [base_name, enemy_level]
	var hp_to_store: int

	# If Analyze revealed actual max HP, use that (player learned the true HP)
	if analyze_revealed_max_hp > 0:
		hp_to_store = analyze_revealed_max_hp
		# Analyze gives exact HP, so always store it (replaces any previous knowledge)
		known_enemy_hp[enemy_key] = hp_to_store
	else:
		# Normal discovery: known HP = damage dealt (includes overkill)
		# Known HP can only go DOWN - if player defeats with less damage, we learn actual HP is lower
		hp_to_store = total_damage
		if known_enemy_hp.has(enemy_key):
			var old_known = known_enemy_hp[enemy_key]
			known_enemy_hp[enemy_key] = mini(old_known, total_damage)
		else:
			known_enemy_hp[enemy_key] = total_damage

	# Also store by monster name only for level-based estimation
	var monster_key = "monster_%s" % base_name
	if not known_enemy_hp.has(monster_key):
		known_enemy_hp[monster_key] = {}

	# Same logic for the level-based tracking
	if analyze_revealed_max_hp > 0:
		# Analyze gives exact HP
		known_enemy_hp[monster_key][enemy_level] = hp_to_store
	elif known_enemy_hp[monster_key].has(enemy_level):
		var old_known = known_enemy_hp[monster_key][enemy_level]
		known_enemy_hp[monster_key][enemy_level] = mini(old_known, total_damage)
	else:
		known_enemy_hp[monster_key][enemy_level] = total_damage

func _get_base_monster_name(monster_name: String) -> String:
	"""Strip variant prefixes from monster name to get the base type.
	Used for tracking unique monster types discovered."""
	# Known variant prefixes (monster ability variants)
	var variant_prefixes = [
		"Corrosive ", "Sundering ", "Shield Guardian ", "Weapon Master ", "Gem Bearer ",
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
	Uses base monster name so variants share knowledge with base type.
	Returns 0 if no estimate available."""
	var base_name = _get_base_monster_name(enemy_name)
	# First check exact match
	var enemy_key = "%s_%d" % [base_name, enemy_level]
	if known_enemy_hp.has(enemy_key):
		return known_enemy_hp[enemy_key]

	# Check if we have any data for this monster type
	var monster_key = "monster_%s" % base_name
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
			# Scale HP estimate using tiered scaling (matching monster_database.gd)
			# Monster HP scales with tiered percentages per level
			var known_scale = _calculate_tiered_stat_scale(best_level)
			var target_scale = _calculate_tiered_stat_scale(enemy_level)
			# Ratio of scales gives us the multiplier
			var scale_ratio = target_scale / known_scale if known_scale > 0 else 1.0
			return int(best_hp * scale_ratio)

	return 0

func _calculate_tiered_stat_scale(level: int) -> float:
	"""Calculate stat scaling using tiered percentages (matching monster_database.gd).
	Used for HP estimation."""
	var scale = 1.0

	# Tier 1: Levels 1-100 at 12% per level
	if level > 1:
		var levels_in_tier = min(level, 100) - 1
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.12

	# Tier 2: Levels 101-500 at 5% per level
	if level > 100:
		var levels_in_tier = min(level, 500) - 100
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.05

	# Tier 3: Levels 501-2000 at 2% per level
	if level > 500:
		var levels_in_tier = min(level, 2000) - 500
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.02

	# Tier 4: Levels 2000+ at 0.5% per level
	if level > 2000:
		var levels_in_tier = level - 2000
		scale += levels_in_tier * 0.005

	return scale

func parse_monster_healing(msg: String) -> int:
	"""Parse healing done BY the monster (life steal, regeneration).
	This should be subtracted from damage_dealt_to_current_enemy to fix HP bar."""
	# First strip all BBCode tags to get clean text
	var clean_msg = msg
	var bbcode_regex = RegEx.new()
	bbcode_regex.compile("\\[/?[a-z]+[^\\]]*\\]")
	clean_msg = bbcode_regex.sub(clean_msg, "", true)

	var regex = RegEx.new()

	# Life steal: "The X drains Y life from you!"
	regex.compile("drains (\\d+) life")
	var result = regex.search(clean_msg)
	if result:
		return int(result.get_string(1))

	# Regeneration: "The X regenerates Y HP!"
	regex.compile("regenerates (\\d+) HP")
	result = regex.search(clean_msg)
	if result:
		return int(result.get_string(1))

	return 0

func parse_damage_dealt(msg: String) -> int:
	"""Parse damage dealt by PLAYER (and allies) to enemy from combat messages.
	Handles various formats with color codes. Excludes monster damage to player."""
	# First strip all BBCode tags to get clean text
	var clean_msg = msg
	var bbcode_regex = RegEx.new()
	bbcode_regex.compile("\\[/?[a-z]+[^\\]]*\\]")
	clean_msg = bbcode_regex.sub(clean_msg, "", true)

	# EXCLUDE damage messages that are NOT damage to the enemy
	# Monster attacks: "The X attacks and deals", "X hits N times for", "to you"
	# Self-damage: "backfires", "burns you", "yourself", "Bleeding deals"
	if "attacks and deals" in clean_msg:
		return 0
	if "hits" in clean_msg and "times for" in clean_msg:
		return 0
	if "to you" in clean_msg:
		return 0
	# Player poison: "Poison deals X damage! (Y turns)" - no "to the"
	# Monster poison: "Poison deals X damage to the Wolf!" - HAS "to the" (DO track)
	if "Poison deals" in clean_msg and "to the" not in clean_msg:
		return 0
	if "death curse deals" in clean_msg:
		return 0
	# Monster reflect ability: "The Wolf reflects X damage!" (damage to player)
	# Player gear reflect: "Retribution gear reflects X damage!" (damage to monster - DO track)
	if "reflects" in clean_msg and "damage" in clean_msg and not "gear reflects" in clean_msg:
		return 0
	if "backfires" in clean_msg:
		return 0
	if "burns you" in clean_msg:
		return 0
	if "yourself" in clean_msg:
		return 0
	if "Bleeding deals" in clean_msg:
		return 0
	# Thorns deal damage to player, not monster
	if "Thorns deal" in clean_msg:
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
	# Also matches monster poison: "Poison deals X damage to the Wolf!"
	regex.compile("deals (\\d+) damage")
	result = regex.search(clean_msg)
	if result:
		return int(result.get_string(1))

	# Bonus damage: companion crits, shocking proc, execute proc
	# e.g., "Shocking strikes for 50 bonus damage!", "Execute strikes for 30 bonus damage!"
	regex.compile("for (\\d+) bonus damage")
	result = regex.search(clean_msg)
	if result:
		return int(result.get_string(1))

	# Total damage: companion multi-hit abilities
	# e.g., "Wolf uses Fury Swipes! 3 hits for 90 total damage!"
	regex.compile("for (\\d+) total damage")
	result = regex.search(clean_msg)
	if result:
		return int(result.get_string(1))

	# Standard "for X damage" pattern (basic companion attack, exploit, etc.)
	regex.compile("for (\\d+) damage")
	result = regex.search(clean_msg)
	if result:
		return int(result.get_string(1))

	# Equipment reflect: "Retribution gear reflects X damage!"
	regex.compile("reflects (\\d+) damage")
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
			account_id = message.get("account_id", "")
			last_username = username
			_save_connection_settings()
			display_game("[color=#00FF00]Logged in as %s[/color]" % username)
			# Request house data before going to house screen
			send_to_server({"type": "house_request"})
			game_state = GameState.HOUSE_SCREEN

		"login_failed":
			if login_status:
				login_status.text = "[color=#FF0000]%s[/color]" % message.get("reason", "Login failed")

		"house_data":
			house_data = message.get("house", {})
			house_mode = "main"
			pending_house_action = ""
			house_storage_page = 0
			house_storage_withdraw_items = []
			house_checkout_companion_slot = -1
			house_storage_discard_index = -1
			house_storage_register_index = -1
			house_unregister_companion_slot = -1
			house_interactable_at = ""
			_init_house_player_position()
			show_house_panel()
			display_house_main()
			update_action_bar()

		"house_update":
			# Update house data without changing UI state
			house_data = message.get("house", {})
			if game_state == GameState.HOUSE_SCREEN:
				if house_mode == "storage":
					display_house_storage()
				elif house_mode == "companions":
					display_house_companions()
				elif house_mode == "upgrades":
					display_house_upgrades()
				else:
					display_house_main()
				update_action_bar()

		"character_list":
			character_list = message.get("characters", [])
			can_create_character = message.get("can_create", true)
			# Don't switch to character select if we're on death screen or house screen
			if game_state == GameState.DEAD or game_state == GameState.HOUSE_SCREEN:
				return
			# Clear any stale state from death or previous session
			has_character = false
			in_combat = false
			character_data = {}
			show_character_select_panel()

		"character_loaded":
			# Reset any stale state from previous character
			dungeon_mode = false
			dungeon_data = {}
			dungeon_floor_grid = []
			in_combat = false
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
			update_companion_art_overlay()
			display_game("[color=#00FF00]%s[/color]" % message.get("message", ""))
			display_title_holders(message.get("title_holders", []))
			display_character_status()
			request_player_list()

		"character_created":
			# Reset any stale state from previous character
			dungeon_mode = false
			dungeon_data = {}
			dungeon_floor_grid = []
			in_combat = false
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
			# Reset dungeon state
			dungeon_mode = false
			dungeon_data = {}
			dungeon_floor_grid = []
			dungeon_available = []
			dungeon_list_mode = false
			# Go back to house screen instead of character select
			send_to_server({"type": "house_request"})
			game_state = GameState.HOUSE_SCREEN
			update_action_bar()
			show_enemy_hp_bar(false)
			display_game("[color=#00FF00]%s[/color]" % message.get("message", "Logged out of character"))

		"logout_account_success":
			has_character = false
			in_combat = false
			character_data = {}
			character_list = []
			username = ""
			account_id = ""
			house_data = {}
			house_mode = ""
			# Reset dungeon state
			dungeon_mode = false
			dungeon_data = {}
			dungeon_floor_grid = []
			dungeon_available = []
			dungeon_list_mode = false
			# Disconnect and reconnect for clean state
			# (server's stale connection check would kill the unauthenticated peer)
			connection.disconnect_from_host()
			connected = false
			buffer = ""
			connection = StreamPeerTCP.new()
			game_state = GameState.LOGIN_SCREEN
			show_login_panel()
			update_action_bar()
			show_enemy_hp_bar(false)
			_clear_character_hud()
			display_game("[color=#00FF00]%s[/color]" % message.get("message", "Logged out"))
			connect_to_server()

		"permadeath":
			game_state = GameState.DEAD
			in_combat = false
			last_death_message = message.duplicate(true)
			play_death_sound()
			# Show final HP (can be negative) on the bar - visual fill clamped at 0%
			var final_hp = message.get("player_hp", 0)
			var final_max_hp = message.get("player_max_hp", character_data.get("total_max_hp", character_data.get("max_hp", 1)))
			character_data["current_hp"] = final_hp
			character_data["total_max_hp"] = final_max_hp
			update_player_hp_bar()
			has_character = false
			character_data = {}
			hide_all_panels()
			hide_companion_art_overlay()
			display_death_screen(message)
			update_action_bar()
			show_enemy_hp_bar(false)

		"leaderboard":
			update_leaderboard_display(message.get("entries", []))

		"monster_kills_leaderboard":
			update_monster_kills_display(message.get("entries", []))

		"trophy_leaderboard":
			update_trophy_leaderboard_display(message.get("entries", []))

		"leaderboard_top5":
			# A player entered the Hall of Heroes (top 5) - show in chat only
			var char_name = message.get("character_name", "Unknown")
			var level = message.get("level", 1)
			var hero_rank = message.get("rank", 1)
			display_chat("[color=#FFD700]*** %s (Level %d) has entered the Hall of Heroes at #%d! ***[/color]" % [char_name, level, hero_rank])
			play_top5_sound()

		"corpse_looted":
			# Display loot results from looting a corpse
			game_output.clear()
			var loot_msg = message.get("message", "Corpse looted.")
			display_game(loot_msg)
			# Reset corpse state
			at_corpse = false
			corpse_info = {}
			pending_corpse_loot = {}
			update_action_bar()

		"player_list":
			update_online_players(message.get("players", []))

		"examine_result":
			# Check if this was triggered by click on player list
			var examined_name = message.get("name", "")
			if pending_player_info_request != "" and examined_name.to_lower() == pending_player_info_request.to_lower():
				show_player_info_popup(message)
				pending_player_info_request = ""
			else:
				display_examine_result(message)

		"location":
			# Don't update map when in dungeon - dungeon has its own map display
			if not dungeon_mode:
				var desc = message.get("description", "")
				# Don't clear game_output on location updates - map is displayed separately
				# Only update the map display panel
				update_map(desc)
			# Update water/fishing location status
			var was_at_water = at_water
			at_water = message.get("at_water", false)
			fishing_water_type = message.get("water_type", "shallow")
			# Cancel fishing if we moved away from water
			if was_at_water and not at_water and fishing_mode:
				end_fishing(false, "You moved away from the water.")
			# Update ore/mining location status
			var was_at_ore = at_ore_deposit
			at_ore_deposit = message.get("at_ore_deposit", false)
			ore_tier = message.get("ore_tier", 1)
			# Cancel mining if we moved away from ore
			if was_at_ore and not at_ore_deposit and mining_mode:
				end_mining(false, "You moved away from the ore deposit.")
			# Update forest/logging location status
			var was_at_forest = at_dense_forest
			at_dense_forest = message.get("at_dense_forest", false)
			wood_tier = message.get("wood_tier", 1)
			# Cancel logging if we moved away from forest
			if was_at_forest and not at_dense_forest and logging_mode:
				end_logging(false, "You moved away from the trees.")
			# Update dungeon entrance status
			var was_at_dungeon = at_dungeon_entrance
			at_dungeon_entrance = message.get("at_dungeon", false)
			dungeon_entrance_info = message.get("dungeon_info", {})
			# Display dungeon info when arriving at a dungeon entrance
			if at_dungeon_entrance and not was_at_dungeon and not dungeon_entrance_info.is_empty():
				_display_dungeon_entrance_info()
			# Update corpse status
			var was_at_corpse = at_corpse
			at_corpse = message.get("at_corpse", false)
			corpse_info = message.get("corpse_info", {})
			# Display corpse info when arriving at a corpse
			if at_corpse and not was_at_corpse and not corpse_info.is_empty():
				_display_corpse_info()
			# Update action bar if any location status changed
			if was_at_water != at_water or was_at_dungeon != at_dungeon_entrance or was_at_ore != at_ore_deposit or was_at_forest != at_dense_forest or was_at_corpse != at_corpse:
				update_action_bar()

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

		"private_message":
			# Received a whisper from another player
			var sender = message.get("sender", "Unknown")
			var sender_name = message.get("sender_name", sender)  # Plain name for reply
			var text = message.get("message", "")
			last_whisper_from = sender_name
			display_chat("[color=#FF69B4][From %s]:[/color] %s" % [sender, text])
			# Play notification sound
			play_whisper_notification()

		"private_message_sent":
			# Confirmation that our whisper was sent
			var target = message.get("target", "Unknown")
			var text = message.get("message", "")
			display_chat("[color=#FF69B4][To %s]:[/color] %s" % [target, text])

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
			# Sound triggers for text messages
			var text_lower = text_msg.to_lower()
			if "hp restored" in text_lower or "healed" in text_lower or "recovered" in text_lower:
				play_player_healed_sound()
			elif "gem" in text_lower and ("+" in text_msg or "gained" in text_lower or "found" in text_lower):
				play_gem_gain_sound()
			elif "egg" in text_lower and ("found" in text_lower or "dropped" in text_lower):
				play_egg_found_sound()

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

		"npc_encounter":
			# NPC encounters (tax collector, etc.) require acknowledgment before continuing
			game_output.clear()
			# Display appropriate art based on NPC type
			var npc_type = message.get("npc_type", "")
			if npc_type == "tax_collector":
				var tax_art = _get_trader_art().get_tax_collector_art()
				display_game(tax_art)
				display_game("")
			var npc_msg = message.get("message", "An NPC approaches!")
			display_game(npc_msg)
			display_game("")
			display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
			# Update character data (gold/stats may have changed)
			if message.has("character"):
				character_data = message.character
				update_player_level()
				update_player_hp_bar()
				update_resource_bar()
				update_player_xp_bar()
				update_currency_display()
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
				update_companion_art_overlay()
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
							var is_consumable = _is_consumable_type(itm_type) or "potion" in itm_type or "elixir" in itm_type
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

								# Get bonus summary and slot abbreviation (matching Backpack format)
								var bonus_text = _get_item_bonus_summary(item)
								var slot_abbr = _get_slot_abbreviation(item_type)

								# Comparison with equipped item - arrow on left, stats on right
								var compare_arrow = ""
								var compare_text = ""
								var slot = _get_slot_for_item_type(item_type)
								if slot != "":
									var equipped_item = equipped.get(slot)
									compare_arrow = _get_compare_arrow(item, equipped_item)
									var diff_parts = _get_item_comparison_parts(item, equipped_item)
									if diff_parts.size() > 0:
										compare_text = " [%s]" % ", ".join(diff_parts)

								# Display matching Backpack format
								display_game("[%d] %s [color=%s]%s[/color] Lv%d %s %s%s" % [j + 1, compare_arrow, color, item_name, level, bonus_text, slot_abbr, compare_text])
							display_game("[color=#FFD700]%s to equip another item, or [%s] to go back:[/color]" % [get_selection_keys_text(equippable_items.size()), get_action_key_name(0)])
						else:
							display_game("[color=#808080]No more items to equip.[/color]")
							pending_inventory_action = ""
							update_action_bar()  # Update to show main inventory menu with Back option
					elif pending_inventory_action == "unequip_item":
						_show_unequip_slots()
					elif pending_inventory_action == "awaiting_salvage_result":
						# Salvage result will be shown via "text" message - don't redisplay inventory yet
						# Clear the pending action but stay in inventory mode
						pending_inventory_action = ""
						# Show a prompt to continue
						display_game("")
						display_game("[color=#808080]Press [%s] for Backpack or [%s] to exit.[/color]" % [get_action_key_name(0), get_action_key_name(1)])
						update_action_bar()
					elif pending_inventory_action == "lock_item":
						# Lock mode - refresh inventory to show updated lock indicators
						var inv = character_data.get("inventory", [])
						display_inventory()
						display_game("[color=#FFD700]%s to lock/unlock another item, or [%s] to go back:[/color]" % [get_selection_keys_text(max(1, inv.size())), get_action_key_name(0)])
						update_action_bar()
					elif pending_inventory_action == "viewing_materials":
						# Materials view - don't redisplay inventory, keep showing materials
						pass
					else:
						display_inventory()
						update_action_bar()
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
				# Refresh companions display if in companions mode (after activation/dismissal)
				if companions_mode:
					display_companions()
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
				# Play announcement sound
				play_server_announcement()

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
			# Update cloak state and action bar if cloak dropped
			if message.get("effect", "") == "cloak_dropped":
				character_data["cloak_active"] = false
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
			# Display ability management screen and refresh action bar
			display_ability_menu()
			update_action_bar()

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
			# If pending_continue is active (e.g., egg hatching celebration), queue combat for after
			if pending_continue:
				queued_combat_message = message.duplicate(true)
				return
			_process_combat_start(message)

		"combat_message":
			var combat_msg = message.get("message", "")
			# Add visual flair to damage messages
			var enhanced_msg = _enhance_combat_message(combat_msg)
			display_game(enhanced_msg)
			# Stop any ongoing animation when we receive combat feedback
			stop_combat_animation()

			# Trigger combat sounds based on message content
			_trigger_combat_sounds(combat_msg)

			# Loot vanish detection (failed special monster drops)
			var lower_msg = combat_msg.to_lower()
			if "shatters on death" in lower_msg or "crumbles to dust" in lower_msg or "fades away" in lower_msg:
				play_loot_vanish_sound()

			# Trigger shake animations for combat actions
			# Companion attack: "Your X attacks for" (cyan #00FFFF)
			if "Your " in combat_msg and " attacks" in combat_msg:
				shake_companion_art()
			# Companion ability use: "X uses" or "X's" ability messages (cyan #00FFFF)
			elif "#00FFFF" in combat_msg and (" uses " in combat_msg or "'s " in combat_msg):
				shake_companion_art()
			# Monster attack: "The X attacks" (red #FF4444 or #FF0000)
			if "The " in combat_msg and " attacks" in combat_msg:
				shake_game_output()
			# Monster special attacks: "strikes" patterns
			elif "strikes" in combat_msg.to_lower() and ("The " in combat_msg or "#FF" in combat_msg):
				shake_game_output()

			var damage = parse_damage_dealt(combat_msg)
			if damage > 0:
				damage_dealt_to_current_enemy += damage
				update_enemy_hp_bar(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy, current_enemy_hp, current_enemy_max_hp)

			# Track monster healing (life steal, regeneration) to fix HP bar estimate
			var monster_heal = parse_monster_healing(combat_msg)
			if monster_heal > 0:
				damage_dealt_to_current_enemy = max(0, damage_dealt_to_current_enemy - monster_heal)
				update_enemy_hp_bar(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy, current_enemy_hp, current_enemy_max_hp)

		"enemy_hp_revealed":
			# Analyze ability revealed enemy HP - update the health bar for THIS combat
			# Store the revealed max HP so we can use it when player defeats the monster
			var max_hp = message.get("max_hp", 0)
			var current_hp = message.get("current_hp", max_hp)
			if max_hp > 0 and current_enemy_name != "":
				# Store revealed HP as current combat values for display
				current_enemy_hp = current_hp
				current_enemy_max_hp = max_hp
				# Mark that Analyze revealed the true max HP - will be stored as known HP on defeat
				analyze_revealed_max_hp = max_hp
				# Calculate damage dealt from revealed HP
				damage_dealt_to_current_enemy = max_hp - current_hp
				update_enemy_hp_bar(current_enemy_name, current_enemy_level, damage_dealt_to_current_enemy, current_enemy_hp, current_enemy_max_hp)

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
			stop_low_hp_pulse()  # Stop any HP bar animations
			update_player_hp_bar()  # Refresh HP bar to hide shield

			if message.get("victory", false):
				# Record defeat if damage was dealt OR if Analyze revealed HP (e.g., Outsmart victory after Analyze)
				if damage_dealt_to_current_enemy > 0 or analyze_revealed_max_hp > 0:
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

					# Check for egg drops
					var all_drops = message.get("flock_drops", [])
					for drop_msg in all_drops:
						if "egg" in drop_msg.to_lower():
							play_egg_found_sound()
							break

					# Check for gem gains
					var total_gems = message.get("total_gems", 0)
					if total_gems > 0:
						play_gem_gain_sound()

					# Require continue press so player can read loot before display refreshes
					display_game("")
					display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
					pending_continue = true
					if dungeon_mode:
						pending_dungeon_continue = true
			elif message.get("monster_fled", false):
				# Monster fled (Coward ability or Shrieker summon)
				if message.has("character"):
					character_data = message.character
					update_player_level()
					update_player_hp_bar()
					update_resource_bar()
					update_player_xp_bar()
					update_currency_display()
				# Check if another monster is incoming (Shrieker summoned replacement)
				if message.get("flock_incoming", false):
					flock_pending = true
					var flock_msg = message.get("flock_message", "[color=#FF4444]Another enemy approaches![/color]")
					display_game(flock_msg)
					display_game("[color=#FFD700]Press [%s] to continue...[/color]" % get_action_key_name(0))
				else:
					display_game("[color=#FFD700]The enemy fled! No loot earned.[/color]")
					pending_continue = true
					if dungeon_mode:
						pending_dungeon_continue = true
					display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
			elif message.get("fled", false):
				# Player fled - reset combat XP tracking but keep previous XP gain highlight
				xp_before_combat = 0
				# Update position if server moved us
				if message.has("new_x") and message.has("new_y"):
					character_data["x"] = message.new_x
					character_data["y"] = message.new_y
					display_game("[color=#FFD700]You fled to (%d, %d)![/color]" % [message.new_x, message.new_y])
				else:
					display_game("[color=#FFD700]You escaped from combat![/color]")
				pending_continue = true
				if dungeon_mode:
					pending_dungeon_continue = true
				display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))
			else:
				# Defeat handled by permadeath message
				pass

			update_action_bar()
			show_enemy_hp_bar(false)
			current_enemy_name = ""
			current_enemy_level = 0
			current_enemy_is_rare_variant = false
			damage_dealt_to_current_enemy = 0
			analyze_revealed_max_hp = -1  # Reset Analyze flag

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
				# Initialize key press state for any currently-held keys to prevent
				# the key used to activate the scroll from immediately selecting a monster
				for i in range(9):  # Monster select uses keys 1-9
					if is_item_select_key_pressed(i):
						set_meta("monsterselectkey_%d_pressed" % i, true)
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
				# Initialize key press state for any currently-held keys to prevent
				# the key used to activate the scroll from immediately selecting an option
				for i in range(5):
					if is_item_select_key_pressed(i):
						set_meta("targetfarmkey_%d_pressed" % i, true)
				display_game(message.get("message", "Choose a trait to hunt:"))
				display_target_farm_options()
				update_action_bar()

		"home_stone_select":
			# Home Stone used - show selection
			home_stone_type = message.get("stone_type", "")
			home_stone_options = message.get("options", [])
			if home_stone_options.size() > 0:
				# Exit inventory mode
				inventory_mode = false
				pending_inventory_action = ""
				selected_item_index = -1
				home_stone_mode = true
				# Initialize key press state for any currently-held keys
				for i in range(home_stone_options.size()):
					if is_item_select_key_pressed(i):
						set_meta("homestonekey_%d_pressed" % i, true)
				game_output.clear()
				display_game(message.get("message", "Choose a target:"))
				_display_home_stone_options()
				update_action_bar()

		"merchant_start":
			at_merchant = true
			merchant_data = message.get("merchant", {})
			# Display trader art for wandering merchants (they have destination)
			if merchant_data.has("destination") and merchant_data.get("destination", "") != "":
				game_output.clear()
				# Use merchant hash for consistent art per merchant
				var merchant_hash = merchant_data.get("hash", randi())
				var trader_art = _get_trader_art().get_trader_art_for_id(merchant_hash)
				display_game(trader_art)
				display_game("")
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

		"watch_combat_start":
			handle_watch_combat_start(message)

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

		"summon_request":
			# Handle incoming summon request
			pending_summon_from = message.get("from_name", "")
			pending_summon_location = Vector2i(message.get("x", 0), message.get("y", 0))
			display_game("")
			display_game("[color=#00FFFF]═══════════════════════════════════════[/color]")
			display_game("[color=#C0C0C0]SUMMON REQUEST[/color]")
			display_game("[color=#FFD700]%s (Jarl) wants to summon you to (%d, %d)[/color]" % [pending_summon_from, pending_summon_location.x, pending_summon_location.y])
			display_game("[color=#808080][Q] Accept  |  [W] Decline[/color]")
			display_game("[color=#00FFFF]═══════════════════════════════════════[/color]")
			update_action_bar()

		# Trading system messages
		"trade_request_received":
			pending_trade_request = message.get("from_name", "")
			display_game("")
			display_game("[color=#00FFFF]═══════════════════════════════════════[/color]")
			display_game("[color=#FFD700]TRADE REQUEST[/color]")
			display_game("[color=#00FFFF]%s wants to trade with you.[/color]" % pending_trade_request)
			display_game("[color=#808080][Q] Accept  |  [W] Decline[/color]")
			display_game("[color=#00FFFF]═══════════════════════════════════════[/color]")
			update_action_bar()

		"trade_started":
			in_trade = true
			trade_partner_name = message.get("partner_name", "")
			trade_partner_class = message.get("partner_class", "")
			trade_my_items = []
			trade_partner_items = []
			trade_my_ready = false
			trade_partner_ready = false
			pending_trade_request = ""
			trade_pending_add = false
			display_game("")
			display_game("[color=#00FF00]Trade started with %s![/color]" % trade_partner_name)
			display_trade_window()
			update_action_bar()

		"trade_update":
			trade_partner_name = message.get("partner_name", trade_partner_name)
			trade_partner_class = message.get("partner_class", trade_partner_class)
			trade_my_items = message.get("my_items", [])
			trade_partner_items = message.get("partner_items", [])
			trade_my_companions = message.get("my_companions", [])
			trade_my_companions_data = message.get("my_companions_data", [])
			trade_partner_companions = message.get("partner_companions", [])
			trade_my_eggs = message.get("my_eggs", [])
			trade_my_eggs_data = message.get("my_eggs_data", [])
			trade_partner_eggs = message.get("partner_eggs", [])
			trade_my_ready = message.get("my_ready", false)
			trade_partner_ready = message.get("partner_ready", false)
			if in_trade:
				display_trade_window()
				update_action_bar()

		"trade_cancelled":
			var reason = message.get("reason", "Trade cancelled.")
			display_game("[color=#FF8800]%s[/color]" % reason)
			_exit_trade_mode()
			update_action_bar()

		"trade_complete":
			var received = message.get("received_count", 0)
			var gave = message.get("gave_count", 0)
			var received_items = message.get("received_items", received)
			var received_companions = message.get("received_companions", 0)
			var received_eggs = message.get("received_eggs", 0)
			display_game("")
			display_game("[color=#00FF00]═══════════════════════════════════════[/color]")
			display_game("[color=#FFD700]TRADE COMPLETE![/color]")
			var breakdown = []
			if received_items > 0:
				breakdown.append("%d item(s)" % received_items)
			if received_companions > 0:
				breakdown.append("%d companion(s)" % received_companions)
			if received_eggs > 0:
				breakdown.append("%d egg(s)" % received_eggs)
			if breakdown.is_empty():
				display_game("[color=#00FF00]You gave %d thing(s) and received nothing.[/color]" % gave)
			else:
				display_game("[color=#00FF00]You gave %d thing(s) and received %s.[/color]" % [gave, ", ".join(breakdown)])
			display_game("[color=#00FF00]═══════════════════════════════════════[/color]")
			_exit_trade_mode()
			update_action_bar()

		# Wandering NPC encounter messages
		"blacksmith_encounter":
			handle_blacksmith_encounter(message)

		"blacksmith_done":
			pending_blacksmith = false
			blacksmith_items = []
			blacksmith_upgrade_mode = ""
			blacksmith_upgrade_items = []
			blacksmith_upgrade_affixes = []
			blacksmith_trader_art = ""
			update_action_bar()

		"blacksmith_upgrade_select_item":
			handle_blacksmith_upgrade_select_item(message)

		"blacksmith_upgrade_select_affix":
			handle_blacksmith_upgrade_select_affix(message)

		"healer_encounter":
			handle_healer_encounter(message)

		"healer_done":
			pending_healer = false
			healer_costs = {}
			update_action_bar()

		"fish_start":
			handle_fish_start(message)

		"fish_result":
			handle_fish_result(message)

		"mine_start":
			handle_mine_start(message)

		"mine_result":
			handle_mine_result(message)

		"log_start":
			handle_log_start(message)

		"log_result":
			handle_log_result(message)

		"craft_list":
			handle_craft_list(message)

		"craft_result":
			handle_craft_result(message)

		"dungeon_list":
			handle_dungeon_list(message)

		"dungeon_level_warning":
			handle_dungeon_level_warning(message)

		"dungeon_state":
			handle_dungeon_state(message)

		"dungeon_treasure":
			handle_dungeon_treasure(message)

		"dungeon_floor_change":
			handle_dungeon_floor_change(message)

		"dungeon_complete":
			handle_dungeon_complete(message)

		"dungeon_exit":
			handle_dungeon_exit(message)

		"egg_hatched":
			handle_egg_hatched(message)

func _process_combat_start(message: Dictionary):
	"""Process a combat_start message - separated out so queued combat can call it"""
	# Release input field focus immediately so ability hotkeys work
	# This prevents the bug where typing in chat when combat starts causes abilities to be sent as text
	if input_field and input_field.has_focus():
		input_field.clear()
		input_field.release_focus()

	in_combat = true
	flock_pending = false
	flock_monster_name = ""
	combat_item_mode = false
	combat_outsmart_failed = false  # Reset outsmart for new combat
	more_mode = false
	companions_mode = false
	pending_continue = false  # Clear any pending continue from previous combat
	pending_dungeon_continue = false
	last_known_hp_before_round = character_data.get("current_hp", 0)  # Track HP for danger sound
	last_enemy_hp_percent = 100.0  # Reset enemy HP tracking for animations
	update_action_bar()
	update_companion_art_overlay()  # Show companion during combat

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
			var local_art = _get_monster_art().get_bordered_art_with_font(monster_base_name, ui_scale_monster_art)

			# Recolor ASCII art for visual variety (works for both flock and regular encounters)
			var art_color = message.get("flock_art_color", "")  # Flock encounters use flock_art_color
			if art_color == "":
				art_color = message.get("art_color", "")  # Regular encounters use art_color
			if art_color != "":
				local_art = _recolor_ascii_art(local_art, art_color)

			# Build encounter text with traits
			var encounter_text = _build_encounter_text(combat_state)
			# For flock, prepend the "Another X appears!" message with pack number
			if message.get("is_flock", false):
				var flock_count = message.get("flock_count", 1)
				display_msg = "[color=#FF4444]Another %s appears! (Pack #%d)[/color]\n[center]%s[/center]\n%s" % [monster_name, flock_count + 1, local_art, encounter_text]
			else:
				display_msg = "[center]" + local_art + "[/center]\n" + encounter_text
	display_game(display_msg)

	# combat_state already fetched above for client-side art
	current_enemy_name = combat_state.get("monster_name", "Enemy")
	current_enemy_level = combat_state.get("monster_level", 1)
	current_enemy_color = combat_state.get("monster_name_color", "#FFFFFF")
	current_enemy_abilities = combat_state.get("monster_abilities", [])
	current_enemy_is_rare_variant = combat_state.get("is_rare_variant", false)
	damage_dealt_to_current_enemy = 0
	analyze_revealed_max_hp = -1  # Reset Analyze flag for new combat
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

	# Check for bug report mode (waiting for optional description)
	if bug_report_mode:
		bug_report_mode = false
		input_field.placeholder_text = ""
		generate_bug_report(text)
		return

	# Commands
	# Reduced command set - most actions available via action bar
	var command_keywords = ["help", "clear", "who", "players", "examine", "ex", "watch", "unwatch", "bug", "report", "search", "find", "trade", "companion", "pet", "donate", "crucible", "whisper", "w", "msg", "tell", "reply", "r", "fish", "craft", "dungeons", "dungeon", "materials", "mats", "debughatch"]
	# Combat commands as typed fallback (action bar is preferred)
	var combat_keywords = ["attack", "a", "flee", "f", "item", "i",
		# Mage abilities
		"magic_bolt", "bolt", "heal", "shield", "cloak", "blast", "forcefield", "teleport", "meteor",
		# Warrior abilities
		"power_strike", "strike", "war_cry", "warcry", "shield_bash", "bash", "cleave", "berserk", "iron_skin", "ironskin", "devastate",
		# Trickster abilities
		"analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "outsmart", "gambit", "sabotage", "perfect_heist", "heist"]
	var first_word = text.split(" ", false)[0].to_lower() if text.length() > 0 else ""
	var has_slash = first_word.begins_with("/")
	if has_slash:
		first_word = first_word.substr(1)
	# Commands require "/" prefix; combat keywords work without "/" when in combat
	var is_command = has_slash and first_word in command_keywords
	var is_combat_command = first_word in combat_keywords

	# In combat, bare combat keywords work (no chat in combat)
	if in_combat and is_combat_command:
		display_game("[color=#00FFFF]> %s[/color]" % text)
		process_command(text)
		return

	# Not a slash command → send to chat
	if connected and has_character and not is_command:
		display_chat("[color=#FFD700]%s:[/color] %s" % [username, text])
		send_to_server({"type": "chat", "message": text})
		return

	# Slash command → process it
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

func display_item_details(item: Dictionary, source: String, owner_class: String = ""):
	"""Display detailed information about an item.
	owner_class is used for themed display - empty means current player's class."""
	var item_type = item.get("type", "unknown")
	var rarity = item.get("rarity", "common")
	var level = item.get("level", 1)
	var value = item.get("value", 0)
	var rarity_color = _get_item_rarity_color(rarity)
	var is_consumable = item.get("is_consumable", false)
	var is_title_item = item.get("is_title_item", false)

	# Use themed name based on owner's class (or current player if not specified)
	var display_class = owner_class if owner_class != "" else character_data.get("class", "")
	var themed_name = _get_themed_item_name(item, display_class)

	display_game("")
	display_game("[color=%s]===== %s =====[/color]" % [rarity_color, themed_name])
	display_game("[color=#808080]%s[/color]" % source.capitalize())
	display_game("")

	# Title items show description and instructions instead of stats
	if is_title_item:
		display_game("[color=#00FFFF]Type:[/color] Title Quest Item")
		display_game("[color=#00FFFF]Rarity:[/color] [color=%s]%s[/color]" % [rarity_color, rarity.capitalize()])
		display_game("")
		var desc = item.get("description", "This is a special item.")
		display_game("[color=#E6CC80]%s[/color]" % desc)
		display_game("")
		display_game("[color=#808080]This item cannot be equipped or sold.[/color]")
		display_game("")
		return

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
		# Show wear/condition for equipment
		var wear = item.get("wear", 0)
		var condition_text = _get_condition_string(wear)
		var condition_color = _get_condition_color(wear)
		display_game("[color=#00FFFF]Condition:[/color] [color=%s]%s (%d%% wear)[/color]" % [condition_color, condition_text, wear])

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
			var equipped_themed = _get_themed_item_name(equipped_item, display_class)
			display_game("[color=#E6CC80]Compared to equipped %s:[/color]" % equipped_themed)
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
	var item_type = item.get("type", "unknown")
	var rarity = item.get("rarity", "common")
	var level = item.get("level", 1)
	var rarity_color = _get_item_rarity_color(rarity)
	var player_class = character_data.get("class", "")
	var themed_name = _get_themed_item_name(item, player_class)

	display_game("")
	display_game("[color=#FFD700]===== EQUIP ITEM =====[/color]")
	display_game("")
	display_game("[color=%s]%s[/color]" % [rarity_color, themed_name])
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
			var equipped_themed = _get_themed_item_name(equipped_item, player_class)
			display_game("[color=#E6CC80]Compared to equipped %s:[/color]" % equipped_themed)
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
	# Home Stones
	if item_type == "home_stone_egg":
		return "Home Stone - Send an egg to your Sanctuary"
	elif item_type == "home_stone_supplies":
		return "Home Stone - Send supplies to your Sanctuary"
	elif item_type == "home_stone_equipment":
		return "Home Stone - Send equipment to your Sanctuary"
	elif item_type == "home_stone_companion":
		return "Home Stone - Register companion at your Sanctuary"
	# Scrolls
	elif "scroll" in item_type:
		return "Consumable - Magical Scroll"
	# Tomes
	elif "tome" in item_type:
		return "Consumable - Tome of Knowledge"
	# Special items
	elif item_type == "mysterious_box":
		return "Consumable - Mysterious Box"
	elif item_type == "cursed_coin":
		return "Consumable - Cursed Coin"
	elif item_type == "soul_gem":
		return "Consumable - Soul Gem"
	# Resource potions
	elif "mana" in item_type:
		return "Consumable - Mana Potion"
	elif "stamina" in item_type:
		return "Consumable - Stamina Potion"
	elif "energy" in item_type:
		return "Consumable - Energy Potion"
	# Buff potions
	elif "potion_strength" in item_type or "potion_power" in item_type:
		return "Consumable - Strength Potion"
	elif "potion_defense" in item_type or "potion_iron" in item_type:
		return "Consumable - Defense Potion"
	elif "potion_speed" in item_type or "potion_haste" in item_type:
		return "Consumable - Speed Potion"
	elif "potion_crit" in item_type:
		return "Consumable - Critical Strike Potion"
	elif "potion_lifesteal" in item_type:
		return "Consumable - Lifesteal Potion"
	# General potions/elixirs
	elif "potion" in item_type:
		return "Consumable - Healing Potion"
	elif "elixir" in item_type:
		return "Consumable - Powerful Elixir"
	# Equipment
	elif "weapon" in item_type:
		return "Weapon - Increases attack damage"
	elif "armor" in item_type:
		return "Armor - Reduces damage taken"
	elif "helm" in item_type:
		return "Helm - Head protection"
	elif "shield" in item_type:
		return "Shield - Improves defense"
	elif "boots" in item_type:
		return "Boots - Footwear"
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
	var tier_data = CONSUMABLE_TIERS.get(level, CONSUMABLE_TIERS[1]) if is_tier_value else {}

	# Health potions (potion_minor, potion_lesser, etc. or health_potion, elixir)
	if is_tier_value and (item_type == "health_potion" or item_type == "elixir" or (item_type.begins_with("potion_") and "speed" not in item_type and "strength" not in item_type and "defense" not in item_type and "power" not in item_type and "iron" not in item_type and "haste" not in item_type and "crit" not in item_type and "lifesteal" not in item_type) or item_type.begins_with("elixir_")):
		return "Restores %d HP when used" % tier_data.healing
	# Resource potions (mana/stamina/energy - all restore player's PRIMARY resource)
	elif is_tier_value and (item_type == "mana_potion" or item_type.begins_with("mana_") or item_type == "stamina_potion" or item_type.begins_with("stamina_") or item_type == "energy_potion" or item_type.begins_with("energy_")):
		# Show the player's primary resource type
		var player_class = character_data.get("class", "")
		var resource_name = "Resource"
		match player_class:
			"Wizard", "Sorcerer", "Sage":
				resource_name = "Mana"
			"Fighter", "Barbarian", "Paladin":
				resource_name = "Stamina"
			"Thief", "Ranger", "Ninja":
				resource_name = "Energy"
		return "Restores %d %s when used" % [tier_data.resource, resource_name]
	# Buff potions (check tier versions)
	elif is_tier_value and (item_type == "strength_potion" or "potion_strength" in item_type or "potion_power" in item_type or "elixir_might" in item_type):
		return "+%d Strength for 5 battles" % tier_data.buff_value
	elif is_tier_value and (item_type == "defense_potion" or "potion_defense" in item_type or "potion_iron" in item_type or "elixir_fortress" in item_type):
		return "+%d Defense for 5 battles" % tier_data.buff_value
	elif is_tier_value and (item_type == "speed_potion" or "potion_speed" in item_type or "potion_haste" in item_type or "elixir_swiftness" in item_type):
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
		# Show resource as player's class resource type with scaling (mana→stam/energy at 0.5x)
		var player_class = character_data.get("class", "")
		var resource_name = "Resource"
		var scaled_bonus = mana_bonus
		match player_class:
			"Wizard", "Sorcerer", "Sage":
				resource_name = "Mana"
			"Fighter", "Barbarian", "Paladin":
				resource_name = "Stamina"
				scaled_bonus = int(mana_bonus * 0.5)
			"Thief", "Ranger", "Ninja", "Trickster":
				resource_name = "Energy"
				scaled_bonus = int(mana_bonus * 0.5)
		return "+%d Max %s, +%d WIS, +%d WIT" % [scaled_bonus, resource_name, wis_bonus, wit_bonus]
	elif "gold_pouch" in item_type:
		return "Contains %d-%d gold" % [level * 10, level * 50]
	elif "gem" in item_type:
		return "Worth 1000 gold when sold"
	# Scroll effects - buff scrolls
	elif "scroll_forcefield" in item_type:
		if is_tier_value and tier_data.has("forcefield_value"):
			return "Creates a %d HP shield that absorbs damage (1 battle)" % tier_data.forcefield_value
		else:
			var shield_amount = 50 + level * 10
			return "Creates a %d HP shield that absorbs damage (1 battle)" % shield_amount
	elif "scroll_rage" in item_type:
		if is_tier_value and tier_data.has("buff_value"):
			return "+%d Strength for next combat" % tier_data.buff_value
		else:
			return "+%d Strength for next combat" % (20 + level * 4)
	elif "scroll_stone_skin" in item_type:
		if is_tier_value and tier_data.has("buff_value"):
			return "+%d Defense for next combat" % tier_data.buff_value
		else:
			return "+%d Defense for next combat" % (20 + level * 4)
	elif "scroll_haste" in item_type:
		if is_tier_value and tier_data.has("buff_value"):
			return "+%d Speed for next combat" % tier_data.buff_value
		else:
			return "+%d Speed for next combat" % (30 + level * 5)
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
	elif "scroll_target_farm" in item_type:
		return "Farm a specific monster type for 5 encounters"
	elif "scroll_time_stop" in item_type:
		return "Freeze time - take an extra action in combat"
	elif "scroll_resurrect_greater" in item_type:
		return "Revive with 50% HP on death (permanent until used)"
	elif "scroll_resurrect_lesser" in item_type:
		return "Revive with 25% HP on death (next battle only)"
	elif "scroll" in item_type:
		return "Magical scroll with unknown power"
	# Buff potions - crit and lifesteal
	elif "potion_crit" in item_type:
		if is_tier_value and tier_data.has("buff_value"):
			return "+%d%% Critical chance for 5 rounds" % tier_data.buff_value
		else:
			return "+%d%% Critical chance for 5 rounds" % (10 + level)
	elif "potion_lifesteal" in item_type:
		if is_tier_value and tier_data.has("buff_value"):
			return "%d%% Lifesteal for 5 rounds" % tier_data.buff_value
		else:
			return "%d%% Lifesteal for 5 rounds" % (10 + level * 2)
	# Home Stones
	elif item_type == "home_stone_egg":
		return "Send one incubating egg to your Sanctuary storage"
	elif item_type == "home_stone_supplies":
		return "Send up to 10 consumables to your Sanctuary storage"
	elif item_type == "home_stone_equipment":
		return "Send one equipped item to your Sanctuary storage"
	elif item_type == "home_stone_companion":
		return "Register your active companion at your Sanctuary"
	# Tomes - stat tomes
	elif item_type == "tome_strength":
		return "Permanently increases Strength by 1"
	elif item_type == "tome_constitution":
		return "Permanently increases Constitution by 1"
	elif item_type == "tome_dexterity":
		return "Permanently increases Dexterity by 1"
	elif item_type == "tome_intelligence":
		return "Permanently increases Intelligence by 1"
	elif item_type == "tome_wisdom":
		return "Permanently increases Wisdom by 1"
	elif item_type == "tome_wits":
		return "Permanently increases Wits by 1"
	# Tomes - skill enhancers
	elif item_type == "tome_searing_bolt":
		return "Magic Bolt deals +15% damage (permanent)"
	elif item_type == "tome_efficient_bolt":
		return "Magic Bolt costs 10% less mana (permanent)"
	elif item_type == "tome_greater_forcefield":
		return "Forcefield gives +20% shield strength (permanent)"
	elif item_type == "tome_meteor_mastery":
		return "Meteor deals +25% damage (permanent)"
	elif item_type == "tome_brutal_strike":
		return "Power Strike deals +15% damage (permanent)"
	elif item_type == "tome_efficient_strike":
		return "Power Strike costs 10% less stamina (permanent)"
	elif item_type == "tome_greater_cleave":
		return "Cleave deals +20% damage (permanent)"
	elif item_type == "tome_devastating_berserk":
		return "Berserk deals +25% damage (permanent)"
	elif item_type == "tome_swift_analyze":
		return "Analyze costs no energy (permanent)"
	elif item_type == "tome_greater_ambush":
		return "Ambush deals +20% damage (permanent)"
	elif item_type == "tome_perfect_exploit":
		return "Exploit deals +25% damage (permanent)"
	elif item_type == "tome_efficient_vanish":
		return "Vanish costs 15% less energy (permanent)"
	elif "tome" in item_type:
		return "Tome of knowledge - permanent enhancement"
	# Special consumables
	elif item_type == "mysterious_box":
		return "Open to receive a random reward (could be anything!)"
	elif item_type == "cursed_coin":
		return "Flip the coin: 50% double gold, 50% lose half gold"
	elif "boots" in item_type:
		var spd_bonus = int(base_bonus * 0.5)
		var dex_bonus = int(base_bonus * 0.3)
		return "+%d Speed, +%d DEX" % [spd_bonus, dex_bonus]
	else:
		return "Unknown effect"

func process_command(text: String):
	var parts = text.split(" ", false)
	if parts.is_empty():
		return

	var command = parts[0].to_lower()
	# Strip leading "/" for command matching
	if command.begins_with("/"):
		command = command.substr(1)

	match command:
		"help":
			show_help()
		"clear":
			game_output.clear()
			chat_output.clear()
		"who", "players":
			request_player_list()
			display_game("[color=#808080]Refreshing player list...[/color]")
		"examine", "ex":
			if parts.size() > 1:
				var target = parts[1]
				send_to_server({"type": "examine_player", "name": target})
			else:
				display_game("[color=#FF0000]Usage: /examine <playername>[/color]")
		"whisper", "w", "msg", "tell":
			# Private message: /whisper <player> <message>
			if parts.size() > 2:
				var target = parts[1]
				# Join remaining parts as the message
				var msg_parts = parts.slice(2)
				var msg = " ".join(msg_parts)
				send_to_server({"type": "private_message", "target": target, "message": msg})
			else:
				display_game("[color=#FF0000]Usage: /whisper <player> <message>[/color]")
				display_game("[color=#808080]Example: /w Gandalf Hello there![/color]")
		"reply", "r":
			# Reply to last whisper
			if last_whisper_from.is_empty():
				display_game("[color=#FF0000]No one has whispered you yet![/color]")
			elif parts.size() > 1:
				var msg_parts = parts.slice(1)
				var msg = " ".join(msg_parts)
				send_to_server({"type": "private_message", "target": last_whisper_from, "message": msg})
			else:
				display_game("[color=#FF0000]Usage: /reply <message>[/color]")
		"watch":
			if parts.size() > 1:
				var target = parts[1]
				request_watch_player(target)
			else:
				display_game("[color=#FF0000]Usage: /watch <playername>[/color]")
				display_game("[color=#808080]Watch another player's game output (requires their approval).[/color]")
		"unwatch":
			stop_watching()
		"bug", "report":
			# Get optional description from rest of command
			var description = ""
			if parts.size() > 1:
				description = " ".join(parts.slice(1))
			generate_bug_report(description)
		"search", "find":
			if parts.size() > 1:
				var search_term = " ".join(parts.slice(1))
				search_help(search_term)
			else:
				display_game("[color=#FF0000]Usage: /search <term>[/color]")
				display_game("[color=#808080]Example: /search warrior, /search flee, /search gems[/color]")
		"trade":
			if has_character:
				if parts.size() > 1:
					var target = parts[1]
					handle_trade_command(target)
				else:
					display_game("[color=#FF0000]Usage: /trade <playername>[/color]")
					display_game("[color=#808080]Request to trade items with another player.[/color]")
			else:
				display_game("You don't have a character yet")
		"companion", "pet":
			if has_character:
				if parts.size() > 1:
					var subcommand = parts[1].to_lower()
					match subcommand:
						"dismiss", "release":
							send_to_server({"type": "dismiss_companion"})
						"summon", "activate", "switch":
							if parts.size() > 2:
								var gem_name = " ".join(parts.slice(2))
								send_to_server({"type": "activate_companion", "name": gem_name})
							else:
								display_game("[color=#FF0000]Usage: /companion summon <name>[/color]")
						_:
							# Try to summon by name directly
							var gem_name = " ".join(parts.slice(1))
							send_to_server({"type": "activate_companion", "name": gem_name})
				else:
					show_companion_info()
			else:
				display_game("You don't have a character yet")
		"donate":
			if has_character:
				if parts.size() > 1 and parts[1].is_valid_int():
					var amount = int(parts[1])
					send_to_server({"type": "pilgrimage_donate", "amount": amount})
				else:
					display_game("[color=#FF0000]Usage: /donate <amount>[/color]")
					display_game("[color=#808080]Donate gold to the Shrine of Wealth (Elder pilgrimage).[/color]")
			else:
				display_game("You don't have a character yet")
		"crucible":
			if has_character:
				send_to_server({"type": "start_crucible"})
			else:
				display_game("You don't have a character yet")
		"fish":
			if has_character:
				start_fishing()
			else:
				display_game("You don't have a character yet")
		"craft":
			if has_character:
				if at_trading_post:
					open_crafting()
				else:
					display_game("[color=#FF4444]You can only craft at Trading Posts![/color]")
			else:
				display_game("You don't have a character yet")
		"dungeons", "dungeon":
			if has_character:
				request_dungeon_list()
			else:
				display_game("You don't have a character yet")
		"materials", "mats":
			if has_character:
				display_materials()
			else:
				display_game("You don't have a character yet")
		"debughatch":
			if has_character:
				send_to_server({"type": "debug_hatch"})
			else:
				display_game("You don't have a character yet")
		_:
			# Check if this is a combat command while in combat
			if in_combat:
				# Send as combat command (e.g., "attack", "flee", ability names)
				send_combat_command(text)
			else:
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
	"""Load keybind configuration and settings from config file"""
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
				# Load compare stat setting
				if data.has("inventory_compare_stat") and data["inventory_compare_stat"] in COMPARE_STAT_OPTIONS:
					inventory_compare_stat = data["inventory_compare_stat"]
				# Load combat swap settings
				if data.has("swap_attack_outsmart"):
					swap_attack_outsmart = data["swap_attack_outsmart"]
				# Load UI scale settings
				if data.has("ui_scale_monster_art"):
					ui_scale_monster_art = clampf(float(data["ui_scale_monster_art"]), 0.5, 3.0)
				if data.has("ui_scale_map"):
					ui_scale_map = clampf(float(data["ui_scale_map"]), 0.5, 3.0)
				if data.has("ui_scale_game_output"):
					ui_scale_game_output = clampf(float(data["ui_scale_game_output"]), 0.5, 3.0)
				if data.has("ui_scale_buttons"):
					ui_scale_buttons = clampf(float(data["ui_scale_buttons"]), 0.5, 3.0)
				if data.has("ui_scale_chat"):
					ui_scale_chat = clampf(float(data["ui_scale_chat"]), 0.5, 3.0)
				if data.has("ui_scale_right_panel"):
					ui_scale_right_panel = clampf(float(data["ui_scale_right_panel"]), 0.5, 3.0)
				# Load sound volume settings
				if data.has("sfx_volume"):
					sfx_volume = clampf(float(data["sfx_volume"]), 0.0, 1.0)
				if data.has("music_volume"):
					music_volume = clampf(float(data["music_volume"]), 0.0, 1.0)
				if data.has("sfx_muted"):
					sfx_muted = data["sfx_muted"]

func _save_keybinds():
	"""Save keybind configuration and settings to config file"""
	var save_data = keybinds.duplicate()
	# Include other persistent settings
	save_data["inventory_compare_stat"] = inventory_compare_stat
	save_data["swap_attack_outsmart"] = swap_attack_outsmart
	# Include UI scale settings
	save_data["ui_scale_monster_art"] = ui_scale_monster_art
	save_data["ui_scale_map"] = ui_scale_map
	save_data["ui_scale_game_output"] = ui_scale_game_output
	save_data["ui_scale_buttons"] = ui_scale_buttons
	save_data["ui_scale_chat"] = ui_scale_chat
	save_data["ui_scale_right_panel"] = ui_scale_right_panel
	# Include sound volume settings
	save_data["sfx_volume"] = sfx_volume
	save_data["music_volume"] = music_volume
	save_data["sfx_muted"] = sfx_muted
	var file = FileAccess.open(KEYBIND_CONFIG_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
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
		if item_keycode == action_keycode:
			# Check if this key is currently pressed and has an enabled action
			# This works even before action bar processing runs in _process()
			if Input.is_physical_key_pressed(action_keycode) and not Input.is_key_pressed(KEY_SHIFT):
				if j < current_actions.size():
					var action = current_actions[j]
					if action.get("enabled", false) and action.get("action_type", "none") != "none":
						return true
			# Also check if action bar already processed this key (for timing safety)
			if get_meta("hotkey_%d_pressed" % j, false):
				# Block if this action bar key triggered an action THIS frame
				if j in action_triggered_this_frame:
					return true
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
	"""Find any other actions bound to the same key.
	Action bar keys (action_5-9) are allowed to share with item keys (item_1-9)
	since they serve different purposes in different contexts."""
	var conflicts = []
	# Check if the action being rebound is an action bar key or item key
	var is_action_key = exclude_action.begins_with("action_")
	var is_item_key = exclude_action.begins_with("item_")

	for action in keybinds:
		if action != exclude_action and keybinds[action] == keycode:
			# Allow action bar keys to share with item keys
			var other_is_action = action.begins_with("action_")
			var other_is_item = action.begins_with("item_")

			# Skip conflict if one is action bar and other is item key
			if (is_action_key and other_is_item) or (is_item_key and other_is_action):
				continue

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
	if game_state == GameState.HOUSE_SCREEN:
		display_house_main()
	update_action_bar()

func display_settings_menu():
	"""Display the main settings menu"""
	display_game("[color=#FFD700]===== SETTINGS =====[/color]")
	display_game("")
	display_game("[%s] Configure Action Bar Keys" % get_action_key_name(1))
	display_game("[%s] Configure Movement Keys" % get_action_key_name(2))
	display_game("[%s] Configure Item Selection Keys" % get_action_key_name(3))
	display_game("[%s] Reset All to Defaults" % get_action_key_name(4))
	var swap_ability_enabled = character_data.get("swap_attack_with_ability", false)
	var swap_ability_status = "[color=#00FF00]ON[/color]" if swap_ability_enabled else "[color=#FF6666]OFF[/color]"
	display_game("[%s] Swap Attack with First Ability: %s" % [get_action_key_name(5), swap_ability_status])
	var swap_outsmart_status = "[color=#00FF00]ON[/color]" if swap_attack_outsmart else "[color=#FF6666]OFF[/color]"
	display_game("[%s] Swap Attack with Outsmart: %s" % [get_action_key_name(6), swap_outsmart_status])
	display_game("[%s] Manage Abilities" % get_action_key_name(7))
	display_game("[%s] UI Scale Settings" % get_action_key_name(8))
	display_game("[%s] Sound Settings" % get_action_key_name(9))
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

func display_ui_scale_settings():
	"""Display UI scale settings for adjustment"""
	display_game("[color=#FFD700]===== UI SCALE SETTINGS =====[/color]")
	display_game("[color=#808080]Adjust the size of different UI elements (0.5x - 3.0x)[/color]")
	display_game("")
	display_game("[color=#E6CC80]Map Display[/color] (ASCII terrain, player marker)")
	display_game("[1] Increase  [2] Decrease  Current: [color=#00FFFF]%.0f%%[/color]" % (ui_scale_map * 100))
	display_game("")
	display_game("[color=#E6CC80]Monster Art[/color] (Combat ASCII art, companion/egg art)")
	display_game("[3] Increase  [4] Decrease  Current: [color=#00FFFF]%.0f%%[/color]" % (ui_scale_monster_art * 100))
	display_game("")
	display_game("[color=#E6CC80]Game Text[/color] (Combat text, inventory, menus)")
	display_game("[5] Increase  [6] Decrease  Current: [color=#00FFFF]%.0f%%[/color]" % (ui_scale_game_output * 100))
	display_game("")
	display_game("[color=#E6CC80]Action Buttons[/color] (Hotbar buttons and labels)")
	display_game("[7] Increase  [8] Decrease  Current: [color=#00FFFF]%.0f%%[/color]" % (ui_scale_buttons * 100))
	display_game("")
	display_game("[color=#E6CC80]Chat Output[/color] (Chat text)")
	display_game("[Q] Increase  [W] Decrease  Current: [color=#00FFFF]%.0f%%[/color]" % (ui_scale_chat * 100))
	display_game("")
	display_game("[color=#E6CC80]Right Panel[/color] (Level, Gold, Gems, Map Controls, Online Players, Send)")
	display_game("[E] Increase  [R] Decrease  Current: [color=#00FFFF]%.0f%%[/color]" % (ui_scale_right_panel * 100))
	display_game("")
	display_game("[9] Reset All to 100%")
	display_game("[%s] Back to Settings" % get_action_key_name(0))

func adjust_ui_scale(element: String, delta: float):
	"""Adjust a UI scale setting by the given delta"""
	match element:
		"map":
			ui_scale_map = clampf(ui_scale_map + delta, 0.5, 3.0)
		"monster_art":
			ui_scale_monster_art = clampf(ui_scale_monster_art + delta, 0.5, 3.0)
		"game_output":
			ui_scale_game_output = clampf(ui_scale_game_output + delta, 0.5, 3.0)
		"buttons":
			ui_scale_buttons = clampf(ui_scale_buttons + delta, 0.5, 3.0)
		"chat":
			ui_scale_chat = clampf(ui_scale_chat + delta, 0.5, 3.0)
		"right_panel":
			ui_scale_right_panel = clampf(ui_scale_right_panel + delta, 0.5, 3.0)

	# Save settings and apply
	_save_keybinds()
	_on_window_resized()

	# Redisplay the menu
	game_output.clear()
	display_ui_scale_settings()

func reset_ui_scales():
	"""Reset all UI scales to default (1.0)"""
	ui_scale_monster_art = 1.0
	ui_scale_map = 1.0
	ui_scale_game_output = 1.0
	ui_scale_buttons = 1.0
	ui_scale_chat = 1.0
	ui_scale_right_panel = 1.0

	# Save and apply
	_save_keybinds()
	_on_window_resized()

	# Redisplay the menu
	game_output.clear()
	display_ui_scale_settings()

func display_sound_settings():
	"""Display sound volume settings"""
	display_game("[color=#FFD700]===== SOUND SETTINGS =====[/color]")
	display_game("")
	display_game("[color=#E6CC80]SFX Volume[/color]")
	display_game("[1] Increase  [2] Decrease  Current: [color=#00FFFF]%d%%[/color]" % int(sfx_volume * 100))
	display_game("")
	display_game("[color=#E6CC80]Music Volume[/color]")
	display_game("[3] Increase  [4] Decrease  Current: [color=#00FFFF]%d%%[/color]" % int(music_volume * 100))
	display_game("")
	var mute_status = "[color=#FF6666]MUTED[/color]" if sfx_muted else "[color=#00FF00]ON[/color]"
	display_game("[5] Mute All SFX: %s" % mute_status)
	display_game("")
	display_game("[%s] Back to Settings" % get_action_key_name(0))

func adjust_sound_volume(target: String, delta: float):
	"""Adjust SFX or music volume"""
	if target == "sfx":
		sfx_volume = clampf(sfx_volume + delta, 0.0, 1.0)
	elif target == "music":
		music_volume = clampf(music_volume + delta, 0.0, 1.0)
	_apply_volume_settings()
	_save_keybinds()
	game_output.clear()
	display_sound_settings()

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

func toggle_swap_attack_setting():
	"""Toggle the swap attack with first ability setting"""
	var current = character_data.get("swap_attack_with_ability", false)
	var new_value = not current
	# Update local character data
	character_data["swap_attack_with_ability"] = new_value
	# Send to server to persist
	send_to_server({"type": "toggle_swap_attack", "enabled": new_value})
	# Refresh settings display
	game_output.clear()
	var status = "[color=#00FF00]ENABLED[/color]" if new_value else "[color=#FF6666]DISABLED[/color]"
	display_game("[color=#00FF00]Swap Attack with First Ability: %s[/color]" % status)
	if new_value:
		display_game("[color=#808080]Your first equipped ability will now appear on the primary action key (Space).[/color]")
		display_game("[color=#808080]Attack will move to the first ability slot (R key).[/color]")
	else:
		display_game("[color=#808080]Attack is now on the primary action key (Space).[/color]")
	await get_tree().create_timer(1.5).timeout
	display_settings_menu()
	update_action_bar()

func toggle_swap_outsmart_setting():
	"""Toggle the swap attack with outsmart setting (per-client)"""
	swap_attack_outsmart = not swap_attack_outsmart
	_save_keybinds()  # Persist to client settings
	# Refresh settings display
	game_output.clear()
	var status = "[color=#00FF00]ENABLED[/color]" if swap_attack_outsmart else "[color=#FF6666]DISABLED[/color]"
	display_game("[color=#00FF00]Swap Attack with Outsmart: %s[/color]" % status)
	if swap_attack_outsmart:
		display_game("[color=#808080]Outsmart will now appear on the primary action key (Space).[/color]")
		display_game("[color=#808080]Attack will move to the Outsmart slot (E key).[/color]")
	else:
		display_game("[color=#808080]Attack is now on the primary action key (Space).[/color]")
	await get_tree().create_timer(1.5).timeout
	display_settings_menu()
	update_action_bar()

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
	# Reset dungeon state
	dungeon_mode = false
	dungeon_data = {}
	dungeon_floor_grid = []
	dungeon_available = []
	dungeon_list_mode = false
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
		# Don't clear trading post UI - server will notify if we leave
		if at_trading_post:
			_display_trading_post_ui()
		else:
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

	# Clear output and set contrasting background
	game_output.clear()
	_set_game_output_background(Color(0.05, 0.08, 0.12, 1.0))

	var char = character_data
	var stats = char.get("stats", {})
	var equipped = char.get("equipped", {})
	var bonuses = _calculate_equipment_bonuses(equipped)

	var current_xp = char.get("experience", 0)
	var xp_needed = char.get("experience_to_next_level", 100)
	var xp_remaining = xp_needed - current_xp

	var text = ""

	# === HEADER ===
	text += "[b][color=#FFD700]════════════════════════════════════════════[/color][/b]\n"
	text += "[b][color=#FFD700]  %s[/color][/b] - %s %s Level %d\n" % [char.get("name", "Unknown"), char.get("race", "Human"), char.get("class", "Unknown"), char.get("level", 1)]
	text += "[b][color=#FFD700]════════════════════════════════════════════[/color][/b]\n"

	# Class passive
	var class_passive = _get_class_passive(char.get("class", ""))
	if class_passive.name != "None":
		text += "[color=%s]%s:[/color] %s\n" % [class_passive.color, class_passive.name, class_passive.description]
	text += "\n"

	# === PROGRESSION ===
	text += "[color=#808080]── Progress ──[/color]\n"
	text += "[color=#FF00FF]XP:[/color] %d / %d  ([color=#FFFF00]%d to next level[/color])\n" % [current_xp, xp_needed, xp_remaining]
	text += "[color=#FFD700]Gold:[/color] %d  |  [color=#00FFFF]Gems:[/color] %d  |  [color=#FF4444]Kills:[/color] %d\n" % [char.get("gold", 0), char.get("gems", 0), char.get("monsters_killed", 0)]
	text += "[color=#808080]Location:[/color] (%d, %d)\n" % [char.get("x", 0), char.get("y", 0)]
	text += "\n"

	# === RESOURCES ===
	text += "[color=#808080]── Resources ──[/color]\n"
	var base_hp = char.get("max_hp", 0)
	var total_hp = char.get("total_max_hp", base_hp)
	var base_mana = char.get("max_mana", 0)
	var total_mana = char.get("total_max_mana", base_mana)
	var base_stamina = char.get("max_stamina", 0)
	var total_stamina = char.get("total_max_stamina", base_stamina)
	var base_energy = char.get("max_energy", 0)
	var total_energy = char.get("total_max_energy", base_energy)
	text += "[color=#FF6666]HP:[/color] %d/%d  |  [color=#9999FF]Mana:[/color] %d/%d  |  [color=#FFCC00]Stam:[/color] %d/%d  |  [color=#66FF66]Ener:[/color] %d/%d\n" % [
		char.get("current_hp", 0), total_hp,
		char.get("current_mana", 0), total_mana,
		char.get("current_stamina", 0), total_stamina,
		char.get("current_energy", 0), total_energy
	]
	text += "\n"

	# === STATS ===
	text += "[color=#808080]── Base Stats ──[/color]\n"
	var stat_parts = []
	# [label, key, color]
	var stat_colors = [
		["STR", "strength", "#FF6666"],
		["CON", "constitution", "#00FF00"],
		["DEX", "dexterity", "#FFFF00"],
		["INT", "intelligence", "#9999FF"],
		["WIS", "wisdom", "#66CCFF"],
		["WIT", "wits", "#FF00FF"]
	]
	for stat_info in stat_colors:
		var base_val = stats.get(stat_info[1], 0)
		var bonus_val = bonuses.get(stat_info[1], 0)
		if bonus_val > 0:
			stat_parts.append("[color=%s]%s:[/color] %d [color=#00FF00]+%d[/color]" % [stat_info[2], stat_info[0], base_val, bonus_val])
		else:
			stat_parts.append("[color=%s]%s:[/color] %d" % [stat_info[2], stat_info[0], base_val])
	text += "%s\n" % "  |  ".join(stat_parts)
	text += "\n"

	# === COMBAT ===
	text += "[color=#808080]── Combat ──[/color]\n"
	var base_str = stats.get("strength", 0)
	var total_attack = base_str + bonuses.get("strength", 0) + bonuses.get("attack", 0)
	var base_con = stats.get("constitution", 0)
	var total_defense = (base_con + bonuses.get("constitution", 0)) / 2 + bonuses.get("defense", 0)
	var defense_ratio = float(total_defense) / (float(total_defense) + 100.0)
	var damage_reduction_pct = int(defense_ratio * 60)
	text += "[color=#FF4444]Attack:[/color] %d  (deals %d-%d damage)\n" % [total_attack, int(total_attack * 0.8), int(total_attack * 1.2)]
	text += "[color=#00BFFF]Defense:[/color] %d  (reduces damage by %d%%)\n" % [total_defense, damage_reduction_pct]
	if bonuses.get("speed", 0) > 0:
		text += "[color=#FFFF00]Speed:[/color] +%d\n" % bonuses.get("speed", 0)
	text += "\n"

	# === CLASS GEAR BONUSES ===
	var class_bonus_parts = []
	if bonuses.get("mana_regen", 0) > 0:
		class_bonus_parts.append("[color=#66CCCC]+%d Mana/round[/color]" % bonuses.get("mana_regen", 0))
	if bonuses.get("meditate_bonus", 0) > 0:
		class_bonus_parts.append("[color=#66CCCC]+%d%% Meditate[/color]" % bonuses.get("meditate_bonus", 0))
	if bonuses.get("energy_regen", 0) > 0:
		class_bonus_parts.append("[color=#66FF66]+%d Energy/round[/color]" % bonuses.get("energy_regen", 0))
	if bonuses.get("flee_bonus", 0) > 0:
		class_bonus_parts.append("[color=#66FF66]+%d%% Flee[/color]" % bonuses.get("flee_bonus", 0))
	if bonuses.get("stamina_regen", 0) > 0:
		class_bonus_parts.append("[color=#FFCC00]+%d Stamina/round[/color]" % bonuses.get("stamina_regen", 0))
	if class_bonus_parts.size() > 0:
		text += "[color=#808080]── Class Gear Bonuses ──[/color]\n"
		text += "%s\n\n" % "  |  ".join(class_bonus_parts)

	# === EQUIPMENT ===
	var has_gear = false
	for slot in ["weapon", "shield", "armor", "helm", "boots", "ring", "amulet"]:
		if equipped.get(slot) != null:
			has_gear = true
			break
	if has_gear:
		text += "[color=#808080]── Equipment ──[/color]\n"
		var player_class = char.get("class", "")
		for slot in ["weapon", "shield", "armor", "helm", "boots", "ring", "amulet"]:
			var item = equipped.get(slot)
			if item != null and item is Dictionary:
				var wear = item.get("wear", 0)
				var condition = _get_condition_string(wear)
				var condition_color = _get_condition_color(wear)
				var rarity_color = _get_item_rarity_color(item.get("rarity", "common"))
				var slot_display = _get_themed_slot_name(slot, player_class)
				var themed_name = _get_themed_item_name(item, player_class)
				text += "[color=#AAAAAA]%s:[/color] [color=%s]%s[/color] [color=%s](%s)[/color]\n" % [
					slot_display, rarity_color, themed_name, condition_color, condition
				]
		text += "\n"

	# === GATHERING TOOLS ===
	var equipped_rod = char.get("equipped_fishing_rod", {})
	var equipped_pick = char.get("equipped_pickaxe", {})
	var equipped_axe = char.get("equipped_axe", {})
	if not equipped_rod.is_empty() or not equipped_pick.is_empty() or not equipped_axe.is_empty():
		text += "[color=#808080]── Gathering Tools ──[/color]\n"
		if not equipped_rod.is_empty():
			var rod_bonuses = equipped_rod.get("bonuses", {})
			var bonus_text = _format_tool_bonuses(rod_bonuses)
			text += "[color=#00BFFF]Rod:[/color] %s %s\n" % [equipped_rod.get("name", "Unknown"), bonus_text]
		if not equipped_pick.is_empty():
			var pick_bonuses = equipped_pick.get("bonuses", {})
			var bonus_text = _format_tool_bonuses(pick_bonuses)
			text += "[color=#C0C0C0]Pickaxe:[/color] %s %s\n" % [equipped_pick.get("name", "Unknown"), bonus_text]
		if not equipped_axe.is_empty():
			var axe_bonuses = equipped_axe.get("bonuses", {})
			var bonus_text = _format_tool_bonuses(axe_bonuses)
			text += "[color=#8B4513]Axe:[/color] %s %s\n" % [equipped_axe.get("name", "Unknown"), bonus_text]
		text += "\n"

	# === ACTIVE COMPANION ===
	var active_companion = char.get("active_companion", {})
	if not active_companion.is_empty():
		text += "[color=#808080]── Active Companion ──[/color]\n"
		var comp_name = active_companion.get("name", "Unknown")
		var comp_level = active_companion.get("level", 1)
		var comp_variant = active_companion.get("variant", "Normal")
		var comp_variant_color = active_companion.get("variant_color", "#FFFFFF")
		var comp_bonuses = active_companion.get("bonuses", {})

		# Apply variant multiplier to display accurate values
		var variant_mult = 1.0
		match comp_variant:
			"Shiny": variant_mult = 1.25
			"Glittering": variant_mult = 1.5
			"Radiant": variant_mult = 2.0
			"Prismatic": variant_mult = 3.0

		text += "[color=%s]%s %s[/color] [color=#AAAAAA]Lv.%d[/color]\n" % [comp_variant_color, comp_variant, comp_name, comp_level]

		# Show combat bonuses that are actually applied
		var comp_bonus_parts = []
		if comp_bonuses.get("attack", 0) > 0:
			var attack_val = int(comp_bonuses.get("attack", 0) * variant_mult)
			comp_bonus_parts.append("[color=#FF6666]+%d%% Damage[/color]" % attack_val)
		if comp_bonuses.get("crit_chance", 0) > 0:
			var crit_val = int(comp_bonuses.get("crit_chance", 0) * variant_mult)
			comp_bonus_parts.append("[color=#FFFF00]+%d%% Crit[/color]" % crit_val)
		if comp_bonuses.get("hp_regen", 0) > 0:
			var regen_val = int(comp_bonuses.get("hp_regen", 0) * variant_mult)
			comp_bonus_parts.append("[color=#00FF00]+%d%% HP/rnd[/color]" % regen_val)
		if comp_bonuses.get("flee_bonus", 0) > 0:
			var flee_val = int(comp_bonuses.get("flee_bonus", 0) * variant_mult)
			comp_bonus_parts.append("[color=#00BFFF]+%d%% Flee[/color]" % flee_val)
		if comp_bonuses.get("defense", 0) > 0:
			var def_val = int(comp_bonuses.get("defense", 0) * variant_mult)
			comp_bonus_parts.append("[color=#00BFFF]+%d Defense[/color]" % def_val)
		if comp_bonuses.get("lifesteal", 0) > 0:
			var steal_val = int(comp_bonuses.get("lifesteal", 0) * variant_mult)
			comp_bonus_parts.append("[color=#FF00FF]+%d%% Lifesteal[/color]" % steal_val)
		if comp_bonuses.get("gold_find", 0) > 0:
			var gold_val = int(comp_bonuses.get("gold_find", 0) * variant_mult)
			comp_bonus_parts.append("[color=#FFD700]+%d%% Gold[/color]" % gold_val)
		if comp_bonuses.get("speed", 0) > 0:
			var speed_val = int(comp_bonuses.get("speed", 0) * variant_mult)
			comp_bonus_parts.append("[color=#FFFF00]+%d Speed[/color]" % speed_val)

		if comp_bonus_parts.size() > 0:
			text += "[color=#00FFFF]Combat Bonuses:[/color] %s\n" % "  ".join(comp_bonus_parts)
		text += "\n"

	# === ACTIVE EFFECTS ===
	var effects_text = _get_status_effects_text_compact()
	if effects_text != "":
		text += "[color=#808080]── Active Effects ──[/color]\n"
		text += effects_text

	display_game(text)

func _get_status_effects_text_compact() -> String:
	"""Generate compact status effects for character status display"""
	var parts = []

	# Cloak status
	if character_data.get("cloak_active", false):
		parts.append("[color=#9932CC]Cloaked[/color]")

	if character_data.get("poison_active", false):
		var poison_dmg = character_data.get("poison_damage", 0)
		var poison_turns = character_data.get("poison_turns_remaining", 0)
		parts.append("[color=#FF00FF]Poison %d dmg x%d[/color]" % [poison_dmg, poison_turns])

	if character_data.get("blind_active", false):
		var blind_turns = character_data.get("blind_turns_remaining", 0)
		parts.append("[color=#808080]Blind x%d[/color]" % blind_turns)

	# Active combat buffs (use duration)
	var active_buffs = character_data.get("active_buffs", [])
	for buff in active_buffs:
		var buff_type = buff.get("type", "")
		var remaining = buff.get("duration", 0)
		var color = _get_buff_color(buff_type)
		var display_name = _get_buff_display_name(buff_type)
		parts.append("[color=%s]%s x%d[/color]" % [color, display_name, remaining])

	# Persistent buffs (use battles_remaining)
	var persistent_buffs = character_data.get("persistent_buffs", [])
	for buff in persistent_buffs:
		var buff_type = buff.get("type", "")
		var remaining = buff.get("battles_remaining", 0)
		var color = _get_buff_color(buff_type)
		var display_name = _get_buff_display_name(buff_type)
		parts.append("[color=%s]%s x%d[/color]" % [color, display_name, remaining])

	if parts.size() > 0:
		return "[color=#FFFF00]Effects:[/color] %s\n" % " | ".join(parts)
	return ""

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

func _format_tool_bonuses(bonuses: Dictionary) -> String:
	"""Format gathering tool bonuses for display"""
	var parts = []
	var yield_bonus = bonuses.get("yield_bonus", 0)
	var speed_bonus = bonuses.get("speed_bonus", 0.0)
	var tier_bonus = bonuses.get("tier_bonus", 0)

	if yield_bonus > 0:
		parts.append("[color=#00FF00]+%d yield[/color]" % yield_bonus)
	if speed_bonus > 0:
		parts.append("[color=#FFFF00]+%d%% speed[/color]" % int(speed_bonus * 100))
	if tier_bonus > 0:
		parts.append("[color=#00BFFF]+%d tier[/color]" % tier_bonus)

	if parts.is_empty():
		return ""
	return "(" + ", ".join(parts) + ")"

func open_more_menu():
	"""Open the More menu"""
	more_mode = true
	display_more_menu()
	update_action_bar()

func close_more_menu():
	"""Close the More menu"""
	more_mode = false
	game_output.clear()
	update_action_bar()

func display_more_menu():
	"""Display the More menu options"""
	game_output.clear()
	display_game("[color=#FFD700]═══════ MORE ═══════[/color]")
	display_game("")
	display_game("[%s] [color=#00FFFF]Companions[/color] - View and manage your companions" % get_action_key_name(1))
	display_game("[%s] [color=#FFAA00]Eggs[/color] - View incubating eggs" % get_action_key_name(2))
	display_game("[%s] [color=#FFD700]Leaders[/color] - View the leaderboards" % get_action_key_name(3))
	display_game("[%s] [color=#00FF00]Changes[/color] - What's new in recent updates" % get_action_key_name(4))
	display_game("[%s] [color=#FF6666]Bestiary[/color] - Monster tiers and Home Stone drops" % get_action_key_name(5))
	display_game("")
	display_game("[color=#808080]Press [%s] to go back.[/color]" % get_action_key_name(0))

func display_changelog():
	"""Display recent changes and updates"""
	game_output.clear()
	display_game("[color=#FFD700]═══════ WHAT'S CHANGED ═══════[/color]")
	display_game("")

	# v0.9.93 changes
	display_game("[color=#00FF00]v0.9.93[/color] [color=#808080](Current)[/color]")
	display_game("  • Fix: Duplicate companions auto-removed on character load (keeps highest level)")
	display_game("  • Fix: Kennel checkout no longer creates duplicate companion entries")
	display_game("")

	# v0.9.92 changes
	display_game("[color=#00FFFF]v0.9.92[/color]")
	display_game("  • Fix: Quest gem rewards now actually awarded (were silently zeroed)")
	display_game("  • Fix: Dungeon completion now shows 'eggs full' warning when applicable")
	display_game("")

	# v0.9.91 changes
	display_game("[color=#00FFFF]v0.9.91[/color]")
	display_game("  • Fix: Registered kennel companions no longer duplicate via corpse looting")
	display_game("  • Kennel companions now gain XP, track battles, and show abilities")
	display_game("")

	# v0.9.89 changes
	display_game("[color=#00FFFF]v0.9.89[/color]")
	display_game("  • Kennel checkout, All or Nothing rebalance (34% cap), admin variant rolling")
	display_game("")

	# v0.9.88 changes
	display_game("[color=#00FFFF]v0.9.88[/color]")
	display_game("  • Data safety: backup saves, auto-recovery, admin tools")
	display_game("")

	display_game("[color=#808080]Press [%s] to go back to More menu.[/color]" % get_action_key_name(0))

func display_bestiary():
	"""Display monster tiers and Home Stone drop information"""
	game_output.clear()
	display_game("[color=#FFD700]═══════ BESTIARY ═══════[/color]")
	display_game("")

	# Tier 1
	display_game("[color=#AAAAAA]Tier 1[/color] [color=#808080](Levels 1-5)[/color]")
	display_game("  Goblin, Giant Rat, Kobold, Skeleton, Wolf")
	display_game("")

	# Tier 2
	display_game("[color=#FFFFFF]Tier 2[/color] [color=#808080](Levels 6-15)[/color]")
	display_game("  Orc, Hobgoblin, Gnoll, Zombie, Giant Spider, Wight, Siren, Kelpie, Mimic")
	display_game("")

	# Tier 3
	display_game("[color=#00FF00]Tier 3[/color] [color=#808080](Levels 16-30)[/color]")
	display_game("  Ogre, Troll, Wraith, Wyvern, Minotaur, Gargoyle, Harpy, Shrieker")
	display_game("")

	# Tier 4 - Home Stones start dropping
	display_game("[color=#0070DD]Tier 4[/color] [color=#808080](Levels 31-50)[/color]")
	display_game("  Giant, Dragon Wyrmling, Demon, Vampire, Gryphon, Chimaera, Succubus")
	display_game("  [color=#00FFFF]→ Home Stone (Egg), Home Stone (Supplies) start dropping[/color]")
	display_game("")

	# Tier 5
	display_game("[color=#A335EE]Tier 5[/color] [color=#808080](Levels 51-100)[/color]")
	display_game("  Ancient Dragon, Demon Lord, Lich, Titan, Balrog, Cerberus, Jabberwock")
	display_game("  [color=#00FFFF]→ Home Stone (Equipment) starts dropping[/color]")
	display_game("")

	# Tier 6
	display_game("[color=#FF8000]Tier 6[/color] [color=#808080](Levels 101-500)[/color]")
	display_game("  Elemental, Iron Golem, Sphinx, Hydra, Phoenix, Nazgul")
	display_game("  [color=#00FFFF]→ Home Stone (Companion) starts dropping[/color]")
	display_game("")

	# Tier 7
	display_game("[color=#FF4444]Tier 7[/color] [color=#808080](Levels 501-2000)[/color]")
	display_game("  Void Walker, World Serpent, Elder Lich, Primordial Dragon")
	display_game("")

	# Tier 8
	display_game("[color=#FF00FF]Tier 8[/color] [color=#808080](Levels 2001-5000)[/color]")
	display_game("  Cosmic Horror, Time Weaver, Death Incarnate")
	display_game("")

	# Tier 9
	display_game("[color=#FFD700]Tier 9[/color] [color=#808080](Levels 5001+)[/color]")
	display_game("  Avatar of Chaos, The Nameless One, God Slayer, Entropy")
	display_game("")

	display_game("[color=#FFD700]═══ SPECIAL DROPS ═══[/color]")
	display_game("")

	# Class-specific gear drops
	display_game("[color=#66CCCC]Arcane Hoarder[/color] [color=#808080](35% Mage gear)[/color]")
	display_game("  Wraith, Lich, Sphinx, Elder Lich, Time Weaver")
	display_game("  [color=#808080]Drops: Arcane Ring, Mystic Amulet[/color]")
	display_game("")

	display_game("[color=#66FF66]Cunning Prey[/color] [color=#808080](35% Trickster gear)[/color]")
	display_game("  Wolf, Shrieker, Giant Spider, Void Walker")
	display_game("  [color=#808080]Drops: Swift Boots, Stealth Cloak[/color]")
	display_game("")

	display_game("[color=#FF6600]Warrior Hoarder[/color] [color=#808080](35% Warrior gear)[/color]")
	display_game("  Ogre, Iron Golem, Death Incarnate")
	display_game("  [color=#808080]Drops: Battle Ring, War Helm[/color]")
	display_game("")

	# Variant drops
	display_game("[color=#FF8000]★ Weapon Master[/color] [color=#808080](Rare variant - 35% weapon)[/color]")
	display_game("[color=#00FFFF]★ Shield Guardian[/color] [color=#808080](Rare variant - 35% shield)[/color]")
	display_game("  [color=#808080]Any monster can spawn as these variants[/color]")
	display_game("")

	display_game("[color=#808080]Tiers determine loot quality. Higher tier monsters may appear early due to tier bleed.[/color]")
	display_game("[color=#808080]Press [%s] to go back to More menu.[/color]" % get_action_key_name(0))

func show_companion_info():
	"""Display companions menu - eggs, hatched companions, and active companion"""
	more_mode = false
	companions_mode = true
	companions_page = 0
	display_companions()
	update_action_bar()

func _sort_companions(companions: Array) -> Array:
	"""Sort companions based on current sort option."""
	var sorted_comps = companions.duplicate()

	sorted_comps.sort_custom(func(a, b):
		var val_a
		var val_b

		match companion_sort_option:
			"level":
				val_a = a.get("level", 0)
				val_b = b.get("level", 0)
			"tier":
				val_a = a.get("tier", 0)
				val_b = b.get("tier", 0)
			"variant":
				# Sort by variant rarity (Mythic > Legendary > Epic > Rare > Uncommon > Common)
				val_a = _get_variant_sort_value(a.get("variant", "Normal"))
				val_b = _get_variant_sort_value(b.get("variant", "Normal"))
			"damage":
				# Estimated damage based on tier and level
				val_a = _get_companion_sort_damage_value(a)
				val_b = _get_companion_sort_damage_value(b)
			"name":
				val_a = a.get("name", "").to_lower()
				val_b = b.get("name", "").to_lower()
				# For name, ascending = A-Z
				if companion_sort_ascending:
					return val_a < val_b
				else:
					return val_a > val_b
			"type":
				val_a = a.get("monster_type", a.get("name", "")).to_lower()
				val_b = b.get("monster_type", b.get("name", "")).to_lower()
				if companion_sort_ascending:
					return val_a < val_b
				else:
					return val_a > val_b
			_:
				val_a = a.get("level", 0)
				val_b = b.get("level", 0)

		# For numeric sorts
		if companion_sort_ascending:
			return val_a < val_b
		else:
			return val_a > val_b
	)

	return sorted_comps

func _get_variant_sort_value(variant: String) -> int:
	"""Get a numeric value for variant rarity for sorting."""
	# Mythic variants = 5
	if variant in ["Prismatic", "Void", "Cosmic", "Divine"]:
		return 5
	# Legendary variants = 4
	if variant in ["Spectral", "Ethereal", "Celestial", "Bifrost"]:
		return 4
	# Epic variants = 3
	if variant in ["Shiny", "Radiant", "Starfall", "Blessed"]:
		return 3
	# Rare variants = 2
	if variant in ["Volcanic", "Twilight", "Rising", "Dusk", "Storm", "Royal", "Magenta", "Coral", "Mint"]:
		return 2
	# Uncommon variants = 1
	if variant not in ["Normal", ""]:
		return 1
	# Common/Normal = 0
	return 0

func _get_companion_sort_damage_value(companion: Dictionary) -> int:
	"""Get a numeric damage value for sorting companions."""
	var tier = companion.get("tier", 1)
	var level = companion.get("level", 1)
	var variant = companion.get("variant", "Normal")

	# Base damage formula: tier * 5 + level * 2
	var base_damage = tier * 5 + level * 2

	# Apply variant multiplier
	var variant_mult = _get_variant_multiplier(variant)
	return int(base_damage * variant_mult)

func display_companions():
	"""Display the companions list with level, XP, abilities, and variant info"""
	game_output.clear()

	var active_companion = character_data.get("active_companion", {})
	var incubating_eggs = character_data.get("incubating_eggs", [])
	var collected_companions = character_data.get("collected_companions", [])
	var soul_gems = character_data.get("soul_gems", [])

	display_game("[color=#FFD700]═══════ COMPANIONS ═══════[/color]")
	display_game("")

	# Active companion section - enhanced with level and abilities
	if not active_companion.is_empty():
		var comp_name = active_companion.get("name", "Unknown")
		var comp_level = active_companion.get("level", 1)
		var comp_xp = active_companion.get("xp", 0)
		var comp_tier = active_companion.get("tier", 1)
		var variant = active_companion.get("variant", "Normal")
		var variant_color = active_companion.get("variant_color", "#FFFFFF")
		var bonuses = active_companion.get("bonuses", {})

		# Calculate XP needed (formula: (level+1)^1.8 * 20)
		var xp_to_next = 0
		if comp_level < 50:
			xp_to_next = int(pow(comp_level + 1, 1.8) * 20)

		# Get variant stat multiplier and rarity info
		var variant_mult = _get_variant_multiplier(variant)
		var variant_bonus_text = ""
		if variant_mult > 1.0:
			variant_bonus_text = " [color=#FFD700](+%d%% stats)[/color]" % int((variant_mult - 1.0) * 100)
		var rarity_info = _get_variant_rarity_info(variant)

		display_game("[color=#00FFFF]Active Companion:[/color]")
		display_game("  [color=%s][%s][/color] [color=%s]%s %s[/color]%s" % [rarity_info.color, rarity_info.tier, variant_color, variant, comp_name, variant_bonus_text])
		display_game("  [color=#AAAAAA]Level %d | Tier %d[/color]" % [comp_level, comp_tier])

		# XP bar
		if comp_level < 50:
			var xp_percent = int((float(comp_xp) / float(xp_to_next)) * 100) if xp_to_next > 0 else 0
			var bar_length = 20
			var filled = int(bar_length * xp_percent / 100)
			var xp_bar = "[" + "█".repeat(filled) + "░".repeat(bar_length - filled) + "]"
			display_game("  [color=#00FF00]XP: %s %d/%d (%d%%)[/color]" % [xp_bar, comp_xp, xp_to_next, xp_percent])
		else:
			display_game("  [color=#FFD700]MAX LEVEL[/color]")

		# Show bonuses with variant multiplier
		var bonus_parts = _get_companion_bonus_parts_with_variant(bonuses, variant_mult)
		if bonus_parts.size() > 0:
			display_game("  %s" % ", ".join(bonus_parts))

		# Show unlocked abilities with actual names and descriptions
		display_game("")
		display_game("  [color=#A335EE]Abilities:[/color]")
		var tier_abilities = COMPANION_ABILITIES.get(comp_tier, {})

		# Level 10 ability
		if tier_abilities.has(10):
			var ability = tier_abilities[10]
			var ability_desc = _format_companion_ability(ability)
			if comp_level >= 10:
				display_game("    [color=#00FF00]Lv.10: %s[/color] - %s" % [ability.name, ability_desc])
			else:
				display_game("    [color=#808080]Lv.10: %s[/color] [color=#666666](Locked)[/color]" % ability.name)

		# Level 25 ability
		if tier_abilities.has(25):
			var ability = tier_abilities[25]
			var ability_desc = _format_companion_ability(ability)
			if comp_level >= 25:
				display_game("    [color=#00FF00]Lv.25: %s[/color] - %s" % [ability.name, ability_desc])
			else:
				display_game("    [color=#808080]Lv.25: %s[/color] [color=#666666](Locked)[/color]" % ability.name)

		# Level 50 ability
		if tier_abilities.has(50):
			var ability = tier_abilities[50]
			var ability_desc = _format_companion_ability(ability)
			if comp_level >= 50:
				display_game("    [color=#FFD700]Lv.50: %s[/color] - %s" % [ability.name, ability_desc])
			else:
				display_game("    [color=#808080]Lv.50: %s[/color] [color=#666666](Locked)[/color]" % ability.name)

		display_game("")
	else:
		display_game("[color=#808080]No active companion[/color]")
		display_game("")

	# Show egg count with link to Eggs page
	if incubating_eggs.size() > 0:
		display_game("[color=#FFAA00]Incubating Eggs: %d[/color] [color=#808080](View in More > Eggs)[/color]" % incubating_eggs.size())
		display_game("")

	# Hatched companions section - enhanced with level and variant (PAGINATED)
	if collected_companions.size() > 0:
		# Sort the companions before display
		var sorted_companions = _sort_companions(collected_companions)
		# Store sorted order so activate_companion_by_index uses same order as display
		set_meta("sorted_companions", sorted_companions)

		var total_pages = int(ceil(float(sorted_companions.size()) / float(COMPANIONS_PAGE_SIZE)))
		companions_page = clamp(companions_page, 0, max(0, total_pages - 1))
		var start_idx = companions_page * COMPANIONS_PAGE_SIZE
		var end_idx = min(start_idx + COMPANIONS_PAGE_SIZE, sorted_companions.size())

		# Sort indicator
		var sort_direction = "▲" if companion_sort_ascending else "▼"
		var sort_label = companion_sort_option.capitalize()
		display_game("[color=#00FF00]Hatched Companions (%d)[/color] [color=#808080]Page %d/%d | Sort: %s %s[/color]" % [sorted_companions.size(), companions_page + 1, total_pages, sort_label, sort_direction])

		for i in range(start_idx, end_idx):
			var companion = sorted_companions[i]
			var comp_name = companion.get("name", "Unknown")
			var comp_id = companion.get("id", "")
			var comp_level = companion.get("level", 1)
			var variant = companion.get("variant", "Normal")
			var variant_color = companion.get("variant_color", "#FFFFFF")
			var is_active = not active_companion.is_empty() and active_companion.get("id", "") == comp_id

			# Get variant bonus indicator and rarity info
			var variant_mult = _get_variant_multiplier(variant)
			var variant_indicator = ""
			if variant_mult > 1.0:
				variant_indicator = " [color=#FFD700]★[/color]"  # Star for bonus variants
			var rarity_info = _get_variant_rarity_info(variant)

			var display_num = (i - start_idx) + 1  # 1-5 for current page
			if is_active:
				display_game("  [%d] [color=%s][%s][/color] [color=#00FFFF]★ %s Lv.%d[/color] [color=%s](%s)[/color]%s" % [display_num, rarity_info.color, rarity_info.tier, comp_name, comp_level, variant_color, variant, variant_indicator])
			else:
				display_game("  [%d] [color=%s][%s][/color] [color=#00FF00]%s Lv.%d[/color] [color=%s](%s)[/color]%s" % [display_num, rarity_info.color, rarity_info.tier, comp_name, comp_level, variant_color, variant, variant_indicator])

		display_game("")
		if total_pages > 1:
			display_game("[color=#808080]Press 1-5 to activate | Q/E to change page[/color]")
		else:
			display_game("[color=#808080]Press 1-5 to activate a companion[/color]")

	# Soul gems (legacy)
	if soul_gems.size() > 0:
		display_game("[color=#A335EE]Soul Gems (%d):[/color]" % soul_gems.size())
		for gem in soul_gems:
			var gem_name = gem.get("name", "Unknown")
			var is_active = not active_companion.is_empty() and active_companion.get("id", "") == gem.get("id", "")
			if is_active:
				display_game("  [color=#00FFFF]● %s (Active)[/color]" % gem_name)
			else:
				display_game("  [color=#808080]○ %s[/color]" % gem_name)
		display_game("")

	# No companions at all
	if incubating_eggs.size() == 0 and collected_companions.size() == 0 and soul_gems.size() == 0:
		display_game("[color=#808080]No companions yet![/color]")
		display_game("[color=#808080]Find companion eggs in dungeons.[/color]")

	display_game("")
	display_game("[color=#FFD700]══════════════════════════[/color]")

func _get_variant_rarity_info(variant: String) -> Dictionary:
	"""Get rarity tier name and color for a companion variant.
	Returns {tier: String, color: String} for display."""
	# Mythic (+50% stats) - rarest
	if variant in ["Prismatic", "Void", "Cosmic", "Divine"]:
		return {"tier": "Mythic", "color": "#FF00FF"}
	# Legendary (+25% stats)
	if variant in ["Spectral", "Ethereal", "Celestial", "Bifrost"]:
		return {"tier": "Legendary", "color": "#FF8000"}
	# Epic (+10% stats)
	if variant in ["Shiny", "Radiant", "Starfall", "Blessed"]:
		return {"tier": "Epic", "color": "#A335EE"}
	# Rare (rarity 2-3, complex patterns)
	if variant in [
		# Gradients
		"Volcanic", "Twilight", "Rising",
		# Middle patterns
		"Core", "Heart", "Soul", "Nexus", "Beacon",
		# Striped
		"Tiger", "Candy", "Electric", "Aquatic", "Regal", "Haunted",
		# Edge patterns
		"Outlined", "Glowing", "Burning", "Frozen", "Toxic Glow",
		# Diagonal
		"Slash", "Lightning", "Rift", "Shattered", "Ascendant", "Phoenix", "Comet", "Crescent",
		# Split
		"Split", "Duality", "Twilit", "Balanced", "Chimeric",
		# Checker/Radial
		"Mosaic", "Harlequin", "Aura", "Corona", "Eclipse",
		# Columns
		"Barcode", "Zebra", "Neon Bars", "Jailbird",
		# Bands
		"Layered", "Stratified", "Sediment",
		# Corners
		"Framed", "Gilded", "Corrupted",
		# Cross
		"Marked", "Hex", "Branded",
		# Wave
		"Tidal", "Ripple", "Current", "Mirage",
		# Scatter
		"Speckled", "Starry", "Freckled", "Glittering", "Spotted",
		# Ring
		"Ringed", "Orbital", "Halo",
		# Fade
		"Misty", "Smoky", "Dreamlike", "Fading"
	]:
		return {"tier": "Rare", "color": "#0070DD"}
	# Uncommon (rarity 4-6, simple gradients and solids)
	if variant in [
		"Frost", "Infernal", "Toxic", "Amethyst", "Midnight", "Ivory", "Rust", "Mint",
		"Sunset", "Ocean", "Forest", "Dusk", "Ember", "Arctic",
		"Dawn", "Depths", "Bloom"
	]:
		return {"tier": "Uncommon", "color": "#1EFF00"}
	# Common (rarity 8-15, solid colors)
	return {"tier": "Common", "color": "#9D9D9D"}

func _get_variant_multiplier(variant: String) -> float:
	"""Get the stat multiplier for a companion variant."""
	# Rare special (+10% stats)
	if variant in ["Shiny", "Radiant", "Blessed", "Starfall"]:
		return 1.10
	# Very rare (+25% stats)
	if variant in ["Spectral", "Ethereal", "Celestial", "Bifrost"]:
		return 1.25
	# Legendary (+50% stats)
	if variant in ["Prismatic", "Void", "Cosmic", "Divine"]:
		return 1.50
	return 1.0

func _estimate_companion_damage(companion_tier: int, player_level: int, companion_bonuses: Dictionary, companion_level: int, variant_mult: float = 1.0) -> Dictionary:
	"""Estimate companion damage range for display purposes.
	Mirrors the formula in drop_tables.get_companion_attack_damage().
	Returns {min, max, avg} damage values."""
	# Base damage formula: tier*5 + player_level*0.3 + companion_level*0.5
	var tier_damage = companion_tier * 5
	var player_bonus = int(player_level * 0.3)
	var companion_bonus = int(companion_level * 0.5)
	var base_total = tier_damage + player_bonus + companion_bonus
	# Apply attack bonus from companion bonuses
	var attack_bonus = companion_bonuses.get("attack", 0)
	var base = int(base_total * (1.0 + float(attack_bonus) / 100.0))
	# Apply variant multiplier
	base = int(base * variant_mult)
	# Combat applies 80-120% variance
	var min_dmg = max(1, int(base * 0.8))
	var max_dmg = max(1, int(base * 1.2))
	var avg_dmg = int((min_dmg + max_dmg) / 2)
	return {"min": min_dmg, "max": max_dmg, "avg": avg_dmg}

func _get_companion_bonus_parts_with_variant(bonuses: Dictionary, multiplier: float) -> Array:
	"""Get formatted bonus text parts for a companion with variant multiplier applied."""
	var parts = []
	if bonuses.get("attack", 0) > 0:
		var val = int(bonuses.attack * multiplier)
		parts.append("[color=#FF6666]+%d%% Atk[/color]" % val)
	if bonuses.get("defense", 0) > 0:
		var val = int(bonuses.defense * multiplier)
		parts.append("[color=#87CEEB]+%d%% Def[/color]" % val)
	if bonuses.get("hp_bonus", 0) > 0:
		var val = int(bonuses.hp_bonus * multiplier)
		parts.append("[color=#00FF00]+%d%% HP[/color]" % val)
	if bonuses.get("hp_regen", 0) > 0:
		var val = int(bonuses.hp_regen * multiplier)
		parts.append("[color=#66FF66]+%d%% Regen[/color]" % val)
	if bonuses.get("crit_chance", 0) > 0:
		var val = int(bonuses.crit_chance * multiplier)
		parts.append("[color=#FFFF66]+%d%% Crit[/color]" % val)
	if bonuses.get("gold_find", 0) > 0:
		var val = int(bonuses.gold_find * multiplier)
		parts.append("[color=#FFD700]+%d%% Gold[/color]" % val)
	if bonuses.get("flee_bonus", 0) > 0:
		var val = int(bonuses.flee_bonus * multiplier)
		parts.append("[color=#6666FF]+%d%% Flee[/color]" % val)
	if bonuses.get("lifesteal", 0) > 0:
		var val = int(bonuses.lifesteal * multiplier)
		parts.append("[color=#FF00FF]+%d%% Steal[/color]" % val)
	if bonuses.get("speed", 0) > 0:
		var val = int(bonuses.speed * multiplier)
		parts.append("[color=#00FFFF]+%d%% Speed[/color]" % val)
	if bonuses.get("mana_bonus", 0) > 0:
		var val = int(bonuses.mana_bonus * multiplier)
		parts.append("[color=#0070DD]+%d%% Mana[/color]" % val)
	if bonuses.get("mana_regen", 0) > 0:
		var val = int(bonuses.mana_regen * multiplier)
		parts.append("[color=#0070DD]+%d%% MRegen[/color]" % val)
	if bonuses.get("wisdom_bonus", 0) > 0:
		var val = int(bonuses.wisdom_bonus * multiplier)
		parts.append("[color=#9370DB]+%d%% Wis[/color]" % val)
	if bonuses.get("crit_damage", 0) > 0:
		var val = int(bonuses.crit_damage * multiplier)
		parts.append("[color=#FF4444]+%d%% CDmg[/color]" % val)
	return parts

func _get_companion_bonus_parts(bonuses: Dictionary) -> Array:
	"""Get formatted bonus text parts for a companion"""
	var parts = []
	if bonuses.get("attack", 0) > 0:
		parts.append("[color=#FF6666]+%d%% Atk[/color]" % int(bonuses.attack))
	if bonuses.get("defense", 0) > 0:
		parts.append("[color=#87CEEB]+%d%% Def[/color]" % int(bonuses.defense))
	if bonuses.get("hp_bonus", 0) > 0:
		parts.append("[color=#00FF00]+%d%% HP[/color]" % int(bonuses.hp_bonus))
	if bonuses.get("hp_regen", 0) > 0:
		parts.append("[color=#66FF66]+%d%% Regen[/color]" % int(bonuses.hp_regen))
	if bonuses.get("crit_chance", 0) > 0:
		parts.append("[color=#FFFF66]+%d%% Crit[/color]" % int(bonuses.crit_chance))
	if bonuses.get("gold_find", 0) > 0:
		parts.append("[color=#FFD700]+%d%% Gold[/color]" % int(bonuses.gold_find))
	if bonuses.get("flee_bonus", 0) > 0:
		parts.append("[color=#6666FF]+%d%% Flee[/color]" % int(bonuses.flee_bonus))
	if bonuses.get("lifesteal", 0) > 0:
		parts.append("[color=#FF00FF]+%d%% Steal[/color]" % int(bonuses.lifesteal))
	return parts

func _format_companion_ability(ability: Dictionary) -> String:
	"""Format a companion ability for display"""
	var ability_type = ability.get("type", "passive")
	var effect = ability.get("effect", "")
	var value = ability.get("value", 0)

	match ability_type:
		"passive":
			var desc = ""
			if effect == "attack":
				desc = "+%d Attack" % value
			elif effect == "defense":
				desc = "+%d Defense" % value
			elif effect == "speed":
				desc = "+%d Speed" % value
			elif effect == "crit_chance":
				desc = "+%d%% Crit" % value
			else:
				desc = "+%d %s" % [value, effect.capitalize()]
			# Check for secondary effects
			if ability.has("effect2"):
				var val2 = ability.get("value2", 0)
				desc += ", +%d %s" % [val2, ability.effect2.capitalize()]
			if ability.has("effect3"):
				var val3 = ability.get("value3", 0)
				desc += ", +%d %s" % [val3, ability.effect3.capitalize()]
			return desc
		"chance":
			var chance = ability.get("chance", 0)
			if effect == "enemy_miss":
				return "%d%% chance to cause enemy miss" % chance
			elif effect == "bonus_damage":
				var secondary = ""
				if ability.has("effect2") and ability.effect2 == "stun":
					secondary = " (+%d%% stun)" % ability.get("chance2", 0)
				elif ability.has("effect2") and ability.effect2 == "lifesteal":
					secondary = " (+%d%% lifesteal)" % ability.get("value2", 0)
				return "%d%% chance for +%d bonus damage%s" % [chance, value, secondary]
			else:
				return "%d%% chance: %s" % [chance, effect]
		"threshold":
			var hp_percent = ability.get("hp_percent", 50)
			if effect == "defense_buff":
				var duration = ability.get("duration", 3)
				return "At %d%% HP: +%d defense for %d rounds" % [hp_percent, value, duration]
			elif effect == "heal":
				return "At %d%% HP: Heal %d%% of max HP" % [hp_percent, value]
			elif effect == "full_heal":
				return "At %d%% HP: Full heal (once per combat)" % hp_percent
			else:
				return "At %d%% HP: %s" % [hp_percent, effect]
		_:
			return "Unknown ability"

func _ensure_readable_color(hex_color: String) -> String:
	"""Ensure a color is bright enough to be readable against a dark background.
	Lightens dark colors while preserving their hue."""
	if hex_color == "":
		return hex_color

	var color = Color(hex_color)
	# Calculate perceived brightness
	var brightness = (color.r * 0.299 + color.g * 0.587 + color.b * 0.114)

	# If too dark, lighten it while keeping the hue
	if brightness < 0.4:
		# Convert to HSV, boost value (brightness), convert back
		var h = color.h
		var s = color.s
		var v = color.v

		# Boost the value to make it readable (minimum 0.6)
		v = max(0.6, v + (0.6 - brightness))
		# Slightly reduce saturation for very dark colors to make them pop more
		if brightness < 0.2:
			s = min(s, 0.7)

		color = Color.from_hsv(h, s, v)

	return "#" + color.to_html(false)

func _get_contrasting_bg_color(hex_color: String, hex_color2: String = "") -> Color:
	"""Return a consistent dark background for the companion overlay.
	Text colors are lightened separately to ensure readability."""
	# Always use a nice dark background - text colors will be lightened if needed
	return Color(0.05, 0.05, 0.08, 0.92)

func update_companion_art_overlay():
	"""Update the companion art overlay in the bottom-right of the game output."""
	if companion_art_overlay == null:
		return

	var active_companion = character_data.get("active_companion", {})
	if active_companion.is_empty():
		companion_art_overlay.visible = false
		return

	# Get companion info - lighten dark colors for readability
	var variant_color_raw = active_companion.get("variant_color", "#FFFFFF")
	var variant_color2_raw = active_companion.get("variant_color2", "")
	var variant_color = _ensure_readable_color(variant_color_raw)
	var variant_color2 = _ensure_readable_color(variant_color2_raw) if variant_color2_raw != "" else ""
	var variant_pattern = active_companion.get("variant_pattern", "solid")
	var level = active_companion.get("level", 1)
	var companion_name = active_companion.get("name", "Companion")
	var tier = active_companion.get("tier", 1)
	var monster_type = active_companion.get("monster_type", "")

	# Use consistent dark background - colors are already lightened for readability
	var bg_color = _get_contrasting_bg_color(variant_color, variant_color2)
	var style = companion_art_overlay.get_theme_stylebox("normal")
	if style and style is StyleBoxFlat:
		var new_style = style.duplicate()
		new_style.bg_color = bg_color
		# Add subtle border matching the variant color
		new_style.border_color = Color(variant_color)
		new_style.border_color.a = 0.6
		companion_art_overlay.add_theme_stylebox_override("normal", new_style)

	# Get art using helper function
	var art_lines = _get_companion_art_lines(monster_type, companion_name)

	# Build overlay text - readable header with variant name
	var variant_name = active_companion.get("variant", "Normal")
	var overlay_text = "[center][font_size=14][color=%s]%s[/color] [color=#FFFF00]Lv%d[/color][/font_size]\n[font_size=11][color=%s]%s[/color][/font_size][/center]\n" % [variant_color, companion_name, level, variant_color, variant_name]

	if art_lines.size() > 0:
		# Join all art lines and apply variant color pattern
		var art_str = "\n".join(art_lines)

		# Apply pattern-based coloring for visual variety
		art_str = _recolor_ascii_art_pattern(art_str, variant_color, variant_color2, variant_pattern)

		# Use font_size=2 for tiny art display, centered
		overlay_text += "[center][font_size=2]" + art_str + "[/font_size][/center]"
	else:
		# No art found - show text-only display
		overlay_text += "[center][font_size=7][color=#00FFFF]♦ Active ♦[/color][/font_size][/center]"

	companion_art_overlay.clear()
	companion_art_overlay.append_text(overlay_text)
	companion_art_overlay.visible = true

func hide_companion_art_overlay():
	"""Hide the companion art overlay."""
	if companion_art_overlay:
		companion_art_overlay.visible = false

func _get_companion_art_lines(monster_type: String, companion_name: String) -> Array:
	"""Get ASCII art lines for a companion by monster type or name.
	Handles special variants and name mappings."""
	var art_map = _get_monster_art().get_art_map()
	var lookup_name = monster_type

	# Handle elemental variants - pick Fire or Water Elemental art
	if lookup_name == "Elemental":
		var elemental_variants = ["Fire Elemental", "Water Elemental"]
		lookup_name = elemental_variants[randi() % elemental_variants.size()]

	# Handle siren variants - pick Siren A or Siren B art
	if lookup_name == "Siren":
		var siren_variants = ["Siren A", "Siren B"]
		lookup_name = siren_variants[randi() % siren_variants.size()]

	# Apply name mappings
	var name_mappings = {
		"Wolf": "Dire Wolf",
		"Orc": "Orc Warrior",
		"Young Dragon": "Dragon Wyrmling"
	}
	if name_mappings.has(lookup_name):
		lookup_name = name_mappings[lookup_name]

	# Try to find art by lookup name first, then companion name
	if lookup_name != "" and art_map.has(lookup_name):
		return art_map[lookup_name].duplicate()
	elif art_map.has(companion_name):
		return art_map[companion_name].duplicate()

	return []

# Store original offsets for shake animations
var companion_art_original_offset_left: float = -260.0
var companion_art_original_offset_right: float = -5.0
var game_output_original_offset_left: float = 0.0
var game_output_original_offset_right: float = 0.0
var companion_shake_tween: Tween = null
var game_output_shake_tween: Tween = null

func shake_companion_art():
	"""Shake the companion art overlay left and right when companion attacks."""
	if companion_art_overlay == null or not companion_art_overlay.visible:
		return

	# Kill any existing shake tween and reset to original position
	if companion_shake_tween and companion_shake_tween.is_valid():
		companion_shake_tween.kill()
		# Reset to original position immediately to prevent drift
		companion_art_overlay.offset_left = companion_art_original_offset_left
		companion_art_overlay.offset_right = companion_art_original_offset_right

	var shake_amount = 8.0  # Pixels to shake
	var shake_duration = 0.06  # Duration per shake direction

	companion_shake_tween = create_tween()
	# Shake sequence: right, left, right, left, center
	companion_shake_tween.tween_property(companion_art_overlay, "offset_left", companion_art_original_offset_left + shake_amount, shake_duration)
	companion_shake_tween.parallel().tween_property(companion_art_overlay, "offset_right", companion_art_original_offset_right + shake_amount, shake_duration)
	companion_shake_tween.tween_property(companion_art_overlay, "offset_left", companion_art_original_offset_left - shake_amount, shake_duration)
	companion_shake_tween.parallel().tween_property(companion_art_overlay, "offset_right", companion_art_original_offset_right - shake_amount, shake_duration)
	companion_shake_tween.tween_property(companion_art_overlay, "offset_left", companion_art_original_offset_left + shake_amount * 0.5, shake_duration)
	companion_shake_tween.parallel().tween_property(companion_art_overlay, "offset_right", companion_art_original_offset_right + shake_amount * 0.5, shake_duration)
	companion_shake_tween.tween_property(companion_art_overlay, "offset_left", companion_art_original_offset_left - shake_amount * 0.5, shake_duration)
	companion_shake_tween.parallel().tween_property(companion_art_overlay, "offset_right", companion_art_original_offset_right - shake_amount * 0.5, shake_duration)
	# Return to original
	companion_shake_tween.tween_property(companion_art_overlay, "offset_left", companion_art_original_offset_left, shake_duration)
	companion_shake_tween.parallel().tween_property(companion_art_overlay, "offset_right", companion_art_original_offset_right, shake_duration)

func shake_game_output():
	"""Shake the game output when monster attacks."""
	if game_output == null:
		return

	# Kill any existing shake tween and reset to original position
	if game_output_shake_tween and game_output_shake_tween.is_valid():
		game_output_shake_tween.kill()
		# Reset to original position immediately to prevent drift
		game_output.offset_left = game_output_original_offset_left
		game_output.offset_right = game_output_original_offset_right

	var shake_amount = 6.0  # Pixels to shake (slightly less than companion)
	var shake_duration = 0.05  # Duration per shake direction

	game_output_shake_tween = create_tween()
	# Shake sequence: right, left, right, left, center
	game_output_shake_tween.tween_property(game_output, "offset_left", game_output_original_offset_left + shake_amount, shake_duration)
	game_output_shake_tween.parallel().tween_property(game_output, "offset_right", game_output_original_offset_right + shake_amount, shake_duration)
	game_output_shake_tween.tween_property(game_output, "offset_left", game_output_original_offset_left - shake_amount, shake_duration)
	game_output_shake_tween.parallel().tween_property(game_output, "offset_right", game_output_original_offset_right - shake_amount, shake_duration)
	game_output_shake_tween.tween_property(game_output, "offset_left", game_output_original_offset_left + shake_amount * 0.5, shake_duration)
	game_output_shake_tween.parallel().tween_property(game_output, "offset_right", game_output_original_offset_right + shake_amount * 0.5, shake_duration)
	game_output_shake_tween.tween_property(game_output, "offset_left", game_output_original_offset_left - shake_amount * 0.5, shake_duration)
	game_output_shake_tween.parallel().tween_property(game_output, "offset_right", game_output_original_offset_right - shake_amount * 0.5, shake_duration)
	# Return to original
	game_output_shake_tween.tween_property(game_output, "offset_left", game_output_original_offset_left, shake_duration)
	game_output_shake_tween.parallel().tween_property(game_output, "offset_right", game_output_original_offset_right, shake_duration)

func _get_egg_display_name(egg_type: String) -> String:
	"""Get display name for egg type"""
	match egg_type:
		"companion_egg_random":
			return "Common Egg"
		"companion_egg_rare":
			return "Rare Egg"
		"companion_egg_legendary":
			return "Legendary Egg"
		_:
			return egg_type.capitalize().replace("_", " ")

func _refresh_companions_display():
	"""Refresh companion display based on current pending_companion_action state."""
	if pending_companion_action == "release_select":
		game_output.clear()
		display_game("[color=#FF6666]═══════ RELEASE COMPANION ═══════[/color]")
		display_game("")
		display_game("[color=#FFAA00]Select a companion to release (PERMANENTLY DELETE):[/color]")
		display_game("")
		_display_companions_for_release()
	elif pending_companion_action == "inspect_select":
		game_output.clear()
		display_game("[color=#00FFFF]═══════ INSPECT COMPANION ═══════[/color]")
		display_game("")
		display_game("[color=#AAAAAA]Select a companion to inspect (1-%d):[/color]" % min(COMPANIONS_PAGE_SIZE, character_data.get("collected_companions", []).size()))
		display_game("")
		_display_companions_for_selection()
	else:
		display_companions()

func close_companions():
	"""Close companions menu and return to More menu"""
	companions_mode = false
	companions_page = 0
	more_mode = true
	display_more_menu()
	update_action_bar()

func activate_companion_by_index(index: int):
	"""Activate a companion from sorted companion list by index (or select for release)"""
	# Use sorted list (same order as displayed) instead of raw unsorted array
	var sorted_list = get_meta("sorted_companions", [])
	if sorted_list.is_empty():
		sorted_list = character_data.get("collected_companions", [])
	# Adjust index for pagination
	var actual_index = companions_page * COMPANIONS_PAGE_SIZE + index
	if actual_index < 0 or actual_index >= sorted_list.size():
		return

	var companion = sorted_list[actual_index]

	# Handle release selection mode
	if pending_companion_action == "release_select":
		# Check if trying to release active companion
		var active_companion = character_data.get("active_companion", {})
		if not active_companion.is_empty() and active_companion.get("id", "") == companion.get("id", ""):
			display_game("[color=#FF0000]Cannot release your active companion! Dismiss it first.[/color]")
			return

		release_target_companion = companion
		pending_companion_action = "release_confirm"
		game_output.clear()
		var comp_name = companion.get("name", "Unknown")
		var variant = companion.get("variant", "Normal")
		var variant_color = companion.get("variant_color", "#FFFFFF")
		var comp_level = companion.get("level", 1)
		display_game("[color=#FF0000]═══════ CONFIRM RELEASE ═══════[/color]")
		display_game("")
		display_game("[color=#FFAA00]Are you sure you want to PERMANENTLY release:[/color]")
		display_game("")
		display_game("  [color=%s]%s %s[/color] [color=#AAAAAA]Level %d[/color]" % [variant_color, variant, comp_name, comp_level])
		display_game("")
		display_game("[color=#FF6666]This action cannot be undone![/color]")
		display_game("")
		update_action_bar()
		return

	# Handle inspect selection mode
	if pending_companion_action == "inspect_select":
		inspecting_companion = companion
		pending_companion_action = "inspect"
		display_companion_inspection(companion)
		update_action_bar()
		return

	# Normal activation - send ID to uniquely identify companion (handles duplicates)
	var companion_id = companion.get("id", "")
	var companion_name = companion.get("name", "Unknown")
	if companion_id != "":
		send_to_server({"type": "activate_companion", "id": companion_id})
		display_game("[color=#00FFFF]Activating %s...[/color]" % companion_name)

func _display_companions_for_release():
	"""Display companions list for release selection"""
	var collected = character_data.get("collected_companions", [])
	var active_companion = character_data.get("active_companion", {})

	if collected.size() == 0:
		display_game("[color=#808080]No companions to release.[/color]")
		return

	# Use sorted order consistent with main companion display
	var sorted_list = _sort_companions(collected)
	set_meta("sorted_companions", sorted_list)

	var total_pages = int(ceil(float(sorted_list.size()) / float(COMPANIONS_PAGE_SIZE)))
	companions_page = clamp(companions_page, 0, max(0, total_pages - 1))
	var start_idx = companions_page * COMPANIONS_PAGE_SIZE
	var end_idx = min(start_idx + COMPANIONS_PAGE_SIZE, sorted_list.size())

	display_game("[color=#808080]Page %d/%d[/color]" % [companions_page + 1, total_pages])
	display_game("")

	for i in range(start_idx, end_idx):
		var companion = sorted_list[i]
		var comp_name = companion.get("name", "Unknown")
		var comp_id = companion.get("id", "")
		var comp_level = companion.get("level", 1)
		var variant = companion.get("variant", "Normal")
		var variant_color = companion.get("variant_color", "#FFFFFF")
		var is_active = not active_companion.is_empty() and active_companion.get("id", "") == comp_id
		var rarity_info = _get_variant_rarity_info(variant)

		var display_num = (i - start_idx) + 1
		if is_active:
			display_game("  [%d] [color=#808080]%s Lv.%d (%s) - ACTIVE (cannot release)[/color]" % [display_num, comp_name, comp_level, variant])
		else:
			display_game("  [%d] [color=%s][%s][/color] [color=%s]%s %s[/color] [color=#AAAAAA]Lv.%d[/color]" % [display_num, rarity_info.color, rarity_info.tier, variant_color, variant, comp_name, comp_level])

func _display_companions_for_selection():
	"""Display companions list for inspect selection"""
	var collected = character_data.get("collected_companions", [])
	var active_companion = character_data.get("active_companion", {})

	if collected.size() == 0:
		display_game("[color=#808080]No companions to inspect.[/color]")
		return

	# Use sorted order consistent with main companion display
	var sorted_list = _sort_companions(collected)
	set_meta("sorted_companions", sorted_list)

	var total_pages = int(ceil(float(sorted_list.size()) / float(COMPANIONS_PAGE_SIZE)))
	companions_page = clamp(companions_page, 0, max(0, total_pages - 1))
	var start_idx = companions_page * COMPANIONS_PAGE_SIZE
	var end_idx = min(start_idx + COMPANIONS_PAGE_SIZE, sorted_list.size())

	display_game("[color=#808080]Page %d/%d[/color]" % [companions_page + 1, total_pages])
	display_game("")

	for i in range(start_idx, end_idx):
		var companion = sorted_list[i]
		var comp_name = companion.get("name", "Unknown")
		var comp_id = companion.get("id", "")
		var comp_level = companion.get("level", 1)
		var variant = companion.get("variant", "Normal")
		var variant_color = companion.get("variant_color", "#FFFFFF")
		var is_active = not active_companion.is_empty() and active_companion.get("id", "") == comp_id
		var rarity_info = _get_variant_rarity_info(variant)

		var display_num = (i - start_idx) + 1
		var active_marker = "[color=#00FFFF]★[/color] " if is_active else ""
		display_game("  [%d] %s[color=%s][%s][/color] [color=%s]%s %s[/color] [color=#AAAAAA]Lv.%d[/color]" % [display_num, active_marker, rarity_info.color, rarity_info.tier, variant_color, variant, comp_name, comp_level])

func display_companion_inspection(companion: Dictionary):
	"""Display detailed info about a companion including abilities, with art on the right"""
	game_output.clear()

	var comp_name = companion.get("name", "Unknown")
	var comp_level = companion.get("level", 1)
	var comp_xp = companion.get("xp", 0)
	var comp_tier = companion.get("tier", 1)
	var variant = companion.get("variant", "Normal")
	var variant_color_raw = companion.get("variant_color", "#FFFFFF")
	var variant_color2_raw = companion.get("variant_color2", "")
	var variant_pattern = companion.get("variant_pattern", "solid")
	var variant_color = _ensure_readable_color(variant_color_raw)
	var variant_color2 = _ensure_readable_color(variant_color2_raw) if variant_color2_raw != "" else ""
	var bonuses = companion.get("bonuses", {})
	var monster_type = companion.get("monster_type", comp_name)

	# Get variant multiplier and rarity info
	var variant_mult = _get_variant_multiplier(variant)
	var variant_bonus_text = ""
	if variant_mult > 1.0:
		variant_bonus_text = " [color=#FFD700](+%d%% stats)[/color]" % int((variant_mult - 1.0) * 100)
	var rarity_info = _get_variant_rarity_info(variant)

	display_game("[color=#00FFFF]═══════ COMPANION DETAILS ═══════[/color]")
	display_game("")

	# Build left side content (info)
	var info_lines = []
	info_lines.append("[color=%s][%s][/color] [color=%s]%s %s[/color]%s" % [rarity_info.color, rarity_info.tier, variant_color, variant, comp_name, variant_bonus_text])
	info_lines.append("[color=#AAAAAA]Level %d | Tier %d[/color]" % [comp_level, comp_tier])
	info_lines.append("")

	# XP Progress
	var xp_to_next = int(pow(comp_level + 1, 2.0) * 15)
	if comp_level < 10000:
		var xp_percent = int((float(comp_xp) / float(xp_to_next)) * 100) if xp_to_next > 0 else 0
		var bar_length = 15
		var filled = int(bar_length * xp_percent / 100)
		var xp_bar = "[" + "█".repeat(filled) + "░".repeat(bar_length - filled) + "]"
		info_lines.append("[color=#00FF00]XP: %s %d%%[/color]" % [xp_bar, xp_percent])
	else:
		info_lines.append("[color=#FFD700]MAX LEVEL[/color]")
	info_lines.append("")

	# Combat Damage Estimation
	info_lines.append("[color=#FF6666]── Combat Damage ──[/color]")
	var player_level = character_data.get("level", 1)
	var damage_est = _estimate_companion_damage(comp_tier, player_level, bonuses, comp_level, variant_mult)
	info_lines.append("  [color=#FF6666]%d - %d[/color] per turn" % [damage_est.min, damage_est.max])
	info_lines.append("")

	# Combat Bonuses
	info_lines.append("[color=#808080]── Combat Bonuses ──[/color]")
	var bonus_parts = _get_companion_bonus_parts_with_variant(bonuses, variant_mult)
	if bonus_parts.size() > 0:
		info_lines.append("  %s" % ", ".join(bonus_parts))
	else:
		info_lines.append("  [color=#808080]None[/color]")

	# Get companion artwork
	var art_lines = _get_companion_art_lines(monster_type, comp_name)
	var art_str = ""
	if art_lines.size() > 0:
		art_str = "\n".join(art_lines)
		art_str = _recolor_ascii_art_pattern(art_str, variant_color, variant_color2, variant_pattern)

	# Display side-by-side using table if art exists
	if art_str != "":
		var info_content = "\n".join(info_lines)
		# Use table with 2 columns: info on left, art on right (scaled)
		var art_font_size = int(5 * ui_scale_monster_art)
		if art_font_size < 1:
			art_font_size = 1
		display_game("[table=2][cell]%s[/cell][cell][font_size=%d]%s[/font_size][/cell][/table]" % [info_content, art_font_size, art_str])
	else:
		# No art - just display info normally
		for line in info_lines:
			display_game(line)

	display_game("")

	# Abilities Section - show all abilities with unlock requirements (full width below)
	display_game("[color=#A335EE]── Abilities ──[/color]")
	display_game("")

	# Get monster-specific abilities from drop_tables
	var abilities = _get_companion_abilities_for_display(monster_type, comp_level, variant_mult)

	# Passive ability (always active)
	display_game("[color=#00BFFF]Passive (Always Active):[/color]")
	if abilities.has("passive"):
		var passive = abilities.passive
		var passive_desc = _format_ability_for_inspection(passive, "passive")
		display_game("  [color=#00FF00]%s[/color]" % passive.get("name", "Unknown"))
		display_game("  %s" % passive_desc)
	else:
		display_game("  [color=#808080]None[/color]")
	display_game("")

	# Active ability (unlocks at level 5)
	display_game("[color=#FFA500]Active (Unlocks Lv.5):[/color]")
	if abilities.has("active"):
		var active = abilities.active
		var unlocked = comp_level >= 5
		var active_desc = _format_ability_for_inspection(active, "active")
		if unlocked:
			display_game("  [color=#00FF00]%s[/color]" % active.get("name", "Unknown"))
			display_game("  %s" % active_desc)
		else:
			display_game("  [color=#808080]%s[/color] [color=#666666](Locked - Lv.5)[/color]" % active.get("name", "Unknown"))
			display_game("  [color=#666666]%s[/color]" % active_desc)
	else:
		display_game("  [color=#808080]None[/color]")
	display_game("")

	# Threshold ability (unlocks at level 15)
	display_game("[color=#FF4444]Threshold (Unlocks Lv.15):[/color]")
	if abilities.has("threshold"):
		var threshold = abilities.threshold
		var unlocked = comp_level >= 15
		var threshold_desc = _format_ability_for_inspection(threshold, "threshold")
		if unlocked:
			display_game("  [color=#FFD700]%s[/color]" % threshold.get("name", "Unknown"))
			display_game("  %s" % threshold_desc)
		else:
			display_game("  [color=#808080]%s[/color] [color=#666666](Locked - Lv.15)[/color]" % threshold.get("name", "Unknown"))
			display_game("  [color=#666666]%s[/color]" % threshold_desc)
	else:
		display_game("  [color=#808080]None[/color]")

	display_game("")
	display_game("[color=#FFD700]══════════════════════════════[/color]")

func _get_companion_abilities_for_display(monster_type: String, level: int, variant_mult: float) -> Dictionary:
	"""Get companion abilities for display (client-side lookup).
	Uses COMPANION_MONSTER_ABILITIES for monster-specific abilities with level scaling."""
	var result = {}

	# Check for monster-specific abilities first
	if COMPANION_MONSTER_ABILITIES.has(monster_type):
		var monster_abilities = COMPANION_MONSTER_ABILITIES[monster_type]

		# Scale passive ability
		if monster_abilities.has("passive"):
			result["passive"] = _scale_ability_for_display(monster_abilities.passive, level, variant_mult)

		# Scale active ability
		if monster_abilities.has("active"):
			result["active"] = _scale_ability_for_display(monster_abilities.active, level, variant_mult)

		# Scale threshold ability
		if monster_abilities.has("threshold"):
			result["threshold"] = _scale_ability_for_display(monster_abilities.threshold, level, variant_mult)
	else:
		# Fallback: Generic abilities based on monster type name
		result["passive"] = {"name": "%s's Presence" % monster_type, "effect": "attack", "value": int(3 * variant_mult), "description": "+Attack damage"}
		result["active"] = {"name": "%s Strike" % monster_type, "effect": "bonus_damage", "chance": 15, "value": int(10 * variant_mult), "description": "Chance for bonus damage"}
		result["threshold"] = {"name": "%s's Fury" % monster_type, "effect": "attack_buff", "hp_percent": 30, "value": int(15 * variant_mult), "description": "Attack boost when low HP"}

	return result

func _scale_ability_for_display(ability_template: Dictionary, level: int, variant_mult: float) -> Dictionary:
	"""Scale an ability's values based on companion level and variant multiplier for display."""
	var scaled = ability_template.duplicate(true)

	# Scale base values with level
	if scaled.has("base") and scaled.has("scaling"):
		var base_value = scaled.base * variant_mult
		scaled["value"] = int(base_value + (scaled.scaling * level * variant_mult))

	# Scale secondary effects
	if scaled.has("base2") and scaled.has("scaling2"):
		var base_value2 = scaled.base2 * variant_mult
		scaled["value2"] = int(base_value2 + (scaled.scaling2 * level * variant_mult))

	# Scale damage values
	if scaled.has("base_damage") and scaled.has("damage_scaling"):
		var base_dmg = scaled.base_damage * variant_mult
		scaled["damage"] = int(base_dmg + (scaled.damage_scaling * level * variant_mult))

	# Scale chance values (cap at 80%)
	if scaled.has("base_chance") and scaled.has("chance_scaling"):
		var base_chance = scaled.base_chance * variant_mult
		scaled["chance"] = mini(int(base_chance + (scaled.chance_scaling * level)), 80)

	return scaled

func _format_ability_for_inspection(ability: Dictionary, ability_type: String) -> String:
	"""Format an ability dictionary for display in inspection.
	Uses the 'effect' field from COMPANION_MONSTER_ABILITIES format."""

	# First check if ability has a description field - use it directly
	if ability.has("description"):
		var desc = ability.description
		var value = ability.get("value", 0)
		var chance = ability.get("chance", 0)
		var damage = ability.get("damage", ability.get("value", 0))
		var hp_percent = ability.get("hp_percent", 30)

		# Append scaled values to description
		var effect = ability.get("effect", "")
		match effect:
			"attack", "defense", "speed", "gold_find", "regen":
				return "%s (+%d)" % [desc, value]
			"bonus_damage":
				if chance > 0:
					return "%s (%d%% chance, %d dmg)" % [desc, chance, damage]
				return "%s (+%d dmg)" % [desc, damage]
			"bleed", "poison":
				return "%s (%d%% chance, %d dmg/turn)" % [desc, chance, damage]
			"enemy_miss":
				if chance > 0:
					return "%s (%d%% chance)" % [desc, chance]
				return desc
			"stun":
				return "%s (%d%% chance)" % [desc, chance]
			"crit":
				return "%s (%d%% chance)" % [desc, chance]
			"attack_buff", "defense_buff", "speed_buff", "all_buff":
				return "%s (+%d%% below %d%% HP)" % [desc, value, hp_percent]
			"flee_bonus":
				return "%s (+%d%% below %d%% HP)" % [desc, value, hp_percent]
			"heal":
				return "%s (%d HP below %d%% HP)" % [desc, value, hp_percent]
			"absorb", "damage_reduction":
				return "%s (%d%% below %d%% HP)" % [desc, value, hp_percent]
			_:
				if value > 0:
					return "%s (+%d)" % [desc, value]
				return desc

	# Fallback for legacy format
	var atype = ability.get("type", ability.get("effect", "unknown"))
	var value = ability.get("value", 0)
	var chance = ability.get("chance", 0)

	match atype:
		"attack", "defense", "speed":
			return "+%d %s" % [value, atype.capitalize()]
		"bonus_damage":
			if chance > 0:
				return "%d%% chance for %d bonus damage" % [chance, value]
			return "+%d bonus damage" % value
		"enemy_miss":
			return "%d%% chance to make enemy miss" % chance
		"stun":
			return "%d%% chance to stun" % chance
		"heal":
			return "Heals %d HP" % value
		_:
			return "Special ability"

func display_eggs():
	"""Display the eggs page with ASCII art"""
	game_output.clear()

	var eggs = character_data.get("incubating_eggs", [])

	display_game("[color=#FFAA00]═══════ INCUBATING EGGS ═══════[/color]")
	display_game("")

	if eggs.size() == 0:
		display_game("[color=#808080]No eggs incubating.[/color]")
		display_game("")
		display_game("[color=#808080]Find companion eggs in dungeon treasure chests![/color]")
		display_game("")
		display_game("[color=#FFD700]══════════════════════════════[/color]")
		return

	var total_pages = int(ceil(float(eggs.size()) / float(EGGS_PAGE_SIZE)))
	eggs_page = clamp(eggs_page, 0, max(0, total_pages - 1))
	var start_idx = eggs_page * EGGS_PAGE_SIZE
	var end_idx = min(start_idx + EGGS_PAGE_SIZE, eggs.size())

	display_game("[color=#808080]Eggs %d-%d of %d | Page %d/%d[/color]" % [start_idx + 1, end_idx, eggs.size(), eggs_page + 1, total_pages])
	display_game("")

	for i in range(start_idx, end_idx):
		var egg = eggs[i]
		var egg_name = egg.get("companion_name", "Unknown")
		var variant = egg.get("variant", "Normal")
		var variant_color = egg.get("variant_color", "#FFAA00")
		var variant_color2 = egg.get("variant_color2", "")
		var variant_pattern = egg.get("variant_pattern", "solid")
		var tier = egg.get("tier", 1)
		var is_frozen = egg.get("frozen", false)
		var rarity_info = _get_variant_rarity_info(variant)

		# Support both raw format (steps_remaining, hatch_steps) and client format (steps_taken, steps_required)
		var required = egg.get("steps_required", egg.get("hatch_steps", 1000))
		var steps = egg.get("steps_taken", 0)
		if steps == 0 and egg.has("steps_remaining") and egg.has("hatch_steps"):
			steps = egg.get("hatch_steps", 1000) - egg.get("steps_remaining", 1000)
		var progress = int((float(steps) / float(required)) * 100) if required > 0 else 0

		# Display ASCII egg art with variant colors and pattern (scaled)
		var egg_art = MonsterArt.get_egg_art(variant, variant_color, variant_color2, variant_pattern, ui_scale_monster_art)
		display_game(egg_art)

		# Display egg info below the art with rarity tag and frozen status
		var frozen_str = " [color=#00BFFF][FROZEN][/color]" if is_frozen else ""
		var display_num = (i - start_idx) + 1
		display_game("  [%d] [color=%s][%s][/color] [color=%s]%s %s Egg[/color] [color=#808080](Tier %d)[/color]%s" % [display_num, rarity_info.color, rarity_info.tier, variant_color, variant, egg_name, tier, frozen_str])

		# Progress bar
		var bar_length = 16
		var filled = int(bar_length * progress / 100)
		var progress_bar = "[" + "█".repeat(filled) + "░".repeat(bar_length - filled) + "]"
		if is_frozen:
			display_game("  [color=#00BFFF]%s %d%% (%d/%d steps) - PAUSED[/color]" % [progress_bar, progress, steps, required])
		else:
			display_game("  [color=#AAAAAA]%s %d%% (%d/%d steps)[/color]" % [progress_bar, progress, steps, required])
		display_game("")

	display_game("[color=#808080]Walk around to incubate eggs! Frozen eggs won't progress.[/color]")
	display_game("")
	display_game("[color=#FFD700]══════════════════════════════[/color]")

func _get_status_effects_text() -> String:
	"""Generate status effects section for character status display"""
	var lines = []

	# Cloak status (special mode)
	if character_data.get("cloak_active", false):
		lines.append("  [color=#9932CC]Cloaked[/color] - Invisible to monsters (drains resource on movement)")

	# Poison (debuff)
	if character_data.get("poison_active", false):
		var poison_dmg = character_data.get("poison_damage", 0)
		var poison_turns = character_data.get("poison_turns_remaining", 0)
		lines.append("  [color=#FF00FF]Poisoned[/color] - %d damage/round, %d rounds remaining" % [poison_dmg, poison_turns])

	# Blindness (debuff)
	if character_data.get("blind_active", false):
		var blind_turns = character_data.get("blind_turns_remaining", 0)
		lines.append("  [color=#808080]Blinded[/color] - reduced vision & accuracy, %d rounds remaining" % blind_turns)

	# Active combat buffs (round-based)
	var active_buffs = character_data.get("active_buffs", [])
	for buff in active_buffs:
		var buff_type = buff.get("type", "")
		var buff_value = buff.get("value", 0)
		var buff_dur = buff.get("duration", 0)
		var display_name = _get_buff_display_name(buff_type)
		var color = _get_buff_color(buff_type)
		if buff_value > 0:
			lines.append("  [color=%s]%s +%d[/color] - %d rounds remaining" % [color, display_name, buff_value, buff_dur])
		else:
			lines.append("  [color=%s]%s[/color] - %d rounds remaining" % [color, display_name, buff_dur])

	# Persistent buffs (battle-based)
	var persistent_buffs = character_data.get("persistent_buffs", [])
	for buff in persistent_buffs:
		var buff_type = buff.get("type", "")
		var buff_value = buff.get("value", 0)
		var battles = buff.get("battles_remaining", 0)
		var display_name = _get_buff_display_name(buff_type)
		var color = _get_buff_color(buff_type)
		if buff_value > 0:
			lines.append("  [color=%s]%s +%d%%[/color] - %d battles remaining" % [color, display_name, buff_value, battles])
		else:
			lines.append("  [color=%s]%s[/color] - %d battles remaining" % [color, display_name, battles])

	if lines.is_empty():
		return ""

	return "[color=#AAFFAA]Active Effects:[/color]\n" + "\n".join(lines)

func _get_class_passive(class_type: String) -> Dictionary:
	"""Get class passive info (client-side mirror of Character.get_class_passive)"""
	match class_type:
		"Fighter":
			return {"name": "Tactical Discipline", "description": "20% reduced stamina costs, +15% defense. Affects: All abilities", "color": "#C0C0C0"}
		"Barbarian":
			return {"name": "Blood Rage", "description": "+3% dmg per 10% HP missing (max +30%), +25% ability cost. Affects: All attacks", "color": "#8B0000"}
		"Paladin":
			return {"name": "Divine Favor", "description": "Heal 3% HP/round, +25% vs undead/demons. Affects: Combat regen, attacks vs undead", "color": "#FFD700"}
		"Wizard":
			return {"name": "Arcane Precision", "description": "+15% spell damage, +10% spell crit. Affects: All attacks and spells", "color": "#4169E1"}
		"Sorcerer":
			return {"name": "Chaos Magic", "description": "25% double damage, 5% backfire. Affects: ALL attacks and abilities", "color": "#9400D3"}
		"Sage":
			return {"name": "Mana Mastery", "description": "25% reduced mana costs, +50% Meditate. Affects: All spells, Meditate", "color": "#20B2AA"}
		"Thief":
			return {"name": "Backstab", "description": "+15% base crit, +50% crit damage (2x total). Affects: All attacks", "color": "#2F4F4F"}
		"Ranger":
			return {"name": "Hunter's Mark", "description": "+25% dmg vs beasts, +30% gold/XP. Affects: Beast attacks, all rewards", "color": "#228B22"}
		"Ninja":
			return {"name": "Shadow Step", "description": "+40% flee chance, no damage on failed flee. Affects: Flee action only", "color": "#191970"}
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
		"flee_bonus": 0,
		"stamina_regen": 0  # Warrior gear
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

		# Apply diminishing returns for items above level 50 (matches server character.gd)
		var effective_level = _get_effective_item_level_for_display(item_level)

		# Base bonus scales with effective item level, rarity, and wear
		var base_bonus = int(effective_level * rarity_mult * wear_penalty)

		# STEP 1: Apply base item type bonuses (all items get these)
		# Matches _compute_item_bonuses and server character.gd NERFED values exactly
		if "weapon" in item_type:
			bonuses.attack += int(base_bonus * 1.5)  # Nerfed from 2.5x
			bonuses.strength += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		elif "armor" in item_type:
			bonuses.defense += int(base_bonus * 1.0)  # Nerfed from 1.75x
			bonuses.constitution += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			bonuses.max_hp += int(base_bonus * 1.5)  # Nerfed from 2.5x
		elif "helm" in item_type:
			bonuses.defense += int(base_bonus * 0.6)  # Nerfed from 1.0x
			bonuses.wisdom += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "shield" in item_type:
			bonuses.defense += max(1, int(base_bonus * 0.4)) if base_bonus > 0 else 0
			bonuses.max_hp += int(base_bonus * 2.0)  # Nerfed from 4x
			bonuses.constitution += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "ring" in item_type:
			bonuses.attack += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.dexterity += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			bonuses.intelligence += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "amulet" in item_type:
			bonuses.max_mana += int(base_bonus * 1.0)  # Nerfed from 1.75x
			bonuses.wisdom += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			bonuses.wits += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "boots" in item_type:
			bonuses.speed += int(base_bonus * 0.6)  # Nerfed from 1.0x
			bonuses.dexterity += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			bonuses.defense += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0

		# STEP 2: Apply class-specific gear bonuses (IN ADDITION to base type bonuses)
		if "ring_arcane" in item_type:
			# Arcane ring (Mage): extra INT + mana_regen
			bonuses.intelligence += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.mana_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "ring_shadow" in item_type:
			# Shadow ring (Trickster): extra WITS + energy_regen
			bonuses.wits += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.energy_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "amulet_mystic" in item_type:
			# Mystic amulet (Mage): extra max_mana + meditate_bonus
			bonuses.max_mana += base_bonus
			bonuses.meditate_bonus += max(1, int(item_level / 2)) if item_level > 0 else 0
		elif "amulet_evasion" in item_type:
			# Evasion amulet (Trickster): extra speed + flee_bonus
			bonuses.speed += base_bonus
			bonuses.flee_bonus += max(1, int(item_level / 3)) if item_level > 0 else 0
		elif "boots_swift" in item_type:
			# Swift boots (Trickster): extra Speed + WITS + energy_regen
			bonuses.speed += int(base_bonus * 0.5)
			bonuses.wits += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.energy_regen += max(1, int(base_bonus * 0.1)) if base_bonus > 0 else 0
		elif "weapon_warlord" in item_type:
			# Warlord weapon (Warrior): extra stamina_regen
			bonuses.stamina_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "shield_bulwark" in item_type:
			# Bulwark shield (Warrior): extra stamina_regen
			bonuses.stamina_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0

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
		if affixes.has("speed_bonus"):
			bonuses.speed += int(affixes.speed_bonus * wear_penalty)

	return bonuses

func _get_rarity_multiplier_for_status(rarity: String) -> float:
	"""Get multiplier for item rarity - NERFED values to match server"""
	match rarity:
		"common": return 1.0
		"uncommon": return 1.2
		"rare": return 1.4
		"epic": return 1.7
		"legendary": return 2.0
		"artifact": return 2.5
		_: return 1.0

func show_help():
	# Clear output before showing help
	game_output.clear()

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

	var help_text = """[b][color=#FF6666]⚠ PERMADEATH ENABLED - Death is permanent![/color][/b]
[color=#808080]Tip: Use [/color][color=#00FFFF]/search <term>[/color][color=#808080] to find specific topics (e.g., /search warrior, /search flee)[/color]

[b][color=#FFD700]══ GETTING STARTED ══[/color][/b]
[color=#FF6666]▸ WARRIOR[/color] - Straightforward melee. High HP, steady damage. [color=#808080]Focus:[/color] [color=#FF6666]STR[/color] (attack) + [color=#66FF66]CON[/color] (HP/defense)
  Start hunting immediately. Use Power Strike for damage. War Cry when hurt. Tank and outlast enemies.
  [color=#C0C0C0]Fighter[/color]=safe, [color=#8B0000]Barbarian[/color]=risky/high dmg, [color=#FFD700]Paladin[/color]=self-healing. [color=#808080]Races: Dwarf(survive), Orc(damage), Ogre(healing)[/color]

[color=#66FFFF]▸ MAGE[/color] - Powerful spells, resource management. [color=#808080]Focus:[/color] [color=#FF66FF]INT[/color] (spell power) + [color=#FFFF66]WIS[/color] (mana pool/resist)
  Use Magic Bolt to kill - costs mana but deals INT-scaled damage. Meditate to recover HP+mana.
  Mages regen 2%% mana/round (Sage 3%%). [color=#4169E1]Wizard[/color]=reliable, [color=#9400D3]Sorcerer[/color]=gambler, [color=#20B2AA]Sage[/color]=efficient. [color=#808080]Races: Elf(mana+resist), Gnome(cost reduction)[/color]

[color=#66FF66]▸ TRICKSTER[/color] - Tactical gameplay, many options. [color=#808080]Focus:[/color] [color=#FFA500]WIT[/color] (abilities) + [color=#66FFFF]DEX[/color] (crit/flee)
  Use Outsmart vs dumb monsters (free win!). Analyze to learn stats. Flee if outmatched.
  [color=#2F4F4F]Thief[/color]=crits, [color=#228B22]Ranger[/color]=rewards, [color=#191970]Ninja[/color]=escape artist. [color=#808080]Races: Halfling(gold+dodge), Gnome(costs)[/color]

[b][color=#FFD700]══ WHAT STATS DO ══[/color][/b]
[color=#FF6666]STR[/color] [color=#808080]Strength[/color]  - [color=#FFFFFF]+2%% attack damage per point[/color] | Contributes to Stamina pool
[color=#66FF66]CON[/color] [color=#808080]Constitution[/color] - [color=#FFFFFF]+5 max HP per point[/color] | +0.5 defense per point | Contributes to Stamina pool
[color=#66FFFF]DEX[/color] [color=#808080]Dexterity[/color] - [color=#FFFFFF]+1%% hit, +2%% flee, -1%% enemy hit per 5 DEX (max 30%% dodge)[/color] | +0.5%% crit | Energy pool
[color=#FF66FF]INT[/color] [color=#808080]Intelligence[/color] - [color=#FFFFFF]+3%% spell damage per point[/color] | Contributes to Mana pool
[color=#FFFF66]WIS[/color] [color=#808080]Wisdom[/color] - [color=#FFFFFF]Increases mana pool[/color] | Resists enemy abilities (curse, drain, etc.)
[color=#FFA500]WIT[/color] [color=#808080]Wits[/color] - [color=#FFFFFF]Outsmart: 15×log₂(WIT/10) bonus[/color] | Contributes to Energy pool

[b][color=#FFD700]══ RACES ══[/color][/b]
[color=#FFFFFF]Human[/color]=+10%%XP | [color=#66FF99]Elf[/color]=+50%%poison res,+20%%magic res,+25%%mana | [color=#FFA366]Dwarf[/color]=25%%survive lethal@1HP | [color=#8B4513]Ogre[/color]=2x all healing
[color=#D2691E]Halfling[/color]=+10%%dodge,+15%%gold | [color=#556B2F]Orc[/color]=+20%%dmg below 50%%HP | [color=#DDA0DD]Gnome[/color]=-15%%ability costs | [color=#708090]Undead[/color]=curse immune,poison heals

[b][color=#FFD700]══ BASICS ══[/color][/b]
[color=#00FFFF]Keys:[/color] [Esc]=Mode | [NUMPAD]=Move | [%s]=Primary | [%s][%s][%s][%s]=Quick | [%s][%s][%s][%s]=Extra
[color=#00FFFF]Cmds:[/color] /inventory ([%s]) | /abilities ([%s]) | /who | /examine <name> | /help | /clear
[color=#00FFFF]Map:[/color] [color=#FF6600]![/color]=Danger [color=#FFFF00]P[/color]=Post [color=#FFD700]$[/color]=Merchant [color=#00FF00]@[/color]=You

[b][color=#FFD700]══ CLASS SPECIALIZATIONS ══[/color][/b]
[color=#FF6666]WARRIOR (STR>10, Stamina=STR+CON)[/color]                  [color=#66FFFF]MAGE (INT>10, Mana=INT×3+WIS×1.5)[/color]
  [color=#C0C0C0]Fighter[/color] - 20%% less cost, +15%% DEF               [color=#4169E1]Wizard[/color] - +15%% spell dmg, +10%% crit
  [color=#8B0000]Barbarian[/color] - +3%%dmg/10%%HP lost, +25%% cost        [color=#9400D3]Sorcerer[/color] - 25%% double dmg, 5%% backfire(max 15%%HP)
  [color=#FFD700]Paladin[/color] - 3%%HP/rnd heal, +25%% vs undead          [color=#20B2AA]Sage[/color] - 25%% less cost, +50%% meditate

[color=#66FF66]TRICKSTER (WIT>10, Energy=(WIT+DEX)×0.75)[/color]
  [color=#2F4F4F]Thief[/color] - +10%% crit chance, +35%% crit dmg    [color=#228B22]Ranger[/color] - +25%% vs beasts, +30%% rewards
  [color=#191970]Ninja[/color] - +40%% flee, no dmg on fail | [color=#66FF66]25%% chance Quick Strike (+50%% dmg)[/color]

[b][color=#FFD700]══ COMBAT FORMULAS ══[/color][/b]
[color=#00FFFF]ATK:[/color] STR+weapon × (1+STR×0.02) | [color=#00FFFF]Crit:[/color] 1.5x (5%%+DEX×0.5%%) | [color=#00FFFF]DEF:[/color] DEF/(DEF+100)×60%% reduction
[color=#00FFFF]Lvl Penalty:[/color] -1.5%%/lvl (max-25%%) for attacks vs higher monsters. [color=#FF4444]Monster +4%%/lvl exponential![/color]
[color=#00FFFF]Hit:[/color] 75%%+(DEX-spd) [30-95%%] | [color=#00FFFF]Flee:[/color] 50%%+DEX×2+spd-lvldiff×3 | [color=#00FFFF]Enemy:[/color] 85%%+lvl-DEX/5(max30%%)-spd/2 [40-95%%]
[color=#66FF66]Trickster Dodge:[/color] +WIT/50%% dodge (max 15%%). Combined with DEX dodge, tricksters are harder to hit!
[color=#FF4444]Initiative:[/color] mon_spd/2 - DEX/10 (min 5%%, max 45%%, ambusher +15%%)

[b][color=#FFD700]══ ABILITIES ══[/color][/b]
[color=#00FF00]Buff Advantage:[/color] Defensive abilities (Forcefield, Haste, War Cry, etc) = [color=#FFD700]75%% dodge[/color] on enemy turn!
[color=#9932CC]Cloak[/color](L20): 8%%res/step, no encounters | [color=#AA66FF]Teleport[/color](Mage30/Trick45/War60): 10+dist cost
[color=#FF00FF]All or Nothing[/color]: ~3%% instakill, fail=monster 2x STR/SPD, +0.1%%/use permanent (max 34%%)

[color=#FF6666]WARRIOR ABILITIES[/color] [color=#808080](Stamina = STR + CON)[/color]
  [color=#FFFFFF]L1  Power Strike[/color] [color=#808080](10 stam)[/color] - 2× attack damage, scales with √STR
  [color=#FFFFFF]L10 War Cry[/color]      [color=#808080](15 stam)[/color] - +35%% damage buff for 4 rounds
  [color=#FFFFFF]L25 Shield Bash[/color]  [color=#808080](20 stam)[/color] - 1.5× damage + stun (enemy skips 1 turn)
  [color=#FFFFFF]L25 Fortify[/color]      [color=#808080](25 stam)[/color] - +30%% defense + √STR×3 for 5 rounds
  [color=#FFFFFF]L40 Cleave[/color]       [color=#808080](30 stam)[/color] - 2.5× damage + bleed (20%% STR/rnd, 4 rounds)
  [color=#FFFFFF]L40 Rally[/color]        [color=#808080](35 stam)[/color] - Heal 30+√CON×10 HP, +STR buff for 3 rounds
  [color=#FFFFFF]L60 Berserk[/color]      [color=#808080](40 stam)[/color] - +75-200%% damage (more when hurt), -40%% defense, 4 rounds
  [color=#FFFFFF]L80 Iron Skin[/color]    [color=#808080](35 stam)[/color] - Reduce all damage by 60%% for 4 rounds
  [color=#FFFFFF]L100 Devastate[/color]   [color=#808080](50 stam)[/color] - 5× attack damage, scales with √STR

[color=#66FFFF]MAGE ABILITIES[/color] [color=#808080](Mana = INT×3 + WIS×1.5, regen 2%%/round, Sage 3%%)[/color]
  [color=#FFFFFF]L1  Magic Bolt[/color]   [color=#808080](variable)[/color] - Spend mana to deal damage: mana × (1 + √INT/5). "bolt 50" = spend 50 mana
  [color=#FFFFFF]L10 Forcefield[/color]   [color=#808080](20+2%%)[/color]  - Absorb shield worth 100 + INT×8 HP. Blocks all damage until depleted
  [color=#FFFFFF]L25 Cloak[/color]        [color=#808080](30+3%%)[/color]  - 50%% enemy miss chance for 1 attack
  [color=#FFFFFF]L40 Blast[/color]        [color=#808080](50+5%%)[/color]  - 2× INT-scaled damage + burn (20%% INT/rnd for 3 rounds)
  [color=#FFFFFF]L40 Haste[/color]        [color=#808080](35+3%%)[/color]  - +20+INT/5 speed for 5 rounds (helps hit, dodge, flee)
  [color=#FFFFFF]L60 Paralyze[/color]     [color=#808080](60+6%%)[/color]  - 50%%+INT/2 chance (max 85%%) to stun 1-2 turns
  [color=#FFFFFF]L80 Teleport[/color]     [color=#808080](40)[/color]      - Guaranteed flee from any combat
  [color=#FFFFFF]L100 Meteor[/color]      [color=#808080](100+8%%)[/color] - 3-4× INT-scaled massive damage. Save mana for this!
  [color=#66FFFF]Meditate[/color]         [color=#808080](free)[/color]    - Restore HP + 4%% mana (8%% if already full HP)

[color=#FFA500]TRICKSTER ABILITIES[/color] [color=#808080](Energy = (WIT+DEX)×0.75)[/color]
  [color=#FFFFFF]L1  Analyze[/color]      [color=#808080](5 en)[/color]   - Reveal monster stats + 10%% damage bonus for this fight
  [color=#FFFFFF]L10 Distract[/color]     [color=#808080](15 en)[/color]  - -50%% enemy accuracy for 1 attack
  [color=#FFFFFF]L25 Pickpocket[/color]   [color=#808080](20 en)[/color]  - Steal gold (50+lvl×2)×(1+WIT×5%%). 1-3 attempts per fight
  [color=#FFFFFF]L25 Sabotage[/color]     [color=#808080](25 en)[/color]  - Reduce monster STR/DEF by 15%%+WIT/3 (stacks, max 50%%)
  [color=#FFFFFF]L40 Ambush[/color]       [color=#808080](30 en)[/color]  - 3× damage + 50%% crit chance, scales with √WIT
  [color=#FFFFFF]L50 Gambit[/color]       [color=#808080](35 en)[/color]  - 55%%+WIT/4 chance (max 80%%): 4× damage + bonus gold/gems. Fail = 15%% self-damage
  [color=#FFFFFF]L60 Vanish[/color]       [color=#808080](40 en)[/color]  - Go invisible, skip enemy turn. Next attack auto-crits at 1.5×
  [color=#FFFFFF]L80 Exploit[/color]      [color=#808080](35 en)[/color]  - Deal 15-35%% of monster's max HP as damage (scales with WIT)
  [color=#FFFFFF]L100 Perfect Heist[/color] [color=#808080](50 en)[/color] - 30%%+WIT/2 chance: instant win + 25%% bonus gold. Fail = 20%% self-damage
  [color=#AAAAAA]Outsmart[/color]         [color=#808080](free)[/color]   - 5%%+15×log₂(WIT/10). Capped by monster INT/3. Easy vs brutes, hard vs mages. Fail = free enemy attack

[b][color=#FFD700]══ MONSTER ABILITIES ══[/color][/b]
[color=#AAAAAA]Tiers:[/color] 9 tiers by area level. Lower tier monsters become rarer but still appear in higher areas.
[color=#FF4444]Offense:[/color]
  [color=#FFFFFF]Multi-Strike[/color] - Hits 2-3 times per turn (each hit reduced damage)
  [color=#FFFFFF]Enrage[/color] - +10%% damage per round, stacks up to 10 (max +100%%)
  [color=#FFFFFF]Berserker[/color] - +3%% damage per 10%% HP lost. Deadlier when wounded!
  [color=#FFFFFF]Life Steal[/color] - Heals for portion of damage dealt
  [color=#FFFFFF]Glass Cannon[/color] - 3× damage but only 50%% HP. Kill fast!
  [color=#FFFFFF]Ambusher[/color] - First hit auto-crits, +15%% initiative
  [color=#FF00FF]Poison[/color] - 30%% STR damage/round for 35 rounds. [color=#FF4444]PERSISTS outside combat![/color]
[color=#808080]Debuffs:[/color]
  [color=#FFFFFF]Curse[/color] - -25%% attack for 20 rounds | [color=#FFFFFF]Weakness[/color] - -25%% attack for 20 rounds
  [color=#FFFFFF]Disarm[/color] - Removes weapon damage bonus | [color=#FFFFFF]Blind[/color] - -30%% hit chance, hides HP bar, 15 rounds
  [color=#FFFFFF]Bleed[/color] - Stacking DoT (stack×3 damage/round) | [color=#FFFFFF]Slow[/color] - Reduces flee chance
  [color=#FFFFFF]Charm[/color] - Forces you to hit yourself | [color=#FFFFFF]Drain[/color] - Steals mana/stamina/energy
  [color=#FFFFFF]Buff Destroy[/color] - Removes one active buff | [color=#FFFFFF]Shield Shatter[/color] - Destroys forcefield
[color=#6666FF]Defense:[/color]
  [color=#FFFFFF]Armored[/color] - +50%% defense | [color=#FFFFFF]Ethereal[/color] - 50%% chance to dodge attacks
  [color=#FFFFFF]Regen[/color] - Heals 10%% max HP per round | [color=#FFFFFF]Reflect[/color] - Returns 25%% of damage dealt
  [color=#FFFFFF]Thorns[/color] - Melee attacks hurt you back | [color=#FFFFFF]Disguise[/color] - Hidden stats for first 2 rounds
[color=#FFD700]Special:[/color]
  [color=#FFFFFF]Death Curse[/color] - Deals 10%% max HP damage when killed (can't kill you)
  [color=#FFFFFF]Summoner[/color] - Calls reinforcement monster mid-fight
  [color=#FFFFFF]Corrosive/Sunder[/color] - Damages your gear (repair at wandering blacksmiths!)
  [color=#FFFFFF]XP Steal[/color] - Steals 1-3%% of your XP per hit | [color=#FFFFFF]Item Steal[/color] - 5%% chance to steal equipped item
[color=#00FF00]Loot Abilities:[/color]
  [color=#FFFFFF]Gold Hoarder[/color] - Drops 3× gold | [color=#FFFFFF]Gem Bearer[/color] - Always drops gems
  [color=#FFFFFF]Weapon/Shield Master[/color] - 35%% guaranteed equipment drop
  [color=#FFFFFF]Arcane/Cunning/Warrior Hoarder[/color] - 35%% class-specific gear drop
  [color=#FFFFFF]Wish Granter[/color] - 10%% chance for a wish (gems, gear, buff, stats, or equip upgrade!)
[color=#AAAAAA]Wishes:[/color] Gems | Gear | Buff | Equip Upgrade(×12) | Permanent Stats
[color=#00FFFF]HP Bar:[/color] [color=#FFFFFF]150/200[/color]=Known | [color=#808080]~150/200[/color]=Estimated | [color=#808080]???[/color]=Unknown. Kill to learn!

[b][color=#FFD700]══ ITEMS ══[/color][/b]
[color=#00FFFF]Potions([%s]):[/color] Health/Mana/Stam/Energy restore | STR/DEF/SPD boost | Crit/Lifesteal/Thorns effects
[color=#FF00FF]Buff Scrolls:[/color] Forcefield, Rage, Stone Skin, Haste, Vampirism, Thorns, Precision
[color=#A335EE]Special Scrolls:[/color] Time Stop(skip enemy turn) | Resurrect(T8+,revive once) | Bane(+50%% vs type)
[color=#FFD700]Mystery Items:[/color] Box(random tier/+1 item) | Cursed Coin(50%% 2x gold or lose half)
[color=#00FF00]Stat Tomes(T6+):[/color] [color=#FF69B4]Permanent[/color] +1 to any stat! | [color=#00FF00]Skill Tomes(T7+):[/color] -10%% cost or +15%% dmg
[color=#FF4444]Lock:[/color] Inventory→Lock (key 3) protects items from Sell All, Salvage All, and accidental discard.
[color=#AAAAAA]Wear:[/color] Corrosive/Sunder damages gear. 100%% = BROKEN (no stats). Repair via wandering blacksmiths only!

[b][color=#FFD700]══ GEAR HUNTING ══[/color][/b]
[color=#FF6666]Warrior:[/color] Minotaur(t3), Iron Golem(t6), Death Incarnate(t8) - 35%% drop
[color=#66CCCC]Mage:[/color] Wraith(t3), Lich(t5), Elemental/Sphinx(t6), Elder Lich(t7), Time Weaver(t8) - 35%%
[color=#66FF66]Trickster:[/color] Goblin(t1), Hobgoblin/Spider(t2), Void Walker(t7) - 35%%
[color=#FFD700]Weapon/Shield:[/color] Any Lv5+ monster can spawn as Master (4%%) - 35%% guaranteed drop!
[color=#A335EE]Proc Gear(T6+):[/color] Vampire(lifesteal) | Thunder(shock dmg) | Reflection(reflect) | Slayer(execute<20%%HP)
[color=#FFD700]Synergy*:[/color] Asterisk (*) after affix name = double bonus synergy (e.g., Arcane* Hoarder's Ring)

[color=#AAAAAA]Buff Display:[/color] [color=#FF6666]S[/color]=STR [color=#6666FF]D[/color]=DEF [color=#66FF66]V[/color]=SPD [color=#FFD700]C[/color]=Crit [color=#FF00FF]L[/color]=Life [color=#FF4444]T[/color]=Thorns [color=#00FFFF]F[/color]=Force | #=rounds, #+B=battles

[b][color=#FFD700]══ CRAFTING & GATHERING ══[/color][/b]
[color=#AA66FF]Salvage:[/color] Inventory→Salvage destroys items for [color=#AA66FF]Essence[/color] (ESS). Value = rarity × level. Bonus materials possible!
[color=#00FFFF]Materials:[/color] Inventory→Materials shows your gathered resources by category (ore, wood, fish, etc.)
[color=#FFA500]Fishing([%s]):[/color] At water ([color=#00FFFF]~[/color]), press [%s] to fish. Wait for bite, react with the [color=#00FF00]correct key shown[/color]!
[color=#CD7F32]Mining([%s]):[/color] At ore deposits ([color=#CD7F32]O[/color] on map), press [%s] to mine. Tier 1-9 by distance. T3-5=2 reactions, T6+=3.
[color=#228B22]Logging([%s]):[/color] At dense forests ([color=#228B22]T[/color] on map), press [%s] to chop. Tier 1-6 by distance. Higher skill = better catches.
[color=#808080]Starter nodes:[/color] Ore ([color=#CD7F32]O[/color]) and Trees ([color=#228B22]T[/color]) appear within 35 tiles of origin for new players!
[color=#FF4444]IMPORTANT:[/color] Press the [color=#00FF00]correct button[/color] when prompted! Wrong key = [color=#FF4444]FAIL[/color]. Watch the action bar!
[color=#808080]Skills:[/color] Fishing/Mining/Logging gain XP from catches. Higher skill = faster reaction window + better rare odds.

[b][color=#FFD700]══ WORLD ══[/color][/b]
[color=#00FF00]Posts(58):[/color] Haven(0,10)=spawn | Crossroads(0,0)=throne | Frostgate(0,-100)=boss. Recharge([%s])!
[color=#FFD700]Merchants(110):[/color] [color=#FF4444]$[/color]=Weapon [color=#4488FF]$[/color]=Armor [color=#AA44FF]$[/color]=Jeweler [color=#FFD700]$[/color]=General. Buy/sell/gamble!
[color=#FF6600]![/color]=Hotspot (+50-150%% level) | [color=#9932CC]D[/color]=Dungeon entrance (visible on map when nearby!)
[color=#00FFFF]Quests([%s]):[/color] Kill Any/Type/Level, Hotzone(bonus!), Boss Hunt, Dungeon Clear. Tier scales with player level.
[color=#9932CC]Dungeons([%s]):[/color] 53 unique dungeons — every monster type has one! [color=#FFD700]GUARANTEED[/color] companion egg on completion!
  All monsters match dungeon theme (Orc Stronghold = Orcs). Low level? Get warning, can still enter!
[color=#808080]First Dungeon:[/color] Get "Into the Depths" quest at Haven. Dungeons spawn [color=#00FFFF]30+ tiles[/color] from Crossroads in all directions.

[b][color=#FFD700]══ PROGRESSION ══[/color][/b]
[color=#00FFFF]Gems:[/color] Drop from monsters 5+ levels above you. Sell 1=1000g. Pay for upgrades.
[color=#FFD700]Lucky Finds:[/color] Treasure, [color=#FF69B4]Legendary Adventurer[/color] (perm stat!) - Press [%s] to continue.
[color=#00FFFF]Level Up:[/color] Full heal + stat gains by class (2.5 total/level):
[color=#FF6666]WARRIOR:[/color] [color=#C0C0C0]Fighter[/color]=STR1.25/CON.75/DEX.25/WIT.25 | [color=#8B0000]Barbarian[/color]=STR1.5/CON.75/DEX.25 | [color=#FFD700]Paladin[/color]=STR.75/CON1/DEX.25/WIS.25/WIT.25
[color=#66FFFF]MAGE:[/color] [color=#4169E1]Wizard[/color]=INT1.25/WIS.75/CON.25/DEX.25 | [color=#9400D3]Sorcerer[/color]=INT1.5/WIS.5/CON.25/DEX.25 | [color=#20B2AA]Sage[/color]=WIS1/INT.75/CON.5/DEX.25
[color=#66FF66]TRICK:[/color] [color=#2F4F4F]Thief[/color]=WIT1.5/DEX.75/CON.25 | [color=#228B22]Ranger[/color]=DEX.75/WIT.75/STR.5/CON.5 | [color=#191970]Ninja[/color]=DEX1.25/WIT.75/STR.25/CON.25

[b][color=#FFD700]══ ENDGAME ══[/color][/b]
[color=#AAAAAA]Chase Items:[/color] [color=#C0C0C0]Jarl's Ring[/color](Lv50+) | [color=#A335EE]Unforged Crown[/color](Lv200+, forge at Fire Mt -400,0) | [color=#00FFFF]Eternal Flame[/color](hidden)
[color=#AAAAAA]Titles:[/color]
  [color=#C0C0C0]Jarl[/color](50-500): Ring + (0,0). ONE only. Summon/Tax/Gift/Tribute. Lost on death or Lv500+.
  [color=#FFD700]High King[/color](200-1000): Crown + (0,0). ONE only. Knight/Cure/Exile/Treasury. Survives 1 death!
  [color=#9400D3]Elder[/color](1000+): Auto. Many exist. Heal/Mentor/Seek Flame. Can find Eternal Flame.
  [color=#00FFFF]Eternal[/color]: Elder + Flame. Max 3. Has 3 lives! Restore/Bless/Smite/Guardian.
[color=#FF69B4]Trophies(T8+):[/color] 5%% from bosses (Dragon Scale, Phylactery, etc.) - prestige collectibles!
[color=#00FFFF]Companions:[/color] Companion eggs drop from [color=#9932CC]dungeons only[/color] - bosses guarantee their egg, treasure may have extras!
  Wolf(+10%%atk) | Phoenix(2%%HP/rnd) | Shadow(+15%%flee) | Frost(+10%%def) | Storm(+5%%crit) + more
  [color=#00FFFF]More[/color]→[color=#00FFFF]Companions[/color]: View/activate companions, [color=#00FF00]Inspect[/color] for stats & abilities. [color=#FFAA00]Eggs[/color]: View incubating eggs with art!
  Each monster type has unique abilities in combat! Lv5=active, Lv15=threshold. Scales with level. Hatch eggs by walking!

[b][color=#FFD700]══ WANDERING NPCs ══[/color][/b]
[color=#DAA520]Blacksmith[/color] (3%% chance when gear damaged): Offers repairs while traveling. Cost = wear%% × item_level × 5 gold.
  Repair All = 10%% discount! Select items with [1-9] keys, or repair all with [%s].
[color=#00FF00]Healer[/color] (4%% chance when HP<80%%): Offers healing while traveling. Costs scale with level:
  [%s] Quick (25%% HP) = level×22g | [%s] Full (100%% HP) = level×90g | [%s] Cure All (full+debuffs) = level×180g
[color=#DAA520]Tax Collector[/color] (5%% chance when 100+g): 8%% tax (min 10g). Bumbling=5%%, Veteran=10%%. Jarls/High Kings immune.

[b][color=#FFD700]══ SANCTUARY (HOUSE) ══[/color][/b]
[color=#00FFFF]Account-Level Home:[/color] Your Sanctuary persists across all characters on your account!
[color=#00FFFF]Access:[/color] After login, you'll see your Sanctuary before character select. Store items for future characters!
[color=#FFA500]Storage:[/color] Base 20 slots. Store items from current character. Withdraw items when creating new characters.
[color=#A335EE]Companion Kennel:[/color] Register companions to your Sanctuary - they survive permadeath!
  • Use [color=#00FFFF]Home Stone (Companion)[/color] to register your active companion
  • Registered companions return home when your character dies
  • Checkout registered companions on new characters
[color=#FF69B4]Baddie Points (BP):[/color] Meta-currency earned when characters die. Spend on upgrades:
  • Storage Expansion (+10 slots/level) | Companion Kennel (+1 slot/level)
  • Escape Training (+2%% flee/level) | Family Inheritance (+50g start/level)
  • Ancestral Wisdom (+1%% XP/level) | Homesteading (+5%% gathering/level)
[color=#FFD700]Home Stones:[/color] Found in tier 4-6 loot. Use outside combat/dungeons to send things home:
  • Home Stone (Egg) - Send one incubating egg to storage
  • Home Stone (Supplies) - Send up to 10 consumables to storage
  • Home Stone (Equipment) - Send one equipped item to storage
  • Home Stone (Companion) - Register your active companion to Sanctuary
[color=#00BFFF]Egg Freezing:[/color] [color=#FFAA00]More[/color]→[color=#FFAA00]Eggs[/color]: Press Freeze/Unfreeze buttons to pause egg hatching!
  • Frozen eggs don't progress when you walk - perfect for saving until you find a Home Stone
  • Frozen eggs can still be traded with other players

[b][color=#FFD700]══ MISC ══[/color][/b]
[color=#AAAAAA]Whisper:[/color] /w <name> <msg> to send private message. /reply or /r to respond. Also: /msg, /tell
[color=#AAAAAA]Watch:[/color] "watch <name>" to spectate. [%s]=approve, [%s]=deny. Esc/unwatch to stop.
[color=#AAAAAA]Gambling:[/color] 3d6 vs merchant. Triples pay big! Triple 6s = JACKPOT!
[color=#AAAAAA]Bug:[/color] "/bug <desc>" to report | [color=#AAAAAA]Condition:[/color] Pristine→Excellent→Good→Worn→Damaged→BROKEN. Repair@merchants.
[color=#AAAAAA]Formulas:[/color] HP=50+CON×5+class | Mana=INT×3+WIS×1.5 | Stam=STR+CON | Energy=(WIT+DEX)×0.75 | DEF=CON/2+gear
[color=#FF4444]Chat:[/color] All commands need [color=#00FFFF]/[/color] prefix (e.g. /help, /who). Text without / goes to chat. Combat keywords work without /.
[color=#00FFFF]v0.9.83:[/color] Item locking, 53 dungeons (all monsters), 5x blacksmith upgrades, quest scaling, bug fixes.
""" % [k0, k1, k2, k3, k4, k5, k6, k7, k8, k1, k5, k4, k4, k4, k4, k4, k4, k1, k4, k4, k4, k0, k1, k1, k2, k3, k1, k2]
	display_game(help_text)

	# Add discovered trading posts section (dynamic per character)
	var discovered = character_data.get("discovered_posts", [])
	if discovered.size() > 0:
		display_game("")
		display_game("[b][color=#FFD700]══ YOUR DISCOVERED POSTS ══[/color][/b]")
		# Sort by name for readability
		var sorted_posts = discovered.duplicate()
		sorted_posts.sort_custom(func(a, b): return a.name < b.name)
		# Format in columns for horizontal space usage
		var post_strings = []
		for post in sorted_posts:
			post_strings.append("[color=#00FF00]%s[/color](%d,%d)" % [post.name, post.x, post.y])
		# Display 3 posts per line
		var line = ""
		for i in range(post_strings.size()):
			if i > 0 and i % 3 == 0:
				display_game(line)
				line = ""
			if line != "":
				line += " | "
			line += post_strings[i]
		if line != "":
			display_game(line)
		display_game("[color=#808080](%d/%d posts discovered)[/color]" % [discovered.size(), 58])

	# Scroll to top after displaying help
	await get_tree().process_frame
	game_output.scroll_to_line(0)

func search_help(search_term: String):
	"""Search the help text and display matching sections with context"""
	game_output.clear()

	var term = search_term.to_lower().strip_edges()
	if term.is_empty():
		display_game("[color=#FF0000]Please provide a search term.[/color]")
		return

	# Define searchable help sections with keywords
	var help_sections = [
		{
			"title": "GETTING STARTED",
			"keywords": ["start", "starting", "begin", "beginner", "new", "player", "how", "play", "guide", "tutorial", "first", "tips", "advice", "build", "focus"],
			"content": "[color=#FF6666]▸ WARRIOR[/color] - Straightforward melee. High HP, steady damage.\n  [color=#808080]Focus:[/color] [color=#FF6666]STR[/color] (attack) + [color=#66FF66]CON[/color] (HP/defense)\n  Start hunting immediately. Use Power Strike for damage. Tank and outlast enemies.\n  [color=#C0C0C0]Fighter[/color]=safe, [color=#8B0000]Barbarian[/color]=risky/high dmg, [color=#FFD700]Paladin[/color]=self-healing\n\n[color=#66FFFF]▸ MAGE[/color] - Powerful spells, resource management.\n  [color=#808080]Focus:[/color] [color=#FF66FF]INT[/color] (spell power) + [color=#FFFF66]WIS[/color] (mana pool/resist)\n  Use Magic Bolt to kill. Meditate to recover HP+mana.\n  [color=#4169E1]Wizard[/color]=reliable, [color=#9400D3]Sorcerer[/color]=gambler, [color=#20B2AA]Sage[/color]=efficient\n\n[color=#66FF66]▸ TRICKSTER[/color] - Tactical gameplay, many options.\n  [color=#808080]Focus:[/color] [color=#FFA500]WIT[/color] (abilities) + [color=#66FFFF]DEX[/color] (crit/flee)\n  Use Outsmart vs dumb monsters (free win!). Analyze to learn stats. Flee if outmatched.\n  [color=#2F4F4F]Thief[/color]=crits, [color=#228B22]Ranger[/color]=rewards, [color=#191970]Ninja[/color]=escape artist"
		},
		{
			"title": "CONTROLS & BASICS",
			"keywords": ["controls", "keys", "keyboard", "numpad", "move", "movement", "escape", "action", "bar", "commands", "inventory", "abilities", "status", "help", "clear", "map"],
			"content": "[color=#00FFFF]Keys:[/color] [Esc]=Toggle mode | [NUMPAD]=Move (789/456/123) | Type+Enter=Chat\n[color=#00FFFF]Action Bar:[/color] [Space]=Primary | [Q][W][E][R]=Quick | [1][2][3][4]=Additional\n[color=#00FFFF]Commands:[/color] inventory/i, abilities, status, who, examine <name>, help, clear\n[color=#00FFFF]Map:[/color] [color=#FF6600]![/color]=Danger [color=#FFFF00]P[/color]=Trading Post [color=#FFD700]$[/color]=Merchant [color=#00FF00]@[/color]=You"
		},
		{
			"title": "STATS",
			"keywords": ["stats", "str", "strength", "con", "constitution", "dex", "dexterity", "int", "intelligence", "wis", "wisdom", "wit", "wits", "hp", "health", "mana", "stamina", "energy", "level", "up", "gain", "gains", "per"],
			"content": "[color=#FF6666]STR[/color] [color=#808080]Strength[/color] = +2% attack damage per point | Contributes to Stamina pool\n[color=#66FF66]CON[/color] [color=#808080]Constitution[/color] = +5 max HP per point | +0.5 defense per point | Contributes to Stamina pool\n[color=#66FFFF]DEX[/color] [color=#808080]Dexterity[/color] = +1% hit chance, +2% flee chance | +0.5% crit per point | Contributes to Energy pool\n[color=#FF66FF]INT[/color] [color=#808080]Intelligence[/color] = +3% spell damage per point | Contributes to Mana pool\n[color=#FFFF66]WIS[/color] [color=#808080]Wisdom[/color] = Increases mana pool | Resists enemy abilities (curse, drain, etc.)\n[color=#FFA500]WIT[/color] [color=#808080]Wits[/color] = Outsmart: 15×log₂(WIT/10) bonus | Contributes to Energy pool\n\n[color=#FFD700]Level Up Stat Gains (2.5 total/level):[/color]\n[color=#FF6666]WARRIOR:[/color] Fighter=STR1.25/CON.75/DEX.25/WIT.25 | Barbarian=STR1.5/CON.75/DEX.25 | Paladin=STR.75/CON1/DEX.25/WIS.25/WIT.25\n[color=#66FFFF]MAGE:[/color] Wizard=INT1.25/WIS.75/CON.25/DEX.25 | Sorcerer=INT1.5/WIS.5/CON.25/DEX.25 | Sage=WIS1/INT.75/CON.5/DEX.25\n[color=#66FF66]TRICKSTER:[/color] Thief=WIT1.5/DEX.75/CON.25 | Ranger=DEX.75/WIT.75/STR.5/CON.5 | Ninja=DEX1.25/WIT.75/STR.25/CON.25"
		},
		{
			"title": "RACES",
			"keywords": ["race", "races", "human", "elf", "dwarf", "ogre", "halfling", "orc", "gnome", "undead", "poison", "lethal", "heal", "xp", "experience", "dodge", "gold", "damage", "cost", "curse", "death"],
			"content": "[color=#FFFFFF]Human[/color] = +10% XP from all kills\n[color=#66FF99]Elf[/color] = 50% poison resistance, +20% magic resistance, +25% mana\n[color=#FFA366]Dwarf[/color] = 25% chance to survive lethal blow at 1 HP\n[color=#8B4513]Ogre[/color] = 2x healing from all sources\n[color=#D2691E]Halfling[/color] = +10% dodge chance, +15% gold from kills\n[color=#556B2F]Orc[/color] = +20% damage when below 50% HP\n[color=#DDA0DD]Gnome[/color] = -15% ability costs\n[color=#708090]Undead[/color] = Immune to death curses, poison heals instead of damages"
		},
		{
			"title": "WARRIOR PATH",
			"keywords": ["warrior", "fighter", "barbarian", "paladin", "stamina", "strength", "melee", "power", "strike", "war", "cry", "shield", "bash", "cleave", "berserk", "iron", "skin", "devastate", "undead", "demon"],
			"content": "[color=#FF6666]WARRIOR PATH[/color] (STR > 10) - Uses Stamina (STR×4 + CON×4)\n\n[color=#C0C0C0]Fighter[/color] - 20% reduced stamina costs, +15% defense from CON\n[color=#8B0000]Barbarian[/color] - +3% damage per 10% HP missing (max +30%), +25% stamina cost\n[color=#FFD700]Paladin[/color] - Heal 3% max HP per round, +25% damage vs undead/demons\n\n[color=#AAAAAA]Abilities:[/color]\nL1 Power Strike (10) - 1.5x damage\nL10 War Cry (15) - +25% damage, 3 rounds\nL25 Shield Bash (20) - Attack + stun\nL40 Cleave (30) - 2x damage\nL60 Berserk (40) - +100% damage, -50% defense, 3 rounds\nL80 Iron Skin (35) - Block 50% damage, 3 rounds\nL100 Devastate (50) - 4x damage"
		},
		{
			"title": "MAGE PATH",
			"keywords": ["mage", "wizard", "sorcerer", "sage", "mana", "magic", "spell", "bolt", "blast", "meteor", "shield", "haste", "paralyze", "forcefield", "banish", "meditate", "intelligence"],
			"content": "[color=#66FFFF]MAGE PATH[/color] (INT > 10) - Uses Mana (INT×12 + WIS×6)\n\n[color=#4169E1]Wizard[/color] - +15% spell damage, +10% spell crit chance\n[color=#9400D3]Sorcerer[/color] - 25% chance for double damage, 5% backfire chance\n[color=#20B2AA]Sage[/color] - 25% reduced mana costs, +50% meditate bonus\n\n[color=#AAAAAA]Abilities:[/color]\nMeditate - Restore HP + 4% mana (8% if full HP)\nL1 Magic Bolt (variable) - Mana × (1 + INT/50) damage\nL10 Shield (20) - +50% defense, 3 rounds\nL30 Haste (35) - Speed buff, 5 rounds\nL40 Blast (50) - 2x magic damage\nL50 Paralyze (35) - Stun 1 round\nL60 Forcefield (75) - Block 2 attacks\nL70 Banish (60) - Instant kill weak enemies\nL100 Meteor (100) - 5x magic damage\n\n[color=#FFD700]Magic Bolt Suggestion:[/color] The suggested mana is intentionally high to ensure a kill. It accounts for: monster defense, WIS resistance, level penalty, class affinity, damage variance, and Armored ability. Use less if you want to conserve mana (but may not kill)."
		},
		{
			"title": "TRICKSTER PATH",
			"keywords": ["trickster", "thief", "ranger", "ninja", "energy", "wits", "crit", "critical", "flee", "analyze", "distract", "pickpocket", "ambush", "vanish", "exploit", "heist", "beast", "animal"],
			"content": "[color=#66FF66]TRICKSTER PATH[/color] (WITS > 10) - Uses Energy ((WIT+DEX)×0.75)\n\n[color=#2F4F4F]Thief[/color] - +10% crit chance, +35% crit damage (1.85x total)\n[color=#228B22]Ranger[/color] - +25% damage vs beasts, +30% gold and XP\n[color=#191970]Ninja[/color] - +40% flee chance, no damage on failed flee\n[color=#66FF66]All Tricksters:[/color] 25% chance for Quick Strike (+50% bonus damage) on attacks\n\n[color=#AAAAAA]Abilities:[/color]\nL1 Analyze (5) - Reveal monster stats\nL10 Distract (15) - -50% enemy accuracy\nL25 Pickpocket (20) - Steal WITS×10 gold\nL40 Ambush (30) - 3x damage + 50% crit\nL60 Vanish (40) - Invisible, next attack crits\nL80 Exploit (35) - 10% monster HP as damage\nL100 Perfect Heist (50) - Instant win, 2x rewards"
		},
		{
			"title": "COMBAT FORMULAS",
			"keywords": ["combat", "attack", "damage", "defense", "hit", "miss", "dodge", "flee", "crit", "critical", "formula", "calculation", "level", "penalty", "initiative"],
			"content": "[color=#00FFFF]Attack:[/color] (STR + weapon) × (1 + STR×0.02)\n[color=#00FFFF]Critical:[/color] 1.5x damage, chance = 5% + DEX×0.5%\n[color=#00FFFF]Defense:[/color] DEF / (DEF + 100) × 60% damage reduction\n[color=#00FFFF]Level Penalty:[/color] -3% attack / -1.5% ability per level vs higher monsters\n[color=#00FFFF]Hit Chance:[/color] 75% + (DEX - enemy speed), clamped 30-95%\n[color=#00FFFF]Flee Chance:[/color] 40% + DEX + speed - level_diff×3\n[color=#FF4444]Initiative:[/color] If monster speed > DEX, (speed-DEX)×2% chance enemy strikes first"
		},
		{
			"title": "OUTSMART",
			"keywords": ["outsmart", "trick", "instant", "win", "intelligence", "dumb", "beast"],
			"content": "[color=#FFA500]Outsmart[/color] - Trick dumb monsters for instant win\nBase 5% + 15×log₂(WIT/10) bonus\n+15% for Tricksters\n+3% per monster INT below 10, -1% per INT above 10\n-2% per point monster INT exceeds your WIT\nLevel penalty: -2%/lvl (1-10), -1%/lvl (11-50) above you\nCap: 85% Trickster, 70% others (reduced by monster INT/2, min 30%)\n[color=#00FF00]Best vs:[/color] Beasts, undead | [color=#FF4444]Worst vs:[/color] Mages, dragons\nFailure = enemy free attack, can't retry"
		},
		{
			"title": "UNIVERSAL ABILITIES",
			"keywords": ["cloak", "stealth", "teleport", "travel", "all", "nothing", "gamble", "buff", "advantage"],
			"content": "[color=#9932CC]Cloak[/color] (Level 20+) - Stealth movement, 8% resource per step, no encounters\n[color=#AA66FF]Teleport[/color] - Mage L30, Trickster L45, Warrior L60. Cost: 10 + distance\n[color=#FF00FF]All or Nothing[/color] - ~3% instant kill, fail = monster 2x STR/SPD, +0.1%/use permanent (max 34%)\nButton shows your trained base rate. Actual chance varies by level difference.\n[color=#00FF00]Buff Advantage:[/color] Defensive abilities give 75% chance to avoid enemy turn"
		},
		{
			"title": "MONSTER ABILITIES",
			"keywords": ["monster", "ability", "abilities", "multi", "strike", "berserker", "enrage", "life", "steal", "glass", "cannon", "poison", "blind", "curse", "disarm", "bleed", "drain", "armored", "ethereal", "regeneration", "reflect", "thorns", "death", "summoner", "corrosive", "sunder", "wish", "granter", "gem", "gold", "hoarder"],
			"content": "[color=#FF4444]Offensive:[/color] Multi-Strike (2-3x), Berserker (+dmg when hurt), Enrage (+dmg/round), Life Steal, Glass Cannon (3x dmg, 50% HP)\n[color=#808080]Debuffs:[/color] Curse (-def), Disarm (-atk), Bleed (DoT), Slow (-flee), Drain (resources)\n[color=#FF00FF]Poison:[/color] 30% monster STR damage/round, 35 rounds. Cure: Recharge\n[color=#808080]Blind:[/color] -30% hit, hides monster HP, 15 rounds. Cure: Recharge\n[color=#6666FF]Defensive:[/color] Armored (+50% def), Ethereal (50% dodge), Regeneration, Reflect (25%), Thorns\n[color=#FFD700]Special:[/color] Death Curse (damage on death), Summoner (reinforcements), Corrosive/Sunder (gear damage)\n[color=#00FF00]Rewards:[/color] Wish Granter (10% wish), Gem Bearer (gems scale with level), Gold Hoarder (3x gold)"
		},
		{
			"title": "ITEMS & POTIONS",
			"keywords": ["item", "items", "potion", "potions", "scroll", "scrolls", "buff", "debuff", "health", "mana", "stamina", "energy", "strength", "defense", "speed", "crit", "lifesteal", "thorns", "forcefield", "rage", "haste", "weakness", "vulnerability", "slow", "doom", "summoning", "finding", "time", "stop", "resurrect", "bane", "mystery", "box", "cursed", "coin", "tome", "stat", "skill"],
			"content": "[color=#00FFFF]Potions:[/color] Health, Resource (restores your class's primary resource) | STR/DEF/SPD boost | Crit/Lifesteal/Thorns effects\n[color=#FF00FF]Buff Scrolls:[/color] Forcefield, Rage, Stone Skin, Haste, Vampirism, Thorns, Precision\n[color=#A335EE]Special Scrolls (Tier 6+):[/color]\n• Time Stop - Skip monster's next turn\n• Monster Bane (Dragon/Undead/Beast) - +50% damage vs type for 3 battles\n• Resurrect (Tier 8+) - Revive at 25% HP once if killed\n[color=#FFD700]Mystery Items:[/color]\n• Mysterious Box - Opens to random item from same tier or +1 higher\n• Cursed Coin - 50% double gold, 50% lose half gold\n[color=#FF69B4]Permanent Upgrades:[/color]\n• Stat Tomes (Tier 6+) - +1 permanent stat bonus!\n• Skill Enhancer Tomes (Tier 7+) - -10% ability cost or +15% damage"
		},
		{
			"title": "EQUIPMENT & GEAR",
			"keywords": ["equipment", "gear", "weapon", "armor", "shield", "helm", "boots", "ring", "amulet", "wear", "condition", "broken", "repair", "upgrade", "warrior", "mage", "trickster", "class"],
			"content": "[color=#AAAAAA]Wear:[/color] Corrosive/Sunder monsters damage gear. 100% wear = broken (no bonuses). Repair at merchants.\n[color=#AAAAAA]Condition:[/color] Pristine → Excellent → Good → Worn → Damaged → BROKEN\n\n[color=#FF6666]Warrior Gear:[/color] Minotaur (t3), Iron Golem (t6), Death Incarnate (t8) - 35% drop\n[color=#66CCCC]Mage Gear:[/color] Wraith (t3), Lich (t5), Elemental/Sphinx (t6), Elder Lich (t7), Time Weaver (t8)\n[color=#66FF66]Trickster Gear:[/color] Goblin (t1), Hobgoblin/Spider (t2), Void Walker (t7)\n[color=#FFD700]Weapon/Shield:[/color] Any Lv5+ monster can spawn as Master (4%) - 35% guaranteed drop"
		},
		{
			"title": "TRADING POSTS & MERCHANTS",
			"keywords": ["trading", "post", "posts", "merchant", "merchants", "shop", "buy", "sell", "upgrade", "gamble", "recharge", "heal", "haven", "crossroads", "quest", "quests", "safe"],
			"content": "[color=#00FF00]Trading Posts (58):[/color] Safe zones with shops, quests, recharge\nHaven (0,10) - Spawn point, beginner quests\nCrossroads (0,0) - The High Seat, hotzone quests\nFrostgate (0,-100) - Boss hunts\n+55 more across the world!\n\n[color=#FFD700]Merchants (110):[/color] Roam between posts\n[color=#FF4444]$[/color]=Weaponsmith [color=#4488FF]$[/color]=Armorer [color=#AA44FF]$[/color]=Jeweler [color=#FFD700]$[/color]=General\nServices: Buy, Sell, Gamble | Use [color=#AA66FF]Enchanting[/color] to upgrade gear!"
		},
		{
			"title": "GEMS & PROGRESSION",
			"keywords": ["gem", "gems", "gold", "currency", "level", "experience", "xp", "drop", "reward", "lucky", "find", "treasure", "legendary", "adventurer"],
			"content": "[color=#00FFFF]Gems:[/color] Premium currency\n• Drop from monsters 5+ levels ABOVE you\n• Higher level difference = better drop chance\n• Sell to merchants: 1 gem = 1000 gold\n• Pay for upgrades (1 gem = 1000g value)\n\n[color=#FFD700]Lucky Finds:[/color] While moving/hunting you may find:\n• Hidden treasure (gold or items)\n• [color=#FF69B4]Legendary Adventurer[/color] - Permanent stat boost!"
		},
		{
			"title": "TITLES & ENDGAME",
			"keywords": ["title", "titles", "jarl", "king", "high", "elder", "eternal", "flame", "ring", "crown", "endgame", "chase", "fire", "mountain", "obtain", "get", "claim", "pilgrimage", "crucible", "donate", "knight", "mentor", "guardian", "bless"],
			"content": "[color=#FFD700]HOW TO OBTAIN TITLES[/color]\n\n[color=#C0C0C0]Jarl[/color] [color=#808080](Level 50-500, ONE per realm)[/color]\n1. Hunt monsters Lv50+ for [color=#C0C0C0]Jarl's Ring[/color] (0.5% drop)\n2. Go to The High Seat at (0,0) - use [color=#FFD700]High Seat[/color] action bar button\n3. Claim title | Abilities: Summon (500g), Tax (1K), Gift (5%), Tribute (1hr CD)\n\n[color=#FFD700]High King[/color] [color=#808080](Level 200-1000, ONE per realm)[/color]\n1. Hunt monsters Lv200+ for [color=#A335EE]Unforged Crown[/color] (0.2% drop)\n2. Forge at Fire Mountain (-400,0) - use Check Forge button\n3. Claim at (0,0) | Abilities: Knight (50K+5g), Cure (5K), Exile (10K), Treasury (2hr CD)\n\n[color=#9400D3]Elder[/color] [color=#808080](Level 1000+, auto-granted)[/color]\nAbilities: Heal (10K), Mentor (500K+25g), Seek Flame (25K)\n\n[color=#00FFFF]Eternal[/color] [color=#808080](Elder only, max 3, 3 lives)[/color]\nComplete the Eternal Pilgrimage. Abilities: Restore (50K), Bless (5M+100g), Smite (100K+10g), Guardian (2M+50g)"
		},
		{
			"title": "ETERNAL PILGRIMAGE",
			"keywords": ["pilgrimage", "eternal", "awakening", "trial", "blood", "mind", "wealth", "ember", "crucible", "donate", "shrine", "flame"],
			"content": "[color=#00FFFF]ETERNAL PILGRIMAGE[/color] (Elder only, use Seek Flame to track)\n\n[color=#FFFFFF]1. The Awakening[/color] - Slay 5,000 monsters\n[color=#FF4444]2. Trial of Blood[/color] - Kill 1,000 Tier 8+ monsters (Lv250+) → +3 STR\n[color=#FFFF00]3. Trial of Mind[/color] - Outsmart 200 monsters → +3 WIT\n[color=#FFD700]4. Trial of Wealth[/color] - Donate 10M gold (/donate <amount>) → +3 WIS\n[color=#FF8800]5. Ember Hunt[/color] - Collect 500 Flame Embers (T8: 10%, T9: 25%)\n[color=#FF0000]6. The Crucible[/color] - Defeat 10 consecutive T9 bosses (/crucible)\n\n[color=#808080]Commands:[/color] /donate <amount> (at shrine), /crucible (start gauntlet)\n[color=#808080]Note:[/color] Crucible death resets progress but keeps previous trials."
		},
		{
			"title": "TITLE ABILITIES",
			"keywords": ["title", "ability", "abilities", "summon", "tax", "gift", "tribute", "knight", "cure", "exile", "treasury", "heal", "mentor", "restore", "bless", "smite", "guardian", "consent"],
			"content": "[color=#FFD700]TITLE ABILITY COSTS[/color] (gold + gems where noted)\n\n[color=#C0C0C0]JARL:[/color] Summon 500g, Tax 1K, Gift 5% of gold, Tribute 1hr CD\n[color=#FFD700]HIGH KING:[/color] Knight 50K+5g, Cure 5K, Exile 10K, Royal Treasury 2hr CD\n[color=#9400D3]ELDER:[/color] Heal 10K, Mentor 500K+25g, Seek Flame 25K\n[color=#00FFFF]ETERNAL:[/color] Restore 50K, Bless 5M+100g (+5 stat), Smite 100K+10g, Guardian 2M+50g\n\n[color=#AAAAAA]Special Effects:[/color]\n• [color=#87CEEB]Knight[/color] status: +15% dmg, +10% gold (permanent until replaced)\n• [color=#DDA0DD]Mentee[/color] status: +30% XP, +20% gold (Lv500 max)\n• [color=#00FFFF]Guardian[/color]: One-time death save (permanent until used)\n• [color=#00FFFF]Bless[/color]: Choose stat via action bar, permanent +5\n• Summon requires target's consent via action bar prompt"
		},
		{
			"title": "SOCIAL & MISC",
			"keywords": ["watch", "spectate", "gambling", "dice", "bug", "report", "trade", "trading", "player", "exchange", "give"],
			"content": "[color=#AAAAAA]Trading:[/color] \"trade <name>\" to request a trade with another player\n• Both players must be at the same location\n• Add items from your inventory, toggle ready when done\n• Trade completes when both players are ready\n• Items display with the owner's class theme until traded\n[color=#AAAAAA]Watch:[/color] \"watch <name>\" to spectate another player (requires approval)\n[color=#AAAAAA]Gambling:[/color] Dice game at merchants - Roll 3d6 vs merchant's 3d6. Triples pay big!\n[color=#AAAAAA]Bug Reports:[/color] \"bug <description>\" to generate a report"
		},
		{
			"title": "MONSTER HP KNOWLEDGE",
			"keywords": ["hp", "health", "known", "unknown", "estimated", "estimate", "monster", "bar", "question", "marks", "???", "tilde", "knowledge"],
			"content": "[color=#FFD700]Monster HP Knowledge System[/color]\n\nMonster HP visibility depends on your combat experience:\n\n[color=#FFFFFF]Known HP (150/200)[/color] - Exact HP values\n• You've killed this monster type at this level or higher\n• HP bar shows precise current/max values\n\n[color=#808080]Estimated HP (~150/200)[/color] - Approximation with ~ prefix\n• You've killed this monster type, but at a LOWER level\n• HP is scaled up from your known data\n• May be inaccurate - actual HP could be higher!\n\n[color=#808080]Unknown HP (???)[/color] - No data available\n• You've never killed this monster type\n• Or you are Blinded (hides HP even for known monsters)\n\n[color=#00FFFF]Tip:[/color] Kill monsters to learn their HP! Knowledge persists across sessions.\n\n[color=#FFD700]Magic Bolt Suggestions:[/color]\nThe suggested mana is a [color=#FFFFFF]conservative estimate[/color] that accounts for:\n• Monster defense and WIS resistance\n• Level penalty (if monster is higher level)\n• Class affinity (+25% vs blue, -15% vs yellow/green)\n• Worst-case damage variance (85% roll)\n• Armored ability (+50% defense)\nThis ensures a kill in most cases. Use less to save mana, but risk not killing."
		},
		{
			"title": "PROC EQUIPMENT",
			"keywords": ["proc", "procs", "vampire", "lifesteal", "thunder", "shocking", "reflection", "reflect", "slayer", "execute", "suffix", "special", "gear", "effect"],
			"content": "[color=#A335EE]Proc Equipment (Tier 6+)[/color]\n\nHigh-tier monsters can drop equipment with special proc effects:\n\n[color=#FF4444]of the Vampire[/color] - Lifesteal: Heal 10% of damage dealt\n[color=#FFFF00]of Thunder[/color] - Shocking: 20% chance for +15% bonus lightning damage\n[color=#6666FF]of Reflection[/color] - Damage Reflect: Return 20% of damage taken to attacker\n[color=#FF6666]of the Slayer[/color] - Execute: 15% chance to instant-kill monsters below 20% HP\n\n[color=#00FFFF]Note:[/color] Proc effects stack from multiple equipped items!"
		},
		{
			"title": "TROPHIES",
			"keywords": ["trophy", "trophies", "dragon", "scale", "phylactery", "titan", "heart", "entropy", "shard", "collector", "prestige", "collectible"],
			"content": "[color=#FF69B4]Trophy Drops (Tier 8+)[/color]\n\nPowerful monsters have a chance to drop rare trophies:\n\n[color=#FFD700]• Dragon Scale[/color] - 5% from Primordial Dragon\n[color=#A335EE]• Lich Phylactery[/color] - 5% from Elder Lich\n[color=#FFA500]• Titan Heart[/color] - 5% from Titan\n[color=#00FFFF]• Entropy Shard[/color] - 2% from Entropy\n[color=#FF00FF]• Phoenix Feather[/color] - 5% from Phoenix\n...and more!\n\n[color=#00FFFF]Trophies are prestige collectibles[/color] - show them off in your status!"
		},
		{
			"title": "COMPANIONS",
			"keywords": ["companion", "companions", "soul", "gem", "gems", "pet", "wolf", "phoenix", "shadow", "wisp", "guardian", "spirit", "ember", "bonus"],
			"content": "[color=#00FFFF]Companion System[/color]\n\nSoul Gems summon companion spirits that provide combat bonuses:\n\n[color=#808080]Wolf Spirit[/color] - +10% attack damage\n[color=#FF6666]Phoenix Ember[/color] - Regenerate 2% HP per combat round\n[color=#9932CC]Shadow Wisp[/color] - +15% flee chance\n[color=#4169E1]Frost Guardian[/color] - +10% defense\n[color=#FFD700]Storm Spirit[/color] - +5% critical chance\n[color=#00FF00]Nature's Bond[/color] - +3% HP regen per round\n[color=#FF00FF]Void Familiar[/color] - +8% damage, +8% crit\n\n[color=#AAAAAA]Sources:[/color] Dungeon completion (GUARANTEED!), fishing, mining, logging (rare drops)\n[color=#AAAAAA]Only one companion active at a time. Use soul gems from inventory to summon/swap.[/color]"
		},
		{
			"title": "CRAFTING & GATHERING",
			"keywords": ["craft", "crafting", "gather", "gathering", "salvage", "essence", "fish", "fishing", "mine", "mining", "log", "logging", "chop", "ore", "wood", "material", "materials", "fail", "wrong", "key", "button"],
			"content": "[color=#FFD700]Crafting & Gathering System[/color]\n\n[color=#AA66FF]Salvage[/color] - Destroy inventory items for Salvage Essence (ESS)\n• Value scales with rarity and item level\n• Bonus chance for crafting materials (ore from weapons, leather from armor, etc.)\n• Access via Inventory → Salvage → select item\n\n[color=#00FFFF]Fishing[/color] - At water tiles (~), press R to fish\n• Wait for bite, then press the CORRECT key shown to catch\n• [color=#FF4444]Wrong key = FAIL![/color] Watch the action bar carefully!\n• Shallow vs Deep water have different catches\n• Rare: pearls, treasure chests\n\n[color=#8B4513]Mining[/color] - At ore deposits (mountains), press R to mine\n• 9 tiers based on distance from origin\n• T1-2: 1 reaction, T3-5: 2 reactions, T6+: 3 reactions\n• [color=#FF4444]Wrong key = FAIL![/color] Press the correct button only!\n• Drops: ore, gems, herbs, treasure\n\n[color=#228B22]Logging[/color] - At dense forests, press R to chop\n• 6 tiers based on distance from origin\n• [color=#FF4444]Wrong key = FAIL![/color]\n• Drops: wood, herbs, sap, enchanting materials\n\n[color=#808080]View Materials:[/color] Inventory → Materials\n[color=#808080]Skills:[/color] Fishing/Mining/Logging XP from catches → better odds + faster reaction windows"
		},
		{
			"title": "DUNGEONS",
			"keywords": ["dungeon", "dungeons", "floor", "floors", "boss", "instance", "clear", "entrance", "explore", "find", "first", "into", "depths", "haven", "companion", "egg", "pet"],
			"content": "[color=#9932CC]Dungeon System[/color]\n\nDungeons are multi-floor instances that spawn in the wilderness!\n\n[color=#FFD700]Finding Your First Dungeon:[/color]\n• Get the [color=#00FFFF]\"Into the Depths\"[/color] quest at Haven after completing First Blood\n• Dungeons spawn [color=#00FFFF]30+ tiles[/color] from Crossroads (0,0) in all directions\n• Look for [color=#9932CC]D[/color] on your map - that's a dungeon entrance!\n• Tier 1 dungeons: Goblin Caves, Wolf Den (levels 1-12)\n\n[color=#00FFFF]How Dungeons Work:[/color]\n• Press R at a dungeon entrance to view/enter\n• Navigate floors, fight monsters, find treasure\n• Boss awaits on the final floor!\n• Monsters scale to dungeon tier\n\n[color=#FFD700]Rewards:[/color]\n• XP and gold per floor cleared\n• [color=#FFD700]GUARANTEED[/color] companion egg on boss kill!\n• Treasure chests may contain bonus eggs\n• Dungeon quests give extra rewards\n\n[color=#00FFFF]Companion eggs ONLY drop from dungeons![/color]"
		},
		{
			"title": "QUESTS",
			"keywords": ["quest", "quests", "kill", "slay", "hunt", "bounty", "reward", "trading", "post", "daily", "hotzone", "boss"],
			"content": "[color=#00FFFF]Quest System[/color]\n\nAccept quests at trading posts (press R → Quests):\n\n[color=#FF6666]Kill Any[/color] - Slay X monsters of any type\n[color=#FFA500]Kill Type[/color] - Hunt specific monster species\n[color=#FFD700]Kill Level[/color] - Defeat a monster above target level\n[color=#FF4444]Hotzone Kill[/color] - Kill in danger zones (!) for bonus rewards\n[color=#A335EE]Boss Hunt[/color] - Track down and slay a powerful monster\n[color=#9932CC]Dungeon Clear[/color] - Complete a dungeon instance\n\n[color=#00FFFF]Rewards:[/color] XP, Gold, Gems (at higher tiers)\n[color=#00FFFF]Scaling:[/color] Quest difficulty and rewards scale with your level\n[color=#00FFFF]Tip:[/color] Hotzone quests give bonus rewards - look for [color=#FF6600]![/color] on the map!"
		}
	]

	# Find matching sections
	var matches = []
	for section in help_sections:
		var found = false
		# Check title
		if section.title.to_lower().contains(term):
			found = true
		# Check keywords
		if not found:
			for keyword in section.keywords:
				if keyword.contains(term) or term.contains(keyword):
					found = true
					break
		# Check content
		if not found and section.content.to_lower().contains(term):
			found = true

		if found:
			matches.append(section)

	# Display results
	display_game("[b][color=#FFD700]══ SEARCH RESULTS: \"%s\" ══[/color][/b]" % search_term)
	display_game("")

	if matches.is_empty():
		display_game("[color=#FF4444]No results found for \"%s\"[/color]" % search_term)
		display_game("[color=#808080]Try different keywords like: warrior, flee, gems, poison, quest[/color]")
	else:
		display_game("[color=#00FF00]Found %d matching section(s):[/color]" % matches.size())
		display_game("")

		for section in matches:
			display_game("[b][color=#00FFFF]── %s ──[/color][/b]" % section.title)
			display_game(section.content)
			display_game("")

	display_game("[color=#808080]Type /help for full help page | /search <term> to search again[/color]")

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
	# Combat-affecting abilities (offensive)
	if "berserker" in abilities:
		notable_abilities.append("[color=#FF6600]Berserker[/color]")
	if "enrage" in abilities:
		notable_abilities.append("[color=#FF4444]Enrages[/color]")
	if "glass_cannon" in abilities:
		notable_abilities.append("[color=#FF4444]Glass Cannon[/color]")
	if "multi_strike" in abilities:
		notable_abilities.append("[color=#FF8800]Multi-Strike[/color]")
	if "life_steal" in abilities:
		notable_abilities.append("[color=#FF4444]Life Stealer[/color]")
	if "ambusher" in abilities:
		notable_abilities.append("[color=#FF00FF]Ambusher[/color]")
	# Defensive abilities
	if "regeneration" in abilities:
		notable_abilities.append("[color=#00FF00]Regenerates[/color]")
	if "armored" in abilities:
		notable_abilities.append("[color=#6666FF]Armored[/color]")
	if "ethereal" in abilities:
		notable_abilities.append("[color=#AAAAFF]Ethereal[/color]")
	if "thorns" in abilities:
		notable_abilities.append("[color=#AA4400]Thorns[/color]")
	# Debuff abilities
	if "poison" in abilities:
		notable_abilities.append("[color=#FF00FF]Venomous[/color]")
	if "blind" in abilities:
		notable_abilities.append("[color=#808080]Blinding[/color]")
	if "bleed" in abilities:
		notable_abilities.append("[color=#CC0000]Bleeder[/color]")
	if "curse" in abilities:
		notable_abilities.append("[color=#800080]Curses[/color]")
	if "disarm" in abilities:
		notable_abilities.append("[color=#888888]Disarms[/color]")
	if "slow_aura" in abilities:
		notable_abilities.append("[color=#4444AA]Slowing[/color]")
	# Death effects
	if "death_curse" in abilities:
		notable_abilities.append("[color=#660066]Death Curse[/color]")
	# Reward abilities (show last)
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
	if "warrior_hoarder" in abilities:
		notable_abilities.append("[color=#FF6666]★ WARRIOR HOARDER ★[/color]")
	# Danger abilities (equipment damage)
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

	# Combat direction indicators - add colored prefix for player vs monster actions
	if msg.begins_with("You ") or msg.begins_with("you "):
		if "cast" in msg.to_lower() or "invoke" in msg.to_lower() or "unleash" in msg.to_lower() or "channel" in msg.to_lower():
			enhanced = "[color=#9932CC]>> [/color]" + enhanced
		elif "deal" in msg.to_lower() or "strike" in msg.to_lower() or "hit" in msg.to_lower() or "attack" in msg.to_lower():
			enhanced = "[color=#00FF00]>> [/color]" + enhanced
		elif "heal" in msg.to_lower() or "restore" in msg.to_lower() or "recover" in msg.to_lower():
			enhanced = "[color=#00FF00]++ [/color]" + enhanced
	elif msg.begins_with("The ") or msg.begins_with("the "):
		if "attacks" in msg.to_lower() or "strikes" in msg.to_lower() or "deals" in msg.to_lower() or "hits" in msg.to_lower():
			enhanced = "[color=#FF4444]<< [/color]" + enhanced
		elif "cast" in msg.to_lower() or "uses" in msg.to_lower() or "summon" in msg.to_lower() or "invoke" in msg.to_lower():
			enhanced = "[color=#FF6600]<< [/color]" + enhanced

	# Critical hit gets ASCII explosion burst + shaking text
	if "CRITICAL" in upper_msg:
		var crit_burst = "[color=#FF4500]     *  .  *\n   . _\\|/_ .\n  -==  *  ==-\n   ' /|\\ '\n     *  '  *[/color]\n"
		enhanced = crit_burst + enhanced
		# Apply shake to critical text
		enhanced = enhanced.replace("CRITICAL HIT", "[shake rate=25 level=8][color=#FF0000]★ CRITICAL HIT ★[/color][/shake]")
		enhanced = enhanced.replace("Critical Hit", "[shake rate=25 level=8][color=#FF0000]★ CRITICAL HIT ★[/color][/shake]")
		enhanced = enhanced.replace("critical hit", "[shake rate=25 level=8][color=#FF0000]★ CRITICAL HIT ★[/color][/shake]")
		enhanced = enhanced.replace("Critical!", "[shake rate=25 level=8][color=#FF0000]★ CRITICAL! ★[/color][/shake]")
		enhanced = enhanced.replace("CRITICAL!", "[shake rate=25 level=8][color=#FF0000]★ CRITICAL! ★[/color][/shake]")

	# Devastating/massive damage gets explosion + wave effect
	if "DEVASTAT" in upper_msg or "MASSIVE" in upper_msg:
		var impact_burst = "[color=#FF4500]  ╔═══╗\n  ║ ! ║\n  ╚═══╝[/color] "
		enhanced = enhanced.replace("Devastating", impact_burst + "[wave amp=30 freq=5][color=#FF4500]Devastating[/color][/wave]")
		enhanced = enhanced.replace("devastating", impact_burst + "[wave amp=30 freq=5][color=#FF4500]devastating[/color][/wave]")
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

	# Buff activation gets sparkle effect
	if "BUFF" in upper_msg or "BONUS" in upper_msg or "ADVANTAGE" in upper_msg:
		enhanced = enhanced.replace("buff", "[pulse freq=1.5 color=#00FFFF ease=-2.0]✦ buff ✦[/pulse]")
		enhanced = enhanced.replace("Buff", "[pulse freq=1.5 color=#00FFFF ease=-2.0]✦ Buff ✦[/pulse]")
		enhanced = enhanced.replace("bonus", "[color=#00FF00]▲ bonus ▲[/color]")
		enhanced = enhanced.replace("Bonus", "[color=#00FF00]▲ Bonus ▲[/color]")
		enhanced = enhanced.replace("advantage", "[color=#00FFFF]» advantage «[/color]")

	# Poison/DoT gets sickly wave
	if "POISON" in upper_msg or "VENOM" in upper_msg:
		enhanced = enhanced.replace("poisoned", "[wave amp=10 freq=3][color=#00FF00]☠ poisoned ☠[/color][/wave]")
		enhanced = enhanced.replace("Poisoned", "[wave amp=10 freq=3][color=#00FF00]☠ Poisoned ☠[/color][/wave]")
		enhanced = enhanced.replace("poison", "[color=#00FF00]☠ poison[/color]")

	# Monster ability effects
	if "MULTI" in upper_msg and "STRIKE" in upper_msg:
		enhanced = enhanced.replace("multi-strike", "[shake rate=15 level=4][color=#FF6347]⚔️ multi-strike ⚔️[/color][/shake]")
		enhanced = enhanced.replace("Multi-Strike", "[shake rate=15 level=4][color=#FF6347]⚔️ Multi-Strike ⚔️[/color][/shake]")
	if "LIFE STEAL" in upper_msg or "LIFESTEAL" in upper_msg:
		enhanced = enhanced.replace("life steal", "[pulse freq=2.0 color=#8B0000 ease=-2.0]🩸 life steal 🩸[/pulse]")
		enhanced = enhanced.replace("Life Steal", "[pulse freq=2.0 color=#8B0000 ease=-2.0]🩸 Life Steal 🩸[/pulse]")
		enhanced = enhanced.replace("steals life", "[pulse freq=2.0 color=#8B0000 ease=-2.0]🩸 steals life 🩸[/pulse]")
	if "REGENERAT" in upper_msg:
		enhanced = enhanced.replace("regenerates", "[pulse freq=1.5 color=#00FF00 ease=-2.0]♻️ regenerates ♻️[/pulse]")
		enhanced = enhanced.replace("Regenerates", "[pulse freq=1.5 color=#00FF00 ease=-2.0]♻️ Regenerates ♻️[/pulse]")
	if "REFLECT" in upper_msg:
		enhanced = enhanced.replace("reflects", "[color=#FFD700]↩️ reflects ↩️[/color]")
		enhanced = enhanced.replace("Reflects", "[color=#FFD700]↩️ Reflects ↩️[/color]")
		enhanced = enhanced.replace("reflected", "[color=#FFD700]↩️ reflected ↩️[/color]")
	if "DRAIN" in upper_msg:
		enhanced = enhanced.replace("drains", "[wave amp=8 freq=4][color=#9932CC]💀 drains 💀[/color][/wave]")
		enhanced = enhanced.replace("Drains", "[wave amp=8 freq=4][color=#9932CC]💀 Drains 💀[/color][/wave]")
		enhanced = enhanced.replace("drained", "[wave amp=8 freq=4][color=#9932CC]💀 drained 💀[/color][/wave]")
	if "ENRAGE" in upper_msg:
		enhanced = enhanced.replace("enrages", "[shake rate=20 level=6][color=#FF0000]😠 enrages 😠[/color][/shake]")
		enhanced = enhanced.replace("Enrages", "[shake rate=20 level=6][color=#FF0000]😠 Enrages 😠[/color][/shake]")
		enhanced = enhanced.replace("enraged", "[shake rate=20 level=6][color=#FF0000]😠 enraged 😠[/color][/shake]")
	if "AMBUSH" in upper_msg:
		enhanced = enhanced.replace("ambushes", "[fade start=0 length=6][color=#FF4500]⚠️ ambushes ⚠️[/color][/fade]")
		enhanced = enhanced.replace("Ambushes", "[fade start=0 length=6][color=#FF4500]⚠️ Ambushes ⚠️[/color][/fade]")
	if "SUMMON" in upper_msg:
		enhanced = enhanced.replace("summons", "[wave amp=12 freq=3][color=#9932CC]✨ summons ✨[/color][/wave]")
		enhanced = enhanced.replace("Summons", "[wave amp=12 freq=3][color=#9932CC]✨ Summons ✨[/color][/wave]")
	if "CURSE" in upper_msg:
		enhanced = enhanced.replace("curses", "[wave amp=10 freq=4][color=#800080]👁️ curses 👁️[/color][/wave]")
		enhanced = enhanced.replace("Curses", "[wave amp=10 freq=4][color=#800080]👁️ Curses 👁️[/color][/wave]")
		enhanced = enhanced.replace("cursed", "[wave amp=10 freq=4][color=#800080]👁️ cursed 👁️[/color][/wave]")
	if "DISARM" in upper_msg:
		enhanced = enhanced.replace("disarms", "[color=#FFA500]🔓 disarms 🔓[/color]")
		enhanced = enhanced.replace("Disarms", "[color=#FFA500]🔓 Disarms 🔓[/color]")
		enhanced = enhanced.replace("disarmed", "[color=#FFA500]🔓 disarmed 🔓[/color]")
	if "ETHEREAL" in upper_msg or "PHASE" in upper_msg:
		enhanced = enhanced.replace("phases", "[fade start=0 length=8][color=#ADD8E6]👻 phases 👻[/color][/fade]")
		enhanced = enhanced.replace("ethereal", "[fade start=0 length=8][color=#ADD8E6]👻 ethereal 👻[/color][/fade]")
	if "FLEE" in upper_msg and "MONSTER" in upper_msg:
		enhanced = enhanced.replace("flees", "[fade start=0 length=10][color=#808080]💨 flees 💨[/color][/fade]")
	if "DEATH CURSE" in upper_msg:
		enhanced = enhanced.replace("death curse", "[shake rate=25 level=8][color=#8B0000]💀 DEATH CURSE 💀[/color][/shake]")
		enhanced = enhanced.replace("Death Curse", "[shake rate=25 level=8][color=#8B0000]💀 DEATH CURSE 💀[/color][/shake]")

	# Ability cast gets magic sparkle
	if "CAST" in upper_msg or "INVOKE" in upper_msg:
		enhanced = enhanced.replace("cast", "[color=#9932CC]✧ cast ✧[/color]")
		enhanced = enhanced.replace("Cast", "[color=#9932CC]✧ Cast ✧[/color]")
		enhanced = enhanced.replace("invoke", "[color=#9932CC]✧ invoke ✧[/color]")

	# Shield/defend gets solid border effect
	if "SHIELD" in upper_msg or "DEFEND" in upper_msg or "BLOCK" in upper_msg:
		enhanced = enhanced.replace("shield", "[color=#4169E1]『 shield 』[/color]")
		enhanced = enhanced.replace("Shield", "[color=#4169E1]『 Shield 』[/color]")
		enhanced = enhanced.replace("blocked", "[color=#4169E1]▣ blocked ▣[/color]")
		enhanced = enhanced.replace("Blocked", "[color=#4169E1]▣ Blocked ▣[/color]")

	# Mage abilities - magical sparkle effects
	if "FIREBALL" in upper_msg:
		enhanced = enhanced.replace("Fireball", "[wave amp=15 freq=4][color=#FF4500]🔥 Fireball 🔥[/color][/wave]")
		enhanced = enhanced.replace("fireball", "[wave amp=15 freq=4][color=#FF4500]🔥 fireball 🔥[/color][/wave]")
	if "BOLT" in upper_msg or "MANA BOLT" in upper_msg:
		enhanced = enhanced.replace("Mana Bolt", "[pulse freq=3.0 color=#00BFFF ease=-2.0]⚡ Mana Bolt ⚡[/pulse]")
		enhanced = enhanced.replace("Bolt", "[pulse freq=3.0 color=#00BFFF ease=-2.0]⚡ Bolt ⚡[/pulse]")
	if "MEDITATE" in upper_msg:
		enhanced = enhanced.replace("Meditate", "[fade start=2 length=8][color=#9932CC]✨ Meditate ✨[/color][/fade]")
		enhanced = enhanced.replace("meditate", "[fade start=2 length=8][color=#9932CC]✨ meditate ✨[/color][/fade]")
	if "FORCEFIELD" in upper_msg:
		enhanced = enhanced.replace("Forcefield", "[pulse freq=2.0 color=#4169E1 ease=-2.0]🛡️ Forcefield 🛡️[/pulse]")

	# Warrior abilities - impact effects
	if "POWER STRIKE" in upper_msg or "POWERSTRIKE" in upper_msg:
		enhanced = enhanced.replace("Power Strike", "[shake rate=20 level=5][color=#FF6347]💥 Power Strike 💥[/color][/shake]")
	if "BERSERK" in upper_msg:
		enhanced = enhanced.replace("Berserk", "[shake rate=30 level=10][color=#FF0000]⚔️ BERSERK ⚔️[/color][/shake]")
		enhanced = enhanced.replace("berserk", "[shake rate=30 level=10][color=#FF0000]⚔️ berserk ⚔️[/color][/shake]")
	if "FORTIFY" in upper_msg:
		enhanced = enhanced.replace("Fortify", "[color=#FFD700]🏰 Fortify 🏰[/color]")
	if "RALLY" in upper_msg:
		enhanced = enhanced.replace("Rally", "[wave amp=10 freq=3][color=#FFD700]📯 Rally 📯[/color][/wave]")

	# Trickster abilities - sneaky effects
	if "BACKSTAB" in upper_msg:
		enhanced = enhanced.replace("Backstab", "[fade start=0 length=6][color=#00FF00]🗡️ Backstab 🗡️[/color][/fade]")
	if "SABOTAGE" in upper_msg:
		enhanced = enhanced.replace("Sabotage", "[wave amp=8 freq=5][color=#32CD32]⚙️ Sabotage ⚙️[/color][/wave]")
	if "GAMBIT" in upper_msg:
		enhanced = enhanced.replace("Gambit", "[rainbow freq=1.5 sat=0.8 val=0.9]🎲 Gambit 🎲[/rainbow]")
	if "ANALYZE" in upper_msg:
		enhanced = enhanced.replace("Analyze", "[pulse freq=2.0 color=#00FFFF ease=-2.0]🔍 Analyze 🔍[/pulse]")

	# Universal abilities
	if "CLOAK" in upper_msg:
		enhanced = enhanced.replace("Cloak", "[fade start=0 length=10][color=#9932CC]👁️ Cloak 👁️[/color][/fade]")
		enhanced = enhanced.replace("cloaked", "[fade start=0 length=10][color=#9932CC]cloaked[/color][/fade]")

	# Haste ability - speed effect
	if "HASTE" in upper_msg:
		enhanced = enhanced.replace("Haste", "[wave amp=8 freq=6][color=#00FFFF]⚡ Haste ⚡[/color][/wave]")
		enhanced = enhanced.replace("haste", "[wave amp=8 freq=6][color=#00FFFF]⚡ haste ⚡[/color][/wave]")

	# Paralyze ability - static effect
	if "PARALYZE" in upper_msg or "PARALYZ" in upper_msg:
		enhanced = enhanced.replace("paralyze", "[shake rate=15 level=4][color=#FFFF00]⚡ paralyze ⚡[/color][/shake]")
		enhanced = enhanced.replace("Paralyze", "[shake rate=15 level=4][color=#FFFF00]⚡ Paralyze ⚡[/color][/shake]")
		enhanced = enhanced.replace("paralyzed", "[shake rate=15 level=4][color=#FFFF00]paralyzed[/color][/shake]")

	# Banish ability - dimensional effect
	if "BANISH" in upper_msg:
		enhanced = enhanced.replace("banish", "[fade start=0 length=8][color=#FF00FF]✦ banish ✦[/color][/fade]")
		enhanced = enhanced.replace("Banish", "[fade start=0 length=8][color=#FF00FF]✦ Banish ✦[/color][/fade]")

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

	# Specific ability sounds (before generic ability check)
	if "METEOR" in upper_msg:
		play_fire1_sound()
		return
	if "BLAST" in upper_msg and ("CAST" in upper_msg or "UNLEASH" in upper_msg or "DAMAGE" in upper_msg):
		play_fire2_sound()
		return

	# Healing detection (skip Paladin passive - too frequent/noisy)
	if "DIVINE FAVOR" in upper_msg:
		pass  # No sound for passive class regen
	elif ("HEAL" in upper_msg or "RESTORE" in upper_msg) and "+" in msg:
		play_player_healed_sound()
		return

	# Buff detection
	if "WAR CRY" in upper_msg or "RALLY" in upper_msg or "FORTIFY" in upper_msg or "HASTE" in upper_msg or "BERSERK" in upper_msg:
		play_player_buffed_sound()
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
		# Add timestamp to chat messages
		var time_dict = Time.get_time_dict_from_system()
		var timestamp = "[color=#808080][%02d:%02d][/color] " % [time_dict.hour, time_dict.minute]
		chat_output.append_text(timestamp + text + "\n")

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

# ===== WANDERING NPC ENCOUNTER FUNCTIONS =====

func handle_blacksmith_encounter(message: Dictionary):
	"""Handle blacksmith encounter display"""
	pending_blacksmith = true
	blacksmith_upgrade_mode = ""
	blacksmith_items = message.get("items", [])
	blacksmith_repair_all_cost = message.get("repair_all_cost", 0)
	blacksmith_can_upgrade = message.get("can_upgrade", false)
	var player_gold = message.get("player_gold", 0)
	var player_gems = message.get("player_gems", 0)
	var player_essence = message.get("player_essence", 0)

	# Reset all hotkey pressed states to prevent accidental immediate triggers
	for i in range(10):
		set_meta("hotkey_%d_pressed" % i, true)  # Mark as pressed so release is required first
		set_meta("blacksmithkey_%d_pressed" % i, true)

	game_output.clear()

	# Display random trader ASCII art (persist for upgrade screens)
	if blacksmith_trader_art == "":
		blacksmith_trader_art = _get_trader_art().get_random_trader_art()
	display_game(blacksmith_trader_art)
	display_game("")

	display_game(message.get("message", ""))
	display_game("")

	# Show repair options if there are damaged items
	if blacksmith_items.size() > 0:
		display_game("[color=#FFD700]=== Repair Options ===[/color]")
		for i in range(blacksmith_items.size()):
			var item = blacksmith_items[i]
			var wear_pct = item.get("wear", 0)
			var cost = item.get("cost", 0)
			var can_afford = " [color=#FF0000](Not enough gold)[/color]" if player_gold < cost else ""
			var key_name = str(i + 1)  # Keys 1-9 for items
			display_game("[%s] %s (%d%% worn) - %d gold%s" % [key_name, item.get("name", "Item"), wear_pct, cost, can_afford])
		display_game("")
		var all_afford = " [color=#FF0000](Not enough gold)[/color]" if player_gold < blacksmith_repair_all_cost else ""
		display_game("[%s] Repair All - %d gold (10%% discount!)%s" % [get_action_key_name(1), blacksmith_repair_all_cost, all_afford])

	# Show upgrade option if available
	if blacksmith_can_upgrade:
		display_game("")
		display_game("[color=#FFD700]=== Enhancement ===[/color]")
		display_game("[%s] [color=#FFD700]Enhance Equipment[/color] - Upgrade item affixes" % get_action_key_name(2))

	display_game("")
	display_game("[%s] Decline" % get_action_key_name(0))
	display_game("")
	display_game("[color=#808080]Gold: %d | Gems: %d | Essence: %d[/color]" % [player_gold, player_gems, player_essence])

	update_action_bar()

func send_blacksmith_choice(choice: String, slot: String = "", affix_key: String = ""):
	"""Send blacksmith choice to server"""
	var msg = {"type": "blacksmith_choice", "choice": choice}
	if slot != "":
		msg["slot"] = slot
	if affix_key != "":
		msg["affix_key"] = affix_key
	send_to_server(msg)

func handle_blacksmith_upgrade_select_item(message: Dictionary):
	"""Handle item selection for upgrade"""
	blacksmith_upgrade_mode = "select_item"
	blacksmith_upgrade_items = message.get("items", [])
	var player_gold = message.get("player_gold", 0)
	var player_gems = message.get("player_gems", 0)
	var player_essence = message.get("player_essence", 0)

	game_output.clear()
	if blacksmith_trader_art != "":
		display_game(blacksmith_trader_art)
		display_game("")
	display_game(message.get("message", ""))
	display_game("")
	display_game("[color=#FFD700]=== Select Item to Enhance ===[/color]")
	display_game("")

	for i in range(blacksmith_upgrade_items.size()):
		var item = blacksmith_upgrade_items[i]
		display_game("[%s] %s (Level %d)" % [str(i + 1), item.get("name", "Item"), item.get("level", 1)])

	display_game("")
	display_game("[%s] Back" % get_action_key_name(0))
	display_game("")
	display_game("[color=#808080]Gold: %d | Gems: %d | Essence: %d[/color]" % [player_gold, player_gems, player_essence])
	update_action_bar()

func handle_blacksmith_upgrade_select_affix(message: Dictionary):
	"""Handle affix selection for upgrade"""
	blacksmith_upgrade_mode = "select_affix"
	blacksmith_upgrade_affixes = message.get("affixes", [])
	blacksmith_upgrade_item_name = message.get("item_name", "Item")
	var player_gold = message.get("player_gold", 0)
	var player_gems = message.get("player_gems", 0)
	var player_essence = message.get("player_essence", 0)

	game_output.clear()
	if blacksmith_trader_art != "":
		display_game(blacksmith_trader_art)
		display_game("")
	display_game(message.get("message", ""))
	display_game("")
	display_game("[color=#FFD700]=== Select Affix to Enhance ===[/color]")
	display_game("")

	for i in range(blacksmith_upgrade_affixes.size()):
		var affix = blacksmith_upgrade_affixes[i]
		var name = affix.get("affix_name", "Unknown")
		var current = affix.get("current_value", 0)
		var upgrade = affix.get("upgrade_amount", 0)
		var gold = affix.get("gold_cost", 0)
		var gems = affix.get("gem_cost", 0)
		var essence = affix.get("essence_cost", 0)

		var afford_gold = player_gold >= gold
		var afford_gems = player_gems >= gems
		var afford_essence = player_essence >= essence
		var can_afford = afford_gold and afford_gems and afford_essence
		var afford_color = "[color=#00FF00]" if can_afford else "[color=#FF0000]"

		display_game("[%s] %s: %d → %d (+%d)" % [str(i + 1), name, current, current + upgrade, upgrade])
		display_game("    %sCost: %d gold, %d gems, %d essence[/color]" % [afford_color, gold, gems, essence])

	display_game("")
	display_game("[%s] Back" % get_action_key_name(0))
	display_game("")
	display_game("[color=#808080]Gold: %d | Gems: %d | Essence: %d[/color]" % [player_gold, player_gems, player_essence])
	update_action_bar()

func handle_healer_encounter(message: Dictionary):
	"""Handle healer encounter display"""
	pending_healer = true
	healer_costs = {
		"quick": message.get("quick_heal_cost", 0),
		"full": message.get("full_heal_cost", 0),
		"cure_all": message.get("cure_all_cost", 0)
	}
	var has_debuffs = message.get("has_debuffs", false)
	var player_gold = message.get("player_gold", 0)
	var current_hp = message.get("current_hp", 0)
	var max_hp = message.get("max_hp", 100)

	# Reset all hotkey pressed states to prevent accidental immediate triggers
	for i in range(10):
		set_meta("hotkey_%d_pressed" % i, true)  # Mark as pressed so release is required first

	game_output.clear()

	# Display random trader ASCII art
	var trader_art = _get_trader_art().get_random_trader_art()
	display_game(trader_art)
	display_game("")

	display_game(message.get("message", ""))
	display_game("")
	display_game("[color=#00FF00]=== Healing Options ===[/color]")
	display_game("[color=#808080]Current HP: %d / %d[/color]" % [current_hp, max_hp])
	display_game("")

	# Quick heal (25% HP)
	var quick_afford = " [color=#FF0000](Not enough gold)[/color]" if player_gold < healer_costs.quick else ""
	display_game("[%s] Quick Heal (25%% HP) - %d gold%s" % [get_action_key_name(1), healer_costs.quick, quick_afford])

	# Full heal (100% HP)
	var full_afford = " [color=#FF0000](Not enough gold)[/color]" if player_gold < healer_costs.full else ""
	display_game("[%s] Full Heal (100%% HP) - %d gold%s" % [get_action_key_name(2), healer_costs.full, full_afford])

	# Cure All (100% HP + remove debuffs)
	var cure_afford = " [color=#FF0000](Not enough gold)[/color]" if player_gold < healer_costs.cure_all else ""
	var debuff_note = " [color=#808080](no active debuffs)[/color]" if not has_debuffs else ""
	display_game("[%s] Full + Cure All - %d gold%s%s" % [get_action_key_name(3), healer_costs.cure_all, cure_afford, debuff_note])

	display_game("")
	display_game("[%s] Decline" % get_action_key_name(0))
	display_game("")
	display_game("[color=#808080]Your gold: %d[/color]" % player_gold)

	update_action_bar()

func send_healer_choice(choice: String):
	"""Send healer choice to server"""
	send_to_server({"type": "healer_choice", "choice": choice})

# ===== FISHING FUNCTIONS =====

func start_fishing():
	"""Start the fishing minigame"""
	if not at_water:
		display_game("[color=#FF4444]You need to be at a water tile to fish![/color]")
		return

	if in_combat:
		display_game("[color=#FF4444]You can't fish while in combat![/color]")
		return

	if fishing_mode:
		display_game("[color=#808080]You're already fishing.[/color]")
		return

	# Request fishing start from server (validates cooldowns, gets wait time based on skill)
	send_to_server({"type": "fish_start", "water_type": fishing_water_type})

func handle_fish_start(message: Dictionary):
	"""Handle server response to start fishing"""
	# Server sends fish_start with data on success, or error message beforehand
	fishing_mode = true
	fishing_phase = "waiting"
	fishing_wait_timer = message.get("wait_time", 4.0)
	fishing_reaction_window = message.get("reaction_window", 1.5)
	fishing_water_type = message.get("water_type", "shallow")

	game_output.clear()
	display_fishing_waiting()
	update_action_bar()

func display_fishing_waiting():
	"""Display the fishing waiting screen with ASCII art"""
	var water_name = "Deep Waters" if fishing_water_type == "deep" else "Shallow Waters"
	display_game("[color=#00BFFF]===== Fishing: %s =====[/color]" % water_name)
	display_game("")
	# Simple fishing bobber ASCII art
	display_game("[color=#87CEEB]        ~  ~  ~  ~  ~[/color]")
	display_game("[color=#87CEEB]    ~        o        ~[/color]")
	display_game("[color=#87CEEB]        ~  ~│~  ~  ~[/color]")
	display_game("[color=#0077BE]    ≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈[/color]")
	display_game("[color=#005f87]    ≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋[/color]")
	display_game("")
	display_game("[color=#FFFF00]Your line is in the water...[/color]")
	display_game("[color=#808080]Wait for a bite![/color]")

func generate_gathering_pattern(tier: int) -> Array:
	"""Generate a DDR-style pattern based on tier.
	T1-2: 2 keys, T3-5: 3 keys, T6+: 4 keys"""
	var length = 2 if tier <= 2 else (3 if tier <= 5 else 4)
	var pattern = []
	for i in range(length):
		pattern.append(GATHERING_PATTERN_KEYS[randi() % GATHERING_PATTERN_KEYS.size()])
	return pattern

func get_pattern_display_string(pattern: Array, current_index: int) -> String:
	"""Format pattern for display with current key highlighted.
	Shows completed keys dimmed, current key bright, remaining keys normal."""
	var result = ""
	for i in range(pattern.size()):
		var key = pattern[i]
		if i < current_index:
			# Already pressed - show green checkmark
			result += "[color=#00AA00]✓[/color] "
		elif i == current_index:
			# Current key to press - bright yellow and larger
			result += "[color=#FFFF00][%s][/color] " % key
		else:
			# Upcoming - dimmed
			result += "[color=#808080]%s[/color] " % key
	return result.strip_edges()

func display_fishing_bite():
	"""Display the fishing bite screen - player must react with pattern"""
	game_output.clear()
	var water_name = "Deep Waters" if fishing_water_type == "deep" else "Shallow Waters"
	display_game("[color=#00BFFF]===== Fishing: %s =====[/color]" % water_name)
	display_game("")
	# Splashing bobber ASCII art
	display_game("[color=#87CEEB]    ~  ~ [color=#FFFF00]!!!![/color] ~  ~[/color]")
	display_game("[color=#87CEEB]      [color=#FFFFFF]* SPLASH *[/color][/color]")
	display_game("[color=#0077BE]    ≈≈[color=#FFFF00]><>[/color]≈≈≈≈≈≈≈≈≈≈≈≈[/color]")
	display_game("[color=#005f87]    ≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋≋[/color]")
	display_game("")
	display_game("[color=#FF4444][font_size=18]!!! FISH ON THE LINE !!![/font_size][/color]")
	display_game("")
	# Show the pattern to press
	var pattern_display = get_pattern_display_string(gathering_pattern, gathering_pattern_index)
	display_game("[color=#00FF00]Press the sequence: %s[/color]" % pattern_display)

func start_fishing_reaction_phase():
	"""Transition from waiting to reaction phase"""
	fishing_phase = "reaction"
	# Generate pattern based on tier (fishing uses shallow=1, deep=3 as tier equivalent)
	gathering_pattern_tier = 3 if fishing_water_type == "deep" else 1
	gathering_pattern = generate_gathering_pattern(gathering_pattern_tier)
	gathering_pattern_index = 0
	# Use reaction window from server (based on fishing skill) - multiply for pattern length
	fishing_reaction_timer = fishing_reaction_window * gathering_pattern.size() * 0.6

	display_fishing_bite()
	update_action_bar()

	# Play a notification sound for the bite
	play_whisper_notification()

func handle_fishing_pattern_key(key_pressed: String):
	"""Player pressed a pattern key during fishing - check if correct"""
	if not fishing_mode or fishing_phase != "reaction":
		return

	if gathering_pattern_index >= gathering_pattern.size():
		return  # Already complete

	var expected_key = gathering_pattern[gathering_pattern_index]
	if key_pressed == expected_key:
		# Correct key! Advance pattern
		gathering_pattern_index += 1
		if gathering_pattern_index >= gathering_pattern.size():
			# Pattern complete! Send success
			send_to_server({"type": "fish_catch", "success": true, "water_type": fishing_water_type})
		else:
			# More keys to go - refresh display
			display_fishing_bite()
			update_action_bar()
	else:
		# Wrong key - fish escapes
		end_fishing(false, "Wrong key! The fish escaped...")

func end_fishing(caught: bool, message: String = ""):
	"""End the fishing minigame"""
	fishing_mode = false
	fishing_phase = ""
	fishing_wait_timer = 0.0
	fishing_reaction_timer = 0.0
	fishing_target_slot = -1
	gathering_pattern = []
	gathering_pattern_index = 0

	if message != "":
		display_game("[color=#FF4444]%s[/color]" % message)

	update_action_bar()

func handle_fish_result(message: Dictionary):
	"""Handle the result of a fishing attempt from server"""
	fishing_mode = false
	fishing_phase = ""
	fishing_wait_timer = 0.0
	fishing_reaction_timer = 0.0
	fishing_target_slot = -1

	game_output.clear()

	if message.get("success", false):
		var catch_data = message.get("catch", {})
		var catch_name = catch_data.get("name", "something")
		var xp_gained = message.get("xp_gained", 0)
		var new_level = message.get("new_level", 1)
		var leveled_up = message.get("leveled_up", false)
		var main_message = message.get("message", "")
		var extra_messages = message.get("extra_messages", [])

		# Success ASCII art
		display_game("[color=#00FF00]===== CATCH! =====[/color]")
		display_game("")
		display_game("[color=#87CEEB]      ><>  [color=#FFD700]✦[/color]  <><[/color]")
		display_game("")
		# Display the server's catch message
		if main_message != "":
			display_game(main_message)
		if xp_gained > 0:
			display_game("[color=#00BFFF]+%d Fishing XP[/color]" % xp_gained)
		# Display any extra messages (level up, egg hatch steps, etc.)
		for extra_msg in extra_messages:
			display_game(extra_msg)
		display_game("")
		display_game("[color=#808080]Fishing skill: Level %d[/color]" % new_level)
		# Check if node was depleted
		if message.get("node_depleted", false):
			display_game("")
			display_game("[color=#FFAA00]The fishing spot has been exhausted. Search for another nearby![/color]")
	else:
		# Failure - fish escaped (timeout or wrong button)
		var fail_message = message.get("message", "The fish got away!")
		display_game("[color=#FF4444]===== Too Slow! =====[/color]")
		display_game("")
		display_game(fail_message)
		display_game("[color=#808080]Better luck next time![/color]")

	update_action_bar()

# ===== MINING FUNCTIONS =====

func start_mining():
	"""Start the mining minigame"""
	if not at_ore_deposit:
		display_game("[color=#FF4444]You need to be at an ore deposit to mine![/color]")
		return

	if in_combat:
		display_game("[color=#FF4444]You can't mine while in combat![/color]")
		return

	if mining_mode:
		display_game("[color=#808080]You're already mining.[/color]")
		return

	send_to_server({"type": "mine_start"})

func handle_mine_start(message: Dictionary):
	"""Handle server response to start mining"""
	mining_mode = true
	mining_phase = "waiting"
	mining_wait_timer = message.get("wait_time", 8.0)
	mining_reaction_window = message.get("reaction_window", 1.2)
	mining_current_tier = message.get("ore_tier", 1)
	mining_reactions_required = message.get("reactions_required", 1)
	mining_reactions_completed = 0

	game_output.clear()
	display_mining_waiting()
	update_action_bar()

func display_mining_waiting():
	"""Display the mining waiting screen"""
	display_game("[color=#C0C0C0]===== Mining: Tier %d Ore =====[/color]" % mining_current_tier)
	display_game("")
	display_game("[color=#808080]       /\\      /\\[/color]")
	display_game("[color=#808080]      /  \\    /  \\[/color]")
	display_game("[color=#A0522D]     / [color=#C0C0C0]◊◊[/color] \\/[color=#C0C0C0]◊◊[/color] \\[/color]")
	display_game("[color=#8B4513]    /   [color=#FFD700]○[/color]    [color=#FFD700]○[/color]   \\[/color]")
	display_game("[color=#654321]   /________________\\[/color]")
	display_game("")
	display_game("[color=#FFFF00]Swinging your pickaxe...[/color]")
	if mining_reactions_required > 1:
		display_game("[color=#808080]Progress: %d/%d strikes needed[/color]" % [mining_reactions_completed, mining_reactions_required])

func display_mining_strike():
	"""Display the mining strike screen with pattern"""
	game_output.clear()
	display_game("[color=#C0C0C0]===== Mining: Tier %d Ore =====[/color]" % mining_current_tier)
	display_game("")
	display_game("[color=#808080]       /\\[color=#FFFF00]⚡[/color]/\\[/color]")
	display_game("[color=#808080]      /  [color=#FF4444]★[/color]  \\[/color]")
	display_game("[color=#A0522D]     / [color=#C0C0C0]◊◊[/color] [color=#FFFFFF]*CRACK*[/color] \\[/color]")
	display_game("[color=#8B4513]    /        \\[/color]")
	display_game("[color=#654321]   /________________\\[/color]")
	display_game("")
	display_game("[color=#FF4444][font_size=18]!!! STRIKE NOW !!![/font_size][/color]")
	display_game("")
	# Show the pattern to press
	var pattern_display = get_pattern_display_string(gathering_pattern, gathering_pattern_index)
	display_game("[color=#00FF00]Press the sequence: %s[/color]" % pattern_display)
	if mining_reactions_required > 1:
		display_game("[color=#808080]Strike %d of %d[/color]" % [mining_reactions_completed + 1, mining_reactions_required])

func start_mining_reaction_phase():
	"""Transition to mining reaction phase"""
	mining_phase = "reaction"
	# Generate pattern based on ore tier
	gathering_pattern_tier = mining_current_tier
	gathering_pattern = generate_gathering_pattern(gathering_pattern_tier)
	gathering_pattern_index = 0
	# Reaction time scales with pattern length
	mining_reaction_timer = mining_reaction_window * gathering_pattern.size() * 0.6

	display_mining_strike()
	update_action_bar()
	play_whisper_notification()

func handle_mining_pattern_key(key_pressed: String):
	"""Player pressed a pattern key during mining - check if correct"""
	if not mining_mode or mining_phase != "reaction":
		return

	if gathering_pattern_index >= gathering_pattern.size():
		return  # Already complete

	var expected_key = gathering_pattern[gathering_pattern_index]
	if key_pressed == expected_key:
		# Correct key! Advance pattern
		gathering_pattern_index += 1
		if gathering_pattern_index >= gathering_pattern.size():
			# Pattern complete! Count as one successful reaction
			mining_reactions_completed += 1
			if mining_reactions_completed >= mining_reactions_required:
				# All strikes successful
				send_to_server({"type": "mine_catch", "success": true, "ore_tier": mining_current_tier})
			else:
				# Need more strikes - go back to waiting with new pattern
				mining_phase = "waiting"
				mining_wait_timer = mining_reaction_window * 1.5
				gathering_pattern = []
				gathering_pattern_index = 0
				game_output.clear()
				display_mining_waiting()
				display_game("[color=#00FF00]Good strike![/color]")
				update_action_bar()
		else:
			# More keys to go - refresh display
			display_mining_strike()
			update_action_bar()
	else:
		# Wrong key - partial failure
		send_to_server({"type": "mine_catch", "success": false, "partial_success": mining_reactions_completed, "ore_tier": mining_current_tier})

func end_mining(success: bool, message: String = ""):
	"""End the mining minigame"""
	mining_mode = false
	mining_phase = ""
	mining_wait_timer = 0.0
	mining_reaction_timer = 0.0
	mining_target_slot = -1
	mining_reactions_completed = 0
	gathering_pattern = []
	gathering_pattern_index = 0

	if message != "":
		display_game("[color=#FF4444]%s[/color]" % message)

	update_action_bar()

func handle_mine_result(message: Dictionary):
	"""Handle the result of a mining attempt from server"""
	mining_mode = false
	mining_phase = ""
	mining_wait_timer = 0.0
	mining_reaction_timer = 0.0
	mining_target_slot = -1
	mining_reactions_completed = 0
	gathering_pattern = []
	gathering_pattern_index = 0

	game_output.clear()

	if message.get("success", false):
		var catch_data = message.get("catch", {})
		var quantity = message.get("quantity", 1)
		var xp_gained = message.get("xp_gained", 0)
		var new_level = message.get("new_level", 1)
		var main_message = message.get("message", "")
		var extra_messages = message.get("extra_messages", [])

		display_game("[color=#C0C0C0]===== SUCCESS! =====[/color]")
		display_game("")
		display_game("[color=#808080]  [color=#FFD700]◊[/color]  [color=#C0C0C0]◊◊[/color]  [color=#FFD700]◊[/color][/color]")
		display_game("")
		if main_message != "":
			display_game(main_message)
		if xp_gained > 0:
			display_game("[color=#C0C0C0]+%d Mining XP[/color]" % xp_gained)
		for extra_msg in extra_messages:
			display_game(extra_msg)
		display_game("")
		display_game("[color=#808080]Mining skill: Level %d[/color]" % new_level)
		# Check if node was depleted
		if message.get("node_depleted", false):
			display_game("")
			display_game("[color=#FFAA00]The ore vein is exhausted. Search for another nearby![/color]")
	else:
		var fail_message = message.get("message", "The vein crumbled!")
		display_game("[color=#FF4444]===== Failed! =====[/color]")
		display_game("")
		display_game(fail_message)

	update_action_bar()

# ===== LOGGING FUNCTIONS =====

func start_logging():
	"""Start the logging minigame"""
	if not at_dense_forest:
		display_game("[color=#FF4444]You need to be at a harvestable tree to chop![/color]")
		return

	if in_combat:
		display_game("[color=#FF4444]You can't chop while in combat![/color]")
		return

	if logging_mode:
		display_game("[color=#808080]You're already chopping.[/color]")
		return

	send_to_server({"type": "log_start"})

func handle_log_start(message: Dictionary):
	"""Handle server response to start logging"""
	logging_mode = true
	logging_phase = "waiting"
	logging_wait_timer = message.get("wait_time", 8.0)
	logging_reaction_window = message.get("reaction_window", 1.2)
	logging_current_tier = message.get("wood_tier", 1)
	logging_reactions_required = message.get("reactions_required", 1)
	logging_reactions_completed = 0

	game_output.clear()
	display_logging_waiting()
	update_action_bar()

func display_logging_waiting():
	"""Display the logging waiting screen"""
	display_game("[color=#8B4513]===== Logging: Tier %d Wood =====[/color]" % logging_current_tier)
	display_game("")
	display_game("[color=#228B22]        🌲[/color]")
	display_game("[color=#228B22]       /|\\[/color]")
	display_game("[color=#228B22]      / | \\[/color]")
	display_game("[color=#228B22]     /  |  \\[/color]")
	display_game("[color=#8B4513]       |||[/color]")
	display_game("[color=#654321]      ░░░░░[/color]")
	display_game("")
	display_game("[color=#FFFF00]Swinging your axe...[/color]")
	if logging_reactions_required > 1:
		display_game("[color=#808080]Progress: %d/%d chops needed[/color]" % [logging_reactions_completed, logging_reactions_required])

func display_logging_chop():
	"""Display the logging chop screen with pattern"""
	game_output.clear()
	display_game("[color=#8B4513]===== Logging: Tier %d Wood =====[/color]" % logging_current_tier)
	display_game("")
	display_game("[color=#228B22]        🌲 [color=#FFFF00]⚡[/color][/color]")
	display_game("[color=#228B22]       /|[color=#FFFFFF]*CRACK*[/color][/color]")
	display_game("[color=#228B22]      / |[/color]")
	display_game("[color=#228B22]     /  |[/color]")
	display_game("[color=#8B4513]       |||[/color]")
	display_game("[color=#654321]      ░░░░░[/color]")
	display_game("")
	display_game("[color=#FF4444][font_size=18]!!! CHOP NOW !!![/font_size][/color]")
	display_game("")
	# Show the pattern to press
	var pattern_display = get_pattern_display_string(gathering_pattern, gathering_pattern_index)
	display_game("[color=#00FF00]Press the sequence: %s[/color]" % pattern_display)
	if logging_reactions_required > 1:
		display_game("[color=#808080]Chop %d of %d[/color]" % [logging_reactions_completed + 1, logging_reactions_required])

func start_logging_reaction_phase():
	"""Transition to logging reaction phase"""
	logging_phase = "reaction"
	# Generate pattern based on wood tier
	gathering_pattern_tier = logging_current_tier
	gathering_pattern = generate_gathering_pattern(gathering_pattern_tier)
	gathering_pattern_index = 0
	# Reaction time scales with pattern length
	logging_reaction_timer = logging_reaction_window * gathering_pattern.size() * 0.6

	display_logging_chop()
	update_action_bar()
	play_whisper_notification()

func handle_logging_pattern_key(key_pressed: String):
	"""Player pressed a pattern key during logging - check if correct"""
	if not logging_mode or logging_phase != "reaction":
		return

	if gathering_pattern_index >= gathering_pattern.size():
		return  # Already complete

	var expected_key = gathering_pattern[gathering_pattern_index]
	if key_pressed == expected_key:
		# Correct key! Advance pattern
		gathering_pattern_index += 1
		if gathering_pattern_index >= gathering_pattern.size():
			# Pattern complete! Count as one successful reaction
			logging_reactions_completed += 1
			if logging_reactions_completed >= logging_reactions_required:
				# All chops successful
				send_to_server({"type": "log_catch", "success": true, "wood_tier": logging_current_tier})
			else:
				# Need more chops - go back to waiting with new pattern
				logging_phase = "waiting"
				logging_wait_timer = logging_reaction_window * 1.5
				gathering_pattern = []
				gathering_pattern_index = 0
				game_output.clear()
				display_logging_waiting()
				display_game("[color=#00FF00]Good chop![/color]")
				update_action_bar()
		else:
			# More keys to go - refresh display
			display_logging_chop()
			update_action_bar()
	else:
		# Wrong key - partial failure
		send_to_server({"type": "log_catch", "success": false, "partial_success": logging_reactions_completed, "wood_tier": logging_current_tier})

func end_logging(success: bool, message: String = ""):
	"""End the logging minigame"""
	logging_mode = false
	logging_phase = ""
	logging_wait_timer = 0.0
	logging_reaction_timer = 0.0
	logging_target_slot = -1
	logging_reactions_completed = 0

	if message != "":
		display_game("[color=#FF4444]%s[/color]" % message)

	update_action_bar()

func handle_log_result(message: Dictionary):
	"""Handle the result of a logging attempt from server"""
	logging_mode = false
	logging_phase = ""
	logging_wait_timer = 0.0
	logging_reaction_timer = 0.0
	logging_target_slot = -1
	logging_reactions_completed = 0
	gathering_pattern = []
	gathering_pattern_index = 0

	game_output.clear()

	if message.get("success", false):
		var catch_data = message.get("catch", {})
		var quantity = message.get("quantity", 1)
		var xp_gained = message.get("xp_gained", 0)
		var new_level = message.get("new_level", 1)
		var main_message = message.get("message", "")
		var extra_messages = message.get("extra_messages", [])

		display_game("[color=#8B4513]===== SUCCESS! =====[/color]")
		display_game("")
		display_game("[color=#228B22]  🌲  [color=#8B4513]█[/color]  🌲[/color]")
		display_game("")
		if main_message != "":
			display_game(main_message)
		if xp_gained > 0:
			display_game("[color=#8B4513]+%d Logging XP[/color]" % xp_gained)
		for extra_msg in extra_messages:
			display_game(extra_msg)
		display_game("")
		display_game("[color=#808080]Logging skill: Level %d[/color]" % new_level)
		# Check if node was depleted
		if message.get("node_depleted", false):
			display_game("")
			display_game("[color=#FFAA00]The tree is fully harvested. Search for another nearby![/color]")
	else:
		var fail_message = message.get("message", "The branch broke!")
		display_game("[color=#FF4444]===== Failed! =====[/color]")
		display_game("")
		display_game(fail_message)

	update_action_bar()

# ===== CRAFTING FUNCTIONS =====

func open_crafting():
	"""Open the crafting menu"""
	if not at_trading_post:
		display_game("[color=#FF4444]You can only craft at Trading Posts![/color]")
		return

	crafting_mode = true
	crafting_skill = ""
	crafting_recipes = []
	crafting_selected_recipe = -1
	crafting_page = 0

	game_output.clear()
	display_game("[color=#FFD700]===== CRAFTING =====[/color]")
	display_game("")
	display_game("Select a crafting skill:")
	display_game("")
	display_game("[%s] [color=#FF6600]Blacksmithing[/color] - Weapons & Armor" % get_action_key_name(1))
	display_game("[%s] [color=#00FF00]Alchemy[/color] - Potions & Consumables" % get_action_key_name(2))
	display_game("[%s] [color=#A335EE]Enchanting[/color] - Enhance Equipment" % get_action_key_name(3))
	display_game("")
	display_game("[%s] Back to Trading Post" % get_action_key_name(0))

	update_action_bar()

func request_craft_list(skill_name: String):
	"""Request recipe list from server for a skill"""
	crafting_skill = skill_name
	send_to_server({"type": "craft_list", "skill": skill_name})

func handle_craft_list(message: Dictionary):
	"""Handle recipe list from server"""
	# Store data but don't display if waiting for player to acknowledge craft result
	crafting_skill = message.get("skill", "blacksmithing")
	crafting_skill_level = message.get("skill_level", 1)
	crafting_post_bonus = message.get("post_bonus", 0)
	crafting_recipes = message.get("recipes", [])
	crafting_materials = message.get("materials", {})
	crafting_page = 0
	crafting_selected_recipe = -1

	if awaiting_craft_result:
		# Don't clear the craft result display - player hasn't acknowledged it yet
		return

	display_craft_recipe_list()
	update_action_bar()

func display_craft_recipe_list():
	"""Display the list of available recipes"""
	game_output.clear()

	var skill_display = crafting_skill.capitalize()
	var skill_color = "#FFFFFF"
	match crafting_skill:
		"blacksmithing":
			skill_color = "#FF6600"
		"alchemy":
			skill_color = "#00FF00"
		"enchanting":
			skill_color = "#A335EE"

	display_game("[color=%s]===== %s (Level %d) =====[/color]" % [skill_color, skill_display, crafting_skill_level])
	if crafting_post_bonus > 0:
		display_game("[color=#00FFFF]Trading Post Bonus: +%d%% success[/color]" % crafting_post_bonus)
	display_game("")

	if crafting_recipes.is_empty():
		display_game("[color=#808080]No recipes available for this skill.[/color]")
		display_game("")
		display_game("[%s] Back" % get_action_key_name(0))
		return

	# Paginate recipes
	var start_idx = crafting_page * CRAFTING_PAGE_SIZE
	var end_idx = min(start_idx + CRAFTING_PAGE_SIZE, crafting_recipes.size())
	var total_pages = max(1, ceili(float(crafting_recipes.size()) / CRAFTING_PAGE_SIZE))

	display_game("Recipes (Page %d/%d):" % [crafting_page + 1, total_pages])
	display_game("")

	for i in range(start_idx, end_idx):
		var recipe = crafting_recipes[i]
		var display_idx = (i - start_idx) + 1  # 1-5 for display
		var is_locked = recipe.get("locked", false)
		var can_craft = recipe.get("can_craft", false)
		var success_chance = recipe.get("success_chance", 50)
		var name = recipe.get("name", "Unknown")
		var skill_req = recipe.get("skill_required", 1)
		var description = recipe.get("description", "")

		if is_locked:
			# Locked recipe - show with lock icon and unlock level
			display_game("[color=#555555][%s] %s (Unlocks at Lv%d)[/color]" % [
				get_action_key_name(display_idx + 4), name, skill_req
			])
			if description != "":
				display_game("[color=#444444]    %s[/color]" % description)
		else:
			# Unlocked recipe
			var color = "#00FF00" if can_craft else "#808080"
			var craftable_text = "" if can_craft else " [color=#FF4444](Missing materials)[/color]"
			display_game("[%s] [color=%s]%s[/color] (Lv%d) - %d%% success%s" % [
				get_action_key_name(display_idx + 4),  # Keys 1-5 map to action slots 5-9
				color, name, skill_req, success_chance, craftable_text
			])
			if description != "":
				display_game("[color=#888888]    %s[/color]" % description)

	display_game("")
	display_game("[%s] Back | [%s/%s] Prev/Next Page" % [get_action_key_name(0), get_action_key_name(8), get_action_key_name(9)])

func select_craft_recipe(index: int):
	"""Select a recipe to view details/confirm crafting"""
	var actual_idx = crafting_page * CRAFTING_PAGE_SIZE + index
	if actual_idx >= crafting_recipes.size():
		return

	var recipe = crafting_recipes[actual_idx]
	if recipe.get("locked", false):
		var skill_req = recipe.get("skill_required", 1)
		display_game("[color=#FF4444]This recipe requires %s level %d to unlock![/color]" % [crafting_skill.capitalize(), skill_req])
		return

	crafting_selected_recipe = actual_idx
	display_craft_recipe_details()
	update_action_bar()

func display_craft_recipe_details():
	"""Display details of selected recipe"""
	if crafting_selected_recipe < 0 or crafting_selected_recipe >= crafting_recipes.size():
		return

	var recipe = crafting_recipes[crafting_selected_recipe]
	var name = recipe.get("name", "Unknown")
	var skill_req = recipe.get("skill_required", 1)
	var difficulty = recipe.get("difficulty", 10)
	var success_chance = recipe.get("success_chance", 50)
	var can_craft = recipe.get("can_craft", false)
	var materials = recipe.get("materials", {})

	game_output.clear()
	display_game("[color=#FFD700]===== %s =====[/color]" % name)
	display_game("")
	display_game("Skill Required: %d" % skill_req)
	display_game("Difficulty: %d" % difficulty)
	display_game("Success Chance: [color=#00FF00]%d%%[/color]" % success_chance)
	display_game("")
	display_game("[color=#87CEEB]Materials Required:[/color]")

	# Display materials with owned count
	for mat_id in materials:
		var required = materials[mat_id]
		var owned = crafting_materials.get(mat_id, 0)
		var mat_name = mat_id.capitalize().replace("_", " ")
		var color = "#00FF00" if owned >= required else "#FF4444"
		display_game("  [color=%s]%s: %d/%d[/color]" % [color, mat_name, owned, required])

	display_game("")
	display_game("[color=#808080]Quality depends on skill vs difficulty.[/color]")
	display_game("[color=#808080]Higher skill = better quality items![/color]")
	display_game("")

	if can_craft:
		display_game("[%s] [color=#00FF00]CRAFT![/color] | [%s] Cancel" % [get_action_key_name(1), get_action_key_name(0)])
	else:
		display_game("[color=#FF4444]Missing required materials![/color]")
		display_game("[%s] Cancel" % get_action_key_name(0))

func confirm_craft():
	"""Send craft request to server"""
	if crafting_selected_recipe < 0 or crafting_selected_recipe >= crafting_recipes.size():
		return

	var recipe = crafting_recipes[crafting_selected_recipe]
	var recipe_id = recipe.get("id", "")

	send_to_server({"type": "craft_item", "recipe_id": recipe_id})

func handle_craft_result(message: Dictionary):
	"""Handle crafting result from server"""
	var success = message.get("success", false)
	var recipe_name = message.get("recipe_name", "item")
	var quality_name = message.get("quality_name", "Standard")
	var quality_color = message.get("quality_color", "#FFFFFF")
	var xp_gained = message.get("xp_gained", 0)
	var leveled_up = message.get("leveled_up", false)
	var new_level = message.get("new_level", 1)
	var skill_name = message.get("skill_name", "crafting")
	var result_message = message.get("message", "")

	game_output.clear()

	if success:
		# Success animation
		display_game("[color=#00FF00]===== CRAFTING SUCCESS! =====[/color]")
		display_game("")
		display_game("[color=%s]✦ %s %s ✦[/color]" % [quality_color, quality_name, recipe_name])
		display_game("")
		display_game(result_message)
	else:
		# Failure
		display_game("[color=#FF4444]===== CRAFTING FAILED =====[/color]")
		display_game("")
		display_game(result_message)

	display_game("")
	display_game("[color=#00BFFF]+%d %s XP[/color]" % [xp_gained, skill_name.capitalize()])

	if leveled_up:
		display_game("[color=#FFFF00]★ %s skill increased to %d! ★[/color]" % [skill_name.capitalize(), new_level])

	display_game("")
	display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))

	# Set flag to prevent craft_list from overwriting the result
	awaiting_craft_result = true
	crafting_selected_recipe = -1
	update_action_bar()

func close_crafting():
	"""Close crafting menu and return to trading post"""
	crafting_mode = false
	crafting_skill = ""
	crafting_recipes = []
	crafting_selected_recipe = -1
	crafting_page = 0
	awaiting_craft_result = false

	_display_trading_post_ui()
	update_action_bar()

# ===== DUNGEON FUNCTIONS =====

func request_dungeon_list():
	"""Request list of nearby dungeons from server"""
	send_to_server({"type": "dungeon_list"})

func handle_dungeon_list(message: Dictionary):
	"""Handle list of available dungeons from server"""
	dungeon_available = message.get("dungeons", [])

	if dungeon_available.is_empty():
		display_game("[color=#808080]No dungeons are currently available nearby.[/color]")
		display_game("[color=#808080]Dungeons spawn at random locations - keep exploring![/color]")
		return

	dungeon_list_mode = true
	game_output.clear()
	display_game("[color=#FFD700]===== NEARBY DUNGEONS =====[/color]")
	display_game("")

	var idx = 1
	for dungeon in dungeon_available:
		var name = dungeon.get("name", "Unknown Dungeon")
		var tier = dungeon.get("tier", 1)
		var min_level = dungeon.get("min_level", 1)
		var max_level = dungeon.get("max_level", 100)
		var distance = dungeon.get("distance", 0)
		var color = dungeon.get("color", "#FFFFFF")
		var completions = dungeon.get("completions", 0)

		var status = ""
		if completions > 0:
			status = "[color=#00FF00](%d clears)[/color]" % completions

		display_game("[%d] [color=%s]%s[/color] %s" % [idx, color, name, status])
		display_game("    Tier %d | Levels %d-%d | Distance: %d tiles" % [tier, min_level, max_level, distance])
		display_game("")
		idx += 1

	display_game("[color=#808080]Enter a dungeon number to explore, or press [%s] to cancel.[/color]" % get_action_key_name(0))
	update_action_bar()

func handle_dungeon_state(message: Dictionary):
	"""Handle dungeon state update from server"""
	dungeon_mode = true
	dungeon_list_mode = false
	dungeon_data = message
	dungeon_floor_grid = message.get("grid", [])

	# Always update the map display (right panel) so player position is current
	update_dungeon_map()

	# Only update GameOutput if player doesn't need to acknowledge something
	# (e.g., combat victory, treasure found, floor change)
	if not pending_continue:
		display_dungeon_floor()
	update_action_bar()

func handle_dungeon_treasure(message: Dictionary):
	"""Handle opening a treasure chest in dungeon"""
	var gold = message.get("gold", 0)
	var materials = message.get("materials", [])
	var egg = message.get("egg", {})

	game_output.clear()
	display_game("[color=#FFD700]===== TREASURE! =====[/color]")
	display_game("")
	display_game("[color=#FFD700]  $$$[/color]")
	display_game("[color=#8B4513] [===][/color]")
	display_game("")

	display_game("[color=#FFD700]Found %d gold![/color]" % gold)

	if not materials.is_empty():
		display_game("")
		display_game("[color=#87CEEB]Materials:[/color]")
		for mat in materials:
			var mat_name = mat.get("id", "unknown").capitalize().replace("_", " ")
			var quantity = mat.get("quantity", 1)
			display_game("  + %d x %s" % [quantity, mat_name])

	if not egg.is_empty():
		var egg_monster = egg.get("monster", "Unknown")
		display_game("")
		display_game("[color=#A335EE]★ Found a %s Egg! ★[/color]" % egg_monster)

	display_game("")
	display_game("[color=#808080]Move to continue exploring...[/color]")

	# Don't set pending_continue - player can move immediately
	# Movement will naturally request fresh dungeon state
	update_action_bar()

func handle_dungeon_floor_change(message: Dictionary):
	"""Handle advancing to next dungeon floor"""
	var new_floor = message.get("floor", 1)
	var total_floors = message.get("total_floors", 1)
	var dungeon_name = message.get("dungeon_name", "Dungeon")

	game_output.clear()
	display_game("[color=#FFFF00]===== FLOOR %d =====[/color]" % new_floor)
	display_game("")
	display_game("You descend deeper into the %s..." % dungeon_name)
	display_game("")

	if new_floor == total_floors:
		display_game("[color=#FF4444]This is the final floor. The boss awaits![/color]")
	else:
		display_game("Floors remaining: %d" % (total_floors - new_floor))

	display_game("")
	# Immediately show the dungeon floor grid
	display_dungeon_floor()
	update_action_bar()

func handle_dungeon_complete(message: Dictionary):
	"""Handle dungeon completion"""
	dungeon_mode = false
	dungeon_data = {}
	dungeon_floor_grid = []

	# If player is still viewing combat results or in flock mode, queue this for after they acknowledge
	# This handles bosses with flock abilities - the dungeon completes when boss dies, but
	# player still needs to fight the flock before seeing the completion message
	if pending_continue or flock_pending:
		queued_dungeon_complete = message.duplicate(true)
		return

	_display_dungeon_complete(message)

func _display_dungeon_complete(message: Dictionary):
	"""Display the dungeon completion screen"""
	var dungeon_name = message.get("dungeon_name", "Dungeon")
	var rewards = message.get("rewards", {})
	var floors_cleared = rewards.get("floors_cleared", 0)
	var total_floors = rewards.get("total_floors", 0)
	var xp_reward = rewards.get("xp", 0)
	var gold_reward = rewards.get("gold", 0)
	var full_clear = rewards.get("full_clear", false)
	var boss_egg_obtained = message.get("boss_egg_obtained", false)
	var boss_egg_name = message.get("boss_egg_name", "")
	var boss_egg_lost = message.get("boss_egg_lost_to_full", false)

	game_output.clear()

	if full_clear:
		display_game("[color=#00FF00]===== DUNGEON COMPLETE! =====[/color]")
		display_game("")
		display_game("[color=#FFD700]★★★ VICTORY! ★★★[/color]")
	else:
		display_game("[color=#FFFF00]===== DUNGEON CLEARED =====[/color]")

	display_game("")
	display_game("You have conquered the %s!" % dungeon_name)
	display_game("Floors cleared: %d/%d" % [floors_cleared, total_floors])
	display_game("")
	display_game("[color=#FFD700]Rewards:[/color]")
	display_game("  + %d XP" % xp_reward)
	display_game("  + %d Gold" % gold_reward)
	if boss_egg_obtained:
		display_game("[color=#FF69B4]  ★ %s obtained! ★[/color]" % boss_egg_name)
	elif boss_egg_lost:
		display_game("[color=#FF6666]  ★ %s found but eggs full! ★[/color]" % boss_egg_name)
	display_game("")
	display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))

	pending_continue = true
	update_action_bar()

func handle_dungeon_level_warning(message: Dictionary):
	"""Handle warning about entering a dungeon below recommended level"""
	pending_dungeon_warning = {
		"dungeon_type": message.get("dungeon_type", ""),
		"dungeon_name": message.get("dungeon_name", "Dungeon"),
		"min_level": message.get("min_level", 1),
		"player_level": message.get("player_level", 1)
	}

	game_output.clear()
	display_game("[color=#FF4444]═══════ WARNING ═══════[/color]")
	display_game("")
	display_game("[color=#FFAA00]%s[/color]" % message.get("message", "This dungeon may be too dangerous!"))
	display_game("")
	display_game("[color=#FF6666]Recommended Level: %d[/color]" % message.min_level)
	display_game("[color=#AAAAAA]Your Level: %d[/color]" % message.player_level)
	display_game("")
	display_game("[color=#808080]Press [%s] to enter anyway, or [%s] to cancel.[/color]" % [get_action_key_name(0), get_action_key_name(1)])

	update_action_bar()

func handle_dungeon_exit(message: Dictionary):
	"""Handle exiting a dungeon (voluntary or death)"""
	dungeon_mode = false
	dungeon_data = {}
	dungeon_floor_grid = []

	var reason = message.get("reason", "exit")
	var dungeon_name = message.get("dungeon_name", "Dungeon")

	game_output.clear()

	if reason == "fled":
		display_game("[color=#FF4444]===== RETREAT =====[/color]")
		display_game("")
		display_game("You fled from the %s." % dungeon_name)
		display_game("[color=#808080]The dungeon resets behind you.[/color]")
	else:
		display_game("[color=#808080]You left the %s.[/color]" % dungeon_name)

	update_action_bar()

func handle_egg_hatched(message: Dictionary):
	"""Handle egg hatching notification with sound and Continue prompt"""
	var companion = message.get("companion", {})
	var companion_name = companion.get("name", "Companion")
	var variant = companion.get("variant", "Normal")
	var variant_color = companion.get("variant_color", "#FFFFFF")
	var tier = companion.get("tier", 1)
	var bonuses = companion.get("bonuses", {})

	# Play celebration sound
	play_egg_hatch_sound()

	# Display hatching celebration
	game_output.clear()
	display_game("[color=#FF69B4]═══════════════════════════════════════[/color]")
	display_game("")
	display_game("[color=#FFD700]✦ ✦ ✦  EGG HATCHED!  ✦ ✦ ✦[/color]")
	display_game("")
	display_game("[color=#FF69B4]═══════════════════════════════════════[/color]")
	display_game("")
	display_game("Your egg has hatched into:")
	display_game("")
	display_game("  [color=%s]%s %s[/color]" % [variant_color, variant, companion_name])
	display_game("  [color=#AAAAAA]Tier %d Companion[/color]" % tier)
	display_game("")

	# Show companion bonuses
	if not bonuses.is_empty():
		display_game("[color=#00FFFF]Companion Bonuses:[/color]")
		var bonus_lines = []
		if bonuses.has("attack") and bonuses.attack > 0:
			bonus_lines.append("  +%d Attack" % bonuses.attack)
		if bonuses.has("defense") and bonuses.defense > 0:
			bonus_lines.append("  +%d Defense" % bonuses.defense)
		if bonuses.has("hp_bonus") and bonuses.hp_bonus > 0:
			bonus_lines.append("  +%d Max HP" % bonuses.hp_bonus)
		if bonuses.has("hp_regen") and bonuses.hp_regen > 0:
			bonus_lines.append("  +%d HP Regen" % bonuses.hp_regen)
		if bonuses.has("crit_chance") and bonuses.crit_chance > 0:
			bonus_lines.append("  +%d%% Crit Chance" % bonuses.crit_chance)
		if bonuses.has("gold_find") and bonuses.gold_find > 0:
			bonus_lines.append("  +%d%% Gold Find" % bonuses.gold_find)
		if bonuses.has("speed") and bonuses.speed > 0:
			bonus_lines.append("  +%d Speed" % bonuses.speed)
		if bonuses.has("lifesteal") and bonuses.lifesteal > 0:
			bonus_lines.append("  +%d%% Lifesteal" % bonuses.lifesteal)
		if bonuses.has("flee_bonus") and bonuses.flee_bonus > 0:
			bonus_lines.append("  +%d%% Flee Chance" % bonuses.flee_bonus)
		for line in bonus_lines:
			display_game("[color=#00FF00]%s[/color]" % line)
		display_game("")

	display_game("[color=#808080]Visit the Companions menu to activate your new companion![/color]")
	display_game("")
	display_game("[color=#808080]Press [%s] to continue...[/color]" % get_action_key_name(0))

	pending_continue = true
	update_action_bar()

func display_dungeon_floor():
	"""Display the current dungeon floor - map goes in MapDisplay, status in GameOutput"""
	if not dungeon_mode or dungeon_data.is_empty():
		return

	var dungeon_name = dungeon_data.get("dungeon_name", "Dungeon")
	var dungeon_color = dungeon_data.get("color", "#FFFFFF")
	var floor_num = dungeon_data.get("floor", 1)
	var total_floors = dungeon_data.get("total_floors", 1)
	var player_x = dungeon_data.get("player_x", 0)
	var player_y = dungeon_data.get("player_y", 0)
	var encounters_cleared = dungeon_data.get("encounters_cleared", 0)

	# Render the dungeon grid
	var grid_display = _render_dungeon_grid(dungeon_floor_grid, player_x, player_y)

	# Update map_display panel with dungeon map (right side panel)
	if map_display:
		var map_text = "[color=%s]%s[/color]\n" % [dungeon_color, dungeon_name]
		map_text += "Floor %d/%d\n\n" % [floor_num, total_floors]
		map_text += grid_display
		map_text += "\n\n[color=#808080]@ You  ? Fight\n$ Loot  > Exit\nB Boss[/color]"
		map_display.clear()
		map_display.append_text(map_text)

	# GameOutput shows dungeon status (not the map)
	game_output.clear()
	display_game("[color=%s]===== %s =====[/color]" % [dungeon_color, dungeon_name])
	display_game("Floor %d/%d | Encounters cleared: %d" % [floor_num, total_floors, encounters_cleared])
	display_game("")
	display_game("Use [color=#FFFF00]N/S/W/E[/color] to move through the dungeon.")
	display_game("Press [color=#FFFF00][%s][/color] to exit." % get_action_key_name(0))
	display_game("")
	display_game("[color=#808080]The dungeon map is displayed on the right.[/color]")

func update_dungeon_map():
	"""Update just the dungeon map display (right panel) without touching GameOutput"""
	if not dungeon_mode or dungeon_data.is_empty():
		return

	var dungeon_name = dungeon_data.get("dungeon_name", "Dungeon")
	var dungeon_color = dungeon_data.get("color", "#FFFFFF")
	var floor_num = dungeon_data.get("floor", 1)
	var total_floors = dungeon_data.get("total_floors", 1)
	var player_x = dungeon_data.get("player_x", 0)
	var player_y = dungeon_data.get("player_y", 0)

	var grid_display = _render_dungeon_grid(dungeon_floor_grid, player_x, player_y)

	if map_display:
		var map_text = "[color=%s]%s[/color]\n" % [dungeon_color, dungeon_name]
		map_text += "Floor %d/%d\n\n" % [floor_num, total_floors]
		map_text += grid_display
		map_text += "\n\n[color=#808080]@ You  ? Fight\n$ Loot  > Exit\nB Boss[/color]"
		map_display.clear()
		map_display.append_text(map_text)

func _render_dungeon_grid(grid: Array, player_x: int, player_y: int) -> String:
	"""Render dungeon grid to BBCode string"""
	if grid.is_empty():
		return "[color=#808080]No floor data[/color]"

	var lines = []
	var width = grid[0].size() if grid.size() > 0 else 0

	# Top border
	lines.append("[color=#FFD700]+" + "-".repeat(width) + "+[/color]")

	# Grid rows
	for y in range(grid.size()):
		var line = "[color=#FFD700]|[/color]"
		for x in range(grid[y].size()):
			if x == player_x and y == player_y:
				line += "[color=#00FF00]@[/color]"
			else:
				var tile = grid[y][x]
				var tile_info = _get_dungeon_tile_display(tile)
				line += "[color=%s]%s[/color]" % [tile_info.color, tile_info.char]
		line += "[color=#FFD700]|[/color]"
		lines.append(line)

	# Bottom border
	lines.append("[color=#FFD700]+" + "-".repeat(width) + "+[/color]")

	return "\n".join(lines)

func _get_dungeon_tile_display(tile_type: int) -> Dictionary:
	"""Get display character and color for a dungeon tile type"""
	# Matches DungeonDatabase.TileType enum
	match tile_type:
		0:  # EMPTY
			return {"char": ".", "color": "#404040"}
		1:  # WALL
			return {"char": "#", "color": "#808080"}
		2:  # ENTRANCE
			return {"char": "E", "color": "#00FF00"}
		3:  # EXIT
			return {"char": ">", "color": "#FFFF00"}
		4:  # ENCOUNTER
			return {"char": "?", "color": "#FF4444"}
		5:  # TREASURE
			return {"char": "$", "color": "#FFD700"}
		6:  # BOSS
			return {"char": "B", "color": "#FF0000"}
		7:  # CLEARED
			return {"char": "·", "color": "#303030"}
		_:
			return {"char": "?", "color": "#FFFFFF"}

func _display_dungeon_entrance_info():
	"""Display information about the dungeon at the player's current location"""
	if dungeon_entrance_info.is_empty():
		return

	var dungeon_name = dungeon_entrance_info.get("name", "Dungeon")
	var color = dungeon_entrance_info.get("color", "#FFFFFF")
	var tier = dungeon_entrance_info.get("tier", 1)
	var min_level = dungeon_entrance_info.get("min_level", 1)
	var max_level = dungeon_entrance_info.get("max_level", 100)
	var player_level = character_data.get("level", 1)

	display_game("")
	display_game("[color=%s]===== %s =====[/color]" % [color, dungeon_name])
	display_game("Tier %d Dungeon | Levels %d-%d" % [tier, min_level, max_level])

	# Show level requirement warning if player is too low
	if player_level < min_level:
		display_game("[color=#FF4444]Required Level: %d (You are level %d)[/color]" % [min_level, player_level])
	else:
		display_game("[color=#00FF00]Press [%s] to enter[/color]" % get_action_key_name(4))

func enter_dungeon_at_location():
	"""Enter the dungeon at the player's current location (via action bar)"""
	if not at_dungeon_entrance or dungeon_entrance_info.is_empty():
		display_game("[color=#FF4444]There's no dungeon entrance here.[/color]")
		return

	if in_combat:
		display_game("[color=#FF4444]You can't enter a dungeon while in combat![/color]")
		return

	var instance_id = dungeon_entrance_info.get("instance_id", "")
	var dungeon_type = dungeon_entrance_info.get("dungeon_type", "")
	var dungeon_name = dungeon_entrance_info.get("name", "Dungeon")
	var min_level = dungeon_entrance_info.get("min_level", 1)

	# Show dungeon info before entering
	game_output.clear()
	var color = dungeon_entrance_info.get("color", "#FFFFFF")
	display_game("[color=%s]===== %s =====[/color]" % [color, dungeon_name])
	display_game("")
	display_game("Tier %d Dungeon" % dungeon_entrance_info.get("tier", 1))
	display_game("Level Range: %d - %d" % [min_level, dungeon_entrance_info.get("max_level", 100)])
	display_game("")
	display_game("[color=#FFFF00]Entering dungeon...[/color]")

	# Send enter request
	send_to_server({"type": "dungeon_enter", "dungeon_type": dungeon_type, "instance_id": instance_id})

func select_dungeon(index: int):
	"""Select a dungeon from the list to enter (legacy /dungeons command)"""
	if not dungeon_list_mode:
		return

	if index < 0 or index >= dungeon_available.size():
		display_game("[color=#FF4444]Invalid dungeon selection.[/color]")
		return

	var dungeon = dungeon_available[index]
	var dungeon_type = dungeon.get("type", "")
	var instance_id = dungeon.get("active_instance", "")

	dungeon_list_mode = false
	dungeon_available = []
	# Send both type and instance_id - server will create instance if needed
	send_to_server({"type": "dungeon_enter", "dungeon_type": dungeon_type, "instance_id": instance_id})

# ===== TRADING POST FUNCTIONS =====

func handle_trading_post_start(message: Dictionary):
	"""Handle entering a Trading Post"""
	at_trading_post = true
	trading_post_data = message
	quest_view_mode = false
	pending_trading_post_action = ""

	_display_trading_post_ui()
	update_action_bar()

func _display_trading_post_ui():
	"""Display the trading post UI (art, services, quest info)"""
	if not at_trading_post or trading_post_data.is_empty():
		return

	var tp_name = trading_post_data.get("name", "Trading Post")
	var tp_id = trading_post_data.get("id", "default")
	var quest_giver = trading_post_data.get("quest_giver", "Quest Giver")
	var avail_quests = trading_post_data.get("available_quests", 0)
	var ready_quests = trading_post_data.get("quests_to_turn_in", 0)

	game_output.clear()

	# Display trading post ASCII art
	var post_art = _get_trading_post_art().get_trading_post_art(tp_id)
	display_game(post_art)

	display_game("[color=#FFD700]===== %s =====[/color]" % tp_name)
	display_game("[color=#87CEEB]%s greets you.[/color]" % quest_giver)
	display_game("")
	display_game("Services: [%s] Shop | [%s] Quests | [%s] Heal" % [get_action_key_name(1), get_action_key_name(2), get_action_key_name(3)])
	if avail_quests > 0:
		display_game("[color=#00FF00]%d quest(s) available[/color]" % avail_quests)
	if ready_quests > 0:
		display_game("[color=#FFD700]%d quest(s) ready to turn in![/color]" % ready_quests)
	display_game("")
	display_game("[color=#808080]Walk in any direction to leave.[/color]")

func handle_trading_post_end(message: Dictionary):
	"""Handle leaving a Trading Post"""
	at_trading_post = false
	trading_post_data = {}
	quest_view_mode = false
	pending_trading_post_action = ""
	available_quests = []
	quests_to_turn_in = []

	# Clear the trading post UI from game output
	game_output.clear()

	var msg = message.get("message", "")
	if msg != "":
		display_game(msg)
	else:
		display_game("[color=#808080]You leave the trading post.[/color]")

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
	display_game("Services: [%s] Shop | [%s] Quests | [%s] Heal" % [get_action_key_name(1), get_action_key_name(2), get_action_key_name(3)])
	display_game("")
	display_game("[color=#808080]Walk in any direction to leave.[/color]")

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

	# SECTION 4: Locked quests (unmet prerequisites)
	var locked_quests = message.get("locked_quests", [])
	if locked_quests.size() > 0:
		display_game("[color=#808080]=== Locked Quests ===[/color]")
		for quest in locked_quests:
			var prereq_name = quest.get("prerequisite_name", "another quest")
			display_game("  [color=#555555]🔒 %s[/color]" % quest.get("name", "Quest"))
			display_game("    [color=#808080]Requires: Complete '%s' first[/color]" % prereq_name)
			display_game("")

	# Show message if nothing available
	if quests_to_turn_in.size() == 0 and available_quests.size() == 0 and active_quests_display.size() == 0 and locked_quests.size() == 0:
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

func _display_home_stone_options():
	"""Display Home Stone selection options"""
	display_game("")
	var type_label = "egg" if home_stone_type == "egg" else "equipment"
	display_game("[color=#00FFFF]===== HOME STONE (%s) =====[/color]" % type_label.to_upper())
	display_game("[color=#808080]Select which %s to send to your Sanctuary:[/color]" % type_label)
	display_game("")

	for i in range(home_stone_options.size()):
		var option = home_stone_options[i]
		display_game("[color=#FFFF00][%d][/color] %s" % [i + 1, option.get("label", "Unknown")])

	display_game("")
	display_game("[color=#808080][%s] Cancel[/color]" % get_action_key_name(0))

func _select_home_stone_option(index: int):
	"""Send selected Home Stone target to server"""
	if index < 0 or index >= home_stone_options.size():
		return
	send_to_server({
		"type": "home_stone_select",
		"stone_type": home_stone_type,
		"selection_index": index
	})
	home_stone_mode = false
	home_stone_type = ""
	home_stone_options = []
	game_output.clear()
	update_action_bar()

func _cancel_home_stone():
	"""Cancel Home Stone selection"""
	send_to_server({"type": "home_stone_cancel"})
	home_stone_mode = false
	home_stone_type = ""
	home_stone_options = []
	game_output.clear()
	display_game("[color=#808080]Home Stone use cancelled.[/color]")
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

		# Show newly unlocked abilities
		var unlocked_abilities = message.get("unlocked_abilities", [])
		if unlocked_abilities.size() > 0:
			display_game("")
			display_game("[color=#00FFFF]╔══════════════════════════════════════╗[/color]")
			display_game("[color=#00FFFF]║[/color]  [color=#FFFF00][b]NEW ABILITY UNLOCKED![/b][/color]")
			for ability in unlocked_abilities:
				var ability_type = "Universal" if ability.get("universal", false) else "Class"
				display_game("[color=#00FFFF]║[/color]  [color=#00FF00]★[/color] [color=#FFFFFF]%s[/color] [color=#808080](%s)[/color]" % [ability.get("display", ability.get("name", "?")), ability_type])
			display_game("[color=#00FFFF]║[/color]  [color=#808080]Check Abilities menu to equip![/color]")
			display_game("[color=#00FFFF]╚══════════════════════════════════════╝[/color]")

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
		display_game("[color=#00FFFF]Visit a Trading Post to accept new quests![/color]")
		display_game("")
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

	# Mark the corresponding action bar hotkey as pressed to prevent it from
	# triggering later in this same _process frame when we clear quest_log_mode
	# Item key 0 (KEY_1) = action_5, item key 1 (KEY_2) = action_6, etc.
	var action_index = index + 5  # Map item index to action bar slot
	if action_index < 10:
		set_meta("hotkey_%d_pressed" % action_index, true)

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

func handle_watch_combat_start(message: Dictionary):
	"""Handle combat start from watched player with proper art display"""
	if watching_player == "":
		return

	# Clear game output for fresh combat display (like the actual player gets)
	game_output.clear()

	# Apply combat background color
	var combat_bg_color = message.get("combat_bg_color", "")
	if combat_bg_color != "":
		set_combat_background(combat_bg_color)

	# Build encounter text with monster art from monster_art.gd
	var monster_name = message.get("monster_name", "")
	var use_client_art = message.get("use_client_art", false)
	var base_message = message.get("message", "")

	display_game("[color=#808080]--- %s's Combat ---[/color]" % watching_player)

	if use_client_art and monster_name != "":
		# Render monster art locally using MonsterArt class (same as player does)
		var local_art = _get_monster_art().get_bordered_art_with_font(monster_name, ui_scale_monster_art)
		if local_art != "":
			display_game("[center]" + local_art + "[/center]")
			display_game("")

	# Display the combat message (without the server-generated art since we rendered locally)
	display_game(base_message)

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
		bar_color = Color(1.0, 0.8, 0.0)  # #FFCC00 Orange-yellow
	elif char_class in ["Wizard", "Sorcerer", "Sage"]:
		current_val = char_data.get("current_mana", 0)
		max_val = max(char_data.get("max_mana", 1), 1)
		resource_name = "Mana"
		bar_color = Color(0.6, 0.6, 1.0)  # #9999FF Purple
	else:  # Trickster classes: Thief, Ranger, Ninja
		current_val = char_data.get("current_energy", 0)
		max_val = max(char_data.get("max_energy", 1), 1)
		resource_name = "Energy"
		bar_color = Color(0.4, 1.0, 0.4)  # #66FF66 Light green

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

func _on_bug_button_pressed():
	"""Handle bug report button press - prompt for optional description"""
	if not connected:
		display_game("[color=#FF0000]You must be connected to submit a bug report.[/color]")
		return

	bug_report_mode = true
	input_field.placeholder_text = "Describe the bug (or press Enter to skip)..."
	input_field.grab_focus()
	display_game("[color=#FFD700]===== BUG REPORT =====[/color]")
	display_game("[color=#00FFFF]Please describe the bug, or press Enter to submit without a description.[/color]")
	display_game("[color=#808080]The report will include your character info, location, and game state automatically.[/color]")

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

	# Send to server for saving
	if connected:
		send_to_server({
			"type": "bug_report",
			"report": report_text,
			"player": username if username else "Unknown",
			"description": description
		})
		display_game("[color=#00FF00]Bug report submitted to server![/color]")
		display_game("[color=#808080]Thank you for helping improve the game.[/color]")
	else:
		# Fallback: save locally if not connected
		var file = FileAccess.open(BUG_REPORT_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(BUG_REPORT_PATH) else FileAccess.WRITE)
		if file:
			file.seek_end()
			file.store_string(report_text + "\n")
			file.close()
		display_game("[color=#FFD700]===== BUG REPORT SAVED LOCALLY =====[/color]")
		display_game("[color=#808080]Saved to: %s[/color]" % ProjectSettings.globalize_path(BUG_REPORT_PATH))
		display_game("[color=#808080]Connect to server to submit reports directly.[/color]")

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

		# Show realm treasury for Jarl/High King
		if current_title in ["jarl", "high_king"]:
			var treasury = title_menu_data.get("realm_treasury", 0)
			display_game("Realm Treasury: [color=#FFD700]%d gold[/color]" % treasury)

			# Always show abuse points status for title holders
			var abuse_points = title_menu_data.get("abuse_points", 0)
			var abuse_threshold = title_menu_data.get("abuse_threshold", 8)
			if abuse_points == 0:
				display_game("[color=#00FF00]Abuse: 0/%d points (Safe)[/color]" % abuse_threshold)
			else:
				var color = "#FFFF00" if abuse_points < abuse_threshold / 2 else "#FF4444"
				var warning = ""
				if abuse_points >= abuse_threshold:
					warning = " - [color=#FF0000]TITLE AT RISK![/color]"
				elif abuse_points >= abuse_threshold * 0.75:
					warning = " - [color=#FF4444]Warning: Near threshold![/color]"
				display_game("[color=%s]Abuse: %d/%d points[/color]%s" % [color, abuse_points, abuse_threshold, warning])

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
			var cost_parts = []

			# Build cost string from new format
			if ability.get("gold_cost", 0) > 0:
				cost_parts.append(_format_gold(ability.gold_cost))
			if ability.get("gold_cost_percent", 0) > 0:
				cost_parts.append("%d%% gold" % ability.gold_cost_percent)
			if ability.get("gem_cost", 0) > 0:
				cost_parts.append("%d gems" % ability.gem_cost)
			if ability.get("cooldown", 0) > 0:
				var hours = ability.cooldown / 3600
				if hours >= 1:
					cost_parts.append("%dhr CD" % hours)
				else:
					cost_parts.append("%dmin CD" % (ability.cooldown / 60))

			# Legacy cost format fallback
			if cost_parts.is_empty() and ability.get("cost", 0) > 0:
				var resource = ability.get("resource", "mana")
				if resource == "mana_percent":
					cost_parts.append("%d%% Mana" % ability.cost)
				elif resource == "gems":
					cost_parts.append("%d Gems" % ability.cost)
				elif resource != "none":
					cost_parts.append("%d %s" % [ability.cost, resource.capitalize()])

			var cost_text = " (" + ", ".join(cost_parts) + ")" if not cost_parts.is_empty() else ""
			display_game("  [%s] %s%s - %s" % [get_action_key_name(idx), ability.get("name", ability_id), cost_text, ability.get("description", "")])
			idx += 1
		display_game("")

	# Show title hints if no claimable titles and no current title
	var hints = title_menu_data.get("title_hints", [])
	if claimable.is_empty() and current_title.is_empty() and not hints.is_empty():
		display_game("[color=#808080]Title Requirements:[/color]")
		for hint in hints:
			display_game("[color=#808080]  • %s[/color]" % hint)
		display_game("")

	display_game("[color=#808080]Press [%s] to exit[/color]" % get_action_key_name(0))

func _format_gold(amount: int) -> String:
	"""Format gold amount with K/M suffixes"""
	if amount >= 1000000:
		return "%.1fM gold" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.1fK gold" % (amount / 1000.0)
	else:
		return "%d gold" % amount

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

			# For Bless, enter stat selection mode
			if pending_title_ability == "bless":
				pending_bless_target = target_name
				title_stat_selection_mode = true
				title_target_mode = false
				pending_title_ability = ""
				_display_stat_selection()
				update_action_bar()
				return true

			# Regular ability with target
			send_to_server({
				"type": "title_ability",
				"ability": pending_title_ability,
				"target": target_name
			})
			title_target_mode = false
			title_mode = false
			pending_title_ability = ""
			# Mark the corresponding action bar hotkey as pressed to prevent double-trigger
			var action_slot = target_idx + 5
			if action_slot < 10:
				set_meta("hotkey_%d_pressed" % action_slot, true)
			update_action_bar()
			return true
		# Mark hotkey as pressed even if target index was out of range
		if target_idx >= 0:
			var action_slot = target_idx + 5
			if action_slot < 10:
				set_meta("hotkey_%d_pressed" % action_slot, true)
		return true

	# Action_0 to exit (default: Space)
	var exit_key = keybinds.get("action_0", default_keybinds.get("action_0", KEY_SPACE))
	if key == exit_key:
		title_mode = false
		title_ability_mode = false
		# Mark action_0 hotkey as pressed to prevent double-trigger
		set_meta("hotkey_0_pressed", true)
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
			# Mark the corresponding action bar hotkey as pressed to prevent double-trigger
			# Item key index 0 (KEY_1) = action_5, index 1 (KEY_2) = action_6, etc.
			var action_slot = idx + 5
			if action_slot < 10:
				set_meta("hotkey_%d_pressed" % action_slot, true)
			return true

	# Action keys for abilities (if has title)
	if not abilities.is_empty():
		var ability_idx = -1
		for i in range(4):  # action_1 through action_4
			var action_key = keybinds.get("action_%d" % (i + 1), default_keybinds.get("action_%d" % (i + 1), KEY_Q + i))
			if key == action_key:
				ability_idx = i
				break
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
				# Mark the corresponding action bar hotkey as pressed to prevent double-trigger
				# ability_idx 0-3 corresponds to action_1 through action_4
				set_meta("hotkey_%d_pressed" % (ability_idx + 1), true)
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

func _display_stat_selection():
	"""Display stat selection for Bless ability"""
	game_output.clear()
	display_game("[color=#00FFFF]═══ BLESS ═══[/color]")
	display_game("")
	display_game("Choose which stat to grant [color=#00FF00]+5[/color] to [color=#FFD700]%s[/color]:" % pending_bless_target)
	display_game("")
	display_game("[%s] [color=#FF6666]STR[/color] - Strength (damage)" % get_action_key_name(1))
	display_game("[%s] [color=#00FF00]CON[/color] - Constitution (health)" % get_action_key_name(2))
	display_game("[%s] [color=#FFFF00]DEX[/color] - Dexterity (crit chance)" % get_action_key_name(3))
	display_game("[%s] [color=#6666FF]INT[/color] - Intelligence (magic power)" % get_action_key_name(4))
	display_game("[%s] [color=#FF66FF]WIS[/color] - Wisdom (mana/regen)" % get_action_key_name(5))
	display_game("[%s] [color=#66FFFF]WIT[/color] - Wits (outsmart chance)" % get_action_key_name(6))
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

# ===== CORPSE LOOTING SYSTEM =====

func _display_corpse_info():
	"""Display information about the corpse at the player's current location"""
	if corpse_info.is_empty():
		return

	var corpse_name = corpse_info.get("character_name", "Unknown")
	var cause_of_death = corpse_info.get("cause_of_death", "Unknown")
	var contents = corpse_info.get("contents", {})

	display_game("")
	display_game("[color=#FF6666]═══════ CORPSE FOUND ═══════[/color]")
	display_game("[color=#AAAAAA]The remains of [/color][color=#FFFFFF]%s[/color]" % corpse_name)
	display_game("[color=#808080]Killed by: %s[/color]" % cause_of_death)
	display_game("")

	# List contents
	var has_contents = false
	var item = contents.get("item")
	if item != null and item is Dictionary and not item.is_empty():
		var item_name = item.get("name", "Unknown Item")
		var rarity = item.get("rarity", "common")
		var rarity_color = _get_rarity_color(rarity)
		display_game("  [color=#AAAAAA]Item:[/color] [color=%s]%s[/color]" % [rarity_color, item_name])
		has_contents = true

	var companion = contents.get("companion")
	if companion != null and companion is Dictionary and not companion.is_empty():
		var comp_name = companion.get("name", "Unknown")
		var comp_variant = companion.get("variant", "")
		var comp_level = companion.get("level", 1)
		display_game("  [color=#AAAAAA]Companion:[/color] [color=#00FF00]%s %s (Lv.%d)[/color]" % [comp_variant, comp_name, comp_level])
		has_contents = true

	var egg = contents.get("egg")
	if egg != null and egg is Dictionary and not egg.is_empty():
		var egg_type = egg.get("monster_type", "Unknown")
		display_game("  [color=#AAAAAA]Egg:[/color] [color=#FFD700]%s Egg[/color]" % egg_type)
		has_contents = true

	var gems = contents.get("gems", 0)
	if gems > 0:
		display_game("  [color=#AAAAAA]Gems:[/color] [color=#00BFFF]%d[/color]" % gems)
		has_contents = true

	if not has_contents:
		display_game("[color=#808080]  (Empty)[/color]")

	display_game("")
	display_game("[color=#808080]Press [%s] to loot[/color]" % get_action_key_name(4))


func _display_corpse_loot_confirmation():
	"""Display confirmation prompt for looting a corpse"""
	if corpse_info.is_empty():
		return

	var corpse_name = corpse_info.get("character_name", "Unknown")
	var contents = corpse_info.get("contents", {})

	game_output.clear()
	display_game("[color=#FF6666]═══════ LOOT CORPSE ═══════[/color]")
	display_game("[color=#AAAAAA]Loot the remains of [/color][color=#FFFFFF]%s[/color][color=#AAAAAA]?[/color]" % corpse_name)
	display_game("")

	# List what will be looted
	var item = contents.get("item")
	if item != null and item is Dictionary and not item.is_empty():
		var item_name = item.get("name", "Unknown Item")
		var rarity = item.get("rarity", "common")
		var rarity_color = _get_rarity_color(rarity)
		display_game("  [color=%s]%s[/color]" % [rarity_color, item_name])

	var companion = contents.get("companion")
	if companion != null and companion is Dictionary and not companion.is_empty():
		var comp_name = companion.get("name", "Unknown")
		var comp_variant = companion.get("variant", "")
		var comp_level = companion.get("level", 1)
		display_game("  [color=#00FF00]%s %s (Lv.%d)[/color]" % [comp_variant, comp_name, comp_level])

	var egg = contents.get("egg")
	if egg != null and egg is Dictionary and not egg.is_empty():
		var egg_type = egg.get("monster_type", "Unknown")
		display_game("  [color=#FFD700]%s Egg[/color]" % egg_type)

	var gems = contents.get("gems", 0)
	if gems > 0:
		display_game("  [color=#00BFFF]%d Gems[/color]" % gems)

	display_game("")
	display_game("[color=#808080]Press [%s] to confirm, [%s] to cancel[/color]" % [get_action_key_name(0), get_action_key_name(1)])

# ===== HOUSE (SANCTUARY) DISPLAY FUNCTIONS =====

const HOUSE_UPGRADE_DISPLAY = {
	"house_size": {"name": "Expand Sanctuary", "desc": "Larger house with more room", "icon": "🏠"},
	"storage_slots": {"name": "Storage Expansion", "desc": "+10 storage slots", "icon": "📦"},
	"companion_slots": {"name": "Companion Kennel", "desc": "+1 registered companion slot", "icon": "🐾"},
	"egg_slots": {"name": "Incubation Chamber", "desc": "+1 egg incubation slot", "icon": "🥚"},
	"flee_chance": {"name": "Escape Training", "desc": "+2% flee chance", "icon": "🏃"},
	"starting_gold": {"name": "Family Inheritance", "desc": "+50 starting gold", "icon": "💰"},
	"xp_bonus": {"name": "Ancestral Wisdom", "desc": "+1% XP bonus", "icon": "📚"},
	"gathering_bonus": {"name": "Homesteading", "desc": "+5% gathering bonus", "icon": "⛏️"},
	# Combat bonuses
	"hp_bonus": {"name": "Vitality", "desc": "+5% max HP", "icon": "❤️"},
	"resource_max": {"name": "Reservoir", "desc": "+5% max resources", "icon": "🔮"},
	"resource_regen": {"name": "Flow", "desc": "+5% resource regen", "icon": "✨"},
	# Stat training
	"str_bonus": {"name": "Strength Training", "desc": "+1 STR", "icon": "💪"},
	"con_bonus": {"name": "Constitution Training", "desc": "+1 CON", "icon": "🛡️"},
	"dex_bonus": {"name": "Dexterity Training", "desc": "+1 DEX", "icon": "🎯"},
	"int_bonus": {"name": "Intelligence Training", "desc": "+1 INT", "icon": "🧠"},
	"wis_bonus": {"name": "Wisdom Training", "desc": "+1 WIS", "icon": "👁️"},
	"wits_bonus": {"name": "Wits Training", "desc": "+1 WITS", "icon": "⚡"}
}

func _get_house_layout_level() -> int:
	"""Get current house size level from upgrades"""
	var upgrades = house_data.get("upgrades", {})
	return mini(upgrades.get("house_size", 0), HOUSE_LAYOUTS.size() - 1)

func _get_current_house_layout() -> Array:
	"""Get the current house layout array based on upgrade level"""
	var level = _get_house_layout_level()
	return HOUSE_LAYOUTS.get(level, HOUSE_LAYOUTS[0])

func _init_house_player_position():
	"""Initialize player position to center of house"""
	var layout = _get_current_house_layout()
	if layout.size() == 0:
		return
	# Find center floor position
	var height = layout.size()
	var width = layout[0].length()
	house_player_y = height / 2
	house_player_x = width / 2
	# Make sure we're on a walkable tile
	_clamp_house_player_position()

func _is_house_tile_walkable(tile: String) -> bool:
	"""Check if a tile can be walked on"""
	return tile == " " or tile == "." or tile == "C" or tile == "S" or tile == "U" or tile == "D"

func _clamp_house_player_position():
	"""Ensure player is within bounds and on walkable tile"""
	var layout = _get_current_house_layout()
	if layout.size() == 0:
		return
	var height = layout.size()
	var width = layout[0].length()
	house_player_x = clampi(house_player_x, 0, width - 1)
	house_player_y = clampi(house_player_y, 0, height - 1)

func _get_house_tile_at(x: int, y: int) -> String:
	"""Get the tile character at a position"""
	var layout = _get_current_house_layout()
	if y < 0 or y >= layout.size():
		return "#"
	var row = layout[y]
	if x < 0 or x >= row.length():
		return "#"
	return row[x]

func _move_house_player(dx: int, dy: int) -> bool:
	"""Try to move the player in the house. Returns true if moved."""
	var new_x = house_player_x + dx
	var new_y = house_player_y + dy
	var tile = _get_house_tile_at(new_x, new_y)
	if _is_house_tile_walkable(tile):
		house_player_x = new_x
		house_player_y = new_y
		house_interactable_at = tile if tile in ["C", "S", "U", "D"] else ""
		return true
	return false

func _render_house_map() -> String:
	"""Render the ASCII house map with player position"""
	var layout = _get_current_house_layout()
	if layout.size() == 0:
		return "[color=#FF0000]Error: No house layout[/color]"

	var lines = PackedStringArray()

	# Title
	lines.append("[color=#FFD700]    SANCTUARY[/color]")
	lines.append("")

	# Render each row of the house
	for y in range(layout.size()):
		var row = layout[y]
		var rendered_row = ""
		for x in range(row.length()):
			var tile = row[x]
			var char_to_render = tile

			# If player is at this position, show @ instead
			if x == house_player_x and y == house_player_y:
				rendered_row += "[color=#00FF00]@[/color]"
			elif tile == "#":
				rendered_row += "[color=#8B4513]#[/color]"
			elif tile == "C":
				rendered_row += "[color=#A335EE]C[/color]"
			elif tile == "S":
				rendered_row += "[color=#FFD700]S[/color]"
			elif tile == "U":
				rendered_row += "[color=#00FFFF]U[/color]"
			elif tile == "D":
				rendered_row += "[color=#FF6600]D[/color]"
			else:
				rendered_row += tile
		lines.append("  " + rendered_row)

	lines.append("")

	# Legend
	lines.append("[color=#808080]Legend:[/color]")
	lines.append("[color=#00FF00]@[/color]=You [color=#A335EE]C[/color]=Companion")
	lines.append("[color=#FFD700]S[/color]=Storage [color=#00FFFF]U[/color]=Upgrade")
	lines.append("[color=#FF6600]D[/color]=Door (Play)")
	lines.append("")

	# Show what player is standing on
	if house_interactable_at != "":
		var standing_on = ""
		match house_interactable_at:
			"C": standing_on = "[color=#A335EE]Companion Slot[/color] - Press Space"
			"S": standing_on = "[color=#FFD700]Storage Chest[/color] - Press Space"
			"U": standing_on = "[color=#00FFFF]Upgrades[/color] - Press Space"
			"D": standing_on = "[color=#FF6600]Door[/color] - Press Space to Play"
		lines.append("[color=#FFFFFF]Standing on: " + standing_on + "[/color]")
	else:
		lines.append("[color=#808080]Move with WASD or arrows[/color]")

	return "\n".join(lines)

func _update_house_map():
	"""Update the map display with the house layout"""
	if map_display:
		map_display.clear()
		if house_mode == "main":
			map_display.append_text(_render_house_map())
		else:
			# Show simplified info when in submodes
			var lines = PackedStringArray()
			lines.append("[color=#FFD700]SANCTUARY[/color]")
			lines.append("")
			match house_mode:
				"storage":
					lines.append("[color=#FFD700]Storage Chest[/color]")
				"companions":
					lines.append("[color=#A335EE]Companion Kennel[/color]")
				"upgrades":
					lines.append("[color=#00FFFF]Upgrade Forge[/color]")
			lines.append("")
			lines.append("[color=#808080]Press Space to return[/color]")
			map_display.append_text("\n".join(lines))

func display_house_main():
	"""Display the main house/sanctuary view"""
	game_output.clear()
	house_mode = "main"
	pending_house_action = ""
	_init_house_player_position()
	_update_house_map()

	display_game("[color=#FFD700]═══════ SANCTUARY ═══════[/color]")
	display_game("")

	# Owner and Baddie Points
	var bp = house_data.get("baddie_points", 0)
	var total_bp = house_data.get("total_baddie_points_earned", 0)
	display_game("[color=#FFFFFF]Owner: %s[/color]" % username)
	display_game("[color=#FF6600]Baddie Points: %d[/color] [color=#808080](Total: %d)[/color]" % [bp, total_bp])
	display_game("")

	# Quick Stats
	var stats = house_data.get("stats", {})
	display_game("[color=#00FFFF]Legacy Stats:[/color]")
	display_game("  Characters Lost: %d" % stats.get("characters_lost", 0))
	display_game("  Highest Level: %d" % stats.get("highest_level_reached", 0))
	display_game("  Total XP Earned: %d" % stats.get("total_xp_earned", 0))
	display_game("  Total Kills: %d" % stats.get("total_monsters_killed", 0))
	display_game("")

	# Storage Summary
	var storage = house_data.get("storage", {})
	var storage_used = storage.get("items", []).size()
	var storage_capacity = _get_house_storage_capacity()
	display_game("[color=#00FF00]Storage:[/color] %d/%d items" % [storage_used, storage_capacity])

	# Registered Companions Summary
	var reg_companions = house_data.get("registered_companions", {})
	var companions_used = reg_companions.get("companions", []).size()
	var companions_capacity = _get_house_companion_capacity()
	display_game("[color=#A335EE]Registered Companions:[/color] %d/%d" % [companions_used, companions_capacity])
	display_game("")

	# Active Bonuses from Upgrades
	var upgrades = house_data.get("upgrades", {})
	var bonus_parts = []
	# Base bonuses
	if upgrades.get("flee_chance", 0) > 0:
		bonus_parts.append("+%d%% Flee" % (upgrades.flee_chance * 2))
	if upgrades.get("starting_gold", 0) > 0:
		bonus_parts.append("+%d Gold" % (upgrades.starting_gold * 50))
	if upgrades.get("xp_bonus", 0) > 0:
		bonus_parts.append("+%d%% XP" % upgrades.xp_bonus)
	if upgrades.get("gathering_bonus", 0) > 0:
		bonus_parts.append("+%d%% Gather" % (upgrades.gathering_bonus * 5))
	# Combat bonuses
	if upgrades.get("hp_bonus", 0) > 0:
		bonus_parts.append("+%d%% HP" % (upgrades.hp_bonus * 5))
	if upgrades.get("resource_max", 0) > 0:
		bonus_parts.append("+%d%% Resources" % (upgrades.resource_max * 5))
	if upgrades.get("resource_regen", 0) > 0:
		bonus_parts.append("+%d%% Regen" % (upgrades.resource_regen * 5))
	# Stat bonuses
	var stat_bonus_total = 0
	for stat in ["str_bonus", "con_bonus", "dex_bonus", "int_bonus", "wis_bonus", "wits_bonus"]:
		stat_bonus_total += upgrades.get(stat, 0)
	if stat_bonus_total > 0:
		bonus_parts.append("+%d Stats" % stat_bonus_total)

	if bonus_parts.size() > 0:
		display_game("[color=#FFD700]Active Bonuses:[/color] " + ", ".join(bonus_parts))
	else:
		display_game("[color=#808080]No upgrades purchased yet.[/color]")

	display_game("")
	display_game("[color=#FFD700]═══════════════════════════════════════[/color]")

func display_house_storage():
	"""Display house storage with items and withdraw options"""
	game_output.clear()
	house_mode = "storage"
	_update_house_map()

	display_game("[color=#FFD700]═══════ STORAGE CHEST ═══════[/color]")
	display_game("")

	var storage = house_data.get("storage", {})
	var items = storage.get("items", [])
	var capacity = _get_house_storage_capacity()

	display_game("[color=#AAAAAA]Capacity: %d/%d[/color]" % [items.size(), capacity])
	display_game("")

	if items.size() == 0:
		display_game("[color=#808080]Storage is empty.[/color]")
		display_game("[color=#808080]Use Home Stones to send items here![/color]")
	else:
		# Paginate items (5 per page)
		var page_size = 5
		var total_pages = int(ceil(float(items.size()) / float(page_size)))
		house_storage_page = clamp(house_storage_page, 0, max(0, total_pages - 1))
		var start_idx = house_storage_page * page_size
		var end_idx = min(start_idx + page_size, items.size())

		display_game("[color=#00FF00]Stored Items[/color] [color=#808080]Page %d/%d[/color]" % [house_storage_page + 1, total_pages])
		display_game("")

		for i in range(start_idx, end_idx):
			var item = items[i]
			var item_name = item.get("name", "Unknown")
			var rarity = item.get("rarity", "common")
			var rarity_color = _get_rarity_color(rarity)
			var level = item.get("level", 1)
			var display_num = (i - start_idx) + 1
			var is_stored_companion = item.get("type") == "stored_companion"

			# Show item type indicator for stored companions
			var type_indicator = ""
			if is_stored_companion:
				var variant = item.get("variant", "Normal")
				var variant_color = item.get("variant_color", "#A335EE")
				type_indicator = " [color=%s](%s)[/color]" % [variant_color, variant]

			# Check if marked for withdrawal, discard, or register
			var action_marker = ""
			if i in house_storage_withdraw_items:
				action_marker = " [color=#00FFFF][WITHDRAW][/color]"
			elif i == house_storage_discard_index:
				action_marker = " [color=#FF4444][DISCARD][/color]"
			elif i == house_storage_register_index:
				action_marker = " [color=#A335EE][REGISTER][/color]"

			display_game("  [%d] [color=%s]%s[/color]%s [color=#808080]Lv.%d[/color]%s" % [display_num, rarity_color, item_name, type_indicator, level, action_marker])

		display_game("")
		if total_pages > 1:
			display_game("[color=#808080]Q/E to change page[/color]")

	display_game("")
	display_game("[color=#FFD700]════════════════════════════[/color]")

func display_house_companions():
	"""Display registered companions in the house"""
	game_output.clear()
	house_mode = "companions"
	_update_house_map()

	display_game("[color=#A335EE]═══════ COMPANION KENNEL ═══════[/color]")
	display_game("")

	var reg_companions = house_data.get("registered_companions", {})
	var companions = reg_companions.get("companions", [])
	var capacity = _get_house_companion_capacity()

	display_game("[color=#AAAAAA]Slots: %d/%d[/color]" % [companions.size(), capacity])
	display_game("")

	if companions.size() == 0:
		display_game("[color=#808080]No registered companions.[/color]")
		display_game("[color=#808080]Use Home Stone (Companion) to register companions here![/color]")
		display_game("[color=#808080]Registered companions survive death and can be checked out by new characters.[/color]")
	else:
		for i in range(companions.size()):
			var companion = companions[i]
			var comp_name = companion.get("name", "Unknown")
			var monster_type = companion.get("monster_type", "")
			var variant = companion.get("variant", "Normal")
			var variant_color = companion.get("variant_color", "#FFFFFF")
			var comp_level = companion.get("level", 1)
			var comp_tier = companion.get("tier", 1)
			var checked_out_by = companion.get("checked_out_by")

			var status_text = ""
			if checked_out_by != null:
				status_text = " [color=#FF8800](In use by %s)[/color]" % checked_out_by
			else:
				status_text = " [color=#00FF00](Available)[/color]"

			# Show if selected for checkout or unregister
			var action_marker = ""
			if i == house_checkout_companion_slot:
				action_marker = " [color=#00FFFF][CHECKOUT][/color]"
			elif i == house_unregister_companion_slot:
				action_marker = " [color=#FF8800][UNREGISTER][/color]"

			var rarity_info = _get_variant_rarity_info(variant)
			display_game("[%d] [color=%s][%s][/color] [color=%s]%s %s[/color] Lv.%d%s%s" % [
				i + 1, rarity_info.color, rarity_info.tier, variant_color, variant, comp_name, comp_level, status_text, action_marker
			])

			# Show battles fought
			var battles = companion.get("battles_fought", 0)
			display_game("    [color=#808080]Tier %d | %d battles fought[/color]" % [comp_tier, battles])

	display_game("")
	display_game("[color=#808080]Registered companions survive permadeath![/color]")
	display_game("[color=#808080]Check out a companion when creating a new character.[/color]")
	display_game("[color=#808080]You can also register companions from Storage using the Register button.[/color]")
	display_game("")
	display_game("[color=#A335EE]════════════════════════════════════[/color]")

func display_house_upgrades():
	"""Display available house upgrades with pagination"""
	game_output.clear()
	house_mode = "upgrades"
	_update_house_map()

	# Define upgrade pages
	var page_names = ["Base Upgrades", "Combat Bonuses", "Stat Training"]
	var page_upgrades = [
		["storage_slots", "companion_slots", "egg_slots", "flee_chance", "starting_gold", "xp_bonus", "gathering_bonus"],
		["hp_bonus", "resource_max", "resource_regen"],
		["str_bonus", "con_bonus", "dex_bonus", "int_bonus", "wis_bonus", "wits_bonus"]
	]

	house_upgrades_page = clamp(house_upgrades_page, 0, page_names.size() - 1)

	display_game("[color=#FF6600]═══════ UPGRADE FORGE ═══════[/color]")
	display_game("[color=#AAAAAA]Page %d/3: %s[/color]" % [house_upgrades_page + 1, page_names[house_upgrades_page]])
	display_game("")

	var bp = house_data.get("baddie_points", 0)
	display_game("[color=#FF6600]Baddie Points: %d[/color]" % bp)
	display_game("")

	var upgrades = house_data.get("upgrades", {})

	# Get upgrade costs from server (will be sent with house_data)
	var upgrade_costs = house_data.get("upgrade_costs", {
		"house_size": {"effect": 1, "max": 3, "costs": [5000, 15000, 50000]},
		"storage_slots": {"effect": 10, "max": 8, "costs": [500, 1000, 2000, 4000, 8000, 16000, 32000, 64000]},
		"companion_slots": {"effect": 1, "max": 3, "costs": [2000, 5000, 15000]},
		"egg_slots": {"effect": 1, "max": 9, "costs": [500, 1000, 2000, 4000, 7000, 12000, 20000, 35000, 60000]},
		"flee_chance": {"effect": 2, "max": 5, "costs": [1000, 2500, 5000, 10000, 20000]},
		"starting_gold": {"effect": 50, "max": 10, "costs": [250, 500, 750, 1000, 1500, 2000, 3000, 5000, 6500, 8000]},
		"xp_bonus": {"effect": 1, "max": 10, "costs": [1500, 3000, 5000, 8000, 12000, 18000, 28000, 45000, 70000, 100000]},
		"gathering_bonus": {"effect": 5, "max": 4, "costs": [800, 2000, 5000, 12000]},
		"hp_bonus": {"effect": 5, "max": 5, "costs": [2000, 5000, 12000, 30000, 75000]},
		"resource_max": {"effect": 5, "max": 5, "costs": [2000, 5000, 12000, 30000, 75000]},
		"resource_regen": {"effect": 5, "max": 5, "costs": [3000, 8000, 20000, 50000, 120000]},
		"str_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
		"con_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
		"dex_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
		"int_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
		"wis_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]},
		"wits_bonus": {"effect": 1, "max": 10, "costs": [1000, 2000, 4000, 7000, 12000, 18000, 26000, 36000, 45000, 50000]}
	})

	var current_page_upgrades = page_upgrades[house_upgrades_page]
	var idx = 1
	for upgrade_id in current_page_upgrades:
		var upgrade_def = upgrade_costs.get(upgrade_id, {})
		var display_info = HOUSE_UPGRADE_DISPLAY.get(upgrade_id, {"name": upgrade_id, "desc": "", "icon": ""})
		var current_level = upgrades.get(upgrade_id, 0)
		var max_level = upgrade_def.get("max", 1)
		var costs = upgrade_def.get("costs", [])

		var cost_text = ""
		var can_afford = false
		if current_level >= max_level:
			cost_text = "[color=#00FF00]MAXED[/color]"
		elif current_level < costs.size():
			var next_cost = costs[current_level]
			can_afford = bp >= next_cost
			if can_afford:
				cost_text = "[color=#00FF00]%d BP[/color]" % next_cost
			else:
				cost_text = "[color=#FF0000]%d BP[/color]" % next_cost
		else:
			cost_text = "[color=#808080]N/A[/color]"

		var effect_value = upgrade_def.get("effect", 0) * current_level
		var effect_text = _get_upgrade_effect_text(upgrade_id, effect_value)

		display_game("[%d] [color=#FFD700]%s[/color] Lv.%d/%d" % [idx, display_info.name, current_level, max_level])
		display_game("    %s [color=#AAAAAA](%s)[/color]" % [display_info.desc, effect_text])
		display_game("    Cost: %s" % cost_text)
		display_game("")
		idx += 1

	display_game("[color=#FFD700]══════════════════════════════[/color]")

func _get_upgrade_effect_text(upgrade_id: String, effect_value: int) -> String:
	"""Get display text for current upgrade effect"""
	match upgrade_id:
		"storage_slots": return "+%d slots" % effect_value
		"companion_slots": return "+%d slot%s" % [effect_value, "s" if effect_value != 1 else ""]
		"egg_slots": return "%d/%d slots (base 3 + %d)" % [3 + effect_value, 12, effect_value]
		"flee_chance", "xp_bonus", "gathering_bonus", "hp_bonus", "resource_max", "resource_regen":
			return "+%d%%" % effect_value
		"starting_gold": return "+%d gold" % effect_value
		"str_bonus", "con_bonus", "dex_bonus", "int_bonus", "wis_bonus", "wits_bonus":
			return "+%d" % effect_value
		_: return "+%d" % effect_value

func _get_house_storage_capacity() -> int:
	"""Calculate total house storage capacity"""
	var base_slots = house_data.get("storage", {}).get("slots", 20)
	var upgrade_level = house_data.get("upgrades", {}).get("storage_slots", 0)
	return base_slots + (upgrade_level * 10)

func _get_house_companion_capacity() -> int:
	"""Calculate total registered companion capacity"""
	var base_slots = house_data.get("registered_companions", {}).get("slots", 2)
	var upgrade_level = house_data.get("upgrades", {}).get("companion_slots", 0)
	return base_slots + upgrade_level

func _purchase_house_upgrade(index: int):
	"""Send request to purchase a house upgrade based on current page"""
	var page_upgrades = [
		["storage_slots", "companion_slots", "egg_slots", "flee_chance", "starting_gold", "xp_bonus", "gathering_bonus"],
		["hp_bonus", "resource_max", "resource_regen"],
		["str_bonus", "con_bonus", "dex_bonus", "int_bonus", "wis_bonus", "wits_bonus"]
	]
	var current_page_upgrades = page_upgrades[house_upgrades_page]
	if index < 0 or index >= current_page_upgrades.size():
		return
	send_to_server({"type": "house_upgrade", "upgrade_id": current_page_upgrades[index]})

func _toggle_storage_withdraw_item(display_index: int):
	"""Toggle an item for withdrawal from house storage"""
	var items = house_data.get("storage", {}).get("items", [])
	var page_size = 5
	var actual_index = house_storage_page * page_size + display_index

	if actual_index < 0 or actual_index >= items.size():
		return

	# Toggle selection
	if actual_index in house_storage_withdraw_items:
		house_storage_withdraw_items.erase(actual_index)
	else:
		house_storage_withdraw_items.append(actual_index)

	display_house_storage()
	update_action_bar()

func _toggle_companion_checkout(display_index: int):
	"""Toggle a companion for checkout from house"""
	var companions = house_data.get("registered_companions", {}).get("companions", [])

	if display_index < 0 or display_index >= companions.size():
		return

	var companion = companions[display_index]

	# Can't checkout already checked out companions
	if companion.get("checked_out_by") != null:
		display_game("[color=#FF0000]That companion is already in use by %s.[/color]" % companion.checked_out_by)
		return

	# Toggle selection (only one at a time)
	if house_checkout_companion_slot == display_index:
		house_checkout_companion_slot = -1
	else:
		house_checkout_companion_slot = display_index

	display_house_companions()
	update_action_bar()

func _select_storage_discard_item(display_index: int):
	"""Select an item from storage to discard"""
	var items = house_data.get("storage", {}).get("items", [])
	var page_size = 5
	var actual_index = house_storage_page * page_size + display_index

	if actual_index < 0 or actual_index >= items.size():
		return

	# Select this item for discard (only one at a time)
	if house_storage_discard_index == actual_index:
		house_storage_discard_index = -1
	else:
		house_storage_discard_index = actual_index

	display_house_storage()
	update_action_bar()

func _select_storage_register_companion(display_index: int):
	"""Select a stored companion from storage to register to kennel"""
	var items = house_data.get("storage", {}).get("items", [])
	var page_size = 5
	var actual_index = house_storage_page * page_size + display_index

	if actual_index < 0 or actual_index >= items.size():
		return

	var item = items[actual_index]

	# Can only register stored_companion items
	if item.get("type") != "stored_companion":
		display_game("[color=#FF0000]Only stored companions can be registered to the kennel.[/color]")
		return

	# Check if kennel has space
	if house_data.get("registered_companions", {}).get("companions", []).size() >= _get_house_companion_capacity():
		display_game("[color=#FF0000]Your companion kennel is full. Upgrade it or unregister a companion first.[/color]")
		return

	# Select this companion for registration (only one at a time)
	if house_storage_register_index == actual_index:
		house_storage_register_index = -1
	else:
		house_storage_register_index = actual_index

	display_house_storage()
	update_action_bar()

func _select_companion_unregister(display_index: int):
	"""Select a companion from kennel to unregister (move to storage)"""
	var companions = house_data.get("registered_companions", {}).get("companions", [])

	if display_index < 0 or display_index >= companions.size():
		return

	var companion = companions[display_index]

	# Can't unregister if checked out
	if companion.get("checked_out_by") != null:
		display_game("[color=#FF0000]Cannot unregister a companion that is currently in use by %s.[/color]" % companion.checked_out_by)
		return

	# Check if storage has space
	var storage_items = house_data.get("storage", {}).get("items", [])
	if storage_items.size() >= _get_house_storage_capacity():
		display_game("[color=#FF0000]Your house storage is full. Discard or withdraw items first.[/color]")
		return

	# Select this companion for unregister (only one at a time)
	if house_unregister_companion_slot == display_index:
		house_unregister_companion_slot = -1
	else:
		house_unregister_companion_slot = display_index

	display_house_companions()
	update_action_bar()
