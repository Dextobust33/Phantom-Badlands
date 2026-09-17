extends SceneTree
## ⛑ IS THE GOLD MARK ON THE MAP WHEN THE SPRITES ARE NOT?
##
## Backlog, carried forward from the v0.9.790 work: *"Text-map fallback draws no gold ring or
## arrow (sprite toggle off, or licence art missing). Only the side-panel bearing helps there."*
##
## `_render_overworld_room` works out `mark_cell` and `mark_arrow` and then, when the sprite
## renderer declines, returned a bare `MapPayload.inflate(payload)` — which has never heard of
## either. So the Warden said *"it is ringed on your map"* and nothing was ringed. A guide that
## tells you to look for something that is not there is worse than one that says nothing.
##
## This drives the real renderer on a real payload, because the faults available here are all
## off-by-one: the wrong row (the map's y axis is inverted and has been got wrong twice), the
## MINIMAP marked instead of the map (a payload holds more than one grid), or the cell's own
## glyph destroyed by the marker (the marked tile is usually the dungeon `D` being pointed at).
##
## Run:
##   godot --headless --path . --script res://tools/probe/text_map_mark.gd

const MP := preload("res://shared/map_payload.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


## A 7x5 map grid plus a 3x3 "minimap", wrapped in header text — the shape of a real payload.
func _payload() -> Dictionary:
	var rows: Array = []
	for y in range(5):
		var row: PackedStringArray = PackedStringArray()
		for x in range(7):
			row.append("D" if (x == 5 and y == 1) else ".")
		rows.append(row)
	var mini: Array = []
	for _y in range(3):
		var r: PackedStringArray = PackedStringArray()
		for _x in range(3):
			r.append("_")
		mini.append(r)
	return {"segs": [MP.text("HEADER\n"), MP.grid(rows), MP.text("\nmini\n"), MP.grid(mini)]}


func _init() -> void:
	print("===== 1. NO MARK = BYTE-IDENTICAL TO THE PLAIN RENDERER =====")
	# The control. If the marked renderer differs when there is nothing to mark, every later
	# comparison is measuring two things at once.
	var p := _payload()
	var plain: String = MP.inflate(p)
	var none: String = MP.inflate_marked(p, Vector2i(-1, -1), Vector2i.ZERO, 7, 5)
	ck(plain == none, "an absent mark changes nothing (%d vs %d chars)" % [plain.length(), none.length()])
	var no_arrow: String = MP.inflate_marked(p, Vector2i(5, 1), Vector2i.ZERO, 99, 99)
	ck(plain == no_arrow, "and a grid whose size does not match is left alone")

	print("\n===== 2. THE ON-GRID RING KEEPS THE TILE'S OWN GLYPH =====")
	# ⛑ The marked tile is USUALLY the dungeon being pointed at. A marker that overwrote the
	# cell would hide the `D` - pointing at a thing by deleting it.
	var ring: String = MP.inflate_marked(p, Vector2i(5, 1), Vector2i.ZERO, 7, 5)
	print("           " + ring.replace("\n", " / "))
	ck(ring.contains("[bgcolor="), "the ring is drawn as a background")
	ck(ring.contains("]D[/bgcolor]"), "and the D underneath it survives")
	ck(ring.count("[bgcolor=") == 1, "exactly one cell is marked (%d)" % ring.count("[bgcolor="))
	# The ROW, which is the part that has been wrong twice in this codebase.
	var lines: PackedStringArray = ring.split("\n")
	var marked_row := -1
	for i in range(lines.size()):
		if "[bgcolor=" in lines[i]:
			marked_row = i
	# HEADER is line 0, so map row 1 is line 2.
	ck(marked_row == 2, "on the row asked for, not mirrored about it (line %d, want 2)" % marked_row)

	print("\n===== 3. THE MINIMAP IS NOT MARKED INSTEAD =====")
	# A payload holds more than one grid. Marking "the first grid" would put a gold cell in the
	# corner inset and nothing on the map.
	var mini_marked: String = MP.inflate_marked(p, Vector2i(1, 1), Vector2i.ZERO, 3, 3)
	var after_mini: String = mini_marked.substr(mini_marked.find("mini"))
	ck(after_mini.contains("[bgcolor="),
		"asked for the 3x3 grid, the 3x3 grid is what gets marked")
	var before_mini: String = mini_marked.substr(0, mini_marked.find("mini"))
	ck(not before_mini.contains("[bgcolor="), "  and the 7x5 map is untouched")

	print("\n===== 4. THE OFF-GRID ARROWHEAD POINTS THE RIGHT WAY =====")
	# Off-grid, the cell is clamped to four from the player and the DIRECTION is the whole
	# message - so here the marker replaces the cell rather than tinting it.
	var cases := {
		"north": [Vector2i(0, -3), "↑"],
		"south": [Vector2i(0, 3), "↓"],
		"west": [Vector2i(-3, 0), "←"],
		"east": [Vector2i(3, 0), "→"],
		"north-west": [Vector2i(-2, -2), "↖"],
		"south-east": [Vector2i(2, 2), "↘"],
	}
	for name in cases.keys():
		var arrow: Vector2i = cases[name][0]
		var want: String = String(cases[name][1])
		var got: String = MP.inflate_marked(p, Vector2i(3, 2), arrow, 7, 5)
		ck(got.contains("[b]%s[/b]" % want), "%-11s draws %s" % [name, want])

	print("\n===== NOT COVERED HERE =====")
	print("  Whether the gold reads clearly against every biome colour. That is a look,")
	print("  not an assertion - and the sprite map, which most players see, is unaffected.")

	print("\n===== VERDICT =====")
	print("  all checks PASS" if fails == 0 else "  %d check(s) FAIL" % fails)
	quit(1 if fails > 0 else 0)
