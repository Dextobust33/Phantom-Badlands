extends SceneTree
## Which branch actually sets the price - the flat `ceiling`, or `cost_percent`?
##
## `apply_variable_cost` takes `max(flat_ceiling, naked_pool * cost_percent)`. Raising
## `cost_percent` therefore does NOTHING at any level where the flat number still wins, and
## "the change is not on the executed path" is the single most common way a balance edit
## produces byte-identical output.
##
## So before re-pricing anything: at each level, for each class, which branch is in force?
const SimScript = preload("res://tools/combat_simulator/real_combat_sim.gd")
const CM = preload("res://shared/combat_manager.gd")

const LEVELS := [1, 5, 20, 50, 100, 1000]


func _init() -> void:
	var sim = SimScript.new()
	print("\n===== WHICH BRANCH PRICES THE CARD =====")
	print("ceiling = max(flat, basis * cost_percent), basis = naked pool + half the gear bonus.")
	print("A level where FLAT wins is a level where re-pricing cost_percent changes nothing.")
	print("%-10s %5s %9s %9s %10s %10s %8s" % [
		"class", "lvl", "nakedPool", "totalPool", "flatCeil", "pctCeil", "winner"])
	var pct_wins := {}
	for row in sim.ALL_CLASSES:
		var klass := String(row[0])
		for lvl in LEVELS:
			var ch = sim.make_char(lvl, "average", klass, "Human")
			ch.in_combat = false
			ch.current_hp = ch.get_total_max_hp()
			var mon = sim.make_monster(lvl, "normal", 1.0)
			sim.combat_mgr.start_combat(0, ch, mon)
			if not sim.combat_mgr.active_combats.has(0):
				continue
			var combat = sim.combat_mgr.active_combats[0]
			var flat_sum := 0.0
			var pct_sum := 0.0
			var n := 0
			var naked := 0
			var total := 0
			for card in combat.get("combat_hand", []):
				var base := String(ch.card_base(String(card)))
				if not CM.VARIABLE_COST_TABLE.has(base):
					continue
				var e: Dictionary = CM.VARIABLE_COST_TABLE[base]
				var res := String(e.get("resource", "stamina"))
				match res:
					"mana":
						naked = ch.max_mana
						total = ch.get_total_max_mana()
					"stamina":
						naked = ch.max_stamina
						total = ch.get_total_max_stamina()
					"energy":
						naked = ch.max_energy
						total = ch.get_total_max_energy()
				var basis: float = float(naked) + maxf(0.0, float(total - naked)) * CM.GEAR_COST_SHARE
				var flat: float = float(e.get("ceiling", 0))
				var pct: float = basis * float(e.get("cost_percent", 0)) / 100.0
				flat_sum += flat
				pct_sum += pct
				n += 1
			sim.combat_mgr.end_combat(0, false, false)
			if n == 0:
				continue
			var f := flat_sum / float(n)
			var p := pct_sum / float(n)
			var winner := "percent" if p > f else "FLAT"
			if winner == "percent":
				pct_wins[lvl] = int(pct_wins.get(lvl, 0)) + 1
			print("%-10s %5d %9d %9d %10.1f %10.1f %8s" % [
				klass, lvl, naked, total, f, p, winner])

	print("\n----- how many of the nine classes are priced by PERCENT at each level -----")
	for lvl in LEVELS:
		print("  L%-6d %d of 9" % [lvl, int(pct_wins.get(lvl, 0))])
	print("\nWhere this says FLAT, cost_percent is dead weight and the lever is the flat ceiling.")
	quit(0)
