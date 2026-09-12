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
const PR = preload("res://shared/power_rank.gd")

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
		[{"x": 38, "y": 41, "color": "#A335EE", "name": "Goblin Caves", "tier": 1, "sub_tier": 4,
			"min_level": 4, "max_level": 5}],
		[], [{"x": 40, "y": 38}], [{"x": 43, "y": 41}],
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

	# THE CHECK THAT WOULD HAVE CAUGHT IT. Every assertion above reads the SOURCE, and the source
	# was right - every line the probe looked for was present. What was wrong was the INDENTATION:
	# the figure block sat inside the `not figures.has(...)` branch, a condition that is false
	# exactly when there is a figure. It compiled, it read correctly, and it drew nobody. Two
	# releases went out with an empty square where the player should be.
	#
	# So: compose the same view twice, once without a figure and once with, and compare the PIXELS
	# of the centre cell. There is no way to pass this without the figure actually being drawn.
	#
	# AND THE CONTROL MATTERS AS MUCH AS THE TEST. The first version of this check compared "no
	# figures at all" against "a figure", and PASSED against the broken code - because supplying a
	# figure also SUPPRESSES the overlay glyph on that cell, so 175 pixels changed without anyone
	# being drawn. The control is now an entry that is PRESENT but names no sprite: the overlay is
	# suppressed either way, so every pixel that moves is the figure itself.
	var _bare_ok := Room.build(meaning, biomes, {"11,11": ""})
	var bare_px := _cell_pixels(11, 11)
	var _fig_ok := Room.build(meaning, biomes, figures)
	var fig_px := _cell_pixels(11, 11)
	ck(bare_px.size() == 1024 and fig_px.size() == 1024, "the centre cell reads back as 32x32 pixels")
	var moved := 0
	for i in range(mini(bare_px.size(), fig_px.size())):
		if not bare_px[i].is_equal_approx(fig_px[i]):
			moved += 1
	ck(moved > 40, "%d of 1024 centre pixels CHANGE when a figure is supplied - the player is drawn" % moved)

	# Drawn BIGGER than the square it stands on. Owner 2026-09-12: *"the player sprite still looks
	# a little small on the overworld map."* The art is 32x32 with padding around a body about 17
	# wide, and the grid then draws a cell at 26 screen pixels.
	var raw := Room._img(me)
	var big := Room._figure_img(me)
	ck(raw != null and big != null and big.get_width() > raw.get_width(),
		"a figure is composed at %dpx against a %dpx cell" % [
			big.get_width() if big != null else 0, Room.CELL])
	ck(raw != null and raw.get_width() == 32,
		"...and the source art is untouched at %dpx, so scaling a figure cannot scale a tile" % [
			raw.get_width() if raw != null else 0])

	# And the companion stands on its OWN square - the one its owner walked out of - rather than
	# on top of its owner. Owner 2026-09-12: *"The companion will still follow behind the player
	# like before right?"* It did on the letter map; the first composed map drew it on the
	# player's square where the player covered it.
	var comp := "res://client/sprites/overworld_pad32/1_2/down_stand.png"
	if ResourceLoader.exists(comp):
		var trail_bare := _cell_pixels(10, 11)
		Room.build(meaning, biomes, {"11,11": me, "10,11": {"main": comp}})
		var trail_px := _cell_pixels(10, 11)
		var moved2 := 0
		for i in range(mini(trail_bare.size(), trail_px.size())):
			if not trail_bare[i].is_equal_approx(trail_px[i]):
				moved2 += 1
		ck(moved2 > 40, "%d pixels change on the square BEHIND you - the companion trails" % moved2)
		var still_me := _cell_pixels(11, 11)
		var owner_moved := 0
		for i in range(mini(fig_px.size(), still_me.size())):
			if not fig_px[i].is_equal_approx(still_me[i]):
				owner_moved += 1
		ck(owner_moved == 0, "and your own square is unchanged by it (%d pixels)" % owner_moved)
	# Leave the renderer holding the view the pictures below expect.
	Room.build(meaning, biomes, figures)

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
	# The companion trailing behind is asserted by PIXELS above ("pixels change on the square
	# BEHIND you"), not by searching the source for an argument list. The source version of this
	# check broke the moment the call gained a fourth argument, while the behaviour was untouched
	# - which is the whole argument against source-reading checks in one line.
	var cli_t := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli_t.find('if figures.has(ck2):') >= 0,
		"a companion is never placed over another person standing there")
	var dsrc := FileAccess.get_file_as_string("res://client/dungeon_composite.gd")
	ck(dsrc.find("static func cutout(") >= 0,
		"and a companion's baked dungeon floor is cut out first")
	ck(dsrc.substr(dsrc.find("static func cutout("), 1400).find("_background_mask(sprite_path, img)") >= 0,
		"...by the same colour key that tints it, so the two compose")

	print("
--- a dungeon entrance can be hovered ---")
	# With three thousand dungeons in the world, an H4 and an S9 are the same purple marker
	# until you can ask. The server is the only side that knows which is which.
	var dg: Dictionary = payload.get("dungeons", {})
	ck(not dg.is_empty(), "the payload names %d dungeon entrance(s) in view" % dg.size())
	for k in dg:
		var d: Dictionary = dg[k]
		ck(String(d.get("name", "")) != "", "entrance at %s has a name" % k)
		ck(int(d.get("tier", 0)) > 0 and int(d.get("rank", 0)) > 0,
			"...and a grade (%s%d)" % [PR.letter(int(d.get("tier", 1))), int(d.get("rank", 0))])
		ck(int(d.get("hi", 0)) >= int(d.get("lo", 0)) and int(d.get("lo", 0)) > 0,
			"...and the levels inside (%d-%d)" % [int(d.get("lo", 0)), int(d.get("hi", 0))])
	# The fixture above is shaped like what `get_visible_dungeons` returns, so check the SERVER
	# really fills those fields - otherwise this tests the fixture and nothing else.
	var srv2 := FileAccess.get_file_as_string("res://server/server.gd")
	var gvd_i := srv2.find("func get_visible_dungeons(")
	var gvd := srv2.substr(gvd_i, srv2.find("
func ", gvd_i + 10) - gvd_i)
	for field in ['"name":', '"tier":', '"sub_tier":', '"min_level":', '"max_level":']:
		ck(gvd.find(field) >= 0, "get_visible_dungeons sends %s" % field.replace('"', "").replace(":", ""))

	var cli2 := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli2.find('return "[url=owdg:%s]%s[/url]" % [dkey, img]') >= 0,
		"the client wraps an entrance cell in a url, which is what makes it hoverable")
	ck(cli2.find('if m.begins_with("owdg:"):') >= 0, "and handles that hover")
	ck(cli2.find("func _show_overworld_dungeon_hover(") >= 0, "...through one function")
	var hov_i := cli2.find("func _show_overworld_dungeon_hover(")
	var hov := cli2.substr(hov_i, cli2.find("
func ", hov_i + 10) - hov_i)
	ck(hov.find("PowerRank.label(tier, rank)") >= 0,
		"...which shows the GRADE, the thing that tells an H4 from an S9")
	ck(hov.find("monsters Lv %d-%d") >= 0, "...and the levels inside it")

	print("
--- the OLD text-map overlay must not fight the composed map ---")
	# Four reports, one cause. `_sync_map_sprites_overlay` places the player and companion
	# letters from FONT metrics - char width times two, the font line height, a sprite size
	# derived from the font size. None of that describes a grid of 26-pixel images, so in sprite
	# mode it drew the player a row off and companions as bare letters, and everything else
	# looked shifted relative to where the player appeared to be.
	var cli3 := FileAccess.get_file_as_string("res://client/client.gd")
	var sync_i := cli3.find("func _sync_map_sprites_overlay(")
	var sync := cli3.substr(sync_i, cli3.find("
func ", sync_i + 10) - sync_i)
	ck(sync.find("if overworld_sprites and _OverworldRoom.available() and not dungeon_mode:") >= 0,
		"the overlay stands down when the map is art")
	var guard := sync.substr(sync.find("if overworld_sprites and _OverworldRoom"), 400)
	ck(guard.find("local.visible = false") >= 0 and guard.find("_remote_companion_pool") >= 0,
		"...hiding the player, the companion letters and every remote figure")
	ck(guard.find("return") >= 0, "...and returns before it computes a single font metric")

	print("
--- a harvested node LOOKS harvested ---")
	# The text map drew a spent node as a dim grey comma. The sprite map drew the tile and then
	# looked for an overlay called "depleted" that was never baked, so a used-up ore vein was
	# pixel-identical to a fresh one and looked like it had not cleared at all.
	# The DRAWING of a spent node is proven by composing it both ways and comparing pixels and
	# brightness - tools/probe/depleted_looks_spent.gd, which also covers the hotzone case. The
	# two source-reading checks that used to sit here broke on a rename while the behaviour was
	# correct, and had never proven anything the pixel probe does not prove better.
	ck(Room._overlay_name("!depleted:ore_vein") == "depleted", "`!depleted:ore_vein` reads as depleted")
	ck(Room._under_tile("!depleted:ore_vein") == "ore_vein", "...standing on an ore vein, which still draws")
	ck(not FileAccess.file_exists("res://client/sprites/overworld32/overlay/depleted.png"),
		"and there is no depleted overlay sprite - which is exactly why it needed the dim")

	print("
--- and a post is no longer cropped ---")
	# A post is 17-20 tiles across in a 23-tile view: there is nothing to crop away, and the crop
	# was cutting off the walls and the doors.
	var disp2_i := cli3.find("func _overworld_display(")
	var disp2 := cli3.substr(disp2_i, cli3.find("
func ", disp2_i + 10) - disp2_i)
	ck(disp2.find("var crop: int = 0") >= 0, "the crop is off")
	ck(disp2.find("OVERWORLD_SPRITE_PX * 2") < 0, "and so is the double-size zoom that needed it")
	# The thing that actually made a post read as a room is the floor, and that stays.
	var post_payload2: Dictionary = ws.build_map_payload(
		int(cm.get_npc_posts()[0].get("x", 0)), int(cm.get_npc_posts()[0].get("y", 0)),
		11, [], [], [], [], [], {}, [], false, [])
	var pb2: Array = MapPayload.cells(post_payload2.get("biomes", {}))
	var on_post := 0
	for row in pb2:
		for b in row:
			if String(b) == "post":
				on_post += 1
	ck(on_post > 200, "%d of 529 cells stand on the post's own floor, which is what reads as a room" % on_post)

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

	print("
--- inside a post, the view becomes a room ---")
	# The owner's older ask: a post should read as a room rather than a patch of map. Half the
	# width at double the size keeps the panel exactly as wide and doubles the detail, and you
	# cannot see past a post's walls anyway.
	var posts: Array = cm.get_npc_posts()
	ck(posts.size() > 0, "the world has posts to stand in")
	var post_payload: Dictionary = ws.build_map_payload(
		int(posts[0].get("x", 0)), int(posts[0].get("y", 0)), 11, [], [], [], [], [], {}, [], false, [])
	ck(bool(post_payload.get("post", false)), "standing on one, the payload says so")
	ck(not bool(payload.get("post", false)), "and standing in the wilderness it does not")
	var pm: Array = MapPayload.cells(post_payload.get("meaning", {}))
	var pb: Array = MapPayload.cells(post_payload.get("biomes", {}))
	Room.build(pm, pb, {})
	var cropped: String = MapPayload.inflate_sprites(post_payload,
		func(x: int, y: int) -> String:
			var c: String = Room.cell_path(x, y)
			return "[img=52x52]%s[/img]" % c if c != "" else "  ", 11)
	ck(cropped.count("[img=52x52]") == 11 * 11,
		"the post view is %d squares at double size, not %d" % [cropped.count("[img=52x52]"), 23 * 23])
	var uncropped: String = MapPayload.inflate_sprites(post_payload,
		func(x: int, y: int) -> String:
			var c: String = Room.cell_path(x, y)
			return "[img=26x26]%s[/img]" % c if c != "" else "  ", 0)
	ck(uncropped.count("[img=26x26]") == 23 * 23, "and without the crop it is still the full view")
	# Same panel width: 11 squares at 52px is 572, 23 at 26px is 598. Close enough that the map
	# does not jump when you step through a door, which is the whole point.
	ck(absi(11 * 52 - 23 * 26) < 40, "the two are within %dpx of each other, so the panel does not jump" % absi(11 * 52 - 23 * 26))

	# A post, as a picture.
	var pout := Image.create(11 * 32, 11 * 32, false, Image.FORMAT_RGBA8)
	for y in range(6, 17):
		for x in range(6, 17):
			var pp: String = Room.cell_path(x, y)
			if pp == "":
				continue
			var ptex := load(pp) as Texture2D
			if ptex == null:
				continue
			var pim := ptex.get_image()
			if pim.is_compressed():
				pim.decompress()
			pim.convert(Image.FORMAT_RGBA8)
			pout.blit_rect(pim, Rect2i(Vector2i.ZERO, pim.get_size()), Vector2i((x - 6) * 32, (y - 6) * 32))
	pout.resize(pout.get_width() * 3, pout.get_height() * 3, Image.INTERPOLATE_NEAREST)
	pout.save_png("res://claude_screenshots/overworld_post.png")
	print("  wrote claude_screenshots/overworld_post.png")

	# Rebuild the wilderness view for the picture below.
	Room.build(meaning, biomes, figures)

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


static func _cell_pixels(x: int, y: int) -> Array:
	"""The composed cell at (x, y) as a flat array of colours, so two builds can be compared."""
	var p: String = Room.cell_path(x, y)
	if p == "":
		return []
	var tex := load(p) as Texture2D
	if tex == null:
		return []
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var out: Array = []
	for yy in range(im.get_height()):
		for xx in range(im.get_width()):
			out.append(im.get_pixel(xx, yy))
	return out
