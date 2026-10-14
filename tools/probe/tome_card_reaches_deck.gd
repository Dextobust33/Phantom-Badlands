extends SceneTree
## Playtest sheet item 34: "Tome of Gambit card not in deck".
## CAUSE: the tome pool spans all three paths, but the deck builder only deals cards in
## get_all_available_abilities(). A Fighter reading a Gambit tome lost the tome and got an inert card.
## Server fix: `_use_ability_tome` refuses a card the class cannot play, BEFORE consuming it.
## This probe checks (a) every pool card a class CAN play really reaches a fight, (b) the ones it
## cannot are exactly the ones the server's guard would refuse, (c) the guard is a code statement.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var dt = load("res://shared/drop_tables.gd")
	var refused_total := 0
	for cls in ["Ranger", "Fighter", "Wizard"]:
		var ch = sim.make_char(30, "average", cls, "Human")
		ch.initialize_deck_collection_if_needed()
		var usable := {}
		for e in ch.get_all_available_abilities():
			usable[String(e.get("name", ""))] = true
		var granted: Array = []
		var refused := 0
		for card in dt.ABILITY_TOME_POOL:
			if not usable.has(card):
				refused += 1
				continue
			if ch.card_copies_owned(card) < 1:
				granted.append(ch.grant_card_copy(card))
		refused_total += refused
		var mon = sim.make_monster(30, "normal", 8.0)
		sim.combat_mgr.start_combat(0, ch, mon)
		var c = sim.combat_mgr.active_combats[0]
		var all_cards: Array = c.get("combat_deck", []).duplicate() + c.get("combat_hand", []).duplicate() + c.get("combat_discard", []).duplicate()
		var missing: Array = []
		for iid in granted:
			if not all_cards.has(iid):
				missing.append(iid)
		ck(missing.is_empty(), "%s: every card the server would accept is dealt (missing %s); %d pool cards refused" % [cls, str(missing), refused])
		sim.combat_mgr.active_combats.erase(0)
	ck(refused_total > 0, "the guard has something to refuse (%d)" % refused_total)
	# (d) Drops are aimed at the finder's path on pickup (owner 2026-10-14: "mostly finder's path").
	var gen = dt.new()
	for cls in ["Ranger", "Fighter", "Wizard"]:
		var ch2 = sim.make_char(30, "average", cls, "Human")
		var usable2 := {}
		for e in ch2.get_all_available_abilities():
			usable2[String(e.get("name", ""))] = true
		var on := 0
		var n := 1500
		for i in n:
			var t: Dictionary = gen._generate_ability_tome(30)
			ch2.inventory.clear()
			ch2.add_item(t)
			if usable2.has(String(ch2.inventory[0].get("gift_ability", ""))):
				on += 1
			if t.has("tome_unaimed"):
				ck(false, "the unaimed mark is cleared on pickup")
				break
		var frac := float(on) / n
		ck(frac > 0.78 and frac < 0.95, "%s: %.0f%% of fresh tomes are usable by the finder (want ~80-90%%)" % [cls, frac * 100.0])
	var market: Dictionary = gen._generate_ability_tome(30)
	market.erase("tome_unaimed")
	market["gift_ability"] = "gambit"
	var fighter = sim.make_char(30, "average", "Fighter", "Human")
	var same := true
	for i in 200:
		fighter.inventory.clear()
		fighter.add_item(market.duplicate())
		if String(fighter.inventory[0].get("gift_ability", "")) != "gambit":
			same = false
	ck(same, "a tome with no unaimed mark (market/trade) is never re-aimed")
	var tome_name_ok := true
	for i in 200:
		var t2: Dictionary = gen._generate_ability_tome(30)
		fighter.inventory.clear()
		fighter.add_item(t2)
		var it: Dictionary = fighter.inventory[0]
		if String(it.get("name", "")) != "Tome of %s" % dt.get_ability_tome_display(String(it.get("gift_ability", ""))):
			tome_name_ok = false
	ck(tome_name_ok, "the name always matches the card inside")
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var i := src.find("func _use_ability_tome(")
	var j := src.find("\nfunc ", i + 10)
	var body := src.substr(i, j - i)
	ck(body.find("\n\tif not _usable:\n") >= 0, "the server guard is a statement")
	ck(body.find("if not _usable:") < body.find("_spend_one_item("), "...and it runs before the tome is spent")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
