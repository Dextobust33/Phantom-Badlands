extends SceneTree
## Does a party in a dungeon fight ONE monster together, or one each in private?
##
## Owner 2026-09-13, on what "party play isn't working properly" actually meant: *"likely
## regarding no support for it in dungeons."* Confirmed: both dungeon combat starters carried the
## v0.9.732 note *"legacy shared party combat disabled pending rebuild"* and called
## `combat_mgr.start_combat` solo. The #64/#76 co-op rebuild that replaced the legacy path was
## only ever wired into `trigger_encounter` - the overworld.
##
## This RUNS the real functions on a real CombatManager rather than reading server.gd. A
## source-reading probe cannot tell a call that fires from one nested under a branch that never
## runs - see feedback_indentation_is_invisible_to_a_source_probe, where exactly that shipped
## twice. Every assertion below is made against live state after calling the real thing.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const MonsterDB = preload("res://shared/monster_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _mk(nm: String, cls: String) -> Character:
	var c = CharacterScript.new()
	c.name = nm
	c.class_type = cls
	c.level = 10
	c.current_hp = c.get_total_max_hp()
	return c


func _srv() -> Node:
	## A server with just enough state to run the dungeon co-op path. _ready never runs (it would
	## open a TCP port), so combat_mgr is constructed here exactly as server.gd line 741 does.
	var s = ServerScript.new()
	s.combat_mgr = CombatManager.new()
	return s


func _party(s, lead_floor: int, mate_floor: int, mate_inst: String, mate_in_dungeon: bool = true) -> Array:
	var a := _mk("Leader", "warrior")
	var b := _mk("Mate", "mage")
	for c in [a, b]:
		c.in_dungeon = true
		c.current_dungeon_id = "inst_A"
		c.current_dungeon_type = "goblin_caves"
	a.dungeon_floor = lead_floor
	b.dungeon_floor = mate_floor
	b.current_dungeon_id = mate_inst
	b.in_dungeon = mate_in_dungeon
	s.characters = {1: a, 2: b}
	s.active_parties = {1: {"leader": 1, "members": [1, 2], "formed_at": 0}}
	s.party_membership = {1: 1, 2: 1}
	return [a, b]


func _monster() -> Dictionary:
	var db = MonsterDB.new()
	var m = db.generate_monster(10, 10)
	if m.is_empty():
		m = {"name": "Test Ogre", "level": 10, "max_hp": 400, "current_hp": 400,
			 "strength": 20, "defense": 10, "speed": 10, "experience_reward": 50, "abilities": []}
	return m


