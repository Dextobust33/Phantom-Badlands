extends SceneTree
## A party action is confirmed before it is locked in - and ONLY a party action.
##
## 2026-09-11. `_party_submit_action` on the server is a one-way door: once
## `submitted_this_round` is set, a second action is refused, so a misclick meant waiting out
## the round. The owner asked for a confirmation step; it goes in for party only, because solo
## shows the result at once and the card face already carries the reveal.
##
## client.gd cannot be instantiated headless, so this reads the SHAPE of the wiring - the gate
## sits inside the party block of send_combat_command, the bar has a branch that wins over the
## normal party hand, both buttons resolve, and every reset site clears the pending state.
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _body(src: String, header: String) -> String:
	var a := src.find(header)
	if a < 0:
		return ""
	var b := src.find("\nfunc ", a + header.length())
	return src.substr(a, (b if b > 0 else src.length()) - a)


func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("--- the gate ---")
	var send := _body(cli, "func send_combat_command(")
	var g := send.find("_party_confirm_start(command, target)")
	ck(g >= 0, "send_combat_command holds a party action for confirmation")
	var in_party_block := send.find("if _in_party:\n")
	var first_send := send.find("send_to_server(_payload)")
	ck(in_party_block >= 0 and g > in_party_block and g < first_send,
		"...inside the party block and BEFORE the payload is sent")
	ck(send.find("if not party_combat_spectating and not _party_confirm_armed:") >= 0,
		"...gated on the one-shot arm, so only Confirm can pass it")
	var picker := send.find("_start_buff_target_select(command)")
	ck(picker >= 0 and picker < g, "the buff target picker runs first, so the confirm can name the target")
	# Solo must be untouched: the gate lives under `if _in_party:` and nowhere else.
	ck(send.count("_party_confirm_start(") == 1, "exactly one gate - solo has no confirm step")

	print("\n--- the bar ---")
	var bar := _body(cli, "func update_action_bar(")
	var conf_branch := bar.find("elif party_confirm_pending:")
	var active_branch := bar.find("elif party_combat_active:")
	ck(conf_branch >= 0, "the action bar has a confirm branch")
	ck(conf_branch >= 0 and conf_branch < active_branch,
		"...which wins over the party hand (party_combat_active stays true while confirming)")
	ck(bar.find('"action_data": "party_confirm_yes"') >= 0 and bar.find('"action_data": "party_confirm_no"') >= 0,
		"Confirm on Space and Pick again on Q")
	ck(bar.find("if _ci == party_confirm_slot:") >= 0, "the card's own key confirms too (press it twice)")

	print("\n--- both buttons resolve (pitfall #11: click path) ---")
	var ela := _body(cli, "func execute_local_action(")
	ck(ela.find('"party_confirm_yes":\n\t\t\t_party_confirm_yes()') >= 0, "party_confirm_yes handled")
	ck(ela.find('"party_confirm_no":\n\t\t\t_party_confirm_no()') >= 0, "party_confirm_no handled")
	var yes := _body(cli, "func _party_confirm_yes(")
	ck(yes.find("_party_confirm_armed = true") >= 0 and yes.find("send_combat_command(cmd, tgt)") >= 0
		and yes.find("_party_confirm_armed = false") >= 0, "Confirm arms, sends, disarms - one call only")

	print("\n--- every reset clears it ---")
	ck(_body(cli, "func _handle_party_combat_start(").find("_party_confirm_clear()") >= 0
		or cli.find("party_round_submitted = false  # #76 — fresh fight, nothing locked in yet\n\t_party_confirm_clear()") >= 0,
		"a new fight starts clean")
	ck(cli.find("party_round_submitted = false\n\t\t_party_confirm_clear()") >= 0, "falling in a fight clears it")
	ck(cli.find("party_round_submitted = false\n\t_party_confirm_clear()\n\tstop_low_hp_pulse()") >= 0, "the fight ending clears it")

	print("\n--- the origin slot is captured before the picker, on both input paths ---")
	ck(cli.find("_target_select_origin_slot = (index - 4) if index >= 5 and index <= 9 else 0\n\t\t\t_party_confirm_origin_index = index") >= 0,
		"hotkey path records the bar index")
	ck(_body(cli, "func _on_combat_card_played(").find("_party_confirm_origin_index = -1") >= 0,
		"mouse path records none")

	print("\n--- the help page says so ---")
	ck(cli.find("lock it in") >= 0 or cli.find("Lock in") >= 0, "help text mentions the confirm step")

	print("\n[PARTYCONFIRM] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
