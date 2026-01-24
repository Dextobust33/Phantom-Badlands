# world_system.gd
# Phantasia 4-style coordinate-based world system
class_name WorldSystem
extends Node

# World boundaries (Phantasia 4 had a large world)
const WORLD_MIN_X = -1000
const WORLD_MAX_X = 1000
const WORLD_MIN_Y = -1000
const WORLD_MAX_Y = 1000

# Terrain types (matching P4)
enum Terrain {
	THRONE,          # (0,0) - King's throne
	CITY,            # Safe zone, shops
	TRADING_POST,    # Buy/sell
	PLAINS,          # Basic terrain, low danger
	FOREST,          # Light encounters
	DEEP_FOREST,     # Medium danger
	MOUNTAINS,       # High danger
	SWAMP,           # High danger
	DESERT,          # Very high danger
	VOLCANO,         # Extreme danger
	DARK_CIRCLE,     # Special area
	VOID             # Beyond the edge
}

# Special locations (like P4)
const SPECIAL_LOCATIONS = {
	Vector2i(0, 0): {"terrain": Terrain.THRONE, "name": "Throne Room", "description": "The magnificent throne of the realm"},
	Vector2i(0, 10): {"terrain": Terrain.CITY, "name": "Sanctuary", "description": "A safe haven for travelers"},
	Vector2i(0, -10): {"terrain": Terrain.CITY, "name": "Northtown", "description": "A bustling northern city"},
	Vector2i(400, 0): {"terrain": Terrain.DARK_CIRCLE, "name": "Dark Circle", "description": "A place of great danger and power"},
	Vector2i(-400, 0): {"terrain": Terrain.VOLCANO, "name": "Fire Mountain", "description": "An active volcano"},
}

func _ready():
	print("World System initialized - Phantasia 4 style")

func get_terrain_at(x: int, y: int) -> Terrain:
	"""Determine terrain based on coordinates (procedural like P4)"""
	var pos = Vector2i(x, y)
	
	# Check special locations first
	if SPECIAL_LOCATIONS.has(pos):
		return SPECIAL_LOCATIONS[pos].terrain
	
	# Throne area (close to 0,0)
	var distance_from_throne = sqrt(x * x + y * y)
	
	if distance_from_throne < 5:
		return Terrain.CITY
	elif distance_from_throne < 50:
		return Terrain.PLAINS
	elif distance_from_throne < 100:
		# Use coordinate hash for variety
		var hash_val = abs(x * 7 + y * 13) % 100
		if hash_val < 40:
			return Terrain.FOREST
		elif hash_val < 70:
			return Terrain.PLAINS
		else:
			return Terrain.MOUNTAINS
	elif distance_from_throne < 200:
		var hash_val = abs(x * 7 + y * 13) % 100
		if hash_val < 30:
			return Terrain.DEEP_FOREST
		elif hash_val < 50:
			return Terrain.MOUNTAINS
		elif hash_val < 70:
			return Terrain.SWAMP
		else:
			return Terrain.FOREST
	elif distance_from_throne < 400:
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
	
	return {"name": "Unknown", "char": "?", "color": "#FFFFFF", "safe": false}

func get_location_name(x: int, y: int) -> String:
	"""Get the name of a location"""
	var pos = Vector2i(x, y)
	
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

		desc += "[color=#FF6B6B]Danger:[/color] Monsters level %d-%d\n" % [level_range.min, level_range.max]
		desc += "[color=#FF6B6B]Encounter Rate:[/color] %.0f%%\n" % (info.encounter_rate * 100)
	else:
		desc += "[color=#90EE90]This is a safe area[/color]\n"

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

