extends SceneTree
# v0.9.696 WIP — headless combat sim driving the REAL shared code (Character,
# CombatManager, MonsterDatabase, DropTables) so balance data never drifts.
# Outputs avg turns-to-kill + win-rate across level × gear tier × enemy tier,
# with a representative active companion. Foundation for the tiered combat-length
# balance pass (Warrior Momentum etc.).

var drop_tables
var monster_db
var combat_mgr
var CharacterScript
# Cost-tier emulation: after each cast, drain EXTRA resource = spent×(_cost_mult-1)
# to model a higher-tier (pricier) version of the card WITHOUT editing the const
# cost table. Damage held at base → conservatively OVER-states drain (real higher
# tiers also hit harder → shorter fights → less total spend), a safe direction for
# finding the cost curve that restores early-game pressure. 1.0 = unchanged.
var _cost_mult: float = 1.0
# Martial DUMP emulation: after the finisher (Devastate / Gambit) resolves, drain this
# fraction of the CURRENT pool — models a dump finisher (consume the bar, damage scales
# with spend). 0 = off. Only the martial finisher branches apply it.
var _dump_pct: float = 0.0

const FIGHTS_PER_CELL := 200
const SLOTS := ["weapon", "armor", "helm", "shield", "boots", "ring", "amulet"]
# Warrior damage cards, best→worst; the sim casts the highest-priority one that's
# actually in the drawn hand + affordable (the deck constraint is real). Buffs
# (war_cry/berserk/iron_skin/fortify/rally) are cast opportunistically for uptime.
const WARRIOR_DMG_PRIORITY := ["devastate", "cleave", "shield_bash", "power_strike"]
const WARRIOR_BUFFS := ["berserk", "war_cry"]

func _init():
	seed(20260824)  # reproducible run-to-run (gear affixes/crits/empowered are RNG)
	drop_tables = load("res://shared/drop_tables.gd").new()
	monster_db = load("res://shared/monster_database.gd").new()
	combat_mgr = load("res://shared/combat_manager.gd").new()
	CharacterScript = load("res://shared/character.gd")
	root.add_child(drop_tables)
	root.add_child(monster_db)
	root.add_child(combat_mgr)
	var cfg: Dictionary = {}
	var f = FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			cfg = parsed
		f.close()
	combat_mgr.set_balance_config(cfg)
	combat_mgr.set_monster_database(monster_db)
	combat_mgr.drop_tables = drop_tables
	if "drop_tables" in monster_db:
		monster_db.drop_tables = drop_tables

	run_difficulty_audit()     # how far above level each class can punch + risk-vs-level curve.
	quit()

func run_overlevel_audit():
	var N := 60
	var plevels := [20, 60, 150]
	var deltas := [0, 5, 10, 20, 35, 60]
	var classes := [["Fighter", "War"], ["Wizard", "Mag"], ["Thief", "Trk"]]
	print("\n===== OVER-LEVEL REACH (%d fights/cell, AVERAGE gear, normal mob) =====" % N)
	print("Win%% vs a monster at (player level + delta). 'Reliable' ~ >=60%%. Higher delta reachable = punches further above level.")
	for pl in plevels:
		for c in classes:
			var row := "P%-4d %-4s" % [pl, c[1]]
			for d in deltas:
				var wins := 0
				for i in range(N):
					var r = run_fight(pl, "average", "normal", 1.0, 1.0, 1.0, c[0], pl + d)
					if r.win:
						wins += 1
				row += "  +%-2d:%3d%%" % [d, int(100.0 * wins / N)]
			print(row)
	print("")
	print("===== SAME-LEVEL RISK vs LEVEL (does fighting your OWN level get safer as you level?) =====")
	print("AVERAGE gear vs a same-level ELITE. Win%% / avg lowest-HP%% reached.")
	for c in classes:
		var row2 := "%-4s " % c[1]
		for pl in [10, 30, 60, 120, 250]:
			var wins := 0
			var mhp := 0.0
			for i in range(N):
				var r = run_fight(pl, "average", "elite", 1.0, 1.0, 1.0, c[0])
				if r.win:
					wins += 1
				mhp += float(r.get("min_hp_pct", 0.0))
			row2 += "| L%-3d %3d%% H%2.0f " % [pl, int(100.0 * wins / N), mhp / N]
		print(row2)
	print("=====================================================================\n")

