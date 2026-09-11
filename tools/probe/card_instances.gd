extends SceneTree
## Every COPY of a card is its own card.
##
## Owner 2026-09-10: *"Put it in the deck and LEVEL IT UP, hoping for good milestones to stack on
## it. If the rolls disappoint, sell it on the market and try again with a fresh one."* That loop
## needs two Venom Fangs to be two Venom Fangs: separate uses, separate milestone picks, and a way
## to name the one being sold. Before 2026-09-11 the collection was `{card: count}` and all three
## progression dicts were keyed by card, so both copies were one card twice.
##
## This drives the REAL model - Character methods, the combat manager's deck build and cast path -
## rather than reading source, because the fault it guards against (a bare name resolving to the
## wrong copy) is invisible in source and only shows up when a second copy exists.
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

	print("--- ids ---")
	ck(Character.card_base("cleave#2") == "cleave" and Character.card_base("cleave") == "cleave", "card_base strips the copy suffix")
	ck(Character.card_copy_n("cleave") == 1 and Character.card_copy_n("cleave#3") == 3, "copy number: bare is 1")
	ck(Character.card_iid("cleave", 1) == "cleave" and Character.card_iid("cleave", 2) == "cleave#2", "first copy keeps the bare id")

	print("\n--- a legacy save migrates by SPLITTING counts, each copy inheriting the shared progress ---")
	var ch = sim.make_char(30, "average", "Fighter", "Human")
	ch.initialize_deck_collection_if_needed()
	var vf := "dungeon_card_venom_fang"
	ch.combat_deck_collection[vf] = 3
	ch.combat_deck_collection["cleave"] = 2
	ch.combat_deck_collection["berserk"] = 0
	ch.ability_uses["cleave"] = 40
	ch.ability_milestone_picks["cleave"] = ["power", "executioner"]
	ch.ability_effect_ranks["cleave"] = 2
	ch.initialize_deck_collection_if_needed()
	ck(ch.combat_deck_collection.has(vf) and ch.combat_deck_collection.has(vf + "#2") and ch.combat_deck_collection.has(vf + "#3"),
		"3 Venom Fangs became three instances")
	ck(int(ch.combat_deck_collection[vf]) == 1 and int(ch.combat_deck_collection[vf + "#3"]) == 1, "...each in the deck (value 1)")
	ck(int(ch.combat_deck_collection.get("cleave", 0)) == 1 and int(ch.combat_deck_collection.get("cleave#2", 0)) == 1, "2 Cleaves became two")
	ck(int(ch.ability_uses.get("cleave#2", 0)) == 40 and ch.ability_milestone_picks.get("cleave#2", []) == ["power", "executioner"]
		and int(ch.ability_effect_ranks.get("cleave#2", 0)) == 2, "the second Cleave inherited uses, picks and effect rank")
	ck(int(ch.combat_deck_collection.get("berserk", -1)) == 0 and not ch.combat_deck_collection.has("berserk#2"), "a benched card (0) stays one benched instance")
	ck(ch.card_copies_owned("cleave") == 2 and ch.card_copies_in_deck("cleave") == 2 and ch.card_copies_owned(vf) == 3, "counts read per card")
	var before := ch.combat_deck_collection.duplicate(true)
	ch.initialize_deck_collection_if_needed()
	ck(ch.combat_deck_collection == before, "migration is idempotent")

	print("\n--- the combat deck carries instances ---")
	var mon = sim.make_monster(30, "normal", 8.0)
	sim.combat_mgr.start_combat(0, ch, mon)
	var c = sim.combat_mgr.active_combats[0]
	var all_cards: Array = c.get("combat_deck", []).duplicate() + c.get("combat_hand", []).duplicate() + c.get("combat_discard", []).duplicate()
	ck(all_cards.count("cleave") == 1 and all_cards.count("cleave#2") == 1, "one entry per copy, named by copy")
	ck(all_cards.count(vf) == 1 and all_cards.count(vf + "#2") == 1 and all_cards.count(vf + "#3") == 1, "...three distinct Venom Fangs")
	ck(all_cards.count("berserk") == 0, "a benched copy is not dealt")

	print("\n--- progression lands on the copy that was PLAYED ---")
	c["combat_hand"] = ["cleave#2", vf]
	c["player_can_act"] = true
	c["suppress_monster_turn"] = true
	ch.current_stamina = ch.get_total_max_stamina()
	ch.ability_uses["cleave"] = 40
	ch.ability_uses["cleave#2"] = 40
	var res: Dictionary = sim.combat_mgr.process_ability_command(0, "cleave#2", "10")
	ck(bool(res.get("success", false)), "playing 'cleave#2' is accepted (the hand held it)")
	ck(int(ch.ability_uses.get("cleave#2", 0)) == 41 and int(ch.ability_uses.get("cleave", 0)) == 40,
		"the second copy's uses went up; the first copy's did not")
	ck(int(c.get("casts_this_fight", {}).get("cleave#2", 0)) == 1, "casts_this_fight is per copy")
	ck(not ("cleave#2" in c.get("combat_hand", [])), "...and that copy left the hand")
	ck(ch._active_card_iid == "", "the active-copy marker is cleared after the cast")
	c["combat_hand"] = ["cleave"]
	ch.current_stamina = ch.get_total_max_stamina()
	var res2: Dictionary = sim.combat_mgr.process_ability_command(0, "cleave#2", "10")
	ck(not bool(res2.get("success", true)), "'cleave#2' is refused when only 'cleave' is in hand - the copy is the card")

	print("\n--- a bare name resolves to the copy being resolved ---")
	ch.ability_milestone_picks["cleave"] = ["power"]
	ch.ability_milestone_picks["cleave#2"] = ["executioner"]
	ck(ch.get_milestone_picks("cleave") == ["power"], "with no copy active a bare name is the first copy")
	ch.set_active_card_instance("cleave#2")
	ck(ch.get_milestone_picks("cleave") == ["executioner"], "with cleave#2 active, 'cleave' reads cleave#2's picks")
	ck(ch.get_milestone_picks("berserk") == [], "...but another card is untouched")
	ch.clear_active_card_instance()
	var r := ch.apply_milestone_pick("cleave#2", "swift")
	ck(bool(r.get("ok", false)) and "swift" in ch.ability_milestone_picks["cleave#2"] and not ("swift" in ch.ability_milestone_picks["cleave"]),
		"a pick applied to 'cleave#2' lands only there")
	ck(int(ch.get_ability_rank_bonus("cleave#2")) == int(ch.get_ability_rank_bonus("cleave")), "gear rank bonus is per CARD, whichever copy")

	print("\n--- previews are per copy, keyed by the hand entry ---")
	c["combat_hand"] = ["cleave", "cleave#2"]
	var effs: Dictionary = sim.combat_mgr._build_ability_effect_info(c)
	ck(effs.has("cleave") and effs.has("cleave#2"), "both copies get a preview entry under their own key")
	var costs: Dictionary = sim.combat_mgr._build_ability_cost_info(c)
	ck(costs.has("cleave") and costs.has("cleave#2"), "...and a cost entry")
	ck(ch._active_card_iid == "", "the builders leave no active copy behind")
	sim.combat_mgr.end_combat(0) if sim.combat_mgr.has_method("end_combat") else null

	print("\n--- thin / restore / mint / sell ---")
	var ch2 = sim.make_char(30, "average", "Fighter", "Human")
	ch2.initialize_deck_collection_if_needed()
	ch2.combat_deck_collection["cleave"] = 1
	ch2.combat_deck_collection["cleave#2"] = 1
	ch2.combat_deck_collection["power_strike"] = 1
	ch2.combat_deck_collection["shield_bash"] = 1
	ch2.combat_deck_collection["iron_skin"] = 1
	ch2.combat_deck_collection["devastate"] = 1
	ch2.ability_milestone_picks["cleave"] = ["power", "rider"]
	ch2.ability_milestone_picks["cleave#2"] = []
	var cull := ch2.cull_ability_card("cleave")
	ck(bool(cull.get("ok", false)) and String(cull.get("instance", "")) == "cleave#2",
		"thinning 'cleave' benches the copy with the least invested (cleave#2, no picks)")
	ck(int(ch2.combat_deck_collection["cleave#2"]) == 0 and int(ch2.combat_deck_collection["cleave"]) == 1 and int(cull.get("new_count", -1)) == 1,
		"...it is benched, not deleted; the upgraded copy stays in")
	var add := ch2.add_ability_copy("cleave", false)
	ck(bool(add.get("ok", false)) and String(add.get("instance", "")) == "cleave#2" and int(ch2.combat_deck_collection["cleave#2"]) == 1,
		"'+' restores the benched copy for free rather than minting a third")
	var add2 := ch2.add_ability_copy("cleave", false)
	ck(not bool(add2.get("ok", true)), "a free '+' cannot mint a copy when none is benched")
	var g := ch2.grant_card_copy("cleave")
	ck(g == "cleave#3" and ch2.card_copies_owned("cleave") == 3, "a reward mints the lowest free copy number")
	ck(ch2.grant_card_copy("cleave") == "", "...and refuses past MAX_ABILITY_COPIES")
	var sell := ch2.least_invested_instance("cleave", false, true)
	ck(sell == "cleave#3" or sell == "cleave#2", "selling a bare 'cleave' picks a copy with nothing on it, never the upgraded one")
	ch2.ability_uses["cleave#3"] = 12
	var carried := ch2.remove_card_instance("cleave#3")
	ck(int(carried.get("uses", 0)) == 12 and not ch2.combat_deck_collection.has("cleave#3") and not ch2.ability_uses.has("cleave#3"),
		"a sold copy leaves with its progress and is forgotten here")
	var ch3 = sim.make_char(30, "average", "Wizard", "Human")
	ch3.initialize_deck_collection_if_needed()
	var got := ch3.grant_card_copy(vf, {"uses": 12, "picks": ["executioner"], "effect_rank": 1})
	ck(got == vf and int(ch3.ability_uses.get(vf, 0)) == 12 and ch3.ability_milestone_picks.get(vf, []) == ["executioner"],
		"a bought copy arrives carrying the seller's upgrades")
	var counts: Dictionary = ch2.deck_counts_by_card()
	ck(int(counts.get("cleave", -1)) == 2 and counts.has("power_strike"), "deck_counts_by_card gives the deck screen {card: in-deck copies}")

	print("\n--- names and lookups collapse to the card ---")
	ck(sim.combat_mgr._ability_display_name(ch, "cleave#2") == sim.combat_mgr._ability_display_name(ch, "cleave"), "a copy is named for its card")
	var avail_names := []
	for e in ch.get_all_available_abilities():
		avail_names.append(String(e.get("name", "")))
	ck(avail_names.count(vf) == 1 and not (vf + "#2" in avail_names), "the ability list shows each card once, never a copy id")

	print("\n--- wiring the model cannot prove on its own ---")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(srv.find("Character.card_base(cmd) in CombatManager.MAGE_ABILITY_COMMANDS") >= 0, "party combat recognises a copy's command")
	ck(srv.find("character.remove_card_instance(sell_iid)") >= 0 and srv.find('"instance": carried') >= 0, "the market sells ONE copy and the listing carries its progress")
	ck(srv.find("character.grant_card_copy(_bcid, _prog") >= 0, "the buyer receives that progress")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.find("var base_cmd := Character.card_base(command)") >= 0, "the client sends the copy and decides locally by the card")
	ck(cli.find("var deck_collection = _deck_counts_by_card()") >= 0, "the deck screen is fed per-card counts")
	var pnl := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	ck(pnl.find("var _card := Character.card_base(card_name)") >= 0, "the hand renders the card's art and the copy's facts")

	print("\n[CARDINST] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
