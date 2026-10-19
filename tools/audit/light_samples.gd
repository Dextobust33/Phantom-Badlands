extends SceneTree
## Emit one dungeon floor plus the POSITIONS any lighting effect would need, so the look can be
## prototyped and judged before a shader is written.
##
## Owner: *"I'd like to playtest or see a few samples to make a decision."* Same method that
## settled the wall rule - one floor, several treatments, so the treatment is what differs.
##
## The effect itself is simulated in Python from this output rather than rendered here: headless
## Godot has no GPU, and the point is to choose a LOOK, not to ship a shader nobody has agreed to.
const _T = preload("res://client/dungeon_tiles.gd")
const _C = preload("res://client/dungeon_composite.gd")
const _DD = preload("res://shared/dungeon_database.gd")

const VIEW_W := 19
const VIEW_H := 9


func _img(p: String) -> Image:
	var im: Image = (load(p) as Texture2D).get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


func _sheet(sheet: String, cell: Vector2i, size: int) -> Image:
	var sh: Image = (load(sheet) as Texture2D).get_image()
	sh.convert(Image.FORMAT_RGBA8)
	var im := Image.create(size, size, false, Image.FORMAT_RGBA8)
	im.blit_rect(sh, Rect2i(cell * size, Vector2i(size, size)), Vector2i.ZERO)
	if size != 32:
		im.resize(32, 32, Image.INTERPOLATE_NEAREST)
	return im


func _walk(grid: Array, x: int, y: int) -> bool:
	if y < 0 or y >= grid.size():
		return false
	var r = grid[y]
	if x < 0 or x >= r.size():
		return false
	return int(r[x]) != 1


func _init() -> void:
	var out_dir: String = OS.get_environment("PROPSHOT_DIR")
	var res: Dictionary = _DD.generate_floor_grid("wolf_den", 1, false)
	var grid: Array = res.get("grid", [])
	if grid.is_empty():
		quit(1)
		return
	var labels: Dictionary = _T.label_rooms(grid)

	# pick a view containing at least one tall prop, so the "light from lamps" sample has a lamp
	var best := Vector2i.ZERO
	var best_score := -1
	for oy in range(0, maxi(1, grid.size() - VIEW_H), 1):
		for ox in range(0, maxi(1, grid[0].size() - VIEW_W), 1):
			var lamps := 0
			var rooms := 0
			for y in range(oy, mini(oy + VIEW_H, grid.size())):
				for x in range(ox, mini(ox + VIEW_W, grid[y].size())):
					if _T.tall_prop_for(grid, x, y) != "":
						lamps += 1
					if labels.has("%d,%d" % [x, y]):
						rooms += 1
			var sc: int = lamps * 100 + mini(rooms, 40)
			if sc > best_score:
				best_score = sc
				best = Vector2i(ox, oy)

	var corridor := _sheet(_T.SHEET_CAVE16, _T.CAVE_FLOOR, 16)
	var rock := _sheet(_T.SHEET_CAVE32, _T.CAVE_ROCK, 32)
	var voidt := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	voidt.fill(Color(0, 0, 0, 1))

	var canvas := Image.create(VIEW_W * 32, VIEW_H * 32, false, Image.FORMAT_RGBA8)
	var lamps_out := []
	var player := Vector2i(-1, -1)
	for gy in range(VIEW_H):
		for gx in range(VIEW_W):
			var x: int = best.x + gx
			var y: int = best.y + gy
			var tile := 1
			if y < grid.size() and x < grid[y].size():
				tile = int(grid[y][x])
			var cell: Image = null
			if tile == 1:
				var wt: String = _T.tall_prop_for(grid, x, y + 1)
				if wt != "":
					var wp: String = _T.rock_path() if _walk(grid, x, y - 1) else _T.void_path()
					var wh: String = _T.tall_half(wt, "top")
					cell = _img(_C.overlay(wp, wh)) if wh != "" else (rock if _walk(grid, x, y - 1) else voidt)
				else:
					cell = rock if _walk(grid, x, y - 1) else voidt
			else:
				var rid: int = int(labels.get("%d,%d" % [x, y], -1))
				var under: String = _T.room_floor_for(x, y, rid) if rid >= 0 \
					else _T.ROOM_FLOOR_DIR + "corridor_00.png"
				var tb: String = _T.tall_prop_for(grid, x, y)
				var tt: String = _T.tall_prop_for(grid, x, y + 1)
				if tb != "" or tt != "":
					var half: String = _T.tall_half(tb, "bot") if tb != "" else _T.tall_half(tt, "top")
					cell = _img(_C.overlay(under, half)) if half != "" else _img(under)
					if tb != "":
						lamps_out.append(Vector2i(gx, gy))
				else:
					var prop: String = _T.prop_for(x, y)
					if prop != "" and rid >= 0:
						var dec: String = _T.decor_for(x, y, rid)
						cell = _img(_C.overlay(under, dec)) if dec != "" else _img(_C.over_prop(prop, under))
					elif prop != "":
						cell = _img(prop)
					else:
						cell = _img(under) if rid >= 0 else corridor
					# the floor cell NEAREST THE VIEW CENTRE, not the first one found - a torch
					# sample with the player jammed against the edge shows the falloff clipped
					# rather than the falloff
					var ctr := Vector2i(VIEW_W / 2, VIEW_H / 2)
					var here := Vector2i(gx, gy)
					if player.x < 0 or (here - ctr).length() < (player - ctr).length():
						player = here
			canvas.blit_rect(cell, Rect2i(Vector2i.ZERO, Vector2i(32, 32)),
				Vector2i(gx * 32, gy * 32))

	canvas.save_png("%s/light_base.png" % out_dir)
	var meta := {"player": [player.x, player.y], "lamps": [],
		"view_w": VIEW_W, "view_h": VIEW_H, "cell": 32}
	for l in lamps_out:
		meta["lamps"].append([l.x, l.y])
	var f := FileAccess.open("%s/light_meta.json" % out_dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	print("base written: player at %s, %d lamp(s)" % [player, lamps_out.size()])
	quit()
