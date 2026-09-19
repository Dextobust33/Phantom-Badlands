extends SceneTree
const DropTables := preload("res://shared/drop_tables.gd")
func _init() -> void:
	var by_stat := {}
	for pool_name in ["PREFIX_POOL", "SUFFIX_POOL"]:
		if not (pool_name in DropTables):
			continue
		for e in DropTables.get(pool_name):
			var st := ""
			for k in e.keys():
				if String(k).ends_with("_bonus"):
					st = String(k)
			if st == "":
				continue
			by_stat[st] = int(by_stat.get(st, 0)) + 1
	var keys: Array = by_stat.keys()
	keys.sort()
	print("")
	print("HOW MANY AFFIX NAMES GRANT EACH STAT")
	for k in keys:
		print("  %-20s %d affix name(s)" % [k, by_stat[k]])
	print("")
	print("  a player wanting 'keep HP and Wits' must tick %d + %d = %d names"
		% [by_stat.get("hp_bonus", 0), by_stat.get("wits_bonus", 0),
		   int(by_stat.get("hp_bonus", 0)) + int(by_stat.get("wits_bonus", 0))])
	quit()
