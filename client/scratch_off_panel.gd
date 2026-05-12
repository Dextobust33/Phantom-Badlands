extends Control
class_name ScratchOffPanel

# Audit #7 Slice 1E — themed scratch-off ticket with scattered slots + autoskip.
#
# v0.9.359 (1D): row-of-cards visual; this is the iteration.
# v0.9.360 (1E):
#   - 16 slots in jittered-grid positions on a fish-themed canvas (not a row).
#     Player clicks the silhouettes to scratch them.
#   - Smaller cards (~64x64) so the canvas reads as a real ticket.
#   - Auto-skip toggle button at the top-right of the panel. When ON, client
#     fires reveals automatically every ~250ms (timer lives in client.gd).
#     Toggle remains clickable mid-session so the player can halt and pick.
#
# Pattern mirrors stones_panel.gd / post_status_panel.gd: dim backdrop +
# centered PanelContainer, refreshable on every server reveal.

signal slot_clicked(slot_index: int)
signal slot_missed(slot_index: int)
signal auto_skip_toggled(value: bool)

const CARD_SIZE := Vector2(64, 64)
const CANVAS_SIZE := Vector2(640, 380)
const GRID_COLS := 4
const GRID_ROWS := 4
const RIPPLE_GLYPH := "~~~"
const FISH_SILHOUETTE := "<><"

# v0.9.363 — timing minigame. Vertical bar sweeps left-to-right; clicking
# a hidden card while the bar's rect overlaps the card is a HIT (reveal);
# clicking outside the overlap is a MISS (scratch burned, no reveal).
# v0.9.365 — wavy water-themed edges. The bar's left and right boundaries
# are sine-distorted. Hit detection still uses the underlying straight rect
# for forgiveness — the waves are decoration.
const BAR_BASE_SPEED := 220.0  # px/sec at bar_speed_mult=1.0
const BAR_BASE_WIDTH := 36.0   # px at bar_width_mult=1.0
const BAR_COLOR := Color(0.40, 0.85, 1.0, 0.32)
const BAR_EDGE_COLOR := Color(0.55, 0.95, 1.0, 0.85)
const WAVE_AMPLITUDE := 5.0    # px outward distortion per edge
const WAVE_WAVELENGTH := 38.0  # px per full sine cycle
const WAVE_SCROLL_SPEED := 45.0  # px/sec the wave phase scrolls upward
const WAVE_SEGMENTS := 28      # vertical resolution of the polyline
# v0.9.367 — hit-zone glow on hidden cards under the bar.
const HIT_GLOW_PAD := 3.0      # px outside card rect
const HIT_GLOW_COLOR := Color(0.65, 1.0, 1.0, 0.85)
const HIT_GLOW_WIDTH := 2.0

var _root_panel: PanelContainer
var _title_label: Label
var _subtitle_label: RichTextLabel
var _toggle_btn: Button
var _canvas: Control
var _scratches_label: RichTextLabel

var _slot_cards: Array = []  # parallel to slot index; Control or null
var _slot_positions: Array = []  # parallel; Vector2 each
var _slot_hidden: Array = []     # v0.9.367 — parallel bool; true if card is still hidden
var _prev_slots: Array = []      # v0.9.367 — previous frame slot states for transition detection
var _slot_count: int = 0
var _job_type: String = "fishing"
var _auto_skip: bool = false

# v0.9.363 — timing minigame state. Bar sweeps left→right; reset to 0
# when past CANVAS_SIZE.x. Hidden when auto_skip is on (no timing in skip
# mode). Update happens in canvas._process via the BarRunner inner node.
var _bar_x: float = 0.0
var _bar_speed: float = BAR_BASE_SPEED  # current; scaled by tool
var _bar_width: float = BAR_BASE_WIDTH  # current; scaled by tool
var _bar_runner: Control = null  # the actual drawn bar (child of _canvas)
var _scratches_remaining: int = 0  # mirrored from snapshot; gates bar motion
var _wave_phase: float = 0.0  # v0.9.365 — animated phase for wavy edges


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func open(snapshot: Dictionary) -> void:
	"""First call of a session — regenerate scattered positions, then refresh."""
	_slot_count = int(snapshot.get("slot_count", (snapshot.get("slots", []) as Array).size()))
	_generate_positions(_slot_count)
	refresh(snapshot)
	visible = true


