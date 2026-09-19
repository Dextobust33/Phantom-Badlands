extends SceneTree
## ⛑ WHEN A MONSTER RUNS OR CALLS FOR HELP, DOES THE PLAYER GET TOLD?
##
## Owner 2026-09-19: *"if shriekers call for a friend that should show up in the combat log."*
##
## ⚡ THE LINE WAS WRITTEN AND THEN THROWN AWAY. `process_monster_turn` appends the shriek — *"The
## Shrieker's shriek tears the veil, dragging a Tier-N X into the fray!"* plus the warning under
## it — and the server's `monster_fled` branch ended the combat without forwarding `messages`. The
## only text that survived was the generic *"A X answers the call!"*, so the player was told
## something had arrived but never what happened or why. The same gap sat on the COWARD path,
## where a monster runs away and the line explaining it was dropped identically.
##
## ⛑ THIS IS THE SAME DISEASE AS THE CORPSE LOOT, one layer earlier: there, a result was drawn and
## then painted over; here it never left the server. `tools/unreadable_result_audit.py` cannot see
## this one, because the text is lost BEFORE any handler could protect it — which is worth knowing
## about that audit's reach.
##
## WHAT THIS ASSERTS:
##   1. the Shrieker's summon actually produces lines
##   2. the server forwards the round's `messages` on BOTH fled paths
##   3. the client prints them, and into the combat log rather than only the page
##
## Run:
##   godot --headless --path . --script res://tools/probe/a_fleeing_monster_says_why.gd

const CombatManagerScript := preload("res://shared/combat_manager.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	print("")
	print("===== 1. THE SUMMON WRITES SOMETHING TO SAY =====")
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var i := cm.find("ABILITY_SUMMONER in abilities")
	if i < 0:
		_fail("the summoner ability is gone")
	else:
		var body := cm.substr(i, 1600)
		if body.find("shriek tears the veil") < 0:
			_fail("the Shrieker's summon line is gone")
		else:
			_ok("the Shrieker writes a line when it calls something in")
		if body.find("calls for reinforcements") < 0:
			_fail("the ordinary summoner's line is gone")
		else:
			_ok("an ordinary summoner writes one too")
		if body.find("combat[\"monster_fled\"] = true") < 0:
			_fail("the Shrieker no longer flees after summoning - if that is intended, this "
				+ "probe's premise changed and it needs re-pointing")
		else:
			_ok("the Shrieker flees after summoning, which is what ends the combat")

	print("")
	print("===== 2. THE SERVER FORWARDS THE ROUND'S LINES =====")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var j := srv.find("elif result.get(\"monster_fled\", false):")
	if j < 0:
		_fail("the monster_fled branch is gone - re-point this probe")
	else:
		# ⛑ BOUNDED to the branch. A slice running to the next `func ` would sweep in unrelated
		# sends and pass on one of those instead - the too-generous-locator failure this file's
		# siblings hit three times in a week.
		var k := srv.find("\n\t\telse:", j)
		var branch := srv.substr(j, (k - j) if k > j else 3000)
		# Counted, because there are TWO sends here - the Shrieker path and the coward path - and
		# fixing only the reported one would leave the other silently broken.
		var n := 0
		var at := 0
		while true:
			at = branch.find("\"messages\": result.get(\"messages\"", at)
			if at < 0:
				break
			n += 1
			at += 8
		print("  sends in the fled branch that forward `messages`: %d" % n)
		if n < 2:
			_fail("only %d of the two fled paths forwards the round's lines - the other drops "
				% n + "them exactly as the Shrieker's did")
		else:
			_ok("both the summon path and the coward path forward the round's lines")

	print("")
	print("===== 3. THE CLIENT PRINTS THEM, INTO THE LOG =====")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var m := cli.find("elif message.get(\"monster_fled\", false):")
	if m < 0:
		_fail("the client's monster_fled branch is gone")
	else:
		var seg := cli.substr(m, 1400)
		if seg.find("for _fl_msg in message.get(\"messages\"") < 0:
			_fail("the client ignores the forwarded lines - the server sends them and nothing "
				+ "reads them, which looks identical to never sending them")
		else:
			_ok("the client reads the forwarded lines")
		if seg.find("combat_scene_panel.append_log(_fl_text)") < 0:
			_fail("the lines go to the page but NOT to the combat log, which is where the owner "
				+ "asked for them")
		else:
			_ok("they go to the combat log, not only the page")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m2 in _fails:
			print("   - %s" % m2)
		quit(1)
		return
	print("[PROBE] PASS a monster that runs or calls for help says so, and the reason reaches")
	print("       the combat log.")
	quit()
