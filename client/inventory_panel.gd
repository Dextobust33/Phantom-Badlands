extends Control
class_name InventoryPanel

signal close_requested
signal sort_requested
signal salvage_junk_requested
signal materials_requested
signal filter_changed(filter_id: String)
signal card_clicked(item: Dictionary, inventory_index: int)
signal card_double_clicked(item: Dictionary, inventory_index: int)
signal card_right_clicked(item: Dictionary, inventory_index: int, indices: Array, screen_pos: Vector2)
signal card_hovered(item: Dictionary, card)
signal card_unhovered
signal slot_clicked(slot_name: String, slot_kind: String, item: Dictionary)
signal slot_right_clicked(slot_name: String, slot_kind: String, item: Dictionary, screen_pos: Vector2)
signal slot_hovered(slot_name: String, slot_kind: String, item: Dictionary, slot_node)
signal slot_unhovered

const ItemCardScript = preload("res://client/item_card.gd")
const EquipSlotScript = preload("res://client/equip_slot.gd")

const FILTER_CHIPS := [
	{"id": "all", "label": "All"},
	{"id": "weapon", "label": "Weap"},
	{"id": "armor", "label": "Armor"},
	{"id": "consumable", "label": "Cons"},
	{"id": "tool", "label": "Tools"},
	{"id": "rune", "label": "Runes"},
	{"id": "egg", "label": "Eggs"},
]

const GEAR_SLOTS := ["helm", "amulet", "weapon", "shield", "armor", "ring", "boots"]
const TOOL_SLOTS := ["pickaxe", "axe", "sickle", "rod"]

var current_filter: String = "all"
var client_ref = null
var equip_slot_nodes: Dictionary = {}
var tool_slot_nodes: Dictionary = {}
var card_nodes: Array = []
var _filter_buttons: Dictionary = {}
var _selected_card_index: int = -1  # selection within visible cards array

var _root_panel: PanelContainer
var _capacity_label: Label
var _resources_label: RichTextLabel
var _bonus_label: RichTextLabel
var _filter_chips: HBoxContainer
var _paperdoll_grid: GridContainer
var _tools_grid: GridContainer
var _card_grid: HFlowContainer
var _empty_label: Label
var _status_label: RichTextLabel

# Hover tooltip + right-click context menu
var _tooltip: PanelContainer
var _tooltip_label: RichTextLabel
var _context_menu: PopupMenu
var _sort_menu: PopupMenu
var _sort_button: Button
# Cached subject of the currently-open context menu
var _ctx_kind: String = ""  # "card" | "slot"
var _ctx_item: Dictionary = {}
var _ctx_index: int = -1
var _ctx_indices: Array = []
var _ctx_slot_name: String = ""
var _ctx_slot_kind: String = ""

# Context-menu action ids
const CTX_INSPECT := 1
const CTX_USE := 2
const CTX_EQUIP := 3
const CTX_UNEQUIP := 4
const CTX_LOCK := 5
const CTX_DROP := 6

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_build_layout()
	visible = false

