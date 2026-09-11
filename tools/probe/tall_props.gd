extends SceneTree
## Do two-cell props actually span two cells, and never dangle?
##
## The bug this replaces shipped once: a lamppost baked into ONE cell drew as half a lamppost.
## The failure mode of the fix is the mirror image - a base with its top drawn into a wall, or a
## top with no base under it - so both are checked on real generated floors.
const _T = preload("res://client/dungeon_tiles.gd")
const _DD = preload("res://shared/dungeon_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok: fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	print("--- 1. both halves exist for every named tall prop ---")
	for n in _T.TALL_NAMES:
		ck(_T.tall_half(n, "top") != "" and _T.tall_half(n, "bot") != "",
			"%s has a top and a bottom" % n)

	print("--- 2. on REAL floors: every base has somewhere for its top ---")
	var bases := 0
	var dangling := 0
	var in_wall := 0
	for dt in ["wolf_den", "kobold_tunnels"]:
		for f in range(1, 4):
			var res: Dictionary = _DD.generate_floor_grid(dt, f, false)
			var g: Array = res.get("grid", [])
			if g.is_empty():
				continue
			for y in range(g.size()):
				for x in range(g[y].size()):
					var b: String = _T.tall_prop_for(g, x, y)
					if b == "":
						continue
					bases += 1
					# A top half rising into the void is FINE - owner: "A lamppost that is
					# standing on a valid tile but expands up into the void isn't actually a
					# problem as its base is touching the ground." What is counted here is only
					# how often it happens, because it should be common at the edge of a space
					# and a count of zero would mean the rule never got relaxed.
					if y - 1 < 0 or int(g[y - 1][x]) == 1:
						in_wall += 1
					# and the base cell itself must be walkable
					if int(g[y][x]) == 1:
						dangling += 1
	print("      %d bases placed across 6 floors" % bases)
	ck(bases > 0, "tall props are actually placed (density is not zero)")
	print("      %d of them reach up into the void, which is allowed and expected" % in_wall)
	ck(dangling == 0, "no base stands in non-traversable space itself (%d)" % dangling)

	print("--- 2b. every prop's FOOTING is in the LOWER cell ---")
	# The owner's caveat: a top half in the void is fine BECAUSE the base is on the ground. That
	# only holds while the visible footing really is in the lower cell - an object whose foot sat
	# in the upper half would hover. Measured from the art, not assumed.
	for n2 in _T.TALL_NAMES:
		var bot: String = _T.tall_half(n2, "bot")
		if bot == "":
			continue
		var bi: Image = (load(bot) as Texture2D).get_image()
		bi.convert(Image.FORMAT_RGBA8)
		var lowest := -1
		for yy in range(bi.get_height()):
			for xx in range(bi.get_width()):
				if bi.get_pixel(xx, yy).a > 0.12:
					lowest = yy
					break
		ck(lowest > bi.get_height() / 2,
			"%s has ink in the lower part of its base cell (lowest row %d of %d)"
			% [n2, lowest, bi.get_height()])

	print("--- 3. rarer than scatter, or a corridor becomes a street ---")
	# props are 1 in 7; these must be far rarer
	ck(_T.TALL_CHANCE_IN >= 5 * _T.PROP_CHANCE_IN,
		"tall props are at least 5x rarer than scatter (1 in %d vs 1 in %d)"
		% [_T.TALL_CHANCE_IN, _T.PROP_CHANCE_IN])

	print("--- 4. stable: a lamp does not move as the player walks ---")
	var res2: Dictionary = _DD.generate_floor_grid("wolf_den", 1, false)
	var g2: Array = res2.get("grid", [])
	var first := []
	for y in range(g2.size()):
		for x in range(g2[y].size()):
			if _T.tall_prop_for(g2, x, y) != "":
				first.append("%d,%d" % [x, y])
	var second := []
	for y in range(g2.size()):
		for x in range(g2[y].size()):
			if _T.tall_prop_for(g2, x, y) != "":
				second.append("%d,%d" % [x, y])
	ck(first == second, "the same cells every time (position-hashed, not random)")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
