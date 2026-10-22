extends SceneTree
## Paths revamp data model (docs/design/paths_revamp.md): ranked nodes, the point curve, feat ladders, limited respec.
## Drives the real Character and the real server handlers.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const PP = preload("res://shared/path_points.gd")
const PF = preload("res://shared/path_feats.gd")
const PD = preload("res://shared/path_database.gd")
const GoldEconomyScript = preload("res://shared/gold_economy.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class StubConn:
	func get_status() -> int:
		return 0

func _setup(level: int, gold: int):
	var pm = load("res://server/persistence_manager.gd").new()
	get_root().add_child(pm)
	var srv = ServerScript.new()
	srv.persistence = pm
	var hero = CharacterScript.new()
	hero.name = "Dexto"
	hero.class_type = "Fighter"
	hero.level = level
	hero.gold_purse = gold
	srv.characters = {1: hero}
	srv.peers = {1: {"authenticated": true, "account_id": "acct1", "connection": StubConn.new()}}
	return [srv, hero]

func _init() -> void:
	await process_frame
	print("--- the point curve ---")
	var same := true
	for lv in [1, 4, 5, 37, 50, 99, 100]:
		if PP.from_level(lv) != int(lv / 5.0):
			same = false
	ck(same, "through L100 it is exactly the old level/5")
	ck(PP.from_level(150) == 21 and PP.from_level(10000) == 218, "then 1 per 50 levels (L150=%d, L10000=%d)" % [PP.from_level(150), PP.from_level(10000)])
	ck(PP.total_cost(5) == 15 and PP.rank_cost(3) == 3, "rank r costs r; a node maxed costs 15")
	ck(PP.respec_allowance(10) == 3 and PP.respec_allowance(1000) == 4 and PP.respec_allowance(5000) == 5, "respecs: 3, +1 at L1000, +1 at L5000")

	print("--- which nodes can rank ---")
	ck(PD.max_rank(PD.find_node("warrior_1_1")) == 5, "a small percent perk takes 5 ranks")
	ck(PD.max_rank(PD.find_node("warrior_2_2")) == 1, "a duration node stays single-rank")
	ck(PD.max_rank(PD.find_node("warrior_1_5")) == 1 and PD.max_rank(PD.find_node("ck_Fighter")) == 1, "keystones stay single-rank")
	ck(PD.max_rank(PD.find_node("warrior_1_2")) == 3, "a 50% node climbs to its old value over THREE ranks, not five")
	ck(float(PD.rank_effect(PD.find_node("warrior_1_2"), 1).get("bleed_power_pct", 0)) == 25.0 and float(PD.rank_effect(PD.find_node("warrior_1_2"), 3).get("bleed_power_pct", 0)) == 50.0, "...rank 1 is half of it, rank 3 is all of it")
	ck(float(PD.rank_effect(PD.find_node("warrior_1_1"), 3).get("attack_damage_pct", 0)) == 15.0, "rank 3 of +5% damage is +15%")

	print("--- a save from before ranks loses nothing ---")
	var old_save := {"level": 40, "monsters_killed": 10, "path_nodes": ["warrior_1_1", "warrior_1_2"], "path_milestones": ["first_boss_kill"]}
	var vet = CharacterScript.new()
	vet.from_dict(old_save)
	ck(vet.path_rank("warrior_1_1") == 1 and vet.path_rank("warrior_1_2") == 3, "an old plain node becomes rank 1; an old big node is held at its full rank 3 (grandfathered)")
	ck(float(vet.get_path_effect_total("bleed_power_pct")) == 50.0, "...so the veteran still has the full 50%% bleed bonus they paid one point for")
	ck(vet.get_path_points_available() == 7, "points left are 7, exactly as before ranks existed (earned %d incl. the grandfather refund; %d left)" % [vet.get_path_points_earned(), vet.get_path_points_available()])
	ck(vet.claim_feat_rungs().is_empty(), "the old milestone is rung 1 already: nothing is paid twice")
	ck(vet.get_path_effect_total("attack_damage_pct") == 5.0, "its effect is what it was")

	print("--- feats ---")
	var c = CharacterScript.new()
	c.level = 10
	c.monsters_killed = 99
	ck(c.claim_feat_rungs().is_empty(), "99 kills: no rung")
	c.monsters_killed = 100
	var got: Array = c.claim_feat_rungs()
	ck(got.size() == 1 and String(got[0].get("feat", "")) == "kills", "100 kills pays the first kills rung")
	ck(c.claim_feat_rungs().is_empty(), "...once")
	c.bump_feat("bosses", 5)
	ck(c.claim_feat_rungs().size() == 2, "5 bosses reaches rungs 1 and 5 together")
	c.note_feat_max("gear_level", 20)
	c.note_feat_max("gear_level", 10)
	ck(int(c.feat_counts.get("gear_level")) == 20 and c.claim_feat_rungs().size() == 1, "best gear level only goes up, and wearing a level-20 piece pays")
	ck(c.get_path_points_earned() == 2 + 1 + 2 + 1, "level 10 = 2, plus the 6 rungs earned (1+2+1 above: %d)" % c.get_path_points_earned())
	var back = CharacterScript.new()
	back.from_dict(c.to_dict())
	ck(back.get_path_points_earned() == c.get_path_points_earned() and back.claim_feat_rungs().is_empty(), "a save round-trips with nothing re-paid")

	print("--- buying ranks through the real handler ---")
	var s = _setup(40, 0)
	var srv = s[0]
	var hero = s[1]
	srv.handle_path_spend(1, {"node_id": "warrior_1_1"})
	srv.handle_path_spend(1, {"node_id": "warrior_1_1"})
	srv.handle_path_spend(1, {"node_id": "warrior_1_1"})
	ck(hero.path_rank("warrior_1_1") == 3 and hero.get_path_points_spent() == 6, "ranks 1,2,3 cost 1+2+3 = 6 (rank %d, spent %d)" % [hero.path_rank("warrior_1_1"), hero.get_path_points_spent()])
	srv.handle_path_spend(1, {"node_id": "warrior_1_1"})
	ck(hero.path_rank("warrior_1_1") == 3, "rank 4 costs 4 and only 2 are left: refused")
	srv.handle_path_spend(1, {"node_id": "warrior_1_3"})
	ck(hero.path_rank("warrior_1_3") == 0, "a node whose predecessor is not taken is refused")
	srv.handle_path_spend(1, {"node_id": "warrior_1_2"})
	ck(hero.path_rank("warrior_1_2") == 1, "the next node in the branch opens once the first is held")
	ck(hero.get_path_effect_total("attack_damage_pct") == 15.0, "the effect reads the rank (3 x 5%)")
	srv.handle_path_spend(1, {"node_id": "mage_1_1"})
	ck(hero.path_rank("mage_1_1") == 0, "another archetype's node is refused")

	print("--- limited respec ---")
	var refund: int = PP.total_cost(3) + PP.total_cost(1)
	var price: int = PP.respec_price(40, refund)
	ck(price == refund * 40 * GoldEconomyScript.kill_gold(40), "price is 40 kills' gold per point refunded (%d)" % price)
	srv.handle_path_respec(1, {"branch": "onslaught"})
	ck(hero.path_rank("warrior_1_1") == 3 and hero.path_respecs_used == 0, "asking without confirming changes nothing")
	srv.handle_path_respec(1, {"branch": "onslaught", "confirm": true})
	ck(hero.path_rank("warrior_1_1") == 3, "no gold: refused")
	hero.gold_purse = price + 7
	srv.handle_path_respec(1, {"branch": "onslaught", "confirm": true})
	ck(hero.path_rank("warrior_1_1") == 0 and hero.path_rank("warrior_1_2") == 0, "the branch is wound back to nothing")
	ck(hero.gold_purse == 7 and hero.path_respecs_used == 1, "...for exactly the price, using one respec")
	ck(hero.get_path_points_available() == 8, "...and every point comes back (%d)" % hero.get_path_points_available())
	ck(hero.get_path_effect_total("attack_damage_pct") == 0.0, "...and the effect goes with it (the cache is not stale)")
	hero.path_respecs_used = 3
	srv.handle_path_spend(1, {"node_id": "warrior_1_1"})
	hero.gold_purse = 10000000
	srv.handle_path_respec(1, {"branch": "onslaught", "confirm": true})
	ck(hero.path_rank("warrior_1_1") == 1, "with the allowance used up, a respec is refused")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
