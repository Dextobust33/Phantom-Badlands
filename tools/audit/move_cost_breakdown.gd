extends SceneTree
## Where does a single player STEP actually spend server time?
##
## Owner 2026-09-13, from live play: *"There is a delay to our actions intermittently."* The live
## server sits at 24% of a 2-core box for ONE player, which is the anomaly worth chasing.
##
## The existing cost probe times `generate_map_display`, which INFLATES the payload into the full
## BBCode string. The server only does that for clients too old to read a payload
## (`peer_reads_payload`), so for anyone on a current build that measurement includes work the
## server never performs. This times what `send_location_update` actually calls, and then the
## pieces inside it, so the number points at a line rather than at a phase.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const MapPayload = preload("res://shared/map_payload.gd")

const REPS := 25


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	# A WALKING player, not a standing one: every cache in here is keyed on position, so timing
	# the same square repeatedly measures the cache and not the game.
	var explored: Dictionary = {}
	for i in range(120):
		ws.build_map_payload(40 + (i % 13), 40 + (i / 13), 11, [], [], [], [], [], explored, [], false, [])

	print("\n===== WHAT ONE PLAYER STEP COSTS THE SERVER =====")

	var t0 := Time.get_ticks_usec()
	for i in range(REPS):
		ws.build_map_payload(40 + i, 40, 11, [], [], [], [], [], explored, [], false, [])
	var payload_ms := float(Time.get_ticks_usec() - t0) / float(REPS) / 1000.0
	print("  build_map_payload (what the server DOES) : %6.2f ms" % payload_ms)

	var t1 := Time.get_ticks_usec()
	for i in range(REPS):
		MapPayload.inflate(ws.build_map_payload(40 + i, 40, 11, [], [], [], [], [], explored, [], false, []))
	var inflate_ms := float(Time.get_ticks_usec() - t1) / float(REPS) / 1000.0
	print("  + inflate (only for OLD clients)         : %6.2f ms  (inflate alone %.2f ms)" % [
		inflate_ms, inflate_ms - payload_ms])

	print("\n----- inside build_map_payload -----")
	var t2 := Time.get_ticks_usec()
	for i in range(REPS):
		ws._map_cells(40 + i, 40, 11, [], [], [], [], [], explored, {}, {})
	var cells_ms := float(Time.get_ticks_usec() - t2) / float(REPS) / 1000.0
	print("  _map_cells  (the 23x23 grid)             : %6.2f ms" % cells_ms)

	var t3 := Time.get_ticks_usec()
	for i in range(REPS):
		ws._minimap_cells(40 + i, 40, [])
	var mini_ms := float(Time.get_ticks_usec() - t3) / float(REPS) / 1000.0
	print("  _minimap_cells (41x21)                   : %6.2f ms" % mini_ms)

	# The palette encode: 1,390 cells -> a palette plus one byte each, base64'd.
	var cells: Array = ws._map_cells(40, 40, 11, [], [], [], [], [], explored, {}, {})
	var t4 := Time.get_ticks_usec()
	for i in range(REPS):
		MapPayload.grid(cells[ws.CELLS_LOOK], "", "")
	var enc_ms := float(Time.get_ticks_usec() - t4) / float(REPS) / 1000.0
	print("  MapPayload.grid encode (look layer)      : %6.2f ms" % enc_ms)

	print("\n  accounted: %.2f ms of %.2f ms" % [cells_ms + mini_ms, payload_ms])
	print("  unaccounted is the header, compass, threat scan and the other two grid encodes.")

	print("\n----- and how _map_cells spends ITS time, by what the cell IS -----")
	# The grid is 529 cells and each one asks several questions. Time the two the whole grid
	# depends on, at grid scale, so a per-cell cost can be compared against the total above.
	var t5 := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-11, 12):
			for dx in range(-11, 12):
				cm.get_tile(40 + dx, 40 + dy)
	var tile_ms := float(Time.get_ticks_usec() - t5) / float(REPS) / 1000.0
	var seedv: int = cm.world_seed
	var t6 := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-11, 12):
			for dx in range(-11, 12):
				ws.get_biome_at(40 + dx, 40 + dy, seedv)
	var biome_ms := float(Time.get_ticks_usec() - t6) / float(REPS) / 1000.0
	print("  529x get_tile                            : %6.2f ms" % tile_ms)
	print("  529x get_biome_at                        : %6.2f ms" % biome_ms)
	# The per-cell DECISIONS. Each of these is called once per cell by `_map_cells`, and the
	# minimap's post scan was exactly this shape before it was bucketed: a function that walks
	# every post in the world, called 529 times a step.
	var t7 := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-11, 12):
			for dx in range(-11, 12):
				ws.is_safe_zone(40 + dx, 40 + dy)
	print("  529x is_safe_zone                        : %6.2f ms" % [
		float(Time.get_ticks_usec() - t7) / float(REPS) / 1000.0])

	var t8 := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-11, 12):
			for dx in range(-11, 12):
				ws._cell_biome(40 + dx, 40 + dy)
	print("  529x _cell_biome                         : %6.2f ms" % [
		float(Time.get_ticks_usec() - t8) / float(REPS) / 1000.0])

	var clusters = ws._collect_hotspot_clusters(29, 51, 29, 51)
	var t9 := Time.get_ticks_usec()
	for i in range(REPS):
		for dy in range(-11, 12):
			for dx in range(-11, 12):
				ws._is_hotspot_in_clusters(40 + dx, 40 + dy, clusters)
	print("  529x _is_hotspot_in_clusters             : %6.2f ms" % [
		float(Time.get_ticks_usec() - t9) / float(REPS) / 1000.0])

	print("\nA step also runs LOS, the threat scan and the compass. If _map_cells dominates and")
	print("get_tile/get_biome do not, the cost is in the per-cell DECISIONS, not the data.")
	quit(0)
