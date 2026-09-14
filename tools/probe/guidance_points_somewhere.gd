extends SceneTree
## When the game NAMES a button, does anything actually point at it - and is the lesson on time?
##
## Owner 2026-09-14, testing locally: *"Movement still showing after creating a character instead
## of in the Sanctuary like we agreed and implemented. 341658 shows the W that is on the map. There
## is nothing to draw the players attention to any of the buttons or things he is referencing. We
## should be drawing a border around them or having them flash so the player can see them. I
## pressed got it on his dialogue and now I'm just standing here."*
##
## Four separate failures, one shape: the opening kept naming things without pointing at them.

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://server/server.gd")
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")

	print("===== THE MOVEMENT LESSON IS IN THE SANCTUARY, NOT AFTER CREATION =====")
	# Every account passes the Sanctuary before it can make a character, so that is the only
	# place a movement lesson is guaranteed to arrive BEFORE the player has to move.
	ck(src.contains('send_to_peer(peer_id, {"type": "show_movement_help"})'),
		"the Sanctuary intro asks for the keypad diagram")
	var i_intro := src.find("func _maybe_send_sanctuary_intro")
	var i_end := src.find("\nfunc ", i_intro + 10)
	var intro := src.substr(i_intro, (i_end - i_intro) if i_end > i_intro else 3000)
	ck(intro.contains("show_movement_help"), "  from inside that function, not somewhere else")
	ck(intro.contains("mark_account_flag"), "  once per ACCOUNT, as the owner asked")
	ck(csrc.contains('"show_movement_help":'), "and the client answers it")

	# The regression itself: the diagram used to open on character ENTRY, which is what put it
	# after creation. Nothing may queue it there any more.
	var i_entry := csrc.find("if show_numpad_popup")
	ck(i_entry != -1, "the character-entry block still exists")
	var entry := csrc.substr(i_entry, 600)
	ck(not entry.contains("_pending_numpad_open"),
		"and it no longer opens the movement popup - that is what fired after creation")
	ck(entry.contains("_pending_guided_intro"),
		"  the guided tour DOES still belong there (it points at the action bar and map, "
		+ "which do not exist until a character is in the world)")

	print("")
	print("===== THE WARDEN'S SPRITE IS A PERSON =====")
	# `exists()` passed for a full day while the map drew a letter: the bake script wrote his
	# sprite, then a glyph-fallback pass overwrote it with a picture of "W".
	var art := "res://client/sprites/overworld32/tile/warden.png"
	ck(ResourceLoader.exists(art), "the file is there")
	var tex = load(art)
	var img: Image = (tex as Texture2D).get_image() if tex is Texture2D else null
	ck(img != null, "and it loads")
	if img != null:
		var seen := {}
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.03:
					seen[Vector3i(int(c.r * 255), int(c.g * 255), int(c.b * 255))] = true
		print("    %d distinct opaque colours" % seen.size())
		ck(seen.size() >= 4, "and it is ART - a glyph carries one colour, a person carries many")

	# And the cause, so it cannot come back the next time someone hand-bakes a tile.
	var bake := FileAccess.get_file_as_string("res://tools/bake_overworld_tiles.py")
	ck(bake.contains("have_art = baked_tiles"),
		"the glyph pass skips what was actually WRITTEN, not what happens to be in CUTS")
	ck(bake.contains("baked_tiles.add('warden')"), "  and the Warden puts himself in that set")

	print("")
	print("===== A NAMED BUTTON GETS RINGED =====")
	ck(FileAccess.file_exists("res://client/ui_spotlight.gd"), "there is a spotlight overlay")
	ck(csrc.contains("func _resolve_ui_target"), "the client can turn a name into a Control")
	ck(csrc.contains("func _on_tutorial_hint_dismissed"),
		"and rings it when the popup CLOSES - a ring underneath the popup teaches nothing")
	ck(csrc.contains('btn.name = shortcut[1]'),
		"shortcut buttons are named for their action id, so they can be pointed at")

	# Every lesson that names a control must carry the control.
	print("")
	print("----- every lesson that names a button also points at one -----")
	var named := 0
	var pointed := 0
	for fn in ["_guide_teach", "_handle_warden_interact", "_maybe_warden_next_step"]:
		var i_f := src.find("func %s" % fn)
		ck(i_f != -1, "  %s exists" % fn)
		if i_f == -1:
			continue
		var i_e := src.find("\nfunc ", i_f + 10)
		var body := src.substr(i_f, (i_e - i_f) if i_e > i_f else 4000)
		var names_ui: bool = body.contains("Inventory[/color]") or body.contains("Inv[/color]") \
			or body.contains("on the map")
		var points: bool = body.contains("inventory_shortcut") or body.contains("action_1") \
			or body.contains('"map"') or body.contains("action_bar")
		if names_ui:
			named += 1
			if points:
				pointed += 1
		print("    %s: names UI=%s, points at it=%s" % [fn, names_ui, points])
	ck(named > 0, "  at least one lesson names a control (or this check is vacuous)")
	ck(pointed == named, "  and every one of them (%d/%d) rings it" % [pointed, named])

	print("")
	print("===== AND THE LESSON ENDS BY NAMING THE NEXT ACTION =====")
	ck(src.contains("func _maybe_warden_next_step"),
		"putting the blade on triggers the next instruction")
	ck(src.contains("_maybe_warden_next_step(peer_id, character)"), "  wired into the equip path")
	ck(src.contains("func _nearest_door_dir"),
		"and it says WHICH WAY the door is - the post is walled, and nothing said so")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  Whether a pulsing gold ring is actually noticeable on a 4K screen, and whether the")
	print("  Warden reads as a person at 32px. Both are looks, and looks are a playtest.")

	print("")
	if fails == 0:
		print("PASS - every named thing is pointed at, and every beat names the next one")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
