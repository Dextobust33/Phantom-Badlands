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
const PROP_DIR := "res://client/sprites/prop_floor32/"
const PROP_COUNT := 7
## Roughly one floor tile in seven. Flavour, not clutter: high enough that a corridor is not all
## one tile, low enough that the eye still reads the floor as floor.
const PROP_CHANCE_IN := 7


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
