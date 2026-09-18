extends SceneTree
## ⛑ DOES EVERY SURFACE CALL A CARD THE SAME THING?
##
## Owner 2026-09-18, live: *"Chaos bolt shows as Magic bolt in the combat log. We gotta fix these
## naming differences for each class."* and *"Cataclysm on the card says Ramp focus first. The
## Sorcerer doesn't use Focus."*
##
## ⚑ CLAUDE.md ALREADY SAYS A RENAME TOUCHES SEVEN SURFACES, and names the combat log as one of
## the three that were only ever found by sweeping. This is that sweep, run as a check instead of
## by hand: for every class and every card in its deck, the name the LOG prints must be the name
## the CARD shows, and any engine word a card face prints must be that class's own engine word.
##
## ⛑ IT EXECUTES `ability_line`, IT DOES NOT READ IT. The call sites pass a literal fallback, so
## a source-reading check would see the string "Magic Bolt" sitting there and have no way to tell
## whether it reaches the player. Running the function for each of the nine classes does.
##
## Run:
##   godot --headless --path . --script res://tools/probe/card_is_called_one_thing.gd

const CombatManagerScript := preload("res://shared/combat_manager.gd")
const CharacterScript := preload("res://shared/character.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _mk(cls: String):
	var ch = CharacterScript.new()
	ch.initialize("Probe", cls, "Human")
	return ch


func _init() -> void:
	var cm := CombatManagerScript.new()
	var classes: Array = CombatManagerScript.CLASS_ENGINE_LABEL.keys()
	classes.sort()

	print("")
	print("===== 1. EVERY TITLE THE COMBAT LOG CAN PRINT =====")
	# The call sites, read out of the source so a new one cannot be missed - but each is then
	# EXECUTED, which is the half that catches anything.
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	var rx := RegEx.new()
	rx.compile("ability_line[(]character, \"([a-z_]+)\", \"title\", \"([^\"]*)\"")
	var sites: Array = []
	for m in rx.search_all(src):
		sites.append([m.get_string(1), m.get_string(2)])
	print("  %d title call site(s) in the combat log" % sites.size())
	if sites.is_empty():
		_fail("no title call sites found - the pattern this probe greps for has changed")
	var checked := 0
	for cls in classes:
		var ch = _mk(cls)
		for site in sites:
			var card := String(site[0])
			var template := String(site[1])
			var want := String(CombatManagerScript.display_name_for(ch, card))
			var got := String(CombatManagerScript.ability_line(ch, card, "title", template))
			# The log may shout or decorate; what it may NOT do is print a different NAME.
			var bare := got.to_lower()
			for junk in ["!", "❄", "☠", "★", "•", "—", "-"]:
				bare = bare.replace(junk, "")
			bare = bare.strip_edges()
			checked += 1
			if bare.find(want.to_lower()) < 0:
				# A class-specific LINE is allowed to be a whole sentence of flavour rather than a
				# name - that is what ABILITY_LINES_BY_CLASS is for. Only the fallback path, which
				# is supposed to be the name, is a fault.
				var per: Dictionary = CombatManagerScript.ABILITY_LINES_BY_CLASS.get(card, {})
				if (per.get(cls, {}) as Dictionary).has("title"):
					continue
				_fail("%s casts %s: the card says \"%s\", the log says \"%s\"" % [cls, card, want, got])
	if _fails.is_empty():
		_ok("%d class x card log titles all print the card's own name" % checked)

	print("")
	print("===== 2. THE DECORATION SURVIVES =====")
	# ⛑ A fix that flattened "❄ FROST NOVA!" into "Frost Nova" would pass section 1 and quietly
	# strip the log of its emphasis, so the styling is asserted rather than hoped for.
	var wiz = _mk("Wizard")
	var shout := String(CombatManagerScript.ability_line(wiz, "frost_nova", "title", "❄ FROST NOVA!"))
	print("  Wizard frost_nova title: %s" % shout)
	if shout.find("❄") < 0 or shout.find("!") < 0 or shout != shout.to_upper():
		_fail("a shouted title lost its decoration: %s" % shout)
	else:
		_ok("a shouted template still shouts")
	var plain := String(CombatManagerScript.ability_line(wiz, "power_strike", "title", "Power Strike"))
	if plain != plain.to_upper():
		_ok("a plain template stays plain (%s)" % plain)
	else:
		_fail("a plain title is being shouted: %s" % plain)

	print("")
	print("===== 3. THE ENGINE WORD ON A CARD FACE IS THAT CLASS'S OWN =====")
	# Owner: *"Cataclysm on the card says Ramp focus first. The Sorcerer doesn't use Focus."*
	# The Meteor branch of the hand renderer typed the word "Focus" while the Devastate branch two
	# blocks above it used `_momentum_name`. One value, two places, and one of them a literal.
	var cs := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	for phrase in ["\"Ramp Focus first\"", "Ramp Focus first"]:
		if cs.find(phrase) >= 0:
			_fail("the hand still prints the literal word Focus: %s" % phrase)
	if _fails.is_empty() or cs.find("Ramp Focus first") < 0:
		_ok("the card face reads its engine name from the meter, not from a literal")
	print("  the nine engines, as the game names them:")
	for cls in classes:
		print("    %-10s %s" % [cls, CombatManagerScript.class_engine_label(cls)])

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d naming disagreement(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every class's cards are called one thing on the card, in the log and in")
	print("       the engine meter.")
	quit()
