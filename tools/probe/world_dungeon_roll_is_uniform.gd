extends SceneTree
## Owner sheet 2026-10-13, item 10: "I'm not seeing any random dungeons on the map". World dungeons
## are placed by `_roll_location_in_world`, which samples a DISC of radius 2828 (the circle around
## the +/-2000 world square) and then CLAMPS to the square - so every roll outside the square lands
## on its edge, the "reject if out of bounds" check in the caller can never fire, and the interior
## gets fewer dungeons than the count promises. Measures the real function.
const SERVER := preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var s = SERVER.new()
	s.world_system = WorldSystem.new()
	var n := 40000
	var on_edge := 0
	var within_300 := 0
	var within_800 := 0
	for i in range(n):
		var p: Vector2i = s._roll_location_in_world()
		if absi(p.x) >= 2000 or absi(p.y) >= 2000:
			on_edge += 1
		var d := sqrt(float(p.x * p.x + p.y * p.y))
		if d <= 300.0:
			within_300 += 1
		if d <= 800.0:
			within_800 += 1
	var edge_frac := float(on_edge) / n
	# What a UNIFORM spread over the 4000x4000 square would put in each disc.
	var sq := 4000.0 * 4000.0
	var exp300 := PI * 300.0 * 300.0 / sq
	var exp800 := PI * 800.0 * 800.0 / sq
	print("  rolls on the world's edge: %.1f%%" % (edge_frac * 100.0))
	print("  within 300 tiles of the origin: %.2f%% (uniform over the square would be %.2f%%)" % [100.0 * within_300 / n, 100.0 * exp300])
	print("  within 800 tiles of the origin: %.2f%% (uniform over the square would be %.2f%%)" % [100.0 * within_800 / n, 100.0 * exp800])
	ck(edge_frac < 0.01, "almost no dungeon is rolled onto the world's edge (%.1f%%)" % (edge_frac * 100.0))
	var ratio: float = (float(within_300) / n) / exp300
	ck(ratio > 0.95, "the centre gets the density a uniform spread gives it (%.2fx)" % ratio)

	print("\n--- with players online, a SHARE of dungeons appear near them (owner: weight toward players) ---")
	var a := Character.new()
	a.initialize("NearA", "Fighter", "Human")
	a.x = 700
	a.y = -400
	var b := Character.new()
	b.initialize("NearB", "Wizard", "Human")
	b.x = -1200
	b.y = 900
	var under := Character.new()
	under.initialize("Underground", "Fighter", "Human")
	under.x = 5
	under.y = 5
	under.enter_dungeon("some_instance", "goblin_caves", 3, 3)   # dungeon coords, NOT map coords
	s.characters[1] = a
	s.characters[2] = b
	s.characters[3] = under
	var near := 0
	var too_close := 0
	var at_underground := 0
	var m := 30000
	for i in range(m):
		var p: Vector2i = s._roll_location_in_world()
		for anchor in [Vector2i(700, -400), Vector2i(-1200, 900)]:
			var d := Vector2(p - anchor).length()
			if d <= float(s.PLAYER_SPAWN_RADIUS) + 1.0:
				near += 1
		if Vector2(p - Vector2i(5, 5)).length() <= 150.0:
			at_underground += 1
	var near_frac := float(near) / m
	# 40% by design, plus the sliver a uniform roll lands there by chance (two discs of r=140 in 16M tiles).
	print("  within %d tiles of a player: %.1f%% of rolls (design share %.0f%%)" % [s.PLAYER_SPAWN_RADIUS, near_frac * 100.0, s.PLAYER_SPAWN_SHARE * 100.0])
	ck(near_frac > s.PLAYER_SPAWN_SHARE * 0.9 and near_frac < s.PLAYER_SPAWN_SHARE * 1.15, "about the designed share lands near players (%.1f%%)" % (near_frac * 100.0))
	ck(near_frac < 0.5, "...and the rest of the world is still stocked uniformly")
	# Asked of the near-player roll ITSELF: a uniform roll (the other 60%) can land anywhere, including
	# by chance beside a player, so the whole stream is the wrong thing to test this against.
	var closest := 9999.0
	for i in range(m):
		var q: Vector2i = s._roll_location_near_a_player()
		for anchor in [Vector2i(700, -400), Vector2i(-1200, 900)]:
			closest = minf(closest, Vector2(q - anchor).length())
	ck(closest >= float(s.PLAYER_SPAWN_MIN_DIST) - 1.5, "a near-player roll is never closer than %d tiles to a player (closest %.1f)" % [s.PLAYER_SPAWN_MIN_DIST, closest])
	ck(at_underground < m * 0.02, "a player UNDERGROUND is not an anchor (their dungeon coordinates are not a place on the map)")
	s.characters.clear()
	s.free()
	print("\n[WORLDROLL] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
