# monster_database.gd
# Monster definitions and generation for Phantasia 4 style combat
class_name MonsterDatabase
extends Node

# Monster types by difficulty tier
enum MonsterType {
	# Tier 1 (Level 1-5)
	GOBLIN,
	GIANT_RAT,
	KOBOLD,
	SKELETON,
	WOLF,

	# Tier 2 (Level 6-15)
	ORC,
	HOBGOBLIN,
	GNOLL,
	ZOMBIE,
	GIANT_SPIDER,
	WIGHT,

	# Tier 3 (Level 16-30)
	OGRE,
	TROLL,
	WRAITH,
	WYVERN,
	MINOTAUR,

	# Tier 4 (Level 31-50)
	GIANT,
	DRAGON_WYRMLING,
	DEMON,
	VAMPIRE,

	# Tier 5 (Level 51-100)
	ANCIENT_DRAGON,
	DEMON_LORD,
	LICH,
	TITAN,

	# Tier 6 (Level 101-500)
	ELEMENTAL,
	IRON_GOLEM,
	SPHINX,
	HYDRA,
	PHOENIX,

	# Tier 7 (Level 501-2000)
	VOID_WALKER,
	WORLD_SERPENT,
	ELDER_LICH,
	PRIMORDIAL_DRAGON,

	# Tier 8 (Level 2001-5000)
	COSMIC_HORROR,
	TIME_WEAVER,
	DEATH_INCARNATE,

	# Tier 9 (Level 5001-10000)
	AVATAR_OF_CHAOS,
	THE_NAMELESS_ONE,
	GOD_SLAYER,
	ENTROPY
}

func _ready():
	print("Monster Database initialized")

func generate_monster(min_level: int, max_level: int) -> Dictionary:
	"""Generate a random monster appropriate for the level range"""
	var target_level = randi_range(min_level, max_level)

	# Select monster type based on level
	var monster_type = select_monster_type(target_level)

	# Get base stats for this monster type
	var base_stats = get_monster_base_stats(monster_type)

	# Scale to target level
	var monster = scale_monster_to_level(base_stats, target_level)

	return monster

func generate_monster_by_name(monster_name: String, target_level: int) -> Dictionary:
	"""Generate a specific monster type by name at the given level"""
	# Find the monster type by name
	for type_id in MonsterType.values():
		var base_stats = get_monster_base_stats(type_id)
		if base_stats.name == monster_name:
			return scale_monster_to_level(base_stats, target_level)

	# Fallback if name not found - generate random monster
	return generate_monster(target_level, target_level)

func select_monster_type(level: int) -> MonsterType:
	"""Select an appropriate monster type for the level"""
	var possible_types = []

	if level <= 5:
		# Tier 1
		possible_types = [
			MonsterType.GOBLIN,
			MonsterType.GIANT_RAT,
			MonsterType.KOBOLD,
			MonsterType.SKELETON,
			MonsterType.WOLF
		]
	elif level <= 15:
		# Tier 2
		possible_types = [
			MonsterType.ORC,
			MonsterType.HOBGOBLIN,
			MonsterType.GNOLL,
			MonsterType.ZOMBIE,
			MonsterType.GIANT_SPIDER,
			MonsterType.WIGHT
		]
	elif level <= 30:
		# Tier 3
		possible_types = [
			MonsterType.OGRE,
			MonsterType.TROLL,
			MonsterType.WRAITH,
			MonsterType.WYVERN,
			MonsterType.MINOTAUR
		]
	elif level <= 50:
		# Tier 4
		possible_types = [
			MonsterType.GIANT,
			MonsterType.DRAGON_WYRMLING,
			MonsterType.DEMON,
			MonsterType.VAMPIRE
		]
	elif level <= 100:
		# Tier 5
		possible_types = [
			MonsterType.ANCIENT_DRAGON,
			MonsterType.DEMON_LORD,
			MonsterType.LICH,
			MonsterType.TITAN
		]
	elif level <= 500:
		# Tier 6
		possible_types = [
			MonsterType.ELEMENTAL,
			MonsterType.IRON_GOLEM,
			MonsterType.SPHINX,
			MonsterType.HYDRA,
			MonsterType.PHOENIX
		]
	elif level <= 2000:
		# Tier 7
		possible_types = [
			MonsterType.VOID_WALKER,
			MonsterType.WORLD_SERPENT,
			MonsterType.ELDER_LICH,
			MonsterType.PRIMORDIAL_DRAGON
		]
	elif level <= 5000:
		# Tier 8
		possible_types = [
			MonsterType.COSMIC_HORROR,
			MonsterType.TIME_WEAVER,
			MonsterType.DEATH_INCARNATE
		]
	else:
		# Tier 9 (5001+)
		possible_types = [
			MonsterType.AVATAR_OF_CHAOS,
			MonsterType.THE_NAMELESS_ONE,
			MonsterType.GOD_SLAYER,
			MonsterType.ENTROPY
		]

	return possible_types[randi() % possible_types.size()]

