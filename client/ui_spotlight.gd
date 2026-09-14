extends Control
class_name UiSpotlight

## Draws a pulsing border around UI elements the game has just NAMED in a sentence.
##
## Owner 2026-09-14, after being told where the Inventory lives: *"There is nothing to draw the
## players attention to any of the buttons or things he is referencing. We should be drawing a
## border around them or having them flash so the player can see them."*
##
## It is one overlay node sitting above everything, drawing rings around other people's rectangles.
## It never reparents or restyles the target, so it cannot disturb a layout, cannot leave a button
## permanently gold if it is freed mid-pulse, and works for any Control - action bar slot, shortcut
## button, panel, map - without that Control knowing it exists.

const RING_COLOR := Color(1.0, 0.84, 0.25, 1.0)   # the same gold the theme uses for "look here"
const PAD := 3.0
const PULSE_HZ := 1.6

var _targets: Array[Control] = []
var _until_ms: int = 0
var _t: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eats a click meant for the button below
	z_index = 4096
	visible = false
	set_process(false)


func spotlight(targets: Array, seconds: float = 8.0) -> void:
	_targets.clear()
	for t in targets:
		if t is Control and is_instance_valid(t):
			_targets.append(t)
	if _targets.is_empty():
		stop()
		return
	_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
	_t = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func stop() -> void:
	_targets.clear()
	visible = false
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if Time.get_ticks_msec() >= _until_ms:
		stop()
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	if _targets.is_empty():
		return
	# 0..1 and back, so it breathes rather than blinking on and off - a hard blink at this size
	# reads as a rendering fault.
	var pulse: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * TAU * PULSE_HZ))
	var col := RING_COLOR
	col.a = pulse
	var origin := get_global_rect().position
	for t in _targets:
		if not is_instance_valid(t) or not t.is_visible_in_tree():
			continue
		var r: Rect2 = t.get_global_rect()
		r.position -= origin
		r = r.grow(PAD)
		draw_rect(r, col, false, 2.0)
		# a faint wash inside, so the eye lands on the BUTTON and not on a floating rectangle
		var fill := RING_COLOR
		fill.a = pulse * 0.16
		draw_rect(r, fill, true)
