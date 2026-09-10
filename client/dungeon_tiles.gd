extends RefCounted
class_name DungeonTiles

## Sprite tiles for the dungeon floor.
##
## The dungeon map is a MONOSPACE TEXT canvas, not a TileMap. That sounds like the wrong place to
## draw a tile grid, but it was measured before it was chosen: a full 25x11 floor of inline
## `[img]` costs 16.67ms per redraw against 15.70ms for text glyphs - 1.1x - so the existing
## renderer stays and every tile is simply an inline image.
##
## Making a SQUARE grid work inside a text line took one wrong turn worth recording. The first
## attempt used font 58 - whose Consolas cell is exactly 32px wide - with `line_separation = -47`
## to pull the 59px line down to 32. Every headless measurement agreed it gave 32px rows, and it
## was still wrong: a negative separation does not merely tighten rows, it COMPRESSES the inline
## images, so tiles drew at full width and half height. `get_content_height()` reports the row
## pitch, not whether the image inside was squashed, so the instrument confirmed a broken layout
## four times. A 32px lattice drawn over a screenshot found it in one look.
##
## What actually works: font 14, no separation override. A Consolas character is exactly 8px
## there, so a text cell padded to TILE_PX/8 characters is the same width as an image cell, and a
## 32px image sets a natural 32px row on its own.
##
## The hard constraint everywhere below: an inline image MUST be exactly one cell wide, or every
## tile after it on that row shifts and the whole floor shears.

## The dungeon cell, in pixels. Sized at RUNTIME to fill the canvas (see
## `Client._dungeon_pick_tile_px`), not fixed, because the canvas differs by window and by
## resolution and a constant would leave most of it empty on a large screen - which is exactly
## what the owner reported: "the Dungeon looks like it's only taking up a small portion of the
## game output window".
##
## Always a MULTIPLE OF 16 so a 16px source tile lands on a whole-number scale; pixel art at a
## fractional scale is smeared. And always a multiple of 8 so a font-14 Consolas character
## (exactly 8px) divides it evenly - that is what lets a text cell be padded to the same width as
## an image cell.
static var TILE_PX: int = 32

const SHEET_CAVE16 := "res://client/sprites/darkcave/dark cave_tiles_and_sprite_16x16.png"
const SHEET_CAVE32 := "res://client/sprites/darkcave/dark cave_wall_32x32.png"
const SHEET_FREE   := "res://client/sprites/tilemap_pack/free_tiles_16x16.png"

## Cells on the 16px cave sheet. FOUND BY MEASUREMENT, not by eye: scanning for a fully-opaque
## cell with zero colour spread. A first attempt picked (6,2) by eye and produced a room covered
## in black notches, because that is an EDGE tile of the autotile rather than its solid centre.
const CAVE_FLOOR := Vector2i(2, 2)       # solid olive floor, #524B24, zero spread
## The floor's exact colour. It has ZERO colour spread - every pixel of that tile is this - so a
## flat `bgcolor` behind a text glyph matches the floor exactly rather than approximately, and a
## glyph cell stops reading as a hole punched in the ground.
const FLOOR_COLOR := "#524B24"
const CAVE_VOID := Vector2i(2, 8)        # solid black

## The most solid cell on the 32px wall sheet (458 rock pixels of a possible ~1024). The sheet is
## graded rock DENSITY rather than a clean 16-case directional autotile - measuring each cell's
## per-edge rock coverage produced no clean N/S/E/W signatures - so slice 1 uses one solid rim
## tile and directionality is deferred until it can be judged on screen.
const CAVE_ROCK := Vector2i(4, 4)

