extends SceneTree
## Owner 2026-10-14: the monster level band around a spot should be a tighter PERCENTAGE (not a flat
## cap - "5 levels later doesn't mean as much at later levels"). It was +/-10%, so far from the centre
## "around your level" stopped existing (+/-9 levels at L91, +/-50 at L500). Now +/-5%, floor 1 level.
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
const WorldSystemScript = preload("res://shared/world_system.gd")
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
	var checked := 0
	var worst_pct := 0.0
	var bad := 0
	var wide_levels := 0
	# walk outward along several bearings so the base level spans low to very high
	for bearing in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(1, 1)]:
		for dist in [40, 120, 300, 700, 1500, 3000, 6000]:
			var x := int(bearing.x * dist)
			var y := int(bearing.y * dist)
			var r: Dictionary = ws.get_monster_level_range(x, y)
			var base: int = int(r.get("base_level", 0))
			if base <= 0:
				continue
			checked += 1
			var half: int = maxi(1, int(base * 0.05))
			if int(r.min) < maxi(1, base - half) or int(r.max) > mini(10000, base + half):
				bad += 1
			# the 1-level FLOOR makes a low base look wide (1 level on L5 is 20%); the percentage claim
			# only means something where 5% is at least 2 levels
			if base >= 40:
				worst_pct = maxf(worst_pct, float(int(r.max) - base) / float(base))
			if base >= 100:
				wide_levels += 1
	ck(checked >= 10, "sampled %d spots across the world" % checked)
	ck(bad == 0, "every band is within base +/- max(1, 5%%) (%d out of range)" % bad)
	ck(worst_pct <= 0.0501, "on ground at L40+ the widest upper edge seen is %.1f%% above the base - never more than 5%%" % (worst_pct * 100.0))
	ck(wide_levels >= 3, "and it was measured on high-level ground too (%d spots at L100+), not just near the centre" % wide_levels)
	print("PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
