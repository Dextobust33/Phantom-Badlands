extends SceneTree
## ⛑ WHAT DOES A PLAYER ACTUALLY FACE AT A BENCH? Measured before redesigning anything.
##
## Owner 2026-09-18: *"The UI for crafting will likely need redesigned as well once we are done. We
## want it to be organized in a way that makes it easy to understand what peoples options are."*
##
## ⛑ MEASURE THE PROBLEM BEFORE DRAWING A SOLUTION. "The crafting UI is bad" is not actionable and
## invites redesigning whatever the last person happened to notice. This counts what the bench puts
## in front of a player at a realistic skill level: how many recipes, how many pages, and — the
## number that decides the whole design — how many of them they can DO anything about right now.
##
## Run:
##   godot --headless --path . --script res://tools/probe/crafting_ui_shape.gd

const CD := preload("res://shared/crafting_database.gd")

## The client pages the recipe list at this size. Read from the client so the finding cannot
## silently go stale if the page size changes.
var _page_size: int = 5


func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var i: int = cli.find("const CRAFTING_PAGE_SIZE = ")
	if i >= 0:
		_page_size = int(cli.substr(i + 27, 3).strip_edges())

	print("")
	print("===== 1. HOW BIG IS THE LIST, PER SKILL =====")
	print("  page size: %d   (client CRAFTING_PAGE_SIZE)" % _page_size)
	print("")
	print("  %-16s %-8s %-8s %s" % ["skill", "recipes", "pages", "specialist-only"])
	var by_skill: Dictionary = {}
	for rid in CD.RECIPES:
		var r: Dictionary = CD.RECIPES[rid]
		var sk := String(CD.get_skill_name(r.get("skill", 0)))
		if not by_skill.has(sk):
			by_skill[sk] = []
		by_skill[sk].append(r)
	var keys: Array = by_skill.keys()
	keys.sort()
	var worst_pages := 0
	for k in keys:
		var rs: Array = by_skill[k]
		var gated := 0
		for r in rs:
			if bool(r.get("specialist_only", false)):
				gated += 1
		var pages: int = int(ceil(float(rs.size()) / float(_page_size)))
		worst_pages = maxi(worst_pages, pages)
		print("  %-16s %-8d %-8d %d" % [k, rs.size(), pages, gated])

	print("")
	print("===== 2. WHAT A PLAYER CAN ACT ON, BY SKILL LEVEL =====")
	# ⛑ THE NUMBER THAT MATTERS. A list is not long because it has many rows - it is long because
	# most rows are not answers. At a given skill, a recipe is either something you can make now,
	# something you could make if you gathered, or something you simply cannot reach yet.
	print("  Blacksmithing, the largest list (%d recipes):" % by_skill.get("blacksmithing", []).size())
	print("  %-8s %-12s %-14s %-14s %s" % ["skill", "at skill", "too high", "specialist", "pages of noise"])
	for lvl in [1, 10, 25, 50, 75, 100]:
		var at_skill := 0
		var too_high := 0
		var gated := 0
		for r in by_skill.get("blacksmithing", []):
			var req: int = int(r.get("skill_required", 1))
			if req > lvl:
				too_high += 1
			elif bool(r.get("specialist_only", false)):
				gated += 1
			else:
				at_skill += 1
		# Rows that cannot become an action on this visit, however much the player scrolls.
		var noise_pages: float = float(too_high) / float(_page_size)
		print("  %-8d %-12d %-14d %-14d %.1f" % [lvl, at_skill, too_high, gated, noise_pages])

	print("")
	print("===== 3. THE FINDINGS =====")
	var bs: int = by_skill.get("blacksmithing", []).size()
	print("  * The largest single list is %d recipes = %d PAGES at %d per page." % [
		bs, int(ceil(float(bs) / float(_page_size))), _page_size])
	print("  * There is no filter, no sort and no category on the recipe list - the only")
	print("    navigation is Prev/Next through every page.")
	print("  * A level-1 blacksmith pages past ~%d recipes they cannot touch to find the few" % (
		bs - 6))
	print("    they can.")
	print("")
	print("  ⛑ So the redesign is not about prettier rows. The list has no way to ASK a")
	print("     question - 'what can I make right now', 'what is someone paying for', 'what")
	print("     am I close to' - and that is what makes it feel like work.")
	print("")
	print("===== 4. WHAT THE FILTERS DO TO THAT =====")
	# ⛑ THE FIX IS MEASURED AGAINST THE DIAGNOSIS, not asserted. "At My Skill" is the filter a
	# levelling player lives in, so the number that matters is how many pages it removes.
	print("  Blacksmithing, pages to page through:")
	print("  %-8s %-14s %-16s %s" % ["skill", "All (before)", "At My Skill", "pages saved"])
	var bs_list: Array = by_skill.get("blacksmithing", [])
	for lvl in [1, 10, 25, 50, 75]:
		var at_skill := 0
		for r in bs_list:
			if int(r.get("skill_required", 1)) <= lvl:
				at_skill += 1
		var before: int = int(ceil(float(bs_list.size()) / float(_page_size)))
		var after: int = maxi(1, int(ceil(float(at_skill) / float(_page_size))))
		print("  %-8d %-14d %-16d %d" % [lvl, before, after, before - after])

	print("")
	print("===== 5. THE FILTERS ARE WIRED =====")
	var cli2 := FileAccess.get_file_as_string("res://client/client.gd")
	var fails: Array = []
	var wiring := {
		"the list keeps an unfiltered copy": cli2.find("var crafting_recipes_all: Array = []") >= 0,
		"a filter narrows it": cli2.find("func _apply_craft_filter") >= 0,
		"Can Make button": cli2.find("\"action_data\": \"craft_filter_ready\"") >= 0,
		"At Skill button": cli2.find("\"action_data\": \"craft_filter_skill\"") >= 0,
		"Wanted button": cli2.find("\"action_data\": \"craft_filter_wanted\"") >= 0,
		"All button": cli2.find("\"action_data\": \"craft_filter_all\"") >= 0,
		"pressing one is handled": cli2.find("crafting_filter = action.replace(\"craft_filter_\", \"\")") >= 0,
		"the client calls the SHARED predicate":
			cli2.find("recipe_matches_filter(r, crafting_filter)") >= 0,
		"the header names the active filter": cli2.find("▸ %s %d") >= 0,
		"an empty result explains itself": cli2.find("Nothing here under [b]%s[/b]") >= 0,
	}
	for k in wiring.keys():
		if bool(wiring[k]):
			print("  ok    %s" % k)
		else:
			fails.append(String(k))
			print("  FAIL  %s -- MISSING" % k)

	print("")
	print("")
	print("===== 6. THE FILTER ACTUALLY NARROWS, MEASURED BY RUNNING IT =====")
	# ⛑ SECTIONS 4 AND 5 BOTH PASSED WHILE THE FILTER WAS REVERTED TO RETURN EVERY RECIPE. One
	# projected the improvement from recipe DATA and the other only checked the buttons existed -
	# neither touched the rule. This runs the real predicate over a realistic payload.
	var sample: Array = []
	for r in by_skill.get("blacksmithing", []):
		var row: Dictionary = (r as Dictionary).duplicate(true)
		row["locked"] = int(r.get("skill_required", 1)) > 25
		row["can_craft"] = not bool(row["locked"]) and not bool(r.get("specialist_only", false))
		row["can_commission"] = bool(r.get("specialist_only", false)) and not bool(row["locked"])
		row["wanted_count"] = 0
		sample.append(row)
	print("  a skill-25 blacksmith, %d recipes in the payload:" % sample.size())
	var counts: Dictionary = {}
	for f in ["ready", "skill", "wanted", "all"]:
		var n := 0
		for row in sample:
			if CD.recipe_matches_filter(row, f):
				n += 1
		counts[f] = n
		print("    %-10s %3d rows  (%d page(s))" % [f, n, maxi(1, int(ceil(float(n) / float(_page_size))))])
	if int(counts["all"]) != sample.size():
		fails.append("the All filter drops rows")
		print("  FAIL  All should show everything")
	elif int(counts["skill"]) >= int(counts["all"]):
		fails.append("At My Skill narrows nothing")
		print("  FAIL  At My Skill shows as much as All - the filter is not filtering")
	elif int(counts["ready"]) > int(counts["skill"]):
		fails.append("Can Make is wider than At My Skill")
		print("  FAIL  Can Make cannot be wider than At My Skill")
	else:
		print("  ok    %d rows become %d - %d pages become %d" % [
			int(counts["all"]), int(counts["skill"]),
			int(ceil(float(counts["all"]) / float(_page_size))),
			maxi(1, int(ceil(float(counts["skill"]) / float(_page_size))))])

	print("")
	print("===== 7. THE DETAIL SCREEN SAYS WHAT YOU GET =====")
	# ⛑ IT EXPLAINED HOW TO CRAFT IN DEPTH AND NEVER WHAT THE THING WAS. Materials, where each one
	# drops, success odds, quality bands, the boost ladder - and no description and no stats. A
	# player could read every number on that page and still not know whether the item beat what
	# they were wearing. Owner's crafting fault #2.
	var srv3 := FileAccess.get_file_as_string("res://server/server.gd")
	var detail := {
		"the server sizes the output": srv3.find("\"output_stats\": (CraftingDatabaseScript.curve_sized_base_stats") >= 0,
		"sized by the SAME call the craft uses": srv3.count("curve_sized_base_stats(recipe, drop_tables)") >= 2,
		"the screen shows what it makes": cli2.find("[color=#87CEEB]Makes:[/color]") >= 0,
		"and what the item is for": cli2.find("var _desc := String(recipe.get(\"description\", \"\"))") >= 0,
		"compared against what you wear": cli2.find("vs your %s:") >= 0,
		"the comparison uses the shared aggregator": cli2.find("_compute_item_bonuses(_worn)") >= 0,
	}
	for k in detail.keys():
		if bool(detail[k]):
			print("  ok    %s" % k)
		else:
			fails.append(String(k))
			print("  FAIL  %s -- MISSING" % k)
	# ⛑ AND NO SECOND COPY OF THE DAMPING CURVE. The client carried its own
	# `_get_effective_item_level_for_display`, whose docstring SAID it mirrored the server's - the
	# same shape that produced a design figure wrong by 50 earlier the same day.
	if cli2.find("return 50.0 + 15.0 * log(excess) / log(2.0)") >= 0:
		fails.append("the client still has its own copy of the item-level damping curve")
		print("  FAIL  the client re-derives the damping curve instead of calling the shared one")
	else:
		print("  ok    one damping curve, shared")



	if not fails.is_empty():
		print("[PROBE] FAIL %d part(s) of the recipe filter are missing:" % fails.size())
		for f in fails:
			print("   - %s" % f)
		quit(1)
		return
	print("[PROBE] PASS the recipe list can be asked a question, and the four ways to ask it")
	print("       all have buttons.")
	quit()