func run_difficulty_audit():
	# Measures combat feel across level × gear × enemy-tier AFTER the #55 player changes.
	# Per cell: Win% / avg Turns / avg lowest-HP% reached / avg lowest-resource% reached.
	# Goal: normal = quick + fairly safe; elite = a real fight; boss = dangerous. And GEAR
	# should matter — an under-geared player should struggle where a bis one is comfortable.
	var N := 70
	var levels := [10, 50, 200]
	var gears := ["under", "average", "bis"]
	var enemies := ["normal", "elite", "boss"]
	var classes := [["Fighter", "War"], ["Wizard", "Mag"], ["Thief", "Trk"]]
	print("\n===== MONSTER-CHALLENGE AUDIT (%d fights/cell) =====" % N)
	print("cell = Win%% Turns MinHP%% (per gear: under | average | bis). MinHP%% = lowest HP reached.")
	for lvl in levels:
		for c in classes:
			for et in enemies:
				var row := "L%-4d %-4s %-7s" % [lvl, c[1], et]
				for gear in gears:
					var wins := 0
					var tt := 0.0
					var mhp := 0.0
					for i in range(N):
						var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, c[0])
						if r.win:
							wins += 1
						tt += float(r.turns)
						mhp += float(r.get("min_hp_pct", 0.0))
					row += "| %3d%% %4.1ft H%2.0f " % [int(100.0 * wins / N), tt / N, mhp / N]
				print(row)
	print("=====================================================================\n")

func run_proposal_read():
	# Combined proposal: REAL dumps (Devastate + Outsmart in combat_manager) + capped regen,
	# with mage cost still emulated at 2x (until cost_percent is raised for real). Shows the
	# gear-investment gradient (avg = pressured, bis = comfortable) across levels to L1000.
	_dump_pct = 0.0   # dumps are real now — no emulation
	_cost_mult = 1.0  # mage cost is now REAL (raised cost_percent) — no emulation
	run_resource_audit()

func run_hp_solve():
	# #29 — sweep an extra monster-HP multiplier (War+Trk = accurate classes) to find
	# what lands "real" fights at ~8-12t with a healthy win-rate. L50, elite/boss.
	var N := 60
	var mults := [2.0, 3.0, 4.0, 5.0]
	print("\n===== #29 MONSTER-HP SOLVE (L50, War+Trk) — avgTurns@win%% per HP mult =====")
	for c in [["Fighter", "War"], ["Thief", "Trk"]]:
		for gear in ["average", "bis"]:
			for et in ["elite", "boss"]:
				var row := "%s %-8s %-5s" % [c[1], gear, et]
				for hm in mults:
					var wins := 0
					var tt := 0
					for i in range(N):
						var r = run_fight(50, gear, et, hm, 1.0, 1.0, c[0])
						if r.win:
							wins += 1
						tt += r.turns
					row += "   %.0fx: %4.1ft@%d%%" % [hm, float(tt) / N, int(100.0 * wins / N)]
				print(row)
	print("=================================================================\n")

func run_resource_audit():
	# Resource-economy audit (2026-08-25). Answers: does the combat resource ever
	# actually BIND, and does it stay pegged high as level/gear scale (= management
	# is dead)? Headline column = MinRes% (avg lowest pool% reached in a fight). If
	# MinRes% stays high (esp. at high lvl / bis gear), the pool is never a real
	# constraint → the exact "resources stop mattering" problem. Pool = avg max pool.
	# Casts/t = ability casts per turn (near 1.0 + high MinRes% = casting freely).
	var N := 40
	var levels := [10, 50, 200, 1000]  # include EXTREME level — system must hold to L1000+
	var gears := ["average", "bis"]
	var enemies := ["elite", "boss"]
	var classes := [["Fighter", "War"], ["Thief", "Trk"], ["Wizard", "Mag"]]
	print("\n===== RESOURCE AUDIT (%d fights/cell) — does the pool ever bind? =====" % N)
	print("MinRes%% high = pool never pressured (management dead). Watch it RISE with lvl/gear.")
	print("%-4s %-4s %-8s %-6s %6s %7s %8s %8s %8s %7s" % ["Cls", "Lvl", "Gear", "Enemy", "Win%", "Turns", "Casts/t", "MinRes%", "EndRes%", "Pool"])
	for c in classes:
		for lvl in levels:
			for gear in gears:
				for et in enemies:
					var wins := 0
					var tt := 0.0
					var tc := 0.0
					var tmin := 0.0
					var tend := 0.0
					var tpool := 0.0
					for i in range(N):
						var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, c[0])
						if r.win:
							wins += 1
						tt += r.turns
						tc += float(r.get("casts", 0)) / maxf(1.0, float(r.turns))
						tmin += float(r.get("min_res_pct", 0.0))
						tend += float(r.get("end_res_pct", 0.0))
						tpool += float(r.get("max_res", 0))
					print("%-4s %-4d %-8s %-6s %5.0f%% %7.1f %8.2f %7.0f%% %7.0f%% %7.0f" % [
						c[1], lvl, gear, et, 100.0 * wins / N, tt / N, tc / N, tmin / N, tend / N, tpool / N])
	print("=====================================================================\n")

func _force_hand(combat: Dictionary, ability: String) -> void:
	var hand: Array = combat.get("combat_hand", [])
	if not (ability in hand):
		hand.append(ability)
		combat["combat_hand"] = hand

