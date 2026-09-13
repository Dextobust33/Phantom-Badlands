extends SceneTree
## The indexed post lookup must give the SAME answer as the scan it replaced.
##
## `get_npc_post_at` decides whether a tile is a safe zone, which biome a cell reports, whether a
## monster may spawn there and whether the minimap draws a P. Getting it FASTER and WRONG would
## be far worse than leaving it slow - a wrong answer here makes safe ground dangerous or makes
## open road un-spawnable, and neither shows up as an error.
##
## So: the old linear scan is reproduced here, verbatim in behaviour, and every tile in a wide box
## around every post is compared. Then the speed, which is the point of the change.
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _scan(posts: Array, wx: int, wy: int) -> Dictionary:
	"""The ORIGINAL implementation, kept here as the reference."""
	for post in posts:
		var main_room = post.get("main_room", {})
		if not main_room.is_empty():
			if wx >= int(main_room["x0"]) - 1 and wx <= int(main_room["x1"]) + 1 \
					and wy >= int(main_room["y0"]) - 1 and wy <= int(main_room["y1"]) + 1:
				return post
			for wing in post.get("wing_rooms", []):
				if wx >= int(wing["x0"]) - 1 and wx <= int(wing["x1"]) + 1 \
						and wy >= int(wing["y0"]) - 1 and wy <= int(wing["y1"]) + 1:
					return post
		else:
			var px = int(post.get("x", 0))
			var py = int(post.get("y", 0))
			var half_size = int(post.get("size", 15)) / 2
			if abs(wx - px) <= half_size and abs(wy - py) <= half_size:
				return post
	return {}


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var posts: Array = cm.get_npc_posts()
	ck(posts.size() > 0, "the world has %d posts to index" % posts.size())

	print("\n--- same answer, tile for tile, around every post ---")
	var checked := 0
	var diff := 0
	var inside := 0
	for post in posts:
		var px := int(post.get("x", 0))
		var py := int(post.get("y", 0))
		# Wide enough to cover the rooms, the wings and the ground outside them.
		for dy in range(-26, 27):
			for dx in range(-26, 27):
				var wx := px + dx
				var wy := py + dy
				var want: Dictionary = _scan(posts, wx, wy)
				var got: Dictionary = cm.get_npc_post_at(wx, wy)
				checked += 1
				if not want.is_empty():
					inside += 1
				if String(want.get("name", "")) != String(got.get("name", "")):
					diff += 1
					if diff <= 3:
						print("      (%d,%d): scan says %s, index says %s" % [
							wx, wy, want.get("name", "(none)"), got.get("name", "(none)")])
	ck(diff == 0, "%d tiles compared, %d differ" % [checked, diff])
	ck(inside > 1000, "%d of them are INSIDE a post, so the true case is exercised too" % inside)

	print("\n--- and tiles far from any post still say no ---")
	var far_wrong := 0
	for i in range(2000):
		var wx := -1800 + i * 7
		var wy := 1500 - i * 3
		if String(_scan(posts, wx, wy).get("name", "")) != String(cm.get_npc_post_at(wx, wy).get("name", "")):
			far_wrong += 1
	ck(far_wrong == 0, "2000 scattered far tiles agree")

	print("\n--- the point of the change ---")
	var pts: Array = []
	var p0 = posts[0]
	for dy in range(-11, 12):
		for dx in range(-11, 12):
			pts.append(Vector2i(int(p0.get("x", 0)) + dx, int(p0.get("y", 0)) + dy))
	var REPS := 20
	var t0 := Time.get_ticks_usec()
	for r in range(REPS):
		for pt in pts:
			_scan(posts, pt.x, pt.y)
	var scan_ms := float(Time.get_ticks_usec() - t0) / float(REPS) / 1000.0
	var t1 := Time.get_ticks_usec()
	for r in range(REPS):
		for pt in pts:
			cm.get_npc_post_at(pt.x, pt.y)
	var idx_ms := float(Time.get_ticks_usec() - t1) / float(REPS) / 1000.0
	print("  529 lookups: scan %.2f ms -> index %.2f ms  (%.1fx)" % [
		scan_ms, idx_ms, scan_ms / maxf(0.001, idx_ms)])
	ck(idx_ms < scan_ms * 0.5, "the index is at least twice as fast on the worst case (inside a post)")

	print("\n[POSTINDEX] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
