extends SceneTree
## What would a SPRITED overworld cost the client to draw?
##
## Owner 2026-09-11 asked whether the whole overworld could be sprites, and what it would do to
## server load and player capacity. The server side is measured in `docs/BACKLOG.md`; this is the
## client half, measured rather than extrapolated from the dungeon's 171 tiles.
##
## The overworld viewport is radius 11 -> 23x23 = 529 cells, three times the dungeon's floor.
const TILE := 32
const VIEW_R := 11

func _tiles(n: int) -> Array:
	"""n distinct real sprite paths, so texture loading is in the numbers."""
	var out: Array = []
	var dir := DirAccess.open("res://client/sprites/tile_floor32")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "" and out.size() < n:
			if f.ends_with(".png"):
				out.append("res://client/sprites/tile_floor32/" + f)
			f = dir.get_next()
		dir.list_dir_end()
	while out.size() < n and out.size() > 0:
		out.append(out[out.size() % maxi(1, out.size())])
	return out


func _grid(side: int, paths: Array, hoverable: bool) -> String:
	var out := ""
	var i := 0
	for y in range(side):
		for x in range(side):
			var p: String = String(paths[i % paths.size()])
			i += 1
			if hoverable:
				out += "[url=t:%d,%d][img=%dx%d]%s[/img][/url]" % [x, y, TILE, TILE, p]
			else:
				out += "[img=%dx%d]%s[/img]" % [TILE, TILE, p]
		out += "\n"
	return out


func _time(rtl: RichTextLabel, text: String, reps: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(reps):
		rtl.clear()
		rtl.append_text(text)
		rtl.get_content_height()      # forces layout, not just the parse
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(reps)


func _init() -> void:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.size = Vector2(1280, 720)
	get_root().add_child(rtl)

	var paths: Array = _tiles(20)
	if paths.is_empty():
		print("no sprites on disk to measure with (licensed art not restored?) - skipping")
		quit(0)
		return

	var side: int = VIEW_R * 2 + 1
	print("=== CLIENT: one overworld redraw, sprited (%dx%d = %d inline images) ===" % [
		side, side, side * side])

	var plain := _grid(side, paths, false)
	var hov := _grid(side, paths, true)
	_time(rtl, plain, 3)      # warm the texture loads out of the numbers
	_time(rtl, hov, 3)
	var ms_plain := _time(rtl, plain, 25)
	var ms_hov := _time(rtl, hov, 25)
	print("  plain sprites        : %.2f ms" % ms_plain)
	print("  hoverable ([url=]) : %.2f ms  (%+.2f ms)" % [ms_hov, ms_hov - ms_plain])
	print("  bytes of BBCode      : %d plain / %d hoverable" % [plain.length(), hov.length()])

	# The dungeon's own figure, for scale.
	var dside := 19
	var dgrid := _grid(dside, paths, false)
	_time(rtl, dgrid, 3)
	var ms_d := _time(rtl, dgrid, 25)
	print("\n=== for scale: a dungeon-sized grid (%dx%d = %d) ===" % [dside, dside, dside * dside])
	print("  %.2f ms  -> the overworld is %.1fx the dungeon's draw" % [ms_d, ms_plain / maxf(0.01, ms_d)])

	print("\n=== what that means while walking ===")
	for per_sec in [1.0, 2.0, 4.0]:
		print("  at %.0f move(s)/sec: %.1f%% of one client core" % [
			per_sec, ms_hov * per_sec / 10.0])

	print("\n=== and what the SERVER stops doing ===")
	print("  today the server RENDERS this map itself: 17.2 ms CPU + 13,333 bytes per update.")
	print("  sending tile DATA instead is ~%d bytes (1 byte/tile) + entities." % (side * side))
	quit(0)
