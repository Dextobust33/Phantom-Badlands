extends SceneTree
## ⛑ CAN A REAL PLAYER EVER BUY ANYTHING IN THE SANCTUARY?
##
## Owner 2026-09-18: *"most of the choices take too many baddie points, players are playing lots of
## characters and still not having enough for upgrades."*
##
## ⚡ MEASURED ON THE LIVE SERVER 2026-09-19 AND IT WAS WORSE THAN THAT. A median real death earned
## **4** points against a cheapest upgrade of **250** - 62 deaths for the smallest thing on the
## menu. Across 13 live sanctuaries, NINE had never earned a single point and NOT ONE had ever
## reached 5,000 lifetime. The upper two thirds of the ladder was unreachable content.
##
## ⛑ THE SHAPE WAS ALSO WRONG. Points came almost entirely from level milestones (50 at L10, 150 at
## L25) while 40 of 50 real deaths happen at levels 1-9 and clear none of them. The counterweight to
## permadeath paid nothing to the players feeling permadeath most.
##
## This asserts REACHABILITY, not bigger numbers: how many deaths each rung costs a typical
## character, judged against bands the owner chose ("a few deaths per early rung").
const PersistenceScript := preload("res://server/persistence_manager.gd")
const CharacterScript := preload("res://shared/character.gd")

## What a typical low-level death looks like on the live server: level 2-3, a few hundred XP,
## single-digit kills. Taken from the death log, not invented.
const TYPICAL_XP := 250
const TYPICAL_KILLS := 9
const TYPICAL_LEVEL := 3

## The owner's bands. An early rung should be a few deaths, not a career.
const EARLY_RUNG_MAX_DEATHS := 10
const MID_RUNG_MAX_DEATHS := 60

var _fails: Array = []
func _fail(m: String) -> void:
	_fails.append(m); print("  FAIL  %s" % m)
func _ok(m: String) -> void:
	print("  ok    %s" % m)

func _init() -> void:
	var pm = PersistenceScript.new()
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Fighter", "Human")
	ch.experience = TYPICAL_XP
	ch.monsters_killed = TYPICAL_KILLS
	ch.level = TYPICAL_LEVEL
	var per_death: int = int(pm.calculate_baddie_points(ch))

	print("")
	print("===== 1. WHAT A TYPICAL DEATH IS WORTH =====")
	print("  a level-%d character with %d XP and %d kills earns %d points"
		% [TYPICAL_LEVEL, TYPICAL_XP, TYPICAL_KILLS, per_death])
	print("  (the same character earned 4 before 2026-09-19)")
	if per_death <= 10:
		_fail("a typical death earns %d - the sanctuary is still out of reach" % per_death)
	else:
		_ok("a death pays for the attempt, not just for milestones it never reached")

	print("")
	print("===== 2. A LOW-LEVEL DEATH IS NOT WORTH NOTHING =====")
	# ⛑ THE CASE THAT WAS BROKEN. 40 of 50 real deaths are levels 1-9 and clear no milestone.
	var ch2 = CharacterScript.new()
	ch2.initialize("Probe", "Fighter", "Human")
	ch2.experience = 40
	ch2.monsters_killed = 1
	ch2.level = 2
	var low: int = int(pm.calculate_baddie_points(ch2))
	print("  a level-2 death with 40 XP and 1 kill earns %d points" % low)
	if low <= 5:
		_fail("a level-2 death still earns %d - the band where deaths ACTUALLY happen pays nothing" % low)
	else:
		_ok("the band where most deaths happen now pays something")

	print("")
	print("===== 3. EVERY FIRST RUNG IS A FEW DEATHS =====")
	print("  %-20s %8s %10s" % ["upgrade", "cost", "deaths"])
	var worst_early := 0
	for name in PersistenceScript.HOUSE_UPGRADES.keys():
		var up: Dictionary = PersistenceScript.HOUSE_UPGRADES[name]
		var costs: Array = up.get("costs", [])
		if costs.is_empty():
			continue
		var first: int = int(costs[0])
		var deaths: int = int(ceil(float(first) / float(maxi(1, per_death))))
		worst_early = maxi(worst_early, deaths)
		print("  %-20s %8d %10d" % [name, first, deaths])
		if deaths > EARLY_RUNG_MAX_DEATHS:
			_fail("%s's FIRST rung costs %d deaths - not 'a few'" % [name, deaths])
	if worst_early <= EARLY_RUNG_MAX_DEATHS:
		_ok("no first rung costs more than %d deaths" % EARLY_RUNG_MAX_DEATHS)

	print("")
	print("===== 4. HOW FAR UP THE LADDER A PLAYER CAN REALISTICALLY GET =====")
	# ⛑ REPORTED, NOT GATED. The top rungs are meant to be a long chase and the owner said so; what
	# this must never hide is a rung so far away it is not content at all.
	for name in PersistenceScript.HOUSE_UPGRADES.keys():
		var costs: Array = PersistenceScript.HOUSE_UPGRADES[name].get("costs", [])
		if costs.is_empty():
			continue
		var running := 0
		var reachable := 0
		for c in costs:
			running += int(c)
			if int(ceil(float(running) / float(maxi(1, per_death)))) <= 200:
				reachable += 1
		var top: int = int(costs[costs.size() - 1])
		print("  %-20s %d of %d rungs within 200 deaths; top rung alone = %d deaths"
			% [name, reachable, costs.size(), int(ceil(float(top) / float(maxi(1, per_death))))])

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a death pays for the attempt, a low-level death is worth something, and")
	print("       every first rung is a few deaths rather than a career.")
	quit()
