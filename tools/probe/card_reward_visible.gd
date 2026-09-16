extends SceneTree
## ⛑ WHY A PLAYER GETS TWO UPGRADE POPUPS FOR "THE SAME CARD" AND THEN CANNOT FIND IT.
##
## Owner, live, 2026-09-14: *"They aren't working properly. Players aren't seeing or understanding
## what cards they are getting for completing dungeons. Sometimes they notice that two upgrade
## screens pop up back to back for the same card but it's nowhere to be found in their deck. They
## also have no way to differentiate between them even if it was."*
##
## Three complaints. This probe exists to find out whether they share ONE cause, by driving the
## real model: the legacy migration, `milestones_owed`, the rank-choice queue that raises the
## popup, and the text the popup would show.
##
## Run:
##   godot --headless --path . --script res://tools/probe/card_reward_visible.gd

const CM := preload("res://shared/combat_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	# ── The shape a real live character is in ────────────────────────────────────────────────
	# A player who has used a card a lot and owns three copies of it. Picks are EMPTY on purpose:
	# that is the documented state of every character who ranked a card up before 2026-09-05,
	# when the chosen upgrade was validated and then thrown away without being stored
	# (`_reconcile_lost_rank_choices` exists precisely to hand those entitlements back).
	var ch = sim.make_char(30, "average", "Fighter", "Human")
	ch.initialize_deck_collection_if_needed()
	var card := "cleave"
	ch.combat_deck_collection[card] = 3          # legacy: one key, a count
	ch.ability_uses[card] = 60                   # rank 2 at 10/50/200/1000
	ch.ability_milestone_picks.erase(card)       # ...and nothing ever stored

	print("===== 1. WHAT THE LEGACY MIGRATION DOES TO PROGRESS =====")
	ch.migrate_card_counts_to_instances()
	var insts: Array = ch.card_instances(card)
	print("  instances now: %s" % str(insts))
	var owed_each: Array = []
	for iid in insts:
		owed_each.append(int(ch.milestones_owed(String(iid))))
	print("  uses per instance:  %s" % str(insts.map(func(i): return int(ch.ability_uses.get(String(i), 0)))))
	print("  milestones OWED:    %s" % str(owed_each))
	var total_owed := 0
	for o in owed_each:
		total_owed += int(o)
	print("  → total popups this ONE card will raise: %d" % total_owed)
	ck(insts.size() == 3, "three copies exist after migration")
	# This is the heart of it. The migration copies the USE COUNT onto every copy (correct - they
	# WERE that progress) and the PICKS with it. With picks empty, every copy independently owes
	# the same milestones, so one card raises three times as many popups as the player expects.
	ck(total_owed == owed_each[0] * insts.size(),
		"every copy owes the SAME milestones (%d each) - one card, %d popups" % [int(owed_each[0]), total_owed])

	print("\n===== 2. DOES EVERY SURFACE THAT NAMES A CARD SAY WHICH COPY? =====")
	# ⛑ THE FIRST VERSION OF THIS CHECK WAS AN INSTRUMENT DEFECT and is worth recording.
	#
	# It resolved the name through `DropTables.card_display_name(base)`, reported that all three
	# copies read "Cleave\'s Gift", and declared the display broken. But that is not the resolver
	# the game uses: the client has `_card_copy_label`, which appends " · copy N" whenever more
	# than one copy is owned, and the deck screen has been showing "Forcefield · copy 1" for days.
	# An audit written around the wrong UNIT is as wrong as a guess and far more convincing.
	#
	# So the real question is not "can a copy be named" - it can - but WHICH SURFACES forget to.
	# That is a source sweep, because the rule is "every site that names a card calls the labeller",
	# and it is the check that would have caught the 2026-09-15 fix landing on some sites only.
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var missing: Array = []
	for line in src.split("\n"):
		var t := String(line)
		if t.find("_ability_display_name(") < 0:
			continue
		if t.find("func _ability_display_name") >= 0:
			continue
		# Only the sites that build a LABEL A PLAYER READS. A call used to compare or look something
		# up does not need the copy number.
		var is_label := t.find("var title") >= 0 or t.find("var display") >= 0 \
			or t.find("ability_label") >= 0 or t.find("_ms_ability_label") >= 0 \
			or t.find("_label") >= 0 or t.find("cull_label") >= 0
		if not is_label:
			continue
		# The in-combat TARGET prompt is exempt, and deliberately so: "Cleave on Goblin" names
		# the card being cast this instant, and which copy the deck drew is not something the
		# player chose or can act on. A copy number there is noise at the one moment they are
		# picking a target. Exempted by name rather than by loosening the rule.
		if t.find("_canonical_ability(command") >= 0:
			continue
		if t.find("_card_copy_label") < 0:
			missing.append(t.strip_edges())
	print("  player-facing card labels missing the copy number: %d" % missing.size())
	for m in missing:
		print("    " + m)
	ck(missing.is_empty(), "every surface that NAMES a card for the player says which copy")

	print("\n===== 3. A FRESHLY GRANTED DUNGEON CARD: DOES IT LAND, ONCE? =====")
	var ch2 = sim.make_char(30, "average", "Fighter", "Human")
	ch2.initialize_deck_collection_if_needed()
	var dcard := "dungeon_card_venom_fang"
	var before: int = ch2.card_copies_owned(dcard)
	var iid1: String = ch2.grant_card_copy(dcard)
	var after: int = ch2.card_copies_owned(dcard)
	print("  granted %-28s owned %d -> %d" % [iid1, before, after])
	ck(iid1 != "" and after == before + 1, "one grant adds exactly one copy")
	ck(int(ch2.milestones_owed(iid1)) == 0, "a FRESH copy owes no milestones (so it raises no popup)")

	print("\n===== VERDICT =====")
	if fails == 0:
		print("  all checks PASS - the complaints are not reproduced by this model")
	else:
		print("  %d check(s) FAIL - see above; each failure is one of the owner's three complaints" % fails)
	quit(0)
