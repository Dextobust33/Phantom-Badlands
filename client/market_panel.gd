extends Control
class_name MarketPanel

# Visual market surface: tabs (Browse / My Listings), filter chips, sort cycler,
# scrollable listing rows on the left, detail + Buy button on the right.
# Listing creation flows (List from Inventory, List Materials, etc.) stay on
# the keyboard path for the initial slice and are launched via the List ▾ menu.

signal close_requested
signal tab_changed(tab_id: String)
signal filter_changed(category: String)
signal sort_changed(sort_id: String)
signal listing_clicked(listing: Dictionary, index: int)
signal buy_pressed(listing: Dictionary)
signal page_prev_pressed
signal page_next_pressed
signal cancel_listing_pressed(listing: Dictionary, index: int)
signal pull_all_pressed
signal refresh_requested
signal list_action_pressed(action_id: String)

const TAB_BROWSE := "browse"
const TAB_MY := "my_listings"

const FILTER_CHIPS := [
	{"id": "all", "label": "All"},
	{"id": "equipment", "label": "Equip"},
	{"id": "egg", "label": "Eggs"},
	{"id": "consumable", "label": "Cons"},
	{"id": "food", "label": "Food"},
	{"id": "tool", "label": "Tools"},
	{"id": "rune", "label": "Runes"},
	{"id": "material", "label": "Mats"},
	{"id": "monster_part", "label": "Parts"},
]

# Same order the client uses in market_sort_cycle so the panel stays in sync
const SORT_ORDER := ["category", "price_asc", "price_desc", "name_asc", "newest"]
const SORT_LABELS := {
	"category": "Category",
	"price_asc": "Price ▲",
	"price_desc": "Price ▼",
	"name_asc": "Name A-Z",
	"newest": "Newest",
}

const LIST_MENU_ITEMS := [
	{"id": "list_inventory", "label": "List from Inventory"},
	{"id": "list_material", "label": "List Materials"},
	{"id": "list_egg", "label": "List Egg from Incubator"},
	{"id": "_separator", "label": ""},
	{"id": "bulk_equipment", "label": "Bulk: All Equipment"},
	{"id": "bulk_consumable", "label": "Bulk: All Consumables"},
	{"id": "bulk_tool", "label": "Bulk: All Tools"},
	{"id": "bulk_material", "label": "Bulk: All Materials (non-food)"},
	{"id": "bulk_food", "label": "Bulk: All Food"},
]

var client_ref = null

var _current_tab: String = TAB_BROWSE
var _current_category: String = "all"
var _current_sort: String = "category"
var _listings: Array = []
var _post_name: String = ""
# Audit #9 Slice 3 — specialty summary text (e.g., "Specialty: -15% on Materials").
# Empty for non-specialty posts. Renders as a header line below the post name.
var _specialty_summary: String = ""
var _valor: int = 0
var _page: int = 0
var _total_pages: int = 0
var _selected_index: int = -1

