extends SceneTree
## ⛑ DOES AN UPGRADED CARD ACTUALLY LOOK DIFFERENT — IN BOTH PLACES YOU SEE IT?
##
## Owner 2026-09-04: *"Upgrading a card and then the card looking exactly the same and the
## description being exactly the same sucks."* Listing the upgrades in the description was the
## floor and shipped long ago. The part that stayed open for a fortnight was the CARD looking like
## a different card — *"in the deck screen AND the combat hand, not the same art with a line
## appended."*
##
## ⚡ "BOTH PLACES" IS THE WHOLE RISK. The deck screen and the combat hand are exactly the pair
## this codebase keeps finding drifted: the action bar kept its own card-name table, the combat log
## styled cards by literal word, the buff panel had a third copy. A card that looks invested-in
## while you build your deck and plain the moment it reaches your hand is the same bug again.
## So the look is ONE pure function and this asserts that both surfaces ask it.
##
## Run:
##   godot --headless --path . --script res://tools/probe/an_upgraded_card_looks_upgraded.gd

const CardUpgradesScript := preload("res://shared/card_upgrades.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	print("")
	print("===== 1. THE LOOK ACTUALLY CHANGES =====")
	print("  %-9s %-6s %-7s %-16s %s" % ["upgrades", "tier", "border", "sigil", "name"])
	var seen := {}
	for n in [0, 1, 2, 3, 4, 6]:
		var l: Dictionary = CardUpgradesScript.card_upgrade_look(n)
		print("  %-9d %-6d %-7d %-16s %s" % [n, int(l.get("tier", 0)),
			int(l.get("border_width", 0)), String(l.get("sigil", "-")), String(l.get("name", "-"))])
		seen[int(l.get("tier", 0))] = l
	# ⛑ A "look" that returns the same thing at every count is exactly the failure being fixed,
	# and it would pass any check that only asked whether the function exists.
	if seen.size() < 3:
		_fail("only %d distinct looks across 0-6 upgrades - an upgraded card would still look "
			% seen.size() + "like an un-upgraded one")
	else:
		_ok("%d distinct looks, so investment reads at a glance" % seen.size())
	var widths := {}
	for t in seen.keys():
		widths[int(seen[t].get("border_width", 0))] = true
	if widths.size() != seen.size():
		_fail("two different tiers draw the SAME border width - they are not distinguishable")
	else:
		_ok("each tier has its own frame weight")

	print("")
	print("===== 2. A PLAIN CARD WEARS NO BADGE =====")
	# A badge every card wears is furniture, not a badge - and it would cost width on a card face
	# that is already tight.
	var plain: Dictionary = CardUpgradesScript.card_upgrade_look(0)
	if String(plain.get("sigil", "")) != "":
		_fail("an un-upgraded card still draws a sigil (%s)" % String(plain.get("sigil", "")))
	else:
		_ok("an un-upgraded card draws nothing extra")
	if int(plain.get("border_width", 0)) != 2:
		_fail("an un-upgraded card's frame is %d, not the plain 2" % int(plain.get("border_width", 0)))
	else:
		_ok("an un-upgraded card keeps the ordinary frame")

	print("")
	print("===== 3. COUNTING: PER COPY, AND THE BEST COPY =====")
	var cd := {"ability_milestone_picks": {
		"cleave": ["a"],
		"cleave#2": ["a", "b", "c"],
		"cleaver": ["a", "b", "c", "d", "e"],   # a DIFFERENT card whose id starts the same
		"analyze": [],
	}}
	if CardUpgradesScript.card_upgrade_count(cd, "cleave#2") != 3:
		_fail("a copy's own count is wrong")
	else:
		_ok("a copy is counted by its own picks")
	var best: int = CardUpgradesScript.card_upgrade_count_best(cd, "cleave")
	print("  cleave: copy 1 has 1, copy 2 has 3  ->  best = %d" % best)
	if best != 3:
		_fail("the best copy of cleave reported %d, expected 3" % best)
	elif CardUpgradesScript.card_upgrade_count_best(cd, "cleave") == 5:
		_fail("`cleave` picked up `cleaver` - prefix matching without the # separator")
	else:
		_ok("the card tile shows its best copy, and does not pick up a similarly-named card")
	if CardUpgradesScript.card_upgrade_count_best(cd, "analyze") != 0:
		_fail("a card with an empty pick list counted as upgraded")
	else:
		_ok("an empty pick list is not an upgrade")
	if CardUpgradesScript.card_upgrade_count({}, "cleave") != 0:
		_fail("a character with no picks at all errored or counted something")
	else:
		_ok("a character with no picks counts zero")

	print("")
	print("===== 4. BOTH SURFACES ASK THE SAME FUNCTION =====")
	# ⛑ MATCHED ON THE CALL. Two probes passed this week while matching a COMMENT that named the
	# thing being checked; a comment cannot contain a call with its opening bracket.
	var hand := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	var deck := FileAccess.get_file_as_string("res://client/ability_panel.gd")
	if hand.find("CardUpgrades.card_upgrade_look(") < 0:
		_fail("the COMBAT HAND no longer asks CardUpgrades.card_upgrade_look - an upgraded card "
			+ "is plain again in the one place you play it")
	else:
		_ok("the combat hand draws from CardUpgrades.card_upgrade_look")
	if deck.find("CardUpgrades.card_upgrade_look(") < 0:
		_fail("the DECK SCREEN no longer asks CardUpgrades.card_upgrade_look - the two surfaces "
			+ "can now disagree about what an upgraded card looks like")
	else:
		_ok("the deck screen draws from CardUpgrades.card_upgrade_look")
	# The per-copy row is the only place two copies of one card can be told apart at all.
	if deck.find("card_upgrade_count(") < 0:
		_fail("the deck screen's per-COPY rows no longer vary - a three-times-upgraded Cleave and "
			+ "a fresh one are two identical rows again")
	else:
		_ok("the per-copy rows carry each copy's own upgrades")
	# ⚑ AND THE FRAME IS RESET ON REUSE. The hand recycles five cells, so a thick frame left by an
	# Ascendant card is inherited by whatever is dealt into that slot next - the same shape as the
	# finisher halo that had to be reset here for exactly this reason.
	var i := hand.find("func _set_cell_dim(")
	if i < 0:
		_fail("_set_cell_dim is gone")
	else:
		var j := hand.find("\nfunc ", i + 8)
		var body := hand.substr(i, (j - i) if j > i else 2500)
		if body.find("set_border_width_all(2)") < 0:
			_fail("the hand cell's frame is not reset between refreshes - an upgraded card's "
				+ "thick frame is inherited by the next card dealt into that slot")
		else:
			_ok("the frame is reset on cell reuse, so no card inherits another's")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS an upgraded card reads as one in the deck screen and in the hand, both")
	print("       from one table, and a plain card wears nothing extra.")
	quit()
