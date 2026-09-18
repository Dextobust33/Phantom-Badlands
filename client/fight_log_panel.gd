extends Control

const PanelCloseKeysScript := preload("res://client/panel_close_keys.gd")
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
## ⛑ HOVER, NOT ONLY CLICK. Every summary line wraps itself in a `[url]` whose payload is
## a KEY into the blow-by-blow, and the in-combat band has been wired to both halves since
## the summary shipped. This panel was given `meta_clicked` alone, so the detail a line
## exists to reveal could not be reached from the log the player opens to READ it.
## Owner 2026-09-18: *"The log is working now except for the hover to see the details."*
signal meta_hovered(meta)
signal meta_hover_ended

var _body: RichTextLabel = null
var _title: Label = null
var _scroll: ScrollContainer = null
var _prev_btn: Button = null
var _next_btn: Button = null

## ⚑ REPLAY. A stored fight played back at the pace it happened, rather than dropped on screen
## as 190 lines at once.
##
## ⛑ WHAT A REPLAY CAN HONESTLY BE HERE IS SET BY WHAT WAS STORED. A death record keeps its
## `combat_log` as plain BBCode STRINGS - no actor tag, no damage number, no HP per line. So a
## re-animation with moving bars and acting sprites would mean reading numbers back out of the
## prose, and this codebase has been bitten by exactly that twice (the co-op damage numbers
## landed on the wrong combatant because a text parser took "hits Warden Hollis for 43" for
## damage to the monster). Pacing needs none of it: the line ORDER is the fight.
var _replay_lines: Array = []
var _replay_i: int = 0
var _replay_speed: float = 1.0
var _replay_playing: bool = false
var _replay_accum: float = 0.0
var _play_btn: Button = null
var _skip_btn: Button = null
var _progress: ProgressBar = null

## Seconds a line holds the screen at speed 1.0. Measured against the real thing: a 27-round
## death ran 190 lines, so 0.28s is about 53 seconds to watch a fight that took minutes to
## fight. Fast enough to sit through, slow enough to read.
const REPLAY_LINE_SEC := 0.28


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

	_play_btn = Button.new()
	_play_btn.text = "⏸ Pause"
	_play_btn.focus_mode = Control.FOCUS_ALL
	_play_btn.pressed.connect(_toggle_replay)
	_play_btn.visible = false
	head.add_child(_play_btn)

	_skip_btn = Button.new()
	_skip_btn.text = "⏭ To End"
	_skip_btn.focus_mode = Control.FOCUS_ALL
	_skip_btn.pressed.connect(_skip_replay)
	_skip_btn.visible = false
	head.add_child(_skip_btn)

	var close_btn := Button.new()
	close_btn.text = PanelCloseKeysScript.CLOSE_HINT + "  [L]"
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
	# PASS, never IGNORE: IGNORE means the label receives no mouse events at all and the
	# hover listeners above become unreachable while the links still RENDER - an underlined
	# link that advertises an explanation it cannot give. That shipped once already on
	# `_monster_name_label`.
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.meta_clicked.connect(func(m) -> void: meta_clicked.emit(m))

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.visible = false
	col.add_child(_progress)
	# BOTH halves, together - a hover opened with nothing to close it leaves a box stuck on
	# screen, which is the exact fault `_wire_hover` exists in the combat panel to prevent.
	_body.meta_hover_started.connect(func(m) -> void: meta_hovered.emit(m))
	_body.meta_hover_ended.connect(func(_m) -> void: meta_hover_ended.emit())
	_scroll.add_child(_body)


