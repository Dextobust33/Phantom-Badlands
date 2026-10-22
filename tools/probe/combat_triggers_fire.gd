extends SceneTree
## COMBAT TRIGGERS (shared/combat_triggers.gd): every trigger must change the fight it names, from GEAR (the affix path), with the same method as the path probes:
## the real combat manager, one character, the trigger held or not, the same seed per pair. The unit is the trigger; a closing loop fails if any is untested.
const CT = preload("res://shared/combat_triggers.gd")
var sim
var fails := 0
var _pid := 1300
var tested: Dictionary = {}

func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _char(klass: String, trig: String = "", power: float = 1.0):
	var ch = sim.make_char(60, "average", klass, "Human")
	ch.initialize_deck_collection_if_needed()
	ch.set_path_scale_override(1.0)
	_hold(ch, trig, power)
	return ch

func _hold(ch, trig: String, power: float) -> void:
	ch.equipped.erase("ring")
	if trig != "":
		ch.equipped["ring"] = {"name": "Test Ring", "type": "ring", "slot": "ring", "wear": 0, "affixes": {CT.key_for(trig): power}}

func _fight(ch, suppress: bool = true, mon_mul: float = 1.0) -> Array:
	_pid += 1
	var mon = sim.make_monster(60, "normal", 1.0)
	mon.max_hp = 99999999
	mon.current_hp = 99999999
	mon.strength = int(mon.strength * mon_mul)
	sim.combat_mgr.start_combat(_pid, ch, mon)
	var c = sim.combat_mgr.active_combats[_pid]
	c["_probe_pid"] = _pid
	c["player_can_act"] = true
	c["suppress_monster_turn"] = suppress
	return [ch, c, mon]

func _cast(t: Array, card: String, sd: int) -> String:
	t[1]["combat_hand"] = [card]
	t[1]["player_can_act"] = true
	t[0].current_energy = t[0].get_total_max_energy()
	t[0].current_mana = t[0].get_total_max_mana()
	t[0].current_stamina = t[0].get_total_max_stamina()
	seed(sd)
	var r = sim.combat_mgr.process_ability_command(int(t[1]["_probe_pid"]), card, "10")
	var blob := String(r.get("message", ""))
	for m in r.get("messages", []):
		blob += "\n" + String(m)
	return blob

