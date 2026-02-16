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
	"blacksmith":    {"char": "B", "color": "#DAA520", "blocks_move": true, "blocks_los": false},
	"healer":        {"char": "H", "color": "#00FF88", "blocks_move": true, "blocks_los": false},
	"tower":         {"char": "^", "color": "#FFFFFF", "blocks_move": false, "blocks_los": false},
	"storage":       {"char": "C", "color": "#AAAAFF", "blocks_move": false, "blocks_los": false},
	"guard":         {"char": "G", "color": "#C0C0C0", "blocks_move": true, "blocks_los": false},
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
		"floor", "door", "forge", "apothecary", "workbench", "enchant_table", "writing_desk", "market", "inn", "quest_board", "post_marker", "throne", "blacksmith", "healer":
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

				# Check if this tile is a hotspot - show in red/orange (but not inside enclosures)
				if _is_hotspot(x, y) and not info.safe and not is_safe_zone(x, y):
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

	# Check if in a player enclosure — treat as safe zone
	var in_enclosure = false
	if chunk_manager:
		var center_tile = chunk_manager.get_tile(center_x, center_y)
		if center_tile.has("enclosure_owner"):
			in_enclosure = true

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

	# Danger info — enclosures are always safe
	if in_enclosure:
		output += "[color=#00FF00]Safe[/color]"
	elif not info.safe and level_range.min > 0:
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
		if tile_type in ["floor", "forge", "apothecary", "workbench", "enchant_table", "writing_desk", "market", "inn", "quest_board", "storage", "tower", "post_marker", "blacksmith", "healer", "guard"]:
			return true
		if tile.has("enclosure_owner"):
			return true
	# Legacy: check trading posts
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	return info.safe

# Guard position cache for encounter suppression
var _guard_positions: Array = []  # [{x, y, radius}]

func update_guard_positions(guards: Array):
	"""Update guard position cache from server data."""
	_guard_positions = guards

func is_guard_suppressed(x: int, y: int) -> bool:
	"""Check if a position is within any active guard's suppression radius (Manhattan distance)."""
	for gp in _guard_positions:
		var dist = abs(x - int(gp.x)) + abs(y - int(gp.y))
		if dist <= int(gp.radius):
			return true
	return false

func check_encounter(x: int, y: int) -> bool:
	"""Check if player encounters a monster (roll)"""
	if is_safe_zone(x, y):
		return false
	if is_guard_suppressed(x, y):
		return false
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	var rate = info.encounter_rate
	# Roads are safer — halve encounter rate on path tiles
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		if tile.get("type", "") == "path":
			rate *= 0.5
	return randf() < rate

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
				var in_hotzone = _is_hotspot(x, y) and not is_safe_zone(x, y)

				if is_depleted and tile_type in GATHERABLE_TYPES:
					if in_hotzone:
						# Depleted node in hotzone — show red ! instead of gray comma
						var intensity = _get_hotspot_intensity(x, y)
						var hz_color = "#FF0000" if intensity > 0.5 else "#FF4500"
						line_parts.append("[color=%s] ![/color]" % hz_color)
					else:
						# Depleted node — show dim passable ground
						line_parts.append("[color=#444444] ,[/color]")
				elif in_hotzone and (tile_type == "empty" or not TILE_RENDER.get(tile_type, {}).get("blocks_move", false)):
					# Passable tile in hotzone — show red ! with intensity gradient
					var intensity = _get_hotspot_intensity(x, y)
					var hz_color = "#FF0000" if intensity > 0.5 else "#FF4500"
					line_parts.append("[color=%s] ![/color]" % hz_color)
				elif in_hotzone:
					# Non-passable tile in hotzone — show tile with dark red tint
					line_parts.append("[color=#8B0000] ![/color]")
				elif tile_type == "guard":
					# Guard post — color based on active guard status
					line_parts.append(_render_guard_tile(x, y))
				elif tile_type == "tower":
					# Tower — gold if boosting a nearby guard
					line_parts.append(_render_tower_tile(x, y))
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

