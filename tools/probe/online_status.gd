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
	## ⚑ THE FIELD NAMES ARE THE REAL ONES. This fake had `character_class`, because the code
	## under test read `ch.character_class` - and Character has no such field, it is `class_type`.
	## So the feed printed a BLANK class to Discord for its whole life and this probe passed,
	## because the stand-in copied the bug. A fake that mirrors the code cannot test the code.
	var name := "Someone"
	var level := 1
	var class_type := "Warrior"
	var x := 0
	var y := 0
	func _init(n: String, lv: int, cls: String) -> void:
		name = n
		level = lv
		class_type = cls


class FakeServer:
	var characters := {}
	var chunk_manager = null


func _make() -> Node:
	"""A publisher with config loaded from memory rather than from disk, so the probe never touches
	the real server's file."""
	var node = OS_SCRIPT.new()
	get_root().add_child(node)
	return node


func _simulate_day(srv) -> Dictionary:
	"""A full 24 hours of _process ticks, counting how many REQUESTS actually leave the box.

	The population is deliberately quiet, because that is the owner's case: one player logs in at
	hour 3 and plays for two hours, moving between posts. Everything else is an empty server."""
	var node = _make()
	node._server = srv
	node._cfg = {"discord_webhook": "https://example.invalid/hook"}
	node.setup(srv)
	var sends := 0
	var checks := 0
	var bytes := 0
	var tick: float = OS_SCRIPT.CHECK_INTERVAL_SECONDS
	var t := 0.0
	while t < 86400.0:
		t += tick
		# Hours 3-5: one player on, changing location every ~10 minutes.
		srv.characters.clear()
		if t >= 10800.0 and t < 18000.0:
			var c := FakeChar.new("Solo", 12, "warrior")
			c.x = int(t / 600.0)
			srv.characters[1] = c
		# Drive the real decision, then account for what it would have sent.
		node._accum += tick
		node._since_send += tick
		if node._accum < OS_SCRIPT.CHECK_INTERVAL_SECONDS or node._busy:
			continue
		node._accum = 0.0
		checks += 1
		var st: Dictionary = node.build_status()
		if not node._should_send(st):
			continue
		node._last_sent_signature = node.status_signature(st)
		node._since_send = 0.0
		sends += 1
		bytes = maxi(bytes, JSON.stringify({"content": node._status_text(st)}).length())
	return {"sends": sends, "checks": checks, "bytes": bytes,
		"old_timer": int(86400.0 / 180.0)}


func _init() -> void:
	print("--- what a player actually sees in the channel ---")
	var node := _make()
	var srv := FakeServer.new()
	srv.characters = {1: FakeChar.new("Ashwyn", 42, "Sage"), 2: FakeChar.new("Bo", 7, "Fighter")}
	node._server = srv
	node._cfg = {"discord_webhook": "https://example.invalid/hook"}

	var st: Dictionary = node.build_status()
	ck(int(st.get("count", -1)) == 2, "both online players are listed (got %d)" % int(st.get("count", -1)))
	var first := String(st["players"][0].get("name", ""))
	ck(first == "Ashwyn", "sorted by level, highest first (top is %s)" % first)
	ck(String(st["players"][0].get("class", "")) != "", "a class is actually reported, not blank")
	# ⚑ THE DISPLAY NAME. Discord and the website are display surfaces like any other, so a
	# `Sage` must read as "Oracle" there too. Owner 2026-09-13: *"I just made an oracle and it
	# shows I'm a Sage..."*
	ck(String(st["players"][0].get("class", "")) == "Oracle",
		"a Sage is shown as 'Oracle' (got '%s')" % String(st["players"][0].get("class", "")))
	ck(String(st["players"][0].get("where", "")) != "", "and WHERE they are is never blank")

	# The real Character, so a renamed or removed field fails here instead of in Discord.
	var real_char = load("res://shared/character.gd").new()
	ck("class_type" in real_char,
		"Character really has `class_type` - the field the feed reads")
	ck(not ("character_class" in real_char),
		"...and not `character_class`, which is what it used to read")
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
	var wait: float = OS_SCRIPT.CHECK_INTERVAL_SECONDS - fresh._accum
	ck(wait > 0.0 and wait <= 30.0, "first publish is %.0fs after boot, not %.0fs" % [
		wait, OS_SCRIPT.CHECK_INTERVAL_SECONDS])
	print("
--- IT SENDS WHEN SOMETHING CHANGES, NOT ON A CLOCK ---")
	# Owner 2026-09-13: "seems like it will be a lot of wasted data." Measured rather than argued:
	# simulate a full day of _process ticks against a realistic population and count REQUESTS.
	var day := _simulate_day(srv)
	print("  a 24h day, one player on for two hours: %d request(s) sent, %d checks made" % [
		int(day["sends"]), int(day["checks"])])
	print("  the old fixed 3-minute timer would have sent %d" % int(day["old_timer"]))
	var bytes_now: int = int(day["sends"]) * int(day["bytes"])
	var bytes_old: int = int(day["old_timer"]) * int(day["bytes"])
	print("  payload %d bytes -> %.1f KB/day now, %.1f KB/day before" % [
		int(day["bytes"]), bytes_now / 1024.0, bytes_old / 1024.0])
	ck(int(day["sends"]) < int(day["old_timer"]) / 4,
		"a quiet day costs under a quarter of what the timer did")
	ck(int(day["sends"]) >= 24,
		"but the heartbeat still fires, so a stale feed is visible (%d sends)" % int(day["sends"]))

	print("
--- AND A PLAYER ARRIVING SHOWS UP FASTER THAN BEFORE ---")
	ck(OS_SCRIPT.CHECK_INTERVAL_SECONDS <= 60.0,
		"the list is checked every %.0fs" % OS_SCRIPT.CHECK_INTERVAL_SECONDS)
	ck(OS_SCRIPT.CHECK_INTERVAL_SECONDS < 180.0,
		"which is sooner than the 180s the fixed timer took at worst")
	# The signature must ignore the timestamp, or nothing ever compares equal and every check
	# sends - the exact bug this replaces, reintroduced.
	var a: Dictionary = {"updated": 100, "count": 1, "players": [{"name": "A", "level": 2, "class": "Mage", "where": "X"}]}
	var b: Dictionary = {"updated": 999999, "count": 1, "players": [{"name": "A", "level": 2, "class": "Mage", "where": "X"}]}
	ck(node.status_signature(a) == node.status_signature(b),
		"the same players at a different moment are the SAME list")
	var c: Dictionary = {"updated": 100, "count": 1, "players": [{"name": "A", "level": 3, "class": "Mage", "where": "X"}]}
	ck(node.status_signature(a) != node.status_signature(c), "a level-up is a change")
	var d: Dictionary = {"updated": 100, "count": 1, "players": [{"name": "A", "level": 2, "class": "Mage", "where": "Y"}]}
	ck(node.status_signature(a) != node.status_signature(d), "and so is moving somewhere else")



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
	ck(OS_SCRIPT.MIN_SEND_GAP_SECONDS >= 60.0,
		"two sends are at least %.0fs apart, so a login burst is not a request burst"
			% OS_SCRIPT.MIN_SEND_GAP_SECONDS)
	var page := FileAccess.get_file_as_string("res://docs/status.html")
	ck(page.find("setInterval(load, 120000)") >= 0,
		"and the page polls slower than the server republishes, so it never spins")
	ck(page.find("esc(") >= 0, "player names are escaped before going into HTML - they are user input")

	print("\n[ONLINESTATUS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
