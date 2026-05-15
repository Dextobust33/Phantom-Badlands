# trading_post_database.gd
# Trading Post definitions and helper functions
class_name TradingPostDatabase
extends Node

# Trading Post data structure:
# {
#   "id": String,
#   "name": String,
#   "center": Vector2i,
#   "size": int (3 or 5 - creates square),
#   "quest_giver": String,
#   "quest_focus": String,
#   "description": String
# }

# All Trading Posts in the game world
const TRADING_POSTS = {
	# ============================================
	# CORE ZONE (0-30 distance) - Level 1-30, Very Safe
	# High density - new players never far from safety
	# ============================================
	"haven": {
		"id": "haven",
		"name": "Haven",
		"center": Vector2i(0, 10),
		"size": 5,
		"quest_giver": "Guard Captain",
		"quest_focus": "beginner",
		"description": "A fortified sanctuary for new adventurers. The Guard Captain trains recruits here."
	},
	"crossroads": {
		"id": "crossroads",
		"name": "Crossroads",
		"center": Vector2i(0, 0),
		"size": 3,
		"quest_giver": "Royal Herald",
		"quest_focus": "hotzone",
		"description": "The central hub of the realm. The Royal Herald posts daily bounties for brave souls."
	},
	"south_gate": {
		"id": "south_gate",
		"name": "South Gate",
		"center": Vector2i(0, -25),
		"size": 3,
		"quest_giver": "Gate Warden",
		"quest_focus": "beginner",
		"description": "The southern entrance to Haven's territory. The Gate Warden guides newcomers."
	},
	"east_market": {
		"id": "east_market",
		"name": "East Market",
		"center": Vector2i(25, 10),
		"size": 3,
		"quest_giver": "Market Master",
		"quest_focus": "collection",
		"description": "A bustling marketplace east of Haven. The Market Master always needs supplies."
	},
	"west_shrine": {
		"id": "west_shrine",
		"name": "West Shrine",
		"center": Vector2i(-25, 10),
		"size": 3,
		"quest_giver": "Shrine Keeper",
		"quest_focus": "beginner",
		"description": "A sacred shrine west of Haven. The Keeper teaches the ways of the realm."
	},

	# ============================================
	# INNER ZONE (30-75 distance) - Level 30-75
	# Good density - learning the ropes
	# ============================================
	"northeast_farm": {
		"id": "northeast_farm",
		"name": "Northeast Farm",
		"center": Vector2i(40, 40),
		"size": 3,
		"quest_giver": "Farmer Giles",
		"quest_focus": "pest_control",
		"description": "A hardy farm on the northeastern outskirts. Farmer Giles needs help with pests."
	},
	"northwest_mill": {
		"id": "northwest_mill",
		"name": "Northwest Mill",
		"center": Vector2i(-40, 40),
		"size": 3,
		"quest_giver": "Miller Tom",
		"quest_focus": "delivery",
		"description": "An old mill in the northwest. Miller Tom trades with nearby settlements."
	},
	"southeast_mine": {
		"id": "southeast_mine",
		"name": "Southeast Mine",
		"center": Vector2i(45, -35),
		"size": 3,
		"quest_giver": "Mine Foreman",
		"quest_focus": "gathering",
		"description": "A productive mine southeast of Crossroads. The Foreman needs brave escorts."
	},
	"southwest_grove": {
		"id": "southwest_grove",
		"name": "Southwest Grove",
		"center": Vector2i(-45, -35),
		"size": 3,
		"quest_giver": "Grove Tender",
		"quest_focus": "nature",
		"description": "A mystical grove in the southwest. The Tender protects the ancient trees."
	},
	"northwatch": {
		"id": "northwatch",
		"name": "Northwatch",
		"center": Vector2i(0, 75),
		"size": 3,
		"quest_giver": "Scout Leader",
		"quest_focus": "scouting",
		"description": "A watchtower overlooking the northern plains. Scout Leader Mira trains reconnaissance experts."
	},
	"eastern_camp": {
		"id": "eastern_camp",
		"name": "Eastern Camp",
		"center": Vector2i(75, 0),
		"size": 3,
		"quest_giver": "Camp Commander",
		"quest_focus": "combat",
		"description": "A military encampment on the eastern road. The Commander drills soldiers daily."
	},
	"western_refuge": {
		"id": "western_refuge",
		"name": "Western Refuge",
		"center": Vector2i(-75, 0),
		"size": 3,
		"quest_giver": "Hermit Sage",
		"quest_focus": "wisdom",
		"description": "A peaceful sanctuary in the western woods. The Hermit Sage offers guidance to seekers."
	},
	"southern_watch": {
		"id": "southern_watch",
		"name": "Southern Watch",
		"center": Vector2i(0, -65),
		"size": 3,
		"quest_giver": "Watch Commander",
		"quest_focus": "patrol",
		"description": "A defensive position watching the southern approaches. The Commander assigns patrol routes."
	},
	"northeast_tower": {
		"id": "northeast_tower",
		"name": "Northeast Tower",
		"center": Vector2i(55, 55),
		"size": 3,
		"quest_giver": "Tower Warden",
		"quest_focus": "vigilance",
		"description": "A tall watchtower in the northeast. The Warden spots threats from afar."
	},
	"northwest_inn": {
		"id": "northwest_inn",
		"name": "Northwest Inn",
		"center": Vector2i(-55, 55),
		"size": 3,
		"quest_giver": "Innkeeper",
		"quest_focus": "rumors",
		"description": "A cozy inn in the northwest. The Innkeeper hears all the local gossip."
	},
	"southeast_bridge": {
		"id": "southeast_bridge",
		"name": "Southeast Bridge",
		"center": Vector2i(60, -50),
		"size": 3,
		"quest_giver": "Bridge Guard",
		"quest_focus": "protection",
		"description": "A fortified bridge crossing in the southeast. The Guard protects travelers."
	},
	"southwest_temple": {
		"id": "southwest_temple",
		"name": "Southwest Temple",
		"center": Vector2i(-60, -50),
		"size": 3,
		"quest_giver": "Temple Priest",
		"quest_focus": "cleansing",
		"description": "An ancient temple in the southwest. The Priest fights corruption."
	},

	# Mid Zone (Level 50-200 areas)
	"frostgate": {
		"id": "frostgate",
		"name": "Frostgate",
		"center": Vector2i(0, -100),
		"size": 3,
		"quest_giver": "Guild Master",
		"quest_focus": "exploration",
		"description": "A northern outpost built into the frozen cliffs. The Guild Master organizes expeditions."
	},
	"highland_post": {
		"id": "highland_post",
		"name": "Highland Post",
		"center": Vector2i(0, 150),
		"size": 3,
		"quest_giver": "Mountain Guide",
		"quest_focus": "climbing",
		"description": "A sturdy outpost in the northern highlands. The Mountain Guide knows every peak."
	},
	"eastwatch": {
		"id": "eastwatch",
		"name": "Eastwatch",
		"center": Vector2i(150, 0),
		"size": 3,
		"quest_giver": "Bounty Hunter",
		"quest_focus": "kill",
		"description": "A fortress overlooking the eastern wilderness. Bounty Hunter Kira tracks dangerous prey."
	},
	"westhold": {
		"id": "westhold",
		"name": "Westhold",
		"center": Vector2i(-150, 0),
		"size": 3,
		"quest_giver": "Veteran Warrior",
		"quest_focus": "survival",
		"description": "A rugged stronghold on the western frontier. Old warriors share their hard-won wisdom here."
	},
	"southport": {
		"id": "southport",
		"name": "Southport",
		"center": Vector2i(0, -150),
		"size": 3,
		"quest_giver": "Sea Captain",
		"quest_focus": "collection",
		"description": "A trading port on the southern coast. Captain Vex knows the seas and their treasures."
	},
	"northeast_bastion": {
		"id": "northeast_bastion",
		"name": "Northeast Bastion",
		"center": Vector2i(120, 120),
		"size": 3,
		"quest_giver": "Bastion Commander",
		"quest_focus": "defense",
		"description": "A defensive fortress in the northeastern reaches. The Commander holds the line."
	},
	"northwest_lodge": {
		"id": "northwest_lodge",
		"name": "Northwest Lodge",
		"center": Vector2i(-120, 120),
		"size": 3,
		"quest_giver": "Lodge Keeper",
		"quest_focus": "hunting",
		"description": "A hunting lodge in the northwestern forests. The Lodge Keeper tracks legendary beasts."
	},
	"southeast_outpost": {
		"id": "southeast_outpost",
		"name": "Southeast Outpost",
		"center": Vector2i(120, -120),
		"size": 3,
		"quest_giver": "Outpost Warden",
		"quest_focus": "patrol",
		"description": "A border outpost in the southeastern wilds. The Warden patrols dangerous territory."
	},
	"southwest_camp": {
		"id": "southwest_camp",
		"name": "Southwest Camp",
		"center": Vector2i(-120, -120),
		"size": 3,
		"quest_giver": "Ranger Captain",
		"quest_focus": "tracking",
		"description": "A ranger camp in the southwestern badlands. The Captain tracks threats from afar."
	},

	# Mid-Outer Zone (Level 150-300 areas) - Bridge between mid and outer
	"far_east_station": {
		"id": "far_east_station",
		"name": "Far East Station",
		"center": Vector2i(250, 0),
		"size": 3,
		"quest_giver": "Station Master",
		"quest_focus": "expeditions",
		"description": "A remote station on the far eastern frontier. The Station Master supplies brave explorers."
	},
	"far_west_haven": {
		"id": "far_west_haven",
		"name": "Far West Haven",
		"center": Vector2i(-250, 0),
		"size": 3,
		"quest_giver": "Haven Watcher",
		"quest_focus": "vigilance",
		"description": "A fortified haven on the far western edge. The Watcher guards against what lies beyond."
	},
	"deep_south_port": {
		"id": "deep_south_port",
		"name": "Deep South Port",
		"center": Vector2i(0, -275),
		"size": 3,
		"quest_giver": "Harbor Master",
		"quest_focus": "maritime",
		"description": "A harbor at the edge of known waters. The Harbor Master knows secrets of the deep."
	},
	"high_north_peak": {
		"id": "high_north_peak",
		"name": "High North Peak",
		"center": Vector2i(0, 250),
		"size": 3,
		"quest_giver": "Peak Warden",
		"quest_focus": "altitude",
		"description": "A watchtower on the highest northern peak. The Peak Warden sees all approaches."
	},
	"northeast_frontier": {
		"id": "northeast_frontier",
		"name": "Northeast Frontier",
		"center": Vector2i(200, 200),
		"size": 3,
		"quest_giver": "Frontier Marshal",
		"quest_focus": "expansion",
		"description": "The furthest northeast settlement. The Marshal pushes the boundaries of civilization."
	},
	"northwest_citadel": {
		"id": "northwest_citadel",
		"name": "Northwest Citadel",
		"center": Vector2i(-200, 200),
		"size": 3,
		"quest_giver": "Citadel Lord",
		"quest_focus": "fortification",
		"description": "An ancient citadel in the northwest. The Lord maintains defenses against ancient evils."
	},
	"southeast_garrison": {
		"id": "southeast_garrison",
		"name": "Southeast Garrison",
		"center": Vector2i(200, -200),
		"size": 3,
		"quest_giver": "Garrison General",
		"quest_focus": "military",
		"description": "A military garrison in the southeast. The General commands elite forces."
	},
	"southwest_fortress": {
		"id": "southwest_fortress",
		"name": "Southwest Fortress",
		"center": Vector2i(-200, -200),
		"size": 3,
		"quest_giver": "Fortress Commander",
		"quest_focus": "siege",
		"description": "A massive fortress in the southwest. The Commander withstands all assaults."
	},

	# Outer Zone (Level 200+ dangerous areas)
	"shadowmere": {
		"id": "shadowmere",
		"name": "Shadowmere",
		"center": Vector2i(300, 300),
		"size": 5,
		"quest_giver": "Dark Warden",
		"quest_focus": "challenge",
		"description": "A hidden fortress in the shadow realm. The Dark Warden tests only the worthy."
	},
	"inferno_outpost": {
		"id": "inferno_outpost",
		"name": "Inferno Outpost",
		"center": Vector2i(-350, 0),
		"size": 3,
		"quest_giver": "Flame Keeper",
		"quest_focus": "fire",
		"description": "A heat-resistant bastion near Fire Mountain. The Flame Keeper guards volcanic secrets."
	},
	"voids_edge": {
		"id": "voids_edge",
		"name": "Void's Edge",
		"center": Vector2i(350, 0),
		"size": 3,
		"quest_giver": "Shadow Watcher",
		"quest_focus": "void",
		"description": "An outpost at the boundary of reality. The Shadow Watcher peers into the abyss."
	},
	"frozen_reach": {
		"id": "frozen_reach",
		"name": "Frozen Reach",
		"center": Vector2i(0, -400),
		"size": 3,
		"quest_giver": "Frost Hermit",
		"quest_focus": "extreme",
		"description": "The most remote trading post, buried in eternal ice. The Frost Hermit offers extreme challenges."
	},
	"abyssal_depths": {
		"id": "abyssal_depths",
		"name": "Abyssal Depths",
		"center": Vector2i(-300, -300),
		"size": 3,
		"quest_giver": "Depth Walker",
		"quest_focus": "abyss",
		"description": "A station at the edge of the abyss. The Depth Walker has seen things beyond mortal ken."
	},
	"celestial_spire": {
		"id": "celestial_spire",
		"name": "Celestial Spire",
		"center": Vector2i(-300, 300),
		"size": 3,
		"quest_giver": "Star Keeper",
		"quest_focus": "celestial",
		"description": "A tower reaching toward the heavens. The Star Keeper reads the fates in the stars."
	},
	"storm_peak": {
		"id": "storm_peak",
		"name": "Storm Peak",
		"center": Vector2i(0, 350),
		"size": 3,
		"quest_giver": "Storm Caller",
		"quest_focus": "elemental",
		"description": "A peak eternally wreathed in lightning. The Storm Caller commands the tempest."
	},
	"dragons_rest": {
		"id": "dragons_rest",
		"name": "Dragon's Rest",
		"center": Vector2i(300, -300),
		"size": 5,
		"quest_giver": "Dragon Sage",
		"quest_focus": "legendary",
		"description": "An ancient sanctuary where dragons once slumbered. The Dragon Sage guards their legacy."
	},

	# ============================================
	# EXTREME ZONE (500-700 distance) - Level 500+
	# Very sparse - only the most dangerous territories
	# ============================================
	"primordial_sanctum": {
		"id": "primordial_sanctum",
		"name": "Primordial Sanctum",
		"center": Vector2i(0, 500),
		"size": 5,
		"quest_giver": "Ancient One",
		"quest_focus": "primordial",
		"description": "A sanctum from before recorded history. The Ancient One remembers the first days."
	},
	"nether_gate": {
		"id": "nether_gate",
		"name": "Nether Gate",
		"center": Vector2i(0, -550),
		"size": 3,
		"quest_giver": "Gate Keeper",
		"quest_focus": "nether",
		"description": "A gate to realms unknown. The Gate Keeper guards the boundary between worlds."
	},
	"eastern_terminus": {
		"id": "eastern_terminus",
		"name": "Eastern Terminus",
		"center": Vector2i(500, 0),
		"size": 3,
		"quest_giver": "Edge Walker",
		"quest_focus": "terminus",
		"description": "The furthest eastern point of civilization. The Edge Walker maps the unknown."
	},
	"western_terminus": {
		"id": "western_terminus",
		"name": "Western Terminus",
		"center": Vector2i(-500, 0),
		"size": 3,
		"quest_giver": "Boundary Warden",
		"quest_focus": "terminus",
		"description": "The furthest western point of civilization. The Boundary Warden holds the line."
	},
	"chaos_refuge": {
		"id": "chaos_refuge",
		"name": "Chaos Refuge",
		"center": Vector2i(400, 400),
		"size": 3,
		"quest_giver": "Chaos Tamer",
		"quest_focus": "chaos",
		"description": "An island of order in chaotic lands. The Chaos Tamer brings stability."
	},
	"entropy_station": {
		"id": "entropy_station",
		"name": "Entropy Station",
		"center": Vector2i(-400, -400),
		"size": 3,
		"quest_giver": "Entropy Scholar",
		"quest_focus": "entropy",
		"description": "A station studying the decay of reality. The Scholar seeks to understand the end."
	},
	"oblivion_watch": {
		"id": "oblivion_watch",
		"name": "Oblivion Watch",
		"center": Vector2i(-450, 400),
		"size": 3,
		"quest_giver": "Void Sentinel",
		"quest_focus": "oblivion",
		"description": "A watchtower overlooking the void. The Void Sentinel guards against nothingness."
	},
	"genesis_point": {
		"id": "genesis_point",
		"name": "Genesis Point",
		"center": Vector2i(450, -400),
		"size": 3,
		"quest_giver": "Creation Sage",
		"quest_focus": "genesis",
		"description": "Where new realities are born. The Creation Sage harnesses primordial power."
	},

	# ============================================
	# WORLD'S EDGE (700+ distance) - Level 700+
	# The absolute frontier - very sparse
	# ============================================
	"world_spine_north": {
		"id": "world_spine_north",
		"name": "World's Spine North",
		"center": Vector2i(0, 700),
		"size": 5,
		"quest_giver": "Titan Keeper",
		"quest_focus": "titan",
		"description": "A fortress at the northern edge of the world. The Titan Keeper commands godlike power."
	},
	"world_spine_south": {
		"id": "world_spine_south",
		"name": "World's Spine South",
		"center": Vector2i(0, -700),
		"size": 5,
		"quest_giver": "Abyssal Lord",
		"quest_focus": "abyssal",
		"description": "A fortress at the southern edge of the world. The Abyssal Lord rules the depths."
	},
	"eternal_east": {
		"id": "eternal_east",
		"name": "Eternal East",
		"center": Vector2i(700, 0),
		"size": 3,
		"quest_giver": "Dawn Herald",
		"quest_focus": "eternal",
		"description": "Where the sun rises eternally. The Dawn Herald commands the light."
	},
	"eternal_west": {
		"id": "eternal_west",
		"name": "Eternal West",
		"center": Vector2i(-700, 0),
		"size": 3,
		"quest_giver": "Dusk Warden",
		"quest_focus": "eternal",
		"description": "Where the sun sets eternally. The Dusk Warden guards the twilight."
	},
	"apex_northeast": {
		"id": "apex_northeast",
		"name": "Apex Northeast",
		"center": Vector2i(550, 550),
		"size": 3,
		"quest_giver": "Apex Hunter",
		"quest_focus": "apex",
		"description": "A hunting lodge for the ultimate predators. The Apex Hunter tracks godbeasts."
	},
	"apex_southeast": {
		"id": "apex_southeast",
		"name": "Apex Southeast",
		"center": Vector2i(550, -550),
		"size": 3,
		"quest_giver": "Storm Breaker",
		"quest_focus": "apex",
		"description": "A fortress that defies the elements. The Storm Breaker conquers nature itself."
	},
	"apex_northwest": {
		"id": "apex_northwest",
		"name": "Apex Northwest",
		"center": Vector2i(-550, 550),
		"size": 3,
		"quest_giver": "Reality Weaver",
		"quest_focus": "apex",
		"description": "A sanctum where reality bends. The Reality Weaver shapes existence."
	},
	"apex_southwest": {
		"id": "apex_southwest",
		"name": "Apex Southwest",
		"center": Vector2i(-550, -550),
		"size": 3,
		"quest_giver": "Doom Prophet",
		"quest_focus": "apex",
		"description": "A temple to the end times. The Doom Prophet sees all possible futures."
	}
}

