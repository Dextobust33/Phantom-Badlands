extends RefCounted
class_name DungeonComposite

## Draws a dungeon sprite ON TOP of its scatter prop instead of instead of it.
##
## THE PROBLEM. Every dungeon cell is one inline BBCode `[img]`, and BBCode cannot layer two
## images in one cell — so the whole tile pipeline solved transparency by BAKING the floor into
## every sprite offline (`overworld_floor32/`, `monster_floor32/`, `egg_floor32/`...). That works
## until a cell holds a PROP: the sprite carries plain floor, so stepping onto a mossy rock
## replaces the rock with bare ground and it pops back when you leave. Owner: *"when a sprite
## steps on a space with a decorative piece on it the decorative piece seems to go away"*, and
## after living with it: *"The occlusion just makes it look janky currently."*
##
## THE THING THAT MAKES IT CHEAP. `Resource.take_over_path()` inserts a resource into the engine's
## resource CACHE under a chosen path, and `ResourceLoader.load()` — which is what RichTextLabel's
## `[img]` tag calls — checks that cache before it ever touches the disk. So an image composited
## in memory can be handed to the existing renderer as an ordinary `res://` string, and the grid
## keeps being built as ONE BBCode string. Verified before any of this was written
## (`tools/probe/dyn_texture_bbcode.gd`): the tag resolves the fake path and sets a 32px line.
##
## The alternative was converting the grid to an `add_image()` token stream, which would have
## meant re-plumbing every cell emitter and the `[center]` wrapper for one visual fix.
##
## HOW THE SPRITE'S BACKGROUND IS FOUND. There is no alpha left to composite with — the bake
## already flattened it — so the background is recovered by COLOUR KEY. The floor tile is a flat
## `#524B24` with zero colour spread (measured; it is why `FLOOR_COLOR` exists at all), and every
## bake laid the sprite over that exact tile unscaled, so background pixels are still exactly it.
## Checked rather than assumed: 120 sampled `overworld_pad32` frames have their transparent-pixel
## count match the baked frame's floor-coloured-pixel count EXACTLY, 120 of 120.
##
## But a key alone is not enough, and this is the part worth keeping. Some sprites contain that
## brown INSIDE the character — a troll has 24 such pixels, a battler up to 8 — and keying those
## would punch prop-coloured speckles through the middle of a monster. So the mask is the floor
## colour REACHED BY FLOOD FILL FROM THE BORDER. Enclosed floor-coloured pixels are part of the
## art and stay exactly as they render today. That is what makes this safe to apply to every
## sprite directory at once rather than a hand-audited list.
##
## Tall props (the lampposts that render as half a lamppost) are the SAME problem — one cell that
## needs two layers — and this is the layer. They are not wired up here yet only because a 16x32
## source still has to be split across two grid rows.

const _DYN_DIR := "res://__dyncomp/"

## path -> Image, so a sprite is pulled off the GPU and decoded ONCE however many props it is
## later drawn over. `get_image()` is a GPU readback; doing it per cell per frame would be
## indefensible, doing it once per sprite for a whole session is free.
static var _img_cache: Dictionary = {}
## "sprite|prop" -> the fake res:// path of the composited texture.
static var _out_cache: Dictionary = {}
## The composited textures themselves. `take_over_path` does NOT keep a resource alive — the
## cache holds a weak reference — so without this the texture is freed the moment the local
## goes out of scope and the [img] tag resolves to nothing. Found by the tile rendering blank.
static var _keepalive: Array = []
## Sprites whose background could not be keyed (wrong size, undecodable). Remembered so a bad
## sprite costs one failed attempt rather than one per redraw.
static var _rejected: Dictionary = {}


