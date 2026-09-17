extends SceneTree
## ⛑ DOES A QUEST BOARD KNOW WHERE IT IS?
##
## `generate_dynamic_quests` - the live board - computes the area it is in like this:
##
##     var post_coords = TRADING_POST_COORDS.get(trading_post_id, Vector2i(0, 0))
##     var post_distance = sqrt(...)
##     var area_level = max(1, int(post_distance * 0.5))
##
## `TRADING_POST_COORDS` is a hardcoded table keyed by LEGACY post ids ("haven", "northwatch").
## Posts are procedurally placed now and carry no id in `npc_posts.json`, so the server
## synthesises `"npc_" + name` - which is not in the table. Every lookup therefore falls back to
## Vector2i(0, 0), every board computes distance 0, and every post in the world believes it is at
## the origin at area level 1.
##
## This asks the real function, with a real post id and with a legacy one, and compares. If the
## boards are identical the post's location is not reaching the generator.
##
## Run:
##   godot --headless --path . --script res://tools/probe/quest_board_scales_by_post.gd

const QDB := preload("res://shared/quest_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _sum_xp(board: Array) -> int:
	var t := 0
	for q in board:
		t += int(q.get("rewards", {}).get("xp", 0))
	return t


func _init() -> void:
	var qdb = QDB.new()

	print("===== 1. WHAT THE TABLE KNOWS =====")
	var coords: Dictionary = QDB.TRADING_POST_COORDS
	print("           hardcoded post ids: %d" % coords.size())
	ck(coords.has("haven"), "the table is keyed by LEGACY ids (haven present)")
	ck(not coords.has("npc_crossroads"),
		"...and does NOT contain a real post id - which is what the server passes in")

	print("\n===== 2. A NEAR POST AND A FAR POST, THROUGH THE REAL GENERATOR =====")
	# Two legacy ids that ARE in the table, at very different distances: the generator can tell
	# them apart, which proves the mechanism works and isolates the fault to the LOOKUP.
	var near: Array = qdb.generate_dynamic_quests("haven", [], [], 20, 0, {}, "Probe")
	var far: Array = qdb.generate_dynamic_quests("northwatch", [], [], 20, 0, {}, "Probe")
	print("           haven      (dist 10): %d quests, %d total xp" % [near.size(), _sum_xp(near)])
	print("           northwatch (dist 75): %d quests, %d total xp" % [far.size(), _sum_xp(far)])
	ck(_sum_xp(far) != _sum_xp(near),
		"a further post generates a different board - the scaling mechanism itself works")

	# ⚑ REGISTER THE REAL COORDINATES, exactly as the server does at startup. Iron Peak sits
	# ~74 tiles out in the live world; Crossroads is at the origin.
	QDB.register_post_coords({
		"npc_crossroads": Vector2i(0, 0),
		"npc_iron_peak": Vector2i(73, -14),
	})
	print("\n===== 3. AND NOW THE IDS THE SERVER ACTUALLY PASSES =====")
	# Real posts: 'npc_crossroads' sits at the origin, 'npc_iron_peak' is far out. Both miss the
	# table, so both should come back IDENTICAL - and identical boards for a Core post and a
	# World's Edge post is the bug.
	var real_near: Array = qdb.generate_dynamic_quests("npc_crossroads", [], [], 20, 0, {}, "Probe")
	var real_far: Array = qdb.generate_dynamic_quests("npc_iron_peak", [], [], 20, 0, {}, "Probe")
	print("           npc_crossroads: %d quests, %d total xp" % [real_near.size(), _sum_xp(real_near)])
	print("           npc_iron_peak : %d quests, %d total xp" % [real_far.size(), _sum_xp(real_far)])
	# The seed includes the post id, so the quest MIX differs. What must not differ is the
	# reward scale, which is driven purely by the area level the lookup failed to find.
	var scale_near: float = float(_sum_xp(real_near)) / maxf(1.0, float(real_near.size()))
	var scale_far: float = float(_sum_xp(real_far)) / maxf(1.0, float(real_far.size()))
	print("           average xp per quest: %.0f vs %.0f" % [scale_near, scale_far])
	ck(_sum_xp(real_far) > _sum_xp(real_near) * 1.5,
		"a World's Edge post should pay far more than a Core post")

	print("\n===== 4. AND IT IS STILL BROKEN WITHOUT THE REGISTRATION =====")
	# The accessor falls back to the legacy table, so an empty registration must reproduce the
	# original fault exactly. Without this the probe would pass if the server-side
	# `register_post_coords` call were ever deleted - the fix would be gone and the test green.
	QDB.register_post_coords({})
	var bare_near: Array = qdb.generate_dynamic_quests("npc_crossroads", [], [], 20, 0, {}, "Probe")
	var bare_far: Array = qdb.generate_dynamic_quests("npc_iron_peak", [], [], 20, 0, {}, "Probe")
	print("           unregistered: %d xp vs %d xp" % [_sum_xp(bare_near), _sum_xp(bare_far)])
	ck(_sum_xp(bare_far) < _sum_xp(bare_near) * 1.5,
		"with no registration both posts pay the same - the fault this probe was written for")

	print("\n===== VERDICT =====")
	if fails == 0:
		print("  all checks PASS")
	else:
		print("  %d check(s) FAIL" % fails)
		print("  A FAIL on the last check means every board in the world scales as if it were")
		print("  at the origin: the post's location never reaches the generator.")
	quit(0)
