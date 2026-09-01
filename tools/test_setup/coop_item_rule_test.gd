# v0.9.739 co-op item rule: first item each round is FREE per member (they may still act);
# a second SPENDS that member's action only. Five members each using one = all free.
extends SceneTree

func _init():
	seed(5)
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
	for pid in [1, 2, 3]:
		var ch = CharacterScript.new()
		ch.initialize("p%d" % pid, "Fighter", "Human")
		for i in range(9): ch.level_up()
		# give each of them a stack of potions
		for j in range(6):
			ch.add_item({"name": "Health Potion", "type": "health_potion", "item_type": "health_potion", "tier": 1,
				"is_consumable": true, "quantity": 1, "heal_amount": 30, "value": 10})
		chars[pid] = ch

	var mname = monster_db.get_random_monster_name_from_tier(2)
	var monster = monster_db.generate_monster_by_name(mname, 11)
	cm.start_party_combat_simul([1, 2, 3], chars, monster)
	var combat = cm.active_party_combats[1]
	for pid in [1, 2, 3]:
		chars[pid].current_hp = 20   # hurt, so potions actually apply

	print("--- round 1: every member uses ONE item ---")
	var all_free := true
	for pid in [1, 2, 3]:
		var r = cm.party_use_item(1, pid, 0, "self")
		print("   p%d ok=%s msg=%s spent_action=%s" % [pid, str(r.get("success")), str(r.get("message","")), str(r.get("spent_action"))])
		if r.get("spent_action", true): all_free = false
	print("   all three were FREE: %s  (must be true)" % all_free)

	print("--- p1 uses a SECOND item in the same round ---")
	var r2 = cm.party_use_item(1, 1, 0, "self")
	print("   p1 ok=%s spent_action=%s  (spent must be true)" % [str(r2.get("success")), str(r2.get("spent_action"))])
	print("   p2 still free-flagged only: %s" % str(combat.member_states[2].get("free_item_used")))

	print("--- resolve the round, then check the flag resets ---")
	for pid in [1, 2, 3]:
		cm.submit_party_action(1, pid, {"kind": "attack"})
	cm.resolve_party_round(1)
	var reset_ok := true
	for pid in [1, 2, 3]:
		if bool(combat.member_states[pid].get("free_item_used", false)): reset_ok = false
	print("   free_item_used reset for everyone after the round: %s  (must be true)" % reset_ok)

	print("--- next round: p1's first item is free again ---")
	var r3 = cm.party_use_item(1, 1, 0, "self")
	print("   p1 spent_action=%s  (must be false)" % str(r3.get("spent_action")))
	quit()
