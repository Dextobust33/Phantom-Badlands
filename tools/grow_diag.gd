extends SceneTree
func _init():
	var Sim = load("res://tools/combat_simulator/real_combat_sim.gd")
	var sim = Sim.new()
	get_root().add_child(sim)
	await process_frame
	for klass in ["Fighter", "Wizard", "Grifter"]:
		var g = sim._grow_new_character(klass, "Human")
		var m = sim.make_char(1, "starter7", klass, "Human")
		var gslots := 0
		for s in ["weapon","armor","helm","shield","boots","ring","amulet"]:
			var e = g.equipped.get(s, {})
			if e is Dictionary and not e.is_empty(): gslots += 1
		var mslots := 0
		for s in ["weapon","armor","helm","shield","boots","ring","amulet"]:
			var e2 = m.equipped.get(s, {})
			if e2 is Dictionary and not e2.is_empty(): mslots += 1
		print("%-8s GROWN hp=%-5d atk=%-4d def=%-4d slots=%d deck=%d comp=%s" % [
			klass, g.get_total_max_hp(), g.get_total_attack(), g.get_total_defense(), gslots,
			g.combat_deck_collection.size() if g.combat_deck_collection else 0,
			str(g.active_companion.get("name","none"))])
		print("%-8s make_char(starter7) hp=%-5d atk=%-4d def=%-4d slots=%d deck=%d" % [
			"", m.get_total_max_hp(), m.get_total_attack(), m.get_total_defense(), mslots,
			m.combat_deck_collection.size() if m.combat_deck_collection else 0])
	var mon = sim.make_monster(1, "normal", 1.0)
	print("\nL1 normal monster: hp=%s atk/str=%s def=%s xp=%s flock=%s" % [
		str(mon.get("max_hp")), str(mon.get("strength")), str(mon.get("defense")),
		str(mon.get("experience_reward")), str(mon.get("flock_chance"))])
	quit()
