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

const PathDatabaseScript = preload("res://shared/path_database.gd")

var _root_panel: PanelContainer
var _header_label: RichTextLabel
var _points_label: RichTextLabel
var _columns_hbox: HBoxContainer
var _keystone_row: HBoxContainer
var _milestone_label: RichTextLabel
var _detail_label: RichTextLabel
var _learn_button: Button

var _character_data: Dictionary = {}
var _selected_node_id: String = ""
var _node_buttons: Dictionary = {}  # node_id -> Button

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
		"Thief", "Ranger", "Ninja":
			return "trickster"
		_:
			return "warrior"


func _taken() -> Array:
	var t = _character_data.get("path_nodes", [])
	return t if t is Array else []


func _milestones() -> Array:
	var m = _character_data.get("path_milestones", [])
	return m if m is Array else []


func _points_available() -> int:
	# Mirrors character.get_path_points_earned(): level/5 + milestones. The
	# server re-validates every spend, so drift here is display-only.
	var earned: int = int(int(_character_data.get("level", 1)) / 5.0) + _milestones().size()
	return max(0, earned - _taken().size())


func _node_state(node: Dictionary) -> String:
	"""'taken' | 'available' | 'locked' — display mirror of the server gating."""
	var node_id: String = String(node.get("id", ""))
	var taken: Array = _taken()
	if node_id in taken:
		return "taken"
	var class_lock: String = String(node.get("class_lock", ""))
	if class_lock != "":
		if class_lock != String(_character_data.get("class", "")):
			return "locked"
		if taken.size() < PathDatabaseScript.CLASS_KEYSTONE_SPEND_REQ:
			return "locked"
	else:
		var prereq: String = PathDatabaseScript.get_prereq_id(node_id)
		if prereq != "" and not (prereq in taken):
			return "locked"
	if _points_available() < 1:
		return "locked"
	return "available"


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
	_root_panel.custom_minimum_size = Vector2(900, 620)
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

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): close_requested.emit())
	title_hbox.add_child(close_btn)

	# Branch columns
	_columns_hbox = HBoxContainer.new()
	_columns_hbox.add_theme_constant_override("separation", 10)
	_columns_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_columns_hbox)

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

		for node in branch.get("nodes", []):
			col.add_child(_make_node_button(node))

	# Class keystone (only the player's own class)
	for child in _keystone_row.get_children():
		child.queue_free()
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

	# Milestones strip
	var ms_taken := _milestones()
	var ms_parts: Array = []
	for ms_id in PathDatabaseScript.MILESTONES:
		var done: bool = ms_id in ms_taken
		ms_parts.append("[color=%s]%s %s[/color]" % ["#66FF66" if done else "#666666", "✓" if done else "·", String(PathDatabaseScript.MILESTONES[ms_id])])
	_milestone_label.text = "[color=#8A7B5C]Feats (+1 point each):[/color]  " + "   ".join(ms_parts)

	_refresh_detail()


func _make_node_button(node: Dictionary) -> Button:
	var node_id := String(node.get("id", ""))
	var state := _node_state(node)
	var btn := Button.new()
	var star := "★ " if node.get("keystone", false) or String(node.get("class_lock", "")) != "" else ""
	var mark := "✓ " if state == "taken" else ""
	btn.text = mark + star + String(node.get("name", node_id))
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 38)
	btn.tooltip_text = String(node.get("desc", ""))
	match state:
		"taken":
			btn.add_theme_color_override("font_color", COLOR_TAKEN)
		"available":
			btn.add_theme_color_override("font_color", COLOR_AVAILABLE)
		_:
			btn.add_theme_color_override("font_color", COLOR_LOCKED)
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
		_detail_label.text = "[color=#8A7B5C]Select a node to read it. Earn Path points every 5 levels and from the feats above. Choices are permanent for this life.[/color]"
		_learn_button.disabled = true
		return
	var state := _node_state(node)
	var status_line := ""
	match state:
		"taken":
			status_line = "[color=#66FF66]Learned.[/color]"
		"available":
			status_line = "[color=#FFD700]Available — costs 1 Path point.[/color]"
		_:
			if _points_available() < 1:
				status_line = "[color=#FF6666]No Path points available.[/color]"
			else:
				status_line = "[color=#FF6666]Locked — requires the previous node in this branch%s.[/color]" % (" / %d points spent" % PathDatabaseScript.CLASS_KEYSTONE_SPEND_REQ if String(node.get("class_lock", "")) != "" else "")
	_detail_label.text = "[b][color=#FFD700]%s[/color][/b]\n%s\n%s" % [String(node.get("name", "")), String(node.get("desc", "")), status_line]
	_learn_button.disabled = state != "available"


func _on_learn_pressed() -> void:
	if _selected_node_id == "":
		return
	learn_requested.emit(_selected_node_id)
