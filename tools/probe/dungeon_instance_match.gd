extends SceneTree
## The dungeon list must describe the dungeon you can actually walk into.
##
## Owner, twice: *"On the overworld this said it was a T1-2 Forgotten Crypt. I entered and it is a
## T1-7."* `handle_dungeon_list` matched an instance on dungeon_type ALONE and took the first hit
## in DICTIONARY ORDER — so the sub-tier printed in the name, the recommended level band, and the
## map coordinates the player then walked to could all belong to a different dungeon entirely.
##
## This calls the REAL finder on a synthetic instance table rather than reading its source, because
## the fault was never in what the code said — it was in which row it picked.
const SERVER := preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _srv(instances: Dictionary):
	var s = SERVER.new()
	s.active_dungeons = instances
	return s


func _inst(t: String, x: int, y: int, sub: int, extra: Dictionary = {}) -> Dictionary:
	var d := {"dungeon_type": t, "world_x": x, "world_y": y, "sub_tier": sub, "completed_at": 0}
	for k in extra:
		d[k] = extra[k]
	return d


func _init() -> void:
	print("--- a COMPLETED run is not somewhere you can go ---")
	var s = _srv({
		"world_dungeon_1": _inst("crypt", 10, 0, 2, {"completed_at": 1757000000}),
		"world_dungeon_2": _inst("crypt", 400, 0, 7),
	})
	var got: String = s.find_dungeon_instance("crypt", 0, 0)
	ck(got == "world_dungeon_2",
		"the finished T1-2 sitting first in the dictionary is skipped for the live T1-7")
	s.free()

	print("\n--- another player's personal run is invisible ---")
	s = _srv({
		"player_dungeon_9_1": _inst("crypt", 5, 0, 7, {"owner_peer_id": 99, "owner_username": "Someone"}),
		"world_dungeon_2": _inst("crypt", 400, 0, 2),
	})
	got = s.find_dungeon_instance("crypt", 0, 0, 7, "Dexto")
	ck(got == "world_dungeon_2",
		"a stranger's instance is not listed even though it is 80x closer")
	s.free()

	print("\n--- but YOUR OWN live run wins outright, at any distance ---")
	s = _srv({
		"world_dungeon_1": _inst("crypt", 1, 0, 2),
		"player_dungeon_7_3": _inst("crypt", 900, 0, 7, {"owner_peer_id": 7, "owner_username": "Dexto"}),
	})
	got = s.find_dungeon_instance("crypt", 0, 0, 7, "Dexto")
	ck(got == "player_dungeon_7_3",
		"the run you are part way through beats a world 'D' one tile from your feet")
	# ...and is found again after a reconnect, when the peer id has changed but the name has not.
	got = s.find_dungeon_instance("crypt", 0, 0, 41, "Dexto")
	ck(got == "player_dungeon_7_3", "...and survives a reconnect, matched by username")
	s.free()

	print("\n--- otherwise: NEAREST, which is what decides where you end up ---")
	s = _srv({
		"world_dungeon_a": _inst("crypt", 500, 0, 7),
		"world_dungeon_b": _inst("crypt", 12, 0, 2),
		"world_dungeon_c": _inst("crypt", 300, 0, 5),
	})
	got = s.find_dungeon_instance("crypt", 0, 0)
	ck(got == "world_dungeon_b", "picks the one 12 tiles away, not the one first in the dictionary")
	s.free()

	print("\n--- the Cartographer marks a MAP 'D', so personal runs do not answer it ---")
	s = _srv({
		"player_dungeon_7_3": _inst("crypt", 2, 0, 7, {"owner_peer_id": 7, "owner_username": "Dexto"}),
		"world_dungeon_1": _inst("crypt", 600, 0, 3),
	})
	ck(s.find_dungeon_instance("crypt", 0, 0, 7, "Dexto", true) == "world_dungeon_1",
		"world_only skips even your OWN instance — it has no presence on anyone's map")
	ck(s.find_dungeon_instance("crypt", 0, 0, 7, "Dexto", false) == "player_dungeon_7_3",
		"...while the dungeon LIST still prefers it")
	s.free()

	print("\n--- nothing to find is answered honestly ---")
	s = _srv({"world_dungeon_1": _inst("wolf_den", 5, 0, 1)})
	ck(s.find_dungeon_instance("crypt", 0, 0) == "", "no instance of that type returns \"\"")
	s.free()

	print("\n--- and all three callers ask the ONE finder ---")
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.count("find_dungeon_instance(") == 4,
		"1 definition + 3 call sites: the list, the Cartographer, the quest restore — got %d" % src.count("find_dungeon_instance("))
	ck(not src.contains('if inst.dungeon_type == dungeon_type:'),
		"the old type-only match is gone")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
