extends SceneTree
## ⛑ DOES THE MAP EVER GET DRAWN SOMEWHERE IT IS ABOUT TO LEAVE?
##
## Owner, live 2026-09-19: *"when combat ends... my map is drawn in the right column briefly and
## then moved to the left box."* And, on the design: *"Why do we need the original home in the
## side column? I believe Sanctuary, Overworld, and Dungeons all use game_output now."*
##
## ⚡ THE MAP HAS TWO HOMES AND ONE OF THEM WAS BEING USED BY ACCIDENT. `_ow_canvas_eligible()` is
## false for the whole of a Continue prompt (`_canvas_owned_by_combat()`), so every map payload
## arriving during a victory screen was drawn into the COLUMN — where nobody could see it, because
## `_process` hides `map_panel` during a fight so combat fills the full width. It became visible
## only in the gap between the panel returning and the next payload arriving, then jumped to the
## canvas when that payload landed.
##
## ⛑ THE COLUMN HOME IS NOT LEGACY AND MUST SURVIVE. It is the ASCII fallback for when
## `_OverworldRoom.available()` is false — the sprite art did not load. The map's own note calls
## it *"the thing that has to keep working when everything else fails"*, and CLAUDE.md documents
## how silently art can fail in this project (a `.gdignore` makes `ResourceLoader.exists()` lie).
## A probe that simply asserted "the column is never used" would be enforcing a regression.
##
## WHAT THIS ASSERTS:
##   1. the combat skip is gated on the SPRITE ROOM being available, so the fallback still draws
##   2. the skip does not catch dungeons or the sanctuary, which use the column for other things
##   3. leaving combat redraws the map from the cached payload rather than waiting for the server
##
## Run:
##   godot --headless --path . --script res://tools/probe/the_map_has_one_home_per_situation.gd

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("")
	print("===== 1. THE COMBAT SKIP EXISTS, AND KEEPS THE FALLBACK =====")
	var i := cli.find("func update_map(map_text: String):")
	if i < 0:
		_fail("update_map is gone - re-point this probe")
	else:
		# Bounded to the head of the function, where the guard belongs. A slice to the next
		# `func ` would sweep in the whole renderer and match on unrelated lines.
		var head := cli.substr(i, 2400)
		if head.find("in_combat or _canvas_owned_by_combat()") < 0:
			_fail("update_map no longer skips the draw while combat owns the canvas - a map "
				+ "payload during a victory screen is drawn into the hidden column again, and "
				+ "jumps to the box when the next payload lands")
		else:
			_ok("the draw is skipped while combat owns the canvas")
		# ⚑ THE HALF THAT PROTECTS THE FALLBACK. Without this test the skip could be tightened to
		# "always skip during combat", which would leave an art-failed build with NO map at all -
		# turning a cosmetic fix into the loss of the one thing meant to survive everything else.
		if head.find("_OverworldRoom.available()") < 0:
			_fail("the skip is not gated on the sprite room being available. With the art missing "
				+ "the column IS the map's real home, and skipping it leaves no map at all")
		else:
			_ok("the skip only applies when the sprite map is available")
		for other in ["dungeon_mode", "_house_room_active()"]:
			if head.find(other) < 0:
				_fail("the skip does not exempt %s, which uses these nodes differently" % other)
			else:
				_ok("the skip exempts %s" % other)

	print("")
	print("===== 2. LEAVING COMBAT PUTS THE MAP BACK ITSELF =====")
	var a := cli.find("func acknowledge_continue():")
	if a < 0:
		_fail("acknowledge_continue is gone")
	else:
		var b := cli.find("\nfunc ", a + 8)
		var body := cli.substr(a, (b - a) if b > a else 9000)
		# With the skip above, nothing has drawn the map since the fight began. If this redraw is
		# missing the player is handed a stale or empty column until the server's next update -
		# which is the bug, moved rather than fixed.
		if body.find("update_map(_overworld_display(_last_map_payload))") < 0:
			_fail("leaving combat no longer redraws the map from the cached payload - with the "
				+ "skip in place that means no map until the server's next location update")
		else:
			_ok("leaving combat redraws the map from the cached payload")
		if body.find("_ow_canvas_eligible()") < 0:
			_fail("the redraw is not gated on the canvas being eligible, so it could fire in a "
				+ "dungeon or with the art missing and put the map in the wrong home")
		else:
			_ok("the redraw only fires when the canvas is the right home")

	print("")
	print("===== 3. TEXT STILL HAS SOMEWHERE TO GO =====")
	# The map taking the canvas is only safe because pages move to the column when it does. If
	# that routing were removed, this fix would silently start eating the post-combat block.
	if cli.find("func _ow_text_in_column()") < 0:
		_fail("_ow_text_in_column is gone - with the map on the canvas, pages have nowhere to go "
			+ "and the post-combat text would be painted over")
	else:
		_ok("pages route to the column while the map holds the canvas")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the map is only drawn in the home it is going to stay in, and the ASCII")
	print("       fallback still has its own.")
	quit()
