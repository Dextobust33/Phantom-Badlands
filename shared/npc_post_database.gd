# npc_post_database.gd
# Procedural generation of NPC trading posts from world seed.
# Posts are clustered within ~500 tiles of origin with minimum spacing.
# Each post has a main room + 0-3 wing rooms for varied compound shapes.
# Crafting stations, market, Inn, Quest Board placed inside.
class_name NpcPostDatabase
extends RefCounted

# Post generation parameters
const POST_COUNT_TARGET = 18
const MAX_ATTEMPTS = 200
const POST_PLACEMENT_RADIUS = 450  # Max distance from origin
const MIN_POST_SPACING = 100  # Minimum distance between posts

# Main room interior dimensions (odd for clean centering)
const MAIN_ROOM_MIN = 11
const MAIN_ROOM_MAX = 15
const STARTER_MAIN_SIZE = 15  # Starter post gets maximum main room

# Wing room interior dimensions
const WING_MIN = 5
const WING_MAX = 7

# Door placement
const MIN_DOORS = 8
const MAX_DOORS = 14

# Post name components
const POST_PREFIXES = [
	"Iron", "Silver", "Golden", "Crystal", "Stone",
	"Dark", "Bright", "Shadow", "Storm", "Frost",
	"Fire", "Wind", "Moon", "Sun", "Star",
	"Ancient", "Lost", "Hidden", "Sacred", "Wild"
]

const POST_SUFFIXES = [
	"Haven", "Keep", "Hold", "Gate", "Watch",
	"Rest", "Cross", "Bridge", "Peak", "Dell",
	"Fort", "Camp", "Market", "Harbor", "Forge",
	"Hollow", "Springs", "Landing", "Outpost", "Lodge"
]

# Post categories (visual variety from Phase 6 work)
const POST_CATEGORIES = [
	"haven", "market", "shrine", "farm", "mine",
	"tower", "camp", "exotic", "fortress", "default"
]

# Quest giver names
const QUEST_GIVERS = [
	"Elder Mathis", "Captain Sera", "Scholar Venn", "Warden Thane",
	"Mystic Lyra", "Hunter Brix", "Sage Aldric", "Commander Isolde",
	"Trader Fenwick", "Priestess Mira", "Scout Renly", "Alchemist Zara",
	"Blacksmith Kord", "Ranger Fael", "Archon Drust", "Healer Nessa",
	"Captain Roderick", "Seer Ophelia", "Guard-Captain Voss", "Lorekeeper Elias"
]

# Audit #10 Slice 6L — Region name components. Drawn at post-generation time
# so each procedural world produces unique region names that survive wipes.
# Distinct from POST_PREFIXES/SUFFIXES (which name the post itself) — these
# evoke terrain shape so the territory reads as a landscape, not another keep.
const REGION_PREFIXES = [
	"Sun", "Moon", "Ash", "Bone", "Stone", "Iron", "Frost", "Ember",
	"Verdant", "Hollow", "Mist", "Storm", "Gold", "Silver", "Wild",
	"Lost", "Hidden", "Dark", "Pale", "Crimson", "Amber", "Jade",
	"Whisper", "Echo", "Thorn", "Ember", "Twilight", "Dawn",
]

const REGION_SUFFIXES = [
	"Reach", "Moor", "Wilds", "Marches", "Steppe", "Vale", "Hollow",
	"Crags", "Sands", "Tundra", "Mires", "Plains", "Heath", "Fells",
	"Downs", "Glade", "Wastes", "Verge", "Coast", "Fen",
]

# Tier bands for procedurally-placed posts. Distance from origin (Euclidean)
# determines the post's tier. Bands intentionally narrow at the core and
# widen outward so most posts in the 450-tile placement radius get a tier
# T1..T6, with T7 reserved for any post that happens to roll far out into
# a corner. Tier maps to monster level via existing _distance_to_level.
const TIER_BANDS = [
	{"max_dist": 50, "tier": 1},
	{"max_dist": 100, "tier": 2},
	{"max_dist": 200, "tier": 3},
	{"max_dist": 300, "tier": 4},
	{"max_dist": 400, "tier": 5},
	{"max_dist": 500, "tier": 6},
]
const TIER_BAND_DEFAULT = 7

