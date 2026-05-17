extends Control
class_name CompanionsPanel

# Tabbed surface for the More → Companions and More → Eggs screens.
# - Companions tab: active section + grid of collected companions; click to
#   activate, right-click for inspect/release.
# - Eggs tab: grid of egg cards; click to toggle freeze.
# Inspect view replaces the body with full text details.

signal close_requested
signal tab_changed(tab_id: String)
signal companion_activated(companion_id: String)
signal companion_inspect_requested(companion: Dictionary)
signal companion_release_requested(companion: Dictionary)
signal companion_dismiss_requested
signal egg_freeze_toggled(egg_index: int)
signal sort_changed(sort_option: String, ascending: bool)
signal inspect_back_requested

const TAB_COMPANIONS := "companions"
const TAB_EGGS := "eggs"

const SORT_OPTIONS := ["level", "tier", "variant", "damage", "name", "type"]

var client_ref = null

var _current_tab: String = TAB_COMPANIONS
var _companions: Array = []
var _active_companion: Dictionary = {}
var _eggs: Array = []
var _egg_capacity: int = 3
var _sort_option: String = "level"
var _sort_ascending: bool = false
var _inspect_view: Dictionary = {}

var _root_panel: PanelContainer
var _title_label: Label
var _tab_companions_btn: Button
var _tab_eggs_btn: Button
var _capacity_label: RichTextLabel
var _sort_button: Button
var _asc_button: Button

# Companions tab nodes
var _companions_tab: VBoxContainer
var _active_section: PanelContainer
var _active_label: RichTextLabel
var _active_abilities: RichTextLabel
var _dismiss_button: Button
var _no_active_label: Label
var _companion_grid: HFlowContainer
var _companion_empty: Label

# Eggs tab nodes
var _eggs_tab: VBoxContainer
var _egg_grid: HFlowContainer
var _egg_empty: Label

# Inspect view (replaces both tabs when active)
var _inspect_root: VBoxContainer
var _inspect_text: RichTextLabel
var _inspect_back_btn: Button
var _release_button: Button

# Right-click context menu for companion cards
var _ctx_menu: PopupMenu
var _ctx_companion: Dictionary = {}

# Hover tooltip — top_level Control so it can escape the panel's clip_contents.
# Mirrors the inventory_panel pattern; monospace font is required so the
# companion ASCII art rows in the tooltip body line up.
var _tooltip: PanelContainer
var _tooltip_label: RichTextLabel

const CTX_INSPECT := 1
const CTX_RELEASE := 2
const CTX_ACTIVATE := 3


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	_build_layout()
	visible = false


