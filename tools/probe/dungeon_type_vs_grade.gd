extends SceneTree
## How likely is an H1 dungeon to be full of the game's deadliest SPECIES?
##
## Owner 2026-09-13: *"We also need to take a look at our dungeon types. How common is an H1
## dungeon for our highest tier of loot monsters vs an H1 dungeon for a goblin?"*
##
## The two decisions are currently INDEPENDENT. `pick_weighted_type()` chooses a type by
## `spawn_weight` and never looks at the grade; the grade is then read off the land where it
## lands. So P(type | grade) = P(type), and an H1 dungeon is exactly as likely to be a
## Death-Incarnate lair as a Goblin Caves.
##
## This measures that rather than asserting it, and prints the answer in the owner's own terms.
const DD = preload("res://shared/dungeon_database.gd")
const PR = preload("res://shared/power_rank.gd")

const SAMPLE := 40000


func _init() -> void:
	# What the picker actually returns, over a big sample of real calls.
	var counts := {}
	for i in range(SAMPLE):
		var t := DD.pick_weighted_type()
		counts[t] = int(counts.get(t, 0)) + 1

	# Group by the type's DESIGN tier - what species it is made of.
	var by_tier := {}
	var names_by_tier := {}
	for dt in DD.DUNGEON_TYPES:
		var d: Dictionary = DD.DUNGEON_TYPES[dt]
		var tier := int(d.get("tier", 1))
		var c := int(counts.get(dt, 0))
		by_tier[tier] = float(by_tier.get(tier, 0.0)) + float(c)
		if not names_by_tier.has(tier):
			names_by_tier[tier] = []
		if names_by_tier[tier].size() < 3:
			names_by_tier[tier].append(String(d.get("name", dt)))

	print("\n===== WHAT SPECIES A DUNGEON IS MADE OF, REGARDLESS OF ITS GRADE =====")
	print("`pick_weighted_type` reads spawn_weight only - it never sees the grade, so these")
	print("shares are the SAME at H1 as at S9.")
	print("%-8s %9s   %s" % ["species", "share", "e.g."])
	for tier in range(1, 10):
		if not by_tier.has(tier):
			continue
		print("%-8s %8.1f%%   %s" % [
			PR.letter(tier), 100.0 * float(by_tier[tier]) / float(SAMPLE),
			", ".join(names_by_tier.get(tier, []))])

	print("\n--- the owner's question, directly ---")
	var goblin_share := 0.0
	var top_share := 0.0
	for dt in DD.DUNGEON_TYPES:
		var d: Dictionary = DD.DUNGEON_TYPES[dt]
		var share := 100.0 * float(int(counts.get(dt, 0))) / float(SAMPLE)
		if String(dt).find("goblin") >= 0:
			goblin_share += share
		if int(d.get("tier", 1)) >= 8:
			top_share += share
	print("  a dungeon of GOBLIN type          : %.2f%% of all dungeons" % goblin_share)
	print("  a dungeon of TIER A/S species     : %.2f%% of all dungeons" % top_share)
	if goblin_share > 0.0:
		print("  so at ANY grade, including H1, a top-species dungeon is %.2fx as common as a goblin one"
			% (top_share / goblin_share))

	print("\n--- and what an H1 of a top-species type actually contains ---")
	# The grade sets the LEVEL band; the type sets the SPECIES. So an H1 Balrog lair is a
	# level 1-2 Balrog - the name and the danger have come apart.
	var band: Dictionary = DD.get_sub_tier_level_range(1, 1)
	print("  H1 level band: L%d-%d" % [int(band.get("min_level", 0)), int(band.get("max_level", 0))])
	for dt in DD.DUNGEON_TYPES:
		var d: Dictionary = DD.DUNGEON_TYPES[dt]
		if int(d.get("tier", 1)) >= 8:
			print("  e.g. an H1 \"%s\" would spawn its own species at L%d-%d" % [
				String(d.get("name", dt)), int(band.get("min_level", 0)), int(band.get("max_level", 0))])

			break
	print("\nThe SPECIES is what a player reads off the map. A level-2 Balrog is mechanically")
	print("harmless and still tells a new player the starter post is surrounded by Balrogs.")
	print("")
	print("===== AND WITH THE GRADE-AWARE PICKER =====")
	print("`pick_weighted_type_for_grade` keeps full rarity at or BELOW the grade and suppresses")
	print("species above it, so a low species in high country stays possible by design.")
	print("%-6s %10s %10s %10s" % ["grade", "H species", "D species", "A/S species"])
	for g in [1, 3, 5, 7, 9]:
		var c2 := {}
		for i2 in range(12000):
			var t2 := DD.pick_weighted_type_for_grade(g)
			c2[t2] = int(c2.get(t2, 0)) + 1
		var h := 0.0
		var d8 := 0.0
		var top := 0.0
		for dt in DD.DUNGEON_TYPES:
			var tt := int(DD.DUNGEON_TYPES[dt].get("tier", 1))
			var sh := 100.0 * float(int(c2.get(dt, 0))) / 12000.0
			if tt == 1:
				h += sh
			if tt == 5:
				d8 += sh
			if tt >= 8:
				top += sh
		print("%-6s %9.1f%% %9.1f%% %9.2f%%" % [PR.letter(g), h, d8, top])
	print("")
	print("Read the H1 row: top-tier species should be ~0, and goblins should dominate.")
	print("Read the S9 row: everything is available, which is the A5-Goblin-Dungeon case.")
	quit(0)
