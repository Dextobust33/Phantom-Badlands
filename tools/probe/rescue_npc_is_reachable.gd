extends SceneTree
## Owner sheet 2026-10-13, item 1: "Rescue the Scholar quest isn't actually spawning the scholar in
## the Dungeon". Builds REAL rescue instances (the same two calls `handle_quest_accept` makes) across
## dungeon types and floors, then measures where the NPC actually ended up.
const SERVER := preload("res://server/server.gd")
const DD = preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _reachable(grid: Array, from: Vector2i, to: Vector2i) -> bool:
	var seen := {from: true}
	var q: Array = [from]
	var wall: int = int(DD.TileType.WALL)
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == to:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < 0 or n.y >= grid.size() or n.x < 0 or n.x >= grid[0].size():
				continue
			if seen.has(n) or int(grid[n.y][n.x]) == wall:
				continue
			seen[n] = true
			q.append(n)
	return false

func _init() -> void:
	var s = SERVER.new()
	s.world_system = WorldSystem.new()
	s.trading_post_db = load("res://shared/trading_post_database.gd").new()
	s.monster_db = MonsterDatabase.new()
	s.drop_tables = load("res://shared/drop_tables.gd").new()
	var total := 0
	var unreachable := 0
	var on_special := 0
	var shared_tile := 0
	var missing := 0
	var examples: Array = []
	for dt in ["goblin_caves", "wolf_den", "wyvern_roost", "vampire_crypt", "ogre_bog", "balrog_depths"]:
		if DD.get_dungeon(dt).is_empty():
			continue
		for fl in [1, 2, 3]:
			for trial in range(3):
				var id: String = s._create_player_dungeon_instance(1, "rq_%s_%d_%d" % [dt, fl, trial], dt, 30, "", "", 0, 2, 3)
				if id == "":
					continue
				s._spawn_rescue_npc(id, fl, "scholar", "rq")
				total += 1
				var npcs: Dictionary = s.dungeon_npcs.get(id, {})
				if npcs.is_empty():
					missing += 1
					continue
				var fnum: int = int(npcs.keys()[0])
				var npc: Dictionary = npcs[fnum]
				var grid: Array = s.dungeon_floors[id][fnum]
				var p := Vector2i(int(npc.x), int(npc.y))
				var ent: Vector2i = s._find_tile_position(grid, DD.TileType.ENTRANCE)
				if not _reachable(grid, ent, p):
					unreachable += 1
					if examples.size() < 4:
						examples.append("%s floor %d: NPC at %s unreachable from entrance %s" % [dt, fnum, str(p), str(ent)])
				var tv: int = int(grid[p.y][p.x])
				if tv != int(DD.TileType.EMPTY):
					on_special += 1
					if examples.size() < 6:
						examples.append("%s floor %d: NPC stands on tile type %d" % [dt, fnum, tv])
				for m in s.dungeon_monsters.get(id, {}).get(fnum, []):
					if int(m.x) == p.x and int(m.y) == p.y and bool(m.get("alive", true)):
						shared_tile += 1
						break
	print("  built %d rescue instances" % total)
	for e in examples:
		print("      e.g. %s" % e)
	ck(missing == 0, "every rescue instance has its NPC (%d missing)" % missing)
	ck(unreachable == 0, "every NPC can be walked to from the entrance (%d unreachable)" % unreachable)
	ck(on_special == 0, "no NPC stands on stairs/exit/special tiles (%d did)" % on_special)
	ck(shared_tile == 0, "no NPC shares a tile with a monster (%d did)" % shared_tile)
	s.free()
	print("\n[RESCUENPC] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
