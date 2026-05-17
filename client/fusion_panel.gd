extends Control
class_name FusionPanel

# Visual surface for the F-tile (Fusion Station) sub-mode of the Sanctuary.
# Three tabs:
# - Same Type: list of fuseable groups (3 same monster + sub-tier → 1 higher
#   sub-tier). Click a group → confirm → fuse the first 3 in the group.
# - Mixed T9: grid of all sub-tier 8 companions. Click cards to toggle
#   selection (up to 8). Fuse button activates when exactly 8 are selected.
# - Hybrid (Audit #4 Slice 4): grid of companions at sub-tier 5+. Pick
#   exactly 2 of DIFFERENT monster_types, consumes 1 Hybrid Catalyst from
#   inventory, produces a hybrid that blends bonuses + abilities.

signal close_requested
signal tab_changed(tab_id: String)
signal same_fusion_pressed(indices: Array)
signal mixed_fusion_pressed(indices: Array)
signal hybrid_fusion_pressed(indices: Array)

const TAB_SAME := "same"
const TAB_MIXED := "mixed"
const TAB_HYBRID := "hybrid"

var client_ref = null

var _current_tab: String = TAB_SAME
var _groups: Array = []
var _t8_companions: Array = []
var _hybrid_candidates: Array = []
var _catalyst_count: int = 0
var _mixed_selected: Array = []
var _hybrid_selected: Array = []

var _root_panel: PanelContainer
var _title_label: Label
var _tab_same_btn: Button
var _tab_mixed_btn: Button
var _tab_hybrid_btn: Button
var _summary_label: RichTextLabel

# Same-Type tab nodes
var _same_tab: VBoxContainer
var _same_list_vbox: VBoxContainer
var _same_empty_label: Label

# Mixed T9 tab nodes
var _mixed_tab: VBoxContainer
var _mixed_count_label: RichTextLabel
var _mixed_grid: HFlowContainer
var _mixed_empty_label: Label
var _mixed_fuse_btn: Button
var _mixed_clear_btn: Button

# Hybrid tab nodes
var _hybrid_tab: VBoxContainer
var _hybrid_count_label: RichTextLabel
var _hybrid_grid: HFlowContainer
var _hybrid_empty_label: Label
var _hybrid_fuse_btn: Button
var _hybrid_clear_btn: Button

var _same_confirm_dialog: ConfirmationDialog
var _pending_same_indices: Array = []
var _pending_same_label: String = ""

var _mixed_confirm_dialog: ConfirmationDialog
var _hybrid_confirm_dialog: ConfirmationDialog

