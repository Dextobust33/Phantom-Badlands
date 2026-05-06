extends Control
class_name CombatScenePanel

# JRPG-style battle scene overlay. Top half is the scene (player+companion
# on the left, monster on the right). Bottom half is a combat log mirror.
# A1 slice — static layout only, no animations yet. PNG class sprites on
# the left, ASCII monster art on the right (mismatched by design — see
# project_combat_juice.md for the decision).

const MONO_FONT_PATH := "res://font/Consolas/consolas.ttf"
static var _mono_font: FontFile = null

var client_ref = null

# Cached state (last populate call)
var _player_class: String = ""
var _player_name: String = ""
var _player_hp: int = 0
var _player_max_hp: int = 1
var _companion_data: Dictionary = {}
var _companion_font_size: int = 3  # Default; recalculated per fight to ~2/3 of monster art font
var _monster_name: String = ""
var _monster_level: int = 1
var _monster_name_color: String = "#FFFFFF"
var _monster_art_bbcode: String = ""
var _monster_hp: int = -1
var _monster_max_hp: int = -1
var _monster_hp_known: bool = false

const LOG_LINE_LIMIT := 80
var _log_lines: Array = []

# Layout nodes
var _root_panel: PanelContainer
var _scene_section: HBoxContainer
var _log_section: PanelContainer

# Player column
var _player_col: VBoxContainer
var _player_sprite_holder: CenterContainer  # parent of the PNG sprite — collapsed when ASCII art is active
var _player_sprite_rect: TextureRect
var _player_sprite_placeholder: Label
var _player_name_label: RichTextLabel
var _player_hp_bar: ProgressBar
var _player_hp_text: Label

# Per-class ASCII battle art display. Lives at the BOTTOM of the player
# column (just above the shared HP bar strip) when active, so it sits near
# the player HP for easy visual association rather than at the very top.
#
# Two-layer structure to keep the lunge / shake tweens free of HBox
# layout conflicts: `_ascii_outer` is the layout child (HBox positions
# and sizes it), and `_player_ascii_holder` lives inside it as a plain
# Panel with a free-floating position. FX tween the Panel; the wrapper's
# resize signal keeps the Panel's size in lockstep so layout changes
# never overwrite the FX position.
var _ascii_outer: Control
var _player_ascii_holder: Panel
var _player_ascii_label: RichTextLabel

# Companion column (below player)
var _companion_section: VBoxContainer
var _companion_art: RichTextLabel
var _companion_name_label: RichTextLabel

# Monster column
var _monster_col: VBoxContainer
var _monster_name_label: RichTextLabel
var _monster_art_label: RichTextLabel
var _monster_hp_bar: ProgressBar
var _monster_hp_text: Label

# Log
var _log_inner: Control
var _log_label: RichTextLabel
var _log_scroll: ScrollContainer

# Running damage totals strip (Combat readability #2). Three actor boxes —
# player, companion, monster — each with a prefix label ("You:" / "Pet:" /
# "Foe:") in one color and the number in a contrasting color so the digit
# stands out from the surrounding text.
var _totals_strip: HBoxContainer
var _player_total_label: Label
var _companion_total_label: Label
var _companion_total_box: HBoxContainer  # parent for visibility toggle
var _monster_total_label: Label
var _player_total: int = 0
var _companion_total: int = 0
var _monster_total: int = 0

# In-panel picker — overlays the log section during combat_item_mode (and
# eventually monster_select_mode / target_farm_mode) so the scene stays
# visible while the player chooses an item or target.
var _picker_overlay: Control
var _picker_title_label: RichTextLabel
var _picker_items_vbox: VBoxContainer
var _picker_pageinfo_label: Label
var _picker_prev_btn: Button
var _picker_next_btn: Button
var _picker_cancel_btn: Button
signal picker_item_chosen(slot: int)  # 1-based slot on the current page
signal picker_canceled
signal picker_prev_page
signal picker_next_page

# Flock warning banner — persistent label hovering over the monster art
# while another fight is queued ("More Goblins approaching! Press [Space]").
# Players focus on the monster art when reading combat, so the banner sits
# there rather than in the log section below.
var _flock_warning_label: Label = null

# Victory card — overlay on the log section showing XP/loot/level-up/prompt
# after a non-flock victory, so the player reads rewards inside the scene
# panel instead of being yanked into a wall of text in game_output.
var _victory_card_overlay: PanelContainer
var _victory_card_xp_label: RichTextLabel
var _victory_card_levelup_label: RichTextLabel
var _victory_card_loot_vbox: VBoxContainer
var _victory_card_prompt_label: RichTextLabel
# True from show_victory_card() until hide_victory_card(), independent of
# whether the player has temporarily swapped to the log view. Drives the
# panel-stays-visible logic on the client.
var _victory_interlude_active: bool = false

# A2 — hit feedback. Active tween references so a rapid second hit doesn't
# stack on top of an in-progress flash/lunge (we kill the previous one).
var _player_flash_tween: Tween = null
var _monster_flash_tween: Tween = null
var _companion_flash_tween: Tween = null
var _player_lunge_tween: Tween = null
var _monster_lunge_tween: Tween = null

# Lunge baseline (the original position we return to). Captured the first
# time we lunge each side because layout positions aren't valid at _ready.
var _player_sprite_baseline_pos: Vector2 = Vector2.ZERO
var _player_sprite_baseline_captured: bool = false
var _monster_art_baseline_pos: Vector2 = Vector2.ZERO
var _monster_art_baseline_captured: bool = false

# Damage label sequencing — a counter that drives a deterministic spread so
# rapid consecutive hits don't pile on top of each other. Resets when the
# panel is repopulated for a new fight.
var _damage_label_seq: int = 0

const FLASH_TINT_HIT := Color(1.6, 0.5, 0.5)  # Reddish overdrive
const FLASH_TINT_CRIT := Color(2.0, 0.4, 0.2)  # Hotter red
const FLASH_DURATION := 0.18
const LUNGE_DISTANCE := 16.0
const LUNGE_DURATION := 0.10  # one direction; total = 2x


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_load_mono_font()
	_build_layout()
	visible = false


func _load_mono_font() -> void:
	if _mono_font != null:
		return
	if ResourceLoader.exists(MONO_FONT_PATH):
		_mono_font = load(MONO_FONT_PATH) as FontFile


