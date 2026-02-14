# world_system.gd
# Procedural world with chunk-based persistence, LOS raycasting, 10+ resource types
class_name WorldSystem
extends Node

# World boundaries
const WORLD_MIN_X = -2000
const WORLD_MAX_X = 2000
const WORLD_MIN_Y = -2000
const WORLD_MAX_Y = 2000

# Vision radius (expanded for dense world with LOS blocking)
const DEFAULT_VISION_RADIUS = 11
const BLIND_VISION_RADIUS = 2

# Terrain types — legacy enum kept for backward compatibility with systems
# that haven't been migrated yet (combat encounter rates, etc.)
enum Terrain {
	THRONE,
	CITY,
	TRADING_POST,
	PLAINS,
	FOREST,
	DEEP_FOREST,
	MOUNTAINS,
	SWAMP,
	DESERT,
	VOLCANO,
	DARK_CIRCLE,
	VOID,
	WATER,
	DEEP_WATER
}

# ===== NEW TILE TYPE SYSTEM =====
# Each tile has a type string, tier, and blocking properties.
# Types: empty, stone, tree, ore_vein, herb, flower, mushroom, bush, reed,
#        dense_brush, water, deep_water, wall, door, floor, path,
#        forge, apothecary, workbench, enchant_table, market, inn,
#        quest_board, tower, guard, post_marker, void

# Node type weights for terrain generation (% of occupied tiles)
const NODE_WEIGHTS = {
	"stone": 25,
	"tree": 25,
	"ore_vein": 10,
	"herb": 5,
	"flower": 5,
	"mushroom": 5,
	"bush": 5,
	"reed": 5,
	"dense_brush": 10,
	# water: 5% — handled separately via noise clustering
}
const TOTAL_NODE_WEIGHT = 95  # sum of above (water excluded, added via noise)

# Tile rendering data: char, base color, blocks_move, blocks_los
const TILE_RENDER = {
	"empty":         {"char": ".", "color": "#555555", "blocks_move": false, "blocks_los": false},
	"stone":         {"char": "o", "color": "#888888", "blocks_move": true, "blocks_los": true},
	"tree":          {"char": "T", "color": "#228B22", "blocks_move": true, "blocks_los": true},
	"ore_vein":      {"char": "*", "color": "#8B6914", "blocks_move": true, "blocks_los": true},
	"herb":          {"char": "\"", "color": "#66CC66", "blocks_move": false, "blocks_los": false},
	"flower":        {"char": "'", "color": "#FF69B4", "blocks_move": false, "blocks_los": false},
	"mushroom":      {"char": ",", "color": "#9966CC", "blocks_move": false, "blocks_los": false},
	"bush":          {"char": ";", "color": "#006600", "blocks_move": false, "blocks_los": false},
	"reed":          {"char": "|", "color": "#66CCCC", "blocks_move": false, "blocks_los": false},
	"dense_brush":   {"char": "%", "color": "#6B8E23", "blocks_move": true, "blocks_los": false},
	"water":         {"char": "~", "color": "#4488FF", "blocks_move": true, "blocks_los": false},
	"deep_water":    {"char": "~", "color": "#2244AA", "blocks_move": true, "blocks_los": false},
	"wall":          {"char": "#", "color": "#CCCCCC", "blocks_move": true, "blocks_los": true},
	"door":          {"char": "+", "color": "#CCAA00", "blocks_move": false, "blocks_los": false},
	"floor":         {"char": ".", "color": "#D4C4A2", "blocks_move": false, "blocks_los": false},
	"path":          {"char": ":", "color": "#C4A882", "blocks_move": false, "blocks_los": false},
	"forge":         {"char": "F", "color": "#FF8800", "blocks_move": true, "blocks_los": false},
	"apothecary":    {"char": "A", "color": "#00CC66", "blocks_move": true, "blocks_los": false},
	"workbench":     {"char": "W", "color": "#AA7744", "blocks_move": true, "blocks_los": false},
	"enchant_table": {"char": "E", "color": "#AA44FF", "blocks_move": true, "blocks_los": false},
	"writing_desk":  {"char": "S", "color": "#87CEEB", "blocks_move": true, "blocks_los": false},
	"market":        {"char": "$", "color": "#FFD700", "blocks_move": true, "blocks_los": false},
	"inn":           {"char": "I", "color": "#FFAA44", "blocks_move": true, "blocks_los": false},
	"quest_board":   {"char": "Q", "color": "#C4A882", "blocks_move": true, "blocks_los": false},
	"throne":        {"char": "T", "color": "#FFD700", "blocks_move": true, "blocks_los": false},
	"tower":         {"char": "^", "color": "#FFFFFF", "blocks_move": false, "blocks_los": false},
	"storage":       {"char": "C", "color": "#AAAAFF", "blocks_move": false, "blocks_los": false},
	"guard":         {"char": "G", "color": "#C0C0C0", "blocks_move": false, "blocks_los": false},
	"post_marker":   {"char": "P", "color": "#FFD700", "blocks_move": false, "blocks_los": false},
	"void":          {"char": " ", "color": "#111111", "blocks_move": true, "blocks_los": true},
}

# Tier color shifts for resources
const TIER_COLORS = {
	"stone": ["#888888", "#888888", "#AAAAAA", "#AAAAAA", "#CCCCDD", "#CCCCDD"],
	"tree": ["#228B22", "#228B22", "#1A6B1A", "#1A6B1A", "#8B6914", "#8B6914"],
	"ore_vein": ["#B87333", "#A0A0A0", "#A0A0A0", "#FFD700", "#4488FF", "#AA44FF"],
}

# Distance-based tier zones (overlapping for gradual transition)
# Each entry: [min_distance, max_distance]
const TIER_ZONES = [
	[0, 200],       # T1
	[150, 400],     # T2
	[300, 700],     # T3
	[500, 1000],    # T4
	[800, 1400],    # T5
	[1200, 2000],   # T6
]

