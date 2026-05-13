extends Control
class_name CombatScenePanel

# JRPG-style battle scene overlay. Top half is the scene (player+companion
# on the left, monster on the right). Bottom half is a combat log mirror.
# A1 slice — static layout only, no animations yet. PNG class sprites on
# the left, ASCII monster art on the right (mismatched by design — see
# project_combat_juice.md for the decision).
#
# v0.9.417 — Lufia II is the only combat layout. Earlier prototypes
# (LAYOUT_STANDARD, LAYOUT_CHRONO) are dead-code conditionals kept around
# because they don't run anymore — see set_layout removal + combat_layout
# const below. Cleanup pass to delete the dead branches is a follow-up.
const LAYOUT_STANDARD := "standard"
const LAYOUT_CHRONO := "chrono"
const LAYOUT_LUFIA := "lufia"
const combat_layout: String = LAYOUT_LUFIA

const MONO_FONT_PATH := "res://font/Consolas/consolas.ttf"
static var _mono_font: FontFile = null

var client_ref = null

# Cached state (last populate call)
var _player_class: String = ""
var _player_name: String = ""
# Cosmetic appearance variant rolled at character creation. Drives per-line
# pattern recolor of the player's class ASCII art so each character gets a
# unique look. Populated via populate() payload.
var _player_appearance_color: String = ""
var _player_appearance_color2: String = ""
var _player_appearance_pattern: String = "solid"
var _player_hp: int = 0
var _player_max_hp: int = 1
# v0.9.415 — secondary resource (MP/SP/Energy) for the overlay bar.
var _player_resource_cur: int = 0
var _player_resource_max: int = 1
var _player_resource_color: Color = Color("#3DD9FF")
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
# Flock encounter log archive — each entry: {monster_name, color, level, art, lines}.
# Populated by clear_log(archive=true) so [L] legacy view can replay prior fights
# from the same flock chain.
var _flock_history: Array = []
const FLOCK_HISTORY_LIMIT := 16

# Layout nodes
var _root_panel: PanelContainer
var _scene_section: Control  # v0.9.380 — HBox in standard layout, VBox in chrono
var _log_section: PanelContainer

# Player column
var _player_col: Control  # v0.9.382 — relaxed from VBoxContainer so Lufia (HBox of stat boxes) can use the same reference
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
var _companion_section: Control  # v0.9.383 — VBox in standard/chrono, HBox in lufia stat-box
var _companion_art: RichTextLabel
var _companion_name_label: RichTextLabel
# Tiny XP + HP bars between the companion name and the ASCII art. XP bar
# fills as the companion gains XP from kills; HP bar (Phase B1) shows the
# companion's persistent combat HP — it stays low between fights and is
# healed at healers / via potion target.
var _companion_xp_bar: ProgressBar
var _companion_xp_text: Label
var _companion_hp_bar: ProgressBar
var _companion_hp_text: Label
var _companion_hp_row: HBoxContainer
var _companion_hp: int = -1
var _companion_max_hp: int = -1
var _companion_is_ko: bool = false

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

# Status-effect strip (DoT timers / buffs / debuffs). RichTextLabels with
# BBCode-rendered compact tags so colors and per-effect timers fit in one
# row. Hidden when there's nothing active.
var _status_strip: HBoxContainer
var _player_status_label: RichTextLabel
var _monster_status_label: RichTextLabel

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
var _flock_warning_pulse_tween: Tween = null

# Victory card — overlay on the log section showing XP/loot/level-up/prompt
# after a non-flock victory, so the player reads rewards inside the scene
# panel instead of being yanked into a wall of text in game_output.
var _victory_card_overlay: PanelContainer
var _victory_card_monster_label: RichTextLabel  # v0.9.418 — "Defeated: Troll (Lv 21)"
var _victory_card_totals_label: RichTextLabel   # v0.9.418 — "You: 302 · Pet: 25 · Foe: 22"
var _victory_card_xp_label: RichTextLabel
var _victory_card_levelup_label: RichTextLabel
var _victory_card_gear_banner: PanelContainer  # v0.9.353 — dedicated callout for gear drops
var _victory_card_gear_vbox: VBoxContainer
var _victory_card_loot_vbox: VBoxContainer
var _victory_card_prompt_label: RichTextLabel
# True from show_victory_card() until hide_victory_card(), independent of
# whether the player has temporarily swapped to the log view. Drives the
# panel-stays-visible logic on the client.
var _victory_interlude_active: bool = false

# Death card — same structure as the victory card, fired from permadeath.
# Shows the eulogy headline + key stats inside the scene panel so death
# feels like part of combat instead of a wall-of-text exit.
var _death_card_overlay: PanelContainer
var _death_card_header_label: RichTextLabel
var _death_card_summary_label: RichTextLabel
var _death_card_combat_label: RichTextLabel
var _death_card_rewards_label: RichTextLabel
var _death_card_prompt_label: RichTextLabel
var _death_interlude_active: bool = false

# A2 — hit feedback. Active tween references so a rapid second hit doesn't
# stack on top of an in-progress flash/lunge (we kill the previous one).
var _player_flash_tween: Tween = null
var _monster_flash_tween: Tween = null
var _companion_flash_tween: Tween = null
var _player_lunge_tween: Tween = null
var _companion_lunge_tween: Tween = null  # v0.9.410 — per-actor companion lunge
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
# v0.9.395 — time-windowed vertical stack so back-to-back hits don't overlap.
# Each spawn within DAMAGE_STACK_RESET_S of the previous gets pushed up by
# DAMAGE_STACK_STEP_PX; cleared when there's a gap >= reset window.
var _damage_label_last_spawn_ts: float = -10.0
var _damage_label_stack_y: float = 0.0
const DAMAGE_STACK_STEP_PX := 70.0
# v0.9.415 — was 0.35s; popups linger 1.0s + fade 0.35s, so two popups within
# ~1.35s would overlap. Use a window slightly longer than full popup lifetime
# so consecutive popups always stack instead of overdrawing each other.
const DAMAGE_STACK_RESET_S := 1.5
# v0.9.415 — cap stack so rapid bursts don't push popups off the panel.
# At 70px/step, 210px = 4 popups visible before plateauing. Beyond that the
# topmost slot is reused and new popups overlap the previous topmost, but
# everything stays on-screen.
const DAMAGE_STACK_MAX_OFFSET := 210.0

const FLASH_TINT_HIT := Color(1.6, 0.5, 0.5)  # Reddish overdrive
const FLASH_TINT_CRIT := Color(2.0, 0.4, 0.2)  # Hotter red
const FLASH_DURATION := 0.18
const LUNGE_DISTANCE := 16.0
const LUNGE_DURATION := 0.10  # one direction; total = 2x

# Audit #1 Slice 6a — combat hand row. Card cells in a horizontal strip
# plus a small "Deck N · Discard M" indicator on the right. Cells are
# PanelContainers built once at layout time and rebuilt on each hand
# update so we don't repeatedly add/remove children mid-combat.
# v0.9.419 — hand size dropped 5 → 3 so each card matters more per round
# and the strip footprint shrinks. Must match shared/combat_manager.gd's
# COMBAT_HAND_SIZE — server fallback uses the server const, so a
# mismatch would render empty cells.
const COMBAT_HAND_SIZE := 3
signal card_played(card_name: String)
var _hand_strip: HBoxContainer
var _hand_cells: Array = []  # Array of PanelContainers (5)
var _hand_status_label: Label
var _combat_hand: Array = []
var _combat_deck_count: int = 0
var _combat_discard_count: int = 0
# v0.9.385 — optional Lufia-box mirror widgets (HP + deck info inside the
# player's stat box, beside the portrait). Created in
# _build_lufia_player_box_content and updated alongside the shared widgets;
# null in non-lufia layouts.
var _lufia_player_hp_bar: ProgressBar
var _lufia_player_hp_text: Label
var _lufia_player_deck_label: Label
# v0.9.405 — refs to the stats VBox inside each Lufia stat box so the
# action-phase transition can fade ONLY the stats (HP bars, deck info,
# names) while leaving the portrait ASCII visible — characters now appear
# on the battlefield during action, matching Lufia II.
var _lufia_player_stats: VBoxContainer = null
var _lufia_companion_stats: VBoxContainer = null
# v0.9.406 — per-portrait bg panels. _refresh_portrait_bg paints them with a
# contrasting color based on the variant brightness so dark variants pop
# against a parchment-like bg. Painted in set_player_ascii_art / _refresh_companion.
var _player_portrait_bg: Panel = null
var _companion_portrait_bg: Panel = null
# v0.9.403 — Lufia II battlefield reveal: stat boxes hide during action phase
# (FX play out on a clear stage), then return for next-turn command select.
var _action_phase_active: bool = false
var _action_phase_tween: Tween = null
var _action_phase_end_timer: SceneTreeTimer = null
# v0.9.390 — Lufia mode also relocates the monster HP bar to a bordered
# strip at the TOP of the monster column (was bottom-right shared strip).
# These mirror widgets are updated alongside _monster_hp_bar / _text in
# _refresh_monster_hp; null in non-lufia layouts.
var _lufia_monster_hp_bar: ProgressBar
var _lufia_monster_hp_text: Label
# Reference to the shared HP strip so Lufia can hide it (player + monster
# HP both live inside their respective Lufia widgets).
var _shared_hp_strip: HBoxContainer
const HAND_RANK_NAMES: Array = ["Untrained", "Novice", "Adept", "Expert", "Master"]
const HAND_RANK_COLORS: Array = ["#888888", "#9ACD32", "#66CCFF", "#FFD700", "#FF6644"]


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
	# v0.9.406 — reverted to original dark plum (mid-gray made things worse
	# overall). Dark-variant readability is handled by a contrasting portrait
	# bg added per-portrait in populate() (see _refresh_portrait_bg).
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

	# === Top: scene (player vs monster) — layout-specific arrangement ===
	# v0.9.380 — dispatch by combat_layout. Both layouts share the bottom
	# strips (HP / status / totals / hand / log) since those are pure
	# data displays, not arrangement-sensitive.
	var scene_root: Control
	match combat_layout:
		LAYOUT_CHRONO:
			scene_root = _build_scene_section_chrono()
		LAYOUT_LUFIA:
			scene_root = _build_scene_section_lufia()
		_:
			scene_root = _build_scene_section_standard()
	root_vbox.add_child(scene_root)

	# === Shared HP strip — player on left, monster on right, same row ===
	# v0.9.390 — Lufia hides this strip; player HP lives inside the player
	# stat box and monster HP lives in a bordered strip atop the monster column.
	_shared_hp_strip = _build_shared_hp_strip()
	root_vbox.add_child(_shared_hp_strip)
	if combat_layout == LAYOUT_LUFIA:
		_shared_hp_strip.visible = false

	# === Status-effect strip (DoT timers / buffs / debuffs) ===
	root_vbox.add_child(_build_shared_status_strip())

	# === Running damage totals strip (Combat readability #2) ===
	root_vbox.add_child(_build_running_totals_strip())

	# === Audit #1 Slice 6a — combat hand row (cards drawn this combat) ===
	root_vbox.add_child(_build_hand_strip())

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
	# v0.9.383 — log shrinks in vertical layouts so scene_section (now
	# stretch_ratio 4.0 for chrono/lufia) actually gets the vertical room
	# it needs. Standard layout keeps the larger log it had before.
	if combat_layout == LAYOUT_STANDARD:
		_log_section.size_flags_stretch_ratio = 1.0
	else:
		_log_section.size_flags_stretch_ratio = 0.4
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
	_build_death_card_overlay()


func _build_scene_section_standard() -> Control:
	"""Standard layout: HBox with player+companion column on the left and
	monster column on the right. v0.9.380 — extracted from the original
	`_build_layout` body; same visual result as before this refactor."""
	_scene_section = HBoxContainer.new()
	_scene_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_section.size_flags_stretch_ratio = 2.0
	_scene_section.add_theme_constant_override("separation", 8)
	_scene_section.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_player_col = _build_player_column()
	_scene_section.add_child(_player_col)

	_monster_col = _build_monster_column()
	_scene_section.add_child(_monster_col)
	return _scene_section


func _build_scene_section_chrono() -> Control:
	"""Chrono Trigger / Mother 2 style: monster centered + large at the top,
	small party row underneath.

	v0.9.383 — third rewrite. Earlier versions inflated the party row to
	~280px because the full 180x260 battle ASCII art was bundled into the
	player block, starving the monster of vertical space. This version:
	  - Player block contains ONLY the small sprite (~72×72) — no battle
	    ASCII (it's hidden / unused in vertical layouts).
	  - Companion content shrunk to ~72×72 ASCII portrait.
	  - Scene stretch_ratio bumped to 4.0 (vs log_section's 1.0) so the
	    vertical layout actually gets the vertical room it needs.
	  - Inner stretch 4:1 between monster and party row → monster ~80%."""
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 4.0  # Bumped from 2.0 so vertical layouts dominate the panel
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_section = vbox

	# Top: monster, centered, fills the upper 80% of scene_section.
	_monster_col = _build_monster_column()
	_monster_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_monster_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_monster_col.size_flags_stretch_ratio = 4.0
	_monster_col.custom_minimum_size = Vector2(480, 0)
	vbox.add_child(_monster_col)

	# Bottom: small party row, ~20% of scene_section. Sprite-only — no
	# battle ASCII inflating the minimum height.
	var party_row := HBoxContainer.new()
	party_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_row.size_flags_stretch_ratio = 1.0
	party_row.alignment = BoxContainer.ALIGNMENT_CENTER
	party_row.add_theme_constant_override("separation", 24)
	party_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(party_row)

	party_row.add_child(_build_compact_player_block(COMPACT_PORTRAIT_PX))
	party_row.add_child(_build_compact_companion_block(COMPACT_PORTRAIT_PX))

	_player_col = party_row
	return vbox


func _build_scene_section_lufia() -> Control:
	"""Lufia II style per SNES reference: enemy occupies the upper ~75% of
	the scene; party members live in a row of BORDERED STAT BOXES at the
	bottom, each box arranged as [portrait LEFT | stats RIGHT VBox].

	v0.9.383 — third rewrite. Two earlier attempts (v0.9.381 side-view,
	v0.9.382 stacked portrait-above-stats) both failed because the full
	battle ASCII was included inside the boxes and inflated their height
	to consume most of the scene. This version:
	  - Each box is HBox[ small portrait (~72×72) | VBox{name, xp, hp} ]
	  - Total box height ~110-130px regardless of art content
	  - Scene stretch_ratio = 4.0 so vertical layouts get real vertical
	    room (log_section drops from 1.0 to a tight ~0.4 in _build_layout)
	  - Monster:party_box_row inner stretch 3:1 → monster ~75%"""
	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 4.0
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_section = vbox

	# Top: monster, centered. Big.
	_monster_col = _build_monster_column()
	_monster_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_monster_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_monster_col.size_flags_stretch_ratio = 3.0
	_monster_col.custom_minimum_size = Vector2(480, 0)
	vbox.add_child(_monster_col)

	# Bottom: row of bordered stat boxes. v0.9.388 — row expands to full
	# width of scene_section so ALIGNMENT_CENTER actually centers the boxes
	# horizontally. Boxes themselves use SIZE_SHRINK_CENTER so they only
	# take their content's width (no more stretching across the screen).
	var party_box_row := HBoxContainer.new()
	party_box_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_box_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	party_box_row.size_flags_stretch_ratio = 1.0
	party_box_row.alignment = BoxContainer.ALIGNMENT_CENTER
	party_box_row.add_theme_constant_override("separation", 12)
	party_box_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(party_box_row)

	party_box_row.add_child(_build_lufia_party_box(_build_lufia_player_box_content()))
	party_box_row.add_child(_build_lufia_party_box(_build_lufia_companion_box_content()))

	_player_col = party_box_row
	return vbox


