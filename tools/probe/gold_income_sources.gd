extends SceneTree
## Playtest sheet item 50, slice 2: the other four gold sources - salvage, quests, dungeon clears and
## floor loot (kills and gems are in gold_purse_core). Each is checked by what it DOES where it can be
## driven, and by statement where a full dungeon/quest run would be needed.
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
class StubConn:
	func get_status() -> int:
		return 0

func _init() -> void:
	var dt = load("res://shared/drop_tables.gd").new()
	get_root().add_child(dt)
	var sword := {"name": "Test Blade", "type": "weapon_sword", "rarity": "rare", "level": 20, "value": 400}
	var r: Dictionary = dt.get_salvage_value(sword)
	ck(int(r.get("gold", 0)) == 40, "salvage pays level x rarity in gold: L20 rare = 40 (%d)" % int(r.get("gold", 0)))
	var epic50: int = int(dt.get_salvage_value({"name": "e", "type": "weapon_sword", "rarity": "epic", "level": 50, "value": 26000}).get("gold", 0))
	ck(epic50 == 200 and epic50 < 5 * Gold.kill_gold(50), "an L50 epic salvages for ~a few kills' gold, NOT its 26,000 market value (%d vs kill %d)" % [epic50, Gold.kill_gold(50)])
	ck(not (r.get("materials", {}) as Dictionary).is_empty(), "...and still pays materials")
	ck(int(dt.get_salvage_value({"name": "x", "type": "ring_basic", "rarity": "common", "level": 1}).get("gold", 0)) >= 1, "even a valueless item pays at least 1")
	# --- every salvage site credits gold
	var sv := FileAccess.get_file_as_string("res://server/server.gd")
	var sites := 0
	for pat in ["_award_gold(peer_id, int(salvage_result.get(\"gold\", 0)), \"salvage\", true)",
			"_award_gold(peer_id, int(overflow_salvage.get(\"gold\", 0)), \"salvage\", true)",
			"_award_gold(peer_id, int(sal_result.get(\"gold\", 0)), \"salvage\", true)",
			"_award_gold(peer_id, int(overflow_sal.get(\"gold\", 0)), \"salvage\", true)",
			"_award_gold(peer_id, single_gold, \"salvage\", true)",
			"_award_gold(peer_id, bulk_gold, \"salvage\", true)",
			"ch.add_gold(int(overflow_salvage.get(\"gold\", 0)))"]:
		var n := sv.count(pat)
		sites += n
		ck(n >= 1, "salvage site present: %s x%d" % [pat.substr(0, 46), n])
	ck(sites >= 9, "nine salvage paths pay gold (found %d)" % sites)
	# every get_salvage_value call is either a gold site or the known disenchant one
	var calls := sv.count("drop_tables.get_salvage_value(")
	ck(calls == 10, "no NEW salvage path slipped in unpaid (calls=%d: 9 pay, 1 is disenchant)" % calls)
	# --- quests and dungeons, by statement
	ck(sv.find("\t\t_award_gold(peer_id, GoldEconomyScript.quest_gold(maxi(1, old_level)), \"quest\")") >= 0, "quest turn-in pays gold")
	ck(sv.find("\t_award_gold(peer_id, GoldEconomyScript.dungeon_clear_gold(_current_dungeon_tier(character), character.dungeon_floor + 1), \"dungeon clear\")") >= 0, "a dungeon clear pays gold, graded by the INSTANCE tier")
	ck(Gold.dungeon_clear_gold(5, 5) > Gold.dungeon_clear_gold(1, 5) and Gold.dungeon_clear_gold(3, 8) > Gold.dungeon_clear_gold(3, 2), "dungeon gold rises with tier and with depth")
	ck(Gold.quest_gold(40) > Gold.quest_gold(5), "quest gold rises with level")
	# --- floor loot: a gold pile exists, is rarer than the old valor share, and pays on pickup
	var srv = QuietServer.new()
	srv.drop_tables = dt
	var h = CharacterScript.new()
	h.initialize("Hero", "Fighter", "Human")
	srv.characters = {1: h}
	srv.peers = {1: {"authenticated": true, "account_id": "a", "connection": StubConn.new()}}
	var golds := 0
	var valors := 0
	var N := 3000
	var sample: Dictionary = {}
	for i in N:
		var it: Dictionary = srv._roll_floor_item("none", 3, 1, 30, "", false, 1)
		var k := String(it.get("kind", ""))
		if k == "gold":
			golds += 1
			sample = it
		elif k == "valor":
			valors += 1
	ck(golds > N * 0.05 and golds < N * 0.12, "gold piles are ~8%% of floor rolls (%d of %d)" % [golds, N])
	ck(valors > N * 0.10 and valors < N * 0.18, "valor coins are ~14%% (%d of %d)" % [valors, N])
	ck(not sample.is_empty() and int(sample.item_data.gold) >= Gold.floor_gold(30) and int(sample.item_data.gold) <= Gold.floor_gold(60), "a pile is sized to the floor's (ramped) level (%d)" % int(sample.get("item_data", {}).get("gold", -1)))
	var before: int = h.gold_purse
	ck(srv._award_floor_item(1, sample) and h.gold_purse == before + int(sample.item_data.gold), "picking it up credits the purse")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
