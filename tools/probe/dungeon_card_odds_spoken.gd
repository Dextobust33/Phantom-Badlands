extends SceneTree
## A dungeon clear says what it did about your card - including when it gave you none.
##
## Owner 2026-09-15: *"Where does it show what card I got for the dungeon or is it not a guarantee
## or still on the to do?"* - alongside a live report that the dungeon card award was invisible.
##
## It was not hidden. `_roll_dungeon_card_reward` pays a card with probability
## `min(0.30, (0.05 + tier*0.02) * (1 + (rank-1)*0.1))`, which for the STARTER dungeon (tier 1,
## rank 1) is SEVEN PERCENT - and the completion screen only ever spoke when a card dropped. So
## 93 runs in 100 the honest answer was total silence, which reads exactly like a bug. Live saves
## (18 characters) held no dungeon card at all, which fits: nobody was losing cards, almost nobody
## was being given one.
##
## This measures the real roll rate and asserts the completion text speaks either way.
const ServerScript = preload("res://server/server.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const CharacterScript = preload("res://shared/character.gd")
const TRIALS := 4000

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sv = ServerScript.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)

	print("===== HOW OFTEN A CLEAR PAYS A CARD =====")
	print("  tier  rank   measured    stated")
	var starter_rate := 0.0
	for cell in [[1, 1], [1, 9], [5, 1], [9, 9]]:
		var tier: int = cell[0]
		var rank: int = cell[1]
		var hits := 0
		var stated := 0.0
		for i in range(TRIALS):
			seed(hash("card|%d|%d|%d" % [tier, rank, i]))
			var c = CharacterScript.new()
			c.name = "Probe"
			c.class_type = "warrior"
			c.level = maxi(1, tier * 10)
			c.initialize_deck_collection_if_needed()
			var out: Dictionary = sv._roll_dungeon_card_reward(c, tier, "", false, rank)
			stated = float(out.get("chance", 0.0))
			if bool(out.get("granted", false)):
				hits += 1
		var rate: float = float(hits) / float(TRIALS)
		if tier == 1 and rank == 1:
			starter_rate = rate
		print("  %-5d %-6d %6.1f%%     %5.1f%%" % [tier, rank, rate * 100.0, stated * 100.0])
		# The roll can decline to grant even after passing the chance (every card maxed), so the
		# measured rate is a ceiling test against the stated one, not an equality.
		ck(rate <= stated + 0.03, "tier %d rank %d: the stated chance is not an understatement" % [tier, rank])

	ck(starter_rate < 0.15,
		"the STARTER dungeon really does pay a card rarely (%.1f%%) - so silence there was the common case" % (starter_rate * 100.0))

	print("")
	print("===== AND THE SCREEN SAYS SO EITHER WAY =====")
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var at := src.find("# v0.9.679 / #38 — card drop callout")
	ck(at >= 0, "found the completion screen's card section")
	var section := src.substr(at, 2200)
	ck(section.contains("DUNGEON CARD EARNED"), "it speaks when an exclusive card drops")
	ck(section.contains("RARE CARD DROP"), "...and when a copy drops")
	ck(section.contains("No card this run"), "...and when NOTHING drops, which was the missing 93%")
	ck(section.contains('_card_reward.get("chance"'),
		"the odds it quotes come from the roll itself, not a second copy of the formula")
	ck(section.contains("dungeon_card_id_for_dungeon"),
		"and it names the card this dungeon is the only source of, so the run has a stated goal")

	# The odds must actually reach the message - a default of 0.0 would print "1%" forever.
	var c2 = CharacterScript.new()
	c2.name = "Probe2"
	c2.class_type = "warrior"
	c2.level = 10
	c2.initialize_deck_collection_if_needed()
	var r2: Dictionary = sv._roll_dungeon_card_reward(c2, 1, "", false, 1)
	print("  a starter roll reports chance=%.3f" % float(r2.get("chance", 0.0)))
	ck(float(r2.get("chance", 0.0)) > 0.0, "every roll carries its own odds back, granted or not")

	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
