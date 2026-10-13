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
	elif not _has_stmt(held, "return _ow_wide_page or _menu_mode_holds_canvas()"):
		_fail("_canvas_held_by_page no longer answers wide-page OR a held mode")
	else:
		_ok("a wide page or a held mode holds the canvas")

	var modes := _body(src, "_menu_mode_holds_canvas")
	if modes == "" or not _has_stmt(modes, "return inventory_mode or settings_mode or home_stone_mode"):
		_fail("_menu_mode_holds_canvas no longer lists inventory/settings/home-stone - a page of that mode can be painted over")
	else:
		_ok("inventory, settings and home-stone modes each hold the canvas")

	print("===== A LOCATION MESSAGE CANNOT CLOSE A HELD PAGE =====")
	# Another player's step sends a `location`; it must not read as the player walking away.
	var loc_ok := false
	var lines := src.split("\n")
	for i in range(lines.size() - 1):
		if String(lines[i]).strip_edges() == "if not _menu_mode_holds_canvas():" and String(lines[i + 1]).strip_edges() == "_ow_wide_page = false":
			loc_ok = true
	if not loc_ok:
		_fail("the location handler closes a wide page even while a mode holds it (owner items 11/23)")
	else:
		_ok("the location handler leaves a mode's page alone")

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

	print("===== THE WISH RESULT HAS A SURFACE (owner item 46) =====")
	# Bounded to its own match arm: from `"wish_granted":` to the next arm, never further.
	var wi := src.find("
		\"wish_granted\":")
	var wj := src.find("
		\"monster_select_prompt\":", wi + 10)
	if wi < 0 or wj < 0:
		_fail("could not bound the wish_granted arm - the probe's anchors moved")
	else:
		var arm := src.substr(wi, wj - wi)
		if not _has_stmt(arm, "get_tree().create_timer(1.0).timeout.connect(_show_victory_card_deferred.bind(wish_payload, _combat_generation))"):
			_fail("wish_granted no longer puts its result on the victory card - the line is printed behind the combat scene and the map paints over it")
		else:
			_ok("wish_granted shows its result on the victory card")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s)" % _fails.size())
		quit(1)
		return
	print("[PROBE] PASS inventory sub-screens hold the canvas against the idle map redraw")
	quit()
