extends Control
class_name BountyBoardPanel

# v0.9.568 — Bounty Board panel (Slice 3 of the v0.9.568 polish batch).
# Lifts Audit #14 Slice E's bounty system out of chat-only V1 into a real
# UI surface. Renders the bounty_list_result payload (still server-sourced,
# same payload shape) as a table, with a Post Bounty form inline.
#
# Open paths:
#   1. /bounty list — chat command auto-opens the panel
#   2. /bountyboard / /bb — explicit shortcut
# Close: Esc / Enter / X button. Backdrop is non-dismissive (so accidental
# clicks outside don't lose your typed form input).
#
# Per-row actions:
#   • View Postings → fires bounty_on; result feeds the same panel's detail strip
#   • Cancel Mine → fires bounty_cancel; relies on server's text confirmation
#
# The chat `/bounty list / on / cancel` commands stay as legacy fallbacks.

signal post_bounty_requested(target_name: String, amount: int)
signal view_postings_requested(target_name: String)
signal cancel_mine_requested(target_name: String)
signal list_refresh_requested
signal dismissed

const HelpPanelScript = preload("res://client/help_panel.gd")

var _root_panel: PanelContainer
var _vbox: VBoxContainer
var _valor_label: RichTextLabel
var _post_target_input: LineEdit
var _post_amount_input: LineEdit
var _post_status: RichTextLabel
var _list_label: RichTextLabel
var _detail_label: RichTextLabel
var _help_panel: Control = null

var _last_entries: Array = []
var _detail_target: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open_board(player_valor: int) -> void:
	_update_valor(player_valor)
	_post_status.clear()
	_post_target_input.text = ""
	_post_amount_input.text = ""
	_list_label.clear()
	_list_label.append_text("[color=#888888]Loading active bounties…[/color]")
	_detail_label.clear()
	_detail_target = ""
	visible = true
	list_refresh_requested.emit()
	_post_target_input.grab_focus()


func update_valor(player_valor: int) -> void:
	# Called when character_update arrives mid-panel; keeps the form accurate.
	if visible:
		_update_valor(player_valor)


func apply_list(entries: Array) -> void:
	"""Server pushed bounty_list_result. Render entries as a table."""
	_last_entries = entries.duplicate()
	_list_label.clear()
	if entries.is_empty():
		_list_label.append_text("[color=#808080]No active bounties on the board. Be the first to post one.[/color]")
		return
	_list_label.append_text("[color=#FFD700]── Active Bounties ──[/color]\n")
	var slot := 1
	for e in entries:
		if not (e is Dictionary):
			continue
		var target_name = String(e.get("target_name", "?"))
		var total = int(e.get("total_bounty", 0))
		var count = int(e.get("posting_count", 1))
		var online = bool(e.get("online", false))
		var online_tag = "" if online else " [color=#808080](offline)[/color]"
		var key_hint = ""
		if slot <= 9:
			key_hint = "[color=#888888][%d][/color] " % slot
		_list_label.append_text("%s[color=#FF8800]%s[/color]%s — [color=#FFD700]%d valor[/color] [color=#888888](%d postings)[/color] [url=view:%s]› view postings[/url]\n" % [key_hint, target_name, online_tag, total, count, target_name])
		slot += 1


func apply_postings(target_name: String, bounties: Array, total: int) -> void:
	"""Server pushed bounty_on_result. Show the detail strip for this target."""
	_detail_target = target_name
	_detail_label.clear()
	_detail_label.append_text("[color=#FFD700]── Postings on [color=#FF8800]%s[/color] — total [color=#FFD700]%d valor[/color] ──[/color]\n" % [target_name, total])
	if bounties.is_empty():
		_detail_label.append_text("[color=#808080]No postings.[/color]\n")
		return
	var any_mine := false
	for b in bounties:
		if not (b is Dictionary):
			continue
		var poster = String(b.get("poster_character_name", "?"))
		var amount = int(b.get("amount_valor", 0))
		_detail_label.append_text("  • [color=#9ACD32]%s[/color] — [color=#FFD700]%d valor[/color]\n" % [poster, amount])
		# Heuristic — we can't distinguish "mine" without an account match;
		# server validates on cancel so we render a single cancel-all link.
		any_mine = true
	if any_mine:
		_detail_label.append_text("[url=cancel:%s][color=#FF8888]› Cancel ALL my postings on this target (full refund)[/color][/url]\n" % target_name)


