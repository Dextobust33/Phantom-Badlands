extends SceneTree
## What does the MINIMAP cost per move, and what would a wider dungeon query add?
##
## Owner 2026-09-12: *"the minimap probably needs a redesign, dungeons and things only pop up on
## it in some steps even if they are pretty close... do it in a way that is cost sensitive to the
## server and client."*
##
## The FAULT is not the drawing. `_minimap_cells` already checks the full 2x2 sample block for a
## dungeon. It is handed `get_visible_dungeons(x, y, vision_radius)` - radius 11, the player's
## LINE OF SIGHT - while the minimap itself spans +/-40 east/west and +/-20 north/south. A
## dungeon 15 tiles away is inside the picture and absent from the list, so it blinks in only
## when the player walks within 11 tiles.
##
## This measures three things before anything is changed:
##   1. what the minimap costs now, per move, on the server;
##   2. what a query at the minimap's OWN extent costs instead of one at vision radius;
##   3. how many dungeons each radius actually finds, which is the size of the bug.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

const REPS := 40
const MINIMAP_STEP := 2
const MINIMAP_HALF_W := 20
const MINIMAP_HALF_H := 10

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	# Without this the world has no posts and the minimap's post scan costs nothing - the exact
	# instrument defect that made the first overworld cost measurement worthless.
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	var spots := [Vector2i(40, 40), Vector2i(-120, 60), Vector2i(300, -200)]

	print("\n=== what the minimap costs now ===")
	# The minimap is 41x21 = 861 characters, and every character that is not a dungeon, a post or
	# a known tile type asks the chunk manager for a tile AND the world for a biome.
	for spot in spots:
		ws._minimap_cells(spot.x, spot.y, [])   # warm the chunks
		var t0 := Time.get_ticks_usec()
		for i in range(REPS):
			ws._minimap_cells(spot.x, spot.y, [])
		var per := float(Time.get_ticks_usec() - t0) / float(REPS) / 1000.0
		print("  (%d, %d): %.3f ms per move for %d cells" % [
			spot.x, spot.y, per, (MINIMAP_HALF_W * 2 + 1) * (MINIMAP_HALF_H * 2 + 1)])

	print("\n=== and what it costs when it SHIFTS by one tile rather than repeating ===")
	# A cache keyed on the exact centre is worthless: the centre changes every step. This is the
	# number any caching scheme has to beat.
	var t1 := Time.get_ticks_usec()
	for i in range(REPS):
		ws._minimap_cells(40 + i, 40, [])
	print("  walking: %.3f ms per move" % [float(Time.get_ticks_usec() - t1) / float(REPS) / 1000.0])

	print("
=== where those milliseconds go ===")
	# 861 cells, and every one that is not a marker asks the chunk manager for a tile and the
	# world for a biome. Time each on its own, at the same sample points, so a redesign is aimed
	# at whichever one is actually the bill.
	var pts: Array = []
	for my in range(MINIMAP_HALF_H, -MINIMAP_HALF_H - 1, -1):
		for mx in range(-MINIMAP_HALF_W, MINIMAP_HALF_W + 1):
			pts.append(Vector2i(40 + mx * MINIMAP_STEP, 40 + my * MINIMAP_STEP))
	var seed_v: int = cm.world_seed
	var t2 := Time.get_ticks_usec()
	for i in range(REPS):
		for pt in pts:
			cm.get_tile(pt.x, pt.y)
	var tile_ms := float(Time.get_ticks_usec() - t2) / float(REPS) / 1000.0
	var t3 := Time.get_ticks_usec()
	for i in range(REPS):
		for pt in pts:
			ws.get_biome_at(pt.x, pt.y, seed_v)
	var biome_ms := float(Time.get_ticks_usec() - t3) / float(REPS) / 1000.0
	print("  get_tile  x%d: %.3f ms" % [pts.size(), tile_ms])
	print("  get_biome x%d: %.3f ms" % [pts.size(), biome_ms])
	print("  together: %.3f ms of the measured cost" % (tile_ms + biome_ms))

	print("\n=== the size of the bug: how much of the minimap the dungeon list covers ===")
	# The list is built at vision radius; the picture is drawn at minimap extent. Everything in
	# the gap is a dungeon the player can see the ground of and not the marker.
	var vision_box := (11 * 2 + 1) * (11 * 2 + 1)
	var mini_box := (MINIMAP_HALF_W * MINIMAP_STEP * 2 + 1) * (MINIMAP_HALF_H * MINIMAP_STEP * 2 + 1)
	print("  vision radius 11 covers %d tiles" % vision_box)
	print("  the minimap draws %d tiles (+/-%d by +/-%d)" % [
		mini_box, MINIMAP_HALF_W * MINIMAP_STEP, MINIMAP_HALF_H * MINIMAP_STEP])
	ck(mini_box > vision_box * 5,
		"the minimap shows %.1fx more ground than the dungeon list it is given" % [
			float(mini_box) / float(vision_box)])

	print("\n[MINIMAPCOST] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
