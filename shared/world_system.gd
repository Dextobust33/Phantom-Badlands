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
	"empty":         {"char": ".", "color": "#6B5B45", "blocks_move": false, "blocks_los": false},
	"stone":         {"char": "o", "color": "#998877", "blocks_move": true, "blocks_los": true},
	"tree":          {"char": "T", "color": "#228B22", "blocks_move": true, "blocks_los": true},
	"ore_vein":      {"char": "*", "color": "#8B6914", "blocks_move": true, "blocks_los": true},
	"herb":          {"char": "\"", "color": "#66CC66", "blocks_move": false, "blocks_los": false},
	"flower":        {"char": "'", "color": "#FF69B4", "blocks_move": false, "blocks_los": false},
	"mushroom":      {"char": ",", "color": "#9966CC", "blocks_move": false, "blocks_los": false},
	"bush":          {"char": ";", "color": "#006600", "blocks_move": false, "blocks_los": false},
	"reed":          {"char": "|", "color": "#66CCCC", "blocks_move": false, "blocks_los": false},
	"dense_brush":   {"char": "%", "color": "#6B8E23", "blocks_move": true, "blocks_los": false},
	# Slice 6e — biome-locked foraging nodes. Distinct chars + biome-themed
	# colors so they read at a glance on the map. Passable (blocks_move=false)
	# so the player can step onto them like other forage tiles. Each spawns
	# only in its matching biome via BIOME_NODE_WEIGHTS — they never appear
	# outside their biome. Drop tables on the existing Slice 6c biome-bonus
	# materials when foraged (no per-node tables yet — Slice 6f could add).
	"cactus":        {"char": "Y", "color": "#6B8E5A", "blocks_move": false, "blocks_los": false},
	"ice_bloom":     {"char": "i", "color": "#B0E0E6", "blocks_move": false, "blocks_los": false},
	"swamp_lily":    {"char": "&", "color": "#DA70D6", "blocks_move": false, "blocks_los": false},
	"mountain_herb": {"char": "j", "color": "#DAA520", "blocks_move": false, "blocks_los": false},
	"brambleberry":  {"char": "b", "color": "#8B3A3A", "blocks_move": false, "blocks_los": false},
	"water":         {"char": "~", "color": "#4488FF", "blocks_move": true, "blocks_los": false},
	"deep_water":    {"char": "~", "color": "#2244AA", "blocks_move": true, "blocks_los": false},
	"bridge":        {"char": "=", "color": "#C4A882", "blocks_move": false, "blocks_los": false},
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
	# Audit #4 Slice 1A — Companion Stable. Live access to Sanctuary kennel
	# mid-character. Appears at T5+ NPC posts; blocks_move so players bump-
	# interact (matching blacksmith/healer pattern). Magenta to read distinct
	# from the cargo-storage C glyph (#AAAAFF).
	"companion_stable": {"char": "C", "color": "#FF80FF", "blocks_move": true, "blocks_los": false},
	"tower":         {"char": "^", "color": "#FFFFFF", "blocks_move": false, "blocks_los": false},
	"storage":       {"char": "C", "color": "#AAAAFF", "blocks_move": false, "blocks_los": false},
	"guard":         {"char": "G", "color": "#C0C0C0", "blocks_move": true, "blocks_los": false},
	"post_marker":   {"char": "P", "color": "#FFD700", "blocks_move": false, "blocks_los": false},
	# Audit #12 Slice 6 (v0.9.505) — cosmetic player-buildable structures.
	# Banner: walkable; bump-interact shows owner + clan tag. Lamp post:
	# walkable; pure decoration with a warm-glow color.
	"banner":        {"char": "Y", "color": "#FFD700", "blocks_move": false, "blocks_los": false},
	"lamp_post":     {"char": "i", "color": "#FFFF99", "blocks_move": false, "blocks_los": false},
	"torch":         {"char": "t", "color": "#FF6600", "blocks_move": false, "blocks_los": false},
	"statue":        {"char": "M", "color": "#E0E0E0", "blocks_move": true,  "blocks_los": false},
	"signpost":      {"char": "r", "color": "#C4A882", "blocks_move": true,  "blocks_los": false},
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

# Audit #10 v0.9.512 — Apex frontier. The far edge of the world (1500+ tiles
# from origin) carries a +10% XP / +10% gold reward on monster kills as a
# nudge to push into the edges. First beat of "apex content"; future slices
# can stack on T9 encounter pools, unique drops, or named extreme zones.
const APEX_FRONTIER_DISTANCE = 1500

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
	# Slice 6e — biome-locked nodes all forage.
	"cactus": "foraging",
	"ice_bloom": "foraging",
	"swamp_lily": "foraging",
	"mountain_herb": "foraging",
	"brambleberry": "foraging",
}

# Types that can be gathered
const GATHERABLE_TYPES = ["stone", "ore_vein", "tree", "dense_brush", "herb", "flower", "mushroom", "bush", "reed", "water",
	# Slice 6e — biome-locked nodes feed the foraging pipeline.
	"cactus", "ice_bloom", "swamp_lily", "mountain_herb", "brambleberry"]

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

# Post-anchored world Slice 4 — typical distance from origin for each post tier,
# used to derive a tier→level mapping that stays consistent with the radial
# curve at every formal trading post. Player post settler bubbles use this to
# convert their effective tier into a monster level without needing their own
# distance-from-origin (which would defeat the point of bubble suppression).
const TIER_REFERENCE_DISTANCE = {
	1: 10,    # Core (haven cluster)
	2: 75,    # Inner (northwatch ring)
	3: 150,   # Mid (eastwatch / highland)
	4: 250,   # Mid-Outer (far_east_station)
	5: 350,   # Outer (storm_peak / shadowmere ring)
	6: 500,   # Extreme (eastern_terminus / primordial_sanctum)
	7: 700,   # World's Edge (world_spine_north)
}

# Slice 4 — player post settler bubble cache, pushed by server after every
# guard hire/feed/decay. Each entry: {x, y, radius, effective_tier}.
# get_post_anchored_level() checks this first; bubbles override the radial /
# trading-post anchor when (x, y) is inside one.
var player_post_bubbles: Array = []

# =============================================================================
# Slice 6a — Biome layer (post-anchored world, perpendicular axis to tier)
# =============================================================================
# Biomes are large-scale noise regions stamped on top of the existing tier
# layer. A T3 forest, a T6 forest, a T3 desert, a T6 desert all exist — biome
# is mechanically independent of tier and answers "what does the terrain look
# like here?" while tier answers "how dangerous are the things in it?".
#
# Generated via two perpendicular value-noise layers (temperature + humidity,
# Whittaker-style classification) at frequency 0.005 — each noise cell spans
# ~200 tiles so biome regions are large enough to feel like distinct places
# without being so vast that a normal travel session never crosses one.
#
# Slice 6a scope: biome enum + assignment function + per-biome node-weight
# shifts + empty-tile color tint + UI label. NO mechanical effects yet
# (movement penalty, weather, biome-locked monsters — those land in 6b+).

const BIOME_PLAINS  = "plains"
const BIOME_FOREST  = "forest"
const BIOME_MOUNTAIN = "mountain"
const BIOME_SWAMP   = "swamp"
const BIOME_SNOW    = "snow"
const BIOME_DESERT  = "desert"

const BIOME_NAMES = {
	BIOME_PLAINS:   "Plains",
	BIOME_FOREST:   "Forest",
	BIOME_MOUNTAIN: "Highlands",
	BIOME_SWAMP:    "Swamp",
	BIOME_SNOW:     "Tundra",
	BIOME_DESERT:   "Desert",
}

# Empty-tile color tint per biome — the dominant signal players read when
# scanning the map. Plains keeps the existing brown so the most common biome
# isn't visually loud; the others shift hue toward their theme.
const BIOME_EMPTY_COLORS = {
	BIOME_PLAINS:   "#6B5B45",  # current brown (unchanged baseline)
	BIOME_FOREST:   "#4F5B35",  # darker olive-brown
	BIOME_MOUNTAIN: "#665E55",  # gray-brown rock dust
	BIOME_SWAMP:    "#3F5A45",  # mossy green
	BIOME_SNOW:     "#C8D4DC",  # pale ice-blue
	BIOME_DESERT:   "#C4A468",  # warm tan
}