# Starter post gets a fixed region name — it's the player's first
# anchor, so a curated name beats a procedural roll.
const STARTER_REGION_NAME = "The Heartlands"

# ===== GENERATION =====

static func generate_posts(seed: int) -> Array:
	"""Generate NPC posts from world seed. Returns array of post dictionaries."""
	var rng = RandomNumberGenerator.new()
	rng.seed = seed

	var posts = []

	# First: starter post at origin
	posts.append(_create_starter_post(rng))

	# Generate remaining posts
	var attempts = 0
	while posts.size() < POST_COUNT_TARGET and attempts < MAX_ATTEMPTS:
		attempts += 1
		var x = rng.randi_range(-POST_PLACEMENT_RADIUS, POST_PLACEMENT_RADIUS)
		var y = rng.randi_range(-POST_PLACEMENT_RADIUS, POST_PLACEMENT_RADIUS)

		# Don't place too close to origin (starter post)
		if abs(x) < 30 and abs(y) < 30:
			continue

		# Check minimum spacing from existing posts
		var too_close = false
		for p in posts:
			var dx = x - int(p.get("x", 0))
			var dy = y - int(p.get("y", 0))
			if sqrt(dx * dx + dy * dy) < MIN_POST_SPACING:
				too_close = true
				break

		if too_close:
			continue

		# Reject locations that are on or near water (posts should not spawn in lakes/rivers)
		if _location_has_nearby_water(x, y, seed):
			continue

		posts.append(_generate_post(rng, x, y, false))

	return posts

static func _create_starter_post(rng: RandomNumberGenerator) -> Dictionary:
	"""Create the starter post at origin with guaranteed large main room."""
	var post = _generate_post(rng, 0, 0, true)
	post["name"] = "Crossroads"
	post["category"] = "haven"
	post["quest_giver"] = "Elder Mathis"
	post["is_starter"] = true
	return post

static func _generate_post(rng: RandomNumberGenerator, px: int, py: int, is_starter: bool) -> Dictionary:
	"""Generate a compound-shaped post with main room and optional wings."""
	# Main room dimensions (odd for clean centering)
	var main_w: int
	var main_h: int
	if is_starter:
		main_w = STARTER_MAIN_SIZE
		main_h = STARTER_MAIN_SIZE
	else:
		main_w = _make_odd(rng.randi_range(MAIN_ROOM_MIN, MAIN_ROOM_MAX))
		main_h = _make_odd(rng.randi_range(MAIN_ROOM_MIN, MAIN_ROOM_MAX))

	var half_w = main_w / 2
	var half_h = main_h / 2
	var main_room = {
		"x0": px - half_w, "y0": py - half_h,
		"x1": px + half_w, "y1": py + half_h,
	}

	# Wing count distribution: 10% none, 30% one, 40% two, 20% three
	var roll = rng.randf()
	var wing_count = 0
	if roll < 0.1:
		wing_count = 0
	elif roll < 0.4:
		wing_count = 1
	elif roll < 0.8:
		wing_count = 2
	else:
		wing_count = 3

	# Assign wings to random sides
	var sides = ["north", "south", "east", "west"]
	_shuffle_array(rng, sides)

	var wing_rooms = []
	for i in range(mini(wing_count, sides.size())):
		var side = sides[i]
		var ww = _make_odd(rng.randi_range(WING_MIN, WING_MAX))
		var wh = _make_odd(rng.randi_range(WING_MIN, WING_MAX))
		var wing = _compute_wing_rect(side, px, py, main_room, ww, wh)
		wing_rooms.append(wing)

	# Compute bounding box (includes walls)
	var bounds = _compute_bounds(main_room, wing_rooms)

	var category = POST_CATEGORIES[rng.randi_range(0, POST_CATEGORIES.size() - 1)]
	var name = _generate_name(rng)
	var quest_giver = QUEST_GIVERS[rng.randi_range(0, QUEST_GIVERS.size() - 1)]

	# Slice 6L — tier from distance band, region name from procedural pool.
	# Starter post is locked to T1 + curated region name.
	var tier: int
	var region_name: String
	if is_starter:
		tier = 1
		region_name = STARTER_REGION_NAME
	else:
		tier = _tier_from_distance(px, py)
		region_name = _generate_region_name(rng)

	return {
		"x": px,
		"y": py,
		"name": name,
		"category": category,
		"size": main_w,  # Kept for compatibility
		"quest_giver": quest_giver,
		"is_starter": is_starter,
		"bounds": bounds,
		"wings": wing_rooms.size(),
		"main_room": main_room,
		"wing_rooms": wing_rooms,
		"tier": tier,
		"region_name": region_name,
	}

