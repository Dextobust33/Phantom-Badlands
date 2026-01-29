# drop_tables.gd
# Item drop table system for Phantasia Revival
# This file contains stub implementations for future item drops
class_name DropTables
extends Node

# Consumable tier definitions
# Tiers replace level-based scaling with fixed power levels that stack
const CONSUMABLE_TIERS = {
	1: {"name": "Minor", "healing": 50, "buff_value": 3, "forcefield_value": 1500, "level_min": 1, "level_max": 10},
	2: {"name": "Lesser", "healing": 100, "buff_value": 5, "forcefield_value": 2500, "level_min": 11, "level_max": 25},
	3: {"name": "Standard", "healing": 200, "buff_value": 8, "forcefield_value": 4000, "level_min": 26, "level_max": 50},
	4: {"name": "Greater", "healing": 400, "buff_value": 12, "forcefield_value": 6000, "level_min": 51, "level_max": 100},
	5: {"name": "Superior", "healing": 800, "buff_value": 18, "forcefield_value": 10000, "level_min": 101, "level_max": 250},
	6: {"name": "Master", "healing": 1600, "buff_value": 25, "forcefield_value": 15000, "level_min": 251, "level_max": 500},
	7: {"name": "Divine", "healing": 3000, "buff_value": 35, "forcefield_value": 25000, "level_min": 501, "level_max": 99999}
}

# Consumable categories for combat quick-use
const CONSUMABLE_CATEGORIES = {
	"health": ["health_potion"],
	"mana": ["mana_potion"],
	"stamina": ["stamina_potion"],
	"energy": ["energy_potion"],
	"buff": ["strength_potion", "defense_potion", "speed_potion", "crit_potion", "lifesteal_potion", "thorns_potion"],
	"scroll": ["scroll_forcefield", "scroll_rage", "scroll_stone_skin", "scroll_haste", "scroll_vampirism", "scroll_thorns", "scroll_precision", "scroll_time_stop", "scroll_resurrect_lesser", "scroll_resurrect_greater"],
	"bane": ["potion_dragon_bane", "potion_undead_bane", "potion_beast_bane", "potion_demon_bane", "potion_elemental_bane"]
}

func get_tier_for_level(monster_level: int) -> int:
	"""Get the appropriate consumable tier for a monster level"""
	for tier in range(7, 0, -1):  # Check from highest to lowest
		var tier_data = CONSUMABLE_TIERS[tier]
		if monster_level >= tier_data.level_min:
			return tier
	return 1

func get_tier_name(tier: int) -> String:
	"""Get the display name for a tier"""
	if CONSUMABLE_TIERS.has(tier):
		return CONSUMABLE_TIERS[tier].name
	return "Unknown"

# Drop table definitions by tier
# Each entry: {weight: int, item_type: String, rarity: String}
# Higher weight = more common
const DROP_TABLES = {
	"tier1": [
		{"weight": 30, "item_type": "potion_minor", "rarity": "common"},
		{"weight": 15, "item_type": "mana_minor", "rarity": "common"},
		{"weight": 18, "item_type": "weapon_rusty", "rarity": "common"},
		{"weight": 10, "item_type": "armor_leather", "rarity": "common"},
		{"weight": 8, "item_type": "helm_cloth", "rarity": "common"},
		{"weight": 7, "item_type": "shield_wood", "rarity": "common"},
		{"weight": 7, "item_type": "boots_cloth", "rarity": "common"},
		{"weight": 5, "item_type": "ring_copper", "rarity": "uncommon"}
	],
	"tier2": [
		{"weight": 22, "item_type": "potion_lesser", "rarity": "common"},
		{"weight": 10, "item_type": "mana_lesser", "rarity": "common"},
		{"weight": 18, "item_type": "weapon_iron", "rarity": "common"},
		{"weight": 14, "item_type": "armor_chain", "rarity": "uncommon"},
		{"weight": 10, "item_type": "helm_leather", "rarity": "common"},
		{"weight": 9, "item_type": "shield_iron", "rarity": "common"},
		{"weight": 9, "item_type": "boots_leather", "rarity": "common"},
		{"weight": 8, "item_type": "ring_silver", "rarity": "uncommon"}
	],
	"tier3": [
		{"weight": 18, "item_type": "potion_standard", "rarity": "common"},
		{"weight": 6, "item_type": "mana_standard", "rarity": "common"},
		{"weight": 6, "item_type": "stamina_standard", "rarity": "common"},
		{"weight": 6, "item_type": "energy_standard", "rarity": "common"},
		{"weight": 15, "item_type": "weapon_steel", "rarity": "uncommon"},
		{"weight": 12, "item_type": "armor_plate", "rarity": "uncommon"},
		{"weight": 9, "item_type": "helm_chain", "rarity": "uncommon"},
		{"weight": 8, "item_type": "shield_steel", "rarity": "uncommon"},
		{"weight": 8, "item_type": "boots_chain", "rarity": "uncommon"},
		{"weight": 7, "item_type": "amulet_bronze", "rarity": "rare"},
		{"weight": 4, "item_type": "potion_strength", "rarity": "uncommon"},
		{"weight": 4, "item_type": "potion_defense", "rarity": "uncommon"},
		{"weight": 4, "item_type": "potion_speed", "rarity": "uncommon"},
		{"weight": 3, "item_type": "potion_crit", "rarity": "uncommon"}
	],
	"tier4": [
		{"weight": 14, "item_type": "potion_greater", "rarity": "uncommon"},
		{"weight": 5, "item_type": "mana_greater", "rarity": "uncommon"},
		{"weight": 5, "item_type": "stamina_greater", "rarity": "uncommon"},
		{"weight": 5, "item_type": "energy_greater", "rarity": "uncommon"},
		{"weight": 15, "item_type": "weapon_enchanted", "rarity": "rare"},
		{"weight": 12, "item_type": "armor_enchanted", "rarity": "rare"},
		{"weight": 9, "item_type": "helm_plate", "rarity": "rare"},
		{"weight": 8, "item_type": "shield_enchanted", "rarity": "rare"},
		{"weight": 8, "item_type": "boots_plate", "rarity": "rare"},
		{"weight": 8, "item_type": "ring_gold", "rarity": "rare"},
		{"weight": 6, "item_type": "amulet_silver", "rarity": "rare"},
		{"weight": 4, "item_type": "potion_strength", "rarity": "rare"},
		{"weight": 3, "item_type": "potion_defense", "rarity": "rare"},
		{"weight": 3, "item_type": "potion_speed", "rarity": "rare"},
		{"weight": 3, "item_type": "potion_crit", "rarity": "rare"},
		{"weight": 3, "item_type": "potion_lifesteal", "rarity": "rare"},
		{"weight": 3, "item_type": "scroll_monster_select", "rarity": "rare"},
		{"weight": 3, "item_type": "scroll_forcefield", "rarity": "rare"},
		{"weight": 2, "item_type": "scroll_weakness", "rarity": "rare"},
		{"weight": 2, "item_type": "scroll_vulnerability", "rarity": "rare"}
	],
	"tier5": [
		{"weight": 12, "item_type": "potion_superior", "rarity": "rare"},
		{"weight": 6, "item_type": "mana_superior", "rarity": "rare"},
		{"weight": 16, "item_type": "weapon_magical", "rarity": "rare"},
		{"weight": 14, "item_type": "armor_magical", "rarity": "rare"},
		{"weight": 10, "item_type": "helm_magical", "rarity": "rare"},
		{"weight": 9, "item_type": "shield_magical", "rarity": "rare"},
		{"weight": 9, "item_type": "boots_magical", "rarity": "rare"},
		{"weight": 10, "item_type": "amulet_silver", "rarity": "epic"},
		{"weight": 3, "item_type": "potion_strength", "rarity": "epic"},
		{"weight": 3, "item_type": "potion_defense", "rarity": "epic"},
		{"weight": 3, "item_type": "potion_speed", "rarity": "epic"},
		{"weight": 3, "item_type": "potion_lifesteal", "rarity": "epic"},
		{"weight": 3, "item_type": "potion_thorns", "rarity": "epic"},
		{"weight": 3, "item_type": "ring_elemental", "rarity": "epic"},
		{"weight": 3, "item_type": "scroll_monster_select", "rarity": "epic"},
		{"weight": 3, "item_type": "scroll_forcefield", "rarity": "epic"},
		{"weight": 3, "item_type": "scroll_rage", "rarity": "epic"},
		{"weight": 2, "item_type": "scroll_vampirism", "rarity": "epic"},
		{"weight": 2, "item_type": "scroll_slow", "rarity": "epic"},
		{"weight": 2, "item_type": "scroll_doom", "rarity": "epic"},
		{"weight": 2, "item_type": "scroll_target_farm", "rarity": "epic"}
	],
	"tier6": [
		{"weight": 8, "item_type": "potion_master", "rarity": "rare"},
		{"weight": 4, "item_type": "mana_master", "rarity": "rare"},
		{"weight": 14, "item_type": "weapon_elemental", "rarity": "epic"},
		{"weight": 12, "item_type": "armor_elemental", "rarity": "epic"},
		{"weight": 8, "item_type": "helm_elemental", "rarity": "epic"},
		{"weight": 7, "item_type": "shield_elemental", "rarity": "epic"},
		{"weight": 7, "item_type": "boots_elemental", "rarity": "epic"},
		{"weight": 8, "item_type": "ring_elemental", "rarity": "epic"},
		{"weight": 4, "item_type": "amulet_gold", "rarity": "epic"},
		# High-tier consumables
		{"weight": 3, "item_type": "scroll_time_stop", "rarity": "epic"},
		{"weight": 4, "item_type": "potion_dragon_bane", "rarity": "epic"},
		{"weight": 4, "item_type": "potion_undead_bane", "rarity": "epic"},
		{"weight": 4, "item_type": "potion_beast_bane", "rarity": "epic"},
		# Stat tomes
		{"weight": 3, "item_type": "tome_strength", "rarity": "epic"},
		{"weight": 3, "item_type": "tome_constitution", "rarity": "epic"},
		{"weight": 3, "item_type": "tome_dexterity", "rarity": "epic"},
		{"weight": 3, "item_type": "tome_intelligence", "rarity": "epic"},
		# Mystery items
		{"weight": 3, "item_type": "mysterious_box", "rarity": "epic"},
		{"weight": 2, "item_type": "cursed_coin", "rarity": "epic"}
	],
	"tier7": [
		{"weight": 8, "item_type": "elixir_minor", "rarity": "epic"},
		{"weight": 16, "item_type": "weapon_legendary", "rarity": "epic"},
		{"weight": 14, "item_type": "armor_legendary", "rarity": "epic"},
		{"weight": 10, "item_type": "helm_legendary", "rarity": "epic"},
		{"weight": 8, "item_type": "shield_legendary", "rarity": "epic"},
		{"weight": 8, "item_type": "boots_legendary", "rarity": "epic"},
		{"weight": 8, "item_type": "amulet_gold", "rarity": "legendary"},
		{"weight": 8, "item_type": "ring_legendary", "rarity": "legendary"},
		# Stat tomes (all 6)
		{"weight": 2, "item_type": "tome_strength", "rarity": "legendary"},
		{"weight": 2, "item_type": "tome_constitution", "rarity": "legendary"},
		{"weight": 2, "item_type": "tome_dexterity", "rarity": "legendary"},
		{"weight": 2, "item_type": "tome_intelligence", "rarity": "legendary"},
		{"weight": 2, "item_type": "tome_wisdom", "rarity": "legendary"},
		{"weight": 2, "item_type": "tome_wits", "rarity": "legendary"},
		# Skill enhancer tomes
		{"weight": 2, "item_type": "tome_searing_bolt", "rarity": "legendary"},
		{"weight": 2, "item_type": "tome_brutal_strike", "rarity": "legendary"},
		{"weight": 2, "item_type": "tome_swift_analyze", "rarity": "legendary"},
		# Mystery items
		{"weight": 2, "item_type": "mysterious_box", "rarity": "legendary"}
	],
	"tier8": [
		{"weight": 6, "item_type": "elixir_greater", "rarity": "epic"},
		{"weight": 14, "item_type": "weapon_mythic", "rarity": "legendary"},
		{"weight": 12, "item_type": "armor_mythic", "rarity": "legendary"},
		{"weight": 10, "item_type": "helm_mythic", "rarity": "legendary"},
		{"weight": 9, "item_type": "shield_mythic", "rarity": "legendary"},
		{"weight": 9, "item_type": "boots_mythic", "rarity": "legendary"},
		{"weight": 10, "item_type": "ring_mythic", "rarity": "legendary"},
		{"weight": 10, "item_type": "amulet_mythic", "rarity": "legendary"},
		# Powerful consumables (including lesser resurrect!)
		{"weight": 1, "item_type": "scroll_resurrect_lesser", "rarity": "legendary"},
		{"weight": 2, "item_type": "scroll_time_stop", "rarity": "legendary"},
		# Skill enhancer tomes
		{"weight": 3, "item_type": "tome_efficient_bolt", "rarity": "legendary"},
		{"weight": 3, "item_type": "tome_greater_cleave", "rarity": "legendary"},
		{"weight": 3, "item_type": "tome_greater_ambush", "rarity": "legendary"},
		{"weight": 3, "item_type": "tome_meteor_mastery", "rarity": "legendary"},
		{"weight": 3, "item_type": "tome_devastating_berserk", "rarity": "legendary"},
		{"weight": 3, "item_type": "tome_perfect_exploit", "rarity": "legendary"}
	],
	"tier9": [
		{"weight": 3, "item_type": "elixir_divine", "rarity": "legendary"},
		{"weight": 12, "item_type": "weapon_divine", "rarity": "legendary"},
		{"weight": 11, "item_type": "armor_divine", "rarity": "legendary"},
		{"weight": 9, "item_type": "helm_divine", "rarity": "legendary"},
		{"weight": 8, "item_type": "shield_divine", "rarity": "legendary"},
		{"weight": 8, "item_type": "boots_divine", "rarity": "legendary"},
		{"weight": 8, "item_type": "ring_divine", "rarity": "legendary"},
		{"weight": 7, "item_type": "amulet_divine", "rarity": "legendary"},
		{"weight": 8, "item_type": "artifact", "rarity": "artifact"},
		# Very powerful consumables
		{"weight": 2, "item_type": "scroll_resurrect_lesser", "rarity": "artifact"},
		{"weight": 1, "item_type": "scroll_resurrect_greater", "rarity": "artifact"},
		{"weight": 3, "item_type": "scroll_time_stop", "rarity": "artifact"},
		# All skill enhancer tomes with higher drop rates
		{"weight": 3, "item_type": "tome_searing_bolt", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_efficient_bolt", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_greater_forcefield", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_meteor_mastery", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_brutal_strike", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_efficient_strike", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_devastating_berserk", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_swift_analyze", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_greater_ambush", "rarity": "artifact"},
		{"weight": 3, "item_type": "tome_perfect_exploit", "rarity": "artifact"}
	],
	"common": [
		{"weight": 60, "item_type": "potion_minor", "rarity": "common"},
		{"weight": 30, "item_type": "gold_pouch", "rarity": "common"},
		{"weight": 10, "item_type": "gem_small", "rarity": "uncommon"}
	]
}

