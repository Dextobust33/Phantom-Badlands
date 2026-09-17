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
# ⚑ ONE PANEL, TWO TABS. Owner 2026-09-17, asked whether the Atlas and the quest board should
# be one thing: *"Is there enough overlap to combine the two? I guess we will just need to
# ensure the difference between each is clear."*
#
# They share a SUBJECT (dungeons) but answer different QUESTIONS - the Atlas answers *where do
# I go and what is in there*, the board answers *what am I asked to do and what have I got on*.
# One list would make a row sometimes-a-place and sometimes-a-task, so it is one SHELL with two
# tabs, and the difference is carried by the VERB each row offers: Dungeons rows offer Locate,
# Quest rows offer Accept / Turn In / Abandon. The PIN is the bridge between them.
#
# Switching tab re-asks the server rather than caching: a stale Atlas showing a quest you have
# since turned in is worse than a round trip nobody notices.
signal atlas_requested
signal quests_requested
signal locate_requested(dungeon_id: String)

const HelpPanelScript = preload("res://client/help_panel.gd")

# Starter posts where the Pathfinder chain can be turned in from anywhere.
const STARTER_POSTS := ["haven", "crossroads", "south_gate", "east_market", "west_shrine"]

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _subtitle_label: RichTextLabel
var _content: VBoxContainer          # rebuilt each open_board()
var _help_panel: Control = null

var _tp_id: String = ""
## Which tab is showing: "quests" or "dungeons".
var _mode: String = "quests"
var _tab_row: HBoxContainer = null
var _active_count: int = 0
var _max_quests: int = 3


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open_board(message: Dictionary, active_only: bool = false) -> void:
	"""Render the quest_list payload as cards. Called on every quest_list message
	(initial open + refreshes after accept/turn-in). active_only = the unified 'Your Quests'
	view opened from the map — shows just the Active section (no Turn In / Available)."""
	_mode = "quests"
	_tp_id = String(message.get("trading_post_id", ""))
	_active_count = int(message.get("active_count", 0))
	_max_quests = int(message.get("max_quests", 3))
	var giver := String(message.get("quest_giver", "Quest Giver"))
	var tp_name := String(message.get("trading_post", "Trading Post"))
	var turn_ins: Array = message.get("quests_to_turn_in", [])
	var available: Array = message.get("available_quests", [])
	var active: Array = message.get("active_quests", [])
	var full := _active_count >= _max_quests

	_title_label.clear()
	_subtitle_label.clear()
	if active_only:
		_title_label.append_text("[color=#FFD700]✧ Your Quests[/color]")
		_subtitle_label.append_text("[color=#4DD6E0]Active quests: %d / %d[/color]   [color=#888888]Visit a Quest Board (Q) at a post to take or turn in quests.[/color]" % [_active_count, _max_quests])
	else:
		_title_label.append_text("[color=#FFD700]✧ Quest Board — %s[/color]" % tp_name)
		var slot_color := "#FF8866" if full else "#9ACD32"
		_subtitle_label.append_text("[color=#B0B0B0]%s[/color]   [color=%s]Active quests: %d / %d[/color]%s" % [
			giver, slot_color, _active_count, _max_quests,
			("   [color=#FF8866](full — turn in or abandon to free a slot)[/color]" if full else "")])

	# Rebuild content
	for c in _content.get_children():
		c.queue_free()
	_add_tabs()

	if not active_only:
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
	if active_only:
		if active.size() == 0:
			_add_empty_line("You have no active quests. Take some at a Quest Board (Q).")
		else:
			for q in active:
				_add_active_card(q)
	elif active.size() > 0:
		_add_section_header("Your Active Quests", "#4DD6E0")
		for q in active:
			_add_active_card(q)

	visible = true


# ---------- card builders ----------