static func _tier_from_distance(px: int, py: int) -> int:
	"""Slice 6L — assign a tier (1-7) to a procedurally-placed post based on
	its Euclidean distance from origin. Bands narrow at the core and widen
	outward; anything past the last band falls to TIER_BAND_DEFAULT."""
	var dist = sqrt(float(px * px + py * py))
	for band in TIER_BANDS:
		if dist <= float(band["max_dist"]):
			return int(band["tier"])
	return TIER_BAND_DEFAULT

static func _generate_region_name(rng: RandomNumberGenerator) -> String:
	"""Compose a region name from the procedural pools."""
	var prefix = REGION_PREFIXES[rng.randi_range(0, REGION_PREFIXES.size() - 1)]
	var suffix = REGION_SUFFIXES[rng.randi_range(0, REGION_SUFFIXES.size() - 1)]
	return "%s %s" % [prefix, suffix]

static func backfill_post_fields(posts: Array, seed: int) -> Array:
	"""Slice 6L — migrate posts saved before tier/region_name existed. Re-uses
	the world seed so the same world reload produces stable names across
	sessions. New fields only — doesn't touch existing data."""
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	for post in posts:
		if not post.has("tier"):
			if post.get("is_starter", false):
				post["tier"] = 1
			else:
				post["tier"] = _tier_from_distance(int(post.get("x", 0)), int(post.get("y", 0)))
		if not post.has("region_name") or String(post.get("region_name", "")).is_empty():
			if post.get("is_starter", false):
				post["region_name"] = STARTER_REGION_NAME
			else:
				post["region_name"] = _generate_region_name(rng)
	return posts

static func _generate_name(rng: RandomNumberGenerator) -> String:
	"""Generate a random post name."""
	var prefix = POST_PREFIXES[rng.randi_range(0, POST_PREFIXES.size() - 1)]
	var suffix = POST_SUFFIXES[rng.randi_range(0, POST_SUFFIXES.size() - 1)]
	return "%s %s" % [prefix, suffix]

# ===== SHAPE HELPERS =====

static func _make_odd(n: int) -> int:
	"""Ensure a number is odd for clean centering."""
	return n if n % 2 == 1 else n + 1

static func _shuffle_array(rng: RandomNumberGenerator, arr: Array) -> void:
	"""Fisher-Yates shuffle using the given RNG."""
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

static func _compute_wing_rect(side: String, px: int, py: int, main: Dictionary, ww: int, wh: int) -> Dictionary:
	"""Compute a wing rectangle attached to the given side of the main room.
	Wing overlaps main room edge by 1 tile for natural connectivity."""
	var half_w = ww / 2
	var half_h = wh / 2
	match side:
		"north":
			return {"x0": px - half_w, "y0": int(main["y0"]) - wh + 1, "x1": px + half_w, "y1": int(main["y0"])}
		"south":
			return {"x0": px - half_w, "y0": int(main["y1"]), "x1": px + half_w, "y1": int(main["y1"]) + wh - 1}
		"east":
			return {"x0": int(main["x1"]), "y0": py - half_h, "x1": int(main["x1"]) + ww - 1, "y1": py + half_h}
		"west":
			return {"x0": int(main["x0"]) - ww + 1, "y0": py - half_h, "x1": int(main["x0"]), "y1": py + half_h}
	return {}

