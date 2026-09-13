extends SceneTree
## How many fights does a player pick up crossing country beneath them?
##
## Owner 2026-09-13: *"We don't want players to get bombarded by low level meaningless encounters
## while they try to get where they're going."*
##
## The world reshape made journeys much longer - level 100 country moved from radius 234 to 900 -
## so a rate that was tolerable across a short crossing is not any more. This counts actual
## `check_encounter` rolls over a real walk, before and after removing the 10% floor, rather than
## reasoning about the multiplier.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

const WALK := 500
const TRIALS := 40


func _old_scale(player_level: int, area_level: int) -> float:
	var diff: int = player_level - area_level
	if diff <= 0:
		return 1.0
	return clampf(1.0 - float(diff) * 0.05, 0.1, 1.0)   # the OLD floor


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("\n===== FIGHTS PICKED UP CROSSING %d TILES =====" % WALK)
	print("counted from real check_encounter rolls along a real line of ground.")
	print("%-14s %10s %12s %12s" % ["player level", "area ~lv", "was", "now"])
	for pl in [20, 50, 100, 300]:
		# Walk outward from the origin, which is the low country a traveller crosses.
		var now_total := 0
		var was_total := 0
		var area_seen := 0
		for t in range(TRIALS):
			for step in range(WALK):
				var x := 30 + step
				var y := t * 3
				if ws.check_encounter(x, y, pl):
					now_total += 1
				# The old behaviour, recomputed on the same ground: same base rate, old scale.
				var terr := ws.get_terrain_at(x, y)
				var base: float = float(ws.get_terrain_info(terr).encounter_rate)
				var al: int = ws.get_post_anchored_level(x, y)
				area_seen = al
				if base > 0.0 and randf() < base * _old_scale(pl, al):
					was_total += 1
		print("%-14d %10d %12.1f %12.1f" % [
			pl, area_seen, float(was_total) / float(TRIALS), float(now_total) / float(TRIALS)])
	print("\nThese are fights per crossing, averaged over %d walks. The right-hand column is what" % TRIALS)
	print("a player now meets while simply getting somewhere.")
	quit(0)
