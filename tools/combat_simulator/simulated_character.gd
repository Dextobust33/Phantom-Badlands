# simulated_character.gd
# Lightweight character class for combat simulation
# Replicates combat-relevant methods from shared/character.gd
extends RefCounted
class_name SimulatedCharacter

# Core stats
var name: String = "Simulated"
var class_type: String = "Fighter"
var level: int = 1

# Primary stats
var strength: int = 10
var constitution: int = 10
var dexterity: int = 10
var intelligence: int = 10
var wisdom: int = 10
var wits: int = 10

# Derived stats
var max_hp: int = 100
var current_hp: int = 100
var max_mana: int = 50
var current_mana: int = 50
var max_stamina: int = 20
var current_stamina: int = 20
var max_energy: int = 20
var current_energy: int = 20

# Equipment bonuses (pre-calculated)
var equipment_attack: int = 0
var equipment_defense: int = 0
var equipment_hp: int = 0
var equipment_str: int = 0
var equipment_con: int = 0
var equipment_dex: int = 0
var equipment_int: int = 0
var equipment_wis: int = 0
var equipment_wits: int = 0
var equipment_speed: int = 0

# Combat state
var poison_active: bool = false
var poison_damage: int = 0
var poison_turns_remaining: int = 0
var blind_active: bool = false
var blind_turns_remaining: int = 0
var bleed_stacks: int = 0
var bleed_damage: int = 0

# Buff/debuff tracking
var buffs: Dictionary = {}  # {buff_name: {value: int, duration: int}}
var debuffs: Dictionary = {}

# Class starting stats (from character.gd lines 592-604)
const CLASS_STARTING_STATS = {
	"Fighter": {"strength": 14, "constitution": 13, "dexterity": 11, "intelligence": 8, "wisdom": 8, "wits": 10},
	"Barbarian": {"strength": 17, "constitution": 12, "dexterity": 10, "intelligence": 7, "wisdom": 8, "wits": 10},
	"Paladin": {"strength": 13, "constitution": 14, "dexterity": 10, "intelligence": 9, "wisdom": 12, "wits": 12},
	"Wizard": {"strength": 8, "constitution": 10, "dexterity": 10, "intelligence": 17, "wisdom": 12, "wits": 9},
	"Sorcerer": {"strength": 8, "constitution": 9, "dexterity": 10, "intelligence": 17, "wisdom": 11, "wits": 11},
	"Sage": {"strength": 8, "constitution": 12, "dexterity": 10, "intelligence": 13, "wisdom": 15, "wits": 9},
	"Thief": {"strength": 9, "constitution": 9, "dexterity": 14, "intelligence": 9, "wisdom": 9, "wits": 16},
	"Ranger": {"strength": 12, "constitution": 11, "dexterity": 12, "intelligence": 9, "wisdom": 9, "wits": 14},
	"Ninja": {"strength": 11, "constitution": 10, "dexterity": 17, "intelligence": 12, "wisdom": 11, "wits": 10}
}

# Class passive effects (from character.gd lines 609-714)
const CLASS_PASSIVES = {
	"Fighter": {
		"name": "Tactical Discipline",
		"effects": {
			"stamina_cost_reduction": 0.20,
			"defense_bonus_percent": 0.15
		}
	},
	"Barbarian": {
		"name": "Blood Rage",
		"effects": {
			"damage_per_missing_hp": 0.03,
			"max_rage_bonus": 0.30,
			"stamina_cost_increase": 0.25
		}
	},
	"Paladin": {
		"name": "Divine Favor",
		"effects": {
			"combat_regen_percent": 0.03,
			"bonus_vs_undead": 0.25
		}
	},
	"Wizard": {
		"name": "Arcane Precision",
		"effects": {
			"spell_damage_bonus": 0.15,
			"spell_crit_bonus": 0.10
		}
	},
	"Sorcerer": {
		"name": "Chaos Magic",
		"effects": {
			"double_damage_chance": 0.25,
			"backfire_chance": 0.05
		}
	},
	"Sage": {
		"name": "Mana Mastery",
		"effects": {
			"mana_cost_reduction": 0.25,
			"meditate_bonus": 0.50
		}
	},
	"Thief": {
		"name": "Backstab",
		"effects": {
			"crit_damage_bonus": 0.35,
			"crit_chance_bonus": 0.10
		}
	},
	"Ranger": {
		"name": "Hunter's Mark",
		"effects": {
			"bonus_vs_beasts": 0.25,
			"gold_bonus": 0.30,
			"xp_bonus": 0.30
		}
	},
	"Ninja": {
		"name": "Shadow Step",
		"effects": {
			"flee_bonus": 0.40,
			"flee_no_damage": true
		}
	}
}

# Stat growth per level (points to distribute)
const STAT_POINTS_PER_LEVEL = 5

