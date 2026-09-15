extends SceneTree
## Use EVERY usable item type mid-fight - and out of one - and report what actually happened.
##
## Owner 2026-09-15, on the equipment/item audit: *"ensure it also tries to use items in combat. Some
## aren't meant for in combat use and may cause problems or unexpected things to happen."*
##
## Three ways an item gets used, each measured on a fresh copy of the same character:
##   COMBAT  - the combat Use Item menu (and the inventory panel while in a fight) send
##             `combat_use_item` -> combat_manager.process_use_item
##   INV@CMB - `inventory_use` arriving while a fight is running (the dungeon Escape button sends it;
##             handle_inventory_use has no combat gate of its own)
##   OUTSIDE - `inventory_use` on the overworld, no fight - catches the refusals that fire AFTER the
##             item was already taken
## For each: was the item taken, did anything about the character change, did the fight survive,
## and what did the player read. It classifies; it does not fail - several rows are design questions.
## OFFERED = the client's own combat-menu filter (`_is_combat_usable_item`) would list it mid-fight.
const PEER := 1

class RecServer extends "res://server/server.gd":
	var said: Array = []
	func send_to_peer(peer_id: int, message: Dictionary):
		var t := String(message.get("type", ""))
		if t in ["text", "error", "combat_message"] or message.has("message"):
			said.append("%s: %s" % [t, String(message.get("message", ""))])
		else:
			said.append(t)
		super.send_to_peer(peer_id, message)
	func send_combat_message(peer_id: int, msg: String, actor: String = "", dmg: int = 0, mhp: int = -1):
		said.append("combat: " + msg)


var sv
var base_dict: Dictionary
var dungeon_dict: Dictionary
var client_filter = null
var dupes := 0   # the one verdict that is never a design question
var stack_eaten := 0   # one use that removed a whole stack
# Keys that change on every save/tick and say nothing about the item.
const NOISE := ["last_saved", "last_active", "play_time", "updated_at", "last_login", "inventory",
	"in_combat", "combat_log", "last_combat_time", "ability_uses_this_combat", "rng_state"]


func _item(t: String) -> Dictionary:
	# Scribing output built by the server's own crafting functions from the real recipe, not by hand.
	if t.begins_with("craft:"):
		var rid := t.substr(6)
		var rec: Dictionary = sv.CraftingDatabaseScript.RECIPES[rid]
		var q: int = sv.CraftingDatabaseScript.CraftingQuality.STANDARD
		match String(rec.get("output_type", "")):
			"scroll": return sv._craft_scroll(rec, q)
			"map": return sv._craft_map(rec, q)
			"tome": return sv._craft_tome(rec, q)
			"bestiary": return sv._craft_bestiary(rec, q)
			"consumable":
				var cc: Dictionary = sv._create_crafted_consumable(rec, q)
				cc["quantity"] = 1
				return cc
	match t:
		"escape_scroll":
			var e: Dictionary = sv.DungeonDatabaseScript.make_escape_scroll(1)
			e["is_consumable"] = true
			e["level"] = 1
			return e
		"dungeon_compass":
			return {"name": "Dungeon Compass", "item_type": "dungeon_compass", "type": "consumable", "tier_max": 2, "is_consumable": true}
		"apex_sigil":
			return sv.drop_tables._generate_item({"item_type": "apex_sigil", "rarity": "epic"}, 30)
		"ability_tome":
			return sv.drop_tables._generate_item({"item_type": "ability_tome"}, 30)
		"treasure_chest":
			return {"name": "Small Treasure Chest", "type": "treasure_chest", "is_consumable": true, "tier": 1, "quantity": 1}
		"enhancement_scroll":
			return {"name": "Weapon Enhancement", "type": "enhancement_scroll", "slot": "weapon", "effect": {"stat": "attack", "bonus": 5},
				"rarity": "common", "level": 1, "is_consumable": true, "quantity": 1}
		"scroll":
			return {"name": "Scroll of Might", "type": "scroll", "is_consumable": true, "quantity": 1, "level": 1, "rarity": "common",
				"effect": {"type": "buff", "stat": "attack", "bonus_pct": 10, "duration_battles": 3}}
		"area_map":
			return {"name": "Area Map", "type": "area_map", "is_consumable": true, "quantity": 1, "reveal_radius": 20, "level": 1, "rarity": "common"}
		"spell_tome":
			return {"name": "Tome of Strength", "type": "spell_tome", "is_consumable": true, "quantity": 1, "stat": "strength", "amount": 1, "level": 1, "rarity": "common"}
		"bestiary_page":
			return {"name": "Bestiary Page", "type": "bestiary_page", "is_consumable": true, "quantity": 1, "level": 1, "rarity": "common"}
	var it: Dictionary = sv.drop_tables._generate_item({"item_type": t}, 30)
	if not it.has("tier"):
		it["tier"] = 3
	return it


