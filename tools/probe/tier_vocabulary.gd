extends SceneTree
## "Tier" must mean exactly ONE thing in player-facing text.
##
## There are five separate tier ladders in this game and they all used the same word and the same
## bare numbers, so "Tier 5+" could mean five different things depending on the sentence:
##
##   monster / dungeon / companion   9   H G F E D C B A S  (+ rank 1-9)
##   trading post                    7   Core Inner Mid Mid-Outer Outer Extreme World's Edge
##   consumable / material           9   Minor Lesser Standard Greater Superior Master Divine
##                                       Mythic Primordial
##   gathering node                  9   (no names)
##   equipment                       9   (no names)
##
## THREE OF THE FIVE ALREADY HAD NAMES. Nothing needed inventing - the text had simply stopped
## using vocabulary that ships in POST_TIER_NAMES, CONSUMABLE_TIERS and TOOL_SUBTYPES. The rule
## is: the ladder with letters keeps the word "tier"; the named ladders use their names; the two
## nameless ones keep numbers but must NAME THE LADDER ("gear tier 5+", "node tier 1-2"), because
## the ambiguity was always the bare noun, never the digit.
const PR := preload("res://shared/power_rank.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- the named ladders still exist, and are what the text now uses ---")
	var tp := FileAccess.get_file_as_string("res://shared/trading_post_database.gd")
	ck(tp.contains("\"Outer\"") and tp.contains("World's Edge"),
		"POST_TIER_NAMES ships Core..World's Edge - the map already shows these")
	var dt := FileAccess.get_file_as_string("res://shared/drop_tables.gd")
	ck(dt.contains("\"name\": \"Master\"") and dt.contains("\"name\": \"Primordial\""),
		"CONSUMABLE_TIERS ships Minor..Primordial - items are already named with them")

	print("\n--- no bare 'Tier <n>' survives in live player-facing text ---")
	# Patch notes are EXCLUDED on purpose: display_changelog is a historical record of what
	# shipped in a given version. Rewriting it would falsify the record, not fix a label.
	var files := ["res://client/client.gd", "res://client/help_panel.gd",
		"res://client/fusion_panel.gd", "res://client/companion_stable_panel.gd",
		"res://client/sanctuary_stable_panel.gd", "res://server/server.gd",
		"res://shared/titles.gd"]
	var re := RegEx.new()
	re.compile("(Tier [0-9]|\bT[0-9])")
	var bad: Array[String] = []
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		var lines := src.split("\n")
		var in_changelog := false
		for i in range(lines.size()):
			var ln := lines[i]
			if ln.begins_with("func display_changelog"):
				in_changelog = true
			elif ln.begins_with("func ") and in_changelog:
				in_changelog = false
			if in_changelog:
				continue
			var t := ln.strip_edges()
			if t.begins_with("#") or not ln.contains("\""):
				continue
			# only lines that actually reach a player
			# The `+ "..."` case is not optional: most help and panel copy is written as concatenated
			# continuation lines, and leaving it out made this probe blind to nearly all of it.
			# Found by RE-INJECTION - restoring a bare "Tier 5+ trading posts" did not fail the probe,
			# which is the whole reason to re-inject rather than trust a green run.
			var reaches_player: bool = t.begins_with("+ \"") or t.begins_with("\"")
			for marker in ["display_game", ".text =", "\"message\"", "dialog_text",
				"\"content\"", "\"description\""]:
				if ln.contains(marker):
					reaches_player = true
			if not reaches_player:
				continue
			if re.search(ln) != null:
				# the two nameless ladders are allowed a number IF they name the ladder
				var low := ln.to_lower()
				if low.contains("gear tier") or low.contains("node tier") or low.contains("chain tier") \
						or low.contains("patreon_tier"):
					continue
				bad.append("%s:%d" % [f.get_file(), i + 1])
	ck(bad.is_empty(), "no live surface says a bare 'Tier <n>' - found %d%s" % [
		bad.size(), (" (" + ", ".join(bad) + ")") if not bad.is_empty() else ""])

	print("\n--- the ladder page does not claim one level band for two ladders ---")
	# Monster tiers and dungeon tiers DIVERGE below tier 6: monster tier 1 is L1-5, dungeon
	# tier 1 is L1-12. Companions and eggs carry the MONSTER tier, dungeons the dungeon tier.
	# The first help page printed dungeon bands beside every letter, which contradicted the
	# Bestiary on the one page a confused player opens.
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var g0 := cli.find("func _tier_rank_help()")
	var body := cli.substr(g0, cli.find("\nfunc ", g0 + 10) - g0) if g0 >= 0 else ""
	ck(g0 >= 0, "found the ladder generator")
	# The CALL, not the word - the word still appears in the comment that explains why the
	# band was removed, and a check that cannot tell those apart is not a check.
	ck(not body.contains("TIER_LEVEL_RANGES.get("),
		"it no longer READS a level band - the letters are the ordering, which IS shared")
	ck(body.contains("depend on what carries it"),
		"...and it says so, rather than leaving the player to notice the contradiction")

	print("\n--- the Bestiary keeps MONSTER bands, and now carries letters ---")
	ck(cli.contains("Tier H[/color] [color=#808080](Levels 1-5)"),
		"tier H shows the MONSTER band L1-5, not the dungeon band L1-12")
	ck(cli.contains("Tier S[/color] [color=#808080](Levels 5001+)"), "and tier S tops the ladder")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