func open_atlas(message: Dictionary) -> void:
	"""The DUNGEONS tab - where to go, what is in there, and which places are wanted.

	Replaces the text Atlas that lived in `game_output`, and the orphaned text dungeon LIST that
	could only be reached by typing `/dungeons`. Both retire with this, which is the "ensure we
	don't have dead UI buttons/navigations to the one we aren't using" half of the owner's ask.

	A row per dungeon rather than the old three prose lines each - same reasoning as the dungeon
	entrance table: one fact per row, and the detail on the row that needs it."""
	_mode = "dungeons"
	var entries: Array = message.get("entries", [])
	var pins: Dictionary = message.get("pins", {})
	var discovered := int(message.get("discovered", 0))
	var total := int(message.get("total", entries.size()))
	var rank := int(message.get("cartography_rank", 1))
	var rmax := int(message.get("cartography_max_rank", 8))
	var sense := int(message.get("cartography_sense_rank", 8))
	var cxp := int(message.get("cartography_xp", 0))
	var cnext := int(message.get("cartography_next_xp", 0))
	var at_post := bool(message.get("at_post", false))
	var my_level := int(message.get("player_level", 0))

	_title_label.clear()
	_subtitle_label.clear()
	_title_label.append_text("[color=#FFD700]✦ Dungeon Atlas[/color]")
	# Cartography is the Atlas's own progression and its gate on Locate, so it belongs in the
	# subtitle where the quest view puts its slot count - the same line answering "what can I do
	# from here right now".
	var precision := "region hints only"
	if rank >= 5:
		precision = "precise coordinates"
	elif rank >= 3:
		precision = "direction + distance"
	var prog := "[color=#606060](max rank)[/color]"
	if rank < rmax:
		prog = "[color=#606060](%d / %d XP to rank %d)[/color]" % [cxp, cnext, rank + 1]
	var gate := ""
	if rank >= sense:
		gate = "   [color=#7AE07A]Locate works anywhere.[/color]"
	elif at_post:
		gate = "   [color=#C8A24A]A Cartographer is here — Locate costs Valor.[/color]"
	else:
		gate = "   [color=#909090]Locate needs a Cartographer (K) at a post.[/color]"
	_subtitle_label.append_text("[color=#4DD6E0]Discovered %d / %d[/color]   [color=#5AC8FF]🧭 Cartography %d / %d[/color] [color=#909090]— %s[/color] %s%s" % [
		discovered, total, rank, rmax, precision, prog, gate])

	for c in _content.get_children():
		c.queue_free()
	_add_tabs()

	# PINNED FIRST. A dungeon something is asking you for is the one you came to this screen to
	# find, so it sorts above everything regardless of grade.
	var pinned: Array = []
	var known: Array = []
	var rumours: Array = []
	for e in entries:
		var st := int(e.get("state", 0))
		if pins.has(String(e.get("id", ""))):
			pinned.append(e)
		elif st >= 3:
			known.append(e)
		elif st >= 1:
			rumours.append(e)

	if pinned.size() > 0:
		_add_section_header("⚑ Wanted — a quest points here", "#FFD700")
		for e in pinned:
			_add_dungeon_card(e, pins.get(String(e.get("id", "")), {}), rank, sense, at_post, my_level)
	if known.size() > 0:
		_add_section_header("Dungeons you have entered", "#4DD6E0")
		for e in known:
			_add_dungeon_card(e, {}, rank, sense, at_post, my_level)
	if rumours.size() > 0:
		# Owner chose reading (a): a rumour row is INFORMATIONAL and names where it was heard, so
		# every accept still happens at a post. No Accept button lives on this tab.
		_add_section_header("Rumours", "#A0A0A0")
		for e in rumours:
			_add_rumour_line(e)
	if pinned.is_empty() and known.is_empty() and rumours.is_empty():
		_add_empty_line("You have not heard of a single dungeon yet. Ask at a trading post.")

	visible = true


