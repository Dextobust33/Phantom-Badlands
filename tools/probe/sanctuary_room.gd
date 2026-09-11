extends SceneTree
## The sprite Sanctuary composes, its stations actually carry art, and its cells load as [img].
##
## Phase 3.45, first slice. `client/sanctuary_room.gd` builds the whole room as one image and
## hands 32x32 regions of it to the text grid. The failures that look finished: a station whose
## piece failed to load (the cell is bare floor and nobody notices), a cell path the `[img]` tag
## cannot resolve (blank tile), and a rebuild on every move (a stutter). Each is checked here.
const ROOM := preload("res://client/sanctuary_room.gd")
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _uniq(a: Array) -> int:
	var d := {}
	for x in a:
		d[x] = true
	return d.size()


func _init() -> void:
	if not ROOM.available():
		# NOT a pass: the art is licence-restricted and untracked, so a fresh clone lacks it.
		print("[SANCTUARY] SKIP - sprites absent; run tools/bake_sanctuary.py (needs the Raven packs)")
		quit(2)
		return
	var c = load(CLIENT).new()
	var layout: Array = c.HOUSE_MAP_BASE.duplicate()
	# Put two companion slots in, the way _get_current_house_layout does for a base Sanctuary.
	for pos in [[2, 4], [2, 7]]:
		var row: String = layout[pos[0]]
		layout[pos[0]] = row.substr(0, pos[1]) + "C" + row.substr(pos[1] + 1)
	c.free()

	ROOM.build(layout)
	var cols: int = String(layout[0]).length()
	var rows: int = layout.size()
	ck(ROOM._room != null and ROOM._room.get_size() == Vector2i(cols * ROOM.CELL, rows * ROOM.CELL),
		"room image is %dx%d cells at %dpx" % [cols, rows, ROOM.CELL])

	# Every station piece loaded, and its cell is visibly NOT plain floor.
	var floor_cell: Image = ROOM._room.get_region(Rect2i(1 * ROOM.CELL, 16 * ROOM.CELL, ROOM.CELL, ROOM.CELL))
	for y in range(rows):
		var line: String = layout[y]
		for x in range(cols):
			var ch := line[x]
			if not ROOM.STATION_PIECE.has(ch):
				continue
			var piece: String = ROOM.STATION_PIECE[ch]
			ck(ROOM._piece(piece) != null, "'%s' (%s) piece loads" % [piece, ch])
			var region: Image = ROOM._room.get_region(Rect2i(x * ROOM.CELL, y * ROOM.CELL, ROOM.CELL, ROOM.CELL))
			ck(region.get_data() != floor_cell.get_data(), "station %s at %d,%d is drawn, not bare floor" % [ch, x, y])
	for d in ROOM.DECOR:
		ck(ROOM._piece(String(d[0])) != null, "decor '%s' loads" % String(d[0]))

	# A cell path resolves through ResourceLoader - which is what RichTextLabel's [img] calls.
	var p: String = ROOM.cell_path(4, 12)
	var tex = load(p)
	ck(tex is Texture2D and (tex as Texture2D).get_size() == Vector2(ROOM.CELL, ROOM.CELL),
		"cell_path returns a 32x32 texture the [img] tag can load")
	ck(ROOM.cell_path(4, 12) == p, "the same cell returns the same cached path")

	# Same layout: no rebuild (a move must not recompose the room).
	var before = ROOM._room
	ROOM.build(layout)
	ck(ROOM._room == before, "an unchanged layout is not recomposed")
	var layout2: Array = layout.duplicate()
	var r3: String = layout2[3]
	layout2[3] = r3.substr(0, 4) + "C" + r3.substr(5)
	ROOM.build(layout2)
	ck(ROOM._room != before, "a new companion slot DOES recompose it")

	print("\n--- figures: bigger than a cell, animated, layered ---")
	ROOM.build(layout)
	var me_img: Image = ROOM.sprite_image("res://client/sprites/battlers/overworld/1_1/down_stand.png", ROOM.PLAYER_SCALE, false)
	ck(me_img != null and me_img.get_height() == 62, "the player is drawn at 2x the raw sprite (62px tall)")
	var cells: Dictionary = ROOM.overlay_cells([{"key": "me", "img": me_img, "x": 14, "y": 9, "lift": 2}])
	ck(cells.has(Vector2i(14, 9)) and cells.has(Vector2i(14, 8)), "a 2x player covers its own cell AND the one above")
	var wolf := "res://client/sprites/monster_floor32/wolf_1.png"
	var comp_img: Image = ROOM.sprite_image(wolf, ROOM.COMPANION_SCALE, true)
	ck(comp_img != null and comp_img.get_height() > 32 and comp_img.get_height() < me_img.get_height(),
		"a companion is ~1.3x its dungeon sprite, and still smaller than the player")
	ck(comp_img.get_pixel(0, 0).a == 0.0, "the companion's baked dungeon floor is keyed out")
	var w0: Dictionary = ROOM.overlay_cells([{"key": "wolf_1", "img": comp_img, "x": 4, "y": 2, "lift": 6}])
	var comp2: Image = ROOM.sprite_image("res://client/sprites/monster_floor32/wolf_2.png", ROOM.COMPANION_SCALE, true)
	var w1: Dictionary = ROOM.overlay_cells([{"key": "wolf_2", "img": comp2, "x": 4, "y": 2, "lift": 6}])
	ck(w0.get(Vector2i(4, 2), "") != w1.get(Vector2i(4, 2), ""), "a new animation frame is a new cell texture")
	var both: Dictionary = ROOM.overlay_cells([
		{"key": "wolf_1", "img": comp_img, "x": 4, "y": 2, "lift": 6},
		{"key": "me", "img": me_img, "x": 4, "y": 3, "lift": 2}])
	ck(both.has(Vector2i(4, 2)) and both[Vector2i(4, 2)] != w0.get(Vector2i(4, 2), ""),
		"where the player and a companion share a cell, both are drawn into it")
	ck(ROOM.STATION_PIECE.has("M") and ROOM._piece("mirror") != null, "the mirror is a station with art")
	var o: Image = ROOM._outline("chest")
	var ring := 0
	for yy in range(o.get_height()):
		for xx in range(o.get_width()):
			var px: Color = o.get_pixel(xx, yy)
			if px.a > 0.0 and px.a < 0.7 and absf(px.b - ROOM.HIGHLIGHT.b) < 0.02 and absf(px.r - ROOM.HIGHLIGHT.r) < 0.02:
				ring += 1
	var mid := Vector2i(ROOM._piece("chest").get_width() / 2, ROOM._piece("chest").get_height() / 2)
	ck(o != null and o.get_width() == ROOM._piece("chest").get_width() + 4 and ring > 40
		and o.get_pixelv(mid + Vector2i(2, 2)) == ROOM._piece("chest").get_pixelv(mid),
		"stations get a 2px highlight ring (%d ring pixels) and the art itself is untouched" % ring)

	print("\n--- who sits on a cushion ---")
	var cc = load(CLIENT).new()
	cc.house_data = {"registered_companions": {"companions": [
		{"name": "Wolf", "monster_type": "Wolf", "checked_out_by": null},
		{"name": "Goblin", "monster_type": "Goblin", "checked_out_by": "Hero"}]}}
	var res: Array = cc._house_residents(layout)
	ck(res.size() == 1 and int(res[0].x) == 4 and int(res[0].y) == 2, "a companion at home sits on ITS cushion; a checked-out one leaves it empty")
	cc.house_data = {"avatar": "m1_5"}
	ck(cc._house_player_sprite().find("/m1_5/") >= 0, "the mirror's chosen look is what the Sanctuary shows")
	cc.free()
	var ids: Array = BattlerPools.all_ids()
	ck(ids.size() > 50 and ids.size() == _uniq(ids), "the mirror offers every character look once (%d)" % ids.size())
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find("if bid != \"\" and not (bid in BattlerPools.all_ids()):") >= 0, "the server refuses a look the mirror does not offer")

	var src := FileAccess.get_file_as_string(CLIENT)
	ck(src.find("if _house_room_active() and not _house_room_rendering:") >= 0,
		"display_game routes Sanctuary text to the side panel while the room owns the canvas")
	ck(src.find("if _house_room_active():\n\t\t_render_house_room()") >= 0,
		"_update_house_map draws the room (so every move redraws it)")

	print("\n[SANCTUARY] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
