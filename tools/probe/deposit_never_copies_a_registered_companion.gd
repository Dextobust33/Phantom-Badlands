extends SceneTree
## Playtest sheet item 51 - owner screenshots 2026-10-14: the SAME Lime Hydra Sprout in two
## Sanctuary slots, Lv17 ("In use by Dexto") and Lv53 ("Available").
## ROUTE: the Stable deposit asked "registered?" only of the ACTIVE companion. A registered
## companion sitting in the collection was copied into the kennel as a plain one (slot flag
## stripped) while its Sanctuary row stayed checked out; kennel -> Register made a second row.
## This drives the real handler.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class StubConn:
	func get_status() -> int:
		return 0

class StubChunks extends "res://shared/chunk_manager.gd":
	func get_tile(_x, _y) -> Dictionary:
		return {"type": "companion_stable"}

func _hydra(slot: int, lvl: int) -> Dictionary:
	var c := {"id": "hydra-1", "name": "Lime Hydra Sprout", "monster_type": "Hydra", "level": lvl,
			  "xp": 0, "tier": 2, "sub_tier": 1, "variant": "Lime", "bonuses": {}}
	if slot >= 0:
		c["house_slot"] = slot
	return c

func _init() -> void:
	var pm = load("res://server/persistence_manager.gd").new()
	get_root().add_child(pm)
	await process_frame
	var srv = ServerScript.new()
	srv.persistence = pm
	srv.chunk_manager = StubChunks.new()
	var house: Dictionary = pm.create_house("acct1")
	var row := _hydra(-1, 17)
	row["registered_at"] = 1
	row["checked_out_by"] = "Dexto"
	house["registered_companions"] = {"companions": [row]}
	pm.houses_data["houses"]["acct1"] = house

	var hero = CharacterScript.new()
	hero.name = "Dexto"
	hero.class_type = "warrior"
	hero.level = 30
	# The hydra is registered (slot 0) and in the collection; a DIFFERENT companion is out.
	hero.collected_companions = [_hydra(0, 53), {"id": "other", "name": "Wolf", "monster_type": "Wolf", "level": 4}]
	hero.active_companion = hero.collected_companions[1]
	srv.characters = {1: hero}
	srv.peers = {1: {"authenticated": true, "account_id": "acct1", "connection": StubConn.new()}}

	print("===== deposit a registered companion that is NOT the active one =====")
	srv.handle_companion_stable_deposit(1, {"collected_index": 0})
	var h = pm.get_house("acct1")
	ck(h.companion_kennel.companions.size() == 0, "nothing was copied into the kennel (%d there)" % h.companion_kennel.companions.size())
	ck(h.registered_companions.companions.size() == 1, "still exactly one registered row")
	var r = h.registered_companions.companions[0]
	ck(r.get("checked_out_by", "x") == null, "its slot is released (back home)")
	ck(int(r.get("level", 0)) == 53, "and holds the level the character earned (%d)" % int(r.get("level", 0)))
	ck(hero.collected_companions.size() == 1 and String(hero.active_companion.get("id", "")) == "other", "the unrelated active companion is untouched")

	print("===== control: an ordinary companion still goes to the kennel =====")
	hero.collected_companions.append({"id": "plain", "name": "Rat", "monster_type": "Rat", "level": 2})
	srv.handle_companion_stable_deposit(1, {"collected_index": 1})
	h = pm.get_house("acct1")
	ck(h.companion_kennel.companions.size() == 1, "an unregistered companion is kennelled")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
