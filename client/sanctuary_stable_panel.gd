extends Control
class_name SanctuaryStablePanel

# v0.9.497 — Unified Sanctuary Companion Stable.
#
# Replaces the legacy K (Kennel) + F (Fusion Station) tiles in the Sanctuary
# with a single Stable station, mirroring the at-NPC-post CompanionStablePanel
# style. Two tabs:
#
#   Kennel — list of kennel companions with [Register to Slot] [Release] per
#   row. Pagination via action bar.
#
#   Fuse — Same Type / Mixed T9 (no catalyst requirement, so both work in
#   sanctuary). Hybrid + Ascend hidden in sanctuary because their catalysts
#   live in CHARACTER inventory (no character context here in HOUSE_SCREEN).
#
# Data source: client.gd's house_data. The panel does not fetch state itself.
# Signals route to the existing server handlers:
#   register_requested → house_kennel_register
#   release_requested  → house_kennel_release
#   fuse_requested(mode, indices) → house_fusion
#   close_requested    → return to Sanctuary main

signal close_requested
signal release_requested(kennel_index: int)
signal register_requested(kennel_index: int)
signal fuse_requested(fusion_type: String, indices: Array)

const HelpPanelScript = preload("res://client/help_panel.gd")

const TAB_KENNEL := "kennel"
const TAB_FUSE := "fuse"

const FUSE_SAME := "same"
const FUSE_MIXED := "mixed"

const FUSE_MODE_RULES := {
	"same":  {"cap": 3, "min_sub_tier": 1, "max_sub_tier": 9},
	"mixed": {"cap": 8, "min_sub_tier": 8, "max_sub_tier": 8},
}

var _current_tab: String = TAB_KENNEL
var _current_fuse_mode: String = FUSE_SAME

# Payload state (set by show_with_data).
var _kennel: Array = []
var _kennel_capacity: int = 30
var _registered_count: int = 0
var _registered_capacity: int = 2

# Fuse-tab selection state. Each entry: {index: int, companion: Dictionary}
var _fuse_selection: Array = []

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _summary_label: RichTextLabel
var _tab_kennel_btn: Button
var _tab_fuse_btn: Button
var _close_btn: Button
var _help_panel: Control = null

# Kennel-tab nodes.
var _kennel_view: Control
var _kennel_list: VBoxContainer
var _kennel_empty: Label

# Fuse-tab nodes.
var _fuse_view: Control
var _fuse_mode_same_btn: Button
var _fuse_mode_mixed_btn: Button
var _fuse_hint_label: RichTextLabel
var _fuse_candidates_list: VBoxContainer
var _fuse_candidates_empty: Label
var _fuse_selection_label: RichTextLabel
var _fuse_button: Button
var _fuse_clear_btn: Button


func _ready() -> void:
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_layout()
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if _help_panel != null and _help_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()


func show_with_data(payload: Dictionary) -> void:
	"""Populate from house_data-derived payload.
	Expected keys:
	  kennel: Array of companion dicts
	  kennel_capacity: int
	  registered_count: int (for header summary)
	  registered_capacity: int"""
	_kennel = payload.get("kennel", [])
	_kennel_capacity = int(payload.get("kennel_capacity", 30))
	_registered_count = int(payload.get("registered_count", 0))
	_registered_capacity = int(payload.get("registered_capacity", 2))
	_fuse_selection = _fuse_selection.filter(func(sel):
		var idx = int(sel.index)
		return idx >= 0 and idx < _kennel.size()
	)
	_refresh_all()
	visible = true


func _refresh_all() -> void:
	_refresh_summary()
	_refresh_kennel()
	_refresh_fuse()


# ===== TAB SWITCHING =====

func _set_tab(tab: String) -> void:
	_current_tab = tab
	_kennel_view.visible = (tab == TAB_KENNEL)
	_fuse_view.visible = (tab == TAB_FUSE)
	_tab_kennel_btn.button_pressed = (tab == TAB_KENNEL)
	_tab_fuse_btn.button_pressed = (tab == TAB_FUSE)


# ===== SUMMARY HEADER =====

func _refresh_summary() -> void:
	if _summary_label == null:
		return
	_summary_label.clear()
	_summary_label.append_text(
		"[color=#A335EE]Kennel:[/color] %d / %d   " % [_kennel.size(), _kennel_capacity]
		+ "[color=#FF80FF]Registered:[/color] %d / %d   " % [_registered_count, _registered_capacity]
		+ "[color=#888888](Sanctuary mode — between characters)[/color]"
	)


