extends SceneTree
## Does the loot border actually mark the loot, and does it survive compositing?
##
## The point of the border is that a player can tell a pickup from a decoration at a glance. That
## fails silently in two ways this checks for: brackets drawn in the wrong place (invisible), and
## brackets lost when the sprite is composited onto a room floor, which is the order the renderer
## actually uses.
const _C = preload("res://client/dungeon_composite.gd")
const _T = preload("res://client/dungeon_tiles.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok: fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func count_colour(img: Image, c: Color) -> int:
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).is_equal_approx(c):
				n += 1
	return n


func img_of(path: String) -> Image:
	var im: Image = (ResourceLoader.load(path) as Texture2D).get_image()
	im.convert(Image.FORMAT_RGBA8)
	return im


func _init() -> void:
	var loot := "res://client/sprites/loot_floor32/equipment.png"
	var purple := "#A335EE"

	print("--- 1. the brackets are actually drawn ---")
	var b := _C.bordered(loot, purple)
	ck(b != loot, "bordered() returns a new image")
	var bi := img_of(b)
	var n := count_colour(bi, Color(purple))
	print("      %d pixels of the rarity colour" % n)
	# four corners x two arms x 7px, minus the shared corner pixel
	ck(n >= 40 and n <= 70, "bracket pixel count is in the expected range (got %d)" % n)

	print("--- 2. they are in the CORNERS, not scattered ---")
	var w := bi.get_width()
	var mid := 0
	for y in range(10, w - 10):
		for x in range(10, w - 10):
			if bi.get_pixel(x, y).is_equal_approx(Color(purple)):
				mid += 1
	ck(mid == 0, "no bracket pixels in the middle of the tile (%d)" % mid)

	print("--- 3. the colour follows the ITEM, not a constant ---")
	var green := _C.bordered(loot, "#1EFF00")
	ck(green != b, "a different rarity colour gives a different image")
	ck(count_colour(img_of(green), Color("#1EFF00")) > 40, "and it is drawn in that colour")

	print("--- 4. brackets SURVIVE compositing onto a room floor ---")
	# the renderer composites first, then borders. Prove the order works end to end.
	var floor_tile: String = _T.room_floor_for(3, 4, 0)
	var composited: String = _C.over_prop(loot, floor_tile)
	var final := _C.bordered(composited, purple)
	var fi := img_of(final)
	ck(count_colour(fi, Color(purple)) >= 40,
		"the brackets are still there after the sprite is put on a room floor")
	ck(final != composited, "and the bordered image differs from the un-bordered one")

	print("--- 5. cached, because this runs per visible loot cell per redraw ---")
	ck(_C.bordered(loot, purple) == b, "same inputs return the same cached path")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