func start_action_phase() -> void:
	"""v0.9.406 — Lufia II battlefield reveal. (1) The entire party box row
	fades out at the bottom; (2) a separate 'battlefield' overlay fades in
	at a different on-screen position, showing the same player + companion
	ASCII art at a larger size — characters appear ON the battlefield, not
	in the same place as the box. end_action_phase reverses both.

	v0.9.412 — also hide the running-totals banner, hand strip, and status
	strip while in the FX scene. Frees vertical room for the overlay so the
	bigger ASCII blocks don't get cut off by adjacent UI.

	No-op in LAYOUT_STANDARD."""
	if combat_layout == LAYOUT_STANDARD:
		return
	if _action_phase_active:
		return
	_action_phase_active = true
	_ensure_battlefield_overlay()
	_populate_battlefield_overlay()
	# v0.9.412 — collapse non-essential strips so the overlay has more room.
	if _totals_strip and is_instance_valid(_totals_strip):
		_totals_strip.visible = false
	if _hand_strip and is_instance_valid(_hand_strip):
		_hand_strip.visible = false
	if _status_strip and is_instance_valid(_status_strip):
		_status_strip.visible = false
	_kill_action_phase_tween()
	_action_phase_tween = create_tween().set_parallel(true)
	# Fade the whole party row down + out.
	if _player_col and is_instance_valid(_player_col):
		_action_phase_tween.tween_property(_player_col, "modulate:a", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Reposition overlay after the strips collapse so the new available
	# space is accounted for.
	call_deferred("_position_battlefield_overlay")
	# Reveal the battlefield overlay: starts above its rest position and
	# slides down into place with a fade-in.
	if _battlefield_overlay and is_instance_valid(_battlefield_overlay):
		_battlefield_overlay.visible = true
		_battlefield_overlay.modulate.a = 0.0
		_battlefield_overlay.position.y = _battlefield_overlay_rest_y - 40.0
		_action_phase_tween.tween_property(_battlefield_overlay, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_action_phase_tween.tween_property(_battlefield_overlay, "position:y", _battlefield_overlay_rest_y, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func end_action_phase() -> void:
	"""v0.9.406 — hide the battlefield overlay and slide the party row back.
	v0.9.412 — restore the running-totals / hand / status strips that were
	collapsed during the action phase."""
	if combat_layout == LAYOUT_STANDARD:
		return
	_cancel_action_phase_timer()
	if not _action_phase_active:
		return
	_action_phase_active = false
	# Restore the strips that were hidden in start_action_phase.
	if _totals_strip and is_instance_valid(_totals_strip):
		_totals_strip.visible = true
	if _hand_strip and is_instance_valid(_hand_strip):
		_hand_strip.visible = true
	if _status_strip and is_instance_valid(_status_strip):
		_status_strip.visible = true
	_kill_action_phase_tween()
	_action_phase_tween = create_tween().set_parallel(true)
	if _player_col and is_instance_valid(_player_col):
		_action_phase_tween.tween_property(_player_col, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _battlefield_overlay and is_instance_valid(_battlefield_overlay):
		_action_phase_tween.tween_property(_battlefield_overlay, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_action_phase_tween.tween_property(_battlefield_overlay, "position:y", _battlefield_overlay_rest_y - 40.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# Hide after the tween completes so it doesn't block input or paint.
		_action_phase_tween.chain().tween_callback(func():
			if _battlefield_overlay and is_instance_valid(_battlefield_overlay):
				_battlefield_overlay.visible = false
		)


# v0.9.411 — battlefield overlay rebuilt. Per-character block with its own
# ASCII label + HP bar + name; blocks are positioned manually inside the
# overlay so they can be lunged via position tweens during action phase.
# z_index=100 keeps the overlay above the damage banner / ability cards.
var _battlefield_overlay: Control = null
var _overlay_player_block: Control = null
var _overlay_player_ascii: RichTextLabel = null
var _overlay_player_hp_bar: ProgressBar = null
# v0.9.415 — secondary resource bar (MP/SP/energy depending on class) under
# the HP bar. Populated from the same data the in-box stats line uses.
var _overlay_player_resource_bar: ProgressBar = null
var _overlay_player_name: Label = null
var _overlay_companion_block: Control = null
var _overlay_companion_ascii: RichTextLabel = null
var _overlay_companion_hp_bar: ProgressBar = null
var _overlay_companion_name: Label = null
var _battlefield_overlay_rest_y: float = 0.0
var _overlay_player_block_baseline: Vector2 = Vector2.ZERO
var _overlay_companion_block_baseline: Vector2 = Vector2.ZERO

# v0.9.415 — per-actor log strips during action phase. Three small scrolling
# regions inside the overlay so each actor's actions appear over their own
# zone. Single combat log (_log_label) still receives everything and is the
# canonical record for non-overlay layouts / [L] legacy view.
const OVERLAY_LOG_LINE_LIMIT := 5
# v0.9.418 — pause button in the top-right corner of the FX overlay so the
# player can freeze the message-drain pacing and read what just happened.
# Connected to client.toggle_combat_pause() via client_ref.
var _pause_button: Button = null
var _overlay_player_log: RichTextLabel = null
var _overlay_monster_log: RichTextLabel = null
var _overlay_companion_log: RichTextLabel = null
var _overlay_player_log_lines: Array = []
var _overlay_monster_log_lines: Array = []
var _overlay_companion_log_lines: Array = []


func _ensure_battlefield_overlay() -> void:
	if _battlefield_overlay != null and is_instance_valid(_battlefield_overlay):
		return
	if _player_col == null or not is_instance_valid(_player_col):
		return
	var parent: Node = _player_col.get_parent()
	if parent == null:
		return
	# Root Control — sized + positioned in _position_battlefield_overlay.
	# top_level=true: escapes parent layout so we control the position.
	# z_index=100: draws above the damage banner / ability cards which sit
	# below the scene_section.
	_battlefield_overlay = Control.new()
	_battlefield_overlay.name = "BattlefieldOverlay"
	_battlefield_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battlefield_overlay.top_level = true
	_battlefield_overlay.z_index = 100
	_battlefield_overlay.visible = false
	parent.add_child(_battlefield_overlay)

	# v0.9.415 — per-actor log strips at the TOP of the overlay (above the
	# character blocks). Built first so they sit beneath blocks in z-order
	# but logically above in layout. Each is a small RichTextLabel that
	# scrolls a 3-5 line history of that actor's combat messages.
	_overlay_player_log = _build_overlay_log_label("left")
	_battlefield_overlay.add_child(_overlay_player_log)
	_overlay_monster_log = _build_overlay_log_label("center")
	_battlefield_overlay.add_child(_overlay_monster_log)
	_overlay_companion_log = _build_overlay_log_label("right")
	_battlefield_overlay.add_child(_overlay_companion_log)

	# Player block — bigger ASCII font (3) + mini HP bar + name underneath.
	_overlay_player_block = _build_overlay_character_block(true)
	_battlefield_overlay.add_child(_overlay_player_block)
	# Companion block — smaller ASCII font (2) since companion art is often wider.
	_overlay_companion_block = _build_overlay_character_block(false)
	_battlefield_overlay.add_child(_overlay_companion_block)

	# v0.9.418 — pause button. Positioned in _position_battlefield_overlay so
	# it tracks the overlay's actual size at runtime. z_index above strips so
	# it's clickable even when monster strip stretches across the top.
	_pause_button = Button.new()
	_pause_button.text = "⏸ PAUSE"
	_pause_button.tooltip_text = "Pause combat — message drain freezes until you press Resume"
	_pause_button.add_theme_font_size_override("font_size", 12)
	_pause_button.custom_minimum_size = Vector2(86, 28)
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.z_index = 5
	_pause_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_button.pressed.connect(_on_pause_button_pressed)
	_battlefield_overlay.add_child(_pause_button)

	# Defer initial positioning so layout has computed _player_col's rect.
	call_deferred("_position_battlefield_overlay")


func _on_pause_button_pressed() -> void:
	"""v0.9.418 — forward to client.toggle_combat_pause(). Client owns the
	paused-state flag because the combat message queue + drain timer live
	there. Panel just renders the button and updates its label."""
	if client_ref != null and client_ref.has_method("toggle_combat_pause"):
		client_ref.toggle_combat_pause()


func set_pause_button_label(paused: bool) -> void:
	"""Called by client when pause state toggles, so the button reflects the
	current state."""
	if _pause_button == null or not is_instance_valid(_pause_button):
		return
	if paused:
		_pause_button.text = "▶ RESUME"
		_pause_button.tooltip_text = "Resume combat — message drain continues"
	else:
		_pause_button.text = "⏸ PAUSE"
		_pause_button.tooltip_text = "Pause combat — message drain freezes until you press Resume"


func _build_overlay_log_label(align: String) -> RichTextLabel:
	"""v0.9.415 — small scrolling per-actor log shown in the action-phase
	overlay. Holds up to OVERLAY_LOG_LINE_LIMIT recent lines for one actor.
	v0.9.417 — bg removed; text floats over the combat bg so the strip
	disappears visually when empty (no bordered box). scroll_following
	keeps newest line at the bottom."""
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = false
	lbl.scroll_active = true
	lbl.scroll_following = true
	lbl.clip_contents = true
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("normal_font_size", 12)
	match align:
		"center":
			pass  # text aligns naturally; center the block via position
		"right":
			pass
	return lbl


func _build_overlay_character_block(is_player: bool) -> Control:
	"""v0.9.411 — a character block on the battlefield overlay. Manually
	positioned (no parent layout) so it can be lunged via position tweens.
	v0.9.412 — block bumped 220×160 → 320×280 so the ASCII art (often
	75+ lines tall at the bumped font_size) fits without vertical clipping.
	Hidden UI strips during action phase free the space to make this fit."""
	var block := Control.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.custom_minimum_size = Vector2(320, 280)

	# ASCII label fills the top portion of the block.
	var ascii := RichTextLabel.new()
	ascii.bbcode_enabled = true
	ascii.fit_content = false
	ascii.scroll_active = false
	ascii.autowrap_mode = TextServer.AUTOWRAP_OFF
	ascii.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ascii.anchor_left = 0.0
	ascii.anchor_top = 0.0
	ascii.anchor_right = 1.0
	ascii.anchor_bottom = 0.78
	if _mono_font:
		ascii.add_theme_font_override("normal_font", _mono_font)
		ascii.add_theme_font_override("bold_font", _mono_font)
		ascii.add_theme_font_override("mono_font", _mono_font)
	block.add_child(ascii)

	# HP bar — fixed width, just under the ASCII.
	# v0.9.415 — resource bar reverted; HP bar back to 0.80-0.86 for both
	# blocks (no overlap with ASCII at anchor 0.0-0.78).
	var hp_bar := _make_hp_bar(Color("#FF4444"))
	hp_bar.anchor_left = 0.12
	hp_bar.anchor_right = 0.88
	hp_bar.anchor_top = 0.80
	hp_bar.anchor_bottom = 0.86
	hp_bar.custom_minimum_size = Vector2(0, 8)
	block.add_child(hp_bar)

	var resource_bar: ProgressBar = null  # kept for assignment below; unused now

	# Name label — under the bar.
	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_lbl.add_theme_constant_override("outline_size", 2)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.anchor_left = 0.0
	name_lbl.anchor_right = 1.0
	name_lbl.anchor_top = 0.90
	name_lbl.anchor_bottom = 1.0
	block.add_child(name_lbl)

	if is_player:
		_overlay_player_ascii = ascii
		_overlay_player_hp_bar = hp_bar
		_overlay_player_resource_bar = resource_bar
		_overlay_player_name = name_lbl
	else:
		_overlay_companion_ascii = ascii
		_overlay_companion_hp_bar = hp_bar
		_overlay_companion_name = name_lbl
	return block


func _position_battlefield_overlay() -> void:
	"""v0.9.411 — overlay sits AT the party-row vertical band. Player block
	on the left, companion block on the right, each at fixed local positions
	inside the overlay so they can be lunged via position tweens.

	v0.9.412 — overlay can now claim the vertical space freed by the hidden
	totals/hand/status strips during action phase. Grows UP from the box
	row position toward the monster, capped so it doesn't touch monster art."""
	if _battlefield_overlay == null or not is_instance_valid(_battlefield_overlay):
		return
	if _player_col == null or not is_instance_valid(_player_col):
		return
	var rect: Rect2 = Rect2(_player_col.global_position, _player_col.size)
	# Vertical room: prefer 280px (matches block height) so the ASCII fits.
	# If the box row is shorter, grow upward (toward monster) by extending the
	# overlay height above the box top while keeping the bottom anchored to
	# the box top so we don't push into damage banner area below.
	# v0.9.418 — overlay min height bumped 280 → 340 to accommodate taller log
	# strips (so each strip fits a full round of messages without scrolling).
	# Monster-art gap reduced 8 → 4 so the overlay can grow upward when there's
	# little vertical room. If the clamp still kicks in, the strip-vs-block
	# split keeps strips at their floor (100px) and lets the block shrink last.
	var overlay_h: float = maxf(rect.size.y, 340.0)
	var overlay_y: float = rect.position.y - (overlay_h - rect.size.y)
	if _monster_col and is_instance_valid(_monster_col):
		var monster_bottom: float = _monster_col.global_position.y + _monster_col.size.y
		if overlay_y < monster_bottom + 4.0:
			overlay_y = monster_bottom + 4.0
			overlay_h = (rect.position.y + rect.size.y) - overlay_y
	_battlefield_overlay.size = Vector2(rect.size.x, overlay_h)
	_battlefield_overlay.global_position = Vector2(rect.position.x, overlay_y)
	_battlefield_overlay_rest_y = _battlefield_overlay.position.y

	# v0.9.415 — state the user confirmed worked well: 3-strip log visible
	# at top of overlay, player flush-left, companion flush-right, monster
	# strip 320px centered under the goblin.
	# v0.9.418 — strip height bumped from 0.22/60-110 to 0.30/100-140 so a full
	# round of messages fits without internal scrolling. Block height auto-
	# derives from the remaining overlay space below the strip row.
	var block_w: float = 320.0
	var edge_pad: float = 16.0
	var log_strip_h: float = clampf(overlay_h * 0.30, 100.0, 140.0)
	var log_gap: float = 4.0
	var bottom_pad: float = 0.0
	var block_y: float = log_strip_h + log_gap
	var block_h: float = overlay_h - block_y - bottom_pad
	# v0.9.415 — per-user request, lift the player AND companion columns up
	# by ~name-tag height so their ASCII / stats / name / log strip all sit
	# a bit higher. Monster strip stays where it is.
	var actor_lift: float = 22.0
	if _overlay_player_block and is_instance_valid(_overlay_player_block):
		_overlay_player_block.position = Vector2(edge_pad, block_y - actor_lift)
		_overlay_player_block.size = Vector2(block_w, block_h)
		_overlay_player_block_baseline = _overlay_player_block.position
	if _overlay_companion_block and is_instance_valid(_overlay_companion_block):
		_overlay_companion_block.position = Vector2(rect.size.x - block_w - edge_pad, block_y - actor_lift)
		_overlay_companion_block.size = Vector2(block_w, block_h)
		_overlay_companion_block_baseline = _overlay_companion_block.position

	# Three log strips across the top of the overlay. All three use the same
	# width (block_w) so they read as a consistent row of "actor speech".
	# Player aligned over player block, companion over companion block,
	# monster centered UNDER the actual monster art (right-aligned in Lufia
	# layout, so it sits well right of the overlay's geometric center).
	# v0.9.415 — separate Y positions: player/companion at the very top of
	# the overlay so they sit further from their own ASCII below; monster
	# offset DOWN so it sits further from the goblin's ASCII above.
	var log_w_actor: float = block_w
	var log_w_monster: float = block_w  # match the other two for visual rhythm
	var log_y_actor: float = 4.0
	# v0.9.415 — monster strip nudged DOWN by ~actor_lift so it sits further
	# from the goblin's lower ASCII edge above it (matches the amount the
	# player/companion columns were lifted upward).
	var log_y_monster: float = 4.0 + actor_lift
	if _overlay_player_log and is_instance_valid(_overlay_player_log):
		# Same lift as the player block above so the column moves as one.
		_overlay_player_log.position = Vector2(edge_pad, log_y_actor - actor_lift)
		_overlay_player_log.size = Vector2(log_w_actor, log_strip_h)
	if _overlay_companion_log and is_instance_valid(_overlay_companion_log):
		_overlay_companion_log.position = Vector2(rect.size.x - log_w_actor - edge_pad, log_y_actor - actor_lift)
		_overlay_companion_log.size = Vector2(log_w_actor, log_strip_h)
	# v0.9.418 — pause button: top-right corner of the overlay, inside the
	# rect so it sits over the companion strip's top-right corner. z_index
	# above the strip keeps it clickable. Strips use scroll_following so
	# newest text is at the bottom — covering the top-right corner only
	# obscures the oldest line that's about to scroll off.
	if _pause_button and is_instance_valid(_pause_button):
		var btn_w: float = 86.0
		var btn_h: float = 26.0
		_pause_button.position = Vector2(rect.size.x - btn_w - 4.0, 2.0)
		_pause_button.size = Vector2(btn_w, btn_h)
	if _overlay_monster_log and is_instance_valid(_overlay_monster_log):
		# Anchor monster log horizontally under the monster art. _monster_col
		# / _monster_art_label live in a different parent than _player_col,
		# so use their global position to get the actual on-screen center.
		var monster_center_global_x: float = rect.position.x + rect.size.x * 0.5
		if _monster_art_label and is_instance_valid(_monster_art_label):
			monster_center_global_x = _monster_art_label.global_position.x + _monster_art_label.size.x * 0.5
		elif _monster_col and is_instance_valid(_monster_col):
			monster_center_global_x = _monster_col.global_position.x + _monster_col.size.x * 0.5
		var monster_local_x: float = monster_center_global_x - rect.position.x - log_w_monster * 0.5
		# Loose clamp: just don't escape the overlay. Allow overlap with the
		# player/companion strip if the monster sits there — readability of
		# the actual on-target position wins over zone separation.
		monster_local_x = clampf(monster_local_x, 0.0, rect.size.x - log_w_monster)
		_overlay_monster_log.position = Vector2(monster_local_x, log_y_monster)
		_overlay_monster_log.size = Vector2(log_w_monster, log_strip_h)


func _populate_battlefield_overlay() -> void:
	"""v0.9.411 — copy ASCII + stat data into the overlay blocks. Font sizes
	bumped (+2) so the battlefield reveal reads larger than the in-box
	portraits. HP bar + name pulled from current stats."""
	# Player ASCII — bumped font size for battlefield-scale.
	# v0.9.415 — was +2; reduced to +1 so tall ASCII fits the block without
	# vertical clipping. Block height is fixed and the bumped fonts overran.
	# v0.9.415 — wrap in [center] so the ASCII sits over the centered HP bar
	# (HP bar is anchored 0.12-0.88, ASCII previously left-aligned looked
	# offset to the left of the bar).
	if _overlay_player_ascii and is_instance_valid(_overlay_player_ascii):
		if _player_ascii_label and is_instance_valid(_player_ascii_label):
			var p_bumped = _bump_inline_font_size(_player_ascii_label.text, 1)
			_overlay_player_ascii.text = "[center]" + p_bumped + "[/center]"
		else:
			_overlay_player_ascii.text = ""
	# Player HP bar + name.
	if _overlay_player_hp_bar and is_instance_valid(_overlay_player_hp_bar):
		_overlay_player_hp_bar.max_value = maxi(1, _player_max_hp)
		_overlay_player_hp_bar.value = clampi(_player_hp, 0, _player_max_hp)
	# v0.9.415 — wire resource bar (MP/SP/Energy) under the HP bar.
	if _overlay_player_resource_bar and is_instance_valid(_overlay_player_resource_bar):
		_overlay_player_resource_bar.max_value = maxi(1, _player_resource_max)
		_overlay_player_resource_bar.value = clampi(_player_resource_cur, 0, _player_resource_max)
		var fill := _overlay_player_resource_bar.get_theme_stylebox("fill")
		if fill is StyleBoxFlat:
			(fill as StyleBoxFlat).bg_color = _player_resource_color
	if _overlay_player_name and is_instance_valid(_overlay_player_name):
		_overlay_player_name.text = _player_name

	# Companion ASCII + stats. v0.9.415 — bump dropped +2 → +1 to match player.
	if _overlay_companion_ascii and is_instance_valid(_overlay_companion_ascii):
		if _companion_art and is_instance_valid(_companion_art):
			_overlay_companion_ascii.text = _bump_inline_font_size(_companion_art.text, 1)
		else:
			_overlay_companion_ascii.text = ""
	if _overlay_companion_hp_bar and is_instance_valid(_overlay_companion_hp_bar):
		var c_level := int(_companion_data.get("level", 1))
		var c_sub_tier := int(_companion_data.get("sub_tier", _companion_data.get("tier", 1)))
		var c_bonuses: Dictionary = _companion_data.get("bonuses", {})
		var c_hp_bonus := int(c_bonuses.get("hp_bonus", 0))
		var c_max_hp := maxi(1, 30 + c_level * 5 + c_sub_tier * 10 + c_hp_bonus)
		var c_cur_hp := int(_companion_data.get("combat_hp", c_max_hp))
		_overlay_companion_hp_bar.max_value = c_max_hp
		_overlay_companion_hp_bar.value = clampi(c_cur_hp, 0, c_max_hp)
	if _overlay_companion_name and is_instance_valid(_overlay_companion_name):
		_overlay_companion_name.text = str(_companion_data.get("name", "Companion"))

	# Reposition (handles window resize / layout shifts).
	_position_battlefield_overlay()


func _bump_inline_font_size(bbcode: String, bump: int) -> String:
	"""Find [font_size=N] tags in the BBCode and replace each with [font_size=N+bump]."""
	if bbcode == null or bbcode == "" or bump <= 0:
		return bbcode
	var regex := RegEx.new()
	regex.compile("\\[font_size=(\\d+)\\]")
	var out := bbcode
	var matches := regex.search_all(out)
	# Walk matches in reverse so substring offsets stay valid as we substitute.
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var n_str: String = m.get_string(1)
		var n: int = n_str.to_int() + bump
		var rep: String = "[font_size=%d]" % n
		out = out.substr(0, m.get_start()) + rep + out.substr(m.get_end())
	return out


func end_action_phase_after(delay_seconds: float) -> void:
	"""v0.9.403 — schedule end_action_phase after a delay so FX have time to
	play out before the boxes slide back. Cancels any prior pending end."""
	_cancel_action_phase_timer()
	if not _action_phase_active:
		return
	_action_phase_end_timer = get_tree().create_timer(max(0.0, delay_seconds))
	_action_phase_end_timer.timeout.connect(end_action_phase)


func _kill_action_phase_tween() -> void:
	if _action_phase_tween != null and _action_phase_tween.is_valid():
		_action_phase_tween.kill()
	_action_phase_tween = null


func _cancel_action_phase_timer() -> void:
	# SceneTreeTimer doesn't expose a cancel; we drop the reference and the
	# old timer's timeout fires into a no-op since end_action_phase is
	# guarded by _action_phase_active.
	_action_phase_end_timer = null


func _build_compact_player_block(portrait_size: int) -> VBoxContainer:
	"""Chrono helper: small player block — name on top, tiny ASCII portrait
	below. v0.9.385 — battle is ASCII even in compact layouts; sprite is
	overworld-only. set_player_ascii_art() applies a small font_size
	override when _is_compact_layout() so the art fits in portrait_size."""
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_create_player_name_label())
	# Sprite holder still exists for classes with no ASCII art, but it sits
	# at portrait_size and is hidden by default — set_player_ascii_art will
	# flip _ascii_outer visible / _player_sprite_holder hidden when ASCII is
	# present.
	var sprite_holder = _create_player_sprite_holder()
	sprite_holder.custom_minimum_size = Vector2(portrait_size, portrait_size)
	if _player_sprite_rect:
		_player_sprite_rect.custom_minimum_size = Vector2(portrait_size - 4, portrait_size - 4)
	col.add_child(sprite_holder)
	# Compact ASCII holder — portrait_size × portrait_size, clipped, no
	# fit_content inflation. _player_ascii_label fills via PRESET_FULL_RECT.
	var ascii_holder = _create_player_ascii_holder()
	ascii_holder.custom_minimum_size = Vector2(portrait_size, portrait_size)
	ascii_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ascii_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _player_ascii_holder:
		_player_ascii_holder.size = Vector2(portrait_size, portrait_size)
	col.add_child(ascii_holder)
	return col


func _build_compact_companion_block(portrait_size: int) -> VBoxContainer:
	"""Chrono helper: small companion block with the existing name + bar
	rows, plus a TINY ASCII portrait. v0.9.383 — sized so it doesn't
	dominate the party row."""
	_companion_section = VBoxContainer.new()
	_companion_section.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_companion_section.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_companion_section.add_theme_constant_override("separation", 2)
	_companion_section.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label = _create_companion_name_label()
	name_label.add_theme_font_size_override("normal_font_size", 11)
	name_label.custom_minimum_size = Vector2(portrait_size, 0)
	_companion_section.add_child(name_label)
	_companion_section.add_child(_create_companion_xp_row())
	_companion_section.add_child(_create_companion_hp_row())
	var art = _create_companion_art_label()
	# v0.9.384 — fit_content=true (default in _create_companion_art_label)
	# makes the label grow to its content's natural width/height,
	# ignoring custom_minimum_size as a ceiling. Disable it here so
	# custom_minimum_size + clip_contents=true actually bounds the art
	# to the 72×72 portrait box.
	art.fit_content = false
	art.custom_minimum_size = Vector2(portrait_size, portrait_size)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_companion_section.add_child(art)
	return _companion_section


func _build_lufia_monster_hp_panel() -> PanelContainer:
	"""v0.9.390 — bordered Lufia-style strip at the top of the monster column
	showing the monster's HP bar + cur/max text. Same border palette as the
	party stat boxes for visual cohesion. Width is content-sized + centered
	so it doesn't stretch across the screen."""
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# v0.9.406 — reverted Lufia box bg to original dark navy. Contrast for
	# dark-variant portraits is handled by _refresh_portrait_bg painting a
	# light parchment color behind ONLY the portrait, not the whole box.
	sb.bg_color = Color(0.06, 0.05, 0.10, 0.96)
	sb.border_color = Color(0.75, 0.78, 0.92, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_top = 4
	sb.content_margin_right = 8
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)

	# v0.9.395 — bar enlarged to 440×20 (was 220×12) so it's a prominent strip
	# centered over the monster art. Fill color is re-tinted to the monster's
	# class-affinity color (_monster_name_color) in _refresh_monster_hp.
	_lufia_monster_hp_bar = _make_hp_bar(Color("#FFAA22"))
	_lufia_monster_hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lufia_monster_hp_bar.custom_minimum_size = Vector2(440, 20)
	row.add_child(_lufia_monster_hp_bar)

	_lufia_monster_hp_text = Label.new()
	_lufia_monster_hp_text.add_theme_font_size_override("font_size", 13)
	_lufia_monster_hp_text.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_lufia_monster_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lufia_monster_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_lufia_monster_hp_text)

	return box


func _build_lufia_party_box(content: Control) -> PanelContainer:
	"""Wrap a Lufia-style stat box: dark inset bg, light outer border.
	v0.9.388 — SHRINK_CENTER so the box only takes the content's width."""
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# v0.9.411 — near-black box bg. v0.9.410 warm-gray (0.13, 0.12, 0.11)
	# was too light; even Cobalt looked washed out. Near-black gives every
	# variant — Cobalt blue, Crimson red, Gold yellow — maximum contrast
	# against the bg.
	sb.bg_color = Color(0.02, 0.02, 0.03, 0.98)
	sb.border_color = Color(0.75, 0.78, 0.92, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	box.add_child(content)
	return box


func _build_lufia_player_box_content() -> HBoxContainer:
	"""Lufia stat box internal layout: portrait LEFT, stats RIGHT.
	v0.9.388 — content-sized (no EXPAND_FILL), fixed-width bars (COMPACT_BAR_W),
	portrait sized W×H so the wide companion ASCII isn't clipped horizontally."""
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# v0.9.390 — tightened from 8 to 2 to remove dead horizontal space
	# between portrait and stats.
	hbox.add_theme_constant_override("separation", 2)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Left: portrait area — a Panel whose bg is painted per-variant by
	# _refresh_portrait_bg (light parchment behind dark variants, dark behind
	# bright variants). Sprite + ASCII holders anchor full-rect inside.
	_player_portrait_bg = Panel.new()
	_player_portrait_bg.custom_minimum_size = Vector2(COMPACT_PLAYER_PORTRAIT_W, COMPACT_PORTRAIT_H)
	_player_portrait_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_player_portrait_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_player_portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Initial stylebox — gets repainted in set_player_ascii_art based on
	# variant brightness. Use the box bg as default so no visible frame.
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(0.06, 0.05, 0.10, 0.0)
	_player_portrait_bg.add_theme_stylebox_override("panel", pbg)
	hbox.add_child(_player_portrait_bg)

	var sprite_holder = _create_player_sprite_holder()
	sprite_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	if _player_sprite_rect:
		_player_sprite_rect.custom_minimum_size = Vector2(COMPACT_PLAYER_PORTRAIT_W - 4, COMPACT_PORTRAIT_H - 4)
	_player_portrait_bg.add_child(sprite_holder)

	var ascii_holder = _create_player_ascii_holder()
	ascii_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	if _player_ascii_holder:
		_player_ascii_holder.size = Vector2(COMPACT_PLAYER_PORTRAIT_W, COMPACT_PORTRAIT_H)
	_player_portrait_bg.add_child(ascii_holder)

	# Right: stats column — name on top, HP bar beneath, deck info last.
	# v0.9.388 — SHRINK_CENTER, fixed-width bars (no stretchy long bars).
	# v0.9.405 — captured as _lufia_player_stats so start_action_phase can
	# fade ONLY the stats (portrait stays visible on the battlefield).
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 3)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(stats)
	_lufia_player_stats = stats

	var name_label = _create_player_name_label()
	name_label.custom_minimum_size = Vector2(COMPACT_BAR_W + 60, 0)
	stats.add_child(name_label)

	# HP row: fixed-width bar + "HP cur / max" text.
	var hp_row := HBoxContainer.new()
	hp_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hp_row.add_theme_constant_override("separation", 6)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(hp_row)
	_lufia_player_hp_bar = _make_hp_bar(Color("#FF4444"))
	_lufia_player_hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lufia_player_hp_bar.custom_minimum_size = Vector2(COMPACT_BAR_W, 10)
	hp_row.add_child(_lufia_player_hp_bar)
	_lufia_player_hp_text = Label.new()
	_lufia_player_hp_text.add_theme_font_size_override("font_size", 11)
	_lufia_player_hp_text.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_lufia_player_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lufia_player_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(_lufia_player_hp_text)

	# Deck info: "Deck N · Hand M · Discard K"
	_lufia_player_deck_label = Label.new()
	_lufia_player_deck_label.add_theme_font_size_override("font_size", 11)
	_lufia_player_deck_label.add_theme_color_override("font_color", Color(0.82, 0.78, 0.55))
	_lufia_player_deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lufia_player_deck_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(_lufia_player_deck_label)
	return hbox


func _build_lufia_companion_box_content() -> HBoxContainer:
	"""Lufia stat box for the companion: portrait LEFT, name + XP + HP
	bars stacked on the RIGHT (bars BESIDE the portrait, not above it).
	v0.9.388 — content-sized box, wider portrait (so Minotaur ~150-wide
	ASCII fits at font_size 1), fixed-width bars (no stretching)."""
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# v0.9.390 — tightened from 8 to 2 to remove dead space between portrait
	# and stats.
	hbox.add_theme_constant_override("separation", 2)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Left: companion portrait bg + art inside, same pattern as the player box.
	_companion_portrait_bg = Panel.new()
	_companion_portrait_bg.custom_minimum_size = Vector2(COMPACT_PORTRAIT_W, COMPACT_PORTRAIT_H)
	_companion_portrait_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_companion_portrait_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_companion_portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(0.06, 0.05, 0.10, 0.0)
	_companion_portrait_bg.add_theme_stylebox_override("panel", cbg)
	hbox.add_child(_companion_portrait_bg)

	var art = _create_companion_art_label()
	art.fit_content = false
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_companion_portrait_bg.add_child(art)

	# Right: stats column — name on top, fixed-width XP bar, HP bar.
	# v0.9.405 — captured as _lufia_companion_stats for action-phase fade.
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 2)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(stats)
	_lufia_companion_stats = stats

	var name_label = _create_companion_name_label()
	name_label.add_theme_font_size_override("normal_font_size", 11)
	name_label.custom_minimum_size = Vector2(COMPACT_BAR_W + 60, 0)
	stats.add_child(name_label)

	# Constrain the HP / XP rows so the bars don't stretch — they share the
	# same compact width as the player box.
	# v0.9.389 — HP first (top), XP below (matches the player box's HP-then-
	# resource-info order; user feedback request).
	var hp_row = _create_companion_hp_row()
	_constrain_companion_bar_row(hp_row)
	stats.add_child(hp_row)
	var xp_row = _create_companion_xp_row()
	_constrain_companion_bar_row(xp_row)
	stats.add_child(xp_row)

	# Populate code expects _companion_section to exist. Use the HBox itself.
	_companion_section = hbox
	return hbox


func _constrain_companion_bar_row(row: HBoxContainer) -> void:
	"""v0.9.388 — replace SIZE_EXPAND_FILL on the bar (first child) of a
	companion xp/hp row with a fixed COMPACT_BAR_W width so the bar doesn't
	stretch across the screen in the Lufia layout.
	v0.9.395 — row left-anchored (was centered) so HP and XP bars line up
	vertically at the same X within the stats VBox. Previously each row
	centered independently, so different trailing-text widths shifted the
	bars to different X positions."""
	if row == null or not is_instance_valid(row):
		return
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for child in row.get_children():
		if child is ProgressBar:
			(child as ProgressBar).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			(child as ProgressBar).custom_minimum_size = Vector2(COMPACT_BAR_W, 10)
		elif child is Label:
			(child as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			(child as Label).custom_minimum_size = Vector2(0, 0)


func _build_player_column() -> VBoxContainer:
	"""Standard-layout player column. Build helpers below produce the same
	controls regardless of layout; this just arranges them in the existing
	player-left arrangement (player_name top, battle_row[companion, player]
	just above the shared HP strip)."""
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Player name at the top of the column.
	col.add_child(_create_player_name_label())

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

	battle_row.add_child(_create_companion_block())
	battle_row.add_child(_create_player_sprite_holder())
	battle_row.add_child(_create_player_ascii_holder())

	return col


# v0.9.380 — control-creation helpers. Each sets the relevant instance
# variables and returns the root Control of that piece. The standard layout
# composes them in horizontal player/monster split; the chrono layout
# composes them in monster-top + party-bottom arrangement.

func _create_player_name_label() -> RichTextLabel:
	_player_name_label = RichTextLabel.new()
	_player_name_label.bbcode_enabled = true
	_player_name_label.fit_content = true
	_player_name_label.scroll_active = false
	_player_name_label.add_theme_font_size_override("normal_font_size", 14)
	_player_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _player_name_label


func _create_companion_block() -> VBoxContainer:
	"""Standard-layout companion block: name on top, XP bar, HP bar, then
	the companion ASCII art at the bottom. v0.9.383 — body refactored into
	atomic helpers so chrono/lufia layouts can arrange the same controls
	differently (e.g., portrait-left + stats-right inside a stat box)."""
	_companion_section = VBoxContainer.new()
	_companion_section.add_theme_constant_override("separation", 2)
	_companion_section.size_flags_vertical = Control.SIZE_SHRINK_END
	_companion_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_companion_section.add_child(_create_companion_name_label())
	_companion_section.add_child(_create_companion_xp_row())
	_companion_section.add_child(_create_companion_hp_row())
	_companion_section.add_child(_create_companion_art_label())
	return _companion_section


func _create_companion_name_label() -> RichTextLabel:
	_companion_name_label = RichTextLabel.new()
	_companion_name_label.bbcode_enabled = true
	_companion_name_label.fit_content = true
	_companion_name_label.scroll_active = false
	_companion_name_label.add_theme_font_size_override("normal_font_size", 12)
	_companion_name_label.custom_minimum_size = Vector2(180, 0)
	_companion_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _companion_name_label


func _create_companion_xp_row() -> HBoxContainer:
	# Tiny XP bar + text. Mirrors the player's level-progress affordance.
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 4)
	xp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_companion_xp_bar = ProgressBar.new()
	_companion_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_companion_xp_bar.custom_minimum_size = Vector2(0, 6)
	_companion_xp_bar.show_percentage = false
	var xp_bar_sb := StyleBoxFlat.new()
	xp_bar_sb.bg_color = Color(0.1, 0.1, 0.12)
	xp_bar_sb.border_color = Color(0.25, 0.22, 0.18)
	xp_bar_sb.set_border_width_all(1)
	xp_bar_sb.set_corner_radius_all(2)
	_companion_xp_bar.add_theme_stylebox_override("background", xp_bar_sb)
	var xp_fill_sb := StyleBoxFlat.new()
	xp_fill_sb.bg_color = Color("#3DD9FF")
	xp_fill_sb.set_corner_radius_all(2)
	_companion_xp_bar.add_theme_stylebox_override("fill", xp_fill_sb)
	_companion_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_row.add_child(_companion_xp_bar)

	_companion_xp_text = Label.new()
	_companion_xp_text.add_theme_font_size_override("font_size", 10)
	_companion_xp_text.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	_companion_xp_text.custom_minimum_size = Vector2(72, 0)
	_companion_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_companion_xp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_row.add_child(_companion_xp_text)
	return xp_row


func _create_companion_hp_row() -> HBoxContainer:
	# Phase B1 — Companion HP bar. Persistent across fights.
	_companion_hp_row = HBoxContainer.new()
	_companion_hp_row.add_theme_constant_override("separation", 4)
	_companion_hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_companion_hp_bar = ProgressBar.new()
	_companion_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_companion_hp_bar.custom_minimum_size = Vector2(0, 8)
	_companion_hp_bar.show_percentage = false
	var hp_bar_sb := StyleBoxFlat.new()
	hp_bar_sb.bg_color = Color(0.1, 0.05, 0.05)
	hp_bar_sb.border_color = Color(0.3, 0.15, 0.15)
	hp_bar_sb.set_border_width_all(1)
	hp_bar_sb.set_corner_radius_all(2)
	_companion_hp_bar.add_theme_stylebox_override("background", hp_bar_sb)
	var hp_fill_sb := StyleBoxFlat.new()
	hp_fill_sb.bg_color = Color("#FF4444")
	hp_fill_sb.set_corner_radius_all(2)
	_companion_hp_bar.add_theme_stylebox_override("fill", hp_fill_sb)
	_companion_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_companion_hp_row.add_child(_companion_hp_bar)

	_companion_hp_text = Label.new()
	_companion_hp_text.add_theme_font_size_override("font_size", 10)
	_companion_hp_text.add_theme_color_override("font_color", Color(0.95, 0.85, 0.85))
	_companion_hp_text.custom_minimum_size = Vector2(72, 0)
	_companion_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_companion_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_companion_hp_row.add_child(_companion_hp_text)
	return _companion_hp_row


func _create_companion_art_label() -> RichTextLabel:
	_companion_art = RichTextLabel.new()
	_companion_art.bbcode_enabled = true
	_companion_art.fit_content = true
	_companion_art.scroll_active = false
	_companion_art.autowrap_mode = TextServer.AUTOWRAP_OFF
	_companion_art.custom_minimum_size = Vector2(180, 150)
	_companion_art.clip_contents = true
	_companion_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# v0.9.410 — outline approach abandoned (see _create_player_ascii_holder).
	if _mono_font:
		_companion_art.add_theme_font_override("normal_font", _mono_font)
		_companion_art.add_theme_font_override("bold_font", _mono_font)
		_companion_art.add_theme_font_override("italics_font", _mono_font)
		_companion_art.add_theme_font_override("mono_font", _mono_font)
	return _companion_art


func _create_player_sprite_holder() -> CenterContainer:
	# Player PNG sprite holder. Used when there's no ASCII art for the class.
	_player_sprite_holder = CenterContainer.new()
	_player_sprite_holder.custom_minimum_size = Vector2(168, 168)
	_player_sprite_holder.size_flags_vertical = Control.SIZE_SHRINK_END
	_player_sprite_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	return _player_sprite_holder


func _create_player_ascii_holder() -> Control:
	# Player ASCII battle art. Wrapped in a plain Control so the FX-target
	# Panel inside has free-floating position (unaffected by HBox re-layouts
	# when the companion text changes). The wrapper itself is the layout
	# child; the Panel inside is what lunge / shake / death-slump tweens
	# animate.
	_ascii_outer = Control.new()
	_ascii_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ascii_outer.size_flags_vertical = Control.SIZE_SHRINK_END
	_ascii_outer.custom_minimum_size = Vector2(180, 260)
	_ascii_outer.clip_contents = true
	_ascii_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ascii_outer.visible = false
	_ascii_outer.resized.connect(_sync_ascii_holder_size)

	_player_ascii_holder = Panel.new()
	var ascii_sb := StyleBoxFlat.new()
	ascii_sb.bg_color = Color(0, 0, 0, 0)
	_player_ascii_holder.add_theme_stylebox_override("panel", ascii_sb)
	_player_ascii_holder.position = Vector2.ZERO
	_player_ascii_holder.size = Vector2(180, 260)
	_player_ascii_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ascii_outer.add_child(_player_ascii_holder)

	_player_ascii_label = RichTextLabel.new()
	_player_ascii_label.bbcode_enabled = true
	_player_ascii_label.fit_content = false
	_player_ascii_label.scroll_active = false
	_player_ascii_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_ascii_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_player_ascii_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# v0.9.410 — outline approach abandoned. Even 1px halo at font_size 2
	# blurred glyph detail into a glow. Reverted to no outline; visibility
	# now comes from the neutral dark-gray box bg (see _build_lufia_party_box).
	if _mono_font:
		_player_ascii_label.add_theme_font_override("normal_font", _mono_font)
		_player_ascii_label.add_theme_font_override("bold_font", _mono_font)
		_player_ascii_label.add_theme_font_override("italics_font", _mono_font)
		_player_ascii_label.add_theme_font_override("mono_font", _mono_font)
	_player_ascii_holder.add_child(_player_ascii_label)

	return _ascii_outer


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

	# v0.9.390 — Lufia prepends a bordered HP strip ABOVE the name/art so the
	# monster's HP is visible at the top of the scene (where the player's
	# attention is for combat). Standard / chrono keep HP in the shared strip.
	if combat_layout == LAYOUT_LUFIA:
		col.add_child(_build_lufia_monster_hp_panel())

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


func _build_shared_status_strip() -> HBoxContainer:
	"""Tag-colored row showing active buffs / debuffs / DoT timers under each
	combatant's HP bar. Mirrors the HP-strip layout (player on left, monster
	on right) so the eye stays anchored to the same vertical column."""
	_status_strip = HBoxContainer.new()
	_status_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_strip.add_theme_constant_override("separation", 12)
	_status_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_strip.custom_minimum_size = Vector2(0, 18)

	_player_status_label = RichTextLabel.new()
	_player_status_label.bbcode_enabled = true
	_player_status_label.fit_content = true
	_player_status_label.scroll_active = false
	_player_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_status_label.size_flags_stretch_ratio = 1.0
	_player_status_label.add_theme_font_size_override("normal_font_size", 11)
	_player_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_strip.add_child(_player_status_label)

	_monster_status_label = RichTextLabel.new()
	_monster_status_label.bbcode_enabled = true
	_monster_status_label.fit_content = true
	_monster_status_label.scroll_active = false
	_monster_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_monster_status_label.size_flags_stretch_ratio = 1.0
	_monster_status_label.add_theme_font_size_override("normal_font_size", 11)
	_monster_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_strip.add_child(_monster_status_label)

	return _status_strip


# Status-effect tag definitions. Map server status keys to (label, color).
const _STATUS_TAGS := {
	"bleed":      {"label": "Bld",  "color": "#FF4444"},
	"poison":     {"label": "Psn",  "color": "#66FF66"},
	"blind":      {"label": "Bln",  "color": "#888888"},
	"stun":       {"label": "Stn",  "color": "#FFD700"},
	"charm":      {"label": "Chrm", "color": "#FF69B4"},
	"weakness":   {"label": "Wkn",  "color": "#A0A0A0"},
	"slow":       {"label": "Slw",  "color": "#6699FF"},
	"haste":      {"label": "Hst",  "color": "#33CCFF"},
	"fortify":    {"label": "Frt",  "color": "#AAAAFF"},
	"iron_skin":  {"label": "IS",   "color": "#CCCCCC"},
	"war_cry":    {"label": "WC",   "color": "#FFAA33"},
	"berserk":    {"label": "Brsk", "color": "#FF6633"},
	"speed":      {"label": "Spd",  "color": "#33CCFF"},
	"strength":   {"label": "Str+", "color": "#FFAA33"},
	"defense":    {"label": "Def+", "color": "#AAAAFF"},
	"cloak":      {"label": "Cl",   "color": "#9999AA"},
	"forcefield": {"label": "FF",   "color": "#AA66FF"},
	"vampiric":   {"label": "Vmp",  "color": "#CC33CC"},
}

func _format_status_chip(key: String, suffix: String) -> String:
	var tag: Dictionary = _STATUS_TAGS.get(key, {"label": key.substr(0, 3).capitalize(), "color": "#CCCCCC"})
	if suffix == "":
		return "[color=%s]%s[/color]" % [tag.color, tag.label]
	return "[color=%s]%s %s[/color]" % [tag.color, tag.label, suffix]

func update_combat_status(player_status: Dictionary, monster_status: Dictionary) -> void:
	"""Refresh the status strip from the server's combat_state. Called every
	combat_update. Empty side becomes blank — strip stays in place so layout
	doesn't jump."""
	if _player_status_label == null or not is_instance_valid(_player_status_label):
		return
	_player_status_label.text = _build_player_status_bbcode(player_status)
	_monster_status_label.text = _build_monster_status_bbcode(monster_status)

func _build_player_status_bbcode(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	var chips: Array = []
	# DoTs (red-tinted, with damage-per-tick × turns or just turns).
	var poison_turns: int = int(s.get("poison_turns", 0))
	if poison_turns > 0:
		var pdmg: int = int(s.get("poison_damage", 0))
		chips.append(_format_status_chip("poison", "%dx%dT" % [pdmg, poison_turns]))
	var blind_turns: int = int(s.get("blind_turns", 0))
	if blind_turns > 0:
		chips.append(_format_status_chip("blind", "%dT" % blind_turns))
	# Forcefield shield amount (capacity, not turns).
	var ff_shield: int = int(s.get("forcefield_shield", 0))
	if ff_shield > 0:
		chips.append(_format_status_chip("forcefield", "%d" % ff_shield))
	# Cloak — no duration; on/off.
	if bool(s.get("cloak", false)):
		chips.append(_format_status_chip("cloak", ""))
	# Generic active_buffs (haste, fortify, iron_skin, war_cry, berserk,
	# strength, defense, speed, vampiric, etc.). Server passes an array of
	# {type, value, duration} dicts.
	var buffs = s.get("buffs", [])
	if buffs is Array:
		for b in buffs:
			if not (b is Dictionary):
				continue
			var btype: String = str(b.get("type", "")).to_lower()
			var bdur: int = int(b.get("duration", 0))
			if btype == "" or bdur <= 0:
				continue
			chips.append(_format_status_chip(btype, "%dT" % bdur))
	return "  ".join(chips)

func _build_monster_status_bbcode(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	var chips: Array = []
	var bleed_turns: int = int(s.get("bleed_turns", 0))
	if bleed_turns > 0:
		var bdmg: int = int(s.get("bleed_damage", 0))
		chips.append(_format_status_chip("bleed", "%dx%dT" % [bdmg, bleed_turns]))
	var poison_turns: int = int(s.get("poison_turns", 0))
	if poison_turns > 0:
		var pdmg: int = int(s.get("poison_damage", 0))
		chips.append(_format_status_chip("poison", "%dx%dT" % [pdmg, poison_turns]))
	var stun_turns: int = int(s.get("stun_turns", 0))
	if stun_turns > 0:
		chips.append(_format_status_chip("stun", "%dT" % stun_turns))
	var charm_turns: int = int(s.get("charm_turns", 0))
	if charm_turns > 0:
		chips.append(_format_status_chip("charm", "%dT" % charm_turns))
	var weakness_turns: int = int(s.get("weakness_turns", 0))
	if weakness_turns > 0:
		var wval: int = int(s.get("weakness_value", 0))
		chips.append(_format_status_chip("weakness", "-%d%% %dT" % [wval, weakness_turns]))
	var slow_turns: int = int(s.get("slow_turns", 0))
	if slow_turns > 0:
		var sval: int = int(s.get("slow_value", 0))
		chips.append(_format_status_chip("slow", "-%d%% %dT" % [sval, slow_turns]))
	if chips.is_empty():
		return ""
	# Right-align so the chips read from the inside edge inward, matching the
	# monster HP-text alignment above.
	return "[right]%s[/right]" % "  ".join(chips)


func _build_running_totals_strip() -> Control:
	"""Three actor boxes in a row showing fight-wide damage totals. Each
	box pairs a prefix label ("You:" / "Pet:" / "Foe:") with the number
	in a contrasting color so the digit pops.

	v0.9.270 — wrapped the strip in a bordered PanelContainer with much
	larger fonts (was 12pt, now 20pt) so the running totals draw the eye
	at a glance. Player feedback: previous totals were easy to miss in
	the bottom of the scene above the cards."""
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.06, 0.85)
	sb.border_color = Color(0.78, 0.65, 0.42, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	frame.add_theme_stylebox_override("panel", sb)

	_totals_strip = HBoxContainer.new()
	_totals_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_totals_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_totals_strip.add_theme_constant_override("separation", 36)
	_totals_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_totals_strip)

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

	return frame


func _make_total_box(prefix: String, prefix_color: Color, number_color: Color) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var prefix_label := Label.new()
	prefix_label.name = "Prefix"
	prefix_label.text = prefix
	prefix_label.add_theme_font_size_override("font_size", 20)
	prefix_label.add_theme_color_override("font_color", prefix_color)
	prefix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(prefix_label)

	var number_label := Label.new()
	number_label.name = "Number"
	number_label.text = "0"
	number_label.add_theme_font_size_override("font_size", 22)
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


# === Audit #1 Slice 6a — hand strip ============================================

func _build_hand_strip() -> HBoxContainer:
	"""Five card cells + a deck/discard status counter. Each card is a
	clickable PanelContainer. Empty hand (combat just ended, or all cards
	exhausted with empty discard) renders as 5 dim '—' cells.

	Layout: [Card 1][Card 2][Card 3][Card 4][Card 5]   Deck N · Discard M"""
	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 12)
	outer.mouse_filter = Control.MOUSE_FILTER_PASS

	_hand_strip = HBoxContainer.new()
	_hand_strip.add_theme_constant_override("separation", 10)
	_hand_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(_hand_strip)

	_hand_cells.clear()
	for i in range(COMBAT_HAND_SIZE):
		var cell := _build_hand_cell(i)
		_hand_cells.append(cell)
		_hand_strip.add_child(cell)

	_hand_status_label = Label.new()
	_hand_status_label.text = ""
	_hand_status_label.add_theme_font_size_override("font_size", 11)
	_hand_status_label.add_theme_color_override("font_color", Color("#888888"))
	_hand_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(_hand_status_label)

	return outer


func _build_hand_cell(index: int) -> PanelContainer:
	"""Build a single 5-wide card cell. Card title row on top, cost row on
	bottom, mastery rank tag in the corner. Click sends card_played(name).
	Tooltip text is repopulated each refresh from client_ref._get_ability_tooltip
	so hover shows full effect / mastery / progress info matching the
	out-of-combat AbilityPanel."""
	var cell := PanelContainer.new()
	cell.name = "HandCell_%d" % index
	# Audit #1 Slice 6c — doubled card size for legibility. Player feedback:
	# cards were easy to miss at the old 108x54. Bumped to 190x108 (~3.3x area)
	# with proportionally larger fonts. Cards may now visually overlap the
	# scene_section above; that's intended — they should draw the eye.
	cell.custom_minimum_size = Vector2(190, 108)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.tooltip_text = ""

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.09, 0.92)
	sb.border_color = Color(0.55, 0.45, 0.30, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	cell.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(vbox)

	# Top row: hotkey number + ability name
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var key_label := Label.new()
	key_label.name = "Key"
	key_label.text = "%d" % (index + 1)
	key_label.add_theme_font_size_override("font_size", 16)
	key_label.add_theme_color_override("font_color", Color("#FFD700"))
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(key_label)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = "—"
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", Color("#DDDDDD"))
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(name_label)

	# Middle row: cost + rank
	var middle_row := HBoxContainer.new()
	middle_row.add_theme_constant_override("separation", 8)
	middle_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(middle_row)

	var cost_label := Label.new()
	cost_label.name = "Cost"
	cost_label.text = ""
	cost_label.add_theme_font_size_override("font_size", 14)
	cost_label.add_theme_color_override("font_color", Color("#9ACD32"))
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle_row.add_child(cost_label)

	var rank_label := Label.new()
	rank_label.name = "Rank"
	rank_label.text = ""
	rank_label.add_theme_font_size_override("font_size", 13)
	rank_label.add_theme_color_override("font_color", Color("#888888"))
	rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle_row.add_child(rank_label)

	# Bottom row: effect estimate (damage / buff magnitude / chance).
	# Single label that fills the row; populated by _refresh_hand from the
	# client's _estimate_ability_card_effect helper so the panel doesn't have
	# to know per-ability formulas.
	var effect_label := Label.new()
	effect_label.name = "Effect"
	effect_label.text = ""
	effect_label.add_theme_font_size_override("font_size", 13)
	effect_label.add_theme_color_override("font_color", Color("#FFA060"))
	effect_label.clip_text = true
	effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(effect_label)

	# Click handler — pulls the current card name from meta on click.
	cell.gui_input.connect(_on_hand_cell_input.bind(index))
	cell.set_meta("card_name", "")
	cell.set_meta("can_afford", false)
	return cell


func _on_hand_cell_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if index < 0 or index >= _hand_cells.size():
			return
		var cell: PanelContainer = _hand_cells[index]
		var card_name = str(cell.get_meta("card_name", ""))
		if card_name == "":
			return
		# Affordability is enforced server-side too; we just save the click
		# round-trip when we already know it'll bounce.
		if not bool(cell.get_meta("can_afford", true)):
			return
		emit_signal("card_played", card_name)


func update_hand(hand: Array, deck_count: int, discard_count: int) -> void:
	"""Replace current hand state and rerender the strip. `hand` is an array
	of canonical ability names (e.g. 'magic_bolt'). Cell metadata reads
	display name / cost / resource type / mastery rank from client_ref so
	this panel doesn't have to duplicate the ability tables."""
	_combat_hand = hand.duplicate() if hand is Array else []
	_combat_deck_count = max(0, deck_count)
	_combat_discard_count = max(0, discard_count)
	if is_inside_tree():
		_refresh_hand()


func _refresh_hand() -> void:
	if _hand_cells.is_empty():
		return
	for i in range(_hand_cells.size()):
		var cell: PanelContainer = _hand_cells[i]
		var vbox = cell.get_node("VBox")
		var top_row = vbox.get_child(0)
		var middle_row = vbox.get_child(1)
		var key_lbl: Label = top_row.get_child(0)
		var name_lbl: Label = top_row.get_child(1)
		var cost_lbl: Label = middle_row.get_child(0)
		var rank_lbl: Label = middle_row.get_child(1)
		var effect_lbl: Label = vbox.get_child(2)

		# Hotkey label reads the live keybind for the action-bar slot this
		# card sits at. Cards 0-4 land at action_5..action_9 (default keys
		# 1-5), but the user can rebind those — pull the actual label from
		# the client so a player who remapped action_5 to Z sees "Z" here.
		var slot_index = i + 5
		var key_text = "%d" % (i + 1)
		if client_ref and client_ref.has_method("get_action_key_name"):
			var pulled = str(client_ref.get_action_key_name(slot_index))
			if pulled != "":
				key_text = pulled
		key_lbl.text = key_text

		if i >= _combat_hand.size():
			# Empty slot
			cell.set_meta("card_name", "")
			cell.set_meta("can_afford", false)
			name_lbl.text = "—"
			name_lbl.add_theme_color_override("font_color", Color("#444444"))
			key_lbl.add_theme_color_override("font_color", Color("#444444"))
			cost_lbl.text = ""
			rank_lbl.text = ""
			effect_lbl.text = ""
			cell.tooltip_text = ""
			_set_cell_dim(cell, true, false)
			continue

		var card_name = str(_combat_hand[i])
		var info = _resolve_card_info(card_name)
		cell.set_meta("card_name", card_name)
		cell.set_meta("can_afford", bool(info.get("can_afford", true)))

		name_lbl.text = str(info.get("display", card_name))
		name_lbl.add_theme_color_override("font_color", Color("#DDDDDD"))
		key_lbl.add_theme_color_override("font_color", Color("#FFD700"))

		# Hover tooltip — full ability detail (effect, cost, mastery rank,
		# progress to next rank). Mirrors the AbilityPanel hover so players
		# get the same information surface in and out of combat.
		if client_ref and client_ref.has_method("_get_ability_tooltip"):
			cell.tooltip_text = str(client_ref._get_ability_tooltip(card_name))
		else:
			cell.tooltip_text = str(info.get("display", card_name))

		# Show the single amount that will actually be spent if the card is
		# triggered now (mirrors server's auto-cast / Magic Bolt smart suggest).
		var planned_int = int(info.get("planned_cost", 0))
		var resource_type = str(info.get("resource_type", ""))
		if planned_int > 0 and resource_type != "":
			cost_lbl.text = "%d %s" % [planned_int, _short_resource_label(resource_type)]
			cost_lbl.add_theme_color_override("font_color", _resource_color(resource_type))
		else:
			cost_lbl.text = "Free"
			cost_lbl.add_theme_color_override("font_color", Color("#888888"))

		var rank = int(info.get("rank", 0))
		if rank >= 0 and rank < HAND_RANK_NAMES.size():
			var remaining = int(info.get("rank_uses_remaining", 0))
			var at_max = bool(info.get("rank_at_max", false))
			if at_max:
				rank_lbl.text = "R%d ★" % rank
			elif remaining > 0:
				rank_lbl.text = "R%d +%d" % [rank, remaining]
			else:
				rank_lbl.text = "R%d" % rank
			rank_lbl.add_theme_color_override("font_color", Color(HAND_RANK_COLORS[rank]))
		else:
			rank_lbl.text = ""

		var effect_text = str(info.get("effect_text", ""))
		var effect_color = str(info.get("effect_color", "#FFA060"))
		effect_lbl.text = effect_text
		effect_lbl.add_theme_color_override("font_color", Color(effect_color))

		_set_cell_dim(cell, false, bool(info.get("can_afford", true)))

	# Status line
	if _hand_status_label:
		_hand_status_label.text = "Deck %d  ·  Discard %d" % [_combat_deck_count, _combat_discard_count]
	# v0.9.385 — mirror deck / hand / discard into the Lufia in-box label.
	if _lufia_player_deck_label and is_instance_valid(_lufia_player_deck_label):
		var hand_size := _combat_hand.size()
		_lufia_player_deck_label.text = "Deck %d · Hand %d · Discard %d" % [_combat_deck_count, hand_size, _combat_discard_count]


func _set_cell_dim(cell: PanelContainer, empty: bool, can_afford: bool) -> void:
	"""Adjust cell border/bg to convey state. Empty = very muted; uncastable
	= mid muted; castable = active gold border."""
	var sb := cell.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	if empty:
		sb.border_color = Color(0.20, 0.18, 0.14, 1)
		sb.bg_color = Color(0.04, 0.04, 0.05, 0.85)
	elif not can_afford:
		sb.border_color = Color(0.35, 0.25, 0.20, 1)
		sb.bg_color = Color(0.06, 0.05, 0.06, 0.92)
	else:
		sb.border_color = Color(0.70, 0.55, 0.30, 1)
		sb.bg_color = Color(0.08, 0.07, 0.05, 0.95)


func _resolve_card_info(card_name: String) -> Dictionary:
	"""Pull display / cost / resource_type / rank / can_afford from client_ref.
	Returns a dict with safe defaults when client_ref or its helpers aren't
	available (e.g. if the panel is rendered outside a live client)."""
	var info := {"display": card_name.replace("_", " ").capitalize(), "cost": 0, "cost_floor": 0, "planned_cost": 0, "fraction": 1.0, "resource_type": "", "rank": 0, "can_afford": true, "effect_text": "", "effect_color": "#FFA060"}
	if client_ref == null:
		return info
	var path = ""
	if client_ref.has_method("_get_player_active_path"):
		path = client_ref._get_player_active_path()
	if client_ref.has_method("_get_ability_combat_info"):
		var ability_info = client_ref._get_ability_combat_info(card_name, path)
		if ability_info is Dictionary and not ability_info.is_empty():
			info["display"] = str(ability_info.get("display", info["display"]))
			info["cost"] = int(ability_info.get("cost", 0))
			# Slice 6c — variable-cost abilities carry a floor; cards light up if
			# you can afford the floor, even when below the ceiling.
			info["cost_floor"] = int(ability_info.get("cost_floor", 0))
			info["resource_type"] = str(ability_info.get("resource_type", ""))
	# Audit #1 follow-up — show single planned spend + effect estimate so the
	# card answers "how much will this cost me, and what will I get?" without
	# requiring the player to read the range and do mental math.
	if client_ref.has_method("_get_ability_planned_spend"):
		var spend = client_ref._get_ability_planned_spend(card_name)
		if spend is Dictionary:
			info["planned_cost"] = int(spend.get("amount", 0))
			info["fraction"] = float(spend.get("fraction", 1.0))
			if str(spend.get("resource_type", "")) != "":
				info["resource_type"] = str(spend.get("resource_type", ""))
	if client_ref.has_method("_estimate_ability_card_effect"):
		var eff = client_ref._estimate_ability_card_effect(card_name, int(info.get("planned_cost", 0)), float(info.get("fraction", 1.0)))
		if eff is Dictionary:
			info["effect_text"] = str(eff.get("text", ""))
			info["effect_color"] = str(eff.get("color", "#FFA060"))
	# Mastery progress — uses needed before the ability's next rank-up. Renders
	# inline with the rank tag so the card answers "how close am I to ranking
	# this up?" at a glance.
	if client_ref.has_method("_get_ability_rank_progress"):
		var prog = client_ref._get_ability_rank_progress(card_name)
		if prog is Dictionary:
			info["rank_uses_remaining"] = int(prog.get("uses_remaining", 0))
			info["rank_at_max"] = bool(prog.get("at_max", false))
	# Mastery rank from ability_uses dict (mirrors AbilityPanel logic).
	if "character_data" in client_ref:
		var char_data = client_ref.character_data
		if char_data is Dictionary:
			var uses_dict = char_data.get("ability_uses", {})
			var uses = int(uses_dict.get(card_name, 0)) if uses_dict is Dictionary else 0
			info["rank"] = _rank_from_uses(uses)
	# Affordability: compare cost to current resource on character_data.
	var current_mana = 0
	var current_stamina = 0
	var current_energy = 0
	if "character_data" in client_ref and client_ref.character_data is Dictionary:
		current_mana = int(client_ref.character_data.get("current_mana", 0))
		current_stamina = int(client_ref.character_data.get("current_stamina", 0))
		current_energy = int(client_ref.character_data.get("current_energy", 0))
	var cost = int(info.get("cost", 0))
	var cost_floor = int(info.get("cost_floor", 0))
	# For variable-cost abilities, the affordability threshold is the floor;
	# for fixed-cost abilities, it's the full cost.
	var affordability_threshold = cost_floor if cost_floor > 0 else cost
	var rt = str(info.get("resource_type", ""))
	var can_afford = true
	if affordability_threshold > 0:
		match rt:
			"mana":
				can_afford = current_mana >= affordability_threshold
			"stamina":
				can_afford = current_stamina >= affordability_threshold
			"energy":
				can_afford = current_energy >= affordability_threshold
	info["can_afford"] = can_afford
	return info


func _rank_from_uses(uses: int) -> int:
	# Mirrors MASTERY_RANK_THRESHOLDS = [30, 150, 600, 2400].
	var thresholds = [30, 150, 600, 2400]
	var rank = 0
	for t in thresholds:
		if uses >= int(t):
			rank += 1
		else:
			break
	return rank


func _short_resource_label(rt: String) -> String:
	match rt:
		"mana": return "MP"
		"stamina": return "SP"
		"energy": return "EN"
	return ""


func _resource_color(rt: String) -> Color:
	match rt:
		"mana": return Color("#7AA8FF")
		"stamina": return Color("#FFB860")
		"energy": return Color("#A0E060")
	return Color("#888888")


func clear_hand() -> void:
	"""Wipe hand state to '—' cells (called between fights / when combat ends)."""
	_combat_hand = []
	_combat_deck_count = 0
	_combat_discard_count = 0
	if is_inside_tree():
		_refresh_hand()


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
	if payload.has("player_appearance_color"):
		_player_appearance_color = str(payload["player_appearance_color"])
	if payload.has("player_appearance_color2"):
		_player_appearance_color2 = str(payload["player_appearance_color2"])
	if payload.has("player_appearance_pattern"):
		_player_appearance_pattern = str(payload["player_appearance_pattern"])
	if payload.has("player_hp"):
		_player_hp = int(payload["player_hp"])
	if payload.has("player_max_hp"):
		_player_max_hp = maxi(1, int(payload["player_max_hp"]))
	# v0.9.415 — resource (MP/SP/Energy) for the overlay bar.
	if payload.has("player_resource_cur"):
		_player_resource_cur = int(payload["player_resource_cur"])
	if payload.has("player_resource_max"):
		_player_resource_max = maxi(1, int(payload["player_resource_max"]))
	if payload.has("player_resource_color"):
		_player_resource_color = Color(str(payload["player_resource_color"]))
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
	_damage_label_stack_y = 0.0
	_damage_label_last_spawn_ts = -10.0
	reset_running_totals()
	# v0.9.403/406 — reset action-phase state so a fresh fight starts with
	# party row fully visible and the battlefield overlay hidden.
	_action_phase_active = false
	_kill_action_phase_tween()
	_cancel_action_phase_timer()
	# v0.9.415 — clear per-actor overlay logs so previous fight's lines don't
	# bleed into the new one.
	clear_overlay_logs()
	if _lufia_player_stats and is_instance_valid(_lufia_player_stats):
		_lufia_player_stats.modulate.a = 1.0
	if _lufia_companion_stats and is_instance_valid(_lufia_companion_stats):
		_lufia_companion_stats.modulate.a = 1.0
	if _player_col and is_instance_valid(_player_col):
		_player_col.modulate.a = 1.0
	if _battlefield_overlay and is_instance_valid(_battlefield_overlay):
		_battlefield_overlay.visible = false
		_battlefield_overlay.modulate.a = 0.0
	# v0.9.414 — restore the UI strips that start_action_phase hid (totals
	# banner, hand cards, status). If the player pressed Space to chain
	# into the next flock combat before end_action_phase fired, the strips
	# stayed hidden and the new fight had no visible ability cards.
	if _totals_strip and is_instance_valid(_totals_strip):
		_totals_strip.visible = true
	if _hand_strip and is_instance_valid(_hand_strip):
		_hand_strip.visible = true
	if _status_strip and is_instance_valid(_status_strip):
		_status_strip.visible = true

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
	# Clear any flock warning banner / victory card / death card left over
	# from the previous fight.
	hide_flock_warning()
	hide_victory_card()
	hide_death_card()
	# Status strip starts blank — first combat_update will populate it.
	update_combat_status({}, {})

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
	# v0.9.415 — during action_phase, also route to the per-actor overlay log
	# (classified from the line itself if no actor hint was passed).
	if _action_phase_active:
		# Round dividers broadcast to all 3 strips so each actor's log keeps
		# round boundaries.
		var round_n: int = _extract_round_number(bbcode_line)
		if round_n > 0:
			_push_round_divider_to_overlays(round_n)
		else:
			_route_to_overlay_log(bbcode_line, _classify_overlay_actor(bbcode_line))


func append_log_actor(actor: String, bbcode_line: String) -> void:
	"""v0.9.415 — explicit actor routing for the per-actor overlay logs.
	Use this instead of append_log when the caller already knows which actor
	the message belongs to (avoids the classifier heuristic). Falls back to
	append_log if action_phase isn't active."""
	if bbcode_line.strip_edges() == "":
		return
	_log_lines.append(bbcode_line)
	if _log_lines.size() > LOG_LINE_LIMIT:
		_log_lines = _log_lines.slice(_log_lines.size() - LOG_LINE_LIMIT)
	if is_inside_tree():
		_refresh_log()
	if _action_phase_active:
		_route_to_overlay_log(bbcode_line, actor)


func _route_to_overlay_log(bbcode_line: String, actor: String) -> void:
	"""Append the line to the matching overlay log strip + refresh it. Ambient
	(separators / DoT ticks / scene narration) routes to the player log so it
	always shows somewhere."""
	var target_lines: Array
	var target_label: RichTextLabel
	match actor:
		"companion":
			target_lines = _overlay_companion_log_lines
			target_label = _overlay_companion_log
		"monster":
			target_lines = _overlay_monster_log_lines
			target_label = _overlay_monster_log
		_:  # "player" or "ambient"
			target_lines = _overlay_player_log_lines
			target_label = _overlay_player_log
	target_lines.append(bbcode_line)
	if target_lines.size() > OVERLAY_LOG_LINE_LIMIT:
		target_lines.remove_at(0)
	# Re-assign in case match's local view doesn't share the same array reference.
	match actor:
		"companion":
			_overlay_companion_log_lines = target_lines
		"monster":
			_overlay_monster_log_lines = target_lines
		_:
			_overlay_player_log_lines = target_lines
	if target_label and is_instance_valid(target_label):
		target_label.text = "\n".join(target_lines)


func _classify_overlay_actor(raw: String) -> String:
	"""Identify which actor produced this combat line so we can route it to
	their overlay log. Returns 'player', 'companion', 'monster', or 'ambient'.

	v0.9.417 — three layers of detection, in order:
	  1. Condensed per-turn summary glyph prefixes (►/◆/✦) — these don't
	     contain attack verbs so the verb-check below would miss them.
	  2. Firehose enhancement markers (>> / << / ++) — _enhance_combat_message
	     in client.gd prepends '<<' to ANY 'The X ...' line so we can detect
	     the actor from a single marker regardless of the original prefix
	     color (handles #FF4444, #FF6600 ability variants, etc.).
	  3. Raw verb + actor-prefix fallback for non-enhanced lines."""
	var result := _classify_overlay_actor_inner(raw)
	# v0.9.418 — temporary diagnostic for Wyvern-attacks-companion routing bug.
	print("[STRIP-ROUTE] actor=%s | raw=%s" % [result, raw.left(160)])
	return result


func _strip_bbcode_and_whitespace(raw: String) -> String:
	"""Strip BBCode tags ([color=...], [pulse ...], [/...], etc.) and leading/
	trailing whitespace so begins_with checks see the actual text content."""
	var re := RegEx.new()
	re.compile("\\[/?[^\\]]+\\]")
	return re.sub(raw, "", true).strip_edges()


func _classify_overlay_actor_inner(raw: String) -> String:
	"""v0.9.417 — single-discriminator routing based on the server's own
	structural signal: process_monster_turn output is wrapped by
	_indent_multiline(msg, "         ") in combat_manager.gd (lines 1130,
	1252, 2610, 2790, 3670, 3824). Player ability side-effects (Magic Bolt's
	'The bolt strikes', Blast's 'The explosion deals') are emitted via plain
	messages.append with no indent.

	Rule: leading 5+ spaces of indent = monster-turn block. Otherwise classify
	by content prefix (Your → companion, You → player, else ambient).

	No more per-verb / per-ability heuristics."""
	# Condensed-summary glyph prefixes (still used by some buffer paths).
	if "►" in raw and "YOU" in raw:
		return "player"
	if "◆" in raw and "Your " in raw:
		return "companion"
	if "✦" in raw and "The " in raw:
		return "monster"
	# Count leading spaces — the structural signal for monster-turn blocks.
	var leading_ws: int = 0
	while leading_ws < raw.length() and raw[leading_ws] == " ":
		leading_ws += 1
	# Companion — two structural patterns the server emits:
	#   1. "Your <name> attacks/strikes/hits/misses/uses/lunges ..." (standard)
	#   2. "<name>'s <ability> ..." (companion abilities like Poison Bite —
	#      see combat_manager.gd:688)
	# Detect by checking for the companion's own name when populate() has set it.
	var comp_name: String = str(_companion_data.get("name", "")) if not _companion_data.is_empty() else ""
	if "Your " in raw:
		if " attacks" in raw or " strikes" in raw or " hits " in raw or " misses" in raw or " uses " in raw or " lunges" in raw:
			return "companion"
	if comp_name != "" and "%s's " % comp_name in raw:
		return "companion"
	# Enhancement markers explicitly tag player lines.
	if ">>" in raw or "++" in raw:
		return "player"
	var content: String = _strip_bbcode_and_whitespace(raw)
	# 'You' content prefix → player regardless of indent (covers indented
	# 'You gain N experience!' inside monster-turn blocks).
	if content.begins_with("You ") or content.begins_with("you "):
		return "player"
	# Damage-taken phrasing without 'The X' prefix.
	var content_lower: String = content.to_lower()
	if "damage to you" in content_lower or "smashes you" in content_lower:
		return "monster"
	# Indented 'The X' line → monster (came from process_monster_turn block).
	# Non-indented 'The X' line → ambient (player ability side-effect).
	if leading_ws >= 5 and (content.begins_with("The ") or content.begins_with("the ")):
		return "monster"
	return "ambient"


func _extract_round_number(raw: String) -> int:
	"""Detect the round divider line emitted by client.gd (format:
	'[color=...]──────── Round N ────────[/color]') and return N. Returns 0
	if no round number is present."""
	if not ("Round " in raw):
		return 0
	var re := RegEx.new()
	re.compile("Round\\s+(\\d+)")
	var m := re.search(raw)
	if m == null:
		return 0
	return int(m.get_string(1))


func _push_round_divider_to_overlays(round_n: int) -> void:
	"""Add a compact '── R<n> ──' marker to all 3 actor logs so each strip
	shows where round boundaries fall. Skipped if no logs exist."""
	var marker := "[color=#7A6845]── R%d ──[/color]" % round_n
	for entry in [
		[_overlay_player_log_lines, _overlay_player_log],
		[_overlay_monster_log_lines, _overlay_monster_log],
		[_overlay_companion_log_lines, _overlay_companion_log],
	]:
		var lines: Array = entry[0]
		var label: RichTextLabel = entry[1]
		lines.append(marker)
		if lines.size() > OVERLAY_LOG_LINE_LIMIT:
			lines.remove_at(0)
		if label and is_instance_valid(label):
			label.text = "\n".join(lines)
	# Mutate the actual member arrays (entry[0] above is a reference; the
	# append did mutate _overlay_*_log_lines in place since Arrays are
	# passed by reference in GDScript. Nothing further needed.)


func clear_overlay_logs() -> void:
	"""Reset the per-actor overlay logs. Called on fight start so previous
	fight's lines don't leak into the new one."""
	_overlay_player_log_lines.clear()
	_overlay_monster_log_lines.clear()
	_overlay_companion_log_lines.clear()
	if _overlay_player_log and is_instance_valid(_overlay_player_log):
		_overlay_player_log.text = ""
	if _overlay_monster_log and is_instance_valid(_overlay_monster_log):
		_overlay_monster_log.text = ""
	if _overlay_companion_log and is_instance_valid(_overlay_companion_log):
		_overlay_companion_log.text = ""


func clear_log(archive: bool = false) -> void:
	# When archive=true and there's a current log, snapshot it into _flock_history
	# so the [L] legacy view can replay prior fights from this flock chain.
	if archive and _log_lines.size() > 0 and _monster_name != "":
		_flock_history.append({
			"monster_name": _monster_name,
			"color": _monster_name_color,
			"level": _monster_level,
			"art": _monster_art_bbcode,
			"lines": _log_lines.duplicate(),
		})
		if _flock_history.size() > FLOCK_HISTORY_LIMIT:
			_flock_history = _flock_history.slice(_flock_history.size() - FLOCK_HISTORY_LIMIT)
	_log_lines.clear()
	if is_inside_tree():
		_refresh_log()


func reset_flock_history() -> void:
	_flock_history.clear()


func get_flock_history() -> Array:
	return _flock_history.duplicate()


func get_log_lines() -> Array:
	"""Return a copy of the panel's combat log so the [L] legacy view can
	replay it into game_output."""
	return _log_lines.duplicate()


func get_monster_header_bbcode() -> Array:
	"""Return [name_line, art_block] for the [L] legacy view header so the
	wall-of-text reopens with the monster name + ASCII art at the top, the
	way the old detail view used to render."""
	if _monster_name == "":
		return []
	var name_line := "[color=%s]%s[/color] [color=#FFD700]Lv %d[/color]" % [_monster_name_color, _monster_name, _monster_level]
	return [name_line, _monster_art_bbcode]


# === Internal rendering ===

func _refresh_portrait_bg(bg_panel: Panel, variant_color_hex: String) -> void:
	"""v0.9.410 — parchment bg paint abandoned. Per user feedback, the right
	fix was to darken / recolor the BOX bg, not the portrait bg. Kept as a
	no-op for call-site compatibility. See _build_lufia_party_box for the
	new neutral dark-gray box bg that gives every variant enough contrast."""
	if bg_panel == null or not is_instance_valid(bg_panel):
		return
	# Force the portrait bg fully transparent so the (now neutral-gray) box
	# bg shows through. No per-variant logic.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	bg_panel.add_theme_stylebox_override("panel", sb)
	bg_panel.queue_redraw()


func _apply_ascii_outline(label: RichTextLabel, fill_color_hex: String) -> void:
	"""v0.9.410 — outline approach abandoned. Kept as a no-op so existing
	call sites compile, but no outline is applied. Visibility now comes
	from the neutral dark-gray box bg (see _build_lufia_party_box) which
	gives every variant color enough contrast without modifying the ASCII."""
	pass


func _battle_lift_color(hex: String) -> String:
	"""v0.9.414 — battle ASCII lift bumped 0.18 → 0.35 toward white. Tactical
	view still felt dark vs FX overlay; this brings both to a clearly bright
	read while preserving variant hue."""
	if hex == null or hex == "":
		return hex
	var c: Color = Color(hex)
	var lifted: Color = c.lerp(Color.WHITE, 0.35)
	return "#" + lifted.to_html(false)


func _battle_brighten_color_hex(hex: String) -> String:
	"""v0.9.405 — aggressive lerp-toward-white for ASCII colors used in
	battle. The HSV value-floor approach in v0.9.404 wasn't enough for
	colors like Cobalt (low saturation + low value but the HSV V calc only
	measures the brightest channel). Lerp toward white blends WITHOUT
	losing hue, so Cobalt (#0047AB → ~#80A0DB) becomes a light-blue that
	reads on any dark bg, while bright variants (Gold, Ivory) untouched."""
	if hex == null or hex == "":
		return hex
	var c: Color = Color(hex)
	# Perceived brightness via luminance weights.
	var brightness: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	# Already bright enough? leave alone.
	if brightness >= 0.55:
		return hex
	# Lerp toward white. The darker the color, the more lift it gets,
	# capped at 0.55 so very-dark variants don't end up pure white.
	var lift: float = clampf((0.55 - brightness) * 1.4, 0.0, 0.55)
	var lifted: Color = c.lerp(Color.WHITE, lift)
	return "#" + lifted.to_html(false)


func _is_compact_layout() -> bool:
	"""v0.9.384 — chrono / lufia render the same battle ASCII as standard
	but at a tiny font size + clipped to a small portrait box. This helper
	centralizes the layout check (sizes and font sizes branch on it)."""
	return combat_layout != LAYOUT_STANDARD


const COMPACT_PORTRAIT_PX := 96  # v0.9.385 — square chrono party-row portrait size (px)
# v0.9.389 — Lufia portrait box bumped to fit the full ~75-line Minotaur ASCII
# (~200 tall at font_size 1 with the font's minimum line height). Box height
# dominates because monster art is taller than wide in our content; Barbarian
# class art is 100×55 chars which fits at font_size 2.
const COMPACT_PORTRAIT_W := 200  # v0.9.394 — back to 200 (240 was too much horizontal). [center] still helps when natural art is narrower.
const COMPACT_PORTRAIT_H := 180
# v0.9.392 — player portrait gets its own narrower width since player ASCII
# (~100 chars wide at font_size 2 ≈ ~120px rendered) was leaving ~80px of dead
# space on the right of the 200-wide portrait before the stat bars started.
const COMPACT_PLAYER_PORTRAIT_W := 140
const COMPACT_BAR_W := 120  # v0.9.388 — fixed-width bars (no EXPAND_FILL stretch)
const COMPACT_ASCII_FONT_SIZE := 1  # v0.9.385 — companion ASCII font_size in compact layouts
# v0.9.389 — player class ASCII uses a slightly larger font so the figure is
# legible. Player art is ~100 chars wide, so font 2 stays inside the 200px box.
const COMPACT_PLAYER_ASCII_FONT_SIZE := 2


func _refresh_player() -> void:
	# Class ASCII art takes priority over the PNG sprite when available.
	# Drop a file at `res://client/sprites/ascii/<Class>.txt` and it shows up
	# here automatically; classes without one fall back to the LPC PNG.
	var ascii_art = ClassAsciiArt.get_ascii_art(_player_class)
	if ascii_art != "":
		var fsize = ClassAsciiArt.get_font_size(_player_class)
		var col = ClassAsciiArt.get_color(_player_class)
		# Player appearance variant overrides the per-class default color when
		# set. For solid patterns we just swap the single color; for multi-
		# color patterns (gradient / striped / etc) we delegate to the same
		# pattern recolor helper companions use, via client_ref.
		if _player_appearance_color != "":
			col = _player_appearance_color
		# v0.9.412 — always brighten battle ASCII via _ensure_readable_color
		# (same transform used by map hover / player popup / status page).
		# v0.9.413 — extra battle lift on top (lerp 0.18 toward white) since
		# the tactical view still reads darker than the FX overlay for
		# subjective reasons (smaller font, more competing UI).
		var col2 = _player_appearance_color2
		if client_ref != null and client_ref.has_method("_ensure_readable_color"):
			if col != "":
				col = client_ref._ensure_readable_color(col)
			if col2 != "":
				col2 = client_ref._ensure_readable_color(col2)
		col = _battle_lift_color(col)
		if col2 != "":
			col2 = _battle_lift_color(col2)
		set_player_ascii_art(ascii_art, fsize, col, col2, _player_appearance_pattern)
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
	# v0.9.385 — mirror to the Lufia in-box HP widget when it exists.
	if _lufia_player_hp_bar and is_instance_valid(_lufia_player_hp_bar):
		_lufia_player_hp_bar.max_value = _player_max_hp
		_lufia_player_hp_bar.value = clampi(_player_hp, 0, _player_max_hp)
	if _lufia_player_hp_text and is_instance_valid(_lufia_player_hp_text):
		_lufia_player_hp_text.text = "HP %d / %d" % [maxi(0, _player_hp), _player_max_hp]


func update_companion_data(data: Dictionary) -> void:
	"""Refresh the companion section from a new active_companion dict —
	called from character_update so XP/level changes during combat reflect
	in the panel without re-running populate()."""
	if data == null:
		return
	_companion_data = data
	if is_inside_tree():
		_refresh_companion()


func update_companion_combat_hp(current_hp: int, max_hp: int, is_ko: bool) -> void:
	"""Phase B1 — refresh the companion HP bar from the latest combat_state.
	Hides the bar when current/max < 0 (legacy server / no active companion).
	Greys out the companion ASCII when KO so the visual matches the chip."""
	_companion_hp = current_hp
	_companion_max_hp = max_hp
	_companion_is_ko = is_ko
	if _companion_hp_row == null or not is_instance_valid(_companion_hp_row):
		return
	if max_hp <= 0:
		_companion_hp_row.visible = false
	else:
		_companion_hp_row.visible = true
		_companion_hp_bar.max_value = maxi(1, max_hp)
		_companion_hp_bar.value = clampi(current_hp, 0, max_hp)
		_companion_hp_text.text = "HP %d / %d" % [maxi(0, current_hp), max_hp]
	# Grey-out the companion ASCII art when KO.
	if _companion_art and is_instance_valid(_companion_art):
		if is_ko:
			_companion_art.modulate = Color(0.45, 0.45, 0.45, 0.65)
		else:
			_companion_art.modulate = Color.WHITE


func show_damage_on_companion(amount: int, is_crit: bool = false) -> void:
	"""Phase B1 — floating damage label above the companion ASCII when the
	monster targets it. Reuses the existing damage-label fan.
	v0.9.411 — during action phase, anchor on the overlay companion block
	(visible) instead of the faded in-box companion art.
	v0.9.415 — anchor at mid-body (0.5) instead of top-quarter (0.25) so the
	popup lands near the companion's head, not floating high above it."""
	if amount <= 0:
		return
	var anchor: Control
	if _action_phase_active and _overlay_companion_block and is_instance_valid(_overlay_companion_block):
		anchor = _overlay_companion_block
	else:
		anchor = _companion_art
	if anchor == null or not is_instance_valid(anchor):
		return
	var anchor_global := anchor.global_position + Vector2(anchor.size.x * 0.5, anchor.size.y * 0.5)
	# Pink-red color so companion hits are distinguishable from player hits.
	_spawn_damage_label(anchor_global, amount, is_crit, "monster", true)


func _refresh_companion() -> void:
	if _companion_data == null or _companion_data.is_empty():
		_companion_section.visible = false
		# v0.9.421 — clear the cached companion art so a new character with no
		# companion doesn't show the previous character's companion in the FX
		# overlay block. The overlay's _overlay_companion_ascii reads from
		# _companion_art.text, which would otherwise keep its stale BBCode
		# across character permadeath.
		if _companion_art and is_instance_valid(_companion_art):
			_companion_art.text = ""
		if _overlay_companion_ascii and is_instance_valid(_overlay_companion_ascii):
			_overlay_companion_ascii.text = ""
		if _overlay_companion_name and is_instance_valid(_overlay_companion_name):
			_overlay_companion_name.text = ""
		if _overlay_companion_hp_bar and is_instance_valid(_overlay_companion_hp_bar):
			_overlay_companion_hp_bar.max_value = 1
			_overlay_companion_hp_bar.value = 0
		return
	_companion_section.visible = true

	var name := str(_companion_data.get("name", "Companion"))
	var variant := str(_companion_data.get("variant", "Normal"))
	var level := int(_companion_data.get("level", 1))
	var sub_tier := int(_companion_data.get("sub_tier", _companion_data.get("tier", 1)))
	var variant_color := str(_companion_data.get("variant_color", "#FFFFFF"))
	# Tier badge inline with the name — gives players a quick "T2 Crimson"
	# read on the companion's stat presence.
	_companion_name_label.text = "[color=%s]%s[/color] [color=#888888]Lv %d T%d %s[/color]" % [variant_color, name, level, sub_tier, variant]

	# XP bar shows progress to next companion level. Formula matches
	# character.gd:get_companion_xp_to_next_level (pow(level+1, 2.0) * 15).
	if _companion_xp_bar and is_instance_valid(_companion_xp_bar):
		var xp_current := int(_companion_data.get("xp", 0))
		var xp_needed := int(pow(level + 1, 2.0) * 15)
		_companion_xp_bar.max_value = maxi(1, xp_needed)
		_companion_xp_bar.value = clampi(xp_current, 0, xp_needed)
		_companion_xp_text.text = "XP %d / %d" % [xp_current, xp_needed]

	# Phase B1 — Initialize HP bar from companion_data so it's visible at
	# combat_start (before the first combat_update arrives). Mirrors the
	# server's character.calculate_companion_max_hp formula. combat_update
	# overrides with authoritative values.
	if _companion_hp_row and is_instance_valid(_companion_hp_row):
		var bonuses: Dictionary = _companion_data.get("bonuses", {})
		var hp_bonus: int = int(bonuses.get("hp_bonus", 0))
		var comp_max_hp: int = 30 + level * 5 + sub_tier * 10 + hp_bonus
		var comp_cur_hp: int = int(_companion_data.get("combat_hp", comp_max_hp))
		comp_cur_hp = clampi(comp_cur_hp, 0, comp_max_hp)
		update_companion_combat_hp(comp_cur_hp, comp_max_hp, comp_cur_hp <= 0)

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
				# v0.9.412 — always brighten companion variant via
				# _ensure_readable_color (matches map hover brightness).
				# v0.9.413 — extra battle lift for the tactical view.
				if client_ref.has_method("_ensure_readable_color"):
					v_color = client_ref._ensure_readable_color(v_color)
					if v_color2 != "":
						v_color2 = client_ref._ensure_readable_color(v_color2)
				v_color = _battle_lift_color(v_color)
				if v_color2 != "":
					v_color2 = _battle_lift_color(v_color2)
				raw_art = client_ref._recolor_ascii_art_pattern(raw_art, v_color, v_color2, v_pattern)
			# v0.9.385 — compact layouts use a tiny font_size so the companion
			# ASCII fits in the COMPACT_PORTRAIT_PX box.
			# v0.9.393 — also wrap in [center] for compact layouts so the
			# (typically rectangular, line-padded) monster ASCII centers
			# horizontally within its portrait holder instead of left-aligning
			# and leaving a visible gap on the right.
			var comp_fs := COMPACT_ASCII_FONT_SIZE if _is_compact_layout() else _companion_font_size
			if _is_compact_layout():
				art_text = "[center][font_size=%d]%s[/font_size][/center]" % [comp_fs, raw_art]
			else:
				art_text = "[font_size=%d]%s[/font_size]" % [comp_fs, raw_art]
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
		# v0.9.390 — Lufia mirror.
		if _lufia_monster_hp_bar and is_instance_valid(_lufia_monster_hp_bar):
			_lufia_monster_hp_bar.value = 0
			_lufia_monster_hp_bar.max_value = 100
		if _lufia_monster_hp_text and is_instance_valid(_lufia_monster_hp_text):
			_lufia_monster_hp_text.text = "HP ???"
		return
	_monster_hp_bar.max_value = _monster_max_hp
	_monster_hp_bar.value = clampi(_monster_hp, 0, _monster_max_hp)
	_monster_hp_text.text = "HP %d / %d" % [maxi(0, _monster_hp), _monster_max_hp]
	if _lufia_monster_hp_bar and is_instance_valid(_lufia_monster_hp_bar):
		_lufia_monster_hp_bar.max_value = _monster_max_hp
		_lufia_monster_hp_bar.value = clampi(_monster_hp, 0, _monster_max_hp)
		# v0.9.395 — tint the Lufia bar fill to the monster's affinity color.
		# _monster_name_color is supplied per-monster from the server payload
		# (matches the name-tint in the monster name label).
		var fill_sb: StyleBoxFlat = _lufia_monster_hp_bar.get_theme_stylebox("fill")
		if fill_sb != null:
			fill_sb.bg_color = Color.from_string(_monster_name_color, Color("#FFAA22"))
	if _lufia_monster_hp_text and is_instance_valid(_lufia_monster_hp_text):
		_lufia_monster_hp_text.text = "HP %d / %d" % [maxi(0, _monster_hp), _monster_max_hp]


func _refresh_log() -> void:
	_log_label.text = "\n".join(_log_lines)
	# v0.9.415 — RichTextLabel.fit_content expands asynchronously: one frame
	# isn't always enough for `get_v_scroll_bar().max_value` to reflect the
	# new content height, so the auto-scroll silently snaps to a stale max.
	# Wait two frames AND re-apply after the resized signal lands.
	await get_tree().process_frame
	await get_tree().process_frame
	if _log_scroll and is_instance_valid(_log_scroll):
		var bar := _log_scroll.get_v_scroll_bar()
		if bar:
			_log_scroll.scroll_vertical = int(bar.max_value)


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
	# v0.9.411 — during action phase the in-box player portrait is faded
	# (alpha 0) and the battlefield OVERLAY player block is what's visible.
	# Lunge that instead so the player actually moves. Outside action phase
	# (or in non-Lufia layouts), animate the in-box portrait as before.
	if _action_phase_active and _overlay_player_block and is_instance_valid(_overlay_player_block):
		_lunge_node(_overlay_player_block, _overlay_player_block_baseline, true, true)
		return
	var node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
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


func lunge_companion_forward() -> void:
	"""v0.9.410 — per-actor visual signature. Companion ASCII lunges right
	(toward monster) when the companion attacks. v0.9.411 — during action
	phase, animate the OVERLAY companion block (the in-box one is faded)."""
	if _action_phase_active and _overlay_companion_block and is_instance_valid(_overlay_companion_block):
		_lunge_node(_overlay_companion_block, _overlay_companion_block_baseline, false, true)
		return
	if _companion_art == null or not is_instance_valid(_companion_art):
		return
	var baseline: Vector2
	if _companion_art.has_meta("lunge_baseline"):
		baseline = _companion_art.get_meta("lunge_baseline")
	else:
		baseline = _companion_art.position
		_companion_art.set_meta("lunge_baseline", baseline)
	if _companion_lunge_tween and _companion_lunge_tween.is_valid():
		_companion_lunge_tween.kill()
		_companion_art.position = baseline
	var target_pos = baseline + Vector2(LUNGE_DISTANCE, 0)
	_companion_lunge_tween = create_tween()
	_companion_lunge_tween.tween_property(_companion_art, "position", target_pos, LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_companion_lunge_tween.tween_property(_companion_art, "position", baseline, LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _lunge_node(node: Control, baseline: Vector2, is_player: bool, forward: bool) -> void:
	"""v0.9.411 — generic lunge helper for overlay character blocks. Used by
	lunge_player_forward / lunge_companion_forward when action phase is
	active so the visible (overlay) block animates instead of the faded
	in-box portrait."""
	if node == null or not is_instance_valid(node):
		return
	var dir := 1.0 if forward else -1.0
	var target := baseline + Vector2(LUNGE_DISTANCE * dir, 0)
	var t: Tween
	if is_player:
		if _player_lunge_tween and _player_lunge_tween.is_valid():
			_player_lunge_tween.kill()
		_player_lunge_tween = create_tween()
		t = _player_lunge_tween
	else:
		if _companion_lunge_tween and _companion_lunge_tween.is_valid():
			_companion_lunge_tween.kill()
		_companion_lunge_tween = create_tween()
		t = _companion_lunge_tween
	node.position = baseline
	t.tween_property(node, "position", target, LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "position", baseline, LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# === v0.9.413 — Miss FX ===

func show_miss_on_monster(source: String = "player") -> void:
	"""Floating MISS label above the monster (player or companion attacked
	but missed). v0.9.415 — color matches the attacker so MISS is visually
	consistent with the damage number the player/companion would have shown."""
	if _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var anchor_global = _monster_art_label.global_position + Vector2(_monster_art_label.size.x * 0.5, _monster_art_label.size.y * 0.25)
	var col: Color = Color("#3DD9FF") if source == "companion" else Color("#FFD93D")
	_spawn_miss_label(anchor_global, col)


func show_miss_on_player() -> void:
	"""Monster attacked but missed the player. v0.9.413. v0.9.415 — red to
	match the attacker; anchor at mid-body to land near the target."""
	var node: Control
	if _action_phase_active and _overlay_player_block and is_instance_valid(_overlay_player_block):
		node = _overlay_player_block
	else:
		node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
	var anchor_global = node.global_position + Vector2(node.size.x * 0.5, node.size.y * 0.5)
	_spawn_miss_label(anchor_global, Color("#FF6666"))


func show_miss_on_companion() -> void:
	"""Monster attacked but missed the companion (or companion lunged but
	missed). v0.9.413. v0.9.415 — red to match the attacker; anchor at
	mid-body to land near the target."""
	var anchor: Control
	if _action_phase_active and _overlay_companion_block and is_instance_valid(_overlay_companion_block):
		anchor = _overlay_companion_block
	elif _companion_art and is_instance_valid(_companion_art):
		anchor = _companion_art
	else:
		return
	var anchor_global = anchor.global_position + Vector2(anchor.size.x * 0.5, anchor.size.y * 0.5)
	_spawn_miss_label(anchor_global, Color("#FF6666"))


func _spawn_miss_label(anchor_global: Vector2, color: Color = Color("#FFD93D")) -> void:
	# v0.9.414 — bumped to bright yellow + larger font + bold scale-pop so
	# misses are unmistakably visible. The earlier gray-on-dark with 30pt
	# was easy to miss against the action-phase background.
	# v0.9.415 — color is now per-actor (passed in by show_miss_on_*) so the
	# MISS reads consistently with the actor's damage-number color.
	var label := Label.new()
	label.text = "MISS"
	# v0.9.415 — Fredoka Bold matches the normal-hit damage font so MISS
	# reads as part of the same visual family.
	var miss_font: Font = _get_display_font("fredoka")
	if miss_font != null:
		label.add_theme_font_override("font", miss_font)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05, 1.0))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 42)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# v0.9.415 — bumped from 110 to 130 so MISS draws in front of the
	# battlefield overlay (z=100) and its log strips.
	label.z_index = 130
	add_child(label)
	label.reset_size()
	# Position relative to the panel (account for top_level coords).
	var local_anchor: Vector2 = anchor_global - global_position - label.size * 0.5
	label.position = local_anchor

	# Reuse the damage-stack so misses also stack vertically with hits.
	# v0.9.415 — use the same reset window as damage popups (scaled by speed)
	# so misses don't overdraw recent damage numbers; cap so rapid bursts
	# don't push popups off the top of the panel.
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _damage_label_last_spawn_ts < DAMAGE_STACK_RESET_S:
		_damage_label_stack_y = maxf(_damage_label_stack_y - DAMAGE_STACK_STEP_PX, -DAMAGE_STACK_MAX_OFFSET)
	else:
		_damage_label_stack_y = 0.0
	_damage_label_last_spawn_ts = now
	label.position.y += _damage_label_stack_y
	# Final on-screen clamp: anchor can already be near the panel top (esp.
	# monster art), so stack offset on top of that may go negative. Force the
	# label inside the panel bounds; popups beyond capacity overlap at the
	# top edge instead of disappearing above it.
	label.position.y = maxf(label.position.y, 8.0)

	# Bold scale-pop + linger + fade.
	label.scale = Vector2(0.3, 0.3)
	label.pivot_offset = label.size * 0.5
	# v0.9.417 — bold scale-pop + linger + fade for MISS popups.
	var miss_linger := 0.85
	var miss_fade := 0.35
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "scale", Vector2(1.0, 1.0), 0.10).set_delay(0.12)
	t.tween_property(label, "modulate:a", 0.0, miss_fade).set_delay(miss_linger)
	t.tween_callback(label.queue_free).set_delay(miss_linger + miss_fade)


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
	# v0.9.411 — during action phase, anchor the popup over the overlay
	# player block (visible) instead of the faded in-box portrait.
	# v0.9.415 — anchor at mid-body (0.5) so the popup lands near the
	# player's head, not floating high above the target.
	var node: Control
	if _action_phase_active and _overlay_player_block and is_instance_valid(_overlay_player_block):
		node = _overlay_player_block
	else:
		node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return
	var anchor_global = node.global_position + Vector2(node.size.x * 0.5, node.size.y * 0.5)
	_spawn_damage_label(anchor_global, amount, is_crit, "monster", true)


# DoT floating numbers — small, tag-colored "tick" labels for bleed/poison/
# thorns/reflect/charm/curse damage. Spawned above the affected combatant.
const _DOT_COLORS := {
	"bleed":    "#FF4444",
	"poison":   "#66FF66",
	"thorns":   "#AAAAAA",
	"reflect":  "#FF66FF",
	"charm":    "#FF69B4",
	"curse":    "#9966FF",
	"backfire": "#9400D3",
}

func show_dot_tick(amount: int, dot_type: String, target_is_player: bool) -> void:
	"""Spawn a small tag-colored floating number for DoT/proc damage."""
	if amount <= 0:
		return
	var anchor_node: Control = _player_visual_for_fx() if target_is_player else _monster_art_label
	if anchor_node == null or not is_instance_valid(anchor_node):
		return
	var anchor_global := anchor_node.global_position + Vector2(anchor_node.size.x * 0.5, anchor_node.size.y * 0.15)
	var color_hex: String = _DOT_COLORS.get(dot_type, "#FFAA66")
	var label := Label.new()
	# Tag prefix so DoT ticks read distinctly from direct hits.
	var prefix := dot_type.substr(0, 1).to_upper()
	label.text = "%s -%d" % [prefix, amount]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 100
	label.add_theme_color_override("font_color", Color(color_hex))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 14)
	add_child(label)
	label.reset_size()

	# Use a separate fan slot (reuse seq counter) so DoT and direct hits don't
	# stack on the same fixed offsets.
	var slot: int = (_damage_label_seq + 2) % 5
	_damage_label_seq += 1
	var spread_x: float = [-40.0, 38.0, -10.0, 22.0, -28.0][slot]
	var spread_y: float = [-6.0, 2.0, -14.0, 10.0, -2.0][slot]

	var local_anchor: Vector2 = anchor_global - global_position - label.size * 0.5
	local_anchor += Vector2(spread_x, spread_y)
	label.position = local_anchor

	var float_distance := 40.0
	var lifetime := 0.85
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "position", local_anchor + Vector2(0, -float_distance), lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, lifetime * 0.55).set_delay(lifetime * 0.45)
	t.chain().tween_callback(label.queue_free)