static func over_prop(sprite_path: String, prop_path: String) -> String:
	"""`sprite_path` drawn over `prop_path`, as a path the BBCode `[img]` tag can load.

	Returns `sprite_path` UNCHANGED on any failure. Every caller is a hot render path, so this
	never throws and never blocks a tile from drawing — the worst case is the occlusion that
	is there today."""
	if prop_path == "" or sprite_path == "" or sprite_path == prop_path:
		return sprite_path
	var key := sprite_path + "|" + prop_path
	if _out_cache.has(key):
		return _out_cache[key]
	if _rejected.has(key):
		return sprite_path

	var fg := _image_for(sprite_path)
	var bg := _image_for(prop_path)
	if fg == null or bg == null or fg.get_size() != bg.get_size():
		_rejected[key] = true
		return sprite_path

	var mask := _background_mask(sprite_path, fg)
	if mask.is_empty():
		# Nothing keyed as background — the sprite covers its whole tile, so the prop would be
		# invisible anyway. Cache the original so this is not recomputed.
		_out_cache[key] = sprite_path
		return sprite_path

	var w := fg.get_width()
	var out := fg.duplicate() as Image
	for i in mask:
		out.set_pixel(i % w, i / w, bg.get_pixel(i % w, i / w))

	var tex := ImageTexture.create_from_image(out)
	var dyn := _DYN_DIR + "%d.png" % abs(hash(key))
	tex.take_over_path(dyn)
	_keepalive.append(tex)
	_out_cache[key] = dyn
	return dyn


static func overlay(base_path: String, top_path: String) -> String:
	"""`top_path` alpha-composited over `base_path`, as a path the BBCode `[img]` tag can load.

	The sibling of `over_prop`, and deliberately a separate function rather than a flag. They do
	different things for different reasons: `over_prop` recovers a background by COLOUR KEY,
	because the dungeon's sprites had their floor baked in and have no alpha left. Room DECOR is
	cut straight from a tileset and still HAS alpha, so keying it would be both slower and wrong -
	it would punch holes wherever the decor happened to use the floor colour.

	Same cache and same `take_over_path` trick, so the renderer still receives an ordinary
	res:// string."""
	if base_path == "" or top_path == "":
		return base_path
	var key := base_path + "+" + top_path
	if _out_cache.has(key):
		return _out_cache[key]
	if _rejected.has(key):
		return base_path
	var bg := _image_for(base_path)
	var fg := _image_for(top_path)
	if bg == null or fg == null or bg.get_size() != fg.get_size():
		_rejected[key] = true
		return base_path
	var out := bg.duplicate() as Image
	out.blend_rect(fg, Rect2i(Vector2i.ZERO, fg.get_size()), Vector2i.ZERO)
	var tex := ImageTexture.create_from_image(out)
	var dyn := _DYN_DIR + "o%d.png" % abs(hash(key))
	tex.take_over_path(dyn)
	_keepalive.append(tex)
	_out_cache[key] = dyn
	return dyn


## Corner brackets, not a full frame. A closed rectangle around every pickup turns two adjacent
## items into what looks like a table of cells, and it is heavier than the job needs. Brackets
## read as a marker and leave the tile open. Measured in tile pixels, so they scale with TILE_PX.
const _BRACKET_ARM := 7
const _BRACKET_INSET := 1


## The eleven cosmetic PATTERNS, the same names the ASCII art uses
## (`client.gd::_recolor_ascii_art_pattern`). A variant is a colour, sometimes a second colour,
## and one of these; the art has shown them for a long time and the sprites did not.
const TINT_PATTERNS := ["solid", "gradient_down", "gradient_up", "middle", "striped", "edges",
	"diagonal_down", "diagonal_up", "split_v", "checker", "radial"]
## How far a tinted pixel moves toward the variant colour. Enough to read across a room, low
## enough that the art's own shading still shows - the sprite must stay a wolf, in green.
const TINT_STRENGTH := 0.55


static func _tint_mix(orig: Color, c: Color, strength: float) -> Color:
	"""Multiply toward `c`, then lift, so dark pixels keep their shape instead of going black."""
	var mult := Color(orig.r * c.r, orig.g * c.g, orig.b * c.b)
	mult = Color(minf(mult.r * 1.6, 1.0), minf(mult.g * 1.6, 1.0), minf(mult.b * 1.6, 1.0), orig.a)
	return Color(lerpf(orig.r, mult.r, strength), lerpf(orig.g, mult.g, strength),
		lerpf(orig.b, mult.b, strength), orig.a)


