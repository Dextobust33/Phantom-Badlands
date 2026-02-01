# crafting_database.gd
# Defines crafting skills, recipes, materials, and quality system
extends Node
class_name CraftingDatabase

# Crafting skill types
enum CraftingSkill {
	BLACKSMITHING,  # Weapons, armor
	ALCHEMY,        # Potions, consumables
	ENCHANTING      # Upgrade equipment, add effects
}

# Quality levels from crafting
enum CraftingQuality {
	FAILED,      # 0% - materials lost
	POOR,        # 50% stats
	STANDARD,    # 100% stats
	FINE,        # 125% stats
	MASTERWORK   # 150% stats
}

# Quality multipliers for item stats
const QUALITY_MULTIPLIERS = {
	CraftingQuality.FAILED: 0.0,
	CraftingQuality.POOR: 0.5,
	CraftingQuality.STANDARD: 1.0,
	CraftingQuality.FINE: 1.25,
	CraftingQuality.MASTERWORK: 1.5
}

# Quality color codes for display
const QUALITY_COLORS = {
	CraftingQuality.FAILED: "#808080",
	CraftingQuality.POOR: "#FFFFFF",
	CraftingQuality.STANDARD: "#00FF00",
	CraftingQuality.FINE: "#0070DD",
	CraftingQuality.MASTERWORK: "#A335EE"
}

# Quality names
const QUALITY_NAMES = {
	CraftingQuality.FAILED: "Failed",
	CraftingQuality.POOR: "Poor",
	CraftingQuality.STANDARD: "Standard",
	CraftingQuality.FINE: "Fine",
	CraftingQuality.MASTERWORK: "Masterwork"
}

# XP per craft based on recipe difficulty
const BASE_CRAFT_XP = 25

# ===== MATERIALS =====
# Materials can come from fishing, monster drops, or gathering
const MATERIALS = {
	# Fish (from fishing)
	"small_fish": {"name": "Small Fish", "type": "fish", "tier": 1, "value": 5},
	"medium_fish": {"name": "Medium Fish", "type": "fish", "tier": 2, "value": 15},
	"large_fish": {"name": "Large Fish", "type": "fish", "tier": 3, "value": 30},
	"rare_fish": {"name": "Rare Fish", "type": "fish", "tier": 4, "value": 50},
	"deep_sea_fish": {"name": "Deep Sea Fish", "type": "fish", "tier": 5, "value": 80},
	"legendary_fish": {"name": "Legendary Fish", "type": "fish", "tier": 6, "value": 150},

	# Aquatic materials (from fishing)
	"seaweed": {"name": "Seaweed", "type": "plant", "tier": 1, "value": 3},
	"magic_kelp": {"name": "Magic Kelp", "type": "plant", "tier": 3, "value": 25},
	"pearl": {"name": "Pearl", "type": "gem", "tier": 4, "value": 100},
	"black_pearl": {"name": "Black Pearl", "type": "gem", "tier": 6, "value": 300},
	"coral_fragment": {"name": "Coral Fragment", "type": "mineral", "tier": 2, "value": 10},
	"sea_crystal": {"name": "Sea Crystal", "type": "gem", "tier": 5, "value": 150},

	# Ores (from monster drops by tier)
	"copper_ore": {"name": "Copper Ore", "type": "ore", "tier": 1, "value": 8},
	"iron_ore": {"name": "Iron Ore", "type": "ore", "tier": 2, "value": 15},
	"steel_ore": {"name": "Steel Ore", "type": "ore", "tier": 3, "value": 30},
	"mithril_ore": {"name": "Mithril Ore", "type": "ore", "tier": 4, "value": 60},
	"adamantine_ore": {"name": "Adamantine Ore", "type": "ore", "tier": 5, "value": 120},
	"orichalcum_ore": {"name": "Orichalcum Ore", "type": "ore", "tier": 6, "value": 250},
	"void_ore": {"name": "Void Ore", "type": "ore", "tier": 7, "value": 500},
	"celestial_ore": {"name": "Celestial Ore", "type": "ore", "tier": 8, "value": 1000},
	"primordial_ore": {"name": "Primordial Ore", "type": "ore", "tier": 9, "value": 2000},

	# Leather/Cloth (from monster drops)
	"ragged_leather": {"name": "Ragged Leather", "type": "leather", "tier": 1, "value": 5},
	"leather_scraps": {"name": "Leather Scraps", "type": "leather", "tier": 2, "value": 10},
	"thick_leather": {"name": "Thick Leather", "type": "leather", "tier": 3, "value": 20},
	"enchanted_leather": {"name": "Enchanted Leather", "type": "leather", "tier": 4, "value": 45},
	"dragonhide": {"name": "Dragonhide", "type": "leather", "tier": 6, "value": 200},
	"void_silk": {"name": "Void Silk", "type": "cloth", "tier": 7, "value": 400},

	# Herbs (from monster drops, for alchemy)
	"healing_herb": {"name": "Healing Herb", "type": "herb", "tier": 1, "value": 5},
	"mana_blossom": {"name": "Mana Blossom", "type": "herb", "tier": 2, "value": 12},
	"vigor_root": {"name": "Vigor Root", "type": "herb", "tier": 2, "value": 12},
	"shadowleaf": {"name": "Shadowleaf", "type": "herb", "tier": 3, "value": 25},
	"phoenix_petal": {"name": "Phoenix Petal", "type": "herb", "tier": 5, "value": 100},
	"dragon_blood": {"name": "Dragon Blood", "type": "essence", "tier": 6, "value": 250},
	"essence_of_life": {"name": "Essence of Life", "type": "essence", "tier": 7, "value": 500},

	# Enchanting materials
	"magic_dust": {"name": "Magic Dust", "type": "enchant", "tier": 1, "value": 10},
	"arcane_crystal": {"name": "Arcane Crystal", "type": "enchant", "tier": 3, "value": 50},
	"soul_shard": {"name": "Soul Shard", "type": "enchant", "tier": 4, "value": 80},
	"void_essence": {"name": "Void Essence", "type": "enchant", "tier": 6, "value": 200},
	"primordial_spark": {"name": "Primordial Spark", "type": "enchant", "tier": 8, "value": 800},
}

