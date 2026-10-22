extends SceneTree
## Item 11a (owner 2026-10-22): "a fixed theme PLUS a rotating bounty, rotating hourly", and "trait hunts". The bounty is a trait hunt: defeat N monsters carrying a trait of the bounty's GROUP.
## Proves: it is the first thing on a board; it is deterministic per (post, hour) and the same for every player; it changes with the hour; the id regenerates to the same quest; accepting it stores the group;
## a kill carrying one of the group's traits counts and a kill without does not; the post's theme leans the board's first quests toward its family.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var QD = load("res://shared/quest_database.gd")
	var QM = load("res://shared/quest_manager.gd").new()
	root.add_child(QM)
	await process_frame
	var q = QM.quest_db
	QD.register_post_coords({"hunt_post": Vector2i(120, 40), "other_post": Vector2i(30, 20)})

	print("--- the bounty slot ---")
	var board: Array = q.get_available_quests_for_player("hunt_post", [], [], {}, 30, "Alice")
	ck(board.size() > 1 and bool(board[0].get("is_hourly_bounty", false)) and int(board[0]["type"]) == QD.QuestType.TRAIT_HUNT, "the bounty is the first thing on the board (%s)" % String(board[0].get("name", "")))
	var b1: Dictionary = q.generate_hourly_bounty("hunt_post", 30)
	var b2: Dictionary = q.generate_hourly_bounty("hunt_post", 30)
	ck(String(b1["id"]) == String(b2["id"]) and b1["trait_group"] == b2["trait_group"] and int(b1["target"]) == int(b2["target"]), "the same hour gives the same bounty for everyone")
	var other_player: Array = q.get_available_quests_for_player("hunt_post", [], [], {}, 30, "Bob")
	ck(String(other_player[0]["id"]) == String(board[0]["id"]), "two different characters see the SAME bounty id")
	var seen_groups := {}
	var ids := {}
	for hour in range(24):
		var qid := "hunt_post_hunt_20261022%02d" % hour
		var h: Dictionary = q.get_quest(qid, 30)
		ck(not h.is_empty() and String(h["id"]) == qid, "hour %02d regenerates from its id alone" % hour) if hour < 2 else null
		seen_groups[String(h.get("trait_group", ""))] = true
		ids[qid] = true
	ck(seen_groups.size() >= 2, "the bounty rotates across the day (%d different trait groups in 24 hours)" % seen_groups.size())
	var regen: Dictionary = q.get_quest(String(b1["id"]), 30)
	ck(String(regen.get("trait_group", "")) == String(b1["trait_group"]) and int(regen.get("target", 0)) == int(b1["target"]), "an accepted bounty's id regenerates to the same group and target")
	var group_traits: Array = b1["trait_ids"]
	ck(group_traits.size() >= 4 and String(b1["description"]).find("Defeat") >= 0, "it names its group (%s) and says what to do" % ", ".join(PackedStringArray(group_traits)))

	print("--- kills count only the right traits ---")
	var ch = load("res://shared/character.gd").new()
	ch.initialize("Hunter", "Fighter", "Human")
	var acc: Dictionary = QM.accept_quest(ch, String(b1["id"]), 0, 0, "", 30, 0)
	ck(bool(acc.get("success", false)), "the bounty can be accepted (%s)" % String(acc.get("message", "")))
	var in_group: String = String(group_traits[0])
	var out_group := ""
	for g in QD.TRAIT_GROUPS:
		if g != String(b1["trait_group"]):
			out_group = String(QD.TRAIT_GROUPS[g]["traits"][0])
	var none: Array = QM.check_kill_progress(ch, 30, 0, 0, 0.0, null, "Wolf", [])
	var wrong: Array = QM.check_kill_progress(ch, 30, 0, 0, 0.0, null, "Wolf", [out_group])
	var right: Array = QM.check_kill_progress(ch, 30, 0, 0, 0.0, null, "Wolf", [in_group])
	ck(none.is_empty() and wrong.is_empty(), "a plain monster and a monster with another group's trait do not count")
	ck(right.size() == 1 and int(right[0]["progress"]) == 1, "a monster carrying a trait of the group counts (progress %d)" % (int(right[0]["progress"]) if right.size() > 0 else -1))

	print("--- the post's theme ---")
	var themed := 0
	var boards := 0
	for who in ["A", "B", "C", "D", "E", "F"]:
		var bd: Array = q.generate_dynamic_quests("other_post", [], [], 60, 0, {}, who)
		var fam: String = QD.theme_family_for_post("other_post")
		var pool: Array = q._board_dungeon_pool(int(Vector2(30, 20).length() * 0.5))
		var has_fam := false
		for d in pool:
			if String(QD.DUNGEON_FAMILY.get(String(d["type"]), "")) == fam:
				has_fam = true
		var first3: Array = []
		for qq in bd.slice(0, 3):
			first3.append(String(QD.DUNGEON_FAMILY.get(String(qq.get("dungeon_type", "")), "")))
		boards += 1
		if not has_fam or fam in first3:
			themed += 1
	ck(themed == boards, "when the tier range holds dungeons of the post's family (%s), the board's first three quests include one" % QD.theme_family_for_post("other_post"))
	var all_have_family := true
	for d in QD.DUNGEON_FAMILY:
		if not QD.DUNGEON_FAMILIES.has(String(QD.DUNGEON_FAMILY[d])):
			all_have_family = false
	ck(QD.DUNGEON_FAMILY.size() == 53 and all_have_family, "all 53 dungeons belong to a family (%d)" % QD.DUNGEON_FAMILY.size())
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
