extends RefCounted
## The overworld drawn as ONE composed image, the way the Sanctuary room is.
##
## Phase 2.95 PHASE 2. The map used to be a grid of coloured letters. The server still decides
## every cell - line of sight, fog, which overlay wins - and now sends what each cell IS beside
## how it looks (`payload.meaning`) and which biome's ground it stands on (`payload.biomes`).
## This turns those two grids into a picture.
##
## WHY ONE IMAGE RATHER THAN ONE SPRITE PER CELL. BBCode cannot composite two images into a
## single cell, so a transparent prop drawn over a ground would punch a hole through to the
## canvas - the fault that made the dungeon pre-composite every one of its sprites onto its floor
## offline. Composing the whole grid here means the ground and the thing standing on it are laid
## up in one buffer and the grid then draws slices of it. That also makes a figure larger than
## its cell possible later, which `sanctuary_room.gd::overlay_cells` already does.
##
## COST, measured before this was written rather than after: 529 inline images cost 10.4 ms a
## redraw and making every tile hoverable adds 0.10 ms. At one move a second that is about one
## percent of a client core.
const DIR := "res://client/sprites/overworld32/"
const CELL := 32
const _DYN := "res://__overworld/"

## `empty` and `void` have no tile ON PURPOSE - see tools/bake_overworld_tiles.py. Empty IS the
## biome ground, and void is a square outside your sight.
const NO_TILE := ["empty", "void", ""]

## Overlays that share another overlay's picture. A spent node inside a hotzone still wants the
## hotzone warning drawn on it - what marks it as spent is the dimming below, not a sprite of
## its own.
const OVERLAY_SPRITE := {"hotdepleted": "hot"}

static var _grid: Image = null
static var _key: String = ""
static var _cells: Dictionary = {}
static var _tile_cache: Dictionary = {}
static var _keepalive: Array = []


static func available() -> bool:
	"""Whether the art is present. Licence-restricted sprites are not in git, so a build without
	them must fall back to the text map rather than draw nothing."""
	return ResourceLoader.exists(DIR + "ground/plains.png")


static func _img(path: String) -> Image:
	if _tile_cache.has(path):
		return _tile_cache[path]
	var im: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			im = tex.get_image()
			if im != null:
				if im.is_compressed():
					im.decompress()
				im.convert(Image.FORMAT_RGBA8)
	_tile_cache[path] = im
	return im


## How much bigger a FIGURE is drawn than the 32px cell it stands on.
##
## Owner 2026-09-12: *"the player sprite still looks a little small on the overworld map."* It
## was: the art is 32x32 with padding, so a character's actual body is about 17 by 30 pixels, and
## the grid then draws each cell at 26 screen pixels - so a person came out around 14 pixels wide.
## Drawing the figure at 1.35x and anchoring it to the BOTTOM of its cell lets it overflow upward
## into the square above, which is what every tile-based game does and what this renderer was
## built to allow: *"that also makes a figure larger than its cell possible later."*
const FIGURE_SCALE := 1.35
static var _figure_cache: Dictionary = {}


static func _figure_img(path: String) -> Image:
	"""A figure sprite at FIGURE_SCALE, cached separately from the tile it stands on.

	Its own cache on purpose: `_img` hands back the SHARED image for a path, and resizing that in
	place would silently scale up every other use of the same file."""
	if _figure_cache.has(path):
		return _figure_cache[path]
	var src := _img(path)
	var out: Image = null
	if src != null:
		out = src.duplicate()
		out.resize(maxi(1, int(round(src.get_width() * FIGURE_SCALE))),
			maxi(1, int(round(src.get_height() * FIGURE_SCALE))), Image.INTERPOLATE_NEAREST)
	_figure_cache[path] = out
	return out


static func _ground(biome: String) -> Image:
	var im := _img(DIR + "ground/%s.png" % biome)
	return im if im != null else _img(DIR + "ground/plains.png")


static func _overlay_name(meaning: String) -> String:
	"""An overlay's sprite name, or "" if this meaning is terrain.

	Meanings that begin with `!` are overlays rather than tiles - the server marks them that way
	so a dungeon marker can never be mistaken for a tile called "dungeon". Two of them carry the
	tile they sit on after a colon (`!hot:tree`, `!depleted:ore_vein`); those still draw the
	tile, with the overlay over it."""
	if not meaning.begins_with("!"):
		return ""
	var body := meaning.substr(1)
	var colon := body.find(":")
	return body.substr(0, colon) if colon >= 0 else body


static func _under_tile(meaning: String) -> String:
	"""What a `!hot:tree` style meaning is standing on. Empty for a plain overlay."""
	var colon := meaning.find(":")
	return meaning.substr(colon + 1) if colon >= 0 else ""


