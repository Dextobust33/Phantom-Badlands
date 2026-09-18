extends SceneTree
## ⛑ DO THE FOUR BIG PANELS ACTUALLY RESIZE, AND DO THEY STAY PUT?
##
## The three ways this fails are all invisible in the source:
##
##  1. **It scales nothing.** A walker that finds no authored font sizes returns 0 and looks
##     exactly like a working one - register succeeds, the applier runs, the screen is identical.
##  2. **It RUNS AWAY.** Re-applying must re-derive from the AUTHORED size, never from the current
##     one. Compounding is invisible on the first apply and obvious three refreshes later, by
##     which time nobody connects it to this code.
##  3. **The loop variable is captured by reference.** Four registrations built in a `for` loop,
##     each with a lambda closing over the panel - GDScript captures by VALUE, but getting this
##     wrong points every applier at the LAST panel, and the first three silently do nothing to
##     themselves while quadruple-scaling the fourth.
##
## Run:
##   godot --headless --path . --script res://tools/probe/panel_font_scale.gd

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _count_sized(root: Control) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is Control:
			var ctrl: Control = node
			var keys: Array = UIScaleManager.FONT_SIZE_KEYS_RICH if ctrl is RichTextLabel else UIScaleManager.FONT_SIZE_KEYS_PLAIN
			for k in keys:
				if ctrl.has_theme_font_size_override(k):
					n += 1
		for ch in node.get_children():
			stack.append(ch)
	return n


func _first_sized(root: Control) -> Array:
	"""[control, key, current_size] for the first authored font under root."""
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is Control:
			var ctrl: Control = node
			var keys: Array = UIScaleManager.FONT_SIZE_KEYS_RICH if ctrl is RichTextLabel else UIScaleManager.FONT_SIZE_KEYS_PLAIN
			for k in keys:
				if ctrl.has_theme_font_size_override(k):
					return [ctrl, k, ctrl.get_theme_font_size(k)]
		for ch in node.get_children():
			stack.append(ch)
	return []


func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://client/client.tscn")
	if scene == null:
		print("[PROBE] FAIL could not load client.tscn"); quit(1); return
	var c = scene.instantiate()
	get_root().add_child(c)
	for _i in range(10):
		await process_frame

	var names := ["inventory_panel", "market_panel", "crafting_panel", "sanctuary_panel"]
	for nm in names:
		var panel: Control = c.get(nm)
		if panel == null or not is_instance_valid(panel):
			ck(false, "%s exists" % nm)
			continue

		var sized := _count_sized(panel)
		ck(sized > 0, "%s has %d authored font sizes for the walker to find" % [nm, sized])
		if sized == 0:
			continue

		var first := _first_sized(panel)
		var ctrl: Control = first[0]
		var key: String = first[1]
		var authored: int = int(first[2])

		# 1. it scales
		var touched: int = UIScaleManager.scale_fonts_under(panel, 2.0)
		var at2: int = ctrl.get_theme_font_size(key)
		ck(touched == sized, "%s: the walker touched all %d (got %d)" % [nm, sized, touched])
		ck(at2 == authored * 2, "%s: %s %d -> %d at 2.0x" % [nm, key, authored, at2])

		# 2. it does NOT run away - re-applying the SAME scale must give the SAME number
		UIScaleManager.scale_fonts_under(panel, 2.0)
		var again: int = ctrl.get_theme_font_size(key)
		ck(again == at2, "%s: re-applying 2.0x stays %d, does not compound to %d" % [nm, at2, again * 2])

		# 3. and it comes back down, derived from the AUTHORED size
		UIScaleManager.scale_fonts_under(panel, 1.0)
		var back: int = ctrl.get_theme_font_size(key)
		ck(back == authored, "%s: 1.0x returns to the authored %d (got %d)" % [nm, authored, back])

	# 4. the four registrations must each drive their OWN panel
	var mgr = c.get("ui_scale_manager")
	ck(mgr != null, "the client has a UIScaleManager")
	if mgr != null:
		for nm in names:
			var panel: Control = c.get(nm)
			if panel == null:
				continue
			var before: int = _first_sized(panel)[2] if not _first_sized(panel).is_empty() else 0
			mgr.set_scale(nm, 1.5)
			await process_frame
			var after_arr := _first_sized(panel)
			var after: int = int(after_arr[2]) if not after_arr.is_empty() else 0
			ck(after != before and after > 0,
				"%s: its OWN applier fired (%d -> %d) - a by-reference capture would leave this unchanged" % [nm, before, after])
			mgr.set_scale(nm, 1.0)
			await process_frame

	print("")
	if fails == 0:
		print("[PROBE] PASS all four panels scale, stay put, and drive themselves")
	else:
		print("[PROBE] FAIL %d check(s)" % fails)
	quit(1 if fails > 0 else 0)
