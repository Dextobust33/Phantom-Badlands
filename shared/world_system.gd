# world_system.gd
# Phantasia 4-style coordinate-based world system
class_name WorldSystem
extends Node

# World boundaries (expanded for better level progression)
const WORLD_MIN_X = -2000
const WORLD_MAX_X = 2000
const WORLD_MIN_Y = -2000
const WORLD_MAX_Y = 2000

# Terrain types (matching P4)
enum Terrain {
	THRONE,          # (0,0) - King's throne (now part of Crossroads Trading Post)
	CITY,            # Safe zone, shops
	TRADING_POST,    # Trading Post safe zones
	PLAINS,          # Basic terrain, low danger
	FOREST,          # Light encounters
	DEEP_FOREST,     # Medium danger
	MOUNTAINS,       # High danger
	SWAMP,           # High danger
	DESERT,          # Very high danger
	VOLCANO,         # Extreme danger
	DARK_CIRCLE,     # Special area
	VOID,            # Beyond the edge
	WATER,           # Shallow water - fishable
	DEEP_WATER       # Deep water - rare catches, fishable
}

# Special locations - major landmarks only (Trading Posts handled separately)
const SPECIAL_LOCATIONS = {
	Vector2i(400, 0): {"terrain": Terrain.DARK_CIRCLE, "name": "Dark Circle", "description": "A place of great danger and power"},
	Vector2i(-400, 0): {"terrain": Terrain.VOLCANO, "name": "Fire Mountain", "description": "An active volcano"},
}

# Preload Trading Post database
const TradingPostDatabaseScript = preload("res://shared/trading_post_database.gd")

# Trading Post database reference
var trading_post_db: Node = null

func _ready():
	print("World System initialized - Phantasia 4 style")
	# Initialize trading post database
	trading_post_db = TradingPostDatabaseScript.new()
	add_child(trading_post_db)

func get_terrain_at(x: int, y: int) -> Terrain:
	"""Determine terrain based on coordinates (procedural like P4)"""
	var pos = Vector2i(x, y)

	# Check Trading Posts first - they are safe zones
	if trading_post_db and trading_post_db.is_trading_post_tile(x, y):
		return Terrain.TRADING_POST

	# Check special locations
	if SPECIAL_LOCATIONS.has(pos):
		return SPECIAL_LOCATIONS[pos].terrain

	# Check for water bodies (lakes and rivers)
	if _is_water_at(x, y):
		return Terrain.WATER
	if _is_deep_water_at(x, y):
		return Terrain.DEEP_WATER

	# Distance-based terrain
	var distance_from_center = sqrt(x * x + y * y)

	if distance_from_center < 5:
		return Terrain.PLAINS  # Near center is open plains
	elif distance_from_center < 50:
		return Terrain.PLAINS
	elif distance_from_center < 100:
		# Use coordinate hash for variety
		var hash_val = abs(x * 7 + y * 13) % 100
		if hash_val < 40:
			return Terrain.FOREST
		elif hash_val < 70:
			return Terrain.PLAINS
		else:
			return Terrain.MOUNTAINS
	elif distance_from_center < 200:
		var hash_val = abs(x * 7 + y * 13) % 100
		if hash_val < 30:
			return Terrain.DEEP_FOREST
		elif hash_val < 50:
			return Terrain.MOUNTAINS
		elif hash_val < 70:
			return Terrain.SWAMP
		else:
			return Terrain.FOREST
	elif distance_from_center < 400:
		var hash_val = abs(x * 7 + y * 13) % 100
		if hash_val < 40:
			return Terrain.DESERT
		elif hash_val < 60:
			return Terrain.MOUNTAINS
		else:
			return Terrain.SWAMP
	else:
		# Far regions - very dangerous
		return Terrain.VOID

	return Terrain.PLAINS

func _is_water_at(x: int, y: int) -> bool:
	"""Check if coordinates should be shallow water (lakes and rivers)"""
	# Lake near Southport (-30 to 30, -160 to -140)
	if x >= -30 and x <= 30 and y >= -160 and y <= -140:
		return true
	# River along y = -50 (east-west flowing river)
	if y >= -52 and y <= -48 and x >= -100 and x <= 100:
		return true
	# Lake near East Market (40 to 60, 0 to 20)
	if x >= 40 and x <= 60 and y >= 0 and y <= 20:
		return true
	# Northern lake (Highland Post area: -20 to 20, 140 to 160)
	if x >= -20 and x <= 20 and y >= 140 and y <= 160:
		return true
	# Use hash-based water spots for scattered ponds
	var water_hash = abs(x * 31 + y * 53) % 1000
	if water_hash < 5:  # 0.5% chance of random water
		return true
	return false

func _is_deep_water_at(x: int, y: int) -> bool:
	"""Check if coordinates should be deep water (ocean edges)"""
	# Deep water near southern coast (y < -250, within certain x range)
	if y <= -250 and y >= -300 and abs(x) <= 100:
		return true
	# Deep water in center of lakes (smaller areas within water)
	if x >= -10 and x <= 10 and y >= -155 and y <= -145:
		return true  # Center of Southport lake
	if x >= 47 and x <= 53 and y >= 7 and y <= 13:
		return true  # Center of East Market lake
	return false

func is_fishing_spot(x: int, y: int) -> bool:
	"""Check if coordinates are a valid fishing location"""
	var terrain = get_terrain_at(x, y)
	return terrain == Terrain.WATER or terrain == Terrain.DEEP_WATER

func get_fishing_type(x: int, y: int) -> String:
	"""Get the type of fishing available at coordinates (shallow/deep)"""
	var terrain = get_terrain_at(x, y)
	if terrain == Terrain.DEEP_WATER:
		return "deep"
	elif terrain == Terrain.WATER:
		return "shallow"
	return ""

# ===== GATHERING SYSTEM (Mining & Logging) =====

func is_ore_deposit(x: int, y: int) -> bool:
	"""Check if coordinates are a valid mining location (ore deposit in mountains)"""
	var terrain = get_terrain_at(x, y)
	if terrain != Terrain.MOUNTAINS:
		return false
	# Use hash-based ore deposits - 2% of mountain tiles have ore
	var ore_hash = abs(x * 47 + y * 83) % 1000
	return ore_hash < 20  # 2% chance

func is_dense_forest(x: int, y: int) -> bool:
	"""Check if coordinates are a valid logging location (dense forest with harvestable trees)"""
	var terrain = get_terrain_at(x, y)
	if terrain != Terrain.FOREST and terrain != Terrain.DEEP_FOREST:
		return false
	# Use hash-based tree nodes - 3% of forests have harvestable trees
	var wood_hash = abs(x * 67 + y * 97) % 1000
	return wood_hash < 30  # 3% chance

