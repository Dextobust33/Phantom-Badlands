# 08 - World and Map System

This guide covers the procedural world generation, chunk-based persistence, dungeon system, NPC posts, and map rendering in Phantom Badlands. Understanding these systems is essential for any work that touches terrain, movement, gathering, dungeons, or the visual map display.

---

## Table of Contents

1. [World Overview](#1-world-overview)
2. [Terrain Generation](#2-terrain-generation)
3. [Tier Zones and Level Scaling](#3-tier-zones-and-level-scaling)
4. [Tile Detection Functions](#4-tile-detection-functions)
5. [The Chunk System](#5-the-chunk-system)
6. [NPC Posts](#6-npc-posts)
7. [Trading Posts (Legacy)](#7-trading-posts-legacy)
8. [Dungeon System](#8-dungeon-system)
9. [Hotspots and Encounters](#9-hotspots-and-encounters)
10. [Movement and Map Display](#10-movement-and-map-display)
11. [Line of Sight](#11-line-of-sight)
12. [A* Pathfinding and Road System](#12-a-pathfinding-and-road-system)
13. [Merchant NPCs](#13-merchant-npcs)
14. [Player Buildings (Enclosures)](#14-player-buildings-enclosures)
15. [Modifying the World](#15-modifying-the-world)

---

## 1. World Overview

Phantom Badlands uses a **procedural infinite world** generated from a single seed number. The world is text-based: players see a small ASCII map viewport around their position on the client.

### Key Properties

- **World bounds:** -2000 to +2000 on both axes, effectively a 4000x4000 tile area centered on origin (0,0).
- **Deterministic:** Same seed always produces the same world. The seed is generated on first server start and saved to `user://data/world_seed.json`.
- **Tile-based:** Every coordinate has a procedurally generated tile type with properties (character, color, blocks movement, blocks line of sight).
- **Client viewport:** 21x9 tiles (radius 11) around the player, rendered as BBCode in a RichTextLabel.

### Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `shared/world_system.gd` | ~2400 | Terrain generation, tile detection, map rendering, pathfinding, merchants |
| `shared/chunk_manager.gd` | ~530 | 32x32 chunk storage, tile access, node depletion, geological events |
| `shared/dungeon_database.gd` | ~2100 | Dungeon definitions, BSP floor generation, trap/step mechanics |
| `shared/npc_post_database.gd` | ~400 | NPC post generation, compound room layouts, station placement |
| `shared/trading_post_database.gd` | ~450 | Legacy trading post definitions (being migrated to NPC posts) |

### Architecture

```
Server startup:
  1. ChunkManager loads world_seed (or generates new one)
  2. ChunkManager loads NPC posts (or generates + stamps them)
  3. WorldSystem links to ChunkManager as terrain_generator
  4. Roads computed between posts (A* pathfinding)
  5. Merchant circuits assigned to road segments
  6. Dungeons spawned across the map

Player movement:
  Client sends move -> Server validates via WorldSystem ->
  ChunkManager returns tile data -> Server checks encounters ->
  Server sends location + map data back to client
```

---

## 2. Terrain Generation

### The New Tile System

Each tile in the world has a type string, a tier (1-6 for gathering resources), and blocking properties. The `generate_tile()` function in `world_system.gd` is the core of terrain generation.

**Tile types and their rendering:**

| Type | Char | Color | Blocks Move | Blocks LOS | Purpose |
|------|------|-------|-------------|------------|---------|
| `empty` | `.` | `#6B5B45` | No | No | Open ground |
| `stone` | `o` | `#998877` | Yes | Yes | Mining node |
| `tree` | `T` | `#228B22` | Yes | Yes | Logging node |
| `ore_vein` | `*` | `#8B6914` | Yes | Yes | Mining node (rarer) |
| `herb` | `"` | `#66CC66` | No | No | Foraging node |
| `flower` | `'` | `#FF69B4` | No | No | Foraging node |
| `mushroom` | `,` | `#9966CC` | No | No | Foraging node |
| `bush` | `;` | `#006600` | No | No | Foraging node |
| `reed` | `\|` | `#66CCCC` | No | No | Foraging node |
| `dense_brush` | `%` | `#6B8E23` | Yes | No | Logging node |
| `water` | `~` | `#4488FF` | Yes | No | Fishing node |
| `deep_water` | `~` | `#2244AA` | Yes | No | Fishing node (rare) |
| `wall` | `#` | `#CCCCCC` | Yes | Yes | Structure wall |
| `door` | `+` | `#CCAA00` | No | No | Structure door |
| `floor` | `.` | `#D4C4A2` | No | No | Structure interior |
| `path` | `:` | `#C4A882` | No | No | Road/path tile |
| `forge` | `F` | `#FF8800` | Yes | No | Crafting station |
| `apothecary` | `A` | `#00CC66` | Yes | No | Crafting station |
| `workbench` | `W` | `#AA7744` | Yes | No | Crafting station |
| `enchant_table` | `E` | `#AA44FF` | Yes | No | Crafting station |
| `writing_desk` | `S` | `#87CEEB` | Yes | No | Crafting station |
| `market` | `$` | `#FFD700` | Yes | No | Trading/market |
| `inn` | `I` | `#FFAA44` | Yes | No | Rest point |
| `quest_board` | `Q` | `#C4A882` | Yes | No | Quest interface |
| `blacksmith` | `B` | `#DAA520` | Yes | No | Equipment repair/upgrade |
| `healer` | `H` | `#00FF88` | Yes | No | HP restoration |
| `tower` | `^` | `#FFFFFF` | No | No | Player-built tower |
| `storage` | `C` | `#AAAAFF` | No | No | Storage container |
| `guard` | `G` | `#C0C0C0` | Yes | No | Guard post |
| `post_marker` | `P` | `#FFD700` | No | No | NPC post center |
| `void` | ` ` | `#111111` | Yes | Yes | World boundary |

### How Tile Generation Works

The `generate_tile(world_x, world_y, seed)` function determines what occupies each coordinate:

```gdscript
func generate_tile(world_x: int, world_y: int, seed: int) -> Dictionary:
    var distance = sqrt(float(world_x * world_x + world_y * world_y))

    # Step 1: Safe zone at center (radius 5) is always empty
    if distance < 5:
        return {"type": "empty", ...}

    # Step 2: NPC post interiors are always empty (posts stamp their own tiles)
    if chunk_manager and chunk_manager.is_npc_post_tile(world_x, world_y):
        return {"type": "empty", ...}

    # Step 3: Check for water using noise-based clustering
    if _is_water_tile_generated(world_x, world_y, seed):
        # Determine shallow vs deep (deep only beyond distance 200)
        ...

    # Step 4: Density check - determines if tile is occupied or empty
    # Ramps from 50% near origin to 70% at edges
    var density = 0.50 + 0.20 * clampf(distance / 2000.0, 0.0, 1.0)
    var density_roll = _seeded_hash_float(x * 7 + y * 13, seed)
    if density_roll >= density:
        return {"type": "empty", ...}

    # Step 5: Roll node type from weighted distribution
    var type_roll = _seeded_hash_int(x * 31 + y * 53, seed + 1) % 95
    var node_type = _roll_node_type(type_roll)

    # Step 6: Determine tier from distance
    var tier = _get_tier_for_distance(distance, x, y, seed)

    return {"type": node_type, "tier": tier, ...}
```

### Node Type Distribution

The `NODE_WEIGHTS` constant defines the percentage breakdown of occupied tiles:

| Node Type | Weight | Percentage |
|-----------|--------|------------|
| stone | 25 | ~26% |
| tree | 25 | ~26% |
| ore_vein | 10 | ~11% |
| dense_brush | 10 | ~11% |
| herb | 5 | ~5% |
| flower | 5 | ~5% |
| mushroom | 5 | ~5% |
| bush | 5 | ~5% |
| reed | 5 | ~5% |

Water is handled separately via noise clustering (not part of the weighted distribution).

### The Hash Functions

All procedural generation uses two deterministic hash functions:

```gdscript
func _seeded_hash_float(coord_hash: int, seed: int) -> float:
    """Deterministic hash returning 0.0-1.0"""
    var h = abs((coord_hash + seed) * 2654435761) % 1000000
    return h / 1000000.0

func _seeded_hash_int(coord_hash: int, seed: int) -> int:
    """Deterministic hash returning a positive integer"""
    return abs((coord_hash + seed) * 2654435761) % 1000000
```

The magic number `2654435761` is the golden ratio times 2^32, a classic hash multiplier. Different coordinate multipliers (e.g., `x * 7 + y * 13` vs `x * 31 + y * 53`) produce different hash patterns for different purposes, preventing correlation between systems.

### Water Generation

Water uses a noise-based clustering system for natural-looking lakes and rivers:

```gdscript
func _is_water_tile_generated(x, y, seed) -> bool:
    # Layer 1: Large-scale noise (frequency 0.03) produces lakes
    var water_noise = _water_noise(x, y, seed)
    if water_noise > 0.62:
        return true

    # Layer 2: Tiny scattered ponds (~0.3% random)
    var pond_hash = _seeded_hash_float(x * 173 + y * 251, seed + 500)
    return pond_hash > 0.997
```

The `_water_noise()` function uses grid-based value noise with smoothstep interpolation to create coherent water regions.

---

## 3. Tier Zones and Level Scaling

### Resource Tiers (Gathering)

The world has 6 overlapping tier zones for gathering resources:

```
TIER_ZONES = [
    [0, 200],       # T1 — near center
    [150, 400],     # T2
    [300, 700],     # T3
    [500, 1000],    # T4
    [800, 1400],    # T5
    [1200, 2000],   # T6 — near edges
]
```

**Overlap zones** create gradual transitions. When a tile falls in the overlap between two tiers, a hash-based roll determines which tier it gets, weighted toward the higher tier as distance increases:

```
Distance from origin:
0 -------- 150 --- 200 -------- 300 --- 400 -------- 500 --- 700 ...
|   T1 only   | overlap |  T2 only  | overlap |  T3 only  | ...
              | T1 / T2 |           | T2 / T3 |
```

Beyond all defined zones (distance > 2000), all resources are tier 6.

### Monster Level Scaling

Monster levels scale by distance from origin through the `_distance_to_level()` function:

| Distance | Level Range | Description |
|----------|-------------|-------------|
| 0-10 | Level 1 | Safe zone |
| 10-150 | 1-50 | Gentle curve for new players |
| 150-400 | 50-200 | Moderate growth |
| 400-800 | 200-600 | Steady progression |
| 800-1200 | 600-1500 | Accelerating |
| 1200-1800 | 1500-4000 | Steep curve |
| 1800-2828 | 4000-10000 | Approaching max |

The actual level range displayed at a location includes +/-10% variance. Hotspots multiply the base level by 1.5x to 2.5x depending on intensity.

### Dungeon Sub-Tiers

Dungeons use a separate 9-tier system with 8 sub-tiers per tier. The `TIER_LEVEL_RANGES` in `dungeon_database.gd` define:

| Tier | Level Range | Example Dungeons |
|------|-------------|------------------|
| T1 | 1-12 | Goblin Caves, Wolf Den, Rat Warrens |
| T2 | 6-22 | Orc Stronghold, Spider Nest, Hobgoblin Fortress |
| T3 | 16-40 | Troll's Den, Wyvern's Roost, Minotaur Labyrinth |
| T4 | 31-60 | Giant's Keep, Vampire Crypt, Dragon Hatchery |
| T5 | 51-120 | Lich Sanctum, Cerberus Pit, Balrog Depths |
| T6 | 101-500 | Higher tier dungeons |
| T7 | 501-2000 | Higher tier dungeons |
| T8 | 2001-5000 | Higher tier dungeons |
| T9 | 5001-10000 | Endgame dungeons |

Sub-tiers (1-8) subdivide each tier's level range into 8 segments. A dungeon at T2-5 would be in the 5th segment of tier 2's level range.

---

## 4. Tile Detection Functions

The world system provides several detection functions used by the server when a player moves. These determine what actions are available at a location.

### Gathering Detection

```gdscript
# Unified gathering detection (preferred)
func get_gathering_node_at(x, y) -> Dictionary:
    # Returns {type, tier, job} or empty dict
    # Checks depletion status automatically

# Individual checks
func is_ore_deposit(x, y) -> bool      # stone or ore_vein tile
func is_dense_forest(x, y) -> bool     # tree or dense_brush tile
func is_foraging_spot(x, y) -> bool    # herb/flower/mushroom/bush/reed
func is_fishing_spot(x, y) -> bool     # water or deep_water terrain

# Tier queries
func get_ore_tier(x, y) -> int         # From tile data
func get_wood_tier(x, y) -> int        # From tile data
func get_fishing_tier(x, y) -> int     # 1-6 based on distance + water type
```

### Gathering Job Mapping

The `NODE_TO_JOB` constant maps tile types to gathering jobs:

| Tile Type | Job |
|-----------|-----|
| stone, ore_vein | mining |
| tree, dense_brush | logging |
| herb, flower, mushroom, bush, reed | foraging |
| water | fishing |

### Location Detection

```gdscript
func is_safe_zone(x, y) -> bool
    # True if: NPC post tile, structure interior tile (floor, forge, etc.),
    #          enclosure tile, or legacy trading post tile

func get_terrain_at(x, y) -> Terrain
    # Returns legacy Terrain enum for backward compatibility
    # Converts new tile types to Terrain values

func get_monster_level_range(x, y) -> Dictionary
    # Returns {min, max, base_level, is_hotspot, distance}

func get_hotspot_at(x, y) -> Dictionary
    # Returns {in_hotspot: bool, intensity: float}
```

### How Hash-Based Detection Works

All deterministic detection uses the same pattern -- a coordinate-based hash compared against a threshold:

```gdscript
# Example: legacy ore deposit detection
func _legacy_is_ore_deposit(x, y) -> bool:
    # Only mountains can have ore deposits
    if terrain != Terrain.MOUNTAINS:
        return false
    # Hash the coordinates with specific multipliers
    var ore_hash = abs(x * 47 + y * 83) % 1000
    # ~1% of mountain tiles are ore deposits
    return ore_hash < 10
```

The multiplier pair (`x * 47 + y * 83`) determines the distribution pattern. Different multipliers create different patterns that appear random but are fully deterministic.

---

## 5. The Chunk System

**File:** `shared/chunk_manager.gd`

The chunk system divides the 4000x4000 world into 32x32 tile chunks, enabling efficient storage and modification of the procedural world.

### Chunk Coordinates

```gdscript
const CHUNK_SIZE = 32
const WORLD_MIN = -2000
const WORLD_MAX = 2000

# World coordinate -> chunk key
func get_chunk_key(world_x, world_y) -> String:
    var cx = floori(float(world_x - WORLD_MIN) / CHUNK_SIZE)
    var cy = floori(float(world_y - WORLD_MIN) / CHUNK_SIZE)
    return "chunk_%d_%d" % [cx, cy]

# Example: tile at (50, 50) is in chunk "chunk_64_64"
# Because (50 - (-2000)) / 32 = 64.0625 -> floor = 64
```

### Tile Access Pattern

The `get_tile()` method implements a layered lookup:

```
1. Check bounds (return void if out of range)
2. Compute chunk key from world coordinates
3. Load chunk from disk if not in memory
4. Check for modified tile in chunk data
5. If no modification, generate tile procedurally via WorldSystem
```

```gdscript
func get_tile(world_x, world_y) -> Dictionary:
    # Out of bounds -> void
    if world_x < WORLD_MIN or world_x > WORLD_MAX:
        return {"type": "void", "blocks_move": true, "blocks_los": true}

    var chunk_key = get_chunk_key(world_x, world_y)
    var tile_key = "%d,%d" % [world_x, world_y]

    # Check for modifications (player-built structures, NPC posts, etc.)
    if _loaded_chunks.has(chunk_key):
        var modified_tiles = _loaded_chunks[chunk_key].get("modified_tiles", {})
        if modified_tiles.has(tile_key):
            return modified_tiles[tile_key]

    # No modification -> generate procedurally
    return terrain_generator.generate_tile(world_x, world_y, world_seed)
```

### Tile Modification

When something modifies the world (building a wall, stamping an NPC post, depleting a node), the chunk is marked dirty:

```gdscript
func set_tile(world_x, world_y, data: Dictionary) -> void:
    var chunk_key = get_chunk_key(world_x, world_y)
    var tile_key = "%d,%d" % [world_x, world_y]

    # Load or create chunk in memory
    if not _loaded_chunks.has(chunk_key):
        _loaded_chunks[chunk_key] = _load_or_create_chunk(chunk_key)

    chunk_data["modified_tiles"][tile_key] = data
    _dirty_chunks[chunk_key] = true  # Marked for saving
```

Modified chunks are saved as JSON files to `user://data/world/chunk_X_Y.json`. Only modified tiles are stored -- unmodified tiles continue to be generated procedurally.

### Node Depletion

Gathering nodes can be depleted (harvested). Depletion is tracked separately from chunk data:

```gdscript
# depleted_nodes: Dictionary of "x,y" -> respawn_timestamp or DEPLETED_PERMANENT

func deplete_node(world_x, world_y, tile_type):
    var coord_key = "%d,%d" % [world_x, world_y]
    if tile_type == "water":
        # Water respawns after 5 minutes
        depleted_nodes[coord_key] = Time.get_unix_time_from_system() + 300.0
    else:
        # All other nodes are permanently depleted
        depleted_nodes[coord_key] = DEPLETED_PERMANENT  # -1
```

Depleted nodes become passable (players can walk through them) and are rendered as dim commas (`,`) on the map. Water nodes respawn after 5 minutes; all other nodes are permanent.

Depleted node data is persisted to `user://data/depleted_nodes.json` every 30 seconds and across server restarts.

### Chunk I/O

```
Chunk files: user://data/world/chunk_X_Y.json
Format: {"seed": <world_seed>, "modified_tiles": {"x,y": {tile_data}, ...}}

World seed: user://data/world_seed.json
Format: {"seed": <integer>}

Depleted nodes: user://data/depleted_nodes.json
Format: {"x,y": <timestamp_or_-1>, ...}

NPC posts: user://data/npc_posts.json
Format: {"posts": [<post_data>, ...]}

Paths: user://data/world/paths.json
Format: {"paths": {...}, "graph": {...}, "post_positions": {...}}
```

### Wipe Support

The chunk manager supports full and partial wipes:

```gdscript
func wipe_all_chunks():      # Delete all chunk files, clear memory, reset depleted nodes
func wipe_chunk(chunk_key):   # Reset a single chunk to procedural state
func regenerate_world_seed(): # Generate new seed (used for full world reset)
```

---

## 6. NPC Posts

**File:** `shared/npc_post_database.gd`

NPC posts are procedurally-placed settlements across the map. They serve as safe zones with crafting stations, merchants, quest boards, and other services.

### Generation

On first server start, 18 posts are generated from the world seed:

```gdscript
const POST_COUNT_TARGET = 18
const POST_PLACEMENT_RADIUS = 450    # Max distance from origin
const MIN_POST_SPACING = 100         # Minimum distance between posts
```

Generation process:
1. **Starter post** at origin (0,0) named "Crossroads" with guaranteed large size
2. **17 additional posts** placed randomly within 450 tiles of origin
3. Minimum spacing of 100 tiles between any two posts
4. Each post gets a random name (prefix + suffix), category, and quest giver

### Compound Room Layouts

Each post consists of a **main room** and 0-3 **wing rooms** for visual variety:

```
Main room: 11x11 to 15x15 tiles (odd dimensions for clean centering)
Wing rooms: 5x5 to 7x7 tiles, attached to a side of the main room
Wing distribution: 10% none, 30% one, 40% two, 20% three
```

Example layout with 2 wings:
```
                  ######
                  #....#
     #############....#
     #...........#....#
     #...........######
     #...........#
     #...........#
     #############
          #....#
          #....#
          ######
```

### Stamping Into the World

`stamp_post_into_chunks()` writes the post's structure into chunk data:

1. Compute floor tiles from all room rectangles
2. Compute wall tiles (any non-floor adjacent to floor)
3. Select 8-14 door positions from perimeter walls (evenly distributed by angle)
4. Stamp floor, wall, and door tiles into chunks
5. Place stations inside the main room
6. Place post marker at center

### Station Layout

Stations are placed in rows from the top-left of the main room:

```
forge, forge, apothecary, apothecary, enchant_table, enchant_table,
writing_desk, writing_desk, workbench, workbench,
quest_board, quest_board, blacksmith, blacksmith,
inn, healer, healer, market, market
```

Station tiles block movement (you interact by walking adjacent to them), but do not block line of sight.

### Post Categories

Each post has a category for visual variety: `haven`, `market`, `shrine`, `farm`, `mine`, `tower`, `camp`, `exotic`, `fortress`, `default`.

---

## 7. Trading Posts (Legacy)

**File:** `shared/trading_post_database.gd`

The legacy trading post system places fixed locations across the map. These are being migrated to the NPC post system but still function.

### Trading Post Locations

Trading posts are defined with fixed coordinates in `TRADING_POSTS`:

**Core Zone (distance 0-30):** Haven (0,10), Crossroads (0,0), South Gate (0,-25), East Market (25,10), West Shrine (-25,10)

**Inner Zone (distance 30-75):** Northeast Farm (40,40), Northwest Mill (-40,40), Southeast Mine (45,-35), Southwest Grove (-45,-35), Northwatch (0,75), Eastern Camp (75,0), Western Refuge (-75,0), Southern Watch (0,-65), Northeast Tower (55,55), Northwest Inn (-55,55), Southeast Bridge (60,-50), Southwest Temple (-60,-50)

**Mid Zone (distance 75-175):** Frostgate (0,-100), Highland Post (0,150), Eastwatch (150,0), Westhold (-150,0), Southport (0,-150)

**Mid-Outer Zone (distance 175-300):** Far East Station (250,0), Far West Haven (-250,0), Deep South Port (0,-275), High North Peak (0,250), plus corner outposts

**Outer Zone (distance 300+):** Shadowmere (300,300), Inferno Outpost, and other endgame locations

Each trading post provides: quest board, market (player-to-player trading via Valor), Wits training, and recharging.

---

## 8. Dungeon System

**File:** `shared/dungeon_database.gd` (definitions), `server/server.gd` (runtime management)

### World Dungeons vs Player Instances

This distinction is critical and a common source of confusion:

**World Dungeons:**
- Map markers showing `D` tiles, visible to all players
- 150-200 active at any time (configurable via `MIN_WORLD_DUNGEONS` / `MAX_WORLD_DUNGEONS`)
- Have **no** `owner_peer_id` (or -1)
- Exist in `active_dungeons` dictionary on the server
- When a player enters, the world dungeon is marked `completed_at` and a personal instance is created
- Completed world dungeons despawn after 60 seconds (no players nearby)

**Player Instances:**
- Created when a player steps onto a `D` tile
- Have `owner_peer_id` set to the entering player's peer ID
- Private: only the owner (and their party) can access it
- Contain generated floors with encounters, treasures, traps, and a boss
- Despawn after the player completes or leaves

**Lifecycle:**
```
1. _check_dungeon_spawns() maintains 150-200 world dungeons
2. Player walks onto D tile
3. handle_dungeon_enter() called
4. World dungeon marked completed (completed_at = now)
5. _create_player_dungeon_instance() creates personal instance
6. Player explores floors, fights encounters
7. World dungeon despawns after DUNGEON_DESPAWN_DELAY (60s)
8. Player instance destroyed on completion/exit
```

### Server Constants

```gdscript
const MAX_ACTIVE_DUNGEONS = 300   # World + player instances combined
const DUNGEON_DESPAWN_DELAY = 60  # Seconds before completed world dungeons despawn
const MIN_WORLD_DUNGEONS = 150    # Minimum world dungeons maintained
const MAX_WORLD_DUNGEONS = 200    # Maximum world dungeons
```

### Dungeon Spawning

`_check_dungeon_spawns()` runs periodically to:
1. Count active world dungeons (exclude player instances)
2. Remove completed dungeons with no active players older than `DUNGEON_DESPAWN_DELAY`
3. Remove very old dungeons (24+ hours) with no players
4. Spawn new dungeons if below `MIN_WORLD_DUNGEONS`
5. Opportunistically spawn bonus dungeons up to `MAX_WORLD_DUNGEONS`

Spawn location is based on tier:
```gdscript
static func get_spawn_location_for_tier(tier: int) -> Vector2i:
    var min_distance = tier * 30      # T1 = 30, T5 = 150, T9 = 270
    var max_distance = tier * 60      # T1 = 60, T5 = 300, T9 = 540
    var angle = randf() * TAU
    var distance = randf_range(min_distance, max_distance)
    return Vector2i(int(cos(angle) * distance), int(sin(angle) * distance))
```

Additional random offset of +/-100 tiles is applied to spread dungeons out. Spawn validation ensures dungeons do not overlap with trading posts, safe zones, or existing dungeon locations.

### Dungeon Definitions

Each dungeon type in `DUNGEON_TYPES` specifies:

```gdscript
"orc_stronghold": {
    "name": "Orc Stronghold",
    "description": "A fortified camp where orcs prepare for raids.",
    "tier": 2,
    "min_level": 6,
    "max_level": 20,
    "monster_pool": ["Orc", "Hobgoblin", "Gnoll"],   # Regular encounter pool
    "boss": {
        "name": "Orc Warlord",             # Display name
        "monster_type": "Orc",              # Base monster type (for egg)
        "level_mult": 1.1,                  # Level multiplier
        "hp_mult": 2.2,                     # HP multiplier
        "attack_mult": 1.4,                 # Attack multiplier
        "abilities": ["War Cry", "Brutal Slam"]
    },
    "boss_egg": "Orc",                      # Guaranteed egg drop
    "floors": 4,                            # Number of floors
    "grid_size": 5,                         # BSP generation parameter
    "encounters_per_floor": 3,
    "monsters_per_floor": 4,
    "treasures_per_floor": 1,
    "egg_drops": ["Orc", "Hobgoblin"],      # Possible treasure eggs
    "material_drops": ["iron_ore", "copper_ore", "ragged_leather"],
    "cooldown_hours": 6,
    "spawn_weight": 40,                     # Relative spawn frequency
    "color": "#8B4513"                      # Map display color
}
```

### BSP Floor Generation

Each dungeon floor is generated using Binary Space Partitioning (BSP):

```gdscript
static func generate_floor_grid(dungeon_id, floor_num, is_boss_floor) -> Dictionary:
    # 1. Initialize grid with all WALL tiles
    # 2. BSP split the interior into partitions (3-4 levels deep)
    # 3. Carve rooms in each leaf partition
    # 4. Connect rooms with corridors (chain + loop)
    # 5. Place entrance (E) in a random corner's nearest room
    # 6. Place exit (>) or boss (B) in farthest room from entrance
    # 7. Place treasures ($) in small/dead-end rooms
    # 8. Place gathering resources (&) in unused rooms
    # Returns: {grid, rooms, entrance_pos, exit_pos}
```

Grid sizes vary: smaller for lower tiers, boss floors always use maximum size. The grid is a 2D array of `TileType` enum values.

### Dungeon Tile Types

```gdscript
enum TileType {
    EMPTY,       # Walkable '.'
    WALL,        # Impassable '#'
    ENTRANCE,    # Start 'E' (green)
    EXIT,        # Next floor '>' (yellow)
    ENCOUNTER,   # Monster '?' (red)
    TREASURE,    # Chest '$' (gold)
    BOSS,        # Boss 'B' (red)
    CLEARED,     # Done '.' (dim)
    RESOURCE     # Gathering '&' (cyan)
}
```

### Step Pressure System

Each floor has a step limit. Moving costs one step. Exceeding the limit causes exhaustion debuffs. Boss floors get 50% more steps:

```gdscript
const DUNGEON_STEP_LIMITS = {
    1: 100, 2: 95, 3: 90, 4: 85, 5: 80,
    6: 75, 7: 70, 8: 65, 9: 60
}
# Boss floor: limit * 1.5
```

### Trap System

Hidden traps are placed on empty tiles during floor generation:

| Trap Type | Weight | Effect |
|-----------|--------|--------|
| rust | 40% | Damages equipment |
| thief | 30% | Steals gold/items |
| teleport | 30% | Moves player to random location on floor |

Trap count per floor scales by tier: T1-2 get 1 trap, T3-4 get 2, T5-6 get 3, T7-9 get 4.

### Escape Scrolls

Consumable items that let players exit a dungeon immediately:

| Dungeon Tier | Scroll Type |
|-------------|-------------|
| T1-4 | Scroll of Escape |
| T5-7 | Scroll of Greater Escape |
| T8-9 | Scroll of Supreme Escape |

20% chance to drop from treasure chests inside dungeons.

---

## 9. Hotspots and Encounters

Hotspots are clusters of dangerous tiles with higher encounter rates and stronger monsters.

### How Hotspots Work

Hotspot generation uses a cluster-based system:

```gdscript
func _is_hotspot(x, y) -> bool:
    # Check all potential cluster centers within radius 5
    for cx in range(x - 5, x + 6):
        for cy in range(y - 5, y + 6):
            if _is_cluster_center(cx, cy):
                var cluster_radius = _get_cluster_radius(cx, cy)
                var dist = sqrt(float((x-cx)*(x-cx) + (y-cy)*(y-cy)))
                if dist <= cluster_radius:
                    return true
    return false

func _is_cluster_center(x, y) -> bool:
    # ~0.3% of tiles are cluster centers
    var hash_val = abs((x * 73 + y * 127) * 9311) % 1000
    return hash_val < 3

func _get_cluster_radius(x, y) -> float:
    # Each cluster spans 1-20 tiles (radius 0.5 to 2.5)
    var hash_val = abs((x * 41 + y * 83) * 5717) % 100
    return 0.5 + (hash_val / 100.0) * 2.0
```

### Hotspot Effects

- **Monster level multiplier:** 1.5x at the edge to 2.5x at the center of the cluster
- **Visual:** Passable tiles in hotspots display as red `!` on the map (intensity affects color: `#FF0000` at center, `#FF4500` at edges)
- **Purpose:** Players seeking fights can target hotspots for stronger monsters and better rewards

### Encounter Rates

Base encounter rates are defined per legacy terrain type:

| Terrain | Encounter Rate |
|---------|---------------|
| Plains | 10% |
| Forest | 20% |
| Mountains | 30% |
| Deep Forest | 35% |
| Desert | 35% |
| Swamp | 40% |
| Volcano | 60% |
| Dark Circle | 80% |

Safe zones (NPC posts, trading posts, enclosures) have 0% encounter rate.

---

## 10. Movement and Map Display

### Server-Side Movement

Movement is processed by the server when it receives a `move` message from the client:

```
1. Client sends: {"type": "move", "direction": "north"}
   (Direction maps to numpad: 8=N, 6=E, 2=S, 4=W, 7=NW, 9=NE, 1=SW, 3=SE, 5=stay)

2. Server calls world_system.move_player(current_x, current_y, direction)
   - Calculates new position
   - Clamps to world bounds (-2000 to 2000)
   - Checks if target tile blocks movement (via chunk_manager.get_tile())
   - Depleted gathering nodes are passable
   - Returns current position if blocked (cannot move there)

3. Server updates character position: character.x, character.y

4. Server checks new location:
   - Dungeon entrance (D tile)?
   - NPC post?
   - Trading post?
   - Merchant?
   - Random encounter?

5. Server sends response messages:
   - "location" — map display data for the area around player
   - "character_update" — updated position and stats
   - Additional messages based on what's at the location
```

### Numpad Direction Mapping

```
7=NW  8=N   9=NE
4=W   5=Stay 6=E
1=SW  2=S   3=SE
```

The `move_player()` function applies directional offsets:

```gdscript
match direction:
    1: new_x -= 1; new_y -= 1   # Southwest
    2: new_y -= 1                # South
    3: new_x += 1; new_y -= 1   # Southeast
    4: new_x -= 1                # West
    6: new_x += 1                # East
    7: new_x -= 1; new_y += 1   # Northwest
    8: new_y += 1                # North
    9: new_x += 1; new_y += 1   # Northeast
    5: pass                      # Stay (rest/search)
```

### Client-Side Map Display

The server calls `world_system.generate_map_display()` to produce the map BBCode sent to the client. The output includes:

1. **Location header** -- coordinates, terrain name, danger level, compass to nearest post
2. **Map grid** -- 23x23 tiles (radius 11) centered on the player

Map elements in priority order:
1. Player (`@` in yellow) -- always at center
2. Other players (first letter of name, or `*` if multiple; green for party, cyan for others)
3. Dungeons (`D` in dungeon-specific color)
4. Bounty targets (`!` in orange-red)
5. Player corpses (`X` in red)
6. Merchants (letter + color based on merchant type)
7. Hotspot tiles (`!` in red/orange gradient)
8. Depleted nodes (dim `,`)
9. Terrain tiles (character + color from `TILE_RENDER`)

Each tile is rendered as 2 characters wide (space + character) for even grid spacing:

```gdscript
line_parts.append("[color=%s] %s[/color]" % [color, char])
```

### Map Header Format

```
(50, 120) Forest
Lv50-60  NE Crossroads (127)
```

Format: `(x, y) TerrainName`, then `LvMin-Max CompassDirection PostName (distance)`.

At an NPC post: `PostName (x, y)` then `Safe`.

---

## 11. Line of Sight

The map uses Bresenham raycasting to determine which tiles are visible to the player.

### How LOS Works

```gdscript
func is_tile_visible(player_x, player_y, target_x, target_y) -> bool:
    # Trace a line from player to target using Bresenham's algorithm
    var points = bresenham_line(player_x, player_y, target_x, target_y)

    # Check intermediate points (skip player and target)
    for i in range(1, points.size() - 1):
        var tile = chunk_manager.get_tile(points[i].x, points[i].y)
        if tile.get("blocks_los", false):
            # Depleted gathering nodes don't block LOS
            if tile_type in GATHERABLE_TYPES and chunk_manager.is_node_depleted(...):
                continue
            return false  # Blocked!
    return true
```

Key points:
- The **target tile itself** is always visible even if it blocks LOS (you can see a wall, but not past it)
- **Depleted nodes** do not block LOS (the node is gone, you can see through)
- **Tiles outside LOS** are rendered as empty space (not fog of war -- just blank)
- Vision radius is `DEFAULT_VISION_RADIUS = 11` (or `BLIND_VISION_RADIUS = 2` for blind status)

### Tiles That Block LOS

From `TILE_RENDER`:
- `stone` -- blocks
- `tree` -- blocks
- `ore_vein` -- blocks
- `wall` -- blocks
- `void` -- blocks

All other tiles (including water, dense_brush, doors, stations) do **not** block LOS.

---

## 12. A* Pathfinding and Road System

**Location:** `shared/world_system.gd` (from line ~1450)

Roads connect NPC posts, creating walkable paths between settlements. Merchant NPCs follow these roads.

### Path Computation

On server startup (or when a new player post is built), roads are computed between connected posts using A* pathfinding:

```gdscript
func compute_path_between(start_x, start_y, end_x, end_y, permissive) -> Array:
    # Standard A* with 4-directional movement (N, S, E, W only)
    # Returns array of Vector2i waypoints
    # Max 50,000 nodes explored before giving up
```

**Walkability for paths** (strict mode, NPC-to-NPC):
- Depleted gathering nodes -- walkable (player cleared them)
- Structure tiles (floor, door, tower, storage, post_marker) -- walkable
- Modified empty tiles -- walkable
- All other tiles -- not walkable

**Permissive mode** (player posts): any non-blocking tile is walkable.

### Road Stamping

Path waypoints are stamped as `path` tiles (`:` character) into the chunk system. Path tiles are non-blocking and non-LOS-blocking.

### Path Data Persistence

Computed paths are saved to `user://data/world/paths.json` to avoid recomputation on server restart:

```json
{
    "paths": { "postA->postB": [{"x": 10, "y": 20}, ...] },
    "graph": { "postA": ["postB", "postC"], ... },
    "post_positions": { "postA": {"x": 0, "y": 0}, ... }
}
```

---

## 13. Merchant NPCs

Merchants are virtual NPCs that patrol roads between connected NPC posts.

### Circuit Assignment

One merchant is assigned per road segment between two connected posts:

```gdscript
func compute_merchant_circuits(valid_post_keys):
    # For each connected pair of posts:
    #   Create a 2-post circuit [postA, postB]
    #   Precompute waypoints along the road between them
    #   Merchant walks A -> B -> A -> B ...
```

### Position Calculation

Merchant positions are computed mathematically from the current time (no actual entity moves):

```gdscript
const MERCHANT_SPEED = 0.02    # 1 tile every 50 seconds
const MERCHANT_REST_TIME = 300  # 5 minutes rest at each post

func _get_merchant_position(merchant_idx, current_time) -> Dictionary:
    # Calculate total cycle time: travel + rest for each segment
    # Use fmod(current_time + offset, total_cycle_time) for position
    # Return {x, y, is_resting, at_post, segment_idx, destination_key}
```

Each merchant has a time offset (`merchant_idx * 137`) to desynchronize their cycles.

### Merchant Cache

Since computing merchant positions for every tile is expensive, positions are cached for 30 seconds:

```gdscript
const MERCHANT_CACHE_DURATION = 30.0
var _merchant_cache: Dictionary = {}  # "x,y" -> [merchant_indices]
```

Merchants resting inside NPC posts are excluded from the cache (not visible on the road).

### Elite Merchants

Merchants assigned to roads longer than 100 waypoints are flagged as "elite" and may carry better inventory.

---

## 14. Player Buildings (Enclosures)

Players can build structures on the world map to create safe zones and outposts.

### Building Process

1. Player enters building mode at a valid location
2. Selects what to build: wall, tower, storage, guard post
3. Server validates placement via `handle_build_place()`
4. Structure tile is written to chunk data
5. Interior tiles marked with `enclosure_owner` for safe zone detection

### Enclosure Properties

- **Safe zone:** Interior tiles with `enclosure_owner` set suppress encounters
- **Visibility:** Structures appear on the map for all players
- **Post slots:** Additional enclosures require the `post_slots` house upgrade
- **Named posts:** Players can name their enclosures; compass hints point other players toward them

### Structure Tiles

| Type | Tile | Effect |
|------|------|--------|
| Wall | `#` | Blocks movement and LOS |
| Tower | `^` | Boosts nearby guards; gold if active, white otherwise |
| Storage | `C` | Accessible only by owner |
| Guard | `G` | NPC guard; green if active, gray if empty |

### Road Connections

When a player builds an enclosure, a road is computed connecting it to the nearest NPC post using permissive A* pathfinding (any non-blocking tile is walkable).

---

## 15. Modifying the World

### To Change Terrain Generation

Edit `world_system.gd`:

1. **Change density:** Modify the density formula in `generate_tile()` (currently 50-70% based on distance)
2. **Change distribution:** Adjust `NODE_WEIGHTS` constant to change relative frequency of node types
3. **Change water:** Modify `_is_water_tile_generated()` thresholds or noise parameters
4. **Change tier boundaries:** Edit `TIER_ZONES` constant

**Warning:** Changing generation affects all unmodified tiles. Modified tiles (in chunk files) are unaffected. If you change generation significantly, consider a map wipe.

### To Add a New Terrain Type

1. Add tile definition to `TILE_RENDER` in `world_system.gd`:
   ```gdscript
   "lava": {"char": "~", "color": "#FF4500", "blocks_move": true, "blocks_los": false},
   ```
2. Add to `NODE_WEIGHTS` if it should be a naturally occurring node (adjust `TOTAL_NODE_WEIGHT`)
3. Add detection function:
   ```gdscript
   func is_lava_tile(x, y) -> bool:
       if chunk_manager:
           return chunk_manager.get_tile(x, y).get("type", "") == "lava"
       return false
   ```
4. If gatherable, add to `GATHERABLE_TYPES` and `NODE_TO_JOB`
5. Add to `_tile_to_terrain()` for legacy Terrain enum mapping
6. Handle in server movement logic (block movement? trigger effect?)
7. Update client map rendering if special rendering is needed

### To Add a New Dungeon Type

1. Add definition to `DUNGEON_TYPES` in `dungeon_database.gd`:
   ```gdscript
   "new_dungeon_id": {
       "name": "Display Name",
       "description": "Description text.",
       "tier": 3,
       "min_level": 20,
       "max_level": 40,
       "monster_pool": ["MonsterA", "MonsterB"],
       "boss": {
           "name": "Boss Display Name",
           "monster_type": "BaseMonsterType",
           "level_mult": 1.15,
           "hp_mult": 2.5,
           "attack_mult": 1.5,
           "abilities": ["Ability1", "Ability2"]
       },
       "boss_egg": "BaseMonsterType",
       "floors": 5,
       "grid_size": 5,
       "encounters_per_floor": 3,
       "monsters_per_floor": 4,
       "treasures_per_floor": 1,
       "egg_drops": ["MonsterA"],
       "material_drops": ["material1", "material2"],
       "cooldown_hours": 12,
       "spawn_weight": 30,
       "color": "#HEXCOLOR"
   }
   ```
2. The dungeon will automatically be eligible for world spawning -- `_check_dungeon_spawns()` picks randomly from all `DUNGEON_TYPES` keys.
3. Boss monster must exist in `monster_database.gd`.
4. Material drops must exist in `drop_tables.gd`.

### To Add a New NPC Post Station

1. Add tile definition to `TILE_RENDER` in `world_system.gd`
2. Add to the stations array in `_place_stations()` in `npc_post_database.gd`
3. Add safe zone handling in `is_safe_zone()` if needed
4. Add to `_tile_to_terrain()` mapping (return `Terrain.TRADING_POST` for safe)
5. Handle interaction in `server/server.gd` movement logic

### To Modify Dungeon Floor Generation

Edit `dungeon_database.gd`:

- **Room count:** Adjust `max_depth` in BSP split (3-4 levels = 4-8 rooms)
- **Room sizes:** Modify `_carve_room()` function
- **Corridor style:** Edit `_connect_rooms()` for different corridor shapes
- **Special tiles:** Add new `TileType` enum values and place them during generation
- **Step limits:** Edit `DUNGEON_STEP_LIMITS` constant
- **Trap counts:** Edit `TRAPS_PER_FLOOR` constant

### Common Mistakes

1. **Forgetting to handle the chunk system:** Always check `if chunk_manager:` before using it; fall back to legacy when not available.
2. **Modifying generation without considering persistence:** Changed tiles in chunk files will not reflect new generation logic. Consider how existing worlds will be affected.
3. **Stacking dungeons on the same tile:** Always check `existing_coords` when creating world dungeons. Both `_create_world_dungeon()` and `_create_world_dungeon_near()` do this.
4. **Blocking tiles in wrong category:** Movement blocking (`blocks_move`) and LOS blocking (`blocks_los`) are independent. Water blocks movement but not LOS. Trees block both. Stations block movement but not LOS.
5. **Forgetting to update `_tile_to_terrain()`:** The legacy `Terrain` enum is still used by encounter rate calculations and location descriptions. New tile types need a mapping.
