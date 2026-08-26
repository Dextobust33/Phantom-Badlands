extends Control
class_name QuestBoardPanel

# P2 (2026-08-26) — Quest Board panel. Replaces the scrolling game_output text blob
# (where turn-ins and available quests shared one confusing number-key sequence) with a
# real card UI: three clearly-separated sections, each card carrying its OWN explicit
# button so it's never ambiguous whether you're accepting or turning in.
#
#   • Ready to Turn In  → green [✓ Turn In] button per card
#   • Available Quests  → [Accept] button per card (greyed at max active)
#   • Active Quests     → progress + [Abandon] button (hidden for the Pathfinder chain)
#
# The panel is a modal overlay (dim backdrop, MOUSE_FILTER_STOP) with an inner
# ScrollContainer so long boards scroll INSIDE the panel and never overflow the screen.
# client.gd gates movement/action-bar while it's visible (folded into any_popup_open).

signal accept_requested(quest_id: String)
signal turn_in_requested(quest_id: String)
signal abandon_requested(quest_id: String)
signal refresh_requested
signal dismissed

const HelpPanelScript = preload("res://client/help_panel.gd")

# Starter posts where the Pathfinder chain can be turned in from anywhere.
const STARTER_POSTS := ["haven", "crossroads", "south_gate", "east_market", "west_shrine"]

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _subtitle_label: RichTextLabel
var _content: VBoxContainer          # rebuilt each open_board()
var _help_panel: Control = null

var _tp_id: String = ""
var _active_count: int = 0
var _max_quests: int = 3


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open_board(message: Dictionary) -> void:
	"""Render the quest_list payload as cards. Called on every quest_list message
	(initial open + refreshes after accept/turn-in)."""
	_tp_id = String(message.get("trading_post_id", ""))
	_active_count = int(message.get("active_count", 0))
	_max_quests = int(message.get("max_quests", 3))
	var giver := String(message.get("quest_giver", "Quest Giver"))
	var tp_name := String(message.get("trading_post", "Trading Post"))
	var turn_ins: Array = message.get("quests_to_turn_in", [])
	var available: Array = message.get("available_quests", [])
	var active: Array = message.get("active_quests", [])

	_title_label.clear()
	_title_label.append_text("[color=#FFD700]✧ Quest Board — %s[/color]" % tp_name)
	_subtitle_label.clear()
	var full := _active_count >= _max_quests
	var slot_color := "#FF8866" if full else "#9ACD32"
	_subtitle_label.append_text("[color=#B0B0B0]%s[/color]   [color=%s]Active quests: %d / %d[/color]%s" % [
		giver, slot_color, _active_count, _max_quests,
		("   [color=#FF8866](full — turn in or abandon to free a slot)[/color]" if full else "")])

	# Rebuild content
	for c in _content.get_children():
		c.queue_free()

	# --- Section 1: Ready to Turn In ---
	if turn_ins.size() > 0:
		_add_section_header("✓ Ready to Turn In", "#3BE06B")
		for q in turn_ins:
			_add_turn_in_card(q)

	# --- Section 2: Available ---
	_add_section_header("Available Quests", "#FFD700")
	if available.size() == 0:
		_add_empty_line("No quests available here right now.")
	else:
		# Threat bounties first, then featured, then the rest.
		var sorted_avail := available.duplicate()
		sorted_avail.sort_custom(func(a, b):
			var at = bool(a.get("is_threat_relief", false))
			var bt = bool(b.get("is_threat_relief", false))
			if at != bt:
				return at
			return bool(a.get("is_featured", false)) and not bool(b.get("is_featured", false)))
		for q in sorted_avail:
			_add_available_card(q, full)

	# --- Section 3: Active ---
	if active.size() > 0:
		_add_section_header("Your Active Quests", "#4DD6E0")
		for q in active:
			_add_active_card(q)

	visible = true


# ---------- card builders ----------

