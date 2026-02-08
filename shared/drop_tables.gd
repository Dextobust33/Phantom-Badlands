# drop_tables.gd
# Item drop table system for Phantasia Revival
# This file contains stub implementations for future item drops
class_name DropTables
extends Node

# Consumable tier definitions
# Tiers replace level-based scaling with fixed power levels that stack
const CONSUMABLE_TIERS = {
	1: {"name": "Minor", "healing": 50, "resource": 30, "buff_value": 3, "forcefield_value": 1500, "level_min": 1, "level_max": 10},
	2: {"name": "Lesser", "healing": 100, "resource": 60, "buff_value": 5, "forcefield_value": 2500, "level_min": 11, "level_max": 25},
	3: {"name": "Standard", "healing": 200, "resource": 120, "buff_value": 8, "forcefield_value": 4000, "level_min": 26, "level_max": 50},
	4: {"name": "Greater", "healing": 400, "resource": 240, "buff_value": 12, "forcefield_value": 6000, "level_min": 51, "level_max": 100},
	5: {"name": "Superior", "healing": 800, "resource": 480, "buff_value": 18, "forcefield_value": 10000, "level_min": 101, "level_max": 250},
	6: {"name": "Master", "healing": 1600, "resource": 960, "buff_value": 25, "forcefield_value": 15000, "level_min": 251, "level_max": 500},
	7: {"name": "Divine", "healing": 3000, "resource": 1800, "buff_value": 35, "forcefield_value": 25000, "level_min": 501, "level_max": 99999}
}

# Consumable categories for combat quick-use
const CONSUMABLE_CATEGORIES = {
	"health": ["health_potion"],
	"resource": ["mana_potion", "stamina_potion", "energy_potion"],  # All restore primary resource
	"buff": ["strength_potion", "defense_potion", "speed_potion", "crit_potion", "lifesteal_potion", "thorns_potion"],
	"scroll": ["scroll_forcefield", "scroll_rage", "scroll_stone_skin", "scroll_haste", "scroll_vampirism", "scroll_thorns", "scroll_precision", "scroll_time_stop", "scroll_resurrect_lesser", "scroll_resurrect_greater"],
	"bane": ["potion_dragon_bane", "potion_undead_bane", "potion_beast_bane", "potion_demon_bane", "potion_elemental_bane"]
}

# ===== SALVAGE SYSTEM =====
# Salvage values by rarity: {base: int, per_level: int}
# Formula: base + (item_level * per_level)
const SALVAGE_VALUES = {
	"common": {"base": 5, "per_level": 1},
	"uncommon": {"base": 10, "per_level": 2},
	"rare": {"base": 25, "per_level": 3},
	"epic": {"base": 50, "per_level": 5},
	"legendary": {"base": 100, "per_level": 8},
	"artifact": {"base": 200, "per_level": 12}
}

# Material bonus from salvaging based on item type
# When salvaging, there's a chance to get bonus crafting materials
const SALVAGE_MATERIAL_BONUS = {
	"weapon": {"material": "ore", "chance": 0.3},      # 30% chance for ore
	"armor": {"material": "leather", "chance": 0.3},   # 30% chance for leather
	"helm": {"material": "leather", "chance": 0.2},    # 20% chance for leather
	"shield": {"material": "ore", "chance": 0.25},     # 25% chance for ore
	"boots": {"material": "leather", "chance": 0.2},   # 20% chance for leather
	"ring": {"material": "enchant", "chance": 0.4},    # 40% chance for enchanting mat
	"amulet": {"material": "enchant", "chance": 0.4},  # 40% chance for enchanting mat
	"belt": {"material": "leather", "chance": 0.15}    # 15% chance for leather
}

# Maps material type to actual material ID based on item tier/level
# NOTE: These must match IDs in crafting_database.gd MATERIALS
const SALVAGE_MATERIAL_TIERS = {
	"ore": ["copper_ore", "iron_ore", "steel_ore", "mithril_ore", "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"],
	"leather": ["ragged_leather", "leather_scraps", "thick_leather", "enchanted_leather", "dragonhide", "void_silk"],
	"enchant": ["magic_dust", "arcane_crystal", "soul_shard", "void_essence", "primordial_spark"]
}

func get_salvage_value(item: Dictionary) -> Dictionary:
	"""Calculate salvage essence value and potential material bonus for an item."""
	var rarity = item.get("rarity", "common")
	var level = item.get("level", 1)
	var item_type = item.get("type", "")

	# Get base salvage values
	var salvage_data = SALVAGE_VALUES.get(rarity, SALVAGE_VALUES["common"])
	var essence = salvage_data.base + (level * salvage_data.per_level)

	# Check for material bonus
	var material_bonus = null
	if SALVAGE_MATERIAL_BONUS.has(item_type):
		var bonus_data = SALVAGE_MATERIAL_BONUS[item_type]
		if randf() < bonus_data.chance:
			# Determine material tier based on item level
			var tier_index = clampi(int(level / 15), 0, 8)  # Every ~15 levels = new tier
			var material_type = bonus_data.material
			if SALVAGE_MATERIAL_TIERS.has(material_type):
				var materials = SALVAGE_MATERIAL_TIERS[material_type]
				tier_index = mini(tier_index, materials.size() - 1)
				material_bonus = {
					"material_id": materials[tier_index],
					"quantity": randi_range(1, 2)
				}

	return {
		"essence": essence,
		"material_bonus": material_bonus
	}

