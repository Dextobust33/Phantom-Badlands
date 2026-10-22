extends SceneTree
## Item 11a (owner 2026-10-22): "at least 3-4 different species per board". A board's quests all route into dungeons, and a dungeon is themed on a species, so the measurable unit is the DISTINCT dungeon
## types on one board. Measured before the fix (48 boards across six posts and eight characters): the dungeon pool was two per tier, so a starter board named two dungeons and repeated them. This
## fails if a board falls under four distinct dungeon types, if a dungeon repeats while the pool still has unused ones, if a rescued NPC or a fabled boss repeats inside a board, or if a quest
## id no longer regenerates to the same dungeon (the board and `_regenerate_daily_quest` must agree or an accepted quest changes under the player).
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var QD = load("res://shared/quest_database.gd")
	var q = QD.new()
	root.add_child(q)
	var levels := [4, 12, 30, 60, 120, 300, 800]
	var posts := {}
	for i in range(levels.size()):
		posts["post_%d" % i] = Vector2i(int(levels[i] * 2), 0)
	QD.register_post_coords(posts)
	var boards := 0
	var worst_distinct := 99
	var repeats_early := 0
	var npc_repeats := 0
	var boss_repeats := 0
	var drift := 0
	var checked := 0
	for pid in posts:
		for who in ["Alice", "Bob", "Cy", "Di", "Ed", "Flo", "Gus", "Hal"]:
			var board: Array = q.generate_dynamic_quests(pid, [], [], 30, 0, {}, who)
			boards += 1
			var types := {}
			var npc_at: Dictionary = {}   # quest index -> rescued NPC type
			var bosses := {}
			var order: Array = []
			for qq in board:
				var dt := String(qq.get("dungeon_type", ""))
				if dt != "":
					types[dt] = true
					order.append(dt)
				if qq.has("rescue_npc_type"):
					npc_at[QD.board_index_of(String(qq.get("id", "")))] = String(qq["rescue_npc_type"])
				if qq.has("fabled_boss_name"):
					var fn := String(qq["fabled_boss_name"])
					if bosses.has(fn):
						boss_repeats += 1
					bosses[fn] = true
				# the quest must regenerate to the same dungeon from its id alone
				var again: Dictionary = q._regenerate_daily_quest(String(qq.get("id", "")), 30, 0, who)
				checked += 1
				if again.is_empty() or String(again.get("dungeon_type", "")) != dt:
					drift += 1
			# five NPC types cannot all differ on a ten-quest board, so the rule is: never the same person within four slots of each other
			for a in npc_at:
				for b in npc_at:
					if a < b and b - a <= 4 and npc_at[a] == npc_at[b]:
						npc_repeats += 1
			worst_distinct = mini(worst_distinct, types.size())
			# while the pool still has dungeons unused, a dungeon must not repeat
			var seen := {}
			var pool_size: int = q._board_dungeon_pool(int(Vector2(posts[pid]).length() * 0.5)).size()
			for i in range(order.size()):
				if seen.has(order[i]) and seen.size() < mini(pool_size, order.size()):
					repeats_early += 1
				seen[order[i]] = true
	ck(worst_distinct >= 4, "every board names at least four different dungeons (worst of %d boards: %d)" % [boards, worst_distinct])
	ck(repeats_early == 0, "no dungeon repeats on a board while unused ones remain in the pool (%d early repeats)" % repeats_early)
	ck(npc_repeats == 0, "the same NPC is never rescued twice within four slots of a board (%d repeats)" % npc_repeats)
	ck(boss_repeats == 0, "no fabled boss repeats inside a board (%d repeats)" % boss_repeats)
	ck(drift == 0, "every quest regenerates to the same dungeon from its id (%d of %d drifted)" % [drift, checked])
	# the pool reaches below the tier: lower dungeons are possible in higher areas (owner 2026-09-11)
	var high: Array = q._board_dungeon_pool(400)
	var tiers := {}
	for d in high:
		tiers[int(load("res://shared/dungeon_database.gd").DUNGEON_TYPES[String(d["type"])].get("base_tier", 0))] = true
	ck(tiers.size() >= 3, "a high-level post's pool spans %d tiers (the owner wants lower dungeons possible in high areas)" % tiers.size())
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