func _measure_ability(level: int, gear: String, klass: String, ability: String) -> Dictionary:
	# #55 — single cast, ability forced into hand. Returns {damage, cost, pool}.
	# GROSS cost via the `path_last_ability_cost` meta stamped in apply_variable_cost
	# (only zeroed on a KILLING blow), read off an UN-KILLABLE dummy (50× HP) so no
	# kill-refund fires and the per-round mana/stam/energy REGEN can't mask the spend
	# (net-resource delta was the old confound). magic_bolt isn't on the variable path,
	# so use its intended spend (the arg). Engines (momentum/focus/read) start at 0.
	var ch = make_char(level, gear, klass)
	var monster = make_monster(level, "boss", 50.0)  # ultra-tanky: 1 cast never kills
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return {"damage": 0.0, "cost": 0.0, "pool": 0.0}
	var combat = combat_mgr.active_combats[0]
	_force_hand(combat, ability)
	var mhp0: int = int(monster.get("current_hp", 0))
	ch.set_meta("path_last_ability_cost", 0)  # clear before cast so we read THIS cast's spend
	var arg: String = str(maxi(1, int(ch.get_total_max_mana() * 0.25))) if ability == "magic_bolt" else ""
	combat_mgr.process_ability_command(0, ability, arg)
	var dmg: int = mhp0 - int(monster.get("current_hp", 0))
	var cost: int = int(ch.get_meta("path_last_ability_cost", 0))  # GROSS spend, regen-immune
	if ability == "magic_bolt":
		cost = int(arg) if arg.is_valid_int() else 0
	var pool: int = _class_max_resource(ch, klass)  # total pool (incl gear) to show casts/bar
	combat_mgr.end_combat(0, false, false)
	return {"damage": float(dmg), "cost": float(cost), "pool": float(pool)}

func run_ability_efficiency():
	# #55 — measure damage-per-resource for each damage ability across classes + levels/gear.
	# The flagship question (Bolt vs Blast) is a SIMPLE-ability comparison; finishers
	# (devastate/meteor/gambit) scale up with their engine so their number here is a FLOOR.
	var N := 300
	var cells := [[10, "average"], [50, "average"], [50, "bis"], [200, "average"], [1000, "average"]]
	var sets := [
		["Fighter", "War", ["power_strike", "shield_bash", "cleave", "devastate"]],
		["Wizard", "Mag", ["magic_bolt", "blast", "meteor"]],
		["Thief", "Trk", ["ambush", "exploit", "gambit"]],
	]
	print("\n===== #55 ABILITY DAMAGE-PER-RESOURCE AUDIT (%d casts/cell) =====" % N)
	print("Per-cast on a boss-HP target; finishers (devastate/meteor/gambit) = FLOOR (engines at 0).")
	for cell in cells:
		var lvl: int = int(cell[0])
		var gear: String = String(cell[1])
		print("--- L%d %s ---   %-4s %-13s %9s %8s %8s %9s" % [lvl, gear, "Cls", "Ability", "AvgDmg", "AvgCost", "Dmg/Res", "Casts/Bar"])
		for s in sets:
			for ab in s[2]:
				var td := 0.0
				var tc := 0.0
				var tp := 0.0
				var samples := 0
				for i in range(N):
					var r = _measure_ability(lvl, gear, String(s[0]), String(ab))
					if r.cost > 0.0:
						td += r.damage
						tc += r.cost
						tp += r.pool
						samples += 1
				if samples > 0:
					var avg_cost := tc / samples
					var casts := (tp / samples) / maxf(1.0, avg_cost)  # #55 pool ÷ cost = casts per full bar
					print("               %-4s %-13s %9.0f %8.1f %8.2f %9.1f" % [s[1], ab, td / samples, avg_cost, (td / samples) / maxf(1.0, avg_cost), casts])
				else:
					print("               %-4s %-13s   (no paid casts — free/utility or unaffordable)" % [s[1], ab])
	print("=====================================================================\n")

func run_cost_solve():
	# COST-CURVE SOLVE (2026-08-25). For each character level on AVERAGE gear, sweep a
	# cost multiplier and read the MinRes% it produces — i.e. "how much pricier must the
	# card tier be at this level to restore early-game resource pressure?" The mult that
	# lands MinRes% in the target band (elite ~40-60%, boss ~20-40%) at each level IS the
	# level→cost-tier curve. L10 baseline (mult 1.0) is the early-game feel we're matching.
	var N := 70
	var levels := [10, 25, 50, 80]
	var mults := [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]
	var classes := [["Fighter", "War"], ["Thief", "Trk"], ["Wizard", "Mag"]]
	print("\n===== COST-CURVE SOLVE (avg gear, %d fights/cell) — MinRes%% per cost mult =====" % N)
	print("Target: elite ~40-60%%, boss ~20-40%%. Read the mult that lands there per level.")
	for c in classes:
		for et in ["elite", "boss"]:
			var hdr := "%-4s %-6s " % [c[1], et]
			for m in mults:
				hdr += "%9s" % ("%.1fx" % m)
			print(hdr)
			for lvl in levels:
				var row := "  L%-3d      " % lvl
				for m in mults:
					_cost_mult = m
					var tmin := 0.0
					var wins := 0
					for i in range(N):
						var r = run_fight(lvl, "average", et, 1.0, 1.0, 1.0, c[0])
						tmin += float(r.get("min_res_pct", 0.0))
						if r.win:
							wins += 1
					_cost_mult = 1.0
					row += "%9s" % ("%.0f@%d" % [tmin / N, int(100.0 * wins / N)])
				print(row)
	print("(cell = MinRes%%@Win%%)  =============================================\n")

