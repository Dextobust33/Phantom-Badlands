extends SceneTree
## What a single step costs, end to end, after today's changes.
##
## Owner 2026-09-13, on the dungeon-marker fix: *"This isn't going to lead to a regression of lag
## is it?"* A fair question after two lag regressions, and the honest answer is a measurement.
##
## Everything added today that runs PER STEP is timed here against the budget that matters: a
## step has to feel instant, and the server answers every message on one thread.
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

	# Walk a real line so chunks are warm, the way they are for a player who has been moving.
	for i in range(12):
		ws.build_map_payload(40 + i, -10, 11)

	print("===== THE WHOLE MAP PAYLOAD, PER STEP =====")
	var worst := 0.0
	var total := 0.0
	var n := 60
	for i in range(n):
		var t0 := Time.get_ticks_usec()
		ws.build_map_payload(40 + i, -10, 11)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
	print("  mean %.2f ms, worst %.2f ms over %d steps" % [total / n, worst, n])
	ck(total / n < 12.0, "the average step builds its map in %.2f ms" % (total / n))
	ck(worst < 40.0, "and the worst single step is %.2f ms (under the 40ms hitch threshold)" % worst)

	print("\n===== SCOUTING, WHICH WIDENS THE VIEW =====")
	# +2 radius is 27x27 instead of 23x23 - 38% more cells. It must still fit the budget.
	var swors := 0.0
	var stot := 0.0
	for i in range(30):
		var t1 := Time.get_ticks_usec()
		ws.build_map_payload(40 + i, -10, 13)
		var ms2 := float(Time.get_ticks_usec() - t1) / 1000.0
		stot += ms2
		swors = maxf(swors, ms2)
	print("  scouting: mean %.2f ms, worst %.2f ms" % [stot / 30.0, swors])
	ck(stot / 30.0 < 18.0, "scouting costs %.2f ms a step" % (stot / 30.0))

	print("\n===== AND WHAT TODAY ADDED TO IT =====")
	# The dungeon FAMILY is one dictionary lookup per visible dungeon, and the level grid is the
	# only other per-step addition. Both timed directly so the answer is a number.
	var t2 := Time.get_ticks_usec()
	for i in range(200):
		ws.map_level_blocks(40 + i, -10, 11)
	var lvl_ms := float(Time.get_ticks_usec() - t2) / 1000.0 / 200.0
	print("  map hover level grid: %.2f ms a step" % lvl_ms)
	ck(lvl_ms < 2.5, "the level grid costs %.2f ms" % lvl_ms)

	var DungeonDB = load("res://shared/dungeon_database.gd")
	var t3 := Time.get_ticks_usec()
	for i in range(20000):
		DungeonDB.entrance_family("goblin_caves")
	var fam_us := float(Time.get_ticks_usec() - t3) / 20000.0
	print("  dungeon family lookup: %.3f us each (a few per step)" % fam_us)
	ck(fam_us < 2.0, "the family lookup is %.3f us - not a cost" % fam_us)

	print("\n[MAPSTEPCOST] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
