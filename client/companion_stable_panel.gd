extends Control
class_name CompanionStablePanel

# Audit #4 Slice 1A (v0.9.485) — visual UI for the Companion Stable at T5+
# NPC posts. Two-column layout: collected companions (your roster) on the
# left, kennel companions (Sanctuary) on the right. Click a row to deposit
# or withdraw. Help button in the header opens HelpPanel for "companion_stable".
#
# Server messages handled:
#   companion_stable_open  →  show_with_payload(payload)
# Signals emitted (client.gd wires to server messages):
#   deposit_requested(collected_index)  →  companion_stable_deposit
#   withdraw_requested(kennel_index)    →  companion_stable_withdraw
#   close_requested                     →  panel closes locally

signal deposit_requested(collected_index: int)
signal withdraw_requested(kennel_index: int)
signal close_requested

const HelpPanelScript = preload("res://client/help_panel.gd")

var _kennel: Array = []
var _collected: Array = []
var _kennel_capacity: int = 30

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _summary_label: RichTextLabel
var _collected_list: VBoxContainer
var _kennel_list: VBoxContainer
var _collected_empty: Label
var _kennel_empty: Label
var _close_btn: Button
var _help_panel: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_layout()
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	# Don't swallow input when the help overlay is on top of us.
	if _help_panel != null and _help_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()


func show_with_payload(payload: Dictionary) -> void:
	_kennel = payload.get("kennel", [])
	_collected = payload.get("collected", [])
	_kennel_capacity = int(payload.get("kennel_capacity", 30))
	_refresh()
	visible = true


func _refresh() -> void:
	if _summary_label:
		_summary_label.clear()
		_summary_label.append_text(
			"[color=#A335EE]Kennel:[/color] %d / %d   "
			% [_kennel.size(), _kennel_capacity]
			+ "[color=#87CEEB]Collected:[/color] %d" % _collected.size()
		)
	_populate_list(_collected_list, _collected, true, _collected_empty,
		"[color=#808080]No collected companions. Catch one in the world to start.[/color]")
	_populate_list(_kennel_list, _kennel, false, _kennel_empty,
		"[color=#808080]Sanctuary kennel empty.[/color]")


func _populate_list(container: VBoxContainer, items: Array, is_collected: bool, empty_label: Label, empty_text: String) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()
	if items.is_empty():
		if empty_label:
			empty_label.text = ""
			empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.scroll_active = false
		lbl.append_text(empty_text)
		container.add_child(lbl)
		return
	for i in range(items.size()):
		var c = items[i]
		container.add_child(_build_row(c, is_collected))