var _root_panel: PanelContainer
var _title_label: Label
var _valor_label: RichTextLabel
var _specialty_label: RichTextLabel  # Audit #9 Slice 3 — post specialty header
var _tab_browse_btn: Button
var _tab_my_btn: Button
var _filter_chip_row: HBoxContainer
var _filter_buttons: Dictionary = {}
var _sort_button: Button
var _refresh_button: Button
var _page_label: Label
var _prev_button: Button
var _next_button: Button
var _listings_vbox: VBoxContainer
var _detail_root: VBoxContainer
var _detail_title: RichTextLabel
var _detail_meta: RichTextLabel
var _detail_status: RichTextLabel
var _buy_button: Button
var _cancel_button: Button
var _detail_empty: Label
var _list_button: Button
var _list_menu: PopupMenu
var _pull_all_button: Button
var _status_label: RichTextLabel


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
	_title_label.text = "Market"
	_title_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_title_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_title_label)

	_valor_label = RichTextLabel.new()
	_valor_label.bbcode_enabled = true
	_valor_label.fit_content = true
	_valor_label.scroll_active = false
	_valor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_valor_label.custom_minimum_size = Vector2(0, 22)
	_valor_label.add_theme_font_size_override("normal_font_size", 14)
	header.add_child(_valor_label)

	# Specialty header (Audit #9 Slice 3). Sits below the title row; hidden
	# when post has no specialty. Bright green to draw the eye to the discount.
	_specialty_label = RichTextLabel.new()
	_specialty_label.bbcode_enabled = true
	_specialty_label.fit_content = true
	_specialty_label.scroll_active = false
	_specialty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_specialty_label.custom_minimum_size = Vector2(0, 20)
	_specialty_label.add_theme_font_size_override("normal_font_size", 13)
	_specialty_label.visible = false
	root_vbox.add_child(_specialty_label)

	# Tabs
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(tab_row)

	_tab_browse_btn = _make_tab_button("Browse", _on_tab_browse_pressed)
	_tab_my_btn = _make_tab_button("My Listings", _on_tab_my_pressed)
	tab_row.add_child(_tab_browse_btn)
	tab_row.add_child(_tab_my_btn)

	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_spacer)

	_sort_button = _make_action_btn("Sort: Category", _on_sort_pressed)
	_sort_button.custom_minimum_size = Vector2(160, 28)
	tab_row.add_child(_sort_button)

	_refresh_button = _make_action_btn("Refresh", _on_refresh_pressed)
	tab_row.add_child(_refresh_button)

	# Filter chips
	_filter_chip_row = HBoxContainer.new()
	_filter_chip_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(_filter_chip_row)
	for chip in FILTER_CHIPS:
		var btn := Button.new()
		btn.text = chip["label"]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 24)
		btn.pressed.connect(_on_filter_pressed.bind(chip["id"]))
		_filter_chip_row.add_child(btn)
		_filter_buttons[chip["id"]] = btn
	_filter_buttons["all"].button_pressed = true

	# Page nav
	var page_row := HBoxContainer.new()
	page_row.add_theme_constant_override("separation", 6)
	root_vbox.add_child(page_row)

	_prev_button = _make_action_btn("◀ Prev", _on_prev_pressed)
	_prev_button.custom_minimum_size = Vector2(70, 26)
	page_row.add_child(_prev_button)

	_page_label = Label.new()
	_page_label.text = ""
	_page_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_page_label.add_theme_font_size_override("font_size", 12)
	_page_label.custom_minimum_size = Vector2(120, 0)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_row.add_child(_page_label)

	_next_button = _make_action_btn("Next ▶", _on_next_pressed)
	_next_button.custom_minimum_size = Vector2(70, 26)
	page_row.add_child(_next_button)

	var page_spacer := Control.new()
	page_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_row.add_child(page_spacer)

	# Body: listings list (left) + detail (right)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root_vbox.add_child(body)

	var list_panel := _make_subpanel()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 1.4
	body.add_child(list_panel)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(list_scroll)

	_listings_vbox = VBoxContainer.new()
	_listings_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_listings_vbox.add_theme_constant_override("separation", 2)
	list_scroll.add_child(_listings_vbox)

	# Right: detail panel
	var detail_panel := _make_subpanel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)

	_detail_root = VBoxContainer.new()
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.add_theme_constant_override("separation", 6)
	detail_panel.add_child(_detail_root)

	_detail_title = RichTextLabel.new()
	_detail_title.bbcode_enabled = true
	_detail_title.fit_content = true
	_detail_title.scroll_active = false
	_detail_title.add_theme_font_size_override("normal_font_size", 18)
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.add_child(_detail_title)

	_detail_meta = RichTextLabel.new()
	_detail_meta.bbcode_enabled = true
	_detail_meta.fit_content = true
	_detail_meta.scroll_active = false
	_detail_meta.add_theme_font_size_override("normal_font_size", 14)
	_detail_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.add_child(_detail_meta)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_root.add_child(detail_scroll)

	_detail_status = RichTextLabel.new()
	_detail_status.bbcode_enabled = true
	_detail_status.fit_content = true
	_detail_status.scroll_active = false
	_detail_status.add_theme_font_size_override("normal_font_size", 14)
	_detail_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_status)

	_buy_button = Button.new()
	_buy_button.text = "Buy"
	_buy_button.focus_mode = Control.FOCUS_NONE
	_buy_button.add_theme_font_size_override("font_size", 16)
	_buy_button.custom_minimum_size = Vector2(0, 40)
	_buy_button.pressed.connect(_on_buy_pressed)
	_detail_root.add_child(_buy_button)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel Listing"
	_cancel_button.focus_mode = Control.FOCUS_NONE
	_cancel_button.add_theme_font_size_override("font_size", 14)
	_cancel_button.custom_minimum_size = Vector2(0, 32)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_detail_root.add_child(_cancel_button)

	_detail_empty = Label.new()
	_detail_empty.text = "Select a listing on the left."
	_detail_empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_detail_empty.add_theme_font_size_override("font_size", 14)
	_detail_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_root.add_child(_detail_empty)

	# Action row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(action_row)

	_list_button = _make_action_btn("List ▾", _on_list_menu_pressed)
	action_row.add_child(_list_button)

	_pull_all_button = _make_action_btn("Pull All", _on_pull_all_pressed)
	action_row.add_child(_pull_all_button)

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

	# List PopupMenu — assign each slot an id equal to its index in
	# LIST_MENU_ITEMS so the handler can look up entries directly. Without
	# explicit ids the engine auto-assigns sequential ids that include the
	# separator slot, which made id_pressed report a value one off from the
	# "visible item" position the previous handler assumed.
	_list_menu = PopupMenu.new()
	for i in range(LIST_MENU_ITEMS.size()):
		var entry = LIST_MENU_ITEMS[i]
		if entry["id"] == "_separator":
			_list_menu.add_separator("", i)
		else:
			_list_menu.add_item(entry["label"], i)
	_list_menu.id_pressed.connect(_on_list_menu_item_pressed)
	add_child(_list_menu)

	_show_detail_empty(true)
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
	b.custom_minimum_size = Vector2(0, 28)
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