func run_flock_chain(level: int, gear: String, klass: String, chain_len: int, et: String) -> Dictionary:
	# Flock STRESS: `chain_len` back-to-back fights on ONE character, resources NOT
	# refilled between members (only in-combat regen), buffs + engine state (momentum/
	# combo-read/focus) carried via the real preserve path. Mirrors an overworld flock
	# where you don't return to safety between kills. Headline = chain MinRes% (the
	# lowest pool% reached across the WHOLE chain): after decoupling regen (fix A) this
	# must NOT bottom out to ~0 or a flock becomes an un-counterable resource death.
	var ch = make_char(level, gear, klass)  # full resources at chain START only
	var max_res: int = maxi(1, _class_max_resource(ch, klass))
	var chain_min_res: int = _class_resource(ch, klass)
	var total_turns := 0
	var total_casts := 0
	var cleared := 0
	for m_idx in range(chain_len):
		var monster = make_monster(level, et)
		combat_mgr.start_combat(0, ch, monster)
		if not combat_mgr.active_combats.has(0):
			break
		var combat = combat_mgr.active_combats[0]
		if m_idx > 0:  # carry engine state into the next flock member
			var snap = combat_mgr.get_last_combat_engines(0)
			for k in ["momentum", "combo", "focus"]:
				if snap.has(k):
					combat[k] = snap[k]
		var turns := 0
		while turns < 400:
			if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
				break
			turns += 1
			if combat.get("player_can_act", true) and ch.current_hp > 0 and int(monster.get("current_hp", 0)) > 0:
				var res0: int = _class_resource(ch, klass)
				if klass == "Thief":
					_player_act_trickster(combat, ch)
				elif klass == "Wizard":
					_player_act_mage(combat, ch)
				else:
					_player_act(combat, ch)
				if _class_resource(ch, klass) < res0:
					total_casts += 1
					if _cost_mult > 1.0:
						_drain_resource(ch, klass, int((res0 - _class_resource(ch, klass)) * (_cost_mult - 1.0)))
				chain_min_res = mini(chain_min_res, _class_resource(ch, klass))
			if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
				break
			combat_mgr.process_monster_turn(combat)
		total_turns += turns
		var mwin: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
		combat_mgr.end_combat(0, mwin, true)  # preserve buffs/engines across the flock
		if not mwin or ch.current_hp <= 0:
			break
		cleared += 1
		# resources deliberately NOT refilled here — they carry to the next member.
	return {
		"cleared": cleared, "chain_len": chain_len,
		"survived": ch.current_hp > 0 and cleared == chain_len,
		"min_res_pct": 100.0 * float(chain_min_res) / float(max_res),
		"turns": total_turns, "casts": total_casts,
	}

func run_flock_audit():
	# Flock-stress audit (2026-08-25). K back-to-back trash fights, resources carried.
	# ChainMin% = lowest pool% over the whole chain; Clear = avg members cleared of K;
	# Thru% = fraction of chains fully cleared (survival). After fix A, ChainMin% is the
	# SAFETY floor — it must stay high enough that a flock isn't a resource death spiral.
	var N := 60
	var K := 5
	var levels := [10, 50, 80]
	var gears := ["under", "average", "bis"]
	var classes := [["Fighter", "War"], ["Thief", "Trk"], ["Wizard", "Mag"]]
	var et := "plain"  # flocks are trash mobs
	print("\n===== FLOCK STRESS AUDIT (%d chains/cell, K=%d back-to-back, no refill) =====" % [N, K])
	print("ChainMin%% = lowest pool%% across the whole chain (the safety floor for fix A).")
	print("%-4s %-4s %-8s %6s %8s %8s %8s" % ["Cls", "Lvl", "Gear", "Thru%", "Clear/K", "ChainMin%", "Casts/t"])
	for c in classes:
		for lvl in levels:
			for gear in gears:
				var thru := 0
				var tclear := 0.0
				var tmin := 0.0
				var tct := 0.0
				for i in range(N):
					var r = run_flock_chain(lvl, gear, c[0], K, et)
					if r.survived:
						thru += 1
					tclear += float(r.cleared)
					tmin += float(r.get("min_res_pct", 0.0))
					tct += float(r.get("casts", 0)) / maxf(1.0, float(r.turns))
				print("%-4s %-4d %-8s %5.0f%% %8.1f %8.0f%% %8.2f" % [
					c[1], lvl, gear, 100.0 * thru / N, tclear / N, tmin / N, tct / N])
	print("=====================================================================\n")