# ===== RECIPES =====
# Each recipe defines what can be crafted
const RECIPES = {
	# ===== BLACKSMITHING RECIPES =====
	# Tier 1 - Copper (Level 1-15)
	"copper_sword": {
		"name": "Copper Sword",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"copper_ore": 3},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 5, "level": 5},
		"craft_time": 2.0
	},
	"copper_shield": {
		"name": "Copper Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"copper_ore": 4, "ragged_leather": 1},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 4, "level": 5},
		"craft_time": 2.5
	},
	"copper_helm": {
		"name": "Copper Helm",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 8,
		"difficulty": 12,
		"materials": {"copper_ore": 3, "ragged_leather": 1},
		"output_type": "armor",
		"output_slot": "head",
		"base_stats": {"defense": 3, "hp": 10, "level": 5},
		"craft_time": 2.0
	},

	# Tier 2 - Iron (Level 15-30)
	"iron_sword": {
		"name": "Iron Sword",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"iron_ore": 4, "leather_scraps": 1},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 12, "level": 15},
		"craft_time": 3.0
	},
	"iron_breastplate": {
		"name": "Iron Breastplate",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"iron_ore": 6, "leather_scraps": 2},
		"output_type": "armor",
		"output_slot": "chest",
		"base_stats": {"defense": 10, "hp": 25, "level": 15},
		"craft_time": 4.0
	},
	"iron_shield": {
		"name": "Iron Shield",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 18,
		"difficulty": 22,
		"materials": {"iron_ore": 5, "leather_scraps": 1},
		"output_type": "armor",
		"output_slot": "shield",
		"base_stats": {"defense": 8, "level": 15},
		"craft_time": 3.0
	},

	# Tier 3 - Steel (Level 30-50)
	"steel_sword": {
		"name": "Steel Sword",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 30,
		"difficulty": 35,
		"materials": {"steel_ore": 5, "thick_leather": 1},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 25, "level": 30},
		"craft_time": 4.0
	},
	"steel_armor": {
		"name": "Steel Armor",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"steel_ore": 8, "thick_leather": 3},
		"output_type": "armor",
		"output_slot": "chest",
		"base_stats": {"defense": 20, "hp": 50, "level": 30},
		"craft_time": 5.0
	},

	# Tier 4 - Mithril (Level 50-100)
	"mithril_blade": {
		"name": "Mithril Blade",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 45,
		"difficulty": 50,
		"materials": {"mithril_ore": 6, "enchanted_leather": 2},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 45, "speed": 5, "level": 50},
		"craft_time": 5.0
	},
	"mithril_mail": {
		"name": "Mithril Mail",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 50,
		"difficulty": 55,
		"materials": {"mithril_ore": 10, "enchanted_leather": 4},
		"output_type": "armor",
		"output_slot": "chest",
		"base_stats": {"defense": 35, "hp": 100, "speed": 3, "level": 50},
		"craft_time": 6.0
	},

	# Tier 5+ - High level crafting
	"adamantine_greatsword": {
		"name": "Adamantine Greatsword",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 65,
		"difficulty": 70,
		"materials": {"adamantine_ore": 8, "dragonhide": 2, "arcane_crystal": 1},
		"output_type": "weapon",
		"output_slot": "weapon",
		"base_stats": {"attack": 80, "level": 100},
		"craft_time": 8.0
	},
	"orichalcum_plate": {
		"name": "Orichalcum Plate",
		"skill": CraftingSkill.BLACKSMITHING,
		"skill_required": 80,
		"difficulty": 85,
		"materials": {"orichalcum_ore": 12, "dragonhide": 4, "void_essence": 1},
		"output_type": "armor",
		"output_slot": "chest",
		"base_stats": {"defense": 60, "hp": 200, "level": 150},
		"craft_time": 10.0
	},

	# ===== ALCHEMY RECIPES =====
	# Healing Potions
	"minor_health_potion": {
		"name": "Minor Health Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 1,
		"difficulty": 5,
		"materials": {"healing_herb": 2, "small_fish": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 50},
		"craft_time": 1.5
	},
	"health_potion": {
		"name": "Health Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 15,
		"difficulty": 20,
		"materials": {"healing_herb": 4, "medium_fish": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 150},
		"craft_time": 2.0
	},
	"greater_health_potion": {
		"name": "Greater Health Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"healing_herb": 6, "rare_fish": 2, "phoenix_petal": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 400},
		"craft_time": 3.0
	},
	"supreme_health_potion": {
		"name": "Supreme Health Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 60,
		"difficulty": 65,
		"materials": {"phoenix_petal": 3, "dragon_blood": 1, "essence_of_life": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "heal", "amount": 1000},
		"craft_time": 4.0
	},

	# Mana Potions
	"minor_mana_potion": {
		"name": "Minor Mana Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"mana_blossom": 2, "seaweed": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_mana", "amount": 30},
		"craft_time": 1.5
	},
	"mana_potion": {
		"name": "Mana Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"mana_blossom": 4, "magic_kelp": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_mana", "amount": 80},
		"craft_time": 2.0
	},

	# Stamina Potions
	"minor_stamina_potion": {
		"name": "Minor Stamina Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 5,
		"difficulty": 10,
		"materials": {"vigor_root": 2, "small_fish": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_stamina", "amount": 30},
		"craft_time": 1.5
	},
	"stamina_potion": {
		"name": "Stamina Potion",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 20,
		"difficulty": 25,
		"materials": {"vigor_root": 4, "medium_fish": 2},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "restore_stamina", "amount": 80},
		"craft_time": 2.0
	},

	# Buff Potions
	"potion_of_strength": {
		"name": "Potion of Strength",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 25,
		"difficulty": 30,
		"materials": {"vigor_root": 3, "iron_ore": 2, "shadowleaf": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "attack", "amount": 15, "duration": 10},
		"craft_time": 3.0
	},
	"potion_of_fortitude": {
		"name": "Potion of Fortitude",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 25,
		"difficulty": 30,
		"materials": {"healing_herb": 3, "thick_leather": 1, "shadowleaf": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "defense", "amount": 15, "duration": 10},
		"craft_time": 3.0
	},
	"elixir_of_speed": {
		"name": "Elixir of Speed",
		"skill": CraftingSkill.ALCHEMY,
		"skill_required": 40,
		"difficulty": 45,
		"materials": {"shadowleaf": 3, "rare_fish": 2, "arcane_crystal": 1},
		"output_type": "consumable",
		"output_slot": "",
		"effect": {"type": "buff", "stat": "speed", "amount": 20, "duration": 8},
		"craft_time": 4.0
	},

	# ===== ENCHANTING RECIPES =====
	"minor_weapon_enhancement": {
		"name": "Minor Weapon Enhancement",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"magic_dust": 5},
		"output_type": "enhancement",
		"output_slot": "weapon",
		"effect": {"type": "enhance", "stat": "attack", "bonus": 3},
		"craft_time": 3.0
	},
	"minor_armor_enhancement": {
		"name": "Minor Armor Enhancement",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 10,
		"difficulty": 15,
		"materials": {"magic_dust": 5},
		"output_type": "enhancement",
		"output_slot": "armor",
		"effect": {"type": "enhance", "stat": "defense", "bonus": 3},
		"craft_time": 3.0
	},
	"arcane_weapon_enhancement": {
		"name": "Arcane Weapon Enhancement",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"arcane_crystal": 3, "soul_shard": 1},
		"output_type": "enhancement",
		"output_slot": "weapon",
		"effect": {"type": "enhance", "stat": "attack", "bonus": 10},
		"craft_time": 5.0
	},
	"arcane_armor_enhancement": {
		"name": "Arcane Armor Enhancement",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 35,
		"difficulty": 40,
		"materials": {"arcane_crystal": 3, "soul_shard": 1},
		"output_type": "enhancement",
		"output_slot": "armor",
		"effect": {"type": "enhance", "stat": "defense", "bonus": 10},
		"craft_time": 5.0
	},
	"void_enhancement": {
		"name": "Void Enhancement",
		"skill": CraftingSkill.ENCHANTING,
		"skill_required": 60,
		"difficulty": 65,
		"materials": {"void_essence": 2, "primordial_spark": 1},
		"output_type": "enhancement",
		"output_slot": "any",
		"effect": {"type": "enhance", "stat": "all", "bonus": 5},
		"craft_time": 8.0
	},
}

