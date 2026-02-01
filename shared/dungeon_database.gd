# dungeon_database.gd
# Defines dungeon types, layouts, encounters, and rewards
extends Node
class_name DungeonDatabase

# Dungeon tile types
enum TileType {
	EMPTY,       # Walkable, nothing special
	WALL,        # Impassable
	ENTRANCE,    # Where player starts
	EXIT,        # Leads to next floor (or out if last floor)
	ENCOUNTER,   # Monster encounter (? on map)
	TREASURE,    # Treasure chest
	BOSS,        # Boss encounter (final floor only)
	CLEARED      # Cleared encounter (was ENCOUNTER or TREASURE)
}

# Tile display characters
const TILE_CHARS = {
	TileType.EMPTY: ".",
	TileType.WALL: "#",
	TileType.ENTRANCE: "E",
	TileType.EXIT: ">",
	TileType.ENCOUNTER: "?",
	TileType.TREASURE: "$",
	TileType.BOSS: "B",
	TileType.CLEARED: "·"
}

# Tile colors for display
const TILE_COLORS = {
	TileType.EMPTY: "#404040",
	TileType.WALL: "#808080",
	TileType.ENTRANCE: "#00FF00",
	TileType.EXIT: "#FFFF00",
	TileType.ENCOUNTER: "#FF4444",
	TileType.TREASURE: "#FFD700",
	TileType.BOSS: "#FF0000",
	TileType.CLEARED: "#303030"
}

# ===== DUNGEON DEFINITIONS =====
const DUNGEON_TYPES = {
	"goblin_cave": {
		"name": "Goblin Cave",
		"description": "A network of caves infested with goblins and their kin.",
		"tier": 3,
		"min_level": 16,
		"max_level": 35,
		"monster_pool": ["Goblin", "Hobgoblin", "Kobold"],
		"boss": {
			"name": "Goblin King",
			"level_mult": 1.5,
			"hp_mult": 2.0,
			"attack_mult": 1.3,
			"abilities": ["Rally", "Dirty Trick"]
		},
		"floors": 3,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"treasures_per_floor": 1,
		"egg_drops": ["Goblin", "Kobold"],
		"egg_drop_chance": 15,
		"material_drops": ["copper_ore", "iron_ore", "ragged_leather"],
		"cooldown_hours": 12,
		"spawn_weight": 30,
		"color": "#7CFC00"
	},
	"spider_nest": {
		"name": "Spider Nest",
		"description": "A web-covered cavern swarming with giant spiders.",
		"tier": 4,
		"min_level": 31,
		"max_level": 55,
		"monster_pool": ["Giant Spider", "Cave Spider", "Venomspitter"],
		"boss": {
			"name": "Broodmother",
			"level_mult": 1.6,
			"hp_mult": 2.5,
			"attack_mult": 1.4,
			"abilities": ["Web Trap", "Poison Spray", "Summon Spiderlings"]
		},
		"floors": 4,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Giant Spider"],
		"egg_drop_chance": 12,
		"material_drops": ["iron_ore", "steel_ore", "shadowleaf"],
		"cooldown_hours": 18,
		"spawn_weight": 25,
		"color": "#8B008B"
	},
	"undead_crypt": {
		"name": "Undead Crypt",
		"description": "Ancient burial chambers haunted by restless dead.",
		"tier": 5,
		"min_level": 51,
		"max_level": 110,
		"monster_pool": ["Skeleton", "Zombie", "Wight", "Wraith"],
		"boss": {
			"name": "Lich Lord",
			"level_mult": 1.7,
			"hp_mult": 3.0,
			"attack_mult": 1.5,
			"abilities": ["Life Drain", "Bone Storm", "Raise Dead"]
		},
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Skeleton", "Zombie", "Wight"],
		"egg_drop_chance": 10,
		"material_drops": ["steel_ore", "mithril_ore", "soul_shard"],
		"cooldown_hours": 24,
		"spawn_weight": 20,
		"color": "#708090"
	},
	"dragon_lair": {
		"name": "Dragon's Lair",
		"description": "A volcanic cavern home to dragons and their wyrmlings.",
		"tier": 6,
		"min_level": 101,
		"max_level": 260,
		"monster_pool": ["Dragon Wyrmling", "Fire Drake", "Magma Elemental"],
		"boss": {
			"name": "Elder Dragon",
			"level_mult": 1.8,
			"hp_mult": 4.0,
			"attack_mult": 1.7,
			"abilities": ["Fire Breath", "Wing Buffet", "Terrifying Roar"]
		},
		"floors": 5,
		"grid_size": 7,
		"encounters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Dragon Wyrmling", "Ancient Dragon"],
		"egg_drop_chance": 8,
		"material_drops": ["mithril_ore", "adamantine_ore", "dragonhide", "dragon_blood"],
		"cooldown_hours": 36,
		"spawn_weight": 15,
		"color": "#FF4500"
	},
	"demon_fortress": {
		"name": "Demon Fortress",
		"description": "A hellish stronghold where demons plot their invasion.",
		"tier": 7,
		"min_level": 251,
		"max_level": 550,
		"monster_pool": ["Demon", "Succubus", "Hellhound", "Balrog"],
		"boss": {
			"name": "Demon Prince",
			"level_mult": 2.0,
			"hp_mult": 5.0,
			"attack_mult": 2.0,
			"abilities": ["Hellfire", "Soul Rend", "Demonic Corruption"]
		},
		"floors": 6,
		"grid_size": 7,
		"encounters_per_floor": 6,
		"treasures_per_floor": 3,
		"egg_drops": ["Demon", "Succubus", "Balrog"],
		"egg_drop_chance": 5,
		"material_drops": ["adamantine_ore", "orichalcum_ore", "void_essence", "primordial_spark"],
		"cooldown_hours": 48,
		"spawn_weight": 10,
		"color": "#DC143C"
	},
	"void_sanctum": {
		"name": "Void Sanctum",
		"description": "A rift in reality where cosmic horrors dwell.",
		"tier": 8,
		"min_level": 500,
		"max_level": 1200,
		"monster_pool": ["Void Walker", "Chaos Spawn", "Reality Bender"],
		"boss": {
			"name": "Void Lord",
			"level_mult": 2.2,
			"hp_mult": 6.0,
			"attack_mult": 2.2,
			"abilities": ["Reality Tear", "Void Consumption", "Dimensional Shift"]
		},
		"floors": 7,
		"grid_size": 8,
		"encounters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Void Walker", "Entropy"],
		"egg_drop_chance": 3,
		"material_drops": ["orichalcum_ore", "void_ore", "celestial_ore", "primordial_spark"],
		"cooldown_hours": 72,
		"spawn_weight": 5,
		"color": "#4B0082"
	}
}

