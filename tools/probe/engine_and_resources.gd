extends SceneTree
## Does a same-level fight last TWO engine cycles, and do resources ever bind?
##
## Owner direction 2026-09-12:
##   "Fight length should normally be long enough for you to engage with your engine a couple of
##    times if you're fighting enemies of your level... Ability resource costs likely need looked
##    at as well to avoid resource costs being too free. If a fight runs long you should be
##    struggling a bit for resources. I'm not worried about health cost."
##
## Measures the three things that direction is made of, and NOT health cost:
##   * TURNS per same-level fight;
##   * ENGINE SPENDS per fight - the engine dropping sharply is the moment a class gets to USE
##     what it has been building. Two per fight is the target;
##   * whether RESOURCES BIND - the share of turns that fall back to a basic attack, and the
##     LOWEST the bar ever reaches as a share of its pool. A bar that never drops is decoration.
##
## ⚑ THE PLAYER HERE IS `make_char(level, "average", klass)` WITH THE SAME GUARDS AS
## `_role_fight_stats`, and that is not a detail. The first version of this probe asked for gear
## profile "typical", which is not one of the profiles `make_char` accepts ("under", "gearless",
## "average", "bis", "kit", the rarity names, the starter kits) - so it fell through to the
## default and measured a NAKED character. It then also built a "grown" comparison by forcing
## `ch.level += 1` in a loop, which levels a character without giving it anything to wear.
## Both columns were measuring an unarmed player, and the 1.1-1.7 turn fights they produced at
## L100 were not fast kills - they were the character dying. Read as "fights are too short", it
## would have been exactly backwards.
const SimScript = preload("res://tools/combat_simulator/real_combat_sim.gd")

const LEVELS := [1, 5, 20, 100, 1000]
const FIGHTS := 14
## An engine drop of at least this much in one turn is a SPEND rather than decay.
const SPEND_DROP := 2


func _cur_resource(ch) -> int:
	match ch.get_class_path():
		"trickster": return int(ch.current_energy)
		"mage": return int(ch.current_mana)
		_: return int(ch.current_stamina)


func _init() -> void:
	var sim = SimScript.new()
	print("\n===== ENGINE CYCLES AND RESOURCE PRESSURE =====")
	print("same-level NORMAL monster, reference player with `average` gear - the player the")
	print("monster curve is calibrated against, fought exactly the way the calibration fights it.")
	print("target: ~2 engine spends a fight; resources should BIND when a fight runs long")
	print("%-10s %5s %7s %7s %7s %8s %8s %8s" % [
		"class", "lvl", "turns", "win%", "spends", "atk/t", "minRes%", "endRes%"])
	var totals := {}
	for row in sim.ALL_CLASSES:
		var klass := String(row[0])
		for lvl in LEVELS:
			var turns_sum := 0
			var spends_sum := 0
			var atks := 0
			var wins := 0
			var min_res_sum := 0.0
			var end_res_sum := 0.0
			var done := 0
			for f in range(FIGHTS):
				var ch = sim.make_char(lvl, "average", klass, "Human")
				ch.current_hp = ch.get_total_max_hp()
				ch.in_combat = false
				var pool: int = maxi(1, sim._class_max_resource(ch, klass))
				var monster = sim.make_monster(lvl, "normal", 1.0)
				sim.combat_mgr.start_combat(0, ch, monster)
				if not sim.combat_mgr.active_combats.has(0):
					continue
				var combat = sim.combat_mgr.active_combats[0]
				var t := 0
				var prev_eng := 0
				var spends := 0
				var min_res := pool
				while t < 400:
					if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 \
							or combat.get("combat_ended", false):
						break
					t += 1
					var acted := false
					var hand: Array = (combat.get("combat_hand", []) as Array).duplicate()
					if combat.get("player_can_act", true):
						acted = true
						match ch.get_class_path():
							"trickster": sim._player_act_trickster(combat, ch)
							"mage": sim._player_act_mage(combat, ch)
							_: sim._player_act(combat, ch)
					if acted:
						var newhand: Array = combat.get("combat_hand", [])
						var played := false
						for c in hand:
							if not newhand.has(c):
								played = true
								break
						if not played:
							atks += 1
					var eng: int = int(combat.get("momentum", 0)) + int(combat.get("combo", 0)) \
						+ int(combat.get("focus", 0))
					if prev_eng - eng >= SPEND_DROP:
						spends += 1
					prev_eng = eng
					min_res = mini(min_res, _cur_resource(ch))
					if int(monster.get("current_hp", 0)) <= 0:
						break
					sim._monster_turn_if_owed(combat)
				turns_sum += t
				spends_sum += spends
				if int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0:
					wins += 1
				min_res_sum += 100.0 * float(min_res) / float(pool)
				end_res_sum += 100.0 * float(_cur_resource(ch)) / float(pool)
				done += 1
				sim.combat_mgr.end_combat(0, false, false)
			if done == 0:
				continue
			var d := float(done)
			var tf := maxf(1.0, float(turns_sum))
			print("%-10s %5d %7.1f %6.0f%% %7.2f %8.2f %7.0f%% %7.0f%%" % [
				klass, lvl, float(turns_sum) / d, 100.0 * float(wins) / d,
				float(spends_sum) / d, float(atks) / tf, min_res_sum / d, end_res_sum / d])
			if not totals.has(lvl):
				totals[lvl] = {"t": 0.0, "s": 0.0, "a": 0.0, "m": 0.0, "e": 0.0, "w": 0.0, "n": 0.0}
			totals[lvl]["t"] += float(turns_sum) / d
			totals[lvl]["s"] += float(spends_sum) / d
			totals[lvl]["a"] += float(atks) / tf
			totals[lvl]["m"] += min_res_sum / d
			totals[lvl]["e"] += end_res_sum / d
			totals[lvl]["w"] += 100.0 * float(wins) / d
			totals[lvl]["n"] += 1.0

	print("\n----- averaged across all nine classes -----")
	print("%5s %8s %7s %8s %8s %9s %9s" % ["lvl", "turns", "win%", "spends", "atk/t", "minRes%", "endRes%"])
	for lvl in LEVELS:
		if not totals.has(lvl):
			continue
		var a: Dictionary = totals[lvl]
		var n: float = maxf(1.0, float(a["n"]))
		print("%5d %8.1f %6.0f%% %8.2f %8.2f %8.0f%% %8.0f%%" % [
			lvl, float(a["t"]) / n, float(a["w"]) / n, float(a["s"]) / n,
			float(a["a"]) / n, float(a["m"]) / n, float(a["e"]) / n])
	print("\nspends << 2: the fight ends before the class uses its engine twice.")
	print("atk/t near 0 AND minRes%% high together: the resource bar never binds.")
	quit(0)
