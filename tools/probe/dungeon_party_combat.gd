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
const DungeonDB = preload("res://shared/dungeon_database.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const QuestDB = preload("res://shared/quest_database.gd")
const QuestMgr = preload("res://shared/quest_manager.gd")

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
	s.monster_db = MonsterDB.new()
	s.drop_tables = DropTablesScript.new()
	s.quest_db = QuestDB.new()
	s.quest_mgr = QuestMgr.new()
	s.combat_mgr.set_drop_tables(s.drop_tables)
	s.combat_mgr.set_monster_database(s.monster_db)
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
	print("===== 5. THE BOSS: completion runs ONCE, not once per member =====")
	# The expensive mistake available here. _complete_dungeon already rewards and exits every
	# follower itself, so calling it per member would pay the whole party out once per person -
	# each follower collecting the clear rewards two, three, five times over. It is called for
	# ONE player, and this proves which one.
	var s11 = _srv()
	var pc11 := _party(s11, 0, 0, "inst_A")
	for ch in pc11:
		ch.dungeon_x = 3
		ch.dungeon_y = 3
	s11.active_dungeons = {"inst_A": {"dungeon_type": "goblin_caves", "dungeon_level": 10,
									  "sub_tier": 1, "active_players": [1, 2]}}
	var grid: Array = []
	for _y in range(7):
		var row: Array = []
		for _x in range(7):
			row.append(DungeonDB.TileType.EMPTY)
		grid.append(row)
	s11.dungeon_floors = {"inst_A": [grid]}
	s11.dungeon_monsters = {"inst_A": {0: [{"id": 99, "alive": true, "x": 3, "y": 4, "is_boss": true}]}}
	var bctx := {"is_boss_fight": true, "dungeon_monster_id": 99,
				 "dungeon_instance_id": "inst_A", "dungeon_floor": 0, "all_members": [1, 2]}
	s11._party_dungeon_after_combat(1, [1, 2], bctx, true)
	ck(not s11.dungeon_monsters["inst_A"][0][0].alive, "the boss is dead on the shared grid")
	ck(s11.pending_final_chest.size() == 1,
		"completion ran for exactly ONE player, not once each (got %d)" % s11.pending_final_chest.size())
	ck(s11.pending_final_chest.has(1), "  ...and it was the leader")

	print("")
	print("----- and if the leader fell in the boss fight, the survivors still get out -----")
	# A party that wins but loses its leader must not be sealed in.
	var s12 = _srv()
	var pc12 := _party(s12, 0, 0, "inst_A")
	for ch in pc12:
		ch.dungeon_x = 3
		ch.dungeon_y = 3
	s12.active_dungeons = {"inst_A": {"dungeon_type": "goblin_caves", "dungeon_level": 10,
									  "sub_tier": 1, "active_players": [1, 2]}}
	var grid2: Array = []
	for _y in range(7):
		var row2: Array = []
		for _x in range(7):
			row2.append(DungeonDB.TileType.EMPTY)
		grid2.append(row2)
	s12.dungeon_floors = {"inst_A": [grid2]}
	s12.dungeon_monsters = {"inst_A": {0: [{"id": 99, "alive": true, "x": 3, "y": 4, "is_boss": true}]}}
	# NOTE: this one prints a SCRIPT ERROR from send_location_update, which wants a world_system
	# the harness has no cheap way to build. It fires AFTER the exit, so the assertion below is
	# still meaningful - but do not read that line as a failure.
	s12._party_dungeon_after_combat(1, [2], bctx, true)   # only the follower survived
	ck(not s12.characters[2].in_dungeon,
		"the surviving member is let out rather than sealed in")
	# And the difference worth knowing about: a survivor who is not the leader gets an IMMEDIATE
	# completion, no final chest, because _try_spawn_final_chest refuses non-leaders on the
	# grounds that "the leader's chest covers the party". When the leader is dead there is no
	# such chest. Pre-existing, recorded rather than quietly changed.
	ck(s12.pending_final_chest.is_empty(),
		"  ...though without a final chest, since only the leader can place one")

	print("")
	print("===== 6. A LONE NEW PLAYER IN THE STARTER DUNGEON IS ESCORTED =====")
	# The onboarding guide rides this same party machinery. A brand-new character walking into
	# the starter dungeon alone should end up in a TWO-member fight, with the guide listed as an
	# NPC so it neither scales the monster nor leaves the player to take every hit.
	var sg1 = _srv()
	var newbie := _mk("Newbie", "warrior")
	newbie.level = 1
	newbie.in_dungeon = true
	newbie.current_dungeon_id = "starter1"
	newbie.current_dungeon_type = "goblin_caves"
	newbie.dungeon_floor = 0
	newbie.dungeon_x = 4
	newbie.dungeon_y = 4
	sg1.characters = {1: newbie}
	sg1.active_dungeons = {"starter1": {"dungeon_type": "goblin_caves", "dungeon_level": 2,
										"sub_tier": 1, "tier": 1, "starter": true,
										"active_players": [1], "modifiers": []}}
	var ent2 := {"id": 5, "monster_type": "Goblin", "level": 2, "alive": true,
				 "x": 5, "y": 4, "is_boss": false, "boss_data": {}, "is_elite": false}
	sg1._start_dungeon_monster_combat(1, ent2)
	ck(sg1.combat_mgr.active_party_combats.has(1),
		"a lone level-1 in the starter dungeon gets a PARTY fight, not a solo one")
	var gc: Dictionary = sg1.combat_mgr.active_party_combats.get(1, {})
	ck((gc.get("members", []) as Array).size() == 2, "  ...with two members in it")
	ck((gc.get("npc_members", []) as Array).size() == 1,
		"  ...one of whom is flagged as an NPC, so it will not inflate the monster")
	ck(int((gc.get("npc_members", []) as Array)[0]) == sg1._guide_peer_id(1),
		"  ...and that NPC is the guide")

	print("")
	print("----- the guide acts on its own each round -----")
	# submit_party_action is pure state, so the server can act for a member with no socket.
	# Without this the round would wait forever for a client that does not exist.
	var before_sub: bool = bool(gc.get("member_states", {}).get(sg1._guide_peer_id(1), {}).get("submitted_this_round", false))
	sg1._guide_fill_action(1)
	var after_sub: bool = bool(gc.get("member_states", {}).get(sg1._guide_peer_id(1), {}).get("submitted_this_round", false))
	ck(not before_sub and after_sub, "the guide submits an action when asked to")

	print("")
	print("----- and an ORDINARY dungeon gets no escort -----")
	var sg2 = _srv()
	var vet := _mk("Veteran", "warrior")
	vet.level = 40
	vet.in_dungeon = true
	vet.current_dungeon_id = "normal1"
	vet.current_dungeon_type = "goblin_caves"
	vet.dungeon_floor = 0
	vet.dungeon_x = 4
	vet.dungeon_y = 4
	sg2.characters = {1: vet}
	sg2.active_dungeons = {"normal1": {"dungeon_type": "goblin_caves", "dungeon_level": 20,
									   "sub_tier": 3, "tier": 1, "active_players": [1],
									   "modifiers": []}}
	sg2._start_dungeon_monster_combat(1, ent2.duplicate(true))
	ck(not sg2.combat_mgr.active_party_combats.has(1),
		"no guide outside the starter dungeon - it is tutorial content, not a permanent ally")
	ck(sg2.combat_mgr.active_combats.has(1), "  ...they get their normal solo fight")

	print("")
	if fails == 0:
		print("PASS - a dungeon party fights one monster together, and only the right people join")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
