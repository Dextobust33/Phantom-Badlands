extends SceneTree
## Owner 2026-10-22: every dungeon card carries the combat tags, so trigger gear and Ascendant nodes work with them. The tag comes from the card's `kind`; this fails when a kind has no tags
## (a new card must place its kind), when a card resolves to nothing, and proves a trigger really fires from a real dungeon-card cast.
const CT = preload("res://shared/combat_triggers.gd")
var sim
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var DT = load("res://shared/drop_tables.gd")
	var untagged: Array = []
	var unknown_kinds: Array = []
	var n := 0
	for slug in DT.DUNGEON_CARD_DATA:
		n += 1
		var kind: String = String(DT.DUNGEON_CARD_DATA[slug].get("kind", ""))
		if not CT.DUNGEON_KIND_TAGS.has(kind):
			unknown_kinds.append(kind)
		if CT.tags_for("dungeon_card_" + String(slug), true).is_empty():
			untagged.append(String(slug))
	ck(n == 53, "all 53 dungeon cards are in the table (%d)" % n)
	ck(unknown_kinds.is_empty(), "every kind has tags (unplaced: %s)" % str(unknown_kinds))
	ck(untagged.is_empty(), "no dungeon card resolves to an empty tag list (%s)" % ", ".join(untagged))
	ck("guard" in CT.tags_for("dungeon_card_bulwark_of_bone"), "Bulwark of Bone is a guard card")
	ck("finisher" in CT.tags_for("dungeon_card_executioners_edge"), "Executioner's Edge is a finisher")
	ck("control" in CT.tags_for("dungeon_card_undertow"), "Undertow is a control card")
	# a real cast: Steady Hands (guard -> heal) fires from Bulwark of Bone
	var ch = sim.make_char(60, "average", "Fighter", "Human")
	ch.set_path_scale_override(1.0)
	ch.combat_deck_collection["dungeon_card_bulwark_of_bone"] = 1
	ch.equipped["ring"] = {"name": "Test Ring", "type": "ring", "slot": "ring", "wear": 0, "affixes": {"trg_steady_hands": 1.0}}
	var mon = sim.make_monster(60, "normal", 1.0)
	mon.max_hp = 99999999
	mon.current_hp = 99999999
	sim.combat_mgr.start_combat(1500, ch, mon)
	var c = sim.combat_mgr.active_combats[1500]
	c["player_can_act"] = true
	c["suppress_monster_turn"] = true
	c["combat_hand"] = ["dungeon_card_bulwark_of_bone"]
	ch.current_hp = int(ch.get_total_max_hp() * 0.5)
	var hp0: int = ch.current_hp
	var r = sim.combat_mgr.process_ability_command(1500, "dungeon_card_bulwark_of_bone", "")
	var blob := String(r.get("message", ""))
	for m in r.get("messages", []):
		blob += String(m)
	ck(bool(r.get("success", false)) and blob.find("Steady Hands") >= 0, "a trigger fires from a real dungeon-card cast (Steady Hands from Bulwark of Bone)")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