func set_client(client) -> void:
	client_ref = client

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

	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_color_override("font_color", Color(1, 0.84, 0))
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)

	_capacity_label = Label.new()
	_capacity_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_capacity_label.add_theme_font_size_override("font_size", 12)
	_capacity_label.text = "0/40"
	header.add_child(_capacity_label)

	_resources_label = RichTextLabel.new()
	_resources_label.bbcode_enabled = true
	_resources_label.fit_content = true
	_resources_label.scroll_active = false
	_resources_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resources_label.custom_minimum_size = Vector2(0, 20)
	_resources_label.add_theme_font_size_override("normal_font_size", 12)
	header.add_child(_resources_label)

	# Filter chips row
	_filter_chips = HBoxContainer.new()
	_filter_chips.add_theme_constant_override("separation", 4)
	root_vbox.add_child(_filter_chips)
	for chip in FILTER_CHIPS:
		var btn := Button.new()
		btn.text = chip["label"]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 24)
		btn.pressed.connect(_on_filter_pressed.bind(chip["id"]))
		_filter_chips.add_child(btn)
		_filter_buttons[chip["id"]] = btn
	_filter_buttons["all"].button_pressed = true

	# Body: paper-doll (left) + card grid (right)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_vbox.add_child(body)

	# Left side - paper-doll
	var pd_panel := _make_subpanel()
	pd_panel.custom_minimum_size = Vector2(380, 0)
	pd_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pd_panel.clip_contents = true
	body.add_child(pd_panel)

	var pd_scroll := ScrollContainer.new()
	pd_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pd_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pd_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pd_panel.add_child(pd_scroll)

	var pd_vbox := VBoxContainer.new()
	pd_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pd_vbox.add_theme_constant_override("separation", 4)
	pd_scroll.add_child(pd_vbox)

	var pd_title := Label.new()
	pd_title.text = "Equipped"
	pd_title.add_theme_color_override("font_color", Color(0, 1, 1))
	pd_title.add_theme_font_size_override("font_size", 13)
	pd_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pd_vbox.add_child(pd_title)

	_paperdoll_grid = GridContainer.new()
	_paperdoll_grid.columns = 2
	_paperdoll_grid.add_theme_constant_override("h_separation", 4)
	_paperdoll_grid.add_theme_constant_override("v_separation", 4)
	pd_vbox.add_child(_paperdoll_grid)

	for slot in GEAR_SLOTS:
		var slot_node = EquipSlotScript.new()
		slot_node.setup(slot, "gear")
		slot_node.client_ref = client_ref
		slot_node.slot_clicked.connect(_on_slot_clicked)
		slot_node.slot_right_clicked.connect(_on_slot_right_clicked)
		slot_node.slot_hovered.connect(_on_slot_hovered_signal)
		slot_node.slot_unhovered.connect(_on_slot_unhovered_signal)
		_paperdoll_grid.add_child(slot_node)
		equip_slot_nodes[slot] = slot_node

	var tools_title := Label.new()
	tools_title.text = "Tools"
	tools_title.add_theme_color_override("font_color", Color(0.6, 0.85, 0.2))
	tools_title.add_theme_font_size_override("font_size", 12)
	tools_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pd_vbox.add_child(tools_title)

	_tools_grid = GridContainer.new()
	_tools_grid.columns = 2
	_tools_grid.add_theme_constant_override("h_separation", 4)
	_tools_grid.add_theme_constant_override("v_separation", 4)
	pd_vbox.add_child(_tools_grid)

	for slot in TOOL_SLOTS:
		var slot_node = EquipSlotScript.new()
		slot_node.setup(slot, "tool")
		slot_node.client_ref = client_ref
		slot_node.slot_clicked.connect(_on_slot_clicked)
		slot_node.slot_right_clicked.connect(_on_slot_right_clicked)
		slot_node.slot_hovered.connect(_on_slot_hovered_signal)
		slot_node.slot_unhovered.connect(_on_slot_unhovered_signal)
		_tools_grid.add_child(slot_node)
		tool_slot_nodes[slot] = slot_node

	_bonus_label = RichTextLabel.new()
	_bonus_label.bbcode_enabled = true
	_bonus_label.fit_content = true
	_bonus_label.scroll_active = false
	_bonus_label.add_theme_font_size_override("normal_font_size", 11)
	_bonus_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bonus_label.custom_minimum_size = Vector2(0, 32)
	pd_vbox.add_child(_bonus_label)

	# Right side - card grid
	var grid_panel := _make_subpanel()
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_panel.add_child(scroll)

	_card_grid = HFlowContainer.new()
	_card_grid.add_theme_constant_override("h_separation", 6)
	_card_grid.add_theme_constant_override("v_separation", 6)
	_card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_card_grid)

	_empty_label = Label.new()
	_empty_label.text = "(no items match filter)"
	_empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_empty_label.add_theme_font_size_override("font_size", 12)
	_empty_label.visible = false
	_card_grid.add_child(_empty_label)

	# Action row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(action_row)

	_sort_button = _make_action_btn("Sort ▾", _on_sort_pressed)
	action_row.add_child(_sort_button)
	action_row.add_child(_make_action_btn("Salvage Junk", _on_salvage_pressed))
	action_row.add_child(_make_action_btn("Materials", _on_materials_pressed))

	# Transient feedback (e.g., "Used Minor Health Potion: +50 HP")
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

	# Hover tooltip — top_level so it can extend beyond the panel and across clipping bounds
	_tooltip = PanelContainer.new()
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.08, 0.06, 0.05, 0.97)
	tip_sb.border_color = Color(0.55, 0.45, 0.33, 1)
	tip_sb.set_border_width_all(2)
	tip_sb.set_corner_radius_all(5)
	tip_sb.content_margin_left = 8
	tip_sb.content_margin_top = 6
	tip_sb.content_margin_right = 8
	tip_sb.content_margin_bottom = 6
	_tooltip.add_theme_stylebox_override("panel", tip_sb)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.top_level = true
	_tooltip.visible = false
	_tooltip.z_index = 100
	add_child(_tooltip)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	_tooltip_label.custom_minimum_size = Vector2(280, 0)
	_tooltip.add_child(_tooltip_label)

	# Right-click context menu — items rebuilt on each open based on the subject
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	# Sort menu — fixed list, opens from the Sort button. Each entry's metadata is the
	# sort_by string the server expects.
	_sort_menu = PopupMenu.new()
	for entry in [
		{"label": "Level", "key": "level"},
		{"label": "Rarity", "key": "rarity"},
		{"label": "Slot", "key": "slot"},
		{"label": "ATK", "key": "atk"},
		{"label": "DEF", "key": "def"},
		{"label": "HP", "key": "hp"},
		{"label": "Speed", "key": "speed"},
		{"label": "WIT", "key": "wit"},
		{"label": "Mana", "key": "mana"},
	]:
		var idx := _sort_menu.item_count
		_sort_menu.add_item(entry["label"], idx)
		_sort_menu.set_item_metadata(idx, entry["key"])
	_sort_menu.id_pressed.connect(_on_sort_menu_id_pressed)
	add_child(_sort_menu)

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

