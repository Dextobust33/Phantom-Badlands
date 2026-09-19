extends Control
class_name TutorialHintPanel

const PanelCloseKeysScript := preload("res://client/panel_close_keys.gd")

# Audit #3 Slice 4 — modal overlay for tutorial/teaching messages. Replaces
# the v0.9.474 game_output-text version of the progression hint per the
# feedback rule "teaching messages must render in overlays, not chat."
#
# Single-use show(title, body) opens a centered modal with a dim backdrop.
# Player dismisses via the "Got it" button or Esc.

signal dismissed
## Emitted when the player asks not to be shown these again. Account-level, not per character:
## someone who knows the game should not be taught it once per character they roll.
signal opted_out

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _body_scroll: ScrollContainer
var _body_label: RichTextLabel
var _dismiss_button: Button
var _opt_out_button: Button


func _ready() -> void:
	# top_level=true makes this a true viewport-anchored overlay — it ignores
	# parent transform/layout, preventing it from perturbing sibling sizing
	# even while hidden. (v0.9.487 fix: nested CenterContainer+PRESET_FULL_RECT
	# was shrinking the map when added as a Control sibling.)
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func show_hint(title: String, body: String, opt_out_text: String = "",
		dismiss_text: String = "") -> void:
	if _title_label:
		_title_label.clear()
		_title_label.append_text(title)
	if _body_label:
		_body_label.clear()
		_body_label.append_text(body)
	# Always bring to front so we draw on top of any other panel that may
	# have been added later (e.g., Companion Stable panel arrives in the same
	# message burst as the first-time tutorial hint).
	move_to_front()
	visible = true
	# The opt-out is offered only where it is asked for - the very first hint an account
	# ever sees. Putting it on every hint turns every lesson into a chance to switch the
	# lessons off by accident.
	if _opt_out_button:
		_opt_out_button.visible = opt_out_text != ""
		if opt_out_text != "":
			_opt_out_button.text = opt_out_text
	if _dismiss_button:
		# Some hints ask the player to AGREE to something rather than merely read it - the
		# Warden setting off is the first. "Got it" is a wrong label for a decision.
		_dismiss_button.text = dismiss_text if dismiss_text != "" else "Got it  (Esc / Space)"
	# Deferred, because the body's wrapped height is not known until it has been laid out once.
	call_deferred("_fit_to_viewport")


## The fraction of the screen a hint may occupy before its body starts scrolling. Chosen so the
## title, the button row and the panel's own margins all still fit at 720p, the smallest window
## the game supports.
const MAX_SCREEN_FRACTION := 0.62

## Test hook only - see `_fit_to_viewport`. Zero means "measure the real viewport".
var assumed_screen_height: float = 0.0


func _fit_to_viewport() -> void:
	"""Cap the body so the buttons stay on screen, whatever the hint says.

	⛑ IT CLAIMS ITS OWN RECT FIRST, and that is not belt-and-braces. This panel sets
	`top_level = true`, and a top_level Control has NO PARENT RECT - `PRESET_FULL_RECT` resolves
	against nothing, so the overlay is zero-sized and its CenterContainer has nothing to centre
	within. That is the second half of what the owner photographed: the hint was not merely too
	tall, it was pinned to the top-left instead of centred. Same trap as the full-screen modal
	whose dim covered nothing.

	`assumed_screen_height` exists for `tools/probe/hint_panel_fits_the_screen.gd`, which has to
	state the screen height it is testing: a headless viewport reports the project's own default
	(1920) rather than the window the player is on, and a ceiling that only holds at 1920 is not a
	ceiling. Zero in every normal run, so the game always measures the real viewport."""
	if _body_scroll == null or not is_instance_valid(_body_scroll):
		return
	var vp: Vector2 = get_viewport_rect().size
	if assumed_screen_height <= 0.0 and vp.x > 0.0 and vp.y > 0.0:
		position = Vector2.ZERO
		size = vp
	var screen_h: float = assumed_screen_height if assumed_screen_height > 0.0 else size.y
	if screen_h <= 0.0:
		return
	var wanted: float = _body_label.get_content_height() if _body_label else 0.0
	_body_scroll.custom_minimum_size.y = clampf(wanted, 80.0, screen_h * MAX_SCREEN_FRACTION)


