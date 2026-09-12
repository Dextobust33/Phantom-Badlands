extends SceneTree
## Is L1 reachable, or is the multiplier not the knob?
##
## rolecal left L1 at exactly `seed x 1.35^(0.75*6)` = seed x 3.86 for all three roles - the most
## its correction loop can travel - and still measured empowered 65%/50%, elite 70%/40%, boss
## 56%/30%. So L1 is SATURATED, not converged.
##
## Before spending another 30-40 minutes on a re-run with more range, answer the cheaper question:
## does raising str_mult at L1 actually move the win rate, and how far does it have to go? If the
## win rate barely responds, the multiplier is not the knob (monster strength at L1 is small and
## passes through `max(3, int(...))`, so it can quantise away) and more passes would be wasted.
const SimScript = preload("res://tools/combat_simulator/real_combat_sim.gd")

const SWEEP := [1.0, 3.86, 8.0, 16.0, 32.0, 64.0]
const TARGET := {"empowered": 0.50, "elite": 0.40, "boss": 0.30}
const HP := {"empowered": 1.4, "elite": 1.8, "boss": 2.8}


func _init() -> void:
	var sim = SimScript.new()
	var n: int = maxi(30, int(sim._audit_n))
	print("[L1REACH] level 1, n=%d per point. Written by rolecal: x3.86 of seed." % n)
	print("%-11s %9s %8s %8s" % ["role", "str_mult", "win%", "target"])
	var responded := {}
	for role in ["empowered", "elite", "boss"]:
		var first := -1.0
		var last := -1.0
		var reached := 0.0
		for m in SWEEP:
			sim.monster_db.set_calibrated_role_multipliers({
				role: [{"level": 1, "hp_mult": HP[role], "str_mult": m}]})
			var r: Dictionary = sim._role_fight_stats(1, role, n)
			sim.monster_db.set_calibrated_role_multipliers({})
			if r.is_empty():
				print("%-11s %9.2f   (no data)" % [role, m])
				continue
			var w := float(r["win"])
			if first < 0.0:
				first = w
			last = w
			print("%-11s %9.2f %7.0f%% %7.0f%%%s" % [role, m, w * 100.0, TARGET[role] * 100.0,
				"   <- at or under target" if w <= TARGET[role] else ""])
			if w <= TARGET[role] and reached == 0.0:
				reached = m
		responded[role] = {"drop": first - last, "reached": reached}
	print("")
	for role in responded:
		var d: Dictionary = responded[role]
		print("[L1REACH] %-10s win fell %.0fpp across the sweep; target first met at x%s" % [
			role, float(d["drop"]) * 100.0,
			("%.0f" % float(d["reached"])) if float(d["reached"]) > 0.0 else "NEVER"])
	print("\n[L1REACH] If a role never meets target even at x64, str_mult is not the knob at L1")
	print("[L1REACH] and a longer rolecal would burn 40 minutes to land in the same place.")
	quit(0)
