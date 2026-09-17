extends SceneTree
## ⛑ DOES THE CLIENT KNOW WHICH SQUARES OPEN A MENU — AND IS ITS LIST THE SERVER'S?
##
## Owner 2026-09-17, on the travel row still being up as a menu opens: *"Yes - hide on the
## keypress."* Measured cause: bump-to-interact is entirely server-side, so for one round trip
## (71ms to the live server, ~6 frames with the polls) the client has no reason to change
## anything. It guesses now, from the map payload's meaning grid.
##
## A guess is only as good as the two tables behind it, and both are the shapes this project keeps
## paying for:
##
##   1. **WHICH TILES open a menu.** The authority is the server's `elif` chain in `handle_move`.
##      Hand-copied into the client, a station added there silently stops being masked here — and
##      the symptom is "the travel row still shows for that one station", which nobody reports.
##   2. **WHICH WAY each direction id goes.** I wrote the client's copy from memory as 0-7. The
##      game uses the numpad, 1-9 with 5 as stay, so every entry was wrong and the mask would have
##      read the wrong square on every move. There is one table now and `move_player` reads it.
##
## Run:
##   godot --headless --path . --script res://tools/probe/menu_bump_tiles.gd

const WS := preload("res://shared/world_system.gd")
const CDB := preload("res://shared/crafting_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== 1. THE DIRECTION TABLE, AGAINST TWO INDEPENDENT SOURCES =====")
	# ⛑ THE FIRST VERSION OF THIS WAS CIRCULAR AND THE INJECTION PROVED IT. It compared the
	# table with `move_player`, which now READS the table - so breaking the table broke both
	# sides identically and the check still passed. `8: Vector2i(0, -1)` (north pointing south)
	# produced zero failures.
	#
	# A single-owner value cannot be checked against itself. So it is checked against two things
	# that say the same fact independently: `move_player`'s DOCSTRING, which spells the numpad
	# out in words, and `_get_direction_text`, which turns a delta into a compass word and
	# carries its own copy of "world y grows NORTH".
	var ws = WS.new()
	var srv0 := FileAccess.get_file_as_string("res://server/server.gd")
	var wsrc := FileAccess.get_file_as_string("res://shared/world_system.gd")

	# (a) the docstring, parsed. `7=NW, 8=N, 9=NE` etc.
	var di := wsrc.find("func move_player")
	var doc := wsrc.substr(di, 500)
	var from_doc := {}
	var word_delta := {
		"N": Vector2i(0, 1), "S": Vector2i(0, -1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0),
		"NE": Vector2i(1, 1), "NW": Vector2i(-1, 1), "SE": Vector2i(1, -1), "SW": Vector2i(-1, -1),
	}
	# The docstring lays the numpad out as three ROWS on three lines, so newlines and tabs are
	# separators exactly like the commas. Splitting on commas alone found 5 of 9 and mangled
	# every entry that sat at a line break.
	var flat := doc.replace("\n", ",").replace("\t", ",").replace("  ", " ")
	for pair in flat.split(","):
		var t: String = String(pair).strip_edges()
		var eq := t.find("=")
		if eq <= 0:
			continue
		var idtxt := t.substr(0, eq).strip_edges()
		var word := t.substr(eq + 1).strip_edges()
		if not idtxt.is_valid_int():
			continue
		if word_delta.has(word):
			from_doc[int(idtxt)] = word_delta[word]
	print("           docstring names %d of the nine directions" % from_doc.size())
	ck(from_doc.size() >= 8, "the docstring was parsed (%d directions)" % from_doc.size())
	var doc_bad: Array = []
	for d in from_doc.keys():
		if Vector2i(WS.MOVE_DELTAS.get(d, Vector2i(99, 99))) != Vector2i(from_doc[d]):
			doc_bad.append("dir %d: table %v, docstring %v" % [
				int(d), WS.MOVE_DELTAS.get(d, Vector2i.ZERO), from_doc[d]])
	for b in doc_bad:
		print("           AGAINST THE DOCSTRING: " + String(b))
	ck(doc_bad.is_empty(), "the table agrees with move_player's own docstring (%d off)" % doc_bad.size())

	# (b) the compass, which encodes north separately.
	var srv_inst = load("res://server/server.gd").new()
	var id_word := {1: "southwest", 2: "south", 3: "southeast", 4: "west",
		6: "east", 7: "northwest", 8: "north", 9: "northeast"}
	var comp_bad: Array = []
	for d in id_word.keys():
		var dl: Vector2i = WS.MOVE_DELTAS.get(d, Vector2i.ZERO)
		# Scaled out so the compass reads it as a clean bearing rather than a 1-tile diagonal.
		var txt: String = srv_inst._get_direction_text(0, 0, dl.x * 10, dl.y * 10)
		if not txt.ends_with(String(id_word[d])):
			comp_bad.append("dir %d (%v) reads as '%s', expected %s" % [
				int(d), dl, txt, String(id_word[d])])
	for b in comp_bad:
		print("           AGAINST THE COMPASS: " + String(b))
	ck(comp_bad.is_empty(), "and with the compass the bearings are written from (%d off)" % comp_bad.size())
	srv_inst.free()

	# ...and `move_player` still USES it, which is the single-owner half.
	var uses: bool = "MOVE_DELTAS.get(direction" in wsrc
	ck(uses, "move_player reads the table rather than carrying its own match")
	ck(WS.MOVE_DELTAS.size() == 9, "all nine numpad directions are present")
	# ⛑ The specific fault that started this: a 0-7 numbering written from memory.
	ck(not WS.MOVE_DELTAS.has(0), "there is no direction 0 (the game numbers from 1, like a numpad)")
	ck(Vector2i(WS.MOVE_DELTAS.get(5, Vector2i.ONE)) == Vector2i.ZERO, "5 is stay")

	print("\n===== 2. THE MENU-TILE LIST IS THE SERVER'S BUMP CHAIN =====")
	# ⛑ Read off `handle_move`'s own `elif` chain rather than trusting either list. This is the
	# guard that makes the client's copy safe: add a station to the server and this fails.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var i := srv.find("func handle_move")
	var j := srv.find("\nfunc ", i + 10)
	var body := srv.substr(i, (j - i) if j > i else 40000)
	var from_server: Array = []
	for line in body.split("\n"):
		var t: String = line.strip_edges()
		var m := t.trim_prefix("elif ").trim_prefix("if ")
		if m.begins_with("bump_type == \""):
			var q := m.substr(m.find("\"") + 1)
			from_server.append(q.substr(0, q.find("\"")))
	# ...plus the station family, which the chain handles as a group through the shared map.
	var station_line: bool = "bump_type in CraftingDatabaseScript.STATION_SKILL_MAP" in body
	print("           server chain names %d tiles individually, station group present: %s" % [
		from_server.size(), str(station_line)])
	ck(from_server.size() >= 6, "the server's chain was found and parsed (%d)" % from_server.size())
	ck(station_line, "and it handles the crafting stations as a group")

	var missing: Array = []
	for t in from_server:
		if not WS.opens_menu_on_bump(String(t)):
			missing.append(String(t))
	for m2 in missing:
		print("           SERVER OPENS A MENU, CLIENT DOES NOT KNOW: " + String(m2))
	ck(missing.is_empty(), "the client knows every tile the server opens a menu for (%d missed)" % missing.size())

	# ...and nothing in the client's list that the server does NOT act on, which would mask the
	# travel row on a move that opens nothing - the blink the owner accepted, spent for no reason.
	var extra: Array = []
	for t in WS.MENU_ON_BUMP_TILES:
		if not (String(t) in from_server):
			extra.append(String(t))
	for e in extra:
		print("           CLIENT EXPECTS A MENU THE SERVER DOES NOT OPEN: " + String(e))
	ck(extra.is_empty(), "and expects no menu the server will not open (%d extra)" % extra.size())

	print("\n===== 3. THE STATIONS COME FROM THE CRAFTING DATABASE, NOT A COPY =====")
	for st in CDB.STATION_SKILL_MAP.keys():
		ck(WS.opens_menu_on_bump(String(st)), "%s (%s) opens a menu" % [st, CDB.STATION_SKILL_MAP[st]])
	ck(not WS.opens_menu_on_bump("plains"), "and plain ground does not")
	ck(not WS.opens_menu_on_bump(""), "nor does an empty meaning (the uncertain case)")

	print("\n===== 4. AND THE CLIENT IS ACTUALLY WIRED TO USE IT =====")
	# The two tables being right is worth nothing if the three pieces are not connected. Source
	# checks, because reaching this live needs a connected client standing beside a market.
	var cl := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cl.contains("_last_meaning = meaning"),
		"the client keeps the meaning grid it already parses")
	ck(cl.contains("if _tile_opens_menu(direction):"),
		"send_move asks what it is walking into")
	ck(cl.contains("WorldSystem.MOVE_DELTAS.get(direction"),
		"and reads the shared direction table, not a copy")
	ck(cl.contains("WorldSystem.opens_menu_on_bump(m)"),
		"and the shared tile list, not a copy")
	ck(cl.contains("if Time.get_ticks_msec() < _menu_expected_until_ms:"),
		"the margin rule honours the guess")
	ck(cl.contains("_resolve_expected_menu(msg_type)"),
		"and the server's reply ends it")
	# ⛑ The guess MUST expire on its own. If the resolving-message list ever misses the reply that
	# actually comes back, a deadline is the only thing that puts the travel row back.
	ck(cl.contains("const MENU_EXPECTED_WINDOW_MS"),
		"there is a hard expiry, so a missed reply cannot hide the row forever")

	print("\n===== NOT COVERED HERE =====")
	print("  Whether the mask FEELS right - 500ms is the ceiling on the guess, and only a live")
	print("  run against the 71ms server says whether the blink on a refused bump is noticeable.")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
