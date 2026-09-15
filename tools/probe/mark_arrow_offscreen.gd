extends SceneTree
## When the marked tile is off the map, does the map point at it?
##
## Owner 2026-09-15: *"when it says to go to the gold ring will that actually be on the players
## map or too far away for them to see it or behind an overlay?"*
##
## Too far, usually. The starter dungeon spawns ~30 tiles from the origin against a vision radius
## of 11, and the client's off-grid branch set the mark to (-1,-1) - "nothing to draw" - so the
## gold ring was invisible for most of the walk it exists for, and the Warden's line "It is
## ringed on your map" was false whenever he said it.
##
## Now an off-grid mark is drawn as a gold arrowhead a few cells from the player, pointing at it.
## This probe RENDERS both forms and reads pixels: a source read cannot tell an arrow that points
## the right way from one that points backwards, or a branch that never runs.
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _is_gold(c: Color) -> bool:
	return absf(c.r - 1.0) < 0.03 and absf(c.g - 0.84) < 0.03 and absf(c.b - 0.25) < 0.03


func _gold_extent(img: Image, cx: int, cy: int) -> Dictionary:
	var n := 0
	var x0 := 999
	var x1 := -1
	var y0 := 999
	var y1 := -1
	for y in range(Room.CELL):
		for x in range(Room.CELL):
			if _is_gold(img.get_pixel(cx * Room.CELL + x, cy * Room.CELL + y)):
				n += 1
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return {"n": n, "x0": x0, "x1": x1, "y0": y0, "y1": y1}


## How far the gold reaches ALONG a direction versus against it. The tip is at +12.5 and the base
## at -8.5, so an arrow pointing the way it should reaches further forward than back. (Bounding
## boxes lie on a diagonal: the base corners stick out further than the tip.)
func _reach(img: Image, cx: int, cy: int, dir: Vector2) -> Array:
	var d := dir.normalized()
	var half := (Room.CELL - 1) / 2.0
	var fwd := -999.0
	var back := -999.0
	for y in range(Room.CELL):
		for x in range(Room.CELL):
			if _is_gold(img.get_pixel(cx * Room.CELL + x, cy * Room.CELL + y)):
				var a: float = (x - half) * d.x + (y - half) * d.y
				fwd = maxf(fwd, a)
				back = maxf(back, -a)
	return [fwd, back]


func _render(mark_cell: Vector2i, arrow: Vector2i) -> Image:
	var meaning: Array = []
	var biomes: Array = []
	for r in range(5):
		meaning.append(PackedStringArray(["empty", "empty", "empty", "empty", "empty"]))
		biomes.append(PackedStringArray(["plains", "plains", "plains", "plains", "plains"]))
	Room._key = ""
	Room.build(meaning, biomes, {}, {}, 0, mark_cell, arrow)
	return Room._grid.duplicate()


func _init() -> void:
	if not Room.available():
		print("  (overworld art not present - cannot render; this is NOT a pass)")
		quit(1)
		return
	var half := (Room.CELL - 1) / 2.0

	print("===== ON THE GRID: STILL A RING =====")
	var ring := _render(Vector2i(3, 2), Vector2i.ZERO)
	ck(_is_gold(ring.get_pixel(3 * Room.CELL, 2 * Room.CELL)), "the ring's corner pixel is gold")
	ck(not _is_gold(ring.get_pixel(3 * Room.CELL + 16, 2 * Room.CELL + 16)), "and its middle is not")

	print("\n===== OFF THE GRID: AN ARROW, NOT A RING =====")
	var east := _render(Vector2i(3, 2), Vector2i(30, 0))
	var e := _gold_extent(east, 3, 2)
	print("  east arrow: %d gold px, x %d..%d, y %d..%d" % [e.n, e.x0, e.x1, e.y0, e.y1])
	ck(e.n > 80, "an arrowhead is drawn (%d gold pixels)" % e.n)
	ck(not _is_gold(east.get_pixel(3 * Room.CELL, 2 * Room.CELL)), "no ring corner")
	var er := _reach(east, 3, 2, Vector2(1, 0))
	ck(er[0] > er[1] + 1.0, "it points EAST: reaches %.1f forward, %.1f back" % [er[0], er[1]])
	ck(absf((e.y0 + e.y1) / 2.0 - half) <= 1.0, "and it is centred vertically")

	# Screen y runs SOUTH. The client passes a screen-space direction, so (0,-N) is north / up.
	var north := _render(Vector2i(2, 1), Vector2i(0, -30))
	var n := _gold_extent(north, 2, 1)
	print("  north arrow: %d gold px, x %d..%d, y %d..%d" % [n.n, n.x0, n.x1, n.y0, n.y1])
	var nr := _reach(north, 2, 1, Vector2(0, -1))
	ck(nr[0] > nr[1] + 1.0, "(0,-N) points UP the screen: %.1f forward, %.1f back" % [nr[0], nr[1]])

	var sw := _render(Vector2i(1, 3), Vector2i(-20, 20))
	var sr := _reach(sw, 1, 3, Vector2(-1, 1))
	ck(sr[0] > sr[1] + 1.0, "(-N,+N) points down-left: %.1f forward, %.1f back" % [sr[0], sr[1]])
	# And the wrong way round must FAIL the same test - prove the check can fire.
	var wrong := _reach(sw, 1, 3, Vector2(1, -1))
	ck(not (wrong[0] > wrong[1] + 1.0), "control: the same arrow does NOT read as pointing up-right")
	var big := Image.create(Room.CELL * 3, Room.CELL, false, Image.FORMAT_RGBA8)
	big.blit_rect(east, Rect2i(3 * Room.CELL, 2 * Room.CELL, Room.CELL, Room.CELL), Vector2i(0, 0))
	big.blit_rect(north, Rect2i(2 * Room.CELL, 1 * Room.CELL, Room.CELL, Room.CELL), Vector2i(Room.CELL, 0))
	big.blit_rect(sw, Rect2i(1 * Room.CELL, 3 * Room.CELL, Room.CELL, Room.CELL), Vector2i(Room.CELL * 2, 0))
	big.resize(Room.CELL * 3 * 6, Room.CELL * 6, Image.INTERPOLATE_NEAREST)
	big.save_png(OS.get_environment("PROBE_PNG") if OS.get_environment("PROBE_PNG") != "" else "user://mark_arrow.png")

	print("\n===== THE CLIENT ACTUALLY SENDS IT =====")
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(csrc.contains("_ow_anim_tick, mark_cell, mark_arrow)"), "the map composer passes mark_arrow to build")
	ck(not csrc.contains("mark_cell = Vector2i(-1, -1)      # off screen this step; nothing to draw"),
		"the draw-nothing branch is gone")

	print("")
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
