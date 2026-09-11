extends SceneTree
## The map wipe must destroy the world and NOTHING ELSE.
##
## Owner 2026-09-11: "I'd like the map to reset but NOT Accounts, character, or Valor."
##
## The dangerous asymmetry this guards: VALOR IS NOT IN accounts.json. `add_valor` writes it to
## the account's HOUSE, so houses.json is a save-file, not world data — deleting it as "account
## extras" would wipe every player's Valor and their Sanctuary with it.
const SERVER := "res://server/server.gd"
const WS := preload("res://shared/world_system.gd")
const NP := preload("res://shared/npc_post_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body(name: String) -> String:
	var lines := FileAccess.get_file_as_string(SERVER).split("\n")
	var a := -1
	var b := lines.size()
	for i in range(lines.size()):
		# EXACT match on the open paren. Without it, `_body("handle_gm_world_reset")` also matches
		# `handle_gm_world_reset_confirm` and silently returns the wrong function - which it did,
		# failing the "does not perform the reset" assertion against the confirm handler.
		if lines[i].begins_with("func " + name + "("):
			a = i
		elif a >= 0 and lines[i].begins_with("func ") and i > a:
			b = i
			break
	if a < 0:
		return ""
	var out := ""
	for i in range(a, b):
		out += lines[i] + "\n"
	return out


func _init() -> void:
	var reset := _body("_do_world_reset")
	ck(reset != "", "_do_world_reset exists")

	print("--- it must NOT touch anything a player owns ---")
	for forbidden in ["accounts.json", "houses.json", "clear_house", "delete_character",
			"remove_character_from_account", "clans.json", "leaderboard"]:
		ck(not reset.contains(forbidden),
			"never touches '%s'" % forbidden)
	# The strongest form: characters are SAVED, never deleted.
	ck(reset.contains("persistence.save_character("), "characters are re-saved, not removed")
	ck(not reset.contains("delete_character"), "no character is deleted")

	print("\n--- and it must actually wipe the world ---")
	for required in ["wipe_all_chunks()", "save_world_seed()", "generate_posts(",
			"clear_all_market_data()", "save_player_tiles()", "active_dungeons.clear()",
			"save_corpses()"]:
		ck(reset.contains(required), "does '%s'" % required)
	ck(reset.contains("DUNGEON_STATE_PATH"),
		"deletes the dungeon state FILE too (it is reloaded at boot, so clearing memory is not enough)")

	print("\n--- the Crossroads is a guaranteed destination, not a hopeful one ---")
	var ws = WS.new()
	# generate_tile keeps a radius-5 safe zone at the origin for ANY seed.
	for s in [1, 12345, 999999999, 2178175570]:
		var t: Dictionary = ws.generate_tile(0, 0, s)
		ck(not bool(t.get("blocks_move", false)), "(0,0) is standable under seed %d" % s)
	# ...and Crossroads is pinned there regardless of seed.
	for s in [7, 424242]:
		var posts: Array = NP.generate_posts(s)
		var starter := {}
		for p in posts:
			if p is Dictionary and p.get("is_starter", false):
				starter = p
				break
		ck(not starter.is_empty() and int(starter.get("x", -1)) == 0 and int(starter.get("y", -1)) == 0,
			"seed %d puts Crossroads at (0,0)" % s)

	print("\n--- corpses land on ground that exists ---")
	var nearest := _body("_nearest_standable")
	ck(nearest != "", "_nearest_standable exists")
	ck(nearest.contains("generate_tile"),
		"it asks the procedural generator, not the chunk deltas (which are wiped by then)")
	ck(nearest.contains("absi(dx) != r and absi(dy) != r"),
		"it searches in expanding RINGS, so it finds the NEAREST tile, not merely a valid one")
	# Prove the search works on real water.
	var seed_v := 2178175570
	var checked := 0
	var found := 0
	for x in range(-400, 400, 37):
		for y in range(-400, 400, 37):
			var t2: Dictionary = ws.generate_tile(x, y, seed_v)
			if bool(t2.get("blocks_move", false)):
				checked += 1
				# replicate the ring search
				var got := false
				for r in range(1, 61):
					for dx in range(-r, r + 1):
						for dy in range(-r, r + 1):
							if absi(dx) != r and absi(dy) != r:
								continue
							var c := ws.generate_tile(x + dx, y + dy, seed_v)
							if not bool(c.get("blocks_move", false)):
								got = true
								break
						if got: break
					if got: break
				if got:
					found += 1
	print("      %d blocked sample tiles, %d found standable ground within 60" % [checked, found])
	ck(checked > 0, "the sample actually hit blocked terrain (so this is not a vacuous pass)")
	ck(found == checked, "every blocked tile had standable ground nearby")

	print("\n--- and it is two-step ---")
	var arm := _body("handle_gm_world_reset")
	ck(arm.contains("_world_reset_armed_at"), "the first press only ARMS")
	ck(not arm.contains("_do_world_reset()"), "...and does not perform the reset")
	var conf := _body("handle_gm_world_reset_confirm")
	ck(conf.contains("60000"), "the confirm expires (60s window)")
	ck(conf.contains("_is_admin(peer_id)") and arm.contains("_is_admin(peer_id)"),
		"both halves are admin-gated")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