func generate_map_display(center_x: int, center_y: int, radius: int = 7) -> String:
	"""Generate complete map display with location info header"""
	var output = ""

	# Get location info
	var terrain = get_terrain_at(center_x, center_y)
	var info = get_terrain_info(terrain)

	# Get distance-based level range
	var level_range = get_monster_level_range(center_x, center_y)

	# Location header (left-aligned with emphasized coordinates)
	output += "[color=#B8860B]Location:[/color] [color=#5F9EA0][b](%d, %d)[/b][/color]\n" % [center_x, center_y]
	output += "[color=#B8860B]Terrain:[/color] %s\n" % info.name

	# Merchant at current location
	if is_merchant_at(center_x, center_y):
		var merchant = get_merchant_at(center_x, center_y)
		output += "[color=#FFD700][b]%s nearby![/b][/color]\n" % merchant.name

	# Danger info based on distance
	if not info.safe and level_range.min > 0:
		# Hotspot warning
		if level_range.is_hotspot:
			output += "[color=#FF0000][b]!!! DANGER ZONE !!![/b][/color]\n"
		output += "[color=#FF6B6B]Danger:[/color] Level %d-%d monsters\n" % [level_range.min, level_range.max]
	else:
		output += "[color=#90EE90]Safe Zone[/color]\n"

	output += "\n"

	# Add the map (centered)
	output += "[center]"
	output += generate_ascii_map_with_merchants(center_x, center_y, radius)
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

	# Calculate variance range (+/- 15%)
	var variance = max(1, int(adjusted_level * 0.15))
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
	"""Convert distance from origin to monster level (0-1414 -> 1-10000)"""
	# Safe zone (distance 0-5)
	if distance <= 5:
		return 1

	# Distance 5-100: Levels 1-50 (gentle curve)
	if distance <= 100:
		var t = (distance - 5) / 95.0  # 0 to 1
		return int(1 + t * 49)

	# Distance 100-300: Levels 50-300 (moderate growth)
	if distance <= 300:
		var t = (distance - 100) / 200.0  # 0 to 1
		return int(50 + t * 250)

	# Distance 300-600: Levels 300-1500 (accelerating)
	if distance <= 600:
		var t = (distance - 300) / 300.0  # 0 to 1
		return int(300 + t * 1200)

	# Distance 600-900: Levels 1500-5000 (steep)
	if distance <= 900:
		var t = (distance - 600) / 300.0  # 0 to 1
		return int(1500 + t * 3500)

	# Distance 900+: Levels 5000-10000 (approaching max)
	# Max distance is ~1414 (corners of 1000x1000 world)
	var t = min(1.0, (distance - 900) / 514.0)  # 0 to 1
	return int(5000 + t * 5000)

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

# ===== TRAVELING MERCHANT SYSTEM =====

func is_merchant_at(x: int, y: int) -> bool:
	"""Check if a traveling merchant is at this location"""
	# Normal merchants: ~0.2% of tiles, move every hour
	var hour_seed = int(Time.get_unix_time_from_system() / 3600)
	var hash_val = abs((x * 97 + y * 61 + hour_seed * 37) * 7919) % 1000
	if hash_val < 2:  # 0.2% chance (reduced from 0.5%)
		return true

	# Wandering traders: ~0.1% of tiles, move every 12 minutes
	var wanderer_seed = int(Time.get_unix_time_from_system() / 720)  # 12 minutes
	var wanderer_hash = abs((x * 53 + y * 89 + wanderer_seed * 23) * 6131) % 1000
	if wanderer_hash < 1:  # 0.1% chance
		return true

	return false

func check_merchant_encounter(x: int, y: int) -> bool:
	"""Check if player encounters a merchant at this location"""
	if is_merchant_at(x, y):
		return true
	return false

func get_merchant_at(x: int, y: int) -> Dictionary:
	"""Get merchant info for this location"""
	if not is_merchant_at(x, y):
		return {}

	# Check if this is a wandering trader (fast-moving) vs normal merchant
	var hour_seed = int(Time.get_unix_time_from_system() / 3600)
	var wanderer_seed = int(Time.get_unix_time_from_system() / 720)  # 12 minutes

	var normal_hash = abs((x * 97 + y * 61 + hour_seed * 37) * 7919) % 1000
	var wanderer_hash = abs((x * 53 + y * 89 + wanderer_seed * 23) * 6131) % 1000

	var is_wanderer = wanderer_hash < 1 and normal_hash >= 2

	# Generate consistent merchant based on location + appropriate time seed
	var hash_val: int
	var merchant_type: String
	var services = ["buy", "sell"]  # All merchants buy/sell

	if is_wanderer:
		hash_val = abs((x * 53 + y * 89 + wanderer_seed * 23))
		merchant_type = "Wandering Trader"
		services.append("upgrade")
		services.append("gamble")
	else:
		hash_val = abs((x * 97 + y * 61 + hour_seed * 37))
		# Normal merchant types
		var merchant_types = ["Mysterious Merchant", "Traveling Smith", "Fortune Teller"]
		merchant_type = merchant_types[hash_val % merchant_types.size()]

		if "Smith" in merchant_type:
			services.append("upgrade")
		if "Fortune" in merchant_type or "Mysterious" in merchant_type:
			services.append("gamble")

	return {
		"name": merchant_type,
		"services": services,
		"x": x,
		"y": y,
		"hash": hash_val,  # For consistent pricing
		"is_wanderer": is_wanderer
	}

func generate_ascii_map_with_merchants(center_x: int, center_y: int, radius: int = 7) -> String:
	"""Generate ASCII map with merchants shown"""
	var map_lines: PackedStringArray = PackedStringArray()

	for dy in range(radius, -radius - 1, -1):
		var line_parts: PackedStringArray = PackedStringArray()
		for dx in range(-radius, radius + 1):
			var x = center_x + dx
			var y = center_y + dy

			if x < WORLD_MIN_X or x > WORLD_MAX_X or y < WORLD_MIN_Y or y > WORLD_MAX_Y:
				line_parts.append("  ")
				continue

			if dx == 0 and dy == 0:
				line_parts.append("[color=#FFFF00] @[/color]")
			elif is_merchant_at(x, y):
				# Show merchant as $ in gold
				line_parts.append("[color=#FFD700] $[/color]")
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
