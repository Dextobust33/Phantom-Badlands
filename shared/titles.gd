# titles.gd
# Title system constants and definitions for Phantom Badlands
class_name Titles
extends Node

# Title Definitions
const TITLE_DATA = {
	"jarl": {
		"name": "Jarl",
		"color": "#C0C0C0",           # Silver
		"prefix": "[Jarl]",
		"min_level": 50,
		"max_level": 500,             # Lose title if exceed
		"requires_item": "jarls_ring",
		"requires_location": Vector2i(0, 0),  # The High Seat at Crossroads
		"unique": true,               # Only one allowed
		"tax_immune": true,           # Exempt from tax collectors
		"abuse_threshold": 8,         # Lose title at this many abuse points
		"description": "Chieftain of the realm. Claim The High Seat with a Jarl's Ring."
	},
	"high_king": {
		"name": "High King",
		"color": "#FFD700",           # Gold
		"prefix": "[High King]",
		"min_level": 200,
		"max_level": 1000,
		"requires_item": "crown_of_north",
		"requires_location": Vector2i(0, 0),  # The High Seat at Crossroads
		"unique": true,
		"replaces": "jarl",           # Claiming High King removes Jarl
		"tax_immune": true,           # Exempt from tax collectors
		"abuse_threshold": 15,        # Lose title at this many abuse points
		"description": "Supreme ruler. Forge the Crown of the North and claim The High Seat."
	},
	"elder": {
		"name": "Elder",
		"color": "#9400D3",           # Purple
		"prefix": "[Elder]",
		"min_level": 1000,
		"auto_grant": true,           # Automatically granted at level
		"unique": false,              # Multiple Elders allowed
		"description": "Ancient wisdom. Automatically granted at level 1000."
	},
	"eternal": {
		"name": "Eternal",
		"color": "#00FFFF",           # Cyan
		"prefix": "[Eternal]",
		"min_level": 1000,
		"max_count": 3,               # Up to 3 Eternals allowed
		"lives": 3,                   # Loses title after 3 deaths
		"description": "Immortal legend. Complete the Eternal Pilgrimage as an Elder."
	}
}

# Knight status (granted by High King)
const KNIGHT_STATUS = {
	"name": "Knight",
	"color": "#87CEEB",               # Light blue
	"prefix": "[Knight]",
	"damage_bonus": 0.15,             # +15% damage
	"market_bonus": 0.10,             # +10% market listing bonus
	"description": "Knighted by the High King. Permanent until King dies or knights another."
}

# Mentee status (granted by Elder)
const MENTEE_STATUS = {
	"name": "Mentee",
	"color": "#DDA0DD",               # Plum
	"prefix": "[Mentee]",
	"xp_bonus": 0.30,                 # +30% XP
	"extra_xp_bonus": 0.20,           # Additional +20% XP (was gold_bonus)
	"max_level": 500,                 # Can only mentor players below this level
	"description": "Mentored by an Elder. Permanent until Elder dies or mentors another."
}

# Title hierarchy (higher index = more powerful)
const TITLE_HIERARCHY = ["jarl", "high_king", "elder", "eternal"]

# Abuse point settings
const ABUSE_SETTINGS = {
	"same_target_window": 1800,       # 30 minutes in seconds
	"same_target_points": 3,          # Points for targeting same player within window
	"level_diff_threshold": 20,       # Level difference for "punching down"
	"level_diff_points": 2,           # Points for punching down
	"combat_interference_points": 3,  # Points for targeting player in combat
	"spam_window": 600,               # 10 minutes in seconds
	"spam_threshold": 3,              # Number of abilities before spam penalty
	"spam_points": 2,                 # Points for spamming
	"decay_rate": 1,                  # Points decayed per hour
	"decay_interval": 3600            # Seconds between decay (1 hour)
}

