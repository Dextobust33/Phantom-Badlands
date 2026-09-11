extends SceneTree
## Where dungeons WOULD sit if their level matched the land, and how many it takes to find one.
##
## Owner direction 2026-09-11, after finding a G2 dungeon (L7-9 monsters) standing in L15-17
## wilderness: *"Moving the dungeons sounds like the right thing to do. We also want to massively
## increase the amount of dungeons that players can find on the map. We don't want players to
## have to walk hundreds of tiles without seeing any dungeons."*
##
## This is an ANALYSIS tool, not a probe - it asserts nothing, it prints the table the decision
## needs. It reads the game's own curve and bands (`WorldSystem._distance_to_level`,
## `PowerRank.dungeon_band`, `DungeonDatabase.get_sub_tier_level_range`) rather than restating
## them, because a design table copied out of the code is the first thing to go stale.
##
##   godot --headless --path . --script res://tools/dungeon_density.gd
##   ... -- cells     also print all 81 (tier, rank) cells rather than a sample
const WorldSystemScript = preload("res://shared/world_system.gd")
const PowerRankScript = preload("res://shared/power_rank.gd")
const DungeonDatabaseScript = preload("res://shared/dungeon_database.gd")

## How wide a swathe of world a walking player inspects for dungeons. The minimap reaches +/-40
## tiles, so one step sweeps ~80 tiles of new ground; the main map alone would be ~22.
const SIGHT_WIDTH := 80.0

var ws: WorldSystem


func _init() -> void:
	ws = WorldSystemScript.new()
	get_root().add_child(ws)
	var show_all := "cells" in OS.get_cmdline_user_args()

	print("\n=== WHERE THE LAND REACHES EACH TIER'S LEVELS ===")
	print("(today every dungeon spawns in tier*30 .. tier*60, which is a different thing entirely)")
	print("grade its monsters      spawns at today   the land matches at      ring area")
	var total_area := 0.0
	var rings: Array = []
	for t in range(1, 10):
		var b: Dictionary = PowerRankScript.dungeon_band(t)
		var d0 := _distance_for_level(int(b["min"]))
		var d1 := _distance_for_level(int(b["max"]))
		var area := PI * (d1 * d1 - d0 * d0)
		total_area += area
		rings.append({"t": t, "d0": d0, "d1": d1, "area": area})
		# The letter alone - a grade is letter + RANK (G2 = a G-grade dungeon at rank 2), so
		# printing letter + tier here would read as a grade and mean something else entirely.
		print("   %s   L%5d-%-6d    %4d-%-5d       %5d-%-5d          %11.0f" % [
			PowerRankScript.letter(t), int(b["min"]), int(b["max"]),
			t * 30, t * 60, int(d0), int(d1), area])
	print("  the nine rings cover %.0f tiles. Everything today is inside r=540: %.1f%% of that." % [
		total_area, PI * 540.0 * 540.0 / total_area * 100.0])

	print("\n=== HOW MANY IT TAKES ===")
	print("A player walking sweeps ~%d tiles of new ground a step, so 'one per N tiles walked'" % int(SIGHT_WIDTH))
	print("needs one dungeon per N x %d tiles of area." % int(SIGHT_WIDTH))
	for walk in [50, 100, 200, 400]:
		print("  one per %4d tiles walked, everywhere in the world: %7d dungeons" % [
			walk, int(round(total_area / (SIGHT_WIDTH * float(walk))))])
	print("  for scale, the live cap is MAX_WORLD_DUNGEONS = 200.")

	print("\n=== AND WHY A FLAT QUOTA WILL NOT DO ===")
	print("Rank is a ninth of a tier, so a player working H1-3, then H4-6, then H7-9 needs each")
	print("(tier, rank) CELL populated. The cells are wildly different sizes:")
	print("cell    levels             ring            area      walk to find one at K=5 / K=20 / K=100")
	var cell_total := 0.0
	for t in range(1, 10):
		for r in range(1, 10):
			var sub: Dictionary = DungeonDatabaseScript.get_sub_tier_level_range(t, r)
			var lo := int(sub.get("min_level", 1))
			var hi := maxi(int(sub.get("max_level", lo)), lo + 1)
			var d0 := _distance_for_level(lo)
			var d1 := _distance_for_level(hi)
			var area := PI * (d1 * d1 - d0 * d0)
			cell_total += area
			if not show_all and not (r == 1 or r == 9):
				continue
			if not show_all and not (t == 1 or t == 2 or t == 5 or t == 9):
				continue
			print("%s%d    L%5d-%-6d   %5d-%-5d   %10.0f    %6d / %6d / %6d" % [
				PowerRankScript.letter(t), r, lo, hi, int(d0), int(d1), area,
				int(area / (SIGHT_WIDTH * 5.0)), int(area / (SIGHT_WIDTH * 20.0)),
				int(area / (SIGHT_WIDTH * 100.0))])
	print("\n  81 cells, %.0f tiles between them." % cell_total)
	print("  Near home a cell is a thin ring and even five dungeons is one every few steps.")
	print("  At the rim a cell is over a million tiles: a hundred of them is still a long walk,")
	print("  which is the argument for letting players SEEK a rank rather than stumble on it.")
	quit(0)


func _distance_for_level(level: int) -> float:
	"""The distance from origin at which the wilderness first reaches `level`. The curve is
	monotonic, so a bisection over the real function is exact enough and cannot drift from it."""
	var lo := 0.0
	var hi := 2828.0
	for _i in range(90):
		var mid := (lo + hi) * 0.5
		if ws._distance_to_level(mid) < level:
			lo = mid
		else:
			hi = mid
	return hi
