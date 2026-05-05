extends Control
class_name SanctuaryPanel

# Tabbed panel for the two most-frequented Sanctuary sub-modes:
# - Storage: list of items, click row → context menu (Withdraw / Register / Discard)
# - Upgrades: 3 page sub-tabs (Base / Combat / Stats), each upgrade as a card
#   with Buy button + cost in Baddie Points.
# The walkable map view in client.gd stays as-is and remains the navigation
# surface; this panel takes over only when house_mode is "storage" or "upgrades".

signal close_requested
signal tab_changed(tab_id: String)
signal storage_withdraw_toggled(item_index: int)
signal storage_register_requested(item_index: int)
signal storage_discard_requested(item_index: int)
signal storage_withdraw_confirm_pressed
signal storage_withdraw_clear_pressed
signal upgrade_buy_pressed(upgrade_id: String)
signal upgrade_page_changed(page_index: int)

const TAB_STORAGE := "storage"
const TAB_UPGRADES := "upgrades"

const UPGRADE_PAGES := [
	{"label": "Base", "ids": ["storage_slots", "companion_slots", "kennel_capacity", "egg_slots", "post_slots", "flee_chance", "starting_gold", "xp_bonus", "gathering_bonus"]},
	{"label": "Combat", "ids": ["hp_bonus", "resource_max", "resource_regen"]},
	{"label": "Stats", "ids": ["str_bonus", "con_bonus", "dex_bonus", "int_bonus", "wis_bonus", "wits_bonus"]},
]

var client_ref = null

var _current_tab: String = TAB_STORAGE
var _items: Array = []
var _capacity: int = 0
var _withdraw_indices: Array = []
var _pending_withdraw_indices: Array = []
var _selected_storage_index: int = -1
var _baddie_points: int = 0
var _upgrades: Dictionary = {}
var _upgrade_costs: Dictionary = {}
var _upgrade_page: int = 0

var _root_panel: PanelContainer
var _title_label: Label
var _bp_label: RichTextLabel
var _tab_storage_btn: Button
var _tab_upgrades_btn: Button

# Storage tab nodes
var _storage_tab: VBoxContainer
var _storage_capacity_label: RichTextLabel
var _storage_list_vbox: VBoxContainer
var _storage_actions_row: HBoxContainer
var _withdraw_confirm_btn: Button
var _withdraw_clear_btn: Button
var _storage_empty_label: Label

# Upgrades tab nodes
var _upgrades_tab: VBoxContainer
var _upgrade_page_row: HBoxContainer
var _upgrade_page_buttons: Array = []
var _upgrade_grid: HFlowContainer

