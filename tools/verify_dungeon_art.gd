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

	for k in DS.LOOT_SPRITE.keys():
		checked += 1
		var p3: String = DS.loot_path(String(k))
		if p3 == "" or not ResourceLoader.exists(p3):
			bad.append("loot %s -> '%s'" % [k, p3])

	# every cosmetic variant must resolve to an egg
	for v in DTables.EGG_VARIANTS:
		checked += 1
		var p4: String = ES.sprite_for(String(v.get("name", "")))
		if p4 == "":
			bad.append("egg variant %s -> ''" % v.get("name", ""))

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

	# --- and the rule that took THREE occurrences to learn ---
	#
	# Never `color=` a floor-backed sprite. Those images have the ground baked into them, so a
	# tint tag multiplies the floor too. It shipped on the player (brown cell), was fixed, then
	# repeated on the companion (discoloured tile), was fixed, then was still live on alert
	# monsters (red floor). Each time the code read as reasonable - "a tint so it reads as
	# yours", "a tint so alert is visible" - which is exactly why a comment was not enough.
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	var lines := src.split("
")
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

	print("[DUNGEONART] checked=%d broken=%d" % [checked, bad.size()])
	for b in bad:
		print("[DUNGEONART] BROKEN ", b)
	quit(0 if bad.is_empty() else 1)
