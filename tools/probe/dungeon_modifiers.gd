extends SceneTree
## Dungeon rarity, axis two: rolled modifiers.
##
## Owner 2026-09-13 picked all three axes. Axis two is the one that makes rank a DECISION rather
## than a number: a rarer dungeon "reads differently before you enter it". So the two things that
## actually matter here are (1) the effects are real and land on real monsters, and (2) the player
## is TOLD before the door. Under permadeath, a modifier nobody can see beforehand is just an
## unexplained death.
##
## The danger this measures for is compounding. Modifiers multiply, and a rank-9 dungeon can roll
## three at once — so the worst case is not any single line in the table, it is the product.
const ServerScript = preload("res://server/server.gd")
const DungeonDB = preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== RANK DECIDES HOW MANY, AND IT IS NOT GUARANTEED =====")
	print("  %-6s %8s %8s %8s %8s   %s" % ["rank", "0 mods", "1", "2", "3", "mean"])
	var rank1_all_plain := true
	var rank9_mean := 0.0
	for rank in [1, 2, 3, 5, 7, 9]:
		var counts := [0, 0, 0, 0]
		var total := 0
		var n := 8000
		for i in range(n):
			var m: Array = DungeonDB.roll_dungeon_modifiers(rank)
			counts[clampi(m.size(), 0, 3)] += 1
			total += m.size()
		print("  %-6d %7.1f%% %7.1f%% %7.1f%% %7.1f%%   %.2f" % [rank,
			float(counts[0]) / float(n) * 100.0, float(counts[1]) / float(n) * 100.0,
			float(counts[2]) / float(n) * 100.0, float(counts[3]) / float(n) * 100.0,
			float(total) / float(n)])
		if rank <= 2 and counts[0] != n:
			rank1_all_plain = false
		if rank == 9:
			rank9_mean = float(total) / float(n)
	ck(rank1_all_plain,
		"rank 1-2 dungeons are always plain - you have to see an ordinary one first")
	ck(rank9_mean > 1.5 and rank9_mean < 2.6,
		"a rank-9 dungeon averages %.2f modifiers" % rank9_mean)

	print("")
	print("===== NO MODIFIER IS A PUNISHMENT WITHOUT A PRICE =====")
	# The whole design claim is that each one is a trade. A modifier that made a dungeon harder
	# and paid nothing would be a reason to avoid rank, which is the opposite of the point.
	for mid in DungeonDB.DUNGEON_MODIFIERS:
		var d: Dictionary = DungeonDB.DUNGEON_MODIFIERS[mid]
		var harder: bool = (float(d.get("hp_mult", 1.0)) > 1.0 or float(d.get("str_mult", 1.0)) > 1.0
			or float(d.get("def_mult", 1.0)) > 1.0 or float(d.get("count_mult", 1.0)) > 1.0)
		var pays: bool = float(d.get("xp_mult", 1.0)) > 1.0 or float(d.get("loot_bonus", 0.0)) > 0.0
		ck(harder and pays, "  %-12s is both harder and better paid" % String(d.get("name", mid)))
		ck(String(d.get("blurb", "")) != "", "  %-12s has something to say to the player" % String(d.get("name", mid)))

	print("")
	print("===== THE COMPOUNDED WORST CASE =====")
	# Not any single row - the product of the three nastiest, which a rank-9 dungeon can roll.
	# Each dimension is maximised SEPARATELY. The first version of this scored combinations by
	# hp*str*def and then compared that product against hp*str - an inconsistent comparison that
	# could report a combination as "the worst" while a different one hit harder. A bound derived
	# from the wrong worst case is a false all-clear, which is worse than no bound at all.
	var all_ids: Array = DungeonDB.DUNGEON_MODIFIERS.keys()
	var dims := ["hp_mult", "str_mult", "def_mult", "count_mult"]
	var worst := {}
	var worst_of := {}
	for d in dims:
		worst[d] = 1.0
		worst_of[d] = []
	var least_paid := 999.0
	for a in all_ids:
		for b in all_ids:
			for c in all_ids:
				if a == b or b == c or a == c:
					continue
				var e: Dictionary = DungeonDB.modifier_effects([a, b, c])
				for d in dims:
					if float(e[d]) > float(worst[d]):
						worst[d] = float(e[d])
						worst_of[d] = [a, b, c]
				var pay: float = float(e["xp_mult"]) + float(e["loot_bonus"])
				least_paid = minf(least_paid, pay)
	for d in dims:
		print("  worst %-11s x%.2f  (%s)" % [d, worst[d], ", ".join(worst_of[d])])
	ck(float(worst["hp_mult"]) <= 2.0, "monster HP never more than doubles (x%.2f)" % worst["hp_mult"])
	ck(float(worst["str_mult"]) <= 1.6, "monster damage never gets past +60%% (x%.2f)" % worst["str_mult"])
	ck(float(worst["def_mult"]) <= 1.6, "and armour stays reachable (x%.2f)" % worst["def_mult"])
	ck(float(worst["count_mult"]) <= 2.0, "a floor never more than doubles its population (x%.2f)" % worst["count_mult"])
	ck(least_paid > 1.0, "every three-modifier roll in the table pays something (min %.2f)" % least_paid)

	print("")
	print("===== THE EFFECTS LAND ON A REAL MONSTER =====")
	# Executed, not reasoned about: the same helper the two dungeon combat starters call.
	var srv = ServerScript.new()
	srv.active_dungeons = {"plain": {"sub_tier": 1, "modifiers": []},
						   "nasty": {"sub_tier": 9, "modifiers": ["bloodgorged", "feverish"]}}
	var base := {"name": "Ghoul", "max_hp": 1000, "current_hp": 1000, "strength": 100,
				 "defense": 50, "experience_reward": 200}
	var plain: Dictionary = base.duplicate(true)
	srv._apply_dungeon_modifiers_to_monster(plain, "plain")
	ck(int(plain["max_hp"]) == 1000 and int(plain["strength"]) == 100,
		"a dungeon with no modifiers changes nothing at all")
	var nasty: Dictionary = base.duplicate(true)
	srv._apply_dungeon_modifiers_to_monster(nasty, "nasty")
	print("  Bloodgorged + Feverish: hp %d -> %d, str %d -> %d, xp %d -> %d" % [
		1000, int(nasty["max_hp"]), 100, int(nasty["strength"]), 200, int(nasty["experience_reward"])])
	ck(int(nasty["max_hp"]) == 1400, "Bloodgorged puts HP at 1400")
	ck(int(nasty["strength"]) == 125, "Feverish puts damage at 125")
	ck(int(nasty["current_hp"]) == int(nasty["max_hp"]),
		"and it arrives at full health, not at its old HP in a bigger bar")
	ck(int(nasty["experience_reward"]) > 200,
		"the reward rode along (%d)" % int(nasty["experience_reward"]))

	print("")
	print("===== AND THE LOOT BONUS REACHES THE LADDER =====")
	var plain_up := 0
	var rich_up := 0
	for i in range(20000):
		if srv._dungeon_loot_rarity_upgrade(5, 0.0) > 0:
			plain_up += 1
		if srv._dungeon_loot_rarity_upgrade(5, 0.25) > 0:
			rich_up += 1
	print("  rank 5: %.1f%% of drops upgrade plain, %.1f%% under Gilded Rot" % [
		float(plain_up) / 200.0, float(rich_up) / 200.0])
	ck(rich_up > plain_up, "Gilded Rot actually improves what you find")

	print("")
	print("===== THE PLAYER IS TOLD BEFORE THE DOOR =====")
	var lines: Array = DungeonDB.modifier_lines(["bloodgorged", "gilded_rot"])
	ck(lines.size() == 2, "every modifier produces a line (%d)" % lines.size())
	for l in lines:
		print("    " + String(l))
	ck(String(lines[0]).contains("Bloodgorged"), "  named")
	ck(String(lines[0]).contains("[color="), "  and coloured, so it reads as a callout not a footnote")
	ck(DungeonDB.modifier_lines([]).is_empty(), "a plain dungeon says nothing extra")
	ck(DungeonDB.modifier_lines(["not_a_real_modifier"]).is_empty(),
		"and an unknown id is skipped rather than printing a blank bullet")

	print("")
	print("----- NOT COVERED HERE, and saying so rather than implying otherwise -----")
	print("  `modifier_lines` is proven above. Whether handle_dungeon_enter actually CALLS it on")
	print("  the warning screen is not exercised by this probe - that path wants a world_system,")
	print("  a chunk_manager and a live peer to capture the message. It is the same gap that let")
	print("  the v0.9.774 figure fix ship twice under a branch that could not run, so it needs a")
	print("  LIVE check: walk onto a rank 6+ dungeon and read the entry prompt.")

	print("")
	if fails == 0:
		print("PASS - modifiers are real, bounded, paid for, and visible before you commit")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
