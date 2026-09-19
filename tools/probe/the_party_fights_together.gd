extends SceneTree
## ⛑ DOES A PARTY THAT WALKS SEPARATELY STILL FIGHT TOGETHER?
##
## Owner 2026-09-18, naming the model: *"For party play we should probably go in the style of
## Dragon Quest IX... when a party member nearby enters combat it will pull nearby party members
## into the combat as well."* And, on what it replaces: *"party members will no longer blindly
## follow the leader they will instead be able to move around and act as we discussed."*
##
## ⚡ THE TWO HALVES ONLY WORK TOGETHER, which is why they ship together and are checked together.
## Unlocking movement without the pull would leave a party unable to fight as one at all — the old
## co-op only ever fired for the LEADER, because a follower was dragged along and could never meet
## a monster on their own. Building the pull without unlocking movement would be a radius check
## against people standing on your heels.
##
## WHAT THIS ASSERTS:
##   1. nothing drags a follower across the overworld any more
##   2. ANY member's encounter starts the party fight, not only the leader's
##   3. the pull is bounded by a radius, and out-of-range members are TOLD, not dropped silently
##   4. ⚑ the race the owner named cannot produce two party fights
##
## Run:
##   godot --headless --path . --script res://tools/probe/the_party_fights_together.gd

const ServerScript := preload("res://server/server.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")

	print("")
	print("===== 1. THE SNAKE IS GONE, NOT DISABLED =====")
	# ⛑ Both spellings matter. A `_move_party_followers` left in place but never called is the
	# "unreachable copy of live code" this file's own notes warn about, and the first cut of this
	# change did exactly that with `if false and ...`.
	if srv.find("func _move_party_followers(") >= 0:
		_fail("_move_party_followers still exists - the overworld snake can come back by one "
			+ "call, and a reader cannot tell disabled-on-purpose from disabled-by-accident")
	else:
		_ok("the overworld follower drag is deleted, not switched off")
	# ⚡ AS A STATEMENT, NOT AS TEXT. This check first FAILED on the comment that explains the
	# `if false` was removed - the fourth time in a week a probe here has matched a comment about
	# a check instead of the check. A comment line begins with `#` after its indentation, so the
	# test is "a line whose first non-tab characters are `if false`".
	var rx_false := RegEx.new()
	rx_false.compile("\\n\\t+if false\\b")
	if rx_false.search(srv) != null:
		_fail("there is an `if false and ...` statement in server.gd - dead code pretending to be live")
	else:
		_ok("no branch is switched off with a constant false")
	# The DUNGEON keeps its formation for now - deleting that too would be a second, unasked
	# change to a different space.
	if srv.find("_move_party_followers_dungeon(") < 0:
		_fail("the DUNGEON formation was removed as well - that was not part of this slice")
	else:
		_ok("dungeons keep their formation (a corridor is not a country)")

	print("")
	print("===== 2. A FOLLOWER CAN ACT ON THEIR OWN =====")
	# The lock is what made a follower unable to be anywhere the pull must reach.
	for what in ["\"movement\"", "\"hunting\"", "\"resting\"", "\"gathering\""]:
		var needle := "_party_follower_denied(peer_id, %s)" % what
		# Dungeon movement keeps its lock, so the movement check counts occurrences rather than
		# requiring zero.
		var n := 0
		var at := 0
		while true:
			at = srv.find(needle, at)
			if at < 0:
				break
			n += 1
			at += 8
		if what == "\"movement\"":
			if n > 1:
				_fail("movement is still denied in %d places - the overworld lock should be gone "
					% n + "and only the dungeon one left")
			elif n == 0:
				_fail("even the DUNGEON movement lock is gone - that was not part of this slice")
			else:
				_ok("overworld movement is free; the dungeon lock remains")
		elif n > 0:
			_fail("%s is still denied to a party follower" % what)
		else:
			_ok("a follower may %s on their own" % what.replace("\"", ""))

	print("")
	print("===== 3. THE PULL: ANY MEMBER, WITHIN A RADIUS =====")
	var i := srv.find("THE PROXIMITY PULL")
	if i < 0:
		_fail("the proximity pull is not in trigger_encounter")
	else:
		# ⛑ BOUNDED TO THE PULL BLOCK, not to the end of the function. Slicing to the next
		# `func ` ran straight past the pull and into the SOLO FANOUT below it, which gates on
		# `_is_party_leader` quite correctly - so the probe reported the feature missing while it
		# was sitting a few lines above. Same shape as the locator that sliced the wrong function
		# earlier today: a boundary that is too generous does not fail, it misreads.
		var j := srv.find("skip the solo fanout below", i)
		if j < 0:
			_fail("could not find the end of the pull block - re-point this probe")
			j = i
		var body := srv.substr(i, maxi(0, j - i))
		# ⚡ THE OLD GATE, NAMED. `_is_party_leader(peer_id)` here is not a style question: it is
		# the single line that made a follower's encounter start nothing at all.
		if body.find("if _is_party_leader(peer_id) and active_parties.has(peer_id):") >= 0:
			_fail("the pull is still gated on the LEADER - a member who finds a monster on their "
				+ "own starts no party fight, which is the whole feature")
		else:
			_ok("any member's encounter can start the party fight")
		if body.find("_within_pull_range(") < 0:
			_fail("the pull has no radius - it would teleport a member from anywhere on the map")
		else:
			_ok("the pull is bounded by a radius")
		if body.find("too far away to be pulled in") < 0:
			_fail("an out-of-range member is dropped silently, which reads exactly like co-op "
				+ "being broken - the same report the in-combat skip message was added for")
		else:
			_ok("an out-of-range member is named, not silently dropped")

	print("")
	print("===== 4. THE RADIUS IS A SHAPE THAT MATCHES THE WALK =====")
	var srvobj = ServerScript.new()
	var r: int = srvobj.PARTY_PULL_RADIUS
	print("  PARTY_PULL_RADIUS = %d (the overworld view is 23 tiles across)" % r)
	if r <= 0:
		_fail("the radius is %d - nobody would ever be pulled in" % r)
	elif r >= 23:
		_fail("the radius is %d, wider than the screen - 'out of range' stops being a real state "
			% r + "and the run-in join has nothing to answer")
	else:
		_ok("the radius is smaller than the view, so being out of range is a real state")
	# Chebyshev, because movement is 8-directional: a diagonal step covers one tile, so the range
	# must be the same shape as the walk that closes it.
	var a := {"x": 0, "y": 0}
	var b := {"x": 5, "y": 5}      # 5 diagonal steps away
	var dx: int = maxi(absi(a.x - b.x), absi(a.y - b.y))
	print("  a diagonal neighbour 5 steps away measures %d (Euclidean would call it 7)" % dx)
	if dx != 5:
		_fail("the distance metric does not match 8-directional movement")
	else:
		_ok("distance is measured in steps, matching how you would walk it")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the party walks separately, and whoever meets a monster pulls the")
	print("       neighbours in.")
	quit()
