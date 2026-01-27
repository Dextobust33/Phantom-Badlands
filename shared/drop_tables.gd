# drop_tables.gd
# Item drop table system for Phantasia Revival
# This file contains stub implementations for future item drops
class_name DropTables
extends Node

# Consumable tier definitions
# Tiers replace level-based scaling with fixed power levels that stack
const CONSUMABLE_TIERS = {
	1: {"name": "Minor", "healing": 50, "buff_value": 3, "level_min": 1, "level_max": 10},
	2: {"name": "Lesser", "healing": 100, "buff_value": 5, "level_min": 11, "level_max": 25},
	3: {"name": "Standard", "healing": 200, "buff_value": 8, "level_min": 26, "level_max": 50},
	4: {"name": "Greater", "healing": 400, "buff_value": 12, "level_min": 51, "level_max": 100},
	5: {"name": "Superior", "healing": 800, "buff_value": 18, "level_min": 101, "level_max": 250},
	6: {"name": "Master", "healing": 1600, "buff_value": 25, "level_min": 251, "level_max": 500},
	7: {"name": "Divine", "healing": 3000, "buff_value": 35, "level_min": 501, "level_max": 99999}
}

# Consumable categories for combat quick-use
const CONSUMABLE_CATEGORIES = {
	"health": ["health_potion"],
	"mana": ["mana_potion"],
	"stamina": ["stamina_potion"],
	"energy": ["energy_potion"],
	"buff": ["strength_potion", "defense_potion", "speed_potion", "crit_potion", "lifesteal_potion", "thorns_potion"],
	"scroll": ["scroll_forcefield", "scroll_rage", "scroll_stone_skin", "scroll_haste", "scroll_vampirism", "scroll_thorns", "scroll_precision"]
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
		{"weight": 10, "item_type": "potion_master", "rarity": "rare"},
		{"weight": 5, "item_type": "mana_master", "rarity": "rare"},
		{"weight": 16, "item_type": "weapon_elemental", "rarity": "epic"},
		{"weight": 14, "item_type": "armor_elemental", "rarity": "epic"},
		{"weight": 10, "item_type": "helm_elemental", "rarity": "epic"},
		{"weight": 9, "item_type": "shield_elemental", "rarity": "epic"},
		{"weight": 9, "item_type": "boots_elemental", "rarity": "epic"},
		{"weight": 10, "item_type": "ring_elemental", "rarity": "epic"},
		{"weight": 5, "item_type": "amulet_gold", "rarity": "epic"},
		{"weight": 3, "item_type": "potion_strength", "rarity": "epic"},
		{"weight": 3, "item_type": "potion_defense", "rarity": "epic"},
		{"weight": 3, "item_type": "potion_speed", "rarity": "epic"},
		{"weight": 3, "item_type": "scroll_stone_skin", "rarity": "epic"},
		{"weight": 3, "item_type": "scroll_haste", "rarity": "epic"},
		{"weight": 3, "item_type": "scroll_precision", "rarity": "epic"},
		{"weight": 3, "item_type": "scroll_thorns", "rarity": "epic"}
	],
	"tier7": [
		{"weight": 10, "item_type": "elixir_minor", "rarity": "epic"},
		{"weight": 20, "item_type": "weapon_legendary", "rarity": "epic"},
		{"weight": 18, "item_type": "armor_legendary", "rarity": "epic"},
		{"weight": 12, "item_type": "helm_legendary", "rarity": "epic"},
		{"weight": 10, "item_type": "shield_legendary", "rarity": "epic"},
		{"weight": 10, "item_type": "boots_legendary", "rarity": "epic"},
		{"weight": 10, "item_type": "amulet_gold", "rarity": "legendary"},
		{"weight": 10, "item_type": "ring_legendary", "rarity": "legendary"}
	],
	"tier8": [
		{"weight": 8, "item_type": "elixir_greater", "rarity": "epic"},
		{"weight": 18, "item_type": "weapon_mythic", "rarity": "legendary"},
		{"weight": 16, "item_type": "armor_mythic", "rarity": "legendary"},
		{"weight": 12, "item_type": "helm_mythic", "rarity": "legendary"},
		{"weight": 11, "item_type": "shield_mythic", "rarity": "legendary"},
		{"weight": 11, "item_type": "boots_mythic", "rarity": "legendary"},
		{"weight": 12, "item_type": "ring_mythic", "rarity": "legendary"},
		{"weight": 12, "item_type": "amulet_mythic", "rarity": "legendary"}
	],
	"tier9": [
		{"weight": 4, "item_type": "elixir_divine", "rarity": "legendary"},
		{"weight": 16, "item_type": "weapon_divine", "rarity": "legendary"},
		{"weight": 15, "item_type": "armor_divine", "rarity": "legendary"},
		{"weight": 12, "item_type": "helm_divine", "rarity": "legendary"},
		{"weight": 11, "item_type": "shield_divine", "rarity": "legendary"},
		{"weight": 11, "item_type": "boots_divine", "rarity": "legendary"},
		{"weight": 11, "item_type": "ring_divine", "rarity": "legendary"},
		{"weight": 10, "item_type": "amulet_divine", "rarity": "legendary"},
		{"weight": 10, "item_type": "artifact", "rarity": "artifact"}
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
}

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

