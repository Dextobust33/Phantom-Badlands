extends SceneTree
## Hovering a map square must report the danger of THAT ground.
##
## Owner 2026-09-13: *"now that roads are safe and areas level moves around a bit we need to make
## sure players aren't blindsided by high level areas... make it where players can hover an area
## of the map to see the area level."*
##
## ⚑ WHY THIS PROBE EXISTS AT ALL. The hover has three separate pieces - the server samples a
## coarse level grid, the payload carries it, and the CLIENT converts a screen cell into a grid
## index. The third is the one that can be silently wrong: an off-by-one in the row flip, or a
## block index computed from the wrong origin, produces a number for every square and the WRONG
## number for every square. Nothing errors. The player reads it and walks into it.
##
## So this reproduces the client's index arithmetic EXACTLY and compares the answer against the
## level the server would report for the world tile under that square.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


## The client's arithmetic, copied from `_show_overworld_level_hover`. If this ever disagrees with
## client.gd the probe is measuring a fiction - it is asserted against the real source below.
func _client_lookup(levels: Array, block: int, cell_x: int, cell_y: int) -> int:
	var bx: int = cell_x / block
	var by: int = cell_y / block
	if by < 0 or by >= levels.size():
		return -1
	var row = levels[by]
	if bx < 0 or bx >= row.size():
		return -1
	return int(row[bx])


