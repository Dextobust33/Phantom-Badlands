extends Control
class_name CombatScenePanel

# JRPG-style battle scene overlay. Top half is the scene (player+companion
# on the left, monster on the right). Bottom half is a combat log mirror.
# A1 slice — static layout only, no animations yet. PNG class sprites on
# the left, ASCII monster art on the right (mismatched by design — see
# project_combat_juice.md for the decision).
#
# v0.9.417 — Lufia II layout. Earlier prototypes (LAYOUT_STANDARD,
# LAYOUT_CHRONO) were unreachable after the Lufia switch; their build
# functions + early-return guards + dispatch match were pruned in
# v0.9.569's dead-code pass.
const LAYOUT_LUFIA := "lufia"
const combat_layout: String = LAYOUT_LUFIA

const MONO_FONT_PATH := "res://font/Consolas/consolas.ttf"
static var _mono_font: FontFile = null

var client_ref = null

# v0.9.646 — per-element UI scale handles. The outer card PanelContainers are
# captured during _build_scene_section_lufia so the click-to-resize edit mode
# can target each independently.
var _player_party_box: PanelContainer = null
var _companion_party_box: PanelContainer = null
# v0.9.650 — monster ASCII font multiplier applied at _refresh_monster() time.
# Earlier versions used Control.scale on the label, which got clipped by the
# parent art_holder's clip_contents=true so the ASCII never actually grew on
# screen. Now we rewrite the font_size in the BBCode itself so the text re-
# renders at the new size.
var _monster_art_user_scale: float = 1.0
# v0.9.663 — auto-fit: scale computed so the monster ASCII fills its available
# band at any resolution (no spill onto the party cards at 1080p, no waste at
# 1440p). Multiplies with the per-element user scale above.
var _monster_art_auto_scale: float = 1.0
var _last_autofit_band: Vector2 = Vector2.ZERO  # v0.9.663 — resize watchdog (see _process)
var _last_refresh_payload: Dictionary = {}

# Cached state (last populate call)
var _player_class: String = ""
var _player_name: String = ""
var _player_battler_id: String = ""   # v0.9.670 — stored character.battler_id
var _player_equipped: Dictionary = {} # v0.9.672 — for equipment sprite markers
var _player_race: String = ""         # v0.9.675 — for race/class card theming

# v0.9.675 — per-class emblem badge on cards (Dingbats block, same coverage as the
# category glyphs ⚔✦❄◈ that already render). Falls back to the class initial.
const CLASS_EMBLEM := {
	"Fighter": "⚔", "Barbarian": "⚒", "Paladin": "✚", "Wizard": "✸",
	"Sorcerer": "☄", "Sage": "✜", "Thief": "✥", "Ranger": "➹", "Ninja": "✴",
}
# v0.9.675 — colorblind aid: each ability category gets a distinct card corner
# shape (keyed by its glyph) so categories read WITHOUT relying on border colour.
# Sharp = aggressive (offense), round = soft (buff), between for control/utility.
const CATEGORY_CORNER := {"⚔": 2, "✦": 13, "❄": 6, "◈": 10}
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
var _monster_hp_exceeded: bool = false  # v0.9.587 — true when player has dealt > known max, monster still alive

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
# COMBAT REDESIGN (2026-08-20): retire the floating battlefield overlay (the
# source of the resolution-dependent overlap/scatter). Combat stays in the one
# container layout; combat text shows in a single always-visible band below.
var _overlay_retired: bool = true
var _battle_log_frame: PanelContainer
var _battle_log_band: RichTextLabel
var _battle_log_scroll: ScrollContainer  # v0.9.664 — scrollback for the combat log

# COMBAT REDESIGN (2026-08-20) — Time Fantasy pixel battler sprites replacing the
# muddy ASCII player art. TEST slice: Fighter only. Frames named idle_0..2 /
# atk_0..2 (48x48) live in client/sprites/battlers/<folder>/. Battlers face LEFT
# (RPG-Maker convention) so we flip_h to face the enemy.
const BATTLER_DIR := "res://client/sprites/battlers/"
# Each class has a POOL of Time Fantasy characters (ids under battlers/tf/<id>/).
# A character gets a STABLE random pick from its class pool via hash(name) — no
# selection UI, no server field; two same-class characters differ, and the same
# character always looks the same. First-pass pools (verify vs tf_contact_sheet).
const CLASS_SPRITE_POOLS := {
	"Fighter": ["1_1", "2_1", "6_4"],
	"Barbarian": ["6_2", "5_3", "7_8"],
	"Paladin": ["4_7", "2_8", "3_8"],
	"Wizard": ["1_6", "5_6", "2_6"],
	"Sorcerer": ["4_5", "3_6", "1_5"],
	"Sage": ["3_3", "5_7", "5_8"],
	"Thief": ["5_7", "6_3", "7_5"],
	"Ranger": ["3_4", "2_4", "6_1"],
	"Ninja": ["4_5", "1_8", "7_3"],
}
var _battler_idle: Array = []
var _battler_atk: Array = []
var _battler_magic: Array = []
var _battler_bow: Array = []
var _battler_active: bool = false
var _battler_frame: int = 0
var _battler_atk_playing: bool = false
var _battler_timer: Timer = null
# Per-class action animation style: mages cast in place, rangers draw a bow,
# everyone else steps forward and swings. Default (absent) = melee "atk".
const BATTLER_ANIM_STYLE := {
	"Wizard": "magic", "Sorcerer": "magic", "Sage": "magic",
	"Ranger": "bow",
}

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
# Co-op (#64 Slice 2) — right-side party column showing OTHER party members
# (up to 4) + their companions. Hidden/collapsed in solo so solo combat is
# pixel-identical. Populated by set_party_members(); each card dict holds the
# node refs needed to update name/HP/art without a rebuild.
var _party_column: VBoxContainer = null
var _party_scroll: ScrollContainer = null
var _party_member_cards: Array = []
# #76 Slice 3 — peer id -> card, so per-actor FX can find the right teammate. Rebuilt on
# every set_party_members() call (cards are reused positionally, members can change).
var _party_card_by_pid: Dictionary = {}
var _party_card_tweens: Dictionary = {}
const PARTY_COLUMN_MAX_MEMBERS := 4
# Offscreen rasterizer for party-member companion art: renders the monster ASCII
# into an ImageTexture once (cached by monster_type) so it can be scaled to sprite
# size in a TextureRect. Same idea as the player-portrait SubViewport compositor.
var _comp_vp: SubViewport = null
var _comp_vp_label: RichTextLabel = null
var _comp_tex_cache: Dictionary = {}
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
var _totals_strip_frame: PanelContainer  # v0.9.425 — wrapping PanelContainer (yellow-gold border); hide this during action phase to keep the border out of the FX scene
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
# v0.9.501: bumped from 1.5 → 3.0 so the stack accumulates across the full
# new ~2.7s linger of a damage popup (otherwise a rapid second hit reuses
# the same offset and overlaps the still-visible first popup).
const DAMAGE_STACK_RESET_S := 3.0
# v0.9.415 — cap stack so rapid bursts don't push popups off the panel.
# At 70px/step, 210px = 4 popups visible before plateauing. Beyond that the
# topmost slot is reused and new popups overlap the previous topmost, but
# everything stays on-screen.
const DAMAGE_STACK_MAX_OFFSET := 210.0

const FLASH_TINT_HIT := Color(1.6, 0.5, 0.5)  # Reddish overdrive
const FLASH_TINT_CRIT := Color(2.0, 0.4, 0.2)  # Hotter red
const FLASH_DURATION := 0.18
const LUNGE_DISTANCE := 16.0
const LUNGE_DURATION := 0.07  # v0.9.439: 0.10 → 0.07. One direction; total = 2x.

# Audit #1 Slice 6a — combat hand row. Card cells in a horizontal strip
# plus a small "Deck N · Discard M" indicator on the right. Cells are
# PanelContainers built once at layout time and rebuilt on each hand
# update so we don't repeatedly add/remove children mid-combat.
# v0.9.419 — hand size dropped 5 → 3 so each card matters more per round
# and the strip footprint shrinks. Must match shared/combat_manager.gd's
# COMBAT_HAND_SIZE — server fallback uses the server const, so a
# mismatch would render empty cells.
const COMBAT_HAND_SIZE := 3
# v0.9.675 — real portrait card frame (banner + icon + cost pip + rank pips +
# mastery fill) so the hand reads as actual cards.
const CARD_W := 150
const CARD_H := 190
signal card_played(card_name: String)
var _hand_strip: HBoxContainer
var _hand_cells: Array = []  # Array of PanelContainers (5)
var _hand_status_label: RichTextLabel
var _combat_hand: Array = []
var _combat_deck_count: int = 0
var _combat_discard_count: int = 0
# v0.9.385 — optional Lufia-box mirror widgets (HP + deck info inside the
# player's stat box, beside the portrait). Created in
# _build_lufia_player_box_content and updated alongside the shared widgets;
# null in non-lufia layouts.
var _lufia_player_hp_bar: ProgressBar
var _lufia_player_hp_text: Label
# v0.9.601 — resource bar (mana/stamina/energy) for the pre-FX Lufia player
# box. Mirrors the FX overlay so resource is visible in both combat views;
# pairs with the v0.9.601 removal of the bottom resource_bars_overlay
# during combat (info was redundant once the combat scene shows it).
var _lufia_player_resource_bar: ProgressBar = null
var _lufia_player_resource_text: Label = null
var _lufia_player_deck_label: RichTextLabel
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
# v0.9.593 — persistent FX mode. After Round 1 of a combat, the battlefield
# overlay stays up for the rest of the fight instead of fading in/out every
# round. Set to true on the FIRST end_action_phase of a combat (per memo
# `project-persistent-fx-screen`); reset when combat actually ends via
# `_force_end_action_phase()`. While true, start_action_phase / end_action_phase
# skip their fade tweens — the overlay is the persistent backdrop and the
# hand / totals / status strips are visible alongside it.
var _fx_persistent_active: bool = false
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
# v0.9.567 — extended to R6 (Legend, Mythic) to match character.gd.
const HAND_RANK_NAMES: Array = ["Untrained", "Novice", "Adept", "Expert", "Master", "Legend", "Mythic"]
const HAND_RANK_COLORS: Array = ["#888888", "#9ACD32", "#66CCFF", "#FFD700", "#FF6644", "#FF44FF", "#88FFFF"]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_load_mono_font()
	_build_layout()
	visible = false


func _notification(what: int) -> void:
	# v0.9.439 — keep the Review FX button anchored to the top-right on resize
	# and hide it when the combat panel becomes invisible.
	match what:
		NOTIFICATION_RESIZED:
			if _review_button and is_instance_valid(_review_button) and _review_button.visible:
				_position_review_button()
			# v0.9.568 — keep ? Help button anchored to top-left on resize.
			if _help_button and is_instance_valid(_help_button) and _help_button.visible:
				_position_help_button()
			# v0.9.663 — re-fit the monster ASCII to the new band. Deferred so it
			# runs after child containers have taken their new sizes.
			if _monster_name != "":
				call_deferred("_apply_monster_autofit_deferred")
		NOTIFICATION_VISIBILITY_CHANGED:
			if not visible:
				if _review_button and is_instance_valid(_review_button):
					_review_button.visible = false


func _process(_delta: float) -> void:
	# v0.9.663 — resize watchdog. Some size changes (notably toggling fullscreen
	# on a different-resolution monitor) don't deliver a usable
	# NOTIFICATION_RESIZED before the child columns re-layout, so the monster
	# could stay at the old scale. Poll the monster band and re-fit when it moves.
	if _monster_name == "" or not visible:
		return
	if _monster_col == null or not is_instance_valid(_monster_col):
		return
	var sz: Vector2 = _monster_col.size
	if absf(sz.x - _last_autofit_band.x) > 2.0 or absf(sz.y - _last_autofit_band.y) > 2.0:
		_last_autofit_band = sz
		_apply_monster_autofit_deferred()


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

	# === Top: scene (player vs monster) — Lufia II arrangement ===
	# v0.9.569 — pruned the dispatch match + dead alternates (standard / chrono).
	var scene_root: Control = _build_scene_section_lufia()
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

	# v0.9.664 - combat log + ability hand now live INSIDE the 2-column scene
	# section (log=left-top, hand=right-bottom); see _build_scene_section_lufia.

	# === Bottom: combat log mirror ===
	# v0.9.429 — the legacy log strip is no longer attached to the layout.
	# The per-actor overlay strips that land during the action phase
	# (v0.9.415+) replaced its function — that's where attacks read by
	# actor — and in the Lufia layout this strip was squeezed too short
	# to be readable. Keeping _log_section / _log_inner / _log_scroll /
	# _log_label allocated (just not added to root_vbox) so append_log
	# stays a no-op write instead of crashing — testfx fixtures and a few
	# real callers still poke it. Death card / picker overlays that used
	# to be parented under _log_inner now go directly on the panel root.
	_log_section = PanelContainer.new()
	_log_section.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	# v0.9.439 — Review FX button. Sits at the top-right of the combat panel
	# (sibling of _root_panel) so it's visible when the overlay is hidden —
	# i.e., during hand selection. Pressing it re-enters the action-phase
	# visuals so the player can re-read the per-actor strips (which become
	# mouse-scrollable in review mode).
	_review_button = Button.new()
	_review_button.text = "🩸 Review Damage"
	_review_button.tooltip_text = "Re-open the FX scene to re-read this fight's damage / combat log"
	_review_button.add_theme_font_size_override("font_size", 15)
	_review_button.custom_minimum_size = Vector2(168, 36)
	_review_button.focus_mode = Control.FOCUS_NONE
	# v0.9.609 — bumped z_index past the victory card overlay (z=150) so the
	# button is clickable from the victory screen too. Player feedback:
	# "the player should be able to toggle off of the Victory Screen to see
	# the combat log or look back at the FX screen before so they can see
	# what all happened in the fight." The button's _update_review_button_
	# visibility already shows it whenever the action phase isn't active +
	# log content exists; only the z-ordering was blocking it.
	_review_button.z_index = 200
	_review_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_review_button.visible = false
	_review_button.pressed.connect(_on_review_button_pressed)
	add_child(_review_button)
	call_deferred("_position_review_button")

	# v0.9.611 — pagination controls for Review FX across flock chains.
	# Sit just below the Review FX button in a horizontal row. Hidden by
	# default; shown only while in review phase AND total fights > 1.
	_review_prev_btn = Button.new()
	_review_prev_btn.text = "◀ Prev Fight"
	_review_prev_btn.tooltip_text = "Show the previous fight in this flock chain"
	_review_prev_btn.add_theme_font_size_override("font_size", 13)
	_review_prev_btn.custom_minimum_size = Vector2(118, 30)
	_review_prev_btn.focus_mode = Control.FOCUS_NONE
	_review_prev_btn.z_index = 200
	_review_prev_btn.visible = false
	_review_prev_btn.pressed.connect(_on_review_prev_pressed)
	add_child(_review_prev_btn)

	_review_next_btn = Button.new()
	_review_next_btn.text = "Next Fight ▶"
	_review_next_btn.tooltip_text = "Show the next fight in this flock chain"
	_review_next_btn.add_theme_font_size_override("font_size", 13)
	_review_next_btn.custom_minimum_size = Vector2(118, 30)
	_review_next_btn.focus_mode = Control.FOCUS_NONE
	_review_next_btn.z_index = 200
	_review_next_btn.visible = false
	_review_next_btn.pressed.connect(_on_review_next_pressed)
	add_child(_review_next_btn)

	_review_pagination_label = Label.new()
	_review_pagination_label.text = ""
	_review_pagination_label.add_theme_font_size_override("font_size", 13)
	_review_pagination_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	_review_pagination_label.z_index = 200
	_review_pagination_label.visible = false
	_review_pagination_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_review_pagination_label)
	call_deferred("_position_review_pagination_widgets")

	# v0.9.568 — Help coverage sweep. Floating top-LEFT ? button (mirrors the
	# review button's pattern but on the opposite corner; always visible
	# while the combat panel is up). Topic: combat_scene.
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	_help_button = HelpPanelScript.make_help_button("combat_scene", _help_panel)
	# v0.9.663 — compact it; it used to be large and cover the party card.
	_help_button.add_theme_font_size_override("font_size", 12)
	_help_button.custom_minimum_size = Vector2(66, 26)
	_help_button.z_index = 50
	_help_button.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_help_button)
	call_deferred("_position_help_button")


func _build_log_panel() -> Control:
	# v0.9.664 - scrollable combat-log panel (top of the LEFT column). Full log,
	# auto-stuck to the bottom; wheel/drag to scroll back through the fight.
	_battle_log_frame = PanelContainer.new()
	_battle_log_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battle_log_frame.size_flags_stretch_ratio = 2.0
	_battle_log_frame.custom_minimum_size = Vector2(0, 120)
	_battle_log_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	var _blb_sb := StyleBoxFlat.new()
	_blb_sb.bg_color = Color(0.02, 0.02, 0.03, 0.8)
	_blb_sb.border_color = Color(0.30, 0.26, 0.20, 1.0)
	_blb_sb.set_border_width_all(1)
	_blb_sb.set_corner_radius_all(4)
	_blb_sb.content_margin_left = 8
	_blb_sb.content_margin_right = 8
	_blb_sb.content_margin_top = 4
	_blb_sb.content_margin_bottom = 4
	_battle_log_frame.add_theme_stylebox_override("panel", _blb_sb)
	_battle_log_scroll = ScrollContainer.new()
	_battle_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_battle_log_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_battle_log_frame.add_child(_battle_log_scroll)
	_battle_log_band = RichTextLabel.new()
	_battle_log_band.bbcode_enabled = true
	_battle_log_band.fit_content = true
	_battle_log_band.scroll_active = false
	_battle_log_band.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_battle_log_band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_log_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_log_band.add_theme_font_size_override("normal_font_size", 14)
	_battle_log_scroll.add_child(_battle_log_band)
	return _battle_log_frame


func _build_scene_section_lufia() -> Control:
	# v0.9.664 - 2-column combat layout (user-directed):
	#   LEFT  = scrollable combat log (top) + player & companion cards (bottom)
	#   RIGHT = monster (top, its own zone - can't be covered) + ability hand (bottom)
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_stretch_ratio = 4.0
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_section = hbox
	# LEFT column: log on top, party cards below.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.add_theme_constant_override("separation", 8)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_build_log_panel())
	_make_party_boxes()
	# Player + companion in ONE card (white border / black bg), side by side with
	# minimal separation — matching the party-member cards. Kept on the left.
	var pc_card := PanelContainer.new()
	pc_card.name = "PlayerCompanionCard"
	pc_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pc_card.size_flags_vertical = Control.SIZE_SHRINK_END
	pc_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pcsb := StyleBoxFlat.new()
	pcsb.bg_color = Color(0.0, 0.0, 0.0, 0.88)
	pcsb.set_corner_radius_all(6)
	pcsb.set_border_width_all(1)
	pcsb.border_color = Color(1.0, 1.0, 1.0, 0.9)
	pcsb.content_margin_left = 6
	pcsb.content_margin_right = 6
	pcsb.content_margin_top = 4
	pcsb.content_margin_bottom = 4
	pc_card.add_theme_stylebox_override("panel", pcsb)
	var pc_row := HBoxContainer.new()
	pc_row.name = "PlayerCompanionRow"
	pc_row.add_theme_constant_override("separation", 2)
	pc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pc_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc_row.add_child(_player_party_box)
	pc_row.add_child(_companion_party_box)
	pc_card.add_child(pc_row)
	left.add_child(pc_card)
	hbox.add_child(left)
	_player_col = left
	# RIGHT column: monster on top (big), ability hand below.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.3  # 1.5 -> 1.3: Deck/Discard counter removed, so the hand needs less width; give it to the party column
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_monster_col = _build_monster_column()
	_monster_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_monster_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_monster_col.size_flags_stretch_ratio = 3.0
	right.add_child(_monster_col)
	var hand := _build_hand_strip()
	hand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(hand)
	hbox.add_child(right)
	# Co-op (#64 Slice 2) — FAR-RIGHT party column. Hidden by default: with a
	# hidden 3rd child the HBox distributes width between LEFT + RIGHT exactly as
	# before, so SOLO combat is unchanged. When shown (party of 2+), it takes its
	# stretch share and pushes the monster + cards leftward into the freed space.
	_party_column = VBoxContainer.new()
	_party_column.name = "PartyColumn"
	_party_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_party_column.size_flags_stretch_ratio = 1.9  # 1.2 -> 1.9: widened so the main-player-sized member cards fit on-screen instead of spilling off the right
	_party_column.add_theme_constant_override("separation", 4)
	_party_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_column.visible = false
	hbox.add_child(_party_column)
	return hbox
func _make_party_boxes() -> void:
	_player_party_box = _build_lufia_party_box(_build_lufia_player_box_content())
	_player_party_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_companion_party_box = _build_lufia_party_box(_build_lufia_companion_box_content())
	_companion_party_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _build_party_member_card() -> PanelContainer:
	"""MIRRORS the main player's box + companion box, at the SAME sizes, laid LEFT→RIGHT:
	  [member name + HP + resource bars] [member sprite portrait 168x138 (flipped)]
	  [companion name + HP bar] [companion art portrait 168x138 (font 1)].
	Each card is the NATURAL portrait height (COMPACT_PORTRAIT_H = 138) — NOT forced to
	share the column — so 4 cards stack, and the companion art renders in the EXACT box
	the player's own Kobold uses (fits identically; big arts clip the same as the player)."""
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.88)  # black background
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.9)  # white border
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	# 1) member stats — name, HP bar, resource bar (like the player's stats column).
	var mstats := VBoxContainer.new()
	mstats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mstats.alignment = BoxContainer.ALIGNMENT_CENTER
	mstats.add_theme_constant_override("separation", 3)
	mstats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mstats)
	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color("#8FE3FF"))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mstats.add_child(name_lbl)
	card.set_meta("name_lbl", name_lbl)
	var hp_bar := _make_hp_bar(Color("#FF4444"))
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(COMPACT_BAR_W, 10)
	mstats.add_child(hp_bar)
	card.set_meta("hp_bar", hp_bar)
	# v0.9.740 — Forcefield absorb overlay, the SAME purple fill the player's own HP bar
	# uses, so a shield reads identically whoever is carrying it.
	var shield_fill := Panel.new()
	shield_fill.name = "ShieldFill"
	shield_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shield_fill.anchor_top = 0
	shield_fill.anchor_bottom = 1
	shield_fill.offset_left = 0
	shield_fill.offset_top = 0
	shield_fill.offset_bottom = 0
	var shield_style := StyleBoxFlat.new()
	shield_style.bg_color = Color(0.6, 0.2, 0.8, 0.7)
	shield_fill.add_theme_stylebox_override("panel", shield_style)
	shield_fill.visible = false
	hp_bar.add_child(shield_fill)
	card.set_meta("shield_fill", shield_fill)
	var res_bar := _make_hp_bar(Color("#3A7BD5"))
	res_bar.show_percentage = false
	res_bar.custom_minimum_size = Vector2(COMPACT_BAR_W, 8)
	mstats.add_child(res_bar)
	card.set_meta("res_bar", res_bar)

	# 2) member sprite portrait — 168x138 box, sprite fills (keep-aspect), flipped H
	#    vs the player (party is RIGHT of the enemy -> faces LEFT toward it).
	var mport := Panel.new()
	mport.custom_minimum_size = Vector2(COMPACT_PLAYER_PORTRAIT_W, COMPACT_PORTRAIT_H)
	mport.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(0.06, 0.05, 0.10, 0.0)
	mport.add_theme_stylebox_override("panel", pbg)
	row.add_child(mport)
	var sprite := TextureRect.new()
	sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.flip_h = false
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mport.add_child(sprite)
	card.set_meta("sprite", sprite)

	# 3) companion stats — name + HP bar (like the player's companion stats).
	var cstats := VBoxContainer.new()
	cstats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cstats.alignment = BoxContainer.ALIGNMENT_CENTER
	cstats.add_theme_constant_override("separation", 3)
	cstats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cstats)
	var comp_name := Label.new()
	comp_name.add_theme_font_size_override("font_size", 11)
	comp_name.add_theme_color_override("font_color", Color("#B9A0FF"))
	comp_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cstats.add_child(comp_name)
	card.set_meta("comp_name", comp_name)
	var comp_hp := _make_hp_bar(Color("#66DD66"))
	comp_hp.show_percentage = false
	comp_hp.custom_minimum_size = Vector2(COMPACT_BAR_W, 8)
	cstats.add_child(comp_hp)
	card.set_meta("comp_hp", comp_hp)

	# 4) companion art portrait — EXACTLY the player's companion box: 168x138, clipped,
	#    full-rect font-1 ASCII. Renders identically to the Kobold.
	var cport := Panel.new()
	cport.custom_minimum_size = Vector2(COMPACT_PORTRAIT_W, COMPACT_PORTRAIT_H)
	cport.clip_contents = true
	cport.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(0.06, 0.05, 0.10, 0.0)
	cport.add_theme_stylebox_override("panel", cbg)
	row.add_child(cport)
	card.set_meta("comp_box", cport)
	# CenterContainer vertically + horizontally centers the (fit_content) art in the
	# box, so an art that fits shows centered, and one taller than 138 clips
	# SYMMETRICALLY (top+bottom) instead of losing its whole bottom.
	var ccenter := CenterContainer.new()
	ccenter.set_anchors_preset(Control.PRESET_FULL_RECT)
	ccenter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cport.add_child(ccenter)
	var comp_art := RichTextLabel.new()
	comp_art.bbcode_enabled = true
	comp_art.fit_content = true
	comp_art.scroll_active = false
	comp_art.autowrap_mode = TextServer.AUTOWRAP_OFF
	comp_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _mono_font:
		comp_art.add_theme_font_override("normal_font", _mono_font)
		comp_art.add_theme_font_override("bold_font", _mono_font)
		comp_art.add_theme_font_override("mono_font", _mono_font)
	ccenter.add_child(comp_art)
	card.set_meta("comp_art", comp_art)
	# The art label sits inside a CenterContainer, and a container re-lays out its child
	# every frame — which would fight a position tween. Lunges move the CENTER CONTAINER
	# instead; it lives in a plain Panel and keeps whatever position we give it.
	card.set_meta("comp_center", ccenter)

	return card


