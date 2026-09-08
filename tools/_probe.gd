extends SceneTree
var sim
func _init():
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	sim._setup()
	for klass in ["Ninja", "Fighter"]:
		var ch = sim.make_char(20, "average", klass, "Human")
		ch.initialize_deck_collection_if_needed()
		var m = sim.make_monster(20, "normal", 1.0)
		sim.combat_mgr.start_combat(0, ch, m)
		var ab = "analyze" if klass == "Ninja" else "power_strike"
		var res = sim.combat_mgr.process_ability_command(0, ab, "")
		print("--- %s / %s  success=%s error=%s" % [klass, ab, res.get("success","?"), res.get("error","")])
		for line in res.get("messages", []):
			print("    ", line)
		sim.combat_mgr.active_combats.erase(0)
	quit()
