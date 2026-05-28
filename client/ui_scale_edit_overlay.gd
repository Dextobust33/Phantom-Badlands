extends Control
class_name UIScaleEditOverlay

# v0.9.646 — click-to-scale edit mode. Player enters via Settings → Resize UI
# Elements (or the bound hotkey). Overlay tints the screen, banner says "UI
# Scale Edit Mode — click any element to resize." Click → finds the registered
# group under cursor via UIScaleManager → shows a floating +/- popup anchored
# near the click. Esc or Done exits.
#
# Designed to be a single instance, hidden by default, attached high in the
# scene tree (z_index 250 — above panels but the click is processed by us
# first since we cover the viewport).

signal exited

const HIGHLIGHT_COLOR := Color(1.0, 0.86, 0.20, 0.35)
const HIGHLIGHT_BORDER := Color(1.0, 0.86, 0.20, 1.0)

var _manager: Node = null  # UIScaleManager — typed loosely to avoid cyclic load

# Persistent UI inside the overlay.
var _dim: ColorRect = null
var _banner: PanelContainer = null
var _highlight_rect: Panel = null  # outline around the currently-hovered group
var _popup: PanelContainer = null
var _popup_name_label: Label = null
var _popup_value_label: Label = null
var _popup_target_group: String = ""

# Track the hovered group so we can repaint the highlight as the player moves.
var _hovered_group: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 250
	process_mode = Node.PROCESS_MODE_ALWAYS  # work even if game paused
	_build_layout()
	visible = false


func attach(manager: Node) -> void:
	_manager = manager


func enter_edit_mode() -> void:
	"""Open the overlay. Caller should also dismiss any modal that's covering
	the elements the player wants to scale."""
	visible = true
	_hovered_group = ""
	_hide_popup()
	_hide_highlight()


func exit_edit_mode() -> void:
	visible = false
	_hide_popup()
	_hide_highlight()
	emit_signal("exited")


# === Layout ===

