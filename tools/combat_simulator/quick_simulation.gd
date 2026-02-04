# quick_simulation.gd
# Quick simulation with reduced parameters for faster testing
extends SceneTree

const SimulatedCharacter = preload("res://tools/combat_simulator/simulated_character.gd")
const GearGenerator = preload("res://tools/combat_simulator/gear_generator.gd")
const CombatEngine = preload("res://tools/combat_simulator/combat_engine.gd")
const ResultsWriter = preload("res://tools/combat_simulator/results_writer.gd")

# Reduced simulation configuration for quick testing
var CLASSES = ["Fighter", "Wizard", "Thief"]  # One from each path
var LEVELS = [10, 50]  # Just two levels
var GEAR_QUALITIES = ["average"]  # Just one gear quality
var MONSTER_LEVEL_OFFSETS = [0, 10]  # Same level and +10
var ITERATIONS = 50  # Fewer iterations

# Monster database reference
var monster_db: Node = null
var balance_config: Dictionary = {}

# Results storage
var results: Dictionary = {
	"class_results": {},
	"monster_analysis": {},
	"lethality_comparison": {},
	"ability_stats": {},
	"summary_stats": {}
}

func _init():
	run_simulation()

func run_simulation():
	print("=== Quick Combat Simulation ===")
	print("")

	# Load balance config
	_load_balance_config()

	# Load monster database
	_load_monster_database()

	print("Configuration:")
	print("  Classes: %s" % str(CLASSES))
	print("  Levels: %s" % str(LEVELS))
	print("  Iterations: %d" % ITERATIONS)
	print("")

	var gear_gen = GearGenerator.new()
	var combat_engine = CombatEngine.new()
	combat_engine.set_balance_config(balance_config)

	var start_time = Time.get_ticks_msec()

	for class_type in CLASSES:
		print("Simulating %s..." % class_type)
		results.class_results[class_type] = {}

		for level in LEVELS:
			var level_key = "level_%d" % level
			results.class_results[class_type][level_key] = {}

			for gear_quality_str in GEAR_QUALITIES:
				var gear_quality = GearGenerator.quality_from_string(gear_quality_str)
				results.class_results[class_type][level_key][gear_quality_str] = {}

				# Create character with gear
				var character = SimulatedCharacter.new(class_type, level)
				var gear = gear_gen.generate_gear_set(level, gear_quality)
				character.apply_equipment(gear)

				# Get monsters for this level
				var monsters = _get_monsters_for_level(level)

				for monster_base in monsters:
					for offset in MONSTER_LEVEL_OFFSETS:
						var monster_level = max(1, level + offset)
						var monster = _generate_monster(monster_base, monster_level)
						if monster.is_empty():
							continue

						var matchup_key = "vs_%s_%d" % [monster.name.replace(" ", "_"), monster_level]

						# Run iterations
						var matchup_results = _simulate_matchup(character, monster, combat_engine)
						matchup_results["monster_name"] = monster.name
						matchup_results["monster_level"] = monster_level
						matchup_results["total_player_max_hp"] = character.max_hp * ITERATIONS

						results.class_results[class_type][level_key][gear_quality_str][matchup_key] = matchup_results

		print("  Completed %s" % class_type)

	var total_time = (Time.get_ticks_msec() - start_time) / 1000.0
	print("")
	print("Simulation complete in %.1f seconds" % total_time)
	print("")

	# Generate analysis
	print("Generating analysis...")
	_generate_analysis()

	# Write results
	print("Writing results...")
	_write_results()

	print("")
	print("=== Quick Simulation Complete ===")
	quit()