func _block_range(ws, cx: int, cy: int, radius: int, span: int, block: int,
		sx: int, sy: int) -> Array:
	"""The lowest and highest true level among the tiles one map block covers."""
	var lo := 1 << 30
	var hi := 0
	for iy in range(block):
		for ix in range(block):
			var cell_x: int = (sx / block) * block + ix
			var cell_y: int = (sy / block) * block + iy
			if cell_x >= span or cell_y >= span:
				continue
			# Column runs west->east; row runs NORTH->south, which is the flip worth checking.
			# ⚑ THE HUD'S OWN SOURCE. This probe originally compared the hover against
			# `get_post_anchored_level` and claimed that was "the Area readout". It is not - the
			# HUD reads `get_monster_level_range(...).base_level`, which INCLUDES the hotzone
			# multiplier. Both sides of the comparison used the same wrong function, so it
			# passed 5/5 while the hover understated hotzone ground by up to 2.75x.
			var t: int = ws.danger_level_at(cx - radius + cell_x, cy + radius - cell_y)
			lo = mini(lo, t)
			hi = maxi(hi, t)
	return [lo, hi]


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	var block: int = WorldSystemScript.LEVEL_BLOCK
	var radius := 11
	var span := radius * 2 + 1

	print("===== THE CLIENT'S LOOKUP MUST MATCH client.gd =====")
	# The copy above is only trustworthy if it IS the client's. Assert the two lines it depends on.
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(csrc.find("var bx: int = int(parts[0]) / _overworld_level_block") >= 0,
		"client derives the block column by integer division")
	ck(csrc.find("var by: int = int(parts[1]) / _overworld_level_block") >= 0,
		"...and the block row the same way")
	ck(csrc.find('return "[url=owlv:%s]%s[/url]" % [dkey, img], crop)') >= 0,
		"and EVERY plain map square carries the owlv link, or nothing is hoverable")

	print("
===== THE NUMBER UNDER THE CURSOR BELONGS TO THAT GROUND =====")
	# THE UNIT, which took two wrong answers to get right.
	#
	# First this asserted "within 3 LEVELS", which a 4-tile block cannot hold at level 6500 where
	# the field climbs tens of levels across four tiles. Then "within 2 PERCENT", which it cannot
	# hold at level 55 where three levels IS five percent. Both were tolerances invented from
	# outside, and both failed on a hover that was working.
	#
	# The honest question is not "how close is it" - it is "does this number come from the right
	# PART OF THE MAP". A block stands for sixteen tiles, so the number it shows must be one the
	# ground inside it actually reaches: between the lowest and highest level in that block. A
	# wrong index reads ground that is not there and falls outside immediately, at any level.
	var outside := 0
	var checked := 0
	var payload_missing := 0
	var worst_desc := ""
	for spot in [[0, 0], [340, -120], [-900, 640], [1500, 1500], [-2100, 300]]:
		var cx: int = spot[0]
		var cy: int = spot[1]
		var payload: Dictionary = ws.build_map_payload(cx, cy, radius)
		var levels: Array = payload.get("levels", [])
		if levels.is_empty():
			payload_missing += 1
			continue
		for sy in range(span):
			for sx in range(span):
				var shown: int = _client_lookup(levels, block, sx, sy)
				if shown < 0:
					continue
				var band: Array = _block_range(ws, cx, cy, radius, span, block, sx, sy)
				checked += 1
				if shown < int(band[0]) or shown > int(band[1]):
					outside += 1
					if worst_desc == "":
						worst_desc = "cell (%d,%d) showed %d, block spans %d-%d" % [
							sx, sy, shown, int(band[0]), int(band[1])]
	ck(payload_missing == 0, "every view carried a level grid (%d missing)" % payload_missing)
	ck(checked > 2000, "checked %d squares across five parts of the world" % checked)
	ck(outside == 0, "every square's number is one its own block actually reaches (%d outside%s)" % [
		outside, "" if worst_desc == "" else " - " + worst_desc])

	print("
===== A WRONG INDEX WOULD BE CAUGHT =====")
	# Prove the check above CAN fail. A detector that never fires looks exactly like one that
	# finds nothing, so read the grid with the row flip removed - the single most likely mistake
	# in this arithmetic, and one that returns a plausible number for every square.
	var flipped := 0
	var flip_payload: Dictionary = ws.build_map_payload(1500, 1500, radius)
	var flip_levels: Array = flip_payload.get("levels", [])
	for sy in range(span):
		for sx in range(span):
			var shown: int = _client_lookup(flip_levels, block, sx, span - 1 - sy)
			if shown < 0:
				continue
			var band: Array = _block_range(ws, 1500, 1500, radius, span, block, sx, sy)
			if shown < int(band[0]) or shown > int(band[1]):
				flipped += 1
	ck(flipped > 0,
		"reading the grid upside down IS detected (%d squares land outside their block)" % flipped)

	print("\n===== AND IT IS THE SAME NUMBER THE AREA READOUT SHOWS =====")
	# Hovering the square you are STANDING on must agree with the `Area: Lv ~N` tag, or a player
	# is being shown two danger scales that disagree.
	var agree := 0
	var tested := 0
	for spot in [[0, 0], [340, -120], [-900, 640], [1500, 1500], [-2100, 300]]:
		var cx: int = spot[0]
		var cy: int = spot[1]
		var payload: Dictionary = ws.build_map_payload(cx, cy, radius)
		var levels: Array = payload.get("levels", [])
		if levels.is_empty():
			continue
		# The player is always the centre square of the view.
		var shown: int = _client_lookup(levels, block, radius, radius)
		var area: int = ws.danger_level_at(cx, cy)
		tested += 1
		# EXACT. The grid is offset so the player's block samples the player's tile, so there is
		# no tolerance to grant here - a difference of one means the alignment is gone.
		if shown == area:
			agree += 1
		else:
			print("    (%d,%d) hover says %d, Area readout says %d" % [cx, cy, shown, area])
	ck(tested > 0 and agree == tested,
		"your own square reads the same as the Area tag in %d/%d places" % [agree, tested])

	print("
===== AND IT TELLS THE TRUTH INSIDE A HOTZONE =====")
	# The case that made this necessary. A hotzone multiplies spawns by 1.5-2.5x, and every
	# surface that warns a player has to carry that or it warns about the wrong world.
	var hot_checked := 0
	var hot_wrong := 0
	var hot_worst := ""
	for y in range(-140, 141, 2):
		for x in range(60, 700, 2):
			if not ws.get_hotspot_at(x, y).get("in_hotspot", false):
				continue
			hot_checked += 1
			var warned: int = ws.danger_level_at(x, y)
			var spawn_max: int = int(ws.get_monster_level_range(x, y).get("max", 0))
			# Warned-about level must be within the spawn variance of what actually arrives.
			if absi(warned - spawn_max) > maxi(2, int(spawn_max * 0.15)):
				hot_wrong += 1
				if hot_worst == "":
					hot_worst = "(%d,%d) warns Lv %d, spawns up to Lv %d" % [x, y, warned, spawn_max]
	ck(hot_checked > 500, "sampled %d hotzone tiles" % hot_checked)
	ck(hot_wrong == 0, "every hotzone tile warns about what actually spawns there (%d wrong%s)" % [
		hot_wrong, "" if hot_worst == "" else " - " + hot_worst])


	print("\n===== IT DOES NOT COST A STEP =====")
	var t0 := Time.get_ticks_usec()
	for i in range(60):
		ws.map_level_blocks(i * 37, i * 53, radius)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 60.0
	print("  %.2f ms per payload for the level grid" % ms)
	ck(ms < 2.0, "the level grid costs %.2f ms a move (< 2.0)" % ms)

	print("\n[MAPLEVELHOVER] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
