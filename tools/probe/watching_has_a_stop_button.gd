extends SceneTree
## Owner sheet 2026-10-13, item 20: "No way to stop watching a player". The only exits were Escape and the
## `unwatch` chat command. Action Bar First: while watching, slot 0 is a visible Stop Watching button, and
## its click path (execute_local_action) must exist (CLAUDE.md pitfall #11). Statement-level, bounded.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var f := src.find("\nfunc update_action_bar():")
	ck(f >= 0, "found update_action_bar")
	var w := src.find("\n\telif watching_player != \"\" and not settings_mode:\n", f)
	var sm := src.find("\n\telif settings_mode:\n", f)
	ck(w > f and sm > w, "the watching branch sits before the settings branch")
	var slice := src.substr(w, 700)
	ck(slice.find("\"label\": \"Stop Watching\", \"action_type\": \"local\", \"action_data\": \"stop_watching\"") >= 0, "slot 0 is the Stop Watching button")
	var h := src.find("\n\t\t\"stop_watching\":\n")
	ck(h > 0 and src.substr(h, 300).find("\t\t\tstop_watching()\n") >= 0, "the click path calls stop_watching()")
	print("\n[STOPWATCH] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
