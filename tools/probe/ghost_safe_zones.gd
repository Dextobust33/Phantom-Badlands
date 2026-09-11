extends SceneTree
## No invisible safe zones.
##
## Owner 2026-09-11: *"I'm at coords -44, -34 and it is saying It's a Safe Zone in the top right of
## my screen but there is no post. I'm just standing on a road surrounded by a bunch of water."*
##
## They were right, and it was not their tile. 58 LEGACY fixed trading posts are still defined in
## `trading_post_database.gd` from the old world model. They are never stamped into any chunk -
## verified on the live server, where the chunk covering that tile holds 45 modified tiles and
## every one is a path - but `world_system._tile_to_terrain` still asked the legacy table "is
## there a post here", got YES for "Southwest Grove", and returned Terrain.TRADING_POST, which is
## `safe: true`, which makes the area's monster level 0, which the HUD prints as "Safe Zone".
##
## The consequence is worse than a wrong label: `check_encounter` returns false in a safe zone, so
## each ghost was also an invisible pocket where no monster could spawn.
const TP := preload("res://shared/trading_post_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var db = TP.new()

	print("--- the legacy table no longer claims ground ---")
	ck(not TP.LEGACY_POSTS_CLAIM_TILES, "the gate is off")
	ck(not db.is_trading_post_tile(-44, -34),
		"(-44,-34) - the owner's tile - is no longer inside a legacy post")
	ck(db.get_trading_post_at(-44, -34).is_empty(), "...and resolves to no post")

	# The whole sweep, not just the reported tile: the report was one sample of a pattern.
	var claimed := 0
	for x in range(-140, 141, 1):
		for y in range(-140, 141, 1):
			if db.is_trading_post_tile(x, y):
				claimed += 1
	ck(claimed == 0, "no tile within +/-140 of origin is claimed by a ghost post - got %d" % claimed)

	print("\n--- but the table itself is intact for the things keyed by ID ---")
	# resolve_post_category / NPC stock are keyed by post id or dict, not by tile, and still
	# serve LIVE posts through this same code. Deleting the table would have broken them.
	ck(TP.TRADING_POSTS.size() > 0, "the post definitions still exist (%d)" % TP.TRADING_POSTS.size())
	ck(db.has_method("resolve_post_category"), "resolve_post_category still available")
	ck(db.has_method("get_npc_daily_stock"), "get_npc_daily_stock still available")
	ck(TP.POST_TIER_NAMES.size() == 7, "the region names the map shows are untouched")

	print("\n--- and a REAL post is still a safe zone ---")
	# The fix must not make every post unsafe. Real posts come from chunk_manager.npc_posts and
	# are stamped as `floor`, which `is_safe_zone` recognises on its own.
	var WS = load("res://shared/world_system.gd")
	var ws = WS.new()
	var info: Dictionary = ws.get_terrain_info(WS.Terrain.TRADING_POST)
	ck(bool(info.get("safe", false)), "TRADING_POST terrain is still safe where it genuinely applies")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
