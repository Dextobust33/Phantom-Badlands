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
	"M": "mirror",
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

## Owner 2026-09-11: *"we may also want to add a slight highlight to interactable objects vs
## decorations."* Stations get a soft two-ring outline in this colour; decoration gets none, so
## the difference reads at a glance without a legend.
const HIGHLIGHT := Color(1.0, 0.88, 0.55)
const HIGHLIGHT_INNER_A := 0.62
const HIGHLIGHT_OUTER_A := 0.26
## The player is drawn at this multiple of the raw overworld sprite (17x31). Owner: *"is it
## possible for us to roughly double the size of the player sprite in there?"* - at 2x the figure
## stands two cells tall, the scale of the furniture around it.
const PLAYER_SCALE := 2
## Companions on their cushions, relative to their 32px dungeon sprite. Owner: *"I feel like the
## companion sprites should maybe be around 30% larger ... I kind of like the look of the player
## being a bit larger than the companions."* 1.3 keeps them clearly smaller than the 2x player.
## (Non-integer on purpose: these sprites are already a ~0.5x reduction of the Time Fantasy
## originals, so a whole-number step from them would have to be 2x - bigger than the player.)
const COMPANION_SCALE := 1.3

static var _pieces: Dictionary = {}
static var _outlined: Dictionary = {}
static var _sprite_imgs: Dictionary = {}
static var _overlay_cells: Dictionary = {}
static var _overlay_keep: Array = []
## Every (position, facing, frame) a figure has stood in is one cached 32px texture per cell it
## covers. Bounded, so a long session walking laps of the room cannot grow it without limit.
const OVERLAY_CACHE_MAX := 2000
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


static func _outline(name: String) -> Image:
	"""`name`'s piece with a soft highlight ring around its visible pixels (2px, two strengths).
	The ring is drawn BEHIND the art, so it reads as a glow and never covers a pixel of it."""
	if _outlined.has(name):
		return _outlined[name]
	var p := _piece(name)
	if p == null:
		return null
	var w := p.get_width()
	var h := p.get_height()
	var out := Image.create(w + 4, h + 4, false, Image.FORMAT_RGBA8)
	var inner := Color(HIGHLIGHT.r, HIGHLIGHT.g, HIGHLIGHT.b, HIGHLIGHT_INNER_A)
	var outer := Color(HIGHLIGHT.r, HIGHLIGHT.g, HIGHLIGHT.b, HIGHLIGHT_OUTER_A)
	for y in range(h):
		for x in range(w):
			if p.get_pixel(x, y).a < 0.5:
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var d := maxi(absi(dx), absi(dy))
					if d == 0:
						continue
					var ox := x + dx + 2
					var oy := y + dy + 2
					var cur := out.get_pixel(ox, oy)
					var want: Color = inner if d == 1 else outer
					if want.a > cur.a:
						out.set_pixel(ox, oy, want)
	out.blend_rect(p, Rect2i(Vector2i.ZERO, p.get_size()), Vector2i(2, 2))
	_outlined[name] = out
	return out


static func keyed(path: String) -> Image:
	"""A floor-backed 32px sprite with its floor made TRANSPARENT, via the dungeon compositor's
	border-connected colour key - the same one that lets the player stand on dungeon props."""
	var DC = load("res://client/dungeon_composite.gd")
	var img: Image = DC._image_for(path)
	if img == null:
		return null
	var out := img.duplicate() as Image
	var mask: PackedInt32Array = DC._background_mask(path, img)
	var w := out.get_width()
	for i in mask:
		out.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
	return out


static func _load_rgba(path: String) -> Image:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func sprite_image(path: String, scale: float, key_floor: bool) -> Image:
	"""A sprite ready to stand in the room: transparent, scaled NEAREST. Cached per (path, scale).
	`key_floor` strips the baked dungeon floor from a floor-backed 32px sprite (companions)."""
	var k := "%s|%s|%s" % [path, scale, key_floor]
	if _sprite_imgs.has(k):
		return _sprite_imgs[k]
	var img: Image = keyed(path) if key_floor else _load_rgba(path)
	if img != null and not is_equal_approx(scale, 1.0):
		img = img.duplicate() as Image
		img.resize(maxi(1, int(round(img.get_width() * scale))), maxi(1, int(round(img.get_height() * scale))),
			Image.INTERPOLATE_NEAREST)
	_sprite_imgs[k] = img
	return img


