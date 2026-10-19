extends SceneTree
## A REVEAL upgrade must (a) be offerable, (b) make the card ADVERTISE a reveal, and (c) actually
## PAY it when the card cycles unplayed. Advertising without paying is the exact defect the card
## audits exist to catch, so all three are checked together.
func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var CU = load("res://shared/card_upgrades.gd")
	var offerable := 0
	for u in CU.eligible(CU.KIND_DAMAGE, 9, []):
		if String(u.get("id", "")).begins_with("reveal_"):
			offerable += 1
	print("[REVEAL] offerable reveal upgrades: %d (want 3)" % offerable)

	var ch = sim.make_char(30, "average", "Fighter", "Human")
	ch.initialize_deck_collection_if_needed()
	# Put a REVEAL upgrade on a plain class card - the whole point is that it works there.
	ch.ability_milestone_picks["cleave"] = ["reveal_ward"]

	var mon = sim.make_monster(30, "normal", 8.0)
	sim.combat_mgr.start_combat(0, ch, mon)
	var c = sim.combat_mgr.active_combats[0]
	c["combat_hand"] = ["power_strike", "cleave", "cleave"]
	c["player_can_act"] = true
	c["forcefield_shield"] = 0
	# No monster turn: its retaliation is ABSORBED by the very shield being measured, which
	# made the first run report 22 where the face promised 20 each. Measure the payout, not the
	# payout minus an unrelated hit.
	c["suppress_monster_turn"] = true
	ch.current_hp = ch.get_total_max_hp()
	ch.current_stamina = ch.get_total_max_stamina()

	# (b) what the FACE would say
	var effects: Dictionary = sim.combat_mgr._build_ability_effect_info(c)
	var advertised := ""
	if effects.has("cleave"):
		advertised = String(effects["cleave"].get("reveal", ""))
	print("[REVEAL] card face says: '%s'" % advertised)

	# (c) what it PAYS
	var before: int = int(c.get("forcefield_shield", 0))
	sim.combat_mgr.process_ability_command(0, "power_strike", "10")
	var after: int = int(c.get("forcefield_shield", 0))
	print("[REVEAL] two unplayed Cleaves paid: %d ward (0 would mean the upgrade is dead)" % (after - before))
	quit(0)