func _notification(what: int) -> void:
	# Hide the hover tooltip whenever the panel itself becomes hidden — otherwise
	# the top_level tooltip would linger on screen after the panel closes.
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_hide_tooltip()


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
	_title_label.text = "Companions"
	_title_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_title_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_title_label)

	_capacity_label = RichTextLabel.new()
	_capacity_label.bbcode_enabled = true
	_capacity_label.fit_content = true
	_capacity_label.scroll_active = false
	_capacity_label.add_theme_font_size_override("normal_font_size", 14)
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity_label.custom_minimum_size = Vector2(0, 22)
	header.add_child(_capacity_label)

	# Tabs
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(tab_row)

	_tab_companions_btn = _make_tab_button("Companions", _on_tab_companions_pressed)
	_tab_eggs_btn = _make_tab_button("Eggs", _on_tab_eggs_pressed)
	tab_row.add_child(_tab_companions_btn)
	tab_row.add_child(_tab_eggs_btn)

	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_spacer)

	_sort_button = _make_action_btn("Sort: Level", _on_sort_pressed)
	_sort_button.custom_minimum_size = Vector2(140, 28)
	tab_row.add_child(_sort_button)

	_asc_button = _make_action_btn("▼", _on_asc_pressed)
	_asc_button.custom_minimum_size = Vector2(36, 28)
	tab_row.add_child(_asc_button)

	# Companions tab body
	_companions_tab = VBoxContainer.new()
	_companions_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_companions_tab.add_theme_constant_override("separation", 6)
	root_vbox.add_child(_companions_tab)

	# Active companion section
	_active_section = _make_subpanel()
	_companions_tab.add_child(_active_section)

	var active_vbox := VBoxContainer.new()
	active_vbox.add_theme_constant_override("separation", 4)
	_active_section.add_child(active_vbox)

	_active_label = RichTextLabel.new()
	_active_label.bbcode_enabled = true
	_active_label.fit_content = true
	_active_label.scroll_active = false
	_active_label.add_theme_font_size_override("normal_font_size", 14)
	_active_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_vbox.add_child(_active_label)

	_active_abilities = RichTextLabel.new()
	_active_abilities.bbcode_enabled = true
	_active_abilities.fit_content = true
	_active_abilities.scroll_active = false
	_active_abilities.add_theme_font_size_override("normal_font_size", 13)
	_active_abilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_vbox.add_child(_active_abilities)

	var active_action_row := HBoxContainer.new()
	active_action_row.add_theme_constant_override("separation", 8)
	active_vbox.add_child(active_action_row)

	_dismiss_button = _make_action_btn("Dismiss", _on_dismiss_pressed)
	active_action_row.add_child(_dismiss_button)

	var active_spacer := Control.new()
	active_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_action_row.add_child(active_spacer)

	_no_active_label = Label.new()
	_no_active_label.text = "No active companion — click one below to deploy"
	_no_active_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_no_active_label.add_theme_font_size_override("font_size", 13)
	_companions_tab.add_child(_no_active_label)

	# Companion grid (scrollable)
	var grid_panel := _make_subpanel()
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_companions_tab.add_child(grid_panel)

	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_panel.add_child(grid_scroll)

	_companion_grid = HFlowContainer.new()
	_companion_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_companion_grid.add_theme_constant_override("h_separation", 6)
	_companion_grid.add_theme_constant_override("v_separation", 6)
	grid_scroll.add_child(_companion_grid)

	_companion_empty = Label.new()
	_companion_empty.text = "No hatched companions yet."
	_companion_empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_companion_empty.add_theme_font_size_override("font_size", 13)
	_companion_empty.visible = false
	_companion_grid.add_child(_companion_empty)

	# Eggs tab body
	_eggs_tab = VBoxContainer.new()
	_eggs_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_eggs_tab.add_theme_constant_override("separation", 6)
	root_vbox.add_child(_eggs_tab)

	var egg_panel := _make_subpanel()
	egg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	egg_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_eggs_tab.add_child(egg_panel)

	var egg_scroll := ScrollContainer.new()
	egg_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	egg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	egg_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	egg_panel.add_child(egg_scroll)

	_egg_grid = HFlowContainer.new()
	_egg_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_egg_grid.add_theme_constant_override("h_separation", 8)
	_egg_grid.add_theme_constant_override("v_separation", 8)
	egg_scroll.add_child(_egg_grid)

	_egg_empty = Label.new()
	_egg_empty.text = "No eggs incubating."
	_egg_empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_egg_empty.add_theme_font_size_override("font_size", 13)
	_egg_empty.visible = false
	_egg_grid.add_child(_egg_empty)

	# Inspect view (initially hidden)
	_inspect_root = VBoxContainer.new()
	_inspect_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspect_root.add_theme_constant_override("separation", 6)
	_inspect_root.visible = false
	root_vbox.add_child(_inspect_root)

	var inspect_panel := _make_subpanel()
	inspect_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspect_root.add_child(inspect_panel)

	var inspect_scroll := ScrollContainer.new()
	inspect_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspect_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspect_panel.add_child(inspect_scroll)

	_inspect_text = RichTextLabel.new()
	_inspect_text.bbcode_enabled = true
	_inspect_text.fit_content = true
	_inspect_text.scroll_active = false
	_inspect_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspect_text.add_theme_font_size_override("normal_font_size", 14)
	# Monospaced font is required so the ASCII art (rendered in the right
	# column of the inspect view) lines up correctly. Without this the
	# default proportional font skews each row of the art.
	var mono_path := "res://font/Consolas/consolas.ttf"
	if ResourceLoader.exists(mono_path):
		var mono_font: FontFile = load(mono_path)
		if mono_font:
			_inspect_text.add_theme_font_override("normal_font", mono_font)
			_inspect_text.add_theme_font_override("bold_font", mono_font)
			_inspect_text.add_theme_font_override("italics_font", mono_font)
			_inspect_text.add_theme_font_override("mono_font", mono_font)
	inspect_scroll.add_child(_inspect_text)

	var inspect_action_row := HBoxContainer.new()
	inspect_action_row.add_theme_constant_override("separation", 8)
	_inspect_root.add_child(inspect_action_row)

	_inspect_back_btn = _make_action_btn("◀ Back", _on_inspect_back_pressed)
	inspect_action_row.add_child(_inspect_back_btn)

	_release_button = _make_action_btn("Release", _on_release_pressed)
	_release_button.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	inspect_action_row.add_child(_release_button)

	var inspect_spacer := Control.new()
	inspect_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect_action_row.add_child(inspect_spacer)

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

	# Hover tooltip — top_level so it extends beyond the panel's clip bounds.
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
	# Disable word-wrap so wide ASCII art rows extend the tooltip horizontally
	# instead of getting wrapped (which destroys column alignment). Width then
	# grows to fit the widest line; non-art lines stay readable since they're
	# pre-formatted to be short.
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tooltip_label.custom_minimum_size = Vector2(320, 0)
	# Monospace font so ASCII art rendered inside the tooltip body lines up.
	var tip_mono_path := "res://font/Consolas/consolas.ttf"
	if ResourceLoader.exists(tip_mono_path):
		var tip_mono_font: FontFile = load(tip_mono_path)
		if tip_mono_font:
			_tooltip_label.add_theme_font_override("normal_font", tip_mono_font)
			_tooltip_label.add_theme_font_override("bold_font", tip_mono_font)
			_tooltip_label.add_theme_font_override("italics_font", tip_mono_font)
			_tooltip_label.add_theme_font_override("mono_font", tip_mono_font)
	_tooltip.add_child(_tooltip_label)

	_set_tab(TAB_COMPANIONS)
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

