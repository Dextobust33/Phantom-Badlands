# Does a companion variant's RARITY match its STAT multiplier?
# Owner: "the multipliers are supposed to affect stats, that's the whole point of having
# different rarities of companions you can find. That's part of the hunt."
extends SceneTree
const DropTables = preload("res://shared/drop_tables.gd")
const CharacterScript = preload("res://shared/character.gd")

func _init():
	var mults: Dictionary = CharacterScript.VARIANT_STAT_MULTIPLIERS
	var by_rarity := {}
	var total := 0
	var no_bonus := 0
	var rows := []
	for v in DropTables.EGG_VARIANTS:
		var name := String(v.get("name", "?"))
		var rar := int(v.get("rarity", 10))
		var m := float(mults.get(name, 1.0))
		total += 1
		if m <= 1.0:
			no_bonus += 1
		if not by_rarity.has(rar):
			by_rarity[rar] = {"n": 0, "bonus": 0, "mults": []}
		by_rarity[rar]["n"] += 1
		if m > 1.0:
			by_rarity[rar]["bonus"] += 1
		by_rarity[rar]["mults"].append(m)
		rows.append([rar, name, m, String(v.get("pattern", "solid"))])

	print("\n=== VARIANT RARITY vs STAT MULTIPLIER (%d variants) ===" % total)
	print("rarity 1 = rarest. A rare variant with 1.00x is a find that pays NOTHING.")
	print("%-8s %6s %9s %9s  %s" % ["rarity", "count", "w/ bonus", "max mult", "verdict"])
	var keys := by_rarity.keys()
	keys.sort()
	for r in keys:
		var d = by_rarity[r]
		var mx: float = 1.0
		for m in d["mults"]:
			mx = maxf(mx, float(m))
		var verdict := "ok"
		if d["bonus"] == 0:
			verdict = "*** NONE of these give any stat bonus ***"
		elif d["bonus"] < d["n"]:
			verdict = "only %d of %d pay" % [d["bonus"], d["n"]]
		print("%-8d %6d %9d %8.2fx  %s" % [r, d["n"], d["bonus"], mx, verdict])

	print("\n%d of %d variants (%.0f%%) give NO stat bonus at all." % [
		no_bonus, total, 100.0 * float(no_bonus) / float(total)])

	print("\n--- the RAREST variants and what they actually pay ---")
	rows.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	for i in range(mini(14, rows.size())):
		var r = rows[i]
		print("  rarity %-3d %-14s %5.2fx  %-10s %s" % [int(r[0]), String(r[1]), float(r[2]), String(r[3]),
			"" if float(r[2]) > 1.0 else "<-- pays nothing"])
	quit()
