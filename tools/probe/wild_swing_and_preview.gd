extends SceneTree
## Three faults found from one live test session, 2026-09-15 (v0.9.790):
##
## 1. A WILD SWING WHIFF READ AS A 1-DAMAGE HIT. Owner: *"I had a buddy who had Wild Swing on his
##    meteor and it kept hitting for 1 damage."* The whiff returned 0, `apply_damage_variance`
##    floored it to 1, and nothing said it missed. Measured before the fix: 13 of 60 casts dealt 1,
##    0 of them mentioned a miss.
##
## 2. THE CARD PREVIEW CAST THE UPGRADES. Quoting a card ran `_apply_card_upgrade_damage`, which
##    writes once-per-fight flags and rolls the gambles. Measured before the fix: Opener was marked
##    used before the player had cast anything (starting the fight sends the state), and Meteor's
##    quote read 0 on 15 of 80 state sends. Sacrificial - "once per fight, then spent" - was spent
##    by the quote, so every real cast of it returned 0.
##
## 3. THE PARTY PAYLOAD HAD NO FINISHER. Owner, in the Warden's fight (a party combat): Assassinate
##    read "~1 · 3% kill" at every Read level. `_party_member_hand_payload` hand-copied a subset of
##    the engine fields and never gained finisher_kind / finisher_damage. Both paths now read
##    `engine_display_fields`, and this checks the real server function carries every key of it.
const ServerScript = preload("res://server/server.gd")
const MonsterDB = preload("res://shared/monster_database.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sim = load("res://tools/combat_simulator/real_combat_sim.gd").new()
	get_root().add_child(sim)
	await process_frame
	var cm = sim.combat_mgr

	print("===== 1. A WHIFF SAYS IT MISSED =====")
	var ones := 0
	var said := 0
	for i in range(60):
		var ch = sim.make_char(20, "average", "Wizard", "Human")
		ch.ability_milestone_picks["meteor"] = ["wild_swing"]
		cm.start_combat(0, ch, sim.make_monster(20, "normal", 50.0))
		var c = cm.active_combats[0]
		c["combat_hand"] = ["meteor"]
		c["player_can_act"] = true
		c["suppress_monster_turn"] = true
		ch.current_mana = ch.get_total_max_mana()
		var hp0: int = int(c["monster"]["current_hp"])
		var res: Dictionary = cm.process_ability_command(0, "meteor", "")
		if hp0 - int(c["monster"]["current_hp"]) <= 1:
			ones += 1
			if " ".join(PackedStringArray(res.get("messages", []))).find("Wild Swing") >= 0:
				said += 1
		cm.active_combats.erase(0)
	print("  %d of 60 casts whiffed (20%% expected)" % ones)
	ck(ones > 0, "the whiff happens at all (a probe that never whiffs proves nothing)")
	ck(said == ones, "every whiff names Wild Swing in the log (%d of %d)" % [said, ones])

	print("\n===== 2. QUOTING A CARD DOES NOT CAST IT =====")
	var ch2 = sim.make_char(20, "average", "Fighter", "Human")
	ch2.ability_milestone_picks["cleave"] = ["opener"]
	cm.start_combat(0, ch2, sim.make_monster(20, "normal", 50.0))
	var c2 = cm.active_combats[0]
	c2["combat_hand"] = ["cleave"]
	cm.get_combat_display(0)
	cm.get_combat_display(0)
	ck(not c2.has("opener_used_cleave"), "starting the fight and sending the state twice leaves Opener unused")
	cm.active_combats.erase(0)

	var ch3 = sim.make_char(20, "average", "Fighter", "Human")
	ch3.ability_milestone_picks["cleave"] = ["sacrificial"]
	cm.start_combat(0, ch3, sim.make_monster(20, "normal", 50.0))
	var c3 = cm.active_combats[0]
	c3["combat_hand"] = ["cleave"]
	c3["player_can_act"] = true
	c3["suppress_monster_turn"] = true
	cm.get_combat_display(0)
	ck(not c3.has("sacrificed_cleave"), "and Sacrificial is not spent by the quote")
	ch3.current_stamina = ch3.get_total_max_stamina()
	var shp0: int = int(c3["monster"]["current_hp"])
	cm.process_ability_command(0, "cleave", "")
	var sdealt: int = shp0 - int(c3["monster"]["current_hp"])
	ck(sdealt > 1, "so its first real cast lands (%d damage)" % sdealt)
	cm.active_combats.erase(0)

	var ch4 = sim.make_char(20, "average", "Wizard", "Human")
	ch4.ability_milestone_picks["meteor"] = ["wild_swing"]
	cm.start_combat(0, ch4, sim.make_monster(20, "normal", 50.0))
	var c4 = cm.active_combats[0]
	c4["combat_hand"] = ["meteor"]
	var vals := {}
	for i in range(80):
		vals[int(cm._build_ability_effect_info(c4).get("meteor", {}).get("value", -1))] = true
	ck(vals.size() == 1 and not vals.has(0), "Wild Swing Meteor's quote is one steady number over 80 sends: %s" % str(vals.keys()))
	cm.active_combats.erase(0)

	print("\n===== 2b. PHANTOM STRIKE'S CARD QUOTES THE DAMAGE IT DEALS =====")
	# Owner: *"I used Phantom strike and it did damage it didn't advertise or show on the card
	# face."* The preview had no branch for it, so the face showed only "Auto-crit".
	var ch5 = sim.make_char(20, "average", "Ninja", "Human")
	cm.start_combat(0, ch5, sim.make_monster(20, "normal", 50.0))
	var c5 = cm.active_combats[0]
	c5["combat_hand"] = ["vanish"]
	var q5: Dictionary = cm._build_ability_effect_info(c5).get("vanish", {})
	ck(String(q5.get("kind", "")) == "damage" and int(q5.get("value", 0)) > 0,
		"the quote is a damage number (%s)" % str(q5))
	c5["player_can_act"] = true
	c5["suppress_monster_turn"] = true
	ch5.current_energy = ch5.get_total_max_energy()
	var vhp0: int = int(c5["monster"]["current_hp"])
	cm.process_ability_command(0, "vanish", "")
	var vdealt: int = vhp0 - int(c5["monster"]["current_hp"])
	# The cast applies defence and +-15% variance on top; the quote, like every card's, does not.
	ck(vdealt > 0 and vdealt <= int(q5.get("value", 0)) * 1.3,
		"  and the real strike is in its neighbourhood (quoted %d, dealt %d)" % [int(q5.get("value", 0)), vdealt])
	cm.active_combats.erase(0)

	print("\n===== 3. THE PARTY PAYLOAD CARRIES EVERY ENGINE FIELD =====")
	var s = ServerScript.new()
	s.combat_mgr = cm
	s.monster_db = MonsterDB.new()
	s.drop_tables = DropTablesScript.new()
	var ninja = sim.make_char(5, "average", "Ninja", "Human")
	var mon = sim.make_monster(5, "normal", 50.0)
	s.characters = {7: ninja}
	cm.active_party_combats[7] = {"members": [7], "monster": mon, "round": 2,
		"member_states": {7: {"hand": ["perfect_heist"], "deck": [], "discard": [], "combo": 3}}}
	var payload: Dictionary = s._party_member_hand_payload(7, 7)
	var want: Dictionary = cm.engine_display_fields(ninja, {"character": ninja, "monster": mon, "combo": 3})
	var missing: Array = []
	for k in want.keys():
		if not payload.has(k):
			missing.append(k)
	ck(missing.is_empty(), "no engine field missing from the party payload %s" % str(missing))
	ck(String(payload.get("finisher_kind", "")) == "roll", "the Ninja's finisher is named a roll (got '%s')" % payload.get("finisher_kind", ""))
	ck(int(payload.get("finisher_damage", 0)) > 1, "and carries real strike damage (got %s, was absent -> '~1')" % payload.get("finisher_damage", 0))
	ck(int(payload.get("assassinate_chance", 0)) == int(want.get("assassinate_chance", -1)), "the chance matches the shared builder")
	cm.active_party_combats.erase(7)
	s.free()

	print("")
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
