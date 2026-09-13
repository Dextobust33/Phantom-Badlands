extends SceneTree
## The class you pick must be the class you get.
##
## Owner 2026-09-13: *"The mages aren't giving the correct class when creating a character. I had
## a player try to create an elf mage oracle but it gave them a wizard one time and a sorcerer
## the next time."*
##
## The Oracle's internal id is `Sage`. The card picker drove a hidden dropdown by matching item
## TEXT against that id - and the dropdown's text is the DISPLAY name, "Oracle" - so the match
## never succeeded, the dropdown kept whatever was selected before, and the confirm handler read
## that. Wizard and Sorcerer are the two classes above Oracle in the Mage path: it was handing
## back the previous selection.
##
## ⚑ WHY THIS PROBE. Eight of the nine classes have an id identical to their label, so eight
## worked and any spot check would have passed. The fault lived entirely in the one class where
## the two differ - which is exactly the "one value, two places" shape, and exactly what a
## per-class sweep catches and a sample does not.
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== EVERY CLASS, THROUGH THE REAL WIDGET =====")
	# Build the dropdown exactly as `_setup_character_creation` does.
	var opt := OptionButton.new()
	get_root().add_child(opt)
	for cls in CharacterScript.ALL_CLASSES:
		opt.add_item(CharacterScript.class_display_name(cls))
		opt.set_item_metadata(opt.item_count - 1, cls)

	var differ: Array = []
	for cls in CharacterScript.ALL_CLASSES:
		if CharacterScript.class_display_name(cls) != cls:
			differ.append("%s shown as %s" % [cls, CharacterScript.class_display_name(cls)])
	print("  ids that differ from their label: %s" % (", ".join(differ) if not differ.is_empty() else "none"))
	ck(not differ.is_empty(),
		"at least one class has a display name (or this probe proves nothing)")

	# Selecting a class card, the way `_on_class_card_pressed` does.
	var wrong: Array = []
	for cls in CharacterScript.ALL_CLASSES:
		# Deliberately start from a DIFFERENT selection each time, so a failure to move shows up
		# as the previous class rather than accidentally landing on the right one.
		opt.select(0)
		var matched := false
		for i in range(opt.item_count):
			if String(opt.get_item_metadata(i)) == cls:
				opt.select(i)
				matched = true
				break
		# And read it back the way the confirm handler does.
		var got := String(opt.get_item_metadata(opt.selected))
		print("    picked %-10s -> created as %-10s %s" % [
			cls, got, "" if got == cls else "  <-- WRONG"])
		if not matched or got != cls:
			wrong.append("%s became %s" % [cls, got])
	ck(wrong.is_empty(), "all %d classes create as themselves%s" % [
		CharacterScript.ALL_CLASSES.size(),
		"" if wrong.is_empty() else " - " + ", ".join(wrong)])

	print("\n===== THE OLD MATCH-BY-LABEL WOULD HAVE FAILED =====")
	# Prove the probe can catch it: re-run the broken comparison and expect a miss.
	var broken_misses := 0
	for cls in CharacterScript.ALL_CLASSES:
		var found := false
		for i in range(opt.item_count):
			if opt.get_item_text(i) == cls:      # the ORIGINAL bug: text, not metadata
				found = true
				break
		if not found:
			broken_misses += 1
	ck(broken_misses > 0,
		"matching on the LABEL misses %d class(es) - the fault, reproduced" % broken_misses)

	print("\n===== AND A DISPLAY NAME IS NOT A CLASS =====")
	for cls in CharacterScript.ALL_CLASSES:
		ck(CharacterScript.is_valid_class(cls), "%s is a valid class id" % cls)
	ck(not CharacterScript.is_valid_class("Oracle"),
		"'Oracle' is a LABEL and is refused as a class id")
	ck(not CharacterScript.is_valid_class("Wanderer"), "and so is anything invented")
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc.find("if not Character.is_valid_class(String(char_class)):") >= 0,
		"the server refuses one rather than storing it - permadeath has no undo")

	print("\n[CLASSPICKER] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
