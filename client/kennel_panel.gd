extends Control
class_name KennelPanel

# Visual surface for the K-tile (Companion Kennel) sub-mode of the Sanctuary.
# Shows all stored companions as cards in an HFlowContainer; right-click a card
# for Release / Register actions. Mirrors CompanionsPanel layout but without the
# "active companion" section since kennel companions are pure storage.

signal close_requested
signal release_requested(index: int)
signal register_requested(index: int)
signal sort_changed(sort_option: String, ascending: bool)

const SORT_OPTIONS := ["level", "tier", "sub_tier", "variant", "name", "type"]

var client_ref = null

var _companions: Array = []
var _capacity: int = 0
var _can_register: bool = true
var _sort_option: String = "level"
var _sort_ascending: bool = false

var _root_panel: PanelContainer
var _title_label: Label
var _capacity_label: RichTextLabel
var _sort_button: Button
var _asc_button: Button
var _grid_scroll: ScrollContainer
var _grid: HFlowContainer
var _empty_label: Label

var _ctx_menu: PopupMenu
var _ctx_index: int = -1
const CTX_RELEASE := 1
const CTX_REGISTER := 2

var _confirm_dialog: ConfirmationDialog
var _pending_release_index: int = -1


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
	_title_label.text = "Sanctuary — Kennel"
	_title_label.add_theme_color_override("font_color", Color(1, 0.53, 0))
	_title_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_title_label)

	_capacity_label = RichTextLabel.new()
	_capacity_label.bbcode_enabled = true
	_capacity_label.fit_content = true
	_capacity_label.scroll_active = false
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity_label.custom_minimum_size = Vector2(0, 22)
	_capacity_label.add_theme_font_size_override("normal_font_size", 14)
	header.add_child(_capacity_label)

	# Sort row
	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(sort_row)

	var sort_lbl := Label.new()
	sort_lbl.text = "Sort:"
	sort_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sort_lbl.add_theme_font_size_override("font_size", 12)
	sort_row.add_child(sort_lbl)

	_sort_button = Button.new()
	_sort_button.focus_mode = Control.FOCUS_NONE
	_sort_button.add_theme_font_size_override("font_size", 12)
	_sort_button.custom_minimum_size = Vector2(120, 26)
	_sort_button.pressed.connect(_on_sort_cycle)
	sort_row.add_child(_sort_button)

	_asc_button = Button.new()
	_asc_button.focus_mode = Control.FOCUS_NONE
	_asc_button.add_theme_font_size_override("font_size", 12)
	_asc_button.custom_minimum_size = Vector2(70, 26)
	_asc_button.pressed.connect(_on_asc_toggle)
	sort_row.add_child(_asc_button)

	var sort_spacer := Control.new()
	sort_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sort_row.add_child(sort_spacer)

	var hint_lbl := Label.new()
	hint_lbl.text = "Right-click a companion for actions"
	hint_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	hint_lbl.add_theme_font_size_override("font_size", 12)
	sort_row.add_child(hint_lbl)

	# Body — companion grid
	var body_panel := _make_subpanel()
	body_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body_panel)

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_panel.add_child(_grid_scroll)

	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid_scroll.add_child(_grid)

	_empty_label = Label.new()
	_empty_label.text = "Kennel is empty. Use Home Stones (Companion) or unregister companions to send them here."
	_empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.visible = false
	_grid.add_child(_empty_label)

	# Bottom action row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(action_row)

	var action_spacer := Control.new()
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(action_spacer)

	var close_btn := Button.new()
	close_btn.text = "Close (Space)"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.custom_minimum_size = Vector2(0, 30)
	close_btn.pressed.connect(_on_close_pressed)
	action_row.add_child(close_btn)

	# Right-click context menu
	_ctx_menu = PopupMenu.new()
	_ctx_menu.id_pressed.connect(_on_ctx_menu_id_pressed)
	add_child(_ctx_menu)

	# Release confirmation dialog
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = "Release this companion? It will be permanently removed."
	_confirm_dialog.title = "Release Companion"
	_confirm_dialog.confirmed.connect(_on_release_confirmed)
	add_child(_confirm_dialog)

	_update_sort_button_text()
	_update_asc_button_text()


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


# === Public API ===

func populate(companions: Array, capacity: int, can_register: bool, sort_option: String, sort_ascending: bool) -> void:
	if not is_inside_tree():
		return
	_companions = companions
	_capacity = capacity
	_can_register = can_register
	_sort_option = sort_option if sort_option in SORT_OPTIONS else "level"
	_sort_ascending = sort_ascending
	_update_capacity()
	_update_sort_button_text()
	_update_asc_button_text()
	_rebuild_grid()


# === Internal rendering ===

func _update_capacity() -> void:
	_capacity_label.text = "[color=#FF8800]Stored:[/color] %d / %d" % [_companions.size(), _capacity]


func _update_sort_button_text() -> void:
	_sort_button.text = "Sort: %s" % _sort_option.capitalize()


func _update_asc_button_text() -> void:
	_asc_button.text = "Asc" if _sort_ascending else "Desc"


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		if child == _empty_label:
			continue
		child.queue_free()

	if _companions.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false

	# Build a list of {companion, original_index} so cards can emit the original index.
	var indexed: Array = []
	for i in range(_companions.size()):
		indexed.append({"companion": _companions[i], "index": i})
	_sort_indexed(indexed)

	for entry in indexed:
		var card := _make_card(entry["companion"], int(entry["index"]))
		_grid.add_child(card)


