extends Control
class_name CraftingPanel

# Visual crafting surface: recipe list on the left, detail + Craft on the right.
# Mirrors the inventory_panel pattern (one container, no separate card scenes).

signal close_requested
signal recipe_selected(recipe_index: int)
signal craft_pressed(recipe_index: int, quantity: int)
signal quantity_changed(quantity: int)
signal skill_changed(skill: String)

const SKILL_CHIPS := [
	{"id": "blacksmithing", "label": "Forge", "color": Color(1.0, 0.4, 0.0)},
	{"id": "alchemy", "label": "Alch", "color": Color(0.0, 1.0, 0.0)},
	{"id": "enchanting", "label": "Ench", "color": Color(0.64, 0.21, 0.93)},
	{"id": "scribing", "label": "Scribe", "color": Color(0.53, 0.81, 0.92)},
	{"id": "construction", "label": "Build", "color": Color(0.67, 0.47, 0.27)},
]

var client_ref = null
var _current_skill: String = ""
var _recipes: Array = []
var _materials: Dictionary = {}
var _selected_index: int = -1
var _upcoming_unlocks: Array = []  # Audit #8 Layer 7: next 3 locked recipes preview
var _craft_quantity: int = 1
var _allow_skill_switch: bool = true

var _root_panel: PanelContainer
var _title_label: Label

# v0.9.503 — reusable HelpPanel attached to the header ? Help button.
var _help_panel: Control = null
var _skill_label: Label
var _bonus_label: RichTextLabel
var _skill_chip_row: HBoxContainer
var _skill_chip_buttons: Dictionary = {}
var _recipe_list_vbox: VBoxContainer
var _detail_root: VBoxContainer
var _detail_title: Label
var _detail_meta: RichTextLabel
var _detail_materials: RichTextLabel
var _qty_row: HBoxContainer
var _qty_label: Label
var _qty_minus: Button
var _qty_plus: Button
var _qty_max: Button
var _craft_button: Button
var _detail_empty: Label
var _status_label: RichTextLabel

var _recipe_buttons: Array = []  # Buttons in left list, parallel to _recipes


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_build_layout()
	visible = false


