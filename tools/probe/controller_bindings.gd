extends SceneTree
## ⛑ CAN A CONTROLLER PRESS ANYTHING?
##
## Measured before any of this was written: the engine ships **91 default actions and only SIX
## carry any joypad binding.** `ui_up/down/left/right` have the D-pad and the left stick, so a pad
## can already move the highlight between focusable Buttons - which is why the navigation audit
## made every new panel row a real `Button`. But `ui_accept` and `ui_cancel` have NO pad event at
## all, so the highlight could travel the whole game and never press anything.
##
## ⚑ THIS PROBE INJECTS A REAL PAD EVENT rather than re-reading what the code just wrote.
## Reading the InputMap back only proves `action_add_event` was called; it says nothing about
## whether a press of button A reaches `ui_accept`, which is the thing a player does. The two
## checks are deliberately different questions:
##   1. the binding EXISTS on the real client scene (so `_ready` ran it, in the real order)
##   2. an injected press MAKES THE ACTION FIRE (so the binding is the right one)
##
## Run:
##   godot --headless --path . --script res://tools/probe/controller_bindings.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _pad_events(action: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append(e.button_index)
	return out


func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)

	# ⚑ BEFORE the client exists - this is the engine default, and the reason the work was needed.
	var before_accept: int = _pad_events("ui_accept").size()
	var before_cancel: int = _pad_events("ui_cancel").size()
	print("===== 0. THE ENGINE DEFAULT (why this exists) =====")
	print("  ui_accept joypad events before the client loads: %d" % before_accept)
	print("  ui_cancel joypad events before the client loads: %d" % before_cancel)

	var scene: PackedScene = load("res://client/client.tscn")
	if scene == null:
		print("could not load client.tscn"); quit(1); return
	var c = scene.instantiate()
	get_root().add_child(c)
	for _i in range(8):
		await process_frame

	print("===== 1. THE BINDINGS EXIST ON THE REAL SCENE =====")
	var acc: Array = _pad_events("ui_accept")
	var can: Array = _pad_events("ui_cancel")
	ck(JOY_BUTTON_A in acc, "ui_accept carries the pad's A button (got %s)" % str(acc))
	ck(JOY_BUTTON_B in can, "ui_cancel carries the pad's B button (got %s)" % str(can))
	ck(acc.count(JOY_BUTTON_A) == 1, "A is bound to ui_accept exactly ONCE - a double binding fires the action twice per press")

	print("===== 2. AN INJECTED PRESS ACTUALLY FIRES THE ACTION =====")
	# The question a player asks. Re-reading the InputMap would only prove `action_add_event` ran.
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_A
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	ck(Input.is_action_pressed("ui_accept"), "pressing pad A makes ui_accept pressed")
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_A
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	ck(not Input.is_action_pressed("ui_accept"), "releasing pad A releases ui_accept")

	print("===== 3. THE PANELS A PAD HAS TO DRIVE ARE FOCUSABLE =====")
	# A binding is useless if nothing can receive the highlight. The tree is the pad's only door
	# (the shortcut row is FOCUS_NONE on purpose), so its rows must be focusable or Start leads
	# somewhere the pad cannot use.
	var tree = c.get("menu_tree_panel")
	ck(tree != null, "the client built a menu_tree_panel")
	if tree != null:
		tree.open()
		await process_frame
		await process_frame
		var focusable := 0
		var rows := 0
		for row in tree._item_box.get_children():
			for ch in row.get_children():
				if ch is Button:
					rows += 1
					if ch.focus_mode == Control.FOCUS_ALL:
						focusable += 1
		ck(rows > 0, "the tree drew %d entry buttons" % rows)
		ck(focusable == rows, "all %d are FOCUS_ALL (a pad cannot highlight the rest)" % rows)
		var cats := 0
		var cats_focusable := 0
		for b in tree._cat_box.get_children():
			if b is Button:
				cats += 1
				if b.focus_mode == Control.FOCUS_ALL:
					cats_focusable += 1
		ck(cats_focusable == cats and cats > 0, "all %d category buttons are focusable too" % cats)
		tree.close()

	print("")
	if fails == 0:
		print("[PROBE] PASS a controller can move, press and back out")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