func populate_companions(companions: Array, active_companion: Dictionary, sort_option: String, sort_ascending: bool) -> void:
	if not is_inside_tree():
		return
	_current_tab = TAB_COMPANIONS
	_companions = companions
	_active_companion = active_companion
	_sort_option = sort_option
	_sort_ascending = sort_ascending
	_inspect_view = {}
	_set_tab(TAB_COMPANIONS)
	_update_header()
	_update_tab_styles()
	_update_sort_buttons()
	_rebuild_active_section()
	_rebuild_companion_grid()


func populate_eggs(eggs: Array, capacity: int) -> void:
	if not is_inside_tree():
		return
	_current_tab = TAB_EGGS
	_eggs = eggs
	_egg_capacity = capacity
	_inspect_view = {}
	_set_tab(TAB_EGGS)
	_update_header()
	_update_tab_styles()
	_rebuild_egg_grid()


func show_inspect(companion: Dictionary, inspect_text_bbcode: String) -> void:
	if not is_inside_tree():
		return
	_inspect_view = companion
	_inspect_text.text = inspect_text_bbcode
	_show_inspect_view(true)


func clear_inspect() -> void:
	_inspect_view = {}
	_show_inspect_view(false)


# === Internal rendering ===

func _set_tab(tab: String) -> void:
	_companions_tab.visible = (tab == TAB_COMPANIONS) and _inspect_view.is_empty()
	_eggs_tab.visible = (tab == TAB_EGGS) and _inspect_view.is_empty()
	_inspect_root.visible = not _inspect_view.is_empty()