# Cache for fast tile lookups (built on initialization)
var _tile_cache: Dictionary = {}
var _initialized: bool = false

func _ready():
	_build_tile_cache()

func _build_tile_cache():
	"""Build a dictionary mapping tile coordinates to trading post IDs for fast lookup"""
	_tile_cache.clear()

	for post_id in TRADING_POSTS:
		var post = TRADING_POSTS[post_id]
		var center = post.center
		var half_size = post.size / 2

		# Add all tiles in the trading post area to the cache
		for dx in range(-half_size, half_size + 1):
			for dy in range(-half_size, half_size + 1):
				var tile = Vector2i(center.x + dx, center.y + dy)
				_tile_cache[tile] = post_id

	_initialized = true

func is_trading_post_tile(x: int, y: int) -> bool:
	"""Check if the given coordinates are part of any Trading Post"""
	if not _initialized:
		_build_tile_cache()
	return _tile_cache.has(Vector2i(x, y))

func get_trading_post_at(x: int, y: int) -> Dictionary:
	"""Get Trading Post data if the tile is part of one, empty dict otherwise"""
	if not _initialized:
		_build_tile_cache()

	var tile = Vector2i(x, y)
	if _tile_cache.has(tile):
		var post_id = _tile_cache[tile]
		return TRADING_POSTS[post_id].duplicate(true)
	return {}

