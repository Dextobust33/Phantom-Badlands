extends SceneTree
## A dead player's dungeon, and a long-gone player's dungeon, must not stay on the map.
##
## Owner 2026-09-11: *"we need to ensure we have proper cleanup of those after players logout for
## so long or their character dies so they don't just linger on the map."*
##
## Before this, `_cleanup_player_dungeon` was called from exactly two places - quest completion
## and quest abandon - and nowhere else. Disconnect deliberately KEEPS the run so a player can
## reconnect into it, which is a real feature, but nothing ever ended that grace. Death did not
## clean up either. World dungeons have had a 24-hour cull for ages; personal ones had none. And
## they draw a `D` on their owner's own map, so a stale one is visible as well as resident.
##
## The trap this guards against is the opposite mistake: cleaning up ON disconnect, which would
## break reconnect. The grace has to exist AND have an end.
const SRC := "res://server/server.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body(src: String, fname: String) -> String:
	var i := src.find("func %s(" % fname)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	return src.substr(i, (j if j > 0 else src.length()) - i)


func _init() -> void:
	var src := FileAccess.get_file_as_string(SRC)

	print("--- one place knows where dungeon state lives ---")
	var er := _body(src, "_erase_dungeon_instance")
	ck(er != "", "_erase_dungeon_instance exists")
	for d in ["active_dungeons", "dungeon_floors", "dungeon_floor_rooms", "dungeon_monsters",
			"dungeon_floor_items", "dungeon_traps", "dungeon_npcs"]:
		ck(er.find("%s.erase(instance_id)" % d) >= 0, "...and clears %s" % d)
	# The reason it exists: there were three hand-written erase lists and one had fallen behind.
	ck(_body(src, "_cleanup_player_dungeon").find("_erase_dungeon_instance(") >= 0,
		"quest cleanup goes through it")
	var spawns := _body(src, "_check_dungeon_spawns")
	ck(spawns.find("_erase_dungeon_instance(instance_id)") >= 0,
		"the world cull goes through it too (it used to forget dungeon_traps)")

	print("\n--- the grace exists, and it ends ---")
	ck(src.find("const PERSONAL_DUNGEON_GRACE_SECONDS") >= 0, "the grace is a named constant")
	ck(src.find("const PERSONAL_DUNGEON_MAX_AGE_SECONDS") >= 0, "so is the hard age cap")
	var dis := _body(src, "handle_disconnect")
	ck(dis.find('["abandoned_at"] = _dc_now') >= 0,
		"disconnect STAMPS the clock rather than deleting the run")
	ck(dis.find("_erase_dungeon_instance") < 0 and dis.find("_drop_personal_dungeons") < 0,
		"...and does NOT erase on disconnect, which would break reconnecting into a run")
	var sel := _body(src, "handle_select_character")
	ck(sel.find('_inst.erase("abandoned_at")') >= 0, "coming back clears the clock")
	var sweep := _body(src, "_sweep_personal_dungeons")
	ck(sweep != "", "_sweep_personal_dungeons exists")
	ck(sweep.find("PERSONAL_DUNGEON_GRACE_SECONDS") >= 0 and sweep.find("PERSONAL_DUNGEON_MAX_AGE_SECONDS") >= 0,
		"...and uses both limits")
	ck(sweep.find('inst.get("active_players", []).is_empty()') >= 0,
		"...and never touches a dungeon somebody is standing in")
	ck(spawns.find("_sweep_personal_dungeons()") >= 0, "and it actually runs, from the spawn tick")

	print("\n--- death ends it immediately ---")
	var death := _body(src, "handle_permadeath")
	ck(death.find("_drop_personal_dungeons(") >= 0,
		"permadeath drops the instances, not just the character's side of them")
	ck(death.find("character.exit_dungeon()") >= 0,
		"...alongside the existing exit_dungeon, which only ever cleared the CHARACTER")

	print("\n--- and it finds them by the key that survives a reconnect ---")
	var find := _body(src, "_personal_dungeons_of")
	ck(find != "", "_personal_dungeons_of exists")
	ck(find.find('String(inst.get("owner_username", "")) == username') >= 0,
		"it matches on USERNAME first - peer ids are reassigned, so a peer-keyed instance can be orphaned")
	ck(find.find('int(inst.get("owner_peer_id", -1)) < 0') >= 0,
		"...and never sweeps a WORLD dungeon by mistake")

	print("\n[PERSONALCLEANUP] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