# ===== DUNGEON INSTANCE STRUCTURE =====
# A dungeon instance contains:
# - dungeon_id: String (type from DUNGEON_TYPES)
# - instance_id: String (unique ID for this spawn)
# - world_x, world_y: int (location on world map)
# - spawned_at: int (timestamp)
# - floors: Array of floor grids
# - active_players: Array of peer_ids currently inside

# ===== HELPER FUNCTIONS =====

static func get_dungeon(dungeon_id: String) -> Dictionary:
	"""Get dungeon definition by ID"""
	return DUNGEON_TYPES.get(dungeon_id, {})

static func get_dungeons_for_level(player_level: int) -> Array:
	"""Get list of dungeon IDs appropriate for player level"""
	var result = []
	for dungeon_id in DUNGEON_TYPES:
		var dungeon = DUNGEON_TYPES[dungeon_id]
		if player_level >= dungeon.min_level and player_level <= dungeon.max_level:
			result.append(dungeon_id)
	return result

static func generate_floor_grid(dungeon_id: String, floor_num: int, is_boss_floor: bool) -> Array:
	"""Generate a floor grid for a dungeon. Returns 2D array of TileType."""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return []

	var size = dungeon.grid_size
	var grid = []

	# Initialize with empty tiles
	for y in range(size):
		var row = []
		for x in range(size):
			row.append(TileType.EMPTY)
		grid.append(row)

	# Add walls around the edges
	for x in range(size):
		grid[0][x] = TileType.WALL
		grid[size - 1][x] = TileType.WALL
	for y in range(size):
		grid[y][0] = TileType.WALL
		grid[y][size - 1] = TileType.WALL

	# Add some random interior walls (25% of interior tiles)
	var interior_size = size - 2
	var wall_count = int(interior_size * interior_size * 0.15)
	for _i in range(wall_count):
		var wx = 1 + randi() % interior_size
		var wy = 1 + randi() % interior_size
		# Don't block entrance or exit positions
		if not (wx == 1 and wy == 1) and not (wx == size - 2 and wy == size - 2):
			grid[wy][wx] = TileType.WALL

	# Place entrance (always bottom-left interior)
	grid[size - 2][1] = TileType.ENTRANCE

	# Place exit or boss
	if is_boss_floor:
		# Boss in center
		var center = size / 2
		grid[center][center] = TileType.BOSS
	else:
		# Exit in top-right interior
		grid[1][size - 2] = TileType.EXIT

	# Place encounters
	var encounters_to_place = dungeon.encounters_per_floor
	var placed_encounters = 0
	var attempts = 0
	while placed_encounters < encounters_to_place and attempts < 100:
		var ex = 1 + randi() % interior_size
		var ey = 1 + randi() % interior_size
		if grid[ey][ex] == TileType.EMPTY:
			grid[ey][ex] = TileType.ENCOUNTER
			placed_encounters += 1
		attempts += 1

	# Place treasures
	var treasures_to_place = dungeon.treasures_per_floor
	var placed_treasures = 0
	attempts = 0
	while placed_treasures < treasures_to_place and attempts < 100:
		var tx = 1 + randi() % interior_size
		var ty = 1 + randi() % interior_size
		if grid[ty][tx] == TileType.EMPTY:
			grid[ty][tx] = TileType.TREASURE
			placed_treasures += 1
		attempts += 1

	return grid

