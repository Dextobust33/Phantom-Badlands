extends SceneTree
## One-off: the odds a summoning scroll hands you a Juggernaut Swift Elder Lich.
## Rolled rather than reasoned about - the gates interact (a rare variant or an elite BLOCKS the
## empowered roll entirely), and that is exactly the sort of thing hand arithmetic gets wrong.
const MonsterDB = preload("res://shared/monster_database.gd")

func _init() -> void:
	var db = MonsterDB.new()
	var n := 400000
	var lvl := 60          # any area level >= 40 behaves the same for the mod-count gates

	var empowered := 0
	var two_mods := 0
	var want_either := 0
	var want_exact_name := 0
	var rare := 0
	for i in range(n):
		var m: Dictionary = db.generate_monster_by_name("Elder Lich", lvl)
		if m.is_empty():
			continue
		var mods: Array = m.get("empowered_mods", [])
		if not mods.is_empty():
			empowered += 1
		if mods.size() == 2:
			two_mods += 1
			if ("juggernaut" in mods) and ("swift" in mods):
				want_either += 1
				if String(m.get("name", "")).begins_with("Juggernaut Swift"):
					want_exact_name += 1
		if String(m.get("variant_type", "")) != "":
			rare += 1

	print("Elder Lich summoned at level %d, %d rolls" % [lvl, n])
	print("  a legacy variant or elite fired (blocks Empowered): %.2f%%" % (float(rare) / float(n) * 100.0))
	print("  Empowered at all:                                   %.2f%%" % (float(empowered) / float(n) * 100.0))
	print("  Empowered with exactly TWO modifiers:               %.2f%%" % (float(two_mods) / float(n) * 100.0))
	print("  ...and those two are Juggernaut + Swift:            %.4f%%  (1 in %d)" % [
		float(want_either) / float(n) * 100.0,
		int(round(float(n) / maxf(1.0, float(want_either))))])
	print("  ...named exactly 'Juggernaut Swift Elder Lich':     %.4f%%  (1 in %d)" % [
		float(want_exact_name) / float(n) * 100.0,
		int(round(float(n) / maxf(1.0, float(want_exact_name))))])
	quit(0)
