extends SceneTree
## The tile cache must be INVISIBLE: same world, same map, and a player's edit still wins.
##
## 2026-09-11. `get_tile` regenerated every tile on every call and, for any chunk with no player
## edits, also ran `FileAccess.file_exists` - ~1,390 disk stats per player move. Caching the
## generated tile is safe because terrain is a pure function of (x, y, seed), but two things
## could go wrong and neither would be visible in play until it mattered:
##   1. a cached tile masking a MODIFIED one (a wall a player built stops existing);
##   2. the cache changing what the map SAYS (the whole point is that it does not).
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _world():
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws
	return [cm, ws]


func _init() -> void:
	var w = _world()
	var cm = w[0]
	var ws = w[1]

	print("--- a cached tile is the tile the generator makes ---")
	var mismatched := 0
	var compared := 0
	var skipped_modified := 0
	for i in range(400):
		var x := (i * 37) % 600 - 300
		var y := (i * 53) % 600 - 300
		var cached: Dictionary = cm.get_tile(x, y)          # fills the cache
		var cached2: Dictionary = cm.get_tile(x, y)         # served from it
		# A MODIFIED tile (an NPC post is stamped as modified tiles) is supposed to differ from
		# generated terrain - that is the whole point of it. Only generated tiles are comparable.
		var ck_key: String = cm.get_chunk_key(x, y)
		var mods: Dictionary = cm._loaded_chunks.get(ck_key, {}).get("modified_tiles", {})
		if mods.has("%d,%d" % [x, y]):
			skipped_modified += 1
			continue
		compared += 1
		var fresh: Dictionary = ws.generate_tile(x, y, cm.world_seed)
		if cached != fresh or cached2 != fresh:
			mismatched += 1
	ck(compared > 300 and mismatched == 0,
		"%d generated tiles read the same cached, re-read and freshly generated (%d modified tiles skipped)" % [compared, skipped_modified])
	ck(cm._gen_tile_cache.size() > 0, "the cache actually filled (%d tiles)" % cm._gen_tile_cache.size())

	print("\n--- a player's edit still wins ---")
	var ex := 12345 % 500
	var ey := 54321 % 500
	cm.get_tile(ex, ey)   # cache it FIRST, the dangerous order
	cm.set_tile(ex, ey, {"type": "wall", "blocks_move": true, "blocks_los": true})
	var after: Dictionary = cm.get_tile(ex, ey)
	ck(String(after.get("type", "")) == "wall", "a tile modified AFTER being cached reads as modified")
	ck(not cm._empty_chunks.has(cm.get_chunk_key(ex, ey)), "its chunk is no longer remembered as unmodified")

	print("\n--- the map does not change ---")
	# A second world, never warmed: its map must match the warmed one character for character.
	var w2 = _world()
	var cm2 = w2[0]
	var ws2 = w2[1]
	var same := 0
	var diff := 0
	for spot in [Vector2i(40, 40), Vector2i(-120, 60), Vector2i(300, -200)]:
		var a: String = ws.generate_map_display(spot.x, spot.y, 11, [], [], [], [], [], {}, [], false, [])
		var b: String = ws2.generate_map_display(spot.x, spot.y, 11, [], [], [], [], [], {}, [], false, [])
		if a == b:
			same += 1
		else:
			diff += 1
	ck(diff == 0, "%d map views are identical between a warmed cache and a cold one" % same)

	print("\n--- and it is bounded ---")
	ck(cm.GEN_TILE_CACHE_MAX > 0 and cm._gen_tile_cache.size() <= cm.GEN_TILE_CACHE_MAX,
		"the cache is capped at %d tiles" % cm.GEN_TILE_CACHE_MAX)
	var src := FileAccess.get_file_as_string("res://shared/chunk_manager.gd")
	var wipe := src.substr(src.find("func wipe_all_chunks"), 400)
	ck(wipe.find("_gen_tile_cache.clear()") >= 0 and wipe.find("_empty_chunks.clear()") >= 0,
		"a world wipe clears it (the cache describes the OLD world)")
	var reseed := src.substr(src.find("func regenerate_world_seed"), 500)
	ck(reseed.find("_gen_tile_cache.clear()") >= 0, "a new world seed clears it too")

	print("\n[TILECACHE] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