func get_ore_tier(x: int, y: int) -> int:
	"""Get the ore tier based on distance from origin (center is T1, edges are higher)"""
	var distance = sqrt(x * x + y * y)
	# Tier scaling: T1 at 0-50, T2 at 50-100, T3 at 100-150, etc.
	# Max tier 9 at 400+ distance
	var tier = int(distance / 50) + 1
	return clampi(tier, 1, 9)

func get_wood_tier(x: int, y: int) -> int:
	"""Get the wood tier based on distance from origin"""
	var distance = sqrt(x * x + y * y)
	# Tier scaling similar to ore
	# Max tier 6 for wood
	var tier = int(distance / 60) + 1
	return clampi(tier, 1, 6)

func get_terrain_info(terrain: Terrain) -> Dictionary:
	"""Get information about a terrain type"""
	match terrain:
		Terrain.THRONE:
			return {
				"name": "Throne Room",
				"char": "T",  # Single ASCII character
				"color": "#FFD700",
				"safe": true,
				"encounter_rate": 0.0,
				"monster_level_min": 0,
				"monster_level_max": 0
			}
		Terrain.CITY:
			return {
				"name": "City",
				"char": "C",  # Single ASCII character
				"color": "#87CEEB",
				"safe": true,
				"encounter_rate": 0.0,
				"monster_level_min": 0,
				"monster_level_max": 0
			}
		Terrain.TRADING_POST:
			return {
				"name": "Trading Post",
				"char": "$",  # Already single width
				"color": "#FFD700",
				"safe": true,
				"encounter_rate": 0.0,
				"monster_level_min": 0,
				"monster_level_max": 0
			}
		Terrain.PLAINS:
			return {
				"name": "Plains",
				"char": ",",  # Comma is more visible than period
				"color": "#90EE90",
				"safe": false,
				"encounter_rate": 0.1,
				"monster_level_min": 1,
				"monster_level_max": 5
			}
		Terrain.FOREST:
			return {
				"name": "Forest",
				"char": "f",  # Single ASCII character
				"color": "#228B22",
				"safe": false,
				"encounter_rate": 0.2,
				"monster_level_min": 3,
				"monster_level_max": 10
			}
		Terrain.DEEP_FOREST:
			return {
				"name": "Deep Forest",
				"char": "F",  # Single ASCII character (uppercase for deep)
				"color": "#006400",
				"safe": false,
				"encounter_rate": 0.35,
				"monster_level_min": 10,
				"monster_level_max": 20
			}
		Terrain.MOUNTAINS:
			return {
				"name": "Mountains",
				"char": "^",  # Single ASCII character
				"color": "#A0522D",
				"safe": false,
				"encounter_rate": 0.3,
				"monster_level_min": 15,
				"monster_level_max": 30
			}
		Terrain.SWAMP:
			return {
				"name": "Swamp",
				"char": "~",  # Already single width
				"color": "#556B2F",
				"safe": false,
				"encounter_rate": 0.4,
				"monster_level_min": 20,
				"monster_level_max": 40
			}
		Terrain.DESERT:
			return {
				"name": "Desert",
				"char": "=",  # Single ASCII character
				"color": "#EDC9AF",
				"safe": false,
				"encounter_rate": 0.35,
				"monster_level_min": 25,
				"monster_level_max": 50
			}
		Terrain.VOLCANO:
			return {
				"name": "Volcano",
				"char": "V",  # Single ASCII character
				"color": "#FF4500",
				"safe": false,
				"encounter_rate": 0.6,
				"monster_level_min": 50,
				"monster_level_max": 100
			}
		Terrain.DARK_CIRCLE:
			return {
				"name": "Dark Circle",
				"char": "X",  # Single ASCII character
				"color": "#8B0000",
				"safe": false,
				"encounter_rate": 0.8,
				"monster_level_min": 75,
				"monster_level_max": 150
			}
		Terrain.VOID:
			return {
				"name": "The Void",
				"char": "#",  # Single ASCII character
				"color": "#2F4F4F",
				"safe": false,
				"encounter_rate": 0.5,
				"monster_level_min": 100,
				"monster_level_max": 200
			}
		Terrain.WATER:
			return {
				"name": "Water",
				"char": "w",  # Single ASCII character
				"color": "#4169E1",
				"safe": false,
				"encounter_rate": 0.1,  # Low encounter rate - focus on fishing
				"monster_level_min": 5,
				"monster_level_max": 20,
				"fishable": true,
				"fish_type": "shallow"
			}
		Terrain.DEEP_WATER:
			return {
				"name": "Deep Water",
				"char": "W",  # Single ASCII character (uppercase for deep)
				"color": "#00008B",
				"safe": false,
				"encounter_rate": 0.2,
				"monster_level_min": 20,
				"monster_level_max": 50,
				"fishable": true,
				"fish_type": "deep"
			}

	return {"name": "Unknown", "char": "?", "color": "#FFFFFF", "safe": false}

func get_location_name(x: int, y: int) -> String:
	"""Get the name of a location"""
	var pos = Vector2i(x, y)

	# Check Trading Posts first
	if trading_post_db and trading_post_db.is_trading_post_tile(x, y):
		var tp = trading_post_db.get_trading_post_at(x, y)
		return tp.get("name", "Trading Post")

	if SPECIAL_LOCATIONS.has(pos):
		return SPECIAL_LOCATIONS[pos].name

	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	return info.name

func get_location_description(x: int, y: int) -> String:
	"""Get full description of current location"""
	var pos = Vector2i(x, y)
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)

	var desc = ""

	# Trading Post description
	if trading_post_db and trading_post_db.is_trading_post_tile(x, y):
		var tp = trading_post_db.get_trading_post_at(x, y)
		desc += "[color=#FFD700][b]%s[/b][/color]\n" % tp.get("name", "Trading Post")
		desc += "%s\n" % tp.get("description", "A trading hub")
		desc += "[b]Quest Giver:[/b] %s\n" % tp.get("quest_giver", "Unknown")
		desc += "[color=#00FF00]This is a safe area[/color]\n"
		return desc

	# Special location description
	if SPECIAL_LOCATIONS.has(pos):
		desc += SPECIAL_LOCATIONS[pos].description + "\n"

	# Coordinate display (P4 style)
	desc += "[b]Location:[/b] (%d, %d)\n" % [x, y]
	desc += "[b]Terrain:[/b] %s\n" % info.name

	# Get distance-based level range
	var level_range = get_monster_level_range(x, y)

	# Danger info based on distance from origin
	if not info.safe and level_range.min > 0:
		# Hotspot warning
		if level_range.is_hotspot:
			desc += "[color=#FF0000][b]!!! DANGER ZONE !!![/b][/color]\n"

		desc += "[color=#FF4444]Danger:[/color] Monsters level %d-%d\n" % [level_range.min, level_range.max]
		desc += "[color=#FF4444]Encounter Rate:[/color] %.0f%%\n" % (info.encounter_rate * 100)
	else:
		desc += "[color=#00FF00]This is a safe area[/color]\n"

	return desc