func _generate_item(drop_entry: Dictionary, monster_level: int) -> Dictionary:
	"""Generate an actual item from a drop table entry with chance for rarity upgrade."""
	var item_type = drop_entry.get("item_type", "unknown")
	var base_rarity = drop_entry.get("rarity", "common")

	# Small chance for rarity upgrade - adds excitement to loot drops!
	var final_rarity = _maybe_upgrade_rarity(base_rarity)

	# If rarity was upgraded, slightly boost the item level too
	var final_level = monster_level
	if final_rarity != base_rarity:
		final_level = int(monster_level * 1.1)  # 10% level boost on upgrades

	# Check if this is a consumable (potions, resource restorers, scrolls)
	var is_consumable = item_type.begins_with("potion_") or item_type.begins_with("gold_") or item_type.begins_with("gem_") or item_type.begins_with("scroll_") or item_type.begins_with("mana_") or item_type.begins_with("stamina_") or item_type.begins_with("energy_") or item_type.begins_with("elixir_")

	# Roll for affixes (only for equipment, not consumables)
	var affixes = {} if is_consumable else _roll_affixes(final_rarity, final_level)
	var affix_name = _get_affix_prefix(affixes)

	var item = {
		"id": randi(),
		"type": item_type,
		"rarity": final_rarity,
		"level": final_level,
		"name": affix_name + _get_item_name(item_type, final_rarity),
		"affixes": affixes,
		"value": _calculate_item_value(final_rarity, final_level)
	}

	# Add consumable-specific fields for stacking
	if is_consumable:
		item["is_consumable"] = true
		item["quantity"] = 1
		# Determine tier based on monster level
		var tier = get_tier_for_level(final_level)
		item["tier"] = tier
		# Update name to include tier name for consumables
		var tier_name = get_tier_name(tier)
		item["name"] = _get_tiered_consumable_name(item_type, tier_name, final_rarity)

	return item

func _get_tiered_consumable_name(item_type: String, tier_name: String, rarity: String) -> String:
	"""Generate display name for tiered consumables"""
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
		"elixir_divine": "Elixir"
	}

	var base_name = base_names.get(item_type, _get_item_name(item_type, rarity))
	return tier_name + " " + base_name

# Affix definitions: name, stat, value_multiplier (scaled by level)
const AFFIX_POOL = [
	{"name": "Healthy", "stat": "hp_bonus", "base": 10, "per_level": 2},
	{"name": "Vigorous", "stat": "hp_bonus", "base": 20, "per_level": 3},
	{"name": "Stalwart", "stat": "hp_bonus", "base": 30, "per_level": 5},
	{"name": "Mighty", "stat": "attack_bonus", "base": 2, "per_level": 0.5},
	{"name": "Fortified", "stat": "defense_bonus", "base": 2, "per_level": 0.5},
	{"name": "Swift", "stat": "dex_bonus", "base": 1, "per_level": 0.2},
	{"name": "Wise", "stat": "wis_bonus", "base": 1, "per_level": 0.2},
]

func _roll_affixes(rarity: String, item_level: int) -> Dictionary:
	"""Roll for item affixes based on rarity. Higher rarity = more likely and better affixes."""
	var affixes = {}

	# Affix chances by rarity
	var affix_chances = {
		"common": 10,      # 10% chance for 1 affix
		"uncommon": 25,    # 25% chance
		"rare": 45,        # 45% chance
		"epic": 70,        # 70% chance
		"legendary": 90,   # 90% chance
		"artifact": 100    # 100% chance
	}

	var chance = affix_chances.get(rarity, 10)
	var roll = randi() % 100

	if roll >= chance:
		return affixes  # No affixes

	# Roll for which affix
	var affix = AFFIX_POOL[randi() % AFFIX_POOL.size()]
	var value = int(affix.base + affix.per_level * item_level)

	affixes[affix.stat] = value
	affixes["affix_name"] = affix.name

	return affixes

func _get_affix_prefix(affixes: Dictionary) -> String:
	"""Get prefix for item name based on affixes."""
	if affixes.is_empty():
		return ""
	return affixes.get("affix_name", "") + " "

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
			"scroll_target_farm": "Scroll of Finding"
		}
		var base_name = scroll_names.get(item_type, "Mysterious Scroll")
		match rarity:
			"epic": return "Ancient " + base_name
			"legendary": return "Arcane " + base_name
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

	return {
		"id": randi(),
		"type": weapon_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Weapon Master's " + _get_item_name(weapon_type, rarity),
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

	return {
		"id": randi(),
		"type": shield_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Guardian's " + _get_item_name(shield_type, rarity),
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

	return {
		"id": randi(),
		"type": item_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Arcane Hoarder's " + _get_item_name(item_type, rarity),
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
	if roll < 0.33:
		item_type = "ring_shadow"
	elif roll < 0.66:
		item_type = "amulet_evasion"
	else:
		item_type = "boots_swift"

	# Generate with boosted level
	var boosted_level = int(monster_level * 1.15)  # 15% level boost

	var affixes = _roll_affixes(rarity, boosted_level)
	var affix_name = _get_affix_prefix(affixes)

	return {
		"id": randi(),
		"type": item_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Cunning Prey's " + _get_item_name(item_type, rarity),
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

	return {
		"id": randi(),
		"type": item_type,
		"rarity": rarity,
		"level": boosted_level,
		"name": affix_name + "Warrior Hoarder's " + _get_item_name(item_type, rarity),
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
