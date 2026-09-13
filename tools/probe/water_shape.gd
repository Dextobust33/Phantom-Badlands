extends SceneTree
## Is the water small lakes and rivers, with rare large ones?
##
## Owner 2026-09-13: *"I'd like water to be more of small lakes and rivers with rare large lakes,
## instead of just big bodies of water."*
##
## That is a SIZE DISTRIBUTION, so it is measurable: flood-fill every body in a large sample of
## the world and report how big they are. And because shape is not a number, it also renders the
## sample so it can be looked at - the same reason the room floors were rendered rather than
## scored.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

const SAMPLE := 400      # a 400x400 tile window
const ORIGIN := Vector2i(700, 700)

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

	# Build the water mask for the window.
	var wet := {}
	var wet_n := 0
	for gy in range(SAMPLE):
		for gx in range(SAMPLE):
			if ws._is_water_tile_generated(ORIGIN.x + gx, ORIGIN.y + gy, seed):
				wet[gy * SAMPLE + gx] = true
				wet_n += 1
	print("\n===== WATER IN A %dx%d WINDOW =====" % [SAMPLE, SAMPLE])
	print("water covers %.1f%% of the ground" % (100.0 * float(wet_n) / float(SAMPLE * SAMPLE)))

	# Flood-fill into bodies.
	var seen := {}
	var sizes: Array = []
	for key in wet:
		if seen.has(key):
			continue
		var stack: Array = [key]
		seen[key] = true
		var n := 0
		while not stack.is_empty():
			var k: int = stack.pop_back()
			n += 1
			var kx: int = k % SAMPLE
			var ky: int = k / SAMPLE
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = kx + d.x
				var ny: int = ky + d.y
				if nx < 0 or ny < 0 or nx >= SAMPLE or ny >= SAMPLE:
					continue
				var nk: int = ny * SAMPLE + nx
				if wet.has(nk) and not seen.has(nk):
					seen[nk] = true
					stack.append(nk)
		sizes.append(n)
	sizes.sort()

	print("\n%d separate bodies of water" % sizes.size())
	if sizes.is_empty():
		ck(false, "there is no water at all")
		quit(1)
		return
	print("  median body   %d tiles" % sizes[sizes.size() / 2])
	print("  75th          %d tiles" % sizes[int(sizes.size() * 0.75)])
	print("  largest       %d tiles" % sizes[sizes.size() - 1])
	var small := 0
	var big := 0
	for n in sizes:
		if n <= 60:
			small += 1
		if n >= 600:
			big += 1
	print("  %d small (<=60 tiles), %d large (>=600)" % [small, big])

	print("\n--- what the owner asked for ---")
	ck(sizes.size() >= 8, "there are many separate bodies (%d), not one blob" % sizes.size())
	ck(float(small) / float(sizes.size()) > 0.5,
		"most bodies are small (%d of %d)" % [small, sizes.size()])
	ck(big <= maxi(1, sizes.size() / 8),
		"large lakes are RARE (%d of %d bodies)" % [big, sizes.size()])
	ck(wet_n > 0 and float(wet_n) / float(SAMPLE * SAMPLE) < 0.30,
		"water is a feature of the map, not most of it")

	print("\n--- a river is a river, not a pond ---")
	# A river body is long and thin: its tile count is small against its bounding box.
	var longest_thin := 0
	for key in wet:
		pass
	# Recompute one pass with bounding boxes to find the most river-like body.
	seen.clear()
	for key in wet:
		if seen.has(key):
			continue
		var stack: Array = [key]
		seen[key] = true
		var n := 0
		var minx := SAMPLE
		var maxx := 0
		var miny := SAMPLE
		var maxy := 0
		while not stack.is_empty():
			var k: int = stack.pop_back()
			n += 1
			var kx: int = k % SAMPLE
			var ky: int = k / SAMPLE
			minx = mini(minx, kx)
			maxx = maxi(maxx, kx)
			miny = mini(miny, ky)
			maxy = maxi(maxy, ky)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = kx + d.x
				var ny: int = ky + d.y
				if nx < 0 or ny < 0 or nx >= SAMPLE or ny >= SAMPLE:
					continue
				var nk: int = ny * SAMPLE + nx
				if wet.has(nk) and not seen.has(nk):
					seen[nk] = true
					stack.append(nk)
		var span: int = maxi(maxx - minx, maxy - miny)
		if span > 100 and n < span * 12:
			longest_thin = maxi(longest_thin, span)
	ck(longest_thin > 100,
		"at least one body runs %d tiles while staying thin - that is a river" % longest_thin)

	# The picture, because shape is not a number.
	var img := Image.create(SAMPLE, SAMPLE, false, Image.FORMAT_RGBA8)
	for gy in range(SAMPLE):
		for gx in range(SAMPLE):
			var is_wet: bool = wet.has(gy * SAMPLE + gx)
			var c := Color(0.18, 0.20, 0.16)
			if is_wet:
				var depth: float = ws._water_depth_score(ORIGIN.x + gx, ORIGIN.y + gy, seed)
				c = Color(0.15, 0.35, 0.75).lerp(Color(0.05, 0.12, 0.40), depth)
			img.set_pixel(gx, gy, c)
	img.resize(SAMPLE * 2, SAMPLE * 2, Image.INTERPOLATE_NEAREST)
	img.save_png("res://claude_screenshots/water_shape.png")
	print("\n  wrote claude_screenshots/water_shape.png - look at it, shape is not a number")

	print("\n[WATER] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
