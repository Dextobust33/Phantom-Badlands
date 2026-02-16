# Phantom Badlands Code Guide

A practical walkthrough for modifying Phantom Badlands -- a text-based multiplayer RPG built with Godot 4.6 and GDScript.

---

## 1. Architecture Overview

### Client/Server Split

Phantom Badlands uses a classic client-server model with two monolithic files:

- **`client/client.gd`** (~26,000 lines) -- All UI rendering, input handling, action bar, ASCII art display, and network communication. Extends `Control` and runs as a Godot scene.
- **`server/server.gd`** (~21,500 lines) -- All game logic, validation, persistence, combat processing, and message routing. Also extends `Control` and runs as a separate Godot instance.

Both are single-file architectures. Every feature touches these two files.

### Communication: Raw TCP with JSON

The game does **NOT** use Godot's built-in multiplayer API. It uses raw `StreamPeerTCP` connections with newline-delimited JSON messages.

**Client side** (`client/client.gd`):
```gdscript
# Line 294 -- the connection object
var connection = StreamPeerTCP.new()
var buffer = ""

# Line 17583 -- sending a message to the server
func send_to_server(data: Dictionary):
    var json_str = JSON.stringify(data) + "\n"
    connection.put_data(json_str.to_utf8_buffer())

# Line 2756 -- reading data in _process() every frame
var available = connection.get_available_bytes()
if available > 0:
    var data = connection.get_data(available)
    if data[0] == OK:
        buffer += data[1].get_string_from_utf8()
        process_buffer()

# Line 14056 -- parsing the buffer into messages
func process_buffer():
    while "\n" in buffer:
        var pos = buffer.find("\n")
        var msg_str = buffer.substr(0, pos)
        buffer = buffer.substr(pos + 1)
        var json = JSON.new()
        if json.parse(msg_str) == OK:
            handle_server_message(json.data)
```

**Server side** (`server/server.gd`):
```gdscript
# Line 34 -- the TCP server
var server = TCPServer.new()
var peers = {}  # peer_id -> {connection, authenticated, account_id, buffer, ...}

# Line 3987 -- sending a message to one client
func send_to_peer(peer_id: int, data: Dictionary):
    var json_str = JSON.stringify(data) + "\n"
    var bytes = json_str.to_utf8_buffer()
    # ... writes to peer's connection

# Line 652 -- accepting new connections in _process()
if server.is_connection_available():
    var peer = server.take_connection()
    peers[peer_id] = {
        "connection": peer,
        "authenticated": false,
        "buffer": "",
        ...
    }

# Line 700 -- reading from all connected peers
for peer_id in peers.keys():
    connection.poll()
    var available = connection.get_available_bytes()
    if available > 0:
        # ... read data, append to buffer, call process_buffer(peer_id)
```

Every message is a Dictionary with a `"type"` key. Example: `{"type": "craft_item", "recipe_id": "copper_sword"}`.

### Shared Files

These files are loaded by **both** client and server:

| File | Purpose | Lines |
|------|---------|-------|
| `shared/character.gd` | Player stats, inventory, equipment, abilities | ~3,650 |
| `shared/combat_manager.gd` | Turn-based combat engine, damage formulas | ~6,135 |
| `shared/world_system.gd` | Terrain generation, tile types, LOS, merchants | ~2,136 |
| `shared/monster_database.gd` | Monster definitions across 9 tiers | ~1,728 |
| `shared/crafting_database.gd` | Recipes, materials, quality system | ~3,472 |
| `shared/drop_tables.gd` | Item generation, fishing/mining/logging catches | ~4,527 |
| `shared/dungeon_database.gd` | Dungeon types, floors, bosses | ~1,991 |
| `shared/quest_database.gd` | Quest generation, quest types | ~1,261 |
| `shared/constants.gd` | Shared constants, class/race definitions, abilities | ~226 |
| `shared/chunk_manager.gd` | 32x32 chunk world, delta persistence | ~438 |

The server loads these via `preload()`:
```gdscript
# server.gd lines 23-32
const PersistenceManagerScript = preload("res://server/persistence_manager.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const CraftingDatabaseScript = preload("res://shared/crafting_database.gd")
# ... etc
```

The client loads some lazily:
```gdscript
# client.gd lines 6-24
var _monster_art_script = null
func _get_monster_art():
    if _monster_art_script == null:
        _monster_art_script = load("res://client/monster_art.gd")
    return _monster_art_script
```

### The _process() Loop

Both client and server do all their work in `_process(delta)`, called every frame:

**Server** (`_process` at line 588):
1. Auto-save timer (every 60 seconds)
2. Merchant movement updates
3. Dungeon spawn checks
4. Chunk manager / geological events
5. Accept new TCP connections
6. Read data from all peers, parse JSON, dispatch to `handle_message()`

**Client** (`_process` at line 1795):
1. Poll TCP connection
2. Handle escape key
3. Process item selection keys (inventory, crafting, companions, etc.)
4. Process action bar hotkeys
5. Process movement keys
6. Read incoming data from server, parse, dispatch to `handle_server_message()`

---

