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

# Fractional stat accumulators (for class-specific stat gains that use decimals)
@export var stat_accumulator: Dictionary = {
	"strength": 0.0, "constitution": 0.0, "dexterity": 0.0,
	"intelligence": 0.0, "wisdom": 0.0, "wits": 0.0
}

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
	# Handle generic "artifact" type (legacy items) - default to weapon slot
	elif item_type == "artifact":
		return "weapon"
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
# Discovered trading posts: Array of {name: String, x: int, y: int}
@export var discovered_posts: Array = []
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

# Knight/Mentee Status - granted by High King/Elder
# Format: {granted_by: String, granted_by_id: int, granted_at: int (unix timestamp)}
@export var knight_status: Dictionary = {}  # Knighted by High King
@export var mentee_status: Dictionary = {}  # Mentored by Elder

# Guardian Death Save - granted by Eternal (permanent until used)
@export var guardian_death_save: bool = false
@export var guardian_granted_by: String = ""  # Name of Eternal who granted it

# Pilgrimage Progress - Elder's journey to become Eternal
# Format: {stage: String, kills: int, tier8_kills: int, outsmarts: int, gold_donated: int, embers: int, crucible_progress: int}
@export var pilgrimage_progress: Dictionary = {}

# Title Abuse Tracking - for Jarl/High King
# Format: {points: int, last_decay: int (unix timestamp), recent_targets: [{name: String, time: int}], recent_abilities: [int (timestamps)]}
@export var title_abuse: Dictionary = {}

# Title Ability Cooldowns - tracks when abilities can be used again
# Format: {ability_id: int (unix timestamp when available)}
@export var title_cooldowns: Dictionary = {}

# Balance migration flag - characters without this get teleported to safety on first login
@export var balance_migrated_v085: bool = false  # v0.8.5 balance changes

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

# ===== NEW COMPANION SYSTEM (replaces soul gems for egg-based companions) =====
# Incubating Eggs - eggs that are being hatched via movement
# Format: [{egg_id: String, monster_type: String, companion_name: String, tier: int,
#           steps_remaining: int, hatch_steps: int, bonuses: Dictionary, obtained_at: int}]
@export var incubating_eggs: Array = []
const MAX_INCUBATING_EGGS = 3  # Can only incubate 3 eggs at a time

# Companion color variants - assigned randomly when hatched for visual variety
# Each variant has a display name and color code for rendering
const COMPANION_VARIANTS = [
	{"name": "Normal", "color": "#FFFFFF", "rarity": 40},      # White/default - common
	{"name": "Crimson", "color": "#DC143C", "rarity": 10},     # Red variant
	{"name": "Azure", "color": "#007FFF", "rarity": 10},       # Blue variant
	{"name": "Verdant", "color": "#228B22", "rarity": 10},     # Green variant
	{"name": "Golden", "color": "#FFD700", "rarity": 8},       # Gold variant - uncommon
	{"name": "Shadow", "color": "#2F2F2F", "rarity": 8},       # Dark/shadow variant
	{"name": "Violet", "color": "#9400D3", "rarity": 6},       # Purple variant
	{"name": "Frost", "color": "#87CEEB", "rarity": 4},        # Ice blue variant - rare
	{"name": "Infernal", "color": "#FF4500", "rarity": 2},     # Fire orange - very rare
	{"name": "Prismatic", "color": "#FF69B4", "rarity": 1},    # Rainbow/pink - legendary
	{"name": "Void", "color": "#4B0082", "rarity": 1}          # Deep purple - legendary
]

# Collected Companions - companions that have been hatched (can switch between them)
# Format: [{id: String, monster_type: String, name: String, tier: int, bonuses: Dictionary,
#           obtained_at: int, battles_fought: int, variant: String, variant_color: String}]
@export var collected_companions: Array = []

# ===== FISHING SYSTEM =====
@export var fishing_skill: int = 1  # Fishing skill level (1-100)
@export var fishing_xp: int = 0     # XP towards next fishing level
@export var fish_caught: int = 0    # Total fish caught (tracking)

# ===== GATHERING SYSTEM =====
@export var mining_skill: int = 1   # Mining skill level (1-100)
@export var mining_xp: int = 0      # XP towards next mining level
@export var ore_gathered: int = 0   # Total ore gathered (tracking)
@export var logging_skill: int = 1  # Logging skill level (1-100)
@export var logging_xp: int = 0     # XP towards next logging level
@export var wood_gathered: int = 0  # Total wood gathered (tracking)

# ===== SALVAGE SYSTEM =====
@export var salvage_essence: int = 0  # Currency from salvaging items

# ===== CRAFTING SYSTEM =====
@export var crafting_skills: Dictionary = {"blacksmithing": 1, "alchemy": 1, "enchanting": 1}
@export var crafting_xp: Dictionary = {"blacksmithing": 0, "alchemy": 0, "enchanting": 0}
@export var known_recipes: Array = []  # Recipe IDs player has learned
@export var crafting_materials: Dictionary = {}  # {material_id: quantity}

