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
	# ⛑ THE LIST IS DERIVED, BECAUSE THE HAND-TYPED ONE LIED. This block used to carry a
	# literal array of "wired" ids maintained by hand, and it had gone stale: it reported 23
	# upgrades "NOT YET WIRED" while several of them were plainly consumed - `bulwark` is read at
	# combat_manager.gd:7785, and the Executioner family at :8084. A stale list reads as a real
	# finding, which is worse than no list at all: it sends someone to wire something twice.
	#
	# An upgrade is consumed by its QUOTED ID in combat code (`"executioner" in picks`,
	# `card_upgrade_count(ability, "keen")`), so the honest derivation is to search the code that
	# could consume one for the id, excluding the table that DEFINES them - a definition is not a
	# use, and counting it would mark every upgrade wired forever.
	#
	# ⛑ AND THE TWO CLAIMS ARE KEPT APART. "The code mentions this id" is not "this upgrade
	# measurably does something" - the damage section above is what PROVES the ten it covers. This
	# section can only find the ones nothing reads at all, which is a floor, not a verdict.
	var consumers: Array[String] = [
		"res://shared/combat_manager.gd", "res://shared/character.gd", "res://server/server.gd",
		"res://shared/card_gear.gd",
	]
	var code := ""
	for f in consumers:
		code += FileAccess.get_file_as_string(f)
	var referenced: Array = []
	var inert: Array = []
	for u in CU.UPGRADES:
		var uid := String(u["id"])
		if code.find("\"%s\"" % uid) >= 0:
			referenced.append(uid)
		else:
			inert.append(uid)
	print("  pool %d   read by combat code %d   READ BY NOTHING %d" % [
		CU.UPGRADES.size(), referenced.size(), inert.size()])
	if inert.is_empty():
		print("  every upgrade in the pool is read somewhere. (Read != proven; see the damage")
		print("  table above, and upgrade_new_wired.gd / upgrade_triggers.gd, for what is PROVEN.)")
	else:
		# These are offered to a player and do nothing - the exact defect this redesign exists to
		# remove - so it is a FAILURE, not a note.
		print("  *** OFFERED BUT READ BY NOTHING: %s" % ", ".join(inert))
	print("")
	if not inert.is_empty():
		print("[PROBE] FAIL %d upgrade(s) are in the pool and read by no combat code" % inert.size())
		quit(1)
		return
	print("[PROBE] PASS every offered upgrade is read by combat code")
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