func close() -> void:
	visible = false


func refresh(snapshot: Dictionary) -> void:
	"""Re-render with a fresh snapshot. Called on every server reveal +
	whenever auto-skip state changes locally.

	Snapshot keys:
	  - job_type, water_type / node_type, tool_name, pre_reveals
	  - scratches_remaining: int
	  - slot_count: int
	  - slots: Array — empty {} = hidden, otherwise item dict
	  - auto_skip: bool (visual state of the toggle)
	  - bar_speed_mult / bar_width_mult: float (tool-scaled timing knobs)
	"""
	_job_type = String(snapshot.get("job_type", "fishing"))
	_auto_skip = bool(snapshot.get("auto_skip", false))
	# v0.9.363 — tool-scaled bar timing. Lower bar_speed_mult = slower bar;
	# higher bar_width_mult = wider target zone. Both make hits easier.
	_bar_speed = BAR_BASE_SPEED * float(snapshot.get("bar_speed_mult", 1.0))
	_bar_width = BAR_BASE_WIDTH * float(snapshot.get("bar_width_mult", 1.0))
	_scratches_remaining = int(snapshot.get("scratches_remaining", 0))
	var slots: Array = snapshot.get("slots", [])
	_slot_count = int(snapshot.get("slot_count", slots.size()))
	# Positions are stable for the session — generate only if missing.
	if _slot_positions.size() != _slot_count:
		_generate_positions(_slot_count)
		_prev_slots = []  # new session — reset transition tracker
	_render_header(snapshot)
	_render_slots(slots)
	_animate_newly_revealed(slots)
	_render_footer(snapshot)
	_update_toggle_button()
	_update_bar_visibility()
	# Stash for next refresh's transition detection.
	_prev_slots = slots.duplicate(true)


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
	_root_panel.custom_minimum_size = Vector2(CANVAS_SIZE.x + 36, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.10, 0.18, 0.97)
	sb.border_color = Color(0.32, 0.72, 0.95, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_top = 14
	sb.content_margin_right = 18
	sb.content_margin_bottom = 14
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_root_panel.add_child(vbox)

	# Header row: title (expand) + autoskip toggle
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	vbox.add_child(header_row)

	_title_label = Label.new()
	_title_label.text = "FISHING — Scratch-Off Ticket"
	_title_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_title_label)

	_toggle_btn = Button.new()
	_toggle_btn.text = "Auto-Skip: OFF"
	_toggle_btn.focus_mode = Control.FOCUS_NONE
	_toggle_btn.custom_minimum_size = Vector2(220, 42)
	_toggle_btn.add_theme_font_size_override("font_size", 15)
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	header_row.add_child(_toggle_btn)

	_subtitle_label = RichTextLabel.new()
	_subtitle_label.bbcode_enabled = true
	_subtitle_label.fit_content = true
	_subtitle_label.scroll_active = false
	_subtitle_label.add_theme_font_size_override("normal_font_size", 12)
	_subtitle_label.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(_subtitle_label)

	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer_top)

	# Card canvas — Control with absolute-positioned children.
	# Wrap in a PanelContainer for the water-tile inner background.
	var canvas_wrap := PanelContainer.new()
	var canvas_sb := StyleBoxFlat.new()
	canvas_sb.bg_color = Color(0.02, 0.06, 0.12, 1.0)
	canvas_sb.border_color = Color(0.22, 0.45, 0.65, 1)
	canvas_sb.set_border_width_all(1)
	canvas_sb.set_corner_radius_all(4)
	canvas_sb.content_margin_left = 6
	canvas_sb.content_margin_top = 6
	canvas_sb.content_margin_right = 6
	canvas_sb.content_margin_bottom = 6
	canvas_wrap.add_theme_stylebox_override("panel", canvas_sb)
	vbox.add_child(canvas_wrap)

	_canvas = Control.new()
	_canvas.custom_minimum_size = CANVAS_SIZE
	_canvas.clip_contents = false
	canvas_wrap.add_child(_canvas)

	# v0.9.363 — bar overlay drawn ABOVE the slot cards via _draw. Added
	# after _canvas so its draw order is on top. Mouse-transparent so clicks
	# pass through to the cards beneath.
	_bar_runner = Control.new()
	_bar_runner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_runner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_runner.draw.connect(_draw_timing_bar)
	_canvas.add_child(_bar_runner)

	var spacer_bot := Control.new()
	spacer_bot.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer_bot)

	_scratches_label = RichTextLabel.new()
	_scratches_label.bbcode_enabled = true
	_scratches_label.fit_content = true
	_scratches_label.scroll_active = false
	_scratches_label.add_theme_font_size_override("normal_font_size", 13)
	_scratches_label.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(_scratches_label)