## Scatter decoration, pre-composited onto the floor. Owner, on seeing the plain floor: "We will
## likely want to add some of the stones, grass, trees, stumps, lanterns scattered around in the
## future just for flavor to make the floor less of the same thing."
##
## Only genuine SCATTER is in here. The sheet's lanterns, campfire and tent are landmark objects
## - two of those "candidates" turned out to be the lower halves of a lantern and a piece of the
## tent, which read as debris when dropped on their own - so they are left for deliberate
## placement rather than random scatter.
##
## The SKULL was dropped after seeing it in play: at tile scale it reads as a white oval that
## looks like an egg or a pickup, and three in one view competed with the actual floor loot.
## Background scatter has to stay in the background.
## The ROOM floor. Owner 2026-09-10: *"keep our dungeon corridoors using what we currently do
## but make all of the actual rooms out of sprites from those packs."*
##
## Corridors stay on the darkcave floor; a ROOM gets this instead, so walking out of a passage
## into a chamber is a visible change of material rather than more of the same ground.
##
## The pack was chosen by MEASUREMENT, twice over, because picking a sheet cell by eye has already
## put an autotile EDGE on this floor once and covered a room in black notches. First every Raven
## pack's palette was compared to the darkcave corridor sheet in HSV -- an RGB average hides two
## greys with different casts, which is exactly the failure that matters here. `shroom_chasm` came
## back nearest by a wide margin (hue gap 0.006, value 0.009, against `green_dungeon`'s 0.176 and
## 0.210 -- the pack whose NAME suggests it is the obvious choice is one of the worst matches).
## Then the sheet was scanned for a fully-opaque, low-spread, mid-brightness cell the way
## CAVE_FLOOR was found, and the candidates rendered BESIDE the corridor floor before choosing.
##
## Cell (4,2) of `shroom_chasm/All Tileset/Tileset.png`: textured stone, three colours, close to
## the corridor in brightness and clearly a different material. Baked to 32px like every other
## dungeon cell asset, so a 64px cell is a clean 2x.
##
## LICENCE: derived from a pack that forbids redistribution -- untracked, see
## `docs/ASSET_LICENCES.md`. It is in `tools/licensed_assets.manifest`, so the release gate fails
## without it rather than shipping a dungeon with holes in the rooms.
## The ROOM FLOOR pool: one look per PACK, and a room picks one.
##
## Owner 2026-09-10: *"I'm less concerned with if the room looks like it fits in with the dungeon
## and much more concerned that they look unique and fun. The more the better since it will lead
## to more variety and exploration, seeing things no other players have before."*
##
## So a chamber's floor is chosen by its ROOM ID, not by its position: every cell of one room
## agrees, and the next room over is something else entirely. Baked by
## `tools/bake_room_floors.py`, which records how the cells were chosen -- a measured shortlist,
## gated on CONTRAST WITH THE WALL RIM so a room is always readable, then rendered and looked at.
## That last step is what caught what no measurement could: two of the top-scoring "floors" were
## water and one was a boulder.
##
## LICENCE: derived from packs that forbid redistribution -- untracked, and in
## `tools/licensed_assets.manifest` so the release gate fails without them.
const ROOM_FLOOR_DIR := "res://client/sprites/room_floor32/"

## The packs in the pool. Order is not meaningful; a room hashes into it.
const ROOM_PACKS := [
	"cozy_home", "farmlands_v3", "green_dungeon", "red_desert_ruin",
	"shroom_chasm", "the_underworld", "winter_forest",
]

## pack -> how many variant tiles it baked. Counted from the FILES rather than written down a
## second time: the bake script already decides this, and a hand-kept copy here is the "one value,
## two places" shape that causes most of the wrong-text bugs in this repo.
static var _room_variant_count: Dictionary = {}


static func room_variants(pack: String) -> int:
	if _room_variant_count.has(pack):
		return _room_variant_count[pack]
	var n := 0
	while ResourceLoader.exists(ROOM_FLOOR_DIR + "%s_%02d.png" % [pack, n]):
		n += 1
	_room_variant_count[pack] = maxi(1, n)
	return _room_variant_count[pack]


## Per-pack room DECOR. Not every pack has any: a tileset's small objects are mostly ITEMS, and
## decor that reads as loot or as a creature is worse than none (an auto-pick returned chickens).
## A room whose pack has no decor keeps the neutral darkcave scatter props.
const DECOR_DIR := "res://client/sprites/decor32/"
static var _decor_count: Dictionary = {}


static func decor_variants(pack: String) -> int:
	if _decor_count.has(pack):
		return _decor_count[pack]
	var n := 0
	while ResourceLoader.exists(DECOR_DIR + "%s_%02d.png" % [pack, n]):
		n += 1
	_decor_count[pack] = n
	return n


static func decor_for(x: int, y: int, room_id: int) -> String:
	"""This room's own decoration for this cell, or "" if its pack ships none.

	WHERE a decoration goes is still decided by `prop_for`'s position hash - the density and the
	placement are already tuned and there is no reason to have two answers to the same question.
	This decides only WHAT is drawn there."""
	if ROOM_PACKS.is_empty():
		return ""
	var pack: String = ROOM_PACKS[abs(room_id) % ROOM_PACKS.size()]
	var n: int = decor_variants(pack)
	if n <= 0:
		return ""
	var h: int = abs(hash(Vector2i(x + 7919, y)))
	return DECOR_DIR + "%s_%02d.png" % [pack, h % n]


