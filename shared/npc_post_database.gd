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
	}

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
	"""Compute wall tiles: any non-floor tile adjacent to a floor tile."""
	var wall_tiles = {}
	var offsets = [[-1, 0], [1, 0], [0, -1], [0, 1]]
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
	_place_stations(chunk_manager, main_room, is_crossroads, px, py)

	# Step 7: Post marker at center (placed after stations to ensure it wins)
	chunk_manager.set_tile(px, py, {
		"type": "post_marker", "tier": 0,
		"blocks_move": false, "blocks_los": false,
	})

# ===== STATION PLACEMENT =====

static func _place_stations(chunk_manager, main_room: Dictionary, is_crossroads: bool, px: int, py: int) -> void:
	"""Place all crafting stations, services, and commerce inside the main room.
	Stations are placed in rows from top-left, wrapping to next row when needed."""
	var mx0 = int(main_room["x0"])
	var my0 = int(main_room["y0"])
	var mx1 = int(main_room["x1"])
	var my1 = int(main_room["y1"])

	# Station area: 2 tiles in from main room edges
	var ix0 = mx0 + 2
	var ix1 = mx1 - 2
	var iy0 = my0 + 2

	# All stations in placement order
	var stations = [
		"forge", "forge", "apothecary", "apothecary", "enchant_table", "enchant_table",
		"writing_desk", "writing_desk", "workbench", "workbench",
		"quest_board", "quest_board", "blacksmith", "blacksmith",
		"inn", "healer", "healer", "market", "market",
	]

	var cur_x = ix0
	var cur_y = iy0

	for station in stations:
		if cur_x > ix1:
			cur_x = ix0
			cur_y += 2  # Row gap for walkability
		# Skip center tile (reserved for post_marker)
		if cur_x == px and cur_y == py:
			cur_x += 1
			if cur_x > ix1:
				cur_x = ix0
				cur_y += 2
		_place_station(chunk_manager, cur_x, cur_y, station)
		cur_x += 1

	# Crossroads: place throne near center-bottom of main room
	if is_crossroads:
		_place_station(chunk_manager, px, my1 - 1, "throne")

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

	var ix0 = min_x + 2
	var ix1 = max_x - 2
	var iy0 = min_y + 2
	var iy1 = max_y - 2

	_place_station(chunk_manager, ix0, iy0, "forge")
	_place_station(chunk_manager, ix0 + 1, iy0, "forge")
	_place_station(chunk_manager, ix0 + 3, iy0, "apothecary")
	_place_station(chunk_manager, ix0 + 4, iy0, "apothecary")
	_place_station(chunk_manager, ix0 + 6, iy0, "enchant_table")
	_place_station(chunk_manager, ix0 + 7, iy0, "enchant_table")
	_place_station(chunk_manager, ix0, iy0 + 2, "writing_desk")
	_place_station(chunk_manager, ix0 + 1, iy0 + 2, "writing_desk")
	_place_station(chunk_manager, ix0 + 3, iy0 + 2, "workbench")
	_place_station(chunk_manager, ix0 + 4, iy0 + 2, "workbench")
	_place_station(chunk_manager, ix0, iy0 + 4, "quest_board")
	_place_station(chunk_manager, ix0 + 2, iy0 + 4, "quest_board")
	_place_station(chunk_manager, ix0 + 4, iy0 + 4, "blacksmith")
	_place_station(chunk_manager, ix0 + 5, iy0 + 4, "blacksmith")
	chunk_manager.set_tile(px, py, {
		"type": "post_marker", "tier": 0,
		"blocks_move": false, "blocks_los": false,
	})
	_place_station(chunk_manager, ix0, iy0 + 6, "inn")
	_place_station(chunk_manager, ix0 + 2, iy0 + 6, "healer")
	_place_station(chunk_manager, ix0 + 3, iy0 + 6, "healer")
	_place_station(chunk_manager, ix1 - 1, iy0 + 6, "market")
	_place_station(chunk_manager, ix1, iy0 + 6, "market")
	if is_crossroads:
		_place_station(chunk_manager, px, iy1, "throne")
