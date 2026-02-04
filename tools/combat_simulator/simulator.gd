# simulator.gd
# Main entry point for combat simulation
# Run with: godot --headless --path "project_path" --script "res://tools/combat_simulator/simulator.gd"
extends SceneTree

const SimulatedCharacter = preload("res://tools/combat_simulator/simulated_character.gd")
const GearGenerator = preload("res://tools/combat_simulator/gear_generator.gd")
const CombatEngine = preload("res://tools/combat_simulator/combat_engine.gd")
const ResultsWriter = preload("res://tools/combat_simulator/results_writer.gd")

# Simulation configuration
var CLASSES = ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]
var LEVELS = [5, 10, 25, 50, 75, 100]
var GEAR_QUALITIES = ["poor", "average", "good"]
var MONSTER_LEVEL_OFFSETS = [-5, 0, 5, 10, 20]
var ITERATIONS = 1000

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

# Progress tracking
var total_matchups: int = 0
var completed_matchups: int = 0

func _initialize():
	print("=== Combat Simulator v1.0 ===")
	print("Loading dependencies...")

	# Load balance config
	_load_balance_config()

	# Load monster database
	_load_monster_database()

	print("Configuration:")
	print("  Classes: %d" % CLASSES.size())
	print("  Levels: %s" % str(LEVELS))
	print("  Gear qualities: %s" % str(GEAR_QUALITIES))
	print("  Monster offsets: %s" % str(MONSTER_LEVEL_OFFSETS))
	print("  Iterations: %d" % ITERATIONS)

	# Calculate total matchups
	var monsters_per_level = 5  # Approximate
	total_matchups = CLASSES.size() * LEVELS.size() * GEAR_QUALITIES.size() * monsters_per_level * MONSTER_LEVEL_OFFSETS.size()
	print("  Estimated matchups: ~%d" % total_matchups)
	print("")

func _load_balance_config():
	"""Load balance configuration from JSON file"""
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
			push_error("Failed to parse balance_config.json")
			balance_config = {}
	else:
		push_error("Could not open balance_config.json")
		balance_config = {}

func _load_monster_database():
	"""Load and instantiate monster database"""
	var MonsterDatabaseScript = load("res://shared/monster_database.gd")
	if MonsterDatabaseScript:
		monster_db = MonsterDatabaseScript.new()
		monster_db.set_balance_config(balance_config)
		print("  Loaded monster_database.gd")
	else:
		push_error("Could not load monster_database.gd")

func run_full_simulation():
	"""Run the complete simulation suite"""
	print("Starting simulation...")
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

						completed_matchups += 1

		# Progress update
		var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
		print("  Completed %s (%.1fs elapsed)" % [class_type, elapsed])

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
	print("=== Simulation Complete ===")

func _get_monsters_for_level(level: int) -> Array:
	"""Get appropriate monster types for a level"""
	if not monster_db:
		return ["Goblin", "Orc", "Troll"]  # Fallback

	# Get tier for level
	var tier = _get_tier_for_level(level)

	# Get monster names from tier and adjacent tiers
	var monsters = []
	for t in range(max(1, tier - 1), min(9, tier + 1) + 1):
		var tier_monsters = _get_tier_monster_names(t)
		monsters.append_array(tier_monsters)

	# Remove duplicates
	var unique = []
	for m in monsters:
		if m not in unique:
			unique.append(m)

	return unique.slice(0, 8)  # Limit to 8 monsters per level

func _get_tier_for_level(level: int) -> int:
	"""Get monster tier for level (matches monster_database.gd)"""
	if level <= 5:
		return 1
	elif level <= 15:
		return 2
	elif level <= 30:
		return 3
	elif level <= 50:
		return 4
	elif level <= 100:
		return 5
	elif level <= 500:
		return 6
	elif level <= 2000:
		return 7
	elif level <= 5000:
		return 8
	else:
		return 9

func _get_tier_monster_names(tier: int) -> Array:
	"""Get monster names for a tier"""
	match tier:
		1: return ["Goblin", "Giant Rat", "Kobold", "Skeleton", "Wolf"]
		2: return ["Orc", "Hobgoblin", "Gnoll", "Zombie", "Giant Spider", "Wight"]
		3: return ["Ogre", "Troll", "Wraith", "Wyvern", "Minotaur", "Gargoyle"]
		4: return ["Giant", "Young Dragon", "Demon", "Vampire", "Gryphon", "Chimaera"]
		5: return ["Ancient Dragon", "Demon Lord", "Lich", "Titan", "Balrog", "Cerberus"]
		6: return ["Elemental", "Iron Golem", "Sphinx", "Hydra", "Phoenix", "Nazgul"]
		7: return ["Void Walker", "World Serpent", "Elder Lich", "Primordial Dragon"]
		8: return ["Cosmic Horror", "Time Weaver", "Death Incarnate"]
		9: return ["Avatar of Chaos", "The Nameless One", "God Slayer", "Entropy"]
		_: return ["Goblin"]

