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
	print("  quest-stage cadence: %s" % " -> ".join(slots))
	# The WEAPON is not a quest reward any more. 2026-09-14, owner: *"I'm not sure I like
	# that he has you go out and kill something alone ... it's likely players will die before
	# even completing his introduction."* Right - and the weapon being the PRIZE for that
	# first fight meant a new character took their most dangerous fight with empty hands to
	# earn the thing that would have made it safe. The Warden hands it over when you talk to
	# him, before anything is asked of you.
	ck(slots[0] == "", "stage 1 grants no kit - the Warden arms you in person, up front")
	# Stage 3 pays NO gear either, as of 2026-09-14. Owner: *"You should get a couple of pieces
	# of gear from the Warden ... He should take you to a starter dungeon that has all of the
	# rest of your starter equipment as floor loot in the dungeon."* So the trinket is not a
	# turn-in reward any more - it is lying on the floor down there with the helm, boots and
	# shield. `starter_kit_cadence.gd` is what checks the two halves still add up to a whole kit.
	ck(slots[1] == "armor", "stage 2 pays the armour - the Warden's second and last piece")
	ck(slots[2] == "",
		"and stage 3 pays NO gear: the rest is floor loot in the dungeon, found not issued")
	ck(FileAccess.get_file_as_string("res://server/server.gd").contains(
			"if _is_starter_dungeon(instance_id) and floor_count > 0"),
		"  which the starter dungeon really does place")

	var src0 := FileAccess.get_file_as_string("res://server/server.gd")
	ck(src0.contains('drop_tables.get_starter_kit_item("weapon")'),
		"the Warden really hands over a weapon rather than merely promising one")

	var dt = DropTablesScript.new()
	get_root().add_child(dt)
	for sl in ["weapon", "armor", "accessory"]:
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
	# The welcome no longer names the CHAIN at all - a quest name means nothing to someone who
	# has not seen a quest log. It names the Warden, who is standing in front of them.
	ck(src.to_lower().contains("walk into"),
		"the overlay points at the Warden, who is a real figure on the map")
	ck(not src.contains("Pathfinder's Trial[/color]"),
		"and no longer names the retired Pathfinder chain")
	ck(src.contains('accept_quest(character, "wardens_watch_1"'),
		"creation still GRANTS the chain, whether or not the popup names it")
	ck(src.contains("func _guide_escorts_overworld"),
		"and the Warden escorts the early steps, so the first fight is not taken alone")

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