func _notification(what: int) -> void:
	# A window resize can make a hint that fitted stop fitting.
	if what == NOTIFICATION_RESIZED and visible:
		call_deferred("_fit_to_viewport")
		_dismiss_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if PanelCloseKeysScript.wants_close(event):
		get_viewport().set_input_as_handled()
		_on_dismiss()


func _build_layout() -> void:
	# Dim backdrop (blocks input behind panel).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# Use a full-rect CenterContainer to keep the panel centered on screen as
	# the viewport resizes. (Setting PRESET_CENTER + KEEP_SIZE directly on the
	# panel anchored it to (0,0) before the panel had a computed size, causing
	# the top-left cutoff seen in v0.9.475/476 tutorial overlays.)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(520, 0)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.10, 0.08, 0.16, 0.98)
	panel_sb.border_color = Color(1.0, 0.84, 0.0, 1.0)  # gold border
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 22
	panel_sb.content_margin_right = 22
	panel_sb.content_margin_top = 18
	panel_sb.content_margin_bottom = 18
	_root_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_root_panel.add_child(vbox)

	# Title (gold, bold).
	_title_label = RichTextLabel.new()
	_title_label.bbcode_enabled = true
	_title_label.fit_content = true
	_title_label.scroll_active = false
	_title_label.add_theme_font_size_override("normal_font_size", 18)
	_title_label.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(_title_label)

	# Body (wraps inside panel width), INSIDE A SCROLLER WITH A CEILING.
	#
	# ⚡ Owner 2026-09-18, with a screenshot: *"Companion screen is too long vertically again, I
	# can't even see the button to click at the bottom."*
	#
	# ⛑ `fit_content` WITH NO CAP MEANS THE PANEL IS AS TALL AS THE TEXT. The first-companion hint
	# is around 1,400 characters - roughly 40 wrapped lines - so the panel grew past the viewport,
	# and because a CenterContainer centres it, it overflowed at BOTH ends: the title off the top
	# and the "Got it" button off the bottom, with nothing to scroll and no way to dismiss but the
	# keyboard. Any hint long enough does this, which is why it has come back: each time it was the
	# TEXT that got shortened rather than the panel that got a ceiling.
	#
	# `_fit_to_viewport` sizes this scroller to the content up to a fraction of the screen, so a
	# short hint is still a small box and a long one scrolls with its buttons still on screen.
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.custom_minimum_size = Vector2(476, 80)
	vbox.add_child(_body_scroll)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	# Hints can embed a 32px sprite (the Warden's portrait, so a new player knows what they are
	# looking for). Scaled up with the default filter it is a smear; pixel art needs NEAREST.
	_body_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.add_theme_font_size_override("normal_font_size", 14)
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.custom_minimum_size = Vector2(476, 0)
	_body_scroll.add_child(_body_label)

	# Spacer + dismiss button row.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_dismiss_button = Button.new()
	_dismiss_button.text = "Got it  (Esc / Enter)"
	_dismiss_button.custom_minimum_size = Vector2(220, 32)
	_dismiss_button.focus_mode = Control.FOCUS_ALL
	_dismiss_button.pressed.connect(_on_dismiss)
	btn_row.add_child(_dismiss_button)

	_opt_out_button = Button.new()
	_opt_out_button.custom_minimum_size = Vector2(220, 32)
	_opt_out_button.focus_mode = Control.FOCUS_ALL
	_opt_out_button.visible = false
	_opt_out_button.pressed.connect(_on_opt_out)
	btn_row.add_child(_opt_out_button)


func _on_dismiss() -> void:
	visible = false
	dismissed.emit()


func _on_opt_out() -> void:
	visible = false
	opted_out.emit()
	dismissed.emit()