func _render_guard_tile(x: int, y: int) -> String:
	"""Render guard post tile with color based on active guard status."""
	# Check if an active guard is at this exact position
	for gp in _guard_positions:
		if int(gp.x) == x and int(gp.y) == y:
			# Active guard — color by implied food status
			# We don't have days_remaining on client, so active = green
			return "[color=#00FF00] G[/color]"
	# Empty guard post — gray
	return "[color=#555555] G[/color]"

func _render_tower_tile(x: int, y: int) -> String:
	"""Render tower tile — gold if boosting a nearby guard, white otherwise."""
	# Check if any active guard is within 2 tiles (tower boost range)
	for gp in _guard_positions:
		if abs(x - int(gp.x)) <= 2 and abs(y - int(gp.y)) <= 2:
			return "[color=#FFD700] ^[/color]"  # Gold — actively boosting
	return "[color=#FFFFFF] ^[/color]"  # White — normal

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

# ===== A* PATHFINDING & ROAD SYSTEM =====
# Computes roads between NPC posts, stamps path tiles, merchants follow roads.

const ASTAR_MAX_NODES = 50000  # Generous cap — the walkability check is strict, not the cap
const ASTAR_DIRECTIONS = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]  # N, S, W, E only

# Path graph: computed once on world init, updated when player posts are built
# Format: {post_key: [connected_post_keys]}
var _path_graph: Dictionary = {}
# Precomputed waypoints for each path segment: {"keyA->keyB": [Vector2i waypoints]}
var _path_waypoints: Dictionary = {}
# All post positions for pathfinding: {post_key: Vector2i}
var _path_post_positions: Dictionary = {}

func _is_walkable_for_path(x: int, y: int) -> bool:
	"""Check if a tile can be pathed through for road building.
	Roads ONLY form through player-cleared terrain. The wilderness must be tamed
	before roads can connect settlements. Walkable for road = depleted (harvested)
	gathering nodes, existing paths/floors, or NPC post tiles."""
	if not chunk_manager:
		return false
	# Depleted gathering nodes count as cleared (player harvested them)
	if chunk_manager.is_node_depleted(x, y):
		return true
	var tile = chunk_manager.get_tile(x, y)
	var tile_type = tile.get("type", "empty")
	# NPC post structure tiles are walkable (but NOT existing road "path" tiles —
	# roads must not create shortcuts for discovering other roads)
	if tile_type in ["floor", "door", "tower", "storage", "post_marker"]:
		return true
	# Modified empty tiles (explicitly set by chunk system, not procedurally generated)
	# Check if this tile has been modified from its procedural state
	if tile_type == "empty" and chunk_manager.is_tile_modified(x, y):
		return true
	return false

func _is_npc_post_interior(x: int, y: int) -> bool:
	"""Check if a tile is inside an NPC post (walls/stations/floor)."""
	if not chunk_manager:
		return false
	return chunk_manager.is_npc_post_tile(x, y)

func compute_path_between(start_x: int, start_y: int, end_x: int, end_y: int) -> Array:
	"""A* pathfinding from one point to another. Returns array of Vector2i waypoints.
	Uses 4-directional movement only for clean visual roads. Returns empty if no path."""
	var start = Vector2i(start_x, start_y)
	var goal = Vector2i(end_x, end_y)

	if start == goal:
		return [start]

	# Binary heap priority queue: array of [f_score, position]
	# Heap operations: push = append + bubble up, pop = swap root with last + sift down
	var heap: Array = [[absi(end_x - start_x) + absi(end_y - start_y), start]]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var closed_set: Dictionary = {}
	var nodes_explored = 0

	while heap.size() > 0 and nodes_explored < ASTAR_MAX_NODES:
		# Pop minimum from heap
		var current_entry = _heap_pop(heap)
		var current = current_entry[1]

		if current == goal:
			# Reconstruct path
			var path: Array = [current]
			while came_from.has(current):
				current = came_from[current]
				path.push_front(current)
			return path

		if closed_set.has(current):
			continue
		closed_set[current] = true
		nodes_explored += 1

		for dir in ASTAR_DIRECTIONS:
			var neighbor = current + dir
			if closed_set.has(neighbor):
				continue

			if not _is_walkable_for_path(neighbor.x, neighbor.y):
				if neighbor != goal:
					continue

			var tentative_g = g_score[current] + 1

			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				var h = absi(goal.x - neighbor.x) + absi(goal.y - neighbor.y)
				var f = tentative_g + h
				_heap_push(heap, [f, neighbor])

	return []  # No path found

