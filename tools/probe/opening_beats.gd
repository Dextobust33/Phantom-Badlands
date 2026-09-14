extends SceneTree
## The first two minutes: does each thing a new player is told point at something real?
##
## Owner 2026-09-14, after making a fresh account: *"After creating a character you get a Welcome
## popup that mentions the warden is waiting at the gate. 'What gate?' Also, it mentions Warden's
## Watch with how many steps it is ... is in your quest log (players don't know what or where a
## quest log is at this point). Once they hit Got it. They are just standing in a post and haven't
## been guided on what to do or how to do it."*
##
## Their standard for the whole opening: *"ask what do they need to know to do the next thing they
## should focus on?"* So every check here is the same question - does this sentence name something
## the player can see, and does it give exactly one next action?
const ServerScript = preload("res://server/server.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")
const PostDB = preload("res://shared/npc_post_database.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func csrc_has(needle: String) -> bool:
	return FileAccess.get_file_as_string("res://client/client.gd").contains(needle)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var i_w := src.find("Welcome, %s[/color]")
	var body := src.substr(i_w, 900) if i_w != -1 else ""

	print("===== THE WARDEN IS SOMEWHERE =====")
	# The whole "what gate?" problem: the welcome named a person who existed only as a party
	# member inside a dungeon. He has a tile now.
	ck(WorldSystemScript.TILE_RENDER.has("warden"), "'warden' is a real tile type")
	var wt: Dictionary = WorldSystemScript.TILE_RENDER.get("warden", {})
	ck(bool(wt.get("blocks_move", false)),
		"he blocks movement, so you BUMP into him - the same verb every other station uses")
	# The letter is only the fallback for a checkout without art. He is drawn as a FIGURE now
	# (see _overworld_display), at player scale - so the welcome no longer tells anyone to look
	# for a "W", which would have them hunting a letter that is not on the screen.
	ck(String(wt.get("char", "")) == "W", "he keeps a letter as the no-art fallback")
	ck(not body.contains("Find the [color=#9ACD32]W[/color]"),
		"but the welcome does NOT tell the player to look for a letter")
	ck(csrc_has("WARDEN_FIGURE_SPRITE"),
		"because he is composed as a figure at player scale, not as a tile")
	var art := "res://client/sprites/overworld32/tile/warden.png"
	var srcart := "res://client/sprites/overworld_pad32/m1_1/down_stand.png"
	ck(ResourceLoader.exists(art), "the file is there")
	# ...and it is a PERSON, which took three tries to check soundly:
	#
	#   `exists()`        passed for a full day while the map drew a green letter W. The bake
	#                     script writes his sprite, then a glyph-fallback pass overwrote it.
	#   colour count      a glyph is anti-aliased and drop-shadowed, so it carries 67 distinct
	#                     colours against the pixel-art sprite's 16. "Lots of colours" passes
	#                     for the WRONG one.
	#   load()            cannot see a re-bake at all: Godot serves .godot/imported, so injecting
	#                     the fault produced byte-identical numbers - the tell that a check is
	#                     not running. Image.load_from_file reads the PNG off disk.
	#
	# What separates them is the SILHOUETTE. Measured: the real tile overlaps the sprite it was
	# cut from by 83%, a "W" glyph by 39%.
	var a := Image.load_from_file(art)
	var b := Image.load_from_file(srcart)
	ck(a != null and b != null, "and it reads off disk, along with the sprite it was cut from")
	if a != null and b != null:
		var inter := 0
		var uni := 0
		for y in range(mini(a.get_height(), b.get_height())):
			for x in range(mini(a.get_width(), b.get_width())):
				var oa: bool = a.get_pixel(x, y).a > 0.3
				var ob: bool = b.get_pixel(x, y).a > 0.3
				if oa and ob:
					inter += 1
				if oa or ob:
					uni += 1
		var iou: float = 100.0 * inter / maxi(1, uni)
		print("    his tile overlaps that sprite's silhouette by %.0f%%" % iou)
		ck(iou >= 65.0, "and he is shaped like a PERSON, not like the letter W")

	var post_src := FileAccess.get_file_as_string("res://shared/npc_post_database.gd")
	ck(post_src.contains('stations.append("warden")'), "he is placed as a station")
	ck(post_src.contains("if is_crossroads:"),
		"at the STARTER post only - he is the start of the game, not a fixture of every post")

	print("")
	print("===== THE WELCOME NAMES ONLY THINGS THAT EXIST =====")
	ck(i_w != -1, "there is a welcome message")
	ck(not body.contains("at the gate"), "it no longer mentions a gate that does not exist")
	ck(not body.contains("quest log"),
		"nor a quest log, which a player has not seen and cannot find yet")
	ck(not body.contains("three steps"),
		"nor a step count, which is not something they need in order to act")
	ck(body.contains("NUMPAD"), "it names the numpad")
	ck(body.to_lower().contains("walk into"),
		"and gives exactly one next action: walk into the Warden")
	ck(body.contains("figure in the middle of the map"),
		"and first tells them which figure is theirs, which nothing did before")
	# Owner 2026-09-14: *"It doesn't highlight the warden or show you what he looks like."*
	ck(body.contains("[img=96x96]"), "and SHOWS the Warden rather than describing him")
	var portrait := "res://client/sprites/overworld_pad32/m1_1/down_stand.png"
	ck(src.contains('WARDEN_PORTRAIT := "%s"' % portrait),
		"  using the very sprite the map draws him with - one man, one face")
	ck(ResourceLoader.exists(portrait), "  which exists")
	var panel2 := FileAccess.get_file_as_string("res://client/tutorial_hint_panel.gd")
	ck(panel2.contains("TEXTURE_FILTER_NEAREST"),
		"  and the panel renders pixel art crisply rather than smearing it")

	print("")
	print("===== HE ANSWERS DIFFERENTLY DEPENDING ON WHERE YOU ARE =====")
	# A guide who says the same thing forever is a signpost. This one is a lookup on chain
	# progress, so the next action is always the CURRENT next action.
	ck(src.contains("func _handle_warden_interact"), "bumping him runs a handler")
	# The function BODY, not a fixed byte window. The first version took 2000 characters and
	# started failing the moment the stage-1 branch grew - which reported "he has no line for
	# stage 2" when he plainly did. A probe that breaks when the code it watches gets longer
	# is a probe that will be ignored.
	var i_h := src.find("func _handle_warden_interact")
	var i_end := src.find("
func ", i_h + 10)
	var h := src.substr(i_h, (i_end - i_h) if i_end > i_h else 4000)
	for stage in ["1:", "2:", "3:", "4:"]:
		ck(h.contains("\t\t" + stage), "  he has a line for stage %s" % stage.rstrip(":"))
	ck(h.contains("_:"),
		"and a fallback - walking up to someone and being ignored reads as a bug, not as silence")

	print("")
	print("----- and the stages line up with the chain that exists -----")
	var qsrc := FileAccess.get_file_as_string("res://shared/quest_database.gd")
	for qid in ["wardens_watch_1", "wardens_watch_2", "wardens_watch_3"]:
		ck(qsrc.contains('"%s": {' % qid), "  %s is defined" % qid)

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether the Warden is placed somewhere a new player will actually SEE from the")
	print("  spawn tile. Station placement is seeded and scattered; that is a live check.")

	print("")
	if fails == 0:
		print("PASS - every sentence in the opening names something the player can see")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)

