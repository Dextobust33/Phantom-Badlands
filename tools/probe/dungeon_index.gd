extends SceneTree
## Thousands of dungeons must cost no more per player step than two hundred did.
##
## Owner 2026-09-11: *"We also want to massively increase the amount of dungeons that players can
## find on the map. We don't want players to have to walk hundreds of tiles without seeing any
## dungeons... We need to find the best way to do this in a cost efficient manner."*
##
## What stood in the way was not memory but SHAPE. A single player move made roughly three linear
## passes over every dungeon in the world - `get_visible_dungeons` for the map and
## `_get_threat_zone_dungeon_at` twice - and spawning one walked the whole list again to check
## for stacking, which makes filling a world quadratic. Every cap around dungeons was a
## workaround for that.
##
## This probe holds the two claims the new count rests on: the bucket lookup gives the SAME
## answer as the scan it replaced, and it is cheap enough at the sizes now allowed.
const SRC := "res://server/server.gd"
const BUCKET := 64

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body(src: String, fname: String) -> String:
	var i := src.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, (j if j > 0 else src.length()) - i)


## A stand-in for the server's dictionaries, so the bucket maths can be exercised without one.
var dungeons: Dictionary = {}
var buckets: Dictionary = {}
var tiles: Dictionary = {}


func _bk(x: int, y: int) -> String:
	return "%d,%d" % [floori(float(x) / float(BUCKET)), floori(float(y) / float(BUCKET))]


func _add(iid: String, x: int, y: int) -> void:
	dungeons[iid] = {"world_x": x, "world_y": y}
	tiles["%d,%d" % [x, y]] = iid
	var k := _bk(x, y)
	if not buckets.has(k):
		buckets[k] = []
	buckets[k].append(iid)


func _near(x: int, y: int, radius: int) -> Array:
	var out: Array = []
	for bx in range(floori(float(x - radius) / float(BUCKET)), floori(float(x + radius) / float(BUCKET)) + 1):
		for by in range(floori(float(y - radius) / float(BUCKET)), floori(float(y + radius) / float(BUCKET)) + 1):
			for iid in buckets.get("%d,%d" % [bx, by], []):
				out.append(iid)
	return out


func _init() -> void:
	var src := FileAccess.get_file_as_string(SRC)

	print("--- the buckets answer exactly what the scan did ---")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260911
	var N := 3000
	for i in range(N):
		_add("d%d" % i, rng.randi_range(-2000, 2000), rng.randi_range(-2000, 2000))
	ck(dungeons.size() == N, "%d dungeons placed across the whole world" % N)

	var disagreements := 0
	var found_total := 0
	for q in range(400):
		var qx := rng.randi_range(-2000, 2000)
		var qy := rng.randi_range(-2000, 2000)
		var radius: int = [11, 40, 80][q % 3]
		var by_scan: Dictionary = {}
		for iid in dungeons:
			var d: Dictionary = dungeons[iid]
			if absi(int(d["world_x"]) - qx) <= radius and absi(int(d["world_y"]) - qy) <= radius:
				by_scan[iid] = true
		var by_bucket: Dictionary = {}
		for iid in _near(qx, qy, radius):
			var d: Dictionary = dungeons[iid]
			if absi(int(d["world_x"]) - qx) <= radius and absi(int(d["world_y"]) - qy) <= radius:
				by_bucket[iid] = true
		found_total += by_scan.size()
		if by_scan.size() != by_bucket.size():
			disagreements += 1
		else:
			for iid in by_scan:
				if not by_bucket.has(iid):
					disagreements += 1
					break
	ck(disagreements == 0, "400 box queries agree with the full scan, every one (%d dungeons found in total)" % found_total)
	ck(found_total > 0, "and the queries actually found things, so the comparison means something")

	print("\n--- and it is cheap where it has to be ---")
	var t0 := Time.get_ticks_usec()
	for q in range(2000):
		var qx := rng.randi_range(-2000, 2000)
		var qy := rng.randi_range(-2000, 2000)
		for iid in _near(qx, qy, 11):
			pass
	var bucket_us := float(Time.get_ticks_usec() - t0) / 2000.0
	t0 = Time.get_ticks_usec()
	for q in range(200):
		var qx := rng.randi_range(-2000, 2000)
		for iid in dungeons:
			pass
	var scan_us := float(Time.get_ticks_usec() - t0) / 200.0
	print("  one map-radius query: %.1fus bucketed, %.1fus scanning all %d" % [bucket_us, scan_us, N])
	ck(bucket_us * 20.0 < scan_us, "the bucket is more than 20x cheaper at %d dungeons" % N)
	# A move makes three of these. That product is what used to make the count unaffordable.
	print("  three per player move: %.2fms bucketed vs %.2fms scanning" % [
		bucket_us * 3.0 / 1000.0, scan_us * 3.0 / 1000.0])

	print("\n--- the server uses it, in all three places that cost a move ---")
	ck(_body(src, "_get_dungeon_at_location").find("_dungeon_tile_index.get(") >= 0,
		"'am I standing on one?' is a single dictionary lookup")
	ck(_body(src, "get_visible_dungeons").find("_dungeons_near(center_x, center_y, radius)") >= 0,
		"the map's markers come from the buckets")
	ck(_body(src, "_get_threat_zone_dungeon_at").find("_dungeons_near(x, y, THREAT_CORRIDOR_RADIUS)") >= 0,
		"the threat cone lookup does too")
	ck(_body(src, "_count_active_threats_near_post").find("_dungeons_near(post_x, post_y,") >= 0,
		"and so does the per-post threat count, which runs per spawn ATTEMPT")
	ck(_body(src, "_create_world_dungeon").find("existing_coords") < 0,
		"spawning no longer builds a set of every dungeon's coordinates (that made filling quadratic)")

	print("\n--- nothing can be added or removed behind the index's back ---")
	# The failure this guards is silent: a dungeon that exists but cannot be walked into, or a
	# `D` on the map that will not go away.
	ck(src.count("active_dungeons[instance_id] = {") == 0,
		"no path writes active_dungeons directly - they all go through _register_dungeon")
	ck(src.count("_register_dungeon(instance_id, {") == 5, "all five creators register (%d)" % src.count("_register_dungeon(instance_id, {"))
	var erases := src.count("active_dungeons.erase(")
	ck(erases == 1, "exactly one place erases a dungeon (%d), and it unindexes first" % erases)
	ck(_body(src, "_erase_dungeon_instance").find("_unindex_dungeon(instance_id)") >= 0,
		"...which it does")
	ck(src.count("_rebuild_dungeon_index()") >= 5,
		"and the wholesale paths - loading a save, a world reset, a map wipe - rebuild it")

	print("\n--- the counts the owner asked for ---")
	var consts := {}
	for line in src.split("\n"):
		var t := line.strip_edges()
		if not t.begins_with("const "):
			continue
		for name in ["MIN_WORLD_DUNGEONS", "MAX_WORLD_DUNGEONS", "MAX_ACTIVE_DUNGEONS"]:
			if t.begins_with("const %s = " % name):
				consts[name] = int(t.split("=")[1].split("#")[0].strip_edges())
	for name in ["MIN_WORLD_DUNGEONS", "MAX_WORLD_DUNGEONS", "MAX_ACTIVE_DUNGEONS"]:
		var v: int = int(consts.get(name, 0))
		print("  %s = %d" % [name, v])
		ck(v >= 3000, "%s is sized for the new density" % name)

	print("\n[DUNGEONINDEX] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