# === v0.9.415 — Display font cache for damage / miss popups ===
# Fredoka Bold for normal-hit damage + miss labels, Bowlby One for crits.
# Lilita One is downloaded but currently unused (kept for future swaps).
var _display_font_bowlby: Font = null
var _display_font_fredoka: Font = null
var _display_font_lilita: Font = null

func _get_display_font(name: String) -> Font:
	"""Lazy-load and cache a display font from font/display/. Bypasses the
	Godot import system (no .import sidecar needed) by reading the TTF as
	raw bytes via FileAccess and constructing a FontFile manually. Returns
	null if the file is missing so the call site can fall back to default."""
	match name:
		"bowlby":
			if _display_font_bowlby == null:
				_display_font_bowlby = _load_ttf_runtime("res://font/display/BowlbyOne-Regular.ttf")
			return _display_font_bowlby
		"fredoka":
			if _display_font_fredoka == null:
				_display_font_fredoka = _load_ttf_runtime("res://font/display/Fredoka-Bold.ttf")
			return _display_font_fredoka
		"lilita":
			if _display_font_lilita == null:
				_display_font_lilita = _load_ttf_runtime("res://font/display/LilitaOne-Regular.ttf")
			return _display_font_lilita
	return null

func _load_ttf_runtime(path: String) -> FontFile:
	"""Load a TTF directly from disk into a FontFile, skipping the import
	system. Used for display fonts added at runtime without an editor pass."""
	if not FileAccess.file_exists(path):
		push_warning("[combat_scene_panel] display font missing: " + path)
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("[combat_scene_panel] display font is empty: " + path)
		return null
	var font := FontFile.new()
	font.data = bytes
	return font