static func _pattern_t(pattern: String, x: int, y: int, box: Rect2i) -> float:
	"""0.0 = the first colour, 1.0 = the second, for this pixel of the sprite's content box."""
	var w := maxi(1, box.size.x)
	var h := maxi(1, box.size.y)
	var fx := float(x - box.position.x) / float(w)
	var fy := float(y - box.position.y) / float(h)
	match pattern:
		"gradient_down":
			return fy
		"gradient_up":
			return 1.0 - fy
		"middle":
			return 1.0 if fy > 0.33 and fy < 0.67 else 0.0
		"striped":
			return 1.0 if int(float(y - box.position.y) / 4.0) % 2 == 1 else 0.0
		"edges":
			return 1.0 if fx < 0.2 or fx > 0.8 or fy < 0.2 or fy > 0.8 else 0.0
		"diagonal_down":
			return clampf((fx + fy) * 0.5, 0.0, 1.0)
		"diagonal_up":
			return clampf((fx + (1.0 - fy)) * 0.5, 0.0, 1.0)
		"split_v":
			return 1.0 if fx > 0.5 else 0.0
		"checker":
			return 1.0 if (int(float(x) / 4.0) + int(float(y) / 4.0)) % 2 == 1 else 0.0
		"radial":
			return clampf(Vector2(fx - 0.5, fy - 0.5).length() * 2.0, 0.0, 1.0)
		_:
			return 0.0


static func tinted(sprite_path: String, color1: String, color2: String = "", pattern: String = "solid") -> String:
	"""A monster's COSMETIC VARIANT on its sprite: the creature tinted, the floor left alone.

	Owner 2026-09-11: *"Since all monsters have variants that change what their ASCII art looks
	like (like lime ones, or two tone red and blue, etc.) How difficult would it be to put a tint
	or effect on their monster sprites to help reflect that?"* The data was already there
	(`appearance_color`, `appearance_color2`, `appearance_pattern`) and only the ASCII art used it.

	NOT a `color=` tag - that is the mistake this file exists to avoid, three times over: these
	sprites carry the floor baked in, so a tag tints the GROUND under the monster. Here the
	baked floor is found the same way `over_prop` finds it (border-connected colour key) and left
	untouched; only the creature's pixels move toward the variant colour."""
	if sprite_path == "" or color1 == "":
		return sprite_path
	if not (pattern in TINT_PATTERNS):
		pattern = "solid"
	var key := "t|%s|%s|%s|%s" % [sprite_path, color1, color2, pattern]
	if _out_cache.has(key):
		return _out_cache[key]
	if _rejected.has(key):
		return sprite_path
	var img := _image_for(sprite_path)
	if img == null:
		_rejected[key] = true
		return sprite_path
	var c1 := Color(color1)
	var c2 := Color(color2) if color2 != "" else c1
	var w := img.get_width()
	var h := img.get_height()
	# The baked floor: the same border-connected key `over_prop` uses. Everything NOT in it is
	# the creature. An unkeyable sprite tints wholesale rather than not at all - it has no floor
	# to protect.
	var bg := {}
	for i in _background_mask(sprite_path, img):
		bg[i] = true
	var box := Rect2i(w, h, -1, -1)
	for y in range(h):
		for x in range(w):
			if bg.has(y * w + x) or img.get_pixel(x, y).a < 0.5:
				continue
			if box.size.x < 0:
				box = Rect2i(x, y, 1, 1)
			else:
				box = box.expand(Vector2i(x, y))
	if box.size.x <= 0 or box.size.y <= 0:
		_rejected[key] = true
		return sprite_path
	var out := img.duplicate() as Image
	for y in range(h):
		for x in range(w):
			if bg.has(y * w + x):
				continue
			var px := img.get_pixel(x, y)
			if px.a < 0.05:
				continue
			var t := _pattern_t(pattern, x, y, box)
			var c := c1.lerp(c2, t)
			out.set_pixel(x, y, _tint_mix(px, c, TINT_STRENGTH))
	var tex := ImageTexture.create_from_image(out)
	var dyn := _DYN_DIR + "t%d.png" % abs(hash(key))
	tex.take_over_path(dyn)
	_keepalive.append(tex)
	_out_cache[key] = dyn
	return dyn


