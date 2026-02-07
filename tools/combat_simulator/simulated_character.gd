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

# Race (for racial passives)
var race: String = "Human"

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
var equipment_max_mana: int = 0
var equipment_max_stamina: int = 0
var equipment_max_energy: int = 0

# Per-turn resource regeneration from gear
var stamina_regen: int = 0
var mana_regen: int = 0
var energy_regen: int = 0

# Proc effects from equipment (tier 6+ items)
var lifesteal_percent: int = 0    # % of damage healed on hit
var execute_chance: int = 0       # % chance to trigger execute
var execute_bonus: int = 0        # % bonus damage when enemy < 30% HP
var shocking_chance: int = 0      # % chance for bonus lightning damage
var shocking_bonus: int = 0       # % bonus damage from shocking
var damage_reflect_percent: int = 0  # % of incoming damage reflected

# Racial combat flags
var last_stand_used: bool = false

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

# Per-class fractional stat gains per level (from character.gd lines 1176-1191)
# Total: 2.5 stats per level for all classes
const CLASS_STAT_GAINS = {
	"Fighter": {"strength": 1.25, "constitution": 0.75, "dexterity": 0.25, "intelligence": 0.0, "wisdom": 0.0, "wits": 0.25},
	"Barbarian": {"strength": 1.5, "constitution": 0.75, "dexterity": 0.25, "intelligence": 0.0, "wisdom": 0.0, "wits": 0.0},
	"Paladin": {"strength": 0.75, "constitution": 1.0, "dexterity": 0.25, "intelligence": 0.0, "wisdom": 0.25, "wits": 0.25},
	"Wizard": {"strength": 0.0, "constitution": 0.40, "dexterity": 0.25, "intelligence": 1.10, "wisdom": 0.75, "wits": 0.0},
	"Sage": {"strength": 0.0, "constitution": 0.5, "dexterity": 0.25, "intelligence": 0.75, "wisdom": 1.0, "wits": 0.0},
	"Sorcerer": {"strength": 0.0, "constitution": 0.35, "dexterity": 0.25, "intelligence": 1.40, "wisdom": 0.50, "wits": 0.0},
	"Thief": {"strength": 0.0, "constitution": 0.25, "dexterity": 0.75, "intelligence": 0.0, "wisdom": 0.0, "wits": 1.5},
	"Ranger": {"strength": 0.25, "constitution": 0.5, "dexterity": 0.75, "intelligence": 0.0, "wisdom": 0.0, "wits": 1.0},
	"Ninja": {"strength": 0.0, "constitution": 0.25, "dexterity": 1.25, "intelligence": 0.0, "wisdom": 0.0, "wits": 1.0}
}

# Racial passives (from character.gd lines 1800-1942)
const RACIAL_PASSIVES = {
	"Human": {"xp_bonus": 0.10},  # +10% XP (no combat effect)
	"Elf": {"max_mana_bonus": 0.25, "poison_damage_mult": 0.5, "magic_resist": 0.20},
	"Dwarf": {"last_stand_chance": 0.34},  # 34% survive lethal at 1 HP, once per combat
	"Orc": {"low_hp_damage_bonus": 0.20},  # +20% damage below 50% HP
	"Halfling": {"dodge_bonus": 0.10, "crit_bonus": 0.05},  # +10% dodge, +5% crit
	"Gnome": {"ability_cost_mult": 0.85},  # -15% ability resource costs
	"Ogre": {"heal_mult": 2.0},  # 2x healing effectiveness
	"Undead": {"poison_heals": true, "death_curse_immune": true}  # Poison heals, immune to death curse
}

# Optimal race per class path for ceiling testing
const OPTIMAL_RACE = {
	"Fighter": "Dwarf", "Barbarian": "Orc", "Paladin": "Dwarf",
	"Wizard": "Elf", "Sorcerer": "Gnome", "Sage": "Elf",
	"Thief": "Halfling", "Ranger": "Halfling", "Ninja": "Halfling"
}

func _init(char_class: String = "Fighter", char_level: int = 1):
	class_type = char_class
	level = char_level
	race = OPTIMAL_RACE.get(char_class, "Human")
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

	# Apply level-up stat distribution using fractional accumulation
	_apply_level_stats()

	# Calculate derived stats
	_calculate_derived_stats()

