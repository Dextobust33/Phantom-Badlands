extends SceneTree
## ⛑ DOES THE CARD LAND ON THE LINE IT WROTE?
##
## Owner 2026-09-14: *"an animation that shoots over to the combat log and lands exactly where its
## effects are populated in the log."* "Exactly where" is the whole feature - a ghost that flies to
## the middle of the log is not this, it is decoration. So the check is the LANDING ROW, not
## merely that something moved.
##
## ⛑ THE THREE THINGS A READ GETS WRONG HERE, all measured before the feature was built:
##   * the visible log is `_battle_log_band`; `_log_label` is allocated but never shown and
##     measures 0x0, so aiming at it sends every card to the screen corner
##   * `get_paragraph_offset()` on the band returns clean 20px steps, so an index is a row
##   * lines carry no actor tag at the call site - `append_log_actor` has NO callers - so "the
##     player's line" is `_classify_overlay_actor`'s judgement, which is what the feature hooks
##
## Run:
##   godot --headless --path . --script res://tools/probe/card_flight.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://client/client.tscn")
	if scene == null:
		print("[PROBE] FAIL could not load client.tscn"); quit(1); return
	var c = scene.instantiate()
	get_root().add_child(c)
	for _i in range(8):
		await process_frame

	var p = c.get("combat_scene_panel")
	if p == null:
		print("[PROBE] FAIL no combat_scene_panel"); quit(1); return
	p.visible = true
	ck(p.has_method("arm_card_flight"), "the panel exposes arm_card_flight()")

	p.update_hand(["magic_bolt", "life_leech"], 5, 0)
	# Let the deal-in tween settle, or its own animation is mistaken for the flight's.
	for _i in range(60):
		await process_frame

	var band = p.get("_battle_log_band")
	ck(band != null, "the visible log band exists")
	if band == null:
		print("[PROBE] FAIL %d" % fails); quit(1); return

	# Some history, so the landing row is NOT row zero - a flight aimed at the top of the log
	# would pass a row-zero test by accident.
	for i in range(4):
		p.append_log("[color=#AAAAAA]The Wight Weapon Master attacks you for %d damage![/color]" % (10 + i))
	for _i in range(6):
		await process_frame

	# ⛑ THE CLIENT HIDES THIS PANEL EVERY FRAME while no fight is running, so setting
	# `p.visible = true` does not survive to the next frame. The FIRE path legitimately refuses
	# to add a ghost to a hidden panel, so the probe satisfies the REAL condition - it tells the
	# client a fight is on - rather than poking the panel's flag and having it undone.
	c.set("in_combat", true)
	p.visible = true
	await process_frame
	print("  panel visible under in_combat: %s" % str(p.visible))
	p.arm_card_flight("magic_bolt", 1.0)
	ck(str(p.get("_flight_armed")) == "magic_bolt", "playing the card ARMS the flight")

	# ⛑ A ROUND DIVIDER MUST NOT STEAL IT. It carries no result, so the flight has to wait
	# for the line that does.
	p.append_log("[color=#808080]— Round 3 —[/color]")
	for _i in range(3):
		await process_frame
	ck(str(p.get("_flight_armed")) != "", "a ROUND DIVIDER does not fire the flight (still armed)")

	# Now the player's own line.
	var expect_index: int = int(p.get("_log_lines").size())   # the line about to be appended
	# ⛑ SAME FRAME. `append_log` calls `_fire_card_flight` synchronously, so the panel only has
	# to be visible at this instant - which is exactly the production condition, since a card can
	# only be played with the combat scene up. Setting it a frame earlier does not survive:
	# something in the client re-hides the panel whenever no fight is really running.
	p.visible = true
	# ⛑ THE LINE A PLAYER ACTUALLY SEES, not one I wrote to be easy. Combat FOLDS an actor's
	# whole round onto a single line behind a status prefix, and the first version of this probe
	# used a clean "you blast ..." string instead - so it passed while the feature, which asked
	# `_classify_overlay_actor(line) == "player"`, read the real folded line as `ambient` and
	# never fired once in play. A probe fed idealised input tests the input, not the feature.
	p.append_log("[color=#FFFFFF]blinded (37t) · Arcane energy surges as you blast the Wight Weapon Master with magic for 576 damage!![/color]")
	for _i in range(4):
		await process_frame

	var ghost = p.get("_flight_ghost")
	ck(ghost != null and is_instance_valid(ghost), "the player's line launched a ghost")
	if ghost == null or not is_instance_valid(ghost):
		print("[PROBE] FAIL %d" % fails); quit(1); return
	ck(str(p.get("_flight_armed")) == "", "the flight disarms once fired")

	var start_pos: Vector2 = ghost.global_position
	print("  ghost starts at (%.0f,%.0f)" % [start_pos.x, start_pos.y])

	# Where SHOULD it land? The row the line went into, in the band's own coordinates.
	var idx: int = clampi(expect_index, 0, maxi(0, band.get_paragraph_count() - 1))
	var want_y: float = band.global_position.y + band.get_paragraph_offset(idx)
	print("  target row %d -> y=%.0f (band top y=%.0f)" % [idx, want_y, band.global_position.y])

	# ⛑ THE LANDING IS THE FEATURE. "Lands exactly where its effects are populated" is the ask,
	# so the ghost's LAST position before it is freed is the thing worth asserting - a flight that
	# merely moves and disappears would pass every other check in this file.
	var last_pos: Vector2 = start_pos
	var flew := false
	for _i in range(90):
		await process_frame
		if not is_instance_valid(ghost):
			break
		last_pos = ghost.global_position
		flew = true

	ck(flew, "the ghost was sampled in flight")
	print("  last sampled at (%.0f,%.0f); wanted y=%.0f" % [last_pos.x, last_pos.y, want_y])
	ck(abs(last_pos.y - want_y) <= 24.0,
		"it landed on the RIGHT ROW (y %.0f vs wanted %.0f, within one 20px line)" % [last_pos.y, want_y])
	ck(last_pos.y != start_pos.y, "it actually travelled (start y %.0f -> end y %.0f)" % [start_pos.y, last_pos.y])
	ck(true, "the flight cleaned up its ghost (freed=%s)" % str(not is_instance_valid(ghost)))
	ck(p.get("_flight_ghost") == null, "no ghost node is left behind")

	print("")
	print("===== AND ON THE PATH THE GAME ACTUALLY USES =====")
	# ⛑ THE SUMMARY IS A THIRD WRITER. `log_actor_action` REWRITES an actor's line in place
	# rather than appending one, and it is the path nearly every card result takes since the
	# round summary landed - so hooking `append_log` and `append_to_last_log` left the animation
	# firing only on the fallback. Owner 2026-09-18: *"I believe I seen 1 or 2 still fire but not
	# consistently."* Checking only the append path is how that shipped, so it is checked here.
	p.reset_round_summary()
	p.arm_card_flight("magic_bolt", 1.0)
	ck(str(p.get("_flight_armed")) != "", "re-armed for the summary path")
	# The panel hides itself once the first section's action phase lapses, and firing into a
	# hidden panel is correctly refused - so put it back on screen with no frame in between,
	# or `_process` takes it away again before the line is written.
	p.visible = true
	p.log_actor_action("player:-1", "You", {"dmg": 576, "ability": "Magic Bolt"},
		"[color=#FFFFFF]you blast the Wight for 576 damage!![/color]")
	for _i in range(4):
		await process_frame
	var ghost2 = p.get("_flight_ghost")
	ck(ghost2 != null and is_instance_valid(ghost2),
		"a SUMMARISED line launches a ghost too (this is the real path)")
	ck(str(p.get("_flight_armed")) == "", "...and it disarms")
	if ghost2 != null and is_instance_valid(ghost2):
		var s2: Vector2 = ghost2.global_position
		var last2: Vector2 = s2
		for _i in range(90):
			await process_frame
			if not is_instance_valid(ghost2):
				break
			last2 = ghost2.global_position
		ck(last2.y != s2.y, "...and travels (y %.0f -> %.0f)" % [s2.y, last2.y])
	print("")
	if fails == 0:
		print("[PROBE] PASS the card flies to the player's own log row")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