func get_salvage_preview(item: Dictionary) -> Dictionary:
	"""Get expected salvage value range for preview (without random material roll)."""
	var rarity = item.get("rarity", "common")
	var level = item.get("level", 1)
	var item_type = item.get("type", "")

	var salvage_data = SALVAGE_VALUES.get(rarity, SALVAGE_VALUES["common"])
	var essence = salvage_data.base + (level * salvage_data.per_level)

	var possible_material = null
	var material_chance = 0.0
	if SALVAGE_MATERIAL_BONUS.has(item_type):
		var bonus_data = SALVAGE_MATERIAL_BONUS[item_type]
		material_chance = bonus_data.chance
		var tier_index = clampi(int(level / 15), 0, 8)
		var material_type = bonus_data.material
		if SALVAGE_MATERIAL_TIERS.has(material_type):
			var materials = SALVAGE_MATERIAL_TIERS[material_type]
			tier_index = mini(tier_index, materials.size() - 1)
			possible_material = materials[tier_index]

	return {
		"essence": essence,
		"possible_material": possible_material,
		"material_chance": material_chance
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
		{"weight": 18, "item_type": "mana_standard", "rarity": "common"},
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
		{"weight": 15, "item_type": "mana_greater", "rarity": "uncommon"},
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
		{"weight": 2, "item_type": "scroll_vulnerability", "rarity": "rare"},
		# Home Stones - send items to house storage (Tier 4 start)
		{"weight": 3, "item_type": "home_stone_egg", "rarity": "uncommon"},
		{"weight": 2, "item_type": "home_stone_supplies", "rarity": "uncommon"}
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
		{"weight": 2, "item_type": "scroll_target_farm", "rarity": "epic"},
		# Home Stones - send items to house storage
		{"weight": 3, "item_type": "home_stone_egg", "rarity": "uncommon"},
		{"weight": 3, "item_type": "home_stone_supplies", "rarity": "uncommon"},
		{"weight": 2, "item_type": "home_stone_equipment", "rarity": "rare"}
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
		{"weight": 2, "item_type": "cursed_coin", "rarity": "epic"},
		# Home Stones
		{"weight": 4, "item_type": "home_stone_egg", "rarity": "uncommon"},
		{"weight": 3, "item_type": "home_stone_supplies", "rarity": "uncommon"},
		{"weight": 3, "item_type": "home_stone_equipment", "rarity": "rare"},
		{"weight": 2, "item_type": "home_stone_companion", "rarity": "rare"}
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
		{"weight": 2, "item_type": "mysterious_box", "rarity": "legendary"},
		# Home Stones
		{"weight": 4, "item_type": "home_stone_egg", "rarity": "uncommon"},
		{"weight": 4, "item_type": "home_stone_supplies", "rarity": "uncommon"},
		{"weight": 3, "item_type": "home_stone_equipment", "rarity": "rare"},
		{"weight": 2, "item_type": "home_stone_companion", "rarity": "rare"}
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
		{"weight": 3, "item_type": "tome_perfect_exploit", "rarity": "legendary"},
		# Home Stones
		{"weight": 3, "item_type": "home_stone_egg", "rarity": "uncommon"},
		{"weight": 3, "item_type": "home_stone_supplies", "rarity": "uncommon"},
		{"weight": 3, "item_type": "home_stone_equipment", "rarity": "rare"},
		{"weight": 2, "item_type": "home_stone_companion", "rarity": "rare"}
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
		{"weight": 3, "item_type": "tome_perfect_exploit", "rarity": "artifact"},
		# Home Stones
		{"weight": 3, "item_type": "home_stone_egg", "rarity": "uncommon"},
		{"weight": 3, "item_type": "home_stone_supplies", "rarity": "uncommon"},
		{"weight": 3, "item_type": "home_stone_equipment", "rarity": "rare"},
		{"weight": 2, "item_type": "home_stone_companion", "rarity": "rare"}
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
	# === HOME STONES (Tier 5+) ===
	# Send items to house storage for safekeeping (survives permadeath)
	"home_stone_egg": {"home_stone": "egg"},  # Send one incubating egg to house
	"home_stone_supplies": {"home_stone": "supplies"},  # Send up to 10 consumables to house
	"home_stone_equipment": {"home_stone": "equipment"},  # Send one equipped item to house
	"home_stone_companion": {"home_stone": "companion"},  # Register active companion to house
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

# ===== COMPANION & EGG SYSTEM =====
# Every monster in the game has a companion variant and egg
# Companions are miniature versions that fight alongside the player

# Monster to companion name mapping (monster_name -> companion info)
# All 55+ monsters can become companions with tier-appropriate bonuses
const COMPANION_DATA = {
	# Tier 1 (Levels 1-5) - Basic companions with single stat bonus
	"Goblin": {"companion_name": "Goblin Sprite", "tier": 1, "bonuses": {"attack": 2}},
	"Giant Rat": {"companion_name": "Rat Familiar", "tier": 1, "bonuses": {"speed": 3}},
	"Kobold": {"companion_name": "Kobold Helper", "tier": 1, "bonuses": {"gold_find": 5}},
	"Skeleton": {"companion_name": "Bone Servant", "tier": 1, "bonuses": {"defense": 2}},
	"Wolf": {"companion_name": "Wolf Pup", "tier": 1, "bonuses": {"attack": 3}},
	# Tier 2 (Levels 6-15) - Stronger single stat or weak dual stat
	"Orc": {"companion_name": "Orc Grunt", "tier": 2, "bonuses": {"attack": 4}},
	"Hobgoblin": {"companion_name": "Hobgoblin Scout", "tier": 2, "bonuses": {"attack": 3, "speed": 2}},
	"Gnoll": {"companion_name": "Gnoll Pup", "tier": 2, "bonuses": {"attack": 5}},
	"Zombie": {"companion_name": "Zombie Thrall", "tier": 2, "bonuses": {"hp_bonus": 5}},
	"Giant Spider": {"companion_name": "Spider Hatchling", "tier": 2, "bonuses": {"speed": 4, "attack": 2}},
	"Wight": {"companion_name": "Wight Wisp", "tier": 2, "bonuses": {"mana_regen": 1}},
	"Siren": {"companion_name": "Siren Sprite", "tier": 2, "bonuses": {"mana_bonus": 5}},
	"Kelpie": {"companion_name": "Kelpie Foal", "tier": 2, "bonuses": {"speed": 5}},
	"Mimic": {"companion_name": "Mimic Trinket", "tier": 2, "bonuses": {"gold_find": 10}},
	# Tier 3 (Levels 16-30) - Moderate bonuses, more dual stats
	"Ogre": {"companion_name": "Ogre Youngling", "tier": 3, "bonuses": {"attack": 5, "hp_bonus": 3}},
	"Troll": {"companion_name": "Troll Runt", "tier": 3, "bonuses": {"hp_regen": 2}},
	"Wraith": {"companion_name": "Wraith Wisp", "tier": 3, "bonuses": {"mana_bonus": 7, "mana_regen": 1}},
	"Wyvern": {"companion_name": "Wyvern Hatchling", "tier": 3, "bonuses": {"attack": 6, "speed": 3}},
	"Minotaur": {"companion_name": "Minotaur Calf", "tier": 3, "bonuses": {"attack": 7}},
	"Gargoyle": {"companion_name": "Gargoyle Fragment", "tier": 3, "bonuses": {"defense": 6}},
	"Harpy": {"companion_name": "Harpy Chick", "tier": 3, "bonuses": {"speed": 7}},
	"Shrieker": {"companion_name": "Shrieker Spore", "tier": 3, "bonuses": {"flee_bonus": 10}},
	# Tier 4 (Levels 31-50) - Strong bonuses
	"Giant": {"companion_name": "Giant Sprite", "tier": 4, "bonuses": {"hp_bonus": 10, "attack": 5}},
	"Dragon Wyrmling": {"companion_name": "Baby Dragon", "tier": 4, "bonuses": {"attack": 8, "defense": 4}},
	"Demon": {"companion_name": "Demon Imp", "tier": 4, "bonuses": {"attack": 10}},
	"Vampire": {"companion_name": "Vampire Bat", "tier": 4, "bonuses": {"lifesteal": 3}},
	"Gryphon": {"companion_name": "Gryphon Hatchling", "tier": 4, "bonuses": {"speed": 8, "attack": 5}},
	"Chimaera": {"companion_name": "Chimaera Cub", "tier": 4, "bonuses": {"attack": 7, "defense": 5}},
	"Succubus": {"companion_name": "Succubus Familiar", "tier": 4, "bonuses": {"mana_regen": 2, "energy_regen": 2}},
	# Tier 5 (Levels 51-100) - Very strong bonuses
	"Ancient Dragon": {"companion_name": "Dragon Whelp", "tier": 5, "bonuses": {"attack": 12, "defense": 6}},
	"Demon Lord": {"companion_name": "Demon Spawn", "tier": 5, "bonuses": {"attack": 11, "hp_bonus": 7}},
	"Lich": {"companion_name": "Lich Apprentice", "tier": 5, "bonuses": {"mana_bonus": 15, "mana_regen": 2}},
	"Titan": {"companion_name": "Titan Spawn", "tier": 5, "bonuses": {"hp_bonus": 15, "defense": 8}},
	"Balrog": {"companion_name": "Balrog Ember", "tier": 5, "bonuses": {"attack": 12, "crit_chance": 3}},
	"Cerberus": {"companion_name": "Cerberus Pup", "tier": 5, "bonuses": {"attack": 10, "speed": 6}},
	"Jabberwock": {"companion_name": "Jabberwock Hatchling", "tier": 5, "bonuses": {"attack": 11, "hp_regen": 2}},
	# Tier 6 (Levels 101-500) - Powerful bonuses, often triple stat
	"Elemental": {"companion_name": "Elemental Core", "tier": 6, "bonuses": {"attack": 12, "defense": 10}},
	"Iron Golem": {"companion_name": "Golem Fragment", "tier": 6, "bonuses": {"defense": 15, "hp_bonus": 10}},
	"Sphinx": {"companion_name": "Sphinx Kitten", "tier": 6, "bonuses": {"mana_bonus": 12, "wisdom_bonus": 5}},
	"Hydra": {"companion_name": "Hydra Sprout", "tier": 6, "bonuses": {"hp_regen": 4, "attack": 10}},
	"Phoenix": {"companion_name": "Phoenix Chick", "tier": 6, "bonuses": {"hp_regen": 5, "attack": 8}},
	"Nazgul": {"companion_name": "Nazgul Shadow", "tier": 6, "bonuses": {"attack": 14, "flee_bonus": 15}},
	# Tier 7 (Levels 501-2000) - Elite bonuses
	"Void Walker": {"companion_name": "Void Wisp", "tier": 7, "bonuses": {"attack": 16, "speed": 10, "defense": 8}},
	"World Serpent": {"companion_name": "Serpent Hatchling", "tier": 7, "bonuses": {"attack": 18, "hp_bonus": 15}},
	"Elder Lich": {"companion_name": "Elder Shade", "tier": 7, "bonuses": {"mana_bonus": 20, "mana_regen": 4, "attack": 12}},
	"Primordial Dragon": {"companion_name": "Primordial Whelp", "tier": 7, "bonuses": {"attack": 20, "defense": 12, "hp_bonus": 10}},
	# Tier 8 (Levels 2001-5000) - Legendary bonuses
	"Cosmic Horror": {"companion_name": "Cosmic Shard", "tier": 8, "bonuses": {"attack": 20, "hp_bonus": 18, "defense": 12}},
	"Time Weaver": {"companion_name": "Time Fragment", "tier": 8, "bonuses": {"speed": 20, "attack": 15, "crit_chance": 5}},
	"Death Incarnate": {"companion_name": "Death's Echo", "tier": 8, "bonuses": {"attack": 22, "lifesteal": 5}},
	# Tier 9 (Levels 5001+) - Mythic bonuses
	"Avatar of Chaos": {"companion_name": "Chaos Spark", "tier": 9, "bonuses": {"attack": 25, "crit_chance": 8, "hp_bonus": 15}},
	"The Nameless One": {"companion_name": "Nameless Whisper", "tier": 9, "bonuses": {"attack": 22, "defense": 18, "speed": 12}},
	"God Slayer": {"companion_name": "Godslayer Shard", "tier": 9, "bonuses": {"attack": 28, "crit_damage": 15}},
	"Entropy": {"companion_name": "Entropy Mote", "tier": 9, "bonuses": {"attack": 24, "hp_regen": 5, "lifesteal": 4}}
}

# Per-monster companion abilities - each monster type has unique abilities based on their original monster abilities
# Abilities scale with companion level: final_value = base + (scaling * companion_level)
# Types: "passive" (always active), "active" (chance per turn), "threshold" (triggers once when HP drops below %)
# Rarer variant companions get a multiplier on these values (see VARIANT_STAT_MULTIPLIERS in character.gd)
const COMPANION_MONSTER_ABILITIES = {
	# ===== TIER 1 COMPANIONS =====
	"Goblin": {
		"passive": {"name": "Sneaky Support", "effect": "attack", "base": 1, "scaling": 0.03, "description": "Adds attack damage"},
		"active": {"name": "Dirty Trick", "type": "chance", "base_chance": 8, "chance_scaling": 0.1, "effect": "enemy_miss", "description": "Chance to make enemy miss"},
		"threshold": {"name": "Cowardly Retreat", "hp_percent": 40, "effect": "flee_bonus", "base": 10, "scaling": 0.2, "duration": 2, "description": "Boosts flee chance when low HP"}
	},
	"Giant Rat": {
		"passive": {"name": "Scurrying Assistance", "effect": "speed", "base": 2, "scaling": 0.04, "description": "Adds speed"},
		"active": {"name": "Gnaw", "type": "chance", "base_chance": 10, "chance_scaling": 0.1, "effect": "bleed", "base_damage": 2, "damage_scaling": 0.05, "duration": 2, "description": "Chance to cause bleeding"},
		"threshold": {"name": "Survival Instinct", "hp_percent": 35, "effect": "speed_buff", "base": 15, "scaling": 0.2, "duration": 3, "description": "Speed boost when low HP"}
	},
	"Kobold": {
		"passive": {"name": "Treasure Sense", "effect": "gold_find", "base": 3, "scaling": 0.05, "description": "Increases gold find"},
		"active": {"name": "Trap Trigger", "type": "chance", "base_chance": 8, "chance_scaling": 0.08, "effect": "bonus_damage", "base_damage": 5, "damage_scaling": 0.1, "description": "Chance for bonus damage"},
		"threshold": {"name": "Hoard Guard", "hp_percent": 45, "effect": "defense_buff", "base": 8, "scaling": 0.15, "duration": 3, "description": "Defense boost when low HP"}
	},
	"Skeleton": {
		"passive": {"name": "Bone Guard", "effect": "defense", "base": 2, "scaling": 0.03, "description": "Adds defense"},
		"active": {"name": "Rattle", "type": "chance", "base_chance": 10, "chance_scaling": 0.1, "effect": "enemy_miss", "description": "Chance to distract enemy"},
		"threshold": {"name": "Undying Will", "hp_percent": 25, "effect": "absorb", "base": 5, "scaling": 0.15, "duration": 2, "description": "Absorbs some damage when critical"}
	},
	"Wolf": {
		"passive": {"name": "Pack Instinct", "effect": "attack", "base": 2, "scaling": 0.04, "description": "Adds attack damage"},
		"active": {"name": "Ambush Strike", "type": "chance", "base_chance": 12, "chance_scaling": 0.12, "effect": "crit", "crit_mult": 1.5, "description": "Chance to critically strike"},
		"threshold": {"name": "Alpha Howl", "hp_percent": 35, "effect": "attack_buff", "base": 12, "scaling": 0.2, "duration": 3, "description": "Attack boost when low HP"}
	},

	# ===== TIER 2 COMPANIONS =====
	"Orc": {
		"passive": {"name": "Brute Force", "effect": "attack", "base": 3, "scaling": 0.05, "description": "Adds attack damage"},
		"active": {"name": "Battle Rage", "type": "chance", "base_chance": 12, "chance_scaling": 0.12, "effect": "bonus_damage", "base_damage": 8, "damage_scaling": 0.15, "description": "Chance for bonus damage"},
		"threshold": {"name": "Berserker Fury", "hp_percent": 30, "effect": "attack_buff", "base": 20, "scaling": 0.3, "duration": 3, "description": "Major attack boost when low HP"}
	},
	"Hobgoblin": {
		"passive": {"name": "Tactical Mind", "effect": "attack", "base": 2, "scaling": 0.04, "effect2": "speed", "base2": 1, "scaling2": 0.02, "description": "Adds attack and speed"},
		"active": {"name": "Coordinated Strike", "type": "chance", "base_chance": 15, "chance_scaling": 0.1, "effect": "bonus_damage", "base_damage": 6, "damage_scaling": 0.12, "description": "Chance for bonus damage"},
		"threshold": {"name": "Rally Cry", "hp_percent": 40, "effect": "all_buff", "base": 8, "scaling": 0.15, "duration": 2, "description": "Buffs all stats when low HP"}
	},
	"Gnoll": {
		"passive": {"name": "Savage Strength", "effect": "attack", "base": 4, "scaling": 0.06, "description": "Adds significant attack damage"},
		"active": {"name": "Rending Claws", "type": "chance", "base_chance": 14, "chance_scaling": 0.12, "effect": "bleed", "base_damage": 4, "damage_scaling": 0.08, "duration": 3, "description": "Chance to cause bleeding"},
		"threshold": {"name": "Frenzy", "hp_percent": 35, "effect": "attack_buff", "base": 18, "scaling": 0.25, "duration": 3, "description": "Attack boost when low HP"}
	},
	"Zombie": {
		"passive": {"name": "Undead Resilience", "effect": "hp_bonus", "base": 4, "scaling": 0.08, "description": "Adds max HP"},
		"active": {"name": "Infectious Bite", "type": "chance", "base_chance": 10, "chance_scaling": 0.08, "effect": "poison", "base_damage": 3, "damage_scaling": 0.06, "duration": 3, "description": "Chance to poison enemy"},
		"threshold": {"name": "Risen Again", "hp_percent": 20, "effect": "heal", "base": 8, "scaling": 0.2, "description": "Heals when critically low HP"}
	},
	"Giant Spider": {
		"passive": {"name": "Venomous Presence", "effect": "speed", "base": 3, "scaling": 0.05, "effect2": "attack", "base2": 1, "scaling2": 0.02, "description": "Adds speed and attack"},
		"active": {"name": "Poison Bite", "type": "chance", "base_chance": 18, "chance_scaling": 0.15, "effect": "poison", "base_damage": 5, "damage_scaling": 0.1, "duration": 3, "description": "Chance to poison enemy"},
		"threshold": {"name": "Web Trap", "hp_percent": 40, "effect": "slow_enemy", "base": 20, "scaling": 0.2, "duration": 2, "description": "Slows enemy when low HP"}
	},
	"Wight": {
		"passive": {"name": "Spectral Touch", "effect": "mana_regen", "base": 1, "scaling": 0.02, "description": "Adds mana regeneration"},
		"active": {"name": "Life Siphon", "type": "chance", "base_chance": 12, "chance_scaling": 0.1, "effect": "lifesteal", "base_percent": 10, "percent_scaling": 0.15, "description": "Chance to steal life"},
		"threshold": {"name": "Wraithform", "hp_percent": 35, "effect": "dodge_buff", "base": 15, "scaling": 0.2, "duration": 2, "description": "Dodge chance when low HP"}
	},
	"Siren": {
		"passive": {"name": "Melodic Aura", "effect": "mana_bonus", "base": 4, "scaling": 0.08, "description": "Adds max mana"},
		"active": {"name": "Enchanting Song", "type": "chance", "base_chance": 10, "chance_scaling": 0.1, "effect": "charm", "duration": 1, "description": "Chance to charm enemy (skip turn)"},
		"threshold": {"name": "Desperate Melody", "hp_percent": 35, "effect": "mana_restore", "base": 15, "scaling": 0.3, "description": "Restores mana when low HP"}
	},
	"Kelpie": {
		"passive": {"name": "Swift Currents", "effect": "speed", "base": 4, "scaling": 0.07, "description": "Adds speed"},
		"active": {"name": "Tidal Strike", "type": "chance", "base_chance": 14, "chance_scaling": 0.12, "effect": "bonus_damage", "base_damage": 7, "damage_scaling": 0.12, "description": "Chance for bonus damage"},
		"threshold": {"name": "Undertow", "hp_percent": 40, "effect": "slow_enemy", "base": 25, "scaling": 0.25, "duration": 2, "description": "Slows enemy when low HP"}
	},
	"Mimic": {
		"passive": {"name": "Treasure Hunter", "effect": "gold_find", "base": 8, "scaling": 0.15, "description": "Greatly increases gold find"},
		"active": {"name": "Surprise Attack", "type": "chance", "base_chance": 15, "chance_scaling": 0.12, "effect": "crit", "crit_mult": 1.8, "description": "Chance to critically strike"},
		"threshold": {"name": "Fake Out", "hp_percent": 30, "effect": "enemy_miss", "duration": 2, "description": "Enemy misses when low HP"}
	},

	# ===== TIER 3 COMPANIONS =====
	"Ogre": {
		"passive": {"name": "Massive Bulk", "effect": "attack", "base": 4, "scaling": 0.06, "effect2": "hp_bonus", "base2": 2, "scaling2": 0.05, "description": "Adds attack and HP"},
		"active": {"name": "Crushing Blow", "type": "chance", "base_chance": 16, "chance_scaling": 0.12, "effect": "bonus_damage", "base_damage": 12, "damage_scaling": 0.2, "description": "Chance for heavy bonus damage"},
		"threshold": {"name": "Thick Skin", "hp_percent": 35, "effect": "absorb", "base": 10, "scaling": 0.2, "duration": 3, "description": "Absorbs damage when low HP"}
	},
	"Troll": {
		"passive": {"name": "Regeneration", "effect": "hp_regen", "base": 2, "scaling": 0.04, "description": "Heals HP each turn"},
		"active": {"name": "Savage Swipe", "type": "chance", "base_chance": 14, "chance_scaling": 0.1, "effect": "bonus_damage", "base_damage": 10, "damage_scaling": 0.18, "description": "Chance for bonus damage"},
		"threshold": {"name": "Rapid Recovery", "hp_percent": 30, "effect": "heal", "base": 12, "scaling": 0.25, "description": "Major heal when low HP"}
	},
	"Wraith": {
		"passive": {"name": "Ethereal Presence", "effect": "mana_bonus", "base": 5, "scaling": 0.1, "effect2": "mana_regen", "base2": 1, "scaling2": 0.02, "description": "Adds mana and regen"},
		"active": {"name": "Soul Drain", "type": "chance", "base_chance": 15, "chance_scaling": 0.12, "effect": "mana_drain", "base_amount": 5, "amount_scaling": 0.1, "description": "Chance to drain enemy mana"},
		"threshold": {"name": "Incorporeal", "hp_percent": 30, "effect": "dodge_buff", "base": 25, "scaling": 0.3, "duration": 2, "description": "High dodge chance when low HP"}
	},
	"Wyvern": {
		"passive": {"name": "Aerial Agility", "effect": "attack", "base": 5, "scaling": 0.08, "effect2": "speed", "base2": 2, "scaling2": 0.04, "description": "Adds attack and speed"},
		"active": {"name": "Diving Strike", "type": "chance", "base_chance": 16, "chance_scaling": 0.14, "effect": "crit", "crit_mult": 1.7, "description": "Chance to critically strike"},
		"threshold": {"name": "Poison Tail", "hp_percent": 35, "effect": "poison", "base_damage": 8, "damage_scaling": 0.15, "duration": 3, "description": "Poisons enemy when low HP"}
	},
	"Minotaur": {
		"passive": {"name": "Brutal Strength", "effect": "attack", "base": 6, "scaling": 0.1, "description": "Adds significant attack"},
		"active": {"name": "Gore", "type": "chance", "base_chance": 18, "chance_scaling": 0.14, "effect": "bleed", "base_damage": 6, "damage_scaling": 0.12, "duration": 3, "description": "Chance to cause bleeding"},
		"threshold": {"name": "Enraged Charge", "hp_percent": 30, "effect": "attack_buff", "base": 25, "scaling": 0.35, "duration": 2, "description": "Massive attack boost when low HP"}
	},
	"Gargoyle": {
		"passive": {"name": "Stone Skin", "effect": "defense", "base": 5, "scaling": 0.08, "description": "Adds significant defense"},
		"active": {"name": "Stone Gaze", "type": "chance", "base_chance": 10, "chance_scaling": 0.08, "effect": "stun", "duration": 1, "description": "Chance to stun enemy"},
		"threshold": {"name": "Fortify", "hp_percent": 40, "effect": "defense_buff", "base": 30, "scaling": 0.4, "duration": 3, "description": "Major defense boost when low HP"}
	},
	"Harpy": {
		"passive": {"name": "Wind Rider", "effect": "speed", "base": 6, "scaling": 0.1, "description": "Adds significant speed"},
		"active": {"name": "Screech", "type": "chance", "base_chance": 12, "chance_scaling": 0.1, "effect": "enemy_miss", "description": "Chance to disorient enemy"},
		"threshold": {"name": "Desperate Flight", "hp_percent": 35, "effect": "flee_bonus", "base": 30, "scaling": 0.4, "duration": 2, "description": "Major flee bonus when low HP"}
	},
	"Shrieker": {
		"passive": {"name": "Warning Cry", "effect": "flee_bonus", "base": 8, "scaling": 0.15, "description": "Increases flee chance"},
		"active": {"name": "Deafening Shriek", "type": "chance", "base_chance": 14, "chance_scaling": 0.12, "effect": "stun", "duration": 1, "description": "Chance to stun enemy"},
		"threshold": {"name": "Alert", "hp_percent": 50, "effect": "enemy_miss", "duration": 2, "description": "Enemy misses when HP drops"}
	},

	# ===== TIER 4 COMPANIONS =====
	"Giant": {
		"passive": {"name": "Towering Might", "effect": "hp_bonus", "base": 8, "scaling": 0.15, "effect2": "attack", "base2": 4, "scaling2": 0.08, "description": "Adds HP and attack"},
		"active": {"name": "Ground Slam", "type": "chance", "base_chance": 18, "chance_scaling": 0.14, "effect": "bonus_damage", "base_damage": 15, "damage_scaling": 0.25, "effect2": "stun", "stun_chance": 20, "description": "Chance for damage and stun"},
		"threshold": {"name": "Last Stand", "hp_percent": 25, "effect": "all_buff", "base": 15, "scaling": 0.25, "duration": 3, "description": "All stats boosted when critical"}
	},
	"Dragon Wyrmling": {
		"passive": {"name": "Draconic Power", "effect": "attack", "base": 6, "scaling": 0.1, "effect2": "defense", "base2": 3, "scaling2": 0.06, "description": "Adds attack and defense"},
		"active": {"name": "Fire Breath", "type": "chance", "base_chance": 20, "chance_scaling": 0.15, "effect": "bonus_damage", "base_damage": 12, "damage_scaling": 0.2, "description": "Chance for fire damage"},
		"threshold": {"name": "Dragon's Fury", "hp_percent": 30, "effect": "attack_buff", "base": 30, "scaling": 0.4, "duration": 3, "description": "Major attack boost when low HP"}
	},
	"Demon": {
		"passive": {"name": "Infernal Might", "effect": "attack", "base": 8, "scaling": 0.14, "description": "Adds major attack damage"},
		"active": {"name": "Hellfire", "type": "chance", "base_chance": 18, "chance_scaling": 0.14, "effect": "bonus_damage", "base_damage": 14, "damage_scaling": 0.22, "description": "Chance for hellfire damage"},
		"threshold": {"name": "Demonic Pact", "hp_percent": 25, "effect": "lifesteal_buff", "base": 20, "scaling": 0.3, "duration": 3, "description": "Lifesteal when critically low"}
	},
	"Vampire": {
		"passive": {"name": "Blood Drinker", "effect": "lifesteal", "base": 3, "scaling": 0.05, "description": "Steals life with attacks"},
		"active": {"name": "Drain Life", "type": "chance", "base_chance": 20, "chance_scaling": 0.15, "effect": "lifesteal", "base_percent": 20, "percent_scaling": 0.25, "description": "Chance for major life steal"},
		"threshold": {"name": "Blood Frenzy", "hp_percent": 25, "effect": "lifesteal_buff", "base": 30, "scaling": 0.4, "duration": 3, "description": "Major lifesteal when critical"}
	},
	"Gryphon": {
		"passive": {"name": "Noble Beast", "effect": "speed", "base": 6, "scaling": 0.1, "effect2": "attack", "base2": 4, "scaling2": 0.07, "description": "Adds speed and attack"},
		"active": {"name": "Diving Talons", "type": "chance", "base_chance": 20, "chance_scaling": 0.15, "effect": "crit", "crit_mult": 1.8, "description": "Chance for critical strike"},
		"threshold": {"name": "Majestic Roar", "hp_percent": 35, "effect": "all_buff", "base": 12, "scaling": 0.2, "duration": 3, "description": "All stats boosted when low HP"}
	},
	"Chimaera": {
		"passive": {"name": "Multi-Headed", "effect": "attack", "base": 5, "scaling": 0.09, "effect2": "defense", "base2": 4, "scaling2": 0.07, "description": "Adds attack and defense"},
		"active": {"name": "Triple Strike", "type": "chance", "base_chance": 16, "chance_scaling": 0.12, "effect": "multi_hit", "hits": 3, "base_damage": 5, "damage_scaling": 0.1, "description": "Chance for triple attack"},
		"threshold": {"name": "Adaptive Defense", "hp_percent": 30, "effect": "defense_buff", "base": 25, "scaling": 0.35, "duration": 3, "description": "Major defense when low HP"}
	},
	"Succubus": {
		"passive": {"name": "Alluring Presence", "effect": "mana_regen", "base": 2, "scaling": 0.03, "effect2": "energy_regen", "base2": 2, "scaling2": 0.03, "description": "Adds mana and energy regen"},
		"active": {"name": "Charm", "type": "chance", "base_chance": 15, "chance_scaling": 0.12, "effect": "charm", "duration": 1, "description": "Chance to charm enemy"},
		"threshold": {"name": "Kiss of Death", "hp_percent": 25, "effect": "lifesteal", "base_percent": 40, "percent_scaling": 0.5, "description": "Major lifesteal when critical"}
	},

	# ===== TIER 5 COMPANIONS =====
	"Ancient Dragon": {
		"passive": {"name": "Ancient Power", "effect": "attack", "base": 10, "scaling": 0.18, "effect2": "defense", "base2": 5, "scaling2": 0.1, "description": "Adds major attack and defense"},
		"active": {"name": "Dragon Breath", "type": "chance", "base_chance": 22, "chance_scaling": 0.16, "effect": "bonus_damage", "base_damage": 20, "damage_scaling": 0.3, "description": "Chance for devastating fire"},
		"threshold": {"name": "Ancient Fury", "hp_percent": 25, "effect": "attack_buff", "base": 40, "scaling": 0.5, "duration": 3, "description": "Massive attack boost when low"}
	},
	"Demon Lord": {
		"passive": {"name": "Demonic Authority", "effect": "attack", "base": 9, "scaling": 0.16, "effect2": "hp_bonus", "base2": 5, "scaling2": 0.1, "description": "Adds attack and HP"},
		"active": {"name": "Infernal Command", "type": "chance", "base_chance": 20, "chance_scaling": 0.15, "effect": "bonus_damage", "base_damage": 18, "damage_scaling": 0.28, "effect2": "lifesteal", "lifesteal_percent": 15, "description": "Damage with lifesteal"},
		"threshold": {"name": "Unholy Pact", "hp_percent": 20, "effect": "all_buff", "base": 20, "scaling": 0.3, "duration": 3, "description": "All stats massively boosted"}
	},
	"Lich": {
		"passive": {"name": "Arcane Mastery", "effect": "mana_bonus", "base": 12, "scaling": 0.22, "effect2": "mana_regen", "base2": 2, "scaling2": 0.04, "description": "Adds major mana"},
		"active": {"name": "Death Bolt", "type": "chance", "base_chance": 18, "chance_scaling": 0.14, "effect": "bonus_damage", "base_damage": 16, "damage_scaling": 0.25, "effect2": "mana_drain", "drain_amount": 10, "description": "Damage and mana drain"},
		"threshold": {"name": "Phylactery Shield", "hp_percent": 20, "effect": "absorb", "base": 20, "scaling": 0.35, "duration": 3, "description": "Major damage absorption"}
	},
	"Titan": {
		"passive": {"name": "Titanic Endurance", "effect": "hp_bonus", "base": 12, "scaling": 0.25, "effect2": "defense", "base2": 6, "scaling2": 0.12, "description": "Adds major HP and defense"},
		"active": {"name": "Titan's Wrath", "type": "chance", "base_chance": 20, "chance_scaling": 0.14, "effect": "bonus_damage", "base_damage": 22, "damage_scaling": 0.32, "description": "Chance for massive damage"},
		"threshold": {"name": "Unyielding", "hp_percent": 25, "effect": "defense_buff", "base": 50, "scaling": 0.6, "duration": 3, "description": "Massive defense when low HP"}
	},
	"Balrog": {
		"passive": {"name": "Flame Aura", "effect": "attack", "base": 10, "scaling": 0.18, "effect2": "crit_chance", "base2": 2, "scaling2": 0.04, "description": "Adds attack and crit chance"},
		"active": {"name": "Flame Whip", "type": "chance", "base_chance": 22, "chance_scaling": 0.16, "effect": "bonus_damage", "base_damage": 18, "damage_scaling": 0.28, "effect2": "bleed", "bleed_damage": 8, "description": "Fire damage with bleed"},
		"threshold": {"name": "Infernal Rage", "hp_percent": 20, "effect": "attack_buff", "base": 45, "scaling": 0.55, "duration": 3, "description": "Massive attack boost"}
	},
	"Cerberus": {
		"passive": {"name": "Three-Headed Guard", "effect": "attack", "base": 8, "scaling": 0.14, "effect2": "speed", "base2": 5, "scaling2": 0.1, "description": "Adds attack and speed"},
		"active": {"name": "Triple Bite", "type": "chance", "base_chance": 24, "chance_scaling": 0.18, "effect": "multi_hit", "hits": 3, "base_damage": 8, "damage_scaling": 0.14, "description": "Three rapid bites"},
		"threshold": {"name": "Hellhound Fury", "hp_percent": 25, "effect": "attack_buff", "base": 35, "scaling": 0.45, "effect2": "speed_buff", "base2": 20, "scaling2": 0.25, "duration": 3, "description": "Attack and speed boost"}
	},
	"Jabberwock": {
		"passive": {"name": "Chaotic Nature", "effect": "attack", "base": 9, "scaling": 0.16, "effect2": "hp_regen", "base2": 2, "scaling2": 0.03, "description": "Adds attack and regen"},
		"active": {"name": "Vorpal Strike", "type": "chance", "base_chance": 18, "chance_scaling": 0.14, "effect": "crit", "crit_mult": 2.0, "description": "Chance for devastating crit"},
		"threshold": {"name": "Reality Warp", "hp_percent": 25, "effect": "dodge_buff", "base": 35, "scaling": 0.4, "duration": 3, "description": "High dodge when low HP"}
	},

	# ===== TIER 6 COMPANIONS =====
	"Elemental": {
		"passive": {"name": "Elemental Core", "effect": "attack", "base": 10, "scaling": 0.18, "effect2": "defense", "base2": 8, "scaling2": 0.15, "description": "Adds attack and defense"},
		"active": {"name": "Elemental Surge", "type": "chance", "base_chance": 22, "chance_scaling": 0.16, "effect": "bonus_damage", "base_damage": 22, "damage_scaling": 0.32, "description": "Chance for elemental burst"},
		"threshold": {"name": "Elemental Shield", "hp_percent": 25, "effect": "absorb", "base": 25, "scaling": 0.4, "duration": 3, "description": "Major damage absorption"}
	},
	"Iron Golem": {
		"passive": {"name": "Ironclad", "effect": "defense", "base": 12, "scaling": 0.22, "effect2": "hp_bonus", "base2": 8, "scaling2": 0.15, "description": "Adds major defense and HP"},
		"active": {"name": "Iron Fist", "type": "chance", "base_chance": 18, "chance_scaling": 0.14, "effect": "bonus_damage", "base_damage": 20, "damage_scaling": 0.3, "effect2": "stun", "stun_chance": 25, "description": "Damage with stun chance"},
		"threshold": {"name": "Steel Fortress", "hp_percent": 20, "effect": "defense_buff", "base": 60, "scaling": 0.7, "duration": 3, "description": "Massive defense boost"}
	},
	"Sphinx": {
		"passive": {"name": "Ancient Wisdom", "effect": "mana_bonus", "base": 10, "scaling": 0.2, "effect2": "wisdom_bonus", "base2": 4, "scaling2": 0.08, "description": "Adds mana and wisdom"},
		"active": {"name": "Riddle", "type": "chance", "base_chance": 15, "chance_scaling": 0.12, "effect": "charm", "duration": 2, "description": "Chance to confuse enemy"},
		"threshold": {"name": "Ancient Knowledge", "hp_percent": 25, "effect": "mana_restore", "base": 30, "scaling": 0.5, "description": "Major mana restore"}
	},
	"Hydra": {
		"passive": {"name": "Multi-Headed", "effect": "hp_regen", "base": 4, "scaling": 0.07, "effect2": "attack", "base2": 8, "scaling2": 0.15, "description": "Adds regen and attack"},
		"active": {"name": "Multi-Strike", "type": "chance", "base_chance": 25, "chance_scaling": 0.18, "effect": "multi_hit", "hits": 4, "base_damage": 6, "damage_scaling": 0.12, "description": "Four-headed assault"},
		"threshold": {"name": "Head Regrowth", "hp_percent": 20, "effect": "heal", "base": 25, "scaling": 0.4, "description": "Major heal when critical"}
	},
	"Phoenix": {
		"passive": {"name": "Eternal Flame", "effect": "hp_regen", "base": 5, "scaling": 0.08, "effect2": "attack", "base2": 6, "scaling2": 0.12, "description": "Adds regen and attack"},
		"active": {"name": "Solar Flare", "type": "chance", "base_chance": 20, "chance_scaling": 0.15, "effect": "bonus_damage", "base_damage": 24, "damage_scaling": 0.35, "description": "Chance for solar damage"},
		"threshold": {"name": "Rebirth", "hp_percent": 15, "effect": "full_heal", "cooldown": true, "description": "Full heal once when near death"}
	},
	"Nazgul": {
		"passive": {"name": "Shadow Lord", "effect": "attack", "base": 12, "scaling": 0.2, "effect2": "flee_bonus", "base2": 12, "scaling2": 0.22, "description": "Adds attack and flee"},
		"active": {"name": "Black Breath", "type": "chance", "base_chance": 18, "chance_scaling": 0.14, "effect": "weakness", "base_reduction": 15, "reduction_scaling": 0.2, "duration": 3, "description": "Weakens enemy attacks"},
		"threshold": {"name": "Morgul Blade", "hp_percent": 20, "effect": "bonus_damage", "base_damage": 40, "damage_scaling": 0.5, "effect2": "poison", "poison_damage": 15, "description": "Devastating poison attack"}
	},

	# ===== TIER 7 COMPANIONS =====
	"Void Walker": {
		"passive": {"name": "Void Touched", "effect": "attack", "base": 14, "scaling": 0.25, "effect2": "speed", "base2": 8, "scaling2": 0.15, "effect3": "defense", "base3": 6, "scaling3": 0.12, "description": "Adds attack, speed, defense"},
		"active": {"name": "Phase Strike", "type": "chance", "base_chance": 25, "chance_scaling": 0.18, "effect": "crit", "crit_mult": 2.2, "effect2": "lifesteal", "lifesteal_percent": 20, "description": "Critical with lifesteal"},
		"threshold": {"name": "Dimensional Rift", "hp_percent": 20, "effect": "dodge_buff", "base": 50, "scaling": 0.6, "duration": 3, "description": "Massive dodge boost"}
	},
	"World Serpent": {
		"passive": {"name": "Primordial Might", "effect": "attack", "base": 16, "scaling": 0.28, "effect2": "hp_bonus", "base2": 12, "scaling2": 0.22, "description": "Massive attack and HP"},
		"active": {"name": "Coil Crush", "type": "chance", "base_chance": 22, "chance_scaling": 0.16, "effect": "bonus_damage", "base_damage": 30, "damage_scaling": 0.45, "effect2": "stun", "stun_chance": 30, "description": "Crushing damage with stun"},
		"threshold": {"name": "Ouroboros", "hp_percent": 15, "effect": "heal", "base": 35, "scaling": 0.5, "effect2": "attack_buff", "attack_base": 30, "attack_scaling": 0.4, "duration": 3, "description": "Heals and buffs attack"}
	},
	"Elder Lich": {
		"passive": {"name": "Supreme Necromancy", "effect": "mana_bonus", "base": 18, "scaling": 0.35, "effect2": "mana_regen", "base2": 4, "scaling2": 0.07, "effect3": "attack", "base3": 10, "scaling3": 0.18, "description": "Major mana and attack"},
		"active": {"name": "Soul Harvest", "type": "chance", "base_chance": 22, "chance_scaling": 0.16, "effect": "bonus_damage", "base_damage": 28, "damage_scaling": 0.4, "effect2": "heal", "heal_percent": 30, "description": "Damage and self-heal"},
		"threshold": {"name": "Lich's Phylactery", "hp_percent": 10, "effect": "revive", "revive_percent": 50, "cooldown": true, "description": "Revive at 50% HP once"}
	},
	"Primordial Dragon": {
		"passive": {"name": "Primordial Flame", "effect": "attack", "base": 18, "scaling": 0.32, "effect2": "defense", "base2": 10, "scaling2": 0.18, "effect3": "hp_bonus", "base3": 8, "scaling3": 0.15, "description": "Major all stats"},
		"active": {"name": "Primordial Breath", "type": "chance", "base_chance": 25, "chance_scaling": 0.18, "effect": "bonus_damage", "base_damage": 35, "damage_scaling": 0.5, "description": "Devastating breath attack"},
		"threshold": {"name": "Time Warp", "hp_percent": 15, "effect": "all_buff", "base": 30, "scaling": 0.45, "effect2": "heal", "heal_percent": 25, "duration": 3, "description": "All stats and heal"}
	},

	# ===== TIER 8 COMPANIONS =====
	"Cosmic Horror": {
		"passive": {"name": "Eldritch Presence", "effect": "attack", "base": 18, "scaling": 0.32, "effect2": "hp_bonus", "base2": 15, "scaling2": 0.28, "effect3": "defense", "base3": 10, "scaling3": 0.18, "description": "Major all defensive stats"},
		"active": {"name": "Madness Gaze", "type": "chance", "base_chance": 22, "chance_scaling": 0.16, "effect": "charm", "duration": 2, "effect2": "bonus_damage", "base_damage": 25, "damage_scaling": 0.38, "description": "Charm and damage"},
		"threshold": {"name": "Reality Shatter", "hp_percent": 15, "effect": "bonus_damage", "base_damage": 60, "damage_scaling": 0.8, "effect2": "stun", "duration": 2, "description": "Massive damage and stun"}
	},
	"Time Weaver": {
		"passive": {"name": "Temporal Mastery", "effect": "speed", "base": 18, "scaling": 0.32, "effect2": "attack", "base2": 12, "scaling2": 0.22, "effect3": "crit_chance", "base3": 4, "scaling3": 0.08, "description": "Speed, attack, crit"},
		"active": {"name": "Time Stop", "type": "chance", "base_chance": 18, "chance_scaling": 0.14, "effect": "stun", "duration": 2, "effect2": "bonus_attack", "attacks": 2, "description": "Stun and double attack"},
		"threshold": {"name": "Temporal Rewind", "hp_percent": 10, "effect": "full_heal", "effect2": "reset_cooldowns", "cooldown": true, "description": "Full heal and reset"}
	},
	"Death Incarnate": {
		"passive": {"name": "Death's Touch", "effect": "attack", "base": 20, "scaling": 0.35, "effect2": "lifesteal", "base2": 5, "scaling2": 0.08, "description": "Major attack and lifesteal"},
		"active": {"name": "Reaping Strike", "type": "chance", "base_chance": 25, "chance_scaling": 0.18, "effect": "execute", "execute_threshold": 20, "threshold_scaling": 0.1, "description": "Executes low HP enemies"},
		"threshold": {"name": "Death's Embrace", "hp_percent": 10, "effect": "lifesteal_buff", "base": 50, "scaling": 0.7, "duration": 5, "description": "Massive lifesteal"}
	},

	# ===== TIER 9 COMPANIONS =====
	"Avatar of Chaos": {
		"passive": {"name": "Chaos Incarnate", "effect": "attack", "base": 22, "scaling": 0.4, "effect2": "crit_chance", "base2": 6, "scaling2": 0.12, "effect3": "hp_bonus", "base3": 12, "scaling3": 0.22, "description": "Major attack, crit, HP"},
		"active": {"name": "Chaos Storm", "type": "chance", "base_chance": 28, "chance_scaling": 0.2, "effect": "multi_hit", "hits": 5, "base_damage": 12, "damage_scaling": 0.2, "effect2": "random_debuff", "description": "5 hits with random effects"},
		"threshold": {"name": "Entropy Wave", "hp_percent": 10, "effect": "bonus_damage", "base_damage": 100, "damage_scaling": 1.2, "effect2": "all_buff", "buff_base": 40, "buff_scaling": 0.5, "duration": 5, "description": "Devastating damage and buffs"}
	},
	"The Nameless One": {
		"passive": {"name": "Beyond Names", "effect": "attack", "base": 20, "scaling": 0.36, "effect2": "defense", "base2": 15, "scaling2": 0.28, "effect3": "speed", "base3": 10, "scaling3": 0.18, "description": "All stats massively boosted"},
		"active": {"name": "Oblivion", "type": "chance", "base_chance": 25, "chance_scaling": 0.18, "effect": "bonus_damage", "base_damage": 40, "damage_scaling": 0.6, "effect2": "weakness", "weakness_base": 25, "weakness_scaling": 0.3, "description": "Damage and weaken enemy"},
		"threshold": {"name": "Unmaking", "hp_percent": 10, "effect": "execute", "execute_threshold": 30, "threshold_scaling": 0.15, "effect2": "heal", "heal_percent": 40, "description": "Execute and heal"}
	},
	"God Slayer": {
		"passive": {"name": "Divine Bane", "effect": "attack", "base": 25, "scaling": 0.45, "effect2": "crit_damage", "base2": 12, "scaling2": 0.22, "description": "Massive attack and crit damage"},
		"active": {"name": "Godslayer Strike", "type": "chance", "base_chance": 30, "chance_scaling": 0.2, "effect": "crit", "crit_mult": 3.0, "description": "Devastating critical strike"},
		"threshold": {"name": "Deicide", "hp_percent": 10, "effect": "attack_buff", "base": 80, "scaling": 1.0, "effect2": "crit_buff", "crit_base": 50, "crit_scaling": 0.6, "duration": 5, "description": "Massive offensive buffs"}
	},
	"Entropy": {
		"passive": {"name": "End of All", "effect": "attack", "base": 22, "scaling": 0.4, "effect2": "hp_regen", "base2": 5, "scaling2": 0.08, "effect3": "lifesteal", "base3": 4, "scaling3": 0.06, "description": "Attack, regen, lifesteal"},
		"active": {"name": "Decay", "type": "chance", "base_chance": 25, "chance_scaling": 0.18, "effect": "poison", "base_damage": 20, "damage_scaling": 0.35, "duration": 5, "effect2": "weakness", "weakness_base": 20, "description": "Strong poison and weaken"},
		"threshold": {"name": "Heat Death", "hp_percent": 5, "effect": "full_heal", "effect2": "all_buff", "buff_base": 50, "buff_scaling": 0.6, "duration": 10, "cooldown": true, "description": "Full heal and massive buffs"}
	}
}

# Legacy tier-based abilities (kept for backwards compatibility, used as fallback)
const COMPANION_ABILITIES = {
	1: {10: {"name": "Encouraging Presence", "type": "passive", "effect": "attack", "value": 2}, 25: {"name": "Distraction", "type": "chance", "chance": 15, "effect": "enemy_miss"}, 50: {"name": "Protective Instinct", "type": "threshold", "hp_percent": 50, "effect": "defense_buff", "value": 10, "duration": 3}},
	2: {10: {"name": "Battle Focus", "type": "passive", "effect": "attack", "value": 3}, 25: {"name": "Harrying Strike", "type": "chance", "chance": 18, "effect": "bonus_damage", "value": 12}, 50: {"name": "Guardian Shield", "type": "threshold", "hp_percent": 50, "effect": "defense_buff", "value": 12, "duration": 3}},
	3: {10: {"name": "Predator's Eye", "type": "passive", "effect": "attack", "value": 3, "effect2": "defense", "value2": 2}, 25: {"name": "Savage Bite", "type": "chance", "chance": 20, "effect": "bonus_damage", "value": 15}, 50: {"name": "Emergency Heal", "type": "threshold", "hp_percent": 50, "effect": "heal", "value": 10}},
	4: {10: {"name": "Primal Fury", "type": "passive", "effect": "attack", "value": 4, "effect2": "speed", "value2": 3}, 25: {"name": "Vicious Assault", "type": "chance", "chance": 20, "effect": "bonus_damage", "value": 18}, 50: {"name": "Life Bond", "type": "threshold", "hp_percent": 40, "effect": "heal", "value": 12}},
	5: {10: {"name": "Battle Synergy", "type": "passive", "effect": "attack", "value": 4, "effect2": "defense", "value2": 3}, 25: {"name": "Devastating Strike", "type": "chance", "chance": 22, "effect": "bonus_damage", "value": 22, "effect2": "stun", "chance2": 10}, 50: {"name": "Desperate Recovery", "type": "threshold", "hp_percent": 35, "effect": "heal", "value": 15}},
	6: {10: {"name": "Elemental Fury", "type": "passive", "effect": "attack", "value": 5, "effect2": "defense", "value2": 4}, 25: {"name": "Elemental Burst", "type": "chance", "chance": 22, "effect": "bonus_damage", "value": 25}, 50: {"name": "Phoenix Gift", "type": "threshold", "hp_percent": 30, "effect": "heal", "value": 18}},
	7: {10: {"name": "Void Resonance", "type": "passive", "effect": "attack", "value": 6, "effect2": "defense", "value2": 4, "effect3": "speed", "value3": 3}, 25: {"name": "Void Strike", "type": "chance", "chance": 23, "effect": "bonus_damage", "value": 30, "effect2": "lifesteal", "value2": 15}, 50: {"name": "Elder's Blessing", "type": "threshold", "hp_percent": 30, "effect": "heal", "value": 22}},
	8: {10: {"name": "Cosmic Alignment", "type": "passive", "effect": "attack", "value": 7, "effect2": "defense", "value2": 5, "effect3": "crit_chance", "value3": 3}, 25: {"name": "Time Rend", "type": "chance", "chance": 25, "effect": "bonus_damage", "value": 35, "effect2": "stun", "chance2": 20}, 50: {"name": "Death's Reprieve", "type": "threshold", "hp_percent": 25, "effect": "heal", "value": 30}},
	9: {10: {"name": "Divine Presence", "type": "passive", "effect": "attack", "value": 10, "effect2": "defense", "value2": 6, "effect3": "speed", "value3": 5}, 25: {"name": "Godslayer's Wrath", "type": "chance", "chance": 25, "effect": "bonus_damage", "value": 50, "effect2": "lifesteal", "value2": 25}, 50: {"name": "Immortal's Gift", "type": "threshold", "hp_percent": 20, "effect": "full_heal"}}
}

func get_companion_ability(tier: int, level_threshold: int) -> Dictionary:
	"""Legacy function - Get a companion ability by tier and level threshold (10, 25, or 50).
	Kept for backwards compatibility. Use get_monster_companion_abilities() for new code."""
	if not COMPANION_ABILITIES.has(tier):
		return {}
	var tier_abilities = COMPANION_ABILITIES[tier]
	if not tier_abilities.has(level_threshold):
		return {}
	return tier_abilities[level_threshold].duplicate()

func get_all_companion_abilities(tier: int, companion_level: int) -> Array:
	"""Legacy function - Get all unlocked abilities for a companion based on tier and level.
	Kept for backwards compatibility. Use get_monster_companion_abilities() for new code."""
	var abilities = []
	if not COMPANION_ABILITIES.has(tier):
		return abilities

	var tier_abilities = COMPANION_ABILITIES[tier]
	if companion_level >= 10 and tier_abilities.has(10):
		abilities.append(tier_abilities[10].duplicate())
	if companion_level >= 25 and tier_abilities.has(25):
		abilities.append(tier_abilities[25].duplicate())
	if companion_level >= 50 and tier_abilities.has(50):
		abilities.append(tier_abilities[50].duplicate())

	return abilities

# ===== NEW MONSTER-SPECIFIC COMPANION ABILITY SYSTEM =====

func get_monster_companion_abilities(monster_type: String, companion_level: int, variant_multiplier: float = 1.0, sub_tier: int = 1) -> Dictionary:
	"""Get all abilities for a companion based on monster type and level.
	Returns dict with 'passive', 'active', 'threshold' keys, each containing scaled ability data.
	variant_multiplier: Applies to base values for rarer variants (from VARIANT_STAT_MULTIPLIERS).
	sub_tier: Dungeon sub-tier multiplier applied on top of variant mult."""

	var result = {"passive": {}, "active": {}, "threshold": {}}

	# Combine variant and sub-tier multipliers
	var effective_mult = variant_multiplier * COMPANION_SUB_TIER_ABILITY_MULT.get(sub_tier, 1.0)

	# Check for monster-specific abilities
	if COMPANION_MONSTER_ABILITIES.has(monster_type):
		var monster_abilities = COMPANION_MONSTER_ABILITIES[monster_type]

		# Scale passive ability
		if monster_abilities.has("passive"):
			result.passive = _scale_companion_ability(monster_abilities.passive, companion_level, effective_mult)

		# Scale active ability (unlocks at level 5)
		if monster_abilities.has("active") and companion_level >= 5:
			result.active = _scale_companion_ability(monster_abilities.active, companion_level, effective_mult)

		# Scale threshold ability (unlocks at level 15)
		if monster_abilities.has("threshold") and companion_level >= 15:
			result.threshold = _scale_companion_ability(monster_abilities.threshold, companion_level, effective_mult)
	else:
		# Fallback to tier-based abilities for unknown monster types
		var companion_data = COMPANION_DATA.get(monster_type, {})
		var tier = companion_data.get("tier", 1)
		var tier_abilities = get_all_companion_abilities(tier, companion_level)
		if tier_abilities.size() >= 1:
			result.passive = tier_abilities[0]
		if tier_abilities.size() >= 2:
			result.active = tier_abilities[1]
		if tier_abilities.size() >= 3:
			result.threshold = tier_abilities[2]

	return result

func _scale_companion_ability(ability_template: Dictionary, companion_level: int, variant_mult: float) -> Dictionary:
	"""Scale an ability's values based on companion level and variant multiplier."""
	var scaled = ability_template.duplicate(true)

	# Scale base values with level
	if scaled.has("base") and scaled.has("scaling"):
		var base_value = scaled.base * variant_mult
		scaled["value"] = int(base_value + (scaled.scaling * companion_level * variant_mult))

	# Scale secondary effects
	if scaled.has("base2") and scaled.has("scaling2"):
		var base_value2 = scaled.base2 * variant_mult
		scaled["value2"] = int(base_value2 + (scaled.scaling2 * companion_level * variant_mult))

	# Scale tertiary effects
	if scaled.has("base3") and scaled.has("scaling3"):
		var base_value3 = scaled.base3 * variant_mult
		scaled["value3"] = int(base_value3 + (scaled.scaling3 * companion_level * variant_mult))

	# Scale damage values
	if scaled.has("base_damage") and scaled.has("damage_scaling"):
		var base_dmg = scaled.base_damage * variant_mult
		scaled["damage"] = int(base_dmg + (scaled.damage_scaling * companion_level * variant_mult))

	# Scale chance values
	if scaled.has("base_chance") and scaled.has("chance_scaling"):
		var base_chance = scaled.base_chance * variant_mult
		scaled["chance"] = mini(int(base_chance + (scaled.chance_scaling * companion_level)), 80)  # Cap at 80%

	# Scale percentage values (lifesteal, etc)
	if scaled.has("base_percent") and scaled.has("percent_scaling"):
		var base_pct = scaled.base_percent * variant_mult
		scaled["percent"] = int(base_pct + (scaled.percent_scaling * companion_level * variant_mult))

	# Scale custom-named secondary bases used in threshold effect2 entries
	if scaled.has("attack_base") and scaled.has("attack_scaling"):
		var base_val = scaled.attack_base * variant_mult
		scaled["value2"] = int(base_val + (scaled.attack_scaling * companion_level * variant_mult))
	if scaled.has("crit_base") and scaled.has("crit_scaling"):
		var base_val = scaled.crit_base * variant_mult
		scaled["value2"] = int(base_val + (scaled.crit_scaling * companion_level * variant_mult))
	if scaled.has("buff_base") and scaled.has("buff_scaling"):
		var base_val = scaled.buff_base * variant_mult
		scaled["value2"] = int(base_val + (scaled.buff_scaling * companion_level * variant_mult))
	if scaled.has("base_reduction") and scaled.has("reduction_scaling"):
		var base_val = scaled.base_reduction * variant_mult
		scaled["value"] = int(base_val + (scaled.reduction_scaling * companion_level * variant_mult))
	if scaled.has("weakness_base"):
		var base_val = scaled.weakness_base * variant_mult
		if scaled.has("weakness_scaling"):
			scaled["weakness_value"] = int(base_val + (scaled.weakness_scaling * companion_level * variant_mult))
		else:
			scaled["weakness_value"] = int(base_val)

	return scaled

func get_companion_passive_bonuses(monster_type: String, companion_level: int, variant_multiplier: float = 1.0) -> Dictionary:
	"""Get the passive stat bonuses from a companion's passive ability.
	Returns dict like {"attack": 5, "defense": 3} ready to apply to character."""
	var abilities = get_monster_companion_abilities(monster_type, companion_level, variant_multiplier)
	var bonuses = {}

	if abilities.passive.is_empty():
		return bonuses

	var passive = abilities.passive

	# Map effect names to bonus keys
	if passive.has("effect") and passive.has("value"):
		bonuses[passive.effect] = passive.value
	if passive.has("effect2") and passive.has("value2"):
		bonuses[passive.effect2] = passive.value2
	if passive.has("effect3") and passive.has("value3"):
		bonuses[passive.effect3] = passive.value3

	return bonuses

# Hatching steps scale by tier (higher tier = more steps)
const EGG_HATCH_STEPS_BY_TIER = {
	1: 50,    # Tier 1: 50 steps
	2: 75,    # Tier 2: 75 steps
	3: 100,   # Tier 3: 100 steps
	4: 150,   # Tier 4: 150 steps
	5: 200,   # Tier 5: 200 steps
	6: 300,   # Tier 6: 300 steps
	7: 400,   # Tier 7: 400 steps
	8: 500,   # Tier 8: 500 steps
	9: 750    # Tier 9: 750 steps
}

# Sub-tier stat multiplier for companion bonuses and combat damage
# Sub-tiers 1-8 from dungeons, 9 reserved for future fusion system
const COMPANION_SUB_TIER_MULTIPLIERS = {
	1: 1.0, 2: 1.1, 3: 1.2, 4: 1.3,
	5: 1.4, 6: 1.5, 7: 1.6, 8: 1.7,
	9: 2.0  # Fusion-only (Phase 4)
}

# Sub-tier ability enhancement multiplier (applied on top of variant mult)
const COMPANION_SUB_TIER_ABILITY_MULT = {
	1: 1.0, 2: 1.05, 3: 1.10, 4: 1.15,
	5: 1.20, 6: 1.30, 7: 1.40, 8: 1.50,
	9: 1.75  # Fusion-only
}

# Companion eggs are now DUNGEON-EXCLUSIVE
# All tiers set to 0 - eggs only drop from dungeon treasure chests
const EGG_DROP_CHANCE_BY_TIER = {
	1: 0,     # All eggs from dungeons only
	2: 0,
	3: 0,
	4: 0,
	5: 0,
	6: 0,
	7: 0,
	8: 0,
	9: 0
}

func get_companion_data(monster_name: String) -> Dictionary:
	"""Get companion data for a monster. Returns empty dict if none."""
	return COMPANION_DATA.get(monster_name, {})

func get_egg_for_monster(monster_name: String, pre_rolled_variant: Dictionary = {}, sub_tier: int = 1) -> Dictionary:
	"""Generate an egg dictionary for a given monster type.
	If pre_rolled_variant is provided, uses that variant. Otherwise rolls a new one.
	Variant is determined at egg creation and affects egg display and hatch times.
	sub_tier: Dungeon sub-tier (1-8) that affects companion power when hatched."""
	var companion = COMPANION_DATA.get(monster_name, {})
	if companion.is_empty():
		return {}

	var tier = companion.get("tier", 1)
	var companion_name = companion.get("companion_name", monster_name + " Companion")

	# Roll variant if not provided (variant determines egg appearance and final companion)
	var variant = pre_rolled_variant
	if variant.is_empty():
		variant = _roll_egg_variant()

	# Calculate hatch steps based on tier AND variant rarity
	var base_hatch_steps = EGG_HATCH_STEPS_BY_TIER.get(tier, 100)
	var variant_rarity = variant.get("rarity", 10)
	# Rarer variants (lower rarity number) take longer to hatch
	# Rarity 15 (common) = 1.0x, Rarity 1 (ultra rare) = 2.5x
	var rarity_multiplier = 1.0 + (15 - variant_rarity) * 0.1
	var hatch_steps = int(base_hatch_steps * rarity_multiplier)

	return {
		"id": "egg_" + monster_name.to_lower().replace(" ", "_") + "_" + str(randi()),
		"monster_type": monster_name,
		"companion_name": companion_name,
		"name": companion_name + " Egg",
		"tier": tier,
		"sub_tier": sub_tier,
		"hatch_steps": hatch_steps,
		"bonuses": companion.get("bonuses", {}).duplicate(),
		# Variant info for display and hatching
		"variant": variant.get("name", "MISSING_VARIANT"),
		"variant_color": variant.get("color", "#FF00FF"),  # Hot pink = obvious error
		"variant_color2": variant.get("color2", ""),
		"variant_pattern": variant.get("pattern", "solid"),
		"variant_rarity": variant_rarity
	}

func create_fusion_companion(monster_name: String, new_sub_tier: int, inherited_variant: Dictionary = {}) -> Dictionary:
	"""Create a companion directly from fusion (not an egg).
	Uses the egg variant system for proper variant rolling.
	inherited_variant: If all inputs share a variant, pass it to inherit."""
	var companion_data = COMPANION_DATA.get(monster_name, {})
	if companion_data.is_empty():
		return {}

	# Roll or inherit variant
	var variant = inherited_variant
	if variant.is_empty():
		variant = _roll_egg_variant()

	return {
		"id": "fused_" + monster_name.to_lower().replace(" ", "_") + "_" + str(randi()) + "_" + str(int(Time.get_unix_time_from_system())),
		"monster_type": monster_name,
		"name": companion_data.get("companion_name", monster_name + " Companion"),
		"tier": companion_data.get("tier", 1),
		"sub_tier": new_sub_tier,
		"bonuses": companion_data.get("bonuses", {}).duplicate(),
		"level": 1,
		"xp": 0,
		"battles_fought": 0,
		"variant": variant.get("name", "MISSING_VARIANT"),
		"variant_color": variant.get("color", "#FF00FF"),
		"variant_color2": variant.get("color2", ""),
		"variant_pattern": variant.get("pattern", "solid"),
		"obtained_at": int(Time.get_unix_time_from_system()),
	}

# Egg variant rolling - this is the SINGLE SOURCE OF TRUTH for all companion variants
# Special variants give stat bonuses: Shiny/Radiant/etc +10%, Spectral/etc +25%, Prismatic/etc +50%
const EGG_VARIANTS = [
	# === COMMON SOLID COLORS (rarity 8-10) ===
	# Rarity 10 - Most common tier (8 colors for variety)
	{"name": "Crimson", "color": "#DC143C", "pattern": "solid", "rarity": 10},
	{"name": "Azure", "color": "#007FFF", "pattern": "solid", "rarity": 10},
	{"name": "Verdant", "color": "#228B22", "pattern": "solid", "rarity": 10},
	{"name": "Silver", "color": "#C0C0C0", "pattern": "solid", "rarity": 10},
	{"name": "Amber", "color": "#FFBF00", "pattern": "solid", "rarity": 10},
	{"name": "Obsidian", "color": "#0A0A0A", "pattern": "solid", "rarity": 10},
	{"name": "Scarlet", "color": "#FF2400", "pattern": "solid", "rarity": 10},
	{"name": "Cobalt", "color": "#0047AB", "pattern": "solid", "rarity": 10},
	# Rarity 8 - Second common tier
	{"name": "Golden", "color": "#FFD700", "pattern": "solid", "rarity": 8},
	{"name": "Shadow", "color": "#2F2F2F", "pattern": "solid", "rarity": 8},
	{"name": "Violet", "color": "#9400D3", "pattern": "solid", "rarity": 8},
	{"name": "Coral", "color": "#FF7F50", "pattern": "solid", "rarity": 8},
	{"name": "Teal", "color": "#008080", "pattern": "solid", "rarity": 8},
	{"name": "Rose", "color": "#FF007F", "pattern": "solid", "rarity": 8},
	{"name": "Lime", "color": "#32CD32", "pattern": "solid", "rarity": 8},
	{"name": "Copper", "color": "#B87333", "pattern": "solid", "rarity": 8},

	# === UNCOMMON SOLID COLORS (rarity 5-7) ===
	{"name": "Frost", "color": "#87CEEB", "pattern": "solid", "rarity": 6},
	{"name": "Infernal", "color": "#FF4500", "pattern": "solid", "rarity": 5},
	{"name": "Toxic", "color": "#ADFF2F", "pattern": "solid", "rarity": 5},
	{"name": "Amethyst", "color": "#9966CC", "pattern": "solid", "rarity": 5},
	{"name": "Midnight", "color": "#191970", "pattern": "solid", "rarity": 5},
	{"name": "Ivory", "color": "#FFFFF0", "pattern": "solid", "rarity": 5},
	{"name": "Rust", "color": "#B7410E", "pattern": "solid", "rarity": 5},
	{"name": "Mint", "color": "#98FF98", "pattern": "solid", "rarity": 5},

	# === GRADIENT PATTERNS - TOP TO BOTTOM (rarity 3-4) ===
	{"name": "Sunset", "color": "#FF4500", "color2": "#FFD700", "pattern": "gradient_down", "rarity": 4},
	{"name": "Ocean", "color": "#00BFFF", "color2": "#000080", "pattern": "gradient_down", "rarity": 4},
	{"name": "Forest", "color": "#228B22", "color2": "#006400", "pattern": "gradient_down", "rarity": 4},
	{"name": "Dusk", "color": "#9400D3", "color2": "#FF1493", "pattern": "gradient_down", "rarity": 4},
	{"name": "Ember", "color": "#FF0000", "color2": "#8B0000", "pattern": "gradient_down", "rarity": 4},
	{"name": "Arctic", "color": "#FFFFFF", "color2": "#87CEEB", "pattern": "gradient_down", "rarity": 4},
	{"name": "Volcanic", "color": "#FF4500", "color2": "#2F2F2F", "pattern": "gradient_down", "rarity": 3},
	{"name": "Twilight", "color": "#FF69B4", "color2": "#4B0082", "pattern": "gradient_down", "rarity": 3},

	# === GRADIENT PATTERNS - BOTTOM TO TOP (rarity 3-4) ===
	{"name": "Dawn", "color": "#FFD700", "color2": "#FF6347", "pattern": "gradient_up", "rarity": 4},
	{"name": "Depths", "color": "#000080", "color2": "#00CED1", "pattern": "gradient_up", "rarity": 4},
	{"name": "Bloom", "color": "#006400", "color2": "#90EE90", "pattern": "gradient_up", "rarity": 4},
	{"name": "Rising", "color": "#8B0000", "color2": "#FF6347", "pattern": "gradient_up", "rarity": 3},

	# === MIDDLE HIGHLIGHT PATTERNS (rarity 2-3) ===
	{"name": "Core", "color": "#2F2F2F", "color2": "#FF4500", "pattern": "middle", "rarity": 3},
	{"name": "Heart", "color": "#4B0082", "color2": "#FF1493", "pattern": "middle", "rarity": 3},
	{"name": "Soul", "color": "#000080", "color2": "#00FFFF", "pattern": "middle", "rarity": 3},
	{"name": "Nexus", "color": "#228B22", "color2": "#ADFF2F", "pattern": "middle", "rarity": 2},
	{"name": "Beacon", "color": "#2F2F2F", "color2": "#FFD700", "pattern": "middle", "rarity": 2},

	# === STRIPED PATTERNS (rarity 2-3) ===
	{"name": "Tiger", "color": "#FF8C00", "color2": "#2F2F2F", "pattern": "striped", "rarity": 3},
	{"name": "Candy", "color": "#FF69B4", "color2": "#FFFFFF", "pattern": "striped", "rarity": 3},
	{"name": "Electric", "color": "#FFFF00", "color2": "#000000", "pattern": "striped", "rarity": 3},
	{"name": "Aquatic", "color": "#00CED1", "color2": "#006994", "pattern": "striped", "rarity": 2},
	{"name": "Regal", "color": "#FFD700", "color2": "#9400D3", "pattern": "striped", "rarity": 2},
	{"name": "Haunted", "color": "#9400D3", "color2": "#2F2F2F", "pattern": "striped", "rarity": 2},

	# === EDGE/OUTLINE PATTERNS (rarity 2-3) ===
	{"name": "Outlined", "color": "#FFFFFF", "color2": "#000000", "pattern": "edges", "rarity": 3},
	{"name": "Glowing", "color": "#2F2F2F", "color2": "#00FF00", "pattern": "edges", "rarity": 3},
	{"name": "Burning", "color": "#8B0000", "color2": "#FF4500", "pattern": "edges", "rarity": 2},
	{"name": "Frozen", "color": "#FFFFFF", "color2": "#00BFFF", "pattern": "edges", "rarity": 2},
	{"name": "Toxic Glow", "color": "#2F2F2F", "color2": "#ADFF2F", "pattern": "edges", "rarity": 2},

	# === DIAGONAL PATTERNS (rarity 2-3) ===
	{"name": "Slash", "color": "#FF4500", "color2": "#FFD700", "pattern": "diagonal_down", "rarity": 3},
	{"name": "Lightning", "color": "#FFFF00", "color2": "#4B0082", "pattern": "diagonal_down", "rarity": 3},
	{"name": "Rift", "color": "#00FFFF", "color2": "#FF00FF", "pattern": "diagonal_down", "rarity": 2},
	{"name": "Shattered", "color": "#87CEEB", "color2": "#2F2F2F", "pattern": "diagonal_down", "rarity": 2},
	{"name": "Ascendant", "color": "#FFD700", "color2": "#FFFFFF", "pattern": "diagonal_up", "rarity": 3},
	{"name": "Phoenix", "color": "#FF0000", "color2": "#FFD700", "pattern": "diagonal_up", "rarity": 2},
	{"name": "Comet", "color": "#00BFFF", "color2": "#FFFFFF", "pattern": "diagonal_up", "rarity": 2},
	{"name": "Crescent", "color": "#9400D3", "color2": "#E6E6FA", "pattern": "diagonal_up", "rarity": 2},

	# === VERTICAL SPLIT PATTERNS (rarity 2-3) ===
	{"name": "Split", "color": "#FF0000", "color2": "#0000FF", "pattern": "split_v", "rarity": 3},
	{"name": "Duality", "color": "#FFFFFF", "color2": "#000000", "pattern": "split_v", "rarity": 3},
	{"name": "Twilit", "color": "#FF69B4", "color2": "#00CED1", "pattern": "split_v", "rarity": 2},
	{"name": "Balanced", "color": "#FFD700", "color2": "#9400D3", "pattern": "split_v", "rarity": 2},
	{"name": "Chimeric", "color": "#FF4500", "color2": "#228B22", "pattern": "split_v", "rarity": 2},

	# === CHECKER/RADIAL PATTERNS (rarity 2-3) ===
	{"name": "Mosaic", "color": "#FF69B4", "color2": "#00FF00", "pattern": "checker", "rarity": 3},
	{"name": "Harlequin", "color": "#FF0000", "color2": "#FFD700", "pattern": "checker", "rarity": 2},
	{"name": "Aura", "color": "#FFD700", "color2": "#4B0082", "pattern": "radial", "rarity": 3},
	{"name": "Corona", "color": "#FFFFFF", "color2": "#FF4500", "pattern": "radial", "rarity": 2},
	{"name": "Eclipse", "color": "#000000", "color2": "#FFD700", "pattern": "radial", "rarity": 2},

	# === COLUMN/STRIPE PATTERNS (rarity 2-3) ===
	{"name": "Barcode", "color": "#FFFFFF", "color2": "#000000", "pattern": "columns", "rarity": 3},
	{"name": "Zebra", "color": "#FFFFFF", "color2": "#2F2F2F", "pattern": "columns", "rarity": 3},
	{"name": "Neon Bars", "color": "#00FF00", "color2": "#FF00FF", "pattern": "columns", "rarity": 2},
	{"name": "Jailbird", "color": "#FF8C00", "color2": "#000000", "pattern": "columns", "rarity": 2},

	# === BAND PATTERNS (rarity 2-3) ===
	{"name": "Layered", "color": "#8B4513", "color2": "#D2691E", "pattern": "bands", "rarity": 3},
	{"name": "Stratified", "color": "#4682B4", "color2": "#87CEEB", "pattern": "bands", "rarity": 3},
	{"name": "Sediment", "color": "#696969", "color2": "#A9A9A9", "pattern": "bands", "rarity": 2},

	# === CORNER PATTERNS (rarity 2-3) ===
	{"name": "Framed", "color": "#FFFFFF", "color2": "#8B4513", "pattern": "corners", "rarity": 3},
	{"name": "Gilded", "color": "#2F2F2F", "color2": "#FFD700", "pattern": "corners", "rarity": 2},
	{"name": "Corrupted", "color": "#FFFFFF", "color2": "#8B0000", "pattern": "corners", "rarity": 2},

	# === CROSS/X PATTERNS (rarity 2-3) ===
	{"name": "Marked", "color": "#FFFFFF", "color2": "#FF0000", "pattern": "cross", "rarity": 3},
	{"name": "Hex", "color": "#2F2F2F", "color2": "#9400D3", "pattern": "cross", "rarity": 2},
	{"name": "Branded", "color": "#D2691E", "color2": "#FF4500", "pattern": "cross", "rarity": 2},

	# === WAVE PATTERNS (rarity 2-3) ===
	{"name": "Tidal", "color": "#006994", "color2": "#00CED1", "pattern": "wave", "rarity": 3},
	{"name": "Ripple", "color": "#4B0082", "color2": "#E6E6FA", "pattern": "wave", "rarity": 3},
	{"name": "Current", "color": "#228B22", "color2": "#90EE90", "pattern": "wave", "rarity": 2},
	{"name": "Mirage", "color": "#FF8C00", "color2": "#FFFACD", "pattern": "wave", "rarity": 2},

	# === SCATTER PATTERNS (rarity 2-3) ===
	{"name": "Speckled", "color": "#FFFFFF", "color2": "#2F2F2F", "pattern": "scatter", "rarity": 3},
	{"name": "Starry", "color": "#191970", "color2": "#FFFFFF", "pattern": "scatter", "rarity": 3},
	{"name": "Freckled", "color": "#D2691E", "color2": "#8B4513", "pattern": "scatter", "rarity": 2},
	{"name": "Glittering", "color": "#4B0082", "color2": "#FFD700", "pattern": "scatter", "rarity": 2},
	{"name": "Spotted", "color": "#FFD700", "color2": "#8B0000", "pattern": "scatter", "rarity": 2},

	# === RING PATTERNS (rarity 2-3) ===
	{"name": "Ringed", "color": "#4682B4", "color2": "#000080", "pattern": "ring", "rarity": 3},
	{"name": "Orbital", "color": "#2F2F2F", "color2": "#00FFFF", "pattern": "ring", "rarity": 2},
	{"name": "Halo", "color": "#FFFFFF", "color2": "#FFD700", "pattern": "ring", "rarity": 2},

	# === FADE PATTERNS (rarity 2-3) ===
	{"name": "Misty", "color": "#FFFFFF", "color2": "#808080", "pattern": "fade", "rarity": 3},
	{"name": "Smoky", "color": "#696969", "color2": "#2F2F2F", "pattern": "fade", "rarity": 3},
	{"name": "Dreamlike", "color": "#E6E6FA", "color2": "#FF69B4", "pattern": "fade", "rarity": 2},
	{"name": "Fading", "color": "#00BFFF", "color2": "#000080", "pattern": "fade", "rarity": 2},

	# === EPIC VARIANTS (+10% stats) (rarity 2) ===
	{"name": "Shiny", "color": "#FFFACD", "pattern": "solid", "rarity": 2},
	{"name": "Radiant", "color": "#FFD700", "color2": "#FFFFFF", "pattern": "gradient_down", "rarity": 2},
	{"name": "Blessed", "color": "#FFFFFF", "color2": "#FFD700", "pattern": "edges", "rarity": 1},
	{"name": "Starfall", "color": "#FFD700", "color2": "#4B0082", "pattern": "diagonal_down", "rarity": 1},

	# === LEGENDARY VARIANTS (+25% stats) (rarity 1) ===
	{"name": "Spectral", "color": "#E6E6FA", "color2": "#9400D3", "pattern": "gradient_up", "rarity": 1},
	{"name": "Ethereal", "color": "#E6E6FA", "color2": "#87CEEB", "pattern": "middle", "rarity": 1},
	{"name": "Celestial", "color": "#FFD700", "color2": "#FFFFFF", "pattern": "striped", "rarity": 1},
	{"name": "Bifrost", "color": "#FF0000", "color2": "#00FFFF", "pattern": "diagonal_up", "rarity": 1},

	# === MYTHIC VARIANTS (+50% stats) (rarity 1) ===
	{"name": "Prismatic", "color": "#FF69B4", "color2": "#00FFFF", "pattern": "striped", "rarity": 1},
	{"name": "Void", "color": "#4B0082", "color2": "#000000", "pattern": "gradient_down", "rarity": 1},
	{"name": "Cosmic", "color": "#FFFFFF", "color2": "#4B0082", "pattern": "diagonal_down", "rarity": 1},
	{"name": "Divine", "color": "#FFFFFF", "color2": "#FFD700", "pattern": "middle", "rarity": 1}
]

func _roll_egg_variant() -> Dictionary:
	"""Roll for a random egg variant using weighted rarity."""
	var total_weight = 0
	for variant in EGG_VARIANTS:
		total_weight += variant.rarity

	var roll = randi() % total_weight
	var current = 0
	for variant in EGG_VARIANTS:
		current += variant.rarity
		if roll < current:
			return variant.duplicate()

	return EGG_VARIANTS[0].duplicate()  # Fallback to first variant (Crimson)

func roll_egg_drop(monster_name: String, monster_tier: int) -> Dictionary:
	"""Roll for an egg drop from a defeated monster. Returns egg info if dropped."""
	var drop_chance = EGG_DROP_CHANCE_BY_TIER.get(monster_tier, 0)
	if drop_chance <= 0:
		return {}

	# Check if monster has companion data
	if not COMPANION_DATA.has(monster_name):
		return {}

	if randi() % 100 < drop_chance:
		return get_egg_for_monster(monster_name)

	return {}

func get_companion_attack_damage(companion_tier: int, player_level: int, companion_bonuses: Dictionary, companion_level: int = 1, sub_tier: int = 1) -> int:
	"""Calculate damage dealt by companion in combat.
	Damage scales with tier, player level, companion level, and sub-tier for meaningful progression
	without trivializing combat."""
	# Base damage scales with tier (T1=5, T2=10, ... T9=45)
	var tier_damage = companion_tier * 5
	# Player level adds moderate scaling (reduced from 0.5 to 0.3)
	var player_bonus = int(player_level * 0.3)
	# Companion level adds meaningful but balanced scaling
	# At max level 50, adds 25 damage - significant but not overwhelming
	var companion_bonus = int(companion_level * 0.5)
	var total = tier_damage + player_bonus + companion_bonus
	# Apply companion's attack bonus percentage
	var attack_bonus = companion_bonuses.get("attack", 0)
	total = int(total * (1.0 + float(attack_bonus) / 100.0))
	# Apply sub-tier multiplier (1.0x to 1.7x for sub-tiers 1-8)
	total = int(total * COMPANION_SUB_TIER_MULTIPLIERS.get(sub_tier, 1.0))
	return total

func estimate_companion_damage(companion_tier: int, player_level: int, companion_bonuses: Dictionary, companion_level: int, variant_mult: float = 1.0, sub_tier: int = 1) -> Dictionary:
	"""Estimate companion damage range for display purposes.
	Returns {min, max, avg} damage values."""
	var base = get_companion_attack_damage(companion_tier, player_level, companion_bonuses, companion_level, sub_tier)
	# Apply variant multiplier
	base = int(base * variant_mult)
	# Damage has 80-120% variance
	var min_dmg = max(1, int(base * 0.8))
	var max_dmg = max(1, int(base * 1.2))
	var avg_dmg = int((min_dmg + max_dmg) / 2)
	return {"min": min_dmg, "max": max_dmg, "avg": avg_dmg}

func get_all_companion_names() -> Array:
	"""Get list of all companion names for display/selection."""
	var names = []
	for monster_name in COMPANION_DATA:
		names.append(COMPANION_DATA[monster_name].companion_name)
	names.sort()
	return names

# ===== FISHING SYSTEM =====
# Fishing catches and materials for crafting

# Fishing catch tables by water type
const FISHING_CATCHES = {
	"shallow": [
		# Common catches (60%)
		{"weight": 25, "item": "small_fish", "name": "Small Fish", "type": "fish", "value": 5},
		{"weight": 20, "item": "medium_fish", "name": "Medium Fish", "type": "fish", "value": 15},
		{"weight": 15, "item": "seaweed", "name": "Seaweed", "type": "material", "value": 8},
		# Uncommon catches (25%)
		{"weight": 10, "item": "large_fish", "name": "Large Fish", "type": "fish", "value": 30},
		{"weight": 8, "item": "freshwater_pearl", "name": "Freshwater Pearl", "type": "material", "value": 50},
		{"weight": 7, "item": "river_crab", "name": "River Crab", "type": "fish", "value": 25},
		# Rare catches (12%)
		{"weight": 5, "item": "golden_fish", "name": "Golden Fish", "type": "fish", "value": 100},
		{"weight": 4, "item": "enchanted_kelp", "name": "Enchanted Kelp", "type": "material", "value": 75},
		{"weight": 3, "item": "fish_scale_armor", "name": "Fish Scale", "type": "material", "value": 40},
		# Treasure (3%)
		{"weight": 3, "item": "small_treasure_chest", "name": "Small Treasure Chest", "type": "treasure", "value": 150}
	],
	"deep": [
		# Common catches (45%)
		{"weight": 15, "item": "deep_sea_fish", "name": "Deep Sea Fish", "type": "fish", "value": 40},
		{"weight": 15, "item": "magic_kelp", "name": "Magic Kelp", "type": "material", "value": 60},
		{"weight": 15, "item": "abyssal_crab", "name": "Abyssal Crab", "type": "fish", "value": 50},
		# Uncommon catches (35%)
		{"weight": 12, "item": "giant_pearl", "name": "Giant Pearl", "type": "material", "value": 150},
		{"weight": 10, "item": "leviathan_scale", "name": "Leviathan Scale", "type": "material", "value": 200},
		{"weight": 8, "item": "rare_fish", "name": "Rare Fish", "type": "fish", "value": 100},
		{"weight": 5, "item": "prismatic_fish", "name": "Prismatic Fish", "type": "fish", "value": 250},
		# Rare catches (15%)
		{"weight": 6, "item": "sea_dragon_fang", "name": "Sea Dragon Fang", "type": "material", "value": 300},
		{"weight": 5, "item": "ancient_relic", "name": "Ancient Relic", "type": "treasure", "value": 400},
		{"weight": 4, "item": "kraken_ink", "name": "Kraken Ink", "type": "material", "value": 350},
		# Treasure (5%)
		{"weight": 5, "item": "large_treasure_chest", "name": "Large Treasure Chest", "type": "treasure", "value": 500}
	]
}

# Fishing skill XP per catch type
const FISHING_XP = {
	"small_fish": 5,
	"medium_fish": 10,
	"large_fish": 20,
	"seaweed": 5,
	"freshwater_pearl": 25,
	"river_crab": 15,
	"golden_fish": 50,
	"enchanted_kelp": 30,
	"fish_scale_armor": 20,
	"small_treasure_chest": 40,
	"deep_sea_fish": 25,
	"magic_kelp": 30,
	"abyssal_crab": 35,
	"giant_pearl": 50,
	"leviathan_scale": 60,
	"rare_fish": 45,
	"prismatic_fish": 75,
	"sea_dragon_fang": 80,
	"ancient_relic": 100,
	"kraken_ink": 70,
	"large_treasure_chest": 90
}

func roll_fishing_catch(water_type: String, fishing_skill: int) -> Dictionary:
	"""Roll for a fishing catch based on water type and skill level.
	Higher skill improves chances for rare catches."""
	var catches = FISHING_CATCHES.get(water_type, FISHING_CATCHES.get("shallow"))

	# Calculate total weight with skill bonus for rare items
	var modified_catches = []
	var total_weight = 0

	for catch in catches:
		var weight = catch.weight
		# Skill bonus: +0.5% weight to rare/treasure items per skill level
		if catch.type in ["treasure", "egg"] or catch.value >= 100:
			weight = int(weight * (1.0 + fishing_skill * 0.005))
		modified_catches.append({"catch": catch, "weight": weight})
		total_weight += weight

	# Roll
	var roll = randi() % total_weight
	var cumulative = 0

	for entry in modified_catches:
		cumulative += entry.weight
		if roll < cumulative:
			var catch = entry.catch
			return {
				"item_id": catch.item,
				"name": catch.name,
				"type": catch.type,
				"value": catch.value,
				"xp": FISHING_XP.get(catch.item, 10)
			}

	# Fallback
	var fallback = catches[0]
	return {
		"item_id": fallback.item,
		"name": fallback.name,
		"type": fallback.type,
		"value": fallback.value,
		"xp": FISHING_XP.get(fallback.item, 10)
	}

func get_fishing_wait_time(fishing_skill: int) -> float:
	"""Get wait time range for a fishing bite. Higher skill = shorter waits."""
	var base_min = 3.0  # 3 seconds minimum
	var base_max = 8.0  # 8 seconds maximum
	# Skill reduces wait time: -0.02s per skill level
	var skill_reduction = fishing_skill * 0.02
	var min_time = max(1.5, base_min - skill_reduction)
	var max_time = max(3.0, base_max - skill_reduction * 1.5)
	return randf_range(min_time, max_time)

func get_fishing_reaction_window(fishing_skill: int) -> float:
	"""Get reaction window for catching fish. Higher skill = longer window."""
	var base_window = 2.5  # 2.5 seconds base (increased for slower connections)
	# Skill adds time: +0.02s per skill level
	var skill_bonus = fishing_skill * 0.02
	return min(5.0, base_window + skill_bonus)  # Cap at 5 seconds

# ===== MINING SYSTEM =====
# Ore deposits in mountains - tiered by distance from origin

# Mining catches by tier (1-9, matching ore tiers by distance)
const MINING_CATCHES = {
	1: [  # T1: 0-50 distance
		{"weight": 40, "item": "copper_ore", "name": "Copper Ore", "type": "ore", "value": 8},
		{"weight": 25, "item": "stone", "name": "Stone", "type": "mineral", "value": 2},
		{"weight": 15, "item": "coal", "name": "Coal", "type": "mineral", "value": 5},
		{"weight": 10, "item": "rough_gem", "name": "Rough Gem", "type": "gem", "value": 25},
		{"weight": 8, "item": "healing_herb", "name": "Cave Moss", "type": "herb", "value": 10},
		{"weight": 2, "item": "small_treasure_chest", "name": "Buried Chest", "type": "treasure", "value": 100}
	],
	2: [  # T2: 50-100 distance
		{"weight": 35, "item": "iron_ore", "name": "Iron Ore", "type": "ore", "value": 15},
		{"weight": 20, "item": "copper_ore", "name": "Copper Ore", "type": "ore", "value": 8},
		{"weight": 15, "item": "coal", "name": "Coal", "type": "mineral", "value": 5},
		{"weight": 12, "item": "rough_gem", "name": "Rough Gem", "type": "gem", "value": 25},
		{"weight": 10, "item": "mana_blossom", "name": "Crystal Flower", "type": "herb", "value": 20},
		{"weight": 5, "item": "polished_gem", "name": "Polished Gem", "type": "gem", "value": 75},
		{"weight": 3, "item": "small_treasure_chest", "name": "Buried Chest", "type": "treasure", "value": 150}
	],
	3: [  # T3: 100-150 distance
		{"weight": 35, "item": "steel_ore", "name": "Steel Ore", "type": "ore", "value": 30},
		{"weight": 20, "item": "iron_ore", "name": "Iron Ore", "type": "ore", "value": 15},
		{"weight": 15, "item": "shadowleaf", "name": "Shadow Crystal", "type": "enchant", "value": 40},
		{"weight": 12, "item": "polished_gem", "name": "Polished Gem", "type": "gem", "value": 75},
		{"weight": 10, "item": "arcane_crystal", "name": "Arcane Crystal", "type": "enchant", "value": 50},
		{"weight": 5, "item": "flawless_gem", "name": "Flawless Gem", "type": "gem", "value": 150},
		{"weight": 3, "item": "large_treasure_chest", "name": "Ancient Chest", "type": "treasure", "value": 300}
	],
	4: [  # T4: 150-200 distance
		{"weight": 35, "item": "mithril_ore", "name": "Mithril Ore", "type": "ore", "value": 60},
		{"weight": 20, "item": "steel_ore", "name": "Steel Ore", "type": "ore", "value": 30},
		{"weight": 15, "item": "soul_shard", "name": "Soul Shard", "type": "enchant", "value": 80},
		{"weight": 12, "item": "flawless_gem", "name": "Flawless Gem", "type": "gem", "value": 150},
		{"weight": 10, "item": "phoenix_petal", "name": "Fire Crystal", "type": "essence", "value": 100},
		{"weight": 8, "item": "perfect_gem", "name": "Perfect Gem", "type": "gem", "value": 300}
	],
	5: [  # T5: 200-250 distance
		{"weight": 35, "item": "adamantine_ore", "name": "Adamantine Ore", "type": "ore", "value": 120},
		{"weight": 20, "item": "mithril_ore", "name": "Mithril Ore", "type": "ore", "value": 60},
		{"weight": 15, "item": "void_essence", "name": "Deep Earth Essence", "type": "enchant", "value": 150},
		{"weight": 12, "item": "perfect_gem", "name": "Perfect Gem", "type": "gem", "value": 300},
		{"weight": 10, "item": "dragon_blood", "name": "Magma Blood", "type": "essence", "value": 200},
		{"weight": 8, "item": "star_gem", "name": "Star Gem", "type": "gem", "value": 500}
	],
	6: [  # T6: 250-300 distance
		{"weight": 35, "item": "orichalcum_ore", "name": "Orichalcum Ore", "type": "ore", "value": 250},
		{"weight": 20, "item": "adamantine_ore", "name": "Adamantine Ore", "type": "ore", "value": 120},
		{"weight": 15, "item": "void_essence", "name": "Void Essence", "type": "enchant", "value": 200},
		{"weight": 12, "item": "star_gem", "name": "Star Gem", "type": "gem", "value": 500},
		{"weight": 10, "item": "essence_of_life", "name": "Primal Essence", "type": "essence", "value": 400},
		{"weight": 8, "item": "celestial_gem", "name": "Celestial Gem", "type": "gem", "value": 800}
	],
	7: [  # T7: 300-350 distance
		{"weight": 40, "item": "void_ore", "name": "Void Ore", "type": "ore", "value": 500},
		{"weight": 25, "item": "orichalcum_ore", "name": "Orichalcum Ore", "type": "ore", "value": 250},
		{"weight": 15, "item": "celestial_shard", "name": "Celestial Shard", "type": "enchant", "value": 400},
		{"weight": 10, "item": "celestial_gem", "name": "Celestial Gem", "type": "gem", "value": 800},
		{"weight": 10, "item": "primordial_spark", "name": "Primordial Spark", "type": "enchant", "value": 800}
	],
	8: [  # T8: 350-400 distance
		{"weight": 40, "item": "celestial_ore", "name": "Celestial Ore", "type": "ore", "value": 1000},
		{"weight": 25, "item": "void_ore", "name": "Void Ore", "type": "ore", "value": 500},
		{"weight": 15, "item": "primordial_spark", "name": "Primordial Spark", "type": "enchant", "value": 800},
		{"weight": 10, "item": "primordial_gem", "name": "Primordial Gem", "type": "gem", "value": 1500},
		{"weight": 10, "item": "essence_of_life", "name": "Pure Essence", "type": "essence", "value": 600}
	],
	9: [  # T9: 400+ distance
		{"weight": 40, "item": "primordial_ore", "name": "Primordial Ore", "type": "ore", "value": 2000},
		{"weight": 25, "item": "celestial_ore", "name": "Celestial Ore", "type": "ore", "value": 1000},
		{"weight": 15, "item": "primordial_spark", "name": "Primordial Spark", "type": "enchant", "value": 800},
		{"weight": 10, "item": "primordial_gem", "name": "Primordial Gem", "type": "gem", "value": 1500},
		{"weight": 10, "item": "essence_of_life", "name": "Divine Essence", "type": "essence", "value": 1000}
	]
}

# Mining XP per item
const MINING_XP = {
	"copper_ore": 10, "iron_ore": 20, "steel_ore": 35, "mithril_ore": 50,
	"adamantine_ore": 70, "orichalcum_ore": 100, "void_ore": 150, "celestial_ore": 200, "primordial_ore": 300,
	"stone": 3, "coal": 5, "rough_gem": 15, "polished_gem": 30, "flawless_gem": 50,
	"perfect_gem": 80, "star_gem": 120, "celestial_gem": 180, "primordial_gem": 250,
	"healing_herb": 5, "mana_blossom": 10, "shadowleaf": 15, "arcane_crystal": 25,
	"soul_shard": 40, "void_essence": 60, "celestial_shard": 100, "primordial_spark": 150,
	"phoenix_petal": 30, "dragon_blood": 50, "essence_of_life": 80,
	"small_treasure_chest": 50, "large_treasure_chest": 100
}

func roll_mining_catch(ore_tier: int, mining_skill: int) -> Dictionary:
	"""Roll for a mining catch based on ore tier and skill level."""
	var tier = clampi(ore_tier, 1, 9)
	var catches = MINING_CATCHES[tier]

	var modified_catches = []
	var total_weight = 0

	for catch in catches:
		var weight = catch.weight
		# Skill bonus: +0.5% weight to rare items per skill level
		if catch.type in ["treasure", "egg", "gem"] or catch.value >= 100:
			weight = int(weight * (1.0 + mining_skill * 0.005))
		modified_catches.append({"catch": catch, "weight": weight})
		total_weight += weight

	var roll = randi() % total_weight
	var cumulative = 0

	for entry in modified_catches:
		cumulative += entry.weight
		if roll < cumulative:
			var catch = entry.catch
			return {
				"item_id": catch.item,
				"name": catch.name,
				"type": catch.type,
				"value": catch.value,
				"xp": MINING_XP.get(catch.item, 10)
			}

	# Fallback
	var fallback = catches[0]
	return {
		"item_id": fallback.item,
		"name": fallback.name,
		"type": fallback.type,
		"value": fallback.value,
		"xp": MINING_XP.get(fallback.item, 10)
	}

func get_mining_wait_time(mining_skill: int) -> float:
	"""Get wait time for mining. Similar to fishing (3-8 sec base)."""
	var base_min = 3.0
	var base_max = 8.0
	var skill_reduction = mining_skill * 0.02
	var min_time = max(1.5, base_min - skill_reduction)
	var max_time = max(3.0, base_max - skill_reduction * 1.5)
	return randf_range(min_time, max_time)

func get_mining_reaction_window(mining_skill: int) -> float:
	"""Get reaction window for mining. Higher skill = longer window."""
	var base_window = 2.5  # 2.5 seconds base (increased for slower connections)
	var skill_bonus = mining_skill * 0.02
	return min(5.0, base_window + skill_bonus)  # Cap at 5 seconds

func get_mining_reactions_required(ore_tier: int) -> int:
	"""Get number of successful reactions required for this tier.
	T1-2: 1 reaction, T3-5: 2 reactions, T6+: 3 reactions"""
	if ore_tier <= 2:
		return 1
	elif ore_tier <= 5:
		return 2
	else:
		return 3

# ===== LOGGING SYSTEM =====
# Trees in forests - tiered by distance from origin

const LOGGING_CATCHES = {
	1: [  # T1: 0-60 distance
		{"weight": 40, "item": "common_wood", "name": "Common Wood", "type": "wood", "value": 6},
		{"weight": 25, "item": "bark", "name": "Bark", "type": "plant", "value": 3},
		{"weight": 15, "item": "sap", "name": "Tree Sap", "type": "plant", "value": 8},
		{"weight": 10, "item": "healing_herb", "name": "Forest Herb", "type": "herb", "value": 10},
		{"weight": 7, "item": "acorn", "name": "Golden Acorn", "type": "plant", "value": 20},
		{"weight": 3, "item": "small_treasure_chest", "name": "Tree Hollow Cache", "type": "treasure", "value": 100}
	],
	2: [  # T2: 60-120 distance
		{"weight": 40, "item": "oak_wood", "name": "Oak Wood", "type": "wood", "value": 12},
		{"weight": 20, "item": "common_wood", "name": "Common Wood", "type": "wood", "value": 6},
		{"weight": 15, "item": "sap", "name": "Amber Sap", "type": "plant", "value": 15},
		{"weight": 10, "item": "mana_blossom", "name": "Forest Blossom", "type": "herb", "value": 20},
		{"weight": 8, "item": "vigor_root", "name": "Oak Root", "type": "herb", "value": 25},
		{"weight": 7, "item": "magic_dust", "name": "Pollen Dust", "type": "enchant", "value": 30}
	],
	3: [  # T3: 120-180 distance
		{"weight": 40, "item": "ash_wood", "name": "Ash Wood", "type": "wood", "value": 25},
		{"weight": 20, "item": "oak_wood", "name": "Oak Wood", "type": "wood", "value": 12},
		{"weight": 15, "item": "shadowleaf", "name": "Shadow Leaf", "type": "herb", "value": 40},
		{"weight": 10, "item": "arcane_crystal", "name": "Crystallized Sap", "type": "enchant", "value": 50},
		{"weight": 8, "item": "phoenix_petal", "name": "Fire Blossom", "type": "herb", "value": 60},
		{"weight": 7, "item": "enchanted_resin", "name": "Enchanted Resin", "type": "enchant", "value": 75}
	],
	4: [  # T4: 180-240 distance
		{"weight": 40, "item": "ironwood", "name": "Ironwood", "type": "wood", "value": 50},
		{"weight": 20, "item": "ash_wood", "name": "Ash Wood", "type": "wood", "value": 25},
		{"weight": 15, "item": "soul_shard", "name": "Spirit Sap", "type": "enchant", "value": 80},
		{"weight": 10, "item": "dragon_blood", "name": "Blood Sap", "type": "essence", "value": 100},
		{"weight": 8, "item": "heartwood", "name": "Heartwood", "type": "wood", "value": 80},
		{"weight": 7, "item": "void_essence", "name": "Shadow Essence", "type": "enchant", "value": 120}
	],
	5: [  # T5: 240-300 distance
		{"weight": 40, "item": "darkwood", "name": "Darkwood", "type": "wood", "value": 100},
		{"weight": 20, "item": "ironwood", "name": "Ironwood", "type": "wood", "value": 50},
		{"weight": 15, "item": "void_essence", "name": "Void Sap", "type": "enchant", "value": 150},
		{"weight": 10, "item": "essence_of_life", "name": "Life Essence", "type": "essence", "value": 200},
		{"weight": 8, "item": "elderwood", "name": "Elderwood", "type": "wood", "value": 150},
		{"weight": 7, "item": "celestial_shard", "name": "Starlight Shard", "type": "enchant", "value": 300}
	],
	6: [  # T6: 300+ distance
		{"weight": 40, "item": "worldtree_branch", "name": "Worldtree Branch", "type": "wood", "value": 200},
		{"weight": 20, "item": "darkwood", "name": "Darkwood", "type": "wood", "value": 100},
		{"weight": 15, "item": "primordial_spark", "name": "Primordial Sap", "type": "enchant", "value": 400},
		{"weight": 10, "item": "essence_of_life", "name": "Divine Essence", "type": "essence", "value": 500},
		{"weight": 8, "item": "worldtree_heartwood", "name": "Worldtree Heartwood", "type": "wood", "value": 400},
		{"weight": 7, "item": "primordial_spark", "name": "Creation Spark", "type": "enchant", "value": 800}
	]
}

# Logging XP per item
const LOGGING_XP = {
	"common_wood": 10, "oak_wood": 20, "ash_wood": 35, "ironwood": 55,
	"darkwood": 80, "worldtree_branch": 150, "heartwood": 40, "elderwood": 70, "worldtree_heartwood": 200,
	"bark": 3, "sap": 8, "acorn": 12, "enchanted_resin": 30,
	"healing_herb": 5, "mana_blossom": 10, "vigor_root": 12, "shadowleaf": 20,
	"phoenix_petal": 30, "dragon_blood": 50, "essence_of_life": 80,
	"magic_dust": 10, "arcane_crystal": 25, "soul_shard": 40,
	"void_essence": 60, "celestial_shard": 100, "primordial_spark": 150,
	"small_treasure_chest": 50, "large_treasure_chest": 100
}

func roll_logging_catch(wood_tier: int, logging_skill: int) -> Dictionary:
	"""Roll for a logging catch based on wood tier and skill level."""
	var tier = clampi(wood_tier, 1, 6)
	var catches = LOGGING_CATCHES[tier]

	var modified_catches = []
	var total_weight = 0

	for catch in catches:
		var weight = catch.weight
		# Skill bonus: +0.5% weight to rare items per skill level
		if catch.type in ["treasure", "egg", "essence"] or catch.value >= 100:
			weight = int(weight * (1.0 + logging_skill * 0.005))
		modified_catches.append({"catch": catch, "weight": weight})
		total_weight += weight

	var roll = randi() % total_weight
	var cumulative = 0

	for entry in modified_catches:
		cumulative += entry.weight
		if roll < cumulative:
			var catch = entry.catch
			return {
				"item_id": catch.item,
				"name": catch.name,
				"type": catch.type,
				"value": catch.value,
				"xp": LOGGING_XP.get(catch.item, 10)
			}

	# Fallback
	var fallback = catches[0]
	return {
		"item_id": fallback.item,
		"name": fallback.name,
		"type": fallback.type,
		"value": fallback.value,
		"xp": LOGGING_XP.get(fallback.item, 10)
	}

func get_logging_wait_time(logging_skill: int) -> float:
	"""Get wait time for logging. Similar to fishing (3-8 sec base)."""
	var base_min = 3.0
	var base_max = 8.0
	var skill_reduction = logging_skill * 0.02
	var min_time = max(1.5, base_min - skill_reduction)
	var max_time = max(3.0, base_max - skill_reduction * 1.5)
	return randf_range(min_time, max_time)

func get_logging_reaction_window(logging_skill: int) -> float:
	"""Get reaction window for logging. Higher skill = longer window."""
	var base_window = 2.5  # 2.5 seconds base (increased for slower connections)
	var skill_bonus = logging_skill * 0.02
	return min(5.0, base_window + skill_bonus)  # Cap at 5 seconds

func get_logging_reactions_required(wood_tier: int) -> int:
	"""Get number of successful reactions required for this tier.
	T1-2: 1 reaction, T3-4: 2 reactions, T5+: 3 reactions"""
	if wood_tier <= 2:
		return 1
	elif wood_tier <= 4:
		return 2
	else:
		return 3

# ===== CRAFTING MATERIAL DROPS =====
# Materials drop from monsters based on their tier

# Material drops by tier (lower tiers drop more common materials)
const CRAFTING_MATERIAL_DROPS = {
	1: [  # T1 monsters
		{"weight": 40, "material": "copper_ore", "quantity": 1},
		{"weight": 30, "material": "ragged_leather", "quantity": 1},
		{"weight": 20, "material": "healing_herb", "quantity": 1},
		{"weight": 10, "material": "magic_dust", "quantity": 1}
	],
	2: [  # T2 monsters
		{"weight": 35, "material": "copper_ore", "quantity": 2},
		{"weight": 25, "material": "iron_ore", "quantity": 1},
		{"weight": 20, "material": "leather_scraps", "quantity": 1},
		{"weight": 10, "material": "mana_blossom", "quantity": 1},
		{"weight": 10, "material": "vigor_root", "quantity": 1}
	],
	3: [  # T3 monsters
		{"weight": 30, "material": "iron_ore", "quantity": 2},
		{"weight": 25, "material": "steel_ore", "quantity": 1},
		{"weight": 20, "material": "thick_leather", "quantity": 1},
		{"weight": 15, "material": "shadowleaf", "quantity": 1},
		{"weight": 10, "material": "arcane_crystal", "quantity": 1}
	],
	4: [  # T4 monsters
		{"weight": 30, "material": "steel_ore", "quantity": 2},
		{"weight": 25, "material": "mithril_ore", "quantity": 1},
		{"weight": 20, "material": "enchanted_leather", "quantity": 1},
		{"weight": 15, "material": "soul_shard", "quantity": 1},
		{"weight": 10, "material": "phoenix_petal", "quantity": 1}
	],
	5: [  # T5 monsters
		{"weight": 30, "material": "mithril_ore", "quantity": 2},
		{"weight": 25, "material": "adamantine_ore", "quantity": 1},
		{"weight": 20, "material": "dragonhide", "quantity": 1},
		{"weight": 15, "material": "phoenix_petal", "quantity": 1},
		{"weight": 10, "material": "void_essence", "quantity": 1}
	],
	6: [  # T6 monsters
		{"weight": 30, "material": "adamantine_ore", "quantity": 2},
		{"weight": 25, "material": "orichalcum_ore", "quantity": 1},
		{"weight": 20, "material": "dragon_blood", "quantity": 1},
		{"weight": 15, "material": "void_essence", "quantity": 1},
		{"weight": 10, "material": "primordial_spark", "quantity": 1}
	],
	7: [  # T7 monsters
		{"weight": 30, "material": "orichalcum_ore", "quantity": 2},
		{"weight": 25, "material": "void_ore", "quantity": 1},
		{"weight": 25, "material": "void_silk", "quantity": 1},
		{"weight": 20, "material": "essence_of_life", "quantity": 1}
	],
	8: [  # T8 monsters
		{"weight": 35, "material": "void_ore", "quantity": 2},
		{"weight": 30, "material": "celestial_ore", "quantity": 1},
		{"weight": 20, "material": "primordial_spark", "quantity": 1},
		{"weight": 15, "material": "essence_of_life", "quantity": 2}
	],
	9: [  # T9 monsters
		{"weight": 40, "material": "celestial_ore", "quantity": 2},
		{"weight": 35, "material": "primordial_ore", "quantity": 1},
		{"weight": 25, "material": "primordial_spark", "quantity": 2}
	]
}

# Base drop chance for materials by tier (percentage)
const MATERIAL_DROP_CHANCE_BY_TIER = {
	1: 25,  # 25% chance
	2: 28,
	3: 30,
	4: 32,
	5: 35,
	6: 38,
	7: 40,
	8: 45,
	9: 50   # 50% chance at T9
}

func roll_crafting_material_drop(monster_tier: int) -> Dictionary:
	"""Roll for a crafting material drop from a defeated monster."""
	# Clamp tier to valid range
	var tier = clampi(monster_tier, 1, 9)

	# Check drop chance
	var drop_chance = MATERIAL_DROP_CHANCE_BY_TIER.get(tier, 25)
	if randi() % 100 >= drop_chance:
		return {}  # No drop

	# Get drop table for this tier
	var drops = CRAFTING_MATERIAL_DROPS.get(tier, [])
	if drops.is_empty():
		return {}

	# Roll for which material
	var total_weight = 0
	for entry in drops:
		total_weight += entry.weight

	var roll = randi() % total_weight
	var cumulative = 0

	for entry in drops:
		cumulative += entry.weight
		if roll < cumulative:
			return {
				"material_id": entry.material,
				"quantity": entry.quantity
			}

	# Fallback
	return {
		"material_id": drops[0].material,
		"quantity": drops[0].quantity
	}

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

func generate_fallback_item(item_category: String, item_level: int) -> Dictionary:
	"""Generate a guaranteed fallback item for merchants when normal generation fails.
	Used to prevent empty merchant inventories."""
	var item_type: String
	var rarity = "common"

	# Determine rarity based on level (slight chance for better)
	var rarity_roll = randi() % 100
	if item_level >= 50 and rarity_roll < 15:
		rarity = "rare"
	elif item_level >= 20 and rarity_roll < 25:
		rarity = "uncommon"

	# Pick appropriate item type based on category and level
	match item_category:
		"weapon":
			if item_level <= 5:
				item_type = "weapon_rusty"
			elif item_level <= 15:
				item_type = "weapon_iron"
			elif item_level <= 30:
				item_type = "weapon_steel"
			elif item_level <= 50:
				item_type = "weapon_enchanted"
			elif item_level <= 100:
				item_type = "weapon_magical"
			else:
				item_type = "weapon_elemental"
		"armor":
			if item_level <= 5:
				item_type = "armor_leather"
			elif item_level <= 15:
				item_type = "armor_chain"
			elif item_level <= 30:
				item_type = "armor_plate"
			elif item_level <= 50:
				item_type = "armor_enchanted"
			elif item_level <= 100:
				item_type = "armor_magical"
			else:
				item_type = "armor_elemental"
		"ring":
			if item_level <= 15:
				item_type = "ring_copper"
			elif item_level <= 50:
				item_type = "ring_silver"
			elif item_level <= 100:
				item_type = "ring_gold"
			else:
				item_type = "ring_elemental"
		"potion":
			var tier = get_tier_for_level(item_level)
			var tier_name = get_tier_name(tier)
			return {
				"id": randi(),
				"type": "health_potion",
				"name": "%s Health Potion" % tier_name,
				"rarity": "common",
				"level": item_level,
				"tier": tier,
				"is_consumable": true,
				"quantity": 1,
				"value": _calculate_consumable_value(tier, "potion_minor")
			}
		_:
			item_type = "weapon_iron"

	# Generate the item using standard generation
	var drop_entry = {"item_type": item_type, "rarity": rarity}
	return _generate_item(drop_entry, item_level)

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

	# Special handling for generic "artifact" type - convert to random equipment slot
	if item_type == "artifact":
		var artifact_slots = ["weapon_artifact", "armor_artifact", "helm_artifact", "shield_artifact", "boots_artifact", "ring_artifact", "amulet_artifact"]
		item_type = artifact_slots[randi() % artifact_slots.size()]

	# Check if this is a consumable (potions, resource restorers, scrolls, tomes, etc.)
	# Consumables use TIER system, not rarity - tier is based on monster level
	var is_consumable = item_type.begins_with("potion_") or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("scroll_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_") or item_type.begins_with("elixir_") or item_type.begins_with("tome_") or item_type.begins_with("home_stone_") or item_type == "mysterious_box" or item_type == "cursed_coin"

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
		# Consumables use tier instead of level - set level to tier for display consistency
		item["level"] = tier
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
		"mana_minor": "Resource Potion",
		"mana_lesser": "Resource Potion",
		"mana_standard": "Resource Potion",
		"mana_greater": "Resource Potion",
		"mana_superior": "Resource Potion",
		"mana_master": "Resource Potion",
		"stamina_minor": "Resource Potion",
		"stamina_lesser": "Resource Potion",
		"stamina_standard": "Resource Potion",
		"stamina_greater": "Resource Potion",
		"energy_minor": "Resource Potion",
		"energy_lesser": "Resource Potion",
		"energy_standard": "Resource Potion",
		"energy_greater": "Resource Potion",
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
		# Tomes - stat
		"tome_strength": "Tome of Strength",
		"tome_constitution": "Tome of Constitution",
		"tome_dexterity": "Tome of Dexterity",
		"tome_intelligence": "Tome of Intelligence",
		"tome_wisdom": "Tome of Wisdom",
		"tome_wits": "Tome of Wits",
		# Tomes - skill enhancers
		"tome_searing_bolt": "Tome of Searing Bolt",
		"tome_efficient_bolt": "Tome of Efficient Bolt",
		"tome_greater_forcefield": "Tome of Greater Forcefield",
		"tome_meteor_mastery": "Tome of Meteor Mastery",
		"tome_brutal_strike": "Tome of Brutal Strike",
		"tome_efficient_strike": "Tome of Efficient Strike",
		"tome_greater_cleave": "Tome of Greater Cleave",
		"tome_devastating_berserk": "Tome of Devastating Berserk",
		"tome_swift_analyze": "Tome of Swift Analyze",
		"tome_greater_ambush": "Tome of Greater Ambush",
		"tome_perfect_exploit": "Tome of Perfect Exploit",
		"tome_efficient_vanish": "Tome of Efficient Vanish",
		# Special items
		"mysterious_box": "Mysterious Box",
		"cursed_coin": "Cursed Coin",
		# Home Stones
		"home_stone_egg": "Home Stone (Egg)",
		"home_stone_supplies": "Home Stone (Supplies)",
		"home_stone_equipment": "Home Stone (Equipment)",
		"home_stone_companion": "Home Stone (Companion)",
		# Gold/Gems (special - don't prefix with tier)
		"gold_pouch": "Gold Pouch",
		"gem_small": "Gem",
	}

	var base_name = base_names.get(item_type, "Consumable")

	# Items that don't use tier prefix
	if item_type == "gold_pouch" or item_type == "gem_small" or item_type.begins_with("home_stone_") or item_type.begins_with("tome_") or item_type == "mysterious_box" or item_type == "cursed_coin" or item_type == "scroll_resurrect_lesser" or item_type == "scroll_resurrect_greater":
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
	},
	# Weapon Master - Attack focused (weapons from Weapon Master monsters)
	"weapon_master": {
		"prefix_stats": ["attack_bonus"],
		"suffix_stats": ["attack_bonus", "str_bonus"]
	},
	# Shield Guardian - HP focused (shields from Shield Guardian monsters)
	"shield_guardian": {
		"prefix_stats": ["hp_bonus", "defense_bonus"],
		"suffix_stats": ["hp_bonus", "con_bonus", "defense_bonus"]
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
	# Common/Uncommon boosted to add gear variety - most items now have a chance for affixes
	var affix_chances = {
		"common":    {"prefix": 20, "suffix": 12, "both_bonus": 0},    # ~29% chance for at least one affix
		"uncommon":  {"prefix": 35, "suffix": 25, "both_bonus": 5},    # ~51% chance for at least one affix
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

	# Roll for upgrade - decreasing chance for higher tiers (reduced for balance)
	# Common->Uncommon: 4%, Uncommon->Rare: 2.5%, Rare->Epic: 1.5%, Epic->Legendary: 0.75%, Legendary->Artifact: 0.25%
	var upgrade_chances = [4.0, 2.5, 1.5, 0.75, 0.25]
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

	# Special handling for Home Stones
	if item_type.begins_with("home_stone_"):
		var stone_names = {
			"home_stone_egg": "Home Stone (Egg)",
			"home_stone_supplies": "Home Stone (Supplies)",
			"home_stone_equipment": "Home Stone (Equipment)",
			"home_stone_companion": "Home Stone (Companion)"
		}
		var base_name = stone_names.get(item_type, "Home Stone")
		match rarity:
			"rare": return "Shimmering " + base_name
			"epic": return "Radiant " + base_name
			_: return base_name

	# Special handling for resource potions (unified - mana/stamina/energy all restore primary resource)
	if item_type.begins_with("mana_"):
		var tier = item_type.replace("mana_", "").capitalize()
		return tier + " Resource Potion"
	if item_type.begins_with("stamina_"):
		var tier = item_type.replace("stamina_", "").capitalize()
		return tier + " Resource Potion"
	if item_type.begins_with("energy_"):
		var tier = item_type.replace("energy_", "").capitalize()
		return tier + " Resource Potion"

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
	These are special high-quality weapons scaled to the monster's level.
	Weapons are biased toward attack bonuses."""
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

	# Generate with boosted level for the rare drop (1.15x monster level)
	var boosted_level = int(monster_level * 1.15)

	# Use attack-biased affixes for Weapon Master drops
	var affixes = roll_affixes_for_specialty("weapon_master", rarity, boosted_level)
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
	These are special high-quality shields scaled to the monster's level.
	Shields are biased toward HP bonuses."""
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

	# Generate with boosted level for the rare drop (1.15x monster level)
	var boosted_level = int(monster_level * 1.15)

	# Use HP-biased affixes for Shield Guardian drops
	var affixes = roll_affixes_for_specialty("shield_guardian", rarity, boosted_level)
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