func _build_layout() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.05, 0.97)
	sb.border_color = Color(0.55, 0.45, 0.33, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_top = 6
	sb.content_margin_right = 6
	sb.content_margin_bottom = 6
	_root_panel.add_theme_stylebox_override("panel", sb)
	_root_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 4)
	root_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_panel.add_child(root_vbox)

	# === Top: scene (player vs monster) ===
	_scene_section = HBoxContainer.new()
	_scene_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_section.size_flags_stretch_ratio = 2.0
	_scene_section.add_theme_constant_override("separation", 8)
	_scene_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(_scene_section)

	_player_col = _build_player_column()
	_scene_section.add_child(_player_col)

	_monster_col = _build_monster_column()
	_scene_section.add_child(_monster_col)

	# === Shared HP strip — player on left, monster on right, same row ===
	root_vbox.add_child(_build_shared_hp_strip())

	# === Running damage totals strip (Combat readability #2) ===
	root_vbox.add_child(_build_running_totals_strip())

	# === Bottom: combat log mirror ===
	_log_section = PanelContainer.new()
	var log_sb := StyleBoxFlat.new()
	log_sb.bg_color = Color(0.02, 0.02, 0.025, 0.85)
	log_sb.border_color = Color(0.3, 0.25, 0.2, 0.7)
	log_sb.set_border_width_all(1)
	log_sb.set_corner_radius_all(4)
	log_sb.content_margin_left = 6
	log_sb.content_margin_top = 4
	log_sb.content_margin_right = 6
	log_sb.content_margin_bottom = 4
	_log_section.add_theme_stylebox_override("panel", log_sb)
	_log_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_section.size_flags_stretch_ratio = 1.0
	_log_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(_log_section)

	# Wrapper Control inside the log_section so we can stack the scroll
	# (combat log) and a picker overlay on the same rect, swapping which
	# is visible based on whether the player is choosing an item/target.
	_log_inner = Control.new()
	_log_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_section.add_child(_log_inner)

	_log_scroll = ScrollContainer.new()
	_log_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_inner.add_child(_log_scroll)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.scroll_active = false
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_font_size_override("normal_font_size", 13)
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_scroll.add_child(_log_label)

	# Build the picker overlay (initially hidden). Lives in the same
	# rect as _log_scroll so showing it hides the log; the scene above
	# stays untouched.
	_build_picker_overlay()
	_build_victory_card_overlay()


func _build_player_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Player name at the top of the column.
	_player_name_label = RichTextLabel.new()
	_player_name_label.bbcode_enabled = true
	_player_name_label.fit_content = true
	_player_name_label.scroll_active = false
	_player_name_label.add_theme_font_size_override("normal_font_size", 14)
	_player_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_player_name_label)

	# Spacer pushes the battle row down so it sits just above the shared
	# HP strip below the scene_section.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	# Battle row — companion on the LEFT, player visual (ASCII or PNG) on
	# the RIGHT, both on the same row just above the HP bar so the eye
	# can take in the whole party formation in one glance.
	var battle_row := HBoxContainer.new()
	battle_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_row.add_theme_constant_override("separation", 8)
	battle_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(battle_row)

	# === Companion (LEFT of the battle row) ===
	_companion_section = VBoxContainer.new()
	_companion_section.add_theme_constant_override("separation", 2)
	_companion_section.size_flags_vertical = Control.SIZE_SHRINK_END
	_companion_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_row.add_child(_companion_section)

	_companion_name_label = RichTextLabel.new()
	_companion_name_label.bbcode_enabled = true
	_companion_name_label.fit_content = true
	_companion_name_label.scroll_active = false
	_companion_name_label.add_theme_font_size_override("normal_font_size", 12)
	_companion_name_label.custom_minimum_size = Vector2(180, 0)
	_companion_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_companion_section.add_child(_companion_name_label)

	_companion_art = RichTextLabel.new()
	_companion_art.bbcode_enabled = true
	_companion_art.fit_content = true
	_companion_art.scroll_active = false
	_companion_art.autowrap_mode = TextServer.AUTOWRAP_OFF
	_companion_art.custom_minimum_size = Vector2(180, 150)
	_companion_art.clip_contents = true
	_companion_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _mono_font:
		_companion_art.add_theme_font_override("normal_font", _mono_font)
		_companion_art.add_theme_font_override("bold_font", _mono_font)
		_companion_art.add_theme_font_override("italics_font", _mono_font)
		_companion_art.add_theme_font_override("mono_font", _mono_font)
	_companion_section.add_child(_companion_art)

	# === Player PNG sprite (RIGHT of the battle row, used when no ASCII) ===
	_player_sprite_holder = CenterContainer.new()
	_player_sprite_holder.custom_minimum_size = Vector2(168, 168)
	_player_sprite_holder.size_flags_vertical = Control.SIZE_SHRINK_END
	_player_sprite_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_row.add_child(_player_sprite_holder)

	_player_sprite_rect = TextureRect.new()
	_player_sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_sprite_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_player_sprite_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_sprite_rect.custom_minimum_size = Vector2(160, 160)  # 2.5x scale of the 64px source
	_player_sprite_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_sprite_holder.add_child(_player_sprite_rect)

	_player_sprite_placeholder = Label.new()
	_player_sprite_placeholder.text = "(no sprite)"
	_player_sprite_placeholder.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_player_sprite_placeholder.add_theme_font_size_override("font_size", 14)
	_player_sprite_placeholder.visible = false
	_player_sprite_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_sprite_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_sprite_holder.add_child(_player_sprite_placeholder)

	# === Player ASCII art (RIGHT of the battle row). Wrapped in a plain
	# Control so the FX-target Panel inside has free-floating position
	# (unaffected by HBox re-layouts when the companion text changes).
	# The wrapper itself is the HBox child; the Panel inside is what
	# lunge / shake / death-slump tweens animate.
	_ascii_outer = Control.new()
	_ascii_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ascii_outer.size_flags_vertical = Control.SIZE_SHRINK_END
	_ascii_outer.custom_minimum_size = Vector2(180, 200)
	_ascii_outer.clip_contents = true
	_ascii_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ascii_outer.visible = false
	battle_row.add_child(_ascii_outer)
	_ascii_outer.resized.connect(_sync_ascii_holder_size)

	_player_ascii_holder = Panel.new()
	var ascii_sb := StyleBoxFlat.new()
	ascii_sb.bg_color = Color(0, 0, 0, 0)
	_player_ascii_holder.add_theme_stylebox_override("panel", ascii_sb)
	_player_ascii_holder.position = Vector2.ZERO
	_player_ascii_holder.size = Vector2(180, 200)
	_player_ascii_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ascii_outer.add_child(_player_ascii_holder)

	_player_ascii_label = RichTextLabel.new()
	_player_ascii_label.bbcode_enabled = true
	_player_ascii_label.fit_content = false
	_player_ascii_label.scroll_active = false
	_player_ascii_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_ascii_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_player_ascii_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _mono_font:
		_player_ascii_label.add_theme_font_override("normal_font", _mono_font)
		_player_ascii_label.add_theme_font_override("bold_font", _mono_font)
		_player_ascii_label.add_theme_font_override("italics_font", _mono_font)
		_player_ascii_label.add_theme_font_override("mono_font", _mono_font)
	_player_ascii_holder.add_child(_player_ascii_label)

	return col


func _sync_ascii_holder_size() -> void:
	"""Keep the inner Panel's size in lock with its layout-managed wrapper.
	The Panel's position is manually controlled (so FX tweens don't fight
	HBox re-layouts), but size needs to follow the wrapper's resize."""
	if _player_ascii_holder == null or _ascii_outer == null:
		return
	if not is_instance_valid(_player_ascii_holder) or not is_instance_valid(_ascii_outer):
		return
	_player_ascii_holder.size = _ascii_outer.size


func _build_monster_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_monster_name_label = RichTextLabel.new()
	_monster_name_label.bbcode_enabled = true
	_monster_name_label.fit_content = true
	_monster_name_label.scroll_active = false
	_monster_name_label.add_theme_font_size_override("normal_font_size", 16)
	_monster_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_monster_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_monster_name_label)

	# Monster ASCII art — let it expand to fill the right column, but clip
	# rather than push the column wider when the art is large.
	var art_holder := PanelContainer.new()
	var art_sb := StyleBoxFlat.new()
	art_sb.bg_color = Color(0, 0, 0, 0)
	art_holder.add_theme_stylebox_override("panel", art_sb)
	art_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_holder.clip_contents = true
	art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(art_holder)

	_monster_art_label = RichTextLabel.new()
	_monster_art_label.bbcode_enabled = true
	# fit_content = false so wide ASCII art doesn't try to push the column
	# wider than its allotted half — the parent PanelContainer clips overflow.
	_monster_art_label.fit_content = false
	_monster_art_label.scroll_active = false
	_monster_art_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_monster_art_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_monster_art_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_monster_art_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _mono_font:
		_monster_art_label.add_theme_font_override("normal_font", _mono_font)
		_monster_art_label.add_theme_font_override("bold_font", _mono_font)
		_monster_art_label.add_theme_font_override("italics_font", _mono_font)
		_monster_art_label.add_theme_font_override("mono_font", _mono_font)
	art_holder.add_child(_monster_art_label)

	return col


