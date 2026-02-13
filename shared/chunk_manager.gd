# chunk_manager.gd
# Manages 4000x4000 world divided into 32x32 tile chunks.
# Unmodified chunks are generated procedurally from a seed.
# Modified chunks are saved as JSON deltas.
class_name ChunkManager
extends Node

const CHUNK_SIZE = 32
const WORLD_MIN = -2000
const WORLD_MAX = 2000

# World seed — set once on first server start, determines all procedural generation
var world_seed: int = 0

# In-memory cache of loaded/modified chunks
# Key: "chunk_X_Y" -> Dictionary of modified tiles
var _loaded_chunks: Dictionary = {}

# Track which chunks have unsaved changes
var _dirty_chunks: Dictionary = {}  # chunk_key -> true

# Depleted node tracking: "x,y" -> respawn_timestamp (Unix time), or -1 for permanent
var depleted_nodes: Dictionary = {}
const NODE_RESPAWN_TIME = 300.0  # 5 minutes (water/fishing only)
const NODE_RESPAWN_CHECK_INTERVAL = 10.0
const DEPLETED_PERMANENT = -1  # Sentinel for nodes that never respawn
const DEPLETED_NODES_FILE = "user://data/depleted_nodes.json"
var _node_respawn_timer: float = 0.0
var _depleted_save_timer: float = 0.0
const DEPLETED_SAVE_INTERVAL = 30.0  # Save depleted nodes every 30 seconds

# Geological event tracking
const GEO_EVENT_MIN_INTERVAL = 1800.0  # 30 minutes
const GEO_EVENT_MAX_INTERVAL = 3600.0  # 60 minutes
var _geo_event_timer: float = 0.0
var _next_geo_event_time: float = 0.0

# Data directory for chunk files
const WORLD_DIR = "user://data/world/"
const WORLD_SEED_FILE = "user://data/world_seed.json"

# Reference to terrain generator (set by server after init)
var terrain_generator = null  # WorldSystem reference

# ===== CHUNK COORDINATE MATH =====

func get_chunk_key(world_x: int, world_y: int) -> String:
	"""Get the chunk key for a world coordinate"""
	var cx = floori(float(world_x - WORLD_MIN) / CHUNK_SIZE)
	var cy = floori(float(world_y - WORLD_MIN) / CHUNK_SIZE)
	return "chunk_%d_%d" % [cx, cy]

func get_chunk_origin(world_x: int, world_y: int) -> Vector2i:
	"""Get the top-left world coordinate of the chunk containing (world_x, world_y)"""
	var cx = floori(float(world_x - WORLD_MIN) / CHUNK_SIZE)
	var cy = floori(float(world_y - WORLD_MIN) / CHUNK_SIZE)
	return Vector2i(cx * CHUNK_SIZE + WORLD_MIN, cy * CHUNK_SIZE + WORLD_MIN)

func get_chunk_indices(world_x: int, world_y: int) -> Vector2i:
	"""Get the chunk grid indices for a world coordinate"""
	var cx = floori(float(world_x - WORLD_MIN) / CHUNK_SIZE)
	var cy = floori(float(world_y - WORLD_MIN) / CHUNK_SIZE)
	return Vector2i(cx, cy)

func world_to_local(world_x: int, world_y: int) -> Vector2i:
	"""Convert world coordinates to local coordinates within the chunk (0 to CHUNK_SIZE-1)"""
	var origin = get_chunk_origin(world_x, world_y)
	return Vector2i(world_x - origin.x, world_y - origin.y)

# ===== TILE ACCESS =====

func get_tile(world_x: int, world_y: int) -> Dictionary:
	"""Get the tile data at world coordinates.
	Returns modified tile if chunk has been changed, otherwise generates procedurally."""
	# Bounds check
	if world_x < WORLD_MIN or world_x > WORLD_MAX or world_y < WORLD_MIN or world_y > WORLD_MAX:
		return {"type": "void", "blocks_move": true, "blocks_los": true}

	var chunk_key = get_chunk_key(world_x, world_y)
	var tile_key = "%d,%d" % [world_x, world_y]

	# Load chunk from disk if not already loaded
	if not _loaded_chunks.has(chunk_key):
		var loaded = _load_or_create_chunk(chunk_key)
		if not loaded.get("modified_tiles", {}).is_empty():
			_loaded_chunks[chunk_key] = loaded

	# Check if this chunk has modifications
	if _loaded_chunks.has(chunk_key):
		var chunk_data = _loaded_chunks[chunk_key]
		var modified_tiles = chunk_data.get("modified_tiles", {})
		if modified_tiles.has(tile_key):
			return modified_tiles[tile_key]

	# No modification — generate procedurally
	if terrain_generator:
		return terrain_generator.generate_tile(world_x, world_y, world_seed)

	# Fallback if terrain_generator not set yet
	return {"type": "empty", "blocks_move": false, "blocks_los": false}

