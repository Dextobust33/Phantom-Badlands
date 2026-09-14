extends SceneTree
## A Sanctuary companion levels up while it is out with a character. Does that level come BACK?
##
## Owner 2026-09-13, from live reports: *"Can you confirm that companions in the sanctuary are
## actually gaining the levels they get when on a player? Some players are reporting their
## companion show as one thing on their character then don't retain their level once they die."*
##
## Reading the code produced two plausible theories and no answer, so this runs the real round
## trip on a real PersistenceManager: register -> check out -> earn XP -> die -> read the slot
## back. The number in the Sanctuary at the end is the only thing that settles it.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _companion(id: String, lvl: int) -> Dictionary:
	return {
		"id": id, "name": "Glowing Wolf Pup", "monster_type": "Wolf",
		"level": lvl, "xp": 0, "tier": 1, "sub_tier": 1,
		"variant_color": "#88CCFF", "variant_color2": "", "variant_pattern": "solid",
		"battles_fought": 0,
	}


func _hero() -> Character:
	var c = CharacterScript.new()
	c.name = "Hero"
	c.class_type = "warrior"
	c.level = 30
	return c


func _init() -> void:
	var PM = load("res://server/persistence_manager.gd")
	var pm = PM.new()
	get_root().add_child(pm)
	await process_frame

	var srv = ServerScript.new()
	srv.persistence = pm

	print("===== THE ROUND TRIP: register -> check out -> level up -> die =====")
	var house: Dictionary = pm.create_house("acct1")
	house["registered_companions"] = {"companions": [_companion("c1", 5)]}
	pm.houses_data["houses"]["acct1"] = house

	var hero := _hero()
	srv.characters = {1: hero}
	var why: String = srv._checkout_companion_for_character("acct1", hero, 0, "Hero")
	ck(why == "", "checkout succeeded (%s)" % ("ok" if why == "" else why))
	ck(int(hero.active_companion.get("level", 0)) == 5,
		"it arrives at the level the Sanctuary held (got %d)" % int(hero.active_companion.get("level", 0)))

	# Earn enough to climb several levels. add_companion_xp is the ONE grant path.
	var res: Dictionary = hero.add_companion_xp(20000)
	var on_char: int = int(hero.active_companion.get("level", 0))
	ck(res.get("leveled_up", false), "the companion levelled while out with the character")
	ck(on_char > 5, "the character shows it at level %d" % on_char)

	# The collected_companions copy is what the death path writes back first, so if the two ever
	# disagree it is the one that decides what the Sanctuary keeps.
	var collected_lvl := -1
	for comp in hero.collected_companions:
		if String(comp.get("id", "")) == "c1":
			collected_lvl = int(comp.get("level", 0))
	ck(collected_lvl == on_char,
		"the character's own two copies agree (active %d, collected %d)" % [on_char, collected_lvl])

	print("")
	print("----- now die -----")
	srv._return_registered_companions("acct1", hero)
	var back: Dictionary = pm.get_house("acct1").get("registered_companions", {}).get("companions", [])[0]
	var in_sanctuary: int = int(back.get("level", 0))
	ck(in_sanctuary == on_char,
		"the Sanctuary kept level %d, the character had %d" % [in_sanctuary, on_char])
	ck(back.get("checked_out_by", "x") == null,
		"and the slot is free again, so it can be checked out by the next character")

	print("")
	print("===== THE SUSPECT PATH: a stale copy already in collected_companions =====")
	# _return_registered_companions walks collected_companions FIRST and marks the slot done, so
	# the active companion is only written when the slot was NOT already claimed. Its own comment
	# says the active copy "may have newer data". If the two can ever disagree, the stale one wins.
	# This drives that case deliberately: a character holding an OLD level-5 record of the same
	# companion, then checking out the level-40 version.
	var house2: Dictionary = pm.create_house("acct2")
	house2["registered_companions"] = {"companions": [_companion("c1", 40)]}
	pm.houses_data["houses"]["acct2"] = house2

	var hero2 := _hero()
	srv.characters = {2: hero2}
	hero2.collected_companions = [_companion("c1", 5)]   # stale record of the same companion
	var why2: String = srv._checkout_companion_for_character("acct2", hero2, 0, "Hero2")
	ck(why2 == "", "checkout succeeded with a stale record present")
	var active2: int = int(hero2.active_companion.get("level", 0))
	var collected2 := -1
	for comp in hero2.collected_companions:
		if String(comp.get("id", "")) == "c1":
			collected2 = int(comp.get("level", 0))
	print("  after checkout: active=%d  collected=%d  (sanctuary held 40)" % [active2, collected2])
	ck(collected2 == 40,
		"the stale collected record was refreshed to the real level (got %d)" % collected2)

	hero2.add_companion_xp(100)
	print("  after one XP grant: active=%d  collected=%d" % [
		int(hero2.active_companion.get("level", 0)), _lvl_of(hero2, "c1")])
	ck(int(hero2.active_companion.get("level", 0)) >= 40,
		"one XP grant did not DEMOTE it toward the stale record")

	srv._return_registered_companions("acct2", hero2)
	var back2: Dictionary = pm.get_house("acct2").get("registered_companions", {}).get("companions", [])[0]
	ck(int(back2.get("level", 0)) >= 40,
		"the Sanctuary did not lose levels to the stale record (kept %d)" % int(back2.get("level", 0)))

	print("")
	print("===== LEGACY COMPANIONS WITH NO id =====")
	# The likeliest way a live character ends up with the wrong number. Companions predating the
	# `id` field carry "", and the lookup compared `"" == ""` - which matches whichever unnamed
	# creature happens to sit first in the list. The XP then landed on, and was read from, an
	# unrelated companion.
	var hero3 := _hero()
	var other := _companion("", 3)
	other["name"] = "Some Other Beast"
	var mine := _companion("", 30)
	hero3.collected_companions = [other, mine]
	hero3.active_companion = mine.duplicate(true)
	hero3.add_companion_xp(50)
	ck(int(hero3.active_companion.get("level", 0)) >= 30,
		"an id-less companion keeps its own level (got %d, not the level-3 stranger's)"
			% int(hero3.active_companion.get("level", 0)))
	ck(int(hero3.collected_companions[0].get("level", 0)) == 3,
		"and the unrelated creature was left alone (level %d)"
			% int(hero3.collected_companions[0].get("level", 0)))

	print("")
	if fails == 0:
		print("PASS - a Sanctuary companion keeps the levels it earned in the field")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)


func _lvl_of(ch: Character, id: String) -> int:
	for comp in ch.collected_companions:
		if String(comp.get("id", "")) == id:
			return int(comp.get("level", 0))
	return -1
