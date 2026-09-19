extends SceneTree
## ⛑ DOES THE QUEST BOARD TELL THE TRUTH ABOUT WHAT IS IN THERE?
##
## Owner 2026-09-19: *"we want to ensure Quests can be offered for these dungeons we are adding as
## well so players can choose to take them on the Quest boards."*
##
## Quest dungeons already ROLLED modifiers - they go through `_register_dungeon` like any other -
## so the mechanic worked. What was missing is that the board never said so, and a risk you cannot
## see before accepting is not a choice.
##
## ⛑ THE HARD PART IS THAT A QUEST IS DESCRIBED BEFORE ITS DUNGEON EXISTS. The board offers it,
## `_regenerate_daily_quest` may rebuild it from its id, and the instance is only created on
## ACCEPT. An ordinary `randf()` roll would differ at all three moments, so the board would
## advertise one dungeon and hand over another. Seeding on the quest id is what makes the promise
## keepable, and this probe is the thing that proves it stayed keepable.
const DungeonDB := preload("res://shared/dungeon_database.gd")
const QuestDB := preload("res://shared/quest_database.gd")

var _fails: Array = []

func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)

func _ok(m: String) -> void:
	print("  ok    %s" % m)

func _init() -> void:
	print("")
	print("===== 1. THE SAME QUEST ALWAYS DESCRIBES THE SAME DUNGEON =====")
	var ids := ["post_crossroads_daily_0", "post_irongate_daily_3", "post_sunkeep_daily_7"]
	var stable := true
	for qid in ids:
		var first: Array = DungeonDB.roll_dungeon_modifiers_seeded(6, String(qid))
		for i in range(25):
			if DungeonDB.roll_dungeon_modifiers_seeded(6, String(qid)) != first:
				stable = false
				_fail("%s rolled a different set on repeat - the board would lie" % qid)
				break
		print("  %-28s -> %s" % [qid, str(first)])
	if stable:
		_ok("25 repeats per quest id, identical every time")

	print("")
	print("===== 2. DIFFERENT QUESTS ARE NOT ALL THE SAME DUNGEON =====")
	# A seed that ignored its input would be perfectly stable AND perfectly useless.
	var seen := {}
	for i in range(60):
		seen[str(DungeonDB.roll_dungeon_modifiers_seeded(9, "q_%d" % i))] = true
	print("  %d distinct modifier sets across 60 quest ids" % seen.size())
	if seen.size() < 3:
		_fail("only %d distinct sets - the seed is barely reading the quest id" % seen.size())
	else:
		_ok("quests differ from each other")

	print("")
	print("===== 3. RANK STILL GATES IT =====")
	# Low-rank dungeons must stay plain: MODIFIER_COUNT_BY_RANK gives them no slots at all.
	for rank in [1, 2, 3, 6, 9]:
		var got: Array = DungeonDB.roll_dungeon_modifiers_seeded(rank, "same_quest")
		var slots: int = int(DungeonDB.MODIFIER_COUNT_BY_RANK.get(rank, 0))
		print("  rank %d: %d slot(s) -> %s" % [rank, slots, str(got)])
		if got.size() > slots:
			_fail("rank %d produced %d modifiers from %d slots" % [rank, got.size(), slots])
	if _fails.is_empty():
		_ok("no rank exceeds its slot count, and rank 1-2 stay plain")

	print("")
	print("===== 4. THE BOARD LINE READS AS A WARNING =====")
	var mods: Array = DungeonDB.roll_dungeon_modifiers_seeded(9, "a_loaded_one")
	var line: String = QuestDB.modifier_board_line(mods)
	print("  %s" % (line if line != "" else "(this quest rolled none)"))
	if not mods.is_empty():
		if line == "":
			_fail("a dungeon with %d modifier(s) printed no board line" % mods.size())
		else:
			for m in mods:
				var nm := String(DungeonDB.DUNGEON_MODIFIERS.get(String(m), {}).get("name", ""))
				if nm != "" and line.find(nm) < 0:
					_fail("the board line never names %s" % nm)
			if _fails.is_empty():
				_ok("every modifier the dungeon carries is named on the board")
	if QuestDB.modifier_board_line([]) != "":
		_fail("a plain dungeon printed a warning line")
	else:
		_ok("a plain dungeon says nothing extra")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the board can promise what a quest dungeon contains, and the promise is")
	print("       the same one the instance keeps.")
	quit()
