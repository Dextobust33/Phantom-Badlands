extends SceneTree
func _init():
	var MA = load("res://client/monster_art.gd")
	for n in ["Orc", "Orc Warrior", "Venomous Orc", "Corrupted Orc", "Orc Lv 2", "Young Orc"]:
		var key = MA.resolve_art_key(n)
		var art = MA.get_art_map().get(key, "")
		print("%-16s -> key='%s'  art_len=%d %s" % [n, key, String(art).length(), "<-- MISSING" if String(art).length() == 0 else ""])
	quit()
