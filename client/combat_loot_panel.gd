extends Control
class_name CombatLootPanel

# Audit user-request 2026-05-14 — combat scratch-off slice. Replaces the loot
# summary on the victory card with an interactive 16-slot reveal grid. Server
# pre-rolls the bag; client clicks reveal one slot at a time; Done auto-flips
# the rest (showing what was missed but not awarding them).
#
# Lifecycle: client.gd opens this panel when a combat_end message arrives with
# a non-empty loot_bag, threads each combat_loot_reveal_result into reveal_slot,
# and calls finish() when combat_loot_done_result lands. The panel overlays the
# victory card (z=180, above victory z=150 and below action picker z=200).

signal slot_clicked(slot_index: int)
signal done_pressed
signal closed
# v0.9.566 — autoskip checkbox state changed by user. Client persists it.
signal autoskip_toggled(enabled: bool)
# Engagement arc — emitted when a special cell reveals so client.gd can dispatch
# the matching SFX. Names: "chain", "mystery", "trap", "plus_two".
signal play_sfx(name: String)

const SLOT_COUNT := 16
const GRID_COLS := 4
# v0.9.566 — delay between auto-picks when autoskip is on. Slow enough to read
# each card's reveal pop, fast enough that the panel clears quickly.
const AUTOSKIP_INTERVAL: float = 0.35

var _root_panel: PanelContainer
var _header_label: RichTextLabel
var _autoskip_checkbox: CheckBox
var _pinned_container: VBoxContainer  # v0.9.481 — "Equipment Found" banner row
var _reveals_label: RichTextLabel
var _grid: GridContainer
var _done_button: Button

var _cards: Array = []  # Array[PanelContainer], indexed by slot
var _card_labels: Array = []  # Array[RichTextLabel] mirror of _cards

# v0.9.596 — keyboard navigation. _focused_target is "grid" or "done";
# _focused_slot is the active grid index (0-15) when target is "grid".
var _focused_slot: int = 0
var _focused_target: String = "grid"  # "grid" or "done"

var _slots_data: Array = []  # Mirror of server-pushed slot view
var _reveals_used: int = 0
var _reveal_budget: int = 0
var _flock_kills: int = 1
# Tracks the kind of the most recently revealed slot so finish() can hold the
# panel open briefly when the player just hit a special cell (especially trap
# on the last reveal — the panel was auto-closing before the player could read
# what happened).
var _last_reveal_kind: String = ""

# v0.9.568 — reusable HelpPanel attached to the header ? Help button.
var _help_panel: Control = null
var _monster_tier: int = 1
var _cascade_active: bool = false
# v0.9.566 — autoskip state. Toggle persists across panel opens via client.gd.
var _autoskip_enabled: bool = false
var _autoskip_timer: Timer = null

# === Prize Shuffle (#49) ===
# Three-beat flow: "preview" (all cards face-up so the player learns the pool) →
# "shuffle" (flip down + animate the server's swap sequence so a sharp player can
# track a prize) → "hunt" (the existing budget-limited reveal). Autoskip and old
# servers (no preview data) skip straight to "hunt".
var _phase: String = "hunt"
var _preview_slots: Array = []   # pre-shuffle display content per position
var _swaps: Array = []           # [[a,b], ...] server swap sequence
var _shuffle_content: Array = [] # post-shuffle content per position (for peeks)
var _peek_tokens: int = 0
var _peek_armed: bool = false    # next card click spends a peek instead of revealing
var _shuffle_button: Button = null
var _peek_button: Button = null
const PREVIEW_AUTO_SECONDS: float = 4.5  # v0.9.703 — longer study window
var _preview_timer: Timer = null
var _preview_pulse_tweens: Array = []  # looping glows on notable preview cards


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 180
	_build_layout()
	visible = false


func _build_layout() -> void:
	# Dim backdrop so the victory card behind is muted but still visible.
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
	_root_panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.98)
	sb.border_color = Color(0.85, 0.7, 0.2, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_top = 14
	sb.content_margin_right = 16
	sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_root_panel.add_child(vbox)

	# Title row — title centered, autoskip toggle in top-right corner.
	# v0.9.566: autoskip lets players skip the click-fest after the novelty
	# of the reveal animation wears off.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)

	# v0.9.568 — replace the left visual spacer with the Help button so the
	# title stays centered between symmetric controls (help on the left,
	# autoskip checkbox on the right).
	var HelpPanelScript = load("res://client/help_panel.gd")
	_help_panel = HelpPanelScript.new()
	add_child(_help_panel)
	var help_btn = HelpPanelScript.make_help_button("combat_loot", _help_panel)
	help_btn.custom_minimum_size = Vector2(120, 0)
	title_row.add_child(help_btn)

	var title := Label.new()
	title.text = "Loot Reveal"
	title.add_theme_color_override("font_color", Color(1, 0.84, 0))
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	_autoskip_checkbox = CheckBox.new()
	_autoskip_checkbox.text = "Autoskip"
	_autoskip_checkbox.tooltip_text = "When on, the panel auto-clicks random unrevealed cells until your reveal budget runs out, then auto-closes."
	_autoskip_checkbox.focus_mode = Control.FOCUS_NONE
	_autoskip_checkbox.custom_minimum_size = Vector2(120, 0)
	_autoskip_checkbox.toggled.connect(_on_autoskip_toggled)
	title_row.add_child(_autoskip_checkbox)

	# Header — tier + flock info
	_header_label = RichTextLabel.new()
	_header_label.bbcode_enabled = true
	_header_label.fit_content = true
	_header_label.scroll_active = false
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_label.add_theme_font_size_override("normal_font_size", 13)
	_header_label.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(_header_label)

	# v0.9.481 — pinned-equipment banner. Equipment drops are awarded directly
	# (not buried in the random slot pool) so the pre-scratch-off cadence is
	# preserved. The banner shows up only when pinned[] is non-empty; otherwise
	# the container collapses to zero height so the layout is unchanged.
	_pinned_container = VBoxContainer.new()
	_pinned_container.add_theme_constant_override("separation", 2)
	_pinned_container.visible = false
	vbox.add_child(_pinned_container)

	# Reveals counter
	_reveals_label = RichTextLabel.new()
	_reveals_label.bbcode_enabled = true
	_reveals_label.fit_content = true
	_reveals_label.scroll_active = false
	_reveals_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveals_label.add_theme_font_size_override("normal_font_size", 15)
	_reveals_label.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(_reveals_label)

	# 4x4 grid
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(_grid)
	for i in range(SLOT_COUNT):
		var card := _build_card(i)
		_cards.append(card)
		_grid.add_child(card)

	# Footer
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(footer_hbox)

	# Prize Shuffle (#49) — Peek button (hunt phase, only when tokens remain).
	_peek_button = Button.new()
	_peek_button.text = "Peek"
	_peek_button.focus_mode = Control.FOCUS_NONE
	_peek_button.custom_minimum_size = Vector2(120, 36)
	_peek_button.tooltip_text = "Spend a rare peek to briefly re-show one face-down cell — no reveal used."
	_peek_button.visible = false
	_peek_button.pressed.connect(_on_peek_pressed)
	footer_hbox.add_child(_peek_button)

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer)

	# Prize Shuffle (#49) — Shuffle button (preview phase: start the shuffle early
	# instead of waiting out the auto-timer).
	_shuffle_button = Button.new()
	_shuffle_button.text = "Shuffle →"
	_shuffle_button.focus_mode = Control.FOCUS_NONE
	_shuffle_button.custom_minimum_size = Vector2(140, 36)
	_shuffle_button.tooltip_text = "Hide and shuffle the prizes, then hunt for them."
	_shuffle_button.visible = false
	_shuffle_button.pressed.connect(_on_shuffle_pressed)
	footer_hbox.add_child(_shuffle_button)

	_done_button = Button.new()
	_done_button.text = "Done"
	_done_button.focus_mode = Control.FOCUS_NONE
	_done_button.custom_minimum_size = Vector2(140, 36)
	_done_button.pressed.connect(_on_done_pressed)
	footer_hbox.add_child(_done_button)


