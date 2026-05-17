extends Control
class_name CompanionStablePanel

# Audit #4 Slice 1A (v0.9.485+) — visual UI for the Companion Stable at T5+
# NPC posts.
#
# v0.9.485: Two-column Manage view (collected ↔ kennel) with deposit/withdraw.
# v0.9.489: Adds a "Fuse" tab. Same-type fusion only this slice; Mixed T9 +
#           Hybrid land in v0.9.490+. Inputs can be drawn from kennel OR
#           registered slots; output is auto-registered if any input was
#           registered (slot-preserving via the server's stable_fusion path).
#
# Server messages handled:
#   companion_stable_open  →  show_with_payload(payload)
# Signals emitted (client.gd wires to server messages):
#   deposit_requested(collected_index)
#   withdraw_requested(kennel_index)
#   fuse_requested(fusion_type: String, inputs: Array)  # NEW v0.9.489
#   close_requested

signal deposit_requested(collected_index: int)
signal withdraw_requested(kennel_index: int)
signal fuse_requested(fusion_type: String, inputs: Array)
signal close_requested

const HelpPanelScript = preload("res://client/help_panel.gd")

const TAB_MANAGE := "manage"
const TAB_FUSE := "fuse"

# Fuse-tab fusion mode (only "same" implemented in v0.9.489).
const FUSE_SAME := "same"

var _current_tab: String = TAB_MANAGE
var _current_fuse_mode: String = FUSE_SAME

# Payload state (set by show_with_payload).
var _kennel: Array = []
var _collected: Array = []
var _registered: Array = []  # NEW v0.9.489 — non-checked-out registered slots
var _kennel_capacity: int = 30

# Fuse-tab selection state. Each entry: {source: "kennel"|"registered", index: int, companion: Dictionary}
var _fuse_selection: Array = []

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _summary_label: RichTextLabel
var _tab_manage_btn: Button
var _tab_fuse_btn: Button
var _close_btn: Button
var _help_panel: Control = null

# Manage-tab nodes.
var _manage_view: Control
var _collected_list: VBoxContainer
var _kennel_list: VBoxContainer
var _collected_empty: Label
var _kennel_empty: Label

# Fuse-tab nodes.
var _fuse_view: Control
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


func show_with_payload(payload: Dictionary) -> void:
	_kennel = payload.get("kennel", [])
	_collected = payload.get("collected", [])
	_registered = payload.get("registered", [])
	_kennel_capacity = int(payload.get("kennel_capacity", 30))
	# Drop any stale fuse selections (e.g., after a successful fusion the
	# previously-selected indices may no longer exist).
	_fuse_selection = _fuse_selection.filter(func(sel):
		return _find_companion_in_source(sel.source, int(sel.index)) != null
	)
	_refresh_all()
	visible = true


func _refresh_all() -> void:
	_refresh_summary()
	_refresh_manage()
	_refresh_fuse()


# ===== TAB SWITCHING =====

func _set_tab(tab: String) -> void:
	_current_tab = tab
	_manage_view.visible = (tab == TAB_MANAGE)
	_fuse_view.visible = (tab == TAB_FUSE)
	_tab_manage_btn.button_pressed = (tab == TAB_MANAGE)
	_tab_fuse_btn.button_pressed = (tab == TAB_FUSE)


# ===== SUMMARY HEADER =====

func _refresh_summary() -> void:
	if _summary_label == null:
		return
	_summary_label.clear()
	_summary_label.append_text(
		"[color=#A335EE]Kennel:[/color] %d / %d   "
		% [_kennel.size(), _kennel_capacity]
		+ "[color=#87CEEB]Collected:[/color] %d   " % _collected.size()
		+ "[color=#FF80FF]Registered (available):[/color] %d" % _registered.size()
	)


# ===== MANAGE TAB =====

func _refresh_manage() -> void:
	_populate_manage_list(_collected_list, _collected, true, _collected_empty,
		"[color=#808080]No collected companions. Catch one in the world to start.[/color]")
	_populate_manage_list(_kennel_list, _kennel, false, _kennel_empty,
		"[color=#808080]Sanctuary kennel empty.[/color]")


func _populate_manage_list(container: VBoxContainer, items: Array, is_collected: bool, empty_label: Label, empty_text: String) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()
	if items.is_empty():
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.scroll_active = false
		lbl.append_text(empty_text)
		container.add_child(lbl)
		return
	for i in range(items.size()):
		var c = items[i]
		container.add_child(_build_manage_row(c, is_collected))


