extends SceneTree
## Owner sheet 2026-10-13, item 22: with Help Pop-ups off, the Warden's directions vanished and the
## tutorial became unplayable. `_send_hint` now says a caller's `fallback` as plain guide text when
## tutorials are off, and the three essential Warden hints (welcome, "I will walk you to the door",
## "out through the arch") each carry one. Source probe, statements only, slices bounded.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var h := src.find("\nfunc _send_hint(")
	ck(h >= 0, "found _send_hint")
	var he := src.find("\nfunc ", h + 10)
	var body := src.substr(h, he - h)
	ck(body.find("\n\t\tif fallback != \"\":\n\t\t\t_guide_say(peer_id, fallback)\n\t\treturn false") >= 0, "tutorials-off path says the fallback, then returns false")
	var a: int = body.find("not persistence.tutorials_enabled(account_id)")
	var b: int = body.find("_guide_say(peer_id, fallback)")
	ck(a >= 0 and b > a, "the fallback sits inside the tutorials-off branch")
	for needle in ["Welcome. You are the figure in the middle of the map.", "I will walk you to the door - stay close", "Good. That is a weapon now, not luggage."]:
		var i := src.find(needle)
		ck(i >= 0 and src.substr(i - 140, 140).find("\"\", [], \"") >= 0 or i >= 0 and src.substr(i - 60, 60).find("\"\"") >= 0, "Warden line passes its fallback: " + needle.substr(0, 30))
	print("\n[WARDENFALLBACK] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