func _add_dungeon_card(e: Dictionary, pin: Dictionary, rank: int, sense: int, at_post: bool, my_level: int = 0) -> void:
	"""One dungeon: its grade and band, what it holds, and Locate. Plus the quest, when pinned."""
	var tier := int(e.get("tier", 1))
	var row := _make_card(Color(0.30, 0.42, 0.44) if pin.is_empty() else Color(0.62, 0.52, 0.16))
	var body := _make_body(row)
	var label := PowerRank.label(tier, int(e.get("rank", 0))) if int(e.get("rank", 0)) > 0 else PowerRank.letter(tier)
	# ⚑ THE VERDICT, IN THE SAME WORDS THE ENTRANCE SCREEN USES. Deliberately the same
	# phrasing and the same thresholds: a player should not have to learn that "above you"
	# here and "above you" on the door mean the same thing.
	var verdict := ""
	if my_level > 0:
		var gap: int = int(e.get("level_min", 1)) - my_level
		if gap >= 8:
			verdict = "  [color=#FF2A2A]far above you[/color]"
		elif gap >= 3:
			verdict = "  [color=#FF5555]above you[/color]"
		elif gap >= -2:
			verdict = "  [color=#FFAA00]your level[/color]"
		else:
			verdict = "  [color=#9ACD32]below you[/color]"
	# A pinned dungeon may be UNDISCOVERED - the quest is what told the player it exists -
	# and the Atlas only fills `name` in from SPOTTED upward. The pin carries the dungeon's
	# own name for exactly that case, so the one row that must read clearly does.
	var dname: String = String(e.get("name", ""))
	if dname == "":
		dname = String(pin.get("dungeon_name", ""))
	if dname == "":
		dname = "?"
	_body_line(body, "[color=%s][b]%s[/b][/color]  [color=#C8C8C8]%s[/color]   [color=#808080]Lv %d-%d · %d clears[/color]%s" % [
		PowerRank.color(tier), label, dname,
		int(e.get("level_min", 1)), int(e.get("level_max", 99)), int(e.get("clears", 0)), verdict], 15, 22)
	if not pin.is_empty():
		# The bridge to the other tab: what is wanted, how far along, and WHERE to hand it in -
		# because this tab deliberately cannot accept or turn in anything.
		var where := String(pin.get("post", ""))
		_body_line(body, "[color=#FFD700]⚑ %s[/color] [color=#909090]— %d / %d%s[/color]" % [
			String(pin.get("name", "A quest")), int(pin.get("progress", 0)), int(pin.get("target", 1)),
			("  · hand in at %s" % where) if where != "" else ""], 13, 18)
	var mons: Array = e.get("monsters", [])
	if mons.size() > 0:
		_body_line(body, "[color=#909090]%s[/color]   [color=#A335EE]egg:[/color] [color=#909090]%s[/color]" % [
			", ".join(mons), String(e.get("companion", "—"))], 12, 17)
	# Locate is this tab's verb. Greyed rather than hidden when it cannot be used, so the reason
	# is visible - the subtitle says what unlocks it.
	var can_locate: bool = rank >= sense or at_post
	var b := Button.new()
	b.text = "Locate"
	b.disabled = not can_locate
	b.tooltip_text = "Mark this dungeon on your map" if can_locate else "Needs a Cartographer at a post, or Cartography rank %d" % sense
	b.custom_minimum_size = Vector2(96, 30)
	var did := String(e.get("id", ""))
	b.pressed.connect(func(): locate_requested.emit(did))
	row.add_child(b)


func _add_rumour_line(e: Dictionary) -> void:
	"""A dungeon you have only heard about. No name, no Locate, and no Accept - it names the post
	that was talking about it, and you go there to ask."""
	var tier := int(e.get("tier", 1))
	var from_post := String(e.get("from_post", ""))
	var where := ("heard at [color=#C8A24A]%s[/color]" % from_post) if from_post != "" else "whispered of nearby"
	_add_empty_line("[color=%s]?[/color]  [color=#808080]an unnamed[/color] [color=%s][b]%s[/b][/color] [color=#808080]dungeon — %s[/color]" % [
		PowerRank.color(tier), PowerRank.color(tier), PowerRank.letter(tier), where])


func _add_tabs() -> void:
	"""The two doors, always both visible. A tab the player is already on is disabled rather than
	removed, so the pair does not shuffle position between views."""
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 8)
	var q := Button.new()
	q.text = "Quests"
	q.custom_minimum_size = Vector2(120, 32)
	q.disabled = _mode == "quests"
	q.pressed.connect(func(): quests_requested.emit())
	_tab_row.add_child(q)
	var d := Button.new()
	d.text = "Dungeons"
	d.custom_minimum_size = Vector2(120, 32)
	d.disabled = _mode == "dungeons"
	d.pressed.connect(func(): atlas_requested.emit())
	_tab_row.add_child(d)
	_content.add_child(_tab_row)


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
