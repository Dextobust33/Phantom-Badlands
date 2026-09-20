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
		if body.find("_restore_overworld_map()") < 0:
			_fail("leaving combat no longer restores the map - with the combat skip in place that "
				+ "means no map at all until the server's next location update")
		else:
			_ok("leaving combat restores the map")
		# ⚡ ORDER, NOT JUST PRESENCE. The restore must run BEFORE the post-combat text is
		# printed. `_ow_text_in_column()` routes pages to the column only while the map holds the
		# canvas, so restoring afterwards leaves that text ON the canvas - which is how a live
		# player ended up with no map at all rather than a late one. Reported with a screenshot.
		var at_restore := body.find("_restore_overworld_map()")
		var at_context := body.find("_display_post_combat_context()")
		if at_context >= 0 and at_restore > at_context:
			_fail("the map is restored AFTER the post-combat text is printed, so that text takes "
				+ "the canvas and the map has nowhere to go - the 'no map after a fight' report")
		else:
			_ok("the map is restored before anything prints to the canvas")

	print("")
	print("===== 2b. THE RESTORE SURVIVES AN UNSETTLED STATE =====")
	var r := cli.find("func _restore_overworld_map(")
	if r < 0:
		_fail("_restore_overworld_map does not exist")
	else:
		var rb := cli.substr(r, 1400)
		# `_ow_canvas_eligible()` asks whether combat still owns the canvas, and the panel's
		# visibility is settled by _process rather than inline - so one attempt at the instant
		# Continue is pressed can legitimately answer "no". That is what produced a blank canvas.
		if rb.find("call_deferred(\"_restore_overworld_map\"") < 0:
			_fail("the restore gives up if the canvas is not eligible at that exact instant, "
				+ "which is the state that produced a blank canvas on the first fight")
		else:
			_ok("the restore retries once on the next frame")
		if rb.find("_ow_canvas_eligible()") < 0:
			_fail("the restore is not gated on the canvas being the right home")
		else:
			_ok("it still only draws when the canvas is the right home")
		# ⚡ THE EMPTY-CACHE CASE. Reported on the FIRST fight of a session and not later ones,
		# which is the signature of a cache that has not been filled yet. Returning quietly there
		# leaves the player with no map at all until they happen to rest or move - both of which
		# make the server resend one, which is why they "fixed" it.
		if rb.find("request_location") < 0:
			_fail("with nothing cached to draw the restore gives up silently, so a player whose "
				+ "first fight happens before a map payload arrives has no map until they move")
		else:
			_ok("with nothing cached it asks the server for a fresh map")

	print("")
	print("===== 2c. THE SERVER ANSWERS THAT REQUEST =====")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	# Half a feature is worse than none here: the client would ask on every mapless fight and
	# nothing would come back, which looks exactly like the bug it was meant to fix.
	if srv.find("\"request_location\":") < 0:
		_fail("the server has no handler for request_location - the client asks and nothing "
			+ "answers, which is indistinguishable from the original bug")
	else:
		_ok("the server answers request_location")

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
