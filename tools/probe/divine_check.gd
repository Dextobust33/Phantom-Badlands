extends SceneTree
const DropTables = preload("res://shared/drop_tables.gd")
func _init():
	print("\n=== do the rarest variants now pay the most? ===")
	var worst := 99.0
	var best := 0.0
	for v in DropTables.EGG_VARIANTS:
		var m: float = DropTables.companion_variant_mult(v)
		if int(v.get("rarity",10)) == 1:
			worst = minf(worst, m); best = maxf(best, m)
	print("  rarity-1 band: every variant pays between %.2fx and %.2fx" % [worst, best])
	for n in ["Divine", "Prismatic", "Blessed", "Crimson"]:
		for v in DropTables.EGG_VARIANTS:
			if String(v.get("name","")) == n:
				print("  %-12s rarity %-3d -> %.2fx" % [n, int(v.get("rarity",10)), DropTables.companion_variant_mult(v)])
				break
	quit()
