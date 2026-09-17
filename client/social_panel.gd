extends Control
class_name SocialPanel

## Friends, requests and blocked players — the surface the friend system never had.
##
## Owner 2026-09-17: *"Anything that remains needs a way to access it via the UI."*
##
## ⛑ THE WHOLE FRIEND SYSTEM WAS COMMAND-ONLY. There is no other `*_panel.gd` for it: `/friends`
## listed them, `/freq` showed pending requests, `/blocklist` showed the blocked, and
## `/friend accept <name>` was the ONLY way to answer a request. The player context menu added
## *Add Friend* and *Block*, which made a player reachable — but a request you cannot see is a
## request you cannot accept, so retiring those commands would have removed the feature.
##
## Three tabs rather than three panels, because they are one subject: people, and what you have
## decided about them. The server already sends everything this needs (`friend_list_result`,
## `friend_requests_result`, `block_list_result`); nothing new was added to the protocol.
##
## Pattern follows `stones_panel.gd` / `admin_panel.gd`: dim backdrop, centered PanelContainer,
## rows of Buttons. Buttons rather than clickable BBCode for the reason the whole audit exists —
## only a Button takes focus, and this has to survive a D-pad.

signal close_requested
## Emitted for every action; `client.gd` forwards each to the function the chat command calls, so
## this panel sends no protocol message of its own. Same rule as the player context menu.
signal action_requested(action: String, username: String)

const TABS: Array = ["Friends", "Requests", "Blocked"]

var _tab: int = 0
var _friends: Array = []
var _incoming: Array = []
var _outgoing: Array = []
var _blocked: Array = []

var _root_panel: PanelContainer = null
var _tab_row: HBoxContainer = null
var _list_box: VBoxContainer = null
var _status: RichTextLabel = null


func _ready() -> void:
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open() -> void:
	visible = true
	_rebuild()
	# Ask for all three at once. They are small, and a tab that shows yesterday's list because
	# you have not visited it yet is worse than three cheap requests.
	action_requested.emit("refresh", "")


func close() -> void:
	visible = false
	close_requested.emit()


func set_friends(entries: Array) -> void:
	_friends = entries
	if visible:
		_rebuild()


func set_requests(incoming: Array, outgoing: Array) -> void:
	_incoming = incoming
	_outgoing = outgoing
	if visible:
		_rebuild()


func set_blocked(entries: Array) -> void:
	_blocked = entries
	if visible:
		_rebuild()


func pending_request_count() -> int:
	"""How many people are waiting on an answer — for a badge on the way in."""
	return _incoming.size()


func _rebuild() -> void:
	if _list_box == null:
		return
	for c in _list_box.get_children():
		c.queue_free()
	for i in range(TABS.size()):
		var b := _tab_row.get_child(i) as Button
		if b != null:
			b.disabled = (i == _tab)
			# The count rides on the tab, so an unanswered request is visible without opening it.
			var n: int = _incoming.size() if i == 1 else 0
			b.text = "%s (%d)" % [String(TABS[i]), n] if n > 0 else String(TABS[i])
	match _tab:
		0: _build_friends()
		1: _build_requests()
		2: _build_blocked()


func _empty(text: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.append_text("[color=#808080]%s[/color]" % text)
	_list_box.add_child(l)


func _row(label_bb: String, actions: Array) -> void:
	"""One person, with what you can do about them. `actions` is [[text, action_id, username], ...]"""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(300, 24)
	l.append_text(label_bb)
	row.add_child(l)
	for a in actions:
		var b := Button.new()
		b.text = String(a[0])
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(92, 26)
		var act := String(a[1])
		var who := String(a[2])
		b.pressed.connect(func(): action_requested.emit(act, who))
		row.add_child(b)
	_list_box.add_child(row)


func _build_friends() -> void:
	if _friends.is_empty():
		_empty("Nobody yet. Right-click a player in the online list, or on the map, and choose Add Friend.")
		return
	for e in _friends:
		var name_s := String(e.get("username", "?"))
		var line := ""
		if bool(e.get("online", false)):
			# What they are doing matters more than that they exist, so it leads.
			line = "[color=#7FD8A0]●[/color] [b]%s[/b]  [color=#A0A0A0]%s, Lv %d %s%s[/color]" % [
				name_s, String(e.get("character_name", "?")), int(e.get("level", 1)),
				String(e.get("class", "?")),
				"  [color=#808080](afk)[/color]" if bool(e.get("afk", false)) else ""]
		else:
			line = "[color=#5A5A5A]○[/color] [color=#909090]%s — offline[/color]" % name_s
		_row(line, [["Whisper", "whisper", name_s], ["Remove", "friend_remove", name_s]])


func _build_requests() -> void:
	if _incoming.is_empty() and _outgoing.is_empty():
		_empty("No requests waiting.")
		return
	if not _incoming.is_empty():
		_empty("[b]They asked you[/b]")
		for e in _incoming:
			var n := String(e.get("username", "?"))
			# ⚑ THE ONE THING THAT HAD NO UI AT ALL. `/friend accept <name>` was the only way to
			# answer, and you could only learn a request existed by typing `/freq`.
			_row("[b]%s[/b]" % n,
				[["Accept", "friend_accept", n], ["Decline", "friend_reject", n]])
	if not _outgoing.is_empty():
		_empty("[b]You asked them[/b]")
		for e in _outgoing:
			var n := String(e.get("username", "?"))
			_row("[color=#A0A0A0]%s — waiting[/color]" % n, [["Cancel", "friend_cancel", n]])


func _build_blocked() -> void:
	if _blocked.is_empty():
		_empty("Nobody blocked.")
		return
	for e in _blocked:
		var n := String(e.get("username", "?"))
		_row("[color=#C08080]%s[/color]" % n, [["Unblock", "unblock", n]])


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
	_root_panel.custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.98)
	sb.border_color = Color(0.55, 0.78, 0.55, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_root_panel.add_child(vbox)

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.add_theme_font_size_override("normal_font_size", 18)
	title.append_text("[b]People[/b]")
	vbox.add_child(title)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_tab_row)
	for i in range(TABS.size()):
		var tb := Button.new()
		tb.text = String(TABS[i])
		tb.focus_mode = Control.FOCUS_ALL
		tb.custom_minimum_size = Vector2(120, 28)
		var idx := i
		tb.pressed.connect(func():
			_tab = idx
			_rebuild())
		_tab_row.add_child(tb)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(576, 300)
	vbox.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	vbox.add_child(_status)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	var close_btn := Button.new()
	close_btn.text = "Close  (Esc)"
	close_btn.custom_minimum_size = Vector2(200, 32)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(close)
	btn_row.add_child(close_btn)


func show_status(text: String) -> void:
	if _status:
		_status.clear()
		_status.append_text(text)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
