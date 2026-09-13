extends SceneTree
## A spent gathering node has to LOOK spent - including the big ones.
##
## Owner 2026-09-13: *"the big tree gatherables don't change visually once gathered."*
##
## The dimming that marks a node as taken shades the CELL, in pass one of the composer. Art
## bigger than a cell is drawn in pass TWO, straight over the top, at full brightness - so the
## change that made trees and stables draw whole also undid the one piece of feedback that says
## "you already took this". A regression created by a fix, which is why it is measured in pixels
## here rather than read.
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _grid(meaning: String) -> Array:
	var m: Array = []
	for y in range(5):
		var r := PackedStringArray()
		for x in range(5):
			r.append(meaning if (x == 2 and y == 3) else "empty")
		m.append(r)
	return m


func _biomes() -> Array:
	var b: Array = []
	for y in range(5):
		b.append(PackedStringArray(["plains", "plains", "plains", "plains", "plains"]))
	return b


func _render(meaning: String) -> Image:
	Room._key = ""
	Room.build(_grid(meaning), _biomes(), {})
	return Room._grid.duplicate()


func _mean_brightness(img: Image, x0: int, y0: int, w: int, h: int) -> float:
	var t := 0.0
	var n := 0
	for y in range(y0, mini(y0 + h, img.get_height())):
		for x in range(x0, mini(x0 + w, img.get_width())):
			var c := img.get_pixel(x, y)
			t += (c.r + c.g + c.b) / 3.0
			n += 1
	return t / maxf(1.0, float(n))


func _init() -> void:
	if not Room.available():
		print("[DEPLETEDBIG] SKIP - art not present")
		quit(0)
		return

	print("===== A BIG TILE, FRESH AND SPENT =====")
	Room._load_big_spans()
	ck(Room._big_spans.has("tree"), "tree is multi-cell art (the case reported)")

	var fresh := _render("tree")
	var spent := _render("!depleted:tree")
	# The tree is 3x3 anchored on the base cell, so it occupies the block above and around it.
	var span: Array = Room._big_spans["tree"]
	var w: int = int(span[1]) * Room.CELL
	var h: int = int(span[0]) * Room.CELL
	var bx: int = 2 * Room.CELL + (Room.CELL - w) / 2
	var by: int = 4 * Room.CELL - h
	var fb := _mean_brightness(fresh, maxi(0, bx), maxi(0, by), w, h)
	var sb := _mean_brightness(spent, maxi(0, bx), maxi(0, by), w, h)
	print("  mean brightness over the tree: fresh %.3f, spent %.3f (%.0f%% dimmer)" % [
		fb, sb, 100.0 * (1.0 - sb / maxf(0.0001, fb))])
	ck(sb < fb * 0.92, "a gathered tree is visibly dimmer than a fresh one")

	print("\n===== AND THE SMALL ONES STILL ARE =====")
	# `stone` is a single-cell tile - the path that always worked. If this broke, the fix moved
	# the fault rather than removing it.
	var f2 := _render("stone")
	var s2 := _render("!depleted:stone")
	var fb2 := _mean_brightness(f2, 2 * Room.CELL, 3 * Room.CELL, Room.CELL, Room.CELL)
	var sb2 := _mean_brightness(s2, 2 * Room.CELL, 3 * Room.CELL, Room.CELL, Room.CELL)
	ck(sb2 < fb2 * 0.92, "a gathered stone is still dimmer (%.3f vs %.3f)" % [sb2, fb2])

	print("\n===== AND DIMMING IS NOT PAID FOR TWICE =====")
	# The shading is a per-pixel loop in script, which is exactly what made the map stutter
	# before `_darken` became a rect operation. It must be cached, not recomputed per compose.
	var t0 := Time.get_ticks_usec()
	for i in range(40):
		Room._key = ""
		Room.build(_grid("!depleted:tree"), _biomes(), {})
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 40.0
	print("  %.2f ms per compose with a spent big tile in view" % ms)
	ck(ms < 6.0, "composing a spent big tile costs %.2f ms" % ms)

	print("\n[DEPLETEDBIG] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
