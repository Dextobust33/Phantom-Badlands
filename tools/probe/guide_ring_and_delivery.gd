extends SceneTree
## Does the gold ring land on the tile it MEANS, and does the Warden put you ON the dungeon?
##
## Owner 2026-09-15, standing at the end of the escorted walk on the LIVE server:
##
##   *"He got me close to the dungeon but now it shows a yellow ring on a path tile when I think
##   he is standing on the Dungeon we are supposed to go to. The new player will be lost and have
##   no idea that they need to step on the dungeon tile and hit R to go in."*
##
## Two separate faults, and the screenshot settled both. The status panel read "Warden Hollis
## leads you to: Wolf Den — 1 tiles southwest" and the ring was drawn ONE CELL NORTH of the
## player, on bare road.
##
## ⛑ FAULT ONE - THE MAP'S Y AXIS IS INVERTED AND THE RING DID NOT KNOW.
##
## `world_system._map_cells` renders `for dy in range(radius, -radius - 1, -1)`: row 0 is the
## NORTH edge and rows count southward. So the screen row of a world tile is
## `mid - (world_y - center_y)`. The client added it. Every marked tile was therefore drawn
## exactly as far north as it truly lay south - a perfect mirror about the player's own row,
## which is why it looked plausible and was wrong every single time.
##
## The Warden's own sprite offset carries this same negation with a comment recording that it
## shipped wrong once already ("goal 39 tiles SOUTHWEST and the Warden drawn due NORTH"). One
## fact, two copies, one of them fixed. See [[feedback-one-value-two-places]].
##
## ⛑ FAULT TWO - HE STOPPED ONE TILE SHORT, EVERY TIME.
##
## The walk finished at `absi(dx) <= 1 and absi(dy) <= 1`. That one tile cost three things at
## once: the contextual [R] slot only becomes the Dungeon button when you STAND on the entrance,
## the gold ring only clears when you stand on what it marks, and the player was left to guess
## which of eight surrounding squares was the hole.
##
## WHY THIS PROBE READS THE SOURCE FOR FAULT ONE. The conversion is four lines inside a 200-line
## map composer that needs a live payload, a built scene tree and a connected server to reach.
## Re-deriving the row order from `_map_cells` and checking the client agrees is the honest
## version of that check, and it is the part that was wrong. The DELIVERY half below is executed
## for real against a live server object.

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== THE MAP DRAWS NORTH AT THE TOP, AND COUNTS DOWN =====")
	var wsrc := FileAccess.get_file_as_string("res://shared/world_system.gd")
	# Ground truth: the render loop walks dy from +radius DOWN to -radius, emitting one row each.
	# That is the whole reason screen y must be negated against world y.
	ck(wsrc.contains("for dy in range(radius, -radius - 1, -1):"),
		"_map_cells walks dy from +radius downward - row 0 is NORTH")

	print("")
	print("===== SO THE RING MUST NEGATE Y =====")
	var csrc := FileAccess.get_file_as_string("res://client/client.gd")
	var i := csrc.find("mark_cell = Vector2i(mid + (_mark_tile.x - _last_map_center.x)")
	ck(i != -1, "the mark-to-cell conversion is where it was")
	var conv := csrc.substr(i, 200)
	ck(conv.contains("mid - (_mark_tile.y - _last_map_center.y)"),
		"and it SUBTRACTS the world-y delta (the ring was mirrored north/south)")
	ck(not conv.contains("mid + (_mark_tile.y - _last_map_center.y)"),
		"  the old adding form is gone")
	# The x half is NOT negated - world x and screen columns both increase eastward. Asserted so
	# that "fixing" this bug by negating both axes fails loudly instead of trading one mirror
	# for another.
	ck(conv.contains("mid + (_mark_tile.x - _last_map_center.x)"),
		"  and x is still ADDED - columns and world x both run east")

	print("")
	print("===== THE SAME NEGATION, IN THE WARDEN'S OWN OFFSET =====")
	# The second copy. If someone ever unifies these two into one helper this check is what
	# tells them the helper has to serve both.
	var j := csrc.find("var _gy := int(_escort_goal.get(\"y\", 0)) - _last_map_center.y")
	ck(j != -1, "his offset still derives a world-y delta")
	ck(csrc.substr(j, 900).contains("-signi(_gy)"),
		"and still negates it when placing him on screen")

	print("")
	print("===== HE WALKS YOU ONTO THE TILE, NOT BESIDE IT =====")
	var ssrc := FileAccess.get_file_as_string("res://server/server.gd")
	var t := ssrc.find("func _escort_walk_tick")
	var t_end := ssrc.find("\nfunc ", t + 10)
	var tick := ssrc.substr(t, (t_end - t) if t_end > t else 6000)
	# `not _home_walk and` since 2026-09-15: the tick also walks you HOME, whose goal is any post
	# interior rather than one tile. The dungeon arrival rule itself is unchanged.
	ck(tick.contains("int(ch.x) == gx and int(ch.y) == gy:"),
		"arrival is standing ON the entrance")
	ck(not tick.contains("if absi(dx) <= 1 and absi(dy) <= 1:"),
		"  the one-tile-short arrival is gone")
	# ...but a refused LAST step must not strand them beside it forever either.
	ck(tick.contains("if absi(gx - int(ch.x)) <= 1 and absi(gy - int(ch.y)) <= 1:"),
		"  and a wedge on the doorstep counts as delivered rather than as failure")

	print("")
	print("===== AND TELLS YOU HOW TO GET IN =====")
	var d := ssrc.find("func _escort_deliver")
	var d_end := ssrc.find("\nfunc ", d + 10)
	var deliver := ssrc.substr(d, (d_end - d) if d_end > d else 4000)
	ck(d != -1, "there is an arrival beat at all")
	ck(deliver.contains("[color=#9ACD32]R[/color]"), "it names the R key")
	ck(deliver.contains("\"action_4\""),
		"and RINGS the contextual slot, which at an entrance is the Dungeon button")
	# A hint that cannot be shown (tutorials off) must still say the one thing that is not
	# optional, or the player is simply standing on a hole.
	ck(deliver.contains("if not sent:"), "and it still speaks when tutorials are switched off")

	print("")
	print("===== A POST IS A ROOM: HE LEAVES BY THE DOOR =====")
	ck(ssrc.contains("func _escort_step_target"), "the walk has a waypoint step")
	var w := ssrc.find("func _escort_step_target")
	var w_end := ssrc.find("\nfunc ", w + 10)
	var way := ssrc.substr(w, (w_end - w) if w_end > w else 3000)
	ck(way.contains("_is_npc_post_interior(int(character.x), int(character.y))"),
		"  it asks whether the player is inside a post")
	ck(way.contains("_best_door_toward(character, gx, gy)"),
		"  and heads for a door when the goal is outside one")
	ck(tick.contains("_escort_step_target(peer_id, ch, st, gx, gy)"),
		"  and the tick actually uses it (an unused waypoint is a no-op that reads as a feature)")
	# The waypoint is CACHED in the walk state and chosen for the journey. Both halves matter:
	# re-electing the nearest door every step made him pace between two doorways (thirty real
	# steps, zero net displacement), and picking the nearest rather than the one on the way sends
	# him out of the far wall.
	ck(way.contains('st.has("door_x")') and way.contains('st["door_x"] = door.x'),
		"  the chosen door is remembered until they are through it")
	ck(way.contains("_best_door_toward(character, gx, gy)"),
		"  and it is the door on the WAY, not merely the nearest one")
	ck(ssrc.contains("func _best_door_toward"), "  which is scored here -> door -> goal")

	print("")
	print("----- and he never walks the player in a circle -----")
	# The refusal counter only catches a walk that cannot MOVE. Against a concave obstacle a
	# greedy stepper moves every tick and arrives nowhere, sailing straight past that net.
	ck(ssrc.contains("const ESCORT_DRIFT_TICKS"), "there is a drift window")
	ck(tick.contains("ESCORT_DRIFT_TICKS == 0") and tick.contains('st["stuck"] = 6'),
		"and going nowhere across it counts as stuck, so he gives up instead of pacing")
	ck(tick.contains("avoid_posts") and tick.contains("_is_npc_post_interior(int(off.x), int(off.y))"),
		"and once outside a post, stepping back into one sorts last")

	print("")
	print("===== ONE PANEL, NOT THREE =====")
	# The three were: the world lesson, the dungeon pointer, and the ask. Two of them told the
	# player to walk to a ringed tile while the third offered to carry them there.
	ck(not ssrc.contains("func _point_at_the_dungeon"),
		"the standalone dungeon-pointer panel is gone")
	ck(ssrc.contains("func _mark_the_dungeon"),
		"  replaced by a mark-only call - the ring is the useful half")
	var m := ssrc.find("func _mark_the_dungeon")
	var m_end := ssrc.find("\nfunc ", m + 10)
	var mark := ssrc.substr(m, (m_end - m) if m_end > m else 3000)
	ck(mark.contains("\"type\": \"mark_tile\""), "  it still rings the dungeon")
	ck(not mark.contains("_send_hint"), "  and raises no panel of its own")
	var a := ssrc.find("func _escort_ask_to_lead")
	var a_end := ssrc.find("\nfunc ", a + 10)
	var ask := ssrc.substr(a, (a_end - a) if a_end > a else 5000)
	ck(ask.count("_send_hint") == 1, "the remaining beat is exactly ONE panel")
	# Only the TEXT THE PLAYER SEES - the docstring quotes the owner's report verbatim, and a
	# check that cannot tell a quotation from an instruction would force the reason for a fix to
	# be deleted along with the fault.
	var hs := ask.find("_send_hint")
	var he := ask.find("if not sent:", hs)
	var shown := ask.substr(hs, (he - hs) if he > hs else 3000)
	ck(not shown.contains("ringed tile") and not shown.contains("Walk onto it"),
		"and it never tells them to walk to a ringed tile - he does the walking")
	ck(shown.contains("just move") or shown.contains("rather find your own way"),
		"  it does say they may take over, which is the one navigation line worth keeping")

	print("")
	print("===== NOT COVERED HERE =====")
	print("  Whether the merged panel READS well. That is a playtest, not an assertion.")
	print("  Whether the door waypoint clears every post SHAPE - posts vary, and the")
	print("  give-up path (hand the controls back after six refusals) is still the net.")

	print("")
	if fails == 0:
		print("PASS - the ring points at what it means and he delivers you to the door")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