func _generate_monster(monster_name: String, level: int) -> Dictionary:
	"""Generate a monster at the specified level"""
	if monster_db:
		return monster_db.generate_monster_by_name(monster_name, level)

	# Fallback generation
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
	"""Run multiple iterations of a single matchup"""
	var wins = 0
	var total_damage = 0
	var total_rounds = 0
	var death_effect_counts = {}

	for i in range(ITERATIONS):
		# Clone monster for this iteration
		var monster = monster_template.duplicate(true)
		monster.current_hp = monster.max_hp

		# Run combat
		var result = combat_engine.simulate_single_combat(character, monster)

		if result.victory:
			wins += 1
		total_damage += result.damage_taken
		total_rounds += result.rounds

		# Track death effects
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
	"""Generate analysis from raw results"""
	var writer = ResultsWriter.new()

	# Generate summary stats
	results.summary_stats = writer.generate_summary_stats(results)

	# Generate monster analysis
	results.monster_analysis = writer.generate_monster_analysis(results)

	# Generate lethality comparison
	_generate_lethality_comparison()

	# Generate ability stats
	_generate_ability_stats()

func _generate_lethality_comparison():
	"""Compare empirical lethality with formula lethality"""
	var lethality_cfg = balance_config.get("lethality", {})

	for monster_name in results.monster_analysis:
		var analysis = results.monster_analysis[monster_name]
		var emp_lethality = analysis.get("empirical_lethality", 0)

		# Get formula lethality from a sample monster
		var sample_monster = _generate_monster(monster_name, 50)  # Level 50 sample
		var formula_lethality = 0
		if monster_db:
			formula_lethality = monster_db.calculate_lethality(sample_monster)
		else:
			# Fallback calculation
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
	"""Calculate lethality using the formula from monster_database.gd"""
	var hp_weight = cfg.get("hp_weight", 1.0)
	var str_weight = cfg.get("str_weight", 3.0)
	var def_weight = cfg.get("def_weight", 1.0)
	var speed_weight = cfg.get("speed_weight", 2.0)

	var base = monster.get("max_hp", 10) * hp_weight
	base += monster.get("strength", 5) * str_weight
	base += monster.get("defense", 5) * def_weight
	base += monster.get("speed", 10) * speed_weight

	# Apply ability modifiers
	var ability_mods = cfg.get("ability_modifiers", {})
	var mult = 1.0
	for ability in monster.get("abilities", []):
		mult += ability_mods.get(ability, 0.0)

	return max(1, base * mult)

func _generate_ability_stats():
	"""Generate statistics about monster ability impact"""
	# This would require tracking ability triggers during simulation
	# For now, we'll analyze based on monster types with abilities
	var ability_impact = {}

	# Estimate impact based on win rate differences
	# Monsters with certain abilities tend to have lower player win rates
	for monster_name in results.monster_analysis:
		var analysis = results.monster_analysis[monster_name]
		var sample_monster = _generate_monster(monster_name, 50)
		var abilities = sample_monster.get("abilities", [])

		for ability in abilities:
			if not ability_impact.has(ability):
				ability_impact[ability] = {
					"total_fights": 0,
					"total_win_rate": 0.0,
					"count": 0
				}
			ability_impact[ability].total_fights += analysis.get("total_fights", 0)
			ability_impact[ability].total_win_rate += analysis.get("avg_player_win_rate", 0)
			ability_impact[ability].count += 1

	# Calculate averages
	for ability in ability_impact:
		var data = ability_impact[ability]
		if data.count > 0:
			data["avg_win_rate"] = data.total_win_rate / data.count
			# Baseline win rate is ~0.85 for same-level fights
			# Impact is how much this ability reduces win rate
			data["avg_impact"] = (0.85 - data.avg_win_rate) * 100
			data["trigger_rate"] = 1.0  # Estimated

	results.ability_stats = ability_impact

func _write_results():
	"""Write results to files"""
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

# Entry point when run via --script
func _init():
	_initialize()
	run_full_simulation()
	quit()
