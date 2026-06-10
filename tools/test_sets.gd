extends SceneTree
func _init():
	var dt = load("res://shared/drop_tables.gd").new()
	var udb = load("res://shared/unique_database.gd")
	# Every set piece generates
	var fails = 0
	for sid in udb.SETS:
		for pid in udb.SETS[sid]["pieces"]:
			var item = dt.generate_unique(pid, 30)
			if not (item.get("is_set_piece", false) and item.get("set_id") == sid and item.get("level", 0) > 0):
				fails += 1
				print("FAIL piece: %s -> %s" % [pid, item])
	# Set bonus aggregation on a real character
	var ch = load("res://shared/character.gd").new()
	ch.class_type = "Fighter"
	ch.equipped["weapon"] = dt.generate_unique("gravewalkers_cleaver", 30)
	ch.equipped["shield"] = dt.generate_unique("gravewalkers_bulwark", 30)
	print("2pc defense_pct: %s (expect 10) | kill_cleanse: %s (expect 1) | death_save: %s (expect 0)" % [ch.get_path_effect_total("defense_pct"), ch.get_path_effect_total("kill_cleanse"), ch.get_path_effect_total("death_save_per_combat")])
	ch.equipped["helm"] = dt.generate_unique("gravewalkers_visage", 30)
	print("3pc death_save: %s (expect 1) | low_hp: %s (expect 20) | defense still: %s (expect 10)" % [ch.get_path_effect_total("death_save_per_combat"), ch.get_path_effect_total("low_hp_damage_pct"), ch.get_path_effect_total("defense_pct")])
	# Unique + set stacking
	ch.equipped["amulet"] = dt.generate_unique("juggernauts_heart", 30)
	print("with Juggernaut's Heart: stun_immune %s (expect 1) | defense_pct %s (expect 20)" % [ch.get_path_effect_total("stun_immune"), ch.get_path_effect_total("defense_pct")])
	# Pool sanity
	var pool_hits = {}
	for i in range(2000):
		pool_hits[udb.random_named_drop_id()] = true
	print("distinct named drops seen in 2000 rolls: %d (expect 24)" % pool_hits.size())
	print("fails: %d" % fails)
	quit()