func populate(character_data: Dictionary) -> void:
	if not is_inside_tree():
		return
	var inventory: Array = character_data.get("inventory", [])
	var equipped: Dictionary = character_data.get("equipped", {})
	var equipped_tools: Dictionary = character_data.get("equipped_tools", {})

	_capacity_label.text = "%d/40" % inventory.size()

	# Resources line
	if client_ref and client_ref.has_method("_get_resources_summary"):
		_resources_label.text = client_ref._get_resources_summary()
	else:
		_resources_label.text = ""

	# Paper-doll
	for slot in GEAR_SLOTS:
		var node = equip_slot_nodes.get(slot)
		if node:
			node.client_ref = client_ref
			node.set_item(equipped.get(slot, {}))
	for slot in TOOL_SLOTS:
		var node = tool_slot_nodes.get(slot)
		if node:
			node.client_ref = client_ref
			node.set_item(equipped_tools.get(slot, {}))

	# Total bonuses across all equipped items, color-coded per stat
	if client_ref and client_ref.has_method("get_equipped_totals_bbcode"):
		_bonus_label.text = client_ref.get_equipped_totals_bbcode(equipped)
	else:
		_bonus_label.text = ""

	_rebuild_cards(inventory)

func _rebuild_cards(inventory: Array) -> void:
	# Clear existing card nodes
	for c in card_nodes:
		if is_instance_valid(c):
			c.queue_free()
	card_nodes.clear()

	# Partition into equipment, tools, consumables/runes (grouped by name)
	var equipment_entries: Array = []
	var tool_entries: Array = []
	var consumable_groups: Dictionary = {}
	var consumable_order: Array = []

	for idx in range(inventory.size()):
		var itm = inventory[idx]
		var t: String = itm.get("type", "")
		if itm.get("is_consumable", false) or t == "rune":
			var cname: String = itm.get("name", "")
			var qty: int = int(itm.get("quantity", 1))
			if consumable_groups.has(cname):
				consumable_groups[cname]["count"] += qty
				consumable_groups[cname]["indices"].append(idx)
			else:
				consumable_groups[cname] = {
					"index": idx, "item": itm, "count": qty, "indices": [idx]
				}
				consumable_order.append(cname)
		elif t == "tool":
			tool_entries.append({"index": idx, "item": itm, "count": 1, "indices": [idx]})
		else:
			equipment_entries.append({"index": idx, "item": itm, "count": int(itm.get("quantity", 1)), "indices": [idx]})

	var ordered: Array = []
	ordered.append_array(equipment_entries)
	ordered.append_array(tool_entries)
	for cname in consumable_order:
		ordered.append(consumable_groups[cname])

	# Apply filter
	var visible_count := 0
	for entry in ordered:
		var item: Dictionary = entry["item"]
		if not _matches_filter(item):
			continue
		var card = ItemCardScript.new()
		card.client_ref = client_ref
		_card_grid.add_child(card)
		card.set_item(item, int(entry["index"]), int(entry["count"]), entry["indices"])
		card.card_clicked.connect(_on_card_clicked)
		card.card_double_clicked.connect(_on_card_double_clicked)
		card.card_right_clicked.connect(_on_card_right_clicked)
		card.card_hovered.connect(_on_card_hovered_signal)
		card.card_unhovered.connect(_on_card_unhovered_signal)
		card_nodes.append(card)
		visible_count += 1

	# Empty state
	if visible_count == 0:
		_empty_label.visible = true
		# Move to end so it sits in the flow
		_card_grid.move_child(_empty_label, _card_grid.get_child_count() - 1)
	else:
		_empty_label.visible = false

