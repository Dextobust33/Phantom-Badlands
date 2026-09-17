extends SceneTree
## ⛑ CAN THE PLAYER CLICK THE ACTION BAR AND THE STATUS PANEL AND RESIZE THEM?
##
## Backlog: *"Extend UI-scale registration to the elements that still lack it (action bar, status
## HUD, inventory, market, crafting, sanctuary)."* The first two are done; this proves it.
##
## Measured on the REAL client scene, the way `ui_scale_1080p.gd` does, because the two ways this
## silently fails are both invisible in the source:
##
##   1. **A registration that never applies.** `register()` stores the group and calls the
##      applier, so the registry can hold "action_bar" while the FONT never moves — if the apply
##      path does not read `get_scale`, everything looks wired and nothing changes size. That is
##      the shape of a silent no-op: the feature is present, reachable, and does nothing.
##   2. **A per-element scale that overwrites the bulk slider** instead of multiplying with it.
##      Then the settings menu shows a number the player never typed.
##
## Run:
##   godot --headless --path . --script res://tools/probe/ui_scale_registration.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _font(c: Control) -> int:
	if c == null or not is_instance_valid(c):
		return -1
	return int(c.get_theme_font_size("normal_font_size"))


func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://client/client.tscn")
	if scene == null:
		print("could not load client.tscn"); quit(1); return
	var c = scene.instantiate()
	get_root().add_child(c)
	for _i in range(8):
		await process_frame

	var mgr = c.ui_scale_manager
	ck(mgr != null, "the client built a UI scale manager")
	if mgr == null:
		quit(1); return

	print("\n===== 1. THE GROUPS ARE REGISTERED =====")
	for g in ["world_map", "action_bar", "status_hud"]:
		ck(mgr.has_group(g), "%s is registered as \"%s\"" % [g, mgr.get_display_name(g)])

	print("\n===== 2. AND THE FONTS ACTUALLY MOVE =====")
	# ⛑ THE CHECK THAT MATTERS. A group in the registry proves nothing: the apply path has to
	# READ the per-element scale, and if it does not, this is a no-op that looks like a feature.
	var bar_btn: Control = null
	if c.action_buttons.size() > 0:
		bar_btn = c.action_buttons[0]
	var hud: Control = c.tool_status_overlay

	# ⛑ SETTLE FIRST. Read straight after `instantiate()` the fonts are whatever the scene file
	# carries, not what the scaling code produces at 1.0 x 1.0 - so the baseline disagreed with
	# the settled value (29 vs 44) and differed between runs, which failed a different check each
	# time. One explicit resize pass, then measure.
	c._on_window_resized()
	for _i in range(4):
		await process_frame
	var bar_before: int = int(bar_btn.get_theme_font_size("font_size")) if bar_btn != null else -1
	var hud_before: int = _font(hud)
	print("           settled at 1.0x: action bar %dpx, status panel %dpx" % [bar_before, hud_before])
	# The action bar's baseline must be off its clamp, or "it shrinks" below cannot fail.
	ck(bar_before > 15, "the action bar's baseline is off the floor, so shrinking is measurable (%d)" % bar_before)
	# ⛑ THE STATUS PANEL IS DELIBERATELY ALREADY AT ITS FLOOR, and that is a measurement worth
	# pinning rather than a fault. Owner 2026-09-15: *"The status panel text can be smaller by
	# default so it can take up less vertical space as well as needed."* At 1080p that lands on
	# 10px against a `clampi(..., 9, 28)` floor - so the slider's useful direction is UP, and
	# asking this probe to prove it shrinks would be asserting something the design rejects.
	# If the default ever drifts back up, this check is what says so.
	ck(hud_before <= 11,
		"the status panel is at its small default, as asked for (%dpx, floor 9)" % hud_before)

	mgr.set_scale("action_bar", 2.0)
	mgr.set_scale("status_hud", 2.0)
	for _i in range(4):
		await process_frame
	var bar_big: int = int(bar_btn.get_theme_font_size("font_size")) if bar_btn != null else -1
	var hud_big: int = _font(hud)
	print("           at 2.0x: action bar %dpx, status panel %dpx" % [bar_big, hud_big])
	ck(bar_before > 0 and bar_big > bar_before,
		"the action bar grows (%d -> %d)" % [bar_before, bar_big])
	ck(hud_before > 0 and hud_big > hud_before,
		"the status panel grows (%d -> %d)" % [hud_before, hud_big])

	# And DOWN, because a clamp that pins the low end would make the feature one-way.
	mgr.set_scale("action_bar", 0.5)
	mgr.set_scale("status_hud", 0.5)
	for _i in range(4):
		await process_frame
	var bar_small: int = int(bar_btn.get_theme_font_size("font_size")) if bar_btn != null else -1
	var hud_small: int = _font(hud)
	print("           at 0.5x: action bar %dpx, status panel %dpx" % [bar_small, hud_small])
	ck(bar_small < bar_before, "and the action bar shrinks (%d -> %d)" % [bar_before, bar_small])
	# Not asserted to shrink: it starts one point off the floor by design (see above). What
	# matters is that the knob is not one-way in the direction it CAN move, which the growth
	# check proves, and that 0.5x does not somehow grow it.
	ck(hud_small <= hud_before,
		"  and the status panel does not grow when told to shrink (%d -> %d)" % [hud_before, hud_small])

	print("\n===== 3. IT DOES NOT CLOBBER THE SETTINGS SLIDER =====")
	# The settings menu owns the BULK factor and the overlay owns the PER-ELEMENT one; the font is
	# their product. Writing one into the other would make the menu display a number the player
	# never typed - the one-value-two-places shape this project keeps paying for.
	ck(absf(c.ui_scale_buttons - 1.0) < 0.001,
		"the action-bar slider is still 1.0 after the overlay moved the bar (%.2f)" % c.ui_scale_buttons)
	ck(absf(c.ui_scale_status_hud - 1.0) < 0.001,
		"and the status slider too (%.2f)" % c.ui_scale_status_hud)
	# ...and they COMPOSE: slider x per-element, not one or the other.
	# ⛑ MEASURED WELL INSIDE THE CLAMP. The first version of this used slider 2.0x, where the
	# font is already pinned at BUTTON_MAX_FONT_SIZE (44px) - so the per-element factor changed
	# nothing and the check passed on `>=` while proving nothing at all. A cell where the clamp
	# is binding cannot tell composition from replacement.
	mgr.set_scale("action_bar", 1.0)
	c.ui_scale_buttons = 0.6
	c._on_window_resized()
	for _i in range(3):
		await process_frame
	var bar_slider_only: int = int(bar_btn.get_theme_font_size("font_size")) if bar_btn != null else -1
	mgr.set_scale("action_bar", 1.5)
	for _i in range(3):
		await process_frame
	var bar_both: int = int(bar_btn.get_theme_font_size("font_size")) if bar_btn != null else -1
	print("           slider 0.6x alone %dpx, with 1.5x per-element %dpx" % [bar_slider_only, bar_both])
	ck(bar_both > bar_slider_only,
		"the two MULTIPLY rather than replace each other (%d -> %d)" % [bar_slider_only, bar_both])
	# And the other direction, so neither factor is being quietly ignored.
	mgr.set_scale("action_bar", 1.0)
	c.ui_scale_buttons = 1.0
	c._on_window_resized()
	for _i in range(3):
		await process_frame
	var bar_neutral: int = int(bar_btn.get_theme_font_size("font_size")) if bar_btn != null else -1
	ck(bar_neutral == bar_before,
		"and 1.0 x 1.0 returns to the starting size (%d vs %d)" % [bar_neutral, bar_before])

	print("\n===== NOT COVERED HERE =====")
	print("  The four surfaces still unregistered (inventory, market, crafting, sanctuary).")
	print("  They are text in game_output or whole panels rather than one control with one")
	print("  font, so each needs its own applier - not the same three lines.")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