# Eternal Pilgrimage stages and requirements
const PILGRIMAGE_STAGES = {
	"awakening": {
		"name": "The Awakening",
		"description": "Slay 5,000 monsters to awaken the flame within.",
		"requirement": 5000,
		"type": "kills"
	},
	"trial_blood": {
		"name": "Trial of Blood",
		"description": "Defeat 1,000 Tier 8+ monsters (Level 250+).",
		"requirement": 1000,
		"type": "tier8_kills",
		"shrine_reward_stat": "strength",
		"shrine_reward_amount": 3
	},
	"trial_mind": {
		"name": "Trial of Mind",
		"description": "Outsmart 200 monsters.",
		"requirement": 200,
		"type": "outsmarts",
		"shrine_reward_stat": "wits",
		"shrine_reward_amount": 3
	},
	"trial_wealth": {
		"name": "Trial of Wealth",
		"description": "Donate 50,000 valor to the Shrine of Wealth.",
		"requirement": 50000,
		"type": "valor_donated",
		"shrine_reward_stat": "wisdom",
		"shrine_reward_amount": 3
	},
	"ember_hunt": {
		"name": "The Ember Hunt",
		"description": "Collect 500 Flame Embers from powerful monsters.",
		"requirement": 500,
		"type": "embers"
	},
	"crucible": {
		"name": "The Crucible",
		"description": "Complete a gauntlet of 10 consecutive Tier 9 boss fights.",
		"requirement": 10,
		"type": "crucible_bosses"
	}
}

# Pilgrimage stage order
const PILGRIMAGE_ORDER = ["awakening", "trial_blood", "trial_mind", "trial_wealth", "ember_hunt", "crucible"]

# Ember drop rates
const EMBER_DROP_RATES = {
	"tier8": {"chance": 0.10, "min": 1, "max": 1},      # 10% chance, 1 ember
	"tier9": {"chance": 0.25, "min": 1, "max": 3},      # 25% chance, 1-3 embers
	"rare": {"chance": 1.0, "min": 2, "max": 2},        # 100% from rare variants
	"boss": {"chance": 1.0, "min": 5, "max": 5}         # 100% from bosses, 5 embers
}

# Title items
const TITLE_ITEMS = {
	"jarls_ring": {
		"type": "jarls_ring",
		"name": "Jarl's Ring",
		"rarity": "legendary",
		"description": "An arm ring of silver and oath. Claim The High Seat at (0,0).",
		"is_title_item": true,
		"drop_level_min": 50,
		"drop_chance": 0.5  # 0.5% chance from level 50+ monsters
	},
	"unforged_crown": {
		"type": "unforged_crown",
		"name": "Unforged Crown",
		"rarity": "legendary",
		"description": "Take this to the Infernal Forge at Fire Mountain (-400,0).",
		"is_title_item": true,
		"drop_level_min": 200,
		"drop_chance": 0.2  # 0.2% chance from level 200+ monsters
	},
	"crown_of_north": {
		"type": "crown_of_north",
		"name": "Crown of the North",
		"rarity": "artifact",
		"description": "Forged in flame. Claim the throne of the High King at (0,0).",
		"is_title_item": true
	}
}

# Special locations for title system
const TITLE_LOCATIONS = {
	"high_seat": Vector2i(0, 0),        # Crossroads - where Jarls/High Kings claim power
	"infernal_forge": Vector2i(-400, 0) # Fire Mountain - where Crown is forged
}

# Title abilities - REVISED with valor costs
const JARL_ABILITIES = {
	"summon": {
		"name": "Summon",
		"valor_cost": 10,
		"resource": "none",
		"description": "Teleport a willing player to your location",
		"target": "player",
		"requires_consent": true,
		"is_negative": true
	},
	"tax_player": {
		"name": "Tax",
		"valor_cost": 20,
		"resource": "none",
		"description": "Take 5% of target's Valor (max 500)",
		"target": "player",
		"is_negative": true
	},
	"gift_valor": {
		"name": "Gift of Valor",
		"valor_cost_percent": 5,          # Costs 5% of your Valor
		"valor_gift_percent": 8,          # Target receives 8% of your Valor
		"resource": "none",
		"description": "Gift 8% of your Valor to a player (costs 5%)",
		"target": "player",
		"is_negative": true
	},
	"collect_tribute": {
		"name": "Collect Tribute",
		"valor_cost": 0,
		"resource": "none",
		"cooldown": 3600,                 # 1 hour cooldown
		"treasury_percent": 15,           # Collect 15% of realm treasury
		"description": "Collect 15% of realm treasury (1 hour cooldown)",
		"target": "self",
		"is_negative": true
	}
}

