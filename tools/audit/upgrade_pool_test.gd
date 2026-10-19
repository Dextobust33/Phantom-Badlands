# Is the pool big enough that repeats are rare? (owner's stated requirement)
extends SceneTree
const CU = preload("res://shared/card_upgrades.gd")
func _init():
	seed(4)
	print("\n=== POOL SIZE BY CARD KIND ===")
	for kind in [CU.KIND_DAMAGE, CU.KIND_BUFF, CU.KIND_CONTROL, CU.KIND_ANY]:
		var early := CU.eligible(kind, 1, []).size()
		var late := CU.eligible(kind, 5, []).size()
		print("  %-8s  milestone 1: %2d eligible   milestone 5: %2d (trade-offs unlocked)" % [kind, early, late])

	print("\n=== A DAMAGE CARD'S FIRST SIX RANK-UPS (picking the first offer each time) ===")
	var taken: Array = []
	for m in range(1, 7):
		var ch := CU.draw_choices(CU.KIND_DAMAGE, m, taken)
		var names: Array = []
		for u in ch:
			names.append(String(u["name"]) + ("*" if bool(u.get("tradeoff", false)) else ""))
		print("  milestone %d: %s" % [m, "  |  ".join(names)])
		if not ch.is_empty():
			taken.append(String(ch[0]["id"]))
	print("  (* = trade-off; none appear before milestone %d)" % CU.TRADEOFF_MIN_MILESTONE)

	print("\n=== HOW OFTEN DOES A MENU REPEAT? (1000 sims of 4 milestones) ===")
	var dupes := 0
	var runs := 1000
	for i in range(runs):
		var t: Array = []
		var seen := {}
		var rep := false
		for m in range(1, 5):
			var ch := CU.draw_choices(CU.KIND_DAMAGE, m, t)
			var key := ""
			var ids: Array = []
			for u in ch: ids.append(String(u["id"]))
			ids.sort(); key = "|".join(ids)
			if seen.has(key): rep = true
			seen[key] = true
			if not ch.is_empty(): t.append(String(ch[0]["id"]))
		if rep: dupes += 1
	print("  identical menu seen twice in 4 rank-ups: %.1f%% of runs" % (100.0*float(dupes)/float(runs)))
	quit()