static func _compute_bounds(main_room: Dictionary, wing_rooms: Array) -> Dictionary:
	"""Compute bounding box including walls (1 tile outside floor)."""
	var min_x = int(main_room["x0"])
	var max_x = int(main_room["x1"])
	var min_y = int(main_room["y0"])
	var max_y = int(main_room["y1"])
	for wing in wing_rooms:
		min_x = mini(min_x, int(wing["x0"]))
		max_x = maxi(max_x, int(wing["x1"]))
		min_y = mini(min_y, int(wing["y0"]))
		max_y = maxi(max_y, int(wing["y1"]))
	# Include walls (1 tile outside floor on all sides)
	return {"min_x": min_x - 1, "max_x": max_x + 1, "min_y": min_y - 1, "max_y": max_y + 1}

# ===== FLOOR/WALL/DOOR COMPUTATION =====

static func _compute_floor_tiles(main_room: Dictionary, wing_rooms: Array) -> Dictionary:
	"""Compute all floor tile positions from room rectangles. Returns Dictionary of 'x,y' -> true."""
	var floor_tiles = {}
	_add_rect_tiles(floor_tiles, main_room)
	for wing in wing_rooms:
		_add_rect_tiles(floor_tiles, wing)
	return floor_tiles

static func _add_rect_tiles(tiles: Dictionary, rect: Dictionary) -> void:
	"""Add all tile positions in a rectangle to the dictionary."""
	for x in range(int(rect["x0"]), int(rect["x1"]) + 1):
		for y in range(int(rect["y0"]), int(rect["y1"]) + 1):
			tiles["%d,%d" % [x, y]] = true

static func _compute_wall_tiles(floor_tiles: Dictionary) -> Dictionary:
	"""Compute wall tiles: any non-floor tile 8-way adjacent to a floor tile.
	Including diagonal neighbors seals off the outer corners of each room so
	players can't slip into the post diagonally, bypassing the doors."""
	var wall_tiles = {}
	var offsets = [
		[-1, 0], [1, 0], [0, -1], [0, 1],
		[-1, -1], [-1, 1], [1, -1], [1, 1],
	]
	for key in floor_tiles:
		var parts = key.split(",")
		var fx = int(parts[0])
		var fy = int(parts[1])
		for offset in offsets:
			var nkey = "%d,%d" % [fx + offset[0], fy + offset[1]]
			if not floor_tiles.has(nkey):
				wall_tiles[nkey] = true
	return wall_tiles

static func _select_doors(wall_tiles: Dictionary, floor_tiles: Dictionary, px: int, py: int) -> Dictionary:
	"""Select door positions from perimeter walls, evenly distributed around the shape."""
	var offsets = [[-1, 0], [1, 0], [0, -1], [0, 1]]

	# Find perimeter walls: walls that face outward (have a neighbor that is neither floor nor wall)
	var candidates = []
	for key in wall_tiles:
		var parts = key.split(",")
		var wx = int(parts[0])
		var wy = int(parts[1])
		var faces_outside = false
		var adjacent_floor_count = 0
		for offset in offsets:
			var nkey = "%d,%d" % [wx + offset[0], wy + offset[1]]
			if floor_tiles.has(nkey):
				adjacent_floor_count += 1
			elif not wall_tiles.has(nkey):
				faces_outside = true
		# Good door candidate: faces outside and connects to exactly 1 floor tile
		if faces_outside and adjacent_floor_count == 1:
			candidates.append(Vector2i(wx, wy))

	if candidates.is_empty():
		return {}

	# Sort by angle from center for even angular distribution
	var center_x = float(px)
	var center_y = float(py)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var angle_a = atan2(a.y - center_y, a.x - center_x)
		var angle_b = atan2(b.y - center_y, b.x - center_x)
		return angle_a < angle_b
	)

	# Pick evenly spaced doors
	var target = clampi(candidates.size() / 3, MIN_DOORS, MAX_DOORS)
	if candidates.size() <= MIN_DOORS:
		target = candidates.size()

	var doors = {}
	var spacing = float(candidates.size()) / float(target)
	for i in range(target):
		var idx = int(i * spacing) % candidates.size()
		var pos = candidates[idx]
		doors["%d,%d" % [pos.x, pos.y]] = true

	return doors