func set_party_members(members: Array, skip_bars: bool = false) -> void:
	"""Populate the co-op party column with OTHER members (caller excludes self).
	Empty → hide the column (solo stays unchanged). Reuses existing cards; builds
	more as needed up to PARTY_COLUMN_MAX_MEMBERS. Safe to call every round."""
	if _party_column == null or not is_instance_valid(_party_column):
		return
	_party_card_by_pid.clear()
	var shown: int = mini(members.size(), PARTY_COLUMN_MAX_MEMBERS)
	if shown <= 0:
		_party_column.visible = false
		for c in _party_member_cards:
			if is_instance_valid(c):
				c.visible = false
		return
	while _party_member_cards.size() < shown:
		var new_card := _build_party_member_card()
		_party_member_cards.append(new_card)
		_party_column.add_child(new_card)
	for i in range(_party_member_cards.size()):
		var card: PanelContainer = _party_member_cards[i]
		if not is_instance_valid(card):
			continue
		if i >= shown:
			card.visible = false
			continue
		card.visible = true
		var m: Dictionary = members[i] if members[i] is Dictionary else {}
		var pname := str(m.get("name", "Ally"))
		# #76 Slice 3 — remember which peer this card belongs to so per-actor FX can find
		# it (the server tags every log line with the acting / target peer id).
		var _mpid := int(m.get("peer_id", -1))
		card.set_meta("pid", _mpid)
		if _mpid != -1:
			_party_card_by_pid[_mpid] = card
		var cur := int(m.get("current_hp", m.get("hp", 0)))
		var mx := maxi(1, int(m.get("max_hp", 1)))
		var is_dead := bool(m.get("is_dead", false))
		var is_fled := bool(m.get("is_fled", false))
		var comp = m.get("companion", {})
		var name_lbl: Label = card.get_meta("name_lbl")
		var status := ""
		if is_dead:
			status = "  (DEAD)"
		elif is_fled:
			status = "  (FLED)"
		name_lbl.text = pname + status
		name_lbl.add_theme_color_override("font_color", Color("#FF6B6B") if is_dead else Color("#8FE3FF"))
		# Battler sprite (player system) — resolve id from stored battler_id, else
		# class+name; load idle frames for animation; tint; dim when KO'd/fled.
		var sprite: TextureRect = card.get_meta("sprite")
		var frames := _load_member_idle_frames(BattlerSprite.id_from_data(m))
		if not frames.is_empty():
			sprite.texture = frames[0]
			sprite.flip_h = false  # members are RIGHT of the enemy → face LEFT (native)
			sprite.self_modulate = BattlerSprite.tint_color(str(m.get("appearance_color", "")))
			sprite.visible = true
		else:
			sprite.visible = false
		sprite.modulate.a = 0.4 if (is_dead or is_fled) else 1.0
		# Equipment markers — region-tint shader + glyphs, the SAME treatment as the
		# player battler (see _show_player_battler). Applied when the member's equipped
		# gear is present in the snapshot; members reflect their own gear in combat.
		var m_eq = m.get("equipped", {})
		if m_eq is Dictionary and not m_eq.is_empty():
			var mk := EquipmentMarkers.markers_for(m_eq)
			sprite.material = EquipmentMarkers.build_tint_material(mk)
			EquipmentMarkers.spawn_glyphs(sprite, mk, null, 8)
		else:
			sprite.material = null
			for gch in sprite.get_children():
				if gch.has_meta("eq_glyph"):
					gch.queue_free()
		card.set_meta("idle_frames", frames)
		card.set_meta("frame", 0)
		card.set_meta("animate", not (is_dead or is_fled))
		# #76 Slice 3 — during a PACED round the bars are driven beat by beat from the
		# per-actor HP snapshots, so snapping them to the post-round values here would
		# spoil the sequence (everyone would already be at their final HP on beat 1).
		var hp_bar: ProgressBar = card.get_meta("hp_bar")
		hp_bar.max_value = mx
		if not skip_bars:
			hp_bar.value = clampi(cur, 0, mx)
		# v0.9.740 — Forcefield absorb. Shown as a fraction of max HP, capped at full width,
		# exactly like the player's own bar; the name carries the number so a big shield is
		# still legible when the overlay is pinned at 100%.
		var shield_fill = card.get_meta("shield_fill") if card.has_meta("shield_fill") else null
		var shield_val := int(m.get("forcefield_shield", 0))
		if shield_fill != null and is_instance_valid(shield_fill):
			if shield_val > 0 and not (is_dead or is_fled):
				shield_fill.anchor_right = minf(1.0, float(shield_val) / float(mx))
				shield_fill.offset_right = 0
				shield_fill.visible = true
				name_lbl.text = "%s%s  [%d]" % [pname, status, shield_val]
			else:
				shield_fill.visible = false
		# Member resource bar — the class's PRIMARY resource. Real data sends
		# resource_cur/resource_max (server-picked per class); the admin preview
		# samples fall back to current_mana/etc.
		var res_bar: ProgressBar = card.get_meta("res_bar")
		var res_cur := int(m.get("resource_cur", m.get("current_mana", m.get("current_stamina", m.get("current_energy", 0)))))
		var res_max := int(m.get("resource_max", m.get("max_mana", m.get("max_stamina", m.get("max_energy", 0)))))
		if res_max > 0:
			res_bar.max_value = res_max
			if not skip_bars:
				res_bar.value = clampi(res_cur, 0, res_max)
			res_bar.visible = true
		else:
			res_bar.visible = false
		# Companion name + HP bar (like the player's companion stats).
		var comp_name: Label = card.get_meta("comp_name")
		var comp_disp_name := str(comp.get("name", "")) if comp is Dictionary else ""
		comp_name.text = comp_disp_name
		comp_name.visible = comp_disp_name != ""
		var comp_hp: ProgressBar = card.get_meta("comp_hp")
		var comp_hp_cur := int(comp.get("combat_hp", comp.get("current_hp", 0))) if comp is Dictionary else 0
		var comp_hp_max := int(comp.get("max_hp", 0)) if comp is Dictionary else 0
		if comp is Dictionary and not comp.is_empty() and comp_hp_max > 0:
			comp_hp.max_value = comp_hp_max
			if not skip_bars:
				comp_hp.value = clampi(comp_hp_cur, 0, comp_hp_max)
			comp_hp.visible = true
		else:
			comp_hp.visible = false
		# Companion — crisp font-1 ASCII (like the Kobold), centered in its clip box
		# by the CenterContainer. NO scaling (no blur); if it exceeds the card height
		# it clips symmetrically. Whole for anything that fits the card row.
		var comp_box: Panel = card.get_meta("comp_box")
		var comp_art: RichTextLabel = card.get_meta("comp_art")
		var comp_type := str(comp.get("monster_type", "")) if comp is Dictionary else ""
		var clines: Array = []
		if comp_type != "" and client_ref and client_ref.has_method("_get_companion_art_lines"):
			clines = client_ref._get_companion_art_lines(comp_type, pname)
		if clines.is_empty() and comp_type != "":
			var raw := MonsterArt.get_monster_ascii_art(comp_type)
			if raw != "":
				clines = raw.split("\n")
		if not clines.is_empty():
			# #76 — apply the SAME variant recolor + border the PLAYER's own companion gets
			# (see _build_lufia_companion_box_content ~L5625). Without this, teammates'
			# companions rendered in the flat default art colour instead of their variant
			# hue, so a Crimson Wolf didn't look like it does out of battle.
			var raw_art := "\n".join(clines)
			if client_ref and client_ref.has_method("_recolor_ascii_art_pattern") and comp is Dictionary:
				var v_color := str(comp.get("variant_color", "#FFFFFF"))
				var v_color2 := str(comp.get("variant_color2", ""))
				var v_pattern := str(comp.get("variant_pattern", "solid"))
				if client_ref.has_method("_ensure_readable_color"):
					v_color = client_ref._ensure_readable_color(v_color)
					if v_color2 != "":
						v_color2 = client_ref._ensure_readable_color(v_color2)
				v_color = _battle_lift_color(v_color)
				if v_color2 != "":
					v_color2 = _battle_lift_color(v_color2)
				raw_art = client_ref._recolor_ascii_art_pattern(raw_art, v_color, v_color2, v_pattern)
			var _bt := int(comp.get("border_tier", 0)) if comp is Dictionary else 0
			var _bc := ""
			match _bt:
				1: _bc = "#FFFFFF"
				2: _bc = "#1EFF00"
				3: _bc = "#0070DD"
				4: _bc = "#A335EE"
				5: _bc = "#FF8000"
				6: _bc = "#FFD700"
			if _bc != "":
				raw_art = MonsterArt.apply_variant_border(raw_art, _bc)
			comp_art.text = "[center][font_size=%d]%s[/font_size][/center]" % [COMPACT_ASCII_FONT_SIZE, raw_art]
			comp_art.modulate.a = 0.4 if (is_dead or is_fled) else 1.0
			comp_art.scale = Vector2.ONE
			comp_box.visible = true
		else:
			comp_box.visible = false
	_ensure_battler_timer()
	_party_column.visible = true


# ─────────────────────────────────────────────────────────────────────────────
# #76 Slice 3 — PARTY-CARD FX. A teammate's attack has to animate on THEIR card, and a
# monster hit on a teammate has to land on THEIR portrait. The solo text heuristics
# (`_classify_combat_actor`) cannot drive this — a teammate's log line is 3rd person — so
# the server tags each line with actor/target peer ids and the client routes here.
# Members sit RIGHT of the enemy and face LEFT, so they lunge -X (toward it).
# ─────────────────────────────────────────────────────────────────────────────
# v0.9.739 — how far a non-acting party card is dimmed during another actor's beat.
# Dim enough to direct the eye, light enough that HP bars stay readable.
const PARTY_DIM_COLOR: Color = Color(0.62, 0.62, 0.68, 1.0)


func party_card_for_pid(pid: int) -> PanelContainer:
	var card = _party_card_by_pid.get(pid, null)
	if card == null or not is_instance_valid(card) or not card.visible:
		return null
	return card

func spotlight_party_actor(pid: int, include_local: bool = true) -> void:
	"""v0.9.739 — co-op readability. With 4 members, their companions and the monster all
	acting inside one round, the player could not tell WHICH card a beat belonged to. Dim
	everyone except the combatant this beat belongs to — the one acting, or on a monster
	beat the one being struck — so the eye is already on the right card when the lunge,
	the trail and the damage number fire. Purely visual; resolution never depends on it.

	pid == -1 means the LOCAL player is the one lit: every teammate card dims and our own
	column stays bright. The monster's art is deliberately left alone — flash_monster and
	the victory FX own its modulate, and dimming here would fight them."""
	for card in _party_member_cards:
		if card == null or not is_instance_valid(card):
			continue
		var card_pid: int = int(card.get_meta("pid", -1))
		card.modulate = Color(1, 1, 1, 1) if card_pid == pid else PARTY_DIM_COLOR
	if include_local and _player_party_box and is_instance_valid(_player_party_box):
		_player_party_box.modulate = Color(1, 1, 1, 1) if pid == -1 else PARTY_DIM_COLOR


func clear_party_spotlight() -> void:
	"""Restore every combatant to full brightness (round over / combat over)."""
	for card in _party_member_cards:
		if card != null and is_instance_valid(card):
			card.modulate = Color(1, 1, 1, 1)
	if _player_party_box and is_instance_valid(_player_party_box):
		_player_party_box.modulate = Color(1, 1, 1, 1)


func _party_fx_lunge(node: Control) -> void:
	if node == null or not is_instance_valid(node):
		return
	var key := node.get_instance_id()
	var prev = _party_card_tweens.get(key, null)
	if prev != null and prev is Tween and prev.is_valid():
		prev.kill()
	# Capture the resting position ONCE. Re-reading it mid-lunge (or after an interrupted
	# tween) would let the card drift a little further left on every attack.
	if not node.has_meta("fx_baseline"):
		node.set_meta("fx_baseline", node.position)
	var base: Vector2 = node.get_meta("fx_baseline")
	node.position = base
	var t := create_tween()
	_party_card_tweens[key] = t
	t.tween_property(node, "position", base + Vector2(-LUNGE_DISTANCE, 0), LUNGE_DURATION)
	t.tween_property(node, "position", base, LUNGE_DURATION)

func lunge_party_member(pid: int) -> void:
	var card := party_card_for_pid(pid)
	if card == null:
		return
	_party_fx_lunge(card.get_meta("sprite") as Control)

func lunge_party_companion(pid: int) -> void:
	var card := party_card_for_pid(pid)
	if card == null:
		return
	_party_fx_lunge(card.get_meta("comp_center") as Control)

func _party_node_anchor(node: Control) -> Vector2:
	var r := node.get_global_rect()
	return r.position + Vector2(r.size.x * 0.5, r.size.y * 0.3)

func party_member_attacker_anchor(pid: int) -> Vector2:
	"""Where a teammate's damage number launches FROM (their sprite), so the number
	visibly travels from whoever dealt it — same cue the player's own attacks use."""
	var card := party_card_for_pid(pid)
	if card == null:
		return Vector2(INF, INF)
	var n := card.get_meta("sprite") as Control
	if n == null or not is_instance_valid(n):
		return Vector2(INF, INF)
	return _party_node_anchor(n)

func party_companion_attacker_anchor(pid: int) -> Vector2:
	var card := party_card_for_pid(pid)
	if card == null:
		return Vector2(INF, INF)
	var n := card.get_meta("comp_box") as Control
	if n == null or not is_instance_valid(n):
		return Vector2(INF, INF)
	return _party_node_anchor(n)

func show_damage_on_party_member(pid: int, amount: int, is_crit: bool = false) -> void:
	var card := party_card_for_pid(pid)
	if card == null:
		return
	var n := card.get_meta("sprite") as Control
	if n == null or not is_instance_valid(n):
		return
	# v0.9.739 — hold the number until the monster's trail actually reaches this card.
	var wait := _travel_pending_s(pid)
	_note_number_visible(pid, wait)
	if wait > 0.0:
		var t := get_tree().create_timer(wait)
		t.timeout.connect(func():
			if is_instance_valid(n):
				_spawn_damage_label(_party_node_anchor(n), amount, is_crit, "monster", true))
		return
	_spawn_damage_label(_party_node_anchor(n), amount, is_crit, "monster", true)

func show_damage_on_party_companion(pid: int, amount: int, is_crit: bool = false) -> void:
	var card := party_card_for_pid(pid)
	if card == null:
		return
	var n := card.get_meta("comp_box") as Control
	if n == null or not is_instance_valid(n):
		return
	_spawn_damage_label(_party_node_anchor(n), amount, is_crit, "monster", true)

func show_miss_on_party_member(pid: int) -> void:
	var card := party_card_for_pid(pid)
	if card == null:
		return
	var n := card.get_meta("sprite") as Control
	if n == null or not is_instance_valid(n):
		return
	_spawn_miss_label(_party_node_anchor(n))

func update_party_member_hp(pid: int, hp: int, max_hp: int) -> void:
	# v0.9.739 — same rule as every other bar: hold the drop until the monster's trail
	# actually reaches this card, so the number and the bar move together.
	_apply_bar_after_travel(pid, func():
		var card := party_card_for_pid(pid)
		if card == null:
			return
		var bar := card.get_meta("hp_bar") as ProgressBar
		if bar == null or not is_instance_valid(bar) or max_hp <= 0:
			return
		bar.max_value = max_hp
		_animate_bar_value(bar, clampf(float(hp), 0.0, float(max_hp))))

func update_party_companion_hp(pid: int, hp: int, max_hp: int) -> void:
	_apply_bar_after_travel(pid, func():
		var card := party_card_for_pid(pid)
		if card == null:
			return
		var bar := card.get_meta("comp_hp") as ProgressBar
		if bar == null or not is_instance_valid(bar) or max_hp <= 0 or not bar.visible:
			return
		bar.max_value = max_hp
		_animate_bar_value(bar, clampf(float(hp), 0.0, float(max_hp))))


func _load_member_idle_frames(id: String) -> Array:
	"""Load a party member's idle animation frames (idle_0..2) for the battler id,
	falling back to the single idle_0 texture. Mirrors the player's frame loader."""
	var frames: Array = []
	if id == "":
		return frames
	var p := BattlerSprite.idle_path_by_id(id)
	if p == "":
		return frames
	var folder := p.get_base_dir() + "/"
	for i in range(3):
		var it = load(folder + "idle_%d.png" % i)
		if it != null:
			frames.append(it)
	if frames.is_empty():
		var single := BattlerSprite.idle_texture_by_id(id)
		if single != null:
			frames.append(single)
	return frames


func _advance_party_member_frames() -> void:
	"""Cycle each live party member's battler idle frame (called from the shared
	battler timer). KO'd/fled members are frozen (animate meta = false)."""
	if _party_column == null or not is_instance_valid(_party_column) or not _party_column.visible:
		return
	for card in _party_member_cards:
		if not is_instance_valid(card) or not card.visible:
			continue
		if not bool(card.get_meta("animate", true)):
			continue
		var frames: Array = card.get_meta("idle_frames", [])
		if frames.size() <= 1:
			continue
		var sprite: TextureRect = card.get_meta("sprite")
		if sprite == null or not is_instance_valid(sprite) or not sprite.visible:
			continue
		var fsz: int = frames.size()
		var fr: int = (int(card.get_meta("frame", 0)) + 1) % fsz
		card.set_meta("frame", fr)
		sprite.texture = frames[fr]


func _ensure_comp_vp() -> void:
	if _comp_vp and is_instance_valid(_comp_vp):
		return
	_comp_vp = SubViewport.new()
	_comp_vp.size = Vector2i(240, 220)
	_comp_vp.transparent_bg = true
	_comp_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_comp_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_comp_vp)
	_comp_vp_label = RichTextLabel.new()
	_comp_vp_label.bbcode_enabled = true
	_comp_vp_label.fit_content = true
	_comp_vp_label.scroll_active = false
	_comp_vp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if _mono_font:
		_comp_vp_label.add_theme_font_override("normal_font", _mono_font)
		_comp_vp_label.add_theme_font_override("bold_font", _mono_font)
		_comp_vp_label.add_theme_font_override("mono_font", _mono_font)
	_comp_vp.add_child(_comp_vp_label)


func _companion_texture(monster_type: String) -> Texture2D:
	"""Rasterize a companion's monster ASCII into an ImageTexture (cached). Rendered
	at a natural font in an offscreen SubViewport, then displayed scaled-to-fit — so
	any-size art becomes a sprite-sized figure. Async (2 render frames on first build)."""
	if _comp_tex_cache.has(monster_type):
		return _comp_tex_cache[monster_type]
	var cart := MonsterArt.get_monster_ascii_art(monster_type)
	if cart == "":
		return null
	_ensure_comp_vp()
	_comp_vp_label.position = Vector2.ZERO
	_comp_vp_label.text = "[font_size=8]%s[/font_size]" % cart
	await get_tree().process_frame
	var content := _comp_vp_label.get_combined_minimum_size()
	_comp_vp.size = Vector2i(maxi(16, int(ceil(content.x))), maxi(16, int(ceil(content.y))))
	_comp_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _comp_vp.get_texture().get_image()
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_comp_tex_cache[monster_type] = tex
	return tex


func _apply_companion_texture(rect: TextureRect, monster_type: String, dim: bool) -> void:
	"""Fire-and-forget: fetch (or build) the companion texture and drop it into the
	card's TextureRect when ready. Safe if the rect is freed before the await returns."""
	var tex: Texture2D = await _companion_texture(monster_type)
	if rect == null or not is_instance_valid(rect):
		return
	if tex != null:
		rect.texture = tex
		rect.modulate.a = 0.4 if dim else 1.0
		rect.visible = true
	else:
		rect.visible = false