func _show_inspect_view(active: bool) -> void:
	if active:
		_hide_tooltip()
	_inspect_root.visible = active
	_companions_tab.visible = (not active) and _current_tab == TAB_COMPANIONS
	_eggs_tab.visible = (not active) and _current_tab == TAB_EGGS


func _update_header() -> void:
	if _current_tab == TAB_COMPANIONS:
		_title_label.text = "Companions"
		_capacity_label.text = "[color=#808080]Hatched: %d[/color]" % _companions.size()
	else:
		_title_label.text = "Eggs"
		_capacity_label.text = "[color=#FFAA00]Incubating: %d / %d[/color]" % [_eggs.size(), _egg_capacity]


func _update_tab_styles() -> void:
	_tab_companions_btn.button_pressed = (_current_tab == TAB_COMPANIONS)
	_tab_eggs_btn.button_pressed = (_current_tab == TAB_EGGS)


func _update_sort_buttons() -> void:
	_sort_button.text = "Sort: %s" % _sort_option.capitalize()
	_asc_button.text = "▲" if _sort_ascending else "▼"
	# Sort controls only meaningful on the Companions tab
	_sort_button.visible = (_current_tab == TAB_COMPANIONS)
	_asc_button.visible = (_current_tab == TAB_COMPANIONS)


func _rebuild_active_section() -> void:
	if _active_companion.is_empty():
		_active_section.visible = false
		_no_active_label.visible = true
		return
	_active_section.visible = true
	_no_active_label.visible = false

	var c := _active_companion
	var name = str(c.get("name", "Unknown"))
	var level = int(c.get("level", 1))
	var tier = int(c.get("tier", 1))
	var sub_tier = int(c.get("sub_tier", 1))
	var variant = str(c.get("variant", "Normal"))
	var variant_color = str(c.get("variant_color", "#FFFFFF"))
	var rarity_color = "#FFFFFF"
	var rarity_tag = ""
	if client_ref and client_ref.has_method("_get_variant_rarity_info"):
		var info: Dictionary = client_ref._get_variant_rarity_info(variant)
		rarity_color = str(info.get("color", "#FFFFFF"))
		rarity_tag = str(info.get("tier", ""))

	var lines: Array = []
	var rarity_prefix = ""
	if rarity_tag != "":
		rarity_prefix = "[color=%s][%s][/color] " % [rarity_color, rarity_tag]
	lines.append("[color=#00FFFF]Active:[/color] %s[color=%s]★ %s %s[/color] [color=#AAAAAA](Lv %d, T%d-%d)[/color]" % [rarity_prefix, variant_color, variant, name, level, tier, sub_tier])

	# XP bar
	if level < 10000:
		var xp = int(c.get("xp", 0))
		var xp_to_next = int(pow(level + 1, 2.0) * 15)
		var pct = int((float(xp) / float(xp_to_next)) * 100) if xp_to_next > 0 else 0
		var bar_filled := int(20 * pct / 100)
		var bar_text = "[" + "█".repeat(bar_filled) + "░".repeat(20 - bar_filled) + "]"
		lines.append("[color=#00FF00]XP %s %d%%[/color] [color=#808080](%d / %d)[/color]" % [bar_text, pct, xp, xp_to_next])
	else:
		lines.append("[color=#FFD700]MAX LEVEL[/color]")

	_active_label.text = "\n".join(lines)

	# Abilities — keep concise: list unlocked names only
	if client_ref and client_ref.has_method("_format_companion_abilities_summary"):
		_active_abilities.text = str(client_ref._format_companion_abilities_summary(c))
	else:
		_active_abilities.text = ""