func _heap_push(heap: Array, item: Array) -> void:
	"""Push item onto binary min-heap."""
	heap.append(item)
	var idx = heap.size() - 1
	while idx > 0:
		var parent = (idx - 1) / 2
		if heap[idx][0] < heap[parent][0]:
			var tmp = heap[parent]
			heap[parent] = heap[idx]
			heap[idx] = tmp
			idx = parent
		else:
			break

func _heap_pop(heap: Array) -> Array:
	"""Pop minimum item from binary min-heap."""
	if heap.size() == 1:
		return heap.pop_back()
	var result = heap[0]
	heap[0] = heap.pop_back()
	var idx = 0
	var size = heap.size()
	while true:
		var smallest = idx
		var left = 2 * idx + 1
		var right = 2 * idx + 2
		if left < size and heap[left][0] < heap[smallest][0]:
			smallest = left
		if right < size and heap[right][0] < heap[smallest][0]:
			smallest = right
		if smallest != idx:
			var tmp = heap[idx]
			heap[idx] = heap[smallest]
			heap[smallest] = tmp
			idx = smallest
		else:
			break
	return result

func initialize_post_graph(posts: Array) -> void:
	"""Initialize post positions and desired edges (MST + extra) without pathfinding.
	Actual path computation happens incrementally as terrain is cleared."""
	if posts.size() < 2:
		return

	# Build post position lookup
	_path_post_positions.clear()
	var post_list: Array = []
	for post in posts:
		var px = int(post.get("x", 0))
		var py = int(post.get("y", 0))
		var key = _get_post_key(post)
		_path_post_positions[key] = Vector2i(px, py)
		post_list.append({"key": key, "x": px, "y": py})

	# Compute all pairwise Euclidean distances
	var edges: Array = []
	for i in range(post_list.size()):
		for j in range(i + 1, post_list.size()):
			var dx = post_list[j].x - post_list[i].x
			var dy = post_list[j].y - post_list[i].y
			var dist = sqrt(dx * dx + dy * dy)
			edges.append({"from": post_list[i].key, "to": post_list[j].key, "dist": dist})
	edges.sort_custom(func(a, b): return a.dist < b.dist)

	# Kruskal's MST
	var parent: Dictionary = {}
	for p in post_list:
		parent[p.key] = p.key
	var mst_edges: Array = []
	var adjacency: Dictionary = {}
	for p in post_list:
		adjacency[p.key] = []

	for edge in edges:
		var root_a = _uf_find(parent, edge.from)
		var root_b = _uf_find(parent, edge.to)
		if root_a != root_b:
			parent[root_a] = root_b
			mst_edges.append(edge)
			adjacency[edge.from].append(edge.to)
			adjacency[edge.to].append(edge.from)
			if mst_edges.size() == post_list.size() - 1:
				break

	# Add extra short edges for redundancy
	var extra_edges: Array = []
	for edge in edges:
		if adjacency[edge.from].size() < 3 and adjacency[edge.to].size() < 3:
			if edge.to not in adjacency[edge.from]:
				extra_edges.append(edge)
				adjacency[edge.from].append(edge.to)
				adjacency[edge.to].append(edge.from)
				if extra_edges.size() >= post_list.size() / 2:
					break

	# Store desired edges (not yet connected by paths)
	_desired_edges = mst_edges + extra_edges

	# Initialize graph — no connections yet (paths haven't been found)
	_path_graph.clear()
	for p in post_list:
		_path_graph[p.key] = []

# Desired edges (MST + extra) that we want to connect via roads
var _desired_edges: Array = []

