extends SceneTree
## Does a player get TOLD what the monster in front of them does?
##
## A player died at leaderboard position 14 to a Titan's Glass Cannon - triple damage - which was
## printed once in the encounter line and then buried by the fight. Fixing where it is shown
## exposed the bigger problem: MONSTER_TRAITS had 20 entries against 95 ability constants, and the
## client kept its OWN list covering four combat abilities the shared table did not. The table's
## own header says it exists because "a list you have to remember to add to is a list that will be
## incomplete". It was incomplete in exactly that way.
##
## This probe is the thing that notices next time. It fails when a non-boss ability that a monster
## can actually carry has no entry, so the list cannot silently fall behind again.
const CombatMgr = preload("res://shared/combat_manager.gd")
const MonsterDB = preload("res://shared/monster_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== EVERY ABILITY A MONSTER ACTUALLY CARRIES HAS A DESCRIPTION =====")
	# Drawn from the SPECIES TABLES, not from the constant list: what matters is what a player can
	# meet, and several constants are legacy or boss-only. gold_hoarder, for instance, is marked
	# "Legacy - no effect (gold removed)" and deliberately has no chip: a trait that promises
	# something the game no longer does is worse than no trait at all.
	var db = MonsterDB.new()
	var carried := {}
	for tier in range(1, 10):
		for mt in db._get_tier_monsters(tier):
			var base: Dictionary = db.get_monster_base_stats(mt)
			for ab in base.get("abilities", []):
				carried[String(ab)] = String(base.get("name", "?"))

	var missing: Array = []
	for ab in carried:
		if String(ab).begins_with("boss_"):
			continue          # boss signatures announce themselves in combat
		if ab == "gold_hoarder":
			continue          # legacy, no effect
		if not CombatMgr.MONSTER_TRAITS.has(ab):
			missing.append("%s (on %s)" % [ab, carried[ab]])
	print("  %d distinct abilities are carried by real species" % carried.size())
	if not missing.is_empty():
		print("  WITHOUT a description:")
		for m in missing:
			print("    " + String(m))
	ck(missing.is_empty(), "every carried, non-boss ability has an entry (%d missing)" % missing.size())

	print("")
	print("===== THE ONE THAT KILLED SOMEBODY =====")
	var titan: Array = db.get_monster_base_stats(MonsterDB.MonsterType.TITAN).get("abilities", [])
	print("  Titan carries: %s" % str(titan))
	var chips := CombatMgr.combat_trait_tags(titan)
	ck(chips.contains("Glass Cannon"), "a Titan advertises Glass Cannon on the combat screen")
	ck(chips.contains("three times as hard"), "  ...and says what it means when hovered")
	ck(not chips.contains("Gem Bearer"), "  ...while its LOOT traits stay off the combat screen")

	print("")
	print("===== DESCRIPTIONS ARE REAL, NOT PLACEHOLDERS =====")
	var empty: Array = []
	var short_ones: Array = []
	for k in CombatMgr.MONSTER_TRAITS:
		var d: String = String(CombatMgr.MONSTER_TRAITS[k].get("desc", ""))
		if d == "":
			empty.append(k)
		elif d.length() < 20:
			short_ones.append(k)
	ck(empty.is_empty(), "no trait has an empty description (%d)" % empty.size())
	ck(short_ones.is_empty(), "and none is a stub (%d under 20 chars)" % short_ones.size())

	var no_label: Array = []
	for k in CombatMgr.MONSTER_TRAITS:
		if String(CombatMgr.MONSTER_TRAITS[k].get("label", "")) == "":
			no_label.append(k)
	ck(no_label.is_empty(), "every trait has a label to show")

	print("")
	print("===== A LOOT TRAIT IS NEVER MISTAKEN FOR A DANGER =====")
	# The split is what keeps the combat screen readable. Anything NOT flagged `loot` shows,
	# so a trait added later is visible by default - the right way round, given the report.
	var loot_only := CombatMgr.combat_trait_tags(["gem_bearer", "wish_granter", "warrior_hoarder"])
	ck(loot_only == "", "a monster whose only traits are loot ones shows no combat chips")
	var mixed := CombatMgr.combat_trait_tags(["gem_bearer", "multi_strike"])
	ck(mixed.contains("Multi-Strike") and not mixed.contains("Gem Bearer"),
		"and a mixed monster shows only the dangerous half")

	print("")
	if fails == 0:
		print("PASS - a player can see what the thing in front of them does")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
