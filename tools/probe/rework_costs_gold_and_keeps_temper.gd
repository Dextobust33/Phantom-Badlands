extends SceneTree
## Owner 2026-10-14 (yes to both): (1) the enchanter's Rework is a GOLD sink (gear power = gold, Valor =
## services); (2) a stat the blacksmith TEMPERED survives a Rework - only the natural roll is rerolled.
const CharacterScript = preload("res://shared/character.gd")
const Gold = preload("res://shared/gold_economy.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class QuietServer extends "res://server/server.gd":
	func save_character(_p) -> void:
		pass
	func _player_at_npc_post(_p) -> bool:
		return true
class QuietPM extends "res://server/persistence_manager.gd":
	func save_corpses() -> void:
		pass
class StubConn:
	func get_status() -> int:
		return 0

func _sword() -> Dictionary:
	return {"name": "Test Blade", "type": "weapon_sword", "rarity": "epic", "level": 50,
		"affixes": {"attack_bonus": 22, "str_bonus": 25, "prefix_name": "Mighty", "suffix_name": "of Might", "roll_quality": 50}}

func _init() -> void:
	var dt = load("res://shared/drop_tables.gd").new()
	get_root().add_child(dt)
	var pm = QuietPM.new()
	get_root().add_child(pm)
	await process_frame
	# --- the price is gold, rises per rework, never Valor
	var it := _sword()
	var c0: Dictionary = dt.affix_reroll_cost(it, false)
	ck(c0.has("gold") and not c0.has("valor"), "the cost is in gold, not Valor")
	it["reroll_count"] = 3
	ck(int(dt.affix_reroll_cost(it, false).gold) > int(c0.gold), "...and rises with each rework (%d -> %d)" % [int(c0.gold), int(dt.affix_reroll_cost(it, false).gold)])
	ck(int(dt.affix_reroll_cost(it, true).gold) == 0 and not (dt.affix_reroll_cost(it, true).materials as Dictionary).is_empty(), "a committed Enchanter pays no gold but still pays materials (never free)")

	# --- Rework keeps the tempered part
	var t := _sword()
	t["affixes"]["attack_bonus"] = 22 + 12      # 22 natural + 12 bought
	t["temper_gain"] = {"attack_bonus": 12}
	var res: Dictionary = dt.reroll_affix(t, "attack_bonus")
	ck(bool(res.ok), "the natural attack roll can be reworked")
	ck(int(res.old_value) == 22, "...the reported old value is the NATURAL 22, not 34 (%s)" % str(res.old_value))
	ck(int(t["affixes"].get("attack_bonus", 0)) == 12, "...and the 12 bought damage is still on the weapon (%s)" % str(t["affixes"].get("attack_bonus", 0)))
	ck(String(res.new_stat) != "attack_bonus" and t["affixes"].has(String(res.new_stat)), "the natural roll became a different stat (%s)" % String(res.new_stat))
	# the leftover is NOT a rerollable stat any more
	ck(not ("attack_bonus" in dt.rerollable_affixes(t)), "a stat that is only tempered cannot be reworked away")
	var again: Dictionary = dt.reroll_affix(t, "attack_bonus")
	ck(not bool(again.ok) and int(t["affixes"].attack_bonus) == 12, "trying anyway is refused and changes nothing")
	# a reroll never lands ON a tempered-only key and merges over it
	var merged := false
	for i in 60:
		var u := _sword()
		u["affixes"] = {"str_bonus": 25, "prefix_name": "Mighty", "suffix_name": "of Might", "attack_bonus": 9}
		u["temper_gain"] = {"attack_bonus": 9}   # attack_bonus is ONLY tempered here
		var r: Dictionary = dt.reroll_affix(u, "str_bonus")
		if bool(r.ok) and int(u["affixes"].get("attack_bonus", 0)) != 9:
			merged = true
	ck(not merged, "a reroll never overwrites a tempered-only stat (60 tries)")
	# no tempering: behaves exactly as before
	var plain := _sword()
	var rp: Dictionary = dt.reroll_affix(plain, "attack_bonus")
	ck(bool(rp.ok) and not plain["affixes"].has("attack_bonus") and int(rp.old_value) == 22, "an untempered item reworks exactly as it always did")

	# --- the server charges gold, and refunds on a refusal
	var srv = QuietServer.new()
	srv.drop_tables = dt
	srv.persistence = pm
	var h = CharacterScript.new()
	h.initialize("Hero", "Fighter", "Human")
	h.inventory = [_sword()]
	h.crafting_materials = {}
	var need: Dictionary = dt.affix_reroll_cost(h.inventory[0], false)
	for m in need.materials:
		h.crafting_materials[m] = int(need.materials[m]) + 5
	srv.characters = {1: h}
	srv.peers = {1: {"authenticated": true, "account_id": "a", "connection": StubConn.new()}}
	h.gold_purse = 0
	srv.handle_affix_reroll(1, {"item_index": 0, "stat": "attack_bonus"})
	ck(int(h.inventory[0].get("reroll_count", 0)) == 0, "no gold: the rework does not happen")
	h.gold_purse = int(need.gold) + 7
	srv.handle_affix_reroll(1, {"item_index": 0, "stat": "attack_bonus"})
	ck(h.gold_purse == 7 and int(h.inventory[0].reroll_count) == 1, "with gold: it happens and exactly %d gold is taken" % int(need.gold))
	h.gold_purse = 100000
	var before: int = h.gold_purse
	srv.handle_affix_reroll(1, {"item_index": 0, "stat": "not_a_stat"})
	ck(h.gold_purse == before, "a refused rework refunds the gold")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
