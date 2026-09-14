extends SceneTree
## Party flocks: chain on the overworld, never in a dungeon, and nobody loses banked loot.
##
## Owner 2026-09-13: *"Party flocks should happen in party play on the overworld but not in
## dungeons as those encounters are visible on the map."* The dungeon half is the load-bearing
## one - a fight that conjures an unseen second monster contradicts the floor grid the player is
## reading - so it is asserted here at a flock chance of 100, where any leak shows up every run
## rather than one time in four.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const CombatMgr = preload("res://shared/combat_manager.gd")
const MonsterDB = preload("res://shared/monster_database.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const QuestDB = preload("res://shared/quest_database.gd")
const QuestMgr = preload("res://shared/quest_manager.gd")
##
## Harness note: the overworld sections print a SCRIPT ERROR from send_location_update, which
## wants a corpse_manager this probe does not build. It fires AFTER the state under test is
## settled - every assertion below still reads real post-fight state. Do not read those lines as
## failures.
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

var _ws = null

func _srv() -> Node:
	var s = ServerScript.new()
	s.combat_mgr = CombatMgr.new()
	s.monster_db = MonsterDB.new()
	s.drop_tables = DropTablesScript.new()
	s.quest_db = QuestDB.new()
	s.quest_mgr = QuestMgr.new()
	s.combat_mgr.set_drop_tables(s.drop_tables)
	s.combat_mgr.set_monster_database(s.monster_db)
	s.world_system = _ws
	return s


func _mk(nm: String, cls: String) -> Character:
	var c = CharacterScript.new()
	c.name = nm
	c.class_type = cls
	c.level = 40          # >= 25, so flock_scale_for_level is exactly 1.0 and the roll is honest
	c.current_hp = c.get_total_max_hp()
	return c


func _monster(flock_chance: int) -> Dictionary:
	return {
		"name": "Wolf", "base_name": "Wolf", "level": 40, "max_hp": 500, "current_hp": 0,
		"strength": 30, "defense": 15, "speed": 12, "experience_reward": 100,
		"abilities": [], "flock_chance": flock_chance, "variant_type": "", "empowered_mods": [],
	}


func _fight(s, mon: Dictionary, dungeon: bool) -> void:
	"""Put a real 2-hero co-op fight into the combat manager, won."""
	var a := _mk("Leader", "warrior")
	var b := _mk("Mate", "mage")
	s.characters = {1: a, 2: b}
	s.active_parties = {1: {"leader": 1, "members": [1, 2], "formed_at": 0}}
	s.party_membership = {1: 1, 2: 1}
	s.combat_mgr.start_party_combat_simul([1, 2], {1: a, 2: b}, mon)
	if dungeon:
		var pc: Dictionary = s.combat_mgr.active_party_combats[1]
		pc["is_dungeon_combat"] = true
		pc["is_boss_fight"] = false
		pc["dungeon_monster_id"] = -1
		pc["dungeon_instance_id"] = "inst_A"
		pc["dungeon_floor"] = 0
		a.in_dungeon = true
		b.in_dungeon = true
		a.current_dungeon_id = "inst_A"
		b.current_dungeon_id = "inst_A"


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	_ws = WorldSystemScript.new()
	get_root().add_child(_ws)
	_ws.chunk_manager = cm
	cm.terrain_generator = _ws

	print("===== THE CHANCE IS DEFINED ONCE =====")
	# It is not the monster's raw flock_chance: Pack Leader adds 25 capped at 75, and the level
	# ramp scales the result. A second hand-copied version in the co-op path would be wrong twice
	# over and wrong differently at every level.
	ck(CombatMgr.compute_flock_chance(_monster(40), 40) == 40,
		"a plain species number passes through at L40 (ramp is 1.0 by L25)")
	ck(CombatMgr.compute_flock_chance(_monster(40), 1) == 14,
		"the same monster is far tamer at L1 (14, the 0.35 ramp) - the early game is not the chain")
	var packy := _monster(40)
	packy["abilities"] = [CombatMgr.ABILITY_PACK_LEADER]
	ck(CombatMgr.compute_flock_chance(packy, 40) == 65, "Pack Leader adds 25")
	var packy2 := _monster(60)
	packy2["abilities"] = [CombatMgr.ABILITY_PACK_LEADER]
	ck(CombatMgr.compute_flock_chance(packy2, 40) == 75, "and the +25 is capped at 75")

	print("")
	print("===== OVERWORLD: THE CHAIN STARTS =====")
	var s1 = _srv()
	_fight(s1, _monster(100), false)
	s1._end_party_combat_all(1, true, [])
	ck(s1.pending_flocks.has(1), "a chain is queued on the leader")
	var pf: Dictionary = s1.pending_flocks.get(1, {})
	ck(bool(pf.get("party", false)), "  ...marked as a PARTY chain, so continue does not start a solo fight")
	ck((pf.get("members", []) as Array).size() == 2, "  ...carrying both survivors")
	ck(s1.pending_flock_drops.has(1) and s1.pending_flock_drops.has(2),
		"each member has a bank open - in co-op everyone rolls their own loot")

	print("")
	print("===== DUNGEON: THE CHAIN MUST NOT START =====")
	# Same monster, same 100% chance. The only difference is where they are standing.
	var s2 = _srv()
	_fight(s2, _monster(100), true)
	s2._end_party_combat_all(1, true, [])
	ck(not s2.pending_flocks.has(1),
		"no chain in a dungeon even at a 100% flock chance - the grid shows what is there")
	ck(not s2.pending_flock_drops.has(1),
		"  ...and nothing is withheld, so the fight pays out on the spot")

	print("")
	print("===== THE CHAIN ENDS: BANKED LOOT IS PAID =====")
	var s3 = _srv()
	_fight(s3, _monster(0), false)          # 0% - this is the last link
	# Bank a known item for each member, as earlier links would have.
	s3.pending_flock_drops = {
		1: [{"type": "crafting_material", "material_id": "iron_ore", "quantity": 3}],
		2: [{"type": "crafting_material", "material_id": "iron_ore", "quantity": 2}],
	}
	var before1: int = int(s3.characters[1].crafting_materials.get("iron_ore", 0))
	s3._end_party_combat_all(1, true, [])
	ck(not s3.pending_flocks.has(1), "no new chain at 0% chance")
	ck(s3.pending_flock_drops.is_empty(), "every bank was emptied")
	ck(int(s3.characters[1].crafting_materials.get("iron_ore", 0)) >= before1 + 3,
		"the leader actually received what was held for them (%d ore)"
			% int(s3.characters[1].crafting_materials.get("iron_ore", 0)))
	ck(int(s3.characters[2].crafting_materials.get("iron_ore", 0)) >= 2,
		"and so did the member, from their OWN bank (%d ore)"
			% int(s3.characters[2].crafting_materials.get("iron_ore", 0)))

	print("")
	print("===== CONTINUE: the next link is another SHARED fight =====")
	var s4 = _srv()
	var a4 := _mk("Leader", "warrior")
	var b4 := _mk("Mate", "mage")
	s4.characters = {1: a4, 2: b4}
	s4.active_parties = {1: {"leader": 1, "members": [1, 2], "formed_at": 0}}
	s4.party_membership = {1: 1, 2: 1}
	s4.pending_flocks = {1: {"party": true, "members": [1, 2], "monster_name": "Wolf",
							 "monster_level": 40, "variant_type": "", "empowered_mods": [],
							 "flock_count": 1}}
	s4.handle_continue_flock(1)
	ck(s4.combat_mgr.active_party_combats.has(1), "pressing Continue starts one shared fight")
	ck((s4.combat_mgr.active_party_combats[1].get("members", []) as Array).size() == 2,
		"  ...with both of them in it")
	ck(not s4.combat_mgr.active_combats.has(2), "  ...and nobody split off into a private fight")

	print("")
	print("----- a member who cannot come is PAID, not forgotten -----")
	# Losing a fight's drops to a disconnect and never learning why is the failure this guards.
	var s5 = _srv()
	var a5 := _mk("Leader", "warrior")
	var b5 := _mk("Mate", "mage")
	s5.characters = {1: a5, 2: b5}
	s5.active_parties = {1: {"leader": 1, "members": [1, 2], "formed_at": 0}}
	s5.party_membership = {1: 1, 2: 1}
	b5.in_combat = true                     # stuck in something else: cannot join the next link
	s5.pending_flock_drops = {2: [{"type": "crafting_material", "material_id": "iron_ore", "quantity": 7}]}
	s5.pending_flocks = {1: {"party": true, "members": [1, 2], "monster_name": "Wolf",
							 "monster_level": 40, "variant_type": "", "empowered_mods": [],
							 "flock_count": 1}}
	s5.handle_continue_flock(1)
	ck(int(b5.crafting_materials.get("iron_ore", 0)) == 7,
		"the left-behind member got their banked loot (%d ore)" % int(b5.crafting_materials.get("iron_ore", 0)))
	ck(not s5.pending_flock_drops.has(2), "  ...and their bank was closed, not left dangling")

	print("")
	if fails == 0:
		print("PASS - flocks chain for a party outside, and never inside a dungeon")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
