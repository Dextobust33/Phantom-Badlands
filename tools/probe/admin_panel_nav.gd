extends SceneTree
## Does every admin-panel page actually OPEN, and can you always get back out?
##
## Written after the Dungeon button did nothing. The reorganisation added a tenth navigation case
## by hand next to nine correct ones, and omitted its `_render_page()` call - so the button set a
## variable and redrew nothing. Every static check passed: it compiled, the action id existed, the
## page's render case existed, and the nav suffix resolved. None of that is the same as pressing
## the button.
##
## So this presses the buttons.

const AdminPanelScript = preload("res://client/admin_panel.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _labels_of(col: Node) -> Array:
	var out := []
	for c in col.get_children():
		if c is Button:
			out.append(String(c.text))
	return out


func _init() -> void:
	var panel = AdminPanelScript.new()
	get_root().add_child(panel)
	await process_frame
	panel.open()
	await process_frame

	var col = panel._button_column
	ck(col != null, "panel builds its button column")
	if col == null:
		quit(1)
		return

	# Every navigation button advertised on the ROOT page.
	var navs := []
	for c in col.get_children():
		if c is Button:
			var mid = c.get_meta("action_id") if c.has_meta("action_id") else ""
			if String(mid).begins_with("_page_"):
				navs.append([String(mid), String(c.text)])
	# Fall back to reading the source if buttons do not carry their id as metadata.
	if navs.is_empty():
		var src := FileAccess.get_file_as_string("res://client/admin_panel.gd")
		var re := RegEx.new()
		re.compile('_add_button\\("([^"]+)",\\s*"(_page_[a-z_]+)"')
		for m in re.search_all(src):
			navs.append([m.get_string(2), m.get_string(1)])

	panel.open()
	await process_frame
	var root_labels := _labels_of(col)
	print("--- root shows %d buttons: %s" % [root_labels.size(), ", ".join(root_labels)])
	print("--- %d navigation buttons found ---" % navs.size())
	ck(navs.size() >= 9, "root advertises every page (found %d)" % navs.size())

	for pair in navs:
		var action: String = pair[0]
		var label: String = pair[1]
		panel.open()                       # always start from root
		await process_frame
		panel._on_button_pressed(action)
		await process_frame
		var page: String = String(panel._current_page)
		var labels := _labels_of(col)
		var expected: String = action.substr(6)

		ck(page == expected,
			"%-22s sets the page to '%s' (got '%s')" % [action, expected, page])
		# THE ONE THAT MUST CATCH IT: the page variable changing is not the page OPENING.
		#
		# The first version of this asserted `labels.size() > 1`, which is true of the root page
		# as well - so with the bug re-injected it still passed, reporting buttons that were
		# root's own. A check that cannot distinguish "opened the page" from "never left root"
		# is not checking anything. The content must actually DIFFER from root, and a sub-page
		# must carry Back specifically (root carries Close).
		ck(labels != root_labels,
			"%-22s actually RENDERS - content differs from root (%d buttons vs %d)" % [
				action, labels.size(), root_labels.size()])
		ck(labels.has("Back"),
			"%-22s shows a Back button, so it is a sub-page and not root" % action)

		# and Back really returns
		panel._on_button_pressed("_back_root")
		await process_frame
		ck(String(panel._current_page) == "root", "%-22s Back returns to root" % action)

	print("--- an unknown page must not strand the panel ---")
	panel._current_page = "no_such_page"
	panel._render_page()
	await process_frame
	ck(_labels_of(col).size() > 1,
		"an unrecognised page falls back to something with buttons, not a dead empty panel")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