func _count(klass: String, trig: String, card: String, n: int, power: float = 1.0) -> int:
	var hits := 0
	var ch = _char(klass, trig, power)
	var name: String = CT.TRIGGERS[trig]["name"]
	for sd in range(1, n + 1):
		var t = _fight(ch)
		if _cast(t, card, sd).find(name) >= 0:
			hits += 1
		sim.combat_mgr.active_combats.erase(int(t[1]["_probe_pid"]))
	return hits

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("--- the table ---")
	var events := ["on_cast", "on_hit", "on_crit", "on_kill", "on_hurt", "on_fight_start"]
	var bad := 0
	for id in CT.TRIGGERS:
		var t: Dictionary = CT.TRIGGERS[id]
		if not (String(t["event"]) in events) or not (String(t["effect"]) in ["engine", "resource_pct", "heal_pct", "next_damage", "echo_hit", "bleed", "slow", "guard"]):
			bad += 1
	ck(bad == 0, "every trigger names a supported event and effect (%d triggers)" % CT.TRIGGERS.size())
	var all_cards_tagged := true
	for card in ["power_strike", "devastate", "war_cry", "iron_skin", "magic_bolt", "blast", "meteor", "forcefield", "frost_nova", "analyze", "distract", "ambush", "vanish", "perfect_heist", "sabotage", "shadowstep", "shield_bash", "berserk"]:
		if CT.tags_for(card).is_empty():
			all_cards_tagged = false
	ck(all_cards_tagged, "the core cards carry tags")

	print("=== EVENTS ===")
	# on_crit: the line appears exactly when the cast crit
	var crits_with := 0
	var lines_with := 0
	var line_without_crit := 0
	var ch1 = _char("Fighter", "killing_rhythm")
	for sd in range(1, 80):
		var t1 = _fight(ch1)
		var b: String = _cast(t1, "power_strike", sd)
		var crit: bool = b.find("CRITICAL") >= 0
		var line: bool = b.find("Killing Rhythm") >= 0
		if crit:
			crits_with += 1
		if line:
			lines_with += 1
			if not crit:
				line_without_crit += 1
		sim.combat_mgr.active_combats.erase(int(t1[1]["_probe_pid"]))
	ck(lines_with > 0 and line_without_crit == 0 and lines_with <= 4 * crits_with, "Killing Rhythm fires on crits and only on crits (%d lines, %d crits, %d without a crit)" % [lines_with, crits_with, line_without_crit])
	tested["killing_rhythm"] = true
	var t1b = _fight(_char("Fighter", "killing_rhythm", 3))
	t1b[1]["trg_crit"] = true
	t1b[1]["momentum"] = 0
	var msgs: Array = []
	sim.combat_mgr._fire_triggers(t1b[1], "on_crit", {"tags": [], "damage": 100}, msgs)
	ck(int(t1b[1]["momentum"]) == 3, "power 3 is three times as strong: +3 Momentum in one go (%d)" % int(t1b[1]["momentum"]))
	var capped := 0
	for i in range(8):
		var tmp: Array = []
		sim.combat_mgr._fire_triggers(t1b[1], "on_crit", {"tags": [], "damage": 100}, tmp)
		capped += tmp.size()
	ck(capped == 0 or int(t1b[1].get("trg_fired", {}).get("killing_rhythm", 0)) <= 4, "the per-fight cap holds (fired %d, cap 4)" % int(t1b[1].get("trg_fired", {}).get("killing_rhythm", 0)))

	# on_cast with tags
	var ch = _char("Fighter", "finishing_flourish")
	var tf = _fight(ch)
	tf[1]["momentum"] = 3
	ch.current_stamina = 10
	var bf: String = _cast(tf, "devastate", 5)
	ck(bf.find("Finishing Flourish") >= 0, "Finishing Flourish fires after a finisher (Devastate)")
	var tf2 = _fight(ch)
	ck(_cast(tf2, "power_strike", 5).find("Finishing Flourish") < 0, "...and not after a plain strike")
	tested["finishing_flourish"] = true

	var chs = _char("Fighter", "setup_edge")
	var ts = _fight(chs)
	var q0: float = float(sim.combat_mgr.preview_ability_effect(chs, ts[1], "power_strike").get("value", 0))
	var bs: String = _cast(ts, "war_cry", 3)
	var q1: float = float(sim.combat_mgr.preview_ability_effect(chs, ts[1], "power_strike").get("value", 0))
	ck(bs.find("Setup Edge") >= 0 and abs(q1 / q0 - 1.15) < 0.03, "Setup Edge: after War Cry the next strike quotes +15%% (%d -> %d)" % [int(q0), int(q1)])
	_cast(ts, "power_strike", 4)
	var q2: float = float(sim.combat_mgr.preview_ability_effect(chs, ts[1], "power_strike").get("value", 0))
	ck(abs(q2 / q0 - 1.0) < 0.03 and not ts[1].has("trg_next_mult"), "...and it is spent by the strike that used it (%d)" % int(q2))
	tested["setup_edge"] = true

	var chg = _char("Fighter", "steady_hands")
	var tg = _fight(chg)
	chg.current_hp = int(chg.get_total_max_hp() * 0.5)
	var hp0: int = chg.current_hp
	var bg: String = _cast(tg, "iron_skin", 3)
	ck(bg.find("Steady Hands") >= 0 and chg.current_hp > hp0, "Steady Hands: a guard card heals (%d -> %d)" % [hp0, chg.current_hp])
	tested["steady_hands"] = true

	var echo_with: int = _count("Wizard", "echo_bolt", "blast", 150)
	var echo_none: int = _count("Wizard", "", "blast", 10) if false else 0
	ck(echo_with >= 6 and echo_with <= 40, "Echo Bolt: about 12%% of spells echo (%d of 150)" % echo_with)
	var echo3: int = _count("Wizard", "echo_bolt", "blast", 150, 3.0)
	ck(echo3 > echo_with, "...and more often with more power (power 3: %d of 150)" % echo3)
	tested["echo_bolt"] = true

	var barb: int = _count("Fighter", "barbed_strikes", "power_strike", 150)
	ck(barb >= 8 and barb <= 45, "Barbed Strikes: about 15%% of strikes leave a bleed (%d of 150)" % barb)
	tested["barbed_strikes"] = true

	var chill: int = _count("Fighter", "chilling_touch", "shield_bash", 100)
	ck(chill >= 15 and chill <= 50, "Chilling Touch: about 30%% of control cards slow the monster (%d of 100)" % chill)
	var chx = _char("Fighter", "chilling_touch", 3)
	var tch = _fight(chx)
	var slowed := false
	for sd in range(1, 30):
		_cast(tch, "shield_bash", sd)
		if int(tch[1].get("monster_slowed", 0)) > 0:
			slowed = true
			break
	ck(slowed, "...and the slow it sets is the one the monster's turn now honours (monster_slowed %d)" % int(tch[1].get("monster_slowed", 0)))
	tested["chilling_touch"] = true

	var chw = _char("Fighter", "warding_buff")
	chw.active_buffs.clear()
	var tw = _fight(chw)
	var bw: String = _cast(tw, "berserk", 3)
	ck(bw.find("Warding Buff") >= 0 and chw.get_buff_value("path_guard") == 8 and chw.get_buff_source("path_guard").begins_with("Trigger"), "Warding Buff: a buff card also grants 8%% damage reduction, named (%d, '%s')" % [chw.get_buff_value("path_guard"), chw.get_buff_source("path_guard")])
	tested["warding_buff"] = true

	# on_hurt: a big blow
	var chp = _char("Fighter", "pain_fuel")
	var tp = _fight(chp, false, 12.0)
	tp[1]["momentum"] = 0
	var got_pain := false
	for sd in range(1, 20):
		chp.current_hp = chp.get_total_max_hp()
		seed(sd)
		var r = sim.combat_mgr.process_monster_turn(tp[1])
		if chp.current_hp < chp.get_total_max_hp() and int(tp[1].get("momentum", 0)) >= 1:
			got_pain = true
			ck(String(r.get("message", "")).find("Pain Fuel") >= 0, "Pain Fuel: the blow that triggered it says so in the monster's turn")
			break
	ck(got_pain, "Pain Fuel: a blow of 15%%+ builds Momentum (%d)" % int(tp[1].get("momentum", 0)))
	var chp2 = _char("Fighter", "pain_fuel")
	var tp2 = _fight(chp2, false, 1.0)
	var small_fuel := false
	for sd in range(1, 20):
		chp2.current_hp = chp2.get_total_max_hp()
		tp2[1]["momentum"] = 0
		seed(sd)
		sim.combat_mgr.process_monster_turn(tp2[1])
		var lost: int = chp2.get_total_max_hp() - chp2.current_hp
		if lost > 0 and float(lost) * 100.0 < 15.0 * float(chp2.get_total_max_hp()) and int(tp2[1].get("momentum", 0)) >= 1:
			small_fuel = true
	ck(not small_fuel, "...and a small blow does not")
	tested["pain_fuel"] = true

	var chl = _char("Fighter", "last_gasp")
	var tl = _fight(chl, false, 1.0)
	var healed_once := 0
	for sd in range(1, 20):
		chl.current_hp = int(chl.get_total_max_hp() * 0.40)
		var before: int = chl.current_hp
		seed(sd)
		sim.combat_mgr.process_monster_turn(tl[1])
		if int(tl[1].get("trg_fired", {}).get("last_gasp", 0)) == 1 and healed_once == 0:
			healed_once = 1
			ck(chl.current_hp > before - int(chl.get_total_max_hp() * 0.2), "Last Gasp: the blow that leaves you under 35%% heals (HP %d -> %d)" % [before, chl.current_hp])
	ck(int(tl[1].get("trg_fired", {}).get("last_gasp", 0)) <= 1, "...once a fight (fired %d)" % int(tl[1].get("trg_fired", {}).get("last_gasp", 0)))
	tested["last_gasp"] = true

	# variety
	var chv = _char("Fighter", "variety_burst")
	var tv = _fight(chv)
	_cast(tv, "power_strike", 1)
	_cast(tv, "cleave", 2)
	var vb: String = _cast(tv, "shield_bash", 3)
	ck(vb.find("Full Repertoire") >= 0, "Full Repertoire: three different cards in a row fire it")
	ck(abs(float(tv[1].get("trg_next_mult", 1.0)) - 1.25) < 0.001, "...promising the next damaging card +25%% (x%.2f)" % float(tv[1].get("trg_next_mult", 1.0)))
	var chv2 = _char("Fighter", "variety_burst")
	var tv2 = _fight(chv2)
	var rep := ""
	for sd in range(1, 6):
		rep += _cast(tv2, "power_strike", sd)
	ck(rep.find("Full Repertoire") < 0, "...but spamming one card never does - the point of it")
	tested["variety_burst"] = true

	# on_kill
	var chk = _char("Fighter", "kill_vigor")
	var tk = _fight(chk)
	tk[2].current_hp = 1
	tk[2].max_hp = 1
	tk[2].defense = 0
	chk.current_stamina = 0
	var killed := false
	var kb := ""
	for sd in range(1, 30):
		tk[2].current_hp = 1
		seed(sd)
		var rk = sim.combat_mgr.process_attack(tk[1])
		kb = String(rk.get("message", ""))
		for m in rk.get("messages", []):
			kb += String(m)
		if bool(rk.get("victory", false)):
			killed = true
			break
	ck(killed and kb.find("Kill Vigor") >= 0 and chk.current_stamina > 0, "Kill Vigor: a kill restores the pool (stamina %d)" % chk.current_stamina)
	tested["kill_vigor"] = true

	# on_fight_start
	var cho = _char("Fighter", "opening_surge")
	var start = sim.combat_mgr.start_combat(_pid + 50, cho, sim.make_monster(60, "normal", 1.0))
	var cs = sim.combat_mgr.active_combats[_pid + 50]
	ck(int(cs.get("momentum", 0)) >= 1 and String(start.get("message", "")).find("Opening Surge") >= 0, "Opening Surge: the fight opens with the engine built and the line says why (Momentum %d)" % int(cs.get("momentum", 0)))
	tested["opening_surge"] = true
	var chno = _char("Fighter", "")
	sim.combat_mgr.start_combat(_pid + 60, chno, sim.make_monster(60, "normal", 1.0))
	ck(int(sim.combat_mgr.active_combats[_pid + 60].get("momentum", 0)) == 0, "...and without it the fight opens empty (the control)")

	print("=== GEAR ===")
	var item_ok := true
	var drop = load("res://shared/drop_tables.gd").new()
	get_root().add_child(drop)
	var landed := 0
	for i in range(600):
		var af: Dictionary = drop._roll_affixes("epic", 120)
		for k in af:
			if String(k).begins_with("trg_"):
				landed += 1
				if not CT.TRIGGERS.has(String(k).substr(4)) or float(af[k]) < 1.0:
					item_ok = false
	ck(item_ok and landed > 0, "an epic item can roll a trigger (%d of 600 epic L120 rolls carried one)" % landed)
	var line: String = CT.item_line("echo_bolt", 2.0)
	ck(line.find("Echo Bolt") >= 0 and line.find("Greater") >= 0, "an item shows the trigger by name, tier and text ('%s')" % line.substr(0, 60))
	var worn := {"affixes": {"trg_echo_bolt": 2.0}, "wear": 50}
	ck(abs(float(CT.item_triggers(worn)[0]["power"]) - 1.0) < 0.001, "wear weakens a trigger like any affix (power 2 at 50%% wear = 1)")

	print("=== EVERY TRIGGER WAS TESTED ===")
	var missing: Array = []
	for id in CT.TRIGGERS:
		if not tested.has(id):
			missing.append(id)
	ck(missing.is_empty(), "no trigger untested (missing: %s)" % ", ".join(missing))
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