func _generate_positions(slot_count: int) -> void:
	"""Build jittered-grid positions inside the canvas. Each grid cell
	gets at most one card with a small random offset so the layout reads
	as scattered, never as a regular grid. Positions are stable for the
	session."""
	_slot_positions.clear()
	if slot_count <= 0:
		return
	# Pad inside the canvas so cards don't touch the inner border.
	var pad := 8.0
	var usable_w := CANVAS_SIZE.x - CARD_SIZE.x - pad * 2
	var usable_h := CANVAS_SIZE.y - CARD_SIZE.y - pad * 2
	var cell_w := usable_w / float(GRID_COLS - 1) if GRID_COLS > 1 else 0.0
	var cell_h := usable_h / float(GRID_ROWS - 1) if GRID_ROWS > 1 else 0.0
	# Build all grid centers, shuffle, take slot_count.
	var cells: Array = []
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var cx := pad + float(col) * cell_w
			var cy := pad + float(row) * cell_h
			cells.append(Vector2(cx, cy))
	cells.shuffle()
	# Jitter: small random offset (±20% of cell size) per cell so the layout
	# never reads as a strict grid even with all 16 slots placed.
	var jitter_x := cell_w * 0.20
	var jitter_y := cell_h * 0.20
	for i in range(slot_count):
		if i >= cells.size():
			break  # 16 slots fit a 4x4 grid exactly; defensive.
		var base: Vector2 = cells[i]
		var jx := randf_range(-jitter_x, jitter_x)
		var jy := randf_range(-jitter_y, jitter_y)
		_slot_positions.append(base + Vector2(jx, jy))


func _render_header(snapshot: Dictionary) -> void:
	match _job_type:
		"mining":
			_title_label.text = "MINING — Scratch-Off Ticket"
			_title_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
		"logging":
			_title_label.text = "LOGGING — Scratch-Off Ticket"
			_title_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.45))
		_:
			_title_label.text = "FISHING — Scratch-Off Ticket"
			_title_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))

	_subtitle_label.clear()
	var water_type = String(snapshot.get("water_type", ""))
	if water_type == "":
		water_type = String(snapshot.get("node_type", ""))
	var line1 = "Cast in %s water. Click a silhouette while the [color=#7AD8FF]wave[/color] is over it." % water_type if water_type != "" else "Click a silhouette while the [color=#7AD8FF]wave[/color] is over it."
	_subtitle_label.append_text("[color=#88BBDD]%s[/color]\n" % line1)
	var tool_name = String(snapshot.get("tool_name", ""))
	var pre_reveals = int(snapshot.get("pre_reveals", 0))
	if pre_reveals > 0 and tool_name != "":
		var plural = "s" if pre_reveals != 1 else ""
		_subtitle_label.append_text("[color=#C4A882]Your %s pre-revealed %d slot%s.[/color]" % [tool_name, pre_reveals, plural])


