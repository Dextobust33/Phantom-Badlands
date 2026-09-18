extends SceneTree
## ⛑ A PROMISED TITLE BONUS ACTUALLY CHANGES A NUMBER.
##
## Knight promised **+15% damage** and Mentee promised **+50% XP** in the title UI, the help page
## and `titles.gd` — and `get_knight_damage_bonus` / `get_mentee_xp_bonus` /
## `get_mentee_extra_xp_bonus` had **no callers at all**. A player knighted by the High King got a
## blue prefix and nothing else, for the whole life of the feature.
##
## ⛑ THE TELL WAS THE SIBLING, AND IT IS WHY THIS PROBE EXECUTES RATHER THAN GREPS.
## `get_knight_market_bonus` is wired at four sites in server.gd; the damage half of the same
## status, defined eight lines below it in the same file, was wired nowhere. Every one of these
## functions EXISTS, is spelled correctly, and returns the right number when called — so reading
## the source proves nothing whatsoever. The only question worth asking is whether a character
## carrying the status ends up with a different number than one without it, so that is what this
## measures: same character, one field changed, diff the output.
##
## Same shape as `gold_find` and `assassinate_pct` before it. Third time.
##
## Run:
##   godot --headless --path . --script res://tools/probe/title_bonuses_reach_the_dice.gd

const Char = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _make(cls: String) -> Character:
	var c = Char.new()
	c.name = "probe"
	c.class_type = cls
	c.level = 20
	return c


func _init() -> void:
	print("===== MENTEE: +50% XP REACHES add_experience =====")
	# ⛑ THE CONTROL DIFFERS IN ONE THING. Same class, same level, same grant — only the status.
	var plain := _make("Warrior")
	var mentee := _make("Warrior")
	mentee.mentee_status = {"granted_by": "probe_elder"}
	ck(mentee.is_mentored() and not plain.is_mentored(), "one character is a Mentee and one is not")

	# ⛑ LEVELLING CONSUMES `experience`, so the FIELD DELTA IS NOT WHAT WAS AWARDED. The
	# first version of this probe diffed the field, both characters levelled, and the ratio
	# came out 1.55x instead of 1.50x - each had silently had its level-up threshold taken
	# out of the total. It passed only because the tolerance was loose enough to hide it,
	# and the comment above it claimed to be comparing totals while doing the opposite.
	# Push the threshold out of reach so the grant lands whole and the ratio is readable.
	plain.experience_to_next_level = 100000000
	mentee.experience_to_next_level = 100000000
	var xp0: int = plain.experience
	var xp1: int = mentee.experience
	plain.add_experience(1000)
	mentee.add_experience(1000)
	var got_plain: int = plain.experience - xp0
	var got_mentee: int = mentee.experience - xp1
	print("  plain gained %d, mentee gained %d (levels: %d vs %d)" % [
		got_plain, got_mentee, plain.level, mentee.level])
	ck(got_mentee > got_plain,
		"the Mentee is awarded MORE than the identical non-Mentee (%d vs %d)" % [got_mentee, got_plain])
	var ratio: float = float(got_mentee) / float(maxi(1, got_plain))
	ck(absf(ratio - 1.5) < 0.005,
		"...and it is EXACTLY the +50%% the title promises (measured %.3fx)" % ratio)

	print("\n===== KNIGHT: +15% DAMAGE REACHES calculate_damage =====")
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(src.find("character.get_knight_damage_bonus()") >= 0,
		"calculate_damage consults the Knight bonus")
	# The sibling that was ALREADY wired — if this ever goes quiet the whole status is dead again.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.count("get_knight_market_bonus()") >= 4,
		"...and the market half it was asymmetric with is still wired (%d sites)"
			% srv.count("get_knight_market_bonus()"))
	var k := _make("Warrior")
	k.knight_status = {"granted_by": "probe_king"}
	ck(absf(k.get_knight_damage_bonus() - 0.15) < 0.001,
		"a Knight's bonus is the 0.15 titles.gd advertises")
	ck(absf(_make("Warrior").get_knight_damage_bonus()) < 0.001,
		"...and a non-Knight gets nothing (the control)")

	print("\n===== NOTHING ELSE IS LEFT PROMISED-BUT-DEAD =====")
	# Every bonus getter on the status pair must be READ somewhere outside character.gd.
	var chr_src := FileAccess.get_file_as_string("res://shared/character.gd")
	var all := src + srv + chr_src + FileAccess.get_file_as_string("res://client/client.gd")
	for fn in ["get_knight_damage_bonus", "get_knight_market_bonus",
			"get_mentee_xp_bonus", "get_mentee_extra_xp_bonus"]:
		# >1 because the definition itself is one occurrence.
		ck(all.count(fn + "(") > 1, "  %s is called, not just defined" % fn)

	print("")
	if fails == 0:
		print("[PROBE] PASS the promised title bonuses change real numbers")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
