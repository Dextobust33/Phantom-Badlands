extends SceneTree
## Are there enough posts to navigate BY?
##
## Owner 2026-09-13: *"We may want to take a look at post distribution and ensure we have a
## sufficient number of posts for people to navigate to while exploring."*
##
## This is load-bearing now. Measured earlier: from the ORIGIN a player must walk much further to
## reach country at their level (L100 moved from radius 234 to 900), but from the NEAREST POST
## suitable ground is within ten tiles - because posts anchor the level to their own country. So
## the whole travel design rests on a player being able to FIND a post. If posts are sparse, the
## reshape traded one walking problem for another.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const PR = preload("res://shared/power_rank.gd")


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws
	const NPD = preload("res://shared/npc_post_database.gd")
	var live: Array = cm.get_npc_posts()
	# What the SERVER will have on its next boot, not what is on disk: `densify_posts` tops an
	# existing world up to POST_COUNT_TARGET, so measuring the file alone reports yesterday.
	var posts: Array = NPD.densify_posts(live.duplicate(true), cm.world_seed)

	print("\n===== POST SPACING =====")
	print("posts on disk: %d   after densify (what the server will run): %d" % [live.size(), posts.size()])

	# How far is a random point from the nearest post? Sampled over the disc, which is what a
	# player standing anywhere actually faces.
	var dists: Array = []
	var far := 0
	for i in range(4000):
		var r: float = sqrt(randf()) * 2828.0
		var a: float = randf() * TAU
		var gx := int(cos(a) * r)
		var gy := int(sin(a) * r)
		var best := 1 << 30
		for p in posts:
			var dx: int = gx - int(p.get("x", 0))
			var dy: int = gy - int(p.get("y", 0))
			var d2: int = dx * dx + dy * dy
			if d2 < best:
				best = d2
		var d: int = int(sqrt(float(best)))
		dists.append(d)
		if d > 400:
			far += 1
	dists.sort()
	print("\ndistance from a random spot to the NEAREST post:")
	print("  median   %d tiles" % dists[dists.size() / 2])
	print("  75th     %d tiles" % dists[int(dists.size() * 0.75)])
	print("  95th     %d tiles" % dists[int(dists.size() * 0.95)])
	print("  worst    %d tiles" % dists[dists.size() - 1])
	print("  %.1f%% of the world is more than 400 tiles from any post" % (100.0 * float(far) / 4000.0))

	# And the shape that matters most: are posts spread across the GRADES, or clustered in the
	# middle where the old level curve put everything?
	print("\nposts by the grade of country they stand in:")
	var by_grade := {}
	for p in posts:
		var lvl: int = int(ws.get_post_anchored_level(int(p.get("x", 0)), int(p.get("y", 0))))
		var t := int(PR.grade_for_level(maxi(1, lvl)).get("tier", 1))
		by_grade[t] = int(by_grade.get(t, 0)) + 1
	for t in range(1, 10):
		if by_grade.has(t):
			print("  %s : %d post(s)" % [PR.letter(t), int(by_grade[t])])

	# The practical test: standing at a post, can you SEE or reach another one?
	var nn: Array = []
	for p in posts:
		var best := 1 << 30
		for q in posts:
			if q == p:
				continue
			var dx: int = int(p.get("x", 0)) - int(q.get("x", 0))
			var dy: int = int(p.get("y", 0)) - int(q.get("y", 0))
			best = mini(best, dx * dx + dy * dy)
		nn.append(int(sqrt(float(best))))
	nn.sort()
	print("\npost-to-nearest-neighbour distance:")
	print("  median %d tiles, worst %d tiles" % [nn[nn.size() / 2], nn[nn.size() - 1]])
	print("\nA player leaving a post should have a reasonable chance of finding the next one.")
	print("If the median hop is far beyond a comfortable journey, the network is too sparse to")
	print("navigate BY, however many posts there are in total.")
	quit(0)
