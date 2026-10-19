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
			# BEST SUSTAINABLE cast — the card you can play every turn, which is what decides
			# whether a straight fight is winnable. Finishers/gambles are reported separately.
			var best: float = 0.0
			var burst: float = 0.0
			var burst_label := ""
			match String(case[0]):
				"Fighter":
					best = maxf(cm._ability_anchored_damage(ch, "strength", CombatManager.ABILITY_WEIGHTS["cleave"]),
								cm._ability_anchored_damage(ch, "strength", CombatManager.ABILITY_WEIGHTS["power_strike"]))
					burst = cm._ability_anchored_damage(ch, "strength",
						CombatManager.DEVASTATE_WEIGHT_PER_MOMENTUM * float(CombatManager.MOMENTUM_MAX)) * 1.5
					burst_label = "Devastate@5+full bar"
				"Wizard":
					best = cm._ability_anchored_damage(ch, "intelligence", CombatManager.ABILITY_WEIGHTS["blast"])
					burst = cm._ability_anchored_damage(ch, "intelligence", CombatManager.ABILITY_WEIGHTS["magic_bolt"])
					burst_label = "Magic Bolt (full dump)"
				"Ranger":
					best = cm._ability_anchored_damage(ch, "wits", CombatManager.ABILITY_WEIGHTS["ambush"]) * 1.25
					burst = cm._ability_anchored_damage(ch, "wits", CombatManager.ABILITY_WEIGHTS["gambit"])
					burst_label = "Gambit (on hit)"
			var dfn: float = float(m.get("defense", 0))
			var mitig: float = dfn / (dfn + 100.0) * 0.6
			var eff_best: float = best * (1.0 - mitig)
			var basic: float = float(atk) * (1.0 - mitig)
			var turns: float = float(m.get("max_hp", 1)) / maxf(1.0, eff_best)
			var incoming: float = maxf(1.0, float(m.get("strength", 1)) * 0.75)
			var survive: float = float(ch.get_total_max_hp()) / incoming
			var verdict := "ok" if turns < survive else "*** CANNOT WIN ***"
			print("  %-10s %7d %7d %10.0f %8.0f %13.1f %11.1f  %-18s %8.0f %s" % [
				String(case[0]), ch.get_total_max_hp(), atk, eff_best, basic, turns,
				survive, verdict, burst * (1.0 - mitig), burst_label])
	quit()