func _render_slots(slots: Array) -> void:
	# Only free slot cards — keep the bar runner alive across refreshes.
	for card in _slot_cards:
		if is_instance_valid(card):
			card.queue_free()
	_slot_cards.clear()
	_slot_hidden.clear()
	for i in range(slots.size()):
		var slot: Dictionary = slots[i] if slots[i] is Dictionary else {}
		var card := _build_slot_card(i, slot)
		if i < _slot_positions.size():
			card.position = _slot_positions[i]
		_canvas.add_child(card)
		_slot_cards.append(card)
		_slot_hidden.append(slot.is_empty())
	# Bar must draw ON TOP of the freshly-added cards.
	if _bar_runner and is_instance_valid(_bar_runner):
		_canvas.move_child(_bar_runner, _canvas.get_child_count() - 1)


func _animate_newly_revealed(slots: Array) -> void:
	"""v0.9.367 — scale-pop newly revealed cards. Compares the current slot
	state against _prev_slots (set at the end of refresh) to detect the
	hidden → revealed transition. One-shot tween, no kill needed.
	v0.9.368 — MISS transitions horizontal-shake instead of scale-pop, so
	good outcomes feel different from mistimed ones."""
	if _prev_slots.is_empty():
		return  # first frame of a session — nothing to compare against
	for i in range(slots.size()):
		if i >= _slot_cards.size() or i >= _prev_slots.size():
			continue
		var was_hidden: bool = (_prev_slots[i] as Dictionary).is_empty()
		var slot: Dictionary = slots[i] as Dictionary
		var now_revealed: bool = not slot.is_empty()
		if not (was_hidden and now_revealed):
			continue
		var card: Control = _slot_cards[i]
		if not is_instance_valid(card):
			continue
		var kind: String = String(slot.get("kind", "NORMAL"))
		if kind == "MISS":
			_play_miss_shake(card, i)
		else:
			card.pivot_offset = CARD_SIZE * 0.5
			card.scale = Vector2(1.35, 1.35)
			var t := create_tween()
			t.tween_property(card, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_miss_shake(card: Control, slot_index: int) -> void:
	"""Brief horizontal shake on MISS. Tween position offset around the
	card's resting spot. Resting spot is _slot_positions[i] so we tween
	back to that exact value to avoid drift on repeated refreshes."""
	if slot_index < 0 or slot_index >= _slot_positions.size():
		return
	var base_pos: Vector2 = _slot_positions[slot_index]
	var shake := create_tween()
	shake.tween_property(card, "position", base_pos + Vector2(-6, 0), 0.04)
	shake.tween_property(card, "position", base_pos + Vector2(5, 0), 0.05)
	shake.tween_property(card, "position", base_pos + Vector2(-3, 0), 0.05)
	shake.tween_property(card, "position", base_pos + Vector2(2, 0), 0.05)
	shake.tween_property(card, "position", base_pos, 0.04)


func _build_slot_card(slot_index: int, slot: Dictionary) -> PanelContainer:
	var is_hidden: bool = slot.is_empty()
	var kind: String = String(slot.get("kind", "NORMAL"))

	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_top = 4
	sb.content_margin_right = 4
	sb.content_margin_bottom = 4

	if is_hidden:
		sb.bg_color = Color(0.08, 0.22, 0.38, 1.0)
		sb.border_color = Color(0.45, 0.75, 0.95, 1.0)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_clicked.bind(slot_index))
	else:
		var palette := _palette_for_slot(slot)
		sb.bg_color = palette.bg
		sb.border_color = palette.border

	card.add_theme_stylebox_override("panel", sb)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 0)
	card.add_child(inner)

	if is_hidden:
		var ripple_top := Label.new()
		ripple_top.text = RIPPLE_GLYPH
		ripple_top.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0, 0.85))
		ripple_top.add_theme_font_size_override("font_size", 10)
		ripple_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(ripple_top)

		var silhouette := Label.new()
		silhouette.text = FISH_SILHOUETTE
		silhouette.add_theme_color_override("font_color", Color(0.32, 0.55, 0.78, 0.85))
		silhouette.add_theme_font_size_override("font_size", 18)
		silhouette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(silhouette)

		var ripple_bot := Label.new()
		ripple_bot.text = RIPPLE_GLYPH
		ripple_bot.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0, 0.85))
		ripple_bot.add_theme_font_size_override("font_size", 10)
		ripple_bot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(ripple_bot)
	else:
		var palette := _palette_for_slot(slot)
		var kind_label := Label.new()
		kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kind_label.add_theme_font_size_override("font_size", 10)
		kind_label.add_theme_color_override("font_color", palette.kind_color)
		match kind:
			"MISS":
				kind_label.text = "✗ MISS"
			"DUD":
				kind_label.text = "✗ EMPTY"
			"LUCKY":
				kind_label.text = "★ LUCKY"
			"JACKPOT":
				kind_label.text = "★★★"
			_:
				kind_label.text = "◆"
		inner.add_child(kind_label)

		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color", palette.name_color)
		name_label.custom_minimum_size = Vector2(CARD_SIZE.x - 8, 0)
		var display_name = String(slot.get("name", "?"))
		if kind == "LUCKY":
			var qty = int(slot.get("quantity", 2))
			display_name = "%dx %s" % [qty, display_name]
		elif kind == "DUD":
			display_name = ""
		elif kind == "MISS":
			# v0.9.368 — show what slipped away. Server includes the slot's
			# would-be catch in the miss response; client stores lost_name.
			var lost = String(slot.get("lost_name", ""))
			if lost == "" or lost == "Empty":
				display_name = ""
			else:
				display_name = "Lost:\n" + lost
		name_label.text = display_name
		inner.add_child(name_label)

	return card


