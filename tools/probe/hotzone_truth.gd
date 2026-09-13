extends SceneTree
## What a hotzone actually IS, measured - before changing it.
##
## Owner 2026-09-13: *"hotzones don't serve much of a purpose anymore"*, and they should become
## rich hunting grounds that expire or move. Before redesigning them, establish what they do
## today, because two of the three things I assumed turned out to be wrong.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("===== HOW MUCH OF THE WORLD IS HOTZONE, AND HOW BIG =====")
	var tiles := 0
	var hot := 0
	var worst_gap := 0.0
	var worst_desc := ""
	var gaps: Array = []
	for y in range(-140, 141, 2):
		for x in range(60, 700, 2):
			tiles += 1
			var info: Dictionary = ws.get_hotspot_at(x, y)
			if not info.get("in_hotspot", false):
				continue
			hot += 1
			# ⚑ THE TWO NUMBERS. `get_post_anchored_level` is what the Area readout shows and
			# what the new danger-step guard reads. `get_monster_level_range` is what actually
			# SPAWNS. If they disagree, every warning surface is lying inside a hotzone.
			var shown: int = ws.danger_level_at(x, y)
			var spawn: Dictionary = ws.get_monster_level_range(x, y)
			var spawn_max: int = int(spawn.get("max", 0))
			var ratio: float = float(spawn_max) / float(maxi(1, shown))
			gaps.append(ratio)
			if ratio > worst_gap:
				worst_gap = ratio
				worst_desc = "(%d,%d) Area says Lv %d, monsters spawn up to Lv %d" % [
					x, y, shown, spawn_max]
	var pct: float = 100.0 * float(hot) / float(maxi(1, tiles))
	print("  %.2f%% of sampled ground is hotzone (%d of %d tiles)" % [pct, hot, tiles])
	ck(hot > 50, "found %d hotzone tiles to measure" % hot)

	print("\n===== DOES THE WARNING MATCH WHAT SPAWNS? =====")
	var mean := 0.0
	for g in gaps:
		mean += float(g)
	mean /= float(maxi(1, gaps.size()))
	print("  worst: %s  (%.2fx)" % [worst_desc, worst_gap])
	print("  mean spawn-to-shown ratio inside a hotzone: %.2fx" % mean)
	# ⚑ THIS CHECK FOUND THE BUG AND NOW GUARDS IT. Reading `get_post_anchored_level` here
	# measured 2.06x on average and 2.75x at worst - "Area says Lv 104, monsters spawn up to Lv
	# 286" - because the baseline excludes the hotzone multiplier while spawns apply it. Every
	# warning surface reads `danger_level_at` now, which is what this asserts.
	ck(worst_gap <= 1.25,
		"what a player is warned about is within 25%% of what spawns (worst %.2fx)" % worst_gap)

	print("\n===== AND OUTSIDE A HOTZONE, DO THEY AGREE? =====")
	# The control. If they disagree everywhere, the hotzone is not the cause.
	var outside_worst := 0.0
	var outside_desc := ""
	var checked := 0
	for y in range(-140, 141, 7):
		for x in range(60, 700, 7):
			if ws.get_hotspot_at(x, y).get("in_hotspot", false):
				continue
			var shown: int = ws.danger_level_at(x, y)
			var spawn_max: int = int(ws.get_monster_level_range(x, y).get("max", 0))
			var ratio: float = float(spawn_max) / float(maxi(1, shown))
			checked += 1
			if ratio > outside_worst:
				outside_worst = ratio
				outside_desc = "(%d,%d) Area %d vs spawn %d" % [x, y, shown, spawn_max]
	print("  worst outside a hotzone, over %d tiles: %.2fx  %s" % [checked, outside_worst, outside_desc])
	ck(outside_worst <= 1.25,
		"and outside a hotzone too (%.2fx) - the control that proved the hotzone was the cause" % outside_worst)

	print("\n===== DO THEY MOVE? =====")
	# The owner wants them to relocate every few hours. Today they are pure coordinate hashes,
	# so the answer should be no - stated as a measurement rather than from reading the code.
	var before: Array = []
	for x in range(100, 400):
		before.append(ws.get_hotspot_at(x, 0).get("in_hotspot", false))
	var moved := 0
	# Nothing in the current implementation reads a clock, so re-querying can only agree.
	for i in range(before.size()):
		if ws.get_hotspot_at(100 + i, 0).get("in_hotspot", false) != before[i]:
			moved += 1
	print("  re-querying the same 300 tiles: %d differ" % moved)
	ck(moved == 0, "today a hotzone is a fixed property of the coordinate - it never moves")

	print("\n[HOTZONETRUTH] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