# Storage right-click menu
var _ctx_menu: PopupMenu
var _ctx_item_index: int = -1
const CTX_WITHDRAW := 1
const CTX_REGISTER := 2
const CTX_DISCARD := 3


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
	_title_label.text = "Sanctuary"
	_title_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_title_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_title_label)

	_bp_label = RichTextLabel.new()
	_bp_label.bbcode_enabled = true
	_bp_label.fit_content = true
	_bp_label.scroll_active = false
	_bp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bp_label.custom_minimum_size = Vector2(0, 22)
	_bp_label.add_theme_font_size_override("normal_font_size", 14)
	header.add_child(_bp_label)

	# Tabs
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(tab_row)

	_tab_storage_btn = _make_tab_button("Storage", _on_tab_storage_pressed)
	_tab_upgrades_btn = _make_tab_button("Upgrades", _on_tab_upgrades_pressed)
	tab_row.add_child(_tab_storage_btn)
	tab_row.add_child(_tab_upgrades_btn)

	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_spacer)

	# Storage tab body
	_storage_tab = VBoxContainer.new()
	_storage_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_storage_tab.add_theme_constant_override("separation", 6)
	root_vbox.add_child(_storage_tab)

	_storage_capacity_label = RichTextLabel.new()
	_storage_capacity_label.bbcode_enabled = true
	_storage_capacity_label.fit_content = true
	_storage_capacity_label.scroll_active = false
	_storage_capacity_label.add_theme_font_size_override("normal_font_size", 13)
	_storage_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_tab.add_child(_storage_capacity_label)

	var storage_panel := _make_subpanel()
	storage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_storage_tab.add_child(storage_panel)

	var storage_scroll := ScrollContainer.new()
	storage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	storage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	storage_panel.add_child(storage_scroll)

	_storage_list_vbox = VBoxContainer.new()
	_storage_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_list_vbox.add_theme_constant_override("separation", 2)
	storage_scroll.add_child(_storage_list_vbox)

	_storage_empty_label = Label.new()
	_storage_empty_label.text = "Storage is empty. Use Home Stones to send items here."
	_storage_empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_storage_empty_label.add_theme_font_size_override("font_size", 13)
	_storage_empty_label.visible = false
	_storage_list_vbox.add_child(_storage_empty_label)

	_storage_actions_row = HBoxContainer.new()
	_storage_actions_row.add_theme_constant_override("separation", 8)
	_storage_tab.add_child(_storage_actions_row)

	_withdraw_confirm_btn = _make_action_btn("Confirm Withdraw", _on_withdraw_confirm_pressed)
	_storage_actions_row.add_child(_withdraw_confirm_btn)

	_withdraw_clear_btn = _make_action_btn("Clear Withdraw", _on_withdraw_clear_pressed)
	_storage_actions_row.add_child(_withdraw_clear_btn)

	var storage_spacer := Control.new()
	storage_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_actions_row.add_child(storage_spacer)

	var storage_hint := Label.new()
	storage_hint.text = "Right-click an item for actions"
	storage_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	storage_hint.add_theme_font_size_override("font_size", 12)
	_storage_actions_row.add_child(storage_hint)

	# Upgrades tab body
	_upgrades_tab = VBoxContainer.new()
	_upgrades_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrades_tab.add_theme_constant_override("separation", 6)
	root_vbox.add_child(_upgrades_tab)

	_upgrade_page_row = HBoxContainer.new()
	_upgrade_page_row.add_theme_constant_override("separation", 4)
	_upgrades_tab.add_child(_upgrade_page_row)
	for i in range(UPGRADE_PAGES.size()):
		var btn := Button.new()
		btn.text = UPGRADE_PAGES[i]["label"]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		btn.custom_minimum_size = Vector2(110, 28)
		btn.pressed.connect(_on_upgrade_page_pressed.bind(i))
		_upgrade_page_row.add_child(btn)
		_upgrade_page_buttons.append(btn)

	var up_panel := _make_subpanel()
	up_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrades_tab.add_child(up_panel)

	var up_scroll := ScrollContainer.new()
	up_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	up_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	up_panel.add_child(up_scroll)

	_upgrade_grid = HFlowContainer.new()
	_upgrade_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_grid.add_theme_constant_override("h_separation", 6)
	_upgrade_grid.add_theme_constant_override("v_separation", 6)
	up_scroll.add_child(_upgrade_grid)

	# Bottom action row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(action_row)

	var action_spacer := Control.new()
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(action_spacer)

	action_row.add_child(_make_action_btn("Close (Space)", _on_close_pressed))

	# Right-click menu
	_ctx_menu = PopupMenu.new()
	_ctx_menu.id_pressed.connect(_on_ctx_menu_id_pressed)
	add_child(_ctx_menu)

	_set_tab(TAB_STORAGE)
	_update_tab_styles()


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
	b.custom_minimum_size = Vector2(0, 30)
	b.pressed.connect(callback)
	return b


