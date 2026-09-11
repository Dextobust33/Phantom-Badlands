extends SceneTree
## A world dungeon must outlive every personal run that started at it.
##
## Owner 2026-09-10: "I was also able to go back into the dungeon and complete it again, getting
## the chest again." The re-farm lock lives ON the world instance (`cleared_by`) and is written at
## COMPLETION by looking the tile up again — but the tile is erased 5 minutes after first entry,
## and a five-floor run takes longer. The lookup found nothing and the lock was never written.
const SERVER := "res://server/server.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var S := FileAccess.get_file_as_string(SERVER)
	var lines := S.split("\n")

	print("--- the hold predicate exists and reads live runs, not a counter ---")
	ck(S.contains("func _world_dungeon_has_live_runs(wx: int, wy: int) -> bool:"),
		"_world_dungeon_has_live_runs is defined")
	# It must match on origin_wx/origin_wy — the only link a personal run keeps to its tile.
	var a := -1
	var b := -1
	for i in range(lines.size()):
		if lines[i].begins_with("func _world_dungeon_has_live_runs"):
			a = i
		elif a >= 0 and lines[i].begins_with("func ") and i > a:
			b = i
			break
	var body := ""
	for i in range(a, b):
		body += lines[i] + "\n"
	ck(body.contains("origin_wx") and body.contains("origin_wy"),
		"it matches personal runs by the origin tile they were entered from")
	ck(body.contains("owner_peer_id"), "and it counts only PERSONAL instances, never world ones")

	print("\n--- the despawn sweep asks it before erasing ---")
	var sweep_line := -1
	var hold_line := -1
	var remove_line := -1
	for i in range(lines.size()):
		var t: String = lines[i].strip_edges()
		if t.begins_with("if entered_despawn_at > 0 and instance.active_players.is_empty()"):
			sweep_line = i
		if sweep_line > 0 and hold_line < 0 and t.begins_with("if _world_dungeon_has_live_runs("):
			hold_line = i
		if hold_line > 0 and remove_line < 0 and t == "dungeons_to_remove.append(instance_id)":
			remove_line = i
	ck(sweep_line > 0, "found the re-entry-window despawn branch")
	ck(hold_line > sweep_line, "it consults the hold predicate")
	ck(remove_line > hold_line, "...BEFORE appending the tile to the removal list")

	print("\n--- the silent miss is now audible ---")
	var c := -1
	var d := -1
	for i in range(lines.size()):
		if lines[i].begins_with("func _on_world_dungeon_boss_defeated"):
			c = i
		elif c >= 0 and lines[i].begins_with("func ") and i > c:
			d = i
			break
	var fn := ""
	for i in range(c, d):
		fn += lines[i] + "\n"
	ck(fn.contains("re-farm lock and threat clear SKIPPED"),
		"a completion that cannot find its world tile logs the fact instead of returning quietly")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
