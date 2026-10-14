extends SceneTree
## Playtest sheet item 51: "same companion registrable in several slots".
## NOT reproduced through a player route (the Home Stone handler guards on `house_slot`, which is
## a flag on the character and can drift). This pins the invariant at the record that cannot drift:
## the house's own registered list refuses a second row with the same companion id.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _c(id: String) -> Dictionary:
	return {"id": id, "name": "Wolf", "monster_type": "Wolf", "level": 5, "tier": 1}

func _init() -> void:
	var pm = load("res://server/persistence_manager.gd").new()
	get_root().add_child(pm)
	await process_frame
	var house: Dictionary = pm.create_house("acct1")
	pm.houses_data["houses"]["acct1"] = house
	var cap: int = pm.get_house_companion_capacity("acct1")
	ck(cap >= 2, "house has room for two (%d)" % cap)
	var s0: int = pm.register_companion_to_house("acct1", _c("c1"), null)
	var s1: int = pm.register_companion_to_house("acct1", _c("c1"), null)
	var s2: int = pm.register_companion_to_house("acct1", _c("c2"), null)
	ck(s0 == 0, "first registration takes slot 0")
	ck(s1 == -1, "the same companion id is refused a second slot")
	ck(s2 == 1, "a different companion still registers (control)")
	pm.houses_data["houses"]["acct2"] = pm.create_house("acct2")
	var l1: int = pm.register_companion_to_house("acct2", _c(""), null)
	var l2: int = pm.register_companion_to_house("acct2", _c(""), null)
	ck(l1 >= 0 and l2 >= 0, "legacy companions with no id are not conflated")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
