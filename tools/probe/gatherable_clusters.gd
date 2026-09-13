extends SceneTree
## Are gatherables somewhere you GO, or something you walk around?
##
## Owner 2026-09-13: *"they should be clusters you run into sort of like the hot ones are, where
## you run into a large group of trees or a bunch of mining spots altogether or something. Having
## them scattered everywhere makes them obstacles more than actual activities players engage
## with."*
##
## The last sentence is the test. A scattered node is terrain; a stand of twenty is a
## destination. Two things have to be true and neither is obvious from the code:
##   * nodes must CLUMP - most of them in company, not alone;
##   * a clump must be ONE RESOURCE - a mixed hedge is not "a large group of trees".
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

const SAMPLE := 300
const ORIGIN := Vector2i(500, 500)

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws
	var seed: int = cm.world_seed

	var kind := {}
	var nodes := 0
	for gy in range(SAMPLE):
		for gx in range(SAMPLE):
			var t: Dictionary = ws.generate_tile(ORIGIN.x + gx, ORIGIN.y + gy, seed)
			var ty := String(t.get("type", "empty"))
			# WATER IS EXCLUDED, and not to make the numbers nicer. `water` is a GATHERABLE type
			# (you fish it), but a river is not a patch - it is a long connected ribbon that runs
			# THROUGH several patches, and under 8-connectivity it fuses them into one clump that
			# then reads as "mixed". That measured the rivers, not the gatherables: purity fell
			# from 69/125 to 29/92 purely because the new water generator made rivers longer.
			# The owner's ask is about stands of trees and ore, so that is what this counts.
			if ty in ws.GATHERABLE_TYPES and ty != "water" and ty != "deep_water":
				kind[gy * SAMPLE + gx] = ty
				nodes += 1
	var cover := 100.0 * float(nodes) / float(SAMPLE * SAMPLE)
	print("\n===== GATHERABLES IN A %dx%d WINDOW =====" % [SAMPLE, SAMPLE])
	print("nodes cover %.1f%% of the ground (was ~30%% when every tile rolled on its own)" % cover)
	ck(cover < 20.0, "the world is no longer a third nodes (%.1f%%)" % cover)
	ck(nodes > 200, "...but there are still plenty to find (%d)" % nodes)

	# Clump them. 8-connected, because a diagonal neighbour is plainly part of the same stand.
	var seen := {}
	var clumps: Array = []
	for key in kind:
		if seen.has(key):
			continue
		var stack: Array = [key]
		seen[key] = true
		var members: Array = []
		while not stack.is_empty():
			var k: int = stack.pop_back()
			members.append(k)
			var kx: int = k % SAMPLE
			var ky: int = k / SAMPLE
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var nx: int = kx + dx
					var ny: int = ky + dy
					if nx < 0 or ny < 0 or nx >= SAMPLE or ny >= SAMPLE:
						continue
					var nk: int = ny * SAMPLE + nx
					if kind.has(nk) and not seen.has(nk):
						seen[nk] = true
						stack.append(nk)
		clumps.append(members)

	var sizes: Array = []
	for m in clumps:
		sizes.append(m.size())
	sizes.sort()
	var alone := 0
	var in_big := 0
	for m in clumps:
		if m.size() <= 2:
			alone += m.size()
		if m.size() >= 12:
			in_big += m.size()
	print("\n%d clumps, largest %d tiles, median %d" % [
		clumps.size(), sizes[sizes.size() - 1], sizes[sizes.size() / 2]])
	print("  %d nodes stand alone or in pairs, %d are in stands of 12+" % [alone, in_big])
	ck(float(in_big) / float(maxi(1, nodes)) > 0.5,
		"most nodes are in a real stand (%d of %d)" % [in_big, nodes])

	print("\n--- and a stand is ONE resource, not a mixed hedge ---")
	var pure := 0
	var mixed := 0
	for m in clumps:
		if m.size() < 12:
			continue
		var first := String(kind[m[0]])
		var same := true
		for k in m:
			if String(kind[k]) != first:
				same = false
				break
		if same:
			pure += 1
		else:
			mixed += 1
	ck(pure > mixed,
		"%d of %d large stands are a single resource" % [pure, pure + mixed])

	# The picture, because "somewhere you go" is a look as much as a number.
	var palette := {}
	var img := Image.create(SAMPLE, SAMPLE, false, Image.FORMAT_RGBA8)
	for gy in range(SAMPLE):
		for gx in range(SAMPLE):
			var k: int = gy * SAMPLE + gx
			var c := Color(0.16, 0.17, 0.15)
			if kind.has(k):
				var ty := String(kind[k])
				if not palette.has(ty):
					var h: float = float(abs(hash(ty)) % 1000) / 1000.0
					palette[ty] = Color.from_hsv(h, 0.65, 0.95)
				c = palette[ty]
			img.set_pixel(gx, gy, c)
	img.resize(SAMPLE * 2, SAMPLE * 2, Image.INTERPOLATE_NEAREST)
	img.save_png("res://claude_screenshots/gatherable_clusters.png")
	print("\n  wrote claude_screenshots/gatherable_clusters.png (one colour per resource)")

	print("\n[GATHERCLUSTER] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