func _matches_filter(item: Dictionary) -> bool:
	if current_filter == "all":
		return true
	var t: String = item.get("type", "")
	match current_filter:
		"weapon":
			return "weapon" in t
		"armor":
			return ("armor" in t) or ("helm" in t) or ("shield" in t) or ("boots" in t) or ("ring" in t) or ("amulet" in t)
		"consumable":
			return item.get("is_consumable", false)
		"tool":
			return t == "tool"
		"rune":
			return t == "rune"
		"egg":
			return t == "egg" or t.begins_with("egg_")
	return true

func set_filter(id: String) -> void:
	current_filter = id
	for fid in _filter_buttons.keys():
		_filter_buttons[fid].button_pressed = (fid == id)

# === Signal handlers ===

func _on_filter_pressed(id: String) -> void:
	current_filter = id
	for fid in _filter_buttons.keys():
		_filter_buttons[fid].button_pressed = (fid == id)
	emit_signal("filter_changed", id)
	if client_ref and "character_data" in client_ref:
		_rebuild_cards(client_ref.character_data.get("inventory", []))

func _on_sort_pressed() -> void:
	# Pop the sort menu just below the Sort button so the user gets a native menu
	# instead of routing through the legacy paginated text submenu.
	if _sort_menu == null or _sort_button == null:
		emit_signal("sort_requested")
		return
	_hide_tooltip()
	var btn_rect := Rect2(_sort_button.global_position, _sort_button.size)
	_sort_menu.position = Vector2i(btn_rect.position.x, btn_rect.position.y + btn_rect.size.y + 2)
	_sort_menu.popup()

func _on_sort_menu_id_pressed(id: int) -> void:
	if client_ref == null or not client_ref.has_method("_panel_sort_inventory"):
		return
	var key = _sort_menu.get_item_metadata(id)
	if key == null:
		return
	client_ref._panel_sort_inventory(str(key))

func _on_salvage_pressed() -> void:
	emit_signal("salvage_junk_requested")

func _on_materials_pressed() -> void:
	emit_signal("materials_requested")

func _on_close_pressed() -> void:
	emit_signal("close_requested")

func _on_card_clicked(card, _event) -> void:
	emit_signal("card_clicked", card.item_data, card.inventory_index)

func _on_card_double_clicked(card) -> void:
	emit_signal("card_double_clicked", card.item_data, card.inventory_index)

func _on_card_right_clicked(card, screen_pos: Vector2) -> void:
	_open_context_menu_for_card(card, screen_pos)
	emit_signal("card_right_clicked", card.item_data, card.inventory_index, card.grouped_indices, screen_pos)

func _on_card_hovered_signal(card) -> void:
	_show_tooltip_for(card.item_data, card)
	emit_signal("card_hovered", card.item_data, card)

func _on_card_unhovered_signal(_card) -> void:
	_hide_tooltip()
	emit_signal("card_unhovered")

func _on_slot_clicked(slot) -> void:
	emit_signal("slot_clicked", slot.slot_name, slot.slot_kind, slot.item_data)

func _on_slot_right_clicked(slot, screen_pos: Vector2) -> void:
	_open_context_menu_for_slot(slot, screen_pos)
	emit_signal("slot_right_clicked", slot.slot_name, slot.slot_kind, slot.item_data, screen_pos)

func _on_slot_hovered_signal(slot) -> void:
	if slot.has_item:
		_show_tooltip_for(slot.item_data, slot)
	emit_signal("slot_hovered", slot.slot_name, slot.slot_kind, slot.item_data, slot)

func _on_slot_unhovered_signal(_slot) -> void:
	_hide_tooltip()
	emit_signal("slot_unhovered")

# === Tooltip ===

func _show_tooltip_for(item: Dictionary, anchor_node: Control) -> void:
	if item.is_empty():
		return
	if client_ref == null or not client_ref.has_method("format_item_tooltip_bbcode"):
		return
	_tooltip_label.text = client_ref.format_item_tooltip_bbcode(item)
	# Reset size so the container shrinks back to fit shorter content (otherwise it keeps
	# the height of whatever previous, taller tooltip set it).
	_tooltip.size = Vector2.ZERO
	_tooltip.visible = true
	# Position next to the anchor — prefer to its right; fall back to left if that overflows
	await get_tree().process_frame  # let the tooltip resize to fit content
	if not is_instance_valid(_tooltip) or not _tooltip.visible:
		return
	_tooltip.reset_size()
	var vp := get_viewport_rect().size
	var anchor_rect := Rect2(anchor_node.global_position, anchor_node.size)
	var tip_size := _tooltip.size
	var pos := Vector2(anchor_rect.position.x + anchor_rect.size.x + 6, anchor_rect.position.y)
	if pos.x + tip_size.x > vp.x - 4:
		pos.x = max(4.0, anchor_rect.position.x - tip_size.x - 6)
	if pos.y + tip_size.y > vp.y - 4:
		pos.y = max(4.0, vp.y - tip_size.y - 4)
	_tooltip.global_position = pos

