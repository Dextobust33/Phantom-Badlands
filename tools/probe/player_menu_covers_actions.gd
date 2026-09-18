extends SceneTree
## ⛑ EVERY PLAYER-TO-PLAYER ACTION THE SERVER ACCEPTS IS REACHABLE FROM THE MENU.
##
## This has now been wrong twice, the same way both times, and neither was found by a sweep:
##
##   * **Duel for Valor.** `player_duel` takes "none" or "valor_10"; the menu only ever passed
##     "none", so half the feature had no UI route. A sweep reading *"Duel is in the menu"* called
##     it covered.
##   * **Invite to Party.** `handle_party_invite` resolves its target BY NAME and never checks
##     distance - but the only thing that ever sent the message was the walk-into-someone bump
##     prompt. So forming a party with a player you could see in the list meant going to find them.
##
## Both are the same shape: the capability EXISTS server-side and the player cannot reach it. The
## count of menu rows says nothing, so this checks the two things that do - that each action id
## dispatches somewhere, and that the named server verbs have a row that reaches them.
##
## Run:
##   godot --headless --path . --script res://tools/probe/player_menu_covers_actions.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")

	# The menu table and its dispatch, read out of the source rather than assumed.
	var tbl_at := src.find("PLAYER_MENU_ITEMS")
	var tbl_end := src.find("]", src.find("[", tbl_at))
	var tbl := src.substr(tbl_at, tbl_end - tbl_at)
	var disp_at := src.find("func _on_player_menu_id(id: int) -> void:")
	var disp := src.substr(disp_at, src.find("\nfunc ", disp_at + 10) - disp_at)

	print("===== EVERY ROW DISPATCHES =====")
	var ids: Array = []
	var i := 0
	while true:
		var at := tbl.find('{"id": ', i)
		if at < 0:
			break
		var num := tbl.substr(at + 7, 3).strip_edges().split(",")[0].split("}")[0]
		ids.append(int(num))
		i = at + 7
	ck(ids.size() >= 8, "found %d menu rows" % ids.size())
	for id in ids:
		ck(disp.find("\t\t%d: " % int(id)) >= 0,
			"  row id %d has a dispatch arm (a row with none is a dead menu entry)" % int(id))

	print("\n===== THE CAPABILITIES THAT WERE MISSED =====")
	ck(tbl.find('"Invite to Party"') >= 0, "Invite to Party is offered")
	ck(src.find('send_to_server({"type": "party_invite", "target": target})') >= 0,
		"...and it sends the message the server handler listens for")
	ck(srv.find('"party_invite":') >= 0, "...which the server still routes")
	ck(tbl.find('"Duel for Valor"') >= 0, "Duel for Valor is offered (the first bug of this shape)")
	ck(src.find('player_duel(target, "valor_10")') >= 0, "...and passes the wager the server accepts")

	print("\n===== AND THE BUMP PROMPT IS NOT THE ONLY ROUTE =====")
	# The point of the fix: two independent ways in, so losing one does not remove the feature.
	var bump := src.count('send_to_server({"type": "party_invite"')
	ck(bump >= 2,
		"party_invite is sent from %d places - the bump prompt AND the player menu" % bump)

	print("")
	if fails == 0:
		print("[PROBE] PASS the player menu reaches what the server accepts")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
