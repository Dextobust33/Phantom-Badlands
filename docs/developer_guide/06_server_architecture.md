# 06 -- Server Architecture

This guide covers the two files that make up the entire Phantom Badlands server:
`server/server.gd` (~21,500 lines) and `server/persistence_manager.gd` (~1,700 lines).
After reading it you should be able to trace how a client message travels from TCP socket
to game logic and back, add new handlers, and understand how player data is stored.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Server Startup -- _ready()](#2-server-startup----_ready)
3. [The Main Loop -- _process(delta)](#3-the-main-loop----_processdelta)
4. [Connection Management](#4-connection-management)
5. [Message Routing -- handle_message()](#5-message-routing----handle_message)
6. [Player Data Management](#6-player-data-management)
7. [Combat Flow on the Server](#7-combat-flow-on-the-server)
8. [World Management](#8-world-management)
9. [Persistence -- persistence_manager.gd](#9-persistence----persistence_managergd)
10. [Security Features](#10-security-features)
11. [Server Handler Pattern](#11-server-handler-pattern)
12. [Adding a New Server Handler -- Step by Step](#12-adding-a-new-server-handler----step-by-step)
13. [Finding Things in server.gd](#13-finding-things-in-servergd)

---

## 1. Overview

The server is a single Godot scene (`server/server.tscn`) with a single script
(`server/server.gd`) attached to the root `Control` node. That one script is the
**entire** server -- all game logic, all client connections, all message routing, all
combat, all persistence coordination, all world management. There are no other server-side
scripts besides the persistence layer.

```
server/server.tscn
└── Control (root)
    ├── server.gd          ← THE server (~21,500 lines)
    ├── VBox/              ← Admin panel UI
    │   ├── StatusRow/PlayerCountLabel
    │   ├── PlayerList     (RichTextLabel)
    │   ├── ServerLog      (RichTextLabel)
    │   ├── ButtonRow/     (Restart, PendingUpdate, CancelUpdate)
    │   ├── BroadcastRow/  (Input field + Send button)
    │   └── WipeRow/       (Respawn, MapSeed, FullWipe buttons)
    ├── ConfirmDialog
    ├── WipeConfirmDialog
    └── WipeFinalDialog
```

The admin panel is a simple GUI that shows connected players, a scrolling log, and
buttons for broadcast messages, server restarts, and various wipe operations. It is not
required for the server to function -- the server runs headless just fine for production.

### Core Principle: Server-Authoritative

The server validates **everything**. Clients are display terminals. They send requests
("I want to move north", "I want to attack") and the server decides what happens.
Clients never modify game state directly -- they receive the result and render it.

### Shared Scripts

Several scripts live in `shared/` and are loaded by both client and server:

| Script | What the Server Uses It For |
|--------|-----------------------------|
| `shared/character.gd` | The `Character` class -- all player stats, inventory, equipment |
| `shared/combat_manager.gd` | The `CombatManager` -- turn-based combat engine |
| `shared/world_system.gd` | `WorldSystem` -- terrain generation, movement validation, merchants |
| `shared/chunk_manager.gd` | `ChunkManager` -- 32x32 tile chunks, player-built structures |
| `shared/monster_database.gd` | `MonsterDatabase` -- monster stats, variant generation |
| `shared/drop_tables.gd` | Loot tables, gathering catches, salvage values |
| `shared/quest_database.gd` | Quest definitions, daily quest generation |
| `shared/quest_manager.gd` | Quest progress tracking, turn-in validation |
| `shared/dungeon_database.gd` | Dungeon types, floor layouts, boss definitions |
| `shared/crafting_database.gd` | Crafting recipes, material requirements |
| `shared/npc_post_database.gd` | NPC settlement layouts, station types |
| `shared/trading_post_database.gd` | Trading post categories, shapes, colors |
| `shared/titles.gd` | Title/rank system definitions |

These scripts are loaded as constants at the top of `server.gd`:

```gdscript
const PersistenceManagerScript = preload("res://server/persistence_manager.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const QuestDatabaseScript = preload("res://shared/quest_database.gd")
const QuestManagerScript = preload("res://shared/quest_manager.gd")
const TradingPostDatabaseScript = preload("res://shared/trading_post_database.gd")
const TitlesScript = preload("res://shared/titles.gd")
const CraftingDatabaseScript = preload("res://shared/crafting_database.gd")
const DungeonDatabaseScript = preload("res://shared/dungeon_database.gd")
const NpcPostDatabaseScript = preload("res://shared/npc_post_database.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
```

---

## 2. Server Startup -- _ready()

When the server scene loads, `_ready()` runs. Here is the full startup sequence, in order:

### Step 1: Parse Command-Line Arguments

```gdscript
var args = OS.get_cmdline_args()
for arg in args:
    if arg.begins_with("--port="):
        var port_str = arg.substr(7)
        if port_str.is_valid_int():
            PORT = int(port_str)
```

The default port is 9080. You can override it with `--port=XXXX` when launching.

### Step 2: Initialize Persistence

```gdscript
persistence = PersistenceManagerScript.new()
add_child(persistence)
```

This creates the `PersistenceManager` node, which immediately loads all data files
from `user://data/` in its own `_ready()`:

- `accounts.json` -- usernames, hashed passwords, character slots
- `leaderboard.json` -- top 100 dead characters (permadeath game)
- `realm_state.json` -- global state like the realm treasury
- `corpses.json` -- lootable dead player remains on the map
- `houses.json` -- Sanctuary (house) data per account
- `player_tiles.json` -- player-built structures
- `player_posts.json` -- player enclosure metadata
- `market_data.json` -- open market listings
- `ban_list.json` -- banned IP addresses
- `guards.json` -- hired guard entities

### Step 3: Initialize World Systems

```gdscript
chunk_manager = ChunkManagerScript.new()
add_child(chunk_manager)
chunk_manager.load_world_seed()

world_system = WorldSystem.new()
add_child(world_system)

# Bidirectional link
world_system.chunk_manager = chunk_manager
chunk_manager.terrain_generator = world_system
```

The `ChunkManager` handles the 32x32 tile chunk system. It loads (or generates) a
world seed, which the `WorldSystem` uses for deterministic procedural terrain.

### Step 4: Generate or Load NPC Posts

```gdscript
var npc_posts = chunk_manager.load_npc_posts()
if npc_posts.is_empty():
    npc_posts = NpcPostDatabaseScript.generate_posts(chunk_manager.world_seed)
    chunk_manager.save_npc_posts(npc_posts)

# Stamp post layouts into chunks (walls, floors, stations)
for post in npc_posts:
    NpcPostDatabaseScript.stamp_post_into_chunks(post, chunk_manager)

# Compute A* road paths between posts
_initialize_road_paths(npc_posts)
chunk_manager.save_dirty_chunks()
```

NPC posts are settlements scattered across the map with stations like blacksmiths,
healers, and trading posts. Roads connect them for merchant travel.

### Step 5: Rebuild Player Structures

```gdscript
chunk_manager.load_depleted_nodes()
_rebuild_all_player_enclosures()
active_guards = persistence.load_guards()
_update_guard_cache()
```

Player-built walls, towers, and enclosures are reconstructed from persisted tile data.
Guards are loaded and their patrol caches rebuilt.

### Step 6: Initialize Game Systems

```gdscript
monster_db = MonsterDatabase.new()
add_child(monster_db)

combat_mgr = CombatManager.new()
add_child(combat_mgr)

drop_tables = DropTablesScript.new()
add_child(drop_tables)
combat_mgr.set_drop_tables(drop_tables)
combat_mgr.set_monster_database(monster_db)

quest_db = QuestDatabaseScript.new()
add_child(quest_db)
quest_mgr = QuestManagerScript.new()
add_child(quest_mgr)

trading_post_db = TradingPostDatabaseScript.new()
add_child(trading_post_db)
```

Each system is a `Node` added as a child of the server's root control. This is how
Godot manages object lifetimes -- child nodes are freed when the parent is freed.

### Step 7: Load Balance Config and Start Listening

```gdscript
load_balance_config()
combat_mgr.set_balance_config(balance_config)
monster_db.set_balance_config(balance_config)

var error = server.listen(PORT)
if error != OK:
    print("ERROR: Failed to start server on port %d" % PORT)
    return

log_message("Server started successfully!")
log_message("Listening on port: %d" % PORT)
```

`balance_config` is loaded from `server/balance_config.json` and contains all the
tuning parameters for combat -- lethality weights, ability modifiers, XP curves, etc.

### Step 8: Spawn Initial Dungeons

```gdscript
_check_dungeon_spawns()
```

The server maintains 150-200 world dungeons at all times. This initial call seeds
them across the map.

### Step 9: Connect Admin Panel Signals

```gdscript
restart_button.pressed.connect(_on_restart_button_pressed)
confirm_dialog.confirmed.connect(_on_restart_confirmed)
broadcast_button.pressed.connect(_on_broadcast_button_pressed)
# ... etc for wipe buttons
```

Standard Godot signal connections for the admin panel UI buttons.

---

## 3. The Main Loop -- _process(delta)

`_process(delta)` is called every frame by Godot's main loop. The server runs at the
engine's default tick rate (typically 60 FPS unless throttled). Here is what happens
each frame, in order:

### 3a. Timers

Several periodic systems are driven by delta accumulators:

```gdscript
# Auto-save all active characters every 60 seconds
auto_save_timer += delta
if auto_save_timer >= AUTO_SAVE_INTERVAL:       # 60.0
    auto_save_timer = 0.0
    save_all_active_characters()

# Refresh admin panel player list every 3 minutes
player_list_update_timer += delta
if player_list_update_timer >= PLAYER_LIST_UPDATE_INTERVAL:  # 180.0
    player_list_update_timer = 0.0
    update_player_list()
```

Other timer-driven systems (all work the same way):

| Timer | Interval | What It Does |
|-------|----------|--------------|
| `auto_save_timer` | 60s | Saves all active character data to disk |
| `player_list_update_timer` | 180s | Refreshes the admin panel player list |
| `merchant_update_timer` | 10s | Checks if merchants moved, sends map updates |
| `dungeon_spawn_timer` | 30s | Maintains 150-200 world dungeons |
| `guard_decay_timer` | 60s | Ticks guard food timers, removes unfed guards |
| `wall_decay_timer` | 300s | Decays unattended player walls after 72h |
| `security_check_timer` | 5s | Kicks stale unauthenticated connections |
| `_road_check_timer` | varies | Tries to connect unconnected post pairs |
| `_merchant_check_timer` | varies | Checks merchant arrivals at posts |

### 3b. World Updates

```gdscript
# Move traveling merchants along their routes
world_system.update_merchants(delta)

# Process gathering node respawns
chunk_manager.process_node_respawns(delta)

# Geological events (resource area respawning)
var geo_events = chunk_manager.process_geological_events(delta)
for event in geo_events:
    _broadcast_geological_event(event)
```

### 3c. Pending Update Countdown

If an admin initiates a pending update (graceful shutdown), the countdown ticks here
and broadcasts warnings at specific intervals before executing the shutdown.

### 3d. Accept New Connections

```gdscript
if server.is_connection_available():
    var peer = server.take_connection()
    # ... security checks and peer registration (see Section 4)
```

### 3e. Poll Existing Connections

```gdscript
var disconnected_peers = []
for peer_id in peers.keys():
    var peer_data = peers[peer_id]
    var connection = peer_data.connection

    # CRITICAL: Must call poll() to advance TCP state
    connection.poll()

    if connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
        disconnected_peers.append(peer_id)
        continue

    var available = connection.get_available_bytes()
    if available > 0:
        var data = connection.get_data(available)
        if data[0] == OK:
            var message = data[1].get_string_from_utf8()
            peer_data.buffer += message

            # Security: buffer overflow check
            if peer_data.buffer.length() > MAX_BUFFER_BYTES:  # 64KB
                disconnected_peers.append(peer_id)
                continue

            process_buffer(peer_id)

# Clean up disconnected peers
for peer_id in disconnected_peers:
    handle_disconnect(peer_id)
```

**Important Godot detail:** You MUST call `connection.poll()` every frame on each
`StreamPeerTCP`. Without it, the connection's internal state machine does not advance
and you will never receive data. This is a common source of bugs when working with
raw TCP in Godot.

### 3f. Flush Batched Updates

At the end of `_process()`, three network optimization systems flush their queues:

```gdscript
# Delta character updates: one send per peer per frame max
if USE_DELTA_UPDATES:
    _flush_pending_character_updates()

# Periodic forced full update (desync safety net, every 60s)
if USE_DELTA_UPDATES:
    full_update_timer += delta
    if full_update_timer >= FULL_UPDATE_INTERVAL:
        full_update_timer = 0.0
        for pid in characters:
            force_full_character_update(pid)

# Batched map updates (every 300ms)
if USE_BROADCAST_THROTTLE:
    map_update_flush_timer += delta
    if map_update_flush_timer >= MAP_UPDATE_FLUSH_INTERVAL:
        map_update_flush_timer = 0.0
        _flush_dirty_map_updates()
```

These prevent flooding clients with updates. For example, if a handler calls
`send_character_update()` three times in one frame, only one actual message is sent.

---

## 4. Connection Management

### 4a. Accepting New Connections

When a TCP client connects, the server runs a gauntlet of security checks before
accepting:

```gdscript
if server.is_connection_available():
    var peer = server.take_connection()
    var peer_ip = peer.get_connected_host()
    var current_time = Time.get_unix_time_from_system()

    # 1. Is this IP banned?
    if persistence.is_ip_banned(peer_ip):
        peer.disconnect_from_host()
        return

    # 2. Is the server full? (200 max)
    if peers.size() >= MAX_TOTAL_CONNECTIONS:
        peer.disconnect_from_host()
        return

    # 3. Is this IP connecting too fast? (5s cooldown)
    if ip_connection_times.has(peer_ip):
        if current_time - ip_connection_times[peer_ip] < CONNECTION_RATE_LIMIT:
            peer.disconnect_from_host()
            return

    # 4. Too many connections from this IP? (3 max)
    if ip_connection_counts.get(peer_ip, 0) >= MAX_CONNECTIONS_PER_IP:
        peer.disconnect_from_host()
        return

    # Accept the connection
    var peer_id = next_peer_id
    next_peer_id += 1

    peers[peer_id] = {
        "connection": peer,           # The StreamPeerTCP object
        "authenticated": false,        # Not logged in yet
        "account_id": "",             # Filled on login
        "username": "",               # Filled on login
        "character_name": "",         # Filled on character select
        "buffer": "",                 # Incoming data buffer
        "connect_time": current_time, # For auth timeout
        "ip": peer_ip                 # For security tracking
    }

    # Track this IP's connection
    ip_connection_times[peer_ip] = current_time
    ip_connection_counts[peer_ip] = ip_connection_counts.get(peer_ip, 0) + 1

    # Send welcome message
    send_to_peer(peer_id, {
        "type": "welcome",
        "message": "Welcome to Phantom Badlands!",
        "server_version": "0.1.0"
    })
```

### 4b. The `peers` Dictionary

The `peers` dictionary is the central connection registry. It maps `peer_id` (an
incrementing integer) to a dictionary of connection state:

```gdscript
var peers = {}  # peer_id → connection state dictionary
```

Every function that deals with a specific client takes `peer_id` as its first
argument and looks up the connection in `peers`.

### 4c. Authentication Flow

The full lifecycle from connection to playing:

```
1. Client connects        → Server sends {"type": "welcome"}
2. Client sends "login"   → Server validates against accounts.json
   or "register"          → On success: peers[peer_id].authenticated = true
3. Client sends           → Server sends house data
   "house_request"        → Client shows Sanctuary screen
4. Client sends           → Server sends character list
   "list_characters"      → Client shows character select
5. Client sends           → Server loads Character object from file
   "select_character"     → characters[peer_id] = loaded_character
                          → Player is now in the game world
```

Only `"login"` and `"register"` messages are accepted from unauthenticated peers.
All other message types are silently dropped:

```gdscript
# In handle_message() -- all non-auth messages require authentication
# (enforced by individual handlers checking peers[peer_id].authenticated)
```

### 4d. Disconnect Handling

`handle_disconnect()` is thorough -- it must clean up every system the player was
participating in. Here is the sequence:

```gdscript
func handle_disconnect(peer_id: int):
    # 1. Save combat state for reconnect recovery
    if combat_mgr.is_in_combat(peer_id) and characters.has(peer_id):
        var character = characters[peer_id]
        if character.current_hp > 0:
            character.saved_combat_state = combat_mgr.serialize_combat_state(peer_id)

    # 2. Save character to disk (includes combat state)
    save_character(peer_id)

    # 3. End combat session (no loss counted -- state was saved)
    if combat_mgr.is_in_combat(peer_id):
        combat_mgr.end_combat(peer_id, false)

    # 4. Clean up EVERY system this player was part of:
    #    - Pending flocks, wishes, scrolls
    #    - Rate limit state, combat cooldowns
    #    - Active crafts (refund materials)
    #    - Active gathering/harvest sessions
    #    - Merchant position tracking
    #    - Watch relationships (spectating)
    #    - Party membership
    #    - Active trades
    #    - Title holder tracking
    #    - Dungeon active_players list
    pending_flocks.erase(peer_id)
    flock_counts.erase(peer_id)
    pending_wishes.erase(peer_id)
    pending_scroll_use.erase(peer_id)
    combat_command_cooldown.erase(peer_id)
    peer_rate_limits.erase(peer_id)
    peer_type_cooldowns.erase(peer_id)
    at_player_station.erase(peer_id)
    active_gathering.erase(peer_id)
    active_harvests.erase(peer_id)
    gathering_cooldown.erase(peer_id)
    build_cooldown.erase(peer_id)

    # Refund crafting materials if mid-craft
    if active_crafts.has(peer_id):
        var craft = active_crafts[peer_id]
        var consumed = craft.get("consumed_materials", {})
        if characters.has(peer_id) and not consumed.is_empty():
            for mat_id in consumed:
                characters[peer_id].add_crafting_material(mat_id, consumed[mat_id])
        active_crafts.erase(peer_id)

    cleanup_watcher_on_disconnect(peer_id)
    _cleanup_party_on_disconnect(peer_id)

    if active_trades.has(peer_id):
        _cancel_trade(peer_id, "Player disconnected.")

    _update_title_holders_on_logout(peer_id)

    # 5. Clean up dungeon tracking (but preserve state for reconnect)
    if characters.has(peer_id):
        var character = characters[peer_id]
        if character.in_dungeon:
            var instance_id = character.current_dungeon_id
            if active_dungeons.has(instance_id):
                active_dungeons[instance_id].active_players.erase(peer_id)

    # 6. Remove from active state
    characters.erase(peer_id)
    last_sent_character_state.erase(peer_id)
    pending_char_updates.erase(peer_id)
    map_update_dirty.erase(peer_id)
    peers.erase(peer_id)

    # 7. Decrement IP connection count
    # ... (tracked for per-IP connection limits)

    # 8. Update admin UI and broadcast departure
    update_player_list()
    if char_name != "":
        broadcast_chat("[color=#FF0000]%s has left the realm.[/color]" % char_name)
```

The key insight is that **every** dictionary that might hold state for a peer must
be cleaned up here. When you add a new system that tracks per-player state, you must
add cleanup code to `handle_disconnect()`.

---

## 5. Message Routing -- handle_message()

The `handle_message()` function is the heart of the server, located around line 970.
It is a massive `match` statement that routes over 120 message types to their handlers.

### 5a. Structure

```gdscript
func handle_message(peer_id: int, message: Dictionary):
    var msg_type = message.get("type", "")

    # Security: Token bucket rate limiting
    if not _check_rate_limit(peer_id, msg_type):
        return  # Silently drop

    match msg_type:
        # === Account Management ===
        "register":            handle_register(peer_id, message)
        "login":               handle_login(peer_id, message)
        "list_characters":     handle_list_characters(peer_id)
        "select_character":    handle_select_character(peer_id, message)
        "create_character":    handle_create_character(peer_id, message)
        "delete_character":    handle_delete_character(peer_id, message)
        "logout_character":    handle_logout_character(peer_id)
        "logout_account":      handle_logout_account(peer_id)
        "change_password":     handle_change_password(peer_id, message)

        # === Leaderboards ===
        "get_leaderboard":              handle_get_leaderboard(peer_id, message)
        "get_leaderboard_death":        handle_get_leaderboard_death(peer_id, message)
        "get_monster_kills_leaderboard": handle_get_monster_kills_leaderboard(peer_id, message)
        "get_trophy_leaderboard":       handle_get_trophy_leaderboard(peer_id)

        # === Communication ===
        "chat":            handle_chat(peer_id, message)
        "private_message": handle_private_message(peer_id, message)

        # === Movement & Exploration ===
        "move":        handle_move(peer_id, message)
        "hunt":        handle_hunt(peer_id)
        "rest":        handle_rest(peer_id)
        "teleport":    handle_teleport(peer_id, message)

        # === Combat ===
        "combat":           handle_combat_command(peer_id, message)
        "combat_use_item":  handle_combat_use_item(peer_id, message)
        "wish_select":      handle_wish_select(peer_id, message)
        "continue_flock":   handle_continue_flock(peer_id)

        # === Inventory ===
        "inventory_use":     handle_inventory_use(peer_id, message)
        "inventory_equip":   handle_inventory_equip(peer_id, message)
        "inventory_unequip": handle_inventory_unequip(peer_id, message)
        "inventory_discard": handle_inventory_discard(peer_id, message)
        "inventory_sort":    handle_inventory_sort(peer_id, message)
        "inventory_lock":    handle_inventory_lock(peer_id, message)
        "inventory_salvage": handle_inventory_salvage(peer_id, message)
        # ... auto-salvage, home stones, target farm, etc.

        # === Merchant & Trading Post ===
        "merchant_sell":            handle_merchant_sell(peer_id, message)
        "merchant_buy":             handle_merchant_buy(peer_id, message)
        "merchant_gamble":          handle_merchant_gamble(peer_id, message)
        "merchant_leave":           handle_merchant_leave(peer_id)
        "trading_post_shop":        handle_trading_post_shop(peer_id)
        "trading_post_quests":      handle_trading_post_quests(peer_id)
        "trading_post_leave":       handle_trading_post_leave(peer_id)

        # === Quests ===
        "quest_accept":   handle_quest_accept(peer_id, message)
        "quest_abandon":  handle_quest_abandon(peer_id, message)
        "quest_turn_in":  handle_quest_turn_in(peer_id, message)
        "get_quest_log":  handle_get_quest_log(peer_id)

        # === Companions ===
        "activate_companion":  handle_activate_companion(peer_id, message)
        "dismiss_companion":   handle_dismiss_companion(peer_id)
        "release_companion":   handle_release_companion(peer_id, message)
        "toggle_egg_freeze":   handle_toggle_egg_freeze(peer_id, message)

        # === Gathering & Crafting ===
        "gathering_start":         handle_gathering_start(peer_id, message)
        "gathering_choice":        handle_gathering_choice(peer_id, message)
        "gathering_end":           handle_gathering_end(peer_id, message)
        "craft_list":              handle_craft_list(peer_id, message)
        "craft_item":              handle_craft_item(peer_id, message)
        "craft_challenge_answer":  handle_craft_challenge_answer(peer_id, message)

        # === Building ===
        "build_place":     handle_build_place(peer_id, message)
        "build_demolish":  handle_build_demolish(peer_id, message)
        "guard_hire":      handle_guard_hire(peer_id, message)
        "guard_feed":      handle_guard_feed(peer_id, message)

        # === Dungeons ===
        "dungeon_enter":  handle_dungeon_enter(peer_id, message)
        "dungeon_move":   handle_dungeon_move(peer_id, message)
        "dungeon_exit":   handle_dungeon_exit(peer_id)
        "dungeon_rest":   handle_dungeon_rest(peer_id, message)

        # === House (Sanctuary) ===
        "house_request":   handle_house_request(peer_id)
        "house_upgrade":   handle_house_upgrade(peer_id, message)
        "house_fusion":    handle_house_fusion(peer_id, message)

        # === Trading (Player-to-Player) ===
        "trade_request":   handle_trade_request(peer_id, message)
        "trade_offer":     handle_trade_offer(peer_id, message)
        "trade_ready":     handle_trade_ready(peer_id)
        "trade_cancel":    handle_trade_cancel(peer_id)

        # === Open Market ===
        "market_browse":      handle_market_browse(peer_id, message)
        "market_list_item":   handle_market_list_item(peer_id, message)
        "market_buy":         handle_market_buy(peer_id, message)
        "market_my_listings": handle_market_my_listings(peer_id, message)

        # === Party ===
        "party_invite":               handle_party_invite(peer_id, message)
        "party_invite_response":      handle_party_invite_response(peer_id, message)
        "party_disband":              handle_party_disband(peer_id)
        "party_leave":                handle_party_leave(peer_id)

        # === GM/Admin Commands ===
        "gm_setlevel":       handle_gm_setlevel(peer_id, message)
        "gm_godmode":        handle_gm_godmode(peer_id)
        "gm_giveitem":       handle_gm_giveitem(peer_id, message)
        "gm_teleport":       handle_gm_teleport(peer_id, message)
        "gm_banip":          handle_gm_banip(peer_id, message)
        "gm_unbanip":        handle_gm_unbanip(peer_id, message)
        # ... 15+ more GM commands

        _:
            pass  # Unknown message type, silently ignored
```

The above is a condensed excerpt. The actual match statement has ~120+ cases.
The `_:` fallthrough at the end silently drops unknown message types.

### 5b. Message Buffer Processing

Before messages reach `handle_message()`, they go through `process_buffer()`:

```gdscript
func process_buffer(peer_id: int):
    var peer_data = peers[peer_id]
    var buffer = peer_data.buffer
    var messages_this_frame = 0

    while "\n" in buffer:
        var newline_pos = buffer.find("\n")
        var message_str = buffer.substr(0, newline_pos)
        buffer = buffer.substr(newline_pos + 1)

        # Security: max 10 messages per peer per frame
        messages_this_frame += 1
        if messages_this_frame > MAX_MESSAGES_PER_FRAME:
            break

        # Security: drop messages over 32KB
        if message_str.length() > MAX_SINGLE_MESSAGE_BYTES:
            continue

        var json = JSON.new()
        var error = json.parse(message_str)
        if error == OK:
            handle_message(peer_id, json.data)

    peer_data.buffer = buffer
```

The protocol is simple: JSON messages delimited by newlines. The buffer accumulates
raw bytes until a newline is found, then each complete line is parsed as JSON.

**Note on compression:** When `USE_COMPRESSION` is enabled, the client sends using
binary framing instead of newline-delimited JSON. The server's `send_to_peer()` uses
the same binary framing for responses. However, client-to-server messages still use
the newline protocol (compression is primarily for the larger server-to-client payloads).

### 5c. Message Categories with Approximate Line Ranges

To help navigate `server.gd`, here are the major sections:

| Section | Approximate Lines | Description |
|---------|------------------|-------------|
| Variables & constants | 1-234 | All `var` and `const` declarations |
| `_ready()` | 235-378 | Server startup |
| Admin panel handlers | 379-700 | Restart, wipe, broadcast UI |
| `_process()` | 742-937 | Main loop |
| `process_buffer()` | 939-968 | Message parsing |
| `handle_message()` | 970-1369 | Message routing (the big match) |
| Account handlers | 1370-2160 | Login, register, character select/create/delete |
| Chat handlers | 2165-2260 | Chat, private messages |
| Movement & combat | 2260-4110 | `handle_move()`, `handle_hunt()`, `handle_combat_command()`, encounter logic |
| Utility functions | 4111-4738 | `send_location_update()`, `send_to_peer()`, `broadcast_chat()`, `handle_disconnect()`, security helpers |
| Encounter & combat rewards | 4739-5644 | `trigger_encounter()`, victory rewards, death handling |
| Inventory handlers | 5645-7600 | Use, equip, unequip, discard, sort, salvage, character updates |
| Merchant handlers | 7601-8436 | Buy, sell, gamble, recharge, merchant inventory generation |
| House/Sanctuary | 8437-9402 | House screen, upgrades, storage, kennel, fusion |
| Market system | 9403-10320 | Browse, list, buy, cancel, market calculations |
| Quest handlers | 10321-10728 | Accept, abandon, turn-in, quest log |
| Watch/spectate | 10729-11196 | Watch requests, forwarding, cleanup |
| Gathering system | 11718-12683 | Fishing, mining, logging minigame handlers |
| Job system | 13696-13765 | Job info, commitment |
| Crafting system | 13766-15502 | Recipe listing, craft initiation, challenge answers |
| Building system | 15503-16200 | Place, demolish, guard hire/feed |
| Dungeon system | 16616-18438 | Enter, move, exit, floor generation, encounters, traps |
| Title system | 18439-20871 | Title claims, abilities, pilgrimage |
| Trading system | 20872-21475 | Trade requests, offers, ready/cancel |
| GM commands | 21724-22198 | Admin/debug commands |
| Party system | 22546-23504 | Invite, response, disband, snake movement |

---

## 6. Player Data Management

### 6a. In-Memory Storage

The server tracks all live game state in dictionaries keyed by `peer_id`:

```gdscript
# Core state
var peers = {}               # peer_id -> connection metadata
var characters = {}          # peer_id -> Character object (live game state)

# System-specific state
var active_gathering = {}    # peer_id -> gathering minigame state
var active_harvests = {}     # peer_id -> harvest session state
var active_crafts = {}       # peer_id -> crafting challenge state
var active_trades = {}       # peer_id -> trade session with partner
var at_merchant = {}         # peer_id -> merchant data
var at_trading_post = {}     # peer_id -> trading post data
var at_player_station = {}   # peer_id -> {stations: [...], has_inn, has_storage}

# Party system
var party_membership = {}    # peer_id -> leader_peer_id
var active_parties = {}      # leader_peer_id -> {leader, members[], formed_at}
var pending_party_invites = {} # target_peer_id -> {from_peer_id, timestamp}

# Combat tracking
var pending_flocks = {}      # peer_id -> {monster_name, monster_level}
var pending_flock_drops = {} # peer_id -> Array of accumulated drops
var flock_counts = {}        # peer_id -> int (monsters remaining in flock)
var pending_wishes = {}      # peer_id -> {wish_options, drop_messages, ...}

# Dungeon system
var active_dungeons = {}     # instance_id -> dungeon instance data
var dungeon_floors = {}      # instance_id -> [floor grids]
var dungeon_monsters = {}    # instance_id -> {floor_num: [monsters]}
var player_dungeon_instances = {} # peer_id -> {quest_id: instance_id}

# Security
var peer_rate_limits = {}    # peer_id -> {tokens, last_refill}
var peer_type_cooldowns = {} # peer_id -> {msg_type: last_time}
var login_attempts = {}      # IP -> {attempts, first_attempt, locked_until}
```

### 6b. The Character Object

Every logged-in player has a `Character` object (defined in `shared/character.gd`).
This is the single source of truth for all player data:

```gdscript
# Created when a player selects a character:
var character = persistence.load_character_as_object(account_id, char_name)
characters[peer_id] = character
```

The Character object contains everything about the player:

- **Identity:** `name`, `race`, `class_type`, `level`, `experience`
- **Stats:** `strength`, `constitution`, `dexterity`, `intelligence`, `wisdom`, `wits`
- **Resources:** `current_hp`, `max_hp`, `current_mana`, `max_mana`
- **Position:** `x`, `y`, `in_dungeon`, `current_dungeon_id`, `dungeon_floor`
- **Inventory:** `inventory` (Array of item Dictionaries), `equipment` (Dictionary of slot->item)
- **Companions:** `active_companion`, `companions` (Array), `incubating_eggs` (Array)
- **Quests:** `active_quests`, `completed_quests`, `quest_cooldowns`
- **Skills:** `fishing_skill`, `mining_skill`, `logging_skill`, `crafting_skills`
- **Materials:** `crafting_materials` (Dictionary of material_id -> quantity)
- **Progression:** `monsters_killed`, `gold` (legacy), `salvage_essence`
- **Settings:** `cloak_active`, `swap_attack`, player preferences
- **House bonuses:** `house_bonuses` (Dictionary of upgrade effects)
- **Combat recovery:** `saved_combat_state` (serialized combat for disconnect recovery)

#### Serialization

Characters are serialized to JSON dictionaries for saving and network transfer:

```gdscript
# Convert Character to Dictionary (for saving or sending)
var char_dict = character.to_dict()

# Restore Character from Dictionary (when loading)
var character = Character.new()
character.from_dict(saved_data)
```

### 6c. Sending Updates to Clients

The server sends player data to clients via the `send_character_update()` system.
This uses a three-layer optimization pipeline:

**Layer 1: Batching** -- Multiple calls per frame are collapsed into one send.

```gdscript
func send_character_update(peer_id: int):
    """Queue character data update for client."""
    if USE_DELTA_UPDATES:
        pending_char_updates[peer_id] = true  # Mark dirty
    else:
        _send_character_update_immediate(peer_id, true)
```

If a handler calls `send_character_update()` three times in one frame (e.g., after
equipping an item, gaining XP, and updating a quest), only one actual network send
happens at the end of the frame in `_flush_pending_character_updates()`.

**Layer 2: Delta compression** -- Only changed fields are sent.

```gdscript
func _send_character_update_immediate(peer_id: int, force_full: bool):
    var character = characters[peer_id]
    var char_dict = character.to_dict()

    # Append account-level data
    char_dict["egg_capacity"] = persistence.get_egg_capacity(peers[peer_id].account_id)
    char_dict["valor"] = persistence.get_valor(peers[peer_id].account_id)
    char_dict["projected_rank"] = _calculate_projected_rank(character)

    if USE_DELTA_UPDATES and not force_full and last_sent_character_state.has(peer_id):
        var delta = _compute_character_delta(last_sent_character_state[peer_id], char_dict)
        if delta.is_empty():
            return  # Nothing changed -- skip send entirely
        send_to_peer(peer_id, {"type": "character_update", "data": delta, "delta": true})
    else:
        send_to_peer(peer_id, {"type": "character_update", "data": char_dict})

    last_sent_character_state[peer_id] = char_dict
```

The delta computation compares the new state against the last sent state and only
includes keys that changed:

```gdscript
func _compute_character_delta(old_state: Dictionary, new_state: Dictionary) -> Dictionary:
    var delta = {}
    for key in new_state:
        if not old_state.has(key):
            delta[key] = new_state[key]
        elif typeof(old_state[key]) != typeof(new_state[key]):
            delta[key] = new_state[key]
        elif old_state[key] is Array or old_state[key] is Dictionary:
            # Deep compare via JSON serialization
            if JSON.stringify(old_state[key]) != JSON.stringify(new_state[key]):
                delta[key] = new_state[key]
        elif old_state[key] != new_state[key]:
            delta[key] = new_state[key]
    # Check for removed keys
    for key in old_state:
        if not new_state.has(key):
            delta[key] = null
    return delta
```

**Layer 3: gzip compression** -- Large messages are compressed on the wire.

```gdscript
func send_to_peer(peer_id: int, data: Dictionary):
    var connection = peers[peer_id].connection
    if connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
        return

    if USE_COMPRESSION:
        # Binary framing: [4-byte uint32 length][1-byte flags][payload]
        var json_bytes = JSON.stringify(data).to_utf8_buffer()
        var flags: int = 0x00  # 0x00 = plain JSON, 0x01 = gzip
        var payload = json_bytes

        if json_bytes.size() > COMPRESSION_THRESHOLD:  # 512 bytes
            var compressed = json_bytes.compress(FileAccess.COMPRESSION_GZIP)
            if compressed.size() < json_bytes.size():
                payload = compressed
                flags = 0x01

        # Frame: [4-byte big-endian length][1-byte flags][payload bytes]
        var frame_len = 1 + payload.size()
        var header = PackedByteArray()
        header.resize(5)
        header[0] = (frame_len >> 24) & 0xFF
        header[1] = (frame_len >> 16) & 0xFF
        header[2] = (frame_len >> 8) & 0xFF
        header[3] = frame_len & 0xFF
        header[4] = flags
        header.append_array(payload)
        connection.put_data(header)
    else:
        # Legacy: newline-delimited JSON
        var json_str = JSON.stringify(data) + "\n"
        connection.put_data(json_str.to_utf8_buffer())
```

### 6d. Other Commonly Sent Messages

Besides character updates, the server sends several other message types:

```gdscript
# Location/map update (terrain, nearby players, dungeons, corpses)
send_location_update(peer_id)

# Combat messages (damage, effects, status)
send_combat_message(peer_id, "You deal 50 damage to the Goblin!")

# Chat messages (broadcast to all players)
broadcast_chat("[color=#00FF00]A new adventurer has arrived![/color]")

# Text messages (displayed in the player's game output)
send_to_peer(peer_id, {"type": "text", "message": "You found a hidden chest!"})

# Error messages
send_to_peer(peer_id, {"type": "error", "message": "You can't do that right now."})
```

---

## 7. Combat Flow on the Server

### 7a. Starting Combat

Combat is triggered in two ways:

**Random encounters on movement:**

```gdscript
func handle_move(peer_id: int, message: Dictionary):
    # ... validate move, update position ...

    # Roll for encounter (15-25% base chance, modified by terrain)
    if should_trigger_encounter:
        trigger_encounter(peer_id)
```

**Hunting (actively searching):**

```gdscript
func handle_hunt(peer_id: int):
    # Higher encounter rate than movement
    # ... validate state (not in combat, not in dungeon, etc.) ...
    trigger_encounter(peer_id)
```

The `trigger_encounter()` function decides what the player fights:

```gdscript
func trigger_encounter(peer_id: int):
    var character = characters[peer_id]
    var level_range = world_system.get_monster_level_range(character.x, character.y)

    # Roll for rare encounters first
    var rare_roll = randi() % 1000
    if rare_roll < 10:          # 1% legendary adventurer
        trigger_legendary_adventurer(peer_id, character, area_level)
        return
    if rare_roll < 40:          # 3% loot find
        trigger_loot_find(peer_id, character, area_level)
        return

    # Normal monster encounter
    var monster = monster_db.generate_monster(level_range.min, level_range.max)
    combat_mgr.start_combat(peer_id, character, monster)

    # Send combat start to client
    send_to_peer(peer_id, {
        "type": "combat_start",
        "combat_state": combat_mgr.get_combat_state(peer_id)
    })
```

### 7b. Processing Turns

The client sends a combat command, and the server processes one turn:

```gdscript
func handle_combat_command(peer_id: int, message: Dictionary):
    # Rate limit: 150ms minimum between combat commands
    var now = Time.get_ticks_msec()
    if now - combat_command_cooldown.get(peer_id, 0) < 150:
        return
    combat_command_cooldown[peer_id] = now

    var command = message.get("command", "")

    # Route to party combat if applicable
    if combat_mgr.party_combat_membership.has(peer_id):
        _handle_party_combat_command(peer_id, command)
        return

    # Process the combat action (attack, defend, flee, ability, etc.)
    var result = combat_mgr.process_combat_command(peer_id, command)

    if not result.get("success", false):
        for msg in result.get("messages", []):
            send_combat_message(peer_id, msg)
        return

    # Send all combat messages (damage dealt, effects applied, etc.)
    for msg in result.get("messages", []):
        send_combat_message(peer_id, msg)

    # If combat ended, process outcome
    if result.has("combat_ended") and result.combat_ended:
        if result.get("victory", false):
            # Victory: award XP, gold, gems, roll loot
            _process_combat_victory(peer_id, result)
        elif result.get("fled", false):
            # Fled: exit combat, maybe take damage
            _process_combat_flee(peer_id, result)
        elif result.get("player_died", false):
            # Death: permadeath, leaderboard, baddie points
            _process_player_death(peer_id, result)
```

The `combat_mgr.process_combat_command()` function in `shared/combat_manager.gd`
handles the actual turn logic -- damage calculations, ability effects, status effects,
companion actions, monster AI. It returns a result dictionary with messages and outcomes.

### 7c. Ending Combat

**Victory path:**
1. Increment `character.monsters_killed`
2. Track pilgrimage/quest progress
3. Award XP (with house bonus multiplier)
4. Check for level ups (multiple possible)
5. Roll loot drops via `drop_tables`
6. Add items to inventory
7. Handle flock encounters (sequential monster fights)
8. Save character
9. Send all results to client

**Death path:**
1. Record on leaderboard with death snapshot
2. Calculate and award Baddie Points to account
3. Return registered companion to house kennel
4. Apply permadeath (character is deleted)
5. Send death screen data to client

**Flee path:**
1. Speed-based success check
2. On success: exit combat, send location update
3. On failure: take damage, continue combat

### 7d. Combat State Persistence

If a player disconnects during combat, their combat state is serialized and saved
to the character file. On reconnect, combat is restored:

```gdscript
# On disconnect:
character.saved_combat_state = combat_mgr.serialize_combat_state(peer_id)

# On character select (reconnect):
if not character.saved_combat_state.is_empty():
    combat_mgr.restore_combat_state(peer_id, character, character.saved_combat_state)
```

---

## 8. World Management

### 8a. Procedural World

The `WorldSystem` generates a deterministic procedural world from a seed:

- **Size:** 4000x4000 tile area (technically unlimited, but tier scaling limits useful area)
- **9 tiers:** T1 near the center (0,0), T9 at the edges (~2000 tiles out)
- **Terrain types:** Plains, forest, dense forest, mountains, water, swamps, desert, etc.
- **Special tiles:** Dungeon entrances (D), NPC posts, trading posts, roads

Terrain is hash-based -- the same (x,y) always produces the same terrain type for a
given seed. No map data is stored for basic terrain.

### 8b. Chunk System

Player-modifiable terrain (built structures, depleted gathering nodes) is stored in
32x32 tile chunks managed by `ChunkManager`:

```gdscript
# Chunks are loaded on demand
chunk_manager.get_tile(x, y)      # Returns tile type at position
chunk_manager.set_tile(x, y, type) # Modifies a tile (marks chunk dirty)
chunk_manager.save_dirty_chunks()  # Writes changed chunks to disk
```

Chunks are JSON files stored in `user://data/chunks/`. Only chunks that differ from
the procedurally generated default are saved.

### 8c. Dungeon Management

The dungeon system has two types of dungeon objects:

**World dungeons** -- map markers visible to all players:
- Created by `_create_world_dungeon()` during `_check_dungeon_spawns()`
- Show as 'D' tiles on the map
- Stored in `active_dungeons` with NO `owner_peer_id`
- 150-200 maintained across the world at all times

**Player instances** -- private dungeons created when entering:
- Created by `_create_player_dungeon_instance()` when a player walks onto a 'D' tile
- Each player gets their own instance with their own floor layouts and monsters
- Stored in `active_dungeons` WITH `owner_peer_id` set
- Floor grids stored in `dungeon_floors[instance_id]`
- Monsters stored in `dungeon_monsters[instance_id]`

Lifecycle:

```
Player walks onto 'D' tile
  → _mark_world_dungeon_completed() (sets completed_at on world marker)
  → _create_player_dungeon_instance() (creates private dungeon)
  → Player explores, fights, finds loot
  → Player exits or dies
  → Player instance cleaned up

Meanwhile:
  → _check_dungeon_spawns() runs every 30s
  → Removes world dungeons where completed_at > 60s ago
  → Spawns new world dungeons to maintain 150-200 count
```

---

## 9. Persistence -- persistence_manager.gd

### 9a. Overview

`PersistenceManager` is a separate Node (class_name `PersistenceManager`) that handles
all disk I/O. All data is stored as JSON files in Godot's user data directory:

```
user://data/
├── accounts.json           Usernames, hashed passwords, character slot lists
├── characters/             Individual character save files
│   ├── acc_1_warrior.json
│   └── acc_2_mage.json
├── houses.json             Sanctuary data per account (upgrades, storage, kennel)
├── market_data.json        Open market listings per trading post
├── leaderboard.json        Top 100 dead characters (permadeath)
├── ban_list.json           Banned IPs with reasons
├── player_tiles.json       Player-built structures (walls, towers)
├── player_posts.json       Player enclosure metadata
├── guards.json             Hired guard entities
├── corpses.json            Lootable dead player remains on the map
├── realm_state.json        Global data (realm treasury)
└── chunks/                 32x32 tile chunk files (via ChunkManager)
```

### 9b. Safe Save with Backup

All writes use `_safe_save()` which creates a `.bak` backup before overwriting:

```gdscript
func _safe_save(filepath: String, data: Dictionary):
    var json_string = JSON.stringify(data, "\t")
    if json_string.is_empty():
        print("ERROR: JSON stringify returned empty for %s" % filepath)
        return

    # Create backup of current file
    if FileAccess.file_exists(filepath):
        var backup_path = filepath + ".bak"
        var existing = FileAccess.open(filepath, FileAccess.READ)
        if existing:
            var existing_content = existing.get_as_text()
            existing.close()
            if existing_content.length() > 2:
                var backup = FileAccess.open(backup_path, FileAccess.WRITE)
                if backup:
                    backup.store_string(existing_content)
                    backup.close()

    # Write new data
    var file = FileAccess.open(filepath, FileAccess.WRITE)
    if not file:
        print("ERROR: Failed to open file for save: %s" % filepath)
        return
    file.store_string(json_string)
    file.close()
```

Loading uses `_safe_load()` which tries the main file first, then falls back to the
backup if the main file is corrupt or missing:

```gdscript
func _safe_load(filepath: String) -> Dictionary:
    var data = _try_load_json(filepath)
    if not data.is_empty():
        return data

    # Main file failed -- try backup
    var backup_path = filepath + ".bak"
    if FileAccess.file_exists(backup_path):
        data = _try_load_json(backup_path)
        if not data.is_empty():
            _safe_save(filepath, data)  # Restore backup to main
            return data

    return {}
```

### 9c. Account System

Passwords are hashed with SHA-256 and a per-account random salt. Plaintext passwords
are never stored.

```gdscript
func generate_salt() -> String:
    var crypto = Crypto.new()
    var salt_bytes = crypto.generate_random_bytes(32)
    return salt_bytes.hex_encode()

func hash_password(password: String, salt: String) -> String:
    var ctx = HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    ctx.update((salt + password).to_utf8_buffer())
    return ctx.finish().hex_encode()

func verify_password(password: String, password_hash: String, salt: String) -> bool:
    return hash_password(password, salt) == password_hash
```

Account creation validates username (3-20 chars, alphanumeric + underscore) and
password (6-128 chars):

```gdscript
func create_account(username: String, password: String) -> Dictionary:
    # Validate username length, characters, uniqueness
    # Validate password length
    # Generate salt, hash password
    var account_id = "acc_%d" % accounts_data.next_account_id
    accounts_data.accounts[account_id] = {
        "username": username,
        "password_hash": password_hash,
        "password_salt": salt,
        "created_at": int(Time.get_unix_time_from_system()),
        "character_slots": [],
        "max_characters": DEFAULT_MAX_CHARACTERS,  # 6
        "is_admin": false
    }
    accounts_data.username_to_id[username_lower] = account_id
    save_accounts()
    return {"success": true, "account_id": account_id}
```

### 9d. Character Save/Load

Characters are stored as individual JSON files named `{account_id}_{character_name}.json`:

```gdscript
func save_character(account_id: String, character: Character):
    var filepath = get_character_filepath(account_id, character.name)
    var data = character.to_dict()
    data["account_id"] = account_id
    _safe_save(filepath, data)

func load_character_as_object(account_id: String, char_name: String) -> Character:
    var data = load_character(account_id, char_name)
    if data.is_empty():
        return null
    var character = Character.new()
    character.from_dict(data)

    # Safety: ensure HP >= 1 (edge case protection)
    if character.current_hp <= 0:
        character.current_hp = 1
        character.saved_combat_state = {}

    return character
```

The server's `save_character()` helper (in `server.gd`) is a convenience wrapper:

```gdscript
func save_character(peer_id: int):
    if not characters.has(peer_id) or not peers.has(peer_id):
        return
    var account_id = peers[peer_id].account_id
    if account_id.is_empty():
        return
    persistence.save_character(account_id, characters[peer_id])
```

### 9e. Auto-Save

The server auto-saves all active characters every 60 seconds:

```gdscript
func save_all_active_characters():
    for peer_id in characters.keys():
        save_character(peer_id)
```

This is driven by the `auto_save_timer` in `_process()`.

### 9f. House (Sanctuary) System

Houses are account-level persistent data that survives character permadeath. The
persistence manager handles:

- House creation (automatic on first access)
- Upgrade tracking and costs (using `HOUSE_UPGRADES` constant)
- Storage items (consumables, equipment, materials)
- Registered companions (survive character death)
- Kennel capacity (30-500 slots based on upgrade level)
- Valor (account-level currency)
- Baddie Points (meta-currency from character deaths)

```gdscript
# House upgrades with costs in Baddie Points
const HOUSE_UPGRADES = {
    "storage_slots": {"effect": 10, "max": 8, "costs": [500, 1000, ...]},
    "companion_slots": {"effect": 1, "max": 8, "costs": [2000, 5000, ...]},
    "kennel_capacity": {"effect": 0, "max": 9, "costs": [1000, 3000, ...]},
    "xp_bonus": {"effect": 1, "max": 10, "costs": [1500, 3000, ...]},
    "hp_bonus": {"effect": 5, "max": 5, "costs": [2000, 5000, ...]},
    # ... 16 total upgrade types
}

const KENNEL_CAPACITY_TABLE = [30, 50, 80, 120, 175, 250, 325, 400, 450, 500]
```

### 9g. Market System

The open market allows players to list items at trading posts for Valor:

```gdscript
func add_market_listing(post_id: String, listing: Dictionary) -> String:
    # Merges with existing same-seller same-item listing if possible
    # Returns listing_id

func get_market_listings(post_id: String, category: String) -> Array:
    # Returns filtered listings for a post

func calculate_markup(post_id: String, supply_category: String) -> float:
    # Supply-based markup (more listings = lower prices)
```

### 9h. Ban System

```gdscript
func ban_ip(ip: String, reason: String, banned_by: String):
    ban_list_data.banned_ips[ip] = {
        "reason": reason,
        "banned_at": int(Time.get_unix_time_from_system()),
        "banned_by": banned_by
    }
    save_ban_list()

func is_ip_banned(ip: String) -> bool:
    return ban_list_data.banned_ips.has(ip)
```

### 9i. Baddie Points

The meta-currency earned when a character dies (permadeath). Used for house upgrades:

```gdscript
func calculate_baddie_points(character: Character) -> int:
    var points = 0
    points += int(character.experience / 100)          # 1 BP per 100 XP
    points += character.crafting_materials.get("monster_gem", 0) * 5  # 5 BP per gem
    points += int(character.monsters_killed / 10)      # 1 BP per 10 kills
    points += character.completed_quests.size() * 10   # 10 BP per quest
    return points
```

---

## 10. Security Features

As of v0.9.144, the server has multiple layers of security:

### 10a. Connection-Level Security

| Feature | Constant | Value |
|---------|----------|-------|
| Max total connections | `MAX_TOTAL_CONNECTIONS` | 200 |
| Max connections per IP | `MAX_CONNECTIONS_PER_IP` | 3 |
| Connection rate limit | `CONNECTION_RATE_LIMIT` | 5 seconds between connections from same IP |
| Auth timeout | `AUTH_TIMEOUT` | 90 seconds to authenticate or get kicked |
| Max buffer size | `MAX_BUFFER_BYTES` | 64KB per peer |
| Max single message | `MAX_SINGLE_MESSAGE_BYTES` | 32KB |
| Max messages per frame | `MAX_MESSAGES_PER_FRAME` | 10 per peer |

### 10b. Token Bucket Rate Limiting

Each peer gets a bucket of tokens that refills over time. Each message costs one token.
When the bucket is empty, messages are silently dropped:

```gdscript
func _check_rate_limit(peer_id: int, msg_type: String) -> bool:
    var now = Time.get_unix_time_from_system()

    # Initialize bucket for new peers
    if not peer_rate_limits.has(peer_id):
        peer_rate_limits[peer_id] = {
            "tokens": float(RATE_LIMIT_TOKENS_MAX),  # 30
            "last_refill": now
        }

    var bucket = peer_rate_limits[peer_id]

    # Refill tokens (20 per second)
    var elapsed = now - bucket.last_refill
    bucket.tokens = minf(float(RATE_LIMIT_TOKENS_MAX),
                         bucket.tokens + elapsed * RATE_LIMIT_TOKENS_PER_SEC)
    bucket.last_refill = now

    # Per-type cooldowns (chat: 800ms, register: 5s)
    if MESSAGE_TYPE_COOLDOWNS.has(msg_type):
        if not peer_type_cooldowns.has(peer_id):
            peer_type_cooldowns[peer_id] = {}
        var min_interval = MESSAGE_TYPE_COOLDOWNS[msg_type]
        var last_time = peer_type_cooldowns[peer_id].get(msg_type, 0.0)
        if now - last_time < min_interval:
            return false
        peer_type_cooldowns[peer_id][msg_type] = now

    # Consume a token
    if bucket.tokens < 1.0:
        return false
    bucket.tokens -= 1.0
    return true
```

### 10c. Login Brute-Force Protection

```gdscript
const LOGIN_MAX_ATTEMPTS = 5          # Max failed attempts per IP
const LOGIN_WINDOW_SECONDS = 300      # 5 minute tracking window
const LOGIN_LOCKOUT_SECONDS = 900     # 15 minute lockout

func _record_failed_login(ip: String):
    var now = Time.get_unix_time_from_system()
    if not login_attempts.has(ip):
        login_attempts[ip] = {"attempts": 0, "first_attempt": now, "locked_until": 0.0}
    var info = login_attempts[ip]
    info.attempts += 1
    if info.attempts >= LOGIN_MAX_ATTEMPTS:
        info.locked_until = now + LOGIN_LOCKOUT_SECONDS

func _is_login_locked(ip: String) -> bool:
    if not login_attempts.has(ip):
        return false
    var locked_until = login_attempts[ip].get("locked_until", 0.0)
    return locked_until > 0 and Time.get_unix_time_from_system() < locked_until
```

### 10d. Chat Sanitization

```gdscript
const MAX_CHAT_LENGTH = 500

# In handle_chat():
text = text.left(MAX_CHAT_LENGTH)
text = _sanitize_chat_text(text)  # Strips control characters
```

### 10e. IP Bans

GM commands `/banip <ip> [reason]` and `/unbanip <ip>` manage the ban list.
Bans are checked at connection acceptance time (before any data is exchanged).

### 10f. Stale Connection Cleanup

Every 5 seconds, `_check_stale_connections()` kicks peers that have been connected
for more than 90 seconds without authenticating. It also cleans up expired login lockouts.

---

## 11. Server Handler Pattern

Every handler in `server.gd` follows the same structural pattern. Understanding this
pattern is key to reading and modifying the server:

```gdscript
func handle_something(peer_id: int, message: Dictionary):
    # ──── Step 1: Validate the request ────
    # Check that the player exists and is in a valid state
    if not characters.has(peer_id):
        return

    var character = characters[peer_id]

    # Check preconditions (not in combat, not in dungeon, etc.)
    if combat_mgr.is_in_combat(peer_id):
        send_to_peer(peer_id, {
            "type": "error",
            "message": "You cannot do that while in combat!"
        })
        return

    # Validate message parameters (never trust client data)
    var item_index = message.get("index", -1)
    if item_index < 0 or item_index >= character.inventory.size():
        send_to_peer(peer_id, {
            "type": "error",
            "message": "Invalid item selection."
        })
        return

    # ──── Step 2: Execute the game logic ────
    var item = character.inventory[item_index]
    character.inventory.remove_at(item_index)
    character.salvage_essence += item.get("salvage_value", 10)

    # ──── Step 3: Save if needed ────
    save_character(peer_id)

    # ──── Step 4: Send results to client ────
    send_to_peer(peer_id, {
        "type": "text",
        "message": "You salvaged %s for %d essence!" % [item.name, item.salvage_value]
    })

    # ──── Step 5: Send character update ────
    # This triggers the client to refresh its display of stats/inventory
    send_character_update(peer_id)
```

The four essential steps are:
1. **Validate** -- Never trust client input. Check that the player exists, is in the
   right state, and the parameters make sense.
2. **Execute** -- Modify the Character object (or other server state).
3. **Save** -- Call `save_character(peer_id)` if the change should persist immediately
   (critical actions). For less critical changes, the auto-save catches them.
4. **Respond** -- Send results via `send_to_peer()` for text messages, and
   `send_character_update()` for stat/inventory changes.

Here is a real example from the server -- the chat handler:

```gdscript
func handle_chat(peer_id: int, message: Dictionary):
    if not peers[peer_id].authenticated:
        return

    var text = message.get("message", "")
    if text.is_empty():
        return

    # Security: Truncate and sanitize
    text = text.left(MAX_CHAT_LENGTH)
    text = _sanitize_chat_text(text)

    var username = peers[peer_id].username

    # Add title prefix if player has a title
    var display_name = username
    if characters.has(peer_id):
        var character = characters[peer_id]
        if not character.title.is_empty():
            display_name = TitlesScript.format_titled_name(username, character.title)

    # Broadcast to all OTHER authenticated peers
    for other_peer_id in peers.keys():
        if peers[other_peer_id].authenticated and other_peer_id != peer_id:
            send_to_peer(other_peer_id, {
                "type": "chat",
                "sender": display_name,
                "message": text
            })
```

---

## 12. Adding a New Server Handler -- Step by Step

This is a concrete walkthrough for adding a new feature. Let's say you want to add a
`/whistle` command that alerts nearby players.

### Step 1: Add the Message Type to handle_message()

Find the `handle_message()` match statement (~line 970) and add your new case:

```gdscript
match msg_type:
    # ... existing handlers ...
    "whistle":
        handle_whistle(peer_id, message)
    # ...
```

### Step 2: Write the Handler Function

Place it near related handlers (communication handlers are around line 2165):

```gdscript
func handle_whistle(peer_id: int, message: Dictionary):
    # 1. Validate
    if not characters.has(peer_id):
        return
    var character = characters[peer_id]

    # Can't whistle in combat
    if combat_mgr.is_in_combat(peer_id):
        send_to_peer(peer_id, {"type": "error", "message": "Can't whistle in combat!"})
        return

    # 2. Execute -- find nearby players within 10 tiles
    var radius = 10
    var nearby = get_nearby_players(peer_id, radius)

    # 3. Send results
    if nearby.is_empty():
        send_to_peer(peer_id, {
            "type": "text",
            "message": "You whistle loudly, but nobody is nearby to hear it."
        })
    else:
        # Notify the whistler
        send_to_peer(peer_id, {
            "type": "text",
            "message": "You whistle loudly! %d nearby adventurers hear you." % nearby.size()
        })
        # Notify each nearby player
        for other_data in nearby:
            var other_peer_id = other_data.peer_id
            send_to_peer(other_peer_id, {
                "type": "text",
                "message": "[color=#FFD700]You hear %s whistling nearby![/color]" % character.name
            })

    # No save needed -- whistling doesn't change character state
    # No character_update needed -- no stats changed
```

### Step 3: Validate All Input

Always treat client data as potentially malicious:

```gdscript
# GOOD: Use .get() with defaults, validate ranges
var index = message.get("index", -1)
if index < 0 or index >= character.inventory.size():
    return

# BAD: Trust client data
var index = message.index  # Crashes if key missing
character.inventory[index] # Out of bounds possible
```

### Step 4: If Stats Changed, Update the Client

```gdscript
# If you modified the character's stats, inventory, quests, etc.:
send_character_update(peer_id)

# If you moved the character or changed the visible map:
send_location_update(peer_id)
```

### Step 5: If This is a Critical Action, Save Immediately

```gdscript
# Critical: item loss, XP gain, death, trade completion
save_character(peer_id)

# Non-critical: auto-save will catch it within 60 seconds
# (e.g., changing a setting, toggling cloak)
```

### Step 6: Clean Up on Disconnect

If your handler adds per-player tracking state, clean it up in `handle_disconnect()`:

```gdscript
# In handle_disconnect(), add:
my_new_tracking_dict.erase(peer_id)
```

### Step 7: Add Client-Side Support

The client needs to send the message and handle the response. In `client/client.gd`:

1. Send the message from the appropriate UI interaction
2. Handle any response message types in the client's message handler

---

## 13. Finding Things in server.gd

With ~21,500 lines in a single file, navigation is important. Here are practical tips:

### Search by Function Name

Every handler follows the naming pattern `handle_<message_type>()`. Search for:

```
func handle_move         → Movement logic
func handle_hunt         → Hunting/encounter triggering
func handle_combat_      → Combat command processing
func handle_merchant_    → Merchant interactions
func handle_quest_       → Quest accept/abandon/turn-in
func handle_dungeon_     → Dungeon enter/move/exit
func handle_trade_       → Player-to-player trading
func handle_market_      → Open market (Valor)
func handle_house_       → Sanctuary/house
func handle_gm_          → GM/admin commands
func handle_party_       → Party system
func handle_gathering_   → Fishing/mining/logging
func handle_craft_       → Crafting
func handle_build_       → Building walls/towers
func handle_guard_       → Guard system
```

### Search by Section Comments

Major sections are delimited by comment headers:

```
# ===== ACCOUNT HANDLERS =====
# ===== MERCHANT HANDLERS =====
# ===== NETWORK OPTIMIZATION STATE =====
# ===== GUARD SYSTEM =====
# ===== GATHERING NODE SYSTEM =====
# ===== SECURITY HELPER FUNCTIONS =====
```

### Key Variable Declarations (Lines 1-234)

All server state variables are declared at the top of the file. If you need to
understand what tracking dictionaries exist, start here.

### Key Constants

```gdscript
const DEFAULT_PORT = 9080
const AUTO_SAVE_INTERVAL = 60.0
const AUTH_TIMEOUT = 90.0
const MAX_CONNECTIONS_PER_IP = 3
const MAX_TOTAL_CONNECTIONS = 200
const MAX_BUFFER_BYTES = 65536       # 64KB
const MAX_SINGLE_MESSAGE_BYTES = 32768  # 32KB
const MAX_MESSAGES_PER_FRAME = 10
const LOGIN_MAX_ATTEMPTS = 5
const LOGIN_LOCKOUT_SECONDS = 900     # 15 minutes
const RATE_LIMIT_TOKENS_MAX = 30
const RATE_LIMIT_TOKENS_PER_SEC = 20.0
const MAX_CHAT_LENGTH = 500
const COMPRESSION_THRESHOLD = 512
const MAP_UPDATE_FLUSH_INTERVAL = 0.3
const MAX_ACTIVE_DUNGEONS = 300
const MIN_WORLD_DUNGEONS = 150
const MAX_WORLD_DUNGEONS = 200
const DUNGEON_DESPAWN_DELAY = 60.0
const PARTY_MAX_SIZE = 4
```

### Quick Reference: Data Flow for Common Operations

**Player moves north:**
```
Client sends: {"type": "move", "direction": 8}
  → handle_move() validates (not in combat, not a follower, etc.)
  → world_system.move_player() calculates new position
  → Check for encounters, merchants, trading posts, dungeons
  → Update character.x, character.y
  → send_location_update(peer_id)
  → send_character_update(peer_id) if anything changed
  → Maybe: trigger_encounter(peer_id) → combat_mgr.start_combat()
```

**Player attacks in combat:**
```
Client sends: {"type": "combat", "command": "attack"}
  → handle_combat_command() rate-limits (150ms)
  → combat_mgr.process_combat_command() runs turn logic
  → Returns: {success, messages[], combat_ended, victory, rewards}
  → Server sends combat_message for each message
  → If ended: process victory/death/flee
  → send_character_update(peer_id) for stat changes
```

**Player salvages an item:**
```
Client sends: {"type": "inventory_salvage", "index": 3}
  → handle_inventory_salvage() validates index
  → Removes item from inventory
  → Adds salvage essence to character
  → Rolls for bonus materials
  → save_character(peer_id)
  → send_to_peer() with result message
  → send_character_update(peer_id)
```