func start_action_phase() -> void:
	"""v0.9.406 — Lufia II battlefield reveal. (1) The entire party box row
	fades out at the bottom; (2) a separate 'battlefield' overlay fades in
	at a different on-screen position, showing the same player + companion
	ASCII art at a larger size — characters appear ON the battlefield, not
	in the same place as the box. end_action_phase reverses both.

	v0.9.412 — also hide the running-totals banner, hand strip, and status
	strip while in the FX scene. Frees vertical room for the overlay so the
	bigger ASCII blocks don't get cut off by adjacent UI."""
	# COMBAT REDESIGN (2026-08-20): the floating overlay is retired — it caused
	# the resolution-dependent overlap/scatter. Combat now stays in the single
	# container layout (FX on the in-scene visuals, log in the band). No-op.
	if _overlay_retired:
		return
	if _action_phase_active:
		return
	_action_phase_active = true
	# v0.9.439 — hide Review FX button while overlay is showing (pause button on
	# the overlay handles input there).
	if _review_button and is_instance_valid(_review_button):
		_review_button.visible = false
	_ensure_battlefield_overlay()
	_populate_battlefield_overlay()
	# v0.9.593 — when the persistent-FX flag is already true (Round 2+ of a
	# combat), the overlay and strips are both visible from the prior frame's
	# stable state. Skip the fade-in tween + strip-hide so the player doesn't
	# see flicker. Only the internal overlay refresh (_populate above) matters.
	if _fx_persistent_active:
		return
	# v0.9.412 — collapse non-essential strips so the overlay has more room.
	# v0.9.425 — also hide the totals' wrapping PanelContainer so its yellow-gold
	# border doesn't draw underneath the FX scene (hiding only the inner HBox
	# left the bordered frame on screen).
	if _totals_strip_frame and is_instance_valid(_totals_strip_frame):
		_totals_strip_frame.visible = false
	if _totals_strip and is_instance_valid(_totals_strip):
		_totals_strip.visible = false
	if _hand_strip and is_instance_valid(_hand_strip):
		_hand_strip.visible = false
	if _status_strip and is_instance_valid(_status_strip):
		_status_strip.visible = false
	_kill_action_phase_tween()
	_action_phase_tween = create_tween().set_parallel(true)
	# Fade the whole party row down + out. v0.9.439: 0.20 → 0.12.
	if _player_col and is_instance_valid(_player_col):
		_action_phase_tween.tween_property(_player_col, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Reposition overlay after the strips collapse so the new available
	# space is accounted for.
	call_deferred("_position_battlefield_overlay")
	# Reveal the battlefield overlay: starts above its rest position and
	# slides down into place with a fade-in. v0.9.439: 0.25/0.28 → 0.15/0.18.
	if _battlefield_overlay and is_instance_valid(_battlefield_overlay):
		_battlefield_overlay.visible = true
		_battlefield_overlay.modulate.a = 0.0
		_battlefield_overlay.position.y = _battlefield_overlay_rest_y - 40.0
		_action_phase_tween.tween_property(_battlefield_overlay, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_action_phase_tween.tween_property(_battlefield_overlay, "position:y", _battlefield_overlay_rest_y, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func end_action_phase() -> void:
	"""v0.9.406 — hide the battlefield overlay and slide the party row back.
	v0.9.412 — restore the running-totals / hand / status strips that were
	collapsed during the action phase.
	v0.9.593 — once Round 1's action phase ends, switch into persistent-FX
	mode: keep the overlay visible for the rest of combat (hand strip + totals
	+ status come back ALONGSIDE the overlay, not instead of it). Subsequent
	`end_action_phase` calls during the same combat are no-ops on the visual
	side. Combat-end paths use `_force_end_action_phase()` to actually tear
	down the overlay."""
	_cancel_action_phase_timer()
	if not _action_phase_active:
		return
	_action_phase_active = false
	# v0.9.593 — persistent mode: restore strips so the player sees their hand
	# cards in the normal location, but keep the overlay visible. The party row
	# (_player_col) stays faded since the overlay represents the player on the
	# battlefield. No tween needed — just toggle visibility.
	if not _fx_persistent_active:
		_fx_persistent_active = true
		if _totals_strip_frame and is_instance_valid(_totals_strip_frame):
			_totals_strip_frame.visible = true
		if _totals_strip and is_instance_valid(_totals_strip):
			_totals_strip.visible = true
		if _hand_strip and is_instance_valid(_hand_strip):
			_hand_strip.visible = true
		if _status_strip and is_instance_valid(_status_strip):
			_status_strip.visible = true
		# Review FX button is unnecessary while the overlay is always on
		# (between rounds in persistent-FX mode). v0.9.621 — exception:
		# during the victory interlude the button is exactly how the player
		# accesses Review FX, so leave it alone. v0.9.619 made
		# _update_review_button_visibility show the button during victory;
		# but end_action_phase fires AFTER show_victory_card (queue-drain
		# order), and was overwriting that to false. Player report:
		# "Review Damage pops up for a second on the Victory screen in the
		# top right but disappears before the player can click it."
		if _review_button and is_instance_valid(_review_button) and not _victory_interlude_active:
			_review_button.visible = false
		return
	# Already persistent — _action_phase_active was a transient round flag,
	# nothing to do visually.
	return

func hide_fx_overlay_only() -> void:
	"""v0.9.623 — tear down the FX battlefield overlay WITHOUT restoring the
	pre-FX Lufia layout (party row). Used by the loot-panel close path when
	transitioning straight to the victory card. _force_end_action_phase
	tweens _player_col modulate back to 1.0, which makes the pre-FX scene
	visible underneath the victory card — and when the player dismisses
	the card, the pre-FX layout is exposed. Player report v0.9.622 fix:
	'No I'm seeing the Start of combat Screen stuck up there like it
	swapped scenes (not the fx one).'

	This variant clears just the overlay state. The pre-FX layout stays
	hidden (modulate 0); reset_for_new_combat handles the full restore
	when a fresh combat starts."""
	_cancel_action_phase_timer()
	_fx_persistent_active = false
	_action_phase_active = false
	_kill_action_phase_tween()
	if _battlefield_overlay and is_instance_valid(_battlefield_overlay):
		_battlefield_overlay.visible = false
		_battlefield_overlay.modulate.a = 0.0
	# Strip restoration is OK to do — they sit alongside the victory card
	# and don't have a "fade in" tween that would flash visually.
	if _totals_strip_frame and is_instance_valid(_totals_strip_frame):
		_totals_strip_frame.visible = true
	if _totals_strip and is_instance_valid(_totals_strip):
		_totals_strip.visible = true
	if _hand_strip and is_instance_valid(_hand_strip):
		_hand_strip.visible = true
	if _status_strip and is_instance_valid(_status_strip):
		_status_strip.visible = true
	call_deferred("_update_review_button_visibility")


func reset_for_new_combat() -> void:
	"""v0.9.593 — called by client.gd when a new combat starts so any persistent
	FX state from a previous fight doesn't leak in. Forces a clean slate: flag
	off, overlay hidden, _action_phase_active false, strips visible. The next
	start_action_phase call will fire the normal Round 1 fade-in transition.

	v0.9.624 — ALSO dismiss any stale victory interlude. Edge case: with
	autoskip loot enabled + fast movement, the player can trigger a new
	random encounter in the same frame as victory dismissal. The
	_process safety net at client.gd:2802 skips dismissal when
	_now_in_combat is true, so _victory_interlude_active gets stuck.
	Result: new combat shows FX overlay AND Review Damage button stays
	visible (v0.9.621 honored the stuck flag), making the screen feel
	frozen. Player report: 'this is stuck on my screen and overlays
	everything... only clears if I get in a new combat... Auto-Skip
	combat loot reveal on if it matters.' Clearing the victory interlude
	here ensures every new combat starts from a clean slate."""
	if _victory_card_overlay and is_instance_valid(_victory_card_overlay) and _victory_card_overlay.visible:
		_victory_card_overlay.visible = false
	if _log_scroll and is_instance_valid(_log_scroll):
		_log_scroll.visible = true
	_victory_interlude_active = false
	_in_review_phase = false
	_fx_persistent_active = false
	_action_phase_active = false
	_cancel_action_phase_timer()
	_kill_action_phase_tween()
	if _battlefield_overlay and is_instance_valid(_battlefield_overlay):
		_battlefield_overlay.visible = false
		_battlefield_overlay.modulate.a = 0.0
	if _player_col and is_instance_valid(_player_col):
		_player_col.modulate.a = 1.0
	if _totals_strip_frame and is_instance_valid(_totals_strip_frame):
		_totals_strip_frame.visible = true
	if _totals_strip and is_instance_valid(_totals_strip):
		_totals_strip.visible = true
	if _hand_strip and is_instance_valid(_hand_strip):
		_hand_strip.visible = true
	if _status_strip and is_instance_valid(_status_strip):
		_status_strip.visible = true

func _force_end_action_phase() -> void:
	"""v0.9.593 — actually tear down the battlefield overlay. Called only from
	combat-end paths (combat_end, party_combat_end, continue acknowledge). This
	is the path that used to be the normal `end_action_phase` before the
	persistent-FX mode landed — it does the full overlay-fade + party-row
	restore + Review FX button reappear so victory / defeat / flee can
	transition cleanly back to the action UI."""
	_cancel_action_phase_timer()
	_fx_persistent_active = false
	if not _action_phase_active and not (_battlefield_overlay and is_instance_valid(_battlefield_overlay) and _battlefield_overlay.visible):
		return
	_action_phase_active = false
	# v0.9.439 — overlay is fading out; show Review FX button so the player can
	# re-enter at will. Visibility helper also gates on whether any log content
	# exists, so the button stays hidden on the very first FX scene.
	call_deferred("_update_review_button_visibility")
	# Restore the strips that were hidden in start_action_phase.
	if _totals_strip_frame and is_instance_valid(_totals_strip_frame):
		_totals_strip_frame.visible = true
	if _totals_strip and is_instance_valid(_totals_strip):
		_totals_strip.visible = true
	if _hand_strip and is_instance_valid(_hand_strip):
		_hand_strip.visible = true
	if _status_strip and is_instance_valid(_status_strip):
		_status_strip.visible = true
	_kill_action_phase_tween()
	_action_phase_tween = create_tween().set_parallel(true)
	# v0.9.439: 0.25/0.22 → 0.15/0.13. Faster transition back to action UI.
	if _player_col and is_instance_valid(_player_col):
		_action_phase_tween.tween_property(_player_col, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _battlefield_overlay and is_instance_valid(_battlefield_overlay):
		_action_phase_tween.tween_property(_battlefield_overlay, "modulate:a", 0.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_action_phase_tween.tween_property(_battlefield_overlay, "position:y", _battlefield_overlay_rest_y - 40.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
# v0.9.569 — _overlay_player_resource_bar removed. Placeholder was assigned
# null and the consumer block (animate_overlay_state) was unreachable.
var _overlay_player_name: Label = null
# v0.9.601 — extras to mirror pre-FX info into the FX overlay: HP cur/max
# text, resource bar (mana/stamina/energy), deck/hand/discard counts.
var _overlay_player_hp_text: Label = null
var _overlay_player_resource_bar: ProgressBar = null
var _overlay_player_resource_text: Label = null
var _overlay_player_deck_label: Label = null
var _overlay_companion_block: Control = null
var _overlay_companion_ascii: RichTextLabel = null
var _overlay_companion_hp_bar: ProgressBar = null
var _overlay_companion_name: Label = null
# v0.9.601 — companion HP text + XP bar/text to match the pre-FX box.
var _overlay_companion_hp_text: Label = null
var _overlay_companion_xp_bar: ProgressBar = null
var _overlay_companion_xp_text: Label = null
var _battlefield_overlay_rest_y: float = 0.0
var _overlay_player_block_baseline: Vector2 = Vector2.ZERO
var _overlay_companion_block_baseline: Vector2 = Vector2.ZERO

# v0.9.415 — per-actor log strips during action phase. Three small scrolling
# regions inside the overlay so each actor's actions appear over their own
# zone. Single combat log (_log_label) still receives everything and is the
# canonical record for non-overlay layouts / [L] legacy view.
const OVERLAY_LOG_LINE_LIMIT := 30  # v0.9.439: 5 → 30. Strips are scrollable during Review FX.
# v0.9.418 — pause button in the top-right corner of the FX overlay so the
# player can freeze the message-drain pacing and read what just happened.
# Connected to client.toggle_combat_pause() via client_ref.
var _pause_button: Button = null
# v0.9.568 — Help coverage sweep. Floating top-LEFT ? button (mirrors the
# review button's pattern but on the opposite corner; always visible while
# the combat panel is up). Reusable HelpPanel attached.
var _help_panel: Control = null
var _help_button: Button = null
# v0.9.439 — Review FX. When in hand-selection (overlay hidden), this button
# (top-right of the combat panel root) lets the player re-enter the FX scene
# with the latest round's per-actor strips scrollable for re-reading.
var _review_button: Button = null
var _in_review_phase: bool = false
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

	# v0.9.633 — monster strip is the only externally-positioned strip now.
	# Player + companion strips moved INTO their respective character blocks
	# (as the first child of each block's VBoxContainer with ALIGNMENT_END)
	# so they bottom-align with their ASCII art naturally.
	_overlay_monster_log = _build_overlay_log_label("center")
	_battlefield_overlay.add_child(_overlay_monster_log)

	# Player block — VBox with strip + ASCII + info, bottom-aligned.
	_overlay_player_block = _build_overlay_character_block(true)
	_battlefield_overlay.add_child(_overlay_player_block)
	# Companion block — same structure as player block.
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
	there. Panel just renders the button and updates its label.
	v0.9.439 — when in Review FX, this button doubles as 'Back to Hand'."""
	if _in_review_phase:
		end_review_phase()
		return
	if client_ref != null and client_ref.has_method("toggle_combat_pause"):
		client_ref.toggle_combat_pause()


func _on_review_button_pressed() -> void:
	"""v0.9.439 — re-enter FX overlay so the player can re-read this fight's
	per-actor strips. Strips become mouse-scrollable in review mode."""
	start_review_phase()


func start_review_phase() -> void:
	"""v0.9.439 — re-show the FX scene from the action-selection view. Re-uses
	start_action_phase's visual transition. Strips switch to mouse-scrollable.
	The pause button doubles as 'Back to Hand' until end_review_phase fires.

	v0.9.610 — hide the victory card overlay while review is active. Without
	this, the battlefield overlay (z=100) draws behind the victory card
	(z=150) and the user sees no visible change when clicking Review FX.
	Card is restored in end_review_phase. Player report: 'The Review Damage
	button doesn't seem to work, it's supposed to take the player back to
	the FX screen.'"""
	if _action_phase_active:
		# Already on the FX scene from a real action phase — nothing to do.
		return
	_in_review_phase = true
	# Show the back button instead of pause/resume, since there's no queue to
	# pause during review.
	_set_back_button_label()
	# Make per-actor strips mouse-scrollable. Default was MOUSE_FILTER_IGNORE
	# so events passed through to the parent; STOP captures wheel + scrollbar.
	_set_overlay_strips_scrollable(true)
	# v0.9.610 — temporarily hide the victory card so the FX overlay reads.
	# We DON'T touch _victory_interlude_active so the safety net + L-key
	# state still know the card is logically up; just the rendered overlay
	# is hidden.
	if _victory_card_overlay and is_instance_valid(_victory_card_overlay):
		_victory_card_overlay.visible = false
	# v0.9.611 — snapshot the current (live) fight's overlay strips before
	# entering review, so paginating BACK to "current" can restore them.
	_review_live_player_lines = _overlay_player_log_lines.duplicate()
	_review_live_monster_lines = _overlay_monster_log_lines.duplicate()
	_review_live_companion_lines = _overlay_companion_log_lines.duplicate()
	_review_fight_index = -1
	start_action_phase()
	# Hide the review-launch button while in review.
	if _review_button and is_instance_valid(_review_button):
		_review_button.visible = false
	# v0.9.611 — show the pagination row + label if flock chain has >1 fight.
	if _flock_history.size() > 0:
		if _review_prev_btn and is_instance_valid(_review_prev_btn):
			_review_prev_btn.visible = true
		if _review_next_btn and is_instance_valid(_review_next_btn):
			_review_next_btn.visible = true
		if _review_pagination_label and is_instance_valid(_review_pagination_label):
			_review_pagination_label.visible = true
		_position_review_pagination_widgets()
		_update_review_pagination_label()


func end_review_phase() -> void:
	"""v0.9.439 — exit Review FX. Restores the hand-selection view.
	v0.9.610 — also restore the victory card overlay if the player launched
	review FROM the victory screen (interlude still active)."""
	if not _in_review_phase:
		return
	_in_review_phase = false
	# Restore strip mouse_filter so future FX firing through them isn't
	# blocked by the scrollable strip swallowing events.
	_set_overlay_strips_scrollable(false)
	# Restore pause button label so the next real action phase shows ⏸ PAUSE.
	set_pause_button_label(false)
	end_action_phase()
	# v0.9.610 — if the victory card was hidden by start_review_phase,
	# restore it now. _victory_interlude_active stays true the whole time so
	# this is the right re-show signal.
	if _victory_interlude_active and _victory_card_overlay and is_instance_valid(_victory_card_overlay):
		_victory_card_overlay.visible = true
	# v0.9.611 — restore the live-fight strip lines and hide pagination row.
	# Snapshot was taken in start_review_phase. We DON'T tear down the
	# arrays — if combat resumes (e.g., they hit Continue), the new
	# fight's clear_log handles the swap.
	if _review_fight_index != -1:
		_overlay_player_log_lines = _review_live_player_lines.duplicate()
		_overlay_monster_log_lines = _review_live_monster_lines.duplicate()
		_overlay_companion_log_lines = _review_live_companion_lines.duplicate()
		_refresh_overlay_strips_from_lines()
		_review_fight_index = -1
	if _review_prev_btn and is_instance_valid(_review_prev_btn):
		_review_prev_btn.visible = false
	if _review_next_btn and is_instance_valid(_review_next_btn):
		_review_next_btn.visible = false
	if _review_pagination_label and is_instance_valid(_review_pagination_label):
		_review_pagination_label.visible = false
	# Show the review button again so the player can re-enter at will.
	_update_review_button_visibility()


func _set_overlay_strips_scrollable(enabled: bool) -> void:
	"""v0.9.439 — toggle the per-actor strip mouse_filter. Strips are
	IGNORE by default (events pass through) so they don't eat lunge clicks
	or popup interactions. In review mode they're STOP so the player can
	scroll the wheel / drag the scrollbar to re-read older lines.

	v0.9.440 — scroll_following stays TRUE in both modes:
	  • During review the queue is empty so no new lines append → scroll
	    position is whatever the user sets (manual scroll is free).
	  • Re-entering action phase (player pressed Back then fired an ability)
	    new lines append and the strip auto-scrolls back to newest.
	So we get autoscroll-to-newest by default + manual-scroll-when-wanted
	without touching the follow flag."""
	var filter := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if _overlay_player_log and is_instance_valid(_overlay_player_log):
		_overlay_player_log.mouse_filter = filter
		_overlay_player_log.scroll_following = true
	if _overlay_monster_log and is_instance_valid(_overlay_monster_log):
		_overlay_monster_log.mouse_filter = filter
		_overlay_monster_log.scroll_following = true
	if _overlay_companion_log and is_instance_valid(_overlay_companion_log):
		_overlay_companion_log.mouse_filter = filter
		_overlay_companion_log.scroll_following = true


func _set_back_button_label() -> void:
	"""v0.9.439 — show 'Back to Hand' on the pause button while in review."""
	if _pause_button == null or not is_instance_valid(_pause_button):
		return
	_pause_button.text = "← Back"
	_pause_button.tooltip_text = "Exit Review FX and return to action selection"


func _position_review_button() -> void:
	"""v0.9.439 — anchor Review FX button to the top-right of the combat panel.
	Mirrors the overlay pause button position so they swap cleanly."""
	if _review_button == null or not is_instance_valid(_review_button):
		return
	var panel_w: float = size.x
	var btn_w: float = _review_button.custom_minimum_size.x
	var btn_h: float = _review_button.custom_minimum_size.y
	_review_button.size = Vector2(btn_w, btn_h)
	# v0.9.663 — stack below the (top-right) help button so they don't overlap.
	var _help_h: float = _help_button.custom_minimum_size.y if (_help_button and is_instance_valid(_help_button)) else 0.0
	var _review_y: float = 6.0 + (_help_h + 6.0 if _help_h > 0.0 else 0.0)
	_review_button.position = Vector2(maxf(0.0, panel_w - btn_w - 8.0), _review_y)


func _position_review_pagination_widgets() -> void:
	"""v0.9.611 — anchor the prev/label/next pagination row just under the
	Review FX button at top-right. Hidden until review phase starts."""
	var panel_w: float = size.x
	var top_y: float = 44.0  # below the review button
	var spacing: float = 6.0
	if _review_pagination_label and is_instance_valid(_review_pagination_label):
		var lbl_w: float = 140.0
		_review_pagination_label.size = Vector2(lbl_w, 26)
		_review_pagination_label.position = Vector2(maxf(0.0, panel_w - lbl_w - 8.0), top_y)
		top_y += _review_pagination_label.size.y + 4.0
	if _review_prev_btn and is_instance_valid(_review_prev_btn) and _review_next_btn and is_instance_valid(_review_next_btn):
		var prev_w: float = _review_prev_btn.custom_minimum_size.x
		var next_w: float = _review_next_btn.custom_minimum_size.x
		var btn_h: float = _review_prev_btn.custom_minimum_size.y
		_review_prev_btn.size = Vector2(prev_w, btn_h)
		_review_next_btn.size = Vector2(next_w, btn_h)
		var right_edge: float = panel_w - 8.0
		_review_next_btn.position = Vector2(maxf(0.0, right_edge - next_w), top_y)
		_review_prev_btn.position = Vector2(maxf(0.0, right_edge - next_w - spacing - prev_w), top_y)


func _position_help_button() -> void:
	"""v0.9.568 — anchor ? Help button to the top-LEFT of the combat panel.
	Mirrors the Review FX button on the opposite corner so the two corners
	stay symmetric. Stays visible whenever the combat panel itself is."""
	if _help_button == null or not is_instance_valid(_help_button):
		return
	var btn_w: float = _help_button.custom_minimum_size.x
	var btn_h: float = _help_button.custom_minimum_size.y
	_help_button.size = Vector2(btn_w, btn_h)
	# v0.9.663 — top-RIGHT corner now (party card lives in the top-left in the
	# left/right layout, so a top-left help button covered it).
	_help_button.position = Vector2(maxf(8.0, size.x - btn_w - 8.0), 6.0)


func _update_review_button_visibility() -> void:
	"""v0.9.439 — show the Review FX button only when:
	  • The combat panel is visible
	  • We're NOT currently in an action phase (FX scene already up)
	  • We're NOT in review (the pause button doubles as Back)
	  • There's actually log content to review

	v0.9.619 — override the _action_phase_active gate when the victory
	interlude is active. Timing problem: _drain_combat_queue's queue-empty
	branch fires show_victory_card BEFORE it schedules end_action_phase_
	after(grace), so at victory-card-display time _action_phase_active is
	still TRUE — the button stays hidden through the whole victory window.
	Then end_action_phase runs, persistent FX kicks in, explicitly hides
	the button again (line ~626). The button only ever appears AFTER the
	player has acknowledged the victory card via Continue — too late to be
	useful. Player report: 'review damage button seems to be missing from
	the victory screen now.'
	"""
	if _review_button == null or not is_instance_valid(_review_button):
		return
	if _in_review_phase:
		_review_button.visible = false
		return
	if not visible:
		_review_button.visible = false
		return
	var has_log := _overlay_player_log_lines.size() > 0 \
		or _overlay_monster_log_lines.size() > 0 \
		or _overlay_companion_log_lines.size() > 0
	# v0.9.619 — if the victory card is up, we WANT the button visible.
	# action_phase_active is stale during the victory interlude.
	if _victory_interlude_active:
		_review_button.visible = has_log
		if _review_button.visible:
			_position_review_button()
		return
	# Original gate: don't show during active rounds or review.
	if _action_phase_active:
		_review_button.visible = false
		return
	_review_button.visible = has_log
	if _review_button.visible:
		_position_review_button()


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
	v0.9.601 — ASCII anchor shrunk 0-0.78 → 0-0.62 to free room for the
	new info row beneath (HP text, resource/XP bar, deck label). All info
	widgets live in a VBoxContainer anchored at the bottom of the block —
	cleaner than 7 individually-anchored rows."""
	# v0.9.633 — block is now a VBoxContainer with ALIGNMENT_END so its
	# children (strip + ASCII + info) stack from the BOTTOM up. Empty space
	# collects at the TOP. Strip sits just above the ASCII; ASCII fit_content
	# sizes itself to the art so HP bar is right below the art's bottom edge.
	# Strip is inside the block now (was a separate overlay child) so its
	# vertical position tracks the ASCII content height.
	var block := VBoxContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.alignment = BoxContainer.ALIGNMENT_END
	block.add_theme_constant_override("separation", 8)
	block.custom_minimum_size = Vector2(320, 300)

	# Strip lives INSIDE the block VBox as the first item (top of stack).
	var strip := _build_overlay_log_label("left" if is_player else "right")
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.custom_minimum_size = Vector2(0, 140)
	block.add_child(strip)

	# ASCII RichTextLabel — fit_content=true so the RTL sizes to art height.
	# clip_contents still on as a defensive backstop for absurdly tall art.
	var ascii := RichTextLabel.new()
	ascii.bbcode_enabled = true
	ascii.fit_content = true
	ascii.scroll_active = false
	ascii.autowrap_mode = TextServer.AUTOWRAP_OFF
	ascii.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ascii.clip_contents = true
	ascii.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _mono_font:
		ascii.add_theme_font_override("normal_font", _mono_font)
		ascii.add_theme_font_override("bold_font", _mono_font)
		ascii.add_theme_font_override("mono_font", _mono_font)
	block.add_child(ascii)

	# Info VBox at the bottom of the stack (HP bar, resource bar, name).
	var info_vbox := VBoxContainer.new()
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	block.add_child(info_vbox)

	# HP bar
	var hp_bar := _make_hp_bar(Color("#FF4444"))
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.custom_minimum_size = Vector2(0, 10)
	info_vbox.add_child(hp_bar)

	# HP cur/max text (small, centered).
	var hp_text := Label.new()
	hp_text.add_theme_font_size_override("font_size", 11)
	hp_text.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hp_text.add_theme_constant_override("outline_size", 2)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(hp_text)

	if is_player:
		# Player resource bar (mana/stamina/energy depending on class).
		var res_bar := _make_hp_bar(Color("#3DD9FF"))
		res_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		res_bar.custom_minimum_size = Vector2(0, 8)
		info_vbox.add_child(res_bar)

		var res_text := Label.new()
		res_text.add_theme_font_size_override("font_size", 10)
		res_text.add_theme_color_override("font_color", Color(0.8, 0.92, 0.98))
		res_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		res_text.add_theme_constant_override("outline_size", 2)
		res_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		res_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		res_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_child(res_text)

		# Deck info — "Deck N · Hand M · Discard K"
		var deck_lbl := Label.new()
		deck_lbl.add_theme_font_size_override("font_size", 10)
		deck_lbl.add_theme_color_override("font_color", Color(0.82, 0.78, 0.55))
		deck_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		deck_lbl.add_theme_constant_override("outline_size", 2)
		deck_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		deck_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_child(deck_lbl)

		_overlay_player_resource_bar = res_bar
		_overlay_player_resource_text = res_text
		_overlay_player_deck_label = deck_lbl
	else:
		# Companion XP bar + text (mirrors pre-FX Lufia box).
		var xp_bar := ProgressBar.new()
		xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xp_bar.custom_minimum_size = Vector2(0, 8)
		xp_bar.show_percentage = false
		var xp_bg := StyleBoxFlat.new()
		xp_bg.bg_color = Color(0.1, 0.1, 0.12)
		xp_bg.border_color = Color(0.25, 0.22, 0.18)
		xp_bg.set_border_width_all(1)
		xp_bg.set_corner_radius_all(2)
		xp_bar.add_theme_stylebox_override("background", xp_bg)
		var xp_fill := StyleBoxFlat.new()
		xp_fill.bg_color = Color("#3DD9FF")
		xp_fill.set_corner_radius_all(2)
		xp_bar.add_theme_stylebox_override("fill", xp_fill)
		info_vbox.add_child(xp_bar)

		var xp_text := Label.new()
		xp_text.add_theme_font_size_override("font_size", 10)
		xp_text.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
		xp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		xp_text.add_theme_constant_override("outline_size", 2)
		xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		xp_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_child(xp_text)

		_overlay_companion_xp_bar = xp_bar
		_overlay_companion_xp_text = xp_text

	# Name label sits at the bottom of the VBox.
	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_lbl.add_theme_constant_override("outline_size", 2)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(name_lbl)

	if is_player:
		_overlay_player_log = strip
		_overlay_player_ascii = ascii
		_overlay_player_hp_bar = hp_bar
		_overlay_player_hp_text = hp_text
		_overlay_player_name = name_lbl
	else:
		_overlay_companion_log = strip
		_overlay_companion_ascii = ascii
		_overlay_companion_hp_bar = hp_bar
		_overlay_companion_hp_text = hp_text
		_overlay_companion_name = name_lbl
	return block


func _position_battlefield_overlay() -> void:
	"""v0.9.411 — overlay sits AT the party-row vertical band. Player block
	on the left, companion block on the right.
	v0.9.633 — overlay extended UP to the top of GameOutput so the player
	and companion columns can claim the full vertical space LEFT and RIGHT
	of the monster ASCII. The monster sits in the column gap and stays
	visible because the overlay itself doesn't draw anything (just a Control
	parent for its children, which only occupy the side columns).
	Block columns become TALL: strip at top, ASCII filling middle, info at
	bottom — no clipping needed because the column has the height for it.
	"""
	if _battlefield_overlay == null or not is_instance_valid(_battlefield_overlay):
		return
	if _player_col == null or not is_instance_valid(_player_col):
		return
	var rect: Rect2 = Rect2(_player_col.global_position, _player_col.size)
	# v0.9.633 — extend overlay to span the FULL height of GameOutput:
	# top = GameOutput.top + small pad, bottom = GameOutput.bottom - small pad.
	# This puts the HP bars (which sit at the BOTTOM of each side column)
	# at the same vertical level as the ability cards / hand row, matching
	# the user's direction. Falls back to monster-bottom clamp if GameOutput
	# isn't accessible.
	var overlay_h: float = maxf(rect.size.y, 340.0)
	var overlay_y: float = rect.position.y - (overlay_h - rect.size.y)
	var game_output_rect: Rect2 = Rect2()
	if client_ref and is_instance_valid(client_ref):
		var goc = client_ref.get("game_output_container")
		if goc and is_instance_valid(goc):
			game_output_rect = Rect2(goc.global_position, goc.size)
			overlay_y = game_output_rect.position.y + 8.0
			var overlay_bottom: float = game_output_rect.position.y + game_output_rect.size.y - 8.0
			overlay_h = overlay_bottom - overlay_y
	# Safety: don't let the overlay top go below the monster (would clip into it).
	# This only triggers if GameOutput isn't accessible.
	if game_output_rect.size == Vector2.ZERO and _monster_col and is_instance_valid(_monster_col):
		var monster_bottom: float = _monster_col.global_position.y + _monster_col.size.y
		if overlay_y < monster_bottom + 4.0:
			overlay_y = monster_bottom + 4.0
			overlay_h = (rect.position.y + rect.size.y) - overlay_y
	_battlefield_overlay.size = Vector2(rect.size.x, overlay_h)
	_battlefield_overlay.global_position = Vector2(rect.position.x, overlay_y)
	_battlefield_overlay_rest_y = _battlefield_overlay.position.y

	# v0.9.633 — Block is a VBoxContainer with strip + ASCII + info, all
	# bottom-aligned. Block fills the full overlay height; VBox alignment
	# pushes content to the bottom so empty space collects at the TOP.
	# Effect: HP bars sit at the very bottom (= ability-card level), ASCII
	# directly above HP bar (no gap), strip directly above ASCII art.
	var block_w: float = 320.0
	var edge_pad: float = 16.0
	var block_y: float = 4.0
	var block_h: float = overlay_h - 8.0
	if _overlay_player_block and is_instance_valid(_overlay_player_block):
		_overlay_player_block.position = Vector2(edge_pad, block_y)
		_overlay_player_block.size = Vector2(block_w, block_h)
		_overlay_player_block_baseline = _overlay_player_block.position
	if _overlay_companion_block and is_instance_valid(_overlay_companion_block):
		_overlay_companion_block.position = Vector2(rect.size.x - block_w - edge_pad, block_y)
		_overlay_companion_block.size = Vector2(block_w, block_h)
		_overlay_companion_block_baseline = _overlay_companion_block.position

	# Pause button — top-right of overlay. z_index 5 stays above strips.
	if _pause_button and is_instance_valid(_pause_button):
		var btn_w: float = 86.0
		var btn_h: float = 26.0
		_pause_button.position = Vector2(rect.size.x - btn_w - 4.0, 2.0)
		_pause_button.size = Vector2(btn_w, btn_h)

	# Monster log — centered under the monster art, top of overlay.
	var log_w_monster: float = block_w
	var log_strip_h_monster: float = clampf(overlay_h * 0.20, 100.0, 140.0)
	if _overlay_monster_log and is_instance_valid(_overlay_monster_log):
		var monster_center_global_x: float = rect.position.x + rect.size.x * 0.5
		if _monster_art_label and is_instance_valid(_monster_art_label):
			monster_center_global_x = _monster_art_label.global_position.x + _monster_art_label.size.x * 0.5
		elif _monster_col and is_instance_valid(_monster_col):
			monster_center_global_x = _monster_col.global_position.x + _monster_col.size.x * 0.5
		var monster_local_x: float = monster_center_global_x - rect.position.x - log_w_monster * 0.5
		monster_local_x = clampf(monster_local_x, 0.0, rect.size.x - log_w_monster)
		# v0.9.633 — monster strip sits JUST BELOW the monster ASCII (per user
		# direction). The strip is centered horizontally on the monster and
		# the player/companion blocks are on the sides, so vertical overlap
		# between the monster strip and the block columns is fine — they
		# don't share horizontal space. Bottom safety clamp keeps the strip
		# from extending past the overlay's bottom edge.
		var monster_strip_y: float = 4.0
		if _monster_col and is_instance_valid(_monster_col):
			var monster_bottom_local: float = (_monster_col.global_position.y + _monster_col.size.y) - overlay_y
			monster_strip_y = clampf(monster_bottom_local + 8.0, 4.0, overlay_h - log_strip_h_monster - 4.0)
		_overlay_monster_log.position = Vector2(monster_local_x, monster_strip_y)
		_overlay_monster_log.size = Vector2(log_w_monster, log_strip_h_monster)


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
			# v0.9.633 — restore the +1 font bump. Earlier in this release I
			# de-bumped because the art overflowed the 0.62 ASCII area, but
			# now that the strips moved out of the overlay's top (freeing the
			# entire overlay height for the block), the ASCII area is ~210px
			# tall and the bumped fonts fit comfortably.
			var p_bumped = _bump_inline_font_size(_player_ascii_label.text, 1)
			_overlay_player_ascii.text = "[center]" + p_bumped + "[/center]"
		else:
			_overlay_player_ascii.text = ""
	# Player HP bar + name. v0.9.501 — animate drain via _animate_bar_value.
	if _overlay_player_hp_bar and is_instance_valid(_overlay_player_hp_bar):
		_overlay_player_hp_bar.max_value = maxi(1, _player_max_hp)
		_animate_bar_value(_overlay_player_hp_bar, clampi(_player_hp, 0, _player_max_hp))
	if _overlay_player_hp_text and is_instance_valid(_overlay_player_hp_text):
		_overlay_player_hp_text.text = "HP %d / %d" % [maxi(0, _player_hp), _player_max_hp]
	# v0.9.601 — resource bar restored (was removed in v0.9.569 because the
	# placeholder was unreachable). Mirrors the data the pre-FX Lufia box
	# now shows and the bottom resource_bars_overlay used to show outside
	# combat. Color reflects class resource type via _player_resource_color.
	if _overlay_player_resource_bar and is_instance_valid(_overlay_player_resource_bar):
		_overlay_player_resource_bar.max_value = maxi(1, _player_resource_max)
		_animate_bar_value(_overlay_player_resource_bar, clampi(_player_resource_cur, 0, _player_resource_max))
		var res_fill: StyleBox = _overlay_player_resource_bar.get_theme_stylebox("fill")
		if res_fill is StyleBoxFlat:
			(res_fill as StyleBoxFlat).bg_color = _player_resource_color
	if _overlay_player_resource_text and is_instance_valid(_overlay_player_resource_text):
		_overlay_player_resource_text.text = "%d / %d" % [maxi(0, _player_resource_cur), _player_resource_max]
	# Deck info — driven by the same source as the pre-FX deck label.
	if _overlay_player_deck_label and is_instance_valid(_overlay_player_deck_label):
		var hand_size_for_overlay: int = _combat_hand.size() if _combat_hand is Array else 0
		_overlay_player_deck_label.text = "Deck %d · Hand %d · Discard %d" % [_combat_deck_count, hand_size_for_overlay, _combat_discard_count]
	if _overlay_player_name and is_instance_valid(_overlay_player_name):
		_overlay_player_name.text = _player_name

	# Companion ASCII + stats.
	# v0.9.633 — bump restored. See player block above for rationale (strips
	# moved out → block has the full overlay height → bumped art fits).
	if _overlay_companion_ascii and is_instance_valid(_overlay_companion_ascii):
		if _companion_art and is_instance_valid(_companion_art):
			_overlay_companion_ascii.text = _bump_inline_font_size(_companion_art.text, 1)
		else:
			_overlay_companion_ascii.text = ""
	# v0.9.601 — compute companion stats once, used by HP bar/text + XP bar/text.
	var c_level: int = int(_companion_data.get("level", 1))
	var c_sub_tier: int = int(_companion_data.get("sub_tier", _companion_data.get("tier", 1)))
	var c_bonuses: Dictionary = _companion_data.get("bonuses", {})
	var c_hp_bonus: int = int(c_bonuses.get("hp_bonus", 0))
	var c_max_hp: int = maxi(1, 30 + c_level * 5 + c_sub_tier * 10 + c_hp_bonus)
	var c_cur_hp: int = int(_companion_data.get("combat_hp", c_max_hp))
	if _overlay_companion_hp_bar and is_instance_valid(_overlay_companion_hp_bar):
		_overlay_companion_hp_bar.max_value = c_max_hp
		_animate_bar_value(_overlay_companion_hp_bar, clampi(c_cur_hp, 0, c_max_hp))
	if _overlay_companion_hp_text and is_instance_valid(_overlay_companion_hp_text):
		_overlay_companion_hp_text.text = "HP %d / %d" % [maxi(0, c_cur_hp), c_max_hp]
	# v0.9.601 — XP bar mirrors pre-FX companion XP row. XP formula matches
	# character.gd's companion_xp_for_next: pow(level+1, 2.0) * 15.
	if _overlay_companion_xp_bar and is_instance_valid(_overlay_companion_xp_bar):
		var c_xp_cur: int = int(_companion_data.get("xp", 0))
		var c_xp_needed: int = int(round(pow(float(c_level + 1), 2.0) * 15.0))
		_overlay_companion_xp_bar.max_value = maxi(1, c_xp_needed)
		_animate_bar_value(_overlay_companion_xp_bar, clampi(c_xp_cur, 0, c_xp_needed))
		if _overlay_companion_xp_text and is_instance_valid(_overlay_companion_xp_text):
			_overlay_companion_xp_text.text = "Lv %d · %d / %d" % [c_level, c_xp_cur, c_xp_needed]
	if _overlay_companion_name and is_instance_valid(_overlay_companion_name):
		var overlay_name := str(_companion_data.get("name", "Companion"))
		# v0.9.508 — append aggro role tag (Label, no BBCode, plain text).
		if client_ref != null and client_ref.has_method("_get_aggro_role_info"):
			var ov_bonuses: Dictionary = _companion_data.get("bonuses", {})
			var ov_aggro := int(ov_bonuses.get("aggro", 25))
			var ov_role: Dictionary = client_ref._get_aggro_role_info(ov_aggro)
			var ov_label := str(ov_role.get("label", ""))
			if ov_label != "":
				overlay_name += " [%s]" % ov_label.to_upper()
		_overlay_companion_name.text = overlay_name

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
	# 2026-08-27 — borderless/transparent: the player + companion now share ONE
	# outer card (built in _build_scene_section_lufia), so these inner boxes must not
	# draw their own border/bg or they'd look like two separate cards with a gap.
	sb.bg_color = Color(0.02, 0.02, 0.03, 0.0)
	sb.border_color = Color(0.75, 0.78, 0.92, 0.0)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 4
	sb.content_margin_top = 4
	sb.content_margin_right = 4
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
	# v0.9.663 — NOT clipped (the sprite fits at rest) + raised z so the attack
	# lunge animates OVER the stat bars / toward the monster instead of behind them.
	_player_portrait_bg.z_index = 5
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
	# v0.9.663 — left-align (BEGIN) so the HP and resource bars share the same
	# left edge. SHRINK_CENTER centered each row independently, and the differing
	# text widths pushed the two bars out of vertical alignment.
	var hp_row := HBoxContainer.new()
	hp_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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

	# v0.9.601 — resource (mana / stamina / energy) row, same pattern as HP.
	# Mirrors the new FX overlay row so resource is visible during combat
	# (pairs with the v0.9.601 hide of the bottom resource_bars_overlay
	# during combat — the info was redundant once the combat scene shows it).
	var res_row := HBoxContainer.new()
	res_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	res_row.add_theme_constant_override("separation", 6)
	res_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(res_row)
	_lufia_player_resource_bar = _make_hp_bar(Color("#3DD9FF"))
	_lufia_player_resource_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lufia_player_resource_bar.custom_minimum_size = Vector2(COMPACT_BAR_W, 8)
	res_row.add_child(_lufia_player_resource_bar)
	_lufia_player_resource_text = Label.new()
	_lufia_player_resource_text.add_theme_font_size_override("font_size", 11)
	_lufia_player_resource_text.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98))
	_lufia_player_resource_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lufia_player_resource_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res_row.add_child(_lufia_player_resource_text)

	# Deck info: "Deck N · Hand M · Discard K"
	_lufia_player_deck_label = RichTextLabel.new()  # v0.9.663 — RTL for colored Deck/Discard
	_lufia_player_deck_label.bbcode_enabled = true
	_lufia_player_deck_label.fit_content = true
	_lufia_player_deck_label.scroll_active = false
	_lufia_player_deck_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_lufia_player_deck_label.add_theme_font_size_override("normal_font_size", 11)
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
	_companion_portrait_bg.clip_contents = true  # v0.9.663 — art can't spill the card
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
	# 2026-08-27 — was SHRINK_END, which pinned the sprite to the BOTTOM of its box
	# (feedback: player battler sat too low, overlapping the bottom border). CENTER
	# aligns it vertically between the top and bottom of the box.
	_player_sprite_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	# v0.9.601 — SIZE_SHRINK_CENTER (was SIZE_EXPAND_FILL): shrinks the frame
	# to fit the three short totals labels + centers horizontally. Old setting
	# stretched the frame across the entire screen width so the yellow-gold
	# border ran across the player/companion ASCII columns even though the
	# actual "You: N  Foe: N" content only needs ~250-400 px.
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_totals_strip_frame = frame  # v0.9.425 — keep a handle so action-phase can hide the border

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
	# Shrink the inner HBox to its content too — combined with the centered
	# frame above, the strip reads as a tight bordered chip rather than a
	# full-width banner.
	_totals_strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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

# v0.9.696 — Warrior Momentum meter state.
var _momentum_label: RichTextLabel = null
var _momentum: int = 0
var _momentum_max: int = 5
var _momentum_active: bool = false
# v0.9.697 — Trickster Combo shares the same leftmost meter node (_momentum_label).
# A character is either a Warrior or a Trickster, never both, so the two engines
# never contend for the meter.
var _combo: int = 0  # v0.9.698 — repurposed as "Read" (Trickster Outsmart engine)
var _combo_max: int = 5
var _combo_active: bool = false
var _outsmart_chance: int = 0  # live Outsmart % for the Read meter
# v0.9.697 — Mage Focus shares the same meter node too (ramp: boosts all spells).
var _focus: int = 0
var _focus_max: int = 5
var _focus_active: bool = false

func update_momentum(cur: int, mx: int, is_warrior: bool) -> void:
	"""Called from client.gd on each combat_state. Shows a pip meter for Warriors;
	hidden otherwise. Also drives the Devastate card gating in _refresh_hand."""
	_momentum = cur
	_momentum_max = max(1, mx)
	_momentum_active = is_warrior
	if _momentum_label == null or not is_instance_valid(_momentum_label):
		return
	if not is_warrior:
		# Only hide if no other engine owns the meter.
		if not (_combo_active or _focus_active):
			_momentum_label.visible = false
		return
	_combo_active = false  # Warrior owns the meter
	_focus_active = false
	_momentum_label.visible = true
	var pips := ""
	for i in range(_momentum_max):
		pips += "[color=#FFC94D]●[/color]" if i < cur else "[color=#5A4E38]○[/color]"
	var ready := cur >= 1
	var tag := "[color=#FFC94D]FINISHER READY[/color]" if ready else "[color=#7A6E58]build to Devastate[/color]"
	_momentum_label.text = "[color=#C8A24A]⚡ Momentum[/color]\n%s\n%s" % [pips, tag]
	# Re-gate the hand cards (Devastate availability) now that momentum changed.
	if not _hand_cells.is_empty():
		_refresh_hand()

func update_read(cur: int, mx: int, outsmart_chance: int, is_trickster: bool) -> void:
	"""v0.9.698 — Trickster Read meter (teal ◉). Every Trickster ability builds Read,
	which raises your Outsmart chance. Shows the LIVE Outsmart % so you know when to
	spring it. Drives the Gambit label + the '+◉ Read' builder badges in _refresh_hand."""
	_combo = cur
	_combo_max = max(1, mx)
	_outsmart_chance = outsmart_chance
	_combo_active = is_trickster
	if _momentum_label == null or not is_instance_valid(_momentum_label):
		return
	if not is_trickster:
		if not (_momentum_active or _focus_active):
			_momentum_label.visible = false
		return
	_momentum_active = false  # Trickster owns the meter
	_focus_active = false
	_momentum_label.visible = true
	var pips := ""
	for i in range(_combo_max):
		pips += "[color=#7FD8C8]◉[/color]" if i < cur else "[color=#33463F]○[/color]"
	var oc_color := "#7AE07A" if outsmart_chance >= 70 else ("#7FD8C8" if outsmart_chance >= 40 else "#C89A5A")
	var tag := "[color=%s]Outsmart %d%%[/color]" % [oc_color, outsmart_chance]
	_momentum_label.text = "[color=#7FD8C8]◉ Read[/color]\n%s\n%s" % [pips, tag]
	if not _hand_cells.is_empty():
		_refresh_hand()

func update_focus(cur: int, mx: int, is_mage: bool) -> void:
	"""v0.9.697 — Mage Focus meter (blue ◈). A RAMP: shows the live all-spell damage
	bonus. No gate; Meteor discharges it. Drives the spell/Meteor card notes."""
	_focus = cur
	_focus_max = max(1, mx)
	_focus_active = is_mage
	if _momentum_label == null or not is_instance_valid(_momentum_label):
		return
	if not is_mage:
		if not (_momentum_active or _combo_active):
			_momentum_label.visible = false
		return
	_momentum_active = false  # Mage owns the meter
	_combo_active = false
	_momentum_label.visible = true
	var pips := ""
	for i in range(_focus_max):
		pips += "[color=#5AC8FF]◈[/color]" if i < cur else "[color=#37485A]◇[/color]"
	var tag: String
	if cur >= _focus_max:
		tag = "[color=#7AE0FF]MAX +%d%% dmg[/color]" % int(cur * 10)
	elif cur > 0:
		tag = "[color=#5AC8FF]+%d%% spell dmg[/color]" % int(cur * 10)
	else:
		tag = "[color=#6E7E8A]cast to ramp up[/color]"
	_momentum_label.text = "[color=#5AC8FF]◈ Focus[/color]\n%s\n%s" % [pips, tag]
	if not _hand_cells.is_empty():
		_refresh_hand()

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

	# v0.9.696 — Warrior Momentum meter (leftmost). Hidden for non-Warriors.
	_momentum_label = RichTextLabel.new()
	_momentum_label.bbcode_enabled = true
	_momentum_label.fit_content = true
	_momentum_label.scroll_active = false
	_momentum_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_momentum_label.add_theme_font_size_override("normal_font_size", 15)
	_momentum_label.custom_minimum_size = Vector2(120, 0)
	_momentum_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_momentum_label.visible = false
	outer.add_child(_momentum_label)

	_hand_strip = HBoxContainer.new()
	_hand_strip.add_theme_constant_override("separation", 10)
	_hand_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	outer.add_child(_hand_strip)

	_hand_cells.clear()
	for i in range(COMBAT_HAND_SIZE):
		var cell := _build_hand_cell(i)
		_hand_cells.append(cell)
		_hand_strip.add_child(cell)

	_hand_status_label = RichTextLabel.new()  # v0.9.663 — RTL for colored Deck/Discard
	_hand_status_label.bbcode_enabled = true
	_hand_status_label.fit_content = true
	_hand_status_label.scroll_active = false
	_hand_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hand_status_label.add_theme_font_size_override("normal_font_size", 11)
	_hand_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 2026-08-27 — Deck/Discard counter HIDDEN here (freed the ~168px so the party
	# column has room to fit on-screen). The same Deck/Discard info still shows in the
	# player box's own deck label. Kept in the tree (invisible) so update code is safe.
	_hand_status_label.custom_minimum_size = Vector2(0, 0)
	_hand_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hand_status_label.visible = false
	outer.add_child(_hand_status_label)

	return outer


static func companion_card_art_bbcode(card_name: String) -> String:
	"""v0.9.683 — the monster ASCII art for a companion card, centered, or "" if
	the id isn't a companion card / has no art. Keyed by de-slugged type name."""
	if not card_name.begins_with("companion_card_"):
		return ""
	var mtype := card_name.trim_prefix("companion_card_").capitalize()
	var art := MonsterArt.get_monster_ascii_art(mtype)
	if art == "":
		return ""
	return "[center]" + art + "[/center]"

const CARD_ART_BOX := Vector2(134, 88)  # fixed art box inside the 150x190 card (pips moved to own row v0.9.693)

func _make_card_art_label() -> Control:
	"""v0.9.686 — a fixed-size CLIP HOLDER (CARD_ART_BOX) containing a full-size
	RichTextLabel that we uniformly SCALE DOWN so the WHOLE companion art shows,
	just small. The holder's fixed min-size keeps the card uniform; the inner RTL
	renders at natural size and is node-scaled + centered in _apply_card_art.
	Named 'ArtImg' so _refresh_hand's find_child + visibility toggle still work."""
	var holder := Control.new()
	holder.name = "ArtImg"
	holder.custom_minimum_size = CARD_ART_BOX
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	var rtl := RichTextLabel.new()
	rtl.name = "ArtRTL"
	rtl.bbcode_enabled = true
	rtl.fit_content = false
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _mono_font:
		rtl.add_theme_font_override("normal_font", _mono_font)
		rtl.add_theme_font_override("bold_font", _mono_font)
		rtl.add_theme_font_override("italics_font", _mono_font)
		rtl.add_theme_font_override("mono_font", _mono_font)
	holder.add_child(rtl)
	return holder

func _apply_card_art(holder: Control, art_bbcode: String) -> void:
	"""Render the full art in the inner RTL at a base font, then uniformly scale
	the RTL node so the ENTIRE art fits (and centers) inside CARD_ART_BOX. Uses
	measured mono metrics to compute the natural size deterministically (no layout
	wait), so even a 150x72 monster shows whole, just miniaturized."""
	if holder == null:
		return
	var rtl: RichTextLabel = holder.get_node_or_null("ArtRTL")
	if rtl == null:
		return
	# Trim blank top/bottom rows so the creature fills more of the frame (bigger =
	# crisper after downscale). Column trim is skipped (BBCode spans columns).
	var raw_lines := art_bbcode.split("\n")
	var lo: int = 0
	var hi: int = raw_lines.size() - 1
	while lo <= hi and _strip_bbcode(raw_lines[lo]).strip_edges() == "":
		lo += 1
	while hi >= lo and _strip_bbcode(raw_lines[hi]).strip_edges() == "":
		hi -= 1
	var kept: Array = []
	for i in range(lo, hi + 1):
		kept.append(raw_lines[i])
	if not kept.is_empty():
		art_bbcode = "\n".join(kept)
	var plain := _strip_bbcode(art_bbcode)
	var lines := plain.split("\n")
	var rows: int = max(1, lines.size())
	var cols: int = 1
	for ln in lines:
		cols = max(cols, (ln as String).length())
	# Measure the mono font: width-per-point + line-height-per-point.
	var cw: float = 0.62
	var lh: float = 1.35
	if _mono_font != null:
		var wref: float = _mono_font.get_string_size("W", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x / 100.0
		var href: float = float(_mono_font.get_height(100)) / 100.0
		if wref > 0.01:
			cw = wref
		if href > 0.01:
			lh = href
	var base_fs: int = 8  # render crisp, then downscale
	rtl.add_theme_font_size_override("normal_font_size", base_fs)
	rtl.add_theme_font_size_override("bold_font_size", base_fs)
	rtl.add_theme_font_size_override("italics_font_size", base_fs)
	rtl.add_theme_font_size_override("mono_font_size", base_fs)
	# Natural (unscaled) size of the full art, with a little slack so nothing
	# clips inside the RTL before we scale it.
	var nat := Vector2(float(cols) * cw * base_fs, float(rows) * lh * base_fs) * 1.06
	rtl.custom_minimum_size = nat
	rtl.size = nat
	rtl.text = art_bbcode
	# Uniform scale so the WHOLE art fits the box; center it.
	var s: float = min(CARD_ART_BOX.x / nat.x, CARD_ART_BOX.y / nat.y)
	rtl.pivot_offset = Vector2.ZERO
	rtl.scale = Vector2(s, s)
	rtl.position = (CARD_ART_BOX - nat * s) * 0.5

func _fit_label_font(label: Label, text: String, avail_w: float, max_fs: int = 15, min_fs: int = 9) -> void:
	"""v0.9.687 — set the card-name text + shrink its font (down to min_fs) until
	it fits avail_w, so long names like 'Kobold's Stash' don't clip on the right."""
	if label == null:
		return
	label.text = text
	var font := label.get_theme_font("font")
	var fs := max_fs
	if font != null and text != "":
		while fs > min_fs:
			if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail_w:
				break
			fs -= 1
	label.add_theme_font_size_override("font_size", fs)

func _build_hand_cell(index: int) -> PanelContainer:
	"""v0.9.675 — a real PORTRAIT card: category-coloured top banner (hotkey +
	name), a big centred ability icon, a bottom row with rank pips + a bold cost
	pip, and the mastery fill washing up from the bottom behind it. Node names
	(Banner/Row/Key, Banner/Row/Name, IconWrap/Glyph, InfoRow/Pips, InfoRow/Cost,
	Effect, FillLayer/Fill) are read by _refresh_hand."""
	var cell := PanelContainer.new()
	cell.name = "HandCell_%d" % index
	cell.custom_minimum_size = Vector2(CARD_W, CARD_H)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.tooltip_text = ""
	cell.clip_contents = true
	# v0.9.690 — battle sticky description box on hover (client owns the box).
	cell.mouse_entered.connect(_on_hand_cell_mouse_entered.bind(cell))
	cell.mouse_exited.connect(_on_hand_cell_mouse_exited.bind(cell))

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.07, 0.97)
	sb.border_color = Color(0.55, 0.45, 0.30, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	cell.add_theme_stylebox_override("panel", sb)

	# Mastery fill — washes UP from the bottom in the category colour as the card
	# nears its next rank (a card filling toward "level up"). Behind everything.
	var fill_layer := Control.new()
	fill_layer.name = "FillLayer"
	fill_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(fill_layer)
	var fill_rect := ColorRect.new()
	fill_rect.name = "Fill"
	fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_rect.color = Color(0.5, 0.4, 0.3, 0.0)
	fill_rect.anchor_left = 0.0
	fill_rect.anchor_right = 1.0
	fill_rect.anchor_top = 1.0   # bottom-anchored; anchor_top lowered per progress
	fill_rect.anchor_bottom = 1.0
	fill_rect.offset_left = 0
	fill_rect.offset_right = 0
	fill_rect.offset_top = 0
	fill_rect.offset_bottom = 0
	fill_layer.add_child(fill_rect)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(vbox)

	# --- Banner (category colour) : hotkey + ability name ---
	var banner := PanelContainer.new()
	banner.name = "Banner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#8C7656")
	bsb.set_corner_radius_all(0)
	bsb.corner_radius_top_left = 8
	bsb.corner_radius_top_right = 8
	bsb.content_margin_left = 6
	bsb.content_margin_right = 6
	bsb.content_margin_top = 4
	bsb.content_margin_bottom = 4
	banner.add_theme_stylebox_override("panel", bsb)
	var brow := HBoxContainer.new()
	brow.name = "Row"
	brow.add_theme_constant_override("separation", 4)
	brow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(brow)
	# v0.9.675 — class emblem badge (leftmost in the banner) for race/class identity.
	var emblem_label := Label.new()
	emblem_label.name = "Emblem"
	emblem_label.text = ""
	emblem_label.add_theme_font_size_override("font_size", 15)
	emblem_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	emblem_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	emblem_label.add_theme_constant_override("outline_size", 3)
	emblem_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brow.add_child(emblem_label)
	var key_label := Label.new()
	key_label.name = "Key"
	key_label.text = "%d" % (index + 1)
	key_label.add_theme_font_size_override("font_size", 15)
	key_label.add_theme_color_override("font_color", Color("#FFE68A"))
	key_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	key_label.add_theme_constant_override("outline_size", 3)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brow.add_child(key_label)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = "—"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brow.add_child(name_label)
	vbox.add_child(banner)

	# v0.9.675 — class-colour accent line under the banner (recoloured in refresh).
	var accent := ColorRect.new()
	accent.name = "Accent"
	accent.color = Color("#B08C4C")
	accent.custom_minimum_size = Vector2(0, 3)
	accent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(accent)

	# --- Icon (big centred glyph) ---
	var icon_wrap := CenterContainer.new()
	icon_wrap.name = "IconWrap"
	icon_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph_label := Label.new()
	glyph_label.name = "Glyph"
	glyph_label.text = ""
	glyph_label.add_theme_font_size_override("font_size", 46)
	glyph_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	glyph_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	glyph_label.add_theme_constant_override("outline_size", 4)
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(glyph_label)
	# v0.9.683/685 — companion cards show the companion's monster art here instead
	# of the glyph (populated + toggled in _refresh_hand). Fixed-box + clip so it
	# never grows the card.
	icon_wrap.add_child(_make_card_art_label())
	vbox.add_child(icon_wrap)

	# --- Effect line (small, above the info row) ---
	var effect_label := Label.new()
	effect_label.name = "Effect"
	effect_label.text = ""
	effect_label.add_theme_font_size_override("font_size", 12)
	effect_label.add_theme_color_override("font_color", Color("#FFA060"))
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_label.clip_text = true
	effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(effect_label)

	# v0.9.693 — rank pips on their own centered line, MOVED off the numbers row
	# so the damage/heal + cost numbers don't crowd it and stretch the card.
	var pips_row := CenterContainer.new()
	pips_row.name = "PipsRow"
	pips_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pips_label := Label.new()
	pips_label.name = "Pips"
	pips_label.text = ""
	pips_label.add_theme_font_size_override("font_size", 13)
	pips_label.add_theme_color_override("font_color", Color("#FFD700"))
	pips_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pips_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips_row.add_child(pips_label)
	vbox.add_child(pips_row)

	# --- Info row: rank pips (left) + cost pip (right) ---
	var info_row := MarginContainer.new()
	info_row.name = "InfoRow"
	info_row.add_theme_constant_override("margin_left", 8)
	info_row.add_theme_constant_override("margin_right", 8)
	info_row.add_theme_constant_override("margin_top", 2)
	info_row.add_theme_constant_override("margin_bottom", 6)
	info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info_hb := HBoxContainer.new()
	info_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_row.add_child(info_hb)
	# v0.9.691 — damage/heal value pip (leftmost), styled like the cost pip.
	var value_pip := PanelContainer.new()
	value_pip.name = "ValuePip"
	value_pip.visible = false
	value_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vsb := StyleBoxFlat.new()
	vsb.bg_color = Color(0.15, 0.15, 0.18, 0.95)
	vsb.set_corner_radius_all(9)
	vsb.content_margin_left = 8
	vsb.content_margin_right = 8
	vsb.content_margin_top = 1
	vsb.content_margin_bottom = 1
	value_pip.add_theme_stylebox_override("panel", vsb)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = ""
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", Color("#FF7A5A"))
	value_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	value_label.add_theme_constant_override("outline_size", 2)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_pip.add_child(value_label)
	info_hb.add_child(value_pip)
	# v0.9.693 — expand spacer pushes the cost pip to the right (rank pips moved
	# to their own centered row above, so the numbers don't crowd this row).
	var mid_spacer := Control.new()
	mid_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_hb.add_child(mid_spacer)
	# Cost pip — a small rounded panel tinted by resource, with the number.
	var cost_pip := PanelContainer.new()
	cost_pip.name = "CostPip"
	cost_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.15, 0.15, 0.18, 0.95)
	csb.set_corner_radius_all(9)
	csb.content_margin_left = 8
	csb.content_margin_right = 8
	csb.content_margin_top = 1
	csb.content_margin_bottom = 1
	cost_pip.add_theme_stylebox_override("panel", csb)
	var cost_label := Label.new()
	cost_label.name = "Cost"
	cost_label.text = ""
	cost_label.add_theme_font_size_override("font_size", 15)
	cost_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	cost_label.add_theme_constant_override("outline_size", 2)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_pip.add_child(cost_label)
	info_hb.add_child(cost_pip)
	vbox.add_child(info_row)

	# Click handler — pulls the current card name from meta on click.
	cell.gui_input.connect(_on_hand_cell_input.bind(index))
	cell.set_meta("card_name", "")
	cell.set_meta("can_afford", false)
	return cell


func build_milestone_card(branch: String, ability_label: String, category_color_hex: String, glyph: String, detail: String, accent_hex: String, tooltip: String = "") -> PanelContainer:
	"""v0.9.677 — a card-styled PREVIEW for the milestone chooser: same frame as a
	combat card (category banner + big icon), with the upgrade's effect + branch
	name below. Clickable (caller wires gui_input); carries `branch` in meta.
	accent_hex tints the branch footer so the three options read distinctly.
	tooltip: hover text with the projected before→after detail."""
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(CARD_W, CARD_H + 34)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.set_meta("tip_text", tooltip)  # shown in a custom polished box on hover
	cell.set_meta("branch", branch)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _theme_card_bg()
	sb.border_color = Color(category_color_hex)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	cell.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(vbox)

	# Banner (deepened category colour + ability name)
	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(category_color_hex).darkened(0.42)
	bsb.corner_radius_top_left = 8
	bsb.corner_radius_top_right = 8
	bsb.content_margin_left = 6
	bsb.content_margin_right = 6
	bsb.content_margin_top = 4
	bsb.content_margin_bottom = 4
	banner.add_theme_stylebox_override("panel", bsb)
	var name_lbl := Label.new()
	_fit_label_font(name_lbl, ability_label, 124)
	name_lbl.add_theme_color_override("font_color", Color("#FFFFFF"))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.clip_text = true
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(name_lbl)
	vbox.add_child(banner)

	# Icon
	var icon_wrap := CenterContainer.new()
	icon_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph_lbl := Label.new()
	glyph_lbl.text = glyph
	glyph_lbl.add_theme_font_size_override("font_size", 46)
	glyph_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	glyph_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	glyph_lbl.add_theme_constant_override("outline_size", 4)
	glyph_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(glyph_lbl)
	vbox.add_child(icon_wrap)

	# Detail — what this upgrade does
	var detail_lbl := Label.new()
	detail_lbl.text = detail
	detail_lbl.add_theme_font_size_override("font_size", 13)
	detail_lbl.add_theme_color_override("font_color", Color("#DDDDDD"))
	detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_lbl.custom_minimum_size = Vector2(0, 34)
	detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(detail_lbl)

	# Branch footer (accent-coloured)
	var footer := Label.new()
	footer.text = branch.to_upper()
	footer.add_theme_font_size_override("font_size", 15)
	footer.add_theme_color_override("font_color", Color(accent_hex))
	footer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	footer.add_theme_constant_override("outline_size", 2)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.custom_minimum_size = Vector2(0, 22)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(footer)

	return cell


# v0.9.689 — polished formula popup for the [url]-tagged numbers in card
# descriptions (replaces Godot's unstyled [hint] tooltip).
var _formula_popup: PanelContainer = null
var _formula_popup_lbl: RichTextLabel = null

func _ensure_formula_popup() -> void:
	if _formula_popup != null and is_instance_valid(_formula_popup):
		return
	_formula_popup = PanelContainer.new()
	_formula_popup.name = "FormulaPopup"
	_formula_popup.top_level = true
	_formula_popup.z_index = 400
	_formula_popup.visible = false
	_formula_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.06, 0.99)
	sb.border_color = Color("#C8A24A")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	_formula_popup.add_theme_stylebox_override("panel", sb)
	_formula_popup_lbl = RichTextLabel.new()
	_formula_popup_lbl.bbcode_enabled = true
	_formula_popup_lbl.fit_content = true
	_formula_popup_lbl.scroll_active = false
	_formula_popup_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_formula_popup_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_formula_popup_lbl.add_theme_font_size_override("normal_font_size", 13)
	_formula_popup_lbl.add_theme_font_size_override("bold_font_size", 13)
	_formula_popup.add_child(_formula_popup_lbl)
	# Parent to the window root so it shows even on the Deck screen (this combat
	# panel is hidden out of combat, which would hide its children).
	get_tree().root.add_child(_formula_popup)

func _show_formula_popup(formula: String) -> void:
	if formula == "":
		return
	_ensure_formula_popup()
	_formula_popup_lbl.text = "[color=#D4A017][b]ƒ[/b][/color]  [color=#EDE3C8]%s[/color]" % formula
	_formula_popup.visible = true
	_formula_popup.reset_size()
	var mp := get_global_mouse_position()
	var sz := _formula_popup.size
	var vp := get_viewport_rect().size
	var x: float = clamp(mp.x + 14.0, 4.0, vp.x - sz.x - 4.0)
	var y: float = clamp(mp.y - sz.y - 10.0, 4.0, vp.y - sz.y - 4.0)
	_formula_popup.global_position = Vector2(x, y)

func _hide_formula_popup() -> void:
	if _formula_popup != null and is_instance_valid(_formula_popup):
		_formula_popup.visible = false

# v0.9.690 — battle hand-card hover → client's sticky description box.
func _on_hand_cell_mouse_entered(cell) -> void:
	if client_ref == null or not client_ref.has_method("show_card_desc_box"):
		return
	var cn := str(cell.get_meta("card_name", ""))
	if cn == "":
		return
	client_ref.show_card_desc_box(cn, cell.get_global_rect())

func _on_hand_cell_mouse_exited(_cell) -> void:
	if client_ref != null and client_ref.has_method("notify_card_desc_card_exit"):
		client_ref.notify_card_desc_card_exit()


func build_deck_card(display: String, category_color_hex: String, glyph: String, cost_text: String, copies: int, back_bbcode: String, art_bbcode: String = "", value_text: String = "", value_color: String = "#FF7A5A", is_loaner: bool = false) -> Control:
	"""v0.9.678 (slice 3) — a combat-styled card for the DECK SCREEN. Returns a
	Control holding a Front (banner + icon + cost + copy badge) and a Back (long
	description); the Back starts hidden. Caller wires a click to flip (toggle
	child 'Front'/'Back' visibility). Copy badge shows N/3; 0 = greyed 'out'.
	v0.9.717 — is_loaner: a companion loaner card is ACTIVE in the deck while the
	companion is equipped even though its owned-copy count is 0, so render it lit
	(not greyed) with a 'LOAN' badge instead of 'OUT'."""
	# A card counts as in-deck (lit) if you own a copy OR it's an active loaner.
	var active := copies > 0 or is_loaner
	var root := Control.new()
	root.name = "DeckCard"
	root.custom_minimum_size = Vector2(CARD_W, CARD_H)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("flipped", false)

	# --- FRONT ---
	var front := PanelContainer.new()
	front.name = "Front"
	front.set_anchors_preset(Control.PRESET_FULL_RECT)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = _theme_card_bg() if active else Color(0.06, 0.06, 0.07, 0.95)
	fsb.border_color = Color(category_color_hex) if active else Color(0.3, 0.28, 0.24)
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(10)
	front.add_theme_stylebox_override("panel", fsb)
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 0)
	fv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(fv)
	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(category_color_hex).darkened(0.42)
	bsb.corner_radius_top_left = 8
	bsb.corner_radius_top_right = 8
	bsb.content_margin_left = 6
	bsb.content_margin_right = 6
	bsb.content_margin_top = 4
	bsb.content_margin_bottom = 4
	banner.add_theme_stylebox_override("panel", bsb)
	var name_lbl := Label.new()
	_fit_label_font(name_lbl, display, 132)
	name_lbl.add_theme_color_override("font_color", Color("#FFFFFF"))
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.clip_text = true
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(name_lbl)
	fv.add_child(banner)
	var icon_wrap := CenterContainer.new()
	icon_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph_lbl := Label.new()
	glyph_lbl.text = glyph
	glyph_lbl.add_theme_font_size_override("font_size", 46)
	glyph_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	glyph_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	glyph_lbl.add_theme_constant_override("outline_size", 4)
	glyph_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(glyph_lbl)
	# v0.9.683 — companion cards show the companion's monster art here.
	if art_bbcode != "":
		glyph_lbl.visible = false
		var deck_art := _make_card_art_label()
		_apply_card_art(deck_art, art_bbcode)
		deck_art.visible = true
		icon_wrap.add_child(deck_art)
	fv.add_child(icon_wrap)
	# Bottom row: cost pip + copy badge.
	var info := MarginContainer.new()
	info.add_theme_constant_override("margin_left", 8)
	info.add_theme_constant_override("margin_right", 8)
	info.add_theme_constant_override("margin_bottom", 6)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info_hb := HBoxContainer.new()
	info_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(info_hb)
	var cost_lbl := Label.new()
	# Cost helper returns BBCode; strip tags for this plain Label (raw markup was
	# rendering literally + stretching the card).
	var _cost_rx := RegEx.new()
	_cost_rx.compile("\\[.*?\\]")
	cost_lbl.text = _cost_rx.sub(cost_text, "", true)
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", Color("#9ACD32"))
	cost_lbl.clip_text = true
	cost_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_hb.add_child(cost_lbl)
	# v0.9.691 — damage/heal value on the deck card front.
	if value_text != "":
		var value_lbl := Label.new()
		value_lbl.text = value_text
		value_lbl.add_theme_font_size_override("font_size", 12)
		value_lbl.add_theme_color_override("font_color", Color(value_color))
		value_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_hb.add_child(value_lbl)
	var copy_lbl := Label.new()
	if is_loaner and copies == 0:
		copy_lbl.text = "LOAN"
	elif copies > 0:
		copy_lbl.text = "×%d/3" % copies
	else:
		copy_lbl.text = "OUT"
	copy_lbl.add_theme_font_size_override("font_size", 12)
	if is_loaner and copies == 0:
		copy_lbl.add_theme_color_override("font_color", Color("#C8A24A"))  # gold — active loaner
	else:
		copy_lbl.add_theme_color_override("font_color", Color("#9ACD32") if copies >= 2 else (Color("#B05050") if copies == 0 else Color("#AAAAAA")))
	copy_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_hb.add_child(copy_lbl)
	fv.add_child(info)
	root.add_child(front)

	# --- BACK (hidden until flipped) ---
	var back := PanelContainer.new()
	back.name = "Back"
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	# v0.9.688 — PASS (not IGNORE) so the RichTextLabel receives hover for the
	# [hint] formula tooltips, while clicks still bubble up to flip the card.
	back.mouse_filter = Control.MOUSE_FILTER_PASS
	back.visible = false
	var ksb := StyleBoxFlat.new()
	ksb.bg_color = Color(0.07, 0.06, 0.05, 0.98)
	ksb.border_color = Color(category_color_hex)
	ksb.set_border_width_all(2)
	ksb.set_corner_radius_all(10)
	ksb.content_margin_left = 8
	ksb.content_margin_right = 8
	ksb.content_margin_top = 8
	ksb.content_margin_bottom = 8
	back.add_theme_stylebox_override("panel", ksb)
	var back_txt := RichTextLabel.new()
	back_txt.bbcode_enabled = true
	back_txt.fit_content = true
	back_txt.scroll_active = false
	back_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	back_txt.add_theme_font_size_override("normal_font_size", 12)
	back_txt.add_theme_font_size_override("bold_font_size", 13)
	back_txt.mouse_filter = Control.MOUSE_FILTER_PASS  # v0.9.688 — receive number hover
	# v0.9.689 — polished formula popup on number hover (numbers are [url]-tagged).
	back_txt.meta_underlined = false
	back_txt.meta_hover_started.connect(func(meta): _show_formula_popup(str(meta)))
	back_txt.meta_hover_ended.connect(func(_meta): _hide_formula_popup())
	back_txt.text = "[b]%s[/b]\n%s" % [display, back_bbcode]
	back.add_child(back_txt)
	root.add_child(back)
	return root


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


func _theme_class_color() -> Color:
	if _player_class != "":
		return ClassSprite.get_class_color(_player_class)
	return Color("#B08C4C")


func _theme_race_color() -> Color:
	if client_ref and _player_race != "" and client_ref.has_method("_get_race_passive"):
		var rp = client_ref._get_race_passive(_player_race)
		var hex := str(rp.get("color", ""))
		if hex != "" and hex.is_valid_html_color():
			return Color(hex)
	return _theme_class_color()


func _theme_card_bg() -> Color:
	# Dark base faintly washed toward the CLASS colour, then the RACE colour, so
	# the deck reads as "yours" without fighting the category border/banner.
	var col := Color(0.09, 0.08, 0.07, 0.97).lerp(_theme_class_color(), 0.18)
	col = col.lerp(_theme_race_color(), 0.10)
	col.a = 0.97
	return col


func _class_emblem_text() -> String:
	if CLASS_EMBLEM.has(_player_class):
		return String(CLASS_EMBLEM[_player_class])
	return _player_class.substr(0, 1) if _player_class != "" else "◆"


func _refresh_hand() -> void:
	if _hand_cells.is_empty():
		return
	for i in range(_hand_cells.size()):
		var cell: PanelContainer = _hand_cells[i]
		var key_lbl: Label = cell.find_child("Key", true, false)
		var name_lbl: Label = cell.find_child("Name", true, false)
		var glyph_lbl: Label = cell.find_child("Glyph", true, false)
		var pips_lbl: Label = cell.find_child("Pips", true, false)
		var cost_lbl: Label = cell.find_child("Cost", true, false)
		var cost_pip: PanelContainer = cell.find_child("CostPip", true, false)
		var value_pip: PanelContainer = cell.find_child("ValuePip", true, false)
		var value_lbl: Label = cell.find_child("Value", true, false)
		var effect_lbl: Label = cell.find_child("Effect", true, false)
		var banner: PanelContainer = cell.find_child("Banner", true, false)
		var fill_rect: ColorRect = cell.find_child("Fill", true, false)
		var emblem_lbl: Label = cell.find_child("Emblem", true, false)
		var accent: ColorRect = cell.find_child("Accent", true, false)

		# Hotkey label reads the live keybind for the action-bar slot this card
		# sits at (cards land at action_5..; user may have rebound them).
		var slot_index = i + 5
		var key_text = "%d" % (i + 1)
		if client_ref and client_ref.has_method("get_action_key_name"):
			var pulled = str(client_ref.get_action_key_name(slot_index))
			if pulled != "":
				key_text = pulled
		if key_lbl:
			key_lbl.text = key_text

		if i >= _combat_hand.size():
			# Empty slot
			cell.set_meta("card_name", "")
			cell.set_meta("can_afford", false)
			if name_lbl:
				name_lbl.text = "—"
			if cost_lbl:
				cost_lbl.text = ""
			if cost_pip:
				cost_pip.visible = false
			if value_pip:
				value_pip.visible = false
			if pips_lbl:
				pips_lbl.text = ""
			if effect_lbl:
				effect_lbl.text = ""
			if glyph_lbl:
				glyph_lbl.text = ""
			var _ai_empty: Control = cell.find_child("ArtImg", true, false)
			if _ai_empty:
				_ai_empty.visible = false
			if emblem_lbl:
				emblem_lbl.text = ""
			cell.tooltip_text = ""
			if fill_rect:
				fill_rect.visible = false
			_set_cell_dim(cell, true, false)
			continue

		var card_name = str(_combat_hand[i])
		var info = _resolve_card_info(card_name)
		cell.set_meta("card_name", card_name)
		cell.set_meta("can_afford", bool(info.get("can_afford", true)))

		# Category theming — banner colour + icon.
		var category_info: Dictionary = {}
		if client_ref and client_ref.has_method("get_ability_category_info"):
			category_info = client_ref.get_ability_category_info(card_name)
		var category_color_hex := str(category_info.get("color", "#8C7656"))
		cell.set_meta("category_color", category_color_hex)
		if glyph_lbl:
			glyph_lbl.text = str(category_info.get("glyph", ""))
			glyph_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
		# v0.9.683 — companion cards render the companion's monster art in place of
		# the glyph.
		var art_img: Control = cell.find_child("ArtImg", true, false)
		var _cart := companion_card_art_bbcode(card_name)
		if _cart != "":
			if art_img:
				_apply_card_art(art_img, _cart)
				art_img.visible = true
			if glyph_lbl:
				glyph_lbl.visible = false
		else:
			if art_img:
				art_img.visible = false
			if glyph_lbl:
				glyph_lbl.visible = true
		if banner:
			var bsb := banner.get_theme_stylebox("panel") as StyleBoxFlat
			if bsb:
				# v0.9.675 — deepen the category colour for the banner so white
				# title text stays high-contrast on bright categories (e.g. green
				# Buff) while the hue still reads clearly.
				bsb.bg_color = Color(category_color_hex).darkened(0.42)
		# Race/class identity: emblem badge + accent line in the class colour.
		if emblem_lbl:
			emblem_lbl.text = _class_emblem_text()
			emblem_lbl.add_theme_color_override("font_color", _theme_class_color())
		if accent:
			accent.color = _theme_class_color()

		# Mastery fill — washes UP from the bottom in category colour as the card
		# nears its next rank-up (full = about to rank up).
		if fill_rect:
			var at_max_rank := bool(info.get("rank_at_max", false))
			var prog := 1.0 if at_max_rank else clampf(float(info.get("rank_progress", 0.0)), 0.0, 1.0)
			fill_rect.anchor_top = 1.0 - prog
			fill_rect.offset_top = 0
			fill_rect.visible = prog > 0.001
			var cat_col := Color(category_color_hex)
			cat_col.a = 0.30
			fill_rect.color = cat_col

		if name_lbl:
			_fit_label_font(name_lbl, str(info.get("display", card_name)), 98)
			name_lbl.add_theme_color_override("font_color", Color("#FFFFFF"))

		# v0.9.690 — the sticky description box (mouse_entered) replaces the plain
		# native tooltip so numbers + the formula popup work; clear it to avoid a
		# double tooltip.
		cell.tooltip_text = ""

		# Cost pip — number in a resource-tinted circle.
		var planned_int = int(info.get("planned_cost", 0))
		var resource_type = str(info.get("resource_type", ""))
		if cost_pip:
			cost_pip.visible = true
			var csb := cost_pip.get_theme_stylebox("panel") as StyleBoxFlat
			if csb:
				var rc := _resource_color(resource_type) if resource_type != "" else Color("#888888")
				csb.bg_color = Color(rc.r * 0.45, rc.g * 0.45, rc.b * 0.45, 0.96)
				csb.border_color = rc
				csb.set_border_width_all(2)
		if cost_lbl:
			# v0.9.72x — show NET cost after this turn's passive regen (cost − regen),
			# e.g. a 20-cost card with 14 regen shows 6, so the number reflects what the
			# card actually drains from your bar. Regen mirrors combat_manager's capped
			# model (min(16%-of-max, 25+lvl·0.5), floor 4).
			var _regen := _estimate_turn_regen(resource_type)
			cost_lbl.text = "%d" % maxi(0, planned_int - _regen)

		# v0.9.691 — damage/heal value pip (base estimate from your stats).
		if value_pip and value_lbl and client_ref and client_ref.has_method("_ability_primary_value"):
			var pv: Dictionary = client_ref._ability_primary_value(card_name)
			var pv_kind := str(pv.get("kind", ""))
			if pv_kind == "damage":
				value_lbl.text = "⚔ %d" % int(pv.get("value", 0))
				value_lbl.add_theme_color_override("font_color", Color("#FF7A5A"))
				value_pip.visible = true
			elif pv_kind == "heal":
				value_lbl.text = "♥ %d" % int(pv.get("value", 0))
				value_lbl.add_theme_color_override("font_color", Color("#7AE07A"))
				value_pip.visible = true
			else:
				value_pip.visible = false

		# Rank pips (0-6 filled dots), coloured by rank.
		if pips_lbl:
			var rank = clampi(int(info.get("rank", 0)), 0, 6)
			pips_lbl.text = "●".repeat(rank) + "○".repeat(6 - rank)
			pips_lbl.add_theme_color_override("font_color", Color(HAND_RANK_COLORS[clampi(rank, 0, HAND_RANK_COLORS.size() - 1)]))

		if effect_lbl:
			effect_lbl.text = str(info.get("effect_text", ""))
			effect_lbl.add_theme_color_override("font_color", Color(str(info.get("effect_color", "#FFA060"))))

		# v0.9.697 — BUILDER cards advertise that they feed the finisher, so it's
		# clear WHICH cards add Momentum / Combo. Finishers (devastate/gambit) show
		# their own state below and are excluded here. Only the matching class's
		# archetype abilities build the meter (universal/companion cards don't).
		if effect_lbl and (_momentum_active or _combo_active or _focus_active):
			var _arch := Character.get_ability_archetype(card_name)
			if _momentum_active and _arch == "warrior" and card_name != "devastate":
				var _e := effect_lbl.text
				effect_lbl.text = "+⚡ Momentum" if _e == "" else "+⚡  %s" % _e
				effect_lbl.add_theme_color_override("font_color", Color("#C8A24A"))
			elif _combo_active and _arch == "trickster":
				var _e2 := effect_lbl.text
				effect_lbl.text = "+◉ Read" if _e2 == "" else "+◉  %s" % _e2
				effect_lbl.add_theme_color_override("font_color", Color("#7FD8C8"))
			elif _focus_active and _arch == "mage" and card_name != "meteor":
				var _e3 := effect_lbl.text
				effect_lbl.text = "+◈ Focus" if _e3 == "" else "+◈  %s" % _e3
				effect_lbl.add_theme_color_override("font_color", Color("#5AC8FF"))

		# v0.9.696 — Warrior Devastate is gated behind Momentum: it can't be played
		# with 0 Momentum. Render it as uncastable (dimmed + hint) until the meter
		# has at least 1 pip, mirroring the server gate in _process_warrior_ability.
		var castable := bool(info.get("can_afford", true))
		if _momentum_active and card_name == "devastate" and _momentum < 1:
			castable = false
			cell.set_meta("can_afford", false)
			if effect_lbl:
				effect_lbl.text = "Build Momentum first"
				effect_lbl.add_theme_color_override("font_color", Color("#C8A24A"))
			if value_pip:
				value_pip.visible = false

		# v0.9.697 — Mage Meteor DISCHARGES Focus (bigger per-Focus bonus, resets ramp).
		# Not gated; the note shows the payoff for spending the ramp now.
		if _focus_active and card_name == "meteor" and effect_lbl:
			if _focus >= _focus_max:
				effect_lbl.text = "Discharge! +%d%%" % int(_focus * 25)
				effect_lbl.add_theme_color_override("font_color", Color("#7AE0FF"))
			elif _focus > 0:
				effect_lbl.text = "Discharge +%d%%" % int(_focus * 25)
				effect_lbl.add_theme_color_override("font_color", Color("#5AC8FF"))
			else:
				effect_lbl.text = "Ramp Focus first"
				effect_lbl.add_theme_color_override("font_color", Color("#6E7E8A"))

		_set_cell_dim(cell, false, castable)
		# v0.9.715 — class payoff cards get a meter-scaled glow: Devastate
		# (Momentum, hard-locked at 0) and Meteor (Focus, soft-dim at 0).
		_apply_finisher_visual(cell, card_name, castable)

	# Status line
	if _hand_status_label:
		_hand_status_label.text = "[color=#5CE05C]Deck %d[/color]  [color=#888888]·[/color]  [color=#FF6B6B]Discard %d[/color]" % [_combat_deck_count, _combat_discard_count]
	# v0.9.385 — mirror deck / hand / discard into the Lufia in-box label.
	if _lufia_player_deck_label and is_instance_valid(_lufia_player_deck_label):
		var hand_size := _combat_hand.size()
		_lufia_player_deck_label.text = "[color=#5CE05C]Deck %d[/color] [color=#888888]· Hand %d ·[/color] [color=#FF6B6B]Discard %d[/color]" % [_combat_deck_count, hand_size, _combat_discard_count]
	# v0.9.601 — mirror to the FX overlay deck label too.
	if _overlay_player_deck_label and is_instance_valid(_overlay_player_deck_label):
		var hand_size_overlay := _combat_hand.size()
		_overlay_player_deck_label.text = "Deck %d · Hand %d · Discard %d" % [_combat_deck_count, hand_size_overlay, _combat_discard_count]


func _set_cell_dim(cell: PanelContainer, empty: bool, can_afford: bool) -> void:
	"""Adjust cell border/bg to convey state. Empty = very muted; uncastable
	= mid muted; castable = full-color category border.
	v0.9.425 — per-card category color (set in _refresh_hand via meta) drives
	the active border. Empty / uncastable fall back to neutral muted tones so
	an unaffordable Phantom Strike doesn't shout 'utility blue' at the player."""
	var sb := cell.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	# v0.9.715 — reset the finisher glow (Devastate/Gambit) each refresh and kill
	# any running pulse; _apply_finisher_visual re-adds them if this card is a
	# finisher. Keeps stale halos off cards that changed slots.
	sb.shadow_size = 0
	# NOTE: get_meta(name, null) is NOT a safe read — Godot treats a null default as "no
	# default given" and pushes an error, which spammed the log on every hand refresh
	# (54 errors in one fight) and buried real ones. Check has_meta first.
	var _prev_pulse = cell.get_meta("finisher_pulse") if cell.has_meta("finisher_pulse") else null
	if _prev_pulse != null and is_instance_valid(_prev_pulse):
		_prev_pulse.kill()
	cell.set_meta("finisher_pulse", null)
	# v0.9.675 — the whole card fades for empty / uncastable states (clearer than
	# a subtle bg shift on a framed card); castable cards show the category border
	# at full colour. bg stays dark so the mastery fill reads.
	if empty:
		sb.border_color = Color(0.20, 0.18, 0.14, 1)
		sb.bg_color = Color(0.05, 0.05, 0.06, 0.9)
		cell.modulate = Color(1, 1, 1, 0.35)
	elif not can_afford:
		sb.border_color = Color(str(cell.get_meta("category_color", "#8C7656")))
		sb.bg_color = _theme_card_bg()
		cell.modulate = Color(0.72, 0.72, 0.74, 0.9)
	else:
		sb.border_color = Color(str(cell.get_meta("category_color", "#B08C4C")))
		sb.bg_color = _theme_card_bg()
		cell.modulate = Color(1, 1, 1, 1)


func _apply_finisher_visual(cell: PanelContainer, card_name: String, castable: bool) -> void:
	"""v0.9.715 — meter-scaled glow for the class PAYOFF hand cards so their state
	reads at a glance:
	  • building → class-coloured border + a halo that grows with the meter
	  • full     → a gentle looping pulse so 'ready' grabs the eye
	Devastate (Warrior/Momentum) is HARD-gated, so at 0 it gets a locked grey.
	Meteor (Mage/Focus) is NOT gated (castable but weak at 0 Focus), so at 0 it
	just soft-dims. The Trickster payoff is the Outsmart action-bar button (styled
	in client.gd), not a hand card — Gambit is a normal card, no finisher glow."""
	var meter: int = 0
	var meter_max: int = 5
	var glow_col: Color
	var hard_lock: bool = false
	if _momentum_active and card_name == "devastate":
		meter = _momentum
		meter_max = _momentum_max
		glow_col = Color("#FFC94D")  # gold
		hard_lock = true
	elif _focus_active and card_name == "meteor":
		meter = _focus
		meter_max = _focus_max
		glow_col = Color("#5AC8FF")  # cyan
		hard_lock = false
	else:
		return
	var sb := cell.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	# Devastate's Momentum lock takes priority — grey it HARD whenever the meter is
	# empty, since that's exactly why it can't fire (overrides the plain dim).
	if hard_lock and meter < 1:
		sb.border_color = Color(0.34, 0.32, 0.30, 1.0)
		sb.set_border_width_all(2)
		sb.shadow_size = 0
		cell.modulate = Color(0.5, 0.5, 0.53, 0.8)
		return
	# Beyond the lock, a charged glow only makes sense if the card is actually
	# castable — don't paint an unaffordable card as 'ready'. Let the standard
	# uncastable dim (from _set_cell_dim) stand.
	if not castable:
		return
	if meter < 1:
		# Meteor casts (weakly) at 0 Focus — soft-dim + no glow, nudging the player
		# to ramp Focus first without looking disabled.
		sb.shadow_size = 0
		cell.modulate = Color(0.78, 0.80, 0.84, 0.92)
		return
	var t: float = clampf(float(meter) / float(max(1, meter_max)), 0.0, 1.0)
	sb.border_color = glow_col.lerp(Color.WHITE, 0.15 * t)
	sb.set_border_width_all(int(round(2 + 2 * t)))  # 2 → 4
	var glow := glow_col
	glow.a = 0.20 + 0.55 * t
	sb.shadow_color = glow
	sb.shadow_size = int(round(2 + 8 * t))  # 2 → 10 px halo
	cell.modulate = Color(1, 1, 1, 1)
	if t >= 0.999:
		# Ready — pulse the halo. tween_method rewrites shadow_size each step; the
		# tween is killed/reset in _set_cell_dim on the next _refresh_hand.
		var pulse := create_tween().set_loops()
		var _pulse_set := func(s: float):
			var _sb := cell.get_theme_stylebox("panel") as StyleBoxFlat
			if _sb:
				_sb.shadow_size = int(round(s))
		pulse.tween_method(_pulse_set, 10.0, 16.0, 0.55).set_trans(Tween.TRANS_SINE)
		pulse.tween_method(_pulse_set, 16.0, 10.0, 0.55).set_trans(Tween.TRANS_SINE)
		cell.set_meta("finisher_pulse", pulse)


func _estimate_turn_regen(resource_type: String) -> int:
	# Mirror combat_manager's per-turn base regen so cards can show NET cost.
	# regen = clamp(16%-of-max, floor 4, cap = 25 + level·0.5). Only the class's
	# primary resource regenerates; non-matching types return 0.
	if client_ref == null or not ("character_data" in client_ref):
		return 0
	var cd = client_ref.character_data
	if not (cd is Dictionary):
		return 0
	var max_res := 0
	match resource_type:
		"mana": max_res = int(cd.get("max_mana", 0))
		"stamina": max_res = int(cd.get("max_stamina", 0))
		"energy": max_res = int(cd.get("max_energy", 0))
		_: return 0
	if max_res <= 0:
		return 0
	var level := int(cd.get("level", 1))
	var pct_regen := int(float(max_res) * 16.0 / 100.0)
	var cap := 25 + int(float(level) * 0.5)
	return mini(maxi(4, pct_regen), cap)

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
			# v0.9.694 — the damage/heal pip shows the number now, so strip it from
			# the effect line (leaving only the secondary tag, e.g. "+bleed") to
			# avoid two different-looking numbers on the same card.
			var _et := str(eff.get("text", ""))
			var _rx := RegEx.new()
			_rx.compile("~\\s*[0-9]+\\s*dmg|Heal\\s+[0-9]+")
			info["effect_text"] = _rx.sub(_et, "", true).strip_edges()
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
			info["rank_progress"] = _rank_progress_from_uses(uses)
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
	# v0.9.716 — synced to character.gd's compressed v0.9.701 curve (was stale
	# [10,50,250,1200,4000,10000], so card rank pips read wrong after #48).
	var thresholds = [10, 35, 100, 275, 650, 1400]
	var rank = 0
	for t in thresholds:
		if uses >= int(t):
			rank += 1
		else:
			break
	return rank

func _rank_progress_from_uses(uses: int) -> float:
	# v0.9.665 — fraction (0-1) toward the NEXT mastery rank, for the card fill.
	# Returns 1.0 at max rank. Mirrors _rank_from_uses thresholds.
	# v0.9.716 — synced to the compressed v0.9.701 curve (card fill read wrong after #48).
	var thresholds = [10, 35, 100, 275, 650, 1400]
	var rank = _rank_from_uses(uses)
	if rank >= thresholds.size():
		return 1.0
	var prev_t: int = 0 if rank == 0 else int(thresholds[rank - 1])
	var next_t: int = int(thresholds[rank])
	if next_t <= prev_t:
		return 0.0
	return clampf(float(uses - prev_t) / float(next_t - prev_t), 0.0, 1.0)


func _short_resource_label(rt: String) -> String:
	match rt:
		"mana": return "MN"
		"stamina": return "ST"
		"energy": return "EN"
	return ""


func _resource_type_for_class(cls: String) -> String:
	"""Reliable player-resource type from class (matches character.gd get_class_path)."""
	match cls:
		"Wizard", "Sorcerer", "Sage": return "mana"
		"Fighter", "Barbarian", "Paladin": return "stamina"
		"Thief", "Ranger", "Ninja": return "energy"
	return ""


func _resource_type_from_color(c: Color) -> String:
	"""Derive the resource type from its bar color (server sends color, not the
	type string). Nearest-match against the three known resource colors."""
	var best := ""
	var best_d := 0.35
	for rt in ["mana", "stamina", "energy"]:
		var rc := _resource_color(rt)
		var d: float = absf(c.r - rc.r) + absf(c.g - rc.g) + absf(c.b - rc.b)
		if d < best_d:
			best_d = d
			best = rt
	return best


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
	show_item_picker() during combat_item_mode.

	v0.9.428 — parented to the panel root (not _log_inner) so the picker
	covers the FULL combat scene area, not just the small log strip. In the
	Lufia layout _log_inner is too short to render the items ScrollContainer
	(title + Prev/Next buttons consumed all of its vertical space, leaving
	the item list with 0px). z_index=200 keeps it above the battlefield
	overlay (z=100) and victory/death cards (z=150)."""
	_picker_overlay = PanelContainer.new()
	_picker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_overlay.z_index = 200
	# Inset from the panel edges so the player can still see the underlying
	# combat scene around the picker — feels less like a modal takeover.
	_picker_overlay.offset_left = 24
	_picker_overlay.offset_right = -24
	_picker_overlay.offset_top = 24
	_picker_overlay.offset_bottom = -24
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
	add_child(_picker_overlay)

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
		# v0.9.429 — hover tooltip with the same effect description the
		# regular inventory shows on inspect. Caller passes "tooltip" in the
		# entry dict.
		var tip := str(entry.get("tooltip", ""))
		if tip != "":
			btn.tooltip_text = tip
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
	_last_refresh_payload = payload  # v0.9.664 — cached for layout-cycle re-populate
	if not is_inside_tree():
		return
	# v0.9.501 — drop the "hp_drain_initialized" meta so the first refresh
	# after a new combat starts snaps the bar to the starting HP instead of
	# animating from the previous combat's final value (which would look
	# wrong, e.g., draining from 0 → max on a clean re-engage).
	for bar in [_player_hp_bar, _monster_hp_bar, _companion_hp_bar,
			_lufia_player_hp_bar, _lufia_monster_hp_bar,
			_overlay_player_hp_bar, _overlay_companion_hp_bar]:
		if bar != null and is_instance_valid(bar):
			bar.remove_meta("hp_drain_initialized")
	if payload.has("player_class"):
		_player_class = str(payload["player_class"])
	if payload.has("player_name"):
		_player_name = str(payload["player_name"])
	if payload.has("player_battler_id"):
		_player_battler_id = str(payload["player_battler_id"])
	if payload.has("player_equipped") and payload["player_equipped"] is Dictionary:
		_player_equipped = payload["player_equipped"]
	if payload.has("player_race"):
		_player_race = str(payload["player_race"])
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
	# v0.9.439 — reset Review FX state for the new fight. No history yet, so
	# button stays hidden until the first round fires.
	_in_review_phase = false
	if _review_button and is_instance_valid(_review_button):
		_review_button.visible = false
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
	# v0.9.739 — hold the drop until the monster's incoming trail lands on us.
	_apply_bar_after_travel("local", func():
		_player_hp = current
		_player_max_hp = maxi(1, max_hp)
		if is_inside_tree():
			_refresh_player_hp())


func update_monster_hp(current: int, max_hp: int, known: bool, exceeded: bool = false) -> void:
	_apply_bar_after_travel("monster", func(): _set_monster_hp_now(current, max_hp, known, exceeded))


func _set_monster_hp_now(current: int, max_hp: int, known: bool, exceeded: bool = false) -> void:
	_monster_hp = current
	_monster_max_hp = maxi(1, max_hp)
	_monster_hp_known = known
	_monster_hp_exceeded = exceeded
	if is_inside_tree():
		_refresh_monster_hp()


func set_monster_defeated() -> void:
	"""v0.9.663 — drain the monster HP bar to 0 on the killing blow. Combat ends
	via the victory path (no combat_update carries monster_hp=0), so without this
	the bar keeps its last non-zero value when the monster dies."""
	# v0.9.739 — the killing blow drains only after its own animation has landed.
	_apply_bar_after_travel("monster", func():
		_monster_hp = 0
		_monster_hp_known = true
		_monster_hp_exceeded = false
		if is_inside_tree():
			_refresh_monster_hp())


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
	# v0.9.439 — log now has content; Review FX button can show on the next
	# transition out of action phase.
	_update_review_button_visibility()


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
	# v0.9.425 — diagnostic print removed; routing fix landed (indent alone
	# now classifies monster-turn lines, regardless of content prefix).
	return _classify_overlay_actor_inner(raw)


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
	# v0.9.425 — any line carrying the monster-turn indent (5+ leading spaces
	# from _indent_multiline) belongs to the monster. Earlier "You "/"Your "
	# overrides already peeled off the player/companion lines that can occur
	# inside an indented block (e.g., "You gain N experience!"), so by the
	# time we reach this point an indented line must be monster-emitted.
	# The previous rule required content.begins_with("The "), which dropped
	# monster ability bangs like "AMBUSH! The Wolf strikes from the shadows!"
	# or "BLOODIED FURY!" into the player strip.
	if leading_ws >= 5:
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
	# v0.9.611 — also archive the per-actor overlay strips (player / monster /
	# companion log lines) so Review FX can swap to a prior fight's content.
	if archive and _log_lines.size() > 0 and _monster_name != "":
		_flock_history.append({
			"monster_name": _monster_name,
			"color": _monster_name_color,
			"level": _monster_level,
			"art": _monster_art_bbcode,
			"lines": _log_lines.duplicate(),
			"overlay_player_lines": _overlay_player_log_lines.duplicate(),
			"overlay_monster_lines": _overlay_monster_log_lines.duplicate(),
			"overlay_companion_lines": _overlay_companion_log_lines.duplicate(),
		})
		if _flock_history.size() > FLOCK_HISTORY_LIMIT:
			_flock_history = _flock_history.slice(_flock_history.size() - FLOCK_HISTORY_LIMIT)
	_log_lines.clear()
	# v0.9.611 — also clear the overlay strips for the new fight, so the
	# FX scene starts fresh per encounter (without this, prior fight's
	# strips would persist and stack with the new fight's events).
	_overlay_player_log_lines.clear()
	_overlay_monster_log_lines.clear()
	_overlay_companion_log_lines.clear()
	if is_inside_tree():
		_refresh_log()
		_refresh_overlay_strips_from_lines()


func reset_flock_history() -> void:
	_flock_history.clear()


func get_flock_history() -> Array:
	return _flock_history.duplicate()


# v0.9.611 — Review-FX pagination across flock chain. -1 = current (live)
# fight, 0..N-1 indexes _flock_history. Buttons + key handler swap which
# fight the per-actor overlay strips show.
var _review_fight_index: int = -1
var _review_prev_btn: Button = null
var _review_next_btn: Button = null
var _review_pagination_label: Label = null
# Cached snapshot of the current fight's overlay strip lines, captured the
# moment we enter review mode. Restoring this when the player paginates
# back to "current" avoids touching live arrays for past fights.
var _review_live_player_lines: Array = []
var _review_live_monster_lines: Array = []
var _review_live_companion_lines: Array = []


func _refresh_overlay_strips_from_lines() -> void:
	"""v0.9.611 — paint the three per-actor overlay RichTextLabels from
	the current _overlay_*_log_lines arrays. Used by clear_log and by
	the review-pagination swap path so the strips reflect whatever fight
	is being viewed."""
	if _overlay_player_log and is_instance_valid(_overlay_player_log):
		_overlay_player_log.text = "\n".join(_overlay_player_log_lines)
	if _overlay_monster_log and is_instance_valid(_overlay_monster_log):
		_overlay_monster_log.text = "\n".join(_overlay_monster_log_lines)
	if _overlay_companion_log and is_instance_valid(_overlay_companion_log):
		_overlay_companion_log.text = "\n".join(_overlay_companion_log_lines)


func _swap_review_to_fight(idx: int) -> void:
	"""v0.9.611 — swap the per-actor strips to the requested fight.
	idx == -1: live current fight (restored from _review_live_*_lines)
	idx >= 0: archived entry from _flock_history.
	Out of bounds is clamped to -1."""
	var total: int = _flock_history.size() + 1
	if total <= 1:
		return
	# Clamp to valid range [0, _flock_history.size()] where last is current.
	var linear: int = total - 1 if idx == -1 else idx
	linear = clampi(linear, 0, total - 1)
	if linear == total - 1:
		_review_fight_index = -1
		_overlay_player_log_lines = _review_live_player_lines.duplicate()
		_overlay_monster_log_lines = _review_live_monster_lines.duplicate()
		_overlay_companion_log_lines = _review_live_companion_lines.duplicate()
		# Restore the monster header to the current fight's monster.
		_review_fight_index = -1
	else:
		_review_fight_index = linear
		var entry: Dictionary = _flock_history[linear]
		_overlay_player_log_lines = (entry.get("overlay_player_lines", []) as Array).duplicate()
		_overlay_monster_log_lines = (entry.get("overlay_monster_lines", []) as Array).duplicate()
		_overlay_companion_log_lines = (entry.get("overlay_companion_lines", []) as Array).duplicate()
	_refresh_overlay_strips_from_lines()
	_update_review_pagination_label()


func _update_review_pagination_label() -> void:
	if _review_pagination_label == null or not is_instance_valid(_review_pagination_label):
		return
	var total: int = _flock_history.size() + 1
	var current: int = total if _review_fight_index == -1 else (_review_fight_index + 1)
	var tag: String = "  (current)" if _review_fight_index == -1 else ""
	_review_pagination_label.text = "Fight %d of %d%s" % [current, total, tag]
	# Hide arrows when single-fight (nothing to paginate).
	if _review_prev_btn:
		_review_prev_btn.visible = total > 1
		_review_prev_btn.disabled = (_review_fight_index == 0)
	if _review_next_btn:
		_review_next_btn.visible = total > 1
		_review_next_btn.disabled = (_review_fight_index == -1)


func _on_review_prev_pressed() -> void:
	_swap_review_to_fight(_review_fight_index_step(-1))


func _on_review_next_pressed() -> void:
	_swap_review_to_fight(_review_fight_index_step(1))


func _review_fight_index_step(delta: int) -> int:
	var total: int = _flock_history.size() + 1
	var linear: int = total - 1 if _review_fight_index == -1 else _review_fight_index
	linear = clampi(linear + delta, 0, total - 1)
	if linear == total - 1:
		return -1
	return linear


# v0.9.612 — removed the keyboard ← / → pagination handler. The arrow
# keys conflict with overworld movement; players now use the visible
# ◀ Prev Fight / Next Fight ▶ buttons exclusively.


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
	but at a tiny font size + clipped to a small portrait box.
	v0.9.569 — only Lufia layout remains (standard / chrono pruned), so
	this is effectively `true`. Helper kept as a single switch point in
	case a future non-compact alternate gets added."""
	return true


const COMPACT_PORTRAIT_PX := 96  # v0.9.385 — square chrono party-row portrait size (px)
# v0.9.389 — Lufia portrait box bumped to fit the full ~75-line Minotaur ASCII
# (~200 tall at font_size 1 with the font's minimum line height). Box height
# dominates because monster art is taller than wide in our content; Barbarian
# class art is 100×55 chars which fits at font_size 2.
# v0.9.663 — cards shrunk (user: "too large"). Height is the big lever since the
# party-box row height drives how much vertical room the monster band gets.
const COMPACT_PORTRAIT_W := 168  # companion portrait (was 200)
const COMPACT_PORTRAIT_H := 138  # both portraits (was 180)
# v0.9.392 — player portrait gets its own narrower width since player ASCII
# (~100 chars wide at font_size 2 ≈ ~120px rendered) was leaving ~80px of dead
# space on the right of the 200-wide portrait before the stat bars started.
const COMPACT_PLAYER_PORTRAIT_W := 168  # v0.9.663 — matched to companion (COMPACT_PORTRAIT_W) so both cards are the same size + a bigger player sprite
const COMPACT_BAR_W := 108  # v0.9.388 — fixed-width bars (no EXPAND_FILL stretch); v0.9.663 120->108
# v0.9.663 — monster ASCII auto-fit tuning. FILL_RATIO leaves a margin so the art
# never kisses the cards; CHROME_RESERVE accounts for the name + HP widgets that
# share the monster column above the art.
const MONSTER_FILL_RATIO := 0.9
const MONSTER_CHROME_RESERVE := 84.0
const COMPACT_ASCII_FONT_SIZE := 1  # v0.9.385 — companion ASCII font_size in compact layouts
# v0.9.389 — player class ASCII uses a slightly larger font so the figure is
# legible. Player art is ~100 chars wide, so font 2 stays inside the 200px box.
const COMPACT_PLAYER_ASCII_FONT_SIZE := 2


func _ensure_battler_timer() -> void:
	if _battler_timer != null:
		return
	_battler_timer = Timer.new()
	_battler_timer.wait_time = 0.34
	_battler_timer.one_shot = false
	add_child(_battler_timer)
	_battler_timer.timeout.connect(_on_battler_tick)

func _apply_combat_equip_glyphs(markers: Array) -> void:
	"""Spawn equipment glyph Labels over the combat sprite. Deferred one frame so
	the sprite rect has its laid-out size for anchor positioning."""
	if not (_player_sprite_rect and is_instance_valid(_player_sprite_rect)):
		return
	await get_tree().process_frame
	if not (_player_sprite_rect and is_instance_valid(_player_sprite_rect)):
		return
	var gpx := int(max(8.0, _player_sprite_rect.size.y / 15.0))
	EquipmentMarkers.spawn_glyphs(_player_sprite_rect, markers, null, gpx)


func _battler_id_for(cls: String, char_name: String) -> String:
	# v0.9.670 — prefer the character's STORED battler_id (from the combat payload)
	# so combat + the map avatar / info / status / hover all show the SAME sprite.
	# Falls back to the legacy name-hash derivation for any character without one.
	if _player_battler_id != "":
		return _player_battler_id
	return BattlerSprite.id_for(cls, char_name)

func _load_battler(cls: String) -> bool:
	var id: String = _battler_id_for(cls, _player_name)
	if id == "":
		return false
	var folder: String = BATTLER_DIR + "tf/" + id + "/"
	var idle: Array = []
	var atk: Array = []
	var magic: Array = []
	var bow: Array = []
	for i in range(3):
		var it = load(folder + "idle_%d.png" % i)
		if it != null:
			idle.append(it)
		var at = load(folder + "atk_%d.png" % i)
		if at != null:
			atk.append(at)
		var mg = load(folder + "magic_%d.png" % i)
		if mg != null:
			magic.append(mg)
		var bw = load(folder + "bow_%d.png" % i)
		if bw != null:
			bow.append(bw)
	if idle.is_empty():
		return false
	_battler_idle = idle
	_battler_atk = atk
	_battler_magic = magic
	_battler_bow = bow
	return true

func _show_player_battler() -> void:
	_ensure_battler_timer()
	_battler_active = true
	_battler_frame = 0
	_battler_atk_playing = false
	if _ascii_outer and is_instance_valid(_ascii_outer):
		_ascii_outer.visible = false
	if _player_sprite_holder and is_instance_valid(_player_sprite_holder):
		_player_sprite_holder.visible = true
	if _player_sprite_rect and is_instance_valid(_player_sprite_rect):
		_player_sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_player_sprite_rect.flip_h = true  # RPG-Maker battlers face left; face the enemy
		_player_sprite_rect.texture = _battler_idle[0]
		# v0.9.671 — per-character identity tint (self_modulate multiplies UNDER
		# the FX modulate channel, so fades/flashes/grey-out still work).
		_player_sprite_rect.self_modulate = BattlerSprite.tint_color(_player_appearance_color)
		_player_sprite_rect.visible = true
		# v0.9.672 — per-equipped-piece region tint (shader) + glyph markers.
		var _eq_markers := EquipmentMarkers.markers_for(_player_equipped)
		_player_sprite_rect.material = EquipmentMarkers.build_tint_material(_eq_markers)
		_apply_combat_equip_glyphs(_eq_markers)
	if _player_sprite_placeholder and is_instance_valid(_player_sprite_placeholder):
		_player_sprite_placeholder.visible = false
	_battler_timer.start()

func _on_battler_tick() -> void:
	if _battler_active and not _battler_atk_playing and not _battler_idle.is_empty():
		_battler_frame = (_battler_frame + 1) % _battler_idle.size()
		if _player_sprite_rect and is_instance_valid(_player_sprite_rect):
			_player_sprite_rect.texture = _battler_idle[_battler_frame]
			_bob_equip_glyphs(_battler_frame)
	# Party members idle-animate on the same timer (co-op #64 Slice 2).
	_advance_party_member_frames()


func _bob_equip_glyphs(frame: int) -> void:
	"""Nudge equipment glyphs to match the idle bob (TF idle frame 2 sits ~1px
	lower in the 48px source; scaled to the on-screen sprite height)."""
	if not (_player_sprite_rect and is_instance_valid(_player_sprite_rect)):
		return
	const BOB_SRC := [0.0, 0.0, 1.0]  # per-idle-frame vertical shift, source px
	var scale: float = _player_sprite_rect.size.y / 48.0
	var dy: float = float(BOB_SRC[frame % BOB_SRC.size()]) * scale
	for ch in _player_sprite_rect.get_children():
		if ch.has_meta("eq_glyph") and ch.has_meta("eq_base_pos"):
			var base: Vector2 = ch.get_meta("eq_base_pos")
			ch.position = Vector2(base.x, base.y + dy)

func _set_sprite_texture(tex) -> void:
	if _player_sprite_rect and is_instance_valid(_player_sprite_rect):
		_player_sprite_rect.texture = tex

func play_battler_attack() -> void:
	# Step forward toward the enemy, swing (atk frames), step back to idle.
	if not _battler_active or _battler_atk_playing or _battler_idle.is_empty():
		return
	var rect = _player_sprite_rect
	if rect == null or not is_instance_valid(rect):
		return
	_battler_atk_playing = true
	var home: Vector2 = rect.position
	var fwd: Vector2 = home + Vector2(22, 0)  # sprite is flipped to face right = toward enemy
	var frames: Array = _battler_atk if not _battler_atk.is_empty() else _battler_idle
	var t := create_tween()
	t.tween_property(rect, "position", fwd, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for f in frames:
		t.tween_callback(_set_sprite_texture.bind(f))
		t.tween_interval(0.08)
	t.tween_property(rect, "position", home, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_end_battler_attack.bind(home))

func _end_battler_attack(home = null) -> void:
	_battler_atk_playing = false
	if _player_sprite_rect and is_instance_valid(_player_sprite_rect):
		if home != null:
			_player_sprite_rect.position = home
		if not _battler_idle.is_empty():
			_player_sprite_rect.texture = _battler_idle[_battler_frame % _battler_idle.size()]

func play_battler_cast(frames: Array) -> void:
	# Cast/bow: cycle frames with a small forward lean + step back (mages/archers
	# don't rush in like melee, but a little motion reads better than none).
	if not _battler_active or _battler_atk_playing or frames.is_empty():
		return
	var rect = _player_sprite_rect
	if rect == null or not is_instance_valid(rect):
		return
	_battler_atk_playing = true
	var home: Vector2 = rect.position
	var fwd: Vector2 = home + Vector2(10, 0)
	var t := create_tween()
	t.tween_property(rect, "position", fwd, 0.12).set_trans(Tween.TRANS_SINE)
	for f in frames:
		t.tween_callback(_set_sprite_texture.bind(f))
		t.tween_interval(0.10)
	t.tween_property(rect, "position", home, 0.14).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_end_battler_attack.bind(home))

func play_battler_action() -> void:
	# Route a player action to the class-appropriate animation.
	if not _battler_active:
		return
	var style: String = String(BATTLER_ANIM_STYLE.get(_player_class, "atk"))
	if style == "magic" and not _battler_magic.is_empty():
		play_battler_cast(_battler_magic)
	elif style == "bow" and not _battler_bow.is_empty():
		play_battler_cast(_battler_bow)
	else:
		play_battler_attack()

func is_battler_animating() -> bool:
	return _battler_active and _battler_atk_playing

func _refresh_player() -> void:
	# COMBAT REDESIGN test — pixel battler sprite for classes with a battler folder.
	if _load_battler(_player_class):
		_show_player_battler()
		var _cc := ClassSprite.get_class_color(_player_class)
		var _hx := "#%02X%02X%02X" % [int(_cc.r * 255), int(_cc.g * 255), int(_cc.b * 255)]
		if _player_name_label:
			_player_name_label.text = "[color=%s]%s[/color] [color=#888888](%s)[/color]" % [_hx, _player_name, _player_class]
		_refresh_player_hp()
		return
	if _battler_active:
		_battler_active = false
		if _battler_timer:
			_battler_timer.stop()
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
	_animate_bar_value(_player_hp_bar, clampi(_player_hp, 0, _player_max_hp))
	_player_hp_text.text = "HP %d / %d" % [maxi(0, _player_hp), _player_max_hp]
	# v0.9.385 — mirror to the Lufia in-box HP widget when it exists.
	if _lufia_player_hp_bar and is_instance_valid(_lufia_player_hp_bar):
		_lufia_player_hp_bar.max_value = _player_max_hp
		_animate_bar_value(_lufia_player_hp_bar, clampi(_player_hp, 0, _player_max_hp))
	if _lufia_player_hp_text and is_instance_valid(_lufia_player_hp_text):
		_lufia_player_hp_text.text = "HP %d / %d" % [maxi(0, _player_hp), _player_max_hp]
	# v0.9.601 — mirror to FX overlay HP widgets when overlay exists.
	if _overlay_player_hp_bar and is_instance_valid(_overlay_player_hp_bar):
		_overlay_player_hp_bar.max_value = _player_max_hp
		_animate_bar_value(_overlay_player_hp_bar, clampi(_player_hp, 0, _player_max_hp))
	if _overlay_player_hp_text and is_instance_valid(_overlay_player_hp_text):
		_overlay_player_hp_text.text = "HP %d / %d" % [maxi(0, _player_hp), _player_max_hp]
	# Resource bar — mirror to pre-FX Lufia + FX overlay using current cached
	# values. Color reflects class resource type.
	_refresh_player_resource()


func _refresh_player_resource() -> void:
	"""v0.9.601 — paint the new player resource bars (pre-FX Lufia + FX overlay)
	from _player_resource_cur/max/color. Called from _refresh_player_hp and
	from refresh() so resource updates land with every payload."""
	if _lufia_player_resource_bar and is_instance_valid(_lufia_player_resource_bar):
		_lufia_player_resource_bar.max_value = maxi(1, _player_resource_max)
		_animate_bar_value(_lufia_player_resource_bar, clampi(_player_resource_cur, 0, _player_resource_max))
		var lufia_fill: StyleBox = _lufia_player_resource_bar.get_theme_stylebox("fill")
		if lufia_fill is StyleBoxFlat:
			(lufia_fill as StyleBoxFlat).bg_color = _player_resource_color
	if _lufia_player_resource_text and is_instance_valid(_lufia_player_resource_text):
		# v0.9.663 — prefix the short resource label (EN / MN / ST). Prefer the
		# class mapping (reliable); fall back to matching the bar color.
		var _rt := _resource_type_for_class(_player_class)
		if _rt == "":
			_rt = _resource_type_from_color(_player_resource_color)
		var _rlbl := _short_resource_label(_rt)
		var _rprefix := ("%s " % _rlbl) if _rlbl != "" else ""
		_lufia_player_resource_text.text = "%s%d / %d" % [_rprefix, maxi(0, _player_resource_cur), _player_resource_max]
	if _overlay_player_resource_bar and is_instance_valid(_overlay_player_resource_bar):
		_overlay_player_resource_bar.max_value = maxi(1, _player_resource_max)
		_animate_bar_value(_overlay_player_resource_bar, clampi(_player_resource_cur, 0, _player_resource_max))
		var ov_fill: StyleBox = _overlay_player_resource_bar.get_theme_stylebox("fill")
		if ov_fill is StyleBoxFlat:
			(ov_fill as StyleBoxFlat).bg_color = _player_resource_color
	if _overlay_player_resource_text and is_instance_valid(_overlay_player_resource_text):
		_overlay_player_resource_text.text = "%d / %d" % [maxi(0, _player_resource_cur), _player_resource_max]


# v0.9.501 — Combat readability: tween HP/companion/monster bar drain instead
# of snapping. Kills any in-progress tween on the bar so rapid hits don't queue
# stale tweens. Text labels (e.g., "HP 84/150") still update instantly via the
# caller — the bar is the dramatic reveal; the number is the truth.
# 2026-08-27 — drain sped up 1.0s → 0.45s (player feedback: bar updates felt
# sluggish in turn-based pacing). Still visible as a drain, just not laggy.
func _animate_bar_value(bar: ProgressBar, target: float, dur: float = 0.45) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	# v0.9.591 — Godot 4.6 prints an error when get_meta() is called on a key
	# that hasn't been set, even with a default value. Check has_meta first to
	# avoid log spam on every bar refresh.
	var prev = null
	if bar.has_meta("hp_drain_tween"):
		prev = bar.get_meta("hp_drain_tween")
	if prev != null and is_instance_valid(prev):
		prev.kill()
	# Special case: first frame of combat / panel rebuild — snap, don't drain
	# from 0 → max which would look like the player was at 0 HP a moment ago.
	if not bar.has_meta("hp_drain_initialized"):
		bar.value = target
		bar.set_meta("hp_drain_initialized", true)
		return
	var t := create_tween()
	bar.set_meta("hp_drain_tween", t)
	t.tween_property(bar, "value", target, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
		_animate_bar_value(_companion_hp_bar, clampi(current_hp, 0, max_hp))
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
	# Travel from the monster (the attacker) toward the companion — with a launch
	# delay so the monster's lunge reads BEFORE the number flies.
	# v0.9.739 — and hold it until the monster's incoming trail lands, same as every
	# other combatant ("local" is the key the monster's outgoing trail stamps).
	var _cd := maxf(0.30, _travel_pending_s("local"))
	_note_number_visible("local", _cd)
	_spawn_damage_label(anchor_global, amount, is_crit, "monster", true, _attacker_anchor_global("monster"), _cd)


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
	# read on the companion's stat presence. v0.9.508 — aggro role tag.
	var role_tag := ""
	if client_ref != null and client_ref.has_method("_get_aggro_role_info"):
		var bonuses_for_aggro: Dictionary = _companion_data.get("bonuses", {})
		var aggro_value := int(bonuses_for_aggro.get("aggro", 25))
		var role_info: Dictionary = client_ref._get_aggro_role_info(aggro_value)
		var role_label := str(role_info.get("label", ""))
		var role_color := str(role_info.get("color", "#FFFFFF"))
		if role_label != "":
			# v0.9.663 — conservatively sized: small font, title-case (not ALLCAPS),
			# no bold, so it reads as a quiet stance label rather than shouting over
			# the companion's name.
			role_tag = "  [font_size=9][color=%s]%s[/color][/font_size]" % [role_color, role_label.capitalize()]
	_companion_name_label.text = "[color=%s]%s[/color] [color=#888888]Lv %d T%d %s[/color]%s" % [variant_color, name, level, sub_tier, variant, role_tag]

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
			# v0.9.572 — companion border tier visual. Re-color the outermost
			# non-whitespace character of every art line in the border-tier's
			# hue so a Rare-bordered Goblin gets a blue silhouette outline,
			# Epic gets purple, Mythic gets gold. The natural body color of
			# the art (variant pattern recolor above) stays intact in the
			# middle of each line. Tier 0 (None) skips the call entirely.
			var _border_tier := int(_companion_data.get("border_tier", 0))
			var _border_color_for_tier := ""
			match _border_tier:
				1: _border_color_for_tier = "#FFFFFF"  # Common
				2: _border_color_for_tier = "#1EFF00"  # Uncommon
				3: _border_color_for_tier = "#0070DD"  # Rare
				4: _border_color_for_tier = "#A335EE"  # Epic
				5: _border_color_for_tier = "#FF8000"  # Legendary
				6: _border_color_for_tier = "#FFD700"  # Mythic
			if _border_color_for_tier != "":
				raw_art = MonsterArt.apply_variant_border(raw_art, _border_color_for_tier)
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


func _get_niche_passive_tag() -> String:
	"""v0.9.510 — return a colored "[DIVINE FAVOR +25%]" / "[HUNTER'S MARK +25%]"
	tag for the current monster if the player's class passive applies. Empty
	string for classes without a damage-by-type niche, or monsters that don't
	match. Uses CombatManager's authoritative keyword lists + substring match
	helper so the tag tracks 1:1 with the actual damage bonus applied
	server-side (no drift)."""
	if _monster_name == "":
		return ""
	# CombatManager._monster_matches_keywords looks at monster.type and
	# monster.name (lowercased) for substring matches. The combat panel only
	# holds the display name; pass it as both fields so variant prefixes
	# ("Corrosive Skeleton", "★ Lich Champion") still match.
	var monster_dict := {"name": _monster_name, "type": _monster_name}
	if _player_class == "Paladin":
		if CombatManager._monster_matches_keywords(monster_dict, CombatManager._UNDEAD_DEMON_KEYWORDS):
			return " [color=#FFD700][DIVINE FAVOR +25%][/color]"
	elif _player_class == "Ranger":
		if CombatManager._monster_matches_keywords(monster_dict, CombatManager._BEAST_KEYWORDS):
			return " [color=#228B22][HUNTER'S MARK +25%][/color]"
	return ""


func _refresh_monster() -> void:
	if _monster_name == "":
		_monster_name_label.text = ""
		_monster_art_label.text = ""
		_monster_hp_bar.visible = false
		_monster_hp_text.text = ""
		return

	# v0.9.510 — niche-passive surface. Paladin's Divine Favor (+25% vs
	# undead/demons) and Ranger's Hunter's Mark (+25% vs beasts) silently
	# apply during combat. Surfacing the tag on the monster name makes the
	# passive's relevance discoverable per encounter. Closes Audit #2
	# captured item "niche-passive audit (undead/beast frequency)" by
	# making the bonus visible at the point it triggers, rather than hidden
	# in the damage formula.
	var niche_tag := _get_niche_passive_tag()
	_monster_name_label.text = "[color=%s]%s[/color] [color=#FFD700]Lv %d[/color]%s" % [_monster_name_color, _monster_name, _monster_level, niche_tag]
	# v0.9.650 — apply the per-element user scale by rewriting the font_size
	# tag in the stored BBCode. Source BBCode looks like
	# `[right][font_size=N]...[/font_size][/right]`; we multiply N by the
	# user's chosen scale (default 1.0 = no change). Clamped to ≥ 2 so the
	# ASCII stays visible at extreme shrink.
	# v0.9.663 — recompute auto-fit from current geometry, then render at the
	# combined (auto × user) scale. The deferred re-apply corrects the scale once
	# the panel has settled its post-visibility layout on the first combat.
	_monster_art_auto_scale = _compute_monster_autofit_scale()
	_reapply_monster_art_text()
	call_deferred("_apply_monster_autofit_deferred")
	_monster_hp_bar.visible = true
	_refresh_monster_hp()


func _reapply_monster_art_text() -> void:
	"""Render _monster_art_bbcode into the label at the combined auto × user
	scale by rewriting its baked font_size tag."""
	if _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var art: String = _monster_art_bbcode
	var combined: float = _monster_art_auto_scale * _monster_art_user_scale
	if not is_equal_approx(combined, 1.0) and art != "":
		var rx := RegEx.new()
		rx.compile("font_size=(\\d+)")
		var m: RegExMatch = rx.search(art)
		if m != null:
			var old_size: int = int(m.get_string(1))
			var new_size: int = max(2, int(round(old_size * combined)))
			art = art.replace("font_size=%d" % old_size, "font_size=%d" % new_size)
	# v0.9.663 — center the art horizontally within its (full-width) column. Strip
	# any baked [right]/[left] alignment first (the server art carried a side
	# alignment from the old layout, which overrode our [center]). This is BBCode
	# text alignment, so it doesn't touch the node position the lunge tweens use.
	if art != "":
		art = art.replace("[right]", "").replace("[/right]", "").replace("[left]", "").replace("[/left]", "")
		if not art.begins_with("[center]"):
			art = "[center]" + art + "[/center]"
	_monster_art_label.text = art


func _apply_monster_autofit_deferred() -> void:
	"""Recompute the auto-fit scale after layout settles; re-render only if it
	actually changed (avoids churn and infinite re-defer loops)."""
	if _monster_name == "" or _monster_art_bbcode == "":
		return
	var new_scale: float = _compute_monster_autofit_scale()
	if is_equal_approx(new_scale, _monster_art_auto_scale):
		return
	_monster_art_auto_scale = new_scale
	_reapply_monster_art_text()


func _strip_bbcode(s: String) -> String:
	var rx := RegEx.new()
	rx.compile("\\[[^\\]]*\\]")
	return rx.sub(s, "", true)


func _compute_monster_autofit_scale() -> float:
	"""Scale so the monster ASCII fills its available band. Uses the mono font's
	metrics + the raw art dimensions (rows × cols) rather than a render pass, so
	it's deterministic and flicker-free. Returns 1.0 when geometry isn't ready."""
	if _monster_art_bbcode == "" or _mono_font == null:
		return 1.0
	# v0.9.663 — the monster owns the right column now, so fit to THAT band
	# (its own width × height), not the whole scene minus the party row.
	if _monster_col == null or not is_instance_valid(_monster_col):
		return 1.0
	var band: Vector2 = _monster_col.size
	if band.x < 60.0 or band.y < 60.0:
		return 1.0
	var base_size: int = 0
	var rx := RegEx.new()
	rx.compile("font_size=(\\d+)")
	var fm: RegExMatch = rx.search(_monster_art_bbcode)
	if fm != null:
		base_size = int(fm.get_string(1))
	if base_size <= 0:
		return 1.0
	var raw: String = _strip_bbcode(_monster_art_bbcode).strip_edges()
	if raw == "":
		return 1.0
	var lines: PackedStringArray = raw.split("\n")
	var rows: int = lines.size()
	var cols: int = 0
	for l in lines:
		cols = maxi(cols, (l as String).rstrip(" ").length())
	if rows <= 0 or cols <= 0:
		return 1.0
	var char_w: float = _mono_font.get_string_size("W", HORIZONTAL_ALIGNMENT_LEFT, -1, base_size).x
	var line_h: float = _mono_font.get_height(base_size)
	if char_w <= 0.0 or line_h <= 0.0:
		return 1.0
	var art_w: float = float(cols) * char_w
	var art_h: float = float(rows) * line_h
	var avail_w: float = maxf(80.0, band.x - 16.0)
	var avail_h: float = maxf(80.0, band.y - MONSTER_CHROME_RESERVE)
	var s: float = minf(avail_w / art_w, avail_h / art_h) * MONSTER_FILL_RATIO
	return clampf(s, 0.25, 1.5)


func set_monster_art_user_scale(scale: float) -> void:
	"""Set the per-element scale multiplier for the monster ASCII and re-render.
	Called by the UIScaleManager applier from attach_ui_scale_manager."""
	_monster_art_user_scale = clampf(scale, 0.3, 3.0)
	# Re-render — _refresh_monster bails early if there's no monster, which is
	# the right behavior (nothing to scale until combat starts).
	if _monster_name != "":
		_refresh_monster()


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
	_animate_bar_value(_monster_hp_bar, clampi(_monster_hp, 0, _monster_max_hp))
	# v0.9.587 — when the player has out-damaged the known ceiling but the
	# monster's still alive, label the bar so the discovery moment reads.
	var hp_text: String
	if _monster_hp_exceeded:
		hp_text = "HP 0 / %d  (still alive!)" % _monster_max_hp
	else:
		hp_text = "HP %d / %d" % [maxi(0, _monster_hp), _monster_max_hp]
	_monster_hp_text.text = hp_text
	if _lufia_monster_hp_bar and is_instance_valid(_lufia_monster_hp_bar):
		_lufia_monster_hp_bar.max_value = _monster_max_hp
		_animate_bar_value(_lufia_monster_hp_bar, clampi(_monster_hp, 0, _monster_max_hp))
		# v0.9.395 — tint the Lufia bar fill to the monster's affinity color.
		# _monster_name_color is supplied per-monster from the server payload
		# (matches the name-tint in the monster name label).
		var fill_sb: StyleBoxFlat = _lufia_monster_hp_bar.get_theme_stylebox("fill")
		if fill_sb != null:
			fill_sb.bg_color = Color.from_string(_monster_name_color, Color("#FFAA22"))
	if _lufia_monster_hp_text and is_instance_valid(_lufia_monster_hp_text):
		_lufia_monster_hp_text.text = hp_text


func _refresh_log() -> void:
	_log_label.text = "\n".join(_log_lines)
	# COMBAT REDESIGN — mirror the most recent lines into the always-visible band.
	if _battle_log_band and is_instance_valid(_battle_log_band):
		# v0.9.664 — show the last 7 lines so a full combat round (divider + party
		# + enemy actions + a status line) fits the taller band without clipping.
		_battle_log_band.text = "
".join(_log_lines)  # v0.9.664 full log (scrollback)
	# v0.9.415 — RichTextLabel.fit_content expands asynchronously: one frame
	# isn't always enough for `get_v_scroll_bar().max_value` to reflect the
	# new content height, so the auto-scroll silently snaps to a stale max.
	# Wait two frames AND re-apply after the resized signal lands.
	await get_tree().process_frame
	await get_tree().process_frame
	if _battle_log_scroll and is_instance_valid(_battle_log_scroll):
		var bar := _battle_log_scroll.get_v_scroll_bar()
		if bar:
			_battle_log_scroll.scroll_vertical = int(bar.max_value)


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
	# COMBAT REDESIGN — the pixel battler animates on card play (play_battler_action
	# from client.send_combat_command), so the message-timed lunge is a no-op here
	# to avoid double-firing.
	if _battler_active:
		return
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


# === 2026-08-27 — Get-hit recoil (struck-back knockback) ===

func recoil_player() -> void:
	_recoil_node(_player_visual_for_fx())

func recoil_companion() -> void:
	_recoil_node(_companion_art)

func _recoil_node(node: Control) -> void:
	"""Struck reaction: the target is knocked back to the LEFT (away from the
	enemy on the right) then snaps home with a slight overshoot. Pairs with the
	white flash so a hit LANDING on the player/companion is obvious at a glance —
	not just a number the player has to notice. Reuses the shared lunge_baseline
	so it returns to the true rest position."""
	if node == null or not is_instance_valid(node):
		return
	var base: Vector2
	if node.has_meta("lunge_baseline"):
		base = node.get_meta("lunge_baseline")
	else:
		base = node.position
		node.set_meta("lunge_baseline", base)
	if node.has_meta("recoil_tween"):
		var prev = node.get_meta("recoil_tween")
		if prev != null and is_instance_valid(prev):
			prev.kill()
	node.position = base
	var t := create_tween()
	node.set_meta("recoil_tween", t)
	t.tween_property(node, "position", base + Vector2(-12.0, 0.0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "position", base, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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

	# Clamp the START inside the panel — the label rises from here, so leave
	# headroom below the top edge for the float.
	label.position.y = maxf(label.position.y, 40.0)

	# 2026-08-27 — MISS now uses the SAME rise-and-fade as damage numbers so it
	# reads as part of the same visual family and actually catches the eye. The
	# old version was a brief static pop (~0.8s) that players watching the enemy
	# art routinely missed — they'd wait for a number that never came. Pop in,
	# float up, fade; paired with a subtle whiff SFX on the client side.
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(1.3, 1.3)
	var start_pos: Vector2 = label.position
	var life := 1.0
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "scale", Vector2(1.0, 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position:y", start_pos.y - 46.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var miss_fade := life * 0.45
	t.tween_property(label, "modulate:a", 0.0, miss_fade).set_delay(life - miss_fade).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(label.queue_free).set_delay(life + 0.05)


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


func _attacker_anchor_global(source: String) -> Vector2:
	"""Screen-space center of the ATTACKER, used as the travel origin for a
	damage number. source: 'player' → your sprite, 'companion' → companion art,
	'monster' → monster art. Returns Vector2(INF,INF) (no-travel sentinel) when
	the node isn't available so the number just spawns at the target."""
	var node: Control = null
	match source:
		"companion":
			node = _companion_art
		"monster":
			node = _monster_art_label
		_:
			node = _player_visual_for_fx()
	if node == null or not is_instance_valid(node):
		return Vector2(INF, INF)
	return node.global_position + node.size * 0.5


func show_damage_on_monster(amount: int, is_crit: bool, source: String = "player", from_override: Vector2 = Vector2(INF, INF)) -> void:
	"""Spawn a floating damage number above the monster art.
	source: 'player' (yellow), 'companion' (cyan), 'crit' override (red, larger)."""
	if _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var anchor_global = _monster_art_label.global_position + Vector2(_monster_art_label.size.x * 0.5, _monster_art_label.size.y * 0.25)
	# Travel from the ATTACKER (player or companion) so the number visibly comes
	# from whoever dealt it — the at-a-glance "who hit" cue. Player attacks read
	# instantly (their battler already stepped on card-play); companion hits get a
	# short launch delay so the companion's lunge reads BEFORE the number flies.
	var _tdelay: float = 0.30 if source == "companion" else 0.0
	# #76 Slice 3 — a TEAMMATE's hit must launch from THEIR card, not from our own battler,
	# so co-op passes the acting member's anchor explicitly.
	var _from: Vector2 = from_override if from_override.x != INF else _attacker_anchor_global(source)
	# v0.9.739 — wait for the trail. If a travel FX is still flying at the monster, hold the
	# number until it lands so the hit reads as CAUSED by the animation rather than arriving
	# ahead of it. Nothing in flight -> unchanged behaviour.
	_tdelay = maxf(_tdelay, _travel_pending_s("monster"))
	_note_number_visible("monster", _tdelay)
	_spawn_damage_label(anchor_global, amount, is_crit, source, false, _from, _tdelay)


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
	# Travel from the monster (the attacker) toward the player — with a launch
	# delay so the monster's lunge reads BEFORE the number flies.
	# v0.9.739 — and hold it until the monster's incoming trail actually lands on us.
	var _pd := maxf(0.30, _travel_pending_s("local"))
	_note_number_visible("local", _pd)
	_spawn_damage_label(anchor_global, amount, is_crit, "monster", true, _attacker_anchor_global("monster"), _pd)


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

	# v0.9.501: DoT tick lifetime ~3× longer to match the readability ask
	# applied to direct-hit damage popups.
	var float_distance := 40.0
	var lifetime := 2.55
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

func _spawn_damage_label(anchor_global: Vector2, amount: int, is_crit: bool, source: String, target_is_player: bool, from_global: Vector2 = Vector2(INF, INF), travel_delay: float = 0.0) -> void:
	# 2026-08-27 readability redesign: clean rise-and-fade (normal proportions,
	# short life). Optional `from_global` = the ATTACKER's screen position; when
	# given, the number launches from the attacker and flies to the target before
	# settling, so motion origin shows WHO dealt it (player vs companion sit at
	# different spots). Sentinel Vector2(INF,INF) = no travel (spawn at target).
	# `travel_delay` holds the number invisible at the attacker for a beat so the
	# attacker's LUNGE reads first, THEN the number launches — used for companion
	# and enemy hits (whose lunge fires on the same message) so the order matches
	# player attacks (character steps → number flies), not the reverse.
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
	# 2026-08-27 readability redesign: small horizontal jitter only (numbers stay
	# near the sprite that was hit so they're traceable), no static upward stack —
	# the rise-and-fade motion below separates sequential hits on its own.
	var x_jitter := randf_range(-8.0, 8.0)

	# SETTLE point = the target anchor (where the number ends up + rises from).
	var target_local: Vector2 = anchor_global - global_position - label.size * 0.5
	target_local += Vector2(x_jitter, 0.0)
	# Keep the settle point inside the panel — the rise floats up from here, so
	# leave headroom below the top edge for the float.
	target_local.y = maxf(target_local.y, 40.0)

	# Optional travel: launch FROM the attacker and fly to the target. Motion
	# origin tells the player who dealt it; then it settles + rises so it stays
	# readable. Sentinel Vector2(INF,INF) → no travel (spawn straight at target).
	var has_travel: bool = from_global.x < 1e19 and from_global.y < 1e19
	var travel_t := 0.0
	if has_travel:
		label.position = from_global - global_position - label.size * 0.5
		# Player attacks (no launch delay) fly FAST so the number arrives right on
		# the heels of their battler step; companion/enemy hits (delayed launch)
		# travel at a normal pace after their lunge has already read.
		travel_t = 0.03 if travel_delay <= 0.0 else 0.15
	else:
		label.position = target_local

	# d0 = launch delay: hold the number invisible at the attacker so its lunge
	# reads first, then the number appears + flies. Only meaningful with travel.
	var d0: float = travel_delay if has_travel else 0.0
	if d0 > 0.0:
		label.modulate.a = 0.0

	# Readable rise-and-fade: normal proportions, quick pop-in, then float UP
	# while fading. Short life (~1.1s, crits ~1.3s) so numbers don't crowd.
	var rest_scale := Vector2(1.0, 1.0)
	var rise_px := 52.0 if not is_crit else 68.0
	var life := 1.1 if not is_crit else 1.3
	label.rotation = 0.0
	label.scale = Vector2(1.35, 1.35)
	var t := create_tween().set_parallel(true)
	# At launch time (d0): fade in (if it was held), pop in, flash to color.
	if d0 > 0.0:
		t.tween_property(label, "modulate:a", 1.0, 0.05).set_delay(d0)
	t.tween_property(label, "scale", rest_scale, 0.14).set_delay(d0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "theme_override_colors/font_color", color, 0.16).set_delay(d0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Travel attacker → target (fast), if requested.
	if has_travel:
		t.tween_property(label, "position", target_local, travel_t).set_delay(d0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Float upward from the settle point (begins after launch delay + travel).
	t.tween_property(label, "position:y", target_local.y - rise_px, life).set_delay(d0 + travel_t).from(target_local.y).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fade out over the last ~45% of life.
	var fade_time := life * 0.45
	t.tween_property(label, "modulate:a", 0.0, fade_time).set_delay(d0 + travel_t + life - fade_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Crit: brief horizontal shake after arrival (position:x only, so it doesn't
	# fight the vertical rise running in parallel).
	if is_crit:
		var shake_amp := 5.0
		for i in range(4):
			var dly := d0 + travel_t + 0.02 + i * 0.045
			t.tween_property(label, "position:x", target_local.x + randf_range(-shake_amp, shake_amp), 0.045).set_delay(dly).set_trans(Tween.TRANS_SINE)
		t.tween_property(label, "position:x", target_local.x, 0.045).set_delay(d0 + travel_t + 0.02 + 4 * 0.045)

	t.tween_callback(label.queue_free).set_delay(d0 + travel_t + life + 0.05)


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


# v0.9.664 — each attack/skill type draws from its own random char pool + color.
# Physical trails leave "color" empty and take the attacker's color instead.
const _TRAVEL_FX_TYPES := {
	"fire":      {"pool": "*^~×+=#%", "color": "#FF6622"},
	"ice":       {"pool": "+.:*=<>~", "color": "#66DDFF"},
	"lightning": {"pool": "zZ/\\~+×!", "color": "#FFEE44"},
	"poison":    {"pool": "~.:;+*=%", "color": "#77CC33"},
	"holy":      {"pool": "+*✦✧.~=", "color": "#FFE39A"},
	"arcane":    {"pool": "✦✧●~*+=<", "color": "#CC66FF"},
	"physical":  {"pool": "~*^+=xX/\\<>»«-", "color": ""},
}

func _random_trail_from_pool(pool: String) -> String:
	# A fresh random ASCII trail each attack (not a fixed glyph).
	var n: int = 2 + (randi() % 3)  # 2-4 chars
	var s: String = ""
	for i in range(n):
		s += pool[randi() % pool.length()]
	return s

# v0.9.739 — travel-trail flight time. Was 0.36s, which read as an instant flicker once
# several actors were animating in sequence; the user asked for 1/3 speed so the eye can
# actually follow a trail from its caster to its target. Every travel FX shares this, and
# the client's PARTY_ACTOR_HEAD_DELAY is matched to it so the damage number lands as the
# trail arrives rather than before it.
const TRAVEL_FX_DURATION: float = 1.08


func play_travel_fx(attacker: String, fx_type: String = "physical") -> void:
	"""v0.9.664 — a short RANDOM ASCII trail (unique char pool + color per attack
	type) that flies from the attacker to the target, rotated along the path,
	ending in an impact burst. attacker = player|companion|monster."""
	var entry: Dictionary = _TRAVEL_FX_TYPES.get(fx_type, _TRAVEL_FX_TYPES["physical"])
	var glyph: String = _random_trail_from_pool(entry["pool"])
	var color: Color
	if String(entry["color"]) == "":
		color = Color("#FFCC44")  # player: gold
		if attacker == "companion":
			color = Color("#66DDFF")  # companion: cyan
		elif attacker == "monster":
			color = Color("#FF5555")  # monster: red
	else:
		color = Color(entry["color"])
	var from_node: Control = null
	var to_node: Control = null
	if attacker == "monster":
		from_node = _monster_art_label
		to_node = _player_party_box
	elif attacker == "companion":
		from_node = _companion_party_box
		to_node = _monster_art_label
	else:
		from_node = _player_party_box
		to_node = _monster_art_label
	_note_travel_arrival("local" if attacker == "monster" else "monster")
	_travel_fx_between(from_node, to_node, glyph, color)


# v0.9.739 — when the trail currently flying at each target will LAND, in ticks-msec.
# Keyed "monster" or a party pid. Damage numbers consult this so a hit never pops before the
# animation that caused it arrives. The trail is 1.08s now; the log pacing that used to hide
# the gap is much shorter than the flight (0.45s in solo), so the number would otherwise beat
# its own animation to the target — which is exactly what made hits hard to attribute.
var _travel_arrival_ms: Dictionary = {}


# v0.9.739 — sequence per bar target, so a deferred update can tell whether it is still the
# newest one when its timer fires. Without this, waits SHRINK as a trail nears its target, so
# a later update could land before an earlier one and the bar would jump backwards.
var _bar_seq: Dictionary = {}


func _apply_bar_after_travel(key, fn: Callable) -> void:
	"""THE RULE (user, 2026-09-01): a health bar must not drop until the damage number for
	that hit has appeared — and the number itself waits for the animation to land. So bars
	and numbers share one gate: if a trail is still flying at `key`, hold the bar change
	until it arrives. Nothing in flight = apply immediately (buffs, DoT ticks, regen)."""
	var seq: int = int(_bar_seq.get(key, 0)) + 1
	_bar_seq[key] = seq
	# Wait for whichever comes LAST: the trail landing, or the number appearing.
	var wait := maxf(_travel_pending_s(key), _number_pending_s(key))
	if wait <= 0.0:
		fn.call()
		return
	get_tree().create_timer(wait).timeout.connect(func():
		if int(_bar_seq.get(key, 0)) == seq:
			fn.call())


# v0.9.739 — when the damage number for each target becomes VISIBLE. The number's own launch
# delay is max(trail flight, a 0.30s hold for companion/monster hits so their lunge reads
# first) — so gating bars on the trail alone dropped them up to 0.30s BEFORE the number they
# belong to appeared. Bars wait on whichever is later.
var _number_visible_ms: Dictionary = {}


func _note_number_visible(target_key, delay_s: float) -> void:
	_number_visible_ms[target_key] = Time.get_ticks_msec() + int(maxf(0.0, delay_s) * 1000.0)


func _number_pending_s(target_key) -> float:
	var left: int = int(_number_visible_ms.get(target_key, 0)) - Time.get_ticks_msec()
	return (float(left) / 1000.0) if left > 0 else 0.0


func _note_travel_arrival(target_key) -> void:
	_travel_arrival_ms[target_key] = Time.get_ticks_msec() + int(TRAVEL_FX_DURATION * 1000.0)


func _travel_pending_s(target_key) -> float:
	"""Seconds until the in-flight trail reaches target_key; 0.0 if nothing is in flight."""
	var left: int = int(_travel_arrival_ms.get(target_key, 0)) - Time.get_ticks_msec()
	return (float(left) / 1000.0) if left > 0 else 0.0


func _travel_fx_between(from_node: Control, to_node: Control, glyph: String, color: Color) -> void:
	"""v0.9.739 — the trail itself, addressed by NODE so a party card can be either end of
	it (teammate -> monster, monster -> the teammate it is striking). play_travel_fx keeps
	the old player/companion/monster shorthand and routes through here."""
	if from_node == null or not is_instance_valid(from_node):
		return
	if to_node == null or not is_instance_valid(to_node):
		return
	var start_global: Vector2 = from_node.global_position + from_node.size * 0.5
	var end_global: Vector2 = to_node.global_position + to_node.size * 0.5
	var label := Label.new()
	label.text = glyph
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 30)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 110
	add_child(label)
	label.reset_size()
	var start_pos: Vector2 = start_global - global_position - label.size * 0.5
	var end_pos: Vector2 = end_global - global_position - label.size * 0.5
	label.position = start_pos
	label.pivot_offset = label.size * 0.5
	label.rotation = (end_pos - start_pos).angle()  # point the trail along the path
	var t := create_tween()
	t.tween_property(label, "position", end_pos, TRAVEL_FX_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_play_impact_burst.bind(end_pos, color))
	t.tween_callback(label.queue_free)


func _travel_fx_glyph_color(fx_type: String, attacker: String) -> Array:
	"""Resolve the trail glyph + colour for an fx type, shared by every travel FX entry
	point so a teammate's trail looks identical to the local player's."""
	var entry: Dictionary = _TRAVEL_FX_TYPES.get(fx_type, _TRAVEL_FX_TYPES["physical"])
	var glyph: String = _random_trail_from_pool(entry["pool"])
	var color: Color
	if String(entry["color"]) == "":
		color = Color("#FFCC44")
		if attacker == "companion":
			color = Color("#66DDFF")
		elif attacker == "monster":
			color = Color("#FF5555")
	else:
		color = Color(entry["color"])
	return [glyph, color]


func play_party_travel_fx(pid: int, fx_type: String = "physical") -> void:
	"""v0.9.739 — trail from a TEAMMATE's card to the monster. Co-op previously had no
	travel FX for anyone but the local player, so a teammate's attack was a bare number."""
	var card := party_card_for_pid(pid)
	if card == null or _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var src := card.get_meta("sprite") as Control
	var gc := _travel_fx_glyph_color(fx_type, "player")
	_note_travel_arrival("monster")
	_travel_fx_between(src, _monster_art_label, gc[0], gc[1])


func play_monster_travel_fx_at(pid: int, fx_type: String = "physical") -> void:
	"""v0.9.739 — trail from the monster to the party card it is striking, so a hit on a
	teammate reads as coming FROM the monster instead of a number appearing from nowhere."""
	var card := party_card_for_pid(pid)
	if card == null or _monster_art_label == null or not is_instance_valid(_monster_art_label):
		return
	var dst := card.get_meta("sprite") as Control
	var gc := _travel_fx_glyph_color(fx_type, "monster")
	_note_travel_arrival(pid)
	_travel_fx_between(_monster_art_label, dst, gc[0], gc[1])


func play_party_buff_aura(pid: int, color: Color = Color("#33CCFF")) -> void:
	"""v0.9.739 — a self-buff (forcefield, iron skin, haste...) cast by a TEAMMATE blooms
	on THEIR card, so every client sees the same effect the caster sees."""
	var card := party_card_for_pid(pid)
	if card == null:
		return
	_buff_aura_on(card.get_meta("sprite") as Control, color)


func play_party_stealth_fade(pid: int, duration: float = 2.0) -> void:
	"""v0.9.739 — Vanish / Cloak / Teleport cast by a TEAMMATE. Fades their card SPRITE
	(not the card, whose modulate the actor spotlight owns) so the two don't fight."""
	var card := party_card_for_pid(pid)
	if card == null:
		return
	var node := card.get_meta("sprite") as Control
	if node == null or not is_instance_valid(node):
		return
	var t := create_tween()
	t.tween_property(node, "modulate:a", 0.4, 0.25)
	t.tween_interval(maxf(0.1, duration - 0.5))
	t.tween_property(node, "modulate:a", 1.0, 0.25)


func play_party_heal_pulse(pid: int) -> void:
	"""v0.9.739 — green bloom on a teammate's card when they heal themselves."""
	play_party_buff_aura(pid, Color("#55FF88"))


func play_buff_aura(color: Color = Color("#33CCFF")) -> void:
	"""Expanding ring of glyphs around the player sprite. Used for self-buffs
	(Haste, Iron Skin, War Cry, Berserk, Fortify)."""
	_buff_aura_on(_player_visual_for_fx(), color)


func _buff_aura_on(node: Control, color: Color) -> void:
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

	# Defeated-monster line. v0.9.511 — also surface the niche-passive tag on
	# the victory card so the player sees a satisfying capstone confirmation
	# that their class bonus was relevant to the kill (pairs with the live
	# combat tag from v0.9.510).
	if _monster_name != "":
		var name_color: String = _monster_name_color if _monster_name_color != "" else "#FFFFFF"
		var niche_tag := _get_niche_passive_tag()
		_victory_card_monster_label.text = "[center][color=#888888]Defeated:[/color] [color=%s][b]%s[/b][/color] [color=#888888](Lv %d)[/color]%s[/center]" % [name_color, _monster_name, _monster_level, niche_tag]
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
	# v0.9.609 — refresh the Review FX button visibility now that the
	# victory card is up. Without this call, the button might stay hidden
	# from a stale check earlier in the action phase even though there's
	# log content the player can now review.
	_update_review_button_visibility()
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
	# v0.9.429 — parented to the panel root (was _log_inner). The log strip is
	# no longer attached to the layout; reparenting here keeps the death card
	# visible across the full combat scene with its z=150 above the
	# battlefield overlay. Match the picker's 24px inset so the card sits
	# inside the panel border rather than flush against it.
	_death_card_overlay.offset_left = 24
	_death_card_overlay.offset_right = -24
	_death_card_overlay.offset_top = 24
	_death_card_overlay.offset_bottom = -24
	add_child(_death_card_overlay)

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


# === v0.9.646 — per-element UI scale registrations ===

func attach_ui_scale_manager(manager: Node) -> void:
	"""Called by client.gd once both the panel and the UIScaleManager exist.
	Registers each scalable element with its own applier so the click-to-
	resize edit mode can find them. Idempotent — re-attaching just re-applies
	the saved scales."""
	if manager == null:
		return
	# Monster ASCII — rewrites the font_size in the BBCode so the ASCII
	# actually re-renders at the new size. The earlier v0.9.646 Control.scale
	# path was clipped by art_holder.clip_contents, so the visible ASCII
	# didn't change even when scale changed.
	if _monster_art_label != null and is_instance_valid(_monster_art_label):
		manager.register(
			"combat_monster_ascii",
			_monster_art_label,
			func(s: float):
				set_monster_art_user_scale(s),
			"Monster ASCII Art (Combat)"
		)
	# Player card — outer PanelContainer.scale, centered. Shrinking moves the
	# player+companion HBox apart visually (good for low-res screens where the
	# cards crowd the monster art).
	if _player_party_box != null and is_instance_valid(_player_party_box):
		manager.register(
			"combat_player_card",
			_player_party_box,
			func(s: float):
				if _player_party_box == null or not is_instance_valid(_player_party_box):
					return
				_player_party_box.pivot_offset = _player_party_box.size / 2.0
				_player_party_box.scale = Vector2(s, s),
			"Player Card (Combat)"
		)
	# Companion card — same pattern as player card.
	if _companion_party_box != null and is_instance_valid(_companion_party_box):
		manager.register(
			"combat_companion_card",
			_companion_party_box,
			func(s: float):
				if _companion_party_box == null or not is_instance_valid(_companion_party_box):
					return
				_companion_party_box.pivot_offset = _companion_party_box.size / 2.0
				_companion_party_box.scale = Vector2(s, s),
			"Companion Card (Combat)"
		)
	# Shared HP strip — the row containing both player + monster HP bars below
	# the scene. Registered as both bars together so resizing affects the whole
	# strip uniformly (per-side split can come in v2 if needed).
	if _player_hp_bar != null and is_instance_valid(_player_hp_bar) and _player_hp_bar.get_parent() != null:
		var strip_parent: Node = _player_hp_bar.get_parent()
		while strip_parent != null and not (strip_parent is HBoxContainer and strip_parent.get_parent() != null and not (strip_parent.get_parent() is HBoxContainer)):
			strip_parent = strip_parent.get_parent()
		if strip_parent is Control:
			manager.register(
				"combat_hp_strip",
				strip_parent,
				func(s: float):
					if strip_parent == null or not is_instance_valid(strip_parent):
						return
					strip_parent.pivot_offset = strip_parent.size / 2.0
					strip_parent.scale = Vector2(s, s),
				"HP Bars Strip (Combat)"
			)
