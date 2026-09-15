extends SceneTree
## Does the Ninja's finisher tell the truth about BOTH things it does?
##
## Owner 2026-09-15: *"Assassinate doesn't mention how much damage it will do if it doesn't kill
## on the card."*
##
## Chasing that turned up a bigger fault behind it. The card was not merely missing a number - it
## was printing a kill chance the game has never rolled against.
##
## ⛑ TWO COPIES OF ONE VALUE, THIRTEEN POINTS APART.
##
## `assassinate_chance` carries a docstring promising it is "the SINGLE source for Assassinate
## success odds, so the real roll, the live number on the card face and Analyze's report can
## never disagree". It was not: the 2026-09-08 rework that turned the finisher into "a strike
## that always lands, plus a chance it ends them" wrote its odds as new constants at the ROLL
## site and left `assassinate_chance` computing the odds of the retired instant-win card.
##
##     read   shown   rolled
##        1     18%      5%
##        4     27%     14%
##        8     39%     26%
##
## And the roll never read `assassinate_pct`, so Silver Tongue (+15%) and the unique that grants
## +20% moved the card and did nothing to the dice - two pieces of content whose text promised an
## effect the game did not apply.
##
## THE FIX IS STRUCTURAL, not a third copy kept in step by hand: `assassinate_chance` now holds
## the lethal formula and the roll site calls it. The checks below therefore test the SHAPE (one
## definition, one reader) as well as the numbers, because numbers that agree today are exactly
## what this function had a week ago.

const CM = preload("res://shared/combat_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")

	print("===== THE ROLL DOES NOT OWN A SECOND COPY OF THE ODDS =====")
	var i := src.find("--- NINJA: the gamble")
	var nj := src.substr(i, 2000) if i != -1 else ""
	ck(i != -1, "the Ninja branch is where it was")
	ck(nj.contains("assassinate_chance(character, monster, combat, variable_fraction)"),
		"and it ASKS the single source for its odds")
	ck(not nj.contains("mini(90, NINJA_LETHAL_BASE + _nj_read * NINJA_LETHAL_PER_READ)"),
		"  its private copy of the formula is gone")

	print("")
	print("===== ...AND THE SINGLE SOURCE COMPUTES THE ODDS PLAYERS ACTUALLY FACE =====")
	var a := src.find("func assassinate_chance")
	var a_end := src.find("\nfunc ", a + 10)
	var fn := src.substr(a, (a_end - a) if a_end > a else 3000)
	ck(fn.contains("NINJA_LETHAL_BASE + read * NINJA_LETHAL_PER_READ"),
		"it uses the LETHAL constants, not the retired instant-win ones")
	ck(not fn.contains("READ_HEIST_PER") and not fn.contains("READ_CAP_PER"),
		"  and no longer uses the constants of the card that was removed")
	ck(fn.contains('get_path_effect_total("assassinate_pct")'),
		"  Silver Tongue and the uniques still count - and now they count for the DICE too")
	ck(fn.contains("variable_fraction"), "  and a partial energy commit still scales it")

	print("")
	print("----- the numbers themselves, computed rather than asserted from memory -----")
	# Executed against the real function so the table cannot go stale the way the comment it
	# replaces did. A fake monster is enough: the formula reads only its level.
	var cm = CM.new()
	var ch = _make_char()
	if ch == null:
		print("  SKIP  could not build a Character - formula table not checked")
	else:
		var mon := {"level": int(ch.level), "intelligence": 15}
		print("  read   kill chance")
		var prev := -1
		var rising := true
		for r in range(0, 9):
			var pct: int = cm.assassinate_chance(ch, mon, {"combo": r})
			print("  %4d   %6d%%" % [r, pct])
			if pct < prev:
				rising = false
			prev = pct
		ck(rising, "the chance rises with every Read banked")
		ck(cm.assassinate_chance(ch, mon, {"combo": 8}) <= 30,
			"  a full stall is ~26%, not the ~39% the card used to advertise")
		ck(cm.assassinate_chance(ch, mon, {"combo": 0}) <= 5,
			"  and opening cold is still a poor play")
		# The level penalty must bite, or "punching above your weight" costs nothing.
		var hard := {"level": int(ch.level) + 10, "intelligence": 15}
		ck(cm.assassinate_chance(ch, hard, {"combo": 8})
			< cm.assassinate_chance(ch, mon, {"combo": 8}),
			"  and a monster ten levels up is harder to finish")

	print("")
	print("===== THE CARD SHOWS THE DAMAGE, WHICH IS THE PART THAT IS CERTAIN =====")
	ck(src.contains("func _finisher_damage"),
		"there is a damage figure for EVERY Trickster finisher, including the one that rolls")
	ck(src.contains('"finisher_damage": _finisher_damage(character, combat)'),
		"and the server ships it with the combat state")
	var d := src.find("func _finisher_damage")
	var d_end := src.find("\nfunc ", d + 10)
	var dfn := src.substr(d, (d_end - d) if d_end > d else 2500)
	ck(dfn.contains("NINJA_STRIKE_PER_READ"), "  the Ninja's is its real strike coefficient")
	# The guaranteed classes must READ this rather than keep their own copy, or the same
	# two-copies fault grows back on the other side.
	var v := src.find("func _finisher_value")
	var v_end := src.find("\nfunc ", v + 10)
	var vfn := src.substr(v, (v_end - v) if v_end > v else 2500)
	ck(vfn.contains("_finisher_damage(character, combat)"),
		"  and the guaranteed finishers read their damage off the same function")

	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(csrc.contains('"~%d · %d%% kill" % [strike, chance]'),
		"the card face prints BOTH the strike and the kill chance")
	ck(csrc.contains("_combat_finisher_damage = int(state.get(\"finisher_damage\", 0))"),
		"  reading the server's number, never its own")
	# "~N" is what `_ability_card_estimate` parses for the bottom-left damage pip, so printing
	# the damage FIRST also gives Assassinate the pip every other damage card has.
	ck(csrc.find('"~%d · %d%% kill"') != -1,
		"  damage first, so the bottom-left pip finds it like any other damage card")

	print("")
	print("===== AND SO DOES EVERY OTHER SURFACE THAT STATES IT =====")
	# A rename touches seven surfaces; so does a fact. These are the ones that state this one.
	ck(src.contains('"%s ~%s / %d%%"'),
		"the Read meter's note carries the damage as well as the odds")
	ck(csrc.contains("A strike that ALWAYS lands"),
		"the long ability description leads with the guaranteed half")
	ck(not csrc.contains("Instant-win attempt. 15% base"),
		"  and the stale instant-win wording is gone")
	ck(csrc.contains("[b]Guaranteed[/b] damage that scales with the"),
		"the short card description says it too")
	# Analyze reports the same figure because it already calls the single source - asserted so a
	# future edit cannot quietly give it a copy again.
	ck(src.contains("assassinate_chance(character, monster, combat), level_warning"),
		"and Analyze reports the same number, from the same function")

	print("")
	print("===== NOT COVERED HERE =====")
	print("  Whether ~26% at a full stall is the RIGHT number. It is unchanged - this fixed what")
	print("  the game SAYS, not what it rolls - but the two +assassinate_pct sources now reach")
	print("  the dice for the first time, which is a small, per-class power gain.")

	print("")
	if fails == 0:
		print("PASS - one formula, and the card states both halves of what the card does")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)


func _make_char():
	"""A level-10 Ninja, or null if the Character script cannot be built headless."""
	var cs = load("res://shared/character.gd")
	if cs == null:
		return null
	var c = cs.new()
	c.name = "Probe"
	c.class_type = "Ninja"
	c.level = 10
	return c