# Trading post specializations (bonus to success chance)
const TRADING_POST_SPECIALIZATIONS = {
	"haven": {"blacksmithing": 5, "alchemy": 0, "enchanting": 0},
	"crossroads": {"blacksmithing": 0, "alchemy": 5, "enchanting": 0},
	"frostgate": {"blacksmithing": 10, "alchemy": 0, "enchanting": 0},
	"eastwatch": {"blacksmithing": 0, "alchemy": 0, "enchanting": 10},
	"south_gate": {"blacksmithing": 0, "alchemy": 10, "enchanting": 0},
	"west_shrine": {"blacksmithing": 0, "alchemy": 0, "enchanting": 15},
	"fire_mountain": {"blacksmithing": 20, "alchemy": 0, "enchanting": 0},
}

# ===== HELPER FUNCTIONS =====

static func get_skill_name(skill: CraftingSkill) -> String:
	match skill:
		CraftingSkill.BLACKSMITHING:
			return "blacksmithing"
		CraftingSkill.ALCHEMY:
			return "alchemy"
		CraftingSkill.ENCHANTING:
			return "enchanting"
		_:
			return "unknown"

static func get_skill_display_name(skill: CraftingSkill) -> String:
	match skill:
		CraftingSkill.BLACKSMITHING:
			return "Blacksmithing"
		CraftingSkill.ALCHEMY:
			return "Alchemy"
		CraftingSkill.ENCHANTING:
			return "Enchanting"
		_:
			return "Unknown"

