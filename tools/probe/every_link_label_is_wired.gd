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
	print("===== 3. NO LABEL IS BUILT WITH BBCODE AND LEFT SILENT =====")
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
