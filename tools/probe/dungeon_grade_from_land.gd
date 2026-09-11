extends SceneTree
## A dungeon's grade must be a fact about the LAND it stands in.
##
## Owner reported 2026-09-11 a G2 dungeon holding L7-9 monsters standing in L15-17 wilderness, and
## then asked for the opposite to be possible too: *"We do want lower types of monster dungeons to
## be possible in high level areas (example an A5 Goblin Dungeon, or a S2 Kelpie one etc)."*
##
## Both wants have the same answer: the GRADE stops being a number hardcoded on the dungeon type
## and becomes a reading of the land. This probe holds the two primitives that make that possible
## and, crucially, that they are inverses of each other - a level in, a grade out, and the grade's
## own level band containing the level you started with. If those two ever drift, a dungeon will
## quietly advertise a difficulty it does not have, which is the original fault returning.
const PR := preload("res://shared/power_rank.gd")
const DD := preload("res://shared/dungeon_database.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)

	print("--- a level maps to a grade, and that grade's band holds the level ---")
	var checked := 0
	var outside := 0
	var worst := ""
	for level in [1, 2, 5, 6, 12, 15, 16, 22, 30, 31, 50, 51, 100, 101, 250, 500, 501,
			1200, 2000, 2001, 3500, 5000, 5001, 8000, 10000]:
		var g: Dictionary = PR.grade_for_level(level)
		var t: int = int(g["tier"])
		var r: int = int(g["rank"])
		var band: Dictionary = PR.dungeon_band(t)
		checked += 1
		if level < int(band["min"]) or level > int(band["max"]):
			outside += 1
			worst = "L%d -> %s%d, whose band is %d-%d" % [level, PR.letter(t), r, int(band["min"]), int(band["max"])]
		if r < 1 or r > PR.RANKS:
			outside += 1
	ck(outside == 0, "%d levels all land in a grade whose band contains them%s" % [checked, ("" if outside == 0 else " (e.g. " + worst + ")")])

	print("\n--- and the rank is the inverse of the range it names ---")
	# `get_sub_tier_level_range` turns (tier, rank) into levels. `rank_for_level` turns a level
	# back into a rank. A dungeon's advertised grade and its real monsters come from those two, so
	# a gap between them IS the bug the owner reported, in a different disguise.
	var round_trips := 0
	var drifted := 0
	var example := ""
	for t in range(1, PR.RANKS + 1):
		for r in range(1, PR.RANKS + 1):
			var rng: Dictionary = DD.get_sub_tier_level_range(t, r)
			var mid: int = int((int(rng["min_level"]) + int(rng["max_level"])) / 2)
			var back: int = PR.rank_for_level(t, mid)
			round_trips += 1
			if absi(back - r) > 1:
				drifted += 1
				if example == "":
					example = "%s%d spans L%d-%d, whose middle reads back as rank %d" % [
						PR.letter(t), r, int(rng["min_level"]), int(rng["max_level"]), back]
	ck(drifted == 0, "all %d (tier, rank) cells round-trip within one rank%s" % [
		round_trips, ("" if example == "" else " - " + example)])

	print("\n--- the land curve inverts ---")
	var bad := 0
	for level in [1, 5, 17, 50, 120, 500, 2000, 6000, 10000]:
		var d: float = ws.distance_for_level(level)
		var got: int = ws._distance_to_level(d)
		# Bisection lands on the first distance that reaches the level; one step in is below it.
		if got < level or ws._distance_to_level(maxf(0.0, d - 1.0)) > level:
			bad += 1
			print("    L%d -> distance %.1f -> reads back L%d" % [level, d, got])
	ck(bad == 0, "distance_for_level is a true inverse of the curve at every band boundary")
	var d1: float = ws.distance_for_level(17)
	var d2: float = ws.distance_for_level(17)
	ck(is_equal_approx(d1, d2), "and it is cached, so the placer can ask freely")
	var rising := true
	var prev := -1.0
	for level in [1, 5, 17, 50, 120, 500, 2000, 6000, 10000]:
		var d: float = ws.distance_for_level(level)
		if d < prev:
			rising = false
		prev = d
	ck(rising, "a higher level is always further out - the world has no pockets that break the climb")

	print("\n--- what this makes possible, spelled out ---")
	# The point of the exercise: the same dungeon TYPE can now be honest at any grade, because
	# nothing here consults a type at all.
	for level in [8, 17, 120, 3000]:
		var g: Dictionary = PR.grade_for_level(level)
		var rng: Dictionary = DD.get_sub_tier_level_range(int(g["tier"]), int(g["rank"]))
		print("  land at L%-5d -> a %s%d dungeon, monsters L%d-%d, at distance %d" % [
			level, PR.letter(int(g["tier"])), int(g["rank"]),
			int(rng["min_level"]), int(rng["max_level"]), int(ws.distance_for_level(level))])

	print("\n[GRADEFROMLAND] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
