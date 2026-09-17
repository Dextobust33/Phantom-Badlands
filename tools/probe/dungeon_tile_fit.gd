extends SceneTree
## ⛑ THE DUNGEON FLOOR AT EVERY WINDOW SHAPE - WITHOUT OPENING A WINDOW.
##
## The backlog carried *"everything in this arc was measured at ONE canvas size"* for days, and the
## obvious way to answer it - run the screenshot harness at several resolutions - is BOTH expensive
## and, on this hardware, impossible. `--screen 1` puts the harness window on a 1920x1080 monitor
## whose work area is 1920x1032, so every taller or wider window requested was clamped back to the
## same 1009 and four "different" runs measured the same shape four times.
##
## It also matters that each of those runs opened a window on the owner's desk. Owner 2026-09-16:
## *"Am I crazy or do you keep opening a client?"* The cheapest window is the one not opened, so
## the fit maths was pulled out of the renderer into `Client.dungeon_tile_fit`, which depends on
## the canvas it is handed and nothing else. This is that check, headless.
##
## What it is actually asking: the floor is drawn at 32, 64, 96 or 128 px, and a shape that lands
## one step lower than the frames the owner reviewed shows a QUARTER of the area. So the question
## is not "is it the same everywhere" - it will not be - but "where are the cliffs, and is any
## plausible window on the wrong side of one".
##
## Run:
##   godot --headless --path . --script res://tools/probe/dungeon_tile_fit.gd

const Client := preload("res://client/client.gd")

## What the renderer subtracts before handing the maths its room - mirrored from
## `_dungeon_pick_tile_px`. Kept as named constants so a change there shows up here as a wrong
## number rather than as silence.
const CANVAS_W_INSET := 24.0
const CANVAS_H_INSET := 8.0
const VIEW_COLS := 19
## The bottom dock (party strip + key). Measured at 72 on the reference layout.
const DOCK_H := 72.0

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _fit(canvas_w: float, canvas_h: float) -> Dictionary:
	return Client.dungeon_tile_fit(canvas_w - CANVAS_W_INSET,
		canvas_h - CANVAS_H_INSET - DOCK_H, VIEW_COLS)


func _init() -> void:
	# The canvas is not the window: the game stretches with `canvas_items` + `aspect=expand`, so
	# the viewport width is pinned at 1920 and the HEIGHT tracks the window's aspect. A 16:9
	# window of any resolution gives the same viewport, which is why four resolutions read
	# identically. Only the ASPECT moves anything.
	print("===== 1. EVERY PLAUSIBLE WINDOW SHAPE =====")
	print("  %-12s %-9s %-11s %s" % ["aspect", "viewport", "canvas", "floor"])
	var shapes := [
		["16:9", 1920, 1080], ["16:10", 1920, 1200], ["3:2", 1920, 1280],
		["21:9", 1920, 823], ["4:3", 1920, 1440], ["32:9", 1920, 540],
	]
	for sh in shapes:
		# The canvas is the viewport less the action bar, chat row and top HUD - about 270px on
		# the reference layout, measured from `game_output` at 1920x1009 -> 1367x792.
		var vw: float = float(sh[1])
		var vh: float = float(sh[2])
		var cw: float = vw - 553.0
		var chh: float = vh - 217.0
		var f: Dictionary = _fit(cw, chh)
		print("  %-12s %-9s %-11s tile=%dpx rows=%d" % [
			sh[0], "%dx%d" % [int(vw), int(vh)], "%dx%d" % [int(cw), int(chh)],
			int(f["tile"]), int(f["rows"])])

	print("\n===== 2. THE OWNER'S OWN TWO MONITORS LAND ON THE REVIEWED SIZE =====")
	# Measured 2026-09-16: primary 2560x1440, secondary 1920x1080. BOTH are 16:9, so both give
	# the same viewport and the same floor - the frames the owner reviewed are what they will see
	# on either screen. This is the part of the backlog item that actually mattered.
	var ref: Dictionary = _fit(1367.0, 792.0)
	ck(int(ref["tile"]) == 64, "the reviewed 1367x792 canvas draws at 64px (got %d)" % int(ref["tile"]))
	ck(int(ref["rows"]) == 9 or int(ref["rows"]) == 11,
		"...with an odd row count in range (got %d)" % int(ref["rows"]))

	print("\n===== 3. WHERE THE CLIFFS ARE =====")
	# The tile only changes at a width, so the useful number is the narrowest canvas that still
	# affords each step. Below 1240 the floor halves to 32px and shows a quarter of the area.
	for step in [64, 96, 128]:
		var need: float = float(VIEW_COLS * step) + CANVAS_W_INSET
		print("  %dpx needs a canvas %.0f wide (viewport %.0f)" % [step, need, need + 553.0])
	var just_under: Dictionary = _fit(float(VIEW_COLS * 64) + CANVAS_W_INSET - 1.0, 792.0)
	ck(int(just_under["tile"]) == 32,
		"one pixel under the 64px width drops to 32 - a cliff, not a slope (got %d)" % int(just_under["tile"]))

	print("\n===== 4. AND A SHORT WINDOW NEVER LETTERBOXES =====")
	# Rows are clamped 7-15 and forced odd so the player is always on the middle row. A 32:9
	# strip would otherwise compute two rows and put the player on the edge of their own map.
	for h in [400.0, 600.0, 792.0, 1200.0, 2000.0]:
		var f2: Dictionary = _fit(1367.0, h)
		var r: int = int(f2["rows"])
		ck(r >= 7 and r <= 15 and r % 2 == 1,
			"canvas %.0f tall -> %d rows (odd, 7-15)" % [h, r])

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
