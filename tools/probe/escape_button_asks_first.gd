extends SceneTree
## Owner sheet 2026-10-13, item 12: the dungeon Escape button was one press from consuming a scroll.
## The button's arm must OPEN a confirmation, never send inventory_use itself; only the confirmed
## choice may call _use_escape_scroll. Statement matches on bounded slices (not prose).
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var a := src.find("\n\t\t\"dungeon_escape_scroll\":\n")
	ck(a >= 0, "found the button's arm")
	var b := src.find("\n\t\t\"dungeon_continue\":", a)
	ck(b > a, "found the end of the arm")
	var arm := src.substr(a, b - a)
	ck(arm.find("\n\t\t\topen_choice(\"dungeon_escape\"") >= 0, "the arm opens the confirmation")
	ck(arm.find("send_to_server(") < 0 and arm.find("_use_escape_scroll()") < 0, "the arm cannot use the scroll by itself")
	ck(src.count("\n\t\t\t\t_use_escape_scroll()") == 1, "exactly one caller: the confirmed choice")
	var h := src.find("\"dungeon_escape\":\n\t\t\tif index == 0:")
	ck(h >= 0, "the choice handler only acts on the confirming option")
	print("\n[ESCAPEASK] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
