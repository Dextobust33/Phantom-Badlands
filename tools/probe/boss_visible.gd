extends SceneTree
## A boss must be distinguishable from an ordinary monster of the same type.
##
## Owner 2026-09-10: "I couldn't locate a boss and when I grabbed the chest it gave me the dungeon
## loot and teleported me out." They had already killed it. The boss carries display_char "B" and
## a red colour, and the renderer sets both — but only the GLYPH fallback read them, so once every
## dungeon monster had a sprite the marker became dead code.
const _DC := preload("res://client/dungeon_composite.gd")
const _DS := preload("res://client/dungeon_sprites.gd")
const CLIENT := "res://client/client.gd"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _px(path: String) -> Image:
	var t: Texture2D = load(path)
	var i := t.get_image()
	if i.is_compressed():
		i.decompress()
	return i


func _init() -> void:
	print("--- the ring actually changes the image, and only at the edge ---")
	var spr: String = _DS.monster_path("Goblin", 0)
	ck(spr != "" and ResourceLoader.exists(spr), "a Goblin sprite exists to test with (%s)" % spr)
	if spr == "":
		quit(1)
		return

	var plain := _px(spr)
	var ringed_path: String = _DC.ringed(spr, "#FF0000")
	ck(ringed_path != spr, "ringed() returns a DIFFERENT resource, not the input unchanged")
	var ringed := _px(ringed_path)

	var edge_changed := 0
	var interior_changed := 0
	var w := plain.get_width()
	var h := plain.get_height()
	for y in range(h):
		for x in range(w):
			if plain.get_pixel(x, y) != ringed.get_pixel(x, y):
				if x == 0 or y == 0 or x == w - 1 or y == h - 1:
					edge_changed += 1
				else:
					interior_changed += 1
	print("      %d edge px changed, %d interior px changed" % [edge_changed, interior_changed])
	ck(edge_changed >= (w + h) * 2 - 8, "the whole border is painted, not a few corners")
	ck(interior_changed == 0, "the monster's own art is untouched")

	# It must NOT be mistakable for the loot brackets, which are corner arms only.
	var brack := _px(_DC.bordered(spr, "#FF0000"))
	var brack_edge := 0
	for x in range(w):
		if plain.get_pixel(x, 0) != brack.get_pixel(x, 0):
			brack_edge += 1
	var ring_top := 0
	for x in range(w):
		if plain.get_pixel(x, 0) != ringed.get_pixel(x, 0):
			ring_top += 1
	print("      top edge: ring paints %d px, loot brackets paint %d px" % [ring_top, brack_edge])
	ck(ring_top > brack_edge, "a boss ring is visibly NOT the loot bracket (solid vs corners)")

	# A fabled boss is gold, not red — the server's colour must survive.
	var gold := _px(_DC.ringed(spr, "#FFD700"))
	ck(gold.get_pixel(0, 0) != ringed.get_pixel(0, 0),
		"a fabled boss (#FFD700) rings differently from an ordinary one (#FF0000)")

	print("\n--- the renderer asks for it on the SPRITE path, not just the glyph fallback ---")
	var src := FileAccess.get_file_as_string(CLIENT)
	var lines := src.split("\n")
	var a := -1
	var b := -1
	for i in range(lines.size()):
		if lines[i].begins_with("func _render_dungeon_grid"):
			a = i
		elif a >= 0 and lines[i].begins_with("func ") and i > a:
			b = i
			break
	var ring_line := -1
	var sprite_emit := -1
	var glyph_emit := -1
	for i in range(a, b):
		var t: String = lines[i].strip_edges()
		if t.begins_with("_mimg = _DungeonComposite.ringed("):
			ring_line = i
		if t.find("_murl, _DungeonTiles.TILE_PX") >= 0:
			sprite_emit = i
		if t.begins_with("line += _dungeon_glyph_cell(mchar, mcolor"):
			glyph_emit = i
	ck(ring_line > 0, "the ring is applied inside the grid renderer")
	ck(ring_line > 0 and sprite_emit > ring_line,
		"...BEFORE the sprite is emitted, so the sprite path is the one that gets it")
	ck(glyph_emit > 0 and ring_line < glyph_emit,
		"...and it is not hiding in the glyph fallback, which is where the old marker died")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
