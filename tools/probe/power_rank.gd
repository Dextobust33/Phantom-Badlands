extends SceneTree
## A player must be able to order two labels without being told the rule.
##
## Owner, 2026-09-09: *"the Tier and subtier are confusing."* And on the replacement, 2026-09-11:
## *"only if we can make it clear to the player what is better than what... they need to know and
## understand if they have higher tier and rank monster."*
##
## So the checks here are not "does it print a string" — they are "does the printed thing ORDER
## correctly, and does it carry its own explanation".
const PR := preload("res://shared/power_rank.gd")
const DD := preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- the ladder: nine tiers, nine letters, exactly one S ---")
	ck(PR.LADDER.size() == 9, "nine letters for nine tiers (TIER_LEVEL_BANDS has 9)")
	var seen := {}
	for l in PR.LADDER:
		seen[l] = true
	ck(seen.size() == 9, "all nine are distinct — no letter has to be told apart from itself")
	var s_count := 0
	for l in PR.LADDER:
		if String(l).begins_with("S"):
			s_count += 1
	ck(s_count == 1, "exactly ONE S. Owner: \"too many S's, we need an alternative on that\"")
	ck(PR.letter(1) == "H" and PR.letter(9) == "S", "H is the floor, S the apex")

	print("\n--- BOTH halves ascend: later letter wins, higher number wins ---")
	# The whole point of the rename. If this fails the label is no better than [T1-5].
	var strictly_increasing := true
	var last := -1
	for t in range(1, 10):
		for r in range(1, PR.RANKS + 1):
			var idx: int = PR.power_index(t, r)
			if idx <= last:
				strictly_increasing = false
			last = idx
	ck(strictly_increasing, "every one of the 81 steps is stronger than the one before it")
	ck(PR.power_index(2, 1) > PR.power_index(1, 9),
		"the WEAKEST of a higher tier still beats the STRONGEST of a lower one (G1 > H9)")
	ck(PR.power_index(4, 7) > PR.power_index(4, 3), "within a tier, higher rank wins (E7 > E3)")

	print("\n--- rank covers the whole domain, including the part only companions reach ---")
	# Companions fuse up to sub_tier 9; dungeons only generate 1-8. A cap of 8 here would have
	# collapsed the single best companion rank in the game into the second best, everywhere.
	ck(PR.RANKS == 9, "RANKS is 9 — the domain fusion actually produces, not the dungeon's 8")
	ck(PR.label(5, 9) == "D9" and PR.label(5, 8) == "D8",
		"a fused rank-9 companion is distinguishable from a rank-8 one")
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.contains("mini(current_sub_tier + 1, 9)"),
		"...and that 9 is still what the server's fusion actually caps at")

	print("\n--- nothing is rendered bare: the ordering is always SHOWN ---")
	ck(PR.color(1) != PR.color(9), "the danger ramp separates floor from apex")
	var distinct := {}
	for t in range(1, 10):
		distinct[PR.color(t)] = true
	ck(distinct.size() == 9, "every tier has its own colour — no two read as the same danger")
	ck(PR.tag(3, 4).contains("[color=") and PR.tag(3, 4).contains("F4"),
		"tag() carries the colour for panels with no hover handler")
	var rl := PR.rich_label(3, 4)
	ck(rl.contains("[url=") and rl.contains("[color="),
		"rich_label() carries BOTH the colour and the explanation")

	print("\n--- and the explanation actually explains ---")
	var h := PR.hover(4, 6)
	# The marker is >E<, not [E]: a square bracket inside a [url=...] value terminates the
	# tag and dumps the hover into the visible line. See PowerRank._url_safe.
	ck(h.contains("H G F") and h.contains(">E<"),
		"the hover shows the whole ladder with THIS tier marked")
	ck(h.contains("weakest") and h.contains("strongest"), "...and which end is which")
	ck(h.contains("Higher rank is stronger"), "...and the within-tier rule, in words")
	ck(PR.pips(1).begins_with("▰") and PR.pips(1).count("▰") == 1
		and PR.pips(9).count("▰") == 9,
		"pips() answers 'how far along am I' without knowing a single letter")

	print("\n--- the dungeon name uses it, and carries no markup ---")
	var name := DD.get_dungeon_display_name("goblin_caves", 1, 5)
	ck(name.contains("[H5]"), "a dungeon reads 'Goblin Caves [H5]' — got: %s" % name)
	ck(not name.contains("[color=") and not name.contains("[url="),
		"plain: this string reaches Button.text and log lines too, which cannot render BBCode")

	print("\n--- the old notation is gone everywhere ---")
	var leftovers := 0
	for f in ["res://client/client.gd", "res://shared/dungeon_database.gd", "res://server/server.gd",
			"res://client/companions_panel.gd", "res://client/kennel_panel.gd",
			"res://client/fusion_panel.gd", "res://client/market_panel.gd"]:
		leftovers += FileAccess.get_file_as_string(f).count("T%d-%d")
	ck(leftovers == 0, "no surface still builds the old [T1-5] form — got %d" % leftovers)

	print("
--- the help page is GENERATED, not a second copy of the ladder ---")
	# A hand-typed ladder in the help text was the first draft, and it is the worst possible
	# place for a stale copy: the page a confused player opens would teach the wrong order.
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.contains('"content": _tier_rank_help()'),
		"the Tier & Rank topic calls a generator rather than a written-out table")
	var g0 := cli.find("func _tier_rank_help()")
	var gbody := cli.substr(g0, cli.find("\nfunc ", g0 + 10) - g0) if g0 >= 0 else ""
	ck(gbody.contains("PowerRank.LADDER") and gbody.contains("PowerRank.color("),
		"...and reads the ladder and the colours from their real sources")
	# Comments STRIPPED first. The generator explains in a COMMENT why the level band was removed,
	# and that comment mentions L1-12 - a check that cannot tell a comment from a typed table
	# fails on the explanation for its own rule. The same confusion cost a cycle earlier today.
	var code_only := ""
	for gl in gbody.split("\n"):
		if not gl.strip_edges().begins_with("#"):
			code_only += gl + "\n"
	ck(not code_only.contains("L1-12") and not code_only.contains("H G F E D C B A S"),
		"...with no band or letter typed into the generated text by hand")

	print("
--- DUNGEONS reach the top rank, same as companions ---")
	# Owner 2026-09-11: "Let's do dungeons all the way up to the top rank." Dungeons stopped at
	# 8 while fusion reached 9, so the best dungeon findable was labelled a rank below the best
	# companion ownable, for no stated reason.
	var ranks_seen := {}
	for i in range(20000):
		ranks_seen[DD.get_sub_tier_for_distance(1, randf_range(30.0, 60.0))] = true
	ck(ranks_seen.has(PR.RANKS), "rank %d is actually REACHABLE from a spawn roll" % PR.RANKS)
	ck(ranks_seen.size() == PR.RANKS, "every rank 1..%d occurs - no gap in the ladder" % PR.RANKS)
	var lo := 1 << 30
	var hi := -1
	for r in ranks_seen:
		lo = mini(lo, int(r))
		hi = maxi(hi, int(r))
	ck(lo == 1 and hi == PR.RANKS, "and nothing spawns outside 1..%d" % PR.RANKS)

	# The CEILING must not have moved. Adding a slice is not the same as raising difficulty:
	# the last segment still ends exactly at the tier band's max, as it did with eight.
	var ceiling_held := true
	var floor_held := true
	for t in range(1, 10):
		var band: Dictionary = PR.dungeon_band(t)
		var top: Dictionary = DD.get_sub_tier_level_range(t, PR.RANKS)
		var bot: Dictionary = DD.get_sub_tier_level_range(t, 1)
		if int(top.max_level) != int(band.max):
			ceiling_held = false
		if int(bot.min_level) != int(band.min):
			floor_held = false
	ck(ceiling_held, "the top rank of every tier still ends at that tier's max level")
	ck(floor_held, "...and rank 1 still starts at its min - the band is sliced, not stretched")

	print("
--- no COMPANION surface still speaks the old system ---")
	# Owner: "ensure every companion surface is covered so we no longer see the old TX-X system."
	var surfaces := ["res://client/client.gd", "res://client/help_panel.gd",
		"res://client/fusion_panel.gd", "res://client/admin_panel.gd",
		"res://client/companion_stable_panel.gd", "res://client/sanctuary_stable_panel.gd",
		"res://client/companions_panel.gd", "res://client/kennel_panel.gd",
		"res://client/market_panel.gd", "res://server/server.gd",
		"res://shared/drop_tables.gd", "res://shared/character.gd"]
	for dead in ["T%d-%d", "T8.8", "Mixed T9", "sub-tier", "Sub-tier"]:
		var hits := 0
		var where := ""
		for f in surfaces:
			var c: int = FileAccess.get_file_as_string(f).count(dead)
			if c > 0:
				hits += c
				where += " " + f.get_file()
		ck(hits == 0, "no surface still says %-10s - %d left%s" % [dead, hits, where])

	# The fusion capstone was mislabelled long before the rename: it consumes tier-8 rank-8
	# companions and yields RANK 9 of the same tier, so "Mixed T9" was wrong in both halves.
	var stable := FileAccess.get_file_as_string("res://client/companion_stable_panel.gd")
	ck(stable.contains("Mixed A9"), "the capstone reads A8 -> A9, which is what it actually does")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