static func get_recipe(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})

static func get_material(material_id: String) -> Dictionary:
	return MATERIALS.get(material_id, {})

static func get_recipes_for_skill(skill: CraftingSkill) -> Array:
	"""Get all recipes for a specific skill"""
	var result = []
	for recipe_id in RECIPES:
		if RECIPES[recipe_id].skill == skill:
			result.append({"id": recipe_id, "data": RECIPES[recipe_id]})
	# Sort by skill_required
	result.sort_custom(func(a, b): return a.data.skill_required < b.data.skill_required)
	return result

static func get_available_recipes(skill: CraftingSkill, skill_level: int) -> Array:
	"""Get recipes the player can craft at their current skill level"""
	var result = []
	for recipe_id in RECIPES:
		var recipe = RECIPES[recipe_id]
		if recipe.skill == skill and recipe.skill_required <= skill_level:
			result.append({"id": recipe_id, "data": recipe})
	result.sort_custom(func(a, b): return a.data.skill_required < b.data.skill_required)
	return result

static func calculate_success_chance(skill_level: int, difficulty: int, post_bonus: int = 0) -> int:
	"""Calculate base success chance (0-100)"""
	# Base success = 50 + (skill_level - difficulty) * 2 + post_bonus
	var base = 50 + (skill_level - difficulty) * 2 + post_bonus
	return clampi(base, 5, 95)  # Always 5-95% chance

