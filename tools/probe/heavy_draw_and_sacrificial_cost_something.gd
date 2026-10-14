extends SceneTree
## Playtest sheet item 28: do the "slower to come back" / "once per fight" upgrades function?
## HEAVY DRAW was a FREE +25% damage: the damage code said "slower redraw handled by the deck" and
## the deck did nothing. SACRIFICIAL "spent for the rest of the fight" kept coming back as a dead
## draw that whiffed. Both now act at the reshuffle.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _state(ch, cards: Array) -> Dictionary:
	return {"character": ch, "combat_deck": [], "combat_discard": cards.duplicate(), "combat_hand": [], "combat_hand_size": 3}

func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr
	var ch = sim.make_char(30, "average", "Fighter", "Human")
	var cards := ["cleave", "power_strike", "shield_bash", "iron_skin", "devastate", "berserk"]

	print("--- Heavy Draw ---")
	ch.ability_milestone_picks["cleave"] = ["greedy"]
	var N := 400
	var heavy_first := 0
	var control_first := 0
	var conserved := true
	for i in N:
		var st := _state(ch, cards)
		cm._draw_to_hand(st)
		if st["combat_hand"].has("cleave"):
			heavy_first += 1
		if st["combat_hand"].size() + st["combat_deck"].size() + st["combat_discard"].size() != cards.size():
			conserved = false
		var st2 := _state(ch, cards)
		st2["combat_hand_size"] = 3
		var ctl_has := false
		cm._draw_to_hand(st2)
		if st2["combat_hand"].has("power_strike"):
			control_first += 1
	ck(heavy_first == 0, "a Heavy Draw card is never in the first 3 of a fresh 6-card deck (%d of %d)" % [heavy_first, N])
	ck(control_first > N * 0.35 and control_first < N * 0.65, "a plain card is (%d of %d, want ~50%%)" % [control_first, N])
	ck(conserved, "no card is lost or invented")
	var st3 := _state(ch, cards)
	st3["combat_hand_size"] = 6
	cm._draw_to_hand(st3)
	ck(st3["combat_hand"].has("cleave"), "it still comes back - a hand big enough to reach it holds it")

	print("--- Sacrificial ---")
	ch.ability_milestone_picks.erase("cleave")
	ch.ability_milestone_picks["power_strike"] = ["sacrificial"]
	var mon = sim.make_monster(30, "normal", 80.0)
	ch.in_combat = false
	cm.start_combat(0, ch, mon)
	var c = cm.active_combats[0]
	ch.current_stamina = ch.get_total_max_stamina()
	c["combat_hand"] = ["power_strike"] + (c["combat_hand"] as Array).filter(func(x): return x != "power_strike")
	var cast: Dictionary = cm.process_ability_command(0, "power_strike", "")
	ck(bool(cast.get("success", false)), "the cast went through")
	ck(bool(c.get("sacrificed_power_strike", false)), "the first cast marks the card spent")
	var dis: Array = c.get("combat_discard", [])
	var all_other: Array = []
	for k in ["combat_hand", "combat_deck"]:
		for x in c.get(k, []):
			all_other.append(x)
	# Force a reshuffle: everything into discard, deck empty.
	for x in all_other:
		dis.append(x)
	c["combat_discard"] = dis
	c["combat_deck"] = []
	c["combat_hand"] = []
	cm._draw_to_hand(c)
	var after: Array = (c["combat_hand"] as Array) + (c["combat_deck"] as Array) + (c["combat_discard"] as Array)
	ck(not after.has("power_strike"), "a spent card does not rejoin the deck at the next reshuffle")
	ck(after.size() >= 4, "and the rest of the deck is intact (%d cards)" % after.size())
	cm.end_combat(0, false, false)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
