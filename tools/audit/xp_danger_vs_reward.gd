extends SceneTree
## Does the XP a monster pays keep up with how much harder it is?
##
## Owner 2026-09-15: *"the +18% xp, is that enough? How much deadlier are those monsters you are
## getting the extra xp from? If the enemy is only 18% deadlier I guess that makes sense but if
## they are way harder 18% doesn't seem like much of a reward."*
##
## The +18% is the AVERAGE lift across all kills - the pace knob - not the reward for danger. What
## answers the question is the SLOPE: how much more a genuinely harder monster pays than a soft one
## of the same level, set against how much harder it actually is.
##
## "Harder" is measured as lethality (hp + 2*str + def), the same quantity the reward reads. That
## is a proxy for effort rather than for risk: HP is time, strength is damage taken. It understates
## danger if anything, because under permadeath the tail matters more than the mean.
const MonsterDB = preload("res://shared/monster_database.gd")
const SAMPLES := 500

func _init() -> void:
	var db = MonsterDB.new()
	get_root().add_child(db)
	print("How much deadlier, and how much better paid, per level.")
	print("(danger = this monster's lethality / an ordinary monster of its level)")
	print("")
	for lvl in [5, 50, 500, 5000]:
		var expected: float = db._expected_lethality(lvl)
		var bands := [[0.0, 0.7], [0.7, 0.9], [0.9, 1.1], [1.1, 1.4], [1.4, 1.8], [1.8, 99.0]]
		var sums := []
		var counts := []
		var bsum := []
		for i in range(bands.size()):
			sums.append(0.0)
			counts.append(0)
			bsum.append(0.0)
		for i in range(SAMPLES):
			var m: Dictionary = db.generate_monster(lvl, lvl)
			if m.is_empty():
				continue
			var leth: float = float(m.get("max_hp", 0)) + 2.0 * float(m.get("strength", 0)) + float(m.get("defense", 0))
			var r: float = leth / expected
			var b: float = clampf(MonsterDB.XP_DANGER_CENTRE + (r - 1.0) * MonsterDB.XP_DANGER_SLOPE,
				MonsterDB.XP_DANGER_MIN, MonsterDB.XP_DANGER_MAX)
			for k in range(bands.size()):
				if r >= float(bands[k][0]) and r < float(bands[k][1]):
					sums[k] += r
					bsum[k] += b
					counts[k] += 1
					break
		# The "ordinary" band is 0.9-1.1; everything is expressed against it.
		var base_r: float = (sums[2] / float(counts[2])) if counts[2] > 0 else 1.0
		var base_b: float = (bsum[2] / float(counts[2])) if counts[2] > 0 else 1.0
		print("  LEVEL %d   (an ordinary monster here has lethality %.0f)" % [lvl, expected])
		print("    danger band     share   how much deadlier   how much better paid   paid per unit of danger")
		for k in range(bands.size()):
			if counts[k] == 0:
				continue
			var mr: float = sums[k] / float(counts[k])
			var mb: float = bsum[k] / float(counts[k])
			print("    %4.1f-%4.1fx      %4.0f%%        %5.2fx              %5.2fx                  %.2f" % [
				float(bands[k][0]), minf(float(bands[k][1]), 9.9), 100.0 * float(counts[k]) / float(SAMPLES),
				mr / base_r, mb / base_b, (mb / base_b) / maxf(0.01, mr / base_r)])
		print("")
	print("Reading it: 'paid per unit of danger' is 1.00 when XP tracks difficulty exactly.")
	print("Below 1.00 means the harder monster is under-paid for the extra work it costs.")
	print("Current knobs: CENTRE %.2f  SLOPE %.2f  band %.2f..%.2f" % [
		MonsterDB.XP_DANGER_CENTRE, MonsterDB.XP_DANGER_SLOPE, MonsterDB.XP_DANGER_MIN, MonsterDB.XP_DANGER_MAX])
	quit(0)
