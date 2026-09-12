extends SceneTree
## The weakest companion of a grade must beat the strongest of the grade below it.
##
## Owner asked the question directly on 2026-09-11: *"we may need to compare power of companion
## tier and rank to see if an H9 is weaker or stronger than a G1"*. The answer was the bad one.
## An H9 carried about 3.1x the HP of a G1 and handed its owner 2.0x bonuses against 1.0x,
## because companion HP never read tier at all and damage weighted a rank at 0.05 against a
## grade at 0.06 - so eight ranks outweighed eight grades and the ladders crossed freely.
##
## `PowerRank.power_index` had defined the right ordering the whole time, and the probe that
## asserted *"the WEAKEST of a higher tier still beats the STRONGEST of a lower one (G1 > H9)"*
## passed - because `power_index` was called by nothing in the game and the assertion was about
## a display formatter. That is the failure this file exists to make impossible: it checks the
## STATS, on the functions combat actually calls.
const PR := preload("res://shared/power_rank.gd")
const Char := preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _companion(tier: int, rank: int, level: int = 20) -> Dictionary:
	return {"tier": tier, "sub_tier": rank, "level": level,
		"monster_type": "Wolf", "variant_rarity": "common",
		"bonuses": {"aggro": 50, "attack": 3, "defense": 2, "hp_bonus": 0}}


func _init() -> void:
	print("--- the ladder itself ---")
	ck(PR.power_mult(1, 1) == 1.0, "H1 is the floor at exactly 1.0")
	var top: float = PR.power_mult(9, 9)
	print("  H1 %.3f -> S9 %.3f, a span of %.1fx across all 81 grades" % [PR.power_mult(1, 1), top, top])
	ck(top > 4.0 and top < 20.0, "and the whole ladder spans a sane %.1fx" % top)

	var broken := 0
	var prev := -1.0
	for t in range(1, 10):
		for r in range(1, 10):
			var m: float = PR.power_mult(t, r)
			if m <= prev:
				broken += 1
			prev = m
	ck(broken == 0, "every one of the 81 steps is stronger than the one before it")
	# The owner's actual question, at every boundary rather than just the one they asked about.
	var crossings := 0
	for t in range(1, 9):
		if PR.power_mult(t + 1, 1) <= PR.power_mult(t, 9):
			crossings += 1
	ck(crossings == 0, "and at all 8 grade boundaries, rank 1 of the higher beats rank 9 of the lower")
	print("  H9 %.3f vs G1 %.3f  (this pair was 3.1x the WRONG way around)" % [
		PR.power_mult(1, 9), PR.power_mult(2, 1)])

	print("\n--- HP, through the function combat calls ---")
	# calculate_companion_max_hp never read `tier` at all. Pass a real owner HP: with 0 it drops
	# to a dead legacy formula and would measure nothing.
	var owner_hp := 800
	var h9: int = Char.calculate_companion_max_hp(_companion(1, 9), owner_hp, 20)
	var g1: int = Char.calculate_companion_max_hp(_companion(2, 1), owner_hp, 20)
	print("  same species, same level: H9 %d HP, G1 %d HP" % [h9, g1])
	ck(g1 > h9, "a G1 companion is tougher than an H9 one")
	var hp_broken := 0
	var hp_prev := -1
	for t in range(1, 10):
		for r in range(1, 10):
			var hp: int = Char.calculate_companion_max_hp(_companion(t, r), owner_hp, 20)
			if hp < hp_prev:
				hp_broken += 1
			hp_prev = hp
	ck(hp_broken == 0, "and HP rises across all 81 grades without a single step backwards")

	print("\n--- the bonuses a companion grants its owner ---")
	var c = Char.new()
	c.active_companion = _companion(1, 9)
	var b_h9: Dictionary = c.get_companion_effective_bonuses()
	c.active_companion = _companion(2, 1)
	var b_g1: Dictionary = c.get_companion_effective_bonuses()
	print("  attack bonus: H9 %.2f, G1 %.2f" % [float(b_h9.get("attack", 0)), float(b_g1.get("attack", 0))])
	ck(float(b_g1.get("attack", 0)) > float(b_h9.get("attack", 0)),
		"a G1 grants more than an H9 (this was 1.0x against 2.0x, backwards)")

	print("\n--- and nothing is still reading the old rank-only tables ---")
	# Those tables are what made tier decorative. If a surface still reads one, that surface is
	# still tier-blind and the ladder is only half applied.
	var live := 0
	for path in ["res://shared/character.gd", "res://shared/combat_manager.gd", "res://shared/drop_tables.gd"]:
		var src := FileAccess.get_file_as_string(path)
		for table in ["COMPANION_SUB_TIER_MULTIPLIERS.get(", "COMPANION_SUB_TIER_ABILITY_MULT.get("]:
			if src.find(table) >= 0:
				live += 1
				print("    still live: %s in %s" % [table, path])
	ck(live == 0, "no companion surface reads a rank-only multiplier any more")
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.find("PowerRank.power_mult(maxi(1, int(companion_tier))") >= 0,
		"combat damage quality uses the ladder")
	ck(cm.find("0.06 * float(maxi(1, int(companion_tier))") < 0,
		"...and the old hand-weighted formula is gone, not left beside it")

	print("\n[COMPANIONLADDER] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
