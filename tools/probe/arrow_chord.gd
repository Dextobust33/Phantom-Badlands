extends SceneTree
## `_arrow_mask_to_dir` is pure - test it directly. The grace WINDOW needs real key timing and is
## checked in-game, but the mask maths is where an off-by-one would silently send a player the
## wrong way, so it gets a table.
func _init() -> void:
	var C = load("res://client/client.gd").new()
	var cases := [
		[1, 8, "N"], [2, 2, "S"], [4, 4, "W"], [8, 6, "E"],
		[1 | 4, 7, "N+W = NW"], [1 | 8, 9, "N+E = NE"],
		[2 | 4, 1, "S+W = SW"], [2 | 8, 3, "S+E = SE"],
		[1 | 2, 0, "N+S cancel"], [4 | 8, 0, "W+E cancel"],
		[1 | 2 | 4, 4, "N+S cancel, W survives"],
		[1 | 4 | 8, 8, "W+E cancel, N survives"],
		[1 | 2 | 4 | 8, 0, "all four cancel"],
		[0, 0, "nothing"],
	]
	var bad := 0
	for c in cases:
		var got: int = C._arrow_mask_to_dir(int(c[0]))
		var want: int = int(c[1])
		var mark := "ok  " if got == want else "FAIL"
		if got != want:
			bad += 1
		print("  %s %-26s got %d want %d" % [mark, String(c[2]), got, want])
	print("[ARROWCHORD] %s (%d bad)" % ["PASS" if bad == 0 else "FAIL", bad])
	C.free()
	quit(0 if bad == 0 else 1)