func _hide_tooltip() -> void:
	if _tooltip:
		_tooltip.visible = false

# === Right-click context menu ===

func _open_context_menu_for_card(card, screen_pos: Vector2) -> void:
	_hide_tooltip()
	_ctx_kind = "card"
	_ctx_item = card.item_data
	_ctx_index = card.inventory_index
	_ctx_indices = card.grouped_indices
	_ctx_slot_name = ""
	_ctx_slot_kind = ""
	_populate_context_menu()
	_context_menu.position = Vector2i(screen_pos)
	_context_menu.popup()

func _open_context_menu_for_slot(slot, screen_pos: Vector2) -> void:
	_hide_tooltip()
	if not slot.has_item:
		return
	_ctx_kind = "slot"
	_ctx_item = slot.item_data
	_ctx_index = -1
	_ctx_indices = []
	_ctx_slot_name = slot.slot_name
	_ctx_slot_kind = slot.slot_kind
	_populate_context_menu()
	_context_menu.position = Vector2i(screen_pos)
	_context_menu.popup()

func _populate_context_menu() -> void:
	_context_menu.clear()
	# Inspect — always available
	_context_menu.add_item("Inspect", CTX_INSPECT)
	if _ctx_kind == "slot":
		# Equipped item: only Inspect + Unequip
		_context_menu.add_item("Unequip", CTX_UNEQUIP)
		return
	# Backpack item — branch on type
	var t: String = _ctx_item.get("type", "")
	var is_consumable = _ctx_item.get("is_consumable", false) or t == "consumable"
	var is_rune = t == "rune"
	var is_tool = t == "tool"
	var is_egg = t == "egg" or t.begins_with("egg_")
	var is_structure = t == "structure"
	var equippable_slot = ""
	if client_ref and client_ref.has_method("_get_slot_for_item_type"):
		equippable_slot = client_ref._get_slot_for_item_type(t)

	if is_consumable or is_rune:
		_context_menu.add_item("Use", CTX_USE)
	if equippable_slot != "" or is_tool:
		_context_menu.add_item("Equip", CTX_EQUIP)
	# Lock toggle — never on tools/eggs/structures (they have their own gating)
	if not is_egg and not is_structure:
		var lock_label = "Unlock" if _ctx_item.get("locked", false) else "Lock"
		_context_menu.add_item(lock_label, CTX_LOCK)
	# Drop — never available on locked items
	if not _ctx_item.get("locked", false):
		_context_menu.add_item("Drop", CTX_DROP)

# === Panel-level drag drop fallback ===
# Dropping a slot anywhere on the panel that isn't a slot itself = unequip.
# Cards also accept slot drops via their own override; this catches the
# empty-grid-space case (and any non-slot child without its own handler).

func _can_drop_data(_at_position: Vector2, data) -> bool:
	return data is Dictionary and data.get("source", "") == "slot"

func _drop_data(_at_position: Vector2, data) -> void:
	if not (data is Dictionary) or data.get("source", "") != "slot":
		return
	if client_ref and client_ref.has_method("_panel_unequip_slot"):
		client_ref._panel_unequip_slot(str(data.get("slot_name", "")), str(data.get("slot_kind", "")))

func _on_context_menu_id_pressed(id: int) -> void:
	if client_ref == null:
		return
	match id:
		CTX_INSPECT:
			if client_ref.has_method("_panel_inspect_item"):
				client_ref._panel_inspect_item(_ctx_item)
		CTX_USE:
			if client_ref.has_method("_panel_use_item"):
				client_ref._panel_use_item(_ctx_index)
		CTX_EQUIP:
			if client_ref.has_method("_panel_equip_item"):
				client_ref._panel_equip_item(_ctx_index, _ctx_item)
		CTX_UNEQUIP:
			if client_ref.has_method("_panel_unequip_slot"):
				client_ref._panel_unequip_slot(_ctx_slot_name, _ctx_slot_kind)
		CTX_LOCK:
			if client_ref.has_method("_panel_toggle_lock"):
				client_ref._panel_toggle_lock(_ctx_index)
		CTX_DROP:
			if client_ref.has_method("_panel_drop_item"):
				client_ref._panel_drop_item(_ctx_index, _ctx_item)