static func cutout(sprite_path: String) -> String:
	"""The same sprite with its baked floor made TRANSPARENT, as a path.

	The dungeon's sprites carry the floor because BBCode could not composite two images into one
	cell. The OVERWORLD renderer composites the whole grid itself (`client/overworld_room.gd`),
	so a floor-backed companion would arrive standing on a square of dungeon floor in the middle
	of a snowfield - which is exactly what the first overworld render did with the player.

	Same border-connected colour key `over_prop` and `tinted` use, so a sprite is cut out the
	same way it is tinted and the two compose."""
	if sprite_path == "":
		return sprite_path
	var key := "cut|%s" % sprite_path
	if _out_cache.has(key):
		return _out_cache[key]
	if _rejected.has(key):
		return sprite_path
	var img := _image_for(sprite_path)
	if img == null:
		_rejected[key] = true
		return sprite_path
	var w := img.get_width()
	var out := img.duplicate() as Image
	var cut := 0
	for i in _background_mask(sprite_path, img):
		var px := out.get_pixel(i % w, i / w)
		out.set_pixel(i % w, i / w, Color(px.r, px.g, px.b, 0.0))
		cut += 1
	if cut == 0:
		# Nothing keyable: hand back the original rather than a needless copy.
		_rejected[key] = true
		return sprite_path
	var tex := ImageTexture.create_from_image(out)
	var dyn := _DYN_DIR + "c%d.png" % abs(hash(key))
	tex.take_over_path(dyn)
	_keepalive.append(tex)
	_out_cache[key] = dyn
	return dyn


static func bordered(path: String, color_hex: String) -> String:
	"""`path` with corner brackets in `color_hex`, marking it as something you can PICK UP.

	Owner 2026-09-10: *"we could always put a small border around floor loot to help
	differentiate it from decorations."* That inverts a real constraint. Room decor had to be
	curated down to three packs because a tileset's small objects are mostly items, and an
	item-looking decoration is misleading while real loot is also just a floor sprite. Marking the
	LOOT means the decor no longer has to avoid looking like loot.

	The colour is the item's OWN colour, straight off the floor-item payload - rarity for
	equipment, kind for everything else. That colour already existed and was only ever visible on
	the glyph fallback, so this puts information on screen that the sprite path was throwing away
	rather than inventing a new code for players to learn."""
	if path == "" or color_hex == "":
		return path
	var key := path + "#" + color_hex
	if _out_cache.has(key):
		return _out_cache[key]
	var base := _image_for(path)
	if base == null:
		return path
	var out := base.duplicate() as Image
	var c := Color(color_hex)
	var w := out.get_width()
	var h := out.get_height()
	var arm: int = maxi(2, int(round(float(_BRACKET_ARM) * float(w) / 32.0)))
	var ins: int = maxi(0, int(round(float(_BRACKET_INSET) * float(w) / 32.0)))
	for i in range(arm):
		# four corners, an L at each
		out.set_pixel(ins + i, ins, c)
		out.set_pixel(ins, ins + i, c)
		out.set_pixel(w - 1 - ins - i, ins, c)
		out.set_pixel(w - 1 - ins, ins + i, c)
		out.set_pixel(ins + i, h - 1 - ins, c)
		out.set_pixel(ins, h - 1 - ins - i, c)
		out.set_pixel(w - 1 - ins - i, h - 1 - ins, c)
		out.set_pixel(w - 1 - ins, h - 1 - ins - i, c)
	var tex := ImageTexture.create_from_image(out)
	var dyn := _DYN_DIR + "b%d.png" % abs(hash(key))
	tex.take_over_path(dyn)
	_keepalive.append(tex)
	_out_cache[key] = dyn
	return dyn


