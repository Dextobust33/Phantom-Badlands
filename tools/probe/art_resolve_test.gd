# Every empowered/variant prefix against the aliased species, plus the exact name that failed.
extends SceneTree
const MonsterArt = preload("res://client/monster_art.gd")

func _init():
	var prefixes := ["", "Venomous ", "Frenzied ", "Gilded ", "Vampiric ", "Thorned ", "Swift ",
					 "Juggernaut ", "Warded ", "Broodcalling ", "Corrosive ", "Frenzied Venomous "]
	var species := ["Orc", "Wolf", "Young Dragon", "Gnoll", "Goblin", "Skeleton", "Hydra"]
	var fails := 0
	var checked := 0
	print("\n=== ART RESOLUTION: every prefix x aliased species ===")
	for sp in species:
		var row := "  %-14s " % sp
		for pre in prefixes:
			var name: String = pre + sp
			var key: String = MonsterArt.resolve_art_key(name)
			checked += 1
			if key == "":
				fails += 1
				row += "X"
			else:
				row += "."
		print(row)
	print("  (columns = %s)" % ", ".join(prefixes).replace("  ", "(none) "))
	print("\n%d checked, %d unresolved." % [checked, fails])
	print("\n--- the exact reported failure ---")
	var k: String = MonsterArt.resolve_art_key("Venomous Orc")
	print("  'Venomous Orc' -> '%s'  %s" % [k, "FIXED" if k != "" else "*** STILL BROKEN ***"])
	quit(1 if fails > 0 else 0)