func get_monster_base_stats(type: MonsterType) -> Dictionary:
	"""Get base statistics for a monster type"""
	match type:
		# Tier 1
		MonsterType.GOBLIN:
			return {
				"name": "Goblin",
				"base_level": 2,
				"base_hp": 15,
				"base_strength": 8,
				"base_defense": 5,
				"base_speed": 12,
				"base_experience": 25,
				"base_gold": 5,
				"flock_chance": 35,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "A small, green-skinned creature with sharp teeth"
			}
		MonsterType.GIANT_RAT:
			return {
				"name": "Giant Rat",
				"base_level": 1,
				"base_hp": 8,
				"base_strength": 6,
				"base_defense": 3,
				"base_speed": 14,
				"base_experience": 15,
				"base_gold": 2,
				"flock_chance": 40,
				"drop_table_id": "tier1",
				"drop_chance": 3,
				"description": "A rat the size of a large dog"
			}
		MonsterType.KOBOLD:
			return {
				"name": "Kobold",
				"base_level": 3,
				"base_hp": 12,
				"base_strength": 7,
				"base_defense": 6,
				"base_speed": 11,
				"base_experience": 30,
				"base_gold": 8,
				"flock_chance": 30,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "A small reptilian humanoid with crude weapons"
			}
		MonsterType.SKELETON:
			return {
				"name": "Skeleton",
				"base_level": 4,
				"base_hp": 18,
				"base_strength": 10,
				"base_defense": 8,
				"base_speed": 8,
				"base_experience": 40,
				"base_gold": 3,
				"flock_chance": 25,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "Animated bones held together by dark magic"
			}
		MonsterType.WOLF:
			return {
				"name": "Wolf",
				"base_level": 3,
				"base_hp": 20,
				"base_strength": 12,
				"base_defense": 6,
				"base_speed": 15,
				"base_experience": 35,
				"base_gold": 0,
				"flock_chance": 45,
				"drop_table_id": "tier1",
				"drop_chance": 5,
				"description": "A fierce predator with sharp fangs"
			}
		
		# Tier 2
		MonsterType.ORC:
			return {
				"name": "Orc",
				"base_level": 8,
				"base_hp": 45,
				"base_strength": 16,
				"base_defense": 12,
				"base_speed": 9,
				"base_experience": 120,
				"base_gold": 25,
				"flock_chance": 30,
				"drop_table_id": "tier2",
				"drop_chance": 8,
				"description": "A brutish humanoid warrior"
			}
		MonsterType.HOBGOBLIN:
			return {
				"name": "Hobgoblin",
				"base_level": 10,
				"base_hp": 50,
				"base_strength": 18,
				"base_defense": 14,
				"base_speed": 10,
				"base_experience": 150,
				"base_gold": 35,
				"flock_chance": 35,
				"drop_table_id": "tier2",
				"drop_chance": 8,
				"description": "A large, disciplined goblinoid soldier"
			}
		MonsterType.GNOLL:
			return {
				"name": "Gnoll",
				"base_level": 9,
				"base_hp": 42,
				"base_strength": 17,
				"base_defense": 11,
				"base_speed": 12,
				"base_experience": 130,
				"base_gold": 20,
				"flock_chance": 40,
				"drop_table_id": "tier2",
				"drop_chance": 8,
				"description": "A hyena-like humanoid scavenger"
			}
		MonsterType.ZOMBIE:
			return {
				"name": "Zombie",
				"base_level": 6,
				"base_hp": 35,
				"base_strength": 14,
				"base_defense": 9,
				"base_speed": 5,
				"base_experience": 80,
				"base_gold": 0,
				"flock_chance": 50,
				"drop_table_id": "tier2",
				"drop_chance": 5,
				"description": "A shambling corpse animated by necromancy"
			}
		MonsterType.GIANT_SPIDER:
			return {
				"name": "Giant Spider",
				"base_level": 7,
				"base_hp": 30,
				"base_strength": 13,
				"base_defense": 10,
				"base_speed": 16,
				"base_experience": 100,
				"base_gold": 15,
				"flock_chance": 25,
				"drop_table_id": "tier2",
				"drop_chance": 8,
				"description": "A spider large enough to prey on humans"
			}
		MonsterType.WIGHT:
			return {
				"name": "Wight",
				"base_level": 12,
				"base_hp": 55,
				"base_strength": 19,
				"base_defense": 15,
				"base_speed": 8,
				"base_experience": 200,
				"base_gold": 40,
				"flock_chance": 15,
				"drop_table_id": "tier2",
				"drop_chance": 10,
				"description": "An undead warrior with life-draining abilities"
			}
		
		# Tier 3
		MonsterType.OGRE:
			return {
				"name": "Ogre",
				"base_level": 18,
				"base_hp": 100,
				"base_strength": 25,
				"base_defense": 18,
				"base_speed": 7,
				"base_experience": 400,
				"base_gold": 80,
				"flock_chance": 10,
				"drop_table_id": "tier3",
				"drop_chance": 10,
				"description": "A huge, dim-witted giant"
			}
		MonsterType.TROLL:
			return {
				"name": "Troll",
				"base_level": 20,
				"base_hp": 90,
				"base_strength": 24,
				"base_defense": 16,
				"base_speed": 10,
				"base_experience": 500,
				"base_gold": 60,
				"flock_chance": 15,
				"drop_table_id": "tier3",
				"drop_chance": 12,
				"description": "A regenerating monster with terrible claws"
			}
		MonsterType.WRAITH:
			return {
				"name": "Wraith",
				"base_level": 22,
				"base_hp": 75,
				"base_strength": 20,
				"base_defense": 20,
				"base_speed": 12,
				"base_experience": 600,
				"base_gold": 100,
				"flock_chance": 20,
				"drop_table_id": "tier3",
				"drop_chance": 12,
				"description": "A ghostly spirit that feeds on life force"
			}
		MonsterType.WYVERN:
			return {
				"name": "Wyvern",
				"base_level": 25,
				"base_hp": 120,
				"base_strength": 28,
				"base_defense": 22,
				"base_speed": 15,
				"base_experience": 800,
				"base_gold": 150,
				"flock_chance": 5,
				"drop_table_id": "tier3",
				"drop_chance": 15,
				"description": "A two-legged dragon with a venomous tail"
			}
		MonsterType.MINOTAUR:
			return {
				"name": "Minotaur",
				"base_level": 23,
				"base_hp": 110,
				"base_strength": 27,
				"base_defense": 19,
				"base_speed": 11,
				"base_experience": 700,
				"base_gold": 120,
				"flock_chance": 10,
				"drop_table_id": "tier3",
				"drop_chance": 12,
				"description": "A bull-headed humanoid warrior"
			}
		
		# Tier 4
		MonsterType.GIANT:
			return {
				"name": "Giant",
				"base_level": 35,
				"base_hp": 200,
				"base_strength": 35,
				"base_defense": 25,
				"base_speed": 8,
				"base_experience": 1500,
				"base_gold": 300,
				"flock_chance": 5,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A towering humanoid of immense power"
			}
		MonsterType.DRAGON_WYRMLING:
			return {
				"name": "Young Dragon",
				"base_level": 40,
				"base_hp": 180,
				"base_strength": 38,
				"base_defense": 30,
				"base_speed": 14,
				"base_experience": 2000,
				"base_gold": 500,
				"flock_chance": 0,
				"drop_table_id": "tier4",
				"drop_chance": 20,
				"description": "A young but deadly dragon"
			}
		MonsterType.DEMON:
			return {
				"name": "Demon",
				"base_level": 38,
				"base_hp": 170,
				"base_strength": 36,
				"base_defense": 28,
				"base_speed": 13,
				"base_experience": 1800,
				"base_gold": 400,
				"flock_chance": 15,
				"drop_table_id": "tier4",
				"drop_chance": 15,
				"description": "A fiend from the lower planes"
			}
		MonsterType.VAMPIRE:
			return {
				"name": "Vampire",
				"base_level": 42,
				"base_hp": 160,
				"base_strength": 34,
				"base_defense": 32,
				"base_speed": 16,
				"base_experience": 2200,
				"base_gold": 600,
				"flock_chance": 0,
				"drop_table_id": "tier4",
				"drop_chance": 18,
				"description": "An undead noble with supernatural powers"
			}
		
		# Tier 5
		MonsterType.ANCIENT_DRAGON:
			return {
				"name": "Ancient Dragon",
				"base_level": 70,
				"base_hp": 500,
				"base_strength": 60,
				"base_defense": 50,
				"base_speed": 18,
				"base_experience": 10000,
				"base_gold": 5000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 20,
				"description": "A legendary wyrm of immense age and power"
			}
		MonsterType.DEMON_LORD:
			return {
				"name": "Demon Lord",
				"base_level": 75,
				"base_hp": 450,
				"base_strength": 65,
				"base_defense": 55,
				"base_speed": 17,
				"base_experience": 12000,
				"base_gold": 6000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 22,
				"description": "A ruler of the infernal realms"
			}
		MonsterType.LICH:
			return {
				"name": "Lich",
				"base_level": 80,
				"base_hp": 400,
				"base_strength": 50,
				"base_defense": 60,
				"base_speed": 12,
				"base_experience": 15000,
				"base_gold": 8000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 22,
				"description": "An undead sorcerer of terrible power"
			}
		MonsterType.TITAN:
			return {
				"name": "Titan",
				"base_level": 85,
				"base_hp": 600,
				"base_strength": 70,
				"base_defense": 58,
				"base_speed": 15,
				"base_experience": 18000,
				"base_gold": 10000,
				"flock_chance": 0,
				"drop_table_id": "tier5",
				"drop_chance": 25,
				"description": "A godlike being from the dawn of time"
			}

		# Tier 6 (Level 101-500)
		MonsterType.ELEMENTAL:
			return {
				"name": "Elemental",
				"base_level": 150,
				"base_hp": 800,
				"base_strength": 90,
				"base_defense": 70,
				"base_speed": 20,
				"base_experience": 25000,
				"base_gold": 15000,
				"flock_chance": 10,
				"drop_table_id": "tier6",
				"drop_chance": 8,
				"description": "A being of pure elemental energy"
			}
		MonsterType.IRON_GOLEM:
			return {
				"name": "Iron Golem",
				"base_level": 200,
				"base_hp": 1200,
				"base_strength": 100,
				"base_defense": 120,
				"base_speed": 8,
				"base_experience": 35000,
				"base_gold": 20000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 10,
				"description": "An animated construct of living metal"
			}
		MonsterType.SPHINX:
			return {
				"name": "Sphinx",
				"base_level": 250,
				"base_hp": 900,
				"base_strength": 85,
				"base_defense": 90,
				"base_speed": 16,
				"base_experience": 40000,
				"base_gold": 25000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 12,
				"description": "An ancient guardian of forbidden knowledge"
			}
		MonsterType.HYDRA:
			return {
				"name": "Hydra",
				"base_level": 350,
				"base_hp": 1500,
				"base_strength": 110,
				"base_defense": 80,
				"base_speed": 12,
				"base_experience": 60000,
				"base_gold": 35000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 15,
				"description": "A many-headed serpent that regenerates"
			}
		MonsterType.PHOENIX:
			return {
				"name": "Phoenix",
				"base_level": 400,
				"base_hp": 1000,
				"base_strength": 120,
				"base_defense": 75,
				"base_speed": 25,
				"base_experience": 80000,
				"base_gold": 50000,
				"flock_chance": 0,
				"drop_table_id": "tier6",
				"drop_chance": 18,
				"description": "An immortal bird of fire and rebirth"
			}

		# Tier 7 (Level 501-2000)
		MonsterType.VOID_WALKER:
			return {
				"name": "Void Walker",
				"base_level": 700,
				"base_hp": 2000,
				"base_strength": 150,
				"base_defense": 130,
				"base_speed": 22,
				"base_experience": 150000,
				"base_gold": 80000,
				"flock_chance": 5,
				"drop_table_id": "tier7",
				"drop_chance": 10,
				"description": "A creature from between dimensions"
			}
		MonsterType.WORLD_SERPENT:
			return {
				"name": "World Serpent",
				"base_level": 1000,
				"base_hp": 3500,
				"base_strength": 180,
				"base_defense": 150,
				"base_speed": 18,
				"base_experience": 300000,
				"base_gold": 150000,
				"flock_chance": 0,
				"drop_table_id": "tier7",
				"drop_chance": 15,
				"description": "A serpent large enough to encircle the world"
			}
		MonsterType.ELDER_LICH:
			return {
				"name": "Elder Lich",
				"base_level": 1200,
				"base_hp": 2500,
				"base_strength": 160,
				"base_defense": 180,
				"base_speed": 15,
				"base_experience": 400000,
				"base_gold": 200000,
				"flock_chance": 0,
				"drop_table_id": "tier7",
				"drop_chance": 18,
				"description": "An undead sorcerer of unfathomable age"
			}
		MonsterType.PRIMORDIAL_DRAGON:
			return {
				"name": "Primordial Dragon",
				"base_level": 1500,
				"base_hp": 5000,
				"base_strength": 220,
				"base_defense": 200,
				"base_speed": 20,
				"base_experience": 600000,
				"base_gold": 300000,
				"flock_chance": 0,
				"drop_table_id": "tier7",
				"drop_chance": 20,
				"description": "A dragon from before recorded history"
			}

		# Tier 8 (Level 2001-5000)
		MonsterType.COSMIC_HORROR:
			return {
				"name": "Cosmic Horror",
				"base_level": 2500,
				"base_hp": 8000,
				"base_strength": 300,
				"base_defense": 250,
				"base_speed": 25,
				"base_experience": 1000000,
				"base_gold": 500000,
				"flock_chance": 0,
				"drop_table_id": "tier8",
				"drop_chance": 12,
				"description": "An incomprehensible entity from beyond the stars"
			}
		MonsterType.TIME_WEAVER:
			return {
				"name": "Time Weaver",
				"base_level": 3500,
				"base_hp": 6000,
				"base_strength": 280,
				"base_defense": 300,
				"base_speed": 30,
				"base_experience": 1500000,
				"base_gold": 750000,
				"flock_chance": 0,
				"drop_table_id": "tier8",
				"drop_chance": 15,
				"description": "A being that exists across all timelines"
			}
		MonsterType.DEATH_INCARNATE:
			return {
				"name": "Death Incarnate",
				"base_level": 4500,
				"base_hp": 10000,
				"base_strength": 350,
				"base_defense": 280,
				"base_speed": 28,
				"base_experience": 2000000,
				"base_gold": 1000000,
				"flock_chance": 0,
				"drop_table_id": "tier8",
				"drop_chance": 18,
				"description": "The physical manifestation of death itself"
			}

		# Tier 9 (Level 5001-10000)
		MonsterType.AVATAR_OF_CHAOS:
			return {
				"name": "Avatar of Chaos",
				"base_level": 6000,
				"base_hp": 15000,
				"base_strength": 450,
				"base_defense": 380,
				"base_speed": 32,
				"base_experience": 5000000,
				"base_gold": 2000000,
				"flock_chance": 0,
				"drop_table_id": "tier9",
				"drop_chance": 15,
				"description": "Pure entropy given form and purpose"
			}
		MonsterType.THE_NAMELESS_ONE:
			return {
				"name": "The Nameless One",
				"base_level": 7500,
				"base_hp": 20000,
				"base_strength": 500,
				"base_defense": 450,
				"base_speed": 35,
				"base_experience": 8000000,
				"base_gold": 4000000,
				"flock_chance": 0,
				"drop_table_id": "tier9",
				"drop_chance": 18,
				"description": "An entity so ancient its name has been forgotten"
			}
		MonsterType.GOD_SLAYER:
			return {
				"name": "God Slayer",
				"base_level": 8500,
				"base_hp": 25000,
				"base_strength": 600,
				"base_defense": 500,
				"base_speed": 38,
				"base_experience": 12000000,
				"base_gold": 6000000,
				"flock_chance": 0,
				"drop_table_id": "tier9",
				"drop_chance": 20,
				"description": "A being that has killed gods and taken their power"
			}
		MonsterType.ENTROPY:
			return {
				"name": "Entropy",
				"base_level": 9500,
				"base_hp": 30000,
				"base_strength": 700,
				"base_defense": 600,
				"base_speed": 40,
				"base_experience": 20000000,
				"base_gold": 10000000,
				"flock_chance": 0,
				"drop_table_id": "tier9",
				"drop_chance": 25,
				"description": "The end of all things made manifest"
			}

	# Fallback
	return {
		"name": "Unknown",
		"base_level": 1,
		"base_hp": 10,
		"base_strength": 5,
		"base_defense": 5,
		"base_speed": 10,
		"base_experience": 10,
		"base_gold": 1,
		"flock_chance": 0,
		"description": "A mysterious creature"
	}

