extends SceneTree
## Does a new character start at full health, and does the Warden arm them instead of creation?
##
## Owner 2026-09-14: *"New characters are starting out low on health because you're still giving
## them a bunch of starter gear (which they should be getting a piece or two from the warden,
## another one from the first fights loot, and the rest in the dungeon)."*
##
## Both halves of that were true and they were the same fault seen from two sides. `initialize()`
## sets current_hp from the BASE max; equipping anything afterwards raises get_total_max_hp()
## through equipment HP and equipment CON x5, and nothing topped the player up. Seven starter
## pieces later, a level 1 who had never been hit stood at **129/142**.
const Character = preload("res://shared/character.gd")
const DropTables = preload("res://shared/drop_tables.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")

	print("===== EQUIPPING RAISES MAX HP - WHICH IS THE WHOLE MECHANISM =====")
	# Prove the cause rather than assert the fix, so this check still means something if the
	# grant ever comes back in another form.
	var dt = DropTables.new()
	get_root().add_child(dt)
	var ch = Character.new()
	ch.initialize("Test", "Fighter", "Human")
	var bare: int = ch.get_total_max_hp()
	var hp_before: int = ch.current_hp
	ck(hp_before == bare, "a character with nothing on starts at full (%d/%d)" % [hp_before, bare])

	var added := 0
	for slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]:
		var base := ""
		for tier_try in range(1, 10):
			for entry in dt.EQUIPMENT_BASES.get(tier_try, []):
				if String(entry.get("item_type", "")).begins_with(slot):
					base = String(entry["item_type"])
					break
			if base != "":
				break
		if base == "":
			continue
		var piece = dt._generate_item({"item_type": base}, 1, "common")
		if piece is Dictionary and not piece.is_empty() and ch.equipped.has(slot):
			ch.equipped[slot] = piece
			added += 1
	var geared: int = ch.get_total_max_hp()
	print("  %d common pieces on: max hp %d -> %d, current_hp untouched at %d"
		% [added, bare, geared, ch.current_hp])
	ck(added > 0, "the kit equips (or this check proves nothing)")
	ck(geared > bare, "and gear really does raise max hp - that is the 129/142")
	ck(ch.current_hp < geared,
		"  and current_hp does NOT follow it, which is the bug the owner saw")

	print("")
	print("===== SO CREATION TOPS EVERYTHING UP, AFTER EVERY GRANT =====")
	ck(src.contains("character.current_hp = character.get_total_max_hp()"),
		"creation sets current_hp from the TOTAL, not the base")
	for res in ["current_mana", "current_stamina", "current_energy"]:
		ck(src.contains("character.%s = character.get_total_max_" % res),
			"  and %s too" % res)
	# Placement matters more than presence: it has to be after the last thing that can change
	# a maximum, or the next grant added to creation re-opens the hole.
	# Scoped to handle_create_character. The first cut searched the whole FILE, so `i_save`
	# matched a save_character call in some earlier function and the ordering check compared
	# two unrelated offsets - an assertion that was measuring nothing.
	var i_fn := src.find("func handle_create_character")
	var i_fn_end := src.find("
func handle_delete_character")
	var fn := src.substr(i_fn, (i_fn_end - i_fn) if i_fn_end > i_fn else 20000)
	ck(i_fn != -1 and i_fn_end > i_fn, "  (the creation function was located, %d chars)" % fn.length())
	var i_top := fn.find("character.current_hp = character.get_total_max_hp()")
	var i_save := fn.find("persistence.save_character(account_id, character)")
	var i_house := fn.find("character.house_bonuses = house_bonuses")
	var i_head := fn.find("var applied_headstarts = character.apply_headstart_ranks")
	ck(i_top != -1 and i_save != -1 and i_house != -1 and i_head != -1,
		"  (all four landmarks are inside it)")
	ck(i_top > i_house, "  after the house bonuses (they scale max hp by a percentage)")
	ck(i_top > i_head, "  after the mastery headstarts")
	ck(i_top < i_save, "  and before the character is saved, so it persists")

	print("")
	print("===== AND THE BLANKET KIT IS GONE - THE WARDEN ARMS YOU =====")
	ck(src.contains("# === NO STARTER KIT. THE WARDEN ARMS YOU. ==="),
		"creation no longer hands out a full set")
	ck(not src.contains('for starter_slot in ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]'),
		"  the seven-slot loop is removed")
	ck(src.contains('drop_tables.get_starter_kit_item("weapon")'),
		"the Warden still hands over the weapon in person")
	var qsrc := FileAccess.get_file_as_string("res://shared/quest_database.gd")
	ck(qsrc.contains('"starter_kit_slot": "armor"') and qsrc.contains('"starter_kit_slot": "accessory"'),
		"and the chain still pays armour then trinket")

	print("")
	print("----- what was deliberately KEPT -----")
	# 2026-09-15: the Home Stone moved from creation to the END of Warden's Watch (owner), arriving
	# with the egg it protects. Pinned to where it lives now rather than dropped.
	var _qsrc2 := FileAccess.get_file_as_string("res://shared/quest_database.gd")
	ck(_qsrc2.contains('"home_stones": ["home_stone_companion"]') and _qsrc2.contains('"egg": "Wolf", "home_stones"'),
		"the Home Stone is still given - now by the Watch, beside the egg it exists to protect")
	ck(src.contains("DropTables.generate_starter_tools()"),
		"and the gathering tools stay - they are not combat power")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether a level 1 can now SURVIVE to the Warden's second step on one weapon. The")
	print("  escort takes any hit that would kill them, so the answer should be yes by")
	print("  construction - but it is a playtest, and -- newplayer is the measurement.")

	print("")
	if fails == 0:
		print("PASS - a new character starts whole, and earns the rest")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
