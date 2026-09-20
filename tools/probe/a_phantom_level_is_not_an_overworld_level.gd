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
	print("===== 3. GENERATION GOES THROUGH THE ORDINARY GENERATOR =====")
	# ⚑ THE AUDIT WAS DONE 2026-09-19, BEFORE ANY GENERATION EXISTED, and it changed what this
	# section should check. The original version asserted "nothing spawns from a phantom level
	# yet", which is a countdown rather than a guard - it would have passed until the day it
	# mattered and then demanded a checklist nobody had done.
	#
	# What the audit found: `generate_monster_by_name(name, level)` derives stats AND xp from that
	# level, so a monster generated at level 73 IS a level-73 monster - correct stats, correct XP,
	# correctly dangerous. Threat, hotzones and post anchoring are functions of world POSITION and
	# never see a phantom at all. So all five surfaces are correct BY CONSTRUCTION, on one
	# condition: phantom floors spawn through the ordinary generator.
	#
	# ⚡ THE FAILURE THIS NOW CATCHES is the tempting one - hand-building a monster's stats to
	# "make it phantom-ish". That single shortcut breaks XP, the death log's gap column and quest
	# targets simultaneously, and every one of them silently.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	# The hook is INSIDE the ordinary floor spawner, not a forked one - one code path for phantom
	# and ordinary floors, so they cannot drift apart. So the probe reads that function.
	var pi := srv.find("func _spawn_dungeon_floor_monsters(")
	if pi < 0:
		_fail("_spawn_dungeon_floor_monsters is gone - re-point this probe")
	else:
		var pj := srv.find("
func ", pi + 8)
		var pbody := srv.substr(pi, (pj - pi) if pj > pi else 4000)
		if pbody.find("generate_monster_by_name(") < 0:
			_fail("phantom generation does not use generate_monster_by_name. Stats built by hand "
				+ "break XP, the death-log gap column and quest targets at once, all silently")
		else:
			_ok("phantom floors spawn through the ordinary generator")
		# The level must come from the model, or the floor is just an ordinary dungeon.
		if pbody.find("floor_level(") < 0:
			_fail("phantom generation does not ask the model for its level")
		else:
			_ok("the level comes from PhantomModel.floor_level")
		# And nothing may hand-write the stats the generator is responsible for.
		for forbidden in ["\"max_hp\"] =", "\"strength\"] =", "\"defense\"] ="]:
			if pbody.find(forbidden) >= 0:
				_fail("phantom generation assigns %s directly - that is the hand-built-stats "
					% forbidden.strip_edges() + "failure this section exists to catch")

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
