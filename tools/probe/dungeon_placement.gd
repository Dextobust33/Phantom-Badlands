extends SceneTree
## A dungeon stands in country that matches it, and its grade is a reading of that country.
##
## The owner found a G2 dungeon holding L7-9 monsters in L15-17 wilderness, and then asked for
## the mirror to be possible: *"We do want lower types of monster dungeons to be possible in high
## level areas (example an A5 Goblin Dungeon, or a S2 Kelpie one etc)."* Both come from the same
## change - a dungeon is placed where the land already reaches its levels, and the grade is read
## off the ground rather than off a number hardcoded on its type.
##
## Placement used to be `tier*30 .. tier*60`, a ring with no relationship to the level curve.
## This probe spawns a world's worth of dungeons through the SAME functions the server calls and
## measures whether the grade and the ground agree.
const DD := preload("res://shared/dungeon_database.gd")
const PR := preload("res://shared/power_rank.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	var cells: Array = DD.grade_cells(ws.distance_for_level)

	print("--- the 81 grades have somewhere to be ---")
	ck(cells.size() == 81, "%d cells" % cells.size())
	var bad_ring := 0
	for c in cells:
		if float(c["d1"]) <= float(c["d0"]) or float(c["d0"]) < 0.0:
			bad_ring += 1
	ck(bad_ring == 0, "every cell has a real ring of world to sit in")
	var zero_weight := 0
	for c in cells:
		if float(c["weight"]) <= 0.0:
			zero_weight += 1
	ck(zero_weight == 0, "and every grade can actually be rolled - none is weighted to nothing")

	print("\n--- a rank 9 is rarer than a rank 1 of the same grade ---")
	# Owner: "Dungeons should have a rarity moving forward." Area works AGAINST this on its own,
	# because a tier's higher ranks sit in its outer and larger part.
	var falling := 0
	var rising := 0
	for t in range(1, 10):
		var w1 := 0.0
		var w9 := 0.0
		for c in cells:
			if int(c["tier"]) == t and int(c["rank"]) == 1:
				w1 = float(c["weight"])
			elif int(c["tier"]) == t and int(c["rank"]) == 9:
				w9 = float(c["weight"])
		if w9 < w1:
			falling += 1
		else:
			rising += 1
	ck(falling == 9, "in all 9 grades, rank 9 is weighted below rank 1 (%d were not)" % rising)

	print("\n--- spawn a world's worth and look at the ground under each one ---")
	var N := 1500
	var matched := 0
	var off_by_one := 0
	var worse := 0
	var per_tier := {}
	var worst_example := ""
	for i in range(N):
		var cell: Dictionary = DD.pick_grade(cells)
		var pos: Vector2i = DD.roll_location_in_ring(float(cell["d0"]), float(cell["d1"]))
		# Exactly what the server does next: read the grade off the land it landed on.
		var land_level: int = maxi(1, int(ws.get_post_anchored_level(pos.x, pos.y)))
		var grade: Dictionary = PR.grade_for_level(land_level)
		var t: int = int(grade["tier"])
		var r: int = int(grade["rank"])
		per_tier[t] = int(per_tier.get(t, 0)) + 1
		# The dungeon's monsters come from this grade's band. The question is whether that band
		# actually contains the level of the wilderness around it.
		var band: Dictionary = DD.get_sub_tier_level_range(t, r)
		var lo: int = int(band["min_level"])
		var hi: int = int(band["max_level"])
		if land_level >= lo and land_level <= hi:
			matched += 1
		elif land_level >= lo - 2 and land_level <= hi + 2:
			off_by_one += 1
		else:
			worse += 1
			if worst_example == "":
				worst_example = "land L%d at (%d,%d) -> %s%d, whose monsters are L%d-%d" % [
					land_level, pos.x, pos.y, PR.letter(t), r, lo, hi]
	print("  %d spawns: %d land inside their own band, %d within 2 levels, %d further off" % [
		N, matched, off_by_one, worse])
	ck(worse == 0, "not one dungeon is out of step with its country%s" % (
		"" if worst_example == "" else " - " + worst_example))
	ck(matched > N * 0.9, "and %d%% sit exactly inside it" % int(float(matched) / float(N) * 100.0))

	print("\n--- and the world is no longer just its middle ---")
	# Everything used to spawn inside r=540. Half the world by area is S country alone.
	var far := 0
	for i in range(N):
		var cell: Dictionary = DD.pick_grade(cells)
		var pos: Vector2i = DD.roll_location_in_ring(float(cell["d0"]), float(cell["d1"]))
		if sqrt(float(pos.x * pos.x + pos.y * pos.y)) > 540.0:
			far += 1
	ck(far > N / 10, "%d of %d spawns land beyond r=540, where NOTHING used to spawn at all" % [far, N])
	var covered := 0
	for t in range(1, 10):
		if int(per_tier.get(t, 0)) > 0:
			covered += 1
	ck(covered >= 8, "%d of the 9 grades appear in a sample of %d" % [covered, N])
	var line := "  spread: "
	for t in range(1, 10):
		line += "%s=%d " % [PR.letter(t), int(per_tier.get(t, 0))]
	print(line)

	print("\n--- types are picked by RARITY, not uniformly ---")
	var counts := {}
	for i in range(6000):
		var dt: String = DD.pick_weighted_type()
		counts[dt] = int(counts.get(dt, 0)) + 1
	ck(counts.size() > 40, "%d of the 53 types appear" % counts.size())
	# spawn_weight runs from 50 down to 1 and was read by nothing at all before this.
	var heaviest := ""
	var lightest := ""
	var hw := -1
	var lw := 99999
	for dt in DD.DUNGEON_TYPES:
		var w: int = int(DD.DUNGEON_TYPES[dt].get("spawn_weight", 50))
		if w > hw:
			hw = w
			heaviest = String(dt)
		if w < lw:
			lw = w
			lightest = String(dt)
	var ch: int = int(counts.get(heaviest, 0))
	var cl: int = int(counts.get(lightest, 0))
	print("  weight %d (%s) drew %d; weight %d (%s) drew %d" % [hw, heaviest, ch, lw, lightest, cl])
	ck(ch > cl, "the common type really is commoner than the rare one")

	print("\n--- and the server actually places this way ---")
	# The maths above is shared code; these lines are what make the SERVER use it. Without
	# them this probe would pass happily while dungeons still spawned in tier*30..tier*60.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find("_grade_of_land(world_x, world_y)") >= 0,
		"the world placer reads the grade off the ground it landed on")
	ck(srv.find("_roll_location_in_ring(float(_target_cell") >= 0,
		"...having rolled its location inside that grade's ring")
	ck(srv.count("_pick_weighted_dungeon_type()") >= 3,
		"...and both spawn loops pick the TYPE by rarity")
	ck(srv.find('"tier": grade_tier') >= 0,
		"and the instance stores the grade the LAND gave it, not the type's")

	print("\n[DUNGEONPLACEMENT] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
