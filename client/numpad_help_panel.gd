extends Control
class_name NumpadHelpPanel

# v0.9.372 — New-character numpad help popup. Shown once per character on
# first login (if the persistent "show for future characters" setting is on,
# default true). Players can toggle it off from the popup itself so the
# preference applies to future characters they create.
#
# Pattern mirrors stones_panel / post_status_panel: dim backdrop +
# centered PanelContainer with a single close button and an inline toggle.

signal dismissed
signal persistent_toggled(show_for_future: bool)

var _root_panel: PanelContainer
var _toggle_check: CheckBox


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(show_for_future_default: bool) -> void:
	_toggle_check.button_pressed = not show_for_future_default
	# Inverted: checkbox label is "Don't show again", so checked = don't show
	visible = true


func close() -> void:
	visible = false


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(540, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.97)
	sb.border_color = Color(0.85, 0.65, 0.27, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_top = 16
	sb.content_margin_right = 18
	sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_root_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Controls — Numpad"
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.27))
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Intro
	var intro := RichTextLabel.new()
	intro.bbcode_enabled = true
	intro.fit_content = true
	intro.scroll_active = false
	intro.add_theme_font_size_override("normal_font_size", 13)
	intro.custom_minimum_size = Vector2(0, 38)
	intro.append_text("[color=#CCCCCC]The best way to control your character is the [color=#FFD700]numpad[/color]. It maps directly to the 8 movement directions, with [color=#FFD700]5[/color] as a hunt action.[/color]")
	vbox.add_child(intro)

	# ASCII numpad layout — uses a monospaced label inside a thin-bordered panel.
	var grid_wrap := PanelContainer.new()
	var grid_sb := StyleBoxFlat.new()
	grid_sb.bg_color = Color(0.02, 0.04, 0.08, 1.0)
	grid_sb.border_color = Color(0.35, 0.55, 0.80, 1.0)
	grid_sb.set_border_width_all(1)
	grid_sb.set_corner_radius_all(4)
	grid_sb.content_margin_left = 12
	grid_sb.content_margin_top = 10
	grid_sb.content_margin_right = 12
	grid_sb.content_margin_bottom = 10
	grid_wrap.add_theme_stylebox_override("panel", grid_sb)
	vbox.add_child(grid_wrap)

	var grid_label := RichTextLabel.new()
	grid_label.bbcode_enabled = true
	grid_label.fit_content = true
	grid_label.scroll_active = false
	grid_label.add_theme_font_size_override("normal_font_size", 17)
	grid_label.custom_minimum_size = Vector2(0, 200)
	# Use BBCode color spans on the key glyphs to draw the eye.
	# Lines are intentionally short + symmetric for readability at any font.
	var grid_text := "[center][color=#FFD700]"
	grid_text += "╔═════╤═════╤═════╗\n"
	grid_text += "║  [color=#FFFFFF]7[/color]  │  [color=#FFFFFF]8[/color]  │  [color=#FFFFFF]9[/color]  ║\n"
	grid_text += "║ [color=#9ACD32]NW[/color]  │  [color=#9ACD32]N[/color]  │ [color=#9ACD32]NE[/color]  ║\n"
	grid_text += "╟─────┼─────┼─────╢\n"
	grid_text += "║  [color=#FFFFFF]4[/color]  │  [color=#FFFFFF]5[/color]  │  [color=#FFFFFF]6[/color]  ║\n"
	grid_text += "║  [color=#9ACD32]W[/color]  │[color=#FF6B6B]HUNT[/color] │  [color=#9ACD32]E[/color]  ║\n"
	grid_text += "╟─────┼─────┼─────╢\n"
	grid_text += "║  [color=#FFFFFF]1[/color]  │  [color=#FFFFFF]2[/color]  │  [color=#FFFFFF]3[/color]  ║\n"
	grid_text += "║ [color=#9ACD32]SW[/color]  │  [color=#9ACD32]S[/color]  │ [color=#9ACD32]SE[/color]  ║\n"
	grid_text += "╚═════╧═════╧═════╝"
	grid_text += "[/color][/center]"
	grid_label.append_text(grid_text)
	grid_wrap.add_child(grid_label)

	# Legend
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.scroll_active = false
	legend.add_theme_font_size_override("normal_font_size", 13)
	legend.custom_minimum_size = Vector2(0, 88)
	var legend_text := ""
	legend_text += "[color=#9ACD32]Movement (1-4, 6-9):[/color] step in 8 directions. Diagonals ([color=#FFD700]1[/color]/[color=#FFD700]3[/color]/[color=#FFD700]7[/color]/[color=#FFD700]9[/color]) cross two axes at once — faster for getting around terrain.\n"
	legend_text += "[color=#FF6B6B]Hunt (5):[/color] search your current tile + adjacent tiles for monsters and other interactions.\n"
	legend_text += "[color=#888888]Arrow keys also work for cardinal directions (no diagonals).[/color]"
	legend.append_text(legend_text)
	vbox.add_child(legend)

	# Footer: toggle checkbox + Got it button
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)

	_toggle_check = CheckBox.new()
	_toggle_check.text = "Don't show this for future characters"
	_toggle_check.focus_mode = Control.FOCUS_NONE
	_toggle_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle_check.toggled.connect(_on_toggle_changed)
	footer.add_child(_toggle_check)

	var ok_btn := Button.new()
	ok_btn.text = "Got it"
	ok_btn.focus_mode = Control.FOCUS_NONE
	ok_btn.custom_minimum_size = Vector2(110, 36)
	ok_btn.pressed.connect(_on_ok_pressed)
	footer.add_child(ok_btn)


func _on_toggle_changed(checked: bool) -> void:
	# Checkbox is "Don't show again" → emit the inverse for the
	# "show for future characters" preference.
	persistent_toggled.emit(not checked)


func _on_ok_pressed() -> void:
	dismissed.emit()
