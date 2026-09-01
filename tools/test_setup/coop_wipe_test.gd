# Party WIPE: every member dies in the same round. Checks the engine end of the path that
# consistent permadeath now hangs off — the round must resolve, report combat_ended without a
# victory, mark everyone dead, and leave no alive members.
extends SceneTree

func _init():
	seed(31)
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
	for pid in [1, 2]:
		var ch = CharacterScript.new()
		ch.initialize("p%d" % pid, "Fighter", "Human")
		for i in range(4): ch.level_up()
		chars[pid] = ch

	# A monster well above them, and both members on 1 HP.
	var mname = monster_db.get_random_monster_name_from_tier(4)
	var monster = monster_db.generate_monster_by_name(mname, 40)
	var res = cm.start_party_combat_simul([1, 2], chars, monster)
	print("start ok=%s vs %s L40" % [str(res.get("success")), mname])
	var combat = cm.active_party_combats[1]
	combat.monster["max_hp"] = 999999
	combat.monster["current_hp"] = 999999

	var ended := false
	var victory := true
	for rnd in range(8):
		for pid in [1, 2]:
			if not combat.member_states[pid].get("dead", false):
				chars[pid].current_hp = 1        # keep them one hit from death
				cm.submit_party_action(1, pid, {"kind": "attack"})
		var rr = cm.resolve_party_round(1)
		var dead := []
		for pid in [1, 2]:
			if combat.member_states[pid].get("dead", false): dead.append(pid)
		print("round %d: ended=%-5s victory=%-5s dead=%s alive=%d" % [
			rnd + 1, str(rr.get("combat_ended", false)), str(rr.get("victory", false)),
			str(dead), cm._party_alive_members(combat).size()])
		if rr.get("combat_ended", false):
			ended = true
			victory = rr.get("victory", false)
			break
	print("")
	print("combat ended on a wipe        : %s  (must be true)" % str(ended))
	print("reported as NOT a victory     : %s  (must be true)" % str(not victory))
	print("both members flagged dead     : %s  (must be true)" % str(
		combat.member_states[1].get("dead", false) and combat.member_states[2].get("dead", false)))
	print("no alive members left         : %s  (must be true)" % str(cm._party_alive_members(combat).is_empty()))
	quit()
