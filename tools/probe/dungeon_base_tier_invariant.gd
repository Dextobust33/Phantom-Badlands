extends SceneTree
## ⛑ A DUNGEON TYPE HAS NO GRADE. THE NAME `base_tier` IS WHAT ENFORCES IT.
##
## A dungeon's grade belongs to the INSTANCE - the land it spawned in decides it, which is what
## makes an A5 Goblin Dungeon possible (owner, 2026-09-11). So `DUNGEON_TYPES[x]` cannot answer
## "what grade is this dungeon", and for months every surface that asked it got a plausible wrong
## number back.
##
## That leaked SIX times into player-facing text and TWICE into reward formulas, each found
## separately by somebody noticing: *"a player went into a pheonix dungeon that showed as F4 on
## the overworld and instead it put them in a C5."* Owner, 2026-09-16, after the fourth:
## *"do the structural fix then so this doesn't happen again."*
##
## The structural fix is the RENAME. The type's field is `base_tier` - its design weight, an input
## to creation - and `tier` exists only on a dictionary an instance has resolved
## (`server._dungeon_data_for`). A display or reward site that reaches for a type's grade now gets
## a missing key instead of a wrong answer.
##
## This probe is what stops the rename being quietly undone. It is deliberately about the SHAPE of
## the data rather than any one call site, because call sites are what kept getting missed.
##
## Run:
##   godot --headless --path . --script res://tools/probe/dungeon_base_tier_invariant.gd

const DD := preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== 1. NO DUNGEON TYPE CARRIES A `tier` =====")
	var with_tier: Array[String] = []
	var without_base: Array[String] = []
	for dt in DD.DUNGEON_TYPES:
		var d: Dictionary = DD.DUNGEON_TYPES[dt]
		if d.has("tier"):
			with_tier.append(String(dt))
		if not d.has("base_tier"):
			without_base.append(String(dt))
	ck(with_tier.is_empty(), "no type defines `tier` (%d types checked)" % DD.DUNGEON_TYPES.size())
	for t in with_tier:
		print("           %s still has one" % t)
	ck(without_base.is_empty(), "every type defines `base_tier`")
	for t in without_base:
		print("           %s is missing it" % t)

	print("\n===== 2. AND `get_dungeon` DOES NOT ADD ONE BACK =====")
	# `get_dungeon` returns a SCALED copy, so it is a second place the key could reappear - and a
	# copy that grew a `tier` would defeat the whole rename while every type definition still
	# looked correct above.
	for dt in ["goblin_caves", "phoenix_nest", "wolf_den"]:
		var got: Dictionary = DD.get_dungeon(dt)
		ck(not got.has("tier"), "get_dungeon(%s) has no `tier`" % dt)
		ck(int(got.get("base_tier", 0)) > 0, "get_dungeon(%s) carries its `base_tier`" % dt)

	print("\n===== 3. THE REWARD FORMULAS TAKE A GRADE, AND USE IT =====")
	# Both of these read the TYPE's tier until 2026-09-16, so an A5 Goblin Caves - the rarest and
	# hardest version of the place - paid the treasure and the experience of a tier-1 dungeon.
	# Asserting the PARAMETER exists is not enough; assert the number moves.
	var low: Dictionary = DD.calculate_completion_rewards("goblin_caves", 3, 1, 1)
	var high: Dictionary = DD.calculate_completion_rewards("goblin_caves", 3, 1, 8)
	ck(int(high.get("xp", 0)) > int(low.get("xp", 0)),
		"completion XP rises with the GRADE cleared (H %d -> A %d)" % [
			int(low.get("xp", 0)), int(high.get("xp", 0))])

	# The egg a chest can hold is graded too. A HIGHER grade drops eggs LESS often on purpose
	# (TREASURE_EGG_CHANCE_BY_TIER - a rarer egg is a rarer drop), so this asserts that the
	# rate MOVES with the grade rather than asserting a direction. Rolled, so sample it.
	var low_eggs := 0
	var high_eggs := 0
	for i in range(400):
		if not DD.roll_treasure("goblin_caves", 1, 1, 1).get("egg", {}).is_empty():
			low_eggs += 1
		if not DD.roll_treasure("goblin_caves", 1, 1, 8).get("egg", {}).is_empty():
			high_eggs += 1
	print("           eggs in 400 chests: H-grade %d, A-grade %d" % [low_eggs, high_eggs])
	ck(high_eggs != low_eggs, "chest contents respond to the GRADE, not the type")

	print("\n===== 4. AND OMITTING THE GRADE FALLS BACK, RATHER THAN PAYING ZERO =====")
	# A caller that has not been updated must degrade to the old number, not to nothing. This is
	# the difference between a missed call site paying slightly wrong and paying 0 XP.
	var no_grade: Dictionary = DD.calculate_completion_rewards("goblin_caves", 3, 1)
	ck(int(no_grade.get("xp", 0)) > 0,
		"a caller with no grade still pays (%d XP)" % int(no_grade.get("xp", 0)))

	print("\n===== 5. AND NOTHING READS A GRADE OFF A TYPE DICTIONARY =====")
	# ⛑ THE HOLE THE RENAME DOES NOT CLOSE BY ITSELF, stated plainly.
	#
	# `dd.tier` on a renamed dictionary fails loudly - good. But `dd.get("tier", 1)` returns 1
	# and says nothing, which is the same silent-wrong-number the rename exists to stop. So the
	# one remaining spelling gets a detector.
	#
	# It walks PROVENANCE, not proximity: for each read of some `x.tier`, find where `x` was
	# assigned and judge THAT. Proximity was tried on 2026-09-16 for the sibling `T#` check and
	# was a silent no-op, because the word it keyed on sat on the next line.
	var offenders: Array[String] = []
	for path in ["res://server/server.gd", "res://shared/quest_database.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		var src: PackedStringArray = f.get_as_text().split("\n")
		f.close()
		for i in range(src.size()):
			var ln := String(src[i])
			var stripped := ln.strip_edges()
			if stripped.begins_with("#") or stripped.begins_with("##"):
				continue
			var at := ln.find('.get("tier"')
			if at < 0:
				at = ln.find(".tier")
			if at < 0:
				continue
			# the identifier immediately before the dot
			var j := at - 1
			while j >= 0 and (ln[j] == "_" or ln[j].is_valid_identifier()):
				j -= 1
			var name := ln.substr(j + 1, at - j - 1)
			if name == "":
				continue
			# walk back to its assignment, stopping at the enclosing func
			for k in range(i, maxi(-1, i - 400), -1):
				var prev := String(src[k])
				if prev.begins_with("func "):
					break
				if not prev.contains("var " + name):
					continue
				if prev.contains("_dungeon_data_for"):
					break        # an instance resolved it - this IS the grade
				if prev.contains("get_dungeon(") or prev.contains("DUNGEON_TYPES"):
					offenders.append("%s:%d  %s" % [path.get_file(), i + 1, stripped])
				break
	ck(offenders.is_empty(), "no display or reward site reads a TYPE's grade")
	for o in offenders:
		print("           " + o)

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)