func get_trading_post_by_id(post_id: String) -> Dictionary:
	"""Get Trading Post data by ID"""
	if TRADING_POSTS.has(post_id):
		return TRADING_POSTS[post_id].duplicate(true)
	return {}

# ============================================
# CATEGORY & COLOR SYSTEM
# Maps each post to a visual category for map colors and art
# ============================================

const POST_CATEGORIES = {
	# Core Zone
	"haven": "haven", "crossroads": "market", "south_gate": "fortress",
	"east_market": "market", "west_shrine": "shrine",
	# Inner Zone
	"northeast_farm": "farm", "northwest_mill": "farm", "southeast_mine": "mine",
	"southwest_grove": "farm", "northwatch": "tower", "eastern_camp": "camp",
	"western_refuge": "camp", "southern_watch": "tower", "northeast_tower": "tower",
	"northwest_inn": "camp", "southeast_bridge": "fortress", "southwest_temple": "shrine",
	# Mid Zone
	"frostgate": "fortress", "highland_post": "tower", "eastwatch": "tower",
	"westhold": "fortress", "southport": "fortress", "northeast_bastion": "fortress",
	"northwest_lodge": "camp", "southeast_outpost": "camp", "southwest_camp": "camp",
	# Mid-Outer Zone
	"far_east_station": "camp", "far_west_haven": "haven", "deep_south_port": "fortress",
	"high_north_peak": "tower", "northeast_frontier": "camp", "northwest_citadel": "fortress",
	"southeast_garrison": "fortress", "southwest_fortress": "fortress",
	# Outer Zone
	"shadowmere": "exotic", "inferno_outpost": "mine", "voids_edge": "exotic",
	"frozen_reach": "exotic", "abyssal_depths": "exotic", "celestial_spire": "shrine",
	"storm_peak": "exotic", "dragons_rest": "exotic",
	# Extreme Zone
	"primordial_sanctum": "shrine", "nether_gate": "exotic", "eastern_terminus": "tower",
	"western_terminus": "tower", "chaos_refuge": "exotic", "entropy_station": "exotic",
	"oblivion_watch": "tower", "genesis_point": "shrine",
	# World's Edge
	"world_spine_north": "fortress", "world_spine_south": "fortress",
	"eternal_east": "exotic", "eternal_west": "exotic",
	"apex_northeast": "exotic", "apex_southeast": "exotic",
	"apex_northwest": "exotic", "apex_southwest": "exotic",
}