func _rebuild_companion_grid() -> void:
	_hide_tooltip()
	for child in _companion_grid.get_children():
		if child == _companion_empty:
			continue
		child.queue_free()
	if _companions.is_empty():
		_companion_empty.visible = true
		return
	_companion_empty.visible = false

	var sorted := _sort_companions(_companions)
	# Re-store sorted array so signal indices map back
	_companions = sorted

	var active_id = ""
	if not _active_companion.is_empty():
		active_id = str(_active_companion.get("id", ""))

	for i in range(sorted.size()):
		var c = sorted[i]
		var card := _make_companion_card(c, str(c.get("id", "")) == active_id, i)
		_companion_grid.add_child(card)


func _make_companion_card(c: Dictionary, is_active: bool, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if is_active:
		sb.bg_color = Color(0.12, 0.16, 0.12, 0.95)
		sb.border_color = Color(0.0, 1.0, 1.0, 0.9)
	else:
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.95)
		sb.border_color = Color(0.4, 0.34, 0.25, 0.7)
	sb.set_border_width_all(2 if is_active else 1)
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
	var active_marker = "[color=#00FFFF]★[/color] " if is_active else ""
	# v0.9.490 — surface registration status on the card. Active companion
	# carries `house_slot` >= 0 when checked out from a registered slot
	# (see character.gd `_check_out_registered_companion`).
	var registered_marker = ""
	if is_active and int(c.get("house_slot", -1)) >= 0:
		registered_marker = "[color=#FF80FF][REG][/color] "
	name_lbl.text = "%s%s%s[color=%s]%s[/color]" % [active_marker, registered_marker, rarity_prefix, variant_color, name]
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
	var bonus_text = ""
	if client_ref and client_ref.has_method("_get_companion_card_bonus_summary"):
		bonus_text = str(client_ref._get_companion_card_bonus_summary(c))
	bonuses.text = bonus_text
	vbox.add_child(bonuses)

	# Capture click events on the card itself
	card.gui_input.connect(_on_companion_card_input.bind(c, index))
	# Hover tooltip — show formatted companion preview while mouse is over the card.
	card.mouse_entered.connect(_on_companion_card_mouse_entered.bind(c, card))
	card.mouse_exited.connect(_hide_tooltip)
	return card


# === Hover tooltip ===

func _on_companion_card_mouse_entered(companion: Dictionary, anchor: Control) -> void:
	if client_ref == null or not client_ref.has_method("format_companion_tooltip_bbcode"):
		return
	var bbcode: String = str(client_ref.format_companion_tooltip_bbcode(companion))
	_show_tooltip_with(bbcode, anchor)


func _on_egg_card_mouse_entered(egg: Dictionary, anchor: Control) -> void:
	if client_ref == null or not client_ref.has_method("format_egg_tooltip_bbcode"):
		return
	var bbcode: String = str(client_ref.format_egg_tooltip_bbcode(egg))
	_show_tooltip_with(bbcode, anchor)


func _show_tooltip_with(bbcode: String, anchor: Control) -> void:
	if bbcode == "" or _tooltip == null or _tooltip_label == null:
		return
	_tooltip_label.text = bbcode
	# Reset so the tooltip shrinks back to fit shorter content (otherwise it keeps
	# the height of whatever previous, taller tooltip set it).
	_tooltip.size = Vector2.ZERO
	_tooltip.visible = true
	await get_tree().process_frame
	if not is_instance_valid(_tooltip) or not _tooltip.visible:
		return
	_tooltip.reset_size()
	var vp: Vector2 = get_viewport_rect().size
	var anchor_rect := Rect2(anchor.global_position, anchor.size)
	var tip_size: Vector2 = _tooltip.size
	var pos := Vector2(anchor_rect.position.x + anchor_rect.size.x + 6, anchor_rect.position.y)
	if pos.x + tip_size.x > vp.x - 4:
		pos.x = max(4.0, anchor_rect.position.x - tip_size.x - 6)
	if pos.y + tip_size.y > vp.y - 4:
		pos.y = max(4.0, vp.y - tip_size.y - 4)
	_tooltip.global_position = pos