# Audit #15 v0.9.515 — reusable HelpPanel attached to the header ? Help button.
var _help_panel: HelpPanel


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

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Sanctuary — Fusion Station"
	_title_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
	_title_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_title_label)

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.scroll_active = false
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.custom_minimum_size = Vector2(0, 22)
	_summary_label.add_theme_font_size_override("normal_font_size", 13)
	header.add_child(_summary_label)

	# Audit #15 v0.9.515 — Help button.
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("fusion_panel", _help_panel)
	header.add_child(help_btn)

	# Tabs
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	root_vbox.add_child(tab_row)

	_tab_same_btn = _make_tab_button("Same Type", _on_tab_same_pressed)
	_tab_mixed_btn = _make_tab_button("Mixed T9", _on_tab_mixed_pressed)
	_tab_hybrid_btn = _make_tab_button("Hybrid", _on_tab_hybrid_pressed)
	tab_row.add_child(_tab_same_btn)
	tab_row.add_child(_tab_mixed_btn)
	tab_row.add_child(_tab_hybrid_btn)

	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_spacer)

	# Same-Type tab body
	_same_tab = VBoxContainer.new()
	_same_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_same_tab.add_theme_constant_override("separation", 6)
	root_vbox.add_child(_same_tab)

	var same_hint := RichTextLabel.new()
	same_hint.bbcode_enabled = true
	same_hint.fit_content = true
	same_hint.scroll_active = false
	same_hint.add_theme_font_size_override("normal_font_size", 12)
	same_hint.text = "[color=#888888]3 same-type companions at the same sub-tier → 1 companion at the next sub-tier (max T9). The 3 inputs are destroyed.[/color]"
	_same_tab.add_child(same_hint)

	var same_panel := _make_subpanel()
	same_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	same_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_same_tab.add_child(same_panel)

	var same_scroll := ScrollContainer.new()
	same_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	same_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	same_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	same_panel.add_child(same_scroll)

	_same_list_vbox = VBoxContainer.new()
	_same_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_same_list_vbox.add_theme_constant_override("separation", 4)
	same_scroll.add_child(_same_list_vbox)

	_same_empty_label = Label.new()
	_same_empty_label.text = "No fuseable groups yet — need 3+ companions of the same type and sub-tier in the kennel."
	_same_empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_same_empty_label.add_theme_font_size_override("font_size", 13)
	_same_empty_label.visible = false
	_same_list_vbox.add_child(_same_empty_label)

	# Mixed T9 tab body
	_mixed_tab = VBoxContainer.new()
	_mixed_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mixed_tab.add_theme_constant_override("separation", 6)
	root_vbox.add_child(_mixed_tab)

	var mixed_hint := RichTextLabel.new()
	mixed_hint.bbcode_enabled = true
	mixed_hint.fit_content = true
	mixed_hint.scroll_active = false
	mixed_hint.add_theme_font_size_override("normal_font_size", 12)
	mixed_hint.text = "[color=#888888]Combine 8 sub-tier 8 companions of any type into 1 random T9 companion. All 8 inputs are destroyed.[/color]"
	_mixed_tab.add_child(mixed_hint)

	var mixed_count_row := HBoxContainer.new()
	mixed_count_row.add_theme_constant_override("separation", 8)
	_mixed_tab.add_child(mixed_count_row)

	_mixed_count_label = RichTextLabel.new()
	_mixed_count_label.bbcode_enabled = true
	_mixed_count_label.fit_content = true
	_mixed_count_label.scroll_active = false
	_mixed_count_label.add_theme_font_size_override("normal_font_size", 14)
	_mixed_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mixed_count_row.add_child(_mixed_count_label)

	_mixed_clear_btn = Button.new()
	_mixed_clear_btn.text = "Clear"
	_mixed_clear_btn.focus_mode = Control.FOCUS_NONE
	_mixed_clear_btn.add_theme_font_size_override("font_size", 12)
	_mixed_clear_btn.custom_minimum_size = Vector2(80, 28)
	_mixed_clear_btn.pressed.connect(_on_mixed_clear_pressed)
	mixed_count_row.add_child(_mixed_clear_btn)

	_mixed_fuse_btn = Button.new()
	_mixed_fuse_btn.text = "Fuse!"
	_mixed_fuse_btn.focus_mode = Control.FOCUS_NONE
	_mixed_fuse_btn.add_theme_font_size_override("font_size", 13)
	_mixed_fuse_btn.custom_minimum_size = Vector2(120, 28)
	_mixed_fuse_btn.disabled = true
	_mixed_fuse_btn.pressed.connect(_on_mixed_fuse_pressed)
	mixed_count_row.add_child(_mixed_fuse_btn)

	var mixed_panel := _make_subpanel()
	mixed_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mixed_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mixed_tab.add_child(mixed_panel)

	var mixed_scroll := ScrollContainer.new()
	mixed_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mixed_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mixed_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mixed_panel.add_child(mixed_scroll)

	_mixed_grid = HFlowContainer.new()
	_mixed_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mixed_grid.add_theme_constant_override("h_separation", 6)
	_mixed_grid.add_theme_constant_override("v_separation", 6)
	mixed_scroll.add_child(_mixed_grid)

	_mixed_empty_label = Label.new()
	_mixed_empty_label.text = "No sub-tier 8 companions in the kennel yet."
	_mixed_empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_mixed_empty_label.add_theme_font_size_override("font_size", 13)
	_mixed_empty_label.visible = false
	_mixed_grid.add_child(_mixed_empty_label)

	# Hybrid tab body
	_hybrid_tab = VBoxContainer.new()
	_hybrid_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hybrid_tab.add_theme_constant_override("separation", 6)
	root_vbox.add_child(_hybrid_tab)

	var hybrid_hint := RichTextLabel.new()
	hybrid_hint.bbcode_enabled = true
	hybrid_hint.fit_content = true
	hybrid_hint.scroll_active = false
	hybrid_hint.add_theme_font_size_override("normal_font_size", 12)
	hybrid_hint.text = "[color=#888888]Pick 2 companions of [color=#FF66FF]different monster types[/color], both at sub-tier 5+. Costs 1 [color=#FFD700]Hybrid Catalyst[/color] (T5+ chest drop). Output: tier = max(parents), sub-tier 1, bonuses averaged +10% hybrid vigor, threshold ability inherited from parent B.[/color]"
	_hybrid_tab.add_child(hybrid_hint)

	var hybrid_count_row := HBoxContainer.new()
	hybrid_count_row.add_theme_constant_override("separation", 8)
	_hybrid_tab.add_child(hybrid_count_row)

	_hybrid_count_label = RichTextLabel.new()
	_hybrid_count_label.bbcode_enabled = true
	_hybrid_count_label.fit_content = true
	_hybrid_count_label.scroll_active = false
	_hybrid_count_label.add_theme_font_size_override("normal_font_size", 14)
	_hybrid_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hybrid_count_row.add_child(_hybrid_count_label)

	_hybrid_clear_btn = Button.new()
	_hybrid_clear_btn.text = "Clear"
	_hybrid_clear_btn.focus_mode = Control.FOCUS_NONE
	_hybrid_clear_btn.add_theme_font_size_override("font_size", 12)
	_hybrid_clear_btn.custom_minimum_size = Vector2(80, 28)
	_hybrid_clear_btn.pressed.connect(_on_hybrid_clear_pressed)
	hybrid_count_row.add_child(_hybrid_clear_btn)

	_hybrid_fuse_btn = Button.new()
	_hybrid_fuse_btn.text = "Fuse!"
	_hybrid_fuse_btn.focus_mode = Control.FOCUS_NONE
	_hybrid_fuse_btn.add_theme_font_size_override("font_size", 13)
	_hybrid_fuse_btn.custom_minimum_size = Vector2(120, 28)
	_hybrid_fuse_btn.disabled = true
	_hybrid_fuse_btn.pressed.connect(_on_hybrid_fuse_pressed)
	hybrid_count_row.add_child(_hybrid_fuse_btn)

	var hybrid_panel := _make_subpanel()
	hybrid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hybrid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hybrid_tab.add_child(hybrid_panel)

	var hybrid_scroll := ScrollContainer.new()
	hybrid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hybrid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hybrid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hybrid_panel.add_child(hybrid_scroll)

	_hybrid_grid = HFlowContainer.new()
	_hybrid_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hybrid_grid.add_theme_constant_override("h_separation", 6)
	_hybrid_grid.add_theme_constant_override("v_separation", 6)
	hybrid_scroll.add_child(_hybrid_grid)

	_hybrid_empty_label = Label.new()
	_hybrid_empty_label.text = "No sub-tier 5+ companions in the kennel yet."
	_hybrid_empty_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_hybrid_empty_label.add_theme_font_size_override("font_size", 13)
	_hybrid_empty_label.visible = false
	_hybrid_grid.add_child(_hybrid_empty_label)

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

	# Confirm dialogs
	_same_confirm_dialog = ConfirmationDialog.new()
	_same_confirm_dialog.title = "Confirm Fusion"
	_same_confirm_dialog.confirmed.connect(_on_same_confirm_dialog_confirmed)
	add_child(_same_confirm_dialog)

	_mixed_confirm_dialog = ConfirmationDialog.new()
	_mixed_confirm_dialog.title = "Confirm T9 Fusion"
	_mixed_confirm_dialog.dialog_text = "Fuse 8 selected sub-tier 8 companions into 1 random T9? All 8 inputs will be destroyed."
	_mixed_confirm_dialog.confirmed.connect(_on_mixed_confirm_dialog_confirmed)
	add_child(_mixed_confirm_dialog)

	_hybrid_confirm_dialog = ConfirmationDialog.new()
	_hybrid_confirm_dialog.title = "Confirm Hybrid Fusion"
	_hybrid_confirm_dialog.confirmed.connect(_on_hybrid_confirm_dialog_confirmed)
	add_child(_hybrid_confirm_dialog)

	_set_tab(TAB_SAME)
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

