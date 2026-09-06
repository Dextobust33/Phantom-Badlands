# Does every Read stack now buy something? Before this, the cap ate stacks 3-5.
extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")
const MonsterDatabase = preload("res://shared/monster_database.gd")

func _init():
	var CharacterScript = load("res://shared/character.gd")
	var cm = CombatManager.new(); var md = MonsterDatabase.new()
	root.add_child(cm); root.add_child(md); cm.monster_database = md
	print("\n=== OUTSMART vs READ STACKS (same-level Gnoll) ===")
	for case in [["Ranger","wits"],["Wizard","intelligence"],["Fighter","strength"]]:
		for lvl in [5, 30]:
			var ch = CharacterScript.new()
			ch.initialize("probe", String(case[0]), "Human")
			for i in range(max(0, lvl-1)): ch.level_up()
			while ch.unspent_stat_points > 0: ch.spend_stat_point(String(case[1]))
			var mon = md.scale_monster_to_level(md.get_monster_base_stats(MonsterDatabase.MonsterType.GNOLL), lvl, true)
			var row := "  %-8s L%-4d " % [String(case[0]), lvl]
			var prev := -1
			var dead := 0
			for read in range(0, CombatManager.COMBO_MAX + 1):
				var c := {"character": ch, "monster": mon, "combo": read}
				var pct: int = cm.assassinate_chance(ch, mon, c)
				row += "%3d%% " % pct
				if prev == pct:
					dead += 1
				prev = pct
			print(row + ("   <- %d dead stacks" % dead if dead > 0 else "   all stacks pay"))
	print("\nColumns are Read 0..COMBO_MAX.")
	quit()
