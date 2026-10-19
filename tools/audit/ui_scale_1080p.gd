extends SceneTree
## Does the whole ASCII map fit on a 1080p screen, without scrolling?
##
## Owner 2026-09-15: *"1080p players ASCII map has to be scrolled to even see the middle of their
## map. The Tool panel and all of that is too big over there. Ideally they should be able to see
## their whole ASCII map by default."*
##
## Measured on the REAL client scene at a real 1920x1080 viewport, not reasoned about from the
## layout code: instantiate it, let the containers settle, then compare the map's CONTENT height
## against the box it has to live in. The map is 23 rows (radius 11), 46 characters wide.
const MAP_ROWS := 23
const MAP_COLS_CHARS := 46

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://client/client.tscn")
	if scene == null:
		print("could not load client.tscn"); quit(1); return
	var c = scene.instantiate()
	get_root().add_child(c)
	for i in range(8):
		await process_frame

	var md = c.get_node_or_null("RootContainer/TopSection/MapPanel/MapDisplay")
	if md == null:
		print("no MapDisplay"); quit(1); return
	print("  viewport            %s" % str(get_root().size))
	print("  MapDisplay rect     %.0f x %.0f" % [md.size.x, md.size.y])

	var fs: int = md.get_theme_font_size("normal_font_size")
	var f: Font = md.get_theme_font("normal_font")
	var line_h: float = f.get_height(fs) if f != null else float(fs) * 1.3
	var char_w: float = f.get_char_size(32, fs).x if f != null else float(fs) * 0.6
	var need_h: float = line_h * float(MAP_ROWS)
	var need_w: float = char_w * float(MAP_COLS_CHARS)
	print("  map font size       %d  (line %.1f px, char %.1f px)" % [fs, line_h, char_w])
	print("  map needs           %.0f x %.0f px for %d rows x %d chars" % [need_w, need_h, MAP_ROWS, MAP_COLS_CHARS])
	print("  vertical overflow   %.0f px (%.0f%% of the box)" % [need_h - md.size.y, 100.0 * need_h / maxf(1.0, md.size.y)])

	ck(need_w <= md.size.x + 1.0, "the map fits ACROSS (%.0f <= %.0f) - the width cap has existed since v0.9.391" % [need_w, md.size.x])
	ck(need_h <= md.size.y + 1.0, "the map fits DOWN (%.0f <= %.0f) - no scrolling to see your own position" % [need_h, md.size.y])

	# What is taking the room, if anything.
	for path in ["RootContainer/TopSection/MapPanel", "RootContainer/TopSection"]:
		var n = c.get_node_or_null(path)
		if n != null and n is Control:
			print("  %-34s %.0f x %.0f" % [path, (n as Control).size.x, (n as Control).size.y])
	var overlay = c.get("tool_status_overlay")
	if overlay != null and is_instance_valid(overlay) and overlay is Control:
		print("  tool/status overlay             %.0f x %.0f  font %d" % [
			(overlay as Control).size.x, (overlay as Control).size.y,
			(overlay as Control).get_theme_font_size("normal_font_size")])

	print("RESULT: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
