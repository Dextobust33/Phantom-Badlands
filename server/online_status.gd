extends Node
## Who is online, published cheaply to Discord and to the website.
##
## Owner 2026-09-13: *"I need a tool that is efficient and doesn't use much data that shows the
## players currently online. It doesn't have to update every second or anything but should be
## fairly accurate without being too costly. I'd like it to be viewable from my android phone and
## in discord."*
##
## WHY THIS SHAPE. The game host runs nothing but SSH and the game port - no web server, no
## /var/www - and adding one would mean a new open port and something else to keep patched for a
## read-only status list. So nothing is SERVED from the game box. Instead one small HTTPS request
## goes OUT every few minutes:
##
##   * DISCORD - the webhook EDITS a single message rather than posting new ones, so the channel
##     stays clean and the history is not a wall of duplicates. The Discord Android app is what
##     makes this viewable on a phone, which was half the ask.
##   * THE WEBSITE - the same JSON is PATCHed into a GitHub Gist, and the status page on
##     phantombadlands.com (GitHub Pages, served from `docs/`) fetches it. No hosting to add: the
##     site already exists and the gist is a file GitHub serves for free.
##
## COST. One JSON body of a few hundred bytes per interval, regardless of how many players are
## on. At the default three minutes that is about 20 requests an hour.
##
## ⚑ SECRETS ARE NOT IN GIT. Both the webhook URL and the gist token are read from a file on the
## SERVER, outside the repo. A webhook URL in a public repo is an open invitation to post into
## the channel, and a token is worse. See `CONFIG_PATH`.

const CONFIG_PATH := "user://online_status.cfg"

## ⚑ IT SENDS WHEN SOMETHING CHANGES, NOT ON A CLOCK.
##
## Owner 2026-09-13: *"Do we think checking every 3 minutes is too excessive? The game isn't very
## popular yet so there aren't many changes, seems like it will be a lot of wasted data."* Right,
## and worse than it looked: a fixed timer sent the SAME payload 480 times a day whether anybody
## logged in or not, and still took up to three minutes to show someone who just arrived. Both
## halves of that are wrong at once.
##
## So the list is CHECKED often and cheaply - it is a walk over connected peers, in process, no
## network - and only SENT when it differs from what was last sent. An empty server now sends 48
## requests a day instead of 480, and a player arriving shows up within a minute instead of three.
const CHECK_INTERVAL_SECONDS := 60.0
## The floor between two sends, so a burst of logins cannot become a burst of requests.
const MIN_SEND_GAP_SECONDS := 60.0
## Send anyway after this long with no change, so the "updated N ago" line stays credible and a
## silent failure is still visible as a stale timestamp rather than as nothing at all.
const IDLE_HEARTBEAT_SECONDS := 1800.0

var _accum: float = 0.0
## What was last SENT, to compare against. Not the whole payload - the timestamp changes every
## time and would make every check look like a change.
var _last_sent_signature: String = ""
var _since_send: float = 0.0
var _cfg: Dictionary = {}
var _discord_message_id: String = ""
var _busy: bool = false
var _server = null


func setup(server_ref) -> void:
	_server = server_ref
	_load_config()
	# Publish shortly after boot rather than waiting a full interval. A restart is exactly when
	# the channel is most likely to be WRONG - everyone was just disconnected - so leaving it
	# stale is the worst time to be slow. Ten seconds of grace lets players reconnect first, so
	# the first list is not empty.
	_accum = CHECK_INTERVAL_SECONDS - 10.0
	# Nothing has been sent by this process, so the first check always sends.
	_last_sent_signature = ""
	_since_send = IDLE_HEARTBEAT_SECONDS


func _load_config() -> void:
	"""Read the webhook URL and gist credentials from outside the repo.

	Absent config is NOT an error and must never be: a developer running the server locally has
	no webhook, and the game must not care."""
	var f = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_cfg = parsed
		_discord_message_id = String(_cfg.get("discord_message_id", ""))


func _process(delta: float) -> void:
	if _cfg.is_empty() or _server == null:
		return
	_accum += delta
	_since_send += delta
	if _accum < CHECK_INTERVAL_SECONDS or _busy:
		return
	_accum = 0.0
	var st: Dictionary = build_status()
	if not _should_send(st):
		return
	_last_sent_signature = status_signature(st)
	_since_send = 0.0
	_publish(st)


func status_signature(st: Dictionary) -> String:
	"""What makes two status lists the SAME list. Deliberately excludes `updated` - that moves on
	every check and would make nothing ever compare equal, which is the whole bug this avoids."""
	var parts: Array = []
	for p in st.get("players", []):
		parts.append("%s|%d|%s|%s" % [String(p.get("name", "")), int(p.get("level", 0)),
			String(p.get("class", "")), String(p.get("where", ""))])
	# The list is already sorted by level; sort again by the rendered row so two identical
	# populations cannot differ by ordering alone.
	parts.sort()
	return "
".join(parts)


func _should_send(st: Dictionary) -> bool:
	"""Whether this check is worth a request."""
	if _since_send < MIN_SEND_GAP_SECONDS:
		return false
	if status_signature(st) != _last_sent_signature:
		return true
	return _since_send >= IDLE_HEARTBEAT_SECONDS