func generate_ascii_map(center_x: int, center_y: int, radius: int = 7) -> String:
	"""Generate ASCII map centered on player (P4 style with proper spacing)"""
	var map_lines: PackedStringArray = PackedStringArray()

	# Generate map from top to bottom
	for dy in range(radius, -radius - 1, -1):
		var line_parts: PackedStringArray = PackedStringArray()
		for dx in range(-radius, radius + 1):
			var x = center_x + dx
			var y = center_y + dy

			# Check bounds
			if x < WORLD_MIN_X or x > WORLD_MAX_X or y < WORLD_MIN_Y or y > WORLD_MAX_Y:
				line_parts.append("  ")  # Two spaces for out of bounds
				continue

			# Player position
			if dx == 0 and dy == 0:
				line_parts.append("[color=#FFFF00] @[/color]")  # Space before @ for even spacing
			else:
				var terrain = get_terrain_at(x, y)
				var info = get_terrain_info(terrain)

				# Check if this tile is a hotspot - show in red/orange
				if _is_hotspot(x, y) and not info.safe:
					var intensity = _get_hotspot_intensity(x, y)
					# Gradient from orange (edge) to bright red (center)
					var hotspot_color = "#FF4500" if intensity > 0.5 else "#FF6600"
					line_parts.append("[color=%s] ![/color]" % hotspot_color)
				else:
					# Add space BEFORE each character for even grid spacing
					line_parts.append("[color=%s] %s[/color]" % [info.color, info.char])

		map_lines.append("".join(line_parts))

	return "\n".join(map_lines)

func generate_map_display(center_x: int, center_y: int, radius: int = 7, nearby_players: Array = []) -> String:
	"""Generate complete map display with location info header.
	nearby_players is an array of {x, y, name, level} dictionaries for other players to display."""
	var output = ""

	# Check if at Trading Post
	if trading_post_db and trading_post_db.is_trading_post_tile(center_x, center_y):
		var tp = trading_post_db.get_trading_post_at(center_x, center_y)
		output += "[color=#FFD700][b]%s[/b][/color] [color=#5F9EA0](%d, %d)[/color]\n" % [tp.get("name", "Trading Post"), center_x, center_y]
		output += "[color=#00FF00]Safe[/color] - [color=#87CEEB]%s[/color]\n" % tp.get("quest_giver", "Quest Giver")
		output += "[center]"
		output += generate_ascii_map_with_merchants(center_x, center_y, radius, nearby_players)
		output += "[/center]"
		return output

	# Get location info
	var terrain = get_terrain_at(center_x, center_y)
	var info = get_terrain_info(terrain)

	# Get distance-based level range
	var level_range = get_monster_level_range(center_x, center_y)

	# Location header - compact format
	output += "[color=#5F9EA0](%d, %d)[/color] %s" % [center_x, center_y, info.name]

	# Merchant at current location (not in Trading Posts)
	if is_merchant_at(center_x, center_y):
		var merchant = get_merchant_at(center_x, center_y)
		output += " [color=#FFD700]$%s[/color]" % merchant.name

	output += "\n"

	# Danger info based on distance - single line
	if not info.safe and level_range.min > 0:
		if level_range.is_hotspot:
			output += "[color=#FF0000]!DANGER![/color] "
		output += "[color=#FF4444]Lv%d-%d[/color]\n" % [level_range.min, level_range.max]
	else:
		output += "[color=#00FF00]Safe[/color]\n"

	# Add the map (centered)
	output += "[center]"
	output += generate_ascii_map_with_merchants(center_x, center_y, radius, nearby_players)
	output += "[/center]"

	return output

func is_safe_zone(x: int, y: int) -> bool:
	"""Check if location is a safe zone"""
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	return info.safe

func check_encounter(x: int, y: int) -> bool:
	"""Check if player encounters a monster (roll)"""
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	
	if info.safe:
		return false
	
	return randf() < info.encounter_rate

func get_monster_level_range(x: int, y: int) -> Dictionary:
	"""Get the monster level range for this location based on distance from origin"""
	# Check if safe zone first
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	if info.safe:
		return {
			"min": 0,
			"max": 0,
			"is_hotspot": false
		}

	# Calculate Euclidean distance from origin (0,0)
	var distance = sqrt(float(x * x + y * y))

	# Get base level from distance formula
	var base_level = _distance_to_level(distance)

	# Check for hot spot (danger zone cluster)
	var is_hotspot = _is_hotspot(x, y)
	var hotspot_multiplier = 1.0
	if is_hotspot:
		# Hot spots have 50-150% level bonus based on intensity (center = stronger)
		var intensity = _get_hotspot_intensity(x, y)
		hotspot_multiplier = 1.5 + intensity  # 1.5x at edge, 2.5x at center

	# Apply hotspot multiplier to base level
	var adjusted_level = int(base_level * hotspot_multiplier)

	# Calculate variance range (+/- 10% for more predictable encounters)
	var variance = max(1, int(adjusted_level * 0.10))  # Reduced from 15%
	var min_level = max(1, adjusted_level - variance)
	var max_level = min(10000, adjusted_level + variance)

	return {
		"min": min_level,
		"max": max_level,
		"base_level": adjusted_level,
		"is_hotspot": is_hotspot,
		"distance": distance
	}

