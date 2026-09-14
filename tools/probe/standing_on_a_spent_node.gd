extends SceneTree
## What is drawn under your feet when you stand on a node you already harvested?
##
## Owner 2026-09-14: *"my player sprite is still showing water under it even though I already
## cleared the water on this space ... You can't walk on a water tile, it would have to be a
## bridge tile or fished before the sprite can stand on it."*
##
## The second half of that sentence is what identified it. Water blocks movement, so standing
## there at all PROVES the node was spent - `move_player` allows a step onto a gatherable once
## its node is depleted, and that is the only way onto water without a bridge. So the movement
## rule and the render disagreed, and the one tile that could show it was the one guaranteed to
## be under the player.
const WS = preload("res://shared/world_system.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var ws = WS.new()

	print("===== THE TWO RULES AGREE NOW =====")
	# Movement allows the step; the marker must therefore not claim the node is still there.
	var src := FileAccess.get_file_as_string("res://shared/world_system.gd")
	ck(src.contains("if tile_type in GATHERABLE_TYPES and chunk_manager.is_node_depleted(new_x, new_y):"),
		"move_player lets you onto a gatherable whose node is spent")
	ck(src.contains("if t in GATHERABLE_TYPES and depleted_set.has("),
		"and the marker under your feet now asks the same question")

	print("")
	print("===== AND THE MARKER ACTUALLY REPORTS GROUND =====")
	# Executed, not read. A cached tile is enough - the function falls back to chunk_manager only
	# when the cache misses, so no world generation is needed.
	var cache := {"5,7": {"type": "water", "blocks_move": true}}
	var spent := {"5,7": true}
	var on_spent := ws._marker_with_tile("!player", 5, 7, cache, spent)
	var on_fresh := ws._marker_with_tile("!player", 5, 7, cache, {})
	print("  standing on a SPENT water tile -> '%s'" % on_spent)
	print("  standing on a FRESH water tile -> '%s'" % on_fresh)
	ck(on_spent == "!player",
		"a harvested node draws as bare ground - no water under the sprite")
	ck(on_fresh == "!player:water",
		"  and an un-harvested one still draws its tile (or this check proves nothing)")

	print("")
	print("----- it did not break anything that is not a gatherable -----")
	# A road is not a node and must keep drawing, depleted set or not - this is the regression
	# the change could plausibly have caused.
	var road := {"1,1": {"type": "path", "blocks_move": false}}
	ck(ws._marker_with_tile("!player", 1, 1, road, {"1,1": true}) == "!player:path",
		"a player on a road still stands on the road, even if that key is in the set")
	ck(ws._marker_with_tile("!player", 2, 2, {"2,2": {"type": "empty"}}, {}) == "!player",
		"and bare ground is still left unnamed, as before")

	print("")
	print("----- the same fix covers OTHER players, not just you -----")
	ck(src.contains('_marker_with_tile("!other", x, y, tile_cache, depleted_set)'),
		"someone else standing on a spent node reads the same way to you")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether a spent water tile should look like water at all once you can walk on it.")
	print("  It draws the biome ground now, which is what the main render path already did for")
	print("  every OTHER cell - so the two agree. Whether that reads as 'drained' is a design")
	print("  question and a playtest.")

	print("")
	if fails == 0:
		print("PASS - you stand on what you are actually standing on")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