func run_baseline():
	# #29 holistic rebalance baseline — measures win-rate, fight length, AND
	# casts-per-fight (the resource lever) across all three classes.
	var N := 60
	var levels := [10, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "elite", "boss"]
	var classes := [["Fighter", "War"], ["Thief", "Trk"], ["Wizard", "Mag"]]
	print("\n===== #29 BASELINE (%d fights/cell) =====" % N)
	print("%-4s %-4s %-8s %-7s %6s %7s %7s" % ["Cls", "Lvl", "Gear", "Enemy", "Win%", "Turns", "Casts"])
	for c in classes:
		for lvl in levels:
			for gear in gears:
				for et in enemies:
					var wins := 0
					var tt := 0
					var tc := 0
					for i in range(N):
						var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, c[0])
						if r.win:
							wins += 1
						tt += r.turns
						tc += int(r.get("casts", 0))
					print("%-4s %-4d %-8s %-7s %5.0f%% %7.1f %7.1f" % [c[1], lvl, gear, et, 100.0 * wins / N, float(tt) / N, float(tc) / N])
	print("=========================================\n")

func run_matrix():
	var levels := [10, 30, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "empowered", "elite", "boss"]
	print("\n===== REAL-CODE COMBAT SIM (%d fights/cell, Fighter + companion) =====" % FIGHTS_PER_CELL)
	print("%-6s %-9s %-10s %8s %8s %10s" % ["Lvl", "Gear", "Enemy", "WinRate", "AvgTurns", "PlyrHP%%"])
	for lvl in levels:
		for gear in gears:
			for et in enemies:
				var wins := 0
				var total_turns := 0
				for i in range(FIGHTS_PER_CELL):
					var r = run_fight(lvl, gear, et, 1.0)
					if r.win:
						wins += 1
					total_turns += r.turns
				print("%-6d %-9s %-10s %7.0f%% %8.1f" % [lvl, gear, et, 100.0*float(wins)/FIGHTS_PER_CELL, float(total_turns)/FIGHTS_PER_CELL])
	print("=====================================================================\n")

func run_hp_sweep():
	# Reverse-solve: how much monster HP is needed to hit target fight lengths.
	# For well-geared players (BiS), sweep an extra HP multiplier per enemy tier.
	var mults := [1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0]
	var N := 60
	print("\n===== REVERSE-SOLVE: monster HP mult -> fight length (BiS Fighter+companion, %d fights) =====" % N)
	print("Target lengths: plain ~2-3t, empowered/elite ~6-9t, boss ~10-14t. Read the mult that hits it.")
	print("(each cell = avgTurns @ winRate%%)")
	var header := "%-14s" % "Lvl / Enemy"
	for hm in mults:
		header += "%9s" % ("%.0fx" % hm)
	print(header)
	for lvl in [30, 50, 80]:
		for et in ["plain", "empowered", "elite", "boss"]:
			var row := "%-14s" % ("L%d %s" % [lvl, et])
			for hm in mults:
				var wins := 0
				var tt := 0
				for i in range(N):
					var r = run_fight(lvl, "bis", et, hm)
					if r.win: wins += 1
					tt += r.turns
				row += "%9s" % ("%.1f@%.0f" % [float(tt)/N, 100.0*float(wins)/N])
			print(row)
	print("=================================================================================================\n")

func run_trickster_matrix():
	# v0.9.697 — validate the Trickster Combo engine (build via setups → Gambit finisher).
	var levels := [10, 30, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "empowered", "elite", "boss"]
	print("\n===== TRICKSTER COMBO SIM (%d fights/cell, Thief + companion) =====" % FIGHTS_PER_CELL)
	print("%-6s %-9s %-10s %8s %8s" % ["Lvl", "Gear", "Enemy", "WinRate", "AvgTurns"])
	for lvl in levels:
		for gear in gears:
			for et in enemies:
				var wins := 0
				var total_turns := 0
				for i in range(FIGHTS_PER_CELL):
					var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, "Thief")
					if r.win:
						wins += 1
					total_turns += r.turns
				print("%-6d %-9s %-10s %7.0f%% %8.1f" % [lvl, gear, et, 100.0*float(wins)/FIGHTS_PER_CELL, float(total_turns)/FIGHTS_PER_CELL])
	print("=====================================================================\n")

