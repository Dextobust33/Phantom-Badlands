extends SceneTree
## Playtest sheet item 50, slice 3 (owner 2026-10-14): gold dies with the character, but "a portion of
## it can be found on the corpse, as well as gems". Same 10-50% rule for both, rolled.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")
const Gold = preload("res://shared/gold_economy.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class QuietPM extends "res://server/persistence_manager.gd":
	func save_corpses() -> void:
		pass   # never write a probe corpse into the real corpse file
class QuietServer extends "res://server/server.gd":
	func save_character(_p) -> void:
		pass
class StubConn:
	func get_status() -> int:
		return 0

func _hero(nm: String, gold: int, gems: int):
	var c = CharacterScript.new()
	c.initialize(nm, "Fighter", "Human")
	c.level = 30
	c.gold_purse = gold
	c.crafting_materials["monster_gem"] = gems
	return c

func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws
	var pm = QuietPM.new()
	get_root().add_child(pm)
	await process_frame
	var srv = QuietServer.new()
	srv.world_system = ws
	srv.chunk_manager = cm
	srv.persistence = pm
	srv.drop_tables = load("res://shared/drop_tables.gd").new()
	get_root().add_child(srv.drop_tables)
	srv.trading_post_db = load("res://shared/trading_post_database.gd").new()
	get_root().add_child(srv.trading_post_db)

	# the share rule
	var lo := 1000000
	var hi := 0
	for i in 400:
		var g: int = Gold.corpse_share(10000)
		lo = mini(lo, g)
		hi = maxi(hi, g)
	ck(lo >= 1000 and hi <= 5000 and hi > lo, "the share is a roll inside 10-50%% (saw %d..%d of 10,000)" % [lo, hi])
	ck(Gold.corpse_share(0) == 0 and Gold.corpse_share(-5) == 0, "nothing in, nothing out")

	# a death leaves part of the purse AND of the gems on the body
	var dead = _hero("Doomed", 20000, 40)
	var corpse: Dictionary = srv._create_corpse_from_character(dead, "a Wolf")
	var ct: Dictionary = corpse.get("contents", {})
	ck(not corpse.is_empty(), "a corpse is made")
	var cg: int = int(ct.get("gold", -1))
	ck(cg >= 2000 and cg <= 10000, "gold on the corpse is 10-50%% of the purse (%d of 20,000)" % cg)
	var cgem: int = int(ct.get("monster_gems", -1))
	ck(cgem >= 4 and cgem <= 20, "gems still follow the same rule (%d of 40)" % cgem)
	# a purse alone is reason enough to leave a corpse
	var broke_but_rich = _hero("Purse", 5000, 0)
	var c2: Dictionary = srv._create_corpse_from_character(broke_but_rich, "a Wolf")
	ck(not c2.is_empty() and int(c2.contents.gold) > 0, "a body with only gold still leaves a corpse")
	var empty = _hero("Nothing", 0, 0)
	ck(srv._create_corpse_from_character(empty, "a Wolf").is_empty(), "nothing at all leaves none")

	# looting pays it out
	var finder = _hero("Finder", 100, 0)
	finder.x = int(corpse.x)
	finder.y = int(corpse.y)
	srv.characters = {7: finder}
	srv.peers = {7: {"authenticated": true, "account_id": "a", "connection": StubConn.new()}}
	pm.add_corpse(corpse)
	srv.handle_loot_corpse(7, {"corpse_id": corpse.id})
	ck(finder.gold_purse == 100 + cg, "looting adds the gold to the finder's purse (%d)" % finder.gold_purse)
	ck(int(finder.crafting_materials.get("monster_gem", 0)) == cgem, "...and the gems")
	ck(pm.get_corpse_at(finder.x, finder.y).is_empty(), "the corpse is gone")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
