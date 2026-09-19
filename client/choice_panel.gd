extends Control
class_name ChoicePanel

const PanelCloseKeysScript := preload("res://client/panel_close_keys.gd")

## ⚑ THE GAME IS WAITING FOR YOU TO PICK ONE OF THESE, SO IT CANNOT BE TEXT.
##
## Owner 2026-09-18, on the third separate instance in one evening: *"Scroll of finding still
## flashes on the left side of the screen behind the map then the map takes it back over and the
## player can't see to select anything. Why are we not fixing these properly? When we find the
## proper solution to this we need to fix it so it can never happen again."*
##
## ⛑ EVERY PER-SITE FIX FAILED, AND THE CODE ALREADY SAID IT WOULD. `_ow_text_in_column()` carries
## the note: *"There are 230 such clears in this file, so guarding them one at a time was never
## going to hold."* It routes text three ways and the choice depends on live state - whether the map
## owns the canvas, whether a panel is open, whether a page has claimed it. Using a Scroll of
## Finding from the INVENTORY trips the panel clause: the inventory panel is still visible for that
## frame, so the prompt goes to the canvas instead of the column, and the map repaints over it. Add
## `_page_clear()` and it still goes to the canvas, because the clear decides WHEN a page starts,
## not WHERE it lives.
##
## ⛑ SO THE FIX IS TO STOP PUTTING IT IN A SHARED BUFFER. A Control drawn above the map has no
## routing decision to get wrong, nothing that can repaint it, and no ownership question. There is
## no state in which this panel is invisible while the game waits on it. That is what makes this
## the LAST fix of this shape rather than the fourth.
##
## `tools/probe/a_choice_is_never_text.gd` fails if a selection mode reaches the player as text.

signal chosen(index: int)
signal cancelled

var _root_panel: PanelContainer
var _title: RichTextLabel
var _subtitle: RichTextLabel
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _buttons: Array = []

## Fraction of the screen the list may fill before it scrolls. Same reasoning as the tutorial hint
## panel: a container that grows to its content inside a box that does not is how a button ends up
## off the bottom of the screen, which this project shipped twice in one day.
const MAX_SCREEN_FRACTION := 0.60

## Test hook - a headless viewport reports the project default, not the window a player is on.
var assumed_screen_height: float = 0.0


func _ready() -> void:
	# ⛑ top_level, so this is never clipped by whatever container it was added to - and therefore
	# it has NO PARENT RECT, so PRESET_FULL_RECT resolves to zero and it must size itself. That
	# trap is in this project's notes from a modal whose dim covered nothing.
	top_level = true
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.12, 0.99)
	sb.border_color = Color("#C8A24A")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 8
	_root_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_root_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_root_panel.add_child(col)

	_title = RichTextLabel.new()
	_title.bbcode_enabled = true
	_title.fit_content = true
	_title.scroll_active = false
	_title.add_theme_font_size_override("normal_font_size", 19)
	col.add_child(_title)

	_subtitle = RichTextLabel.new()
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(476, 0)
	_subtitle.add_theme_font_size_override("normal_font_size", 14)
	col.add_child(_subtitle)

	# The rows scroll; the Cancel button below them does not. See MAX_SCREEN_FRACTION.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(476, 60)
	col.add_child(_scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	_scroll.add_child(_rows)

	var cancel := Button.new()
	cancel.text = PanelCloseKeysScript.CLOSE_HINT
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 32)
	cancel.pressed.connect(_on_cancel)
	col.add_child(cancel)


func open(title: String, subtitle: String, options: Array) -> void:
	"""Show a numbered choice. `options` is an array of Strings (BBCode allowed)."""
	_title.clear()
	_title.append_text(title)
	_subtitle.clear()
	_subtitle.append_text(subtitle)
	_subtitle.visible = subtitle != ""
	for c in _rows.get_children():
		c.queue_free()
	_buttons.clear()
	for i in range(options.size()):
		var b := Button.new()
		b.text = "[%d]  %s" % [i + 1, String(options[i])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_on_row.bind(i))
		_rows.add_child(b)
		_buttons.append(b)
	move_to_front()
	visible = true
	call_deferred("_fit_to_viewport")


func close() -> void:
	visible = false


func _fit_to_viewport() -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var vp: Vector2 = get_viewport_rect().size
	if assumed_screen_height <= 0.0 and vp.x > 0.0 and vp.y > 0.0:
		position = Vector2.ZERO
		size = vp
	var screen_h: float = assumed_screen_height if assumed_screen_height > 0.0 else size.y
	if screen_h <= 0.0:
		return
	var wanted: float = _rows.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(wanted, 60.0, screen_h * MAX_SCREEN_FRACTION)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		call_deferred("_fit_to_viewport")


func _on_row(i: int) -> void:
	visible = false
	chosen.emit(i)


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if PanelCloseKeysScript.wants_close(event):
		get_viewport().set_input_as_handled()
		_on_cancel()
		return
	# 1-9 pick a row. The panel owns these keys while it is up, which is the other half of why a
	# text menu behind a panel was unusable: the panel's own action bar was eating them.
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: int = (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_9:
			var idx: int = k - KEY_1
			if idx < _buttons.size():
				get_viewport().set_input_as_handled()
				_on_row(idx)