func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func populate_browse(post_name: String, valor: int, listings: Array, category: String, sort: String, page: int, total_pages: int, specialty_summary: String = "") -> void:
	if not is_inside_tree():
		return
	_current_tab = TAB_BROWSE
	_post_name = post_name
	_valor = valor
	_listings = listings
	_current_category = category
	_current_sort = sort
	_page = page
	_total_pages = total_pages
	_specialty_summary = specialty_summary

	_update_header()
	_filter_chip_row.visible = true
	_sort_button.visible = true
	_sort_button.text = "Sort: %s" % SORT_LABELS.get(sort, sort.capitalize())
	for chip_id in _filter_buttons.keys():
		_filter_buttons[chip_id].button_pressed = (chip_id == category)
	_pull_all_button.visible = false

	_page_label.visible = true
	_prev_button.visible = true
	_next_button.visible = true
	_page_label.text = "Page %d / %d" % [page + 1, max(1, total_pages)]
	_prev_button.disabled = page <= 0
	_next_button.disabled = page >= total_pages - 1

	_rebuild_browse_rows()
	_update_tab_styles()
	# Selection no longer valid after refresh
	_selected_index = -1
	_show_detail_empty(true)


func populate_my_listings(post_name: String, valor: int, listings: Array) -> void:
	if not is_inside_tree():
		return
	_current_tab = TAB_MY
	_post_name = post_name
	_valor = valor
	_listings = listings

	_update_header()
	_filter_chip_row.visible = false
	_sort_button.visible = false
	_pull_all_button.visible = listings.size() > 0
	_page_label.visible = false
	_prev_button.visible = false
	_next_button.visible = false

	_rebuild_my_rows()
	_update_tab_styles()
	_selected_index = -1
	_show_detail_empty(true)


