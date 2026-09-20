extends SceneTree
## ⛑ DOES A PHANTOM'S REWARD ESCAPE THE SCALE THE GAME IS BALANCED ON?
##
## The five-surface audit (2026-09-19) found that the monster side of this feature is safe by
## construction — a phantom monster generated at level N is an ordinary level-N monster, so XP,
## threat, post anchoring, the death log and quest targets are all correct. It also found where the
## danger actually is:
##
## ⚡ **THE REWARD SIDE.** The archived design asks for eggs *"enhanced beyond the normal
## tier/sub-tier ceiling"*. Egg rank BECOMES the companion's `sub_tier`, which is worth up to 2x
## its stats and 2x the bonuses it grants, and `PowerRank.RANKS` is the hard top of that scale.
## Going past it would create a companion power tier nothing in the game has been balanced
## against — and unlike a monster level, there is no existing machinery that would make it correct.
##
## ⛑ SO THE IMPLEMENTATION READS "BEYOND THE CEILING" AS "RELIABLY AT IT": a deep, heavily-fed
## Phantom stops rolling LOW ranks rather than inventing high ones. This probe is what holds that
## line, because the temptation to add "just one more rank" is exactly how an uncapped reward
## starts.
##
## WHAT THIS ASSERTS:
##   1. no investment, at any depth, produces a rank above PowerRank.RANKS
##   2. the deep reward is still clearly better than the shallow one (or the risk buys nothing)
##   3. the guaranteed egg is gated on DEPTH, not on investment
##
## Run:
##   godot --headless --path . --script res://tools/probe/the_phantom_reward_stays_inside_the_ceiling.gd

const PM := preload("res://shared/phantom_model.gd")
const PowerRankScript := preload("res://shared/power_rank.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")

	print("")
	print("===== 1. THE RANK CEILING HOLDS =====")
	# The model's bonus is 0..2 and the server adds floor(bonus) to the ordinary roll, then clamps.
	# Check the clamp is really there rather than trusting the arithmetic.
	var i := srv.find("func _phantom_egg_rank(")
	if i < 0:
		_fail("_phantom_egg_rank is gone - the phantom egg bonus is unbounded or absent")
	else:
		var j := srv.find("\nfunc ", i + 8)
		var body := srv.substr(i, (j - i) if j > i else 2000)
		if body.find("clampi(") < 0 or body.find("PowerRankScript.RANKS") < 0:
			_fail("the phantom egg rank is not clamped to PowerRank.RANKS. Rank becomes a "
				+ "companion's sub_tier, worth up to 2x stats - past the top of that scale is a "
				+ "power tier nothing has been balanced against")
		else:
			_ok("the phantom egg rank is clamped to PowerRank.RANKS")
	# And the model's own bonus is bounded, so the clamp is a belt on top of braces rather than
	# the only thing standing between the player and an unbounded number.
	var worst: float = PM.egg_quality_bonus(9999, 20, {"eggs": {"Goblin": 100000}, "companions": 100000})
	print("  worst-case quality bonus from an absurd investment at absurd depth: %.3f" % worst)
	if worst > 2.0001:
		_fail("the model's egg bonus escapes its 0-2 range (%.3f)" % worst)
	else:
		_ok("the model's own bonus is bounded at 2.0")

	print("")
	print("===== 2. THE DEEP REWARD IS STILL WORTH THE RISK =====")
	# A ceiling that clamps everything to the same value would be "safe" and pointless: the player
	# would take the danger and get what the shallow floors already gave.
	var heavy := {"eggs": {"Goblin": 40}, "companions": 10}
	var shallow: float = PM.egg_quality_bonus(3, 20, heavy)
	var deep: float = PM.egg_quality_bonus(20, 20, heavy)
	print("  a well-stocked Phantom: %.3f at floor 3, %.3f at floor 20" % [shallow, deep])
	if deep < shallow * 10.0:
		_fail("the bottom is only %.1fx the top - not enough to pay for the danger"
			% (deep / maxf(shallow, 0.0001)))
	else:
		_ok("the bottom is %.0fx the top" % (deep / maxf(shallow, 0.0001)))
	# Gear too: companions are the gearing axis, and the same logic applies.
	var g_shallow: float = PM.gear_bonus(3, 20, heavy)
	var g_deep: float = PM.gear_bonus(20, 20, heavy)
	print("  gear bonus: %.3f at floor 3, %.3f at floor 20" % [g_shallow, g_deep])
	if g_deep <= g_shallow:
		_fail("gear does not improve with depth, so there is no reason to descend for it")
	else:
		_ok("gear improves with depth as well")

	print("")
	print("===== 3. THE CERTAIN EGG IS GATED ON DEPTH, NOT ON STOCKING =====")
	# ⚡ If investment alone could make an egg certain, a player could feed a post heavily and farm
	# floor one - which is the pump, and depth-risk is the ONLY thing the owner chose to stop it.
	# ⚡ BOUNDED TO THE SPAWNER. The first cut searched the whole file for
	# `guaranteed_egg_depth(` and found the FIRST one - which is in `_send_phantom_state`, the
	# message that tells the client where the certain egg is. It then judged that, and reported
	# the gate missing while the gate sat in a different function entirely. Fifth wrong-locator
	# in two days, and the fix is the same every time: name the function, bound the slice.
	# ⛑ AND IN THE RIGHT FUNCTION. The second cut bounded the search correctly but to
	# `_spawn_dungeon_floor_monsters` - which spawns MONSTERS. Floor loot is placed by
	# `_spawn_all_dungeon_floor_items`, so the probe reported the gate missing while the gate was
	# there, one function away. A bounded slice is only as good as the boundary being the right
	# one; this was found by asking which function the line is actually in rather than assuming.
	var NL := "
"
	var sp := srv.find("func _spawn_all_dungeon_floor_items(")
	if sp < 0:
		_fail("_spawn_all_dungeon_floor_items is gone - re-point this probe")
		sp = 0
	var sp_end := srv.find(NL + "func ", sp + 8)
	var seg := srv.substr(sp, (sp_end - sp) if sp_end > sp else 12000)
	var k := seg.find("guaranteed_egg_depth(")
	if k < 0:
		_fail("the floor spawner never consults guaranteed_egg_depth - there is no deterministic "
			+ "floor, so a heavy investment can still come back with nothing")
	else:
		_ok("the guaranteed egg is placed by depth")
	if seg.find("floor_num") < 0:
		_fail("the guaranteed-egg gate does not look at the floor number")
	else:
		_ok("the gate compares the floor the player has reached")
	if seg.find("investment_weight(") >= 0:
		_fail("the guaranteed egg is gated on INVESTMENT - stocking a post would make floor one "
			+ "certain, which is the laundering pump with its only brake removed")
	else:
		_ok("stocking a post does not make a shallow egg certain")

	print("")
	print("  For reference, where the certain egg falls:")
	for md in [4, 10, 20]:
		print("    a %2d-floor Phantom -> floor %d" % [md, PM.guaranteed_egg_depth(md)])

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the reward climbs steeply with depth, stays inside the scale the game is")
	print("       balanced on, and cannot be bought with stocking alone.")
	quit()
