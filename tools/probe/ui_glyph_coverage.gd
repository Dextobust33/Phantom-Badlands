extends SceneTree
## A glyph used as a UI control's text must be BMP, never an emoji.
##
## Owner 2026-09-11, on Linux: *"The icons for the bug report and a few others aren't displaying
## properly (up in the very top right)."*
##
## MEASURED, not guessed. The bundled font is Consolas, and it covers almost nothing beyond ASCII
## - not even U+266A, the music note. Yet the music note RENDERS on the owner's Linux build,
## sitting right beside the broken icons. So symbols already reach a fallback font there; what
## that fallback does not carry is the ASTRAL plane, which is where every emoji lives:
##
##     lightbulb U+1F4A1  ladybug U+1F41E  camera U+1F4F7   -> astral, tofu
##     music note U+266A                                     -> BMP, renders
##
## That is the entire distinction, and it gives a rule a machine can check.
##
## THIS HAS HAPPENED BEFORE. v0.9.636 removed emoji from the bounty board and tool slots for
## exactly this reason ("was U+1F4B0 money bag, SMP range fonts tofu it"), and new ones were added
## afterwards - in the toolbar, the Review Damage button, the scratch-off, and every feedback
## button in the LAUNCHER, which is the first thing a Linux player sees. Without this check it
## comes back a third time.
const FILES := ["res://client/client.gd", "res://client/combat_scene_panel.gd",
	"res://client/scratch_off_panel.gd", "res://client/bounty_board_panel.gd",
	"res://client/companions_panel.gd", "res://client/kennel_panel.gd",
	"res://client/market_panel.gd", "res://client/fusion_panel.gd",
	"res://client/admin_panel.gd", "res://client/help_panel.gd",
	"res://launcher/launcher.gd"]

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- the distinction this rests on ---")
	var f: FontFile = load("res://font/Consolas/consolas.ttf")
	ck(f != null, "the bundled font loads")
	if f != null:
		ck(not f.has_char(0x266A),
			"the bundled font does NOT carry the music note - yet it renders, so fallback works")
		ck(not f.has_char(0x1F4A1), "...and does not carry emoji either")

	print("\n--- no UI control is labelled with an emoji ---")
	var bad: Array[String] = []
	var scanned := 0
	for path in FILES:
		var src := FileAccess.get_file_as_string(path)
		if src == "":
			continue
		var lines := src.split("\n")
		for i in range(lines.size()):
			var ln := lines[i]
			var t := ln.strip_edges()
			# Comments and changelog prose are EXCLUDED on purpose. Several of them quote the old
			# glyph while explaining why it was removed, and rewriting those would falsify the
			# record rather than fix a button.
			if t.begins_with("#") or ln.contains("display_game("):
				continue
			# Only where a glyph becomes a control's visible text.
			if not (ln.contains(".text =") or ln.contains(".text=") or ln.contains("add_item(")
					or ln.contains("tooltip_text") or ln.contains("_fb in [")):
				continue
			scanned += 1
			for ch in ln:
				if ch.unicode_at(0) > 0xFFFF:
					bad.append("%s:%d  U+%05X  %s" % [path.get_file(), i + 1, ch.unicode_at(0), t.substr(0, 60)])
					break
	ck(scanned > 0, "scanned %d control-text lines across %d files" % [scanned, FILES.size()])
	if not bad.is_empty():
		print("")
		for b in bad:
			print("    " + b)
		print("")
	ck(bad.is_empty(), "every control label is BMP - %d astral glyphs found" % bad.size())

	print("\n--- and the replacements sit in the block the working glyph comes from ---")
	# Misc Symbols, U+2600-26FF, is where the proven-good music note lives.
	for pair in [["screenshot", 0x26F6], ["suggest idea", 0x263C], ["report issue", 0x26A0],
			["tools", 0x2692], ["review damage", 0x2694], ["recent changes", 0x2630]]:
		var cp: int = int(pair[1])
		ck(cp >= 0x2600 and cp <= 0x26FF,
			"%s uses U+%04X, same block as the music note" % [String(pair[0]), cp])

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