## 2. How a Player Action Works

### End-to-End Trace: "Player Crafts an Item"

Here is every step that happens when a player crafts a Copper Sword.

#### Step 1: Player enters crafting mode

The player is at a Trading Post and presses the "Craft" action bar button (action bar slot handled in `update_action_bar()`, line ~4348). This calls:

```gdscript
# client.gd line ~8496 in execute_local_action()
"enter_crafting":
    enter_crafting_mode()
```

`enter_crafting_mode()` at line ~21997 sets `crafting_mode = true`, clears the game output, and displays the skill selection menu (Blacksmithing, Alchemy, etc.). It then calls `update_action_bar()` to show crafting-mode buttons.

#### Step 2: Player selects a crafting skill

The player presses a number key (e.g., "1" for Blacksmithing). This is handled in `_process()` at line ~2133 (crafting recipe selection), but first the skill selection is handled via the action bar. The action bar triggers `execute_local_action("craft_skill_1")`, which calls:

```gdscript
# client.gd line ~22048
func request_craft_list(skill_name: String):
    crafting_skill = skill_name
    send_to_server({"type": "craft_list", "skill": skill_name})
```

#### Step 3: Client sends JSON message to server

The message `{"type": "craft_list", "skill": "blacksmithing"}` is sent as a newline-terminated JSON string over the TCP connection.

#### Step 4: Server receives and routes the message

In the server's `_process()`, the peer's buffer is read and parsed. `handle_message()` at line 755 matches the type:

```gdscript
# server.gd line 928
"craft_list":
    handle_craft_list(peer_id, message)
```

#### Step 5: Server validates and processes

`handle_craft_list()` at line 12815:
1. Checks the player is at a trading post or player station
2. Validates the skill name
3. Gets the player's skill level from `character.get_crafting_skill()`
4. Fetches all recipes from `CraftingDatabaseScript.get_recipes_for_skill()`
5. Calculates trading post bonus and job bonus
6. Checks which recipes the player can craft (has materials, meets level)
7. Builds a response with the full recipe list

#### Step 6: Server sends response

```gdscript
# server.gd line 12890
send_to_peer(peer_id, {
    "type": "craft_list",
    "skill": skill_name,
    "skill_level": skill_level,
    "post_bonus": post_bonus,
    "job_bonus": job_bonus,
    "recipes": recipe_list,
    "materials": character.crafting_materials
})
```

#### Step 7: Client receives and displays

The client's `handle_server_message()` at line 14066 routes `"craft_list"` to:

```gdscript
# client.gd line 15536
"craft_list":
    handle_craft_list(message)
```

`handle_craft_list()` at line 22053 stores the recipes and calls `display_craft_recipe_list()` at line 22078, which renders the recipe list with color-coded materials (cyan = have enough, red = missing).

#### Step 8: Player selects a recipe

In `_process()` at line 2133, crafting key presses are detected:

```gdscript
if crafting_mode and crafting_skill != "" and crafting_selected_recipe < 0:
    for i in range(5):
        if is_item_select_key_pressed(i):
            if not get_meta("craftkey_%d_pressed" % i, false):
                set_meta("craftkey_%d_pressed" % i, true)
                _consume_item_select_key(i)
                select_craft_recipe(i)
```

`select_craft_recipe()` shows recipe details and a "Craft" button. When the player confirms:

```gdscript
# client.gd line ~22261
send_to_server({"type": "craft_item", "recipe_id": recipe_id})
```

#### Step 9: Server processes the craft

`handle_craft_item()` at server line 13023:
1. Validates player is at a station
2. Looks up the recipe in `CraftingDatabaseScript`
3. Checks skill requirement, specialist gating, materials
4. **Consumes materials** from the character
5. If the skill gap is small enough, sends a **crafting challenge minigame** (`"craft_challenge"` message)
6. Otherwise auto-skips the minigame and rolls quality immediately

#### Step 10: Crafting challenge minigame (if applicable)

The server generates 3 multiple-choice questions and sends them:

```gdscript
# server.gd line 13098
send_to_peer(peer_id, {
    "type": "craft_challenge",
    "rounds": challenge["client_rounds"],
    "skill_name": skill_name,
})
```

The client handles this at line 22263 (`handle_craft_challenge()`), sets `crafting_challenge_mode = true`, and shows the questions one at a time. The player answers by pressing number keys, and after 3 rounds:

```gdscript
# client.gd line 22314
send_to_server({
    "type": "craft_challenge_answer",
    "answers": craft_challenge_answers,
})
```

The server scores the answers at `handle_craft_challenge_answer()` (line 14092), rolls quality based on score, creates the item, awards crafting XP, and sends the result.

#### Step 11: Client displays the result

```gdscript
# client.gd line 15539
"craft_result":
    handle_craft_result(message)
```

`handle_craft_result()` at line 22328 displays the challenge score, quality name (Poor/Standard/Fine/Masterwork), item stats, XP gained, and level-up notifications.

### Message Types Summary

