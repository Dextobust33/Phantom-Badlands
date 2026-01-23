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
	TITAN
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
		possible_types = [
			MonsterType.GOBLIN,
			MonsterType.GIANT_RAT,
			MonsterType.KOBOLD,
			MonsterType.SKELETON,
			MonsterType.WOLF
		]
	elif level <= 15:
		possible_types = [
			MonsterType.ORC,
			MonsterType.HOBGOBLIN,
			MonsterType.GNOLL,
			MonsterType.ZOMBIE,
			MonsterType.GIANT_SPIDER,
			MonsterType.WIGHT
		]
	elif level <= 30:
		possible_types = [
			MonsterType.OGRE,
			MonsterType.TROLL,
			MonsterType.WRAITH,
			MonsterType.WYVERN,
			MonsterType.MINOTAUR
		]
	elif level <= 50:
		possible_types = [
			MonsterType.GIANT,
			MonsterType.DRAGON_WYRMLING,
			MonsterType.DEMON,
			MonsterType.VAMPIRE
		]
	else:
		possible_types = [
			MonsterType.ANCIENT_DRAGON,
			MonsterType.DEMON_LORD,
			MonsterType.LICH,
			MonsterType.TITAN
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
				"flock_chance": 35,  # Goblins travel in groups
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
				"flock_chance": 40,  # Rats swarm together
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
				"flock_chance": 30,  # Kobolds work in packs
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
				"flock_chance": 25,  # Often rise in groups
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
				"flock_chance": 45,  # Hunt in packs
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
				"flock_chance": 30,  # War bands
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
				"flock_chance": 35,  # Military formations
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
				"flock_chance": 40,  # Pack hunters
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
				"flock_chance": 50,  # Hordes of undead
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
				"flock_chance": 25,  # Nest clusters
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
				"flock_chance": 15,  # Usually solitary
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
				"flock_chance": 10,  # Solitary brutes
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
				"flock_chance": 15,  # Territorial loners
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
				"flock_chance": 20,  # Haunted places
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
				"flock_chance": 5,  # Rare apex predator
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
				"flock_chance": 10,  # Labyrinth guardians
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
				"flock_chance": 5,  # Solitary titans
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
				"flock_chance": 0,  # Unique encounter
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
				"flock_chance": 15,  # Summoned in pairs
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
				"flock_chance": 0,  # Lone predators
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
				"flock_chance": 0,  # Legendary unique
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
				"flock_chance": 0,  # Supreme evil
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
				"flock_chance": 0,  # Solitary mastermind
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
				"flock_chance": 0,  # Primordial deity
				"description": "A godlike being from the dawn of time"
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
	"""Scale monster stats to match target level"""
	var level_diff = target_level - base_stats.base_level

	# Scale factor for stats - minimum 0.25 to prevent negative/zero stats
	var stat_scale = max(0.25, 1.0 + (level_diff * 0.12))

	# Calculate scaled combat stats
	var scaled_hp = max(5, int(base_stats.base_hp * stat_scale))
	var scaled_strength = max(3, int(base_stats.base_strength * stat_scale))
	var scaled_defense = max(1, int(base_stats.base_defense * stat_scale))

	# Experience based on lethality: (HP + Strength*3 + Defense) * Level / 10
	# This rewards fighting dangerous, high-level monsters
	var lethality = scaled_hp + (scaled_strength * 3) + scaled_defense
	var experience_reward = max(10, int((lethality * target_level) / 10))

	# Gold based on monster tier with some variance, minimum 1
	var base_gold = base_stats.base_gold
	var gold_scale = max(0.5, stat_scale)
	var gold_reward = max(1, int(base_gold * gold_scale * randf_range(0.8, 1.2)))

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
		"description": base_stats.description
	}

func to_dict() -> Dictionary:
	return {"initialized": true}
