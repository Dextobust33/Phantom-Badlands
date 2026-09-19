extends SceneTree
## What the simulator's "average" kit actually carries, in the same terms the live log records.
const SimScript := preload("res://tools/combat_simulator/real_combat_sim.gd")
const SLOTS := ["weapon", "armor", "shield", "helm", "boots", "ring", "amulet"]

func _init() -> void:
	var sim = SimScript.new()
	for lvl in [1, 3, 5, 10]:
		var agg := {}
		var rar := {}
		var ilvl := 0.0
		var items := 0
		var kits := 30
		var hp_tot := 0.0
		for i in range(kits):
			var klass := String(sim.ALL_CLASSES[i % sim.ALL_CLASSES.size()][0])
			var ch = sim.make_char(lvl, "average", klass, "Human")
			hp_tot += float(ch.get_total_max_hp())
			for s in SLOTS:
				var it = ch.equipped.get(s, null)
				if it == null:
					continue
				items += 1
				var r := String(it.get("rarity", "?"))
				rar[r] = int(rar.get(r, 0)) + 1
				ilvl += float(it.get("level", 0))
				for k in (it.get("affixes", {}) as Dictionary).keys():
					var v = (it.get("affixes", {}) as Dictionary)[k]
					if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
						agg[k] = float(agg.get(k, 0.0)) + float(v)
		print("")
		print("SIM 'average' KITS, L%d  (n=%d characters, %d items)" % [lvl, kits, items])
		print("  rarity mix: %s   mean item level %.1f   mean maxHP %.0f"
			% [str(rar), ilvl / maxf(1.0, float(items)), hp_tot / kits])
		var keys: Array = agg.keys()
		keys.sort_custom(func(a, b): return float(agg[a]) > float(agg[b]))
		for k in keys.slice(0, 9):
			print("    %-18s mean per kit %7.1f" % [k, float(agg[k]) / float(kits)])
	print("")
	quit()
