extends SceneTree
## Server half of sheet item 14: a rune built the way crafting builds it (rune_stat / rune_cap /
## target_slot) must raise the affix, be consumed, be refused on a wrong slot or no gain, and be
## remembered for Disenchant. Pairs with a_rune_can_be_applied_from_the_panel (the client half).
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class QuietServer extends "res://server/server.gd":
	func save_character(_peer_id) -> void:
		pass   # never write a probe character into a real save directory

class StubConn:
	func get_status() -> int:
		return 0

func _rune() -> Dictionary:
	return {"type": "rune", "name": "Minor Rune of Attack", "target_slot": "weapon", "rune_stat": "attack_bonus", "rune_cap": 8, "rune_tier": "minor", "quantity": 1}

func _init() -> void:
	var srv = QuietServer.new()
	var hero = CharacterScript.new()
	hero.name = "Hero"
	hero.class_type = "warrior"
	hero.level = 20
	hero.equipped["weapon"] = {"name": "Rusty Sword", "type": "weapon", "affixes": {"attack_bonus": 3}}
	hero.equipped["ring"] = {"name": "Tin Ring", "type": "ring"}
	hero.inventory = [_rune()]
	srv.characters = {1: hero}
	srv.peers = {1: {"authenticated": true, "account_id": "a", "connection": StubConn.new()}}
	srv.handle_use_rune(1, {"rune_index": 0, "target_slot": "ring"})
	ck(hero.inventory.size() == 1, "a wrong slot is refused and the rune is kept")
	srv.handle_use_rune(1, {"rune_index": 0, "target_slot": "weapon"})
	ck(int(hero.equipped["weapon"]["affixes"].get("attack_bonus", 0)) == 8, "the weapon's attack bonus went 3 -> 8")
	ck(hero.inventory.is_empty(), "the rune was consumed")
	ck((hero.equipped["weapon"].get("applied_runes", []) as Array).size() == 1, "and remembered for Disenchant")
	hero.inventory = [_rune()]
	srv.handle_use_rune(1, {"rune_index": 0, "target_slot": "weapon"})
	ck(hero.inventory.size() == 1, "a rune that would not improve anything is kept, not wasted")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