func scale_monster_to_level(base_stats: Dictionary, target_level: int) -> Dictionary:
	"""Scale monster stats to match target level using tiered scaling"""
	var level_diff = target_level - base_stats.base_level

	# Tiered scaling to prevent astronomical stats at high levels
	# Levels 1-100:    12% per level (unchanged)
	# Levels 101-500:  5% per level (slower growth)
	# Levels 501-2000: 2% per level (diminishing)
	# Levels 2000+:    0.5% per level (near-cap)
	var stat_scale = _calculate_tiered_stat_scale(base_stats.base_level, target_level)

	# Calculate scaled combat stats
	var scaled_hp = max(5, int(base_stats.base_hp * stat_scale))
	var scaled_strength = max(3, int(base_stats.base_strength * stat_scale))
	var scaled_defense = max(1, int(base_stats.base_defense * stat_scale))

	# Calculate XP and gold with tiered formulas
	var experience_reward = _calculate_experience_reward(scaled_hp, scaled_strength, scaled_defense, target_level)
	var gold_reward = _calculate_gold_reward(base_stats, stat_scale, target_level)

	return {
		"name": base_stats.name,
		"level": target_level,
		"max_hp": scaled_hp,
		"current_hp": scaled_hp,
		"strength": scaled_strength,
		"defense": scaled_defense,
		"speed": base_stats.base_speed,  # Speed doesn't scale
		"experience_reward": experience_reward,
		"gold_reward": gold_reward,
		"flock_chance": base_stats.get("flock_chance", 0),
		"drop_table_id": base_stats.get("drop_table_id", "common"),
		"drop_chance": base_stats.get("drop_chance", 5),
		"description": base_stats.description
	}

