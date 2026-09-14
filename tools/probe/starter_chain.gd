extends SceneTree
## Warden's Watch: does a brand-new character actually get a chain, and does it arm them in time?
##
## The Pathfinder chain was retired 2026-09-03 in favour of this, and for eleven days the welcome
## overlay still pointed every new player at a quest nothing granted. So the first thing to assert
## is the dull one: the chain exists, it is reachable, and each stage leads to the next.
##
## The gear cadence is not decoration. `-- newplayer` measured a gearless character at 76% win at
## L1, 53% at L5 and 16% at L10 - so the chain has to produce real equipment inside the L1-L3
## window or it has taught someone to play a game that kills them three levels later.
const QuestDB = preload("res://shared/quest_database.gd")
const ServerScript = preload("res://server/server.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var db = QuestDB.new()

	print("===== THE CHAIN EXISTS AND HOLDS TOGETHER =====")
	var ids := ["wardens_watch_1", "wardens_watch_2", "wardens_watch_3"]
	var prev := ""
	for idx in range(ids.size()):
		var qid: String = ids[idx]
		var q: Dictionary = db.get_quest(qid)
		ck(not q.is_empty(), "%s is defined" % qid)
		if q.is_empty():
			continue
		ck(String(q.get("chain_id", "")) == "wardens_watch", "  chain_id is set")
		ck(int(q.get("chain_stage", 0)) == idx + 1, "  stage %d" % (idx + 1))
		ck(int(q.get("chain_total", 0)) == 3, "  of 3")
		ck(String(q.get("prerequisite", "")) == prev,
			"  prerequisite is %s" % ("nothing" if prev == "" else prev))
		var nxt: String = String(q.get("next_in_chain", ""))
		var want_next: String = ids[idx + 1] if idx + 1 < ids.size() else ""
		ck(nxt == want_next, "  leads to %s" % ("the end" if want_next == "" else want_next))
		prev = qid

	print("")
	print("===== IT ARMS YOU, IN THE ORDER THAT MATTERS =====")
	# Weapon first: a gearless character's problem is that it cannot kill anything fast enough,
	# and attrition is what actually ends new characters.
	var slots: Array = []
	for qid in ids:
		slots.append(String(db.get_quest(qid).get("starter_kit_slot", "")))
	print("  cadence: %s" % " -> ".join(slots))
	ck(slots == ["weapon", "armor", "accessory"], "weapon, then armour, then trinket")

	var dt = DropTablesScript.new()
	get_root().add_child(dt)
	for sl in slots:
		var item: Dictionary = dt.get_starter_kit_item(sl)
		ck(not item.is_empty(), "  the '%s' slot resolves to a real item (%s)"
			% [sl, String(item.get("name", "NOTHING"))])

	print("")
	print("===== THE LAST STEP IS THE DUNGEON, AND IT PAYS THE EGG =====")
	var last: Dictionary = db.get_quest("wardens_watch_3")
	ck(int(last.get("type", -1)) == QuestDB.QuestType.DUNGEON_CLEAR,
		"the chain ends in a dungeon clear, not another errand")
	var bonus: Dictionary = last.get("chain_bonus", {})
	ck(String(bonus.get("egg", "")) != "",
		"the companion egg is paid HERE (%s) - creation no longer hands one out"
			% String(bonus.get("egg", "none")))
	ck(int(bonus.get("valor", 0)) > 0, "and a valor bonus for finishing")

	print("")
	print("===== THE WELCOME OVERLAY NAMES SOMETHING THAT EXISTS =====")
	# For eleven days it named Pathfinder's Trial, which nothing granted. That is the failure this
	# check is here to stop repeating: the very first thing a new player reads must be true.
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var named_in_overlay := src.contains("Warden's Watch[/color]")
	ck(named_in_overlay, "the overlay names Warden's Watch")
	ck(not src.contains("Pathfinder's Trial[/color]"),
		"and no longer names the retired Pathfinder chain")
	ck(src.contains('accept_quest(character, "wardens_watch_1"'),
		"creation actually GRANTS the chain it names")

	print("")
	print("----- and the free creation egg is gone, as decided -----")
	ck(not src.contains('tutorial_egg["tutorial_gift"] = true'),
		"creation no longer hands out a companion egg - the chain does")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether the three stages are the right LENGTH, and whether a level-1 finishes them")
	print("  before the gearless curve turns on them at L5. That is a playtest.")

	print("")
	if fails == 0:
		print("PASS - a new character is given a chain that exists and arms them in order")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
