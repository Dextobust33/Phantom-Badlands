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
	s.free()
	print("\n[WORLDROLL] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