const POST_MAP_COLORS = {
	"haven":    {"center": "#FFD700", "edge": "#B8860B", "interior": "#8B7500"},
	"market":   {"center": "#FF8C00", "edge": "#DAA520", "interior": "#B8860B"},
	"shrine":   {"center": "#E6E6FA", "edge": "#9370DB", "interior": "#7B68AE"},
	"farm":     {"center": "#90EE90", "edge": "#8FBC8F", "interior": "#6B8E6B"},
	"mine":     {"center": "#CD853F", "edge": "#A0522D", "interior": "#8B4513"},
	"tower":    {"center": "#B0C4DE", "edge": "#6A8EAE", "interior": "#5A7A94"},
	"camp":     {"center": "#DEB887", "edge": "#CD853F", "interior": "#A0704B"},
	"exotic":   {"center": "#DA70D6", "edge": "#9932CC", "interior": "#7B28A0"},
	"fortress": {"center": "#C0C0C0", "edge": "#808080", "interior": "#606060"},
	"default":  {"center": "#FFD700", "edge": "#D2B48C", "interior": "#C4A84B"},
}

# ============================================
# REGION TIER SYSTEM (post-anchored world model — Slice 1)
# Each post is classified T1-T7 by its zone. Future slices use this
# tier as the anchor for local monster difficulty (vs current radial
# distance-from-origin). Slice 1 is data + visibility only.
# See memory/project_audit_10_world.md for the full direction.
# ============================================

const POST_TIERS = {
	# Core Zone (T1) — starter haven, near 0,0
	"haven": 1, "crossroads": 1, "south_gate": 1, "east_market": 1, "west_shrine": 1,
	# Inner Zone (T2)
	"northeast_farm": 2, "northwest_mill": 2, "southeast_mine": 2, "southwest_grove": 2,
	"northwatch": 2, "eastern_camp": 2, "western_refuge": 2, "southern_watch": 2,
	"northeast_tower": 2, "northwest_inn": 2, "southeast_bridge": 2, "southwest_temple": 2,
	# Mid Zone (T3)
	"frostgate": 3, "highland_post": 3, "eastwatch": 3, "westhold": 3, "southport": 3,
	"northeast_bastion": 3, "northwest_lodge": 3, "southeast_outpost": 3, "southwest_camp": 3,
	# Mid-Outer Zone (T4)
	"far_east_station": 4, "far_west_haven": 4, "deep_south_port": 4, "high_north_peak": 4,
	"northeast_frontier": 4, "northwest_citadel": 4, "southeast_garrison": 4, "southwest_fortress": 4,
	# Outer Zone (T5)
	"shadowmere": 5, "inferno_outpost": 5, "voids_edge": 5, "frozen_reach": 5,
	"abyssal_depths": 5, "celestial_spire": 5, "storm_peak": 5, "dragons_rest": 5,
	# Extreme Zone (T6)
	"primordial_sanctum": 6, "nether_gate": 6, "eastern_terminus": 6, "western_terminus": 6,
	"chaos_refuge": 6, "entropy_station": 6, "oblivion_watch": 6, "genesis_point": 6,
	# World's Edge (T7) — apex content frontier
	"world_spine_north": 7, "world_spine_south": 7, "eternal_east": 7, "eternal_west": 7,
	"apex_northeast": 7, "apex_southeast": 7, "apex_northwest": 7, "apex_southwest": 7,
}

const POST_TIER_NAMES = {
	1: "Core",
	2: "Inner",
	3: "Mid",
	4: "Mid-Outer",
	5: "Outer",
	6: "Extreme",
	7: "World's Edge",
}

const POST_TIER_COLORS = {
	1: "#00FF00",  # green — safe
	2: "#88FF00",  # yellow-green
	3: "#FFFF00",  # yellow
	4: "#FFAA00",  # orange
	5: "#FF6600",  # red-orange
	6: "#FF0000",  # red — extreme
	7: "#AA00FF",  # purple — world's edge
}

# Audit #10 Slice 6L — Region naming moved off legacy fixed posts onto the
# procedurally-generated NPC posts (see npc_post_database.gd + chunk_manager
# .get_nearest_npc_post_with_tier). Names now survive map wipes because they
# live on the post itself, not on a constant keyed by post_id.

# ============================================
# REGIONAL POST SPECIALIZATION (Audit #9 Slice 3)
# Each post category gives a buy discount on a specialty item supply category.
# Encourages travel — go to a mine post to buy materials cheaper, a farm for
# food/consumables, a shrine for runes, a fortress for equipment.
# Discounts stack ON TOP of the base supply-markup. Sellers still receive base
# valor regardless; the discount reduces only what the buyer pays (server spread
# absorbs the cost).
# Keys in the value dict match supply_category prefixes returned by
# drop_tables.get_supply_category — "material" matches material_t1..t9.
# ============================================

const POST_SPECIALTY_DISCOUNTS = {
	"mine":     {"material": 0.15},
	"farm":     {"consumable": 0.15},
	"shrine":   {"rune": 0.15},
	"fortress": {"equipment": 0.10},
	"market":   {"equipment": 0.05, "consumable": 0.05, "material": 0.05},
}

const POST_SPECIALTY_LABELS = {
	"mine":     "Materials",
	"farm":     "Food & Consumables",
	"shrine":   "Runes",
	"fortress": "Equipment",
	"market":   "All goods (generalist)",
}

func get_specialty_discount(post_id: String, supply_category: String) -> float:
	"""Audit #9 Slice 3 — returns the buy discount fraction for a given post +
	supply_category pair. 0.15 = 15% off; 0.0 = no specialty match. Material
	tiers (material_t1..t9) all collapse to the "material" lookup key."""
	var post_cat = get_post_category(post_id)
	var discounts: Dictionary = POST_SPECIALTY_DISCOUNTS.get(post_cat, {})
	if discounts.is_empty():
		return 0.0
	var lookup = supply_category
	if supply_category.begins_with("material_"):
		lookup = "material"
	return float(discounts.get(lookup, 0.0))