Every feature follows this pattern:
1. Client sends `{"type": "some_action", ...}` via `send_to_server()`
2. Server's `handle_message()` routes to a handler function
3. Server validates, processes, sends response via `send_to_peer()`
4. Client's `handle_server_message()` routes to a display function

---

## 3. Adding New Features

### 3a. Adding a New Action Bar Button

The action bar has 10 slots (Space, Q, W, E, R, 1-5 by default). Buttons are contextual -- they change based on game state.

**Step 1: Find the right section in `update_action_bar()`** (client.gd line 4348)

The function has priority-ordered sections. Find the mode your button belongs to:

```
Line ~4355: settings_mode
Line ~4462: dungeon_mode (and not in_combat)
Line ~4600: in_combat
Line ~4900: at_merchant
Line ~5100: inventory_mode
Line ~5400: crafting_mode
Line ~5700: at_trading_post
Line ~6100: gathering_mode
Line ~6300: default movement mode
```

**Step 2: Add your button definition**

```gdscript
# Inside the appropriate elif block:
current_actions.append({
    "label": "My Button",        # Text shown on button
    "action_type": "local",      # "local", "server", or "combat"
    "action_data": "my_action",  # Identifier for the handler
    "enabled": true              # Whether button is clickable
})
```

Action types:
- `"local"` -- Handled by `execute_local_action()` in client.gd (line 8458). No server message sent.
- `"server"` -- Automatically sends `{"type": action_data}` to the server.
- `"combat"` -- Sends a combat command.

**Step 3: Add the handler**

For `"local"` actions, add to `execute_local_action()`:

```gdscript
# client.gd line ~8458, in the match statement inside execute_local_action():
"my_action":
    # Do something
    display_game("You did the thing!")
    update_action_bar()
```

For `"server"` actions, add to `handle_message()` in server.gd (line 755):

```gdscript
# server.gd line ~755, in the match statement:
"my_action":
    handle_my_action(peer_id, message)
```

**Step 4: Always call `update_action_bar()` after state changes.** This is critical -- the action bar won't update itself.

### 3b. Adding a New Slash Command

Slash commands (like `/help`, `/who`, `/trade`) are typed in the chat input field.

**Step 1: Add to `command_keywords` array** (client.gd line ~15835)

```gdscript
var command_keywords = ["help", "clear", "who", ..., "mycommand"]
```

Without this, the command will be sent as a chat message instead of being processed.

**Step 2: Add handler in `process_command()`** (client.gd line ~16505)

```gdscript
func process_command(text: String):
    var parts = text.split(" ", false)
    var command = parts[0].to_lower()

    match command:
        # ... existing commands ...
        "mycommand":
            # Client-only command:
            display_game("Hello from mycommand!")
            # OR server command:
            send_to_server({"type": "mycommand", "arg": parts[1] if parts.size() > 1 else ""})
```

**Step 3: For server-side commands**, add to `handle_message()` in server.gd:

```gdscript
# server.gd in handle_message() match statement:
"mycommand":
    handle_mycommand(peer_id, message)
```

Then implement the handler function:

```gdscript
func handle_mycommand(peer_id: int, message: Dictionary):
    if not characters.has(peer_id):
        return
    var character = characters[peer_id]
    # ... do something ...
    send_to_peer(peer_id, {"type": "text", "message": "Result of mycommand"})
```

### 3c. Adding a New Crafting Recipe

Recipes are defined in `shared/crafting_database.gd` in the `RECIPES` constant (line 363).

**Add to the `RECIPES` dictionary:**

```gdscript
# shared/crafting_database.gd line ~363
const RECIPES = {
    # ... existing recipes ...

    "my_new_sword": {
        "name": "Enchanted Blade",
        "skill": CraftingSkill.BLACKSMITHING,  # Which crafting skill
        "skill_required": 25,                   # Minimum skill level to craft
        "difficulty": 30,                       # Affects success chance
        "materials": {                          # Required materials (IDs from drop_tables)
            "iron_ore": 5,
            "magic_dust": 2,
            "@attack_parts": 3                  # @ prefix = monster part group
        },
        "output_type": "weapon",                # "weapon", "armor", "consumable", "tool", "structure", etc.
        "output_slot": "weapon",                # Equipment slot (for weapon/armor types)
        "base_stats": {                         # Base stats before quality multiplier
            "attack": 20,
            "level": 25
        },
        "craft_time": 2.0                       # Display only (no actual delay)
    },
}
```

For specialist-only recipes (require a committed job):

```gdscript
"my_special_recipe": {
    "name": "Master's Blade",
    "skill": CraftingSkill.BLACKSMITHING,
    "skill_required": 50,
    "difficulty": 55,
    "specialist_only": true,   # Only committed Blacksmiths can craft this
    "materials": {"steel_ore": 8, "soul_shard": 3},
    "output_type": "weapon",
    "output_slot": "weapon",
    "base_stats": {"attack": 50, "level": 50},
    "craft_time": 3.0
},
```