## Everything else in the bag, so an item that GIVES an item (a box, a chest) is not read as "nothing".
func _others(ch, proto: Dictionary) -> String:
	var parts: Array = []
	for it in ch.inventory:
		if it is Dictionary and not (String(it.get("name", "")) == String(proto.get("name", "")) 				and String(it.get("type", "")) == String(proto.get("type", ""))):
			parts.append("%s x%d" % [String(it.get("name", "")), int(it.get("quantity", 1))])
	parts.sort()
	return ",".join(parts)


func _count(ch, proto: Dictionary) -> int:
	var n := 0
	for it in ch.inventory:
		if it is Dictionary and String(it.get("name", "")) == String(proto.get("name", "")) \
				and String(it.get("type", "")) == String(proto.get("type", "")):
			n += int(it.get("quantity", 1)) if it.get("is_consumable", false) else 1
	return n


func _fresh(in_dungeon: bool = false):
	var CharacterScript = load("res://shared/character.gd")
	var ch = CharacterScript.new()
	ch.from_dict((dungeon_dict if in_dungeon else base_dict).duplicate(true))
	sv.characters[PEER] = ch
	sv.pending_scroll_use.erase(PEER)
	sv.pending_home_stone_companion.erase(PEER)
	sv.combat_mgr.active_combats.erase(PEER)
	return ch


func _fight(ch) -> void:
	var mon: Dictionary = sv.monster_db.generate_monster(3, 1)
	mon["max_hp"] = 99999
	mon["current_hp"] = 99999
	mon["strength"] = 1
	mon["abilities"] = []
	sv.combat_mgr.start_combat(PEER, ch, mon)
	ch.in_combat = true
	var c = sv.combat_mgr.active_combats[PEER]
	c["player_can_act"] = true


func _diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in b:
		if k in NOISE:
			continue
		if not a.has(k) or JSON.stringify(a[k]) != JSON.stringify(b[k]):
			out.append(String(k))
	return out


