extends SceneTree
## The admin jump: does it really put you one kill from the end of step two?
##
## Owner 2026-09-14: *"setup a test scenario too where we are about to kill the third enemy in
## step 2. You're exhausting me with all these failures and having to repeat the same steps."*
##
## Fair, and the reason is measurable: every fix to the back half of Warden's Watch has cost a
## full replay of the front half to reach, and most of those replays found nothing because the
## bug was further on.
##
## ⛑ A SHORTCUT IS ONLY WORTH HAVING IF IT LANDS ON THE REAL STATE. A jump that sets the quest
## counter but not, say, `met_warden` would leave the tester in a state no player can occupy -
## and then the thing they went to test would fail for a reason that does not exist in the game.
## So this boots the REAL server and, after jumping, drives the REAL kill-credit path: one kill
## must finish step two and hand over step three, exactly as the third fight does in play.
const ServerScript = preload("res://server/server.gd")

var fails := 0
var sv = null
const PEER := 1

func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _stage2(ch) -> Dictionary:
	for q in ch.active_quests:
		if String(q.get("quest_id", q.get("id", ""))) == "wardens_watch_2":
			return q
	return {}


func _init() -> void:
	sv = ServerScript.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)

	var uname := "jumpacct"
	var _u: int = Time.get_ticks_usec() % 456976
	for _i in range(4):
		uname += char(97 + (_u % 26))
		_u /= 26
	var made: Dictionary = sv.persistence.create_account(uname, "probe-password")
	var acct := String(made.get("account_id", ""))
	sv.peers[PEER] = {"authenticated": true, "account_id": acct, "character_name": "",
		"connection": StreamPeerTCP.new()}

	var nm := "Jump"
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

	print("===== IT IS GATED, LIKE EVERY OTHER ADMIN CONTROL =====")
	# Worth one check: a scenario jump in a player's hands is a quest-completion button.
	sv.peers[PEER]["is_admin"] = false
	sv.handle_gm_tutorial_jump(PEER, {"to": "step2_last"})
	await process_frame
	ck(not ch.met_warden, "a non-admin press changes nothing at all")

	sv.peers[PEER]["is_admin"] = true

	print("")
	print("===== THE JUMP LANDS ON A STATE A PLAYER COULD BE IN =====")
	sv.handle_gm_tutorial_jump(PEER, {"to": "step2_last"})
	await process_frame
	ck(ch.met_warden, "they have met the Warden - so he escorts them, as he would by now")
	ck(sv._guide_escorts_overworld(PEER, ch), "and he is actually following")
	ck(ch.completed_quests.has("wardens_watch_1"), "step one is behind them")
	var q2: Dictionary = _stage2(ch)
	ck(not q2.is_empty(), "step two is the active quest")
	if q2.is_empty():
		_finish(); return
	var target := int(q2.get("target", 0))
	print("  step two stands at %d/%d" % [int(q2.get("progress", 0)), target])
	ck(target >= 1, "  it has a real target")
	ck(int(q2.get("progress", 0)) == target - 1, "  and they are ONE kill from finishing")

	print("")
	print("----- armed the way the Warden arms them -----")
	# Not decoration: taking that fight barehanded is a different fight, and the tester would be
	# measuring a difficulty no real player meets at this point.
	ck(ch.equipped.get("weapon", null) != null, "a weapon is equipped")
	ck(ch.equipped.get("armor", null) != null, "and armour")
	ck(ch.current_hp == ch.get_total_max_hp(),
		"at full health (%d/%d) - not carrying damage from a previous scenario"
			% [ch.current_hp, ch.get_total_max_hp()])

	print("")
	print("----- and the lessons will fire again -----")
	# Second run of a scenario going silent is indistinguishable from the pop-up being broken.
	ck(not ch.seen_guide_world_hint, "the world lesson is unseen again")

	print("")
	print("===== ONE KILL FINISHES IT - DRIVEN THROUGH THE REAL PATH =====")
	# `check_kill_quest_progress` is what a won fight calls. Setting the counter and declaring
	# victory would prove nothing: the whole point of the scenario is the code that runs NEXT.
	sv.check_kill_quest_progress(PEER, maxi(1, ch.level), "Goblin")
	await process_frame
	await process_frame
	ck(ch.completed_quests.has("wardens_watch_2"),
		"step two completed on that single kill")
	var on3 := false
	for q in ch.active_quests:
		if String(q.get("quest_id", q.get("id", ""))) == "wardens_watch_3":
			on3 = true
	ck(on3, "and step three - the dungeon - was handed over")

	print("")
	print("===== THE OTHER BEAT: STRAIGHT TO THE WALK =====")
	sv.handle_gm_tutorial_jump(PEER, {"to": "step3"})
	await process_frame
	var on3b := false
	for q in ch.active_quests:
		if String(q.get("quest_id", q.get("id", ""))) == "wardens_watch_3":
			on3b = true
	ck(on3b, "step three is active")
	ck(ch.completed_quests.has("wardens_watch_2"), "with step two behind them")
	ck(not sv._escort_released.has(PEER),
		"and the escort is un-released, so he takes the lead rather than waiting to be nudged")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether the fight that finishes step two is winnable, and whether the walk to the")
	print("  dungeon LOOKS right. Those are the judgements the scenario exists to let you make.")
	_finish()


func _finish() -> void:
	print("")
	if fails == 0:
		print("PASS - the jump lands on a real state, and one kill carries it forward")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
