extends SceneTree
## ⛑ SOLVE FOR HOW OFTEN A PLAYER GETS OUT, FROM A RATE THAT IS ACTUALLY OBSERVABLE.
##
## The simulator needs to know how often a losing player escapes instead of dying. Two attempts at
## this were both wrong, in opposite directions:
##
##   ALWAYS FLEE (below 30% HP)  -> refcal reported 0.0% death at every level. Uninformative.
##   1 IN 44 (from death logs)   -> 5.1% death at L1 rising to 39% at L1000. Unshippable under
##                                  permadeath, and the figure itself came from a sample that
##                                  CANNOT contain a successful flee - only characters who died.
##
## ⚑ SO CALIBRATE IT AGAINST SOMETHING THE LIVE SERVER CAN ACTUALLY TELL US. Deaths per encounter
## is observable and unbiased: every character, dead or alive, records `monsters_killed`, and the
## leaderboard records the deaths. Measured 2026-09-18:
##
##     50 deaths / (2716 kills + 50 deaths) = 1.81% per encounter
##
## The flee rate is then whatever reproduces that. It is a PROXY for every out a real player has -
## fleeing, potions, walking away - not a claim about the flee command specifically.
##
## ⛑ MEASURED AT L1-10 ONLY, and that limit is the honest part. Every one of the 50 deaths is at
## L1-24 and 80% at L1-9, so those are the only levels where a live death rate exists to fit. What
## the same flee rate implies higher up is REPORTED, not fitted, because nothing up there has been
## observed yet - the highest living character is L25-49.
##
## Run:
##   godot --headless --path . --script res://tools/probe/flee_rate_matches_live.gd

const SimScript := preload("res://tools/combat_simulator/real_combat_sim.gd")

## Live server, 2026-09-18. 50 current-era deaths over 2766 encounters.
const LIVE_DEATH_PER_ENCOUNTER := 0.0181

const FIT_LEVELS := [1, 3, 5, 10]
const RATES := [0.0, 0.10, 0.25, 0.40, 0.55, 0.70, 0.85, 1.0]


## Death rate across FIT_LEVELS at a given flee rate.
func _death_rate(sim, rate: float, levels: Array, samples: int) -> float:
	sim._flee_rate = rate
	var deaths := 0.0
	var n := 0
	for lvl in levels:
		var r: Dictionary = sim._fight_stats_at(int(lvl), samples)
		if r.is_empty():
			continue
		deaths += float(r.get("death", 0.0))
		n += 1
	return deaths / maxf(1.0, float(n))


func _init() -> void:
	var sim = SimScript.new()
	print("")
	print("===== WHAT FLEE RATE REPRODUCES THE LIVE DEATH RATE? =====")
	print("  live: 50 deaths / 2766 encounters = %.2f%% per encounter" % (100.0 * LIVE_DEATH_PER_ENCOUNTER))
	print("  fitted at L%s - the only band where live deaths exist" % str(FIT_LEVELS))
	print("")
	print("  %-12s %14s" % ["flee rate", "death/encounter"])
	var best := 0.0
	var best_err := 1e9
	for rate in RATES:
		var d: float = _death_rate(sim, float(rate), FIT_LEVELS, 40)
		var err: float = absf(d - LIVE_DEATH_PER_ENCOUNTER)
		if err < best_err:
			best_err = err
			best = float(rate)
		var mark := ""
		if d > LIVE_DEATH_PER_ENCOUNTER * 1.5:
			mark = "   too lethal"
		elif d < LIVE_DEATH_PER_ENCOUNTER * 0.5:
			mark = "   too safe"
		print("  %-12.2f %13.2f%%%s" % [rate, 100.0 * d, mark])
	print("")
	print("  CLOSEST: flee rate %.2f  (live %.2f%%)" % [best, 100.0 * LIVE_DEATH_PER_ENCOUNTER])
	print("")
	print("===== WHAT THAT RATE IMPLIES HIGHER UP - reported, NOT fitted =====")
	print("  nothing above L24 has died on the live server, so these are a projection.")
	print("  %-8s %14s" % ["level", "death/encounter"])
	for lvl in [25, 50, 100, 250, 1000]:
		var d: float = _death_rate(sim, best, [lvl], 40)
		print("  L%-7d %13.2f%%" % [lvl, 100.0 * d])
	print("")
	quit()
