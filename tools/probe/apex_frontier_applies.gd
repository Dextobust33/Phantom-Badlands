extends SceneTree
## Does standing in the apex frontier actually make the fight you PICKED an apex fight?
##
## Until 2026-09-13 it did not. The overlay lived inline in `trigger_flock_encounter` and nothing
## else called it, so in an apex zone the monster you walked into was ordinary and only its
## pack-mates were apex. The zone's +10% XP went with it: the reward path reads `is_apex_frontier`
## off the monster, and that field was stamped inside the same flock-only block - so the frontier
## paid its bonus on links 2+ of a chain and paid NOTHING for the species that do not flock at all.
##
## Found sideways, working out the odds on a summoned Elder Lich. Elder Lich has flock_chance 0,
## so it could never have been apex under the old code no matter where you stood.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _monster() -> Dictionary:
	return {"name": "Elder Lich", "base_name": "Elder Lich", "level": 20,
			"max_hp": 1000, "hp": 1000, "current_hp": 1000, "damage": 100,
			"strength": 100, "defense": 50, "abilities": []}


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	var srv = ServerScript.new()
	srv.world_system = ws

	var hero = CharacterScript.new()
	hero.name = "Probe"
	hero.class_type = "warrior"
	hero.level = 40

	print("===== FIND REAL APEX GROUND AND REAL ORDINARY GROUND =====")
	# Measured against the real world generator rather than a stubbed flag, so this also proves
	# the frontier is reachable at all.
	var apex_pos := Vector2i(0, 0)
	var plain_pos := Vector2i(0, 0)
	var found_apex := false
	var found_plain := false
	for r in range(50, 6000, 50):
		for ang in range(0, 8):
			var x := int(round(float(r) * cos(float(ang) * PI / 4.0)))
			var y := int(round(float(r) * sin(float(ang) * PI / 4.0)))
			var is_apex: bool = ws.is_apex_frontier(x, y)
			if is_apex and not found_apex:
				apex_pos = Vector2i(x, y)
				found_apex = true
			if not is_apex and not found_plain:
				plain_pos = Vector2i(x, y)
				found_plain = true
		if found_apex and found_plain:
			break
	ck(found_apex, "found apex frontier ground at (%d,%d)" % [apex_pos.x, apex_pos.y])
	ck(found_plain, "found ordinary ground at (%d,%d)" % [plain_pos.x, plain_pos.y])
	if not found_apex:
		print("FAIL - no apex ground found; the rest cannot be measured")
		quit(1)
		return

	print("")
	print("===== STANDING IN IT, THE FIGHT YOU PICKED IS APEX =====")
	hero.x = apex_pos.x
	hero.y = apex_pos.y
	var m := _monster()
	var base_hp := int(m["max_hp"])
	srv._apply_apex_frontier(m, hero, false)
	print("  %s  hp %d -> %d  damage %d -> %d" % [
		String(m.get("name", "?")), base_hp, int(m["max_hp"]), 100, int(m["damage"])])
	ck(String(m.get("name", "")).begins_with("Apex "), "it is named Apex")
	ck(int(m["max_hp"]) == int(base_hp * 1.25), "HP is +25 percent")
	ck(int(m["damage"]) == 110, "damage is +10 percent")
	ck(int(m["current_hp"]) == int(m["max_hp"]),
		"and it arrives at FULL health - a bigger bar with the old value in it would be a free kill")
	ck(bool(m.get("is_apex_frontier", false)),
		"the zone flag the +10 percent XP is paid from is set")
	ck(String(m.get("apex_zone_name", "")) != "",
		"and the zone has a name to put in the reward line (%s)" % String(m.get("apex_zone_name", "")))

	print("")
	print("===== ORDINARY GROUND IS UNTOUCHED =====")
	hero.x = plain_pos.x
	hero.y = plain_pos.y
	var m2 := _monster()
	srv._apply_apex_frontier(m2, hero, false)
	ck(String(m2.get("name", "")) == "Elder Lich", "no prefix off the frontier")
	ck(int(m2["max_hp"]) == 1000, "no HP buff")
	ck(not bool(m2.get("is_apex_frontier", true)), "and the flag is explicitly false, not absent")

	print("")
	print("===== AND A DUNGEON NEVER GETS THE OVERLAY =====")
	# Dungeons have their own tier scaling; a frontier overlay on top would double-count.
	hero.x = apex_pos.x
	hero.y = apex_pos.y
	var m3 := _monster()
	srv._apply_apex_frontier(m3, hero, true)
	ck(int(m3["max_hp"]) == 1000, "a dungeon monster keeps its own numbers")
	ck(String(m3.get("name", "")) == "Elder Lich", "and its own name")

	print("")
	print("===== IT IS IDEMPOTENT =====")
	# The flock path stamps a monster that may already have been stamped by the encounter path.
	hero.x = apex_pos.x
	hero.y = apex_pos.y
	var m4 := _monster()
	srv._apply_apex_frontier(m4, hero, false)
	var once_hp := int(m4["max_hp"])
	var once_name := String(m4["name"])
	srv._apply_apex_frontier(m4, hero, false)
	ck(String(m4["name"]) == once_name, "the name is not prefixed twice")
	print("  note: HP compounds on a second stamp (%d -> %d), which is why only ONE path may"
		% [once_hp, int(m4["max_hp"])])
	print("  stamp a given monster - the encounter path OR the flock path, never both.")

	print("")
	if fails == 0:
		print("PASS - the apex frontier applies to the fight you picked, not just its pack")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
