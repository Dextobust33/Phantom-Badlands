extends SceneTree
## Dungeon rarity, axis three: rarer monsters, and a guaranteed unique at the top.
##
## Owner 2026-09-13 picked all three axes. This is the last one: "rarer monsters / a guaranteed
## unique". The guarantee is the point of rank 9 - the jump from 40% to 100% is deliberate, not a
## table that got away from someone.
##
## The gap this closed was bigger than the feature. Co-op party combat rolled NO uniques at all -
## a party could kill anything in the game and the rarest reward would simply never be checked
## for. That was already true of every party fight in the world, and enabling party dungeon
## combat the same day would have made "bring a friend" the way to guarantee you never see one.
const ServerScript = preload("res://server/server.gd")
const MonsterDB = preload("res://shared/monster_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv = ServerScript.new()
	srv.monster_db = MonsterDB.new()

	print("===== THE UNIQUE CHANCE, ONE DEFINITION =====")
	print("  %-6s %14s %14s" % ["rank", "boss kill", "ordinary kill"])
	for rank in [1, 3, 5, 7, 8, 9]:
		print("  %-6d %13.2f%% %13.2f%%" % [rank,
			srv._unique_drop_chance(0, true, rank), srv._unique_drop_chance(0, false, rank)])
	ck(srv._unique_drop_chance(0, true, 9) >= 100.0,
		"a rank-9 dungeon boss ALWAYS hands back a unique - the reward the owner chose for the top")
	ck(srv._unique_drop_chance(0, true, 8) < 50.0,
		"rank 8 does not (%.0f%%), so the last step is worth taking" % srv._unique_drop_chance(0, true, 8))
	ck(srv._unique_drop_chance(0, false, 9) < 1.0,
		"an ordinary monster in a rank-9 dungeon is still not a slot machine (%.2f%%)"
			% srv._unique_drop_chance(0, false, 9))

	print("")
	print("----- the world outside a dungeon is unchanged -----")
	# A refactor that quietly moved the overworld boss number would be a balance change nobody
	# asked for, hidden inside a dungeon feature.
	ck(abs(srv._unique_drop_chance(0, true, 1) - 2.75) < 0.001,
		"a world boss is still 2.75%% (0.25 base + 2.5 boss) - got %.2f%%"
			% srv._unique_drop_chance(0, true, 1))
	ck(abs(srv._unique_drop_chance(3, false, 1) - 2.5) < 0.001,
		"a 3-modifier elite is still 2.5%% - got %.2f%%" % srv._unique_drop_chance(3, false, 1))
	ck(srv._unique_drop_chance(3, false, 9) == srv._unique_drop_chance(3, false, 1),
		"and rank does NOT leak onto ordinary kills - only the boss row moves")

	print("")
	print("===== RARER MONSTERS: EMPOWERED DENSITY BY RANK =====")
	print("  %-6s %10s" % ["rank", "empowered"])
	var r1_share := 0.0
	var r9_share := 0.0
	for rank in [1, 3, 5, 7, 9]:
		var got := 0
		var n := 4000
		for i in range(n):
			var m := {"name": "Ghoul", "base_name": "Ghoul", "max_hp": 500, "strength": 50,
					  "defense": 20, "abilities": [], "empowered_mods": [], "is_boss": false}
			srv._empower_for_dungeon_rank(m, rank)
			if not (m.get("empowered_mods", []) as Array).is_empty():
				got += 1
		var share := float(got) / float(n)
		print("  %-6d %9.1f%%" % [rank, share * 100.0])
		if rank == 1:
			r1_share = share
		if rank == 9:
			r9_share = share
	ck(r1_share == 0.0, "a rank-1 dungeon adds nothing - its monsters are whatever they rolled")
	ck(r9_share > 0.35 and r9_share < 0.55,
		"a rank-9 dungeon empowers %.0f%% of what it holds" % (r9_share * 100.0))

	print("")
	print("----- and it never doubles up on a monster that is already Empowered -----")
	# The base roll and this one are two routes to the same state. Applying both would compound a
	# monster the calibration never saw, and the prefix would stack twice in its name.
	var already := {"name": "Frenzied Ghoul", "base_name": "Ghoul", "max_hp": 500, "strength": 50,
					"defense": 20, "abilities": [], "empowered_mods": ["frenzied"], "is_boss": false}
	var hp_before := int(already["max_hp"])
	for i in range(200):
		srv._empower_for_dungeon_rank(already, 9)
	ck((already.get("empowered_mods", []) as Array).size() == 1,
		"200 passes over an Empowered monster left it with exactly one modifier")
	ck(int(already["max_hp"]) == hp_before, "and its stats were not touched")

	print("")
	print("----- a boss is left alone -----")
	var boss := {"name": "Ghoul King", "base_name": "Ghoul King", "max_hp": 9000, "strength": 300,
				 "defense": 100, "abilities": [], "empowered_mods": [], "is_boss": true}
	for i in range(500):
		srv._empower_for_dungeon_rank(boss, 9)
	ck((boss.get("empowered_mods", []) as Array).is_empty(),
		"a boss carries its own multipliers and is not empowered on top of them")

	print("")
	print("===== THE TWO AXES COMPOUND, ON PURPOSE =====")
	# Every Empowered modifier is +0.75% on the unique roll, so a rarer dungeon is populated by
	# rarer monsters which are themselves likelier to hand something back. Worth stating as a
	# measured number rather than an intention.
	var plain := srv._unique_drop_chance(0, false, 1)
	var emp := srv._unique_drop_chance(1, false, 9)
	print("  ordinary kill, rank 1, no modifier: %.2f%%" % plain)
	print("  ordinary kill, rank 9, one modifier it got FROM the rank: %.2f%%" % emp)
	ck(emp > plain, "the rarer place makes its ordinary kills likelier to pay too")

	print("")
	print("===== THE CO-OP PATH ACTUALLY ROLLS THEM =====")
	# The whole point of this axis is that it works when you bring someone. Driving the real
	# _end_party_combat_all rather than trusting the call site: the shared chance function being
	# right says nothing about whether co-op asks it, which is the gap that let the v0.9.774
	# figure fix ship twice under a branch that could not run.
	srv.drop_tables = load("res://shared/drop_tables.gd").new()
	get_root().add_child(srv.drop_tables)
	srv.combat_mgr = load("res://shared/combat_manager.gd").new()
	srv.combat_mgr.set_drop_tables(srv.drop_tables)
	srv.combat_mgr.set_monster_database(srv.monster_db)
	var CharacterScript = load("res://shared/character.gd")
	var heroes := {}
	for pid in [1, 2]:
		var c = CharacterScript.new()
		c.name = "Hero%d" % pid
		c.class_type = "warrior"
		c.level = 40
		c.current_hp = c.get_total_max_hp()
		heroes[pid] = c
	srv.characters = heroes
	srv.active_parties = {1: {"leader": 1, "members": [1, 2], "formed_at": 0}}
	srv.party_membership = {1: 1, 2: 1}
	srv.active_dungeons = {"inst9": {"sub_tier": 9, "modifiers": []}}
	var boss_mon := {"name": "Ghoul King", "base_name": "Ghoul King", "level": 40,
					 "max_hp": 9000, "current_hp": 0, "strength": 300, "defense": 100,
					 "speed": 10, "experience_reward": 5000, "abilities": [],
					 "empowered_mods": [], "flock_chance": 0, "is_boss": true}
	srv.combat_mgr.start_party_combat_simul([1, 2], heroes, boss_mon)
	var pc: Dictionary = srv.combat_mgr.active_party_combats[1]
	pc["is_dungeon_combat"] = true
	pc["is_boss_fight"] = true
	pc["dungeon_monster_id"] = -1
	pc["dungeon_instance_id"] = "inst9"
	pc["dungeon_floor"] = 0
	# in_dungeon left FALSE on purpose: the completion/teleport path is a separate concern with a
	# much heavier harness, and leaving it out keeps this measuring the unique roll and nothing
	# else. The dungeon CONTEXT is what the roll reads, and that is set above.
	srv._end_party_combat_all(1, true, [])
	# A "named drop" is a unique OR a set piece - random_named_drop_id() draws from one pool of
	# 15 uniques and 9 set pieces. The first version of this check looked only for `is_unique`
	# and reported a FAILURE when the leader was handed Magpie's Claw, which is a set piece and
	# carries `is_set_piece`/`set_id` instead. The feature was working; the detector was reading
	# one of the two shapes it can return.
	var got := {1: false, 2: false}
	for pid in [1, 2]:
		print("    Hero%d inventory (%d):" % [pid, srv.characters[pid].inventory.size()])
		for it in srv.characters[pid].inventory:
			var named: bool = (bool(it.get("is_unique", false)) or bool(it.get("is_set_piece", false))
				or String(it.get("unique_id", "")) != "" or String(it.get("set_id", "")) != "")
			print("      %s | named=%s rarity=%s" % [
				String(it.get("name", "?")), str(named), String(it.get("rarity", ""))])
			if named:
				got[pid] = true
	print("  leader got a unique: %s   member got a unique: %s" % [str(got[1]), str(got[2])])
	ck(got[1] and got[2],
		"clearing a rank-9 dungeon boss in a PARTY hands EVERY member a named item")

	print("")
	if fails == 0:
		print("PASS - rank buys rarer monsters, and the top of the ladder guarantees a unique")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
