extends SceneTree
## The Wizard's, Sorcerer's and Oracle's Signature paths (docs/design/paths_revamp.md section 7): every node must CHANGE the
## fight or the card it names. Same method as the Warrior probes: the real combat manager, with and without the node.
## Where the effect is a random roll, the same seed is used for both runs so the roll cannot explain the difference.
const PD = preload("res://shared/path_database.gd")
var sim
var fails := 0
var _next_pid := 400
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _fresh(klass: String, ranks: Dictionary) -> Array:
	_next_pid += 1
	var pid: int = _next_pid
	var ch = sim.make_char(60, "average", klass, "Human")
	ch.initialize_deck_collection_if_needed()
	for k in ranks:
		ch.set_path_rank(String(k), int(ranks[k]))
	var mon = sim.make_monster(60, "normal", 8.0)
	mon.max_hp = 9999999
	mon.current_hp = 9999999
	sim.combat_mgr.start_combat(pid, ch, mon)
	var c = sim.combat_mgr.active_combats[pid]
	c["_probe_pid"] = pid
	c["player_can_act"] = true
	c["suppress_monster_turn"] = true
	ch.current_mana = ch.get_total_max_mana()
	return [ch, c, mon]

func _cast(t: Array, name: String, arg: String = "10") -> Dictionary:
	t[1]["combat_hand"] = [name]
	t[1]["player_can_act"] = true
	t[0].current_mana = t[0].get_total_max_mana()
	return sim.combat_mgr.process_ability_command(int(t[1]["_probe_pid"]), name, arg)

func _has_line(res: Dictionary, needle: String) -> bool:
	for m in res.get("messages", []):
		if String(m).find(needle) >= 0:
			return true
	return false

func _quote(t: Array, name: String) -> Dictionary:
	return sim.combat_mgr.preview_ability_effect(t[0], t[1], name)