func _build_layout() -> void:
	_root_panel = PanelContainer.new()
	_root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.055, 0.045, 0.97)
	sb.border_color = Color(0.55, 0.45, 0.33, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_top = 8
	sb.content_margin_right = 8
	sb.content_margin_bottom = 8
	_root_panel.add_theme_stylebox_override("panel", sb)
	add_child(_root_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	_root_panel.add_child(root_vbox)

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Crafting"
	_title_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_title_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_title_label)

	_skill_label = Label.new()
	_skill_label.text = ""
	_skill_label.add_theme_font_size_override("font_size", 13)
	header.add_child(_skill_label)

	_bonus_label = RichTextLabel.new()
	_bonus_label.bbcode_enabled = true
	_bonus_label.fit_content = true
	_bonus_label.scroll_active = false
	_bonus_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bonus_label.custom_minimum_size = Vector2(0, 20)
	_bonus_label.add_theme_font_size_override("normal_font_size", 12)
	header.add_child(_bonus_label)

	# v0.9.503 — Help button on the Crafting header. Opens crafting_page
	# topic (7 transparency layers, specialty lock-in, quality scaling).
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("crafting_page", _help_panel)
	header.add_child(help_btn)

	# Skill chips (only visible when we're allowed to switch — i.e., not station-locked)
	_skill_chip_row = HBoxContainer.new()
	_skill_chip_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(_skill_chip_row)
	for chip in SKILL_CHIPS:
		var btn := Button.new()
		btn.text = chip["label"]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 24)
		var col: Color = chip["color"]
		btn.add_theme_color_override("font_color", col)
		btn.pressed.connect(_on_skill_chip_pressed.bind(chip["id"]))
		_skill_chip_row.add_child(btn)
		_skill_chip_buttons[chip["id"]] = btn

	# Body: recipe list (left) + detail (right)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_vbox.add_child(body)

	# Left: recipe list inside a scroll container
	var list_panel := _make_subpanel()
	list_panel.custom_minimum_size = Vector2(360, 0)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(list_panel)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(list_scroll)

	_recipe_list_vbox = VBoxContainer.new()
	_recipe_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list_vbox.add_theme_constant_override("separation", 2)
	list_scroll.add_child(_recipe_list_vbox)

	# Right: detail
	var detail_panel := _make_subpanel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)

	_detail_root = VBoxContainer.new()
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.add_theme_constant_override("separation", 6)
	detail_panel.add_child(_detail_root)

	_detail_title = Label.new()
	_detail_title.text = ""
	_detail_title.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_root.add_child(_detail_title)

	_detail_meta = RichTextLabel.new()
	_detail_meta.bbcode_enabled = true
	_detail_meta.fit_content = true
	_detail_meta.scroll_active = false
	_detail_meta.add_theme_font_size_override("normal_font_size", 15)
	_detail_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.add_child(_detail_meta)

	_detail_materials = RichTextLabel.new()
	_detail_materials.bbcode_enabled = true
	_detail_materials.fit_content = true
	_detail_materials.scroll_active = false
	_detail_materials.add_theme_font_size_override("normal_font_size", 16)
	_detail_materials.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.add_child(_detail_materials)

	# Quantity stepper
	_qty_row = HBoxContainer.new()
	_qty_row.add_theme_constant_override("separation", 6)
	_detail_root.add_child(_qty_row)

	var qty_title := Label.new()
	qty_title.text = "Qty:"
	qty_title.add_theme_color_override("font_color", Color(0.55, 0.81, 0.92))
	qty_title.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(qty_title)

	_qty_minus = _make_action_btn(" - ", _on_qty_minus_pressed)
	_qty_minus.custom_minimum_size = Vector2(40, 30)
	_qty_minus.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(_qty_minus)

	_qty_label = Label.new()
	_qty_label.text = "1"
	_qty_label.custom_minimum_size = Vector2(48, 0)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(_qty_label)

	_qty_plus = _make_action_btn(" + ", _on_qty_plus_pressed)
	_qty_plus.custom_minimum_size = Vector2(40, 30)
	_qty_plus.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(_qty_plus)

	_qty_max = _make_action_btn("Max", _on_qty_max_pressed)
	_qty_max.add_theme_font_size_override("font_size", 15)
	_qty_row.add_child(_qty_max)

	# Craft button
	_craft_button = Button.new()
	_craft_button.text = "Craft"
	_craft_button.focus_mode = Control.FOCUS_NONE
	_craft_button.add_theme_font_size_override("font_size", 18)
	_craft_button.custom_minimum_size = Vector2(0, 44)
	_craft_button.pressed.connect(_on_craft_pressed)
	_detail_root.add_child(_craft_button)

	_detail_empty = Label.new()
	_detail_empty.text = "Select a recipe on the left."
	_detail_empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_detail_empty.add_theme_font_size_override("font_size", 15)
	_detail_root.add_child(_detail_empty)

	# Spacer pushes status row to bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.add_child(spacer)

	# Status row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(action_row)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_font_size_override("normal_font_size", 13)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.text = ""
	action_row.add_child(_status_label)

	action_row.add_child(_make_action_btn("Close (Space)", _on_close_pressed))

	_show_detail_empty(true)