## `spec` is an item type, optionally with modifiers after "|": pet (an active companion), ko (a
## knocked-out one), tgt (aim the item at the companion), dgn (standing in the starter dungeon).
func _run(spec: String, how: String) -> Dictionary:
	var t: String = spec.split("|")[0]
	var mods: String = spec.substr(spec.find("|")) if spec.contains("|") else ""
	var ch = _fresh(mods.contains("dgn"))
	if mods.contains("pet") or mods.contains("ko"):
		var pdata: Dictionary = sv.drop_tables.COMPANION_DATA.get("Wolf", {})
		ch.active_companion = {"id": "probe_comp", "monster_type": "Wolf", "name": String(pdata.get("companion_name", "Wolf")),
			"tier": int(pdata.get("tier", 1)), "level": 5, "xp": 0, "bonuses": (pdata.get("bonuses", {}) as Dictionary).duplicate(),
			"variant": "Normal", "sub_tier": 1, "border_tier": 1}
		ch.set_companion_combat_hp(0 if mods.contains("ko") else maxi(1, int(ch.get_companion_max_hp() / 2)))
	if mods.contains("capped") or mods.contains("gear"):
		# A weapon to enhance - at the attack enchantment cap for "capped", bare for "gear".
		var wpn := {"type": "weapon_iron", "name": "Probe Blade", "rarity": "rare", "level": 30, "affixes": {}, "enchantments": {}}
		if mods.contains("capped"):
			wpn["enchantments"]["attack"] = int(sv.CraftingDatabaseScript.ENCHANTMENT_STAT_CAPS.get("attack", 60))
		ch.equipped["weapon"] = wpn
	# A little hurt and drained, so heals and restores have something to fill.
	ch.current_hp = maxi(1, int(ch.get_total_max_hp() / 2))
	ch.current_mana = 0
	ch.current_stamina = 0
	ch.current_energy = 0
	if how != "OUTSIDE":
		_fight(ch)
	var proto := _item(t)
	var placed := proto.duplicate(true)
	if mods.contains("qty3"):
		placed["quantity"] = 3   # a stack: one use must take ONE
	ch.inventory.append(placed)
	var idx: int = ch.inventory.size() - 1
	# DEEP copy: to_dict hands back the live buff/material containers, so a shallow snapshot mutates
	# along with the character and every effect diffs as "nothing changed". The first run did exactly that.
	var before: Dictionary = ch.to_dict().duplicate(true)
	var n0 := _count(ch, proto)
	var o0 := _others(ch, proto)
	sv.said.clear()
	var msg := {"index": idx}
	if mods.contains("tgt"):
		msg["target"] = "companion"
	if how == "COMBAT":
		sv.handle_combat_use_item(PEER, msg)
	else:
		sv.handle_inventory_use(PEER, msg)
	var ch2 = sv.characters.get(PEER, ch)
	var after: Dictionary = ch2.to_dict()
	var n1 := _count(ch2, proto)
	var changed := _diff(before, after)
	if _others(ch2, proto) != o0:
		changed.append("inventory")
	var fight_on: bool = sv.combat_mgr.active_combats.has(PEER)
	var pending: bool = sv.pending_scroll_use.has(PEER) or sv.pending_home_stone_companion.has(PEER) or ch2.has_meta("pending_home_stone_index")
	var said_txt := " | ".join(sv.said.filter(func(s): return not String(s) in ["character_update", "location", "inventory_update"]))
	var taken: bool = n1 < n0
	var verdict := ""
	if n1 > n0:
		verdict = "DUPLICATED"
		dupes += 1
	elif taken and changed.is_empty() and not pending:
		verdict = "EATEN-NOTHING"
	elif taken:
		verdict = "used"
	elif not changed.is_empty():
		verdict = "FREE-EFFECT"
	elif pending:
		verdict = "prompt"
	else:
		verdict = "refused"
	if taken and n0 - n1 > 1 and t != "treasure_chest":
		verdict += "+ATE-STACK(%d)" % (n0 - n1)
		stack_eaten += 1
	if how != "OUTSIDE" and not fight_on:
		verdict += "+FIGHT-GONE"
	if how != "OUTSIDE" and bool(after.get("in_dungeon", false)) != bool(before.get("in_dungeon", false)):
		verdict += "+LEFT-DUNGEON"
	sv.combat_mgr.active_combats.erase(PEER)
	return {"verdict": verdict, "changed": changed, "said": said_txt.substr(0, 150)}