func set_tile(world_x: int, world_y: int, data: Dictionary) -> void:
	"""Set tile data at world coordinates. Marks the chunk as dirty."""
	if world_x < WORLD_MIN or world_x > WORLD_MAX or world_y < WORLD_MIN or world_y > WORLD_MAX:
		return

	var chunk_key = get_chunk_key(world_x, world_y)
	var tile_key = "%d,%d" % [world_x, world_y]

	# Ensure chunk is loaded
	if not _loaded_chunks.has(chunk_key):
		_loaded_chunks[chunk_key] = _load_or_create_chunk(chunk_key)

	var chunk_data = _loaded_chunks[chunk_key]
	if not chunk_data.has("modified_tiles"):
		chunk_data["modified_tiles"] = {}

	chunk_data["modified_tiles"][tile_key] = data
	_dirty_chunks[chunk_key] = true

func remove_tile_modification(world_x: int, world_y: int) -> void:
	"""Remove any modification at this tile, reverting to procedural generation."""
	var chunk_key = get_chunk_key(world_x, world_y)
	var tile_key = "%d,%d" % [world_x, world_y]

	if _loaded_chunks.has(chunk_key):
		var chunk_data = _loaded_chunks[chunk_key]
		var modified_tiles = chunk_data.get("modified_tiles", {})
		if modified_tiles.has(tile_key):
			modified_tiles.erase(tile_key)
			_dirty_chunks[chunk_key] = true

# ===== GATHERING NODE DEPLETION =====

func deplete_node(world_x: int, world_y: int, tile_type: String = "") -> void:
	"""Mark a gathering node as depleted.
	Water nodes respawn after NODE_RESPAWN_TIME. All other nodes are permanent."""
	var coord_key = "%d,%d" % [world_x, world_y]
	if tile_type == "water":
		depleted_nodes[coord_key] = Time.get_unix_time_from_system() + NODE_RESPAWN_TIME
	else:
		depleted_nodes[coord_key] = DEPLETED_PERMANENT

func is_node_depleted(world_x: int, world_y: int) -> bool:
	"""Check if a gathering node is currently depleted."""
	var coord_key = "%d,%d" % [world_x, world_y]
	if not depleted_nodes.has(coord_key):
		return false
	var value = depleted_nodes[coord_key]
	if value == DEPLETED_PERMANENT:
		return true  # Permanent depletion, never respawns
	if Time.get_unix_time_from_system() >= value:
		depleted_nodes.erase(coord_key)
		return false
	return true

func get_depleted_keys() -> Array:
	"""Get all depleted node coordinate keys (for map rendering)."""
	return depleted_nodes.keys()

func process_node_respawns(delta: float) -> void:
	"""Periodically clean up expired depleted nodes and save to disk."""
	_node_respawn_timer += delta
	if _node_respawn_timer >= NODE_RESPAWN_CHECK_INTERVAL:
		_node_respawn_timer = 0.0
		var current_time = Time.get_unix_time_from_system()
		var to_remove = []
		for coord_key in depleted_nodes:
			var value = depleted_nodes[coord_key]
			if value != DEPLETED_PERMANENT and value <= current_time:
				to_remove.append(coord_key)
		for coord_key in to_remove:
			depleted_nodes.erase(coord_key)

	# Periodically save depleted nodes to disk
	_depleted_save_timer += delta
	if _depleted_save_timer >= DEPLETED_SAVE_INTERVAL:
		_depleted_save_timer = 0.0
		save_depleted_nodes()

