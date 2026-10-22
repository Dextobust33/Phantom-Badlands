extends SceneTree
## The Barbarian's and Paladin's Signature paths (docs/design/paths_revamp.md section 7): every node must CHANGE the fight
## it names. Same method as fighter_signature_fires: the real combat manager, with and without the node.
const PD = preload("res://shared/path_database.gd")
var sim
var fails := 0
var _next_pid := 200
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _fresh(klass: String, ranks: Dictionary) -> Array:
	_next_pid += 1
	var pid: int = _next_pid
	var ch = sim.make_char(60, "average", klass, "Human")
	ch.set_path_scale_override(1.0)   # the node's own numbers, not the class's value scale (PathDatabase.CLASS_SCALE)
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
	ch.current_stamina = ch.get_total_max_stamina()
	return [ch, c, mon]

func _cast(ch, c, name: String) -> Dictionary:
	c["combat_hand"] = [name]
	c["player_can_act"] = true
	ch.current_stamina = ch.get_total_max_stamina()
	return sim.combat_mgr.process_ability_command(int(c["_probe_pid"]), name, "10")

func _num_after(res: Dictionary, pattern: String) -> int:
	var re := RegEx.new()
	re.compile(pattern)
	for m in res.get("messages", []):
		var hit = re.search(String(m))
		if hit:
			return int(hit.get_string(1))
	return -999

