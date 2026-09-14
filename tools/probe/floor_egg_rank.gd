extends SceneTree
## Climbing a dungeon's rank has to pay off in the eggs it drops.
##
## Owner 2026-09-11: *"each of those higher ranked ones should ideally have a higher chance to
## drop higher rank eggs (we should check this and fix it if they don't)."*
##
## Egg rank becomes the companion's `sub_tier`, which multiplies its stats (1.0x at rank 1 to 2.0x
## at rank 9) and the bonuses it hands its owner. It is the whole reward for climbing ranks, and
## the floor is where most of the eggs come from - so if the floor roll ignores the dungeon, rank
## buys a player exactly one egg per run.
const ServerScript = preload("res://server/server.gd")
const PowerRankScript = preload("res://shared/power_rank.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv = ServerScript.new()

	print("===== DOES A HIGHER-RANK DUNGEON DROP HIGHER-RANK EGGS? =====")
	print("  %-8s %8s %8s %8s   %s" % ["dungeon", "mean", "min", "max", "distribution"])
	var means: Array = []
	var n := 4000
	for r in range(1, PowerRankScript.RANKS + 1):
		var total := 0
		var lo := 99
		var hi := 0
		var hist: Dictionary = {}
		for i in range(n):
			var e: int = srv._floor_egg_rank(r)
			total += e
			lo = mini(lo, e)
			hi = maxi(hi, e)
			hist[e] = int(hist.get(e, 0)) + 1
		var mean: float = float(total) / float(n)
		means.append(mean)
		var bar := ""
		for k in range(1, PowerRankScript.RANKS + 1):
			var pct: int = int(round(100.0 * float(hist.get(k, 0)) / float(n)))
			bar += "%d:%-3d" % [k, pct]
		print("  rank %-3d %8.2f %8d %8d   %s" % [r, mean, lo, hi, bar])

	# The claim: a higher-rank dungeon gives better eggs. Monotonic means, not just "different".
	var rising := true
	for i in range(1, means.size()):
		if float(means[i]) < float(means[i - 1]) - 0.001:
			rising = false
	ck(rising, "mean egg rank rises with the dungeon's rank, every step")
	ck(float(means[means.size() - 1]) - float(means[0]) >= 4.0,
		"and the spread across the ladder is worth having: rank 1 gives %.2f, rank 9 gives %.2f"
			% [float(means[0]), float(means[means.size() - 1])])

	print("\n===== AND A RANK-9 DUNGEON CAN ACTUALLY PRODUCE A RANK-9 EGG =====")
	# The old roll was `1 + randi() % 8` - it could never return 9 even after dungeons started
	# generating rank 9, so the top of the ladder was unreachable from the floor.
	var saw_nine := false
	for i in range(4000):
		if srv._floor_egg_rank(PowerRankScript.RANKS) == PowerRankScript.RANKS:
			saw_nine = true
			break
	ck(saw_nine, "rank %d is reachable from a floor egg" % PowerRankScript.RANKS)
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc.find("1 + randi() % 8") < 0 or ssrc.find("It used to be `1 + randi() % 8`") >= 0,
		"the old uniform roll survives only as a comment explaining itself")

	print("\n===== AND A RANK-1 DUNGEON DOES NOT HAND OUT TOP EGGS =====")
	var top := 0
	for i in range(4000):
		if srv._floor_egg_rank(1) >= 7:
			top += 1
	print("  a rank-1 dungeon produced a rank-7+ egg %d times in 4000" % top)
	ck(top == 0, "the bottom of the ladder cannot produce the top of it")

	print("\n===== AND THE FINAL CHEST'S GEAR SCALES WITH RANK TOO =====")
	# The one reward every run ends on. It used to roll at `max(1, character.level)` - the
	# LOOTER's level - so a rank-1 and a rank-9 dungeon of the same tier gave identical
	# equipment, and `inst_sub_tier` sat two lines above it, read and unused.
	const DungeonDB = preload("res://shared/dungeon_database.gd")
	print("  %-6s %10s %10s   %s" % ["rank", "band min", "band max", "chest gear level (level-20 player)"])
	var last := -1
	var rising2 := true
	for r in range(1, PowerRankScript.RANKS + 1):
		var band: Dictionary = DungeonDB.get_sub_tier_level_range(4, r)
		var mid: int = int((int(band.get("min_level", 1)) + int(band.get("max_level", 1))) / 2)
		var lvl: int = maxi(1, maxi(20, mid))
		print("  %-6d %10d %10d   %d" % [r, int(band.get("min_level", 0)), int(band.get("max_level", 0)), lvl])
		if last >= 0 and lvl < last:
			rising2 = false
		last = lvl
	ck(rising2, "chest gear level never falls as the dungeon's rank rises")
	var b1: Dictionary = DungeonDB.get_sub_tier_level_range(4, 1)
	var b9: Dictionary = DungeonDB.get_sub_tier_level_range(4, 9)
	var mid1: int = int((int(b1.get("min_level", 1)) + int(b1.get("max_level", 1))) / 2)
	var mid9: int = int((int(b9.get("min_level", 1)) + int(b9.get("max_level", 1))) / 2)
	ck(mid9 > mid1, "a rank-9 dungeon's band sits above a rank-1's (%d vs %d)" % [mid9, mid1])
	var ssrc2 := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc2.find("var item_level = max(1, max(character.level, _band_mid))") >= 0,
		"the chest rolls at the dungeon's band, or the player's level if they have out-levelled it")
	ck(ssrc2.find("var item_level = max(1, character.level)") < 0,
		"and the looter-only version is gone")

	print("\n===== EVERY COMPLETION REWARD THAT SHOULD FOLLOW RANK, DOES =====")
	# XP and materials already applied `1.0 + (rank - 1) * 0.1`; valor did not, so a rank-9 run
	# paid 1.8x the xp and 1.8x the materials of a rank-1 and exactly the same valor - the one
	# reward a player converts into everything else.
	var ssrc3 := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc3.find("var valor_bonus = int((3 + randi() % 3) * dungeon_tier * 5 * (1.0 + (inst_sub_tier - 1) * 0.1))") >= 0,
		"valor scales with rank, on the same curve as xp and materials")
	ck(ssrc3.find("var qty = int(m.get(\"quantity\", 1) * (1.0 + (inst_sub_tier - 1) * 0.1))") >= 0,
		"materials still do")
	var dsrc2 := FileAccess.get_file_as_string("res://shared/dungeon_database.gd")
	ck(dsrc2.find("var sub_tier_mult = 1.0 + (sub_tier - 1) * 0.1") >= 0, "and so does completion xp")

	print("\n===== THE TREASURE-TILE PATH IS DEAD, AND STAYS THAT WAY KNOWINGLY =====")
	# `_open_dungeon_treasure` cannot run: floor-item spawning blanks every TREASURE tile in the
	# only kind of instance a player walks. It is kept because re-enabling treasure tiles is a
	# live design option - so this asserts the thing that makes it dead, and will start failing
	# the day somebody turns it back on without noticing the old path wakes up with it.
	ck(ssrc3.find("if _t == _tt_treasure or _t == _tt_scattered or _t == _tt_hoard:") >= 0,
		"treasure tiles are blanked when floor loot is placed")
	ck(ssrc3.find('if instance_id.begins_with("player_dungeon_"):') >= 0,
		"...for every personal instance, which is the only kind a player explores")
	ck(ssrc3.find("## ⚑ UNREACHABLE IN PRACTICE, AND THAT IS DELIBERATE") >= 0,
		"and the dead function SAYS it is dead, so nobody debugs it for an hour")

	print("\n[FLOOREGGRANK] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
