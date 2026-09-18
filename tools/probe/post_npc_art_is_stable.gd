extends SceneTree
## ⛑ DOES THE SAME BLACKSMITH GREET YOU EVERY TIME, FROM EVERY SIDE?
##
## Owner 2026-09-18: *"regarding the Blacksmith and healer they shouldn't rotate through ASCII art
## each time you talk to them. They should pick one for that post and stick with it."*
## And then, after the first fix shipped: *"the Healer's ASCII art is changing still, almost seems
## different if I bump into it from different sides."*
##
## ⚑ THE FIRST FIX WAS VACUOUS, AND THAT IS WHY THIS PROBE EXISTS. `_post_npc_art_seed` hashed
## `character_data.current_post_name` — **a field nothing in the codebase has ever written** — so
## every call fell through to a fallback that hashed the PLAYER'S OWN x,y. Bumping the healer from
## the north and from the west are two different tiles, so they were two different people. The
## helper read correctly, had a docstring describing the right behaviour, and did nothing.
##
## So this runs the real lookup from eight approach tiles and compares the seeds it produces.
##
## Run:
##   godot --headless --path . --script res://tools/probe/post_npc_art_is_stable.gd

const NpcPostDatabaseScript := preload("res://shared/npc_post_database.gd")

const LIVE_SEED := 349942589444

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


## The client's own seed rule, which is one line and must stay one line.
func _seed(post_key: String, role: String) -> int:
	return hash(post_key + "|" + role)


func _init() -> void:
	var posts: Array = NpcPostDatabaseScript.generate_posts(LIVE_SEED)
	print("")
	print("===== 1. EVERY APPROACH TO A POST GIVES ONE IDENTITY =====")
	var approaches := [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var drift := 0
	var tested := 0
	for p in posts:
		var post: Dictionary = p
		var px: int = int(post.get("x", 0))
		var py: int = int(post.get("y", 0))
		# Stand on each of the eight tiles around the post centre, and a few cells further out
		# where the stations actually sit.
		var keys: Dictionary = {}
		for a in approaches:
			for reach in [1, 3, 5]:
				var k := String(NpcPostDatabaseScript.post_art_key_for(posts, px + a.x * reach, py + a.y * reach))
				keys[k] = true
				tested += 1
		if keys.size() != 1:
			drift += 1
			if drift <= 5:
				_fail("%s at (%d,%d) answers to %d different identities: %s" % [
					String(post.get("name", "?")), px, py, keys.size(), str(keys.keys())])
	print("  %d posts, %d standing positions" % [posts.size(), tested])
	if drift == 0:
		_ok("every tile in every post's grounds resolves to the same post")

	print("")
	print("===== 2. TWO ROLES AT ONE POST ARE TWO PEOPLE =====")
	# ⛑ The owner asked for this in the same sentence: *"pick one for blacksmith and a different
	# one for healer"*. Keying on the post alone would have given them the same face.
	var first: Dictionary = posts[0]
	var k0 := String(NpcPostDatabaseScript.post_art_key_for(
		posts, int(first.get("x", 0)), int(first.get("y", 0))))
	var s_smith := _seed(k0, "blacksmith")
	var s_heal := _seed(k0, "healer")
	print("  post %s: blacksmith seed %d, healer seed %d" % [k0, s_smith, s_heal])
	if s_smith == s_heal:
		_fail("the smith and the healer share a seed - they would be the same person")
	else:
		_ok("the two residents of a post are different people")

	print("")
	print("===== 3. TWO POSTS ARE TWO SMITHS =====")
	var collisions := 0
	var seen: Dictionary = {}
	for p in posts:
		var k := String(NpcPostDatabaseScript.post_art_key_for(
			posts, int((p as Dictionary).get("x", 0)), int((p as Dictionary).get("y", 0))))
		if seen.has(k):
			collisions += 1
		seen[k] = true
	if collisions > 0:
		_fail("%d post(s) share an identity with another" % collisions)
	else:
		_ok("all %d posts have distinct identities" % posts.size())

	print("")
	print("===== 4. THE DEAD FIELD IS GONE AND THE REAL ONE IS WIRED =====")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	if cli.find("current_post_name") >= 0:
		_fail("the client still reads `current_post_name`, which nothing writes")
	else:
		_ok("the field nothing wrote is gone")
	var wiring := {
		"the server computes a post identity": srv.find("func post_art_key(peer_id: int)") >= 0,
		"...from the SHARED rule this probe just tested":
			srv.find("NpcPostDatabaseScript.post_art_key_for(") >= 0,
		"the healer encounter carries it": srv.count("\"post_key\": post_art_key(peer_id),") >= 2,
		"the client stores what arrives": cli.find("_post_art_key = String(message.get(\"post_key\", \"\"))") >= 0,
		"and the seed reads that, not the player's tile": cli.find("var post_name := _post_art_key") >= 0,
	}
	for k in wiring.keys():
		if bool(wiring[k]):
			_ok(String(k))
		else:
			_fail("%s -- MISSING" % k)

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a post's smith and healer are two fixed people, the same from every")
	print("       approach, and different at every post.")
	quit()
