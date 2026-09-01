# Find the nearest world tile of a given kind so a scenario can PARK the party somewhere the
# thing being tested actually exists. Hunting for a water tile by walking around in-game is
# exactly the setup waste this harness exists to remove.
#
#   godot --headless --path . --script tools/test_setup/find_tile.gd -- --kind=water --near=57,-11
#
# Prints one line: "FOUND <x> <y> (terrain=<n>)" or "NONE". kind: water | ore | forest
#
# IMPORTANT: this wires chunk_manager <-> world_system and loads the SAVED WORLD SEED exactly as
# server.gd does. Without that pairing the terrain generated here is not the terrain the live
# server has, and the scenario would park the party on a "water tile" that is dry land in game.
extends SceneTree

func _init():
	var kind := "water"
	var nx := 0
	var ny := 0
	var radius := 80
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--kind="):
			kind = s.substr(7)
		elif s.begins_with("--near="):
			var parts := s.substr(7).split(",")
			if parts.size() == 2:
				nx = int(parts[0]); ny = int(parts[1])
		elif s.begins_with("--radius="):
			radius = int(s.substr(9))

	# Mirror server.gd's world bring-up.
	var chunks = load("res://shared/chunk_manager.gd").new()
	root.add_child(chunks)
	chunks.load_world_seed()
	var WS = load("res://shared/world_system.gd")
	var ws = WS.new()
	root.add_child(ws)
	ws.chunk_manager = chunks
	chunks.terrain_generator = ws
	print("world seed: %d" % int(chunks.world_seed))

	var want := []
	match kind:
		"water":   want = [WS.Terrain.WATER, WS.Terrain.DEEP_WATER]
		"ore":     want = [WS.Terrain.MOUNTAINS]
		"forest":  want = [WS.Terrain.FOREST, WS.Terrain.DEEP_FOREST]
		_:         want = [WS.Terrain.PLAINS]

	# Spiral outward so we get the CLOSEST match rather than any match.
	for r in range(1, radius):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue   # walk the ring only
				var x := nx + dx
				var y := ny + dy
				var t = ws.get_terrain_at(x, y)
				if t in want:
					print("FOUND %d %d  (terrain=%d)" % [x, y, int(t)])
					quit(); return
	print("NONE")
	quit()
