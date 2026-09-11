extends SceneTree

## Does every dungeon-art lookup RESOLVE to a file that exists?
##
## This exists because prose did not work. "Verify the thing that RUNS, not the ingredients" was
## written into a commit message and then violated on the next piece of work in the same session:
## the monster table shipped to production with every value carrying a `.png` that `monster_path`
## appended again, so all 53 lookups returned `skeleton.png.png` and every monster in every
## dungeon fell back to a letter. The files existed. The table had 53 rows. Both were checked.
## The FUNCTION was never called once.
##
## So the lesson is a script now. It calls each resolver on every key it claims to serve and
## fails the release if any of them returns something that cannot be loaded.

func _init() -> void:
	var DS = load("res://client/dungeon_sprites.gd")
	var DT = load("res://client/dungeon_tiles.gd")
	var ES = load("res://client/egg_sprites.gd")
	var DTables = load("res://shared/drop_tables.gd")
	var bad: Array = []
	var warn: Array = []
	var checked := 0

	# EVERY walk frame, not just one. Monsters animate now, and checking a single frame would
	# pass while two thirds of the art was missing - the same shape as checking that files exist
	# while never calling the resolver.
	for k in DS.MONSTER_SPRITE.keys():
		for fr in range(DS.MONSTER_FRAMES):
			checked += 1
			var p: String = DS.monster_path(String(k), fr)
			if p == "" or not ResourceLoader.exists(p):
				bad.append("monster %s frame %d -> '%s'" % [k, fr, p])

	for k in DS.GLYPH_TILE.keys():
		checked += 1
		var parts := String(k).split("|")
		if parts.size() != 2:
			bad.append("glyph key malformed: %s" % k)
			continue
		var p2: String = DS.glyph_path(parts[0], parts[1])
		if p2 == "" or not ResourceLoader.exists(p2):
			bad.append("glyph %s -> '%s'" % [k, p2])

	# landmark tiles, every frame
	for k in DS.TILE_FRAMES.keys():
		for fr in range(int(DS.TILE_FRAMES[k])):
			checked += 1
			var tp: String = DS.tile_path(String(k), fr)
			if tp == "" or not ResourceLoader.exists(tp):
				bad.append("tile %s frame %d -> '%s'" % [k, fr, tp])

	for k in DS.LOOT_SPRITE.keys():
		checked += 1
		var p3: String = DS.loot_path(String(k))
		if p3 == "" or not ResourceLoader.exists(p3):
			bad.append("loot %s -> '%s'" % [k, p3])

	# every cosmetic variant must resolve to an egg — and to a DISTINCT, textured one
	var egg_art_seen := {}
	for v in DTables.EGG_VARIANTS:
		checked += 1
		var p4: String = ES.sprite_for(String(v.get("name", "")))
		if p4 == "":
			bad.append("egg variant %s -> ''" % v.get("name", ""))
			continue
		# RESOLVING IS NOT ENOUGH - this check used to stop at the line above, and five variants
		# (Ivory, Arctic, Marked, Halo, Blessed) all pointed at `0624-egg-base.png`, the pack's
		# UNTEXTURED template. It resolved, it loaded, it drew - as a flat white blob, identical
		# for all five, which is what the owner saw on a dungeon floor: "Two of the eggs in that
		# last screenshot look plain white."
		#
		# Two properties are asserted instead, both measured from the image itself:
		#   1. it is SHADED - a real egg has 99-120 distinct body colours, the template has 2
		#   2. it is UNIQUE - two variants sharing art cannot be told apart, which defeats the
		#      whole point of a variant having its own look
		var tex: Texture2D = load(p4)
		if tex == null:
			bad.append("egg variant %s -> %s did not load" % [v.get("name", ""), p4])
			continue
		var img: Image = tex.get_image()
		var seen := {}
		for py in range(img.get_height()):
			for px in range(img.get_width()):
				var c: Color = img.get_pixel(px, py)
				if c.a < 0.8:
					continue
				seen[c.to_rgba32()] = true
		if seen.size() < 20:
			bad.append("egg variant %s -> %s is FLAT (%d colours) - an untextured template"
				% [v.get("name", ""), p4.get_file(), seen.size()])
		# Sharing is a WARNING, not a failure. There are 117 variants and 93 distinct egg
		# sprites, so some reuse is a content limitation rather than a bug, and blocking every
		# release on 20 known pairs would just train people to ignore the gate. A FLAT sprite
		# above stays a hard failure: that one is never intentional.
		if egg_art_seen.has(p4):
			warn.append("egg variant %s shares art with %s (%s)"
				% [v.get("name", ""), egg_art_seen[p4], p4.get_file()])
		else:
			egg_art_seen[p4] = String(v.get("name", ""))

	# the tiles the floor itself is made of
	for f in [DT.floor_img(), DT.rock_img(), DT.blank_img()]:
		checked += 1
		if String(f).find("res://") < 0:
			bad.append("tile builder produced no resource: %s" % f)
	for i in range(DT.PROP_COUNT):
		checked += 1
		var pp: String = String(DT.PROP_DIR) + ("prop_%02d.png" % i)
		if not ResourceLoader.exists(pp):
			bad.append("prop %s missing" % pp)

	# --- can every floor-loot KIND the server can drop actually be drawn? ---
	#
	# 2026-09-10. `consumable` had no sprite for as long as the sprite table has existed, so a
	# Floor Skip Charm on the dungeon floor rendered as a bare glyph beside five sprited kinds.
	# Nothing caught it because every check asked "do the files in the table load", and the table
	# was the thing that was incomplete. Owner found it by walking past one.
	#
	# So this asks the other direction: for every kind the SERVER can put on the floor, does the
	# client have art? The list is read out of server.gd rather than copied here, because a copy
	# is the "one value, two places" shape that causes most of the wrong-text bugs in this repo -
	# a new kind added to the server must show up here without anyone remembering to update it.
	var srv := FileAccess.get_file_as_string("res://server/server.gd")
	var kind_re := RegEx.new()
	kind_re.compile('"kind": "([a-z_]+)", "char"')
	var kinds := {}
	for m in kind_re.search_all(srv):
		kinds[m.get_string(1)] = true
	if kinds.is_empty():
		bad.append("floor-loot kind scan matched NOTHING - the pattern has drifted from server.gd")
	for k in kinds:
		checked += 1
		# eggs are drawn from the EGG sprite set by variant, not from the loot table
		if k == "egg":
			continue
		var lp: String = DS.loot_path(k)
		if lp == "":
			bad.append("floor loot kind '%s' has no sprite - it will draw as a bare glyph" % k)
		elif not ResourceLoader.exists(lp):
			bad.append("floor loot kind '%s' -> %s does not load" % [k, lp])

	# --- and the rule that took THREE occurrences to learn ---
	#
	# Never `color=` a floor-backed sprite. Those images have the ground baked into them, so a
	# tint tag multiplies the floor too. It shipped on the player (brown cell), was fixed, then
	# repeated on the companion (discoloured tile), was fixed, then was still live on alert
	# monsters (red floor). Each time the code read as reasonable - "a tint so it reads as
	# yours", "a tint so alert is visible" - which is exactly why a comment was not enough.
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	# The delimiter is the ESCAPE "\n", not a literal newline typed inside the quotes. It was a
	# literal one, which GDScript accepted, and the split then returned the WHOLE FILE as a
	# single element - so `lines[0]` held every `color=`, every `[img` and every marker in
	# client.gd at once, and the scan reported exactly one BROKEN at line 1 forever, whatever
	# the code actually said. `verify_release_build.sh` fails on this script's exit code, so
	# the dungeon-art gate had been RED on master and would have blocked the next release for
	# a fault that does not exist. An always-on detector is as useless as one that never
	# fires and much harder to notice, since it looks like a finding.
	var lines := src.split("\n")
	assert(lines.size() > 100, "client.gd did not split into lines - the scan below is vacuous")
	var MARKERS := ["_floor32", "monster_path", "prop_for", "floor_img", "TILE_PX"]
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.find("color=") < 0 or line.find("[img") < 0:
			continue
		# The sprite path is usually on the FOLLOWING line (the format-args list), so a
		# same-line test misses it - the first version of this check did exactly that and
		# failed to fire when the real bug was re-injected. Look at a small window.
		var window := ""
		for j in range(i, mini(i + 3, lines.size())):
			window += String(lines[j])
		for m in MARKERS:
			if window.find(m) >= 0:
				checked += 1
				bad.append("a floor-backed sprite is tinted at client.gd:%d - %s"
					% [i + 1, line.strip_edges()])
				break

	# --- BAKED GLYPHS MUST NOT BE THE FONT'S MISSING-GLYPH BOX -----------------------------
	# 2026-09-10. The owner reported "Elite monsters don't have a sprite", and the marker turned
	# out to be a magenta [?] box - the font's .notdef glyph, rendered by the OFFLINE baker for a
	# character the font cannot draw, and then baked onto the floor tile as if it were art. Six
	# characters were affected: the Elite Den and Rest Room markers plus four loot kinds.
	#
	# The test needs no reference image and no font: tofu makes every unsupported character draw
	# the SAME shape, so two different characters sharing one ink silhouette is the fault itself.
	# A real glyph collision is not possible - these are distinct letters and symbols.
	var shape_owner := {}
	var gdir := DirAccess.open("res://client/sprites/glyph_floor32")
	if gdir != null:
		var seen_char := {}
		gdir.list_dir_begin()
		var fn := gdir.get_next()
		while fn != "":
			if fn.ends_with(".png") and fn.begins_with("u"):
				var cp := fn.substr(1, fn.find("_") - 1)
				if not seen_char.has(cp):          # one tile per character is enough
					seen_char[cp] = true
					var tex: Texture2D = load("res://client/sprites/glyph_floor32/" + fn)
					if tex != null:
						var img := tex.get_image()
						if img != null:
							if img.is_compressed():
								img.decompress()
							# the INK mask: which pixels differ from the flat floor, as a string
							var base := img.get_pixel(0, 0)
							var mask := ""
							for y in range(img.get_height()):
								for x in range(img.get_width()):
									var _c := img.get_pixel(x, y)
									var _d: float = absf(_c.r - base.r) + absf(_c.g - base.g) + absf(_c.b - base.b)
									mask += "1" if _d > 0.05 else "0"
							checked += 1
							if shape_owner.has(mask):
								bad.append("baked glyph U+%s is pixel-identical to U+%s - both are the font's missing-glyph box, not art (re-bake with a font that has them)"
									% [cp.to_upper(), String(shape_owner[mask]).to_upper()])
							else:
								shape_owner[mask] = cp
			fn = gdir.get_next()
		gdir.list_dir_end()

	print("[DUNGEONART] checked=%d broken=%d warnings=%d" % [checked, bad.size(), warn.size()])
	for b in bad:
		print("[DUNGEONART] BROKEN ", b)
	for w in warn:
		print("[DUNGEONART] warn ", w)
	quit(0 if bad.is_empty() else 1)
