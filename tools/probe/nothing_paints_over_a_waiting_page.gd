extends SceneTree
## ⛑ CAN ANYTHING PAINT THE MAP OVER A PAGE THE PLAYER HAS NOT READ YET?
##
## Owner, after the fourth lost-text report: *"Why are we still having issues where the text is
## being lost? ... It's literally killing features."* and *"When we find the proper solution to this
## we need to fix it so it can never happen again."*
##
## Three separate fixes were made for that class - the ChoicePanel for choices, the location-pass
## guard for events, and the page-claim sweep for prompts. What has never existed is a CHECK that
## the remaining path stays closed, and the backlog still carried a note saying a text page could
## be overwritten by the next map redraw.
##
## ⚡ AUDITED 2026-09-19: that note is STALE - every canvas-writing path is gated. But "it is
## guarded today" is precisely the belief that rots, because the guard is INDIRECT: the render and
## the heal both call `_ow_canvas_eligible()`, which calls `_free_to_roam()`, which is where
## `pending_continue` actually appears. Three hops. Anyone adding a fourth redraw path, or
## simplifying `_free_to_roam`, breaks it without touching anything that looks related.
##
## So this asserts the CHAIN, not the behaviour:
##   1. `_free_to_roam()` refuses while `pending_continue`
##   2. `_ow_canvas_eligible()` goes through `_free_to_roam()`
##   3. every place that paints the map is gated on `_ow_canvas_eligible()`
##
## Run:
##   godot --headless --path . --script res://tools/probe/nothing_paints_over_a_waiting_page.gd

var _fails: Array = []
func _fail(m: String) -> void:
	_fails.append(m); print("  FAIL  %s" % m)
func _ok(m: String) -> void:
	print("  ok    %s" % m)

func _body(src: String, fn: String) -> String:
	var i := src.find("func %s(" % fn)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 8)
	return src.substr(i, (j - i) if j > i else 3000)

func _init() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")

	print("")
	print("===== 1. `_free_to_roam` REFUSES WHILE A PAGE IS WAITING =====")
	var roam := _body(src, "_free_to_roam")
	if roam == "":
		_fail("_free_to_roam is gone - the whole chain rested on it")
	elif roam.find("not pending_continue") < 0:
		_fail("_free_to_roam no longer checks pending_continue - a waiting page can be painted over")
	else:
		_ok("_free_to_roam refuses while pending_continue")

	print("")
	print("===== 2. WHAT `_ow_canvas_eligible` ACTUALLY ANSWERS =====")
	# ⚡ IT IS NOT A PERMISSION CHECK, AND ITS NAME SUGGESTS OTHERWISE. It asks whether the map
	# COULD own the canvas - sprites available, not in a dungeon, not in combat - never whether
	# something is currently waiting to be read. The first draft of this probe asserted it consulted
	# `_free_to_roam`; it never did, and I had read a neighbouring function and believed it.
	var elig := _body(src, "_ow_canvas_eligible")
	if elig == "":
		_fail("_ow_canvas_eligible is gone")
	elif elig.find("pending_continue") >= 0:
		_ok("eligibility now answers the waiting question itself")
	else:
		print("  noted: it does NOT consider pending_continue - so every CALLER must, and that is")
		print("  what section 3 gates.")

	print("")
	print("===== 3. THE HEAL REFUSES WHILE A PAGE IS WAITING =====")
	# ⛑ THE HEAL IS THE DANGEROUS ONE. Its whole job is to put the map BACK after a page clears the
	# canvas, so it is the single path whose purpose is to overwrite. A short acknowledgement screen
	# fell straight through it until 2026-09-19: the length check only protects a page that printed
	# MORE text than the map did.
	var heal := _body(src, "_ow_heal_canvas")
	if heal == "":
		_fail("_ow_heal_canvas is gone")
	else:
		# ⛑ THE STATEMENT, NOT THE WORD. This first matched "pending_continue" anywhere in the
		# function - and the explanatory comment above the guard says it four times, so deleting the
		# guard still passed. Exactly the failure the healer probe hit hours earlier: a source scan
		# cannot tell a check from a note about a check.
		if heal.find("if pending_continue:") < 0:
			_fail("the canvas HEAL does not check pending_continue - it repaints over unread pages")
		else:
			_ok("the heal refuses while pending_continue")
		for guard in ["_ow_wide_page", "_canvas_panel_open()"]:
			if heal.find(guard) < 0:
				_fail("the heal no longer honours %s" % guard)

	print("")
	print("===== 4. NO RENDER PATH BYPASSES THE GATE =====")
	# Any line that hands a built map payload to the canvas must sit behind the gate. Counted
	# rather than named, so a NEW path shows up as a change in the number.
	var sets := src.count("_ow_rendering = true")
	print("  %d place(s) begin a map render" % sets)
	if sets != 1:
		_fail("%d render entry points - the gate was written for exactly one; check each" % sets)
	else:
		_ok("exactly one render entry point, and it reads _ow_canvas_eligible()")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS nothing repaints the map while a page is waiting to be read, and the")
	print("       three-hop chain that guarantees it is asserted rather than assumed.")
	quit()
