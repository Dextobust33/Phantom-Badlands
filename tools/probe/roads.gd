extends SceneTree
## Roads should be worth walking on: wide enough to follow, quiet enough to cross a continent.
##
## Owner 2026-09-13: *"We may want to make paths/roads generate a little wider and make encounters
## very rare on them so players can traverse and explore the map without running into a crazy
## amount of encounters."*
##
## Both halves matter together. A one-tile road that nearly removes encounters is a trap - step
## off it without noticing and the world changes under you. A three-tile road that only halves
## them is not worth finding. This measures the width as generated and the encounter rate as
## rolled, rather than reading the constants back.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("--- a road is a band, not a line ---")
	# FIND DRY LAND FIRST. The first version of this probe stamped across (1200,1200), which is
	# deep water - the road correctly refused to pave it and the probe reported "0 tiles wide",
	# blaming the code for doing the right thing. A test that does not check its own fixture
	# measures the fixture.
	var ox := 0
	var oy := 0
	var found := false
	for cand_y in range(200, 900, 40):
		for cand_x in range(200, 900, 40):
			var dry := true
			for i in range(30):
				var tt := String(cm.get_tile(cand_x + i, cand_y).get("type", ""))
				if tt in ["water", "deep_water"]:
					dry = false
					break
				for dy2 in range(-2, 3):
					if String(cm.get_tile(cand_x + i, cand_y + dy2).get("type", "")) in ["water", "deep_water"]:
						dry = false
						break
				if not dry:
					break
			if dry:
				ox = cand_x
				oy = cand_y
				found = true
				break
		if found:
			break
	ck(found, "found dry ground to build a road on, at (%d, %d)" % [ox, oy])
	var wps: Array = []
	for i in range(30):
		wps.append(Vector2i(ox + i, oy))
	ws.stamp_paths_into_chunks({"test": wps})
	var width := 0
	for dy in range(-4, 5):
		if String(cm.get_tile(ox + 15, oy + dy).get("type", "")) == "path":
			width += 1
	ck(width >= 3, "a straight run is %d tiles wide" % width)
	ck(width <= 5, "...and not so wide it stops reading as a road (%d)" % width)

	print("\n--- the edges are protected, not just the centre ---")
	# The widening has to respect the same rules the single tile did, or a band paves over the
	# things the original skip list was protecting.
	var src := FileAccess.get_file_as_string("res://shared/world_system.gd")
	var i := src.find("func _stamp_one_path_tile(")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i)
	ck(body.find("_is_npc_post_interior(x, y)") >= 0, "post interiors are skipped per tile")
	ck(body.find('"bridge"') >= 0, "...and bridges")
	ck(body.find('"water", "deep_water"') >= 0,
		"...and water, which a widened road would otherwise pave into an accidental bridge")

	print("\n--- and a road is genuinely quiet ---")
	# Rolled, not read: walk the road and walk beside it, same ground, same level.
	var on_road := 0
	var off_road := 0
	var trials := 30
	for t in range(trials):
		for step in range(200):
			var x := ox + (step % 30)
			if ws.check_encounter(x, oy, 0, false, 1.0):
				on_road += 1
			if ws.check_encounter(x, oy + 12, 0, false, 1.0):
				off_road += 1
	var on_per := float(on_road) / float(trials)
	var off_per := float(off_road) / float(trials)
	print("    200 steps on the road: %.1f encounters;  beside it: %.1f" % [on_per, off_per])
	ck(off_per > 0.0 and on_per < off_per * 0.35,
		"the road is at least three times quieter than the ground beside it")
	ck(on_per > 0.0 or off_per == 0.0,
		"...but not perfectly safe - a rail through the world makes the wilderness pointless")

	print("\n[ROADS] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
