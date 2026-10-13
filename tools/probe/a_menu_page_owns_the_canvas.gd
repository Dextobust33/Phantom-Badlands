extends SceneTree
## Owner sheet 2026-10-13, items 2/3/8: Rework, Salvage and Inspect "just display the map".
## Cause: the ~0.4s idle redraw (`update_map`) protected WIDE pages only; the inventory's short
## sub-screens were painted over within a tick. `_canvas_held_by_page()` is the one predicate, and
## the three callers that can paint or route over the canvas must ask it.
##
## ⛑ THIS PROBE READS STATEMENTS, NOT PROSE (see CLAUDE.md): every needle is a line of code, and
## each function body is sliced to its own `func` so a comment elsewhere cannot satisfy it. The
## real check is `python tools/test_setup/shots.py invpath`, which photographs the screens.

var _fails: Array = []
func _fail(m: String) -> void:
	_fails.append(m); print("  FAIL  %s" % m)
func _ok(m: String) -> void:
	print("  ok    %s" % m)

func _body(src: String, fn: String) -> String:
	var i := src.find("\nfunc %s(" % fn)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 8)
	return src.substr(i, (j - i) if j > i else 4000)

# A needle must be a whole code line, indentation included, not a fragment of a comment.
func _has_stmt(body: String, stmt: String) -> bool:
	for line in body.split("\n"):
		if String(line).strip_edges(true, true) == stmt:
			return true
	return false

func _init() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd").replace("\r\n", "\n")

	print("===== THE PREDICATE =====")
	var held := _body(src, "_canvas_held_by_page")
	if held == "":
		_fail("_canvas_held_by_page is gone")
	elif not _has_stmt(held, "return _ow_wide_page or inventory_mode"):
		_fail("_canvas_held_by_page no longer answers wide-page OR inventory_mode")
	else:
		_ok("a wide page or any inventory sub-screen holds the canvas")

	print("===== THE THREE CALLERS ASK IT =====")
	var um := _body(src, "update_map")
	if um == "":
		_fail("update_map is gone")
	elif not _has_stmt(um, "if _ow_canvas and _canvas_held_by_page():"):
		_fail("update_map no longer stands down for a held page - the idle redraw will paint over Rework/Salvage")
	else:
		_ok("update_map stands down (this is the idle-redraw guard)")

	var heal := _body(src, "_ow_heal_canvas")
	if heal == "" or not _has_stmt(heal, "if _canvas_held_by_page():"):
		_fail("_ow_heal_canvas no longer stands down for a held page")
	else:
		_ok("_ow_heal_canvas stands down")

	var col := _body(src, "_ow_text_in_column")
	var routes := false
	for line in col.split("\n"):
		if String(line).strip_edges().begins_with("return ") and String(line).find("not _canvas_held_by_page()") >= 0:
			routes = true
	if not routes:
		_fail("_ow_text_in_column no longer excludes a held page - its text goes to the column behind the map")
	else:
		_ok("_ow_text_in_column excludes a held page")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s)" % _fails.size())
		quit(1)
		return
	print("[PROBE] PASS inventory sub-screens hold the canvas against the idle map redraw")
	quit()
