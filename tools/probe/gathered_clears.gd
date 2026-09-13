extends SceneTree
## A gathered node clears from the map, and the ground recovers.
##
## Owner 2026-09-13: *"gatherables should likely clear from the map once they are gathered then
## new ones pop up in other areas."*
##
## Two separate faults behind that. A spent node was DRAWN DIMMED, so a worked stand still looked
## full and you had to walk every tile to find out. And away from a post it was depleted
## PERMANENTLY - a bargain that made sense when gatherables covered a third of the world, and
## does not now they cover ~6%: every area a player works gets stripped and stays stripped, so
## the world only ever gets poorer.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()

	print("===== NOTHING IS STRIPPED FOREVER =====")
	# Three kinds of ground: water, beside a post, and out in the wild. The last was permanent.
	var posts: Array = cm.get_npc_posts()
	var near := Vector2i(int(posts[0].get("x", 0)) + 3, int(posts[0].get("y", 0)) + 3)
	# ⚑ ACTUALLY WILD. The first version took "a post plus 900 tiles" and landed beside a
	# DIFFERENT post - there are 120 of them spread across the whole world now, which is a change
	# I made myself. It then measured the post respawn time and reported the wild one as broken.
	var wild := Vector2i(0, 0)
	for r in range(200, 3000, 50):
		var candidate := Vector2i(r, r)
		if not cm._is_near_npc_post(candidate.x, candidate.y, ChunkManagerScript.POST_RESOURCE_RADIUS):
			wild = candidate
			break
	ck(wild != Vector2i(0, 0), "found ground genuinely away from every post: (%d,%d)" % [wild.x, wild.y])
	var now := Time.get_unix_time_from_system()

	cm.deplete_node(wild.x, wild.y, "tree")
	var wild_until: float = float(cm.depleted_nodes.get("%d,%d" % [wild.x, wild.y], 0))
	ck(wild_until != ChunkManagerScript.DEPLETED_PERMANENT,
		"a tree gathered in the wild is NOT permanent any more")
	ck(wild_until > now, "...it recovers in about %d minutes" % int((wild_until - now) / 60.0))

	cm.deplete_node(near.x, near.y, "tree")
	var near_until: float = float(cm.depleted_nodes.get("%d,%d" % [near.x, near.y], 0))
	ck(near_until > now and near_until <= wild_until,
		"ground beside a post recovers at least as fast (%d min vs %d)" % [
			int((near_until - now) / 60.0), int((wild_until - now) / 60.0)])

	print("\n===== AND A SPENT NODE IS GONE FROM THE MAP =====")
	if not Room.available():
		print("  (art not present - skipping the pixel half)")
	else:
		# Compose a fresh tree and a gathered one. Gathered must look like BARE GROUND, not like
		# a dimmed tree - that was the whole complaint.
		var biomes: Array = []
		for i in range(5):
			biomes.append(PackedStringArray(["plains", "plains", "plains", "plains", "plains"]))
		var g_tree: Array = []
		var g_bare: Array = []
		for y in range(5):
			var a := PackedStringArray()
			var b := PackedStringArray()
			for x in range(5):
				a.append("tree" if (x == 2 and y == 3) else "empty")
				b.append("empty")
			g_tree.append(a)
			g_bare.append(b)
		Room._key = ""
		Room.build(g_tree, biomes, {})
		var with_tree := Room._grid.duplicate()
		Room._key = ""
		Room.build(g_bare, biomes, {})
		var bare := Room._grid.duplicate()

		var diff := 0
		for y in range(bare.get_height()):
			for x in range(bare.get_width()):
				var c1: Color = with_tree.get_pixel(x, y)
				var c2: Color = bare.get_pixel(x, y)
				if absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b) > 0.02:
					diff += 1
		ck(diff > 200, "a tree and bare ground differ by %d pixels, so 'cleared' is visible" % diff)

	print("\n===== THE MAP SAYS SO =====")
	var wsrc := FileAccess.get_file_as_string("res://shared/world_system.gd")
	ck(wsrc.find('sem_parts.append("empty")') >= 0,
		"a gathered node reports as EMPTY GROUND, not as a dimmed copy of itself")
	ck(wsrc.find('sem_parts.append("!depleted:" + tile_type)') < 0,
		"the dimmed-ghost path is gone")
	ck(wsrc.find('sem_parts.append("!hotdepleted")') >= 0,
		"...and inside a hotzone the warning stays, over bare ground")

	print("\n[GATHEREDCLEARS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
