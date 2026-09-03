# The rank-up offer path end to end, including co-op.
extends SceneTree
const CU = preload("res://shared/card_upgrades.gd")
const CombatManager = preload("res://shared/combat_manager.gd")

func _init():
	seed(21)
	var CharacterScript = load("res://shared/character.gd")
	var cm = CombatManager.new(); root.add_child(cm)
	var ch = CharacterScript.new()
	ch.initialize("p", "Fighter", "Human")
	for _i in range(29): ch.level_up()

	print("\n=== OFFER SHAPE (what the client is dealt) ===")
	for ability in ["cleave", "iron_skin", "sabotage"]:
		var offer: Array = cm._build_upgrade_offer(ch, ability, 4)
		var names: Array = []
		for o in offer: names.append(String(o["name"]) + ("*" if bool(o["tradeoff"]) else ""))
		print("  %-10s %d dealt, reveal %d, pick 1" % [ability, offer.size(), CU.REVEALS_ALLOWED])
		print("      %s" % "  ".join(names))

	print("\n=== IS THE OFFER STABLE? (a reconnect must not re-roll it) ===")
	var a: Array = cm._build_upgrade_offer(ch, "cleave", 4)
	var b: Array = cm._build_upgrade_offer(ch, "cleave", 4)
	var ids_a: Array = []
	var ids_b: Array = []
	for o in a: ids_a.append(String(o["id"]))
	for o in b: ids_b.append(String(o["id"]))
	print("  two draws differ: %s  -> which is WHY the offer is drawn once and PERSISTED" % str(ids_a != ids_b))

	print("\n=== ALREADY-TAKEN NON-STACKING UPGRADES ARE NOT RE-OFFERED ===")
	ch.ability_milestone_picks["cleave"] = ["executioner", "leeching", "opener"]
	var o2: Array = cm._build_upgrade_offer(ch, "cleave", 4)
	var bad: Array = []
	for o in o2:
		if String(o["id"]) in ["executioner", "leeching", "opener"]:
			bad.append(String(o["id"]))
	print("  re-offered already-taken: %s  %s" % [str(bad), "ok" if bad.is_empty() else "*** BUG ***"])

	print("\n=== CO-OP: does a party member's card carry its upgrades? ===")
	# The party path resolves through the SAME apply_skill_damage_bonus on a member view, so an
	# upgrade taken by a member applies in co-op automatically. Verify rather than assume.
	var m = CharacterScript.new()
	m.initialize("member", "Fighter", "Human")
	for _i in range(29): m.level_up()
	m.ability_milestone_picks["cleave"] = ["executioner"]
	var mon := {"max_hp": 1000, "current_hp": 100}   # wounded -> executioner should fire
	var view := {"character": m, "monster": mon, "round": 2, "combat_hand": ["cleave"]}
	var with_up := cm.apply_skill_damage_bonus(m, "cleave", 1000, view)
	m.ability_milestone_picks["cleave"] = []
	var without := cm.apply_skill_damage_bonus(m, "cleave", 1000, view)
	print("  member view, wounded foe: %d with Executioner vs %d without  -> %s" % [
		with_up, without, "applies in co-op" if with_up > without else "*** NOT APPLIED ***"])
	quit()
