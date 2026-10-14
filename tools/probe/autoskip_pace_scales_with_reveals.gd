extends SceneTree
## Playtest sheet item 30 (owner 2026-10-14): late minigames drag. Auto-skip clicked on a fixed gap,
## so a 45-reveal combat haul took ~16s. The gap now shrinks with the pick count: a whole run takes
## about AutoskipPace.TARGET_TOTAL seconds, never slower than the base gap, never below the floor.
const Pace = preload("res://client/autoskip_pace.gd")
var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)

func _init() -> void:
	ck(is_equal_approx(Pace.interval(0.35, 3), 0.35), "3 reveals: the base gap (a short haul is not rushed)")
	ck(Pace.interval(0.35, 45) < 0.08, "45 reveals: much faster (%.3fs)" % Pace.interval(0.35, 45))
	ck(Pace.interval(0.35, 45) * 45.0 <= Pace.TARGET_TOTAL + 0.01, "...and the whole run is ~%.0fs (%.1fs)" % [Pace.TARGET_TOTAL, Pace.interval(0.35, 45) * 45.0])
	ck(Pace.interval(0.35, 10000) >= Pace.FLOOR, "never below the floor, however many")
	ck(Pace.interval(0.35, 0) == 0.35 and Pace.interval(0.6, -4) == 0.6, "no picks left: the base gap, no divide by zero")
	ck(Pace.interval(0.6, 100) < Pace.interval(0.6, 10) and Pace.interval(0.6, 10) < 0.6, "monotonic: more picks, shorter gap")
	# The real panel uses it.
	var panel = load("res://client/combat_loot_panel.gd").new()
	get_root().add_child(panel)
	await process_frame
	panel._autoskip_enabled = true
	panel._reveal_budget = 45
	panel._reveals_used = 0
	panel._start_autoskip()
	ck(panel._autoskip_timer != null and panel._autoskip_timer.wait_time < 0.08, "the combat loot panel's timer is paced to a 45-reveal budget (%.3fs)" % (panel._autoskip_timer.wait_time if panel._autoskip_timer else -1.0))
	panel._stop_autoskip()
	panel._reveal_budget = 3
	panel._start_autoskip()
	ck(panel._autoskip_timer != null and is_equal_approx(panel._autoskip_timer.wait_time, 0.35), "...and stays 0.35s for a 3-reveal budget")
	panel._stop_autoskip()
	var cl := FileAccess.get_file_as_string("res://client/client.gd")
	ck(cl.find("scratch_off_auto_next_at = now + AutoskipPaceScript.interval(SCRATCH_OFF_AUTO_INTERVAL, _picks_left)") >= 0, "the gather/craft scratch-off auto-skip is paced by the same rule (statement)")
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