static func room_floor_for(x: int, y: int, room_id: int) -> String:
	"""The floor tile for a room cell: the ROOM picks the pack, the CELL picks the variant.

	Two hashes doing two different jobs. `room_id` selects the pack, so a chamber is one material
	throughout -- hashing the pack per cell would speckle eight looks through one room, which is the
	failure this whole approach exists to avoid. The cell then picks a variant WITHIN that pack,
	which is what stops a textured tile gridding into wallpaper across a large chamber; it did
	exactly that on the first single-tile attempt.

	Position-hashed rather than random, like `prop_for`, because the grid is rebuilt on every step
	and a random pick would make the floor shimmer as the player walks."""
	if ROOM_PACKS.is_empty():
		return ""
	var pack: String = ROOM_PACKS[abs(room_id) % ROOM_PACKS.size()]
	var n: int = room_variants(pack)
	var v: int = (abs(hash(Vector2i(y, x))) % n) if n > 1 else 0
	return ROOM_FLOOR_DIR + "%s_%02d.png" % [pack, v]


const PROP_DIR := "res://client/sprites/prop_floor32/"
## 7 -> 14 on 2026-09-10. Owner, after a live look: *"I also haven't seen much variety in the
## decorations like the lamps and things from the sprite packs."* Correct, and worse than it
## sounds: FOUR of the original seven were near-identical grass sprigs, so a corridor was really
## showing three distinct things. Added boulders, a small rock, a dead shrub, a moss patch and two
## lanterns - all picked by rendering the cave sheet with its cells LABELLED and looking at it,
## because a previous pick-by-eye put an edge tile on the floor and covered the room in black
## notches.
##
## THE LANTERNS DID NOT SURVIVE, and the reason is structural. Owner, seeing them in play: *"the
## two lanterns you added in those are actually two vertical squares tall, I think one of the
## shrubs are too, currently they render as half of a lamppost."* Correct - the lamp occupies
## (19,5)+(19,6) and the shrub (17,3)+(17,4), so baking one cell yields half a sprite. A 2-cell
## prop cannot fit this grid at all: every cell is one square image drawn at the tile width, so a
## 16x32 source either squashes or drops to half the scale of everything around it. Tall props
## need a second draw LAYER - which is the same thing prop occlusion needs, so the two are one
## problem, not two.
## The LAYER now exists (`dungeon_composite.gd`, 2026-09-10) and prop OCCLUSION is fixed with
## it - anything standing on a prop now draws over it instead of erasing it. What a tall prop
## still needs on top of that is the ROW SPLIT: one prop claiming two cells.
## Still deliberately excluded, each for a reason: the SKULL (dropped in d42bf00f for reading as
## loot), the CAMPFIRE (reads as a rest site, which is a real feature), the grave MARKER (reads as
## remains) and the 3x3 TENT (reads as a safe room). Background scatter must stay background.
const PROP_COUNT := 11
## Roughly one floor tile in seven. Flavour, not clutter: high enough that a corridor is not all
## one tile, low enough that the eye still reads the floor as floor.
const PROP_CHANCE_IN := 7


## Only a WALL breaks a room.
##
## This first also excluded the two staircases, which was wrong and showed up immediately: a
## staircase inside a chamber is an OBJECT STANDING ON the room's floor, not a hole in it. Owner,
## on the first walkthrough: *"The stairs still seem to suffer from occlusion... I also found
## another one near the stairs that seems to be brown for no apparent reason."* That brown square
## was the room's floor reverting to corridor under a landmark tile.
const _NOT_ROOM_FLOOR := [1]