# ===== KENNEL TAB =====

func _refresh_kennel() -> void:
	if _kennel_list == null:
		return
	for child in _kennel_list.get_children():
		child.queue_free()
	if _kennel.is_empty():
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.scroll_active = false
		lbl.append_text("[color=#808080]Kennel is empty. Use Home Stone (Companion) in-game with the [b]Kennel[/b] option to bulk-store companions here.[/color]")
		_kennel_list.add_child(lbl)
		return
	for i in range(_kennel.size()):
		_kennel_list.add_child(_build_kennel_row(i))


func _build_kennel_row(idx: int) -> Control:
	var c: Dictionary = _kennel[idx]
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var rarity_color = _variant_color_for(c)
	sb.bg_color = Color(0.13, 0.13, 0.17, 0.95)
	sb.border_color = rarity_color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var variant_str = str(c.get("variant", "Normal"))
	var variant_bbcode := ""
	if variant_str != "" and variant_str != "Normal":
		variant_bbcode = "[color=%s]%s[/color] " % [rarity_color.to_html(false), variant_str]
	var hybrid_marker := ""
	var partner = str(c.get("hybrid_partner_type", ""))
	if partner != "":
		hybrid_marker = "  [color=#FF80FF][HYBRID×%s][/color]" % partner
	info.append_text(
		"[b]%s[/b]%s\n[color=#888888]%s T%d.%d  Lv %d[/color]" % [
			c.get("name", "Unknown"),
			hybrid_marker,
			variant_bbcode + str(c.get("monster_type", "")),
			int(c.get("tier", 1)),
			int(c.get("sub_tier", 1)),
			int(c.get("level", 1)),
		]
	)
	hb.add_child(info)

	var reg_btn := Button.new()
	reg_btn.focus_mode = Control.FOCUS_NONE
	reg_btn.custom_minimum_size = Vector2(140, 28)
	reg_btn.text = "✦ Register to Slot"
	reg_btn.tooltip_text = "Move this companion from the kennel into a registered slot (survives permadeath)."
	reg_btn.disabled = (_registered_count >= _registered_capacity)
	reg_btn.pressed.connect(func(): emit_signal("register_requested", idx))
	hb.add_child(reg_btn)

	var rel_btn := Button.new()
	rel_btn.focus_mode = Control.FOCUS_NONE
	rel_btn.custom_minimum_size = Vector2(90, 28)
	rel_btn.text = "✗ Release"
	rel_btn.tooltip_text = "Permanently release (delete) this kennel companion."
	rel_btn.pressed.connect(func(): emit_signal("release_requested", idx))
	hb.add_child(rel_btn)

	return row


# ===== FUSE TAB =====

func _refresh_fuse() -> void:
	if _fuse_hint_label == null:
		return
	if _fuse_mode_same_btn:
		_fuse_mode_same_btn.button_pressed = (_current_fuse_mode == FUSE_SAME)
	if _fuse_mode_mixed_btn:
		_fuse_mode_mixed_btn.button_pressed = (_current_fuse_mode == FUSE_MIXED)
	_fuse_hint_label.clear()
	match _current_fuse_mode:
		FUSE_SAME:
			_fuse_hint_label.append_text(
				"[color=#FFD700]Same Type Fusion[/color] — Select [b]3[/b] kennel companions of the same monster type AND same sub-tier. "
				+ "They combine into [b]1[/b] companion of the next sub-tier (sub_tier 8 caps).\n"
				+ "[color=#888888]Output goes to the kennel.[/color]"
			)
		FUSE_MIXED:
			_fuse_hint_label.append_text(
				"[color=#FF00FF]Mixed T9 Fusion[/color] — Select [b]8[/b] kennel companions all at [b]T8.8 (Tier 8, sub-tier 8)[/b]. Types can differ. "
				+ "Output is a [b]random Tier 9[/b] companion (rolls from one of the selected types).\n"
				+ "[color=#888888]The capstone fusion. Output goes to the kennel.[/color]"
			)
	_fuse_hint_label.append_text(
		"\n[color=#888888]Hybrid & Tier Ascend modes need an [b]active character[/b] (their catalysts come from inventory). Visit the [color=#A335EE]Companion Stable[/color] at any Tier 5+ NPC post to use those.[/color]"
	)
	_populate_fuse_candidates()
	_refresh_fuse_selection_state()


