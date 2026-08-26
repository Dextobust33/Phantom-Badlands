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

	run_resource_audit()  # resource-economy audit (does the pool ever bind? does it stay pegged high as level/gear scale?)
	quit()

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
	var N := 80
	var levels := [10, 50, 80]
	var gears := ["under", "average", "bis"]
	var enemies := ["plain", "elite", "boss"]
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
	var combo: int = int(combat.get("combo", 0))
	# Finisher when the chain is built high (near-guaranteed + big).
	if combo >= 4 and "gambit" in hand:
		if combat_mgr.process_ability_command(0, "gambit", "").get("success", false):
			return
	# Build Combo with a damage setup (these also +1 Combo).
	for ab in ["ambush", "exploit"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# Filler builders (debuffs still add Combo).
	for ab in ["sabotage", "distract"]:
		if ab in hand:
			if combat_mgr.process_ability_command(0, ab, "").get("success", false):
				return
	# Low Combo but only Gambit in hand → gamble (spends what little we have).
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
	# Ramp with damage spells (each +1 Focus).
	if "blast" in hand:
		if combat_mgr.process_ability_command(0, "blast", "").get("success", false):
			return
	if "magic_bolt" in hand:
		var amt := str(max(1, int(min(float(ch.current_mana), ch.get_total_max_mana() * 0.25))))
		if combat_mgr.process_ability_command(0, "magic_bolt", amt).get("success", false):
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

func run_fight(level: int, gear: String, et: String, extra_hp_mult: float = 1.0, player_dmg_scale: float = 1.0, monster_dmg_scale: float = 1.0, klass: String = "Fighter") -> Dictionary:
	# player_dmg_scale/monster_dmg_scale < 1.0 simulate a rebalanced damage profile
	# (e.g. Momentum gating the burst → lower avg player DPS) by giving back a
	# fraction of the damage dealt/taken each turn — the reverse-solve knobs.
	var ch = make_char(level, gear, klass)
	var monster = make_monster(level, et, extra_hp_mult)
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
	var win: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
	var end_res: int = _class_resource(ch, klass)
	combat_mgr.end_combat(0, win, false)
	return {
		"win": win, "turns": turns, "casts": casts,
		"min_res_pct": 100.0 * float(min_res) / float(max_res),
		"end_res_pct": 100.0 * float(end_res) / float(max_res),
		"max_res": max_res,
	}

func _class_resource(ch, klass: String) -> int:
	# #29 — current value of the class's combat resource, for cast-counting.
	if klass == "Thief":
		return int(ch.current_energy)
	if klass == "Wizard":
		return int(ch.current_mana)
	return int(ch.current_stamina)

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
