extends SceneTree
## ⛑ IS A PHANTOM-BORN COMPANION ACTUALLY STRONGER THAN ITS DUPLICATE?
##
## Owner 2026-09-19, rejecting all three options I offered: *"Eggs/companions that hatch out of
## them should have an additional multiplier or something that makes them unique and stronger than
## a duplicate you would find out in a normal dungeon, ie an e4 in a dungeon is not as strong as an
## e4 from a phantom."*
##
## ⚡ THE THREE OBVIOUS AXES WERE ALL DEAD ENDS, MEASURED:
##   RANK    the whole spread from rank 1 to rank 9 inside a tier is **1.26x**, and `power_index`
##           already clamps rank to RANKS — so ranks above the ceiling return IDENTICAL power.
##           Pushing rank past it buys literally nothing. (I had claimed rank was "worth up to 2x";
##           that was wrong, and this probe exists partly so the real number is on record.)
##   TIER    is where the power is (8.16x H to S) but collides with the grade ladder and every
##           surface that reads a letter.
##   RARITY  alone abandons the design's "far stronger than an identical-tier egg" promise.
## So provenance rides ALONGSIDE the grade: the letter stays honest, the companion is stronger.
##
## ⛑ A MULTIPLIER IS ONLY WORTH ANYTHING IF IT SURVIVES THE WHOLE JOURNEY — egg, hatch, companion,
## combat. It is dropped in exactly one place and the feature silently does nothing, which is the
## hardest kind of bug to notice because everything still works.
##
## Run:
##   godot --headless --path . --script res://tools/probe/a_phantom_born_companion_is_stronger.gd

const PM := preload("res://shared/phantom_model.gd")
const DT := preload("res://shared/drop_tables.gd")
const PR := preload("res://shared/power_rank.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	print("")
	print("===== 1. THE BONUS IS BOUNDED, AND SIZED AGAINST THE LADDER =====")
	var per_tier: float = pow(PR.power_mult(9, 1) / PR.power_mult(1, 1), 1.0 / 8.0)
	var cap: float = PM.PHANTOM_POWER_CAP
	print("  one full GRADE step        %.3fx" % per_tier)
	print("  rank 1 -> 9 within a tier  %.3fx   (why rank was the wrong axis)" % (PR.power_mult(5, 9) / PR.power_mult(5, 1)))
	print("  phantom cap                %.3fx   = %.2f grade steps"
		% [1.0 + cap, log(1.0 + cap) / log(per_tier)])
	var worst: float = PM.companion_power_bonus(99999, 20, {"eggs": {"Goblin": 99999}, "companions": 99999})
	if worst > cap + 0.0001:
		_fail("the bonus escapes its cap (%.3f > %.3f) - that is a tenth grade nobody designed"
			% [worst, cap])
	else:
		_ok("no depth or investment exceeds the cap (worst case %.3f)" % worst)
	if 1.0 + cap > per_tier * 1.6:
		_fail("the cap is worth more than 1.6 grade steps - at that size it stops being a bonus "
			+ "and becomes a parallel grade ladder")
	else:
		_ok("the cap is worth about one grade, not a new ladder")

	print("")
	print("===== 2. IT IS EARNED AT THE BOTTOM, LIKE EVERY OTHER PHANTOM REWARD =====")
	var heavy := {"eggs": {"Goblin": 40}, "companions": 10}
	var shallow: float = PM.companion_power_bonus(2, 20, heavy)
	var deep: float = PM.companion_power_bonus(20, 20, heavy)
	print("  floor 2: +%.3f     floor 20: +%.3f" % [shallow, deep])
	if shallow > 0.05:
		_fail("a shallow floor already pays +%.3f - depth-risk is the only brake on the loop and "
			% shallow + "this would let it be farmed in safety")
	else:
		_ok("the shallow floors pay almost nothing")
	if deep <= shallow * 5.0:
		_fail("the bottom is not decisively better than the top")
	else:
		_ok("the bottom is %.0fx the top" % (deep / maxf(shallow, 0.0001)))

	print("")
	print("===== 3. THE MULTIPLIER SURVIVES THE WHOLE JOURNEY =====")
	# (a) the model -> the egg
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	if srv.find("egg[\"phantom_power\"]") < 0:
		_fail("nothing stamps phantom_power onto an egg, so the provenance is never recorded")
	else:
		_ok("a phantom egg is stamped with its provenance")
	# (b) the egg -> the companion
	var ch := FileAccess.get_file_as_string("res://shared/character.gd")
	var hi := ch.find("func _hatch_egg(")
	if hi < 0:
		_fail("_hatch_egg is gone - re-point this probe")
	else:
		var hj := ch.find("\nfunc ", hi + 8)
		var hbody := ch.substr(hi, (hj - hi) if hj > hi else 3000)
		if hbody.find("\"phantom_power\"") < 0:
			_fail("hatching DROPS phantom_power - the egg is special and the companion is ordinary, "
				+ "which is the silent version of this feature not existing")
		else:
			_ok("hatching carries the provenance onto the companion")
	# (c) the companion -> its actual power. Measured, not read.
	var plain := {"bonuses": {}, "sub_tier": 4, "border_tier": 0}
	var phantom := {"bonuses": {}, "sub_tier": 4, "border_tier": 0, "phantom_power": cap}
	var m_plain: float = DT.companion_stat_mult(plain)
	var m_phantom: float = DT.companion_stat_mult(phantom)
	print("  stat multiplier: ordinary %.3f vs phantom-born %.3f" % [m_plain, m_phantom])
	if m_phantom <= m_plain:
		_fail("a phantom-born companion has no more power than its duplicate - the whole point")
	else:
		_ok("a phantom-born companion is %.2fx its duplicate" % (m_phantom / maxf(m_plain, 0.001)))
	# ⛑ AND EVERY SITE USES THE TOTAL. `companion_variant_mult` was the chokepoint until provenance
	# became a second axis; a site left on the old function would make a companion stronger in
	# combat and ordinary on its own card, or the reverse.
	var stale := 0
	for line in ch.split("\n"):
		if String(line).find("companion_variant_mult(") >= 0:
			stale += 1
	if stale > 0:
		_fail("%d site(s) in character.gd still use companion_variant_mult - those read the "
			% stale + "variant alone and will disagree with combat about a phantom companion")
	else:
		_ok("every companion-power site in character.gd uses the total")

	print("")
	print("===== 4. AN ORDINARY COMPANION IS COMPLETELY UNCHANGED =====")
	# Every companion in every save today has no such key. Absent must read as zero everywhere,
	# or this feature silently re-tunes the entire existing population.
	if abs(DT.companion_phantom_mult({}) - 1.0) > 0.0001:
		_fail("a companion with no provenance is not 1.0x - every existing companion just changed")
	else:
		_ok("a companion with no provenance is exactly 1.0x")
	if abs(DT.companion_stat_mult(plain) - DT.companion_variant_mult(plain)) > 0.0001:
		_fail("the total differs from the variant multiplier for an ORDINARY companion")
	else:
		_ok("for an ordinary companion the total is the variant multiplier, unchanged")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a phantom-born companion is stronger than its duplicate, by about one")
	print("       grade, earned at the bottom, and every ordinary companion is untouched.")
	quit()
