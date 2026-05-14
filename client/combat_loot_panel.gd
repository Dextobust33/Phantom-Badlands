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

const SLOT_COUNT := 16
const GRID_COLS := 4

var _root_panel: PanelContainer
var _header_label: RichTextLabel
var _reveals_label: RichTextLabel
var _grid: GridContainer
var _done_button: Button

var _cards: Array = []  # Array[PanelContainer], indexed by slot
var _card_labels: Array = []  # Array[RichTextLabel] mirror of _cards

var _slots_data: Array = []  # Mirror of server-pushed slot view
var _reveals_used: int = 0
var _reveal_budget: int = 0
var _flock_kills: int = 1
var _monster_tier: int = 1
var _cascade_active: bool = false


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

	# Title
	var title := Label.new()
	title.text = "Loot Reveal"
	title.add_theme_color_override("font_color", Color(1, 0.84, 0))
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Header — tier + flock info
	_header_label = RichTextLabel.new()
	_header_label.bbcode_enabled = true
	_header_label.fit_content = true
	_header_label.scroll_active = false
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_label.add_theme_font_size_override("normal_font_size", 13)
	_header_label.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(_header_label)

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

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(footer_spacer)

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
	_render_header()
	_render_reveals_counter()
	_render_all_cards()
	visible = true


func reveal_slot(slot_index: int, reveal_data: Dictionary, reveals_used: int, reveal_budget: int) -> void:
	"""Server confirmed a reveal — flip the card to show the awarded outcome."""
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


func finish(final_bag: Dictionary) -> void:
	"""Server says done — cascade-flip the remaining cards (which are NOT
	awarded; they're shown so the player sees what they missed). After a brief
	pause, hide and emit closed."""
	_cascade_active = true
	_done_button.disabled = true
	var final_slots: Array = final_bag.get("slots", [])
	# Reveal any still-sealed cards with the server's final state. Cascade
	# them so the player sees the flip rather than an instant pop.
	var unrevealed: Array = []
	for i in range(min(final_slots.size(), _cards.size())):
		if not bool(_slots_data[i].get("revealed", false)):
			_slots_data[i] = final_slots[i].duplicate(true)
			_slots_data[i]["revealed"] = true
			_slots_data[i]["missed"] = true  # client marker so it renders dim
			unrevealed.append(i)
	for offset_i in range(unrevealed.size()):
		var idx_local: int = unrevealed[offset_i]
		var captured_local := idx_local
		var delay := 0.06 * float(offset_i)
		_call_deferred_after(delay, func():
			if not is_inside_tree():
				return
			_render_card(captured_local)
			_play_reveal_pop(captured_local))
	# After the cascade completes, hide the panel and emit `closed` so the
	# client wiring can advance the post-victory flow.
	var total_delay: float = 0.06 * float(unrevealed.size()) + 0.6
	_call_deferred_after(total_delay, func():
		if is_inside_tree():
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
		# Sealed card
		sb.bg_color = Color(0.10, 0.08, 0.14, 1.0)
		sb.border_color = Color(0.55, 0.45, 0.85, 1)
		card.add_theme_stylebox_override("panel", sb)
		lbl.text = "[center][color=#888888][font_size=20]?[/font_size][/color][/center]"
		return
	# Revealed — colored by kind. Missed (cascade) renders dim.
	var color_hex: String = String(slot.get("color", "#FFFFFF"))
	var name: String = String(slot.get("name", ""))
	var kind: String = String(slot.get("kind", "item"))
	var dim_fac: float = 0.55 if bool(slot.get("missed", false)) else 1.0
	var rgb := Color.html(color_hex) if color_hex != "" else Color.WHITE
	sb.bg_color = Color(rgb.r * 0.25 * dim_fac, rgb.g * 0.25 * dim_fac, rgb.b * 0.25 * dim_fac, 1.0)
	sb.border_color = Color(rgb.r, rgb.g, rgb.b, 0.6 if bool(slot.get("missed", false)) else 1.0)
	card.add_theme_stylebox_override("panel", sb)
	var miss_prefix: String = "[color=#888888][i](missed)[/i][/color] " if bool(slot.get("missed", false)) else ""
	# Equipment reveals get the rarity symbol too.
	var symbol: String = String(slot.get("symbol", ""))
	var sym_prefix: String = ("[color=%s]%s[/color] " % [color_hex, symbol]) if symbol != "" else ""
	# Wrap in center + small font for compact reveal cards.
	var label_text: String = "[center]%s[color=%s]%s%s[/color][/center]" % [miss_prefix, color_hex, sym_prefix, name]
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


# === Internal callbacks ===

func _on_card_clicked(slot_index: int) -> void:
	if _cascade_active:
		return
	if slot_index < 0 or slot_index >= _slots_data.size():
		return
	if bool(_slots_data[slot_index].get("revealed", false)):
		return
	if _reveals_used >= _reveal_budget:
		return
	emit_signal("slot_clicked", slot_index)


func _on_done_pressed() -> void:
	if _cascade_active:
		return
	_cascade_active = true
	_done_button.disabled = true
	emit_signal("done_pressed")