func _distance_to_level(distance: float) -> int:
	"""Convert distance from origin to monster level (0-2828 -> 1-10000).
	   Expanded world with more gradual level progression."""
	# Safe zone (distance 0-10)
	if distance <= 10:
		return 1

	# Distance 10-150: Levels 1-50 (gentle curve for new players)
	if distance <= 150:
		var t = (distance - 10) / 140.0  # 0 to 1
		return int(1 + t * 49)

	# Distance 150-400: Levels 50-200 (moderate growth)
	if distance <= 400:
		var t = (distance - 150) / 250.0  # 0 to 1
		return int(50 + t * 150)

	# Distance 400-800: Levels 200-600 (steady)
	if distance <= 800:
		var t = (distance - 400) / 400.0  # 0 to 1
		return int(200 + t * 400)

	# Distance 800-1200: Levels 600-1500 (accelerating)
	if distance <= 1200:
		var t = (distance - 800) / 400.0  # 0 to 1
		return int(600 + t * 900)

	# Distance 1200-1800: Levels 1500-4000 (steep)
	if distance <= 1800:
		var t = (distance - 1200) / 600.0  # 0 to 1
		return int(1500 + t * 2500)

	# Distance 1800+: Levels 4000-10000 (approaching max)
	# Max distance is ~2828 (corners of 2000x2000 world)
	var t = min(1.0, (distance - 1800) / 1028.0)  # 0 to 1
	return int(4000 + t * 6000)

func get_hotspot_at(x: int, y: int) -> Dictionary:
	"""Get hotspot info for a location. Returns {in_hotspot: bool, intensity: float}"""
	var in_hotspot = _is_hotspot(x, y)
	var intensity = 0.0
	if in_hotspot:
		intensity = _get_hotspot_intensity(x, y)
	return {"in_hotspot": in_hotspot, "intensity": intensity}

func _is_hotspot(x: int, y: int) -> bool:
	"""Check if coordinates are within a danger zone hot spot cluster"""
	# Find the nearest cluster center and check if we're within its radius
	# Clusters are seeded at ~0.3% of tiles but expand to 1-20 tiles each

	# Check nearby potential cluster centers (within max cluster radius of 5)
	for cx in range(x - 5, x + 6):
		for cy in range(y - 5, y + 6):
			if _is_cluster_center(cx, cy):
				var cluster_radius = _get_cluster_radius(cx, cy)
				var dist = sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
				if dist <= cluster_radius:
					return true
	return false

func _is_cluster_center(x: int, y: int) -> bool:
	"""Check if this coordinate is a hotspot cluster center (~0.3% of tiles)"""
	# Use a different hash to determine cluster centers
	var hash_val = abs((x * 73 + y * 127) * 9311) % 1000
	return hash_val < 3  # 0.3% chance to be a cluster center

func _get_cluster_radius(x: int, y: int) -> float:
	"""Get the radius of a hotspot cluster (results in 1-20 connected tiles)"""
	# Use coordinate hash to determine cluster size (radius 0.5 to 2.5)
	# radius 0.5 = ~1 tile, radius 2.5 = ~20 tiles
	var hash_val = abs((x * 41 + y * 83) * 5717) % 100
	return 0.5 + (hash_val / 100.0) * 2.0  # 0.5 to 2.5 radius

func _get_hotspot_intensity(x: int, y: int) -> float:
	"""Get the intensity of the hotspot (for level multiplier)"""
	# Find the closest cluster center and calculate intensity based on distance
	var min_dist = 999.0
	var cluster_x = x
	var cluster_y = y

	for cx in range(x - 5, x + 6):
		for cy in range(y - 5, y + 6):
			if _is_cluster_center(cx, cy):
				var dist = sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
				if dist < min_dist:
					min_dist = dist
					cluster_x = cx
					cluster_y = cy

	# Intensity is higher at cluster center, decreases toward edges
	var radius = _get_cluster_radius(cluster_x, cluster_y)
	var intensity = 1.0 - (min_dist / (radius + 0.1))
	return clamp(intensity, 0.0, 1.0)

func move_player(current_x: int, current_y: int, direction: int) -> Vector2i:
	"""Move player based on numpad direction (P4 style)
	7=NW, 8=N, 9=NE
	4=W,  5=stay, 6=E
	1=SW, 2=S, 3=SE
	"""
	var new_x = current_x
	var new_y = current_y
	
	match direction:
		1:  # Southwest
			new_x -= 1
			new_y -= 1
		2:  # South
			new_y -= 1
		3:  # Southeast
			new_x += 1
			new_y -= 1
		4:  # West
			new_x -= 1
		6:  # East
			new_x += 1
		7:  # Northwest
			new_x -= 1
			new_y += 1
		8:  # North
			new_y += 1
		9:  # Northeast
			new_x += 1
			new_y += 1
		5:  # Stay (rest/search)
			pass
	
	# Clamp to world bounds
	new_x = clampi(new_x, WORLD_MIN_X, WORLD_MAX_X)
	new_y = clampi(new_y, WORLD_MIN_Y, WORLD_MAX_Y)
	
	return Vector2i(new_x, new_y)

func get_direction_name(direction: int) -> String:
	"""Get name of direction"""
	match direction:
		1: return "southwest"
		2: return "south"
		3: return "southeast"
		4: return "west"
		5: return "here"
		6: return "east"
		7: return "northwest"
		8: return "north"
		9: return "northeast"
	return "unknown"

# ===== PROCEDURAL TRAVELING MERCHANT SYSTEM =====
# Lightweight merchant system - positions calculated on-demand, not simulated
# Merchants travel between trading posts with deterministic positions based on time

# Total number of wandering merchants in the world
# Since positions are calculated on-demand (not simulated), more merchants has minimal server cost
const TOTAL_WANDERING_MERCHANTS = 260

