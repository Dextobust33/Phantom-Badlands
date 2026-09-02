# Item targeting: the item leaves the USER's inventory, but the effect lands on the chosen
# teammate (or their companion). Solo behaviour must be unchanged.
extends SceneTree

func _init():
	seed(21)
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
		for i in range(9): ch.level_up()
		for j in range(4):
			ch.add_item({"name": "Health Potion", "type": "health_potion", "item_type": "health_potion",
				"is_consumable": true, "quantity": 1, "tier": 1, "level": 1, "value": 25})
		chars[pid] = ch

	var mname = monster_db.get_random_monster_name_from_tier(2)
	cm.start_party_combat_simul([1, 2], chars, monster_db.generate_monster_by_name(mname, 11))

	chars[1].current_hp = 40
	chars[2].current_hp = 40
	var p1_before := int(chars[1].current_hp)
	var p2_before := int(chars[2].current_hp)
	var inv1_before: int = chars[1].inventory.size()

	# p1 uses a potion ON p2
	var r = cm.party_use_item(1, 1, 0, "pid:2")
	print("use on teammate ok=%s" % str(r.get("success")))
	print("  p1 hp %d -> %d   (must be unchanged)" % [p1_before, int(chars[1].current_hp)])
	print("  p2 hp %d -> %d   (must INCREASE)" % [p2_before, int(chars[2].current_hp)])
	print("  p1 inventory %d -> %d  (the USER pays the item)" % [inv1_before, chars[1].inventory.size()])
	print("")
	# self-target still works
	var p1b := int(chars[1].current_hp)
	var r2 = cm.party_use_item(1, 1, 0, "self")
	print("use on self ok=%s   p1 hp %d -> %d (must INCREASE)" % [str(r2.get("success")), p1b, int(chars[1].current_hp)])
	print("")
	# a target who is not in the fight is refused
	var r3 = cm.party_use_item(1, 1, 0, "pid:99")
	print("unknown target refused: %s  (%s)" % [str(not r3.get("success", false)), str(r3.get("message", ""))])
	quit()