func _sort_indexed(arr: Array) -> void:
	var asc := _sort_ascending
	var key := _sort_option
	arr.sort_custom(func(a, b):
		var av = _sort_key_value(a["companion"], key)
		var bv = _sort_key_value(b["companion"], key)
		if av == bv:
			return false
		if asc:
			return av < bv
		return av > bv
	)


func _sort_key_value(c: Dictionary, key: String):
	match key:
		"level": return int(c.get("level", 1))
		"tier": return int(c.get("tier", 1)) * 10 + int(c.get("sub_tier", 1))
		"sub_tier": return int(c.get("sub_tier", 1)) * 100 + int(c.get("tier", 1))
		"variant":
			if client_ref and client_ref.has_method("_get_variant_sort_value"):
				return int(client_ref._get_variant_sort_value(str(c.get("variant", "Normal"))))
			return 0
		"name": return str(c.get("name", "")).to_lower()
		"type": return str(c.get("monster_type", c.get("name", ""))).to_lower()
	return 0


func _make_card(c: Dictionary, original_index: int) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.95)
	sb.border_color = Color(0.4, 0.34, 0.25, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(220, 84)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var name_lbl := RichTextLabel.new()
	name_lbl.bbcode_enabled = true
	name_lbl.fit_content = true
	name_lbl.scroll_active = false
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("normal_font_size", 13)
	var name = str(c.get("name", "?"))
	var variant = str(c.get("variant", "Normal"))
	var variant_color = str(c.get("variant_color", "#FFFFFF"))
	var rarity_color = "#FFFFFF"
	var rarity_tag = ""
	if client_ref and client_ref.has_method("_get_variant_rarity_info"):
		var info: Dictionary = client_ref._get_variant_rarity_info(variant)
		rarity_color = str(info.get("color", "#FFFFFF"))
		rarity_tag = str(info.get("tier", ""))
	var rarity_prefix = ("[color=%s][%s][/color] " % [rarity_color, rarity_tag]) if rarity_tag != "" else ""
	name_lbl.text = "%s[color=%s]%s[/color]" % [rarity_prefix, variant_color, name]
	vbox.add_child(name_lbl)

	var meta := RichTextLabel.new()
	meta.bbcode_enabled = true
	meta.fit_content = true
	meta.scroll_active = false
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_font_size_override("normal_font_size", 12)
	var level = int(c.get("level", 1))
	var tier = int(c.get("tier", 1))
	var sub_tier = int(c.get("sub_tier", 1))
	meta.text = "[color=#AAAAAA]Lv %d  T%d-%d[/color]  [color=%s]%s[/color]" % [level, tier, sub_tier, variant_color, variant]
	vbox.add_child(meta)

	var bonuses := RichTextLabel.new()
	bonuses.bbcode_enabled = true
	bonuses.fit_content = true
	bonuses.scroll_active = false
	bonuses.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bonuses.add_theme_font_size_override("normal_font_size", 11)
	var bonus_text := ""
	if client_ref and client_ref.has_method("_get_companion_card_bonus_summary"):
		bonus_text = str(client_ref._get_companion_card_bonus_summary(c))
	bonuses.text = bonus_text
	vbox.add_child(bonuses)

	card.gui_input.connect(_on_card_input.bind(original_index))
	return card


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_open_ctx_menu(index, event.global_position)


func _open_ctx_menu(index: int, screen_pos: Vector2) -> void:
	if index < 0 or index >= _companions.size():
		return
	_ctx_index = index
	_ctx_menu.clear()
	if _can_register:
		_ctx_menu.add_item("Register as Companion", CTX_REGISTER)
	else:
		var idx := _ctx_menu.get_item_count()
		_ctx_menu.add_item("Register (slots full)", CTX_REGISTER)
		_ctx_menu.set_item_disabled(idx, true)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("Release...", CTX_RELEASE)
	_ctx_menu.position = Vector2i(screen_pos)
	_ctx_menu.popup()


func _on_ctx_menu_id_pressed(id: int) -> void:
	if _ctx_index < 0:
		return
	match id:
		CTX_REGISTER:
			emit_signal("register_requested", _ctx_index)
		CTX_RELEASE:
			_pending_release_index = _ctx_index
			_confirm_dialog.popup_centered()
	_ctx_index = -1


func _on_release_confirmed() -> void:
	if _pending_release_index < 0:
		return
	emit_signal("release_requested", _pending_release_index)
	_pending_release_index = -1


func _on_sort_cycle() -> void:
	var cur := SORT_OPTIONS.find(_sort_option)
	if cur < 0:
		cur = 0
	var next_idx := (cur + 1) % SORT_OPTIONS.size()
	_sort_option = SORT_OPTIONS[next_idx]
	emit_signal("sort_changed", _sort_option, _sort_ascending)


func _on_asc_toggle() -> void:
	_sort_ascending = not _sort_ascending
	emit_signal("sort_changed", _sort_option, _sort_ascending)


func _on_close_pressed() -> void:
	emit_signal("close_requested")
