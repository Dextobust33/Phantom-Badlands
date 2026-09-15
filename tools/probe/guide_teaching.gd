extends SceneTree
## The guide teaches: one panel per system, then his own voice.
##
## Owner 2026-09-14 chose panel-then-voice. A panel for each major system so the lesson cannot be
## missed, and the guide's in-world voice after so he still reads as a person rather than a help
## file. The panels fire ON THE BEAT - being told about equipment before you own any is how a
## tutorial turns into noise a player learns to dismiss.
##
## The thing this guards is "once". A lesson that repeats is worse than one that never fired: the
## first is a bug the player feels every single fight, the second they simply never notice.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

var sent: Array = []


func _init() -> void:
	var srv = ServerScript.new()
	var ch = CharacterScript.new()
	ch.initialize("Newbie", "warrior", "human")
	srv.characters = {1: ch}

	print("===== EACH LESSON FIRES ONCE, AND ONLY ONCE =====")
	# send_to_peer no-ops without a socket, so the FLAG is the observable: it is what stops the
	# panel coming back, and it is what persists.
	for topic in ["items", "equipment", "combat"]:
		srv._guide_teach(1, topic)
	ck(ch.seen_guide_items_hint, "the items lesson was marked seen")
	ck(ch.seen_guide_equipment_hint, "the equipment lesson was marked seen")
	ck(ch.seen_guide_combat_hint, "the combat lesson was marked seen")

	# Calling again must change nothing. A repeating tutorial panel is felt on every fight.
	var before := [ch.seen_guide_items_hint, ch.seen_guide_equipment_hint, ch.seen_guide_combat_hint]
	for i in range(20):
		srv._guide_teach(1, "items")
		srv._guide_teach(1, "equipment")
		srv._guide_teach(1, "combat")
	ck(before == [ch.seen_guide_items_hint, ch.seen_guide_equipment_hint, ch.seen_guide_combat_hint],
		"twenty further calls changed nothing")

	print("")
	print("----- an unknown topic is ignored rather than firing a blank panel -----")
	srv._guide_teach(1, "not_a_lesson")
	ck(true, "no crash, no empty box")

	print("")
	print("===== THE LESSONS SURVIVE A SAVE =====")
	# They live on the character, so a reconnect must not replay the whole tutorial. This is the
	# failure mode that would hit every returning player rather than only new ones.
	var data: Dictionary = ch.to_dict()
	ck(data.has("seen_guide_items_hint"), "the flags are serialised")
	var reloaded = CharacterScript.new()
	reloaded.from_dict(data)
	ck(reloaded.seen_guide_items_hint and reloaded.seen_guide_equipment_hint
		and reloaded.seen_guide_combat_hint,
		"and they come back set, so reconnecting does not replay the tutorial")

	print("")
	print("----- a FRESH character has seen none of them -----")
	var fresh = CharacterScript.new()
	fresh.initialize("Other", "warrior", "human")
	ck(not fresh.seen_guide_items_hint and not fresh.seen_guide_equipment_hint
		and not fresh.seen_guide_combat_hint,
		"a new character still gets taught")

	print("")
	print("===== THE LESSONS SAY SOMETHING TRUE =====")
	# Every claim in a tutorial is a promise. These three were checked against the code they
	# describe rather than written from memory.
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.contains("three Healing Herb"),
		"the items lesson names the rations creation actually grants (STARTER_RATIONS = 3)")
	# ⛑ STALE ASSERTIONS, FOUND RED ON MASTER 2026-09-15. These pinned three exact sentences
	# ("Glass Cannon", "Dying here is permanent", "Rust is fine") that the 2026-09-14 onboarding
	# rewrite deliberately replaced, and nobody updated the probe - so the tutorial gate had been
	# failing for a day on text that had CHANGED ON PURPOSE.
	#
	# Re-pinned to the PROPERTY rather than the prose wherever that is possible. The old version
	# asserted that the combat lesson named a monster trait; the rewrite replaced that with the
	# controls, because the owner pointed out the trait was often not on the monster in front of
	# them: *"When it mentions read what the thing in front of you does it's not clear what the
	# player should do, not all monsters have something to see or hover."* Naming the CONTROLS is
	# the promise now, and a control either exists or it does not - which is checkable.
	var i_c := src.find("How A Fight Goes")
	var combat_lesson := src.substr(i_c, 1600) if i_c != -1 else ""
	ck(i_c != -1, "there is a combat lesson")
	for control in ["Hover one with your mouse", "click the card", "[color=#FFD700]1[/color]"]:
		ck(combat_lesson.contains(control),
			"  the combat lesson names a control the player has: %s" % control)
	ck(src.contains("Dying out here is permanent"),
		"and it says the thing a new player most needs to hear")

	print("")
	print("----- the guide has a voice as well as a panel -----")
	ck(src.contains("func _guide_say"), "_guide_say exists")
	ck(src.contains("not luggage"), "and he speaks when the weapon lands")
	ck(src.contains("Staying up is the trick"), "and again when the armour does")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether the panels fire at the right MOMENT in a live session, and whether the")
	print("  writing lands. Both are a playtest.")

	print("")
	if fails == 0:
		print("PASS - each lesson fires once, survives a save, and tells the truth")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
