extends SceneTree
## Does the DISGUISE REVEAL make the monster's HP bar jump UP - i.e. make dealt damage look like
## it never registered? Player report v0.9.764 on an APEX Mimic.
func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var ch = sim.make_char(7, "average", "Wizard", "Human")
	ch.initialize_deck_collection_if_needed()
	var mon = sim.make_monster(8, "normal", 3.0)
	mon["name"] = "Mimic"
	mon["abilities"] = ["ambusher", "disguise", "gold_hoarder", "cunning_prey"]
	var true_max: int = int(mon.get("max_hp", 0))
	sim.combat_mgr.start_combat(0, ch, mon)
	var c = sim.combat_mgr.active_combats[0]
	print("TRUE max=%d   after disguise: %d/%d" % [true_max, int(mon.current_hp), int(mon.max_hp)])
	for rnd in range(6):
		var b_cur: int = int(mon.current_hp)
		var b_max: int = int(mon.max_hp)
		var was_revealed: bool = bool(c.get("disguise_revealed", false))
		# BASIC ATTACK - the only path that reaches the reveal.
		var res: Dictionary = sim.combat_mgr.process_combat_command(0, "attack")
		var a_cur: int = int(mon.current_hp)
		var a_max: int = int(mon.max_hp)
		var revealed_now: bool = bool(c.get("disguise_revealed", false)) and not was_revealed
		var tag := "   <<< REVEAL: bar jumped %+d" % (a_cur - b_cur) if revealed_now else ""
		print("round %d: %d/%d -> %d/%d%s" % [rnd + 1, b_cur, b_max, a_cur, a_max, tag])
		if int(mon.current_hp) <= 0 or bool(res.get("combat_ended", false)):
			print("  (ended)")
			break
	quit(0)
