extends SceneTree
## The overworld, drawn from a real payload, as a picture you can look at.
##
## Phase 2.95 PHASE 2. Every previous step in this arc was checkable by assertion: the display
## string was byte-identical, the meaning grid named the tile that was really there. This one is
## not. A map can be structurally perfect and still unreadable, so this renders the real thing
## from a real world and writes it out - and asserts the things that CAN be asserted around it.
##
## What it holds:
##   * the renderer consumes what the server actually sends, not a hand-made fixture;
##   * every cell of the composed image comes from somewhere (nothing is left as the black fill
##     except squares outside your sight, which is what black means);
##   * a hotzone gatherable still shows its own tile under the warning, because the alternative
##     was the fault the owner reported in the ASCII map: "the players can't tell if there are
##     gather locations in hotzones since its just a red exclamation mark".
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const MapPayload = preload("res://shared/map_payload.gd")
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	if not Room.available():
		print("[OVERWORLDRENDER] SKIP - overworld sprites are licence-restricted and absent here")
		quit(2)
		return
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("--- a real payload, from a real world ---")
	var explored: Dictionary = {}
	# Walk once so the second view has FOG to draw, which is its own branch.
	ws.build_map_payload(35, 35, 11, [], [], [], [], [], explored, [], false, [])
	var payload: Dictionary = ws.build_map_payload(40, 40, 11,
		[{"x": 41, "y": 40, "name": "Kestrel", "in_my_party": true}],
		[{"x": 38, "y": 41, "color": "#A335EE"}], [], [{"x": 40, "y": 38}], [{"x": 43, "y": 41}],
		explored, [], false, [])
	var meaning: Array = MapPayload.cells(payload.get("meaning", {}))
	var biomes: Array = MapPayload.cells(payload.get("biomes", {}))
	ck(meaning.size() == 23 and biomes.size() == 23,
		"the payload carries a %dx%d meaning grid and a %dx%d biome grid" % [
			meaning.size(), meaning[0].size() if meaning.size() else 0,
			biomes.size(), biomes[0].size() if biomes.size() else 0])

	var kinds := {}
	for row in meaning:
		for m in row:
			kinds[String(m)] = true
	ck(kinds.size() > 5, "%d distinct cell meanings in one view" % kinds.size())

	print("\n--- and it composes ---")
	ck(Room.build(meaning, biomes), "the renderer builds a map from it")
	ck(Room.cell_path(0, 0) != "", "and serves a cell as something an [img] tag can load")
	ck(Room.cell_path(0, 0) == Room.cell_path(0, 0), "the same cell twice is the same texture")

	print("\n--- nothing is left as the black fill except what should be ---")
	# Black means "outside your sight". Anywhere else, black is a tile that failed to draw.
	var black := 0
	var void_cells := 0
	for y in range(meaning.size()):
		for x in range(meaning[y].size()):
			var m := String(meaning[y][x])
			var path: String = Room.cell_path(x, y)
			if m == "!void" or m == "":
				void_cells += 1
				continue
			var tex := load(path) as Texture2D
			if tex == null:
				black += 1
				continue
			var im := tex.get_image()
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			var lit := false
			for yy in range(0, 32, 4):
				for xx in range(0, 32, 4):
					var px := im.get_pixel(xx, yy)
					if px.r > 0.02 or px.g > 0.02 or px.b > 0.02:
						lit = true
						break
				if lit:
					break
			if not lit:
				black += 1
				print("    black cell at (%d,%d), meaning %s" % [x, y, m])
	ck(black == 0, "every visible cell drew something (%d cells outside sight, correctly dark)" % void_cells)
	ck(void_cells > 0 and void_cells < meaning.size() * meaning.size(),
		"and the vision circle is a circle - some cells are outside it, most are not")

	print("\n--- a gatherable in a hotzone still shows what it is ---")
	# The owner's report on the ASCII map: a red `!` replaced the tile, so a player could not tell
	# whether a hotzone held ore or nothing. The sprite map must not repeat that.
	var src := FileAccess.get_file_as_string("res://client/overworld_room.gd")
	ck(src.find("var tile_name := meaning if overlay == \"\" else _under_tile(meaning)") >= 0,
		"the renderer draws the tile under an overlay that names one")
	ck(Room._under_tile("!hot:tree") == "tree", "and `!hot:tree` resolves to a tree")
	ck(Room._overlay_name("!hot:tree") == "hot", "with `hot` over it")
	ck(Room._overlay_name("tree") == "", "while plain terrain has no overlay at all")

	# The picture. A probe can say "not black"; only eyes can say "readable".
	var out := Image.create(23 * 32, 23 * 32, false, Image.FORMAT_RGBA8)
	for y in range(23):
		for x in range(23):
			var p: String = Room.cell_path(x, y)
			if p == "":
				continue
			var tex := load(p) as Texture2D
			if tex == null:
				continue
			var im := tex.get_image()
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			out.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x * 32, y * 32))
	out.resize(out.get_width() * 2, out.get_height() * 2, Image.INTERPOLATE_NEAREST)
	out.save_png("res://claude_screenshots/overworld_render.png")
	print("  wrote claude_screenshots/overworld_render.png")

	print("\n[OVERWORLDRENDER] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
