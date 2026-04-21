# 10. How-To Guides — Step-by-Step Recipes

These are practical, copy-paste-ready guides for the most common modifications you'll want to make. Each guide is a numbered checklist with code examples.

> **Prerequisite:** Read [01_gdscript_fundamentals.md](01_gdscript_fundamentals.md) and [02_godot_engine_basics.md](02_godot_engine_basics.md) first if you haven't already.

---

## Table of Contents

1. [Add a New Monster](#1-add-a-new-monster)
2. [Add Monster ASCII Art](#2-add-monster-ascii-art)
3. [Add a New Item to Loot Tables](#3-add-a-new-item-to-loot-tables)
4. [Add a New Chat Command](#4-add-a-new-chat-command)
5. [Add a New Action Bar Button](#5-add-a-new-action-bar-button)
6. [Add a New UI Screen/Mode](#6-add-a-new-ui-screenmode)
7. [Add a New Server Message Type](#7-add-a-new-server-message-type)
8. [Add a New Quest Type](#8-add-a-new-quest-type)
9. [Add a New Dungeon](#9-add-a-new-dungeon)
10. [Add a New Crafting Recipe](#10-add-a-new-crafting-recipe)
11. [Modify Combat Balance](#11-modify-combat-balance)
12. [Add a New Gathering Catch](#12-add-a-new-gathering-catch)
13. [Add a New Monster Ability](#13-add-a-new-monster-ability)
14. [Add a New Consumable Item](#14-add-a-new-consumable-item)
15. [Create a Release](#15-create-a-release)

---

## 1. Add a New Monster

**Files to edit:** `shared/monster_database.gd`

**Steps:**

1. Open `shared/monster_database.gd` and find the monster definitions (large constant dictionary organized by tier).

2. Find the tier section where your monster belongs (T1 = levels 1-10ish, T9 = endgame).

3. Add your monster definition. Follow the existing pattern:
```gdscript
"My New Monster": {
    "tier": 3,
    "base_hp": 120,
    "base_strength": 18,
    "base_defense": 8,
    "base_speed": 10,
    "abilities": ["sunder"],       # Monster abilities (see combat doc)
    "affinity": "fire",            # Element affinity (optional)
    "description": "A fearsome beast from the wastes."
},
```

4. **Important fields:**
   - `tier` — determines where it spawns (distance from origin)
   - `base_hp/strength/defense/speed` — scaled by level when generated
   - `abilities` — list of monster ability names (defined in combat_manager.gd)
   - `affinity` — element type for advantage/disadvantage system

5. **Verify:** Run the script validator to check for syntax errors:
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --check-only --script "res://shared/monster_database.gd" 2>&1
```

6. **Optional:** Add ASCII art for the monster (see guide #2 below).

7. **Optional:** Add the monster as a companion egg source in `drop_tables.gd` → `get_egg_for_monster()`.

---

## 2. Add Monster ASCII Art

**Files to edit:** `client/monster_art.gd`

**Steps:**

1. Open `client/monster_art.gd` and find the `get_art_map()` function. This returns a dictionary mapping monster names to art arrays.

2. Add your art entry. The format is:
```gdscript
"My New Monster": ["[color=#FF0000]",
"    /\\___/\\    ",
"   ( o   o )   ",
"   (  =^=  )   ",
"    )     (    ",
"   (       )   ",
"  ( /\\ Y /\\ )  ",
"   \"\"   \"\"    ",
"[/color]"],
```

3. **Format rules:**
   - First element: `"[color=#HEXCOLOR]"` — the color for the entire art
   - Middle elements: lines of ASCII art (strings)
   - Last element: `"[/color]"` — closing color tag
   - Each line should be the SAME width (pad with spaces)

4. **Color by monster type:**
   - Green `#00FF00` — Goblins, nature creatures
   - Brown `#8B4513` — Animals, beasts
   - Gray `#808080` — Undead, golems, constructs
   - Red `#FF0000` — Demons, fire creatures
   - Blue `#0070DD` — Water/ice creatures
   - Purple `#A335EE` — Magical beings, aberrations

5. **Size categories:**
   - **Wide art (>50 chars per line):** Used as-is, all whitespace preserved
   - **Small art (≤50 chars per line):** Auto-centered with border

6. **Font size:** The system auto-calculates font size to fit ~330 vertical units. If your art looks too big or small, add an override in `FONT_SIZE_OVERRIDES`:
```gdscript
const FONT_SIZE_OVERRIDES = {
    # ...existing entries...
    "My New Monster": 6,  # Adjust as needed (smaller number = larger art)
}
```

7. **The monster name in the art map MUST exactly match the name in monster_database.gd.** Case-sensitive!

8. **Source files:** If you have ASCII art files, they're typically at `C:\Users\Dexto\Desktop\Phantasia_Project\ASCII\`

---

## 3. Add a New Item to Loot Tables

**Files to edit:** `shared/drop_tables.gd`

**Steps:**

1. Open `shared/drop_tables.gd` and find the relevant loot table for the tier.

2. Loot tables are organized by tier (TIER_1_DROPS, TIER_2_DROPS, etc.). Each is an array of item definitions.

3. Add your item definition:
```gdscript
# For equipment:
{
    "name": "Flame Sword",
    "type": "weapon",
    "slot": "weapon",
    "level": 15,
    "rarity": "rare",
    "attack": 25,
    "defense": 0,
    "hp_bonus": 0,
    "description": "A blade wreathed in eternal flame."
},

# For consumables:
{
    "name": "Greater Health Potion",
    "type": "consumable",
    "item_type": "consumable",
    "is_consumable": true,
    "healing": 100,
    "level": 10,
    "rarity": "uncommon",
    "description": "Restores 100 HP."
},
```

4. **Critical for consumables:** Must have BOTH `"type": "consumable"` AND `"is_consumable": true` for the item to be usable. Also set `"item_type"` to the specific subtype.

5. **Drop weight:** Items in the tier array have equal chance by default. To make an item rarer, add it fewer times or use the weight system if one exists.

6. **Verify:** Run the script validator on drop_tables.gd.

---

## 4. Add a New Chat Command

**Files to edit:** `client/client.gd` (both `command_keywords` and `process_command()`), possibly `server/server.gd`

This is a two-step process because commands must be whitelisted before they'll work.

**Steps:**

### Client-Side Command (no server interaction needed)

1. **Step 1: Add to command_keywords** (~line 15835 in client.gd)
   Find the `command_keywords` array and add your command name:
```gdscript
var command_keywords = ["help", "settings", "inventory", "status", "mycommand", ...]
```
   Without this, typing `/mycommand` will be sent as a chat message!

2. **Step 2: Add handler in process_command()** (~line 16505 in client.gd)
   Find the `process_command()` function's match statement and add:
```gdscript
"mycommand":
    display_game("[color=#00FFFF]My command executed![/color]")
    display_game("Here's what it does...")
```

### Server-Side Command (needs server processing)

1. **Client side:** Same as above (add to command_keywords + process_command), but instead of displaying locally, send to server:
```gdscript
"mycommand":
    send_to_server({"type": "my_command", "param": args})
```

2. **Server side — Step 3: Add to handle_message()** (~line 970 in server.gd)
```gdscript
"my_command":
    handle_my_command(peer_id, message)
```

3. **Server side — Step 4: Write the handler function**
```gdscript
func handle_my_command(peer_id: int, message: Dictionary):
    var character = characters.get(peer_id)
    if not character:
        return

    # Your logic here
    var param = message.get("param", "")

    # Send result back to client
    send_to_peer(peer_id, {"type": "text", "message": "Command result: %s" % param})
```

4. **Client side — Step 5: Handle the response** (if needed)
   If the server sends back a custom message type (not just "text"), add it to `handle_server_message()`:
```gdscript
"my_command_result":
    var result = message.get("result", "")
    display_game("[color=#00FF00]%s[/color]" % result)
```

> **Remember:** The CLAUDE.md says to prefer Action Bar buttons over chat commands for new features. Commands are fine for debug/utility, but gameplay features should use the action bar.

---

## 5. Add a New Action Bar Button

**Files to edit:** `client/client.gd` (`update_action_bar()` and `execute_local_action()`)

**Steps:**

1. **Decide which state/mode the button appears in.** The action bar is contextual — different buttons show in different modes. Find the right section in `update_action_bar()` (~line 4723).

2. **Add the button to the action bar array for that state:**
```gdscript
# In update_action_bar(), find the section for your mode:
elif my_new_mode:
    current_actions = [
        {"label": "Back", "action_type": "local", "action_data": "my_mode_back", "enabled": true},
        {"label": "Do Thing", "action_type": "local", "action_data": "my_mode_action", "enabled": true},
        {"label": "", "action_type": "none", "action_data": "", "enabled": false},  # Empty slot
        # ... fill all 10 slots (pad empty ones)
    ]
```

3. **Add click handler in execute_local_action()** (~line 9001):
```gdscript
"my_mode_action":
    # Do the thing when the button is clicked
    display_game("[color=#00FFFF]You did the thing![/color]")

"my_mode_back":
    my_new_mode = false
    display_location()  # Return to normal view
    update_action_bar()
```

4. **CRITICAL: Both input paths must work!**
   - Keyboard path: handled by `_process()` hotkey polling (automatic if your mode isn't in the exclusion list)
   - Click path: handled by `execute_local_action()` (you just added this)
   - If your mode IS in the exclusion list (`settings_mode`, `combat_item_mode`, etc.), you ALSO need keyboard handling in `_input()`

5. **If using number keys (slots 5-9):** Make sure to handle the item selection conflict. See guide #6.

---

## 6. Add a New UI Screen/Mode

**Files to edit:** `client/client.gd` (multiple locations)

This is the most complex task because of the "output disappears" problem. Follow ALL steps carefully.

**Steps:**

### Step 1: Create state variables
At the top of client.gd (variable declarations area, lines 1-800):
```gdscript
var my_mode: bool = false
var pending_my_action: String = ""  # For sub-states within the mode
```

### Step 2: Create the display function
```gdscript
func display_my_screen():
    game_output.clear()
    display_game("[color=#FFD700]===== MY NEW SCREEN =====[/color]")
    display_game("")
    display_game("  Welcome to my new screen!")
    display_game("  Here's what you can do:")
    display_game("")
    display_game("  1. Option A")
    display_game("  2. Option B")
    display_game("  3. Option C")
    display_game("")
    display_game("[color=#808080]Space=Back  1-3=Select[/color]")
    update_action_bar()
```

### Step 3: Add action bar state in update_action_bar() (~line 4723)
Add your mode check in the priority chain (order matters — add it in the right place):
```gdscript
elif my_mode:
    if pending_my_action == "confirm":
        current_actions = [
            {"label": "Yes", "action_type": "local", "action_data": "my_confirm_yes", "enabled": true},
            {"label": "No", "action_type": "local", "action_data": "my_confirm_no", "enabled": true},
            # ... pad remaining slots
        ]
    else:
        current_actions = [
            {"label": "Back", "action_type": "local", "action_data": "my_mode_back", "enabled": true},
            {"label": "Do A", "action_type": "local", "action_data": "my_action_a", "enabled": true},
            {"label": "Do B", "action_type": "local", "action_data": "my_action_b", "enabled": true},
            # ... pad remaining slots
        ]
```

### Step 4: Add execute_local_action() handlers (~line 9001)
```gdscript
"my_mode_back":
    my_mode = false
    pending_my_action = ""
    display_location()  # Return to world view
    update_action_bar()

"my_action_a":
    pending_my_action = "doing_a"
    display_game("[color=#00FFFF]You chose option A![/color]")
    # Don't call display_my_screen() here — we want the message to stay visible

"my_confirm_yes":
    # Handle confirmation
    pending_my_action = ""
    display_my_screen()  # Return to main screen
```

### Step 5: CRITICAL — Add bypass in character_update handler (~line 15439)
Find the section where `character_update` triggers mode refreshes. Add your mode:
```gdscript
# In the character_update handler:
elif my_mode:
    if pending_my_action in ["doing_a", "doing_b", "confirm"]:
        pass  # Don't refresh — keep showing current output
    else:
        display_my_screen()  # Safe to refresh
```

### Step 6: CRITICAL — Add to item selection exclusion (~line 1866)
If your mode uses number keys for selection, add it to the exclusion list:
```gdscript
if ... and pending_my_action not in ["doing_a", "confirm"] and ...
```

### Step 7: Add item selection key handling (if using 1-9 keys)
```gdscript
# In the _process() item selection area:
elif my_mode and pending_my_action == "":
    for i in range(3):  # 3 options
        if is_item_select_key_pressed(i):
            if not get_meta("itemkey_%d_pressed" % i, false):
                set_meta("itemkey_%d_pressed" % i, true)
                _consume_item_select_key(i)  # CRITICAL: always call this!
                match i:
                    0: execute_local_action("my_action_a")
                    1: execute_local_action("my_action_b")
                    2: execute_local_action("my_action_c")
```

### Step 8: Add entry point
How does the player open this screen? Add a button or command that sets the mode:
```gdscript
# In the "More" menu, or via a command:
"open_my_screen":
    my_mode = true
    pending_my_action = ""
    display_my_screen()
```

### Step 9: Test!
1. Open the screen
2. Trigger an action that shows output
3. Wait 2 seconds (server messages will arrive)
4. Output should STILL be visible (not cleared)
5. Press Back — should return to normal view
6. Test BOTH keyboard AND mouse click for every button

---

## 7. Add a New Server Message Type

**Files to edit:** `client/client.gd` and `server/server.gd`

See [04_networking.md](04_networking.md) for the full networking explanation. Here's the quick recipe:

**Steps:**

1. **Define the message format** (what the client sends and what the server responds with):
```
Client → Server: {"type": "my_request", "param1": "value"}
Server → Client: {"type": "my_response", "result": "data", "success": true}
```

2. **Server — Add to handle_message()** (~line 970 in server.gd):
```gdscript
"my_request":
    handle_my_request(peer_id, message)
```

3. **Server — Write the handler:**
```gdscript
func handle_my_request(peer_id: int, message: Dictionary):
    var character = characters.get(peer_id)
    if not character:
        return

    var param1 = message.get("param1", "")
    # Validate input (NEVER trust client data)
    if param1 == "":
        send_to_peer(peer_id, {"type": "error", "message": "Missing parameter"})
        return

    # Do game logic
    var result = do_something(character, param1)

    # Save if character data changed
    save_character(peer_id)

    # Send response
    send_to_peer(peer_id, {"type": "my_response", "result": result, "success": true})

    # Send character update if stats/inventory changed
    send_character_update(peer_id)
```

4. **Client — Send the request** (from action bar handler or command):
```gdscript
send_to_server({"type": "my_request", "param1": some_value})
```

5. **Client — Handle the response** in handle_server_message() (~line 14970):
```gdscript
"my_response":
    var result = message.get("result", "")
    var success = message.get("success", false)
    if success:
        display_game("[color=#00FF00]Success: %s[/color]" % result)
    else:
        display_game("[color=#FF0000]Failed![/color]")
```

---

## 8. Add a New Quest Type

**Files to edit:** `shared/quest_database.gd`, `shared/quest_manager.gd`, `server/server.gd`

**Steps:**

1. **Define the quest type** in `quest_database.gd`:
   - Add to the quest generation logic
   - Define: objective description, target, requirements, rewards

2. **Add progress tracking** in `quest_manager.gd`:
   - How does progress get incremented? (on kill, on gather, on explore, etc.)
   - What's the completion condition?

3. **Add server-side tracking:**
   - Where does the progress event happen? (combat end, gathering end, movement, etc.)
   - Call `quest_manager.update_quest_progress()` at that point

4. **Add client display:**
   - Update quest log display to show the new quest type
   - Add progress text formatting

---

## 9. Add a New Dungeon

**Files to edit:** `shared/dungeon_database.gd`

**Steps:**

1. Open `shared/dungeon_database.gd` and find the dungeon definitions.

2. Add your dungeon:
```gdscript
{
    "name": "Dragon's Lair",
    "tier": 7,
    "min_level": 50,
    "floors": 5,
    "boss": {
        "name": "Ancient Dragon",
        "monster_type": "Dragon"  # Must match a monster in monster_database.gd
    },
    "description": "A volcanic cave housing an ancient dragon.",
    "trap_chance": 0.15,  # 15% chance of traps per tile
},
```

3. **The `monster_type` field is critical** — ALL monsters on ALL floors will be this type. The boss is a named variant of this type.

4. **Make sure the monster_type exists** in `monster_database.gd`. If "Dragon" doesn't exist, add it first (see guide #1).

5. The dungeon will automatically be eligible for world spawning in its tier zone.

---

## 10. Add a New Crafting Recipe

**Files to edit:** `shared/crafting_database.gd`

**Steps:**

1. Open `shared/crafting_database.gd` and find the recipe definitions for your crafting skill.

2. Add your recipe:
```gdscript
{
    "name": "Enchanted Iron Helm",
    "skill": "blacksmithing",
    "skill_level_required": 15,
    "materials": {
        "iron_ore": 5,
        "magic_dust": 2,
        "leather": 1
    },
    "result_type": "helm",
    "result_level": 15,
    "result_rarity": "rare",
    "result_stats": {
        "defense": 12,
        "hp_bonus": 20
    },
    "description": "A helm infused with protective magic."
},
```

3. **Ensure materials exist** — check that the material names match what gathering produces (defined in `drop_tables.gd` catch tables).

4. **Quality system** applies automatically based on the crafter's skill level.

---

## 11. Modify Combat Balance

**Files to edit:** `server/balance_config.json`

**Steps:**

1. Open `server/balance_config.json`. This is a JSON file with tuning numbers.

2. **Key sections:**

```json
{
    "player_str_multiplier": 0.02,
    "crit_base_chance": 0.05,
    "crit_max_chance": 0.25,
    "defense_constant": 100,
    "defense_max_reduction": 0.60,

    "lethality_weights": {
        "hp": 2.5,
        "strength": 7.5,
        "defense": 2.5,
        "speed": 5.0
    },

    "ability_modifiers": {
        "sunder": 0.30,
        "ethereal": 0.60,
        "berserker": 0.40,
        "weapon_master": 1.50
    },

    "xp_multiplier": 0.10,
    "gold_cap_multiplier": 2.0,
    "gem_divisor": 1000
}
```

3. **To make combat easier:** Lower monster stat weights, reduce ability modifiers.
4. **To make combat harder:** Increase lethality weights, add stronger abilities.
5. **To adjust XP:** Change `xp_multiplier` (higher = more XP per fight).

6. **Verify with combat simulator:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --script "res://tools/combat_simulator/simulator.gd" 2>&1
```
This tests all 9 classes and outputs win rates. Target: 85-95% win rate at same level.

---

## 12. Add a New Gathering Catch

**Files to edit:** `shared/drop_tables.gd`

**Steps:**

1. Open `shared/drop_tables.gd` and find the relevant catch table:
   - `FISHING_CATCHES` — fish by tier
   - `MINING_CATCHES` — ores/materials by tier
   - `LOGGING_CATCHES` — wood/materials by tier

2. Add your item to the appropriate tier:
```gdscript
# In MINING_CATCHES, tier 5:
5: [
    # ...existing catches...
    {"name": "Mithril Ore", "rarity": "rare", "weight": 5},  # Lower weight = rarer
],
```

3. **Weight** determines drop chance relative to other items in the same tier. Higher weight = more common.

4. If the material is used in crafting, make sure the name matches what `crafting_database.gd` recipes expect.

---

## 13. Add a New Monster Ability

**Files to edit:** `shared/combat_manager.gd`, `server/balance_config.json`

**Steps:**

1. **Define the ability logic** in `combat_manager.gd`. Find where monster abilities are processed (in the turn processing function):
```gdscript
# Add to the ability processing section:
if "my_new_ability" in monster.get("abilities", []):
    # Apply the ability effect
    # Examples:
    # - Modify damage: damage *= 1.3
    # - Apply debuff: add to player_buffs
    # - Heal monster: monster.hp += heal_amount
    pass
```

2. **Add the ability modifier** to `balance_config.json`:
```json
"ability_modifiers": {
    "my_new_ability": 0.25
}
```
This value affects lethality calculation (how much XP the monster gives).

3. **Add the ability to monsters** in `monster_database.gd`:
```gdscript
"Monster Name": {
    "abilities": ["my_new_ability", "sunder"],
    # ...
},
```

4. **Add display text** — when the ability triggers in combat, the player should see what happened. Add combat messages in the ability processing code:
```gdscript
messages.append("[color=#FF6600]The %s uses My New Ability![/color]" % monster_name)
```

5. **Test** with the combat simulator to verify balance impact.

---

## 14. Add a New Consumable Item

**Files to edit:** `shared/drop_tables.gd`, `server/server.gd`, `client/client.gd`

**Steps:**

1. **Add the item definition** to drop tables in `shared/drop_tables.gd`:
```gdscript
{
    "name": "Elixir of Speed",
    "type": "consumable",
    "item_type": "speed_elixir",
    "is_consumable": true,
    "level": 10,
    "rarity": "uncommon",
    "description": "Increases speed for 5 turns."
},
```

2. **Add server-side use handler** in `server/server.gd`. Find the item use handler (`handle_inventory_use` or similar) and add:
```gdscript
"speed_elixir":
    # Apply the effect
    character.add_buff("speed_boost", {"amount": 10, "turns": 5})
    send_to_peer(peer_id, {"type": "text", "message": "[color=#00FFFF]You drink the Elixir of Speed! +10 Speed for 5 turns.[/color]"})
    # Remove the item from inventory
    character.remove_item(item_index)
    send_character_update(peer_id)
```

3. **Add client-side effect description** in `client/client.gd`. Find `_get_item_effect_description()` and add:
```gdscript
"speed_elixir":
    return "+10 Speed for 5 turns"
```

4. **CRITICAL — Check item_type ordering:** In `_get_item_effect_description()`, specific subtypes (like `"speed_elixir"`) must be checked BEFORE generic catch-alls (like `"elixir" in item_type`). Put specific checks first!

5. **Add to _is_consumable_type()** if needed — this function determines if an item shows up in the "Use" action and under the consumable market category.

---

## 15. Create a Release

**Steps:**

1. **Bump the version** in `VERSION.txt`:
```bash
echo "0.9.145" > VERSION.txt
```
> **CRITICAL:** Never reuse a version number! The launcher compares versions to decide if an update is needed.

2. **Update the changelog** in `client/client.gd` → `display_changelog()` function (~line 18648). Add the new version's changes. Keep 5 most recent versions, remove oldest.

3. **Commit and push:**
```bash
git add VERSION.txt client/client.gd
git commit -m "Bump version to v0.9.145, update changelog"
git push
```

4. **Export the client build:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --export-release "Phantom-Badlands" "builds/PhantomBadlandsClient.exe"
```

5. **Create the release ZIP:**
```bash
powershell -Command "Compress-Archive -Path 'builds/PhantomBadlandsClient.exe', 'builds/PhantomBadlandsClient.pck', 'builds/libgdsqlite.windows.template_debug.x86_64.dll', 'VERSION.txt' -DestinationPath 'releases/phantom-badlands-client-v0.9.145.zip' -Force"
```

6. **Upload to GitHub:**
```bash
"/c/Program Files/GitHub CLI/gh.exe" release create v0.9.145 releases/phantom-badlands-client-v0.9.145.zip --title "v0.9.145" --notes "Description of changes"
```

7. **Verify:** The new tag version must be HIGHER than the previous release. Players' launchers will auto-detect and download the update.

---

## General Tips for Making Changes

### Before You Edit
1. **Search first** — use Ctrl+F to find related code. Names are consistent.
2. **Read existing examples** — look at how similar features are implemented.
3. **Check for duplicate names** — constants and variable names must be unique per file.

### After You Edit
1. **Validate** — run `--check-only` on modified scripts to catch syntax errors.
2. **Test both paths** — keyboard AND mouse click for any action bar buttons.
3. **Test output persistence** — wait 2 seconds after any action to confirm output isn't cleared.
4. **Check all affected modes** — your change might affect multiple game states.

### Common Gotchas
- **Forgot to add to command_keywords** → command goes to chat instead of being processed
- **Forgot execute_local_action()** → button click does nothing (even if keyboard works)
- **Forgot _consume_item_select_key()** → number key triggers both item selection AND action bar
- **Forgot character_update bypass** → output disappears after 1-2 seconds
- **Used dot access on dict** → crashes if key missing (always use `.get("key", default)`)
- **JSON float keys** → `int(value)` before using as dictionary key
- **Serialization key mismatch** → saved as "xp_reward" but read as "experience_reward"

### The Golden Rules
1. **Action bar first** — new features go on the action bar, not chat commands
2. **Server validates everything** — never trust client input
3. **Always use .get() with defaults** — for any dictionary from JSON/network
4. **Test output persistence** — player must be able to READ results
5. **Both input paths** — keyboard AND mouse click must work
6. **Call update_action_bar()** — after every state change
