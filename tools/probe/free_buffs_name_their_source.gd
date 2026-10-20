extends SceneTree
## A buff the player did not cast must say where it came from (owner 2026-10-20: the Fighter's free 85% mitigation
## "doesn't make sense why the fighter gets it" - it was real, but nothing on screen named it).
## Checks the Fighter stance executes at half strength, carries its label, shows under that label in the mitigation
## breakdown, and that a Barbarian gets nothing.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var CM = load("res://shared/combat_manager.gd")
	var CH = load("res://shared/character.gd")
	var cm = CM.new()
	var f = CH.new()
	f.initialize("probe_fighter", "Fighter", "Human")
	var rec: Dictionary = cm._apply_opening_stance(f)
	ck(int(rec.get("warrior_stance_dr", 0)) == 30, "stance DR is half of 60 (got %s)" % str(rec.get("warrior_stance_dr")))
	ck(f.get_buff_source("damage_reduction") == CM.STANCE_LABEL, "the DR buff carries the stance label")
	ck(f.get_buff_source("defense") == CM.STANCE_LABEL, "the defense buff carries the stance label")
	var labels: Array = []
	for s in cm.player_mitigation_breakdown(f, {}):
		labels.append(String(s["label"]))
	ck(CM.STANCE_LABEL in labels, "mitigation breakdown names it: %s" % str(labels))
	# a cast card (no source) must not inherit the label, and a stronger anonymous value drops it
	f.add_buff("damage_reduction", 60, 3)
	ck(f.get_buff_source("damage_reduction") == "", "a stronger cast card replaces the label")
	var b = CH.new()
	b.initialize("probe_barb", "Barbarian", "Human")
	ck(cm._apply_opening_stance(b).is_empty() and b.get_buff_value("damage_reduction") == 0, "Barbarian opens with nothing")
	# the fight's opening line names the class passive, the racial passive and (Fighter) the stance
	var cm2 = CM.new()
	var f2 = CH.new()
	f2.initialize("probe_f2", "Fighter", "Orc")
	var mon: Dictionary = {"name": "Rat", "level": 1, "max_hp": 50, "current_hp": 50, "strength": 5, "defense": 1, "speed": 1, "abilities": [], "experience_reward": 1, "gold_reward": 1}
	var res: Dictionary = cm2.start_combat(7, f2, mon)
	var log_txt: String = "
".join(cm2.active_combats[7].get("combat_log", [])) if cm2.active_combats.has(7) else ""
	ck(log_txt.find("Passive - Tactical Discipline") >= 0, "opening line names the class passive")
	ck(log_txt.find("Racial - Berserker") >= 0, "opening line names the racial passive")
	ck(log_txt.find("Fighter's stance") >= 0, "opening line names the stance")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
