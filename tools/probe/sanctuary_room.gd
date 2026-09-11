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

	var src := FileAccess.get_file_as_string(CLIENT)
	ck(src.find("if _house_room_active() and not _house_room_rendering:") >= 0,
		"display_game routes Sanctuary text to the side panel while the room owns the canvas")
	ck(src.find("if _house_room_active():\n\t\t_render_house_room()") >= 0,
		"_update_house_map draws the room (so every move redraws it)")

	print("\n[SANCTUARY] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
