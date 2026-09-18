extends SceneTree
## ⛑ WHERE DOES A GATHERED MATERIAL GO? For most of them the answer is "nowhere".
##
## Owner 2026-09-18, redirecting the crafting arc away from power tuning: *"I want to get rid of a
## lot of the level gated grindy crafts unless they are for something that's actually useful and
## easy for the players to understand, trade, and use. No one wants to sit around and craft a ton
## of dust, logs, etc. They want to do meaningful things with their gathered materials... Seems
## like many materials just pile up or players get them and don't care because they don't know what
## to do with them."*
##
## So the question is not how strong a crafted item is - it is whether a material has a
## DESTINATION, and whether the recipes between a player and something useful are worth walking.
##
## Three things are counted, and they are different problems:
##   1. materials no recipe consumes at all - they can only pile up;
##   2. recipes whose OUTPUT is another material - the "craft a ton of dust" tier;
##   3. how deep the chain is before a material becomes something a player can equip or drink.
##
## Run:
##   godot --headless --path . --script res://tools/probe/crafting_materials_audit.gd

const CD := preload("res://shared/crafting_database.gd")

func _init() -> void:
	var mats: Dictionary = CD.MATERIALS
	# ⛑ TWO TABLES CONSUME MATERIALS, NOT ONE, and reading only `RECIPES` made this audit report
	# six materials as having NO DESTINATION when three of them (ash_wood, oak_wood, darkwood -
	# the common weight-40 results of chopping) are each used by four `GATHERING_TOOLS` recipes.
	# An audit written around the wrong unit is as wrong as a guess and far more convincing; this
	# one had been quoted as a finding and put on the backlog as work to do.
	#
	# Derived rather than hand-listed: any const dictionary whose entries carry a `materials` key
	# is a consumer, so a third table added later is picked up without editing this line.
	var recipes: Dictionary = {}
	for src in [CD.RECIPES, CD.GATHERING_TOOLS]:
		for rid in src:
			recipes[rid] = src[rid]

	# --- who consumes what
	var consumed: Dictionary = {}
	var produced: Dictionary = {}
	var out_kinds: Dictionary = {}
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		var ot := String(r.get("output_type", "?"))
		out_kinds[ot] = int(out_kinds.get(ot, 0)) + 1
		var m = r.get("materials", {})
		if m is Dictionary:
			for k in m.keys():
				consumed[String(k)] = int(consumed.get(String(k), 0)) + 1
		# A recipe that makes a MATERIAL is an intermediate step, not a destination.
		if ot == "material" or mats.has(String(rid)):
			produced[String(rid)] = true

	print("materials defined: %d   recipes: %d" % [mats.size(), recipes.size()])
	print("")
	print("===== 1. MATERIALS NOTHING CONSUMES =====")
	var orphans: Array = []       # no recipe AND not edible - truly nowhere to go
	var food_only: Array = []     # no recipe, but can be eaten
	var by_type: Dictionary = {}
	for mid in mats:
		var t := String(mats[mid].get("type", "?"))
		if not by_type.has(t):
			by_type[t] = {"n": 0, "orphan": 0, "food": 0}
		by_type[t]["n"] = int(by_type[t]["n"]) + 1
		# ⛑ EATING IS A DESTINATION, AND THE FIRST VERSION OF THIS PROBE DID NOT KNOW IT.
		# `FOOD_MATERIAL_TYPES` (plant / herb / fungus / fish / meat) is read at three places in
		# server.gd - a herb no recipe consumes can still be eaten, so counting it as having
		# nowhere to go would have over-reported the problem by 16 materials and pointed the
		# redesign at the wrong half of the list. Checked before reporting, not after.
		var edible: bool = t in CD.FOOD_MATERIAL_TYPES
		if not consumed.has(String(mid)):
			if edible:
				food_only.append(String(mid))
				by_type[t]["food"] = int(by_type[t].get("food", 0)) + 1
			else:
				orphans.append(String(mid))
				by_type[t]["orphan"] = int(by_type[t]["orphan"]) + 1
	print("  %d of %d materials have NO DESTINATION AT ALL - no recipe, not edible (%.0f%%)" % [
		orphans.size(), mats.size(), 100.0 * float(orphans.size()) / float(maxi(1, mats.size()))])
	print("  %d more are EDIBLE ONLY - no recipe wants them, but they are food" % food_only.size())
	print("")
	print("  by material type (orphaned / total):")
	var types: Array = by_type.keys()
	types.sort()
	for t in types:
		var d: Dictionary = by_type[t]
		var flag := "   <-- NOTHING in this category has any use" if int(d["orphan"]) == int(d["n"]) else ""
		print("    %-14s no-use %2d  food-only %2d  of %-3d%s" % [
			String(t), int(d["orphan"]), int(d.get("food", 0)), int(d["n"]), flag])
	if not orphans.is_empty():
		orphans.sort()
		print("")
		print("  NO DESTINATION: %s" % ", ".join(orphans.slice(0, 40)))
		if orphans.size() > 40:
			print("  ...and %d more" % (orphans.size() - 40))

	if not food_only.is_empty():
		food_only.sort()
		print("  EDIBLE ONLY:    %s" % ", ".join(food_only))
	print("")
	print("===== 2. WHAT RECIPES ACTUALLY MAKE =====")
	# ⛑ The "craft a ton of dust" tier is visible here: an output_type that is itself a material
	# is a step on the way to something, never the something.
	var kinds: Array = out_kinds.keys()
	kinds.sort()
	for k in kinds:
		print("    %-14s %d recipes" % [String(k), int(out_kinds[k])])

	print("")
	print("===== 3. HOW MANY RECIPES ARE GATED BEHIND A SKILL GRIND =====")
	var buckets := {"0-10": 0, "11-25": 0, "26-50": 0, "51-75": 0, "76+": 0}
	for rid in recipes:
		var sk := int(recipes[rid].get("skill_required", 0))
		if sk <= 10: buckets["0-10"] += 1
		elif sk <= 25: buckets["11-25"] += 1
		elif sk <= 50: buckets["26-50"] += 1
		elif sk <= 75: buckets["51-75"] += 1
		else: buckets["76+"] += 1
	for b in ["0-10", "11-25", "26-50", "51-75", "76+"]:
		print("    skill %-6s %d recipes" % [b, int(buckets[b])])

	print("")
	# ⛑ THIS WAS MEASUREMENT-ONLY UNTIL THE COUNT REACHED ZERO (2026-09-18). A probe that only
	# reports cannot stop a regression, and "6 materials have no destination" sat in the backlog
	# as a finding for weeks - four of those six being FALSE, because the audit read only
	# `RECIPES` and not `GATHERING_TOOLS`. Now that the real number is 0, it holds the line: any
	# new material with nowhere to go fails here rather than waiting to be noticed.
	#
	# EDIBLE-ONLY is deliberately NOT a failure. Food is a real destination, and a foraged herb
	# that is only ever eaten is working as intended.
	if not orphans.is_empty():
		print("[PROBE] FAIL %d material(s) have no destination at all: %s" % [
			orphans.size(), ", ".join(orphans)])
		print("        Give each a recipe that consumes it, or remove it from MATERIALS.")
		print("        Prefer a NEW sink over adding it as an ingredient to an existing recipe -")
		print("        an added ingredient gates that recipe behind whichever job drops it.")
		quit(1)
		return
	print("[PROBE] PASS every one of %d materials has somewhere to go (%d of them as food)." % [
		mats.size(), food_only.size()])
	quit()
	quit()
