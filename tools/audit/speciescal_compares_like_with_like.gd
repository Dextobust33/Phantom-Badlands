extends SceneTree
## Do speciescal's two samplers model the SAME PLAYER, on the same monsters?
##
## Isolation matters here and the first re-run got it wrong: comparing the mix against ONE species
## folds in the real difference between that species and the mix, which is exactly the quantity
## speciescal exists to measure. So both sides fight the SAME real spawn mix, and the only thing
## that differs is the player model each sampler uses.
const SimScript := preload("res://tools/combat_simulator/real_combat_sim.gd")

## The species sampler's player model, run against the ordinary spawn mix.
func _species_model_on_mix(sim, lvl: int, reps: int) -> float:
	var wins := 0
	var n := 0
	for klass_row in sim.ALL_CLASSES:
		var klass := String(klass_row[0])
		for i in range(reps):
			var ch = sim.make_char(lvl, "average", klass)
			var mon = sim.make_monster(lvl, "normal", 1.0)
			ch.in_combat = false
			var php0: int = ch.get_total_max_hp()
			sim.combat_mgr.start_combat(0, ch, mon)
			if not sim.combat_mgr.active_combats.has(0):
				continue
			var combat = sim.combat_mgr.active_combats[0]
			var flee_aware: bool = randf() < sim._flee_rate
			var fled := false
			var t := 0
			while t < 300:
				if ch.current_hp <= 0 or int(mon.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
					break
				t += 1
				if combat.get("player_can_act", true):
					match ch.get_class_path():
						"trickster": sim._player_act_trickster(combat, ch)
						"mage": sim._player_act_mage(combat, ch)
						_: sim._player_act(combat, ch)
				if int(mon.get("current_hp", 0)) <= 0:
					break
				if flee_aware and not fled and float(ch.current_hp) / float(maxi(1, php0)) < sim.RUN_FIGHT_FLEE_AT:
					if bool(sim.combat_mgr.process_flee(combat).get("fled", false)):
						fled = true
						break
				sim._monster_turn_if_owed(combat)
			if int(mon.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
				wins += 1
			n += 1
			sim.combat_mgr.end_combat(0, false, false)
	return 100.0 * float(wins) / maxf(1.0, float(n))


func _init() -> void:
	var sim = SimScript.new()
	print("")
	print("SAME MONSTERS, SAME LEVEL. Only the sampler's player model differs.")
	print("  %-7s %14s %14s %8s" % ["level", "MIX sampler", "SPECIES model", "gap"])
	var worst := 0.0
	for lvl in [5, 10, 50]:
		var mix: Dictionary = sim._fight_stats_at(lvl, 90)
		var a: float = 100.0 * float(mix.get("win", 0.0))
		var b: float = _species_model_on_mix(sim, lvl, 10)
		worst = maxf(worst, absf(b - a))
		print("  L%-6d %13.0f%% %13.0f%% %+7.0fpp" % [lvl, a, b, b - a])
	print("")
	print("  worst gap %.0fpp. Before the fix this was +12 to +24pp - three classes chosen for" % worst)
	print("  strength, and no retreat, against a mix of nine that flees. That bias is why EVERY")
	print("  species correction was a strengthening and 68 of 136 pinned at the x2.50 clamp.")
	print("")
	quit()