func _make_subpanel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.035, 0.025, 0.7)
	sb.border_color = Color(0.4, 0.34, 0.25, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 6
	sb.content_margin_right = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_action_btn(label: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(0, 28)
	b.pressed.connect(callback)
	return b


# === Public API ===

func show_panel() -> void:
	visible = true


func hide_panel() -> void:
	visible = false


func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func set_allow_skill_switch(allow: bool) -> void:
	_allow_skill_switch = allow
	if _skill_chip_row:
		_skill_chip_row.visible = allow


# Audit #8 Layer 7 — next 3 locked recipes shown as a "Coming Up" footer in
# the recipe list. Call right after populate() so _rebuild_recipe_list sees it.
func set_upcoming_unlocks(unlocks: Array) -> void:
	_upcoming_unlocks = unlocks


# Called by client.gd whenever the recipe list / materials change (server craft_list response,
# materials update, character_update, etc.).
func populate(skill: String, recipes: Array, materials: Dictionary, skill_level: int, post_bonus: int, job_bonus: Dictionary, selected_index: int, craft_quantity: int) -> void:
	if not is_inside_tree():
		return
	_current_skill = skill
	_recipes = recipes
	_materials = materials
	_selected_index = selected_index
	_craft_quantity = max(1, craft_quantity)

	# Header
	if skill != "":
		_skill_label.text = "[%s Lv%d]" % [skill.capitalize(), skill_level]
		var col := _skill_color(skill)
		_skill_label.add_theme_color_override("font_color", col)
	else:
		_skill_label.text = ""

	var bonus_parts := []
	if post_bonus > 0:
		bonus_parts.append("[color=#00FFFF]Post +%d%%[/color]" % post_bonus)
	if job_bonus.get("quality_bonus", 0) > 0:
		bonus_parts.append("[color=#FFD700]Spec +%d%%[/color]" % job_bonus["quality_bonus"])
	_bonus_label.text = "  ".join(bonus_parts) if bonus_parts.size() > 0 else ""

	# Skill chip selection
	for sk in _skill_chip_buttons.keys():
		_skill_chip_buttons[sk].button_pressed = (sk == skill)

	_rebuild_recipe_list()
	_refresh_detail()


func _skill_color(skill: String) -> Color:
	for chip in SKILL_CHIPS:
		if chip["id"] == skill:
			return chip["color"]
	return Color(1, 1, 1)


func _rebuild_recipe_list() -> void:
	for child in _recipe_list_vbox.get_children():
		child.queue_free()
	_recipe_buttons.clear()

	if _recipes.is_empty():
		var lbl := Label.new()
		lbl.text = "No recipes available."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		lbl.add_theme_font_size_override("font_size", 12)
		_recipe_list_vbox.add_child(lbl)
		return

	for i in range(_recipes.size()):
		var recipe = _recipes[i]
		var btn = _make_recipe_button(recipe, i)
		_recipe_list_vbox.add_child(btn)
		_recipe_buttons.append(btn)

	# Audit #8 Layer 7 — Coming Up preview footer mirroring the text-mode list.
	if not _upcoming_unlocks.is_empty():
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 6)
		_recipe_list_vbox.add_child(spacer)

		var header := Label.new()
		header.text = "── Coming Up ──"
		header.add_theme_color_override("font_color", Color(0.60, 0.80, 0.20))
		header.add_theme_font_size_override("font_size", 12)
		_recipe_list_vbox.add_child(header)

		for unlock in _upcoming_unlocks:
			var u_name := str(unlock.get("name", "Unknown"))
			var u_req := int(unlock.get("skill_required", 0))
			var u_type := str(unlock.get("output_type", ""))
			var u_away := int(unlock.get("levels_away", 0))
			var away_label := "%d level%s away" % [u_away, "" if u_away == 1 else "s"]
			var type_tag := " (%s)" % u_type if u_type != "" else ""
			var row := RichTextLabel.new()
			row.bbcode_enabled = true
			row.fit_content = true
			row.scroll_active = false
			row.add_theme_font_size_override("normal_font_size", 12)
			row.text = "  [color=#888888]Lv%d[/color] [color=#AAAAAA]%s[/color][color=#666666]%s[/color] [color=#9ACD32]— %s[/color]" % [u_req, u_name, type_tag, away_label]
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_recipe_list_vbox.add_child(row)


func _make_recipe_button(recipe: Dictionary, index: int) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 44)
	btn.toggle_mode = true
	btn.button_pressed = (index == _selected_index)
	btn.add_theme_font_size_override("font_size", 12)

	var name := str(recipe.get("name", "?"))
	var skill_req := int(recipe.get("skill_required", 1))
	var is_locked: bool = recipe.get("locked", false)
	var is_specialist_gated: bool = recipe.get("specialist_gated", false)
	var can_craft: bool = recipe.get("can_craft", false)

	var label := name
	if is_locked:
		label = "Locked  %s (Lv%d)" % [name, skill_req]
		btn.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		btn.disabled = true
	elif is_specialist_gated:
		label = "[Spec]  %s" % name
		btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.27))
		btn.disabled = true
	else:
		var color := Color(0, 1, 0) if can_craft else Color(0.7, 0.7, 0.7)
		btn.add_theme_color_override("font_color", color)
		var spec_tag = " ★" if recipe.get("specialist_only", false) else ""
		label = "%s%s  Lv%d" % [name, spec_tag, skill_req]

	btn.text = label
	btn.pressed.connect(_on_recipe_pressed.bind(index))
	return btn


