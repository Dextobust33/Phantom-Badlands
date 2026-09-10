extends SceneTree
## Does an entity standing on a scatter prop actually still show the prop?
##
## Calls the real compositor on real files and inspects the PIXELS that come back, because the
## failure this replaces was invisible to every check that only asked whether the files existed.
const _C = preload("res://client/dungeon_composite.gd")
const _T = preload("res://client/dungeon_tiles.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok: fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _prop_ink(img: Image, floor_col: Color) -> int:
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if not img.get_pixel(x, y).is_equal_approx(floor_col): n += 1
	return n


func _init() -> void:
	var prop := _T.PROP_DIR + "prop_00.png"
	var floor_col := Color(_T.FLOOR_COLOR)

	print("--- 1. a monster on a prop ---")
	var spr := "res://client/sprites/monster_floor32/wolf_1.png"
	var out := _C.over_prop(spr, prop)
	ck(out != spr, "composited path differs from the sprite (%s)" % out)
	var t_out: Texture2D = ResourceLoader.load(out)
	ck(t_out != null, "the fake res:// path loads the way a BBCode [img] tag would")
	var i_out: Image = t_out.get_image(); i_out.convert(Image.FORMAT_RGBA8)
	var i_spr: Image = (load(spr) as Texture2D).get_image(); i_spr.convert(Image.FORMAT_RGBA8)
	var i_prp: Image = (load(prop) as Texture2D).get_image(); i_prp.convert(Image.FORMAT_RGBA8)

	# The right unit is the prop's OWN INK, not the prop tile. A prop is a pebble or a tuft
	# standing on the same floor tile as everything else, so most of its 1024 pixels are plain
	# floor and are indistinguishable whether they composite or not. Counting those made the
	# first version of this assertion read 60/576 and call a working fix a failure — the
	# measurement was of the wrong quantity, which is the recurring shape in this repo.
	var ink_shown := 0      # prop ink that reaches the screen
	var ink_hidden := 0     # prop ink legitimately behind the sprite's body
	var kept_body := 0      # sprite pixels left alone
	var wrong := 0          # sprite pixels that were overwritten — the bug this must not have
	for y in range(i_out.get_height()):
		for x in range(i_out.get_width()):
			var o := i_out.get_pixel(x, y)
			var s := i_spr.get_pixel(x, y)
			var pr := i_prp.get_pixel(x, y)
			var was_floor: bool = s.is_equal_approx(floor_col)
			var is_ink: bool = not pr.is_equal_approx(floor_col)
			if not was_floor:
				if o.is_equal_approx(s): kept_body += 1
				else: wrong += 1
				if is_ink: ink_hidden += 1
			elif is_ink:
				if o.is_equal_approx(pr): ink_shown += 1
				else: wrong += 1
	print("      prop ink visible=%d  hidden behind the sprite=%d  sprite body kept=%d  clobbered=%d" % [
		ink_shown, ink_hidden, kept_body, wrong])
	ck(ink_shown > 0, "the prop's own ink reaches the screen instead of being erased")
	ck(ink_shown + ink_hidden == _prop_ink(i_prp, floor_col), "every prop pixel is accounted for")
	ck(kept_body > 100, "the wolf is still a wolf")
	ck(wrong == 0, "NOT ONE pixel of the sprite's own art was replaced")

	print("--- 2. floor-coloured pixels INSIDE the art are left alone ---")
	# A troll has 24 of them. Keying by colour alone would punch prop speckles through its middle;
	# the mask is border-connected precisely so it does not.
	var troll := "res://client/sprites/monster_floor32/troll_1.png"
	# prop_10, NOT the pebble used above. The pebble is plain floor at every one of the troll's
	# interior pixels, so writing it there changes nothing and the test passed with the flood fill
	# deliberately disabled — a detector that cannot fire. prop_10 has ink over all 24 of them,
	# measured, so a regression here is visible. (Injecting the fault and watching this go RED is
	# the only reason to believe any of the PASSes above.)
	var prop_dense := _T.PROP_DIR + "prop_10.png"
	var t2: Image = (ResourceLoader.load(_C.over_prop(troll, prop_dense)) as Texture2D).get_image()
	t2.convert(Image.FORMAT_RGBA8)
	var i_tr: Image = (load(troll) as Texture2D).get_image(); i_tr.convert(Image.FORMAT_RGBA8)
	# INDEPENDENT flood fill, deliberately not sharing a line of code with the compositor's.
	# The first version of this test called a pixel "interior" only if all four of its neighbours
	# were non-floor — and a troll's interior floor pixels sit in CLUSTERS, so it found zero
	# candidates and passed vacuously. Injecting the exact fault (key by colour, skip the flood)
	# and watching it still say PASS is what exposed it.
	var iw := i_tr.get_width()
	var ih := i_tr.get_height()
	var reach := {}
	var stk: Array[Vector2i] = []
	for x in range(iw):
		for y in [0, ih - 1]:
			if i_tr.get_pixel(x, y).is_equal_approx(floor_col): stk.append(Vector2i(x, y))
	for y in range(ih):
		for x in [0, iw - 1]:
			if i_tr.get_pixel(x, y).is_equal_approx(floor_col): stk.append(Vector2i(x, y))
	while not stk.is_empty():
		var c: Vector2i = stk.pop_back()
		if reach.has(c): continue
		reach[c] = true
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nn: Vector2i = c + d
			if nn.x < 0 or nn.x >= iw or nn.y < 0 or nn.y >= ih: continue
			if not reach.has(nn) and i_tr.get_pixel(nn.x, nn.y).is_equal_approx(floor_col):
				stk.append(nn)
	var interior_total := 0
	var interior_changed := 0
	for y in range(ih):
		for x in range(iw):
			var q := Vector2i(x, y)
			if not i_tr.get_pixel(x, y).is_equal_approx(floor_col) or reach.has(q): continue
			interior_total += 1
			if not t2.get_pixel(x, y).is_equal_approx(i_tr.get_pixel(x, y)): interior_changed += 1
	print("      enclosed floor pixels inside the troll: %d" % interior_total)
	ck(interior_total > 0, "the test has something to detect (a vacuous pass is not a pass)")
	ck(interior_changed == 0, "none of them were replaced by prop (%d changed)" % interior_changed)

	print("--- 3. the player, the companion and floor loot go through the same door ---")
	for s2 in ["res://client/sprites/overworld_floor32/1_1/down_stand.png",
			   "res://client/sprites/battler_floor32/1_1.png",
			   "res://client/sprites/egg_floor32/0624-egg-base.png",
			   "res://client/sprites/glyph_floor32/" ]:
		if s2.ends_with("/"): continue
		if not ResourceLoader.exists(s2):
			ck(false, "missing sample %s" % s2); continue
		ck(_C.over_prop(s2, prop) != s2, "composites %s" % s2.get_file())

	print("--- 4. no prop means no work, and results are cached ---")
	ck(_C.over_prop(spr, "") == spr, "empty prop returns the sprite unchanged")
	ck(_C.over_prop(spr, prop) == out, "second call returns the SAME cached texture path")

	print("--- 5. cost of a worst-case floor: every prop under every sprite in view ---")
	var t0 := Time.get_ticks_usec()
	var n := 0
	for p in range(_T.PROP_COUNT):
		for m in ["wolf_1", "troll_1", "skeleton_1", "orc_1"]:
			var sp := "res://client/sprites/monster_floor32/%s.png" % m
			if ResourceLoader.exists(sp):
				_C.over_prop(sp, _T.PROP_DIR + "prop_%02d.png" % p); n += 1
	var us := Time.get_ticks_usec() - t0
	print("      %d cold composites in %.1fms (%.2fms each); a redraw touches at most a few" % [
		n, us / 1000.0, us / 1000.0 / maxi(1, n)])
	var t1 := Time.get_ticks_usec()
	for i in range(2000): _C.over_prop(spr, prop)
	print("      2000 warm lookups in %.2fms" % ((Time.get_ticks_usec() - t1) / 1000.0))

	print("--- 6. it survives being drawn by a real RichTextLabel ---")
	var rtl := RichTextLabel.new(); rtl.bbcode_enabled = true; rtl.size = Vector2(600, 200)
	get_root().add_child(rtl)
	rtl.text = "[img=32x32]%s[/img]" % out
	await process_frame; await process_frame
	ck(rtl.get_content_height() >= 32, "RichTextLabel draws the composite at full tile height")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
