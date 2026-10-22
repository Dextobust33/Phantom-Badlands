extends Control
class_name PathsPanel

# Path of the Badlands (ARPG pillar 3, slice 1) — visual skill tree panel.
# Three themed branch columns + the player's class keystone. Click a node to
# preview it in the detail strip; Learn sends path_spend to the server, which
# owns all validation. The panel re-renders from character_update so server
# truth always wins (no optimistic state).
#
# Opened from the Stats panel's ⚜ Paths button (client._on_stats_panel_paths).

signal close_requested
signal learn_requested(node_id: String)
signal respec_requested(branch_id: String, confirm: bool)

const PathDatabaseScript = preload("res://shared/path_database.gd")
const PathPointsScript = preload("res://shared/path_points.gd")
const PathFeatsScript = preload("res://shared/path_feats.gd")

var _root_panel: PanelContainer
var _header_label: RichTextLabel
var _points_label: RichTextLabel
var _columns_hbox: GridContainer
var _keystone_row: HBoxContainer
var _milestone_label: RichTextLabel
var _detail_label: RichTextLabel
var _learn_button: Button

var _character_data: Dictionary = {}
var _selected_node_id: String = ""
var _node_buttons: Dictionary = {}  # node_id -> Button
var _respec_armed: String = ""      # branch id awaiting a second click to confirm

const COLOR_TAKEN := Color(0.35, 0.85, 0.35)
const COLOR_AVAILABLE := Color(1.0, 0.84, 0.0)
const COLOR_LOCKED := Color(0.45, 0.42, 0.38)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(character_data: Dictionary) -> void:
	populate(character_data)
	visible = true


func close() -> void:
	visible = false


func populate(character_data: Dictionary) -> void:
	_character_data = character_data.duplicate(true) if character_data is Dictionary else {}
	_render()


static func archetype_for_class(class_type: String) -> String:
	match class_type:
		"Fighter", "Barbarian", "Paladin":
			return "warrior"
		"Wizard", "Sorcerer", "Sage":
			return "mage"
		"Grifter", "Ranger", "Ninja":
			return "trickster"
		_:
			return "warrior"


func _ranks() -> Dictionary:
	var r = _character_data.get("path_ranks", {})
	if r is Dictionary:
		return r
	return {}


func _rank(node_id: String) -> int:
	return int(_ranks().get(node_id, 0))


func _spent() -> int:
	var n := 0
	for id in _ranks():
		n += PathPointsScript.total_cost(int(_ranks()[id]))
	return n


func _feat_src() -> Dictionary:
	var q = _character_data.get("completed_quests", [])
	return {"monsters_killed": int(_character_data.get("monsters_killed", 0)),
		"completed_quests": (q.size() if q is Array else 0),
		"level": int(_character_data.get("level", 1)),
		"counts": _character_data.get("feat_counts", {})}


func _points_earned() -> int:
	# The SAME functions the server uses (shared/path_points.gd), so the panel cannot drift from it.
	var claimed = _character_data.get("feats_claimed", {})
	var feat_points := 0
	if claimed is Dictionary:
		for fid in claimed:
			feat_points += int(claimed[fid])
	var legacy_free = _character_data.get("path_legacy_free", [])
	var ranks = _character_data.get("path_ranks", {})
	var bonus := 0
	if legacy_free is Array and ranks is Dictionary:
		bonus = PathPointsScript.legacy_bonus(ranks, legacy_free)
	return PathPointsScript.from_level(int(_character_data.get("level", 1))) + feat_points + bonus


func _points_available() -> int:
	return max(0, _points_earned() - _spent())