func _palette_for_slot(slot: Dictionary) -> Dictionary:
	var kind = String(slot.get("kind", "NORMAL"))
	match kind:
		"MISS":
			return {
				"bg": Color(0.22, 0.06, 0.06, 1.0),
				"border": Color(0.65, 0.20, 0.20, 1.0),
				"kind_color": Color(1.0, 0.45, 0.45),
				"name_color": Color(0.80, 0.55, 0.55),
			}
		"DUD":
			return {
				"bg": Color(0.14, 0.14, 0.14, 1.0),
				"border": Color(0.35, 0.35, 0.35, 1.0),
				"kind_color": Color(0.55, 0.55, 0.55),
				"name_color": Color(0.45, 0.45, 0.45),
			}
		"LUCKY":
			return {
				"bg": Color(0.07, 0.20, 0.07, 1.0),
				"border": Color(0.30, 0.85, 0.30, 1.0),
				"kind_color": Color(0.50, 1.0, 0.30),
				"name_color": Color(0.85, 1.0, 0.85),
			}
		"JACKPOT":
			return {
				"bg": Color(0.22, 0.16, 0.04, 1.0),
				"border": Color(1.0, 0.84, 0.20, 1.0),
				"kind_color": Color(1.0, 0.84, 0.20),
				"name_color": Color(1.0, 0.94, 0.55),
			}
		_:
			var t = String(slot.get("type", "fish"))
			match t:
				"material":
					return {
						"bg": Color(0.04, 0.16, 0.22, 1.0),
						"border": Color(0.0, 0.75, 1.0, 1.0),
						"kind_color": Color(0.40, 0.85, 1.0),
						"name_color": Color(0.75, 0.95, 1.0),
					}
				"treasure":
					return {
						"bg": Color(0.16, 0.08, 0.22, 1.0),
						"border": Color(0.64, 0.21, 0.93, 1.0),
						"kind_color": Color(0.85, 0.45, 1.0),
						"name_color": Color(0.90, 0.75, 1.0),
					}
				"treasure_chest":
					return {
						"bg": Color(0.22, 0.16, 0.04, 1.0),
						"border": Color(1.0, 0.84, 0.20, 1.0),
						"kind_color": Color(1.0, 0.84, 0.20),
						"name_color": Color(1.0, 0.92, 0.55),
					}
				"egg":
					return {
						"bg": Color(0.20, 0.08, 0.14, 1.0),
						"border": Color(1.0, 0.41, 0.71, 1.0),
						"kind_color": Color(1.0, 0.55, 0.80),
						"name_color": Color(1.0, 0.80, 0.92),
					}
				_:
					return {
						"bg": Color(0.05, 0.20, 0.10, 1.0),
						"border": Color(0.12, 0.85, 0.20, 1.0),
						"kind_color": Color(0.40, 1.0, 0.40),
						"name_color": Color(0.85, 1.0, 0.85),
					}


