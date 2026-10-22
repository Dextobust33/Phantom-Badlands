extends SceneTree
## `pathvalue` measured the whole original Trickster Lethality branch at exactly +0 for Grifter, Ranger and Ninja. Two of its four nodes were read by the
## basic attack alone (about 1% of a deck-driven player's actions): First Blood (+30% vs a full-HP monster) and Serrated Tools (a crit leaves a bleed).
## Both now reach cards. Same method as the other path probes: one character, the node toggled.
var sim
var fails := 0
var _pid := 1100
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _fight(ch) -> Array:
	_pid += 1
	var mon = sim.make_monster(60, "normal", 1.0)
	mon.max_hp = 9999999
	mon.current_hp = 9999999
	sim.combat_mgr.start_combat(_pid, ch, mon)
	var c = sim.combat_mgr.active_combats[_pid]
	c["_probe_pid"] = _pid
	c["player_can_act"] = true
	c["suppress_monster_turn"] = true
	return [ch, c, mon]

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var ch = sim.make_char(60, "average", "Grifter", "Human")
	ch.initialize_deck_collection_if_needed()
	var t = _fight(ch)
	var q0: float = float(sim.combat_mgr.preview_ability_effect(ch, t[1], "ambush").get("value", 0))
	ch.set_path_rank("trickster_1_4", 3)
	var q1: float = float(sim.combat_mgr.preview_ability_effect(ch, t[1], "ambush").get("value", 0))
	t[2].current_hp = int(t[2].max_hp * 0.9)
	var q2: float = float(sim.combat_mgr.preview_ability_effect(ch, t[1], "ambush").get("value", 0))
	ck(q0 > 0 and abs(q1 / q0 - 1.30) < 0.03, "First Blood: a card quotes +30%% against a full-HP monster (%d -> %d)" % [int(q0), int(q1)])
	ck(abs(q2 / q0 - 1.0) < 0.01, "...and nothing once the monster is hurt (%d)" % int(q2))
	ch.set_path_rank("trickster_1_4", 0)
	# Serrated Tools: find a seed where the card crits, then compare the bleed with and without the node
	var bled := [0, 0]
	for r in [0, 3]:
		ch.set_path_rank("trickster_1_2", r)
		for sd in range(1, 60):
			var tf = _fight(ch)
			ch.current_energy = ch.get_total_max_energy()
			tf[1]["combat_hand"] = ["ambush"]
			seed(sd)
			var res = sim.combat_mgr.process_ability_command(int(tf[1]["_probe_pid"]), "ambush", "10")
			if int(tf[1].get("monster_bleed", 0)) > 0:
				bled[0 if r == 0 else 1] += 1
	ck(bled[0] == 0 and bled[1] > 5, "Serrated Tools: card crits now leave a bleed (%d of 59 casts with the node, %d without)" % [bled[1], bled[0]])
	# Crit past the cap becomes crit damage: a character AT the 75% cap still gains from +crit chance.
	var nj = sim.make_char(100, "average", "Ninja", "Human")
	nj.initialize_deck_collection_if_needed()
	var tn = _fight(nj)
	var capped: int = sim.combat_mgr.player_crit_chance(nj, tn[1], "ambush")
	var m0: float = sim.combat_mgr.ability_crit_multiplier(nj, tn[1], "ambush")
	nj.set_path_rank("trickster_1_1", 5)
	var m1: float = sim.combat_mgr.ability_crit_multiplier(nj, tn[1], "ambush")
	ck(capped == 75 and m1 > m0 and abs((m1 - m0) - 0.075) < 0.001, "Keen Eye r5 on a capped Ninja: +15 crit chance past the 75%% cap becomes +7.5 points of crit damage (x%.3f -> x%.3f)" % [m0, m1])
	# Vicious Rhythm: the first DAMAGING card, not the first card
	var gr = sim.make_char(60, "average", "Grifter", "Human")
	gr.initialize_deck_collection_if_needed()
	gr.set_path_rank("trickster_6_4", 5)
	var tg = _fight(gr)
	var base_q: float = float(sim.combat_mgr.preview_ability_effect(gr, tg[1], "ambush").get("value", 0))
	tg[1]["path_cards_cast"] = 1   # a setup card was cast first
	var after_setup: float = float(sim.combat_mgr.preview_ability_effect(gr, tg[1], "ambush").get("value", 0))
	tg[1]["path_damaging_cast"] = 1
	var after_hit: float = float(sim.combat_mgr.preview_ability_effect(gr, tg[1], "ambush").get("value", 0))
	ck(abs(after_setup - base_q) < 1.0 and after_hit < base_q * 0.8, "Vicious Rhythm: a setup card first does not spend it (%d, %d); a damaging card does (%d)" % [int(base_q), int(after_setup), int(after_hit)])
	# Flowing Font: the per-card mana regeneration
	var wz = sim.make_char(60, "average", "Wizard", "Human")
	wz.initialize_deck_collection_if_needed()
	var tw = _fight(wz)
	wz.current_mana = 0
	sim.combat_mgr._apply_gear_resource_regen(wz, [])
	var regen0: int = wz.current_mana
	wz.set_path_rank("mage_3_3", 3)
	wz.current_mana = 0
	sim.combat_mgr._apply_gear_resource_regen(wz, [])
	var regen1: int = wz.current_mana
	ck(regen0 > 0 and regen1 > regen0 and float(regen1) / float(regen0) > 1.2 and float(regen1) / float(regen0) <= 1.5, "Flowing Font r3: the per-card mana regeneration is up to 50%% stronger (%d -> %d; part of the total is not the base trickle)" % [regen0, regen1])
	# The Ranger cannot crit (Steady Hand), so its crit nodes become card damage
	var rg = sim.make_char(60, "average", "Ranger", "Human")
	rg.initialize_deck_collection_if_needed()
	var trg = _fight(rg)
	ck(not rg.crit_affects_abilities(), "a Ranger's cards never crit")
	var r0: float = float(sim.combat_mgr.preview_ability_effect(rg, trg[1], "exploit").get("value", 0))
	rg.set_path_rank("trickster_1_1", 5)
	var r1: float = float(sim.combat_mgr.preview_ability_effect(rg, trg[1], "exploit").get("value", 0))
	ck(r0 > 0 and abs(r1 / r0 - 1.06) < 0.02, "Keen Eye r5 on a Ranger: +15%% crit chance becomes +6%% card damage (%d -> %d)" % [int(r0), int(r1)])
	rg.set_path_rank("trickster_1_1", 0)
	rg.set_path_rank("trickster_6_5", 1)
	var r2: float = float(sim.combat_mgr.preview_ability_effect(rg, trg[1], "exploit").get("value", 0))
	ck(abs(r2 / r0 - 1.125) < 0.02, "Cold Blood on a Ranger: +25 crit damage becomes +12.5%% card damage (%d -> %d)" % [int(r0), int(r2)])
	rg.set_path_rank("trickster_6_5", 0)
	var gf = sim.make_char(60, "average", "Grifter", "Human")
	gf.initialize_deck_collection_if_needed()
	var tgf = _fight(gf)
	var g0: float = float(sim.combat_mgr.preview_ability_effect(gf, tgf[1], "exploit").get("value", 0))
	gf.set_path_rank("trickster_1_1", 5)
	var g1: float = float(sim.combat_mgr.preview_ability_effect(gf, tgf[1], "exploit").get("value", 0))
	ck(abs(g1 / g0 - 1.0) < 0.005, "...but a Grifter, who CAN crit, gets no damage from it (%d -> %d)" % [int(g0), int(g1)])
	rg.set_path_rank("trickster_1_2", 3)
	var bleed_seen := 0
	for sd in range(1, 30):
		var tb = _fight(rg)
		tb[1]["combo"] = 5
		rg.current_energy = rg.get_total_max_energy()
		tb[1]["combat_hand"] = ["perfect_heist"]
		seed(sd)
		sim.combat_mgr.process_ability_command(int(tb[1]["_probe_pid"]), "perfect_heist", "10")
		if int(tb[1].get("monster_bleed", 0)) > 0:
			bleed_seen += 1
	ck(bleed_seen > 20, "Serrated Tools on a Ranger: Killing Shot leaves the bleed (%d of 29 shots)" % bleed_seen)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
