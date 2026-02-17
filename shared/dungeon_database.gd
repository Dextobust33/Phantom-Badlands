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
	CLEARED,     # Cleared encounter (was ENCOUNTER or TREASURE)
	RESOURCE     # Gathering node (ore/herb/crystal)
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
	TileType.CLEARED: "·",
	TileType.RESOURCE: "&"
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
	TileType.CLEARED: "#303030",
	TileType.RESOURCE: "#00FFCC"
}

# Sub-tier level ranges per overarching tier (1-9)
# Each tier spans a level range; sub-tiers (1-8) subdivide that range
const TIER_LEVEL_RANGES = {
	1: {"min": 1, "max": 12},
	2: {"min": 6, "max": 22},
	3: {"min": 16, "max": 40},
	4: {"min": 31, "max": 60},
	5: {"min": 51, "max": 120},
	6: {"min": 101, "max": 500},
	7: {"min": 501, "max": 2000},
	8: {"min": 2001, "max": 5000},
	9: {"min": 5001, "max": 10000}
}

# ===== STEP PRESSURE SYSTEM =====
# Steps allowed per floor before collapse. Boss floors get +50%.
const DUNGEON_STEP_LIMITS = {1: 100, 2: 95, 3: 90, 4: 85, 5: 80, 6: 75, 7: 70, 8: 65, 9: 60}

# Number of hidden traps per floor by tier
const TRAPS_PER_FLOOR = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3, 7: 4, 8: 4, 9: 4}
const TRAP_TYPES = ["rust", "thief", "teleport"]
const TRAP_WEIGHTS = {"rust": 40, "thief": 30, "teleport": 30}

static func get_step_limit(tier: int, is_boss_floor: bool) -> int:
	"""Get step limit for a dungeon floor based on tier. Boss floors get +50%."""
	var base = DUNGEON_STEP_LIMITS.get(tier, 400)
	if is_boss_floor:
		base = int(base * 1.5)
	return base

static func generate_traps(grid: Array, floor_num: int, tier: int, rng: RandomNumberGenerator) -> Array:
	"""Generate hidden trap positions on a floor. Returns array of {x, y, type}."""
	var count = TRAPS_PER_FLOOR.get(tier, 2)
	var traps = []
	var occupied = {}

	# Build list of valid EMPTY tiles (not in treasure rooms, not entrance/exit)
	var candidates = []
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			var t = grid[y][x]
			if t == TileType.EMPTY:
				candidates.append(Vector2i(x, y))

	# Weighted random selection of trap types
	var total_weight = 0
	for w in TRAP_WEIGHTS.values():
		total_weight += w

	for _i in range(count):
		if candidates.is_empty():
			break
		var idx = rng.randi_range(0, candidates.size() - 1)
		var pos = candidates[idx]
		candidates.remove_at(idx)

		# Pick trap type by weight
		var roll = rng.randi_range(0, total_weight - 1)
		var trap_type = "rust"
		var cumulative = 0
		for tt in TRAP_TYPES:
			cumulative += TRAP_WEIGHTS[tt]
			if roll < cumulative:
				trap_type = tt
				break

		traps.append({"x": pos.x, "y": pos.y, "type": trap_type, "triggered": false})

	return traps