func note_post_result(success: bool, message: String) -> void:
	"""Called by client.gd after the server confirms (or rejects) a post.
	V1 server only returns text, so client.gd parses success heuristically."""
	_post_status.clear()
	if success:
		_post_status.append_text("[color=#88FF88]%s[/color]" % message)
		_post_target_input.text = ""
		_post_amount_input.text = ""
		list_refresh_requested.emit()
	else:
		_post_status.append_text("[color=#FF8888]%s[/color]" % message)


func _update_valor(v: int) -> void:
	_valor_label.clear()
	_valor_label.append_text("[color=#FFD700]Your valor: %d[/color]   [color=#888888]Bounties are paid out when the target is KO'd in an apex-zone PvP fight.[/color]" % v)


func _on_close() -> void:
	visible = false
	dismissed.emit()


func _on_post_submit() -> void:
	var target = _post_target_input.text.strip_edges()
	var amount_text = _post_amount_input.text.strip_edges()
	if target == "":
		note_post_result(false, "Enter the target's character name.")
		return
	if not amount_text.is_valid_int():
		note_post_result(false, "Amount must be a whole number.")
		return
	var amount = int(amount_text)
	if amount <= 0:
		note_post_result(false, "Amount must be positive.")
		return
	# Server enforces BOUNTY_MIN_AMOUNT (50); we don't duplicate the
	# threshold here so it stays a single source of truth.
	post_bounty_requested.emit(target, amount)
	_post_status.clear()
	_post_status.append_text("[color=#AAAAAA]Posting bounty…[/color]")


func _on_refresh_pressed() -> void:
	_list_label.clear()
	_list_label.append_text("[color=#888888]Refreshing…[/color]")
	list_refresh_requested.emit()