static func ringed(path: String, color_hex: String) -> String:
	"""`path` with a full RECTANGLE outline in `color_hex`, marking it as a BOSS.

	Deliberately a closed ring and not the corner brackets `bordered` draws. Players have already
	learned brackets = something you can pick up; reusing them here would teach that a boss is
	loot. A solid frame is the opposite reading and cannot be confused with four corners.

	Owner 2026-09-10: *"I couldn't locate a boss and when I grabbed the chest it gave me the
	dungeon loot and teleported me out of the dungeon."* They had already killed it. The boss
	spawns as a wandering entity carrying display_char "B" and a red colour, and the renderer set
	both - but only the GLYPH fallback ever read them. Once every dungeon monster had a sprite,
	the boss was drawn as an ordinary Goblin and its marker became dead code.

	The colour is the server's own: #FF0000 for a boss, #FFD700 for a fabled one, so the rarer
	thing stays visibly rarer."""
	if path == "" or color_hex == "":
		return path
	var key := path + "@ring@" + color_hex
	if _out_cache.has(key):
		return _out_cache[key]
	var base := _image_for(path)
	if base == null:
		return path
	var out := base.duplicate() as Image
	var c := Color(color_hex)
	var w := out.get_width()
	var h := out.get_height()
	for x in range(w):
		out.set_pixel(x, 0, c)
		out.set_pixel(x, h - 1, c)
	for y in range(h):
		out.set_pixel(0, y, c)
		out.set_pixel(w - 1, y, c)
	var tex := ImageTexture.create_from_image(out)
	var dyn := _DYN_DIR + "r%d.png" % abs(hash(key))
	tex.take_over_path(dyn)
	_keepalive.append(tex)
	_out_cache[key] = dyn
	return dyn


static func _image_for(path: String) -> Image:
	if _img_cache.has(path):
		return _img_cache[path]
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex != null:
			img = tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RGBA8)
	_img_cache[path] = img
	return img


static func _background_mask(path: String, img: Image) -> PackedInt32Array:
	"""Indices of the pixels that are FLOOR, reached from the tile's edge.

	Border-connected is the whole point — see the class comment. Cached per sprite path because
	it walks every pixel and the answer never changes for a file."""
	if _mask_cache.has(path):
		return _mask_cache[path]
	var w := img.get_width()
	var h := img.get_height()
	var floor_col := Color(DungeonTiles.FLOOR_COLOR)
	var is_floor := PackedByteArray()
	is_floor.resize(w * h)
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			# Byte-exact. The bake copied the floor tile verbatim, so an approximate match would
			# only ever add false positives inside the art.
			is_floor[y * w + x] = 1 if (c.a >= 1.0 and is_equal_approx(c.r, floor_col.r) \
				and is_equal_approx(c.g, floor_col.g) and is_equal_approx(c.b, floor_col.b)) else 0

	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[int] = []
	for x in range(w):
		for y in [0, h - 1]:
			var i: int = y * w + x
			if is_floor[i] == 1 and seen[i] == 0:
				seen[i] = 1
				stack.append(i)
	for y in range(h):
		for x in [0, w - 1]:
			var i: int = y * w + x
			if is_floor[i] == 1 and seen[i] == 0:
				seen[i] = 1
				stack.append(i)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var cx: int = i % w
		var cy: int = i / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				continue
			var ni: int = ny * w + nx
			if is_floor[ni] == 1 and seen[ni] == 0:
				seen[ni] = 1
				stack.append(ni)

	var out := PackedInt32Array()
	for i in range(w * h):
		if seen[i] == 1:
			out.append(i)
	_mask_cache[path] = out
	return out

static var _mask_cache: Dictionary = {}
