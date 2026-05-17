extends Control
class_name ClanVaultPanel

# Audit #14 Slice 6 — visual Clan Vault panel. Promotes v0.9.446's
# `/vault` chat-command MVP to a real UI surface. Two view modes:
#   "vault"   → list of clan vault items, each with Withdraw button.
#   "deposit" → list of player inventory items, each with Deposit button.
# Server pushes are received via refresh(); inventory snapshot is fed
# separately via set_inventory() so the picker always reflects the
# latest character_update.

signal close_requested
signal withdraw_requested(vault_index: int)
signal deposit_requested(inventory_slot: int)

const MAX_DESC_LEN: int = 80

var _root_panel: PanelContainer
var _vbox: VBoxContainer
var _body_container: VBoxContainer
var _status_label: RichTextLabel
var _tab_strip: HBoxContainer

var _vault_data: Dictionary = {}
var _inventory: Array = []
var _mode: String = "vault"   # "vault" or "deposit"

# Audit #15 v0.9.516 — reusable HelpPanel attached to the header ? Help button.
var _help_panel: HelpPanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(vault_data: Dictionary, inventory: Array) -> void:
	_mode = "vault"
	_inventory = inventory.duplicate(true) if inventory is Array else []
	refresh(vault_data)
	visible = true


func close() -> void:
	visible = false
	_set_status("")


func refresh(vault_data: Dictionary) -> void:
	_vault_data = vault_data.duplicate(true) if vault_data is Dictionary else {}
	_render_body()


func set_inventory(inventory: Array) -> void:
	"""Called when character_update arrives so the deposit picker reflects the
	latest inventory state without needing a fresh open()."""
	_inventory = inventory.duplicate(true) if inventory is Array else []
	if visible and _mode == "deposit":
		_render_body()


func show_action_result(success: bool, message: String) -> void:
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
	_root_panel.custom_minimum_size = Vector2(620, 0)
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

	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 8)
	_vbox.add_child(title_hbox)

	var title_label := Label.new()
	title_label.text = "Clan Vault"
	title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_label)

	# Audit #15 v0.9.516 — Help button.
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("clan_vault_panel", _help_panel)
	title_hbox.add_child(help_btn)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): close_requested.emit())
	title_hbox.add_child(close_btn)

	_tab_strip = HBoxContainer.new()
	_tab_strip.add_theme_constant_override("separation", 6)
	_vbox.add_child(_tab_strip)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.add_theme_font_size_override("normal_font_size", 12)
	_status_label.custom_minimum_size = Vector2(0, 20)
	_vbox.add_child(_status_label)

	_body_container = VBoxContainer.new()
	_body_container.add_theme_constant_override("separation", 4)
	_vbox.add_child(_body_container)


func _render_body() -> void:
	for child in _tab_strip.get_children():
		child.queue_free()
	for child in _body_container.get_children():
		child.queue_free()

	_tab_strip.add_child(_make_tab_button("Vault", "vault"))
	_tab_strip.add_child(_make_tab_button("Deposit", "deposit"))

	# Capacity header — same line for both modes so the player always sees N/30.
	var items: Array = _vault_data.get("items", [])
	var capacity := int(_vault_data.get("capacity", 30))
	var clan_name := String(_vault_data.get("clan_name", ""))
	var clan_tag := String(_vault_data.get("clan_tag", ""))
	var capacity_color: String = "#88FF88" if items.size() < capacity else "#FF8800"

	var header := RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.add_theme_font_size_override("normal_font_size", 13)
	header.custom_minimum_size = Vector2(0, 22)
	var tag_str: String = "[%s]" % clan_tag if clan_tag != "" else ""
	header.text = "[color=#A0A0A0]%s [color=#FFD700]%s[/color][/color]    [color=%s]%d / %d[/color]" % [clan_name, tag_str, capacity_color, items.size(), capacity]
	_body_container.add_child(header)

	if _mode == "vault":
		_render_vault_list(items)
	else:
		_render_deposit_list()


func _make_tab_button(label: String, mode: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120, 28)
	var sb := StyleBoxFlat.new()
	if mode == _mode:
		sb.bg_color = Color(0.20, 0.15, 0.30, 1)
		sb.border_color = Color(0.85, 0.70, 0.30, 1)
		btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	else:
		sb.bg_color = Color(0.10, 0.10, 0.14, 1)
		sb.border_color = Color(0.35, 0.30, 0.50, 1)
		btn.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_top = 4
	sb.content_margin_right = 8
	sb.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.pressed.connect(func(): _switch_mode(mode))
	return btn


