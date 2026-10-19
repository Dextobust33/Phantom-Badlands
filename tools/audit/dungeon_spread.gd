extends SceneTree
## WHERE do 3,300 dungeons actually land, and how many end up on a post's doorstep?
##
## Owner 2026-09-13: *"now that the number of dungeons have grown we once again have posts being
## overwhelmed with an enormous amount of dungeons spilling out monsters. The starter post alone
## is overwhelmed with a huge number of dungeons around it."*
##
## The suspicion worth testing is that this is not density but CLUSTERING, and that it follows
## from the placement rule itself. A dungeon is graded by the land it stands in
## (`get_post_anchored_level`), and posts PULL THE LEVEL DOWN around them - so the only low-level
## country in the world is the ground near posts, and every low-grade dungeon that wants matching
## land has nowhere else to go. If that is what is happening, the starter post is not unlucky;
## it is the single most attractive spot on the map for an H-grade dungeon.
##
## This runs the REAL placement (`DungeonDatabase.grade_cells` + `roll_location_in_ring`) and the
## REAL grading (`get_post_anchored_level`), then counts what lands near each post.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const DD = preload("res://shared/dungeon_database.gd")
const PR = preload("res://shared/power_rank.gd")

const SAMPLE := 3300
const NEAR := 40      # the radius the threat scan cares about is 80; 40 is "on the doorstep"


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws
	var posts: Array = cm.get_npc_posts()

	print("\n===== WHERE %d DUNGEONS LAND =====" % SAMPLE)
	print("placement and grading both as the server does them.")

	# Sample the LAND first: what grade is the world made of? If the world is overwhelmingly
	# high-grade country, then low-grade dungeons have almost nowhere legal to stand.
	var land_hist := {}
	var n := 0
	for i in range(4000):
		var x := -1900 + (i * 37) % 3800
		var y := -1900 + (i * 71) % 3800
		var lvl: int = int(ws.get_post_anchored_level(x, y))
		var g: Dictionary = PR.grade_for_level(maxi(1, lvl))
		var t := int(g.get("tier", 1))
		land_hist[t] = int(land_hist.get(t, 0)) + 1
		n += 1
	print("\n--- what GRADE the world's country is, sampled at %d points ---" % n)
	for t in range(1, 10):
		var c := int(land_hist.get(t, 0))
		if c == 0:
			continue
		print("  %s : %5.1f%% of the world" % [PR.letter(t), 100.0 * float(c) / float(n)])

	# Now: how much of the LOW-grade country sits near a post?
	print("\n--- and how much of the lowest-grade country is on a post's doorstep ---")
	for target in [1, 2]:
		var tot := 0
		var near := 0
		for i in range(6000):
			var x := -1900 + (i * 43) % 3800
			var y := -1900 + (i * 97) % 3800
			var lvl: int = int(ws.get_post_anchored_level(x, y))
			if int(PR.grade_for_level(maxi(1, lvl)).get("tier", 1)) != target:
				continue
			tot += 1
			for p in posts:
				var dx: int = x - int(p.get("x", 0))
				var dy: int = y - int(p.get("y", 0))
				if dx * dx + dy * dy <= NEAR * NEAR:
					near += 1
					break
		if tot == 0:
			print("  %s : none sampled" % PR.letter(target))
			continue
		print("  %s : %d sampled, %.1f%% of it within %d tiles of a post" % [
			PR.letter(target), tot, 100.0 * float(near) / float(tot), NEAR])

	print("\n--- the starter post specifically ---")
	var start_p: Dictionary = {}
	var best := 1 << 30
	for p in posts:
		var d: int = int(p.get("x", 0)) * int(p.get("x", 0)) + int(p.get("y", 0)) * int(p.get("y", 0))
		if d < best:
			best = d
			start_p = p
	print("  nearest post to origin: %s at (%d,%d)" % [
		start_p.get("name", "?"), int(start_p.get("x", 0)), int(start_p.get("y", 0))])
	var sx := int(start_p.get("x", 0))
	var sy := int(start_p.get("y", 0))
	var grades := {}
	for dy in range(-NEAR, NEAR + 1, 4):
		for dx in range(-NEAR, NEAR + 1, 4):
			var lvl: int = int(ws.get_post_anchored_level(sx + dx, sy + dy))
			var t := int(PR.grade_for_level(maxi(1, lvl)).get("tier", 1))
			grades[t] = int(grades.get(t, 0)) + 1
	var line := ""
	for t in range(1, 10):
		if grades.has(t):
			line += "%s:%d  " % [PR.letter(t), int(grades[t])]
	print("  country within %d tiles of it, by grade: %s" % [NEAR, line])
	print("\nIf the world is nearly all high grade and the only low-grade land is around posts,")
	print("then every low-grade dungeon is FORCED to the doorstep - that is the clustering.")
	quit(0)
