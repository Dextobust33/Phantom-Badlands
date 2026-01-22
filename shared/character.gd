# character.gd
# Simple Character class - extends Resource so it can be easily serialized
class_name Character
extends Resource

# Basic Info
@export var character_id: int = 0
@export var name: String = ""
@export var class_type: String = ""
@export var level: int = 1
@export var experience: int = 0
@export var experience_to_next_level: int = 100

# Primary Stats
@export var strength: int = 10
@export var constitution: int = 10
@export var dexterity: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

# Current State
@export var current_hp: int = 100
@export var max_hp: int = 100
@export var current_mana: int = 50
@export var max_mana: int = 50

# Location & Status (Phantasia 4 style coordinates)
@export var x: int = 0  # X coordinate
@export var y: int = 10  # Y coordinate (start at Sanctuary)
@export var gold: int = 100

# Combat
@export var in_combat: bool = false

func _init():
	# Constructor
	pass

func initialize(char_name: String, char_class: String):
	"""Initialize a new character with starting values"""
	name = char_name
	class_type = char_class
	level = 1
	experience = 0
	
	# Set starting stats based on class
	var starting_stats = get_starting_stats_for_class(char_class)
	strength = starting_stats.strength
	constitution = starting_stats.constitution
	dexterity = starting_stats.dexterity
	intelligence = starting_stats.intelligence
	wisdom = starting_stats.wisdom
	charisma = starting_stats.charisma
	
	# Calculate derived stats
	calculate_derived_stats()
	
	# Start with full health and mana
	current_hp = max_hp
	current_mana = max_mana
	
	# Starting location - Sanctuary (0, 10) like Phantasia 4
	x = 0
	y = 10
	gold = 100

func get_starting_stats_for_class(char_class: String) -> Dictionary:
	"""Get starting stats based on character class"""
	var stats = {
		"Fighter": {"strength": 14, "constitution": 13, "dexterity": 11, "intelligence": 8, "wisdom": 8, "charisma": 10},
		"Barbarian": {"strength": 16, "constitution": 14, "dexterity": 10, "intelligence": 6, "wisdom": 8, "charisma": 8},
		"Paladin": {"strength": 13, "constitution": 14, "dexterity": 10, "intelligence": 9, "wisdom": 12, "charisma": 12},
		"Wizard": {"strength": 8, "constitution": 10, "dexterity": 11, "intelligence": 16, "wisdom": 13, "charisma": 10},
		"Sorcerer": {"strength": 8, "constitution": 9, "dexterity": 10, "intelligence": 17, "wisdom": 11, "charisma": 11},
		"Sage": {"strength": 8, "constitution": 11, "dexterity": 10, "intelligence": 12, "wisdom": 16, "charisma": 12},
		"Thief": {"strength": 10, "constitution": 10, "dexterity": 17, "intelligence": 11, "wisdom": 10, "charisma": 10},
		"Ranger": {"strength": 12, "constitution": 12, "dexterity": 15, "intelligence": 10, "wisdom": 12, "charisma": 10},
		"Ninja": {"strength": 11, "constitution": 10, "dexterity": 17, "intelligence": 12, "wisdom": 11, "charisma": 10}
	}
	
	return stats.get(char_class, stats["Fighter"])

func calculate_derived_stats():
	"""Calculate HP, mana, etc. from primary stats"""
	max_hp = (constitution * 10) + (level * 5)
	max_mana = (intelligence * 8) + (wisdom * 4)

func get_health_state() -> String:
	"""Get current health state description"""
	var percent = (float(current_hp) / float(max_hp)) * 100.0
	if percent >= 70:
		return "Healthy"
	elif percent >= 30:
		return "Wounded"
	elif percent >= 10:
		return "Bloodied"
	else:
		return "Critical"

func get_stat(stat_name: String) -> int:
	"""Get a stat value by name"""
	match stat_name.to_lower():
		"strength", "str":
			return strength
		"constitution", "con":
			return constitution
		"dexterity", "dex":
			return dexterity
		"intelligence", "int":
			return intelligence
		"wisdom", "wis":
			return wisdom
		"charisma", "cha":
			return charisma
		_:
			return 0

func get_attack_damage() -> Dictionary:
	"""Calculate attack damage range"""
	var base_damage = strength
	var min_damage = int(base_damage * 0.8)
	var max_damage = int(base_damage * 1.2)
	
	return {
		"min": min_damage,
		"max": max_damage,
		"base": base_damage
	}

func take_damage(damage: int) -> Dictionary:
	"""Apply damage and return result"""
	current_hp -= damage
	
	var result = {
		"damage": damage,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"health_state": get_health_state(),
		"died": false
	}
	
	if current_hp <= 0:
		current_hp = 0
		result.died = true
	
	return result

func heal(amount: int) -> int:
	"""Heal the character, return actual amount healed"""
	var old_hp = current_hp
	current_hp = min(current_hp + amount, max_hp)
	return current_hp - old_hp

