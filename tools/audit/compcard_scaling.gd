extends SceneTree
## Does a BETTER companion give a better card? That is the whole point of it being a companion's
## card, and until 2026-09-09 it was not true: the damage came from the player's weapon arm, so a
## fresh hatchling and a fused apex produced an identical hit.
func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var ch = sim.make_char(40, "average", "Wizard", "Human")
	ch.initialize_deck_collection_if_needed()
	var cid := "companion_card_orc"          # 'strike' kind - pure damage, nothing conditional
	ch.combat_deck_collection[cid] = 3
	print("%-28s %s" % ["companion", "card damage"])
	for spec in [{"t": 1, "s": 1, "atk": 0, "label": "T1 sub1, no attack profile"},
			{"t": 1, "s": 5, "atk": 0, "label": "T1 sub5"},
			{"t": 5, "s": 1, "atk": 0, "label": "T5 sub1"},
			{"t": 5, "s": 9, "atk": 0, "label": "T5 sub9 (fusion apex)"},
			{"t": 5, "s": 9, "atk": 5, "label": "T5 sub9 + attack profile 5"}]:
		ch.active_companion = {"monster_type": "Orc", "name": "Probe", "tier": int(spec["t"]),
			"sub_tier": int(spec["s"]), "level": 20, "bonuses": {"attack": int(spec["atk"])}}
		var total := 0
		var n := 0
		for i in range(10):
			seed(777 + i)
			var mon = sim.make_monster(40, "normal", 8.0)
			sim.combat_mgr.start_combat(0, ch, mon)
			var c = sim.combat_mgr.active_combats[0]
			c["combat_hand"] = [cid]
			c["player_can_act"] = true
			ch.current_hp = ch.get_total_max_hp()
			ch.current_mana = ch.get_total_max_mana()
			var hp0: int = int(mon.get("current_hp", 0))
			var res: Dictionary = sim.combat_mgr.process_ability_command(0, cid, "10")
			if bool(res.get("success", false)):
				total += maxi(0, hp0 - int(mon.get("current_hp", 0)))
				n += 1
			sim.combat_mgr.active_combats.erase(0)
		print("%-28s %d" % [String(spec["label"]), int(total / maxi(1, n))])
	quit(0)
