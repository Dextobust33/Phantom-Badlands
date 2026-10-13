extends SceneTree
## Owner sheet 2026-10-13, item 13: "Blacksmith Armor Upgrade, what is it doing?" Every upgrade recipe's
## description must say it raises ITEM LEVEL, name the quality multipliers the craft really applies, and
## quote its own cap (recipe max_upgrades) and the global cap.
const CDB := preload("res://shared/crafting_database.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var srv = load("res://server/server.gd").new()
	var n := 0
	for id in CDB.RECIPES:
		var r: Dictionary = CDB.RECIPES[id]
		if String(r.get("output_type", "")) != "upgrade":
			continue
		n += 1
		var d: String = srv._get_recipe_description(r)
		var ok: bool = d.find("ITEM LEVEL") >= 0 and d.find("Masterwork x1.5") >= 0 \
			and d.find("fewer than %d upgrades" % int(r.get("max_upgrades", CDB.MAX_UPGRADE_LEVELS))) >= 0 \
			and d.find("hard cap %d" % CDB.MAX_UPGRADE_LEVELS) >= 0
		ck(ok, "%s: %s" % [id, d.substr(0, 70)])
	ck(n >= 9, "checked %d upgrade recipes" % n)
	print("\n[UPGRADEDESC] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