func check_level_up():
	"""Check if character should level up"""
	var exp_table = {
		2: 100, 3: 250, 4: 500, 5: 1000,
		10: 10000, 20: 50000, 50: 500000
	}
	var required_exp = exp_table.get(level + 1, int(pow(level + 1, 2.5) * 100))
	
	if experience >= required_exp:
		level_up()

func level_up():
	"""Increase level and stats"""
	level += 1
	
	# Get stat gains for class
	var gains = get_stat_gains_for_class()
	
	strength += gains.strength
	constitution += gains.constitution
	dexterity += gains.dexterity
	intelligence += gains.intelligence
	wisdom += gains.wisdom
	charisma += gains.charisma
	
	# Recalculate derived stats
	calculate_derived_stats()
	
	# Full heal on level up
	current_hp = max_hp
	current_mana = max_mana

func get_stat_gains_for_class() -> Dictionary:
	"""Get stat increases per level based on class"""
	var gains = {
		"Fighter": {"strength": 3, "constitution": 2, "dexterity": 1, "intelligence": 0, "wisdom": 0, "charisma": 1},
		"Barbarian": {"strength": 4, "constitution": 2, "dexterity": 1, "intelligence": 0, "wisdom": 0, "charisma": 0},
		"Paladin": {"strength": 2, "constitution": 3, "dexterity": 1, "intelligence": 1, "wisdom": 2, "charisma": 2},
		"Wizard": {"strength": 0, "constitution": 1, "dexterity": 1, "intelligence": 4, "wisdom": 2, "charisma": 1},
		"Sorcerer": {"strength": 0, "constitution": 1, "dexterity": 1, "intelligence": 5, "wisdom": 1, "charisma": 1},
		"Sage": {"strength": 0, "constitution": 2, "dexterity": 1, "intelligence": 2, "wisdom": 4, "charisma": 2},
		"Thief": {"strength": 1, "constitution": 1, "dexterity": 5, "intelligence": 1, "wisdom": 1, "charisma": 1},
		"Ranger": {"strength": 2, "constitution": 2, "dexterity": 4, "intelligence": 1, "wisdom": 2, "charisma": 1},
		"Ninja": {"strength": 2, "constitution": 1, "dexterity": 5, "intelligence": 2, "wisdom": 1, "charisma": 1}
	}
	
	return gains.get(class_type, gains["Fighter"])

func to_dict() -> Dictionary:
	"""Convert character to dictionary for network transmission"""
	return {
		"id": character_id,
		"name": name,
		"class": class_type,
		"level": level,
		"experience": experience,
		"experience_to_next_level": experience_to_next_level,
		"stats": {
			"strength": strength,
			"constitution": constitution,
			"dexterity": dexterity,
			"intelligence": intelligence,
			"wisdom": wisdom,
			"charisma": charisma
		},
		"current_hp": current_hp,
		"max_hp": max_hp,
		"current_mana": current_mana,
		"max_mana": max_mana,
		"x": x,
		"y": y,
		"health_state": get_health_state(),
		"gold": gold,
		"in_combat": in_combat
	}

func from_dict(data: Dictionary):
	"""Load character from dictionary"""
	character_id = data.get("id", 0)
	name = data.get("name", "")
	class_type = data.get("class", "Fighter")
	level = data.get("level", 1)
	experience = data.get("experience", 0)
	
	var stats = data.get("stats", {})
	strength = stats.get("strength", 10)
	constitution = stats.get("constitution", 10)
	dexterity = stats.get("dexterity", 10)
	intelligence = stats.get("intelligence", 10)
	wisdom = stats.get("wisdom", 10)
	charisma = stats.get("charisma", 10)
	
	current_hp = data.get("current_hp", 100)
	max_hp = data.get("max_hp", 100)
	current_mana = data.get("current_mana", 50)
	max_mana = data.get("max_mana", 50)
	
	x = data.get("x", 0)
	y = data.get("y", 10)
	gold = data.get("gold", 100)
	in_combat = data.get("in_combat", false)
	experience_to_next_level = data.get("experience_to_next_level", 100)

func add_experience(amount: int) -> Dictionary:
	"""Add experience and check for level up"""
	experience += amount
	var leveled_up = false
	var levels_gained = 0
	
	# Check for level ups (can gain multiple levels)
	while experience >= experience_to_next_level:
		experience -= experience_to_next_level
		level += 1
		levels_gained += 1
		leveled_up = true
		
		# Increase stats on level up
		strength += 1
		constitution += 1
		dexterity += 1
		intelligence += 1
		wisdom += 1
		charisma += 1
		
		# Increase HP and Mana
		max_hp += 10 + (constitution / 2)
		max_mana += 5 + (intelligence / 2)
		
		# Fully heal on level up
		current_hp = max_hp
		current_mana = max_mana
		
		# Calculate next level requirement (increases by 50% each level)
		experience_to_next_level = int(experience_to_next_level * 1.5)
	
	return {
		"leveled_up": leveled_up,
		"levels_gained": levels_gained,
		"new_level": level
	}

func get_experience_progress() -> int:
	"""Get experience progress as percentage"""
	if experience_to_next_level <= 0:
		return 100
	return int((float(experience) / experience_to_next_level) * 100)