func populate(groups: Array, t8_companions: Array, current_tab: String, hybrid_candidates: Array = [], catalyst_count: int = 0) -> void:
	if not is_inside_tree():
		return
	_groups = groups
	_t8_companions = t8_companions
	_hybrid_candidates = hybrid_candidates
	_catalyst_count = catalyst_count
	# Drop any mixed-tab selections that no longer exist.
	var valid_mixed_indices := {}
	for entry in t8_companions:
		valid_mixed_indices[int(entry.get("index", -1))] = true
	var filtered_mixed: Array = []
	for idx in _mixed_selected:
		if valid_mixed_indices.has(int(idx)):
			filtered_mixed.append(int(idx))
	_mixed_selected = filtered_mixed
	# Drop any hybrid-tab selections that no longer exist.
	var valid_hybrid_indices := {}
	for entry in hybrid_candidates:
		valid_hybrid_indices[int(entry.get("index", -1))] = true
	var filtered_hybrid: Array = []
	for idx in _hybrid_selected:
		if valid_hybrid_indices.has(int(idx)):
			filtered_hybrid.append(int(idx))
	_hybrid_selected = filtered_hybrid
	if current_tab in [TAB_SAME, TAB_MIXED, TAB_HYBRID]:
		_current_tab = current_tab
	_set_tab(_current_tab)
	_update_tab_styles()
	_update_summary()
	_rebuild_same_list()
	_rebuild_mixed_grid()
	_rebuild_hybrid_grid()


