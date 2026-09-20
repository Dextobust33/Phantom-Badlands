extends SceneTree
## ⛑ IS THE PHANTOM-POST FEATURE ACTUALLY HELD, OR ONLY DESCRIBED AS HELD?
##
## Owner 2026-09-19, starting the arc with limited time: *"implement in a way where if we don't
## finish we can hold anything breaking."*
##
## ⚡ A FLAG IS ONLY A HOLD IF EVERY DOOR CHECKS IT. The usual failure is guarding the shop window
## and not the till: the build menu shows nothing, so nobody notices that a hand-sent
## `buy_prefab_post` still works. A client can send any message it likes, so the purchase has to
## refuse on its own account rather than trust that nothing offered it.
##
## WHAT THIS ASSERTS:
##   1. the flag exists and is OFF (this is the unfinished state; flipping it is a deliberate act)
##   2. BOTH doors check it — the listing and the purchase
##   3. the tier data is complete and self-consistent, so turning it on cannot half-work
##   4. ⚑ NO TIER MENTIONS A PHANTOM, because the Phantom does not exist yet
##
## ⛑ (4) IS THE ONE THAT MATTERS MOST. The whole point of these posts is the Phantom inside them.
## Selling a charter that promises one before it exists is a promise taken in Valor and not
## returned — and Valor is not refundable by any path in the game. The tiers are priced to be
## worth it for the post ALONE, and the Phantom joins the layouts when it works.
##
## Run:
##   godot --headless --path . --script res://tools/probe/a_held_feature_is_really_held.gd

const PrefabPostsScript := preload("res://shared/prefab_posts.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")

	print("")
	print("===== 1. THE HOLD IS ON =====")
	if srv.find("const PHANTOM_POSTS_ENABLED := false") < 0:
		if srv.find("const PHANTOM_POSTS_ENABLED := true") >= 0:
			_ok("the feature is switched ON - this is only correct once a rung works end to end")
		else:
			_fail("there is no PHANTOM_POSTS_ENABLED flag at all - the feature cannot be held")
	else:
		_ok("the feature is held (PHANTOM_POSTS_ENABLED = false)")

	print("")
	print("===== 2. BOTH DOORS CHECK IT =====")
	# ⛑ The listing AND the purchase, bounded to each function so a check in one cannot satisfy
	# the test for the other.
	for fname in ["_prefab_charters_for", "handle_buy_prefab_post"]:
		var i := srv.find("func %s(" % fname)
		if i < 0:
			_fail("%s is gone - re-point this probe" % fname)
			continue
		var j := srv.find("\nfunc ", i + 8)
		var body := srv.substr(i, (j - i) if j > i else 3000)
		if body.find("PHANTOM_POSTS_ENABLED") < 0:
			_fail("%s does not check the flag. A client can send any message it likes, so "
				% fname + "guarding only the menu leaves the purchase reachable by hand")
		else:
			_ok("%s refuses while the feature is held" % fname)

	print("")
	print("===== 3. THE TIER LADDER IS COMPLETE =====")
	var tiers: Array = PrefabPostsScript.tiers()
	print("  %-26s %-9s %-7s %s" % ["charter", "valor", "size", "stations"])
	var last_cost := -1
	var ids := {}
	for t in tiers:
		var r: int = int(t.get("radius", 0))
		print("  %-26s %-9d %-7s %s" % [String(t.get("name", "?")), int(t.get("valor", 0)),
			"%dx%d" % [r * 2 + 1, r * 2 + 1], ", ".join(t.get("stations", []))])
		var tid := String(t.get("id", ""))
		if tid == "" or ids.has(tid):
			_fail("a tier has a missing or duplicate id (%s)" % tid)
		ids[tid] = true
		if int(t.get("valor", 0)) <= last_cost:
			_fail("%s does not cost more than the rung below it - the ladder has no direction"
				% String(t.get("name", "?")))
		last_cost = int(t.get("valor", 0))
		if String(t.get("blurb", "")) == "":
			_fail("%s has no description, so the build menu can only show a price"
				% String(t.get("name", "?")))

	print("")
	print("===== 4. EVERY LAYOUT IS A SEALED WALL WITH ONE DOOR =====")
	for t in tiers:
		var tid := String(t.get("id", ""))
		var layout: Array = PrefabPostsScript.layout_for(tid)
		var r: int = int(t.get("radius", 0))
		var doors := 0
		var walls := 0
		var stations := 0
		var seen := {}
		for cell in layout:
			var k := "%d,%d" % [int(cell.dx), int(cell.dy)]
			if seen.has(k):
				_fail("%s places two tiles on %s" % [tid, k])
			seen[k] = String(cell.type)
			match String(cell.type):
				"door": doors += 1
				"wall": walls += 1
				_: stations += 1
		# ⚑ A PERIMETER WITH A HOLE IS A POST MONSTERS WALK INTO. The count is derived rather
		# than eyeballed: a square ring of radius r has (2r+1)^2 - (2r-1)^2 cells.
		var want_edge: int = (r * 2 + 1) * (r * 2 + 1) - (r * 2 - 1) * (r * 2 - 1)
		if walls + doors != want_edge:
			_fail("%s has %d perimeter tiles, expected %d - the wall has a hole in it"
				% [tid, walls + doors, want_edge])
		elif doors != 1:
			_fail("%s has %d doors; the owner asked for one" % [tid, doors])
		else:
			_ok("%s: sealed %dx%d wall, one door, %d station(s)"
				% [tid, r * 2 + 1, r * 2 + 1, stations])
		# Stations must be INSIDE, or they are part of the wall and unreachable.
		for cell in layout:
			if String(cell.type) in ["wall", "door"]:
				continue
			if absi(int(cell.dx)) >= r or absi(int(cell.dy)) >= r:
				_fail("%s puts a %s on the perimeter, where it cannot be used"
					% [tid, String(cell.type)])

	print("")
	print("===== 5. NOTHING PROMISES A PHANTOM YET =====")
	# The Phantom is the whole point of these posts and it does not exist. Valor is not refundable
	# by any path in the game, so a charter that mentions one is a debt that cannot be settled.
	for t in tiers:
		var blob := (String(t.get("name", "")) + " " + String(t.get("blurb", "")) + " "
			+ ", ".join(t.get("stations", []))).to_lower()
		if blob.find("phantom") >= 0:
			_fail("%s mentions a Phantom, which does not exist yet - that is a promise taken in "
				% String(t.get("name", "?")) + "Valor, and Valor cannot be refunded")
	if _fails.is_empty():
		_ok("no charter promises a Phantom")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the feature is held at every door, and the ladder it is holding is")
	print("       complete and promises nothing it cannot deliver.")
	quit()