# ===== LAYOUT STAMPING =====

static func stamp_post_into_chunks(post: Dictionary, chunk_manager) -> void:
	"""Write post layout (walls, stations, floor) into chunk data.
	Supports compound shapes with main room + wings.
	Falls back to legacy layout for old-format posts."""
	var px = int(post.get("x", 0))
	var py = int(post.get("y", 0))
	var is_crossroads = post.get("is_starter", false)
	var main_room = post.get("main_room", {})
	var wing_rooms = post.get("wing_rooms", [])

	# Legacy fallback for old-format posts
	if main_room.is_empty():
		_stamp_legacy_post(post, chunk_manager)
		return

	# Step 1: Compute floor tiles from all rooms
	var floor_tiles = _compute_floor_tiles(main_room, wing_rooms)

	# Step 2: Compute wall tiles
	var wall_tiles = _compute_wall_tiles(floor_tiles)

	# Step 3: Select doors from perimeter walls
	var door_tiles = _select_doors(wall_tiles, floor_tiles, px, py)

	# Step 4: Stamp floor tiles
	for key in floor_tiles:
		var parts = key.split(",")
		chunk_manager.set_tile(int(parts[0]), int(parts[1]), {
			"type": "floor", "tier": 0,
			"blocks_move": false, "blocks_los": false,
		})

	# Step 5: Stamp wall and door tiles
	for key in wall_tiles:
		var parts = key.split(",")
		var wx = int(parts[0])
		var wy = int(parts[1])
		if door_tiles.has(key):
			chunk_manager.set_tile(wx, wy, {
				"type": "door", "tier": 0,
				"blocks_move": false, "blocks_los": false,
			})
		else:
			chunk_manager.set_tile(wx, wy, {
				"type": "wall", "tier": 0,
				"blocks_move": true, "blocks_los": true,
			})

	# Step 6: Place stations inside main room
	_place_stations(chunk_manager, main_room, is_crossroads, px, py, door_tiles)

	# Step 7: Post marker at center (placed after stations to ensure it wins)
	chunk_manager.set_tile(px, py, {
		"type": "post_marker", "tier": 0,
		"blocks_move": false, "blocks_los": false,
	})

# ===== STATION PLACEMENT =====