# Gathering job mapping for node types
const NODE_TO_JOB = {
	"stone": "mining",
	"ore_vein": "mining",
	"tree": "logging",
	"dense_brush": "logging",
	"herb": "foraging",
	"flower": "foraging",
	"mushroom": "foraging",
	"bush": "foraging",
	"reed": "foraging",
	"water": "fishing",
}

# Types that can be gathered
const GATHERABLE_TYPES = ["stone", "ore_vein", "tree", "dense_brush", "herb", "flower", "mushroom", "bush", "reed", "water"]

# Special locations - major landmarks only
const SPECIAL_LOCATIONS = {
	Vector2i(400, 0): {"terrain": Terrain.DARK_CIRCLE, "name": "Dark Circle", "description": "A place of great danger and power"},
	Vector2i(-400, 0): {"terrain": Terrain.VOLCANO, "name": "Fire Mountain", "description": "An active volcano"},
}

# Preload Trading Post database (kept for backward compatibility during transition)
const TradingPostDatabaseScript = preload("res://shared/trading_post_database.gd")

# Trading Post database reference (legacy, kept for transition)
var trading_post_db: Node = null

# ChunkManager reference — set by server after initialization
var chunk_manager = null  # ChunkManager

func _ready():
	print("World System initialized")
	# Initialize legacy trading post database (kept for transition)
	trading_post_db = TradingPostDatabaseScript.new()
	add_child(trading_post_db)

# ===== NEW PROCEDURAL TILE GENERATION =====

func generate_tile(world_x: int, world_y: int, seed: int) -> Dictionary:
	"""Generate a tile procedurally from world seed + coordinates.
	Returns {type, tier, blocks_move, blocks_los}"""
	var distance = sqrt(float(world_x * world_x + world_y * world_y))

	# Safe zone at very center (radius 5) — always empty
	if distance < 5:
		return {"type": "empty", "tier": 0, "blocks_move": false, "blocks_los": false}

	# NPC post interiors should not generate resources (stamped tiles override this,
	# but this is a safety net for any tiles not explicitly stamped)
	if chunk_manager and chunk_manager.is_npc_post_tile(world_x, world_y):
		return {"type": "empty", "tier": 0, "blocks_move": false, "blocks_los": false}

	# Check for water first using noise clustering
	if _is_water_tile_generated(world_x, world_y, seed):
		# Determine shallow vs deep
		var deep_noise = _seeded_hash_float(world_x * 97 + world_y * 151, seed + 999)
		if deep_noise > 0.75 and distance > 200:
			return {"type": "deep_water", "tier": 0, "blocks_move": true, "blocks_los": false}
		return {"type": "water", "tier": 0, "blocks_move": true, "blocks_los": false}

	# Density check — ramps from 50% near origin to 70% at edges
	var density = 0.50 + 0.20 * clampf(distance / 2000.0, 0.0, 1.0)
	var density_roll = _seeded_hash_float(world_x * 7 + world_y * 13, seed)
	if density_roll >= density:
		return {"type": "empty", "tier": 0, "blocks_move": false, "blocks_los": false}

	# This tile is occupied — determine node type
	var type_roll = _seeded_hash_int(world_x * 31 + world_y * 53, seed + 1) % TOTAL_NODE_WEIGHT
	var node_type = _roll_node_type(type_roll)

	# Determine tier from distance
	var tier = _get_tier_for_distance(distance, world_x, world_y, seed)

	# Get blocking properties from TILE_RENDER
	var render = TILE_RENDER.get(node_type, TILE_RENDER["empty"])

	return {
		"type": node_type,
		"tier": tier,
		"blocks_move": render.blocks_move,
		"blocks_los": render.blocks_los,
	}

func _roll_node_type(roll: int) -> String:
	"""Convert a weighted roll (0-94) into a node type string."""
	var cumulative = 0
	for node_type in NODE_WEIGHTS:
		cumulative += NODE_WEIGHTS[node_type]
		if roll < cumulative:
			return node_type
	return "stone"  # fallback

func _get_tier_for_distance(distance: float, x: int, y: int, seed: int) -> int:
	"""Get material tier based on distance from origin. Uses overlapping zones for gradual transition."""
	# Find which tiers are possible at this distance
	var possible_tiers = []
	for i in range(TIER_ZONES.size()):
		var zone = TIER_ZONES[i]
		if distance >= zone[0] and distance <= zone[1]:
			possible_tiers.append(i + 1)  # Tiers are 1-indexed

	if possible_tiers.is_empty():
		# Beyond all defined zones — max tier
		return 6

	if possible_tiers.size() == 1:
		return possible_tiers[0]

	# In overlap zone — randomly pick between the two tiers
	# Weight toward higher tier as distance increases within the overlap
	var lower_tier = possible_tiers[0]
	var upper_tier = possible_tiers[possible_tiers.size() - 1]
	var lower_zone = TIER_ZONES[lower_tier - 1]
	var upper_zone = TIER_ZONES[upper_tier - 1]

	# How far through the overlap are we?
	var overlap_start = upper_zone[0]  # where upper tier begins
	var overlap_end = lower_zone[1]    # where lower tier ends
	var t = 0.5
	if overlap_end > overlap_start:
		t = clampf((distance - overlap_start) / (overlap_end - overlap_start), 0.0, 1.0)

	var tier_roll = _seeded_hash_float(x * 41 + y * 83, seed + 2)
	if tier_roll < t:
		return upper_tier
	return lower_tier

func _is_water_tile_generated(x: int, y: int, seed: int) -> bool:
	"""Check if a tile should be water using noise-based clustering for natural lakes/rivers."""
	# Use two layers of noise for natural-looking water bodies
	# Layer 1: Large-scale water regions (low frequency)
	var water_noise = _water_noise(x, y, seed)
	if water_noise > 0.62:
		return true

	# Layer 2: Small scattered ponds (very rare)
	var pond_hash = _seeded_hash_float(x * 173 + y * 251, seed + 500)
	return pond_hash > 0.997  # ~0.3% random scatter

