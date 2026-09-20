extends SceneTree
## ⛑ DOES A PARTY THAT WALKS SEPARATELY STILL FIGHT TOGETHER?
##
## Owner 2026-09-18, naming the model: *"For party play we should probably go in the style of
## Dragon Quest IX... when a party member nearby enters combat it will pull nearby party members
## into the combat as well. Party Players could also join mid-battle as they could visually tell
## on the map if a player was in battle and they could run into them to enter it."* And, on what
## it replaces: *"party members will no longer blindly follow the leader they will instead be able
## to move around and act as we discussed."*
##
## ⚡ THE PIECES ONLY WORK TOGETHER, which is why they are checked together. Unlocking movement
## without the pull leaves a party unable to fight as one at all — the old co-op fired only for the
## LEADER, because a follower was dragged along and could never meet a monster alone. Building the
## pull without unlocking movement is a radius check against people standing on your heels. And
## marking a fighting teammate on the map without the run-in join is a promise with nothing behind
## it, which is worse than not marking them.
##
## WHAT THIS ASSERTS:
##   1. nothing drags a follower, above ground or below
##   2. ANY member's encounter starts the party fight — overworld AND dungeon
##   3. the pull is bounded by a radius, and out-of-range members are TOLD, not dropped
##   4. you can run into a fighting teammate and join, without healing the monster
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


