# Do the new rank-up upgrades ACTUALLY DO SOMETHING? The owner's complaint about the old set
# was that options were "useless or non working" - so every one that ships must be measurable.
extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")
const MonsterDatabase = preload("res://shared/monster_database.gd")
const CU = preload("res://shared/card_upgrades.gd")

func _init():
	seed(9)
	var CharacterScript = load("res://shared/character.gd")
	var cm = CombatManager.new(); var md = MonsterDatabase.new()
	root.add_child(cm); root.add_child(md); cm.monster_database = md

	print("\n=== DAMAGE-SIDE UPGRADES: mean damage over 200 casts, vs no upgrade ===")
	print("%-16s %10s %9s  %s" % ["upgrade", "mean dmg", "vs base", "verdict"])
	var base := _mean(cm, CharacterScript, md, [], 200, false)
	print("%-16s %10.0f %8s  %s" % ["(none)", base, "-", "baseline"])
	for up in ["executioner", "overdraw", "reckless", "brittle", "greedy", "wild_swing", "all_in", "slow_burn", "hair_trigger", "gamblers_cut"]:
		var m := _mean(cm, CharacterScript, md, [up], 200, up == "executioner")
		var ratio := m / maxf(1.0, base)
		print("%-16s %10.0f %8.2fx  %s" % [up, m, ratio,
			"ok" if absf(ratio - 1.0) > 0.05 else "*** NO EFFECT ***"])

	print("
=== WIRED vs MERELY DEFINED ===")
	# An honest list of what combat code actually consumes today. Anything in the pool but NOT
	# here would be offered to the player and do nothing - the exact defect this redesign exists
	# to remove - so the gap must be visible rather than assumed away.
	var wired := ["power","efficiency","rider","duration",
		"executioner","opener","leeching","momentum_feed","refund",
		"overdraw","reckless","brittle","greedy","wild_swing","all_in","slow_burn",
		"hair_trigger","gamblers_cut","sacrificial",
		"concentrated","costly_vigil","fragile_ward","slow_cast","reckless_guard",
		"swift","warding","unsettling",
		"keen","preload","shared","bloodprice","provoking","unstable_hex"]
	var pending: Array = []
	for u in CU.UPGRADES:
		if not (String(u["id"]) in wired):
			pending.append(String(u["id"]))
	print("  pool %d   wired %d   NOT YET WIRED %d" % [CU.UPGRADES.size(), wired.size(), pending.size()])
	print("  pending: %s" % ", ".join(pending))
	quit()

func _mean(cm, CharacterScript, md, picks: Array, n: int, hurt_monster: bool) -> float:
	var tot := 0.0
	for i in range(n):
		var ch = CharacterScript.new()
		ch.initialize("p", "Fighter", "Human")
		for _l in range(29): ch.level_up()
		while ch.unspent_stat_points > 0: ch.spend_stat_point("strength")
		if not picks.is_empty():
			ch.ability_milestone_picks["cleave"] = picks.duplicate()
		var mon = md.scale_monster_to_level(md.get_monster_base_stats(MonsterDatabase.MonsterType.GNOLL), 30, true)
		mon["max_hp"] = 100000; mon["current_hp"] = 20000 if hurt_monster else 100000
		if hurt_monster: mon["max_hp"] = 100000
		var combat := {"character": ch, "monster": mon, "round": 2, "combat_hand": ["cleave"]}
		tot += float(cm.apply_skill_damage_bonus(ch, "cleave", 1000, combat))
	return tot / float(n)
