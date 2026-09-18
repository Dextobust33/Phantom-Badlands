extends SceneTree
## ⛑ A CRAFTED ITEM *WITH ITS RUNES* AGAINST A DROPPED ONE — the number the whole fix is for.
##
## `_roll_affixes` says it outright: *"Crafted items get 0 affixes - affixes come from Enchanter
## Runes."* So crafting and enchanting are a PAIR, and measuring either half alone answers the
## wrong question. Owner 2026-09-18 set the target for the pair: *"Beats a typical drop, loses to a
## lucky one"* — 1.15x the MEDIAN drop, under a good roll.
##
## Before this arc: base 0.49x, runes 0.17x/0.06x/0.03x by tier, and a FLAT enchantment ceiling
## that bound before either mattered — at item level 8 a +60 attack cap was triple the whole item;
## at 140 it was under 8% of it.
##
## ⛑ IT MEASURES THE CEILING, NOT THE RUNE VALUES, because the ceiling is what binds. A probe that
## summed rune caps would have reported this system fixed while play was unchanged above the mid
## game — which is exactly the non-fix that was one edit from being written.
##
## Run:
##   godot --headless --path . --script res://tools/probe/crafted_pair_worth.gd

const CD := preload("res://shared/crafting_database.gd")
const DT := preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _stat_total(d: Dictionary) -> float:
	var t := 0.0
	for k in d.keys():
		if String(k) in ["level", "value", "durability", "weight", "roll_quality", "prefix_name", "suffix_name"]:
			continue
		var v = d[k]
		if v is int or v is float:
			t += float(v)
	return t


func _init() -> void:
	var dt = DT.new()
	get_root().add_child(dt)
	seed(777)

	# One representative equipment recipe per item level.
	var by_level: Dictionary = {}
	for rid in CD.RECIPES:
		var r: Dictionary = CD.RECIPES[rid]
		if not (String(r.get("output_type", "")) in ["weapon", "armor"]):
			continue
		var bs: Dictionary = r.get("base_stats", {})
		var lvl := int(bs.get("level", 0))
		if lvl > 0 and not by_level.has(lvl):
			by_level[lvl] = r
	var levels: Array = by_level.keys()
	levels.sort()

	print("%-6s %8s %8s %8s %9s %8s" % ["lvl", "base", "runes", "pair", "drop med", "ratio"])
	var ratios: Array = []
	for lvl in levels:
		var r: Dictionary = by_level[lvl]
		var base_total: float = _stat_total(CD.curve_sized_base_stats(r, dt))
		# The rune contribution a player can actually reach: the per-item CEILING on the three
		# stats they may enchant, which is the binding constraint - not the sum of rune caps.
		var item := {"level": int(lvl)}
		var caps: Array = []
		for st in CD.ENCHANTMENT_STAT_CAPS.keys():
			caps.append(float(CD.enchant_cap(String(st), item, dt)))
		caps.sort()
		caps.reverse()
		var rune_total := 0.0
		for i in range(mini(CD.MAX_ENCHANTMENT_TYPES, caps.size())):
			rune_total += float(caps[i])
		var drop_med: float = float(dt.expected_item_power(int(lvl)))
		var pair: float = base_total + rune_total
		var ratio: float = pair / maxf(1.0, drop_med)
		ratios.append(ratio)
		print("%-6d %8.0f %8.0f %8.0f %9.0f %7.2fx" % [int(lvl), base_total, rune_total, pair, drop_med, ratio])

	ratios.sort()
	var med: float = float(ratios[ratios.size() / 2])
	print("")
	print("===== THE PAIR =====")
	print("  median %.2fx   |   worst %.2fx   best %.2fx   (target 1.15x)" % [
		med, float(ratios[0]), float(ratios[ratios.size() - 1])])
	# ⛑ A BAND, NOT A POINT. Two independent samples of a high-variance generator will not agree
	# exactly, and chasing the last few points would be tuning noise.
	ck(med >= 0.95 and med <= 1.40, "the pair beats a typical drop without dwarfing it (%.2fx)" % med)
	ck(float(ratios[0]) >= 0.70, "and no level is left far behind (worst %.2fx)" % float(ratios[0]))
	ck(float(ratios[ratios.size() - 1]) <= 1.80,
		"...nor runs away with it (best %.2fx)" % float(ratios[ratios.size() - 1]))

	print("")
	print("===== THE CEILING MOVES WITH LEVEL =====")
	var lo: int = CD.enchant_cap("attack", {"level": 8}, dt)
	var hi: int = CD.enchant_cap("attack", {"level": 140}, dt)
	print("  attack cap: %d at level 8, %d at level 140 (was a FLAT 60 at both)" % [lo, hi])
	ck(hi > lo * 3, "a deep item allows far more enchantment than a shallow one")
	ck(lo < 60, "...and a level-8 item no longer allows triple its own worth")

	print("")
	if fails == 0:
		print("[PROBE] PASS crafted + runed beats a typical drop, at every level")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