func populate_inspect(listing: Dictionary, valor: int) -> void:
	if not is_inside_tree():
		return
	if listing.is_empty():
		_show_detail_empty(true)
		return
	_valor = valor
	_update_header()

	var item: Dictionary = listing.get("item", {})
	var item_name: String = _resolve_item_name(item)
	var rarity_color: String = _rarity_color_hex(item.get("rarity", "common"))
	var price := int(listing.get("markup_price", listing.get("base_valor", 0)))
	var seller: String = str(listing.get("seller_name", "Unknown"))
	var qty := int(listing.get("total_quantity", listing.get("quantity", 1)))

	_detail_title.text = "[color=%s][b]%s[/b][/color]" % [rarity_color, item_name]

	var meta_lines: Array = []
	if item.has("level"):
		meta_lines.append("[color=#87CEEB]Level:[/color] %d" % int(item.get("level", 1)))
	if item.get("type", "") == "egg":
		var variant = str(item.get("variant", "Normal"))
		var tier = int(item.get("tier", 1))
		var sub = int(item.get("sub_tier", 1))
		meta_lines.append("[color=#87CEEB]Egg:[/color] %s (T%d-%d)" % [variant, tier, sub])
	if qty > 1:
		meta_lines.append("[color=#87CEEB]Quantity:[/color] %d" % qty)
	meta_lines.append("[color=#87CEEB]Seller:[/color] %s" % seller)
	meta_lines.append("[color=#87CEEB]Price:[/color] [color=#00FF00]%s Valor[/color]" % _format_number(price))
	if qty > 1:
		var per_unit = int(price / qty) if qty > 0 else price
		meta_lines.append("[color=#808080]Per unit: %s V[/color]" % _format_number(per_unit))
	_detail_meta.text = "\n".join(meta_lines)

	# Status: full item description if we can borrow client_ref's helper
	if client_ref and client_ref.has_method("format_item_tooltip_bbcode"):
		_detail_status.text = str(client_ref.format_item_tooltip_bbcode(item))
	else:
		_detail_status.text = ""

	_show_detail_empty(false)

	if _current_tab == TAB_MY:
		_buy_button.visible = false
		_cancel_button.visible = true
	else:
		_cancel_button.visible = false
		_buy_button.visible = true
		if valor >= price:
			_buy_button.text = "Buy for %s V" % _format_number(price)
			_buy_button.disabled = false
			_buy_button.add_theme_color_override("font_color", Color(0, 1, 0))
		else:
			_buy_button.text = "Not Enough Valor"
			_buy_button.disabled = true
			_buy_button.add_theme_color_override("font_color", Color(1, 0.4, 0.4))


# === Internal rendering ===

func _update_header() -> void:
	var title_text := "Market"
	if _post_name != "":
		title_text = "Market - %s" % _post_name
	_title_label.text = title_text
	_valor_label.text = "[color=#00FF00]Your Valor:[/color] [color=#FFFF00]%s[/color]" % _format_number(_valor)
	# Audit #9 Slice 3 — specialty line under the header. Visible only when the
	# current browse view delivered a non-empty specialty summary (browse only;
	# my_listings doesn't carry one).
	if _specialty_label:
		if _current_tab == TAB_BROWSE and _specialty_summary != "":
			_specialty_label.text = "[color=#9ACD32]%s[/color]" % _specialty_summary
			_specialty_label.visible = true
		else:
			_specialty_label.visible = false


func _update_tab_styles() -> void:
	_tab_browse_btn.button_pressed = (_current_tab == TAB_BROWSE)
	_tab_my_btn.button_pressed = (_current_tab == TAB_MY)


func _rebuild_browse_rows() -> void:
	for child in _listings_vbox.get_children():
		child.queue_free()

	if _listings.is_empty():
		var lbl := Label.new()
		lbl.text = "No listings found."
		lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		lbl.add_theme_font_size_override("font_size", 13)
		_listings_vbox.add_child(lbl)
		return

	# When sorted by category, insert dividers
	var show_dividers := _current_category == "all" and _current_sort == "category"
	var last_category := ""

	for i in range(_listings.size()):
		var listing = _listings[i]
		if show_dividers:
			var disp := str(listing.get("display_category", ""))
			if disp != "" and disp != last_category:
				if last_category != "":
					var spacer := Control.new()
					spacer.custom_minimum_size = Vector2(0, 4)
					_listings_vbox.add_child(spacer)
				var hdr := Label.new()
				hdr.text = "── %s" % disp
				hdr.add_theme_color_override("font_color", Color(1, 0.84, 0))
				hdr.add_theme_font_size_override("font_size", 12)
				_listings_vbox.add_child(hdr)
				last_category = disp
		var row := _make_listing_row(listing, i, false)
		_listings_vbox.add_child(row)


