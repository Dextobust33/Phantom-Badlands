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
				var total_hpfrac := 0.0
				for i in range(FIGHTS_PER_CELL):
					var r = run_fight(lvl, gear, et)
					if r.win:
						wins += 1
					total_turns += r.turns
					total_hpfrac += r.hp_frac
				var wr := 100.0 * float(wins) / float(FIGHTS_PER_CELL)
				var at := float(total_turns) / float(FIGHTS_PER_CELL)
				var hp := 100.0 * total_hpfrac / float(FIGHTS_PER_CELL)
				print("%-6d %-9s %-10s %7.0f%% %8.1f %9.0f%%" % [lvl, gear, et, wr, at, hp])
	print("=====================================================================\n")
	quit()

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

func make_monster(level: int, et: String) -> Dictionary:
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
	m["current_hp"] = m.get("max_hp", 1)
	return m

func run_fight(level: int, gear: String, et: String) -> Dictionary:
	var ch = make_char(level, gear)
	var monster = make_monster(level, et)
	var max_hp: int = ch.get_total_max_hp()
	combat_mgr.start_combat(0, ch, monster)
	if not combat_mgr.active_combats.has(0):
		return {"win": false, "turns": 0, "hp_frac": 0.0}
	var combat = combat_mgr.active_combats[0]
	var turns := 0
	while turns < 400:
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		turns += 1
		if combat.get("player_can_act", true) and ch.current_hp > 0 and int(monster.get("current_hp", 0)) > 0:
			combat_mgr.process_attack(combat)
		if ch.current_hp <= 0 or int(monster.get("current_hp", 0)) <= 0 or combat.get("combat_ended", false):
			break
		combat_mgr.process_monster_turn(combat)
	var win: bool = int(monster.get("current_hp", 0)) <= 0 and ch.current_hp > 0
	var hp_frac: float = clampf(float(ch.current_hp) / float(max(1, max_hp)), 0.0, 1.0)
	combat_mgr.end_combat(0, win, false)
	return {"win": win, "turns": turns, "hp_frac": hp_frac}
