extends SceneTree
## Sample rooms for judging the WALL RIM rule, which is a question only eyes can answer.
##
## Owner: *"It may be better if only the spaces below a corridor show those (almost as if they are
## holding up the corridors) and then walls would only be placed above spaces in a room, helping
## people differentiate the rooms from the corridors even further."*
##
## Renders the SAME generated floor under three rules so they are actually comparable. Rendering
## three different floors would compare the floors, not the rules.
const _T = preload("res://client/dungeon_tiles.gd")
const _C = preload("res://client/dungeon_composite.gd")
const _DD = preload("res://shared/dungeon_database.gd")

const VIEW_W := 19
const VIEW_H := 9
const CELL := 64

var grid: Array = []
var labels: Dictionary = {}


func _walkable(x: int, y: int) -> bool:
	if y < 0 or y >= grid.size():
		return false
	var r = grid[y]
	if x < 0 or x >= r.size():
		return false
	return int(r[x]) != 1


func _is_room(x: int, y: int) -> bool:
	return labels.has("%d,%d" % [x, y])


func _is_corridor(x: int, y: int) -> bool:
	return _walkable(x, y) and not _is_room(x, y)


func show_rock(rule: String, x: int, y: int) -> bool:
	"""Should this WALL cell draw the rock rim, under the given rule?"""
	match rule:
		"current":
			# whatever touches floor - what ships today
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _walkable(x + d.x, y + d.y):
					return true
			return false
		"owner":
			# rock BELOW a corridor (holding it up), and ABOVE a room (its far wall)
			return _is_corridor(x, y - 1) or _is_room(x, y + 1)
		"south":
			# the simpler cousin: a wall under ALL floor, room or corridor
			return _walkable(x, y - 1)
	return false


func _img(path: String) -> Image:
	var im: Image = (load(path) as Texture2D).get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


func _from_sheet(sheet: String, cell: Vector2i, size: int) -> Image:
	var sh: Image = (load(sheet) as Texture2D).get_image()
	sh.convert(Image.FORMAT_RGBA8)
	var im := Image.create(size, size, false, Image.FORMAT_RGBA8)
	im.blit_rect(sh, Rect2i(cell * size, Vector2i(size, size)), Vector2i.ZERO)
	if size != 32:
		im.resize(32, 32, Image.INTERPOLATE_NEAREST)
	return im


func _init() -> void:
	var out_dir: String = OS.get_environment("PROPSHOT_DIR")
	var res: Dictionary = _DD.generate_floor_grid("wolf_den", 1, false)
	grid = res.get("grid", [])
	if grid.is_empty():
		quit(1)
		return
	labels = _T.label_rooms(grid)

	# a viewport with both kinds in view, or the comparison shows nothing
	var best := Vector2i.ZERO
	var best_mix := -1
	for oy in range(0, maxi(1, grid.size() - VIEW_H), 2):
		for ox in range(0, maxi(1, grid[0].size() - VIEW_W), 2):
			var r := 0
			var c := 0
			for y in range(oy, mini(oy + VIEW_H, grid.size())):
				for x in range(ox, mini(ox + VIEW_W, grid[y].size())):
					if int(grid[y][x]) == 1:
						continue
					if _is_room(x, y): r += 1
					else: c += 1
			if mini(r, c) > best_mix:
				best_mix = mini(r, c)
				best = Vector2i(ox, oy)

	var corridor := _from_sheet(_T.SHEET_CAVE16, _T.CAVE_FLOOR, 16)
	var rock := _from_sheet(_T.SHEET_CAVE32, _T.CAVE_ROCK, 32)
	var voidt := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	voidt.fill(Color(0, 0, 0, 1))

	for rule in ["current", "owner", "south"]:
		var canvas := Image.create(VIEW_W * 32, VIEW_H * 32, false, Image.FORMAT_RGBA8)
		var rocks := 0
		for gy in range(VIEW_H):
			for gx in range(VIEW_W):
				var x: int = best.x + gx
				var y: int = best.y + gy
				var tile := 1
				if y < grid.size() and x < grid[y].size():
					tile = int(grid[y][x])
				var cell: Image = null
				if tile == 1:
					if show_rock(rule, x, y):
						cell = rock
						rocks += 1
					else:
						cell = voidt
				else:
					var rid: int = int(labels.get("%d,%d" % [x, y], -1))
					if rid >= 0:
						var fl: String = _T.room_floor_for(x, y, rid)
						var prop: String = _T.prop_for(x, y)
						if prop != "":
							var dec: String = _T.decor_for(x, y, rid)
							cell = _img(_C.overlay(fl, dec)) if dec != "" else _img(_C.over_prop(prop, fl))
						else:
							cell = _img(fl)
					else:
						var p2: String = _T.prop_for(x, y)
						cell = _img(p2) if (p2 != "" and ResourceLoader.exists(p2)) else corridor
				canvas.blit_rect(cell, Rect2i(Vector2i.ZERO, Vector2i(32, 32)),
					Vector2i(gx * 32, gy * 32))
		canvas.resize(VIEW_W * CELL, VIEW_H * CELL, Image.INTERPOLATE_NEAREST)
		canvas.save_png("%s/wall_%s.png" % [out_dir, rule])
		print("%-8s %d rock cells drawn" % [rule, rocks])
	quit()
