extends SceneTree
## What does the sprite work actually COST, and what does it cost the SERVER?
##
## Asked by the owner before committing to Raven Fantasy and to spriting whole rooms: "Is any of
## this sprite work going to tank server or client performance or severely limit the amount of
## players it can support online at once?" Measured rather than reasoned about.
const _C = preload("res://client/dungeon_composite.gd")
const _T = preload("res://client/dungeon_tiles.gd")

const VW := 19
const VH := 9

func _grid_text(with_composites: bool) -> String:
	var out := ""
	var sprites := ["res://client/sprites/monster_floor32/wolf_1.png",
		"res://client/sprites/monster_floor32/skeleton_1.png",
		"res://client/sprites/overworld_floor32/1_1/down_stand.png"]
	for y in range(VH):
		for x in range(VW):
			var prop: String = _T.prop_for(x + 40, y + 40)
			var path := ""
			if (x + y) % 11 == 0:
				# an entity cell — the only kind the compositor touches
				var spr: String = sprites[(x + y) % sprites.size()]
				path = _C.over_prop(spr, prop) if (with_composites and prop != "") else spr
			elif prop != "":
				path = prop
			else:
				path = "res://client/sprites/prop_floor32/prop_00.png"
			out += "[img=%dx%d]%s[/img]" % [64, 64, path]
		out += "\n"
	return out

func _time_layout(rtl: RichTextLabel, text: String, reps: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(reps):
		rtl.clear()
		rtl.append_text(text)
		rtl.get_content_height()      # forces the layout, not just the parse
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(reps)

func _init() -> void:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.size = Vector2(1280, 640)
	get_root().add_child(rtl)

	print("=== CLIENT: one full dungeon floor redraw (%dx%d = %d inline images) ===" % [
		VW, VH, VW * VH])
	var plain := _grid_text(false)
	var comp := _grid_text(true)
	_time_layout(rtl, plain, 3)        # warm the texture loads out of the numbers
	_time_layout(rtl, comp, 3)
	var ms_plain := _time_layout(rtl, plain, 40)
	var ms_comp := _time_layout(rtl, comp, 40)
	print("  before this change : %.2f ms" % ms_plain)
	print("  with composites    : %.2f ms  (%+.2f ms)" % [ms_comp, ms_comp - ms_plain])
	print("  the floor redraws at most every %.2fs while idle -> %.2f%% of one core" % [
		0.42, ms_comp / 420.0 * 100.0])

	print("\n=== CLIENT: what the composite cache can grow to ===")
	# Worst case is every monster sprite seen under every prop. 32x32 RGBA8 = 4096 bytes each.
	var monster_frames := 0
	var d := DirAccess.open("res://client/sprites/monster_floor32")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".png"):
				monster_frames += 1
	var worst: int = _T.PROP_COUNT * (monster_frames + 12 + 1)   # + own 12 walk frames + companion
	print("  props=%d  monster frames=%d  worst-case pairs=%d" % [
		_T.PROP_COUNT, monster_frames, worst])
	print("  at 32x32 RGBA8 (4KB each): %.1f MB if a single session met EVERY monster" % [
		worst * 4096.0 / 1048576.0])
	print("  realistic dungeon run (one class, ~8 monster types): %.2f MB" % [
		_T.PROP_COUNT * (8 * 6 + 12 + 1) * 4096.0 / 1048576.0])

	print("\n=== SERVER: what a dungeon step costs the wire ===")
	# The server sends the FLOOR GRID as ints plus entity positions. No sprite, tile, path or
	# pixel ever crosses the wire — every one of them is resolved client-side from the local pck.
	var grid := []
	for y in range(24):
		var row := []
		for x in range(28):
			row.append(0)
		grid.append(row)
	var payload := {
		"type": "dungeon_state", "dungeon_type": "wolf_den", "dungeon_name": "Wolf Den",
		"grid": grid, "player_x": 5, "player_y": 5, "floor": 1, "total_floors": 3,
		"monsters": [], "npcs": [], "floor_items": [], "triggered_traps": [],
	}
	for i in range(6):
		payload["monsters"].append({"id": i, "x": i, "y": i, "type": "wolf", "char": "w",
			"color": "#888888", "alert": false, "level": 10, "variant_name": "Grey Wolf"})
	var bytes := JSON.stringify(payload).to_utf8_buffer().size()
	print("  a 28x24 floor with 6 monsters: %d bytes per step" % bytes)
	print("  100 players each stepping once a second: %.1f KB/s outbound" % (bytes * 100 / 1024.0))
	quit()
