extends SceneTree
## ⛑ EVERY DUNGEON HAS A CARD, AND EVERY CARD DOES SOMETHING.
##
## Owner 2026-09-17, asked what the 49 dungeons with no exclusive card should offer instead of a
## generic copy-drop: *"Write cards for all 53."*
##
## The four ways this content pass can be wrong are all silent:
##
##   1. **A dungeon with no card.** It falls back to the copy-drop and the clear has nothing named
##      to chase — the exact hole this closes, and the easiest gap to leave across 53 rows.
##   2. **A `kind` with no arm in the processor.** `_process_companion_ability`'s `match` has
##      a `_:` fallback that deals plain strike damage, so a typo'd kind produces a card that
##      works, reads as a poison strike on its own face, and quietly is not one.
##   3. **A `tier` that disagrees with the dungeon.** Every kind scales its numbers off `tier`, so
##      a wrong one is a mis-sized card and nothing else complains. The value is stored in the row
##      (dungeon_database sits on the other side of drop_tables' imports), so this is the guard
##      that keeps the copy honest.
##   4. **A `cycle` type the payout does not implement.** `_cycle_unplayed` simply skips it, so the
##      card's own description promises an effect it never pays.
##
## So the checks read the REAL tables and then CAST all 53 through the real processor.
##
## Run:
##   godot --headless --path . --script res://tools/probe/dungeon_cards_complete.gd

const DT := preload("res://shared/drop_tables.gd")
const DDB := preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


## The kinds the processor really implements, read off its source rather than listed here — a
## hand-written list is the second copy this check exists to prevent.
func _implemented_kinds() -> Array:
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var i := src.find("func _process_companion_ability")
	if i < 0:
		return []
	var j := src.find("\nfunc ", i + 10)
	var body := src.substr(i, (j - i) if j > i else 12000)
	var out: Array = []
	for line in body.split("\n"):
		var t: String = line.strip_edges()
		if line.begins_with("\t\t\"") and t.ends_with("\":"):
			out.append(t.substr(1, t.length() - 3))
	return out


func _cycle_types() -> Array:
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var i := src.find("func _cycle_unplayed")
	var j := src.find("\nfunc ", i + 10)
	var body := src.substr(i, (j - i) if j > i else 6000)
	var out: Array = []
	for line in body.split("\n"):
		var t: String = line.strip_edges()
		if line.begins_with("\t\t\t\"") and t.ends_with("\":"):
			out.append(t.substr(1, t.length() - 3))
	return out


