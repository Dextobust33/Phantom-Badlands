# Create (or recreate) a test account + character using the REAL persistence + Character code,
# so the result is indistinguishable from one made in-game. Permadeath deletes its own fixture,
# so scenarios call this automatically when a test character is missing.
#
#   godot --headless --path . --script tools/test_setup/make_char.gd -- \
#       --acc=acc_5 --user=Testing2 --pass=devtest --name=test002 \
#       --class=Sorcerer --race=Dwarf --level=9 --stat=intelligence
#
# --user/--pass are optional: given, the ACCOUNT is created too if it does not exist yet.
extends SceneTree

func _init():
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		for k in ["acc", "name", "class", "race", "level", "stat", "user", "pass"]:
			if s.begins_with("--%s=" % k):
				args[k] = s.substr(k.length() + 3)
	if not args.has("name"):
		print("need --name=")
		quit(1); return

	var persistence = load("res://server/persistence_manager.gd").new()
	root.add_child(persistence)
	if persistence.has_method("load_accounts"):
		persistence.load_accounts()

	# Create the account when asked and it does not exist. create_account does the salt +
	# hash + id allocation properly; hand-writing accounts.json risks a subtly wrong shape.
	var acc_id := String(args.get("acc", ""))
	if args.has("user") and args.has("pass"):
		var uname := String(args["user"])
		var existing := ""
		for aid in persistence.accounts_data.get("accounts", {}):
			if String(persistence.accounts_data["accounts"][aid].get("username", "")) == uname:
				existing = aid
				break
		if existing == "":
			var res: Dictionary = persistence.create_account(uname, String(args["pass"]))
			if not res.get("success", false):
				print("account create failed: %s" % str(res.get("reason", "?")))
				quit(1); return
			for aid in persistence.accounts_data.get("accounts", {}):
				if String(persistence.accounts_data["accounts"][aid].get("username", "")) == uname:
					existing = aid
					break
			print("created account %s (%s)" % [uname, existing])
		acc_id = existing

	if acc_id == "":
		print("need --acc= (or --user/--pass so the account can be resolved)")
		quit(1); return

	var CharacterScript = load("res://shared/character.gd")
	var ch = CharacterScript.new()
	ch.initialize(String(args["name"]), String(args.get("class", "Fighter")), String(args.get("race", "Human")))
	var want_level := int(args.get("level", "1"))
	for i in range(max(0, want_level - 1)):
		ch.level_up()
	var stat := String(args.get("stat", "strength"))
	while ch.unspent_stat_points > 0:
		ch.spend_stat_point(stat)
	if ch.has_method("initialize_deck_collection_if_needed"):
		ch.initialize_deck_collection_if_needed()

	persistence.save_character(acc_id, ch)
	persistence.add_character_to_account(acc_id, ch.name)
	print("created %s (L%d %s %s) on %s" % [ch.name, ch.level, args.get("race", "Human"), args.get("class", "Fighter"), acc_id])
	quit()
