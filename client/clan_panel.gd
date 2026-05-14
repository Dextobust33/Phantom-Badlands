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
# Audit #14 Slice 2 — invitation flow.
signal invite_requested(username: String)
signal accept_requested(clan_id: String)
signal decline_requested(clan_id: String)
# Audit #14 Slice 4 — rank actions. target_account_id matches the value the
# server sends in the members[] payload so the round-trip is trivial.
signal promote_requested(target_account_id: String)
signal demote_requested(target_account_id: String)
signal kick_requested(target_account_id: String)

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


func _render_invitations_section() -> void:
	"""Audit #14 Slice 2 — render pending clan invitations. Skipped when there
	are none. Each invite is a card with inviter + clan + Accept / Decline."""
	var invitations: Array = _data.get("invitations", [])
	if invitations.is_empty():
		return

	var header := RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.add_theme_font_size_override("normal_font_size", 14)
	header.custom_minimum_size = Vector2(0, 22)
	header.text = "[color=#FFD700][b]Pending Invitations (%d)[/b][/color]" % invitations.size()
	_body_container.add_child(header)

	for invite_var in invitations:
		if not (invite_var is Dictionary):
			continue
		var invite: Dictionary = invite_var
		var clan_id_v: String = String(invite.get("clan_id", ""))
		var clan_name: String = String(invite.get("clan_name", "(unknown)"))
		var clan_tag: String = String(invite.get("clan_tag", ""))
		var inviter: String = String(invite.get("inviter_username", "(unknown)"))

		var row := PanelContainer.new()
		var row_sb := StyleBoxFlat.new()
		row_sb.bg_color = Color(0.10, 0.08, 0.14, 0.90)
		row_sb.border_color = Color(0.55, 0.45, 0.85, 1)
		row_sb.set_border_width_all(1)
		row_sb.set_corner_radius_all(4)
		row_sb.content_margin_left = 10
		row_sb.content_margin_top = 6
		row_sb.content_margin_right = 10
		row_sb.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", row_sb)
		_body_container.add_child(row)

		var row_hbox := HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 8)
		row.add_child(row_hbox)

		var text_vbox := VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_vbox.add_theme_constant_override("separation", 2)
		row_hbox.add_child(text_vbox)

		var name_label := RichTextLabel.new()
		name_label.bbcode_enabled = true
		name_label.fit_content = true
		name_label.scroll_active = false
		name_label.add_theme_font_size_override("normal_font_size", 13)
		name_label.custom_minimum_size = Vector2(0, 20)
		name_label.text = "[color=#A335EE][b]%s[/b][/color]  [color=#FFD700][%s][/color]" % [clan_name, clan_tag]
		text_vbox.add_child(name_label)

		var inviter_label := RichTextLabel.new()
		inviter_label.bbcode_enabled = true
		inviter_label.fit_content = true
		inviter_label.scroll_active = false
		inviter_label.add_theme_font_size_override("normal_font_size", 11)
		inviter_label.custom_minimum_size = Vector2(0, 16)
		inviter_label.text = "[color=#A0A0A0]Invited by [color=#FFFFFF]%s[/color][/color]" % inviter
		text_vbox.add_child(inviter_label)

		var accept_btn := Button.new()
		accept_btn.text = "Accept"
		accept_btn.focus_mode = Control.FOCUS_NONE
		accept_btn.custom_minimum_size = Vector2(90, 32)
		var clan_id_captured = clan_id_v
		accept_btn.pressed.connect(func(): accept_requested.emit(clan_id_captured))
		row_hbox.add_child(accept_btn)

		var decline_btn := Button.new()
		decline_btn.text = "Decline"
		decline_btn.focus_mode = Control.FOCUS_NONE
		decline_btn.custom_minimum_size = Vector2(90, 32)
		decline_btn.pressed.connect(func(): decline_requested.emit(clan_id_captured))
		row_hbox.add_child(decline_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_body_container.add_child(spacer)


func _render_create_form() -> void:
	"""No clan — show invitations (if any) + create form."""
	# Render pending invitations first so they're impossible to miss.
	_render_invitations_section()

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
	# Audit #14 Slice 4 — viewer's own rank. Officers see Invite + Kick (for
	# regular members only). Leaders see everything.
	var is_officer: bool = bool(_data.get("is_officer", false))
	var can_invite: bool = is_leader or is_officer
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
	elif is_officer:
		var officer_note := RichTextLabel.new()
		officer_note.bbcode_enabled = true
		officer_note.fit_content = true
		officer_note.scroll_active = false
		officer_note.add_theme_font_size_override("normal_font_size", 11)
		officer_note.custom_minimum_size = Vector2(0, 18)
		officer_note.text = "[color=#66DDFF]You are an officer.[/color] [color=#888888]You can invite + kick regular members.[/color]"
		_body_container.add_child(officer_note)

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
	roster_vbox.add_theme_constant_override("separation", 3)
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
			roster_vbox.add_child(_build_member_row(member, is_leader, is_officer))

	# Audit #14 Slice 2 + 4 — Invite input. Leader or officer can send invites.
	if can_invite and member_count < max_members:
		var invite_spacer := Control.new()
		invite_spacer.custom_minimum_size = Vector2(0, 4)
		_body_container.add_child(invite_spacer)

		var invite_label := Label.new()
		invite_label.text = "Invite Player"
		invite_label.add_theme_color_override("font_color", Color(0.83, 0.71, 1.0))
		invite_label.add_theme_font_size_override("font_size", 13)
		_body_container.add_child(invite_label)

		var invite_hbox := HBoxContainer.new()
		invite_hbox.add_theme_constant_override("separation", 8)
		_body_container.add_child(invite_hbox)

		var invite_edit := LineEdit.new()
		invite_edit.placeholder_text = "Player username"
		invite_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		invite_hbox.add_child(invite_edit)

		var invite_btn := Button.new()
		invite_btn.text = "Invite"
		invite_btn.focus_mode = Control.FOCUS_NONE
		invite_btn.custom_minimum_size = Vector2(100, 32)
		var submit_invite = func():
			var uname: String = invite_edit.text.strip_edges()
			if uname == "":
				_set_status("[color=#FF6644]Enter a username.[/color]")
				return
			invite_requested.emit(uname)
			invite_edit.text = ""
		invite_btn.pressed.connect(submit_invite)
		invite_edit.text_submitted.connect(func(_t): submit_invite.call())
		invite_hbox.add_child(invite_btn)
	elif can_invite and member_count >= max_members:
		var full_note := RichTextLabel.new()
		full_note.bbcode_enabled = true
		full_note.fit_content = true
		full_note.scroll_active = false
		full_note.add_theme_font_size_override("normal_font_size", 11)
		full_note.custom_minimum_size = Vector2(0, 18)
		full_note.text = "[color=#FF8800]Clan is full — cannot send new invitations.[/color]"
		_body_container.add_child(full_note)

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


func _build_member_row(member: Dictionary, viewer_is_leader: bool, viewer_is_officer: bool) -> Control:
	"""Audit #14 Slice 4 — one roster row with a rank badge and the rank-action
	buttons the viewer is allowed to use against this member. Buttons hidden on
	the viewer's own row to avoid self-actions (leave handles self-removal)."""
	var username: String = String(member.get("username", "(unknown)"))
	var target_account_id: String = String(member.get("account_id", ""))
	var leader_flag: bool = bool(member.get("is_leader", false))
	var officer_flag: bool = bool(member.get("is_officer", false))
	var rank: String = String(member.get("rank", "member"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 28)

	# Rank badge — fixed width so usernames align across rows.
	var badge := RichTextLabel.new()
	badge.bbcode_enabled = true
	badge.fit_content = true
	badge.scroll_active = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("normal_font_size", 11)
	badge.custom_minimum_size = Vector2(86, 22)
	var badge_color: String
	var badge_text: String
	match rank:
		"leader":
			badge_color = "#FFD700"
			badge_text = "LEADER"
		"officer":
			badge_color = "#66DDFF"
			badge_text = "OFFICER"
		_:
			badge_color = "#888888"
			badge_text = "MEMBER"
	badge.text = "[color=%s][b]%s[/b][/color]" % [badge_color, badge_text]
	row.add_child(badge)

	# Username (expands to fill remaining space).
	var name_label := RichTextLabel.new()
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("normal_font_size", 13)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(0, 22)
	if leader_flag:
		name_label.text = "[color=#FFD700]★ %s[/color]" % username
	else:
		name_label.text = "[color=#DDDDDD]%s[/color]" % username
	row.add_child(name_label)

	# Rank-action buttons.
	var viewer_account_id: String = String(_data.get("account_id", ""))
	var is_self: bool = viewer_account_id != "" and viewer_account_id == target_account_id
	if not is_self and target_account_id != "":
		# Leader can promote / demote / kick anyone (not self).
		if viewer_is_leader:
			if not leader_flag and not officer_flag:
				row.add_child(_make_rank_button("Promote", "#A335EE", target_account_id, promote_requested))
			elif officer_flag:
				row.add_child(_make_rank_button("Demote", "#888888", target_account_id, demote_requested))
			if not leader_flag:
				row.add_child(_make_rank_button("Kick", "#FF6644", target_account_id, kick_requested))
		# Officer can only kick regular members (not leader, not other officers).
		elif viewer_is_officer and not leader_flag and not officer_flag:
			row.add_child(_make_rank_button("Kick", "#FF6644", target_account_id, kick_requested))

	return row


func _make_rank_button(label: String, color_hex: String, target_account_id: String, sig: Signal) -> Button:
	"""Helper: action button that emits the given rank-action signal with the
	target's account_id when pressed. Color tint matches the action's intent."""
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(72, 26)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color.html(color_hex))
	var sig_ref := sig
	var target_captured := target_account_id
	btn.pressed.connect(func(): sig_ref.emit(target_captured))
	return btn
