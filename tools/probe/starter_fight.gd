# What a fresh, gearless character actually faces coming out of the starter post.
extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")
const MonsterDatabase = preload("res://shared/monster_database.gd")

func _init():
	var CharacterScript = load("res://shared/character.gd")
	var cm = CombatManager.new(); var md = MonsterDatabase.new()
	root.add_child(cm); root.add_child(md); cm.monster_database = md

	print("\n=== STARTER FIGHT: gearless character vs a same-level Gnoll ===")
	var base = md.get_monster_base_stats(MonsterDatabase.MonsterType.GNOLL)
	for lvl in [3, 5, 8]:
		var m = md.scale_monster_to_level(base, lvl, true)
		print("\n--- Level %d | Gnoll HP=%d STR=%d DEF=%d" % [
			lvl, int(m.get("max_hp",0)), int(m.get("strength",0)), int(m.get("defense",0))])
		print("  %-10s %7s %7s %10s %8s %14s %12s" % ["class","maxHP","attack","best hit","basic","turns to kill","you survive"])
		for case in [["Fighter","strength"],["Wizard","intelligence"],["Ranger","wits"]]:
			var ch = CharacterScript.new()
			ch.initialize("probe", String(case[0]), "Human")
			for i in range(max(0, lvl-1)): ch.level_up()
			while ch.unspent_stat_points > 0: ch.spend_stat_point(String(case[1]))
			var atk: int = ch.get_total_attack()
			var s_str: int = ch.get_effective_stat("strength")
			var s_wit: int = ch.get_effective_stat("wits")
			var best: float = 0.0
			match String(case[0]):
				"Fighter":
					best = maxf(cm._ability_anchored_damage(ch, "strength", CombatManager.ABILITY_WEIGHTS["cleave"]),
								float(atk) * 7.0 * (1.0 + sqrt(float(s_str))/10.0))
				"Wizard":
					best = cm._ability_anchored_damage(ch, "intelligence", CombatManager.ABILITY_WEIGHTS["magic_bolt"])
				"Ranger":
					best = float(atk) * 4.5 * (1.0 + sqrt(float(s_wit))/10.0)
			var dfn: float = float(m.get("defense", 0))
			var mitig: float = dfn / (dfn + 100.0) * 0.6
			var eff_best: float = best * (1.0 - mitig)
			var basic: float = float(atk) * (1.0 - mitig)
			var turns: float = float(m.get("max_hp", 1)) / maxf(1.0, eff_best)
			var incoming: float = maxf(1.0, float(m.get("strength", 1)) * 0.75)
			print("  %-10s %7d %7d %10.0f %8.0f %13.1f %11.1f" % [
				String(case[0]), ch.get_total_max_hp(), atk, eff_best, basic, turns,
				float(ch.get_total_max_hp()) / incoming])
	quit()
