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
		dungeons: Dictionary = {}, anim_tick: int = 0, mark_cell: Vector2i = Vector2i(-1, -1),
		mark_arrow: Vector2i = Vector2i.ZERO) -> bool:
	"""Compose the map. Cheap when nothing has changed, which is most redraws that are not moves.

	`anim_tick` is the IDLE heartbeat. Every figure on the map - you, your companion, other
	players, their companions - rises and settles by a pixel on a slow cycle, so the world
	does not read as a diorama of statues. Owner 2026-09-14: *"ideally we want the player and
	their companion to seem more alive rather than just having art where they just stand
	still."*

	A one-pixel offset rather than new art is the whole point: it costs nothing, and it works
	for every figure regardless of what its sprite is. Half our 80 player sprites have no
	alternate poses at all, and companions are monster art with no walk frames whatsoever -
	any solution built on extra frames would have covered some of the map and not the rest."""
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
	# The marked cell too - the guide points at ONE door, and the map has to redraw when he
	# starts and stops pointing.
	key += "m%d,%d>%d,%d;" % [mark_cell.x, mark_cell.y, mark_arrow.x, mark_arrow.y]
	# Dungeon families are part of the picture now, so they are part of what decides whether it
	# has to be redrawn.
	for dk in dungeons:
		var _di = dungeons[dk]
		key += "d%s=%s;" % [dk, String(_di.get("family", "")) if _di is Dictionary else ""]
	# The idle beat is part of the key, or the cache would hand back the previous frame and
	# nothing would ever move.
	key += "a%d;" % anim_tick
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
			# ⛑ A HOTZONE IS A WASH OVER THE GROUND, NOT A SPRITE PER SQUARE. It is applied
			# here rather than in the overlay block below because it must go UNDER the figures
			# and under the big art - it tints the country, it does not sit on top of people
			# standing in it. And unlike the old sprite it runs even when a figure is on the
			# cell, so the square you are standing in still reads as dangerous.
			if overlay == "hot" or overlay == "hotdepleted":
				_wash(grid, x, y, HOT_WASH)
			if overlay != "" and overlay != "fog" and overlay != "hot" and overlay != "hotdepleted" and not figures.has("%d,%d" % [x, y]):
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
		# The idle bob. Phase is offset by the figure's own cell so a crowd does not breathe in
		# unison, which reads as a glitch rather than as life.
		var _phase: int = (anim_tick + int(fr["x"]) * 3 + int(fr["y"]) * 5) % 6
		var _bob: int = -1 if _phase < 3 else 0
		_blend_clipped(grid, fi, int(fr["x"]) * CELL + (CELL - fi.get_width()) / 2,
			(int(fr["y"]) + 1) * CELL - fi.get_height() + _bob)

	# PASS 4 - the guide's pointer. ONE cell, ringed, drawn over everything so it is not hidden
	# behind a tower or a figure.
	#
	# Owner 2026-09-14: *"the highlight for the map should only highlight the door he's wanting
	# you to leave out of."* A post has several doors; ringing the map display pointed at all of
	# them and therefore at none. Drawn INTO the map rather than as an overlay Control because a
	# map cell is not a Control - the grid is one composited image.
	#
	# When the marked tile is off the grid the client passes `mark_arrow` (its direction in
	# screen cells) and a cell a few steps from the player; a gold arrowhead is drawn there
	# instead of the ring, pointing the way. Outlined dark so it reads on sand and snow alike.
	if mark_cell.x >= 0 and mark_cell.y >= 0 and mark_cell.x < cols and mark_cell.y < rows 			and mark_arrow != Vector2i.ZERO:
		var ax: int = mark_cell.x * CELL
		var ay: int = mark_cell.y * CELL
		var d := Vector2(mark_arrow).normalized()
		var half: float = (CELL - 1) / 2.0
		var edge := Color(0.1, 0.07, 0.02, 1.0)
		var gold_a := Color(1.0, 0.84, 0.25, 1.0)
		for j in range(CELL):
			for i in range(CELL):
				var u: float = i - half
				var v: float = j - half
				var along: float = u * d.x + v * d.y
				var across: float = absf(-u * d.y + v * d.x)
				# Tip at +12.5 along the direction, base at -8.5, half-width ~7 at the base. Longer
				# than it is wide on purpose: an equilateral triangle does not say which way it means.
				if along <= 14.5 and along >= -10.5 and across <= (14.5 - along) * 0.36 + 1.0:
					var inner: bool = along <= 12.5 and along >= -8.5 and across <= (12.5 - along) * 0.33
					_px(grid, ax + i, ay + j, gold_a if inner else edge)
	elif mark_cell.x >= 0 and mark_cell.y >= 0 and mark_cell.x < cols and mark_cell.y < rows:
		var mx: int = mark_cell.x * CELL
		var my: int = mark_cell.y * CELL
		var gold := Color(1.0, 0.84, 0.25, 1.0)
		for t in range(3):                      # a 3px ring, inset so it frames the tile
			for i in range(CELL):
				_px(grid, mx + i, my + t, gold)
				_px(grid, mx + i, my + CELL - 1 - t, gold)
				_px(grid, mx + t, my + i, gold)
				_px(grid, mx + CELL - 1 - t, my + i, gold)

	_grid = grid
	return true


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, c)


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


## ⚑ THE HOTZONE WASH. Owner 2026-09-17: *"they don't need a half broken campfire sprite on
## them... or just a red tint to the tiles."* A hotzone is tens of tiles across and the old overlay
## stamped one small fire on each of them, which read as clutter rather than as danger.
##
## Danger is a property of the GROUND over an area, so the area is what gets painted. A depleted
## hotzone washes weaker, so "still dangerous, nothing left to take" stays legible.
## ⛑ ONE COLOUR FOR BOTH. `hotdepleted` is a SPENT NODE STANDING IN a hotzone, not a spent
## hotzone - `OVERLAY_SPRITE` says so by mapping it to the same `hot` picture. The ground is
## exactly as dangerous, so it gets exactly the same wash, and what marks it spent is the
## `_darken` further down that was already doing that job.
##
## Measured, not guessed: a 0.26 wash over plains rendered as BROWN - red at low alpha over green
## desaturates to mud and reads as dirt, which is the opposite of a warning. Deeper and stronger.
const HOT_WASH := Color(0.82, 0.04, 0.04, 0.52)
static var _wash_cache: Dictionary = {}


static func _wash(grid: Image, cx: int, cy: int, color: Color) -> void:
	"""Alpha-blend one flat colour over a cell.

	⛑ A RECT OPERATION, FOR THE SAME MEASURED REASON AS `_darken`. That function's note records
	15.2 ms of an 18.7 ms compose lost to a per-pixel loop, and a live report of *"a delay to our
	actions intermittently"*. A hotzone can cover more cells than fog does, so a naive loop here
	would bring that straight back."""
	var key := "%d" % int(color.to_rgba32())
	var tint: Image = _wash_cache.get(key, null)
	if tint == null:
		tint = Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
		tint.fill(color)
		_wash_cache[key] = tint
	grid.blend_rect(tint, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)), Vector2i(cx * CELL, cy * CELL))


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
