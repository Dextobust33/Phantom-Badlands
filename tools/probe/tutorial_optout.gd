extends SceneTree
## Can a player turn the teaching pop-ups off, and does the switch actually reach all of them?
##
## Owner 2026-09-14, after making a fresh account: *"When the player logs into their Sanctuary they
## should get the movement tutorial popup (with an option to turn it off for the future of their
## account)."*
##
## The failure this guards is a switch that only turns off the hints somebody remembered to wire
## to it. Every teaching pop-up now goes through ONE function, so the check is that no other send
## site exists - not that the fourteen known ones behave.
const ServerScript = preload("res://server/server.gd")
const PM = preload("res://server/persistence_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var pm = PM.new()
	get_root().add_child(pm)
	await process_frame
	pm.houses_data = {"houses": {"acct1": {}}}

	print("===== THE DEFAULT IS ON =====")
	ck(pm.tutorials_enabled("acct1"), "a new account wants the lessons")
	ck(pm.tutorials_enabled("never_seen"), "and so does an account with no house yet")

	print("")
	print("===== THE SWITCH STICKS, AND IT IS ACCOUNT LEVEL =====")
	pm.set_tutorials_enabled("acct1", false)
	ck(not pm.tutorials_enabled("acct1"), "turned off")
	ck(bool(pm.houses_data["houses"]["acct1"].get("tutorials_enabled")) == false,
		"stored on the HOUSE, which is per account - so it survives permadeath and every new "
		+ "character rolled afterwards")
	pm.set_tutorials_enabled("acct1", true)
	ck(pm.tutorials_enabled("acct1"), "and back on again")

	print("")
	print("===== A ONE-SHOT FIRES ONCE =====")
	ck(pm.mark_account_flag("acct1", "seen_sanctuary_intro"), "the intro fires the first time")
	ck(not pm.mark_account_flag("acct1", "seen_sanctuary_intro"), "and never again")
	ck(pm.mark_account_flag("acct1", "some_other_flag"),
		"a different flag is independent - one function, any number of one-shots")

	print("")
	print("===== EVERY TEACHING POP-UP GOES THROUGH THE GATE =====")
	# This is the check that matters. A switch is only worth having if nothing can route around
	# it, and the way that breaks is the NEXT hint somebody adds, not the ones here today.
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var sends := src.count('"type": "tutorial_hint"')
	print("  %d place(s) in server.gd construct a tutorial_hint message" % sends)
	ck(sends <= 3, "almost all of them route through _send_hint (%d direct)" % sends)
	ck(src.contains("func _send_hint(peer_id: int"), "the gate exists")
	ck(src.contains("not persistence.tutorials_enabled(account_id)"),
		"and it actually checks the account setting")

	print("")
	print("----- the exceptions, and why they are exceptions -----")
	print("  The WELCOME overlay and the POST RECLAIMED warning still send directly.")
	print("  Post-reclaimed is not a lesson - it tells a player their post is gone, and someone")
	print("  who switched tutorials off must still be told that. Suppressing it would be a bug.")

	print("")
	print("===== THE OPT-OUT IS OFFERED, BUT NOT EVERYWHERE =====")
	# Putting it on every hint turns every lesson into a chance to switch the lessons off by
	# accident. It belongs on the first one an account ever sees.
	ck(src.contains('"Don\'t show me tips'), "the Sanctuary intro offers the opt-out")
	var panel := FileAccess.get_file_as_string("res://client/tutorial_hint_panel.gd")
	ck(panel.contains("_opt_out_button.visible = opt_out_text != \"\""),
		"and the button is hidden on every hint that does not ask for it")

	print("")
	print("===== AND IT TEACHES THE RIGHT CONTROL =====")
	# Owner: "Movement is done with the Numpad and alternatively the arrow keys." Naming arrows
	# first would teach a new player the lesser control - the numpad is the one with diagonals.
	var i_num := src.find("Move with the NUMPAD")
	var i_arr := src.find("Arrow keys work too")
	ck(i_num != -1, "the intro names the numpad")
	ck(i_arr != -1 and i_arr > i_num, "and names arrow keys SECOND, as the alternative")

	print("")
	if fails == 0:
		print("PASS - the lessons can be switched off, once, for the whole account")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
