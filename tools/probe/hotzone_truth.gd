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

	print("\n===== ARE THEY DESTINATIONS, OR THINGS YOU BLUNDER INTO? =====")
	# Owner: hotzones should become rich hunting grounds. A place you TRAVEL to has to be big
	# enough to be worth the trip and rare enough to be a landmark - the old ones could be a
	# SINGLE TILE. Measure the footprint of each distinct ground, not just total coverage.
	var sizes: Array = []
	for y in range(-140, 141):
		for x in range(60, 700):
			if not ws._is_cluster_center(x, y):
				continue
			var r: float = ws._get_cluster_radius(x, y)
			sizes.append(int(round(PI * r * r)))
	var total := 0
	for v in sizes:
		total += int(v)
	var mean_size: float = float(total) / float(maxi(1, sizes.size()))
	sizes.sort()
	var smallest: int = int(sizes[0]) if sizes.size() > 0 else 0
	print("  %d hunting grounds in a 640x281 region, mean %.0f tiles, smallest %d, largest %d" % [
		sizes.size(), mean_size, smallest, int(sizes[-1]) if sizes.size() > 0 else 0])
	ck(smallest >= 10, "the SMALLEST is %d tiles - none are a single square you trip over" % smallest)
	ck(mean_size >= 25.0, "the typical one is %.0f tiles, big enough to hunt in" % mean_size)
	ck(pct > 0.8 and pct < 5.0,
		"and they still cover %.2f%% of ground - rarer but bigger, not simply more dangerous" % pct)

	print("\n===== DO THEY MOVE? =====")
	# Owner: "maybe a few hours before they move." The epoch is folded into the coordinate hash,
	# so advancing it must relocate the whole map of them. Drive the real function by moving the
	# clock, not by trusting that it reads one.
	var epoch_now: int = ws.hot_epoch()
	# ⚑ SAMPLE AN AREA, NOT A LINE. This first walked 600 tiles along y=0 and found ZERO centres
	# in either window, then reported "0 changed" as a failure to move. Centres are 7 in 10,000,
	# so a 600-tile line expects 0.4 of them - the probe was too small to see anything at all,
	# which looks exactly like a feature that does not work.
	var before: Array = []
	var spots: Array = []
	for y in range(-120, 121, 2):
		for x in range(100, 700, 2):
			spots.append(Vector2i(x, y))
			before.append(ws._is_cluster_center(x, y))
	ws._hot_epoch_value = epoch_now + 1
	ws._hot_epoch_checked_ms = Time.get_ticks_msec()
	var moved := 0
	var before_count := 0
	var after_count := 0
	for i in range(before.size()):
		var now_c: bool = ws._is_cluster_center(spots[i].x, spots[i].y)
		if bool(before[i]):
			before_count += 1
		if now_c:
			after_count += 1
		if now_c != bool(before[i]):
			moved += 1
	ws._hot_epoch_value = epoch_now
	print("  across %d sampled tiles: %d centres now, %d next window, %d changed" % [
		before.size(), before_count, after_count, moved])
	ck(moved > 0, "the next window puts them somewhere else")
	ck(ws.HOTZONE_PERIOD_SECONDS >= 3600.0 and ws.HOTZONE_PERIOD_SECONDS <= 21600.0,
		"a set stands for %.1f hours - 'a few hours', as asked" % (ws.HOTZONE_PERIOD_SECONDS / 3600.0))
	var left: int = ws.hotzone_seconds_remaining()
	ck(left > 0 and float(left) <= ws.HOTZONE_PERIOD_SECONDS,
		"and the time left is reportable to the player (%d min)" % int(left / 60))

	print("\n===== ONE PROMPT, NOT TWO =====")
	# The generic danger-step guard learned to read `danger_level_at`, which includes the hotzone
	# multiplier - so it started seeing hotzones, which already have their own entry prompt.
	# Without a hand-off, stepping into a hunting ground asked twice in a row.
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc.find("if world_system.get_hotspot_at(nx, ny).get(\"in_hotspot\", false):") >= 0,
		"the step guard stands down on a hotzone tile and lets the hunting-ground prompt speak")
	ck(ssrc.find("payload[\"confirm\"] = false") >= 0,
		"and a character who outclasses the ground is told, not asked")
	ck(ssrc.find("if float(estimated_level) / float(my_level) < DANGER_STEP_RATIO:") >= 0,
		"...on the same 2x threshold the step guard uses, so there is one danger scale")

	print("\n===== THE PROMISE MATCHES THE PAYOUT =====")
	# The screen quotes a bonus; combat pays one. They were three hand-copied copies of
	# `1.3 + i * 0.4`, which is how nearly every wrong-text bug in this project has started.
	for i in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var mult: float = WorldSystemScript.hotzone_reward_multiplier(float(i))
		var quoted: int = int(round((mult - 1.0) * 100.0))
		var expected: int = int(round((1.3 + float(i) * 0.4 - 1.0) * 100.0))
		ck(quoted == expected, "intensity %.2f pays +%d%% and says +%d%%" % [i, expected, quoted])
	var csrc := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(csrc.find("1.3 + hotspot_intensity * 0.4") < 0,
		"no hand-copied formula survives in combat_manager")
	# Count CALL SITES, not mentions - the doc comment above the preload names it too, and
	# counting the bare word made this fail on a file that was correct.
	ck(csrc.count("WorldSystemScript.hotzone_reward_multiplier(") == 2,
		"both the xp grant and the drop roll call the one function")

	print("\n===== AND WHAT LIVES THERE IS DIFFERENT =====")
	# The base elite roll is 1% above level 15 - invisible. A hunting ground has to feel unlike
	# ordinary ground or the reward is just a number in a log.
	var ServerScript = load("res://server/server.gd")
	ck(ServerScript.HOTZONE_ELITE_CHANCE_MIN >= 0.05,
		"at the edge %d%% of encounters are elites" % int(ServerScript.HOTZONE_ELITE_CHANCE_MIN * 100))
	ck(ServerScript.HOTZONE_ELITE_CHANCE_MAX >= ServerScript.HOTZONE_ELITE_CHANCE_MIN,
		"and %d%% at its heart" % int(ServerScript.HOTZONE_ELITE_CHANCE_MAX * 100))
	ck(ssrc.find("monster_db.generate_monster(level_range.min, level_range.max, encounter_biome, forced_role)") >= 0,
		"the forced role actually reaches the spawn, or none of that happens")
	var msrc := FileAccess.get_file_as_string("res://shared/monster_database.gd")
	ck(msrc.find("scale_monster_to_level(base_stats, target_level, false, force_role)") >= 0,
		"...and generate_monster passes it on rather than dropping it")

	print("\n[HOTZONETRUTH] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
