extends SceneTree
## Playtest sheet item 50, slice 4 (owner 2026-10-14): the GOLD SINK. Per-item upgrade tiers at the
## blacksmith - weapons gain damage, everything else gains HP. They must be CAPPED (the old uncapped
## blacksmith upgrade was removed on purpose), paid only when the tier lands, and real in the stat
## aggregator - a tier that only edits a number nobody reads is the failure this repo keeps finding.
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
class QuietPM extends "res://server/persistence_manager.gd":
	func save_corpses() -> void:
		pass

class StubConn:
	func get_status() -> int:
		return 0

func _init() -> void:
	# --- the numbers
	ck(Gold.temper_cost(50, 2) > Gold.temper_cost(50, 1) and Gold.temper_cost(100, 1) > Gold.temper_cost(50, 1), "cost rises with the tier and with the item level")
	ck(Gold.temper_gain("weapon", 50).stat == "attack_bonus" and Gold.temper_gain("armor", 50).stat == "hp_bonus" and Gold.temper_gain("ring", 50).stat == "hp_bonus", "weapons gain damage, everything else HP")
	ck(Gold.temper_gain("armor", 50).amount > Gold.temper_gain("ring", 50).amount, "a ring gains less HP than body armour")
	ck(Gold.TEMPER_MAX_TIERS == 5, "capped at 5 tiers")

	var pm = QuietPM.new()
	get_root().add_child(pm)
	await process_frame
	var srv = QuietServer.new()
	srv.persistence = pm
	var h = CharacterScript.new()
	h.initialize("Hero", "Fighter", "Human")
	h.level = 50
	h.equipped["weapon"] = {"name": "Test Blade", "type": "weapon_sword", "level": 50, "rarity": "epic", "affixes": {"attack_bonus": 22}}
	h.equipped["armor"] = {"name": "Test Plate", "type": "armor_plate", "level": 50, "rarity": "epic", "affixes": {"hp_bonus": 100}}
	srv.characters = {1: h}
	srv.peers = {1: {"authenticated": true, "account_id": "a", "connection": StubConn.new()}}
	srv.pending_blacksmith_encounters[1] = {"items": [], "total_cost": 0, "repair_all_cost": 0}

	# --- poor: nothing happens, nothing is taken
	h.gold_purse = 10
	var atk0: int = h.get_total_attack()
	srv.handle_blacksmith_choice(1, {"choice": "select_upgrade_item", "slot": "weapon"})
	ck(h.gold_purse == 10 and int(h.equipped["weapon"].get("temper", 0)) == 0 and int(h.equipped["weapon"].affixes.attack_bonus) == 22, "too poor: no tier, no gold taken")

	# --- weapon: five tiers, each priced and applied, and the stat aggregator really moves
	h.gold_purse = 1000000
	var paid := 0
	for t in range(1, 6):
		var before: int = h.gold_purse
		srv.handle_blacksmith_choice(1, {"choice": "select_upgrade_item", "slot": "weapon"})
		var cost: int = Gold.temper_cost(50, t)
		paid += cost
		ck(before - h.gold_purse == cost and int(h.equipped["weapon"].temper) == t, "tier %d costs %s and lands" % [t, str(cost)])
	var gain: int = int(Gold.temper_gain("weapon", 50).amount)
	ck(int(h.equipped["weapon"].affixes.attack_bonus) == 22 + 5 * gain, "five tiers added 5 x %d damage (22 -> %d)" % [gain, int(h.equipped["weapon"].affixes.attack_bonus)])
	ck(h.get_total_attack() > atk0, "...and the character's real attack went up (%d -> %d)" % [atk0, h.get_total_attack()])
	# --- the cap
	var gold_at_cap: int = h.gold_purse
	srv.handle_blacksmith_choice(1, {"choice": "select_upgrade_item", "slot": "weapon"})
	ck(h.gold_purse == gold_at_cap and int(h.equipped["weapon"].temper) == 5, "a 6th tier is refused and costs nothing (capped)")
	# --- armour gains HP, and max HP really moves
	var hp0: int = h.get_total_max_hp()
	srv.handle_blacksmith_choice(1, {"choice": "select_upgrade_item", "slot": "armor"})
	ck(int(h.equipped["armor"].affixes.hp_bonus) == 100 + int(Gold.temper_gain("armor", 50).amount), "armour gained HP")
	ck(h.get_total_max_hp() > hp0, "...and max HP really went up (%d -> %d)" % [hp0, h.get_total_max_hp()])
	# --- an empty slot
	var g2: int = h.gold_purse
	srv.handle_blacksmith_choice(1, {"choice": "select_upgrade_item", "slot": "boots"})
	ck(h.gold_purse == g2, "an empty slot costs nothing")
	# --- the list the client shows
	var rows: Array = srv._temper_rows(h)
	var wrow: Dictionary = {}
	for r in rows:
		if r.slot == "weapon":
			wrow = r
	ck(not wrow.is_empty() and String(wrow.line).find("fully tempered 5/5") >= 0, "the list says a maxed piece is fully tempered")
	# --- the legacy uncapped upgrade is still refused
	var sv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(sv.find("\tif choice in [\"upgrade\", \"confirm_upgrade\"]:") >= 0, "the old 'upgrade' / 'confirm_upgrade' choices are still refused (statement)")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
