extends SceneTree
## ⛑ DOES COMMITTING TO A JOB STILL TAKE ANYTHING AWAY?
##
## Owner 2026-09-18: *"We may want to do away with locking people at level 5 of gathering/crafting
## jobs. Maybe let players specialize in a job to get additional xp in it and make leveling it give
## a benefit when doing it rather than gate anything."*
##
## ⛑ THERE WERE TWO GATES AND THE QUIET ONE WAS WORSE. The level-5 trial cap is the one everybody
## talks about. But `can_gain_job_xp` also read `return gathering_job == job_name` once you had
## committed - so choosing mining froze fishing, logging, foraging and soldier **permanently**.
## A player who committed had LESS access than one who never did, which is the opposite of a
## reward, and it is not what the cap was ever advertised to do.
##
## This probe EXECUTES the real character. A source-reading check cannot tell "the gate is gone"
## from "the gate moved", and four checks in this session have already passed while asserting
## nothing.
##
## Run:
##   godot --headless --path . --script res://tools/probe/jobs_are_a_carrot_not_a_fence.gd

const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _mk():
	var ch = CharacterScript.new()
	ch.initialize("Probe", "Fighter", "Human")
	return ch


func _init() -> void:
	print("")
	print("===== 1. NO LEVEL-5 WALL ON AN UNCOMMITTED JOB =====")
	var ch = _mk()
	# Pour in enough XP to blow well past the old cap.
	for _i in range(400):
		ch.add_job_xp("mining", 500)
	var lvl: int = int(ch.job_levels.get("mining", 1))
	print("  uncommitted mining after 200k XP: level %d" % lvl)
	if lvl <= CharacterScript.JOB_TRIAL_CAP:
		_fail("mining stopped at %d - the trial cap is still binding" % lvl)
	else:
		_ok("levelled past the old cap of %d without committing" % CharacterScript.JOB_TRIAL_CAP)

	print("")
	print("===== 2. COMMITTING DOES NOT FREEZE THE OTHERS =====")
	# ⛑ THE GATE THAT MATTERED. Commit to one, then check a DIFFERENT job still earns.
	var ch2 = _mk()
	for _i in range(20):
		ch2.add_job_xp("mining", 500)
	if not ch2.commit_gathering_job("mining"):
		_fail("could not commit to mining - the probe cannot test what it is here to test")
	else:
		var before: int = int(ch2.job_levels.get("fishing", 1))
		var before_xp: int = int(ch2.job_xp.get("fishing", 0))
		for _i in range(60):
			ch2.add_job_xp("fishing", 500)
		var after: int = int(ch2.job_levels.get("fishing", 1))
		var after_xp: int = int(ch2.job_xp.get("fishing", 0))
		print("  committed to mining; fishing went Lv%d -> Lv%d (xp %d -> %d)" % [
			before, after, before_xp, after_xp])
		if after <= before and after_xp <= before_xp:
			_fail("fishing earned NOTHING after committing to mining - the exclusivity gate is still there")
		else:
			_ok("a non-focus job keeps levelling normally")
		# And the same for the crafting side, which had the identical rule.
		var ch3 = _mk()
		for _i in range(20):
			ch3.add_job_xp("blacksmith", 500)
		if ch3.commit_specialty_job("blacksmith"):
			var b2: int = int(ch3.job_xp.get("scribe", 0))
			for _i in range(40):
				ch3.add_job_xp("scribe", 500)
			if int(ch3.job_xp.get("scribe", 0)) <= b2:
				_fail("scribe earned nothing after committing to blacksmith")
			else:
				_ok("the crafting side behaves the same way")

	print("")
	print("===== 3. COMMITTING IS WORTH SOMETHING =====")
	# ⛑ A carrot that pays nothing is just a removed fence. The bonus has to be MEASURABLE, and
	# measured on the XP that actually lands, not on the constant.
	# ⛑ BOTH SUBJECTS MUST START FROM THE SAME PLACE, and the first version of this check did not:
	# it levelled `keen` to ~10 to make it eligible to commit and left `plain` at level 1, then
	# compared `job_xp`, which is progress toward the NEXT level and RESETS on level-up. It
	# reported the bonus as 8.72x. The number was pure baseline mismatch - a harness defect that
	# would have read as a wild balance bug in a screenshot.
	var plain = _mk()
	var keen = _mk()
	for _i in range(20):
		plain.add_job_xp("mining", 500)
		keen.add_job_xp("mining", 500)
	keen.commit_gathering_job("mining")
	if int(plain.job_levels.get("mining", 1)) != int(keen.job_levels.get("mining", 1)):
		_fail("the two subjects are at different mining levels - the comparison is unsound")
	var p0: int = int(plain.job_xp.get("mining", 0))
	var k0: int = int(keen.job_xp.get("mining", 0))
	# A grant small enough that neither can level, so no reset can corrupt the delta.
	plain.add_job_xp("mining", 40)
	keen.add_job_xp("mining", 40)
	var p_gain: int = int(plain.job_xp.get("mining", 0)) - p0
	var k_gain: int = int(keen.job_xp.get("mining", 0)) - k0
	var ratio: float = float(k_gain) / maxf(1.0, float(p_gain))
	print("  same 40 XP at the same level: uncommitted +%d, committed +%d (%.2fx)" % [p_gain, k_gain, ratio])
	var want: float = 1.0 + CharacterScript.COMMITTED_JOB_XP_BONUS
	if absf(ratio - want) > 0.05:
		_fail("committed XP is %.2fx, expected %.2fx" % [ratio, want])
	else:
		_ok("the committed job earns %.0f%% more, as advertised" % ((want - 1.0) * 100.0))
	# The bonus must apply ONLY to the focus, or it is not a specialisation.
	var off0: int = int(keen.job_xp.get("fishing", 0))
	keen.add_job_xp("fishing", 40)
	var off_gain: int = int(keen.job_xp.get("fishing", 0)) - off0
	if off_gain > p_gain:
		_fail("the bonus leaked onto a non-focus job (%d vs %d)" % [off_gain, p_gain])
	else:
		_ok("and only in that job")

	print("")
	print("===== 4. NO SURFACE STILL SAYS 'LOCKED' =====")
	# ⛑ A rule change that leaves stale copy is this codebase's most repeated player-facing bug.
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	for phrase in ["✗ LOCKED", "trial cap Lv 5", "capped at Lv5", "Try any job up to Lv5"]:
		if cli.find(phrase) >= 0:
			_fail("the client still tells players: %s" % phrase)
	if _fails.is_empty():
		_ok("the jobs screen, the commit prompt and the help page all describe the new rule")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for f in _fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS jobs level freely, committing pays %.0f%% more in your focus and costs" % [
		CharacterScript.COMMITTED_JOB_XP_BONUS * 100.0])
	print("       nothing anywhere else.")
	quit()
