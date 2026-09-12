extends SceneTree
## Does the GAME read what rolecal wrote?
##
## The curve file changing proves nothing on its own - `role_multipliers` is only live if
## `_load_reference_curve()` parses it into `_calibrated_role_mults` and the monster builder then
## multiplies by it. Writing a file and assuming it is read is the same mistake as reading source
## and assuming it runs.
const MonsterDB = preload("res://shared/monster_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var db = MonsterDB.new()
	get_root().add_child(db)
	# Force the loader by asking for a monster, which is what the game does.
	var warm: Dictionary = db.generate_monster_by_name("Goblin", 1, true, "normal")
	ck(not warm.is_empty(), "the database builds a level 1 monster")

	print("\n--- the calibrated multipliers are LOADED, not just on disk ---")
	# NOT a magic threshold. The first version asserted `str_mult > 4.0`, a number copied out of
	# one calibration's output - and the very next calibration legitimately put boss L1 at 3.83,
	# so the probe failed on a correct curve. A check pinned to last run's numbers goes stale
	# every time the thing it checks is re-measured.
	#
	# The structural question is whether the CALIBRATED table is in force at all, rather than the
	# derived algebra `role_multipliers` falls back to. Those differ by construction: the fallback
	# is one pair per role for the whole game, the calibrated form is per level.
	for role in ["empowered", "elite", "boss"]:
		var m: Dictionary = MonsterDB.role_multipliers(role, 1)
		var m_late: Dictionary = MonsterDB.role_multipliers(role, 10000)
		print("    %-10s L1 hp x%.2f str x%.2f   L10000 str x%.2f" % [
			role, float(m.hp_mult), float(m.str_mult), float(m_late.str_mult)])
		ck(not is_equal_approx(float(m.str_mult), float(m_late.str_mult)),
			"%s is priced PER LEVEL (L1 %.2f vs L10000 %.2f), so the calibrated table is in force" % [
				role, float(m.str_mult), float(m_late.str_mult)])
	# ...and the mid game came DOWN, which is the other half of what rolecal changed.
	# Same reasoning: assert the SHAPE the calibration always produces - roles cost far less
	# per point of strength in the mid game than at level 1 - not a number from one run.
	var e1: Dictionary = MonsterDB.role_multipliers("elite", 1)
	var e1000: Dictionary = MonsterDB.role_multipliers("elite", 1000)
	ck(float(e1000.str_mult) < float(e1.str_mult),
		"elite's multiplier falls from L1 (%.2f) to L1000 (%.2f), which is the measured shape" % [
			float(e1.str_mult), float(e1000.str_mult)])

	print("\n--- and a real L1 elite is built stronger than a plain one ---")
	# The multiplier only matters if the builder applies it. Build both and compare.
	# Same species, same level, forced roles - so the ONLY difference is the role multiplier.
	var plain: Dictionary = db.generate_monster_by_name("Goblin", 1, true, "normal")
	var elite: Dictionary = db.generate_monster_by_name("Goblin", 1, true, "elite")
	ck(not plain.is_empty() and not elite.is_empty(), "both a plain and an elite L1 Goblin build")
	if not plain.is_empty() and not elite.is_empty():
		var ps := int(plain.get("strength", 0))
		var es := int(elite.get("strength", 0))
		var ph := int(plain.get("max_hp", plain.get("hp", 0)))
		var eh := int(elite.get("max_hp", elite.get("hp", 0)))
		print("    plain  str %d  hp %d" % [ps, ph])
		print("    elite  str %d  hp %d" % [es, eh])
		ck(es > ps, "the elite hits harder (%d vs %d) - the multiplier reaches the monster" % [es, ps])
		ck(eh > ph, "and has more health (%d vs %d)" % [eh, ph])

	print("\n[ROLECALLIVE] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
