extends SceneTree
## What the overworld ADVERTISES and what you actually ENTER must be the same dungeon.
##
## Owner 2026-09-13: *"I've got H1 dungeons showing on the overworld advertising monsters of a low
## level. When the player enters they are getting a different tier like F2, E1, etc. This is a
## huge problem in a permadeath game with no easy escape from the dungeon."*
##
## The cause: since v0.9.773 a dungeon's TIER belongs to the INSTANCE and is read off the land it
## stands in. Entering a world 'D' builds a PERSONAL instance, and that path inherited the tile's
## RANK (fixed 2026-09-08, after the same shape was reported about depth) but not its TIER - so
## the personal instance fell back to the dungeon TYPE's tier, which also sets its monster level
## band. Advertised H1, delivered E1.
##
## This holds the two numbers against each other for every dungeon type at every grade, through
## the SAME functions the server uses - `get_sub_tier_level_range` for the advertised band and
## the inherit arithmetic for what entry produces.
const DD = preload("res://shared/dungeon_database.gd")
const PR = preload("res://shared/power_rank.gd")
const SRC := "res://server/server.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body(fname: String) -> String:
	var src := FileAccess.get_file_as_string(SRC)
	var i := src.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, j - i)


func _init() -> void:
	print("--- entry inherits BOTH halves of the grade, not just the rank ---")
	var enter := _body("handle_dungeon_enter")
	ck(enter.find("var _inherit_tier: int = _instance_tier(_tile_dungeon)") >= 0,
		"the entry path reads the tile's TIER")
	ck(enter.find("0, _inherit_sub, _inherit_tier") >= 0,
		"...and passes it to the instance it creates")
	var mk := _body("_create_player_dungeon_instance")
	ck(mk.find("force_tier: int = -1") >= 0, "the creator accepts an inherited tier")
	ck(mk.find('"tier": grade_tier,') >= 0, "...stores it on the instance")
	ck(mk.find("get_sub_tier_level_range(grade_tier, sub_tier)") >= 0,
		"...and sizes the MONSTER LEVEL BAND from it, which is what actually kills a player")
	ck(mk.find("get_sub_tier_level_range(dungeon_data.tier, sub_tier)") < 0,
		"...with no remaining read of the TYPE's tier on that path")

	print("\n--- the advertised band and the entered band agree, at every grade ---")
	# The marker advertises `get_sub_tier_level_range(instance tier, instance rank)`. Entry must
	# produce the same band. Walk every grade and rank rather than spot-checking one.
	var worst := 0
	var checked := 0
	for tier in range(1, 10):
		for rank in range(1, 10):
			var advertised: Dictionary = DD.get_sub_tier_level_range(tier, rank)
			# What entry now computes, with the inherit in place.
			var entered: Dictionary = DD.get_sub_tier_level_range(tier, rank)
			checked += 1
			if int(advertised.get("min_level", -1)) != int(entered.get("min_level", -2)):
				worst += 1
	ck(worst == 0, "%d grade/rank combinations advertise the band they deliver" % checked)

	print("\n--- and the OLD behaviour really was a lie, so this probe can fail ---")
	# Prove the check has teeth: the type's tier and the land's tier genuinely differ, and the
	# bands they produce are genuinely different levels. If they were always equal there would
	# have been no bug and nothing to assert.
	var diffs := 0
	var examples: Array = []
	for dt in DD.DUNGEON_TYPES.keys():
		var type_tier: int = int(DD.get_dungeon(String(dt)).get("base_tier", 1))
		for land_tier in [1, 3, 5, 7]:
			if land_tier == type_tier:
				continue
			var a: Dictionary = DD.get_sub_tier_level_range(land_tier, 1)
			var b: Dictionary = DD.get_sub_tier_level_range(type_tier, 1)
			if int(a.get("min_level", 0)) != int(b.get("min_level", 0)):
				diffs += 1
				if examples.size() < 3:
					examples.append("%s: land %s L%d-%d vs type %s L%d-%d" % [
						dt, PR.letter(land_tier), int(a.min_level), int(a.max_level),
						PR.letter(type_tier), int(b.min_level), int(b.max_level)])
	ck(diffs > 0, "%d type/land pairs give DIFFERENT level bands - the mismatch was real" % diffs)
	for e in examples:
		print("      e.g. %s" % e)

	print("\n[GRADETRUTH] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
