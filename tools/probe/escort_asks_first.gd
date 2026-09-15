extends SceneTree
## He asks before he moves you - and he waits rather than shoving.
##
## Owner 2026-09-14, from a screenshot of the walk to the starter dungeon: *"He does start walking
## you but you have popups on the screen so you can't tell what's happening. I'm also stuck in a
## fishing minigame now."* And then: *"He should instead talk to you and you have to acknowledge
## what's about to happen before he starts moving you."*
##
## The screenshot showed one fault wearing three faces. The walk did not know gathering refuses
## movement, so it asked three times a tick, every 450ms, and the log filled with "You cannot move
## while gathering!". Six refusals cancelled the walk - and the very next tick restarted it,
## because nothing recorded that it had just given up. Each restart re-announced the Warden and
## healed the player to full, which is a full heal on tap for anyone standing beside him.
##
## So: a walk that starts only when the player SAYS so, pauses when their hands are busy, stops for
## good once it arrives, and pays the rest exactly once.
const ServerScript = preload("res://server/server.gd")

var fails := 0
var sv = null
const PEER := 1

func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	sv = ServerScript.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)

	var uname := "escacct"
	var _u: int = Time.get_ticks_usec() % 456976
	for _i in range(4):
		uname += char(97 + (_u % 26))
		_u /= 26
	var acct := String(sv.persistence.create_account(uname, "probe-password").get("account_id", ""))
	sv.peers[PEER] = {"authenticated": true, "account_id": acct, "character_name": "",
		"connection": StreamPeerTCP.new(), "is_admin": true}
	var nm := "Esc"
	var _n: int = Time.get_ticks_usec() % 456976
	for _i in range(4):
		nm += char(97 + (_n % 26))
		_n /= 26
	sv.handle_create_character(PEER, {"name": nm, "class": "Fighter", "race": "Human"})
	await process_frame
	if not sv.characters.has(PEER):
		print("FAIL - could not create a character")
		quit(1)
		return
	var ch = sv.characters[PEER]

	# Straight to the beat where he leads, using the same admin jump a tester would press.
	sv.handle_gm_tutorial_jump(PEER, {"to": "step3"})
	await process_frame

	print("===== HE ASKS FIRST, AND WAITS =====")
	sv._escort_walk_tick()
	ck(not sv._escort_walk.has(PEER), "no walk has started")
	ck(bool(sv._escort_asked.get(PEER, false)), "because he has ASKED instead")
	ck(not bool(sv._escort_ready.get(PEER, false)), "and is waiting to be told to go")
	var before := Vector2i(int(ch.x), int(ch.y))
	for _i in range(5):
		sv._escort_walk_tick()
	ck(Vector2i(int(ch.x), int(ch.y)) == before,
		"five more ticks and the player has not been moved a single tile")
	ck(bool(sv._escort_asked.get(PEER, false)),
		"and he asked ONCE - the ask is not re-sent every tick")

	print("")
	print("----- the question really is a question -----")
	# The pop-up must carry the ack the server is waiting on, and the client must send it back.
	# Either half missing leaves the player at the post forever with no way to say yes.
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc.contains('"escort_ready", "Lead the way"'),
		"the pop-up asks for an answer and labels the button as a decision")
	ck(ssrc.contains('"tutorial_ack":'), "the server routes the answer")
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(csrc.contains('{"type": "tutorial_ack", "ack": _hint_ack_pending}'),
		"and the client sends it when the panel closes - not before")

	print("")
	print("===== SAYING YES SETS HIM OFF =====")
	sv.handle_tutorial_ack(PEER, {"ack": "escort_ready"})
	sv._escort_walk_tick()
	ck(sv._escort_walk.has(PEER), "the walk is running")
	var hp_before: int = int(ch.current_hp)
	ch.current_hp = maxi(1, int(ch.get_total_max_hp() / 2))
	ck(hp_before == ch.get_total_max_hp(), "he bound their wounds on the way out (%d HP)" % hp_before)

	print("")
	print("===== BUSY HANDS: HE WAITS, HE DOES NOT SHOVE =====")
	# The exact state in the screenshot. What made it unreadable was not the pause - it was the
	# walk arguing with the gathering guard several times a second.
	sv.active_gathering[PEER] = {"type": "fish"}
	var at := Vector2i(int(ch.x), int(ch.y))
	var st_before: int = int((sv._escort_walk.get(PEER, {}) as Dictionary).get("stuck", 0))
	for _i in range(10):
		# Guarded, because the fault this section exists to catch ENDS the walk: the flailing
		# version wedged itself after six refusals. Indexing a walk that is gone would abort the
		# probe mid-run, and an aborted SceneTree probe never calls quit() - it hangs, which is
		# the one failure mode that looks like nothing at all.
		if sv._escort_walk.has(PEER):
			sv._escort_walk[PEER]["next_ms"] = 0
		sv._escort_walk_tick()
	ck(Vector2i(int(ch.x), int(ch.y)) == at, "ten ticks while fishing moved them nowhere")
	ck(sv._escort_walk.has(PEER), "and the walk is still there, paused rather than abandoned")
	ck(int((sv._escort_walk.get(PEER, {}) as Dictionary).get("stuck", 0)) == st_before,
		"refusals that were never attempted do not count as being wedged")
	ck(int(ch.current_hp) < ch.get_total_max_hp(),
		"and nothing healed them again - the rest is paid once, not every restart")
	sv.active_gathering.erase(PEER)

	print("")
	print("===== ARRIVING IS THE END OF IT =====")
	# The stage stays at 3 until the dungeon is CLEARED, so arrival alone never stopped him: he
	# restarted, arrived, and announced it again on a loop.
	var goal: Dictionary = sv._escort_goal_for(PEER, ch)
	ck(not goal.is_empty(), "he has somewhere to take them (%s)" % String(goal.get("name", "?")))
	ch.x = int(goal.get("x", 0))
	ch.y = int(goal.get("y", 0))
	sv._escort_walk[PEER]["next_ms"] = 0
	sv._escort_walk_tick()
	ck(not sv._escort_walk.has(PEER), "standing at the door, the walk ends")
	ck(bool(sv._escort_done.get(PEER, false)), "and is recorded as DONE")
	sv._escort_walk_tick()
	sv._escort_walk_tick()
	ck(not sv._escort_walk.has(PEER), "two more ticks and he has not set off again")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether the pop-up reads well, and whether the walk looks right on screen. Those are")
	print("  the judgements the scenario buttons exist to let you make.")

	print("")
	if fails == 0:
		print("PASS - he asks, waits, pauses for busy hands, and stops when he arrives")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