func _rebuild_my_rows() -> void:
	for child in _listings_vbox.get_children():
		child.queue_free()

	if _listings.is_empty():
		var lbl := Label.new()
		lbl.text = "You have no active listings."
		lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		lbl.add_theme_font_size_override("font_size", 13)
		_listings_vbox.add_child(lbl)
		return

	# Group by category for display
	var cat_order := {"equipment": 0, "egg": 1, "consumable": 2, "tool": 3, "rune": 4, "monster_part": 5}
	var sorted := _listings.duplicate()
	sorted.sort_custom(func(a, b):
		var a_cat = a.get("supply_category", "equipment")
		var b_cat = b.get("supply_category", "equipment")
		var a_o = cat_order.get(a_cat, 7 if not str(a_cat).begins_with("material") else 6)
		var b_o = cat_order.get(b_cat, 7 if not str(b_cat).begins_with("material") else 6)
		if a_o != b_o:
			return a_o < b_o
		return int(a.get("base_valor", 0)) > int(b.get("base_valor", 0)))

	var last_category := ""
	for i in range(sorted.size()):
		var listing = sorted[i]
		var supply_cat = str(listing.get("supply_category", "equipment"))
		var display_cat := _my_listing_category_label(supply_cat)
		if display_cat != last_category:
			if last_category != "":
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(0, 4)
				_listings_vbox.add_child(spacer)
			var hdr := Label.new()
			hdr.text = "── %s" % display_cat
			hdr.add_theme_color_override("font_color", Color(1, 0.84, 0))
			hdr.add_theme_font_size_override("font_size", 12)
			_listings_vbox.add_child(hdr)
			last_category = display_cat
		var row := _make_listing_row(listing, i, true)
		_listings_vbox.add_child(row)
	# Replace the displayed list so click handlers map back into this sorted array
	_listings = sorted


func _my_listing_category_label(supply_cat: String) -> String:
	if supply_cat == "equipment": return "Equipment"
	if supply_cat == "egg": return "Companion Eggs"
	if supply_cat == "consumable": return "Consumables"
	if supply_cat == "tool": return "Tools"
	if supply_cat == "rune": return "Runes"
	if supply_cat.begins_with("material"): return "Materials"
	if supply_cat == "monster_part": return "Monster Parts"
	return "Other"


func _make_listing_row(listing: Dictionary, index: int, is_my_listing: bool) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 40)
	btn.toggle_mode = true
	btn.button_pressed = (index == _selected_index)
	btn.add_theme_font_size_override("font_size", 13)

	var item: Dictionary = listing.get("item", {})
	var item_name: String = _resolve_item_name(item)
	var price := int(listing.get("markup_price", listing.get("base_valor", 0)))
	var seller: String = str(listing.get("seller_name", ""))
	var qty := int(listing.get("total_quantity", listing.get("quantity", 1)))
	var qty_text: String = "" if qty <= 1 else " x%d" % qty
	var rarity := str(item.get("rarity", "common"))
	var rarity_color := _rarity_color(rarity)

	var label_parts: Array = []
	if item.has("level"):
		label_parts.append("Lv%d" % int(item.get("level", 1)))
	if item.get("type", "") == "egg":
		var t = int(item.get("tier", 1))
		var s = int(item.get("sub_tier", 1))
		label_parts.append("T%d-%d" % [t, s])
	var meta := ""
	if label_parts.size() > 0:
		meta = "  " + " ".join(label_parts)

	var price_text := "%s V" % _format_number(price)
	# Audit #9 Slice 3 — tag rows where the buyer is getting the post's specialty
	# discount. The server has already baked the discount into `markup_price`;
	# this badge just calls out which listings benefit. Buttons don't render
	# BBCode, so we append as plain text and rely on a brighter font_color.
	var disc := float(listing.get("specialty_discount", 0.0))
	if disc > 0.0 and not is_my_listing:
		price_text += "  ★-%d%%" % int(disc * 100)
	# Audit #9 Slice 4 — rolling avg recent paid price (post-markup). Lets
	# buyers spot deals and sellers price competitively at a glance. Server
	# emits 0 when there's no history; suppress the badge in that case.
	var avg_recent := int(listing.get("avg_recent_price", 0))
	if avg_recent > 0 and not is_my_listing:
		price_text += "  (avg %s)" % _format_number(avg_recent)
	if is_my_listing:
		var post_name = listing.get("post_name", "")
		if str(post_name) != "":
			meta += "  @%s" % post_name

	# Use BBCode-free button text since Buttons don't render BBCode — use color override
	btn.text = "%s%s%s   —   %s%s" % [item_name, qty_text, meta, price_text, "  (by %s)" % seller if not is_my_listing and seller != "" else ""]
	btn.add_theme_color_override("font_color", rarity_color)

	btn.pressed.connect(_on_listing_pressed.bind(index))
	return btn


