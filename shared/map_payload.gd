# map_payload.gd
# The overworld map as DATA rather than as a wall of BBCode.
#
# Phase 2.95 PHASE 1 (2026-09-11). The server used to build the whole map as a ~25 KB BBCode
# string and ship it in `location.description`. That string is ~96% repetition: a tile is
# `[color=#1A6B1A] T[/color]` - 23 bytes to say "tree", and the same 23 bytes again for the next
# tree. Here the distinct cells become a PALETTE and the map becomes one byte per cell.
#
# Two things this is NOT:
#   * it is not a change to what the map LOOKS like. `inflate()` rebuilds the server's string
#     byte for byte, and `generate_map_display` is now that inflate call, so the two cannot drift.
#   * it is not raw world data. The server still decides what a player may see - line of sight,
#     fog, which overlay wins on a tile - and sends the RESOLVED cell. A client that lies cannot
#     see through a wall, because the tile behind it was never sent.
#
# It is also the enabler for PHASE 2 (sprites): a palette entry can carry the tile's type beside
# its glyph, and the client can draw either from the same message.
# Deliberately NOT a class_name: global class registration lives in the .godot cache, and this
# project has been bitten by that cache being stale. A preload constant resolves from source.
extends RefCounted

## Bumped when the wire shape changes in a way an older reader would get wrong.
const FORMAT := 1


static func grid(rows: Array, row_sep: String = "\n", tail: String = "") -> Dictionary:
	"""One rectangular block of cells as a palette plus an index per cell.

	`rows` is an Array of PackedStringArray, each entry the exact BBCode for one cell."""
	var pal: Array = []
	var idx: Dictionary = {}
	var w := -1
	for r in rows:
		if w < 0:
			w = r.size()
		elif r.size() != w:
			# Ragged input would silently mis-decode, so say so rather than ship a scrambled map.
			push_error("MapPayload.grid: ragged rows (%d vs %d)" % [r.size(), w])
			return {"w": 0, "h": 0, "p": [], "c": "", "b": 1, "rs": row_sep, "t": tail}
		for cell in r:
			if not idx.has(cell):
				idx[cell] = pal.size()
				pal.append(cell)
	if w < 0:
		w = 0
	var wide: bool = pal.size() > 255
	var bytes := PackedByteArray()
	bytes.resize(rows.size() * w * (2 if wide else 1))
	var at := 0
	for r in rows:
		for cell in r:
			var i: int = idx[cell]
			if wide:
				bytes[at] = i & 0xFF
				bytes[at + 1] = (i >> 8) & 0xFF
				at += 2
			else:
				bytes[at] = i
				at += 1
	return {
		"w": w, "h": rows.size(), "p": pal,
		"c": Marshalls.raw_to_base64(bytes), "b": 2 if wide else 1,
		"rs": row_sep, "t": tail,
	}


static func text(s: String) -> Dictionary:
	"""A literal run - headers, the [center] wrapper, the minimap caption."""
	return {"s": s}


static func append_text(segs: Array, s: String) -> void:
	"""Append a literal, merging into the previous literal so the wire carries few segments."""
	if s == "":
		return
	if segs.size() > 0 and segs[-1] is Dictionary and segs[-1].has("s"):
		segs[-1]["s"] = String(segs[-1]["s"]) + s
	else:
		segs.append(text(s))


static func cells(grid: Dictionary) -> Array:
	"""One grid back as rows of values.

	`inflate` turns a grid into the display STRING. The sprite renderer needs the values
	themselves - what each cell is, which biome it stands on - so both go through here rather
	than each decoding the base64 in its own way."""
	var w: int = int(grid.get("w", 0))
	var h: int = int(grid.get("h", 0))
	var pal: Array = grid.get("p", [])
	var bpp: int = int(grid.get("b", 1))
	if w <= 0 or h <= 0 or pal.is_empty():
		return []
	var bytes: PackedByteArray = Marshalls.base64_to_raw(String(grid.get("c", "")))
	var rows: Array = []
	var at := 0
	for _y in range(h):
		var row: PackedStringArray = PackedStringArray()
		for _x in range(w):
			var i := 0
			if bpp == 2:
				if at + 1 < bytes.size():
					i = bytes[at] | (bytes[at + 1] << 8)
				at += 2
			else:
				if at < bytes.size():
					i = bytes[at]
				at += 1
			row.append(String(pal[i]) if i < pal.size() else "")
		rows.append(row)
	return rows


static func inflate(payload: Dictionary) -> String:
	"""Rebuild the display string. This is the ONLY definition of what a payload means, and the
	server renders through it too, so a client can never draw something the server would not."""
	var out := ""
	for seg in payload.get("segs", []):
		if not (seg is Dictionary):
			continue
		if seg.has("s"):
			out += String(seg["s"])
			continue
		var pal: Array = seg.get("p", [])
		var w: int = int(seg.get("w", 0))
		var h: int = int(seg.get("h", 0))
		var bpp: int = int(seg.get("b", 1))
		var row_sep: String = String(seg.get("rs", "\n"))
		var tail: String = String(seg.get("t", ""))
		if w <= 0 or h <= 0 or pal.is_empty():
			out += tail
			continue
		var bytes: PackedByteArray = Marshalls.base64_to_raw(String(seg.get("c", "")))
		var lines: PackedStringArray = PackedStringArray()
		var at := 0
		for _y in range(h):
			var parts: PackedStringArray = PackedStringArray()
			for _x in range(w):
				var i := 0
				if bpp == 2:
					if at + 1 < bytes.size():
						i = bytes[at] | (bytes[at + 1] << 8)
					at += 2
				else:
					if at < bytes.size():
						i = bytes[at]
					at += 1
				parts.append(String(pal[i]) if i < pal.size() else "")
			lines.append("".join(parts))
		out += row_sep.join(lines) + tail
	return out


static func wire_size(payload: Dictionary) -> int:
	"""Bytes this payload costs as JSON - what the comparison against the old string is about."""
	return JSON.stringify(payload).length()