func _load_balance_config():
	var file = FileAccess.open("res://server/balance_config.json", FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		var json = JSON.new()
		var error = json.parse(json_text)
		if error == OK:
			balance_config = json.data
			print("  Loaded balance_config.json")
		else:
			print("  WARNING: Failed to parse balance_config.json")
			balance_config = {}
	else:
		print("  WARNING: Could not open balance_config.json")
		balance_config = {}

func _load_monster_database():
	var MonsterDatabaseScript = load("res://shared/monster_database.gd")
	if MonsterDatabaseScript:
		monster_db = MonsterDatabaseScript.new()
		monster_db.set_balance_config(balance_config)
		print("  Loaded monster_database.gd")
	else:
		print("  WARNING: Could not load monster_database.gd")

func _get_monsters_for_level(level: int) -> Array:
	var tier = _get_tier_for_level(level)
	return _get_tier_monster_names(tier).slice(0, 3)  # Just 3 monsters per tier

func _get_tier_for_level(level: int) -> int:
	if level <= 5: return 1
	elif level <= 15: return 2
	elif level <= 30: return 3
	elif level <= 50: return 4
	elif level <= 100: return 5
	else: return 6

func _get_tier_monster_names(tier: int) -> Array:
	match tier:
		1: return ["Goblin", "Skeleton", "Wolf"]
		2: return ["Orc", "Zombie", "Giant Spider"]
		3: return ["Troll", "Wraith", "Minotaur"]
		4: return ["Young Dragon", "Demon", "Vampire"]
		5: return ["Ancient Dragon", "Lich", "Titan"]
		_: return ["Goblin"]

func _generate_monster(monster_name: String, level: int) -> Dictionary:
	if monster_db:
		return monster_db.generate_monster_by_name(monster_name, level)

	# Fallback
	return {
		"name": monster_name,
		"level": level,
		"max_hp": 50 + level * 10,
		"current_hp": 50 + level * 10,
		"strength": 10 + level,
		"defense": 5 + int(level * 0.5),
		"speed": 10,
		"class_affinity": 0,
		"abilities": []
	}

func _simulate_matchup(character: SimulatedCharacter, monster_template: Dictionary, combat_engine: CombatEngine) -> Dictionary:
	var wins = 0
	var total_damage = 0
	var total_rounds = 0
	var death_effect_counts = {}

	for i in range(ITERATIONS):
		var monster = monster_template.duplicate(true)
		monster.current_hp = monster.max_hp

		var result = combat_engine.simulate_single_combat(character, monster)

		if result.victory:
			wins += 1
		total_damage += result.damage_taken
		total_rounds += result.rounds

		for effect in result.death_effects:
			if not death_effect_counts.has(effect):
				death_effect_counts[effect] = 0
			death_effect_counts[effect] += 1

	return {
		"wins": wins,
		"total": ITERATIONS,
		"win_rate": float(wins) / ITERATIONS,
		"total_damage_taken": total_damage,
		"avg_damage_taken": float(total_damage) / ITERATIONS,
		"total_rounds": total_rounds,
		"avg_rounds": float(total_rounds) / ITERATIONS,
		"death_effects": death_effect_counts
	}

func _generate_analysis():
	var writer = ResultsWriter.new()
	results.summary_stats = writer.generate_summary_stats(results)
	results.monster_analysis = writer.generate_monster_analysis(results)
	_generate_lethality_comparison()

func _generate_lethality_comparison():
	var lethality_cfg = balance_config.get("lethality", {})
	for monster_name in results.monster_analysis:
		var analysis = results.monster_analysis[monster_name]
		var emp_lethality = analysis.get("empirical_lethality", 0)
		var sample_monster = _generate_monster(monster_name, 50)
		var formula_lethality = 0
		if monster_db:
			formula_lethality = monster_db.calculate_lethality(sample_monster)
		else:
			formula_lethality = _calculate_formula_lethality(sample_monster, lethality_cfg)
		var delta = 0.0
		if formula_lethality > 0:
			delta = ((emp_lethality - formula_lethality) / formula_lethality) * 100
		results.lethality_comparison[monster_name] = {
			"empirical_lethality": emp_lethality,
			"formula_lethality": formula_lethality,
			"delta_percent": delta
		}

func _calculate_formula_lethality(monster: Dictionary, cfg: Dictionary) -> float:
	var hp_weight = cfg.get("hp_weight", 1.0)
	var str_weight = cfg.get("str_weight", 3.0)
	var def_weight = cfg.get("def_weight", 1.0)
	var speed_weight = cfg.get("speed_weight", 2.0)
	var base = monster.get("max_hp", 10) * hp_weight
	base += monster.get("strength", 5) * str_weight
	base += monster.get("defense", 5) * def_weight
	base += monster.get("speed", 10) * speed_weight
	var ability_mods = cfg.get("ability_modifiers", {})
	var mult = 1.0
	for ability in monster.get("abilities", []):
		mult += ability_mods.get(ability, 0.0)
	return max(1, base * mult)

func _write_results():
	var writer = ResultsWriter.new("res://docs/simulation_results/")

	var config = {
		"iterations": ITERATIONS,
		"classes": CLASSES,
		"levels": LEVELS,
		"gear_qualities": GEAR_QUALITIES,
		"monster_level_offsets": MONSTER_LEVEL_OFFSETS
	}

	var paths = writer.write_results(results, config)
	print("  JSON: %s" % paths.json_path)
	print("  Markdown: %s" % paths.markdown_path)
