extends SceneTree
## Can a player change their mind in a party fight, and is the window the fair one?
##
## Owner 2026-09-14: *"I don't like the way Party lock in works currently. I think we should have
## a cancel button or something different, players shouldn't have to confirm all of their actions,
## they should just have a way to pick something different if they change their mind while their
## party members are still deciding on their actions."*
##
## Two things to hold: it must WORK while others are choosing, and it must STOP the moment the
## round is complete - otherwise someone could watch the round land and then rewrite their move.
const CM = preload("res://shared/combat_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _mk(cm, members: Array) -> void:
	var ms := {}
	for pid in members:
		ms[pid] = {"submitted_this_round": false, "queued_action": {}, "dead": false, "fled": false}
	cm.active_party_combats[1] = {"members": members, "member_states": ms}


func _init() -> void:
	var cm = CM.new()
	get_root().add_child(cm)

	print("===== YOU CAN TAKE IT BACK WHILE SOMEONE IS STILL CHOOSING =====")
	_mk(cm, [1, 2, 3])
	ck(cm.submit_party_action(1, 1, {"kind": "ability", "name": "shield"}).get("ok", false),
		"player 1 picks a shield")
	ck(not cm.submit_party_action(1, 1, {"kind": "attack"}).get("ok", false),
		"  and cannot simply submit a second time (that is why an UNDO is needed)")
	var w = cm.withdraw_party_action(1, 1)
	ck(w.get("ok", false), "but CAN withdraw while 2 and 3 are still deciding")
	ck(not cm.active_party_combats[1]["member_states"][1].get("submitted_this_round", true),
		"  and is genuinely un-submitted afterwards")
	ck(cm.active_party_combats[1]["member_states"][1].get("queued_action", {}).is_empty(),
		"  with the queued action cleared, not left lying around")
	ck(cm.submit_party_action(1, 1, {"kind": "attack"}).get("ok", false),
		"  so they can pick something else")

	print("")
	print("===== AND NOT ONCE THE ROUND IS COMPLETE =====")
	# The fairness rule. If the last member's submit resolves the round, an undo after that would
	# let someone rewrite their move knowing what everyone else did.
	_mk(cm, [1, 2])
	cm.submit_party_action(1, 1, {"kind": "attack"})
	ck(cm.withdraw_party_action(1, 1).get("ok", false),
		"one of two has picked - still changeable")
	cm.submit_party_action(1, 1, {"kind": "attack"})
	var r2 = cm.submit_party_action(1, 2, {"kind": "attack"})
	ck(r2.get("all_submitted", false), "the second member completes the round")
	var late = cm.withdraw_party_action(1, 1)
	ck(not late.get("ok", true),
		"and NOW it is refused - '%s'" % String(late.get("reason", "")))

	print("")
	print("----- the dull guards -----")
	_mk(cm, [1, 2])
	ck(not cm.withdraw_party_action(1, 1).get("ok", true),
		"withdrawing before choosing anything is refused")
	ck(not cm.withdraw_party_action(1, 99).get("ok", true), "a stranger is refused")
	ck(not cm.withdraw_party_action(77, 1).get("ok", true), "an unknown fight is refused")
	cm.active_party_combats[1]["member_states"][1]["dead"] = true
	cm.active_party_combats[1]["member_states"][1]["submitted_this_round"] = true
	ck(not cm.withdraw_party_action(1, 1).get("ok", true), "a dead member is refused")

	print("")
	print("===== AND THE CONFIRM STATE IS GONE FROM THE CLIENT =====")
	# The state itself was the bug: monster_select_mode and ability_mode both sit above it in
	# update_action_bar, so any card that asks WHO to aim at reached a confirm row that could
	# never be drawn. Moving the branch fixed one shadow; removing the state retires the class.
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	ck(not src.contains("elif party_confirm_pending:"),
		"no action-bar branch depends on a confirm state any more")
	ck(src.contains("elif party_round_submitted and party_combat_active:"),
		"the bar instead offers to CHANGE what you already sent")
	ck(src.contains('"party_action_withdrawn"'), "and the client re-opens the hand when it lands")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether 'Change action' is findable mid-fight. That is a look, and looks are a")
	print("  playtest.")

	print("")
	if fails == 0:
		print("PASS - you can change your mind, right up until the round is everyone's")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
