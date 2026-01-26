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
		"requires_item": "eternal_flame",
		"max_count": 3,               # Up to 3 Eternals allowed
		"lives": 3,                   # Loses title after 3 deaths
		"description": "Immortal legend. Find the Eternal Flame as an Elder."
	}
}

# Title hierarchy (higher index = more powerful)
const TITLE_HIERARCHY = ["jarl", "high_king", "elder", "eternal"]

# Title items
const TITLE_ITEMS = {
	"jarls_ring": {
		"type": "jarls_ring",
		"name": "Jarl's Ring",
		"rarity": "legendary",
		"description": "An arm ring of silver and oath. Claim The High Seat at (0,0).",
		"is_title_item": true,
		"drop_level_min": 100,
		"drop_chance": 0.5  # 0.5% chance from level 100+ monsters
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

# Title abilities
const JARL_ABILITIES = {
	"banish": {
		"name": "Banish",
		"cost": 50,
		"resource": "mana",
		"description": "Relocate a player randomly (50 tiles)",
		"target": "player"
	},
	"curse": {
		"name": "Curse",
		"cost": 30,
		"resource": "mana",
		"description": "Apply 5 poison + drain 20% energy to target",
		"target": "player"
	},
	"gift_silver": {
		"name": "Gift of Silver",
		"cost": 5,
		"resource": "gems",
		"description": "Give 5000 gold to a player",
		"target": "player"
	},
	"claim_tribute": {
		"name": "Claim Tribute",
		"cost": 0,
		"resource": "none",
		"description": "Collect 10% of realm treasury",
		"target": "self"
	}
}

const HIGH_KING_ABILITIES = {
	"exile": {
		"name": "Exile",
		"cost": 100,
		"resource": "mana",
		"description": "Teleport player to random edge (200 tiles)",
		"target": "player"
	},
	"knight": {
		"name": "Knight",
		"cost": 50,
		"resource": "mana",
		"description": "Grant +25% damage buff (10 battles) to player",
		"target": "player"
	},
	"cure": {
		"name": "Cure",
		"cost": 75,
		"resource": "mana",
		"description": "Remove all debuffs from a player",
		"target": "player"
	},
	"royal_decree": {
		"name": "Royal Decree",
		"cost": 0,
		"resource": "none",
		"description": "Broadcast message to all players",
		"target": "self"
	}
}

const ELDER_ABILITIES = {
	"heal_other": {
		"name": "Heal",
		"cost": 25,
		"resource": "mana_percent",
		"description": "Restore 50% HP to another player",
		"target": "player"
	},
	"seek_flame": {
		"name": "Seek Flame",
		"cost": 50,
		"resource": "mana_percent",
		"description": "Reveal distance to Eternal Flame",
		"target": "self"
	},
	"slap": {
		"name": "Slap",
		"cost": 10,
		"resource": "mana_percent",
		"description": "Relocate player 20 tiles",
		"target": "player"
	}
}

const ETERNAL_ABILITIES = {
	"smite": {
		"name": "Smite",
		"cost": 25,
		"resource": "mana_percent",
		"description": "Devastating curse (50 poison, -50% stats, 5 rounds)",
		"target": "player"
	},
	"restore": {
		"name": "Restore",
		"cost": 25,
		"resource": "mana_percent",
		"description": "Fully heal and cure all ailments",
		"target": "player"
	},
	"bless": {
		"name": "Bless",
		"cost": 1,
		"resource": "lives",
		"description": "Grant permanent +5 to random stat",
		"target": "player"
	},
	"proclaim": {
		"name": "Proclaim",
		"cost": 0,
		"resource": "none",
		"description": "Global broadcast (special formatting)",
		"target": "self"
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
