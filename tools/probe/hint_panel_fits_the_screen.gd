extends SceneTree
## ⛑ DOES A LONG TUTORIAL HINT STILL FIT ON THE SCREEN?
##
## Owner 2026-09-18, with a screenshot of the first-companion hint running off both ends of the
## window: *"Companion screen is too long vertically AGAIN, I can't even see the button to click at
## the bottom."*
##
## ⚑ "AGAIN" IS THE WHOLE POINT. `fit_content` with no ceiling means the panel is exactly as tall
## as its text, and a `CenterContainer` then centres it — so a long hint overflows at BOTH ends,
## taking the title off the top and the dismiss button off the bottom, with nothing to scroll. Every
## previous round of this shortened the TEXT. The text grows again.
##
## So the check is on the PANEL, not on any hint: build it, hand it a body far longer than anything
## the game ships, lay it out at the smallest supported window, and measure whether the button is
## still on screen. A source-reading check cannot answer this — it is a number that only exists once
## the thing has been laid out.
##
## Run:
##   godot --headless --path . --script res://tools/probe/hint_panel_fits_the_screen.gd

const HintPanel := preload("res://client/tutorial_hint_panel.gd")

## The smallest window the game supports. If it fits here it fits everywhere.
const SCREEN := Vector2i(1280, 720)

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	# ⛑ SIZE IT BY HAND, EVERY FRAME. This panel sets `top_level = true`, and a top_level Control
	# has NO PARENT RECT - `PRESET_FULL_RECT` resolves to a zero-size rect, so headless it lays out
	# at the origin with nothing inside it and every measurement below reads 0. That trap is already
	# in this project's notes from a full-screen modal that "opened" and covered nothing; it is why
	# the first run of this probe reported a 216px panel for both a 4,560-character hint and a
	# one-line one.
	root.content_scale_size = SCREEN
	root.size = SCREEN
	var panel = HintPanel.new()
	root.add_child(panel)
	await process_frame
	panel.assumed_screen_height = float(SCREEN.y)
	panel.size = Vector2(SCREEN)
	print("  viewport reports %s" % str(panel.get_viewport_rect().size))

	# A body four times the longest hint the game actually sends (the first-companion one, ~1,400
	# characters). A ceiling that only holds for the hints we have today is not a ceiling.
	var para := ("Companions fight beside you in combat, share XP, and grow stronger as you do. "
		+ "Each monster type has unique abilities, passive and active and threshold. ")
	var body := ""
	for _i in range(30):
		body += para
	print("")
	print("===== 1. A HINT FOUR TIMES THE LONGEST ONE WE SEND =====")
	print("  screen %dx%d, body %d characters" % [SCREEN.x, SCREEN.y, body.length()])
	panel.show_hint("✦ Companions", body, "Don't show these again", "")

	# Let the layout settle: fit_content, the deferred cap, and the container pass each need a frame.
	for _f in range(8):
		panel.size = Vector2(SCREEN)
		panel._fit_to_viewport()
		await process_frame

	var root_panel: PanelContainer = null
	var dismiss: Button = null
	for n in _walk(panel):
		if n is PanelContainer and root_panel == null and n.get_parent() is CenterContainer:
			root_panel = n
		if n is Button and String(n.text).begins_with("Got it"):
			dismiss = n
	if root_panel == null or dismiss == null:
		_fail("could not find the panel or its dismiss button - the layout has changed shape")
		_finish()
		return

	print("")
	print("===== 2. WHERE THINGS ACTUALLY LANDED =====")
	var pr: Rect2 = Rect2(root_panel.global_position, root_panel.size)
	var br: Rect2 = Rect2(dismiss.global_position, dismiss.size)
	print("  panel   top %.0f  bottom %.0f  (height %.0f)" % [pr.position.y, pr.end.y, pr.size.y])
	for n in _walk(panel):
		if n is ScrollContainer:
			print("  scroll  min %s  size %s  combined_min %s" % [
				str(n.custom_minimum_size), str(n.size), str(n.get_combined_minimum_size())])
			for c in n.get_children():
				if c is Control:
					print("  label   min %s  size %s  combined_min %s" % [
						str((c as Control).custom_minimum_size), str((c as Control).size),
						str((c as Control).get_combined_minimum_size())])
	print("  button  top %.0f  bottom %.0f" % [br.position.y, br.end.y])
	if pr.position.y < 0.0:
		_fail("the panel's top is %.0f px above the screen" % -pr.position.y)
	else:
		_ok("the title is on screen")
	if pr.end.y > float(SCREEN.y):
		_fail("the panel runs %.0f px past the bottom of the screen" % (pr.end.y - float(SCREEN.y)))
	else:
		_ok("the panel ends on screen")
	if br.end.y > float(SCREEN.y) or br.position.y < 0.0:
		_fail("the dismiss button is OFF SCREEN (top %.0f, bottom %.0f, screen %d)" % [
			br.position.y, br.end.y, SCREEN.y])
	else:
		_ok("the player can see the button they are meant to click")

	print("")
	print("===== 3. A SHORT HINT IS STILL A SMALL BOX =====")
	# ⛑ THE FAILURE MODE OF A NAIVE CAP: pinning the body to the ceiling would make a one-line
	# hint a full-screen box, which is worse than the bug.
	panel.show_hint("✦ Test", "One short line.", "", "")
	for _f in range(8):
		panel.size = Vector2(SCREEN)
		panel._fit_to_viewport()
		await process_frame
	var short_h: float = root_panel.size.y
	print("  a one-line hint is %.0f px tall (the long one was %.0f)" % [short_h, pr.size.y])
	if short_h >= pr.size.y:
		_fail("a short hint is as tall as a long one - the panel is pinned to its ceiling")
	else:
		_ok("the panel still sizes to its content")

	_finish()


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _finish() -> void:
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a hint of any length fits the smallest supported window, and a short one")
	print("       is still a small box.")
	quit()
