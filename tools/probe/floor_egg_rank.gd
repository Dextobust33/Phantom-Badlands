extends SceneTree
## A deeper dungeon must be a better place to find an egg.
##
## Owner 2026-09-11: *"each of those higher ranked ones should ideally have a higher chance to
## drop higher rank eggs (we should check this and fix it if they don't)."* They did not. A
## dungeon floor rolled `1 + randi() % 8` - a uniform rank that ignored the dungeon completely,
## so an H1 and an H9 handed out identical eggs and the only thing climbing ranks bought was the
## single boss egg at the end.
##
## Egg rank becomes the companion's `sub_tier`, which is worth up to 2x its stats and 2x the
## bonuses it grants its owner, so this was the reward for the whole climb going missing.
##
## What this holds: the floor-egg rank RISES with the dungeon's rank, reaches 9, never leaves
## 1-9, and still varies. "Higher chance", not "always exactly".
const SRC := "res://server/server.gd"
const PR := preload("res://shared/power_rank.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


## The shipped rule, read off the source rather than re-typed - the constants are the thing the
## owner will tune, and a probe holding its own copy of them would stop testing the game.
var spread_down := 0
var spread_up := 0

func floor_egg_rank(dungeon_rank: int) -> int:
	var r: int = clampi(dungeon_rank, 1, PR.RANKS)
	var lo: int = maxi(1, r - spread_down)
	var hi: int = mini(PR.RANKS, r + spread_up)
	return lo + (randi() % (hi - lo + 1))


func _init() -> void:
	var src := FileAccess.get_file_as_string(SRC)

	print("--- the old uniform roll is gone ---")
	ck(src.find("var egg_sub := 1 + (randi() % 8)") < 0,
		"no floor egg rolls a rank that ignores its dungeon")
	ck(src.find("_floor_egg_rank(sub_tier)") >= 0, "the floor egg asks for the dungeon's rank")
	ck(src.find("func _floor_egg_rank(") >= 0, "and one function decides what that means")
	# `sub_tier` was a DEAD parameter on _roll_floor_item - passed by three call sites, read by
	# none. That is what let the fault sit unnoticed.
	var i0 := src.find("func _roll_floor_item(")
	var i1 := src.find("\nfunc ", i0 + 10)
	ck(i0 > 0 and src.substr(i0, i1 - i0).find("sub_tier") >= 0,
		"_roll_floor_item finally READS the sub_tier it has always been handed")

	for line in src.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("const FLOOR_EGG_RANK_SPREAD_DOWN"):
			spread_down = int(t.split(":=")[1].strip_edges())
		elif t.begins_with("const FLOOR_EGG_RANK_SPREAD_UP"):
			spread_up = int(t.split(":=")[1].strip_edges())
	ck(spread_down >= 0 and spread_up >= 0,
		"the window is named and tunable (down %d, up %d)" % [spread_down, spread_up])

	print("\n--- a deeper dungeon really is a better place to look ---")
	var N := 4000
	var means: Array = []
	for rank in range(1, PR.RANKS + 1):
		var total := 0
		var lo := 99
		var hi := 0
		for i in range(N):
			var v := floor_egg_rank(rank)
			total += v
			lo = mini(lo, v)
			hi = maxi(hi, v)
		var mean := float(total) / float(N)
		means.append(mean)
		print("  %s%d: mean egg rank %.2f  (seen %d-%d)" % [PR.letter(1), rank, mean, lo, hi])
		ck(lo >= 1 and hi <= PR.RANKS, "rank %d never leaves 1-%d" % [rank, PR.RANKS])
	var rising := true
	for i in range(1, means.size()):
		if means[i] <= means[i - 1]:
			rising = false
	ck(rising, "every extra dungeon rank raises the average egg rank")
	ck(means[8] - means[0] > 5.0,
		"and the climb is worth making: rank 1 averages %.2f, rank 9 averages %.2f" % [means[0], means[8]])

	print("\n--- rank 9 is reachable, and it still surprises ---")
	var saw9 := false
	for i in range(2000):
		if floor_egg_rank(9) == 9:
			saw9 = true
			break
	ck(saw9, "a rank-9 dungeon can drop a rank-9 egg (the old roll capped at 8 and never could)")
	var distinct := {}
	for i in range(2000):
		distinct[floor_egg_rank(5)] = true
	ck(distinct.size() > 1, "a rank-5 dungeon still gives %d different egg ranks, not one" % distinct.size())

	print("\n[FLOOREGG] %s" % ("PASS" if fails == 0 else "FAIL - %d check(s)" % fails))
	quit(0 if fails == 0 else 1)