func _build_shared_hp_strip() -> HBoxContainer:
	# Both HP bars on a single row, mirroring the player/monster column split
	# above. Each side gets its own [bar | text] sub-row so the numbers stay
	# anchored to the inside edges.
	var strip := HBoxContainer.new()
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_theme_constant_override("separation", 12)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var player_side := HBoxContainer.new()
	player_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_side.size_flags_stretch_ratio = 1.0
	player_side.add_theme_constant_override("separation", 6)
	player_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(player_side)

	_player_hp_bar = _make_hp_bar(Color("#FF4444"))
	_player_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_side.add_child(_player_hp_bar)

	_player_hp_text = Label.new()
	_player_hp_text.add_theme_font_size_override("font_size", 12)
	_player_hp_text.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_player_hp_text.custom_minimum_size = Vector2(110, 0)
	_player_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_side.add_child(_player_hp_text)

	var monster_side := HBoxContainer.new()
	monster_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monster_side.size_flags_stretch_ratio = 1.0
	monster_side.add_theme_constant_override("separation", 6)
	monster_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(monster_side)

	_monster_hp_bar = _make_hp_bar(Color("#FFAA22"))
	_monster_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monster_side.add_child(_monster_hp_bar)

	_monster_hp_text = Label.new()
	_monster_hp_text.add_theme_font_size_override("font_size", 12)
	_monster_hp_text.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_monster_hp_text.custom_minimum_size = Vector2(110, 0)
	_monster_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_monster_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monster_side.add_child(_monster_hp_text)

	return strip


func _build_running_totals_strip() -> HBoxContainer:
	"""Three actor boxes in a row showing fight-wide damage totals. Each
	box pairs a prefix label ("You:" / "Pet:" / "Foe:") with the number
	in a contrasting color so the digit pops."""
	_totals_strip = HBoxContainer.new()
	_totals_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_totals_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_totals_strip.add_theme_constant_override("separation", 18)
	_totals_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Player — muted gold prefix, bright yellow number.
	var player_box = _make_total_box("You:", Color("#C9A040"), Color("#FFD93D"))
	_player_total_label = player_box.get_node("Number")
	_totals_strip.add_child(player_box)

	# Companion — warm orange prefix so the cyan number stands out clearly
	# (was: prefix and number both cyan, hard to read the digit).
	_companion_total_box = _make_total_box("Pet:", Color("#FF9966"), Color("#3DD9FF"))
	_companion_total_label = _companion_total_box.get_node("Number")
	_companion_total_box.visible = false  # Hidden until a companion contributes
	_totals_strip.add_child(_companion_total_box)

	# Monster — red prefix, orange number, per user's "text red, number
	# orange" pattern.
	var monster_box = _make_total_box("Foe:", Color("#FF6666"), Color("#FFA033"))
	_monster_total_label = monster_box.get_node("Number")
	_totals_strip.add_child(monster_box)

	return _totals_strip


func _make_total_box(prefix: String, prefix_color: Color, number_color: Color) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var prefix_label := Label.new()
	prefix_label.name = "Prefix"
	prefix_label.text = prefix
	prefix_label.add_theme_font_size_override("font_size", 12)
	prefix_label.add_theme_color_override("font_color", prefix_color)
	prefix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(prefix_label)

	var number_label := Label.new()
	number_label.name = "Number"
	number_label.text = "0"
	number_label.add_theme_font_size_override("font_size", 12)
	number_label.add_theme_color_override("font_color", number_color)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(number_label)

	return box


func add_player_damage(amount: int) -> void:
	if amount <= 0: return
	_player_total += amount
	_refresh_totals()


func add_companion_damage(amount: int) -> void:
	if amount <= 0: return
	_companion_total += amount
	_refresh_totals()


func add_monster_damage(amount: int) -> void:
	if amount <= 0: return
	_monster_total += amount
	_refresh_totals()


func reset_running_totals() -> void:
	_player_total = 0
	_companion_total = 0
	_monster_total = 0
	_refresh_totals()


func _refresh_totals() -> void:
	if _player_total_label:
		_player_total_label.text = "%d" % _player_total
	if _companion_total_label:
		_companion_total_label.text = "%d" % _companion_total
	if _companion_total_box:
		# Show companion box only once it's contributed something.
		_companion_total_box.visible = _companion_total > 0
	if _monster_total_label:
		_monster_total_label.text = "%d" % _monster_total


func get_totals_summary_bbcode() -> String:
	"""Return the running totals as a single BBCode line — used to mirror
	the strip into game_output so the wall-of-text log shows the same
	at-a-glance totals players see in the panel."""
	var parts: Array = []
	parts.append("[color=#C9A040]You: [/color][color=#FFD93D]%d[/color]" % _player_total)
	if _companion_total > 0:
		parts.append("[color=#FF9966]Pet: [/color][color=#3DD9FF]%d[/color]" % _companion_total)
	parts.append("[color=#FF6666]Foe: [/color][color=#FFA033]%d[/color]" % _monster_total)
	return "   ·   ".join(parts)


func _build_picker_overlay() -> void:
	"""Build the in-panel picker UI. Hidden by default; show via
	show_item_picker() during combat_item_mode."""
	_picker_overlay = PanelContainer.new()
	_picker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var picker_sb := StyleBoxFlat.new()
	picker_sb.bg_color = Color(0.05, 0.04, 0.06, 0.97)
	picker_sb.border_color = Color(0.55, 0.45, 0.33)
	picker_sb.set_border_width_all(2)
	picker_sb.set_corner_radius_all(4)
	picker_sb.content_margin_left = 8
	picker_sb.content_margin_right = 8
	picker_sb.content_margin_top = 6
	picker_sb.content_margin_bottom = 6
	_picker_overlay.add_theme_stylebox_override("panel", picker_sb)
	_picker_overlay.visible = false
	_picker_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	_log_inner.add_child(_picker_overlay)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_picker_overlay.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)

	_picker_title_label = RichTextLabel.new()
	_picker_title_label.bbcode_enabled = true
	_picker_title_label.fit_content = true
	_picker_title_label.scroll_active = false
	_picker_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_title_label.add_theme_font_size_override("normal_font_size", 14)
	_picker_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_picker_title_label)

	_picker_pageinfo_label = Label.new()
	_picker_pageinfo_label.add_theme_font_size_override("font_size", 12)
	_picker_pageinfo_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.62))
	_picker_pageinfo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_picker_pageinfo_label)

	# Items list — fills available vertical space
	var items_scroll := ScrollContainer.new()
	items_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(items_scroll)

	_picker_items_vbox = VBoxContainer.new()
	_picker_items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_items_vbox.add_theme_constant_override("separation", 2)
	items_scroll.add_child(_picker_items_vbox)

	# Action row (prev / cancel / next)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	vbox.add_child(action_row)

	_picker_prev_btn = Button.new()
	_picker_prev_btn.text = "◀ Prev"
	_picker_prev_btn.focus_mode = Control.FOCUS_NONE
	_picker_prev_btn.pressed.connect(func(): emit_signal("picker_prev_page"))
	action_row.add_child(_picker_prev_btn)

	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(spacer_l)

	_picker_cancel_btn = Button.new()
	_picker_cancel_btn.text = "Cancel"
	_picker_cancel_btn.focus_mode = Control.FOCUS_NONE
	_picker_cancel_btn.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	_picker_cancel_btn.pressed.connect(func(): emit_signal("picker_canceled"))
	action_row.add_child(_picker_cancel_btn)

	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(spacer_r)

	_picker_next_btn = Button.new()
	_picker_next_btn.text = "Next ▶"
	_picker_next_btn.focus_mode = Control.FOCUS_NONE
	_picker_next_btn.pressed.connect(func(): emit_signal("picker_next_page"))
	action_row.add_child(_picker_next_btn)


