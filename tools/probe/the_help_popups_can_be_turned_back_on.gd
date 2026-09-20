extends SceneTree
## ⛑ CAN A PLAYER WHO TURNED THE HELP POP-UPS OFF EVER TURN THEM BACK ON?
##
## Owner 2026-09-19: *"the original tutorial should be skippable and players should also be able to
## disable the help popups for their account if they want."*
##
## Both halves were BUILT, which is why this needed checking rather than building:
##   * the walkthrough has a Skip button (`_skip_tutorial`)
##   * the pop-ups have an account-level opt-out (`set_tutorials` -> `set_tutorials_enabled`)
##
## ⚡ BUT THE DOOR ONLY OPENED ONE WAY. The opt-out lives on the pop-up itself, the setting lives
## on the ACCOUNT, the server never reported its value, and Settings had no row for it — while the
## line the pop-up printed on its way out said *"Turn them back on in Settings."* A player who
## opted out could not undo it from anywhere in the game.
##
## ⛑ TWO SETTINGS THAT SOUND ALIKE, and conflating them is what hid this:
##   `disable_tutorial`   CLIENT preference, per install — is a NEW CHARACTER offered the
##                        walkthrough? This is Settings [5] and always worked.
##   `tutorials_enabled`  ACCOUNT setting, server-side — do the first-touch teaching pop-ups
##                        appear at all? This is the one with no way back.
##
## Run:
##   godot --headless --path . --script res://tools/probe/the_help_popups_can_be_turned_back_on.gd

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")

	print("")
	print("===== 1. THE WALKTHROUGH IS STILL SKIPPABLE =====")
	if cli.find("func _skip_tutorial(") < 0:
		_fail("the tutorial can no longer be skipped")
	else:
		_ok("the walkthrough has a skip")
	# The button, not just the function - a skip nothing offers is not a skip.
	if cli.find("\"action_data\": \"tutorial_skip\"") < 0:
		_fail("nothing offers the skip - the function exists but no button reaches it")
	else:
		_ok("the prompt offers it as a button")

	print("")
	print("===== 2. THE POP-UPS CAN BE TURNED OFF =====")
	if srv.find("func handle_set_tutorials(") < 0:
		_fail("the server no longer accepts the opt-out")
	else:
		_ok("the server accepts the opt-out")
	if srv.find("persistence.set_tutorials_enabled(") < 0:
		_fail("the opt-out is not persisted, so it lasts until logout")
	else:
		_ok("it is persisted on the account")

	print("")
	print("===== 3. ...AND BACK ON, WHICH IS THE HALF THAT WAS MISSING =====")
	# ⚑ THREE THINGS HAVE TO EXIST TOGETHER. Any one alone looks like a feature and works like
	# nothing: a row that cannot read the value shows a guess, a value nobody reports cannot be
	# shown, and a toggle with no row cannot be reached.
	if srv.find("\"type\": \"tutorials_state\"") < 0:
		_fail("the server never reports the setting, so Settings cannot show its real state")
	else:
		_ok("the server reports the current state")
	if cli.find("\"tutorials_state\":") < 0:
		_fail("the client ignores the report - the server sends it and nothing reads it, which "
			+ "looks exactly like never sending it")
	else:
		_ok("the client reads the report")
	if cli.find("Help Pop-ups (this account)") < 0:
		_fail("there is no Settings row for the account pop-ups, so the opt-out message's "
			+ "promise - \"Turn them back on in Settings\" - is still a lie")
	else:
		_ok("Settings has a row for it")
	if cli.find("func _toggle_account_tutorials(") < 0:
		_fail("the row cannot be flipped")
	else:
		_ok("the row flips it")

	print("")
	print("===== 4. IT DID NOT RENUMBER THE OTHER SETTINGS =====")
	# Every row is addressed by its number. Inserting above an existing one moves the keys under
	# the player's fingers, which is a silent regression for anyone with muscle memory.
	var rows := {
		"[5] Tutorial on New Character": "the per-install walkthrough toggle",
		"[8] Stat Compare Priority": "the stat priority submenu",
	}
	for r in rows.keys():
		if cli.find(r) < 0:
			_fail("%s (%s) has moved or gone - the new row must be added at the END" % [r, rows[r]])
		else:
			_ok("%s is still where it was" % r)
	# And the two must stay distinct: merging them would silently turn a player's pop-ups off
	# when all they wanted was to skip the walkthrough on a new character.
	if cli.find("func _toggle_disable_tutorial(") < 0:
		_fail("the per-install tutorial toggle is gone - it is a DIFFERENT setting from the "
			+ "account pop-ups and both should exist")
	else:
		_ok("the two settings are still separate")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS the walkthrough can be skipped, and the account's help pop-ups can be")
	print("       turned off AND back on from Settings.")
	quit()