func _node_state(node: Dictionary) -> String:
	"""'maxed' | 'ranked' (some ranks, more to buy) | 'available' | 'locked' - display mirror of the server gating."""
	var node_id: String = String(node.get("id", ""))
	var have: int = _rank(node_id)
	var top: int = PathDatabaseScript.max_rank(node)
	if have >= top:
		return "maxed"
	var class_lock: String = String(node.get("class_lock", ""))
	if class_lock != "":
		if class_lock != String(_character_data.get("class", "")):
			return "locked"
		if bool(node.get("signature", false)):
			var sp: String = PathDatabaseScript.get_prereq_id(node_id)
			if sp != "" and _rank(sp) < 1:
				return "locked"
		elif _spent() < PathDatabaseScript.CLASS_KEYSTONE_SPEND_REQ:
			return "locked"
	else:
		var prereq: String = PathDatabaseScript.get_prereq_id(node_id)
		if prereq != "" and _rank(prereq) < 1:
			return "locked"
	if _points_available() < PathPointsScript.rank_cost(have + 1):
		return "locked"
	return "ranked" if have > 0 else "available"


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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.055, 0.04, 0.98)
	sb.border_color = Color(0.75, 0.62, 0.28, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_root_panel.add_theme_stylebox_override("panel", sb)
	_root_panel.custom_minimum_size = Vector2(900, 860)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_root_panel.add_child(vbox)

	# Title row
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(title_hbox)

	_header_label = RichTextLabel.new()
	_header_label.bbcode_enabled = true
	_header_label.fit_content = true
	_header_label.scroll_active = false
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.add_theme_font_size_override("normal_font_size", 18)
	title_hbox.add_child(_header_label)

	_points_label = RichTextLabel.new()
	_points_label.bbcode_enabled = true
	_points_label.fit_content = true
	_points_label.scroll_active = false
	_points_label.add_theme_font_size_override("normal_font_size", 15)
	_points_label.custom_minimum_size = Vector2(170, 0)
	title_hbox.add_child(_points_label)

	# Reusable ? Help button → paths_page topic (help-button-per-screen UX).
	var HelpPanelScript = load("res://client/help_panel.gd")
	var help_panel = HelpPanelScript.new()
	add_child(help_panel)
	title_hbox.add_child(HelpPanelScript.make_help_button("paths_page", help_panel))

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): close_requested.emit())
	title_hbox.add_child(close_btn)

	# Branch columns
	# Six branches per archetype: two rows of three, scrolled, so each column stays wide enough to read.
	var columns_scroll := ScrollContainer.new()
	columns_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(columns_scroll)
	_columns_hbox = GridContainer.new()
	_columns_hbox.columns = 3
	_columns_hbox.add_theme_constant_override("h_separation", 10)
	_columns_hbox.add_theme_constant_override("v_separation", 16)
	_columns_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_scroll.add_child(_columns_hbox)

	# Class keystone row
	_keystone_row = HBoxContainer.new()
	_keystone_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_keystone_row)

	# Milestones strip
	_milestone_label = RichTextLabel.new()
	_milestone_label.bbcode_enabled = true
	_milestone_label.fit_content = true
	_milestone_label.scroll_active = false
	_milestone_label.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(_milestone_label)

	# Detail strip + Learn button
	var detail_hbox := HBoxContainer.new()
	detail_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(detail_hbox)

	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = true
	_detail_label.scroll_active = false
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_label.add_theme_font_size_override("normal_font_size", 13)
	_detail_label.custom_minimum_size = Vector2(0, 56)
	detail_hbox.add_child(_detail_label)

	_learn_button = Button.new()
	_learn_button.text = "Learn (1 pt)"
	_learn_button.focus_mode = Control.FOCUS_NONE
	_learn_button.custom_minimum_size = Vector2(130, 40)
	_learn_button.disabled = true
	_learn_button.pressed.connect(_on_learn_pressed)
	detail_hbox.add_child(_learn_button)


