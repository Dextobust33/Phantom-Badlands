# drop_tables.gd
# Item drop table system for Phantasia Revival
# This file contains stub implementations for future item drops
class_name DropTables
extends Node

# Drop table definitions by tier
# Each entry: {weight: int, item_type: String, rarity: String}
# Higher weight = more common
const DROP_TABLES = {
	"tier1": [
		{"weight": 50, "item_type": "potion_minor", "rarity": "common"},
		{"weight": 30, "item_type": "weapon_rusty", "rarity": "common"},
		{"weight": 15, "item_type": "armor_leather", "rarity": "common"},
		{"weight": 5, "item_type": "ring_copper", "rarity": "uncommon"}
	],
	"tier2": [
		{"weight": 40, "item_type": "potion_lesser", "rarity": "common"},
		{"weight": 30, "item_type": "weapon_iron", "rarity": "common"},
		{"weight": 20, "item_type": "armor_chain", "rarity": "uncommon"},
		{"weight": 10, "item_type": "ring_silver", "rarity": "uncommon"}
	],
	"tier3": [
		{"weight": 30, "item_type": "potion_standard", "rarity": "common"},
		{"weight": 25, "item_type": "weapon_steel", "rarity": "uncommon"},
		{"weight": 22, "item_type": "armor_plate", "rarity": "uncommon"},
		{"weight": 8, "item_type": "amulet_bronze", "rarity": "rare"},
		{"weight": 5, "item_type": "potion_strength", "rarity": "uncommon"},
		{"weight": 5, "item_type": "potion_defense", "rarity": "uncommon"},
		{"weight": 5, "item_type": "potion_speed", "rarity": "uncommon"}
	],
	"tier4": [
		{"weight": 25, "item_type": "potion_greater", "rarity": "uncommon"},
		{"weight": 25, "item_type": "weapon_enchanted", "rarity": "rare"},
		{"weight": 22, "item_type": "armor_enchanted", "rarity": "rare"},
		{"weight": 12, "item_type": "ring_gold", "rarity": "rare"},
		{"weight": 6, "item_type": "potion_strength", "rarity": "rare"},
		{"weight": 5, "item_type": "potion_defense", "rarity": "rare"},
		{"weight": 5, "item_type": "potion_speed", "rarity": "rare"}
	],
	"tier5": [
		{"weight": 22, "item_type": "potion_superior", "rarity": "rare"},
		{"weight": 26, "item_type": "weapon_magical", "rarity": "rare"},
		{"weight": 22, "item_type": "armor_magical", "rarity": "rare"},
		{"weight": 16, "item_type": "amulet_silver", "rarity": "epic"},
		{"weight": 5, "item_type": "potion_strength", "rarity": "epic"},
		{"weight": 5, "item_type": "potion_defense", "rarity": "epic"},
		{"weight": 4, "item_type": "potion_speed", "rarity": "epic"}
	],
	"tier6": [
		{"weight": 17, "item_type": "potion_master", "rarity": "rare"},
		{"weight": 26, "item_type": "weapon_elemental", "rarity": "epic"},
		{"weight": 26, "item_type": "armor_elemental", "rarity": "epic"},
		{"weight": 17, "item_type": "ring_elemental", "rarity": "epic"},
		{"weight": 5, "item_type": "potion_strength", "rarity": "epic"},
		{"weight": 5, "item_type": "potion_defense", "rarity": "epic"},
		{"weight": 4, "item_type": "potion_speed", "rarity": "epic"}
	],
	"tier7": [
		{"weight": 15, "item_type": "elixir_minor", "rarity": "epic"},
		{"weight": 35, "item_type": "weapon_legendary", "rarity": "epic"},
		{"weight": 30, "item_type": "armor_legendary", "rarity": "epic"},
		{"weight": 20, "item_type": "amulet_gold", "rarity": "legendary"}
	],
	"tier8": [
		{"weight": 10, "item_type": "elixir_greater", "rarity": "epic"},
		{"weight": 35, "item_type": "weapon_mythic", "rarity": "legendary"},
		{"weight": 35, "item_type": "armor_mythic", "rarity": "legendary"},
		{"weight": 20, "item_type": "ring_mythic", "rarity": "legendary"}
	],
	"tier9": [
		{"weight": 5, "item_type": "elixir_divine", "rarity": "legendary"},
		{"weight": 35, "item_type": "weapon_divine", "rarity": "legendary"},
		{"weight": 35, "item_type": "armor_divine", "rarity": "legendary"},
		{"weight": 25, "item_type": "artifact", "rarity": "artifact"}
	],
	"common": [
		{"weight": 60, "item_type": "potion_minor", "rarity": "common"},
		{"weight": 30, "item_type": "gold_pouch", "rarity": "common"},
		{"weight": 10, "item_type": "gem_small", "rarity": "uncommon"}
	]
}

# Potion effects for consumables
# heal: restores HP, buff: applies temporary combat buff
const POTION_EFFECTS = {
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
	# Basic buff potions - last rounds (single combat), scale with level
	"potion_strength": {"buff": "strength", "base": 3, "per_level": 1, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	"potion_defense": {"buff": "defense", "base": 3, "per_level": 1, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	"potion_speed": {"buff": "speed", "base": 5, "per_level": 2, "rounds": true, "base_duration": 5, "duration_per_10_levels": 2},
	# Power potions - last multiple battles
	"potion_power": {"buff": "strength", "base": 8, "per_level": 2, "battles": true, "base_duration": 2, "duration_per_10_levels": 1},
	"potion_iron": {"buff": "defense", "base": 8, "per_level": 2, "battles": true, "base_duration": 2, "duration_per_10_levels": 1},
	"potion_haste": {"buff": "speed", "base": 15, "per_level": 3, "battles": true, "base_duration": 2, "duration_per_10_levels": 1},
	# Elixirs - powerful multi-battle buffs
	"elixir_might": {"buff": "strength", "base": 15, "per_level": 3, "battles": true, "base_duration": 5, "duration_per_10_levels": 2},
	"elixir_fortress": {"buff": "defense", "base": 15, "per_level": 3, "battles": true, "base_duration": 5, "duration_per_10_levels": 2},
	"elixir_swiftness": {"buff": "speed", "base": 25, "per_level": 5, "battles": true, "base_duration": 5, "duration_per_10_levels": 2},
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

	# Roll for affixes
	var affixes = _roll_affixes(final_rarity, final_level)
	var affix_name = _get_affix_prefix(affixes)

	return {
		"id": randi(),
		"type": item_type,
		"rarity": final_rarity,
		"level": final_level,
		"name": affix_name + _get_item_name(item_type, final_rarity),
		"affixes": affixes,
		"value": _calculate_item_value(final_rarity, final_level)
	}

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