func _make_tab_button(label: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(120, 32)
	b.pressed.connect(callback)
	return b


# === Public API ===

func populate_storage(items: Array, capacity: int, baddie_points: int, withdraw_indices: Array, pending_withdraw_indices: Array) -> void:
	if not is_inside_tree():
		return
	_current_tab = TAB_STORAGE
	_items = items
	_capacity = capacity
	_baddie_points = baddie_points
	_withdraw_indices = withdraw_indices
	_pending_withdraw_indices = pending_withdraw_indices
	_set_tab(TAB_STORAGE)
	_update_header()
	_update_tab_styles()
	_rebuild_storage_list()


func populate_upgrades(upgrades: Dictionary, upgrade_costs: Dictionary, baddie_points: int, page_index: int) -> void:
	if not is_inside_tree():
		return
	_current_tab = TAB_UPGRADES
	_upgrades = upgrades
	_upgrade_costs = upgrade_costs
	_baddie_points = baddie_points
	_upgrade_page = clampi(page_index, 0, UPGRADE_PAGES.size() - 1)
	_set_tab(TAB_UPGRADES)
	_update_header()
	_update_tab_styles()
	_update_upgrade_page_styles()
	_rebuild_upgrade_grid()


# === Internal rendering ===

func _set_tab(tab: String) -> void:
	_storage_tab.visible = (tab == TAB_STORAGE)
	_upgrades_tab.visible = (tab == TAB_UPGRADES)


func _update_header() -> void:
	if _current_tab == TAB_STORAGE:
		_title_label.text = "Sanctuary — Storage"
	else:
		_title_label.text = "Sanctuary — Upgrades"
	_bp_label.text = "[color=#FF6600]Baddie Points: %s[/color]" % _format_number(_baddie_points)


func _update_tab_styles() -> void:
	_tab_storage_btn.button_pressed = (_current_tab == TAB_STORAGE)
	_tab_upgrades_btn.button_pressed = (_current_tab == TAB_UPGRADES)


func _update_upgrade_page_styles() -> void:
	for i in range(_upgrade_page_buttons.size()):
		_upgrade_page_buttons[i].button_pressed = (i == _upgrade_page)


func _rebuild_storage_list() -> void:
	for child in _storage_list_vbox.get_children():
		if child == _storage_empty_label:
			continue
		child.queue_free()

	_storage_capacity_label.text = "[color=#AAAAAA]Capacity:[/color] %d / %d" % [_items.size(), _capacity]

	if _items.is_empty():
		_storage_empty_label.visible = true
		_withdraw_confirm_btn.disabled = true
		_withdraw_clear_btn.disabled = true
		return
	_storage_empty_label.visible = false

	for i in range(_items.size()):
		var row := _make_storage_row(_items[i], i)
		_storage_list_vbox.add_child(row)

	# Withdraw buttons enabled only when there are queued items
	var has_queue := _withdraw_indices.size() > 0
	_withdraw_confirm_btn.disabled = not has_queue
	_withdraw_clear_btn.disabled = not has_queue


func _make_storage_row(item: Dictionary, index: int) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 13)

	var name = str(item.get("name", "Unknown"))
	var rarity = str(item.get("rarity", "common"))
	var rarity_color = _rarity_color(rarity)
	var level = int(item.get("level", 1))
	var is_companion = item.get("type") == "stored_companion"
	var variant_tag = ""
	if is_companion:
		var variant = str(item.get("variant", "Normal"))
		variant_tag = "  (%s)" % variant

	var status_tag := ""
	if index in _withdraw_indices:
		status_tag = "  [WITHDRAW]"
	elif index in _pending_withdraw_indices:
		status_tag = "  [PENDING]"

	btn.text = "%s%s   Lv %d%s" % [name, variant_tag, level, status_tag]
	btn.add_theme_color_override("font_color", rarity_color)

	btn.gui_input.connect(_on_storage_row_input.bind(index))
	return btn


func _on_storage_row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_open_storage_ctx_menu(index, event.global_position)


func _open_storage_ctx_menu(index: int, screen_pos: Vector2) -> void:
	if index < 0 or index >= _items.size():
		return
	_ctx_item_index = index
	_ctx_menu.clear()
	var item = _items[index]
	var is_companion = item.get("type") == "stored_companion"

	if index in _withdraw_indices:
		_ctx_menu.add_item("Cancel Withdraw", CTX_WITHDRAW)
	elif index in _pending_withdraw_indices:
		# Already pending, show greyed-out hint
		var info_idx = _ctx_menu.get_item_count()
		_ctx_menu.add_item("Pending withdraw — choose at character select", CTX_WITHDRAW)
		_ctx_menu.set_item_disabled(info_idx, true)
	else:
		_ctx_menu.add_item("Mark for Withdraw", CTX_WITHDRAW)

	if is_companion:
		_ctx_menu.add_item("Register as Companion", CTX_REGISTER)

	_ctx_menu.add_separator()
	_ctx_menu.add_item("Discard...", CTX_DISCARD)

	_ctx_menu.position = Vector2i(screen_pos)
	_ctx_menu.popup()


func _on_ctx_menu_id_pressed(id: int) -> void:
	if _ctx_item_index < 0:
		return
	match id:
		CTX_WITHDRAW:
			emit_signal("storage_withdraw_toggled", _ctx_item_index)
		CTX_REGISTER:
			emit_signal("storage_register_requested", _ctx_item_index)
		CTX_DISCARD:
			emit_signal("storage_discard_requested", _ctx_item_index)
	_ctx_item_index = -1


func _rebuild_upgrade_grid() -> void:
	for child in _upgrade_grid.get_children():
		child.queue_free()

	var ids: Array = UPGRADE_PAGES[_upgrade_page]["ids"]
	for upgrade_id in ids:
		var card := _make_upgrade_card(str(upgrade_id))
		_upgrade_grid.add_child(card)


