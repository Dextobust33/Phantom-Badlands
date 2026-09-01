# Recreate a test character that permadeath deleted, using the REAL Character + persistence
# code so it is indistinguishable from one made in-game (deck, stats, starting kit all correct).
#   godot --headless --path . --script tools/test_setup/make_char.gd -- --acc=acc_5 --name=test002 --class=Sorcerer --race=Dwarf --level=9
extends SceneTree

func _init():
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		for k in ["acc", "name", "class", "race", "level", "stat"]:
			if s.begins_with("--%s=" % k):
				args[k] = s.substr(k.length() + 3)
	if not args.has("acc") or not args.has("name"):
		print("need --acc= and --name=")
		quit(1); return

	var persistence = load("res://server/persistence_manager.gd").new()
	root.add_child(persistence)
	if persistence.has_method("load_accounts"):
		persistence.load_accounts()

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

	persistence.save_character(String(args["acc"]), ch)
	persistence.add_character_to_account(String(args["acc"]), ch.name)
	print("created %s (L%d %s %s) on %s" % [ch.name, ch.level, args.get("race", "Human"), args.get("class", "Fighter"), args["acc"]])
	quit()
