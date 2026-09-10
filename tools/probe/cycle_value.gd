extends SceneTree
## Does a card you did NOT play pay its cycle value - and from BOTH hand-dump paths?
##
## The two paths matter: playing a card and making a basic ATTACK both dump the unused hand, in
## different functions. Hooking one and not the other would pay out when you cast and stay silent
## when you attack, which is the kind of half-wiring this codebase keeps finding.
func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var ch = sim.make_char(30, "average", "Fighter", "Human")
	ch.initialize_deck_collection_if_needed()
	var cid := "dungeon_card_bulwark_of_bone"     # cycle: shield 4% max HP
	ch.combat_deck_collection[cid] = 3
	for mode in ["cast", "attack"]:
		var mon = sim.make_monster(30, "normal", 8.0)
		sim.combat_mgr.start_combat(0, ch, mon)
		var c = sim.combat_mgr.active_combats[0]
		# Two unplayed copies in hand alongside the card being used.
		c["combat_hand"] = ["power_strike", cid, cid]
		c["player_can_act"] = true
		c["forcefield_shield"] = 0
		ch.current_hp = ch.get_total_max_hp()
		ch.current_stamina = ch.get_total_max_stamina()
		var before: int = int(c.get("forcefield_shield", 0))
		var res: Dictionary
		if mode == "cast":
			res = sim.combat_mgr.process_ability_command(0, "power_strike", "10")
		else:
			res = sim.combat_mgr.process_combat_command(0, "attack")
		var after: int = int(c.get("forcefield_shield", 0))
		var said := 0
		for m in res.get("messages", []):
			if String(m).find("cycles") >= 0:
				said += 1
		print("[CYCLE] %-7s shield %d -> %d (gain %d)   cycle lines in log: %d"
			% [mode, before, after, after - before, said])
		sim.combat_mgr.active_combats.erase(0)
	# And a class card must pay NOTHING - the opt-in property.
	var mon2 = sim.make_monster(30, "normal", 8.0)
	sim.combat_mgr.start_combat(0, ch, mon2)
	var c2 = sim.combat_mgr.active_combats[0]
	c2["combat_hand"] = ["power_strike", "cleave", "shield_bash"]
	c2["player_can_act"] = true
	c2["forcefield_shield"] = 0
	ch.current_stamina = ch.get_total_max_stamina()
	sim.combat_mgr.process_ability_command(0, "power_strike", "10")
	print("[CYCLE] class-only hand gained shield: %d (must be 0)" % int(c2.get("forcefield_shield", 0)))
	quit(0)
