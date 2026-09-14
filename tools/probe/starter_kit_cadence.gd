extends SceneTree
## Where does a new character's equipment actually come from?
##
## Owner 2026-09-14, correcting me: *"You should get a couple of pieces of gear from the Warden,
## he teaches you how to fight then teaches you about the world. He should take you to a starter
## dungeon that has all of the rest of your starter equipment as floor loot in the dungeon."*
##
## Two pieces handed over, four found. The half that is easy to get wrong is "the REST" - if the
## Warden's two and the dungeon's four do not add up to the full kit, a new character walks out of
## the tutorial with an empty slot and nothing ever fills it.
const QuestDB = preload("res://shared/quest_database.gd")
const DropTables = preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var db = QuestDB.new()
	var dt = DropTables.new()
	get_root().add_child(dt)

	print("===== THE WARDEN HANDS OVER TWO =====")
	var from_warden: Array = []
	if src.contains('drop_tables.get_starter_kit_item("weapon")'):
		from_warden.append("weapon")
	for qid in ["wardens_watch_1", "wardens_watch_2", "wardens_watch_3"]:
		var slot := String(db.get_quest(qid).get("starter_kit_slot", ""))
		if slot != "" and not (slot in from_warden):
			from_warden.append(slot)
	print("  from the Warden: %s" % str(from_warden))
	ck(from_warden.size() == 2, "a couple of pieces, not a wardrobe (%d)" % from_warden.size())
	ck("weapon" in from_warden, "  the weapon, in person, before anything is asked of you")
	ck("armor" in from_warden, "  and the armour after the second step")

	print("")
	print("===== THE DUNGEON FLOOR HAS THE REST =====")
	var i_k := src.find("var _kit_slots: Array = ")
	ck(i_k != -1, "the starter dungeon seeds kit onto its floors")
	var line := src.substr(i_k, 160)
	var from_floor: Array = []
	for slot in dt.STARTER_KIT_SLOT_MAP.keys():
		if line.contains('"%s"' % String(slot)):
			from_floor.append(String(slot))
	print("  on the floor:    %s" % str(from_floor))
	ck(src.contains("if _is_starter_dungeon(instance_id) and floor_count > 0"),
		"  and ONLY in the starter dungeon - no other dungeon owes anybody a wardrobe")
	ck(src.contains("_place_floor_item_random(instance_id, _kf, floor_grids[_kf]"),
		"  placed as real floor loot, walked over and picked up")

	print("")
	print("===== AND TOGETHER THEY ARE THE WHOLE KIT =====")
	# The check that matters. Executed against the real slot map, so adding a slot to the game
	# fails this until somebody decides where it comes from.
	var all_slots: Array = dt.STARTER_KIT_SLOT_MAP.keys()
	var covered: Array = []
	covered.append_array(from_warden)
	covered.append_array(from_floor)
	var missing: Array = []
	for slot in all_slots:
		if not (String(slot) in covered):
			missing.append(String(slot))
	print("  the kit is %s" % str(all_slots))
	ck(missing.is_empty(), "every slot is accounted for (missing: %s)" % str(missing))
	var dupes: Array = []
	for slot in from_warden:
		if slot in from_floor:
			dupes.append(slot)
	ck(dupes.is_empty(), "and nothing is handed out twice (%s)" % str(dupes))

	# And every one of them resolves to a real item, not a hole in the table.
	for slot in all_slots:
		var it: Dictionary = dt.get_starter_kit_item(String(slot))
		ck(not it.is_empty(), "  '%s' resolves to an item" % String(slot))

	print("")
	print("===== FIGHT, THEN WORLD, THEN THE DARK =====")
	ck(src.contains('"world":'), "there is a lesson about the world")
	ck(src.contains('_guide_teach(peer_id, "world")'), "  and it is taught")
	var i_w := src.find('_guide_teach(peer_id, "world")')
	var i_ctx := src.rfind('"wardens_watch_2"', i_w)
	ck(i_ctx != -1 and i_w - i_ctx < 400,
		"  when step TWO finishes - after the fighting, before the dungeon")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether four pieces are findable in two short floors without hunting every tile.")
	print("  They are spread one per floor in rotation and auto-collected on step, but whether a")
	print("  player actually walks over them is a playtest.")

	print("")
	if fails == 0:
		print("PASS - two given, four found, and the kit is complete")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
