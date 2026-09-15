extends SceneTree
## The starter post has a handful of doors, not a wall full of them.
##
## Owner 2026-09-15: *"reduce the number of doors on the starter post. We don't need so many of them."*
## Counted on the real generator and the real door picker, across several world seeds (the starter's
## wings are rolled), and checked that every door still opens onto the post's own floor.
const DB = preload("res://shared/npc_post_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var counts: Array = []
	var other_counts: Array = []
	for seed_i in range(8):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + seed_i
		var post: Dictionary = DB._create_starter_post(rng)
		var floor_tiles: Dictionary = DB._compute_floor_tiles(post.main_room, post.get("wing_rooms", []))
		var wall_tiles: Dictionary = DB._compute_wall_tiles(floor_tiles)
		var doors: Dictionary = DB._doors_for_post(post, wall_tiles, floor_tiles)
		counts.append(doors.size())
		if seed_i == 0:
			print("  before the cap this starter post had %d doors" % DB._select_doors(wall_tiles, floor_tiles, int(post.x), int(post.y)).size())
		var on_floor := true
		for k in doors:
			var p: PackedStringArray = String(k).split(",")
			var touches := false
			for o in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				if floor_tiles.has("%d,%d" % [int(p[0]) + o[0], int(p[1]) + o[1]]):
					touches = true
			on_floor = on_floor and touches
		ck(on_floor, "seed %d: every starter door opens onto the post's floor" % seed_i)
		# An ordinary post is untouched.
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 5000 + seed_i
		var op: Dictionary = DB._generate_post(rng2, 400, 400, false)
		var of: Dictionary = DB._compute_floor_tiles(op.main_room, op.get("wing_rooms", []))
		var ow: Dictionary = DB._compute_wall_tiles(of)
		var od: Dictionary = DB._doors_for_post(op, ow, of)
		other_counts.append(od.size())
	print("  starter post doors by seed: %s" % str(counts))
	print("  ordinary post doors by seed: %s" % str(other_counts))
	var most: int = counts.max()
	var fewest: int = counts.min()
	ck(most <= DB.STARTER_MAX_DOORS, "the starter post has at most %d doors (most seen %d)" % [DB.STARTER_MAX_DOORS, most])
	ck(fewest >= 2, "...and still more than one way in (fewest seen %d)" % fewest)
	ck(other_counts.min() >= DB.MIN_DOORS, "ordinary posts keep their doors (fewest %d)" % other_counts.min())
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
