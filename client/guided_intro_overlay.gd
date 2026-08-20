extends Control
class_name GuidedIntroOverlay

# Phase 2 of the UX arc (see [[feedback_progressive_disclosure]]): a guided
# "spotlight" tour for brand-new players. Dims the whole screen, cuts a hole
# around ONE element at a time, shows a one-sentence caption, and advances on
# Next. Answers the new-player question "what am I supposed to look at?".
#
# Driven entirely by the caller: client.gd calls start([{target, title, body}, ...]).
# `target` is a Control (spotlit) or null (centered card, no spotlight).

signal finished

const DIM := Color(0, 0, 0, 0.72)
const ACCENT := Color(1, 0.85, 0.3)

var _steps: Array = []
var _idx: int = 0
var _current_target: Control = null

var _dim_top: ColorRect
var _dim_bottom: ColorRect
var _dim_left: ColorRect
var _dim_right: ColorRect
var _highlight: Panel
var _card: PanelContainer
var _title_label: Label
var _body_label: RichTextLabel
var _step_label: Label
var _next_btn: Button
var _skip_btn: Button


func _ready() -> void:
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if visible:
		_layout()


func _make_dim() -> ColorRect:
	var c := ColorRect.new()
	c.color = DIM
	c.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks on the dimmed area
	add_child(c)
	return c


func _build() -> void:
	_dim_top = _make_dim()
	_dim_bottom = _make_dim()
	_dim_left = _make_dim()
	_dim_right = _make_dim()

	_highlight = Panel.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0, 0, 0, 0)
	hs.border_color = ACCENT
	hs.set_border_width_all(3)
	hs.set_corner_radius_all(4)
	_highlight.add_theme_stylebox_override("panel", hs)
	_highlight.mouse_filter = Control.MOUSE_FILTER_STOP  # don't let clicks hit the spotlit control mid-tour
	add_child(_highlight)

	_card = PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	cs.border_color = ACCENT
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(6)
	cs.set_content_margin_all(14)
	_card.add_theme_stylebox_override("panel", cs)
	_card.custom_minimum_size = Vector2(360, 0)
	add_child(_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_card.add_child(vb)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 11)
	_step_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vb.add_child(_step_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", ACCENT)
	vb.add_child(_title_label)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.custom_minimum_size = Vector2(340, 0)
	_body_label.add_theme_font_size_override("normal_font_size", 13)
	vb.add_child(_body_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	_skip_btn = Button.new()
	_skip_btn.text = "Skip tour"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.flat = true
	_skip_btn.pressed.connect(_on_skip)
	row.add_child(_skip_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_next_btn = Button.new()
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.custom_minimum_size = Vector2(96, 32)
	_next_btn.pressed.connect(_on_next)
	row.add_child(_next_btn)


func start(steps: Array) -> void:
	if steps.is_empty():
		return
	_steps = steps
	_idx = 0
	visible = true
	move_to_front()
	_show_step()


func _show_step() -> void:
	if _idx >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_idx]
	_step_label.text = "Step %d of %d" % [_idx + 1, _steps.size()]
	_title_label.text = String(step.get("title", ""))
	_body_label.text = String(step.get("body", ""))
	_next_btn.text = "Done" if _idx == _steps.size() - 1 else "Next →"
	_skip_btn.visible = _idx < _steps.size() - 1
	var target = step.get("target")
	_current_target = target if (target is Control and is_instance_valid(target)) else null
	_layout()


func _layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	_card.reset_size()
	var card_size: Vector2 = _card.get_combined_minimum_size()
	card_size.x = max(card_size.x, 360.0)

	if _current_target != null:
		var r: Rect2 = _current_target.get_global_rect().grow(6.0)
		var below_y: float = r.position.y + r.size.y
		var right_x: float = r.position.x + r.size.x
		_dim_top.position = Vector2(0, 0)
		_dim_top.size = Vector2(vp.x, max(0.0, r.position.y))
		_dim_bottom.position = Vector2(0, below_y)
		_dim_bottom.size = Vector2(vp.x, max(0.0, vp.y - below_y))
		_dim_left.position = Vector2(0, r.position.y)
		_dim_left.size = Vector2(max(0.0, r.position.x), r.size.y)
		_dim_right.position = Vector2(right_x, r.position.y)
		_dim_right.size = Vector2(max(0.0, vp.x - right_x), r.size.y)
		for b in [_dim_top, _dim_bottom, _dim_left, _dim_right]:
			b.visible = true
		_highlight.visible = true
		_highlight.position = r.position
		_highlight.size = r.size

		# Place the card below the target, or above if it wouldn't fit.
		var cx: float = clamp(r.position.x + r.size.x / 2.0 - card_size.x / 2.0, 10.0, vp.x - card_size.x - 10.0)
		var cy: float = below_y + 14.0
		if cy + card_size.y > vp.y - 10.0:
			cy = r.position.y - card_size.y - 14.0
		if cy < 10.0:
			cy = clamp(vp.y / 2.0 - card_size.y / 2.0, 10.0, vp.y - card_size.y - 10.0)
		_card.position = Vector2(cx, cy)
	else:
		_dim_top.position = Vector2.ZERO
		_dim_top.size = vp
		_dim_top.visible = true
		for b in [_dim_bottom, _dim_left, _dim_right]:
			b.visible = false
		_highlight.visible = false
		_card.position = Vector2(vp.x / 2.0 - card_size.x / 2.0, vp.y / 2.0 - card_size.y / 2.0)


func _on_next() -> void:
	_idx += 1
	_show_step()


func _on_skip() -> void:
	_finish()


func _finish() -> void:
	visible = false
	_steps = []
	_current_target = null
	finished.emit()
