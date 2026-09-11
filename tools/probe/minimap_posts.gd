extends SceneTree
## The minimap's NPC-post test must stay EXACT while it stops scanning every post in the world.
##
## 2026-09-11: `_generate_minimap` walked all ~150 post points (60 posts plus their wing rooms)
## for each of its 861 cells - well over a hundred thousand box tests for every step a player
## takes, 5.7 ms of a 15.4 ms location update. It now files those points into a coarse bucket
## grid and looks only at the buckets a cell's box can overlap.
##
## The danger is silent: a point that hides in a bucket the lookup never visits does not crash
## anything, it just stops drawing a P, and a player walks past a trading post they should have
## seen. So this compares the shipped `_near_npc_post` against the full scan it replaced, on every
## cell of nine different minimaps, and demands they agree on all of them.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

const STEP := 2
const MAP_HALF_W := 20
const MAP_HALF_H := 10

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()   # the server does this at boot; without it the world has no posts at all
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("--- what a four-bucket lookup rests on ---")
	var near: int = ws.POST_NEAR
	var bucket: int = ws.POST_BUCKET
	ck(bucket > 2 * near + 1,
		"the bucket (%d) is wider than the box (%d), so a lookup stays at four buckets" % [bucket, 2 * near + 1])

	# The old scan, written out here, so the comparison is against the code that SHIPPED rather
	# than against the new code restating itself.
	var post_points: Array = []
	for p in cm.get_npc_posts():
		post_points.append(Vector2i(int(p.get("x", 0)), int(p.get("y", 0))))
		for wing in p.get("wing_rooms", []):
			post_points.append(Vector2i(
				(int(wing.get("x0", 0)) + int(wing.get("x1", 0))) / 2,
				(int(wing.get("y0", 0)) + int(wing.get("y1", 0))) / 2))
	ck(post_points.size() > 50, "the world really has a crowd of post points to scan (%d)" % post_points.size())

	var buckets: Dictionary = ws._bucket_post_points(cm.get_npc_posts())
	ck(buckets.size() > 0, "they file into %d buckets" % buckets.size())
	var filed := 0
	for k in buckets:
		filed += buckets[k].size()
	ck(filed == post_points.size(), "and not one is lost on the way in (%d filed, %d points)" % [filed, post_points.size()])

	print("\n--- every cell of every minimap, old answer vs new ---")
	# Centres that matter: where a player starts, and ON several posts, where the test is actually
	# true. A comparison that only visits empty wilderness proves nothing.
	var centres: Array = [Vector2i(40, 40), Vector2i(0, 0), Vector2i(-300, 150)]
	var posts_all: Array = cm.get_npc_posts()
	for i in range(mini(6, posts_all.size())):
		centres.append(Vector2i(int(posts_all[i].get("x", 0)), int(posts_all[i].get("y", 0))))

	var cells := 0
	var disagree := 0
	var trues := 0
	for c in centres:
		for miny in range(MAP_HALF_H, -MAP_HALF_H - 1, -1):
			for minx in range(-MAP_HALF_W, MAP_HALF_W + 1):
				var wx: int = c.x + minx * STEP
				var wy: int = c.y + miny * STEP
				cells += 1
				var old_near := false
				for pp in post_points:
					if absi(pp.x - wx) <= near and absi(pp.y - wy) <= near:
						if cm.is_npc_post_tile(wx, wy):
							old_near = true
							break
				var new_near: bool = ws._near_npc_post(buckets, wx, wy)
				if old_near:
					trues += 1
				if old_near != new_near:
					disagree += 1
	ck(cells > 7000, "%d minimap cells across %d centres" % [cells, centres.size()])
	ck(trues > 20, "%d of them ARE post tiles, so the test is exercised true as well as false" % trues)
	ck(disagree == 0, "old scan and bucket lookup agree on EVERY one (%d disagreements)" % disagree)

	print("\n--- the posts still draw ---")
	var pc := 0
	for i in range(mini(4, posts_all.size())):
		var mm: String = ws._generate_minimap(int(posts_all[i].get("x", 0)), int(posts_all[i].get("y", 0)), [])
		pc += mm.count("]P[/color]")
	ck(pc > 0, "a minimap centred on a post shows %d gold P markers" % pc)

	print("\n--- and it is the point of the exercise ---")
	var probe_cells: Array = []
	for miny in range(MAP_HALF_H, -MAP_HALF_H - 1, -1):
		for minx in range(-MAP_HALF_W, MAP_HALF_W + 1):
			probe_cells.append(Vector2i(40 + minx * STEP, 40 + miny * STEP))
	var t0 := Time.get_ticks_usec()
	for c in probe_cells:
		for pp in post_points:
			if absi(pp.x - c.x) <= near and absi(pp.y - c.y) <= near:
				break
	var old_us := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for c in probe_cells:
		ws._near_npc_post(buckets, c.x, c.y)
	var new_us := Time.get_ticks_usec() - t0
	print("  one minimap's worth of proximity tests: scan %d us -> bucket %d us" % [old_us, new_us])
	ck(new_us * 3 < old_us, "the bucket is at least 3x cheaper over a whole minimap")

	print("\n[MINIMAPPOSTS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