static func _place_stations(chunk_manager, main_room: Dictionary, is_crossroads: bool, px: int, py: int, door_tiles: Dictionary = {}) -> void:
	"""Scatter all crafting stations, services, and commerce randomly inside the main
	room. Each station is placed on a unique floor tile such that no two stations are
	cardinally adjacent (so players can always walk around any station). Placement is
	seeded by the post center so the layout is stable across visits but varies
	between posts."""
	var mx0 = int(main_room["x0"])
	var my0 = int(main_room["y0"])
	var mx1 = int(main_room["x1"])
	var my1 = int(main_room["y1"])

	# Station area: 1 tile in from main room edges (leaves a 1-tile walkable
	# corridor along the inner wall perimeter).
	var ix0 = mx0 + 1
	var ix1 = mx1 - 1
	var iy0 = my0 + 1
	var iy1 = my1 - 1

	# Station list — pairs are preserved (2 forges, 2 healers, etc.) but they
	# no longer have to land near each other on the map.
	var stations: Array = [
		"forge", "forge",
		"apothecary", "apothecary",
		"enchant_table", "enchant_table",
		"writing_desk", "writing_desk",
		"workbench", "workbench",
		"quest_board", "quest_board",
		"blacksmith", "blacksmith",
		"inn",
		"healer", "healer",
		"market", "market",
	]

	# Deterministic RNG so layout is stable per post but varies between posts.
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("post_layout_%d_%d" % [px, py])

	# Shuffle station order (which spot each station type ends up in is random).
	for i in range(stations.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = stations[i]
		stations[i] = stations[j]
		stations[j] = tmp

	# Build the candidate tile list — every interior floor tile except:
	#  • the post marker at (px, py)
	#  • tiles that are cardinally adjacent to any door (keep entries clear)
	#  • the throne spot for crossroads (reserved below)
	var throne_spot = Vector2i(px, my1 - 1) if is_crossroads else Vector2i(-99999, -99999)
	var candidates: Array[Vector2i] = []
	for x in range(ix0, ix1 + 1):
		for y in range(iy0, iy1 + 1):
			if x == px and y == py:
				continue
			if is_crossroads and x == throne_spot.x and y == throne_spot.y:
				continue
			if _tile_touches_door(x, y, door_tiles):
				continue
			candidates.append(Vector2i(x, y))

	# Shuffle candidates — Fisher-Yates with the same seeded RNG.
	for i in range(candidates.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	# Greedy placement: walk the shuffled candidates and place a station
	# whenever the tile has no already-placed station cardinally adjacent.
	# This guarantees every station has open corridor on at least some side.
	var placed: Dictionary = {}  # "x,y" -> true
	var placed_count = 0
	var total_stations = stations.size()
	for cand in candidates:
		if placed_count >= total_stations:
			break
		if _has_cardinal_neighbor(cand.x, cand.y, placed):
			continue
		_place_station(chunk_manager, cand.x, cand.y, stations[placed_count])
		placed["%d,%d" % [cand.x, cand.y]] = true
		placed_count += 1

	# Fallback: if the spacing constraint was too strict (tiny post), place
	# leftover stations wherever there's still a free candidate, ignoring the
	# adjacency rule. Better to have a cramped station than none at all.
	if placed_count < total_stations:
		for cand in candidates:
			if placed_count >= total_stations:
				break
			var key = "%d,%d" % [cand.x, cand.y]
			if placed.has(key):
				continue
			_place_station(chunk_manager, cand.x, cand.y, stations[placed_count])
			placed[key] = true
			placed_count += 1

	# Crossroads: throne is always dead-center of the south wall so it's easy
	# to find and anchor the capital visually.
	if is_crossroads:
		_place_station(chunk_manager, throne_spot.x, throne_spot.y, "throne")

static func _tile_touches_door(x: int, y: int, door_tiles: Dictionary) -> bool:
	"""True if (x,y) or any of its 4 cardinal neighbors is a door tile."""
	if door_tiles.is_empty():
		return false
	var offsets = [[0, 0], [-1, 0], [1, 0], [0, -1], [0, 1]]
	for o in offsets:
		if door_tiles.has("%d,%d" % [x + o[0], y + o[1]]):
			return true
	return false

static func _has_cardinal_neighbor(x: int, y: int, placed: Dictionary) -> bool:
	"""True if any of the 4 cardinal neighbors of (x,y) is in the placed set."""
	var offsets = [[-1, 0], [1, 0], [0, -1], [0, 1]]
	for o in offsets:
		if placed.has("%d,%d" % [x + o[0], y + o[1]]):
			return true
	return false

static func _place_station(chunk_manager, x: int, y: int, station_type: String) -> void:
	"""Place a station tile (blocking — interacted via bump)."""
	chunk_manager.set_tile(x, y, {
		"type": station_type, "tier": 0,
		"blocks_move": true, "blocks_los": false,
	})

# ===== LEGACY SUPPORT =====

static func _stamp_legacy_post(post: Dictionary, chunk_manager) -> void:
	"""Stamp a post using the old size-based square layout. For backward compatibility."""
	var px = int(post.get("x", 0))
	var py = int(post.get("y", 0))
	var size = int(post.get("size", 15))
	var half = size / 2
	var is_crossroads = post.get("is_starter", false)

	var min_x = px - half
	var max_x = px + half
	var min_y = py - half
	var max_y = py + half
	var door_offsets = [-3, 0, 3]

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			if x == min_x or x == max_x or y == min_y or y == max_y:
				var is_door = false
				for offset in door_offsets:
					if (y == min_y or y == max_y) and x == px + offset:
						is_door = true
						break
					if (x == min_x or x == max_x) and y == py + offset:
						is_door = true
						break
				if (x == min_x or x == max_x) and (y == min_y or y == max_y):
					is_door = false
				if is_door:
					chunk_manager.set_tile(x, y, {
						"type": "door", "tier": 0,
						"blocks_move": false, "blocks_los": false,
					})
				else:
					chunk_manager.set_tile(x, y, {
						"type": "wall", "tier": 0,
						"blocks_move": true, "blocks_los": true,
					})
			else:
				chunk_manager.set_tile(x, y, {
					"type": "floor", "tier": 0,
					"blocks_move": false, "blocks_los": false,
				})

	# Center marker (under the stations grid)
	chunk_manager.set_tile(px, py, {
		"type": "post_marker", "tier": 0,
		"blocks_move": false, "blocks_los": false,
	})

	# Delegate station placement to the shared randomized layout so legacy
	# posts get the same random-per-post variety as new posts.
	var synthetic_main = {"x0": min_x, "y0": min_y, "x1": max_x, "y1": max_y}
	# Build door coord set for the legacy perimeter doors so stations don't
	# spawn immediately inside a doorway and block foot traffic.
	var door_coords: Dictionary = {}
	for offset in door_offsets:
		door_coords["%d,%d" % [px + offset, min_y]] = true
		door_coords["%d,%d" % [px + offset, max_y]] = true
		door_coords["%d,%d" % [min_x, py + offset]] = true
		door_coords["%d,%d" % [max_x, py + offset]] = true
	_place_stations(chunk_manager, synthetic_main, is_crossroads, px, py, door_coords)

# ===== WATER PROXIMITY CHECK =====
# Duplicated from WorldSystem so it can run in a static context during post generation.
# Keep in sync with WorldSystem._is_water_tile_generated / _water_noise / _seeded_hash_float.

static func _location_has_nearby_water(cx: int, cy: int, seed: int) -> bool:
	"""Return true if any tile within POST_WATER_MARGIN of (cx,cy) is water."""
	const POST_WATER_MARGIN = 12  # Must be >= max half-size of any post room + walls
	for dx in range(-POST_WATER_MARGIN, POST_WATER_MARGIN + 1):
		for dy in range(-POST_WATER_MARGIN, POST_WATER_MARGIN + 1):
			if _is_water_static(cx + dx, cy + dy, seed):
				return true
	return false

static func _is_water_static(x: int, y: int, seed: int) -> bool:
	var water_noise = _water_noise_static(x, y, seed)
	if water_noise > 0.62:
		return true
	var pond_hash = _seeded_hash_float_static(x * 173 + y * 251, seed + 500)
	return pond_hash > 0.997

static func _water_noise_static(x: int, y: int, seed: int) -> float:
	const FREQ = 0.03
	var fx = x * FREQ
	var fy = y * FREQ
	var ix = floori(fx)
	var iy = floori(fy)
	var frac_x = fx - ix
	var frac_y = fy - iy
	var v00 = _seeded_hash_float_static(ix * 127 + iy * 311, seed + 100)
	var v10 = _seeded_hash_float_static((ix + 1) * 127 + iy * 311, seed + 100)
	var v01 = _seeded_hash_float_static(ix * 127 + (iy + 1) * 311, seed + 100)
	var v11 = _seeded_hash_float_static((ix + 1) * 127 + (iy + 1) * 311, seed + 100)
	var sx = frac_x * frac_x * (3.0 - 2.0 * frac_x)
	var sy = frac_y * frac_y * (3.0 - 2.0 * frac_y)
	var top = v00 + (v10 - v00) * sx
	var bottom = v01 + (v11 - v01) * sx
	return top + (bottom - top) * sy

static func _seeded_hash_float_static(coord_hash: int, seed: int) -> float:
	var h = abs((coord_hash + seed) * 2654435761) % 1000000
	return h / 1000000.0
