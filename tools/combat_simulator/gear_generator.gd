# gear_generator.gd
# Generate level-appropriate equipment for combat simulation
# Based on equipment formulas from shared/character.gd lines 831-1043
# Includes estimated affix contributions from shared/drop_tables.gd
extends RefCounted
class_name GearGenerator

# Quality presets for gear generation
enum GearQuality {
	POOR,      # Common rarity, level-5, minimal affixes
	AVERAGE,   # Uncommon rarity, level-appropriate, some affixes
	GOOD,      # Rare rarity, level+10%, good affixes
	OPTIMAL    # Epic rarity, level+20%, excellent affixes
}

# Rarity multipliers (from character.gd lines 1017-1026)
const RARITY_MULTIPLIERS = {
	"common": 1.0,
	"uncommon": 1.2,
	"rare": 1.4,
	"epic": 1.7,
	"legendary": 2.0,
	"artifact": 2.5
}

# Equipment slots and their bonus types (from character.gd lines 876-901)
const SLOT_BONUSES = {
	"weapon": {"attack": 1.5, "strength": 0.3},
	"armor": {"defense": 1.0, "constitution": 0.2, "max_hp": 1.5},
	"helm": {"defense": 0.6, "wisdom": 0.15},
	"shield": {"defense": 0.4, "max_hp": 2.0, "constitution": 0.2},
	"ring": {"attack": 0.3, "dexterity": 0.2, "intelligence": 0.15},
	"amulet": {"max_mana": 1.0, "wisdom": 0.2, "wits": 0.15},
	"boots": {"speed": 0.6, "dexterity": 0.2, "defense": 0.3}
}

# All equipment slots
const ALL_SLOTS = ["weapon", "armor", "helm", "shield", "ring", "amulet", "boots"]

# Average affix values per stat (base + per_level scaling)
# From drop_tables.gd PREFIX_POOL and SUFFIX_POOL analysis
# Format: {stat: {base: avg_base, per_level: avg_per_level}}
const AFFIX_AVG_VALUES = {
	"attack_bonus": {"base": 4.5, "per_level": 0.83},    # Average of attack prefixes
	"defense_bonus": {"base": 4.0, "per_level": 0.77},   # Average of defense prefixes
	"hp_bonus": {"base": 25.0, "per_level": 4.0},        # Average of HP prefixes
	"speed_bonus": {"base": 4.0, "per_level": 0.5},      # Average of speed prefixes
	"mana_bonus": {"base": 15.0, "per_level": 3.0},      # Average of mana prefixes
	"stamina_bonus": {"base": 7.5, "per_level": 1.5},    # Average of stamina prefixes
	"energy_bonus": {"base": 8.0, "per_level": 1.5},     # Average of energy prefixes
	"str_bonus": {"base": 3.0, "per_level": 0.5},        # From suffix pool
	"con_bonus": {"base": 3.0, "per_level": 0.5},
	"dex_bonus": {"base": 3.0, "per_level": 0.5},
	"int_bonus": {"base": 3.0, "per_level": 0.5},
	"wis_bonus": {"base": 3.0, "per_level": 0.5},
	"wits_bonus": {"base": 3.0, "per_level": 0.5}
}

# Expected number of affixes per item by quality (across all 7 slots)
# Poor: ~0.3 affixes per item (common, 29% chance)
# Average: ~0.6 affixes per item (uncommon, 51% chance, often 1 affix)
# Good: ~1.2 affixes per item (rare, usually 1, sometimes 2)
# Optimal: ~1.7 affixes per item (epic, usually 1-2 affixes)
const AFFIXES_PER_ITEM = {
	GearQuality.POOR: 0.3,
	GearQuality.AVERAGE: 0.6,
	GearQuality.GOOD: 1.2,
	GearQuality.OPTIMAL: 1.7
}

func _init():
	pass