# ===== DUNGEON SYSTEM =====
@export var in_dungeon: bool = false
@export var current_dungeon_id: String = ""  # Instance ID of current dungeon
@export var current_dungeon_type: String = ""  # Type ID (e.g., "goblin_cave")
@export var dungeon_floor: int = 0  # Current floor (0-indexed)
@export var dungeon_x: int = 0  # Position on floor grid
@export var dungeon_y: int = 0
@export var dungeon_encounters_cleared: int = 0  # Total encounters cleared this run
@export var dungeon_cooldowns: Dictionary = {}  # {dungeon_type: timestamp when available}
@export var dungeons_completed: Dictionary = {}  # {dungeon_type: times_completed}

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
			# Nerfed: crit damage 50% → 35%, crit chance 15% → 10%
			return {
				"name": "Backstab",
				"description": "+35% crit damage, +10% base crit chance",
				"color": "#2F4F4F",
				"effects": {
					"crit_damage_bonus": 0.35,  # Reduced from 0.50
					"crit_chance_bonus": 0.10   # Reduced from 0.15
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
	# HP formula: Base 50 + CON × 5 + primary stat contribution
	var primary_stat_bonus = _get_primary_stat_for_hp()
	max_hp = 50 + (constitution * 5) + primary_stat_bonus

	# Resource pools reduced by ~75% from original values for balance
	var base_mana = int((intelligence * 3) + (wisdom * 1.5))  # Mage resource (was INT×12 + WIS×6)
	max_mana = int(base_mana * get_mana_multiplier())         # Apply Elf racial bonus (+25%)
	max_stamina = strength + constitution                      # Warrior resource (was (STR+CON)×4)
	max_energy = int((wits + dexterity) * 0.75)                # Trickster resource (was (WITS+DEX)×4)

func _get_primary_stat_for_hp() -> int:
	"""Get primary stat bonus for HP based on class type"""
	match class_type:
		"Fighter", "Barbarian", "Paladin":
			return strength  # Warriors get STR added to HP
		"Wizard", "Sorcerer", "Sage":
			return int(intelligence * 0.5)  # Mages get half INT added to HP
		"Thief", "Ranger", "Ninja":
			return int(wits * 0.5)  # Tricksters get half WITS added to HP
		_:
			return strength

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

		# Apply diminishing returns for items above level 100
		var effective_level = _get_effective_item_level(item_level)

		# Base bonus scales with effective item level, rarity, and wear
		var base_bonus = int(effective_level * rarity_mult * wear_penalty)

		# STEP 1: Apply base item type bonuses (all items get these)
		# NERFED: Reduced multipliers significantly for balance
		if "weapon" in item_type:
			bonuses.attack += int(base_bonus * 1.5)  # Nerfed from 2.5x
			bonuses.strength += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
		elif "armor" in item_type:
			bonuses.defense += int(base_bonus * 1.0)  # Nerfed from 1.75x
			bonuses.constitution += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			bonuses.max_hp += int(base_bonus * 1.5)  # Nerfed from 2.5x
		elif "helm" in item_type:
			bonuses.defense += int(base_bonus * 0.6)  # Nerfed from 1.0x
			bonuses.wisdom += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "shield" in item_type:
			bonuses.defense += max(1, int(base_bonus * 0.4)) if base_bonus > 0 else 0
			bonuses.max_hp += int(base_bonus * 2.0)  # Nerfed from 4x
			bonuses.constitution += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
		elif "ring" in item_type:
			bonuses.attack += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
			bonuses.dexterity += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			bonuses.intelligence += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "amulet" in item_type:
			bonuses.max_mana += int(base_bonus * 1.0)  # Nerfed from 1.75x
			bonuses.wisdom += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			bonuses.wits += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		elif "boots" in item_type:
			bonuses.speed += int(base_bonus * 0.6)  # Nerfed from 1.0x
			bonuses.dexterity += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			bonuses.defense += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0

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

	# Universal resource conversion: all resource bonuses apply to your class's resource
	# Mana bonuses are ~2x larger than stamina/energy, so scale accordingly:
	# - Mana → Stamina/Energy: 0.5x
	# - Stamina/Energy → Mana: 2x
	var mana_contrib = bonuses.max_mana
	var stam_energy_contrib = bonuses.max_stamina + bonuses.max_energy
	bonuses.max_mana = 0
	bonuses.max_stamina = 0
	bonuses.max_energy = 0

	match class_type:
		"Wizard", "Sorcerer", "Sage":
			# Mana class: mana stays 1:1, stamina/energy scale up 2x
			bonuses.max_mana = mana_contrib + (stam_energy_contrib * 2)
		"Fighter", "Barbarian", "Paladin":
			# Stamina class: stamina/energy stay 1:1, mana scales down 0.5x
			bonuses.max_stamina = int(mana_contrib * 0.5) + stam_energy_contrib
		"Thief", "Ranger", "Ninja", "Trickster":
			# Energy class: stamina/energy stay 1:1, mana scales down 0.5x
			bonuses.max_energy = int(mana_contrib * 0.5) + stam_energy_contrib

	return bonuses

func _get_rarity_multiplier(rarity: String) -> float:
	"""Get multiplier for item rarity - NERFED for balance"""
	match rarity:
		"common": return 1.0
		"uncommon": return 1.2
		"rare": return 1.4
		"epic": return 1.7
		"legendary": return 2.0
		"artifact": return 2.5
		_: return 1.0

func _get_effective_item_level(item_level: int) -> float:
	"""Apply diminishing returns for items above level 50.
	   Items 1-50: Full linear scaling
	   Items 51+: Logarithmic scaling (50 + 15 * log2(level - 49))
	   NERFED: Starts earlier (50 vs 100), smaller scaling factor (15 vs 20)
	   This means a L100 item is ~equivalent to L80, L200 to ~L100, L500 to ~L120"""
	if item_level <= 50:
		return float(item_level)
	# Above 50: diminishing returns using log scaling
	# Formula: 50 + 15 * log2(level - 49)
	# L100 = 50 + 15 * log2(51) ≈ 50 + 15 * 5.67 = 85
	# L200 = 50 + 15 * log2(151) ≈ 50 + 15 * 7.24 = 109
	# L500 = 50 + 15 * log2(451) ≈ 50 + 15 * 8.82 = 132
	# L1000 = 50 + 15 * log2(951) ≈ 50 + 15 * 9.89 = 148
	var excess = item_level - 49
	return 50.0 + 15.0 * log(excess) / log(2.0)

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
	Formula: base max_mana + equipment mana + (equipment INT * 3) + (equipment WIS * 1.5)"""
	var bonuses = get_equipment_bonuses()
	# Equipment INT/WIS contribute to mana via the reduced formula
	var int_mana_bonus = int(bonuses.intelligence * 3)
	var wis_mana_bonus = int(bonuses.wisdom * 1.5)
	return max_mana + bonuses.max_mana + int_mana_bonus + wis_mana_bonus

func get_total_max_stamina() -> int:
	"""Get total max stamina including equipment bonuses.
	Formula: base max_stamina + equipment stamina + equipment STR + equipment CON"""
	var bonuses = get_equipment_bonuses()
	# Equipment STR/CON contribute to stamina via the reduced formula
	var str_stamina_bonus = bonuses.strength
	var con_stamina_bonus = bonuses.constitution
	return max_stamina + bonuses.max_stamina + str_stamina_bonus + con_stamina_bonus

func get_total_max_energy() -> int:
	"""Get total max energy including equipment bonuses.
	Formula: base max_energy + equipment energy + (equipment WIT + DEX) * 0.75"""
	var bonuses = get_equipment_bonuses()
	# Equipment WIT/DEX contribute to energy via the reduced formula
	var equip_energy_bonus = int((bonuses.wits + bonuses.dexterity) * 0.75)
	return max_energy + bonuses.max_energy + equip_energy_bonus

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
	current_stamina = get_total_max_stamina()
	current_energy = get_total_max_energy()

func get_stat_gains_for_class() -> Dictionary:
	"""Get stat increases per level based on class (2.5 total stats per level, class-specific distribution)"""
	var gains = {
		# Warrior Path (primary: STR, secondary: CON) - Total: 2.5
		"Fighter": {"strength": 1.25, "constitution": 0.75, "dexterity": 0.25, "intelligence": 0.0, "wisdom": 0.0, "wits": 0.25},
		"Barbarian": {"strength": 1.5, "constitution": 0.75, "dexterity": 0.25, "intelligence": 0.0, "wisdom": 0.0, "wits": 0.0},
		"Paladin": {"strength": 0.75, "constitution": 1.0, "dexterity": 0.25, "intelligence": 0.0, "wisdom": 0.25, "wits": 0.25},
		# Mage Path (primary: INT, secondary: WIS) - Total: 2.5
		"Wizard": {"strength": 0.0, "constitution": 0.25, "dexterity": 0.25, "intelligence": 1.25, "wisdom": 0.75, "wits": 0.0},
		"Sage": {"strength": 0.0, "constitution": 0.5, "dexterity": 0.25, "intelligence": 0.75, "wisdom": 1.0, "wits": 0.0},
		"Sorcerer": {"strength": 0.0, "constitution": 0.25, "dexterity": 0.25, "intelligence": 1.5, "wisdom": 0.5, "wits": 0.0},
		# Trickster Path (primary: WITS/DEX, secondary: varies) - Total: 2.5
		"Thief": {"strength": 0.0, "constitution": 0.25, "dexterity": 0.75, "intelligence": 0.0, "wisdom": 0.0, "wits": 1.5},
		"Ranger": {"strength": 0.5, "constitution": 0.5, "dexterity": 0.75, "intelligence": 0.0, "wisdom": 0.0, "wits": 0.75},
		"Ninja": {"strength": 0.25, "constitution": 0.25, "dexterity": 1.25, "intelligence": 0.0, "wisdom": 0.0, "wits": 0.75}
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
		"knight_status": knight_status,
		"mentee_status": mentee_status,
		"guardian_death_save": guardian_death_save,
		"guardian_granted_by": guardian_granted_by,
		"pilgrimage_progress": pilgrimage_progress,
		"title_abuse": title_abuse,
		"title_cooldowns": title_cooldowns,
		"balance_migrated_v085": balance_migrated_v085,
		"permanent_stat_bonuses": permanent_stat_bonuses,
		"skill_enhancements": skill_enhancements,
		"trophies": trophies,
		"active_companion": active_companion,
		"soul_gems": soul_gems,
		"discovered_posts": discovered_posts,
		"crafting_materials": crafting_materials,
		"salvage_essence": salvage_essence,
		"mining_skill": mining_skill,
		"mining_xp": mining_xp,
		"ore_gathered": ore_gathered,
		"logging_skill": logging_skill,
		"logging_xp": logging_xp,
		"wood_gathered": wood_gathered
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
	discovered_posts = data.get("discovered_posts", [])

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
	knight_status = data.get("knight_status", {})
	mentee_status = data.get("mentee_status", {})
	guardian_death_save = data.get("guardian_death_save", false)
	guardian_granted_by = data.get("guardian_granted_by", "")
	pilgrimage_progress = data.get("pilgrimage_progress", {})
	title_abuse = data.get("title_abuse", {})
	title_cooldowns = data.get("title_cooldowns", {})

	# Balance migration flag
	balance_migrated_v085 = data.get("balance_migrated_v085", false)

	# Permanent stat bonuses from tomes
	permanent_stat_bonuses = data.get("permanent_stat_bonuses", {})

	# Skill enhancements from skill tomes
	skill_enhancements = data.get("skill_enhancements", {})

	# Trophies
	trophies = data.get("trophies", [])

	# Companions
	active_companion = data.get("active_companion", {})
	soul_gems = data.get("soul_gems", [])

	# Crafting and gathering
	crafting_materials = data.get("crafting_materials", {})
	salvage_essence = data.get("salvage_essence", 0)
	mining_skill = data.get("mining_skill", 1)
	mining_xp = data.get("mining_xp", 0)
	ore_gathered = data.get("ore_gathered", 0)
	logging_skill = data.get("logging_skill", 1)
	logging_xp = data.get("logging_xp", 0)
	wood_gathered = data.get("wood_gathered", 0)

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

func discover_trading_post(post_name: String, post_x: int, post_y: int) -> bool:
	"""Record that the player has discovered a trading post. Returns true if newly discovered."""
	# Check if already discovered
	for post in discovered_posts:
		if post.x == post_x and post.y == post_y:
			return false  # Already discovered
	# Add new discovery
	discovered_posts.append({"name": post_name, "x": post_x, "y": post_y})
	return true

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

		# Get class-specific stat gains (fractional, totaling 2.5 per level)
		var gains = get_stat_gains_for_class()

		# Accumulate fractional stats and apply whole numbers
		for stat_name in ["strength", "constitution", "dexterity", "intelligence", "wisdom", "wits"]:
			stat_accumulator[stat_name] += gains.get(stat_name, 0.0)
			var whole_gain = int(stat_accumulator[stat_name])
			if whole_gain >= 1:
				stat_accumulator[stat_name] -= whole_gain
				match stat_name:
					"strength": strength += whole_gain
					"constitution": constitution += whole_gain
					"dexterity": dexterity += whole_gain
					"intelligence": intelligence += whole_gain
					"wisdom": wisdom += whole_gain
					"wits": wits += whole_gain

		# Recalculate derived stats with new formulas
		calculate_derived_stats()

		# Restore only 10% of resources on level up (prevents ability spam exploit)
		var hp_restore = int(get_total_max_hp() * 0.10)
		var mana_restore = int(get_total_max_mana() * 0.10)
		var stamina_restore = int(get_total_max_stamina() * 0.10)
		var energy_restore = int(get_total_max_energy() * 0.10)

		current_hp = min(get_total_max_hp(), current_hp + hp_restore)
		current_mana = min(get_total_max_mana(), current_mana + mana_restore)
		current_stamina = min(get_total_max_stamina(), current_stamina + stamina_restore)
		current_energy = min(get_total_max_energy(), current_energy + energy_restore)

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
	"""Clamp all resources to their current maximum values (including equipment)."""
	current_hp = min(current_hp, get_total_max_hp())
	current_mana = min(current_mana, get_total_max_mana())
	current_stamina = min(current_stamina, get_total_max_stamina())
	current_energy = min(current_energy, get_total_max_energy())

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

func has_debuff(debuff_type: String) -> bool:
	"""Check if character has a specific debuff (negative buff) active."""
	return has_buff(debuff_type)

func apply_debuff(debuff_type: String, value: int, rounds: int):
	"""Apply a debuff (negative buff) that persists outside combat.
	Uses the persistent buff system with negative connotation."""
	add_persistent_buff(debuff_type, value, rounds)

func get_debuff_value(debuff_type: String) -> int:
	"""Get the current value of a debuff. Returns 0 if not active."""
	return get_buff_value(debuff_type)

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

func get_magic_resistance() -> float:
	"""Get magic damage resistance. Elf gets 20% magic resistance."""
	if race == "Elf":
		return 0.20
	return 0.0

func get_mana_multiplier() -> float:
	"""Get mana pool multiplier. Elf gets +25% mana."""
	if race == "Elf":
		return 1.25
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
	"""Process one turn of poison. Returns damage dealt (negative = healing for Undead).
	Called each combat turn."""
	if not poison_active or poison_turns_remaining <= 0:
		return 0

	poison_turns_remaining -= 1
	if poison_turns_remaining <= 0:
		cure_poison()
		return 0

	# Undead racial: poison heals instead of damages
	if does_poison_heal():
		var heal_amount = int(poison_damage * 0.5)  # Heal for 50% of poison damage
		return -max(1, heal_amount)  # Negative indicates healing

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

func get_dodge_bonus() -> float:
	"""Get dodge chance bonus from racial passive. Halfling gets +10% dodge."""
	if race == "Halfling":
		return 0.10
	return 0.0

func get_gold_multiplier() -> float:
	"""Get gold multiplier from racial passive. Halfling gets +15% gold."""
	if race == "Halfling":
		return 1.15
	return 1.0

func get_low_hp_damage_bonus() -> float:
	"""Get damage bonus when below 50% HP. Orc gets +20% damage."""
	if race == "Orc":
		if current_hp < get_total_max_hp() * 0.5:
			return 0.20
	return 0.0

func get_ability_cost_multiplier() -> float:
	"""Get ability cost multiplier from racial passive. Gnome gets -15% costs."""
	if race == "Gnome":
		return 0.85
	return 1.0

func is_immune_to_death_curse() -> bool:
	"""Check if character is immune to death curse. Undead racial."""
	return race == "Undead"

func does_poison_heal() -> bool:
	"""Check if poison heals instead of damages. Undead racial."""
	return race == "Undead"

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


func restore_all_resources():
	"""Restore all resources to full (for resting or sanctuaries)."""
	current_hp = get_total_max_hp()
	current_mana = get_total_max_mana()
	current_stamina = get_total_max_stamina()
	current_energy = get_total_max_energy()

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

func add_trophy(trophy_id: String, monster_name: String, monster_level: int) -> int:
	"""Add a trophy to the collection. Returns the count of this trophy type after adding."""
	trophies.append({
		"id": trophy_id,
		"monster_name": monster_name,
		"monster_level": monster_level,
		"obtained_at": int(Time.get_unix_time_from_system())
	})
	return get_trophy_count_by_id(trophy_id)

func has_trophy(trophy_id: String) -> bool:
	"""Check if character has at least one of a specific trophy."""
	for trophy in trophies:
		if trophy.get("id") == trophy_id:
			return true
	return false

func get_trophy_count_by_id(trophy_id: String) -> int:
	"""Get the count of a specific trophy type."""
	var count = 0
	for trophy in trophies:
		if trophy.get("id") == trophy_id:
			count += 1
	return count

func get_trophy_count() -> int:
	"""Get total number of trophies collected (including duplicates)."""
	return trophies.size()

func get_unique_trophy_count() -> int:
	"""Get number of unique trophy types collected."""
	var unique_ids = {}
	for trophy in trophies:
		unique_ids[trophy.get("id", "")] = true
	return unique_ids.size()

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

# ===== EGG-BASED COMPANION SYSTEM =====

func add_egg(egg_data: Dictionary) -> Dictionary:
	"""Add an egg to incubating_eggs. Returns {success: bool, message: String}."""
	if incubating_eggs.size() >= MAX_INCUBATING_EGGS:
		return {"success": false, "message": "You can only incubate %d eggs at a time." % MAX_INCUBATING_EGGS}

	var egg = {
		"egg_id": egg_data.get("id", ""),
		"monster_type": egg_data.get("monster_type", ""),
		"companion_name": egg_data.get("companion_name", ""),
		"tier": egg_data.get("tier", 1),
		"steps_remaining": egg_data.get("hatch_steps", 100),
		"hatch_steps": egg_data.get("hatch_steps", 100),
		"bonuses": egg_data.get("bonuses", {}).duplicate(),
		"obtained_at": int(Time.get_unix_time_from_system())
	}
	incubating_eggs.append(egg)
	return {"success": true, "message": "Now incubating: %s" % egg.companion_name}

func process_egg_steps(steps: int = 1) -> Array:
	"""Process movement steps for all incubating eggs. Returns array of hatched companions."""
	var hatched = []
	var remaining_eggs = []

	for egg in incubating_eggs:
		egg.steps_remaining -= steps
		if egg.steps_remaining <= 0:
			# Egg hatched!
			var companion = _hatch_egg(egg)
			hatched.append(companion)
		else:
			remaining_eggs.append(egg)

	incubating_eggs = remaining_eggs
	return hatched

func _roll_companion_variant() -> Dictionary:
	"""Roll for a random companion color variant using weighted rarity."""
	var total_weight = 0
	for variant in COMPANION_VARIANTS:
		total_weight += variant.rarity

	var roll = randi() % total_weight
	var current = 0
	for variant in COMPANION_VARIANTS:
		current += variant.rarity
		if roll < current:
			return variant

	# Fallback to normal
	return COMPANION_VARIANTS[0]

func _hatch_egg(egg: Dictionary) -> Dictionary:
	"""Hatch an egg into a companion and add to collected_companions.
	Assigns a random color variant for visual variety."""
	# Roll for color variant
	var variant = _roll_companion_variant()

	var companion = {
		"id": "companion_" + egg.monster_type.to_lower().replace(" ", "_") + "_" + str(randi()),
		"monster_type": egg.monster_type,
		"name": egg.companion_name,
		"tier": egg.tier,
		"bonuses": egg.bonuses.duplicate(),
		"obtained_at": int(Time.get_unix_time_from_system()),
		"battles_fought": 0,
		"variant": variant.name,
		"variant_color": variant.color
	}
	collected_companions.append(companion)
	return companion

func activate_hatched_companion(companion_id: String) -> bool:
	"""Activate a companion from collected_companions. Returns true if successful."""
	for companion in collected_companions:
		if companion.get("id") == companion_id:
			active_companion = {
				"id": companion.id,
				"name": companion.name,
				"monster_type": companion.get("monster_type", ""),
				"tier": companion.get("tier", 1),
				"bonuses": companion.bonuses.duplicate(),
				"variant": companion.get("variant", "Normal"),
				"variant_color": companion.get("variant_color", "#FFFFFF")
			}
			return true
	return false

func get_incubating_eggs() -> Array:
	"""Get all incubating eggs with progress info."""
	var result = []
	for egg in incubating_eggs:
		var progress = 100.0 * (1.0 - float(egg.steps_remaining) / float(egg.hatch_steps))
		result.append({
			"egg_id": egg.egg_id,
			"companion_name": egg.companion_name,
			"tier": egg.tier,
			"steps_remaining": egg.steps_remaining,
			"hatch_steps": egg.hatch_steps,
			"progress_percent": progress
		})
	return result

func get_collected_companions() -> Array:
	"""Get all collected (hatched) companions."""
	return collected_companions.duplicate(true)

func has_companion_of_type(monster_type: String) -> bool:
	"""Check if player has a companion from a specific monster type."""
	for companion in collected_companions:
		if companion.get("monster_type", "") == monster_type:
			return true
	return false

func get_companion_tier() -> int:
	"""Get the tier of the active companion (0 if none)."""
	return active_companion.get("tier", 0)

# ===== FISHING SYSTEM =====

func add_fishing_xp(xp: int) -> Dictionary:
	"""Add fishing XP and check for level up. Returns {leveled_up: bool, new_level: int}."""
	fishing_xp += xp
	var leveled_up = false
	var xp_needed = _get_fishing_xp_needed(fishing_skill)

	while fishing_xp >= xp_needed and fishing_skill < 100:
		fishing_xp -= xp_needed
		fishing_skill += 1
		leveled_up = true
		xp_needed = _get_fishing_xp_needed(fishing_skill)

	return {"leveled_up": leveled_up, "new_level": fishing_skill}

func _get_fishing_xp_needed(current_level: int) -> int:
	"""Get XP needed for next fishing level."""
	# Simple formula: 50 * level^1.5
	return int(50 * pow(current_level, 1.5))

func record_fish_caught():
	"""Record a successful catch."""
	fish_caught += 1

func get_fishing_stats() -> Dictionary:
	"""Get fishing statistics."""
	return {
		"skill": fishing_skill,
		"xp": fishing_xp,
		"xp_needed": _get_fishing_xp_needed(fishing_skill),
		"total_caught": fish_caught
	}

# ===== GATHERING SYSTEM (Mining & Logging) =====

func add_mining_xp(xp: int) -> Dictionary:
	"""Add mining XP and check for level up. Returns {leveled_up: bool, new_level: int}."""
	mining_xp += xp
	var leveled_up = false
	var xp_needed = _get_gathering_xp_needed(mining_skill)

	while mining_xp >= xp_needed and mining_skill < 100:
		mining_xp -= xp_needed
		mining_skill += 1
		leveled_up = true
		xp_needed = _get_gathering_xp_needed(mining_skill)

	return {"leveled_up": leveled_up, "new_level": mining_skill}

func add_logging_xp(xp: int) -> Dictionary:
	"""Add logging XP and check for level up. Returns {leveled_up: bool, new_level: int}."""
	logging_xp += xp
	var leveled_up = false
	var xp_needed = _get_gathering_xp_needed(logging_skill)

	while logging_xp >= xp_needed and logging_skill < 100:
		logging_xp -= xp_needed
		logging_skill += 1
		leveled_up = true
		xp_needed = _get_gathering_xp_needed(logging_skill)

	return {"leveled_up": leveled_up, "new_level": logging_skill}

func _get_gathering_xp_needed(current_level: int) -> int:
	"""Get XP needed for next gathering skill level."""
	# Same formula as fishing: 50 * level^1.5
	return int(50 * pow(current_level, 1.5))

func record_ore_gathered():
	"""Record a successful mining gather."""
	ore_gathered += 1

func record_wood_gathered():
	"""Record a successful logging gather."""
	wood_gathered += 1

func get_mining_stats() -> Dictionary:
	"""Get mining statistics."""
	return {
		"skill": mining_skill,
		"xp": mining_xp,
		"xp_needed": _get_gathering_xp_needed(mining_skill),
		"total_gathered": ore_gathered
	}

func get_logging_stats() -> Dictionary:
	"""Get logging statistics."""
	return {
		"skill": logging_skill,
		"xp": logging_xp,
		"xp_needed": _get_gathering_xp_needed(logging_skill),
		"total_gathered": wood_gathered
	}

# ===== SALVAGE SYSTEM =====

func add_salvage_essence(amount: int) -> int:
	"""Add salvage essence. Returns new total."""
	salvage_essence += amount
	return salvage_essence

func remove_salvage_essence(amount: int) -> bool:
	"""Remove salvage essence. Returns true if successful."""
	if salvage_essence < amount:
		return false
	salvage_essence -= amount
	return true

func has_salvage_essence(amount: int) -> bool:
	"""Check if player has enough salvage essence."""
	return salvage_essence >= amount

# ===== CRAFTING SYSTEM =====

func add_crafting_material(material_id: String, quantity: int = 1) -> int:
	"""Add crafting materials. Returns new total."""
	if not crafting_materials.has(material_id):
		crafting_materials[material_id] = 0
	crafting_materials[material_id] += quantity
	return crafting_materials[material_id]

func remove_crafting_material(material_id: String, quantity: int = 1) -> bool:
	"""Remove crafting materials. Returns true if successful."""
	if not crafting_materials.has(material_id):
		return false
	if crafting_materials[material_id] < quantity:
		return false
	crafting_materials[material_id] -= quantity
	if crafting_materials[material_id] <= 0:
		crafting_materials.erase(material_id)
	return true

func has_crafting_materials(materials: Dictionary) -> bool:
	"""Check if player has required materials. Format: {material_id: quantity}"""
	for mat_id in materials:
		var needed = materials[mat_id]
		var owned = crafting_materials.get(mat_id, 0)
		if owned < needed:
			return false
	return true

func get_crafting_skill(skill_name: String) -> int:
	"""Get a crafting skill level."""
	return crafting_skills.get(skill_name.to_lower(), 1)

func add_crafting_xp(skill_name: String, xp: int) -> Dictionary:
	"""Add XP to a crafting skill. Returns {leveled_up: bool, new_level: int}."""
	var skill = skill_name.to_lower()
	if not crafting_xp.has(skill):
		crafting_xp[skill] = 0
	if not crafting_skills.has(skill):
		crafting_skills[skill] = 1

	crafting_xp[skill] += xp
	var leveled_up = false
	var current_level = crafting_skills[skill]
	var xp_needed = _get_crafting_xp_needed(current_level)

	while crafting_xp[skill] >= xp_needed and current_level < 100:
		crafting_xp[skill] -= xp_needed
		current_level += 1
		crafting_skills[skill] = current_level
		leveled_up = true
		xp_needed = _get_crafting_xp_needed(current_level)

	return {"leveled_up": leveled_up, "new_level": current_level}

func _get_crafting_xp_needed(current_level: int) -> int:
	"""Get XP needed for next crafting level."""
	# Formula: 100 * level^1.5
	return int(100 * pow(current_level, 1.5))

func learn_recipe(recipe_id: String) -> bool:
	"""Learn a new recipe. Returns true if newly learned."""
	if recipe_id in known_recipes:
		return false
	known_recipes.append(recipe_id)
	return true

func knows_recipe(recipe_id: String) -> bool:
	"""Check if player knows a recipe."""
	return recipe_id in known_recipes

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

# ===== KNIGHT/MENTEE STATUS =====

func is_knighted() -> bool:
	"""Check if character has Knight status"""
	return not knight_status.is_empty()

func is_mentored() -> bool:
	"""Check if character has Mentee status"""
	return not mentee_status.is_empty()

func get_knight_damage_bonus() -> float:
	"""Get damage bonus from Knight status (0.15 = +15%)"""
	if is_knighted():
		return 0.15
	return 0.0

func get_knight_gold_bonus() -> float:
	"""Get gold bonus from Knight status (0.10 = +10%)"""
	if is_knighted():
		return 0.10
	return 0.0

func get_mentee_xp_bonus() -> float:
	"""Get XP bonus from Mentee status (0.30 = +30%)"""
	if is_mentored():
		return 0.30
	return 0.0

func get_mentee_gold_bonus() -> float:
	"""Get gold bonus from Mentee status (0.20 = +20%)"""
	if is_mentored():
		return 0.20
	return 0.0

func clear_knight_status():
	"""Remove Knight status"""
	knight_status = {}

func clear_mentee_status():
	"""Remove Mentee status"""
	mentee_status = {}

func set_knight_status(granter_name: String, granter_id: int):
	"""Set Knight status"""
	knight_status = {
		"granted_by": granter_name,
		"granted_by_id": granter_id,
		"granted_at": int(Time.get_unix_time_from_system())
	}

func set_mentee_status(granter_name: String, granter_id: int):
	"""Set Mentee status"""
	mentee_status = {
		"granted_by": granter_name,
		"granted_by_id": granter_id,
		"granted_at": int(Time.get_unix_time_from_system())
	}

# ===== GUARDIAN DEATH SAVE =====

func has_guardian_death_save() -> bool:
	"""Check if character has a death save from Guardian ability"""
	return guardian_death_save

func use_guardian_death_save() -> bool:
	"""Use the death save. Returns true if it was available."""
	if guardian_death_save:
		guardian_death_save = false
		guardian_granted_by = ""
		return true
	return false

func grant_guardian_death_save(granter_name: String):
	"""Grant a death save from the Guardian ability"""
	guardian_death_save = true
	guardian_granted_by = granter_name

# ===== PILGRIMAGE PROGRESS =====

func get_pilgrimage_stage() -> String:
	"""Get current pilgrimage stage, or empty string if not started"""
	return pilgrimage_progress.get("stage", "")

func init_pilgrimage():
	"""Initialize pilgrimage progress for a new Elder"""
	pilgrimage_progress = {
		"stage": "awakening",
		"kills": 0,
		"tier8_kills": 0,
		"outsmarts": 0,
		"gold_donated": 0,
		"embers": 0,
		"crucible_progress": 0,
		"shrines_completed": []
	}

func add_pilgrimage_kills(count: int = 1):
	"""Add kills to pilgrimage progress"""
	if pilgrimage_progress.is_empty():
		return
	pilgrimage_progress["kills"] = pilgrimage_progress.get("kills", 0) + count

func add_pilgrimage_tier8_kills(count: int = 1):
	"""Add tier 8+ kills to pilgrimage progress"""
	if pilgrimage_progress.is_empty():
		return
	pilgrimage_progress["tier8_kills"] = pilgrimage_progress.get("tier8_kills", 0) + count

func add_pilgrimage_outsmarts(count: int = 1):
	"""Add outsmarts to pilgrimage progress"""
	if pilgrimage_progress.is_empty():
		return
	pilgrimage_progress["outsmarts"] = pilgrimage_progress.get("outsmarts", 0) + count

func add_pilgrimage_gold_donation(amount: int):
	"""Add gold donation to pilgrimage progress"""
	if pilgrimage_progress.is_empty():
		return
	pilgrimage_progress["gold_donated"] = pilgrimage_progress.get("gold_donated", 0) + amount

func add_pilgrimage_embers(count: int = 1):
	"""Add embers to pilgrimage progress"""
	if pilgrimage_progress.is_empty():
		return
	pilgrimage_progress["embers"] = pilgrimage_progress.get("embers", 0) + count

func add_pilgrimage_crucible_progress():
	"""Add crucible boss progress"""
	if pilgrimage_progress.is_empty():
		return
	pilgrimage_progress["crucible_progress"] = pilgrimage_progress.get("crucible_progress", 0) + 1

func reset_pilgrimage_crucible():
	"""Reset crucible progress (on death during crucible)"""
	if pilgrimage_progress.is_empty():
		return
	pilgrimage_progress["crucible_progress"] = 0

func complete_pilgrimage_shrine(shrine_id: String):
	"""Mark a shrine as completed"""
	if pilgrimage_progress.is_empty():
		return
	var shrines = pilgrimage_progress.get("shrines_completed", [])
	if shrine_id not in shrines:
		shrines.append(shrine_id)
		pilgrimage_progress["shrines_completed"] = shrines

func is_pilgrimage_shrine_complete(shrine_id: String) -> bool:
	"""Check if a shrine is completed"""
	var shrines = pilgrimage_progress.get("shrines_completed", [])
	return shrine_id in shrines

func advance_pilgrimage_stage(new_stage: String):
	"""Advance to the next pilgrimage stage"""
	if pilgrimage_progress.is_empty():
		return
	pilgrimage_progress["stage"] = new_stage

# ===== TITLE ABUSE TRACKING =====

func get_abuse_points() -> int:
	"""Get current abuse points"""
	return title_abuse.get("points", 0)

func add_abuse_points(points: int):
	"""Add abuse points"""
	title_abuse["points"] = title_abuse.get("points", 0) + points
	title_abuse["last_activity"] = int(Time.get_unix_time_from_system())

func decay_abuse_points():
	"""Decay abuse points based on time elapsed"""
	var now = int(Time.get_unix_time_from_system())
	var last_decay = title_abuse.get("last_decay", now)
	var elapsed = now - last_decay
	var decay_interval = 3600  # 1 hour
	var decays = int(elapsed / decay_interval)
	if decays > 0:
		var current = title_abuse.get("points", 0)
		title_abuse["points"] = max(0, current - decays)
		title_abuse["last_decay"] = now

func record_ability_target(target_name: String):
	"""Record that an ability was used on a target"""
	var now = int(Time.get_unix_time_from_system())
	var recent = title_abuse.get("recent_targets", [])
	recent.append({"name": target_name, "time": now})
	# Keep only last 30 minutes of targets
	recent = recent.filter(func(t): return now - t.time < 1800)
	title_abuse["recent_targets"] = recent

func count_recent_targets(target_name: String, window_seconds: int = 1800) -> int:
	"""Count how many times a target was hit in the time window"""
	var now = int(Time.get_unix_time_from_system())
	var recent = title_abuse.get("recent_targets", [])
	var count = 0
	for t in recent:
		if t.name == target_name and now - t.time < window_seconds:
			count += 1
	return count

func record_ability_use():
	"""Record that an ability was used (for spam detection)"""
	var now = int(Time.get_unix_time_from_system())
	var recent = title_abuse.get("recent_abilities", [])
	recent.append(now)
	# Keep only last 10 minutes
	recent = recent.filter(func(t): return now - t < 600)
	title_abuse["recent_abilities"] = recent

func count_recent_ability_uses(window_seconds: int = 600) -> int:
	"""Count how many abilities were used in the time window"""
	var now = int(Time.get_unix_time_from_system())
	var recent = title_abuse.get("recent_abilities", [])
	return recent.filter(func(t): return now - t < window_seconds).size()

func clear_abuse_tracking():
	"""Clear all abuse tracking (on title loss)"""
	title_abuse = {}

# ===== TITLE COOLDOWNS =====

func is_ability_on_cooldown(ability_id: String) -> bool:
	"""Check if an ability is on cooldown"""
	var available_at = title_cooldowns.get(ability_id, 0)
	return int(Time.get_unix_time_from_system()) < available_at

func get_ability_cooldown_remaining(ability_id: String) -> int:
	"""Get seconds remaining on cooldown"""
	var available_at = title_cooldowns.get(ability_id, 0)
	var now = int(Time.get_unix_time_from_system())
	return max(0, available_at - now)

func set_ability_cooldown(ability_id: String, cooldown_seconds: int):
	"""Set an ability on cooldown"""
	title_cooldowns[ability_id] = int(Time.get_unix_time_from_system()) + cooldown_seconds

func clear_ability_cooldowns():
	"""Clear all ability cooldowns"""
	title_cooldowns = {}

# ===== DUNGEON SYSTEM =====

func enter_dungeon(instance_id: String, dungeon_type: String, start_x: int, start_y: int):
	"""Enter a dungeon instance"""
	in_dungeon = true
	current_dungeon_id = instance_id
	current_dungeon_type = dungeon_type
	dungeon_floor = 0
	dungeon_x = start_x
	dungeon_y = start_y
	dungeon_encounters_cleared = 0

func exit_dungeon():
	"""Exit current dungeon"""
	in_dungeon = false
	current_dungeon_id = ""
	current_dungeon_type = ""
	dungeon_floor = 0
	dungeon_x = 0
	dungeon_y = 0
	dungeon_encounters_cleared = 0

func advance_dungeon_floor(new_x: int, new_y: int):
	"""Move to the next floor of the dungeon"""
	dungeon_floor += 1
	dungeon_x = new_x
	dungeon_y = new_y

func is_dungeon_on_cooldown(dungeon_type: String) -> bool:
	"""Check if a dungeon type is on cooldown for this character"""
	var available_at = dungeon_cooldowns.get(dungeon_type, 0)
	return int(Time.get_unix_time_from_system()) < available_at

func get_dungeon_cooldown_remaining(dungeon_type: String) -> int:
	"""Get seconds remaining on dungeon cooldown"""
	var available_at = dungeon_cooldowns.get(dungeon_type, 0)
	var now = int(Time.get_unix_time_from_system())
	return max(0, available_at - now)

func set_dungeon_cooldown(dungeon_type: String, cooldown_hours: int):
	"""Set a dungeon on cooldown"""
	dungeon_cooldowns[dungeon_type] = int(Time.get_unix_time_from_system()) + (cooldown_hours * 3600)

func record_dungeon_completion(dungeon_type: String):
	"""Record completing a dungeon"""
	if not dungeons_completed.has(dungeon_type):
		dungeons_completed[dungeon_type] = 0
	dungeons_completed[dungeon_type] += 1

func get_dungeon_completions(dungeon_type: String) -> int:
	"""Get number of times player has completed a dungeon type"""
	return dungeons_completed.get(dungeon_type, 0)
