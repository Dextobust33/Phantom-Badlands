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
	# Inner Zone (Safe Start)
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

	# Inner-Mid Zone (Level 25-75 areas) - Filling gaps closer to center
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
	Returns: 'P' for center, '+' for corners, '-' for horizontal edges, '|' for vertical edges, ' ' for interior"""
	if not is_trading_post_tile(x, y):
		return ""

	var post = get_trading_post_at(x, y)
	var center = post.center
	var half_size = post.size / 2

	# Check if this is the center
	if x == center.x and y == center.y:
		return "P"

	# Check if on edge
	var on_left = (x == center.x - half_size)
	var on_right = (x == center.x + half_size)
	var on_top = (y == center.y + half_size)
	var on_bottom = (y == center.y - half_size)

	# Corners
	if (on_left or on_right) and (on_top or on_bottom):
		return "+"

	# Horizontal edges
	if on_top or on_bottom:
		return "-"

	# Vertical edges
	if on_left or on_right:
		return "|"

	# Interior tile
	return " "

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
