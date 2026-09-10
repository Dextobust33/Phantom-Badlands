extends SceneTree
## Render a REAL generated floor with room floors and corridor floors, at the real cell size.
##
## The pack was chosen by measurement and the rule proved by probe, but the one question neither
## can answer is what the SEAM looks like where a corridor meets a room. That needs looking at.
const _T = preload("res://client/dungeon_tiles.gd")
const _C = preload("res://client/dungeon_composite.gd")
const _DD = preload("res://shared/dungeon_database.gd")

const VIEW_W := 19
const VIEW_H := 9
const CELL := 64


func _img(path: String) -> Image:
	var im: Image = (load(path) as Texture2D).get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


func _corridor_floor() -> Image:
	var sheet: Image = (load(_T.SHEET_CAVE16) as Texture2D).get_image()
	sheet.convert(Image.FORMAT_RGBA8)
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, Rect2i(_T.CAVE_FLOOR * 16, Vector2i(16, 16)), Vector2i.ZERO)
	im.resize(32, 32, Image.INTERPOLATE_NEAREST)
	return im


func _rock() -> Image:
	var sheet: Image = (load(_T.SHEET_CAVE32) as Texture2D).get_image()
	sheet.convert(Image.FORMAT_RGBA8)
	var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, Rect2i(_T.CAVE_ROCK * 32, Vector2i(32, 32)), Vector2i.ZERO)
	return im


func _touches_floor(grid: Array, x: int, y: int) -> bool:
	"""Mirrors client.gd `_dungeon_supports_floor`: rock only where it holds up the floor above."""
	var ny: int = y - 1
	if ny < 0 or ny >= grid.size():
		return false
	var row = grid[ny]
	if x < 0 or x >= row.size():
		return false
	return int(row[x]) != 1


func _init() -> void:
	var out_dir: String = OS.get_environment("PROPSHOT_DIR")
	var res: Dictionary = _DD.generate_floor_grid("wolf_den", 1, false)
	var grid: Array = res.get("grid", [])
	if grid.is_empty():
		print("no grid")
		quit(1)
		return

	# Find a viewport that actually contains a SEAM - both room and corridor - rather than
	# whatever is at the origin. Showing a view of pure corridor would prove nothing.
	var best := Vector2i(0, 0)
	var best_mix := -1
	for oy in range(0, maxi(1, grid.size() - VIEW_H), 2):
		for ox in range(0, maxi(1, grid[0].size() - VIEW_W), 2):
			var r := 0
			var c := 0
			for y in range(oy, mini(oy + VIEW_H, grid.size())):
				for x in range(ox, mini(ox + VIEW_W, grid[y].size())):
					if int(grid[y][x]) == 1:
						continue
					if _T.is_room_cell(grid, x, y): r += 1
					else: c += 1
			var mix: int = mini(r, c)          # maximise the SMALLER of the two
			if mix > best_mix:
				best_mix = mix
				best = Vector2i(ox, oy)
	print("viewport at %s - %d cells of the rarer kind in view" % [best, best_mix])

	# label ONCE, not per cell - relabelling inside the loop is O(cells x grid)
	var labels: Dictionary = _T.label_rooms(grid)
	print("rooms on this floor: %d" % _T.room_count(labels))
	var corridor := _corridor_floor()
	var rock := _rock()
	var void_im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	void_im.fill(Color(0, 0, 0, 1))

	for mode in ["before", "after"]:
		var canvas := Image.create(VIEW_W * 32, VIEW_H * 32, false, Image.FORMAT_RGBA8)
		var rooms := 0
		for gy in range(VIEW_H):
			for gx in range(VIEW_W):
				var x: int = best.x + gx
				var y: int = best.y + gy
				var tile: int = 1
				if y < grid.size() and x < grid[y].size():
					tile = int(grid[y][x])
				var cell: Image = null
				if tile == 1:
					cell = rock if _touches_floor(grid, x, y) else void_im
				elif mode == "after" and (_T.tall_prop_for(grid, x, y) != "" or _T.tall_prop_for(grid, x, y + 1) != ""):
					# a TWO-CELL prop claims this cell; mirrors client.gd `_dungeon_ground_at`
					var tb: String = _T.tall_prop_for(grid, x, y)
					var tt: String = _T.tall_prop_for(grid, x, y + 1)
					var rid0: int = int(labels.get("%d,%d" % [x, y], -1))
					var under: String = _T.room_floor_for(x, y, rid0) if rid0 >= 0 						else _T.ROOM_FLOOR_DIR + "corridor_00.png"
					var half: String = _T.tall_half(tb, "bot") if tb != "" else _T.tall_half(tt, "top")
					cell = _img(_C.overlay(under, half)) if half != "" else corridor
				else:
					var is_room: bool = _T.is_room_cell(grid, x, y)
					var prop: String = _T.prop_for(x, y)
					if mode == "after" and is_room:
						rooms += 1
						var rid: int = int(labels.get("%d,%d" % [x, y], 0))
						var fl: String = _T.room_floor_for(x, y, rid)
						if prop != "" and ResourceLoader.exists(prop):
							var dec: String = _T.decor_for(x, y, rid)
							cell = _img(_C.overlay(fl, dec)) if dec != "" else _img(_C.over_prop(prop, fl))
						else:
							cell = _img(fl)
					elif prop != "" and ResourceLoader.exists(prop):
						cell = _img(prop)
					else:
						cell = corridor
				canvas.blit_rect(cell, Rect2i(Vector2i.ZERO, Vector2i(32, 32)),
					Vector2i(gx * 32, gy * 32))
		canvas.resize(VIEW_W * CELL, VIEW_H * CELL, Image.INTERPOLATE_NEAREST)
		canvas.save_png("%s/rooms_%s.png" % [out_dir, mode])
		print("%s: %d room cells drawn" % [mode, rooms])
	quit()
