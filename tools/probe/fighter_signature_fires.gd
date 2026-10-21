extends SceneTree
## The Fighter's Signature path (docs/design/paths_revamp.md section 7) - every node must CHANGE the fight it names.
## Drives the real combat manager with the same seed with and without the node, so any difference is the node.
## ("Identical numbers after a real change mean the change is not running.")
const PD = preload("res://shared/path_database.gd")
var sim
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

var _next_pid := 100
func _fresh(ranks: Dictionary) -> Array:
	_next_pid += 1
	var pid: int = _next_pid
	var ch = sim.make_char(60, "average", "Fighter", "Human")
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

func _rounds_in(res: Dictionary) -> int:
	var re := RegEx.new()
	re.compile("for ([0-9]+) rounds")
	for m in res.get("messages", []):
		var hit = re.search(String(m))
		if hit:
			return int(hit.get_string(1))
	return 0

func _damage_done(mon, before: int) -> int:
	return before - int(mon.current_hp)

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("--- the nodes exist and are reachable ---")
	var sig: Array = PD.signature_nodes("Fighter")
	ck(sig.size() == 6, "six Signature nodes for the Fighter (+ the class keystone = seven)")
	ck(PD.get_prereq_id("sig_Fighter_3") == "sig_Fighter_2" and PD.get_prereq_id("sig_Fighter_1") == "", "they chain S1..S6")
	ck(String(PD.find_node("sig_Fighter_4").get("class_lock", "")) == "Fighter", "locked to the Fighter")

	print("--- S1 Drilled Stance ---")
	var a = _fresh({})
	var b = _fresh({"sig_Fighter_1": 5})
	var dr0: int = int(a[1].get("warrior_stance_dr", 0))
	var dr5: int = int(b[1].get("warrior_stance_dr", 0))
	ck(dr5 > dr0 and dr0 == 30 and dr5 == 42, "the opening stance's damage reduction goes 30 -> 42 at rank 5 (%d -> %d)" % [dr0, dr5])
	ck(int(b[1].get("warrior_stance_path_pct", 0)) == 20, "and the fight records where the extra came from")

	print("--- S2 Banked Momentum ---")
	ck(int(_fresh({})[1].get("momentum", 0)) == 0, "no node: Momentum starts at 0")
	ck(int(_fresh({"sig_Fighter_2": 3})[1].get("momentum", 0)) == 3, "rank 3: Momentum starts at 3")

	print("--- S3 Shield Wall ---")
	# A huge defense makes the node's share dwarf the roll's variance, so one cast each is enough.
	var plain = _fresh({})
	var walled = _fresh({"sig_Fighter_3": 5})
	plain[0].constitution = 1000000
	walled[0].constitution = 1000000
	var hp0: int = int(plain[2].current_hp)
	_cast(plain[0], plain[1], "shield_bash")
	var d_plain: int = _damage_done(plain[2], hp0)
	var hp1: int = int(walled[2].current_hp)
	_cast(walled[0], walled[1], "shield_bash")
	var d_wall: int = _damage_done(walled[2], hp1)
	ck(d_wall > d_plain * 5 and d_plain > 0, "Shield Bash hits much harder with the node on a heavy defense (%d -> %d)" % [d_plain, d_wall])

	print("--- S4 Lasting Guard ---")
	# Read the rounds off the card's own line: the buff's remaining duration also depends on whether the monster's turn ticked it.
	var g0 = _fresh({})
	var g1 = _fresh({"sig_Fighter_4": 1})
	var dur0 := _rounds_in(_cast(g0[0], g0[1], "iron_skin"))
	var dur1 := _rounds_in(_cast(g1[0], g1[1], "iron_skin"))
	ck(dur0 > 0 and dur1 == dur0 + 2, "Bulwark lasts 2 rounds longer (%d -> %d)" % [dur0, dur1])

	print("--- S5 Staggering Bash ---")
	var s0 = _fresh({})
	var s1 = _fresh({"sig_Fighter_5": 1})
	seed(5)
	_cast(s0[0], s0[1], "shield_bash")
	seed(5)
	_cast(s1[0], s1[1], "shield_bash")
	var m0: int = int(s0[1].get("momentum", 0))
	var m1: int = int(s1[1].get("momentum", 0))
	var stunned: bool = int(s1[1].get("monster_stunned", 0)) > 0 or int(s1[1].get("consec_stuns", 0)) > 0
	ck(stunned and m1 == m0 + 1, "a stunning Bash builds one more Momentum (%d -> %d)" % [m0, m1])

	print("--- S6 Aftershock ---")
	var f0 = _fresh({})
	f0[1]["momentum"] = 5
	_cast(f0[0], f0[1], "devastate")
	var f1 = _fresh({"sig_Fighter_6": 1})
	f1[1]["momentum"] = 5
	_cast(f1[0], f1[1], "devastate")
	ck(int(f0[1].get("momentum", 9)) == 0 and int(f1[1].get("momentum", 9)) == 2, "Devastate leaves 2 Momentum behind (%d vs %d)" % [int(f0[1].get("momentum", 9)), int(f1[1].get("momentum", 9))])

	print("--- every effect is named at the start of the fight ---")
	var named = _fresh({"sig_Fighter_1": 2, "sig_Fighter_2": 1})
	var summary: String = named[0].path_summary()
	ck(summary.find("Drilled Stance 2") >= 0 and summary.find("Banked Momentum 1") >= 0, "the Path line names each node and rank (%s)" % summary)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
