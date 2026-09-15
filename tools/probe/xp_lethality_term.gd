extends SceneTree
## Is the XP formula's "tough monsters pay more" term still alive? And what would replace it?
##
## `_calculate_experience_reward` scales a kill by lethality (hp + 2*str + def) against a
## hand-written `expected_lethality = 50 + level * 10`, clamped to 0.7-1.4. That constant was
## written before the monster curve was calibrated, and the curve has moved several times since.
## MEASURED against real generated monsters: every monster at every level clamps at 1.4, so the
## term does nothing - a monster six times deadlier than another of its level pays the same XP.
##
## Owner 2026-09-15 chose to make danger pay, and to pay more overall. So this also measures what
## "expected for this level" should be: the REAL spawn mix's mean lethality, expressed against the
## calibrated curve's own hp/str at that level, so the replacement reads the curve rather than a
## second hand-written constant that will go stale the same way.
const MonsterDB = preload("res://shared/monster_database.gd")
const SAMPLES := 60

func _init() -> void:
	var db = MonsterDB.new()
	get_root().add_child(db)
	print("level  n   lethality  mean     spread(x mean)   curve hp+2str   mean/curve   old bonus")
	var factors: Array = []
	var spreads: Array = []
	for lvl in [1, 3, 5, 7, 10, 25, 50, 100, 250, 1000, 5000]:
		var leths: Array = []
		for i in range(SAMPLES):
			var m: Dictionary = db.generate_monster(lvl, lvl)
			if m.is_empty():
				continue
			leths.append(float(m.get("max_hp", 0)) + 2.0 * float(m.get("strength", 0)) + float(m.get("defense", 0)))
		if leths.is_empty():
			continue
		var mean := 0.0
		for l in leths:
			mean += float(l)
		mean /= float(leths.size())
		var ref: Dictionary = db._reference_at(lvl)
		var curve: float = float(ref.get("hp", 0.0)) + 2.0 * float(ref.get("str", 0.0))
		var factor: float = mean / maxf(1.0, curve)
		factors.append(factor)
		spreads.append(float(leths.min()) / mean)
		spreads.append(float(leths.max()) / mean)
		var old_ratio: float = mean / (50.0 + float(lvl) * 10.0)
		print("%-6d %-3d %6.0f..%-6.0f %-8.0f %.2f..%-6.2f   %-13.0f  %6.2f       x%.2f" % [
			lvl, leths.size(), leths.min(), leths.max(), mean,
			float(leths.min()) / mean, float(leths.max()) / mean,
			curve, factor, clampf(1.0 + (old_ratio - 1.0) * 0.3, 0.7, 1.4)])
	var fmin: float = factors.min()
	var fmax: float = factors.max()
	var fmean := 0.0
	for f in factors:
		fmean += float(f)
	fmean /= float(factors.size())
	print("")
	print("The spawn mix sits at %.2f..%.2f x the curve's own hp+2str (mean %.2f)." % [fmin, fmax, fmean])
	print("A monster's lethality within its level runs %.2f..%.2f x that level's mean."
		% [float(spreads.min()), float(spreads.max())])
	print("So `expected = _reference_at(level).hp + 2*str, x %.2f` centres the term on the real mix." % fmean)
	quit(0)
