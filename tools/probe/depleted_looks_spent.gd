extends SceneTree
## A gathering node you have already taken must LOOK taken.
##
## Owner 2026-09-12: *"Gathering points don't seem to line up with where they are drawn on the map
## either and I'm not sure if they are clearing properly once I get them."* and then, asking the
## right question afterwards: *"Did we confirm that gathering points properly update their sprite
## after they are gathered rather than still looking like they are there?"*
##
## v0.9.774 answered the first one by READING THE SOURCE for `elif overlay == "depleted":`. That
## is the same kind of check that let a figure block that could never run ship twice. This one
## EXECUTES both halves of the chain:
##
##   1. the SERVER really emits a different meaning for a spent node - measured by depleting a
##      real node in a real world and diffing the meaning grid;
##   2. the CLIENT really draws it differently - measured by composing the cell both ways and
##      comparing pixels and brightness.
##
## It covers hotzones too, which is where the fault was still live: the text map drew a spent
## node in a hotzone as a red `!` and a fresh one as its own glyph in red, but BOTH were reported
## to the sprite renderer as `!hot:<tile>`.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const MapPayload = preload("res://shared/map_payload.gd")
const Room = preload("res://client/overworld_room.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _cell_stats(x: int, y: int) -> Dictionary:
	"""Mean brightness and a pixel signature for one composed cell."""
	var p: String = Room.cell_path(x, y)
	if p == "":
		return {}
	var tex := load(p) as Texture2D
	if tex == null:
		return {}
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var sum := 0.0
	var sig: Array = []
	for yy in range(im.get_height()):
		for xx in range(im.get_width()):
			var c := im.get_pixel(xx, yy)
			sum += c.r + c.g + c.b
			sig.append(c)
	return {"lum": sum / float(im.get_width() * im.get_height() * 3), "px": sig}


func _compose(meaning: String) -> Dictionary:
	"""One 1x1 view holding a single cell with this meaning."""
	var mrow := PackedStringArray([meaning])
	var brow := PackedStringArray(["plains"])
	Room.build([mrow], [brow], {})
	return _cell_stats(0, 0)


func _init() -> void:
	if not Room.available():
		print("[DEPLETED] SKIP - overworld sprites are licence-restricted and absent here")
		quit(2)
		return

	print("--- the CLIENT draws a spent node differently from a fresh one ---")
	for tile in ["ore_vein", "tree", "herb_patch", "berry_bush", "reeds", "mushroom_ring"]:
		if not ResourceLoader.exists("res://client/sprites/overworld32/tile/%s.png" % tile):
			continue
		var fresh := _compose(tile)
		var spent := _compose("!depleted:" + tile)
		if fresh.is_empty() or spent.is_empty():
			ck(false, "%s: a cell failed to compose at all" % tile)
			continue
		var diff := 0
		for i in range(mini(fresh["px"].size(), spent["px"].size())):
			if not fresh["px"][i].is_equal_approx(spent["px"][i]):
				diff += 1
		ck(diff > 200 and spent["lum"] < fresh["lum"] * 0.75,
			"%s: %d pixels differ, brightness %.3f -> %.3f once taken" % [
				tile, diff, fresh["lum"], spent["lum"]])

	# CONTROL. If the tile art were not drawing at all, every "fresh" cell would be bare ground
	# and every comparison above would still pass on the dimming alone. Two different tiles must
	# compose to two different pictures.
	var f_ore := _compose("ore_vein")
	var f_tree := _compose("tree")
	var cdiff := 0
	for i2 in range(mini(f_ore["px"].size(), f_tree["px"].size())):
		if not f_ore["px"][i2].is_equal_approx(f_tree["px"][i2]):
			cdiff += 1
	ck(cdiff > 100, "a fresh ore vein and a fresh tree are different pictures (%d pixels) - the tiles really draw" % cdiff)

	print("\n--- and inside a HOTZONE, where it was still identical ---")
	# The narrower case, and it was live until now: both states arrived as `!hot:<tile>`.
	var hot_fresh := _compose("!hot:ore_vein")
	var hot_spent := _compose("!hotdepleted:ore_vein")
	var hdiff := 0
	for i in range(mini(hot_fresh["px"].size(), hot_spent["px"].size())):
		if not hot_fresh["px"][i].is_equal_approx(hot_spent["px"][i]):
			hdiff += 1
	ck(hdiff > 200 and hot_spent["lum"] < hot_fresh["lum"] * 0.75,
		"a spent node in a hotzone: %d pixels differ, brightness %.3f -> %.3f" % [
			hdiff, hot_fresh["lum"], hot_spent["lum"]])
	# ...and it still carries the hotzone warning, which is the whole reason it cannot just go dark.
	var plain_spent := _compose("!depleted:ore_vein")
	var wdiff := 0
	for i in range(mini(plain_spent["px"].size(), hot_spent["px"].size())):
		if not plain_spent["px"][i].is_equal_approx(hot_spent["px"][i]):
			wdiff += 1
	ck(wdiff > 100, "and it still shows the hotzone warning (%d pixels unlike a plain spent node)" % wdiff)
	ck(Room._overlay_name("!hotdepleted:ore_vein") == "hotdepleted", "`!hotdepleted:` reads as hotdepleted")
	ck(Room._under_tile("!hotdepleted:ore_vein") == "ore_vein", "...standing on an ore vein, which still draws")

	print("\n--- the SERVER really says so, on a real node in a real world ---")
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	# Find a real gatherable in a real view rather than inventing one.
	var found := Vector2i(99999, 99999)
	var ftype := ""
	var centre := Vector2i(40, 40)
	for ring in range(0, 60):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				var t = cm.get_tile(centre.x + dx, centre.y + dy)
				if String(t.get("type", "")) in ws.GATHERABLE_TYPES:
					found = Vector2i(centre.x + dx, centre.y + dy)
					ftype = String(t.get("type", ""))
					break
			if found.x != 99999:
				break
		if found.x != 99999:
			break
	ck(found.x != 99999, "found a real %s at (%d, %d) to harvest" % [ftype, found.x, found.y])
	if found.x != 99999:
		var here := Vector2i(found.x, found.y)
		# Stand BESIDE it. Standing ON it makes the cell read `!player`, which is what the first
		# run of this probe measured - the node was never in the picture at all.
		var eye := Vector2i(here.x + 1, here.y)
		var before: Dictionary = ws.build_map_payload(eye.x, eye.y, 11, [], [], [], [], [], {}, [], false, [])
		var after: Dictionary = ws.build_map_payload(eye.x, eye.y, 11, [],
			[], ["%d,%d" % [here.x, here.y]], [], [], {}, [], false, [])
		var mb: Array = MapPayload.cells(before.get("meaning", {}))
		var ma: Array = MapPayload.cells(after.get("meaning", {}))
		# grid column = dx + radius, row = radius - dy
		var col: int = (here.x - eye.x) + 11
		var row: int = 11 - (here.y - eye.y)
		var cb := String(mb[row][col])
		var ca := String(ma[row][col])
		ck(cb.find(ftype) >= 0, "the cell beside the player really is the %s (%s)" % [ftype, cb])
		ck(cb != ca, "the cell's MEANING changes when it is depleted: %s -> %s" % [cb, ca])
		ck(ca.begins_with("!depleted:") or ca.begins_with("!hotdepleted:"),
			"...and says depleted (%s)" % ca)
		# And the two meanings really do compose to different pictures, which is the join between
		# the two halves above.
		var pb := _compose(cb)
		var pa := _compose(ca)
		var jd := 0
		for i in range(mini(pb["px"].size(), pa["px"].size())):
			if not pb["px"][i].is_equal_approx(pa["px"][i]):
				jd += 1
		ck(jd > 200, "and what the server now sends composes to a different picture (%d pixels)" % jd)

	print("\n[DEPLETED] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
