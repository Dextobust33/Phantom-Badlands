extends SceneTree
## ⛑ IS A RUNE WORTH ITS MATERIALS? 46 recipes, the second-largest block in the game, never checked.
##
## A rune ADDS a capped stat bonus to gear you already own, so "is it worth it" is a ratio: what
## the rune gives against what the item it sits on already carries. A Supreme rune giving +180 to
## an item that totals 300 is transformative; one giving +16 to the same item is noise wearing a
## grand name.
##
## ⛑ MEASURED AGAINST REAL DROPS, like `crafting_worth.gd`, and for the same reason: gear totals
## are GENERATED off a level curve while rune caps are hand-authored constants, so the two can only
## agree by coincidence. That is exactly the fault that measurement found in crafted gear - 1.38x
## at item level 90 and 0.17x at 150 - and there is no reason to assume runes escaped it.
##
## Run:
##   godot --headless --path . --script res://tools/probe/rune_worth.gd

const CD := preload("res://shared/crafting_database.gd")
const DT := preload("res://shared/drop_tables.gd")
const PR := preload("res://shared/power_rank.gd")

const SAMPLES := 60
const NOT_POWER := ["level", "value", "durability", "weight",
	"roll_quality", "prefix_name", "suffix_name", "created_at", "id"]

# Where each rune tier is expected to be used, from RUNE_TIER_RANGES (grade tiers 1-2, 3-6, 7-9).
# Turned into a representative ITEM LEVEL by asking PowerRank for a level in that grade band.
const TIER_PROBE_LEVEL := {"minor": 8, "greater": 45, "supreme": 140}


func _stat_total(stats: Dictionary) -> float:
	var t := 0.0
	for k in stats.keys():
		if String(k) in NOT_POWER:
			continue
		var v = stats[k]
		if v is int or v is float:
			t += float(v)
	return t


func _init() -> void:
	var dt = DT.new()
	get_root().add_child(dt)
	seed(4242)

	# Median drop total at each tier's representative level.
	var med_at: Dictionary = {}
	for tier in TIER_PROBE_LEVEL:
		var lvl: int = int(TIER_PROBE_LEVEL[tier])
		var gt: int = int(PR.grade_for_level(lvl).get("tier", 1))
		var totals: Array = []
		for i in range(SAMPLES):
			var it: Dictionary = dt.roll_dungeon_chest_equipment(gt, lvl)
			if it.is_empty():
				continue
			var af: Dictionary = it.get("affixes", {}) if it.get("affixes", null) is Dictionary else {}
			if af.is_empty():
				continue
			totals.append(_stat_total(af))
		totals.sort()
		med_at[tier] = float(totals[totals.size() / 2]) if not totals.is_empty() else 0.0
		print("  %-9s probe level %-4d  median drop total %.0f  (%d samples)" % [
			String(tier), lvl, float(med_at[tier]), totals.size()])

	print("")
	print("%-30s %-9s %6s %9s %8s" % ["rune", "tier", "cap", "drop med", "share"])
	var by_tier: Dictionary = {}
	for rid in CD.RECIPES:
		var r: Dictionary = CD.RECIPES[rid]
		if String(r.get("output_type", "")) != "rune":
			continue
		var tier := String(r.get("rune_tier", "?"))
		var cap := float(r.get("rune_cap", 0))
		var med: float = float(med_at.get(tier, 0.0))
		if med <= 0.0:
			continue
		var share: float = cap / med
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(share)
		print("%-30s %-9s %6.0f %9.0f %7.2fx" % [
			String(r.get("name", rid)).substr(0, 30), tier, cap, med, share])

	print("")
	print("===== WHAT A RUNE IS WORTH, BY TIER =====")
	var tiers: Array = by_tier.keys()
	tiers.sort()
	for t in tiers:
		var arr: Array = by_tier[t]
		arr.sort()
		print("  %-9s n=%-3d median %.2fx of a whole item   (worst %.2fx, best %.2fx)" % [
			String(t), arr.size(), float(arr[arr.size() / 2]), float(arr[0]), float(arr[arr.size() - 1])])

	print("")
	print("  Read: 0.10x means the rune adds a tenth of what the item it sits on already carries.")
	print("  A rune the player cannot feel is a recipe they will not make twice.")
	print("")
	print("[PROBE] measurement only - the shape is the finding.")
	quit()
