extends SceneTree
## How long will `rolecal` ACTUALLY take, measured, before committing 45 minutes to finding out.
##
## Owner 2026-09-12: *"Ensure we aren't running into the same problem that caused it to run for a
## longer period of time last time."*
##
## What happened last time: the run was abandoned at 45 minutes "with no end in sight". 45 minutes
## is not a coincidence - it is `DEFAULT_BUDGET_SECONDS := 2700`, the simulator's own watchdog
## deadline, past which it aborts and prints "results are INCOMPLETE and must not be used". The
## run was going to produce nothing whether it was stopped or not, because nobody raised
## `--budget`. So the question is not "is it slow" but "what budget does it need".
##
## The shape of the work is fixed and knowable:
##   3 roles x 7 anchor levels x (6 correction passes + 1 verify) = 147 batches
##   each batch is `maxi(30, _audit_n)` = 40 real fights
## so timing ONE batch per level and summing gives 1/21 of the run. That is the projection.
const SimScript = preload("res://tools/combat_simulator/real_combat_sim.gd")

const LEVELS := [1, 10, 50, 250, 1000, 5000, 10000]
const ROLES := 3
const BATCHES_PER_LEVEL := 7   # 6 correction passes + 1 verify


func _init() -> void:
	var sim = SimScript.new()
	var samples: int = maxi(30, int(sim._audit_n))
	print("[PROJECT] samples per batch = %d (from _audit_n = %d)" % [samples, sim._audit_n])

	var total_s := 0.0
	var per_level: Array = []
	for lvl in LEVELS:
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = sim._role_fight_stats(lvl, "elite", samples)
		var dt := float(Time.get_ticks_msec() - t0) / 1000.0
		if r.is_empty():
			print("[PROJECT] L%-6d batch returned NOTHING - the instrument is broken, stop here" % lvl)
			quit(1)
			return
		per_level.append(dt)
		total_s += dt
		print("[PROJECT] L%-6d one batch of %d fights: %6.1f s   (win %.2f)" % [
			lvl, samples, dt, float(r.get("win", -1.0))])

	# 21 = 3 roles x 7 batches per level. The sum above already walks every level once.
	var projected := total_s * float(ROLES) * float(BATCHES_PER_LEVEL)
	print("\n[PROJECT] one pass over all 7 levels: %.1f s" % total_s)
	print("[PROJECT] full rolecal = that x %d roles x %d batches = %.0f s (%.1f min)" % [
		ROLES, BATCHES_PER_LEVEL, projected, projected / 60.0])
	# Headroom, because the projection uses ELITE for every role and a boss fight is longer.
	var budget := int(ceil(projected * 1.8 / 60.0)) * 60
	print("[PROJECT] the DEFAULT budget is 2700 s (45 min) - %s" % [
		"ENOUGH" if projected < 2400.0 else "NOT ENOUGH, this is why the last run died"])
	print("[PROJECT] recommended:  -- rolecal --budget=%d   (%.0f min, 1.8x headroom for bosses)" % [
		budget, float(budget) / 60.0])
	quit(0)