func show_item_picker(title: String, items_on_page: Array, page: int, total_pages: int) -> void:
	"""Show the in-panel item picker. items_on_page is an array of dicts
	with keys: name (string), color (hex string), qty (int)."""
	if _picker_overlay == null or not is_instance_valid(_picker_overlay):
		return
	_picker_title_label.text = "[b]%s[/b]" % title
	if total_pages > 1:
		_picker_pageinfo_label.text = "Page %d / %d" % [page + 1, total_pages]
		_picker_prev_btn.disabled = (page <= 0)
		_picker_next_btn.disabled = (page >= total_pages - 1)
		_picker_prev_btn.visible = true
		_picker_next_btn.visible = true
	else:
		_picker_pageinfo_label.text = ""
		_picker_prev_btn.visible = false
		_picker_next_btn.visible = false

	# Clear previous item rows
	for child in _picker_items_vbox.get_children():
		child.queue_free()

	# Build a button per item
	for i in range(items_on_page.size()):
		var entry: Dictionary = items_on_page[i]
		var name = str(entry.get("name", "Unknown"))
		var color = str(entry.get("color", "#FFFFFF"))
		var qty = int(entry.get("qty", 1))
		var qty_text = ("  x%d" % qty) if qty > 1 else ""
		var slot = i + 1
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = "[%d]  %s%s" % [slot, name, qty_text]
		# Override the text color via a custom theme font color — but Buttons
		# only support solid color, so prefix the index with the rarity color
		# isn't possible without BBCode. Just tint the whole label.
		btn.add_theme_color_override("font_color", Color(color))
		btn.add_theme_color_override("font_hover_color", Color(color).lightened(0.2))
		btn.pressed.connect(func(): emit_signal("picker_item_chosen", slot))
		_picker_items_vbox.add_child(btn)

	_picker_overlay.visible = true
	if _log_scroll:
		_log_scroll.visible = false


func hide_picker() -> void:
	if _picker_overlay and is_instance_valid(_picker_overlay):
		_picker_overlay.visible = false
	if _log_scroll and is_instance_valid(_log_scroll):
		_log_scroll.visible = true


func _make_hp_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.custom_minimum_size = Vector2(0, 14)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.05, 0.03, 0.95)
	bg.border_color = Color(0.4, 0.34, 0.25, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)

	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


# === Public API ===

func populate(payload: Dictionary) -> void:
	"""Refresh the panel from a payload dictionary. Optional keys are
	preserved if missing so partial refreshes don't blow away other state."""
	if not is_inside_tree():
		return
	if payload.has("player_class"):
		_player_class = str(payload["player_class"])
	if payload.has("player_name"):
		_player_name = str(payload["player_name"])
	if payload.has("player_hp"):
		_player_hp = int(payload["player_hp"])
	if payload.has("player_max_hp"):
		_player_max_hp = maxi(1, int(payload["player_max_hp"]))
	if payload.has("companion_data"):
		_companion_data = payload["companion_data"]
	if payload.has("companion_font_size"):
		_companion_font_size = maxi(1, int(payload["companion_font_size"]))
	if payload.has("monster_name"):
		_monster_name = str(payload["monster_name"])
	if payload.has("monster_level"):
		_monster_level = int(payload["monster_level"])
	if payload.has("monster_name_color"):
		_monster_name_color = str(payload["monster_name_color"])
	if payload.has("monster_art_bbcode"):
		_monster_art_bbcode = str(payload["monster_art_bbcode"])
	if payload.has("monster_hp_known"):
		_monster_hp_known = bool(payload["monster_hp_known"])
	if payload.has("monster_hp"):
		_monster_hp = int(payload["monster_hp"])
	if payload.has("monster_max_hp"):
		_monster_max_hp = maxi(1, int(payload["monster_max_hp"]))

	# New fight — reset the damage label fan position so the first hit lands
	# at the leftmost slot every time. Also reset the running damage totals
	# so the strip starts at zero for this fight.
	_damage_label_seq = 0
	reset_running_totals()

	# Reset any FX-applied sprite state from the prior fight (death slump,
	# stealth fade, victory grey-out) so this fight starts clean. Reset
	# both the PNG sprite and the ASCII holder since either might have
	# been the FX target in the previous fight.
	for node in [_player_sprite_rect, _player_ascii_holder]:
		if node and is_instance_valid(node):
			node.modulate = Color.WHITE
			node.rotation = 0.0
			if node.has_meta("lunge_baseline"):
				node.position = node.get_meta("lunge_baseline")
	if _monster_art_label and is_instance_valid(_monster_art_label):
		_monster_art_label.modulate = Color.WHITE
		if _monster_art_baseline_captured:
			_monster_art_label.position = _monster_art_baseline_pos
	# Clear any flock warning banner / victory card left over from the
	# previous fight.
	hide_flock_warning()
	hide_victory_card()

	_refresh_player()
	_refresh_companion()
	_refresh_monster()


func update_player_hp(current: int, max_hp: int) -> void:
	_player_hp = current
	_player_max_hp = maxi(1, max_hp)
	if is_inside_tree():
		_refresh_player_hp()


func update_monster_hp(current: int, max_hp: int, known: bool) -> void:
	_monster_hp = current
	_monster_max_hp = maxi(1, max_hp)
	_monster_hp_known = known
	if is_inside_tree():
		_refresh_monster_hp()


func update_companion(companion_data: Dictionary) -> void:
	_companion_data = companion_data
	if is_inside_tree():
		_refresh_companion()


func append_log(bbcode_line: String) -> void:
	if bbcode_line.strip_edges() == "":
		return
	_log_lines.append(bbcode_line)
	if _log_lines.size() > LOG_LINE_LIMIT:
		_log_lines = _log_lines.slice(_log_lines.size() - LOG_LINE_LIMIT)
	if is_inside_tree():
		_refresh_log()


func clear_log() -> void:
	_log_lines.clear()
	if is_inside_tree():
		_refresh_log()


# === Internal rendering ===

