extends SceneTree
## ⛑ IS THERE ANY REASON TO BUY ANYTHING BUT THE CHEAP HEAL?
##
## Owner 2026-09-18: *"The healer options may need looked at as well, there's no real reason to do
## anything other than a quick heal for reviving companions."*
##
## ⚑ "DOMINATED" IS A CLAIM ABOUT NUMBERS, so the backlog entry required this measured before
## anything was redesigned. The three options are priced off LEVEL and pay off in PERCENT of the
## bar, which is the shape that makes one of them strictly better than the others at every level at
## once — if it is true, it is true everywhere, and the fix is structural rather than a nudge.
##
## Run:
##   godot --headless --path . --script res://tools/probe/healer_options_are_a_choice.gd

const CharacterScript := preload("res://shared/character.gd")

## The live formulas, read off `check_healer_encounter` in server.gd. Named here so a change there
## and no change here shows up as a disagreement rather than as a quietly stale audit.
const QUICK_PER_LEVEL := 2.2     # level * 22 / 10
const FULL_PER_LEVEL := 6.6      # level * 66 / 10
const CLEANSE_PER_LEVEL := 3.3   # level * 33 / 10
const CURE_PER_LEVEL := 9.0      # level * 90 / 10

## How much cheaper per point of healing the bulk option must be before the menu is a decision.
## 1.0 would only mean "not strictly dominated", which a rounding error could satisfy.
const MIN_BULK_DISCOUNT := 1.10
const QUICK_PCT := 25
const FULL_PCT := 100
const CURE_PCT := 100

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	# ⛑ THE FORMULAS MUST STILL BE THE ONES THE SERVER USES. A constants block copied out of a
	# file is the "one value, two places" shape this project has been bitten by repeatedly, so the
	# source is checked before any number below is believed.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var live := {
		"quick": srv.find("var quick_heal_cost = max(1, level * 22 / 10)") >= 0,
		"full": srv.find("var full_heal_cost = max(1, level * 66 / 10)") >= 0,
		"cleanse": srv.find("var cleanse_cost = max(1, level * 33 / 10)") >= 0,
		"cure": srv.find("var cure_all_cost = max(1, level * 90 / 10)") >= 0,
		"quick pays 25%": srv.find("heal_percent = 25") >= 0,
		"a cleanse can be bought ALONE": srv.find("\"cleanse\":") >= 0,
		"the cure names its debuffs": srv.find("for _d in PERSISTENT_DEBUFFS:") >= 0,
		# ⛑ THE CALL, NOT THE WORDS. Matching the bare string found the COMMENT that records the
		# old code and reported the fix missing - a source-reading check cannot tell a call from a
		# note about a call, so it looks for the receiver too.
		"nothing blanket-clears persistent_buffs": srv.find("character.persistent_buffs.clear()") < 0,
	}
	print("")
	print("===== 0. THE NUMBERS BELOW ARE THE ONES THE SERVER USES =====")
	for k in live.keys():
		if bool(live[k]):
			_ok(String(k))
		else:
			_fail("the %s formula has changed - this audit is stale" % k)
	if not _fails.is_empty():
		_finish()
		return

	print("")
	print("===== 1. WHAT EACH OPTION COSTS, AND WHAT IT BUYS =====")
	print("  A character at its own level with a full bar missing, so every option pays its most.")
	print("")
	print("  %-7s %-9s %-9s %-9s %-14s %s" % ["level", "quick", "full", "cure", "quick x4", "full vs 4x quick"])
	for lvl in [5, 10, 25, 50, 100, 400, 1000]:
		var q := maxi(1, int(float(lvl) * QUICK_PER_LEVEL))
		var f := maxi(1, int(float(lvl) * FULL_PER_LEVEL))
		var c := maxi(1, int(float(lvl) * CURE_PER_LEVEL))
		# Four quick heals restore the same 100% of the bar that one full heal does.
		var q4 := q * 4
		var verdict := "full is %.2fx the cost of the same healing" % (float(f) / maxf(1.0, float(q4)))
		print("  %-7d %-9d %-9d %-9d %-14d %s" % [lvl, q, f, c, q4, verdict])

	print("")
	print("===== 2. IS THE EXPENSIVE OPTION DOMINATED? =====")
	# ⛑ THE WHOLE QUESTION IN ONE RATIO. Both options pay in PERCENT OF THE BAR and both are priced
	# per LEVEL, so the ratio is a constant - it does not matter what the character's max HP is, or
	# what level they are. That is what makes this structural rather than a tuning miss.
	var ratio: float = FULL_PER_LEVEL / (QUICK_PER_LEVEL * (float(FULL_PCT) / float(QUICK_PCT)))
	print("  Quick Heal pays %d%% for %.1f per level  ->  %.3f valor per 1%% of the bar" % [
		QUICK_PCT, QUICK_PER_LEVEL, QUICK_PER_LEVEL / float(QUICK_PCT)])
	print("  Full Heal  pays %d%% for %.1f per level  ->  %.3f valor per 1%% of the bar" % [
		FULL_PCT, FULL_PER_LEVEL, FULL_PER_LEVEL / float(FULL_PCT)])
	print("")
	print("  Full Heal costs %.2fx what the SAME healing costs bought as Quick Heals," % ratio)
	print("  at EVERY level - both are linear in level and pay in percent, so the ratio is a")
	print("  constant - so whichever way it points, it points that way EVERYWHERE. Below 1.00x the")
	print("  bulk option is the better buy at every level; above it, at none.")
	if ratio > 1.0:
		_fail("Full Heal is strictly dominated by repeating Quick Heal (%.2fx)" % ratio)
	else:
		_ok("Full Heal is worth its price")

	# ⛑ THE GATE. Buying the whole bar must be CHEAPER PER POINT than topping up four times,
	# by a margin big enough to be a reason rather than a rounding artifact.
	var four_quick: float = QUICK_PER_LEVEL * 4.0
	var bulk: float = four_quick / FULL_PER_LEVEL
	print("")
	print("  Full Heal costs %.2f per level; the same healing as four Quick Heals costs %.2f."
		% [FULL_PER_LEVEL, four_quick])
	print("  Buying the bar whole is %.2fx cheaper (gate: %.2fx)." % [bulk, MIN_BULK_DISCOUNT])
	if bulk < MIN_BULK_DISCOUNT:
		_fail("Full Heal saves only %.2fx over repeating Quick Heal - not a reason to buy it" % bulk)
	else:
		_ok("Full Heal is a real saving over repeating Quick Heal (%.2fx)" % bulk)

	# ⛑ AND THE CLEANSE MUST BE BUYABLE WITHOUT HEALING YOU DO NOT NEED. Bundling it was the
	# other half of the fault: a poisoned player at full health had to buy a Full Heal to be cured.
	print("")
	print("  Cure Ailments alone: %.1f per level. Full + Cure All bundled: %.1f, against %.1f"
		% [CLEANSE_PER_LEVEL, CURE_PER_LEVEL, FULL_PER_LEVEL + CLEANSE_PER_LEVEL])
	if CLEANSE_PER_LEVEL >= FULL_PER_LEVEL:
		_fail("curing ailments costs as much as a full heal - the cleanse is still bundled in effect")
	else:
		_ok("ailments can be cured for %.2fx a Full Heal, without buying healing"
			% (CLEANSE_PER_LEVEL / FULL_PER_LEVEL))
	if CURE_PER_LEVEL > FULL_PER_LEVEL + CLEANSE_PER_LEVEL:
		_fail("the bundle costs MORE than buying the two parts separately")
	else:
		_ok("the bundle is no worse than buying both parts (%.1f vs %.1f)"
			% [CURE_PER_LEVEL, FULL_PER_LEVEL + CLEANSE_PER_LEVEL])

	var cure_ratio: float = CURE_PER_LEVEL / FULL_PER_LEVEL
	print("")
	print("  Cure All costs %.2fx a Full Heal for the same healing plus the debuff clear." % cure_ratio)
	print("  So the debuff clear alone is priced at %.1f per level - %.2fx a whole Full Heal." % [
		CURE_PER_LEVEL - FULL_PER_LEVEL, (CURE_PER_LEVEL - FULL_PER_LEVEL) / FULL_PER_LEVEL])

	print("")
	print("===== 3. WHAT THE CHEAP OPTION ALREADY COVERS =====")
	# ⛑ THE OWNER'S OWN REASON FOR BUYING IT. The companion heal rides on `heal_percent` and is not
	# priced separately, so Quick Heal at 25% also heals the companion 25% - and repeating it heals
	# the companion the rest of the way for the same total.
	print("  The companion is healed by the SAME `heal_percent`, at no extra cost, on every option.")
	print("  So Quick Heal x4 restores the player AND the companion in full for %.2fx less" % ratio)
	print("  than one Full Heal. Healing is the same product at every tier - the only thing that can")
	print("  make the big option worth buying is PRICE PER POINT, which is what section 2 gates.")
	print("")
	print("  \u26d1 THE ONLY THING QUICK HEAL CANNOT DO is clear debuffs - that is Cure All's real")
	print("     product - and since 2026-09-19 it has its own line, so a hale but poisoned player")
	print("     no longer has to buy a full heal to be cured.")

	_finish()


func _finish() -> void:
	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every healer option is worth buying at some point.")
	quit()
