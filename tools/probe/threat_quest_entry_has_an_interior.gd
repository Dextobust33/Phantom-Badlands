extends SceneTree
## Owner sheet 2026-10-13, item 5. A threat-relief quest binds to the WORLD dungeon (so clearing it
## clears the post's threat). World dungeons build their interior LAZILY, and `handle_dungeon_enter`
## never asked for it - so the entry read floors that did not exist. A release server carries on
## with null: it flags you "inside", sends the client nothing, and every retry says "already in a
## dungeon". This drives the REAL entry path on a world-style instance.
const SERVER := preload("res://server/server.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var s = SERVER.new()
	s.world_system = WorldSystem.new()
	s.trading_post_db = load("res://shared/trading_post_database.gd").new()
	s.monster_db = MonsterDatabase.new()
	s.drop_tables = load("res://shared/drop_tables.gd").new()
	s.combat_mgr = CombatManager.new()

	# A world dungeon exactly as `_create_world_dungeon` leaves it: registered, NO interior.
	var iid := "world_dungeon_probe"
	s._register_dungeon(iid, {
		"instance_id": iid, "dungeon_type": "wyvern_roost", "world_x": 10, "world_y": 10,
		"spawned_at": int(Time.get_unix_time_from_system()), "active_players": [],
		"dungeon_level": 40, "sub_tier": 3, "tier": 3,
	})
	ck(not s.dungeon_floors.has(iid), "the world dungeon starts with no interior (the lazy design)")

	var ch := Character.new()
	ch.initialize("ThreatProbe", "Fighter", "Human")
	ch.level = 40
	ch.x = 10
	ch.y = 10
	s.characters[1] = ch
	# What `handle_quest_accept` does for a threat-relief bounty.
	s.player_dungeon_instances[1] = {"threat_probe@wyvern_roost": iid}

	s.handle_dungeon_enter(1, {"dungeon_type": "wyvern_roost", "confirmed": true})

	ck(ch.in_dungeon, "the character was put inside")
	ck(ch.current_dungeon_id == iid, "...in the WORLD dungeon the quest is bound to (%s)" % ch.current_dungeon_id)
	# THE INVARIANT. Being inside must mean there is somewhere to be.
	ck(s.dungeon_floors.has(iid) and s.dungeon_floors[iid].size() > 0,
		"a character flagged inside has an interior to stand in")
	ck(s.dungeon_monsters.has(iid), "...and it is populated")
	print("\n--- and nobody is ever left flagged inside a place that is not there ---")
	# The general form of the defect: whatever puts a character "inside" an instance with no
	# interior (a cleanup race, a bad restore), `_send_dungeon_state` must not return quietly.
	var ch2 := Character.new()
	ch2.initialize("StrandedProbe", "Fighter", "Human")
	ch2.enter_dungeon("world_dungeon_vanished", "wyvern_roost", 5, 5)
	s.characters[2] = ch2
	ck(ch2.in_dungeon, "setup: flagged inside an instance that does not exist")
	s._send_dungeon_state(2)
	ck(not ch2.in_dungeon, "it is put back on the overworld instead of stranded")
	ck(ch2.current_dungeon_id == "", "...with no dungeon id left behind")
	s.free()
	print("\n[THREATENTRY] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