func _spawn_damage_label(anchor_global: Vector2, amount: int, is_crit: bool, source: String, target_is_player: bool) -> void:
	# v0.9.396 — damage popup pass 4 per feedback:
	#   • NO boxy background panel — just a Label with a thick outline that
	#     forms a "border around the number" (the letterforms themselves get
	#     a near-black halo, not a rectangle).
	#   • NO upward drift — the number lingers in place, then fades.
	#   • Kept: thin+tall scale, white-flash impact, rotation jitter, crit
	#     shake, vertical no-overlap stacking.
	var color := Color("#FFD93D")  # default yellow = player damage
	var font_size := 40
	if is_crit:
		color = Color("#FF3B3B")
		font_size = 58
	elif source == "companion":
		color = Color("#3DD9FF")
	elif target_is_player:
		color = Color("#FF6666")

	# Bare Label — no Panel wrapper. The outline is the "border around the
	# number" the user asked for; thickness scales with font size.
	var label := Label.new()
	label.text = ("-%d" % amount) if amount > 0 else "0"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# v0.9.415 — bumped from 100 to 130 so damage popups draw in FRONT of
	# the battlefield overlay (z_index 100) and its child log strips, not
	# behind them.
	label.z_index = 130
	# v0.9.415 — display font: Fredoka Bold for normal hits, Bowlby One for
	# crits (bigger visual impact on the harder hit). Falls back to default
	# if a font is missing.
	var dmg_font: Font = _get_display_font("bowlby") if is_crit else _get_display_font("fredoka")
	if dmg_font != null:
		label.add_theme_font_override("font", dmg_font)
	# White-flash spawn color, tweens to damage color shortly after.
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 1.0))
	label.add_theme_constant_override("outline_size", maxi(8, int(font_size / 5.0)))
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5

	# Time-windowed vertical stack so rapid hits don't overlap. If recent,
	# push this one up by DAMAGE_STACK_STEP_PX; otherwise reset the stack.
	# The popup itself doesn't move — stack offset just determines spawn Y.
	_damage_label_seq += 1
	var now := float(Time.get_ticks_msec()) / 1000.0
	# v0.9.415 — scale reset window by speed_mult so Slow mode's longer
	# linger doesn't cause overlapping spawns. Cap the cumulative offset so
	# rapid bursts can't push popups off the top of the panel.
	if now - _damage_label_last_spawn_ts < DAMAGE_STACK_RESET_S:
		_damage_label_stack_y = maxf(_damage_label_stack_y - DAMAGE_STACK_STEP_PX, -DAMAGE_STACK_MAX_OFFSET)
	else:
		_damage_label_stack_y = 0.0
	_damage_label_last_spawn_ts = now
	var x_jitter := randf_range(-22.0, 22.0)

	var local_anchor = anchor_global - global_position - label.size * 0.5
	local_anchor += Vector2(x_jitter, _damage_label_stack_y)
	label.position = local_anchor
	# v0.9.415 — final on-screen clamp: anchor + stack can go above panel
	# when monster is high in the layout. Keep popups inside the panel.
	label.position.y = maxf(label.position.y, 8.0)

	# Slight random rotation per spawn (more for crits).
	var jitter_deg = randf_range(-4.0, 4.0) if not is_crit else randf_range(-7.0, 7.0)
	label.rotation = deg_to_rad(jitter_deg)

	# Persistent "thin + tall" scale (verticality).
	var rest_scale := Vector2(0.70, 1.55)
	label.scale = Vector2(0.30, 1.85)
	var t := create_tween().set_parallel(true)
	# Scale pop-in (overshoot for SNES "punch").
	t.tween_property(label, "scale", rest_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# White → damage color flash.
	t.tween_property(label, "theme_override_colors/font_color", color, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Crit shake during early linger (small wobble).
	# v0.9.415 — use the CLAMPED label.position as the shake base so the
	# shake doesn't pull a clamped popup back above the panel top edge.
	if is_crit:
		var shake_base: Vector2 = label.position
		var shake_amp := 4.0
		var shake_count := 4
		for i in range(shake_count):
			var dt := 0.05
			var dly := 0.20 + i * dt
			var dir = Vector2(randf_range(-shake_amp, shake_amp), randf_range(-shake_amp, shake_amp))
			t.tween_property(label, "position", shake_base + dir, dt).set_delay(dly).set_trans(Tween.TRANS_SINE)
		t.tween_property(label, "position", shake_base, 0.05).set_delay(0.20 + shake_count * 0.05)

	# v0.9.415 — breathe pulse: gentle scale oscillation during linger so the
	# number isn't completely static. Runs on its own tween in parallel.
	var breathe := create_tween().set_loops(3)
	var beat_a := rest_scale * Vector2(1.05, 0.97)
	var beat_b := rest_scale * Vector2(0.96, 1.04)
	breathe.tween_property(label, "scale", beat_a, 0.18).set_trans(Tween.TRANS_SINE).set_delay(0.25)
	breathe.tween_property(label, "scale", beat_b, 0.18).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(label, "scale", rest_scale, 0.18).set_trans(Tween.TRANS_SINE)

	# Linger in place, then fade with a subtle scale shrink (no upward drift).
	# v0.9.411 — reverted to 1.0s linger + 0.35s fade. The right fix is to
	# pause LONGER between actor attacks, not shorten popup readability.
	var linger_time := 1.0
	var fade_time := 0.35
	t.tween_property(label, "modulate:a", 0.0, fade_time).set_delay(linger_time)
	t.tween_property(label, "scale", rest_scale * 0.85, fade_time).set_delay(linger_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(label.queue_free).set_delay(linger_time + fade_time)


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
	# Subtle alpha pulse so the eye keeps coming back to it without it strobing.
	# Stored as a member so hide_flock_warning() can kill it explicitly —
	# without that, freeing the label leaves a 0-duration infinite-loop tween
	# behind and Godot hangs at scene/animation/tween.cpp:406 ("Infinite loop
	# detected") on the next frame, which has frozen the client during flock
	# transitions in the past.
	if _flock_warning_pulse_tween and is_instance_valid(_flock_warning_pulse_tween):
		_flock_warning_pulse_tween.kill()
	_flock_warning_pulse_tween = create_tween().set_loops()
	_flock_warning_pulse_tween.tween_property(label, "modulate:a", 0.65, 0.7).set_trans(Tween.TRANS_SINE)
	_flock_warning_pulse_tween.tween_property(label, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func hide_flock_warning() -> void:
	if _flock_warning_pulse_tween and is_instance_valid(_flock_warning_pulse_tween):
		_flock_warning_pulse_tween.kill()
	_flock_warning_pulse_tween = null
	if _flock_warning_label and is_instance_valid(_flock_warning_label):
		_flock_warning_label.queue_free()
	_flock_warning_label = null


# === Alt sprite (ASCII art) — /altsprite test ===

func set_player_ascii_art(text: String, font_size: int = 3, color_hex: String = "#E8E8E8", color2_hex: String = "", pattern: String = "solid") -> void:
	"""Render ASCII art at the bottom of the player column. Collapses the
	PNG sprite holder so the companion stays as the only thing on the
	left side of the battle row.

	Optional color2_hex + pattern apply per-line variant recoloring (gradient,
	stripes, middle-band, etc.) using the same helper companions use. Defaults
	mean the prior behavior (single-color tint) is preserved when no variant
	data is passed."""
	if _player_ascii_label == null or not is_instance_valid(_player_ascii_label):
		return
	# v0.9.406 — paint a contrasting bg behind the portrait based on variant
	# brightness (dark variants get a light parchment; bright variants keep
	# the dark box bg). This replaces the v0.9.404/405 color-brightening
	# attempts which couldn't get dark variants like Cobalt readable.
	_refresh_portrait_bg(_player_portrait_bg, color_hex)
	# v0.9.409 — text outline gives a contrasting halo around every glyph
	# so the figure reads regardless of bg. Halo color flips based on the
	# variant brightness: dark variants get a light halo (cream), bright
	# variants get a dark halo (near-black).
	_apply_ascii_outline(_player_ascii_label, color_hex)
	var safe_text = text.replace("[", "[lb]")  # keep stray brackets from being read as BBCode tags
	var bbcode: String
	if pattern != "solid" and color2_hex != "" and client_ref != null and client_ref.has_method("_recolor_ascii_art_pattern"):
		# Wrap in placeholder color tags so the helper can re-color per line.
		var wrapped = "[color=%s]\n%s\n[/color]" % [color_hex, safe_text]
		var recolored = client_ref._recolor_ascii_art_pattern(wrapped, color_hex, color2_hex, pattern)
		bbcode = "[font_size=%d]%s[/font_size]" % [font_size, recolored]
	else:
		bbcode = "[font_size=%d][color=%s]%s[/color][/font_size]" % [font_size, color_hex, safe_text]
	# v0.9.385/389 — compact layouts force a small font_size override so the
	# ASCII fits inside the portrait box. Player gets COMPACT_PLAYER_ASCII_FONT_SIZE
	# (slightly larger than the companion's font for readability). Sprites are
	# overworld-only; battle is ASCII even in compact layouts.
	if _is_compact_layout():
		if pattern != "solid" and color2_hex != "" and client_ref != null and client_ref.has_method("_recolor_ascii_art_pattern"):
			var wrapped = "[color=%s]\n%s\n[/color]" % [color_hex, safe_text]
			var recolored = client_ref._recolor_ascii_art_pattern(wrapped, color_hex, color2_hex, pattern)
			bbcode = "[font_size=%d]%s[/font_size]" % [COMPACT_PLAYER_ASCII_FONT_SIZE, recolored]
		else:
			bbcode = "[font_size=%d][color=%s]%s[/color][/font_size]" % [COMPACT_PLAYER_ASCII_FONT_SIZE, color_hex, safe_text]
	if _player_ascii_label and is_instance_valid(_player_ascii_label):
		_player_ascii_label.text = bbcode
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
	"""v0.9.418 — full-panel victory screen layered above the entire combat
	scene. Replaces the smaller v0.9.353 reward card. Shows VICTORY banner,
	defeated-monster line, Battle Totals row, XP / level-up, gear banner,
	loot list, and the Press-Space prompt. Sits at z_index 150 so it covers
	the battlefield overlay (z=100) and the panel chrome below.

	Parented to the panel's outer Control (self) so PRESET_FULL_RECT matches
	the full combat panel rect, not just the log section."""
	_victory_card_overlay = PanelContainer.new()
	_victory_card_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_card_overlay.z_index = 150
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.04, 0.03, 0.05, 0.98)
	card_sb.border_color = Color("#FFD700")
	card_sb.set_border_width_all(3)
	card_sb.set_corner_radius_all(6)
	card_sb.content_margin_left = 24
	card_sb.content_margin_right = 24
	card_sb.content_margin_top = 16
	card_sb.content_margin_bottom = 16
	_victory_card_overlay.add_theme_stylebox_override("panel", card_sb)
	_victory_card_overlay.visible = false
	_victory_card_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_victory_card_overlay)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_victory_card_overlay.add_child(vbox)

	# VICTORY banner — large gold centered title.
	var victory_banner := RichTextLabel.new()
	victory_banner.bbcode_enabled = true
	victory_banner.fit_content = true
	victory_banner.scroll_active = false
	victory_banner.add_theme_font_size_override("normal_font_size", 36)
	victory_banner.text = "[center][b][color=#FFD700]★ VICTORY ★[/color][/b][/center]"
	victory_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(victory_banner)

	# Defeated-monster line — "Defeated: Troll (Lv 21)".
	_victory_card_monster_label = RichTextLabel.new()
	_victory_card_monster_label.bbcode_enabled = true
	_victory_card_monster_label.fit_content = true
	_victory_card_monster_label.scroll_active = false
	_victory_card_monster_label.add_theme_font_size_override("normal_font_size", 18)
	_victory_card_monster_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_victory_card_monster_label)

	# Divider before totals.
	var divider_top := ColorRect.new()
	divider_top.color = Color("#5C4D33")
	divider_top.custom_minimum_size = Vector2(0, 2)
	divider_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider_top)

	# Battle Totals header + row.
	var totals_header := RichTextLabel.new()
	totals_header.bbcode_enabled = true
	totals_header.fit_content = true
	totals_header.scroll_active = false
	totals_header.add_theme_font_size_override("normal_font_size", 14)
	totals_header.text = "[center][color=#5C4D33][b]── Battle Totals ──[/b][/color][/center]"
	totals_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(totals_header)

	_victory_card_totals_label = RichTextLabel.new()
	_victory_card_totals_label.bbcode_enabled = true
	_victory_card_totals_label.fit_content = true
	_victory_card_totals_label.scroll_active = false
	_victory_card_totals_label.add_theme_font_size_override("normal_font_size", 16)
	_victory_card_totals_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_victory_card_totals_label)

	# Divider before XP/loot.
	var divider_mid := ColorRect.new()
	divider_mid.color = Color("#5C4D33")
	divider_mid.custom_minimum_size = Vector2(0, 2)
	divider_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider_mid)

	_victory_card_xp_label = RichTextLabel.new()
	_victory_card_xp_label.bbcode_enabled = true
	_victory_card_xp_label.fit_content = true
	_victory_card_xp_label.scroll_active = false
	_victory_card_xp_label.add_theme_font_size_override("normal_font_size", 16)
	_victory_card_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_victory_card_xp_label)

	_victory_card_levelup_label = RichTextLabel.new()
	_victory_card_levelup_label.bbcode_enabled = true
	_victory_card_levelup_label.fit_content = true
	_victory_card_levelup_label.scroll_active = false
	_victory_card_levelup_label.add_theme_font_size_override("normal_font_size", 18)
	_victory_card_levelup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_victory_card_levelup_label.visible = false
	vbox.add_child(_victory_card_levelup_label)

	# v0.9.353 — dedicated gear banner. Highlighted PanelContainer that calls
	# out new gear drops with a rarity-colored frame so they don't disappear
	# into the regular drop list. Hidden when there are no gear drops.
	_victory_card_gear_banner = PanelContainer.new()
	var gear_sb := StyleBoxFlat.new()
	gear_sb.bg_color = Color(0.20, 0.16, 0.05, 0.90)
	gear_sb.border_color = Color("#FFD700")
	gear_sb.set_border_width_all(2)
	gear_sb.set_corner_radius_all(3)
	gear_sb.content_margin_left = 8
	gear_sb.content_margin_right = 8
	gear_sb.content_margin_top = 4
	gear_sb.content_margin_bottom = 4
	_victory_card_gear_banner.add_theme_stylebox_override("panel", gear_sb)
	_victory_card_gear_banner.visible = false
	_victory_card_gear_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_victory_card_gear_banner)
	_victory_card_gear_vbox = VBoxContainer.new()
	_victory_card_gear_vbox.add_theme_constant_override("separation", 2)
	_victory_card_gear_banner.add_child(_victory_card_gear_vbox)

	# Divider before loot
	var divider1 := ColorRect.new()
	divider1.color = Color("#5C4D33")
	divider1.custom_minimum_size = Vector2(0, 1)
	divider1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider1)

	# Loot list — scrollable in case there are many drops
	# Loot section header.
	var loot_header := RichTextLabel.new()
	loot_header.bbcode_enabled = true
	loot_header.fit_content = true
	loot_header.scroll_active = false
	loot_header.add_theme_font_size_override("normal_font_size", 14)
	loot_header.text = "[center][color=#5C4D33][b]── Loot ──[/b][/color][/center]"
	loot_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(loot_header)

	var loot_scroll := ScrollContainer.new()
	loot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	loot_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(loot_scroll)

	_victory_card_loot_vbox = VBoxContainer.new()
	_victory_card_loot_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_victory_card_loot_vbox.add_theme_constant_override("separation", 2)
	loot_scroll.add_child(_victory_card_loot_vbox)

	# Divider before prompt
	var divider_bot := ColorRect.new()
	divider_bot.color = Color("#5C4D33")
	divider_bot.custom_minimum_size = Vector2(0, 2)
	divider_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider_bot)

	_victory_card_prompt_label = RichTextLabel.new()
	_victory_card_prompt_label.bbcode_enabled = true
	_victory_card_prompt_label.fit_content = true
	_victory_card_prompt_label.scroll_active = false
	_victory_card_prompt_label.add_theme_font_size_override("normal_font_size", 16)
	_victory_card_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_victory_card_prompt_label)


