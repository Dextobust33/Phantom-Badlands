extends SceneTree
## ⛑ DOES THE PLAYED CARD ACTUALLY MOVE?
##
## Owner 2026-09-14: *"a cool animation showing it is being used."* A tween that silently does
## nothing is indistinguishable from an unimplemented feature - it compiles, it is called, and the
## screen is identical. So this drives the real panel and watches the cell's transform CHANGE.
##
## ⛑ IT CHECKS THE MIDDLE OF THE ANIMATION, NOT THE END. At the end the card is back at rest by
## design, so an end-state check passes just as happily when nothing ever happened. The only
## honest sample is while it is in flight.
##
## Run:
##   godot --headless --path . --script res://tools/probe/card_flourish.gd

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

	var panel = c.get("combat_scene_panel")
	if panel == null:
		print("[PROBE] FAIL no combat_scene_panel"); quit(1); return
	ck(panel.has_method("flourish_card"), "the panel exposes flourish_card()")

	# A real hand, through the real entry point.
	panel.update_hand(["magic_bolt", "life_leech", "bulwark_of_bone"], 5, 0)
	# ⛑ WAIT FOR THE DEAL-IN TO SETTLE. The hand has its OWN entry animation, and it uses
	# TRANS_BACK - which overshoots past 1.0 - so a rest sample taken too early reads 1.016 and
	# then "shrinks" as that tween finishes. The first run of this probe did exactly that and
	# blamed the flourish. A baseline measured during someone else's animation is not a baseline.
	for _i in range(90):
		await process_frame

	var cells: Array = panel.get("_hand_cells")
	var target: Control = null
	for cell in cells:
		if cell != null and is_instance_valid(cell) and str(cell.get_meta("card_name", "")) == "magic_bolt":
			target = cell
			break
	ck(target != null, "the hand drew a cell for magic_bolt")
	if target == null:
		print("[PROBE] FAIL %d check(s)" % fails); quit(1); return

	var rest_scale: Vector2 = target.scale
	var rest_y: float = target.position.y
	print("  rest: scale=%s y=%.1f" % [str(rest_scale), rest_y])

	panel.flourish_card("magic_bolt", 1.0)
	# Sample mid-flight. The flourish rises for ~35% of its duration, so a few frames in is
	# comfortably inside the lift.
	for _i in range(6):
		await process_frame
	var mid_scale: Vector2 = target.scale
	var mid_y: float = target.position.y
	print("  mid:  scale=%s y=%.1f" % [str(mid_scale), mid_y])

	ck(mid_scale.x > rest_scale.x + 0.01, "the card GREW mid-flourish (%.3f -> %.3f)" % [rest_scale.x, mid_scale.x])
	# ⛑ The lift is a SCALE about the bottom edge, not a position change - the HBoxContainer
	# owns position. So the check is that the pivot sits at the card's base, which is what turns
	# growth into a lift; checking `position` would pass forever regardless.
	ck(target.pivot_offset.y >= target.size.y - 1.0,
		"the pivot is at the card's bottom edge, so growth reads as a lift (pivot y=%.1f, height=%.1f)" % [
			target.pivot_offset.y, target.size.y])

	# A name nothing in the hand matches must be a silent no-op, never an error: a copy played
	# from a menu, or a party member's card, reaches this with a name that is not on screen.
	var before: Vector2 = target.scale
	panel.flourish_card("not_a_real_card_xyz", 1.0)
	await process_frame
	ck(is_instance_valid(target), "an unknown card name does not crash the panel")

	print("")
	if fails == 0:
		print("[PROBE] PASS the played card visibly reacts")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
