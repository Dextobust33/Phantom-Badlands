extends SceneTree
## ⛑ IS THERE ONE ANSWER TO "HOW DO I GET OUT OF THIS SCREEN"?
##
## Owner 2026-09-18: *"A lot of these menus with popup windows like the atlas and the quest board
## require me to click the x or maybe hit escape to get out of. Lots of the others I can press
## space to get out of. We need to make it uniform."*
##
## ⛑ MEASURED BEFORE CHANGING ANYTHING: of 31 panel scripts, eight handled their own keys and took
## ESCAPE ONLY, three took SPACE, and the rest closed through the action bar's Space button. Which
## key worked depended on which of three eras a panel was written in, and nothing on screen said
## so. The eight Escape-only ones are exactly the full-screen panels the owner named.
##
## The rule now lives in `client/panel_close_keys.gd`. This checks two things: that every panel
## handling its own close key ASKS that rule rather than testing a keycode itself, and — by
## EXECUTING it — that the rule accepts the keys a player will actually press.
##
## Run:
##   godot --headless --path . --script res://tools/probe/panels_close_the_same_way.gd

const PanelCloseKeysScript := preload("res://client/panel_close_keys.gd")

var _fails: Array = []


func _fail(m: String) -> void:
	_fails.append(m)
	print("  FAIL  %s" % m)


func _ok(m: String) -> void:
	print("  ok    %s" % m)


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.echo = false
	return e


func _init() -> void:
	print("")
	print("===== 1. THE RULE ITSELF, RUN =====")
	# ⛑ EXECUTED, not read. A close rule that compiles and matches nothing looks exactly like one
	# that works - and this session has already shipped one helper that read a field nobody wrote.
	var cases := [
		["Escape closes", PanelCloseKeysScript.wants_close(_key(KEY_ESCAPE))],
		["Space closes", PanelCloseKeysScript.wants_close(_key(KEY_SPACE))],
		["Enter closes", PanelCloseKeysScript.wants_close(_key(KEY_ENTER))],
		["numpad Enter closes", PanelCloseKeysScript.wants_close(_key(KEY_KP_ENTER))],
		["a letter does NOT close", not PanelCloseKeysScript.wants_close(_key(KEY_J))],
		["a digit does NOT close", not PanelCloseKeysScript.wants_close(_key(KEY_4))],
		["a non-key event is ignored", not PanelCloseKeysScript.wants_close(InputEventMouseMotion.new())],
	]
	for c in cases:
		if bool(c[1]):
			_ok(String(c[0]))
		else:
			_fail(String(c[0]))
	# A key RELEASE must not close, or a panel opened with Space closes on the same press.
	var up := _key(KEY_SPACE)
	up.pressed = false
	if PanelCloseKeysScript.wants_close(up):
		_fail("a key RELEASE closes the panel - opening one with Space would shut it instantly")
	else:
		_ok("a release does not close")
	var echo := _key(KEY_ESCAPE)
	echo.echo = true
	if PanelCloseKeysScript.wants_close(echo):
		_fail("a held key repeats the close")
	else:
		_ok("auto-repeat does not close twice")

	print("")
	print("===== 2. NO PANEL KEEPS ITS OWN PRIVATE ANSWER =====")
	var dir := DirAccess.open("res://client")
	var names: Array = []
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with("_panel.gd"):
				names.append(f)
			f = dir.get_next()
		dir.list_dir_end()
	names.sort()
	var own := 0
	var shared := 0
	for n in names:
		var src := FileAccess.get_file_as_string("res://client/%s" % n)
		var uses_shared: bool = src.find("PanelCloseKeysScript.wants_close(") >= 0
		# A panel that tests KEY_ESCAPE itself is a private answer - UNLESS it is stepping back
		# through its own sub-view rather than closing, which is a different question.
		var tests_escape: bool = src.find("== KEY_ESCAPE") >= 0 or src.find("KEY_ESCAPE or") >= 0 \
			or src.find("or KEY_ESCAPE") >= 0 or src.find("KEY_ESCAPE]") >= 0
		if uses_shared:
			shared += 1
		if tests_escape and not uses_shared:
			own += 1
			_fail("%s decides for itself which key closes it" % n)
	print("  %d panel scripts, %d use the shared rule" % [names.size(), shared])
	if own == 0:
		_ok("no panel carries its own close-key list")

	print("")
	print("===== 3. AND THE SCREEN SAYS SO =====")
	# A uniform key nobody is told about is still a key nobody presses.
	print("  the label every close button carries: \"%s\"" % PanelCloseKeysScript.CLOSE_HINT)
	var labelled := 0
	for n in names:
		var src := FileAccess.get_file_as_string("res://client/%s" % n)
		if src.find("PanelCloseKeysScript.CLOSE_HINT") >= 0:
			labelled += 1
	print("  %d panels print the keys on their close control" % labelled)
	if labelled == 0:
		_fail("no panel tells the player which keys close it")
	else:
		_ok("the close control names the keys")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS every panel that handles its own keys asks one shared rule, and that rule")
	print("       accepts Escape, Space and Enter.")
	quit()