func _set_fuse_mode(mode: String) -> void:
	if mode == _current_fuse_mode:
		return
	_current_fuse_mode = mode
	_fuse_selection = []
	_refresh_fuse()


func _candidate_matches_mode(c: Dictionary, mode: String) -> bool:
	var rules: Dictionary = FUSE_MODE_RULES.get(mode, FUSE_MODE_RULES[FUSE_SAME])
	var st = int(c.get("sub_tier", 1))
	if st < int(rules.get("min_sub_tier", 1)) or st > int(rules.get("max_sub_tier", 9)):
		return false
	if mode == FUSE_MIXED and int(c.get("tier", 1)) != 8:
		return false
	return true


func _populate_fuse_candidates() -> void:
	if _fuse_candidates_list == null:
		return
	for child in _fuse_candidates_list.get_children():
		child.queue_free()
	var candidates: Array = []
	for i in range(_kennel.size()):
		if _candidate_matches_mode(_kennel[i], _current_fuse_mode):
			candidates.append({"index": i, "companion": _kennel[i]})
	if candidates.is_empty():
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.scroll_active = false
		var msg := ""
		match _current_fuse_mode:
			FUSE_SAME:
				msg = "[color=#808080]No kennel companions available. Send some via Home Stone (Companion) → Kennel.[/color]"
			FUSE_MIXED:
				msg = "[color=#808080]No T8.8 companions in the kennel. Mixed T9 needs maxed-out Tier 8 inputs.[/color]"
		lbl.append_text(msg)
		_fuse_candidates_list.add_child(lbl)
		return
	candidates.sort_custom(func(a, b):
		var at = String(a.companion.get("monster_type", ""))
		var bt = String(b.companion.get("monster_type", ""))
		if at != bt:
			return at < bt
		var ast = int(a.companion.get("sub_tier", 1))
		var bst = int(b.companion.get("sub_tier", 1))
		if ast != bst:
			return ast < bst
		return int(a.companion.get("level", 1)) < int(b.companion.get("level", 1))
	)
	for cand in candidates:
		_fuse_candidates_list.add_child(_build_fuse_candidate_row(cand))


func _build_fuse_candidate_row(cand: Dictionary) -> Control:
	var idx = int(cand.index)
	var c: Dictionary = cand.companion
	var selected = _is_fuse_selected(idx)

	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var rarity_color = _variant_color_for(c)
	if selected:
		sb.bg_color = Color(0.20, 0.10, 0.25, 0.95)
		sb.border_color = Color(1.0, 0.84, 0.0, 0.95)
		sb.set_border_width_all(2)
	else:
		sb.bg_color = Color(0.13, 0.13, 0.17, 0.95)
		sb.border_color = rarity_color
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var variant_str = str(c.get("variant", "Normal"))
	var variant_bbcode := ""
	if variant_str != "" and variant_str != "Normal":
		variant_bbcode = "[color=%s]%s[/color] " % [rarity_color.to_html(false), variant_str]
	info.append_text(
		"[b]%s[/b]\n[color=#888888]%s T%d.%d  Lv %d[/color]" % [
			c.get("name", "Unknown"),
			variant_bbcode + str(c.get("monster_type", "")),
			int(c.get("tier", 1)),
			int(c.get("sub_tier", 1)),
			int(c.get("level", 1)),
		]
	)
	hb.add_child(info)

	var toggle_btn := Button.new()
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.custom_minimum_size = Vector2(90, 28)
	toggle_btn.text = "✓ Selected" if selected else "+ Select"
	toggle_btn.pressed.connect(func(): _toggle_fuse_selection(cand))
	hb.add_child(toggle_btn)

	return row


func _is_fuse_selected(index: int) -> bool:
	for sel in _fuse_selection:
		if int(sel.index) == index:
			return true
	return false


func _toggle_fuse_selection(cand: Dictionary) -> void:
	var idx = int(cand.index)
	if _is_fuse_selected(idx):
		var new_selection: Array = []
		for sel in _fuse_selection:
			if int(sel.index) != idx:
				new_selection.append(sel)
		_fuse_selection = new_selection
	else:
		var cap = int(FUSE_MODE_RULES.get(_current_fuse_mode, FUSE_MODE_RULES[FUSE_SAME]).get("cap", 3))
		if _fuse_selection.size() >= cap:
			return
		_fuse_selection.append(cand)
	_populate_fuse_candidates()
	_refresh_fuse_selection_state()


