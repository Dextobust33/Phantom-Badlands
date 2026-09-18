extends SceneTree
## ⛑ DOES THE BOARD ADVERTISE THE GRADE THE PLAYER ACTUALLY GETS?
##
## The quest stamps `dungeon_tier` / `dungeon_rank`, the server hands those to
## `_create_player_dungeon_instance` as `force_tier` / `force_sub_tier`, and the instance is built
## from them. The board's difficulty line is supposed to print the SAME pair.
##
## ⛑ IT DID NOT, AND THIS IS THE SEVENTH TIME THAT CLASS OF BUG HAS SHIPPED.
## `dungeon_difficulty_line` re-derived the tier from `dungeon_info.base_tier` - the dungeon
## TYPE's design weight - while using the passed-in rank. So it printed the type's tier beside the
## land's rank: a grade that matched neither the advertisement nor the dungeon. Owner 2026-09-17:
## *"Board showed H2, where it points me shows G2. Inside shows G2 as well."*
##
## CLAUDE.md records this defect six separate times (*"A dungeon TYPE has no grade - base_tier is
## NOT tier"*), and it came back inside the function written to prevent it, because a comment
## there was careful about the rank and said nothing about the tier.
##
## So the check is not "does the line render" - it did, beautifully, with the wrong number. It is
## "does the line agree with the fields the server will build from".
##
## Run:
##   godot --headless --path . --script res://tools/probe/quest_grade_advertised.gd

const QD = preload("res://shared/quest_database.gd")
const PR = preload("res://shared/power_rank.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var q = QD.new()
	get_root().add_child(q)

	# A resolver that returns a grade deliberately DIFFERENT from any dungeon type's base_tier,
	# so a line reading the type instead of the land cannot accidentally agree.
	q.land_grade_fn = func(_post_id: String) -> Dictionary:
		return {"tier": 6, "rank": 4}

	var checked := 0
	for post in ["haven", "northeast_farm", "northwatch"]:
		for quest in q.generate_dynamic_quests(post, [], [], 30, 0, {}, "probe"):
			if not quest.has("dungeon_tier"):
				continue
			checked += 1
			var t: int = int(quest["dungeon_tier"])
			var r: int = int(quest["dungeon_rank"])
			var want: String = PR.label(t, r)
			var desc: String = String(quest.get("description", ""))
			# The line prints the grade inside a colour tag; the label itself is what matters.
			ck(desc.contains(want),
				"%s: stamped %s (tier=%d rank=%d) and the board says so" % [
					String(quest.get("name", "?")).substr(0, 22), want, t, r])
			# And the resolver's grade is what got stamped - not the type's design weight.
			ck(t == 6 and r == 4,
				"  ...and the stamp came from the LAND (got tier=%d rank=%d, want 6/4)" % [t, r])

	ck(checked > 0, "found %d dungeon quests to check" % checked)
	print("")
	if fails == 0:
		print("[PROBE] PASS the board advertises the grade it pinned")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
