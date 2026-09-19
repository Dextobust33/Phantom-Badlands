extends SceneTree
## ⛑ IS EVERY LABEL THAT RENDERS A LINK ACTUALLY WIRED FOR ONE?
##
## Owner 2026-09-18: *"Hovering the underlined text in death log still doesn't work."*
##
## ⚑ THIS IS THE FOURTH TIME. A `[url=...]` in a RichTextLabel draws underlined whether or not
## anything is listening, so a label with no `meta_hover_started` connection looks exactly like one
## that works until you put the mouse on it. The record in `client.gd` is explicit about the
## previous three:
##   * the battle panel's own label — *"the damage in the party combat log still isn't hoverable"*
##   * the dungeon key's hoverable tiles, underlined and dead for a week
##   * `map_display.meta_clicked`, never connected, so click-to-inspect died with the sprite overlay
## and the fourth is `_ow_side_place`, the pinned block every PAGE in the side column is drawn into —
## which is where the death screen goes. Not the death log: all of them.
##
## So the check is on the CLASS. Every RichTextLabel the client builds with `bbcode_enabled` must
## either connect the meta signals or be named here as one that never renders a link.
##
## Run:
##   godot --headless --path . --script res://tools/probe/every_link_label_is_wired.gd

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _init() -> void:
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("")
	print("===== 1. THE LABELS THAT SHOW PLAYER TEXT, AND THEIR WIRING =====")
	# The four surfaces the game prints hoverable text into, checked by name because each is a
	# single named node rather than a pattern.
	var surfaces := {
		"game_output (the canvas)": "game_output.meta_hover_started.connect(_on_log_meta_hover)",
		"map_display (the side column log)": "map_display.meta_hover_started.connect(_on_log_meta_hover)",
		"the dungeon key": "_dungeon_key_label.meta_hover_started.connect(_on_log_meta_hover)",
		"_ow_side_place (the pinned column page)": "_ow_side_place.meta_hover_started.connect(_on_log_meta_hover)",
		"_ow_side_prompt (the pinned column prompt)": "_ow_side_prompt.meta_hover_started.connect(_on_log_meta_hover)",
		"the party strip": "lbl.meta_hover_started.connect(_on_log_meta_hover)",
	}
	for k in surfaces.keys():
		if cli.find(String(surfaces[k])) >= 0:
			_ok(String(k))
		else:
			_fail("%s renders links but nothing listens for a hover" % k)

	print("")
	print("===== 2. AND THE ONE THAT ALSO TAKES CLICKS =====")
	# ⛑ HOVER AND CLICK ARE TWO SIGNALS. `map_display` had hover wired and `meta_clicked` never
	# connected, so click-to-inspect was dead while hovering worked - which reads as "the tooltip
	# is fine, clicking is broken" rather than as a missing connection.
	for k in ["map_display.meta_clicked.connect(_on_map_meta_clicked)",
			"_ow_side_place.meta_clicked.connect(_on_map_meta_clicked)"]:
		if cli.find(k) >= 0:
			_ok(k.split(".")[0])
		else:
			_fail("%s -- links are hoverable but not clickable" % k.split(".")[0])

	print("")
	print("===== 3. AND THE PANELS, NOT ONLY client.gd =====")
	# ⚡ THIS PROBE MISSED THE FIFTH ONE BECAUSE IT ONLY READ client.gd. Owner 2026-09-18, hours
	# after the fourth was fixed: *"guess the Fight log still isn't hoverable?"* - and
	# `fight_log_panel.gd` had its signals connected all along. The fault there was different (its
	# hover box was a CHILD of the combat panel, which is hidden on the death screen, so a Control
	# in an invisible parent drew nothing) but the probe could not have told me either way, because
	# it never opened the file. A check scoped to one file is a check that will be wrong about the
	# next file.
	var panel_dir := DirAccess.open("res://client")
	var panels: Array = []
	if panel_dir != null:
		panel_dir.list_dir_begin()
		var f := panel_dir.get_next()
		while f != "":
			if f.ends_with("_panel.gd"):
				panels.append(f)
			f = panel_dir.get_next()
		panel_dir.list_dir_end()
	panels.sort()
	var silent_panels: Array = []
	for n in panels:
		var src := FileAccess.get_file_as_string("res://client/%s" % n)
		# A panel that renders `[url=` is offering links; it must listen for at least one of them.
		if src.find("[url=") < 0 and src.find("\"[url=%s]") < 0:
			continue
		if src.find("meta_hover_started") >= 0 or src.find("meta_clicked") >= 0:
			_ok("%s renders links and listens" % n)
		else:
			silent_panels.append(n)
			_fail("%s renders [url= and connects no meta signal" % n)
	if silent_panels.is_empty():
		_ok("every panel that renders a link listens for one")

	print("")
	print("===== 4. A HOVER BOX MUST NOT LIVE IN A HIDDEN PARENT =====")
	# ⛑ THE FIFTH FAULT, NAMED. The fight log opens from the death screen and the overworld; its
	# detail box has to be its own child, and it asks the combat panel only for the TEXT so there is
	# still one copy of the blow-by-blow.
	var flp := FileAccess.get_file_as_string("res://client/fight_log_panel.gd")
	var boxes := {
		"the fight log owns its detail box": flp.find("func show_detail(text: String)") >= 0,
		"...and hides it": flp.find("func hide_detail()") >= 0,
		"the TEXT still comes from the combat panel":
			cli.find("combat_scene_panel.log_detail_text(str(m))") >= 0,
		"and the panel resolves per FIGHT, not globally":
			FileAccess.get_file_as_string("res://client/combat_scene_panel.gd").find("func _detail_source()") >= 0,
	}
	for k in boxes.keys():
		if bool(boxes[k]):
			_ok(String(k))
		else:
			_fail("%s -- MISSING" % k)

	print("")
	print("===== 5. NO LABEL IS BUILT WITH BBCODE AND LEFT SILENT =====")
	# A sweep for the SHAPE, so the next one is caught when it is written rather than when it is
	# reported. Every `X = RichTextLabel.new()` whose block turns bbcode on is listed with whether
	# its variable ever appears beside `meta_hover_started`.
	var rx := RegEx.new()
	rx.compile("(_?[a-z][a-z0-9_]*) = RichTextLabel.new[(][)]")
	var built: Dictionary = {}
	for m in rx.search_all(cli):
		built[m.get_string(1)] = true
	var silent: Array = []
	for name in built.keys():
		var n := String(name)
		if cli.find("%s.bbcode_enabled = true" % n) < 0:
			continue
		if cli.find("%s.meta_hover_started" % n) >= 0:
			continue
		silent.append(n)
	silent.sort()
	print("  %d bbcode labels built in client.gd; %d have no meta wiring:" % [built.size(), silent.size()])
	for n in silent:
		print("    %s" % n)
	print("")
	print("  \u26d1 A NAME ON THAT LIST IS NOT AUTOMATICALLY A BUG - most of these never render a")
	print("     `[url=...]`. It is the list to check when a player says an underline does nothing,")
	print("     and it is here so that check takes a minute instead of a report.")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d label(s) render links nothing is listening for:" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every surface that prints hoverable text has the signals connected.")
	quit()
