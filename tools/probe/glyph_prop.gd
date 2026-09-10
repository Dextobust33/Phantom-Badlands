extends SceneTree
const _C = preload("res://client/dungeon_composite.gd")
const _T = preload("res://client/dungeon_tiles.gd")
const _DS = preload("res://client/dungeon_sprites.gd")
func _init() -> void:
	var prop := _T.PROP_DIR + "prop_07.png"
	print("1. does over_prop work on a BAKED GLYPH tile at all?")
	for pair in [["w", "#A335EE"], ["×", "#FF4444"], ["$", "#FFD700"], ["?", "#00FF00"]]:
		var g: String = _DS.glyph_path(String(pair[0]), String(pair[1]))
		if g == "" or not ResourceLoader.exists(g):
			print("   %s  NO BAKED TILE (%s)" % [pair[0], g]); continue
		var c: String = _C.over_prop(g, prop)
		print("   %s  baked=%s  composited=%s" % [pair[0], g.get_file(), "YES" if c != g else "NO"])

	print("\n2. which TILE TYPES can carry a prop today?")
	# `_dungeon_tile_cell` only scatters props on 0 (EMPTY) and 7 (CLEARED). Every theme tile —
	# the webbed / poison / mud / moss floors that make up a large share of a themed floor — is a
	# different enum value, so it never gets one.
	var walkable_theme := 0
	for t in range(10, 50):
		walkable_theme += 1
	print("   plain floor: 0, 7            -> props YES")
	print("   theme floors: 10..49 (%d)     -> props NO  <-- these are walkable floor too" % walkable_theme)
	print("   landmarks (stairs/chest/boss) -> props NO  (correct: they are objects, not floor)")
	quit()