func _build_card(slot_index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(112, 76)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.14, 1.0)
	sb.border_color = Color(0.55, 0.45, 0.85, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var inner := RichTextLabel.new()
	inner.bbcode_enabled = true
	inner.fit_content = true
	inner.scroll_active = false
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_font_size_override("normal_font_size", 13)
	inner.text = "[center][color=#888888]?[/color][/center]"
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(inner)
	_card_labels.append(inner)

	var captured := slot_index
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_card_clicked(captured))
	return card


func _grow_grid_to(n: int) -> void:
	"""v0.9.664 — extend the grid mid-session (bonus reveals added cells server
	side). Pad _slots_data with sealed placeholders, rebuild the cards to match,
	then render the newly-added sealed tiles."""
	var old: int = _cards.size()
	while _slots_data.size() < n:
		_slots_data.append({"kind": "sealed", "revealed": false})
	_ensure_card_count(n)
	for i in range(old, _cards.size()):
		_render_card(i)


func _ensure_card_count(n: int) -> void:
	"""v0.9.664 — the bag can grow past the default 16 slots (big flock / jackpot
	budgets add cells so no reveal is wasted). Build/trim cards to match the bag,
	and scale the column count so the grid stays roughly square."""
	n = max(1, n)
	if _grid == null:
		return
	# Scale columns so tall bags don't run off the panel.
	var cols: int = GRID_COLS
	if n > 24:
		cols = 6
	elif n > 16:
		cols = 5
	_grid.columns = cols
	# Add missing cards.
	while _cards.size() < n:
		var card := _build_card(_cards.size())
		_cards.append(card)
		_grid.add_child(card)
	# Remove extras (also trim the label mirror _build_card appended to).
	while _cards.size() > n:
		var idx := _cards.size() - 1
		var card = _cards[idx]
		if is_instance_valid(card):
			_grid.remove_child(card)
			card.queue_free()
		_cards.remove_at(idx)
		if idx < _card_labels.size():
			_card_labels.remove_at(idx)


# === Public API ===

func open_bag(bag_view: Dictionary) -> void:
	"""Initial open: show 16 sealed cards plus the budget counter. bag_view
	matches server.gd::_serialize_combat_loot_bag_for_client."""
	_slots_data = bag_view.get("slots", []).duplicate(true)
	_reveals_used = int(bag_view.get("reveals_used", 0))
	_reveal_budget = int(bag_view.get("reveal_budget", 0))
	_flock_kills = int(bag_view.get("flock_kills", 1))
	_monster_tier = int(bag_view.get("monster_tier", 1))
	_cascade_active = false
	# v0.9.566 — restore persisted autoskip preference. Client passes it via
	# bag_view["autoskip_enabled"] (added in client.gd at open_bag callsite).
	_autoskip_enabled = bool(bag_view.get("autoskip_enabled", false))
	if _autoskip_checkbox != null:
		_autoskip_checkbox.set_pressed_no_signal(_autoskip_enabled)
	# Prize Shuffle (#49) — preview snapshot + swap sequence + peek tokens.
	_preview_slots = bag_view.get("preview", []).duplicate(true)
	_swaps = bag_view.get("swaps", []).duplicate(true)
	_peek_tokens = int(bag_view.get("peek_tokens", 0))
	_peek_armed = false
	_ensure_card_count(_slots_data.size())
	_render_header()
	_render_pinned(bag_view.get("pinned", []))
	visible = true
	# Preview phase — only when we have preview data AND the player isn't
	# autoskipping (they want speed, not knowledge). Old servers omit "preview"
	# → fall through to the classic hunt open below.
	if not _autoskip_enabled and _preview_slots.size() >= _slots_data.size() and _preview_slots.size() > 0:
		_enter_preview()
		return
	# Classic hunt open (autoskip / no preview data).
	_phase = "hunt"
	_render_reveals_counter()
	_render_all_cards()
	_refresh_action_buttons()
	# v0.9.596 — seed keyboard focus on the first unrevealed card so the
	# player can press Enter/Space immediately without first reaching for the
	# mouse. Autoskip path skips visuals entirely.
	_focused_target = "grid"
	_focused_slot = _first_unrevealed_slot()
	_apply_focus_visuals()
	# Kick off autoskip if enabled. Defer one frame so the panel finishes
	# layout before the first auto-click fires.
	if _autoskip_enabled:
		call_deferred("_start_autoskip")


func _start_autoskip() -> void:
	"""v0.9.566 — start the auto-pick timer. Picks one random unrevealed cell
	per AUTOSKIP_INTERVAL seconds until budget is exhausted, then auto-presses
	Done to trigger the cascade reveal of the remaining cells."""
	if not _autoskip_enabled or _cascade_active:
		return
	if _autoskip_timer != null:
		return
	_autoskip_timer = Timer.new()
	_autoskip_timer.wait_time = AUTOSKIP_INTERVAL
	_autoskip_timer.one_shot = false
	_autoskip_timer.timeout.connect(_on_autoskip_tick)
	add_child(_autoskip_timer)
	_autoskip_timer.start()


func _stop_autoskip() -> void:
	if _autoskip_timer != null:
		_autoskip_timer.stop()
		_autoskip_timer.queue_free()
		_autoskip_timer = null