func save_depleted_nodes() -> void:
	"""Save depleted nodes to disk for persistence across restarts."""
	if depleted_nodes.is_empty():
		if FileAccess.file_exists(DEPLETED_NODES_FILE):
			DirAccess.remove_absolute(DEPLETED_NODES_FILE)
		return
	var file = FileAccess.open(DEPLETED_NODES_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(depleted_nodes))
		file.close()

func load_depleted_nodes() -> void:
	"""Load depleted nodes from disk."""
	if not FileAccess.file_exists(DEPLETED_NODES_FILE):
		return
	var file = FileAccess.open(DEPLETED_NODES_FILE, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		if not content.is_empty():
			var json = JSON.new()
			var error = json.parse(content)
			if error == OK and json.data is Dictionary:
				depleted_nodes = {}
				for key in json.data:
					depleted_nodes[key] = int(json.data[key])  # Cast float back to int
				print("Loaded %d depleted nodes" % depleted_nodes.size())

# ===== CHUNK I/O =====

func _load_or_create_chunk(chunk_key: String) -> Dictionary:
	"""Load a chunk from disk or create an empty one."""
	var filepath = WORLD_DIR + chunk_key + ".json"
	if FileAccess.file_exists(filepath):
		var file = FileAccess.open(filepath, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			if not content.is_empty():
				var json = JSON.new()
				var error = json.parse(content)
				if error == OK and json.data is Dictionary:
					return json.data
				else:
					print("WARNING: Corrupt chunk file %s, creating fresh" % chunk_key)

	# No file or corrupt — return empty chunk (no modifications)
	return {"seed": world_seed, "modified_tiles": {}}

func save_dirty_chunks() -> void:
	"""Write all modified chunks to disk."""
	if _dirty_chunks.is_empty():
		return

	_ensure_world_directory()

	var saved_count = 0
	for chunk_key in _dirty_chunks:
		if _loaded_chunks.has(chunk_key):
			var chunk_data = _loaded_chunks[chunk_key]
			var modified_tiles = chunk_data.get("modified_tiles", {})

			# If chunk has no modifications left, delete the file instead of saving empty
			if modified_tiles.is_empty():
				var filepath = WORLD_DIR + chunk_key + ".json"
				if FileAccess.file_exists(filepath):
					DirAccess.remove_absolute(filepath)
				_loaded_chunks.erase(chunk_key)
			else:
				_save_chunk(chunk_key, chunk_data)
				saved_count += 1

	if saved_count > 0:
		print("Saved %d modified chunks" % saved_count)
	_dirty_chunks.clear()

func _save_chunk(chunk_key: String, chunk_data: Dictionary) -> void:
	"""Save a single chunk to disk."""
	var filepath = WORLD_DIR + chunk_key + ".json"
	var json_string = JSON.stringify(chunk_data, "\t")
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	else:
		print("ERROR: Failed to save chunk %s" % chunk_key)

func is_chunk_modified(chunk_key: String) -> bool:
	"""Check if a chunk has been modified from its procedural state."""
	if _loaded_chunks.has(chunk_key):
		var modified_tiles = _loaded_chunks[chunk_key].get("modified_tiles", {})
		return not modified_tiles.is_empty()
	# Check disk
	var filepath = WORLD_DIR + chunk_key + ".json"
	return FileAccess.file_exists(filepath)

# ===== WORLD SEED =====

func load_world_seed() -> void:
	"""Load world seed from disk, or generate a new one if first run."""
	if FileAccess.file_exists(WORLD_SEED_FILE):
		var file = FileAccess.open(WORLD_SEED_FILE, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var json = JSON.new()
			var error = json.parse(content)
			if error == OK and json.data is Dictionary:
				world_seed = int(json.data.get("seed", 0))
				print("Loaded world seed: %d" % world_seed)
				return

	# Generate new seed
	world_seed = randi()
	save_world_seed()
	print("Generated new world seed: %d" % world_seed)

func save_world_seed() -> void:
	"""Save world seed to disk."""
	_ensure_world_directory()
	var file = FileAccess.open(WORLD_SEED_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"seed": world_seed}, "\t"))
		file.close()

# ===== DIRECTORY MANAGEMENT =====

func _ensure_world_directory() -> void:
	"""Create the world data directory if it doesn't exist."""
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("data"):
			dir.make_dir("data")
		if not dir.dir_exists("data/world"):
			dir.make_dir_recursive("data/world")

# ===== WIPE SUPPORT =====

func wipe_all_chunks() -> void:
	"""Delete all chunk files and reset in-memory state. Used for map wipe."""
	_loaded_chunks.clear()
	_dirty_chunks.clear()
	depleted_nodes.clear()
	# Remove persisted depleted nodes file
	if FileAccess.file_exists(DEPLETED_NODES_FILE):
		DirAccess.remove_absolute(DEPLETED_NODES_FILE)

	var dir = DirAccess.open(WORLD_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json") and file_name.begins_with("chunk_"):
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	print("All chunk files wiped")

func wipe_chunk(chunk_key: String) -> void:
	"""Reset a single chunk to its procedural state."""
	_loaded_chunks.erase(chunk_key)
	_dirty_chunks.erase(chunk_key)

	var filepath = WORLD_DIR + chunk_key + ".json"
	if FileAccess.file_exists(filepath):
		DirAccess.remove_absolute(filepath)

# ===== NPC POST TRACKING =====

# NPC posts are stored separately from chunk data since they're generated once
# and referenced by many systems (quest board, merchants, spawn points, etc.)
const NPC_POSTS_FILE = "user://data/npc_posts.json"

var npc_posts: Array = []  # Array of {x, y, name, category, size, ...}

func load_npc_posts() -> Array:
	"""Load NPC posts from disk. Returns empty array if none exist (first run)."""
	if FileAccess.file_exists(NPC_POSTS_FILE):
		var file = FileAccess.open(NPC_POSTS_FILE, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var json = JSON.new()
			var error = json.parse(content)
			if error == OK and json.data is Dictionary:
				npc_posts = json.data.get("posts", [])
				print("Loaded %d NPC posts" % npc_posts.size())
				return npc_posts

	npc_posts = []
	return npc_posts

func save_npc_posts(posts: Array) -> void:
	"""Save NPC posts to disk."""
	npc_posts = posts
	_ensure_world_directory()
	var file = FileAccess.open(NPC_POSTS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"posts": posts}, "\t"))
		file.close()
		print("Saved %d NPC posts" % posts.size())

func get_npc_posts() -> Array:
	"""Get all NPC posts."""
	return npc_posts

func get_nearest_npc_post(world_x: int, world_y: int) -> Dictionary:
	"""Find the nearest NPC post to the given coordinates."""
	var nearest = {}
	var nearest_dist = INF
	for post in npc_posts:
		var dx = post.get("x", 0) - world_x
		var dy = post.get("y", 0) - world_y
		var dist = sqrt(dx * dx + dy * dy)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = post
	return nearest

func get_npc_post_at(world_x: int, world_y: int) -> Dictionary:
	"""Get NPC post data if the player is inside a post's bounds. Returns {} if not."""
	for post in npc_posts:
		var px = int(post.get("x", 0))
		var py = int(post.get("y", 0))
		var half_size = int(post.get("size", 15)) / 2
		if abs(world_x - px) <= half_size and abs(world_y - py) <= half_size:
			return post
	return {}

func is_npc_post_tile(world_x: int, world_y: int) -> bool:
	"""Check if a tile is inside any NPC post."""
	return not get_npc_post_at(world_x, world_y).is_empty()

# ===== GEOLOGICAL EVENTS =====

func process_geological_events(delta: float) -> Array:
	"""Process geological event timer. Returns array of event descriptions if any triggered."""
	_geo_event_timer += delta
	if _geo_event_timer < _next_geo_event_time:
		return []

	# Reset timer
	_geo_event_timer = 0.0
	_next_geo_event_time = randf_range(GEO_EVENT_MIN_INTERVAL, GEO_EVENT_MAX_INTERVAL)

	# Find a heavily depleted area to regenerate
	return _trigger_geological_event()

func _trigger_geological_event() -> Array:
	"""Geological events are disabled — nodes deplete permanently (except water).
	Kept as stub for potential future use."""
	return []

func initialize_geo_timer() -> void:
	"""Set up initial geological event timer."""
	_geo_event_timer = 0.0
	_next_geo_event_time = randf_range(GEO_EVENT_MIN_INTERVAL, GEO_EVENT_MAX_INTERVAL)