func _render_footer(snapshot: Dictionary) -> void:
	_scratches_label.clear()
	var remaining = int(snapshot.get("scratches_remaining", 0))
	if remaining > 0:
		if _auto_skip:
			_scratches_label.append_text("[center][color=#FFD700]Scratches remaining: %d[/color]  [color=#88BBDD]— auto-skipping (≈60%% yield) — click toggle to halt[/color][/center]" % remaining)
		else:
			_scratches_label.append_text("[center][color=#FFD700]Scratches remaining: %d[/color]  [color=#88BBDD]— click a silhouette while the wave is over it[/color][/center]" % remaining)
	else:
		_scratches_label.append_text("[center][color=#00FF88]Cashing in...[/color][/center]")


func _update_toggle_button() -> void:
	# Distinct styles so the toggle reads as a clear affordance:
	# ON  → orange "STOP AUTO-SKIP" button (action-oriented; player is in
	#       auto mode and the only clickable affordance halts it)
	# OFF → green "AUTO-SKIP" button (idle, start auto on click)
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_top = 6
	sb.content_margin_right = 10
	sb.content_margin_bottom = 6
	if _auto_skip:
		_toggle_btn.text = "⏸  STOP AUTO-SKIP"
		_toggle_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
		sb.bg_color = Color(0.65, 0.30, 0.05, 1.0)
		sb.border_color = Color(1.0, 0.70, 0.20, 1.0)
	else:
		_toggle_btn.text = "▶  Auto-Skip"
		_toggle_btn.add_theme_color_override("font_color", Color(0.95, 1.0, 0.90))
		sb.bg_color = Color(0.10, 0.30, 0.10, 1.0)
		sb.border_color = Color(0.30, 0.85, 0.30, 1.0)
	# Apply to all the button styles so hover/pressed states match.
	_toggle_btn.add_theme_stylebox_override("normal", sb)
	_toggle_btn.add_theme_stylebox_override("hover", sb)
	_toggle_btn.add_theme_stylebox_override("pressed", sb)


func _on_toggle_pressed() -> void:
	_auto_skip = not _auto_skip
	_update_toggle_button()
	# Update footer hint immediately to reflect new mode (client.gd will also
	# refresh us on the next reveal — this just makes the toggle feel snappy).
	_scratches_label.clear()
	auto_skip_toggled.emit(_auto_skip)


