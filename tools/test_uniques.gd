extends SceneTree
func _init():
	var dt = load("res://shared/drop_tables.gd").new()
	var udb = load("res://shared/unique_database.gd")
	var fails = 0
	for uid in udb.UNIQUES:
		var item = dt.generate_unique(uid, 42)
		var ok = item.get("is_unique", false) and item.get("name") == udb.UNIQUES[uid]["name"] and item.get("level", 0) > 0 and item.get("rarity") == "artifact"
		if not ok:
			fails += 1
			print("FAIL: %s -> %s" % [uid, item])
	var sample = dt.generate_unique("bloodletters_hook", 42)
	print("sample: %s | lvl %d | rarity %s | unique_effect %s | lore '%s'" % [sample.name, sample.level, sample.rarity, sample.unique_effect, sample.lore])
	var die = dt.generate_unique("sevenfold_die", 42)
	print("sevenfold extra_turn_chance affix: %s" % die.get("affixes", {}).get("extra_turn_chance", "MISSING"))
	print("fails: %d / %d uniques" % [fails, udb.UNIQUES.size()])
	quit()