func try_connect_one_pair() -> Dictionary:
	"""Try A* on one unconnected desired edge. Returns {path_key: waypoints} if found, else empty.
	Called periodically by server. Cheap if no path exists yet (hits node cap quickly)."""
	for edge in _desired_edges:
		var path_key = _make_path_key(edge.from, edge.to)
		if _path_waypoints.has(path_key):
			continue  # Already connected

		var from_pos = _path_post_positions.get(edge.from, Vector2i(0, 0))
		var to_pos = _path_post_positions.get(edge.to, Vector2i(0, 0))
		var from_exit = _find_post_exit(from_pos.x, from_pos.y)
		var to_exit = _find_post_exit(to_pos.x, to_pos.y)

		var waypoints = compute_path_between(from_exit.x, from_exit.y, to_exit.x, to_exit.y)
		if waypoints.size() > 0:
			_path_waypoints[path_key] = waypoints
			if edge.to not in _path_graph.get(edge.from, []):
				if not _path_graph.has(edge.from):
					_path_graph[edge.from] = []
				_path_graph[edge.from].append(edge.to)
			if edge.from not in _path_graph.get(edge.to, []):
				if not _path_graph.has(edge.to):
					_path_graph[edge.to] = []
				_path_graph[edge.to].append(edge.from)
			return {path_key: waypoints}

	return {}  # All edges either connected or unreachable for now

func get_unconnected_edge_count() -> int:
	"""Count how many desired edges don't have paths yet."""
	var count = 0
	for edge in _desired_edges:
		var path_key = _make_path_key(edge.from, edge.to)
		if not _path_waypoints.has(path_key):
			count += 1
	return count

func _find_post_exit(center_x: int, center_y: int) -> Vector2i:
	"""Find a walkable tile just outside a post's walls, near a door."""
	if not chunk_manager:
		return Vector2i(center_x, center_y)

	# Search in expanding rings for a door tile, then go one step past it
	for radius in range(1, 12):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue  # Only check ring perimeter
				var tx = center_x + dx
				var ty = center_y + dy
				var tile = chunk_manager.get_tile(tx, ty)
				if tile.get("type", "") == "door":
					# Found a door — return the walkable tile just outside it
					for dir in ASTAR_DIRECTIONS:
						var outside = Vector2i(tx + dir.x, ty + dir.y)
						var outside_tile = chunk_manager.get_tile(outside.x, outside.y)
						if not outside_tile.get("blocks_move", false) and not _is_npc_post_interior(outside.x, outside.y):
							return outside
					# Door found but no walkable outside? Return door itself
					return Vector2i(tx, ty)

	# Fallback: return center (shouldn't happen with well-formed posts)
	return Vector2i(center_x, center_y)

func stamp_paths_into_chunks(paths: Dictionary) -> void:
	"""Write path tiles into chunks for each waypoint that isn't already a floor/door/post tile."""
	if not chunk_manager:
		return

	for path_key in paths:
		var waypoints = paths[path_key]
		for wp in waypoints:
			var x = wp.x if wp is Vector2i else int(wp.get("x", 0))
			var y = wp.y if wp is Vector2i else int(wp.get("y", 0))

			# Skip NPC post interior tiles
			if _is_npc_post_interior(x, y):
				continue

			# Skip tiles that are already non-blocking walkable types we don't want to overwrite
			var existing = chunk_manager.get_tile(x, y)
			var existing_type = existing.get("type", "empty")
			if existing_type in ["floor", "door", "forge", "apothecary", "workbench",
				"enchant_table", "writing_desk", "market", "inn", "quest_board",
				"tower", "storage", "post_marker", "blacksmith", "healer", "guard"]:
				continue

			# Stamp path tile
			chunk_manager.set_tile(x, y, {"type": "path", "blocks_move": false, "blocks_los": false})

func clear_path_tiles(waypoints: Array) -> void:
	"""Remove path tiles for a specific route (for rerouting)."""
	if not chunk_manager:
		return
	for wp in waypoints:
		var x = wp.x if wp is Vector2i else int(wp.get("x", 0))
		var y = wp.y if wp is Vector2i else int(wp.get("y", 0))
		var tile = chunk_manager.get_tile(x, y)
		if tile.get("type", "") == "path":
			chunk_manager.remove_tile_modification(x, y)

