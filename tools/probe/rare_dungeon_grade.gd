extends SceneTree
## ⛑ A RARE DUNGEON STANDS ABOVE ITS LAND — BY A LITTLE, AND NEVER BY A GRADE.
##
## Owner 2026-09-18: *"I'm fine with some variance and rare finds, it would help keep those finds
## interesting and diversify the Quests offered on the board BUT, it shouldn't be huge jumps like
## we had before where it goes up entire grades (like a G2 where an H2 normally is)."*
##
## Two properties, and BOTH are load-bearing:
##
##   1. **The letter never changes.** One rank is ~3% power and nine ranks is a whole grade, so a
##      bump of 1-3 is ~3-9%. Crossing into the next letter is the thing being ruled out.
##   2. **The same dungeon always grades the same.** This is why the roll is a hash of the
##      dungeon's identity and not `randi()`. A dungeon's grade is computed independently by the
##      overworld marker, the quest board, the accept path, the entry warning and the turn-in —
##      and in v0.9.802 they disagreed, which the owner met as *"Board showed H2, where it points
##      me shows G2. Inside shows G2 as well."* A random roll at any of those sites brings that
##      straight back, and it would be invisible until a player walked into it.
##
## Run:
##   godot --headless --path . --script res://tools/probe/rare_dungeon_grade.gd

const PR = preload("res://shared/power_rank.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== THE LETTER IS NEVER CROSSED =====")
	var n := 0
	var raised := 0
	var worst_bump := 0
	var by_bump := {0: 0, 1: 0, 2: 0, 3: 0}
	# Sweep real land grades across the whole ladder, many dungeons each.
	for tier in range(1, 10):
		for rank in range(1, PR.RANKS + 1):
			for i in range(400):
				n += 1
				var g: Dictionary = PR.varied_grade(tier, rank, "wd:%d,%d|%d" % [tier * 37, rank * 91, i])
				ck_silent(int(g["tier"]) == tier, "tier changed from %d to %d" % [tier, int(g["tier"])])
				var bump: int = int(g["rank"]) - rank
				ck_silent(bump >= 0 and bump <= PR.RARE_GRADE_MAX_BUMP,
					"bump out of range: %d" % bump)
				if bump > 0:
					raised += 1
				worst_bump = maxi(worst_bump, bump)
				by_bump[bump] = int(by_bump.get(bump, 0)) + 1
	ck(true, "swept %d dungeons across every grade on the ladder" % n)
	ck(worst_bump <= PR.RARE_GRADE_MAX_BUMP,
		"the largest bump seen anywhere is +%d (cap is +%d)" % [worst_bump, PR.RARE_GRADE_MAX_BUMP])

	print("\n===== HOW OFTEN, AND BY HOW MUCH =====")
	var pct: float = 100.0 * float(raised) / float(n)
	var want: float = 100.0 / float(PR.RARE_GRADE_ONE_IN)
	print("  raised: %d of %d = %.1f%% (target ~%.1f%%, one in %d)" % [raised, n, pct, want, PR.RARE_GRADE_ONE_IN])
	for b in [1, 2, 3]:
		print("     +%d rank: %d" % [b, int(by_bump.get(b, 0))])
	# Loose band: this is a hash, not an RNG, so it will not land exactly on 1/12.
	ck(absf(pct - want) < 2.5, "the rare rate is close to one in %d" % PR.RARE_GRADE_ONE_IN)
	ck(int(by_bump.get(1, 0)) > 0 and int(by_bump.get(2, 0)) > 0 and int(by_bump.get(3, 0)) > 0,
		"all three bump sizes actually occur")

	print("\n===== THE TOP OF A BAND CANNOT SPILL OVER =====")
	# The case the clamp exists for: already at rank 9, a bump must do nothing.
	var spill := 0
	for i in range(2000):
		var g: Dictionary = PR.varied_grade(4, PR.RANKS, "edge:%d" % i)
		if int(g["tier"]) != 4 or int(g["rank"]) > PR.RANKS:
			spill += 1
	ck(spill == 0, "a rank-9 dungeon never becomes rank 10 or the next letter (%d spills)" % spill)

	print("\n===== THE SAME DUNGEON ALWAYS GRADES THE SAME =====")
	var stable := true
	for i in range(500):
		var k := "wd:%d,%d" % [i * 13, -i * 7]
		var a: Dictionary = PR.varied_grade(3, 4, k)
		var b: Dictionary = PR.varied_grade(3, 4, k)
		if int(a["tier"]) != int(b["tier"]) or int(a["rank"]) != int(b["rank"]):
			stable = false
	ck(stable, "re-asking for one dungeon's grade returns the same answer (no randi on the path)")
	# ...and different dungeons in the SAME country do differ, or there is no variance at all.
	var seen := {}
	for i in range(300):
		var g: Dictionary = PR.varied_grade(3, 4, "wd:%d,0" % i)
		seen[int(g["rank"])] = true
	ck(seen.size() > 1, "different dungeons in one country can differ (%d distinct ranks)" % seen.size())

	print("\n===== AND NO CALL SITE ROLLS ITS OWN =====")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var qdb := FileAccess.get_file_as_string("res://shared/quest_database.gd")
	ck(srv.count("varied_grade(") == 2, "both world spawn paths use it (%d)" % srv.count("varied_grade("))
	ck(qdb.count("varied_grade(") == 1, "and the quest board uses it once")
	ck(srv.find('varied_grade') >= 0 and srv.find('"wd:%d,%d"') >= 0,
		"the world key is the dungeon's POSITION - stable for the life of that dungeon")
	ck(qdb.find('"q:" + quest_id') >= 0,
		"the quest key is the QUEST ID - stable across board, accept and turn-in")

	print("")
	if fails == 0:
		print("[PROBE] PASS rare dungeons are rare, small, and stable")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)


var _silent_fails := 0
func ck_silent(ok: bool, msg: String) -> void:
	if not ok and _silent_fails < 5:
		_silent_fails += 1
		fails += 1
		print("  FAIL  " + msg)
