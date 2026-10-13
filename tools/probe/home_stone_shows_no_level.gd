extends SceneTree
## Owner 2026-10-13, item 31: Home Stones showed a level in the inventory and the market. Every surface that
## prints an item level asks DropTables.shows_item_level; this pins the answer and that the five sites ask.
const DT := preload("res://shared/drop_tables.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	for t in ["home_stone_egg", "home_stone_supplies", "home_stone_equipment", "home_stone_companion"]:
		ck(not DT.shows_item_level({"type": t, "level": 30}), "%s prints no level" % t)
		ck(not DT.shows_item_level({"item_type": t, "level": 30}), "%s (item_type key) prints no level" % t)
	ck(DT.shows_item_level({"type": "potion_health", "level": 5}), "potions still do")
	ck(DT.shows_item_level({"type": "weapon_sword", "level": 5}), "gear still does")
	var guard := "shows_item_level("
	var card := FileAccess.get_file_as_string("res://client/item_card.gd")
	var mk := FileAccess.get_file_as_string("res://client/market_panel.gd")
	ck(card.count(guard) == 2, "item_card asks at both level sites (%d)" % card.count(guard))
	ck(mk.count(guard) == 3, "market_panel asks at all three level sites (%d)" % mk.count(guard))
	# item 6: the bulk-salvage result state must hand the panel the new inventory
	var cl := FileAccess.get_file_as_string("res://client/client.gd")
	var a := cl.find("\n\t\t\t\t\t\tpending_inventory_action = \"salvage_result_shown\"\n")
	ck(a > 0 and cl.substr(a, 1200).find("\n\t\t\t\t\t\t\tinventory_panel.populate(character_data)\n") > 0, "salvage_result_shown refreshes the visible inventory panel")
	print("\n[HOMESTONELV] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
