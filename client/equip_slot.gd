extends PanelContainer
class_name EquipSlot

signal slot_clicked(slot: EquipSlot)
signal slot_right_clicked(slot: EquipSlot, screen_pos: Vector2)
signal slot_hovered(slot: EquipSlot)
signal slot_unhovered(slot: EquipSlot)

const SLOT_WIDTH := 175
const SLOT_HEIGHT := 78

const TYPE_LETTERS := {
	"weapon": "W", "armor": "A", "helm": "H", "shield": "S",
	"boots": "B", "ring": "R", "amulet": "N",
	"pickaxe": "P", "axe": "X", "sickle": "K", "rod": "F",
}
const TYPE_BG_COLORS := {
	"weapon": Color(0.55, 0.15, 0.15), "armor": Color(0.18, 0.35, 0.55),
	"helm": Color(0.18, 0.35, 0.55), "shield": Color(0.18, 0.35, 0.55),
	"boots": Color(0.18, 0.35, 0.55), "ring": Color(0.55, 0.4, 0.1),
	"amulet": Color(0.55, 0.4, 0.1),
	"pickaxe": Color(0.35, 0.25, 0.12), "axe": Color(0.35, 0.25, 0.12),
	"sickle": Color(0.35, 0.25, 0.12), "rod": Color(0.35, 0.25, 0.12),
}

var slot_name: String = ""
var slot_kind: String = "gear"  # "gear" or "tool"
var item_data: Dictionary = {}
var has_item: bool = false
var _hover: bool = false
var _stylebox: StyleBoxFlat

var _icon_rect: ColorRect
var _type_letter: Label
var _slot_label: Label
var _name_label: Label
var _info_label: RichTextLabel

var client_ref = null

func setup(s_name: String, kind: String) -> void:
	slot_name = s_name
	slot_kind = kind

func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_WIDTH, SLOT_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_visuals()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	_render()

func _build_visuals() -> void:
	_stylebox = StyleBoxFlat.new()
	_stylebox.bg_color = Color(0.06, 0.05, 0.04, 0.85)
	_stylebox.border_color = Color(0.4, 0.34, 0.25, 0.7)
	_stylebox.set_border_width_all(1)
	_stylebox.set_corner_radius_all(3)
	_stylebox.content_margin_left = 4
	_stylebox.content_margin_top = 3
	_stylebox.content_margin_right = 4
	_stylebox.content_margin_bottom = 3
	add_theme_stylebox_override("panel", _stylebox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(24, 24)
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_container)

	_icon_rect = ColorRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.color = Color(0.15, 0.13, 0.10)
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(_icon_rect)

	_type_letter = Label.new()
	_type_letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_type_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_type_letter.add_theme_font_size_override("font_size", 13)
	_type_letter.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_type_letter.add_theme_color_override("font_outline_color", Color.BLACK)
	_type_letter.add_theme_constant_override("outline_size", 2)
	_type_letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(_type_letter)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 1)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	_slot_label = Label.new()
	_slot_label.add_theme_font_size_override("font_size", 10)
	_slot_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_slot_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_label)

	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.scroll_active = false
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("normal_font_size", 11)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(_info_label)

func set_item(item) -> void:
	if item is Dictionary and not item.is_empty():
		item_data = item
		has_item = true
	else:
		item_data = {}
		has_item = false
	if is_inside_tree():
		_render()

