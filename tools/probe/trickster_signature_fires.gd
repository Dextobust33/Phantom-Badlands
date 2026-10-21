extends SceneTree
## The Grifter's, Ranger's and Ninja's Signature paths (docs/design/paths_revamp.md section 7): every node must CHANGE the fight or
## the card it names. Same method as the other signature probes: the real combat manager, with and without the node; random rolls
## on the same seed; card quotes compared on ONE character with the node toggled (two make_char calls are two different characters).
const PD = preload("res://shared/path_database.gd")
var sim
var fails := 0
var _next_pid := 600
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
	ch.current_energy = ch.get_total_max_energy()
	return [ch, c, mon]

func _cast(t: Array, name: String) -> Dictionary:
	t[1]["combat_hand"] = [name]
	t[1]["player_can_act"] = true
	t[0].current_energy = t[0].get_total_max_energy()
	return sim.combat_mgr.process_ability_command(int(t[1]["_probe_pid"]), name, "10")

func _quote(t: Array, name: String) -> int:
	return int(sim.combat_mgr.preview_ability_effect(t[0], t[1], name).get("value", 0))

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("--- the nodes exist and chain ---")
	for cls in ["Grifter", "Ranger", "Ninja"]:
		ck(PD.signature_nodes(cls).size() == 6 and PD.get_prereq_id("sig_%s_5" % cls) == "sig_%s_4" % cls, "%s: six Signature nodes, chained (+ its class keystone)" % cls)

	print("=== GRIFTER ===")
	ck(int(_fresh("Grifter", {})[1].get("combo", 0)) == 0 and int(_fresh("Grifter", {"sig_Grifter_1": 3})[1].get("combo", 0)) == 3, "S1 Loaded Odds: rank 3 starts the fight with 3 Read")
	var d0 = _fresh("Grifter", {})
	var dq0: int = _quote(d0, "ambush")
	d0[0].set_path_rank("sig_Grifter_2", 5)
	var dq1: int = _quote(d0, "ambush")
	ck(dq0 > 0 and abs(float(dq1) / float(dq0) - 1.20) < 0.03, "S2 Dirty Tricks: Sucker Punch quotes %d -> %d (+20%% at rank 5)" % [dq0, dq1])
	var h0 = _fresh("Grifter", {})
	h0[1]["combo"] = 4
	var hq0: int = int(sim.combat_mgr._finisher_value(h0[0], h0[1]))
	h0[0].set_path_rank("sig_Grifter_3", 5)
	var hq1: int = int(sim.combat_mgr._finisher_value(h0[0], h0[1]))
	var n_stacks: int = int(sim.combat_mgr._finisher_stacks(h0[1]))
	ck(hq0 > 0 and abs(float(hq1) / float(hq0) - (1.0 + float(n_stacks) * 0.10)) < 0.03, "S3 Cash Out: the Double Cross card quotes %d -> %d (+10%% per Read spent, %d Read)" % [hq0, hq1, n_stacks])
	# Same seed, one cast at a time: two fights built first and cast after do not share a random stream.
	seed(21)
	var x0 = _fresh("Grifter", {})
	x0[1]["combo"] = 4
	_cast(x0, "perfect_heist")
	seed(21)
	var x1 = _fresh("Grifter", {"sig_Grifter_3": 5})
	x1[1]["combo"] = 4
	_cast(x1, "perfect_heist")
	var dmg0: int = 9999999 - int(x0[2].current_hp)
	var dmg1: int = 9999999 - int(x1[2].current_hp)
	ck(dmg0 > 0 and abs(float(dmg1) / float(dmg0) - (1.0 + float(n_stacks) * 0.10)) < 0.06, "...and the real Double Cross hits that much harder (%d -> %d)" % [dmg0, dmg1])
	seed(31)
	var y0 = _fresh("Grifter", {})
	_cast(y0, "distract")
	seed(31)
	var y1 = _fresh("Grifter", {"sig_Grifter_4": 1})
	_cast(y1, "distract")
	ck(int(y1[1].get("combo", 0)) == int(y0[1].get("combo", 0)) + 1, "S4 Hot Hand: Distract builds one more Read (%d vs %d)" % [int(y0[1].get("combo", 0)), int(y1[1].get("combo", 0))])
	var z0 = _fresh("Grifter", {})
	var z1 = _fresh("Grifter", {"sig_Grifter_5": 1})
	z0[1]["monster_sabotaged"] = 48
	z1[1]["monster_sabotaged"] = 48
	_cast(z0, "sabotage")
	_cast(z1, "sabotage")
	ck(int(z0[1].get("monster_sabotaged", 0)) == 50 and int(z1[1].get("monster_sabotaged", 0)) > 50, "S5 Deep Cuts: Sabotage passes the 50%% cap (%d vs %d)" % [int(z0[1].get("monster_sabotaged", 0)), int(z1[1].get("monster_sabotaged", 0))])
	var k0 = _fresh("Grifter", {})
	var k1 = _fresh("Grifter", {"sig_Grifter_6": 1})
	k0[1]["combo"] = 5
	k1[1]["combo"] = 5
	_cast(k0, "perfect_heist")
	_cast(k1, "perfect_heist")
	ck(int(k0[1].get("combo", 9)) == 0 and int(k1[1].get("combo", 9)) == 2, "S6 House Edge: Double Cross leaves 2 Read (%d vs %d)" % [int(k0[1].get("combo", 9)), int(k1[1].get("combo", 9))])

	print("=== RANGER ===")
	ck(int(_fresh("Ranger", {})[1].get("combo", 0)) == 0 and int(_fresh("Ranger", {"sig_Ranger_1": 2})[1].get("combo", 0)) == 2, "S1 Steady Aim: rank 2 starts the fight with 2 Aim")
	var e0 = _fresh("Ranger", {})
	var eq0: int = _quote(e0, "exploit")
	e0[0].set_path_rank("sig_Ranger_2", 5)
	var eq1: int = _quote(e0, "exploit")
	ck(eq0 > 0 and abs(float(eq1) / float(eq0) - 1.20) < 0.03, "S2 Hunter's Reach: Weak Point quotes %d -> %d (+20%% at rank 5)" % [eq0, eq1])
	var b0 = _fresh("Ranger", {})
	b0[1]["combo"] = 3
	var bq0: int = int(sim.combat_mgr._finisher_value(b0[0], b0[1]))
	b0[0].set_path_rank("sig_Ranger_3", 5)
	var bq1: int = int(sim.combat_mgr._finisher_value(b0[0], b0[1]))
	var bn: int = int(sim.combat_mgr._finisher_stacks(b0[1]))
	ck(bq0 > 0 and abs(float(bq1) / float(bq0) - (1.0 + float(bn) * 0.15)) < 0.03, "S3 Bowyer: Killing Shot quotes %d -> %d (+15%% per Aim spent, %d Aim)" % [bq0, bq1, bn])
	var t0 = _fresh("Ranger", {})
	var t1 = _fresh("Ranger", {"sig_Ranger_4": 1})
	_cast(t0, "analyze")
	_cast(t1, "analyze")
	ck(int(t0[1].get("analyze_bonus", 0)) > 0 and int(t1[1].get("analyze_bonus", 0)) == int(t0[1].get("analyze_bonus", 0)) + 10, "S4 Eagle Eye: Track's damage bonus is 10 points stronger (%d vs %d)" % [int(t0[1].get("analyze_bonus", 0)), int(t1[1].get("analyze_bonus", 0))])
	var s0 = _fresh("Ranger", {})
	var s1 = _fresh("Ranger", {"sig_Ranger_5": 1})
	_cast(s0, "sabotage")
	_cast(s1, "sabotage")
	ck(int(s0[1].get("enemy_distracted", 0)) == 0 and int(s1[1].get("enemy_distracted", 0)) == 20, "S5 Pinning Snare: Snare rattles the target (-20%% accuracy)")
	var f0 = _fresh("Ranger", {})
	f0[1]["combo"] = 8
	var fq0: int = int(sim.combat_mgr._finisher_value(f0[0], f0[1]))
	f0[0].set_path_rank("sig_Ranger_6", 1)
	var fq1: int = int(sim.combat_mgr._finisher_value(f0[0], f0[1]))
	ck(fq0 > 0 and abs(float(fq1) / float(fq0) - 1.25) < 0.02, "S6 Deadeye: a full-Aim Killing Shot quotes %d -> %d (+25%%)" % [fq0, fq1])
	f0[1]["combo"] = 3
	var fq2: int = int(sim.combat_mgr._finisher_value(f0[0], f0[1]))
	f0[0].set_path_rank("sig_Ranger_6", 0)
	var fq3: int = int(sim.combat_mgr._finisher_value(f0[0], f0[1]))
	ck(fq2 == fq3, "...and only at FULL Aim (no change at 3)")

	print("=== NINJA ===")
	ck(int(_fresh("Ninja", {})[1].get("combo", 0)) == 0 and int(_fresh("Ninja", {"sig_Ninja_1": 3})[1].get("combo", 0)) == 3, "S1 Patient Blade: rank 3 starts the fight with 3 Read")
	var c0 = _fresh("Ninja", {})
	var cc0: float = sim.combat_mgr.ability_crit_multiplier(c0[0])
	c0[0].set_path_rank("sig_Ninja_2", 5)
	var cc1: float = sim.combat_mgr.ability_crit_multiplier(c0[0])
	ck(abs(cc1 - cc0 - 0.20) < 0.001, "S2 Keen Edge: a card crit is +20 points stronger at rank 5 (x%.2f -> x%.2f). (Not crit CHANCE: a level-60 Ninja is already at the 75%% cap, so more would do nothing.)" % [cc0, cc1])
	var a0 = _fresh("Ninja", {})
	var ac0: int = sim.combat_mgr.assassinate_chance(a0[0], a0[2], a0[1])
	a0[0].set_path_rank("sig_Ninja_3", 2)
	var ac1: int = sim.combat_mgr.assassinate_chance(a0[0], a0[2], a0[1])
	ck(ac1 == ac0 + 6, "S3 Assassin's Edge: +6 points of Assassinate chance at rank 2, and the card quotes the same function (%d -> %d)" % [ac0, ac1])
	var m0 = _fresh("Ninja", {})
	var m1 = _fresh("Ninja", {"sig_Ninja_4": 1})
	_cast(m0, "analyze")
	_cast(m1, "analyze")
	ck(int(m1[1].get("combo", 0)) == int(m0[1].get("combo", 0)) + 1, "S4 Marked for Death: Mark builds one more Read (%d vs %d)" % [int(m0[1].get("combo", 0)), int(m1[1].get("combo", 0))])
	var r0 = _fresh("Ninja", {})
	var r1 = _fresh("Ninja", {"sig_Ninja_5": 1})
	r0[1]["combo"] = 5
	r1[1]["combo"] = 5
	_cast(r0, "perfect_heist")
	_cast(r1, "perfect_heist")
	ck(int(r0[1].get("combo", 9)) == 0 and int(r1[1].get("combo", 9)) == 2, "S5 Shadow Echo: Assassinate leaves 2 Read (%d vs %d)" % [int(r0[1].get("combo", 9)), int(r1[1].get("combo", 9))])
	var v0 = _fresh("Ninja", {})
	var v1 = _fresh("Ninja", {"sig_Ninja_6": 1})
	v0[0].active_buffs.clear()
	v1[0].active_buffs.clear()
	_cast(v0, "vanish")
	_cast(v1, "vanish")
	ck(v0[0].get_buff_value("evasion") == 0 and v1[0].get_buff_value("evasion") == 25 and v1[0].get_buff_source("evasion") == "Path - Vanishing Act", "S6 Vanishing Act: Phantom Strike leaves you 25% harder to hit, sourced to the Path")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
