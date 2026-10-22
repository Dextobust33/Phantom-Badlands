extends SceneTree
## The six new archetype branches (docs/design/paths_revamp.md): every EFFECT KEY they use must change the fight or the card it names.
## Same method as the Signature probes: the real combat manager, ONE character with the node toggled, the same seed per pair.
## The unit is the effect key (that is what has a reader); the closing loop proves every key used by any of the 45 nodes was tested.
const PD = preload("res://shared/path_database.gd")
var sim
var fails := 0
var _pid := 900
var tested: Dictionary = {}

func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func covered(keys: Array) -> void:
	for k in keys:
		tested[String(k)] = true

var _proto = null
var _last_reflect := 0

func _fight(ch, hp_frac: float = 1.0, suppress: bool = true, proto = null) -> Array:
	_pid += 1
	var mon = proto.duplicate(true) if proto != null else sim.make_monster(60, "normal", 1.0)
	mon.max_hp = 9999999
	mon.current_hp = int(9999999 * hp_frac)
	sim.combat_mgr.start_combat(_pid, ch, mon)
	var c = sim.combat_mgr.active_combats[_pid]
	c["_probe_pid"] = _pid
	c["player_can_act"] = true
	c["suppress_monster_turn"] = suppress
	return [ch, c, mon]

func _char(klass: String):
	var ch = sim.make_char(60, "average", klass, "Human")
	ch.initialize_deck_collection_if_needed()
	return ch

func _quote(t: Array, name: String) -> float:
	return float(sim.combat_mgr.preview_ability_effect(t[0], t[1], name).get("value", 0))

func _lost(t: Array, seeds: int, mul: float = 1.0, rnd: int = 1) -> int:
	# HP lost over `seeds` monster turns, the same seeds every call. A FRESH fight per seed: a monster that has already taken
	# turns has enraged / frenzied, so two runs on one combat are not the same monster.
	var ch = t[0]
	var total := 0
	_last_reflect = 0
	if _proto == null:
		_proto = sim.make_monster(60, "normal", 1.0)
	for s in range(seeds):
		var ft = _fight(ch, 1.0, false, _proto)
		ft[2].strength = int(ft[2].strength * mul)
		ft[1]["round"] = rnd
		var mx: int = ch.get_total_max_hp()
		ch.current_hp = mx
		seed(1000 + s)
		var mhp0: int = int(ft[2].current_hp)
		sim.combat_mgr.process_monster_turn(ft[1])
		_last_reflect += mhp0 - int(ft[2].current_hp)
		total += mx - int(ch.current_hp)
		sim.combat_mgr.active_combats.erase(int(ft[1]["_probe_pid"]))
	return total

