extends SceneTree
const DropTables = preload("res://shared/drop_tables.gd")
const CharacterScript = preload("res://shared/character.gd")
func _init():
	var mults: Dictionary = CharacterScript.VARIANT_STAT_MULTIPLIERS
	var byr := {}
	for v in DropTables.EGG_VARIANTS:
		var r := int(v.get("rarity", 10))
		if not byr.has(r): byr[r] = []
		byr[r].append(v)
	var keys := byr.keys(); keys.sort()
	var out := "# Companion variant review list\n\n"
	out += "All %d variants, grouped by rarity (1 = rarest). `mult` is the STAT multiplier from\n" % DropTables.EGG_VARIANTS.size()
	out += "`VARIANT_STAT_MULTIPLIERS`; **1.00x means the variant is cosmetic only**.\n\n"
	out += "Owner is reviewing for two things: whether the RARITY matches how good the variant\n"
	out += "LOOKS, and whether the NAME conveys its rarity.\n\n"
	for r in keys:
		out += "\n## Rarity %d  (%d variants)\n\n" % [r, byr[r].size()]
		out += "| variant | mult | pattern | colour | colour2 |\n|---|---|---|---|---|\n"
		for v in byr[r]:
			var n := String(v.get("name", "?"))
			var m := float(mults.get(n, 1.0))
			out += "| %s | %s | %s | `%s` | `%s` |\n" % [n,
				("**x%.2f**" % m) if m > 1.0 else "x1.00 *(looks only)*",
				String(v.get("pattern", "solid")), String(v.get("color", "")), String(v.get("color2", ""))]
	var f := FileAccess.open("res://docs/design/companion_variants_review.md", FileAccess.WRITE)
	f.store_string(out); f.close()
	print("wrote docs/design/companion_variants_review.md (%d variants)" % DropTables.EGG_VARIANTS.size())
	quit()