func _player_act_trickster(combat: Dictionary, ch) -> void:
	var hand: Array = combat.get("combat_hand", [])
	# OUTWIT only when the odds are actually good (chance-gated, like a real player) AND
	# energy is stocked — Outsmart now DUMPS energy to sharpen the read (+~30% at a full
	# bar). Don't burn attempts on low-odds outwits vs higher-level bosses; damage instead.
	var base_os: int = combat_mgr._outsmart_chance(ch, combat.get("monster", {}), combat)
	var full_en: bool = ch.current_energy > int(ch.get_total_max_energy() * 0.6)
	if full_en and base_os + 30 >= 70:  # +30 ≈ the full-bar dump bonus
		var r = combat_mgr.process_outsmart(combat)
		if r.get("combat_ended", false):
			combat["combat_ended"] = true
			if r.get("victory", false):
				var m = combat.get("monster", {})
				if m:  # outsmart win leaves monster at full HP — mark dead for the win check
					m["current_hp"] = 0
		return
	# Build Read with damage setups (these spend energy + add Read).
	for ab in ["ambush", "exploit"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# Filler builders (debuffs still add Read).
	for ab in ["sabotage", "distract"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# Low Read but Gambit in hand → chip damage.
	if "gambit" in hand:
		if combat_mgr.process_ability_command(0, "gambit", "").get("success", false):
			return
	combat_mgr.process_attack(combat)

func run_mage_matrix():
	# v0.9.697 — validate the Mage Focus ramp (spells build Focus → Meteor discharges).
	var levels := [10, 30, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "empowered", "elite", "boss"]
	print("\n===== MAGE FOCUS SIM (%d fights/cell, Wizard + companion) =====" % FIGHTS_PER_CELL)
	print("%-6s %-9s %-10s %8s %8s" % ["Lvl", "Gear", "Enemy", "WinRate", "AvgTurns"])
	for lvl in levels:
		for gear in gears:
			for et in enemies:
				var wins := 0
				var total_turns := 0
				for i in range(FIGHTS_PER_CELL):
					var r = run_fight(lvl, gear, et, 1.0, 1.0, 1.0, "Wizard")
					if r.win:
						wins += 1
					total_turns += r.turns
				print("%-6d %-9s %-10s %7.0f%% %8.1f" % [lvl, gear, et, 100.0*float(wins)/FIGHTS_PER_CELL, float(total_turns)/FIGHTS_PER_CELL])
	print("=====================================================================\n")

func _player_act_mage(combat: Dictionary, ch) -> void:
	var hand: Array = combat.get("combat_hand", [])
	var focus: int = int(combat.get("focus", 0))
	# Discharge the ramp with Meteor once Focus is built.
	if focus >= 3 and "meteor" in hand:
		if combat_mgr.process_ability_command(0, "meteor", "").get("success", false):
			return
	# #55 — Magic Bolt is now the mage's big burst nuke (rebuilt multiplier). A real
	# mage opens with it while mana is stocked (dumps ~25% pool for a huge hit), then
	# falls to Blast for efficient sustain. Meteor discharges the Focus ramp above.
	if "magic_bolt" in hand and ch.current_mana > int(ch.get_total_max_mana() * 0.25):
		var amt := str(max(1, int(ch.get_total_max_mana() * 0.25)))
		if combat_mgr.process_ability_command(0, "magic_bolt", amt).get("success", false):
			return
	# Efficient sustain / Focus ramp (each +1 Focus).
	if "blast" in hand:
		if combat_mgr.process_ability_command(0, "blast", "").get("success", false):
			return
	if "meteor" in hand:
		if combat_mgr.process_ability_command(0, "meteor", "").get("success", false):
			return
	combat_mgr.process_attack(combat)

func make_char(level: int, gear: String, klass: String = "Fighter"):
	var ch = CharacterScript.new()
	ch.initialize("SimChar", klass, "Human")
	for i in range(level - 1):
		ch.level_up()
	# #55 (2026-08-26) — allocate every level-up stat point into the class's primary
	# stat so NAKED resource pools (max_mana / max_stamina / max_energy, which drive
	# the new absolute cost model) scale with level like a real focused build. The sim
	# previously left points unspent, artificially flattening the pools.
	var _primary := "strength"
	if klass in ["Wizard", "Sorcerer", "Sage"]:
		_primary = "intelligence"
	elif klass in ["Thief", "Ranger", "Ninja"]:
		_primary = "dexterity"
	while ch.unspent_stat_points > 0:
		ch.spend_stat_point(_primary)
	# Gear tiers: under = common/uncommon a bit below level; average = rare at level;
	# bis = artifact at level.
	var rarity := "common"
	var glevel := level
	match gear:
		"under":
			rarity = "uncommon"
			glevel = max(1, level - 8)
		"average":
			rarity = "rare"
		"bis":
			rarity = "artifact"
	for slot in SLOTS:
		var item = drop_tables._generate_item({"item_type": "%s_artifact" % slot}, glevel, rarity)
		if item is Dictionary and not item.is_empty():
			ch.equipped[slot] = item
	# Representative companion (tier scales loosely with level).
	var comp_tier: int = clampi(1 + int(level / 12.0), 1, 9)
	ch.active_companion = {
		"id": "sim_comp", "monster_type": "Wolf", "name": "Fang",
		"tier": comp_tier, "level": level, "xp": 0,
		"bonuses": {"attack": 10.0, "hp_bonus": 5.0, "mana_bonus": 3.0, "wisdom_bonus": 2.0, "speed": 5.0},
		"variant": "Normal", "sub_tier": 1, "border_tier": 1,
	}
	ch.current_hp = ch.get_total_max_hp()
	# Enter combat at FULL resources — in real play, out-of-combat regen tops the
	# pool between fights. (level_up/equip raise MAX but don't refill current, and
	# make_char only topped HP — leaving resources at the pre-gear base, which
	# distorted MinRes%/EndRes%.)
	ch.current_stamina = ch.get_total_max_stamina()
	ch.current_mana = ch.get_total_max_mana()
	ch.current_energy = ch.get_total_max_energy()
	return ch

func make_monster(level: int, et: String, extra_hp_mult: float = 1.0) -> Dictionary:
	var m = monster_db.generate_monster_by_name("Orc", level)
	match et:
		"empowered":
			m["max_hp"] = int(m.get("max_hp", 1) * 2.2)  # #29 v0.9.700 — mirrors empowered flat HP (~2 mods)
			m["strength"] = int(m.get("strength", 1) * 1.1)
			m["defense"] = int(m.get("defense", 1) * 1.15)
		"elite":
			m["max_hp"] = int(m.get("max_hp", 1) * 3.5)  # #29 v0.9.700 — mirrors ★ Champion HP 1.5→3.5
			m["strength"] = int(m.get("strength", 1) * 1.3)
			m["defense"] = int(m.get("defense", 1) * 1.25)
		"boss":
			m["max_hp"] = int(m.get("max_hp", 1) * 5.0)  # #29 v0.9.700 — mirrors dungeon boss hp_mult ×2.5 (2.0→5.0 effective)
			m["strength"] = int(m.get("strength", 1) * 1.5)
			m["defense"] = int(m.get("defense", 1) * 1.5)
	if extra_hp_mult != 1.0:
		m["max_hp"] = int(m.get("max_hp", 1) * extra_hp_mult)
	m["current_hp"] = m.get("max_hp", 1)
	return m

func _player_act(combat: Dictionary, ch) -> void:
	var hand: Array = combat.get("combat_hand", [])
	var mom: int = int(combat.get("momentum", 0))
	# #55 identity pass (2026-08-27) — a real Warrior is a DEFENSIVE bruiser: keep its
	# mitigation buffs UP (Iron Skin = damage_reduction, Fortify = defense) so it's the
	# safest in long fights. Recast when they lapse (models buff uptime, which the old
	# sim ignored — it only cast damage buffs, so the audit under-rated Warrior tankiness).
	if "iron_skin" in hand and ch.get_buff_value("damage_reduction") <= 0:
		if combat_mgr.process_ability_command(0, "iron_skin", "").get("success", false):
			return
	if "fortify" in hand and ch.get_buff_value("defense") <= 0:
		if combat_mgr.process_ability_command(0, "fortify", "").get("success", false):
			return
	# Opportunistic damage buff (once per fight): buff early for uptime (also builds Momentum).
	if not combat.get("_sim_buffed", false):
		for b in WARRIOR_BUFFS:
			if b in hand:
				var rb = combat_mgr.process_ability_command(0, b, "")
				if rb.get("success", false):
					combat["_sim_buffed"] = true
					return
	# v0.9.696 — Momentum play: hold Devastate until Momentum is high, unleash the finisher.
	if mom >= 4 and "devastate" in hand:
		# Devastate is now a REAL dump in combat_manager (no sim emulation needed).
		if combat_mgr.process_ability_command(0, "devastate", "").get("success", false):
			return
	# Build with the best affordable BUILDER in hand (Devastate excluded here).
	for ab in ["cleave", "shield_bash", "power_strike"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# If only Devastate is available and we have some Momentum, spend it (beats a basic hit).
	if mom >= 1 and "devastate" in hand:
		if combat_mgr.process_ability_command(0, "devastate", "").get("success", false):
			return
	# Out of resource / no castable card → basic attack (also regens + builds Momentum? no).
	combat_mgr.process_attack(combat)

func run_fight(level: int, gear: String, et: String, extra_hp_mult: float = 1.0, player_dmg_scale: float = 1.0, monster_dmg_scale: float = 1.0, klass: String = "Fighter", monster_level: int = -1) -> Dictionary:
	# player_dmg_scale/monster_dmg_scale < 1.0 simulate a rebalanced damage profile
	# (e.g. Momentum gating the burst → lower avg player DPS) by giving back a
	# fraction of the damage dealt/taken each turn — the reverse-solve knobs.
	# monster_level > 0 pits the player (at `level`) against an OVER/under-level monster.
	var ch = make_char(level, gear, klass)
	var monster = make_monster(monster_level if monster_level > 0 else level, et, extra_hp_mult)
	var max_hp: int = ch.get_total_max_hp()
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return {"win": false, "turns": 0}
	var combat = combat_mgr.active_combats[0]
	var turns := 0
	var casts := 0  # #29 — count ability casts (resource decreased this turn = a cast, not a basic attack)
	# Resource-economy telemetry: how far the pool is actually pushed over the fight.
	var max_res: int = maxi(1, _class_max_resource(ch, klass))
	var min_res: int = _class_resource(ch, klass)
	var min_hp_pct := 100.0  # #55 monster-challenge audit — lowest HP% reached (danger telemetry)
	while turns < 400:
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		turns += 1
		if combat.get("player_can_act", true) and ch.current_hp > 0 and int(monster.get("current_hp", 0)) > 0:
			var mhp0: int = int(monster.get("current_hp", 0))
			var res0: int = _class_resource(ch, klass)
			if klass == "Thief":
				_player_act_trickster(combat, ch)
			elif klass == "Wizard":
				_player_act_mage(combat, ch)
			else:
				_player_act(combat, ch)
			if _class_resource(ch, klass) < res0:
				casts += 1
				if _cost_mult > 1.0:
					_drain_resource(ch, klass, int((res0 - _class_resource(ch, klass)) * (_cost_mult - 1.0)))
			min_res = mini(min_res, _class_resource(ch, klass))
			if player_dmg_scale < 1.0:
				var dealt: int = mhp0 - int(monster.get("current_hp", 0))
				if dealt > 0:
					var giveback: int = int(dealt * (1.0 - player_dmg_scale))
					monster["current_hp"] = min(int(monster.get("max_hp", 1)), int(monster.get("current_hp", 0)) + giveback)
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		var php0: int = ch.current_hp
		combat_mgr.process_monster_turn(combat)
		if monster_dmg_scale < 1.0:
			var taken: int = php0 - ch.current_hp
			if taken > 0:
				ch.current_hp = min(max_hp, ch.current_hp + int(taken * (1.0 - monster_dmg_scale)))
		min_hp_pct = minf(min_hp_pct, 100.0 * float(maxi(0, ch.current_hp)) / float(max_hp))
	var win: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
	var end_res: int = _class_resource(ch, klass)
	combat_mgr.end_combat(0, win, false)
	return {
		"win": win, "turns": turns, "casts": casts,
		"min_res_pct": 100.0 * float(min_res) / float(max_res),
		"end_res_pct": 100.0 * float(end_res) / float(max_res),
		"min_hp_pct": min_hp_pct,
		"max_res": max_res,
	}

func _class_resource(ch, klass: String) -> int:
	# #29 — current value of the class's combat resource, for cast-counting.
	if klass == "Thief":
		return int(ch.current_energy)
	if klass == "Wizard":
		return int(ch.current_mana)
	return int(ch.current_stamina)

func _drain_resource(ch, klass: String, amt: int) -> void:
	# Subtract extra resource (cost-tier emulation), floored at 0.
	if amt <= 0:
		return
	if klass == "Thief":
		ch.current_energy = maxi(0, int(ch.current_energy) - amt)
	elif klass == "Wizard":
		ch.current_mana = maxi(0, int(ch.current_mana) - amt)
	else:
		ch.current_stamina = maxi(0, int(ch.current_stamina) - amt)

func _class_max_resource(ch, klass: String) -> int:
	# Max pool for the class's combat resource (for resource-pressure telemetry).
	if klass == "Thief":
		return int(ch.get_total_max_energy())
	if klass == "Wizard":
		return int(ch.get_total_max_mana())
	return int(ch.get_total_max_stamina())

func run_design_solve():
	# Reverse-solve the DESIGN numbers: what player-damage% × monster-damage% give
	# the target fight lengths + win-rates → tells us the avg per-turn damage
	# Momentum must produce (and how much monster damage must soften).
	var N := 80
	var pds := [1.0, 0.5, 0.33, 0.25]
	var mds := [1.0, 0.75, 0.5]
	print("\n===== DESIGN-SOLVE: player dmg%% × monster dmg%% -> avgTurns@win (L50 BiS Fighter) =====")
	print("Targets: elite ~6-9t, boss ~10-14t at ~85-90%% win. Find the combo that lands there.")
	for et in ["elite", "boss"]:
		print("-- %s (L50 BiS) --" % et)
		var hdr := "%-12s" % "plyDmg\\monDmg"
		for md in mds:
			hdr += "%13s" % ("mon %d%%" % int(md * 100))
		print(hdr)
		for pd in pds:
			var row := "%-12s" % ("ply %d%%" % int(pd * 100))
			for md in mds:
				var wins := 0
				var tt := 0
				for i in range(N):
					var r = run_fight(50, "bis", et, 1.0, pd, md)
					if r.win:
						wins += 1
					tt += r.turns
				row += "%13s" % ("%.1ft@%d%%" % [float(tt) / N, int(100.0 * wins / N)])
			print(row)
	print("==============================================================================\n")
