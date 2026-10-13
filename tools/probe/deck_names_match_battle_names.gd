extends SceneTree
## Owner sheet 2026-10-13, item 39: "Cards are showing different names on the Deck screen than they do in
## battle (Sorcerer ... Blast on Deck)". The Deck panel reads `ability_data.all_abilities[].display`; battle
## names a card through CombatManager.display_name_for. For every class and every card the class can hold,
## the name the server SENDS the Deck must equal the name battle USES.
const CM := preload("res://shared/combat_manager.gd")
const CharacterScript := preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var srv = load("res://server/server.gd").new()
	var checked := 0
	var renamed := 0
	var bad: Array = []
	for cls in ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]:
		var ch = CharacterScript.new()
		ch.initialize("P_" + cls, cls, "Human")
		ch.level = 500
		for list in [ch.get_all_available_abilities(), ch.get_unlocked_abilities()]:
			for ab in srv._class_named_abilities(ch, list):
				if not (ab is Dictionary) or bool(ab.get("non_combat", false)):
					continue
				var id := String(ab.get("name", ""))
				var want: String = CM.display_name_for(ch, id)
				var per = CM.ABILITY_DISPLAY_BY_CLASS.get(String(CharacterScript.card_base(id)), null)
				if per is Dictionary and String((per as Dictionary).get(cls, "")) != "":
					checked += 1
					if String(ab.get("display", "")) == want:
						renamed += 1
					else:
						bad.append("%s %s: deck says '%s', battle says '%s'" % [cls, id, ab.get("display", ""), want])
	for b in bad:
		print("      " + b)
	ck(checked >= 20, "checked %d class-renamed cards across the nine classes" % checked)
	ck(bad.is_empty(), "every class-renamed card shows its battle name on the Deck (%d of %d)" % [renamed, checked])
	var sorc = CharacterScript.new()
	sorc.initialize("S", "Sorcerer", "Human")
	sorc.level = 500
	var seen := ""
	for ab in srv._class_named_abilities(sorc, sorc.get_all_available_abilities()):
		if String(ab.get("name", "")) == "blast":
			seen = String(ab.get("display", ""))
	ck(seen == "Wild Surge", "the owner's case: a Sorcerer's blast reads 'Wild Surge' on the Deck (got '%s')" % seen)
	print("\n[DECKNAMES] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
