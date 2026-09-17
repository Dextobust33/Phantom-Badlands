extends SceneTree
## ⛑ CAN A PLAYER DO EVERY PLAYER-TARGETED THING WITHOUT TYPING A COMMAND?
##
## Owner 2026-09-17: *"Anything that remains needs a way to access it via the UI. Example, on the
## player list you right click a player for a menu that has a whisper option, etc."*
##
## That turns the command-retirement question inside out: the list of commands to delete is only
## safe once every capability has a UI route. So this checks the ROUTE, not the menu's looks:
##
##   1. every action in the menu reaches the SAME function the chat command calls — a menu that
##      re-sends the messages itself is two copies of every protocol message, and the day one
##      gains a field only one copy gets it
##   2. the menu actually fires — driven on the real client scene, because a `PopupMenu` whose
##      `id_pressed` is not connected looks identical to one that works
##   3. whisper, which is the one action that needs WORDS, carries the target through to the send
##      path and can be escaped without sending anything
##   4. there are TWO doors, because a right-click survives neither a controller nor a phone and
##      that is the entire reason for the audit
##
## Run:
##   godot --headless --path . --script res://tools/probe/player_actions_menu.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://client/client.tscn")
	if scene == null:
		print("could not load client.tscn"); quit(1); return
	var c = scene.instantiate()
	get_root().add_child(c)
	for _i in range(8):
		await process_frame

	print("===== 1. THE MENU EXISTS AND NAMES ITS SUBJECT =====")
	c.character_data = {"name": "Me"}
	c.open_player_menu("Bob", Vector2(100, 100))
	await process_frame
	var m: PopupMenu = c._player_menu
	ck(m != null and is_instance_valid(m), "a PopupMenu was built")
	if m == null:
		print("  no menu; stopping"); quit(1); return
	# ⛑ A context menu that does not name its subject is how you whisper to the wrong person.
	ck(m.get_item_count() >= 3, "it has items (%d)" % m.get_item_count())
	ck(m.get_item_text(0) == "Bob", "the first row names the player (%s)" % m.get_item_text(0))
	ck(m.is_item_disabled(0), "and that row is a label, not an action")
	var labels: Array = []
	for i in range(m.get_item_count()):
		if not m.is_item_disabled(i) and not m.is_item_separator(i):
			labels.append(m.get_item_text(i))
	print("           actions: %s" % ", ".join(PackedStringArray(labels)))
	for want in ["Whisper", "Inspect", "Trade", "Duel", "Watch", "Add Friend", "Block"]:
		ck(want in labels, "  %s is offered" % want)
	# ...and never on yourself, where none of it means anything.
	c._player_menu_target = ""
	c.open_player_menu("Me", Vector2(100, 100))
	ck(c._player_menu_target == "", "the menu refuses to open on yourself")

	print("\n===== 2. EVERY ACTION REACHES THE SHARED FUNCTION =====")
	# ⛑ Source-read, deliberately: the point is that the menu does NOT carry its own
	# `send_to_server`. Driving each action would prove it does something; this proves it does
	# the same thing the typed route does.
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var i := src.find("func _on_player_menu_id")
	var j := src.find("\nfunc ", i + 10)
	var body := src.substr(i, (j - i) if j > i else 2000)
	ck(not body.contains("send_to_server("),
		"the menu sends no protocol message of its own")
	for fn in ["start_whisper_to(", "player_examine(", "handle_trade_command(", "player_duel(",
			"request_watch_player(", "player_friend_add(", "player_block("]:
		ck(body.contains(fn), "  it calls %s" % fn)
	# ...and the COMMAND arms call the same functions, which is the half that makes it one owner.
	var ci := src.find("func process_command")
	var cj := src.find("\nfunc ", ci + 10)
	var cbody := src.substr(ci, (cj - ci) if cj > ci else 60000)
	for fn in ["player_examine(", "player_block(", "player_unblock(", "player_friend_add(",
			"player_whisper(", "player_duel("]:
		ck(cbody.contains(fn), "  and the chat command calls %s too" % fn)
	# The old inline sends must be GONE from the arms, or there are still two copies.
	for gone in ['send_to_server({"type": "examine_player", "name": target})',
			'send_to_server({"type": "block_user", "username": String(parts[1])})',
			'send_to_server({"type": "private_message", "target": target, "message": msg})']:
		ck(not cbody.contains(gone), "  no inline copy left: %s" % gone.substr(0, 46))

	print("\n===== 3. THE MENU FIRES =====")
	# ⛑ A PopupMenu whose `id_pressed` is not connected looks exactly like one that works, so the
	# signal is emitted for real and the effect is watched.
	c.open_player_menu("Bob", Vector2(100, 100))
	await process_frame
	ck(m.id_pressed.get_connections().size() > 0, "id_pressed is connected")
	c.whisper_target = ""
	m.id_pressed.emit(0)                    # Whisper
	await process_frame
	ck(c.whisper_target == "Bob", "choosing Whisper points the input at Bob (%s)" % c.whisper_target)

	print("\n===== 4. WHISPER NEEDS WORDS, AND CAN BE ESCAPED =====")
	ck(c.input_field != null and "Bob" in c.input_field.placeholder_text,
		"the input says who it is talking to (%s)" % (c.input_field.placeholder_text if c.input_field else "?"))
	# An empty line means "I changed my mind", not "send nothing".
	c.input_field.text = ""
	c.send_input()
	await process_frame
	ck(c.whisper_target == "", "an empty line cancels rather than sending")
	# And one line is ONE whisper - staying in the mode is how the next idle thought goes private.
	c.open_player_menu("Bob", Vector2(100, 100))
	m.id_pressed.emit(0)
	await process_frame
	c.input_field.text = "hello"
	c.send_input()
	await process_frame
	ck(c.whisper_target == "", "and one line is one whisper, not a mode you stay in")
	ck(c.input_field.placeholder_text == "", "  the placeholder is cleared with it")

	print("\n===== 5. TWO DOORS, BECAUSE RIGHT-CLICK IS NOT ONE ON A CONTROLLER =====")
	ck(src.contains("func _on_online_players_gui_input"), "right click on the online list opens it")
	ck(src.contains("MOUSE_BUTTON_RIGHT"), "  on the right button specifically")
	ck(src.contains("_online_hovered_player"),
		"  reading the hovered name, since meta_clicked is left-button only")
	var btn: Node = null
	if c.close_player_info_button != null and is_instance_valid(c.close_player_info_button):
		btn = c.close_player_info_button.get_parent().get_node_or_null("PlayerActionsButton")
	ck(btn != null, "and the player-info popup has an Actions BUTTON")
	if btn != null:
		ck(btn.focus_mode == Control.FOCUS_ALL, "  which is focusable, so a D-pad can reach it")

	print("\n===== NOT COVERED HERE =====")
	print("  Whether the menu lands somewhere sensible on screen, and whether the server")
	print("  accepts each action for a real second player. Both want two connected clients.")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
