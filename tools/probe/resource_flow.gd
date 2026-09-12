extends SceneTree
## Where does the resource bar actually GO during a fight?
##
## Two earlier numbers disagreed and one of them had to be wrong:
##   * `_build_ability_cost_info` prices a card at 11-27% of the pool, and `apply_variable_cost`
##     says it "spend[s] max-affordable up to ceiling" - so a cast is expensive and not optional;
##   * yet the bar never drops below half and no turn ever falls back to a basic attack.
## Both cannot hold unless the bar is REFILLING as fast as it drains. An earlier probe measured
## regen as 0.0%/turn, which would make it impossible - so that measurement is the suspect.
##
## This stops inferring and watches the bar every turn: what a cast actually takes, what comes
## back, and how the two compare. Spend and regen are read as deltas on the character, so
## whatever mechanism moves the bar is captured whether or not this probe knows its name.
const SimScript = preload("res://tools/combat_simulator/real_combat_sim.gd")

const LEVELS := [1, 20, 100, 1000]
const FIGHTS := 10


func _cur(ch) -> int:
	match ch.get_class_path():
		"trickster": return int(ch.current_energy)
		"mage": return int(ch.current_mana)
		_: return int(ch.current_stamina)


func _init() -> void:
	var sim = SimScript.new()
	print("\n===== RESOURCE FLOW PER FIGHT =====")
	print("spend/cast and regen/turn as a %% of max pool, read as deltas on the character.")
	print("If regen/turn is close to spend/cast, the bar cannot bind however expensive a card is.")
	print("%-10s %5s %8s %10s %11s %10s %9s" % [
		"class", "lvl", "pool", "casts", "spend/cast", "regen/turn", "net/turn"])
	var avg := {}
	for row in sim.ALL_CLASSES:
		var klass := String(row[0])
		for lvl in LEVELS:
			var casts := 0
			var turns := 0
			var spent := 0
			var regen := 0
			var pool := 1
			var done := 0
			for f in range(FIGHTS):
				var ch = sim.make_char(lvl, "average", klass, "Human")
				ch.current_hp = ch.get_total_max_hp()
				ch.in_combat = false
				pool = maxi(1, sim._class_max_resource(ch, klass))
				var mon = sim.make_monster(lvl, "normal", 1.0)
				sim.combat_mgr.start_combat(0, ch, mon)
				if not sim.combat_mgr.active_combats.has(0):
					continue
				var combat = sim.combat_mgr.active_combats[0]
				var t := 0
				while t < 400:
					if ch.current_hp <= 0 or int(mon.get("current_hp", 0)) <= 0 \
							or combat.get("combat_ended", false):
						break
					t += 1
					var before: int = _cur(ch)
					var hand: Array = (combat.get("combat_hand", []) as Array).duplicate()
					if combat.get("player_can_act", true):
						match ch.get_class_path():
							"trickster": sim._player_act_trickster(combat, ch)
							"mage": sim._player_act_mage(combat, ch)
							_: sim._player_act(combat, ch)
					var after_act: int = _cur(ch)
					var newhand: Array = combat.get("combat_hand", [])
					var played := false
					for c in hand:
						if not newhand.has(c):
							played = true
							break
					if played:
						casts += 1
					# Anything the bar LOST across the action is spend; anything it GAINED is
					# regen, wherever it came from.
					if after_act < before:
						spent += before - after_act
					else:
						regen += after_act - before
					if int(mon.get("current_hp", 0)) <= 0:
						break
					var before_mon: int = _cur(ch)
					sim._monster_turn_if_owed(combat)
					var after_mon: int = _cur(ch)
					if after_mon > before_mon:
						regen += after_mon - before_mon
					else:
						spent += before_mon - after_mon
				turns += t
				done += 1
				sim.combat_mgr.end_combat(0, false, false)
			if done == 0 or casts == 0:
				continue
			var spc := 100.0 * float(spent) / float(casts) / float(pool)
			var rpt := 100.0 * float(regen) / maxf(1.0, float(turns)) / float(pool)
			var net := 100.0 * float(spent - regen) / maxf(1.0, float(turns)) / float(pool)
			print("%-10s %5d %8d %10.1f %10.1f%% %9.1f%% %8.1f%%" % [
				klass, lvl, pool, float(casts) / float(done), spc, rpt, net])
			if not avg.has(lvl):
				avg[lvl] = {"s": 0.0, "r": 0.0, "n": 0.0, "net": 0.0}
			avg[lvl]["s"] += spc
			avg[lvl]["r"] += rpt
			avg[lvl]["net"] += net
			avg[lvl]["n"] += 1.0

	print("\n----- averaged across all nine classes -----")
	print("%5s %12s %12s %12s %18s" % ["lvl", "spend/cast", "regen/turn", "net/turn", "turns to empty"])
	for lvl in LEVELS:
		if not avg.has(lvl):
			continue
		var a: Dictionary = avg[lvl]
		var n: float = maxf(1.0, float(a["n"]))
		var net: float = float(a["net"]) / n
		var tte: String = "never" if net <= 0.05 else ("%.1f" % (100.0 / net))
		print("%5d %11.1f%% %11.1f%% %11.1f%% %18s" % [
			lvl, float(a["s"]) / n, float(a["r"]) / n, net, tte])
	print("\n'turns to empty' is the whole question: if it exceeds the fight length, the bar is")
	print("decoration. Fight length measured separately: ~4 turns at L1 rising to ~12 at L1000.")
	quit(0)
