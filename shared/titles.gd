# titles.gd
# Title system constants and definitions for Phantasia Revival
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
	"gold_bonus": 0.10,               # +10% gold find
	"description": "Knighted by the High King. Permanent until King dies or knights another."
}

# Mentee status (granted by Elder)
const MENTEE_STATUS = {
	"name": "Mentee",
	"color": "#DDA0DD",               # Plum
	"prefix": "[Mentee]",
	"xp_bonus": 0.30,                 # +30% XP
	"gold_bonus": 0.20,               # +20% gold find
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
		"description": "Donate 10,000,000 gold to the Shrine of Wealth.",
		"requirement": 10000000,
		"type": "gold_donated",
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

# Tax collector settings
const TAX_COLLECTOR = {
	"encounter_rate": 0.05,           # 5% chance per movement
	"tax_rate": 0.08,                 # 8% of current gold
	"minimum_gold": 100,              # Don't trigger if player has less than this
	"minimum_tax": 10                 # Minimum tax collected
}

# Tax collector encounter messages (randomly selected)
const TAX_ENCOUNTERS = [
	{
		"type": "quick",
		"messages": [
			"A Tax Collector steps forward. 'The realm requires its due.'",
			"You pay %d gold."
		]
	},
	{
		"type": "slip",
		"messages": [
			"A hooded figure steps from the shadows... but you slip past!",
			"The Tax Collector appears anyway. 'Nice try. The realm requires %d gold.'"
		],
		"delay": true
	},
	{
		"type": "negotiator",
		"messages": [
			"A well-dressed Tax Collector bows. 'Good citizen, the Crown requests a modest contribution.'",
			"'Your %d gold is noted. May fortune favor you.'",
			"[color=#00FF00]+5% gold find for 3 battles![/color]"
		],
		"bonus": {"type": "gold_find", "value": 5, "battles": 3}
	},
	{
		"type": "bumbling",
		"messages": [
			"A nervous Tax Collector fumbles with his ledger. 'Er, let me see... you owe...'",
			"'...%d gold! Yes, that's it. Sorry for the trouble.'"
		],
		"tax_modifier": 0.625  # Only takes 5% instead of 8%
	},
	{
		"type": "veteran",
		"messages": [
			"A scarred Tax Collector blocks your path. 'Don't even think about running.'",
			"'I've been doing this longer than you've been alive. %d gold. Now.'"
		],
		"tax_modifier": 1.25  # Takes 10% instead of 8%
	},
	{
		"type": "duo",
		"messages": [
			"Two Tax Collectors approach from opposite directions.",
			"'Nowhere to run!' laughs one. 'The realm requires %d gold,' says the other.",
			"They split your payment and vanish into the crowd."
		]
	}
]

# Title ruler immunity message
const TAX_IMMUNITY_MESSAGE = [
	"A Tax Collector approaches... then recognizes your sigil.",
	"'My %s! Forgive my intrusion. The realm prospers under your rule.'",
	"[color=#00FF00]He bows and leaves without collecting.[/color]"
]

# Title abilities - REVISED with economic costs
const JARL_ABILITIES = {
	"summon": {
		"name": "Summon",
		"gold_cost": 500,
		"resource": "none",
		"description": "Teleport a willing player to your location",
		"target": "player",
		"requires_consent": true
	},
	"tax_player": {
		"name": "Tax",
		"gold_cost": 1000,
		"resource": "none",
		"description": "Take 10% of target's gold (max 10,000)",
		"target": "player",
		"is_negative": true
	},
	"gift_silver": {
		"name": "Gift of Silver",
		"gold_cost_percent": 5,           # Costs 5% of your gold
		"gold_gift_percent": 8,           # Target receives 8% of your gold
		"resource": "none",
		"description": "Gift 8% of your gold to a player (costs 5%)",
		"target": "player"
	},
	"collect_tribute": {
		"name": "Collect Tribute",
		"gold_cost": 0,
		"resource": "none",
		"cooldown": 3600,                 # 1 hour cooldown
		"treasury_percent": 15,           # Collect 15% of realm treasury
		"description": "Collect 15% of realm treasury (1 hour cooldown)",
		"target": "self"
	}
}

const HIGH_KING_ABILITIES = {
	"knight": {
		"name": "Knight",
		"gold_cost": 50000,
		"gem_cost": 5,
		"resource": "none",
		"description": "Grant permanent Knight status (+15% dmg, +10% gold)",
		"target": "player"
	},
	"cure": {
		"name": "Cure",
		"gold_cost": 5000,
		"resource": "none",
		"description": "Remove all debuffs from a player",
		"target": "player"
	},
	"exile": {
		"name": "Exile",
		"gold_cost": 10000,
		"resource": "none",
		"description": "Teleport player 100 tiles in random direction",
		"target": "player",
		"is_negative": true
	},
	"royal_treasury": {
		"name": "Royal Treasury",
		"gold_cost": 0,
		"resource": "none",
		"cooldown": 7200,                 # 2 hour cooldown
		"treasury_percent": 30,           # Collect 30% of realm treasury
		"description": "Collect 30% of realm treasury (2 hour cooldown)",
		"target": "self"
	}
}

const ELDER_ABILITIES = {
	"heal_other": {
		"name": "Heal",
		"gold_cost": 10000,
		"resource": "none",
		"description": "Restore 50% HP to another player",
		"target": "player"
	},
	"mentor": {
		"name": "Mentor",
		"gold_cost": 500000,
		"gem_cost": 25,
		"resource": "none",
		"description": "Grant permanent Mentee status (+30% XP, +20% gold) to player below Lv500",
		"target": "player",
		"max_target_level": 500
	},
	"seek_flame": {
		"name": "Seek Flame",
		"gold_cost": 25000,
		"resource": "none",
		"description": "Check Eternal Pilgrimage progress",
		"target": "self"
	}
}

const ETERNAL_ABILITIES = {
	"restore": {
		"name": "Restore",
		"gold_cost": 50000,
		"resource": "none",
		"description": "Fully heal and cure all ailments",
		"target": "player"
	},
	"bless": {
		"name": "Bless",
		"gold_cost": 5000000,
		"gem_cost": 100,
		"resource": "none",
		"description": "Grant permanent +5 to a chosen stat",
		"target": "player"
	},
	"smite": {
		"name": "Smite",
		"gold_cost": 100000,
		"gem_cost": 10,
		"resource": "none",
		"description": "Curse target (25 poison, -25% damage for 10 rounds)",
		"target": "player",
		"is_negative": true
	},
	"guardian": {
		"name": "Guardian",
		"gold_cost": 2000000,
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

static func is_title_tax_immune(title_id: String) -> bool:
	"""Check if a title grants tax immunity"""
	var title_info = TITLE_DATA.get(title_id, {})
	return title_info.get("tax_immune", false)

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

	if ability.has("gold_cost") and ability.gold_cost > 0:
		parts.append("%s gold" % _format_number(ability.gold_cost))

	if ability.has("gold_cost_percent") and ability.gold_cost_percent > 0:
		parts.append("%d%% of your gold" % ability.gold_cost_percent)

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
