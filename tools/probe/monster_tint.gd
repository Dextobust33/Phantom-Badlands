extends SceneTree
## A monster's cosmetic VARIANT shows on its sprite - and never on the floor under it.
##
## Owner 2026-09-11: *"all monsters have variants that change what their ASCII art looks like
## (like lime ones, or two tone red and blue, etc.) How difficult would it be to put a tint or
## effect on their monster sprites?"* The data was always there; only the ASCII art used it.
##
## The failure this guards is specific and has reached the screen THREE times (player, companion,
## then the alert monster): these sprites carry the dungeon floor baked in, so tinting the IMAGE
## tints the ground. Every check below is about that line: the creature changes, the floor does not.
const DC := preload("res://client/dungeon_composite.gd")
const SPRITE := "res://client/sprites/monster_floor32/wolf_1.png"

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _img(path: String) -> Image:
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var i := tex.get_image()
	if i != null and i.is_compressed():
		i.decompress()
	if i != null:
		i.convert(Image.FORMAT_RGBA8)
	return i


func _init() -> void:
	if not ResourceLoader.exists(SPRITE):
		print("[TINT] SKIP - monster sprites are licence-restricted and absent here")
		quit(2)
		return
	var base := _img(SPRITE)
	var w := base.get_width()
	var bg := {}
	for i in DC._background_mask(SPRITE, base):
		bg[i] = true
	ck(bg.size() > 0, "the sprite's baked floor is keyable (%d floor pixels)" % bg.size())

	print("\n--- the creature is tinted, the floor is not ---")
	var green: String = DC.tinted(SPRITE, "#39FF14", "", "solid")
	ck(green != SPRITE, "a tinted sprite is a new image")
	var gi := _img(green)
	var floor_changed := 0
	var body_changed := 0
	for y in range(base.get_height()):
		for x in range(w):
			var same: bool = base.get_pixel(x, y).is_equal_approx(gi.get_pixel(x, y))
			if bg.has(y * w + x):
				if not same:
					floor_changed += 1
			elif not same:
				body_changed += 1
	ck(floor_changed == 0, "NOT ONE floor pixel moved (this is the bug that shipped three times)")
	ck(body_changed > 50, "the creature itself is recoloured (%d pixels)" % body_changed)

	print("\n--- two colours and eleven patterns ---")
	var seen := {}
	for pat in DC.TINT_PATTERNS:
		var p: String = DC.tinted(SPRITE, "#FF2020", "#2040FF", pat)
		var im := _img(p)
		var sig := hash(im.get_data())
		seen[sig] = String(seen.get(sig, "")) + pat + " "
	ck(seen.size() >= 9, "%d of %d patterns produce a distinct image" % [seen.size(), DC.TINT_PATTERNS.size()])
	var solid_one: String = DC.tinted(SPRITE, "#FF2020", "", "solid")
	var unknown: String = DC.tinted(SPRITE, "#FF2020", "", "not_a_pattern")
	ck(_img(unknown).get_data() == _img(solid_one).get_data(), "an unknown pattern falls back to solid")

	print("\n--- cheap and safe ---")
	ck(DC.tinted(SPRITE, "#39FF14", "", "solid") == green, "the same variant returns the cached image")
	ck(DC.tinted(SPRITE, "", "", "solid") == SPRITE, "no variant colour = the original sprite, untouched")
	ck(DC.tinted("", "#39FF14", "", "solid") == "", "an empty path is handed back")
	var t0 := Time.get_ticks_usec()
	for i in range(200):
		DC.tinted(SPRITE, "#39FF14", "", "solid")
	var per := float(Time.get_ticks_usec() - t0) / 200.0
	ck(per < 30.0, "a cached tint costs %.1fus, so a room of monsters redraws freely" % per)

	print("\n--- the call site ---")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cli.find("_DungeonComposite.tinted(_msprite,") >= 0, "the dungeon grid tints its monsters")
	var i0 := cli.find("var _mtinted: String")
	var i1 := cli.find("var _mimg: String = _DungeonComposite.over_prop(_mtinted, _prop)")
	ck(i0 > 0 and i1 > i0, "...before over_prop, so a monster on a prop still composites")
	# Owner: the tint belongs "everywhere pretty much". One helper, called from every sprite
	# surface a companion appears on - so a Verdant Wolf cannot be green in one place and grey
	# in another. (The overworld joins these when Phase 2.95 sprites it.)
	ck(cli.find("func _companion_tinted_sprite(") >= 0, "one helper maps a COMPANION's variant onto the tint")
	var dci := cli.find("func _dungeon_companion_img(")
	var dce := cli.find("
func ", dci + 10)
	ck(cli.substr(dci, dce - dci).find("_companion_tinted_sprite(") >= 0,
		"the companion following you underground wears its variant")
	var hri := cli.find("func _house_residents(")
	var hre := cli.find("
func ", hri + 10)
	ck(cli.substr(hri, hre - hri).find("_companion_tinted_sprite(") >= 0,
		"...and so does one sitting on its Sanctuary cushion")
	ck(cli.find("# NO TINT. Owner:") < 0, "the old 'never tint these' note is gone, not left contradicting the code")

	# A sheet to LOOK at: a probe can say "different", only eyes can say "right".
	var sheet := Image.create(w * 6, base.get_height() * 2, false, Image.FORMAT_RGBA8)
	var demo := [["#39FF14", "", "solid"], ["#FF2020", "#2040FF", "split_v"], ["#FFD700", "#FF00FF", "gradient_down"],
		["#00FFFF", "#FFFFFF", "striped"], ["#FF8800", "#220044", "radial"], ["#AA00FF", "#00FF88", "checker"]]
	for i in range(demo.size()):
		sheet.blit_rect(base, Rect2i(Vector2i.ZERO, base.get_size()), Vector2i(i * w, 0))
		var ti := _img(DC.tinted(SPRITE, demo[i][0], demo[i][1], demo[i][2]))
		sheet.blit_rect(ti, Rect2i(Vector2i.ZERO, ti.get_size()), Vector2i(i * w, base.get_height()))
	sheet.resize(sheet.get_width() * 4, sheet.get_height() * 4, Image.INTERPOLATE_NEAREST)
	sheet.save_png("res://claude_screenshots/monster_tints.png")
	print("  wrote claude_screenshots/monster_tints.png (top row plain, bottom row tinted)")

	print("\n[TINT] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
