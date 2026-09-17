extends SceneTree
## ⛑ IS A QUEST PAID FOR WHAT IT ASKS?
##
## Owner 2026-09-17: *"rewards should scale with the dungeons difficulty as well as the difficulty
## of the task you have to do in the dungeon."*
##
## Before this the reward was driven by the POST's distance, the player's level, and `index` - the
## quest's SLOT on the board. Task scaling existed as three ad-hoc multipliers, and they priced
## CLEARING A WHOLE DUNGEON AND ITS BOSS exactly the same as reaching an NPC on an early floor.
## Depth was worth nothing at all: a nine-floor dungeon and a three-floor one paid the same.
##
## The board is RNG-seeded per post and per day, so a single board cannot be compared against
## another. This SAMPLES many posts, groups the quests by type, and compares the means - which is
## the only honest way to read a seeded generator.
##
## Run:
##   godot --headless --path . --script res://tools/probe/quest_reward_by_difficulty.gd

const QDB := preload("res://shared/quest_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _type_name(t: int) -> String:
	match t:
		QDB.QuestType.DUNGEON_CLEAR: return "CLEAR"
		QDB.QuestType.BOSS_HUNT: return "BOSS_HUNT"
		QDB.QuestType.RESCUE: return "RESCUE"
		QDB.QuestType.GATHER: return "GATHER"
	return "other(%d)" % t


func _init() -> void:
	var qdb = QDB.new()

	print("===== 1. THE DEPTH MULTIPLIER, DIRECTLY =====")
	# Normalised around five floors on purpose: this REDISTRIBUTES rather than inflates, so the
	# median dungeon must come out unchanged.
	var m1: float = QDB.quest_depth_mult(1)
	var m5: float = QDB.quest_depth_mult(QDB.QUEST_DEPTH_PIVOT)
	var m9: float = QDB.quest_depth_mult(9)
	print("           1 floor %.2fx | 5 floors %.2fx | 9 floors %.2fx" % [m1, m5, m9])
	ck(absf(m5 - 1.0) < 0.001, "a median-depth dungeon is unchanged (%.2fx)" % m5)
	ck(m9 > m5 and m5 > m1, "deeper pays more, shallower pays less")
	ck(m9 <= QDB.QUEST_DEPTH_CLAMP.y and m1 >= QDB.QUEST_DEPTH_CLAMP.x,
		"and it is clamped, so an absurd floor count cannot run away")

	print("\n===== 2. THE TASK TABLE IS ORDERED BY WHAT IT COSTS YOU =====")
	var tr: Dictionary = QDB.QUEST_TASK_REWARD
	var clear_xp: float = float(tr[QDB.QuestType.DUNGEON_CLEAR]["xp"])
	var boss_xp: float = float(tr[QDB.QuestType.BOSS_HUNT]["xp"])
	var resc_xp: float = float(tr[QDB.QuestType.RESCUE]["xp"])
	var gath_xp: float = float(tr[QDB.QuestType.GATHER]["xp"])
	print("           BOSS %.1f > CLEAR %.1f > RESCUE %.1f > GATHER %.1f" % [
		boss_xp, clear_xp, resc_xp, gath_xp])
	# ⛑ THIS ORDER WAS WRONG FIRST TIME. CLEAR was priced above BOSS_HUNT on the assumption
	# that "clear" meant clearing every floor. It does not: a dungeon completes when the BOSS
	# dies, the floors are never required to be emptied, and both tasks are the same descent.
	# The fabled boss then carries 1.5x HP, 1.25x attack and 1.1x level, so BOSS_HUNT is
	# strictly harder - and the probe asserted the wrong ordering happily, because a test
	# written from the same wrong premise agrees with it.
	ck(boss_xp > clear_xp, "a buffed boss beats the same descent against an ordinary one")
	ck(clear_xp > resc_xp, "a full descent beats a partial one")
	ck(resc_xp > gath_xp, "a partial descent beats picking things up on the way")
	# The old code paid CLEAR and RESCUE identically at 2.0x. What matters is that the
	# EQUALITY is gone - not that the gap clears some arbitrary size, which is what the first
	# version of this check demanded (>0.2) and then failed on a gap of exactly 0.2.
	ck(absf(clear_xp - resc_xp) > 0.05,
		"CLEAR and RESCUE are no longer priced the same (both were 2.0x)")
	# Every live board type must be in the table, or it silently pays 1.0x.
	for t in QDB.DYNAMIC_QUEST_TYPES:
		ck(tr.has(t), "%s has a task price" % _type_name(t))

	print("\n===== 3. SAMPLED ACROSS REAL BOARDS =====")
	# Registered coordinates, so the boards are not all sitting at the origin - see
	# `quest_board_scales_by_post.gd` for why that mattered.
	var coords := {}
	for i in range(24):
		coords["npc_probe_%d" % i] = Vector2i(20 + i * 6, -8 + i * 3)
	QDB.register_post_coords(coords)

	var xp_by_type := {}
	var n_by_type := {}
	for i in range(24):
		var board: Array = qdb.generate_dynamic_quests("npc_probe_%d" % i, [], [], 30, 0, {}, "Probe%d" % i)
		for q in board:
			var t: int = int(q.get("type", -1))
			var xp: int = int(q.get("rewards", {}).get("xp", 0))
			xp_by_type[t] = int(xp_by_type.get(t, 0)) + xp
			n_by_type[t] = int(n_by_type.get(t, 0)) + 1
	var seen := 0
	for t in xp_by_type.keys():
		var n: int = int(n_by_type[t])
		print("           %-10s %3d quests, mean %d xp" % [_type_name(t), n, int(xp_by_type[t] / maxi(1, n))])
		seen += 1
	ck(seen >= 3, "the sample covered at least three quest types (%d)" % seen)
	# Not asserting an ordering on the MEANS: the board mixes depths and slots, and a GATHER in
	# a nine-floor dungeon can out-pay a CLEAR in a three-floor one - which is the point. The
	# ordering claims belong to the table, checked above, where nothing else is varying.

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
