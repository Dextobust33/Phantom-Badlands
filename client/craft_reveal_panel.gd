extends Control
class_name CraftRevealPanel

# Audit #4 Slice 3 — Crafting reveal animation.
# Modal panel that plays a tweened reveal when a craft completes. Replaces the
# raw text-dump of quality in game_output with a tactile moment that scales
# with the boost tier the player committed to.
#
# Flow: open(payload) → fade in → "???" shimmer (phase 1) → flip / label swap
# (phase 2) → quality color sweep + stat subtitle (phase 3) → wait for dismiss.
# Dismissible at any time after the minimum feel-hold window (1.0s) via
# Space / Enter / OK button.

signal dismissed

const MIN_HOLD_SEC := 1.0   # Player can't accidentally skip the first beat
const PHASE_1_END := 1.0
const PHASE_2_END := 1.8
const PHASE_3_END := 2.6

# Quality bucket → display color (matches CraftingDatabase.QUALITY_COLORS).
const QUALITY_COLORS := {
	"Poor": Color(1, 1, 1),
	"Standard": Color(0, 1, 0),
	"Fine": Color(0, 0.44, 0.87),
	"Masterwork": Color(0.64, 0.21, 0.93),
}
const QUALITY_MULTIPLIERS := {
	"Poor": "×0.5 stats",
	"Standard": "×1.0 stats",
	"Fine": "×1.25 stats",
	"Masterwork": "×1.5 stats",
}

var _root_panel: PanelContainer
var _root_stylebox: StyleBoxFlat
var _vbox: VBoxContainer
var _header_label: Label
var _boost_tag: Label
var _card_panel: PanelContainer
var _card_stylebox: StyleBoxFlat
var _card_label: Label
var _name_label: Label
var _quality_label: Label
var _stats_label: Label
var _specialist_save_label: Label
var _ok_button: Button

var _quality_color: Color = Color(0, 1, 0)
var _opened_at: float = 0.0
var _payload: Dictionary = {}
var _shimmer_t: float = 0.0
var _shimmering: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	_build_layout()
	visible = false


func _build_layout() -> void:
	# Backdrop dim
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.65)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(360, 280)
	_root_stylebox = StyleBoxFlat.new()
	_root_stylebox.bg_color = Color(0.08, 0.06, 0.05, 0.98)
	_root_stylebox.border_color = Color(0.55, 0.45, 0.33, 1)
	_root_stylebox.set_border_width_all(2)
	_root_stylebox.set_corner_radius_all(8)
	_root_stylebox.content_margin_left = 16
	_root_stylebox.content_margin_top = 14
	_root_stylebox.content_margin_right = 16
	_root_stylebox.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", _root_stylebox)
	center.add_child(_root_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_root_panel.add_child(_vbox)

	_header_label = Label.new()
	_header_label.text = "✦ CRAFTING ✦"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_header_label.add_theme_font_size_override("font_size", 16)
	_vbox.add_child(_header_label)

	_boost_tag = Label.new()
	_boost_tag.text = ""
	_boost_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boost_tag.add_theme_font_size_override("font_size", 12)
	_vbox.add_child(_boost_tag)

	# Card — the dramatic reveal slot. Border color gets tweened from neutral
	# gray to the quality color in phase 3.
	_card_panel = PanelContainer.new()
	_card_panel.custom_minimum_size = Vector2(320, 90)
	_card_stylebox = StyleBoxFlat.new()
	_card_stylebox.bg_color = Color(0.04, 0.03, 0.02, 1)
	_card_stylebox.border_color = Color(0.45, 0.45, 0.45, 1)
	_card_stylebox.set_border_width_all(2)
	_card_stylebox.set_corner_radius_all(6)
	_card_stylebox.content_margin_left = 12
	_card_stylebox.content_margin_top = 10
	_card_stylebox.content_margin_right = 12
	_card_stylebox.content_margin_bottom = 10
	_card_panel.add_theme_stylebox_override("panel", _card_stylebox)
	_vbox.add_child(_card_panel)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 2)
	card_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_panel.add_child(card_vbox)

	_card_label = Label.new()
	_card_label.text = "???"
	_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_card_label.add_theme_font_size_override("font_size", 32)
	card_vbox.add_child(_card_label)

	_name_label = Label.new()
	_name_label.text = ""
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.modulate.a = 0.0
	_vbox.add_child(_name_label)

	_quality_label = Label.new()
	_quality_label.text = ""
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quality_label.add_theme_font_size_override("font_size", 20)
	_quality_label.modulate.a = 0.0
	_vbox.add_child(_quality_label)

	_stats_label = Label.new()
	_stats_label.text = ""
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.modulate.a = 0.0
	_vbox.add_child(_stats_label)

	_specialist_save_label = Label.new()
	_specialist_save_label.text = ""
	_specialist_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_specialist_save_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_specialist_save_label.add_theme_font_size_override("font_size", 13)
	_specialist_save_label.modulate.a = 0.0
	_vbox.add_child(_specialist_save_label)

	_ok_button = Button.new()
	_ok_button.text = "OK (Space)"
	_ok_button.focus_mode = Control.FOCUS_NONE
	_ok_button.custom_minimum_size = Vector2(0, 32)
	_ok_button.pressed.connect(_on_ok_pressed)
	_vbox.add_child(_ok_button)


