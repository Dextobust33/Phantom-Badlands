extends SceneTree
## Does danger pay? And what does it do to how long a level takes?
##
## `_calculate_experience_reward` scales a kill by lethality (hp + 2*str + def) against an
## expectation for its level. That expectation used to be a hand-written `50 + level * 10`, written
## before the monster curve was ever calibrated - 2.5x low at L1, 75x low at L250 - so EVERY
## monster at EVERY level pinned the 1.4 clamp and the term was dead: a species six times deadlier
## than another paid identical XP. Measured then: 660 of 660 clamped.
##
## Owner 2026-09-15 chose to make danger pay AND to raise the average kill 15-20%. The expectation
## now comes from `_expected_lethality`, the mean of the level's own weighted spawn pool computed
## through `compute_anchored_stats` - the same function that builds a real monster - so it tracks
## the calibrated curve instead of a constant.
##
## This measures the result on REAL generated monsters, and the thing that actually matters to a
## player: kills per level, which must not drift away from what the early game was tuned to.
const MonsterDB = preload("res://shared/monster_database.gd")
const CharacterScript = preload("res://shared/character.gd")
const SAMPLES := 80
const OLD_FLAT_BONUS := 1.40   # what every monster used to get, because everything clamped

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _kills_per_level(level: int, mean_xp: float) -> float:
	var c = CharacterScript.new()
	c.level = level
	var need: float = float(c.xp_required_for_next_level(level)) if c.has_method("xp_required_for_next_level") else float(c.experience_to_next_level)
	# A kill also carries the flat +10% every victory applies.
	return need / maxf(1.0, mean_xp * 1.10)


func _init() -> void:
	var db = MonsterDB.new()
	get_root().add_child(db)
	print("level   expected    monster lethality      danger multiplier        clamped   kills/level")
	print("        lethality   min .. max             min .. mean .. max                 old -> new")
	var all_means: Array = []
	var any_spread := 0
	var levels := [1, 3, 5, 7, 10, 25, 50, 100, 250, 1000, 5000]
	for lvl in levels:
		var expected: float = db._expected_lethality(lvl)
		var bonuses: Array = []
		var leths: Array = []
		var xps: Array = []
		var clamped := 0
		for i in range(SAMPLES):
			var m: Dictionary = db.generate_monster(lvl, lvl)
			if m.is_empty():
				continue
			var leth: float = float(m.get("max_hp", 0)) + 2.0 * float(m.get("strength", 0)) + float(m.get("defense", 0))
			leths.append(leth)
			var b: float = clampf(MonsterDB.XP_DANGER_CENTRE + (leth / expected - 1.0) * MonsterDB.XP_DANGER_SLOPE,
				MonsterDB.XP_DANGER_MIN, MonsterDB.XP_DANGER_MAX)
			bonuses.append(b)
			if is_equal_approx(b, MonsterDB.XP_DANGER_MIN) or is_equal_approx(b, MonsterDB.XP_DANGER_MAX):
				clamped += 1
			xps.append(float(m.get("experience_reward", 0)))
		if bonuses.is_empty():
			continue
		var bmean := 0.0
		for b in bonuses:
			bmean += float(b)
		bmean /= float(bonuses.size())
		all_means.append(bmean)
		if clamped < bonuses.size():
			any_spread += 1
		var xmean := 0.0
		for x in xps:
			xmean += float(x)
		xmean /= float(xps.size())
		var kpl_new: float = _kills_per_level(lvl, xmean)
		var kpl_old: float = kpl_new * (bmean / OLD_FLAT_BONUS)
		print("%-7d %-11.0f %7.0f..%-13.0f %.2f .. %.2f .. %-8.2f %3d/%-3d   %5.1f -> %.1f" % [
			lvl, expected, float(leths.min()), float(leths.max()),
			float(bonuses.min()), bmean, float(bonuses.max()),
			clamped, bonuses.size(), kpl_old, kpl_new])

	var overall := 0.0
	for m in all_means:
		overall += float(m)
	overall /= float(all_means.size())
	print("")
	print("Mean danger multiplier across all levels: %.3f (the old flat value was %.2f)" % [overall, OLD_FLAT_BONUS])
	print("So the average kill is worth %.0f%% of what it was." % (100.0 * overall / OLD_FLAT_BONUS))
	ck(any_spread == all_means.size(), "the term VARIES at every level sampled (%d/%d)" % [any_spread, all_means.size()])
	var lift: float = overall / OLD_FLAT_BONUS
	# Band, not a point: this is a sampled mean, so a tight equality would fail on RNG alone.
	ck(lift >= 1.14 and lift <= 1.21, "the average kill pays 15-20%% more, as chosen (measured %.1f%%)" % ((lift - 1.0) * 100.0))
	ck(float(all_means.min()) > MonsterDB.XP_DANGER_MIN and float(all_means.max()) < MonsterDB.XP_DANGER_MAX,
		"no level's AVERAGE sits on a clamp (%.2f..%.2f inside %.2f..%.2f)" % [
			float(all_means.min()), float(all_means.max()), MonsterDB.XP_DANGER_MIN, MonsterDB.XP_DANGER_MAX])
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
