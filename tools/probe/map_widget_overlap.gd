extends SceneTree
## ⛑ DO THE COORDS / AREA BOXES ACTUALLY COVER THE MAP?
##
## The backlog item has been carrying a DERIVED answer since it was filed - "roughly the top four
## rows of about a third of the width at each corner" - with a note that it was never measured in
## pixels. Deriving a geometry from offsets is how the gold-ring bug survived twice: the numbers
## look right and the screen disagrees.
##
## So this measures it. It puts the client into the configuration the item is about - the one
## `_place_map_widgets(false)` builds, which is what the game uses in combat, in a dungeon and in
## the house - and reads the REAL rects off the nodes after a layout pass.
##
## ⛑ `_place_map_widgets(false)` IS CALLED DIRECTLY rather than by driving the client into a
## fight. That is deliberate and it is also this probe's limit: it proves the GEOMETRY of that
## configuration, not that the game reaches it. The shots harness covers the second half.
##
## Run:
##   godot --headless --path . --script res://tools/probe/map_widget_overlap.gd

func _init() -> void:
	get_root().set_content_scale_size(Vector2i(1920, 1080))
	get_root().size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://client/client.tscn")
	if scene == null:
		print("[OVERLAP] FAIL could not load client.tscn")
		quit(1)
		return
	var c = scene.instantiate()
	get_root().add_child(c)
	for _i in range(8):
		await process_frame

	var map = c.get("map_display")
	if map == null:
		print("[OVERLAP] FAIL no map_display")
		quit(1)
		return

	# ⛑ BUILD THE COORDS BOX FIRST. It is created lazily by `_ensure_coord_post_label()` on the
	# first location update, so in a headless probe with no server it is simply NULL - and the
	# first run of this probe duly reported "absent" and then printed a confident 0.0% coverage
	# for a box that did not exist. A measurement that silently drops one of the two things it is
	# measuring is worse than no measurement.
	c.call("_ensure_coord_post_label")
	if c.get("region_label") != null:
		c.get("region_label").visible = true
	if c.get("coord_post_label") != null:
		c.get("coord_post_label").visible = true
	for _i in range(2):
		await process_frame

	# The configuration the item is about: the map back in its column, boxes floating on it.
	c.call("_place_map_widgets", false)
	for _i in range(4):
		await process_frame

	var map_rect: Rect2 = Rect2(map.global_position, map.size)
	print("[OVERLAP] map_display  pos=(%.0f,%.0f) size=%.0fx%.0f" % [
		map_rect.position.x, map_rect.position.y, map_rect.size.x, map_rect.size.y])

	var total_covered: float = 0.0
	for name in ["coord_post_label", "region_label", "tool_status_overlay", "minimap_display"]:
		var n = c.get(name)
		if n == null or not is_instance_valid(n):
			print("[OVERLAP] %-20s (absent)" % name)
			continue
		var vis: bool = bool(n.visible)
		var r: Rect2 = Rect2(n.global_position, n.size)
		var inter: Rect2 = r.intersection(map_rect)
		var area: float = inter.size.x * inter.size.y
		if vis:
			total_covered += area
		var pct: float = 0.0
		if map_rect.size.x * map_rect.size.y > 0.0:
			pct = 100.0 * area / (map_rect.size.x * map_rect.size.y)
		print("[OVERLAP] %-20s vis=%-5s rect=(%.0f,%.0f %.0fx%.0f) parent=%s covers %.0fx%.0f = %.1f%% of the map" % [
			name, str(vis), r.position.x, r.position.y, r.size.x, r.size.y,
			(n.get_parent().name if n.get_parent() != null else "-"),
			inter.size.x, inter.size.y, pct])

	var map_area: float = map_rect.size.x * map_rect.size.y
	var pct_total: float = (100.0 * total_covered / map_area) if map_area > 0.0 else 0.0
	print("[OVERLAP] VISIBLE widgets cover %.1f%% of the map in the non-canvas layout" % pct_total)
	quit(0)