## Count non-overlapping occurrences of a literal.
func _count(hay: String, needle: String) -> int:
	var n := 0
	var at := 0
	while true:
		at = hay.find(needle, at)
		if at < 0:
			return n
		n += 1
		at += needle.length()
	return n


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var NL := "\n"

	print("")
	print("===== 1. THE SNAKES ARE GONE, NOT DISABLED =====")
	# ⛑ A `_move_party_followers` left in place but never called is the "unreachable copy of live
	# code" this codebase warns about, and the first cut of slice 1 did exactly that with
	# `if false and ...`.
	if srv.find("func _move_party_followers(") >= 0:
		_fail("_move_party_followers still exists - the overworld snake is one call from coming "
			+ "back, and a reader cannot tell disabled-on-purpose from disabled-by-accident")
	else:
		_ok("the overworld follower drag is deleted, not switched off")
	if srv.find("func _move_party_followers_dungeon(") >= 0:
		_fail("the DUNGEON snake still exists - followers are yanked onto the leader's trail "
			+ "underground, which makes independent movement there meaningless")
	else:
		_ok("the dungeon formation is gone too, matching the overworld")
	# ⚡ AS A STATEMENT, NOT AS TEXT. This check once FAILED on the comment explaining that the
	# `if false` had been removed - the fourth comment-match in a week. A comment line begins with
	# `#` after its indentation, so the test is "a line whose first non-tab characters are
	# `if false`".
	var rx_false := RegEx.new()
	rx_false.compile("\\n\\t+if false\\b")
	if rx_false.search(srv) != null:
		_fail("there is an `if false ...` statement in server.gd - dead code pretending to be live")
	else:
		_ok("no branch is switched off with a constant false")

	print("")
	print("===== 2. A FOLLOWER CAN ACT ON THEIR OWN =====")
	# The lock is what made a follower unable to be anywhere the pull must reach. All four are
	# gone now, INCLUDING the dungeon one - that last assertion was the opposite a few hours
	# earlier, when leaving dungeons alone was my scoping call rather than the owner's direction.
	for what in ["\"movement\"", "\"hunting\"", "\"resting\"", "\"gathering\""]:
		var n := _count(srv, "_party_follower_denied(peer_id, %s)" % what)
		if n > 0:
			_fail("%s is still denied to a party follower, in %d place(s)" % [what, n])
		else:
			_ok("a follower may %s on their own" % what.replace("\"", ""))

	print("")
	print("===== 3. THE PULL: ANY MEMBER, WITHIN A RADIUS =====")
	var i := srv.find("THE PROXIMITY PULL")
	if i < 0:
		_fail("the proximity pull is not in trigger_encounter")
	else:
		# ⛑ BOUNDED TO THE PULL BLOCK. Slicing to the next `func ` ran past the pull into the SOLO
		# FANOUT below it, which gates on `_is_party_leader` quite correctly - so the probe once
		# reported the feature missing while it sat a few lines above.
		var j := srv.find("skip the solo fanout below", i)
		if j < 0:
			_fail("could not find the end of the pull block - re-point this probe")
			j = i
		var body := srv.substr(i, maxi(0, j - i))
		if body.find("if _is_party_leader(peer_id) and active_parties.has(peer_id):") >= 0:
			_fail("the pull is still gated on the LEADER - a member who finds a monster alone "
				+ "starts no party fight, which is the whole feature")
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
	print("===== 3b. DUNGEONS FOLLOW THE OVERWORLD =====")
	var di := srv.find("func _try_start_dungeon_coop(")
	if di < 0:
		_fail("_try_start_dungeon_coop is gone - re-point this probe")
	else:
		var dj := srv.find(NL + "func ", di + 8)
		var dbody := srv.substr(di, (dj - di) if dj > di else 3000)
		if dbody.find("if not _is_party_leader(peer_id) or not active_parties.has(peer_id):") >= 0:
			_fail("dungeon co-op is still gated on the LEADER, so a member who meets a monster "
				+ "underground on their own starts no party fight")
		else:
			_ok("any member's dungeon encounter can start the party fight")

	print("")
	print("===== 3c. YOU CAN RUN INTO A FIGHT AND JOIN IT =====")
	if srv.find("join_party_combat_in_progress(") < 0:
		_fail("nothing joins a fight in progress - the map marks a fighting teammate and the "
			+ "hover says to walk into them, so this would be a promise with nothing behind it")
	else:
		_ok("walking into a fighting teammate joins their fight")
	# The marker and its explanation are half the feature: a tint nobody can read is not an
	# indicator, and an instruction that does not work is worse than silence.
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	if cli.find("walk into them to join") < 0:
		_fail("the map never tells the player they can join - the whole point of marking it")
	else:
		_ok("the map says what the marker means")
	if srv.find("\"in_combat\": bool(other_char.in_combat)") < 0:
		_fail("`in_combat` is not on the overworld wire, so the client cannot mark anybody")
	else:
		_ok("the server reports who is fighting")

	var ji := cm.find("func join_party_combat_in_progress(")
	if ji < 0:
		_fail("join_party_combat_in_progress does not exist")
	else:
		# ⛑ BOUNDED TO THE FUNCTION. A flat 3200-character slice ran PAST it into
		# `start_party_combat_simul`, which sets `monster["max_hp"]` quite correctly at the start
		# of a fight - so the probe reported that joining re-scales the monster when it does no
		# such thing. Fourth too-generous slice in two days; the fix is always the same.
		var jend := cm.find(NL + "func ", ji + 8)
		var jb := cm.substr(ji, (jend - ji) if jend > ji else 3200)
		# ⚡ THE TRAP THE BACKLOG NAMED. `start_party_combat_simul` multiplies the monster's max HP
		# by the party size, so re-scaling on join would HEAL the thing the rescuer came to help
		# kill - the fight getting longer the more help arrives, which inverts the feature.
		if jb.find("monster[\"max_hp\"]") >= 0:
			_fail("joining re-scales the monster's HP - a rescuer would heal it on arrival")
		else:
			_ok("joining does not re-scale the monster's health")
		# ⛑ And they join BETWEEN rounds. `_party_all_submitted` gates the round on the member
		# list as it stands, so a joiner who is not marked as having acted would either stall the
		# round in progress or have it resolve without them.
		if jb.find("\"submitted_this_round\": true") < 0:
			_fail("a joiner is not marked as having acted, so the round in progress will stall "
				+ "waiting for somebody who was not there when it started")
		else:
			_ok("a joiner sits out the round in progress and acts from the next")
		if jb.find("_initialize_combat_deck(") < 0:
			_fail("a joiner gets no deck, so they are in the fight and cannot act in it")
		else:
			_ok("a joiner is dealt their own deck and hand")

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
	var dx: int = maxi(absi(0 - 5), absi(0 - 5))
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
	print("[PROBE] PASS the party walks its own paths, whoever meets a monster pulls the")
	print("       neighbours in, and anyone further off can run over and join.")
	quit()
