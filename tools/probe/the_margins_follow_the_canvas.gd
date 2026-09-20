extends SceneTree
## ⛑ DO THE MARGIN WIDGETS MOVE WHEN THE BOX THEY ARE MEASURED AGAINST MOVES?
##
## Owner 2026-09-19, with a screenshot from the live server: after a fight the Area/Region box,
## the minimap, the map frame and the party strip all sat too far right for a moment — the frame
## starting in the middle of the map — before snapping into place.
##
## ⚡ THEY ARE PLACED AGAINST `canvas.size.x`, AND THE CANVAS IS WIDER DURING A FIGHT.
## `_place_map_widgets` computes the margin as `(canvas.size.x - _ow_map_px_w) * 0.5` and the map
## frame's left edge the same way. `_process` hides `map_panel` while the combat scene is up so
## the fight fills the full TopSection width (v0.9.663) — so anything laid out in that moment is
## positioned for a canvas several hundred pixels wider than the one the player is handed back.
##
## ⛑ AND NOTHING LISTENED FOR A RESIZE. There was not one `resized.connect` in a 56,000-line
## file. The placement ran on mode changes and on map redraws, both of which can happen while the
## canvas is the wrong size, and never simply because the box it measures against moved — so the
## same fault applied to an ordinary WINDOW resize, not only to leaving combat.
##
## WHAT THIS ASSERTS:
##   1. something is connected to the canvas's `resized`
##   2. it re-places the widgets, rather than only noting the new size
##   3. it is guarded on an actual change, because `resized` fires liberally and the placement
##      RE-PARENTS nodes
##
## Run:
##   godot --headless --path . --script res://tools/probe/the_margins_follow_the_canvas.gd

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("")
	print("===== 1. SOMETHING WATCHES THE CANVAS =====")
	if cli.find("canvas.resized.connect(_on_canvas_resized)") < 0:
		_fail("nothing connects to the canvas's resized signal - the margin widgets keep whatever "
			+ "position they were given while the canvas was a different width")
	else:
		_ok("the canvas's resized signal is connected")
	if cli.find("_watch_canvas_resize()") < 0:
		_fail("the watcher is never armed, so the connection above is never made")
	else:
		_ok("the watcher is armed")

	print("")
	print("===== 2. IT ACTUALLY RE-PLACES THEM =====")
	var i := cli.find("func _on_canvas_resized() -> void:")
	if i < 0:
		_fail("_on_canvas_resized does not exist")
	else:
		var j := cli.find("\nfunc ", i + 8)
		var body := cli.substr(i, (j - i) if j > i else 1600)
		# Noting the width without re-placing would look like a fix and change nothing on screen.
		if body.find("_place_map_widgets(") < 0:
			_fail("the handler records the new size but never re-places the widgets")
		else:
			_ok("it re-places the map widgets")
		if body.find("_place_stance_bar(") < 0:
			_fail("the stance/travel row is not re-placed - it is one of these widgets too, and "
				+ "was in the screenshot")
		else:
			_ok("it re-places the stance row as well")
		# ⚑ `resized` fires liberally and `_place_map_widgets` RE-PARENTS nodes, so an unguarded
		# handler would be re-parenting several controls every time anything nudges the layout.
		if body.find("< 1.0") < 0 and body.find("_margin_canvas_w") < 0:
			_fail("the handler is not guarded on an actual width change - it re-parents nodes, so "
				+ "running it on every resize event is a cost with no benefit")
		else:
			_ok("it only acts on a real width change")

	print("")
	print("===== 3. THE THING THAT MAKES THE CANVAS CHANGE IS STILL THERE =====")
	# If map_panel stopped being hidden during combat this whole fault would vanish - and so
	# would the reason for this probe. Worth knowing which it is if this ever goes quiet.
	if cli.find("map_panel.visible = not _combat_scene_should_show") < 0:
		_fail("map_panel is no longer toggled with the combat scene - re-check whether the canvas "
			+ "still changes width at all, and whether this probe still describes reality")
	else:
		_ok("map_panel still toggles with combat, so the canvas still changes width")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the margin widgets follow the canvas when it changes size, instead of")
	print("       keeping a position measured against a box that has since moved.")
	quit()