# Per-biome node weight overrides. Each biome rebalances the same node types
# rather than introducing new ones — keeps Slice 6a a pure distribution
# shift, no new tile rendering or gather behavior to wire up. Plains uses the
# baseline NODE_WEIGHTS.
const BIOME_NODE_WEIGHTS = {
	BIOME_FOREST: {
		"stone": 12,
		"tree": 40,
		"ore_vein": 5,
		"herb": 6,
		"flower": 4,
		"mushroom": 8,
		"bush": 6,
		"reed": 2,
		"dense_brush": 12,
		# Slice 6e — biome-locked node; only spawns here.
		"brambleberry": 8,
	},
	BIOME_MOUNTAIN: {
		"stone": 42,
		"tree": 12,
		"ore_vein": 22,
		"herb": 3,
		"flower": 2,
		"mushroom": 3,
		"bush": 3,
		"reed": 1,
		"dense_brush": 7,
		"mountain_herb": 6,
	},
	BIOME_SWAMP: {
		"stone": 8,
		"tree": 18,
		"ore_vein": 3,
		"herb": 8,
		"flower": 2,
		"mushroom": 18,
		"bush": 6,
		"reed": 22,
		"dense_brush": 10,
		"swamp_lily": 10,
	},
	BIOME_SNOW: {
		"stone": 38,
		"tree": 22,
		"ore_vein": 14,
		"herb": 4,
		"flower": 1,
		"mushroom": 4,
		"bush": 4,
		"reed": 2,
		"dense_brush": 6,
		"ice_bloom": 6,
	},
	BIOME_DESERT: {
		"stone": 48,
		"tree": 4,
		"ore_vein": 18,
		"herb": 3,
		"flower": 4,
		"mushroom": 1,
		"bush": 12,
		"reed": 2,
		"dense_brush": 8,
		"cactus": 12,
	},
}

# Slice 6d — starter-resource ring around NPC posts. Inside this radius (in
# tiles) of any NPC post centroid, generate_tile blends the biome's weight
# table back toward the baseline NODE_WEIGHTS so a new player who spawns at
# (say) a Desert NPC post can still find trees / herbs / mushrooms for
# starter materials. Outside the ring, biome distribution applies as
# before. Vision radius is 11 tiles, so 25 covers the screen + ~one more
# screen of walking around the post.
const NPC_STARTER_RING_RADIUS = 25
# Blend weight when inside the ring: 70% baseline, 30% biome. Keeps some
# biome flavor (a Desert post's surrounding tiles still lean toward cactus /
# sun_petal in the foraging table via Slice 6c) while ensuring every node
# type has real representation. Pure baseline would feel sterile and erase
# biome character; pure biome would leave Desert starters with no trees.
const NPC_STARTER_RING_BASELINE_WEIGHT = 0.7

# =============================================================================
# Slice 6h — Weather (per biome, server-driven cycle)
# =============================================================================
# Each biome has a small pool of possible weather states. Server cycles them
# every few minutes; the location message carries the player's current biome
# weather + display name + vision modifier. Effects layer on top of biome
# (a Tundra player gets Snow weather; a Plains player can't get Blizzard).
# Clear is the most common state across all biomes — weather should add
# variety, not constant noise.

const WEATHER_EFFECTS = {
	"clear":     {"display": "Clear",       "vision_mod": 0},
	"breeze":    {"display": "Breezy",      "vision_mod": 0},
	"wind":      {"display": "Strong Wind", "vision_mod": 0},
	"rain":      {"display": "Rain",        "vision_mod": -1},
	"mist":      {"display": "Mist",        "vision_mod": -2},
	"fog":       {"display": "Fog",         "vision_mod": -3},
	"snow":      {"display": "Snow",        "vision_mod": -1},
	"blizzard":  {"display": "Blizzard",    "vision_mod": -3},
	"haze":      {"display": "Heat Haze",   "vision_mod": -1},
	"sandstorm": {"display": "Sandstorm",   "vision_mod": -3},
}

# Per-biome weather pool. First entry is the "default" state used when the
# server first boots (before the first weather cycle runs). Weights are
# tuned in _pick_biome_weather to favor clear states so weather feels like
# punctuation rather than the steady state.
const BIOME_WEATHER_POOL = {
	BIOME_PLAINS:   ["clear", "breeze", "rain"],
	BIOME_FOREST:   ["clear", "breeze", "rain", "mist"],
	BIOME_MOUNTAIN: ["clear", "wind", "fog"],
	BIOME_SWAMP:    ["clear", "mist", "rain", "fog"],
	BIOME_SNOW:     ["clear", "snow", "blizzard"],
	BIOME_DESERT:   ["clear", "haze", "sandstorm"],
}

# Clear-state weight when rolling weather. Other states share the remaining
# (1.0 - CLEAR_WEIGHT) uniformly. Yields ~55% clear weather at any time, with
# the other 45% spread across the biome's 2-3 non-clear states.
const WEATHER_CLEAR_WEIGHT = 0.55

func get_weather_display(weather: String) -> String:
	var entry = WEATHER_EFFECTS.get(weather, {})
	return str(entry.get("display", weather.capitalize()))

func get_weather_vision_mod(weather: String) -> int:
	var entry = WEATHER_EFFECTS.get(weather, {})
	return int(entry.get("vision_mod", 0))

func pick_biome_weather(biome: String, rng_seed: int = 0) -> String:
	"""Roll a new weather state for `biome` from its pool. Clear gets
	WEATHER_CLEAR_WEIGHT; the remaining states share the rest uniformly.
	rng_seed lets the server pass a per-tick salt; if 0, randf() is used."""
	var pool = BIOME_WEATHER_POOL.get(biome, ["clear"])
	if pool.is_empty():
		return "clear"
	# Clear-vs-other roll
	var r1 = randf() if rng_seed == 0 else _seeded_hash_float(rng_seed, 9001)
	if r1 < WEATHER_CLEAR_WEIGHT or pool.size() == 1:
		return "clear"
	# Pick uniformly from the non-clear entries.
	var non_clear: Array = []
	for w in pool:
		if w != "clear":
			non_clear.append(w)
	if non_clear.is_empty():
		return "clear"
	var r2 = randf() if rng_seed == 0 else _seeded_hash_float(rng_seed + 1, 9001)
	var idx = int(r2 * float(non_clear.size())) % non_clear.size()
	return str(non_clear[idx])

func _is_in_npc_starter_ring(world_x: int, world_y: int) -> bool:
	"""True if (x, y) is within NPC_STARTER_RING_RADIUS of any NPC post
	centroid. Linear scan; npc_posts is ~18-100 entries which is cheap per
	tile (generate_tile is the per-tile hot path; it's already paying I/O
	and chunk-load costs that dwarf this lookup)."""
	if chunk_manager == null:
		return false
	var posts = chunk_manager.npc_posts if "npc_posts" in chunk_manager else []
	if posts.is_empty():
		return false
	var r2 = NPC_STARTER_RING_RADIUS * NPC_STARTER_RING_RADIUS
	for post in posts:
		var dx = int(post.get("x", 0)) - world_x
		var dy = int(post.get("y", 0)) - world_y
		if dx * dx + dy * dy <= r2:
			return true
	return false

func _blend_starter_ring_weights(biome_weights: Dictionary) -> Dictionary:
	"""Linear-interpolate between baseline NODE_WEIGHTS and the biome's
	weight table. Returns a dict the modulo roll can sum and use. Every
	node type gets at least weight 1 so a starter ring always has some
	chance of every gatherable type (Desert post still produces an
	occasional tree)."""
	var blended := {}
	var b = NPC_STARTER_RING_BASELINE_WEIGHT
	var ib = 1.0 - b
	for k in NODE_WEIGHTS:
		var baseline = float(NODE_WEIGHTS[k])
		var biome_val = float(biome_weights.get(k, 0))
		blended[k] = max(1, int(baseline * b + biome_val * ib))
	return blended

