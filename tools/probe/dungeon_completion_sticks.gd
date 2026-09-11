extends SceneTree
## A completed dungeon instance must stay completed — across a restart, a reconnect, a new peer id.
##
## Evidence, live server log 2026-09-10:
##   Player Dexto entered dungeon Goblin Caves (instance player_dungeon_1_2544)
##   [DUNGEON PERSIST] Reloaded 14 dungeon instance(s), dropped 0 completed
## No "Created dungeon instance" beside it — the owner re-entered an instance already completed in
## an earlier session, whose saved grid still held the FINAL_CHEST and whose saved monsters still
## held the boss marked dead.
const SERVER := "res://server/server.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _fn_body(lines: PackedStringArray, name: String) -> String:
	var a := -1
	var b := lines.size()
	for i in range(lines.size()):
		if lines[i].begins_with("func " + name):
			a = i
		elif a >= 0 and lines[i].begins_with("func ") and i > a:
			b = i
			break
	if a < 0:
		return ""
	var out := ""
	for i in range(a, b):
		out += lines[i] + "\n"
	return out


func _init() -> void:
	var S := FileAccess.get_file_as_string(SERVER)
	var lines := S.split("\n")

	print("--- completion is recorded ON the instance ---")
	var body := _fn_body(lines, "_complete_dungeon")
	ck(body != "", "found _complete_dungeon")
	ck(body.contains('active_dungeons[instance_id]["completed_at"]'),
		"it stamps completed_at on the instance")

	# The stamp must NOT be nested inside the peer-keyed bookkeeping that loses its key.
	var stamp := -1
	var freekey := -1
	var bl := body.split("\n")
	for i in range(bl.size()):
		var t: String = bl[i].strip_edges()
		if stamp < 0 and t.begins_with('active_dungeons[instance_id]["completed_at"]'):
			stamp = i
		if freekey < 0 and t.begins_with('if player_dungeon_instances.has(peer_id):'):
			freekey = i
	ck(stamp >= 0 and freekey >= 0 and stamp < freekey,
		"...BEFORE the peer-keyed _free_run_ cleanup, so it does not depend on that key surviving")
	# and at function indent (one tab), not inside a conditional
	for i in range(bl.size()):
		if bl[i].strip_edges().begins_with('active_dungeons[instance_id]["completed_at"]'):
			var indent: int = bl[i].length() - bl[i].lstrip("\t").length()
			print("      stamp sits at %d tabs" % indent)
			ck(indent <= 2, "it is not buried inside another conditional")
			break

	print("\n--- and the three consumers of completed_at already exist ---")
	var load_body := _fn_body(lines, "_load_dungeon_state")
	if load_body == "":
		# name may differ; fall back to the pruning text
		ck(S.contains('if int(inst.get("completed_at", 0)) != 0:'),
			"the persistence reload prunes instances with completed_at set")
	else:
		ck(load_body.contains("completed_at"), "the persistence reload prunes on completed_at")
	ck(S.contains('var completed_at = instance.get("completed_at", 0)'),
		"the despawn sweep removes instances with completed_at set")
	var loc := _fn_body(lines, "_get_dungeon_at_location")
	ck(loc.contains('instance.get("completed_at", 0) > 0'),
		"the entrance lookup skips completed instances, so the tile cannot be re-entered")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
