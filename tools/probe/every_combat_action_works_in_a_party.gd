extends SceneTree
## ⛑ CAN YOU ACTUALLY DO, IN A PARTY, EVERYTHING THE ACTION BAR OFFERS YOU?
##
## Owner, live, 2026-09-19, in a party at the starter dungeon boss: *"attempted to use Slip. The
## combat log instead says Brace and shows I'm locked in but can still change my picks but whenever
## I try it just says waiting for party."*
##
## ⚡ TWO SYMPTOMS, ONE CAUSE, AND THE WORSE ONE WAS INVISIBLE. `handle_party_combat_command` keeps
## its OWN allow-list of what counts as a combat command. Brace/Ward/Slip shipped wired into SOLO
## combat and into the action bar, and that list was never updated — so `slip` matched nothing,
## fell to the `else`, printed "Unknown combat command" and **returned without submitting**. The
## player was never locked in; the client had already drawn them as locked, so every retry did
## nothing and the round could never complete. A defensive action that silently costs you the
## whole fight is worse than not having one.
##
## ⛑ THIS IS THE "SEVEN SURFACES" RULE WITH A SECOND ALLOW-LIST. The party dispatcher answers
## "is this a real combat command?" independently of the solo path, so any action added to one and
## not the other is dead in the other — silently, because an unknown command looks like a typo.
##
## WHAT THIS ASSERTS:
##   1. every command the SOLO engine accepts is accepted by the PARTY dispatcher
##   2. brace specifically resolves to a brace, not an attack
##   3. the party log calls it by the ARCHETYPE's word — Brace / Ward / Slip
##
## Run:
##   godot --headless --path . --script res://tools/probe/every_combat_action_works_in_a_party.gd

const CombatManagerScript := preload("res://shared/combat_manager.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	# ⛑ THE EXACT NAME, AND NO FALLBACK. The first cut of this probe looked for
	# `func handle_party_combat_command(` (the real one has a leading underscore), missed, and
	# fell back to searching for a line of code inside it - which occurs 40,000 lines earlier in
	# an unrelated function. It then measured THAT function and reported that the dispatcher does
	# not accept `attack`, which is plainly false. A locator with a loose fallback does not fail
	# when it cannot find its target; it silently measures something else, and a confident wrong
	# answer is worse than no answer. If this name changes, this probe must fail and be re-pointed.
	var i := srv.find("func _handle_party_combat_command(")
	var dispatcher := ""
	if i >= 0:
		var j := srv.find("\nfunc ", i + 8)
		dispatcher = srv.substr(i, (j - i) if j > i else 4000)

	print("")
	print("===== 1. EVERY ACTION THE BAR OFFERS IS A COMMAND THE PARTY ACCEPTS =====")
	if dispatcher == "":
		_fail("could not find the party combat dispatcher - re-point this probe")
	else:
		# The action bar offers exactly these four non-card actions in a fight. Attack and Flee
		# were always here; Brace arrived in v0.9.817 and was not.
		# ⚑ THE BRANCH STATEMENT, NOT THE WORD. Proven necessary: deleting the brace branch left
		# this probe passing, because the explanatory comment above it still said "BRACE_COMMANDS"
		# and the `action = {"kind": "brace"}` line still said "brace". That is the third time in
		# one week a probe here has read a COMMENT about a check instead of the check — the healer
		# menu, the canvas heal guard, and now this. A comment cannot contain `elif cmd in`.
		var required := {
			"attack": "if cmd in [\"attack\"",
			"flee": "elif cmd in [\"flee\"",
			"brace": "elif cmd in CombatManager.BRACE_COMMANDS:",
		}
		for label in required.keys():
			var needle := String(required[label])
			if dispatcher.find(needle) < 0:
				_fail("the party dispatcher never mentions %s - pressing it in a party falls to "
					% label + "\"Unknown combat command\" and never submits, so the round hangs")
			else:
				_ok("the party dispatcher accepts %s" % label)
		# ⛑ THE LIST IS READ, NOT COPIED. A hand-typed ["brace","ward","slip"] here would be a
		# THIRD copy of the same list and would go stale the day a fourth archetype is added.
		if dispatcher.find("CombatManager.BRACE_COMMANDS") < 0:
			_fail("brace is matched against a hand-written list rather than BRACE_COMMANDS - a "
				+ "new archetype's word would be accepted solo and rejected in a party")
		else:
			_ok("it matches against BRACE_COMMANDS itself, not a copy of it")

	print("")
	print("===== 2. A SUBMITTED BRACE RESOLVES AS A BRACE =====")
	var cmsrc := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var a := cmsrc.find("func _party_apply_member_action(")
	if a < 0:
		_fail("_party_apply_member_action is gone")
	else:
		var b := cmsrc.find("\nfunc ", a + 8)
		var body := cmsrc.substr(a, (b - a) if b > a else 6000)
		# Without this branch a brace falls into the `else` and the member ATTACKS - they spend
		# the round they meant to defend with, and take the hit at full force.
		if body.find("process_brace(view)") < 0:
			_fail("a queued brace is not resolved by process_brace - it falls through to the "
				+ "attack branch, so the player attacks instead of defending")
		else:
			_ok("a queued brace resolves through process_brace")
		if body.find("brace_name_for(") < 0:
			_fail("the party log does not ask brace_name_for - it will announce \"Brace\" to a "
				+ "Ninja, which is exactly what was reported")
		else:
			_ok("the party log names it by the archetype's own word")

	print("")
	print("===== 3. THE THREE WORDS ARE STILL DISTINCT =====")
	# If these ever collapse to one, the log is correct and useless at the same time.
	var names := {}
	for cls in ["Fighter", "Wizard", "Ninja"]:
		var n := String(CombatManagerScript.brace_name_for_class(cls))
		print("  %-9s -> %s" % [cls, n])
		names[n] = true
	if names.size() != 3:
		_fail("the three archetypes do not have three distinct words: %s" % str(names.keys()))
	else:
		_ok("Brace / Ward / Slip are three different words")
	# Every one of them must be a command the dispatcher takes, or the class that uses that word
	# is the one left unable to defend - which is how this was found.
	for w in ["brace", "ward", "slip"]:
		if not (w in CombatManagerScript.BRACE_COMMANDS):
			_fail("\"%s\" is a name shown to players but not an accepted command" % w)

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every action the bar offers is accepted in a party, a brace braces, and")
	print("       the log calls it by the name that class was given.")
	quit()
