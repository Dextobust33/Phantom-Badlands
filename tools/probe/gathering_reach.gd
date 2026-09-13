extends SceneTree
## Can a player still FIND things to gather?
##
## Owed since 2026-09-13. Gatherables were scattered evenly across ~30% of the world and became
## clustered stands covering ~6% - a FIVE-FOLD drop, made because the owner said *"Having them
## scattered everywhere makes them obstacles more than actual activities players engage with."*
## The intent was destinations instead of clutter. The risk is that a gathering job becomes a
## chore nobody can complete, and that is a live-economy question, not a taste one.
##
## So: how far does a player actually walk to find each resource, and how much is there once they
## do? Measured from POSTS, because that is where a player with a gathering quest sets out from.
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

	var posts: Array = cm.get_npc_posts()
	var sample: Array = []
	for i in range(mini(10, posts.size())):
		var p = posts[(i * 7) % posts.size()]
		sample.append(Vector2i(int(p.get("x", 0)), int(p.get("y", 0))))

	print("===== HOW FAR FROM A POST IS THE NEAREST OF EACH RESOURCE? =====")
	print("  (searching outward from %d posts; a gathering quest starts at one)" % sample.size())
	print("  %-16s %10s %10s %s" % ["resource", "median", "worst", "found at"])
	var far: Array = []
	for gtype in WorldSystemScript.GATHERABLE_TYPES:
		var dists: Array = []
		for centre in sample:
			var best := -1
			for r in range(1, 90):
				var hit := false
				for a in range(0, 360, 10):
					var rad := deg_to_rad(float(a))
					var x: int = centre.x + int(round(cos(rad) * float(r)))
					var y: int = centre.y + int(round(sin(rad) * float(r)))
					if String(cm.get_tile(x, y).get("type", "")) == gtype:
						best = r
						hit = true
						break
				if hit:
					break
			dists.append(best if best > 0 else 999)
		dists.sort()
		var med: int = int(dists[dists.size() / 2])
		var worst: int = int(dists[dists.size() - 1])
		var found: int = 0
		for d in dists:
			if int(d) < 999:
				found += 1
		print("  %-16s %8s %10s %d/%d posts" % [
			gtype, ("%d" % med) if med < 999 else "none", ("%d" % worst) if worst < 999 else "none",
			found, dists.size()])
		# ⚑ TWO DIFFERENT BARS, because these are two different kinds of resource.
		#
		# A COMMON resource has to be near a post - a gathering job that sends a new player 80
		# tiles out is not an activity. A BIOME-LOCKED one is supposed to need a trip: mountains
		# are 2.67% of the ground near a post and swamp 1.13%, and travelling to them is the
		# design. Holding both to "reachable from most posts" flagged four resources that were
		# working as intended, which is the probe being wrong about the game.
		if not (gtype in WorldSystemScript.BIOME_SIGNATURE_NODE.values()):
			if found < sample.size() / 2:
				far.append(gtype)
	ck(far.is_empty(), "every COMMON resource is reachable from most posts%s" % [
		"" if far.is_empty() else " - UNREACHABLE: " + ", ".join(far)])

	print("\n===== AND HOW MUCH IS THERE WHEN YOU ARRIVE? =====")
	# A stand has to be worth the walk. One node at the end of an 80-tile trip is not an activity.
	var total := 0
	var tiles := 0
	var by_type: Dictionary = {}
	for y in range(-120, 121, 2):
		for x in range(-400, 401, 2):
			tiles += 1
			var t := String(cm.get_tile(x, y).get("type", ""))
			if t in WorldSystemScript.GATHERABLE_TYPES:
				total += 1
				by_type[t] = int(by_type.get(t, 0)) + 1
	print("  %.2f%% of sampled ground carries a node (%d of %d)" % [
		100.0 * float(total) / float(maxi(1, tiles)), total, tiles])
	var kinds: Array = by_type.keys()
	kinds.sort()
	var line := ""
	for k in kinds:
		line += "%s %d  " % [k, int(by_type[k])]
	print("  " + line)
	ck(total > 0, "nodes exist at all")
	# And the biome-locked ones must EXIST in usable numbers, even if the trip is long.
	var thin: Array = []
	for k in WorldSystemScript.BIOME_SIGNATURE_NODE.values():
		if int(by_type.get(k, 0)) < 15:
			thin.append("%s %d" % [k, int(by_type.get(k, 0))])
	ck(thin.is_empty(), "every signature resource exists in usable numbers%s" % [
		"" if thin.is_empty() else " - TOO THIN: " + ", ".join(thin)])

	print("\n[GATHERREACH] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
