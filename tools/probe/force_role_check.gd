extends SceneTree
const MonsterDB = preload("res://shared/monster_database.gd")

func _init():
	var mdb = MonsterDB.new()
	print("\n=== force_role: does it actually produce the role? ===")
	for role in ["", "empowered", "elite"]:
		var hp_tot := 0.0
		var n := 0
		var sample_name := ""
		for i in range(20):
			var m = mdb.generate_monster_by_name("Gryphon", 50, false, role)
			if m.is_empty():
				continue
			hp_tot += float(m.get("max_hp", 0))
			if sample_name == "":
				sample_name = String(m.get("name", "?"))
			n += 1
		var label = "(normal roll)" if role == "" else role
		print("  %-12s mean HP %8.0f   e.g. %s" % [label, hp_tot / maxf(1.0, n), sample_name])
	quit()
