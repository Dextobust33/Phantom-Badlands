extends SceneTree
## ⛑ DOES EVERY CLASS START WITH EXACTLY ONE COPY OF EACH OF ITS CARDS?
##
## Owner 2026-09-16: *"All classes should only start with 1 copy of each of their cards. It seemed
## like we did a fix not too long ago to try to fix this."*
##
## The fix they are remembering is `repair_deck_once()` (commit 3ac2e08c), and it repaired deck
## SIZE - live saves carrying 6-13 cards against a designed 5. It says nothing about how many
## COPIES of one card a starter hands out, which is a different number and the one being asked
## about here.
##
## So: build a fresh character of all nine classes through the real `make_char` + deck init, and
## count copies per card. No source reading - the answer is whatever the constructor produces.
##
## Run:
##   godot --headless --path . --script res://tools/probe/deck_starts_with_one.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame

	var classes := ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage",
		"Grifter", "Ranger", "Ninja"]

	print("===== COPIES PER CARD IN A FRESH DECK =====")
	var offenders: Array = []
	for cls in classes:
		var ch = sim.make_char(1, "average", cls, "Human")
		ch.initialize_deck_collection_if_needed()
		# Count OWNED copies per base card, through the real accessor rather than by reading
		# the dictionary - `card_copies_owned` is what every gameplay path asks.
		var per_card := {}
		for k in ch.combat_deck_collection.keys():
			var base := Character.card_base(String(k))
			per_card[base] = true
		var doubled: Array = []
		for base in per_card.keys():
			var n: int = int(ch.card_copies_owned(String(base)))
			if n > 1:
				doubled.append("%s x%d" % [base, n])
		var total: int = ch.total_deck_copies()
		print("  %-10s cards=%-3d copies=%-3d %s" % [cls, per_card.size(), total,
			("⛑ " + ", ".join(doubled)) if not doubled.is_empty() else ""])
		if not doubled.is_empty():
			offenders.append(cls)
	ck(offenders.is_empty(), "no class starts with a duplicate card (offenders: %s)" % (
		", ".join(offenders) if not offenders.is_empty() else "none"))

	print("\n===== AND DOES USE-TRACKING BELONG TO THE CARD OR THE SKILL? =====")
	# Owner: *"They should not both track usage for the skill itself being used, it should
	# instead track the number of times that unique card has been used."*
	#
	# Two copies, then the progression key each one resolves to. If both land on the same key,
	# casting either advances both - which is the thing being reported.
	var ch2 = sim.make_char(30, "average", "Fighter", "Human")
	ch2.initialize_deck_collection_if_needed()
	var card := "cleave"
	var iid2: String = ch2.grant_card_copy(card)
	print("  copies: %s" % str(ch2.card_instances(card)))
	ck(iid2 != "", "a second copy could be granted (%s)" % iid2)

	# Cast copy 2 the way combat does: the active instance is announced, THEN uses are recorded.
	# `record_mastery_use` is the one combat calls on a SUCCESSFUL cast (record_ability_use is
	# the title-system spam counter and carries no args - easy to grab the wrong one).
	# Combat hands it the INSTANCE id (`hand_key`), so that is tested first, and then the
	# bare-name path with the active instance announced, which is what the twenty-odd
	# bare-name reads elsewhere in the cast rely on.
	ch2.ability_uses.clear()
	ch2.record_mastery_use(iid2)
	var u_bare: int = int(ch2.ability_uses.get(card, 0))
	var u_copy: int = int(ch2.ability_uses.get(iid2, 0))
	print("  after casting %s once:  uses[%s]=%d  uses[%s]=%d" % [iid2, card, u_bare, iid2, u_copy])
	ck(u_copy == 1 and u_bare == 0,
		"a cast addressed by instance id lands on that COPY, not the shared card name")

	ch2.ability_uses.clear()
	ch2.set_active_card_instance(iid2)
	ch2.record_mastery_use(card)          # bare name, as most of the cast path uses
	ch2.clear_active_card_instance()
	var b_bare: int = int(ch2.ability_uses.get(card, 0))
	var b_copy: int = int(ch2.ability_uses.get(iid2, 0))
	print("  after a BARE-name cast while %s is active:  uses[%s]=%d  uses[%s]=%d" % [
		iid2, card, b_bare, iid2, b_copy])
	ck(b_copy == 1 and b_bare == 0,
		"a bare-name cast is attributed to the ACTIVE copy, not to the card")

	print("\n===== VERDICT =====")
	if fails == 0:
		print("  all checks PASS")
	else:
		print("  %d check(s) FAIL" % fails)
	quit(0)