func get_biome_at(world_x: int, world_y: int, world_seed: int = 0) -> String:
	"""Return the biome string for a world tile. Whittaker-style assignment
	from two perpendicular noise layers: temperature (cold→hot) and humidity
	(dry→wet). Deterministic per (x, y, seed). Frequency 0.005 = ~200-tile
	biome cells. Plains is the central default; biome regions cluster around
	their climate niches and transition smoothly through plains."""
	var temp = _biome_temp_noise(world_x, world_y, world_seed)
	var humid = _biome_humid_noise(world_x, world_y, world_seed)

	# Cold regions are snow regardless of humidity — visually consistent and
	# matches the "Tundra is everywhere up north" mental model.
	if temp < 0.28:
		return BIOME_SNOW
	# Hot + dry = desert.
	if temp > 0.72 and humid < 0.40:
		return BIOME_DESERT
	# Hot + wet = swamp (humid jungle / mangrove read).
	if temp > 0.65 and humid > 0.62:
		return BIOME_SWAMP
	# Temperate wet = forest.
	if humid > 0.62:
		return BIOME_FOREST
	# Temperate dry = mountain / highlands.
	if humid < 0.30:
		return BIOME_MOUNTAIN
	# Everything in the middle band = plains (baseline biome).
	return BIOME_PLAINS

func get_biome_display_name(biome: String) -> String:
	return BIOME_NAMES.get(biome, "Wilderness")

func get_biome_empty_color(biome: String) -> String:
	return BIOME_EMPTY_COLORS.get(biome, "#6B5B45")

func _biome_temp_noise(x: int, y: int, world_seed: int) -> float:
	"""Low-frequency value noise for temperature gradient. Cold = 0, hot = 1.
	Uses a different hash multiplier than humidity so the two layers don't
	correlate — without that, biomes would smear into a 1D band."""
	return _biome_value_noise(x, y, world_seed + 7919, 0.005)

func _biome_humid_noise(x: int, y: int, world_seed: int) -> float:
	"""Low-frequency value noise for humidity. Dry = 0, wet = 1."""
	return _biome_value_noise(x, y, world_seed + 4001, 0.005)

func _biome_value_noise(x: int, y: int, world_seed: int, freq: float) -> float:
	"""Smoothstep-interpolated value noise. Same shape as _water_noise but
	parameterized so temperature + humidity share the math while staying
	independent via differing seed offsets."""
	var fx = x * freq
	var fy = y * freq
	var ix = floori(fx)
	var iy = floori(fy)
	var frac_x = fx - ix
	var frac_y = fy - iy
	var v00 = _seeded_hash_float(ix * 191 + iy * 419, world_seed)
	var v10 = _seeded_hash_float((ix + 1) * 191 + iy * 419, world_seed)
	var v01 = _seeded_hash_float(ix * 191 + (iy + 1) * 419, world_seed)
	var v11 = _seeded_hash_float((ix + 1) * 191 + (iy + 1) * 419, world_seed)
	var sx = frac_x * frac_x * (3.0 - 2.0 * frac_x)
	var sy = frac_y * frac_y * (3.0 - 2.0 * frac_y)
	var top = v00 + (v10 - v00) * sx
	var bottom = v01 + (v11 - v01) * sx
	return top + (bottom - top) * sy

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
	var density = 0.25 + 0.10 * clampf(distance / 2000.0, 0.0, 1.0)
	var density_roll = _seeded_hash_float(world_x * 7 + world_y * 13, seed)
	if density_roll >= density:
		return {"type": "empty", "tier": 0, "blocks_move": false, "blocks_los": false}

	# This tile is occupied — determine node type using the biome's weight
	# table (Slice 6a). Plains uses the baseline NODE_WEIGHTS; the other five
	# biomes shift distribution toward their theme (forest = tree-heavy,
	# mountain = stone/ore-heavy, etc.).
	var biome = get_biome_at(world_x, world_y, seed)
	var weights = BIOME_NODE_WEIGHTS.get(biome, NODE_WEIGHTS)
	# Slice 6d — starter ring around NPC posts blends biome weights back
	# toward baseline so a new player at a Desert / Tundra post can still
	# find every starter material within walking distance. Plains posts skip
	# the blend (biome weights == baseline already).
	if biome != BIOME_PLAINS and _is_in_npc_starter_ring(world_x, world_y):
		weights = _blend_starter_ring_weights(weights)
	var total_weight = _biome_total_weight(weights)
	if total_weight <= 0:
		total_weight = TOTAL_NODE_WEIGHT
		weights = NODE_WEIGHTS
	var type_roll = _seeded_hash_int(world_x * 31 + world_y * 53, seed + 1) % total_weight
	var node_type = _roll_node_type_weighted(type_roll, weights)

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
	"""Convert a weighted roll into a node type using baseline NODE_WEIGHTS."""
	return _roll_node_type_weighted(roll, NODE_WEIGHTS)

func _roll_node_type_weighted(roll: int, weights: Dictionary) -> String:
	"""Convert a weighted roll into a node type using the given weight table.
	Generic over biome variants — baseline NODE_WEIGHTS and any biome
	override in BIOME_NODE_WEIGHTS plug in here."""
	var cumulative = 0
	for node_type in weights:
		cumulative += int(weights[node_type])
		if roll < cumulative:
			return node_type
	return "stone"  # fallback

func _biome_total_weight(weights: Dictionary) -> int:
	"""Sum a biome's node weights so the modulo on the roll matches the
	table's actual coverage (biomes don't have to total 95 like baseline)."""
	var total = 0
	for k in weights:
		total += int(weights[k])
	return total

func _dim_color(hex_color: String, factor: float) -> String:
	"""Scale a #RRGGBB color toward black by factor (0..1). Used by the
	minimap so biome tints read as faint regions rather than competing with
	the bright glyphs (posts, dungeons) on the same surface."""
	if hex_color.length() != 7 or not hex_color.begins_with("#"):
		return hex_color
	var r = hex_color.substr(1, 2).hex_to_int()
	var g = hex_color.substr(3, 2).hex_to_int()
	var b = hex_color.substr(5, 2).hex_to_int()
	r = clampi(int(r * factor), 0, 255)
	g = clampi(int(g * factor), 0, 255)
	b = clampi(int(b * factor), 0, 255)
	return "#%02X%02X%02X" % [r, g, b]

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
	"""Check if coordinates are a foraging location. Includes the baseline
	herb/flower/mushroom/bush/reed nodes plus Slice 6e biome-locked nodes."""
	if chunk_manager:
		var tile = chunk_manager.get_tile(x, y)
		return tile.get("type", "") in ["herb", "flower", "mushroom", "bush", "reed",
			"cactus", "ice_bloom", "swamp_lily", "mountain_herb", "brambleberry"]
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