func _on_autoskip_tick() -> void:
	# Stop if user toggled off or budget exhausted or cascade firing.
	if not _autoskip_enabled or _cascade_active:
		_stop_autoskip()
		return
	if _reveals_used >= _reveal_budget:
		_stop_autoskip()
		# Trigger Done so the remaining unrevealed cells cascade-reveal.
		_on_done_pressed()
		return
	# Build pool of unrevealed slot indices and pick one at random.
	var unrevealed: Array[int] = []
	for i in range(_slots_data.size()):
		var slot: Dictionary = _slots_data[i]
		if not bool(slot.get("revealed", false)):
			unrevealed.append(i)
	if unrevealed.is_empty():
		_stop_autoskip()
		_on_done_pressed()
		return
	var pick = unrevealed[randi() % unrevealed.size()]
	emit_signal("slot_clicked", pick)


func _on_autoskip_toggled(pressed: bool) -> void:
	_autoskip_enabled = pressed
	autoskip_toggled.emit(pressed)
	if pressed:
		_start_autoskip()
	else:
		_stop_autoskip()


# === Prize Shuffle (#49) — preview → shuffle → hunt ===

func _refresh_action_buttons() -> void:
	"""Show the footer controls appropriate to the current phase."""
	if _shuffle_button != null:
		_shuffle_button.visible = (_phase == "preview")
	if _done_button != null:
		_done_button.visible = (_phase == "hunt")
		_done_button.disabled = _cascade_active
	if _peek_button != null:
		_peek_button.visible = (_phase == "hunt" and _peek_tokens > 0)
		_peek_button.text = ("Peek (%d)" % _peek_tokens)
		_peek_button.disabled = (_peek_tokens <= 0)
	if _autoskip_checkbox != null:
		_autoskip_checkbox.visible = (_phase == "hunt")


func _enter_preview() -> void:
	"""Beat 1 — show every cell face-up so the player learns the pool; the best
	prizes are highlighted. Auto-advances to the shuffle, or the player can hit
	the Shuffle button to start early."""
	_phase = "preview"
	_cascade_active = false
	_header_label.text = "[center][color=#FFD54A][b]✦ Memorize the prizes! ✦[/b][/color]   [color=#999]the best are highlighted[/color][/center]"
	# Callout the single best prize so the player has a clear target to track.
	var best: Dictionary = _best_preview_prize()
	if not best.is_empty():
		var bcolor: String = String(best.get("color", "#FFD700"))
		var bname: String = String(best.get("name", ""))
		if bname == "":
			bname = _kind_display_name(String(best.get("kind", "")))
		_reveals_label.text = "[center][color=#FFD700]★ Top prize:[/color] [color=%s][b]%s[/b][/color] [color=#FFD700]★[/color][/center]" % [bcolor, bname]
	else:
		_reveals_label.text = "[center][color=#FFD54A]Prize preview…[/color][/center]"
	for i in range(_cards.size()):
		_render_preview_card(i)
	_refresh_action_buttons()
	if _preview_timer != null and is_instance_valid(_preview_timer):
		_preview_timer.queue_free()
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = PREVIEW_AUTO_SECONDS
	_preview_timer.timeout.connect(_on_shuffle_pressed)
	add_child(_preview_timer)
	_preview_timer.start()


func _on_shuffle_pressed() -> void:
	if _phase != "preview":
		return
	if _preview_timer != null and is_instance_valid(_preview_timer):
		_preview_timer.stop()
		_preview_timer.queue_free()
		_preview_timer = null
	_enter_shuffle()


func _enter_shuffle() -> void:
	"""Beat 2 — flip every card face-down, then replay the server's swap sequence
	with floating overlays so a sharp-eyed player can follow the prize they want.
	After the swaps, position p holds the same content as the server's slots[p]."""
	_phase = "shuffle"
	if _shuffle_button != null:
		_shuffle_button.visible = false
	_header_label.text = "[center][color=#5C9DFF][b]Shuffling…[/b][/color]  [color=#999]follow the prize you want![/color][/center]"
	_reveals_label.text = ""
	emit_signal("play_sfx", "shuffle")  # v0.9.703 juice — soft shuffle cue
	# Stop the notable-card glow pulses so cards reset to neutral before flipping.
	_stop_preview_pulses()
	# Track post-shuffle content per position (for peeks) by replaying the swaps.
	_shuffle_content = _preview_slots.duplicate(true)
	# Fixed card positions (grid-local); overlays move between these.
	var card_pos: Array = []
	for i in range(_cards.size()):
		_cards[i].modulate = Color.WHITE  # clear any leftover pulse brightness
		_render_card(i)  # sealed look under the overlays
		card_pos.append(_cards[i].global_position - global_position)
	var overlays: Array = []
	for i in range(_cards.size()):
		overlays.append(_make_shuffle_overlay(i, card_pos[i]))
	# v0.9.710 — faster + more overlapping movement (playtest: was too slow).
	var per: float = clampf(1.0 / float(max(1, _swaps.size())), 0.06, 0.16)
	var step: float = 0.0
	for pair in _swaps:
		if not (pair is Array) or pair.size() < 2:
			continue
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		if a < 0 or b < 0 or a >= overlays.size() or b >= overlays.size() or a == b:
			continue
		# Content follows the swap so _shuffle_content ends matching the server.
		var ca = _shuffle_content[a]
		_shuffle_content[a] = _shuffle_content[b]
		_shuffle_content[b] = ca
		# Capture the actual nodes + targets (positions are fixed per index).
		var node_a = overlays[a]
		var node_b = overlays[b]
		var tgt_a: Vector2 = card_pos[b]
		var tgt_b: Vector2 = card_pos[a]
		var dur: float = per
		_call_deferred_after(step, func():
			_tween_move(node_a, tgt_a, dur)
			_tween_move(node_b, tgt_b, dur))
		# Reflect the swap in the overlay index map for subsequent swaps.
		overlays[a] = node_b
		overlays[b] = node_a
		step += per * 0.5  # more overlap = more simultaneous movement, faster overall
	# Fade overlays + enter the hunt after the last swap settles.
	var captured_overlays := overlays
	_call_deferred_after(step + per + 0.15, func():
		for ov in captured_overlays:
			if is_instance_valid(ov):
				var tw := create_tween()
				tw.tween_property(ov, "modulate:a", 0.0, 0.18)
				tw.tween_callback(Callable(ov, "queue_free"))
		_enter_hunt())