func connect_new_post(post: Dictionary) -> Dictionary:
	"""Connect a new post (player-built) to the nearest existing post.
	Returns the new path waypoints dict, or empty if no connection found."""
	var px = int(post.get("x", 0))
	var py = int(post.get("y", 0))
	var new_key = _get_post_key(post)
	_path_post_positions[new_key] = Vector2i(px, py)

	if not _path_graph.has(new_key):
		_path_graph[new_key] = []

	# Find nearest post within 200 tiles
	var nearest_key = ""
	var nearest_dist = 999999.0
	for key in _path_post_positions:
		if key == new_key:
			continue
		var pos = _path_post_positions[key]
		var dist = sqrt(pow(pos.x - px, 2) + pow(pos.y - py, 2))
		if dist < nearest_dist and dist <= 200:
			nearest_dist = dist
			nearest_key = key

	if nearest_key == "":
		return {}

	# Compute path
	var from_exit = _find_post_exit(px, py)
	var to_pos = _path_post_positions[nearest_key]
	var to_exit = _find_post_exit(to_pos.x, to_pos.y)
	var waypoints = compute_path_between(from_exit.x, from_exit.y, to_exit.x, to_exit.y)

	if waypoints.size() == 0:
		return {}

	var path_key = _make_path_key(new_key, nearest_key)
	_path_waypoints[path_key] = waypoints
	if nearest_key not in _path_graph[new_key]:
		_path_graph[new_key].append(nearest_key)
	if not _path_graph.has(nearest_key):
		_path_graph[nearest_key] = []
	if new_key not in _path_graph[nearest_key]:
		_path_graph[nearest_key].append(new_key)

	# Stamp the path tiles
	stamp_paths_into_chunks({path_key: waypoints})

	return {path_key: waypoints}

func get_post_connections() -> Dictionary:
	"""Returns the computed path graph: {post_key: [connected_post_keys]}"""
	return _path_graph

func _get_post_key(post: Dictionary) -> String:
	"""Generate a unique key for a post."""
	var post_id = post.get("id", "")
	if post_id != "":
		return post_id
	var name = post.get("name", "unknown")
	return "post_%s_%d_%d" % [name.to_lower().replace(" ", "_"), int(post.get("x", 0)), int(post.get("y", 0))]

func _make_path_key(key_a: String, key_b: String) -> String:
	"""Create a canonical path key from two post keys (alphabetical order)."""
	if key_a < key_b:
		return "%s->%s" % [key_a, key_b]
	return "%s->%s" % [key_b, key_a]

func _uf_find(parent: Dictionary, x: String) -> String:
	"""Union-find: find root with path compression."""
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

func get_path_waypoints_for_segment(from_key: String, to_key: String) -> Array:
	"""Get waypoints for a specific path segment. Returns them in the correct direction."""
	var path_key = _make_path_key(from_key, to_key)
	if not _path_waypoints.has(path_key):
		return []
	var waypoints = _path_waypoints[path_key]
	# If the canonical key has from_key first, return as-is; otherwise reverse
	if path_key.begins_with(from_key):
		return waypoints
	else:
		var reversed_path: Array = []
		for i in range(waypoints.size() - 1, -1, -1):
			reversed_path.append(waypoints[i])
		return reversed_path

# ===== PROCEDURAL TRAVELING MERCHANT SYSTEM =====
# Merchants follow stamped road tiles between connected NPC posts.
# Positions calculated on-demand based on time + precomputed waypoints.

const TOTAL_WANDERING_MERCHANTS = 10

