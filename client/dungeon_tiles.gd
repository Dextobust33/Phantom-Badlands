extends RefCounted
class_name DungeonTiles

## Sprite tiles for the dungeon floor.
##
## The dungeon map is a MONOSPACE TEXT canvas, not a TileMap. That sounds like the wrong place to
## draw a tile grid, but it was measured before it was chosen: a full 25x11 floor of inline
## `[img]` costs 16.67ms per redraw against 15.70ms for text glyphs - 1.1x - so the existing
## renderer stays and every tile is simply an inline image.
##
## Two numbers make a SQUARE grid possible inside a text line, and both were measured rather than
## derived (see `Client.DUNGEON_TILE_FONT_SIZE` and `DUNGEON_ROW_SEPARATION`):
##
##   * Consolas at font size 58 has a cell exactly 32px wide. That is a perfect 2x integer scale
##     of a 16px tile and 1:1 for the 32px wall sheet. Non-integer scaling is what makes pixel art
##     look smeared, so this number is the whole point of choosing 58 over 46.
##   * `line_separation = -47` puts rows exactly 32px apart. Measured: -45 gives 34px, -47 gives
##     32px, -50 gives 29px.
##
## The hard constraint everywhere below: an inline image MUST be exactly one cell wide, or every
## tile after it on that row shifts and the whole floor shears.

const TILE_PX := 32                      # one dungeon cell, square

const SHEET_CAVE16 := "res://client/sprites/darkcave/dark cave_tiles_and_sprite_16x16.png"
const SHEET_CAVE32 := "res://client/sprites/darkcave/dark cave_wall_32x32.png"
const SHEET_FREE   := "res://client/sprites/tilemap_pack/free_tiles_16x16.png"

## Cells on the 16px cave sheet. FOUND BY MEASUREMENT, not by eye: scanning for a fully-opaque
## cell with zero colour spread. A first attempt picked (6,2) by eye and produced a room covered
## in black notches, because that is an EDGE tile of the autotile rather than its solid centre.
const CAVE_FLOOR := Vector2i(2, 2)       # solid olive floor, #524B24, zero spread
const CAVE_VOID := Vector2i(2, 8)        # solid black

## The most solid cell on the 32px wall sheet (458 rock pixels of a possible ~1024). The sheet is
## graded rock DENSITY rather than a clean 16-case directional autotile - measuring each cell's
## per-edge rock coverage produced no clean N/S/E/W signatures - so slice 1 uses one solid rim
## tile and directionality is deferred until it can be judged on screen.
const CAVE_ROCK := Vector2i(4, 4)

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
