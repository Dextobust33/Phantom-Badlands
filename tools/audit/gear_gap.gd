extends SceneTree
# Does the sim's "average" gear model match the character a real playtest actually fights with?
# The fixture (balance_char.gd) rolls real drop-table gear best-of-40 nearest reference HP.
# The sim rolls a fitted model. If they diverge on ATTACK, every difficulty number the sim
# produces is wrong in the direction of "too hard", and live play will feel trivial.
const Character = preload("res://shared/character.gd")
const DropTables = preload("res://shared/drop_tables.gd")

func _init():
	var dt = DropTables.new()
	print("\n=== real drop-table gear at L50, 40 rolls, best-by-reference-HP ===")
	var best_atk := 0
	var atk_sum := 0.0
	var n := 0
	var lo := 999999
	var hi := 0
	for i in range(40):
		var it = dt.generate_equipment(50, "weapon")
		if it == null or it.is_empty():
			continue
		var atk := int(it.get("attack", it.get("attack_bonus", 0)))
		atk_sum += atk
		n += 1
		lo = mini(lo, atk)
		hi = maxi(hi, atk)
	if n > 0:
		print("  weapon attack: mean %.0f, range %d - %d over %d rolls" % [atk_sum / n, lo, hi, n])
		print("  spread hi/lo = %.2fx  <-- how much luck swings a character's damage" % (float(hi) / maxf(1.0, float(lo))))
	quit()
