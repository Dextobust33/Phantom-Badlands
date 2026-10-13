extends SceneTree
## Low-severity finding from the 2026-10-13 probe triage: `handle_move` reads `escorted` from the
## INCOMING MESSAGE and skips the danger-step confirmation for escorted steps, so a modified client
## could send `"escorted": true` on its own move. Only the server's own Warden calls may set it.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	# The network dispatch's "move" arm, bounded to that arm and nothing else.
	var a := src.find("\n\t\t\"move\":\n")
	var b := src.find("\n\t\t\"set_travel_stance\":", a + 5)
	ck(a > 0 and b > a, "found the dispatcher's move arm")
	var arm := src.substr(a, b - a) if (a > 0 and b > a) else ""
	var lines: Array = []
	for l in arm.split("\n"):
		lines.append(String(l).strip_edges())
	var erase_at := lines.find('message.erase("escorted")')
	var call_at := lines.find("handle_move(peer_id, message)")
	ck(erase_at >= 0 and call_at > erase_at, "a client's `escorted` is stripped BEFORE the message reaches handle_move")
	# ...and the Warden still gets through: his own calls build a fresh dictionary and set the flag.
	var internal := 0
	for l in src.split("\n"):
		var t := String(l).strip_edges()
		if t.begins_with("handle_move(peer_id, {") and t.find('"escorted": true') >= 0:
			internal += 1
	ck(internal >= 2, "the Warden's own steps still pass the flag (%d call sites)" % internal)
	print("\n[ESCORTFLAG] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
