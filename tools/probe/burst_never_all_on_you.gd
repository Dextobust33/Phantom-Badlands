extends SceneTree
## Can a multi-hit round land entirely on the player?
##
## Owner 2026-09-14: *"for swift enemies can we make sure the hits can be divided up ... Maybe it
## targets you with 2 of the 3 hits it did that round and 1 to your companion."*
##
## Swift grants MULTI_STRIKE, and each of its 2-3 hits deals FULL damage - so a Swift monster's
## round is 2-3x a normal one. The per-hit companion roll was already here, but at the default 25%
## aggro all three land on the player 0.75^3 = 42% of the time, and that round is the one that
## reads as a one-shot. Independent rolls have no memory: nothing stopped the worst case coming up
## twice running.
const CM = preload("res://shared/combat_manager.gd")

var fails := 0
func ck(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
	print(("  PASS  " if ok else "  FAIL  ") + msg)


func _init() -> void:
	print("===== THE ARITHMETIC THAT MADE THIS A PROBLEM =====")
	var aggro := 0.25
	var all_on_player := pow(1.0 - aggro, 3.0)
	print("  3 hits, %d%% aggro, rolled independently -> all three on the player %.0f%% of rounds"
		% [int(aggro * 100.0), all_on_player * 100.0])
	ck(all_on_player > 0.25, "which is often enough to be the thing players remember")

	print("")
	print("===== THE GUARANTEE =====")
	var src := FileAccess.get_file_as_string("res://shared/combat_manager.gd")
	ck(src.contains("if comp_hits == 0 and _remaining.size() >= 2:"),
		"a multi-hit round that rolled nothing onto the companion gives it one anyway")
	ck(src.contains("_remaining.remove_at(0)"),
		"  moved, not duplicated - the player stops taking that hit")
	# The bound matters: a single-hit round has nothing to divide, and taking its only hit away
	# would mean an ordinary monster could never touch the player while a companion was out.
	ck(src.contains(">= 2"), "and a SINGLE-hit round is left alone - there is nothing to divide")

	print("")
	print("===== SIMULATED OVER MANY ROUNDS =====")
	# Model the same rule the code applies, so the shape of the outcome is visible rather than
	# argued. This is arithmetic, not the combat path - `guide_shields_on_the_real_path.gd` is
	# the file that drives the real one.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for hits in [1, 2, 3]:
		var worst := 0
		var to_player_total := 0
		var n := 4000
		for i in range(n):
			var rem: Array = []
			var comp := 0
			for h in range(hits):
				if rng.randf() < aggro:
					comp += 1
				else:
					rem.append(1)
			if comp == 0 and rem.size() >= 2:
				comp += 1
				rem.remove_at(0)
			if rem.size() == hits:
				worst += 1
			to_player_total += rem.size()
		var pct_worst := 100.0 * worst / float(n)
		var avg := float(to_player_total) / float(n)
		print("  %d-hit round: player eats ALL of it %.0f%% of the time, average %.2f hits"
			% [hits, pct_worst, avg])
		if hits >= 2:
			ck(pct_worst < 1.0, "  a %d-hit burst never all lands on the player" % hits)
		else:
			ck(pct_worst > 50.0, "  a 1-hit round still mostly hits the player (control)")

	print("")
	print("----- NOT COVERED HERE -----")
	print("  A player with NO companion - which is every character during the tutorial, since the")
	print("  egg is paid at step three. There is nothing to divide onto, so a Swift monster is")
	print("  still 2-3 full hits there. That is what the escort exists to absorb.")

	print("")
	if fails == 0:
		print("PASS - a multi-hit burst is always shared when there is somebody to share it with")
	else:
		print("FAIL - %d check(s) failed" % fails)
	quit(1 if fails > 0 else 0)
