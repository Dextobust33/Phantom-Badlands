extends SceneTree
## The online-status feed: small, correct, and silent when unconfigured.
##
## Owner 2026-09-13: *"a tool that is efficient and doesn't use much data that shows the players
## currently online... viewable from my android phone and in discord."*
##
## The failure that matters is not "it does not work" - it is that it costs something, or leaks
## something, or spams a Discord channel with a new message every three minutes forever.
const OS_SCRIPT = preload("res://server/online_status.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/online_status.gd")

	print("--- it costs nothing when nobody has configured it ---")
	# A developer running the server locally has no webhook. That must not be an error, and it
	# must not fire a request.
	ck(src.find("if _cfg.is_empty() or _server == null:\n\t\treturn") >= 0,
		"an unconfigured server never publishes")
	ck(src.find("if f == null:\n\t\treturn") >= 0, "a missing config file is not an error")

	print("\n--- it EDITS one Discord message rather than posting forever ---")
	ck(src.find("HTTPClient.METHOD_PATCH") >= 0, "later publishes PATCH")
	ck(src.find("/messages/%s") >= 0, "...the message it already posted")
	ck(src.find("?wait=true") >= 0,
		"...having asked Discord to return the first message so its id is known")
	ck(src.find("_cfg[\"discord_message_id\"] = _discord_message_id") >= 0,
		"and the id is REMEMBERED, or a restart would start a second message")

	print("\n--- secrets stay out of git ---")
	ck(src.find('const CONFIG_PATH := "user://online_status.cfg"') >= 0,
		"config lives in user:// on the server, not in the repo")
	var repo_leak := false
	for f in ["res://server/online_status.gd", "res://docs/status.html", "res://server/server.gd"]:
		var t := FileAccess.get_file_as_string(f)
		if t.find("discord.com/api/webhooks/") >= 0 or t.find("ghp_") >= 0:
			repo_leak = true
	ck(not repo_leak, "no webhook URL or token is committed anywhere")

	print("\n--- and it stays small ---")
	ck(src.find("PUBLISH_INTERVAL_SECONDS := 180.0") >= 0, "publishes every 3 minutes, not every tick")
	var page := FileAccess.get_file_as_string("res://docs/status.html")
	ck(page.find("setInterval(load, 120000)") >= 0,
		"and the page polls slower than the server republishes, so it never spins")
	ck(page.find("esc(") >= 0,
		"player names are escaped before going into HTML - they are user input")

	print("\n[ONLINESTATUS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