const HIGH_KING_ABILITIES = {
	"knight": {
		"name": "Knight",
		"valor_cost": 500,
		"gem_cost": 5,
		"resource": "none",
		"description": "Grant permanent Knight status (+15% dmg, +10% market)",
		"target": "player",
		"is_negative": true
	},
	"cure": {
		"name": "Cure",
		"valor_cost": 50,
		"resource": "none",
		"description": "Remove all debuffs from a player",
		"target": "player",
		"is_negative": true
	},
	"exile": {
		"name": "Exile",
		"valor_cost": 100,
		"resource": "none",
		"description": "Teleport player 100 tiles in random direction",
		"target": "player",
		"is_negative": true
	},
	"royal_treasury": {
		"name": "Royal Treasury",
		"valor_cost": 0,
		"resource": "none",
		"cooldown": 7200,                 # 2 hour cooldown
		"treasury_percent": 30,           # Collect 30% of realm treasury
		"description": "Collect 30% of realm treasury (2 hour cooldown)",
		"target": "self",
		"is_negative": true
	}
}

const ELDER_ABILITIES = {
	"heal_other": {
		"name": "Heal",
		"valor_cost": 100,
		"resource": "none",
		"description": "Restore 50% HP to another player",
		"target": "player"
	},
	"mentor": {
		"name": "Mentor",
		"valor_cost": 5000,
		"gem_cost": 25,
		"resource": "none",
		"description": "Grant permanent Mentee status (+50% XP) to player below Lv500",
		"target": "player",
		"max_target_level": 500
	},
	"seek_flame": {
		"name": "Seek Flame",
		"valor_cost": 25,
		"resource": "none",
		"description": "Check Eternal Pilgrimage progress",
		"target": "self"
	}
}

const ETERNAL_ABILITIES = {
	"restore": {
		"name": "Restore",
		"valor_cost": 500,
		"resource": "none",
		"description": "Fully heal and cure all ailments",
		"target": "player"
	},
	"bless": {
		"name": "Bless",
		"valor_cost": 50000,
		"gem_cost": 100,
		"resource": "none",
		"description": "Grant permanent +5 to a chosen stat",
		"target": "player"
	},
	"smite": {
		"name": "Smite",
		"valor_cost": 1000,
		"gem_cost": 10,
		"resource": "none",
		"description": "Curse target (25 poison, -25% damage for 10 rounds)",
		"target": "player",
		"is_negative": true
	},
	"guardian": {
		"name": "Guardian",
		"valor_cost": 20000,
		"gem_cost": 50,
		"resource": "none",
		"description": "Grant 1 permanent death save (until used)",
		"target": "player"
	}
}

static func get_title_info(title_id: String) -> Dictionary:
	"""Get title definition by ID"""
	return TITLE_DATA.get(title_id, {})

static func get_title_color(title_id: String) -> String:
	"""Get the display color for a title"""
	var info = TITLE_DATA.get(title_id, {})
	return info.get("color", "#FFFFFF")

static func get_title_prefix(title_id: String) -> String:
	"""Get the display prefix for a title"""
	var info = TITLE_DATA.get(title_id, {})
	return info.get("prefix", "")

static func get_title_name(title_id: String) -> String:
	"""Get the display name for a title"""
	var info = TITLE_DATA.get(title_id, {})
	return info.get("name", title_id.capitalize())