func _refresh_player() -> void:
	# Class ASCII art takes priority over the PNG sprite when available.
	# Drop a file at `res://client/sprites/ascii/<Class>.txt` and it shows up
	# here automatically; classes without one fall back to the LPC PNG.
	var ascii_art = ClassAsciiArt.get_ascii_art(_player_class)
	if ascii_art != "":
		var fsize = ClassAsciiArt.get_font_size(_player_class)
		var col = ClassAsciiArt.get_color(_player_class)
		set_player_ascii_art(ascii_art, fsize, col)
	else:
		# Hide the alt holder if we'd previously been showing ASCII for a
		# different class, and bring back the PNG slot.
		if _ascii_outer and is_instance_valid(_ascii_outer):
			_ascii_outer.visible = false
		if _player_sprite_holder and is_instance_valid(_player_sprite_holder):
			_player_sprite_holder.visible = true
		var atlas: AtlasTexture = ClassSprite.get_idle_atlas(_player_class)
		if atlas != null:
			_player_sprite_rect.texture = atlas
			_player_sprite_rect.visible = true
			_player_sprite_placeholder.visible = false
		else:
			_player_sprite_rect.texture = null
			_player_sprite_rect.visible = false
			_player_sprite_placeholder.text = "(no sprite for %s)" % _player_class
			_player_sprite_placeholder.visible = true

	# Name label — class color tint
	var class_color := ClassSprite.get_class_color(_player_class)
	var hex := "#%02X%02X%02X" % [int(class_color.r * 255), int(class_color.g * 255), int(class_color.b * 255)]
	_player_name_label.text = "[color=%s]%s[/color] [color=#888888](%s)[/color]" % [hex, _player_name, _player_class]

	_refresh_player_hp()


func _refresh_player_hp() -> void:
	_player_hp_bar.max_value = _player_max_hp
	_player_hp_bar.value = clampi(_player_hp, 0, _player_max_hp)
	_player_hp_text.text = "HP %d / %d" % [maxi(0, _player_hp), _player_max_hp]


func _refresh_companion() -> void:
	if _companion_data == null or _companion_data.is_empty():
		_companion_section.visible = false
		return
	_companion_section.visible = true

	var name := str(_companion_data.get("name", "Companion"))
	var variant := str(_companion_data.get("variant", "Normal"))
	var level := int(_companion_data.get("level", 1))
	var variant_color := str(_companion_data.get("variant_color", "#FFFFFF"))
	_companion_name_label.text = "[color=%s]%s[/color] [color=#888888]Lv %d %s[/color]" % [variant_color, name, level, variant]

	# Companion ASCII art — tiny font, monospaced. No [center] wrapper because
	# the column is much wider than the art at font_size 2; centering pads with
	# blank space on both sides and visually disconnects the figure. Left-align
	# is fine — the player sprite above is centered by its CenterContainer.
	var art_text := ""
	if client_ref and client_ref.has_method("_get_companion_art_lines"):
		var monster_type = _companion_data.get("monster_type", name)
		var lines: Array = client_ref._get_companion_art_lines(monster_type, name)
		if lines.size() > 0:
			var raw_art = "\n".join(lines)
			# Apply the same variant pattern coloring used by the corner overlay
			# so a Crimson Wolf is red here too, not its default art color.
			if client_ref.has_method("_recolor_ascii_art_pattern"):
				var v_color = str(_companion_data.get("variant_color", "#FFFFFF"))
				var v_color2 = str(_companion_data.get("variant_color2", ""))
				var v_pattern = str(_companion_data.get("variant_pattern", "solid"))
				if client_ref.has_method("_ensure_readable_color"):
					v_color = client_ref._ensure_readable_color(v_color)
					if v_color2 != "":
						v_color2 = client_ref._ensure_readable_color(v_color2)
				raw_art = client_ref._recolor_ascii_art_pattern(raw_art, v_color, v_color2, v_pattern)
			art_text = "[font_size=%d]%s[/font_size]" % [_companion_font_size, raw_art]
	if art_text == "":
		art_text = "[color=#666666](companion)[/color]"
	_companion_art.text = art_text


func _refresh_monster() -> void:
	if _monster_name == "":
		_monster_name_label.text = ""
		_monster_art_label.text = ""
		_monster_hp_bar.visible = false
		_monster_hp_text.text = ""
		return

	_monster_name_label.text = "[color=%s]%s[/color] [color=#FFD700]Lv %d[/color]" % [_monster_name_color, _monster_name, _monster_level]
	_monster_art_label.text = _monster_art_bbcode
	_monster_hp_bar.visible = true
	_refresh_monster_hp()


func _refresh_monster_hp() -> void:
	if not _monster_hp_known or _monster_hp < 0 or _monster_max_hp <= 0:
		_monster_hp_bar.value = 0
		_monster_hp_bar.max_value = 100
		_monster_hp_text.text = "HP ???"
		return
	_monster_hp_bar.max_value = _monster_max_hp
	_monster_hp_bar.value = clampi(_monster_hp, 0, _monster_max_hp)
	_monster_hp_text.text = "HP %d / %d" % [maxi(0, _monster_hp), _monster_max_hp]


func _refresh_log() -> void:
	_log_label.text = "\n".join(_log_lines)
	# Auto-scroll to bottom
	await get_tree().process_frame
	if _log_scroll and is_instance_valid(_log_scroll):
		_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


# === A2 hit feedback ===

func flash_player(is_crit: bool = false) -> void:
	_flash_node(_player_visual_for_fx(), _player_flash_tween, is_crit, "_player_flash_tween")

func flash_companion(is_crit: bool = false) -> void:
	_flash_node(_companion_art, _companion_flash_tween, is_crit, "_companion_flash_tween")

func flash_monster(is_crit: bool = false) -> void:
	_flash_node(_monster_art_label, _monster_flash_tween, is_crit, "_monster_flash_tween")


func _flash_node(node: CanvasItem, current_tween: Tween, is_crit: bool, tween_field: String) -> void:
	if node == null or not is_instance_valid(node):
		return
	if current_tween and current_tween.is_valid():
		current_tween.kill()
	node.modulate = Color.WHITE
	var tint = FLASH_TINT_CRIT if is_crit else FLASH_TINT_HIT
	var t := create_tween()
	t.tween_property(node, "modulate", tint, FLASH_DURATION * 0.3)
	t.tween_property(node, "modulate", Color.WHITE, FLASH_DURATION * 0.7)
	set(tween_field, t)


