extends SceneTree
## ⛑ DOES THE PHANTOM'S OWN DIFFICULTY BAND LEAK INTO THE OVERWORLD'S?
##
## Owner's decision 1, 2026-09-19: a Phantom gets its **own band, scaled by investment**, so the
## calibrated overworld curve is never consulted and never disturbed. That decision is what makes
## the whole loop balanceable — but it creates a hazard that has bitten this project before, in
## almost the same words.
##
## ⚡ `base_tier` IS NOT `tier`. CLAUDE.md records six player-facing leaks and two reward-formula
## leaks from exactly this shape: two different numbers that look alike, and a surface reading the
## wrong one. A phantom monster's level and an overworld monster's level will look identical on the
## wire — an integer called `level` — and mean completely different things. A level-73 phantom
## monster is not a level-73 overworld monster: it exists in a band that the curve knows nothing
## about, so paying XP, setting threat, or anchoring a post from it would all be wrong, and wrong
## QUIETLY.
##
## WHAT THIS ASSERTS, while the feature is still held and cheap to shape:
##   1. the model never consults the calibrated curve
##   2. the model's own output is self-consistent (deeper is never safer)
##   3. ⚑ the moment anything live calls the model, this probe demands the audit be done
##
## ⛑ (3) IS THE POINT OF WRITING THIS NOW. Today nothing calls `PhantomModel`, so there is nothing
## to leak and this passes trivially. It is armed so that the FIRST wiring of a phantom level into
## generation fails here, with the list of surfaces to check, rather than shipping and being found
## in a reward formula three weeks later.
##
## Run:
##   godot --headless --path . --script res://tools/probe/a_phantom_level_is_not_an_overworld_level.gd

const PM := preload("res://shared/phantom_model.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	print("")
	print("===== 1. THE MODEL DOES NOT TOUCH THE CALIBRATED CURVE =====")
	# ⚡ CODE ONLY, COMMENTS STRIPPED. This check FAILED on its first run - against the
	# docstring in phantom_model.gd that says "`reference_monster_curve.json` is not consulted
	# here". The fifth time in a week a probe here has matched prose describing the check instead
	# of the thing being checked. A file that EXPLAINS it does not read the curve is not a file
	# that reads it.
	var src := ""
	for raw_line in FileAccess.get_file_as_string("res://shared/phantom_model.gd").split("
"):
		var t := String(raw_line).strip_edges()
		if t.begins_with("#"):
			continue
		# An end-of-line comment counts too, and a `#` cannot appear in GDScript code outside a
		# string - none of which this file contains.
		var hash_at := String(raw_line).find("#")
		src += (String(raw_line).substr(0, hash_at) if hash_at >= 0 else String(raw_line)) + "
"
	for forbidden in ["reference_monster_curve", "_reference_anchors", "species_power",
			"role_multipliers", "monster_database"]:
		if src.find(forbidden) >= 0:
			_fail("phantom_model.gd references `%s` - the Phantom is supposed to have its OWN "
				% forbidden + "band, and reading the shared curve is how it stops having one")
		else:
			_ok("does not reference %s" % forbidden)

	print("")
	print("===== 2. THE BAND IS SELF-CONSISTENT =====")
	# Deeper must never be safer, at any investment, for any local level. Cheap to check
	# exhaustively while it is pure.
	var bad := 0
	for local in [1, 12, 30, 90, 400]:
		for eggs in [0, 5, 40, 400]:
			var inv := {"eggs": {"Goblin": eggs}, "companions": eggs / 4}
			var md := 20
			var prev := -1
			for d in range(1, md + 1):
				var lv: int = PM.floor_level(d, md, local, inv)
				if lv < prev:
					bad += 1
				prev = lv
	if bad > 0:
		_fail("%d depth steps got EASIER as they went deeper" % bad)
	else:
		_ok("across 20 combinations, deeper is never safer")
	# And the first floor is the local level exactly - the player's only honest warning.
	# ⛑ Tracked LOCALLY, not by asking whether `_fails` is empty. The first cut reported this
	# section's success only when no EARLIER section had failed, so one unrelated failure hid a
	# genuine pass - a check whose result depends on another check's result is not a check.
	var first_floor_ok := true
	for local in [1, 30, 400]:
		var heavy := {"eggs": {"Goblin": 500}, "companions": 200}
		if PM.floor_level(1, 20, local, heavy) != local:
			first_floor_ok = false
			_fail("the first floor of a heavily stocked Phantom is not the local level, so a "
				+ "player cannot tell what they walked into by walking into it")
	if first_floor_ok:
		_ok("the first floor always equals the local level")

	print("")
	print("===== 3. THE AUDIT, ARMED FOR WHEN THIS GOES LIVE =====")
	# ⚑ The surfaces that read a monster's level and would be WRONG for a phantom one. Listed by
	# name so that whoever wires generation has the checklist in front of them rather than having
	# to rediscover it.
	var surfaces := [
		"XP payout (a phantom level is not worth an overworld level's XP)",
		"threat / hotzone escalation (a phantom is not a thing happening in the country)",
		"post anchoring (get_post_anchored_level must not see phantom levels)",
		"the death log's level-gap column (parity against WHICH level?)",
		"quest 'kill a level N' targets",
	]
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	# Live generation is the trigger: the state message quoting a level to the player is fine, a
	# SPAWNED monster carrying one is not.
	var generating: bool = srv.find("phantom_floor_monster") >= 0 or srv.find("_spawn_phantom_") >= 0
	print("  phantom levels reaching generation: %s" % str(generating))
	if generating:
		_fail("a phantom level now reaches monster generation. Before shipping that, check every "
			+ "surface below reads the RIGHT level:")
		for sfc in surfaces:
			_fail("   - %s" % sfc)
	else:
		_ok("nothing spawns from a phantom level yet - this probe is armed for when it does")
		print("")
		print("  When it does, these are the surfaces to check:")
		for sfc in surfaces:
			print("    - %s" % sfc)

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the Phantom's band is its own, internally consistent, and not yet reaching")
	print("       anything that would mistake it for the overworld's.")
	quit()