func _make_upgrade_card(upgrade_id: String) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.95)
	sb.border_color = Color(0.4, 0.34, 0.25, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_top = 6
	sb.content_margin_right = 8
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(280, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	var info: Dictionary = {}
	if client_ref and client_ref.has_method("_get_house_upgrade_display"):
		info = client_ref._get_house_upgrade_display(upgrade_id)
	if info.is_empty():
		info = {"name": upgrade_id.capitalize(), "desc": ""}

	var current_level: int = int(_upgrades.get(upgrade_id, 0))
	var def: Dictionary = _upgrade_costs.get(upgrade_id, {})
	var max_level: int = int(def.get("max", 1))
	var costs: Array = def.get("costs", [])
	var maxed := current_level >= max_level
	var next_cost: int = 0
	var can_afford := false
	if not maxed and current_level < costs.size():
		next_cost = int(costs[current_level])
		can_afford = _baddie_points >= next_cost

	var name_lbl := RichTextLabel.new()
	name_lbl.bbcode_enabled = true
	name_lbl.fit_content = true
	name_lbl.scroll_active = false
	name_lbl.add_theme_font_size_override("normal_font_size", 14)
	name_lbl.text = "[color=#FFD700]%s[/color]  [color=#AAAAAA]Lv %d / %d[/color]" % [str(info.get("name", upgrade_id)), current_level, max_level]
	vbox.add_child(name_lbl)

	var desc_lbl := RichTextLabel.new()
	desc_lbl.bbcode_enabled = true
	desc_lbl.fit_content = true
	desc_lbl.scroll_active = false
	desc_lbl.add_theme_font_size_override("normal_font_size", 12)
	var effect_text := ""
	if client_ref and client_ref.has_method("_get_upgrade_effect_text"):
		var effect_value: int = int(def.get("effect", 0)) * current_level
		effect_text = str(client_ref._get_upgrade_effect_text(upgrade_id, effect_value))
	desc_lbl.text = "[color=#AAAAAA]%s[/color]" % str(info.get("desc", ""))
	if effect_text != "":
		desc_lbl.text += "\n[color=#888888]Current: %s[/color]" % effect_text
	vbox.add_child(desc_lbl)

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(0, 32)
	if maxed:
		btn.text = "MAXED"
		btn.disabled = true
		btn.add_theme_color_override("font_color", Color(0, 1, 0))
	elif not can_afford:
		btn.text = "Buy — %s BP" % _format_number(next_cost)
		btn.disabled = true
		btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	else:
		btn.text = "Buy — %s BP" % _format_number(next_cost)
		btn.disabled = false
		btn.add_theme_color_override("font_color", Color(0, 1, 0))
	btn.pressed.connect(_on_upgrade_buy_pressed.bind(upgrade_id))
	vbox.add_child(btn)

	return card


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(1, 1, 1)
		"uncommon": return Color(0.12, 1, 0)
		"rare": return Color(0, 0.44, 0.87)
		"epic": return Color(0.64, 0.21, 0.93)
		"legendary": return Color(1, 0.5, 0)
		_: return Color(1, 1, 1)


func _format_number(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	var i := s.length()
	while i > 3:
		out = "," + s.substr(i - 3, 3) + out
		i -= 3
	out = s.substr(0, i) + out
	if n < 0:
		out = "-" + out
	return out


# === Internal callbacks ===

func _on_tab_storage_pressed() -> void:
	if _current_tab == TAB_STORAGE:
		_tab_storage_btn.button_pressed = true
		return
	emit_signal("tab_changed", TAB_STORAGE)


func _on_tab_upgrades_pressed() -> void:
	if _current_tab == TAB_UPGRADES:
		_tab_upgrades_btn.button_pressed = true
		return
	emit_signal("tab_changed", TAB_UPGRADES)


func _on_upgrade_page_pressed(index: int) -> void:
	if index == _upgrade_page:
		_upgrade_page_buttons[index].button_pressed = true
		return
	emit_signal("upgrade_page_changed", index)


func _on_upgrade_buy_pressed(upgrade_id: String) -> void:
	emit_signal("upgrade_buy_pressed", upgrade_id)


func _on_withdraw_confirm_pressed() -> void:
	emit_signal("storage_withdraw_confirm_pressed")


func _on_withdraw_clear_pressed() -> void:
	emit_signal("storage_withdraw_clear_pressed")


func _on_close_pressed() -> void:
	emit_signal("close_requested")
