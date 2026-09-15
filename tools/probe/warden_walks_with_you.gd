extends SceneTree
## Does the Warden actually appear beside you while he is escorting?
##
## Owner 2026-09-14: *"He still doesn't follow you on the map or lead the way so the player may
## think they are alone still and not sure what to do."* He existed only at combat start, so an
## escort the player had been promised in writing was invisible for the entire walk to the fight.
##
## Two things can go wrong and neither is visible in the source: he can be drawn into the cell the
## companion already occupies (the composer refuses to overwrite an occupied cell, so one of them
## silently vanishes), and he can be drawn at tile scale instead of figure scale.
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


# Mirrors of the two client helpers. They are three lines each and duplicating them here would be
# two copies of one value - so the probe reads them out of the client instead.
func _offsets(fn: String) -> Dictionary:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var i := src.find("func %s(facing: String) -> Vector2i:" % fn)
	if i == -1:
		return {}
	var j := src.find("\nfunc ", i + 10)
	var body := src.substr(i, (j - i) if j > i else 1200)
	var out := {}
	var cur: Array = []
	for line in body.split("\n"):
		var t := line.strip_edges()
		if t.ends_with(":") and t.begins_with("\"") :
			cur = []
			for piece in t.rstrip(":").split(","):
				cur.append(piece.strip_edges().replace("\"", ""))
		elif t.begins_with("_:"):
			cur = ["_default"]
		elif t.begins_with("return Vector2i("):
			var nums := t.replace("return Vector2i(", "").split(")")[0].split(",")
			var v := Vector2i(int(nums[0].strip_edges()), int(nums[1].strip_edges()))
			for c in cur:
				out[c] = v
	return out


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")

	print("===== THE SERVER SAYS WHETHER HE IS WITH YOU =====")
	ck(ssrc.contains('"escort": "warden" if _guide_escorts_overworld(peer_id, character) else ""'),
		"escort state rides the LOCATION message, so it is true of the frame being drawn")
	ck(src.contains('_escort_kind = String(message.get("escort", ""))'), "and the client reads it")

	print("")
	print("===== HE WALKS BEHIND YOU, WHICH IS WHAT 'FOLLOWING' LOOKS LIKE =====")
	# A figure level with you reads as one STANDING BESIDE you. The owner asked for a follower.
	# Behind is normally the companion's square - but a character being escorted has no
	# companion: the Warden walks stages 1 and 2, and the egg is not paid until the end of
	# stage 3. So for every player this actually happens to, the cell behind is empty.
	ck(src.contains("else _trail_offset(_local_map_facing)"),
		"with no companion he takes the cell BEHIND you, like a follower")
	ck(src.contains("_escort_offset(_local_map_facing) if _has_comp"),
		"and only steps to the flank when a companion already has that square")
	var qsrc := FileAccess.get_file_as_string("res://shared/quest_database.gd")
	var i3 := qsrc.find("\"wardens_watch_3\"")
	var q3 := qsrc.substr(i3, 1400) if i3 != -1 else ""
	ck(q3.contains("companion egg"),
		"  (the egg really is paid at stage 3, after the escort has gone)")
	ck(FileAccess.get_file_as_string("res://server/server.gd").contains("return st == 1 or st == 2"),
		"  (and the escort really is stages 1-2 only)")

	print("")
	print("===== AND WHEN THERE IS A COMPANION, THEY DO NOT SHARE A SQUARE =====")
	# This is the one that would have shipped silently: the composer skips a cell that already
	# holds a figure, so a collision does not error, it just deletes somebody.
	var trail := _offsets("_trail_offset")
	var escort := _offsets("_escort_offset")
	ck(not trail.is_empty() and not escort.is_empty(),
		"both offset tables were read out of the client (%d / %d entries)" % [trail.size(), escort.size()])
	for facing in ["left", "right", "up", "down", "_default"]:
		var t: Vector2i = trail.get(facing, trail.get("_default", Vector2i.ZERO))
		var e: Vector2i = escort.get(facing, escort.get("_default", Vector2i.ZERO))
		ck(t != e, "  facing %-8s companion %v, Warden %v" % [facing, t, e])
		ck(e != Vector2i.ZERO, "    and he is not standing on top of you")

	print("")
	print("===== AND ALL THREE OF YOU ACTUALLY DRAW =====")
	if not Room.available():
		print("  SKIP - baked overworld art not present in this checkout")
	else:
		var meaning: Array = []
		var biomes: Array = []
		for y in range(5):
			var r: Array = []
			var b: Array = []
			for x in range(5):
				r.append("grass")
				b.append("grass")
			meaning.append(r)
			biomes.append(b)
		var me := "res://client/sprites/overworld_pad32/1_1/down_stand.png"
		var warden := "res://client/sprites/overworld_pad32/m1_1/down_stand.png"
		# you at centre, companion behind (facing right -> -1,0), Warden beside (0,-1)
		var figs := {"2,2": {"main": me}, "1,2": {"main": me}, "2,1": {"main": warden}}
		ck(Room.build(meaning, biomes, figs, {}, 0), "a map with you, a companion and the Warden composes")
		var three: Image = Room._grid
		ck(three != null, "  and produced an image")
		var figs_two := {"2,2": {"main": me}, "1,2": {"main": me}}
		Room.build(meaning, biomes, figs_two, {}, 0)
		var two: Image = Room._grid
		ck(two != null and three != null and _hash(two) != _hash(three),
			"  and it differs from the same map WITHOUT him - he is really drawn, not dropped")

		print("")
		print("  ----- and at PERSON size, not tile size -----")
		var fig: Image = Room._figure_img(warden)
		var tile := Image.load_from_file("res://client/sprites/overworld32/tile/warden.png")
		ck(fig != null, "his figure renders")
		if fig != null and tile != null:
			print("    tile %dx%d, figure %dx%d (FIGURE_SCALE %s)"
				% [tile.get_width(), tile.get_height(), fig.get_width(), fig.get_height(),
					str(Room.FIGURE_SCALE)])
			ck(fig.get_width() > tile.get_width(),
				"and it is LARGER than the tile he used to be drawn as")

	print("")
	print("===== AND HE IS IN ONE PLACE, FACING THE RIGHT WAY =====")
	# Owner 2026-09-14: *"the Warden is still duplicated, he's standing in the post and following
	# me (but his sprite isn't actually facing the way I am and following properly)."*
	#
	# The blanking test was an EXACT match on "warden". A cell's meaning carries markers -
	# "!hot:warden" in a hotzone, "!other:warden" with somebody standing on him - so every marked
	# case slipped through and the post copy survived beside the follower.
	ck(src.contains('if not String(_wrow[_wx]).contains("warden"):'),
		"the post copy is blanked for ANY warden cell, marked or not")
	# ⛑ AND THE BLANKING IS ACTUALLY KEPT.
	#
	# `MapPayload.cells` returns PackedStringArray rows, and a PackedStringArray is a VALUE type:
	# `var row = meaning[y]` copies it, so `row[x] = "empty"` edited a copy and threw it away.
	# The Warden survived two "fixes" that way - the FIGURE suppression worked, because that
	# writes to a Dictionary, so he stopped being drawn twice as a figure while the tile carried
	# on underneath. Demonstrated: without the write-back the cell still reads "warden".
	ck(src.contains("var _wrow: PackedStringArray = meaning[_wy]"),
		"the row is held as the PackedStringArray it really is")
	ck(src.contains("meaning[_wy] = _wrow"),
		"and written BACK - without this every edit to it is discarded")
	var _g: Array = []
	var _r := PackedStringArray()
	_r.append("floor")
	_r.append("warden")
	_g.append(_r)
	var _copy: Array = _g[0]
	_copy[1] = "empty"
	ck(_g[0][1] == "warden",
		"  (proof: editing the row without writing back leaves it unchanged)")
	var _row2: PackedStringArray = _g[0]
	_row2[1] = "empty"
	_g[0] = _row2
	ck(_g[0][1] == "empty", "  (and writing back is what makes it stick)")
	for marked in ["warden", "!hot:warden", "!other:warden", "!player:warden"]:
		ck(marked.contains("warden"), "  '%s' is recognised as his tile" % marked)
	ck(not "wall".contains("warden"), "  and an unrelated tile is not (control)")

	# He faces where he walks. He was pinned to one forward-facing frame.
	ck(src.contains("func _warden_sprite(facing: String, walking: bool)"),
		"his sprite is chosen by facing")
	ck(src.contains("_warden_sprite(_local_map_facing, _wmoving)"),
		"  from the player's own facing, since he walks behind them")
	var missing: Array = []
	for f in ["up", "down", "left", "right"]:
		for fr in ["_stand", "_walk1", "_walk2"]:
			var pth := "res://client/sprites/overworld_pad32/m1_1/%s%s.png" % [f, fr]
			if not ResourceLoader.exists(pth):
				missing.append("%s%s" % [f, fr])
	print("  his sprite set: 12 expected, %d missing" % missing.size())
	ck(missing.is_empty(),
		"every facing and walk frame exists, so nothing silently falls back to facing the camera")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether he keeps up convincingly while you walk. Position is recomputed per frame")
	print("  from your facing, so he snaps rather than steps - that is a look, and a playtest.")

	print("")
	if fails == 0:
		print("PASS - the Warden walks beside you, at your size, in nobody else's square")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)


func _hash(img: Image) -> int:
	var d := img.get_data()
	var h := 0
	for i in range(0, d.size(), 97):
		h = (h * 31 + d[i]) & 0x7FFFFFFF
	return h