# Merchant type templates for variety
# Each type has a specialty that affects inventory and map color
const MERCHANT_TYPES = [
	# Weapons (Red on map)
	{"prefix": "Traveling", "suffix": "Weaponsmith", "specialty": "weapons", "services": ["buy", "sell", "upgrade"]},
	{"prefix": "Grizzled", "suffix": "Blademaster", "specialty": "weapons", "services": ["buy", "sell", "upgrade"]},
	# Armor (Blue on map)
	{"prefix": "Wandering", "suffix": "Armorer", "specialty": "armor", "services": ["buy", "sell", "upgrade"]},
	{"prefix": "Dwarven", "suffix": "Smithy", "specialty": "armor", "services": ["buy", "sell", "upgrade"]},
	# Jewelry (Purple on map)
	{"prefix": "Mysterious", "suffix": "Jeweler", "specialty": "jewelry", "services": ["buy", "sell", "gamble"]},
	{"prefix": "Exotic", "suffix": "Dealer", "specialty": "jewelry", "services": ["buy", "sell", "gamble"]},
	# Potions (Green on map)
	{"prefix": "Wandering", "suffix": "Alchemist", "specialty": "potions", "services": ["buy", "sell"]},
	{"prefix": "Hooded", "suffix": "Herbalist", "specialty": "potions", "services": ["buy", "sell"]},
	# Scrolls (Cyan on map)
	{"prefix": "Arcane", "suffix": "Scribe", "specialty": "scrolls", "services": ["buy", "sell"]},
	{"prefix": "Mystical", "suffix": "Sage", "specialty": "scrolls", "services": ["buy", "sell", "gamble"]},
	# General (Gold on map)
	{"prefix": "Lucky", "suffix": "Gambler", "specialty": "all", "services": ["buy", "sell", "gamble"]},
	{"prefix": "Old", "suffix": "Trader", "specialty": "all", "services": ["buy", "sell", "upgrade"]},
	{"prefix": "Swift", "suffix": "Peddler", "specialty": "all", "services": ["buy", "sell"]},
	{"prefix": "Master", "suffix": "Merchant", "specialty": "all", "services": ["buy", "sell", "upgrade", "gamble"]},
	# Elite (White on map) - Rare, sells everything with better odds
	{"prefix": "Legendary", "suffix": "Collector", "specialty": "elite", "services": ["buy", "sell", "upgrade", "gamble"]},
	# === AFFIX-FOCUSED MERCHANTS (sell equipment with guaranteed stat affixes) ===
	# Warrior gear (Orange on map) - STR, CON, Stamina, Attack affixes
	{"prefix": "Veteran", "suffix": "Outfitter", "specialty": "warrior_affixes", "services": ["buy", "sell", "upgrade"]},
	{"prefix": "Battle-worn", "suffix": "Supplier", "specialty": "warrior_affixes", "services": ["buy", "sell", "upgrade"]},
	# Mage gear (Light Blue on map) - INT, WIS, Mana affixes
	{"prefix": "Enchanted", "suffix": "Emporium", "specialty": "mage_affixes", "services": ["buy", "sell", "upgrade"]},
	{"prefix": "Arcane", "suffix": "Outfitter", "specialty": "mage_affixes", "services": ["buy", "sell", "upgrade"]},
	# Trickster gear (Lime on map) - DEX, WITS, Energy, Speed affixes
	{"prefix": "Shadowy", "suffix": "Fence", "specialty": "trickster_affixes", "services": ["buy", "sell", "upgrade"]},
	{"prefix": "Cunning", "suffix": "Dealer", "specialty": "trickster_affixes", "services": ["buy", "sell", "upgrade"]},
	# Tank gear (Gray on map) - HP, Defense, CON affixes
	{"prefix": "Ironclad", "suffix": "Supplier", "specialty": "tank_affixes", "services": ["buy", "sell", "upgrade"]},
	{"prefix": "Stalwart", "suffix": "Armorer", "specialty": "tank_affixes", "services": ["buy", "sell", "upgrade"]},
	# DPS gear (Yellow on map) - Attack, Speed, STR affixes
	{"prefix": "Keen", "suffix": "Bladedealer", "specialty": "dps_affixes", "services": ["buy", "sell", "upgrade"]},
	{"prefix": "Swift", "suffix": "Striker", "specialty": "dps_affixes", "services": ["buy", "sell", "upgrade"]},
]

# Name parts for generating unique merchant names
const MERCHANT_FIRST_NAMES = ["Grim", "Kira", "Marcus", "Zara", "Lou", "Mira", "Tom", "Vex", "Rook", "Sage",
	"Finn", "Nora", "Brock", "Ivy", "Cole", "Luna", "Rex", "Faye", "Jax", "Wren"]

# Trading post IDs for routing (referenced by index for efficiency)
const TRADING_POST_IDS = [
	# Core zone (0-30 distance)
	"haven", "crossroads", "south_gate", "east_market", "west_shrine",
	# Inner zone (30-75 distance)
	"northeast_farm", "northwest_mill", "southeast_mine", "southwest_grove",
	"northwatch", "eastern_camp", "western_refuge", "southern_watch",
	"northeast_tower", "northwest_inn", "southeast_bridge", "southwest_temple",
	# Mid zone (75-200 distance)
	"frostgate", "highland_post", "eastwatch", "westhold", "southport",
	"northeast_bastion", "northwest_lodge", "southeast_outpost", "southwest_camp",
	# Mid-outer zone (200-350 distance)
	"far_east_station", "far_west_haven", "deep_south_port", "high_north_peak",
	"northeast_frontier", "northwest_citadel", "southeast_garrison", "southwest_fortress",
	# Outer zone (350-500 distance)
	"shadowmere", "inferno_outpost", "voids_edge", "frozen_reach",
	"abyssal_depths", "celestial_spire", "storm_peak", "dragons_rest",
	# Extreme zone (500-700 distance)
	"primordial_sanctum", "nether_gate", "eastern_terminus", "western_terminus",
	"chaos_refuge", "entropy_station", "oblivion_watch", "genesis_point",
	# World's edge (700+ distance)
	"world_spine_north", "world_spine_south", "eternal_east", "eternal_west",
	"apex_northeast", "apex_southeast", "apex_northwest", "apex_southwest"
]

# Merchant travel parameters
# Slower speed so players can follow merchants on the map
const MERCHANT_SPEED = 0.02  # Tiles per second (1 tile every 50 seconds - very slow, easy to follow)
const MERCHANT_JOURNEY_TIME = 900.0  # ~15 minutes per journey segment (longer journeys)
const MERCHANT_REST_TIME = 300.0  # 5 minutes rest at each trading post (longer rest for catchup)

# Cache for merchant positions (cleared periodically)
var _merchant_cache: Dictionary = {}
var _merchant_cache_time: float = 0.0
const MERCHANT_CACHE_DURATION = 30.0  # Recalculate every 30 seconds

func _get_total_merchants() -> int:
	return TOTAL_WANDERING_MERCHANTS

