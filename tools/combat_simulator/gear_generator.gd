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

func generate_gear_set(level: int, quality: GearQuality) -> Dictionary:
	"""Generate a full equipment set at the given level and quality.
	Includes base slot bonuses AND estimated affix contributions."""
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
		"speed": 0
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
	total_bonuses.speed += affix_bonuses.get("speed", 0)
	total_bonuses.strength += affix_bonuses.get("strength", 0)
	total_bonuses.constitution += affix_bonuses.get("constitution", 0)
	total_bonuses.dexterity += affix_bonuses.get("dexterity", 0)
	total_bonuses.intelligence += affix_bonuses.get("intelligence", 0)
	total_bonuses.wisdom += affix_bonuses.get("wisdom", 0)
	total_bonuses.wits += affix_bonuses.get("wits", 0)

	return total_bonuses

func _estimate_affix_bonuses(item_level: int, quality: GearQuality) -> Dictionary:
	"""Estimate total affix bonuses across all equipment slots.
	Uses average affix values and expected affix counts per quality level."""
	var bonuses = {
		"attack": 0,
		"defense": 0,
		"max_hp": 0,
		"max_mana": 0,
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
	# Combat stats (attack, defense, hp) are most common (~60%)
	# Other stats make up the rest (~40%)
	var combat_affixes = int(total_affixes * 0.6)
	var other_affixes = total_affixes - combat_affixes

	# Calculate average affix value for this level
	# attack_bonus: base 4.5 + 0.83 * level
	var avg_attack = int(AFFIX_AVG_VALUES.attack_bonus.base + AFFIX_AVG_VALUES.attack_bonus.per_level * item_level)
	var avg_defense = int(AFFIX_AVG_VALUES.defense_bonus.base + AFFIX_AVG_VALUES.defense_bonus.per_level * item_level)
	var avg_hp = int(AFFIX_AVG_VALUES.hp_bonus.base + AFFIX_AVG_VALUES.hp_bonus.per_level * item_level)
	var avg_speed = int(AFFIX_AVG_VALUES.speed_bonus.base + AFFIX_AVG_VALUES.speed_bonus.per_level * item_level)
	var avg_stat = int(AFFIX_AVG_VALUES.str_bonus.base + AFFIX_AVG_VALUES.str_bonus.per_level * item_level)

	# Distribute combat affixes (roughly equal between attack, defense, HP)
	var attack_affixes = int(combat_affixes / 3.0)
	var defense_affixes = int(combat_affixes / 3.0)
	var hp_affixes = combat_affixes - attack_affixes - defense_affixes

	bonuses.attack = attack_affixes * avg_attack
	bonuses.defense = defense_affixes * avg_defense
	bonuses.max_hp = hp_affixes * avg_hp

	# Distribute other affixes (speed, mana, stats)
	var speed_affixes = int(other_affixes * 0.3)
	var stat_affixes = other_affixes - speed_affixes

	bonuses.speed = speed_affixes * avg_speed

	# Spread stat affixes across primary stats
	if stat_affixes > 0:
		var per_stat = max(1, int(stat_affixes / 3.0))
		bonuses.strength = per_stat * avg_stat
		bonuses.constitution = per_stat * avg_stat
		bonuses.dexterity = per_stat * avg_stat

	return bonuses

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