func lunge_player_forward() -> void:
	var node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
	# Per-node baseline via metadata — works whether the visual is the
	# PNG sprite or the ASCII holder.
	var baseline: Vector2
	if node.has_meta("lunge_baseline"):
		baseline = node.get_meta("lunge_baseline")
	else:
		baseline = node.position
		node.set_meta("lunge_baseline", baseline)
	if _player_lunge_tween and _player_lunge_tween.is_valid():
		_player_lunge_tween.kill()
		node.position = baseline
	# Player is on the left, monster on the right — lunge to the RIGHT.
	var target_pos = baseline + Vector2(LUNGE_DISTANCE, 0)
	_player_lunge_tween = create_tween()
	_player_lunge_tween.tween_property(node, "position", target_pos, LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_player_lunge_tween.tween_property(node, "position", baseline, LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func lunge_monster_forward() -> void:
	if _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	if not _monster_art_baseline_captured:
		_monster_art_baseline_pos = _monster_art_label.position
		_monster_art_baseline_captured = true
	if _monster_lunge_tween and _monster_lunge_tween.is_valid():
		_monster_lunge_tween.kill()
		_monster_art_label.position = _monster_art_baseline_pos
	# Monster is on the right — lunge to the LEFT (toward player).
	var target_pos = _monster_art_baseline_pos + Vector2(-LUNGE_DISTANCE, 0)
	_monster_lunge_tween = create_tween()
	_monster_lunge_tween.tween_property(_monster_art_label, "position", target_pos, LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_monster_lunge_tween.tween_property(_monster_art_label, "position", _monster_art_baseline_pos, LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func show_damage_on_monster(amount: int, is_crit: bool, source: String = "player") -> void:
	"""Spawn a floating damage number above the monster art.
	source: 'player' (yellow), 'companion' (cyan), 'crit' override (red, larger)."""
	if _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var anchor_global = _monster_art_label.global_position + Vector2(_monster_art_label.size.x * 0.5, _monster_art_label.size.y * 0.25)
	_spawn_damage_label(anchor_global, amount, is_crit, source, false)


func show_damage_on_player(amount: int, is_crit: bool) -> void:
	var node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
	var anchor_global = node.global_position + Vector2(node.size.x * 0.5, node.size.y * 0.25)
	_spawn_damage_label(anchor_global, amount, is_crit, "monster", true)


func _spawn_damage_label(anchor_global: Vector2, amount: int, is_crit: bool, source: String, target_is_player: bool) -> void:
	var label := Label.new()
	label.text = ("-%d" % amount) if amount > 0 else "0"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 100
	# Color by source (who dealt it) and crit
	var color := Color("#FFD93D")  # default yellow = player damage
	var font_size := 22
	if is_crit:
		color = Color("#FF3B3B")
		font_size = 30
	elif source == "companion":
		color = Color("#3DD9FF")
	elif target_is_player:
		# Damage TO the player — shown in red so it visually reads as "hurt me"
		color = Color("#FF6666")
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	# Force layout so label.size is valid before we anchor.
	label.reset_size()

	# Deterministic spread: cycle through 5 positions in a fan pattern so
	# rapid back-to-back hits don't stack. Counter resets when populate()
	# is called for a new fight.
	var slot = _damage_label_seq % 5
	_damage_label_seq += 1
	var spread_x = [-50.0, 30.0, -20.0, 60.0, 0.0][slot]
	var spread_y = [0.0, -10.0, 14.0, 4.0, -18.0][slot]

	var local_anchor = anchor_global - global_position - label.size * 0.5
	local_anchor += Vector2(spread_x, spread_y)
	label.position = local_anchor

	var float_distance := 60.0
	var lifetime := 1.0
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "position", local_anchor + Vector2(0, -float_distance), lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, lifetime * 0.6).set_delay(lifetime * 0.4)
	t.chain().tween_callback(label.queue_free)


# === A3 ability VFX ===

func play_slash_arc(is_crit: bool = false) -> void:
	"""A diagonal slash glyph swept across the monster art. Used for melee
	abilities (Cleave, Power Strike, Devastate, Berserk)."""
	if _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var center_global = _monster_art_label.global_position + _monster_art_label.size * 0.5
	var local_center = center_global - global_position
	var glyph := "✗" if is_crit else "／"
	var color := Color("#FF3333") if is_crit else Color("#FF9966")
	var font_size := 64 if is_crit else 56
	# Slash sweeps diagonally from upper-left to lower-right of the monster.
	var span = max(80.0, _monster_art_label.size.x * 0.5)
	var start_pos = local_center + Vector2(-span * 0.5, -span * 0.4)
	var end_pos = local_center + Vector2(span * 0.5, span * 0.4)
	var label := Label.new()
	label.text = glyph
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 110
	add_child(label)
	label.reset_size()
	label.position = start_pos - label.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "position", end_pos - label.size * 0.5, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.18).set_delay(0.10)
	t.chain().tween_callback(label.queue_free)


func play_projectile(glyph: String = "✦", color: Color = Color("#FF66FF")) -> void:
	"""A glyph that flies from the player sprite to the monster art and
	vanishes in a small flash on impact. Used for ranged spells
	(Magic Bolt, Blast, Meteor)."""
	var src = _player_visual_for_fx()
	if src == null or not is_instance_valid(src):
		return
	if _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var start_global = src.global_position + src.size * Vector2(0.85, 0.45)
	var end_global = _monster_art_label.global_position + _monster_art_label.size * 0.5
	var label := Label.new()
	label.text = glyph
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_font_size_override("font_size", 36)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 110
	add_child(label)
	label.reset_size()
	label.position = start_global - global_position - label.size * 0.5
	var end_pos = end_global - global_position - label.size * 0.5
	# Slight upward arc — pass through a midpoint above the straight line.
	var mid_pos = (label.position + end_pos) * 0.5 + Vector2(0, -28)
	var travel := 0.32
	var t := create_tween()
	t.tween_property(label, "position", mid_pos, travel * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position", end_pos, travel * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_play_impact_burst.bind(end_pos, color))
	t.tween_callback(label.queue_free)


func _play_impact_burst(local_pos: Vector2, color: Color) -> void:
	# Small radial burst when a projectile lands.
	var burst := Label.new()
	burst.text = "✸"
	burst.add_theme_color_override("font_color", color)
	burst.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.7))
	burst.add_theme_constant_override("outline_size", 4)
	burst.add_theme_font_size_override("font_size", 48)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.z_index = 111
	add_child(burst)
	burst.reset_size()
	burst.position = local_pos
	burst.scale = Vector2(0.4, 0.4)
	burst.pivot_offset = burst.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(burst, "scale", Vector2(1.6, 1.6), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(burst, "modulate:a", 0.0, 0.22)
	t.chain().tween_callback(burst.queue_free)


func play_buff_aura(color: Color = Color("#33CCFF")) -> void:
	"""Expanding ring of glyphs around the player sprite. Used for self-buffs
	(Haste, Iron Skin, War Cry, Berserk, Fortify)."""
	var node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
	var center_global = node.global_position + node.size * 0.5
	var local_center = center_global - global_position
	var radius_start := 8.0
	var radius_end := 80.0
	var glyph_count := 6
	for i in range(glyph_count):
		var angle = (TAU * i) / glyph_count
		var label := Label.new()
		label.text = "✦"
		label.add_theme_color_override("font_color", color)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_font_size_override("font_size", 28)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = 105
		add_child(label)
		label.reset_size()
		var dir = Vector2(cos(angle), sin(angle))
		label.position = local_center + dir * radius_start - label.size * 0.5
		var end_pos = local_center + dir * radius_end - label.size * 0.5
		var t := create_tween().set_parallel(true)
		t.tween_property(label, "position", end_pos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.08)
		t.chain().tween_callback(label.queue_free)


func play_stealth_fade(duration: float = 2.5) -> void:
	"""Fade the player sprite to ~40% alpha for a duration, then back. Used
	for Vanish, Cloak, Teleport."""
	var node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
	var t := create_tween()
	t.tween_property(node, "modulate:a", 0.4, 0.25)
	t.tween_interval(duration - 0.5)
	t.tween_property(node, "modulate:a", 1.0, 0.25)


# === A4 outcome FX ===

func play_victory_fx() -> void:
	"""Monster art slumps + greys out, big VICTORY banner across the scene.
	Roughly 2 seconds total — caller should hold the panel visible at least
	that long so the animation completes before the victory screen takes over."""
	if _monster_art_label and is_instance_valid(_monster_art_label):
		var t := create_tween().set_parallel(true)
		t.tween_property(_monster_art_label, "modulate", Color(0.45, 0.45, 0.45, 0.55), 0.6)
		t.tween_property(_monster_art_label, "position", _monster_art_label.position + Vector2(0, 24), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Victory takes the lower position so a coincident level-up banner above
	# can be read alongside it (real combat fires both back-to-back).
	_spawn_outcome_banner("VICTORY!", Color("#FFD93D"), 56, 1.6, 30.0)


func play_death_fx() -> void:
	"""Player sprite greys + slumps, DEFEATED banner. About 2 seconds."""
	var node = _player_visual_for_fx()
	if node and is_instance_valid(node):
		var t := create_tween().set_parallel(true)
		t.tween_property(node, "modulate", Color(0.4, 0.4, 0.4, 0.6), 0.5)
		t.tween_property(node, "rotation", deg_to_rad(15), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(node, "position", node.position + Vector2(0, 30), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_spawn_outcome_banner("DEFEATED", Color("#FF4444"), 52, 1.8, -30.0)


func play_level_up_fx(new_level: int) -> void:
	"""Golden burst around the player + LEVEL UP banner."""
	var node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
	var center_global = node.global_position + node.size * 0.5
	var local_center = center_global - global_position
	# Two concentric rings of golden sparkles, staggered, plus the banner.
	var ring_count := 2
	var glyph_count := 8
	var radius_start := 12.0
	var radius_end := 110.0
	for ring in range(ring_count):
		var ring_delay = ring * 0.18
		for i in range(glyph_count):
			var angle = (TAU * i) / glyph_count + ring * (TAU / glyph_count) * 0.5
			var label := Label.new()
			label.text = "✦"
			label.add_theme_color_override("font_color", Color("#FFE066"))
			label.add_theme_color_override("font_outline_color", Color(0.4, 0.2, 0, 0.95))
			label.add_theme_constant_override("outline_size", 4)
			label.add_theme_font_size_override("font_size", 30)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.z_index = 108
			add_child(label)
			label.reset_size()
			var dir = Vector2(cos(angle), sin(angle))
			label.position = local_center + dir * radius_start - label.size * 0.5
			var end_pos = local_center + dir * radius_end - label.size * 0.5
			var t := create_tween().set_parallel(true)
			t.tween_property(label, "position", end_pos, 0.85).set_delay(ring_delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(label, "modulate:a", 0.0, 0.85).set_delay(ring_delay + 0.2)
			t.chain().tween_callback(label.queue_free)
	# Level-up banner sits high above center so a victory banner (which
	# fires immediately after on a killing-blow level-up) can land below it.
	_spawn_outcome_banner("LEVEL UP!  Lv %d" % new_level, Color("#FFE066"), 44, 1.6, -90.0)


func play_outsmart_spiral() -> void:
	"""A spiral of glyphs winding inward toward the monster — used for
	Trickster outsmart / Perfect Heist outcomes."""
	if _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var center_global = _monster_art_label.global_position + _monster_art_label.size * 0.5
	var local_center = center_global - global_position
	var glyph_count := 12
	var max_radius := 90.0
	for i in range(glyph_count):
		var t_along = float(i) / float(glyph_count - 1)  # 0..1 outside-in
		var angle = TAU * 1.5 * t_along  # 1.5 turns
		var radius = max_radius * (1.0 - t_along)
		var label := Label.new()
		label.text = "✦"
		label.add_theme_color_override("font_color", Color("#33FF99"))
		label.add_theme_color_override("font_outline_color", Color(0, 0.2, 0.05, 0.95))
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_font_size_override("font_size", 24)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = 108
		add_child(label)
		label.reset_size()
		var pos = local_center + Vector2(cos(angle), sin(angle)) * radius - label.size * 0.5
		label.position = pos
		label.modulate.a = 0.0
		var stagger = i * 0.05
		var t := create_tween()
		t.tween_interval(stagger)
		t.tween_property(label, "modulate:a", 1.0, 0.12)
		t.tween_interval(0.18)
		t.tween_property(label, "modulate:a", 0.0, 0.30)
		t.tween_callback(label.queue_free)


func _spawn_outcome_banner(text: String, color: Color, font_size: int, lifetime: float, y_offset: float = 0.0) -> void:
	"""Big centered text banner used by victory / defeat / level-up FX.
	Pops in with a small overshoot, holds, then fades. y_offset is added
	to the vertical center so coincident banners can stagger (negative =
	higher up). Default 0 = exact center."""
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 120
	add_child(label)
	label.reset_size()
	label.position = (size - label.size) * 0.5 + Vector2(0, y_offset)
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.4, 0.4)
	label.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 1.0, 0.18)
	t.chain().tween_interval(lifetime)
	t.chain().tween_property(label, "modulate:a", 0.0, 0.35)
	t.chain().tween_callback(label.queue_free)


func play_heal_pulse(amount: int) -> void:
	"""Green +N text floats up from the player. Used for heals/restores."""
	var node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
	var center_global = node.global_position + node.size * Vector2(0.5, 0.25)
	var local_anchor = center_global - global_position
	var label := Label.new()
	label.text = "+%d" % amount if amount > 0 else "+"
	label.add_theme_color_override("font_color", Color("#3DFF6E"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 100
	add_child(label)
	label.reset_size()
	label.position = local_anchor - label.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "position", label.position + Vector2(0, -55), 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.4)
	t.chain().tween_callback(label.queue_free)


# === Flock warning banner ===

func show_flock_warning(text: String) -> void:
	"""Persistent banner anchored near the monster art that calls out an
	incoming next fight. Stays visible (with a subtle alpha pulse) until
	hide_flock_warning() is called."""
	hide_flock_warning()
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("#FF8888"))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 22)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 115
	add_child(label)
	label.reset_size()
	# Position over the monster art's top edge — falls back to a panel-relative
	# spot if the art label isn't laid out yet.
	var target_pos := Vector2(size.x * 0.72, size.y * 0.10)
	if _monster_art_label and is_instance_valid(_monster_art_label) and _monster_art_label.size != Vector2.ZERO:
		var art_top_center = _monster_art_label.global_position + Vector2(_monster_art_label.size.x * 0.5, 4)
		target_pos = art_top_center - global_position
	label.position = target_pos - label.size * 0.5
	label.modulate.a = 0.0
	_flock_warning_label = label
	# Fade in
	var fade_in := create_tween()
	fade_in.tween_property(label, "modulate:a", 1.0, 0.22)
	# Subtle alpha pulse so the eye keeps coming back to it without it strobing
	var pulse := create_tween().set_loops()
	pulse.tween_property(label, "modulate:a", 0.65, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(label, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func hide_flock_warning() -> void:
	if _flock_warning_label and is_instance_valid(_flock_warning_label):
		_flock_warning_label.queue_free()
	_flock_warning_label = null


# === Alt sprite (ASCII art) — /altsprite test ===

func set_player_ascii_art(text: String, font_size: int = 3, color_hex: String = "#E8E8E8") -> void:
	"""Render ASCII art at the bottom of the player column. Collapses the
	PNG sprite holder so the companion stays as the only thing on the
	left side of the battle row."""
	if _player_ascii_label == null or not is_instance_valid(_player_ascii_label):
		return
	var safe_text = text.replace("[", "[lb]")  # keep stray brackets from being read as BBCode tags
	_player_ascii_label.text = "[font_size=%d][color=%s]%s[/color][/font_size]" % [font_size, color_hex, safe_text]
	if _ascii_outer:
		_ascii_outer.visible = true
	if _player_sprite_holder:
		_player_sprite_holder.visible = false
	if _player_sprite_rect:
		_player_sprite_rect.visible = false
	if _player_sprite_placeholder:
		_player_sprite_placeholder.visible = false


func clear_player_ascii_art() -> void:
	"""Hide the ASCII holder and restore the PNG sprite slot."""
	if _ascii_outer:
		_ascii_outer.visible = false
	if _player_sprite_holder:
		_player_sprite_holder.visible = true
	# Re-run the player refresh so the PNG/placeholder visibility resets
	# correctly based on the current class.
	_refresh_player()


func is_alt_sprite_visible() -> bool:
	return _ascii_outer != null and is_instance_valid(_ascii_outer) and _ascii_outer.visible


func _player_visual_for_fx() -> Control:
	"""Return whichever player visual is currently visible. For ASCII this
	is the inner Panel (which has free-floating position so lunge tweens
	don't fight the HBox layout); for PNG it's the TextureRect."""
	if _ascii_outer and is_instance_valid(_ascii_outer) and _ascii_outer.visible:
		return _player_ascii_holder
	return _player_sprite_rect


# === Victory card ===

func _build_victory_card_overlay() -> void:
	"""Card layered over the log section that shows post-fight rewards
	(XP, level-up, loot) inside the scene panel. Hidden by default; shown
	via show_victory_card()."""
	_victory_card_overlay = PanelContainer.new()
	_victory_card_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.05, 0.04, 0.06, 0.97)
	card_sb.border_color = Color("#FFD700")
	card_sb.set_border_width_all(2)
	card_sb.set_corner_radius_all(4)
	card_sb.content_margin_left = 10
	card_sb.content_margin_right = 10
	card_sb.content_margin_top = 6
	card_sb.content_margin_bottom = 6
	_victory_card_overlay.add_theme_stylebox_override("panel", card_sb)
	_victory_card_overlay.visible = false
	_victory_card_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	_log_inner.add_child(_victory_card_overlay)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_victory_card_overlay.add_child(vbox)

	# Header row — small "REWARDS" tag (the big "VICTORY!" banner from
	# play_victory_fx already announced the outcome, so the card just lists
	# what was earned).
	var header := RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.add_theme_font_size_override("normal_font_size", 14)
	header.text = "[b][color=#FFD700]REWARDS[/color][/b]"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	_victory_card_xp_label = RichTextLabel.new()
	_victory_card_xp_label.bbcode_enabled = true
	_victory_card_xp_label.fit_content = true
	_victory_card_xp_label.scroll_active = false
	_victory_card_xp_label.add_theme_font_size_override("normal_font_size", 13)
	_victory_card_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_victory_card_xp_label)

	_victory_card_levelup_label = RichTextLabel.new()
	_victory_card_levelup_label.bbcode_enabled = true
	_victory_card_levelup_label.fit_content = true
	_victory_card_levelup_label.scroll_active = false
	_victory_card_levelup_label.add_theme_font_size_override("normal_font_size", 14)
	_victory_card_levelup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_victory_card_levelup_label.visible = false
	vbox.add_child(_victory_card_levelup_label)

	# Divider before loot
	var divider1 := ColorRect.new()
	divider1.color = Color("#5C4D33")
	divider1.custom_minimum_size = Vector2(0, 1)
	divider1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider1)

	# Loot list — scrollable in case there are many drops
	var loot_scroll := ScrollContainer.new()
	loot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	loot_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(loot_scroll)

	_victory_card_loot_vbox = VBoxContainer.new()
	_victory_card_loot_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_victory_card_loot_vbox.add_theme_constant_override("separation", 1)
	loot_scroll.add_child(_victory_card_loot_vbox)

	# Divider before prompt
	var divider2 := ColorRect.new()
	divider2.color = Color("#5C4D33")
	divider2.custom_minimum_size = Vector2(0, 1)
	divider2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider2)

	_victory_card_prompt_label = RichTextLabel.new()
	_victory_card_prompt_label.bbcode_enabled = true
	_victory_card_prompt_label.fit_content = true
	_victory_card_prompt_label.scroll_active = false
	_victory_card_prompt_label.add_theme_font_size_override("normal_font_size", 13)
	_victory_card_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_victory_card_prompt_label)


