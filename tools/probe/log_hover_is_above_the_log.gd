extends SceneTree
## Owner 2026-10-13, item 17: "the Hover is popping up behind the Combat Log window (L / after dying)".
## The log window is top_level at z 4000; its LogDetail box is ALSO top_level, and a top_level node is drawn on
## the canvas rather than under its parent, so the box's z_index is absolute. At 400 it sat BELOW the window.
## Measured through the RenderingServer is not available headless, so this pins the numbers: the box must
## out-rank the window.
func _init() -> void:
	var P = load("res://client/fight_log_panel.gd").new()
	get_root().add_child(P)
	await process_frame
	P.show_detail("hover text")
	var box = P._detail_box
	var ok: bool = box != null and box.top_level and box.z_index > P.z_index
	print("  %s  detail box z %d vs window z %d (top_level box)" % ["PASS" if ok else "FAIL", box.z_index if box else -1, P.z_index])
	print("\n[LOGHOVERZ] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
