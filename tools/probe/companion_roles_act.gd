extends SceneTree
## Item 14 S1: a companion has a ROLE (from its species) and a TACTICS focus, and the role changes what it
## actually DOES in a fight. Design: docs/design/companion_roles_s0.md.
##
## Three layers, each proven separately because each fails differently:
##   1. the species -> role table (all five roles populated, the eight theme healers present, no species
##      without one)
##   2. choose_action, the pure decision (tactics change it, the cooldown holds it back)
##   3. a REAL fight turn: a healer at low owner HP raises the owner's HP; the same turn under All out does
##      not; a tank under Protect raises the taunt; a Striker's strike out-hits its own plain attack.
## Run:  godot --headless --path . --script res://tools/probe/companion_roles_act.gd
const RolesScript = preload("res://shared/companion_roles.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

var sim

func _comp(species: String, tactics: String = "balanced") -> Dictionary:
	var d: Dictionary = sim.drop_tables.COMPANION_DATA.get(species, {})
	return {"id": "t", "monster_type": species, "name": str(d.get("companion_name", species)),
		"tier": int(d.get("tier", 1)), "level": 40, "xp": 0, "bonuses": (d.get("bonuses", {}) as Dictionary).duplicate(),
		"variant": "Normal", "sub_tier": 1, "border_tier": 1, "tactics": tactics}

# One fight turn of the companion against a tough, far-off monster, with the owner at `hp_frac`.
func _turn(species: String, tactics: String, hp_frac: float) -> Dictionary:
	var ch = sim.make_char(40, "average", "Fighter", "Human")
	ch.active_companion = _comp(species, tactics)
	ch.current_hp = int(ch.get_total_max_hp() * hp_frac)
	var mon = sim.make_monster(40, "normal", 1.0)
	mon["max_hp"] = 9999999
	mon["current_hp"] = 9999999
	ch.in_combat = false
	sim.combat_mgr.start_combat(0, ch, mon)
	var c = sim.combat_mgr.active_combats[0]
	c["companion_role_cd"] = 0
	var hp0: int = ch.current_hp
	var m0: int = int(c.monster.current_hp)
	var msgs: Array = []
	sim.combat_mgr._process_companion_attack(c, msgs)
	var out := {"healed": ch.current_hp - hp0, "dealt": m0 - int(c.monster.current_hp), "taunt": int(c.get("companion_taunt_bonus", 0)),
		"weak": int(c.get("monster_weakness", 0)), "msgs": " | ".join(msgs.map(func(x): return str(x)))}
	sim.combat_mgr.end_combat(0, false, false)
	return out

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	print("--- 1. the species -> role table ---")
	var by_role := {}
	for sp in sim.drop_tables.COMPANION_DATA.keys():
		var r: String = RolesScript.role_of(_comp(sp))
		by_role[r] = int(by_role.get(r, 0)) + 1
	print("  roles: ", by_role)
	for r in RolesScript.ROLES:
		ck(int(by_role.get(r, 0)) >= 3, "role %s has species (%d)" % [r, int(by_role.get(r, 0))])
	var total := 0
	for r in by_role: total += int(by_role[r])
	ck(total == sim.drop_tables.COMPANION_DATA.size(), "every species has exactly one role (%d of %d)" % [total, sim.drop_tables.COMPANION_DATA.size()])
	for h in RolesScript.HEALER_SPECIES:
		ck(sim.drop_tables.COMPANION_DATA.has(h) and RolesScript.role_of(_comp(h)) == RolesScript.ROLE_HEALER, "theme healer %s is a Healer" % h)
	ck(RolesScript.role_of(_comp("Iron Golem")) == RolesScript.ROLE_TANK, "Iron Golem is a Tank")
	ck(RolesScript.role_of(_comp("Balrog")) == RolesScript.ROLE_DPS, "Balrog is a Striker")

	print("--- 2. the decision ---")
	var low := {"owner_hp_pct": 0.40, "cooldown": 0}
	var high := {"owner_hp_pct": 0.95, "cooldown": 0}
	ck(RolesScript.choose_action("healer", "balanced", low) == "heal", "healer heals a 40% owner (Balanced)")
	ck(RolesScript.choose_action("healer", "balanced", high) == "attack", "healer attacks a 95% owner")
	ck(RolesScript.choose_action("healer", "all_out", low) == "attack", "All out: healer does NOT heal a 40% owner")
	ck(RolesScript.choose_action("healer", "all_out", {"owner_hp_pct": 0.2, "cooldown": 0}) == "heal", "All out: ...but does save a 20% owner")
	ck(RolesScript.choose_action("healer", "protect", {"owner_hp_pct": 0.7, "cooldown": 0}) == "heal", "Protect: heals earlier (70%)")
	ck(RolesScript.choose_action("healer", "balanced", {"owner_hp_pct": 0.40, "cooldown": 2}) == "attack", "cooldown holds a role action back")
	ck(RolesScript.choose_action("tank", "protect", high) == "taunt", "tank under Protect taunts at full health")
	ck(RolesScript.choose_action("tank", "all_out", low) == "attack", "tank under All out just attacks")
	ck(RolesScript.choose_action("dps", "balanced", high) == "strike", "striker strikes")
	ck(RolesScript.choose_action("dps", "protect", high) == "attack", "striker under Protect does not")
	ck(RolesScript.choose_action("utility", "support", high) == "buff", "utility under Support buffs first")
	ck(RolesScript.choose_action("utility", "all_out", high) == "debuff", "utility under All out weakens the enemy")
	ck(RolesScript.heal_fraction("healer") <= RolesScript.HEAL_PCT_CAP, "heal never above the 15% cap")
	ck(RolesScript.heal_fraction("jack") < RolesScript.heal_fraction("healer"), "a Jack heals for less than a Healer")

	print("--- 3. a real fight turn ---")
	var a := _turn("Phoenix", "balanced", 0.40)
	ck(a.healed > 0, "Healer (Phoenix) at 40%% owner HP heals them (+%d)" % a.healed)
	ck(a.dealt == 0, "...and a heal replaces its attack (dealt %d)" % a.dealt)
	var b := _turn("Phoenix", "all_out", 0.40)
	ck(b.healed == 0 and b.dealt > 0, "same turn under All out: no heal, it attacks (healed %d, dealt %d)" % [b.healed, b.dealt])
	var t := _turn("Iron Golem", "protect", 1.0)
	ck(t.taunt >= RolesScript.TAUNT_AGGRO, "Tank (Iron Golem) under Protect raises its taunt (+%d)" % t.taunt)
	var g := _turn("Goblin", "all_out", 1.0)
	ck(g.weak > 0, "Utility (Goblin) under All out weakens the monster (-%d%%)" % g.weak)
	# strike vs plain: average over several turns, striker's strike turn vs the cooldown turn
	var strike_sum := 0
	var plain_sum := 0
	for i in 12:
		strike_sum += int(_turn("Balrog", "balanced", 1.0).dealt)
		var ch = sim.make_char(40, "average", "Fighter", "Human")
		ch.active_companion = _comp("Balrog", "balanced")
		var mon = sim.make_monster(40, "normal", 1.0)
		mon["max_hp"] = 9999999
		mon["current_hp"] = 9999999
		ch.in_combat = false
		sim.combat_mgr.start_combat(0, ch, mon)
		var c = sim.combat_mgr.active_combats[0]
		c["companion_role_cd"] = 2     # on cooldown: its next turn is a plain attack
		var m0: int = int(c.monster.current_hp)
		sim.combat_mgr._process_companion_attack(c, [])
		plain_sum += m0 - int(c.monster.current_hp)
		sim.combat_mgr.end_combat(0, false, false)
	ck(strike_sum > plain_sum * 1.2, "a Striker's strike out-hits its plain attack (%d vs %d over 12 turns)" % [strike_sum, plain_sum])

	print("")
	print(("PASS - companion_roles_act" if fails == 0 else "FAIL - companion_roles_act: %d check(s)" % fails))
	quit(1 if fails > 0 else 0)
