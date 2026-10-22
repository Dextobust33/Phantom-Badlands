extends SceneTree
## Persistent boons (owner 2026-10-22). Every boon must be READ by something, stacking must weaken, offers must be valid and class/deck filtered, a pick must land on the character and survive a save, a
## dungeon boon must end with its dungeon, and hard fights must offer where ordinary ones only sometimes do.
const B = preload("res://shared/boons.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _mk(cls: String):
	var c = load("res://shared/character.gd").new()
	c.initialize("Boony", cls, "Human")
	return c

func _init() -> void:
	print("--- every boon is read by something ---")
	var readers: String = FileAccess.get_file_as_string("res://shared/combat_manager.gd") + FileAccess.get_file_as_string("res://shared/character.gd")
	var CT = load("res://shared/combat_triggers.gd")
	var dead: Array = []
	for id in B.BOONS:
		for key in B.BOONS[id]["effect"]:
			var k := String(key)
			if k.begins_with("trg_"):
				if not CT.TRIGGERS.has(k.substr(4)):
					dead.append(id + ":" + k)
			elif not readers.contains("\"%s\"" % k):
				dead.append(id + ":" + k)
	ck(dead.is_empty(), "every effect key has a reader / every trigger exists (dead: %s)" % str(dead))

	print("--- stacking weakens ---")
	var one: float = B.effect_totals({"thick_skin": 1}, {})["damage_reduction_pct"]
	var five: float = B.effect_totals({"thick_skin": 5}, {})["damage_reduction_pct"]
	var fifty: float = B.effect_totals({"thick_skin": 50}, {})["damage_reduction_pct"]
	ck(five > one * 3.0 and five < one * 5.0, "five copies are worth more than three but less than five times one (%.2f vs %.2f)" % [five, one])
	ck(fifty < one / (1.0 - B.LIFE_CURVE) + 0.001, "fifty copies never pass the geometric ceiling (%.2f < %.2f)" % [fifty, one / (1.0 - B.LIFE_CURVE)])
	var spread: float = B.effect_totals({"thick_skin": 1, "hardy": 1, "light_step": 1}, {}).size()
	ck(spread == 3.0, "different boons do not weaken each other (three keys, three full values)")
	var d1: float = B.effect_totals({}, {"thick_skin": 1})["damage_reduction_pct"]
	ck(d1 > one * 1.5, "a dungeon boon is worth more than the same life boon (%.2f vs %.2f)" % [d1, one])

	print("--- eligibility ---")
	ck(not B.eligible("arcane_edge", "Fighter", []) and B.eligible("arcane_edge", "Wizard", []), "a spell boon is offered to mages only")
	ck(B.eligible("keen_edge", "Fighter", []) and not B.eligible("keen_edge", "Wizard", []), "an attack boon is not offered to mages")
	ck(not B.eligible("rhythm", "Ranger", []), "a crit trigger is not offered to a class that cannot crit")
	ck(not B.eligible("chill", "Fighter", ["strike"]) and B.eligible("chill", "Fighter", ["control"]), "a card-tag trigger needs a card of that tag in the deck")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var clean := true
	for i in range(300):
		var cls: String = ["Fighter", "Wizard", "Ranger", "Paladin", "Sage"][i % 5]
		var opts: Array = B.roll_options(cls, ["strike", "guard"], {}, rng)
		var seen := {}
		for o in opts:
			if seen.has(o) or not B.eligible(String(o), cls, ["strike", "guard"]):
				clean = false
			seen[o] = true
		if opts.size() != 3:
			clean = false
	ck(clean, "300 offers: always three DIFFERENT boons, every one eligible for the class and deck")

	print("--- how often ---")
	ck(B.offer_chance("hard", 50, 0) == 1.0, "a hard fight always offers when behind budget")
	ck(B.offer_chance("hard", 50, 200) == 0.0, "...but not when far ahead of budget")
	var behind: float = B.offer_chance("normal", 50, 0)
	var level: float = B.offer_chance("normal", 50, B.budget_for_level(50))
	ck(behind > level and level > 0.0 and behind <= B.CHANCE_NORMAL + 0.0001, "an ordinary fight offers sometimes, more when behind (%.3f vs %.3f)" % [behind, level])
	ck(B.fight_kind({"empowered_mods": ["swift", "giant"]}) == "hard" and B.fight_kind({"empowered_mods": ["swift"]}) == "modified" and B.fight_kind({"is_boss_fight": true}) == "hard" and B.fight_kind({}) == "normal", "boss / elite / two traits are hard; one trait modified; else normal")

	print("--- on a character ---")
	var c = _mk("Fighter")
	var base: float = c.get_path_effect_total("damage_reduction_pct")
	c.add_boon("thick_skin")
	ck(c.get_path_effect_total("damage_reduction_pct") > base, "a taken boon reaches the effect funnel combat reads (%.2f -> %.2f)" % [base, c.get_path_effect_total("damage_reduction_pct")])
	var tp0: float = c.trigger_power("steady_hands")
	c.add_boon("steady")
	ck(c.trigger_power("steady_hands") > tp0, "a trigger boon grants trigger power")
	c.add_boon("hardy", "dungeon")
	var with_dg: float = c.get_path_effect_total("max_hp_pct")
	c.pending_boon_offers.append({"options": ["keen_edge", "hardy", "thick_skin"], "scope": "dungeon", "why": "x"})
	var back = _mk("Fighter")
	back.from_dict(c.to_dict())
	ck(back.boons == c.boons and back.dungeon_boons == c.dungeon_boons and back.pending_boon_offers.size() == 1, "boons, dungeon boons and a waiting offer survive a save")
	ck(abs(back.get_path_effect_total("max_hp_pct") - with_dg) < 0.0001, "...and give the same totals after loading")
	c.exit_dungeon()
	ck(c.dungeon_boons.is_empty() and c.get_path_effect_total("max_hp_pct") < with_dg and c.pending_boon_offers.is_empty(), "leaving the dungeon drops dungeon boons and their waiting offers, keeps life boons (%d)" % c.boon_count())
	ck(c.boons.has("thick_skin"), "life boons stay")

	print("--- server plumbing ---")
	var s: String = FileAccess.get_file_as_string("res://server/server.gd")
	ck(s.contains("\t\t\t_maybe_offer_boon(peer_id, {") and s.contains("\t\t\t_maybe_offer_boon(pid, {"), "both the solo kill and the party kill offer a boon")
	ck(s.contains("\t\t\"boon_pick\":\n\t\t\thandle_boon_pick(peer_id, message)"), "boon_pick is routed")
	ck(s.contains("if choice != \"\" and not (choice in (offer.get(\"options\", []) as Array)):"), "a pick must be one of the three offered")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
