extends SceneTree
## Does `is_room_cell` actually tell a room from a corridor?
##
## The renderer draws a different FLOOR for each, so a wrong answer is visible on every tile: a
## corridor painted as room floor, or a chamber that stays corridor. Hand-built grids with a known
## answer, then the real generator, because a rule that works on a diagram and not on a real floor
## is no rule.
const _T = preload("res://client/dungeon_tiles.gd")
const _DD = preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok: fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func grid_from(rows: Array) -> Array:
	"""'#' wall, '.' floor — so the fixture reads as the thing it describes."""
	var g := []
	for r in rows:
		var line := []
		for ch in String(r):
			line.append(1 if ch == "#" else 0)
		g.append(line)
	return g


func _init() -> void:
	print("--- 1. a 1-wide corridor is NEVER a room ---")
	var corridor := grid_from([
		"#####",
		"#...#",
		"#####",
	])
	var any_room := false
	for x in range(1, 4):
		if _T.is_room_cell(corridor, x, 1):
			any_room = true
	ck(not any_room, "no cell of a straight 1-wide corridor reads as room")

	print("--- 2. a T-JUNCTION is still corridor (the case a both-axes test gets wrong) ---")
	var tee := grid_from([
		"##.##",
		"##.##",
		"#...#",
		"##.##",
	])
	ck(not _T.is_room_cell(tee, 2, 2), "the junction cell is corridor, not room")
	ck(not _T.is_room_cell(tee, 2, 1), "the arm above the junction is corridor")

	print("--- 3. a 3x3 chamber IS a room, all of it ---")
	var room := grid_from([
		"#####",
		"#...#",
		"#...#",
		"#...#",
		"#####",
	])
	var all_room := true
	for y in range(1, 4):
		for x in range(1, 4):
			if not _T.is_room_cell(room, x, y):
				all_room = false
	ck(all_room, "every cell of a 3x3 chamber reads as room")

	print("--- 4. the SEAM: a corridor meeting a room ---")
	var seam := grid_from([
		"#######",
		"#...###",
		"#...###",
		"#...###",
		"#.....#",
		"#######",
	])
	ck(_T.is_room_cell(seam, 2, 2), "inside the 3x3 chamber -> room")
	ck(_T.is_room_cell(seam, 3, 3), "chamber cell touching the corridor -> room")
	ck(not _T.is_room_cell(seam, 5, 4), "the corridor running off it -> corridor")

	print("--- 5. a staircase inside a chamber STANDS ON the room floor ---")
	# This first asserted the opposite, and the opposite was wrong. Excluding stairs from a
	# room made the GROUND under them revert to corridor, so a staircase in a chamber sat on a
	# brown square. Owner, first walkthrough: "I also found another one near the stairs that
	# seems to be brown for no apparent reason." A staircase is an OBJECT ON the floor, not a
	# hole in it - only a WALL breaks a room.
	var st := grid_from(["#####", "#...#", "#...#", "#...#", "#####"])
	st[2][2] = 3   # EXIT stairs dropped into a chamber
	ck(_T.is_room_cell(st, 2, 2), "the ground under a staircase in a chamber is room floor")
	var st2 := grid_from(["#####", "#...#", "#####"])
	st2[1][2] = 3  # stairs at the end of a CORRIDOR
	ck(not _T.is_room_cell(st2, 2, 1), "a staircase in a corridor still stands on corridor floor")

	print("--- 6. a REAL generated floor, not a diagram ---")
	# It returns a Dictionary; the grid is one field of it. Reading the signature rather than
	# guessing the shape, because a probe that silently gets an empty array reports a vacuous
	# pass -- which has already happened twice today.
	var res: Dictionary = _DD.generate_floor_grid("wolf_den", 1, false)
	var g: Array = res.get("grid", [])
	if g.is_empty():
		print("      (generator entry point not reachable from here; skipped)")
	else:
		var rooms := 0
		var corr := 0
		for y in range(g.size()):
			for x in range(g[y].size()):
				if int(g[y][x]) in [1, 2, 3]:
					continue
				if _T.is_room_cell(g, x, y): rooms += 1
				else: corr += 1
		print("      real floor: %d room cells, %d corridor cells" % [rooms, corr])
		ck(rooms > 0, "a real floor has room cells")
		ck(corr > 0, "a real floor has corridor cells")
		# No assertion on which is larger. It was "rooms outnumber corridors", which held only
		# while the 2x2 rule was over-counting: passages were being labelled as rooms. With the
		# 3x3 rule a floor of small chambers joined by long corridors has MORE corridor, and that
		# is the correct shape. Asserting the old ratio would have locked in the bug.
		print("      room:corridor ratio %.2f" % (float(rooms) / float(maxi(1, corr))))

	print("--- 7. ROOM IDENTITY: each chamber gets its own id ---")
	# Needed because each chamber picks a LOOK. Hashing per cell would speckle several looks
	# through one room; the room has to be one thing.
	var two := grid_from([
		"###########",
		"#...###...#",
		"#...#.#...#",
		"#...###...#",
		"###########",
	])
	# the '+' is a corridor cell joining the two chambers - it is 1 wide, so not room floor
	var labels := _T.label_rooms(two)
	ck(_T.room_count(labels) == 2, "two chambers joined by a 1-wide corridor are TWO rooms (got %d)" % _T.room_count(labels))
	ck(labels.get("1,1", -1) == labels.get("3,3", -2), "cells of the same chamber share an id")
	ck(labels.get("1,1", -1) != labels.get("7,1", -2), "cells of different chambers do not")
	ck(not labels.has("5,2"), "the joining corridor cell has no room id at all")

	var one := grid_from([
		"######",
		"#....#",
		"#....#",
		"#....#",
		"######",
	])
	ck(_T.room_count(_T.label_rooms(one)) == 1, "one open chamber is ONE room, not several")

	print("--- 8. room identity on a REAL floor ---")
	var res2: Dictionary = _DD.generate_floor_grid("wolf_den", 1, false)
	var g2: Array = res2.get("grid", [])
	if not g2.is_empty():
		var l2 := _T.label_rooms(g2)
		var n2: int = _T.room_count(l2)
		print("      %d room cells across %d distinct chambers" % [l2.size(), n2])
		ck(n2 >= 2, "a real floor has several distinct chambers, not one blob")
		ck(n2 <= 40, "and not one chamber per cell (%d)" % n2)
		# stability: labelling the same grid twice must agree, or a room would change look on redraw
		ck(_T.label_rooms(g2) == l2, "labelling is deterministic - a room keeps its look on redraw")


	print("--- 9. no ROOM is really a run of passages (the bug the owner spotted) ---")
	# The 2x2 rule passed every fixture above and still mislabelled real floors, because two
	# corridors running ADJACENT form a 2x2 and the flood fill spread along the whole run. It
	# produced "rooms" of 8x26 at 45% fill. Fixtures cannot catch that; only generated floors can.
	for dt in ["kobold_tunnels", "wolf_den"]:
		for f in range(1, 4):
			var r3: Dictionary = _DD.generate_floor_grid(dt, f, false)
			var g3: Array = r3.get("grid", [])
			if g3.is_empty():
				continue
			var l3: Dictionary = _T.label_rooms(g3)
			var box := {}
			for k in l3:
				var id: int = l3[k]
				var pp: PackedStringArray = String(k).split(",")
				var xx := int(pp[0])
				var yy := int(pp[1])
				if not box.has(id):
					box[id] = {"x0": xx, "x1": xx, "y0": yy, "y1": yy, "n": 0}
				var bb = box[id]
				bb.x0 = mini(bb.x0, xx); bb.x1 = maxi(bb.x1, xx)
				bb.y0 = mini(bb.y0, yy); bb.y1 = maxi(bb.y1, yy)
				bb.n += 1
			var bad := 0
			for id in box:
				var bb = box[id]
				var w: int = bb.x1 - bb.x0 + 1
				var h: int = bb.y1 - bb.y0 + 1
				if float(bb.n) / float(w * h) < 0.5:
					bad += 1
			ck(bad == 0, "%s f%d: %d rooms, none is a sparse blob" % [dt, f, box.size()])

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
