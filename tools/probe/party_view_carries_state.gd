extends SceneTree
## Does a party member's fight state survive from one round to the next?
##
## Owner 2026-09-15, in the Warden's fight (a party combat): *"I used Phantom Strike ... My next
## move was a regular attack and it didn't mention being a Crit at all."*
##
## A party member acts through a solo-shaped VIEW that is rebuilt every action and discarded
## after it, and only whitelisted keys survived. Enumerating what each class's cards actually
## write onto a view found the whitelist missing `vanished`, `analyze_bonus`,
## `crit_escalation_stacks`, `casts_this_fight`, `forcefield_casts`, `guard_open`, and every
## runtime-named once-per-fight flag (`opener_used_<card>` ...). It also found a non-lethal
## Assassinate aborting mid-cast in a party, on a script error reading the suppressed monster
## turn's missing `message`.
##
## Driven through `_party_apply_member_action`, the function a party round really calls.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _text(entries: Array) -> String:
	var out := PackedStringArray()
	for e in entries:
		if e is Dictionary:
			out.append(String(e.get("self", "")))
	return " | ".join(out)


func _party(cm, sim, klass: String) -> Dictionary:
	cm.active_party_combats.clear()
	cm.party_combat_membership.clear()
	var ch = sim.make_char(30, "average", klass, "Human")
	var mon = sim.make_monster(30, "normal", 400.0)
	var r = cm.start_party_combat_simul([1], {1: ch}, mon)
	return r["combat"]


func _act(cm, combat: Dictionary, action: Dictionary) -> String:
	var ch = combat.characters[1]
	ch.current_hp = ch.get_total_max_hp()
	ch.current_mana = ch.get_total_max_mana()
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_energy = ch.get_total_max_energy()
	var st = combat.member_states[1]
	if String(action.get("kind", "")) == "ability":
		st["hand"] = [String(action["ability"])] + (st.get("hand", []) as Array)
	st["queued_action"] = action
	return _text(cm._party_apply_member_action(combat, 1))


func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr

	print("===== 1. PHANTOM STRIKE, THEN AN ATTACK, IN A PARTY =====")
	var c1 := _party(cm, sim, "Ninja")
	var t1 := _act(cm, c1, {"kind": "ability", "ability": "vanish", "arg": ""})
	ck(t1.find("PHANTOM STRIKE") >= 0, "Phantom Strike resolves in the party")
	ck(bool((c1.member_states[1].get("view_carry", {}) as Dictionary).get("vanished", false)),
		"  and its 'next strike lands true' flag survives the view being thrown away")
	var t2 := _act(cm, c1, {"kind": "attack"})
	print("  next attack: %s" % t2.substr(0, 220))
	ck(t2.to_lower().find("critical") >= 0, "the NEXT attack is the promised critical, and says so")

	print("\n===== 2. A ONCE-PER-FIGHT UPGRADE STAYS SPENT =====")
	var c2 := _party(cm, sim, "Fighter")
	c2.characters[1].ability_milestone_picks["cleave"] = ["opener"]
	_act(cm, c2, {"kind": "ability", "ability": "cleave", "arg": ""})
	ck(bool((c2.member_states[1].get("view_carry", {}) as Dictionary).get("opener_used_cleave", false)),
		"Opener's flag - a key named at runtime, which no whitelist could list - is kept")
	var v2: Dictionary = cm._party_member_view(c2, 1)
	ck(bool(v2.get("opener_used_cleave", false)), "  and the next action's view sees it, so it cannot fire twice")

	print("
===== 3. A NON-LETHAL ASSASSINATE STILL REPORTS ITSELF IN A PARTY =====")
	# Its miss branch read the suppressed monster turn's `message`, which did not exist, and the
	# script error threw away the whole cast's log. A generic "did anything print" check passed
	# on the broken code (other lines still arrived), so this asks for the card's own words.
	var c3 := _party(cm, sim, "Ninja")
	var hit_word := String(cm.finisher_flavour(c3.characters[1]).get("hit", "ASSASSINATE"))
	var reported := 0
	for rep in range(10):
		c3.monster["current_hp"] = c3.monster["max_hp"]
		c3.member_states[1]["combo"] = 1          # low odds: mostly the non-lethal branch
		var t3 := _act(cm, c3, {"kind": "ability", "ability": "perfect_heist", "arg": ""})
		if t3.find("ASSASSINATE") >= 0 or t3.find(hit_word) >= 0:
			reported += 1
	ck(reported == 10, "every Assassinate cast's own result reaches the log (%d of 10)" % reported)

	print("")
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
