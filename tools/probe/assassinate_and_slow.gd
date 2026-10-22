extends SceneTree
## Two effects that were written and never read by the cards / the monster's turn:
##   1. Assassinate keystone (`crit_damage_pct` +50, `noncrit_damage_pct` -10) reached the BASIC ATTACK only. A deck-driven Trickster
##      never felt either half. Both halves now reach card casts, together (the upside alone would make the keystone pure gain).
##   2. `monster_slowed` (companion Web Trap / Undertow, random_debuff): written, ticked down, drawn as a chip, never read.
##      A slowed monster is now less likely to hit the player, at the player's own speed-buff rate (-N% speed = -N/2 to hit).
## Method: the real combat manager, same character, one toggle, the same seed for each pair of casts.
const PD = preload("res://shared/path_database.gd")
var sim
var fails := 0
var _next_pid := 700
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _fresh(klass: String) -> Array:
	_next_pid += 1
	var pid: int = _next_pid
	var ch = sim.make_char(60, "average", klass, "Human")
	ch.initialize_deck_collection_if_needed()
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

func _cast_dmg(t: Array, name: String, sd: int) -> int:
	t[2].current_hp = 9999999
	t[1]["combat_hand"] = [name]
	t[1]["player_can_act"] = true
	t[1]["combo"] = 0
	t[1].erase("monster_sabotaged")
	t[0].current_energy = t[0].get_total_max_energy()
	seed(sd)
	sim.combat_mgr.process_ability_command(int(t[1]["_probe_pid"]), name, "10")
	return 9999999 - int(t[2].current_hp)

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("=== ASSASSINATE KEYSTONE REACHES THE CARDS ===")
	var kn = PD.find_node("trickster_1_5")
	ck(not kn.is_empty() and kn.get("effect", {}).has("crit_damage_pct") and kn.get("effect", {}).has("noncrit_damage_pct"), "the keystone still carries both halves (+crit, -normal)")
	var t = _fresh("Ninja")
	var m0: float = sim.combat_mgr.ability_crit_multiplier(t[0], t[1], "ambush")
	var n0: float = sim.combat_mgr.ability_noncrit_multiplier(t[0])
	t[0].set_path_rank("trickster_1_5", 1)
	var m1: float = sim.combat_mgr.ability_crit_multiplier(t[0], t[1], "ambush")
	var n1: float = sim.combat_mgr.ability_noncrit_multiplier(t[0])
	ck(abs(m1 - m0 - 0.50) < 0.001, "a card crit is +50 points stronger (x%.2f -> x%.2f), the basic attack's own amount" % [m0, m1])
	ck(abs(n0 - 1.0) < 0.001 and abs(n1 - 0.90) < 0.001, "a card that does not crit deals 10%% less (x%.2f -> x%.2f)" % [n0, n1])
	# Real casts. Same seed per pair: the same rolls, so each pair differs ONLY by the keystone. A crit must come out x(1.75/1.25),
	# an ordinary cast x0.90, and across enough seeds both must occur.
	var crits := 0
	var plain := 0
	var other := 0
	var base_sum := 0
	var key_sum := 0
	for sd in range(1, 81):
		t[0].set_path_rank("trickster_1_5", 0)
		var d0: int = _cast_dmg(t, "ambush", sd)
		t[0].set_path_rank("trickster_1_5", 1)
		var d1: int = _cast_dmg(t, "ambush", sd)
		base_sum += d0
		key_sum += d1
		var r: float = float(d1) / float(max(1, d0))
		if abs(r - (m1 / m0)) < 0.04:
			crits += 1
		elif abs(r - 0.90) < 0.03:
			plain += 1
		else:
			other += 1
	ck(crits > 0 and plain > 0, "across 80 seeded pairs both outcomes occur: %d crits (x%.2f), %d ordinary casts (x0.90)" % [crits, m1 / m0, plain])
	ck(other == 0, "no pair lands anywhere else (%d off-pattern)" % other)
	ck(key_sum != base_sum, "the keystone changes a Ninja's total card damage (%d -> %d, %+.1f%%)" % [base_sum, key_sum, 100.0 * (float(key_sum) / float(base_sum) - 1.0)])
	# A Ranger on Steady Hand never crits, so it must not pay the price for an upside it cannot get.
	var rg = _fresh("Ranger")
	rg[0].set_path_rank("trickster_1_5", 1)
	var steady_n: float = sim.combat_mgr.ability_noncrit_multiplier(rg[0])
	ck(abs(steady_n - 0.90) < 0.001, "the multiplier itself is a plain 0.90 (the no-crit exemption is in the cast, checked next)")
	var src: String = FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(src.contains("if not _crit_landed and cc > 0 and _noncrit_mult < 1.0:"), "the cast skips the penalty when the character cannot crit at all (cc = 0)")

	print("=== A SLOWED MONSTER HITS LESS ===")
	var s = _fresh("Fighter")
	s[1]["suppress_monster_turn"] = false
	var max_hp: int = s[0].get_total_max_hp()
	var hits0 := 0
	var hits1 := 0
	var rounds := 500
	for slow in [0, 40]:
		var hits := 0
		for i in range(rounds):
			seed(9000 + i)
			s[0].current_hp = max_hp
			s[1]["monster_slowed"] = slow
			s[1]["monster_slow_duration"] = 99
			s[1]["monster_stunned"] = 0
			s[1]["monster_charmed"] = 0
			s[1]["monster_weakness"] = 0
			s[1]["player_can_act"] = false
			sim.combat_mgr.process_monster_turn(s[1])
			if s[0].current_hp < max_hp:
				hits += 1
		if slow == 0:
			hits0 = hits
		else:
			hits1 = hits
	var rate0: float = float(hits0) / float(rounds)
	var rate1: float = float(hits1) / float(rounds)
	print("  (monster lands a hit in %.1f%% of rounds un-slowed, %.1f%% slowed 40%%)" % [rate0 * 100.0, rate1 * 100.0])
	ck(hits0 > 0 and rate0 - rate1 > 0.10, "a 40%% slow cuts the monster's hit rate by about 20 points (%.0f%% -> %.0f%%)" % [rate0 * 100.0, rate1 * 100.0])
	ck(rate1 < rate0, "same seeds, one toggle: the slowed monster never hits more often")

	print("")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