func show_log(title: String, bbcode: String, can_prev: bool, can_next: bool) -> void:
	"""Put one fight on screen. `can_prev` / `can_next` drive the flock-chain arrows."""
	visible = true
	_fit_to_viewport()
	_title.text = title
	# Leaving replay mode: the panel is shared, and a stale ticking replay would keep
	# appending lines underneath a log the player asked to read.
	_replay_playing = false
	_replay_lines = []
	_play_btn.visible = false
	_skip_btn.visible = false
	_progress.visible = false
	_body.text = bbcode
	_prev_btn.visible = can_prev or can_next
	_next_btn.visible = can_prev or can_next
	_prev_btn.disabled = not can_prev
	_next_btn.disabled = not can_next
	# The newest lines are what the player pressed [L] for, so start at the bottom.
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func play_replay(title: String, lines: Array, speed: float = 1.0) -> void:
	"""Play a stored fight back at the pace it happened.

	⛑ THE ORDER IS THE FIGHT. A stored `combat_log` is plain BBCode strings with no actor, no
	damage number and no HP per line, so there is nothing here to re-animate FROM - a moving
	health bar would have to be reconstructed by reading numbers back out of the prose, which is
	the mistake that put co-op damage numbers on the wrong combatant. Pacing needs none of that.

	Speed comes from the viewer's own combat-speed setting, so a replay runs at the rate they
	have already chosen to watch fights at rather than a second preference to discover."""
	visible = true
	_fit_to_viewport()
	_title.text = title
	_replay_lines = lines.duplicate()
	_replay_i = 0
	_replay_speed = maxf(0.1, speed)
	_replay_accum = 0.0
	_replay_playing = _replay_lines.size() > 0
	_body.text = ""
	_prev_btn.visible = false
	_next_btn.visible = false
	_play_btn.visible = true
	_skip_btn.visible = true
	_play_btn.text = "⏸ Pause"
	_progress.visible = true
	_progress.max_value = maxf(1.0, float(_replay_lines.size()))
	_progress.value = 0
	set_process(true)
	if _replay_lines.is_empty():
		_body.text = "[color=#888888]No blow-by-blow was recorded for this fight.[/color]"
		_play_btn.visible = false
		_skip_btn.visible = false
		_progress.visible = false


func _process(delta: float) -> void:
	if not visible or not _replay_playing:
		return
	_replay_accum += delta * _replay_speed
	# A while-loop, not an if: at high speed more than one line is due in a single frame, and
	# dropping the extras would silently make a fast replay SHORTER rather than faster.
	while _replay_accum >= REPLAY_LINE_SEC and _replay_i < _replay_lines.size():
		_replay_accum -= REPLAY_LINE_SEC
		_append_replay_line()
	if _replay_i >= _replay_lines.size():
		_finish_replay()


func _append_replay_line() -> void:
	var line := String(_replay_lines[_replay_i])
	_replay_i += 1
	_progress.value = _replay_i
	if line.strip_edges() == "":
		return
	_body.text = line if _body.text == "" else _body.text + "
" + line
	# Follow the newest line, the way a live fight does.
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _toggle_replay() -> void:
	if _replay_i >= _replay_lines.size():
		# Finished: the button restarts it rather than doing nothing, which is what a player
		# pressing Play on a finished replay means.
		_body.text = ""
		_replay_i = 0
		_replay_accum = 0.0
	_replay_playing = not _replay_playing
	_play_btn.text = "⏸ Pause" if _replay_playing else "▶ Play"


func _skip_replay() -> void:
	"""Show the whole fight at once. The reason to watch a replay is usually one specific moment,
	and making someone sit through 190 lines to reach it would be worse than the wall of text this
	replaced."""
	_replay_playing = false
	var parts: Array = []
	for l in _replay_lines:
		if String(l).strip_edges() != "":
			parts.append(String(l))
	_body.text = "
".join(parts)
	_replay_i = _replay_lines.size()
	_finish_replay()


func _finish_replay() -> void:
	_replay_playing = false
	_progress.value = _progress.max_value
	_play_btn.text = "↺ Replay"

func close() -> void:
	if not visible:
		return
	visible = false
	_replay_playing = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if PanelCloseKeysScript.wants_close(event) or (
			event is InputEventKey and event.pressed and not event.echo
			and (event as InputEventKey).keycode == KEY_L):
		close()
		get_viewport().set_input_as_handled()
