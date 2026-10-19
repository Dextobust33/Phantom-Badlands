extends SceneTree
## How far must a player walk to find country at their own level?
##
## Owner 2026-09-13: *"It seems like players will have to travel much farther now to fight
## monsters of their level right?"*
##
## A fair question and a real consequence of widening the early bands: level 100 used to sit at
## radius 250 and now sits at 900. This measures the walk rather than reassuring about it, in the
## two terms that matter - how far from the ORIGIN, and how far from the NEAREST POST, which is
## where a player actually sets out from.
const WorldSystemScript = preload("res://shared/world_system.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")

## The curve as it was before 2026-09-13, kept here so the comparison is a measurement and not a
## memory. Only the bands that changed are reproduced; the rest is identical.
func _old_curve(d: float) -> int:
	if d <= 10:
		return 1
	if d <= 20:
		return int(1 + ((d - 10) / 10.0) * 1)
	if d <= 40:
		return int(2 + ((d - 20) / 20.0) * 4)
	if d <= 150:
		return int(6 + ((d - 40) / 110.0) * 44)
	if d <= 400:
		return int(50 + ((d - 150) / 250.0) * 150)
	if d <= 800:
		return int(200 + ((d - 400) / 400.0) * 400)
	if d <= 1200:
		return int(600 + ((d - 800) / 400.0) * 900)
	if d <= 1800:
		return int(1500 + ((d - 1200) / 600.0) * 2500)
	return int(4000 + min(1.0, (d - 1800) / 1028.0) * 6000)


func _radius_for_level(ws, lvl: int, use_old: bool) -> int:
	for r in range(1, 2829):
		var got: int = _old_curve(float(r)) if use_old else ws._distance_to_level(float(r))
		if got >= lvl:
			return r
	return 2828


func _init() -> void:
	var cm = ChunkManagerScript.new()
	get_root().add_child(cm)
	cm.load_world_seed()
	cm.load_npc_posts()
	var ws = WorldSystemScript.new()
	get_root().add_child(ws)
	ws.chunk_manager = cm
	cm.terrain_generator = ws

	print("\n===== HOW FAR OUT IS COUNTRY AT YOUR LEVEL? =====")
	print("radius from the ORIGIN at which the base curve first reaches each level.")
	print("%7s %10s %10s %9s" % ["level", "was", "now", "change"])
	for lvl in [5, 10, 20, 50, 100, 250, 500, 1000, 2500, 5000]:
		var was := _radius_for_level(ws, lvl, true)
		var now := _radius_for_level(ws, lvl, false)
		print("%7d %10d %10d %+8d" % [lvl, was, now, now - was])

	print("\n===== BUT A PLAYER SETS OUT FROM A POST, NOT THE ORIGIN =====")
	# The honest version of the question. Posts sit all over the map, so the walk that matters is
	# from the nearest post to country at your level - and menace means level varies at a given
	# radius, so this samples the real function rather than inverting the curve.
	var posts: Array = cm.get_npc_posts()
	print("%7s %14s %16s" % ["level", "nearest post", "tiles to walk"])
	for lvl in [10, 25, 50, 100, 300, 1000]:
		var best := 1 << 30
		var best_post := ""
		for p in posts:
			var px := int(p.get("x", 0))
			var py := int(p.get("y", 0))
			# Search outward from this post for ground within +/-20% of the target level.
			for rad in range(10, 700, 10):
				var found := false
				for step in range(0, 12):
					var a: float = float(step) / 12.0 * TAU
					var gx: int = px + int(cos(a) * float(rad))
					var gy: int = py + int(sin(a) * float(rad))
					var got: int = ws.get_post_anchored_level(gx, gy)
					if absf(float(got - lvl)) <= float(lvl) * 0.2:
						found = true
						break
				if found:
					if rad < best:
						best = rad
						best_post = String(p.get("name", "?"))
					break
		if best < (1 << 30):
			print("%7d %14s %13d tiles" % [lvl, best_post.substr(0, 13), best])
		else:
			print("%7d %14s %16s" % [lvl, "-", "none within 700"])

	print("\nThe second table is the one that matters: a player standing at a post asks how far to")
	print("ground worth fighting, not how far from the middle of the world.")
	quit(0)