func _init() -> void:
	sv = RecServer.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)
	var made: Dictionary = sv.persistence.create_account("iic%d" % (Time.get_ticks_usec() % 100000), "probe-password")
	sv.peers[PEER] = {"authenticated": true, "account_id": String(made.get("account_id", "")), "character_name": "",
		"connection": StreamPeerTCP.new()}
	var nm := "Iic"
	var u: int = Time.get_ticks_usec()
	for i in range(4):
		nm += char(97 + (u % 26))
		u /= 26
	sv.handle_create_character(PEER, {"name": nm, "class": "Fighter", "race": "Human"})
	await process_frame
	var ch0 = sv.characters[PEER]
	ch0.level = 30
	base_dict = ch0.to_dict().duplicate(true)
	# A second starting point standing on floor 1 of the personal starter dungeon, entered the way a
	# player enters it (see instance_floor_count.gd), for the items whose rules depend on being inside.
	sv._ensure_starter_dungeon_exists()
	for d in sv.active_dungeons:
		if bool(sv.active_dungeons[d].get("starter", false)):
			ch0.x = int(sv.active_dungeons[d].get("world_x", 0))
			ch0.y = int(sv.active_dungeons[d].get("world_y", 0))
			sv.handle_dungeon_enter(PEER, {"dungeon_type": String(sv.active_dungeons[d].get("dungeon_type", "")), "confirmed": true})
			break
	await process_frame
	print("[ITEMS] dungeon start: in_dungeon=%s floor=%d" % [ch0.in_dungeon, ch0.dungeon_floor])
	dungeon_dict = sv.characters[PEER].to_dict().duplicate(true)
	print("[ITEMS] apex sigil as the drop generator builds it: %s" % JSON.stringify(sv.drop_tables._generate_item({"item_type": "apex_sigil", "rarity": "epic"}, 30)))
	client_filter = load("res://client/client.gd").new()

	var types: Array = []
	for k in sv.drop_tables.POTION_EFFECTS.keys():
		types.append(String(k))
	types += ["escape_scroll", "dungeon_compass", "apex_sigil", "ability_tome", "treasure_chest",
		"enhancement_scroll",
		"potion_revive_companion|ko", "charm_taunt|pet", "health_potion|ko|tgt", "health_potion|pet|tgt",
		"enhancement_scroll|gear", "enhancement_scroll|capped", "health_potion|qty3", "escape_scroll|dgn|qty3",
		"dungeon_compass|qty3", "ability_tome|qty3", "apex_sigil|qty3", "tome_strength|qty3", "floor_skip_charm|dgn", "escape_scroll|dgn", "home_stone_supplies|dgn", "scroll_time_stop|dgn"]

	for rid in sv.CraftingDatabaseScript.RECIPES:
		if String(sv.CraftingDatabaseScript.RECIPES[rid].get("output_type", "")) in ["scroll", "map", "tome", "bestiary", "consumable"]:
			types.append("craft:" + String(rid))
	print("[ITEMS] %-26s %-7s | %-24s | %-24s | %-24s" % ["item", "OFFERED", "COMBAT menu", "inventory_use in fight", "OUTSIDE a fight"])
	for t in types:
		var proto := _item(String(t).split("|")[0])
		var offered: bool = client_filter._is_combat_usable_item(proto)
		var cells: Array = []
		var details: Array = []
		for how in ["COMBAT", "INV@CMB", "OUTSIDE"]:
			print("[ITEMS-RUN] %s %s" % [t, how])   # any SCRIPT ERROR prints right after the row that raised it
			var r := _run(t, how)
			cells.append(String(r.verdict))
			details.append("    %-7s changed=%s  said=%s" % [how, ",".join(r.changed), r.said])
		print("[ITEMS] %-26s %-7s | %-24s | %-24s | %-24s" % [t, "yes" if offered else "no", cells[0], cells[1], cells[2]])
		for d in details:
			print("[ITEMS-D] " + d)
	client_filter.free()
	# EVERY BUFF A CONSUMABLE WRITES MUST HAVE A READER. Crafted Rage wrote "attack", Forcefield "shield",
	# Insight "xp_bonus", Luck "rare_drop" - all read by nothing, so the potions did nothing. The writes
	# come from the real resolver (drop_tables.consumable_buff_writes) over every drop type and every
	# crafted recipe; a reader is a get_buff_value/has_buff call naming it. equipment_audit.gd MEASURES
	# the common names; this catches a new name the day it is added.
	var src := ""
	for f in ["res://shared/combat_manager.gd", "res://shared/character.gd", "res://server/server.gd"]:
		src += FileAccess.get_file_as_string(f)
	var unread: Array = []
	var probe_ch = _fresh()
	var all_items: Array = []
	for k in sv.drop_tables.POTION_EFFECTS.keys():
		all_items.append(_item(String(k)))
	for rid in sv.CraftingDatabaseScript.RECIPES:
		if String(sv.CraftingDatabaseScript.RECIPES[rid].get("output_type", "")) in ["scroll", "consumable"]:
			all_items.append(_item("craft:" + String(rid)))
	for it in all_items:
		var eff: Dictionary = sv.drop_tables.consumable_effect(it)
		if not eff.has("buff"):
			continue
		for w in sv.drop_tables.consumable_buff_writes(it, eff, probe_ch, int(it.get("tier", 3))):
			var nm2 := String(w.type)
			if not (src.contains('get_buff_value("%s")' % nm2) or src.contains('has_buff("%s")' % nm2)):
				unread.append("%s -> %s" % [String(it.get("name", "?")), nm2])
	print("[ITEMS] buff names with no reader: %s" % ("none" if unread.is_empty() else ", ".join(unread)))

	# THE DUNGEON-CRYSTAL RUNES. Until 2026-09-15 their recipes had no slot or effect and every craft
	# refunded. Built by the real rune builder, applied by the real handler, read by the real aggregator.
	var rune_fail := 0
	for spec in [["void_rune", "weapon", "attack"], ["abyssal_rune", "armor", "defense"], ["primordial_rune", "helm", "max_hp"]]:
		var rch = _fresh()
		rch.equipped[spec[1]] = {"type": "%s_iron" % spec[1] if spec[1] != "weapon" else "weapon_iron", "name": "Probe Piece", "rarity": "rare", "level": 30, "affixes": {}}
		var before_stat: int = int(rch.get_equipment_bonuses().get(spec[2], 0))
		var rune: Dictionary = sv._create_crafted_rune(sv.CraftingDatabaseScript.RECIPES[spec[0]], sv.CraftingDatabaseScript.CraftingQuality.STANDARD, "probe")
		rch.inventory.append(rune)
		sv.handle_use_rune(PEER, {"rune_index": rch.inventory.size() - 1, "target_slot": spec[1]})
		var after_stat: int = int(rch.get_equipment_bonuses().get(spec[2], 0))
		var ok_r: bool = after_stat > before_stat
		if not ok_r:
			rune_fail += 1
		print("[ITEMS] %-16s on %-6s %s %d -> %d  %s" % [spec[0], spec[1], spec[2], before_stat, after_stat, "works" if ok_r else "NO EFFECT"])

	# CURSED COIN, both faces, through the real handler and the real encounter. Owner 2026-09-15: heads
	# is better loot for a few fights, tails an elite next.
	var coin_fail := 0
	var faces := {}
	for attempt in range(40):
		var cch = _fresh()
		cch.x = 57
		cch.y = -11
		cch.inventory.append(_item("cursed_coin"))
		sv.handle_inventory_use(PEER, {"index": cch.inventory.size() - 1})
		if cch.get_buff_value("rare_drop") >= 100:
			faces["heads"] = true
		for d in cch.pending_monster_debuffs:
			if String(d.get("type", "")) == "elite":
				faces["tails"] = true
				sv.trigger_encounter(PEER)
				var fought = sv.combat_mgr.active_combats.get(PEER, {})
				var is_elite: bool = not fought.is_empty() and bool(fought.monster.get("is_elite", false))
				faces["tails_elite"] = is_elite
				sv.combat_mgr.active_combats.erase(PEER)
				break
		if faces.has("heads") and faces.has("tails_elite"):
			break
	if not (faces.get("heads", false) and faces.get("tails_elite", false)):
		coin_fail = 1
	print("[ITEMS] cursed coin faces seen: %s  %s" % [str(faces), "works" if coin_fail == 0 else "FAIL"])

	# Everything else is classified for the owner; a duplication is a failure outright. Proven to fire:
	# the Enhancement Scroll at its cap reported DUPLICATED on the code before 2026-09-15's fix.
	var ok: bool = dupes == 0 and unread.is_empty() and stack_eaten == 0 and rune_fail == 0 and coin_fail == 0
	print("RESULT: %s (%d duplicating uses, %d unread buff names, %d uses that ate a stack)" % ["PASS" if ok else "FAIL", dupes, unread.size(), stack_eaten])
	quit(0 if ok else 1)