# Merchant type templates
const MERCHANT_TYPES = [
	{"prefix": "Traveling", "suffix": "Weaponsmith", "specialty": "weapons", "services": ["buy", "sell"]},
	{"prefix": "Grizzled", "suffix": "Blademaster", "specialty": "weapons", "services": ["buy", "sell"]},
	{"prefix": "Wandering", "suffix": "Armorer", "specialty": "armor", "services": ["buy", "sell"]},
	{"prefix": "Dwarven", "suffix": "Smithy", "specialty": "armor", "services": ["buy", "sell"]},
	{"prefix": "Mysterious", "suffix": "Jeweler", "specialty": "jewelry", "services": ["buy", "sell", "gamble"]},
	{"prefix": "Exotic", "suffix": "Dealer", "specialty": "jewelry", "services": ["buy", "sell", "gamble"]},
	{"prefix": "Wandering", "suffix": "Alchemist", "specialty": "potions", "services": ["buy", "sell"]},
	{"prefix": "Hooded", "suffix": "Herbalist", "specialty": "potions", "services": ["buy", "sell"]},
	{"prefix": "Arcane", "suffix": "Scribe", "specialty": "scrolls", "services": ["buy", "sell"]},
	{"prefix": "Mystical", "suffix": "Sage", "specialty": "scrolls", "services": ["buy", "sell", "gamble"]},
	{"prefix": "Lucky", "suffix": "Gambler", "specialty": "all", "services": ["buy", "sell", "gamble"]},
	{"prefix": "Old", "suffix": "Trader", "specialty": "all", "services": ["buy", "sell"]},
	{"prefix": "Swift", "suffix": "Peddler", "specialty": "all", "services": ["buy", "sell"]},
	{"prefix": "Master", "suffix": "Merchant", "specialty": "all", "services": ["buy", "sell", "gamble"]},
	{"prefix": "Legendary", "suffix": "Collector", "specialty": "elite", "services": ["buy", "sell", "gamble"]},
	{"prefix": "Veteran", "suffix": "Outfitter", "specialty": "warrior_affixes", "services": ["buy", "sell"]},
	{"prefix": "Battle-worn", "suffix": "Supplier", "specialty": "warrior_affixes", "services": ["buy", "sell"]},
	{"prefix": "Enchanted", "suffix": "Emporium", "specialty": "mage_affixes", "services": ["buy", "sell"]},
	{"prefix": "Arcane", "suffix": "Outfitter", "specialty": "mage_affixes", "services": ["buy", "sell"]},
	{"prefix": "Shadowy", "suffix": "Fence", "specialty": "trickster_affixes", "services": ["buy", "sell"]},
	{"prefix": "Cunning", "suffix": "Dealer", "specialty": "trickster_affixes", "services": ["buy", "sell"]},
	{"prefix": "Ironclad", "suffix": "Supplier", "specialty": "tank_affixes", "services": ["buy", "sell"]},
	{"prefix": "Stalwart", "suffix": "Armorer", "specialty": "tank_affixes", "services": ["buy", "sell"]},
	{"prefix": "Keen", "suffix": "Bladedealer", "specialty": "dps_affixes", "services": ["buy", "sell"]},
	{"prefix": "Swift", "suffix": "Striker", "specialty": "dps_affixes", "services": ["buy", "sell"]},
]

const MERCHANT_FIRST_NAMES = ["Grim", "Kira", "Marcus", "Zara", "Lou", "Mira", "Tom", "Vex", "Rook", "Sage",
	"Finn", "Nora", "Brock", "Ivy", "Cole", "Luna", "Rex", "Faye", "Jax", "Wren"]

# Merchant travel parameters
const MERCHANT_SPEED = 0.02  # Tiles per second (1 tile every 50 seconds)
const MERCHANT_REST_TIME = 300.0  # 5 minutes rest at each trading post

# Cache for merchant positions (cleared periodically)
var _merchant_cache: Dictionary = {}
var _merchant_cache_time: float = 0.0
const MERCHANT_CACHE_DURATION = 30.0

# Precomputed merchant circuits: {merchant_idx: [post_key, post_key, ...]}
var _merchant_circuits: Dictionary = {}
# Precomputed merchant route waypoints: {merchant_idx: [[Vector2i segment1], [Vector2i segment2], ...]}
var _merchant_route_waypoints: Dictionary = {}
# Total waypoint counts per merchant for time-based position lookup
var _merchant_total_waypoints: Dictionary = {}

func _get_total_merchants() -> int:
	return TOTAL_WANDERING_MERCHANTS