static func build(meaning_rows: Array, biome_rows: Array, figures: Dictionary = {}) -> bool:
	"""Compose the map. Cheap when nothing has changed, which is most redraws that are not moves."""
	if meaning_rows.is_empty() or not available():
		return false
	var rows := meaning_rows.size()
	var cols: int = meaning_rows[0].size()
	if cols <= 0:
		return false
	var key := "%d,%d|" % [rows, cols]
	for r in meaning_rows:
		key += "".join(r) + ";"
	for r in biome_rows:
		key += "".join(r) + ";"
	# Figures are part of the key: the map has to recompose when you walk, and you are a figure.
	for fk in figures:
		key += "%s=%s;" % [fk, str(figures[fk])]
	if key == _key and _grid != null:
		return true
	_key = key
	_cells.clear()
	var grid := Image.create(cols * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	# Black behind everything: a cell outside your sight draws nothing, and this is what it
	# leaves - the same darkness the text map left as two blank characters.
	grid.fill(Color(0, 0, 0, 1))

	for y in range(rows):
		var mrow: PackedStringArray = meaning_rows[y]
		var brow: PackedStringArray = biome_rows[y] if y < biome_rows.size() else PackedStringArray()
		for x in range(mini(cols, mrow.size())):
			var meaning := String(mrow[x])
			if meaning == "" or meaning == "!void":
				continue
			var biome := String(brow[x]) if x < brow.size() else "plains"
			var g := _ground(biome)
			if g != null:
				grid.blit_rect(g, Rect2i(Vector2i.ZERO, g.get_size()), Vector2i(x * CELL, y * CELL))

			var overlay := _overlay_name(meaning)
			# The tile itself. An overlay that names what it stands on still draws it, so a
			# gatherable inside a hotzone is visibly a tree with a warning on it rather than
			# just a warning.
			var tile_name := meaning if overlay == "" else _under_tile(meaning)
			if not (tile_name in NO_TILE):
				var t := _img(DIR + "tile/%s.png" % tile_name)
				if t != null:
					grid.blend_rect(t, Rect2i(Vector2i.ZERO, t.get_size()), Vector2i(x * CELL, y * CELL))
			if overlay != "" and overlay != "fog" and not figures.has("%d,%d" % [x, y]):
				var o := _img(DIR + "overlay/%s.png" % OVERLAY_SPRITE.get(overlay, overlay))
				if o != null:
					grid.blend_rect(o, Rect2i(Vector2i.ZERO, o.get_size()), Vector2i(x * CELL, y * CELL))

			# A FIGURE - you, another player, and the companion travelling with them.
			#
			# THE INDENTATION HERE IS THE POINT. This block sat one level deeper for two
			# releases, inside the `not figures.has(...)` branch above - a condition that is
			# FALSE exactly when there is a figure to draw. So it could never run, and the map
			# showed no player at all. It compiled, and a probe that read the source found every
			# line it was looking for. Only a screenshot showed the empty square.
			#
			# Hand it a TRANSPARENT sprite (`overworld_pad32`), never the floor-backed set: those
			# carry the dungeon floor baked in, because BBCode could not composite there. Here
			# the compositing happens above, so a floor-backed figure stands on the wrong ground.
			var fig_entry = figures.get("%d,%d" % [x, y], null)
			if fig_entry != null:
				# A cell holds ONE figure. A companion is not drawn on its owner's square any
				# more - it stands on the square its owner just walked out of, which is what the
				# old letter map did and what the owner expected to keep: the client picks that
				# cell and sends the companion as its own entry.
				var fpath := ""
				if fig_entry is Dictionary:
					fpath = String(fig_entry.get("main", ""))
				else:
					fpath = String(fig_entry)
				if fpath != "":
					var fi := _figure_img(fpath)
					if fi != null:
						# Centred on its cell and anchored to the BOTTOM of it, so a figure taller
						# than its square stands ON the tile and overflows into the one above
						# rather than floating.
						grid.blend_rect(fi, Rect2i(Vector2i.ZERO, fi.get_size()),
							Vector2i(x * CELL + (CELL - fi.get_width()) / 2,
								(y + 1) * CELL - fi.get_height()))
			if overlay == "fog":
				# Remembered ground, not seen ground. Darkened rather than hidden, which is what
				# the text map did with a dim colour.
				_darken(grid, x, y, 0.45)
			elif overlay == "depleted" or overlay == "hotdepleted":
				# A node you have already harvested. The TEXT map drew it as a dim grey comma -
				# obviously spent. The sprite map drew the tile and then looked for an overlay called
				# "depleted", which does not exist, so a used-up ore vein looked exactly like a fresh
				# one. Owner 2026-09-12: "not sure if they are clearing properly once I get them."
				# They WERE clearing. They just did not look it.
				_darken(grid, x, y, 0.42)
	_grid = grid
	return true


static func _darken(grid: Image, cx: int, cy: int, amount: float) -> void:
	for yy in range(CELL):
		for xx in range(CELL):
			var px := grid.get_pixel(cx * CELL + xx, cy * CELL + yy)
			grid.set_pixel(cx * CELL + xx, cy * CELL + yy,
				Color(px.r * amount, px.g * amount, px.b * amount, px.a))


static func cell_path(x: int, y: int) -> String:
	"""The 32x32 slice of the composed map at cell (x, y), as a path an `[img]` tag can load."""
	if _grid == null:
		return ""
	var k := "%d,%d" % [x, y]
	if _cells.has(k):
		return _cells[k]
	if (x + 1) * CELL > _grid.get_width() or (y + 1) * CELL > _grid.get_height():
		return ""
	var region := _grid.get_region(Rect2i(x * CELL, y * CELL, CELL, CELL))
	var tex := ImageTexture.create_from_image(region)
	var dyn := _DYN + "%d_%d_%d.png" % [absi(hash(_key)), x, y]
	tex.take_over_path(dyn)
	_keepalive.append(tex)
	if _keepalive.size() > 4096:
		_keepalive = _keepalive.slice(_keepalive.size() - 2048)
	_cells[k] = dyn
	return dyn