func _has_line(res: Dictionary, needle: String) -> bool:
	for m in res.get("messages", []):
		if String(m).find(needle) >= 0:
			return true
	return false

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("--- the nodes exist and chain ---")
	for cls in ["Barbarian", "Paladin"]:
		ck(PD.signature_nodes(cls).size() == 6, "%s has six Signature nodes (+ its class keystone)" % cls)
		ck(PD.get_prereq_id("sig_%s_4" % cls) == "sig_%s_3" % cls, "%s chains S1..S6" % cls)

	print("=== BARBARIAN ===")
	print("--- S1 Thicker Skin ---")
	var b0 = _fresh("Barbarian", {})
	var b1 = _fresh("Barbarian", {"sig_Barbarian_1": 5})
	for t in [b0, b1]:
		t[0].current_hp = int(t[0].get_total_max_hp() * 0.3)
	var has0 := false
	var has1 := false
	for row in sim.combat_mgr.player_mitigation_breakdown(b0[0], b0[1]):
		if String(row.get("label", "")).find("Thicker Skin") >= 0:
			has0 = true
	var skin_pct := 0
	for row in sim.combat_mgr.player_mitigation_breakdown(b1[0], b1[1]):
		if String(row.get("label", "")).find("Thicker Skin") >= 0:
			has1 = true
			skin_pct = int(row.get("pct", 0))
	ck(not has0 and has1 and skin_pct == 8, "below half HP the breakdown names Thicker Skin (7.5%% -> %d%%)" % skin_pct)
	b1[0].current_hp = b1[0].get_total_max_hp()
	var healthy := false
	for row in sim.combat_mgr.player_mitigation_breakdown(b1[0], b1[1]):
		if String(row.get("label", "")).find("Thicker Skin") >= 0:
			healthy = true
	ck(not healthy, "...and it is gone at full health")

	print("--- S2 Fury Reserve ---")
	ck(int(_fresh("Barbarian", {})[1].get("momentum", 0)) == 0 and int(_fresh("Barbarian", {"sig_Barbarian_2": 2})[1].get("momentum", 0)) == 2, "rank 2: Rage starts at 2")

	print("--- S3 Reaver ---")
	var r0 = _fresh("Barbarian", {})
	var r1 = _fresh("Barbarian", {"sig_Barbarian_3": 5})
	for t in [r0, r1]:
		t[1]["momentum"] = 5
		t[0].current_hp = 1
	_cast(r0[0], r0[1], "devastate")
	var res_r1: Dictionary = _cast(r1[0], r1[1], "devastate")
	ck(r0[0].current_hp <= 5 and r1[0].current_hp > 100 and _has_line(res_r1, "Reaver"), "Rampage heals with the node and not without (%d vs %d)" % [r0[0].current_hp, r1[0].current_hp])

	print("--- S4 Berserk Discipline ---")
	var k0 = _fresh("Barbarian", {})
	var k1 = _fresh("Barbarian", {"sig_Barbarian_4": 1})
	var rk0: Dictionary = _cast(k0[0], k0[1], "berserk")
	var rk1: Dictionary = _cast(k1[0], k1[1], "berserk")
	var d0 := _num_after(rk0, "defense for ([0-9]+) rounds")
	var d1 := _num_after(rk1, "defense for ([0-9]+) rounds")
	var p0 := _num_after(rk0, "(-[0-9]+)% defense")
	var p1 := _num_after(rk1, "(-[0-9]+)% defense")
	ck(d1 == d0 + 1 and d0 > 0, "Berserk lasts 1 round longer (%d -> %d)" % [d0, d1])
	ck(p0 < 0 and p1 == int(float(p0) * 0.5), "...and its defense penalty is halved (%d%% -> %d%%)" % [p0, p1])

	print("--- S5 Bull Rush Breaks ---")
	var w0 = _fresh("Barbarian", {})
	var w1 = _fresh("Barbarian", {"sig_Barbarian_5": 1})
	_cast(w0[0], w0[1], "shield_bash")
	_cast(w1[0], w1[1], "shield_bash")
	ck(int(w0[1].get("monster_weakness", 0)) == 0 and int(w1[1].get("monster_weakness", 0)) == 10 and int(w1[1].get("monster_weakness_duration", 0)) >= 3, "Bull Rush saps the target (-10% attack for 3 rounds)")

	print("--- S6 Unchained ---")
	var u0 = _fresh("Barbarian", {})
	var u1 = _fresh("Barbarian", {"sig_Barbarian_6": 1})
	for t in [u0, u1]:
		t[1]["momentum"] = 5
		_cast(t[0], t[1], "devastate")
	ck(int(u0[1].get("monster_stunned", 0)) == 0 and int(u1[1].get("monster_stunned", 0)) == 1, "a full-Rage Rampage stuns with the node and not without")
	var u2 = _fresh("Barbarian", {"sig_Barbarian_6": 1})
	u2[1]["momentum"] = 3
	_cast(u2[0], u2[1], "devastate")
	ck(int(u2[1].get("monster_stunned", 0)) == 0, "...only at FULL Rage")

	print("=== PALADIN ===")
	print("--- S1 Resolute ---")
	var a0 = _fresh("Paladin", {})
	var a1 = _fresh("Paladin", {"sig_Paladin_1": 2})
	sim.combat_mgr._apply_on_taken_hit(a0[1], a0[0], {})
	sim.combat_mgr._apply_on_taken_hit(a1[1], a1[0], {})
	var cv0: int = int(a0[1].get("momentum", 0))
	var cv1: int = int(a1[1].get("momentum", 0))
	ck(cv1 == cv0 + 2, "the first blow builds 2 extra Conviction at rank 2 (%d -> %d)" % [cv0, cv1])
	sim.combat_mgr._apply_on_taken_hit(a1[1], a1[0], {})
	sim.combat_mgr._apply_on_taken_hit(a0[1], a0[0], {})
	ck(int(a1[1].get("momentum", 0)) - int(a0[1].get("momentum", 0)) == 2, "...and only the first blow (still +2 after a second)")

	print("--- S2 Bastion of Faith ---")
	var h0 = sim.make_char(60, "average", "Paladin", "Human")
	var h1 = sim.make_char(60, "average", "Paladin", "Human")
	h0.set_path_scale_override(1.0)
	h1.set_path_scale_override(1.0)
	h1.set_path_rank("sig_Paladin_2", 5)
	var hp_a: int = h0.get_total_max_hp()
	var hp_b: int = h1.get_total_max_hp()
	ck(hp_b > hp_a and abs(float(hp_b) / float(hp_a) - 1.10) < 0.02, "rank 5 is +10%% max HP (%d -> %d)" % [hp_a, hp_b])

	print("--- S3 Mercy ---")
	var m0 = _fresh("Paladin", {})
	var m1 = _fresh("Paladin", {"sig_Paladin_3": 5})
	m0[0].current_hp = 1
	m1[0].current_hp = 1
	_cast(m0[0], m0[1], "rally")
	_cast(m1[0], m1[1], "rally")
	var g0: int = m0[0].current_hp - 1
	var g1: int = m1[0].current_hp - 1
	ck(g0 > 0 and abs(float(g1) / float(g0) - 1.25) < 0.05, "Lay on Hands heals 25%% more at rank 5 (%d -> %d)" % [g0, g1])
	var q0: int = int(sim.combat_mgr.preview_ability_effect(m0[0], m0[1], "rally").get("value", 0))
	var q1: int = int(sim.combat_mgr.preview_ability_effect(m1[0], m1[1], "rally").get("value", 0))
	ck(q1 > q0, "...and the card face quotes it (%d -> %d)" % [q0, q1])

	print("--- S4 Cleansing Hands ---")
	var n0 = _fresh("Paladin", {})
	var n1 = _fresh("Paladin", {"sig_Paladin_4": 1})
	n0[0].poison_active = true
	n1[0].poison_active = true
	_cast(n0[0], n0[1], "rally")
	_cast(n1[0], n1[1], "rally")
	ck(n0[0].poison_active and not n1[0].poison_active, "Lay on Hands cleanses poison with the node and not without")

	print("--- S5 Radiant Shield ---")
	var s0 = _fresh("Paladin", {})
	var s1 = _fresh("Paladin", {"sig_Paladin_5": 1})
	s0[0].active_buffs.clear()
	s1[0].active_buffs.clear()
	_cast(s0[0], s0[1], "fortify")
	_cast(s1[0], s1[1], "fortify")
	ck(s0[0].get_buff_value("damage_reduction") == 0 and s1[0].get_buff_value("damage_reduction") == 10, "Shield of Faith also blocks 10%")
	ck(s1[0].get_buff_source("damage_reduction") == "Path - Radiant Shield", "...and names where it comes from")

	print("--- S6 Verdict ---")
	var v0 = _fresh("Paladin", {})
	var v1 = _fresh("Paladin", {"sig_Paladin_6": 1})
	for t in [v0, v1]:
		t[1]["momentum"] = 3
	var l0 := _num_after({"messages": [str(sim.combat_mgr.preview_ability_effect(v0[0], v0[1], "devastate").get("scales", ""))]}, "([0-9]+)% lethal")
	var l1 := _num_after({"messages": [str(sim.combat_mgr.preview_ability_effect(v1[0], v1[1], "devastate").get("scales", ""))]}, "([0-9]+)% lethal")
	ck(l0 > 0 and l1 == l0 + 10, "Judgement's lethal chance is 10 points higher, and the card says so (%d%% -> %d%%)" % [l0, l1])
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
