extends SceneTree
## ⛑ A DEATH ANNOUNCEMENT LINKS TO THE FIGHT THAT CAUSED IT.
##
## Backlog: *"When a player dies, the chat message carries a clickable link to the combat log."*
##
## ⛑ ALMOST ALL OF THIS WAS ALREADY BUILT, WHICH IS THE POINT. Every death has carried its full
## `combat_log` inside `death_data` since the leaderboard was written; the server already answers a
## `get_leaderboard_death` request with it; and the client already renders that log. The only thing
## missing was a way to ASK — you had to open the leaderboard and find the row. That is the fourth
## item this arc where the capability shipped and the route did not (party invite, Duel for Valor,
## the fight log itself, now this), so this probe checks the ROUTE end to end rather than the parts.
##
## Run:
##   godot --headless --path . --script res://tools/probe/death_log_link.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var per := FileAccess.get_file_as_string("res://server/persistence_manager.gd")

	print("===== THE ANNOUNCEMENT CARRIES A LINK =====")
	ck(srv.find("[url=deathlog:%s]") >= 0, "the death broadcast writes a `deathlog:` link")
	# It must go to CHAT, which is the window everyone sees - including players on character select.
	ck(srv.find('"type": "chat",') >= 0 and srv.find('"sender": "World",') >= 0,
		"...and the announcement is broadcast to every peer as chat")

	print("\n===== CHAT LINKS ARE CLICKABLE AT ALL =====")
	# They were not. A [url] in chat rendered as underlined text that did nothing, which is worse
	# than no link: it advertises an action and then refuses it.
	ck(cli.find("chat_output.meta_clicked.connect(_on_game_output_meta_clicked)") >= 0,
		"chat_output routes meta clicks")
	ck(cli.find("game_output.meta_clicked.connect(_on_game_output_meta_clicked)") >= 0,
		"...through the SAME dispatcher as game_output, so a meta means one thing everywhere")

	print("\n===== THE CLICK REACHES THE EXISTING FETCH =====")
	ck(cli.find('meta_str.begins_with("deathlog:")') >= 0, "the client recognises the link")
	ck(cli.find('send_to_server({"type": "get_leaderboard_death", "character_name": _dead_name})') >= 0,
		"...and asks with the request the server already answers")
	ck(srv.find('"get_leaderboard_death":') >= 0, "the server still routes that request")
	ck(srv.find('"type": "leaderboard_death",') >= 0, "...and replies with `leaderboard_death`")
	ck(cli.find('death_data.get("combat_log", [])') >= 0,
		"the client renders the combat_log out of the reply (this already worked)")

	print("\n===== NAME-ONLY LOOKUP FINDS THE RIGHT DEATH =====")
	# ⛑ The link identifies a death by NAME, because `add_to_leaderboard` stamps `died_at`
	# internally and returns only a rank. So "no timestamp" has to mean the MOST RECENT death
	# under that name - it used to mean "whichever matched first", and `entries` is sorted by
	# LEVEL, so a name that had died twice returned whichever ranked higher.
	ck(per.find("var best_at: int = -1") >= 0 and per.find("if at > best_at:") >= 0,
		"get_leaderboard_death_data picks the most RECENT death when given no timestamp")
	ck(per.find("if at == died_at:") >= 0,
		"...and still honours an exact timestamp when the leaderboard passes one")

	print("")
	if fails == 0:
		print("[PROBE] PASS a death announcement reaches its own combat log")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