func show_victory_card(rewards: Dictionary) -> void:
	"""Render the post-fight rewards card. Expected keys:
	xp_gain (int), old_level (int), new_level (int), did_level_up (bool),
	loot (Array of preformatted BBCode strings), harvest_available (bool),
	continue_key (String), gear_drops (Array of Dict).
	The card stays visible until hide_victory_card() is called.

	v0.9.418 — also pulls _monster_name + _monster_level + _player_total /
	_companion_total / _monster_total directly from the panel so callers don't
	need to thread that data through the rewards dict."""
	if _victory_card_overlay == null or not is_instance_valid(_victory_card_overlay):
		return

	# Defeated-monster line.
	if _monster_name != "":
		var name_color: String = _monster_name_color if _monster_name_color != "" else "#FFFFFF"
		_victory_card_monster_label.text = "[center][color=#888888]Defeated:[/color] [color=%s][b]%s[/b][/color] [color=#888888](Lv %d)[/color][/center]" % [name_color, _monster_name, _monster_level]
	else:
		_victory_card_monster_label.text = ""

	# Battle Totals row — pull totals from panel's own running tally.
	var totals_parts: Array = []
	totals_parts.append("[color=#C9A040]You: [/color][color=#FFD93D]%d[/color]" % _player_total)
	if _companion_total > 0:
		totals_parts.append("[color=#FF9966]Pet: [/color][color=#3DD9FF]%d[/color]" % _companion_total)
	totals_parts.append("[color=#FF6666]Foe: [/color][color=#FFA033]%d[/color]" % _monster_total)
	_victory_card_totals_label.text = "[center]" + "   ·   ".join(totals_parts) + "[/center]"

	var xp_gain = int(rewards.get("xp_gain", 0))
	if xp_gain > 0:
		_victory_card_xp_label.text = "[center][color=#A0E0FF]+%d XP[/color][/center]" % xp_gain
		_victory_card_xp_label.visible = true
	else:
		_victory_card_xp_label.text = ""
		_victory_card_xp_label.visible = false

	var did_level_up = bool(rewards.get("did_level_up", false))
	if did_level_up:
		var old_level = int(rewards.get("old_level", 0))
		var new_level = int(rewards.get("new_level", 0))
		_victory_card_levelup_label.text = "[center][b][color=#FFE066]LEVEL UP![/color][/b]  [color=#FFE066]Lv %d → Lv %d[/color][/center]" % [old_level, new_level]
		_victory_card_levelup_label.visible = true
	else:
		_victory_card_levelup_label.visible = false

	# v0.9.353 — gear drop banner. Server populates `gear_drops` with one
	# entry per equipment item dropped this combat. Each entry carries
	# {name, rarity, symbol, color, level} so we can render a prominent
	# rarity-colored callout that won't blend into the generic loot list.
	# v0.9.355 — filter out non-gear entries. drop_data is also populated
	# with {is_egg: true} / {is_material: true} entries used for sound-FX
	# routing — those don't have a `name` and would render as "Unknown".
	# Real gear entries always carry a non-empty `name`.
	for child in _victory_card_gear_vbox.get_children():
		child.queue_free()
	var raw_drops: Array = rewards.get("gear_drops", [])
	var gear_drops: Array = []
	for entry in raw_drops:
		if entry is Dictionary and String(entry.get("name", "")) != "":
			gear_drops.append(entry)
	if gear_drops.is_empty():
		_victory_card_gear_banner.visible = false
	else:
		_victory_card_gear_banner.visible = true
		# Header line: "★ N NEW ITEM(S) ACQUIRED ★"
		var header_label := RichTextLabel.new()
		header_label.bbcode_enabled = true
		header_label.fit_content = true
		header_label.scroll_active = false
		header_label.add_theme_font_size_override("normal_font_size", 15)
		header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var noun = "ITEM" if gear_drops.size() == 1 else "ITEMS"
		header_label.text = "[center][b][color=#FFD700]★ %d NEW %s ACQUIRED ★[/color][/b][/center]" % [gear_drops.size(), noun]
		_victory_card_gear_vbox.add_child(header_label)
		# One row per gear drop — large, rarity-colored, with level tag
		for entry in gear_drops:
			if not (entry is Dictionary):
				continue
			var row := RichTextLabel.new()
			row.bbcode_enabled = true
			row.fit_content = true
			row.scroll_active = false
			row.add_theme_font_size_override("normal_font_size", 16)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var g_name = String(entry.get("name", "Unknown Item"))
			var g_color = String(entry.get("color", "#FFFFFF"))
			var g_symbol = String(entry.get("symbol", "•"))
			var g_rarity = String(entry.get("rarity", "common"))
			var g_level = int(entry.get("level", 0))
			# Capitalize rarity for display
			var rarity_label = g_rarity.capitalize() if g_rarity.length() > 0 else "Common"
			var level_str = ("Lv %d " % g_level) if g_level > 0 else ""
			row.text = "[center][color=%s][b]%s %s[/b][/color]   [color=#888888]%s%s[/color][/center]" % [g_color, g_symbol, g_name, level_str, rarity_label]
			_victory_card_gear_vbox.add_child(row)

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
			# v0.9.353 — bumped 12→13pt so regular loot list is readable next
			# to the new gear banner (which is 15-16pt). Keeps a visual gap
			# between "headline drop" and "everything else."
			row.add_theme_font_size_override("normal_font_size", 13)
			row.text = "  " + str(drop_msg)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_victory_card_loot_vbox.add_child(row)

	var key_name = str(rewards.get("continue_key", "Space"))
	var primary_prompt = ""
	if bool(rewards.get("harvest_available", false)):
		primary_prompt = "[color=#FF6600][b]Press [%s] to harvest[/b][/color]" % key_name
	else:
		primary_prompt = "[color=#FFD700][b]Press [%s] to continue[/b][/color]" % key_name
	# Secondary hint — let players who want the full play-by-play pop the
	# legacy detail view (game_output) without pressing continue.
	_victory_card_prompt_label.text = "[center]%s   [color=#888888]·  Press [L] to view details[/color][/center]" % primary_prompt

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


