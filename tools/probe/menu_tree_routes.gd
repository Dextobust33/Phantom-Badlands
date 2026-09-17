extends SceneTree

## Does every menu tree entry actually GO somewhere?
##
## ⚑ A TREE ENTRY POINTING AT AN ID NOTHING HANDLES IS A DEAD BUTTON WITH A NICE LABEL, and
## it looks identical to a working one from the source, from a screenshot, and from the panel
## itself. The tree exists because thirteen capabilities had no door; a mistyped id would quietly
## give one of them a door that opens onto nothing, which is worse than no door at all - the
## player stops looking.
##
## The instrument calls `MenuTreePanel.all_action_ids()` rather than re-reading the table, so the
## probe and the panel cannot disagree about what the tree offers. The other side IS read from
## source, and that is the point: two independent sources, or the check is circular.

const CLIENT := "res://client/client.gd"
const TREE := preload("res://client/menu_tree_panel.gd")


func _init() -> void:
	var src_text: String = FileAccess.get_file_as_string(CLIENT)
	if src_text == "":
		print("[PROBE] FAIL could not read ", CLIENT)
		quit(1)
		return

	# The arm headers of BOTH dispatchers, as literal names. An arm may list several:
	#   "clan_set_desc", "clan_set_motto", "clan_set_color":
	var handled := {}
	for body in [_func_body(src_text, "execute_local_action"), _func_body(src_text, "_on_shortcut_button_pressed")]:
		for line in body.split("
"):
			var t: String = line.strip_edges()
			if not t.begins_with("\"") or not t.ends_with(":"):
				continue
			for piece in t.substr(0, t.length() - 1).split(","):
				var name: String = piece.strip_edges()
				if name.begins_with("\"") and name.ends_with("\""):
					handled[name.substr(1, name.length() - 2)] = true

	var ids: Array = TREE.all_action_ids()
	print("[PROBE] tree offers %d entries; the two dispatchers handle %d ids" % [ids.size(), handled.size()])

	var missing: Array = []
	for id in ids:
		if not handled.has(id):
			missing.append(id)

	# Duplicated labels are a different fault and just as invisible: two rows, one destination.
	var seen := {}
	var dupes: Array = []
	for id in ids:
		if seen.has(id):
			dupes.append(id)
		seen[id] = true

	if missing.is_empty() and dupes.is_empty():
		print("[PROBE] PASS every tree entry routes, and no id appears twice")
		quit(0)
		return
	for m in missing:
		print("[PROBE] FAIL no dispatcher arm for tree id '%s'" % m)
	for d in dupes:
		print("[PROBE] FAIL tree id '%s' appears in more than one row" % d)
	quit(1)


func _func_body(src_text: String, fname: String) -> String:
	"""From `func <fname>(` to the next top-level `func `."""
	var start := src_text.find("func %s(" % fname)
	if start < 0:
		print("[PROBE] FAIL function not found: ", fname)
		return ""
	var end := src_text.find("
func ", start + 1)
	if end < 0:
		end = src_text.length()
	return src_text.substr(start, end - start)