func generate_map_display(center_x: int, center_y: int, radius: int = 11, nearby_players: Array = [], dungeon_locations: Array = [], depleted_nodes: Array = [], corpse_locations: Array = [], bounty_locations: Array = [], explored_tiles: Dictionary = {}, threatened_post_centers: Array = [], current_post_threatened: bool = false) -> String:
	"""Generate complete map display with location info header.
	Slice 6j — explored_tiles dict (key: "x,y", value: true) is mutated in
	place: LOS-visible tiles are marked, and LOS-blocked tiles that were
	previously seen render as a dim fog version of the static terrain.
	Audit #11 Slice 8 — threatened_post_centers ("x,y" keys) overlay red
	warning glyphs on visible threatened post tiles; current_post_threatened
	flips the at-post 'Safe' header to 'Under Threat'."""
	var output = ""

	# Pre-compute lookup set for the inner renderer to avoid repeated linear
	# scans during the per-tile loop.
	var threatened_post_set: Dictionary = {}
	for ck in threatened_post_centers:
		threatened_post_set[String(ck)] = true

	# Check if at NPC post (new system)
	if chunk_manager and chunk_manager.is_npc_post_tile(center_x, center_y):
		var post = chunk_manager.get_npc_post_at(center_x, center_y)
		if not post.is_empty():
			# v0.9.350 — drop [b] so the post header uses the regular font
			# variant. The bold font has slightly different line metrics,
			# which shifted the map block ~2px lower when entering a post
			# vs the wilderness wrapper. Color alone distinguishes the name.
			output += "[color=#FFD700]%s[/color] [color=#5F9EA0](%d, %d)[/color]\n" % [post.get("name", "Trading Post"), center_x, center_y]
			# Audit #11 Slice 8 — header reflects threat state of this post.
			if current_post_threatened:
				output += "[color=#FF4400]Under Threat[/color]"
			else:
				output += "[color=#00FF00]Safe[/color]"
			# Compass to nearest OTHER post — appended inline with the Safe
			# marker (matches the wilderness path) so the header is 2 lines
			# total. Putting the compass on its own line previously made the
			# map block start a row lower than the client sprite overlay
			# expected (header_lines=2 in client.gd), drawing the player
			# figure one tile too high. Inline keeps both layouts consistent.
			output += _get_compass_line(center_x, center_y, post)
			output += "\n"
			output += "[center]"
			output += _generate_new_map(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations, explored_tiles, threatened_post_set)
			output += "[/center]"
			# Minimap — zoomed-out overview at small font, appended below the main map
			output += "\n" + _generate_minimap(center_x, center_y, dungeon_locations)
			return output

	# Check legacy Trading Post
	if trading_post_db and trading_post_db.is_trading_post_tile(center_x, center_y):
		var tp = trading_post_db.get_trading_post_at(center_x, center_y)
		# v0.9.350 — drop [b] for consistent map alignment (see NPC post path)
		output += "[color=#FFD700]%s[/color] [color=#5F9EA0](%d, %d)[/color]\n" % [tp.get("name", "Trading Post"), center_x, center_y]
		output += "[color=#00FF00]Safe[/color] - [color=#87CEEB]%s[/color]\n" % tp.get("quest_giver", "Quest Giver")
		output += "[center]"
		if chunk_manager:
			output += _generate_new_map(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations, explored_tiles, threatened_post_set)
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

	# Danger marker only — the precise level is shown in the Status HUD to avoid
	# duplicating the same info above and below the map.
	if in_enclosure:
		output += "[color=#00FF00]Safe[/color]"
	elif not info.safe and level_range.min > 0:
		if level_range.is_hotspot:
			output += "[color=#FF0000]!DANGER![/color]"
		else:
			output += "[color=#FF8800]Wilds[/color]"
	else:
		output += "[color=#00FF00]Safe[/color]"

	# Compass to nearest NPC post
	if chunk_manager:
		output += _get_compass_line(center_x, center_y)

	output += "\n"

	# Add the main map (centered)
	output += "[center]"
	if chunk_manager:
		output += _generate_new_map(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations, explored_tiles, threatened_post_set)
	else:
		output += generate_ascii_map_with_merchants(center_x, center_y, radius, nearby_players, dungeon_locations, depleted_nodes, corpse_locations, bounty_locations)
	output += "[/center]"

	# Minimap — zoomed-out overview at small font, appended below the main map
	output += "\n" + _generate_minimap(center_x, center_y, dungeon_locations)

	return output

func is_apex_frontier(x: int, y: int) -> bool:
	"""Audit #10 v0.9.512 — true when the coord is in the apex frontier zone
	(distance from origin > APEX_FRONTIER_DISTANCE). Used for visual marker
	in region label + +10% XP/gold combat reward bonus. First beat of apex
	content; future slices stack T9 encounter pools / unique drops / named
	extreme zones on top of this geometric definition."""
	var dist_sq = x * x + y * y
	return dist_sq > APEX_FRONTIER_DISTANCE * APEX_FRONTIER_DISTANCE

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
			"base_level": 0,
			"is_hotspot": false,
			"distance": sqrt(float(x * x + y * y))
		}

	# Calculate Euclidean distance from origin (0,0) — kept for hotspot info
	var distance = sqrt(float(x * x + y * y))

	# Post-anchored base level: trading posts anchor difficulty, with the
	# radial distance curve as a floor for wilderness/apex regions.
	var base_level = get_post_anchored_level(x, y)

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

func level_for_tier(tier: int) -> int:
	"""Convert a post tier (1-7) into the monster level it anchors at, using
	the radial _distance_to_level curve evaluated at each tier's reference
	distance. Used by player post settler bubbles in Slice 4 — their
	effective tier feeds into this to produce a level that matches the
	natural difficulty of trading posts at that tier."""
	var clamped = clamp(tier, 1, 7)
	return _distance_to_level(float(TIER_REFERENCE_DISTANCE.get(clamped, 10)))

func update_player_post_bubbles(bubbles: Array):
	"""Server pushes player post settler bubble cache here after every change
	(guard hire/feed/decay, post create/destroy). Each bubble:
	{x: int, y: int, radius: int, effective_tier: int}.
	Slice 4 of post-anchored world overhaul."""
	player_post_bubbles = bubbles

func _bubble_level_at(x: int, y: int) -> int:
	"""Returns the monster level from the closest covering player post settler
	bubble, or -1 if no bubble covers (x, y). The bubble's effective tier
	(already accounting for guard/tower suppression on the server) is mapped
	to a level via level_for_tier(). Returns -1 to signal 'no bubble' so the
	caller can fall back to the trading-post anchored level."""
	if player_post_bubbles.is_empty():
		return -1
	var nearest_dist = INF
	var nearest_tier = -1
	for bubble in player_post_bubbles:
		var bx = float(bubble.get("x", 0))
		var by = float(bubble.get("y", 0))
		var radius = float(bubble.get("radius", 25))
		var dx = float(x) - bx
		var dy = float(y) - by
		var d = sqrt(dx * dx + dy * dy)
		if d <= radius and d < nearest_dist:
			nearest_dist = d
			nearest_tier = int(bubble.get("effective_tier", 1))
	if nearest_tier < 0:
		return -1
	return level_for_tier(nearest_tier)

func get_post_anchored_level(x: int, y: int) -> int:
	"""Post-anchored monster level for (x, y).

	Player post settler bubbles take precedence (Slice 4) — when (x, y) is
	inside any bubble, the bubble's effective tier sets the level. Otherwise
	each formal trading post anchors the level at the radial-curve value of
	its own location, and positions between posts blend linearly between the
	two nearest anchors (Slice 2). The wilderness radial curve is the floor
	so apex zones beyond the post network keep their existing difficulty."""
	var bubble_level = _bubble_level_at(x, y)
	if bubble_level >= 0:
		return bubble_level
	var wilderness_level = _distance_to_level(sqrt(float(x * x + y * y)))
	# Slice 6L — anchor against procedurally-generated NPC posts so the level
	# model survives a map wipe. Falls through to the wilderness curve when
	# chunk_manager isn't ready or no posts exist (boot, dev test).
	if chunk_manager == null or chunk_manager.npc_posts.is_empty():
		return wilderness_level

	var nearest_dist = INF
	var nearest_post_origin_dist = 0.0
	var second_dist = INF
	var second_post_origin_dist = 0.0
	for post in chunk_manager.npc_posts:
		var cx = int(post.get("x", 0))
		var cy = int(post.get("y", 0))
		var dx = float(x - cx)
		var dy = float(y - cy)
		var d = sqrt(dx * dx + dy * dy)
		if d < nearest_dist:
			second_dist = nearest_dist
			second_post_origin_dist = nearest_post_origin_dist
			nearest_dist = d
			nearest_post_origin_dist = sqrt(float(cx * cx + cy * cy))
		elif d < second_dist:
			second_dist = d
			second_post_origin_dist = sqrt(float(cx * cx + cy * cy))

	if nearest_dist == INF:
		return wilderness_level

	var base_nearest = _distance_to_level(nearest_post_origin_dist)
	var post_blended: int
	if second_dist == INF:
		post_blended = base_nearest
	else:
		var base_second = _distance_to_level(second_post_origin_dist)
		var total = nearest_dist + second_dist
		if total < 0.001:
			post_blended = base_nearest
		else:
			# v0.9.480 — cubic blend (t^3) so each post DOMINATES its immediate
			# vicinity instead of linearly bleeding into neighbors. Was: linear
			# t = nearest/total — at d=30 from haven the blend already hit Lv 4
			# because the second-nearest post (forced 70+ tiles away by spacing
			# rules) anchors at Lv 10+. Cubic keeps the post's own anchor in
			# control through ~50% of the gap, then ramps sharply near the
			# other post. Result: haven Lv 1 stays Lv 1-2 in the buffer band,
			# and other posts get a cleaner "level pocket" too. Wilderness
			# floor still applies via max() below for apex zones.
			var t = nearest_dist / total
			var t_curved = t * t * t
			post_blended = int(round(lerp(float(base_nearest), float(base_second), t_curved)))

	return max(post_blended, wilderness_level)