func _water_noise(x: int, y: int, seed: int) -> float:
	"""Simple value noise for water clustering. Returns 0.0-1.0."""
	# Use grid-based interpolated noise at low frequency
	var freq = 0.03  # Low frequency = large water bodies
	var fx = x * freq
	var fy = y * freq

	# Grid cell corners
	var ix = floori(fx)
	var iy = floori(fy)
	var frac_x = fx - ix
	var frac_y = fy - iy

	# Hash values at corners
	var v00 = _seeded_hash_float(ix * 127 + iy * 311, seed + 100)
	var v10 = _seeded_hash_float((ix + 1) * 127 + iy * 311, seed + 100)
	var v01 = _seeded_hash_float(ix * 127 + (iy + 1) * 311, seed + 100)
	var v11 = _seeded_hash_float((ix + 1) * 127 + (iy + 1) * 311, seed + 100)

	# Smoothstep interpolation
	var sx = frac_x * frac_x * (3.0 - 2.0 * frac_x)
	var sy = frac_y * frac_y * (3.0 - 2.0 * frac_y)

	var top = v00 + (v10 - v00) * sx
	var bottom = v01 + (v11 - v01) * sx
	return top + (bottom - top) * sy

func _seeded_hash_float(coord_hash: int, seed: int) -> float:
	"""Deterministic hash returning 0.0-1.0 from coordinate hash + seed."""
	var h = abs((coord_hash + seed) * 2654435761) % 1000000
	return h / 1000000.0

func _seeded_hash_int(coord_hash: int, seed: int) -> int:
	"""Deterministic hash returning a positive integer from coordinate hash + seed."""
	return abs((coord_hash + seed) * 2654435761) % 1000000

func get_terrain_at(x: int, y: int) -> Terrain:
	"""Determine terrain type at coordinates.
	When chunk_manager is available, uses the new tile system.
	Otherwise falls back to legacy procedural generation."""
	# New system: derive legacy Terrain enum from tile type
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		return _tile_to_terrain(tile, x, y)

	# Legacy fallback
	return _legacy_get_terrain_at(x, y)

func _tile_to_terrain(tile: Dictionary, x: int, y: int) -> Terrain:
	"""Convert new tile system type to legacy Terrain enum for backward compatibility."""
	var tile_type = tile.get("type", "empty")

	# NPC post tiles are safe zones
	if chunk_manager and chunk_manager.is_npc_post_tile(x, y):
		return Terrain.TRADING_POST

	# Also check legacy trading posts during transition
	if trading_post_db and trading_post_db.is_trading_post_tile(x, y):
		return Terrain.TRADING_POST

	match tile_type:
		"water": return Terrain.WATER
		"deep_water": return Terrain.DEEP_WATER
		"wall", "void": return Terrain.VOID
		"floor", "door", "forge", "apothecary", "workbench", "enchant_table", "writing_desk", "market", "inn", "quest_board", "post_marker", "throne":
			return Terrain.TRADING_POST  # Inside a post = safe
		"stone", "ore_vein":
			return Terrain.MOUNTAINS
		"tree", "dense_brush":
			return Terrain.FOREST
		"herb", "flower", "mushroom", "bush", "reed":
			return Terrain.PLAINS
		"empty", "path":
			# Use distance to flavor the terrain enum
			var distance = sqrt(float(x * x + y * y))
			if distance < 100:
				return Terrain.PLAINS
			elif distance < 400:
				return Terrain.FOREST
			elif distance < 800:
				return Terrain.DEEP_FOREST
			else:
				return Terrain.DESERT

	return Terrain.PLAINS

func _legacy_get_terrain_at(x: int, y: int) -> Terrain:
	"""Legacy terrain generation (pre-chunk system)."""
	var pos = Vector2i(x, y)

	if trading_post_db and trading_post_db.is_trading_post_tile(x, y):
		return Terrain.TRADING_POST

	if SPECIAL_LOCATIONS.has(pos):
		return SPECIAL_LOCATIONS[pos].terrain

	if _is_water_at(x, y):
		return Terrain.WATER
	if _is_deep_water_at(x, y):
		return Terrain.DEEP_WATER

	var distance_from_center = sqrt(x * x + y * y)

	if distance_from_center < 5:
		return Terrain.PLAINS
	elif distance_from_center < 50:
		var hash_val = abs(x * 11 + y * 17) % 100
		if hash_val < 15:
			return Terrain.FOREST
		elif hash_val < 25:
			return Terrain.MOUNTAINS
		else:
			return Terrain.PLAINS
	elif distance_from_center < 100:
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
		return Terrain.VOID

	return Terrain.PLAINS

func _is_water_at(x: int, y: int) -> bool:
	"""Check if coordinates should be shallow water (lakes and rivers)"""
	# Starter pond near origin (15 to 25, -15 to -5) - for early fishing
	if x >= 15 and x <= 25 and y >= -15 and y <= -5:
		return true
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

func get_fishing_tier(x: int, y: int) -> int:
	"""Get the fishing tier at coordinates (1-6 based on distance and water type)"""
	var terrain = get_terrain_at(x, y)
	var distance = sqrt(x * x + y * y)

	# Base tier from distance (similar to ore/wood tiers)
	var base_tier = 1
	if distance < 50:
		base_tier = 1
	elif distance < 100:
		base_tier = 2
	elif distance < 200:
		base_tier = 3
	elif distance < 350:
		base_tier = 4
	elif distance < 500:
		base_tier = 5
	else:
		base_tier = 6

	# Deep water adds +1 tier
	if terrain == Terrain.DEEP_WATER:
		base_tier = mini(base_tier + 1, 6)

	return base_tier

