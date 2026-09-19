extends SceneTree
## ⛑ IS THE SIMULATED PLAYER HOLDING THE CARDS A REAL PLAYER HOLDS?
##
## Owner 2026-09-18, mid-balance-pass: *"are we sure the sim is using the actual starting decks
## each class is using?"*
##
## ⚑ THE RIGHT QUESTION AT THE RIGHT TIME. The whole chain sizes monsters against a REFERENCE
## PLAYER. If that player is holding a different hand from the one a real character is dealt, every
## monster in the game is sized against somebody who does not exist - and nothing else in the
## chain can detect it, because the chain measures the reference player against itself.
##
## ⛑ IT EXECUTES THE FIGHT, IT DOES NOT READ THE TABLE. `make_char` never calls
## `initialize_deck_collection_if_needed` itself; the deck is seeded deep inside
## `combat_manager._initialize_combat_deck`, which `start_combat` calls. So the only honest way to
## ask what the simulated player is holding is to start a real combat and look at
## `combat_state.combat_deck`. Reading CURATED_STARTER_DECKS_BY_CLASS would only prove the table
## exists.
##
## WHAT IT CHECKS, per class:
##   1. the deck a FIGHT deals from == that class's curated starter deck
##   2. no card is missing, none is extra, and the size is exactly 5 (+ a loaner if a companion)
##   3. the LOANER COMPANION CARD is reported separately - it is a real card a real player with a
##      hatched companion holds, but a brand-new character has an EGG, not a companion, so its
##      presence at L1 is a statement about the player model rather than about the deck
##
## Run:
##   godot --headless --path . --script res://tools/probe/sim_plays_the_real_deck.gd

const SimScript := preload("res://tools/combat_simulator/real_combat_sim.gd")
const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


## The base card ids in the deck a real fight would deal from, plus anything unexpected.
func _deck_of(sim, klass: String, level: int, gear: String) -> Dictionary:
	var ch = sim.make_char(level, gear, klass, "Human")
	ch.in_combat = false
	ch.current_hp = ch.get_total_max_hp()
	var mon = sim.make_monster(level, "normal", 1.0)
	sim.combat_mgr.start_combat(0, ch, mon)
	if not sim.combat_mgr.active_combats.has(0):
		return {}
	var combat = sim.combat_mgr.active_combats[0]
	var bases: Array = []
	var loaners: Array = []
	# ⛑ ALL THREE PILES. The first cut of this probe read `combat_deck` alone and reported
	# every class dealing from TWO cards - which is 5 minus the 3-card opening hand.
	# `start_combat` builds the deck and then immediately draws to hand, so the draw pile is
	# never the deck. Measuring the wrong container is the instrument-defect shape CLAUDE.md
	# names, and it nearly became a nine-class false alarm.
	var all_iids: Array = []
	for pile in ["combat_deck", "combat_hand", "combat_discard"]:
		for _i in combat.get(pile, []):
			all_iids.append(_i)
	for iid in all_iids:
		var b := String(CharacterScript.card_base(String(iid)))
		if b.begins_with("companion_card_"):
			loaners.append(b)
		else:
			bases.append(b)
	bases.sort()
	loaners.sort()
	sim.combat_mgr.end_combat(0, false, false)
	sim.combat_mgr.active_combats.erase(0)
	return {
		"bases": bases,
		"loaners": loaners,
		"has_companion": ch.has_active_companion(),
		"hp": ch.get_total_max_hp(),
	}


func _init() -> void:
	var sim = SimScript.new()

	print("")
	print("===== 1. THE DECK A SIMULATED FIGHT DEALS FROM, AT LEVEL 1 =====")
	print("  (gear='average' - the model `_fight_stats_at` uses, which is what WRITES the curve)")
	print("")
	print("  %-10s %-7s %s" % ["class", "cards", "deck as dealt"])
	var classes: Array = []
	for row in sim.ALL_CLASSES:
		classes.append(String(row[0]))
	classes.sort()

	for klass in classes:
		var got: Dictionary = _deck_of(sim, klass, 1, "average")
		if got.is_empty():
			_fail("%s - combat would not start" % klass)
			continue
		var bases: Array = got["bases"]
		var curated: Array = CharacterScript.CURATED_STARTER_DECKS_BY_CLASS.get(klass, []).duplicate()
		curated.sort()
		var extra: Array = []
		var missing: Array = []
		for c in bases:
			if not (c in curated):
				extra.append(c)
		for c in curated:
			if not (c in bases):
				missing.append(c)
		var loan := ""
		if not (got["loaners"] as Array).is_empty():
			loan = "  +loaner %s" % str(got["loaners"])
		print("  %-10s %-7d %s%s" % [klass, bases.size(), str(bases), loan])
		if curated.is_empty():
			_fail("%s has no curated starter deck at all - it falls back to 'everything accessible'" % klass)
			continue
		if not missing.is_empty():
			_fail("%s is MISSING %s - the sim plays a hand the real class does not" % [klass, str(missing)])
		if not extra.is_empty():
			_fail("%s carries EXTRA %s that a new character does not own" % [klass, str(extra)])
		if bases.size() != 5:
			_fail("%s deals from %d non-companion cards, not 5" % [klass, bases.size()])

	print("")
	print("===== 2. DOES THE REFERENCE PLAYER HOLD A LOANER A NEW CHARACTER CANNOT? =====")
	# ⛑ NOT A DECK FAULT - A PLAYER-MODEL ONE, and worth separating. `_initialize_combat_deck`
	# injects a companion's temporary card when the character HAS a hatched companion. That is
	# correct behaviour. The question is whether the reference player should have one at level 1:
	# a character created today starts with an EGG, and the companion card only exists once it
	# hatches. If the curve is fitted against an L1 player who already has a companion, monsters
	# are sized for a player the live server does not have yet.
	var withcomp := 0
	var total := 0
	for klass in classes:
		var got: Dictionary = _deck_of(sim, klass, 1, "average")
		if got.is_empty():
			continue
		total += 1
		if bool(got["has_companion"]):
			withcomp += 1
	print("  %d of %d level-1 reference players have a LIVE companion" % [withcomp, total])
	if withcomp > 0:
		print("  NOTE: a character created today starts with an unhatched EGG. This is a statement")
		print("        about the player model, not about the deck - reported, not failed here.")

	print("")
	print("===== 3. THE SAME CHECK AT LEVEL 10 =====")
	# A level-10 character has had rank-ups and may legitimately own more than five cards, so this
	# half only asserts that every CURATED card is still present - never that nothing was added.
	for klass in classes:
		var got: Dictionary = _deck_of(sim, klass, 10, "average")
		if got.is_empty():
			continue
		var bases: Array = got["bases"]
		var curated: Array = CharacterScript.CURATED_STARTER_DECKS_BY_CLASS.get(klass, [])
		var missing: Array = []
		for c in curated:
			if not (c in bases):
				missing.append(c)
		print("  %-10s %d cards%s" % [klass, bases.size(),
			("   MISSING %s" % str(missing)) if not missing.is_empty() else ""])
		if not missing.is_empty():
			_fail("L10 %s lost curated card(s) %s" % [klass, str(missing)])

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every simulated class deals from exactly its own curated starter deck.")
	quit()