func _on_meta_clicked(meta: Variant) -> void:
	var s = String(meta)
	if s.begins_with("view:"):
		var target = s.substr(5)
		view_postings_requested.emit(target)
	elif s.begins_with("cancel:"):
		var target = s.substr(7)
		cancel_mine_requested.emit(target)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key = event.keycode
		if key == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()
		elif key >= KEY_1 and key <= KEY_9:
			# Quick-jump: pressing 1-9 fires "view postings" for that row.
			# Useful for keyboard players to drill into a target without mousing.
			var idx = int(key - KEY_1)
			if idx < _last_entries.size():
				var entry = _last_entries[idx]
				if entry is Dictionary:
					var tname = String(entry.get("target_name", ""))
					if tname != "":
						get_viewport().set_input_as_handled()
						view_postings_requested.emit(tname)


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.06, 0.04, 0.98)
	sb.border_color = Color(1.0, 0.65, 0.15, 1)  # Bounty gold
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 22
	sb.content_margin_top = 16
	sb.content_margin_right = 22
	sb.content_margin_bottom = 16
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 10)
	_root_panel.add_child(_vbox)

	# Header row — title left, Help + Close right
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(header_row)

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(0, 26)
	title.add_theme_font_size_override("normal_font_size", 18)
	# v0.9.636 — was 💰 (U+1F4B0 money bag), SMP range fonts tofu it.
	title.append_text("[color=#FFD700]$ Bounty Board[/color]")
	header_row.add_child(title)

	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("bounty_board", _help_panel)
	header_row.add_child(help_btn)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.tooltip_text = "Close (Esc)"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(32, 26)
	close_btn.pressed.connect(_on_close)
	header_row.add_child(close_btn)

	# Valor + tagline
	_valor_label = RichTextLabel.new()
	_valor_label.bbcode_enabled = true
	_valor_label.fit_content = true
	_valor_label.scroll_active = false
	_valor_label.custom_minimum_size = Vector2(0, 22)
	_valor_label.add_theme_font_size_override("normal_font_size", 13)
	_vbox.add_child(_valor_label)

	var sep1 = HSeparator.new()
	_vbox.add_child(sep1)

	# Post Bounty form
	var post_title := RichTextLabel.new()
	post_title.bbcode_enabled = true
	post_title.fit_content = true
	post_title.scroll_active = false
	post_title.custom_minimum_size = Vector2(0, 22)
	post_title.add_theme_font_size_override("normal_font_size", 14)
	post_title.append_text("[color=#FFD700]── Post a New Bounty ──[/color]")
	_vbox.add_child(post_title)

	var form_row := HBoxContainer.new()
	form_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(form_row)

	var target_label := Label.new()
	target_label.text = "Target:"
	target_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	form_row.add_child(target_label)

	_post_target_input = LineEdit.new()
	_post_target_input.placeholder_text = "character name"
	_post_target_input.custom_minimum_size = Vector2(180, 28)
	_post_target_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_row.add_child(_post_target_input)

	var amount_label := Label.new()
	amount_label.text = "Valor:"
	amount_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	form_row.add_child(amount_label)

	_post_amount_input = LineEdit.new()
	_post_amount_input.placeholder_text = "≥ 50"
	_post_amount_input.custom_minimum_size = Vector2(80, 28)
	form_row.add_child(_post_amount_input)

	var post_btn := Button.new()
	post_btn.text = "Post Bounty"
	post_btn.custom_minimum_size = Vector2(110, 28)
	post_btn.focus_mode = Control.FOCUS_NONE
	post_btn.pressed.connect(_on_post_submit)
	form_row.add_child(post_btn)

	_post_status = RichTextLabel.new()
	_post_status.bbcode_enabled = true
	_post_status.fit_content = true
	_post_status.scroll_active = false
	_post_status.custom_minimum_size = Vector2(0, 20)
	_post_status.add_theme_font_size_override("normal_font_size", 12)
	_vbox.add_child(_post_status)

	var sep2 = HSeparator.new()
	_vbox.add_child(sep2)

	# Active list
	var list_header := HBoxContainer.new()
	list_header.add_theme_constant_override("separation", 8)
	_vbox.add_child(list_header)

	var list_title := RichTextLabel.new()
	list_title.bbcode_enabled = true
	list_title.fit_content = true
	list_title.scroll_active = false
	list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_title.custom_minimum_size = Vector2(0, 20)
	list_title.add_theme_font_size_override("normal_font_size", 13)
	list_title.append_text("[color=#888888]Click [url=help]› view postings[/url] to drill into a target. Press 1-9 to drill by keyboard.[/color]")
	list_header.add_child(list_title)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.custom_minimum_size = Vector2(80, 22)
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(_on_refresh_pressed)
	list_header.add_child(refresh_btn)

	_list_label = RichTextLabel.new()
	_list_label.bbcode_enabled = true
	_list_label.fit_content = true
	_list_label.scroll_active = true
	_list_label.custom_minimum_size = Vector2(560, 180)
	_list_label.add_theme_font_size_override("normal_font_size", 13)
	_list_label.meta_clicked.connect(_on_meta_clicked)
	_vbox.add_child(_list_label)

	# Detail strip — only populated when a row is drilled into.
	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = true
	_detail_label.scroll_active = true
	_detail_label.custom_minimum_size = Vector2(560, 120)
	_detail_label.add_theme_font_size_override("normal_font_size", 13)
	_detail_label.meta_clicked.connect(_on_meta_clicked)
	_vbox.add_child(_detail_label)
