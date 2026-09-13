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
## How often to publish. Deliberately slow: the owner asked for "fairly accurate without being
## too costly", and a status list nobody is watching second-by-second does not need to be.
const PUBLISH_INTERVAL_SECONDS := 180.0

var _accum: float = 0.0
var _cfg: Dictionary = {}
var _discord_message_id: String = ""
var _busy: bool = false
var _server = null


func setup(server_ref) -> void:
	_server = server_ref
	_load_config()


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
	if _accum < PUBLISH_INTERVAL_SECONDS or _busy:
		return
	_accum = 0.0
	_publish()


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


func _publish() -> void:
	var st: Dictionary = build_status()
	_busy = true
	_publish_discord(st)
	_publish_gist(st)


func _publish_discord(st: Dictionary) -> void:
	var hook := String(_cfg.get("discord_webhook", ""))
	if hook == "":
		_busy = false
		return
	var body := JSON.stringify({"content": _status_text(st)})
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, resp):
		# First publish: remember the message id so every later one EDITS instead of posting.
		if _discord_message_id == "" and code >= 200 and code < 300:
			var parsed = JSON.parse_string(resp.get_string_from_utf8())
			if parsed is Dictionary and parsed.has("id"):
				_discord_message_id = String(parsed["id"])
				_cfg["discord_message_id"] = _discord_message_id
				_save_config()
		req.queue_free()
		_busy = false)
	var headers := ["Content-Type: application/json"]
	if _discord_message_id != "":
		req.request("%s/messages/%s" % [hook, _discord_message_id], headers, HTTPClient.METHOD_PATCH, body)
	else:
		# `?wait=true` makes Discord return the created message, which is how we learn its id.
		req.request(hook + "?wait=true", headers, HTTPClient.METHOD_POST, body)


func _publish_gist(st: Dictionary) -> void:
	"""PATCH the status JSON into a gist, which the website's status page fetches."""
	var token := String(_cfg.get("github_token", ""))
	var gist := String(_cfg.get("gist_id", ""))
	if token == "" or gist == "":
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	var body := JSON.stringify({"files": {"status.json": {"content": JSON.stringify(st)}}})
	req.request("https://api.github.com/gists/" + gist,
		["Content-Type: application/json", "Authorization: Bearer " + token,
		 "User-Agent: PhantomBadlands", "X-GitHub-Api-Version: 2022-11-28"],
		HTTPClient.METHOD_PATCH, body)


func _save_config() -> void:
	var f = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cfg, "\t"))
	f.close()