func _apply_level_stats():
	"""Apply stat gains from leveling using fractional accumulation (matches character.gd)"""
	var gains = CLASS_STAT_GAINS.get(class_type, CLASS_STAT_GAINS["Fighter"])
	var levels_to_apply = level - 1
	if levels_to_apply <= 0:
		return

	# Use stat_accumulator pattern matching character.gd lines 1526-1537
	var accumulator = {
		"strength": 0.0, "constitution": 0.0, "dexterity": 0.0,
		"intelligence": 0.0, "wisdom": 0.0, "wits": 0.0
	}

	for _i in range(levels_to_apply):
		for stat_name in ["strength", "constitution", "dexterity", "intelligence", "wisdom", "wits"]:
			accumulator[stat_name] += gains.get(stat_name, 0.0)
			var whole_gain = int(accumulator[stat_name])
			if whole_gain >= 1:
				accumulator[stat_name] -= whole_gain
				_add_stat(stat_name, whole_gain)

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
	max_mana += int(equipment_int * 3) + int(equipment_wis * 1.5) + equipment_max_mana
	max_stamina += equipment_str + equipment_con + equipment_max_stamina
	max_energy += int((equipment_wits + equipment_dex) * 0.75) + equipment_max_energy

	# Elf racial: +25% max mana
	var racial = get_racial_passive()
	if racial.has("max_mana_bonus"):
		max_mana = int(max_mana * (1.0 + racial.max_mana_bonus))

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
	equipment_max_mana = gear.get("max_mana", 0)
	equipment_max_stamina = gear.get("max_stamina", 0)
	equipment_max_energy = gear.get("max_energy", 0)
	stamina_regen = gear.get("stamina_regen", 0)
	mana_regen = gear.get("mana_regen", 0)
	energy_regen = gear.get("energy_regen", 0)

	# Proc effects
	lifesteal_percent = gear.get("lifesteal_percent", 0)
	execute_chance = gear.get("execute_chance", 0)
	execute_bonus = gear.get("execute_bonus", 0)
	shocking_chance = gear.get("shocking_chance", 0)
	shocking_bonus = gear.get("shocking_bonus", 0)
	damage_reflect_percent = gear.get("damage_reflect_percent", 0)

	# Recalculate derived stats with equipment (includes max_stamina/max_energy from gear)
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

	# Poison tick (Undead: poison heals instead of damages)
	if poison_active and poison_turns_remaining > 0:
		if does_poison_heal():
			var heal_amount = max(1, int(poison_damage * 0.5))
			current_hp = mini(max_hp, current_hp + heal_amount)
			messages.append("Poison heals %d HP (Undead)" % heal_amount)
		else:
			current_hp -= poison_damage
			messages.append("Poison deals %d damage (%d turns remaining)" % [poison_damage, poison_turns_remaining])
		poison_turns_remaining -= 1
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
	"""Reset combat state for a new fight (proc effects persist from equipment)"""
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
	last_stand_used = false
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

func get_racial_passive() -> Dictionary:
	"""Get racial passive effects"""
	return RACIAL_PASSIVES.get(race, {})

func get_poison_damage_multiplier() -> float:
	"""Elf takes 50% poison damage"""
	var racial = get_racial_passive()
	return racial.get("poison_damage_mult", 1.0)

func does_poison_heal() -> bool:
	"""Undead: poison heals instead of damages"""
	return get_racial_passive().get("poison_heals", false)

func is_death_curse_immune() -> bool:
	"""Undead: immune to death curse"""
	return get_racial_passive().get("death_curse_immune", false)

func try_last_stand() -> bool:
	"""Dwarf: 34% chance to survive lethal hit at 1 HP, once per combat"""
	if race != "Dwarf" or last_stand_used:
		return false
	var chance = get_racial_passive().get("last_stand_chance", 0.34)
	if randf() < chance:
		last_stand_used = true
		current_hp = 1
		return true
	return false

func get_dodge_bonus() -> float:
	"""Halfling: +10% dodge"""
	return get_racial_passive().get("dodge_bonus", 0.0)

func get_crit_bonus() -> float:
	"""Halfling: +5% crit chance"""
	return get_racial_passive().get("crit_bonus", 0.0)

func get_low_hp_damage_bonus() -> float:
	"""Orc: +20% damage below 50% HP"""
	var racial = get_racial_passive()
	if racial.has("low_hp_damage_bonus") and current_hp < max_hp * 0.5:
		return racial.low_hp_damage_bonus
	return 0.0

func get_ability_cost_multiplier() -> float:
	"""Gnome: -15% ability costs"""
	return get_racial_passive().get("ability_cost_mult", 1.0)

func get_heal_multiplier() -> float:
	"""Ogre: 2x healing"""
	return get_racial_passive().get("heal_mult", 1.0)

static func get_all_classes() -> Array:
	"""Get list of all class types"""
	return ["Fighter", "Barbarian", "Paladin", "Wizard", "Sorcerer", "Sage", "Thief", "Ranger", "Ninja"]