func generate_gear_set(level: int, quality: GearQuality, class_type: String = "") -> Dictionary:
	"""Generate a full equipment set at the given level and quality.
	Includes base slot bonuses, estimated affix contributions, and class-specific gear.
	If class_type is provided, includes class-specific items based on quality."""
	var gear_level = _get_gear_level_for_quality(level, quality)
	var rarity = _get_rarity_for_quality(quality)
	var rarity_mult = RARITY_MULTIPLIERS.get(rarity, 1.0)

	# Calculate effective level with diminishing returns (from character.gd lines 1028-1043)
	var effective_level = _get_effective_item_level(gear_level)

	# Base bonus from level and rarity
	var base_bonus = int(effective_level * rarity_mult)

	# Accumulate bonuses from all slots
	var total_bonuses = {
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
		"max_stamina": 0,
		"max_energy": 0,
		"speed": 0,
		"stamina_regen": 0,
		"mana_regen": 0,
		"energy_regen": 0,
		# Proc effects (tier 6+ items, level 100+)
		"lifesteal_percent": 0,
		"execute_chance": 0,
		"execute_bonus": 0,
		"shocking_chance": 0,
		"shocking_bonus": 0,
		"damage_reflect_percent": 0
	}

	# Add base slot bonuses
	for slot in ALL_SLOTS:
		var slot_multipliers = SLOT_BONUSES.get(slot, {})
		for stat in slot_multipliers:
			var mult = slot_multipliers[stat]
			var bonus = int(base_bonus * mult)
			if bonus > 0:
				total_bonuses[stat] += max(1, bonus)

	# Add estimated affix contributions
	var affix_bonuses = _estimate_affix_bonuses(gear_level, quality)
	total_bonuses.attack += affix_bonuses.get("attack", 0)
	total_bonuses.defense += affix_bonuses.get("defense", 0)
	total_bonuses.max_hp += affix_bonuses.get("max_hp", 0)
	total_bonuses.max_mana += affix_bonuses.get("max_mana", 0)
	total_bonuses.max_stamina += affix_bonuses.get("max_stamina", 0)
	total_bonuses.max_energy += affix_bonuses.get("max_energy", 0)
	total_bonuses.speed += affix_bonuses.get("speed", 0)
	total_bonuses.strength += affix_bonuses.get("strength", 0)
	total_bonuses.constitution += affix_bonuses.get("constitution", 0)
	total_bonuses.dexterity += affix_bonuses.get("dexterity", 0)
	total_bonuses.intelligence += affix_bonuses.get("intelligence", 0)
	total_bonuses.wisdom += affix_bonuses.get("wisdom", 0)
	total_bonuses.wits += affix_bonuses.get("wits", 0)

	# Add class-specific gear bonuses (from character.gd lines 766-792)
	if class_type != "":
		_apply_class_gear_bonuses(total_bonuses, base_bonus, gear_level, quality, class_type)

	# Add proc effects for tier 6+ items (level 100+)
	if gear_level >= 100:
		_apply_proc_effects(total_bonuses, gear_level, quality)

	return total_bonuses

func _apply_class_gear_bonuses(bonuses: Dictionary, base_bonus: int, gear_level: int, quality: GearQuality, class_type: String):
	"""Apply class-specific gear bonuses based on quality.
	Average quality: 1 class-specific item. Good quality: 2 class-specific items.
	Matches character.gd lines 766-792."""
	var class_path = _get_class_path(class_type)
	var num_class_items = 0
	match quality:
		GearQuality.POOR:
			num_class_items = 0
		GearQuality.AVERAGE:
			num_class_items = 1
		GearQuality.GOOD, GearQuality.OPTIMAL:
			num_class_items = 2

	if num_class_items == 0:
		return

	match class_path:
		"warrior":
			# Warlord Blade: +stamina_regen = int(base_bonus * 0.2)
			bonuses.stamina_regen += max(1, int(base_bonus * 0.2)) if base_bonus > 0 else 0
			if num_class_items >= 2:
				# Bulwark Shield: +stamina_regen = int(base_bonus * 0.15)
				bonuses.stamina_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
		"mage":
			# Arcane Ring: +INT = int(base_bonus * 0.7), +mana_regen = int(base_bonus * 0.35)
			bonuses.intelligence += max(1, int(base_bonus * 0.7)) if base_bonus > 0 else 0
			bonuses.mana_regen += max(1, int(base_bonus * 0.35)) if base_bonus > 0 else 0
			if num_class_items >= 2:
				# Mystic Amulet: +max_mana, +meditate_bonus (meditate_bonus not tracked, use mana_regen)
				bonuses.max_mana += base_bonus
				bonuses.mana_regen += max(1, int(gear_level / 3)) if gear_level > 0 else 0
		"trickster":
			# Shadow Ring: +WITS = int(base_bonus * 0.5), +energy_regen = int(base_bonus * 0.15)
			bonuses.wits += max(1, int(base_bonus * 0.5)) if base_bonus > 0 else 0
			bonuses.energy_regen += max(1, int(base_bonus * 0.15)) if base_bonus > 0 else 0
			if num_class_items >= 2:
				# Swift Boots: +speed, +WITS = int(base_bonus * 0.3), +energy_regen = int(base_bonus * 0.1)
				bonuses.speed += int(base_bonus * 0.5)
				bonuses.wits += max(1, int(base_bonus * 0.3)) if base_bonus > 0 else 0
				bonuses.energy_regen += max(1, int(base_bonus * 0.1)) if base_bonus > 0 else 0

