extends SceneTree
## Can you hover and click the people on the overworld map again?
##
## v0.9.774 stood down the old text-map sprite overlay, which was a grid of Controls with
## `mouse_entered` on each - and that overlay carried the hover tooltip and the click-to-inspect
## for players and their companions. A composed picture has no Controls, so both were lost.
##
## The replacement is the `[url=]` + `meta_hover_started` mechanism the dungeon entrances already
## proved. What this checks, by EXECUTING rather than by reading the source:
##   1. the payload names WHO is in each figure cell - so the client never re-derives it from
##      world coordinates with its own copy of the server's grid mapping;
##   2. the name it gives is the right person, at the cell the figure is actually drawn in;
##   3. a companion travelling with that player is described well enough to hover.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const MapPayload = preload("res://shared/map_payload.gd")

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

	# Put a player at a KNOWN offset from the viewer, with a companion, and check the payload
	# both places them and names them. Offsets on both axes, because the row inverts (+Y is north
	# and north is up) and an inverted row is exactly the fault a coordinate copy produces.
	print("--- the payload names who is standing in each figure cell ---")
	var cases := [Vector2i(1, 0), Vector2i(-3, 2), Vector2i(0, -4), Vector2i(2, 5)]
	for off in cases:
		var me := Vector2i(40, 40)
		var them: Vector2i = me + off
		var payload: Dictionary = ws.build_map_payload(me.x, me.y, 11,
			[{"x": them.x, "y": them.y, "name": "Kestrel", "in_my_party": true,
				"appearance_variant": "1_1",
				"companion": {"monster_type": "Wolf", "variant_color": "#39FF14",
					"variant_color2": "", "variant_pattern": "solid"}}],
			[], [], [], [], {}, [], false, [])
		var figs: Dictionary = payload.get("figures", {})
		# The cell the server actually drew them in - read from the payload, not recomputed here.
		var key := ""
		for k in figs:
			key = String(k)
		if key == "":
			ck(false, "offset (%d,%d): no figure in the payload at all" % [off.x, off.y])
			continue
		var ent: Dictionary = figs[key]
		ck(String(ent.get("name", "")) == "Kestrel",
			"offset (%d,%d) -> cell %s names %s" % [off.x, off.y, key, ent.get("name", "(nothing)")])
		# And the cell is the one the renderer will draw into: the grid is 23 wide, so a figure
		# one east of centre must be at column 12, and one NORTH must be at row 10.
		var parts: PackedStringArray = key.split(",")
		var col := int(parts[0])
		var row := int(parts[1])
		ck(col == 11 + off.x and row == 11 - off.y,
			"...and that cell is where they stand (col %d row %d, expected %d/%d)" % [
				col, row, 11 + off.x, 11 - off.y])
		ck(ent.has("companion") and String(ent["companion"].get("monster_type", "")) == "Wolf",
			"...and their companion is named, so it can be hovered too")

	print("\n--- a figure the client cannot identify is not made clickable ---")
	# A stack of players collapses to one glyph and carries no look, so there is nothing to name.
	# The client must not offer a hover that would then say nothing.
	var crowd: Dictionary = ws.build_map_payload(40, 40, 11,
		[{"x": 41, "y": 40, "name": "A", "appearance_variant": "1_1"},
		 {"x": 41, "y": 40, "name": "B", "appearance_variant": "1_2"}],
		[], [], [], [], {}, [], false, [])
	ck(crowd.get("figures", {}).is_empty(),
		"two players on one tile stay an unnamed marker (%d figures)" % crowd.get("figures", {}).size())

	print("\n--- the client asks by NAME, not by re-deriving the cell ---")
	# The structural point: there must be exactly one copy of the grid mapping, on the server.
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.find("func _nearby_player_named(") >= 0, "the lookup is by name")
	ck(cli.find("func _nearby_player_at_cell(") < 0,
		"and the coordinate version is gone, so the mapping is not duplicated")
	ck(cli.find('if _overworld_figure_meta.has(dkey):') >= 0,
		"a figure cell is wrapped in a url, which is what makes it hoverable")
	ck(cli.find('if m.begins_with("owfig:"):') >= 0, "hover is handled")
	ck(cli.find("func _on_map_meta_clicked(") >= 0, "click is handled")
	ck(cli.find("map_display.meta_clicked.connect(_on_map_meta_clicked)") >= 0,
		"...and the map actually emits clicks - it never had meta_clicked connected before")
	ck(cli.find('send_to_server({"type": "examine_player", "name": pname})') >= 0,
		"clicking a player examines them, the same message the old overlay sent")
	ck(cli.find("_open_map_companion_inspect(data)") >= 0,
		"clicking a companion opens the same inspect view it used to")

	print("\n[MAPFIGHOVER] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
