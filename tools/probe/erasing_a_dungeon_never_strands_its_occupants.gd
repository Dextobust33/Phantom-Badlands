extends SceneTree
## Owner sheet 2026-10-13, item 36: "What happens to dungeons spawned from abandoned quests? Are they
## properly being cleaned up?" They ARE erased (abandon, the 30-minute/24-hour sweeper) - but the
## erase never asked who was standing in them, so abandoning a quest from inside its dungeon left
## the character flagged inside a place that no longer existed. Drives the REAL abandon cleanup.
const SERVER := preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _server():
	var s = SERVER.new()
	s.world_system = WorldSystem.new()
	s.trading_post_db = load("res://shared/trading_post_database.gd").new()
	s.monster_db = MonsterDatabase.new()
	s.drop_tables = load("res://shared/drop_tables.gd").new()
	s.combat_mgr = CombatManager.new()
	return s

func _init() -> void:
	print("--- abandoning a quest from INSIDE its dungeon ---")
	var s = _server()
	var iid: String = s._create_player_dungeon_instance(1, "q_abandon", "goblin_caves", 20, "", "", 0, 1, 1)
	s.player_dungeon_instances[1] = {"q_abandon": iid}
	var ch := Character.new()
	ch.initialize("Occupant", "Fighter", "Human")
	s.characters[1] = ch
	ch.enter_dungeon(iid, "goblin_caves", 5, 5)
	s.active_dungeons[iid]["active_players"].append(1)
	ck(ch.in_dungeon and s.dungeon_floors.has(iid), "setup: inside a real quest dungeon")
	s._cleanup_player_dungeon(1, "q_abandon")        # exactly what handle_quest_abandon calls
	ck(not s.active_dungeons.has(iid), "the instance was erased")
	ck(not ch.in_dungeon, "the character who was inside is no longer flagged inside")
	ck(ch.current_dungeon_id == "", "...and holds no dungeon id")
	s.free()

	print("\n--- the sweeper's erase is the same function, so a party is covered too ---")
	s = _server()
	iid = s._create_player_dungeon_instance(1, "q_sweep", "goblin_caves", 20, "", "", 0, 1, 1)
	var a := Character.new()
	a.initialize("MemberA", "Fighter", "Human")
	var b := Character.new()
	b.initialize("MemberB", "Wizard", "Human")
	var bystander := Character.new()
	bystander.initialize("Elsewhere", "Fighter", "Human")
	s.characters[1] = a
	s.characters[2] = b
	s.characters[3] = bystander
	a.enter_dungeon(iid, "goblin_caves", 5, 5)
	b.enter_dungeon(iid, "goblin_caves", 6, 5)
	s._erase_dungeon_instance(iid)
	ck(not a.in_dungeon and not b.in_dungeon, "every occupant is put back on the overworld")
	ck(not bystander.in_dungeon, "...and someone elsewhere is untouched")
	s.free()

	print("\n[ERASESTRAND] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