func compute_merchant_circuits() -> void:
	"""Assign each merchant a circuit of 3-5 connected posts from the path graph.
	Deterministic based on merchant index."""
	_merchant_circuits.clear()
	_merchant_route_waypoints.clear()
	_merchant_total_waypoints.clear()

	var post_keys = _path_graph.keys()
	if post_keys.size() < 2:
		return

	for merchant_idx in range(TOTAL_WANDERING_MERCHANTS):
		# Pick a starting post deterministically
		var start_idx = (merchant_idx * 7 + 3) % post_keys.size()
		var circuit: Array = [post_keys[start_idx]]

		# Walk the graph to build a circuit of 3-5 posts
		var visited: Dictionary = {post_keys[start_idx]: true}
		var current_key = post_keys[start_idx]
		var circuit_len = 3 + (merchant_idx % 3)  # 3, 4, or 5 posts

		for _step in range(circuit_len - 1):
			var neighbors = _path_graph.get(current_key, [])
			if neighbors.size() == 0:
				break
			# Pick next unvisited neighbor deterministically
			var picked = ""
			var pick_seed = (merchant_idx * 13 + _step * 7) % maxi(1, neighbors.size())
			for attempt in range(neighbors.size()):
				var candidate = neighbors[(pick_seed + attempt) % neighbors.size()]
				if not visited.has(candidate):
					picked = candidate
					break
			if picked == "":
				# All neighbors visited, pick any neighbor to create a shorter circuit
				picked = neighbors[pick_seed % neighbors.size()]
			circuit.append(picked)
			visited[picked] = true
			current_key = picked

		_merchant_circuits[merchant_idx] = circuit

		# Precompute waypoints for each segment in the circuit
		var route_waypoints: Array = []
		var total_wp = 0
		for seg_idx in range(circuit.size()):
			var from_key = circuit[seg_idx]
			var to_key = circuit[(seg_idx + 1) % circuit.size()]
			var segment = get_path_waypoints_for_segment(from_key, to_key)
			if segment.size() == 0:
				# No path between these posts — use direct line as fallback
				var from_pos = _path_post_positions.get(from_key, Vector2i(0, 0))
				var to_pos = _path_post_positions.get(to_key, Vector2i(0, 0))
				segment = [from_pos, to_pos]
			route_waypoints.append(segment)
			total_wp += segment.size()

		_merchant_route_waypoints[merchant_idx] = route_waypoints
		_merchant_total_waypoints[merchant_idx] = total_wp

func _get_merchant_position(merchant_idx: int, current_time: float) -> Dictionary:
	"""Calculate merchant position by walking along precomputed waypoints.
	Returns {x, y, is_resting, at_post, segment_idx, destination_key}"""
	if not _merchant_circuits.has(merchant_idx):
		return {"x": 0, "y": 0, "is_resting": true, "at_post": "", "segment_idx": 0, "destination_key": ""}

	var circuit = _merchant_circuits[merchant_idx]
	var route_waypoints = _merchant_route_waypoints.get(merchant_idx, [])
	if circuit.size() < 2 or route_waypoints.size() == 0:
		var pos = _path_post_positions.get(circuit[0], Vector2i(0, 0))
		return {"x": pos.x, "y": pos.y, "is_resting": true, "at_post": circuit[0], "segment_idx": 0, "destination_key": ""}

	# Calculate total cycle time: for each segment, travel_time + rest_time
	var segment_times: Array = []
	var total_cycle_time = 0.0
	for seg in route_waypoints:
		var travel_time = float(seg.size()) / MERCHANT_SPEED if MERCHANT_SPEED > 0 else 300.0
		segment_times.append({"travel": travel_time, "rest": MERCHANT_REST_TIME})
		total_cycle_time += travel_time + MERCHANT_REST_TIME

	if total_cycle_time <= 0:
		var pos = _path_post_positions.get(circuit[0], Vector2i(0, 0))
		return {"x": pos.x, "y": pos.y, "is_resting": true, "at_post": circuit[0], "segment_idx": 0, "destination_key": ""}

	# Time offset for desynchronization
	var time_offset = float(merchant_idx * 137)
	var cycle_pos = fmod(current_time + time_offset, total_cycle_time)

	# Find which segment/phase we're in
	var elapsed = 0.0
	for seg_idx in range(segment_times.size()):
		var seg_travel = segment_times[seg_idx].travel
		var seg_rest = segment_times[seg_idx].rest

		# Rest phase at this post
		if cycle_pos < elapsed + seg_rest:
			var post_key = circuit[seg_idx]
			var pos = _path_post_positions.get(post_key, Vector2i(0, 0))
			return {"x": pos.x, "y": pos.y, "is_resting": true, "at_post": post_key, "segment_idx": seg_idx, "destination_key": circuit[(seg_idx + 1) % circuit.size()]}
		elapsed += seg_rest

		# Travel phase
		if cycle_pos < elapsed + seg_travel:
			var travel_progress = cycle_pos - elapsed
			var waypoints = route_waypoints[seg_idx]
			var wp_idx = int(travel_progress * MERCHANT_SPEED)
			wp_idx = clampi(wp_idx, 0, waypoints.size() - 1)
			var wp = waypoints[wp_idx]
			var dest_key = circuit[(seg_idx + 1) % circuit.size()]
			return {"x": wp.x, "y": wp.y, "is_resting": false, "at_post": "", "segment_idx": seg_idx, "destination_key": dest_key}
		elapsed += seg_travel

	# Fallback (shouldn't reach here due to fmod)
	var pos = _path_post_positions.get(circuit[0], Vector2i(0, 0))
	return {"x": pos.x, "y": pos.y, "is_resting": true, "at_post": circuit[0], "segment_idx": 0, "destination_key": ""}