func _init(char_class: String = "Fighter", char_level: int = 1):
	class_type = char_class
	level = char_level
	_initialize_stats()

func _initialize_stats():
	"""Initialize stats based on class and level"""
	# Get starting stats for class
	var starting = CLASS_STARTING_STATS.get(class_type, CLASS_STARTING_STATS["Fighter"])

	strength = starting.strength
	constitution = starting.constitution
	dexterity = starting.dexterity
	intelligence = starting.intelligence
	wisdom = starting.wisdom
	wits = starting.wits

	# Apply level-up stat distribution
	_apply_level_stats()

	# Calculate derived stats
	_calculate_derived_stats()

func _apply_level_stats():
	"""Apply stat points from leveling based on class priorities"""
	var points_to_distribute = (level - 1) * STAT_POINTS_PER_LEVEL

	# Get stat priority order based on class
	var priorities = _get_stat_priorities()

	# Distribute points (60% primary, 25% secondary, 15% tertiary)
	var primary_points = int(points_to_distribute * 0.60)
	var secondary_points = int(points_to_distribute * 0.25)
	var tertiary_points = points_to_distribute - primary_points - secondary_points

	# Apply points
	_add_stat(priorities[0], primary_points)
	_add_stat(priorities[1], secondary_points)
	_add_stat(priorities[2], tertiary_points)

func _get_stat_priorities() -> Array:
	"""Return stat priority order for each class [primary, secondary, tertiary]"""
	match class_type:
		"Fighter":
			return ["strength", "constitution", "dexterity"]
		"Barbarian":
			return ["strength", "constitution", "dexterity"]
		"Paladin":
			return ["constitution", "strength", "wisdom"]
		"Wizard":
			return ["intelligence", "wisdom", "constitution"]
		"Sorcerer":
			return ["intelligence", "wits", "dexterity"]
		"Sage":
			return ["wisdom", "intelligence", "constitution"]
		"Thief":
			return ["dexterity", "wits", "strength"]
		"Ranger":
			return ["dexterity", "strength", "wits"]
		"Ninja":
			return ["dexterity", "wits", "intelligence"]
		_:
			return ["strength", "constitution", "dexterity"]

func _add_stat(stat_name: String, amount: int):
	"""Add points to a stat"""
	match stat_name:
		"strength": strength += amount
		"constitution": constitution += amount
		"dexterity": dexterity += amount
		"intelligence": intelligence += amount
		"wisdom": wisdom += amount
		"wits": wits += amount

func _calculate_derived_stats():
	"""Calculate HP, mana, stamina, energy from primary stats"""
	# HP formula: Base 50 + CON × 5 + primary stat contribution
	var primary_stat_bonus = _get_primary_stat_for_hp()
	max_hp = 50 + (constitution * 5) + primary_stat_bonus

	# Resource pools
	max_mana = int((intelligence * 3) + (wisdom * 1.5))
	max_stamina = strength + constitution
	max_energy = int((wits + dexterity) * 0.75)

	# Apply equipment bonuses to max pools
	max_hp += equipment_hp + (equipment_con * 5)
	max_mana += int(equipment_int * 3) + int(equipment_wis * 1.5)
	max_stamina += equipment_str + equipment_con
	max_energy += int((equipment_wits + equipment_dex) * 0.75)

	# Set current to max
	current_hp = max_hp
	current_mana = max_mana
	current_stamina = max_stamina
	current_energy = max_energy

func _get_primary_stat_for_hp() -> int:
	"""Get HP bonus from primary class stat"""
	match class_type:
		"Fighter", "Barbarian", "Paladin":
			return int(strength * 0.5)
		"Wizard", "Sorcerer", "Sage":
			return int(intelligence * 0.3)
		"Thief", "Ranger", "Ninja":
			return int(dexterity * 0.4)
		_:
			return 0

func get_class_passive() -> Dictionary:
	"""Get the unique passive ability for this character's class"""
	return CLASS_PASSIVES.get(class_type, {"name": "None", "effects": {}})

func get_effective_stat(stat_name: String) -> int:
	"""Get stat value including equipment bonuses"""
	match stat_name.to_lower():
		"strength", "str":
			return strength + equipment_str
		"constitution", "con":
			return constitution + equipment_con
		"dexterity", "dex":
			return dexterity + equipment_dex
		"intelligence", "int":
			return intelligence + equipment_int
		"wisdom", "wis":
			return wisdom + equipment_wis
		"wits":
			return wits + equipment_wits
		_:
			return 10

func get_total_attack() -> int:
	"""Get total attack power including equipment"""
	return strength + equipment_str + equipment_attack

func get_total_defense() -> int:
	"""Get total defense including equipment"""
	return int(constitution / 2) + equipment_defense

func get_equipment_defense() -> int:
	"""Get defense bonus from equipment only"""
	return equipment_defense