# ===== GATHERING SYSTEM (Mining & Logging) =====

# Starter gathering nodes near origin (within 25 tiles) - training areas for new players
const STARTER_GATHERING_RADIUS = 25
const STARTER_NODE_DENSITY = 15  # 1.5% chance for starter nodes (reduced from 4%)

func is_ore_deposit(x: int, y: int) -> bool:
	"""Check if coordinates are a mining location (ore/stone node)."""
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		return tile.get("type", "") in ["stone", "ore_vein"]
	# Legacy fallback
	return _legacy_is_ore_deposit(x, y)

func is_dense_forest(x: int, y: int) -> bool:
	"""Check if coordinates are a logging location (tree/dense brush node)."""
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		return tile.get("type", "") in ["tree", "dense_brush"]
	# Legacy fallback
	return _legacy_is_dense_forest(x, y)

func is_foraging_spot(x: int, y: int) -> bool:
	"""Check if coordinates are a foraging location (herb/flower/mushroom/bush/reed)."""
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		return tile.get("type", "") in ["herb", "flower", "mushroom", "bush", "reed"]
	return false

func get_ore_tier(x: int, y: int) -> int:
	"""Get the ore/stone tier at this location."""
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		return tile.get("tier", 1)
	# Legacy fallback
	var distance = sqrt(x * x + y * y)
	return clampi(int(distance / 50) + 1, 1, 9)

func get_wood_tier(x: int, y: int) -> int:
	"""Get the wood tier at this location."""
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		return tile.get("tier", 1)
	# Legacy fallback
	var distance = sqrt(x * x + y * y)
	return clampi(int(distance / 60) + 1, 1, 6)

func get_gathering_node_at(x: int, y: int) -> Dictionary:
	"""Unified gathering node detection. Returns {type, tier, job} or empty dict."""
	if chunk_manager:
		if chunk_manager.is_node_depleted(x, y):
			return {}
		var tile = chunk_manager.get_tile(x, y)
		var tile_type = tile.get("type", "")
		if tile_type in GATHERABLE_TYPES:
			return {
				"type": tile_type,
				"tier": tile.get("tier", 1),
				"job": NODE_TO_JOB.get(tile_type, ""),
			}
		return {}

	# Legacy fallback — check old gathering functions
	if is_fishing_spot(x, y):
		return {"type": "fishing", "tier": get_fishing_tier(x, y), "job": "fishing"}
	if _legacy_is_ore_deposit(x, y):
		return {"type": "mining", "tier": get_ore_tier(x, y), "job": "mining"}
	if _legacy_is_dense_forest(x, y):
		return {"type": "logging", "tier": get_wood_tier(x, y), "job": "logging"}
	return {}

func _legacy_is_ore_deposit(x: int, y: int) -> bool:
	"""Legacy ore deposit detection."""
	var terrain = _legacy_get_terrain_at(x, y)
	if terrain == Terrain.WATER or terrain == Terrain.DEEP_WATER:
		return false
	var distance = sqrt(x * x + y * y)
	if distance > 5 and distance <= STARTER_GATHERING_RADIUS:
		var info = get_terrain_info(terrain)
		if not info.safe:
			var ore_hash = abs(x * 47 + y * 83) % 1000
			if ore_hash < STARTER_NODE_DENSITY:
				return true
	if terrain != Terrain.MOUNTAINS:
		return false
	var ore_hash = abs(x * 47 + y * 83) % 1000
	return ore_hash < 10

func _legacy_is_dense_forest(x: int, y: int) -> bool:
	"""Legacy dense forest detection."""
	var terrain = _legacy_get_terrain_at(x, y)
	if terrain == Terrain.WATER or terrain == Terrain.DEEP_WATER:
		return false
	var distance = sqrt(x * x + y * y)
	if distance > 5 and distance <= STARTER_GATHERING_RADIUS:
		var info = get_terrain_info(terrain)
		if not info.safe:
			var wood_hash = abs(x * 67 + y * 97) % 1000
			if wood_hash < STARTER_NODE_DENSITY:
				return true
	if terrain != Terrain.FOREST and terrain != Terrain.DEEP_FOREST:
		return false
	var wood_hash = abs(x * 67 + y * 97) % 1000
	return wood_hash < 15

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
			elif is_ore_deposit(x, y):
				# Show ore deposit - brown/copper color
				line_parts.append("[color=#CD7F32] O[/color]")
			elif is_dense_forest(x, y):
				# Show dense forest/logging spot - dark green
				line_parts.append("[color=#228B22] T[/color]")
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

