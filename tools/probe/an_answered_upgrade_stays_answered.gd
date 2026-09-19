extends SceneTree
## ⛑ CAN THE SAME MILESTONE UPGRADE BE OFFERED TWICE?
##
## Owner, live 2026-09-19: *"I had the upgrade for my Assassinate show up twice and I had to pick
## twice for it (I chose Foretold both times)."*
##
## ⚡ THE REPLAY WAS READING A QUEUE THE CLIENT NEVER UPDATES. `character_data.pending_rank_choices`
## is the SERVER'S queue, refreshed only when the next `character_update` arrives. Answering a
## choice sends `rank_choice_response` and clears `_rank_choice_pending_ability`, but left that
## cached queue untouched — so the entry just resolved was still at the head of it. Then
## `acknowledge_continue` fires `_replay_pending_rank_choice()` on the Continue press, which
## presents `queue[0]` with no test for whether it was answered, and the same milestone came back.
##
## ⛑ THE REPLAY EXISTS FOR A REAL REASON and must not simply be removed: it is what surfaces a
## choice earned mid-fight that the victory card covered, and a choice queued when a player
## disconnected. Before it, those sat unusable until reconnect. So the fix is at the other end —
## an answered entry leaves the client's copy of the queue.
##
## WHAT THIS ASSERTS:
##   1. both response paths consume the local entry (there are TWO, and fixing one is not a fix)
##   2. the consume matches by ability and removes exactly one
##   3. the replay itself still exists, so the case it was written for is not regressed
##
## Run:
##   godot --headless --path . --script res://tools/probe/an_answered_upgrade_stays_answered.gd

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("")
	print("===== 1. BOTH WAYS OF ANSWERING CONSUME THE ENTRY =====")
	# ⛑ There are two: the milestone overlay (`_send_milestone_choice`) and the older popup
	# (`_on_rank_choice_picked`). They send the same message by different routes, so a fix applied
	# to one leaves the other able to reproduce the bug exactly.
	for fname in ["_send_milestone_choice", "_on_rank_choice_picked"]:
		var i := cli.find("func %s(" % fname)
		if i < 0:
			_fail("%s is gone - re-point this probe" % fname)
			continue
		var j := cli.find("\nfunc ", i + 8)
		var body := cli.substr(i, (j - i) if j > i else 2000)
		if body.find("send_to_server(") < 0:
			_fail("%s no longer sends a response - re-point this probe" % fname)
			continue
		# Matched as a CALL, not as a mention: a comment naming the helper would otherwise pass.
		if body.find("_consume_local_rank_choice(") < 0:
			_fail("%s answers the choice but leaves it in the client's queue - pressing Continue "
				% fname + "replays it and the player picks the same upgrade twice")
		else:
			_ok("%s removes the answered choice from the local queue" % fname)

	print("")
	print("===== 2. THE CONSUME REMOVES ONE ENTRY, BY ABILITY =====")
	var k := cli.find("func _consume_local_rank_choice(")
	if k < 0:
		_fail("_consume_local_rank_choice does not exist")
	else:
		var j2 := cli.find("\nfunc ", k + 8)
		var body2 := cli.substr(k, (j2 - k) if j2 > k else 1600)
		if body2.find("pending_rank_choices") < 0:
			_fail("it does not touch pending_rank_choices, which is the queue the replay reads")
		else:
			_ok("it edits the queue the replay reads")
		if body2.find("remove_at(") < 0:
			_fail("it never removes anything")
		else:
			_ok("it removes the entry")
		# ⚡ ONE, not all. A character can legitimately owe SEVERAL milestones at once - the
		# server queues one entry per owed milestone - so clearing the whole queue would swallow
		# upgrades the player has earned and never answered.
		if body2.find("queue.clear()") >= 0:
			_fail("it clears the WHOLE queue - a character can owe several milestones at once, "
				+ "and the rest would be silently thrown away")
		else:
			_ok("it removes one entry, not the queue")
		if body2.find("return") < 0:
			_fail("it does not stop after the first match, so two owed milestones for the same "
				+ "ability would both be dropped by one answer")
		else:
			_ok("it stops at the first match")

	print("")
	print("===== 3. THE REPLAY IS STILL THERE =====")
	# The bug is the replay firing on an ANSWERED choice, not the replay existing. Deleting it
	# would re-break the two cases it was written for: a milestone earned by the killing blow
	# (the victory card covers the popup), and one queued across a disconnect.
	if cli.find("func _replay_pending_rank_choice(") < 0:
		_fail("the replay was removed - a milestone earned by the killing blow, or queued across "
			+ "a disconnect, is unreachable again")
	else:
		_ok("the replay still exists for the cases it was written for")
	if cli.find("call_deferred(\"_replay_pending_rank_choice\")") < 0:
		_fail("nothing calls the replay after a fight any more")
	else:
		_ok("it still runs after a fight")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS an upgrade you have answered is not offered again, and the replay still")
	print("       covers the cases it was written for.")
	quit()
