extends SceneTree
## What the world threat refresh costs, and why the lag came back.
##
## Owner 2026-09-13: *"The intermittent lag is still in the game... I walk a few or up to around
## 7 steps then it freezes for a moment"* and then *"It even seems to happen in combat. It
## definitely feels like its taking longer for the server to respond intermittently."*
##
## "In combat too" is the clue that matters. Movement and combat share nothing except the server
## TICK, so a stall in both is periodic work in `_process`, not anything on the move path. There
## is exactly one periodic job whose period matches a few seconds: `_refresh_world_threat_states`,
## every 3 seconds, documented as O(npc_posts x active_dungeons).
##
## And npc_posts went from 60 to 120 in v0.9.781 - my own change - which doubled it.
const ServerScript = preload("res://server/server.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")
const DungeonDB = preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _fake_dungeons(n: int, seed_v: int) -> Dictionary:
	"""A world's worth of active dungeons, spread the way the real ones are."""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var types: Array = DungeonDB.DUNGEON_TYPES.keys()
	var out: Dictionary = {}
	for i in range(n):
		var r: float = sqrt(rng.randf()) * 2600.0
		var a: float = rng.randf() * TAU
		out["d%d" % i] = {
			"world_x": int(cos(a) * r),
			"world_y": int(sin(a) * r),
			"dungeon_type": String(types[rng.randi() % types.size()]),
			"sub_tier": rng.randi_range(1, 9),
			"completed_at": 0,
		}
	return out


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	var srv = ServerScript.new()
	srv.world_system = ws
	srv.chunk_manager = cm

	var posts: int = cm.get_npc_posts().size()
	print("===== THE SCAN, AT THE SIZE THE WORLD IS NOW =====")
	print("  %d NPC posts (it was 60 before v0.9.781)" % posts)
	print("%10s %12s %14s" % ["dungeons", "refresh", "per 3s window"])
	var measured: Dictionary = {}
	for n in [200, 500, 1000, 2000, 3000]:
		srv.active_dungeons = _fake_dungeons(n, 99)
		srv._world_threat_states.clear()
		srv._threat_state_cache.clear()
		var t0 := Time.get_ticks_usec()
		srv._refresh_world_threat_states()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		measured[n] = ms
		var verdict := ""
		if ms >= 100.0:
			verdict = "  <-- A VISIBLE FREEZE"
		elif ms >= 40.0:
			verdict = "  <-- felt as a hitch"
		print("%10d %10.1fms %s" % [n, ms, verdict])

	print("\n===== AND IT MUST STILL BE RIGHT =====")
	# ⚑ A FASTER WRONG ANSWER IS WORSE THAN A SLOW RIGHT ONE. The index skips dungeons outside
	# the 3x3 bucket block, so if the bucket size were smaller than the reach it would silently
	# drop real threats and posts would stop looking threatened. Compare every post against a
	# brute-force scan of every dungeon.
	srv.active_dungeons = _fake_dungeons(1500, 7)
	srv._world_threat_states.clear()
	srv._threat_state_cache.clear()
	srv._refresh_world_threat_states()
	var indexed: Dictionary = srv._world_threat_states.duplicate(true)

	var mismatches := 0
	var checked := 0
	var first := ""
	for np_post in cm.get_npc_posts():
		var px: int = int(np_post.get("x", 0))
		var py: int = int(np_post.get("y", 0))
		# Brute force: the same rules, over every dungeon, no buckets.
		var want := 0
		for iid in srv.active_dungeons:
			var inst = srv.active_dungeons[iid]
			if inst.get("completed_at", 0) > 0 or inst.get("threat_cleared", false):
				continue
			if inst.has("owner_peer_id"):
				continue
			var dd: Dictionary = srv._dungeon_data_for(inst)
			if dd.is_empty() or int(dd.get("tier", 1)) < 2:
				continue
			var ddx: int = int(inst.world_x) - px
			var ddy: int = int(inst.world_y) - py
			if int(sqrt(float(ddx * ddx + ddy * ddy))) <= 80:
				want += 1
		var got_state: Dictionary = indexed.get("%d,%d" % [px, py], {"threatened": false})
		var got: bool = bool(got_state.get("threatened", false))
		checked += 1
		if got != (want > 0):
			mismatches += 1
			if first == "":
				first = "post (%d,%d): brute force found %d threats, index said %s" % [
					px, py, want, str(got)]
	ck(mismatches == 0, "all %d posts agree with a brute-force scan%s" % [
		checked, "" if first == "" else " - " + first])

	print("\n===== WOULD A PLAYER FEEL IT? =====")
	# The server ticks and answers messages on one thread, so a refresh this long delays EVERY
	# reply - a move, a combat action, anything. That is precisely the report.
	var at2000: float = float(measured.get(2000, 0.0))
	print("  at 2000 dungeons the tick stalls for %.0fms, every 3 seconds" % at2000)
	ck(at2000 < 40.0,
		"the 3-second refresh stays under 40ms (measured %.0fms)" % at2000)

	print("\n===== AND HOW MUCH OF IT IS THE POST COUNT =====")
	# The same work with the OLD post count, to size my own regression rather than assert it.
	srv.active_dungeons = _fake_dungeons(2000, 99)
	var all_posts: Array = cm.get_npc_posts()
	var half: Array = all_posts.slice(0, all_posts.size() / 2)
	cm.npc_posts = half
	srv._world_threat_states.clear()
	srv._threat_state_cache.clear()
	var t1 := Time.get_ticks_usec()
	srv._refresh_world_threat_states()
	var half_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	cm.npc_posts = all_posts
	print("  %d posts: %.0fms     %d posts: %.0fms" % [
		half.size(), half_ms, all_posts.size(), at2000])
	print("  doubling the post count cost %.0fms a refresh" % (at2000 - half_ms))

	print("\n[THREATREFRESH] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