func _resolve_item_name(item: Dictionary) -> String:
	var n = item.get("name", "")
	if str(n) == "" and item.get("type", "") == "egg":
		var comp_name = str(item.get("companion_name", ""))
		if comp_name != "":
			return comp_name + " Egg"
	if str(n) == "":
		return "Unknown"
	return str(n)


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(1, 1, 1)
		"uncommon": return Color(0.12, 1, 0)
		"rare": return Color(0, 0.44, 0.87)
		"epic": return Color(0.64, 0.21, 0.93)
		"legendary": return Color(1, 0.5, 0)
		_: return Color(1, 1, 1)


func _rarity_color_hex(rarity: String) -> String:
	match rarity:
		"common": return "#FFFFFF"
		"uncommon": return "#1EFF00"
		"rare": return "#0070DD"
		"epic": return "#A335EE"
		"legendary": return "#FF8000"
		_: return "#FFFFFF"


func _format_number(n: int) -> String:
	# Lightweight thousands separators
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


func _show_detail_empty(empty: bool) -> void:
	if not _detail_empty:
		return
	_detail_empty.visible = empty
	_detail_title.visible = not empty
	_detail_meta.visible = not empty
	_detail_status.visible = not empty
	_buy_button.visible = (not empty) and _current_tab == TAB_BROWSE
	_cancel_button.visible = (not empty) and _current_tab == TAB_MY


# === Internal callbacks ===

func _on_tab_browse_pressed() -> void:
	if _current_tab == TAB_BROWSE:
		_tab_browse_btn.button_pressed = true
		return
	emit_signal("tab_changed", TAB_BROWSE)


func _on_tab_my_pressed() -> void:
	if _current_tab == TAB_MY:
		_tab_my_btn.button_pressed = true
		return
	emit_signal("tab_changed", TAB_MY)


func _on_filter_pressed(category: String) -> void:
	for cid in _filter_buttons.keys():
		_filter_buttons[cid].button_pressed = (cid == category)
	if category != _current_category:
		emit_signal("filter_changed", category)


func _on_sort_pressed() -> void:
	var idx: int = SORT_ORDER.find(_current_sort)
	var next_sort: String = SORT_ORDER[(idx + 1) % SORT_ORDER.size()]
	emit_signal("sort_changed", next_sort)


func _on_refresh_pressed() -> void:
	emit_signal("refresh_requested")


func _on_prev_pressed() -> void:
	emit_signal("page_prev_pressed")


func _on_next_pressed() -> void:
	emit_signal("page_next_pressed")


func _on_listing_pressed(index: int) -> void:
	if index < 0 or index >= _listings.size():
		return
	_selected_index = index
	# Re-sync row toggle state — only the selected row stays pressed
	_refresh_row_toggles()
	emit_signal("listing_clicked", _listings[index], index)


func _refresh_row_toggles() -> void:
	var row_idx := 0
	for child in _listings_vbox.get_children():
		if child is Button:
			(child as Button).button_pressed = (row_idx == _selected_index)
			row_idx += 1


func _on_buy_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _listings.size():
		return
	emit_signal("buy_pressed", _listings[_selected_index])


func _on_cancel_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _listings.size():
		return
	emit_signal("cancel_listing_pressed", _listings[_selected_index], _selected_index)


func _on_pull_all_pressed() -> void:
	emit_signal("pull_all_pressed")


func _on_list_menu_pressed() -> void:
	if not _list_menu:
		return
	var pos: Vector2 = _list_button.global_position + Vector2(0, _list_button.size.y)
	_list_menu.position = Vector2i(pos)
	_list_menu.popup()


func _on_list_menu_item_pressed(item_id: int) -> void:
	# id_pressed sends the explicit id we assigned when building the menu —
	# which is the index into LIST_MENU_ITEMS. Direct lookup, no separator
	# bookkeeping. Separators are not clickable so we shouldn't get one,
	# but guard anyway.
	if item_id < 0 or item_id >= LIST_MENU_ITEMS.size():
		return
	var entry = LIST_MENU_ITEMS[item_id]
	if entry["id"] == "_separator":
		return
	emit_signal("list_action_pressed", entry["id"])


func _on_close_pressed() -> void:
	emit_signal("close_requested")
