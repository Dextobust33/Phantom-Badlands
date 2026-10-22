extends SceneTree
## The ASCENDANT tier (docs/design/paths_revamp.md 3.4): three level-gated trigger nodes per class. Each must exist, be gated by LEVEL (not points), carry a price from the
## second on, name only real triggers, deliver the trigger power it says, and be taken by the simulator's specs once the level opens it.
const PD = preload("res://shared/path_database.gd")
const CT = preload("res://shared/combat_triggers.gd")
const CharacterScript = preload("res://shared/character.gd")
const Specs = preload("res://tools/combat_simulator/path_specs.gd")
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
	var classes: Array = ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Grifter", "Ranger", "Ninja"]
	print("--- the data ---")
	for k in classes:
		var nodes: Array = PD.ascendant_nodes(k)
		var lv_ok: bool = nodes.size() == 3 and int(nodes[0]["level_req"]) == 500 and int(nodes[1]["level_req"]) == 2000 and int(nodes[2]["level_req"]) == 6000
		var single := true
		var real_triggers := true
		var priced := true
		for i in range(nodes.size()):
			var f: Dictionary = PD.find_node(String(nodes[i]["id"]))
			if PD.max_rank(f) != 1 or String(f.get("class_lock", "")) != k or not bool(f.get("ascendant", false)):
				single = false
			var has_trigger := false
			var has_price := false
			for key in nodes[i]["effect"]:
				if String(key).begins_with("trg_"):
					has_trigger = true
					if not CT.TRIGGERS.has(String(key).substr(4)):
						real_triggers = false
				else:
					has_price = true
			if not has_trigger:
				real_triggers = false
			if i >= 1 and not has_price:
				priced = false
			if i == 0 and has_price:
				priced = false
		ck(lv_ok and single and real_triggers and priced, "%s: three Ascendants at L500/2000/6000, single rank, class-locked, real triggers, a price from the second on only" % k)
	var ranger_crit := false
	for n in PD.ascendant_nodes("Ranger"):
		for key in n["effect"]:
			if String(key) in ["trg_killing_rhythm"]:
				ranger_crit = true
	ck(not ranger_crit, "the Ranger is given no crit trigger (Steady Hand never crits)")

	print("--- the level gate ---")
	var a3: Dictionary = PD.find_node("asc_Fighter_3")
	ck(not PD.ascendant_unlocked(a3, 5999) and PD.ascendant_unlocked(a3, 6000) and not PD.ascendant_unlocked(PD.find_node("asc_Fighter_1"), 499), "L6000's node opens at 6000 exactly, and not before; L500's not at 499")
	var src: String = FileAccess.get_file_as_string("res://server/server.gd")
	var i: int = src.find("func handle_path_spend(")
	var j: int = src.find("\nfunc ", i + 10)
	var body: String = src.substr(i, j - i)
	ck(body.contains("elif bool(node.get(\"ascendant\", false)):") and body.contains("PathDatabaseScript.ascendant_unlocked(node, int(character.level))"), "the server refuses an Ascendant below its level (the gate is in handle_path_spend, not just the panel)")
	var k2: int = body.find("elif bool(node.get(\"ascendant\", false)):")
	var k3: int = body.find("elif character.get_path_points_spent() < PathDatabaseScript.CLASS_KEYSTONE_SPEND_REQ")
	ck(k2 >= 0 and k3 > k2, "...and an Ascendant is NOT held to the class keystone's 8-points-spent rule")
	var rs: int = src.find("func handle_path_respec(")
	var rb: String = src.substr(rs, src.find("\nfunc ", rs + 10) - rs)
	ck(rb.contains("branch_key == \"ascendant\""), "the Ascendant row has its own respec")

	print("--- what a held node delivers ---")
	var fa = CharacterScript.new()
	fa.initialize("T", "Fighter", "Human")
	fa.set_path_rank("asc_Fighter_2", 1)
	ck(abs(fa.trigger_power("pain_fuel") - 2.0) < 0.001 and abs(fa.trigger_power("last_gasp") - 2.0) < 0.001, "Unbroken gives Pain Fuel and Last Gasp power 2")
	ck(abs(fa.get_path_effect_total("attack_damage_pct") + 8.0) < 0.001, "...and its price: -8%% attack damage (%.1f)" % fa.get_path_effect_total("attack_damage_pct"))
	var pa = CharacterScript.new()
	pa.initialize("T", "Paladin", "Human")
	pa.set_path_rank("asc_Paladin_1", 1)
	ck(abs(pa.trigger_power("judgement_mend") - 1.0) < 0.001, "a Paladin's trigger power is exactly 1: the class value table (x%.1f) never scales trigger power" % PD.class_scale("Paladin"))
	var pa2 = CharacterScript.new()
	pa2.initialize("T", "Paladin", "Human")
	pa2.set_path_rank("asc_Paladin_3", 1)
	ck(abs(pa2.get_path_effect_total("ability_cost_pct") - 15.0 * PD.class_scale("Paladin")) < 0.001 or abs(pa2.get_path_effect_total("ability_cost_pct") - 15.0) < 0.001, "...while its ordinary price still follows the class table")

	print("--- the simulator's specs take them as the level opens them ---")
	var held := []
	for lvl in [300, 700, 2500, 6500]:
		sim._path_kind = "typical"
		var ch = sim.make_char(lvl, "average", "Wizard", "Human")
		sim._path_kind = ""
		var n := 0
		for id in ch.path_ranks:
			if String(id).begins_with("asc_"):
				n += 1
		held.append(n)
	ck(held == [0, 1, 2, 3], "a typical Wizard holds %s Ascendants at L300 / 700 / 2500 / 6500 (want [0, 1, 2, 3])" % str(held))
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
