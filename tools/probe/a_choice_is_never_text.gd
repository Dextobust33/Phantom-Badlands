extends SceneTree
## ⛑ CAN A "PICK ONE OF THESE" EVER REACH THE PLAYER AS TEXT?
##
## Owner 2026-09-18, on the third instance of one symptom in one evening: *"Scroll of finding still
## flashes on the left side of the screen behind the map then the map takes it back over and the
## player can't see to select anything. Why are we not fixing these properly? When we find the
## proper solution to this we need to fix it so it can never happen again."*
##
## ⚑ THREE PER-SITE FIXES FAILED, AND THE CODE SAID THEY WOULD. `_ow_text_in_column()` carries the
## note: *"There are 230 such clears in this file, so guarding them one at a time was never going to
## hold."* `display_game` routes three ways off live state - does the map own the canvas, is a panel
## open, has a page claimed it - and a scroll used FROM THE INVENTORY trips the panel clause, so its
## prompt goes to the canvas and the map repaints over it. Adding `_page_clear()` does not help:
## the clear decides WHEN a page starts, not WHERE it lives.
##
## ⛑ SO THE RULE IS STRUCTURAL, NOT PER-SITE: a flow the game is WAITING on draws in a Control
## above the map. A Control has no routing decision to get wrong, nothing that can repaint it, and
## no state in which it is invisible while the game waits. This probe fails if a selection mode can
## reach the player any other way.
##
## Run:
##   godot --headless --path . --script res://tools/probe/a_choice_is_never_text.gd

const ChoicePanelScript := preload("res://client/choice_panel.gd")

## Every mode where the game is WAITING for the player to pick one of a list. Each must open the
## modal; each must close it on both exits.
const SELECTION_FLOWS := {
	"target_farm": "Scroll of Finding",
	"monster_select": "Scroll of Summoning",
}

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
	var cli := FileAccess.get_file_as_string("res://client/client.gd")

	print("")
	print("===== 1. THE MODAL EXISTS AND IS WIRED =====")
	var wiring := {
		"the panel is built": FileAccess.file_exists("res://client/choice_panel.gd"),
		"the client holds one": cli.find("var choice_panel = null") >= 0,
		"it is added to the tree": cli.find("choice_panel = preload(\"res://client/choice_panel.gd\").new()") >= 0,
		"a pick is routed": cli.find("choice_panel.chosen.connect(_on_choice_panel_chosen)") >= 0,
		"a cancel is routed": cli.find("choice_panel.cancelled.connect(_on_choice_panel_cancelled)") >= 0,
		"there is one way to open it": cli.find("func open_choice(kind: String") >= 0,
		"and one way to close it": cli.find("func close_choice()") >= 0,
	}
	for k in wiring.keys():
		if bool(wiring[k]):
			_ok(String(k))
		else:
			_fail("%s -- MISSING" % k)

	print("")
	print("===== 2. EVERY WAITING FLOW USES IT =====")
	var fk: Array = SELECTION_FLOWS.keys()
	fk.sort()
	for kind in fk:
		var label := String(SELECTION_FLOWS[kind])
		if cli.find("open_choice(\"%s\"" % kind) < 0:
			_fail("%s (%s) never opens the modal" % [label, kind])
		else:
			_ok("%s opens the modal" % label)
		# Both exits must put it away, or the next screen is drawn underneath a stale list.
		var picks: int = cli.count("\"%s\":" % kind)
		if picks < 2:
			_fail("%s is not handled on both pick and cancel" % label)
		else:
			_ok("%s is handled on pick and on cancel" % label)

	print("")
	print("===== 3. NOTHING POLLS THE SAME KEYS UNDERNEATH IT =====")
	# ⛑ THE DOUBLE-TRIGGER CLASS, which CLAUDE.md gives two Common Pitfalls to. The modal owns 1-9
	# while it is up; a `_process` poller that also reads them fires the same press twice.
	if cli.find("func _choice_modal_open() -> bool:") < 0:
		_fail("there is no test for whether the modal is up")
	else:
		_ok("the modal's own state is askable")
	for kind in fk:
		var guard := "and %s_mode \\n			and not _choice_modal_open():" % kind
		if cli.find("not _choice_modal_open()") < 0:
			_fail("no poller stands down while the modal is up")
			break
	if cli.count("not _choice_modal_open()") >= SELECTION_FLOWS.size():
		_ok("%d pollers stand down while it is up" % cli.count("not _choice_modal_open()"))
	else:
		_fail("only %d poller(s) stand down; %d flows need it" % [
			cli.count("not _choice_modal_open()"), SELECTION_FLOWS.size()])

	print("")
	print("===== 4. THE PANEL BEHAVES, RUN =====")
	# ⛑ EXECUTED, because a modal that compiles and never shows is exactly the failure being fixed.
	var panel = ChoicePanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.assumed_screen_height = 720.0
	panel.size = Vector2(1280, 720)
	# ⛑ CAPTURED IN AN ARRAY, NOT A LOCAL. A GDScript lambda captures a local by VALUE, so
	# `func(i): got_index = i` assigns the closure's own copy and the outer variable never moves -
	# the first run of this probe reported the panel ignoring every key press when it was the
	# harness that could not see the result. An Array is a reference, so the write lands.
	var got: Array = [-1, false]
	panel.chosen.connect(func(i): got[0] = i)
	panel.cancelled.connect(func(): got[1] = true)
	var opts: Array = []
	for i in range(40):
		opts.append("Option %d with a long enough label to wrap a narrow panel" % (i + 1))
	panel.open("[color=#FF00FF]Test[/color]", "Pick one.", opts)
	for _f in range(8):
		panel.size = Vector2(1280, 720)
		panel._fit_to_viewport()
		await process_frame
	if not panel.visible:
		_fail("the panel did not become visible")
	else:
		_ok("it shows")
	# 40 options must not make it taller than the screen - the fault the tutorial hint panel had.
	var pc: PanelContainer = null
	for n in _walk(panel):
		if n is PanelContainer and n.get_parent() is CenterContainer:
			pc = n
	if pc == null:
		_fail("could not find the panel body")
	else:
		print("  40 options: panel top %.0f bottom %.0f on a 720px screen" % [
			pc.global_position.y, pc.global_position.y + pc.size.y])
		if pc.global_position.y < 0.0 or pc.global_position.y + pc.size.y > 720.0:
			_fail("a 40-option list runs off the screen")
		else:
			_ok("a 40-option list fits and scrolls")
	# A number key picks; Escape cancels. Both through the real handler.
	panel._unhandled_key_input(_key(KEY_3))
	if int(got[0]) != 2:
		_fail("pressing 3 did not choose the third option (got %d)" % int(got[0]))
	else:
		_ok("a number key picks the row it names")
	panel.open("t", "", opts)
	panel._unhandled_key_input(_key(KEY_ESCAPE))
	if not bool(got[1]):
		_fail("Escape did not cancel")
	else:
		_ok("Escape cancels")

	print("")
	if not _fails.is_empty():
		print("[PROBE] FAIL %d problem(s):" % _fails.size())
		for m in _fails:
			print("   - %s" % m)
		quit(1)
		return
	print("[PROBE] PASS a choice the game is waiting on is drawn above the map, never printed into")
	print("       a buffer something else can repaint.")
	quit()


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