func _lethal_in(note: String) -> int:
	var re := RegEx.new()
	re.compile("([0-9]+)% lethal")
	var hit = re.search(note)
	return int(hit.get_string(1)) if hit else -1

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("--- the nodes exist and chain ---")
	for cls in ["Wizard", "Sorcerer", "Sage"]:
		ck(PD.signature_nodes(cls).size() == 6 and PD.get_prereq_id("sig_%s_5" % cls) == "sig_%s_4" % cls, "%s: six Signature nodes, chained (+ its class keystone)" % cls)

	print("=== WIZARD ===")
	ck(int(_fresh("Wizard", {})[1].get("focus", 0)) == 0 and int(_fresh("Wizard", {"sig_Wizard_1": 2})[1].get("focus", 0)) == 2, "S1 Deep Focus: rank 2 starts the fight with 2 Focus")
	var r0 = _fresh("Wizard", {})
	var r1 = _fresh("Wizard", {"sig_Wizard_2": 5})
	r0[1]["focus"] = 5
	r1[1]["focus"] = 5
	# Two make_char calls are two DIFFERENT characters (random gear), so a card quote is compared on ONE character with the node toggled.
	var q0: int = int(_quote(r0, "meteor").get("value", 0))
	r0[0].set_path_rank("sig_Wizard_2", 5)
	var q1: int = int(_quote(r0, "meteor").get("value", 0))
	r0[0].set_path_rank("sig_Wizard_2", 0)
	ck(q0 > 0 and abs(float(q1) / float(q0) - (1.0 + 5.0 * 0.40) / (1.0 + 5.0 * 0.25)) < 0.03, "S2 Resonance: at 5 Focus the Meteor card quotes %d -> %d (x1.33)" % [q0, q1])
	var res_msg0: Dictionary = _cast(r0, "meteor")
	var res_msg1: Dictionary = _cast(r1, "meteor")
	ck(_has_line(res_msg0, "+125% damage") and _has_line(res_msg1, "+200% damage"), "...and the discharge line says what it did (+125% -> +200%)")
	var e5 = _fresh("Wizard", {"sig_Wizard_3": 5})
	ck(e5[0].get_path_effect_total("double_cast_pct") == 10.0, "S3 Echoing Casts: rank 5 is +10% double-cast chance (read by Magic Bolt, Blast and Meteor, which path_nodes_are_wired proves)")
	var f0 = _fresh("Wizard", {})
	var f1 = _fresh("Wizard", {"sig_Wizard_4": 1})
	_cast(f0, "haste")
	_cast(f1, "haste")
	ck(int(f0[1].get("focus", 0)) == 1 and int(f1[1].get("focus", 0)) == 2, "S4 Surging Focus: Arcane Surge builds 2 Focus instead of 1 (%d vs %d)" % [int(f0[1].get("focus", 0)), int(f1[1].get("focus", 0))])
	var t0 = _fresh("Wizard", {})
	var t1 = _fresh("Wizard", {"sig_Wizard_5": 1})
	t0[1]["focus"] = 5
	t1[1]["focus"] = 5
	var tb0: Dictionary = _cast(t0, "magic_bolt", "100")
	var tb1: Dictionary = _cast(t1, "magic_bolt", "100")
	ck(not _has_line(tb0, "DOUBLE CAST") and _has_line(tb1, "DOUBLE CAST"), "S5 Twin Bolt: a full-Focus Magic Bolt casts twice, and not without the node")
	t1[1]["focus"] = 3
	ck(not _has_line(_cast(t1, "magic_bolt", "100"), "DOUBLE CAST"), "...only at FULL Focus")
	var b0 = _fresh("Wizard", {})
	var b1 = _fresh("Wizard", {"sig_Wizard_6": 1})
	b0[1]["focus"] = 3
	b1[1]["focus"] = 3
	_cast(b0, "meteor")
	_cast(b1, "meteor")
	ck(int(b0[1].get("monster_burn", 0)) == 0 and int(b1[1].get("monster_burn", 0)) > 0 and int(b1[1].get("monster_burn_duration", 0)) == 3, "S6 Smoldering Impact: Meteor leaves a burn (%d/round for 3 rounds)" % int(b1[1].get("monster_burn", 0)))

	print("=== SORCERER ===")
	var s0 = _fresh("Sorcerer", {})
	var fx0: Dictionary = sim.combat_mgr._chaos_adjusted(s0[0], s0[0].get_class_passive().get("effects", {}))
	var s1 = _fresh("Sorcerer", {"sig_Sorcerer_1": 5, "sig_Sorcerer_2": 5})
	var fx1: Dictionary = sim.combat_mgr._chaos_adjusted(s1[0], s1[0].get_class_passive().get("effects", {}))
	ck(abs(float(fx0["double_damage_chance"]) - 0.25) < 0.001 and abs(float(fx1["double_damage_chance"]) - 0.30) < 0.001, "S1 Loaded Dice: double chance 25%% -> 30%% (%.2f -> %.2f)" % [float(fx0["double_damage_chance"]), float(fx1["double_damage_chance"])])
	ck(abs(float(fx0["backfire_chance"]) - 0.05) < 0.001 and float(fx1["backfire_chance"]) <= 0.0001, "S2 Steady Hands: backfire 5%% -> 0%% (%.2f -> %.2f)" % [float(fx0["backfire_chance"]), float(fx1["backfire_chance"])])
	var sk = _fresh("Sorcerer", {"ck_Sorcerer": 1})
	var fxk: Dictionary = sim.combat_mgr._chaos_adjusted(sk[0], sk[0].get_class_passive().get("effects", {}))
	ck(abs(float(fxk["double_damage_chance"]) - 0.35) < 0.001, "...and the class keystone (Chaos Theory, 35%%) now reaches the CARDS, not just the basic attack (%.2f)" % float(fxk["double_damage_chance"]))
	var n0 = _fresh("Sorcerer", {})
	var fq0: int = int(_quote(n0, "frost_nova").get("value", 0))
	n0[0].set_path_rank("sig_Sorcerer_3", 5)
	var fq1: int = int(_quote(n0, "frost_nova").get("value", 0))
	ck(fq0 > 0 and abs(float(fq1) / float(fq0) - 1.25) < 0.03, "S3 Fractured Frost: the Frost Nova card quotes %d -> %d (+25%%)" % [fq0, fq1])
	var bk = _fresh("Sorcerer", {"sig_Sorcerer_4": 1})
	var fxb: Dictionary = sim.combat_mgr._chaos_adjusted(bk[0], bk[0].get_class_passive().get("effects", {}))
	var banked := false
	for i in range(400):
		var r: float = sim.combat_mgr._chaos_roll(bk[1], bk[0], fxb)
		if bool(bk[1].get("_chaos_banked", false)):
			banked = true
			var nxt: float = sim.combat_mgr._chaos_roll(bk[1], bk[0], fxb)
			ck(r >= float(fxb["backfire_chance"]) + float(fxb["double_damage_chance"]) and nxt >= float(fxb["backfire_chance"]) and nxt < float(fxb["backfire_chance"]) + float(fxb["double_damage_chance"]) and not bool(bk[1].get("_chaos_banked", false)), "S4 Banked Chaos: a failed roll (%.2f) banks, and the next lands in the double zone (%.2f) and clears the bank" % [r, nxt])
			break
	ck(banked, "...a failed roll did happen to test it")
	var nb = _fresh("Sorcerer", {})
	ck(not bool(nb[1].get("_chaos_banked", false)) and sim.combat_mgr._chaos_roll(nb[1], nb[0], fx0) >= 0.0 and not bool(nb[1].get("_chaos_banked", false)), "...and without the node nothing is ever banked")
	# S5: the same seed, a backfire without the node, then the same cast with it.
	var found_seed := -1
	var hit0 := 0
	var re := RegEx.new()
	re.compile("backfires for ([0-9]+) damage")
	for k in range(1, 300):
		seed(k)
		var a = _fresh("Sorcerer", {})
		a[1]["focus"] = 0
		var ra: Dictionary = _cast(a, "blast")
		for m in ra.get("messages", []):
			var mm = re.search(String(m))
			if mm:
				found_seed = k
				hit0 = int(mm.get_string(1))
		if found_seed > 0:
			break
	if found_seed > 0:
		seed(found_seed)
		var b5 = _fresh("Sorcerer", {"sig_Sorcerer_5": 1})
		var rb: Dictionary = _cast(b5, "blast")
		var hit1 := -1
		for m in rb.get("messages", []):
			var mm2 = re.search(String(m))
			if mm2:
				hit1 = int(mm2.get_string(1))
		ck(hit0 > 0 and hit1 >= 0 and abs(hit1 - int(hit0 * 0.5)) <= 1, "S5 Controlled Backfire: the same backfire (seed %d) costs %d instead of %d" % [found_seed, hit1, hit0])
	else:
		ck(false, "S5 Controlled Backfire: no backfire found in 300 seeds to compare")
	var c0 = _fresh("Sorcerer", {})
	c0[1]["focus"] = 3
	var cq0: int = int(_quote(c0, "meteor").get("value", 0))
	c0[0].set_path_rank("sig_Sorcerer_6", 1)
	var cq1: int = int(_quote(c0, "meteor").get("value", 0))
	ck(cq0 > 0 and abs(float(cq1) / float(cq0) - 4.0 / 3.0) < 0.03, "S6 Cataclysm Unbound: at 3 Volatility the card quotes %d -> %d (counts as 4)" % [cq0, cq1])
	var c_empty = _fresh("Sorcerer", {"sig_Sorcerer_6": 1})
	ck(not bool(_cast(c_empty, "meteor").get("success", true)), "...but with nothing banked it still refuses to cast")

	print("=== ORACLE ===")
	ck(int(_fresh("Sage", {})[1].get("focus", 0)) == 0 and int(_fresh("Sage", {"sig_Sage_1": 3})[1].get("focus", 0)) == 3, "S1 Clear Sight: rank 3 starts the fight with 3 Insight")
	seed(11)
	var o0 = _fresh("Sage", {})
	seed(11)
	var o1 = _fresh("Sage", {"sig_Sage_2": 5})
	_cast(o0, "forcefield")
	_cast(o1, "forcefield")
	var sh0: int = int(o0[1].get("forcefield_shield", 0))
	var sh1: int = int(o1[1].get("forcefield_shield", 0))
	ck(sh0 > 0 and abs(float(sh1) / float(sh0) - 1.30) < 0.03, "S2 Quiet Mind: Premonition absorbs %d -> %d (+30%% at rank 5)" % [sh0, sh1])
	var l0 = _fresh("Sage", {})
	l0[1]["focus"] = 4
	var lq0: int = int(_quote(l0, "magic_bolt").get("value", 0))
	l0[0].set_path_rank("sig_Sage_3", 5)
	var lq1: int = int(_quote(l0, "magic_bolt").get("value", 0))
	ck(lq0 > 0 and abs(float(lq1) / float(lq0) - 1.8) < 0.05, "S3 Piercing Lance: at 4 Insight Mind Lance quotes %d -> %d (+80%%)" % [lq0, lq1])
	var g0 = _fresh("Sage", {})
	var g1 = _fresh("Sage", {"sig_Sage_4": 1})
	_cast(g0, "frost_nova")
	_cast(g1, "frost_nova")
	# (An Oracle also earns Foresight Insight on an unharmed round, so only the DIFFERENCE is the node's.)
	ck(int(g1[1].get("focus", 0)) == int(g0[1].get("focus", 0)) + 1, "S4 Gentle Stillness: Stillness builds one more Insight (%d vs %d)" % [int(g0[1].get("focus", 0)), int(g1[1].get("focus", 0))])
	var d_found := false
	for k in range(1, 80):
		seed(k)
		var p0 = _fresh("Sage", {})
		_cast(p0, "paralyze")
		if int(p0[1].get("monster_stunned", 0)) > 0:
			var base_stun: int = int(p0[1].get("monster_stunned", 0))
			seed(k)
			var p1 = _fresh("Sage", {"sig_Sage_5": 1})
			_cast(p1, "paralyze")
			ck(int(p1[1].get("monster_stunned", 0)) == base_stun + 1, "S5 Deep Transfix: the same stun lasts one round longer (seed %d: %d -> %d)" % [k, base_stun, int(p1[1].get("monster_stunned", 0))])
			d_found = true
			break
	ck(d_found, "...a landing Transfix was found to compare")
	var u0 = _fresh("Sage", {})
	u0[1]["focus"] = 2
	var ul0: int = _lethal_in(str(_quote(u0, "meteor").get("scales", "")))
	u0[0].set_path_rank("sig_Sage_6", 1)
	var ul1: int = _lethal_in(str(_quote(u0, "meteor").get("scales", "")))
	ck(ul0 > 0 and ul1 == ul0 + 8, "S6 Final Reading: Unmaking's lethal chance %d%% -> %d%%, and the card says so" % [ul0, ul1])
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
