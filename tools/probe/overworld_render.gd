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
		[{"x": 41, "y": 40, "name": "Kestrel", "in_my_party": true, "appearance_variant": "1_1",
			"companion": {"monster_type": "Wolf", "variant_color": "#39FF14",
				"variant_color2": "", "variant_pattern": "solid"}}],
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
	# A FIGURE on the centre cell - you. The overworld already carries 80 player looks; the
	# renderer draws what it is handed rather than choosing.
	# `overworld_pad32`, NOT `overworld_floor32`. The floor-backed set has the dungeon floor baked
	# into every frame, because BBCode could not composite there; here the renderer composites, so
	# a figure must be transparent or it arrives standing on a square of someone else's ground.
	var me := "res://client/sprites/overworld_pad32/1_1/down_stand.png"
	var figures: Dictionary = {"11,11": me} if ResourceLoader.exists(me) else {}
	ck(Room.build(meaning, biomes, figures), "the renderer builds a map from it")
	ck(not figures.is_empty(), "and a player figure is available to stand on the centre cell")
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

	print("\n--- and a figure replaces the marker rather than sitting beside it ---")
	var src2 := FileAccess.get_file_as_string("res://client/overworld_room.gd")
	ck(src2.find('and not figures.has("%d,%d" % [x, y])') >= 0,
		"the overlay glyph is skipped where a figure stands")
	ck(src2.find("(y + 1) * CELL - fi.get_height()") >= 0,
		"and a figure is anchored to the bottom of its cell, so a tall one stands on its tile")

	print("
--- the display string the client will show ---")
	# The map becomes images; everything AROUND it must not move, or the header and the sprite
	# overlay drift apart. This compares the sprite display against the text one it replaces.
	var text_form: String = MapPayload.inflate(payload)
	var sprite_form: String = MapPayload.inflate_sprites(payload,
		func(x: int, y: int) -> String:
			var c: String = Room.cell_path(x, y)
			return "[img=26x26]%s[/img]" % c if c != "" else "  ")
	var imgs := sprite_form.count("[img=26x26]")
	ck(imgs == 23 * 23, "the map is %d images, one per square" % imgs)
	ck(sprite_form.find("[center]") >= 0 and text_form.find("[center]") >= 0,
		"the [center] wrapper survives, so the map sits where it did")
	ck(sprite_form.count("minimap (") == text_form.count("minimap ("),
		"the minimap is still there, still text - only the map was sprited")
	var head_t := text_form.substr(0, text_form.find("[center]"))
	var head_s := sprite_form.substr(0, sprite_form.find("[center]"))
	ck(head_t == head_s, "and the header is byte-identical, so nothing above the map shifted")

	print("
--- other players, and the companions walking with them ---")
	# The client is sent resolved cells, not a roster, so it cannot know who is out there or what
	# they look like. The server names them.
	var pf: Dictionary = payload.get("figures", {})
	ck(not pf.is_empty(), "the payload names %d other player figure(s)" % pf.size())
	var with_comp := 0
	for k in pf:
		var ent: Dictionary = pf[k]
		ck(String(ent.get("id", "")) != "", "figure at %s carries a look id" % k)
		if ent.has("companion"):
			with_comp += 1
			ck(String(ent["companion"].get("monster_type", "")) != "",
				"...and its companion names a species")
	var rsrc := FileAccess.get_file_as_string("res://client/overworld_room.gd")
	ck(rsrc.find('behind = String(fig_entry.get("behind", ""))') >= 0,
		"the renderer draws a companion BEHIND its owner rather than instead of them")
	var dsrc := FileAccess.get_file_as_string("res://client/dungeon_composite.gd")
	ck(dsrc.find("static func cutout(") >= 0,
		"and a companion's baked dungeon floor is cut out first")
	ck(dsrc.substr(dsrc.find("static func cutout("), 1400).find("_background_mask(sprite_path, img)") >= 0,
		"...by the same colour key that tints it, so the two compose")

	print("
--- and every fallback lands on the text map ---")
	# A map that will not draw is worse than a map made of letters.
	ck(MapPayload.inflate_sprites({}, func(_x, _y): return "x") == "",
		"an empty payload yields nothing rather than erroring")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var body_start := cli.find("func _overworld_display(")
	var body := cli.substr(body_start, cli.find("
func ", body_start + 10) - body_start)
	ck(body.count("return MapPayload.inflate(payload)") == 3,
		"the client falls back to the text map on all three failures (art, payload, renderer)")
	ck(cli.find("overworld_pad32/%s/%s%s.png") >= 0,
		"and the player figure comes from the TRANSPARENT sprite set")

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