func generate_map_display(center_x: int, center_y: int, radius: int = 11, nearby_players: Array = [], dungeon_locations: Array = [], depleted_nodes: Array = [], corpse_locations: Array = [], bounty_locations: Array = []) -> String:
	"""Generate complete map display with location info header."""
	var output = ""

	# Check if at NPC post (new system)
	if chunk_manager and chunk_manager.is_npc_post_tile(center_x, center_y):
		var post = chunk_manager.get_npc_post_at(center_x, center_y)
		if not post.is_empty():
			output += "[color=#FFD700][b]%s[/b][/color] [color=#5F9EA0](%d, %d)[/color]\n" % [post.get("name", "Trading Post"), center_x, center_y]
			output += "[color=#00FF00]Safe[/color]\n"
			# Compass to nearest OTHER post
			output += _get_compass_line(center_x, center_y, post)
			output += "[center]"
			output += _generate_new_map(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations)
			output += "[/center]"
			return output

	# Check legacy Trading Post
	if trading_post_db and trading_post_db.is_trading_post_tile(center_x, center_y):
		var tp = trading_post_db.get_trading_post_at(center_x, center_y)
		output += "[color=#FFD700][b]%s[/b][/color] [color=#5F9EA0](%d, %d)[/color]\n" % [tp.get("name", "Trading Post"), center_x, center_y]
		output += "[color=#00FF00]Safe[/color] - [color=#87CEEB]%s[/color]\n" % tp.get("quest_giver", "Quest Giver")
		output += "[center]"
		if chunk_manager:
			output += _generate_new_map(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations)
		else:
			output += generate_ascii_map_with_merchants(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations)
		output += "[/center]"
		return output

	# Get location info
	var terrain = get_terrain_at(center_x, center_y)
	var info = get_terrain_info(terrain)
	var level_range = get_monster_level_range(center_x, center_y)

	# Location header - compact format with compass
	output += "[color=#5F9EA0](%d, %d)[/color] %s" % [center_x, center_y, info.name]

	# Merchant at current location
	if is_merchant_at(center_x, center_y):
		var merchant = get_merchant_at(center_x, center_y)
		output += " [color=#FFD700]$%s[/color]" % merchant.name

	output += "\n"

	# Danger info
	if not info.safe and level_range.min > 0:
		if level_range.is_hotspot:
			output += "[color=#FF0000]!DANGER![/color] "
		output += "[color=#FF4444]Lv%d-%d[/color]" % [level_range.min, level_range.max]
	else:
		output += "[color=#00FF00]Safe[/color]"

	# Compass to nearest NPC post
	if chunk_manager:
		output += _get_compass_line(center_x, center_y)

	output += "\n"

	# Add the map (centered)
	output += "[center]"
	if chunk_manager:
		output += _generate_new_map(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations)
	else:
		output += generate_ascii_map_with_merchants(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations)
	output += "[/center]"

	return output

func is_safe_zone(x: int, y: int) -> bool:
	"""Check if location is a safe zone (NPC post, trading post, structure interior)"""
	# New system: check NPC posts
	if chunk_manager and chunk_manager.is_npc_post_tile(x, y):
		return true
	# Check tile type for structure interiors
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		var tile_type = tile.get("type", "")
		if tile_type in ["floor", "forge", "apothecary", "workbench", "enchant_table", "writing_desk", "market", "inn", "quest_board", "storage", "tower", "post_marker"]:
			return true
		if tile.has("enclosure_owner"):
			return true
	# Legacy: check trading posts
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	return info.safe

func check_encounter(x: int, y: int) -> bool:
	"""Check if player encounters a monster (roll)"""
	if is_safe_zone(x, y):
		return false
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
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
	Returns the new position. If blocked by terrain, returns current position.
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

	# Check if tile blocks movement (new chunk system)
	if chunk_manager and direction != 5:
		var tile = chunk_manager.get_tile(new_x, new_y)
		if tile.get("blocks_move", false):
			# Depleted gathering nodes become passable
			var tile_type = tile.get("type", "")
			if tile_type in GATHERABLE_TYPES and chunk_manager.is_node_depleted(new_x, new_y):
				pass  # Allow movement through depleted node
			else:
				return Vector2i(current_x, current_y)  # Can't move there

	return Vector2i(new_x, new_y)

func get_direction_offset(x: int, y: int, direction: int) -> Vector2i:
	"""Get the target position for a direction (ignoring blocking)."""
	var dx = 0
	var dy = 0
	match direction:
		1: dx = -1; dy = -1
		2: dy = -1
		3: dx = 1; dy = -1
		4: dx = -1
		6: dx = 1
		7: dx = -1; dy = 1
		8: dy = 1
		9: dx = 1; dy = 1
	return Vector2i(x + dx, y + dy)

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

# ===== LINE OF SIGHT (BRESENHAM) =====

func is_tile_visible(player_x: int, player_y: int, target_x: int, target_y: int) -> bool:
	"""Check if target tile is visible from player using Bresenham LOS.
	A tile is visible if no intermediate tile blocks LOS.
	The target tile itself is visible even if it blocks LOS (you can see the wall)."""
	if not chunk_manager:
		return true  # No LOS without chunk system

	var points = bresenham_line(player_x, player_y, target_x, target_y)

	# Check intermediate points (skip player tile [0] and target tile [last])
	for i in range(1, points.size() - 1):
		var tile = chunk_manager.get_tile(points[i].x, points[i].y)
		if tile.get("blocks_los", false):
			# Depleted gathering nodes don't block LOS
			var tile_type = tile.get("type", "")
			if tile_type in GATHERABLE_TYPES and chunk_manager.is_node_depleted(points[i].x, points[i].y):
				continue
			return false

	return true

