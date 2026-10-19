extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")

func _init():
	print("\n=== Forcefield: old flat formula vs anchored, full spend ===")
	print("%-8s %8s %8s %10s %10s %12s %12s" % [
		"level", "maxHP", "INT", "old", "new", "old/bar", "new/bar"])
	# INT roughly 0.75/level + base for a Wizard; HP from the reference curve shape.
	var cases := [[10, 190, 21], [50, 662, 76], [250, 2260, 320], [1000, 7900, 1200]]
	for c in cases:
		var lvl: int = int(c[0]); var hp: int = int(c[1]); var i_stat: int = int(c[2])
		var old_v: float = 100.0 + float(i_stat) * 8.0
		var ratio: float = pow(maxf(0.05, float(i_stat) / float(lvl + 13)), 0.5)
		var new_v: float = float(hp) * CombatManager.FORCEFIELD_SHARE_OF_BAR * ratio
		print("%-8d %8d %8d %10.0f %10.0f %11.2fx %11.2fx" % [
			lvl, hp, i_stat, old_v, new_v, old_v / float(hp), new_v / float(hp)])
	print("\nold/bar above 1.00 = one cast absorbs more than the caster's entire health bar.")
	quit()