func _distance_to_level(distance: float) -> int:
	"""Convert distance from origin to monster level (0-2828 -> 1-10000).
	   Expanded world with more gradual level progression.

	   v0.9.479 — stretched the early curve so the immediate area outside the
	   starter post is a Lv 1-2 buffer. Was: d=10-150 → lv 1-50 linear (put
	   Lv 4-7 within 25 tiles of haven). Now: 10-30 → 1-2 (first ring of
	   20 tiles), 30-60 → 2-6 (gentle next ring), 60-150 → 6-50 (catch up).
	   Endpoint at d=150 = lv 50 preserved so the rest of the world is
	   unaffected."""
	# Safe zone (distance 0-10): no monsters spawn here.
	if distance <= 10:
		return 1

	# Novice band (10-30): Lv 1-2 — first ring of 20 tiles around the
	# starter post. New characters get to fight Lv 1-2 monsters before
	# encountering anything tougher.
	if distance <= 30:
		var t = (distance - 10) / 20.0  # 0 to 1
		return int(1 + t * 1)  # 1 to 2

	# Easy band (30-60): Lv 2-6 — second ring, gentle ramp.
	if distance <= 60:
		var t = (distance - 30) / 30.0  # 0 to 1
		return int(2 + t * 4)  # 2 to 6

	# Distance 60-150: Levels 6-50 (catch up to old curve at the 150 anchor).
	if distance <= 150:
		var t = (distance - 60) / 90.0  # 0 to 1
		return int(6 + t * 44)

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
	"""Get hotspot info for a location. Returns {in_hotspot: bool, intensity: float}.
	Safe terrain (roads, trading posts, safe zones) suppresses hotspots so the map
	and the warning agree — both hide hotspot effects on safe tiles."""
	var terrain = get_terrain_at(x, y)
	var info = get_terrain_info(terrain)
	if info.safe or is_safe_zone(x, y):
		return {"in_hotspot": false, "intensity": 0.0}
	var in_hotspot = _is_hotspot(x, y)
	var intensity = 0.0
	if in_hotspot:
		intensity = _get_hotspot_intensity(x, y)
	return {"in_hotspot": in_hotspot, "intensity": intensity}

func _is_hotspot(x: int, y: int) -> bool:
	"""Check if coordinates are within a danger zone hot spot cluster.
	Single-query path — scans the 11x11 window around (x, y) for cluster
	centers. For bulk per-render lookups use [[_collect_hotspot_clusters]]
	+ [[_is_hotspot_in_clusters]] instead (one window scan total)."""
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

func _collect_hotspot_clusters(min_x: int, max_x: int, min_y: int, max_y: int) -> Array:
	"""v0.9.427 — collect every hotspot cluster center whose footprint can
	intersect the [min_x..max_x] x [min_y..max_y] box. Pad the search by 5
	(max cluster radius) so a center just outside the box but whose radius
	reaches in is still captured. Returns Array of {x, y, radius}.

	Used by the map renderer to replace ~500 per-tile 121-hash window scans
	with one window scan + per-tile array walks. With 0.3% cluster density
	and typical 33x33 padded vision (1089 cells), expect ~3 clusters per
	render."""
	var clusters: Array = []
	var pad: int = 5
	for cx in range(min_x - pad, max_x + pad + 1):
		for cy in range(min_y - pad, max_y + pad + 1):
			if _is_cluster_center(cx, cy):
				clusters.append({"x": cx, "y": cy, "radius": _get_cluster_radius(cx, cy)})
	return clusters

func _is_hotspot_in_clusters(x: int, y: int, clusters: Array) -> bool:
	"""v0.9.427 — fast per-tile hotspot check using a pre-collected cluster
	list (see [[_collect_hotspot_clusters]]). Typically iterates a handful
	of clusters instead of 121 hash checks."""
	for c in clusters:
		var dx = x - int(c.x)
		var dy = y - int(c.y)
		var r = float(c.radius)
		if dx * dx + dy * dy <= r * r:
			return true
	return false

func _get_hotspot_intensity_in_clusters(x: int, y: int, clusters: Array) -> float:
	"""v0.9.427 — fast per-tile intensity check using a pre-collected cluster
	list. Returns the highest intensity from any covering cluster (was: only
	the nearest cluster, but with the bounded array walk the highest wins)."""
	var best: float = 0.0
	for c in clusters:
		var dx = x - int(c.x)
		var dy = y - int(c.y)
		var r = float(c.radius)
		var dist_sq = float(dx * dx + dy * dy)
		if dist_sq <= r * r:
			var dist = sqrt(dist_sq)
			var intensity = clamp(1.0 - (dist / (r + 0.1)), 0.0, 1.0)
			if intensity > best:
				best = intensity
	return best

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

func _is_tile_visible_cached(player_x: int, player_y: int, target_x: int, target_y: int, blocks_los_cache: Dictionary) -> bool:
	"""v0.9.428 — fast LOS check using a pre-fetched blocks_los lookup.
	Intermediate Bresenham points read from the cache instead of calling
	chunk_manager.get_tile per step. Cache misses (intermediate point fell
	outside the pre-fetched bounding box) fall through to the safe path.

	Used by [[_generate_new_map]] to drop LOS time from 66-140ms to ~10-30ms
	on a typical r=11 render."""
	if not chunk_manager:
		return true
	var points = bresenham_line(player_x, player_y, target_x, target_y)
	# Skip the player tile (index 0) and the target tile (last) — same rule
	# as is_tile_visible: target is visible even if it blocks (you can see
	# the wall).
	for i in range(1, points.size() - 1):
		var pkey = "%d,%d" % [points[i].x, points[i].y]
		if blocks_los_cache.has(pkey):
			if blocks_los_cache[pkey]:
				return false
		else:
			# Cache miss — fall back to a single get_tile.
			var tile = chunk_manager.get_tile(points[i].x, points[i].y)
			if tile.get("blocks_los", false):
				var tile_type = tile.get("type", "")
				if tile_type in GATHERABLE_TYPES and chunk_manager.is_node_depleted(points[i].x, points[i].y):
					continue
				return false
	return true

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