func _build_layout() -> void:
	# Dim tint — subtle so the underlying UI is still readable.
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.15)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	# Banner at the top center — explains the mode.
	_banner = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.14, 0.95)
	sb.border_color = Color(1.0, 0.86, 0.20, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_banner.add_theme_stylebox_override("panel", sb)
	_banner.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_banner)
	# Anchor banner to top-center.
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.offset_top = 14
	_banner.offset_left = -240
	_banner.offset_right = 240

	var banner_box := HBoxContainer.new()
	banner_box.add_theme_constant_override("separation", 14)
	_banner.add_child(banner_box)

	var banner_label := RichTextLabel.new()
	banner_label.bbcode_enabled = true
	banner_label.fit_content = true
	banner_label.scroll_active = false
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_label.add_theme_font_size_override("normal_font_size", 14)
	banner_label.custom_minimum_size = Vector2(330, 22)
	banner_label.text = "[center][color=#FFD700][b]UI Scale Edit Mode[/b][/color] — click any element to resize[/center]"
	banner_box.add_child(banner_label)

	var done_btn := Button.new()
	done_btn.text = "Done (Esc)"
	done_btn.focus_mode = Control.FOCUS_NONE
	done_btn.custom_minimum_size = Vector2(110, 30)
	done_btn.pressed.connect(exit_edit_mode)
	banner_box.add_child(done_btn)

	# Hover-highlight outline (just a border, transparent body). We move + resize
	# this whenever the mouse hovers over a registered Control.
	_highlight_rect = Panel.new()
	_highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := StyleBoxFlat.new()
	hb.bg_color = HIGHLIGHT_COLOR
	hb.border_color = HIGHLIGHT_BORDER
	hb.set_border_width_all(3)
	hb.set_corner_radius_all(4)
	_highlight_rect.add_theme_stylebox_override("panel", hb)
	_highlight_rect.visible = false
	add_child(_highlight_rect)

	# +/- popup. Hidden until the player clicks something.
	_popup = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.05, 0.10, 0.98)
	psb.border_color = Color(1.0, 0.86, 0.20, 1.0)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(6)
	psb.content_margin_left = 12
	psb.content_margin_right = 12
	psb.content_margin_top = 10
	psb.content_margin_bottom = 10
	_popup.add_theme_stylebox_override("panel", psb)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup.visible = false
	add_child(_popup)

	var popup_vbox := VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 6)
	_popup.add_child(popup_vbox)

	_popup_name_label = Label.new()
	_popup_name_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.20))
	_popup_name_label.add_theme_font_size_override("font_size", 14)
	_popup_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_vbox.add_child(_popup_name_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	popup_vbox.add_child(btn_row)

	var minus_btn := Button.new()
	minus_btn.text = "−"
	minus_btn.focus_mode = Control.FOCUS_NONE
	minus_btn.custom_minimum_size = Vector2(40, 32)
	minus_btn.add_theme_font_size_override("font_size", 18)
	minus_btn.pressed.connect(_on_minus_pressed)
	btn_row.add_child(minus_btn)

	_popup_value_label = Label.new()
	_popup_value_label.add_theme_font_size_override("font_size", 15)
	_popup_value_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_popup_value_label.custom_minimum_size = Vector2(80, 0)
	_popup_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn_row.add_child(_popup_value_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.focus_mode = Control.FOCUS_NONE
	plus_btn.custom_minimum_size = Vector2(40, 32)
	plus_btn.add_theme_font_size_override("font_size", 18)
	plus_btn.pressed.connect(_on_plus_pressed)
	btn_row.add_child(plus_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(80, 28)
	reset_btn.pressed.connect(_on_reset_pressed)
	popup_vbox.add_child(reset_btn)


# === Input ===

func _process(_delta: float) -> void:
	if not visible or _manager == null:
		return
	# Update hover highlight every frame so the player can see what they'd
	# click. Skip when the popup is open (player is interacting with controls).
	if _popup.visible:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var grp: String = _manager.find_group_at_position(mouse_pos)
	if grp != _hovered_group:
		_hovered_group = grp
		if grp == "":
			_hide_highlight()
		else:
			_show_highlight_for_group(grp)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Esc: close popup if open, otherwise exit edit mode.
			if _popup.visible:
				_hide_popup()
			else:
				exit_edit_mode()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	# If the popup is open and the click is INSIDE it, let the popup buttons
	# handle it. (Popup has mouse_filter STOP so it won't reach us.)
	if _popup.visible and _popup.get_global_rect().has_point(event.position):
		return
	# If the popup is open and the click is OUTSIDE it, dismiss the popup
	# (don't immediately try to open a new one — feels jumpy).
	if _popup.visible:
		_hide_popup()
		get_viewport().set_input_as_handled()
		return
	# Otherwise find what's under the mouse and open the popup for it.
	if _manager == null:
		return
	var grp: String = _manager.find_group_at_position(event.position)
	if grp == "":
		return
	_show_popup_for(grp, event.position)
	get_viewport().set_input_as_handled()


# === Highlight ===

func _show_highlight_for_group(group_id: String) -> void:
	if _manager == null:
		_hide_highlight()
		return
	# Find the largest registered Control in the group that's visible — that's
	# the one we outline. Multiple controls per group means we want the union
	# of their rects, but a single bounding rect is good enough for now.
	var info: Dictionary = _manager._groups.get(group_id, {})
	if info.is_empty():
		_hide_highlight()
		return
	var union_rect: Rect2 = Rect2()
	var seeded: bool = false
	for ctrl in info.get("ctrls", []):
		if not is_instance_valid(ctrl):
			continue
		if not ctrl.visible:
			continue
		if not ctrl.is_visible_in_tree():
			continue
		var r: Rect2 = ctrl.get_global_rect()
		if not seeded:
			union_rect = r
			seeded = true
		else:
			union_rect = union_rect.merge(r)
	if not seeded:
		_hide_highlight()
		return
	_highlight_rect.position = union_rect.position
	_highlight_rect.size = union_rect.size
	_highlight_rect.visible = true


func _hide_highlight() -> void:
	_highlight_rect.visible = false


# === Popup ===

func _show_popup_for(group_id: String, click_pos: Vector2) -> void:
	if _manager == null:
		return
	_popup_target_group = group_id
	var name: String = _manager.get_display_name(group_id)
	_popup_name_label.text = name
	_refresh_popup_value()
	_popup.visible = true
	# Force layout so size is correct.
	_popup.reset_size()
	# Position the popup near the click but kept on-screen.
	var vp_size: Vector2 = get_viewport_rect().size
	var ps: Vector2 = _popup.size
	var pos: Vector2 = click_pos + Vector2(12, 12)
	if pos.x + ps.x > vp_size.x - 8:
		pos.x = vp_size.x - ps.x - 8
	if pos.y + ps.y > vp_size.y - 8:
		pos.y = vp_size.y - ps.y - 8
	pos.x = max(8.0, pos.x)
	pos.y = max(8.0, pos.y)
	_popup.position = pos
	# Re-paint the highlight on the targeted group so the player keeps the
	# context while interacting with the popup.
	_show_highlight_for_group(group_id)


func _hide_popup() -> void:
	_popup.visible = false
	_popup_target_group = ""


func _refresh_popup_value() -> void:
	if _manager == null or _popup_target_group == "":
		return
	var s: float = _manager.get_scale(_popup_target_group)
	_popup_value_label.text = "%d%%" % int(round(s * 100.0))


func _on_minus_pressed() -> void:
	if _manager == null or _popup_target_group == "":
		return
	_manager.bump_scale(_popup_target_group, -0.1)
	_refresh_popup_value()
	# Re-paint highlight in case the size shrank.
	_show_highlight_for_group(_popup_target_group)


func _on_plus_pressed() -> void:
	if _manager == null or _popup_target_group == "":
		return
	_manager.bump_scale(_popup_target_group, 0.1)
	_refresh_popup_value()
	_show_highlight_for_group(_popup_target_group)


func _on_reset_pressed() -> void:
	if _manager == null or _popup_target_group == "":
		return
	_manager.reset_group(_popup_target_group)
	_refresh_popup_value()
	_show_highlight_for_group(_popup_target_group)
