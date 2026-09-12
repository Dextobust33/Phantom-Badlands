extends SceneTree
## The minimap after the rewrite must draw EXACTLY what it drew before.
##
## `_minimap_cells` was turned inside out for cost: it used to ask each of its 861 cells "is there
## a dungeon here? a post here?" and now walks the markers instead and writes them into the cells
## they land in. That is the kind of change that is easy to get subtly wrong at the edges - a
## marker one cell off, a post that stops appearing, an off-by-one at the rim of the picture.
##
## So this holds a REFERENCE implementation of the old per-cell logic and compares character for
## character, over real world positions with real posts and planted dungeons.
##
## It also checks the memo, which is the other half of the change: a cached glyph must equal the
## glyph computed fresh, and a terrain edit must throw the cache away.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

const STEP := 2
const MAP_HALF_W := 20
const MAP_HALF_H := 10

var fails := 0
var ws
var cm

func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _reference(center_x: int, center_y: int, dungeon_locations: Array) -> Array:
	"""The ORIGINAL logic, gathering per cell, on the snapped lattice."""
	var base_x: int = center_x - posmod(center_x, STEP)
	var base_y: int = center_y - posmod(center_y, STEP)
	var dungeon_set: Dictionary = {}
	for d in dungeon_locations:
		dungeon_set["%d,%d" % [int(d.x), int(d.y)]] = true
	var post_buckets: Dictionary = ws._bucket_post_points(cm.get_npc_posts())
	var rows: Array = []
	for miny in range(MAP_HALF_H, -MAP_HALF_H - 1, -1):
		var line: PackedStringArray = PackedStringArray()
		for minx in range(-MAP_HALF_W, MAP_HALF_W + 1):
			var wx = base_x + minx * STEP
			var wy = base_y + miny * STEP
			if minx == 0 and miny == 0:
				line.append("[color=#FFFF00]@[/color]")
				continue
			var has_dungeon = false
			for dox in range(STEP):
				for doy in range(STEP):
					if dungeon_set.has("%d,%d" % [wx + dox, wy + doy]):
						has_dungeon = true
						break
				if has_dungeon:
					break
			if has_dungeon:
				line.append("[color=#FF4444]D[/color]")
				continue
			if ws._near_npc_post(post_buckets, wx, wy):
				line.append("[color=#FFD700]P[/color]")
				continue
			line.append(ws._minimap_glyph(wx, wy))
		rows.append(line)
	return rows


func _diff(a: Array, b: Array) -> int:
	var n := 0
	for y in range(mini(a.size(), b.size())):
		for x in range(mini(a[y].size(), b[y].size())):
			if String(a[y][x]) != String(b[y][x]):
				n += 1
				if n <= 4:
					print("      (%d,%d): got %s want %s" % [x, y, a[y][x], b[y][x]])
	return n


func _init() -> void:
	cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("--- the rewritten minimap draws what the old one drew ---")
	# Real posts are in the world already. Plant dungeons at a spread of offsets, INCLUDING the
	# rim and just outside it, because a marker one cell off at the edge is the fault this shape
	# of rewrite produces.
	var posts: Array = cm.get_npc_posts()
	var spots: Array = [Vector2i(40, 40), Vector2i(-120, 61), Vector2i(300, -200)]
	# A position standing ON a post, so the P markers are actually exercised rather than absent.
	if posts.size() > 0:
		spots.append(Vector2i(int(posts[0].get("x", 0)) + 3, int(posts[0].get("y", 0)) - 2))
	var total_marks := 0
	for spot in spots:
		var dl: Array = []
		for off in [Vector2i(0, 6), Vector2i(-13, 0), Vector2i(7, -9), Vector2i(39, 19),
				Vector2i(-40, -20), Vector2i(41, 0), Vector2i(0, 21), Vector2i(-3, -5)]:
			dl.append({"x": spot.x + off.x, "y": spot.y + off.y})
		var got: Array = ws._minimap_cells(spot.x, spot.y, dl)
		var want: Array = _reference(spot.x, spot.y, dl)
		var d := _diff(got, want)
		var marks := 0
		for row in got:
			for c in row:
				if String(c).find("]D[") >= 0 or String(c).find("]P[") >= 0:
					marks += 1
		total_marks += marks
		ck(d == 0, "(%d,%d): %d of %d cells differ, %d markers drawn" % [
			spot.x, spot.y, d, MAP_HALF_H * 2 + 1, marks])
	ck(total_marks > 0, "%d dungeon/post markers were actually drawn - the comparison is not two empty maps" % total_marks)

	print("\n--- and the markers land where the dungeons are ---")
	# The reference could be wrong in the same way the new code is, so check one marker against
	# arithmetic rather than against the other implementation.
	var solo: Array = [{"x": 40 + 6, "y": 40 + 4}]
	var g2: Array = ws._minimap_cells(40, 40, solo)
	# cell (minx=3, miny=2) -> row index MAP_HALF_H - 2 = 8, col MAP_HALF_W + 3 = 23
	ck(String(g2[MAP_HALF_H - 2][MAP_HALF_W + 3]).find("]D[") >= 0,
		"a dungeon 6 east and 4 north draws a D three cells right and two up")
	var empty_far: Array = ws._minimap_cells(40, 40, [{"x": 40 + 200, "y": 40}])
	var far_marks := 0
	for row in empty_far:
		for c in row:
			if String(c).find("]D[") >= 0:
				far_marks += 1
	ck(far_marks == 0, "and a dungeon 200 tiles away draws nothing (%d markers)" % far_marks)

	print("\n--- the memo returns the truth, and a terrain edit throws it away ---")
	var probe_pt := Vector2i(512, -333)
	var fresh: String = ws._minimap_glyph(probe_pt.x, probe_pt.y)
	ck(ws._minimap_glyph(probe_pt.x, probe_pt.y) == fresh, "a cached glyph equals the first answer")
	ck(ws._mini_glyphs.size() > 0, "%d glyphs are held between moves" % ws._mini_glyphs.size())
	var rev_before: int = int(cm.tile_revision)
	cm.set_tile(probe_pt.x, probe_pt.y, {"type": "wall", "blocks_move": true, "blocks_los": true})
	ck(int(cm.tile_revision) > rev_before, "a tile edit bumps the revision")
	ws._minimap_cells(512, -332, [])
	var after: String = ws._minimap_glyph(probe_pt.x, probe_pt.y)
	ck(after.find("#888888") >= 0,
		"and the cell reads as the NEW terrain (%s), so the cache did not go stale" % after)
	ck(after != fresh, "which is a different character from the one that was cached")

	print("\n--- the lattice is snapped, so walking reuses what it already computed ---")
	# This is what makes the memo work at all: unsnapped, every sample point shifts by one on
	# each step and nothing is ever reusable.
	var a: Array = ws._minimap_cells(100, 100, [])
	var b: Array = ws._minimap_cells(101, 100, [])
	var same := 0
	var cells := 0
	for y in range(a.size()):
		for x in range(a[y].size()):
			cells += 1
			if String(a[y][x]) == String(b[y][x]):
				same += 1
	ck(same == cells, "a one-tile step inside the same 2x2 block redraws identically (%d/%d)" % [same, cells])
	var c: Array = ws._minimap_cells(102, 100, [])
	var moved := 0
	for y in range(a.size()):
		for x in range(a[y].size()):
			if String(a[y][x]) != String(c[y][x]):
				moved += 1
	ck(moved > 0, "and a step into the NEXT block does scroll the picture (%d cells changed)" % moved)

	print("\n[MINIMAPGOLDEN] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
