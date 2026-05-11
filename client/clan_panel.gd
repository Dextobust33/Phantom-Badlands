extends Control
class_name ClanPanel

# Audit #14 Slice 1 — visual Clan panel (per "no chat-command-first" rule).
# Two states:
#   no clan  → Create form (Name + Tag fields, [Create] button)
#   in clan  → Roster view (name, tag, member count, list, [Leave] button)
# Server is authoritative via `clan_info_data` pushes.

signal close_requested
signal create_requested(name: String, tag: String)
signal leave_requested

var _root_panel: PanelContainer
var _vbox: VBoxContainer
var _body_container: VBoxContainer
var _status_label: RichTextLabel

# Last snapshot pushed from server.
var _has_clan: bool = false
var _data: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(data: Dictionary) -> void:
	refresh(data)
	visible = true


func close() -> void:
	visible = false
	_set_status("")


func refresh(data: Dictionary) -> void:
	_data = data.duplicate(true) if data is Dictionary else {}
	_has_clan = bool(_data.get("has_clan", false))
	_render_body()


func show_action_result(success: bool, message: String) -> void:
	"""Called by client.gd when a clan_action_result message arrives.
	Renders inline feedback in the status label."""
	if success:
		_set_status("[color=#88FF88]%s[/color]" % message)
	else:
		_set_status("[color=#FF6644]%s[/color]" % message)


func _set_status(bbcode: String) -> void:
	if _status_label == null:
		return
	_status_label.clear()
	if bbcode != "":
		_status_label.append_text(bbcode)


func _build_layout() -> void:
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
	_root_panel.custom_minimum_size = Vector2(540, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	sb.border_color = Color(0.55, 0.45, 0.85, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_top = 14
	sb.content_margin_right = 16
	sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 8)
	_root_panel.add_child(_vbox)

	# Title bar
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 8)
	_vbox.add_child(title_hbox)

	var title_label := Label.new()
	title_label.text = "Clan"
	title_label.add_theme_color_override("font_color", Color(0.83, 0.71, 1.0))
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): close_requested.emit())
	title_hbox.add_child(close_btn)

	# Status / feedback line (set by show_action_result)
	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.add_theme_font_size_override("normal_font_size", 12)
	_status_label.custom_minimum_size = Vector2(0, 20)
	_vbox.add_child(_status_label)

	# Body container — refilled when state flips
	_body_container = VBoxContainer.new()
	_body_container.add_theme_constant_override("separation", 6)
	_vbox.add_child(_body_container)


func _render_body() -> void:
	for child in _body_container.get_children():
		child.queue_free()

	if _has_clan:
		_render_in_clan_view()
	else:
		_render_create_form()


func _render_create_form() -> void:
	"""No clan — show create form."""
	var intro := RichTextLabel.new()
	intro.bbcode_enabled = true
	intro.fit_content = true
	intro.scroll_active = false
	intro.add_theme_font_size_override("normal_font_size", 13)
	intro.custom_minimum_size = Vector2(0, 60)
	intro.text = "[color=#A0A0A0]Found a clan to band together with other players. Members can find each other on the player list; later slices add clan storage, posts, and shared progress.[/color]"
	_body_container.add_child(intro)

	# Name row
	var name_hbox := HBoxContainer.new()
	name_hbox.add_theme_constant_override("separation", 8)
	_body_container.add_child(name_hbox)

	var name_label := Label.new()
	name_label.text = "Name"
	name_label.custom_minimum_size = Vector2(60, 0)
	name_hbox.add_child(name_label)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "3-24 chars, letters / numbers / spaces"
	name_edit.max_length = 24
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_hbox.add_child(name_edit)

	# Tag row
	var tag_hbox := HBoxContainer.new()
	tag_hbox.add_theme_constant_override("separation", 8)
	_body_container.add_child(tag_hbox)

	var tag_label := Label.new()
	tag_label.text = "Tag"
	tag_label.custom_minimum_size = Vector2(60, 0)
	tag_hbox.add_child(tag_label)

	var tag_edit := LineEdit.new()
	tag_edit.placeholder_text = "2-5 chars, letters / numbers only"
	tag_edit.max_length = 5
	tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_hbox.add_child(tag_edit)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_body_container.add_child(spacer)

	# Submit
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 8)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	_body_container.add_child(btn_hbox)

	var create_btn := Button.new()
	create_btn.text = "Create Clan"
	create_btn.focus_mode = Control.FOCUS_NONE
	create_btn.custom_minimum_size = Vector2(140, 36)
	var submit = func():
		var nm: String = name_edit.text.strip_edges()
		var tg: String = tag_edit.text.strip_edges()
		if nm.length() < 3 or nm.length() > 24:
			_set_status("[color=#FF6644]Name must be 3-24 characters.[/color]")
			return
		if tg.length() < 2 or tg.length() > 5:
			_set_status("[color=#FF6644]Tag must be 2-5 characters.[/color]")
			return
		create_requested.emit(nm, tg)
	create_btn.pressed.connect(submit)
	# Enter in either field submits.
	name_edit.text_submitted.connect(func(_t): submit.call())
	tag_edit.text_submitted.connect(func(_t): submit.call())
	btn_hbox.add_child(create_btn)