func _build_manage_row(c: Dictionary, is_collected: bool) -> Control:
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
	info.custom_minimum_size = Vector2(280, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hybrid_marker := ""
	var partner = str(c.get("hybrid_partner_type", ""))
	if partner != "":
		hybrid_marker = "  [color=#FF80FF][HYBRID×%s][/color]" % partner
	var active_marker := ""
	if is_collected and bool(c.get("is_active", false)):
		active_marker = "  [color=#FFD700][ACTIVE][/color]"
	if is_collected and bool(c.get("using_registered", false)):
		active_marker += "  [color=#FF80FF][REGISTERED][/color]"
	var variant_str = str(c.get("variant", "Normal"))
	var variant_bbcode := ""
	if variant_str != "" and variant_str != "Normal":
		variant_bbcode = "[color=%s]%s[/color] " % [rarity_color.to_html(false), variant_str]
	info.append_text(
		"[b]%s[/b]%s%s\n[color=#888888]%s T%d.%d  Lv %d[/color]" % [
			c.get("name", "Unknown"),
			hybrid_marker,
			active_marker,
			variant_bbcode + str(c.get("monster_type", "")),
			int(c.get("tier", 1)),
			int(c.get("sub_tier", 1)),
			int(c.get("level", 1)),
		]
	)
	hb.add_child(info)

	var action_btn := Button.new()
	action_btn.focus_mode = Control.FOCUS_NONE
	action_btn.custom_minimum_size = Vector2(110, 28)
	var idx = int(c.get("index", -1))
	if is_collected:
		action_btn.text = "→ Deposit"
		action_btn.tooltip_text = "Send to Sanctuary kennel"
		var disabled := false
		if bool(c.get("using_registered", false)):
			action_btn.text = "→ Return to Slot"
			action_btn.tooltip_text = "Return to its registered Sanctuary slot. Still registered; just not on your character anymore."
		elif _kennel.size() >= _kennel_capacity:
			disabled = true
			action_btn.tooltip_text = "Kennel is full — upgrade at the Sanctuary."
		action_btn.disabled = disabled
		action_btn.pressed.connect(func(): emit_signal("deposit_requested", idx))
	else:
		action_btn.text = "← Withdraw"
		action_btn.tooltip_text = "Bring into your roster"
		action_btn.pressed.connect(func(): emit_signal("withdraw_requested", idx))
	hb.add_child(action_btn)

	return row


# ===== FUSE TAB =====

func _refresh_fuse() -> void:
	if _fuse_hint_label == null:
		return
	# Hint by mode (only Same supported in v0.9.489).
	_fuse_hint_label.clear()
	_fuse_hint_label.append_text(
		"[color=#FFD700]Same Type Fusion[/color] — Select [b]3[/b] companions of the same monster type AND same sub-tier. "
		+ "They will combine into [b]1[/b] companion of the next sub-tier (sub_tier 8 caps out).\n"
		+ "[color=#888888]Inputs can come from kennel or registered slots. If any input is registered, the output is automatically registered (slot-preserving).[/color]"
	)
	_populate_fuse_candidates()
	_refresh_fuse_selection_state()


func _populate_fuse_candidates() -> void:
	if _fuse_candidates_list == null:
		return
	for child in _fuse_candidates_list.get_children():
		child.queue_free()
	# Build unified candidate list. For same-type mode all kennel + registered
	# (non-checked-out) are candidates.
	var candidates: Array = []
	for i in range(_kennel.size()):
		candidates.append({"source": "kennel", "index": i, "companion": _kennel[i]})
	for i in range(_registered.size()):
		candidates.append({"source": "registered", "index": i, "companion": _registered[i]})
	if candidates.is_empty():
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.scroll_active = false
		lbl.append_text("[color=#808080]No fusion candidates yet. Deposit companions or register some via a Home Stone (Companion).[/color]")
		_fuse_candidates_list.add_child(lbl)
		return
	# Sort: by monster_type then sub_tier so same-type same-sub-tier groups
	# are visually adjacent for easy picking.
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
	var source = String(cand.source)
	var idx = int(cand.index)
	var c: Dictionary = cand.companion
	var selected = _is_fuse_selected(source, idx)

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
	info.custom_minimum_size = Vector2(0, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var source_tag = ""
	if source == "kennel":
		source_tag = "  [color=#A335EE][KENNEL][/color]"
	else:
		source_tag = "  [color=#FF80FF][REG][/color]"
	var hybrid_marker := ""
	var partner = str(c.get("hybrid_partner_type", ""))
	if partner != "":
		hybrid_marker = "  [color=#FF80FF][HYBRID×%s][/color]" % partner
	var variant_str = str(c.get("variant", "Normal"))
	var variant_bbcode := ""
	if variant_str != "" and variant_str != "Normal":
		variant_bbcode = "[color=%s]%s[/color] " % [rarity_color.to_html(false), variant_str]
	info.append_text(
		"[b]%s[/b]%s%s\n[color=#888888]%s T%d.%d  Lv %d[/color]" % [
			c.get("name", "Unknown"),
			source_tag,
			hybrid_marker,
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
	toggle_btn.tooltip_text = "Toggle this companion in the fusion pool"
	toggle_btn.pressed.connect(func(): _toggle_fuse_selection(cand))
	hb.add_child(toggle_btn)

	return row


func _is_fuse_selected(source: String, index: int) -> bool:
	for sel in _fuse_selection:
		if String(sel.source) == source and int(sel.index) == index:
			return true
	return false


func _toggle_fuse_selection(cand: Dictionary) -> void:
	var source = String(cand.source)
	var idx = int(cand.index)
	if _is_fuse_selected(source, idx):
		# Remove
		var new_selection: Array = []
		for sel in _fuse_selection:
			if not (String(sel.source) == source and int(sel.index) == idx):
				new_selection.append(sel)
		_fuse_selection = new_selection
	else:
		# Add — cap at 3 for same-type fusion.
		if _fuse_selection.size() >= 3:
			return
		_fuse_selection.append(cand)
	_populate_fuse_candidates()
	_refresh_fuse_selection_state()


func _refresh_fuse_selection_state() -> void:
	if _fuse_selection_label == null:
		return
	_fuse_selection_label.clear()
	var count = _fuse_selection.size()
	var color := "#00FF00" if count == 3 else ("#FFAA00" if count > 0 else "#AAAAAA")
	_fuse_selection_label.append_text("[color=%s]Selected: %d / 3[/color]" % [color, count])
	# Validate same-type same-sub-tier and decide enable.
	var fuse_ready = false
	var preview := ""
	if count == 3:
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
			var any_registered = false
			for sel in _fuse_selection:
				if String(sel.source) == "registered":
					any_registered = true
					break
			var new_st = mini(int(first.get("sub_tier", 1)) + 1, 9)
			var dest = "registered slot (slot-preserving)" if any_registered else "kennel"
			preview = "[color=#88FF88]→ %s T%d.%d will be added to %s.[/color]" % [
				str(first.get("monster_type", "?")),
				int(first.get("tier", 1)),
				new_st,
				dest,
			]
	elif count > 0:
		preview = "[color=#888888]Pick %d more to enable Fuse.[/color]" % (3 - count)
	if preview != "":
		_fuse_selection_label.append_text("    " + preview)
	if _fuse_button:
		_fuse_button.disabled = not fuse_ready
	if _fuse_clear_btn:
		_fuse_clear_btn.disabled = (count == 0)


func _on_fuse_button_pressed() -> void:
	if _fuse_selection.size() != 3:
		return
	var inputs: Array = []
	for sel in _fuse_selection:
		inputs.append({"source": String(sel.source), "index": int(sel.index)})
	emit_signal("fuse_requested", FUSE_SAME, inputs)
	# Clear local selection; server response will refresh state.
	_fuse_selection = []


func _on_fuse_clear_pressed() -> void:
	_fuse_selection = []
	_populate_fuse_candidates()
	_refresh_fuse_selection_state()


# ===== HELPERS =====

func _find_companion_in_source(source: String, index: int):
	"""Returns the companion dict or null if no longer present (after fusion)."""
	if source == "kennel" and index >= 0 and index < _kennel.size():
		return _kennel[index]
	if source == "registered" and index >= 0 and index < _registered.size():
		return _registered[index]
	return null


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
	_root_panel.custom_minimum_size = Vector2(940, 620)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.10, 0.08, 0.16, 0.98)
	panel_sb.border_color = Color(1.0, 0.5, 1.0)
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 18
	panel_sb.content_margin_right = 18
	panel_sb.content_margin_top = 14
	panel_sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(_root_panel)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 10)
	_root_panel.add_child(root_vb)

	# Header.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root_vb.add_child(header)

	_title_label = RichTextLabel.new()
	_title_label.bbcode_enabled = true
	_title_label.fit_content = true
	_title_label.scroll_active = false
	_title_label.add_theme_font_size_override("normal_font_size", 18)
	_title_label.custom_minimum_size = Vector2(0, 26)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.append_text("[color=#FF80FF]✦ Companion Stable ✦[/color]")
	header.add_child(_title_label)

	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn := HelpPanelScript.make_help_button("companion_stable", _help_panel)
	header.add_child(help_btn)

	_close_btn = Button.new()
	_close_btn.text = "Close (Esc)"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.pressed.connect(_on_close)
	header.add_child(_close_btn)

	# Tab bar.
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	root_vb.add_child(tab_bar)
	_tab_manage_btn = _make_tab_button("Manage", TAB_MANAGE)
	tab_bar.add_child(_tab_manage_btn)
	_tab_fuse_btn = _make_tab_button("Fuse", TAB_FUSE)
	tab_bar.add_child(_tab_fuse_btn)

	# Summary line.
	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.scroll_active = false
	_summary_label.add_theme_font_size_override("normal_font_size", 13)
	root_vb.add_child(_summary_label)

	# Body container holds both views.
	var body := Control.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(900, 480)
	root_vb.add_child(body)

	_manage_view = _build_manage_view()
	_manage_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(_manage_view)

	_fuse_view = _build_fuse_view()
	_fuse_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(_fuse_view)

	_set_tab(TAB_MANAGE)


func _make_tab_button(text: String, tab_id: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120, 28)
	btn.pressed.connect(func(): _set_tab(tab_id))
	return btn


func _build_manage_view() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.scroll_active = false
	hint.add_theme_font_size_override("normal_font_size", 12)
	hint.append_text("[color=#888888]Deposit a collected companion to send it to the kennel — or withdraw a kennel companion into your roster. Registered companions return to their slot (registration preserved).[/color]")
	vb.add_child(hint)

	var body_hb := HBoxContainer.new()
	body_hb.add_theme_constant_override("separation", 14)
	body_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body_hb)

	body_hb.add_child(_build_manage_column("[color=#87CEEB]Your Roster (Collected)[/color]", true))
	body_hb.add_child(_build_manage_column("[color=#A335EE]Sanctuary Kennel[/color]", false))

	return vb


func _build_manage_column(title_bb: String, is_collected: bool) -> Control:
	var col_panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	sb.border_color = Color(0.3, 0.3, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	col_panel.add_theme_stylebox_override("panel", sb)
	col_panel.custom_minimum_size = Vector2(440, 460)
	col_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col_vb := VBoxContainer.new()
	col_vb.add_theme_constant_override("separation", 6)
	col_panel.add_child(col_vb)

	var col_header := RichTextLabel.new()
	col_header.bbcode_enabled = true
	col_header.fit_content = true
	col_header.scroll_active = false
	col_header.add_theme_font_size_override("normal_font_size", 14)
	col_header.append_text(title_bb)
	col_vb.add_child(col_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col_vb.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var empty_label := Label.new()
	empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	if is_collected:
		_collected_list = list
		_collected_empty = empty_label
	else:
		_kennel_list = list
		_kennel_empty = empty_label

	return col_panel


func _build_fuse_view() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	_fuse_hint_label = RichTextLabel.new()
	_fuse_hint_label.bbcode_enabled = true
	_fuse_hint_label.fit_content = true
	_fuse_hint_label.scroll_active = false
	_fuse_hint_label.add_theme_font_size_override("normal_font_size", 12)
	vb.add_child(_fuse_hint_label)

	# Candidate panel (single scrolling list).
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

	var cand_vb := VBoxContainer.new()
	cand_vb.add_theme_constant_override("separation", 6)
	cand_panel.add_child(cand_vb)

	var cand_header := RichTextLabel.new()
	cand_header.bbcode_enabled = true
	cand_header.fit_content = true
	cand_header.scroll_active = false
	cand_header.add_theme_font_size_override("normal_font_size", 14)
	cand_header.append_text("[color=#FFD700]Fusion Candidates[/color]   [color=#888888](sorted by monster type → sub-tier → level)[/color]")
	cand_vb.add_child(cand_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cand_vb.add_child(scroll)

	_fuse_candidates_list = VBoxContainer.new()
	_fuse_candidates_list.add_theme_constant_override("separation", 4)
	_fuse_candidates_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fuse_candidates_list)

	# Footer row: selection state + Fuse / Clear buttons.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	vb.add_child(footer)

	_fuse_selection_label = RichTextLabel.new()
	_fuse_selection_label.bbcode_enabled = true
	_fuse_selection_label.fit_content = true
	_fuse_selection_label.scroll_active = false
	_fuse_selection_label.add_theme_font_size_override("normal_font_size", 13)
	_fuse_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_fuse_selection_label)

	_fuse_clear_btn = Button.new()
	_fuse_clear_btn.text = "Clear"
	_fuse_clear_btn.focus_mode = Control.FOCUS_NONE
	_fuse_clear_btn.custom_minimum_size = Vector2(80, 30)
	_fuse_clear_btn.disabled = true
	_fuse_clear_btn.pressed.connect(_on_fuse_clear_pressed)
	footer.add_child(_fuse_clear_btn)

	_fuse_button = Button.new()
	_fuse_button.text = "✦ Fuse"
	_fuse_button.focus_mode = Control.FOCUS_NONE
	_fuse_button.custom_minimum_size = Vector2(120, 30)
	_fuse_button.disabled = true
	_fuse_button.pressed.connect(_on_fuse_button_pressed)
	footer.add_child(_fuse_button)

	return vb


func _on_close() -> void:
	visible = false
	emit_signal("close_requested")
