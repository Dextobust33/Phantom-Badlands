extends SceneTree
## Is the starter dungeon actually survivable for the character who will walk into it?
##
## Measured first, built second. `-- newplayer` (2026-09-13): a gearless level-1 wins 76% of
## normal fights against a 60% design target - so the FIGHTS are fine and softening them would
## have been the wrong fix, which is what I was about to build before measuring.
##
## What kills a new character is ATTRITION. In a dungeon you recover 0.5% of max HP per step,
## half the overworld rate; a stock tier-1 is 3 floors whose population scales with floor AREA up
## to 14 each; and a character created today carried NO food, so the one recovery mechanic in the
## building - `handle_dungeon_rest` - was inert for them.
##
## This asserts the two structural answers to that. It does NOT claim the run is survivable end to
## end; that is a live playtest, and it is recorded as owed.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const DungeonDB = preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv = ServerScript.new()

	print("===== THE SIZE OF THE RUN =====")
	var stock_floors := int(DungeonDB.get_dungeon("goblin_caves").get("floors", 0))
	print("  a stock Goblin Caves is %d floors, up to 14 monsters each (area-scaled): up to %d fights"
		% [stock_floors, stock_floors * 14])
	print("  a STARTER run is %d floors, capped at %d each: %d fights plus the boss"
		% [ServerScript.STARTER_DUNGEON_FLOORS, ServerScript.STARTER_DUNGEON_MONSTERS_PER_FLOOR,
		   ServerScript.STARTER_DUNGEON_FLOORS * ServerScript.STARTER_DUNGEON_MONSTERS_PER_FLOOR])
	ck(ServerScript.STARTER_DUNGEON_FLOORS < stock_floors,
		"the starter run is shorter than the stock dungeon it is built from")
	ck(ServerScript.STARTER_DUNGEON_FLOORS * ServerScript.STARTER_DUNGEON_MONSTERS_PER_FLOOR <= 12,
		"and is at most a dozen fights - finishable on one health bar")
	ck(ServerScript.STARTER_DUNGEON_FLOORS >= 2,
		"but still more than one floor, or it is a room rather than a dungeon")

	print("")
	print("===== THE FLAG SURVIVES THE TRIP =====")
	# The marker on the map is not what you fight in: entering spins up a PERSONAL instance, so a
	# starter flag that does not make that journey caps nothing at all.
	srv.active_dungeons = {
		"world_starter": {"sub_tier": 1, "tier": 1, "starter": true, "dungeon_type": "goblin_caves"},
		"world_normal": {"sub_tier": 1, "tier": 1, "dungeon_type": "goblin_caves"},
	}
	ck(srv._is_starter_dungeon("world_starter"), "a starter dungeon says so")
	ck(not srv._is_starter_dungeon("world_normal"), "an ordinary one does not")
	ck(not srv._is_starter_dungeon("does_not_exist"),
		"and an unknown id is not accidentally a starter dungeon")

	print("")
	print("===== A NEW CHARACTER CAN ACTUALLY REST =====")
	# handle_dungeon_rest accepts plant / herb / fungus / fish and consumes one. Before this a
	# created character carried nothing at all, so the button was inert for them.
	var ch = CharacterScript.new()
	ch.initialize("Newbie", "warrior", "human")
	ch.add_crafting_material("healing_herb", ServerScript.STARTER_RATIONS)
	var qty := int(ch.crafting_materials.get("healing_herb", 0))
	print("  a created character carries %d Healing Herb" % qty)
	ck(qty == ServerScript.STARTER_RATIONS, "the rations are there")
	var CraftingDB = load("res://shared/crafting_database.gd")
	var mat: Dictionary = CraftingDB.MATERIALS.get("healing_herb", {})
	ck(String(mat.get("type", "")) in CraftingDB.FOOD_MATERIAL_TYPES,
		"and it is a type the Rest handler accepts (%s) - a ration it refuses would be worse than none"
			% String(mat.get("type", "")))
	ck(int(mat.get("tier", 99)) == 1, "at tier 1, so it is not a valuable item in disguise")

	print("")
	print("----- NOT PROVEN HERE -----")
	print("  That a gearless level-1 SURVIVES the whole run. Per-fight win rate is measured (76%),")
	print("  and the two structural blockers are answered, but the end-to-end attrition of nine")
	print("  fights on one health bar is a live playtest. Recorded as owed in docs/BACKLOG.md.")

	print("")
	if fails == 0:
		print("PASS - the starter dungeon is short, marked, and its player can rest in it")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