func show_victory_card(rewards: Dictionary) -> void:
	"""Render the post-fight rewards card. Expected keys:
	xp_gain (int), old_level (int), new_level (int), did_level_up (bool),
	loot (Array of preformatted BBCode strings), harvest_available (bool),
	continue_key (String).
	The card stays visible until hide_victory_card() is called."""
	if _victory_card_overlay == null or not is_instance_valid(_victory_card_overlay):
		return

	var xp_gain = int(rewards.get("xp_gain", 0))
	if xp_gain > 0:
		_victory_card_xp_label.text = "[color=#A0E0FF]+%d XP[/color]" % xp_gain
		_victory_card_xp_label.visible = true
	else:
		_victory_card_xp_label.text = ""
		_victory_card_xp_label.visible = false

	var did_level_up = bool(rewards.get("did_level_up", false))
	if did_level_up:
		var old_level = int(rewards.get("old_level", 0))
		var new_level = int(rewards.get("new_level", 0))
		_victory_card_levelup_label.text = "[b][color=#FFE066]LEVEL UP![/color][/b]  [color=#FFE066]Lv %d → Lv %d[/color]" % [old_level, new_level]
		_victory_card_levelup_label.visible = true
	else:
		_victory_card_levelup_label.visible = false

	# Replace loot rows
	for child in _victory_card_loot_vbox.get_children():
		child.queue_free()
	var loot: Array = rewards.get("loot", [])
	if loot.is_empty():
		var none_row := RichTextLabel.new()
		none_row.bbcode_enabled = true
		none_row.fit_content = true
		none_row.scroll_active = false
		none_row.add_theme_font_size_override("normal_font_size", 12)
		none_row.text = "[color=#888888]  No items dropped[/color]"
		none_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_victory_card_loot_vbox.add_child(none_row)
	else:
		for drop_msg in loot:
			var row := RichTextLabel.new()
			row.bbcode_enabled = true
			row.fit_content = true
			row.scroll_active = false
			row.add_theme_font_size_override("normal_font_size", 12)
			row.text = "  " + str(drop_msg)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_victory_card_loot_vbox.add_child(row)

	var key_name = str(rewards.get("continue_key", "Space"))
	var primary_prompt = ""
	if bool(rewards.get("harvest_available", false)):
		primary_prompt = "[color=#FF6600][b]Press [%s] to harvest[/b][/color]" % key_name
	else:
		primary_prompt = "[color=#FFD700]Press [%s] to continue[/color]" % key_name
	# Secondary hint — let players who want the full play-by-play pop the
	# legacy detail view (game_output) without pressing continue.
	_victory_card_prompt_label.text = "%s   [color=#888888]·  Press [L] to view details[/color]" % primary_prompt

	_victory_card_overlay.visible = true
	if _log_scroll:
		_log_scroll.visible = false
	_victory_interlude_active = true
	# Subtle slide-in: fade from invisible to full alpha
	_victory_card_overlay.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_victory_card_overlay, "modulate:a", 1.0, 0.18)


func hide_victory_card() -> void:
	if _victory_card_overlay and is_instance_valid(_victory_card_overlay):
		_victory_card_overlay.visible = false
	if _log_scroll and is_instance_valid(_log_scroll):
		_log_scroll.visible = true
	_victory_interlude_active = false


func is_victory_card_visible() -> bool:
	return _victory_card_overlay != null and is_instance_valid(_victory_card_overlay) and _victory_card_overlay.visible


func is_victory_interlude_active() -> bool:
	"""True while the post-fight rewards interlude is in progress. Drives
	the panel-stays-visible logic on the client."""
	return _victory_interlude_active