# === Internal rendering ===

func _set_tab(tab: String) -> void:
	_same_tab.visible = (tab == TAB_SAME)
	_mixed_tab.visible = (tab == TAB_MIXED)
	_hybrid_tab.visible = (tab == TAB_HYBRID)


func _update_tab_styles() -> void:
	_tab_same_btn.button_pressed = (_current_tab == TAB_SAME)
	_tab_mixed_btn.button_pressed = (_current_tab == TAB_MIXED)
	_tab_hybrid_btn.button_pressed = (_current_tab == TAB_HYBRID)


func _update_summary() -> void:
	var groups_count := _groups.size()
	var t8_count := _t8_companions.size()
	var hybrid_count := _hybrid_candidates.size()
	_summary_label.text = "[color=#00FF00]Fuseable groups:[/color] %d   [color=#FF00FF]T8 companions:[/color] %d / 8   [color=#FF66FF]Hybrid pool (ST5+):[/color] %d   [color=#FFD700]Catalysts:[/color] %d" % [groups_count, t8_count, hybrid_count, _catalyst_count]


func _rebuild_same_list() -> void:
	for child in _same_list_vbox.get_children():
		if child == _same_empty_label:
			continue
		child.queue_free()

	if _groups.is_empty():
		_same_empty_label.visible = true
		return
	_same_empty_label.visible = false

	for gi in range(_groups.size()):
		var row := _make_same_group_row(_groups[gi], gi)
		_same_list_vbox.add_child(row)


func _make_same_group_row(group: Dictionary, _group_index: int) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 40)
	btn.add_theme_font_size_override("font_size", 13)

	var monster_type = str(group.get("monster_type", "?"))
	var tier = int(group.get("tier", 1))
	var sub_tier = int(group.get("sub_tier", 1))
	var count = int(group.get("count", 0))
	var next_st = mini(sub_tier + 1, 9)
	var indices: Array = group.get("indices", [])

	btn.text = "%s  T%d-%d  ×%d  →  %s T%d-%d" % [monster_type, tier, sub_tier, count, monster_type, tier, next_st]

	# Take first 3 of the available indices.
	var first_three: Array = []
	for i in range(mini(3, indices.size())):
		first_three.append(int(indices[i]))

	var label = "Fuse 3× %s T%d-%d → 1× %s T%d-%d?" % [monster_type, tier, sub_tier, monster_type, tier, next_st]
	btn.pressed.connect(_on_same_group_pressed.bind(first_three, label))
	return btn


func _on_same_group_pressed(indices: Array, label: String) -> void:
	if indices.size() != 3:
		return
	_pending_same_indices = indices
	_pending_same_label = label
	_same_confirm_dialog.dialog_text = label + "\n\nThe 3 input companions will be destroyed."
	_same_confirm_dialog.popup_centered()


func _on_same_confirm_dialog_confirmed() -> void:
	if _pending_same_indices.size() == 3:
		emit_signal("same_fusion_pressed", _pending_same_indices.duplicate())
	_pending_same_indices = []
	_pending_same_label = ""


