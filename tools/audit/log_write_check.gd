extends SceneTree
const CombatManager = preload("res://shared/combat_manager.gd")

func _init():
	var dir := ProjectSettings.globalize_path("res://tools/test_setup/logs")
	DirAccess.make_dir_recursive_absolute(dir)
	CombatManager.playtest_log_path = dir + "/playtest_probe.jsonl"
	print("path: ", CombatManager.playtest_log_path)
	CombatManager.playtest_log({"event": "probe", "hp_cost_pct": 42})
	var f = FileAccess.open(CombatManager.playtest_log_path, FileAccess.READ)
	if f == null:
		print("FAIL: file not created. FileAccess error = ", FileAccess.get_open_error())
	else:
		print("OK wrote: ", f.get_as_text().strip_edges())
		f.close()
	quit()
