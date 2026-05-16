extends Control
class_name TutorialHintPanel

# Audit #3 Slice 4 — modal overlay for tutorial/teaching messages. Replaces
# the v0.9.474 game_output-text version of the progression hint per the
# feedback rule "teaching messages must render in overlays, not chat."
#
# Single-use show(title, body) opens a centered modal with a dim backdrop.
# Player dismisses via the "Got it" button or Esc.

signal dismissed

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _body_label: RichTextLabel
var _dismiss_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func show_hint(title: String, body: String) -> void:
	if _title_label:
		_title_label.clear()
		_title_label.append_text(title)
	if _body_label:
		_body_label.clear()
		_body_label.append_text(body)
	visible = true
	if _dismiss_button:
		_dismiss_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key = event.keycode
		if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_on_dismiss()


func _build_layout() -> void:
	# Dim backdrop (blocks input behind panel).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Use a full-rect CenterContainer to keep the panel centered on screen as
	# the viewport resizes. (Setting PRESET_CENTER + KEEP_SIZE directly on the
	# panel anchored it to (0,0) before the panel had a computed size, causing
	# the top-left cutoff seen in v0.9.475/476 tutorial overlays.)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(520, 0)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.10, 0.08, 0.16, 0.98)
	panel_sb.border_color = Color(1.0, 0.84, 0.0, 1.0)  # gold border
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 22
	panel_sb.content_margin_right = 22
	panel_sb.content_margin_top = 18
	panel_sb.content_margin_bottom = 18
	_root_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_root_panel.add_child(vbox)

	# Title (gold, bold).
	_title_label = RichTextLabel.new()
	_title_label.bbcode_enabled = true
	_title_label.fit_content = true
	_title_label.scroll_active = false
	_title_label.add_theme_font_size_override("normal_font_size", 18)
	_title_label.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(_title_label)

	# Body (wraps inside panel width).
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.add_theme_font_size_override("normal_font_size", 14)
	_body_label.custom_minimum_size = Vector2(476, 80)
	vbox.add_child(_body_label)

	# Spacer + dismiss button row.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_dismiss_button = Button.new()
	_dismiss_button.text = "Got it  (Esc / Enter)"
	_dismiss_button.custom_minimum_size = Vector2(220, 32)
	_dismiss_button.focus_mode = Control.FOCUS_ALL
	_dismiss_button.pressed.connect(_on_dismiss)
	btn_row.add_child(_dismiss_button)


func _on_dismiss() -> void:
	visible = false
	dismissed.emit()