func _refresh_detail() -> void:
	var has_selection := _selected_index >= 0 and _selected_index < _recipes.size()
	_show_detail_empty(not has_selection)
	if not has_selection:
		return

	var recipe = _recipes[_selected_index]
	var name = str(recipe.get("name", "?"))
	var skill_req = int(recipe.get("skill_required", 1))
	var difficulty = int(recipe.get("difficulty", 10))
	var success_chance = int(recipe.get("success_chance", 50))
	var is_bulk = recipe.get("bulk_craftable", false) and int(recipe.get("max_craftable", 1)) > 1
	var max_qty = int(recipe.get("max_craftable", 1)) if is_bulk else 1
	var can_craft = recipe.get("can_craft", false)
	var is_locked = recipe.get("locked", false)
	var is_specialist_gated = recipe.get("specialist_gated", false)

	if is_bulk:
		_craft_quantity = clampi(_craft_quantity, 1, max_qty)
	else:
		_craft_quantity = 1

	_detail_title.text = name

	var meta_lines := []
	meta_lines.append("[color=#87CEEB]Skill Req:[/color] %d   [color=#87CEEB]Difficulty:[/color] %d   [color=#87CEEB]Success:[/color] %d%%" % [skill_req, difficulty, success_chance])
	# Audit #8 Layer 5 — quality odds bar
	var odds = recipe.get("quality_odds", {})
	if odds and typeof(odds) == TYPE_DICTIONARY and not odds.is_empty():
		var p = int(odds.get("poor", 0))
		var s = int(odds.get("standard", 0))
		var f = int(odds.get("fine", 0))
		var m = int(odds.get("masterwork", 0))
		meta_lines.append("[color=#FFFFFF]Poor:[/color] %d%%   [color=#00FF00]Standard:[/color] %d%%   [color=#0070DD]Fine:[/color] %d%%   [color=#A335EE]Masterwork:[/color] %d%%" % [p, s, f, m])
	# Audit #8 Layer 6 (v0.9.445) — sell-value preview from #9's rolling market avg.
	# 0 means no sales recorded yet — skip rendering rather than mislead with zero.
	var market_avg := int(recipe.get("avg_market_price", 0))
	if market_avg > 0:
		meta_lines.append("[color=#FFD700]Recent market avg:[/color] %d Valor [color=#888888](rolling)[/color]" % market_avg)
	var description := str(recipe.get("description", ""))
	if description != "":
		meta_lines.append("[color=#888888]%s[/color]" % description)
	_detail_meta.text = "\n".join(meta_lines)

	# Materials
	var mat_lines := []
	var materials = recipe.get("materials", {})
	for mat_id in materials.keys():
		var required = int(materials[mat_id]) * _craft_quantity
		var owned = _resolve_owned(mat_id)
		var mat_name = _material_display_name(mat_id)
		var color = "#00FF00" if owned >= required else "#FF4444"
		mat_lines.append("  [color=%s]%s: %d/%d[/color]" % [color, mat_name, owned, required])
	if mat_lines.size() > 0:
		_detail_materials.text = "[color=#87CEEB]Materials (x%d):[/color]\n%s" % [_craft_quantity, "\n".join(mat_lines)]
	else:
		_detail_materials.text = "[color=#888888](no materials needed)[/color]"

	# Quantity row
	_qty_row.visible = is_bulk and not is_locked and not is_specialist_gated
	_qty_label.text = str(_craft_quantity)
	_qty_minus.disabled = _craft_quantity <= 1
	_qty_plus.disabled = _craft_quantity >= max_qty
	_qty_max.disabled = _craft_quantity == max_qty

	# Craft button state
	if is_locked:
		_craft_button.text = "Locked (Lv%d required)" % skill_req
		_craft_button.disabled = true
	elif is_specialist_gated:
		_craft_button.text = "Specialist Job Required"
		_craft_button.disabled = true
	elif not can_craft:
		_craft_button.text = "Missing Materials"
		_craft_button.disabled = true
	else:
		_craft_button.text = "CRAFT %dx" % _craft_quantity if _craft_quantity > 1 else "CRAFT"
		_craft_button.disabled = false