func _add_section_header(text: String, color: String) -> void:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.custom_minimum_size = Vector2(0, 24)
	lbl.add_theme_font_size_override("normal_font_size", 15)
	lbl.append_text("[color=%s]── %s ──[/color]" % [color, text])
	_content.add_child(lbl)


func _add_empty_line(text: String) -> void:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.custom_minimum_size = Vector2(0, 20)
	lbl.add_theme_font_size_override("normal_font_size", 13)
	lbl.append_text("[color=#808080]%s[/color]" % text)
	_content.add_child(lbl)


func _make_card(border_color: Color) -> HBoxContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.11, 0.13, 0.9)
	sb.border_color = border_color
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	_content.add_child(card)
	return row


func _make_body(row: HBoxContainer) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	return body


func _body_line(body: VBoxContainer, bbcode: String, font_size: int = 14, min_h: int = 20) -> void:
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size = Vector2(0, min_h)
	lbl.add_theme_font_size_override("normal_font_size", font_size)
	lbl.append_text(bbcode)
	body.add_child(lbl)


func _add_turn_in_card(q: Dictionary) -> void:
	var row := _make_card(Color(0.23, 0.88, 0.42))
	var body := _make_body(row)
	_body_line(body, "[color=#3BE06B]✓ %s[/color]" % String(q.get("name", "Quest")), 15)
	_body_line(body, "[color=#9ACD32]Reward: %s[/color]" % _format_rewards(q.get("rewards", {})), 12, 18)
	var btn := Button.new()
	btn.text = "Turn In"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(96, 34)
	btn.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75))
	var qid := String(q.get("quest_id", q.get("id", "")))
	btn.pressed.connect(func(): turn_in_requested.emit(qid))
	var wrap := CenterContainer.new()
	wrap.add_child(btn)
	row.add_child(wrap)


func _add_available_card(q: Dictionary, board_full: bool) -> void:
	var is_threat := bool(q.get("is_threat_relief", false))
	var is_featured := bool(q.get("is_featured", false))
	var border := Color(0.85, 0.68, 0.15)
	if is_threat:
		border = Color(1.0, 0.53, 0.0)
	var row := _make_card(border)
	var body := _make_body(row)

	var tags := ""
	if is_threat:
		tags += " [color=%s]⚠ THREAT[/color]" % String(q.get("threat_color", "#FF8800"))
	if is_featured:
		tags += " [color=#FFD700]★ FEATURED[/color]"
	_body_line(body, "[color=#FFE066]%s[/color]%s" % [String(q.get("name", "Quest")), tags], 15)
	var desc := String(q.get("description", ""))
	if desc != "":
		_body_line(body, "[color=#B8B8B8]%s[/color]" % desc, 12, 18)
	var dir_hint := String(q.get("dungeon_direction", q.get("direction_hint", "")))
	var reward_line := "[color=#9ACD32]Rewards: %s[/color]" % _format_rewards(q.get("rewards", {}))
	if dir_hint != "":
		reward_line += "   [color=#7FB8D8]%s[/color]" % dir_hint
	_body_line(body, reward_line, 12, 18)

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(96, 34)
	var qid := String(q.get("id", ""))
	if board_full:
		btn.text = "Full"
		btn.disabled = true
		btn.tooltip_text = "You have the max active quests. Turn in or abandon one first."
	else:
		btn.text = "Accept"
		btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		btn.pressed.connect(func(): accept_requested.emit(qid))
	var wrap := CenterContainer.new()
	wrap.add_child(btn)
	row.add_child(wrap)


