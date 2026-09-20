extends SceneTree
## ⛑ CAN THE PHANTOM LOOP BE FARMED WITHOUT RISK?
##
## Owner 2026-09-19, choosing how to stop the laundering pump (invest cheap eggs → extract better
## ones → hatch → invest those → repeat): **depth and survival risk, and nothing else.** Diminishing
## returns, a lossy exchange and a cooldown were all offered and all rejected.
##
## ⚡ THAT CHOICE PUTS THE ENTIRE WEIGHT ON ONE PROPERTY: volume must buy nothing that depth does
## not also demand. If stocking a post harder made a SHALLOW descent more lucrative, the loop would
## be farmable in safety and there is no second guard to catch it. Every assertion here is a test of
## that one property, from a different angle.
##
## The model is pure functions, so this measures the real thing rather than a description of it —
## no server, no dungeon, no generation.
##
## Run:
##   godot --headless --path . --script res://tools/probe/the_phantom_pump_is_shut.gd

const PM := preload("res://shared/phantom_model.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _inv(eggs: int, comps: int) -> Dictionary:
	return {"eggs": {"Goblin": eggs}, "companions": comps}


func _init() -> void:
	var MAXD := 20

	print("")
	print("===== 1. VOLUME DOES NOT PAY AT SHALLOW DEPTH =====")
	# The pump's move is to stock heavily and then farm the safe floors. If that works, the loop is
	# open, because the owner's design has no other guard.
	var poor := _inv(0, 0)
	var rich := _inv(400, 100)          # an absurd hoard, far beyond any real player
	print("  %-10s %-14s %-14s" % ["depth", "empty post", "400 eggs+100 comp"])
	for d in [1, 2, 4, 10, 16, 20]:
		var a: float = PM.egg_quality_bonus(d, MAXD, poor)
		var b: float = PM.egg_quality_bonus(d, MAXD, rich)
		print("  %-10d %-14.3f %-14.3f" % [d, a, b])
	var shallow_gain: float = PM.egg_quality_bonus(2, MAXD, rich) - PM.egg_quality_bonus(2, MAXD, poor)
	var deep_gain: float = PM.egg_quality_bonus(20, MAXD, rich) - PM.egg_quality_bonus(20, MAXD, poor)
	print("  a hoard buys %.3f at depth 2, and %.3f at depth 20" % [shallow_gain, deep_gain])
	if shallow_gain > 0.05:
		_fail("stocking a post pays %.3f on floor 2 - the loop can be farmed in safety, and depth "
			% shallow_gain + "risk was the ONLY guard chosen against exactly that")
	else:
		_ok("a hoard is worth almost nothing on the shallow floors")
	if deep_gain <= shallow_gain * 8.0:
		_fail("the deep payoff (%.3f) is not decisively larger than the shallow one (%.3f), so "
			% [deep_gain, shallow_gain] + "there is little reason to take the risk")
	else:
		_ok("the payoff is overwhelmingly at the bottom, where the danger is")

	print("")
	print("===== 2. DANGER RISES WITH THE REWARD =====")
	# Decision 1: the Phantom has its own band, scaled by investment. If reward rose and danger did
	# not, "gated by survival risk" would be a phrase rather than a mechanism.
	print("  %-10s %-12s %-12s" % ["depth", "level (empty)", "level (rich)"])
	var last_poor := 0
	var last_rich := 0
	for d in [1, 5, 10, 15, 20]:
		var lp: int = PM.floor_level(d, MAXD, 30, poor)
		var lr: int = PM.floor_level(d, MAXD, 30, rich)
		print("  %-10d %-12d %-12d" % [d, lp, lr])
		if lp < last_poor or lr < last_rich:
			_fail("floor level went DOWN with depth - deeper must never be safer")
		last_poor = lp
		last_rich = lr
	if PM.floor_level(20, MAXD, 30, rich) <= PM.floor_level(20, MAXD, 30, poor):
		_fail("a heavily stocked Phantom is no more dangerous at the bottom than an empty one, so "
			+ "its far larger rewards are free")
	else:
		_ok("a stocked Phantom is more dangerous where it is more rewarding")
	# ⛑ And the TOP is unchanged by investment: the player should be able to learn how bad it gets
	# by descending, not by reading a number before they go in.
	if PM.floor_level(1, MAXD, 30, rich) != PM.floor_level(1, MAXD, 30, poor):
		_fail("investment changes the FIRST floor, so a stocked Phantom is dangerous before the "
			+ "player has any way to find that out")
	else:
		_ok("the first floor is the same either way - you learn by descending")

	print("")
	print("===== 3. A HOARD IS NOT A SHORTCUT =====")
	# Saturating rather than linear, or the hundredth egg is worth as much as the first and volume
	# becomes the lever the owner declined to grant.
	print("  %-16s %s" % ["investment", "weight"])
	var prev := -1.0
	for pair in [[0, 0], [10, 2], [40, 10], [100, 25], [400, 100], [4000, 1000]]:
		var w: float = PM.investment_weight(_inv(pair[0], pair[1]))
		print("  %-16s %.3f" % ["%d eggs, %d comp" % [pair[0], pair[1]], w])
		if w < prev:
			_fail("more investment produced LESS weight")
		prev = w
	var w40: float = PM.investment_weight(_inv(40, 10))
	var w4000: float = PM.investment_weight(_inv(4000, 1000))
	if w4000 > w40 * 1.6:
		_fail("a 100x hoard is worth %.2fx a modest investment - volume is a shortcut"
			% (w4000 / maxf(w40, 0.001)))
	else:
		_ok("100x the investment is worth %.2fx the modest one - the curve saturates"
			% (w4000 / maxf(w40, 0.001)))
	if PM.investment_weight(_inv(4000, 1000)) > 1.0:
		_fail("the weight escapes its 0-1 range, so everything scaled by it is unbounded")
	else:
		_ok("the weight stays bounded")

	print("")
	print("===== 4. THE GUARANTEED EGG IS DEEP =====")
	# Decision 3 gives a deterministic floor so effort always pays. Decision 2 means it has to sit
	# where the danger is - a guaranteed egg on floor 2 IS the pump.
	for md in [4, 10, 20]:
		var g: int = PM.guaranteed_egg_depth(md)
		print("  max depth %-4d -> guaranteed egg at floor %d (%.0f%% down)"
			% [md, g, 100.0 * float(g) / float(md)])
		if float(g) / float(md) < 0.6:
			_fail("the guaranteed egg sits %.0f%% down a %d-floor Phantom - shallow enough to farm"
				% [100.0 * float(g) / float(md), md])
	if _fails.is_empty():
		_ok("the certain egg is always in the dangerous part")

	print("")
	print("===== 5. FURTHER OUT IS DEEPER =====")
	print("  %-12s %s" % ["distance", "max depth"])
	var lastd := 0
	for dist in [0.0, 300.0, 900.0, 1600.0, 2200.0, 2800.0]:
		var md: int = PM.max_depth_for(dist)
		print("  %-12.0f %d" % [dist, md])
		if md < lastd:
			_fail("a further-out post got a SHALLOWER Phantom")
		lastd = md
	if PM.max_depth_for(0.0) >= PM.max_depth_for(2200.0):
		_fail("distance does not deepen the Phantom, so there is no reason to push out")
	else:
		_ok("a frontier Phantom is longer than a homely one")

	print("")
	print("===== 6. THE GROUND REMEMBERS, BUT DOES NOT FORGET =====")
	var mixed := {"eggs": {"Goblin": 30, "Harpy": 10}, "companions": 0}
	var w: Dictionary = PM.species_weights(mixed)
	print("  30 goblin + 10 harpy -> %s" % str(w))
	if w.is_empty():
		_fail("investment produced no spawn weighting at all")
	else:
		if float(w.get("Goblin", 0.0)) <= float(w.get("Harpy", 0.0)):
			_fail("the species fed MOST is not the most likely to spawn")
		else:
			_ok("the species fed most is the most likely")
		# ⛑ Nothing driven to zero: a Phantom that spawns exactly one thing is a worse place than
		# one with a strong theme, and the fiction is that the ground remembers - not that it forgets.
		for k in w.keys():
			if float(w[k]) <= 0.0:
				_fail("%s was driven to zero weight" % k)
	if not PM.species_weights({"eggs": {}, "companions": 3}).is_empty():
		_fail("a post with no eggs still claims a species theme")
	else:
		_ok("an unstocked post uses the ordinary spawn table")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the payoff lives at the bottom, the danger rises with it, and no amount of")
	print("       stocking makes a safe descent worth doing.")
	quit()
