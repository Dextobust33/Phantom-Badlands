extends SceneTree
## A hover listener on a label that ignores the mouse can never fire.
##
## Owner 2026-09-11: *"I just ran into a Frenzied Giant Rat. Frenzied in its name is Red and
## underlined but hovering it does nothing."*
##
## `_monster_name_label` had `meta_hover_started` connected on one line and
## `MOUSE_FILTER_IGNORE` on the next. IGNORE means the control receives no mouse events, so the
## handler was unreachable - while the `[url=]` still RENDERED as a coloured, underlined link.
## That is the worst shape of this bug: it advertises an explanation that cannot be reached, and
## reading the code shows a hover handler wired correctly one line above.
##
## This checks the whole class rather than the one instance.
const FILES := ["res://client/combat_scene_panel.gd", "res://client/client.gd",
	"res://client/companions_panel.gd", "res://client/kennel_panel.gd",
	"res://client/fusion_panel.gd", "res://client/market_panel.gd",
	"res://client/help_panel.gd", "res://client/companion_stable_panel.gd",
	"res://client/sanctuary_stable_panel.gd"]

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("--- every meta_hover listener must be able to receive a mouse ---")
	var broken: Array[String] = []
	var checked := 0
	for f in FILES:
		var src := FileAccess.get_file_as_string(f)
		if src == "":
			continue
		var lines := src.split("\n")
		for i in range(lines.size()):
			if not lines[i].contains("meta_hover_started.connect"):
				continue
			# the node this listener belongs to
			var node := lines[i].strip_edges().split(".meta_hover_started")[0]
			if node == "":
				continue
			checked += 1
			# Look for that node's mouse_filter anywhere in the file. IGNORE makes the listener
			# dead; PASS or STOP both deliver events.
			for j in range(lines.size()):
				var ln := lines[j]
				if ln.contains(node + ".mouse_filter") and ln.contains("MOUSE_FILTER_IGNORE"):
					broken.append("%s:%d %s" % [f.get_file(), j + 1, node])
	ck(checked > 0, "found %d hover listeners to check" % checked)
	ck(broken.is_empty(), "none of them is on an IGNORE control%s" % (
		"" if broken.is_empty() else " - dead: " + ", ".join(broken)))

	print("\n--- and the prefix the owner hovered resolves to real text ---")
	var CM = load("res://shared/combat_manager.gd")
	for mod in ["frenzied", "juggernaut", "broodcalling", "vampiric", "swift", "thorned",
			"venomous", "warded", "gilded"]:
		var h: String = CM.empowered_mod_hover(mod)
		ck(h != "", "'%s' explains itself: \"%s\"" % [mod, h])
	# Every modifier the game can actually roll must have wording, or a player meets a red
	# underlined word with nothing behind it - which is what this whole report was.
	var MDB = load("res://shared/monster_database.gd")
	var missing: Array[String] = []
	for mod_id in MDB.EMPOWERED_MODIFIERS:
		if CM.empowered_mod_hover(String(mod_id)) == "":
			missing.append(String(mod_id))
	ck(missing.is_empty(), "every rollable empowered modifier has hover text%s" % (
		"" if missing.is_empty() else " - missing: " + ", ".join(missing)))

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
