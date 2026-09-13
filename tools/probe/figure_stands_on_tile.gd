extends SceneTree
## What you are standing on must be drawn under you.
##
## Owner 2026-09-13: *"walking on roads is showing the grass under the player sprite instead of
## the road."*
##
## The player's own cell emitted `!player` with no tile after it, so the renderer had nothing to
## draw and fell through to the bare biome ground. It was never only roads - a bridge, a post
## floor, a station all vanished the moment you stood on them - and because you are always at the
## centre of your own view, it is the one cell a player looks at most.
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
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("===== FIND REAL GROUND THAT IS NOT PLAIN DIRT =====")
	# A road, specifically, because that is what was reported.
	# ⚑ SEARCH WHERE ROADS ARE. The first version of this walked expanding rings from the origin
	# out to radius 700, calling `get_tile` on each - which GENERATES CHUNKS - and ran for over
	# ten minutes without finding one. Roads join posts, so a small box around a post finds one
	# in a fraction of a second.
	var road := Vector2i(99999, 99999)
	var posts: Array = cm.get_npc_posts()
	for pi in range(mini(6, posts.size())):
		var p = posts[pi]
		var cx: int = int(p.get("x", 0))
		var cy: int = int(p.get("y", 0))
		for oy in range(-24, 25):
			for ox in range(-24, 25):
				if String(cm.get_tile(cx + ox, cy + oy).get("type", "")) == "path":
					road = Vector2i(cx + ox, cy + oy)
					break
			if road.x != 99999:
				break
		if road.x != 99999:
			break
	ck(road.x != 99999, "found a road tile at (%d,%d)" % [road.x, road.y])

	print("\n===== THE PAYLOAD NAMES IT =====")
	var payload: Dictionary = ws.build_map_payload(road.x, road.y, 11)
	var meaning: Array = payload.get("meaning", [])
	# The player is always the centre cell of their own view.
	var mrow = meaning[11]
	var cell := String(mrow[11])
	print("  the cell the player occupies reads: %s" % cell)
	ck(cell.begins_with("!player"), "it is the player marker")
	ck(cell.find(":") > 0, "and it NAMES a tile (was bare '!player', which drew nothing)")
	ck(cell == "!player:path", "specifically the road: got '%s'" % cell)

	print("\n===== AND THE RENDERER DRAWS IT =====")
	if not Room.available():
		print("  (art not present - skipping the pixel half)")
	else:
		# Render the player's cell twice: once standing on a road, once on bare ground. If the
		# road is drawn, the two differ. This is the check that a source read cannot make.
		var rows := 3
		var cols := 3
		var with_road: Array = [PackedStringArray(["empty", "empty", "empty"]),
			PackedStringArray(["empty", "!player:path", "empty"]),
			PackedStringArray(["empty", "empty", "empty"])]
		var bare: Array = [PackedStringArray(["empty", "empty", "empty"]),
			PackedStringArray(["empty", "!player", "empty"]),
			PackedStringArray(["empty", "empty", "empty"])]
		var biomes: Array = []
		for i in range(rows):
			biomes.append(PackedStringArray(["plains", "plains", "plains"]))
		var figs := {"1,1": "res://client/sprites/overworld_pad32/human_m_01.png"}

		Room._key = ""
		Room.build(with_road, biomes, figs)
		var a := Room._grid.duplicate()
		Room._key = ""
		Room.build(bare, biomes, figs)
		var b := Room._grid.duplicate()

		var diff := 0
		for y in range(Room.CELL):
			for x in range(Room.CELL):
				var pa: Color = a.get_pixel(Room.CELL + x, Room.CELL + y)
				var pb: Color = b.get_pixel(Room.CELL + x, Room.CELL + y)
				if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) > 0.02:
					diff += 1
		print("  %d of %d pixels under the player differ between road and bare ground" % [
			diff, Room.CELL * Room.CELL])
		ck(diff > 80, "the road is actually drawn beneath the figure")

	print("\n[FIGURETILE] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