func _generate_new_map(center_x: int, center_y: int, radius: int, nearby_players: Array = [], dungeon_locations: Array = [], depleted_nodes: Array = [], corpse_locations: Array = [], bounty_locations: Array = [], explored_tiles: Dictionary = {}, threatened_post_set: Dictionary = {}) -> String:
	"""Generate ASCII map using chunk-based tile data with LOS raycasting.
	Slice 6j — explored_tiles is mutated in place: any tile that resolves
	to LOS-visible inside the vision circle is added to the set, and any
	tile that is LOS-blocked but previously seen renders as fog instead
	of blank."""
	var map_lines: PackedStringArray = PackedStringArray()

	# v0.9.427 — pre-collect hotspot clusters for the entire vision area in a
	# single window scan. Replaces per-tile _is_hotspot() (121 hash checks
	# each, ~500 tiles per render = ~64K hash checks) with one scan + tiny
	# per-tile array walks. Typical render finds ~3 clusters in the padded box.
	var _diag_setup_start: int = Time.get_ticks_usec()
	var _hotspot_clusters: Array = _collect_hotspot_clusters(
		center_x - radius, center_x + radius,
		center_y - radius, center_y + radius
	)

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

	# v0.9.428 — pre-fetch tile data for every tile in the vision bounding box
	# in one pass. Stores the full tile dict (not just blocks_los) so the
	# per-tile render loop can read from the same cache instead of calling
	# chunk_manager.get_tile again. Each get_tile call on an unmodified tile
	# runs the full procedural-noise pipeline, so re-fetching the same tile
	# is expensive. v0.9.429 diag: setup=50-62ms, render=34-42ms — render
	# was paying generate_tile cost a SECOND time. With shared cache, render
	# loop reads dict.
	var tile_cache: Dictionary = {}
	var blocks_los_cache: Dictionary = {}
	if chunk_manager:
		for dy_pf in range(-radius, radius + 1):
			for dx_pf in range(-radius, radius + 1):
				var pf_x = center_x + dx_pf
				var pf_y = center_y + dy_pf
				var pf_tile = chunk_manager.get_tile(pf_x, pf_y)
				var pf_key = "%d,%d" % [pf_x, pf_y]
				tile_cache[pf_key] = pf_tile
				var blocks = bool(pf_tile.get("blocks_los", false))
				# Depleted gathering nodes don't block LOS (matches is_tile_visible).
				if blocks and String(pf_tile.get("type", "")) in GATHERABLE_TYPES:
					if depleted_set.has(pf_key):
						blocks = false
				blocks_los_cache[pf_key] = blocks
	var _diag_setup_us: int = Time.get_ticks_usec() - _diag_setup_start

	# Pre-compute LOS for all tiles in vision radius — now reads from the
	# cached blocks_los map instead of re-fetching every tile per Bresenham
	# walk.
	var _diag_los_start: int = Time.get_ticks_usec()
	var visible_tiles = {}
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var dist = sqrt(float(dx * dx + dy * dy))
			if dist > radius:
				continue
			var tx = center_x + dx
			var ty = center_y + dy
			var key = "%d,%d" % [tx, ty]
			var visible = _is_tile_visible_cached(center_x, center_y, tx, ty, blocks_los_cache)
			visible_tiles[key] = visible
			# Slice 6j — record any tile seen in LOS as explored. Blockers
			# themselves count as visible (you can see the mountain face that
			# stops your sight) so they get remembered too.
			if visible:
				explored_tiles[key] = true
	var _diag_los_us: int = Time.get_ticks_usec() - _diag_los_start

	# Render map
	var _diag_render_start: int = Time.get_ticks_usec()
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

			# LOS check — tiles outside line of sight are blank, unless the
			# character has explored them before, in which case render a dim
			# fog version (Slice 6j map memory).
			if not visible_tiles.get(pos_key, false):
				if explored_tiles.has(pos_key):
					line_parts.append(_render_fog_tile(x, y))
				else:
					line_parts.append("  ")
				continue

			# Audit #11 Slice 8 — overlay red warning glyph on threatened post
			# centers. Sits above terrain but below transient overlays so
			# players / dungeons / corpses / bounties still read normally; only
			# unoccupied post tiles flip to the warning indicator.
			if threatened_post_set.has(pos_key) and not (player_positions.has(pos_key) or dungeon_positions.has(pos_key) or corpse_positions.has(pos_key) or bounty_positions.has(pos_key)):
				line_parts.append("[color=#FF4400] ![/color]")
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
				# Render tile from chunk data — v0.9.430 uses the per-render
				# cache populated in setup. Skips the procedural-noise pipeline
				# that chunk_manager.get_tile runs for unmodified tiles. Cache
				# miss only happens if the tile fell outside the bounding box
				# (shouldn't, since we iterate the same box).
				var tile = tile_cache.get(pos_key, null)
				if tile == null:
					tile = chunk_manager.get_tile(x, y)
				var tile_type = tile.get("type", "empty")
				var tile_tier = tile.get("tier", 1)
				var is_depleted = depleted_set.has(pos_key)
				# v0.9.427 — use pre-collected cluster array instead of the
				# per-tile 121-hash _is_hotspot scan. Same is_safe_zone gate.
				var in_hotzone = _is_hotspot_in_clusters(x, y, _hotspot_clusters) and not is_safe_zone(x, y)

				if is_depleted and tile_type in GATHERABLE_TYPES:
					if in_hotzone:
						# Depleted node in hotzone — show red ! instead of gray comma
						var intensity = _get_hotspot_intensity_in_clusters(x, y, _hotspot_clusters)
						var hz_color = "#FF0000" if intensity > 0.5 else "#FF4500"
						line_parts.append("[color=%s] ![/color]" % hz_color)
					else:
						# Depleted node — show dim passable ground
						line_parts.append("[color=#444444] ,[/color]")
				elif in_hotzone and (tile_type == "empty" or not TILE_RENDER.get(tile_type, {}).get("blocks_move", false)):
					# Passable tile in hotzone — show red ! with intensity gradient
					var intensity = _get_hotspot_intensity_in_clusters(x, y, _hotspot_clusters)
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
					line_parts.append(_render_tile_bbcode(tile_type, tile_tier, x, y))

		map_lines.append("".join(line_parts))
	var _diag_render_us: int = Time.get_ticks_usec() - _diag_render_start
	var _diag_join_start: int = Time.get_ticks_usec()
	var _joined: String = "\n".join(map_lines)
	var _diag_join_us: int = Time.get_ticks_usec() - _diag_join_start
	# v0.9.428 — fine-grained map-render timing. Emit if total ≥ 80ms so we can
	# see whether the cost is setup, LOS pre-compute, the per-tile render
	# loop, or the final string join. Spike threshold is 80ms = the bottom of
	# the 200-240ms move spikes we're chasing.
	var _diag_total_us: int = _diag_setup_us + _diag_los_us + _diag_render_us + _diag_join_us
	if _diag_total_us >= 80000:
		print("[MAPRENDER] total=%.1fms setup=%.1fms los=%.1fms render=%.1fms join=%.1fms (r=%d, visible=%d)" % [
			_diag_total_us / 1000.0,
			_diag_setup_us / 1000.0,
			_diag_los_us / 1000.0,
			_diag_render_us / 1000.0,
			_diag_join_us / 1000.0,
			radius,
			visible_tiles.size(),
		])
	return _joined

func _render_tile_bbcode(tile_type: String, tier: int = 1, world_x: int = 0, world_y: int = 0) -> String:
	"""Render a single tile as BBCode. 2 chars wide: space + character.
	Slice 6a — empty tiles pick up their biome's tint so map regions read at
	a glance. world_x/world_y default to (0, 0) which always plains, preserving
	legacy callers."""
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

	# Biome tint for empty / path tiles — the dominant signal players read
	# when scanning the map. Plains keeps the baseline brown unchanged.
	if tile_type == "empty" or tile_type == "path":
		var biome_seed = chunk_manager.world_seed if chunk_manager and "world_seed" in chunk_manager else 0
		var biome = get_biome_at(world_x, world_y, biome_seed)
		color = get_biome_empty_color(biome)

	return "[color=%s] %s[/color]" % [color, char]

func _render_fog_tile(x: int, y: int) -> String:
	"""Slice 6j — render the static terrain at (x, y) as a dim 'fog of war'
	tile. Used for positions outside current LOS that the character has
	explored before. Strips all transient overlays (players, dungeons,
	corpses, bounties, depletion, hotzone tint) — those are dynamic and
	would be stale, so memory only preserves the immobile terrain shape."""
	if chunk_manager == null:
		return "  "
	var tile = chunk_manager.get_tile(x, y)
	var tile_type = tile.get("type", "empty")
	var tile_tier = int(tile.get("tier", 1))
	var render = TILE_RENDER.get(tile_type, TILE_RENDER["empty"])
	var char = render.char
	var color = render.color
	if TIER_COLORS.has(tile_type) and tile_tier >= 1 and tile_tier <= 6:
		color = TIER_COLORS[tile_type][tile_tier - 1]
	if tile_type == "empty" or tile_type == "path":
		var biome_seed = chunk_manager.world_seed if "world_seed" in chunk_manager else 0
		var biome = get_biome_at(x, y, biome_seed)
		color = get_biome_empty_color(biome)
	return "[color=%s] %s[/color]" % [_dim_color(color, 0.35), char]

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

