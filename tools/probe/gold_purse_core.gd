extends SceneTree
## Playtest sheet item 50, slice 1 (owner decisions 2026-10-14): a per-character GOLD purse, kill income,
## gems sell at 1,000 each, and a HUD readout. Gold is NOT the retired `gold` field (which a login
## migration converts to Valor), so a purse must never be eaten by that migration.
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
	# --- formula
	ck(Gold.kill_gold(50) > Gold.kill_gold(5) and Gold.kill_gold(1) >= 1, "kill gold rises with the monster's level and is never 0")
	ck(Gold.kill_gold(50, true) == Gold.kill_gold(50) * 4, "a boss pays x4")
	ck(Gold.kill_gold(50, false, 2) > Gold.kill_gold(50), "empowered mods pay more")
	ck(Gold.GEM_GOLD_VALUE == 1000, "1 gem = 1,000 gold")
	# --- the purse
	var c = CharacterScript.new()
	c.initialize("Hero", "Fighter", "Human")
	ck(c.gold_purse == 0, "starts empty")
	c.add_gold(250)
	ck(c.gold_purse == 250 and c.add_gold(-5) == 0 and c.gold_purse == 250, "add_gold adds and ignores negatives")
	ck(not c.spend_gold(251) and c.gold_purse == 250, "a short purse pays nothing and loses nothing")
	ck(c.spend_gold(100) and c.gold_purse == 150, "spend_gold pays")
	var d: Dictionary = c.to_dict()
	var c2 = CharacterScript.new()
	c2.from_dict(d)
	ck(c2.gold_purse == 150, "the purse survives a save round trip")
	ck(c2.gold == 0, "...and the retired `gold` field stays untouched (the Valor migration cannot eat the purse)")
	var old = CharacterScript.new()
	var od: Dictionary = c.to_dict()
	od.erase("gold_purse")
	old.from_dict(od)
	ck(old.gold_purse == 0, "a save from before this shipped loads with an empty purse")
	# --- server: gem sale + funnel
	var srv = QuietServer.new()
	var h = CharacterScript.new()
	h.initialize("Hero", "Fighter", "Human")
	h.crafting_materials["monster_gem"] = 7
	srv.characters = {1: h}
	srv.peers = {1: {"authenticated": true, "account_id": "a", "connection": StubConn.new()}}
	srv.handle_merchant_sell_gems(1, {"count": 0})
	ck(h.gold_purse == 0 and int(h.crafting_materials.get("monster_gem", 0)) == 7, "away from a merchant nothing is sold")
	srv.at_merchant[1] = {"services": []}
	srv.handle_merchant_sell_gems(1, {"count": 3})
	ck(h.gold_purse == 3000 and int(h.crafting_materials.get("monster_gem", 0)) == 4, "3 gems sold = 3,000 gold, 4 left")
	srv.handle_merchant_sell_gems(1, {"count": 0})
	ck(h.gold_purse == 7000 and int(h.crafting_materials.get("monster_gem", 0)) == 0, "the rest sold = 7,000 gold in all")
	srv.handle_merchant_sell_gems(1, {"count": 0})
	ck(h.gold_purse == 7000, "no gems, no gold")
	ck(srv._award_gold(1, 0) == 0 and srv._award_gold(1, -5) == 0 and srv._award_gold(99, 50) == 0, "the funnel ignores nothing/negative/unknown peers")
	ck(srv._award_gold(1, 40, "test", true) == 40 and h.gold_purse == 7040, "the funnel credits the purse")
	# --- the kill hooks, as statements
	var sv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(sv.find("\t\t\t_award_gold(peer_id, GoldEconomyScript.kill_gold(") >= 0, "solo victory pays kill gold (statement)")
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.find("\t\tcharacter.add_gold(party_gold)\n") >= 0, "party victory pays every surviving member (statement)")
	# --- HUD
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var cl = (load("res://client/client.tscn") as PackedScene).instantiate()
	get_root().add_child(cl)
	for _i in range(8):
		await process_frame
	cl.has_character = true
	cl.character_data = {"valor": 5, "gold_purse": 12345}
	cl.update_currency_display()
	ck(cl._purse_label != null and cl._purse_label.text == cl.format_number(12345), "the HUD shows the purse in the same style as Valor (%s)" % (cl._purse_label.text if cl._purse_label else "none"))
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
