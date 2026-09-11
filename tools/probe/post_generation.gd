extends SceneTree
## Post generation must actually place posts.
##
## 2026-09-11: `generate_posts` returned ONE post — the starter — for every seed tried, so a world
## regenerated from scratch had no trading posts at all. It stayed invisible because the live
## world's 60 posts were generated before the water check existed and have persisted in
## npc_posts.json ever since; nothing regenerates them in normal play. A map reset did, and the
## world came back with one post.
const NP := preload("res://shared/npc_post_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- a world gets its posts, whatever seed it has ---")
	var seeds := [2178175570, 1009317153301, 7, 424242, 999999999999, 1]
	for s in seeds:
		var posts: Array = NP.generate_posts(s)
		ck(posts.size() >= 50, "seed %d places %d posts (target 60)" % [s, posts.size()])

	print("\n--- and they are still spaced and seeded properly ---")
	var p1: Array = NP.generate_posts(424242)
	var mind := 999999.0
	for i in range(p1.size()):
		for j in range(i + 1, p1.size()):
			var dx: float = float(int(p1[i].x) - int(p1[j].x))
			var dy: float = float(int(p1[i].y) - int(p1[j].y))
			mind = minf(mind, sqrt(dx * dx + dy * dy))
	print("      closest pair: %.0f tiles" % mind)
	ck(mind >= 70.0, "minimum spacing is still honoured")
	var p2: Array = NP.generate_posts(424242)
	ck(p1.size() == p2.size() and int(p1[5].x) == int(p2[5].x) and int(p1[5].y) == int(p2[5].y),
		"the same seed gives the same world (generation is deterministic)")
	var p3: Array = NP.generate_posts(99)
	ck(int(p3[5].x) != int(p1[5].x) or int(p3[5].y) != int(p1[5].y),
		"a different seed gives a different layout")

	print("")
	print("--- water does not gate placement at all any more ---")
	# Owner 2026-09-11: "Posts should overwrite any type of tile that was already down. Water
	# shouldn't be an obstruction moving forward." A post is stamped as tile DELTAS, which
	# overwrite the terrain underneath, so a post on a lake is simply a post.
	var src := FileAccess.get_file_as_string("res://shared/npc_post_database.gd")
	ck(not src.contains("_location_has_nearby_water("),
		"the any-water rejection is gone entirely, not merely relaxed")
	ck(not src.contains("_location_has_water_in_margin("),
		"and so is the densify variant of it")
	var ws = load("res://shared/world_system.gd").new()
	var seed_w := 424242
	var pw: Array = NP.generate_posts(seed_w)
	var on_water := 0
	for q in pw:
		var t: Dictionary = ws.generate_tile(int(q.x), int(q.y), seed_w)
		if String(t.get("type", "")) in ["water", "deep_water"]:
			on_water += 1
	print("      %d of %d posts sit on water (allowed - the stamp overwrites it)"
		% [on_water, pw.size()])
	ck(pw.size() >= 50, "and the target count is still met with no water filtering")
	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