func _init() -> void:
	var cards: Dictionary = DT.DUNGEON_CARD_DATA
	var dungeons: Array = DDB.DUNGEON_TYPES.keys()

	print("===== 1. 53 DUNGEONS, 53 CARDS, ONE EACH =====")
	print("           %d dungeon types, %d cards" % [dungeons.size(), cards.size()])
	var missing: Array = []
	for id in dungeons:
		if DT.dungeon_card_id_for_dungeon(String(id)) == "":
			missing.append(String(id))
	for m in missing:
		print("           NO CARD: " + String(m))
	ck(missing.is_empty(), "every dungeon type has a card (%d without)" % missing.size())
	# ...and nothing points at a dungeon that does not exist, which would be a card nobody can
	# ever earn - indistinguishable from one that is merely rare.
	var orphans: Array = []
	var claimed: Dictionary = {}
	for slug in cards.keys():
		var d: String = String(cards[slug].get("dungeon", ""))
		if not DDB.DUNGEON_TYPES.has(d):
			orphans.append("%s -> %s" % [slug, d])
		if claimed.has(d):
			orphans.append("%s and %s both claim %s" % [slug, claimed[d], d])
		claimed[d] = slug
	for o in orphans:
		print("           ORPHAN: " + String(o))
	ck(orphans.is_empty(), "and no card is unearnable or double-claimed (%d)" % orphans.size())

	print("\n===== 2. EVERY KIND AND CYCLE IS ONE THE CODE IMPLEMENTS =====")
	var kinds: Array = _implemented_kinds()
	var cycles: Array = _cycle_types()
	print("           processor implements %d kinds, payout implements %d cycle types" % [
		kinds.size(), cycles.size()])
	ck(kinds.size() >= 15, "the kind list was read off the processor (%d)" % kinds.size())
	ck(cycles.size() >= 5, "and the cycle list off the payout (%d)" % cycles.size())
	var bad_kind: Array = []
	var bad_cycle: Array = []
	for slug in cards.keys():
		var c: Dictionary = cards[slug]
		if not kinds.has(String(c.get("kind", ""))):
			bad_kind.append("%s kind=%s" % [slug, c.get("kind", "")])
		var cy: Dictionary = c.get("cycle", {})
		if cy.is_empty() or not cycles.has(String(cy.get("type", ""))):
			bad_cycle.append("%s cycle=%s" % [slug, str(cy)])
	for b in bad_kind + bad_cycle:
		print("           UNIMPLEMENTED: " + String(b))
	# ⛑ A typo'd kind does NOT error. It hits the `_:` fallback and deals plain strike damage, so
	# the card works, reads as something else on its own face, and is quietly a lie.
	ck(bad_kind.is_empty(), "no card names a kind with no arm (%d)" % bad_kind.size())
	ck(bad_cycle.is_empty(), "and none promises a cycle the payout skips (%d)" % bad_cycle.size())

	print("\n===== 3. TIER MATCHES THE DUNGEON THAT DROPS IT =====")
	var tier_bad: Array = []
	for slug in cards.keys():
		var c: Dictionary = cards[slug]
		var d: Dictionary = DDB.DUNGEON_TYPES.get(String(c.get("dungeon", "")), {})
		var want: int = int(d.get("base_tier", -1))
		if int(c.get("tier", 0)) != want:
			tier_bad.append("%s tier=%d, dungeon base_tier=%d" % [slug, int(c.get("tier", 0)), want])
	for t in tier_bad:
		print("           MISMATCH: " + String(t))
	ck(tier_bad.is_empty(), "every card is sized to its own dungeon (%d off)" % tier_bad.size())

	print("\n===== 4. THE COLLECTION IS VARIED, AND THE STRONG KINDS ARE GATED =====")
	var by_kind: Dictionary = {}
	for slug in cards.keys():
		var k: String = String(cards[slug].get("kind", ""))
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	var widest := 0
	var widest_k := ""
	var line := ""
	for k in by_kind.keys():
		line += "%s %d  " % [k, int(by_kind[k])]
		if int(by_kind[k]) > widest:
			widest = int(by_kind[k])
			widest_k = String(k)
	print("           " + line)
	ck(by_kind.size() >= 15, "the cards span %d different kinds" % by_kind.size())
	# A pass that reached for `strike` every time would have written 53 cards and one card.
	ck(widest <= 5, "and the most-repeated kind is %s at %d of %d" % [widest_k, widest, cards.size()])
	# ⛑ `timestop` is the only kind that takes a monster's turn away outright. It must not be
	# earnable in a starter dungeon, whatever its numbers say.
	var early_timestop: Array = []
	for slug in cards.keys():
		if String(cards[slug].get("kind", "")) == "timestop" and int(cards[slug].get("tier", 9)) < 7:
			early_timestop.append("%s at T%d" % [slug, int(cards[slug].get("tier", 0))])
	for e in early_timestop:
		print("           TOO EARLY: " + String(e))
	ck(early_timestop.is_empty(), "timestop is confined to T7+ (%d breaches)" % early_timestop.size())

	print("\n===== 5. THE FACE A PLAYER READS =====")
	var text_bad: Array = []
	for slug in cards.keys():
		var c: Dictionary = cards[slug]
		var nm: String = DT.card_display_name("dungeon_card_" + String(slug))
		var desc: String = String(c.get("desc", ""))
		if nm == "" or nm == "dungeon_card_" + String(slug):
			text_bad.append("%s has no display name" % slug)
		if desc.length() < 40:
			text_bad.append("%s description is %d chars" % [slug, desc.length()])
		# The description must say what the CYCLE does, because that is the half a player cannot
		# see from the card's effect - every one of the four originals does.
		if not ("cycle" in desc.to_lower()):
			text_bad.append("%s never mentions its cycle" % slug)
		if DT.calculate_card_valor("dungeon_card_" + String(slug)) <= 0:
			text_bad.append("%s prices at 0 valor - it would be given away" % slug)
	for t in text_bad:
		print("           TEXT: " + String(t))
	ck(text_bad.is_empty(), "every card names itself, explains its cycle and has a price (%d)" % text_bad.size())

	print("\n===== 6. ALL 53 ACTUALLY CAST =====")
	# ⛑ THE CHECK NONE OF THE ABOVE CAN MAKE. A row can be perfectly formed and still do nothing
	# when played - the arm may need combat state the card does not carry. So every card is cast
	# through the real processor against a real monster, and something has to happen.
	# NOT add_child'd: `real_combat_sim.gd` extends SceneTree, so parenting it errors
	# ("Required object rp_child is null") in every probe that copies that shape. Its `_init`
	# builds `combat_mgr` and `monster_db` regardless, which is all this needs.
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	await process_frame
	var cm = sim.combat_mgr
	var md = sim.monster_db
	var cast_bad: Array = []
	var did := 0
	for slug in cards.keys():
		var card_id := "dungeon_card_" + String(slug)
		var ch = sim.make_char(200, "average", "Fighter", "Human")
		ch.current_hp = ch.get_total_max_hp()
		var mon: Dictionary = md.generate_monster_by_name("Orc", 200, true)
		mon["max_hp"] = 5000000
		mon["current_hp"] = 5000000
		mon["defense"] = 0
		cm.start_combat(0, ch, mon)
		var combat = cm.active_combats[0]
		combat["player_can_act"] = true
		combat["suppress_monster_turn"] = true
		var hp0: int = int(combat.monster.current_hp)
		var res: Dictionary = cm._process_companion_ability(combat, card_id)
		var msgs: Array = res.get("messages", [])
		var moved: bool = int(combat.monster.current_hp) < hp0
		# A pure self-buff deals no damage, so "something happened" is damage OR a change to the
		# combat state the card is meant to write.
		var stateful: bool = int(combat.get("forcefield_shield", 0)) > 0 \
			or int(combat.get("monster_bleed", 0)) > 0 \
			or int(combat.get("monster_weakness", 0)) > 0 \
			or int(combat.get("enemy_distracted", 0)) > 0 \
			or int(combat.get("monster_stunned", 0)) > 0 \
			or int(combat.get("monster_charmed", 0)) > 0 \
			or int(combat.get("card_bonus_valor", 0)) > 0 \
			or float(combat.get("card_loot_mult", 1.0)) > 1.0 \
			or not ch.active_buffs.is_empty()
		if not res.get("success", false):
			cast_bad.append("%s did not succeed" % slug)
		elif msgs.is_empty():
			cast_bad.append("%s said nothing" % slug)
		elif not (moved or stateful):
			cast_bad.append("%s changed nothing (kind %s)" % [slug, cards[slug].get("kind", "")])
		else:
			did += 1
		cm.active_combats.erase(0)
	for b in cast_bad:
		print("           DEAD CARD: " + String(b))
	print("           %d/%d cast and did something" % [did, cards.size()])
	ck(cast_bad.is_empty(), "no dungeon card is a dead card (%d)" % cast_bad.size())

	print("\n===== NOT COVERED HERE =====")
	print("  Whether 53 cards READ well together, or whether any one of them is the obvious")
	print("  best pick at its tier. That is a balance question for the sim and a taste")
	print("  question for the owner - what this proves is that all 53 exist and all 53 work.")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