func get_total_max_hp() -> int:
	"""Get total max HP including equipment bonuses"""
	return max_hp

func get_total_max_mana() -> int:
	"""Get total max mana"""
	return max_mana

func apply_equipment(gear: Dictionary):
	"""Apply equipment bonuses from a gear dictionary"""
	equipment_attack = gear.get("attack", 0)
	equipment_defense = gear.get("defense", 0)
	equipment_hp = gear.get("max_hp", 0)
	equipment_str = gear.get("strength", 0)
	equipment_con = gear.get("constitution", 0)
	equipment_dex = gear.get("dexterity", 0)
	equipment_int = gear.get("intelligence", 0)
	equipment_wis = gear.get("wisdom", 0)
	equipment_wits = gear.get("wits", 0)
	equipment_speed = gear.get("speed", 0)

	# Recalculate derived stats with equipment
	_calculate_derived_stats()

func heal(amount: int) -> int:
	"""Heal HP, returns actual amount healed"""
	var actual = min(amount, max_hp - current_hp)
	current_hp += actual
	return actual

func add_buff(buff_name: String, value: int, duration: int):
	"""Add a buff"""
	buffs[buff_name] = {"value": value, "duration": duration}

func remove_buff(buff_name: String):
	"""Remove a buff"""
	buffs.erase(buff_name)

func get_buff_value(buff_name: String) -> int:
	"""Get current value of a buff"""
	if buffs.has(buff_name):
		return buffs[buff_name].value
	return 0

func has_buff(buff_name: String) -> bool:
	"""Check if buff is active"""
	return buffs.has(buff_name)

func apply_debuff(debuff_name: String, value: int, duration: int):
	"""Apply a debuff"""
	debuffs[debuff_name] = {"value": value, "duration": duration}

func has_debuff(debuff_name: String) -> bool:
	"""Check if debuff is active"""
	return debuffs.has(debuff_name)

func get_debuff_value(debuff_name: String) -> int:
	"""Get debuff value"""
	if debuffs.has(debuff_name):
		return debuffs[debuff_name].value
	return 0

func apply_poison(damage: int, duration: int):
	"""Apply poison status"""
	poison_active = true
	poison_damage = damage
	poison_turns_remaining = duration

func apply_blind(duration: int):
	"""Apply blind status"""
	blind_active = true
	blind_turns_remaining = duration

func tick_status_effects() -> Array:
	"""Process per-turn status effects, return messages"""
	var messages = []

	# Poison tick
	if poison_active and poison_turns_remaining > 0:
		current_hp -= poison_damage
		poison_turns_remaining -= 1
		messages.append("Poison deals %d damage (%d turns remaining)" % [poison_damage, poison_turns_remaining])
		if poison_turns_remaining <= 0:
			poison_active = false

	# Blind tick
	if blind_active and blind_turns_remaining > 0:
		blind_turns_remaining -= 1
		if blind_turns_remaining <= 0:
			blind_active = false
			messages.append("Blindness fades")

	# Tick buff durations
	var expired_buffs = []
	for buff_name in buffs:
		buffs[buff_name].duration -= 1
		if buffs[buff_name].duration <= 0:
			expired_buffs.append(buff_name)
	for buff_name in expired_buffs:
		buffs.erase(buff_name)

	# Tick debuff durations
	var expired_debuffs = []
	for debuff_name in debuffs:
		debuffs[debuff_name].duration -= 1
		if debuffs[debuff_name].duration <= 0:
			expired_debuffs.append(debuff_name)
	for debuff_name in expired_debuffs:
		debuffs.erase(debuff_name)

	return messages

func reset_for_combat():
	"""Reset combat state for a new fight"""
	current_hp = max_hp
	current_mana = max_mana
	current_stamina = max_stamina
	current_energy = max_energy
	poison_active = false
	poison_damage = 0
	poison_turns_remaining = 0
	blind_active = false
	blind_turns_remaining = 0
	bleed_stacks = 0
	bleed_damage = 0
	buffs.clear()
	debuffs.clear()

func get_class_path() -> String:
	"""Get the combat path of the character class"""
	match class_type.to_lower():
		"fighter", "barbarian", "paladin":
			return "warrior"
		"wizard", "sorcerer", "sage":
			return "mage"
		"thief", "ranger", "ninja":
			return "trickster"
		_:
			return "warrior"

func is_trickster() -> bool:
	"""Check if character is a trickster class"""
	return class_type in ["Thief", "Ranger", "Ninja"]

func is_mage() -> bool:
	"""Check if character is a mage class"""
	return class_type in ["Wizard", "Sorcerer", "Sage"]

func is_warrior() -> bool:
	"""Check if character is a warrior class"""
	return class_type in ["Fighter", "Barbarian", "Paladin"]

static func get_all_classes() -> Array:
	"""Get list of all class types"""
	return ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]