Output types and what they do:
- `"weapon"` / `"armor"` -- Creates equipment with stats scaled by quality
- `"consumable"` -- Creates a consumable item (needs `"effect"` field)
- `"tool"` -- Creates a gathering tool
- `"structure"` -- Creates a buildable structure for player posts
- `"upgrade"` -- Upgrades an equipped item (+levels)
- `"enchantment"` -- Adds stat bonuses to equipment
- `"rune"` -- Creates a rune item

Material IDs must match items in `drop_tables.gd` (mining/logging/fishing catches) or `crafting_database.gd` material definitions. Monster part groups use `@` prefix (e.g., `@attack_parts` matches any `_fang`, `_tooth`, `_claw`, `_horn`, `_mandible` parts).

### 3d. Adding a New Monster

Monsters are defined in `shared/monster_database.gd`.

**Step 1: Add to the `MonsterType` enum** (line ~96):

```gdscript
enum MonsterType {
    # Tier 1 (Level 1-5)
    GOBLIN,
    GIANT_RAT,
    # ... existing entries ...
    MY_MONSTER,  # Add at the end of the appropriate tier
}
```

**Step 2: Add to the tier's monster list** in `_get_tier_monsters()` (line ~294):

```gdscript
1:  # Tier 1
    return [
        MonsterType.GOBLIN,
        MonsterType.GIANT_RAT,
        MonsterType.KOBOLD,
        MonsterType.SKELETON,
        MonsterType.WOLF,
        MonsterType.MY_MONSTER  # Add here
    ]
```

**Step 3: Add base stats** in `get_monster_base_stats()` (line ~381):

```gdscript
MonsterType.MY_MONSTER:
    return {
        "name": "Shadow Cat",
        "base_level": 3,
        "base_hp": 20,
        "base_strength": 10,
        "base_defense": 4,
        "base_speed": 25,
        "base_experience": 30,
        "base_gold": 8,
        "flock_chance": 20,           # % chance of pack encounter
        "drop_table_id": "tier1",     # Which loot table
        "drop_chance": 5,             # % chance of equipment drop
        "description": "A dark feline with glowing eyes",
        "class_affinity": ClassAffinity.CUNNING,
        "abilities": [ABILITY_AMBUSHER],  # Special abilities
        "death_message": "The shadow cat fades into darkness."
    }
```

Available abilities are constants at the top of `monster_database.gd` (lines 15-61), like `ABILITY_POISON`, `ABILITY_REGENERATION`, `ABILITY_MULTI_STRIKE`, etc.

**Step 4: Add ASCII art** in `client/monster_art.gd` in `get_art_map()` (line 78):

```gdscript
"Shadow Cat": ["[color=#808080]",
"    /\_/\  ",
"   ( o.o ) ",
"    > ^ <  ",
"   /|   |\ ",
"  (_|   |_)","[/color]"],
```

Art rules:
- First element: `[color=#HEXCOLOR]`
- Middle elements: Lines of ASCII art
- Last element: `[/color]`
- Small art (under 50 chars wide) is auto-centered
- Wide art (over 50 chars) is displayed as-is

### 3e. Adding a New Gathering Catch

Catches are defined in `shared/drop_tables.gd`.

**For fishing** -- add to `FISHING_CATCHES` (line ~1957):

```gdscript
const FISHING_CATCHES = {
    "shallow": [
        # ... existing catches ...
        {"weight": 5, "item": "golden_koi", "name": "Golden Koi", "type": "fish", "value": 75},
    ],
    "deep": [
        # ... deep water catches ...
    ]
}
```

**For mining** -- add to `MINING_CATCHES` (line ~2084), organized by tier (1-9):

```gdscript
const MINING_CATCHES = {
    1: [  # T1: 0-50 distance from origin
        # ... existing T1 catches ...
        {"weight": 3, "item": "quartz_crystal", "name": "Quartz Crystal", "type": "gem", "value": 30},
    ],
}
```

**For logging** -- add to `LOGGING_CATCHES` (line ~2242), same tier structure as mining.

Fields:
- `weight` -- Relative spawn chance (higher = more common)
- `item` -- Internal ID (used in crafting recipes, inventory)
- `name` -- Display name
- `type` -- Category: `"fish"`, `"ore"`, `"mineral"`, `"wood"`, `"plant"`, `"herb"`, `"treasure"`, `"gem"`, `"material"`, `"egg"`
- `value` -- Base value (used for various calculations)

---

## 4. Common Patterns

### The Pending Action Flag Pattern

When a player takes an action that displays results (like salvaging an item), server messages arriving immediately afterward can wipe the display. The solution is pending action flags.

**The problem:**
1. Player salvages items -- result message appears: "Salvaged 5 items for 150 essence!"
2. Server sends `character_update` (because inventory changed)
3. Client is in `inventory_mode`, so `character_update` handler calls `display_inventory()`
4. The salvage result message is gone -- player never saw it

**The solution:**

```gdscript
# 1. Set a flag BEFORE the action
pending_inventory_action = "awaiting_salvage_result"

# 2. In the character_update handler (client.gd line ~14540), check the flag:
if inventory_mode:
    if pending_inventory_action == "awaiting_salvage_result":
        pass  # Don't refresh -- keep showing salvage results
    else:
        display_inventory()

# 3. Clear the flag when the player explicitly exits
"salvage_back":
    pending_inventory_action = ""
    display_inventory()
    update_action_bar()
```