func _render() -> void:
	var archetype := archetype_for_class(String(_character_data.get("class", "")))
	var tree: Dictionary = PathDatabaseScript.get_archetype_tree(archetype)
	_node_buttons.clear()

	_header_label.text = "[color=#FFD700]⚜ %s[/color]" % String(tree.get("title", "Path of the Badlands"))
	var pts := _points_available()
	_points_label.text = "[color=%s]Points: %d[/color]" % ["#FFD700" if pts > 0 else "#808080", pts]

	# Rebuild branch columns
	for child in _columns_hbox.get_children():
		child.queue_free()
	for branch in tree.get("branches", []):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_columns_hbox.add_child(col)

		var branch_title := RichTextLabel.new()
		branch_title.bbcode_enabled = true
		branch_title.fit_content = true
		branch_title.scroll_active = false
		branch_title.add_theme_font_size_override("normal_font_size", 15)
		branch_title.text = "[center][color=%s][b]%s[/b][/color][/center]" % [String(branch.get("color", "#FFFFFF")), String(branch.get("name", ""))]
		col.add_child(branch_title)
		var respec_btn := Button.new()
		var bid: String = String(branch.get("id", ""))
		var refund := 0
		for n in branch.get("nodes", []):
			refund += PathPointsScript.total_cost(_rank(String(n.get("id", ""))))
		respec_btn.focus_mode = Control.FOCUS_NONE
		respec_btn.disabled = refund <= 0
		respec_btn.text = ("Click again: refund %d pts for %s gold" % [refund, str(PathPointsScript.respec_price(int(_character_data.get("level", 1)), refund))]) if _respec_armed == bid else "Respec branch"
		respec_btn.tooltip_text = "Refund every point in this branch. Costs gold (%d kills' worth per point) and one of your limited respecs." % PathPointsScript.RESPEC_KILLS_PER_POINT
		respec_btn.pressed.connect(_on_respec_pressed.bind(bid))
		col.add_child(respec_btn)

		for node in branch.get("nodes", []):
			col.add_child(_make_node_button(node))

	# Class keystone (only the player's own class), preceded by the class's Signature branch when it has one
	for child in _keystone_row.get_children():
		child.queue_free()
	var sig_nodes: Array = PathDatabaseScript.signature_nodes(String(_character_data.get("class", "")))
	if not sig_nodes.is_empty():
		var sig_def: Dictionary = PathDatabaseScript.SIGNATURES[String(_character_data.get("class", ""))]
		var sig_box := VBoxContainer.new()
		sig_box.add_theme_constant_override("separation", 4)
		sig_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_keystone_row.add_child(sig_box)
		var sig_title := RichTextLabel.new()
		sig_title.bbcode_enabled = true
		sig_title.fit_content = true
		sig_title.scroll_active = false
		sig_title.add_theme_font_size_override("normal_font_size", 14)
		sig_title.text = "[color=%s][b]%s[/b][/color]  [color=#8A7B5C](%s only)[/color]" % [String(sig_def.get("color", "#C0C0C0")), String(sig_def.get("name", "Signature")), String(_character_data.get("class", ""))]
		sig_box.add_child(sig_title)
		var sig_row := HBoxContainer.new()
		sig_row.add_theme_constant_override("separation", 6)
		sig_box.add_child(sig_row)
		var sig_refund := 0
		for sn in sig_nodes:
			var sd: Dictionary = PathDatabaseScript.find_node(String(sn.get("id", "")))
			sig_refund += PathPointsScript.total_cost(_rank(String(sn.get("id", ""))))
			var sb := _make_node_button(sd)
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sig_row.add_child(sb)
		var sig_respec := Button.new()
		sig_respec.focus_mode = Control.FOCUS_NONE
		sig_respec.disabled = sig_refund <= 0
		sig_respec.text = ("Click again: refund %d pts for %s gold" % [sig_refund, str(PathPointsScript.respec_price(int(_character_data.get("level", 1)), sig_refund))]) if _respec_armed == "signature" else "Respec"
		sig_respec.pressed.connect(_on_respec_pressed.bind("signature"))
		sig_row.add_child(sig_respec)
		_keystone_row.move_child(sig_box, 0)
	var keystones: Dictionary = tree.get("class_keystones", {})
	var cls := String(_character_data.get("class", ""))
	if keystones.has(cls):
		var ck: Dictionary = keystones[cls].duplicate()
		ck["class_lock"] = cls
		var ck_label := RichTextLabel.new()
		ck_label.bbcode_enabled = true
		ck_label.fit_content = true
		ck_label.scroll_active = false
		ck_label.add_theme_font_size_override("normal_font_size", 13)
		ck_label.custom_minimum_size = Vector2(200, 0)
		ck_label.text = "[color=#C4A882]%s Keystone (%d pts spent to unlock):[/color]" % [cls, PathDatabaseScript.CLASS_KEYSTONE_SPEND_REQ]
		_keystone_row.add_child(ck_label)
		var ck_btn := _make_node_button(ck)
		ck_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_keystone_row.add_child(ck_btn)

	# Feats strip: each ladder with progress toward its next rung (every rung pays +1 point)
	var claimed = _character_data.get("feats_claimed", {})
	var src := _feat_src()
	var ms_parts: Array = []
	for fid in PathFeatsScript.FEATS:
		var f: Dictionary = PathFeatsScript.FEATS[fid]
		var rungs: Array = f.get("rungs", [])
		var have: int = int((claimed as Dictionary).get(fid, 0)) if claimed is Dictionary else 0
		var val: int = PathFeatsScript.value_of(String(fid), src)
		if have >= rungs.size():
			ms_parts.append("[color=#66FF66]✓ %s (all %d)[/color]" % [String(f.get("label", fid)), rungs.size()])
		else:
			ms_parts.append("[color=#B0A080]%s %d/%d (%d/%d)[/color]" % [String(f.get("label", fid)), val, int(rungs[have]), have, rungs.size()])
	_milestone_label.text = "[color=#8A7B5C]Feats (each rung +1 point):[/color]  " + "   ".join(ms_parts)

	_refresh_detail()