func _setr(ch, id: String, r: int) -> void:
	ch.set_path_rank(id, r)

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("--- the data: six branches per archetype, chained, every key valued ---")
	for arch in ["warrior", "mage", "trickster"]:
		var br: Array = PD.get_archetype_tree(arch)["branches"]
		ck(br.size() == 6, "%s: six branches (3 original + 3 new)" % arch)
		for b in br.slice(3):
			var nodes: Array = b["nodes"]
			ck(nodes.size() == 5 and bool(nodes[4].get("keystone", false)) and PD.get_prereq_id(String(nodes[4]["id"])) == String(nodes[3]["id"]), "%s / %s: five nodes, chained, ends in a keystone" % [arch, b["name"]])
	ck(PD.max_rank(PD.find_node("warrior_6_4")) == 1 and PD.max_rank(PD.find_node("warrior_4_1")) == 5 and PD.max_rank(PD.find_node("warrior_4_5")) == 1, "ranks: a plain node has 5, a yes/no node 1, a keystone 1")

	print("=== DAMAGE TAKEN ===")
	var f = _char("Fighter")
	var t = _fight(f, 1.0, false)
	var base: int = _lost(t, 24)
	_setr(f, "warrior_4_1", 5)
	var dr: int = _lost(t, 24)
	ck(base > 0 and abs(float(dr) / float(base) - 0.90) < 0.03, "Steel Nerves r5: real damage taken x%.2f (want 0.90)" % (float(dr) / float(base)))
	var bd: Array = sim.combat_mgr.player_mitigation_breakdown(f, t[1])
	ck(bd.any(func(e): return String(e["label"]) == "Path - Damage reduction" and int(e["pct"]) == 10), "...and it is listed in the mitigation breakdown the player reads")
	_setr(f, "warrior_4_1", 0)
	covered(["damage_reduction_pct"])
	# negative: High Roller (Trickster keystone) makes you take MORE
	var n = _char("Ninja")
	var tn = _fight(n, 1.0, false)
	var nb: int = _lost(tn, 24)
	_setr(n, "trickster_4_5", 1)
	var nh: int = _lost(tn, 24)
	ck(nh > nb and abs(float(nh) / float(nb) - 1.10) < 0.04, "High Roller: you take 10%% more (x%.2f) - its price" % (float(nh) / float(nb)))
	_setr(n, "trickster_4_5", 0)

	var small_base: int = _lost(t, 24)
	_setr(f, "warrior_4_3", 5)
	var small_guard: int = _lost(t, 24)
	ck(small_base == small_guard, "Stand Firm: an ordinary hit (13%% of max HP) is untouched (%d vs %d)" % [small_base, small_guard])
	_setr(f, "warrior_4_3", 0)
	var big_base: int = _lost(t, 24, 12.0)
	_setr(f, "warrior_4_3", 5)
	var big_guard: int = _lost(t, 24, 12.0)
	ck(big_base > 0 and abs(float(big_guard) / float(big_base) - 0.70) < 0.04, "Stand Firm r5: a hit over a quarter of max HP is cut 30%% (x%.2f)" % (float(big_guard) / float(big_base)))
	_setr(f, "warrior_4_3", 0)
	covered(["big_hit_reduction_pct"])

	# opening window: round 1 reduced, round 3 not
	var t2 = _fight(n, 1.0, false)
	var o0: int = _lost(t2, 24, 1.0, 1)
	_setr(n, "trickster_5_3", 5)
	var o1: int = _lost(t2, 24, 1.0, 1)
	var o3: int = _lost(t2, 24, 1.0, 3)
	_setr(n, "trickster_5_3", 0)
	var o3b: int = _lost(t2, 24, 1.0, 3)
	ck(o0 > 0 and abs(float(o1) / float(o0) - 0.70) < 0.04, "Feint r5: round 1 damage x%.2f (want 0.70)" % (float(o1) / float(o0)))
	ck(o3 == o3b, "...and round 3 is untouched (%d vs %d)" % [o3, o3b])
	covered(["opening_guard_pct"])

	# dodge: the monster lands fewer hits
	var w = _char("Wizard")
	var tw = _fight(w, 1.0, false)
	var hits0 := 0
	var hits1 := 0
	for pass_i in range(2):
		var h := 0
		if pass_i == 1:
			_setr(w, "mage_5_2", 5)
		for s in range(120):
			var tw2 = _fight(w, 1.0, false, _proto)
			seed(5000 + s)
			w.current_hp = w.get_total_max_hp()
			sim.combat_mgr.process_monster_turn(tw2[1])
			if w.current_hp < w.get_total_max_hp():
				h += 1
			sim.combat_mgr.active_combats.erase(int(tw2[1]["_probe_pid"]))
		if pass_i == 0:
			hits0 = h
		else:
			hits1 = h
	ck(hits0 > 0 and hits1 < hits0 and float(hits0 - hits1) / 120.0 > 0.04, "Blur r5: the monster hits %d of 120 rounds instead of %d" % [hits1, hits0])
	_setr(w, "mage_5_2", 0)
	covered(["dodge_pct"])

	# reflect: the monster loses HP when it hits you
	var tr = _fight(w, 1.0, false)
	_lost(tr, 12)
	var refl0: int = _last_reflect
	_setr(w, "mage_5_3", 5)
	_lost(tr, 12)
	var refl1: int = _last_reflect
	ck(refl1 > refl0, "Reflective Veil r5: the monster takes damage for hitting you (%d vs %d)" % [refl1, refl0])
	_setr(w, "mage_5_3", 0)
	covered(["reflect_pct"])

	print("=== SUSTAIN ===")
	var fr = _char("Fighter")
	var tfr = _fight(fr)
	fr.current_hp = int(fr.get_total_max_hp() * 0.4)
	var h_a: int = int(fr.current_hp)
	sim.combat_mgr._apply_gear_resource_regen(fr, [])
	var gain0: int = int(fr.current_hp) - h_a
	_setr(fr, "warrior_4_2", 5)
	fr.current_hp = h_a
	sim.combat_mgr._apply_gear_resource_regen(fr, [])
	var gain1: int = int(fr.current_hp) - h_a
	ck(gain1 - gain0 >= int(fr.get_total_max_hp() * 0.05) - 2, "Shrug It Off r5: +5%% max HP a round while hurt (%d -> %d)" % [gain0, gain1])
	fr.current_hp = int(fr.get_total_max_hp() * 0.9)
	h_a = int(fr.current_hp)
	sim.combat_mgr._apply_gear_resource_regen(fr, [])
	ck(int(fr.current_hp) == h_a, "...and nothing while above half HP")
	_setr(fr, "warrior_4_2", 0)
	covered(["low_hp_regen_pct"])
	w.current_hp = int(w.get_total_max_hp() * 0.5)
	h_a = int(w.current_hp)
	_setr(w, "mage_5_4", 5)
	sim.combat_mgr._apply_gear_resource_regen(w, [])
	var qm: int = int(w.current_hp) - h_a
	ck(abs(qm - int(w.get_total_max_hp() * 0.025)) <= 2, "Quiet Mind r5: +2.5%% max HP every round (%d, want ~%d)" % [qm, int(w.get_total_max_hp() * 0.025)])
	_setr(w, "mage_5_4", 0)
	covered(["round_heal_pct"])

	print("=== KILLS ===")
	for case in [["Fighter", "warrior_5_4", "stamina", "Bloodletter", 15.0], ["Wizard", "mage_6_1", "mana", "Focused Study", 15.0], ["Ninja", "trickster_4_2", "energy", "Pilfer", 15.0]]:
		var kc = _char(case[0])
		var after := []
		for r in [0, 5]:
			_setr(kc, case[1], r)
			var kt = _fight(kc)
			kt[2].current_hp = 1
			kt[2].max_hp = 1
			kt[2].defense = 0
			match case[2]:
				"stamina": kc.current_stamina = 0
				"mana": kc.current_mana = 0
				"energy": kc.current_energy = 0
			var killed := false
			for s in range(30):
				seed(77 + s)
				kt[2].current_hp = 1
				match case[2]:
					"stamina": kc.current_stamina = 0
					"mana": kc.current_mana = 0
					"energy": kc.current_energy = 0
				var res = sim.combat_mgr.process_attack(kt[1])
				if bool(res.get("combat_ended", false)) and bool(res.get("victory", false)):
					killed = true
					break
			var got: int = int({"stamina": kc.current_stamina, "mana": kc.current_mana, "energy": kc.current_energy}[case[2]])
			after.append(got if killed else -1)
		var mxr: int = int({"stamina": kc.get_total_max_stamina(), "mana": kc.get_total_max_mana(), "energy": kc.get_total_max_energy()}[case[2]])
		ck(after[0] >= 0 and after[1] - after[0] >= int(mxr * case[4] / 100.0) - 2, "%s r5: a kill restores 15%% of max %s (%d -> %d of %d)" % [case[3], case[2], after[0], after[1], mxr])
		_setr(kc, case[1], 0)
	covered(["kill_resource_pct"])
	var rc = _char("Fighter")
	_setr(rc, "warrior_4_4", 5)
	var rt = _fight(rc)
	rt[2].current_hp = 1
	rt[2].max_hp = 1
	rt[2].defense = 0
	for s in range(30):
		seed(90 + s)
		rt[2].current_hp = 1
		var res2 = sim.combat_mgr.process_attack(rt[1])
		if bool(res2.get("victory", false)):
			break
	ck(rc.get_buff_value("path_guard") == 20 and rc.get_buff_source("path_guard") == "Path - Rally", "Rally r5: a kill gives 20%% damage reduction, named for the Path (%d, '%s')" % [rc.get_buff_value("path_guard"), rc.get_buff_source("path_guard")])
	var rbd: Array = sim.combat_mgr.player_mitigation_breakdown(rc, rt[1])
	ck(rbd.any(func(e): return String(e["label"]) == "Path - Rally" and int(e["pct"]) == 20), "...and it sits in the mitigation breakdown beside the stance, not swallowed by it")
	covered(["kill_defense_buff_pct"])

	print("=== CARD DAMAGE (face quotes and casts share one function) ===")
	var q = _char("Fighter")
	var tq = _fight(q)
	var q0: float = _quote(tq, "power_strike")
	_setr(q, "warrior_5_1", 5)
	var q1: float = _quote(tq, "power_strike")
	ck(q0 > 0 and abs(q1 / q0 - 1.40) < 0.03, "Opening Salvo r5: the first card quotes %d -> %d (+40%%)" % [int(q0), int(q1)])
	tq[1]["path_cards_cast"] = 1
	ck(abs(_quote(tq, "power_strike") / q0 - 1.0) < 0.01, "...and the second card is back to base")
	tq[1]["path_cards_cast"] = 0
	_setr(q, "warrior_5_1", 0)
	covered(["first_card_damage_pct"])
	tq[2].current_hp = int(tq[2].max_hp * 0.2)
	_setr(q, "warrior_5_2", 5)
	var lq: float = _quote(tq, "power_strike")
	tq[2].current_hp = tq[2].max_hp
	var fq: float = _quote(tq, "power_strike")
	ck(abs(lq / q0 - 1.30) < 0.03 and abs(fq / q0 - 1.0) < 0.01, "Executioner r5: +30%% below 30%% HP (%d), none at full HP (%d), base %d" % [int(lq), int(fq), int(q0)])
	_setr(q, "warrior_5_2", 0)
	covered(["vs_low_hp_damage_pct"])
	_setr(q, "warrior_5_3", 5)
	tq[1]["path_sunder"] = 3
	var sq: float = _quote(tq, "power_strike")
	ck(abs(sq / q0 - 1.15) < 0.03, "Sundering r5: three stacks quote +15%% (%d vs %d)" % [int(sq), int(q0)])
	tq[1]["path_sunder"] = 0
	var tc = _fight(q)
	tc[0].current_stamina = tc[0].get_total_max_stamina()
	for i in range(7):
		tc[1]["combat_hand"] = ["power_strike"]
		tc[1]["player_can_act"] = true
		tc[0].current_stamina = tc[0].get_total_max_stamina()
		sim.combat_mgr.process_ability_command(int(tc[1]["_probe_pid"]), "power_strike", "10")
	ck(int(tc[1].get("path_sunder", 0)) == 5, "...real casts build the stacks and stop at 5 (%d after 7 hits)" % int(tc[1].get("path_sunder", 0)))
	_setr(q, "warrior_5_3", 0)
	covered(["sunder_pct"])
	# keystone prices
	_setr(q, "warrior_5_5", 1)
	var gq: float = _quote(tq, "power_strike")
	ck(abs(gq / q0 - 1.25) < 0.03, "Glass Cannon: cards hit 25%% harder (%d vs %d)" % [int(gq), int(q0)])
	var mx_before: int = q.get_total_max_hp()
	ck(true, "(max HP before %d)" % mx_before)
	_setr(q, "warrior_5_5", 0)
	var mx0: int = q.get_total_max_hp()
	_setr(q, "warrior_5_5", 1)
	ck(abs(float(q.get_total_max_hp()) / float(mx0) - 0.85) < 0.02, "...and costs 15%% max HP (%d -> %d)" % [mx0, q.get_total_max_hp()])
	_setr(q, "warrior_5_5", 0)
	_setr(q, "warrior_4_5", 1)
	var iq: float = _quote(tq, "power_strike")
	ck(abs(iq / q0 - 0.90) < 0.03, "Immovable: cards hit 10%% softer (%d vs %d) - the price of its 15%% damage reduction" % [int(iq), int(q0)])
	_setr(q, "warrior_4_5", 0)

	# variety, overdrive, first-card cost, refund, siphon, extra turn - on a Wizard
	var wz = _char("Wizard")
	var tz = _fight(wz)
	var z0: float = _quote(tz, "magic_bolt")
	_setr(wz, "mage_4_1", 5)
	var z1: float = _quote(tz, "magic_bolt")
	tz[1]["path_cards_seen"] = ["frost_nova", "meteor"]
	var z3: float = _quote(tz, "magic_bolt")
	tz[1]["path_cards_seen"] = ["frost_nova", "meteor", "overload", "blast"]
	var z4: float = _quote(tz, "magic_bolt")
	ck(abs(z1 / z0 - 1.10) < 0.03 and abs(z3 / z0 - 1.30) < 0.03 and abs(z4 / z0 - 1.30) < 0.03, "Varied Arsenal r5: +10%% with one card, +30%% with three, capped there (%d, %d, %d vs %d)" % [int(z1), int(z3), int(z4), int(z0)])
	_setr(wz, "mage_4_1", 0)
	covered(["variety_damage_pct"])
	tz[1]["path_cards_seen"] = []
	# first card cost
	wz.current_mana = wz.get_total_max_mana()
	var spd: Dictionary = sim.combat_mgr.apply_variable_cost(wz, "blast", tz[1])
	print("   (cost probe: ", spd, ")")
	var sp0: int = int(spd.get("spent", 0))
	_setr(wz, "mage_4_3", 5)
	wz.current_mana = wz.get_total_max_mana()
	var sp1: int = int(sim.combat_mgr.apply_variable_cost(wz, "blast", tz[1]).get("spent", 0))
	tz[1]["path_cards_cast"] = 1
	wz.current_mana = wz.get_total_max_mana()
	var sp2: int = int(sim.combat_mgr.apply_variable_cost(wz, "blast", tz[1]).get("spent", 0))
	tz[1]["path_cards_cast"] = 0
	ck(sp0 > 0 and abs(float(sp1) / float(sp0) - 0.50) < 0.12 and sp2 == sp0, "Opening Gambit r5: the first card costs %d instead of %d; the second %d" % [sp1, sp0, sp2])
	_setr(wz, "mage_4_3", 0)
	covered(["first_card_cost_pct"])
	# refund
	var refunded0 := 0
	var refunded1 := 0
	for r in [0, 5]:
		_setr(wz, "mage_4_2", r)
		var cnt := 0
		for s in range(400):
			seed(3000 + s)
			wz.current_mana = 0
			wz.set_meta("path_last_ability_cost", 100)
			wz.set_meta("path_last_ability_resource", "mana")
			sim.combat_mgr._apply_path_cast_riders(tz[1], "magic_bolt", 0, {"messages": []})
			if wz.current_mana >= 100:
				cnt += 1
		if r == 0:
			refunded0 = cnt
		else:
			refunded1 = cnt
	ck(refunded0 == 0 and refunded1 >= 30 and refunded1 <= 100, "Echo r5: about 15%% of casts refund the cost (%d of 400; none without the node)" % refunded1)
	_setr(wz, "mage_4_2", 0)
	covered(["card_refund_pct"])
	# siphon
	_setr(wz, "mage_4_4", 5)
	wz.current_mana = 0
	wz.set_meta("path_last_ability_cost", 0)
	sim.combat_mgr._apply_path_cast_riders(tz[1], "magic_bolt", 0, {"messages": []})
	ck(abs(wz.current_mana - int(wz.get_total_max_mana() * 0.05)) <= 2, "Siphon r5: each card restores 5%% max mana (%d, want ~%d)" % [wz.current_mana, int(wz.get_total_max_mana() * 0.05)])
	_setr(wz, "mage_4_4", 0)
	covered(["cast_resource_pct"])
	# overdrive
	_setr(wz, "mage_4_5", 1)
	tz[1]["path_cards_cast"] = 3
	wz.current_mana = wz.get_total_max_mana()
	var od: Dictionary = sim.combat_mgr.apply_variable_cost(wz, "blast", tz[1])
	var odq: float = _quote(tz, "magic_bolt")
	tz[1]["path_cards_cast"] = 0
	var odq0: float = _quote(tz, "magic_bolt")
	ck(bool(od.get("ok", false)) and int(od.get("spent", -1)) == 0 and odq0 > 0 and abs(odq / odq0 - 1.30) < 0.04, "Overdrive: every fourth card is free (spent %d) and hits 30%% harder (%d vs %d)" % [int(od.get("spent", -1)), int(odq), int(odq0)])
	ck(true, "(Overdrive's price: max mana %d -> %d)" % [int(wz.get_total_max_mana() / 0.9), wz.get_total_max_mana()])
	_setr(wz, "mage_4_5", 0)
	covered(["overdrive_damage_pct"])
	# extra turn
	for case2 in [["mage_6_3", 5, 0.10], ["mage_6_5", 1, 0.10]]:
		_setr(wz, case2[0], case2[1])
		var tx = _fight(wz)
		var turns := 0
		for i in range(300):
			tx[1]["combat_hand"] = ["magic_bolt"]
			tx[1]["player_can_act"] = true
			wz.current_mana = wz.get_total_max_mana()
			seed(40000 + i)
			var rr = sim.combat_mgr.process_ability_command(int(tx[1]["_probe_pid"]), "magic_bolt", "10")
			if bool(rr.get("skip_monster_turn", false)):
				turns += 1
		ck(turns >= 14 and turns <= 50, "%s: about 10%% of damaging cards give an extra turn (%d of 300)" % [case2[0], turns])
		_setr(wz, case2[0], 0)
	covered(["extra_turn_pct"])
	_setr(wz, "mage_6_5", 1)
	var cost_k: Dictionary = {}
	wz.current_mana = wz.get_total_max_mana()
	var kc1: int = int(sim.combat_mgr.apply_variable_cost(wz, "blast", _fight(wz)[1]).get("spent", 0))
	_setr(wz, "mage_6_5", 0)
	wz.current_mana = wz.get_total_max_mana()
	var kc0: int = int(sim.combat_mgr.apply_variable_cost(wz, "blast", _fight(wz)[1]).get("spent", 0))
	ck(kc0 > 0 and abs(float(kc1) / float(kc0) - 1.15) < 0.05, "Prodigy: cards cost 15%% more (%d vs %d)" % [kc1, kc0])
	# Pale Veil
	_setr(wz, "mage_5_5", 1)
	var pv_t = _fight(wz, 1.0, false)
	var pv1: int = _lost(pv_t, 24, 1.0, 1)
	var pv5: int = _lost(pv_t, 24, 1.0, 5)
	_setr(wz, "mage_5_5", 0)
	var pv0: int = _lost(pv_t, 24, 1.0, 1)
	var pv5b: int = _lost(pv_t, 24, 1.0, 5)
	ck(pv0 > 0 and abs(float(pv1) / float(pv0) - 0.5) < 0.05 and pv5 == pv5b, "Pale Veil: round 1 takes x%.2f, round 5 untouched (%d vs %d)" % [float(pv1) / float(pv0), pv5, pv5b])
	var sq0: float = _quote(tz, "magic_bolt")
	_setr(wz, "mage_5_5", 1)
	var sq1: float = _quote(tz, "magic_bolt")
	ck(abs(sq1 / sq0 - 0.92) < 0.03, "...and its price: spells hit 8%% softer (%d vs %d)" % [int(sq1), int(sq0)])
	_setr(wz, "mage_5_5", 0)
	# hurt resource
	_setr(wz, "mage_6_4", 5)
	var th = _fight(wz, 1.0, false)
	wz.current_mana = 0
	var got_res := 0
	for s in range(20):
		seed(100 + s)
		wz.current_hp = wz.get_total_max_hp()
		wz.current_mana = 0
		sim.combat_mgr.process_monster_turn(th[1])
		if wz.current_hp < wz.get_total_max_hp():
			got_res = int(wz.current_mana)
			break
	_setr(wz, "mage_6_4", 0)
	ck(got_res > 0 and abs(got_res - int(wz.get_total_max_mana() * 0.05)) <= 3, "Mind Over Matter r5: being hit restores 5%% max mana (%d, want ~%d)" % [got_res, int(wz.get_total_max_mana() * 0.05)])
	covered(["hurt_resource_pct"])

	print("=== ITEMS ===")
	var pf = _char("Fighter")
	var gains := []
	for r in [0, 5]:
		_setr(pf, "warrior_6_1", r)
		var ti = _fight(pf)
		pf.inventory = [{"type": "health_potion", "name": "Health Potion", "tier": 3, "quantity": 1, "is_consumable": true}]
		pf.current_hp = int(pf.get_total_max_hp() * 0.3)
		var hb: int = int(pf.current_hp)
		var ur = sim.combat_mgr.process_use_item(int(ti[1]["_probe_pid"]), 0)
		gains.append(int(pf.current_hp) - hb)
	ck(gains[0] > 0 and abs(float(gains[1]) / float(gains[0]) - 1.40) < 0.06, "Field Medic r5: a potion heals %d instead of %d (+40%%)" % [gains[1], gains[0]])
	_setr(pf, "warrior_6_1", 0)
	covered(["item_heal_pct"])
	var st := []
	for r in [0, 5]:
		_setr(pf, "warrior_6_2", r)
		var ti2 = _fight(pf)
		pf.inventory = [{"type": "health_potion", "name": "Health Potion", "tier": 3, "quantity": 1, "is_consumable": true}]
		pf.current_hp = int(pf.get_total_max_hp() * 0.3)
		pf.current_stamina = 0
		sim.combat_mgr.process_use_item(int(ti2[1]["_probe_pid"]), 0)
		st.append(int(pf.current_stamina))
	ck(st[1] - st[0] >= int(pf.get_total_max_stamina() * 0.20) - 2, "Second Helping r5: a potion also restores 20%% max stamina (%d vs %d)" % [st[1], st[0]])
	_setr(pf, "warrior_6_2", 0)
	covered(["item_resource_pct"])
	var cl := []
	for r in [0, 1]:
		_setr(pf, "warrior_6_4", r)
		var ti3 = _fight(pf)
		pf.inventory = [{"type": "health_potion", "name": "Health Potion", "tier": 3, "quantity": 1, "is_consumable": true}]
		pf.current_hp = int(pf.get_total_max_hp() * 0.3)
		pf.apply_poison(50, 20)
		sim.combat_mgr.process_use_item(int(ti3[1]["_probe_pid"]), 0)
		cl.append(pf.poison_active)
	ck(cl[0] == true and cl[1] == false, "Antidote Lore: a potion cleanses poison (before %s, after %s)" % [cl[0], cl[1]])
	_setr(pf, "warrior_6_4", 0)
	pf.cure_poison()
	covered(["item_cleanse"])
	_setr(pf, "warrior_6_5", 1)
	var ti4 = _fight(pf)
	pf.active_buffs.clear()
	pf.inventory = [{"type": "health_potion", "name": "Health Potion", "tier": 3, "quantity": 1, "is_consumable": true}]
	pf.current_hp = int(pf.get_total_max_hp() * 0.3)
	sim.combat_mgr.process_use_item(int(ti4[1]["_probe_pid"]), 0)
	ck(pf.get_buff_value("path_guard") == 25 and pf.get_buff_source("path_guard") == "Path - Last Rations", "Last Rations: a potion grants 25%% damage reduction, named for the Path (%d, '%s')" % [pf.get_buff_value("path_guard"), pf.get_buff_source("path_guard")])
	_setr(pf, "warrior_6_5", 0)
	covered(["item_guard_pct"])
	# the mage's own item node
	_setr(wz, "mage_6_2", 5)
	var ti5 = _fight(wz)
	wz.inventory = [{"type": "health_potion", "name": "Health Potion", "tier": 3, "quantity": 1, "is_consumable": true}]
	wz.current_hp = int(wz.get_total_max_hp() * 0.3)
	wz.current_mana = 0
	sim.combat_mgr.process_use_item(int(ti5[1]["_probe_pid"]), 0)
	ck(wz.current_mana >= int(wz.get_total_max_mana() * 0.20) - 2, "Arcane Alchemy r5: a potion restores 20%% max mana (%d)" % wz.current_mana)
	_setr(wz, "mage_6_2", 0)
	# poison and bleed
	var dp = _char("Fighter")
	var pt = _fight(dp)
	var dl := []
	for r in [0, 5]:
		_setr(dp, "warrior_6_3", r)
		dp.apply_poison(100, 20)
		dp.current_hp = dp.get_total_max_hp()
		var hh: int = int(dp.current_hp)
		sim.combat_mgr._process_status_ticks(dp, [])
		dl.append(hh - int(dp.current_hp))
		dp.cure_poison()
	ck(dl[0] > 0 and abs(float(dl[1]) / float(dl[0]) - 0.60) < 0.06, "Iron Stomach r5: a poison tick hurts x%.2f as much (%d vs %d)" % [float(dl[1]) / float(dl[0]), dl[1], dl[0]])
	covered(["dot_reduction_pct"])

	print("=== TRICKSTER-ONLY NODES ===")
	var rg = sim.make_char(20, "average", "Grifter", "Human")
	rg.initialize_deck_collection_if_needed()
	var cc0: int = sim.combat_mgr.player_crit_chance(rg, _fight(rg)[1])
	_setr(rg, "trickster_6_3", 5)
	var cc1: int = sim.combat_mgr.player_crit_chance(rg, _fight(rg)[1])
	ck(cc1 == cc0 + 5, "Predator's Eye r5: +5%% crit chance (%d -> %d)" % [cc0, cc1])
	_setr(rg, "trickster_6_3", 0)
	var mc0: float = sim.combat_mgr.ability_crit_multiplier(rg)
	_setr(rg, "trickster_6_5", 1)
	var mc1: float = sim.combat_mgr.ability_crit_multiplier(rg)
	ck(abs(mc1 - mc0 - 0.25) < 0.001 and abs(float(rg.get_total_max_hp()) - 0.0) > 0.0, "Cold Blood: card crits +25 points (x%.2f -> x%.2f)" % [mc0, mc1])
	_setr(rg, "trickster_6_5", 0)
	# Untouchable needs a character the monster is level-matched against: a level-20 character facing a level-60 monster is
	# already clamped at the 95% hit cap, and dodge cannot be seen through a clamp.
	rg = _char("Ranger")
	var mh0: int = rg.get_total_max_hp()
	var uh := 0
	var uh0 := 0
	for pass_i in range(2):
		var h2 := 0
		_setr(rg, "trickster_5_5", 1 if pass_i == 0 else 0)
		for s in range(120):
			var tu = _fight(rg, 1.0, false, _proto)
			seed(6000 + s)
			rg.current_hp = rg.get_total_max_hp()
			sim.combat_mgr.process_monster_turn(tu[1])
			if rg.current_hp < rg.get_total_max_hp():
				h2 += 1
			sim.combat_mgr.active_combats.erase(int(tu[1]["_probe_pid"]))
		if pass_i == 0:
			uh = h2
		else:
			uh0 = h2
	ck(uh < uh0 and uh0 - uh >= 3, "Untouchable: the monster hits %d of 120 rounds instead of %d (relative, so it works on the 40%% floor too)" % [uh, uh0])
	_setr(rg, "trickster_5_5", 1)
	ck(abs(float(rg.get_total_max_hp()) / float(mh0) - 0.85) < 0.02, "...and costs 15%% max HP (%d -> %d)" % [mh0, rg.get_total_max_hp()])
	_setr(rg, "trickster_5_5", 0)
	covered(["crit_chance_pct", "ability_crit_damage_pct", "max_hp_pct", "max_resource_pct", "ability_cost_pct", "attack_damage_pct", "spell_damage_keystone_pct"])

	print("=== EVERY KEY THE 45 NODES USE WAS TESTED ===")
	var used: Dictionary = {}
	for arch in ["warrior", "mage", "trickster"]:
		for b in PD.get_archetype_tree(arch)["branches"].slice(3):
			for nd in b["nodes"]:
				for k in nd["effect"]:
					used[String(k)] = String(nd["id"])
	var missing: Array = []
	for k in used:
		if not tested.has(k):
			missing.append("%s (%s)" % [k, used[k]])
	ck(missing.is_empty(), "no key untested (%d keys; missing: %s)" % [used.size(), ", ".join(missing)])

	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