static func is_room_cell(grid: Array, x: int, y: int) -> bool:
	"""Is this cell ROOM floor rather than corridor?

	Owner wants corridors to keep the darkcave look and ROOMS to be drawn from another pack, so
	the renderer has to tell them apart. The generator knows while it is carving and then throws
	it away — `_carve_room` and `_connect_rooms` both write `TileType.EMPTY`, so what reaches the
	client is one number for both. Adding a `TileType.ROOM` would mean touching every walkable
	check in the client AND the server, which is the shape of change that leaves one site behind.
	Deriving it here needs no protocol change and no new tile type.

	**The test: does this cell belong to any fully-walkable 3x3 block?**

	It was 2x2 first, and that was wrong in a way only a real floor showed. A 1-wide corridor can
	never form a 2x2, which is what the fixtures tested -- but TWO corridors running ADJACENT do,
	and the flood fill then spread along the whole connected run. Measured across six generated
	floors that produced "rooms" of 8x26 at 45% fill: a branching set of passages painted as one
	chamber. Owner, seeing one in play: *"Not sure if this room is legit."*

	3x3 is not an arbitrary tightening - it is the GENERATOR'S OWN MINIMUM. `_carve_room` sizes
	every room `rng.randi_range(3, ...)` in both axes, so every real room contains a 3x3 block and
	no pair of adjacent corridors does. The rule now matches the thing it is trying to detect.

	Still deliberately not "walkable on both axes", which calls a corridor T-JUNCTION a room.

	Pure and static so it can be probed; the caller owns any caching."""
	for dy in [-2, -1, 0]:
		for dx in [-2, -1, 0]:
			var ok := true
			for oy in range(3):
				for ox in range(3):
					var nx: int = x + dx + ox
					var ny: int = y + dy + oy
					if ny < 0 or ny >= grid.size():
						ok = false
						break
					var row = grid[ny]
					if nx < 0 or nx >= row.size():
						ok = false
						break
					if int(row[nx]) in _NOT_ROOM_FLOOR:
						ok = false
						break
				if not ok:
					break
			if ok:
				return true
	return false


static func label_rooms(grid: Array) -> Dictionary:
	"""Give every ROOM its own id: {"x,y": room_id} for each room cell. Corridors are absent.

	Owner 2026-09-10, on what rooms should look like: *"I'm less concerned with if the room looks
	like it fits in with the dungeon and much more concerned that they look unique and fun. The
	more the better since it will lead to more variety and exploration, seeing things no other
	players have before."*

	Which means each CHAMBER picks a look — and `is_room_cell` cannot support that, because it
	answers "is this room floor", not "which room". Hashing per cell is right for breaking up a
	floor texture and exactly wrong here: it would speckle four looks through one chamber instead
	of giving the chamber one. So rooms need an identity, and an identity is a connected component.

	Flood fill over room cells, 4-connected. Two chambers joined by a 1-wide corridor get
	different ids because the corridor cells are not room cells and so do not conduct — which is
	the behaviour wanted: the corridor is the JOIN, and a doorway is where the look changes.

	Ids are assigned in scan order, so they are stable for a given grid: the same floor always
	labels the same way, and a room keeps its look for the life of the floor rather than
	shimmering as the player walks. Computed once per floor by the caller and cached; this walks
	the whole grid and is not something to run per frame."""
	var out := {}
	var next_id := 0
	for y in range(grid.size()):
		var row = grid[y]
		for x in range(row.size()):
			var key := "%d,%d" % [x, y]
			if out.has(key):
				continue
			if not is_room_cell(grid, x, y):
				continue
			# a new chamber: flood it
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				var ck := "%d,%d" % [c.x, c.y]
				if out.has(ck):
					continue
				if c.y < 0 or c.y >= grid.size():
					continue
				var r = grid[c.y]
				if c.x < 0 or c.x >= r.size():
					continue
				if not is_room_cell(grid, c.x, c.y):
					continue
				out[ck] = next_id
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					stack.append(c + d)
			next_id += 1
	return out


static func room_count(labels: Dictionary) -> int:
	"""How many distinct chambers `label_rooms` found."""
	var seen := {}
	for k in labels:
		seen[labels[k]] = true
	return seen.size()


## TWO-CELL props. The lamps and the dead shrub were dropped from the scatter pool because a
## 2-cell object baked into one cell is half an object - owner: *"currently they render as half of
## a lamppost"*. They come back here as top and bottom HALVES drawn into two grid cells.
##
## Rarer than scatter by a wide margin: a lamppost is a landmark and a floor covered in them is a
## street. One in ~55 eligible cells against one in 7 for pebbles.
const TALL_DIR := "res://client/sprites/tall32/"
const TALL_NAMES := ["lantern", "lantern2", "shrub"]
const TALL_CHANCE_IN := 55