const ASTAR_MAX_NODES = 100000  # Increased to handle longer permissive-mode paths
# Maximum allowed path length as a multiple of the Manhattan distance between endpoints.
# Paths that require a longer detour than this are considered blocked and won't auto-form.
const PATH_MAX_DEVIATION_RATIO = 1.5
const ASTAR_DIRECTIONS = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]  # N, S, W, E only

# Path graph: computed once on world init, updated when player posts are built
# Format: {post_key: [connected_post_keys]}
var _path_graph: Dictionary = {}
# Precomputed waypoints for each path segment: {"keyA->keyB": [Vector2i waypoints]}
var _path_waypoints: Dictionary = {}
# All post positions for pathfinding: {post_key: Vector2i}
var _path_post_positions: Dictionary = {}

func _is_walkable_for_path(x: int, y: int, permissive: bool = false) -> bool:
	"""Check if a tile can be pathed through for road building.
	Strict mode (NPC-to-NPC): only depleted nodes, structure tiles, modified empty.
	Permissive mode (player posts): any non-blocking tile is walkable."""
	if not chunk_manager:
		return false
	# Depleted gathering nodes count as cleared (player harvested them)
	if chunk_manager.is_node_depleted(x, y):
		return true
	var tile = chunk_manager.get_tile(x, y)
	var tile_type = tile.get("type", "empty")
	# NPC post structure tiles, player structure tiles, and bridges are walkable
	if tile_type in ["floor", "door", "tower", "storage", "post_marker", "bridge"]:
		return true
	# Modified empty tiles (explicitly set by chunk system, not procedurally generated)
	if tile_type == "empty" and chunk_manager.is_tile_modified(x, y):
		return true
	# Permissive mode: any non-blocking tile is walkable (for player post connections)
	if permissive and not tile.get("blocks_move", false):
		return true
	return false

func _is_npc_post_interior(x: int, y: int) -> bool:
	"""Check if a tile is inside an NPC post (walls/stations/floor)."""
	if not chunk_manager:
		return false
	return chunk_manager.is_npc_post_tile(x, y)