Existing flags to know about:
- `pending_inventory_action` -- States: `""`, `"equip_item"`, `"use_item"`, `"equip_confirm"`, `"sort_select"`, `"salvage_select"`, `"viewing_materials"`, `"awaiting_salvage_result"`, `"lock_item"`, `"rune_apply"`, etc.
- `awaiting_item_use_result` -- Prevents text message display during item use
- `crafting_challenge_mode` -- Prevents crafting list refresh during minigame
- `awaiting_craft_result` -- Prevents craft list refresh while showing result

### Output Protection Pattern

Whenever you add a new display that the player needs to read, follow this checklist:

1. **Create a state flag** (or reuse an existing pending action variable)
2. **Add bypass in `character_update` handler** (line ~14523) -- check your flag and `pass` instead of refreshing
3. **Add action bar state** in `update_action_bar()` -- show a "Back" button
4. **Add exit handler** in `execute_local_action()` -- clear flag, return to parent view
5. **Add to item selection exclusion list** (line ~1866) -- prevent number keys from double-triggering

### Mode Transitions and Action Bar Updates

The action bar state machine is priority-ordered. In `update_action_bar()`, modes are checked in this order:

```
settings_mode > pending_trade > in_combat > at_merchant >
inventory_mode > at_trading_post > crafting_mode > dungeon_mode >
build_mode > gathering_mode > default_movement
```

When entering a new mode:
```gdscript
inventory_mode = true
pending_inventory_action = ""
display_inventory()
update_action_bar()  # ALWAYS call this after state changes
```

When exiting a mode:
```gdscript
inventory_mode = false
pending_inventory_action = ""
# Redisplay whatever was showing before (movement view, etc.)
update_action_bar()  # ALWAYS call this
```

### Item Selection Key Handling

Number keys 1-5 are shared between:
- **Item selection** (inventory items, recipe selection, companion activation)
- **Action bar slots 5-9** (the right half of the action bar)

The `_consume_item_select_key()` function (line ~16960) prevents double-triggers:

```gdscript
func _consume_item_select_key(item_index: int):
    # 1. Same-frame protection: add keycode to consumed list
    var keycode = get_item_select_keycode(item_index)
    item_selection_consumed_this_frame.append(keycode)

    # 2. Cross-frame protection: mark action bar hotkey as "already pressed"
    for ab_slot in range(10):
        var ab_key = keybinds.get("action_%d" % ab_slot, ...)
        if ab_key == keycode:
            set_meta("hotkey_%d_pressed" % ab_slot, true)
            break
```

**Every** `is_item_select_key_pressed(i)` handler in `_process()` MUST call `_consume_item_select_key(i)`. The pattern:

```gdscript
for i in range(9):
    if is_item_select_key_pressed(i):
        if not get_meta("mykey_%d_pressed" % i, false):
            set_meta("mykey_%d_pressed" % i, true)
            _consume_item_select_key(i)  # ALWAYS add this
            do_my_action(i)
    else:
        set_meta("mykey_%d_pressed" % i, false)
```

If you forget `_consume_item_select_key(i)`, the action bar will also fire on the same key press, or on the next frame after your mode exits.

### Pre-Marking Held Keys on Mode Entry

When entering a mode via a key press, any currently held keys must be pre-marked to prevent them from immediately triggering actions in the new mode:

```gdscript
# When entering a mode that uses item selection keys:
for i in range(9):
    if is_item_select_key_pressed(i):
        set_meta("craftkey_%d_pressed" % i, true)

# When entering a mode that uses action bar keys:
for i in range(10):
    var action_key = "action_%d" % i
    var key = keybinds.get(action_key, default_keybinds.get(action_key, KEY_SPACE))
    if Input.is_physical_key_pressed(key):
        set_meta("hotkey_%d_pressed" % i, true)
```

---

## 5. Debugging Tips

### Reading Godot Console Output

Run with output capture:
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" server/server.tscn 2>&1
```

The `2>&1` redirects stderr to stdout so you see all `print()` output and error messages.

### Validating Scripts Without Running

Use `--check-only` to validate a single script for syntax and type errors:
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --check-only --script "res://shared/character.gd" 2>&1
```

### Common GDScript Errors

**"Identifier X not declared in the current scope"**

Usually a variable name mismatch. The server uses `monster_db` (line 112) while some shared code might reference `monster_database`. Always check the file's actual variable declarations.

**"Invalid access to property or key X on a base object of type Dictionary"**

Dot access (`dict.key`) throws a SCRIPT ERROR if the key doesn't exist. Use `.get("key", default)` instead:

```gdscript
# BAD -- crashes if "experience_reward" key is missing:
var xp = monster.experience_reward

# GOOD -- returns 10 if key is missing:
var xp = monster.get("experience_reward", 10)
```

**JSON Float vs Integer Key Mismatch**

JSON stores all numbers as floats. If you have a Dictionary with integer keys and look up a value loaded from JSON, it won't match:

```gdscript
# This dict uses integer keys:
const TIER_DATA = {1: "copper", 2: "iron", 3: "steel"}

# JSON gives you float 1.0, not int 1:
var tier = item.get("tier", 0)  # tier = 1.0 (float)
TIER_DATA.has(tier)  # FALSE! 1.0 != 1

# Fix: cast to int
var tier = int(item.get("tier", 0))  # tier = 1 (int)
TIER_DATA.has(tier)  # TRUE
```

**Serialization Key Name Mismatches**

When you serialize data (e.g., saving combat state), the key names must exactly match what the consumer expects:

```gdscript
# If victory code reads monster.get("experience_reward", 10):
# Then serialization MUST use the same key:
monster_data["experience_reward"] = monster.get("experience_reward", 10)
# NOT "xp_reward" or "exp" or any other name
```

Always grep for the key name in consuming code before choosing the serialization key.

**"Constant X has the same name as a previously declared constant"**

GDScript won't let you declare two constants with the same name. Before adding a new constant, grep the file for the name to make sure it doesn't already exist.

### Debugging Network Messages

Add print statements in the message handlers to see what's being sent and received:

```gdscript
# In server.gd handle_message():
func handle_message(peer_id: int, message: Dictionary):
    print("RECV from %d: %s" % [peer_id, str(message).left(200)])

# In client.gd handle_server_message():
func handle_server_message(message: Dictionary):
    print("RECV: %s" % str(message).left(200))
```

---

## 6. File Map

### Client (`client/`)

| File | Lines | Purpose |
|------|-------|---------|
| `client.gd` | ~26,308 | Main client: UI, input, networking, action bar, all game modes, display functions |
| `monster_art.gd` | ~5,651 | ASCII art for all monsters and eggs. `get_art_map()` returns name-to-art dictionary |
| `trader_art.gd` | ~2,130 | ASCII art for wandering trader NPCs. `get_random_trader_art()`, `get_trader_art_for_id()` |
| `trading_post_art.gd` | ~316 | ASCII art for trading post buildings by category |

### Server (`server/`)

| File | Lines | Purpose |
|------|-------|---------|
| `server.gd` | ~21,551 | Main server: game logic, message routing, combat, dungeons, trading, crafting, parties |
| `persistence_manager.gd` | ~1,679 | File-based persistence: accounts, characters, leaderboard, houses, market data. Stores in `user://data/` |

### Shared (`shared/`)

| File | Lines | Purpose |
|------|-------|---------|
| `character.gd` | ~3,653 | `Character` class: stats, inventory, equipment, abilities, crafting skills, companion data |
| `combat_manager.gd` | ~6,135 | `CombatManager`: turn resolution, damage formulas, ability processing, party combat |
| `world_system.gd` | ~2,136 | `WorldSystem`: procedural terrain, tile types, LOS raycasting, NPC post generation, merchants |
| `chunk_manager.gd` | ~438 | `ChunkManager`: 32x32 chunk system, delta JSON persistence, node respawns, geological events |
| `monster_database.gd` | ~1,728 | `MonsterDatabase`: 9 tiers of monsters, stat scaling, lethality calculation, tier blending |
| `crafting_database.gd` | ~3,472 | `CraftingDatabase`: 5 crafting skills, recipes, quality system, upgrade/enchantment caps |
| `drop_tables.gd` | ~4,527 | `DropTables`: equipment generation, fishing/mining/logging catches, salvage, companion eggs |
| `dungeon_database.gd` | ~1,991 | `DungeonDatabase`: dungeon types, floor generation, boss definitions, encounter tables |
| `quest_database.gd` | ~1,261 | `QuestDatabase`: quest types (KILL, KILL_TIER, BOSS_HUNT, RESCUE, GATHER), daily seed generation |
| `quest_manager.gd` | ~563 | `QuestManager`: quest state tracking, completion checks, party quest sync |
| `trading_post_database.gd` | ~1,054 | Trading post definitions: locations, categories, visual variety (10 categories, 10 border shapes) |
| `npc_post_database.gd` | ~224 | NPC post definitions: procedural post generation from world seed |
| `constants.gd` | ~226 | Shared constants: classes, races, abilities, experience table, UI colors |
| `titles.gd` | ~444 | Title system: Jarl, High King, Eternal, Knight, Elder title definitions and requirements |
| `network_protocol.gd` | 1 | Empty placeholder (protocol is defined implicitly by message types in client/server) |

### Tools (`tools/`)

| File | Lines | Purpose |
|------|-------|---------|
| `combat_simulator/simulator.gd` | -- | Main entry point for combat balance testing |
| `combat_simulator/combat_engine.gd` | -- | Ports combat formulas for headless simulation |
| `combat_simulator/simulated_character.gd` | -- | Lightweight character for simulation |
| `combat_simulator/gear_generator.gd` | -- | Generates level-appropriate equipment |
| `combat_simulator/results_writer.gd` | -- | JSON and Markdown output generation |
| `combat_simulator/quick_simulation.gd` | -- | Quick single-run simulation |
| `combat_simulator/test_simulation.gd` | -- | Test harness for simulation |