func _refresh_fuse_selection_state() -> void:
	if _fuse_selection_label == null:
		return
	_fuse_selection_label.clear()
	var count = _fuse_selection.size()
	var cap = int(FUSE_MODE_RULES.get(_current_fuse_mode, FUSE_MODE_RULES[FUSE_SAME]).get("cap", 3))
	var color := "#00FF00" if count == cap else ("#FFAA00" if count > 0 else "#AAAAAA")
	_fuse_selection_label.append_text("[color=%s]Selected: %d / %d[/color]" % [color, count, cap])
	var fuse_ready = false
	var preview := ""
	match _current_fuse_mode:
		FUSE_SAME:
			if count == cap:
				var first: Dictionary = _fuse_selection[0].companion
				var same_type = true
				var same_st = true
				for sel in _fuse_selection:
					if sel.companion.get("monster_type") != first.get("monster_type"):
						same_type = false
					if int(sel.companion.get("sub_tier", 1)) != int(first.get("sub_tier", 1)):
						same_st = false
				if not same_type:
					preview = "[color=#FF6644]All 3 must share the same monster type.[/color]"
				elif not same_st:
					preview = "[color=#FF6644]All 3 must share the same sub-tier.[/color]"
				else:
					fuse_ready = true
					var new_st = mini(int(first.get("sub_tier", 1)) + 1, 9)
					preview = "[color=#88FF88]→ %s T%d.%d will be added to kennel.[/color]" % [
						str(first.get("monster_type", "?")),
						int(first.get("tier", 1)),
						new_st,
					]
			elif count > 0:
				preview = "[color=#888888]Pick %d more to enable Fuse.[/color]" % (cap - count)
		FUSE_MIXED:
			if count == cap:
				var all_t88 = true
				for sel in _fuse_selection:
					if int(sel.companion.get("tier", 1)) != 8 or int(sel.companion.get("sub_tier", 1)) != 8:
						all_t88 = false
						break
				if not all_t88:
					preview = "[color=#FF6644]All 8 must be T8.8 (Tier 8, sub-tier 8).[/color]"
				else:
					fuse_ready = true
					preview = "[color=#88FF88]→ Random T9 companion will be added to kennel.[/color]"
			elif count > 0:
				preview = "[color=#888888]Pick %d more to enable Fuse.[/color]" % (cap - count)
	if preview != "":
		_fuse_selection_label.append_text("    " + preview)
	if _fuse_button:
		_fuse_button.disabled = not fuse_ready
	if _fuse_clear_btn:
		_fuse_clear_btn.disabled = (count == 0)


func _on_fuse_button_pressed() -> void:
	var cap = int(FUSE_MODE_RULES.get(_current_fuse_mode, FUSE_MODE_RULES[FUSE_SAME]).get("cap", 3))
	if _fuse_selection.size() != cap:
		return
	var indices: Array = []
	for sel in _fuse_selection:
		indices.append(int(sel.index))
	emit_signal("fuse_requested", _current_fuse_mode, indices)
	_fuse_selection = []


func _on_fuse_clear_pressed() -> void:
	_fuse_selection = []
	_populate_fuse_candidates()
	_refresh_fuse_selection_state()


# ===== HELPERS =====

func _variant_color_for(c: Dictionary) -> Color:
	var hex = str(c.get("variant_color", "#FFFFFF"))
	if hex == "" or not hex.begins_with("#") or hex.length() < 7:
		return Color(1, 1, 1)
	return Color.html(hex)