# ===== DUNGEON DEFINITIONS =====
# Dungeons are now named after their boss monster. Defeating the boss GUARANTEES
# that monster's companion egg. Additional eggs can drop from treasure chests
# with chances based on monster tier (higher tier = rarer drops).
const DUNGEON_TYPES = {
	# ===== TIER 1 DUNGEONS (Level 1-10) =====
	"goblin_caves": {
		"name": "Goblin Caves",
		"description": "A network of crude tunnels where goblins have established a small colony.",
		"tier": 1,
		"min_level": 1,
		"max_level": 10,
		"monster_pool": ["Goblin", "Giant Rat", "Kobold"],
		"boss": {
			"name": "Goblin King",
			"monster_type": "Goblin",
			"level_mult": 1.1,
			"hp_mult": 2.0,
			"attack_mult": 1.3,
			"abilities": ["Rally Minions", "Dirty Fighting"]
		},
		"boss_egg": "Goblin",
		"floors": 3,
		"grid_size": 4,
		"encounters_per_floor": 2,
		"monsters_per_floor": 3,
		"treasures_per_floor": 1,
		"egg_drops": ["Goblin", "Kobold"],
		"material_drops": ["pine_log", "copper_ore"],
		"cooldown_hours": 4,
		"spawn_weight": 50,
		"color": "#32CD32"
	},
	"wolf_den": {
		"name": "Wolf Den",
		"description": "A cavern where a pack of wolves has made their home, led by a massive alpha.",
		"tier": 1,
		"min_level": 3,
		"max_level": 12,
		"monster_pool": ["Wolf", "Giant Rat"],
		"boss": {
			"name": "Alpha Wolf",
			"monster_type": "Wolf",
			"level_mult": 1.1,
			"hp_mult": 2.0,
			"attack_mult": 1.4,
			"abilities": ["Pack Howl", "Savage Bite"]
		},
		"boss_egg": "Wolf",
		"floors": 3,
		"grid_size": 4,
		"encounters_per_floor": 2,
		"monsters_per_floor": 3,
		"treasures_per_floor": 1,
		"egg_drops": ["Wolf"],
		"material_drops": ["ragged_leather", "pine_log"],
		"cooldown_hours": 4,
		"spawn_weight": 50,
		"color": "#708090"
	},

	"rat_warrens": {
		"name": "Rat Warrens",
		"description": "A maze of filthy tunnels beneath old ruins, teeming with oversized rats.",
		"tier": 1,
		"min_level": 1,
		"max_level": 8,
		"monster_pool": ["Giant Rat", "Kobold"],
		"boss": {
			"name": "Rat King",
			"monster_type": "Giant Rat",
			"level_mult": 1.1,
			"hp_mult": 2.0,
			"attack_mult": 1.3,
			"abilities": ["Plague Bite", "Swarm Call"]
		},
		"boss_egg": "Giant Rat",
		"floors": 3,
		"grid_size": 4,
		"encounters_per_floor": 2,
		"monsters_per_floor": 3,
		"treasures_per_floor": 1,
		"egg_drops": ["Giant Rat"],
		"material_drops": ["ragged_leather", "pine_log"],
		"cooldown_hours": 4,
		"spawn_weight": 50,
		"color": "#8B7355"
	},
	"kobold_tunnels": {
		"name": "Kobold Tunnels",
		"description": "Cramped mining tunnels dug by a tribe of cunning kobolds.",
		"tier": 1,
		"min_level": 2,
		"max_level": 10,
		"monster_pool": ["Kobold", "Giant Rat"],
		"boss": {
			"name": "Kobold Chieftain",
			"monster_type": "Kobold",
			"level_mult": 1.1,
			"hp_mult": 2.0,
			"attack_mult": 1.3,
			"abilities": ["Trap Master", "Rallying Screech"]
		},
		"boss_egg": "Kobold",
		"floors": 3,
		"grid_size": 4,
		"encounters_per_floor": 2,
		"monsters_per_floor": 3,
		"treasures_per_floor": 1,
		"egg_drops": ["Kobold", "Giant Rat"],
		"material_drops": ["copper_ore", "pine_log"],
		"cooldown_hours": 4,
		"spawn_weight": 50,
		"color": "#CD853F"
	},
	"forgotten_crypt": {
		"name": "Forgotten Crypt",
		"description": "An ancient burial ground where skeletons rise to guard forgotten treasures.",
		"tier": 1,
		"min_level": 3,
		"max_level": 12,
		"monster_pool": ["Skeleton", "Giant Rat"],
		"boss": {
			"name": "Skeleton Lord",
			"monster_type": "Skeleton",
			"level_mult": 1.1,
			"hp_mult": 2.0,
			"attack_mult": 1.4,
			"abilities": ["Bone Shield", "Rattling Strike"]
		},
		"boss_egg": "Skeleton",
		"floors": 3,
		"grid_size": 4,
		"encounters_per_floor": 2,
		"monsters_per_floor": 3,
		"treasures_per_floor": 1,
		"egg_drops": ["Skeleton"],
		"material_drops": ["copper_ore", "ragged_leather"],
		"cooldown_hours": 4,
		"spawn_weight": 50,
		"color": "#C0C0C0"
	},

	# ===== TIER 2 DUNGEONS (Level 6-20) =====
	"orc_stronghold": {
		"name": "Orc Stronghold",
		"description": "A fortified camp where orcs prepare for raids on nearby settlements.",
		"tier": 2,
		"min_level": 6,
		"max_level": 20,
		"monster_pool": ["Orc", "Hobgoblin", "Gnoll"],
		"boss": {
			"name": "Orc Warlord",
			"monster_type": "Orc",
			"level_mult": 1.1,
			"hp_mult": 2.2,
			"attack_mult": 1.4,
			"abilities": ["War Cry", "Brutal Slam"]
		},
		"boss_egg": "Orc",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Orc", "Hobgoblin"],
		"material_drops": ["iron_ore", "copper_ore", "ragged_leather"],
		"cooldown_hours": 6,
		"spawn_weight": 40,
		"color": "#8B4513"
	},
	"spider_nest": {
		"name": "Spider Nest",
		"description": "A web-covered cavern where a giant spider queen lairs with her brood.",
		"tier": 2,
		"min_level": 8,
		"max_level": 22,
		"monster_pool": ["Giant Spider", "Kobold"],
		"boss": {
			"name": "Spider Queen",
			"monster_type": "Giant Spider",
			"level_mult": 1.1,
			"hp_mult": 2.3,
			"attack_mult": 1.3,
			"abilities": ["Web Trap", "Venomous Bite"]
		},
		"boss_egg": "Giant Spider",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Giant Spider"],
		"material_drops": ["silk_thread", "venom_sac", "ragged_leather"],
		"cooldown_hours": 6,
		"spawn_weight": 40,
		"color": "#4B0082"
	},

	"hobgoblin_fortress": {
		"name": "Hobgoblin Fortress",
		"description": "A disciplined military outpost where hobgoblins drill for war.",
		"tier": 2,
		"min_level": 7,
		"max_level": 18,
		"monster_pool": ["Hobgoblin", "Goblin", "Orc"],
		"boss": {
			"name": "Hobgoblin Commander",
			"monster_type": "Hobgoblin",
			"level_mult": 1.1,
			"hp_mult": 2.2,
			"attack_mult": 1.4,
			"abilities": ["Shield Wall", "Tactical Strike"]
		},
		"boss_egg": "Hobgoblin",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Hobgoblin", "Goblin"],
		"material_drops": ["iron_ore", "ragged_leather"],
		"cooldown_hours": 6,
		"spawn_weight": 40,
		"color": "#556B2F"
	},
	"gnoll_den": {
		"name": "Gnoll Pack Den",
		"description": "A savage hunting camp where gnolls gather between raids.",
		"tier": 2,
		"min_level": 7,
		"max_level": 18,
		"monster_pool": ["Gnoll", "Wolf", "Hobgoblin"],
		"boss": {
			"name": "Gnoll Packmaster",
			"monster_type": "Gnoll",
			"level_mult": 1.1,
			"hp_mult": 2.2,
			"attack_mult": 1.4,
			"abilities": ["Pack Tactics", "Frenzied Bite"]
		},
		"boss_egg": "Gnoll",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Gnoll", "Wolf"],
		"material_drops": ["ragged_leather", "iron_ore"],
		"cooldown_hours": 6,
		"spawn_weight": 40,
		"color": "#8B6914"
	},
	"plagued_graveyard": {
		"name": "Plagued Graveyard",
		"description": "A cemetery overrun by shambling undead, spreading their corruption.",
		"tier": 2,
		"min_level": 8,
		"max_level": 20,
		"monster_pool": ["Zombie", "Skeleton"],
		"boss": {
			"name": "Plague Zombie",
			"monster_type": "Zombie",
			"level_mult": 1.1,
			"hp_mult": 2.3,
			"attack_mult": 1.3,
			"abilities": ["Plague Touch", "Shambling Charge"]
		},
		"boss_egg": "Zombie",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Zombie", "Skeleton"],
		"material_drops": ["copper_ore", "ragged_leather"],
		"cooldown_hours": 6,
		"spawn_weight": 40,
		"color": "#6B8E23"
	},
	"barrow_mounds": {
		"name": "Barrow Mounds",
		"description": "Ancient burial hills where wights guard treasures of a forgotten age.",
		"tier": 2,
		"min_level": 9,
		"max_level": 22,
		"monster_pool": ["Wight", "Skeleton", "Zombie"],
		"boss": {
			"name": "Barrow Wight",
			"monster_type": "Wight",
			"level_mult": 1.1,
			"hp_mult": 2.3,
			"attack_mult": 1.4,
			"abilities": ["Life Drain", "Grave Chill"]
		},
		"boss_egg": "Wight",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Wight", "Skeleton"],
		"material_drops": ["iron_ore", "copper_ore"],
		"cooldown_hours": 6,
		"spawn_weight": 40,
		"color": "#696969"
	},
	"siren_cove": {
		"name": "Siren's Cove",
		"description": "A coastal cave where enchanting voices lure sailors to their doom.",
		"tier": 2,
		"min_level": 8,
		"max_level": 20,
		"monster_pool": ["Siren", "Kelpie"],
		"boss": {
			"name": "Siren Enchantress",
			"monster_type": "Siren",
			"level_mult": 1.1,
			"hp_mult": 2.0,
			"attack_mult": 1.3,
			"abilities": ["Enchanting Song", "Tidal Surge"]
		},
		"boss_egg": "Siren",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Siren", "Kelpie"],
		"material_drops": ["copper_ore", "silk_thread"],
		"cooldown_hours": 6,
		"spawn_weight": 40,
		"color": "#00CED1"
	},
	"kelpie_marsh": {
		"name": "Kelpie Marsh",
		"description": "A waterlogged swamp where kelpies drag victims beneath the murky waters.",
		"tier": 2,
		"min_level": 8,
		"max_level": 20,
		"monster_pool": ["Kelpie", "Siren", "Giant Rat"],
		"boss": {
			"name": "Elder Kelpie",
			"monster_type": "Kelpie",
			"level_mult": 1.1,
			"hp_mult": 2.2,
			"attack_mult": 1.3,
			"abilities": ["Drowning Grasp", "Murky Veil"]
		},
		"boss_egg": "Kelpie",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Kelpie", "Siren"],
		"material_drops": ["silk_thread", "ragged_leather"],
		"cooldown_hours": 6,
		"spawn_weight": 40,
		"color": "#2F4F4F"
	},
	"mimic_treasury": {
		"name": "Mimic Treasury",
		"description": "An abandoned vault where nothing is as it seems and every chest bites back.",
		"tier": 2,
		"min_level": 10,
		"max_level": 22,
		"monster_pool": ["Mimic", "Kobold"],
		"boss": {
			"name": "Grand Mimic",
			"monster_type": "Mimic",
			"level_mult": 1.1,
			"hp_mult": 2.3,
			"attack_mult": 1.4,
			"abilities": ["Shapeshifter Strike", "Adhesive Trap"]
		},
		"boss_egg": "Mimic",
		"floors": 4,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 2,
		"egg_drops": ["Mimic"],
		"material_drops": ["iron_ore", "copper_ore", "silk_thread"],
		"cooldown_hours": 6,
		"spawn_weight": 35,
		"color": "#DAA520"
	},

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
			"level_mult": 1.15,
			"hp_mult": 2.5,
			"attack_mult": 1.4,
			"abilities": ["Regeneration", "Boulder Throw"]
		},
		"boss_egg": "Troll",  # GUARANTEED egg on completion
		"floors": 5,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
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
			"level_mult": 1.15,
			"hp_mult": 2.0,
			"attack_mult": 1.5,
			"abilities": ["Diving Strike", "Poison Tail", "Screech"]
		},
		"boss_egg": "Wyvern",
		"floors": 5,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Harpy", "Gargoyle"],
		"material_drops": ["iron_ore", "steel_ore", "wyvern_scale"],
		"cooldown_hours": 14,
		"spawn_weight": 25,
		"color": "#4682B4"
	},
	"ogre_bog": {
		"name": "Ogre Bog",
		"description": "A stinking swamp where a clan of ogres feast on anything that wanders in.",
		"tier": 3,
		"min_level": 16,
		"max_level": 32,
		"monster_pool": ["Ogre", "Goblin", "Gnoll"],
		"boss": {
			"name": "Ogre Chieftain",
			"monster_type": "Ogre",
			"level_mult": 1.15,
			"hp_mult": 2.5,
			"attack_mult": 1.5,
			"abilities": ["Crushing Blow", "Thick Hide"]
		},
		"boss_egg": "Ogre",
		"floors": 5,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Ogre", "Gnoll"],
		"material_drops": ["iron_ore", "ragged_leather", "copper_ore"],
		"cooldown_hours": 12,
		"spawn_weight": 30,
		"color": "#6B4226"
	},
	"wraith_barrow": {
		"name": "Wraith Barrow",
		"description": "A haunted tomb deep underground where restless spirits guard cursed relics.",
		"tier": 3,
		"min_level": 18,
		"max_level": 35,
		"monster_pool": ["Wraith", "Skeleton", "Wight"],
		"boss": {
			"name": "Wraith Overlord",
			"monster_type": "Wraith",
			"level_mult": 1.15,
			"hp_mult": 2.0,
			"attack_mult": 1.5,
			"abilities": ["Soul Drain", "Ethereal Phase", "Chilling Touch"]
		},
		"boss_egg": "Wraith",
		"floors": 5,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Wraith", "Wight"],
		"material_drops": ["iron_ore", "steel_ore", "copper_ore"],
		"cooldown_hours": 12,
		"spawn_weight": 28,
		"color": "#4A4A6A"
	},
	"minotaur_labyrinth": {
		"name": "Minotaur's Labyrinth",
		"description": "A twisting underground maze with a fearsome minotaur lurking at its heart.",
		"tier": 3,
		"min_level": 18,
		"max_level": 36,
		"monster_pool": ["Minotaur", "Ogre", "Gargoyle"],
		"boss": {
			"name": "Minotaur Champion",
			"monster_type": "Minotaur",
			"level_mult": 1.15,
			"hp_mult": 2.5,
			"attack_mult": 1.5,
			"abilities": ["Gore Charge", "Labyrinth Fury", "Mighty Stomp"]
		},
		"boss_egg": "Minotaur",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Minotaur", "Ogre"],
		"material_drops": ["iron_ore", "steel_ore", "ragged_leather"],
		"cooldown_hours": 14,
		"spawn_weight": 28,
		"color": "#A0522D"
	},
	"gargoyle_cathedral": {
		"name": "Gargoyle Cathedral",
		"description": "A crumbling cathedral where stone guardians come alive to protect ancient secrets.",
		"tier": 3,
		"min_level": 20,
		"max_level": 38,
		"monster_pool": ["Gargoyle", "Skeleton", "Wraith"],
		"boss": {
			"name": "Gargoyle Sentinel",
			"monster_type": "Gargoyle",
			"level_mult": 1.15,
			"hp_mult": 2.5,
			"attack_mult": 1.4,
			"abilities": ["Stone Skin", "Swooping Strike", "Petrifying Gaze"]
		},
		"boss_egg": "Gargoyle",
		"floors": 5,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Gargoyle", "Skeleton"],
		"material_drops": ["iron_ore", "steel_ore"],
		"cooldown_hours": 14,
		"spawn_weight": 25,
		"color": "#778899"
	},
	"harpy_cliffs": {
		"name": "Harpy Cliffs",
		"description": "Wind-swept coastal cliffs where a flock of harpies nest and hunt.",
		"tier": 3,
		"min_level": 17,
		"max_level": 34,
		"monster_pool": ["Harpy", "Kobold", "Giant Rat"],
		"boss": {
			"name": "Harpy Matriarch",
			"monster_type": "Harpy",
			"level_mult": 1.15,
			"hp_mult": 2.0,
			"attack_mult": 1.5,
			"abilities": ["Shrieking Blast", "Talon Dive", "Wind Gust"]
		},
		"boss_egg": "Harpy",
		"floors": 5,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Harpy"],
		"material_drops": ["iron_ore", "ragged_leather", "silk_thread"],
		"cooldown_hours": 12,
		"spawn_weight": 28,
		"color": "#9370DB"
	},
	"shrieker_caverns": {
		"name": "Shrieker Caverns",
		"description": "Echo-filled caves where monstrous fungi emit deafening shrieks.",
		"tier": 3,
		"min_level": 19,
		"max_level": 36,
		"monster_pool": ["Shrieker", "Giant Spider", "Kobold"],
		"boss": {
			"name": "Shrieker Titan",
			"monster_type": "Shrieker",
			"level_mult": 1.15,
			"hp_mult": 2.5,
			"attack_mult": 1.4,
			"abilities": ["Deafening Shriek", "Spore Cloud", "Root Grasp"]
		},
		"boss_egg": "Shrieker",
		"floors": 5,
		"grid_size": 5,
		"encounters_per_floor": 3,
		"monsters_per_floor": 4,
		"treasures_per_floor": 1,
		"egg_drops": ["Shrieker", "Giant Spider"],
		"material_drops": ["copper_ore", "iron_ore", "silk_thread"],
		"cooldown_hours": 12,
		"spawn_weight": 26,
		"color": "#3CB371"
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
			"level_mult": 1.2,
			"hp_mult": 3.0,
			"attack_mult": 1.6,
			"abilities": ["Ground Slam", "Mighty Throw", "Intimidate"]
		},
		"boss_egg": "Giant",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"monsters_per_floor": 5,
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
			"level_mult": 1.2,
			"hp_mult": 2.5,
			"attack_mult": 1.7,
			"abilities": ["Life Drain", "Charm", "Bat Swarm"]
		},
		"boss_egg": "Vampire",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"monsters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Wight", "Wraith"],
		"material_drops": ["steel_ore", "mithril_ore", "vampire_fang"],
		"cooldown_hours": 20,
		"spawn_weight": 20,
		"color": "#8B0000"
	},
	"dragon_hatchery": {
		"name": "Dragon Hatchery",
		"description": "A volcanic cave where dragon eggs incubate and wyrmlings fiercely guard their nest.",
		"tier": 4,
		"min_level": 32,
		"max_level": 55,
		"monster_pool": ["Dragon Wyrmling", "Kobold", "Wyvern"],
		"boss": {
			"name": "Broodmother Wyrmling",
			"monster_type": "Dragon Wyrmling",
			"level_mult": 1.2,
			"hp_mult": 2.8,
			"attack_mult": 1.6,
			"abilities": ["Fire Breath", "Wing Slash", "Hatchling Fury"]
		},
		"boss_egg": "Dragon Wyrmling",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"monsters_per_floor": 5,
		"treasures_per_floor": 1,
		"egg_drops": ["Dragon Wyrmling", "Wyvern"],
		"material_drops": ["steel_ore", "iron_ore", "wyvern_scale"],
		"cooldown_hours": 18,
		"spawn_weight": 22,
		"color": "#FF8C00"
	},
	"demon_gate": {
		"name": "Demon Gate",
		"description": "A rift to the infernal planes where demons pour through to wreak havoc.",
		"tier": 4,
		"min_level": 35,
		"max_level": 58,
		"monster_pool": ["Demon", "Hobgoblin", "Orc"],
		"boss": {
			"name": "Demon Overlord",
			"monster_type": "Demon",
			"level_mult": 1.2,
			"hp_mult": 2.8,
			"attack_mult": 1.7,
			"abilities": ["Hellfire", "Demonic Roar", "Shadow Strike"]
		},
		"boss_egg": "Demon",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"monsters_per_floor": 5,
		"treasures_per_floor": 1,
		"egg_drops": ["Demon"],
		"material_drops": ["steel_ore", "mithril_ore", "iron_ore"],
		"cooldown_hours": 20,
		"spawn_weight": 20,
		"color": "#B22222"
	},
	"gryphon_aerie": {
		"name": "Gryphon Aerie",
		"description": "A mountain fortress where gryphons roost and fiercely defend their territory.",
		"tier": 4,
		"min_level": 33,
		"max_level": 56,
		"monster_pool": ["Gryphon", "Harpy", "Wyvern"],
		"boss": {
			"name": "Gryphon Alpha",
			"monster_type": "Gryphon",
			"level_mult": 1.2,
			"hp_mult": 2.5,
			"attack_mult": 1.6,
			"abilities": ["Diving Talon", "Majestic Roar", "Wind Shear"]
		},
		"boss_egg": "Gryphon",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"monsters_per_floor": 5,
		"treasures_per_floor": 1,
		"egg_drops": ["Gryphon", "Harpy"],
		"material_drops": ["steel_ore", "iron_ore", "ragged_leather"],
		"cooldown_hours": 18,
		"spawn_weight": 22,
		"color": "#B8860B"
	},
	"chimaera_gorge": {
		"name": "Chimaera's Gorge",
		"description": "A twisting canyon where a monstrous chimaera terrorizes all who enter.",
		"tier": 4,
		"min_level": 36,
		"max_level": 58,
		"monster_pool": ["Chimaera", "Wyvern", "Gargoyle"],
		"boss": {
			"name": "Elder Chimaera",
			"monster_type": "Chimaera",
			"level_mult": 1.2,
			"hp_mult": 3.0,
			"attack_mult": 1.7,
			"abilities": ["Triple Maw", "Venomous Tail", "Fire Breath"]
		},
		"boss_egg": "Chimaera",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"monsters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Chimaera", "Wyvern"],
		"material_drops": ["steel_ore", "mithril_ore", "wyvern_scale"],
		"cooldown_hours": 20,
		"spawn_weight": 20,
		"color": "#8B008B"
	},
	"succubus_parlor": {
		"name": "Succubus Parlor",
		"description": "A cursed palace of temptation and illusion where a succubus holds court.",
		"tier": 4,
		"min_level": 38,
		"max_level": 60,
		"monster_pool": ["Succubus", "Demon", "Siren"],
		"boss": {
			"name": "Succubus Queen",
			"monster_type": "Succubus",
			"level_mult": 1.2,
			"hp_mult": 2.5,
			"attack_mult": 1.7,
			"abilities": ["Seduction", "Life Drain", "Dark Charm"]
		},
		"boss_egg": "Succubus",
		"floors": 5,
		"grid_size": 6,
		"encounters_per_floor": 4,
		"monsters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Succubus", "Siren"],
		"material_drops": ["mithril_ore", "steel_ore", "silk_thread"],
		"cooldown_hours": 20,
		"spawn_weight": 18,
		"color": "#FF69B4"
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
			"level_mult": 1.2,
			"hp_mult": 3.0,
			"attack_mult": 1.8,
			"abilities": ["Life Drain", "Bone Storm", "Raise Dead", "Soul Freeze"]
		},
		"boss_egg": "Lich",
		"floors": 6,
		"grid_size": 6,
		"encounters_per_floor": 5,
		"monsters_per_floor": 5,
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
			"level_mult": 1.2,
			"hp_mult": 4.0,
			"attack_mult": 1.9,
			"abilities": ["Triple Bite", "Hellfire Breath", "Ferocious Howl"]
		},
		"boss_egg": "Cerberus",
		"floors": 6,
		"grid_size": 6,
		"encounters_per_floor": 5,
		"monsters_per_floor": 5,
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
			"level_mult": 1.2,
			"hp_mult": 4.5,
			"attack_mult": 2.0,
			"abilities": ["Flame Whip", "Shadow Wings", "Demonic Roar"]
		},
		"boss_egg": "Balrog",
		"floors": 6,
		"grid_size": 7,
		"encounters_per_floor": 5,
		"monsters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Demon", "Succubus"],
		"material_drops": ["adamantine_ore", "demon_heart", "balrog_essence"],
		"cooldown_hours": 32,
		"spawn_weight": 12,
		"color": "#DC143C"
	},
	"demon_lord_throne": {
		"name": "Demon Lord's Throne",
		"description": "The seat of infernal power where a Demon Lord commands legions of the damned.",
		"tier": 5,
		"min_level": 55,
		"max_level": 100,
		"monster_pool": ["Demon", "Succubus", "Balrog"],
		"boss": {
			"name": "Demon Lord",
			"monster_type": "Demon Lord",
			"level_mult": 1.2,
			"hp_mult": 3.5,
			"attack_mult": 1.9,
			"abilities": ["Infernal Command", "Hellfire Storm", "Soul Rend", "Dark Pact"]
		},
		"boss_egg": "Demon Lord",
		"floors": 6,
		"grid_size": 6,
		"encounters_per_floor": 5,
		"monsters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Demon", "Succubus"],
		"material_drops": ["mithril_ore", "adamantine_ore", "demon_heart"],
		"cooldown_hours": 26,
		"spawn_weight": 15,
		"color": "#660000"
	},
	"titan_colosseum": {
		"name": "Titan's Colosseum",
		"description": "An ancient arena where a Titan still battles, shaking the earth with every blow.",
		"tier": 5,
		"min_level": 60,
		"max_level": 110,
		"monster_pool": ["Giant", "Minotaur", "Ogre"],
		"boss": {
			"name": "Titan",
			"monster_type": "Titan",
			"level_mult": 1.2,
			"hp_mult": 4.0,
			"attack_mult": 2.0,
			"abilities": ["Earthquake", "Titan's Grip", "Colossal Swing", "Unyielding"]
		},
		"boss_egg": "Titan",
		"floors": 6,
		"grid_size": 7,
		"encounters_per_floor": 5,
		"monsters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Giant", "Minotaur"],
		"material_drops": ["adamantine_ore", "mithril_ore", "giant_bone"],
		"cooldown_hours": 30,
		"spawn_weight": 14,
		"color": "#CD7F32"
	},
	"jabberwock_thicket": {
		"name": "Jabberwock's Thicket",
		"description": "A twisted dark forest where reality bends and a Jabberwock hunts.",
		"tier": 5,
		"min_level": 65,
		"max_level": 115,
		"monster_pool": ["Troll", "Wyvern", "Shrieker"],
		"boss": {
			"name": "Jabberwock",
			"monster_type": "Jabberwock",
			"level_mult": 1.2,
			"hp_mult": 3.5,
			"attack_mult": 1.9,
			"abilities": ["Vorpal Jaws", "Whiffling Wings", "Burbling Cry", "Eyes of Flame"]
		},
		"boss_egg": "Jabberwock",
		"floors": 6,
		"grid_size": 6,
		"encounters_per_floor": 5,
		"monsters_per_floor": 5,
		"treasures_per_floor": 2,
		"egg_drops": ["Troll", "Wyvern"],
		"material_drops": ["adamantine_ore", "mithril_ore", "wyvern_scale"],
		"cooldown_hours": 28,
		"spawn_weight": 14,
		"color": "#006400"
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
			"level_mult": 1.25,
			"hp_mult": 5.0,
			"attack_mult": 2.1,
			"abilities": ["Fire Breath", "Wing Buffet", "Terrifying Roar", "Ancient Fury"]
		},
		"boss_egg": "Ancient Dragon",
		"floors": 7,
		"grid_size": 7,
		"encounters_per_floor": 5,
		"monsters_per_floor": 6,
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
			"level_mult": 1.25,
			"hp_mult": 6.0,
			"attack_mult": 1.8,
			"abilities": ["Multi-Head Strike", "Regeneration", "Poison Spray", "Head Regrowth"]
		},
		"boss_egg": "Hydra",
		"floors": 7,
		"grid_size": 7,
		"encounters_per_floor": 6,
		"monsters_per_floor": 6,
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
			"level_mult": 1.25,
			"hp_mult": 4.0,
			"attack_mult": 2.2,
			"abilities": ["Rebirth", "Solar Flare", "Ash Storm", "Purifying Flame"]
		},
		"boss_egg": "Phoenix",
		"floors": 7,
		"grid_size": 7,
		"encounters_per_floor": 6,
		"monsters_per_floor": 6,
		"treasures_per_floor": 3,
		"egg_drops": ["Gryphon", "Elemental"],
		"material_drops": ["orichalcum_ore", "phoenix_feather", "eternal_ember"],
		"cooldown_hours": 44,
		"spawn_weight": 7,
		"color": "#FFD700"
	},
	"elemental_nexus": {
		"name": "Elemental Nexus",
		"description": "A convergence of elemental planes where raw forces of nature clash.",
		"tier": 6,
		"min_level": 120,
		"max_level": 350,
		"monster_pool": ["Elemental", "Phoenix", "Iron Golem"],
		"boss": {
			"name": "Primeval Elemental",
			"monster_type": "Elemental",
			"level_mult": 1.25,
			"hp_mult": 5.0,
			"attack_mult": 2.0,
			"abilities": ["Elemental Storm", "Planar Shift", "Absorb Element", "Unstable Core"]
		},
		"boss_egg": "Elemental",
		"floors": 7,
		"grid_size": 7,
		"encounters_per_floor": 5,
		"monsters_per_floor": 6,
		"treasures_per_floor": 2,
		"egg_drops": ["Elemental"],
		"material_drops": ["orichalcum_ore", "adamantine_ore", "eternal_ember"],
		"cooldown_hours": 38,
		"spawn_weight": 9,
		"color": "#00BFFF"
	},
	"golem_foundry": {
		"name": "Golem Foundry",
		"description": "An ancient dwarven forge where iron golems continue their endless work.",
		"tier": 6,
		"min_level": 130,
		"max_level": 400,
		"monster_pool": ["Iron Golem", "Elemental", "Gargoyle"],
		"boss": {
			"name": "Iron Golem Overlord",
			"monster_type": "Iron Golem",
			"level_mult": 1.25,
			"hp_mult": 6.0,
			"attack_mult": 2.0,
			"abilities": ["Iron Fist", "Forge Heat", "Magnetic Pull", "Impervious Shell"]
		},
		"boss_egg": "Iron Golem",
		"floors": 7,
		"grid_size": 7,
		"encounters_per_floor": 6,
		"monsters_per_floor": 6,
		"treasures_per_floor": 2,
		"egg_drops": ["Iron Golem", "Elemental"],
		"material_drops": ["orichalcum_ore", "adamantine_ore", "steel_ore"],
		"cooldown_hours": 40,
		"spawn_weight": 8,
		"color": "#A9A9A9"
	},
	"sphinx_riddle_hall": {
		"name": "Sphinx's Riddle Hall",
		"description": "A desert temple where a Sphinx poses deadly riddles to all who seek passage.",
		"tier": 6,
		"min_level": 150,
		"max_level": 450,
		"monster_pool": ["Sphinx", "Gargoyle", "Mimic"],
		"boss": {
			"name": "Ancient Sphinx",
			"monster_type": "Sphinx",
			"level_mult": 1.25,
			"hp_mult": 5.0,
			"attack_mult": 2.1,
			"abilities": ["Riddle of Death", "Sphinx's Pounce", "Mind Shatter", "Desert Wind"]
		},
		"boss_egg": "Sphinx",
		"floors": 7,
		"grid_size": 7,
		"encounters_per_floor": 5,
		"monsters_per_floor": 6,
		"treasures_per_floor": 3,
		"egg_drops": ["Sphinx", "Gargoyle"],
		"material_drops": ["orichalcum_ore", "adamantine_ore", "ancient_scale"],
		"cooldown_hours": 42,
		"spawn_weight": 8,
		"color": "#F4A460"
	},
	"nazgul_shadow_keep": {
		"name": "Nazgul's Shadow Keep",
		"description": "A fortress of darkness and despair where a Nazgul commands the shadows.",
		"tier": 6,
		"min_level": 180,
		"max_level": 500,
		"monster_pool": ["Nazgul", "Wraith", "Wight"],
		"boss": {
			"name": "Nazgul Lord",
			"monster_type": "Nazgul",
			"level_mult": 1.25,
			"hp_mult": 5.5,
			"attack_mult": 2.2,
			"abilities": ["Black Breath", "Shadow Blade", "Morgul Strike", "Dread Aura"]
		},
		"boss_egg": "Nazgul",
		"floors": 7,
		"grid_size": 7,
		"encounters_per_floor": 6,
		"monsters_per_floor": 6,
		"treasures_per_floor": 2,
		"egg_drops": ["Nazgul", "Wraith"],
		"material_drops": ["orichalcum_ore", "void_essence", "soul_shard"],
		"cooldown_hours": 44,
		"spawn_weight": 7,
		"color": "#1C1C1C"
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
			"level_mult": 1.25,
			"hp_mult": 6.0,
			"attack_mult": 2.4,
			"abilities": ["Phase Shift", "Void Bolt", "Reality Tear", "Dimensional Prison"]
		},
		"boss_egg": "Void Walker",
		"floors": 8,
		"grid_size": 8,
		"encounters_per_floor": 6,
		"monsters_per_floor": 7,
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
			"level_mult": 1.25,
			"hp_mult": 7.0,
			"attack_mult": 2.6,
			"abilities": ["Primordial Breath", "Time Warp", "Cataclysm", "World Shaker"]
		},
		"boss_egg": "Primordial Dragon",
		"floors": 8,
		"grid_size": 8,
		"encounters_per_floor": 7,
		"monsters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Ancient Dragon"],
		"material_drops": ["void_ore", "primordial_scale", "time_crystal"],
		"cooldown_hours": 56,
		"spawn_weight": 4,
		"color": "#9400D3"
	},
	"world_serpent_coil": {
		"name": "World Serpent's Coil",
		"description": "The oceanic depths where the World Serpent coils around the roots of reality.",
		"tier": 7,
		"min_level": 600,
		"max_level": 1500,
		"monster_pool": ["Hydra", "Kelpie", "Siren"],
		"boss": {
			"name": "World Serpent",
			"monster_type": "World Serpent",
			"level_mult": 1.25,
			"hp_mult": 7.0,
			"attack_mult": 2.5,
			"abilities": ["Coil Crush", "Tidal Wave", "Venom Surge", "World Ender"]
		},
		"boss_egg": "World Serpent",
		"floors": 8,
		"grid_size": 8,
		"encounters_per_floor": 7,
		"monsters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Hydra"],
		"material_drops": ["void_ore", "orichalcum_ore", "primordial_scale"],
		"cooldown_hours": 52,
		"spawn_weight": 5,
		"color": "#006994"
	},
	"elder_lich_phylactery": {
		"name": "Elder Lich's Phylactery",
		"description": "The hidden vault containing an Elder Lich's soul, guarded by legions of undead.",
		"tier": 7,
		"min_level": 700,
		"max_level": 1800,
		"monster_pool": ["Lich", "Wraith", "Wight"],
		"boss": {
			"name": "Elder Lich",
			"monster_type": "Elder Lich",
			"level_mult": 1.25,
			"hp_mult": 6.5,
			"attack_mult": 2.5,
			"abilities": ["Phylactery Pulse", "Death Storm", "Soul Prison", "Undying Will"]
		},
		"boss_egg": "Elder Lich",
		"floors": 8,
		"grid_size": 8,
		"encounters_per_floor": 6,
		"monsters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Lich", "Wraith"],
		"material_drops": ["void_ore", "soul_shard", "phylactery_fragment"],
		"cooldown_hours": 54,
		"spawn_weight": 5,
		"color": "#2C0854"
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
			"level_mult": 1.3,
			"hp_mult": 8.0,
			"attack_mult": 2.8,
			"abilities": ["Madness Gaze", "Tentacle Storm", "Reality Warp", "Void Consumption"]
		},
		"boss_egg": "Cosmic Horror",
		"floors": 9,
		"grid_size": 8,
		"encounters_per_floor": 7,
		"monsters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Void Walker", "Elder Lich"],
		"material_drops": ["void_ore", "celestial_ore", "cosmic_fragment", "sanity_shard"],
		"cooldown_hours": 72,
		"spawn_weight": 3,
		"color": "#191970"
	},
	"time_weaver_loom": {
		"name": "Time Weaver's Loom",
		"description": "A temporal distortion where past and future collide under the Time Weaver's will.",
		"tier": 8,
		"min_level": 2500,
		"max_level": 5000,
		"monster_pool": ["Void Walker", "Primordial Dragon", "Elder Lich"],
		"boss": {
			"name": "Time Weaver",
			"monster_type": "Time Weaver",
			"level_mult": 1.3,
			"hp_mult": 8.0,
			"attack_mult": 2.8,
			"abilities": ["Temporal Shift", "Chrono Beam", "Time Loop", "Age of Ruin"]
		},
		"boss_egg": "Time Weaver",
		"floors": 9,
		"grid_size": 8,
		"encounters_per_floor": 7,
		"monsters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Void Walker", "Primordial Dragon"],
		"material_drops": ["celestial_ore", "void_ore", "time_crystal"],
		"cooldown_hours": 72,
		"spawn_weight": 3,
		"color": "#4169E1"
	},
	"death_domain": {
		"name": "Death's Domain",
		"description": "The threshold between life and oblivion where Death Incarnate waits.",
		"tier": 8,
		"min_level": 3000,
		"max_level": 5000,
		"monster_pool": ["Elder Lich", "Cosmic Horror", "Void Walker"],
		"boss": {
			"name": "Death Incarnate",
			"monster_type": "Death Incarnate",
			"level_mult": 1.3,
			"hp_mult": 8.5,
			"attack_mult": 3.0,
			"abilities": ["Reaper's Scythe", "Death's Embrace", "Soul Harvest", "Final Judgment"]
		},
		"boss_egg": "Death Incarnate",
		"floors": 9,
		"grid_size": 8,
		"encounters_per_floor": 7,
		"monsters_per_floor": 7,
		"treasures_per_floor": 3,
		"egg_drops": ["Elder Lich", "Cosmic Horror"],
		"material_drops": ["celestial_ore", "void_ore", "cosmic_fragment", "soul_shard"],
		"cooldown_hours": 84,
		"spawn_weight": 2,
		"color": "#0D0D0D"
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
			"level_mult": 1.3,
			"hp_mult": 10.0,
			"attack_mult": 3.0,
			"abilities": ["Chaos Storm", "Reality Shatter", "Entropy Wave", "Ultimate Destruction"]
		},
		"boss_egg": "Avatar of Chaos",
		"floors": 10,
		"grid_size": 9,
		"encounters_per_floor": 8,
		"monsters_per_floor": 8,
		"treasures_per_floor": 4,
		"egg_drops": ["Cosmic Horror", "Death Incarnate"],
		"material_drops": ["celestial_ore", "chaos_essence", "primordial_spark", "god_fragment"],
		"cooldown_hours": 96,
		"spawn_weight": 1,
		"color": "#800080"
	},
	"nameless_void": {
		"name": "The Nameless Void",
		"description": "A place beyond comprehension where The Nameless One erases all meaning.",
		"tier": 9,
		"min_level": 5500,
		"max_level": 10000,
		"monster_pool": ["Cosmic Horror", "Time Weaver", "Death Incarnate"],
		"boss": {
			"name": "The Nameless One",
			"monster_type": "The Nameless One",
			"level_mult": 1.3,
			"hp_mult": 10.0,
			"attack_mult": 3.0,
			"abilities": ["Nameless Dread", "Void Erasure", "Existential Horror", "Unmaking"]
		},
		"boss_egg": "The Nameless One",
		"floors": 10,
		"grid_size": 9,
		"encounters_per_floor": 8,
		"monsters_per_floor": 8,
		"treasures_per_floor": 4,
		"egg_drops": ["Cosmic Horror", "Time Weaver"],
		"material_drops": ["celestial_ore", "chaos_essence", "god_fragment", "primordial_spark"],
		"cooldown_hours": 96,
		"spawn_weight": 1,
		"color": "#0A0A0A"
	},
	"god_slayer_arena": {
		"name": "God Slayer's Arena",
		"description": "A divine battlefield where the God Slayer tests all challengers.",
		"tier": 9,
		"min_level": 6000,
		"max_level": 10000,
		"monster_pool": ["Avatar of Chaos", "Death Incarnate", "Time Weaver"],
		"boss": {
			"name": "God Slayer",
			"monster_type": "God Slayer",
			"level_mult": 1.3,
			"hp_mult": 10.0,
			"attack_mult": 3.2,
			"abilities": ["Divine Smite", "God Killer", "Ascendant Fury", "Immortal's End"]
		},
		"boss_egg": "God Slayer",
		"floors": 10,
		"grid_size": 9,
		"encounters_per_floor": 8,
		"monsters_per_floor": 8,
		"treasures_per_floor": 4,
		"egg_drops": ["Avatar of Chaos", "Death Incarnate"],
		"material_drops": ["celestial_ore", "chaos_essence", "god_fragment", "primordial_spark"],
		"cooldown_hours": 120,
		"spawn_weight": 1,
		"color": "#C5B358"
	},
	"entropy_end": {
		"name": "Entropy's End",
		"description": "The final dissolution of all things, where Entropy itself awaits.",
		"tier": 9,
		"min_level": 7000,
		"max_level": 10000,
		"monster_pool": ["Avatar of Chaos", "The Nameless One", "God Slayer"],
		"boss": {
			"name": "Entropy",
			"monster_type": "Entropy",
			"level_mult": 1.3,
			"hp_mult": 12.0,
			"attack_mult": 3.5,
			"abilities": ["Heat Death", "Entropic Decay", "Universe Collapse", "Final Entropy"]
		},
		"boss_egg": "Entropy",
		"floors": 10,
		"grid_size": 9,
		"encounters_per_floor": 8,
		"monsters_per_floor": 8,
		"treasures_per_floor": 4,
		"egg_drops": ["The Nameless One", "God Slayer"],
		"material_drops": ["celestial_ore", "chaos_essence", "god_fragment", "primordial_spark"],
		"cooldown_hours": 144,
		"spawn_weight": 1,
		"color": "#36013F"
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

# BSP dungeon grid size range (floors vary between min and max)
const DUNGEON_GRID_SIZE_MIN = 16
const DUNGEON_GRID_SIZE_MAX = 20

# Monster display colors by dungeon tier
const MONSTER_DISPLAY_COLORS = {
	1: "#22BB22", 2: "#22BB22",
	3: "#BBBB22", 4: "#BBBB22",
	5: "#DD8822", 6: "#DD8822",
	7: "#DD4444", 8: "#DD4444",
	9: "#AA44DD"
}

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

# ===== BSP DUNGEON GENERATION =====

static func generate_floor_grid(dungeon_id: String, floor_num: int, is_boss_floor: bool) -> Dictionary:
	"""Generate a BSP floor grid for a dungeon. Returns Dictionary with grid, rooms, entrance_pos, exit_pos."""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return {"grid": [], "rooms": [], "entrance_pos": Vector2i(1, 18), "exit_pos": Vector2i(18, 1)}

	var rng = RandomNumberGenerator.new()
	rng.seed = hash(dungeon_id + str(floor_num))
	# Randomize floor size for variety (boss floors always max size)
	var size = DUNGEON_GRID_SIZE_MAX if is_boss_floor else rng.randi_range(DUNGEON_GRID_SIZE_MIN, DUNGEON_GRID_SIZE_MAX)

	# Initialize grid with all walls
	var grid = []
	for y in range(size):
		var row = []
		for x in range(size):
			row.append(TileType.WALL)
		grid.append(row)

	# BSP split the area (leave 1-tile border)
	# Scale split depth with grid size: smaller grids get fewer splits
	var max_depth = 3 if size <= 14 else 4
	var partitions = []
	var initial_rect = Rect2i(1, 1, size - 2, size - 2)
	_bsp_split(initial_rect, 0, max_depth, rng, partitions)

	# Carve rooms in each leaf partition
	var rooms: Array = []
	for partition in partitions:
		var room = _carve_room(grid, partition, rng)
		if room.size.x > 0 and room.size.y > 0:
			rooms.append(room)

	# Connect rooms with corridors (connect each pair of siblings)
	if rooms.size() >= 2:
		# Sort rooms by position for more logical connections
		rooms.sort_custom(func(a, b): return (a.position.y * size + a.position.x) < (b.position.y * size + b.position.x))
		# Connect each room to the next (chain)
		for i in range(rooms.size() - 1):
			_connect_rooms(grid, rooms[i], rooms[i + 1], rng)
		# Extra connection from last to a middle room for loops
		if rooms.size() > 3:
			var mid = rooms.size() / 2
			_connect_rooms(grid, rooms[rooms.size() - 1], rooms[mid], rng)

	# Pick a random corner for entrance placement (adds layout variety)
	var corners = [
		Vector2i(1, size - 2),       # bottom-left
		Vector2i(size - 2, size - 2), # bottom-right
		Vector2i(1, 1),              # top-left
		Vector2i(size - 2, 1),       # top-right
	]
	var entrance_corner = corners[rng.randi_range(0, 3)]
	var entrance_room_idx = _find_closest_room(rooms, entrance_corner)
	var entrance_pos = _get_room_center(rooms[entrance_room_idx])
	grid[entrance_pos.y][entrance_pos.x] = TileType.ENTRANCE

	# Place exit/boss in room farthest from entrance
	var exit_room_idx = _find_farthest_room(rooms, entrance_pos)
	var exit_pos = _get_room_center(rooms[exit_room_idx])
	if is_boss_floor:
		# Boss floor has no exit tile, boss entity will be placed by server
		pass
	else:
		grid[exit_pos.y][exit_pos.x] = TileType.EXIT

	# Place treasures in small/dead-end rooms (1-3 per floor)
	var treasure_count = 1 + rng.randi_range(0, 2)
	var used_rooms = [entrance_room_idx, exit_room_idx]
	for _i in range(treasure_count):
		var best_room = -1
		var smallest_area = 999
		for ri in range(rooms.size()):
			if ri in used_rooms:
				continue
			var area = rooms[ri].size.x * rooms[ri].size.y
			if area < smallest_area:
				smallest_area = area
				best_room = ri
		if best_room >= 0:
			used_rooms.append(best_room)
			var tpos = _get_room_center(rooms[best_room])
			if grid[tpos.y][tpos.x] == TileType.EMPTY:
				grid[tpos.y][tpos.x] = TileType.TREASURE

	# Place 1-2 gathering resource nodes in unused rooms
	var resource_count = rng.randi_range(1, 2)
	for _i in range(resource_count):
		var best_room = -1
		var best_area = 999
		for ri in range(rooms.size()):
			if ri in used_rooms:
				continue
			var area = rooms[ri].size.x * rooms[ri].size.y
			if area < best_area:
				best_area = area
				best_room = ri
		if best_room >= 0:
			used_rooms.append(best_room)
			var rpos = _get_room_center(rooms[best_room])
			if grid[rpos.y][rpos.x] == TileType.EMPTY:
				grid[rpos.y][rpos.x] = TileType.RESOURCE

	return {"grid": grid, "rooms": rooms, "entrance_pos": entrance_pos, "exit_pos": exit_pos}

static func _bsp_split(rect: Rect2i, depth: int, max_depth: int, rng: RandomNumberGenerator, out_partitions: Array):
	"""Recursively split area into BSP partitions"""
	# Stop if too small or max depth reached
	if rect.size.x < 7 or rect.size.y < 7 or depth >= max_depth:
		out_partitions.append(rect)
		return

	# Also stop randomly at deeper levels for variety
	if depth >= 2 and rng.randf() < 0.15:
		out_partitions.append(rect)
		return

	# Decide split direction: alternate, but prefer splitting the longer axis
	var split_horizontal: bool
	if rect.size.x > rect.size.y * 1.3:
		split_horizontal = false  # Split vertically (left/right)
	elif rect.size.y > rect.size.x * 1.3:
		split_horizontal = true  # Split horizontally (top/bottom)
	else:
		split_horizontal = (depth % 2 == 0)  # Alternate

	if split_horizontal:
		# Split horizontally - 40-60% ratio
		var split_y = rect.position.y + int(rect.size.y * rng.randf_range(0.4, 0.6))
		var top = Rect2i(rect.position.x, rect.position.y, rect.size.x, split_y - rect.position.y)
		var bottom = Rect2i(rect.position.x, split_y, rect.size.x, rect.end.y - split_y)
		if top.size.y >= 5 and bottom.size.y >= 5:
			_bsp_split(top, depth + 1, max_depth, rng, out_partitions)
			_bsp_split(bottom, depth + 1, max_depth, rng, out_partitions)
		else:
			out_partitions.append(rect)
	else:
		# Split vertically - 40-60% ratio
		var split_x = rect.position.x + int(rect.size.x * rng.randf_range(0.4, 0.6))
		var left = Rect2i(rect.position.x, rect.position.y, split_x - rect.position.x, rect.size.y)
		var right = Rect2i(split_x, rect.position.y, rect.end.x - split_x, rect.size.y)
		if left.size.x >= 5 and right.size.x >= 5:
			_bsp_split(left, depth + 1, max_depth, rng, out_partitions)
			_bsp_split(right, depth + 1, max_depth, rng, out_partitions)
		else:
			out_partitions.append(rect)

static func _carve_room(grid: Array, partition: Rect2i, rng: RandomNumberGenerator) -> Rect2i:
	"""Carve a random room within a BSP partition (min 3x3, max ~80% of partition)"""
	var max_w = max(3, int(partition.size.x * 0.8))
	var max_h = max(3, int(partition.size.y * 0.8))
	var room_w = rng.randi_range(3, max_w)
	var room_h = rng.randi_range(3, max_h)

	# Random position within partition
	var room_x = partition.position.x + rng.randi_range(1, max(1, partition.size.x - room_w - 1))
	var room_y = partition.position.y + rng.randi_range(1, max(1, partition.size.y - room_h - 1))

	# Clamp to grid bounds (leave outer border as wall)
	room_x = clampi(room_x, 1, grid.size() - 2)
	room_y = clampi(room_y, 1, grid.size() - 2)
	room_w = mini(room_w, grid.size() - 1 - room_x)
	room_h = mini(room_h, grid.size() - 1 - room_y)

	var room = Rect2i(room_x, room_y, room_w, room_h)

	# Carve the room
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if x > 0 and x < grid.size() - 1 and y > 0 and y < grid.size() - 1:
				grid[y][x] = TileType.EMPTY

	return room

static func _connect_rooms(grid: Array, room_a: Rect2i, room_b: Rect2i, rng: RandomNumberGenerator):
	"""Connect two rooms with an L-shaped corridor"""
	var center_a = _get_room_center(room_a)
	var center_b = _get_room_center(room_b)

	# Randomly choose to go horizontal-first or vertical-first
	if rng.randi() % 2 == 0:
		# Horizontal then vertical
		_carve_h_corridor(grid, center_a.x, center_b.x, center_a.y)
		_carve_v_corridor(grid, center_a.y, center_b.y, center_b.x)
	else:
		# Vertical then horizontal
		_carve_v_corridor(grid, center_a.y, center_b.y, center_a.x)
		_carve_h_corridor(grid, center_a.x, center_b.x, center_b.y)

static func _carve_h_corridor(grid: Array, x1: int, x2: int, y: int):
	"""Carve a horizontal corridor"""
	var start_x = mini(x1, x2)
	var end_x = maxi(x1, x2)
	y = clampi(y, 1, grid.size() - 2)
	for x in range(start_x, end_x + 1):
		x = clampi(x, 1, grid.size() - 2)
		if grid[y][x] == TileType.WALL:
			grid[y][x] = TileType.EMPTY

static func _carve_v_corridor(grid: Array, y1: int, y2: int, x: int):
	"""Carve a vertical corridor"""
	var start_y = mini(y1, y2)
	var end_y = maxi(y1, y2)
	x = clampi(x, 1, grid.size() - 2)
	for y in range(start_y, end_y + 1):
		y = clampi(y, 1, grid.size() - 2)
		if grid[y][x] == TileType.WALL:
			grid[y][x] = TileType.EMPTY

static func _get_room_center(room: Rect2i) -> Vector2i:
	"""Get the center tile of a room"""
	return Vector2i(room.position.x + room.size.x / 2, room.position.y + room.size.y / 2)

static func _find_closest_room(rooms: Array, target: Vector2i) -> int:
	"""Find room index closest to target position"""
	var best_idx = 0
	var best_dist = 99999
	for i in range(rooms.size()):
		var center = _get_room_center(rooms[i])
		var dist = abs(center.x - target.x) + abs(center.y - target.y)
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	return best_idx

static func _find_farthest_room(rooms: Array, target: Vector2i) -> int:
	"""Find room index farthest from target position"""
	var best_idx = 0
	var best_dist = -1
	for i in range(rooms.size()):
		var center = _get_room_center(rooms[i])
		var dist = abs(center.x - target.x) + abs(center.y - target.y)
		if dist > best_dist:
			best_dist = dist
			best_idx = i
	return best_idx

static func grid_to_string(grid: Array, player_x: int, player_y: int, monsters: Array = []) -> String:
	"""Convert floor grid to display string with player position and monsters"""
	if grid.is_empty():
		return ""
	var lines = []
	var width = grid[0].size() if grid.size() > 0 else 0
	lines.append("[color=#FFD700]+" + "-".repeat(width) + "+[/color]")

	# Build monster position lookup
	var monster_map = {}
	for m in monsters:
		var key = "%d,%d" % [m.get("x", -1), m.get("y", -1)]
		monster_map[key] = m

	for y in range(grid.size()):
		var line = "[color=#FFD700]|[/color]"
		for x in range(grid[y].size()):
			if x == player_x and y == player_y:
				line += "[color=#00FF00]@[/color]"
			else:
				var mkey = "%d,%d" % [x, y]
				if monster_map.has(mkey):
					var mon = monster_map[mkey]
					var mchar = mon.get("char", "M")
					var mcolor = mon.get("color", "#FF4444")
					if mon.get("alert", false):
						mcolor = "#FF0000"
					if mon.get("is_boss", false):
						mchar = "B"
						mcolor = "#FF0000"
					line += "[color=%s]%s[/color]" % [mcolor, mchar]
				else:
					var tile = grid[y][x]
					var tchar = TILE_CHARS.get(tile, "?")
					var color = TILE_COLORS.get(tile, "#FFFFFF")
					line += "[color=%s]%s[/color]" % [color, tchar]
		line += "[color=#FFD700]|[/color]"
		lines.append(line)

	lines.append("[color=#FFD700]+" + "-".repeat(width) + "+[/color]")
	return "\n".join(lines)

static func get_monster_for_encounter(dungeon_id: String, floor_num: int, dungeon_level: int) -> Dictionary:
	"""Generate a monster for a dungeon encounter - uses the dungeon's boss monster type"""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return {}

	# Use the boss's monster_type for all encounters in this dungeon
	var boss_data = dungeon.get("boss", {})
	var monster_name = boss_data.get("monster_type", "")

	# Fallback to first monster in pool if no boss monster_type defined
	if monster_name == "":
		var monster_pool = dungeon.get("monster_pool", [])
		if monster_pool.is_empty():
			return {}
		monster_name = monster_pool[0]

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
		"name": boss_data.name,  # Display name (e.g., "Orc Warlord")
		"monster_type": boss_data.get("monster_type", boss_data.name),  # Base monster type for generation (e.g., "Orc")
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

static func roll_treasure(dungeon_id: String, floor_num: int, sub_tier: int = 1) -> Dictionary:
	"""Roll for treasure chest contents. Eggs use tier-based rarity. Sub-tier scales material quantity."""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return {"materials": [], "egg": {}}

	var tier = dungeon.tier
	var sub_tier_mult = 1.0 + (sub_tier - 1) * 0.1

	# Roll for materials (more generous since no gold)
	var materials = []
	var material_drops = dungeon.get("material_drops", [])
	if not material_drops.is_empty():
		# 60% chance for each material, quantity scales with floor and sub-tier
		for mat in material_drops:
			if randi() % 100 < 60:
				var qty = int((1 + randi() % 3 + floor_num) * sub_tier_mult)
				materials.append({"id": mat, "quantity": qty})
		# Guarantee at least 1 material from the pool
		if materials.is_empty():
			var mat = material_drops[randi() % material_drops.size()]
			var qty = int((1 + floor_num) * sub_tier_mult)
			materials.append({"id": mat, "quantity": qty})

	# Roll for egg using tier-based rarity (higher tier = lower chance)
	var egg = {}
	var egg_drops = dungeon.get("egg_drops", [])
	if not egg_drops.is_empty():
		# Use tier-based drop chance instead of dungeon's egg_drop_chance
		var egg_chance = TREASURE_EGG_CHANCE_BY_TIER.get(tier, 10)
		if randi() % 100 < egg_chance:
			var egg_monster = egg_drops[randi() % egg_drops.size()]
			egg = {"monster": egg_monster, "sub_tier": sub_tier}

	return {
		"materials": materials,
		"egg": egg
	}

static func calculate_completion_rewards(dungeon_id: String, floors_cleared: int, sub_tier: int = 1) -> Dictionary:
	"""Calculate rewards for completing a dungeon. Includes GUARANTEED boss egg!
	Sub-tier scales XP by +10% per sub-tier above 1."""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return {}

	var tier = dungeon.tier
	var total_floors = dungeon.floors

	# Base rewards scale with tier and completion
	var completion_bonus = float(floors_cleared) / float(total_floors)
	var base_xp = tier * 500 * completion_bonus

	# Bonus for full clear
	if floors_cleared >= total_floors:
		base_xp *= 1.5

	# Sub-tier scales rewards: +10% per sub-tier above 1
	var sub_tier_mult = 1.0 + (sub_tier - 1) * 0.1
	base_xp *= sub_tier_mult

	# Get guaranteed boss egg (dungeon completion ALWAYS gives the boss's egg)
	var boss_egg = dungeon.get("boss_egg", "")

	return {
		"xp": int(base_xp),
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

static func get_sub_tier_level_range(tier: int, sub_tier: int) -> Dictionary:
	"""Get level range for a specific tier + sub-tier combo.
	Sub-tiers 1-8 subdivide the tier's level range into 8 segments."""
	var tr = TIER_LEVEL_RANGES.get(tier, {"min": 1, "max": 12})
	var range_size = tr.max - tr.min
	var segment = float(range_size) / 8.0
	var sub_min = tr.min + int(segment * (sub_tier - 1))
	var sub_max = tr.min + int(segment * sub_tier)
	sub_min = clampi(sub_min, tr.min, tr.max)
	sub_max = clampi(sub_max, sub_min + 1, tr.max)
	if sub_min >= sub_max:
		sub_max = sub_min + 1
	return {"min_level": sub_min, "max_level": maxi(sub_min, sub_max)}

static func get_sub_tier_for_distance(tier: int, distance: float) -> int:
	"""Calculate sub-tier (1-8) based on distance within tier's spawn band.
	Further from origin within the tier band = higher sub-tier.
	Includes random variance of +/-1 (25% chance of +/-2)."""
	var min_dist = tier * 30
	var max_dist = tier * 60
	var progress = clampf((distance - min_dist) / float(maxi(1, max_dist - min_dist)), 0.0, 1.0)
	var base = 1 + int(progress * 7.0)
	# Random variance: usually +/-1, 25% chance of +/-2
	var variance = (randi() % 3) - 1
	if randi() % 4 == 0:
		variance = (randi() % 5) - 2
	return clampi(base + variance, 1, 8)

static func get_dungeon_display_name(dungeon_id: String, tier: int, sub_tier: int) -> String:
	"""Get display name with tier notation, e.g. 'Goblin Caves [T1-5]'."""
	var dungeon = get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return "Unknown Dungeon [T%d-%d]" % [tier, sub_tier]
	return "%s [T%d-%d]" % [dungeon.name, tier, sub_tier]

static func get_dungeon_resource_tier(dungeon_tier: int) -> int:
	"""Map dungeon tier to resource material tier for gathering nodes."""
	if dungeon_tier <= 3:
		return clampi(dungeon_tier + 3, 4, 5)  # T1-3 dungeons → T4-5 materials
	elif dungeon_tier <= 6:
		return clampi(dungeon_tier + 1, 6, 7)  # T4-6 dungeons → T6-7 materials
	else:
		return clampi(dungeon_tier, 7, 9)       # T7-9 dungeons → T7-9 materials (dungeon-exclusive)

static func roll_dungeon_resource_type(rng: RandomNumberGenerator) -> String:
	"""Roll a random resource node type for dungeons."""
	var roll = rng.randi_range(0, 99)
	if roll < 40:
		return "ore"
	elif roll < 70:
		return "herb"
	else:
		return "crystal"

# Escape scroll tier mapping: dungeon tier → scroll item_type
const ESCAPE_SCROLL_TIERS = {
	1: "scroll_of_escape", 2: "scroll_of_escape", 3: "scroll_of_escape", 4: "scroll_of_escape",
	5: "scroll_of_greater_escape", 6: "scroll_of_greater_escape", 7: "scroll_of_greater_escape",
	8: "scroll_of_supreme_escape", 9: "scroll_of_supreme_escape"
}

static func roll_escape_scroll_drop(dungeon_tier: int) -> Dictionary:
	"""20% chance to drop an escape scroll from treasure. Returns empty dict or scroll item."""
	if randi() % 100 >= 20:
		return {}
	var scroll_id = ESCAPE_SCROLL_TIERS.get(dungeon_tier, "scroll_of_escape")
	var tier_max = 4
	var scroll_name = "Scroll of Escape"
	if scroll_id == "scroll_of_greater_escape":
		tier_max = 7
		scroll_name = "Scroll of Greater Escape"
	elif scroll_id == "scroll_of_supreme_escape":
		tier_max = 9
		scroll_name = "Scroll of Supreme Escape"
	return {
		"name": scroll_name,
		"item_type": "escape_scroll",
		"tier_max": tier_max,
		"type": "consumable"
	}