### Root

| File | Lines | Purpose |
|------|-------|---------|
| `admin_tool.gd` | ~452 | Admin panel for server management |
| `project.godot` | -- | Godot project configuration |
| `export_presets.cfg` | -- | Export presets for client build |
| `VERSION.txt` | 1 | Current version number (used by launcher for updates) |

### Launcher (`launcher/`)

| File | Lines | Purpose |
|------|-------|---------|
| `launcher.gd` | ~222 | Auto-update launcher: checks GitHub releases, downloads new client versions |

### Data Files (Runtime, not in repo)

| Path | Purpose |
|------|---------|
| `user://data/accounts.json` | Account credentials (hashed passwords) |
| `user://data/characters/` | Per-character save files |
| `user://data/leaderboard.json` | High scores |
| `user://data/houses.json` | Sanctuary (house) data per account |
| `user://data/world/` | Modified chunk deltas (32x32 tiles) |
| `user://data/world_seed.json` | World generation seed |
| `user://data/market_data.json` | Player market listings |
| `user://data/player_tiles.json` | Player-placed tiles (walls, structures) |
| `user://data/player_posts.json` | Named player enclosures |
| `user://data/guards.json` | Guard companion data at player posts |
| `server/balance_config.json` | Combat tuning: lethality weights, ability modifiers |

### Key Line Number References (approximate, may shift as code changes)

**client.gd:**
- `_ready()`: line ~1332
- `_process()`: line ~1795
- Item selection keys: line ~1862
- Action bar processing: line ~2547
- Movement keys: line ~2690
- `update_action_bar()`: line ~4348
- `trigger_action()`: line ~6678
- `execute_local_action()`: line ~8458
- `handle_server_message()`: line ~14066
- `character_update` handler: line ~14523
- `command_keywords`: line ~15835
- `process_command()`: line ~16505
- `send_to_server()`: line ~17583
- `_consume_item_select_key()`: line ~16960

**server.gd:**
- `_process()`: line ~588
- TCP accept loop: line ~652
- Peer data reading: line ~700
- `process_buffer()`: line ~735
- `handle_message()`: line ~755
- `send_to_peer()`: line ~3987
- `handle_craft_list()`: line ~12815
- `handle_craft_item()`: line ~13023

---

## 7. Phase 5: Dungeon Expansion

Phase 5 adds step pressure, dungeon gathering, traps, escape scrolls, restricted exit, rest food, and a server UI map wipe button. The implementation spans `dungeon_database.gd`, `character.gd`, `server.gd`, `client.gd`, `crafting_database.gd`, and `server.tscn`.

### 7a. Step Pressure

Every move inside a dungeon increments a per-floor step counter. When it hits 100% the dungeon collapses.

**Constants (dungeon_database.gd line ~61):**
```gdscript
const DUNGEON_STEP_LIMITS = {1: 100, 2: 95, 3: 90, 4: 85, 5: 80, 6: 75, 7: 70, 8: 65, 9: 60}
```

Boss floors get +50% via `get_step_limit(tier, is_boss_floor)` (line ~68).

**Character tracking (character.gd):** `dungeon_floor_steps` is incremented by the server on every `handle_dungeon_move()` call (server.gd line ~15977). It is reset when the player advances to a new floor.

**Threshold warnings (server.gd line ~15976):**
1. Server increments `character.dungeon_floor_steps`
2. Computes `step_pct = dungeon_floor_steps / step_limit`
3. At 100%: calls `_collapse_dungeon(peer_id)` (line ~17399) -- penalizes player and ejects from dungeon
4. At 90%+: sends a warning text message to the client

`_collapse_dungeon()` at line ~17399 handles the penalty (loses gathered dungeon materials) and ejects the player.

### 7b. Dungeon Gathering

Resource tiles (`TileType.RESOURCE = 8`) appear on dungeon floors as `&` characters (cyan `#00FFCC` on the map).

**Floor generation (dungeon_database.gd line ~1712):** Resource tiles are placed at room centers during floor generation.

**Server flow (server.gd):**
1. Player steps onto a `TileType.RESOURCE` tile in `handle_dungeon_move()` (line ~16099)
2. Server calls `_prompt_dungeon_gather(peer_id)` -- sends a prompt to the client
3. Client enters `dungeon_resource_prompt = true` state (client.gd line ~1026)
4. Client shows Gather / Skip action bar buttons
5. Player confirms: client sends `dungeon_gather_confirm` message (server.gd line ~1017)
6. Player skips: client sends `dungeon_gather_skip` (server.gd line ~1019)

**Display protection (client.gd line ~1027):** `awaiting_dungeon_gather_result = true` flag prevents `_send_dungeon_state()` from overwriting the gather result text. The flag is cleared when the player makes their next dungeon move (line ~17685) or when the dungeon state refreshes without pending results (line ~22581).

**Dungeon movement is blocked** while `dungeon_resource_prompt` is true (client.gd line ~2607).

### 7c. Traps

Traps are server-only hidden data. The client only sees traps AFTER they trigger.

