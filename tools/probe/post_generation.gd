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

	print("\n--- the water rule asks HOW WET, not merely whether wet ---")
	# The old rule rejected on a single water tile anywhere in a 25x25 bubble. Show that such
	# sites exist and are now accepted — otherwise this fix would be indistinguishable from
	# simply deleting the check.
	var seed_v := 2178175570
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var one_or_two := 0
	var accepted := 0
	var soaked := 0
	var soaked_rejected := 0
	for i in range(240):
		var x := rng.randi_range(-600, 600)
		var y := rng.randi_range(-600, 600)
		if absi(x) < 30 and absi(y) < 30:
			continue
		var wet: int = NP._post_water_tiles(x, y, seed_v, 12)
		var rejected: bool = NP._location_has_nearby_water(x, y, seed_v)
		if wet >= 1 and wet <= 3:
			one_or_two += 1
			if not rejected:
				accepted += 1
		if wet > 40:
			soaked += 1
			if rejected:
				soaked_rejected += 1
	print("      %d sites with 1-3 water tiles, %d accepted" % [one_or_two, accepted])
	print("      %d genuinely soaked sites (>40 tiles), %d rejected" % [soaked, soaked_rejected])
	ck(one_or_two > 0, "the sample contains lightly-ponded sites (not a vacuous test)")
	ck(accepted == one_or_two, "a lone pond no longer refuses a whole trading post")
	ck(soaked == soaked_rejected, "a genuinely wet site is STILL rejected (a lake is not a pond)")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
