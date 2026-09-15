extends SceneTree
## Two new players at step three: the second one's Warden must lead to the ENTRANCE, not to the first
## player's private copy of the dungeon.
##
## Owner, live on v0.9.791 with another new player on the server: *"the warden led me to a different
## spot that was in a hotzone (he couldn't get in due to the warning). I walked onto the spot that was
## highlighted and can't find a dungeon here."* Entering a starter dungeon creates the entrant's
## personal instance, flagged starter and registered at a random point 25-40 tiles away; the lookup
## the Warden and the map ring share did not skip it. The probe puts A's copy right beside B - the
## case that fooled the owner - and B must still be sent to the world tile.
const ServerScript = preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _make(sv, peer: int, tag: String):
	var made: Dictionary = sv.persistence.create_account("sd2%s%d" % [tag, Time.get_ticks_usec() % 100000], "probe-password")
	sv.peers[peer] = {"authenticated": true, "account_id": String(made.get("account_id", "")), "character_name": "",
		"connection": StreamPeerTCP.new()}
	var nm := "Sdt" + tag
	var u: int = Time.get_ticks_usec()
	for i in range(4):
		nm += char(97 + (u % 26))
		u /= 26
	sv.handle_create_character(peer, {"name": nm, "class": "Fighter", "race": "Human"})
	return sv.characters[peer]


func _init() -> void:
	var sv = ServerScript.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)
	var a = _make(sv, 1, "a")
	var b = _make(sv, 2, "b")
	await process_frame
	sv._ensure_starter_dungeon_exists()
	var world_iid := ""
	for d in sv.active_dungeons:
		if bool(sv.active_dungeons[d].get("starter", false)) and int(sv.active_dungeons[d].get("owner_peer_id", -1)) < 0:
			world_iid = String(d)
	ck(world_iid != "", "a starter dungeon entrance exists")
	var wx := int(sv.active_dungeons[world_iid].world_x)
	var wy := int(sv.active_dungeons[world_iid].world_y)

	# A walks onto the entrance and goes in, the way a player does.
	a.x = wx
	a.y = wy
	sv.handle_dungeon_enter(1, {"dungeon_type": String(sv.active_dungeons[world_iid].dungeon_type), "confirmed": true})
	await process_frame
	ck(a.in_dungeon, "player A is inside their own copy")
	var copy_iid := String(a.current_dungeon_id)
	ck(copy_iid != world_iid and bool(sv.active_dungeons.get(copy_iid, {}).get("starter", false)),
		"A's copy is a separate instance that carries the starter flag")

	# B stands far from the entrance, with A's copy registered right beside them.
	b.x = wx + 40
	b.y = wy + 40
	sv.active_dungeons[copy_iid]["world_x"] = b.x + 1
	sv.active_dungeons[copy_iid]["world_y"] = b.y
	var found: Dictionary = sv._nearest_starter_dungeon(b)
	ck(int(found.get("x", 99999)) == wx and int(found.get("y", 99999)) == wy,
		"B's Warden and ring point at the ENTRANCE (%d,%d), not A's copy (got %d,%d)" % [wx, wy, int(found.get("x", 0)), int(found.get("y", 0))])

	# The entrance despawns while A's run continues: a NEW entrance must spawn, and A's copy must not
	# count as one.
	sv.active_dungeons.erase(world_iid)
	sv._ensure_starter_dungeon_exists()
	var entrances := 0
	for d in sv.active_dungeons:
		if bool(sv.active_dungeons[d].get("starter", false)) and int(sv.active_dungeons[d].get("owner_peer_id", -1)) < 0:
			entrances += 1
	ck(entrances == 1, "with the entrance gone and A still inside, a new entrance spawns (%d)" % entrances)
	print("")
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