func open(payload: Dictionary) -> void:
	"""Show the panel and kick off the reveal animation.

	Payload fields read:
	  recipe_name: String      — displayed once the card flips
	  quality_name: String     — one of Poor/Standard/Fine/Masterwork
	  quality_color: String    — hex (#RRGGBB); falls back to QUALITY_COLORS
	  stats_summary: String    — short rich-text line (ATK/DEF/HP/etc.)
	  boost_tier: String       — none/refined/master; tags the panel
	  specialist_save: bool    — if true, surfaces the gold specialist-save flag
	"""
	_payload = payload
	visible = true
	_opened_at = Time.get_ticks_msec() / 1000.0
	_shimmering = true
	_shimmer_t = 0.0

	# Reset visual state to "pre-reveal".
	_card_label.text = "???"
	_card_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_card_panel.scale = Vector2(1, 1)
	_card_panel.pivot_offset = _card_panel.custom_minimum_size * 0.5
	_card_stylebox.border_color = Color(0.45, 0.45, 0.45, 1)
	_name_label.modulate.a = 0.0
	_quality_label.modulate.a = 0.0
	_stats_label.modulate.a = 0.0
	_specialist_save_label.modulate.a = 0.0
	modulate.a = 0.0

	# Resolve the quality color (server hex wins; fall back to canonical map).
	var qname := String(payload.get("quality_name", "Standard"))
	_quality_color = QUALITY_COLORS.get(qname, Color(0, 1, 0))
	var hex := String(payload.get("quality_color", ""))
	if hex.begins_with("#"):
		var parsed := Color(hex)
		if parsed != Color(0, 0, 0, 1) or hex.to_upper() == "#000000":
			_quality_color = parsed

	# Boost tag — visible commitment cue.
	var boost := String(payload.get("boost_tier", "none"))
	match boost:
		"refined":
			_boost_tag.text = "✦ REFINED ✦"
			_boost_tag.add_theme_color_override("font_color", Color(1, 0.67, 0.40))
			_boost_tag.visible = true
		"master":
			_boost_tag.text = "✦ MASTER ✦"
			_boost_tag.add_theme_color_override("font_color", Color(0.64, 0.21, 0.93))
			_boost_tag.visible = true
		_:
			_boost_tag.text = ""
			_boost_tag.visible = false

	# Tween the panel fade-in.
	var fade_in := create_tween()
	fade_in.tween_property(self, "modulate:a", 1.0, 0.25)

	# Phase 2 — flip the card + reveal the recipe name + quality at PHASE_1_END.
	var flip_in := create_tween()
	flip_in.tween_interval(PHASE_1_END)
	flip_in.tween_callback(_phase_2_flip)

	# Phase 3 — color sweep + stat subtitle reveal at PHASE_2_END.
	var sweep := create_tween()
	sweep.tween_interval(PHASE_2_END)
	sweep.tween_callback(_phase_3_sweep)


func _process(delta: float) -> void:
	if not visible:
		return
	# Pulse the "???" label until phase 2 starts.
	if _shimmering:
		_shimmer_t += delta
		var pulse: float = 0.55 + 0.45 * abs(sin(_shimmer_t * 4.0))
		_card_label.add_theme_color_override("font_color", Color(pulse, pulse, pulse))


func _phase_2_flip() -> void:
	"""Shrink the card horizontally to 0, swap its content to the recipe name +
	quality, then expand back. Reads like a flipped tarot card."""
	_shimmering = false
	var tw := create_tween()
	tw.tween_property(_card_panel, "scale:x", 0.0, 0.18)
	tw.tween_callback(_swap_card_content)
	tw.tween_property(_card_panel, "scale:x", 1.0, 0.22)
	# Reveal the name + quality labels right after the card swap completes.
	var fade := create_tween()
	fade.tween_interval(0.18 + 0.22)
	fade.tween_property(_name_label, "modulate:a", 1.0, 0.25)
	fade.parallel().tween_property(_quality_label, "modulate:a", 1.0, 0.25)


func _swap_card_content() -> void:
	var recipe_name := String(_payload.get("recipe_name", "item"))
	var quality_name := String(_payload.get("quality_name", "Standard"))
	_card_label.text = quality_name.to_upper()
	_card_label.add_theme_color_override("font_color", _quality_color)
	_name_label.text = recipe_name
	_name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_quality_label.text = quality_name
	_quality_label.add_theme_color_override("font_color", _quality_color)


func _phase_3_sweep() -> void:
	"""Sweep the card border color from neutral gray to the quality color, then
	fade in the stat-multiplier subtitle (and specialist save flourish, if set)."""
	var tw := create_tween()
	tw.tween_property(_card_stylebox, "border_color", _quality_color, 0.35)

	var qname := String(_payload.get("quality_name", "Standard"))
	_stats_label.text = String(QUALITY_MULTIPLIERS.get(qname, ""))
	var stats_summary := String(_payload.get("stats_summary", ""))
	if stats_summary != "":
		_stats_label.text += "    " + stats_summary
	var fade := create_tween()
	fade.tween_property(_stats_label, "modulate:a", 1.0, 0.35)

	# Specialist save flourish — only fires when the server tagged this craft.
	if bool(_payload.get("specialist_save", false)):
		_specialist_save_label.text = "★ Specialist Save — one tier higher! ★"
		var save_fade := create_tween()
		save_fade.tween_interval(0.20)
		save_fade.tween_property(_specialist_save_label, "modulate:a", 1.0, 0.30)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	if not event.pressed:
		return
	# Dismiss on Space / Enter (any key works; restrict to those two to avoid
	# accidental dismisses from movement keys).
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		_try_dismiss()
		get_viewport().set_input_as_handled()


func _on_ok_pressed() -> void:
	_try_dismiss()


func _try_dismiss() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _opened_at < MIN_HOLD_SEC:
		return  # Honor minimum feel hold
	close()


func close() -> void:
	visible = false
	_shimmering = false
	emit_signal("dismissed")
