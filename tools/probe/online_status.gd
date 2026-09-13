extends SceneTree
## The online-status feed: small, correct, self-healing, and silent when unconfigured.
##
## Owner 2026-09-13: *"a tool that is efficient and doesn't use much data that shows the players
## currently online... viewable from my android phone and in discord."*
##
## The failure that matters is not "it does not work" - it is that it costs something, or leaks
## something, or spams a Discord channel with a new message every three minutes forever, or
## quietly stops publishing and nobody finds out for a week.
##
## ⚑ THIS PROBE EXECUTES THE NODE. Its first version only searched the source for strings, which
## is the instrument defect that let an unreachable figure block ship twice: source that reads
## correctly and never runs looks identical to source that works. Every behavioural claim below
## drives a real call.
const OS_SCRIPT = preload("res://server/online_status.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


class FakeChar:
	var name := "Someone"
	var level := 1
	var character_class := "warrior"
	var x := 0
	var y := 0
	func _init(n: String, lv: int, cls: String) -> void:
		name = n
		level = lv
		character_class = cls


class FakeServer:
	var characters := {}
	var chunk_manager = null


func _make() -> Node:
	"""A publisher with config loaded from memory rather than from disk, so the probe never touches
	the real server's file."""
	var node = OS_SCRIPT.new()
	get_root().add_child(node)
	return node


func _init() -> void:
	print("--- what a player actually sees in the channel ---")
	var node := _make()
	var srv := FakeServer.new()
	srv.characters = {1: FakeChar.new("Ashwyn", 42, "necromancer"), 2: FakeChar.new("Bo", 7, "warrior")}
	node._server = srv
	node._cfg = {"discord_webhook": "https://example.invalid/hook"}

	var st: Dictionary = node.build_status()
	ck(int(st.get("count", -1)) == 2, "both online players are listed (got %d)" % int(st.get("count", -1)))
	var first := String(st["players"][0].get("name", ""))
	ck(first == "Ashwyn", "sorted by level, highest first (top is %s)" % first)
	ck(String(st["players"][0].get("class", "")) == "Necromancer", "class is shown title-cased")
	ck(String(st["players"][0].get("where", "")) != "", "and WHERE they are is never blank")

	var text: String = node._status_text(st)
	ck(text.find("Ashwyn") >= 0 and text.find("Bo") >= 0, "the Discord body names them")
	ck(text.find("Lv 42") >= 0, "...with their level")
	ck(text.find("<t:") >= 0, "...and a timestamp Discord renders as 'x minutes ago'")

	var empty: String = node._status_text({"count": 0, "updated": 0, "players": []})
	ck(empty.find("nobody") >= 0 and empty.find("```") < 0,
		"nobody online reads as 'nobody', with no empty code block")

	print("\n--- the payload stays SMALL, because it is sent forever ---")
	var big := FakeServer.new()
	for i in range(40):
		big.characters[i] = FakeChar.new("Player%d" % i, i + 1, "rogue")
	node._server = big
	var bytes := JSON.stringify(node.build_status()).length()
	ck(bytes < 6000, "40 players serialise to %d bytes (< 6000)" % bytes)
	node._server = srv

	print("\n--- it EDITS one message rather than posting forever ---")
	node._discord_message_id = ""
	node._cfg.erase("discord_message_id")
	# First reply from Discord, carrying the id of the message it just created.
	node.on_discord_response(HTTPRequest.RESULT_SUCCESS, 200, '{"id":"111222333"}', false)
	ck(node._discord_message_id == "111222333",
		"the first POST's message id is remembered (got '%s')" % node._discord_message_id)

	print("\n--- and it HEALS if that message is deleted ---")
	# Somebody tidies the channel. Every later PATCH 404s. Without this the status is gone for good.
	node.on_discord_response(HTTPRequest.RESULT_SUCCESS, 404, '{"message":"Unknown Message"}', true)
	ck(node._discord_message_id == "",
		"a 404 on the edit forgets the dead id, so the next publish reposts")
	ck(not node._cfg.has("discord_message_id"), "...and forgets it on disk too, so a restart agrees")

	print("\n--- a bad reply does not corrupt the remembered id ---")
	node._discord_message_id = "999"
	node.on_discord_response(HTTPRequest.RESULT_SUCCESS, 500, "oops", true)
	ck(node._discord_message_id == "999", "a 500 is transient and keeps editing the same message")
	node.on_discord_response(HTTPRequest.RESULT_CANT_CONNECT, 0, "", true)
	ck(node._discord_message_id == "999", "so is being unable to connect at all")
	# A 404 that is NOT an edit is the webhook itself being wrong - do not loop clearing an id.
	node._discord_message_id = ""
	node.on_discord_response(HTTPRequest.RESULT_SUCCESS, 404, "", false)
	ck(node._discord_message_id == "", "a 404 on the first POST leaves nothing to forget")

	print("\n--- it costs nothing when nobody has configured it ---")
	var bare := _make()
	bare._server = srv
	bare._cfg = {}
	bare._process(9999.0)   # a developer's local server: no config, no webhook, no requests
	ck(bare._busy == false, "an unconfigured server never starts a request")
	var no_hook := _make()
	no_hook._server = srv
	no_hook._cfg = {"gist_id": "x"}
	no_hook._busy = true
	no_hook._publish_discord({"count": 0, "updated": 0, "players": []})
	ck(no_hook._busy == false,
		"and a config with no webhook RELEASES the busy flag, or it would never publish again")

	print("\n--- a failed send cannot wedge it forever ---")
	# `request()` refusing must clear _busy itself: the completion signal never fires, so nothing
	# else will. (What makes it refuse here is incidental - the probe's HTTPRequest is not in a
	# live tree. The branch under test is `if err != OK`, and this is what reaches it.)
	var wedge := _make()
	wedge._server = srv
	wedge._cfg = {"discord_webhook": "not a url at all"}
	wedge._busy = true
	wedge._publish_discord(wedge.build_status())
	ck(wedge._busy == false, "a request that cannot even start clears _busy")

	print("\n--- it publishes soon after a restart, not three minutes later ---")
	var fresh := _make()
	fresh._server = srv
	fresh.setup(srv)
	var wait: float = OS_SCRIPT.PUBLISH_INTERVAL_SECONDS - fresh._accum
	ck(wait > 0.0 and wait <= 30.0, "first publish is %.0fs after boot, not %.0fs" % [
		wait, OS_SCRIPT.PUBLISH_INTERVAL_SECONDS])

	print("\n--- secrets stay out of git ---")
	ck(OS_SCRIPT.CONFIG_PATH == "user://online_status.cfg",
		"config lives in user:// on the server, not in the repo")
	# The needles are ASSEMBLED rather than written out, because this probe scans ITSELF and a
	# literal webhook prefix here would match. That it did exactly that on first run is the only
	# proof this detector fires at all - an empty result and a broken search look the same.
	var needles := ["discord.com/api/" + "webhooks/", "gh" + "p_"]
	var repo_leak := ""
	for f in ["res://server/online_status.gd", "res://docs/status.html", "res://server/server.gd",
			"res://tools/probe/online_status.gd"]:
		var t := FileAccess.get_file_as_string(f)
		for needle in needles:
			if t.find(needle) >= 0:
				repo_leak = "%s (%s)" % [f, needle]
	ck(repo_leak == "", "no webhook URL or token is committed anywhere (leak: %s)" % repo_leak)

	print("\n--- and it stays cheap ---")
	ck(OS_SCRIPT.PUBLISH_INTERVAL_SECONDS >= 120.0,
		"publishes every %.0fs, not every tick" % OS_SCRIPT.PUBLISH_INTERVAL_SECONDS)
	var page := FileAccess.get_file_as_string("res://docs/status.html")
	ck(page.find("setInterval(load, 120000)") >= 0,
		"and the page polls slower than the server republishes, so it never spins")
	ck(page.find("esc(") >= 0, "player names are escaped before going into HTML - they are user input")

	print("\n[ONLINESTATUS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
