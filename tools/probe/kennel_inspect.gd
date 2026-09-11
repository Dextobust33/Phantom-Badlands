extends SceneTree
## The kennel must be able to INSPECT a companion, and show the same facts as everywhere else.
##
## Owner: *"it doesn't list its current subtier in that screen or let you inspect them"*. The rank
## landed earlier today; this is the other half.
##
## The rule that matters here is ONE BUILDER. A second copy of the inspect screen is exactly how
## the two would drift, and the companion variant multiplier being wrong for 93% of variants
## started as precisely that kind of private copy.

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var k := FileAccess.get_file_as_string("res://client/kennel_panel.gd")
	var c := FileAccess.get_file_as_string("res://client/companions_panel.gd")
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("--- the kennel can inspect ---")
	ck(k.contains("const CTX_INSPECT"), "there is an Inspect context action")
	ck(k.contains('_ctx_menu.add_item("Inspect", CTX_INSPECT)'), "...and it is in the menu")
	ck(k.contains("CTX_INSPECT:") and k.contains("_show_inspect(_ctx_index)"), "...and it dispatches")
	ck(k.contains("func _show_inspect(") and k.contains("func _on_inspect_back("),
		"open and back both exist")

	print("\n--- and it reuses the ONE builder, rather than growing a second screen ---")
	ck(k.contains("client_ref._build_companion_inspect_bbcode(c)"),
		"the kennel renders the shared inspect text")
	ck(c.contains("_build_companion_inspect_bbcode") or cli.contains("_build_companion_inspect_bbcode"),
		"...which is the same one the Companions screen uses")
	ck(cli.contains("kennel_panel.client_ref = self"), "the kennel has the client reference it needs")
	# A second hand-written stat block in the kennel would be the drift this avoids.
	ck(not k.contains("COMPANION_STAT_HELP") and not k.contains("Its Combat Card"),
		"the kennel does NOT restate any of the inspect content itself")

	print("\n--- the hoverable stats in that text are actually REACHABLE ---")
	# Both halves of the dead-hover class, one of which each panel had:
	#   nameplate: listener connected, control set to IGNORE  (the "Frenzied" report)
	#   inspect:   control fine, NO listener at all           (found while doing this item)
	for pair in [["kennel_panel.gd", k], ["companions_panel.gd", c]]:
		var name: String = String(pair[0])
		var src: String = String(pair[1])
		ck(src.contains("_inspect_text.meta_hover_started.connect"),
			"%s: the inspect text has a hover listener" % name)
		ck(src.contains("_inspect_text.mouse_filter = Control.MOUSE_FILTER_PASS"),
			"%s: ...and can receive the mouse" % name)
	ck(k.contains("func _show_inspect_tip("), "the kennel has a tooltip surface of its own")

	print("\n--- a refresh cannot strand the player in a stale overlay ---")
	ck(k.contains("if _inspect_root != null and _inspect_root.visible:"),
		"populate() notices the overlay is open")
	ck(k.contains("_on_inspect_back()") and k.contains("_show_inspect(_inspect_index)"),
		"...and either re-renders it or drops back to the grid")

	print("\n--- and the card rows still show the rank, which was the first half ---")
	ck(k.contains("PowerRank.tag(tier, sub_tier)"), "the kennel card shows tier and rank")
	ck(k.contains("PowerRank.pips(tier)"), "...with the ladder bar beside it")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
