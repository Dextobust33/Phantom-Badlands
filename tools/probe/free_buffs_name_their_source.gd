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
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
