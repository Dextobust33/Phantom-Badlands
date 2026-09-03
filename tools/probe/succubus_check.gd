extends SceneTree
const Character = preload("res://shared/character.gd")
const DropTables = preload("res://shared/drop_tables.gd")

func _init():
	var dt = DropTables.new()
	print("\n=== Is 334 right for a L50 Succubus on a ~663 HP owner? ===")
	for nm in ["Succubus", "Gryphon", "Chimaera", "Giant", "Iron Golem"]:
		var data: Dictionary = dt.COMPANION_DATA.get(nm, {})
		var b: Dictionary = (data.get("bonuses", {}) as Dictionary)
		var comp := {"name": nm, "level": 50, "sub_tier": 1, "bonuses": b}
		var hp := Character.calculate_companion_max_hp(comp, 663, 50)
		var share: float = Character.companion_hp_share(b)
		var a: float = float(int(b.get("aggro", 25))) / 100.0
		var life: float = share * (1.0 - a) / maxf(0.01, a)
		print("  %-12s aggro %2d%%  share %.2f  ->  HP %5d   (lasts %.2fx as long as you)" % [
			nm, int(b.get("aggro", 25)), share, hp, life])
	print("\nOld flat model gave EVERY companion share 0.50. Only companions above ~29%% aggro")
	print("changed; the floor means none got weaker.")
	quit()
