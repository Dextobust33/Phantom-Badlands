extends SceneTree
## The fight-log overlay actually BUILDS, SIZES and RENDERS - headless.
##
## ⛑ A PANEL THAT PARSES IS NOT A PANEL THAT WORKS. The two faults this guards have both shipped
## before in this project: `top_level = true` detaches a Control from its parent's rect, so
## `PRESET_FULL_RECT` resolves against nothing and sizes the panel to ZERO - it opens, reports
## `visible = true`, and covers nothing at all. That shipped in `social_panel.gd` for its whole
## life and again in the menu tree. So this asserts the SIZE, not the flag.
##
## Run:
##   godot --headless --path . --script res://tools/probe/fight_log_panel_builds.gd

const FL = preload("res://client/fight_log_panel.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var p = FL.new()
	get_root().add_child(p)
	await process_frame

	var vp: Vector2 = get_root().get_visible_rect().size
	print("  viewport is %dx%d" % [int(vp.x), int(vp.y)])

	ck(not p.visible, "starts hidden")
	ck(p.has_method("blocks_hotkeys") and not p.blocks_hotkeys(),
		"and does not swallow hotkeys while hidden")

	var lines: Array = []
	for i in range(40):
		lines.append("[color=#8FD98F]line %d[/color]  you hit for %d" % [i, i * 13])
	p.show_log("Fight 2 of 3  (current)", "\n".join(lines), true, false)
	await process_frame
	await process_frame

	ck(p.visible, "opens")
	ck(p.blocks_hotkeys(), "...and swallows hotkeys while open")
	# THE fault this probe exists for: a top_level Control sized to nothing.
	ck(p.size.x >= vp.x - 1.0 and p.size.y >= vp.y - 1.0,
		"fills the viewport (got %dx%d, want %dx%d)" % [int(p.size.x), int(p.size.y), int(vp.x), int(vp.y)])

	var body: RichTextLabel = p._body
	ck(body != null, "has a body label")
	if body != null:
		var seen: String = body.get_parsed_text()
		ck(seen.contains("line 39"), "the LAST line is in the rendered text, not just the first")
		ck(not seen.contains("[color="), "BBCode is parsed, not shown raw (%d chars drawn)" % seen.length())
		ck(body.size.x > 100.0, "the body has real width (%d px)" % int(body.size.x))
	ck(p._prev_btn.visible and not p._prev_btn.disabled, "Prev is offered when there is a prior fight")
	ck(p._next_btn.disabled, "...and Next is disabled on the current fight")

	p.close()
	await process_frame
	ck(not p.visible, "closes")
	ck(not p.blocks_hotkeys(), "...and releases the hotkeys")

	print("")
	if fails == 0:
		print("[PROBE] PASS the fight log overlay builds and fills the screen")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