func _show_detail_empty(empty: bool) -> void:
	if not _detail_empty:
		return
	_detail_empty.visible = empty
	_detail_title.visible = not empty
	_detail_meta.visible = not empty
	_detail_materials.visible = not empty
	_qty_row.visible = not empty and _qty_row.visible
	_craft_button.visible = not empty


func _resolve_owned(mat_id: String) -> int:
	if mat_id.begins_with("@"):
		if client_ref and client_ref.has_method("_count_group_materials"):
			return int(client_ref._count_group_materials(mat_id))
		return 0
	return int(_materials.get(mat_id, 0))


func _material_display_name(mat_id: String) -> String:
	if mat_id.begins_with("@"):
		if client_ref and client_ref.has_method("_get_group_material_label"):
			return client_ref._get_group_material_label(mat_id)
		return mat_id
	if client_ref and client_ref.has_method("_get_simple_material_name"):
		return client_ref._get_simple_material_name(mat_id)
	return mat_id.capitalize().replace("_", " ")


# === Internal callbacks ===

func _on_skill_chip_pressed(skill_id: String) -> void:
	# Re-pin selection in case user clicked the same chip
	for sk in _skill_chip_buttons.keys():
		_skill_chip_buttons[sk].button_pressed = (sk == skill_id)
	if skill_id != _current_skill:
		emit_signal("skill_changed", skill_id)


func _on_recipe_pressed(index: int) -> void:
	emit_signal("recipe_selected", index)


func _on_qty_minus_pressed() -> void:
	if _craft_quantity > 1:
		_craft_quantity -= 1
		_refresh_detail()
		emit_signal("quantity_changed", _craft_quantity)


func _on_qty_plus_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _recipes.size():
		return
	var max_qty := int(_recipes[_selected_index].get("max_craftable", 1))
	if _craft_quantity < max_qty:
		_craft_quantity += 1
		_refresh_detail()
		emit_signal("quantity_changed", _craft_quantity)


func _on_qty_max_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _recipes.size():
		return
	var max_qty := int(_recipes[_selected_index].get("max_craftable", 1))
	if max_qty > 1:
		_craft_quantity = max_qty
		_refresh_detail()
		emit_signal("quantity_changed", _craft_quantity)


func _on_craft_pressed() -> void:
	if _selected_index < 0:
		return
	emit_signal("craft_pressed", _selected_index, _craft_quantity)


func _on_close_pressed() -> void:
	emit_signal("close_requested")