func _get_elite_merchant_route(merchant_idx: int) -> Dictionary:
	"""Get route for elite merchants - they stay in outer zones (100+ from center).
	Destinations are weighted toward the outer edge of the map."""
	# Find all posts that are at least 100 distance from center
	var outer_posts: Array = []
	for i in range(TRADING_POST_IDS.size()):
		var post_id = TRADING_POST_IDS[i]
		var post = trading_post_db.get_trading_post_by_id(post_id)
		if post.is_empty():
			continue
		var dist = sqrt(pow(post.center.x, 2) + pow(post.center.y, 2))
		if dist >= 100:
			outer_posts.append({"idx": i, "id": post_id, "dist": dist})

	if outer_posts.size() < 2:
		# Fallback if not enough outer posts
		return {"home_id": "shadowmere", "dest_id": "voids_edge", "home_idx": 26, "dest_idx": 27}

	# Use merchant index to pick home post from outer posts
	var home_idx_in_outer = merchant_idx % outer_posts.size()
	var home_post = outer_posts[home_idx_in_outer]

	# Pick destination weighted toward furthest posts
	# Sort by distance descending and pick from top half more often
	outer_posts.sort_custom(func(a, b): return a.dist > b.dist)

	# Use a different seed for destination selection
	var dest_seed = (merchant_idx * 31 + 17) % outer_posts.size()
	# Bias toward outer posts: 70% chance to pick from outer half
	var pick_outer = ((merchant_idx * 7) % 10) < 7
	var dest_idx_in_outer: int
	if pick_outer and outer_posts.size() > 1:
		# Pick from outer half (sorted by distance, so first half is furthest)
		dest_idx_in_outer = dest_seed % maxi(1, outer_posts.size() / 2)
	else:
		# Pick from anywhere in outer posts
		dest_idx_in_outer = dest_seed

	# Make sure destination is different from home
	if dest_idx_in_outer == home_idx_in_outer:
		dest_idx_in_outer = (dest_idx_in_outer + 1) % outer_posts.size()

	var dest_post = outer_posts[dest_idx_in_outer]

	return {
		"home_id": home_post.id,
		"dest_id": dest_post.id,
		"home_idx": home_post.idx,
		"dest_idx": dest_post.idx
	}

func _get_merchant_route(merchant_idx: int) -> Dictionary:
	"""Get the route for a specific merchant based on their index.
	Elite merchants (0-7) use special outer-zone routing.
	Other merchants are spread evenly across all zones."""

	# Elite merchants have special routing - they stay in outer zones
	if _is_elite_merchant(merchant_idx):
		return _get_elite_merchant_route(merchant_idx)

	var num_posts = TRADING_POST_IDS.size()

	# Zone boundaries in TRADING_POST_IDS:
	# 0-4: Core zone (5 posts) - 25% of merchants (reduced from 40%)
	# 5-16: Inner zone (12 posts) - 25% of merchants (reduced from 30%)
	# 17-25: Mid zone (9 posts) - 25% of merchants (increased from 15%)
	# 26+: Outer zones (32 posts) - 25% of merchants (increased from 15%)
	# This ensures merchants are findable everywhere, not just near spawn

	# Adjust merchant_idx to account for elite merchants (0-7)
	var adjusted_idx = merchant_idx - 8

	var home_post_idx: int
	var zone_roll = adjusted_idx % 100

	if zone_roll < 25:  # 25% in core zone
		home_post_idx = (adjusted_idx * 3) % 5  # Posts 0-4
	elif zone_roll < 50:  # 25% in inner zone
		home_post_idx = 5 + ((adjusted_idx * 7) % 12)  # Posts 5-16
	elif zone_roll < 75:  # 25% in mid zone
		home_post_idx = 17 + ((adjusted_idx * 11) % 9)  # Posts 17-25
	else:  # 25% in outer zones
		home_post_idx = 26 + ((adjusted_idx * 13) % (num_posts - 26))  # Posts 26+

	# Destination varies - some stay local, some travel far
	# This creates more varied travel patterns visible on the map
	var dest_offset = ((adjusted_idx * 17) % 15) + 1  # 1-15 posts away (increased range)
	var dest_post_idx = (home_post_idx + dest_offset) % num_posts

	# Ensure destination is different from home
	if dest_post_idx == home_post_idx:
		dest_post_idx = (dest_post_idx + 1) % num_posts

	return {
		"home_id": TRADING_POST_IDS[home_post_idx],
		"dest_id": TRADING_POST_IDS[dest_post_idx],
		"home_idx": home_post_idx,
		"dest_idx": dest_post_idx
	}

func _get_merchant_position(merchant_idx: int, current_time: float) -> Dictionary:
	"""Calculate where a merchant is right now based on time.
	Returns {x, y, is_resting, at_post}"""
	var route = _get_merchant_route(merchant_idx)

	var home_post = trading_post_db.get_trading_post_by_id(route.home_id)
	var dest_post = trading_post_db.get_trading_post_by_id(route.dest_id)

	if home_post.is_empty() or dest_post.is_empty():
		return {"x": 0, "y": 0, "is_resting": true, "at_post": "haven"}

	# Calculate journey cycle time (travel + rest at each end)
	var home_x = float(home_post.center.x)
	var home_y = float(home_post.center.y)
	var dest_x = float(dest_post.center.x)
	var dest_y = float(dest_post.center.y)

	var route_dist = sqrt(pow(dest_x - home_x, 2) + pow(dest_y - home_y, 2))
	var travel_time = route_dist / MERCHANT_SPEED if MERCHANT_SPEED > 0 else MERCHANT_JOURNEY_TIME
	travel_time = min(travel_time, MERCHANT_JOURNEY_TIME)  # Cap journey time

	# Full cycle: rest at home -> travel to dest -> rest at dest -> travel home
	var cycle_time = (travel_time + MERCHANT_REST_TIME) * 2

	# Add offset based on merchant index so they're not all synchronized
	var time_offset = float(merchant_idx * 137) # Prime number for spread
	var cycle_position = fmod(current_time + time_offset, cycle_time)

	# Determine phase: 0=resting at home, 1=traveling to dest, 2=resting at dest, 3=traveling home
	var phase_time = cycle_time / 4.0
	var phase = int(cycle_position / phase_time) % 4
	var phase_progress = fmod(cycle_position, phase_time) / phase_time

	match phase:
		0:  # Resting at home
			return {"x": int(home_x), "y": int(home_y), "is_resting": true, "at_post": route.home_id}
		1:  # Traveling to destination
			var x = home_x + (dest_x - home_x) * phase_progress
			var y = home_y + (dest_y - home_y) * phase_progress
			return {"x": int(round(x)), "y": int(round(y)), "is_resting": false, "at_post": ""}
		2:  # Resting at destination
			return {"x": int(dest_x), "y": int(dest_y), "is_resting": true, "at_post": route.dest_id}
		3:  # Traveling home
			var x = dest_x + (home_x - dest_x) * phase_progress
			var y = dest_y + (home_y - dest_y) * phase_progress
			return {"x": int(round(x)), "y": int(round(y)), "is_resting": false, "at_post": ""}

	return {"x": int(home_x), "y": int(home_y), "is_resting": true, "at_post": route.home_id}

# Inventory refresh interval (5 minutes)
const INVENTORY_REFRESH_INTERVAL = 300.0

