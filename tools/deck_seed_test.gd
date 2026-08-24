extends SceneTree
# v0.9.697 — verify curated starter decks seed correctly for new characters and
# that an existing (already-seeded) character's deck is left untouched.

func _init():
	var CharacterScript = load("res://shared/character.gd")
	for combo in [["Fighter", "warrior"], ["Wizard", "mage"], ["Thief", "trickster"]]:
		var ch = CharacterScript.new()
		ch.initialize("New_%s" % combo[0], combo[0], "Human")
		var changed = ch.initialize_deck_collection_if_needed()
		var keys: Array = ch.combat_deck_collection.keys()
		keys.sort()
		print("[NEW %s / %s] changed=%s  deck(%d): %s" % [combo[0], combo[1], changed, keys.size(), ", ".join(keys)])

	# Existing character: pretend they already have a full bloated deck; the
	# function must NOT shrink or reseed it.
	var ex = CharacterScript.new()
	ex.initialize("Existing", "Fighter", "Human")
	ex.combat_deck_collection = {"power_strike": 1, "cleave": 1, "berserk": 1, "iron_skin": 1, "fortify": 1, "rally": 1}
	ex.deck_collection_initialized = true
	var ex_changed = ex.initialize_deck_collection_if_needed()
	var ex_keys: Array = ex.combat_deck_collection.keys()
	ex_keys.sort()
	print("[EXISTING Fighter] changed=%s  deck(%d): %s" % [ex_changed, ex_keys.size(), ", ".join(ex_keys)])
	quit()