func _render() -> void:
	_icon_rect.color = TYPE_BG_COLORS.get(slot_name, Color(0.15, 0.13, 0.10))
	_type_letter.text = TYPE_LETTERS.get(slot_name, "?")

	var slot_display := slot_name.capitalize()
	if slot_kind == "gear" and client_ref and client_ref.has_method("_get_themed_slot_name"):
		var cls := ""
		if "character_data" in client_ref:
			cls = client_ref.character_data.get("class", "")
		slot_display = client_ref._get_themed_slot_name(slot_name, cls)
	_slot_label.text = slot_display

	if not has_item:
		_name_label.text = "(empty)"
		_name_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		_info_label.text = ""
		_icon_rect.color = _icon_rect.color * 0.4
		_type_letter.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
		return

	_type_letter.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	var rarity: String = item_data.get("rarity", "common")
	var rarity_hex := _rarity_color_hex(rarity)
	var name_str: String = item_data.get("name", "?")
	if slot_kind == "gear" and client_ref and client_ref.has_method("_get_themed_item_name"):
		name_str = client_ref._get_themed_item_name(item_data, "")
	_name_label.text = name_str
	_name_label.add_theme_color_override("font_color", Color(rarity_hex))

	var info_bb := ""
	if slot_kind == "tool":
		var dur := int(item_data.get("durability", 0))
		var maxd := int(item_data.get("max_durability", 1))
		var pct := 0
		if maxd > 0:
			pct = int(float(dur) / float(maxd) * 100.0)
		var dur_color := "#00FF00"
		if pct <= 50:
			dur_color = "#FFAA00"
		if pct <= 20:
			dur_color = "#FF4444"
		info_bb = "[color=#888]T%d[/color] [color=%s]%d/%d[/color]" % [int(item_data.get("tier", 1)), dur_color, dur, maxd]
	else:
		var lvl := int(item_data.get("level", 1))
		var bonus := ""
		if client_ref and client_ref.has_method("get_compact_stats_bbcode"):
			bonus = client_ref.get_compact_stats_bbcode(item_data)
		elif client_ref and client_ref.has_method("_get_item_bonus_summary"):
			bonus = client_ref._get_item_bonus_summary(item_data)
		info_bb = "[color=#888]Lv%d[/color] %s" % [lvl, bonus]
	_info_label.text = info_bb

func _apply_hover_visual() -> void:
	if not _stylebox:
		return
	if _hover:
		_stylebox.bg_color = Color(0.12, 0.10, 0.08, 0.95)
		_stylebox.border_color = Color(0.7, 0.6, 0.4, 1)
	else:
		_stylebox.bg_color = Color(0.06, 0.05, 0.04, 0.85)
		_stylebox.border_color = Color(0.4, 0.34, 0.25, 0.7)

func _on_mouse_entered() -> void:
	_hover = true
	_apply_hover_visual()
	emit_signal("slot_hovered", self)

func _on_mouse_exited() -> void:
	_hover = false
	_apply_hover_visual()
	emit_signal("slot_unhovered", self)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			emit_signal("slot_clicked", self)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			emit_signal("slot_right_clicked", self, get_global_mouse_position())

# === Drag-and-drop ===
# Slot source: drag the equipped item out (drop on a card or open inventory area = unequip).
# Slot target: accept a backpack card whose type matches this slot to equip.

func _get_drag_data(_at_position: Vector2):
	if not has_item or item_data.is_empty():
		return null
	# Locked items can still be unequipped via drag — lock only protects against discard.
	set_drag_preview(_make_drag_preview())
	return {
		"source": "slot",
		"slot_name": slot_name,
		"slot_kind": slot_kind,
		"item": item_data,
	}

func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not (data is Dictionary):
		return false
	if data.get("source", "") != "card":
		return false
	var dragged_item = data.get("item", {})
	if not (dragged_item is Dictionary):
		return false
	var item_type: String = dragged_item.get("type", "")
	if slot_kind == "tool":
		if item_type != "tool":
			return false
		return str(dragged_item.get("subtype", "")) == slot_name
	# Gear: the item's natural slot must match this slot
	if client_ref and client_ref.has_method("_get_slot_for_item_type"):
		return client_ref._get_slot_for_item_type(item_type) == slot_name
	return false

func _drop_data(_at_position: Vector2, data) -> void:
	if not (data is Dictionary):
		return
	if client_ref and client_ref.has_method("_panel_equip_item"):
		client_ref._panel_equip_item(int(data.get("index", -1)), data.get("item", {}))

func _make_drag_preview() -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.92)
	var hex := _rarity_color_hex(item_data.get("rarity", "common"))
	sb.border_color = Color(hex)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = item_data.get("name", "?")
	lbl.add_theme_color_override("font_color", Color(hex))
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_font_size_override("font_size", 12)
	p.add_child(lbl)
	return p

func _rarity_color_hex(r: String) -> String:
	match r:
		"common": return "#FFFFFF"
		"uncommon": return "#1EFF00"
		"rare": return "#0070DD"
		"epic": return "#A335EE"
		"legendary": return "#FF8000"
		"artifact": return "#E6CC80"
		_: return "#FFFFFF"
