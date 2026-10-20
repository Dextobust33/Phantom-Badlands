extends SceneTree
## The Master Smith: an announced, occasional gold sink for a piece of gear far above what the level drops
## (docs/design/economy.md 4.6). Drives the real server handlers.
const ServerScript = preload("res://server/server.gd")
const CharacterScript = preload("res://shared/character.gd")
const MS = preload("res://shared/master_smith.gd")
const GoldEconomyScript = preload("res://shared/gold_economy.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

class StubConn:
	func get_status() -> int:
		return 0

class StubChunks extends "res://shared/chunk_manager.gd":
	func get_nearest_npc_post(_x, _y) -> Dictionary:
		return {"x": 5, "y": 5, "name": "Probe Post"}

func _setup(gold: int):
	var pm = load("res://server/persistence_manager.gd").new()
	get_root().add_child(pm)
	var srv = ServerScript.new()
	srv.persistence = pm
	srv.chunk_manager = StubChunks.new()
	srv.drop_tables = load("res://shared/drop_tables.gd").new()
	pm.houses_data["houses"]["acct1"] = pm.create_house("acct1")
	var hero = CharacterScript.new()
	hero.name = "Dexto"
	hero.class_type = "Fighter"
	hero.level = 40
	hero.x = 5
	hero.y = 6
	hero.gold_purse = gold
	srv.characters = {1: hero}
	srv.peers = {1: {"authenticated": true, "account_id": "acct1", "connection": StubConn.new()}}
	return [srv, hero]

func _init() -> void:
	await process_frame
	print("--- the offer's shape ---")
	var worn := {"weapon": {"rarity": "rare", "level": 30}, "armor": {"rarity": "epic", "level": 35}, "helm": null, "shield": null, "boots": null, "ring": null, "amulet": null}
	ck(MS.offer_rarity(worn) == "legendary", "one step above the best worn (epic -> %s)" % MS.offer_rarity(worn))
	ck(MS.offer_rarity({}) == "epic", "never below epic")
	ck(MS.offer_level(40) > 40, "item level beats the player's (%d)" % MS.offer_level(40))
	var slots: Array = MS.pick_slots(worn, 3)
	ck(slots.size() == 3 and slots.size() == slots.duplicate().size(), "three slots")
	ck(not ("armor" in slots) and not ("weapon" in slots), "...the empty slots first, never the best-covered (%s)" % str(slots))
	ck(MS.price(50) == 800 * GoldEconomyScript.kill_gold(50), "price is 800 kills' gold (L50: %d)" % MS.price(50))
	var live := {"expires": 1000, "locked": false}
	ck(MS.is_live(live, 999) and not MS.is_live(live, 1001), "an unlocked offer lapses")
	live["locked"] = true
	ck(MS.is_live(live, 99999), "a locked offer is held")

	print("--- the real handlers ---")
	var s = _setup(10)
	var srv = s[0]
	var hero = s[1]
	srv._master_smith_visit(1)
	ck(not hero.master_offer.is_empty() and hero.master_offer.get("items", []).size() == 3, "a visit builds an offer of three")
	ck(srv._master_offer_here(1), "...at the post the hero stands beside")
	var first: Dictionary = hero.master_offer["items"][0]
	ck(int(first.get("level", 0)) >= MS.offer_level(40), "...of a level above the hero's (%d)" % int(first.get("level", 0)))
	ck(["epic", "legendary", "artifact"].has(String(first.get("rarity"))), "...and epic or better (%s)" % str(first.get("rarity")))
	var inv_before: int = hero.inventory.size()
	srv._master_choice(1, "master_buy", {"slot": "0"})
	ck(hero.inventory.size() == inv_before and not hero.master_offer.is_empty(), "too little gold: nothing taken, offer kept")
	srv._master_choice(1, "master_lock", {})
	ck(bool(hero.master_offer.get("locked", false)), "lock holds the offer")
	hero.master_offer["expires"] = 1
	ck(MS.is_live(hero.master_offer, int(Time.get_unix_time_from_system())), "...even past its window")
	var price: int = int(hero.master_offer.get("price", 0))
	hero.gold_purse = price + 123
	srv._master_choice(1, "master_buy", {"slot": "1"})
	ck(hero.gold_purse == 123, "buying takes exactly the price (purse %d)" % hero.gold_purse)
	ck(hero.inventory.size() == inv_before + 1, "...and the piece lands in the pack")
	ck(hero.master_offer.is_empty(), "...and the other two go with the master")
	srv._master_choice(1, "master_buy", {"slot": "0"})
	ck(hero.inventory.size() == inv_before + 1 and hero.gold_purse == 123, "no offer left: no second purchase")
	var back = CharacterScript.new()
	back.from_dict(hero.to_dict())
	ck(back.master_clock == hero.master_clock, "the visit clock survives a save")
	srv._master_smith_visit(1)
	var saved = CharacterScript.new()
	saved.from_dict(hero.to_dict())
	ck(saved.master_offer.get("items", []).size() == 3, "an offer survives a save")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