func _build_row(c: Dictionary, is_collected: bool) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var rarity_color = _variant_color_for(c)
	sb.bg_color = Color(0.13, 0.13, 0.17, 0.95)
	sb.border_color = rarity_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.custom_minimum_size = Vector2(280, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hybrid_marker := ""
	var partner = str(c.get("hybrid_partner_type", ""))
	if partner != "":
		hybrid_marker = "  [color=#FF80FF][HYBRID×%s][/color]" % partner
	var active_marker := ""
	if is_collected and bool(c.get("is_active", false)):
		active_marker = "  [color=#FFD700][ACTIVE][/color]"
	var variant_str = str(c.get("variant", "Normal"))
	var variant_bbcode := ""
	if variant_str != "" and variant_str != "Normal":
		variant_bbcode = "[color=%s]%s[/color] " % [rarity_color.to_html(false), variant_str]
	info.append_text(
		"[b]%s[/b]%s%s\n[color=#888888]%s T%d.%d  Lv %d[/color]" % [
			c.get("name", "Unknown"),
			hybrid_marker,
			active_marker,
			variant_bbcode + str(c.get("monster_type", "")),
			int(c.get("tier", 1)),
			int(c.get("sub_tier", 1)),
			int(c.get("level", 1)),
		]
	)
	hb.add_child(info)

	var action_btn := Button.new()
	action_btn.focus_mode = Control.FOCUS_NONE
	action_btn.custom_minimum_size = Vector2(110, 28)
	var idx = int(c.get("index", -1))
	if is_collected:
		action_btn.text = "→ Deposit"
		action_btn.tooltip_text = "Send to Sanctuary kennel"
		var disabled := false
		# Block deposit of registered-checkout active companion server-side too,
		# but disable here for clarity.
		if bool(c.get("using_registered", false)):
			disabled = true
			action_btn.tooltip_text = "Unregister at the Sanctuary first."
		if _kennel.size() >= _kennel_capacity:
			disabled = true
			action_btn.tooltip_text = "Kennel is full — upgrade at the Sanctuary."
		action_btn.disabled = disabled
		action_btn.pressed.connect(func(): emit_signal("deposit_requested", idx))
	else:
		action_btn.text = "← Withdraw"
		action_btn.tooltip_text = "Bring into your roster"
		action_btn.pressed.connect(func(): emit_signal("withdraw_requested", idx))
	hb.add_child(action_btn)

	return row


func _variant_color_for(c: Dictionary) -> Color:
	var hex = str(c.get("variant_color", "#FFFFFF"))
	if hex == "" or not hex.begins_with("#") or hex.length() < 7:
		return Color(1, 1, 1)
	return Color.html(hex)


func _build_layout() -> void:
	# Backdrop dim.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(940, 580)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.10, 0.08, 0.16, 0.98)
	panel_sb.border_color = Color(1.0, 0.5, 1.0)  # magenta to match Companion Stable tile color
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 18
	panel_sb.content_margin_right = 18
	panel_sb.content_margin_top = 14
	panel_sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(_root_panel)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 10)
	_root_panel.add_child(root_vb)

	# Header row: title + help button + close button.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root_vb.add_child(header)

	_title_label = RichTextLabel.new()
	_title_label.bbcode_enabled = true
	_title_label.fit_content = true
	_title_label.scroll_active = false
	_title_label.add_theme_font_size_override("normal_font_size", 18)
	_title_label.custom_minimum_size = Vector2(0, 26)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.append_text("[color=#FF80FF]✦ Companion Stable ✦[/color]")
	header.add_child(_title_label)

	# Help button — re-openable; uses the new reusable HelpPanel.
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn := HelpPanelScript.make_help_button("companion_stable", _help_panel)
	header.add_child(help_btn)

	_close_btn = Button.new()
	_close_btn.text = "Close (Esc)"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.pressed.connect(_on_close)
	header.add_child(_close_btn)

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.scroll_active = false
	_summary_label.add_theme_font_size_override("normal_font_size", 13)
	root_vb.add_child(_summary_label)

	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.scroll_active = false
	hint.add_theme_font_size_override("normal_font_size", 12)
	hint.append_text("[color=#888888]Deposit a collected companion to send it to the kennel — or withdraw a kennel companion into your roster. Fusion ingredients live in the kennel.[/color]")
	root_vb.add_child(hint)

	# Two-column body.
	var body_hb := HBoxContainer.new()
	body_hb.add_theme_constant_override("separation", 14)
	body_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_child(body_hb)

	body_hb.add_child(_build_column("[color=#87CEEB]Your Roster (Collected)[/color]", true))
	body_hb.add_child(_build_column("[color=#A335EE]Sanctuary Kennel[/color]", false))


func _build_column(title_bb: String, is_collected: bool) -> Control:
	var col_panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	sb.border_color = Color(0.3, 0.3, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	col_panel.add_theme_stylebox_override("panel", sb)
	col_panel.custom_minimum_size = Vector2(440, 480)
	col_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col_vb := VBoxContainer.new()
	col_vb.add_theme_constant_override("separation", 6)
	col_panel.add_child(col_vb)

	var header := RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.add_theme_font_size_override("normal_font_size", 14)
	header.append_text(title_bb)
	col_vb.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_vb.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var empty_label := Label.new()
	empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	if is_collected:
		_collected_list = list
		_collected_empty = empty_label
	else:
		_kennel_list = list
		_kennel_empty = empty_label

	return col_panel


func _on_close() -> void:
	visible = false
	emit_signal("close_requested")