# Inventory refresh interval (5 minutes)
const INVENTORY_REFRESH_INTERVAL = 300.0

func _is_elite_merchant(merchant_idx: int) -> bool:
	"""Check if a merchant index is one of the first 2 elite merchants."""
	return merchant_idx < 2

func _get_merchant_info(merchant_idx: int) -> Dictionary:
	"""Generate merchant info based on index (deterministic)"""
	var name_idx = merchant_idx % MERCHANT_FIRST_NAMES.size()

	var merchant_type: Dictionary
	if _is_elite_merchant(merchant_idx):
		for mt in MERCHANT_TYPES:
			if mt.specialty == "elite":
				merchant_type = mt
				break
	else:
		# Skip elite type at index 14
		var adjusted_idx = merchant_idx - 2  # 2 elite merchants
		var type_idx = adjusted_idx % (MERCHANT_TYPES.size() - 1)
		if type_idx >= 14:
			type_idx += 1
		merchant_type = MERCHANT_TYPES[type_idx]

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
		# Skip merchants resting inside NPC posts (they're "inside" — not visible on road)
		if pos.get("is_resting", false) and pos.get("at_post", "") != "":
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

	var merchant_idx = _merchant_cache[key][0]
	var info = _get_merchant_info(merchant_idx)
	var pos = _get_merchant_position(merchant_idx, Time.get_unix_time_from_system())

	# Get destination name from post positions
	var dest_key = pos.get("destination_key", "")
	var dest_name = ""
	if dest_key != "":
		# Look up post name from NPC posts
		if chunk_manager:
			for npc_post in chunk_manager.get_npc_posts():
				if _get_post_key(npc_post) == dest_key:
					dest_name = npc_post.get("name", "Unknown")
					break
		if dest_name == "":
			dest_name = dest_key  # Fallback to key

	return {
		"id": info.id,
		"name": info.name,
		"services": info.services,
		"specialty": info.specialty,
		"x": x,
		"y": y,
		"hash": info.inventory_seed,
		"is_wanderer": false,
		"destination": dest_name if not pos.is_resting else "",
		"destination_id": dest_key,
		"last_restock": Time.get_unix_time_from_system(),
		"is_resting": pos.is_resting,
		"at_post": pos.get("at_post", ""),
		"merchant_idx": merchant_idx,
		"road_merchant": not pos.is_resting
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

				if _is_hotspot(x, y) and not info.safe and not is_safe_zone(x, y):
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