func _is_elite_merchant(merchant_idx: int) -> bool:
	"""Check if a merchant index is one of the 8 elite merchants."""
	# Elite merchants are indices 0-7 (the first 8 merchants are elite)
	# They have special routing that keeps them in outer zones
	return merchant_idx < 8

func _get_merchant_info(merchant_idx: int) -> Dictionary:
	"""Generate merchant info based on index (deterministic)"""
	var name_idx = merchant_idx % MERCHANT_FIRST_NAMES.size()

	# Elite merchants are VERY rare - only 8 total, they roam the outer zones
	var merchant_type: Dictionary
	if _is_elite_merchant(merchant_idx):
		# Find the elite type in MERCHANT_TYPES
		for mt in MERCHANT_TYPES:
			if mt.specialty == "elite":
				merchant_type = mt
				break
	else:
		# Normal merchant type assignment (skip elite type at index 14)
		# Offset by 8 since indices 0-7 are reserved for elite
		var adjusted_idx = merchant_idx - 8
		var type_idx = adjusted_idx % (MERCHANT_TYPES.size() - 1)  # -1 to exclude elite
		if type_idx >= 14:  # Elite is at index 14, skip it
			type_idx += 1
		merchant_type = MERCHANT_TYPES[type_idx]

	# Inventory seed changes every 5 minutes
	var time_window = int(Time.get_unix_time_from_system() / INVENTORY_REFRESH_INTERVAL)
	var inventory_seed = (merchant_idx * 7919 + time_window * 104729) % 2147483647

	return {
		"id": "merchant_%d" % merchant_idx,
		"name": "%s %s %s" % [merchant_type.prefix, MERCHANT_FIRST_NAMES[name_idx], merchant_type.suffix],
		"specialty": merchant_type.specialty,
		"services": merchant_type.services,
		"inventory_seed": inventory_seed
	}

func _refresh_merchant_cache():
	"""Refresh the merchant position cache if needed"""
	var current_time = Time.get_unix_time_from_system()
	if current_time - _merchant_cache_time < MERCHANT_CACHE_DURATION and not _merchant_cache.is_empty():
		return

	_merchant_cache.clear()
	_merchant_cache_time = current_time

	var total = _get_total_merchants()
	for i in range(total):
		var pos = _get_merchant_position(i, current_time)
		var key = "%d,%d" % [pos.x, pos.y]
		if not _merchant_cache.has(key):
			_merchant_cache[key] = []
		_merchant_cache[key].append(i)

func update_merchants(_delta: float = 0.0):
	"""Lightweight update - just refresh cache periodically"""
	_refresh_merchant_cache()

func is_merchant_at(x: int, y: int) -> bool:
	"""Check if any merchant is at this location"""
	_refresh_merchant_cache()
	var key = "%d,%d" % [x, y]
	return _merchant_cache.has(key)

func get_merchant_at(x: int, y: int) -> Dictionary:
	"""Get merchant info for this location"""
	_refresh_merchant_cache()
	var key = "%d,%d" % [x, y]

	if not _merchant_cache.has(key):
		return {}

	# Get the first merchant at this location
	var merchant_idx = _merchant_cache[key][0]
	var info = _get_merchant_info(merchant_idx)
	var pos = _get_merchant_position(merchant_idx, Time.get_unix_time_from_system())
	var route = _get_merchant_route(merchant_idx)

	# Get destination info
	var dest_post = trading_post_db.get_trading_post_by_id(route.dest_id)
	var home_post = trading_post_db.get_trading_post_by_id(route.home_id)

	return {
		"id": info.id,
		"name": info.name,
		"services": info.services,
		"specialty": info.specialty,
		"x": x,
		"y": y,
		"hash": info.inventory_seed,
		"is_wanderer": false,
		"destination": dest_post.get("name", "Unknown") if not pos.is_resting else "",
		"destination_id": route.dest_id,
		"next_destination": home_post.get("name", "Unknown"),
		"next_destination_id": route.home_id,
		"last_restock": Time.get_unix_time_from_system(),
		"is_resting": pos.is_resting,
		"at_post": pos.at_post
	}

func get_all_merchant_positions() -> Array:
	"""Get positions of all merchants for map display (within reasonable range)"""
	_refresh_merchant_cache()

	var positions = []
	for key in _merchant_cache:
		var parts = key.split(",")
		var x = int(parts[0])
		var y = int(parts[1])
		var merchant_idx = _merchant_cache[key][0]
		var info = _get_merchant_info(merchant_idx)
		positions.append({"x": x, "y": y, "name": info.name})

	return positions

func get_merchants_near(center_x: int, center_y: int, radius: int = 10) -> Array:
	"""Get merchants within a radius of a position (for map display)"""
	_refresh_merchant_cache()

	var nearby = []
	for key in _merchant_cache:
		var parts = key.split(",")
		var x = int(parts[0])
		var y = int(parts[1])
		if abs(x - center_x) <= radius and abs(y - center_y) <= radius:
			var merchant_idx = _merchant_cache[key][0]
			var info = _get_merchant_info(merchant_idx)
			nearby.append({"x": x, "y": y, "name": info.name})

	return nearby

func check_merchant_encounter(x: int, y: int) -> bool:
	"""Check if player encounters a merchant at this location"""
	return is_merchant_at(x, y)

func _get_merchant_map_color(x: int, y: int) -> String:
	"""Get the map display color for a merchant based on their specialty."""
	_refresh_merchant_cache()
	var key = "%d,%d" % [x, y]

	if not _merchant_cache.has(key):
		return "#FFD700"  # Default gold

	var merchant_idx = _merchant_cache[key][0]
	var info = _get_merchant_info(merchant_idx)
	var specialty = info.get("specialty", "all")

	match specialty:
		"weapons":
			return "#FF4444"  # Red for weapons
		"armor":
			return "#4488FF"  # Blue for armor
		"jewelry":
			return "#AA44FF"  # Purple for jewelry
		"potions":
			return "#44FF44"  # Bright green for potions/consumables
		"scrolls":
			return "#44FFFF"  # Cyan for scrolls
		"elite":
			return "#FFFFFF"  # White for elite/legendary merchants
		# Affix-focused merchants
		"warrior_affixes":
			return "#FF8C00"  # Orange for warrior gear (STR/CON/Stamina)
		"mage_affixes":
			return "#87CEEB"  # Light blue for mage gear (INT/WIS/Mana)
		"trickster_affixes":
			return "#32CD32"  # Lime green for trickster gear (DEX/WITS/Energy)
		"tank_affixes":
			return "#A9A9A9"  # Gray for tank gear (HP/DEF/CON)
		"dps_affixes":
			return "#FFFF44"  # Yellow for DPS gear (ATK/Speed/STR)
		_:
			return "#FFD700"  # Gold for general merchants