static func get_title_abilities(title_id: String) -> Dictionary:
	"""Get abilities available for a title"""
	match title_id:
		"jarl": return JARL_ABILITIES
		"high_king": return HIGH_KING_ABILITIES
		"elder": return ELDER_ABILITIES
		"eternal": return ETERNAL_ABILITIES
		_: return {}

static func format_titled_name(player_name: String, title_id: String) -> String:
	"""Format a player name with their title prefix and color"""
	if title_id.is_empty():
		return player_name
	var color = get_title_color(title_id)
	var prefix = get_title_prefix(title_id)
	return "[color=%s]%s[/color] %s" % [color, prefix, player_name]

static func can_claim_title(title_id: String, character, has_item: bool, at_location: bool) -> Dictionary:
	"""Check if a character can claim a title. Returns {can_claim: bool, reason: String}"""
	var title_info = TITLE_DATA.get(title_id, {})
	if title_info.is_empty():
		return {"can_claim": false, "reason": "Unknown title."}

	# Check level requirements
	var min_level = title_info.get("min_level", 0)
	var max_level = title_info.get("max_level", 999999)

	if character.level < min_level:
		return {"can_claim": false, "reason": "You must be at least level %d." % min_level}

	if character.level > max_level:
		return {"can_claim": false, "reason": "You are too powerful (max level %d)." % max_level}

	# Check item requirement
	if title_info.has("requires_item") and not title_info.get("auto_grant", false):
		if not has_item:
			var item_info = TITLE_ITEMS.get(title_info.requires_item, {})
			var item_name = item_info.get("name", title_info.requires_item)
			return {"can_claim": false, "reason": "You need a %s." % item_name}

	# Check location requirement
	if title_info.has("requires_location"):
		if not at_location:
			var loc = title_info.requires_location
			return {"can_claim": false, "reason": "You must be at The High Seat (%d,%d)." % [loc.x, loc.y]}

	return {"can_claim": true, "reason": ""}

static func get_item_for_title(title_id: String) -> String:
	"""Get the required item type for a title"""
	var title_info = TITLE_DATA.get(title_id, {})
	return title_info.get("requires_item", "")

static func get_abuse_threshold(title_id: String) -> int:
	"""Get the abuse point threshold for losing a title"""
	var title_info = TITLE_DATA.get(title_id, {})
	return title_info.get("abuse_threshold", 999)

static func get_pilgrimage_stage_info(stage_id: String) -> Dictionary:
	"""Get pilgrimage stage definition"""
	return PILGRIMAGE_STAGES.get(stage_id, {})

static func get_next_pilgrimage_stage(current_stage: String) -> String:
	"""Get the next stage in the pilgrimage"""
	var idx = PILGRIMAGE_ORDER.find(current_stage)
	if idx < 0 or idx >= PILGRIMAGE_ORDER.size() - 1:
		return ""
	return PILGRIMAGE_ORDER[idx + 1]

static func format_ability_cost(ability: Dictionary) -> String:
	"""Format the cost of an ability for display"""
	var parts = []

	if ability.has("valor_cost") and ability.valor_cost > 0:
		parts.append("%s valor" % _format_number(ability.valor_cost))

	if ability.has("valor_cost_percent") and ability.valor_cost_percent > 0:
		parts.append("%d%% of your valor" % ability.valor_cost_percent)

	if ability.has("gem_cost") and ability.gem_cost > 0:
		parts.append("%d gems" % ability.gem_cost)

	if ability.has("cooldown") and ability.cooldown > 0:
		var hours = ability.cooldown / 3600
		if hours >= 1:
			parts.append("%dhr CD" % hours)
		else:
			parts.append("%dmin CD" % (ability.cooldown / 60))

	if parts.is_empty():
		return "Free"

	return ", ".join(parts)

static func _format_number(num: int) -> String:
	"""Format a number with K/M suffixes for readability"""
	if num >= 1000000:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000:
		return "%.1fK" % (num / 1000.0)
	else:
		return str(num)