func build_status() -> Dictionary:
	"""The payload. Small on purpose - this is sent every few minutes forever."""
	var players: Array = []
	for peer_id in _server.characters:
		var ch = _server.characters[peer_id]
		if ch == null:
			continue
		var where := "the wilds"
		if _server.chunk_manager != null:
			var near: Dictionary = _server.chunk_manager.get_nearest_npc_post_with_tier(int(ch.x), int(ch.y))
			var pname := String(near.get("post_name", ""))
			if pname != "":
				where = pname
		players.append({
			"name": String(ch.name),
			"level": int(ch.level),
			"class": String(ch.character_class).capitalize(),
			"where": where,
		})
	players.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	return {
		"updated": int(Time.get_unix_time_from_system()),
		"count": players.size(),
		"players": players,
	}


func _status_text(st: Dictionary) -> String:
	"""The Discord body. Plain text in a code block - it renders identically on the Android app
	and the desktop client, which a table or an embed does not."""
	var n := int(st.get("count", 0))
	var lines: Array = []
	lines.append("**Phantom Badlands** - %s online" % ("nobody" if n == 0 else str(n)))
	lines.append("<t:%d:R>" % int(st.get("updated", 0)))   # Discord renders this as "2 minutes ago"
	if n > 0:
		lines.append("```")
		for p in st.get("players", []):
			lines.append("%-16s Lv %-5d %-10s %s" % [
				String(p.get("name", "?")).substr(0, 16), int(p.get("level", 1)),
				String(p.get("class", "")).substr(0, 10), String(p.get("where", ""))])
		lines.append("```")
	return "\n".join(lines)


func _publish(st: Dictionary) -> void:
	_busy = true
	_publish_discord(st)
	_publish_gist(st)


func _publish_discord(st: Dictionary) -> void:
	var hook := String(_cfg.get("discord_webhook", ""))
	if hook == "":
		_busy = false
		return
	var body := JSON.stringify({"content": _status_text(st)})
	var editing := _discord_message_id != ""
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, resp):
		on_discord_response(result, code, resp.get_string_from_utf8(), editing)
		req.queue_free()
		_busy = false)
	var headers := ["Content-Type: application/json"]
	var err: int
	if editing:
		err = req.request("%s/messages/%s" % [hook, _discord_message_id], headers, HTTPClient.METHOD_PATCH, body)
	else:
		# `?wait=true` makes Discord return the created message, which is how we learn its id.
		err = req.request(hook + "?wait=true", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		# ⚑ `_busy` IS CLEARED HERE OR IT IS NEVER CLEARED. When `request()` itself fails the
		# completion signal never fires, so the callback above - the only other place that clears
		# the flag - does not run, and a single failed call would stop publishing FOREVER rather
		# than for one interval.
		push_warning("[online_status] could not start discord request: %d" % err)
		req.queue_free()
		_busy = false


func on_discord_response(result: int, code: int, body: String, editing: bool) -> void:
	"""What a Discord reply MEANS. A named method rather than a closure so a probe can drive every
	branch of it without a network - the previous probe could only read this file's source, and a
	source-reading probe once passed on a block that could never execute."""
	if result != HTTPRequest.RESULT_SUCCESS:
		# The request never reached Discord at all - DNS, TLS, the box briefly offline.
		# Say so: the whole point of this node is that nobody is watching it.
		push_warning("[online_status] discord request failed, result %d" % result)
	elif code == 404 and editing:
		# ⚑ THE MESSAGE WAS DELETED, and without this the status never comes back.
		# We only ever PATCH once an id is known, so a 404 means the thing we are editing is
		# gone - somebody tidied the channel. Holding the dead id would make every future publish
		# 404 forever, silently. Forgetting it makes the next one POST a fresh message and
		# re-learn its id, which is the self-healing path.
		push_warning("[online_status] discord message %s is gone; will repost" % _discord_message_id)
		_discord_message_id = ""
		_cfg.erase("discord_message_id")
		_save_config()
	elif code < 200 or code >= 300:
		push_warning("[online_status] discord returned HTTP %d: %s" % [code, body.substr(0, 200)])
	elif not editing:
		# First publish: remember the message id so every later one EDITS instead of posting.
		var parsed = JSON.parse_string(body)
		if parsed is Dictionary and parsed.has("id"):
			_discord_message_id = String(parsed["id"])
			_cfg["discord_message_id"] = _discord_message_id
			_save_config()
			print("[online_status] discord message %s created; later updates will edit it" % _discord_message_id)


func _publish_gist(st: Dictionary) -> void:
	"""PATCH the status JSON into a gist, which the website's status page fetches."""
	var token := String(_cfg.get("github_token", ""))
	var gist := String(_cfg.get("gist_id", ""))
	if token == "" or gist == "":
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, resp):
		# A token expires, a gist gets deleted. Neither should be a silent stop.
		if result != HTTPRequest.RESULT_SUCCESS:
			push_warning("[online_status] gist request failed, result %d" % result)
		elif code < 200 or code >= 300:
			push_warning("[online_status] gist returned HTTP %d: %s" % [
				code, resp.get_string_from_utf8().substr(0, 200)])
		req.queue_free())
	var body := JSON.stringify({"files": {"status.json": {"content": JSON.stringify(st)}}})
	var err := req.request("https://api.github.com/gists/" + gist,
		["Content-Type: application/json", "Authorization: Bearer " + token,
		 "User-Agent: PhantomBadlands", "X-GitHub-Api-Version: 2022-11-28"],
		HTTPClient.METHOD_PATCH, body)
	if err != OK:
		push_warning("[online_status] could not start gist request: %d" % err)
		req.queue_free()


func _save_config() -> void:
	var f = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cfg, "\t"))
	f.close()