# Potion effects for consumables
# heal: restores HP, mana: restores mana, buff: applies temporary combat buff, gold: grants gold, gems: grants gems
const POTION_EFFECTS = {
	# Gold pouches - grants variable gold based on item level
	"gold_pouch": {"gold": true, "base": 50, "per_level": 25, "variance": 0.5},  # 50 + 25*level ± 50%
	# Gem items - grants gems (premium currency)
	"gem_small": {"gems": true, "base": 1, "per_tier": 1},  # 1 gem + 1 per tier above 1
	# === NORMALIZED TYPES (used by tiered consumables) ===
	"health_potion": {"heal": true, "base": 0, "per_level": 0},  # Uses tier system for actual values
	"mana_potion": {"mana": true, "base": 0, "per_level": 0},
	"stamina_potion": {"stamina": true, "base": 0, "per_level": 0},
	"energy_potion": {"energy": true, "base": 0, "per_level": 0},
	"elixir": {"heal": true, "base": 0, "per_level": 0},
	# === LEGACY TYPES (for backwards compatibility with old items) ===
	# Healing potions
	"potion_minor": {"heal": true, "base": 10, "per_level": 10},
	"potion_lesser": {"heal": true, "base": 20, "per_level": 12},
	"potion_standard": {"heal": true, "base": 40, "per_level": 15},
	"potion_greater": {"heal": true, "base": 80, "per_level": 20},
	"potion_superior": {"heal": true, "base": 150, "per_level": 25},
	"potion_master": {"heal": true, "base": 300, "per_level": 30},
	"elixir_minor": {"heal": true, "base": 500, "per_level": 40},
	"elixir_greater": {"heal": true, "base": 1000, "per_level": 60},
	"elixir_divine": {"heal": true, "base": 2000, "per_level": 100},
	# Mana potions
	"mana_minor": {"mana": true, "base": 15, "per_level": 8},
	"mana_lesser": {"mana": true, "base": 30, "per_level": 10},
	"mana_standard": {"mana": true, "base": 50, "per_level": 12},
	"mana_greater": {"mana": true, "base": 100, "per_level": 15},
	"mana_superior": {"mana": true, "base": 200, "per_level": 20},
	"mana_master": {"mana": true, "base": 400, "per_level": 25},
	# Stamina potions (for Warriors)
	"stamina_minor": {"stamina": true, "base": 15, "per_level": 8},
	"stamina_lesser": {"stamina": true, "base": 30, "per_level": 10},
	"stamina_standard": {"stamina": true, "base": 50, "per_level": 12},
	"stamina_greater": {"stamina": true, "base": 100, "per_level": 15},
	# Energy potions (for Tricksters)
	"energy_minor": {"energy": true, "base": 15, "per_level": 8},
	"energy_lesser": {"energy": true, "base": 30, "per_level": 10},
	"energy_standard": {"energy": true, "base": 50, "per_level": 12},
	"energy_greater": {"energy": true, "base": 100, "per_level": 15},
	# Basic buff potions - last rounds (single combat), scale with level
	"potion_strength": {"buff": "strength", "base": 3, "per_level": 1, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	"potion_defense": {"buff": "defense", "base": 3, "per_level": 1, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	"potion_speed": {"buff": "speed", "base": 5, "per_level": 2, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	"potion_crit": {"buff": "crit_chance", "base": 10, "per_level": 1, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	"potion_lifesteal": {"buff": "lifesteal", "base": 10, "per_level": 2, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	"potion_thorns": {"buff": "thorns", "base": 15, "per_level": 2, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	# Power potions - last multiple battles
	"potion_power": {"buff": "strength", "base": 8, "per_level": 2, "battles": true, "base_duration": 2, "duration_per_10_levels": 1},
	"potion_iron": {"buff": "defense", "base": 8, "per_level": 2, "battles": true, "base_duration": 2, "duration_per_10_levels": 1},
	"potion_haste": {"buff": "speed", "base": 15, "per_level": 3, "battles": true, "base_duration": 2, "duration_per_10_levels": 1},
	# Elixirs - powerful multi-battle buffs
	"elixir_might": {"buff": "strength", "base": 15, "per_level": 3, "battles": true, "base_duration": 5, "duration_per_10_levels": 2},
	"elixir_fortress": {"buff": "defense", "base": 15, "per_level": 3, "battles": true, "base_duration": 5, "duration_per_10_levels": 2},
	"elixir_swiftness": {"buff": "speed", "base": 25, "per_level": 5, "battles": true, "base_duration": 5, "duration_per_10_levels": 2},
	# Scrolls - special consumable effects
	"scroll_monster_select": {"monster_select": true},  # Lets player choose next monster encounter
	# Buff scrolls - apply before next combat
	"scroll_forcefield": {"buff": "forcefield", "base": 50, "per_level": 10, "battles": true, "base_duration": 1, "duration_per_10_levels": 0},  # Absorbs damage
	"scroll_rage": {"buff": "strength", "base": 20, "per_level": 4, "battles": true, "base_duration": 1, "duration_per_10_levels": 0},  # +STR for 1 battle
	"scroll_stone_skin": {"buff": "defense", "base": 20, "per_level": 4, "battles": true, "base_duration": 1, "duration_per_10_levels": 0},  # +DEF for 1 battle
	"scroll_haste": {"buff": "speed", "base": 30, "per_level": 5, "battles": true, "base_duration": 1, "duration_per_10_levels": 0},  # +SPD for 1 battle
	"scroll_vampirism": {"buff": "lifesteal", "base": 25, "per_level": 3, "battles": true, "base_duration": 1, "duration_per_10_levels": 0},  # Lifesteal for 1 battle
	"scroll_thorns": {"buff": "thorns", "base": 30, "per_level": 4, "battles": true, "base_duration": 1, "duration_per_10_levels": 0},  # Reflect damage
	"scroll_precision": {"buff": "crit_chance", "base": 25, "per_level": 2, "battles": true, "base_duration": 1, "duration_per_10_levels": 0},  # Crit chance
	# Debuff scrolls - apply debuff to next monster encountered
	"scroll_weakness": {"monster_debuff": "weakness", "base": 25, "per_level": 2},  # -ATK on monster
	"scroll_vulnerability": {"monster_debuff": "vulnerability", "base": 25, "per_level": 2},  # -DEF on monster
	"scroll_slow": {"monster_debuff": "slow", "base": 30, "per_level": 3},  # -SPD on monster
	"scroll_doom": {"monster_debuff": "doom", "base": 10, "per_level": 2},  # Monster loses % max HP at start
	# Target farming scroll - guarantees ability on next N encounters
	"scroll_target_farm": {"target_farm": true, "encounters": 5},
	# === HIGH-TIER CONSUMABLES (Tier 5+) ===
	# Time Stop Scroll - Skip monster's next turn
	"scroll_time_stop": {"time_stop": true, "battles": 1},
	# Monster Bane Potions - +50% damage vs specific monster types
	"potion_dragon_bane": {"monster_bane": "dragon", "damage_bonus": 50, "battles": 3},
	"potion_undead_bane": {"monster_bane": "undead", "damage_bonus": 50, "battles": 3},
	"potion_beast_bane": {"monster_bane": "beast", "damage_bonus": 50, "battles": 3},
	"potion_demon_bane": {"monster_bane": "demon", "damage_bonus": 50, "battles": 3},
	"potion_elemental_bane": {"monster_bane": "elemental", "damage_bonus": 50, "battles": 3},
	# Lesser Resurrect Scroll - Death prevention for 1 battle, revive at 25% HP
	"scroll_resurrect_lesser": {"resurrect": true, "revive_percent": 25, "battles": 1},
	# Greater Resurrect Scroll - Persists until you actually die, revive at 50% HP
	"scroll_resurrect_greater": {"resurrect": true, "revive_percent": 50, "battles": -1},  # -1 = until death
	# === MYSTERY/GAMBLING ITEMS (Tier 4+) ===
	# Mysterious Box - Opens to random item from same tier or +1 higher
	"mysterious_box": {"mystery_box": true},
	# Cursed Coin - 50% double gold, 50% lose half gold
	"cursed_coin": {"cursed_coin": true},
	# === STAT TOMES (Tier 6+) ===
	# Each tome permanently increases a stat by 1
	"tome_strength": {"permanent_stat": "strength", "amount": 1},
	"tome_constitution": {"permanent_stat": "constitution", "amount": 1},
	"tome_dexterity": {"permanent_stat": "dexterity", "amount": 1},
	"tome_intelligence": {"permanent_stat": "intelligence", "amount": 1},
	"tome_wisdom": {"permanent_stat": "wisdom", "amount": 1},
	"tome_wits": {"permanent_stat": "wits", "amount": 1},
	# === SKILL ENHANCER TOMES (Tier 7+) ===
	# Mage skill enhancers
	"tome_searing_bolt": {"skill_enhance": "magic_bolt", "effect": "damage_bonus", "value": 15},
	"tome_efficient_bolt": {"skill_enhance": "magic_bolt", "effect": "cost_reduction", "value": 10},
	"tome_greater_forcefield": {"skill_enhance": "forcefield", "effect": "damage_bonus", "value": 20},  # Shield strength
	"tome_meteor_mastery": {"skill_enhance": "meteor", "effect": "damage_bonus", "value": 25},
	# Warrior skill enhancers
	"tome_brutal_strike": {"skill_enhance": "power_strike", "effect": "damage_bonus", "value": 15},
	"tome_efficient_strike": {"skill_enhance": "power_strike", "effect": "cost_reduction", "value": 10},
	"tome_greater_cleave": {"skill_enhance": "cleave", "effect": "damage_bonus", "value": 20},
	"tome_devastating_berserk": {"skill_enhance": "berserk", "effect": "damage_bonus", "value": 25},
	# Trickster skill enhancers
	"tome_swift_analyze": {"skill_enhance": "analyze", "effect": "cost_reduction", "value": 100},  # Free analyze!
	"tome_greater_ambush": {"skill_enhance": "ambush", "effect": "damage_bonus", "value": 20},
	"tome_perfect_exploit": {"skill_enhance": "exploit", "effect": "damage_bonus", "value": 25},
	"tome_efficient_vanish": {"skill_enhance": "vanish", "effect": "cost_reduction", "value": 15},
}

# Trophy definitions - rare drops from specific powerful monsters
# Format: {monster_name: {trophy_id, name, description, drop_chance (%)}}
const TROPHY_DEFINITIONS = {
	"Primordial Dragon": {
		"id": "dragon_scale",
		"name": "Primordial Dragon Scale",
		"description": "A scale from the most ancient of dragons, shimmering with primordial power.",
		"drop_chance": 5
	},
	"Elder Lich": {
		"id": "lich_phylactery",
		"name": "Lich's Phylactery",
		"description": "The soul vessel of an Elder Lich. It still pulses with dark energy.",
		"drop_chance": 5
	},
	"Titan": {
		"id": "titan_heart",
		"name": "Heart of the Titan",
		"description": "A massive crystallized heart, still warm with the essence of a Titan.",
		"drop_chance": 5
	},
	"Entropy": {
		"id": "entropy_shard",
		"name": "Shard of Entropy",
		"description": "A fragment of pure chaos. Reality bends around it.",
		"drop_chance": 2
	},
	"God Slayer": {
		"id": "godslayer_blade",
		"name": "Godslayer's Broken Blade",
		"description": "A shard of the weapon that felled a deity. Emanates divine fury.",
		"drop_chance": 2
	},
	"The Nameless One": {
		"id": "nameless_mask",
		"name": "Mask of the Nameless",
		"description": "A featureless mask. Looking at it makes you forget your own name.",
		"drop_chance": 2
	},
	"Avatar of Chaos": {
		"id": "chaos_essence",
		"name": "Essence of Chaos",
		"description": "Pure chaotic energy given form. It shifts between colors impossibly.",
		"drop_chance": 3
	},
	"World Serpent": {
		"id": "serpent_fang",
		"name": "World Serpent's Fang",
		"description": "A fang large enough to be a weapon, dripping with venom that dissolves stone.",
		"drop_chance": 5
	},
	"Phoenix": {
		"id": "phoenix_feather",
		"name": "Phoenix Feather",
		"description": "An eternally burning feather that never consumes itself.",
		"drop_chance": 5
	},
	"Death Incarnate": {
		"id": "death_scythe",
		"name": "Shard of Death's Scythe",
		"description": "A fragment of Death's own weapon. Cold to the touch, even in flame.",
		"drop_chance": 2
	}
}

func get_trophy_definition(monster_name: String) -> Dictionary:
	"""Get trophy definition for a monster, if any."""
	return TROPHY_DEFINITIONS.get(monster_name, {})

func roll_trophy_drop(monster_name: String) -> Dictionary:
	"""Roll for a trophy drop from a monster. Returns trophy info if dropped, empty dict otherwise."""
	var definition = get_trophy_definition(monster_name)
	if definition.is_empty():
		return {}

	var drop_chance = definition.get("drop_chance", 0)
	if randi() % 100 < drop_chance:
		return {
			"id": definition.id,
			"name": definition.name,
			"description": definition.description
		}
	return {}

# Soul Gem definitions - companion items (Tier 7+)
# Format: {id: {name, description, bonuses: {type: value}, tier, drop_chance}}
const SOUL_GEM_DEFINITIONS = {
	"wolf_spirit": {
		"name": "Wolf Spirit Soul Gem",
		"description": "Contains the spirit of a great wolf. Grants ferocity in battle.",
		"bonuses": {"attack": 10},  # +10% attack damage
		"tier": 7,
		"drop_chance": 3
	},
	"phoenix_ember": {
		"name": "Phoenix Ember Soul Gem",
		"description": "A shard of phoenix fire. Grants regeneration.",
		"bonuses": {"hp_regen": 2},  # Regenerate 2% HP per combat round
		"tier": 7,
		"drop_chance": 3
	},
	"shadow_wisp": {
		"name": "Shadow Wisp Soul Gem",
		"description": "A captured wisp of shadow. Grants evasion.",
		"bonuses": {"flee_bonus": 15},  # +15% flee chance
		"tier": 7,
		"drop_chance": 3
	},
	"dragon_essence": {
		"name": "Dragon Essence Soul Gem",
		"description": "Pure draconic essence. Grants devastating power.",
		"bonuses": {"attack": 15, "crit_chance": 5},  # +15% attack, +5% crit
		"tier": 8,
		"drop_chance": 2
	},
	"titan_soul": {
		"name": "Titan's Soul Gem",
		"description": "The bound soul of a Titan. Grants immense fortitude.",
		"bonuses": {"hp_bonus": 20, "defense": 10},  # +20% max HP, +10% defense
		"tier": 8,
		"drop_chance": 2
	},
	"void_fragment": {
		"name": "Void Fragment Soul Gem",
		"description": "A piece of the void given form. Grants otherworldly power.",
		"bonuses": {"attack": 20, "lifesteal": 5},  # +20% attack, 5% lifesteal
		"tier": 9,
		"drop_chance": 1
	},
	"celestial_spark": {
		"name": "Celestial Spark Soul Gem",
		"description": "Divine light captured in crystal. Grants divine protection.",
		"bonuses": {"hp_regen": 5, "defense": 15, "hp_bonus": 10},  # 5% regen, +15% def, +10% HP
		"tier": 9,
		"drop_chance": 1
	}
}

func get_soul_gem_definition(gem_id: String) -> Dictionary:
	"""Get soul gem definition by ID."""
	return SOUL_GEM_DEFINITIONS.get(gem_id, {})

func roll_soul_gem_drop(monster_tier: int) -> Dictionary:
	"""Roll for a soul gem drop based on monster tier. Returns gem info if dropped, empty dict otherwise."""
	# Filter gems by tier
	var available_gems = []
	for gem_id in SOUL_GEM_DEFINITIONS:
		var gem = SOUL_GEM_DEFINITIONS[gem_id]
		if gem.get("tier", 10) <= monster_tier:
			available_gems.append({"id": gem_id, "data": gem})

	if available_gems.is_empty():
		return {}

	# Pick a random gem and check drop chance
	var picked = available_gems[randi() % available_gems.size()]
	var drop_chance = picked.data.get("drop_chance", 0)

	if randi() % 100 < drop_chance:
		return {
			"id": picked.id,
			"name": picked.data.name,
			"description": picked.data.description,
			"bonuses": picked.data.bonuses.duplicate()
		}
	return {}

# Monster type categories for bane potions
# Maps bane type to list of monster names that match that type
const MONSTER_TYPES = {
	"dragon": ["Dragon Wyrmling", "Ancient Dragon", "Primordial Dragon", "World Serpent"],
	"undead": ["Skeleton", "Zombie", "Wight", "Wraith", "Vampire", "Lich", "Elder Lich", "Death Incarnate"],
	"beast": ["Giant Rat", "Wolf", "Giant Spider", "Troll", "Harpy", "Cerberus", "Gryphon", "Hydra"],
	"demon": ["Demon", "Succubus", "Balrog", "Demon Lord", "Avatar of Chaos"],
	"elemental": ["Elemental", "Fire Elemental", "Phoenix", "Golem", "Iron Golem"]
}

func get_monster_type(monster_name: String) -> String:
	"""Get the type category for a monster name (for bane potion matching)"""
	for type_name in MONSTER_TYPES:
		if monster_name in MONSTER_TYPES[type_name]:
			return type_name
	return ""

# Rarity colors for display
const RARITY_COLORS = {
	"common": "#FFFFFF",
	"uncommon": "#1EFF00",
	"rare": "#0070DD",
	"epic": "#A335EE",
	"legendary": "#FF8000",
	"artifact": "#E6CC80"
}

func _ready():
	print("Drop Tables initialized")

func roll_drops(drop_table_id: String, drop_chance: int, monster_level: int) -> Array:
	"""Roll for item drops from a monster. Returns array of dropped items."""
	var drops = []

	# Apply 15% boost to drop chance
	var boosted_chance = int(drop_chance * 1.15)

	# Check if we drop anything at all
	var roll = randi() % 100
	if roll >= boosted_chance:
		return drops  # No drops

	# Get the drop table
	var table = get_drop_table(drop_table_id)
	if table.is_empty():
		return drops

	# Roll for which item drops
	var item = _roll_item_from_table(table)
	if item.is_empty():
		return drops

	# Generate the actual item with stats based on monster level
	var generated_item = _generate_item(item, monster_level)
	if not generated_item.is_empty():
		drops.append(generated_item)

	return drops

func get_drop_table(table_id: String) -> Array:
	"""Get a drop table by ID. Returns empty array if not found."""
	return DROP_TABLES.get(table_id, [])

func _roll_item_from_table(table: Array) -> Dictionary:
	"""Roll for an item from a weighted drop table"""
	if table.is_empty():
		return {}

	# Calculate total weight
	var total_weight = 0
	for entry in table:
		total_weight += entry.get("weight", 0)

	if total_weight <= 0:
		return {}

	# Roll
	var roll = randi() % total_weight
	var cumulative = 0

	for entry in table:
		cumulative += entry.get("weight", 0)
		if roll < cumulative:
			return entry

	return table[-1]  # Fallback to last entry

func _normalize_consumable_type(item_type: String) -> String:
	"""Normalize consumable type for stacking (e.g., potion_minor -> health_potion)"""
	# Health potions
	if item_type in ["potion_minor", "potion_lesser", "potion_standard", "potion_greater", "potion_superior", "potion_master"]:
		return "health_potion"
	# Mana potions
	if item_type in ["mana_minor", "mana_lesser", "mana_standard", "mana_greater", "mana_superior", "mana_master"]:
		return "mana_potion"
	# Stamina potions
	if item_type in ["stamina_minor", "stamina_lesser", "stamina_standard", "stamina_greater"]:
		return "stamina_potion"
	# Energy potions
	if item_type in ["energy_minor", "energy_lesser", "energy_standard", "energy_greater"]:
		return "energy_potion"
	# Elixirs
	if item_type in ["elixir_minor", "elixir_greater", "elixir_divine"]:
		return "elixir"
	# Buff potions - already have good names
	if item_type.begins_with("potion_"):
		return item_type  # strength, defense, speed, crit, lifesteal, thorns
	# Scrolls - already have good names
	if item_type.begins_with("scroll_"):
		return item_type
	# Gold/Gems - keep as-is
	return item_type

func _generate_item(drop_entry: Dictionary, monster_level: int) -> Dictionary:
	"""Generate an actual item from a drop table entry with chance for rarity upgrade."""
	var item_type = drop_entry.get("item_type", "unknown")
	var base_rarity = drop_entry.get("rarity", "common")

	# Check if this is a consumable (potions, resource restorers, scrolls)
	# Consumables use TIER system, not rarity - tier is based on monster level
	var is_consumable = item_type.begins_with("potion_") or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("scroll_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_") or item_type.begins_with("elixir_")

	var final_rarity: String
	var final_level = monster_level

	if is_consumable:
		# Consumables don't have rarity - they use tiers instead
		# Set to "common" as a placeholder (won't be displayed)
		final_rarity = "common"
	else:
		# Equipment gets rarity upgrades
		final_rarity = _maybe_upgrade_rarity(base_rarity)
		# If rarity was upgraded, slightly boost the item level too
		if final_rarity != base_rarity:
			final_level = int(monster_level * 1.1)  # 10% level boost on upgrades

	# Roll for affixes (only for equipment, not consumables)
	var affixes = {} if is_consumable else _roll_affixes(final_rarity, final_level)
	var affix_name = _get_affix_prefix(affixes)
	var affix_suffix = _get_affix_suffix(affixes)

	var item = {
		"id": randi(),
		"type": item_type,
		"rarity": final_rarity,
		"level": final_level,
		"name": affix_name + _get_item_name(item_type, final_rarity) + affix_suffix,
		"affixes": affixes,
		"value": _calculate_item_value(final_rarity, final_level)
	}

	# Add consumable-specific fields for stacking
	if is_consumable:
		item["is_consumable"] = true
		item["quantity"] = 1
		# Normalize type for proper stacking (e.g., potion_minor -> health_potion)
		item["type"] = _normalize_consumable_type(item_type)
		# Determine tier based on monster level
		var tier = get_tier_for_level(final_level)
		item["tier"] = tier
		# Update name to include tier name (no rarity prefix for consumables)
		var tier_name = get_tier_name(tier)
		item["name"] = _get_tiered_consumable_name(item_type, tier_name)
		# Recalculate value based on tier, not rarity
		item["value"] = _calculate_consumable_value(tier, item_type)

	return item

func _get_tiered_consumable_name(item_type: String, tier_name: String) -> String:
	"""Generate display name for tiered consumables (no rarity, just tier)"""
	# Map item types to base names
	var base_names = {
		"potion_minor": "Health Potion",
		"potion_lesser": "Health Potion",
		"potion_standard": "Health Potion",
		"potion_greater": "Health Potion",
		"potion_superior": "Health Potion",
		"potion_master": "Health Potion",
		"mana_minor": "Mana Potion",
		"mana_lesser": "Mana Potion",
		"mana_standard": "Mana Potion",
		"mana_greater": "Mana Potion",
		"mana_superior": "Mana Potion",
		"mana_master": "Mana Potion",
		"stamina_minor": "Stamina Potion",
		"stamina_lesser": "Stamina Potion",
		"stamina_standard": "Stamina Potion",
		"stamina_greater": "Stamina Potion",
		"energy_minor": "Energy Potion",
		"energy_lesser": "Energy Potion",
		"energy_standard": "Energy Potion",
		"energy_greater": "Energy Potion",
		"elixir_minor": "Elixir",
		"elixir_greater": "Elixir",
		"elixir_divine": "Elixir",
		# Buff potions
		"potion_strength": "Strength Potion",
		"potion_defense": "Defense Potion",
		"potion_speed": "Speed Potion",
		"potion_crit": "Critical Potion",
		"potion_lifesteal": "Lifesteal Potion",
		"potion_thorns": "Thorns Potion",
		# Scrolls
		"scroll_monster_select": "Scroll of Summoning",
		"scroll_forcefield": "Scroll of Forcefield",
		"scroll_rage": "Scroll of Rage",
		"scroll_stone_skin": "Scroll of Stone Skin",
		"scroll_haste": "Scroll of Haste",
		"scroll_vampirism": "Scroll of Vampirism",
		"scroll_thorns": "Scroll of Thorns",
		"scroll_precision": "Scroll of Precision",
		"scroll_weakness": "Scroll of Weakness",
		"scroll_vulnerability": "Scroll of Vulnerability",
		"scroll_slow": "Scroll of Slow",
		"scroll_doom": "Scroll of Doom",
		"scroll_target_farm": "Scroll of Finding",
		"scroll_time_stop": "Scroll of Time Stop",
		"scroll_resurrect_lesser": "Lesser Scroll of Resurrection",
		"scroll_resurrect_greater": "Greater Scroll of Resurrection",
		# Gold/Gems (special - don't prefix with tier)
		"gold_pouch": "Gold Pouch",
		"gem_small": "Gem",
	}

	var base_name = base_names.get(item_type, "Consumable")

	# Gold and gem items don't use tier prefix
	if item_type == "gold_pouch" or item_type == "gem_small":
		return base_name

	return tier_name + " " + base_name

func _calculate_consumable_value(tier: int, item_type: String) -> int:
	"""Calculate gold value of a consumable based on tier."""
	# Base values per tier (exponential scaling)
	var tier_values = {
		1: 10,      # Minor
		2: 25,      # Lesser
		3: 60,      # Standard
		4: 150,     # Greater
		5: 400,     # Superior
		6: 1000,    # Master
		7: 2500     # Divine
	}
	var base_value = tier_values.get(tier, 10)

	# Scrolls are worth more
	if item_type.begins_with("scroll_"):
		base_value = int(base_value * 2.5)
	# Elixirs are worth more
	elif item_type.begins_with("elixir_"):
		base_value = int(base_value * 2.0)
	# Buff potions worth slightly more than basic potions
	elif item_type.begins_with("potion_") and not item_type in ["potion_minor", "potion_lesser", "potion_standard", "potion_greater", "potion_superior", "potion_master"]:
		base_value = int(base_value * 1.5)

	return base_value

# Prefix affixes: Adjective-style names that appear BEFORE the item name
# Example: "Draconic Steel Sword"
# Monster-themed prefixes are inspired by creatures in the game
const PREFIX_POOL = [
	# Attack prefixes (generic)
	{"name": "Mighty", "stat": "attack_bonus", "base": 2, "per_level": 0.5},
	{"name": "Brutal", "stat": "attack_bonus", "base": 4, "per_level": 0.8},
	# Attack prefixes (monster-themed)
	{"name": "Orcish", "stat": "attack_bonus", "base": 3, "per_level": 0.6},        # Orc
	{"name": "Draconic", "stat": "attack_bonus", "base": 5, "per_level": 0.9},      # Dragon
	{"name": "Demonic", "stat": "attack_bonus", "base": 6, "per_level": 1.0},       # Demon
	{"name": "Balrog-touched", "stat": "attack_bonus", "base": 7, "per_level": 1.2},# Balrog
	# Defense prefixes (generic)
	{"name": "Fortified", "stat": "defense_bonus", "base": 2, "per_level": 0.5},
	{"name": "Armored", "stat": "defense_bonus", "base": 4, "per_level": 0.8},
	# Defense prefixes (monster-themed)
	{"name": "Skeletal", "stat": "defense_bonus", "base": 3, "per_level": 0.6},     # Skeleton
	{"name": "Golem-forged", "stat": "defense_bonus", "base": 5, "per_level": 0.9}, # Iron Golem
	{"name": "Gargoyle-hewn", "stat": "defense_bonus", "base": 6, "per_level": 1.0},# Gargoyle
	# HP prefixes (generic)
	{"name": "Healthy", "stat": "hp_bonus", "base": 10, "per_level": 2},
	{"name": "Stalwart", "stat": "hp_bonus", "base": 20, "per_level": 3},
	# HP prefixes (monster-themed)
	{"name": "Trollish", "stat": "hp_bonus", "base": 25, "per_level": 4},           # Troll
	{"name": "Hydra-scaled", "stat": "hp_bonus", "base": 30, "per_level": 5},       # Hydra
	{"name": "Titanic", "stat": "hp_bonus", "base": 40, "per_level": 6},            # Titan
	# Speed prefixes (generic)
	{"name": "Quick", "stat": "speed_bonus", "base": 2, "per_level": 0.3},
	{"name": "Swift", "stat": "speed_bonus", "base": 4, "per_level": 0.5},
	# Speed prefixes (monster-themed)
	{"name": "Wolfish", "stat": "speed_bonus", "base": 3, "per_level": 0.4},        # Wolf
	{"name": "Harpy-blessed", "stat": "speed_bonus", "base": 5, "per_level": 0.6},  # Harpy
	{"name": "Serpentine", "stat": "speed_bonus", "base": 6, "per_level": 0.7},     # World Serpent
	# Resource prefixes (mana - monster-themed)
	{"name": "Arcane", "stat": "mana_bonus", "base": 10, "per_level": 2},
	{"name": "Lich-touched", "stat": "mana_bonus", "base": 15, "per_level": 3},     # Lich
	{"name": "Sphinx-blessed", "stat": "mana_bonus", "base": 20, "per_level": 4},   # Sphinx
	# Resource prefixes (stamina - monster-themed)
	{"name": "Enduring", "stat": "stamina_bonus", "base": 5, "per_level": 1},
	{"name": "Minotaur-forged", "stat": "stamina_bonus", "base": 8, "per_level": 1.5}, # Minotaur
	{"name": "Ogre-made", "stat": "stamina_bonus", "base": 10, "per_level": 2},     # Ogre
	# Resource prefixes (energy - monster-themed)
	{"name": "Energetic", "stat": "energy_bonus", "base": 5, "per_level": 1},
	{"name": "Spider-spun", "stat": "energy_bonus", "base": 8, "per_level": 1.5},   # Giant Spider
	{"name": "Void-touched", "stat": "energy_bonus", "base": 12, "per_level": 2},   # Void Walker
]

# Suffix affixes: "of X" style names that appear AFTER the item name
# Example: "Steel Sword of the Dragon"
# Monster-themed suffixes are inspired by creatures in the game
const SUFFIX_POOL = [
	# Stat suffixes - STR (generic + monster-themed)
	{"name": "of Strength", "stat": "str_bonus", "base": 2, "per_level": 0.3},
	{"name": "of the Orc", "stat": "str_bonus", "base": 3, "per_level": 0.4},       # Orc
	{"name": "of the Ogre", "stat": "str_bonus", "base": 4, "per_level": 0.5},      # Ogre
	{"name": "of the Titan", "stat": "str_bonus", "base": 6, "per_level": 0.7},     # Titan
	# Stat suffixes - CON (generic + monster-themed)
	{"name": "of Fortitude", "stat": "con_bonus", "base": 2, "per_level": 0.3},
	{"name": "of the Troll", "stat": "con_bonus", "base": 4, "per_level": 0.5},     # Troll
	{"name": "of the Golem", "stat": "con_bonus", "base": 5, "per_level": 0.6},     # Iron Golem
	{"name": "of the Hydra", "stat": "con_bonus", "base": 6, "per_level": 0.7},     # Hydra
	# Stat suffixes - DEX (generic + monster-themed)
	{"name": "of Dexterity", "stat": "dex_bonus", "base": 2, "per_level": 0.3},
	{"name": "of the Spider", "stat": "dex_bonus", "base": 3, "per_level": 0.4},    # Giant Spider
	{"name": "of the Harpy", "stat": "dex_bonus", "base": 4, "per_level": 0.5},     # Harpy
	{"name": "of the Serpent", "stat": "dex_bonus", "base": 6, "per_level": 0.7},   # World Serpent
	# Stat suffixes - INT (generic + monster-themed)
	{"name": "of Intellect", "stat": "int_bonus", "base": 2, "per_level": 0.3},
	{"name": "of the Wight", "stat": "int_bonus", "base": 3, "per_level": 0.4},     # Wight
	{"name": "of the Lich", "stat": "int_bonus", "base": 5, "per_level": 0.6},      # Lich
	{"name": "of the Sphinx", "stat": "int_bonus", "base": 6, "per_level": 0.7},    # Sphinx
	# Stat suffixes - WIS (generic + monster-themed)
	{"name": "of Wisdom", "stat": "wis_bonus", "base": 2, "per_level": 0.3},
	{"name": "of the Wraith", "stat": "wis_bonus", "base": 4, "per_level": 0.5},    # Wraith
	{"name": "of the Phoenix", "stat": "wis_bonus", "base": 5, "per_level": 0.6},   # Phoenix
	{"name": "of Entropy", "stat": "wis_bonus", "base": 6, "per_level": 0.7},       # Entropy
	# Stat suffixes - WITS (generic + monster-themed)
	{"name": "of Cunning", "stat": "wits_bonus", "base": 2, "per_level": 0.3},
	{"name": "of the Goblin", "stat": "wits_bonus", "base": 3, "per_level": 0.4},   # Goblin
	{"name": "of the Mimic", "stat": "wits_bonus", "base": 4, "per_level": 0.5},    # Mimic
	{"name": "of the Succubus", "stat": "wits_bonus", "base": 6, "per_level": 0.7}, # Succubus
	# Combat suffixes - attack (generic + monster-themed)
	{"name": "of Striking", "stat": "attack_bonus", "base": 2, "per_level": 0.4},
	{"name": "of the Wolf", "stat": "attack_bonus", "base": 3, "per_level": 0.5},   # Wolf
	{"name": "of the Dragon", "stat": "attack_bonus", "base": 5, "per_level": 0.7}, # Ancient Dragon
	{"name": "of the Balrog", "stat": "attack_bonus", "base": 6, "per_level": 0.9}, # Balrog
	# Combat suffixes - defense (generic + monster-themed)
	{"name": "of Warding", "stat": "defense_bonus", "base": 2, "per_level": 0.4},
	{"name": "of the Skeleton", "stat": "defense_bonus", "base": 3, "per_level": 0.5}, # Skeleton
	{"name": "of the Gargoyle", "stat": "defense_bonus", "base": 5, "per_level": 0.7}, # Gargoyle
	{"name": "of the Nazgul", "stat": "defense_bonus", "base": 6, "per_level": 0.9},# Nazgul
	# HP suffixes (generic + monster-themed)
	{"name": "of Vitality", "stat": "hp_bonus", "base": 15, "per_level": 2.5},
	{"name": "of the Giant", "stat": "hp_bonus", "base": 20, "per_level": 3.5},     # Giant
	{"name": "of the Cerberus", "stat": "hp_bonus", "base": 25, "per_level": 4},    # Cerberus
	{"name": "of the Primordial", "stat": "hp_bonus", "base": 35, "per_level": 5},  # Primordial Dragon
	# Resource suffixes - mana (monster-themed)
	{"name": "of the Siren", "stat": "mana_bonus", "base": 12, "per_level": 2.5},   # Siren
	{"name": "of the Elemental", "stat": "mana_bonus", "base": 18, "per_level": 3.5}, # Elemental
	{"name": "of the Elder Lich", "stat": "mana_bonus", "base": 25, "per_level": 5},# Elder Lich
	# Resource suffixes - stamina (monster-themed)
	{"name": "of the Gnoll", "stat": "stamina_bonus", "base": 6, "per_level": 1.2}, # Gnoll
	{"name": "of the Gryphon", "stat": "stamina_bonus", "base": 10, "per_level": 2},# Gryphon
	{"name": "of the God Slayer", "stat": "stamina_bonus", "base": 15, "per_level": 3}, # God Slayer
	# Resource suffixes - energy (monster-themed)
	{"name": "of the Kobold", "stat": "energy_bonus", "base": 6, "per_level": 1.2}, # Kobold
	{"name": "of the Vampire", "stat": "energy_bonus", "base": 10, "per_level": 2}, # Vampire
	{"name": "of the Void", "stat": "energy_bonus", "base": 15, "per_level": 3},    # Void Walker
]

# Specialty affix pools for class-focused merchants
# These map merchant specialties to the specific affix stats they should guarantee
const SPECIALTY_AFFIX_STATS = {
	# Warrior's Outfitter - STR, CON, Stamina, Attack focused
	"warrior_affixes": {
		"prefix_stats": ["attack_bonus", "hp_bonus", "stamina_bonus"],
		"suffix_stats": ["str_bonus", "con_bonus", "attack_bonus", "stamina_bonus"]
	},
	# Mage's Emporium - INT, WIS, Mana focused
	"mage_affixes": {
		"prefix_stats": ["mana_bonus"],
		"suffix_stats": ["int_bonus", "wis_bonus", "mana_bonus"]
	},
	# Rogue's Fence - DEX, WITS, Energy, Speed focused
	"trickster_affixes": {
		"prefix_stats": ["speed_bonus", "energy_bonus"],
		"suffix_stats": ["dex_bonus", "wits_bonus", "energy_bonus", "speed_bonus"]
	},
	# Ironclad Supplier - HP, Defense, CON focused (tank gear)
	"tank_affixes": {
		"prefix_stats": ["defense_bonus", "hp_bonus"],
		"suffix_stats": ["defense_bonus", "hp_bonus", "con_bonus"]
	},
	# Swiftblade Dealer - Attack, Speed, STR focused (DPS gear)
	"dps_affixes": {
		"prefix_stats": ["attack_bonus", "speed_bonus"],
		"suffix_stats": ["attack_bonus", "str_bonus", "speed_bonus"]
	}
}

# Proc Suffixes - Special effects that trigger on hit/being hit (Tier 6+ only)
# These are rarer and more powerful than regular affixes
# Format: {name, proc_type, value, chance (% per hit)}
const PROC_SUFFIX_POOL = [
	# Lifesteal - heal % of damage dealt
	{"name": "of the Vampire", "proc_type": "lifesteal", "value": 10, "chance": 100},  # Always procs, 10% lifesteal
	{"name": "of Blood", "proc_type": "lifesteal", "value": 15, "chance": 100},  # Stronger version
	{"name": "of the Leech", "proc_type": "lifesteal", "value": 20, "chance": 100},  # Tier 8+ version
	# Shocking - % chance for bonus lightning damage on hit
	{"name": "of Thunder", "proc_type": "shocking", "value": 15, "chance": 25},  # 25% chance, 15% bonus damage
	{"name": "of the Storm", "proc_type": "shocking", "value": 25, "chance": 30},  # Stronger
	{"name": "of Lightning", "proc_type": "shocking", "value": 35, "chance": 35},  # Tier 8+
	# Damage Reflect - reflect % damage back to attacker when hit
	{"name": "of Reflection", "proc_type": "damage_reflect", "value": 15, "chance": 100},  # Always active
	{"name": "of Retaliation", "proc_type": "damage_reflect", "value": 25, "chance": 100},  # Stronger
	{"name": "of Vengeance", "proc_type": "damage_reflect", "value": 35, "chance": 100},  # Tier 8+
	# Execute - % chance to deal bonus damage when enemy below 30% HP
	{"name": "of Execution", "proc_type": "execute", "value": 50, "chance": 25},  # 25% chance, 50% bonus damage
	{"name": "of the Executioner", "proc_type": "execute", "value": 75, "chance": 30},  # Stronger
]

func _get_affixes_for_stat(stat: String, is_prefix: bool) -> Array:
	"""Get all affixes that have a specific stat from prefix or suffix pool."""
	var pool = PREFIX_POOL if is_prefix else SUFFIX_POOL
	var matching = []
	for affix in pool:
		if affix.stat == stat:
			matching.append(affix)
	return matching

func roll_affixes_for_specialty(specialty: String, rarity: String, item_level: int) -> Dictionary:
	"""Roll affixes from a specific specialty's affix pool.
	Guarantees affixes with stats matching the specialty."""
	var affixes = {}

	if not SPECIALTY_AFFIX_STATS.has(specialty):
		# Fall back to normal affix rolling if specialty not found
		return _roll_affixes(rarity, item_level)

	var spec_data = SPECIALTY_AFFIX_STATS[specialty]
	var roll_range = _get_stat_roll_range(item_level)
	var total_roll_quality = 0
	var affix_count = 0

	# Specialty merchants guarantee at least one affix
	# Higher rarity = higher chance of getting both prefix AND suffix
	var affix_chances = {
		"common":    {"prefix": 60, "suffix": 30, "both_bonus": 10},
		"uncommon":  {"prefix": 75, "suffix": 50, "both_bonus": 20},
		"rare":      {"prefix": 90, "suffix": 70, "both_bonus": 30},
		"epic":      {"prefix": 100, "suffix": 85, "both_bonus": 50},
		"legendary": {"prefix": 100, "suffix": 95, "both_bonus": 70},
		"artifact":  {"prefix": 100, "suffix": 100, "both_bonus": 90}
	}

	var chances = affix_chances.get(rarity, {"prefix": 60, "suffix": 30, "both_bonus": 10})

	# Roll for prefix from specialty's prefix stats
	var prefix_roll = randi() % 100
	if prefix_roll < chances.prefix and spec_data.prefix_stats.size() > 0:
		# Pick a random stat from the specialty's prefix stats
		var target_stat = spec_data.prefix_stats[randi() % spec_data.prefix_stats.size()]
		var matching_prefixes = _get_affixes_for_stat(target_stat, true)
		if matching_prefixes.size() > 0:
			var prefix = matching_prefixes[randi() % matching_prefixes.size()]
			var result = _calculate_affix_value(prefix, item_level, roll_range)
			affixes[prefix.stat] = result.value
			affixes["prefix_name"] = prefix.name
			total_roll_quality += result.quality
			affix_count += 1

	# Roll for suffix from specialty's suffix stats
	var suffix_roll = randi() % 100
	var suffix_chance = chances.suffix
	if affixes.has("prefix_name"):
		suffix_chance += chances.both_bonus

	if suffix_roll < suffix_chance and spec_data.suffix_stats.size() > 0:
		# Pick a random stat from the specialty's suffix stats
		var target_stat = spec_data.suffix_stats[randi() % spec_data.suffix_stats.size()]
		var matching_suffixes = _get_affixes_for_stat(target_stat, false)
		if matching_suffixes.size() > 0:
			var suffix = matching_suffixes[randi() % matching_suffixes.size()]
			var result = _calculate_affix_value(suffix, item_level, roll_range)

			# If same stat as prefix, add to existing value
			if affixes.has(suffix.stat):
				affixes[suffix.stat] += result.value
			else:
				affixes[suffix.stat] = result.value
			affixes["suffix_name"] = suffix.name
			total_roll_quality += result.quality
			affix_count += 1

	# Store average roll quality if we have affixes
	if affix_count > 0:
		affixes["roll_quality"] = int(total_roll_quality / affix_count)

	return affixes

func _roll_affixes(rarity: String, item_level: int) -> Dictionary:
	"""Roll for item affixes based on rarity. Higher rarity = more/better affixes.
	Items can have a prefix (adjective), suffix (of X), or both."""
	var affixes = {}

	# Chances for prefix and suffix by rarity
	# Format: {prefix_chance, suffix_chance, both_chance (bonus for getting both)}
	var affix_chances = {
		"common":    {"prefix": 10, "suffix": 5,  "both_bonus": 0},    # 10% prefix, 5% suffix
		"uncommon":  {"prefix": 25, "suffix": 15, "both_bonus": 5},    # Can get both
		"rare":      {"prefix": 45, "suffix": 35, "both_bonus": 15},   # 15% bonus for both
		"epic":      {"prefix": 70, "suffix": 55, "both_bonus": 30},   # Good chance for both
		"legendary": {"prefix": 90, "suffix": 80, "both_bonus": 50},   # High chance for both
		"artifact":  {"prefix": 100, "suffix": 95, "both_bonus": 75}   # Almost always both
	}

	var chances = affix_chances.get(rarity, {"prefix": 10, "suffix": 5, "both_bonus": 0})
	var roll_range = _get_stat_roll_range(item_level)
	var total_roll_quality = 0
	var affix_count = 0

	# Roll for prefix
	var prefix_roll = randi() % 100
	if prefix_roll < chances.prefix:
		var prefix = PREFIX_POOL[randi() % PREFIX_POOL.size()]
		var result = _calculate_affix_value(prefix, item_level, roll_range)
		affixes[prefix.stat] = result.value
		affixes["prefix_name"] = prefix.name
		total_roll_quality += result.quality
		affix_count += 1

	# Roll for suffix
	var suffix_roll = randi() % 100
	# If we already have a prefix, apply the both_bonus to make suffix more likely
	var suffix_chance = chances.suffix
	if affixes.has("prefix_name"):
		suffix_chance += chances.both_bonus

	if suffix_roll < suffix_chance:
		var suffix = SUFFIX_POOL[randi() % SUFFIX_POOL.size()]
		var result = _calculate_affix_value(suffix, item_level, roll_range)

		# If same stat as prefix, add to existing value instead of replacing
		if affixes.has(suffix.stat):
			affixes[suffix.stat] += result.value
		else:
			affixes[suffix.stat] = result.value
		affixes["suffix_name"] = suffix.name
		total_roll_quality += result.quality
		affix_count += 1

	# Store average roll quality if we have affixes
	if affix_count > 0:
		affixes["roll_quality"] = int(total_roll_quality / affix_count)

	# Roll for proc suffix (Tier 6+ only, based on item level)
	# Chance: 5% at tier 6, 10% at tier 7, 15% at tier 8, 20% at tier 9
	var tier = get_tier_for_level(item_level)
	if tier >= 6:
		var proc_chance = (tier - 5) * 5  # 5% at tier 6, 20% at tier 9
		if rarity in ["epic", "legendary", "artifact"]:
			proc_chance += 10  # +10% for high rarity
		if randi() % 100 < proc_chance:
			var proc = _roll_proc_suffix(tier)
			if not proc.is_empty():
				affixes["proc_type"] = proc.proc_type
				affixes["proc_value"] = proc.value
				affixes["proc_chance"] = proc.chance
				affixes["proc_name"] = proc.name
				# Replace suffix name with proc name if no regular suffix
				if not affixes.has("suffix_name"):
					affixes["suffix_name"] = proc.name

	return affixes

func _roll_proc_suffix(tier: int) -> Dictionary:
	"""Roll a proc suffix appropriate for the tier level."""
	# Filter procs by tier appropriateness
	var available_procs = []
	for proc in PROC_SUFFIX_POOL:
		# Tier 6: basic procs (lower values)
		# Tier 7-8: medium procs
		# Tier 9: powerful procs
		if proc.value <= 15 or tier >= 7:
			if proc.value <= 25 or tier >= 8:
				if proc.value <= 35 or tier >= 9:
					available_procs.append(proc)

	if available_procs.is_empty():
		return {}

	return available_procs[randi() % available_procs.size()]

func _calculate_affix_value(affix: Dictionary, item_level: int, roll_range: Dictionary) -> Dictionary:
	"""Calculate the value for an affix with roll range applied."""
	var base_value = affix.base + affix.per_level * item_level
	var roll_multiplier = randf_range(roll_range.min_mult, roll_range.max_mult)
	var value = int(base_value * roll_multiplier)
	value = maxi(1, value)

	var quality = int(((roll_multiplier - roll_range.min_mult) / (roll_range.max_mult - roll_range.min_mult)) * 100)
	return {"value": value, "quality": quality}

func _get_stat_roll_range(item_level: int) -> Dictionary:
	"""Get the min/max roll multiplier range based on item level.
	Higher level items have better minimum rolls (tighter range, higher floor)."""
	# Clamp level for calculation (1-200 meaningful range)
	var clamped_level = clampi(item_level, 1, 200)

	# Min multiplier: 0.70 at level 1, scaling to 0.90 at level 100+
	# Formula: 0.70 + (level/100) * 0.20, capped at 0.90
	var min_mult = 0.70 + (float(clamped_level) / 100.0) * 0.20
	min_mult = minf(min_mult, 0.90)

	# Max multiplier: 1.10 at level 1, scaling to 1.30 at level 100+
	# Formula: 1.10 + (level/100) * 0.20, capped at 1.30
	var max_mult = 1.10 + (float(clamped_level) / 100.0) * 0.20
	max_mult = minf(max_mult, 1.30)

	return {"min_mult": min_mult, "max_mult": max_mult}

func _get_affix_prefix(affixes: Dictionary) -> String:
	"""Get prefix for item name (adjective that goes BEFORE the item name)."""
	if affixes.is_empty() or not affixes.has("prefix_name"):
		return ""
	return affixes.get("prefix_name", "") + " "

func _get_affix_suffix(affixes: Dictionary) -> String:
	"""Get suffix for item name (of X phrase that goes AFTER the item name)."""
	if affixes.is_empty() or not affixes.has("suffix_name"):
		return ""
	return " " + affixes.get("suffix_name", "")

func _maybe_upgrade_rarity(base_rarity: String) -> String:
	"""Small chance to upgrade item rarity for exciting drops"""
	var rarity_order = ["common", "uncommon", "rare", "epic", "legendary", "artifact"]
	var current_index = rarity_order.find(base_rarity)

	if current_index < 0 or current_index >= rarity_order.size() - 1:
		return base_rarity  # Already max or unknown

	# Roll for upgrade - decreasing chance for higher tiers
	# Common->Uncommon: 8%, Uncommon->Rare: 5%, Rare->Epic: 3%, Epic->Legendary: 1.5%, Legendary->Artifact: 0.5%
	var upgrade_chances = [8.0, 5.0, 3.0, 1.5, 0.5]
	var chance = upgrade_chances[current_index] if current_index < upgrade_chances.size() else 0.5

	var roll = randf() * 100.0
	if roll < chance:
		return rarity_order[current_index + 1]

	return base_rarity

func _get_item_name(item_type: String, rarity: String = "common") -> String:
	"""Get display name for an item type, with prefix for high rarity."""
	# Special handling for gold pouches - name based on rarity
	if item_type == "gold_pouch":
		match rarity:
			"common": return "Small Gold Pouch"
			"uncommon": return "Gold Pouch"
			"rare": return "Heavy Gold Pouch"
			"epic": return "Bulging Gold Sack"
			"legendary": return "Treasure Chest"
			"artifact": return "Dragon's Hoard"
			_: return "Gold Pouch"

	# Special handling for gem items - name based on rarity
	if item_type == "gem_small":
		match rarity:
			"common": return "Tiny Gem"
			"uncommon": return "Small Gem"
			"rare": return "Gem"
			"epic": return "Precious Gem"
			"legendary": return "Flawless Gem"
			"artifact": return "Perfect Gem"
			_: return "Small Gem"

	# Special handling for scrolls
	if item_type.begins_with("scroll_"):
		var scroll_names = {
			"scroll_monster_select": "Scroll of Summoning",
			"scroll_forcefield": "Scroll of Forcefield",
			"scroll_rage": "Scroll of Rage",
			"scroll_stone_skin": "Scroll of Stone Skin",
			"scroll_haste": "Scroll of Haste",
			"scroll_vampirism": "Scroll of Vampirism",
			"scroll_thorns": "Scroll of Thorns",
			"scroll_precision": "Scroll of Precision",
			"scroll_weakness": "Scroll of Weakness",
			"scroll_vulnerability": "Scroll of Vulnerability",
			"scroll_slow": "Scroll of Slow",
			"scroll_doom": "Scroll of Doom",
			"scroll_target_farm": "Scroll of Finding",
			"scroll_time_stop": "Scroll of Time Stop",
			"scroll_resurrect_lesser": "Lesser Scroll of Resurrection",
			"scroll_resurrect_greater": "Greater Scroll of Resurrection"
		}
		var base_name = scroll_names.get(item_type, "Mysterious Scroll")
		match rarity:
			"epic": return "Ancient " + base_name
			"legendary": return "Arcane " + base_name
			_: return base_name

	# Special handling for bane potions
	if item_type.begins_with("potion_") and "_bane" in item_type:
		var bane_names = {
			"potion_dragon_bane": "Dragon Bane Potion",
			"potion_undead_bane": "Undead Bane Potion",
			"potion_beast_bane": "Beast Bane Potion",
			"potion_demon_bane": "Demon Bane Potion",
			"potion_elemental_bane": "Elemental Bane Potion"
		}
		var base_name = bane_names.get(item_type, "Bane Potion")
		match rarity:
			"epic": return "Potent " + base_name
			"legendary": return "Supreme " + base_name
			_: return base_name

	# Special handling for mystery/gambling items
	if item_type == "mysterious_box":
		match rarity:
			"epic": return "Ornate Mysterious Box"
			"legendary": return "Ancient Mysterious Box"
			_: return "Mysterious Box"

	if item_type == "cursed_coin":
		match rarity:
			"epic": return "Ominous Cursed Coin"
			"legendary": return "Dread Cursed Coin"
			_: return "Cursed Coin"

	# Special handling for stat tomes and skill enhancer tomes
	if item_type.begins_with("tome_"):
		var tome_names = {
			# Stat tomes
			"tome_strength": "Tome of Strength",
			"tome_constitution": "Tome of Constitution",
			"tome_dexterity": "Tome of Dexterity",
			"tome_intelligence": "Tome of Intelligence",
			"tome_wisdom": "Tome of Wisdom",
			"tome_wits": "Tome of Wits",
			# Mage skill enhancer tomes
			"tome_searing_bolt": "Tome of Searing Bolt",
			"tome_efficient_bolt": "Tome of Efficient Bolt",
			"tome_greater_forcefield": "Tome of Greater Forcefield",
			"tome_meteor_mastery": "Tome of Meteor Mastery",
			# Warrior skill enhancer tomes
			"tome_brutal_strike": "Tome of Brutal Strikes",
			"tome_efficient_strike": "Tome of Efficient Strikes",
			"tome_greater_cleave": "Tome of Greater Cleave",
			"tome_devastating_berserk": "Tome of Devastating Berserk",
			# Trickster skill enhancer tomes
			"tome_swift_analyze": "Tome of Swift Analysis",
			"tome_greater_ambush": "Tome of Greater Ambush",
			"tome_perfect_exploit": "Tome of Perfect Exploit",
			"tome_efficient_vanish": "Tome of Efficient Vanish"
		}
		var base_name = tome_names.get(item_type, "Tome of Power")
		match rarity:
			"epic": return "Ancient " + base_name
			"legendary": return "Divine " + base_name
			_: return base_name

	# Special handling for resource potions
	if item_type.begins_with("stamina_"):
		var tier = item_type.replace("stamina_", "").capitalize()
		return tier + " Stamina Potion"
	if item_type.begins_with("energy_"):
		var tier = item_type.replace("energy_", "").capitalize()
		return tier + " Energy Potion"

	# Class-specific gear names
	var class_item_names = {
		"ring_arcane": "Arcane Ring",
		"amulet_mystic": "Mystic Amulet",
		"ring_shadow": "Shadow Ring",
		"amulet_evasion": "Evasion Amulet",
		"boots_swift": "Swift Boots",
		"weapon_warlord": "Warlord Blade",
		"shield_bulwark": "Bulwark Shield"
	}
	if class_item_names.has(item_type):
		var base = class_item_names[item_type]
		match rarity:
			"epic": return "Masterwork " + base
			"legendary": return "Mythical " + base
			"artifact": return "Divine " + base
			_: return base

	# Convert item_type like "weapon_rusty" to "Rusty Weapon"
	var parts = item_type.split("_")
	var name_parts = []
	for i in range(parts.size() - 1, -1, -1):
		name_parts.append(parts[i].capitalize())
	var base_name = " ".join(name_parts)

	# Add exciting prefix for upgraded/high rarity items
	var prefixes = {
		"epic": ["Masterwork", "Pristine", "Exquisite", "Superior"],
		"legendary": ["Ancient", "Mythical", "Heroic", "Fabled"],
		"artifact": ["Divine", "Celestial", "Primordial", "Eternal"]
	}

	if prefixes.has(rarity):
		var prefix_list = prefixes[rarity]
		var prefix = prefix_list[randi() % prefix_list.size()]
		return prefix + " " + base_name

	return base_name

func _calculate_item_value(rarity: String, level: int) -> int:
	"""Calculate gold value of an item based on rarity and level.
	Uses quadratic scaling so high-level gear is MUCH more valuable."""
	var base_values = {
		"common": 10,
		"uncommon": 50,
		"rare": 200,
		"epic": 1000,
		"legendary": 5000,
		"artifact": 25000
	}
	var base = base_values.get(rarity, 10)
	# Quadratic scaling: level 1 = base, level 10 = base*2, level 50 = base*26, level 100 = base*101
	var level_multiplier = 1.0 + (level * level) / 100.0
	return int(base * level_multiplier)

func get_rarity_color(rarity: String) -> String:
	"""Get the display color for a rarity tier"""
	return RARITY_COLORS.get(rarity, "#FFFFFF")

func get_potion_effect(item_type: String) -> Dictionary:
	"""Get the effect data for a potion type. Returns empty dict if not a potion."""
	return POTION_EFFECTS.get(item_type, {})

func is_usable_in_combat(item_type: String) -> bool:
	"""Check if an item can be used during combat."""
	return POTION_EFFECTS.has(item_type)

func to_dict() -> Dictionary:
	return {"initialized": true}

func generate_weapon(monster_level: int) -> Dictionary:
	"""Generate a guaranteed weapon drop from a Weapon Master monster.
	These are special high-quality weapons scaled to the monster's level."""
	# Determine rarity based on level - higher level = better chance of good rarity
	var rarity = _get_rare_drop_rarity(monster_level)

	# Pick a weapon type based on level tier
	var weapon_type = "weapon_rusty"
	if monster_level >= 2000:
		weapon_type = "weapon_mythic"
	elif monster_level >= 500:
		weapon_type = "weapon_legendary"
	elif monster_level >= 100:
		weapon_type = "weapon_elemental"
	elif monster_level >= 50:
		weapon_type = "weapon_magical"
	elif monster_level >= 30:
		weapon_type = "weapon_enchanted"
	elif monster_level >= 15:
		weapon_type = "weapon_steel"
	elif monster_level >= 5:
		weapon_type = "weapon_iron"

	# Generate with boosted level for the rare drop
	var boosted_level = int(monster_level * 1.15)  # 15% level boost

	var affixes = _roll_affixes(rarity, boosted_level)
	var affix_name = _get_affix_prefix(affixes)
	var affix_suffix = _get_affix_suffix(affixes)

	return {
		"id": randi(),
		"type": weapon_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Weapon Master's " + _get_item_name(weapon_type, rarity) + affix_suffix,
		"affixes": affixes,
		"value": _calculate_item_value(rarity, boosted_level),
		"from_rare_monster": true
	}

func generate_shield(monster_level: int) -> Dictionary:
	"""Generate a guaranteed shield drop from a Shield Guardian monster.
	These are special high-quality shields scaled to the monster's level."""
	# Determine rarity based on level - higher level = better chance of good rarity
	var rarity = _get_rare_drop_rarity(monster_level)

	# Pick a shield type based on level tier
	var shield_type = "shield_wood"
	if monster_level >= 2000:
		shield_type = "shield_mythic"
	elif monster_level >= 500:
		shield_type = "shield_legendary"
	elif monster_level >= 100:
		shield_type = "shield_elemental"
	elif monster_level >= 50:
		shield_type = "shield_magical"
	elif monster_level >= 30:
		shield_type = "shield_enchanted"
	elif monster_level >= 15:
		shield_type = "shield_steel"
	elif monster_level >= 5:
		shield_type = "shield_iron"

	# Generate with boosted level for the rare drop
	var boosted_level = int(monster_level * 1.15)  # 15% level boost

	var affixes = _roll_affixes(rarity, boosted_level)
	var affix_name = _get_affix_prefix(affixes)
	var affix_suffix = _get_affix_suffix(affixes)

	return {
		"id": randi(),
		"type": shield_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Guardian's " + _get_item_name(shield_type, rarity) + affix_suffix,
		"affixes": affixes,
		"value": _calculate_item_value(rarity, boosted_level),
		"from_rare_monster": true
	}

func generate_mage_gear(monster_level: int) -> Dictionary:
	"""Generate mage-specific gear from an Arcane Hoarder monster.
	Returns arcane ring or mystic amulet scaled to monster level."""
	var rarity = _get_rare_drop_rarity(monster_level)

	# 50/50 ring or amulet
	var is_ring = randf() < 0.5
	var item_type = "ring_arcane" if is_ring else "amulet_mystic"

	# Generate with boosted level
	var boosted_level = int(monster_level * 1.15)  # 15% level boost

	var affixes = _roll_affixes(rarity, boosted_level)
	var affix_name = _get_affix_prefix(affixes)
	var affix_suffix = _get_affix_suffix(affixes)

	# Use simpler item names to avoid duplicate "Arcane" in name
	# (Arcane Hoarder's Ring instead of Arcane Hoarder's Arcane Ring)
	var base_item_name = "Ring" if is_ring else "Amulet"
	# Add rarity prefix for higher tier items
	match rarity:
		"epic": base_item_name = "Masterwork " + base_item_name
		"legendary": base_item_name = "Mythical " + base_item_name
		"artifact": base_item_name = "Divine " + base_item_name

	# If prefix is "Arcane", mark it with * to show double arcane bonus
	if affixes.get("prefix_name", "") == "Arcane":
		affix_name = "Arcane* "  # Asterisk indicates double arcane synergy

	return {
		"id": randi(),
		"type": item_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Arcane Hoarder's " + base_item_name + affix_suffix,
		"affixes": affixes,
		"value": _calculate_item_value(rarity, boosted_level),
		"from_rare_monster": true
	}

func generate_trickster_gear(monster_level: int) -> Dictionary:
	"""Generate trickster-specific gear from a Cunning Prey monster.
	Returns shadow ring, evasion amulet, or swift boots scaled to monster level."""
	var rarity = _get_rare_drop_rarity(monster_level)

	# 33/33/33 distribution
	var roll = randf()
	var item_type: String
	var base_item_name: String
	if roll < 0.33:
		item_type = "ring_shadow"
		base_item_name = "Shadow Ring"
	elif roll < 0.66:
		item_type = "amulet_evasion"
		base_item_name = "Evasion Amulet"
	else:
		item_type = "boots_swift"
		base_item_name = "Boots"  # Use simple name to avoid "Swift Cunning Prey's Swift Boots"

	# Generate with boosted level
	var boosted_level = int(monster_level * 1.15)  # 15% level boost

	var affixes = _roll_affixes(rarity, boosted_level)
	var affix_name = _get_affix_prefix(affixes)
	var affix_suffix = _get_affix_suffix(affixes)

	# Add rarity prefix for higher tier items
	match rarity:
		"epic": base_item_name = "Masterwork " + base_item_name
		"legendary": base_item_name = "Mythical " + base_item_name
		"artifact": base_item_name = "Divine " + base_item_name

	# If prefix would duplicate item name, mark with * for synergy
	if affixes.get("prefix_name", "") == "Swift" and item_type == "boots_swift":
		affix_name = "Swift* "  # Asterisk indicates double swift synergy

	return {
		"id": randi(),
		"type": item_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Cunning Prey's " + base_item_name + affix_suffix,
		"affixes": affixes,
		"value": _calculate_item_value(rarity, boosted_level),
		"from_rare_monster": true
	}

func generate_warrior_gear(monster_level: int) -> Dictionary:
	"""Generate warrior-specific gear from a Warrior Hoarder monster.
	Returns warlord blade or bulwark shield scaled to monster level."""
	var rarity = _get_rare_drop_rarity(monster_level)

	# 50/50 weapon or shield
	var is_weapon = randf() < 0.5
	var item_type = "weapon_warlord" if is_weapon else "shield_bulwark"

	# Generate with boosted level
	var boosted_level = int(monster_level * 1.15)  # 15% level boost

	var affixes = _roll_affixes(rarity, boosted_level)
	var affix_name = _get_affix_prefix(affixes)
	var affix_suffix = _get_affix_suffix(affixes)

	return {
		"id": randi(),
		"type": item_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Warrior Hoarder's " + _get_item_name(item_type, rarity) + affix_suffix,
		"affixes": affixes,
		"value": _calculate_item_value(rarity, boosted_level),
		"from_rare_monster": true
	}

func _get_rare_drop_rarity(monster_level: int) -> String:
	"""Determine rarity for rare monster drops. Higher level = better rarity."""
	var roll = randf()

	# Level-based thresholds for rarity
	if monster_level >= 1000:
		# High level: 20% legendary, 50% epic, 30% rare
		if roll < 0.20:
			return "legendary"
		elif roll < 0.70:
			return "epic"
		else:
			return "rare"
	elif monster_level >= 100:
		# Mid level: 10% legendary, 40% epic, 40% rare, 10% uncommon
		if roll < 0.10:
			return "legendary"
		elif roll < 0.50:
			return "epic"
		elif roll < 0.90:
			return "rare"
		else:
			return "uncommon"
	elif monster_level >= 30:
		# Lower mid: 5% epic, 35% rare, 40% uncommon, 20% common
		if roll < 0.05:
			return "epic"
		elif roll < 0.40:
			return "rare"
		elif roll < 0.80:
			return "uncommon"
		else:
			return "common"
	else:
		# Low level: 20% rare, 40% uncommon, 40% common
		if roll < 0.20:
			return "rare"
		elif roll < 0.60:
			return "uncommon"
		else:
			return "common"

func generate_shop_item_with_specialty(item_type: String, rarity: String, item_level: int, specialty: String) -> Dictionary:
	"""Generate a shop item with affixes guaranteed from a specific specialty pool.
	Used by affix-focused merchants to ensure their items have relevant stats."""
	# Roll for rarity upgrade
	var final_rarity = _maybe_upgrade_rarity(rarity)
	var final_level = item_level
	if final_rarity != rarity:
		final_level = int(item_level * 1.1)

	# Use specialty affix rolling instead of random
	var affixes = roll_affixes_for_specialty(specialty, final_rarity, final_level)
	var affix_name = _get_affix_prefix(affixes)
	var affix_suffix = _get_affix_suffix(affixes)

	return {
		"id": randi(),
		"type": item_type,
		"rarity": final_rarity,
		"level": final_level,
		"name": affix_name + _get_item_name(item_type, final_rarity) + affix_suffix,
		"affixes": affixes,
		"value": _calculate_item_value(final_rarity, final_level)
	}

func is_affix_specialty(specialty: String) -> bool:
	"""Check if a specialty is an affix-focused specialty."""
	return SPECIALTY_AFFIX_STATS.has(specialty)

func generate_mystery_box_item(box_tier: int) -> Dictionary:
	"""Generate a random item from a mystery box. 50% same tier, 50% one tier higher (max 9)."""
	var target_tier = box_tier
	if randf() < 0.5 and box_tier < 9:
		target_tier = box_tier + 1

	var tier_key = "tier" + str(target_tier)
	if not DROP_TABLES.has(tier_key):
		tier_key = "tier" + str(box_tier)

	var table = DROP_TABLES.get(tier_key, [])
	if table.is_empty():
		return {}

	# Roll an item from the tier table
	var item_entry = _roll_item_from_table(table)
	if item_entry.is_empty():
		return {}

	# Calculate level based on tier
	var level_ranges = {
		1: [1, 10], 2: [11, 25], 3: [26, 50], 4: [51, 100],
		5: [101, 250], 6: [251, 500], 7: [501, 1000], 8: [1001, 2500], 9: [2501, 5000]
	}
	var lvl_range = level_ranges.get(target_tier, [1, 10])
	var item_level = randi_range(lvl_range[0], lvl_range[1])

	return _generate_item(item_entry, item_level)
