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
const FULL_PER_LEVEL := 9.0      # level * 90 / 10
const CURE_PER_LEVEL := 18.0     # level * 180 / 10
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
		"full": srv.find("var full_heal_cost = max(1, level * 90 / 10)") >= 0,
		"cure": srv.find("var cure_all_cost = max(1, level * 180 / 10)") >= 0,
		"quick pays 25%": srv.find("heal_percent = 25") >= 0,
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
	print("  constant. There is no level at which Full Heal is the better buy.")
	if ratio > 1.0:
		_fail("Full Heal is strictly dominated by repeating Quick Heal (%.2fx)" % ratio)
	else:
		_ok("Full Heal is worth its price")

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
	print("  than one Full Heal. The expensive options buy nothing the cheap one cannot repeat.")
	print("")
	print("  \u26d1 THE ONLY THING QUICK HEAL CANNOT DO is clear debuffs - that is Cure All's real")
	print("     product, and it is sold bundled with healing the player does not need to buy.")

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
