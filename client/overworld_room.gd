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

## ART THAT IS BIGGER THAN ITS CELL.
##
## Owner 2026-09-13: *"The samples you provided all look like multi tile artwork you've attempted
## to break down into one. We should instead use the multitile art so they appear as complete on
## the map with only a single base tile serving as the interactable tile."*
##
## Nineteen tiles were cut from blocks of two or three cells square and then SHRUNK into one
## 32-pixel square - `companion_stable` and `tree` threw away 89% of their pixels, and a door was
## worse than that: the cell picked was a fragment out of the middle of a 3x2 door, so it was not
## a small door, it was a piece of one.
##
## The baker keeps the full-size art now, and this draws it across the cells it really occupies,
## anchored to the BASE cell - the one the server knows about and the player walks into. Nothing
## on the server changes: one tile is still one tile, it is only drawn bigger. This is the same
## mechanism `FIGURE_SCALE` already uses, and the reason this renderer composes one image at all.
const BIG_DIR := DIR + "big/"
static var _big_spans: Dictionary = {}
static var _big_loaded := false


static func _load_big_spans() -> void:
	if _big_loaded:
		return
	_big_loaded = true
	var f := FileAccess.open(BIG_DIR + "big_tiles.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_big_spans = parsed


static func _big_img(tile_name: String) -> Image:
	"""The full-size art for a tile, or null if it has none."""
	_load_big_spans()
	if not _big_spans.has(tile_name):
		return null
	return _img(BIG_DIR + "%s.png" % tile_name)

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


static func _overlay_img(overlay: String) -> Image:
	"""An overlay's picture, with the fallbacks that stop a new marker drawing a hole.

	Dungeon markers vary by what the place IS (`dungeon_cave`, `dungeon_crypt`, ...). A family
	whose art has not been cut yet falls back to the plain `dungeon` marker rather than to
	nothing: a dungeon you cannot see on the map is far worse than one drawn generically, and a
	missing file is exactly how the 53-type variety could regress silently."""
	var im := _img(DIR + "overlay/%s.png" % OVERLAY_SPRITE.get(overlay, overlay))
	if im == null and overlay.begins_with("dungeon_"):
		im = _img(DIR + "overlay/dungeon.png")
	return im


static func _under_tile(meaning: String) -> String:
	"""What a `!hot:tree` style meaning is standing on. Empty for a plain overlay."""
	var colon := meaning.find(":")
	return meaning.substr(colon + 1) if colon >= 0 else ""


static func build(meaning_rows: Array, biome_rows: Array, figures: Dictionary = {},
		dungeons: Dictionary = {}) -> bool:
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
	# Dungeon families are part of the picture now, so they are part of what decides whether it
	# has to be redrawn.
	for dk in dungeons:
		var _di = dungeons[dk]
		key += "d%s=%s;" % [dk, String(_di.get("family", "")) if _di is Dictionary else ""]
	if key == _key and _grid != null:
		return true
	_key = key
	_cells.clear()
	var grid := Image.create(cols * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	# Black behind everything: a cell outside your sight draws nothing, and this is what it
	# leaves - the same darkness the text map left as two blank characters.
	grid.fill(Color(0, 0, 0, 1))
	# Collected during the cell pass and drawn after it - see the notes at each append.
	var bigs: Array = []
	var figs: Array = []

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
				# Art bigger than a cell is DEFERRED to a second pass. Drawn here it would be painted
				# over by the cells to its right and below, which have not been reached yet - the grid
				# fills west to east, north to south.
				if _big_img(tile_name) != null:
					# ⚑ CARRY THE DIMMING WITH IT. `_darken` shades the CELL, in pass one - and
					# pass two then paints the full-size art straight over the top at full
					# brightness. Owner 2026-09-13: *"the big tree gatherables don't change
					# visually once gathered."* Exactly that: a spent tree was dimmed and then
					# un-dimmed, so the one piece of feedback that says "you already took this"
					# was lost for every tile big enough to matter.
					var shade := 0.0
					if overlay == "fog":
						shade = 0.45
					elif overlay == "depleted" or overlay == "hotdepleted":
						shade = 0.42
					bigs.append({"x": x, "y": y, "name": tile_name, "shade": shade})
				else:
					var t := _img(DIR + "tile/%s.png" % tile_name)
					if t != null:
						grid.blend_rect(t, Rect2i(Vector2i.ZERO, t.get_size()), Vector2i(x * CELL, y * CELL))
			if overlay != "" and overlay != "fog" and not figures.has("%d,%d" % [x, y]):
				# A dungeon's marker depends on what KIND of place it is, and that arrives in the
				# `dungeons` side channel rather than in the meaning string - see the note in
				# `world_system._map_cells`. Older servers send no family and get the generic
				# marker, which is exactly the fallback `_overlay_img` already provides.
				var oname := overlay
				if overlay == "dungeon":
					var dinfo = dungeons.get("%d,%d" % [x, y], null)
					if dinfo is Dictionary:
						var fam := String(dinfo.get("family", ""))
						if fam != "":
							oname = "dungeon_%s" % fam
				var o := _overlay_img(oname)
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
			# A FIGURE is COLLECTED, not drawn yet. People must stand in FRONT of the big art laid
			# down in the next pass - a player walking past a stable should not vanish behind it.
			if figures.has("%d,%d" % [x, y]):
				figs.append({"x": x, "y": y, "e": figures["%d,%d" % [x, y]]})
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

	# PASS 2 - art that is bigger than its cell.
	#
	# Sorted south-then-east so a structure nearer the viewer overlaps one behind it, which is
	# the only ordering that looks right when two of them are adjacent. Each is anchored to the
	# BOTTOM of its base cell and centred on it, so it stands ON the square the player walks into
	# and grows upward - exactly what a figure does, and why this renderer composes one image.
	bigs.sort_custom(func(a, b): return (a["y"] * cols + a["x"]) < (b["y"] * cols + b["x"]))
	for b in bigs:
		var bi := _big_img(String(b["name"]))
		if bi == null:
			continue
		var bx: int = int(b["x"]) * CELL + (CELL - bi.get_width()) / 2
		var by: int = (int(b["y"]) + 1) * CELL - bi.get_height()
		# Shade the ART, not the cell under it - the art is what the player sees. Cached per
		# (tile, amount): dimming is a per-pixel loop, and a per-pixel loop on every compose is
		# precisely what made the map stutter before `_darken` became a rect operation.
		_blend_clipped(grid, _dimmed_big(String(b["name"]), float(b.get("shade", 0.0))), bx, by)

	# PASS 3 - people, last, so nobody is hidden behind a building.
	for fr in figs:
		var fig_entry = fr["e"]
		# A cell holds ONE figure. A companion is not drawn on its owner's square any more - it
		# stands on the square its owner just walked out of, which is what the old letter map did
		# and what the owner expected to keep: the client picks that cell and sends the companion
		# as its own entry.
		var fpath := ""
		if fig_entry is Dictionary:
			fpath = String(fig_entry.get("main", ""))
		else:
			fpath = String(fig_entry)
		if fpath == "":
			continue
		var fi := _figure_img(fpath)
		if fi == null:
			continue
		# Centred on its cell and anchored to the BOTTOM of it, so a figure taller than its
		# square stands ON the tile and overflows into the one above rather than floating.
		_blend_clipped(grid, fi, int(fr["x"]) * CELL + (CELL - fi.get_width()) / 2,
			(int(fr["y"]) + 1) * CELL - fi.get_height())

	_grid = grid
	return true


static func _blend_clipped(grid: Image, src: Image, dx: int, dy: int) -> void:
	"""Blend `src` at (dx, dy), clipping to the grid.

	⚑ CLIPPING IS THE POINT. Art bigger than its cell routinely hangs off the edge of the view -
	a 3x2 door on the top row reaches two rows above the map - and `blend_rect` with a
	destination outside the image silently draws nothing at all. That would make exactly the
	tiles nearest the edge disappear, which is the hardest kind of fault to notice because the
	middle of the screen looks perfect."""
	var sw := src.get_width()
	var sh := src.get_height()
	var sx := maxi(0, -dx)
	var sy := maxi(0, -dy)
	var w := mini(sw - sx, grid.get_width() - maxi(0, dx))
	var h := mini(sh - sy, grid.get_height() - maxi(0, dy))
	if w <= 0 or h <= 0:
		return
	grid.blend_rect(src, Rect2i(sx, sy, w, h), Vector2i(maxi(0, dx), maxi(0, dy)))


## One pre-made translucent black square per darkening amount. Two are ever used (fog and a
## spent gathering node), so this cache never holds more than a couple of 32x32 images.
static var _shade_cache: Dictionary = {}


static var _dim_big_cache: Dictionary = {}


static func _dimmed_big(tile_name: String, amount: float) -> Image:
	"""Full-size art, shaded - a spent tree, or one remembered through fog.

	`_darken` shades one CELL of the composed grid, which is the right thing for an ordinary
	tile and useless for art drawn in a LATER pass: the big art lands on top and undoes it.
	Owner 2026-09-13: *"the big tree gatherables don't change visually once gathered."*

	Multiplying the colour and leaving alpha alone keeps the transparent margins transparent,
	which blending a translucent black square over the whole rect would not.

	⚑ CACHED, because this is a per-pixel loop in script and there are only a handful of (tile,
	amount) pairs in the game. An uncached version would run on every compose for every spent
	node in view - the same shape as the fog darkening that measured 15.2ms of an 18.7ms
	compose before it was rewritten."""
	var base := _big_img(tile_name)
	if base == null or amount <= 0.0:
		return base
	var key := "%s|%d" % [tile_name, int(round(amount * 1000.0))]
	if _dim_big_cache.has(key):
		return _dim_big_cache[key]
	var img := base.duplicate() as Image
	var k := clampf(amount, 0.0, 1.0)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, c.a))
	_dim_big_cache[key] = img
	return img


static func _darken(grid: Image, cx: int, cy: int, amount: float) -> void:
	"""Multiply one cell toward black - remembered ground, or a node already harvested.

	⚑ THIS IS A RECT OPERATION ON PURPOSE. It used to be a per-pixel GDScript loop: 1024
	`get_pixel` plus 1024 `set_pixel` per cell, and a well-explored view darkens ~220 of them,
	which measured 15.2 ms of an 18.7 ms compose - on EVERY step. Owner, from live play
	2026-09-13: *"There is a delay to our actions intermittently."* Intermittent because the cost
	is proportional to how much FOG is in view, which changes as you walk and grows as you
	explore.

	Alpha-blending BLACK at `1 - amount` is the same arithmetic the loop was doing:
	`dst*(1-a) + src*a` with src black is exactly `dst * (1 - a)`. It just happens in C++ once
	instead of 2048 times in script."""
	var key := int(round(amount * 1000.0))
	var shade: Image = _shade_cache.get(key, null)
	if shade == null:
		shade = Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
		shade.fill(Color(0, 0, 0, clampf(1.0 - amount, 0.0, 1.0)))
		_shade_cache[key] = shade
	grid.blend_rect(shade, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)),
		Vector2i(cx * CELL, cy * CELL))


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