static func tall_prop_for(grid: Array, x: int, y: int) -> String:
	"""The two-cell prop whose BASE stands on this cell, or "".

	Position-hashed like `prop_for`, on a different salt so the two do not correlate.

	The placement rule is the whole point: a base is only allowed where the cell ABOVE is also
	walkable floor. Without that the top half would be drawn into a wall or into the void, which
	is precisely the half-object problem this exists to fix, just moved up one cell."""
	if y <= 0 or y >= grid.size():
		return ""
	var row = grid[y]
	if x < 0 or x >= row.size():
		return ""
	if int(row[x]) == 1:
		return ""
	var above = grid[y - 1]
	if x >= above.size() or int(above[x]) == 1:
		return ""      # nowhere for the top half to go
	var h: int = abs(hash(Vector2i(x * 31 + 5, y * 17)))
	if h % TALL_CHANCE_IN != 0:
		return ""
	return TALL_NAMES[(h / TALL_CHANCE_IN) % TALL_NAMES.size()]


static func tall_half(name: String, half: String) -> String:
	var p := TALL_DIR + "%s_%s.png" % [name, half]
	return p if ResourceLoader.exists(p) else ""


static func prop_for(x: int, y: int) -> String:
	"""The scatter prop for a floor tile, or "" for plain floor.

	Keyed on the tile's POSITION, not on a random draw: the grid is rebuilt on every step, so a
	random pick would make the decoration shimmer and crawl as the player walks. Hashing the
	coordinates means a given tile keeps the same pebble forever."""
	var h: int = abs(hash(Vector2i(x, y)))
	if h % PROP_CHANCE_IN != 0:
		return ""
	return PROP_DIR + "prop_%02d.png" % ((h / PROP_CHANCE_IN) % PROP_COUNT)

## `free_tiles_16x16.png` is indexed by the enum in `tilemap_pack/FreeTileMap.cs.reference`, which
## NAMES every tile - so none of these were identified by eye. Verified by rendering each index
## and looking at it. Index -> cell is (i % 32, i / 32).
const FREE_ACROSS := 32
const FREE_STAIRS_DOWN := 12
const FREE_STAIRS_UP := 13
const FREE_DOOR_SHUT := 14
const FREE_DOOR_OPEN := 15
const FREE_DOOR_BROKE := 16
const FREE_WALL_TORCH := [17, 18, 19, 20]    # a 4-frame animation


static func cell_img(sheet: String, cell: Vector2i, src_px: int) -> String:
	"""One sheet cell as an inline image exactly one dungeon cell wide.

	`src_px` is the tile size ON THE SHEET (16 or 32); the output is always TILE_PX, so a 16px
	tile is drawn at a clean 2x and a 32px tile at 1:1."""
	return "[img=%dx%d region=%d,%d,%d,%d]%s[/img]" % [
		TILE_PX, TILE_PX,
		cell.x * src_px, cell.y * src_px, src_px, src_px,
		sheet]


const FREE_FLOOR_DIR := "res://client/sprites/free_floor32/"


static func free_backed_path(name: String) -> String:
	"""The PATH of a floor-backed free-tileset tile, or "" if there is none.

	Split out from `free_backed_img` because that one returns finished BBCODE, and anything that
	wants to COMPOSITE the tile onto a different ground needs the file, not a tag. Passing the
	BBCode to the compositor silently produced an `[img]` nested inside an `[img]` - the tile
	would simply not have drawn."""
	var p := FREE_FLOOR_DIR + name + ".png"
	return p if ResourceLoader.exists(p) else ""


static func free_backed_img(name: String) -> String:
	"""A free-tileset tile with the cave floor baked UNDER it. The Pixel Level tiles have their
	own transparent surround, so drawn raw they sat in a dark square while every other cell had
	ground beneath it."""
	var p := FREE_FLOOR_DIR + name + ".png"
	if not ResourceLoader.exists(p):
		return ""
	return "[img=%dx%d]%s[/img]" % [TILE_PX, TILE_PX, p]


static func free_img(index: int) -> String:
	"""A tile from the Pixel Level sheet, addressed by its ENUM INDEX rather than a coordinate,
	so the call site reads as the name the artist gave it."""
	return cell_img(SHEET_FREE, Vector2i(index % FREE_ACROSS, index / FREE_ACROSS), 16)


static func floor_img() -> String:
	return cell_img(SHEET_CAVE16, CAVE_FLOOR, 16)


static func rock_img() -> String:
	return cell_img(SHEET_CAVE32, CAVE_ROCK, 32)


static func blank_img() -> String:
	"""Deep void. Drawn as a TILE rather than a space so the row height is set by an image on
	every cell; a bare space would be sized by the font instead and the row would jump."""
	return cell_img(SHEET_CAVE16, CAVE_VOID, 16)
