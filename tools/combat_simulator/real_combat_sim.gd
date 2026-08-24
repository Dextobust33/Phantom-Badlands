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

	run_matrix()
	quit()

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

func make_char(level: int, gear: String):
	var ch = CharacterScript.new()
	ch.initialize("SimChar", "Fighter", "Human")
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
	return ch

func make_monster(level: int, et: String, extra_hp_mult: float = 1.0) -> Dictionary:
	var m = monster_db.generate_monster_by_name("Orc", level)
	match et:
		"empowered":
			m["max_hp"] = int(m.get("max_hp", 1) * 1.3)
			m["strength"] = int(m.get("strength", 1) * 1.1)
			m["defense"] = int(m.get("defense", 1) * 1.15)
		"elite":
			m["max_hp"] = int(m.get("max_hp", 1) * 1.5)
			m["strength"] = int(m.get("strength", 1) * 1.3)
			m["defense"] = int(m.get("defense", 1) * 1.25)
		"boss":
			m["max_hp"] = int(m.get("max_hp", 1) * 2.5)
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

func run_fight(level: int, gear: String, et: String, extra_hp_mult: float = 1.0, player_dmg_scale: float = 1.0, monster_dmg_scale: float = 1.0) -> Dictionary:
	# player_dmg_scale/monster_dmg_scale < 1.0 simulate a rebalanced damage profile
	# (e.g. Momentum gating the burst → lower avg player DPS) by giving back a
	# fraction of the damage dealt/taken each turn — the reverse-solve knobs.
	var ch = make_char(level, gear)
	var monster = make_monster(level, et, extra_hp_mult)
	var max_hp: int = ch.get_total_max_hp()
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return {"win": false, "turns": 0}
	var combat = combat_mgr.active_combats[0]
	var turns := 0
	while turns < 400:
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		turns += 1
		if combat.get("player_can_act", true) and ch.current_hp > 0 and int(monster.get("current_hp", 0)) > 0:
			var mhp0: int = int(monster.get("current_hp", 0))
			_player_act(combat, ch)
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
	combat_mgr.end_combat(0, win, false)
	return {"win": win, "turns": turns}

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
