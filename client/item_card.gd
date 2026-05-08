extends PanelContainer
class_name ItemCard

signal card_clicked(card: ItemCard, event: InputEventMouseButton)
signal card_double_clicked(card: ItemCard)
signal card_right_clicked(card: ItemCard, screen_pos: Vector2)
signal card_hovered(card: ItemCard)
signal card_unhovered(card: ItemCard)

const CARD_WIDTH := 215
const CARD_HEIGHT := 84

const TYPE_LETTERS := {
	"weapon": "W", "armor": "A", "helm": "H", "shield": "S",
	"boots": "B", "ring": "R", "amulet": "N",
	"tool": "T", "rune": "U", "consumable": "C", "structure": "X", "egg": "E",
}
const TYPE_BG_COLORS := {
	"weapon": Color(0.55, 0.15, 0.15), "armor": Color(0.18, 0.35, 0.55),
	"helm": Color(0.18, 0.35, 0.55), "shield": Color(0.18, 0.35, 0.55),
	"boots": Color(0.18, 0.35, 0.55), "ring": Color(0.55, 0.4, 0.1),
	"amulet": Color(0.55, 0.4, 0.1), "tool": Color(0.35, 0.25, 0.12),
	"rune": Color(0.45, 0.18, 0.55), "consumable": Color(0.15, 0.45, 0.2),
	"structure": Color(0.3, 0.3, 0.3), "egg": Color(0.5, 0.45, 0.3),
}

var item_data: Dictionary = {}
var inventory_index: int = -1
var grouped_indices: Array = []  # for stacked consumables, all matching inventory indices
var stack_count: int = 1
var is_grouped: bool = false
var _selected: bool = false
var _hover: bool = false
var _border_color: Color = Color.WHITE

var _icon_rect: ColorRect
var _type_letter: Label
var _name_label: Label
var _stat_label: RichTextLabel
var _badge_label: Label
var _lock_label: Label
var _wear_bar: ProgressBar
var _stylebox: StyleBoxFlat

var client_ref = null  # set by panel for accessing helper functions

func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_visuals()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	if not item_data.is_empty():
		_render()

func _build_visuals() -> void:
	_stylebox = StyleBoxFlat.new()
	_stylebox.bg_color = Color(0.1, 0.08, 0.06, 0.95)
	_stylebox.border_color = _border_color
	_stylebox.set_border_width_all(2)
	_stylebox.set_corner_radius_all(4)
	_stylebox.content_margin_left = 4
	_stylebox.content_margin_top = 4
	_stylebox.content_margin_right = 4
	_stylebox.content_margin_bottom = 4
	add_theme_stylebox_override("panel", _stylebox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hbox)

	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(28, 28)
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_container)

	_icon_rect = ColorRect.new()
	_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon_rect.color = Color(0.3, 0.3, 0.3)
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(_icon_rect)

	_type_letter = Label.new()
	_type_letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_type_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_type_letter.add_theme_font_size_override("font_size", 16)
	_type_letter.add_theme_color_override("font_color", Color.WHITE)
	_type_letter.add_theme_color_override("font_outline_color", Color.BLACK)
	_type_letter.add_theme_constant_override("outline_size", 2)
	_type_letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(_type_letter)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_FILL
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	# Name row: lock + name (expand) + badge (shrink end) -- all inline so name uses full width
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_row)

	_lock_label = Label.new()
	_lock_label.add_theme_font_size_override("font_size", 12)
	_lock_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	_lock_label.text = "L"
	_lock_label.visible = false
	_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_lock_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_name_label)

	_badge_label = Label.new()
	_badge_label.add_theme_font_size_override("font_size", 11)
	_badge_label.add_theme_color_override("font_color", Color(1, 0.92, 0.5))
	_badge_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_badge_label.add_theme_constant_override("outline_size", 2)
	_badge_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_badge_label)

	_stat_label = RichTextLabel.new()
	_stat_label.bbcode_enabled = true
	_stat_label.fit_content = true
	_stat_label.scroll_active = false
	_stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stat_label.add_theme_font_size_override("normal_font_size", 12)
	_stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_label.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(_stat_label)

	_wear_bar = ProgressBar.new()
	_wear_bar.show_percentage = false
	_wear_bar.custom_minimum_size = Vector2(0, 4)
	_wear_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wear_bar.visible = false
	vbox.add_child(_wear_bar)