func _make_shuffle_overlay(slot_index: int, local_pos: Vector2) -> Control:
	"""A floating face-up copy of a preview cell that the shuffle animates."""
	var slot: Dictionary = _preview_slots[slot_index] if slot_index < _preview_slots.size() else {}
	var color_hex: String = String(slot.get("color", "#FFFFFF"))
	var rgb: Color = Color.html(color_hex) if color_hex != "" else Color.WHITE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 20
	panel.size = _cards[slot_index].size
	panel.position = local_pos
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(rgb.r * 0.28, rgb.g * 0.28, rgb.b * 0.28, 1.0)
	sb.border_color = Color(1, 0.85, 0.3, 1) if _is_notable(slot) else Color(rgb.r, rgb.g, rgb.b, 0.9)
	sb.set_border_width_all(3 if _is_notable(slot) else 2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("normal_font_size", 12)
	lbl.text = _slot_display_bbcode(slot)
	panel.add_child(lbl)
	# Parent to the panel Control (NOT the GridContainer, which would lay the
	# overlay out as a cell and override our manual positions).
	add_child(panel)
	return panel


func _tween_move(node: Control, target: Vector2, dur: float) -> void:
	if not is_instance_valid(node):
		return
	var tw := create_tween()
	tw.tween_property(node, "position", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _enter_hunt() -> void:
	"""Beat 3 — the classic budget-limited reveal, now with knowledge + peeks."""
	_phase = "hunt"
	_render_header()
	_render_reveals_counter()
	_render_all_cards()
	_refresh_action_buttons()
	_focused_target = "grid"
	_focused_slot = _first_unrevealed_slot()
	_apply_focus_visuals()
	if _autoskip_enabled:
		call_deferred("_start_autoskip")


func _on_peek_pressed() -> void:
	if _phase != "hunt" or _peek_tokens <= 0:
		return
	_peek_armed = not _peek_armed
	if _peek_armed:
		_header_label.text = "[center][color=#7FD8C8][b]Peek armed[/b] — click a face-down cell to sneak a look.[/color][/center]"
	else:
		_render_header()


func _do_peek(slot_index: int) -> void:
	if _peek_tokens <= 0 or slot_index < 0 or slot_index >= _cards.size():
		return
	if slot_index >= _slots_data.size() or bool(_slots_data[slot_index].get("revealed", false)):
		return
	_peek_tokens -= 1
	_peek_armed = false
	emit_signal("play_sfx", "mystery")
	var content: Dictionary = _shuffle_content[slot_index] if slot_index < _shuffle_content.size() else {}
	_show_peek_overlay(slot_index, content)
	_render_header()
	_refresh_action_buttons()


func _show_peek_overlay(slot_index: int, content: Dictionary) -> void:
	var card: Control = _cards[slot_index]
	if not is_instance_valid(card):
		return
	var overlay := PanelContainer.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 30
	overlay.size = card.size
	overlay.position = card.global_position - global_position
	var color_hex: String = String(content.get("color", "#FFFFFF"))
	var rgb: Color = Color.html(color_hex) if color_hex != "" else Color.WHITE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(rgb.r * 0.3, rgb.g * 0.3, rgb.b * 0.3, 1.0)
	sb.border_color = Color(0.5, 0.85, 0.78, 1)  # teal peek frame
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	overlay.add_theme_stylebox_override("panel", sb)
	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("normal_font_size", 12)
	lbl.text = _slot_display_bbcode(content)
	overlay.add_child(lbl)
	add_child(overlay)
	_call_deferred_after(1.8, func():
		if is_instance_valid(overlay):
			var tw := create_tween()
			tw.tween_property(overlay, "modulate:a", 0.0, 0.25)
			tw.tween_callback(Callable(overlay, "queue_free")))


func _render_preview_card(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _cards.size():
		return
	var card: PanelContainer = _cards[slot_index]
	var lbl: RichTextLabel = _card_labels[slot_index]
	var slot: Dictionary = _preview_slots[slot_index] if slot_index < _preview_slots.size() else {}
	var color_hex: String = String(slot.get("color", "#FFFFFF"))
	var rgb: Color = Color.html(color_hex) if color_hex != "" else Color.WHITE
	var notable: bool = _is_notable(slot)
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	sb.bg_color = Color(rgb.r * 0.22, rgb.g * 0.22, rgb.b * 0.22, 1.0)
	sb.border_color = Color(1, 0.85, 0.3, 1) if notable else Color(rgb.r, rgb.g, rgb.b, 0.85)
	sb.set_border_width_all(3 if notable else 2)
	card.add_theme_stylebox_override("panel", sb)
	var star: String = "[color=#FFD700]✦[/color] " if notable else ""
	lbl.text = _slot_display_bbcode(slot, star)
	if notable:
		_play_preview_pulse(card)


func _play_preview_pulse(card: Control) -> void:
	"""v0.9.703 — a looping brightness pulse so notable prizes visibly 'breathe'
	during the preview and draw the eye. Tracked so _enter_shuffle can stop them."""
	if not is_instance_valid(card):
		return
	var tw := create_tween().set_loops()
	tw.tween_property(card, "modulate", Color(1.35, 1.35, 1.15, 1.0), 0.55).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.55).set_trans(Tween.TRANS_SINE)
	_preview_pulse_tweens.append(tw)


func _stop_preview_pulses() -> void:
	for tw in _preview_pulse_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_preview_pulse_tweens.clear()


func _best_preview_prize() -> Dictionary:
	"""v0.9.703 — the single most valuable slot in the pool, for the top-prize
	callout. Higher score = better."""
	var best: Dictionary = {}
	var best_score: int = 0
	for slot in _preview_slots:
		if not (slot is Dictionary):
			continue
		var score: int = 0
		match String(slot.get("rarity", "")):
			"legendary": score = 100
			"epic": score = 80
			"rare": score = 60
			"uncommon": score = 25
		match String(slot.get("kind", "")):
			"egg", "egg_full": score = max(score, 70)
			"filler_mystery": score = max(score, 45)
			"filler_plus_two": score = max(score, 35)
			"filler_chain": score = max(score, 30)
		if score > best_score:
			best_score = score
			best = slot
	return best


func _is_notable(slot: Dictionary) -> bool:
	"""Prizes worth chasing — draws the eye during preview."""
	var r: String = String(slot.get("rarity", ""))
	if r in ["rare", "epic", "legendary"]:
		return true
	var k: String = String(slot.get("kind", ""))
	return k in ["filler_plus_two", "filler_mystery", "filler_chain", "egg", "egg_full"]


func _slot_display_bbcode(slot: Dictionary, prefix: String = "") -> String:
	var color_hex: String = String(slot.get("color", "#FFFFFF"))
	var name: String = String(slot.get("name", ""))
	if name == "":
		name = _kind_display_name(String(slot.get("kind", "")))
	var symbol: String = String(slot.get("symbol", ""))
	var sym: String = ("[color=%s]%s[/color] " % [color_hex, symbol]) if symbol != "" else ""
	return "[center]%s%s[color=%s]%s[/color][/center]" % [prefix, sym, color_hex, name]


func _render_pinned(pinned: Array) -> void:
	"""Render the equipment-found banner. v0.9.481 — pinned equipment is
	already awarded server-side; this panel only displays what landed in
	inventory so the player sees the gear they got."""
	for child in _pinned_container.get_children():
		child.queue_free()
	if pinned.is_empty():
		_pinned_container.visible = false
		return
	_pinned_container.visible = true
	# Header line
	var header := RichTextLabel.new()
	header.bbcode_enabled = true
	header.fit_content = true
	header.scroll_active = false
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_font_size_override("normal_font_size", 14)
	header.custom_minimum_size = Vector2(0, 22)
	header.text = "[center][color=#FFD700][b]✦ Equipment Found ✦[/b][/color][/center]"
	_pinned_container.add_child(header)
	# One row per pinned item, styled by rarity.
	for entry in pinned:
		if not (entry is Dictionary):
			continue
		var row := RichTextLabel.new()
		row.bbcode_enabled = true
		row.fit_content = true
		row.scroll_active = false
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_font_size_override("normal_font_size", 13)
		row.custom_minimum_size = Vector2(0, 18)
		var name: String = String(entry.get("name", "Unknown Item"))
		var color_hex: String = String(entry.get("color", "#FFFFFF"))
		var symbol: String = String(entry.get("symbol", ""))
		var sym_prefix: String = ("%s " % symbol) if symbol != "" else ""
		var kind: String = String(entry.get("kind", "item"))
		# Auto-salvaged or inventory-full variants get a small tag so the
		# player understands what happened. The kind is what _award_real_combat_loot
		# returns; "item" = normal pickup, "auto_salvaged" / "inv_full_salvaged"
		# / "inv_full_lost" cover the other branches.
		var suffix := ""
		match kind:
			"auto_salvaged":
				suffix = " [color=#888888](auto-salvaged)[/color]"
			"inv_full_salvaged":
				suffix = " [color=#FF8800](inv full → salvaged)[/color]"
			"inv_full_lost":
				suffix = " [color=#FF4444](inv full, lost)[/color]"
			_:
				suffix = " [color=#888888]→ inventory[/color]"
		row.text = "[center][color=%s]%s%s[/color]%s[/center]" % [color_hex, sym_prefix, name, suffix]
		_pinned_container.add_child(row)


func reveal_slot(slot_index: int, reveal_data: Dictionary, reveals_used: int, reveal_budget: int, chain_neighbors: Array = [], total_slots: int = 0) -> void:
	"""Server confirmed a reveal — flip the card to show the awarded outcome.
	When chain_neighbors[] is non-empty (the awarded slot was a Chain cell), the
	panel cascades the neighbor reveals on a 60ms stagger after the shockwave.
	total_slots (v0.9.664): the server can GROW the grid mid-session when a bonus
	reveal (+2 / Chain) adds budget — add the new sealed cards first so the extra
	reveals have somewhere to land."""
	if total_slots > _cards.size():
		_grow_grid_to(total_slots)
	if slot_index < 0 or slot_index >= _cards.size():
		return
	if slot_index >= _slots_data.size():
		# Defensive — pad if bag_view was somehow short.
		while _slots_data.size() <= slot_index:
			_slots_data.append({"kind": "sealed", "revealed": false})
	_slots_data[slot_index] = reveal_data.duplicate(true)
	_slots_data[slot_index]["revealed"] = true
	_reveals_used = reveals_used
	_reveal_budget = reveal_budget
	_render_card(slot_index)
	_render_reveals_counter()
	_play_reveal_pop(slot_index)
	# Engagement-arc FX + SFX per kind. Each special cell gets a distinct
	# visual flourish on top of the base scale-pop. Sound dispatches via the
	# play_sfx signal; client.gd wires those to existing SFX players.
	var kind: String = String(reveal_data.get("kind", ""))
	_last_reveal_kind = kind
	match kind:
		"filler_chain":
			emit_signal("play_sfx", "chain")
			_play_chain_shockwave(slot_index)
		"filler_mystery":
			emit_signal("play_sfx", "mystery")
			_play_mystery_shimmer(slot_index)
		"filler_trap":
			emit_signal("play_sfx", "trap")
			_play_trap_flash_and_shake(slot_index)
		"filler_plus_two":
			emit_signal("play_sfx", "plus_two")
	# v0.9.703 juice — a real rare/epic/legendary or egg reveal is a "you got it!"
	# moment: gold burst + rare-drop sound + a bigger pop on top of the base flip.
	var rar: String = String(reveal_data.get("rarity", ""))
	if rar in ["rare", "epic", "legendary"] or kind in ["egg", "egg_full"]:
		emit_signal("play_sfx", "reveal_big")
		_play_mystery_shimmer(slot_index)
		_play_big_celebration(slot_index)
	# Chain neighbors cascade — server already revealed + awarded them; we just
	# flip the visuals on a stagger so the player reads the chain pattern.
	if not chain_neighbors.is_empty():
		var stagger: float = 0.07
		var delay: float = 0.15  # let the shockwave breathe before neighbors flip
		for entry in chain_neighbors:
			if not (entry is Dictionary):
				continue
			var n_idx: int = int(entry.get("slot_index", -1))
			var n_reveal: Dictionary = entry.get("reveal", {})
			if n_idx < 0 or n_idx >= _cards.size():
				continue
			var captured_idx := n_idx
			var captured_reveal := n_reveal.duplicate(true)
			_call_deferred_after(delay, func():
				if captured_idx < _slots_data.size():
					_slots_data[captured_idx] = captured_reveal
					_slots_data[captured_idx]["revealed"] = true
				_render_card(captured_idx)
				_play_reveal_pop(captured_idx)
				# Trap-in-chain still bites — flash + shake the neighbor too.
				var nk: String = String(captured_reveal.get("kind", ""))
				if nk == "filler_trap":
					_play_trap_flash_and_shake(captured_idx)
				elif nk == "filler_mystery":
					_play_mystery_shimmer(captured_idx))
			delay += stagger
	# v0.9.596 — advance keyboard focus to the next unrevealed card so the
	# player can hammer Enter without re-aiming. If everything is revealed,
	# move focus to the Done button.
	if _focused_target == "grid" and _focused_slot == slot_index:
		if _reveals_used >= _reveal_budget:
			_focused_target = "done"
		else:
			_focused_slot = _first_unrevealed_slot()
		_apply_focus_visuals()


func finish(final_bag: Dictionary) -> void:
	"""Server says done — close the panel.

	v0.9.603 — scrapped the cascade-reveal animation per player feedback:
	'It doesn't stay on the screen long enough for players to really read any
	of it and it's not exactly helpful because they can't go back and change
	their options.' The cascade was flipping missed tiles one-by-one with a
	60ms-per-card stagger; total reveal time was up to ~1.5s and there was
	no payoff. Now we just close the panel — the accumulated loot is already
	on the victory card (v0.9.602 atomic refresh path).

	v0.9.645 — when the last reveal was a special cell (trap especially),
	hold the panel open ~1.4s so the player can read what happened. The
	auto-close was firing the same frame as the trap reveal, so players only
	found out they'd been trapped from the victory-screen breakdown."""
	_cascade_active = true
	_done_button.disabled = true
	# Still mirror the final slot state internally so anyone querying the
	# panel post-close sees the correct "missed" labels. Just no animation.
	var final_slots: Array = final_bag.get("slots", [])
	for i in range(min(final_slots.size(), _cards.size())):
		if not bool(_slots_data[i].get("revealed", false)):
			_slots_data[i] = final_slots[i].duplicate(true)
			_slots_data[i]["revealed"] = true
			_slots_data[i]["missed"] = true
	# Hold open if the player just flipped a special — gives the FX time to
	# play out AND lets them read the result line on the card itself.
	var hold_seconds: float = 0.0
	match _last_reveal_kind:
		"filler_trap":
			hold_seconds = 1.4
		"filler_chain":
			hold_seconds = 1.0  # neighbor cascade is ~0.5s; give a beat after
		"filler_mystery", "filler_plus_two":
			hold_seconds = 0.8
	if hold_seconds <= 0.0:
		visible = false
		emit_signal("closed")
		return
	_call_deferred_after(hold_seconds, func():
		visible = false
		emit_signal("closed"))


func _call_deferred_after(delay: float, fn: Callable) -> void:
	"""Schedule fn to run after `delay` seconds. Uses a one-shot Timer so we
	don't depend on get_tree().create_timer (which is fine but harder to test)."""
	if delay <= 0.0:
		fn.call()
		return
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = max(0.01, delay)
	t.timeout.connect(func():
		fn.call()
		t.queue_free())
	add_child(t)
	t.start()


# === Internal rendering ===

func _render_header() -> void:
	var parts: Array = []
	parts.append("[color=#888]Tier %d monster[/color]" % _monster_tier)
	if _flock_kills > 1:
		parts.append("[color=#FFAA00]Flock x%d[/color]" % _flock_kills)
	_header_label.text = "[center]" + "   ·   ".join(parts) + "[/center]"


func _render_reveals_counter() -> void:
	var remaining: int = max(0, _reveal_budget - _reveals_used)
	var color: String = "#88FF88" if remaining > 0 else "#FF6644"
	_reveals_label.text = "[center][color=%s][b]Reveals remaining: %d / %d[/b][/color][/center]" % [color, remaining, _reveal_budget]


func _render_all_cards() -> void:
	for i in range(_cards.size()):
		_render_card(i)


func _render_card(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _cards.size():
		return
	var card: PanelContainer = _cards[slot_index]
	var lbl: RichTextLabel = _card_labels[slot_index]
	var slot: Dictionary = _slots_data[slot_index] if slot_index < _slots_data.size() else {"kind": "sealed"}
	var revealed: bool = bool(slot.get("revealed", false))
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	if not revealed:
		# Sealed card. v0.9.603 — show the QWERTY key letter for this slot
		# instead of a generic "?". Player can read it and press that key.
		# Light yellow tint matches the focus highlight palette without
		# overwhelming the unrevealed look.
		sb.bg_color = Color(0.10, 0.08, 0.14, 1.0)
		sb.border_color = Color(0.55, 0.45, 0.85, 1)
		card.add_theme_stylebox_override("panel", sb)
		var key_label: String = _SLOT_KEY_LABELS[slot_index] if slot_index >= 0 and slot_index < _SLOT_KEY_LABELS.size() else "?"
		lbl.text = "[center][color=#D4C376][font_size=22][b]%s[/b][/font_size][/color][/center]" % key_label
		return
	# Revealed — colored by kind. Missed (cascade) renders dim.
	var color_hex: String = String(slot.get("color", "#FFFFFF"))
	var name: String = String(slot.get("name", ""))
	var kind: String = String(slot.get("kind", "item"))
	var is_missed: bool = bool(slot.get("missed", false))
	# v0.9.602 — player-picked reveals (revealed AND not missed) get a thicker
	# brighter border + gold star marker so they pop visually from the
	# cascade-revealed "what you missed" tiles. Player report: the picked-vs-
	# missed distinction wasn't clear enough.
	var is_picked: bool = not is_missed
	var dim_fac: float = 0.55 if is_missed else 1.0
	var rgb := Color.html(color_hex) if color_hex != "" else Color.WHITE
	sb.bg_color = Color(rgb.r * 0.25 * dim_fac, rgb.g * 0.25 * dim_fac, rgb.b * 0.25 * dim_fac, 1.0)
	sb.border_color = Color(rgb.r, rgb.g, rgb.b, 0.6 if is_missed else 1.0)
	# Picked reveals get a 3px border (vs 2px for missed) so they read
	# bolder. The keyboard-focus border (also 3px, yellow) still wins when
	# active because _apply_focus_visuals paints AFTER _render_card.
	sb.set_border_width_all(3 if is_picked else 2)
	card.add_theme_stylebox_override("panel", sb)
	var miss_prefix: String = "[color=#888888][i](missed)[/i][/color] " if is_missed else ""
	# v0.9.602 — gold ★ on picked tiles so the player-earned loot is visually
	# unambiguous next to the cascade reveals.
	var pick_prefix: String = "[color=#FFD700]★[/color] " if is_picked else ""
	# Equipment reveals get the rarity symbol too.
	var symbol: String = String(slot.get("symbol", ""))
	var sym_prefix: String = ("[color=%s]%s[/color] " % [color_hex, symbol]) if symbol != "" else ""
	# v0.9.574 — +2 Reveals bonus cell gets a sparkle prefix so the lucky
	# pull reads obviously special. The cell already uses gold (#FFD700)
	# from the server side; the sparkle adds the "you found something" beat.
	if kind == "filler_plus_two":
		sym_prefix = "[color=#FFD700]✦[/color] " + sym_prefix
	# Same treatment for the three new special cells — each gets a distinct
	# glyph prefix so the player can tell at a glance what kind of special
	# they hit. Colors come from the server payload.
	elif kind == "filler_chain":
		sym_prefix = "[color=%s]⚡[/color] " % color_hex + sym_prefix
	elif kind == "filler_mystery":
		sym_prefix = "[color=%s]✦[/color] " % color_hex + sym_prefix
	elif kind == "filler_trap":
		sym_prefix = "[color=%s]☠[/color] " % color_hex + sym_prefix
	# Wrap in center + small font for compact reveal cards.
	var label_text: String = "[center]%s%s[color=%s]%s%s[/color][/center]" % [pick_prefix, miss_prefix, color_hex, sym_prefix, name]
	# Add subtle kind tag underneath for context.
	var kind_label: String = _kind_display_name(kind)
	if kind_label != "":
		label_text += "\n[center][color=#666666][font_size=10]%s[/font_size][/color][/center]" % kind_label
	lbl.text = label_text


func _kind_display_name(kind: String) -> String:
	match kind:
		"egg", "egg_full":
			return "Egg"
		"material":
			return "Material"
		"monster_part":
			return "Part"
		"item":
			return "Item"
		"auto_salvaged":
			return "Auto-salvaged"
		"inv_full_salvaged":
			return "Inv full → salvaged"
		"inv_full_lost":
			return "Inv full → lost"
		"filler_valor":
			return "Valor"
		"filler_essence":
			return "Essence"
		"filler_material":
			return "Mat"
		"filler_part":
			return "Part"
		"filler_plus_two":
			return "Bonus Reveals"
		"filler_chain":
			return "Chain Reveal"
		"filler_mystery":
			return "Mystery"
		"filler_trap":
			return "Trap"
		_:
			return ""


func _play_reveal_pop(slot_index: int) -> void:
	"""Subtle scale pop on the revealed card so the flip reads."""
	if slot_index < 0 or slot_index >= _cards.size():
		return
	var card: Control = _cards[slot_index]
	if not is_instance_valid(card):
		return
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(0.85, 0.85)
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector2(1.05, 1.05), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2(1.0, 1.0), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _play_chain_shockwave(slot_index: int) -> void:
	"""Chain reveal — expanding cyan ring overlay centered on the triggering
	cell. Fades out in ~0.35s. Tells the player which cell fired the chain
	before the neighbor cards start flipping."""
	if slot_index < 0 or slot_index >= _cards.size():
		return
	var card: Control = _cards[slot_index]
	if not is_instance_valid(card):
		return
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0.36, 0.62, 1.0, 0.95)  # cyan-blue, matches #5C9DFF
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	ring.add_theme_stylebox_override("panel", sb)
	ring.z_index = 10
	ring.size = card.size
	ring.position = card.global_position - _grid.global_position
	_grid.add_child(ring)
	ring.pivot_offset = ring.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(3.2, 3.2), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(Callable(ring, "queue_free"))


func _play_big_celebration(slot_index: int) -> void:
	"""v0.9.703 — the 'you got it!' flourish for a real rare+/egg reveal: a strong
	scale pop plus a gold expanding ring so the win reads as a big moment."""
	if slot_index < 0 or slot_index >= _cards.size():
		return
	var card: Control = _cards[slot_index]
	if not is_instance_valid(card):
		return
	# Strong pop.
	card.pivot_offset = card.size / 2.0
	var pop := create_tween()
	pop.tween_property(card, "scale", Vector2(1.22, 1.22), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(card, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Gold expanding ring (parented to the panel so the GridContainer won't relayout it).
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1.0, 0.84, 0.2, 0.95)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	ring.add_theme_stylebox_override("panel", sb)
	ring.z_index = 25
	ring.size = card.size
	ring.position = card.global_position - global_position
	add_child(ring)
	ring.pivot_offset = ring.size / 2.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.8, 2.8), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(Callable(ring, "queue_free"))


func _play_mystery_shimmer(slot_index: int) -> void:
	"""Mystery reveal — gold overlay flashes in then fades, giving the card a
	`jackpot` shimmer beat on top of the base scale-pop."""
	if slot_index < 0 or slot_index >= _cards.size():
		return
	var card: Control = _cards[slot_index]
	if not is_instance_valid(card):
		return
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.84, 0.0, 0.55)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = card.size
	glow.position = Vector2.ZERO
	glow.z_index = 5
	card.add_child(glow)
	var tw := create_tween()
	tw.tween_property(glow, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(Callable(glow, "queue_free"))


func _play_trap_flash_and_shake(slot_index: int) -> void:
	"""Trap reveal — red flash on the card + small shake of the panel root so
	the punishment reads physical."""
	if slot_index < 0 or slot_index >= _cards.size():
		return
	var card: Control = _cards[slot_index]
	if not is_instance_valid(card):
		return
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.15, 0.15, 0.75)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.size = card.size
	flash.position = Vector2.ZERO
	flash.z_index = 5
	card.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(Callable(flash, "queue_free"))
	# Panel shake — translate root by a few pixels in a quick back-and-forth.
	if _root_panel == null or not is_instance_valid(_root_panel):
		return
	var origin: Vector2 = _root_panel.position
	var shake := create_tween()
	shake.tween_property(_root_panel, "position", origin + Vector2(6, 0), 0.04)
	shake.tween_property(_root_panel, "position", origin + Vector2(-5, 0), 0.05)
	shake.tween_property(_root_panel, "position", origin + Vector2(3, 0), 0.04)
	shake.tween_property(_root_panel, "position", origin, 0.04)


# === Internal callbacks ===

func _on_card_clicked(slot_index: int) -> void:
	if _cascade_active:
		return
	# Prize Shuffle (#49) — no reveals during preview/shuffle; a peek intercepts.
	if _phase != "hunt":
		return
	if slot_index < 0 or slot_index >= _slots_data.size():
		return
	if bool(_slots_data[slot_index].get("revealed", false)):
		return
	if _peek_armed:
		_do_peek(slot_index)
		return
	if _reveals_used >= _reveal_budget:
		return
	emit_signal("slot_clicked", slot_index)


func _on_done_pressed() -> void:
	if _cascade_active:
		return
	_cascade_active = true
	_done_button.disabled = true
	_stop_autoskip()  # v0.9.566 — cancel autoskip timer if still running.
	emit_signal("done_pressed")


# === v0.9.596 / v0.9.602 keyboard navigation ===
#
# v0.9.602 — added QWERTY-grid direct-binding. Each grid slot has its own
# single keypress so the player doesn't have to navigate with arrow keys
# (which feels clunky and left a focus trail before the v0.9.602 fix).
# Arrow keys + Enter still work as a fallback.
#
# QWERTY-grid layout (positionally matches the 4×4 slot grid like a
# touch-typist's left hand):
# A single keypress immediately attempts to reveal that slot (same path
# as a click). Useful keys (Enter / Space / arrows / WASD / Tab) still work.
# v0.9.664 — extended from 16 to 30 keys (reading order: number row, then QWERTY
# rows) so the grown grid (up to COMBAT_LOOT_MAX_SLOTS=30) never shows a keyless
# "?" tile. The tile prints its own key, so a flat sequence reads fine even when
# the column count varies (4/5/6).
const _QWERTY_SLOT_KEYS := {
	KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3, KEY_5: 4, KEY_6: 5, KEY_7: 6, KEY_8: 7, KEY_9: 8, KEY_0: 9,
	KEY_Q: 10, KEY_W: 11, KEY_E: 12, KEY_R: 13, KEY_T: 14, KEY_Y: 15, KEY_U: 16, KEY_I: 17, KEY_O: 18, KEY_P: 19,
	KEY_A: 20, KEY_S: 21, KEY_D: 22, KEY_F: 23, KEY_G: 24, KEY_H: 25, KEY_J: 26, KEY_K: 27, KEY_L: 28,
	KEY_Z: 29, KEY_X: 30, KEY_C: 31, KEY_V: 32, KEY_B: 33, KEY_N: 34, KEY_M: 35,
}
# Inverse map: slot index → key label rendered on the sealed tile. Replaces the
# generic "?" so the player can see at a glance which key reveals each tile.
# 36 entries — matches COMBAT_LOOT_MAX_SLOTS so a fully-grown grid is all keyed.
const _SLOT_KEY_LABELS := [
	"1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
	"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P",
	"A", "S", "D", "F", "G", "H", "J", "K", "L",
	"Z", "X", "C", "V", "B", "N", "M",
]


func _input(event: InputEvent) -> void:
	if not visible or _cascade_active:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	# Prize Shuffle (#49) — during preview, Space/Enter starts the shuffle; block
	# all reveal keys until the hunt phase begins.
	if _phase != "hunt":
		if _phase == "preview" and k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_on_shuffle_pressed()
			get_viewport().set_input_as_handled()
		return
	# v0.9.602 — direct QWERTY-grid slot keys. Take priority over WASD-as-
	# arrows so A/S/D press the slot, not the focus arrow. Arrow keys
	# (KEY_LEFT/RIGHT/UP/DOWN) are still available for focus nav.
	if _QWERTY_SLOT_KEYS.has(k):
		var slot_idx: int = int(_QWERTY_SLOT_KEYS[k])
		# Update focus to that slot so the visual confirms the press.
		_focused_target = "grid"
		_focused_slot = slot_idx
		_apply_focus_visuals()
		_on_card_clicked(slot_idx)
		get_viewport().set_input_as_handled()
		return
	match k:
		KEY_LEFT:
			_move_focus(-1, 0)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_move_focus(1, 0)
			get_viewport().set_input_as_handled()
		KEY_UP:
			_move_focus(0, -1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_move_focus(0, 1)
			get_viewport().set_input_as_handled()
		KEY_TAB:
			# Cycle grid <-> done button.
			if _focused_target == "grid":
				_focused_target = "done"
			else:
				_focused_target = "grid"
				_focused_slot = _first_unrevealed_slot()
			_apply_focus_visuals()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			# Activate. Space is gated upstream by trigger_action's loot-reveal
			# check (v0.9.596 / v0.9.602) so the action bar doesn't fire too.
			if _focused_target == "done":
				_on_done_pressed()
			else:
				_on_card_clicked(_focused_slot)
			get_viewport().set_input_as_handled()


func _move_focus(dx: int, dy: int) -> void:
	"""Arrow-key movement. Moving outside the grid drops focus to the Done
	button (for Down off the bottom row). Up from the Done button returns to
	the bottom-most matching column of the grid."""
	# v0.9.664 — the grid is dynamic (up to COMBAT_LOOT_MAX_SLOTS), so read the
	# live column/card count instead of the fixed 16-slot / GRID_COLS constants.
	var grid_cols: int = _grid.columns if _grid != null else GRID_COLS
	var total: int = _cards.size()
	if _focused_target == "done":
		if dy < 0:
			# Up from Done → bottom row of grid.
			_focused_target = "grid"
			var rows0 := int(ceil(float(total) / float(grid_cols)))
			_focused_slot = clampi((rows0 - 1) * grid_cols, 0, total - 1)
			_apply_focus_visuals()
		# Left/Right/Down from Done: no-op (only one footer button currently).
		return
	# Grid movement.
	var col := _focused_slot % grid_cols
	var row := int(_focused_slot / grid_cols)
	var rows := int(ceil(float(total) / float(grid_cols)))
	var new_col := col + dx
	var new_row := row + dy
	# Vertical out-of-bounds — bottom row Down → Done button.
	if new_row >= rows:
		_focused_target = "done"
		_apply_focus_visuals()
		return
	# Clamp horizontals; wrap is overkill for the grid.
	new_col = clampi(new_col, 0, grid_cols - 1)
	new_row = clampi(new_row, 0, rows - 1)
	var new_index: int = new_row * grid_cols + new_col
	if new_index >= total:
		new_index = total - 1
	_focused_slot = new_index
	_apply_focus_visuals()


func _first_unrevealed_slot() -> int:
	for i in range(_slots_data.size()):
		if not bool(_slots_data[i].get("revealed", false)):
			return i
	return 0


func _apply_focus_visuals() -> void:
	"""Paint the focused element with a bright yellow border. v0.9.602 — fixed
	the focus-color trail bug: previously this only reset the border WIDTH on
	non-focused cards, so cards the player navigated THROUGH kept the yellow
	border permanently. Now we re-call `_render_card(i)` to restore the
	natural state (sealed purple / rarity-colored / dim missed) before
	overlaying focus on the currently-focused card."""
	for i in range(_cards.size()):
		var card = _cards[i]
		if not is_instance_valid(card):
			continue
		var is_focused_card: bool = (_focused_target == "grid" and i == _focused_slot)
		if is_focused_card:
			# Restore natural state first, then apply focus border on top.
			# _render_card replaces the stylebox so we grab the new one.
			_render_card(i)
			var fsb = card.get_theme_stylebox("panel")
			if fsb is StyleBoxFlat:
				(fsb as StyleBoxFlat).border_color = Color(1.0, 0.86, 0.20, 1)
				(fsb as StyleBoxFlat).set_border_width_all(3)
		else:
			# Restore the natural stylebox — kills any lingering yellow border
			# from when this card had focus a moment ago.
			_render_card(i)
	# Done button highlight.
	if _done_button != null:
		if _focused_target == "done":
			_done_button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.20, 1))
		else:
			_done_button.remove_theme_color_override("font_color")