**Data structure (server.gd line ~102):**
```gdscript
var dungeon_traps: Dictionary = {}  # instance_id -> {floor_num: [{x, y, type, triggered}]}
```

**Generation (server.gd line ~17485):** `_generate_dungeon_traps()` is called during dungeon creation (both normal and player dungeon instances). It delegates to `DungeonDatabaseScript.generate_traps()` (dungeon_database.gd line ~75), which uses a seeded RNG per floor.

**Trap count per floor (dungeon_database.gd line ~64):**
```gdscript
const TRAPS_PER_FLOOR = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3, 7: 4, 8: 4, 9: 4}
```

**Detection (server.gd line ~17505):** `_check_dungeon_trap()` checks if an untriggered trap exists at the player's position after each move. If found, `_trigger_trap()` (line ~17515) applies the effect and marks `trap.triggered = true`.

**Three trap types (server.gd line ~17522):**

| Type | Effect | Color |
|------|--------|-------|
| `rust` | +10-20 wear on 1-2 random equipped items | `#FF4444` (red) |
| `thief` | Steals 1-3 dungeon-gathered materials (or 1 from inventory as fallback) | `#A335EE` (purple) |
| `teleport` | Teleports player to a random empty tile on the same floor | `#00BFFF` (cyan) |

**Client display:** Server sends `dungeon_trap` message with `trap_x`, `trap_y`, `trap_color`. Client adds the position to `dungeon_triggered_traps` array (client.gd line ~1025) so triggered traps are visible on the dungeon map in subsequent renders.

### 7d. Escape Scrolls

The only way to voluntarily leave a dungeon (besides completing it or dying).

**Crafting (crafting_database.gd line ~2999):** Three tiers, all Scribing skill:

| Recipe | Skill Req | Specialist | Tier Max |
|--------|-----------|------------|----------|
| Scroll of Escape | 8 | No | T4 |
| Scroll of Greater Escape | 16 | Yes | T7 |
| Scroll of Supreme Escape | 24 | Yes | T9 |

Each has `output_type: "escape_scroll"` and a `tier_max` field limiting which dungeon tiers it works in.

**Usage (server.gd line ~5298):** When a player uses an item with `item_type == "escape_scroll"`, the server calls `_use_escape_scroll()` (line ~17733). This function:
1. Validates the player is in a dungeon
2. Checks `tier_max >= dungeon_tier` (scroll must cover the dungeon's tier)
3. Bypasses the normal `handle_dungeon_exit()` block
4. Removes the scroll from inventory and exits the player safely

**Chest drops (server.gd line ~17010):** Dungeon treasure chests have a 20% chance to drop an escape scroll. The tier of the scroll matches the dungeon tier via `DungeonDatabaseScript.roll_escape_scroll_drop(dungeon_tier)`.

### 7e. No Free Exit

`handle_dungeon_exit()` (server.gd line ~16135) blocks voluntary exit:
```gdscript
func handle_dungeon_exit(peer_id: int):
    """Handle player exiting dungeon -- no free exit, must use escape scroll"""
    # ...
    send_to_peer(peer_id, {
        "type": "text",
        "message": "[color=#FF6666]There is no way out! Use an Escape Scroll to leave safely.[/color]"
    })
```

**Flee behavior (server.gd line ~3168):** When a player flees combat inside a dungeon, they are NOT ejected. Instead:
1. The player is relocated to a random empty/cleared/entrance tile on the **same floor**
2. A message appears: "You flee deeper into the dungeon!"
3. The dungeon state is re-sent so the map updates

This means fleeing is a survival tool but not an escape mechanism.

### 7f. Rest Food

Players can rest in dungeons to heal, but only if they have food materials.

**Material types (server.gd line ~17804):**
```gdscript
const DUNGEON_REST_FOOD_MATERIAL_TYPES = ["plant", "herb", "fungus", "fish"]
```

When a player rests (`handle_dungeon_rest`, routed via `dungeon_rest` message type at line ~1015), the server scans `character.crafting_materials` for any material whose type (from `CraftingDatabase.MATERIALS`) matches one of these food types (line ~18215). If found, one unit is consumed and the player heals.

### 7g. Map Wipe Button (Server UI)

The server scene has a GUI button for wiping the world map without a full data wipe.

**Scene nodes (server.tscn):**
- `MapWipeButton` -- Button in `VBox/ButtonRow`
- `MapWipeDialog` -- First confirmation dialog ("Step 1 of 2")
- `MapWipeFinalDialog` -- Final confirmation dialog

**Signal connections (server.gd line ~308):**
```gdscript
map_wipe_button.pressed.connect(_on_map_wipe_button_pressed)      # line ~328
map_wipe_dialog.confirmed.connect(_on_map_wipe_step1_confirmed)   # line ~333
map_wipe_final_dialog.confirmed.connect(_on_map_wipe_final_confirmed)  # line ~338
```

The final confirmation calls `_execute_map_wipe(-1)` (line ~341), where `-1` indicates the wipe was triggered from the server UI rather than by an admin player (admin-triggered wipes pass the `peer_id`). `_execute_map_wipe()` is defined at line ~21202.
