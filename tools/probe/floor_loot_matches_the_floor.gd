extends SceneTree
## Owner sheet 2026-10-13, items 37/42: "I'm fighting level 83 monsters on the 8th floor of this
## dungeon but the floor loot I'm finding is level 56." Monsters scale per floor by
## `dungeon_level x (1 + floor x FLOOR_DIFFICULTY_PER_FLOOR)`; floor loot was rolled at the flat
## `dungeon_level`. Builds REAL deep instances and compares, floor by floor, what the monsters are
## to what the equipment lying on that floor is.
const SERVER := preload("res://server/server.gd")
const DD = preload("res://shared/dungeon_database.gd")

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
	var by_floor_items: Dictionary = {}    # floor -> [item levels]
	var by_floor_mon: Dictionary = {}      # floor -> [monster levels]
	var by_floor_valor: Dictionary = {}    # floor -> [coin amounts]
	var made := 0
	for dt in ["balrog_depths", "cerberus_pit", "vampire_crypt", "wyvern_roost"]:
		for trial in range(6):
			var id: String = s._create_player_dungeon_instance(1, "fl_%s_%d" % [dt, trial], dt, 70, "", "", 0, 4, 4)
			if id == "":
				continue
			made += 1
			var fl_items: Dictionary = s.dungeon_floor_items.get(id, {})
			for f in fl_items.keys():
				for it in fl_items[f]:
					var d: Dictionary = it.get("item_data", {})
					if String(it.get("kind", "")) == "equipment" and d.has("level"):
						if not by_floor_items.has(f):
							by_floor_items[f] = []
						by_floor_items[f].append(int(d.level))
					elif String(it.get("kind", "")) == "valor":
						if not by_floor_valor.has(f):
							by_floor_valor[f] = []
						by_floor_valor[f].append(int(d.get("valor", 0)))
			var mons: Dictionary = s.dungeon_monsters.get(id, {})
			for f in mons.keys():
				for m in mons[f]:
					if not bool(m.get("is_boss", false)):
						if not by_floor_mon.has(f):
							by_floor_mon[f] = []
						by_floor_mon[f].append(int(m.get("level", 0)))
	print("  built %d deep instances" % made)
	var worst := 9.9
	var floors := by_floor_items.keys()
	floors.sort()
	for f in floors:
		if not by_floor_mon.has(f) or by_floor_items[f].size() < 4:
			continue
		var mi := 0.0
		for v in by_floor_items[f]:
			mi += float(v)
		mi /= by_floor_items[f].size()
		var mm := 0.0
		for v in by_floor_mon[f]:
			mm += float(v)
		mm /= by_floor_mon[f].size()
		var ratio := mi / maxf(1.0, mm)
		var coin := 0.0
		for v in by_floor_valor.get(f, [0]):
			coin += float(v)
		coin /= maxi(1, by_floor_valor.get(f, [0]).size())
		print("    floor %d: monsters avg L%.0f, equipment avg L%.0f (%.0f%%), avg coin %.1f  [n=%d items]" % [f + 1, mm, mi, ratio * 100.0, coin, by_floor_items[f].size()])
		if f >= 2:
			worst = minf(worst, ratio)
	ck(worst >= 0.9, "from floor 3 down, equipment is within 10%% of the monsters it sits beside (worst %.0f%%)" % (worst * 100.0))
	s.free()
	print("\n[FLOORLOOT] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
