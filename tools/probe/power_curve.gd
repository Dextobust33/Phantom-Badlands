extends SceneTree
## ⛑ THE CURVE EVERY CRAFTED THING IS SIZED AGAINST MUST RISE, AND MUST BE STABLE.
##
## `DropTables.expected_item_power(level)` is the single source the crafting arc sizes against -
## recipe base stats, rune caps and the enchantment ceiling all derive from it. Two properties have
## to hold or it silently produces a broken ladder:
##
##   1. **MONOTONIC.** A higher-level item must be worth more. This is not hypothetical: at the
##      first sample size tried (40) the median was non-monotonic - 33 at level 5 against 19 at
##      level 15, and 685 at 140 against 603 at 150. Recipes sized against that would have gone
##      BACKWARDS in places, and the defect would have read as a content mistake rather than as a
##      sample size.
##   2. **STABLE.** Two runs must agree closely, or a recipe's stats depend on when it was first
##      crafted on that server.
##
## Run:
##   godot --headless --path . --script res://tools/probe/power_curve.gd

const DT := preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var dt = DT.new()
	get_root().add_child(dt)
	seed(31337)

	var levels := [5, 15, 30, 50, 70, 90, 100, 120, 150]
	var vals: Array = []
	print("===== THE CURVE =====")
	for lvl in levels:
		var v: float = dt.expected_item_power(lvl)
		vals.append(v)
		print("  level %-4d -> %.0f" % [lvl, v])

	print("")
	print("===== IT RISES =====")
	var dips: Array = []
	for i in range(1, vals.size()):
		if float(vals[i]) < float(vals[i - 1]):
			dips.append("%d(%.0f) < %d(%.0f)" % [
				int(levels[i]), float(vals[i]), int(levels[i - 1]), float(vals[i - 1])])
	ck(dips.is_empty(), "no level is worth less than a lower one%s" % (
		"" if dips.is_empty() else " - dips: " + ", ".join(dips)))
	ck(float(vals[vals.size() - 1]) > float(vals[0]) * 5.0,
		"and it actually climbs (%.0f at level %d vs %.0f at %d)" % [
			float(vals[vals.size() - 1]), int(levels[levels.size() - 1]), float(vals[0]), int(levels[0])])

	print("")
	print("===== IT IS STABLE =====")
	# The cache makes a repeat call identical by construction; the real question is whether a
	# FRESH instance lands in the same place, because that is a different server restarting.
	var dt2 = DT.new()
	get_root().add_child(dt2)
	var worst := 0.0
	for i in range(levels.size()):
		var a: float = float(vals[i])
		var b: float = dt2.expected_item_power(int(levels[i]))
		var drift: float = absf(b - a) / maxf(1.0, a)
		worst = maxf(worst, drift)
	print("  worst drift between two independent samplings: %.0f%%" % (worst * 100.0))
	ck(worst < 0.35, "a fresh sampling lands close to the first (%.0f%% worst drift)" % (worst * 100.0))
	ck(dt.expected_item_power(30) == dt.expected_item_power(30), "and the cache is exact on repeat")

	print("")
	if fails == 0:
		print("[PROBE] PASS the power curve rises and holds still")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