func _make_node_button(node: Dictionary) -> Button:
	var node_id := String(node.get("id", ""))
	var state := _node_state(node)
	var btn := Button.new()
	var star := "★ " if node.get("keystone", false) or (String(node.get("class_lock", "")) != "" and not bool(node.get("signature", false))) else ""
	var top: int = PathDatabaseScript.max_rank(node)
	var have: int = _rank(node_id)
	var mark := "✓ " if state == "maxed" else ""
	var rank_txt := "" if top <= 1 else " %d/%d" % [have, top]
	btn.text = mark + star + String(node.get("name", node_id)) + rank_txt
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 38)
	btn.tooltip_text = String(node.get("desc", ""))
	match state:
		"maxed", "ranked":
			btn.add_theme_color_override("font_color", COLOR_TAKEN)
		"available":
			btn.add_theme_color_override("font_color", COLOR_AVAILABLE)
		_:
			btn.add_theme_color_override("font_color", COLOR_LOCKED)
	if state == "ranked":
		btn.add_theme_color_override("font_color", COLOR_AVAILABLE if _points_available() >= PathPointsScript.rank_cost(have + 1) else COLOR_TAKEN)
	btn.pressed.connect(_on_node_pressed.bind(node))
	_node_buttons[node_id] = btn
	return btn


func _on_node_pressed(node: Dictionary) -> void:
	_selected_node_id = String(node.get("id", ""))
	_refresh_detail(node)


func _refresh_detail(node: Dictionary = {}) -> void:
	if node.is_empty() and _selected_node_id != "":
		node = PathDatabaseScript.find_node(_selected_node_id)
	if node.is_empty():
		_detail_label.text = "[color=#8A7B5C]Select a node to read it. Earn Path points by levelling and from the feats above; most nodes can be ranked up. Choices are permanent for this life, apart from a limited, paid respec.[/color]"
		_learn_button.disabled = true
		return
	var state := _node_state(node)
	var nid: String = String(node.get("id", ""))
	var have: int = _rank(nid)
	var top: int = PathDatabaseScript.max_rank(node)
	var cost: int = PathPointsScript.rank_cost(have + 1)
	var status_line := ""
	match state:
		"maxed":
			status_line = "[color=#66FF66]Learned%s.[/color]" % ("" if top <= 1 else " - fully ranked (%d/%d)" % [have, top])
		"available", "ranked":
			status_line = "[color=#FFD700]%s - costs %d Path point(s).[/color]" % ["Available" if have == 0 else "Rank %d of %d learned; rank %d is available" % [have, top, have + 1], cost]
		_:
			if have > 0 and _points_available() < cost:
				status_line = "[color=#FF6666]Rank %d costs %d point(s); you have %d.[/color]" % [have + 1, cost, _points_available()]
			elif _points_available() < cost:
				status_line = "[color=#FF6666]Costs %d point(s); you have %d.[/color]" % [cost, _points_available()]
			else:
				status_line = "[color=#FF6666]Locked — requires the previous node in this branch%s.[/color]" % (" / %d points spent" % PathDatabaseScript.CLASS_KEYSTONE_SPEND_REQ if String(node.get("class_lock", "")) != "" else "")
	var per_rank := "" if top <= 1 else "\n[color=#C4A882]Each rank adds this again (you have %dx).[/color]" % have
	if node.has("rank_curve"):
		per_rank = "\n[color=#C4A882]Rank 1 gives half of this, rank 2 three quarters, rank %d all of it (you have rank %d).[/color]" % [top, have]
	_detail_label.text = "[b][color=#FFD700]%s[/color][/b]\n%s%s\n%s" % [String(node.get("name", "")), String(node.get("desc", "")), per_rank, status_line]
	_learn_button.text = "Learn (%d pt)" % cost if have == 0 else "Rank up (%d pt)" % cost
	_learn_button.disabled = not (state == "available" or state == "ranked")


func _on_respec_pressed(branch_id: String) -> void:
	if _respec_armed == branch_id:
		_respec_armed = ""
		respec_requested.emit(branch_id, true)
	else:
		_respec_armed = branch_id
		_render()


func _on_learn_pressed() -> void:
	if _selected_node_id == "":
		return
	learn_requested.emit(_selected_node_id)
