extends SceneTree
## ⛑ CAN EVERY CLASS ANSWER AN INCOMING HIT, WHATEVER IT DREW?
##
## Owner 2026-09-19, on a proposal to make boss bursts answerable with cards: *"If they don't draw
## the card they need that round how can they do so?"* The measurement said: often they cannot, and
## three classes never could.
##
##     class                       hard answers in deck   P(one in a 3-card hand)
##     Sage                                           3                     100%
##     Fighter / Sorcerer                             2                      90%
##     Barbarian / Paladin / Wizard                   1                      60%
##     Ninja / Ranger / Grifter                       0                       0%
##
## The whole Trickster archetype holds nothing in `DEFENSIVE_REPRIEVE_ABILITIES`, and combat's
## always-available actions were Attack / Use Item / Flee. So "telegraphed but answerable" would
## have been unanswerable 40% of the time for half the roster and always for a Ninja - unavoidable
## damage with a warning label on it.
##
## BRACE is the floor that fixes it. This probe asserts the three things that make it a floor
## rather than a new best option:
##   1. every class can brace, on any turn, holding any hand
##   2. it actually reduces the incoming hit
##   3. it is STRICTLY WEAKER than spending a card, so the cards still matter
##      (the healer had exactly this failure: an expensive option nobody should ever buy)
##
## Run:
##   godot --headless --path . --script res://tools/probe/every_class_can_answer.gd

const CombatManagerScript := preload("res://shared/combat_manager.gd")
const CharacterScript := preload("res://shared/character.gd")
const MonsterDB := preload("res://shared/monster_database.gd")

const CLASSES := ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage",
	"Grifter", "Ranger", "Ninja"]

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var cm := CombatManagerScript.new()
	var db := MonsterDB.new()

	print("")
	print("===== 1. EVERY CLASS CAN BRACE, WHATEVER IT IS HOLDING =====")
	print("  %-10s %-10s %-8s %s" % ["class", "calls it", "works", "damage reduction"])
	for klass in CLASSES:
		var ch = CharacterScript.new()
		ch.initialize("Probe", String(klass), "Human")
		ch.current_hp = ch.get_total_max_hp()
		# ⛑ TWO THINGS WRONG HERE FIRST TIME, both of which HUNG the probe rather than failing it.
		# `generate_monster` is (min_level, max_level) - passing a role as the second argument
		# coerced it to 0 and gave a 5..0 range. And `CombatManager` has no `monster_db` at all,
		# so the database is built here. A SceneTree script that errors mid-`_init` never reaches
		# `quit()`, so both mistakes presented as a hang, which is the zombie CLAUDE.md warns about.
		var mon: Dictionary = db.generate_monster(5, 5)
		if mon.is_empty():
			_fail("%s - could not build a monster to fight" % klass)
			continue
		cm.start_combat(0, ch, mon)
		if not cm.active_combats.has(0):
			_fail("%s - combat would not start" % klass)
			continue
		# ⛑ TWO SEPARATE QUESTIONS, MEASURED SEPARATELY.
		#
		# ⚡ The first cut asked both at once - `process_combat_command` then read the buff - and
		# reported all nine classes gaining NOTHING. That was the probe, not the game: the command
		# resolves the player's action AND the monster's turn, and a one-round buff has ticked away
		# by the time control returns. It had done its job and expired, which is correct.
		# So: `process_brace` is called directly to see the EFFECT, and the command is sent to see
		# the ROUTING.
		var before: int = ch.get_buff_value("damage_reduction")
		var combat: Dictionary = cm.active_combats[0]
		cm.process_brace(combat)
		var during: int = ch.get_buff_value("damage_reduction")
		var nm := String(CombatManagerScript.brace_name_for(ch))
		var gained: int = during - before
		var routed: bool = bool(cm.process_combat_command(0, "brace").get("success", false))
		print("  %-10s %-10s %-8s %2d%% -> %2d%%" % [klass, nm, str(routed), before, during])
		if not routed:
			_fail("%s cannot brace - the command was refused" % klass)
		# ⛑ THE TEST IS THE FLOOR, NOT THE DELTA - and getting that wrong flagged the Fighter.
		# A Fighter OPENS combat holding `damage_reduction 60` from its Momentum mitigation, and
		# `add_buff` will not lower an existing buff of the same type, so bracing correctly does
		# nothing for a character already better protected than bracing would make it. Asserting
		# "the number went up" called that a failure; asserting "you end up at least braced" is
		# the property that actually matters to a player.
		if during < int(CombatManagerScript.BRACE_DAMAGE_REDUCTION):
			_fail("%s ends a brace on %d%% reduction, below the %d%% floor"
				% [klass, during, int(CombatManagerScript.BRACE_DAMAGE_REDUCTION)])
		cm.active_combats.erase(0)

	print("")
	print("===== 2. THE NAME IS THE ARCHETYPE'S OWN =====")
	# Owner: *"it should probably have different name for Warriors, mages, and tricksters."*
	var seen := {}
	for klass in CLASSES:
		var nm := String(CombatManagerScript.brace_name_for_class(String(klass)))
		seen[nm] = true
	print("  the three words: %s" % str(seen.keys()))
	if seen.size() != 3:
		_fail("expected one name per archetype, got %d distinct name(s): %s" % [seen.size(), str(seen.keys())])
	else:
		_ok("warriors, mages and tricksters each have their own word")
	# ⛑ AND THE CLIENT MUST AGREE WITH THE SERVER. The button reads `class`, the combat log reads
	# the character - two paths to one name, which is the shape behind most wrong-text bugs here.
	for klass in CLASSES:
		var ch2 = CharacterScript.new()
		ch2.initialize("P", String(klass), "Human")
		var by_char := String(CombatManagerScript.brace_name_for(ch2))
		var by_class := String(CombatManagerScript.brace_name_for_class(String(klass)))
		if by_char != by_class:
			_fail("%s: the log says '%s' and the button says '%s'" % [klass, by_char, by_class])
	if _fails.is_empty():
		_ok("the button and the combat log call it the same thing for all nine")

	print("")
	print("===== 3. BRACE IS A FLOOR, NOT THE BEST OPTION =====")
	# ⛑ THE HEALER FAILED EXACTLY HERE - an expensive option nobody should ever buy. If the free
	# action matched a card, every defensive card in the game would become pointless.
	var brace_dr: int = int(CombatManagerScript.BRACE_DAMAGE_REDUCTION)
	# `iron_skin` at a full spend is 60% for four rounds; brace is one round, free, no reprieve.
	var card_dr := 60
	var card_rounds := 4
	print("  brace      %d%% for 1 round, free, no defensive reprieve" % brace_dr)
	print("  iron_skin  %d%% for %d rounds, costs a card and stamina, 40%% reprieve chance"
		% [card_dr, card_rounds])
	if brace_dr >= card_dr:
		_fail("brace (%d%%) is as strong as spending a card (%d%%) - the cards become pointless"
			% [brace_dr, card_dr])
	else:
		_ok("brace is %.0f%% as strong as the card, for one round instead of %d"
			% [100.0 * float(brace_dr) / float(card_dr), card_rounds])
	# It must not earn the reprieve a defensive CARD buys.
	if CombatManagerScript.DEFENSIVE_REPRIEVE_ABILITIES.has("brace"):
		_fail("brace earns the defensive reprieve - that is what spending a card is for")
	else:
		_ok("brace does not earn the defensive reprieve")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every class can answer an incoming hit on any turn, by its own name, and")
	print("       bracing never replaces the card that does it better.")
	quit()
