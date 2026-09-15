extends SceneTree
## Does a thing lying on a dungeon floor look like the thing it is?
##
## Owner 2026-09-15, walking the starter dungeon: *"most floor loot equipment looks like a shield,
## one of the scrolls looks like a potion. We should have plenty of equipment sprites to use more
## appropriate ones based on the item."*
##
## Both were literally true. The floor picked its sprite from `kind`, which is a GAMEPLAY bucket:
## every helm, blade, ring and pair of boots in the game is `equipment`, and `equipment.png` is a
## picture of a shield. Every potion, tome, charm and scroll is `consumable`, and `consumable.png`
## is a picture of a potion. Two images doing the work of a wardrobe.
##
## ⛑ AND IT IS THE SAME MISTAKE `gearsources` MADE - THE WRONG UNIT.
##
## CLAUDE.md records it: an audit written around the wrong unit is as wrong as a guess and far
## more convincing. So this probe does not enumerate the table. It GENERATES real items through
## the real drop tables, hands each one to the real resolver, and asserts the sprite it names
## loads - which is the same discipline `verify_dungeon_art.gd` learned from the `.png.png` bug:
## when you write a lookup table, the check is CALLING the lookup.

const DS = preload("res://client/dungeon_sprites.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sv = load("res://server/server.gd").new()
	var dt = load("res://shared/drop_tables.gd").new()

	print("===== THE OLD BEHAVIOUR, STATED SO IT CANNOT COME BACK QUIETLY =====")
	# Not a regression test on the picture itself - it is a picture, and asserting its pixels
	# would fail on any art change. What matters is that gear no longer RESOLVES to it.
	ck(DS.loot_path("equipment") != "", "the category fallbacks still exist (and must)")
	ck(DS.loot_path("consumable") != "", "  both of them")

	print("")
	print("===== EVERY EQUIPMENT SLOT GETS ITS OWN PICTURE =====")
	# Generated, not hand-written: these are real items off the real starter-kit generator, which
	# is exactly what the starter dungeon scatters on its floors.
	var seen := {}
	for slot in ["weapon", "helm", "boots", "shield", "accessory"]:
		var it: Dictionary = dt.get_starter_kit_item(String(slot))
		if it.is_empty():
			ck(false, "starter kit '%s' generated nothing" % slot)
			continue
		var art: String = sv._floor_loot_art({"item_data": it})
		var path: String = DS.loot_path_for(art, "equipment")
		ck(art != "", "%-10s -> art '%s'" % [String(it.get("name", slot)), art])
		ck(path != "" and ResourceLoader.exists(path), "  and %s loads" % path)
		ck(path != DS.loot_path("equipment"),
			"  and it is NOT the old one-shield-fits-all picture")
		seen[art] = String(it.get("name", slot))

	print("")
	print("----- and the slots the starter kit does not cover -----")
	# armor and amulet have no starter-kit entry, so they are probed through the type->slot
	# function the resolver actually uses rather than skipped.
	for pair in [["armor_plate", "eq_armor"], ["amulet_bronze", "eq_amulet"],
			["ring_copper", "eq_ring"], ["weapon_iron", "eq_weapon"]]:
		var art: String = sv._floor_loot_art({"item_data": {"item_type": String(pair[0])}})
		ck(art == String(pair[1]), "%-14s -> %s" % [String(pair[0]), art])
		ck(ResourceLoader.exists(DS.loot_path(art)), "  and its sprite loads")
		seen[art] = String(pair[0])

	print("")
	print("===== AND THEY ARE ALL DIFFERENT PICTURES =====")
	# The whole complaint was "they all look the same". Distinct keys is the checkable half;
	# whether the ART reads distinctly at 32px is a look, and is listed as uncovered below.
	var paths := {}
	var collide: Array = []
	for a in seen:
		var p: String = DS.loot_path(String(a))
		if paths.has(p):
			collide.append("%s and %s share %s" % [a, paths[p], p])
		paths[p] = a
	ck(collide.is_empty(), "no two slots resolve to the same sprite (%s)" % str(collide))

	print("")
	print("===== A SCROLL IS NOT A POTION =====")
	for pair in [["scroll_fire", "cn_scroll"], ["potion_health", "cn_potion"],
			["mana_potion", "cn_potion"], ["tome_strength", "cn_tome"],
			["ability_tome", "cn_tome"], ["floor_skip_charm", "cn_charm"],
			["gem_ruby", "cn_gem"], ["gold_pouch", "cn_pouch"],
			["home_stone_basic", "cn_stone"], ["travel_stone", "cn_stone"]]:
		var art: String = sv._floor_loot_art({"item_data": {"item_type": String(pair[0])}})
		ck(art == String(pair[1]), "%-18s -> %s" % [String(pair[0]), art])
		if art != "":
			ck(ResourceLoader.exists(DS.loot_path(art)), "  and its sprite loads")
	ck(DS.loot_path("cn_scroll") != DS.loot_path("cn_potion"),
		"and the two the owner named are genuinely different files")

	print("")
	print("===== AN ITEM THE TABLE HAS NEVER HEARD OF STILL DRAWS SOMETHING =====")
	# The fallback is the point of `loot_path_for`. Without it, this pass would have traded one
	# wrong picture for a bare glyph, which is worse.
	var unknown: String = sv._floor_loot_art({"item_data": {"item_type": "brand_new_widget"}})
	ck(unknown == "", "an unrecognised type yields no art key")
	ck(DS.loot_path_for(unknown, "consumable") == DS.loot_path("consumable"),
		"  and falls back to its gameplay category rather than to nothing")
	ck(DS.loot_path_for("", "") == "", "  while a genuinely empty pair still yields nothing")

	print("")
	print("===== THE SERVER ACTUALLY SENDS IT =====")
	# A resolver nothing calls is a no-op that reads as a feature - the shape CLAUDE.md warns
	# about, and one I shipped earlier today in the escort.
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	ck(ssrc.contains('"art": _floor_loot_art(it),'),
		"the floor-item payload carries the art key")
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	ck(csrc.contains("_DungeonSprites.loot_path_for("),
		"and the dungeon renderer reads it")

	print("")
	print("===== NOT COVERED HERE =====")
	print("  Whether the fourteen sprites READ distinctly at 32px on a dark floor. They were")
	print("  eyeballed on a contact sheet (cn_scroll was re-baked after the first pick rendered")
	print("  as a pale smear) - but that is a look, not an assertion.")
	print("  verify_dungeon_art.gd is the release gate: it fails if a key the server can emit")
	print("  has no art, which is the half that must never regress silently.")

	print("")
	if fails == 0:
		print("PASS - loot on the floor looks like what it is")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
