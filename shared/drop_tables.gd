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
		{"weight": 35, "item_type": "potion_standard", "rarity": "common"},
		{"weight": 30, "item_type": "weapon_steel", "rarity": "uncommon"},
		{"weight": 25, "item_type": "armor_plate", "rarity": "uncommon"},
		{"weight": 10, "item_type": "amulet_bronze", "rarity": "rare"}
	],
	"tier4": [
		{"weight": 30, "item_type": "potion_greater", "rarity": "uncommon"},
		{"weight": 30, "item_type": "weapon_enchanted", "rarity": "rare"},
		{"weight": 25, "item_type": "armor_enchanted", "rarity": "rare"},
		{"weight": 15, "item_type": "ring_gold", "rarity": "rare"}
	],
	"tier5": [
		{"weight": 25, "item_type": "potion_superior", "rarity": "rare"},
		{"weight": 30, "item_type": "weapon_magical", "rarity": "rare"},
		{"weight": 25, "item_type": "armor_magical", "rarity": "rare"},
		{"weight": 20, "item_type": "amulet_silver", "rarity": "epic"}
	],
	"tier6": [
		{"weight": 20, "item_type": "potion_master", "rarity": "rare"},
		{"weight": 30, "item_type": "weapon_elemental", "rarity": "epic"},
		{"weight": 30, "item_type": "armor_elemental", "rarity": "epic"},
		{"weight": 20, "item_type": "ring_elemental", "rarity": "epic"}
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

	# Check if we drop anything at all
	var roll = randi() % 100
	if roll >= drop_chance:
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

	return {
		"id": randi(),
		"type": item_type,
		"rarity": final_rarity,
		"level": final_level,
		"name": _get_item_name(item_type, final_rarity),
		"stats": {},  # Placeholder for item stats
		"value": _calculate_item_value(final_rarity, final_level)
	}

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
	"""Calculate gold value of an item based on rarity and level"""
	var base_values = {
		"common": 10,
		"uncommon": 50,
		"rare": 200,
		"epic": 1000,
		"legendary": 5000,
		"artifact": 25000
	}
	var base = base_values.get(rarity, 10)
	return int(base * (1.0 + level * 0.1))

func get_rarity_color(rarity: String) -> String:
	"""Get the display color for a rarity tier"""
	return RARITY_COLORS.get(rarity, "#FFFFFF")

func to_dict() -> Dictionary:
	return {"initialized": true}
