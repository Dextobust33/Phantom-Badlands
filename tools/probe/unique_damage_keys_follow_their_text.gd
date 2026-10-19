extends SceneTree
## Playtest sheet item 40: artifact / unique gear vs its text.
## FOUND by A/B at +100 (same weapon in both arms, only the effect differs):
##   attack_damage_pct ("+X% attack damage", Bloodletter's Hook): basic attacks x1.98, CARDS x1.01
##   spell_damage_pct  ("+X% spell damage", Cinderheart Staff):   every class's cards x2.0, attacks x0.97
## i.e. inverted. A card has a SCHOOL now: a mage's cards are spells, everyone else's are attacks.
## Also pins the two stat-aggregator effects (defense_pct, max_hp_pct) to their text.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _avg_hit(sim, cls: String, key: String, mode: String, card: String, n: int) -> float:
	var total := 0.0
	var cnt := 0
	for f in n:
		var ch = sim.make_char(40, "average", cls, "Human")
		var ufx := {}
		if key != "":
			ufx[key] = 100
		ch.equipped["weapon"] = {"name": "Probe Weapon", "type": "weapon", "level": 40, "rarity": "artifact", "unique_effect": ufx}
		var mon = sim.make_monster(40, "normal", 500.0)
		ch.in_combat = false
		sim.combat_mgr.start_combat(0, ch, mon)
		var c = sim.combat_mgr.active_combats[0]
		c["suppress_monster_turn"] = true
		ch.current_hp = ch.get_total_max_hp()
		ch.current_stamina = ch.get_total_max_stamina()
		ch.current_mana = ch.get_total_max_mana()
		ch.current_energy = ch.get_total_max_energy()
		var before: int = int(mon.current_hp)
		if mode == "attack":
			sim.combat_mgr.process_combat_action(0, sim.combat_mgr.CombatAction.ATTACK)
		else:
			var hand: Array = c.get("combat_hand", [])
			if not hand.has(card):
				hand.append(card)
			c["combat_hand"] = hand
			sim.combat_mgr.process_ability_command(0, card, "100" if card == "magic_bolt" else "")
		var lost: int = before - int(mon.current_hp)
		if lost > 0:
			total += lost
			cnt += 1
		sim.combat_mgr.end_combat(0, false, false)
	return total / maxf(1.0, float(cnt))

func _ratio(sim, cls: String, key: String, mode: String, card: String) -> float:
	var base := _avg_hit(sim, cls, "", mode, card, 60)
	var with := _avg_hit(sim, cls, key, mode, card, 60)
	return with / maxf(1.0, base)

func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var rows := [
		# [class, mode, card, key, should it apply?]
		["Fighter", "attack", "", "attack_damage_pct", true],
		["Fighter", "card", "power_strike", "attack_damage_pct", true],
		["Ranger", "card", "ambush", "attack_damage_pct", true],
		["Wizard", "attack", "", "attack_damage_pct", true],
		["Wizard", "card", "magic_bolt", "attack_damage_pct", false],
		["Fighter", "card", "power_strike", "spell_damage_pct", false],
		["Ranger", "card", "ambush", "spell_damage_pct", false],
		["Wizard", "card", "magic_bolt", "spell_damage_pct", true],
	]
	for r in rows:
		var ratio: float = _ratio(sim, r[0], r[3], r[1], r[2])
		if r[4]:
			ck(ratio > 1.6, "%s %s %s: %s at +100 applies (x%.2f)" % [r[0], r[1], r[2], r[3], ratio])
		else:
			ck(ratio < 1.25, "%s %s %s: %s correctly does NOT apply (x%.2f)" % [r[0], r[1], r[2], r[3], ratio])
	var ch = sim.make_char(40, "average", "Fighter", "Human")
	# Baseline is measured WITH the plain replacement weapon already worn: the starting weapon carries its own
	# HP/defense, so swapping it for the unique drops that and compared the unique against a larger baseline.
	ch.equipped["weapon"] = {"name": "W", "type": "weapon", "level": 40}
	var hp0: int = ch.get_total_max_hp()
	var def0: int = ch.get_total_defense()
	ch.equipped["weapon"] = {"name": "W", "type": "weapon", "level": 40, "unique_effect": {"max_hp_pct": 50, "defense_pct": 50}}
	ck(ch.get_total_max_hp() > hp0 * 1.3, "max_hp_pct +50 raises max HP (%d -> %d)" % [hp0, ch.get_total_max_hp()])
	ck(ch.get_total_defense() > def0 * 1.2, "defense_pct +50 raises defense (%d -> %d)" % [def0, ch.get_total_defense()])
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