static func overlay_cells(sprites: Array) -> Dictionary:
	"""Stand every sprite in `sprites` on its cell and return {Vector2i cell: path} for each cell
	any of them covers. A sprite is {key, img, x, y, lift}: `img` from `sprite_image`, feet on the
	lower edge of cell (x, y) raised by `lift` px. Sprites overlapping one cell are drawn in feet
	order, so whoever stands lower is in front - the player in front of a companion behind them.

	This is what lets sprites be bigger than a cell AND animate: the room is one image, so a
	figure two cells tall is two regions with the figure blended in, and a new frame is just a
	new combination for the cells it touches. Cached per cell by exactly which frames are on it."""
	if _room == null:
		return {}
	var room_cells := Vector2i(_room.get_width() / CELL, _room.get_height() / CELL)
	var placed: Array = []
	var per_cell := {}
	for sp in sprites:
		var img: Image = sp.get("img", null)
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		var cx := int(sp.get("x", 0))
		var cy := int(sp.get("y", 0))
		var px := cx * CELL + CELL / 2 - w / 2
		var py := (cy + 1) * CELL - h - int(sp.get("lift", 0))
		var entry := {"key": String(sp.get("key", "")), "img": img, "px": px, "py": py, "foot": cy}
		placed.append(entry)
		for gy in range(floori(float(py) / CELL), floori(float(py + h - 1) / CELL) + 1):
			for gx in range(floori(float(px) / CELL), floori(float(px + w - 1) / CELL) + 1):
				if gx < 0 or gy < 0 or gx >= room_cells.x or gy >= room_cells.y:
					continue
				var c := Vector2i(gx, gy)
				if not per_cell.has(c):
					per_cell[c] = []
				per_cell[c].append(entry)
	if _overlay_cells.size() > OVERLAY_CACHE_MAX:
		_overlay_cells.clear()
		_overlay_keep.clear()
	var out := {}
	var rk := absi(hash(_room_key))
	for c in per_cell:
		var list: Array = per_cell[c]
		list.sort_custom(func(a, b): return a.foot < b.foot)
		var sig := "%d|%d,%d" % [rk, c.x, c.y]
		for e in list:
			sig += "|%s@%d,%d" % [e.key, e.px, e.py]
		if _overlay_cells.has(sig):
			out[c] = _overlay_cells[sig]
			continue
		var region := _room.get_region(Rect2i(c.x * CELL, c.y * CELL, CELL, CELL))
		for e in list:
			var eimg: Image = e.img
			var src := Rect2i(Vector2i.ZERO, eimg.get_size())
			var dst := Vector2i(int(e.px) - c.x * CELL, int(e.py) - c.y * CELL)
			if dst.x < 0:
				src.position.x -= dst.x; src.size.x += dst.x; dst.x = 0
			if dst.y < 0:
				src.position.y -= dst.y; src.size.y += dst.y; dst.y = 0
			if src.size.x > 0 and src.size.y > 0:
				region.blend_rect(eimg, src, dst)
		var tex := ImageTexture.create_from_image(region)
		var dyn := _DYN + "o%d.png" % absi(hash(sig))
		tex.take_over_path(dyn)
		_overlay_keep.append(tex)
		_overlay_cells[sig] = dyn
		out[c] = dyn
	return out


static func build(layout: Array) -> void:
	"""Compose the room for `layout` (an Array of equal-length Strings). Cheap when unchanged.
	Everything that MOVES or ANIMATES - you, your companions - is drawn over it by
	`overlay_cells`, so the room itself only changes when the layout does."""
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
				items.append({"name": String(STATION_PIECE[ch]), "x": x, "y": y, "anchor": "bottom", "rug": false,
					"station": true})
	items.sort_custom(func(a, b):
		if a.rug != b.rug:
			return a.rug
		return a.y < b.y)
	for it in items:
		if it.get("station", false):
			var o := _outline(it.name)
			if o != null:
				# The outlined image is 2px bigger on every side; anchor it as the piece would be.
				var px := int(it.x) * CELL + CELL / 2 - o.get_width() / 2
				var py := (int(it.y) + 1) * CELL - (o.get_height() - 2)
				_blit(room, o, px, py)
				continue
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
