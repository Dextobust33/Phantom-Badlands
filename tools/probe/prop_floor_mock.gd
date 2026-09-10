extends SceneTree
## A whole dungeon floor at REAL cell size, drawn twice: with prop occlusion and without.
##
## The per-tile sheet magnifies a 32px tile 6x, which makes every choice look louder than it is
## on screen. This composes the actual 19x9 viewport at the actual 64px cell, using the real
## `prop_for()` position hash, so the two can be judged the way they will be seen.
const _C = preload("res://client/dungeon_composite.gd")
const _T = preload("res://client/dungeon_tiles.gd")

const VW := 19
const VH := 9
const CELL := 64

func _tile(path: String) -> Image:
	var im: Image = (load(path) as Texture2D).get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im

func _floor_tile() -> Image:
	var sheet: Image = (load(_T.SHEET_CAVE16) as Texture2D).get_image()
	sheet.convert(Image.FORMAT_RGBA8)
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	im.blit_rect(sheet, Rect2i(_T.CAVE_FLOOR * 16, Vector2i(16, 16)), Vector2i.ZERO)
	im.resize(32, 32, Image.INTERPOLATE_NEAREST)
	return im

func _init() -> void:
	var out_dir: String = OS.get_environment("PROPSHOT_DIR")
	var floor_im := _floor_tile()
	# A few actors dropped ON prop cells on purpose — that is the case being judged.
	var actors := {
		"res://client/sprites/overworld_floor32/1_1/down_stand.png": Vector2i(9, 4),
		"res://client/sprites/monster_floor32/wolf_1.png": Vector2i(4, 2),
		"res://client/sprites/monster_floor32/skeleton_1.png": Vector2i(14, 6),
		"res://client/sprites/monster_floor32/troll_1.png": Vector2i(7, 7),
		"res://client/sprites/monster_floor32/orc_1.png": Vector2i(16, 1),
	}
	# Put each actor on a cell that ACTUALLY has a prop, found by asking `prop_for()` rather than
	# by picking coordinates and hoping — the first version hard-coded five cells and every one of
	# them came back plain floor, so the "before" and "after" were byte-identical and the mock
	# proved nothing. Identical output after a real change means the change is not on the path.
	var prop_cells: Array[Vector2i] = []
	for gy in range(VH):
		for gx in range(VW):
			if _T.prop_for(gx + 40, gy + 40) != "":
				prop_cells.append(Vector2i(gx, gy))
	var placed := {}
	var ai := 0
	for p in actors:
		if ai < prop_cells.size():
			placed[prop_cells[ai]] = p
			ai += 1
	print("prop cells in view: %d, actors placed on props: %d" % [prop_cells.size(), placed.size()])

	for mode in ["old", "new"]:
		var canvas := Image.create(VW * 32, VH * 32, false, Image.FORMAT_RGBA8)
		var on_prop := 0
		for gy in range(VH):
			for gx in range(VW):
				# Offset the origin so the position hash yields a realistic scatter AND lands
				# props under the actors placed above; searched for, not assumed.
				var wx: int = gx + 40
				var wy: int = gy + 40
				var prop: String = _T.prop_for(wx, wy)
				var cell := Vector2i(gx, gy)
				var tile: Image = floor_im
				if prop != "" and ResourceLoader.exists(prop):
					tile = _tile(prop)
				if placed.has(cell):
					var spr: String = placed[cell]
					if prop != "":
						on_prop += 1
					if mode == "new" and prop != "":
						tile = _tile(_C.over_prop(spr, prop))
					else:
						tile = _tile(spr)
				canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, Vector2i(32, 32)),
					Vector2i(gx * 32, gy * 32))
		canvas.resize(VW * CELL, VH * CELL, Image.INTERPOLATE_NEAREST)
		canvas.save_png("%s/floor_%s.png" % [out_dir, mode])
		print("%s: %d of %d actors are standing on a prop" % [mode, on_prop, actors.size()])
	quit()
