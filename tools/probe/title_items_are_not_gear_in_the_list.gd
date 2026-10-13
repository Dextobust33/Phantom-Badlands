extends SceneTree
## Owner sheet 2026-10-13, item 47: the Jarl Ring read as equipable gear in the inventory. Its list row
## (`_get_item_bonus_summary`) fell into the "ring" branch and advertised an attack bonus. Title items must
## say what to do with them instead, and a real ring must still read as gear.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	var c = load("res://client/client.gd").new()
	var ring: String = c._get_item_bonus_summary({"type": "jarls_ring", "name": "Jarl's Ring", "is_title_item": true, "rarity": "legendary"})
	ck(ring.find("High Seat") >= 0 and ring.find("Atk") < 0, "Jarl's Ring says where to turn it in, no Atk (%s)" % ring)
	var crown: String = c._get_item_bonus_summary({"type": "unforged_crown", "is_title_item": true})
	ck(crown.find("Forge") >= 0, "Unforged Crown points at the forge")
	var real: String = c._get_item_bonus_summary({"type": "ring", "level": 40, "rarity": "rare"})
	ck(real.find("Atk") >= 0, "a real ring still reads as gear (%s)" % real)
	print("\n[TITLELIST] %s" % ("PASS" if fails == 0 else "FAIL - %d" % fails))
	quit(0 if fails == 0 else 1)
