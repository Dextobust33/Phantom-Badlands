extends SceneTree
## What does composing the overworld actually COST on the client, per redraw?
##
## Owner 2026-09-13, from live play: *"It seems like we are getting some lag on the live server
## now that we have made the sprite changes. There is a delay to our actions intermittently."*
##
## The SERVER got cheaper when rendering moved to the client (that was the point of Phase 1), so
## a delay that appeared with the sprite work is most likely on the side that gained the work.
## `overworld_room.build()` composes 529 cells into one image on every redraw, and one of the
## things it does per cell is a PER-PIXEL loop in GDScript.
##
## This times the whole compose and then the pieces, on a real payload from a real world, at
## FOG levels from none to most-of-the-view - because fog is what decides how many cells take
## the per-pixel path, and fog is what a player accumulates as they explore.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const MapPayload = preload("res://shared/map_payload.gd")
const Room = preload("res://client/overworld_room.gd")

const REPS := 12


func _init() -> void:
	if not Room.available():
		print("[COMPOSECOST] SKIP - overworld sprites are licence-restricted and absent here")
		quit(2)
		return
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("\n===== OVERWORLD COMPOSE COST, per redraw =====")
	print("a redraw happens on EVERY move, so this is per player step on the client.")
	print("%-22s %8s %8s %10s" % ["view", "cells", "fog", "compose ms"])

	# Walk a widening area first, so later views have real FOG to draw. Fog is the whole point:
	# it is the branch that runs the per-pixel darken, and a player accumulates it by playing.
	var explored: Dictionary = {}
	var cases := [["fresh, no fog", 0], ["lightly explored", 40], ["well explored", 400]]
	for c in cases:
		var steps: int = int(c[1])
		for i in range(steps):
			ws.build_map_payload(40 + (i % 20) - 10, 40 + (i / 20) - 10, 11,
				[], [], [], [], [], explored, [], false, [])
		var payload: Dictionary = ws.build_map_payload(40, 40, 11, [], [], [], [], [], explored, [], false, [])
		var meaning: Array = MapPayload.cells(payload.get("meaning", {}))
		var biomes: Array = MapPayload.cells(payload.get("biomes", {}))
		var fog := 0
		var cells := 0
		for row in meaning:
			for m in row:
				cells += 1
				if String(m).begins_with("!fog") or String(m) == "fog" or String(m).find("fog") >= 0:
					fog += 1
		# Force a real rebuild every rep - the renderer caches on an unchanged key, and a player
		# who is MOVING never hits that cache, so timing the cached path would measure nothing.
		var t0 := Time.get_ticks_usec()
		for r in range(REPS):
			Room._key = ""
			Room.build(meaning, biomes, {"11,11": "res://client/sprites/overworld_pad32/1_1/down_stand.png"})
		var ms := float(Time.get_ticks_usec() - t0) / float(REPS) / 1000.0
		print("%-22s %8d %8d %10.1f" % [String(c[0]), cells, fog, ms])

	print("\n--- and what the per-pixel darken costs on its own ---")
	# 1024 get_pixel + 1024 set_pixel per darkened cell, in GDScript.
	var img := Image.create(23 * 32, 23 * 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.5, 0.4, 1))
	for n in [1, 50, 200]:
		var t1 := Time.get_ticks_usec()
		for r in range(REPS):
			for i in range(n):
				Room._darken(img, i % 23, (i / 23) % 23, 0.45)
		var dms := float(Time.get_ticks_usec() - t1) / float(REPS) / 1000.0
		print("  %3d darkened cells: %7.1f ms  (%d get_pixel + %d set_pixel)" % [
	print("")
	print("--- and SLICING the composed image into 529 cell textures ---")
	# Composing is only half a redraw. The grid then has to become 529 things an [img] tag can
	# load, which is a get_region + ImageTexture.create_from_image + take_over_path each.
	var pay2: Dictionary = ws.build_map_payload(40, 40, 11, [], [], [], [], [], explored, [], false, [])
	var mean2: Array = MapPayload.cells(pay2.get("meaning", {}))
	var bio2: Array = MapPayload.cells(pay2.get("biomes", {}))
	var t2 := Time.get_ticks_usec()
	for r in range(REPS):
		Room._key = ""
		Room.build(mean2, bio2, {})
		for y in range(23):
			for x in range(23):
				Room.cell_path(x, y)
	var full := float(Time.get_ticks_usec() - t2) / float(REPS) / 1000.0
	var t3 := Time.get_ticks_usec()
	for r in range(REPS):
		Room._key = ""
		Room.build(mean2, bio2, {})
	var only := float(Time.get_ticks_usec() - t3) / float(REPS) / 1000.0
	print("  compose only            : %6.1f ms" % only)
	print("  compose + 529 cell slices: %6.1f ms   (slicing = %.1f ms)" % [full, full - only])
	print("  that is the REAL per-move client cost of the sprite map.")

			n, dms, n * 1024, n * 1024])
	print("\nIf the darken dominates, the fix is a rect operation, not a pixel loop.")
	quit(0)