func _init() -> void:
	print("===== 1. SAME FLOOR, SAME INSTANCE -> ONE SHARED FIGHT =====")
	var s = _srv()
	var pc := _party(s, 2, 2, "inst_A")
	var mon := _monster()
	var base_hp := int(mon.get("max_hp", 0))
	var started: bool = s._try_start_dungeon_coop(1, pc[0], mon, false, 77)
	ck(started, "co-op started (returned true, so the caller skips the solo fight)")
	ck(s.combat_mgr.active_party_combats.has(1), "a party combat exists, keyed on the leader")
	var c: Dictionary = s.combat_mgr.active_party_combats.get(1, {})
	ck(c.get("members", []).size() == 2, "both heroes are in it (got %d)" % c.get("members", []).size())
	ck(not s.combat_mgr.active_combats.has(1) and not s.combat_mgr.active_combats.has(2),
		"and NEITHER of them is in a private solo combat")

	print("")
	print("----- the dungeon context has to travel with the fight -----")
	# It cannot be re-derived at victory: completing a boss teleports everyone out, so by then
	# the leader no longer knows which floor the monster was standing on.
	ck(bool(c.get("is_dungeon_combat", false)), "is_dungeon_combat stamped")
	ck(int(c.get("dungeon_monster_id", -1)) == 77,
		"the monster ENTITY id is carried (got %d)" % int(c.get("dungeon_monster_id", -99)))
	ck(String(c.get("dungeon_instance_id", "")) == "inst_A", "the instance is pinned")
	ck(int(c.get("dungeon_floor", -1)) == 2, "the floor is pinned (got %d)" % int(c.get("dungeon_floor", -1)))
	ck(int(mon.get("max_hp", 0)) == base_hp * 2,
		"monster HP scaled for 2 (%d -> %d)" % [base_hp, int(mon.get("max_hp", 0))])

	print("")
	print("===== 2. CONTROLS: who must NOT be dragged in =====")
	# The gate that matters. Followers only track the leader while the leader moves, so a party
	# genuinely can be split across floors, and a fight on floor 3 must not conscript someone
	# standing on floor 1 - they would be fighting something they cannot see.
	var s2 = _srv()
	var pc2 := _party(s2, 2, 0, "inst_A")
	ck(not s2._try_start_dungeon_coop(1, pc2[0], _monster(), false, 5),
		"a teammate on ANOTHER FLOOR does not join")
	ck(not s2.combat_mgr.active_party_combats.has(1), "  ...and no party combat was created")

	var s3 = _srv()
	var pc3 := _party(s3, 1, 1, "inst_OTHER")
	ck(not s3._try_start_dungeon_coop(1, pc3[0], _monster(), false, 5),
		"a teammate in a DIFFERENT INSTANCE does not join")

	var s4 = _srv()
	var pc4 := _party(s4, 1, 1, "inst_A", false)
	ck(not s4._try_start_dungeon_coop(1, pc4[0], _monster(), false, 5),
		"a teammate who never entered the dungeon does not join")

	var s5 = _srv()
	var pc5 := _party(s5, 1, 1, "inst_A")
	pc5[0].in_dungeon = false
	ck(not s5._try_start_dungeon_coop(1, pc5[0], _monster(), false, 5),
		"and an OVERWORLD leader is left to the overworld co-op path")

	print("")
	print("===== 3. VICTORY BOOKKEEPING: one grid, many characters =====")
	# The scope bug this is written to catch: the monster entity is ONE thing on ONE shared grid
	# and must die once, while cleared-counts are per character. Getting that backwards either
	# leaves the corpse standing for the second player or pays the floor out twice.
	var s6 = _srv()
	var pc6 := _party(s6, 0, 0, "inst_A")
	s6.dungeon_monsters = {"inst_A": {0: [
		{"id": 77, "alive": true, "x": 3, "y": 3, "is_boss": false},
		{"id": 78, "alive": true, "x": 9, "y": 9, "is_boss": false},
	]}}
	var ctx := {"is_boss_fight": false, "dungeon_monster_id": 77,
				"dungeon_instance_id": "inst_A", "dungeon_floor": 0, "all_members": [1, 2]}
	var before_a := int(pc6[0].dungeon_encounters_cleared)
	var before_b := int(pc6[1].dungeon_encounters_cleared)
	s6._party_dungeon_after_combat(1, [1, 2], ctx, true)
	var ents: Array = s6.dungeon_monsters["inst_A"][0]
	ck(not ents[0].alive, "the monster they fought is dead on the shared grid")
	ck(ents[1].alive, "  ...and the OTHER monster on that floor is untouched")
	ck(int(pc6[0].dungeon_encounters_cleared) == before_a + 1,
		"leader cleared count +1 exactly (got +%d)" % (int(pc6[0].dungeon_encounters_cleared) - before_a))
	ck(int(pc6[1].dungeon_encounters_cleared) == before_b + 1,
		"mate cleared count +1 exactly (got +%d)" % (int(pc6[1].dungeon_encounters_cleared) - before_b))
	ck(bool(s6.dungeon_combat_breather.get(1, false)) and bool(s6.dungeon_combat_breather.get(2, false)),
		"both get the post-fight breather, so neither is ambushed on their next step")

	print("")
	print("----- a fallen teammate gets no floor progress -----")
	var s7 = _srv()
	var pc7 := _party(s7, 0, 0, "inst_A")
	s7.dungeon_monsters = {"inst_A": {0: [{"id": 77, "alive": true, "x": 1, "y": 1, "is_boss": false}]}}
	var dead_before := int(pc7[1].dungeon_encounters_cleared)
	s7._party_dungeon_after_combat(1, [1], ctx, true)   # survivors = leader only
	ck(int(pc7[1].dungeon_encounters_cleared) == dead_before,
		"the member who fell is not credited with the clear")

	print("")
	print("----- a party WIPE kills nothing on the grid -----")
	var s8 = _srv()
	var _pc8 := _party(s8, 0, 0, "inst_A")
	s8.dungeon_monsters = {"inst_A": {0: [{"id": 77, "alive": true, "x": 1, "y": 1, "is_boss": false}]}}
	s8._party_dungeon_after_combat(1, [], ctx, false)
	ck(bool(s8.dungeon_monsters["inst_A"][0][0].alive),
		"the monster that beat the party is still standing")

	print("")
	print("===== 4. THE WIRING ITSELF - is the co-op call actually REACHED? =====")
	# Everything above calls _try_start_dungeon_coop directly, which proves the helper works and
	# proves NOTHING about whether the dungeon combat starter calls it. That gap is exactly how
	# v0.9.774's figure fix shipped twice without ever running - the code was right and sat under
	# a branch that could not run. So this drives the REAL entry point,
	# _start_dungeon_monster_combat, the same function a player's step into a monster reaches.
	var s9 = _srv()
	s9.monster_db = MonsterDB.new()
	var pc9 := _party(s9, 0, 0, "inst_A")
	pc9[0].dungeon_x = 4
	pc9[0].dungeon_y = 4
	s9.active_dungeons = {"inst_A": {"dungeon_type": "goblin_caves", "dungeon_level": 10,
									 "sub_tier": 1, "active_players": [1, 2]}}
	# dungeon_floors left empty on purpose: _send_dungeon_state returns early without it, so the
	# starter runs to the branch under test without needing a generated grid.
	var entity := {"id": 77, "monster_type": "Goblin", "level": 10, "alive": true,
				   "x": 5, "y": 4, "is_boss": false, "boss_data": {}, "is_elite": false}
	s9._start_dungeon_monster_combat(1, entity)
	ck(s9.combat_mgr.active_party_combats.has(1),
		"stepping into a dungeon monster as a party leader starts a SHARED fight")
	ck(not s9.combat_mgr.active_combats.has(1),
		"  ...and not a solo one for the leader")

	print("")
	print("----- control: the same step, alone, still starts a normal solo fight -----")
	# The counterpart check. If this one also produced a party combat, the gate would be broken
	# open rather than wired, and every solo dungeon run would be affected.
	var s10 = _srv()
	s10.monster_db = MonsterDB.new()
	var solo := _mk("Alone", "warrior")
	solo.in_dungeon = true
	solo.current_dungeon_id = "inst_A"
	solo.current_dungeon_type = "goblin_caves"
	solo.dungeon_floor = 0
	solo.dungeon_x = 4
	solo.dungeon_y = 4
	s10.characters = {1: solo}
	s10.active_dungeons = {"inst_A": {"dungeon_type": "goblin_caves", "dungeon_level": 10,
									  "sub_tier": 1, "active_players": [1]}}
	s10._start_dungeon_monster_combat(1, entity.duplicate(true))
	ck(not s10.combat_mgr.active_party_combats.has(1), "no party combat for a lone player")
	ck(s10.combat_mgr.active_combats.has(1), "  ...they get their own solo combat as before")

	print("")
	if fails == 0:
		print("PASS - a dungeon party fights one monster together, and only the right people join")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
