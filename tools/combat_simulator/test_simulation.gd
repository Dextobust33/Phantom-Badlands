# test_simulation.gd
# Quick test run with minimal iterations to verify simulator works
extends SceneTree

const SimulatedCharacter = preload("res://tools/combat_simulator/simulated_character.gd")
const GearGenerator = preload("res://tools/combat_simulator/gear_generator.gd")
const CombatEngine = preload("res://tools/combat_simulator/combat_engine.gd")

func _init():
	run_tests()

func run_tests():
	print("=== Combat Simulator Quick Test ===")
	print("")

	# Test 1: SimulatedCharacter creation
	print("Test 1: Creating characters...")
	var classes = ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]
	for char_class in classes:
		var char = SimulatedCharacter.new(char_class, 50)
		print("  %s L50: HP=%d ATK=%d DEF=%d" % [char_class, char.max_hp, char.get_total_attack(), char.get_total_defense()])
	print("  OK!")
	print("")

	# Test 2: Gear generation
	print("Test 2: Generating gear...")
	var gear_gen = GearGenerator.new()
	for quality in [GearGenerator.GearQuality.POOR, GearGenerator.GearQuality.AVERAGE, GearGenerator.GearQuality.GOOD]:
		var gear = gear_gen.generate_gear_set(50, quality)
		print("  Quality %d: ATK=%d DEF=%d HP=%d" % [quality, gear.attack, gear.defense, gear.max_hp])
	print("  OK!")
	print("")

	# Test 3: Combat engine basic test
	print("Test 3: Running combat simulation...")
	var combat_engine = CombatEngine.new()
	var char = SimulatedCharacter.new("Fighter", 50)
	var gear = gear_gen.generate_gear_set(50, GearGenerator.GearQuality.AVERAGE)
	char.apply_equipment(gear)

	# Create a test monster
	var monster = {
		"name": "Test Orc",
		"level": 50,
		"max_hp": 300,
		"current_hp": 300,
		"strength": 40,
		"defense": 25,
		"speed": 12,
		"class_affinity": 1,  # PHYSICAL
		"abilities": []
	}

	var wins = 0
	var total_damage = 0
	var total_rounds = 0
	var iterations = 100

	for i in range(iterations):
		monster.current_hp = monster.max_hp
		var result = combat_engine.simulate_single_combat(char, monster)
		if result.victory:
			wins += 1
		total_damage += result.damage_taken
		total_rounds += result.rounds

	print("  Fighter L50 vs Orc L50 (%d iterations):" % iterations)
	print("    Win rate: %.1f%%" % (float(wins) / iterations * 100))
	print("    Avg damage taken: %.1f" % (float(total_damage) / iterations))
	print("    Avg rounds: %.1f" % (float(total_rounds) / iterations))
	print("  OK!")
	print("")

	# Test 4: Test with abilities
	print("Test 4: Testing monster abilities...")
	var monster_with_abilities = {
		"name": "Demon",
		"level": 50,
		"max_hp": 250,
		"current_hp": 250,
		"strength": 45,
		"defense": 30,
		"speed": 14,
		"class_affinity": 2,  # MAGICAL
		"abilities": ["poison", "curse", "death_curse"]
	}

	wins = 0
	total_damage = 0
	for i in range(iterations):
		monster_with_abilities.current_hp = monster_with_abilities.max_hp
		var result = combat_engine.simulate_single_combat(char, monster_with_abilities)
		if result.victory:
			wins += 1
		total_damage += result.damage_taken

	print("  Fighter L50 vs Demon L50 (with abilities):")
	print("    Win rate: %.1f%%" % (float(wins) / iterations * 100))
	print("    Avg damage taken: %.1f" % (float(total_damage) / iterations))
	print("  OK!")
	print("")

	# Test 5: Class comparison
	print("Test 5: Class comparison at L50 vs Orc L50...")
	monster.abilities = []
	for char_class in classes:
		char = SimulatedCharacter.new(char_class, 50)
		gear = gear_gen.generate_gear_set(50, GearGenerator.GearQuality.AVERAGE)
		char.apply_equipment(gear)

		wins = 0
		for i in range(iterations):
			monster.current_hp = monster.max_hp
			var result = combat_engine.simulate_single_combat(char, monster)
			if result.victory:
				wins += 1

		print("  %s: %.1f%% win rate" % [char_class, float(wins) / iterations * 100])
	print("  OK!")
	print("")

	print("=== All Tests Passed ===")
	quit()
