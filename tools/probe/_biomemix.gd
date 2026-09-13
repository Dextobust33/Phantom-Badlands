extends SceneTree
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
func _init() -> void:
	var cm = ChunkManagerScript.new(); get_root().add_child(cm)
	cm.load_world_seed(); cm.load_npc_posts()
	var ws = WorldSystemScript.new(); get_root().add_child(ws)
	ws.chunk_manager = cm; cm.terrain_generator = ws
	var seed_v: int = cm.world_seed
	var counts := {}
	var n := 0
	for y in range(-200, 201, 3):
		for x in range(-600, 601, 3):
			var b := String(ws.get_biome_at(x, y, seed_v))
			counts[b] = int(counts.get(b, 0)) + 1
			n += 1
	print("biome mix over %d sampled tiles:" % n)
	var ks: Array = counts.keys(); ks.sort()
	for k in ks:
		print("  %-12s %5.2f%%" % [k, 100.0 * float(counts[k]) / float(n)])
	# And how much of the world is within reach of a post, by biome.
	print("\nbiome mix within 60 tiles of the first 12 posts:")
	var near := {}
	var m := 0
	var posts: Array = cm.get_npc_posts()
	for i in range(mini(12, posts.size())):
		var p = posts[i]
		for dy in range(-60, 61, 4):
			for dx in range(-60, 61, 4):
				var b2 := String(ws.get_biome_at(int(p.x) + dx, int(p.y) + dy, seed_v))
				near[b2] = int(near.get(b2, 0)) + 1
				m += 1
	var ks2: Array = near.keys(); ks2.sort()
	for k in ks2:
		print("  %-12s %5.2f%%" % [k, 100.0 * float(near[k]) / float(m)])
	quit(0)
