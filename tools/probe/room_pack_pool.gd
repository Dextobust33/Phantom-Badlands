extends SceneTree
## The room-floor pool the renderer uses must match the tiles that were actually baked.
##
## `ROOM_PACKS` is a hand-written list in `dungeon_tiles.gd`; the tiles live in
## `client/sprites/room_floor32/` and are produced by `tools/bake_room_floors.py`. Those are two
## places holding one fact, and the failure is silent in both directions: a pack listed but not
## baked makes every room that hashes to it fall back or draw nothing, and a pack baked but not
## listed is art that no player will ever see.
##
## This is the same reason `room_variants()` counts FILES instead of carrying a written-down
## number, and the reason that is a comment in the file rather than a convention.
const Tiles = preload("res://client/dungeon_tiles.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var dir := "res://client/sprites/room_floor32/"
	if not ResourceLoader.exists(dir + "corridor_00.png"):
		print("[ROOMPOOL] SKIP - room floor art is licence-restricted and absent here")
		quit(2)
		return

	print("--- every listed pack has baked tiles ---")
	var total := 0
	for pack in Tiles.ROOM_PACKS:
		var n: int = Tiles.room_variants(String(pack))
		var first_exists: bool = ResourceLoader.exists(dir + "%s_00.png" % pack)
		total += n
		ck(first_exists, "%s has %d baked variant(s)" % [pack, n])
	ck(Tiles.ROOM_PACKS.size() >= 9,
		"the pool is %d packs" % Tiles.ROOM_PACKS.size())
	ck(total >= 13, "%d baked tiles across the pool" % total)

	print("\n--- and every baked pack is REACHABLE from the pool ---")
	# Art that is baked but not listed is work nobody will ever see. Walk the directory rather
	# than trusting the list that is under test.
	var listed := {}
	for pack in Tiles.ROOM_PACKS:
		listed[String(pack)] = true
	var d := DirAccess.open(dir)
	var orphans: Array = []
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with("_00.png"):
				var pack := f.substr(0, f.length() - 7)
				# `corridor` is baked into the same directory and is deliberately NOT a room
				# pack - it is the passage floor every room is meant to read as different from.
				# Named explicitly rather than loosening the check, so a REAL orphan still fails.
				if pack != "corridor" and not listed.has(pack):
					orphans.append(pack)
			f = d.get_next()
		d.list_dir_end()
	ck(orphans.is_empty(), "no baked pack is missing from ROOM_PACKS (%s)" % (
		"none orphaned" if orphans.is_empty() else ", ".join(orphans)))
	print("")
	print("--- a room actually RESOLVES to one of them ---")
	# The list existing is not the same as the renderer reaching it. Ask for a floor the way the
	# renderer does and check the path is a real file, over enough room ids to hit every pack.
	var seen := {}
	var missing := 0
	for room_id in range(0, 90):
		var pth: String = Tiles.room_floor_for(room_id % 7, room_id % 5, room_id)
		if pth == "":
			missing += 1
			continue
		if not ResourceLoader.exists(pth):
			missing += 1
			continue
		seen[pth.get_file()] = true
	ck(missing == 0, "every one of 90 room ids resolves to a file that exists (%d missing)" % missing)
	ck(seen.size() >= Tiles.ROOM_PACKS.size(),
		"%d distinct floor tiles reached across 90 room ids, pool is %d packs" % [
			seen.size(), Tiles.ROOM_PACKS.size()])
	quit(0 if fails == 0 else 1)
