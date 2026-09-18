extends SceneTree
## ⛑ DOES THE WARDEN WALK A NEW PLAYER THROUGH A HOTZONE?
##
## Owner 2026-09-18: *"If a hotzone is near the starter dungeon warden hollis has a rough time
## getting to it as he doesn't go around hotzones."*
##
## ⚑ A HOTZONE DOES NOT BLOCK MOVEMENT, which is why this was invisible to every existing check.
## `_escort_path_search` asks `world_system.move_player` whether each neighbour can be entered —
## deliberately, so there is only ONE authority on what blocks a step — and that rule says yes to
## dangerous ground, because walking into danger is allowed. A shortest-path search therefore takes
## the straight line through it, on the guided first walk of a permadeath game, with a level-one
## character who has no gear.
##
## ⛑ THIS RUNS THE REAL SEARCH. `_escort_path_search` is a method on `server.gd`; the probe builds
## the object without adding it to the tree (so nothing listens on a port) and hands it a real
## `WorldSystem`, then walks routes across ground that genuinely contains hotzones.
##
## Run:
##   godot --headless --path . --script res://tools/probe/escort_walks_around_danger.gd

const WorldSystemScript := preload("res://shared/world_system.gd")
const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var ws = WorldSystemScript.new()
	var srv = load("res://server/server.gd").new()
	srv.world_system = ws

	print("")
	print("===== 1. IS THERE DANGER NEAR SPAWN AT ALL? =====")
	# ⛑ Ask the world, do not assume. A probe whose scenario contains no hotzone would pass
	# whatever the pathfinder did - the silent-no-op shape this project keeps finding.
	var clusters: Array = ws._collect_hotspot_clusters(-60, 60, -60, 60)
	print("  hotzone clusters within 60 tiles of origin: %d" % clusters.size())
	if clusters.is_empty():
		_fail("no hotzones near spawn - this probe cannot test what it exists to test")
		_finish()
		return
	_ok("there is dangerous ground to route around")

	print("")
	print("===== 2. ROUTES THAT USED TO CROSS IT =====")
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Fighter", "Human")
	var crossed_before := 0
	var crossed_after := 0
	var routed := 0
	var no_route := 0
	var longer_total := 0
	var tried := 0
	# Goals spread around the starter ring, at the 25-40 tiles a starter dungeon really sits at.
	for ang in range(0, 360, 20):
		for reach in [26, 34]:
			var gx: int = int(round(cos(deg_to_rad(float(ang))) * float(reach)))
			var gy: int = int(round(sin(deg_to_rad(float(ang))) * float(reach)))
			ch.x = 0
			ch.y = 0
			var plain: Array = srv._escort_path_search(ch, gx, gy, false, 16, false, false)
			if plain.is_empty():
				continue
			tried += 1
			var hot_on_plain := 0
			for t in plain:
				if ws._is_hotspot_in_clusters(int(t.x), int(t.y), clusters):
					hot_on_plain += 1
			if hot_on_plain == 0:
				continue        # this route was never in danger; nothing to prove here
			crossed_before += 1
			var safe: Array = srv._escort_path(ch, gx, gy, false, false)
			if safe.is_empty():
				no_route += 1
				continue
			var hot_on_safe := 0
			for t in safe:
				if ws._is_hotspot_in_clusters(int(t.x), int(t.y), clusters):
					hot_on_safe += 1
			if hot_on_safe > 0:
				crossed_after += 1
			else:
				routed += 1
				longer_total += safe.size() - plain.size()
	print("  %d goals with a route; %d of them used to cross a hotzone" % [tried, crossed_before])
	print("  now routed around it ....... %d" % routed)
	print("  still crossing ............. %d  (goal or start stands inside one)" % crossed_after)
	print("  no route at all ............ %d" % no_route)
	if crossed_before == 0:
		_fail("no sampled route crossed a hotzone - the sample proves nothing")
	elif routed == 0:
		_fail("not one route was diverted; the avoidance is not running")
	else:
		_ok("%d of %d dangerous routes now go around" % [routed, crossed_before])
		print("  average detour: %+.1f tiles" % (float(longer_total) / float(maxi(1, routed))))
	if no_route > 0:
		_fail("%d goal(s) became unreachable - the escort would give up" % no_route)
	else:
		_ok("no goal lost its route; avoidance is a preference, never a wall")

	print("")
	print("===== 3. A GOAL INSIDE A HOTZONE IS STILL REACHED =====")
	# ⛑ THE FAILURE MODE OF A NAIVE FIX. A dungeon that happens to sit in a hotzone must still be
	# walked to, or the escort stalls forever on the one case the player most needs leading through.
	var inside: Vector2i = Vector2i(int(clusters[0]["x"]), int(clusters[0]["y"]))
	ch.x = 0
	ch.y = 0
	var to_danger: Array = srv._escort_path(ch, inside.x, inside.y, false, false)
	print("  goal (%d,%d) is inside a hotzone: path of %d step(s)" % [
		inside.x, inside.y, to_danger.size()])
	if to_danger.is_empty():
		_fail("the escort refuses to walk to a dungeon that stands in a hotzone")
	else:
		_ok("he still takes you there")

	_finish()


func _finish() -> void:
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the escort prefers ground that is not a hotzone, never loses a route to")
	print("       that preference, and still leads you into one when that is where you are going.")
	quit()