func _rebuild_mixed_grid() -> void:
	for child in _mixed_grid.get_children():
		if child == _mixed_empty_label:
			continue
		child.queue_free()

	_update_mixed_count()

	if _t8_companions.is_empty():
		_mixed_empty_label.visible = true
		return
	_mixed_empty_label.visible = false

	for entry in _t8_companions:
		var comp: Dictionary = entry.get("companion", {})
		var idx = int(entry.get("index", -1))
		var card := _make_mixed_card(comp, idx)
		_mixed_grid.add_child(card)


func _update_mixed_count() -> void:
	var count := _mixed_selected.size()
	var color := "#00FF00" if count == 8 else ("#FFAA00" if count > 0 else "#AAAAAA")
	_mixed_count_label.text = "[color=%s]Selected: %d / 8[/color]" % [color, count]
	_mixed_fuse_btn.disabled = (count != 8)
	_mixed_clear_btn.disabled = (count == 0)


func _make_mixed_card(c: Dictionary, kennel_index: int) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var selected := kennel_index in _mixed_selected
	if selected:
		sb.bg_color = Color(0.18, 0.08, 0.22, 0.95)
		sb.border_color = Color(1.0, 0.0, 1.0, 0.9)
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.95)
		sb.border_color = Color(0.4, 0.34, 0.25, 0.7)
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(220, 80)
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
	var sel_marker = "[color=#FF00FF]●[/color] " if selected else ""
	name_lbl.text = "%s%s[color=%s]%s[/color]" % [sel_marker, rarity_prefix, variant_color, name]
	vbox.add_child(name_lbl)

	var meta := RichTextLabel.new()
	meta.bbcode_enabled = true
	meta.fit_content = true
	meta.scroll_active = false
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_font_size_override("normal_font_size", 12)
	var level = int(c.get("level", 1))
	var tier = int(c.get("tier", 1))
	meta.text = "[color=#AAAAAA]Lv %d  T%d-8[/color]  [color=%s]%s[/color]" % [level, tier, variant_color, variant]
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

	card.gui_input.connect(_on_mixed_card_input.bind(kennel_index))
	return card


