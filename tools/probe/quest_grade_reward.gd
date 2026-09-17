extends SceneTree
## ⛑ DOES A HARDER DUNGEON PAY MORE FOR THE SAME QUEST?
##
## Owner 2026-09-17: *"Yes, grade multiplies the payout."* Task and depth shipped earlier the same
## day; grade was the third axis of *"rewards should scale with the dungeons difficulty as well as
## the difficulty of the task you have to do in the dungeon"*, and the quest reward ignored it.
##
## ⛑ THE HARD PART IS NOT THE MULTIPLIER, IT IS THAT THE BOARD CANNOT KNOW IT. A quest names a
## dungeon TYPE; a dungeon's grade belongs to the INSTANCE. So the same Goblin Caves quest can be
## settled in an H1 or an A6 and the grade is only known when the run ends. That is why the
## multiplier can only ADD — a turn-in figure lower than the advertised one would be the entrance
## screen's old fault with the sign flipped (*"We don't need the overworld advertising F something
## and end up in a C dungeon."*).
##
## Run:
##   godot --headless --path . --script res://tools/probe/quest_grade_reward.gd

const QDB := preload("res://shared/quest_database.gd")
const PR := preload("res://shared/power_rank.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== 1. THE LADDER IS MONOTONIC AND NEVER PAYS LESS =====")
	var last := 0.0
	var breaks := 0
	var below := 0
	for t in range(1, 10):
		for r in range(1, PR.RANKS + 1):
			var m: float = QDB.quest_grade_mult(t, r)
			if m < last - 0.0001:
				breaks += 1
				print("           NOT MONOTONIC at %s: %.3f after %.3f" % [PR.label(t, r), m, last])
			if m < 1.0:
				below += 1
			last = m
	print("           H1 %.2fx  D5 %.2fx  A9 %.2fx  S9 %.2fx" % [
		QDB.quest_grade_mult(1, 1), QDB.quest_grade_mult(5, 5),
		QDB.quest_grade_mult(8, 9), QDB.quest_grade_mult(9, 9)])
	ck(breaks == 0, "every step up the ladder pays at least as much (%d breaks)" % breaks)
	# ⛑ THE CHECK THAT PROTECTS THE ADVERTISED NUMBER. If any grade multiplied below 1.0, the
	# board would be promising more than the turn-in pays, for a reason the player cannot see
	# when they accept.
	ck(below == 0, "and no grade EVER pays below the board's figure (%d would)" % below)
	ck(absf(QDB.quest_grade_mult(1, 1) - 1.0) < 0.001,
		"the weakest dungeon pays exactly the advertised amount (the floor is real)")
	ck(QDB.quest_grade_mult(9, 9) <= QDB.QUEST_GRADE_MAX + 0.001,
		"and the best is capped at the ceiling the card quotes (%.2fx)" % QDB.quest_grade_mult(9, 9))

	print("\n===== 2. IT IS WORTH NOTICING, AND NOT WORTH GAMING =====")
	var span: float = QDB.quest_grade_mult(9, 9) / QDB.quest_grade_mult(1, 1)
	var one_letter: float = QDB.quest_grade_mult(5, 5) / QDB.quest_grade_mult(4, 5)
	print("           whole ladder %.2fx, one letter %+.1f%%" % [span, (one_letter - 1.0) * 100.0])
	ck(span > 1.25, "a player can feel the whole climb (%.2fx)" % span)
	ck(span < 2.0, "but grade does not swamp the task and depth multipliers (%.2fx)" % span)
	ck(one_letter > 1.02 and one_letter < 1.15,
		"and one letter is a nudge, not a reason to ignore your own level (%+.1f%%)" % ((one_letter - 1.0) * 100.0))

	print("\n===== 3. AN UNKNOWN GRADE IS NEUTRAL =====")
	# Every quest that is not settled by clearing a dungeon, and every quest accepted before
	# today, has no grade stamped. That must be 1.0 and not 0, or the fix would zero the payout
	# of every legacy quest in the game - which is the exact shape of the bug it is fixing.
	ck(absf(QDB.quest_grade_mult(0, 0) - 1.0) < 0.001, "no grade recorded -> 1.0x, not 0")
	ck(absf(QDB.quest_grade_mult(0, 5) - 1.0) < 0.001, "half a grade recorded -> 1.0x")
	ck(absf(QDB.quest_grade_mult(5, 0) - 1.0) < 0.001, "  the other half too")
	# Out of range must clamp rather than run away - `sub_tier` domains differ between dungeons
	# (1-8) and companions (1-9), which power_rank.gd documents as a live trap.
	ck(QDB.quest_grade_mult(99, 99) <= QDB.QUEST_GRADE_MAX + 0.001, "an absurd grade clamps")

	print("\n===== 4. THE WIRING IS THERE AND THE MESSAGE NAMES THE RIGHT CAUSE =====")
	var qm := FileAccess.get_file_as_string("res://shared/quest_manager.gd")
	ck(qm.contains("cleared_tier: int = 0, cleared_rank: int = 0"),
		"check_dungeon_progress accepts the grade of the run that settled the quest")
	ck(qm.contains('quest_data["cleared_grade_tier"] = cleared_tier'), "and records it")
	ck(qm.contains("quest_grade_mult("), "and the payout applies it")
	# ⛑ The hotzone line announced ANY multiplier above 1.0 as a "hotzone bonus", so a dungeon
	# clear in an A6 would have told the player about a mechanic that was not involved. A message
	# naming the wrong cause teaches a mechanic that does not exist.
	ck(qm.contains("dungeon: +%d%% pay"), "the turn-in attributes the grade bonus to the grade")
	ck(qm.contains("var _other: float = float(rewards.get(\"multiplier\", 1.0)) / maxf(0.0001, _gm)"),
		"and the hotzone line reports only what the hotzone did")
	# Both server completion sites must pass it, or a party follower's clear pays the base rate.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var calls := 0
	var bare := 0
	for line in srv.split("\n"):
		if "check_dungeon_progress(" in line:
			calls += 1
			if "int(tier)" not in line:
				bare += 1
				print("           NO GRADE PASSED: " + line.strip_edges().substr(0, 110))
	print("           %d completion sites, %d without a grade" % [calls, bare])
	ck(calls >= 2 and bare == 0, "every dungeon-completion site hands the grade over")
	# And the CARD must quote the same ceiling the server enforces.
	var card := FileAccess.get_file_as_string("res://client/quest_board_panel.gd")
	ck(card.contains("QuestDatabaseScript.QUEST_GRADE_MAX"),
		"the card reads the ceiling off the server's constant, not a copy of the number")

	print("\n===== NOT COVERED HERE =====")
	print("  What a real board pays END TO END. Task, depth, distance, level and now grade all")
	print("  multiply, and nothing has measured the product on a live board since the distance")
	print("  fix moved one from 4,505 to 773,027 XP. That wants a live turn-in, not a probe.")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
