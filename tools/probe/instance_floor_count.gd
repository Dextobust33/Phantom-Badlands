extends SceneTree
## A dungeon has the floors ITS INSTANCE was generated with, not the floors its TYPE has.
##
## Owner screenshot 2026-09-15: the starter dungeon's completion screen read "Floors Cleared: 2/5".
## The starter instance is capped to 2 floors, and five places asked the dungeon TYPE (5) instead:
## the HUD, the floor-change message, the go-back message, the completion screen - and the Floor Skip
## Charm's "already on the boss floor?" guard, which let a player skip OFF the real boss floor and
## complete the dungeon with the boss alive. (XP deliberately still divides by the type's count -
## owner's call: fix the text, keep the tutorial's pay.)
const ServerScript = preload("res://server/server.gd")
const PEER := 1

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var sv = ServerScript.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)
	var made: Dictionary = sv.persistence.create_account("ifc%d" % (Time.get_ticks_usec() % 100000), "probe-password")
	sv.peers[PEER] = {"authenticated": true, "account_id": String(made.get("account_id", "")), "character_name": "",
		"connection": StreamPeerTCP.new()}
	var nm := "Ifc"
	var u: int = Time.get_ticks_usec()
	for i in range(4):
		nm += char(97 + (u % 26))
		u /= 26
	sv.handle_create_character(PEER, {"name": nm, "class": "Fighter", "race": "Human"})
	await process_frame
	var ch = sv.characters[PEER]
	sv._ensure_starter_dungeon_exists()
	var iid := ""
	for d in sv.active_dungeons:
		if bool(sv.active_dungeons[d].get("starter", false)):
			iid = String(d)
	ck(iid != "", "a starter dungeon exists")
	var inst = sv.active_dungeons[iid]
	ch.x = int(inst.get("world_x", 0))
	ch.y = int(inst.get("world_y", 0))
	# Entered the way a player does - standing on the tile, naming the TYPE - so the server makes the
	# personal instance that inherits the starter cap. Passing the world instance id skips that, and
	# the first cut measured a 5-floor world instance and "found" nothing wrong.
	sv.handle_dungeon_enter(PEER, {"dungeon_type": String(inst.get("dungeon_type", "")), "confirmed": true})
	await process_frame
	ck(ch.in_dungeon, "the player is inside it")
	var type_floors: int = int(sv.DungeonDatabaseScript.get_dungeon(ch.current_dungeon_type).get("floors", 0))
	# Read off the generated floors directly, so this probe also runs (and fails) on code without the helper.
	var real: int = (sv.dungeon_floors.get(String(ch.current_dungeon_id), []) as Array).size()
	if sv.has_method("_instance_floor_count"):
		ck(sv._instance_floor_count(ch) == real, "the helper agrees with the generated floors")
	print("  %s: the type says %d floors, this instance has %d" % [ch.current_dungeon_type, type_floors, real])
	ck(real == sv.STARTER_DUNGEON_FLOORS, "the instance count is the starter cap (%d)" % real)
	ck(type_floors != real, "control: the type disagrees, so the rest of this is measuring something (%d vs %d)" % [type_floors, real])

	print("\n===== THE FLOOR SKIP CHARM CANNOT SKIP THE REAL BOSS FLOOR =====")
	ch.dungeon_floor = real - 1                     # standing on the boss floor
	var charm: Dictionary = {"type": "floor_skip_charm", "name": "Floor Skip Charm", "tier": 1, "quantity": 1}
	ch.inventory.append(charm)
	var idx: int = ch.inventory.size() - 1
	sv.handle_inventory_use(PEER, {"index": idx})
	await process_frame
	var still_have := false
	for it in ch.inventory:
		if it is Dictionary and String(it.get("type", "")) == "floor_skip_charm":
			still_have = true
	# The first cut asserted only "still inside, on the boss floor", which the OLD code also satisfied:
	# the bad skip did not complete the dungeon outright - it went to the final-chest step, so the
	# player stayed put while the charm was spent and the boss was skipped. Assert what actually
	# distinguishes a refusal.
	ck(still_have, "using it on the boss floor is REFUSED - the charm is not spent")
	ck(not sv.pending_final_chest.has(PEER), "  and the boss is not skipped to its final chest")
	ck(ch.in_dungeon and ch.dungeon_floor == real - 1, "  and the player is still on the boss floor")
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src.contains('"total_floors": _instance_floor_count(character),'), "the HUD and floor messages send the instance's count")
	ck(src.contains("maxi(1, _cfloors) if _cfloors > 0 else rewards.total_floors"), "and the completion screen shows it")
	print("")
	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
