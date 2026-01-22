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
	
	# Danger info
	if not info.safe and info.monster_level_min > 0:
		desc += "[color=#FF6B6B]Danger:[/color] Monsters level %d-%d\n" % [info.monster_level_min, info.monster_level_max]
		desc += "[color=#FF6B6B]Encounter Rate:[/color] %.0f%%\n" % (info.encounter_rate * 100)
	else:
		desc += "[color=#90EE90]This is a safe area[/color]\n"
	
	return desc

func generate_ascii_map(center_x: int, center_y: int, radius: int = 7) -> String:
	"""Generate ASCII map centered on player (P4 style with proper spacing)"""
	var map_lines = []
	
	# Generate map from top to bottom
	for dy in range(radius, -radius - 1, -1):
		var line = ""
		for dx in range(-radius, radius + 1):
			var x = center_x + dx
			var y = center_y + dy
			
			# Check bounds
			if x < WORLD_MIN_X or x > WORLD_MAX_X or y < WORLD_MIN_Y or y > WORLD_MAX_Y:
				line += "  "  # Two spaces for out of bounds
				continue
			
			# Player position
			if dx == 0 and dy == 0:
				line += "[color=#FFFF00] @[/color]"  # Space before @ for even spacing
			else:
				var terrain = get_terrain_at(x, y)
				var info = get_terrain_info(terrain)
				# Add space BEFORE each character for even grid spacing
				line += "[color=%s] %s[/color]" % [info.color, info.char]
		
		map_lines.append(line)
	
	return "\n".join(map_lines)

func generate_map_display(center_x: int, center_y: int, radius: int = 7) -> String:
	"""Generate complete map display with location info header"""
	var output = ""
	
	# Get location info
	var pos = Vector2i(center_x, center_y)
	var terrain = get_terrain_at(center_x, center_y)
	var info = get_terrain_info(terrain)
	
	# Location header
	output += "[b][color=#FFD700]Location:[/color][/b] (%d, %d)\n" % [center_x, center_y]
	output += "[b][color=#FFD700]Terrain:[/color][/b] %s\n" % info.name
	
	# Danger info if applicable
	if not info.safe and info.monster_level_min > 0:
		output += "[color=#FF6B6B]Danger:[/color] Level %d-%d monsters\n" % [info.monster_level_min, info.monster_level_max]
	else:
		output += "[color=#90EE90]Safe Zone[/color]\n"
	
	output += "\n"
	
	# Add the map
	output += generate_ascii_map(center_x, center_y, radius)
	
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
	"""Get the monster level range for this location"""
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	
	return {
		"min": info.monster_level_min,
		"max": info.monster_level_max
	}

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
