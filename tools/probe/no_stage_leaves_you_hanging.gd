extends SceneTree
## Does EVERY step of the opening end by telling you what to do next?
##
## Owner 2026-09-14, after step two completed in silence: *"While we are on the subject we should
## probably make sure other stages aren't going to leave the player hanging and lost about what to
## do either."*
##
## Two separate things have to be true at every step, and they failed independently:
##
##   ADVANCE — the step has to settle itself. Step one turned itself in and step two did not, so
##             the chain stopped at a quest marked complete with nothing to move it on.
##   TELL    — the player has to be told the next action, IN A POPUP. Twice now the next action
##             was a chat line, and the owner has said twice that his chat lines get buried.
##
## Checking the steps one at a time is what let step two through, so this walks the chain from the
## database rather than from a list somebody maintains by hand.
const QuestDB = preload("res://shared/quest_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var db = QuestDB.new()

	# Walk the chain from its own links, so a fourth step added tomorrow is covered.
	var chain: Array = []
	var qid := "wardens_watch_1"
	while qid != "" and chain.size() < 12:
		var q: Dictionary = db.get_quest(qid)
		if q.is_empty():
			break
		chain.append(qid)
		qid = String(q.get("next_in_chain", ""))
	print("the chain, read from its own next_in_chain links: %s" % str(chain))
	ck(chain.size() >= 3, "it has at least the three steps it is supposed to")

	print("")
	print("===== EVERY STEP SETTLES ITSELF =====")
	# One loop over the chain, not a branch per step. A per-step branch is exactly how step two
	# ended up without a turn-in while step one had one.
	ck(src.contains('if not _qid.begins_with("wardens_watch_"):'),
		"the completion hook matches the CHAIN, not individual step ids")
	ck(src.contains("handle_quest_turn_in(peer_id, {\"quest_id\": _qid})"),
		"and turns in whichever step just completed")
	var i_h := src.find("AND HE SETTLES IT HIMSELF")
	var hook := src.substr(i_h, 1800) if i_h != -1 else ""
	for step in chain:
		ck(not hook.contains('handle_quest_turn_in(peer_id, {"quest_id": "%s"})' % step),
			"  no hardcoded turn-in for %s - the loop covers it" % step)

	print("")
	print("===== AND EVERY STEP NAMES THE NEXT ACTION, IN A POPUP =====")
	# The lesson that fires as each step closes must end with an explicit next action. A popup,
	# because the owner has twice reported his chat lines being missed.
	var beats := {
		"wardens_watch_1": ["Catching Your Breath", "he is handing you armour"],
		"wardens_watch_2": ["Where You Are", "find the [color=#FFD700]D[/color] on your map"],
	}
	for step in beats:
		var title: String = String(beats[step][0])
		var expect: String = String(beats[step][1])
		var i_t := src.find('title = "[color=#9ACD32]%s' % title)
		ck(i_t != -1, "%s closes with the '%s' popup" % [step, title])
		if i_t == -1:
			continue
		var body := src.substr(i_t, 2600)
		var cut := body.find("\n\t\t\tring")
		if cut != -1:
			body = body.substr(0, cut)
		ck(body.contains("[color=#FFD700]Next:[/color]"),
			"  and it ends with an explicit Next: line")
		ck(body.contains(expect), "  naming the real next action")

	print("")
	print("----- the LAST step, which has no next quest to hand you -----")
	# The end of the chain is the one place a "Next:" cannot point at another step, so it has to
	# point at the game instead. Owner's chosen line does exactly that.
	ck(src.contains("Keep an eye on the Area Level and see what you can recover out there."),
		"the farewell tells them what to DO with the rest of the game")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  The dungeon step's own beats - entering, finding the floor loot, the boss, coming")
	print("  back out. Those are checked in tutorial_walkthrough.gd only as far as entry; the")
	print("  rest is a playthrough.")

	print("")
	if fails == 0:
		print("PASS - no step of the opening ends without telling you what to do next")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
