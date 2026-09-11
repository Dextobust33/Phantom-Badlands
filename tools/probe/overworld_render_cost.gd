extends SceneTree
## WHERE does the server's 17ms per move actually go?
##
## Phase 2.95 PHASE 1 moves overworld rendering to the client, and the backlog's payoff figure
## ("server render CPU -> ~0") assumes the cost is the STRING BUILDING. It might not be: the
## server has to raycast line of sight anyway, because it decides what a player is allowed to
## see, and that stays server-side whoever draws the map. If LOS dominates, Phase 1 is still
## worth doing for bandwidth but its CPU claim needs rewriting BEFORE anyone builds on it.
##
## So: build the real world, call the real `generate_map_display`, and report the split it
## already measures (setup / LOS / render / join).
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

const REPS := 30
const RADIUS := 11


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws
	ws.map_diag_always = true   # the function's own timers, reported every call

	# A spot with terrain around it. Not the origin: (0,0) is the Crossroads safe zone and its
	# post tiles are unusually cheap (few gatherables, no hotspots).
	var spots := [Vector2i(40, 40), Vector2i(-120, 60), Vector2i(300, -200)]
	print("\n=== OVERWORLD MAP COST — the real generator, radius %d ===" % RADIUS)
	for spot in spots:
		var explored := {}
		# One warm-up: chunk generation on first touch is not what we are measuring.
		ws.generate_map_display(spot.x, spot.y, RADIUS, [], [], [], [], [], explored, [], false, [])
		var t0 := Time.get_ticks_usec()
		var out := ""
		for i in range(REPS):
			out = ws.generate_map_display(spot.x, spot.y, RADIUS, [], [], [], [], [], explored, [], false, [])
		var per := float(Time.get_ticks_usec() - t0) / float(REPS) / 1000.0
		print("  (%d, %d): %.2f ms per call, %d bytes on the wire" % [spot.x, spot.y, per, out.to_utf8_buffer().size()])

	# A full call is far more than the map grid: the header, the compass and the MINIMAP are in
	# there too. Time the parts, because "move rendering to the client" only helps the parts that
	# are string building - and only if the DATA they need is cheap to gather.
	print("")
	print("=== WHERE THE REST GOES (spot 40,40) ===")
	var spot := Vector2i(40, 40)
	var explored2 := {}
	ws.generate_map_display(spot.x, spot.y, RADIUS, [], [], [], [], [], explored2, [], false, [])

	var t1 := Time.get_ticks_usec()
	for i in range(REPS):
		ws._collect_hotspot_clusters(spot.x - RADIUS, spot.x + RADIUS, spot.y - RADIUS, spot.y + RADIUS)
	print("  hotspot clusters : %.2f ms" % (float(Time.get_ticks_usec() - t1) / float(REPS) / 1000.0))

	var n := (2 * RADIUS + 1) * (2 * RADIUS + 1)
	var t2 := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				cm.get_tile(spot.x + dx, spot.y + dy)
	var tile_ms := float(Time.get_ticks_usec() - t2) / float(REPS) / 1000.0
	print("  %d x get_tile    : %.2f ms  (%.1f us each)" % [n, tile_ms, tile_ms * 1000.0 / float(n)])

	var t3 := Time.get_ticks_usec()
	for i in range(REPS):
		ws._get_compass_line(spot.x, spot.y)
	print("  compass line     : %.2f ms" % (float(Time.get_ticks_usec() - t3) / float(REPS) / 1000.0))

	var t4 := Time.get_ticks_usec()
	for i in range(REPS):
		ws._generate_minimap(spot.x, spot.y, [])
	print("  minimap          : %.2f ms" % (float(Time.get_ticks_usec() - t4) / float(REPS) / 1000.0))

	var t5 := Time.get_ticks_usec()
	var inner := ""
	for i in range(REPS):
		inner = ws._generate_new_map(spot.x, spot.y, RADIUS, [], [], [], [], [], explored2, {}, {})
	print("  map grid (whole) : %.2f ms, %d bytes" % [
		float(Time.get_ticks_usec() - t5) / float(REPS) / 1000.0, inner.to_utf8_buffer().size()])

	print("")
	print("Phase 1 moves only STRING BUILDING. Anything that gathers DATA (tiles, LOS, hotspots,")
	print("compass targets, minimap scan) stays on the server, which decides what may be sent.")
	quit(0)
