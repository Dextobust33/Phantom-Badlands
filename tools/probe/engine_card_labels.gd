extends SceneTree

## Does the CARD FACE name each class's engine correctly, for all nine?
##
## Owner 2026-09-09: *"Ensure the cards and meters are reading correctly per class. Each path now
## has one of each type for their classes. Warriors are no longer all momentum, etc."*
##
## `-- enginenames` already covers the meter, the combat log and the label plumbing. It does NOT
## cover the card face, and that gap is not theoretical: on 2026-09-09 the mage branch of the card
## face reached for the TRICKSTER's label variable and a Wizard's Blast printed "+◈ Read". It
## compiled, and enginenames passed, because the meter was right.
##
## So this drives the real panel: it calls the same three update functions client.gd calls, with
## the label the SERVER computes for that class, and reads back the name the card face would use.

func _init() -> void:
	var Panel = load("res://client/combat_scene_panel.gd")
	var CM = load("res://shared/combat_manager.gd")
	var CH = load("res://shared/character.gd")
	var PATH_OF := {
		"Fighter": "warrior", "Barbarian": "warrior", "Paladin": "warrior",
		"Wizard": "mage", "Sorcerer": "mage", "Sage": "mage",
		"Grifter": "trickster", "Ranger": "trickster", "Ninja": "trickster",
	}
	var bad := 0
	print("%-11s %-10s %-12s %s" % ["class", "path", "want", "card face says"])
	print("------------------------------------------------------------")
	for klass in PATH_OF.keys():
		var path: String = PATH_OF[klass]
		var want: String = CM.class_engine_label(klass)
		var p = Panel.new()
		# Exactly what client.gd does on a combat_state: every meter is updated each tick, and
		# only the one matching this class is flagged active. Calling all three is the point -
		# it is how a setter writing another archetype's slot would show up.
		p.update_momentum(1, 5, path == "warrior", want if path == "warrior" else "Momentum", "Devastate")
		p.update_read(1, 8, 40, path == "trickster", want if path == "trickster" else "Read", "")
		p.update_focus(1, 5, path == "mage", want if path == "mage" else "Focus", "")
		var got := String(p._engine_label_by_arch.get(path, ""))
		var flag := ""
		if got != want:
			flag = "   <-- WRONG"
			bad += 1
		print("%-11s %-10s %-12s %s%s" % [klass, path, want, got, flag])
		p.free()
	# --- the SERVER must put the label in the slot that matches the class's archetype ---
	#
	# `-- enginenames` reads the first non-empty of momentum_label / read_label / focus_label, so
	# it would still pass if a Paladin's "Conviction" arrived in `focus_label`. The client keys
	# off the SLOT to decide which archetype it belongs to, so a wrong slot puts the right name
	# on the wrong engine - and every card face for that class with it.
	var CMgr = CM.new()
	var SLOT_OF := {"warrior": "momentum_label", "trickster": "read_label", "mage": "focus_label"}
	print("")
	for klass2 in PATH_OF.keys():
		var path2: String = PATH_OF[klass2]
		var want2: String = CM.class_engine_label(klass2)
		var ch = CH.new()
		ch.name = "probe"
		ch.class_type = klass2
		ch.level = 20
		ch.initialize_deck_collection_if_needed()
		var mon = {"name": "Probe Dummy", "current_hp": 9999, "max_hp": 9999,
			"level": 20, "strength": 10, "defense": 10, "abilities": []}
		CMgr.start_combat(0, ch, mon)
		var d: Dictionary = CMgr.get_combat_display(0)
		var slot: String = SLOT_OF[path2]
		var in_slot := String(d.get(slot, ""))
		if in_slot != want2:
			print("[ENGINECARD] %s: expected '%s' in %s, got '%s'"
				% [klass2, want2, slot, in_slot])
			bad += 1
		# NOT checked: that the other two slots are empty. They are not, and that is DELIBERATE -
		# all three are `class_engine_label(class_type)`, the same value, and the client decides
		# which meter is live from the is_warrior / is_trickster / is_mage flags rather than from
		# which slot is populated. A first version of this probe asserted emptiness and reported
		# 12 failures across 6 classes, all of them a rule I had invented rather than measured.
		CMgr.active_combats.erase(0)

	# --- and the half the table cannot prove ---
	#
	# The check above executes the SETTERS and reads the table, which is the right test for "does
	# each class store its own name". It cannot see what the card face then DOES with it: a first
	# version of this probe passed while a deliberately re-injected "mage reads the Trickster's
	# variable" bug was live, because that bug sits downstream of the table. A detector that
	# cannot catch the fault it exists for is worse than none.
	#
	# Driving the real render path needs a live `client_ref` and a built node tree, which is more
	# scaffolding than this earns. So the RULE is enforced on the source instead - the same
	# treatment `verify_dungeon_art.gd` gives "never `color=` a floor-backed sprite". The card
	# face must take the engine name from the archetype-keyed table and from nothing else.
	var src := FileAccess.get_file_as_string("res://client/combat_scene_panel.gd")
	var lines := src.split("
")
	var in_face := false
	for i in range(lines.size()):
		var ln: String = lines[i]
		if ln.find("var _eng_on :=") >= 0:
			in_face = true
		elif in_face and ln.begins_with("		# v0.9.696"):
			in_face = false
		if not in_face:
			continue
		if ln.find("_label =") < 0 and ln.find("_label :=") < 0:
			continue
		if ln.find("_engine_label_by_arch") >= 0:
			continue
		print("[ENGINECARD] card face sets the engine name from something other than the table:")
		print("             combat_scene_panel.gd:%d  %s" % [i + 1, ln.strip_edges()])
		bad += 1

	print("")
	if bad == 0:
		print("[ENGINECARD] PASS - all 9 classes name their own engine on the card face.")
	else:
		print("[ENGINECARD] FAIL - %d class(es) show the wrong engine name on their cards." % bad)
	quit(0 if bad == 0 else 1)