# === Death card ===

func _build_death_card_overlay() -> void:
	"""Card layered over the log section that mirrors the victory card
	pattern for permadeath. Shows the key eulogy info inside the scene
	so death is part of combat, not a wall-of-text exit."""
	_death_card_overlay = PanelContainer.new()
	_death_card_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# v0.9.420 — z_index 150 so the death card draws above the battlefield
	# overlay (z=100) when the player dies mid-action-phase. Without this,
	# the strips covered the death card and players saw the combat panel
	# instead of the eulogy + Continue prompt. Matches victory card's z=150.
	_death_card_overlay.z_index = 150
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.08, 0.02, 0.02, 0.97)
	card_sb.border_color = Color("#FF4444")
	card_sb.set_border_width_all(2)
	card_sb.set_corner_radius_all(4)
	card_sb.content_margin_left = 12
	card_sb.content_margin_right = 12
	card_sb.content_margin_top = 8
	card_sb.content_margin_bottom = 8
	_death_card_overlay.add_theme_stylebox_override("panel", card_sb)
	_death_card_overlay.visible = false
	_death_card_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	_log_inner.add_child(_death_card_overlay)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_death_card_overlay.add_child(vbox)

	_death_card_header_label = RichTextLabel.new()
	_death_card_header_label.bbcode_enabled = true
	_death_card_header_label.fit_content = true
	_death_card_header_label.scroll_active = false
	_death_card_header_label.add_theme_font_size_override("normal_font_size", 16)
	_death_card_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_death_card_header_label)

	_death_card_summary_label = RichTextLabel.new()
	_death_card_summary_label.bbcode_enabled = true
	_death_card_summary_label.fit_content = true
	_death_card_summary_label.scroll_active = false
	_death_card_summary_label.add_theme_font_size_override("normal_font_size", 13)
	_death_card_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_death_card_summary_label)

	# Divider
	var divider1 := ColorRect.new()
	divider1.color = Color("#5C2D2D")
	divider1.custom_minimum_size = Vector2(0, 1)
	divider1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider1)

	_death_card_combat_label = RichTextLabel.new()
	_death_card_combat_label.bbcode_enabled = true
	_death_card_combat_label.fit_content = true
	_death_card_combat_label.scroll_active = false
	_death_card_combat_label.add_theme_font_size_override("normal_font_size", 13)
	_death_card_combat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_death_card_combat_label)

	# Divider before rewards
	var divider2 := ColorRect.new()
	divider2.color = Color("#5C2D2D")
	divider2.custom_minimum_size = Vector2(0, 1)
	divider2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(divider2)

	_death_card_rewards_label = RichTextLabel.new()
	_death_card_rewards_label.bbcode_enabled = true
	_death_card_rewards_label.fit_content = true
	_death_card_rewards_label.scroll_active = false
	_death_card_rewards_label.add_theme_font_size_override("normal_font_size", 13)
	_death_card_rewards_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_death_card_rewards_label)

	# Spacer pushes the prompt to the bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	_death_card_prompt_label = RichTextLabel.new()
	_death_card_prompt_label.bbcode_enabled = true
	_death_card_prompt_label.fit_content = true
	_death_card_prompt_label.scroll_active = false
	_death_card_prompt_label.add_theme_font_size_override("normal_font_size", 13)
	_death_card_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_death_card_prompt_label)


