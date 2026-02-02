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
# Dungeons are now named after their boss monster. Defeating the boss GUARANTEES
# that monster's companion egg. Additional eggs can drop from treasure chests
# with chances based on monster tier (higher tier = rarer drops).
const DUNGEON_TYPES = {
	# ===== TIER 3 DUNGEONS (Level 16-35) =====
	"troll_den": {
		"name": "Troll's Den",
		"description": "A foul-smelling cave where a mighty Troll has made its lair.",
		"tier": 3,
		"min_level": 16,
		"max_level": 35,
		"monster_pool": ["Goblin", "Hobgoblin", "Ogre"],
		"boss": {
			"name": "Troll",
			"monster_type": "Troll",  # Actual monster type for egg drop
			"level_mult": 1.5,
			"hp_mult": 2.5,
			"attack_mult": 1.4,
			"abilities": ["Regeneration", "Boulder Throw"]
		},
		"boss_egg": "Troll",  # GUARANTEED egg on completion
		"floors": 3,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"treasures_per_floor": 1,
		"egg_drops": ["Goblin", "Ogre"],  # Additional possible eggs from treasure
		"material_drops": ["copper_ore", "iron_ore", "ragged_leather"],
		"cooldown_hours": 12,
		"spawn_weight": 30,
		"color": "#228B22"
	},
	"wyvern_roost": {
		"name": "Wyvern's Roost",
		"description": "A mountain peak nest where a fearsome Wyvern guards its territory.",
		"tier": 3,
		"min_level": 20,
		"max_level": 40,
		"monster_pool": ["Harpy", "Gargoyle", "Kobold"],
		"boss": {
			"name": "Wyvern",
			"monster_type": "Wyvern",
			"level_mult": 1.6,
			"hp_mult": 2.0,
			"attack_mult": 1.5,
			"abilities": ["Diving Strike", "Poison Tail", "Screech"]
		},
		"boss_egg": "Wyvern",
		"floors": 3,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"treasures_per_floor": 1,
		"egg_drops": ["Harpy", "Gargoyle"],
		"material_drops": ["iron_ore", "steel_ore", "wyvern_scale"],
		"cooldown_hours": 14,
		"spawn_weight": 25,
		"color": "#4682B4"
	},
	# ===== TIER 4 DUNGEONS (Level 31-55) =====
	"giant_keep": {
		"name": "Giant's Keep",
		"description": "A crumbling fortress claimed by a towering Giant.",
		"tier": 4,
		"min_level": 31,
		"max_level": 55,
		"monster_pool": ["Ogre", "Troll", "Minotaur"],
		"boss": {
			"name": "Giant",
			"monster_type": "Giant",
			"level_mult": 1.7,
			"hp_mult": 3.0,
			"attack_mult": 1.6,
			"abilities": ["Ground Slam", "Mighty Throw", "Intimidate"]
		},
		"boss_egg": "Giant",
		"floors": 4,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Ogre", "Minotaur"],
		"material_drops": ["iron_ore", "steel_ore", "giant_bone"],
		"cooldown_hours": 18,
		"spawn_weight": 22,
		"color": "#8B4513"
	},
	"vampire_crypt": {
		"name": "Vampire's Crypt",
		"description": "An ancient tomb where a Vampire lord slumbers and feeds.",
		"tier": 4,
		"min_level": 35,
		"max_level": 60,
		"monster_pool": ["Skeleton", "Zombie", "Wight", "Wraith"],
		"boss": {
			"name": "Vampire",
			"monster_type": "Vampire",
			"level_mult": 1.8,
			"hp_mult": 2.5,
			"attack_mult": 1.7,
			"abilities": ["Life Drain", "Charm", "Bat Swarm"]
		},
		"boss_egg": "Vampire",
		"floors": 4,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"treasures_per_floor": 2,
		"egg_drops": ["Wight", "Wraith"],
		"material_drops": ["steel_ore", "mithril_ore", "vampire_fang"],
		"cooldown_hours": 20,
		"spawn_weight": 20,
		"color": "#8B0000"
	},
	# ===== TIER 5 DUNGEONS (Level 51-100) =====
	"lich_sanctum": {
		"name": "Lich's Sanctum",
		"description": "A hidden sanctuary where an undead sorcerer performs dark rituals.",
		"tier": 5,
		"min_level": 51,
		"max_level": 100,
		"monster_pool": ["Skeleton", "Wraith", "Wight", "Zombie"],
		"boss": {
			"name": "Lich",
			"monster_type": "Lich",
			"level_mult": 1.9,
			"hp_mult": 3.0,
			"attack_mult": 1.8,
			"abilities": ["Life Drain", "Bone Storm", "Raise Dead", "Soul Freeze"]
		},
		"boss_egg": "Lich",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Wraith", "Wight"],
		"material_drops": ["mithril_ore", "soul_shard", "phylactery_fragment"],
		"cooldown_hours": 24,
		"spawn_weight": 18,
		"color": "#483D8B"
	},
	"cerberus_pit": {
		"name": "Cerberus's Pit",
		"description": "A volcanic hellmouth guarded by the three-headed beast Cerberus.",
		"tier": 5,
		"min_level": 60,
		"max_level": 110,
		"monster_pool": ["Demon", "Hellhound", "Fire Elemental"],
		"boss": {
			"name": "Cerberus",
			"monster_type": "Cerberus",
			"level_mult": 2.0,
			"hp_mult": 4.0,
			"attack_mult": 1.9,
			"abilities": ["Triple Bite", "Hellfire Breath", "Ferocious Howl"]
		},
		"boss_egg": "Cerberus",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Demon"],
		"material_drops": ["mithril_ore", "adamantine_ore", "hellhound_fang"],
		"cooldown_hours": 28,
		"spawn_weight": 15,
		"color": "#FF4500"
	},
	"balrog_depths": {
		"name": "Balrog's Depths",
		"description": "The deepest mines where an ancient Balrog was awakened.",
		"tier": 5,
		"min_level": 70,
		"max_level": 120,
		"monster_pool": ["Demon", "Fire Elemental", "Succubus"],
		"boss": {
			"name": "Balrog",
			"monster_type": "Balrog",
			"level_mult": 2.1,
			"hp_mult": 4.5,
			"attack_mult": 2.0,
			"abilities": ["Flame Whip", "Shadow Wings", "Demonic Roar"]
		},
		"boss_egg": "Balrog",
		"floors": 5,
		"grid_size": 7,
		"encounters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Demon", "Succubus"],
		"material_drops": ["adamantine_ore", "demon_heart", "balrog_essence"],
		"cooldown_hours": 32,
		"spawn_weight": 12,
		"color": "#DC143C"
	},
	# ===== TIER 6 DUNGEONS (Level 101-500) =====
	"ancient_dragon_lair": {
		"name": "Ancient Dragon's Lair",
		"description": "A volcanic cavern ruled by an Ancient Dragon of immense power.",
		"tier": 6,
		"min_level": 101,
		"max_level": 300,
		"monster_pool": ["Dragon Wyrmling", "Demon", "Elemental"],
		"boss": {
			"name": "Ancient Dragon",
			"monster_type": "Ancient Dragon",
			"level_mult": 2.2,
			"hp_mult": 5.0,
			"attack_mult": 2.1,
			"abilities": ["Fire Breath", "Wing Buffet", "Terrifying Roar", "Ancient Fury"]
		},
		"boss_egg": "Ancient Dragon",
		"floors": 5,
		"grid_size": 7,
		"encounters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Dragon Wyrmling"],
		"material_drops": ["adamantine_ore", "dragonhide", "dragon_blood", "ancient_scale"],
		"cooldown_hours": 36,
		"spawn_weight": 10,
		"color": "#FF6347"
	},
	"hydra_swamp": {
		"name": "Hydra's Swamp",
		"description": "A poisonous bog where a regenerating Hydra lurks.",
		"tier": 6,
		"min_level": 150,
		"max_level": 400,
		"monster_pool": ["Giant Spider", "Siren", "Kelpie"],
		"boss": {
			"name": "Hydra",
			"monster_type": "Hydra",
			"level_mult": 2.3,
			"hp_mult": 6.0,
			"attack_mult": 1.8,
			"abilities": ["Multi-Head Strike", "Regeneration", "Poison Spray", "Head Regrowth"]
		},
		"boss_egg": "Hydra",
		"floors": 6,
		"grid_size": 7,
		"encounters_per_floor": 6,
		"treasures_per_floor": 2,
		"egg_drops": ["Giant Spider", "Siren"],
		"material_drops": ["orichalcum_ore", "hydra_blood", "regenerating_tissue"],
		"cooldown_hours": 40,
		"spawn_weight": 8,
		"color": "#2E8B57"
	},
	"phoenix_nest": {
		"name": "Phoenix's Nest",
		"description": "A sacred mountain peak where a Phoenix guards its eternal flame.",
		"tier": 6,
		"min_level": 200,
		"max_level": 500,
		"monster_pool": ["Elemental", "Gryphon", "Harpy"],
		"boss": {
			"name": "Phoenix",
			"monster_type": "Phoenix",
			"level_mult": 2.4,
			"hp_mult": 4.0,
			"attack_mult": 2.2,
			"abilities": ["Rebirth", "Solar Flare", "Ash Storm", "Purifying Flame"]
		},
		"boss_egg": "Phoenix",
		"floors": 6,
		"grid_size": 7,
		"encounters_per_floor": 6,
		"treasures_per_floor": 3,
		"egg_drops": ["Gryphon", "Elemental"],
		"material_drops": ["orichalcum_ore", "phoenix_feather", "eternal_ember"],
		"cooldown_hours": 44,
		"spawn_weight": 7,
		"color": "#FFD700"
	},
	# ===== TIER 7 DUNGEONS (Level 501-2000) =====
	"void_walker_rift": {
		"name": "Void Walker's Rift",
		"description": "A tear in reality where a Void Walker steps between dimensions.",
		"tier": 7,
		"min_level": 501,
		"max_level": 1200,
		"monster_pool": ["Elemental", "Nazgul", "Wraith"],
		"boss": {
			"name": "Void Walker",
			"monster_type": "Void Walker",
			"level_mult": 2.5,
			"hp_mult": 6.0,
			"attack_mult": 2.4,
			"abilities": ["Phase Shift", "Void Bolt", "Reality Tear", "Dimensional Prison"]
		},
		"boss_egg": "Void Walker",
		"floors": 6,
		"grid_size": 8,
		"encounters_per_floor": 6,
		"treasures_per_floor": 3,
		"egg_drops": ["Nazgul"],
		"material_drops": ["orichalcum_ore", "void_essence", "reality_shard"],
		"cooldown_hours": 48,
		"spawn_weight": 6,
		"color": "#4B0082"
	},
	"primordial_dragon_domain": {
		"name": "Primordial Dragon's Domain",
		"description": "An ancient realm ruled by a dragon from the dawn of time.",
		"tier": 7,
		"min_level": 800,
		"max_level": 2000,
		"monster_pool": ["Ancient Dragon", "Dragon Wyrmling", "Elemental"],
		"boss": {
			"name": "Primordial Dragon",
			"monster_type": "Primordial Dragon",
			"level_mult": 2.7,
			"hp_mult": 7.0,
			"attack_mult": 2.6,
			"abilities": ["Primordial Breath", "Time Warp", "Cataclysm", "World Shaker"]
		},
		"boss_egg": "Primordial Dragon",
		"floors": 7,
		"grid_size": 8,
		"encounters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Ancient Dragon"],
		"material_drops": ["void_ore", "primordial_scale", "time_crystal"],
		"cooldown_hours": 56,
		"spawn_weight": 4,
		"color": "#9400D3"
	},
	# ===== TIER 8 DUNGEONS (Level 2001-5000) =====
	"cosmic_horror_realm": {
		"name": "Cosmic Horror's Realm",
		"description": "A nightmare dimension where sanity frays and a Cosmic Horror dwells.",
		"tier": 8,
		"min_level": 2001,
		"max_level": 5000,
		"monster_pool": ["Void Walker", "Elder Lich", "Time Weaver"],
		"boss": {
			"name": "Cosmic Horror",
			"monster_type": "Cosmic Horror",
			"level_mult": 3.0,
			"hp_mult": 8.0,
			"attack_mult": 2.8,
			"abilities": ["Madness Gaze", "Tentacle Storm", "Reality Warp", "Void Consumption"]
		},
		"boss_egg": "Cosmic Horror",
		"floors": 7,
		"grid_size": 8,
		"encounters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Void Walker", "Elder Lich"],
		"material_drops": ["void_ore", "celestial_ore", "cosmic_fragment", "sanity_shard"],
		"cooldown_hours": 72,
		"spawn_weight": 3,
		"color": "#191970"
	},
	# ===== TIER 9 DUNGEONS (Level 5001+) =====
	"chaos_sanctum": {
		"name": "Avatar of Chaos's Sanctum",
		"description": "The heart of entropy itself, where the Avatar of Chaos reigns supreme.",
		"tier": 9,
		"min_level": 5001,
		"max_level": 10000,
		"monster_pool": ["Cosmic Horror", "Death Incarnate", "Time Weaver"],
		"boss": {
			"name": "Avatar of Chaos",
			"monster_type": "Avatar of Chaos",
			"level_mult": 3.5,
			"hp_mult": 10.0,
			"attack_mult": 3.0,
			"abilities": ["Chaos Storm", "Reality Shatter", "Entropy Wave", "Ultimate Destruction"]
		},
		"boss_egg": "Avatar of Chaos",
		"floors": 8,
		"grid_size": 9,
		"encounters_per_floor": 8,
		"treasures_per_floor": 4,
		"egg_drops": ["Cosmic Horror", "Death Incarnate"],
		"material_drops": ["celestial_ore", "chaos_essence", "primordial_spark", "god_fragment"],
		"cooldown_hours": 96,
		"spawn_weight": 1,
		"color": "#800080"
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

# Egg drop chances from treasure chests by monster tier (higher tier = rarer)
const TREASURE_EGG_CHANCE_BY_TIER = {
	1: 20,   # 20% for tier 1 monsters
	2: 18,   # 18% for tier 2
	3: 15,   # 15% for tier 3
	4: 12,   # 12% for tier 4
	5: 10,   # 10% for tier 5
	6: 7,    # 7% for tier 6
	7: 5,    # 5% for tier 7
	8: 3,    # 3% for tier 8
	9: 1     # 1% for tier 9 (extremely rare!)
}

static func roll_treasure(dungeon_id: String, floor_num: int) -> Dictionary:
	"""Roll for treasure chest contents. Eggs use tier-based rarity."""
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

	# Roll for egg using tier-based rarity (higher tier = lower chance)
	var egg = {}
	var egg_drops = dungeon.get("egg_drops", [])
	if not egg_drops.is_empty():
		# Use tier-based drop chance instead of dungeon's egg_drop_chance
		var egg_chance = TREASURE_EGG_CHANCE_BY_TIER.get(tier, 10)
		if randi() % 100 < egg_chance:
			var egg_monster = egg_drops[randi() % egg_drops.size()]
			egg = {"monster": egg_monster}

	return {
		"gold": gold,
		"materials": materials,
		"egg": egg
	}

static func calculate_completion_rewards(dungeon_id: String, floors_cleared: int) -> Dictionary:
	"""Calculate rewards for completing a dungeon. Includes GUARANTEED boss egg!"""
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

	# Get guaranteed boss egg (dungeon completion ALWAYS gives the boss's egg)
	var boss_egg = dungeon.get("boss_egg", "")

	return {
		"xp": int(base_xp),
		"gold": int(base_gold),
		"floors_cleared": floors_cleared,
		"total_floors": total_floors,
		"full_clear": floors_cleared >= total_floors,
		"boss_egg": boss_egg  # GUARANTEED egg from the boss monster
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