# ===== LAYOUT =====

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
	_root_panel.custom_minimum_size = Vector2(960, 640)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.08, 0.10, 0.16, 0.98)
	panel_sb.border_color = Color(0.53, 0.81, 0.92, 1.0)
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 18
	panel_sb.content_margin_right = 18
	panel_sb.content_margin_top = 14
	panel_sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(_root_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_root_panel.add_child(vb)

	# Title + Help/Close header row
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	vb.add_child(header_row)

	_title_label = RichTextLabel.new()
	_title_label.bbcode_enabled = true
	_title_label.fit_content = true
	_title_label.scroll_active = false
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("normal_font_size", 18)
	_title_label.append_text("[color=#FFD700]Sanctuary Companion Stable[/color]")
	header_row.add_child(_title_label)

	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn := HelpPanelScript.make_help_button("companion_stable", _help_panel)
	header_row.add_child(help_btn)

	_close_btn = Button.new()
	_close_btn.text = "Close (Esc)"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.custom_minimum_size = Vector2(110, 26)
	_close_btn.pressed.connect(_on_close)
	header_row.add_child(_close_btn)

	# Summary line
	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.scroll_active = false
	_summary_label.add_theme_font_size_override("normal_font_size", 12)
	vb.add_child(_summary_label)

	# Tab row
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	vb.add_child(tab_row)
	_tab_kennel_btn = _make_tab_button("Kennel", TAB_KENNEL)
	tab_row.add_child(_tab_kennel_btn)
	_tab_fuse_btn = _make_tab_button("Fuse", TAB_FUSE)
	tab_row.add_child(_tab_fuse_btn)

	# Stacked views
	_kennel_view = _build_kennel_view()
	vb.add_child(_kennel_view)
	_fuse_view = _build_fuse_view()
	vb.add_child(_fuse_view)
	_set_tab(TAB_KENNEL)


func _make_tab_button(text: String, tab_id: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(140, 28)
	btn.pressed.connect(func(): _set_tab(tab_id))
	return btn


func _make_fuse_mode_button(text: String, mode_id: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120, 26)
	btn.pressed.connect(func(): _set_fuse_mode(mode_id))
	return btn


func _build_kennel_view() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.scroll_active = false
	hint.add_theme_font_size_override("normal_font_size", 12)
	hint.append_text("[color=#888888][b]Register to Slot[/b] moves a kennel companion into a permadeath-resistant registered slot. [b]Release[/b] permanently deletes it.[/color]")
	vb.add_child(hint)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	sb.border_color = Color(0.3, 0.3, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(900, 460)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_kennel_list = VBoxContainer.new()
	_kennel_list.add_theme_constant_override("separation", 4)
	_kennel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_kennel_list)

	_kennel_empty = Label.new()
	_kennel_empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	return vb


func _build_fuse_view() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	vb.add_child(mode_row)
	_fuse_mode_same_btn = _make_fuse_mode_button("Same Type", FUSE_SAME)
	mode_row.add_child(_fuse_mode_same_btn)
	_fuse_mode_mixed_btn = _make_fuse_mode_button("Mixed T9", FUSE_MIXED)
	mode_row.add_child(_fuse_mode_mixed_btn)

	_fuse_hint_label = RichTextLabel.new()
	_fuse_hint_label.bbcode_enabled = true
	_fuse_hint_label.fit_content = true
	_fuse_hint_label.scroll_active = false
	_fuse_hint_label.add_theme_font_size_override("normal_font_size", 12)
	vb.add_child(_fuse_hint_label)

	var cand_panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	sb.border_color = Color(0.3, 0.3, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	cand_panel.add_theme_stylebox_override("panel", sb)
	cand_panel.custom_minimum_size = Vector2(900, 380)
	cand_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cand_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cand_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cand_panel.add_child(scroll)

	_fuse_candidates_list = VBoxContainer.new()
	_fuse_candidates_list.add_theme_constant_override("separation", 4)
	_fuse_candidates_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fuse_candidates_list)

	# Selection summary + buttons.
	_fuse_selection_label = RichTextLabel.new()
	_fuse_selection_label.bbcode_enabled = true
	_fuse_selection_label.fit_content = true
	_fuse_selection_label.scroll_active = false
	_fuse_selection_label.add_theme_font_size_override("normal_font_size", 13)
	vb.add_child(_fuse_selection_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vb.add_child(btn_row)
	_fuse_clear_btn = Button.new()
	_fuse_clear_btn.text = "Clear Selection"
	_fuse_clear_btn.focus_mode = Control.FOCUS_NONE
	_fuse_clear_btn.custom_minimum_size = Vector2(140, 32)
	_fuse_clear_btn.pressed.connect(_on_fuse_clear_pressed)
	btn_row.add_child(_fuse_clear_btn)
	_fuse_button = Button.new()
	_fuse_button.text = "FUSE"
	_fuse_button.focus_mode = Control.FOCUS_NONE
	_fuse_button.custom_minimum_size = Vector2(180, 36)
	_fuse_button.add_theme_font_size_override("font_size", 15)
	_fuse_button.pressed.connect(_on_fuse_button_pressed)
	btn_row.add_child(_fuse_button)

	return vb


func _on_close() -> void:
	visible = false
	emit_signal("close_requested")