func get_specialty_summary(post_id: String) -> String:
	"""Audit #9 Slice 3 — short BBCode summary of the post's specialty bonus,
	for the market panel header. Empty string if no specialty."""
	var post_cat = get_post_category(post_id)
	var discounts: Dictionary = POST_SPECIALTY_DISCOUNTS.get(post_cat, {})
	if discounts.is_empty():
		return ""
	# Single-category posts (mine/farm/shrine/fortress) read better as
	# "Specialty: -15% on Materials" than as a list.
	if discounts.size() == 1:
		var only_key = discounts.keys()[0]
		var pct = int(discounts[only_key] * 100)
		var label = POST_SPECIALTY_LABELS.get(post_cat, only_key.capitalize())
		return "Specialty: -%d%% on %s" % [pct, label]
	# Multi-category (market): list all.
	var parts: Array = []
	for cat in discounts:
		var p = int(discounts[cat] * 100)
		parts.append("-%d%% %s" % [p, cat.capitalize()])
	return "Specialty: %s" % ", ".join(parts)

func get_post_category(post_id: String) -> String:
	return POST_CATEGORIES.get(post_id, "default")

# Audit #9 Slice 3b + Audit #11 Slice 8 — category NPC vendors.
#
# Each "specialty" post category (exotic / mine / farm / shrine) hosts an
# NPC with a small, themed inventory that rotates daily. Items are listed
# alongside player listings at the post, flagged with is_npc=true so the
# browse handler skips supply markup + specialty discount on them (NPC
# prices are fixed). Threat multiplier still applies.
#
# Slice 3b launched with exotic only; Slice 8 extends the same pattern to
# the other three specialty categories from #9 Slice 3 (mine/farm/shrine),
# pairing #9's specialty discount with a category-themed destination vendor.
# Each category gets its own vendor name, tag glyph, and color so the
# market browse reads at a glance: [FORGE] at mine, [FARM] at farm, etc.
#
# The daily rotation is deterministic: hash(post_id, days_since_epoch)
# picks the same `slots_per_day` items from the category pool every time
# on a given day, so all players visiting the same post see the same
# stock that day. Tomorrow rolls a fresh subset.
#
# Items are unlimited stock — players can buy as many as they want at the
# listed price all day. No daily-purchase tracking. The intent is
# "destination vendor" — these posts are a reason to travel, not a daily
# limited resource.
const CATEGORY_STOCK_POOLS: Dictionary = {
	"exotic": [
		{"item_type": "home_stone_egg", "rarity": "uncommon", "price": 800, "supply_category": "consumable", "display_name": "Home Stone (Egg)"},
		{"item_type": "home_stone_supplies", "rarity": "uncommon", "price": 600, "supply_category": "consumable", "display_name": "Home Stone (Supplies)"},
		{"item_type": "home_stone_equipment", "rarity": "rare", "price": 1500, "supply_category": "consumable", "display_name": "Home Stone (Equipment)"},
		{"item_type": "home_stone_companion", "rarity": "rare", "price": 3000, "supply_category": "consumable", "display_name": "Home Stone (Companion)"},
		{"item_type": "mysterious_box", "rarity": "uncommon", "price": 400, "supply_category": "consumable", "display_name": "Mysterious Box"},
		{"item_type": "boss_slayer_tonic", "rarity": "rare", "price": 1200, "supply_category": "consumable", "display_name": "Boss Slayer Tonic"},
		{"item_type": "reclaimer_lantern", "rarity": "rare", "price": 900, "supply_category": "consumable", "display_name": "Reclaimer Lantern"},
		{"item_type": "floor_skip_charm", "rarity": "rare", "price": 1500, "supply_category": "consumable", "display_name": "Floor Skip Charm"},
		{"item_type": "elixir", "rarity": "common", "price": 350, "supply_category": "consumable", "display_name": "Elixir"},
		{"item_type": "cursed_coin", "rarity": "common", "price": 75, "supply_category": "consumable", "display_name": "Cursed Coin"},
		# Audit #9 Slice 5 — Travel Stone. Curiosity Trader carries them too
		# so players have a market path alongside T5+ drops.
		{"item_type": "travel_stone", "rarity": "rare", "price": 3000, "supply_category": "consumable", "display_name": "Travel Stone"},
	],
	"mine": [
		# Forge Master — equipment + defensive theme. Sanctuary equipment
		# storage stone is the headliner; charm_taunt + revive potions
		# round out the front-line-focused kit.
		{"item_type": "home_stone_equipment", "rarity": "rare", "price": 1500, "supply_category": "consumable", "display_name": "Home Stone (Equipment)"},
		{"item_type": "charm_taunt", "rarity": "uncommon", "price": 400, "supply_category": "consumable", "display_name": "Charm of Taunt"},
		{"item_type": "potion_revive_companion", "rarity": "uncommon", "price": 350, "supply_category": "consumable", "display_name": "Revival Potion"},
		{"item_type": "scroll_stone_skin", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Stone Skin"},
		{"item_type": "scroll_forcefield", "rarity": "common", "price": 240, "supply_category": "consumable", "display_name": "Scroll of Forcefield"},
		{"item_type": "elixir_greater", "rarity": "common", "price": 320, "supply_category": "consumable", "display_name": "Greater Elixir"},
	],
	"farm": [
		# Provisioner — restoration + supplies theme. Home Stone (Supplies)
		# is the headliner; potions and elixirs fit the "harvest hall" vibe.
		{"item_type": "home_stone_supplies", "rarity": "uncommon", "price": 600, "supply_category": "consumable", "display_name": "Home Stone (Supplies)"},
		{"item_type": "potion_standard", "rarity": "common", "price": 60, "supply_category": "consumable", "display_name": "Standard Health Potion"},
		{"item_type": "potion_greater", "rarity": "common", "price": 120, "supply_category": "consumable", "display_name": "Greater Health Potion"},
		{"item_type": "elixir_minor", "rarity": "common", "price": 80, "supply_category": "consumable", "display_name": "Minor Elixir"},
		{"item_type": "elixir_greater", "rarity": "common", "price": 320, "supply_category": "consumable", "display_name": "Greater Elixir"},
		{"item_type": "potion_revive_companion", "rarity": "uncommon", "price": 350, "supply_category": "consumable", "display_name": "Revival Potion"},
	],
	"shrine": [
		# Mystic — magical/spiritual theme. Home Stone (Egg) is the headliner
		# (eggs read as spiritual artifacts); scrolls and divine elixirs round
		# out the rune-shrine vibe.
		{"item_type": "home_stone_egg", "rarity": "uncommon", "price": 800, "supply_category": "consumable", "display_name": "Home Stone (Egg)"},
		{"item_type": "scroll_haste", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Haste"},
		{"item_type": "scroll_rage", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Rage"},
		{"item_type": "scroll_precision", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Precision"},
		{"item_type": "scroll_vampirism", "rarity": "common", "price": 260, "supply_category": "consumable", "display_name": "Scroll of Vampirism"},
		{"item_type": "elixir_divine", "rarity": "common", "price": 500, "supply_category": "consumable", "display_name": "Divine Elixir"},
	],
	# === Audit #11 Slice 10 — Vendors for the remaining 5 post categories ===
	# Same pattern as Slice 8 (mine/farm/shrine + exotic from #9 Slice 3b).
	# Each category gets a themed identity to differentiate destination posts.
	"haven": [
		# Innkeeper — restoration + traveler-supplies theme. Mid-tier potions
		# and elixirs across all four resources. Friendly mid-price stock.
		{"item_type": "elixir", "rarity": "common", "price": 350, "supply_category": "consumable", "display_name": "Elixir"},
		{"item_type": "potion_greater", "rarity": "common", "price": 120, "supply_category": "consumable", "display_name": "Greater Health Potion"},
		{"item_type": "mana_greater", "rarity": "common", "price": 120, "supply_category": "consumable", "display_name": "Greater Mana Potion"},
		{"item_type": "stamina_greater", "rarity": "common", "price": 120, "supply_category": "consumable", "display_name": "Greater Stamina Potion"},
		{"item_type": "energy_greater", "rarity": "common", "price": 120, "supply_category": "consumable", "display_name": "Greater Energy Potion"},
		{"item_type": "elixir_minor", "rarity": "common", "price": 80, "supply_category": "consumable", "display_name": "Minor Elixir"},
	],
	"market": [
		# Trade Master — generalist mix. Sample one item from each other
		# specialty so a market post reads as "a bit of everything" by design.
		{"item_type": "home_stone_egg", "rarity": "uncommon", "price": 800, "supply_category": "consumable", "display_name": "Home Stone (Egg)"},
		{"item_type": "mysterious_box", "rarity": "uncommon", "price": 400, "supply_category": "consumable", "display_name": "Mysterious Box"},
		{"item_type": "elixir", "rarity": "common", "price": 350, "supply_category": "consumable", "display_name": "Elixir"},
		{"item_type": "scroll_haste", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Haste"},
		{"item_type": "charm_taunt", "rarity": "uncommon", "price": 400, "supply_category": "consumable", "display_name": "Charm of Taunt"},
		{"item_type": "potion_greater", "rarity": "common", "price": 120, "supply_category": "consumable", "display_name": "Greater Health Potion"},
	],
	"tower": [
		# Lookout — scout / foresight theme. Tools for hunting and spotting:
		# the lantern + monster select scroll let you steer encounters, and
		# precision plays into the "scout's eye" vibe.
		{"item_type": "reclaimer_lantern", "rarity": "rare", "price": 900, "supply_category": "consumable", "display_name": "Reclaimer Lantern"},
		{"item_type": "scroll_monster_select", "rarity": "common", "price": 240, "supply_category": "consumable", "display_name": "Scroll of Monster Selection"},
		{"item_type": "scroll_precision", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Precision"},
		{"item_type": "elixir", "rarity": "common", "price": 350, "supply_category": "consumable", "display_name": "Elixir"},
		{"item_type": "mysterious_box", "rarity": "uncommon", "price": 400, "supply_category": "consumable", "display_name": "Mysterious Box"},
		{"item_type": "charm_taunt", "rarity": "uncommon", "price": 400, "supply_category": "consumable", "display_name": "Charm of Taunt"},
	],
	"camp": [
		# Outfitter — basic traveler supplies. Cheap entry-tier potions across
		# all four resources, plus a couple of low-cost utility items. Newbie
		# friendly pricing so first-timers near camp posts can stock up.
		{"item_type": "potion_standard", "rarity": "common", "price": 60, "supply_category": "consumable", "display_name": "Standard Health Potion"},
		{"item_type": "mana_standard", "rarity": "common", "price": 60, "supply_category": "consumable", "display_name": "Standard Mana Potion"},
		{"item_type": "stamina_standard", "rarity": "common", "price": 60, "supply_category": "consumable", "display_name": "Standard Stamina Potion"},
		{"item_type": "energy_standard", "rarity": "common", "price": 60, "supply_category": "consumable", "display_name": "Standard Energy Potion"},
		{"item_type": "cursed_coin", "rarity": "common", "price": 75, "supply_category": "consumable", "display_name": "Cursed Coin"},
		{"item_type": "scroll_haste", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Haste"},
	],
	"fortress": [
		# Quartermaster — heavy combat + equipment theme. Wall-of-iron stock
		# for the serious raid prep: equipment-stone, defensive wards, boss-
		# slayer for hard fights. Pairs well with the fortress posts (which
		# get the equipment specialty discount from #9 Slice 3).
		{"item_type": "home_stone_equipment", "rarity": "rare", "price": 1500, "supply_category": "consumable", "display_name": "Home Stone (Equipment)"},
		{"item_type": "scroll_forcefield", "rarity": "common", "price": 240, "supply_category": "consumable", "display_name": "Scroll of Forcefield"},
		{"item_type": "scroll_stone_skin", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Stone Skin"},
		{"item_type": "scroll_rage", "rarity": "common", "price": 180, "supply_category": "consumable", "display_name": "Scroll of Rage"},
		{"item_type": "boss_slayer_tonic", "rarity": "rare", "price": 1200, "supply_category": "consumable", "display_name": "Boss Slayer Tonic"},
		{"item_type": "charm_taunt", "rarity": "uncommon", "price": 400, "supply_category": "consumable", "display_name": "Charm of Taunt"},
	],
}

# Per-category vendor presentation: NPC name, market-row tag, hex tag color,
# slots-per-day. Categories absent from this dict have no NPC stock.
const CATEGORY_VENDOR_CONFIG: Dictionary = {
	"exotic":   {"vendor_name": "Curiosity Trader", "tag": "EXOTIC",   "color": "#A335EE", "slots_per_day": 4},
	"mine":     {"vendor_name": "Forge Master",     "tag": "FORGE",    "color": "#FF8C42", "slots_per_day": 3},
	"farm":     {"vendor_name": "Provisioner",      "tag": "FARM",     "color": "#80E060", "slots_per_day": 3},
	"shrine":   {"vendor_name": "Mystic",           "tag": "SHRINE",   "color": "#7FD7FF", "slots_per_day": 3},
	# Slice 10 — remaining 5 categories.
	"haven":    {"vendor_name": "Innkeeper",        "tag": "HAVEN",    "color": "#FFE0A0", "slots_per_day": 3},
	"market":   {"vendor_name": "Trade Master",     "tag": "MARKET",   "color": "#FFA070", "slots_per_day": 3},
	"tower":    {"vendor_name": "Lookout",          "tag": "TOWER",    "color": "#88AAFF", "slots_per_day": 3},
	"camp":     {"vendor_name": "Outfitter",        "tag": "CAMP",     "color": "#AA8866", "slots_per_day": 3},
	"fortress": {"vendor_name": "Quartermaster",    "tag": "FORTRESS", "color": "#A0A0A0", "slots_per_day": 3},
}

# Back-compat alias — Slice 3b client code may reference EXOTIC_STOCK_POOL.
# Keeping the symbol so cross-version client builds still resolve it.
const EXOTIC_STOCK_POOL: Array = []  # superseded by CATEGORY_STOCK_POOLS["exotic"]
const EXOTIC_SLOTS_PER_DAY := 4  # superseded by CATEGORY_VENDOR_CONFIG["exotic"].slots_per_day

func resolve_post_category(post_dict: Dictionary, post_id: String) -> String:
	"""Audit #9 Slice 3b — resolve a trading post's category from either source.
	Procedural NPC posts carry "category" on the post dict; legacy fixed posts
	in TRADING_POSTS use the separate POST_CATEGORIES lookup. Callers with the
	live post dict (e.g. at_trading_post[peer_id]) should prefer this over
	get_post_category(post_id) so procedural posts resolve correctly."""
	var dict_cat: String = String(post_dict.get("category", ""))
	if dict_cat != "":
		return dict_cat
	return POST_CATEGORIES.get(post_id, "default")

func get_npc_vendor_config(category: String) -> Dictionary:
	"""Slice 8 — returns vendor presentation for a category, or empty when
	the category has no NPC stock. Empty result signals 'no vendor here.'"""
	return CATEGORY_VENDOR_CONFIG.get(category, {})

func category_has_npc_stock(category: String) -> bool:
	"""Slice 8 — single source of truth for which categories host a vendor."""
	return CATEGORY_STOCK_POOLS.has(category) and not CATEGORY_STOCK_POOLS[category].is_empty()

func get_npc_daily_stock(post_id: String, category: String) -> Array:
	"""Audit #11 Slice 8 (generalises Audit #9 Slice 3b). Deterministic
	per-post-per-day NPC stock. Hashes post_id with days-since-epoch and
	the category so different categories roll independently (the same
	post wouldn't change category mid-life, but the seed is cleaner if
	categories are independent). Returns Array of vendor_config.slots_per_day
	pool entries (or fewer if the pool is smaller)."""
	if not category_has_npc_stock(category):
		return []
	var pool: Array = CATEGORY_STOCK_POOLS[category]
	var cfg: Dictionary = CATEGORY_VENDOR_CONFIG.get(category, {})
	var slots: int = int(cfg.get("slots_per_day", 3))
	# Days since epoch — UTC truncation is fine, all players use the
	# server's clock so the day boundary is consistent.
	var seconds_since_epoch: int = int(Time.get_unix_time_from_system())
	var day_index: int = seconds_since_epoch / 86400
	var seed_str := "%s|%s|%d" % [category, post_id, day_index]
	var seed_hash: int = seed_str.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash
	# Sample without replacement: shuffle pool indices, take first N.
	var indices: Array = []
	for i in range(pool.size()):
		indices.append(i)
	# Fisher-Yates on indices using the seeded RNG.
	for i in range(indices.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	var picked: Array = []
	var limit: int = mini(slots, pool.size())
	for i in range(limit):
		picked.append(pool[indices[i]])
	return picked

# Back-compat shim — Slice 3b server code calls get_exotic_daily_stock(post_id).
# Delegates to the new generalised helper so any stale callers stay correct
# until they migrate.
func get_exotic_daily_stock(post_id: String) -> Array:
	return get_npc_daily_stock(post_id, "exotic")

func get_post_map_colors(post_id: String) -> Dictionary:
	var category = get_post_category(post_id)
	return POST_MAP_COLORS.get(category, POST_MAP_COLORS["default"])

func get_post_tier(post_id: String) -> int:
	"""Get tier classification (1-7) for a trading post. Defaults to 1 if unknown.
	Legacy fixed-post API — Slice 6L moved region naming and the live region
	tier lookup onto chunk_manager.get_nearest_npc_post_with_tier."""
	return POST_TIERS.get(post_id, 1)

func get_nearest_post_tier(x: int, y: int) -> Dictionary:
	"""Get tier info for the nearest trading post.
	Returns {tier, post_id, post_name, distance, tier_name, tier_color}."""
	var nearest_post_id = ""
	var nearest_post_name = ""
	var nearest_dist = 999999.0

	for post_id in TRADING_POSTS:
		var post = TRADING_POSTS[post_id]
		var center = post.center
		var dist = sqrt(pow(x - center.x, 2) + pow(y - center.y, 2))
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_post_id = post_id
			nearest_post_name = post.name

	var tier = POST_TIERS.get(nearest_post_id, 1)
	return {
		"tier": tier,
		"post_id": nearest_post_id,
		"post_name": nearest_post_name,
		"distance": nearest_dist,
		"tier_name": POST_TIER_NAMES.get(tier, "Unknown"),
		"tier_color": POST_TIER_COLORS.get(tier, "#FFFFFF"),
		# Legacy fallback — Slice 6L moved live region naming to the procedural
		# posts. This function is no longer called by the live region label,
		# but keep the field shape consistent for any legacy diagnostics.
		"region_name": POST_TIER_NAMES.get(tier, "Wilderness"),
	}

func get_post_id_at(x: int, y: int) -> String:
	if not _initialized:
		_build_tile_cache()
	var tile = Vector2i(x, y)
	if _tile_cache.has(tile):
		return _tile_cache[tile]
	return ""

func is_trading_post_center(x: int, y: int) -> bool:
	"""Check if the given coordinates are the center of a Trading Post"""
	for post_id in TRADING_POSTS:
		var post = TRADING_POSTS[post_id]
		if post.center.x == x and post.center.y == y:
			return true
	return false

func get_all_trading_posts() -> Array:
	"""Get array of all Trading Post data"""
	var posts = []
	for post_id in TRADING_POSTS:
		posts.append(TRADING_POSTS[post_id].duplicate(true))
	return posts

func get_nearest_trading_post(x: int, y: int) -> Dictionary:
	"""Find the nearest Trading Post to the given coordinates"""
	var nearest_post = {}
	var nearest_dist = 999999.0

	for post_id in TRADING_POSTS:
		var post = TRADING_POSTS[post_id]
		var center = post.center
		var dist = sqrt(pow(x - center.x, 2) + pow(y - center.y, 2))
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_post = post.duplicate(true)

	return nearest_post

func get_distance_to_nearest_trading_post(x: int, y: int) -> float:
	"""Get distance to the nearest Trading Post"""
	var nearest_dist = 999999.0

	for post_id in TRADING_POSTS:
		var post = TRADING_POSTS[post_id]
		var center = post.center
		var dist = sqrt(pow(x - center.x, 2) + pow(y - center.y, 2))
		if dist < nearest_dist:
			nearest_dist = dist

	return nearest_dist

func get_tile_position_in_post(x: int, y: int) -> String:
	"""Get the position character for map rendering within a Trading Post.
	Uses different shapes based on trading post ID for visual variety.
	Returns: 'P' for center, various edge/corner chars based on shape, ' ' for interior"""
	if not is_trading_post_tile(x, y):
		return ""

	var post = get_trading_post_at(x, y)
	var center = post.center
	var half_size = post.size / 2
	var post_id = post.get("id", "")

	# Check if this is the center
	if x == center.x and y == center.y:
		return "P"

	# Calculate relative position from center
	var rel_x = x - center.x
	var rel_y = y - center.y

	# Check if on edge
	var on_left = (x == center.x - half_size)
	var on_right = (x == center.x + half_size)
	var on_top = (y == center.y + half_size)
	var on_bottom = (y == center.y - half_size)
	var on_edge = on_left or on_right or on_top or on_bottom

	# Get shape type based on trading post ID hash
	var shape_type = _get_post_shape_type(post_id)

	match shape_type:
		0:  # Classic shape: + - |
			if (on_left or on_right) and (on_top or on_bottom):
				return "+"
			if on_top or on_bottom:
				return "-"
			if on_left or on_right:
				return "|"
			return " "

		1:  # Fortress shape: # = ||
			if (on_left or on_right) and (on_top or on_bottom):
				return "#"
			if on_top or on_bottom:
				return "="
			if on_left or on_right:
				return "#"
			return "."

		2:  # Tower shape: * ~ :
			if (on_left or on_right) and (on_top or on_bottom):
				return "*"
			if on_top or on_bottom:
				return "~"
			if on_left or on_right:
				return ":"
			return " "

		3:  # Camp shape: o - .
			if (on_left or on_right) and (on_top or on_bottom):
				return "o"
			if on_top or on_bottom:
				return "-"
			if on_left or on_right:
				return "."
			return " "

		4:  # Temple shape: ^ _ |
			if on_top and (on_left or on_right):
				return "^"
			if on_bottom and (on_left or on_right):
				return "."
			if on_top:
				return "^"
			if on_bottom:
				return "_"
			if on_left or on_right:
				return "|"
			return " "

		5:  # Outpost shape: [ ] =
			if on_left and (on_top or on_bottom):
				return "["
			if on_right and (on_top or on_bottom):
				return "]"
			if on_top or on_bottom:
				return "="
			if on_left:
				return "["
			if on_right:
				return "]"
			return "."

		6:  # Ruins shape: gaps in walls, broken corners
			if on_top and on_left:
				return "."
			if on_bottom and on_right:
				return "."
			if on_top and on_right:
				return "'"
			if on_bottom and on_left:
				return "_"
			if on_top:
				return "-"
			if on_bottom:
				if rel_x == 0:
					return "_"
				return " "
			if on_left:
				if rel_y == 0:
					return "|"
				return " "
			if on_right:
				return "|"
			return "."

		7:  # Arch shape: curved edges
			if on_top and (on_left or on_right):
				return "~"
			if on_bottom and on_left:
				return "("
			if on_bottom and on_right:
				return ")"
			if on_top:
				return "~"
			if on_bottom:
				return "_"
			if on_left:
				return "("
			if on_right:
				return ")"
			return " "

		8:  # Dock shape: open south wall
			if on_top and on_left:
				return "["
			if on_top and on_right:
				return "]"
			if on_top:
				return "="
			if on_bottom:
				return " "
			if on_left:
				return "["
			if on_right:
				return "]"
			return "."

		9:  # Gateway shape: ornate entrance
			if on_top and on_left:
				return "/"
			if on_top and on_right:
				return "\\"
			if on_bottom and on_left:
				return "\\"
			if on_bottom and on_right:
				return "/"
			if on_top:
				return "^"
			if on_bottom:
				return "v"
			if on_left:
				return "{"
			if on_right:
				return "}"
			return " "

	# Default fallback
	if (on_left or on_right) and (on_top or on_bottom):
		return "+"
	if on_top or on_bottom:
		return "-"
	if on_left or on_right:
		return "|"
	return " "

func _get_post_shape_type(post_id: String) -> int:
	"""Get shape type for a trading post based on its ID and zone.
	Shapes: 0=Classic, 1=Fortress, 2=Tower, 3=Camp, 4=Temple, 5=Outpost,
	        6=Ruins, 7=Arch, 8=Dock, 9=Gateway"""
	# Explicit assignments for thematic consistency
	match post_id:
		# Shape 0 - Classic: welcoming/safe
		"haven", "far_west_haven":
			return 0
		# Shape 1 - Fortress: fortified/military
		"crossroads", "shadowmere", "dragons_rest", "northeast_bastion":
			return 1
		"world_spine_north", "world_spine_south", "northwest_citadel":
			return 1
		"southeast_garrison", "southwest_fortress", "westhold":
			return 1
		# Shape 2 - Tower: elevated/mystical
		"primordial_sanctum", "celestial_spire", "storm_peak", "northeast_tower":
			return 2
		"northwatch", "southern_watch", "highland_post", "high_north_peak":
			return 2
		"eastern_terminus", "western_terminus", "oblivion_watch":
			return 2
		# Shape 3 - Camp: rustic/temporary
		"eastern_camp", "southwest_camp", "northwest_lodge", "western_refuge":
			return 3
		"northeast_frontier", "southeast_outpost", "far_east_station":
			return 3
		# Shape 4 - Temple: religious/sacred
		"southwest_temple", "west_shrine", "genesis_point":
			return 4
		# Shape 5 - Outpost: military outpost
		"voids_edge", "eastwatch", "inferno_outpost":
			return 5
		# Shape 6 - Ruins: broken/chaotic
		"chaos_refuge", "entropy_station", "abyssal_depths":
			return 6
		# Shape 7 - Arch: natural/curved
		"frozen_reach", "southwest_grove", "northwest_inn", "northwest_mill":
			return 7
		# Shape 8 - Dock: port/water
		"southport", "deep_south_port", "southeast_bridge":
			return 8
		# Shape 9 - Gateway: ornate entrance
		"south_gate", "nether_gate", "frostgate":
			return 9

	# Fallback: hash-based for any unassigned posts
	var hash_val = 0
	for c in post_id:
		hash_val = (hash_val * 31 + c.unicode_at(0)) % 1000000

	return hash_val % 10

func get_trading_posts_within_distance(x: int, y: int, max_distance: float) -> Array:
	"""Get all Trading Posts within the specified distance"""
	var nearby_posts = []

	for post_id in TRADING_POSTS:
		var post = TRADING_POSTS[post_id]
		var center = post.center
		var dist = sqrt(pow(x - center.x, 2) + pow(y - center.y, 2))
		if dist <= max_distance:
			var post_data = post.duplicate(true)
			post_data["distance"] = dist
			nearby_posts.append(post_data)

	# Sort by distance
	nearby_posts.sort_custom(func(a, b): return a.distance < b.distance)

	return nearby_posts

func get_post_recommended_level(post_id: String) -> int:
	"""Get the recommended player level for a trading post based on its distance from origin."""
	if not TRADING_POSTS.has(post_id):
		return 1
	var post = TRADING_POSTS[post_id]
	var center = post.center
	var dist = sqrt(center.x * center.x + center.y * center.y)

	# Distance to level mapping (roughly matches zone descriptions)
	# Core Zone (0-30): Level 1-30
	# Inner Zone (30-75): Level 30-75
	# Mid Zone (75-200): Level 50-200
	# Mid-Outer Zone (200-350): Level 150-300
	# Outer Zone (350-500): Level 200-500
	# Extreme Zone (500-700): Level 500-700
	# World's Edge (700+): Level 700+
	return max(1, int(dist))

func get_post_distance_from_origin(post_id: String) -> float:
	"""Get the distance of a trading post from the origin (0,0)."""
	if not TRADING_POSTS.has(post_id):
		return 0.0
	var post = TRADING_POSTS[post_id]
	var center = post.center
	return sqrt(center.x * center.x + center.y * center.y)

func get_next_progression_post(current_post_id: String, player_level: int) -> Dictionary:
	"""Find the next trading post the player should travel to for progression.
	Returns the nearest post that is:
	1. Further from origin than current post
	2. Within reasonable level range (player_level to player_level + 50)
	Returns empty dict if no suitable post found."""

	if not TRADING_POSTS.has(current_post_id):
		return {}

	var current_dist = get_post_distance_from_origin(current_post_id)
	var candidates = []

	for post_id in TRADING_POSTS:
		if post_id == current_post_id:
			continue

		var post_dist = get_post_distance_from_origin(post_id)
		var recommended_level = get_post_recommended_level(post_id)

		# Must be further from origin
		if post_dist <= current_dist:
			continue

		# Recommended level should be within range (current level to +50)
		# Player should be at least 80% of the recommended level
		var min_player_level = int(recommended_level * 0.8)
		if player_level < min_player_level:
			continue

		# Don't suggest posts way beyond player's level (more than +100)
		if recommended_level > player_level + 100:
			continue

		var post_data = TRADING_POSTS[post_id].duplicate(true)
		post_data["distance_from_origin"] = post_dist
		post_data["recommended_level"] = recommended_level
		candidates.append(post_data)

	if candidates.is_empty():
		return {}

	# Sort by distance from origin (closest first that's still further than current)
	candidates.sort_custom(func(a, b): return a.distance_from_origin < b.distance_from_origin)

	return candidates[0]

func get_posts_sorted_by_distance() -> Array:
	"""Get all trading posts sorted by distance from origin."""
	var posts = []
	for post_id in TRADING_POSTS:
		var post = TRADING_POSTS[post_id].duplicate(true)
		post["distance_from_origin"] = get_post_distance_from_origin(post_id)
		post["recommended_level"] = get_post_recommended_level(post_id)
		posts.append(post)

	posts.sort_custom(func(a, b): return a.distance_from_origin < b.distance_from_origin)
	return posts
