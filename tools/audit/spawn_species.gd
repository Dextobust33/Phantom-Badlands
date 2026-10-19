extends SceneTree
# Prints the species the game can ACTUALLY spawn at a level, with rough frequency.
# Exists because a playtest was run against `/spawnmonster Orc 50` — an Orc is tier 2 and has a
# 0% spawn rate at L50, so the whole test measured a monster no player meets there.
const MonsterDB = preload("res://shared/monster_database.gd")

func _init():
	var lvl := 50
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			lvl = int(a)
	var mdb = MonsterDB.new()
	var seen := {}
	var N := 600
	for i in range(N):
		var t = mdb.select_monster_type(lvl)
		var nm := String(mdb.get_monster_base_stats(t).get("name", "?"))
		seen[nm] = int(seen.get(nm, 0)) + 1
	var names: Array = seen.keys()
	names.sort_custom(func(a, b): return int(seen[a]) > int(seen[b]))
	print("\nSpecies actually spawnable at L%d (sampled %d):" % [lvl, N])
	for nm in names:
		var pct := 100.0 * float(seen[nm]) / float(N)
		if pct < 1.0:
			continue
		var apex := "  <-- APEX, deliberately brutal" if mdb.APEX_SPECIES.has(nm) else ""
		print("   %5.1f%%  %s%s" % [pct, nm, apex])
	quit()
