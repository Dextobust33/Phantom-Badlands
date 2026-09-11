extends SceneTree
## ONE tier-level table, and every system that maps a level to a tier agrees with it.
##
## 2026-09-11, owner's decision. The 5 / 15 / 30 / 50 / 100 / 500 / 2000 / 5000 ladder was typed
## out in seven places and an eighth copy (dungeons) disagreed below tier 6. This drives the REAL
## functions - monster_database, combat_manager, quest_database, quest_manager, three in server -
## and demands they all answer the same tier as PowerRank for the same level. The dungeon side is
## held to the exact numbers its old private table produced, because that overlap was a design
## choice the refit must not move.
const PR := preload("res://shared/power_rank.gd")
const DD := preload("res://shared/dungeon_database.gd")
const MD := preload("res://shared/monster_database.gd")
const CM := preload("res://shared/combat_manager.gd")
const QD := preload("res://shared/quest_database.gd")
const QM := preload("res://shared/quest_manager.gd")
const SV := preload("res://server/server.gd")

## The ladder as every copy typed it, kept here as the REFERENCE the shared table must match.
const OLD_THRESHOLDS := [5, 15, 30, 50, 100, 500, 2000, 5000]
## The dungeon table exactly as dungeon_database.gd held it before the refit.
const OLD_DUNGEON := {
	1: {"min": 1, "max": 12}, 2: {"min": 6, "max": 22}, 3: {"min": 16, "max": 40},
	4: {"min": 31, "max": 60}, 5: {"min": 51, "max": 120}, 6: {"min": 101, "max": 500},
	7: {"min": 501, "max": 2000}, 8: {"min": 2001, "max": 5000}, 9: {"min": 5001, "max": 10000},
}

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _old_tier(level: int) -> int:
	for i in range(OLD_THRESHOLDS.size()):
		if level <= OLD_THRESHOLDS[i]:
			return i + 1
	return 9


func _old_progress(level: int) -> float:
	var t := _old_tier(level)
	if t == 9:
		return 1.0
	var lo: int = 0 if t == 1 else OLD_THRESHOLDS[t - 2]
	return float(level - lo) / float(OLD_THRESHOLDS[t - 1] - lo)


func _init() -> void:
	var md = MD.new()
	var cm = CM.new()
	var qd = QD.new()
	var qm = QM.new()
	var sv = SV.new()

	# Every band edge, both sides of it, plus a spread through the middle of each band.
	var levels: Array[int] = [0, 1, 2]
	for th in OLD_THRESHOLDS:
		levels.append(th - 1)
		levels.append(th)
		levels.append(th + 1)
	for l in [8, 22, 40, 75, 250, 1200, 3500, 7000, 10000, 12000]:
		levels.append(l)

	print("--- the shared table reproduces the ladder every copy typed ---")
	var bad_shared := 0
	var bad_prog := 0
	for l in levels:
		if PR.tier_for_level(l) != _old_tier(l):
			bad_shared += 1
		if absf(PR.tier_progress(l) - _old_progress(l)) > 0.0001:
			bad_prog += 1
	ck(bad_shared == 0, "PowerRank.tier_for_level matches the old thresholds at %d levels" % levels.size())
	ck(bad_prog == 0, "PowerRank.tier_progress matches _get_tier_info's old arithmetic (top tier = 1.0)")

	print("\n--- seven consumers, one answer ---")
	var disagree := {}
	for l in levels:
		var want: int = PR.tier_for_level(l)
		var got := {
			"monster_database._get_tier_info": int(md._get_tier_info(l).tier),
			"combat_manager._get_tier_for_level": cm._get_tier_for_level(l),
			"quest_database._get_tier_for_area_level": qd._get_tier_for_area_level(l),
			"quest_manager._get_tier_from_level": qm._get_tier_from_level(l),
			"server._level_to_tier": int(String(sv._level_to_tier(l)).trim_prefix("tier")),
			"server._get_monster_tier": sv._get_monster_tier(l),
			"server._get_tier_from_player_level": sv._get_tier_from_player_level(l),
		}
		for k in got:
			if got[k] != want:
				disagree[k] = disagree.get(k, 0) + 1
	for k in ["monster_database._get_tier_info", "combat_manager._get_tier_for_level",
			"quest_database._get_tier_for_area_level", "quest_manager._get_tier_from_level",
			"server._level_to_tier", "server._get_monster_tier", "server._get_tier_from_player_level"]:
		ck(not disagree.has(k), "%s agrees at every level" % k)
	ck(QD.TIER_LEVEL_RANGES == PR.TIER_LEVEL_BANDS, "quest_database.TIER_LEVEL_RANGES IS the shared table, not a copy")

	print("\n--- dungeons: same numbers as before, now derived ---")
	var moved := []
	for t in range(1, 10):
		var b: Dictionary = PR.dungeon_band(t)
		if int(b.min) != int(OLD_DUNGEON[t].min) or int(b.max) != int(OLD_DUNGEON[t].max):
			moved.append("T%d %d-%d (was %d-%d)" % [t, b.min, b.max, OLD_DUNGEON[t].min, OLD_DUNGEON[t].max])
	ck(moved.is_empty(), "dungeon_band(t) reproduces the old dungeon table for all nine tiers%s" % (
		"" if moved.is_empty() else ": " + ", ".join(moved)))
	# The rank slices are what the server actually reads; hold them too.
	var slices_ok := true
	for t in range(1, 10):
		var lo: int = int(OLD_DUNGEON[t].min)
		var hi: int = int(OLD_DUNGEON[t].max)
		var seg := float(hi - lo) / 9.0
		for r in range(1, 10):
			var want_min := clampi(lo + int(seg * (r - 1)), lo, hi)
			var want_max := clampi(lo + int(seg * r), want_min + 1, hi)
			if want_min >= want_max:
				want_max = want_min + 1
			var got: Dictionary = DD.get_sub_tier_level_range(t, r)
			if int(got.min_level) != want_min or int(got.max_level) != maxi(want_min, want_max):
				slices_ok = false
	ck(slices_ok, "get_sub_tier_level_range gives every rank the slice it gave before, all 81")
	ck(int(PR.dungeon_band(1).max) == int(PR.band(1).max) + int(PR.DUNGEON_REACH[1]),
		"the overlap is a NAMED reach on top of the monster band, not a second table")
	for t in range(6, 10):
		if int(PR.DUNGEON_REACH[t]) != 0:
			fails += 1
			print("  FAIL  tier %d has a reach; the ladders have always agreed from tier 6 up" % t)

	print("\n--- no typed-out copy survives outside the shared file ---")
	var copies := 0
	for f in ["res://shared/monster_database.gd", "res://shared/combat_manager.gd",
			"res://shared/quest_database.gd", "res://shared/quest_manager.gd",
			"res://shared/dungeon_database.gd", "res://shared/drop_tables.gd",
			"res://server/server.gd", "res://client/client.gd"]:
		for ln in FileAccess.get_file_as_string(f).split("\n"):
			var line := String(ln).strip_edges()
			if line.begins_with("#"):
				continue
			# A tier ladder is the only thing in this codebase that compares a level to 2000/5000.
			if line.find("level <= 2000") >= 0 or line.find("level <= 5000") >= 0 \
					or line.find('"min": 6, "max": 15') >= 0 or line.find('"min": 6, "max": 22') >= 0:
				copies += 1
				print("  copy: %s: %s" % [f, line])
	ck(copies == 0, "no file besides power_rank.gd types the ladder out")

	md.free(); cm.free(); qd.free(); qm.free(); sv.free()
	print("\n[TIERBANDS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
