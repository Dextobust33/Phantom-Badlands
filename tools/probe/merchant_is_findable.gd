extends SceneTree
## ⛑ CAN A PLAYER ACTUALLY MEET A MERCHANT?
##
## Owner 2026-09-19: *"Can you confirm Merchants are actually doing what they are supposed to?
## I didn't see any last time I was on the live server."*
##
## They were doing their JOB - the live log is full of them hauling stock between posts - and they
## were invisible while doing it. `_refresh_merchant_cache` dropped any merchant resting at a post
## with a bare `continue`, so for that whole stretch it did not draw, `is_merchant_at` was false
## and `get_merchant_at` returned nothing. A merchant rests 16-60% of its life depending on road
## length, and posts are exactly where players stand, so standing at one you met a merchant **0%
## of the time**.
##
## ⛑ THE TEST IS THAT IT IS FINDABLE, NOT THAT THE FUNCTION RETURNS SOMETHING. The old code also
## "worked" - it returned an empty cache perfectly reliably. So this asserts the three things a
## player needs: the merchant is ON the map, it is NOT painted over the post's own art, and it can
## be interacted with at the tile where it is drawn.
##
## ⛑ NO WORLD GENERATION. The road graph needs a generated world, and `compute_merchant_circuits`
## returns nothing without one - which is why the merchant speed constant shipped with a comment
## saying it could not be measured headless. A circuit is injected directly instead, with SHORT
## legs so the rest phase dominates the cycle (300s rest against 8s of travel = 97% resting), which
## is what makes the resting case the one under test rather than a coin flip.
##
## Run:
##   godot --headless --path . --script res://tools/probe/merchant_is_findable.gd

const WorldScript := preload("res://shared/world_system.gd")

const POST_A := Vector2i(0, 0)
const POST_B := Vector2i(6, 0)
const MERCHANTS := 12

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var ws = WorldScript.new()

	# A two-post circuit with short legs, so the merchant is resting almost all the time.
	var road_ab: Array = [Vector2i(1, 0), Vector2i(2, 0)]
	var road_ba: Array = [Vector2i(5, 0), Vector2i(4, 0)]
	ws._path_post_positions = {"post_a": POST_A, "post_b": POST_B}
	for i in range(MERCHANTS):
		ws._merchant_circuits[i] = ["post_a", "post_b"]
		ws._merchant_route_waypoints[i] = [road_ab, road_ba]
		ws._merchant_total_waypoints[i] = road_ab.size() + road_ba.size()

	ws._merchant_cache.clear()
	ws._merchant_cache_time = 0.0
	ws._refresh_merchant_cache()

	print("")
	print("===== 1. A RESTING MERCHANT IS STILL ON THE MAP =====")
	print("  %d merchants injected; %d tile(s) hold one" % [MERCHANTS, ws._merchant_cache.size()])
	if ws._merchant_cache.is_empty():
		_fail("the cache is EMPTY - resting merchants are still being dropped, so nobody can meet one")
	else:
		var shown := 0
		for k in ws._merchant_cache.keys():
			shown += (ws._merchant_cache[k] as Array).size()
		_ok("%d of %d merchants are findable" % [shown, MERCHANTS])
		if shown < MERCHANTS:
			_fail("%d merchant(s) are on no tile at all" % (MERCHANTS - shown))

	print("")
	print("===== 2. IT IS NOT PAINTED OVER THE POST'S OWN ART =====")
	# The post centre is where the station sprite sits. A wagon drawn there hides the building.
	for centre in [POST_A, POST_B]:
		var ckey := "%d,%d" % [centre.x, centre.y]
		if ws._merchant_cache.has(ckey):
			_fail("a merchant is drawn ON the post centre %s - it would cover the station art" % str(centre))
		else:
			_ok("nothing is drawn on the post centre %s" % str(centre))

	print("")
	print("===== 3. IT CAN BE INTERACTED WITH WHERE IT IS DRAWN =====")
	# `is_merchant_at` / `get_merchant_at` are what the move handler and the location panel ask.
	var checked := 0
	for k in ws._merchant_cache.keys():
		var parts: PackedStringArray = String(k).split(",")
		var x := int(parts[0])
		var y := int(parts[1])
		checked += 1
		if not ws.is_merchant_at(x, y):
			_fail("is_merchant_at(%d,%d) is false at a tile the cache says holds one" % [x, y])
			continue
		var info: Dictionary = ws.get_merchant_at(x, y)
		if info.is_empty():
			_fail("get_merchant_at(%d,%d) returns nothing - it can be seen but not used" % [x, y])
		elif String(info.get("name", "")) == "":
			_fail("the merchant at (%d,%d) has no name" % [x, y])
	if checked > 0 and _fails.is_empty():
		_ok("every occupied tile answers is_merchant_at and returns a named merchant")

	print("")
	print("===== 4. IT IS PARKED ON ITS OWN ROAD =====")
	# Not just "somewhere else" - it must be a tile of the route, or it is standing in a field.
	var road: Dictionary = {}
	for wp in road_ab + road_ba:
		road["%d,%d" % [wp.x, wp.y]] = true
	for k in ws._merchant_cache.keys():
		if not road.has(String(k)):
			_fail("a merchant is parked at %s, which is not on its route" % String(k))
	if _fails.is_empty():
		_ok("every parked merchant is on a road tile of its own circuit")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a resting merchant is drawn on the road outside its post, off the station")
	print("       art, and can be traded with where it stands.")
	quit()
