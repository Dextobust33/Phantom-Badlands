# Co-op Outsmart + party resource regen. Both reported broken from a live playtest:
# "Outsmart shows 0% chance under the Read dots" and "attacked for a round but it didn't
# provide any energy back".
extends SceneTree

func _init():
	seed(11)
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

	var chars = {}
	var ranger = CharacterScript.new()
	ranger.initialize("ranger", "Ranger", "Human")
	for i in range(9): ranger.level_up()
	while ranger.unspent_stat_points > 0: ranger.spend_stat_point("wits")
	chars[1] = ranger
	var wiz = CharacterScript.new()
	wiz.initialize("wiz", "Wizard", "Human")
	for i in range(9): wiz.level_up()
	chars[2] = wiz

	var monster = monster_db.generate_monster_by_name("Wolf", 10)
	cm.start_party_combat_simul([1, 2], chars, monster)
	var combat = cm.active_party_combats[1]

	print("\n=== 1. DOES ENERGY REGENERATE OVER A PARTY ROUND? ===")
	ranger.current_energy = 10
	print("   energy before round: %d / %d" % [ranger.current_energy, ranger.get_total_max_energy()])
	var mhp_before: int = int(combat.monster.get("current_hp", 0))
	cm.submit_party_action(1, 1, {"kind": "attack"})
	cm.submit_party_action(1, 2, {"kind": "attack"})
	# Submitting only QUEUES the action; the server resolves the round separately. Leaving this
	# out made the first version of this test report "no regen" when no round had actually run.
	cm.resolve_party_round(1)
	print("   monster HP %d -> %d (a drop proves the round really resolved)" % [
		mhp_before, int(combat.monster.get("current_hp", 0))])
	print("   energy after  round: %d   %s" % [ranger.current_energy,
		"OK (regen applied)" if ranger.current_energy > 10 else "*** NO REGEN ***"])

	print("\n=== 2. DOES OUTSMART REPORT A REAL CHANCE, AND DOES READ MOVE IT? ===")
	var st = combat.member_states[1]
	for read in [0, 2, 4, 6, 8]:
		st["combo"] = read
		st["outsmart_attempts"] = 0
		var view := {"character": ranger, "monster": combat.monster,
			"combo": read, "outsmart_attempts": 0}
		print("   Read %d/%d -> %d%%" % [read, cm.COMBO_MAX, cm._outsmart_chance(ranger, combat.monster, view)])

	print("\n=== 3. DOES A PARTY OUTSMART ACTUALLY RESOLVE? ===")
	st["combo"] = 8
	ranger.current_energy = ranger.get_total_max_energy()
	var hp_before: int = int(combat.monster.get("current_hp", 0))
	var attempts := 0
	var killed := false
	while attempts < 25 and not killed:
		attempts += 1
		st["combo"] = 8
		st["outsmart_attempts"] = 0
		ranger.current_energy = ranger.get_total_max_energy()
		combat.monster["current_hp"] = hp_before
		var entries = cm._party_outsmart(combat, 1, 0)   # commit ZERO energy — must be legal
		if int(combat.monster.get("current_hp", 1)) <= 0:
			killed = true
			print("   attempt %d: SUCCESS — monster HP driven to 0 (party victory path takes over)" % attempts)
			for e in entries:
				print("      | %s" % String(e.get("text", e.get("mine", ""))).left(90))
	if not killed:
		print("   *** 25 attempts, never succeeded — check the roll ***")
	print("\n   failure path (Read must reset to 0):")
	st["combo"] = 8
	combat.monster["current_hp"] = hp_before
	var tries := 0
	while tries < 25:
		tries += 1
		st["combo"] = 8
		combat.monster["current_hp"] = hp_before
		cm._party_outsmart(combat, 1, 0)
		if int(combat.monster.get("current_hp", 1)) > 0:
			print("      after a MISS, Read = %d  %s" % [int(st.get("combo", -1)),
				"OK" if int(st.get("combo", -1)) == 0 else "*** NOT RESET ***"])
			break
	quit()