func bresenham_line(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	"""Standard Bresenham line algorithm. Returns all points on the line."""
	var points: Array[Vector2i] = []
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy

	var cx = x0
	var cy = y0
	while true:
		points.append(Vector2i(cx, cy))
		if cx == x1 and cy == y1:
			break
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy

	return points

# ===== NEW MAP RENDERER (Chunk-based with LOS) =====

func _generate_new_map(center_x: int, center_y: int, radius: int, nearby_players: Array = [], dungeon_locations: Array = [], depleted_nodes: Array = [], corpse_locations: Array = [], bounty_locations: Array = []) -> String:
	"""Generate ASCII map using chunk-based tile data with LOS raycasting."""
	var map_lines: PackedStringArray = PackedStringArray()

	# Build lookups
	var depleted_set = {}
	for coord_key in depleted_nodes:
		depleted_set[coord_key] = true

	var player_positions = {}
	for player in nearby_players:
		var key = "%d,%d" % [player.x, player.y]
		if not player_positions.has(key):
			player_positions[key] = []
		player_positions[key].append(player)

	var dungeon_positions = {}
	for dungeon in dungeon_locations:
		var key = "%d,%d" % [dungeon.x, dungeon.y]
		dungeon_positions[key] = dungeon

	var corpse_positions = {}
	for corpse in corpse_locations:
		var key = "%d,%d" % [corpse.get("x", -9999), corpse.get("y", -9999)]
		corpse_positions[key] = corpse

	var bounty_positions = {}
	for bounty in bounty_locations:
		var key = "%d,%d" % [bounty.get("x", -9999), bounty.get("y", -9999)]
		bounty_positions[key] = bounty

	# Pre-compute LOS for all tiles in vision radius
	var visible_tiles = {}
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var dist = sqrt(float(dx * dx + dy * dy))
			if dist > radius:
				continue
			var tx = center_x + dx
			var ty = center_y + dy
			var key = "%d,%d" % [tx, ty]
			visible_tiles[key] = is_tile_visible(center_x, center_y, tx, ty)

	# Render map
	for dy in range(radius, -radius - 1, -1):
		var line_parts: PackedStringArray = PackedStringArray()
		for dx in range(-radius, radius + 1):
			var x = center_x + dx
			var y = center_y + dy
			var dist = sqrt(float(dx * dx + dy * dy))

			# Outside vision radius
			if dist > radius:
				line_parts.append("  ")
				continue

			# Out of world bounds
			if x < WORLD_MIN_X or x > WORLD_MAX_X or y < WORLD_MIN_Y or y > WORLD_MAX_Y:
				line_parts.append("  ")
				continue

			var pos_key = "%d,%d" % [x, y]

			# Player position (always visible)
			if dx == 0 and dy == 0:
				line_parts.append("[color=#FFFF00] @[/color]")
				continue

			# LOS check — tiles outside line of sight are fully dark
			if not visible_tiles.get(pos_key, false):
				line_parts.append("  ")
				continue

			# Priority: players > dungeons > bounties > corpses > entities > terrain
			if player_positions.has(pos_key):
				var players_here = player_positions[pos_key]
				var first_player = players_here[0]
				var player_char = first_player.name[0].to_upper() if first_player.name.length() > 0 else "?"
				if players_here.size() > 1:
					player_char = "*"
				# Party members show in green, others in cyan
				var player_color = "#00FF00" if first_player.get("in_my_party", false) else "#00FFFF"
				line_parts.append("[color=%s] %s[/color]" % [player_color, player_char])
			elif dungeon_positions.has(pos_key):
				var dungeon = dungeon_positions[pos_key]
				var dungeon_color = dungeon.get("color", "#A335EE")
				line_parts.append("[color=%s] D[/color]" % dungeon_color)
			elif bounty_positions.has(pos_key):
				line_parts.append("[color=#FF4500] ![/color]")
			elif corpse_positions.has(pos_key):
				line_parts.append("[color=#FF0000] X[/color]")
			elif is_merchant_at(x, y):
				var merchant_color = _get_merchant_map_color(x, y)
				var merchant_char = _get_merchant_map_char(x, y)
				line_parts.append("[color=%s] %s[/color]" % [merchant_color, merchant_char])
			else:
				# Render tile from chunk data
				var tile = chunk_manager.get_tile(x, y)
				var tile_type = tile.get("type", "empty")
				var tile_tier = tile.get("tier", 1)
				var is_depleted = depleted_set.has(pos_key)

				if is_depleted and tile_type in GATHERABLE_TYPES:
					# Depleted node — show dim passable ground
					line_parts.append("[color=#444444] ,[/color]")
				else:
					line_parts.append(_render_tile_bbcode(tile_type, tile_tier))

		map_lines.append("".join(line_parts))

	return "\n".join(map_lines)

func _render_tile_bbcode(tile_type: String, tier: int = 1) -> String:
	"""Render a single tile as BBCode. 2 chars wide: space + character."""
	var render = TILE_RENDER.get(tile_type, TILE_RENDER["empty"])
	var char = render.char
	var color = render.color

	# Apply tier color shift for resources
	if TIER_COLORS.has(tile_type) and tier >= 1 and tier <= 6:
		color = TIER_COLORS[tile_type][tier - 1]

	# Flower color variety (deterministic from type name hash)
	if tile_type == "flower":
		var flower_colors = ["#FF69B4", "#FFD700", "#DA70D6", "#FF6347"]
		# Use a simple approach — vary by... well, flowers all look the same per tile
		# The tier can serve as color index
		color = flower_colors[(tier - 1) % flower_colors.size()]

	return "[color=%s] %s[/color]" % [color, char]

# ===== COMPASS / NAVIGATION =====

func _get_compass_line(player_x: int, player_y: int, exclude_post: Dictionary = {}) -> String:
	"""Get compass direction string pointing to nearest NPC post."""
	if not chunk_manager:
		return ""

	var nearest = chunk_manager.get_nearest_npc_post(player_x, player_y)
	if nearest.is_empty():
		return ""

	# Don't point to the post we're standing in
	if not exclude_post.is_empty():
		if nearest.get("x", -999) == exclude_post.get("x", -998) and nearest.get("y", -999) == exclude_post.get("y", -998):
			# Find second nearest
			var posts = chunk_manager.get_npc_posts()
			var best_dist = INF
			var second_nearest = {}
			for post in posts:
				if post.get("x", 0) == exclude_post.get("x", -1) and post.get("y", 0) == exclude_post.get("y", -1):
					continue
				var dx = post.get("x", 0) - player_x
				var dy = post.get("y", 0) - player_y
				var d = sqrt(dx * dx + dy * dy)
				if d < best_dist:
					best_dist = d
					second_nearest = post
			if second_nearest.is_empty():
				return ""
			nearest = second_nearest

	var dx = nearest.get("x", 0) - player_x
	var dy = nearest.get("y", 0) - player_y
	var dist = int(sqrt(dx * dx + dy * dy))

	if dist < 2:
		return ""  # Already at a post

	# Determine cardinal direction
	var angle = atan2(dy, dx)
	var direction = ""
	if angle > -PI/8 and angle <= PI/8:
		direction = "E"
	elif angle > PI/8 and angle <= 3*PI/8:
		direction = "NE"
	elif angle > 3*PI/8 and angle <= 5*PI/8:
		direction = "N"
	elif angle > 5*PI/8 and angle <= 7*PI/8:
		direction = "NW"
	elif angle > 7*PI/8 or angle <= -7*PI/8:
		direction = "W"
	elif angle > -7*PI/8 and angle <= -5*PI/8:
		direction = "SW"
	elif angle > -5*PI/8 and angle <= -3*PI/8:
		direction = "S"
	else:
		direction = "SE"

	return " [color=#C4A882]%s %s (%d)[/color]" % [direction, nearest.get("name", "Post"), dist]

# ===== PROCEDURAL TRAVELING MERCHANT SYSTEM =====
# Lightweight merchant system - positions calculated on-demand, not simulated
# Merchants travel between trading posts with deterministic positions based on time

# Total number of wandering merchants in the world
# Since positions are calculated on-demand (not simulated), more merchants has minimal server cost
const TOTAL_WANDERING_MERCHANTS = 0  # Disabled until market system is implemented

# Merchant type templates for variety
# Each type has a specialty that affects inventory and map color
const MERCHANT_TYPES = [
	# Weapons (Red on map)
	{"prefix": "Traveling", "suffix": "Weaponsmith", "specialty": "weapons", "services": ["buy", "sell"]},
	{"prefix": "Grizzled", "suffix": "Blademaster", "specialty": "weapons", "services": ["buy", "sell"]},
	# Armor (Blue on map)
	{"prefix": "Wandering", "suffix": "Armorer", "specialty": "armor", "services": ["buy", "sell"]},
	{"prefix": "Dwarven", "suffix": "Smithy", "specialty": "armor", "services": ["buy", "sell"]},
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
	{"prefix": "Old", "suffix": "Trader", "specialty": "all", "services": ["buy", "sell"]},
	{"prefix": "Swift", "suffix": "Peddler", "specialty": "all", "services": ["buy", "sell"]},
	{"prefix": "Master", "suffix": "Merchant", "specialty": "all", "services": ["buy", "sell", "gamble"]},
	# Elite (White on map) - Rare, sells everything with better odds
	{"prefix": "Legendary", "suffix": "Collector", "specialty": "elite", "services": ["buy", "sell", "gamble"]},
	# === AFFIX-FOCUSED MERCHANTS (sell equipment with guaranteed stat affixes) ===
	# Warrior gear (Orange on map) - STR, CON, Stamina, Attack affixes
	{"prefix": "Veteran", "suffix": "Outfitter", "specialty": "warrior_affixes", "services": ["buy", "sell"]},
	{"prefix": "Battle-worn", "suffix": "Supplier", "specialty": "warrior_affixes", "services": ["buy", "sell"]},
	# Mage gear (Light Blue on map) - INT, WIS, Mana affixes
	{"prefix": "Enchanted", "suffix": "Emporium", "specialty": "mage_affixes", "services": ["buy", "sell"]},
	{"prefix": "Arcane", "suffix": "Outfitter", "specialty": "mage_affixes", "services": ["buy", "sell"]},
	# Trickster gear (Lime on map) - DEX, WITS, Energy, Speed affixes
	{"prefix": "Shadowy", "suffix": "Fence", "specialty": "trickster_affixes", "services": ["buy", "sell"]},
	{"prefix": "Cunning", "suffix": "Dealer", "specialty": "trickster_affixes", "services": ["buy", "sell"]},
	# Tank gear (Gray on map) - HP, Defense, CON affixes
	{"prefix": "Ironclad", "suffix": "Supplier", "specialty": "tank_affixes", "services": ["buy", "sell"]},
	{"prefix": "Stalwart", "suffix": "Armorer", "specialty": "tank_affixes", "services": ["buy", "sell"]},
	# DPS gear (Yellow on map) - Attack, Speed, STR affixes
	{"prefix": "Keen", "suffix": "Bladedealer", "specialty": "dps_affixes", "services": ["buy", "sell"]},
	{"prefix": "Swift", "suffix": "Striker", "specialty": "dps_affixes", "services": ["buy", "sell"]},
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
		# Skip merchants in safe zones (NPC posts, trading posts)
		if is_safe_zone(pos.x, pos.y):
			continue
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

func generate_ascii_map_with_merchants(center_x: int, center_y: int, radius: int = 11, nearby_players: Array = [], dungeon_locations: Array = [], depleted_nodes: Array = [], corpse_locations: Array = [], bounty_locations: Array = []) -> String:
	"""Generate ASCII map with merchants, Trading Posts, dungeons, corpses, bounties, and other players shown.
	nearby_players is an array of {x, y, name, level} dictionaries for other players to display.
	dungeon_locations is an array of {x, y, color} dictionaries for dungeon entrances.
	depleted_nodes is an array of "x,y" strings for nodes that are currently depleted.
	corpse_locations is an array of {x, y, ...} dictionaries for corpses to display.
	bounty_locations is an array of {x, y} dictionaries for bounty targets to display."""
	var map_lines: PackedStringArray = PackedStringArray()

	# Build lookup for depleted nodes
	var depleted_set = {}
	for coord_key in depleted_nodes:
		depleted_set[coord_key] = true

	# Build a lookup for player positions (excluding self at center)
	var player_positions = {}
	for player in nearby_players:
		var key = "%d,%d" % [player.x, player.y]
		if not player_positions.has(key):
			player_positions[key] = []
		player_positions[key].append(player)

	# Build a lookup for dungeon positions
	var dungeon_positions = {}
	for dungeon in dungeon_locations:
		var key = "%d,%d" % [dungeon.x, dungeon.y]
		dungeon_positions[key] = dungeon

	# Build a lookup for corpse positions
	var corpse_positions = {}
	for corpse in corpse_locations:
		var key = "%d,%d" % [corpse.get("x", -9999), corpse.get("y", -9999)]
		corpse_positions[key] = corpse

	# Build a lookup for bounty positions
	var bounty_positions = {}
	for bounty in bounty_locations:
		var key = "%d,%d" % [bounty.get("x", -9999), bounty.get("y", -9999)]
		bounty_positions[key] = bounty

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
			elif dungeon_positions.has(pos_key):
				# Show dungeon entrance - use red if in danger area, otherwise dungeon's color
				var dungeon = dungeon_positions[pos_key]
				var dungeon_color = dungeon.get("color", "#A335EE")  # Default purple if no color
				if _is_hotspot(x, y):
					# Danger area + dungeon: show D with red background indicator
					line_parts.append("[color=#FF4500] D[/color]")
				else:
					line_parts.append("[color=%s] D[/color]" % dungeon_color)
			elif bounty_positions.has(pos_key):
				# Show bounty target as red-orange !
				line_parts.append("[color=#FF4500] ![/color]")
			elif corpse_positions.has(pos_key):
				# Show corpse as red X
				line_parts.append("[color=#FF0000] X[/color]")
			elif trading_post_db and trading_post_db.is_trading_post_tile(x, y):
				# Trading Post tiles - color-coded by category, shape chars rendered
				var tp_char = trading_post_db.get_tile_position_in_post(x, y)
				var post_id = trading_post_db.get_post_id_at(x, y)
				var colors = trading_post_db.get_post_map_colors(post_id)
				if tp_char == "P":
					# Center marker
					line_parts.append("[color=%s] P[/color]" % colors.center)
				elif tp_char == " " or tp_char == "":
					# Interior space
					line_parts.append("[color=%s] .[/color]" % colors.interior)
				elif tp_char == ".":
					# Interior dot
					line_parts.append("[color=%s] .[/color]" % colors.interior)
				else:
					# Edge/border characters - show actual shape char
					line_parts.append("[color=%s] %s[/color]" % [colors.edge, tp_char])
			elif is_merchant_at(x, y):
				# Show merchant with color based on specialty
				# Elite merchants get a special ★ symbol, others get $
				var merchant_color = _get_merchant_map_color(x, y)
				var merchant_char = _get_merchant_map_char(x, y)
				line_parts.append("[color=%s] %s[/color]" % [merchant_color, merchant_char])
			elif is_fishing_spot(x, y):
				# Check if this water is in a safe zone (can't fish in safe zones)
				var water_terrain_info = get_terrain_info(get_terrain_at(x, y))
				if water_terrain_info.safe:
					# Safe zone water - show as regular water (not fishable)
					line_parts.append("[color=#4169E1] ~[/color]")
				elif depleted_set.has(pos_key):
					# Depleted - show as dim water
					line_parts.append("[color=#4A6B8A] ~[/color]")
				else:
					# Active fishing spot - bright cyan
					line_parts.append("[color=#00FFFF] ~[/color]")
			elif is_ore_deposit(x, y):
				# Show ore deposit - check if depleted
				if depleted_set.has(pos_key):
					# Depleted - show as dim rock
					line_parts.append("[color=#5C4033] ^[/color]")
				else:
					# Active ore vein - bright gold
					line_parts.append("[color=#FFD700] *[/color]")
			elif is_dense_forest(x, y):
				# Show dense forest/logging spot - check if depleted
				if depleted_set.has(pos_key):
					# Depleted - show as dim forest
					line_parts.append("[color=#2E5A2E] &[/color]")
				else:
					# Active harvestable tree - bright green
					line_parts.append("[color=#32CD32] T[/color]")
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
	"""Check if tile is part of any Trading Post or NPC Post"""
	if chunk_manager:
		# New system: NPC posts replace legacy trading posts
		return chunk_manager.is_npc_post_tile(x, y)
	if trading_post_db:
		return trading_post_db.is_trading_post_tile(x, y)
	return false

func get_trading_post_at(x: int, y: int) -> Dictionary:
	"""Get Trading Post / NPC Post data if at one, empty dict otherwise.
	Always returns normalized dict with: id, name, center, description, quest_giver."""
	if chunk_manager:
		# New system: NPC posts replace legacy trading posts
		var post = chunk_manager.get_npc_post_at(x, y)
		if not post.is_empty():
			return _normalize_npc_post(post)
		return {}
	if trading_post_db:
		return trading_post_db.get_trading_post_at(x, y)
	return {}

func _normalize_npc_post(post: Dictionary) -> Dictionary:
	"""Ensure NPC post dict has all fields trading post handlers expect."""
	var result = post.duplicate()
	if not result.has("id"):
		result["id"] = "npc_" + result.get("name", "unknown").to_lower().replace(" ", "_")
	if not result.has("center"):
		result["center"] = {"x": result.get("x", 0), "y": result.get("y", 0)}
	if not result.has("description"):
		var cat = result.get("category", "default")
		var descriptions = {
			"haven": "A sheltered sanctuary for weary travelers.",
			"market": "A bustling marketplace with goods from across the land.",
			"shrine": "A place of quiet contemplation and healing.",
			"farm": "A rural settlement surrounded by cultivated fields.",
			"mine": "A rugged outpost built around rich mineral deposits.",
			"tower": "A fortified watchtower overlooking the badlands.",
			"camp": "A makeshift camp offering basic supplies.",
			"exotic": "A mysterious outpost trading in rare curiosities.",
			"fortress": "A heavily fortified stronghold.",
		}
		result["description"] = descriptions.get(cat, "A trading post in the wilderness.")
	return result

func is_trading_post_center(x: int, y: int) -> bool:
	"""Check if tile is the center of a Trading Post or NPC Post"""
	if chunk_manager:
		for post in chunk_manager.get_npc_posts():
			if post.get("x", -999) == x and post.get("y", -999) == y:
				return true
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