func _switch_mode(mode: String) -> void:
	if mode == _mode:
		return
	_mode = mode
	_set_status("")
	_render_body()


func _render_vault_list(items: Array) -> void:
	if items.is_empty():
		var empty := RichTextLabel.new()
		empty.bbcode_enabled = true
		empty.fit_content = true
		empty.scroll_active = false
		empty.add_theme_font_size_override("normal_font_size", 13)
		empty.custom_minimum_size = Vector2(0, 22)
		empty.text = "[color=#888888]Vault is empty. Switch to the [color=#FFD700]Deposit[/color] tab to add items from your inventory.[/color]"
		_body_container.add_child(empty)
		return

	for i in range(items.size()):
		var row = _build_item_row(items[i], i, false)
		_body_container.add_child(row)


func _render_deposit_list() -> void:
	# Filter out empty slots — server expects valid 0-indexed slot.
	var filled_rows: Array = []
	for i in range(_inventory.size()):
		var item = _inventory[i]
		if item == null:
			continue
		if item is Dictionary and item.is_empty():
			continue
		filled_rows.append({"slot": i, "item": item})

	if filled_rows.is_empty():
		var empty := RichTextLabel.new()
		empty.bbcode_enabled = true
		empty.fit_content = true
		empty.scroll_active = false
		empty.add_theme_font_size_override("normal_font_size", 13)
		empty.custom_minimum_size = Vector2(0, 22)
		empty.text = "[color=#888888]Your inventory is empty.[/color]"
		_body_container.add_child(empty)
		return

	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.scroll_active = false
	hint.add_theme_font_size_override("normal_font_size", 11)
	hint.custom_minimum_size = Vector2(0, 18)
	hint.text = "[color=#888888]Pick an inventory item to deposit. Any clan member can withdraw later.[/color]"
	_body_container.add_child(hint)

	for entry in filled_rows:
		var slot = int(entry.slot)
		var item = entry.item
		var row = _build_item_row(item, slot, true)
		_body_container.add_child(row)


func _build_item_row(item: Dictionary, index: int, is_deposit: bool) -> Control:
	var iname: String = String(item.get("name", "?"))
	var itype: String = String(item.get("type", item.get("item_type", "")))
	var rarity: String = String(item.get("rarity", ""))
	var qty: int = int(item.get("quantity", 1))
	var rarity_color: String = _rarity_color(rarity)

	var row := PanelContainer.new()
	var row_sb := StyleBoxFlat.new()
	row_sb.bg_color = Color(0.08, 0.07, 0.12, 0.85)
	row_sb.border_color = Color(0.30, 0.25, 0.45, 1)
	row_sb.set_border_width_all(1)
	row_sb.set_corner_radius_all(4)
	row_sb.content_margin_left = 10
	row_sb.content_margin_top = 4
	row_sb.content_margin_right = 10
	row_sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", row_sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var idx_label := Label.new()
	idx_label.text = "%2d." % (index + 1)
	idx_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
	idx_label.custom_minimum_size = Vector2(34, 0)
	hbox.add_child(idx_label)

	var text_label := RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_size_override("normal_font_size", 13)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.custom_minimum_size = Vector2(0, 22)
	var qty_str: String = ""
	if qty > 1:
		qty_str = " [color=#AAAAAA]x%d[/color]" % qty
	var type_str: String = ""
	if itype != "":
		type_str = "  [color=#888888](%s)[/color]" % itype
	text_label.text = "[color=%s]%s[/color]%s%s" % [rarity_color, iname, qty_str, type_str]
	hbox.add_child(text_label)

	var action_btn := Button.new()
	action_btn.focus_mode = Control.FOCUS_NONE
	action_btn.custom_minimum_size = Vector2(96, 28)
	if is_deposit:
		action_btn.text = "Deposit"
		action_btn.add_theme_color_override("font_color", Color.html("#88FF88"))
		var captured_slot := index
		action_btn.pressed.connect(func(): deposit_requested.emit(captured_slot))
	else:
		action_btn.text = "Withdraw"
		action_btn.add_theme_color_override("font_color", Color.html("#FFD700"))
		var captured_index := index
		action_btn.pressed.connect(func(): withdraw_requested.emit(captured_index))
	hbox.add_child(action_btn)

	return row


func _rarity_color(rarity: String) -> String:
	match rarity.to_lower():
		"common":
			return "#FFFFFF"
		"uncommon":
			return "#1EFF00"
		"rare":
			return "#0070DD"
		"epic":
			return "#A335EE"
		"legendary":
			return "#FF8000"
		"mythic":
			return "#FF0080"
		_:
			return "#DDDDDD"