func _get_merchant_map_char(x: int, y: int) -> String:
	"""Get the map display character for a merchant. Elite merchants get ★, others get $."""
	_refresh_merchant_cache()
	var key = "%d,%d" % [x, y]

	if not _merchant_cache.has(key):
		return "$"  # Default

	var merchant_idx = _merchant_cache[key][0]
	if _is_elite_merchant(merchant_idx):
		return "★"  # Elite merchants are visually distinct
	return "$"  # Normal merchants

func generate_ascii_map_with_merchants(center_x: int, center_y: int, radius: int = 7, nearby_players: Array = []) -> String:
	"""Generate ASCII map with merchants, Trading Posts, and other players shown.
	nearby_players is an array of {x, y, name, level} dictionaries for other players to display."""
	var map_lines: PackedStringArray = PackedStringArray()

	# Build a lookup for player positions (excluding self at center)
	var player_positions = {}
	for player in nearby_players:
		var key = "%d,%d" % [player.x, player.y]
		if not player_positions.has(key):
			player_positions[key] = []
		player_positions[key].append(player)

	for dy in range(radius, -radius - 1, -1):
		var line_parts: PackedStringArray = PackedStringArray()
		for dx in range(-radius, radius + 1):
			var x = center_x + dx
			var y = center_y + dy

			if x < WORLD_MIN_X or x > WORLD_MAX_X or y < WORLD_MIN_Y or y > WORLD_MAX_Y:
				line_parts.append("  ")
				continue

			var pos_key = "%d,%d" % [x, y]

			if dx == 0 and dy == 0:
				line_parts.append("[color=#FFFF00] @[/color]")
			elif player_positions.has(pos_key):
				# Show other player - use first letter of name in cyan
				var players_here = player_positions[pos_key]
				var first_player = players_here[0]
				var player_char = first_player.name[0].to_upper() if first_player.name.length() > 0 else "?"
				# Multiple players: show * instead
				if players_here.size() > 1:
					player_char = "*"
				line_parts.append("[color=#00FFFF] %s[/color]" % player_char)
			elif trading_post_db and trading_post_db.is_trading_post_tile(x, y):
				# Trading Post tiles with special rendering
				var tp_char = trading_post_db.get_tile_position_in_post(x, y)
				if tp_char == "P":
					# Center - gold P
					line_parts.append("[color=#FFD700] P[/color]")
				elif tp_char == "+":
					# Corners - tan
					line_parts.append("[color=#D2B48C] +[/color]")
				elif tp_char == "-":
					# Horizontal edges - tan
					line_parts.append("[color=#D2B48C] -[/color]")
				elif tp_char == "|":
					# Vertical edges - tan
					line_parts.append("[color=#D2B48C] |[/color]")
				else:
					# Interior - light background
					line_parts.append("[color=#C4A84B] .[/color]")
			elif is_merchant_at(x, y):
				# Show merchant with color based on specialty
				# Elite merchants get a special ★ symbol, others get $
				var merchant_color = _get_merchant_map_color(x, y)
				var merchant_char = _get_merchant_map_char(x, y)
				line_parts.append("[color=%s] %s[/color]" % [merchant_color, merchant_char])
			else:
				var terrain = get_terrain_at(x, y)
				var info = get_terrain_info(terrain)

				if _is_hotspot(x, y) and not info.safe:
					var intensity = _get_hotspot_intensity(x, y)
					var hotspot_color = "#FF4500" if intensity > 0.5 else "#FF6600"
					line_parts.append("[color=%s] ![/color]" % hotspot_color)
				else:
					line_parts.append("[color=%s] %s[/color]" % [info.color, info.char])

		map_lines.append("".join(line_parts))

	return "\n".join(map_lines)

# ===== TRADING POST HELPERS =====

func is_trading_post_tile(x: int, y: int) -> bool:
	"""Check if tile is part of any Trading Post"""
	if trading_post_db:
		return trading_post_db.is_trading_post_tile(x, y)
	return false

func get_trading_post_at(x: int, y: int) -> Dictionary:
	"""Get Trading Post data if at one, empty dict otherwise"""
	if trading_post_db:
		return trading_post_db.get_trading_post_at(x, y)
	return {}

func is_trading_post_center(x: int, y: int) -> bool:
	"""Check if tile is the center of a Trading Post"""
	if trading_post_db:
		return trading_post_db.is_trading_post_center(x, y)
	return false

func find_nearby_hotzone(x: int, y: int, max_distance: float) -> Dictionary:
	"""Find the nearest hotzone within the specified distance.
	Returns {found: bool, x: int, y: int, distance: float, intensity: float} or {found: false}"""
	# Search in a spiral pattern outward from the position
	var search_radius = int(max_distance) + 1

	var nearest_hotzone = {"found": false}
	var nearest_dist = max_distance + 1

	for check_x in range(x - search_radius, x + search_radius + 1):
		for check_y in range(y - search_radius, y + search_radius + 1):
			var dist = sqrt(float((check_x - x) * (check_x - x) + (check_y - y) * (check_y - y)))
			if dist <= max_distance and dist < nearest_dist:
				if _is_hotspot(check_x, check_y):
					nearest_dist = dist
					nearest_hotzone = {
						"found": true,
						"x": check_x,
						"y": check_y,
						"distance": dist,
						"intensity": _get_hotspot_intensity(check_x, check_y)
					}

	return nearest_hotzone

func find_hotzones_within_distance(x: int, y: int, max_distance: float) -> Array:
	"""Find all hotzones within the specified distance.
	Returns array of {x, y, distance, intensity}"""
	var hotzones = []
	var search_radius = int(max_distance) + 1

	for check_x in range(x - search_radius, x + search_radius + 1):
		for check_y in range(y - search_radius, y + search_radius + 1):
			var dist = sqrt(float((check_x - x) * (check_x - x) + (check_y - y) * (check_y - y)))
			if dist <= max_distance and _is_hotspot(check_x, check_y):
				hotzones.append({
					"x": check_x,
					"y": check_y,
					"distance": dist,
					"intensity": _get_hotspot_intensity(check_x, check_y)
				})

	return hotzones

func to_dict() -> Dictionary:
	"""Serialize world system state"""
	return {
		"world_bounds": {
			"min_x": WORLD_MIN_X,
			"max_x": WORLD_MAX_X,
			"min_y": WORLD_MIN_Y,
			"max_y": WORLD_MAX_Y
		}
	}