func _render_in_clan_view() -> void:
	"""Already in a clan — show roster + leave."""
	var clan_name: String = String(_data.get("name", ""))
	var clan_tag: String = String(_data.get("tag", ""))
	var member_count: int = int(_data.get("member_count", 0))
	var max_members: int = int(_data.get("max_members", 30))
	var is_leader: bool = bool(_data.get("is_leader", false))
	var members: Array = _data.get("members", [])

	# Header
	var header := RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.add_theme_font_size_override("normal_font_size", 15)
	header.custom_minimum_size = Vector2(0, 24)
	header.text = "[color=#A335EE][b]%s[/b][/color]  [color=#FFD700][%s][/color]   [color=#888888]%d/%d members[/color]" % [clan_name, clan_tag, member_count, max_members]
	_body_container.add_child(header)

	if is_leader:
		var leader_note := RichTextLabel.new()
		leader_note.bbcode_enabled = true
		leader_note.fit_content = true
		leader_note.scroll_active = false
		leader_note.add_theme_font_size_override("normal_font_size", 11)
		leader_note.custom_minimum_size = Vector2(0, 18)
		leader_note.text = "[color=#FFD700]You are the leader.[/color] [color=#888888]Leaving disbands the clan.[/color]"
		_body_container.add_child(leader_note)

	# Roster panel
	var roster_panel := PanelContainer.new()
	var rp_sb := StyleBoxFlat.new()
	rp_sb.bg_color = Color(0.08, 0.07, 0.12, 0.85)
	rp_sb.border_color = Color(0.35, 0.30, 0.50, 1)
	rp_sb.set_border_width_all(1)
	rp_sb.set_corner_radius_all(4)
	rp_sb.content_margin_left = 10
	rp_sb.content_margin_top = 6
	rp_sb.content_margin_right = 10
	rp_sb.content_margin_bottom = 6
	roster_panel.add_theme_stylebox_override("panel", rp_sb)
	_body_container.add_child(roster_panel)

	var roster_vbox := VBoxContainer.new()
	roster_vbox.add_theme_constant_override("separation", 2)
	roster_panel.add_child(roster_vbox)

	if members.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(no members)"
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		roster_vbox.add_child(empty_label)
	else:
		for member_var in members:
			if not (member_var is Dictionary):
				continue
			var member: Dictionary = member_var
			var username: String = String(member.get("username", "(unknown)"))
			var leader_flag: bool = bool(member.get("is_leader", false))
			var row := RichTextLabel.new()
			row.bbcode_enabled = true
			row.fit_content = true
			row.scroll_active = false
			row.add_theme_font_size_override("normal_font_size", 13)
			row.custom_minimum_size = Vector2(0, 18)
			if leader_flag:
				row.text = "[color=#FFD700]★ %s[/color] [color=#888888](leader)[/color]" % username
			else:
				row.text = "[color=#DDDDDD]%s[/color]" % username
			roster_vbox.add_child(row)

	# Spacer + leave button
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_body_container.add_child(spacer)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 8)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	_body_container.add_child(btn_hbox)

	var leave_btn := Button.new()
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.custom_minimum_size = Vector2(140, 36)
	leave_btn.text = "Disband Clan" if is_leader else "Leave Clan"
	leave_btn.pressed.connect(func(): leave_requested.emit())
	btn_hbox.add_child(leave_btn)
