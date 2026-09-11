extends RefCounted
## The Sanctuary, drawn in sprites - Phase 3.45, first slice ("one interior end to end").
##
## HOW IT DRAWS. The dungeon proved a text canvas can be a sprite grid: every cell is one inline
## `[img]`, and `take_over_path` lets a texture composited in memory be handed to that tag as an
## ordinary res:// path (see dungeon_composite.gd). This reuses that and adds one thing the
## dungeon did not need: furniture BIGGER than a cell. A chest is 2x2 cells, the statue 2x3, a rug
## 4x3, and they do not sit on the cell grid.
##
## So the room is composed ONCE into a single image - floor, walls, then every object at its own
## pixel position - and each cell is a 32x32 region of that image. An object spanning four cells
## is simply four regions, and there is no per-object row-split logic of the kind the two-cell
## dungeon lamps needed. The image is rebuilt only when the LAYOUT changes (a companion slot is
## added by an upgrade), never on a move.
##
## The pieces come from tools/bake_sanctuary.py (Raven interiors + cozy_home, licence-restricted,
## untracked). If they are absent, `available()` is false and the caller keeps the ASCII map.

const DIR := "res://client/sprites/sanctuary32/"
const CELL := 32
const _DYN := "res://__sanctuary/"

## Station tile -> the piece drawn there. Anchored BOTTOM-CENTRE on the station's cell, so a tall
## object stands on its tile and rises above it, the way furniture reads in a top-down room.
const STATION_PIECE := {
	"S": "chest",
	"U": "statue",
	"C": "cushion",
	"K": "cushion_teal",
	"D": "door",
}

## Decoration that is not a station: purely visual, the player walks over it. Positions are for
## the 29x19 HOUSE_MAP_BASE and are dropped if a layout is ever too small to hold them.
## [piece, cell x, cell y, anchor ("bottom" | "center")]
const DECOR := [
	["rug_green", 10, 9, "center"],    # under the Stable
	["rug_blue", 23, 12, "center"],    # under the upgrade statue
	["shelf", 2, 3, "bottom"],
	["lamp", 26, 3, "bottom"],
	["firepit", 19, 6, "center"],
	["barrel", 2, 13, "bottom"],
	["crate", 3, 16, "bottom"],
	["lamp", 26, 16, "bottom"],
]
## Top-wall columns that hold a window instead of bare brick.
const WINDOW_COLS := [8, 12, 16, 20, 24]

static var _pieces: Dictionary = {}
static var _room: Image = null
static var _room_key: String = ""
static var _cells: Dictionary = {}
## `take_over_path` does not keep a texture alive; this does (see dungeon_composite.gd).
static var _keepalive: Array = []


static func available() -> bool:
	return ResourceLoader.exists(DIR + "floor.png")


static func _piece(name: String) -> Image:
	if _pieces.has(name):
		return _pieces[name]
	var img: Image = null
	var path := DIR + name + ".png"
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			img = tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RGBA8)
	_pieces[name] = img
	return img


static func _blit(room: Image, piece: Image, px: int, py: int) -> void:
	"""Alpha-blend `piece` at pixel (px, py), clipped to the room."""
	if piece == null:
		return
	var src := Rect2i(Vector2i.ZERO, piece.get_size())
	var dst := Vector2i(px, py)
	# blend_rect clips at the destination's bounds itself; a negative origin must be clipped here.
	if dst.x < 0:
		src.position.x -= dst.x
		src.size.x += dst.x
		dst.x = 0
	if dst.y < 0:
		src.position.y -= dst.y
		src.size.y += dst.y
		dst.y = 0
	if src.size.x <= 0 or src.size.y <= 0:
		return
	room.blend_rect(piece, src, dst)


static func _place(room: Image, name: String, cx: int, cy: int, anchor: String) -> void:
	var p := _piece(name)
	if p == null:
		return
	var w := p.get_width()
	var h := p.get_height()
	var px := cx * CELL + CELL / 2 - w / 2
	var py := (cy + 1) * CELL - h if anchor == "bottom" else cy * CELL + CELL / 2 - h / 2
	_blit(room, p, px, py)


static func build(layout: Array) -> void:
	"""Compose the room for `layout` (an Array of equal-length Strings). Cheap when unchanged."""
	var key := "\n".join(PackedStringArray(layout))
	if key == _room_key and _room != null:
		return
	_room_key = key
	_cells.clear()
	var rows := layout.size()
	var cols := String(layout[0]).length() if rows > 0 else 0
	var room := Image.create(maxi(1, cols * CELL), maxi(1, rows * CELL), false, Image.FORMAT_RGBA8)
	room.fill(Color(0.08, 0.06, 0.05, 1.0))
	# One seamless plank tile (see tools/bake_sanctuary.py for how it was chosen).
	var floor_tile := _piece("floor")
	var wall := _piece("wall")
	var window := _piece("window")
	# 1. floor under everything that is not wall (the door stands on floor too).
	for y in range(rows):
		var line := String(layout[y])
		for x in range(cols):
			if line[x] == "#":
				continue
			_blit(room, floor_tile, x * CELL, y * CELL)
	# 2. walls, with windows along the top.
	for y in range(rows):
		var line := String(layout[y])
		for x in range(cols):
			if line[x] != "#":
				continue
			var t: Image = window if (y == 0 and x in WINDOW_COLS and window != null) else wall
			_blit(room, t, x * CELL, y * CELL)
	# 3. rugs first (they lie on the floor), then everything else sorted top to bottom so a lower
	#    object overlaps the one behind it.
	var items: Array = []
	for d in DECOR:
		if int(d[1]) < cols and int(d[2]) < rows:
			items.append({"name": String(d[0]), "x": int(d[1]), "y": int(d[2]), "anchor": String(d[3]),
				"rug": String(d[0]).begins_with("rug_")})
	for y in range(rows):
		var line := String(layout[y])
		for x in range(cols):
			var ch := line[x]
			if STATION_PIECE.has(ch):
				items.append({"name": String(STATION_PIECE[ch]), "x": x, "y": y, "anchor": "bottom", "rug": false})
	items.sort_custom(func(a, b):
		if a.rug != b.rug:
			return a.rug
		return a.y < b.y)
	for it in items:
		_place(room, it.name, it.x, it.y, it.anchor)
	_room = room


static func cell_path(x: int, y: int) -> String:
	"""The 32x32 region of the room at cell (x, y), as a path an `[img]` tag can load."""
	if _room == null:
		return ""
	var k := "%d,%d" % [x, y]
	if _cells.has(k):
		return _cells[k]
	var region := _room.get_region(Rect2i(x * CELL, y * CELL, CELL, CELL))
	var tex := ImageTexture.create_from_image(region)
	var dyn := _DYN + "%d_%d_%d.png" % [absi(hash(_room_key)), x, y]
	tex.take_over_path(dyn)
	_keepalive.append(tex)
	_cells[k] = dyn
	return dyn
