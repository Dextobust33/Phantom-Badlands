# npc_post_database.gd
# Procedural generation of NPC trading posts from world seed.
# Posts are clustered within ~500 tiles of origin with minimum spacing.
# Each post has crafting stations, market, Inn, Quest Board.
class_name NpcPostDatabase
extends RefCounted

# Post generation parameters
const POST_COUNT_TARGET = 18
const MAX_ATTEMPTS = 200
const POST_PLACEMENT_RADIUS = 450  # Max distance from origin
const MIN_POST_SPACING = 100  # Minimum distance between posts
const MIN_POST_SIZE = 15  # Minimum interior size
const MAX_POST_SIZE = 17  # Maximum interior size
const STARTER_POST_SIZE = 15  # Size of the origin post

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
			var dx = x - p.get("x", 0)
			var dy = y - p.get("y", 0)
			if sqrt(dx * dx + dy * dy) < MIN_POST_SPACING:
				too_close = true
				break

		if too_close:
			continue

		var size = rng.randi_range(MIN_POST_SIZE, MAX_POST_SIZE)
		var category = POST_CATEGORIES[rng.randi_range(0, POST_CATEGORIES.size() - 1)]
		var name = _generate_name(rng)
		var quest_giver = QUEST_GIVERS[rng.randi_range(0, QUEST_GIVERS.size() - 1)]

		posts.append({
			"x": x,
			"y": y,
			"name": name,
			"category": category,
			"size": size,
			"quest_giver": quest_giver,
			"is_starter": false,
		})

	return posts

static func _create_starter_post(rng: RandomNumberGenerator) -> Dictionary:
	"""Create the starter post at origin."""
	return {
		"x": 0,
		"y": 0,
		"name": "Crossroads",
		"category": "haven",
		"size": STARTER_POST_SIZE,
		"quest_giver": "Elder Mathis",
		"is_starter": true,
	}

static func _generate_name(rng: RandomNumberGenerator) -> String:
	"""Generate a random post name."""
	var prefix = POST_PREFIXES[rng.randi_range(0, POST_PREFIXES.size() - 1)]
	var suffix = POST_SUFFIXES[rng.randi_range(0, POST_SUFFIXES.size() - 1)]
	return "%s %s" % [prefix, suffix]

# ===== LAYOUT STAMPING =====

static func stamp_post_into_chunks(post: Dictionary, chunk_manager) -> void:
	"""Write post layout (walls, stations, floor) into chunk data.
	Clears any resource nodes inside the walls.
	Layout: 2 copies of each crafting station (solid/blocking), 2 quest boards,
	market, inn, post_marker. All stations use bump-to-interact.
	Crossroads gets a throne tile. Multiple doors per wall side."""
	var px = int(post.get("x", 0))
	var py = int(post.get("y", 0))
	var size = int(post.get("size", 15))
	var half = size / 2
	var is_crossroads = post.get("is_starter", false)

	# Calculate bounds (all integers — critical: JSON loads numbers as floats)
	var min_x = px - half
	var max_x = px + half
	var min_y = py - half
	var max_y = py + half

	# Door offsets from center on each wall side (3 doors per side)
	var door_offsets = [-3, 0, 3]

	# Phase 1: Clear interior, place walls with multiple doors
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			if x == min_x or x == max_x or y == min_y or y == max_y:
				# Check if this position is a door
				var is_door = false
				for offset in door_offsets:
					# North/South walls: vary x
					if (y == min_y or y == max_y) and x == px + offset:
						is_door = true
						break
					# East/West walls: vary y
					if (x == min_x or x == max_x) and y == py + offset:
						is_door = true
						break
				# Corner tiles are always walls
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

	# Phase 2: Place stations inside the post (all blocking for bump-to-interact)
	# Interior bounds (2 tiles in from walls for spacing)
	var ix0 = min_x + 2  # interior left
	var ix1 = max_x - 2  # interior right
	var iy0 = min_y + 2  # interior top
	var iy1 = max_y - 2  # interior bottom

	# Row 1 (top interior): Crafting stations, 2 of each, paired
	# forge, forge, apothecary, apothecary, enchant_table, enchant_table
	_place_station(chunk_manager, ix0, iy0, "forge")
	_place_station(chunk_manager, ix0 + 1, iy0, "forge")
	_place_station(chunk_manager, ix0 + 3, iy0, "apothecary")
	_place_station(chunk_manager, ix0 + 4, iy0, "apothecary")
	_place_station(chunk_manager, ix0 + 6, iy0, "enchant_table")
	_place_station(chunk_manager, ix0 + 7, iy0, "enchant_table")

	# Row 2 (top+2): writing_desk pair, workbench pair
	_place_station(chunk_manager, ix0, iy0 + 2, "writing_desk")
	_place_station(chunk_manager, ix0 + 1, iy0 + 2, "writing_desk")
	_place_station(chunk_manager, ix0 + 3, iy0 + 2, "workbench")
	_place_station(chunk_manager, ix0 + 4, iy0 + 2, "workbench")

	# Row 3 (middle area): quest boards, post marker, inn
	_place_station(chunk_manager, ix0, iy0 + 4, "quest_board")
	_place_station(chunk_manager, ix0 + 2, iy0 + 4, "quest_board")

	# Post marker at center
	chunk_manager.set_tile(px, py, {
		"type": "post_marker", "tier": 0,
		"blocks_move": false, "blocks_los": false,
	})

	# Inn and Market on right side
	_place_station(chunk_manager, ix1 - 1, iy0 + 4, "inn")
	_place_station(chunk_manager, ix1, iy0 + 4, "market")

	# Crossroads: place throne near center-bottom
	if is_crossroads:
		_place_station(chunk_manager, px, iy1, "throne")

static func _place_station(chunk_manager, x: int, y: int, station_type: String) -> void:
	"""Place a station tile (blocking — interacted via bump)."""
	chunk_manager.set_tile(x, y, {
		"type": station_type, "tier": 0,
		"blocks_move": true, "blocks_los": false,
	})