func _on_card_clicked(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# v0.9.363 — during auto-skip clicks are ignored entirely; the
			# auto-loop in client.gd handles reveals + the toggle is the
			# only interactive element. To pick manually the player must
			# halt auto-skip via the toggle first.
			if _auto_skip:
				return
			if _is_bar_over_slot(slot_index):
				slot_clicked.emit(slot_index)
			else:
				slot_missed.emit(slot_index)


func _is_bar_over_slot(slot_index: int) -> bool:
	"""Returns true if the bar's vertical column intersects this slot's
	card rect (horizontal overlap only — bar runs the full canvas height)."""
	if slot_index < 0 or slot_index >= _slot_positions.size():
		return false
	var card_x: float = _slot_positions[slot_index].x
	return _bar_overlaps_x(card_x, card_x + CARD_SIZE.x)


func _process(delta: float) -> void:
	# Advance the bar only while panel is open + auto-skip is off + session
	# still active. When scratches hit 0 the panel enters its post-complete
	# hold; freezing the bar makes "Cashing in..." read clearly.
	if not visible or _auto_skip or _scratches_remaining <= 0:
		return
	_bar_x += _bar_speed * delta
	if _bar_x > CANVAS_SIZE.x:
		_bar_x = -_bar_width  # restart fully off-screen left
	_wave_phase += WAVE_SCROLL_SPEED * delta
	if _bar_runner and is_instance_valid(_bar_runner):
		_bar_runner.queue_redraw()


func _draw_timing_bar() -> void:
	if _auto_skip:
		return
	# v0.9.365 — water-wave bar. Left + right edges are sine-distorted along
	# the vertical axis and the phase scrolls upward over time. Hit detection
	# (in _is_bar_over_slot) still uses the underlying straight rect — the
	# waves are decoration and we don't want the player blamed for the wave
	# trough being a few pixels short of a card.
	var left_pts := PackedVector2Array()
	var right_pts := PackedVector2Array()
	var height := CANVAS_SIZE.y
	for i in range(WAVE_SEGMENTS + 1):
		var t = float(i) / WAVE_SEGMENTS
		var y = t * height
		# Left + right edges use opposite phase so the bar appears to ripple
		# rather than bend uniformly — gives it more "water" feel.
		var off_l = sin((y + _wave_phase) / WAVE_WAVELENGTH * TAU) * WAVE_AMPLITUDE
		var off_r = sin((y + _wave_phase + WAVE_WAVELENGTH * 0.5) / WAVE_WAVELENGTH * TAU) * WAVE_AMPLITUDE
		left_pts.append(Vector2(_bar_x + off_l, y))
		right_pts.append(Vector2(_bar_x + _bar_width + off_r, y))
	# Fill: traverse left edge top→bottom, then right edge bottom→top.
	var polygon := PackedVector2Array()
	polygon.append_array(left_pts)
	for i in range(right_pts.size() - 1, -1, -1):
		polygon.append(right_pts[i])
	_bar_runner.draw_colored_polygon(polygon, BAR_COLOR)
	# Edge lines for legibility — players need to see where the bar is even
	# when its alpha-blended fill is hard to read against bright cards.
	_bar_runner.draw_polyline(left_pts, BAR_EDGE_COLOR, 1.5)
	_bar_runner.draw_polyline(right_pts, BAR_EDGE_COLOR, 1.5)
	# v0.9.367 — hit-zone glow on hidden cards the bar currently overlaps.
	# Player can see exactly which slots are "live" right now.
	for i in range(_slot_hidden.size()):
		if not _slot_hidden[i]:
			continue
		if i >= _slot_positions.size():
			continue
		var pos: Vector2 = _slot_positions[i]
		if not _bar_overlaps_x(pos.x, pos.x + CARD_SIZE.x):
			continue
		var glow_rect := Rect2(pos - Vector2(HIT_GLOW_PAD, HIT_GLOW_PAD), CARD_SIZE + Vector2(HIT_GLOW_PAD * 2, HIT_GLOW_PAD * 2))
		_bar_runner.draw_rect(glow_rect, HIT_GLOW_COLOR, false, HIT_GLOW_WIDTH)


func _bar_overlaps_x(x_left: float, x_right: float) -> bool:
	return (_bar_x + _bar_width) >= x_left and _bar_x <= x_right


func _update_bar_visibility() -> void:
	"""Hide the bar when auto-skip is on; reset its position when toggled
	back to manual so the player doesn't get a surprise mid-canvas click
	check."""
	if not _bar_runner or not is_instance_valid(_bar_runner):
		return
	if _auto_skip:
		_bar_runner.visible = false
	else:
		_bar_runner.visible = true
		_bar_x = 0.0  # restart from left when entering manual
		_bar_runner.queue_redraw()
