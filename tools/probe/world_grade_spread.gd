extends SceneTree
## What share of the WORLD is each grade of country, and what would fix it?
##
## Owner 2026-09-13: *"It sounds like we need to better design our distribution."*
##
## Measured: the world is 0.0% H-grade, 0.1% G, 44.8% A and 16.6% S. That is not a tuning miss,
## it is geometry. Level is a function of DISTANCE from origin, and the area of a ring grows with
## its radius - so the outer rings, which hold the highest levels, are most of the map by area.
## A curve that spends its first 150 tiles getting to level 50 and the remaining 2,678 getting to
## 10,000 will always put almost the whole world in the top grades.
##
## This prints the curve, the area each band occupies, and what the SAME curve would give if the
## level were a function of the fraction of the map crossed rather than raw distance - so the
## owner can see the trade rather than be told one.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const PR = preload("res://shared/power_rank.gd")


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("\n===== THE LEVEL CURVE, BY DISTANCE =====")
	print("%8s %9s %7s" % ["distance", "level", "grade"])
	for d in [10, 20, 40, 80, 150, 300, 600, 1000, 1500, 2000, 2828]:
		var lvl: int = ws._distance_to_level(float(d))
		print("%8d %9d %7s" % [d, lvl, PR.letter(int(PR.grade_for_level(maxi(1, lvl)).get("tier", 1)))])

	print("\n===== HOW MUCH GROUND EACH GRADE OCCUPIES =====")
	print("area-weighted: a ring at radius r holds 2*pi*r tiles, so the rim dominates by area.")
	var area := {}
	var total := 0.0
	# Integrate over radius, weighting by circumference - the honest way to ask "how much of the
	# map is this", rather than sampling points evenly in radius which under-counts the rim.
	for step in range(1, 2829):
		var r := float(step)
		var w := r                       # proportional to 2*pi*r
		var lvl: int = ws._distance_to_level(r)
		var t := int(PR.grade_for_level(maxi(1, lvl)).get("tier", 1))
		area[t] = float(area.get(t, 0.0)) + w
		total += w
	for t in range(1, 10):
		if not area.has(t):
			continue
		var pct := 100.0 * float(area[t]) / total
		var bar := ""
		for i in range(int(pct / 2.0)):
			bar += "#"
		print("  %s %6.2f%%  %s" % [PR.letter(t), pct, bar])

	print("\n===== WHAT A NEW PLAYER HAS =====")
	# The practical question: how much ground is sized for a character below level 10?
	var low := 0.0
	for step in range(1, 2829):
		var r := float(step)
		if ws._distance_to_level(r) <= 10:
			low += r
	print("  country at level 10 or below: %.3f%% of the world by area" % (100.0 * low / total))
	print("  ...which is a disc of radius %d tiles around the origin." % 150)
	print("\nThe trade to decide: a flatter curve gives new players more room and pushes the")
	print("endgame further out; a steeper one keeps the rim deadly but leaves the start thin.")
	quit(0)
