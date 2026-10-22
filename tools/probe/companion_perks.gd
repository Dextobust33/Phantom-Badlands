extends SceneTree
## Item 11c (owner 2026-10-22): "inherit one, roll one", companion-sized. An egg made from a TRAITED monster carries two perks (the inherited one first, then one rolled and different); an egg from a plain monster
## carries one rolled perk. The perks are baked into `bonuses`, so a perked companion is stronger on exactly the stat the perk names, and the perks survive egg -> hatched companion -> active companion.
const CP = preload("res://shared/companion_perks.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var DT = load("res://shared/drop_tables.gd").new()
	root.add_child(DT)
	await process_frame
	print("--- the table ---")
	var mapped_ok := true
	var MD = load("res://shared/monster_database.gd")
	for t in CP.TRAIT_PERK:
		if not CP.PERKS.has(String(CP.TRAIT_PERK[t])) or not MD.EMPOWERED_MODIFIERS.has(String(t)):
			mapped_ok = false
	ck(mapped_ok, "every mapped trait is a real modifier and every perk it names exists")
	var all_traits_mapped := true
	for t in MD.EMPOWERED_MODIFIERS:
		if not CP.TRAIT_PERK.has(String(t)):
			all_traits_mapped = false
	ck(all_traits_mapped, "every monster modifier has a companion meaning (no trait leaves the inherited slot empty)")

	print("--- inherit one, roll one ---")
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var traited: Array = CP.roll(["thickhided", "swift"], r)
	ck(traited.size() == 2 and traited[0] == "sturdy" and traited[1] != "sturdy", "a Thick-hided monster's egg inherits Sturdy and rolls a DIFFERENT second perk (%s)" % str(traited))
	var plain: Array = CP.roll([], r)
	ck(plain.size() == 1, "a plain monster's egg has just the one rolled perk (%s)" % str(plain))
	var always_distinct := true
	for i in range(200):
		var p: Array = CP.roll(["giant"], r)
		if p.size() != 2 or p[0] == p[1]:
			always_distinct = false
	ck(always_distinct, "over 200 rolls the two perks are never the same")

	print("--- baked into the bonuses ---")
	var base := {"attack": 10, "aggro": 30}
	var fierce: Dictionary = CP.bake(base, ["fierce"], 3)
	ck(abs(float(fierce["attack"]) - 12.5) < 0.01 and int(fierce["aggro"]) == 30, "Fierce raises attack 10 -> %s and touches nothing else" % str(fierce["attack"]))
	var sturdy: Dictionary = CP.bake(base, ["sturdy"], 3)
	ck(float(sturdy.get("hp_bonus", 0)) >= 6.0 and float(sturdy.get("defense", 0)) >= 3.0, "Sturdy on a companion with no health or defence gives the per-tier floor (hp %s, def %s)" % [str(sturdy.get("hp_bonus")), str(sturdy.get("defense"))])
	ck(int(base["attack"]) == 10, "baking returns a new dictionary: the species table is untouched")

	print("--- an egg, a hatchling, an active companion ---")
	var plain_egg: Dictionary = DT.get_egg_for_monster("Wolf", {}, 1, 0, [])
	var fierce_egg: Dictionary = DT.get_egg_for_monster("Wolf", {}, 1, 0, ["frenzied"])
	ck(plain_egg["perks"].size() == 1 and fierce_egg["perks"].size() == 2 and fierce_egg["perks"][0] == "fierce", "a Wolf egg from a Frenzied monster carries Fierce first (%s), from a plain one just a rolled perk (%s)" % [str(fierce_egg["perks"]), str(plain_egg["perks"])])
	var species: Dictionary = DT.COMPANION_DATA["Wolf"]["bonuses"]
	ck(float(fierce_egg["bonuses"].get("attack", 0)) >= float(species["attack"]) * 1.2, "...and its attack bonus is higher than the species' (%s vs %s)" % [str(fierce_egg["bonuses"].get("attack")), str(species["attack"])])
	var ch = load("res://shared/character.gd").new()
	ch.initialize("Tamer", "Fighter", "Human")
	var hatched: Dictionary = ch._hatch_egg(fierce_egg)
	ck(hatched.get("perks", []) == fierce_egg["perks"], "the hatched companion keeps the perks (%s)" % str(hatched.get("perks")))
	ch.activate_hatched_companion(String(hatched["id"]))
	ck(ch.active_companion.get("perks", []) == fierce_egg["perks"] and float(ch.get_companion_bonus("attack")) > 0.0, "the ACTIVE companion carries them and their bonus reaches combat (attack %.1f)" % float(ch.get_companion_bonus("attack")))
	var src: String = FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.contains("roll_egg_drop(killed_monster_name, _get_monster_tier(killed_monster_level), result.get(\"is_dungeon_combat\", false), killed_monster_empowered_mods)"), "the kill passes the monster's traits to the egg roll")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
