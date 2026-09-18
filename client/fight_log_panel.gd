extends Control
## The last fight's blow-by-blow, as an OVERLAY rather than text in the shared output window.
##
## ⛑ WHY THIS IS A PANEL AND NOT `display_game()` CALLS. The [L] view used to paint itself into
## `game_output` - the same RichTextLabel the map, the location text, merchant screens and combat
## all paint into. Three separate faults followed from that one decision, and all three were
## reported as separate bugs:
##
##   * it FLASHED and vanished, because whatever repainted `game_output` next won;
##   * CLOSING it left the text on screen, since closing only cleared a flag - so the footer said
##     "[L] to close" while the only thing that visibly worked was Space (which on the overworld
##     also made the player rest);
##   * it could only be kept up at all by HIDING the combat scene panel, which is why it was gated
##     on the victory card still being on screen and died the moment the player took a step.
##
## Owner 2026-09-18: *"It says press L to close at the bottom but I have to press space to close,
## which also forces me to rest or meditate... you can't see the log, it just flashes and goes to
## the map again."*
##
## An overlay has none of those failure modes: nothing else draws here, closing it reveals whatever
## was underneath with no repaint needed, and it does not care what is on screen behind it.

signal closed
signal step_fight(delta: int)
signal meta_clicked(meta)

var _body: RichTextLabel = null
var _title: Label = null
var _scroll: ScrollContainer = null
var _prev_btn: Button = null
var _next_btn: Button = null


func _ready() -> void:
	top_level = true
	# ⛑ ABOVE THE VICTORY CARD. That card is drawn at z_index 150 INSIDE the combat scene
	# panel, and this overlay is a sibling of that panel - so without a higher z the log
	# opened UNDERNEATH it and looked like nothing had happened. Owner 2026-09-18: *"If
	# pressed while the victory card is up it goes behind the victory card."*
	z_index = 4000
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	# ⛑ `top_level` DETACHES this Control from its parent's rect, so PRESET_FULL_RECT has nothing
	# to resolve against and sizes the panel to zero - it lands at the origin with its dim
	# covering nothing. Size from the viewport instead. (Same trap as the menu tree and the
	# social panel; recorded in CLAUDE.md because it has now cost three panels.)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


func _fit_to_viewport() -> void:
	var r := get_viewport().get_visible_rect()
	position = Vector2.ZERO
	size = r.size


func blocks_hotkeys() -> bool:
	"""Opts this panel into `client._blocking_overlay_open()`. The action bar polls PHYSICAL keys
	rather than focus, so without this a number key would page this panel AND fire an action slot
	behind it."""
	return visible


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.anchor_left = 0.10
	frame.anchor_right = 0.90
	frame.anchor_top = 0.06
	frame.anchor_bottom = 0.94
	frame.offset_left = 0.0
	frame.offset_right = 0.0
	frame.offset_top = 0.0
	frame.offset_bottom = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.98)
	sb.border_color = Color(0.36, 0.30, 0.20)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	frame.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)

	_title = Label.new()
	_title.text = "Fight Log"
	_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.40))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)

	_prev_btn = Button.new()
	_prev_btn.text = "\u25c0 Prev Fight"
	_prev_btn.focus_mode = Control.FOCUS_ALL
	_prev_btn.pressed.connect(func() -> void: step_fight.emit(-1))
	head.add_child(_prev_btn)

	_next_btn = Button.new()
	_next_btn.text = "Next Fight \u25b6"
	_next_btn.focus_mode = Control.FOCUS_ALL
	_next_btn.pressed.connect(func() -> void: step_fight.emit(1))
	head.add_child(_next_btn)

	var close_btn := Button.new()
	close_btn.text = "Close  [L]"
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	# ⛑ MONOSPACE, BECAUSE THE LOG CARRIES ASCII ART. The monster header is drawn with
	# spaces and box characters, and in a proportional face every row is a different width -
	# the art shears. Owner 2026-09-18: *"The monsters ASCII art on the log is skewed."* The
	# combat panel loads the same file for the same reason.
	var mono: FontFile = load("res://font/Consolas/consolas.ttf") as FontFile
	if mono != null:
		_body.add_theme_font_override("normal_font", mono)
		_body.add_theme_font_override("bold_font", mono)
	_body.add_theme_font_size_override("normal_font_size", 14)
	_body.fit_content = true
	_body.scroll_active = false
	_body.selection_enabled = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.meta_clicked.connect(func(m) -> void: meta_clicked.emit(m))
	_scroll.add_child(_body)


func show_log(title: String, bbcode: String, can_prev: bool, can_next: bool) -> void:
	"""Put one fight on screen. `can_prev` / `can_next` drive the flock-chain arrows."""
	visible = true
	_fit_to_viewport()
	_title.text = title
	_body.text = bbcode
	_prev_btn.visible = can_prev or can_next
	_next_btn.visible = can_prev or can_next
	_prev_btn.disabled = not can_prev
	_next_btn.disabled = not can_next
	# The newest lines are what the player pressed [L] for, so start at the bottom.
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L or event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
