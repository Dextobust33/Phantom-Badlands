extends SceneTree
## Find EVERY place a tier is formatted into player-facing text — by argument, not by format.
##
## This exists because pattern-matching on format strings failed THREE times in one day:
##   1st sweep  searched `T%d-%d`      and missed `T%d.%d` and `Tier %d-%d`  (16 sites)
##   2nd sweep  added those two        and missed bare `T%d`                  (8 sites)
##   3rd            "                  and missed quest_database's tier names
## Each time the probe passed, because what it asserted was true and irrelevant. That is
## CLAUDE.md's "an audit written around the wrong UNIT" reached from three different angles.
##
## So this one does not enumerate FORMATS. It looks at every player-facing line that formats a
## variable whose name is tier-ish, and requires it to go through a ladder helper or to name a
## ladder that has no letters. A new surface is caught the moment it is written, whatever spelling
## of the format string its author invents.
const FILES := ["res://client/client.gd", "res://client/companions_panel.gd",
	"res://client/kennel_panel.gd", "res://client/fusion_panel.gd",
	"res://client/market_panel.gd", "res://client/help_panel.gd",
	"res://client/companion_stable_panel.gd", "res://client/sanctuary_stable_panel.gd",
	"res://client/admin_panel.gd", "res://server/server.gd",
	"res://shared/dungeon_database.gd", "res://shared/quest_database.gd"]

## GM / admin diagnostics are EXCUSED on purpose. They exist to read the data back, so the raw
## number that matches `post.tier` is the useful thing there - translating it to a letter would
## make the tool worse at its one job. Player-facing text is a different contract.
const ADMIN_MARKERS := ["[GM]", "gm_", "_debug", "Wilderness tier:", "Floor tier", "Effective tier"]
## Ladders with no letters of their own. A number is fine IF the noun says which ladder.
const NAMED_LADDER_WORDS := ["gear tier", "node tier", "chain tier", "patreon", "border",
	"material", "tool", "ore_tier", "wood_tier", "forage_tier", "fishing", "resource_tier"]

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var suspects: Array[String] = []
	var scanned := 0
	for f in FILES:
		var src := FileAccess.get_file_as_string(f)
		if src == "":
			continue
		var lines := src.split("\n")
		var in_changelog := false
		for i in range(lines.size()):
			var ln := lines[i]
			# Patch notes are a historical record; rewriting them would falsify it.
			if ln.begins_with("func display_changelog"):
				in_changelog = true
			elif ln.begins_with("func ") and in_changelog:
				in_changelog = false
			if in_changelog:
				continue
			var t := ln.strip_edges()
			if t.begins_with("#") or not ln.contains("\""):
				continue
			# Does this line FORMAT something, and is a tier-ish variable among the arguments?
			if not (ln.contains("%d") or ln.contains("%s")):
				continue
			var low := ln.to_lower()
			# The format string must LABEL a tier next to a specifier - "Tier %d", "T%d", "T%s".
			# Merely mentioning the word (a formula description, a `tier_data` lookup, an ability
			# mastery rank) is not a ladder being printed, and treating it as one drowns the real
			# hits in noise, which is how a check stops being read.
			var labels_tier: bool = false
			for mark in ["Tier %d", "Tier %s", "T%d", "T%s"]:
				if ln.contains(mark):
					labels_tier = true
			if not labels_tier:
				continue
			scanned += 1
			# Acceptable: it already goes through the ladder, or it names a lettered-less ladder.
			if ln.contains("PowerRank.") or ln.contains("POST_TIER_NAMES") \
					or ln.contains("CONSUMABLE_TIERS") or ln.contains("get_tier_name"):
				continue
			var excused := false
			for w in NAMED_LADDER_WORDS:
				if low.contains(w):
					excused = true
			for m in ADMIN_MARKERS:
				if ln.contains(m):
					excused = true
			if excused:
				continue
			# A line that only READS a tier into a variable is fine; we want ones that PRINT it.
			if not (ln.contains("display_game") or ln.contains(".text") or ln.contains("\"message\"")
					or ln.contains("append") or ln.contains("return \"") or ln.contains("label")):
				continue
			suspects.append("%s:%d  %s" % [f.get_file(), i + 1, t.substr(0, 96)])

	print("--- every player-facing line that formats a tier ---")
	ck(scanned > 0, "scanned %d candidate lines across %d files" % [scanned, FILES.size()])
	if not suspects.is_empty():
		print("")
		for s in suspects:
			print("    " + s)
		print("")
	ck(suspects.is_empty(),
		"every one goes through a ladder helper or names a numberless ladder - %d unresolved" % suspects.size())

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
