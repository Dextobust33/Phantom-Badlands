extends SceneTree
## Does doubling the number of posts bring the lag back?
##
## Owner 2026-09-13: *"Ensure we aren't introducing a new lag problem with all the new posts."*
##
## A fair worry and the right instinct: walking every post per tile IS what made a step cost
## 28 ms, and `POST_COUNT_TARGET` just went 60 -> 120 with the placement radius 600 -> 2600. If
## the lookup were still linear this change would double the very cost that was just removed.
##
## The index makes a lookup bucket-local, so it should be FLAT in the number of posts - but
## "should be" is what this file exists to disprove. Measured at 60, 120 and 240.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const NPD = preload("res://shared/npc_post_database.gd")

const REPS := 20

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _measure(posts: Array) -> Dictionary:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.npc_posts = posts
	cm._invalidate_post_index()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	# Warm the chunks so we time the lookup and not terrain generation.
	var explored := {}
	ws.build_map_payload(40, 40, 11, [], [], [], [], [], explored, [], false, [])

	var t0 := Time.get_ticks_usec()
	for i in range(REPS):
		ws.build_map_payload(40 + i, 40, 11, [], [], [], [], [], explored, [], false, [])
	var step_ms := float(Time.get_ticks_usec() - t0) / float(REPS) / 1000.0

	# And the lookup itself, at grid scale - the thing that was linear.
	var t1 := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-11, 12):
			for dx in range(-11, 12):
				cm.get_npc_post_at(40 + dx, 40 + dy)
	var look_ms := float(Time.get_ticks_usec() - t1) / float(REPS) / 1000.0

	cm.queue_free()
	ws.queue_free()
	return {"step": step_ms, "look": look_ms}


func _init() -> void:
	var base = ChunkManagerScript.new()
	get_root().add_child(base)
	base.load_world_seed()
	base.load_npc_posts()
	var live: Array = base.get_npc_posts()

	print("\n===== COST AGAINST THE NUMBER OF POSTS =====")
	print("%8s %14s %18s" % ["posts", "step (ms)", "529 lookups (ms)"])
	var results := {}
	for target in [60, 120, 240]:
		# Build a post set of the requested size from the real generator, so these are real
		# posts with real rooms and wings rather than a convenient fixture.
		var posts: Array = live.duplicate(true)
		while posts.size() > target:
			posts.remove_at(posts.size() - 1)
		# `densify_posts` stops at POST_COUNT_TARGET, so it cannot build a set larger than the
		# configured target. To test ABOVE it, clone posts to fresh coordinates - real rooms and
		# wings, just more of them. Without this the 240 row silently measured 120 and the check
		# passed having tested nothing, which is worse than no check.
		var guard := 0
		while posts.size() < target and guard < 8:
			posts = NPD.densify_posts(posts, base.world_seed + guard)
			guard += 1
		var clone_i := 0
		while posts.size() < target:
			var src: Dictionary = (live[clone_i % live.size()] as Dictionary).duplicate(true)
			src["x"] = int(src.get("x", 0)) + 40 + clone_i * 7
			src["y"] = int(src.get("y", 0)) - 40 - clone_i * 5
			src["name"] = "%s Clone %d" % [String(src.get("name", "Post")), clone_i]
			posts.append(src)
			clone_i += 1
		while posts.size() > target:
			posts.remove_at(posts.size() - 1)
		var m: Dictionary = _measure(posts)
		m["n"] = posts.size()
		results[target] = m
		print("%8d %14.2f %18.2f" % [posts.size(), m["step"], m["look"]])

	print("\n--- the question the owner asked ---")
	var a: float = float(results[60]["step"])
	var b: float = float(results[120]["step"])
	var c: float = float(results[240]["step"])
	ck(b < a * 1.35, "doubling posts (60 -> 120) does not meaningfully raise the per-step cost (%.2f -> %.2f ms)" % [a, b])
	ck(int(results[240]["n"]) >= 240,
		"the 240-post case really built %d posts, not the target's cap" % int(results[240]["n"]))
	ck(c < a * 1.6, "and quadrupling it still does not (%.2f ms at %d posts)" % [c, int(results[240]["n"])])
	ck(b < 12.0, "a step stays well under the 28 ms it cost before the index (%.2f ms)" % b)
	print("\nIf these pass, the cost is flat in the number of posts - which is what the bucket")
	print("index was for, and the reason more posts is now a design choice rather than a budget.")
	print("\n[POSTCOST] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
