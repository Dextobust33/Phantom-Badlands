# character.gd
# Simple Character class - extends Resource so it can be easily serialized
class_name Character
extends Resource

# Basic Info
@export var character_id: int = 0
@export var name: String = ""
@export var race: String = "Human"  # Human, Elf, Dwarf, or Ogre
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
@export var wits: int = 10  # Renamed from charisma - used for outsmarting enemies

# Current State
@export var current_hp: int = 100
@export var max_hp: int = 100
@export var current_mana: int = 50
@export var max_mana: int = 50
@export var current_stamina: int = 80  # Warrior resource
@export var max_stamina: int = 80      # STR*4 + CON*4
@export var current_energy: int = 80   # Trickster resource
@export var max_energy: int = 80       # WITS*4 + DEX*4

# Location & Status (Phantasia 4 style coordinates)
@export var x: int = 0  # X coordinate
@export var y: int = 10  # Y coordinate (start at Sanctuary)
@export var gold: int = 100
@export var gems: int = 0  # Premium currency from high-level monsters

# Combat
@export var in_combat: bool = false
@export var last_stand_used: bool = false  # Dwarf racial - resets each combat

# Poison status (persists outside combat)
@export var poison_active: bool = false
@export var poison_damage: int = 0
@export var poison_turns_remaining: int = 0  # Decrements each combat turn

# Blind status (persists outside combat - reduces vision and hides monster HP)
@export var blind_active: bool = false
@export var blind_turns_remaining: int = 0  # Decrements each combat turn

# All or Nothing ability - usage count increases success chance over time
@export var all_or_nothing_uses: int = 0

# Forced next monster (from Monster Selection Scroll)
@export var forced_next_monster: String = ""  # Monster name, empty = random

# Target farming (from Target Farming Scroll)
@export var target_farm_ability: String = ""  # Ability to add to next encounters
@export var target_farm_remaining: int = 0    # Number of encounters remaining

# Pending monster debuffs (from debuff scrolls) - applied at start of next combat
# Array of {type: String, value: int} - types: "weakness", "vulnerability", "slow", "doom"
@export var pending_monster_debuffs: Array = []

# Inventory System (stubs for future item drops)
@export var inventory: Array = []  # Array of item dictionaries
@export var equipped: Dictionary = {
	"weapon": null,
	"armor": null,
	"helm": null,
	"shield": null,
	"boots": null,
	"ring": null,
	"amulet": null
}
const MAX_INVENTORY_SIZE = 40
const MAX_STACK_SIZE = 99

# Thematic Equipment Display - each class sees equipment with themed names
# Maps class -> slot -> display name for that slot type
const CLASS_EQUIPMENT_THEMES = {
	# Warrior Path - Heavy armor, martial weapons
	"Fighter": {
		"weapon": "Sword", "shield": "Shield", "armor": "Plate",
		"helm": "Helm", "boots": "Greaves", "ring": "Signet", "amulet": "Medallion"
	},
	"Barbarian": {
		"weapon": "Axe", "shield": "Buckler", "armor": "Chainmail",
		"helm": "Helm", "boots": "Boots", "ring": "Band", "amulet": "Torc"
	},
	"Paladin": {
		"weapon": "Mace", "shield": "Aegis", "armor": "Plate",
		"helm": "Crown", "boots": "Sabatons", "ring": "Ring", "amulet": "Pendant"
	},
	# Mage Path - Cloth robes, magical implements
	"Wizard": {
		"weapon": "Staff", "shield": "Orb", "armor": "Robes",
		"helm": "Hood", "boots": "Slippers", "ring": "Ring", "amulet": "Amulet"
	},
	"Sorcerer": {
		"weapon": "Wand", "shield": "Focus", "armor": "Vestments",
		"helm": "Cowl", "boots": "Shoes", "ring": "Band", "amulet": "Talisman"
	},
	"Sage": {
		"weapon": "Tome", "shield": "Codex", "armor": "Vestments",
		"helm": "Circlet", "boots": "Sandals", "ring": "Ring", "amulet": "Pendant"
	},
	# Trickster Path - Light leather, agile weapons
	"Thief": {
		"weapon": "Dagger", "shield": "Parry Blade", "armor": "Leathers",
		"helm": "Mask", "boots": "Boots", "ring": "Ring", "amulet": "Charm"
	},
	"Ranger": {
		"weapon": "Bow", "shield": "Quiver", "armor": "Leathers",
		"helm": "Hood", "boots": "Boots", "ring": "Band", "amulet": "Locket"
	},
	"Ninja": {
		"weapon": "Katana", "shield": "Shuriken", "armor": "Garb",
		"helm": "Mask", "boots": "Tabi", "ring": "Ring", "amulet": "Pendant"
	}
}

# Generic slot names used in item generation (these get replaced with themed versions)
const GENERIC_SLOT_NAMES = {
	"weapon": ["Weapon", "Sword", "Axe", "Mace", "Staff", "Wand", "Tome", "Dagger", "Bow", "Katana", "Blade"],
	"shield": ["Shield", "Buckler", "Aegis", "Orb", "Focus", "Codex", "Parry Blade", "Quiver", "Shuriken"],
	"armor": ["Armor", "Plate", "Chainmail", "Robes", "Vestments", "Leathers", "Garb", "Mail"],
	"helm": ["Helm", "Helmet", "Crown", "Hood", "Cowl", "Circlet", "Mask", "Cap"],
	"boots": ["Boots", "Greaves", "Sabatons", "Slippers", "Shoes", "Sandals", "Tabi", "Footwear"],
	"ring": ["Ring", "Signet", "Band"],
	"amulet": ["Amulet", "Medallion", "Torc", "Pendant", "Talisman", "Charm", "Locket", "Necklace"]
}

static func get_themed_item_name(item_name: String, slot: String, class_type: String) -> String:
	"""Transform an item name to use class-themed slot terminology.
	Example: 'Mythical Steel Weapon' -> 'Mythical Steel Bow' for Ranger"""
	if not CLASS_EQUIPMENT_THEMES.has(class_type):
		return item_name
	if not CLASS_EQUIPMENT_THEMES[class_type].has(slot):
		return item_name

	var themed_name = CLASS_EQUIPMENT_THEMES[class_type][slot]
	var generic_names = GENERIC_SLOT_NAMES.get(slot, [])

	# Replace any generic slot name with the themed version
	var result = item_name
	for generic in generic_names:
		# Case-insensitive replacement that preserves the rest of the name
		if generic.to_lower() in result.to_lower():
			# Find the position and replace while preserving surrounding text
			var lower_result = result.to_lower()
			var pos = lower_result.find(generic.to_lower())
			if pos != -1:
				result = result.substr(0, pos) + themed_name + result.substr(pos + generic.length())
				break  # Only replace first occurrence

	return result

static func get_item_slot_from_type(item_type: String) -> String:
	"""Determine which equipment slot an item belongs to based on its type."""
	if item_type.begins_with("weapon_"):
		return "weapon"
	elif item_type.begins_with("armor_"):
		return "armor"
	elif item_type.begins_with("helm_"):
		return "helm"
	elif item_type.begins_with("shield_"):
		return "shield"
	elif item_type.begins_with("boots_"):
		return "boots"
	elif item_type.begins_with("ring_"):
		return "ring"
	elif item_type.begins_with("amulet_"):
		return "amulet"
	return ""

# Tracking / Persistence
@export var created_at: int = 0
@export var played_time_seconds: int = 0
@export var monsters_killed: int = 0

# Active combat buffs - array of {type: String, value: int, duration: int}
@export var active_buffs: Array = []

# Persistent buffs that last multiple battles - array of {type: String, value: int, battles_remaining: int}
@export var persistent_buffs: Array = []

# Quest System
# active_quests: Array of {quest_id: String, progress: int, target: int, started_at: int, origin_x: int, origin_y: int, accumulated_intensity: float, kills_in_hotzone: int}
@export var active_quests: Array = []
# completed_quests: Array of quest IDs that have been turned in
@export var completed_quests: Array = []
# daily_quest_cooldowns: {quest_id: unix_timestamp} - when daily quests can be accepted again
@export var daily_quest_cooldowns: Dictionary = {}
const MAX_ACTIVE_QUESTS = 5

# Monster Knowledge System - tracks which monsters the player has killed
# Dictionary of {monster_name: max_level_killed} - knowing a monster reveals its HP
# Killing a monster reveals HP for that type at or below the killed level (within 20 levels)
@export var known_monsters: Dictionary = {}

