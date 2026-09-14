extends SceneTree
const MDB = preload("res://shared/monster_database.gd")
const CM = preload("res://shared/combat_manager.gd")
const Character = preload("res://shared/character.gd")
func _init() -> void:
	var db = MDB.new(); get_root().add_child(db)
	var cm = CM.new(); get_root().add_child(cm)
	await process_frame
	print("%-6s %-8s %-10s %-12s %-14s %s" % ["lvl", "playerHP", "1 hit", "as % of HP", "swift round", "% of HP"])
	for lvl in [1, 2, 5, 10, 20]:
		var pl = Character.new(); pl.initialize("P", "Fighter", "Human")
		pl.level = lvl; pl.calculate_derived_stats()
		pl.current_hp = pl.get_total_max_hp()
		var m: Dictionary = db.generate_monster(lvl, lvl)
		if m.is_empty(): continue
		# average a single hit over many rolls
		var tot := 0
		var n := 400
		for i in range(n):
			tot += cm.calculate_monster_damage(m, pl, {})
		var one := int(tot / float(n))
		var hp := pl.get_total_max_hp()
		# swift = multi_strike = 2-3 full hits
		var swift_round := int(one * 2.5)
		print("%-6d %-8d %-10d %-12s %-14d %s" % [lvl, hp, one,
			"%d%%" % int(100.0 * one / hp), swift_round, "%d%%" % int(100.0 * swift_round / hp)])
	quit(0)