func _add_active_card(q: Dictionary) -> void:
	var row := _make_card(Color(0.30, 0.84, 0.88))
	var body := _make_body(row)
	var is_complete := bool(q.get("is_complete", false))
	var progress := int(q.get("progress", 0))
	var target := int(q.get("target", 1))
	var name_color := "#3BE06B" if is_complete else "#E8E86A"
	_body_line(body, "[color=%s]%s[/color]  [color=#888888]%d/%d[/color]" % [name_color, String(q.get("name", "Quest")), progress, target], 14)

	# Objective + dungeon direction hint (payload 'description' carries both).
	var desc := String(q.get("description", ""))
	if desc != "":
		_body_line(body, "[color=#B8B8B8]%s[/color]" % desc, 12, 18)

	# Turn-in location hint (mirrors the old text logic).
	var chain_id := String(q.get("chain_id", ""))
	var is_pathfinder := chain_id == "pathfinder"
	if is_complete:
		var quest_tp := String(q.get("trading_post", ""))
		if quest_tp == _tp_id or (is_pathfinder and _tp_id in STARTER_POSTS):
			_body_line(body, "[color=#3BE06B]Ready — turn in here (above).[/color]", 12, 18)
		elif is_pathfinder:
			_body_line(body, "[color=#88FF88]Ready — turn in at any starter post.[/color]", 12, 18)
		else:
			_body_line(body, "[color=#888888]Ready — turn in at %s.[/color]" % quest_tp.capitalize(), 12, 18)
	else:
		_body_line(body, "[color=#888888]In progress.[/color]", 12, 18)

	# Abandon button (Pathfinder chain is unabandonable).
	if not is_pathfinder:
		var btn := Button.new()
		btn.text = "Abandon"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(96, 34)
		btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
		var qid := String(q.get("id", ""))
		btn.pressed.connect(func(): abandon_requested.emit(qid))
		var wrap := CenterContainer.new()
		wrap.add_child(btn)
		row.add_child(wrap)


func _format_rewards(rewards: Dictionary) -> String:
	var parts: Array = []
	var xp := int(rewards.get("xp", 0))
	var valor := int(rewards.get("valor", 0))
	if xp > 0:
		parts.append("[color=#7FD8FF]%d XP[/color]" % xp)
	if valor > 0:
		parts.append("[color=#FFD700]%d Valor[/color]" % valor)
	if rewards.get("egg", false) or String(rewards.get("egg_type", "")) != "":
		parts.append("[color=#A335EE]an egg[/color]")
	if int(rewards.get("home_stones", 0)) > 0:
		parts.append("[color=#87CEEB]%d Home Stone(s)[/color]" % int(rewards.get("home_stones", 0)))
	var title := String(rewards.get("title", ""))
	if title != "":
		parts.append("[color=#FFD700]title: %s[/color]" % title)
	if parts.is_empty():
		return "[color=#808080]—[/color]"
	return "  ".join(parts)


func _on_close() -> void:
	visible = false
	dismissed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()


func _build_layout() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	# Sized large so a full board fits with little/no scrolling (fits within 1080p with margins).
	_root_panel.custom_minimum_size = Vector2(920, 960)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.10, 0.98)
	sb.border_color = Color(0.85, 0.68, 0.15, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_top = 16
	sb.content_margin_right = 20
	sb.content_margin_bottom = 16
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_root_panel.add_child(outer)

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)

	_title_label = RichTextLabel.new()
	_title_label.bbcode_enabled = true
	_title_label.fit_content = true
	_title_label.scroll_active = false
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.custom_minimum_size = Vector2(0, 28)
	_title_label.add_theme_font_size_override("normal_font_size", 19)
	header.add_child(_title_label)

	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("quest_board", _help_panel)
	header.add_child(help_btn)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.tooltip_text = "Close (Esc)"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(32, 28)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	_subtitle_label = RichTextLabel.new()
	_subtitle_label.bbcode_enabled = true
	_subtitle_label.fit_content = true
	_subtitle_label.scroll_active = false
	_subtitle_label.custom_minimum_size = Vector2(0, 22)
	_subtitle_label.add_theme_font_size_override("normal_font_size", 13)
	outer.add_child(_subtitle_label)

	var sep := HSeparator.new()
	outer.add_child(sep)

	# Scrollable content
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 860)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