static func grid_to_string(grid: Array, player_x: int, player_y: int) -> String:
	"""Convert floor grid to display string with player position"""
	var lines = []
	lines.append("[color=#FFD700]+" + "-".repeat(grid[0].size()) + "+[/color]")

	for y in range(grid.size()):
		var line = "[color=#FFD700]|[/color]"
		for x in range(grid[y].size()):
			if x == player_x and y == player_y:
				line += "[color=#00FF00]@[/color]"
			else:
				var tile = grid[y][x]
				var char = TILE_CHARS.get(tile, "?")
				var color = TILE_COLORS.get(tile, "#FFFFFF")
				line += "[color=%s]%s[/color]" % [color, char]
		line += "[color=#FFD700]|[/color]"
		lines.append(line)

	lines.append("[color=#FFD700]+" + "-".repeat(grid[0].size()) + "+[/color]")
	return "\n".join(lines)

static func get_monster_for_encounter(dungeon_id: String, floor_num: int, dungeon_level: int) -> Dictionary:
	"""Generate a monster for a dungeon encounter"""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return {}

	var monster_pool = dungeon.get("monster_pool", [])
	if monster_pool.is_empty():
		return {}

	# Pick random monster from pool
	var monster_name = monster_pool[randi() % monster_pool.size()]

	# Scale level based on floor (deeper = harder)
	var level_mult = 1.0 + (floor_num * 0.1)  # +10% per floor
	var monster_level = int(dungeon_level * level_mult)

	return {
		"name": monster_name,
		"level": monster_level,
		"is_dungeon_monster": true
	}

static func get_boss_for_dungeon(dungeon_id: String, dungeon_level: int) -> Dictionary:
	"""Generate the boss monster for a dungeon"""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return {}

	var boss_data = dungeon.get("boss", {})
	if boss_data.is_empty():
		return {}

	var level_mult = boss_data.get("level_mult", 1.5)
	var hp_mult = boss_data.get("hp_mult", 2.0)
	var attack_mult = boss_data.get("attack_mult", 1.3)

	return {
		"name": boss_data.name,
		"level": int(dungeon_level * level_mult),
		"hp_mult": hp_mult,
		"attack_mult": attack_mult,
		"abilities": boss_data.get("abilities", []),
		"is_boss": true,
		"is_dungeon_monster": true
	}

static func roll_treasure(dungeon_id: String, floor_num: int) -> Dictionary:
	"""Roll for treasure chest contents"""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return {"gold": 100}

	var tier = dungeon.tier
	var base_gold = tier * 50 * (1 + floor_num)

	# Roll gold
	var gold = base_gold + randi() % (base_gold / 2)

	# Roll for materials
	var materials = []
	var material_drops = dungeon.get("material_drops", [])
	if not material_drops.is_empty():
		# 50% chance for each material
		for mat in material_drops:
			if randi() % 100 < 50:
				materials.append({"id": mat, "quantity": 1 + randi() % 3})

	# Roll for egg (lower chance)
	var egg = {}
	var egg_drops = dungeon.get("egg_drops", [])
	var egg_chance = dungeon.get("egg_drop_chance", 10)
	if not egg_drops.is_empty() and randi() % 100 < egg_chance:
		var egg_monster = egg_drops[randi() % egg_drops.size()]
		egg = {"monster": egg_monster}

	return {
		"gold": gold,
		"materials": materials,
		"egg": egg
	}

static func calculate_completion_rewards(dungeon_id: String, floors_cleared: int) -> Dictionary:
	"""Calculate rewards for completing a dungeon"""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return {}

	var tier = dungeon.tier
	var total_floors = dungeon.floors

	# Base rewards scale with tier and completion
	var completion_bonus = float(floors_cleared) / float(total_floors)
	var base_xp = tier * 500 * completion_bonus
	var base_gold = tier * 200 * completion_bonus

	# Bonus for full clear
	if floors_cleared >= total_floors:
		base_xp *= 1.5
		base_gold *= 1.5

	return {
		"xp": int(base_xp),
		"gold": int(base_gold),
		"floors_cleared": floors_cleared,
		"total_floors": total_floors,
		"full_clear": floors_cleared >= total_floors
	}

static func get_spawn_location_for_tier(tier: int) -> Vector2i:
	"""Get a suitable spawn location for a dungeon of the given tier"""
	# Dungeons spawn further from origin for higher tiers
	var min_distance = tier * 30
	var max_distance = tier * 60

	var angle = randf() * TAU
	var distance = randf_range(min_distance, max_distance)

	return Vector2i(
		int(cos(angle) * distance),
		int(sin(angle) * distance)
	)