func _calculate_tiered_stat_scale(base_level: int, target_level: int) -> float:
	"""Calculate stat scaling using tiered percentages"""
	var scale = 1.0
	var current_level = base_level

	# Tier 1: Levels 1-100 at 12% per level
	if current_level < 100:
		var levels_in_tier = min(target_level, 100) - current_level
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.12
			current_level = min(target_level, 100)

	# Tier 2: Levels 101-500 at 5% per level
	if current_level < 500 and target_level > 100:
		var start = max(current_level, 100)
		var levels_in_tier = min(target_level, 500) - start
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.05
			current_level = min(target_level, 500)

	# Tier 3: Levels 501-2000 at 2% per level
	if current_level < 2000 and target_level > 500:
		var start = max(current_level, 500)
		var levels_in_tier = min(target_level, 2000) - start
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.02
			current_level = min(target_level, 2000)

	# Tier 4: Levels 2000+ at 0.5% per level
	if target_level > 2000:
		var start = max(current_level, 2000)
		var levels_in_tier = target_level - start
		if levels_in_tier > 0:
			scale += levels_in_tier * 0.005

	return max(0.25, scale)

func _calculate_experience_reward(hp: int, strength: int, defense: int, level: int) -> int:
	"""Calculate XP reward using tiered formula for high levels"""
	var lethality = hp + (strength * 3) + defense

	# Level 1-100: (lethality * level) / 10
	if level <= 100:
		return max(10, int((lethality * level) / 10))

	# Level 101-1000: lethality * (100 + sqrt(level-100) * 20) / 10
	if level <= 1000:
		var bonus = 100 + sqrt(level - 100) * 20
		return max(10, int(lethality * bonus / 10))

	# Level 1000+: lethality * (1000 + log(level) * 200) / 10
	var bonus = 1000 + log(level) * 200
	return max(10, int(lethality * bonus / 10))

func _calculate_gold_reward(base_stats: Dictionary, stat_scale: float, level: int) -> int:
	"""Calculate gold reward with level bonus for high-level monsters"""
	var base_gold = base_stats.base_gold
	var gold_scale = max(0.5, stat_scale)
	var gold_reward = base_gold * gold_scale

	# Add level bonus for level 100+
	if level >= 100:
		var level_bonus = 1.0 + log(level / 100.0) * 0.5
		gold_reward *= level_bonus

	# Apply variance
	gold_reward *= randf_range(0.8, 1.2)

	return max(1, int(gold_reward))

func to_dict() -> Dictionary:
	return {"initialized": true}