func compute_path_between(start_x: int, start_y: int, end_x: int, end_y: int, permissive: bool = false, time_budget_ms: int = 0) -> Array:
	"""A* pathfinding from one point to another. Returns array of Vector2i waypoints.
	Uses 4-directional movement only for clean visual roads. Returns empty if no path.
	Permissive mode allows any non-blocking tile (used for player post connections).

	v0.9.379 — optional wall-clock time_budget_ms. Default 0 = unbounded (legacy
	behavior; safe for short paths and tests). Background road A* (long permissive
	paths over loaded chunks) was producing 4.8s frame spikes on Hetzner — pass a
	~150ms budget there so a single _process tick stays bounded. Returns empty
	if budget elapses; caller can retry next tick."""
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

	# Time-budget check is amortized: only Time.get_ticks_usec() once every
	# ~256 expansions (cheap enough at 150ms granularity, expensive otherwise).
	var start_us: int = Time.get_ticks_usec() if time_budget_ms > 0 else 0
	var budget_us: int = time_budget_ms * 1000

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

		# Time-budget bail-out (only when caller passed a budget).
		if budget_us > 0 and (nodes_explored & 0xFF) == 0:
			if Time.get_ticks_usec() - start_us >= budget_us:
				return []

		for dir in ASTAR_DIRECTIONS:
			var neighbor = current + dir
			if closed_set.has(neighbor):
				continue

			if not _is_walkable_for_path(neighbor.x, neighbor.y, permissive):
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
	Called periodically by server. Cheap if no path exists yet (hits node cap quickly).
	v0.9.379 — total wall-clock cap (200ms) so multiple edges timing out in
	the same call can't stack into a frame freeze. Per-pair budget is 150ms;
	outer cap is 200ms (allows at most ~one full per-pair timeout plus a
	quick-fail attempt or two). Next 5-min tick picks up where we left off."""
	var outer_start_us: int = Time.get_ticks_usec()
	var outer_budget_us: int = 200 * 1000
	for edge in _desired_edges:
		var path_key = _make_path_key(edge.from, edge.to)
		if _path_waypoints.has(path_key):
			continue  # Already connected

		# Bail out of the outer loop if we've already burned the total budget
		# (e.g., a previous edge in this call timed out).
		if Time.get_ticks_usec() - outer_start_us >= outer_budget_us:
			return {}

		var from_pos = _path_post_positions.get(edge.from, Vector2i(0, 0))
		var to_pos = _path_post_positions.get(edge.to, Vector2i(0, 0))
		var from_exit = _find_post_exit(from_pos.x, from_pos.y)
		var to_exit = _find_post_exit(to_pos.x, to_pos.y)

		# Use permissive mode so roads auto-connect through any non-blocking terrain.
		# Water still blocks (blocks_move = true), so bridges are needed for water crossings.
		# Per-pair budget = remaining of the outer budget (so we never blow past 200ms total).
		var elapsed_us: int = Time.get_ticks_usec() - outer_start_us
		var remaining_ms: int = maxi(10, (outer_budget_us - elapsed_us) / 1000)
		var waypoints = compute_path_between(from_exit.x, from_exit.y, to_exit.x, to_exit.y, true, remaining_ms)
		if waypoints.size() > 0:
			# Reject paths that deviate too far from a straight line.
			# Compare actual path length against the Manhattan distance between endpoints.
			# Diagonal routes have path_length ≈ Manhattan, so 1.5× allows modest detours.
			var manhattan = absi(to_exit.x - from_exit.x) + absi(to_exit.y - from_exit.y)
			if waypoints.size() > manhattan * PATH_MAX_DEVIATION_RATIO:
				continue  # Too much deviation — wait for terrain to change (e.g. a bridge placed)
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
	"""Find a walkable tile just outside a post's walls, near a door.
	Returns the door tile itself if no non-blocking outside tile exists."""
	if not chunk_manager:
		return Vector2i(center_x, center_y)

	# Search in expanding rings for a door tile, then go one step past it
	var found_door = Vector2i(-99999, -99999)
	for radius in range(1, 12):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue  # Only check ring perimeter
				var tx = center_x + dx
				var ty = center_y + dy
				var tile = chunk_manager.get_tile(tx, ty)
				if tile.get("type", "") == "door":
					found_door = Vector2i(tx, ty)
					# Found a door — return the walkable tile just outside it
					for dir in ASTAR_DIRECTIONS:
						var outside = Vector2i(tx + dir.x, ty + dir.y)
						var outside_tile = chunk_manager.get_tile(outside.x, outside.y)
						if not outside_tile.get("blocks_move", false) and not _is_npc_post_interior(outside.x, outside.y):
							return outside
					# Door found but no walkable outside? Return door itself
					return Vector2i(tx, ty)

	# No door found — return center (shouldn't happen with well-formed posts)
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
				"tower", "storage", "post_marker", "blacksmith", "healer", "guard", "bridge"]:
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

	# Compute path — use permissive mode (any non-blocking tile) for player posts.
	# v0.9.379 — 150ms wall-clock budget (same as periodic road check). This
	# fires when a player builds a post; if the budget elapses no road is
	# stamped this time, but the periodic _try_connect_road will retry.
	var from_exit = _find_post_exit(px, py)
	var to_pos = _path_post_positions[nearest_key]
	var to_exit = _find_post_exit(to_pos.x, to_pos.y)
	var waypoints = compute_path_between(from_exit.x, from_exit.y, to_exit.x, to_exit.y, true, 150)

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

func is_tile_on_path(x: int, y: int) -> bool:
	"""Check if a tile coordinate is a waypoint on any active stamped road path."""
	var pos = Vector2i(x, y)
	for path_key in _path_waypoints:
		if pos in _path_waypoints[path_key]:
			return true
	return false

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

# Dynamic merchant count: 1 per valid road segment (set by compute_merchant_circuits)

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
	return _merchant_circuits.size()

func compute_merchant_circuits(valid_post_keys: Array = []) -> void:
	"""Assign 1 merchant per valid road segment between posts with markets.
	Each merchant walks back and forth between the two posts on its road."""
	_merchant_circuits.clear()
	_merchant_route_waypoints.clear()
	_merchant_total_waypoints.clear()
	_merchant_cache.clear()

	var allowed = valid_post_keys if valid_post_keys.size() > 0 else _path_graph.keys()
	var allowed_set: Dictionary = {}
	for k in allowed:
		allowed_set[k] = true

	# Collect unique connected edges where both posts have markets
	var seen_edges: Dictionary = {}
	var merchant_idx = 0
	for key_a in allowed_set:
		for key_b in _path_graph.get(key_a, []):
			if not allowed_set.has(key_b):
				continue
			var edge_key = _make_path_key(key_a, key_b)
			if seen_edges.has(edge_key):
				continue
			# Must have an actual path between them
			var path_key = _make_path_key(key_a, key_b)
			if not _path_waypoints.has(path_key):
				continue
			seen_edges[edge_key] = true

			# 2-post circuit: [A, B] → walks A→B then B→A
			var circuit: Array = [key_a, key_b]
			_merchant_circuits[merchant_idx] = circuit

			# Precompute waypoints for each segment
			var route_waypoints: Array = []
			var total_wp = 0
			for seg_idx in range(circuit.size()):
				var from_key = circuit[seg_idx]
				var to_key = circuit[(seg_idx + 1) % circuit.size()]
				var segment = get_path_waypoints_for_segment(from_key, to_key)
				if segment.size() == 0:
					var from_pos = _path_post_positions.get(from_key, Vector2i(0, 0))
					var to_pos = _path_post_positions.get(to_key, Vector2i(0, 0))
					segment = [from_pos, to_pos]
				route_waypoints.append(segment)
				total_wp += segment.size()

			_merchant_route_waypoints[merchant_idx] = route_waypoints
			_merchant_total_waypoints[merchant_idx] = total_wp
			merchant_idx += 1

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
	"""Check if a merchant is elite (assigned to a long road)."""
	# First merchant on a road > 100 waypoints gets elite status
	var total_wp = _merchant_total_waypoints.get(merchant_idx, 0)
	return total_wp > 100

func _get_merchant_info(merchant_idx: int) -> Dictionary:
	"""Generate merchant info based on index (deterministic).
	Merchants are couriers — no specialty shop, just carry market goods."""
	var name_idx = merchant_idx % MERCHANT_FIRST_NAMES.size()
	var type_idx = merchant_idx % MERCHANT_TYPES.size()
	var merchant_type = MERCHANT_TYPES[type_idx]

	var inventory_seed = (merchant_idx * 7919 + 42) % 2147483647

	return {
		"id": "merchant_%d" % merchant_idx,
		"name": "%s %s %s" % [merchant_type.prefix, MERCHANT_FIRST_NAMES[name_idx], merchant_type.suffix],
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
		"x": x,
		"y": y,
		"hash": info.inventory_seed,
		"destination": dest_name if not pos.is_resting else "",
		"destination_id": dest_key,
		"is_resting": pos.is_resting,
		"at_post": pos.get("at_post", ""),
		"merchant_idx": merchant_idx,
		"road_merchant": true
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

func _generate_minimap(center_x: int, center_y: int, dungeon_locations: Array = []) -> String:
	"""Generate a compact zoomed-out minimap centered on the player.
	Samples every 2 world tiles → each minimap character covers a 2×2 tile area.
	Coverage: ±40 tiles east/west, ±20 tiles north/south (41×21 chars).
	Displayed at small font size for compact appearance below the main map."""
	if not chunk_manager:
		return ""

	# Sample step: 2 world tiles per minimap char
	const STEP = 2
	const MAP_HALF_W = 20  # minimap chars in each direction (x)
	const MAP_HALF_H = 10  # minimap chars in each direction (y)

	# Build dungeon lookup
	var dungeon_set: Dictionary = {}
	for d in dungeon_locations:
		dungeon_set["%d,%d" % [int(d.x), int(d.y)]] = true

	# Pre-build NPC post bounding boxes for fast lookup
	# (avoid calling is_npc_post_tile for every tile — that iterates all posts)
	var posts = chunk_manager.get_npc_posts()
	# We'll check against post centroids with a generous match radius
	var post_points: Array = []
	for p in posts:
		post_points.append({"x": int(p.get("x", 0)), "y": int(p.get("y", 0))})
		# Also add wing room centers if present
		for wing in p.get("wing_rooms", []):
			var wx = (int(wing.get("x0", 0)) + int(wing.get("x1", 0))) / 2
			var wy = (int(wing.get("y0", 0)) + int(wing.get("y1", 0))) / 2
			post_points.append({"x": wx, "y": wy})

	var output = "[right][font_size=9]"
	for miny in range(MAP_HALF_H, -MAP_HALF_H - 1, -1):
		var line = ""
		for minx in range(-MAP_HALF_W, MAP_HALF_W + 1):
			var wx = center_x + minx * STEP
			var wy = center_y + miny * STEP

			# Player marker (exact center)
			if minx == 0 and miny == 0:
				line += "[color=#FFFF00]@[/color]"
				continue

			# Dungeon — check nearby world tiles in the 2x2 sample block
			var has_dungeon = false
			for dox in range(STEP):
				for doy in range(STEP):
					if dungeon_set.has("%d,%d" % [wx + dox, wy + doy]):
						has_dungeon = true
						break
				if has_dungeon:
					break
			if has_dungeon:
				line += "[color=#FF4444]D[/color]"
				continue

			# NPC post — check if close to any post centroid
			var near_post = false
			for pp in post_points:
				if abs(pp.x - wx) <= STEP + 8 and abs(pp.y - wy) <= STEP + 8:
					# Confirm with actual tile check (on the sampled tile only)
					if chunk_manager.is_npc_post_tile(wx, wy):
						near_post = true
						break
			if near_post:
				line += "[color=#FFD700]P[/color]"
				continue

			# Tile type from chunk
			var tile = chunk_manager.get_tile(wx, wy)
			var tile_type = tile.get("type", "empty")

			match tile_type:
				"water":
					line += "[color=#4488FF]~[/color]"
				"deep_water":
					line += "[color=#2244AA]~[/color]"
				"bridge":
					line += "[color=#C4A882]=[/color]"
				"path":
					line += "[color=#8B7355]:[/color]"
				"wall":
					line += "[color=#888888]#[/color]"
				"tree", "dense_brush":
					line += "[color=#1A6B1A]T[/color]"
				"stone", "ore_vein":
					line += "[color=#887766]o[/color]"
				"floor", "door", "forge", "apothecary", "workbench", "enchant_table",\
				"writing_desk", "market", "inn", "quest_board", "post_marker",\
				"blacksmith", "healer", "throne", "storage", "guard":
					line += "[color=#FFD700].[/color]"
				_:
					# Slice 6a — minimap also picks up biome tint so the overview
					# shows biome regions at a glance. Dimmed (~45% brightness) so
					# the small chars stay legible.
					var minimap_seed = chunk_manager.world_seed if chunk_manager else 0
					var minimap_biome = get_biome_at(wx, wy, minimap_seed)
					line += "[color=%s].[/color]" % _dim_color(get_biome_empty_color(minimap_biome), 0.45)

		output += line + "\n"

	output += "[/font_size][/right]"
	output += "[center][color=#555555][font_size=8]minimap (±%d tiles)[/font_size][/color][/center]" % [MAP_HALF_W * STEP]
	return output

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