static func roll_quality(skill_level: int, difficulty: int, post_bonus: int = 0) -> CraftingQuality:
	"""Roll for crafting quality based on skill vs difficulty"""
	var success_chance = calculate_success_chance(skill_level, difficulty, post_bonus)
	var roll = randi() % 100

	# Quality thresholds based on success chance vs roll
	# Higher skill = more likely to get better quality
	if roll > success_chance + 30:
		return CraftingQuality.FAILED
	elif roll > success_chance + 15:
		return CraftingQuality.POOR
	elif roll > success_chance - 15:
		return CraftingQuality.STANDARD
	elif roll > success_chance - 30:
		return CraftingQuality.FINE
	else:
		return CraftingQuality.MASTERWORK

static func calculate_craft_xp(difficulty: int, quality: CraftingQuality) -> int:
	"""Calculate XP gained from crafting"""
	var base_xp = BASE_CRAFT_XP + difficulty
	# Bonus XP for quality
	match quality:
		CraftingQuality.FAILED:
			return base_xp / 4  # Still get some XP for trying
		CraftingQuality.POOR:
			return base_xp / 2
		CraftingQuality.STANDARD:
			return base_xp
		CraftingQuality.FINE:
			return int(base_xp * 1.5)
		CraftingQuality.MASTERWORK:
			return base_xp * 2
		_:
			return base_xp

static func get_post_specialization_bonus(post_id: String, skill_name: String) -> int:
	"""Get crafting bonus for a specific skill at a trading post"""
	if not TRADING_POST_SPECIALIZATIONS.has(post_id):
		return 0
	return TRADING_POST_SPECIALIZATIONS[post_id].get(skill_name.to_lower(), 0)

static func apply_quality_to_stats(base_stats: Dictionary, quality: CraftingQuality) -> Dictionary:
	"""Apply quality multiplier to item stats"""
	var multiplier = QUALITY_MULTIPLIERS.get(quality, 1.0)
	var result = {}
	for stat in base_stats:
		if stat == "level":
			result[stat] = base_stats[stat]  # Level doesn't scale
		else:
			result[stat] = int(base_stats[stat] * multiplier)
	return result

static func format_materials_list(materials: Dictionary, owned_materials: Dictionary) -> String:
	"""Format materials list with owned counts"""
	var lines = []
	for mat_id in materials:
		var required = materials[mat_id]
		var owned = owned_materials.get(mat_id, 0)
		var mat_info = MATERIALS.get(mat_id, {"name": mat_id})
		var color = "#00FF00" if owned >= required else "#FF4444"
		lines.append("[color=%s]%s: %d/%d[/color]" % [color, mat_info.name, owned, required])
	return "\n".join(lines)
