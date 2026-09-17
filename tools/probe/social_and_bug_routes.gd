extends SceneTree
## ⛑ THE TWO THINGS THAT BLOCKED THE COMMAND SWEEP.
##
## Owner 2026-09-17: *"Anything that remains needs a way to access it via the UI."* Working through
## the retirement list, two capabilities turned out to have no UI route at all:
##
##   1. **Reporting a bug.** `_on_bug_button_pressed()` existed, complete and correct, connected to
##      NOTHING — a handler for a button nobody built. So `/bug` was the only way, which is the
##      worst thing in the game to be command-only: a player who has just hit a bug is exactly the
##      person who does not know the command.
##   2. **The whole friend system.** No `*_panel.gd` for it. `/friend accept <name>` was the ONLY
##      way to answer a request, and `/freq` the only way to learn one existed — so a request you
##      could not see was a request you could not accept.
##
## Both are driven on the real client scene here, because both failed in the same invisible way:
## a handler with nothing calling it, and a panel with nothing opening it, look exactly like
## working features from the source.
##
## Run:
##   godot --headless --path . --script res://tools/probe/social_and_bug_routes.gd

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

	print("===== 1. REPORTING A BUG IS A BUTTON =====")
	var row: Node = c.send_button.get_parent() if c.send_button != null else null
	var bug: Node = row.get_node_or_null("BugButton") if row != null else null
	ck(bug != null, "there is a Report button beside Send")
	if bug != null:
		ck(bug.focus_mode == Control.FOCUS_ALL, "  focusable, so a D-pad reaches it")
		# ⛑ The fault was a handler NOTHING called, so the connection is what matters.
		ck(bug.pressed.get_connections().size() > 0, "  and it is connected to something")
		c.connected = true
		c.bug_report_mode = false
		bug.pressed.emit()
		await process_frame
		ck(c.bug_report_mode, "pressing it starts a bug report")
		ck("bug" in String(c.input_field.placeholder_text).to_lower(),
			"  and the input says what it wants (%s)" % c.input_field.placeholder_text)
		c.bug_report_mode = false
		c.input_field.placeholder_text = ""

	print("\n===== 2. THE FRIEND SYSTEM HAS A SURFACE =====")
	var sp = c.social_panel
	ck(sp != null, "the People panel exists")
	if sp == null:
		print("  no panel; stopping"); quit(1); return
	ck(c.social_panel.action_requested.get_connections().size() > 0,
		"and the client is listening to it")
	# It must be REACHABLE - a panel nothing opens is the shape this audit keeps finding.
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	ck(src.contains('["People", "social_shortcut"]'), "a People button is in the shortcut row")
	ck(src.contains('"social_shortcut":'), "  with a handler")
	ck(src.contains("social_panel.open()"), "  that opens it")

	print("\n===== 3. A REQUEST YOU CAN SEE IS A REQUEST YOU CAN ANSWER =====")
	# ⛑ THE CAPABILITY THAT HAD NO UI AT ALL. `/friend accept <name>` was the only way.
	sp.set_requests([{"username": "Ann"}], [{"username": "Bo"}])
	sp.set_friends([{"username": "Cy", "online": true, "character_name": "Cyrus",
		"level": 12, "class": "Ranger"}])
	sp.set_blocked([{"username": "Dex"}])
	sp.visible = true
	sp._tab = 1
	sp._rebuild()
	await process_frame
	var labels: Array = []
	for r in sp._list_box.get_children():
		for ch in r.get_children():
			if ch is Button:
				labels.append((ch as Button).text)
	print("           request row buttons: %s" % ", ".join(PackedStringArray(labels)))
	for want in ["Accept", "Decline", "Cancel"]:
		ck(want in labels, "  %s is offered" % want)
	# ...and pressing Accept asks for the right thing, by name.
	# \u26d1 MUTATE, DO NOT REASSIGN. A GDScript lambda captures by VALUE, so `got = {...}` inside
	# it rebinds the lambda's own copy and the outer variable never changes - the signal fired
	# correctly and the first version of this check could not see it. The Dictionary's CONTENTS
	# are shared, because the capture copies the handle.
	var got := {"action": "", "user": ""}
	sp.action_requested.connect(func(a, u):
		got["action"] = a
		got["user"] = u)
	for r in sp._list_box.get_children():
		for ch in r.get_children():
			if ch is Button and (ch as Button).text == "Accept":
				(ch as Button).pressed.emit()
	await process_frame
	ck(got["action"] == "friend_accept" and got["user"] == "Ann",
		"Accept asks to accept Ann (%s / %s)" % [got["action"], got["user"]])

	print("\n===== 4. THE PANEL SENDS NOTHING OF ITS OWN =====")
	# Same rule as the player context menu: every action forwards to the function the chat
	# command calls, so the typed route and the clicked route cannot drift apart.
	var psrc := FileAccess.get_file_as_string("res://client/social_panel.gd")
	ck(not psrc.contains("send_to_server"), "the panel has no protocol message in it")
	var i := src.find("func _on_social_action")
	var j := src.find("\nfunc ", i + 10)
	var body := src.substr(i, (j - i) if j > i else 3000)
	ck(body.contains("player_friend_answer("), "the dispatcher forwards the four answers")
	ck(body.contains("player_unblock("), "  and unblock")
	ck(body.contains("start_whisper_to("), "  and whisper")
	# ...and the CHAT arms call the same function, which is the half that makes it one owner.
	var ci := src.find("func process_command")
	var cj := src.find("\nfunc ", ci + 10)
	var cbody := src.substr(ci, (cj - ci) if cj > ci else 60000)
	ck(cbody.contains('player_friend_answer("accept"'), "and /friend accept calls it too")
	for gone in ['send_to_server({"type": "friend_accept", "username": String(parts[2])})',
			'send_to_server({"type": "friend_reject", "username": String(parts[2])})']:
		ck(not cbody.contains(gone), "  no inline copy left: %s" % gone.substr(0, 44))

	print("\n===== 5. THE COUNT IS VISIBLE WITHOUT OPENING THE TAB =====")
	# An unanswered request is the one thing here that is time-sensitive.
	ck(sp.pending_request_count() == 1, "the panel knows how many are waiting (%d)" % sp.pending_request_count())
	var tab_texts: Array = []
	for t in sp._tab_row.get_children():
		tab_texts.append((t as Button).text)
	print("           tabs: %s" % ", ".join(PackedStringArray(tab_texts)))
	ck("Requests (1)" in tab_texts, "and the tab says so")

	print("\n===== NOT COVERED HERE =====")
	print("  Whether the server accepts each action for a real second account, and whether the")
	print("  panel reads well at 1080p. Both want a live run with two clients.")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
