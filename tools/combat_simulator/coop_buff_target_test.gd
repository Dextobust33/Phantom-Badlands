# Headless regression harness for v0.9.740 TEAMMATE-TARGETED BUFFS (backlog item 2).
#   godot --headless --path . --script res://tools/combat_simulator/coop_buff_target_test.gd
#
# The contract: the CASTER pays and the caster's stats set the magnitude, but the EFFECT lands
# entirely on the recipient. Asserts, for a redirected cast:
#   * the recipient gains the buff and the caster does NOT
#   * the caster still pays the resource (a free buff for an ally would be strictly better)
#   * Forcefield's shield (view state, not a Character buff) moves too
#   * Rally's HEAL moves to the recipient
#   * an un-redirected cast is unchanged (the caster keeps everything)
#   * Arcane Surge survives the view rebuild (it was silently dropped every round in co-op)
extends SceneTree

var fails := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	print("  %s %s%s" % ["PASS" if ok else "FAIL", label, ("  <- " + detail) if detail != "" else ""])
	if not ok: fails += 1

func _init():
	seed(909)
	var drop_tables = load("res://shared/drop_tables.gd").new()
	var monster_db = load("res://shared/monster_database.gd").new()
	var cm = load("res://shared/combat_manager.gd").new()
	var CharacterScript = load("res://shared/character.gd")
	root.add_child(drop_tables); root.add_child(monster_db); root.add_child(cm)
	var f = FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	var cfg = {}
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary: cfg = parsed
		f.close()
	cm.set_balance_config(cfg)
	cm.set_monster_database(monster_db)
	cm.drop_tables = drop_tables
	if "drop_tables" in monster_db: monster_db.drop_tables = drop_tables

	# 1 = Wizard (forcefield / haste), 2 = Fighter (iron skin / rally), 3 = plain ally.
	var spec := {1: ["Wizard", "intelligence"], 2: ["Fighter", "strength"], 3: ["Fighter", "strength"]}
	var chars := {}
	for pid in [1, 2, 3]:
		var ch = CharacterScript.new()
		ch.initialize("p%d" % pid, spec[pid][0], "Human")
		for i in range(19): ch.level_up()
		while ch.unspent_stat_points > 0: ch.spend_stat_point(spec[pid][1])
		chars[pid] = ch

	var mname = monster_db.get_random_monster_name_from_tier(2)
	var monster = monster_db.generate_monster_by_name(mname, 12)
	cm.start_party_combat_simul([1, 2, 3], chars, monster)
	var combat = cm.active_party_combats[1]

	# The hand gate only lets a card in hand be cast; force the ones under test into hand.
	func_force_hand(combat, 1, ["forcefield", "haste"])
	func_force_hand(combat, 2, ["iron_skin", "rally"])

	print("\n=== 1. Forcefield cast on a teammate ===")
	var caster_shield_before := int(combat.member_states[1].get("forcefield_shield", 0))
	var ally_shield_before := int(combat.member_states[3].get("forcefield_shield", 0))
	round_with(cm, combat, {1: {"kind": "ability", "ability": "forcefield", "arg": "", "target_pid": 3}})
	check("recipient gained the shield",
		int(combat.member_states[3].get("forcefield_shield", 0)) > ally_shield_before,
		"ally shield=%d" % int(combat.member_states[3].get("forcefield_shield", 0)))
	check("caster's own shield unchanged",
		int(combat.member_states[1].get("forcefield_shield", 0)) == caster_shield_before,
		"caster shield=%d" % int(combat.member_states[1].get("forcefield_shield", 0)))

	# The cost is measured on the MEMBER ACTION ALONE, not across a whole round: a round runs
	# the monster phase and its resource regen afterwards, and at level 20 regen is larger than
	# Forcefield's 3% cost, so a before/after on the round reads 0 for a self-cast too.
	func_force_hand(combat, 1, ["forcefield"])
	combat.member_states[1]["queued_action"] = {"kind": "ability", "ability": "forcefield", "arg": "", "target_pid": 3}
	var mana_start := int(chars[1].current_mana)
	cm._party_apply_member_action(combat, 1)
	var spent_on_ally := mana_start - int(chars[1].current_mana)
	func_force_hand(combat, 1, ["forcefield"])
	combat.member_states[1]["queued_action"] = {"kind": "ability", "ability": "forcefield", "arg": ""}
	mana_start = int(chars[1].current_mana)
	cm._party_apply_member_action(combat, 1)
	var spent_on_self := mana_start - int(chars[1].current_mana)
	# NOTE: the NET mana delta for a mage is often 0 — the cast is charged and then the same
	# turn's regen refills it (16%/turn regen vs Forcefield's 3% cost). That is the known
	# resource-economy flaw (backlog item 4) and it reads identically in SOLO combat, so it is
	# not something this change can assert on. What IS this change's contract is that aiming a
	# buff at an ally costs the caster exactly what a self-cast costs — no ally-buff discount,
	# no double charge. The Iron Skin case below shows a real, unmasked spend (stamina regen is
	# small enough not to hide it).
	check("aiming a buff at an ally costs the caster exactly what a self-cast costs",
		spent_on_ally == spent_on_self, "ally=%d self=%d" % [spent_on_ally, spent_on_self])

	print("\n=== 2. Iron Skin cast on a teammate ===")
	func_force_hand(combat, 2, ["iron_skin", "rally"])
	var caster_dr_before := int(chars[2].get_buff_value("damage_reduction"))
	var ally_dr_before := int(chars[3].get_buff_value("damage_reduction"))
	var stam_before := int(chars[2].current_stamina)
	round_with(cm, combat, {2: {"kind": "ability", "ability": "iron_skin", "arg": "", "target_pid": 3}})
	check("recipient gained damage_reduction",
		int(chars[3].get_buff_value("damage_reduction")) > ally_dr_before,
		"ally dr=%d" % int(chars[3].get_buff_value("damage_reduction")))
	check("caster gained none",
		int(chars[2].get_buff_value("damage_reduction")) == caster_dr_before,
		"caster dr=%d" % int(chars[2].get_buff_value("damage_reduction")))
	check("caster still paid the stamina", int(chars[2].current_stamina) < stam_before)

	print("\n=== 3. Rally's HEAL follows the buff ===")
	func_force_hand(combat, 2, ["rally"])
	chars[2].current_hp = maxi(1, int(chars[2].get_total_max_hp() * 0.5))
	chars[3].current_hp = maxi(1, int(chars[3].get_total_max_hp() * 0.5))
	var caster_hp_before := int(chars[2].current_hp)
	var ally_hp_before := int(chars[3].current_hp)
	var ally_str_before := int(chars[3].get_buff_value("strength"))
	round_with(cm, combat, {2: {"kind": "ability", "ability": "rally", "arg": "", "target_pid": 3}}, true)
	check("recipient was healed", int(chars[3].current_hp) > ally_hp_before,
		"%d -> %d" % [ally_hp_before, int(chars[3].current_hp)])
	check("caster was NOT healed", int(chars[2].current_hp) <= caster_hp_before,
		"%d -> %d" % [caster_hp_before, int(chars[2].current_hp)])
	check("recipient gained the strength buff",
		int(chars[3].get_buff_value("strength")) > ally_str_before)

	print("\n=== 4. NO target = unchanged self-cast ===")
	func_force_hand(combat, 2, ["iron_skin"])
	var self_dr_before := int(chars[2].get_buff_value("damage_reduction"))
	round_with(cm, combat, {2: {"kind": "ability", "ability": "iron_skin", "arg": ""}})
	check("caster buffs themself when no target is given",
		int(chars[2].get_buff_value("damage_reduction")) > self_dr_before)

	print("\n=== 5. Arcane Surge survives the view rebuild ===")
	func_force_hand(combat, 1, ["haste"])
	round_with(cm, combat, {1: {"kind": "ability", "ability": "haste", "arg": ""}})
	var surge := int(combat.member_states[1].get("arcane_surge_double_cast", 0))
	check("double-cast persisted in member_states", surge > 0, "surge=%d" % surge)
	var view: Dictionary = cm._party_member_view(combat, 1)
	check("and is seeded back into the next round's view",
		int(view.get("arcane_surge_double_cast", 0)) == surge)

	print("\n=== 6. Alias table ===")
	check("shield -> forcefield", cm.canonical_ability("shield") == "forcefield")
	check("ironskin -> iron_skin", cm.canonical_ability("ironskin") == "iron_skin")
	check("unknown passes through", cm.canonical_ability("meteor") == "meteor")

	print("\n%s (%d failure(s))" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails else 0)

func func_force_hand(combat: Dictionary, pid: int, cards: Array) -> void:
	combat.member_states[pid]["hand"] = cards.duplicate()

func round_with(cm, combat: Dictionary, actions: Dictionary, quiet: bool = false) -> void:
	"""Everyone acts; the named members use the given action, the rest attack. The monster is
	topped back up so a test round can never end the fight out from under a later assertion."""
	combat.monster["current_hp"] = int(combat.monster.get("max_hp", 100))
	for pid in [1, 2, 3]:
		cm.submit_party_action(1, pid, actions.get(pid, {"kind": "attack"}))
	var rr = cm.resolve_party_round(1)
	if not quiet:
		for e in rr.get("message_entries", []):
			var t := String(e.get("other", "")).strip_edges()
			if t != "": print("    | " + _strip(t))

func _strip(s: String) -> String:
	var out := ""
	var depth := 0
	for c in s:
		if c == "[": depth += 1
		elif c == "]": depth -= 1
		elif depth <= 0: out += c
	return out
