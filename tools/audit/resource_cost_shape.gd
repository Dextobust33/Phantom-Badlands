extends SceneTree
## What does a card COST against the pool it draws from, and how fast does the pool refill?
##
## `engine_and_resources.gd` measured that the bar never binds: across 630 fights, nine classes,
## five levels, NOT ONE turn fell back to a basic attack, and the bar never dropped below half.
## This asks why, in the only terms a fix can be written in - cost as a SHARE of pool, and regen
## as a share of pool per turn.
##
## The suspicion on record ([[project_resource_economy_scaling]]) is that costs are flat while
## pools grow, so a cost that stung at level 1 is rounding error later. This measures that
## directly rather than restating it.
const SimScript = preload("res://tools/combat_simulator/real_combat_sim.gd")

const LEVELS := [1, 5, 20, 100, 1000]


func _pool(sim, ch, klass: String) -> int:
	return maxi(1, sim._class_max_resource(ch, klass))


func _init() -> void:
	var sim = SimScript.new()
	print("\n===== WHAT A CARD COSTS, AS A SHARE OF THE POOL IT DRAWS FROM =====")
	print("cost%% = mean cost of the class's five cards / max pool. regen%% = per-turn refill / pool.")
	print("A deck whose mean card is a small share of pool, refilled fast, cannot bind.")
	print("%-10s %5s %8s %9s %8s %8s %9s" % [
		"class", "lvl", "pool", "meanCost", "cost%", "regen/t", "regen%"])
	var avg := {}
	for row in sim.ALL_CLASSES:
		var klass := String(row[0])
		for lvl in LEVELS:
			var ch = sim.make_char(lvl, "average", klass, "Human")
			ch.current_hp = ch.get_total_max_hp()
			ch.in_combat = false
			var pool: int = _pool(sim, ch, klass)
			var mon = sim.make_monster(lvl, "normal", 1.0)
			sim.combat_mgr.start_combat(0, ch, mon)
			if not sim.combat_mgr.active_combats.has(0):
				continue
			var combat = sim.combat_mgr.active_combats[0]
			# The five cards this class actually fights with, priced by THE SAME CODE THAT WILL
			# CHARGE for them - `_build_ability_cost_info` folds in mastery, Path and class
			# passives. The first version of this probe guessed a function name
			# (`get_ability_cost`), guarded the guess with `has_method`, and printed "(no costs)"
			# for all 45 rows: a probe that measured nothing and said so quietly.
			var costinfo: Dictionary = sim.combat_mgr._build_ability_cost_info(combat)
			var total := 0.0
			var counted := 0
			for k in costinfo:
				var ci: Dictionary = costinfo[k]
				# The CEILING is what a full-strength cast costs; the floor is a chip-in.
				total += float(ci.get("ceiling", ci.get("floor", 0)))
				counted += 1

			var before: int = sim._class_max_resource(ch, klass)
			match ch.get_class_path():
				"trickster": ch.current_energy = maxi(0, int(before * 0.5))
				"mage": ch.current_mana = maxi(0, int(before * 0.5))
				_: ch.current_stamina = maxi(0, int(before * 0.5))
			var r0: int = _cur(ch)
			sim._monster_turn_if_owed(combat)
			var regen: int = maxi(0, _cur(ch) - r0)
			sim.combat_mgr.end_combat(0, false, false)
			if counted == 0:
				print("%-10s %5d %8d %9s %8s %8s %9s" % [klass, lvl, pool, "(no costs)", "-", "-", "-"])
				continue
			var mean := total / float(counted)
			print("%-10s %5d %8d %9.1f %7.1f%% %8d %8.1f%%" % [
				klass, lvl, pool, mean, 100.0 * mean / float(pool), regen,
				100.0 * float(regen) / float(pool)])
			if not avg.has(lvl):
				avg[lvl] = {"c": 0.0, "r": 0.0, "n": 0.0}
			avg[lvl]["c"] += 100.0 * mean / float(pool)
			avg[lvl]["r"] += 100.0 * float(regen) / float(pool)
			avg[lvl]["n"] += 1.0

	print("\n----- averaged across all nine classes -----")
	print("%5s %10s %10s %14s" % ["lvl", "cost%", "regen%/t", "casts to empty"])
	for lvl in LEVELS:
		if not avg.has(lvl):
			continue
		var a: Dictionary = avg[lvl]
		var n: float = maxf(1.0, float(a["n"]))
		var cpct: float = float(a["c"]) / n
		var rpct: float = float(a["r"]) / n
		# How many casts a full bar buys, net of what it regenerates between them.
		var net: float = maxf(0.01, cpct - rpct)
		print("%5d %9.1f%% %9.1f%% %14.1f" % [lvl, cpct, rpct, 100.0 / net])
	print("\n'casts to empty' is the honest number: how many casts a FULL bar buys once regen is")
	print("netted off. A fight lasting fewer turns than that can never run the player dry.")
	quit(0)


func _cur(ch) -> int:
	match ch.get_class_path():
		"trickster": return int(ch.current_energy)
		"mage": return int(ch.current_mana)
		_: return int(ch.current_stamina)