func _get_class_path(class_type: String) -> String:
	"""Get combat path for a class type"""
	match class_type:
		"Fighter", "Barbarian", "Paladin":
			return "warrior"
		"Wizard", "Sorcerer", "Sage":
			return "mage"
		"Thief", "Ranger", "Ninja":
			return "trickster"
		_:
			return "warrior"

func _estimate_affix_bonuses(item_level: int, quality: GearQuality) -> Dictionary:
	"""Estimate total affix bonuses across all equipment slots.
	Uses average affix values and expected affix counts per quality level."""
	var bonuses = {
		"attack": 0,
		"defense": 0,
		"max_hp": 0,
		"max_mana": 0,
		"max_stamina": 0,
		"max_energy": 0,
		"speed": 0,
		"strength": 0,
		"constitution": 0,
		"dexterity": 0,
		"intelligence": 0,
		"wisdom": 0,
		"wits": 0
	}

	# How many affixes do we expect across all 7 slots?
	var affixes_per_item = AFFIXES_PER_ITEM.get(quality, 0.5)
	var total_affixes = int(ALL_SLOTS.size() * affixes_per_item)

	if total_affixes == 0:
		return bonuses

	# Distribute affixes across stats with typical distribution:
	# Combat stats (attack, defense, hp) ~40%
	# Resource stats (mana, stamina, energy) ~15%
	# Speed ~10%
	# Primary stats (all 6) ~35%
	var combat_affixes = int(total_affixes * 0.40)
	var resource_affixes = int(total_affixes * 0.15)
	var speed_affixes = int(total_affixes * 0.10)
	var stat_affixes = total_affixes - combat_affixes - resource_affixes - speed_affixes

	# Calculate average affix value for this level
	var avg_attack = int(AFFIX_AVG_VALUES.attack_bonus.base + AFFIX_AVG_VALUES.attack_bonus.per_level * item_level)
	var avg_defense = int(AFFIX_AVG_VALUES.defense_bonus.base + AFFIX_AVG_VALUES.defense_bonus.per_level * item_level)
	var avg_hp = int(AFFIX_AVG_VALUES.hp_bonus.base + AFFIX_AVG_VALUES.hp_bonus.per_level * item_level)
	var avg_speed = int(AFFIX_AVG_VALUES.speed_bonus.base + AFFIX_AVG_VALUES.speed_bonus.per_level * item_level)
	var avg_mana = int(AFFIX_AVG_VALUES.mana_bonus.base + AFFIX_AVG_VALUES.mana_bonus.per_level * item_level)
	var avg_stamina = int(AFFIX_AVG_VALUES.stamina_bonus.base + AFFIX_AVG_VALUES.stamina_bonus.per_level * item_level)
	var avg_energy = int(AFFIX_AVG_VALUES.energy_bonus.base + AFFIX_AVG_VALUES.energy_bonus.per_level * item_level)
	var avg_stat = int(AFFIX_AVG_VALUES.str_bonus.base + AFFIX_AVG_VALUES.str_bonus.per_level * item_level)

	# Distribute combat affixes (roughly equal between attack, defense, HP)
	var attack_affixes = int(combat_affixes / 3.0)
	var defense_affixes = int(combat_affixes / 3.0)
	var hp_affixes = combat_affixes - attack_affixes - defense_affixes

	bonuses.attack = attack_affixes * avg_attack
	bonuses.defense = defense_affixes * avg_defense
	bonuses.max_hp = hp_affixes * avg_hp

	# Distribute resource affixes (roughly equal between mana, stamina, energy)
	if resource_affixes > 0:
		var per_resource = max(1, int(resource_affixes / 3.0))
		bonuses.max_mana = per_resource * avg_mana
		bonuses.max_stamina = per_resource * avg_stamina
		bonuses.max_energy = per_resource * avg_energy

	# Speed affixes
	bonuses.speed = max(1, speed_affixes) * avg_speed

	# Spread stat affixes across ALL 6 primary stats (not just STR/CON/DEX)
	if stat_affixes > 0:
		var per_stat = max(1, int(stat_affixes / 6.0))
		bonuses.strength = per_stat * avg_stat
		bonuses.constitution = per_stat * avg_stat
		bonuses.dexterity = per_stat * avg_stat
		bonuses.intelligence = per_stat * avg_stat
		bonuses.wisdom = per_stat * avg_stat
		bonuses.wits = per_stat * avg_stat

	return bonuses