func _on_mixed_card_input(event: InputEvent, kennel_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_mixed_selection(kennel_index)


func _toggle_mixed_selection(kennel_index: int) -> void:
	if kennel_index in _mixed_selected:
		_mixed_selected.erase(kennel_index)
	else:
		if _mixed_selected.size() >= 8:
			return  # Cap at 8
		_mixed_selected.append(kennel_index)
	_rebuild_mixed_grid()


func _on_mixed_clear_pressed() -> void:
	_mixed_selected.clear()
	_rebuild_mixed_grid()


func _on_mixed_fuse_pressed() -> void:
	if _mixed_selected.size() == 8:
		_mixed_confirm_dialog.popup_centered()


func _on_mixed_confirm_dialog_confirmed() -> void:
	if _mixed_selected.size() == 8:
		emit_signal("mixed_fusion_pressed", _mixed_selected.duplicate())
		_mixed_selected.clear()


# === Tab callbacks ===

func _on_tab_same_pressed() -> void:
	if _current_tab == TAB_SAME:
		_tab_same_btn.button_pressed = true
		return
	_current_tab = TAB_SAME
	_set_tab(TAB_SAME)
	_update_tab_styles()
	emit_signal("tab_changed", TAB_SAME)


func _on_tab_mixed_pressed() -> void:
	if _current_tab == TAB_MIXED:
		_tab_mixed_btn.button_pressed = true
		return
	_current_tab = TAB_MIXED
	_set_tab(TAB_MIXED)
	_update_tab_styles()
	emit_signal("tab_changed", TAB_MIXED)


func _on_tab_hybrid_pressed() -> void:
	if _current_tab == TAB_HYBRID:
		_tab_hybrid_btn.button_pressed = true
		return
	_current_tab = TAB_HYBRID
	_set_tab(TAB_HYBRID)
	_update_tab_styles()
	emit_signal("tab_changed", TAB_HYBRID)


# === Hybrid tab rendering / selection ===

func _rebuild_hybrid_grid() -> void:
	for child in _hybrid_grid.get_children():
		if child == _hybrid_empty_label:
			continue
		child.queue_free()

	_update_hybrid_count()

	if _hybrid_candidates.is_empty():
		_hybrid_empty_label.visible = true
		return
	_hybrid_empty_label.visible = false

	for entry in _hybrid_candidates:
		var comp: Dictionary = entry.get("companion", {})
		var idx = int(entry.get("index", -1))
		var card := _make_hybrid_card(comp, idx)
		_hybrid_grid.add_child(card)


func _update_hybrid_count() -> void:
	var count := _hybrid_selected.size()
	var diff_types := _selected_hybrid_types_differ()
	var has_catalyst := _catalyst_count >= 1
	var ready := (count == 2 and diff_types and has_catalyst)
	var color := "#00FF00" if ready else ("#FFAA00" if count > 0 else "#AAAAAA")
	var reason := ""
	if count == 2 and not diff_types:
		reason = "  [color=#FF6666](both same monster type — pick different)[/color]"
	elif count == 2 and not has_catalyst:
		reason = "  [color=#FF6666](no Hybrid Catalyst in inventory)[/color]"
	_hybrid_count_label.text = "[color=%s]Selected: %d / 2[/color]%s" % [color, count, reason]
	_hybrid_fuse_btn.disabled = not ready
	_hybrid_clear_btn.disabled = (count == 0)


func _selected_hybrid_types_differ() -> bool:
	if _hybrid_selected.size() != 2:
		return false
	var t0 := ""
	var t1 := ""
	for entry in _hybrid_candidates:
		var idx := int(entry.get("index", -1))
		if idx == int(_hybrid_selected[0]):
			t0 = String(entry.get("companion", {}).get("monster_type", ""))
		elif idx == int(_hybrid_selected[1]):
			t1 = String(entry.get("companion", {}).get("monster_type", ""))
	return t0 != "" and t1 != "" and t0 != t1


func _make_hybrid_card(c: Dictionary, kennel_index: int) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var selected := kennel_index in _hybrid_selected
	if selected:
		sb.bg_color = Color(0.22, 0.10, 0.22, 0.95)
		sb.border_color = Color(1.0, 0.4, 1.0, 0.9)
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(0.06, 0.05, 0.04, 0.95)
		sb.border_color = Color(0.4, 0.34, 0.25, 0.7)
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(220, 80)
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
	var sel_marker = "[color=#FF66FF]●[/color] " if selected else ""
	name_lbl.text = "%s%s[color=%s]%s[/color]" % [sel_marker, rarity_prefix, variant_color, name]
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
	var monster_type = str(c.get("monster_type", "?"))
	meta.text = "[color=#AAAAAA]Lv %d  T%d-%d  %s[/color]  [color=%s]%s[/color]" % [level, tier, sub_tier, monster_type, variant_color, variant]
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

	card.gui_input.connect(_on_hybrid_card_input.bind(kennel_index))
	return card


func _on_hybrid_card_input(event: InputEvent, kennel_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_hybrid_selection(kennel_index)


func _toggle_hybrid_selection(kennel_index: int) -> void:
	if kennel_index in _hybrid_selected:
		_hybrid_selected.erase(kennel_index)
	else:
		if _hybrid_selected.size() >= 2:
			return  # Cap at 2
		_hybrid_selected.append(kennel_index)
	_rebuild_hybrid_grid()


func _on_hybrid_clear_pressed() -> void:
	_hybrid_selected.clear()
	_rebuild_hybrid_grid()


func _on_hybrid_fuse_pressed() -> void:
	if _hybrid_selected.size() != 2:
		return
	if not _selected_hybrid_types_differ():
		return
	if _catalyst_count < 1:
		return
	# Build confirmation text naming the two parents.
	var names: Array = []
	for entry in _hybrid_candidates:
		var idx := int(entry.get("index", -1))
		if idx in _hybrid_selected:
			names.append(String(entry.get("companion", {}).get("monster_type", "?")))
	var label = "Fuse %s + %s into 1 hybrid? Both parents are destroyed and 1 Hybrid Catalyst is consumed." % [
		names[0] if names.size() > 0 else "?",
		names[1] if names.size() > 1 else "?",
	]
	_hybrid_confirm_dialog.dialog_text = label
	_hybrid_confirm_dialog.popup_centered()


func _on_hybrid_confirm_dialog_confirmed() -> void:
	if _hybrid_selected.size() == 2 and _selected_hybrid_types_differ() and _catalyst_count >= 1:
		emit_signal("hybrid_fusion_pressed", _hybrid_selected.duplicate())
		_hybrid_selected.clear()


func _on_close_pressed() -> void:
	emit_signal("close_requested")