func show_death_card(payload: Dictionary) -> void:
	"""Render the in-scene death card. Expected keys:
	character_name (String), level (int), race (String), class_type (String),
	cause_of_death (String), rounds_fought (int), total_damage_dealt (int),
	total_damage_taken (int), baddie_points_earned (int),
	leaderboard_rank (int), continue_key (String)."""
	if _death_card_overlay == null or not is_instance_valid(_death_card_overlay):
		return

	var char_name = str(payload.get("character_name", "Unknown"))
	var level = int(payload.get("level", 1))
	var race = str(payload.get("race", ""))
	var class_type = str(payload.get("class_type", ""))
	var cause = str(payload.get("cause_of_death", "Unknown"))
	var rounds = int(payload.get("rounds_fought", 0))
	var dmg_dealt = int(payload.get("total_damage_dealt", 0))
	var dmg_taken = int(payload.get("total_damage_taken", 0))
	var bp = int(payload.get("baddie_points_earned", 0))
	var rank = int(payload.get("leaderboard_rank", 0))
	var key_name = str(payload.get("continue_key", "Space"))

	_death_card_header_label.text = "[b][color=#FF4444]%s HAS FALLEN[/color][/b]" % char_name.to_upper()
	var summary_lines: Array = []
	var class_line = "Lv %d" % level
	if race != "" or class_type != "":
		class_line = "Lv %d %s %s" % [level, race, class_type]
	summary_lines.append("[color=#CCCCCC]%s[/color]" % class_line.strip_edges())
	summary_lines.append("[color=#FF8888]Slain by:[/color] %s" % cause)
	_death_card_summary_label.text = "\n".join(summary_lines)

	var combat_lines: Array = []
	if rounds > 0:
		combat_lines.append("[color=#888888]Rounds Fought:[/color] %d" % rounds)
	if dmg_dealt > 0 or dmg_taken > 0:
		combat_lines.append("[color=#66FF99]Damage Dealt:[/color] %d   [color=#FF6666]Damage Taken:[/color] %d" % [dmg_dealt, dmg_taken])
	if combat_lines.is_empty():
		combat_lines.append("[color=#888888]No combat recorded[/color]")
	_death_card_combat_label.text = "\n".join(combat_lines)

	var reward_lines: Array = []
	if bp > 0:
		reward_lines.append("[color=#FF6600][b]+%d Baddie Points[/b][/color]" % bp)
		reward_lines.append("[color=#888888]Spend them at your Sanctuary.[/color]")
	if rank > 0:
		reward_lines.append("[color=#FFD700]Leaderboard Rank:[/color] #%d" % rank)
	if reward_lines.is_empty():
		reward_lines.append("[color=#888888]No rewards earned[/color]")
	_death_card_rewards_label.text = "\n".join(reward_lines)

	_death_card_prompt_label.text = "[color=#FFD700]Press [%s] to continue[/color]   [color=#888888]·  Press [L] for full eulogy[/color]" % key_name

	_death_card_overlay.visible = true
	_death_interlude_active = true
	if _log_scroll:
		_log_scroll.visible = false
	# Subtle fade-in
	_death_card_overlay.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_death_card_overlay, "modulate:a", 1.0, 0.30)


func hide_death_card() -> void:
	if _death_card_overlay and is_instance_valid(_death_card_overlay):
		_death_card_overlay.visible = false
	if _log_scroll and is_instance_valid(_log_scroll):
		_log_scroll.visible = true
	_death_interlude_active = false


func is_death_card_visible() -> bool:
	return _death_card_overlay != null and is_instance_valid(_death_card_overlay) and _death_card_overlay.visible


func is_death_interlude_active() -> bool:
	"""True while the death card is showing or temporarily swapped out for
	the legacy eulogy view. Drives panel-stays-visible logic on the client."""
	return _death_interlude_active