func _apply_proc_effects(bonuses: Dictionary, gear_level: int, quality: GearQuality):
	"""Apply proc suffix effects for tier 6+ items (level 100+).
	From drop_tables.gd PROC_SUFFIX_POOL - these appear on higher quality items.
	Poor: no procs, Average: 1 proc on 1 item, Good+: 1-2 procs."""
	var num_procs = 0
	match quality:
		GearQuality.POOR:
			return  # No procs at poor quality
		GearQuality.AVERAGE:
			num_procs = 1 if gear_level >= 150 else 0
		GearQuality.GOOD:
			num_procs = 1 if gear_level >= 100 else 0
		GearQuality.OPTIMAL:
			num_procs = 2 if gear_level >= 100 else 1

	if num_procs == 0:
		return

	# Scale proc values by level tier
	# Tier 6 (100-200): basic procs, Tier 7+ (200+): stronger procs
	var proc_tier = 1 if gear_level < 200 else (2 if gear_level < 500 else 3)

	# Always include lifesteal as the most common proc (10-20%)
	match proc_tier:
		1:
			bonuses.lifesteal_percent = 10
		2:
			bonuses.lifesteal_percent = 15
		3:
			bonuses.lifesteal_percent = 20

	# Second proc if available
	if num_procs >= 2:
		# Execute is the most impactful secondary proc
		match proc_tier:
			1:
				bonuses.execute_chance = 25
				bonuses.execute_bonus = 50
			2:
				bonuses.execute_chance = 28
				bonuses.execute_bonus = 65
			3:
				bonuses.execute_chance = 30
				bonuses.execute_bonus = 75

func _get_gear_level_for_quality(player_level: int, quality: GearQuality) -> int:
	"""Get item level based on player level and quality setting"""
	match quality:
		GearQuality.POOR:
			return max(1, player_level - 5)
		GearQuality.AVERAGE:
			return player_level
		GearQuality.GOOD:
			return int(player_level * 1.10)
		GearQuality.OPTIMAL:
			return int(player_level * 1.20)
		_:
			return player_level

func _get_rarity_for_quality(quality: GearQuality) -> String:
	"""Get rarity string based on quality setting"""
	match quality:
		GearQuality.POOR:
			return "common"
		GearQuality.AVERAGE:
			return "uncommon"
		GearQuality.GOOD:
			return "rare"
		GearQuality.OPTIMAL:
			return "epic"
		_:
			return "common"

func _get_effective_item_level(item_level: int) -> float:
	"""Apply diminishing returns for items above level 50.
	   Items 1-50: Full linear scaling
	   Items 51+: Logarithmic scaling (50 + 15 * log2(level - 49))
	   From character.gd lines 1028-1043"""
	if item_level <= 50:
		return float(item_level)
	# Above 50: diminishing returns using log scaling
	var excess = item_level - 49
	return 50.0 + 15.0 * log(excess) / log(2.0)

func get_quality_name(quality: GearQuality) -> String:
	"""Get display name for quality level"""
	match quality:
		GearQuality.POOR:
			return "poor"
		GearQuality.AVERAGE:
			return "average"
		GearQuality.GOOD:
			return "good"
		GearQuality.OPTIMAL:
			return "optimal"
		_:
			return "unknown"

static func quality_from_string(quality_str: String) -> GearQuality:
	"""Convert string to GearQuality enum"""
	match quality_str.to_lower():
		"poor":
			return GearQuality.POOR
		"average":
			return GearQuality.AVERAGE
		"good":
			return GearQuality.GOOD
		"optimal":
			return GearQuality.OPTIMAL
		_:
			return GearQuality.AVERAGE

static func get_all_qualities() -> Array:
	"""Get list of all quality levels as strings"""
	return ["poor", "average", "good"]
