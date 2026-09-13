extends SceneTree
## Multi-cell art must actually be drawn across multiple cells.
##
## Owner 2026-09-13: *"The samples you provided all look like multi tile artwork you've attempted
## to break down into one. We should instead use the multitile art so they appear as complete on
## the map with only a single base tile serving as the interactable tile."*
##
## ⚑ MEASURED IN PIXELS, because the last renderer fault that shipped twice was a block of code
## that read correctly and never executed, and the only thing that caught it was counting pixels.
## A tile that "supports" big art but silently falls back to the 32px version looks identical in
## source and identical in a screenshot taken from the wrong distance.
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _grid_with(meaning: String, rows: int, cols: int, at: Vector2i) -> Array:
	var m: Array = []
	var b: Array = []
	for y in range(rows):
		var mr := PackedStringArray()
		var br := PackedStringArray()
		for x in range(cols):
			mr.append(meaning if (x == at.x and y == at.y) else "empty")
			br.append("plains")
		m.append(mr)
		b.append(br)
	return [m, b]


func _ink_bbox(img: Image, ref: Image) -> Rect2i:
	"""The box of pixels that differ from a reference render - i.e. what the tile actually drew."""
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-1, -1)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var a := img.get_pixel(x, y)
			var b := ref.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.02:
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	if hi.x < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(lo, hi - lo + Vector2i(1, 1))


func _render(meaning: String, rows: int, cols: int, at: Vector2i) -> Image:
	var g: Array = _grid_with(meaning, rows, cols, at)
	Room._key = ""      # the composer caches on the grid contents; force a rebuild
	Room.build(g[0], g[1], {})
	return Room._grid.duplicate()


func _init() -> void:
	if not Room.available():
		print("[BIGTILE] SKIP - overworld art is not present in this checkout")
		quit(0)
		return
	var rows := 9
	var cols := 9
	var at := Vector2i(4, 6)     # not on an edge, and with room above to overflow into

	var bare := _render("empty", rows, cols, at)

	print("===== THE MANIFEST IS READ AT ALL =====")
	Room._load_big_spans()
	ck(not Room._big_spans.is_empty(),
		"%d tiles are registered as multi-cell" % Room._big_spans.size())
	ck(Room._big_spans.has("tree"), "including tree")
	ck(Room._big_spans.has("door"), "and door, which was a FRAGMENT of a 3x2 door")

	print("\n===== AND THE ART IS DRAWN BIGGER THAN ITS CELL =====")
	for name in ["tree", "door", "companion_stable", "well"]:
		if not Room._big_spans.has(name):
			ck(false, "%s is not in the manifest" % name)
			continue
		var span: Array = Room._big_spans[name]
		var want_w: int = int(span[1]) * Room.CELL
		var want_h: int = int(span[0]) * Room.CELL
		var img := _render(name, rows, cols, at)
		var box := _ink_bbox(img, bare)
		print("  %-18s span %dx%d cells -> drew %dx%d px (one cell is %d)" % [
			name, int(span[1]), int(span[0]), box.size.x, box.size.y, Room.CELL])
		# Art has transparent margins, so it will not fill its span exactly - but it must be
		# clearly wider or taller than ONE cell, which is the whole claim.
		var bigger: bool = box.size.x > Room.CELL or box.size.y > Room.CELL
		ck(bigger, "%s draws beyond a single %dpx cell" % [name, Room.CELL])
		ck(box.size.x <= want_w + 2 and box.size.y <= want_h + 2,
			"...and stays within its declared %dx%d px footprint" % [want_w, want_h])

	print("\n===== IT GROWS UPWARD FROM THE CELL YOU WALK INTO =====")
	# The base cell is what the server knows about. The art must sit ON it and overflow upward,
	# not straddle it - otherwise the thing you see and the thing you interact with are apart.
	var img2 := _render("tree", rows, cols, at)
	var box2 := _ink_bbox(img2, bare)
	var base_bottom: int = (at.y + 1) * Room.CELL
	ck(absi((box2.position.y + box2.size.y) - base_bottom) <= 3,
		"the art's bottom sits on the base cell's bottom edge (%d vs %d)" % [
			box2.position.y + box2.size.y, base_bottom])
	ck(box2.position.y < at.y * Room.CELL,
		"and it reaches into the cells ABOVE, which is what makes it look whole")

	print("\n===== ART AT THE EDGE OF THE VIEW IS NOT LOST =====")
	# `blend_rect` with a destination outside the image draws NOTHING - so without clipping, the
	# tiles nearest the edge would silently vanish while the middle looked perfect.
	var edge := _render("tree", rows, cols, Vector2i(0, 0))
	var ebox := _ink_bbox(edge, _render("empty", rows, cols, Vector2i(0, 0)))
	ck(ebox.size.x > 0 and ebox.size.y > 0,
		"a tree in the top-left corner still draws (%dx%d px)" % [ebox.size.x, ebox.size.y])

	print("\n[BIGTILE] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
