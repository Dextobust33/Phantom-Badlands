extends SceneTree
## The Scroll of Finding must pay out what it offers, and say what it did.
##
## Owner 2026-09-10: picked "Shield Guardian", met "a normal wolf", and only worked out it had
## done anything because a shield turned up in their inventory. Then picked the Warrior option and
## saw nothing at all — because for the three CLASS-GEAR traits there was nothing to see, and the
## drop was a hidden 35% where the other three were guaranteed.
const CM := preload("res://shared/combat_manager.gd")
const SERVER := "res://server/server.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = CM.new()

	print("--- a scroll-granted hoarder is guaranteed; a natural one is not ---")
	ck(abs(cm._hoarder_drop_chance({"scroll_trait_guaranteed": true}) - 1.0) < 0.001,
		"scroll-granted pays out every time")
	ck(abs(cm._hoarder_drop_chance({}) - 0.35) < 0.001,
		"a monster that carries it NATURALLY keeps 35% (the curve is sized against that)")
	ck(abs(cm._hoarder_drop_chance({"scroll_trait_guaranteed": false}) - 0.35) < 0.001,
		"...and an explicit false is still natural")

	print("\n--- every trait the scroll can grant is announced on the encounter ---")
	# The six options the server offers, and the ability constant each maps to.
	var offered := ["weapon_master", "shield_bearer", "gem_bearer",
		"arcane_hoarder", "cunning_prey", "warrior_hoarder"]
	# Confirm the server still offers exactly these, so this list cannot silently drift.
	var srv := FileAccess.get_file_as_string(SERVER)
	for o in offered:
		ck(srv.contains('"%s"' % o), "the scroll still offers '%s'" % o)

	for o in offered:
		var txt: String = cm.generate_encounter_text({
			"name": "Wolf", "level": 5, "max_hp": 10, "current_hp": 10,
			"abilities": [o],
		})
		var plain: String = cm.generate_encounter_text({
			"name": "Wolf", "level": 5, "max_hp": 10, "current_hp": 10, "abilities": [],
		})
		ck(txt != plain, "'%s' changes what the player is shown" % o)

	print("\n--- and the scroll no longer promises to choose your monster ---")
	var cmsrc := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(not cmsrc.contains("choose your next quarry"),
		"the apex drop no longer says 'choose your next quarry' (that is the Scroll of Summoning)")
	ck(srv.contains("guaranteed"), "the picker states the payout is guaranteed")

	print("")
	print("--- the marked monster WEARS the trait in its name ---")
	ck(CM.SCROLL_TRAITS.size() == offered.size(),
		"SCROLL_TRAITS holds exactly the %d offered traits" % offered.size())
	for o in offered:
		ck(CM.SCROLL_TRAITS.has(o), "'%s' is in the canonical table" % o)
		ck(cm.scroll_trait_name(o) != "", "'%s' has a player-facing name" % o)
	ck(cm.scroll_trait_name("regeneration") == "",
		"a NATURAL trait is not a scroll trait, so it never renames anything")
	print("      e.g. weapon_master -> '%s Wolf'" % cm.scroll_trait_name("weapon_master"))

	# The prefix must not break art lookup: the resolver drops leading words to find a species.
	var MA = load("res://client/monster_art.gd")
	for o in offered:
		var prefixed: String = "%s Wolf" % cm.scroll_trait_name(o)
		ck(MA.resolve_art_key(prefixed) == MA.resolve_art_key("Wolf"),
			"'%s' still resolves to the Wolf art" % prefixed)

	ck(srv.contains("CombatManager.SCROLL_TRAITS.keys()"),
		"the scroll picker is DERIVED from the table, not a second copy of the list")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
