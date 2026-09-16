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
		ch.level = 30
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
	print("READY - log in as  look / looklook")
	quit(0)
