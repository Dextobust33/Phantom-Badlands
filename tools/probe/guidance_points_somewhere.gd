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
	print("===== HE DOES NOT FOLLOW A STRANGER, AND THE GATE HOLDS =====")
	# Owner 2026-09-14: *"The Warden is already following me before I've even talked to him."*
	# Stage 1 begins at CHARACTER CREATION, so keying the escort on the stage alone had him
	# trailing someone who had never met him.
	ck(src.contains("if not character.met_warden:
		return false"),
		"the escort requires having actually spoken to him")
	ck(src.contains("character.met_warden = true"), "  which the conversation sets")
	ck(src.contains("if not character.met_warden:") and src.contains('"[color=#9ACD32]Not Yet[/color]"'),
		"and the post will not let you leave before that conversation")
	ck(src.contains("not persistence.tutorials_enabled(_acct)"),
		"  unless the tutorials are switched off, as the owner specified")

	print("")
	print("===== THE MONSTER SAYS WHO IT HIT =====")
	# *"it says the wolf attacked twice but didn't mention who it attacked."*
	var cm := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(cm.contains('The %s hits you for %s damage!'),
		"the attack line is SECOND PERSON, so _party_thirdperson can name the target")
	ck(not cm.contains('The %s attacks and deals %s damage!'),
		"  and the pronoun-less version that named nobody is gone")

	print("")
	print("===== THE GUIDE CANNOT FALL =====")
	# *"it looks like the Warden's health isn't very high and he could possibly die."* He could:
	# his stats were assigned after initialize() and never recomputed, so his "generous" HP was
	# the base 129 - identical to the level-1 player he is protecting.
	ck(src.contains("g.calculate_derived_stats()"),
		"his attributes are actually applied now (they were assigned and discarded)")
	ck(cm.contains('if int(target_pid) in combat.get("npc_members", [])'),
		"and an NPC guide is held at 1 HP rather than dying mid-lesson")
	ck(cm.contains("_npc.current_hp = 1"), "  held, not healed")

	print("")
	print("===== HE POINTS AT ONE DOOR =====")
	# *"the highlight for the map should only highlight the door he's wanting you to leave out of."*
	ck(src.contains('"type": "mark_tile"'), "the server names the exact door tile")
	ck(src.contains("func _nearest_door("), "  which it locates rather than gesturing at a compass point")
	ck(csrc.contains('"mark_tile":'), "the client receives it")
	var room := FileAccess.get_file_as_string("res://client/overworld_room.gd")
	ck(room.contains("mark_cell: Vector2i"), "and the composer rings that ONE cell")
	ck(room.contains('key += "m%d,%d;" % [mark_cell.x, mark_cell.y]'),
		"  and the mark is in the cache key, so the map redraws when he starts pointing")

	print("")
	print("  ----- and it lands on the DOOR, not near it -----")
	# Owner 2026-09-14: *"The highlight on the map when I equip the sword is out of the post,
	# it's not actually highlighting a door at all."* The cell was computed as
	#   mid + (door - payload.x)
	# and the MAP PAYLOAD HAS NO x. So `payload.get("x", 0)` returned 0 and the ring landed
	# exactly the player's own distance-from-origin away from the door - at (2,0) that is two
	# cells, which put it through the wall.
	var wsrc := FileAccess.get_file_as_string("res://shared/world_system.gd")
	var i_ret := wsrc.find('return {"f": MapPayload.FORMAT')
	var ret := wsrc.substr(i_ret, 400) if i_ret != -1 else ""
	ck(i_ret != -1, "the map payload's shape was located")
	ck(not ret.contains('"x":'), "and it really carries NO x - so the old read could only be wrong")
	ck(csrc.contains("_last_map_center = Vector2i(int(message.get(\"x\", 0))"),
		"the centre is taken from the LOCATION message, which does carry it")
	ck(csrc.contains("mid + (_mark_tile.x - _last_map_center.x)"),
		"  and the cell is offset from that centre")
	ck(not csrc.contains('Vector2i(int(payload.get("x", 0)), int(payload.get("y", 0)))'),
		"  with the payload read gone entirely")
	# The arithmetic itself, executed.
	var mid_t := 11
	var centre := Vector2i(2, 0)
	var door := Vector2i(5, -3)
	var cell := Vector2i(mid_t + (door.x - centre.x), mid_t + (door.y - centre.y))
	print("    centre %v, door %v, grid mid %d -> cell %v" % [centre, door, mid_t, cell])
	ck(cell == Vector2i(14, 8), "  a door 3 east and 3 north of you lands 3 east and 3 north of centre")
	var wrong := Vector2i(mid_t + door.x, mid_t + door.y)
	ck(wrong != cell, "  and the old formula really gave a different cell (%v)" % wrong)

	print("")
	print("===== AND A WON FIGHT TEACHES RECOVERY =====")
	# *"He also needs to guide players on how to Rest and get their resources back as well as
	# let them know where and how monsters can be found and where is safe."*
	ck(src.contains('"recovery":'), "there is a lesson about resting and where danger is")
	ck(src.contains('_guide_teach(peer_id, "recovery")'), "  fired after the first kill")
	var i_r := src.find('"recovery":')
	var r_body := src.substr(i_r, 1800)
	ck(r_body.contains("Rest"), "  it names Rest")
	# Owner 2026-09-14: *"One of the dialogs he mentions resting takes food, this is true but
	# only in dungeons."* Confirmed in the handlers - handle_dungeon_rest eats a tier-1 herb and
	# the overworld handle_rest takes nothing. This lesson fires OUT IN THE WORLD, so it must
	# name the real cost there, which is time and the risk that comes with it.
	ck(r_body.contains("TIME"), "  says what resting really costs out here")
	ck(not r_body.contains("food"),
		"  and does NOT claim it costs food, which is true only inside a dungeon")
	ck(r_body.contains("Next:"), "  and ends by naming the next action, not leaving it to chat")
	ck(r_body.contains("Hunting"), "  and covers travel stances, as asked")
	ck(r_body.contains('ring = ["action_0", "travel_stance"]'),
		"  and rings the Rest button and the stance row")

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

