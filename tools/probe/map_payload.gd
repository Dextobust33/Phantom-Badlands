extends SceneTree
## The overworld map on the wire: same picture, a fraction of the bytes.
##
## Phase 2.95 PHASE 1 (2026-09-11). `build_map_payload` is now the single implementation and
## `generate_map_display` is that payload inflated, so this probe's first job is to prove the
## round trip is exact - not close, exact - at every spot and in every header branch.
##
## Its second job is to hold the reason the change was made: the string is ~96% repetition and
## the payload is not. If a future edit starts pushing whole BBCode runs into the payload one
## cell at a time, the saving evaporates quietly, and the byte budget below is what notices.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const MapPayload = preload("res://shared/map_payload.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	var spots: Array = [Vector2i(40, 40), Vector2i(0, 0), Vector2i(-120, 60), Vector2i(300, -200)]
	for i in range(mini(4, cm.get_npc_posts().size())):
		var p: Dictionary = cm.get_npc_posts()[i]
		spots.append(Vector2i(int(p.get("x", 0)), int(p.get("y", 0))))

	print("--- a grid decodes to the CELLS it was built from ---")
	# This check exists because the obvious one is a tautology. `generate_map_display` IS
	# `inflate(build(...))` now, so comparing those two compares a thing with itself: an encoder
	# that mangled every index would still agree with itself and pass. Proven - corrupting the
	# palette index left the round-trip check green. So the reference here is the CELLS, which
	# the encoder never touches.
	var ref_rows: Array = ws._map_cells(40, 40, 11, [], [], [], [], [], {}, {}, {})
	var ref_lines: PackedStringArray = PackedStringArray()
	for r in ref_rows:
		ref_lines.append("".join(r))
	var expect: String = "\n".join(ref_lines)
	var through: String = MapPayload.inflate({"segs": [MapPayload.grid(ref_rows, "\n", "")]})
	ck(through == expect, "%d rows survive palette + index + base64 unchanged" % ref_rows.size())
	var mini_rows: Array = ws._minimap_cells(40, 40, [])
	var mini_expect := ""
	for r in mini_rows:
		mini_expect += "".join(r) + "\n"
	ck(MapPayload.inflate({"segs": [MapPayload.grid(mini_rows, "\n", "\n")]}) == mini_expect,
		"and so do the minimap's %d rows, trailing newline included" % mini_rows.size())

	print("\n--- inflate(build(x)) == what the string path produces ---")
	var exact := 0
	var wrong := 0
	var str_bytes := 0
	var pay_bytes := 0
	for s in spots:
		var explored: Dictionary = {}
		# Walk once so the second view has FOG to draw - a rendering path a single call misses.
		ws.generate_map_display(s.x - 5, s.y - 5, 11, [], [], [], [], [], explored, [], false, [])
		var overlays: Array = [{"x": s.x + 1, "y": s.y, "name": "Kestrel", "in_my_party": true},
			{"x": s.x + 2, "y": s.y, "name": "Vole"}, {"x": s.x + 2, "y": s.y, "name": "Wren"}]
		var payload: Dictionary = ws.build_map_payload(s.x, s.y, 11, overlays,
			[{"x": s.x - 1, "y": s.y, "color": "#A335EE"}], ["%d,%d" % [s.x, s.y + 1]],
			[{"x": s.x, "y": s.y - 1}], [{"x": s.x + 3, "y": s.y + 1}],
			explored.duplicate(), ["%d,%d" % [s.x - 2, s.y - 2]], true, [{"x": s.x - 3, "y": s.y + 2}])
		var from_payload: String = MapPayload.inflate(payload)
		var direct: String = ws.generate_map_display(s.x, s.y, 11, overlays,
			[{"x": s.x - 1, "y": s.y, "color": "#A335EE"}], ["%d,%d" % [s.x, s.y + 1]],
			[{"x": s.x, "y": s.y - 1}], [{"x": s.x + 3, "y": s.y + 1}],
			explored.duplicate(), ["%d,%d" % [s.x - 2, s.y - 2]], true, [{"x": s.x - 3, "y": s.y + 2}])
		if from_payload == direct:
			exact += 1
		else:
			wrong += 1
		str_bytes += direct.length()
		pay_bytes += MapPayload.wire_size(payload)
	ck(wrong == 0, "%d spots agree between the two paths, %d do not (consistency, not proof - see above)" % [exact, wrong])

	print("\n--- the bytes, which are the point ---")
	var avg_s := str_bytes / maxi(1, spots.size())
	var avg_p := pay_bytes / maxi(1, spots.size())
	print("  per location update: %d bytes of BBCode -> %d bytes of payload" % [avg_s, avg_p])
	ck(avg_p * 3 < avg_s, "the payload is at least 3x smaller (%.1fx)" % (float(avg_s) / maxf(1.0, float(avg_p))))

	print("\n--- it carries cells, not the world ---")
	var pay: Dictionary = ws.build_map_payload(40, 40, 11, [], [], [], [], [], {}, [], false, [])
	var grids := 0
	var cells := 0
	var pal_total := 0
	for seg in pay.get("segs", []):
		if seg.has("w"):
			grids += 1
			cells += int(seg["w"]) * int(seg["h"])
			pal_total += seg.get("p", []).size()
	ck(grids == 2, "two grids - the map and the minimap (%d)" % grids)
	ck(cells == 23 * 23 + 41 * 21, "%d cells, exactly the map (23x23) plus the minimap (41x21)" % cells)
	ck(pal_total < cells / 4, "%d distinct cells across %d squares - the repetition is what compresses" % [pal_total, cells])
	var raw := JSON.stringify(pay)
	ck(raw.find("blocks_los") < 0 and raw.find("encounter_rate") < 0 and raw.find("monster_level") < 0,
		"no tile internals ride along - the client gets what it may SEE, never the chunk")

	print("\n--- a payload a client cannot trust is still safe to read ---")
	ck(MapPayload.inflate({}) == "", "an empty payload inflates to nothing rather than erroring")
	ck(MapPayload.inflate({"segs": [{"w": 4, "h": 2, "p": [], "c": "", "b": 1}]}) == "",
		"a grid with no palette draws nothing")
	var truncated: Dictionary = pay.duplicate(true)
	for seg in truncated["segs"]:
		if seg.has("c"):
			seg["c"] = String(seg["c"]).substr(0, 8)
	var short_out: String = MapPayload.inflate(truncated)
	ck(short_out.length() > 0, "a truncated grid still inflates (%d chars) instead of crashing the client" % short_out.length())

	print("\n--- the wiring, on both sides ---")
	# A payload nobody sends is a payload nobody benefits from, and a negotiation with one half
	# missing is worse than none: it is a black map for whoever did not get the memo.
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	ck(cli.count('"caps": CLIENT_CAPS') == 3,
		"all three ways in announce what this build can read (login, register, dev auto-login)")
	ck(cli.find("const CLIENT_CAPS := {\"map\": 1}") >= 0, "and `map` is among them")
	var loc := cli.find("var map_payload = message.get(\"map\", null)")
	ck(loc > 0, "the location handler reads the payload")
	ck(loc > 0 and cli.substr(loc, 400).find("MapPayload.inflate(map_payload)") >= 0,
		"...and inflates it")
	ck(loc > 0 and cli.substr(loc, 400).find("message.get(\"description\", \"\")") >= 0,
		"...still falling back to the old string, so an old server keeps working")
	ck(srv.find("world_system.build_map_payload(") >= 0, "the server builds the payload once")
	ck(srv.find("_peer_reads_map_payload(peer_id)") >= 0, "...and asks whether this peer can read it")
	ck(srv.find('world_system.MapPayload.inflate(map_payload)') >= 0,
		"...inflating it for the ones that cannot, rather than sending them nothing")
	var caps := srv.find("func _peer_reads_map_payload")
	ck(caps > 0 and srv.substr(caps, 220).find('.get("caps", {}).get("map", 0)') >= 0,
		"a client that says nothing reads as not-capable, which is the safe default")

	print("\n[MAPPAYLOAD] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
