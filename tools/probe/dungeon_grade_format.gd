extends SceneTree
## ⛑ NO DUNGEON ANYWHERE MAY SHOW A NUMERIC TIER.
##
## Owner 2026-09-16: *"T# dungeons shouldn't exist anymore as all dungeons are now on the letter
## number format."* The letter ladder (H G F E D C B A S, ascending, with an ascending rank beside
## it) replaced the numeric tier on 2026-09-11 - and seven surfaces never got the message. A GM
## line read "(T3)", a compass bearing read "(T5)", and the Atlas printed a bare `2` because an
## int was interpolated straight through a `%s`.
##
## This is the "a rename touches SEVEN surfaces" rule with a detector attached, so the next one
## cannot go a week unnoticed. Two halves, because they fail differently:
##
##   1. THE FORMATTER produces a letter, coloured, with the ladder hover attached - checked by
##      calling it, for every tier, which is the only thing that proves a lookup table.
##   2. THE CALL SITES carry no `T%d` any more. That half is a SOURCE scan and is honest about
##      being one: it cannot see whether a line is reachable, only whether the token is gone.
##      Both halves are needed - a perfect formatter nobody calls is exactly the bug being fixed.
##
## Run:
##   godot --headless --path . --script res://tools/probe/dungeon_grade_format.gd

const PowerRankScript := preload("res://shared/power_rank.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== 1. THE GRADE FORMATTER, CALLED ON EVERY TIER =====")
	for t in range(1, PowerRankScript.LADDER.size() + 1):
		var out: String = PowerRankScript.rich_grade(t)
		var letter: String = PowerRankScript.LADDER[t - 1]
		ck(out.contains("]%s[/color]" % letter), "tier %d renders as the letter %s" % [t, letter])
		ck(out.contains("[color=%s]" % PowerRankScript.color(t)), "tier %d carries its danger colour" % t)
		# The file's own standing rule: "Never render a bare label." A letter ladder is not
		# self-evident and the owner's one condition on the whole change was that a player can
		# tell what beats what.
		ck(out.begins_with("[url=") and out.contains("weakest"),
			"tier %d carries the ladder hover" % t)
		# A `]` inside a `[url=...]` value truncates the tag and dumps the hover into the visible
		# line. That has happened once already, on the companion inspect header.
		var url_val: String = out.substr(5, out.find("]") - 5)
		ck(not url_val.contains("["), "tier %d hover has no bracket to break the tag" % t)

	print("\n===== 2. AND IT IS NEVER A NUMBER =====")
	for t in range(1, PowerRankScript.LADDER.size() + 1):
		var vis: String = PowerRankScript.rich_grade(t)
		# Strip the hover value and the tags; what a player SEES must hold no digit.
		var shown: String = vis.substr(vis.rfind("[color="))
		shown = shown.substr(shown.find("]") + 1)
		shown = shown.substr(0, shown.find("["))
		ck(not _has_digit(shown), "tier %d shows '%s' - no digit" % [t, shown])

	print("\n===== 3. NO PLAYER-FACING LINE STILL SAYS T# UNLESS IT IS NOT A DUNGEON =====")
	# ⛑ THE FIRST VERSION OF THIS CHECK WAS A SILENT NO-OP, caught by re-injecting the exact
	# `(T%d)` fault it exists to find. It only flagged a line carrying `T%d` AND the word
	# "dungeon" - and on the GM line the dungeon NAME is on the next source line, so the token
	# sat there and the probe said PASS. Proximity was the wrong unit.
	#
	# So the token is BANNED and the legitimate non-dungeon uses are NAMED. Ore veins, groves,
	# trading posts, the region readout, companions, items and tools all still carry a numeric
	# tier and are none of this rule's business. Anything NEW fails until someone decides which
	# it is - which is the right default for a ban: unsafe unless listed.
	# Each entry names ONE thing that is legitimately still numeric, with the substring that
	# identifies its line. Triaged by reading every hit the ban produced on 2026-09-16 - all
	# gathering nodes, tools, trading posts, the region readout, monster tier and one admin
	# diagnostic. None of them is a dungeon, and none of them is on the letter ladder.
	var allowed: Array[String] = [
		# gathering nodes and the act of gathering them
		"ore vein", "grove", "mining the ore vein", "chopping the tree", "Gathering costs",
		"Mine T%d", "Chop T%d", "Forage T%d",
		# trading posts and the settler bubble around them
		"POST_TIER_NAMES", "wild T%d", "var tier_part", "Under Threat",
		"wilderness T%d showing", "suppressed to T%d by guards",
		"Wilderness tier", "Floor tier (post.tier)", "Effective tier",
		# the region readout on the HUD
		"hud_region_tier", "hud_region_outside_tier",
		# a TOOL's tier (pickaxe, axe, rod), shown beside its durability
		"tier_str = \" T%d\"",
		# a MONSTER's tier - a separate scale from the dungeon ladder, see show_help
		"monster[/color]",
		# admin grants, which echo the raw field they were given
		"GM] Received", "GM] Gave",
	]
	for path in ["res://client/client.gd", "res://server/server.gd",
			"res://client/post_status_panel.gd", "res://client/combat_loot_panel.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		var n := 0
		var hits: Array[String] = []
		while not f.eof_reached():
			n += 1
			var line := f.get_line()
			# `log_message` goes to the server console, never to a player.
			if line.contains("log_message"):
				continue
			if not (line.contains("T%d") or line.contains("Tier %d")):
				continue
			var ok := false
			for a in allowed:
				if line.contains(a):
					ok = true
					break
			if not ok:
				hits.append("%s:%d  %s" % [path.get_file(), n, line.strip_edges()])
		f.close()
		ck(hits.is_empty(), "%s has no unaccounted numeric tier" % path.get_file())
		for h in hits:
			print("           " + h)

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(0)


func _has_digit(s: String) -> bool:
	for c in s:
		if c >= "0" and c <= "9":
			return true
	return false