func set_item(item: Dictionary, idx: int, count: int = 1, indices: Array = []) -> void:
	item_data = item
	inventory_index = idx
	stack_count = max(1, count)
	grouped_indices = indices
	is_grouped = grouped_indices.size() > 1
	if is_inside_tree():
		_render()

func _render() -> void:
	if item_data.is_empty():
		return
	var item_type: String = item_data.get("type", "")
	var rarity: String = item_data.get("rarity", "common")
	var rarity_hex := _rarity_color_hex(rarity)
	_border_color = Color(rarity_hex)
	if _stylebox:
		_stylebox.border_color = _border_color

	var category := _category_for_type(item_type)
	_icon_rect.color = TYPE_BG_COLORS.get(category, Color(0.3, 0.3, 0.3))
	_type_letter.text = TYPE_LETTERS.get(category, "?")

	var display_name: String = item_data.get("name", "Unknown")
	if client_ref and client_ref.has_method("_get_themed_item_name"):
		display_name = client_ref._get_themed_item_name(item_data, "")
	_name_label.text = display_name
	_name_label.add_theme_color_override("font_color", _border_color)

	# Stat / info line
	var info_bb := ""
	if item_type == "tool":
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
		var subtype: String = item_data.get("subtype", "tool")
		info_bb = "[color=#888]%s T%d[/color] [color=%s]%d/%d[/color]" % [
			subtype.capitalize(), int(item_data.get("tier", 1)), dur_color, dur, maxd
		]
	elif item_type == "rune":
		if item_data.has("rune_proc"):
			info_bb = "[color=#A335EE]Proc: %s[/color]" % item_data.get("rune_proc", "").replace("_", " ").capitalize()
		else:
			var stat: String = item_data.get("rune_stat", "").replace("_bonus", "").replace("_", " ")
			info_bb = "[color=#A335EE]+%d %s[/color]" % [int(item_data.get("rune_cap", 0)), stat]
	elif item_type == "egg":
		info_bb = "[color=#9ACD32]Egg[/color]"
	elif item_data.get("is_consumable", false) or _is_consumable_type(item_type):
		var lvl := int(item_data.get("level", 1))
		info_bb = "[color=#9ACD32]Lv%d Consumable[/color]" % lvl
	else:
		# Equipment: show delta vs currently equipped item in the same slot,
		# or absolute multi-stat breakdown if nothing is equipped there.
		var eq_item = null
		if client_ref and client_ref.has_method("_get_slot_for_item_type") and "character_data" in client_ref:
			var slot_for_item: String = client_ref._get_slot_for_item_type(item_type)
			if slot_for_item != "":
				var equipped: Dictionary = client_ref.character_data.get("equipped", {})
				var maybe = equipped.get(slot_for_item)
				if maybe != null and maybe is Dictionary and not maybe.is_empty():
					eq_item = maybe
		if eq_item != null and client_ref.has_method("_get_item_comparison_parts"):
			var diff_parts: Array = client_ref._get_item_comparison_parts(item_data, eq_item)
			if diff_parts.is_empty():
				info_bb = "[color=#888]Identical to equipped[/color]"
			else:
				info_bb = " ".join(diff_parts)
		elif client_ref and client_ref.has_method("get_compact_stats_bbcode"):
			info_bb = client_ref.get_compact_stats_bbcode(item_data)
		elif client_ref and client_ref.has_method("_get_item_bonus_summary"):
			info_bb = client_ref._get_item_bonus_summary(item_data)
	_stat_label.text = info_bb

	# Corner badge: stack count if grouped, else level for equipment
	var badge_text := ""
	if stack_count > 1:
		badge_text = "x%d" % stack_count
	elif item_type != "tool" and not (item_data.get("is_consumable", false) or _is_consumable_type(item_type)):
		var lvl := int(item_data.get("level", 0))
		if lvl > 0:
			badge_text = "Lv%d" % lvl
	_badge_label.text = badge_text

	# Lock indicator
	_lock_label.visible = bool(item_data.get("locked", false))

	# Wear bar for equipment with wear
	var wear := int(item_data.get("wear", 0))
	if wear > 0 and item_type != "tool" and not item_data.get("is_consumable", false):
		_wear_bar.visible = true
		_wear_bar.max_value = 100
		_wear_bar.value = max(0, 100 - wear)
		var wear_color := Color(0.2, 0.8, 0.2)
		if wear >= 70:
			wear_color = Color(0.9, 0.2, 0.2)
		elif wear >= 35:
			wear_color = Color(0.95, 0.7, 0.15)
		var fill := StyleBoxFlat.new()
		fill.bg_color = wear_color
		_wear_bar.add_theme_stylebox_override("fill", fill)
	else:
		_wear_bar.visible = false

	_apply_hover_visual()

