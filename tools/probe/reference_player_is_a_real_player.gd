extends SceneTree
## ⛑ IS THE PLAYER THE CURVE IS FITTED AGAINST THE PLAYER WHO IS DYING?
##
## The deck check passed - every class deals from exactly its curated five. So the cards are not
## why `speciescal` measures 100% win at levels 1-10 while the live death log shows **40 of 50
## deaths in that band**. Something else about the reference player is wrong.
##
## ⚑ THE GROUND TRUTH IS NOT A MODEL. `tools/death_log_audit.py` reads the live server's own
## leaderboard: every real character that has actually died, with the HP bar it brought and the
## damage it was dealing. Those are the numbers the reference player has to match, and nothing in
## the chain compares them - the chain measures the reference player against itself, which is why
## a wrong reference is invisible to it.
##
## WHAT IT PRINTS: for each class at levels 1-10, what `make_char(level, "average", ...)` actually
## builds - max HP, attack, how many of seven gear slots are filled, and the damage it lands in one
## real round against a real monster. Against the live figures, stated in the constants below so
## the comparison is explicit rather than remembered.
##
## Run:
##   godot --headless --path . --script res://tools/probe/reference_player_is_a_real_player.gd

const SimScript := preload("res://tools/combat_simulator/real_combat_sim.gd")

## Measured from the live death log, 2026-09-18, current-era deaths at levels 1-9.
const LIVE_L1_9_HP := 113.0
const LIVE_L1_9_DMG_PER_ROUND := 35.0

const SLOTS := ["weapon", "armor", "shield", "helm", "boots", "ring", "amulet"]


func _init() -> void:
	var sim = SimScript.new()
	var classes: Array = []
	for row in sim.ALL_CLASSES:
		classes.append(String(row[0]))
	classes.sort()

	print("")
	print("===== THE REFERENCE PLAYER THE CURVE IS FITTED AGAINST =====")
	print("  live characters that DIED at L1-9 carried ~%d HP and dealt ~%d damage a round."
		% [int(LIVE_L1_9_HP), int(LIVE_L1_9_DMG_PER_ROUND)])
	print("")
	print("  %-10s %-4s %7s %7s %7s %7s" % ["class", "lvl", "maxHP", "atk", "slots", "dmg/rnd"])

	for lvl in [1, 3, 5, 10]:
		var hp_tot := 0.0
		var dmg_tot := 0.0
		var slot_tot := 0.0
		var n := 0
		for klass in classes:
			# Average several rolls - "average" gear rolls each slot's rarity, so one sample is a
			# coin toss rather than a measurement.
			var hp_s := 0.0
			var atk_s := 0.0
			var slots_s := 0.0
			var dmg_s := 0.0
			var reps := 8
			for r in range(reps):
				var ch = sim.make_char(lvl, "average", klass, "Human")
				ch.in_combat = false
				ch.current_hp = ch.get_total_max_hp()
				hp_s += float(ch.get_total_max_hp())
				atk_s += float(ch.get_effective_stat("strength"))
				var filled := 0
				for s in SLOTS:
					if ch.equipped.get(s, null) != null:
						filled += 1
				slots_s += float(filled)
				# One real round against a real monster of the same level.
				var mon = sim.make_monster(lvl, "normal", 1.0)
				sim.combat_mgr.start_combat(0, ch, mon)
				if sim.combat_mgr.active_combats.has(0):
					var combat = sim.combat_mgr.active_combats[0]
					var before: int = int(mon.get("current_hp", 0))
					match ch.get_class_path():
						"trickster": sim._player_act_trickster(combat, ch)
						"mage": sim._player_act_mage(combat, ch)
						_: sim._player_act(combat, ch)
					dmg_s += float(before - int(mon.get("current_hp", 0)))
					sim.combat_mgr.end_combat(0, false, false)
					sim.combat_mgr.active_combats.erase(0)
			var hp := hp_s / reps
			var dmg := dmg_s / reps
			print("  %-10s %-4d %7d %7d %7.1f %7.1f"
				% [klass, lvl, int(hp), int(atk_s / reps), slots_s / reps, dmg])
			hp_tot += hp
			dmg_tot += dmg
			slot_tot += slots_s / reps
			n += 1
		print("  %-10s %-4d %7d %7s %7.1f %7.1f   <== MEAN"
			% ["ALL", lvl, int(hp_tot / n), "", slot_tot / n, dmg_tot / n])
		print("")

	print("  A reference player far above the live figures means the monsters were fitted to")
	print("  somebody stronger than the people dying to them.")
	print("")
	quit()
