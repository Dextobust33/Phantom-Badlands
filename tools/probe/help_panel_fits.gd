## ⛑ DOES THE HELP PANEL FIT ON THE SCREEN?
##
## Owner 2026-09-17: *"The companions help box that pops up spills over vertically, can't see the
## bottom of it."* Cause: `_body_label` had `fit_content = true` AND `scroll_active = true`, which
## contradict each other - `fit_content` grows the label to its entire content so the scroller
## never engages, the panel gets taller than the screen, and a CenterContainer centres an
## oversized panel, cutting off the bottom AND the top.
##
## ⛑ THE LONGEST TOPICS ARE THE ONES THAT BREAK, so this sorts by body length and checks the
## worst eight. A spot check of a short topic would have passed while the pages most worth reading
## were unreadable.
##
## ⛑ AND THE FIRST VERSION OF THIS PROBE PASSED THE BUG IT WAS WRITTEN FOR.
## `get_root().get_visible_rect().size.y` returns 1920 in a headless root - the WIDTH - so every
## panel was compared against a threshold nearly twice the real screen. Proven to fire now: with
## `fit_content = true` re-injected it reports two topics at 1284px and 1133px against 1080.
##
## Run:
##   godot --headless --path . --script res://tools/probe/help_panel_fits.gd

extends SceneTree
const HP = preload("res://client/help_panel.gd")

func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var p = HP.new()
	get_root().add_child(p)
	for _i in range(4):
		await process_frame

	# ⛑ THE DESIGN HEIGHT, not get_visible_rect() - that reported 1920 (the WIDTH) in a
	# headless root, so the first version of this probe compared every panel against a
	# threshold nearly twice the real screen and passed the very bug it was written for.
	var vp_h: float = 1080.0
	# longest topics first - those are the ones that overflowed
	var keys: Array = HP.HELP_TOPICS.keys()
	keys.sort_custom(func(a, b):
		return String(HP.HELP_TOPICS[a].get("body", "")).length() > String(HP.HELP_TOPICS[b].get("body", "")).length())

	var worst := 0.0
	var worst_key := ""
	var fails := 0
	for k in keys.slice(0, 8):
		p.show_topic(String(k))
		for _i in range(3):
			await process_frame
		var root_panel = p.get("_root_panel")
		var h: float = root_panel.size.y if root_panel != null else 0.0
		var body_len: int = String(HP.HELP_TOPICS[k].get("body", "")).length()
		var over := h > vp_h
		if over:
			fails += 1
		if h > worst:
			worst = h
			worst_key = String(k)
		print("[FIT] %-22s body=%5d chars  panel=%6.0f px  %s" % [k, body_len, h, "OVERFLOWS" if over else "fits"])

	print("[FIT] viewport %.0f px; tallest panel %.0f px (%s)" % [vp_h, worst, worst_key])
	if fails == 0:
		print("[FIT] PASS every topic fits on screen")
	else:
		print("[FIT] FAIL %d topic(s) taller than the screen" % fails)
	quit(1 if fails > 0 else 0)