func set_selected(sel: bool) -> void:
	_selected = sel
	_apply_hover_visual()

func _apply_hover_visual() -> void:
	if not _stylebox:
		return
	if _selected:
		_stylebox.bg_color = Color(0.18, 0.15, 0.10, 1.0)
		_stylebox.set_border_width_all(3)
	elif _hover:
		_stylebox.bg_color = Color(0.16, 0.12, 0.08, 0.98)
		_stylebox.set_border_width_all(2)
	else:
		_stylebox.bg_color = Color(0.1, 0.08, 0.06, 0.95)
		_stylebox.set_border_width_all(2)

func _on_mouse_entered() -> void:
	_hover = true
	_apply_hover_visual()
	emit_signal("card_hovered", self)

func _on_mouse_exited() -> void:
	_hover = false
	_apply_hover_visual()
	emit_signal("card_unhovered", self)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				emit_signal("card_double_clicked", self)
			else:
				emit_signal("card_clicked", self, mb)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			emit_signal("card_right_clicked", self, get_global_mouse_position())

# === Drag-and-drop ===
# Card source: drag a backpack item onto a paper-doll slot to equip it.
# Card target: accept drops from equipped slots (drop a slot onto inventory area = unequip).

func _get_drag_data(_at_position: Vector2):
	if item_data.is_empty():
		return null
	# Locked items can still be dragged onto valid equip slots — lock only protects
	# against discard, not equip. _panel_drop_item still refuses dropping a locked
	# item via the right-click menu.
	set_drag_preview(_make_drag_preview())
	return {
		"source": "card",
		"index": inventory_index,
		"item": item_data,
	}

func _can_drop_data(_at_position: Vector2, data) -> bool:
	if not (data is Dictionary):
		return false
	return data.get("source", "") == "slot"

func _drop_data(_at_position: Vector2, data) -> void:
	if not (data is Dictionary):
		return
	if data.get("source", "") != "slot":
		return
	if client_ref and client_ref.has_method("_panel_unequip_slot"):
		client_ref._panel_unequip_slot(str(data.get("slot_name", "")), str(data.get("slot_kind", "")))

func _make_drag_preview() -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.92)
	sb.border_color = _border_color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = item_data.get("name", "?")
	lbl.add_theme_color_override("font_color", _border_color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_font_size_override("font_size", 12)
	p.add_child(lbl)
	return p

func _category_for_type(t: String) -> String:
	if t == "":
		return "consumable"
	if "weapon" in t:
		return "weapon"
	if "armor" in t:
		return "armor"
	if "helm" in t:
		return "helm"
	if "shield" in t:
		return "shield"
	if "boots" in t:
		return "boots"
	if "ring" in t:
		return "ring"
	if "amulet" in t:
		return "amulet"
	if t == "tool":
		return "tool"
	if t == "rune":
		return "rune"
	if t == "egg" or t.begins_with("egg_"):
		return "egg"
	if t == "structure":
		return "structure"
	return "consumable"

func _is_consumable_type(t: String) -> bool:
	return (t == "consumable"
		or t.begins_with("potion_") or t.begins_with("mana_")
		or t.begins_with("stamina_") or t.begins_with("energy_")
		or t.begins_with("scroll_") or t.begins_with("tome_")
		or t == "gold_pouch" or t.begins_with("gem_")
		or t == "mysterious_box" or t == "cursed_coin"
		or t == "soul_gem" or t.begins_with("home_stone_")
		or t.begins_with("charm_")
		or t == "boss_slayer_tonic" or t == "reclaimer_lantern"
		or t == "floor_skip_charm")

func _rarity_color_hex(r: String) -> String:
	match r:
		"common": return "#FFFFFF"
		"uncommon": return "#1EFF00"
		"rare": return "#0070DD"
		"epic": return "#A335EE"
		"legendary": return "#FF8000"
		"artifact": return "#E6CC80"
		_: return "#FFFFFF"
