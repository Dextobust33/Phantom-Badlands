extends SceneTree
## Local-only convenience: make an ADMIN account with a ready character, so a UI look-over starts
## in the situation being judged instead of at a character creation screen.
##
## Not a test. Run it against the LOCAL user:// data, then launch the local server + client.
##   login:  look / looklook
const ServerScript = preload("res://server/server.gd")
const PEER := 1

func _init() -> void:
	var sv = ServerScript.new()
	get_root().add_child(sv)
	await process_frame
	await process_frame
	sv.set_process(false)
	sv.set_physics_process(false)

	var made: Dictionary = sv.persistence.create_account("look", "looklook")
	var acct := String(made.get("account_id", ""))
	if acct == "":
		# Already there from a previous run - reuse it.
		var res: Dictionary = sv.persistence.authenticate("look", "looklook")
		acct = String(res.get("account_id", ""))
		if acct == "":
			print("could not create or log into the 'look' account"); quit(1); return
		print("reusing existing account")
	sv.persistence.set_admin_status("look", true)
	print("admin: %s" % str(sv.persistence.is_admin_username("look")))

	sv.peers[PEER] = {"authenticated": true, "account_id": acct, "character_name": "",
		"connection": StreamPeerTCP.new(), "is_admin": true}
	var chars: Array = sv.persistence.get_account_characters(acct)
	if chars.is_empty():
		sv.handle_create_character(PEER, {"name": "Looker", "class": "Fighter", "race": "Human"})
		await process_frame
		var ch = sv.characters.get(PEER, null)
		if ch == null:
			print("character creation failed"); quit(1); return
		# Enough level that the HUD has real numbers in it, and tools so the Tools panel is
		# populated the way a played character's is - an empty panel is not the thing being judged.
		# ⚑ LEVEL AND GEAR, BOTH. 2026-09-16: the first version made a level-30 character and put
		# six items in its BACKPACK. Every dungeon capture then died in the entrance ambush -
		# "Damage Dealt: 0, Damage Taken: 130" - because a naked level 30 is not a level 30, and
		# the scripted runs only survived because the shots harness turns godmode on. A character
		# built to be LOOKED at has to survive being looked at.
		ch.level = 60
		# ⚑ REAL BASE TYPES, NOT A "slot" KEY THE GENERATOR DOES NOT READ. The first version
		# passed {"slot": "weapon"}; `_generate_item` ignores that, so it produced typeless
		# items that came out named "Healthy Pristine Unknown of the Sphinx" and could only be
		# worn because this probe forced them into slots - the game could not work out where
		# they went, so taking one off was a one-way trip. Owner found it by unequipping one.
		var slot_bases := {
			"weapon": "weapon_mythic", "armor": "armor_mythic", "helm": "helm_mythic",
			"shield": "shield_mythic", "boots": "boots_mythic", "ring": "ring_mythic",
			"amulet": "amulet_mythic",
		}
		for slot in slot_bases.keys():
			var gear: Dictionary = sv.drop_tables._generate_item(
				{"item_type": String(slot_bases[slot]), "rarity": "epic"}, 60)
			if gear.is_empty():
				continue
			ch.equip_item(gear, slot)
			print("  equipped %s: %s" % [slot, String(gear.get("name", "?"))])
		ch.current_hp = ch.get_total_max_hp()
		for t in ["pickaxe", "axe", "sickle", "fishing_rod"]:
			var tool_item: Dictionary = sv.drop_tables._generate_item({"item_type": t, "rarity": "uncommon"}, 30)
			if not tool_item.is_empty():
				ch.add_item(tool_item)
		for i in range(6):
			var loot: Dictionary = sv.drop_tables._generate_item({}, 30)
			if not loot.is_empty():
				ch.add_item(loot)
		sv.save_character(PEER)
		print("created character 'Looker' (Fighter, level %d, %d items)" % [ch.level, ch.inventory.size()])
	else:
		print("character already exists: %s" % str(chars))

	# A COMPANION, OUT AND WALKING. Owner 2026-09-16, looking at the overworld: *"I have no
	# companion so I can't judge that correctly."* The companion has its own art panel in the
	# map's margin and its own sprite trailing you, so a screen built to be judged has to have one.
	# The character is only loaded into `sv.characters` when this run CREATED it. On a re-run
	# it has to be selected first, or every line below silently does nothing - which is what
	# happened the first time (no companion, no message, exit 0).
	if not sv.characters.has(PEER) and not chars.is_empty():
		sv.handle_select_character(PEER, {"name": String(chars[0].get("name", "Looker"))})
		await process_frame
	# Strip anything the broken first version left worn: an item with no `item_type` cannot be
	# re-equipped once removed, so it is not gear, it is a trap.
	var chr_fix = sv.characters.get(PEER, null)
	if chr_fix != null:
		var bases := {"weapon": "weapon_mythic", "armor": "armor_mythic", "helm": "helm_mythic",
			"shield": "shield_mythic", "boots": "boots_mythic", "ring": "ring_mythic",
			"amulet": "amulet_mythic"}
		for slot in bases.keys():
			var worn = chr_fix.equipped.get(slot, null)
			if worn == null or not (worn is Dictionary) or String(worn.get("item_type", "")) == "":
				var fresh: Dictionary = sv.drop_tables._generate_item(
					{"item_type": String(bases[slot]), "rarity": "epic"}, 60)
				if not fresh.is_empty():
					chr_fix.equip_item(fresh, slot)
					print("  replaced typeless %s with %s" % [slot, String(fresh.get("name", "?"))])
		sv.save_character(PEER)
	var chr2 = sv.characters.get(PEER, null)
	if chr2 != null:
		if chr2.collected_companions.is_empty():
			sv.handle_gm_givecompanion(PEER, {"monster_type": "Wolf"})
			await process_frame
		if chr2.active_companion == null or chr2.active_companion.is_empty():
			if not chr2.collected_companions.is_empty():
				var comp: Dictionary = chr2.collected_companions[0]
				chr2.active_companion = comp.duplicate(true)
				chr2.active_companion["current_hp"] = 9999
				sv.save_character(PEER)
		print("companion: %s" % str(chr2.active_companion.get("name", "(none)")))
	print("READY - log in as  look / looklook")
	quit(0)
