extends SceneTree
## Is an H9 companion stronger or weaker than a G1 - and is ascending an upgrade?
##
## Owner 2026-09-11: *"we may need to compare power of companion tier and rank to see if an H9 is
## weaker or stronger than a G1."*
##
## The backlog says the answer is the bad one: rank was the whole power axis, tier very nearly
## cosmetic, and Tier Ascension therefore a TRAP - three H companions plus a Catalyst buy one G1
## with rank and level reset, so the player pays levels and a rank multiplier for a tier that buys
## almost nothing. This measures whether that is still true, because the HP formula's own comment
## says it "used to be" rank-only, and a backlog entry is not evidence.
const CharacterScript = preload("res://shared/character.gd")
const PowerRank = preload("res://shared/power_rank.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _comp(tier: int, rank: int, level: int) -> Dictionary:
	"""A companion built the way the game builds one - species bonuses and all.

	⚑ THIS USED TO PASS `"bonuses": {}`. The builders fill bonuses from `COMPANION_DATA`, and
	`calculate_companion_max_hp` multiplies by them, so comparing a synthetic bonus-less parent
	against a real ascended child measured the BONUSES as well as the tier and reported a 3x jump
	from one grade. Two things that differ in more than one way - the exact instrument defect
	CLAUDE.md lists. Only tier, rank and level may differ between the two sides."""
	var data: Dictionary = DropTablesScript.COMPANION_DATA.get("Skeleton", {})
	return {"name": "Pet", "monster_type": "Skeleton", "level": level,
		"tier": tier, "sub_tier": rank, "variant": "Normal",
		"bonuses": data.get("bonuses", {}).duplicate()}


func _hp(tier: int, rank: int, level: int) -> int:
	return CharacterScript.calculate_companion_max_hp(_comp(tier, rank, level), 4000, 50)


func _init() -> void:
	print("===== DOES TIER DO ANYTHING AT ALL? =====")
	# The original fault: HP read rank and never read tier, so a tier was worth nothing.
	var h1 := _hp(1, 1, 20)
	var g1 := _hp(2, 1, 20)
	print("  same level, same rank: H1 %d hp, G1 %d hp  (x%.2f)" % [h1, g1, float(g1) / maxf(1.0, float(h1))])
	ck(g1 > h1, "one tier up is worth something in HP (it used to be worth exactly nothing)")

	print("\n===== THE COMPARISON THE OWNER ASKED FOR =====")
	var h9 := _hp(1, 9, 20)
	print("  H9 %d hp   vs   G1 %d hp   ->  %s" % [h9, g1,
		"H9 is stronger" if h9 > g1 else "G1 is stronger"])
	print("  power_mult: H9 %.3f, G1 %.3f" % [PowerRank.power_mult(1, 9), PowerRank.power_mult(2, 1)])
	# H9 being a little stronger than G1 is FINE and intended - nine ranks of work should beat a
	# fresh promotion. What is not fine is 3x, which is what made ascension a trap.
	var ratio: float = float(h9) / maxf(1.0, float(g1))
	print("  H9 is %.2fx a G1" % ratio)
	ck(ratio < 2.0, "an H9 is not MORE THAN DOUBLE a G1 (was ~3.1x)")

	print("\n===== IS THE LADDER MONOTONIC ACROSS ALL 81 CELLS? =====")
	# The real guarantee: going up a grade can never be a step DOWN, at any rank.
	var bad: Array = []
	var prev := -1.0
	for t in range(1, 10):
		for r in range(1, 10):
			var m: float = PowerRank.power_mult(t, r)
			if m < prev - 0.0001:
				bad.append("tier %d rank %d" % [t, r])
			prev = m
	ck(bad.is_empty(), "the 81-cell power ladder never steps backwards%s" % [
		"" if bad.is_empty() else " - DROPS AT: " + ", ".join(bad)])

	print("\n===== AND IS COMBINING THINGS AN UPGRADE? =====")
	# ⚑ DRIVE THE REAL BUILDERS. The first version of this reconstructed the output as
	# `_hp(tier+1, 1, 1)` - a copy of what the code was believed to do - so it could not have
	# noticed the fix, and would not notice a future change either. These call
	# `create_ascended_companion` and `create_fusion_companion` and weigh what comes back.
	# ⚑ AN INSTANCE. `create_ascended_companion` and `create_fusion_companion` are instance
	# methods, not static ones - calling them on the SCRIPT produced no output and no error and
	# simply span, which is the zombie CLAUDE.md warns about. It cost a 10-minute timeout.
	var Drop = DropTablesScript.new()
	get_root().add_child(Drop)
	for lvl in [10, 20, 40]:
		var parents: Array = []
		for k in range(3):
			parents.append(_comp(1, 9, lvl))
		var out: Dictionary = Drop.create_ascended_companion(parents, {"name": "Normal"})
		if out.is_empty():
			ck(false, "create_ascended_companion returned nothing for level %d" % lvl)
			continue
		var gave: int = _hp(1, 9, lvl)
		var got: int = CharacterScript.calculate_companion_max_hp(out, 4000, 50)
		print("  ASCEND: three H9s at level %d (best %d hp) -> %s%d at level %d, %d hp  %s" % [
			lvl, gave, "tier ", int(out.get("tier", 0)), int(out.get("level", 0)), got,
			"UPGRADE" if got >= gave else "DOWNGRADE x%.2f" % (float(got) / maxf(1.0, float(gave)))])
		ck(got >= gave, "ascending a level-%d H9 is not a downgrade" % lvl)
		ck(int(out.get("level", 0)) == lvl, "...and the new companion keeps level %d" % lvl)

	for lvl in [10, 20, 40]:
		var out2: Dictionary = Drop.create_fusion_companion("Skeleton", 4, {"name": "Normal"}, -1, lvl)
		if out2.is_empty():
			ck(false, "create_fusion_companion returned nothing for level %d" % lvl)
			continue
		var gave2: int = _hp(1, 3, lvl)
		var got2: int = CharacterScript.calculate_companion_max_hp(out2, 4000, 50)
		print("  FUSE:   three rank-3s at level %d (best %d hp) -> rank %d at level %d, %d hp  %s" % [
			lvl, gave2, int(out2.get("sub_tier", 0)), int(out2.get("level", 0)), got2,
			"UPGRADE" if got2 >= gave2 else "DOWNGRADE x%.2f" % (float(got2) / maxf(1.0, float(gave2)))])
		ck(got2 >= gave2, "fusing level-%d rank-3s is not a downgrade" % lvl)

	print("\n===== AND THE SERVER ACTUALLY PASSES THE LEVEL =====")
	# A defaulted parameter is the quietest way for this to regress: the builders would keep
	# their new behaviour and every caller would keep getting level 1.
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc.count("_best_kennel_level(kennel, indices)") == 2,
		"both house-fusion call sites pass the best input level")
	ck(ssrc.count("_best_companion_level(companions)") == 1,
		"and the stable-fusion one does too")
	var dsrc := FileAccess.get_file_as_string("res://shared/drop_tables.gd")
	ck(dsrc.find('"level": maxi(1, inherited_level),') >= 0, "fusion writes the inherited level")
	ck(dsrc.find('"level": inherited_level,') >= 0, "ascension writes the inherited level")

	print("\n[COMPTIERRANK] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