# Ability Loadout System - which abilities are equipped and their keybinds
# equipped_abilities: Array of ability names in slot order (max 5 slots)
@export var equipped_abilities: Array = []
# ability_keybinds: Dictionary mapping slot index to key string {0: "R", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5"}
@export var ability_keybinds: Dictionary = {0: "R", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5"}
const MAX_ABILITY_SLOTS = 6
const DEFAULT_ABILITY_KEYBINDS = {0: "R", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5"}

# Combat action bar customization - swap Attack with first ability
@export var swap_attack_with_ability: bool = false

# Cloak System - universal stealth ability
@export var cloak_active: bool = false
const CLOAK_COST_PERCENT = 8  # % of max resource per movement (must exceed regen)

# Title System - prestigious titles with special abilities
@export var title: String = ""  # Current title: "", "jarl", "high_king", "elder", "eternal"
@export var title_data: Dictionary = {}  # Title-specific data (lives for Eternal, etc.)

# Permanent Stat Bonuses - from stat tomes (persists forever)
# Format: {stat_name: bonus_value} e.g. {"strength": 5, "intelligence": 3}
@export var permanent_stat_bonuses: Dictionary = {}

# Skill Enhancements - from skill enhancer tomes (persists forever)
# Format: {ability_name: {effect: value}} e.g. {"magic_bolt": {"cost_reduction": 10, "damage_bonus": 15}}
@export var skill_enhancements: Dictionary = {}

# Trophies - rare drops from powerful monsters (prestige/collectibles)
# Format: [{id: String, obtained_at: int (unix timestamp), monster_name: String, monster_level: int}]
@export var trophies: Array = []

# Active Companion - from soul gems (only one active at a time)
# Format: {id: String, name: String, bonuses: {attack: %, hp_regen: %, flee_bonus: %}, level: int}
@export var active_companion: Dictionary = {}

# Collected Soul Gems - companions that have been obtained (can switch between them)
# Format: [{id: String, name: String, bonuses: Dictionary, obtained_at: int}]
@export var soul_gems: Array = []

func _init():
	# Constructor
	pass

func initialize(char_name: String, char_class: String, char_race: String = "Human"):
	"""Initialize a new character with starting values"""
	name = char_name
	race = char_race
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
	wits = starting_stats.wits

	# Calculate derived stats
	calculate_derived_stats()

	# Start with full resources
	current_hp = max_hp
	current_mana = max_mana
	current_stamina = max_stamina
	current_energy = max_energy

	# Starting location - Sanctuary (0, 10) like Phantasia 4
	x = 0
	y = 10
	gold = 100

	# Tracking fields
	created_at = int(Time.get_unix_time_from_system())
	played_time_seconds = 0
	monsters_killed = 0

	# Reset known monsters for new character (prevents shared dictionary bug)
	known_monsters = {}

	# Initialize default ability loadout
	initialize_default_abilities()

func get_starting_stats_for_class(char_class: String) -> Dictionary:
	"""Get starting stats based on character class"""
	var stats = {
		# Warrior Path (STR > 10 for Stamina abilities)
		"Fighter": {"strength": 14, "constitution": 13, "dexterity": 11, "intelligence": 8, "wisdom": 8, "wits": 10},
		"Barbarian": {"strength": 17, "constitution": 12, "dexterity": 10, "intelligence": 7, "wisdom": 8, "wits": 10},
		# Mage Path (INT > 10 for Mana abilities)
		"Wizard": {"strength": 8, "constitution": 10, "dexterity": 10, "intelligence": 17, "wisdom": 12, "wits": 9},
		"Sage": {"strength": 8, "constitution": 12, "dexterity": 10, "intelligence": 13, "wisdom": 15, "wits": 9},
		# Trickster Path (WITS > 10 for Energy abilities)
		"Thief": {"strength": 9, "constitution": 9, "dexterity": 14, "intelligence": 9, "wisdom": 9, "wits": 16},
		"Ranger": {"strength": 12, "constitution": 11, "dexterity": 12, "intelligence": 9, "wisdom": 9, "wits": 14},
		# Legacy classes (for existing characters)
		"Paladin": {"strength": 13, "constitution": 14, "dexterity": 10, "intelligence": 9, "wisdom": 12, "wits": 12},
		"Sorcerer": {"strength": 8, "constitution": 9, "dexterity": 10, "intelligence": 17, "wisdom": 11, "wits": 11},
		"Ninja": {"strength": 11, "constitution": 10, "dexterity": 17, "intelligence": 12, "wisdom": 11, "wits": 10}
	}

	return stats.get(char_class, stats["Fighter"])

func get_class_passive() -> Dictionary:
	"""Get the unique passive ability for this character's class"""
	match class_type:
		# Warriors
		"Fighter":
			return {
				"name": "Tactical Discipline",
				"description": "20% reduced stamina costs, +15% defense",
				"color": "#C0C0C0",
				"effects": {
					"stamina_cost_reduction": 0.20,
					"defense_bonus_percent": 0.15
				}
			}
		"Barbarian":
			return {
				"name": "Blood Rage",
				"description": "+3% damage per 10% HP missing (max +30%), abilities cost 25% more",
				"color": "#8B0000",
				"effects": {
					"damage_per_missing_hp": 0.03,  # Per 10% HP missing
					"max_rage_bonus": 0.30,
					"stamina_cost_increase": 0.25
				}
			}
		"Paladin":
			return {
				"name": "Divine Favor",
				"description": "Heal 3% max HP per round, +25% damage vs undead/demons",
				"color": "#FFD700",
				"effects": {
					"combat_regen_percent": 0.03,
					"bonus_vs_undead": 0.25
				}
			}
		# Mages
		"Wizard":
			return {
				"name": "Arcane Precision",
				"description": "+15% spell damage, +10% spell crit chance",
				"color": "#4169E1",
				"effects": {
					"spell_damage_bonus": 0.15,
					"spell_crit_bonus": 0.10
				}
			}
		"Sorcerer":
			return {
				"name": "Chaos Magic",
				"description": "25% chance for double spell damage, 5% chance to backfire",
				"color": "#9400D3",
				"effects": {
					"double_damage_chance": 0.25,
					"backfire_chance": 0.05
				}
			}
		"Sage":
			return {
				"name": "Mana Mastery",
				"description": "25% reduced mana costs, Meditate restores 50% more",
				"color": "#20B2AA",
				"effects": {
					"mana_cost_reduction": 0.25,
					"meditate_bonus": 0.50
				}
			}
		# Tricksters
		"Thief":
			return {
				"name": "Backstab",
				"description": "+50% crit damage, +15% base crit chance",
				"color": "#2F4F4F",
				"effects": {
					"crit_damage_bonus": 0.50,
					"crit_chance_bonus": 0.15
				}
			}
		"Ranger":
			return {
				"name": "Hunter's Mark",
				"description": "+25% damage vs beasts, +30% gold/XP from kills",
				"color": "#228B22",
				"effects": {
					"bonus_vs_beasts": 0.25,
					"gold_bonus": 0.30,
					"xp_bonus": 0.30
				}
			}
		"Ninja":
			return {
				"name": "Shadow Step",
				"description": "+40% flee success, take no damage when fleeing",
				"color": "#191970",
				"effects": {
					"flee_bonus": 0.40,
					"flee_no_damage": true
				}
			}
		_:
			return {
				"name": "None",
				"description": "No passive ability",
				"color": "#808080",
				"effects": {}
			}

func get_class_attack_verb() -> String:
	"""Get the attack verb/style for this character's class"""
	match class_type:
		"Fighter": return "strike"
		"Barbarian": return "smash"
		"Paladin": return "smite"
		"Wizard": return "blast"
		"Sorcerer": return "unleash chaos upon"
		"Sage": return "channel energy at"
		"Thief": return "stab"
		"Ranger": return "shoot"
		"Ninja": return "slash"
		_: return "attack"

func get_class_attack_description(damage: int, monster_name: String, is_crit: bool = false) -> String:
	"""Get a flavored attack description for this class"""
	var verb = get_class_attack_verb()
	var crit_text = ""

	match class_type:
		"Fighter":
			if is_crit:
				crit_text = "With perfect form, you "
			return "%syou %s the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		"Barbarian":
			if is_crit:
				crit_text = "In a blood-fueled frenzy, "
			return "%syou %s the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		"Paladin":
			if is_crit:
				crit_text = "Divine light guides your blade as "
			return "%syou %s the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		"Wizard":
			if is_crit:
				crit_text = "Arcane energy surges as "
			return "%syou %s the %s with magic for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		"Sorcerer":
			if is_crit:
				crit_text = "Wild magic explodes as "
			return "%syou %s the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		"Sage":
			if is_crit:
				crit_text = "Ancient wisdom empowers you as "
			return "%syou %s the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		"Thief":
			if is_crit:
				crit_text = "You find a gap in their defenses and "
			return "%syou %s the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		"Ranger":
			if is_crit:
				crit_text = "Your arrow finds its mark as "
			return "%syou %s the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		"Ninja":
			if is_crit:
				crit_text = "Moving like a shadow, "
			return "%syou %s the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, verb, monster_name, damage]
		_:
			if is_crit:
				crit_text = "[color=#FF6600]CRITICAL![/color] "
			return "%sYou attack the %s for [color=#FFFF00]%d damage[/color]!" % [crit_text, monster_name, damage]

func calculate_derived_stats():
	"""Calculate HP, mana, stamina, energy from primary stats"""
	max_hp = 50 + (constitution * 5)  # Base 50 + CON × 5
	max_mana = (intelligence * 12) + (wisdom * 6)     # Mage resource (increased for Magic Bolt)
	max_stamina = (strength * 4) + (constitution * 4)  # Warrior resource
	max_energy = (wits * 4) + (dexterity * 4)          # Trickster resource

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
		"wits", "wit":
			return wits
		_:
			return 0

func get_equipment_bonuses() -> Dictionary:
	"""Calculate total bonuses from all equipped items"""
	var bonuses = {
		"attack": 0,
		"defense": 0,
		"strength": 0,
		"constitution": 0,
		"dexterity": 0,
		"intelligence": 0,
		"wisdom": 0,
		"wits": 0,
		"max_hp": 0,
		"max_mana": 0,
		"max_stamina": 0,     # Bonus max stamina from gear
		"max_energy": 0,      # Bonus max energy from gear
		"speed": 0,
		# Class-specific bonuses
		"mana_regen": 0,      # Flat mana per combat round (Mage gear)
		"meditate_bonus": 0,  # % bonus to Meditate effectiveness (Mage gear)
		"energy_regen": 0,    # Flat energy per combat round (Trickster gear)
		"flee_bonus": 0,      # % bonus to flee chance (Trickster gear)
		"stamina_regen": 0    # Flat stamina per combat round (Warrior gear)
	}

	for slot in equipped.keys():
		var item = equipped[slot]
		if item == null or not item is Dictionary:
			continue

		var item_level = item.get("level", 1)
		var item_type = item.get("type", "")
		var rarity_mult = _get_rarity_multiplier(item.get("rarity", "common"))

		# Check for item wear/damage (0-100, 100 = fully damaged/broken)
		var wear = item.get("wear", 0)
		var wear_penalty = 1.0 - (float(wear) / 100.0)  # 0% wear = 100% effectiveness, 100% wear = 0%

		# Base bonus scales with item level, rarity, and wear
		var base_bonus = int(item_level * rarity_mult * wear_penalty)

		# STEP 1: Apply base item type bonuses (all items get these)
		# Note: Multipliers balanced to make gear valuable but not overwhelming
		if "weapon" in item_type:
			bonuses.attack += int(base_bonus * 2.5)  # Weapons give strong attack
			bonuses.strength += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
		elif "armor" in item_type:
			bonuses.defense += int(base_bonus * 1.75)  # Armor gives defense
			bonuses.constitution += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.max_hp += int(base_bonus * 2.5)
		elif "helm" in item_type:
			bonuses.defense += base_bonus
			bonuses.wisdom += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "shield" in item_type:
			bonuses.defense += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.max_hp += base_bonus * 4  # Shields give good HP
			bonuses.constitution += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		elif "ring" in item_type:
			bonuses.attack += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.dexterity += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.intelligence += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "amulet" in item_type:
			bonuses.max_mana += int(base_bonus * 1.75)
			bonuses.wisdom += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.wits += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "boots" in item_type:
			bonuses.speed += base_bonus  # Speed bonus for flee chance
			bonuses.dexterity += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.defense += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0

		# STEP 2: Apply class-specific gear bonuses (IN ADDITION to base type bonuses)
		# Use max(1, ...) for fractional multipliers to ensure even low-level items give bonuses
		if "ring_arcane" in item_type:
			# Arcane ring (Mage): extra INT + mana_regen
			bonuses.intelligence += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.mana_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "ring_shadow" in item_type:
			# Shadow ring (Trickster): extra WITS + energy_regen
			bonuses.wits += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.energy_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "amulet_mystic" in item_type:
			# Mystic amulet (Mage): extra max_mana + meditate_bonus
			bonuses.max_mana += base_bonus  # Extra mana on top of base
			bonuses.meditate_bonus += max(1, int(item_level / 2)) if item_level > 0 else 0
		elif "amulet_evasion" in item_type:
			# Evasion amulet (Trickster): extra speed + flee_bonus
			bonuses.speed += base_bonus
			bonuses.flee_bonus += max(1, int(item_level / 3)) if item_level > 0 else 0
		elif "boots_swift" in item_type:
			# Swift boots (Trickster): extra Speed + WITS + energy_regen
			bonuses.speed += int(base_bonus * 0.5)  # Extra speed on top of base
			bonuses.wits += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.energy_regen += max(1, int(base_bonus * 0.1)) if base_bonus > 0 else 0
		elif "weapon_warlord" in item_type:
			# Warlord weapon (Warrior): extra stamina_regen (base weapon stats already applied)
			bonuses.stamina_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "shield_bulwark" in item_type:
			# Bulwark shield (Warrior): extra stamina_regen (base shield stats already applied)
			bonuses.stamina_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0

		# Apply affix bonuses (from randomized item affixes) - also affected by wear
		var affixes = item.get("affixes", {})
		# HP/Resources
		if affixes.has("hp_bonus"):
			bonuses.max_hp += int(affixes.hp_bonus * wear_penalty)
		if affixes.has("mana_bonus"):
			bonuses.max_mana += int(affixes.mana_bonus * wear_penalty)
		if affixes.has("stamina_bonus"):
			bonuses.max_stamina += int(affixes.stamina_bonus * wear_penalty)
		if affixes.has("energy_bonus"):
			bonuses.max_energy += int(affixes.energy_bonus * wear_penalty)
		# Attack/Defense
		if affixes.has("attack_bonus"):
			bonuses.attack += int(affixes.attack_bonus * wear_penalty)
		if affixes.has("defense_bonus"):
			bonuses.defense += int(affixes.defense_bonus * wear_penalty)
		# Core stats
		if affixes.has("str_bonus"):
			bonuses.strength += int(affixes.str_bonus * wear_penalty)
		if affixes.has("con_bonus"):
			bonuses.constitution += int(affixes.con_bonus * wear_penalty)
		if affixes.has("dex_bonus"):
			bonuses.dexterity += int(affixes.dex_bonus * wear_penalty)
		if affixes.has("int_bonus"):
			bonuses.intelligence += int(affixes.int_bonus * wear_penalty)
		if affixes.has("wis_bonus"):
			bonuses.wisdom += int(affixes.wis_bonus * wear_penalty)
		if affixes.has("wits_bonus"):
			bonuses.wits += int(affixes.wits_bonus * wear_penalty)
		# Speed
		if affixes.has("speed_bonus"):
			bonuses.speed += int(affixes.speed_bonus * wear_penalty)

	return bonuses

func _get_rarity_multiplier(rarity: String) -> float:
	"""Get multiplier for item rarity"""
	match rarity:
		"common": return 1.0
		"uncommon": return 1.5
		"rare": return 2.0
		"epic": return 3.0
		"legendary": return 4.5
		"artifact": return 6.0
		_: return 1.0

func get_total_attack() -> int:
	"""Get total attack power including equipment"""
	var bonuses = get_equipment_bonuses()
	return strength + bonuses.strength + bonuses.attack

func get_total_defense() -> int:
	"""Get total defense including equipment"""
	var bonuses = get_equipment_bonuses()
	return (constitution / 2) + bonuses.defense

func get_equipment_defense() -> int:
	"""Get defense bonus from equipment only (used for equipment reduction calculation)"""
	var bonuses = get_equipment_bonuses()
	return bonuses.defense

func get_total_max_hp() -> int:
	"""Get total max HP including equipment bonuses.
	Formula: base max_hp + equipment HP + (equipment CON * 5)"""
	var bonuses = get_equipment_bonuses()
	# Equipment CON also contributes to HP via the CON*5 formula
	var con_hp_bonus = bonuses.constitution * 5
	return max_hp + bonuses.max_hp + con_hp_bonus

func get_total_max_mana() -> int:
	"""Get total max mana including equipment bonuses.
	Formula: base max_mana + equipment mana + (equipment INT * 12) + (equipment WIS * 6)"""
	var bonuses = get_equipment_bonuses()
	# Equipment INT/WIS also contribute to mana via the INT*12 + WIS*6 formula
	var int_mana_bonus = bonuses.intelligence * 12
	var wis_mana_bonus = bonuses.wisdom * 6
	return max_mana + bonuses.max_mana + int_mana_bonus + wis_mana_bonus

func get_total_max_stamina() -> int:
	"""Get total max stamina including equipment bonuses.
	Formula: base max_stamina + equipment stamina + (equipment STR * 4) + (equipment CON * 4)"""
	var bonuses = get_equipment_bonuses()
	# Equipment STR/CON also contribute to stamina via the (STR*4 + CON*4) formula
	var str_stamina_bonus = bonuses.strength * 4
	var con_stamina_bonus = bonuses.constitution * 4
	return max_stamina + bonuses.max_stamina + str_stamina_bonus + con_stamina_bonus

func get_total_max_energy() -> int:
	"""Get total max energy including equipment bonuses.
	Formula: base max_energy + equipment energy + (equipment WIT * 4) + (equipment DEX * 4)"""
	var bonuses = get_equipment_bonuses()
	# Equipment WIT/DEX also contribute to energy via the (WIT*4 + DEX*4) formula
	var wit_energy_bonus = bonuses.wits * 4
	var dex_energy_bonus = bonuses.dexterity * 4
	return max_energy + bonuses.max_energy + wit_energy_bonus + dex_energy_bonus

func get_equipment_procs() -> Dictionary:
	"""Get all proc effects from equipped items.
	Returns {lifesteal: %, shocking: {value, chance}, damage_reflect: %, execute: {value, chance}}"""
	var procs = {
		"lifesteal": 0,
		"shocking": {"value": 0, "chance": 0},
		"damage_reflect": 0,
		"execute": {"value": 0, "chance": 0}
	}

	for slot in equipped.keys():
		var item = equipped[slot]
		if item == null or not item is Dictionary:
			continue

		var affixes = item.get("affixes", {})
		if not affixes.has("proc_type"):
			continue

		var proc_type = affixes.get("proc_type", "")
		var proc_value = affixes.get("proc_value", 0)
		var proc_chance = affixes.get("proc_chance", 100)

		match proc_type:
			"lifesteal":
				procs.lifesteal += proc_value
			"shocking":
				# Stack damage, take highest chance
				procs.shocking.value += proc_value
				procs.shocking.chance = max(procs.shocking.chance, proc_chance)
			"damage_reflect":
				procs.damage_reflect += proc_value
			"execute":
				# Stack damage, take highest chance
				procs.execute.value += proc_value
				procs.execute.chance = max(procs.execute.chance, proc_chance)

	return procs

func get_effective_stat(stat_name: String) -> int:
	"""Get stat value including equipment bonuses and permanent bonuses from tomes"""
	var base_stat = get_stat(stat_name)
	var bonuses = get_equipment_bonuses()

	# Get permanent bonus from stat tomes
	var perm_bonus = permanent_stat_bonuses.get(stat_name.to_lower(), 0)

	match stat_name.to_lower():
		"strength", "str":
			return base_stat + bonuses.strength + perm_bonus + permanent_stat_bonuses.get("strength", 0)
		"constitution", "con":
			return base_stat + bonuses.constitution + perm_bonus + permanent_stat_bonuses.get("constitution", 0)
		"dexterity", "dex":
			return base_stat + bonuses.dexterity + perm_bonus + permanent_stat_bonuses.get("dexterity", 0)
		"intelligence", "int":
			return base_stat + bonuses.intelligence + perm_bonus + permanent_stat_bonuses.get("intelligence", 0)
		"wisdom", "wis":
			return base_stat + bonuses.wisdom + perm_bonus + permanent_stat_bonuses.get("wisdom", 0)
		"wits", "wit":
			return base_stat + bonuses.wits + perm_bonus + permanent_stat_bonuses.get("wits", 0)
		_:
			return base_stat + perm_bonus

func get_attack_damage() -> Dictionary:
	"""Calculate attack damage range including equipment"""
	var bonuses = get_equipment_bonuses()
	var total_str = strength + bonuses.strength
	var base_damage = total_str + bonuses.attack
	var min_damage = int(base_damage * 0.8)
	var max_damage = int(base_damage * 1.2)

	return {
		"min": min_damage,
		"max": max_damage,
		"base": base_damage,
		"from_equipment": bonuses.attack
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
	"""Heal the character, return actual amount healed. Ogre racial applies 2x healing."""
	var old_hp = current_hp
	var heal_amount = int(amount * get_heal_multiplier())
	current_hp = min(current_hp + heal_amount, get_total_max_hp())
	return current_hp - old_hp

func damage_equipment(slot: String, wear_amount: int) -> Dictionary:
	"""Damage equipment in a specific slot. Returns info about the damage."""
	if not equipped.has(slot) or equipped[slot] == null:
		return {"success": false, "message": "No item in slot"}

	var item = equipped[slot]
	var old_wear = item.get("wear", 0)
	var new_wear = min(100, old_wear + wear_amount)
	item["wear"] = new_wear

	var result = {
		"success": true,
		"item_name": item.get("name", "Unknown"),
		"slot": slot,
		"old_wear": old_wear,
		"new_wear": new_wear,
		"wear_added": new_wear - old_wear,
		"is_broken": new_wear >= 100
	}

	return result

func damage_weapon(wear_amount: int) -> Dictionary:
	"""Damage the equipped weapon. Returns info about the damage."""
	return damage_equipment("weapon", wear_amount)

func damage_shield(wear_amount: int) -> Dictionary:
	"""Damage the equipped shield. Returns info about the damage."""
	return damage_equipment("shield", wear_amount)

func get_equipment_wear_status() -> Dictionary:
	"""Get wear status for all equipped items"""
	var status = {}
	for slot in equipped.keys():
		var item = equipped[slot]
		if item != null and item is Dictionary:
			var wear = item.get("wear", 0)
			status[slot] = {
				"name": item.get("name", "Unknown"),
				"wear": wear,
				"condition": _get_condition_string(wear),
				"effectiveness": 100 - wear
			}
	return status

func _get_condition_string(wear: int) -> String:
	"""Get a human-readable condition string from wear percentage"""
	if wear == 0:
		return "Pristine"
	elif wear <= 10:
		return "Excellent"
	elif wear <= 25:
		return "Good"
	elif wear <= 50:
		return "Worn"
	elif wear <= 75:
		return "Damaged"
	elif wear < 100:
		return "Nearly Broken"
	else:
		return "BROKEN"

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
	wits += gains.wits
	
	# Recalculate derived stats
	calculate_derived_stats()

	# Full heal on level up (including equipment bonuses)
	current_hp = get_total_max_hp()
	current_mana = get_total_max_mana()
	current_stamina = max_stamina
	current_energy = max_energy

func get_stat_gains_for_class() -> Dictionary:
	"""Get stat increases per level based on class"""
	var gains = {
		# Warrior Path (primary: STR, secondary: CON)
		"Fighter": {"strength": 3, "constitution": 2, "dexterity": 1, "intelligence": 0, "wisdom": 0, "wits": 1},
		"Barbarian": {"strength": 4, "constitution": 2, "dexterity": 1, "intelligence": 0, "wisdom": 0, "wits": 0},
		# Mage Path (primary: INT, secondary: WIS)
		"Wizard": {"strength": 0, "constitution": 1, "dexterity": 1, "intelligence": 4, "wisdom": 2, "wits": 0},
		"Sage": {"strength": 0, "constitution": 2, "dexterity": 1, "intelligence": 2, "wisdom": 3, "wits": 0},
		# Trickster Path (primary: WITS, secondary: DEX)
		"Thief": {"strength": 1, "constitution": 1, "dexterity": 2, "intelligence": 0, "wisdom": 0, "wits": 4},
		"Ranger": {"strength": 2, "constitution": 2, "dexterity": 2, "intelligence": 0, "wisdom": 0, "wits": 2},
		# Legacy classes (for existing characters)
		"Paladin": {"strength": 2, "constitution": 3, "dexterity": 1, "intelligence": 1, "wisdom": 2, "wits": 2},
		"Sorcerer": {"strength": 0, "constitution": 1, "dexterity": 1, "intelligence": 5, "wisdom": 1, "wits": 1},
		"Ninja": {"strength": 2, "constitution": 1, "dexterity": 5, "intelligence": 2, "wisdom": 1, "wits": 1}
	}

	return gains.get(class_type, gains["Fighter"])

func to_dict() -> Dictionary:
	"""Convert character to dictionary for network transmission"""
	return {
		"id": character_id,
		"name": name,
		"race": race,
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
			"wits": wits
		},
		"current_hp": current_hp,
		"max_hp": max_hp,
		"total_max_hp": get_total_max_hp(),  # Equipment-boosted max HP for display
		"current_mana": current_mana,
		"max_mana": max_mana,
		"total_max_mana": get_total_max_mana(),  # Equipment-boosted max mana for display
		"current_stamina": current_stamina,
		"max_stamina": max_stamina,
		"total_max_stamina": get_total_max_stamina(),  # Equipment-boosted max stamina for display
		"current_energy": current_energy,
		"max_energy": max_energy,
		"total_max_energy": get_total_max_energy(),  # Equipment-boosted max energy for display
		"x": x,
		"y": y,
		"health_state": get_health_state(),
		"gold": gold,
		"gems": gems,
		"in_combat": in_combat,
		"poison_active": poison_active,
		"poison_damage": poison_damage,
		"poison_turns_remaining": poison_turns_remaining,
		"blind_active": blind_active,
		"blind_turns_remaining": blind_turns_remaining,
		"all_or_nothing_uses": all_or_nothing_uses,
		"forced_next_monster": forced_next_monster,
		"target_farm_ability": target_farm_ability,
		"target_farm_remaining": target_farm_remaining,
		"pending_monster_debuffs": pending_monster_debuffs,
		"inventory": inventory,
		"equipped": equipped,
		"created_at": created_at,
		"played_time_seconds": played_time_seconds,
		"monsters_killed": monsters_killed,
		"active_buffs": active_buffs,
		"persistent_buffs": persistent_buffs,
		"active_quests": active_quests,
		"completed_quests": completed_quests,
		"daily_quest_cooldowns": daily_quest_cooldowns,
		"known_monsters": known_monsters,
		"equipped_abilities": equipped_abilities,
		"ability_keybinds": ability_keybinds,
		"swap_attack_with_ability": swap_attack_with_ability,
		"cloak_active": cloak_active,
		"title": title,
		"title_data": title_data,
		"permanent_stat_bonuses": permanent_stat_bonuses,
		"skill_enhancements": skill_enhancements,
		"trophies": trophies,
		"active_companion": active_companion,
		"soul_gems": soul_gems
	}

func from_dict(data: Dictionary):
	"""Load character from dictionary"""
	character_id = data.get("id", 0)
	name = data.get("name", "")
	race = data.get("race", "Human")  # Default to Human for legacy characters
	class_type = data.get("class", "Fighter")
	level = data.get("level", 1)
	experience = data.get("experience", 0)

	var stats = data.get("stats", {})
	strength = stats.get("strength", 10)
	constitution = stats.get("constitution", 10)
	dexterity = stats.get("dexterity", 10)
	intelligence = stats.get("intelligence", 10)
	wisdom = stats.get("wisdom", 10)
	wits = stats.get("wits", stats.get("charisma", 10))  # Support legacy save files with charisma

	current_hp = data.get("current_hp", 100)
	max_hp = data.get("max_hp", 100)
	current_mana = data.get("current_mana", 50)
	max_mana = data.get("max_mana", 50)

	# Calculate max stamina/energy from stats for legacy characters, then load current values
	var calc_max_stamina = (strength * 4) + (constitution * 4)
	var calc_max_energy = (wits * 4) + (dexterity * 4)
	max_stamina = data.get("max_stamina", calc_max_stamina)
	max_energy = data.get("max_energy", calc_max_energy)
	current_stamina = data.get("current_stamina", max_stamina)
	current_energy = data.get("current_energy", max_energy)

	x = data.get("x", 0)
	y = data.get("y", 10)
	gold = data.get("gold", 100)
	gems = data.get("gems", 0)
	in_combat = data.get("in_combat", false)
	experience_to_next_level = data.get("experience_to_next_level", 100)

	# Poison status
	poison_active = data.get("poison_active", false)
	poison_damage = data.get("poison_damage", 0)
	poison_turns_remaining = data.get("poison_turns_remaining", 0)

	# Blind status
	blind_active = data.get("blind_active", false)
	blind_turns_remaining = data.get("blind_turns_remaining", 0)

	# All or Nothing usage tracking
	all_or_nothing_uses = data.get("all_or_nothing_uses", 0)

	# Forced next monster (from Monster Selection Scroll)
	forced_next_monster = data.get("forced_next_monster", "")

	# Target farming (from Target Farming Scroll)
	target_farm_ability = data.get("target_farm_ability", "")
	target_farm_remaining = data.get("target_farm_remaining", 0)

	# Pending monster debuffs (from debuff scrolls)
	pending_monster_debuffs = data.get("pending_monster_debuffs", [])

	# Inventory system
	inventory = data.get("inventory", [])
	var loaded_equipped = data.get("equipped", {})
	for slot in equipped.keys():
		equipped[slot] = loaded_equipped.get(slot, null)

	# Tracking fields
	created_at = data.get("created_at", 0)
	played_time_seconds = data.get("played_time_seconds", 0)
	monsters_killed = data.get("monsters_killed", 0)

	# Active buffs (clear on load - combat buffs don't persist between sessions)
	active_buffs = []

	# Persistent buffs DO persist between sessions (battle-based potions)
	persistent_buffs = data.get("persistent_buffs", [])

	# Quest system
	active_quests = data.get("active_quests", [])
	completed_quests = data.get("completed_quests", [])
	daily_quest_cooldowns = data.get("daily_quest_cooldowns", {})

	# Monster knowledge system
	known_monsters = data.get("known_monsters", {})

	# Ability loadout system
	equipped_abilities = data.get("equipped_abilities", [])
	ability_keybinds = data.get("ability_keybinds", DEFAULT_ABILITY_KEYBINDS.duplicate())
	# Ensure keybinds has all slots (in case of legacy data)
	for slot in DEFAULT_ABILITY_KEYBINDS.keys():
		if not ability_keybinds.has(slot):
			ability_keybinds[slot] = DEFAULT_ABILITY_KEYBINDS[slot]
	swap_attack_with_ability = data.get("swap_attack_with_ability", false)

	# Cloak system - always starts off when loading (no free permanent cloak)
	cloak_active = false

	# Title system
	title = data.get("title", "")
	title_data = data.get("title_data", {})

	# Permanent stat bonuses from tomes
	permanent_stat_bonuses = data.get("permanent_stat_bonuses", {})

	# Skill enhancements from skill tomes
	skill_enhancements = data.get("skill_enhancements", {})

	# Trophies
	trophies = data.get("trophies", [])

	# Companions
	active_companion = data.get("active_companion", {})
	soul_gems = data.get("soul_gems", [])

	# Clamp resources to max in case saved data has resources over max
	_clamp_resources_to_max()

func knows_monster(monster_name: String, monster_level: int = 0) -> bool:
	"""Check if the player knows this monster's HP based on previous kills.
	Player knows HP if they've killed this monster type at or above this level,
	or within 20 levels below their highest kill."""
	if not known_monsters.has(monster_name):
		return false
	var max_level_killed = known_monsters[monster_name]
	# Know monsters at or below the level you've killed
	# Also know monsters up to 20 levels below your highest kill
	return monster_level <= max_level_killed

func record_monster_kill(monster_name: String, monster_level: int = 1):
	"""Record that the player has killed this monster type at this level.
	Updates to track the highest level killed."""
	if not known_monsters.has(monster_name):
		known_monsters[monster_name] = monster_level
	else:
		# Only update if this is a higher level than previously killed
		known_monsters[monster_name] = max(known_monsters[monster_name], monster_level)

func add_experience(amount: int) -> Dictionary:
	"""Add experience and check for level up. Applies Human racial XP bonus."""
	# Apply Human racial XP bonus (+10%)
	var final_amount = int(amount * get_xp_multiplier())
	experience += final_amount
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
		wits += 1
		
		# Increase HP, Mana, Stamina, Energy
		max_hp += 10 + (constitution / 2)
		max_mana += 10 + intelligence  # Increased mana growth for mages
		max_stamina = (strength * 4) + (constitution * 4)  # Recalculate from new stats
		max_energy = (wits * 4) + (dexterity * 4)         # Recalculate from new stats

		# Fully restore resources on level up (including equipment bonuses)
		current_hp = get_total_max_hp()
		current_mana = get_total_max_mana()
		current_stamina = max_stamina
		current_energy = max_energy

		# Calculate next level requirement using polynomial scaling
		# Formula: (level+1)^2.2 * 50 - scales reasonably up to level 10000
		experience_to_next_level = int(pow(level + 1, 2.2) * 50)
	
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

# Inventory System Stubs

func can_add_item() -> bool:
	"""Check if inventory has space for another item"""
	return inventory.size() < MAX_INVENTORY_SIZE

func add_item(item: Dictionary) -> bool:
	"""Add an item to inventory. Consumables stack automatically. Returns true if successful."""
	# Check if it's a stackable consumable
	if item.get("is_consumable", false):
		return _add_stackable_consumable(item)
	# Non-consumable - add as separate item
	if not can_add_item():
		return false
	inventory.append(item)
	return true

func _add_stackable_consumable(item: Dictionary) -> bool:
	"""Add a consumable item, stacking with existing items of same type+tier"""
	var item_type = item.get("type", "")
	var item_tier = item.get("tier", 1)
	var add_quantity = item.get("quantity", 1)

	# Find existing stack of same type+tier
	for inv_item in inventory:
		if inv_item.get("is_consumable", false) and inv_item.get("type", "") == item_type and inv_item.get("tier", 1) == item_tier:
			# Found matching stack - add to it
			var current_qty = inv_item.get("quantity", 1)
			var new_qty = mini(MAX_STACK_SIZE, current_qty + add_quantity)
			inv_item["quantity"] = new_qty
			return true

	# No existing stack - create new if space available
	if not can_add_item():
		return false
	item["quantity"] = mini(MAX_STACK_SIZE, add_quantity)
	inventory.append(item)
	return true

func use_consumable_stack(index: int) -> Dictionary:
	"""Use one consumable from a stack. Returns the item data or empty if invalid/empty."""
	if index < 0 or index >= inventory.size():
		return {}

	var item = inventory[index]
	if not item.get("is_consumable", false):
		return {}

	var quantity = item.get("quantity", 1)
	if quantity <= 0:
		return {}

	# Decrease quantity
	item["quantity"] = quantity - 1

	# Remove from inventory if depleted
	if item["quantity"] <= 0:
		inventory.remove_at(index)

	return item

func remove_item(index: int) -> Dictionary:
	"""Remove and return item at index. Returns empty dict if invalid."""
	if index < 0 or index >= inventory.size():
		return {}
	return inventory.pop_at(index)

func get_inventory_count() -> int:
	"""Get current number of items in inventory"""
	return inventory.size()

func equip_item(item: Dictionary, slot: String) -> Dictionary:
	"""Equip an item to a slot. Returns previously equipped item or empty dict."""
	if not equipped.has(slot):
		return {}
	var old_item = equipped[slot]
	equipped[slot] = item
	if old_item != null:
		return old_item
	return {}

func unequip_slot(slot: String) -> Dictionary:
	"""Unequip item from slot. Returns the item or empty dict."""
	if not equipped.has(slot) or equipped[slot] == null:
		return {}
	var item = equipped[slot]
	equipped[slot] = null
	# Clamp resources to new max after unequipping (in case gear boosted max)
	_clamp_resources_to_max()
	return item

func _clamp_resources_to_max():
	"""Clamp all resources to their current maximum values."""
	current_hp = min(current_hp, get_total_max_hp())
	current_mana = min(current_mana, get_total_max_mana())
	current_stamina = min(current_stamina, max_stamina)
	current_energy = min(current_energy, max_energy)

# ===== BUFF SYSTEM =====

func add_buff(buff_type: String, value: int, duration: int):
	"""Add or refresh a combat buff (lasts rounds). If buff already exists, refreshes duration and uses higher value."""
	for buff in active_buffs:
		if buff.type == buff_type:
			buff.value = max(buff.value, value)
			buff.duration = max(buff.duration, duration)
			return
	active_buffs.append({"type": buff_type, "value": value, "duration": duration})

func add_persistent_buff(buff_type: String, value: int, battles: int):
	"""Add or refresh a persistent buff (lasts multiple battles). If buff already exists, refreshes battles and uses higher value."""
	for buff in persistent_buffs:
		if buff.type == buff_type:
			buff.value = max(buff.value, value)
			buff.battles_remaining = max(buff.battles_remaining, battles)
			return
	persistent_buffs.append({"type": buff_type, "value": value, "battles_remaining": battles})

func get_buff_value(buff_type: String) -> int:
	"""Get the current value of a buff type (combines combat and persistent buffs). Returns 0 if not active."""
	var total = 0
	for buff in active_buffs:
		if buff.type == buff_type:
			total += buff.value
	for buff in persistent_buffs:
		if buff.type == buff_type:
			total += buff.value
	return total

func tick_buffs() -> Array:
	"""Decrement buff durations by 1. Call at end of each combat round. Returns expired buff info."""
	var expired_indices = []
	var expired_buffs = []
	for i in range(active_buffs.size()):
		active_buffs[i].duration -= 1
		if active_buffs[i].duration <= 0:
			expired_indices.append(i)
			expired_buffs.append({"type": active_buffs[i].type, "value": active_buffs[i].value})
	# Remove expired buffs (reverse order to preserve indices)
	for i in range(expired_indices.size() - 1, -1, -1):
		active_buffs.remove_at(expired_indices[i])
	return expired_buffs

func tick_persistent_buffs() -> Array:
	"""Decrement persistent buff battles by 1. Call when combat ends. Returns expired buff info.
	Buffs with battles_remaining = -1 are permanent (until triggered) and don't expire."""
	var expired_indices = []
	var expired_buffs = []
	for i in range(persistent_buffs.size()):
		# Skip permanent buffs (-1 = until triggered, like Greater Resurrect)
		if persistent_buffs[i].battles_remaining == -1:
			continue
		persistent_buffs[i].battles_remaining -= 1
		if persistent_buffs[i].battles_remaining <= 0:
			expired_indices.append(i)
			expired_buffs.append({"type": persistent_buffs[i].type, "value": persistent_buffs[i].value})
	# Remove expired buffs (reverse order to preserve indices)
	for i in range(expired_indices.size() - 1, -1, -1):
		persistent_buffs.remove_at(expired_indices[i])
	return expired_buffs

func clear_buffs():
	"""Clear all active combat buffs. Call when combat ends. Does NOT clear persistent buffs."""
	active_buffs.clear()

func get_active_buff_names() -> Array:
	"""Get list of active buff type names for display (combines combat and persistent)."""
	var names = []
	for buff in active_buffs:
		names.append(buff.type)
	for buff in persistent_buffs:
		if buff.type not in names:
			names.append(buff.type)
	return names

func has_buff(buff_type: String) -> bool:
	"""Check if character has a specific buff type active."""
	for buff in active_buffs:
		if buff.type == buff_type:
			return true
	for buff in persistent_buffs:
		if buff.type == buff_type:
			return true
	return false

func remove_buff(buff_type: String) -> bool:
	"""Remove a specific buff by type. Returns true if buff was found and removed."""
	# Check combat buffs first
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i].type == buff_type:
			active_buffs.remove_at(i)
			return true
	# Check persistent buffs
	for i in range(persistent_buffs.size() - 1, -1, -1):
		if persistent_buffs[i].type == buff_type:
			persistent_buffs.remove_at(i)
			return true
	return false

func get_persistent_buff_display() -> String:
	"""Get display string for persistent buffs."""
	if persistent_buffs.is_empty():
		return ""
	var parts = []
	for buff in persistent_buffs:
		if buff.battles_remaining == -1:
			# Permanent buff (until triggered, like Greater Resurrect)
			parts.append("+%d%% %s (Until death)" % [buff.value, buff.type])
		elif buff.battles_remaining == 1:
			parts.append("+%d%% %s (1 battle)" % [buff.value, buff.type])
		else:
			parts.append("+%d%% %s (%d battles)" % [buff.value, buff.type, buff.battles_remaining])
	return "[color=#00FFFF]Buffs: %s[/color]" % ", ".join(parts)

# ===== RACIAL PASSIVE ABILITIES =====

func get_xp_multiplier() -> float:
	"""Get XP multiplier from racial passive. Human gets +10%."""
	if race == "Human":
		return 1.10
	return 1.0

func has_poison_resistance() -> bool:
	"""Check if character is resistant to poison (Elf racial)."""
	return race == "Elf"

func get_poison_damage_multiplier() -> float:
	"""Get poison damage multiplier. Elf takes 50% poison damage."""
	if race == "Elf":
		return 0.5
	return 1.0

func cure_poison():
	"""Cure poison status effect."""
	poison_active = false
	poison_damage = 0
	poison_turns_remaining = 0

func apply_poison(damage: int, duration: int = 20):
	"""Apply poison to the character. Duration is in combat turns."""
	poison_active = true
	poison_damage = damage
	poison_turns_remaining = duration

func tick_poison() -> int:
	"""Process one turn of poison. Returns damage dealt. Called each combat turn."""
	if not poison_active or poison_turns_remaining <= 0:
		return 0

	poison_turns_remaining -= 1
	if poison_turns_remaining <= 0:
		cure_poison()
		return 0

	# Apply racial resistance
	var final_damage = int(poison_damage * get_poison_damage_multiplier())
	return max(1, final_damage)

func cure_blind():
	"""Cure blind status effect."""
	blind_active = false
	blind_turns_remaining = 0

func apply_blind(duration: int = 15):
	"""Apply blindness to the character. Duration is in combat turns.
	Blindness reduces map vision and hides monster HP."""
	blind_active = true
	blind_turns_remaining = duration

func tick_blind() -> bool:
	"""Process one turn of blindness. Returns true if still blind.
	Called each combat turn."""
	if not blind_active or blind_turns_remaining <= 0:
		return false

	blind_turns_remaining -= 1
	if blind_turns_remaining <= 0:
		cure_blind()
		return false

	return true

func try_last_stand() -> bool:
	"""Dwarf racial: 25% chance to survive lethal damage with 1 HP.
	Returns true if Last Stand triggered, false otherwise.
	Can only trigger once per combat."""
	if race != "Dwarf":
		return false
	if last_stand_used:
		return false

	# 25% chance to trigger
	var roll = randi() % 100
	if roll < 25:
		last_stand_used = true
		current_hp = 1
		return true
	return false

func reset_combat_flags():
	"""Reset per-combat flags. Call at start of each combat."""
	last_stand_used = false

func get_heal_multiplier() -> float:
	"""Get healing multiplier from racial passive. Ogre gets 2x healing."""
	if race == "Ogre":
		return 2.0
	return 1.0

# ===== RESOURCE MANAGEMENT =====

func use_stamina(amount: int) -> bool:
	"""Attempt to use stamina. Returns true if successful, false if insufficient."""
	if current_stamina < amount:
		return false
	current_stamina -= amount
	return true

func use_energy(amount: int) -> bool:
	"""Attempt to use energy. Returns true if successful, false if insufficient."""
	if current_energy < amount:
		return false
	current_energy -= amount
	return true

func use_mana(amount: int) -> bool:
	"""Attempt to use mana. Returns true if successful, false if insufficient."""
	if current_mana < amount:
		return false
	current_mana -= amount
	return true

func regenerate_stamina_defending() -> int:
	"""Regenerate 10% stamina while defending. Returns amount regenerated."""
	var regen = int(max_stamina * 0.10)
	regen = max(1, regen)  # At least 1
	current_stamina = min(max_stamina, current_stamina + regen)
	return regen

func regenerate_energy() -> int:
	"""Regenerate 15% energy each combat round automatically. Returns amount regenerated."""
	var regen = int(max_energy * 0.15)
	regen = max(1, regen)  # At least 1
	current_energy = min(max_energy, current_energy + regen)
	return regen

func restore_all_resources():
	"""Restore all resources to full (for resting or sanctuaries)."""
	current_hp = get_total_max_hp()
	current_mana = get_total_max_mana()
	current_stamina = max_stamina
	current_energy = max_energy

# ===== QUEST SYSTEM =====

func can_accept_quest() -> bool:
	"""Check if player can accept another quest"""
	return active_quests.size() < MAX_ACTIVE_QUESTS

func has_quest(quest_id: String) -> bool:
	"""Check if player has an active quest with this ID"""
	for quest in active_quests:
		if quest.quest_id == quest_id:
			return true
	return false

func has_completed_quest(quest_id: String) -> bool:
	"""Check if player has completed this quest"""
	return quest_id in completed_quests

func can_accept_daily_quest(quest_id: String) -> bool:
	"""Check if daily quest cooldown has expired"""
	if not daily_quest_cooldowns.has(quest_id):
		return true
	var cooldown_end = daily_quest_cooldowns[quest_id]
	return Time.get_unix_time_from_system() >= cooldown_end

func get_quest_progress(quest_id: String) -> Dictionary:
	"""Get progress for an active quest. Returns empty dict if not found."""
	for quest in active_quests:
		if quest.quest_id == quest_id:
			return quest
	return {}

func add_quest(quest_id: String, target: int, origin_x: int = 0, origin_y: int = 0, description: String = "", player_level_at_accept: int = 1, completed_at_post: int = 0) -> bool:
	"""Add a new quest to active quests. Returns false if at max or already has quest."""
	if not can_accept_quest() or has_quest(quest_id):
		return false

	active_quests.append({
		"quest_id": quest_id,
		"progress": 0,
		"target": target,
		"started_at": int(Time.get_unix_time_from_system()),
		"origin_x": origin_x,
		"origin_y": origin_y,
		"accumulated_intensity": 0.0,  # For hotzone quests
		"kills_in_hotzone": 0,  # Track kills specifically in hotzones
		"description": description,  # Store scaled description for display
		"player_level_at_accept": player_level_at_accept,  # For regenerating dynamic quests
		"completed_at_post": completed_at_post  # For regenerating dynamic quests
	})
	return true

func update_quest_progress(quest_id: String, amount: int = 1, hotzone_intensity: float = 0.0) -> Dictionary:
	"""Increment quest progress. Returns {updated: bool, completed: bool, progress: int, target: int}"""
	for quest in active_quests:
		if quest.quest_id == quest_id:
			quest.progress += amount
			if hotzone_intensity > 0:
				quest.kills_in_hotzone += amount
				quest.accumulated_intensity += hotzone_intensity * amount
			return {
				"updated": true,
				"completed": quest.progress >= quest.target,
				"progress": quest.progress,
				"target": quest.target
			}
	return {"updated": false, "completed": false, "progress": 0, "target": 0}

func complete_quest(quest_id: String, is_daily: bool = false) -> bool:
	"""Mark quest as completed and remove from active. Returns false if quest not found."""
	for i in range(active_quests.size()):
		if active_quests[i].quest_id == quest_id:
			var quest = active_quests[i]
			active_quests.remove_at(i)
			if not is_daily:
				completed_quests.append(quest_id)
			else:
				# Daily quests have 24 hour cooldown
				daily_quest_cooldowns[quest_id] = int(Time.get_unix_time_from_system()) + 86400
			return true
	return false

func abandon_quest(quest_id: String) -> bool:
	"""Remove quest from active without completing. Returns false if quest not found."""
	for i in range(active_quests.size()):
		if active_quests[i].quest_id == quest_id:
			active_quests.remove_at(i)
			return true
	return false

func get_active_quest_count() -> int:
	"""Get number of active quests"""
	return active_quests.size()

func get_average_hotzone_intensity(quest_id: String) -> float:
	"""Get average hotzone intensity for a quest (for reward multiplier)"""
	for quest in active_quests:
		if quest.quest_id == quest_id:
			if quest.kills_in_hotzone > 0:
				return quest.accumulated_intensity / quest.kills_in_hotzone
			return 0.0
	return 0.0

# ===== ABILITY LOADOUT SYSTEM =====

func get_class_path() -> String:
	"""Get the class path (warrior/mage/trickster) for this character"""
	match class_type:
		"Fighter", "Barbarian", "Paladin":
			return "warrior"
		"Wizard", "Sorcerer", "Sage":
			return "mage"
		"Thief", "Ranger", "Ninja":
			return "trickster"
		_:
			return "warrior"

func get_all_available_abilities() -> Array:
	"""Get list of all abilities this character can learn (based on class path)"""
	var path = get_class_path()
	var abilities = []

	# Universal abilities available to all classes
	abilities.append({"name": "cloak", "level": 20, "display": "Cloak", "universal": true})
	abilities.append({"name": "all_or_nothing", "level": 1, "display": "All or Nothing", "universal": true})

	# Teleport unlocks at different levels per class path
	var teleport_level = 60  # Default (warrior)
	match path:
		"mage":
			teleport_level = 30
		"trickster":
			teleport_level = 45
		"warrior":
			teleport_level = 60
	abilities.append({"name": "teleport", "level": teleport_level, "display": "Teleport", "universal": true, "non_combat": true})

	match path:
		"mage":
			abilities.append({"name": "magic_bolt", "level": 1, "display": "Magic Bolt"})
			abilities.append({"name": "shield", "level": 10, "display": "Shield"})
			abilities.append({"name": "blast", "level": 40, "display": "Blast"})
			abilities.append({"name": "forcefield", "level": 60, "display": "Forcefield"})
			abilities.append({"name": "meteor", "level": 100, "display": "Meteor"})
			abilities.append({"name": "haste", "level": 30, "display": "Haste"})
			abilities.append({"name": "paralyze", "level": 50, "display": "Paralyze"})
			abilities.append({"name": "banish", "level": 70, "display": "Banish"})
		"warrior":
			abilities.append({"name": "power_strike", "level": 1, "display": "Power Strike"})
			abilities.append({"name": "war_cry", "level": 10, "display": "War Cry"})
			abilities.append({"name": "shield_bash", "level": 25, "display": "Shield Bash"})
			abilities.append({"name": "cleave", "level": 40, "display": "Cleave"})
			abilities.append({"name": "berserk", "level": 60, "display": "Berserk"})
			abilities.append({"name": "iron_skin", "level": 80, "display": "Iron Skin"})
			abilities.append({"name": "devastate", "level": 100, "display": "Devastate"})
			abilities.append({"name": "fortify", "level": 35, "display": "Fortify"})
			abilities.append({"name": "rally", "level": 55, "display": "Rally"})
		"trickster":
			abilities.append({"name": "analyze", "level": 1, "display": "Analyze"})
			abilities.append({"name": "distract", "level": 10, "display": "Distract"})
			abilities.append({"name": "pickpocket", "level": 25, "display": "Pickpocket"})
			abilities.append({"name": "ambush", "level": 40, "display": "Ambush"})
			abilities.append({"name": "vanish", "level": 60, "display": "Vanish"})
			abilities.append({"name": "exploit", "level": 80, "display": "Exploit"})
			abilities.append({"name": "perfect_heist", "level": 100, "display": "Perfect Heist"})
			abilities.append({"name": "sabotage", "level": 30, "display": "Sabotage"})
			abilities.append({"name": "gambit", "level": 50, "display": "Gambit"})

	return abilities

func get_unlocked_abilities() -> Array:
	"""Get list of abilities this character has unlocked (based on level)"""
	var all_abilities = get_all_available_abilities()
	var unlocked = []
	for ability in all_abilities:
		if level >= ability.level:
			unlocked.append(ability)
	return unlocked

func get_abilities_unlocked_at_level(check_level: int) -> Array:
	"""Get list of abilities that unlock exactly at the specified level"""
	var all_abilities = get_all_available_abilities()
	var newly_unlocked = []
	for ability in all_abilities:
		if ability.level == check_level:
			newly_unlocked.append(ability)
	return newly_unlocked

func get_newly_unlocked_abilities(old_level: int, new_level: int) -> Array:
	"""Get list of abilities unlocked between old_level and new_level (exclusive/inclusive)"""
	var all_abilities = get_all_available_abilities()
	var newly_unlocked = []
	for ability in all_abilities:
		# Ability unlocks if: old_level < ability.level <= new_level
		if ability.level > old_level and ability.level <= new_level:
			newly_unlocked.append(ability)
	return newly_unlocked

func initialize_default_abilities():
	"""Initialize default equipped abilities for a new character"""
	var unlocked = get_unlocked_abilities()
	equipped_abilities.clear()
	# Equip first 4 unlocked abilities by default
	for i in range(min(MAX_ABILITY_SLOTS, unlocked.size())):
		equipped_abilities.append(unlocked[i].name)
	# Reset keybinds to default
	ability_keybinds = DEFAULT_ABILITY_KEYBINDS.duplicate()

func equip_ability(slot: int, ability_name: String) -> bool:
	"""Equip an ability to a slot. Returns false if ability not unlocked or slot invalid."""
	if slot < 0 or slot >= MAX_ABILITY_SLOTS:
		return false

	# Check if ability is unlocked
	var unlocked = get_unlocked_abilities()
	var found = false
	for ability in unlocked:
		if ability.name == ability_name:
			found = true
			break
	if not found:
		return false

	# Expand equipped array if needed
	while equipped_abilities.size() <= slot:
		equipped_abilities.append("")

	equipped_abilities[slot] = ability_name
	return true

func unequip_ability(slot: int) -> bool:
	"""Remove ability from a slot"""
	if slot < 0 or slot >= equipped_abilities.size():
		return false
	equipped_abilities[slot] = ""
	return true

func set_ability_keybind(slot: int, key: String) -> bool:
	"""Set the keybind for an ability slot"""
	if slot < 0 or slot >= MAX_ABILITY_SLOTS:
		return false
	if key.length() == 0:
		return false
	ability_keybinds[slot] = key.to_upper()
	return true

func get_ability_in_slot(slot: int) -> String:
	"""Get the ability name in a slot, or empty string if none"""
	if slot < 0 or slot >= equipped_abilities.size():
		return ""
	return equipped_abilities[slot]

func get_keybind_for_slot(slot: int) -> String:
	"""Get the keybind for a slot"""
	if ability_keybinds.has(slot):
		return ability_keybinds[slot]
	return DEFAULT_ABILITY_KEYBINDS.get(slot, "")

func get_slot_for_keybind(key: String) -> int:
	"""Get the slot index for a keybind, or -1 if not found"""
	var upper_key = key.to_upper()
	for slot in ability_keybinds.keys():
		if ability_keybinds[slot] == upper_key:
			return slot
	return -1

# ===== PERMANENT STAT BONUSES =====

func apply_permanent_stat_bonus(stat_name: String, amount: int) -> int:
	"""Apply a permanent stat bonus from a tome. Returns new total bonus for that stat."""
	var lower_stat = stat_name.to_lower()
	if not permanent_stat_bonuses.has(lower_stat):
		permanent_stat_bonuses[lower_stat] = 0
	permanent_stat_bonuses[lower_stat] += amount
	return permanent_stat_bonuses[lower_stat]

func get_permanent_stat_bonus(stat_name: String) -> int:
	"""Get the permanent stat bonus for a specific stat."""
	return permanent_stat_bonuses.get(stat_name.to_lower(), 0)

func get_all_permanent_stat_bonuses() -> Dictionary:
	"""Get all permanent stat bonuses."""
	return permanent_stat_bonuses.duplicate()

# ===== SKILL ENHANCEMENTS =====

func enhance_skill(ability_name: String, effect: String, value: float) -> float:
	"""Add a skill enhancement. Effects stack additively. Returns new total value."""
	var lower_ability = ability_name.to_lower()
	if not skill_enhancements.has(lower_ability):
		skill_enhancements[lower_ability] = {}
	if not skill_enhancements[lower_ability].has(effect):
		skill_enhancements[lower_ability][effect] = 0.0
	skill_enhancements[lower_ability][effect] += value
	return skill_enhancements[lower_ability][effect]

func get_skill_enhancement(ability_name: String, effect: String) -> float:
	"""Get the enhancement value for an ability's effect. Returns 0 if not enhanced."""
	var lower_ability = ability_name.to_lower()
	if not skill_enhancements.has(lower_ability):
		return 0.0
	return skill_enhancements[lower_ability].get(effect, 0.0)

func get_skill_cost_reduction(ability_name: String) -> float:
	"""Get the cost reduction percentage for an ability (0-100)."""
	return get_skill_enhancement(ability_name, "cost_reduction")

func get_skill_damage_bonus(ability_name: String) -> float:
	"""Get the damage bonus percentage for an ability."""
	return get_skill_enhancement(ability_name, "damage_bonus")

func get_all_skill_enhancements() -> Dictionary:
	"""Get all skill enhancements."""
	return skill_enhancements.duplicate(true)

# ===== TROPHY SYSTEM =====

func add_trophy(trophy_id: String, monster_name: String, monster_level: int) -> bool:
	"""Add a trophy to the collection. Returns true if added (not a duplicate)."""
	# Check if already have this trophy
	for trophy in trophies:
		if trophy.get("id") == trophy_id:
			return false  # Already have it
	trophies.append({
		"id": trophy_id,
		"monster_name": monster_name,
		"monster_level": monster_level,
		"obtained_at": int(Time.get_unix_time_from_system())
	})
	return true

func has_trophy(trophy_id: String) -> bool:
	"""Check if character has a specific trophy."""
	for trophy in trophies:
		if trophy.get("id") == trophy_id:
			return true
	return false

func get_trophy_count() -> int:
	"""Get total number of trophies collected."""
	return trophies.size()

func get_all_trophies() -> Array:
	"""Get all trophies."""
	return trophies.duplicate(true)

# ===== COMPANION SYSTEM =====

func add_soul_gem(gem_id: String, gem_name: String, bonuses: Dictionary) -> bool:
	"""Add a soul gem to the collection. Returns true if added (not duplicate)."""
	for gem in soul_gems:
		if gem.get("id") == gem_id:
			return false  # Already have it
	soul_gems.append({
		"id": gem_id,
		"name": gem_name,
		"bonuses": bonuses,
		"obtained_at": int(Time.get_unix_time_from_system())
	})
	return true

func has_soul_gem(gem_id: String) -> bool:
	"""Check if character has a specific soul gem."""
	for gem in soul_gems:
		if gem.get("id") == gem_id:
			return true
	return false

func activate_companion(gem_id: String) -> bool:
	"""Activate a companion from owned soul gems. Returns true if successful."""
	for gem in soul_gems:
		if gem.get("id") == gem_id:
			active_companion = {
				"id": gem.id,
				"name": gem.name,
				"bonuses": gem.bonuses.duplicate()
			}
			return true
	return false

func dismiss_companion() -> void:
	"""Dismiss the active companion."""
	active_companion = {}

func get_companion_bonus(bonus_type: String) -> float:
	"""Get active companion's bonus value for a type (e.g., 'attack', 'hp_regen', 'flee_bonus')."""
	if active_companion.is_empty():
		return 0.0
	var bonuses = active_companion.get("bonuses", {})
	return bonuses.get(bonus_type, 0.0)

func has_active_companion() -> bool:
	"""Check if a companion is active."""
	return not active_companion.is_empty()

func get_active_companion() -> Dictionary:
	"""Get the active companion data."""
	return active_companion.duplicate(true)

func get_all_soul_gems() -> Array:
	"""Get all collected soul gems."""
	return soul_gems.duplicate(true)

# ===== CLOAK SYSTEM =====

func get_primary_resource() -> String:
	"""Get the primary resource type for this character's class path"""
	match get_class_path():
		"mage": return "mana"
		"warrior": return "stamina"
		"trickster": return "energy"
		_: return "mana"

func get_primary_resource_current() -> int:
	"""Get current value of primary resource"""
	match get_class_path():
		"mage": return current_mana
		"warrior": return current_stamina
		"trickster": return current_energy
		_: return current_mana

func get_primary_resource_max() -> int:
	"""Get max value of primary resource"""
	match get_class_path():
		"mage": return max_mana
		"warrior": return max_stamina
		"trickster": return max_energy
		_: return max_mana

func get_cloak_cost() -> int:
	"""Get the resource cost to maintain cloak for one movement"""
	var max_resource = get_primary_resource_max()
	return max(1, int(max_resource * CLOAK_COST_PERCENT / 100.0))

func can_maintain_cloak() -> bool:
	"""Check if character has enough resource to maintain cloak"""
	return get_primary_resource_current() >= get_cloak_cost()

func drain_cloak_cost() -> int:
	"""Drain the cloak cost from primary resource. Returns amount drained."""
	var cost = get_cloak_cost()
	var path = get_class_path()
	match path:
		"mage":
			var actual = min(cost, current_mana)
			current_mana -= actual
			return actual
		"warrior":
			var actual = min(cost, current_stamina)
			current_stamina -= actual
			return actual
		"trickster":
			var actual = min(cost, current_energy)
			current_energy -= actual
			return actual
	return 0

func toggle_cloak() -> Dictionary:
	"""Toggle cloak on/off. Returns result with success and message."""
	if cloak_active:
		cloak_active = false
		return {"success": true, "message": "You drop your cloak and become visible.", "active": false}
	else:
		if can_maintain_cloak():
			cloak_active = true
			var cost = get_cloak_cost()
			var resource = get_primary_resource()
			return {"success": true, "message": "You cloak yourself in shadows. (-%d %s per move)" % [cost, resource], "active": true}
		else:
			return {"success": false, "message": "Not enough %s to maintain cloak!" % get_primary_resource(), "active": false}

func process_cloak_on_move() -> Dictionary:
	"""Process cloak drain when moving. Returns result with cloak status."""
	if not cloak_active:
		return {"cloaked": false, "dropped": false}

	if can_maintain_cloak():
		var drained = drain_cloak_cost()
		return {"cloaked": true, "dropped": false, "drained": drained}
	else:
		cloak_active = false
		return {"cloaked": false, "dropped": true, "message": "Your cloak fades as you run out of %s!" % get_primary_resource()}