func _hide_tooltip() -> void:
	if _tooltip:
		_tooltip.visible = false


func _on_companion_card_input(event: InputEvent, companion: Dictionary, _index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Click to activate (only if not already active)
			var active_id = str(_active_companion.get("id", ""))
			var clicked_id = str(companion.get("id", ""))
			if clicked_id != active_id:
				emit_signal("companion_activated", clicked_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_open_ctx_menu(companion, event.global_position)


func _open_ctx_menu(companion: Dictionary, screen_pos: Vector2) -> void:
	_hide_tooltip()
	_ctx_companion = companion
	_ctx_menu.clear()
	var clicked_id = str(companion.get("id", ""))
	var active_id = str(_active_companion.get("id", ""))
	if clicked_id != active_id:
		_ctx_menu.add_item("Activate", CTX_ACTIVATE)
	_ctx_menu.add_item("Inspect", CTX_INSPECT)
	_ctx_menu.add_item("Release...", CTX_RELEASE)
	_ctx_menu.position = Vector2i(screen_pos)
	_ctx_menu.popup()


func _on_ctx_menu_id_pressed(id: int) -> void:
	if _ctx_companion.is_empty():
		return
	match id:
		CTX_ACTIVATE:
			emit_signal("companion_activated", str(_ctx_companion.get("id", "")))
		CTX_INSPECT:
			emit_signal("companion_inspect_requested", _ctx_companion)
		CTX_RELEASE:
			emit_signal("companion_release_requested", _ctx_companion)
	_ctx_companion = {}


func _sort_companions(companions: Array) -> Array:
	if client_ref and client_ref.has_method("_sort_companions"):
		return client_ref._sort_companions(companions)
	# Fallback: sort by level desc
	var dup := companions.duplicate()
	dup.sort_custom(func(a, b):
		return int(b.get("level", 0)) > int(a.get("level", 0)) if not _sort_ascending else int(a.get("level", 0)) > int(b.get("level", 0)))
	return dup


func _rebuild_egg_grid() -> void:
	_hide_tooltip()
	for child in _egg_grid.get_children():
		if child == _egg_empty:
			continue
		child.queue_free()
	if _eggs.is_empty():
		_egg_empty.visible = true
		return
	_egg_empty.visible = false

	for i in range(_eggs.size()):
		var card := _make_egg_card(_eggs[i], i)
		_egg_grid.add_child(card)


func _make_egg_card(egg: Dictionary, index: int) -> PanelContainer:
	var is_frozen: bool = bool(egg.get("frozen", false))
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.95)
	sb.border_color = Color(0.0, 0.75, 1.0, 0.85) if is_frozen else Color(0.4, 0.34, 0.25, 0.7)
	sb.set_border_width_all(2 if is_frozen else 1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(260, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	# Egg art
	var art_lbl := RichTextLabel.new()
	art_lbl.bbcode_enabled = true
	art_lbl.fit_content = true
	art_lbl.scroll_active = false
	art_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_lbl.add_theme_font_size_override("normal_font_size", 12)
	var variant = str(egg.get("variant", "Normal"))
	var color1 = str(egg.get("variant_color", "#FFAA00"))
	var color2 = str(egg.get("variant_color2", ""))
	var pattern = str(egg.get("variant_pattern", "solid"))
	var art_text := ""
	if client_ref and client_ref.has_method("_get_egg_art_for_panel"):
		art_text = str(client_ref._get_egg_art_for_panel(variant, color1, color2, pattern))
	art_lbl.text = art_text
	vbox.add_child(art_lbl)

	# Name + tier
	var name_lbl := RichTextLabel.new()
	name_lbl.bbcode_enabled = true
	name_lbl.fit_content = true
	name_lbl.scroll_active = false
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("normal_font_size", 13)
	var egg_name = str(egg.get("companion_name", "Unknown"))
	var tier = int(egg.get("tier", 1))
	var sub_tier = int(egg.get("sub_tier", 1))
	var rarity_color = "#FFFFFF"
	var rarity_tag = ""
	if client_ref and client_ref.has_method("_get_variant_rarity_info"):
		var info: Dictionary = client_ref._get_variant_rarity_info(variant)
		rarity_color = str(info.get("color", "#FFFFFF"))
		rarity_tag = str(info.get("tier", ""))
	var rarity_prefix := ("[color=%s][%s][/color] " % [rarity_color, rarity_tag]) if rarity_tag != "" else ""
	var frozen_tag = "  [color=#00BFFF][FROZEN][/color]" if is_frozen else ""
	name_lbl.text = "%s[color=%s]%s %s Egg[/color] [color=#808080](T%d-%d)[/color]%s" % [rarity_prefix, color1, variant, egg_name, tier, sub_tier, frozen_tag]
	vbox.add_child(name_lbl)

	# Progress
	var progress_lbl := RichTextLabel.new()
	progress_lbl.bbcode_enabled = true
	progress_lbl.fit_content = true
	progress_lbl.scroll_active = false
	progress_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_lbl.add_theme_font_size_override("normal_font_size", 12)
	var required = int(egg.get("steps_required", egg.get("hatch_steps", 1000)))
	var steps = int(egg.get("steps_taken", 0))
	if steps == 0 and egg.has("steps_remaining") and egg.has("hatch_steps"):
		steps = int(egg.get("hatch_steps", 1000)) - int(egg.get("steps_remaining", 1000))
	var pct := 0
	if required > 0:
		pct = int((float(steps) / float(required)) * 100)
	pct = clampi(pct, 0, 100)
	var bar_filled := int(16 * pct / 100)
	var bar_text := "[" + "█".repeat(bar_filled) + "░".repeat(16 - bar_filled) + "]"
	var color_tag := "#00BFFF" if is_frozen else "#AAAAAA"
	var status_tag := " - PAUSED" if is_frozen else ""
	progress_lbl.text = "[color=%s]%s %d%% (%d/%d)%s[/color]" % [color_tag, bar_text, pct, steps, required, status_tag]
	vbox.add_child(progress_lbl)

	# Click to toggle freeze
	card.gui_input.connect(_on_egg_card_input.bind(index))
	# Hover tooltip — show ability/hatch-target preview for the egg.
	card.mouse_entered.connect(_on_egg_card_mouse_entered.bind(egg, card))
	card.mouse_exited.connect(_hide_tooltip)
	return card


func _on_egg_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("egg_freeze_toggled", index)


# === Internal callbacks ===

func _on_tab_companions_pressed() -> void:
	if _current_tab == TAB_COMPANIONS:
		_tab_companions_btn.button_pressed = true
		return
	emit_signal("tab_changed", TAB_COMPANIONS)


func _on_tab_eggs_pressed() -> void:
	if _current_tab == TAB_EGGS:
		_tab_eggs_btn.button_pressed = true
		return
	emit_signal("tab_changed", TAB_EGGS)


func _on_sort_pressed() -> void:
	var idx: int = SORT_OPTIONS.find(_sort_option)
	var next_sort: String = SORT_OPTIONS[(idx + 1) % SORT_OPTIONS.size()]
	emit_signal("sort_changed", next_sort, _sort_ascending)


func _on_asc_pressed() -> void:
	emit_signal("sort_changed", _sort_option, not _sort_ascending)


func _on_dismiss_pressed() -> void:
	emit_signal("companion_dismiss_requested")


func _on_release_pressed() -> void:
	if _inspect_view.is_empty():
		return
	emit_signal("companion_release_requested", _inspect_view)


func _on_inspect_back_pressed() -> void:
	clear_inspect()
	emit_signal("inspect_back_requested")


func _on_close_pressed() -> void:
	emit_signal("close_requested")
