# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Quick Start

**Detailed diagrams in `/docs/`:**
- `QUICK_REFERENCE.md` - Condensed overview, file map, common tasks
- `architecture.md` - System architecture, data flow, class hierarchy
- `action-bar-states.md` - Complete action bar state machine (CRITICAL for UI work)
- `combat-flow.md` - Combat lifecycle, damage formulas, monster abilities
- `networking-protocol.md` - All message types, sequence diagrams
- `quest-system.md` - Quest flow, trading posts
- `game-systems.md` - Feature documentation (gems, trading, abilities, etc.)

## Project Overview

Phantasia Revival is a text-based multiplayer RPG built with Godot 4.5 and GDScript. Client-server architecture with turn-based combat, procedural world generation, and 9 class archetypes.

## UI Design Principle: Action Bar First

**IMPORTANT: Always prefer Action Bar over chat commands when implementing new features.**

- New features should be accessible via the Action Bar, not `/commands`
- The Action Bar has 10 slots (Space, Q, W, E, R, 1-5) with contextual buttons
- Slot 4 (R key) is the "contextual location action" - shows different buttons based on location:
  - At water: Fish
  - At dungeon entrance: Dungeon
  - At Infernal Forge: Forge
  - Otherwise: Quests
- Chat commands can exist as fallbacks but shouldn't be the primary interface
- See `docs/action-bar-states.md` for the full state machine

## Player-Visible Output Rule

**CRITICAL: All feature results MUST be visible to the player.**

### The Problem
The server frequently sends messages (`character_update`, `location`, `text`, etc.) that can trigger UI refreshes. When the client receives these while in ANY mode (inventory, merchant, trading post, crafting, etc.), the default behavior often calls a display function that clears `game_output`. This wipes out any results the player was trying to read.

**This affects ALL modes and actions, not just inventory:**
- `inventory_mode` → `display_inventory()` clears output
- `at_merchant` → merchant display functions clear output
- `at_trading_post` → trading post display clears output
- `crafting_mode` → crafting display clears output
- `ability_mode` → ability mapping display clears output
- `settings_mode` → settings display clears output
- Using items → result message cleared by character_update
- Viewing materials → cleared by inventory refresh
- Any action with results → can be wiped by incoming messages

**Specific actions that have caused this bug:**
- Salvaging items (result message wiped)
- Viewing crafting materials (view cleared immediately)
- Mapping abilities to slots (confirmation wiped)
- Using consumables (effect message wiped)
- Any "view" or "inspect" action in a submenu

### Mandatory Checklist for New Actions in ANY Mode

When implementing ANY new action that displays something the player needs to read, you MUST:

**Step 1: Create a pending/state flag**
```gdscript
# Use the appropriate pending variable for the mode:
pending_inventory_action = "my_new_action"      # For inventory mode
pending_merchant_action = "my_new_action"       # For merchant mode
pending_trading_post_action = "my_new_action"   # For trading post mode
pending_ability_action = "my_new_action"        # For ability mode
rebinding_action = "my_new_action"              # For settings/keybind mode
# Or create a new state variable if needed for entirely new modes
```

**Existing state flags to be aware of:**
- `awaiting_item_use_result` - Prevents text message from displaying during item use
- `awaiting_salvage_result` - Prevents inventory refresh after salvage
- `viewing_materials` - Prevents inventory refresh while viewing materials
- `sort_select`, `salvage_select` - Submenu states in inventory
- `equip_confirm`, `unequip_item` - Equipment action states

**Step 2: Add action bar state for the new view**
Find the appropriate mode's action bar section in `update_action_bar()` (~line 3700-4200) and add:
```gdscript
elif pending_xxx_action == "my_new_action":
    current_actions = [
        {"label": "Back", "action_type": "local", "action_data": "my_action_back", "enabled": true},
        # ... other buttons
    ]
```

**Step 3: CRITICAL - Add bypass in message handlers**
Find where incoming messages trigger UI refreshes and add your state to prevent clearing:

```gdscript
# In "character_update" handler (~line 9910-9990):
# Find the mode check (e.g., `if inventory_mode:`) and add:
elif pending_inventory_action == "my_new_action":
    pass  # Don't redisplay - keep showing current view

# Similar patterns exist for other modes - search for where
# display functions are called after receiving server messages
```

**Step 4: Add handler to exit the view**
```gdscript
"my_action_back":
    pending_xxx_action = ""
    display_xxx()  # Return to parent view
    update_action_bar()
```

**Step 5: CRITICAL - Add to item selection exclusion list** (~line 1751 in client.gd)
The `_process()` function has item selection handling that checks `pending_inventory_action`. If your new state isn't excluded, number key presses will be processed as item selections AND action bar presses simultaneously, causing immediate unwanted actions.

```gdscript
# Find this line and add your state to the exclusion list:
if ... and pending_inventory_action not in ["equip_confirm", "sort_select", "salvage_select", "viewing_materials", "awaiting_salvage_result", "YOUR_NEW_STATE"] and ...
```

### Common Patterns That Cause This Bug
1. Server sends result via `"text"` message → displayed correctly
2. Server sends `"character_update"` immediately after → triggers mode refresh
3. Mode refresh calls `display_xxx()` → clears the text message
4. Player sees results for a split second, then gone

**Real examples from this codebase:**
- Player salvages items → "Salvaged 5 items for 150 essence!" appears → character_update arrives → `display_inventory()` called → message gone
- Player views materials → materials list shows → character_update arrives → `display_inventory()` called → back to inventory
- Player uses potion → "+50 HP!" appears → character_update arrives → combat/inventory refresh → message gone
- Player maps ability → "Ability assigned to slot 3" → character_update → ability list refreshes → message gone
- Player changes setting → "Setting saved" → any update → settings redisplay → message gone

**Another common cause - Item Selection Conflict:**
The `_process()` function (~line 1751) handles item selection with number keys (1-9). If your new `pending_inventory_action` state isn't in the exclusion list, pressing a number key to select an action bar button ALSO triggers item selection handling, which can immediately call `display_inventory()` or other functions.

Example: Player presses "3" for Materials button → action bar processes "view_materials" → BUT _process() also sees key "3" as item selection → processes item at index 3 → calls display_inventory() → materials view immediately replaced

### How to Verify Your Implementation
1. Trigger your new action
2. Confirm the output displays
3. Wait 1-2 seconds (server messages arrive)
4. Output should STILL be visible
5. Test pressing Back - should return to parent view correctly

### Quick Reference - Where Refreshes Happen
Search client.gd for these to find where to add bypasses:
- `if inventory_mode:` in character_update handler (~line 9926)
- `if at_merchant` in character_update handler
- `if at_trading_post` in various handlers
- `if ability_mode` in relevant handlers
- `if settings_mode` in relevant handlers
- Any `display_xxx()` call triggered by incoming messages
- Any `game_output.clear()` call in message handlers

**Key message types that trigger refreshes:**
- `"character_update"` - Most common culprit, sent after almost every server action
- `"location"` - Sent on movement, can affect displayed state
- `"text"` - Usually safe, but check `awaiting_item_use_result` pattern
- `"combat_update"` - Refreshes combat display
- `"inventory_update"` - If it exists, will refresh inventory

**Features are useless if players can't see what happened.**

## Running the Project

**Godot executable:** `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`

**Preferred Launch (with output capture):**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" server/server.tscn 2>&1 &
sleep 3
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" client/client.tscn 2>&1
```
Use `run_in_background: true` and 600000ms timeout. Read output file to see console messages.

**Simple Launch:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" server/server.tscn &
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" client/client.tscn &
```

**Validate GDScript:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --check-only --script "res://shared/character.gd" 2>&1
```

## Key Files

| File | Purpose |
|------|---------|
| `client/client.gd` | Client UI, networking, action bar (~8000 lines) |
| `client/monster_art.gd` | ASCII art rendering |
| `server/server.gd` | Server logic, message routing (~4000 lines) |
| `shared/character.gd` | Player stats, inventory, equipment |
| `shared/combat_manager.gd` | Turn-based combat engine |
| `shared/world_system.gd` | Terrain, hotspots, coordinates |
| `shared/monster_database.gd` | Monster definitions (9 tiers) |
| `shared/quest_database.gd` | Quest definitions |
| `shared/drop_tables.gd` | Item generation |

## Adding ASCII Art

**Location:** `client/monster_art.gd` in `get_art_map()`

**Format:**
```gdscript
"Monster Name": ["[color=#HEXCOLOR]",
"line 1 of art",
"line 2 of art","[/color]"],
```

**Two Size Categories:**
1. **Wide Art (>50 chars)** - Copy EXACTLY as-is, preserve all whitespace
2. **Small Art (≤50 chars)** - Auto-centered with border, no padding needed

**Source Files:** `C:\Users\Dexto\Desktop\Phantasia_Project\ASCII\`

**Colors by Type:**
- Green `#00FF00` - Goblins, nature
- Brown `#8B4513` - Animals
- Gray `#808080` - Undead, golems
- Red `#FF0000` - Demons, fire
- Blue `#0070DD` - Water/ice
- Purple `#A335EE` - Magical beings

## Releases & Distribution

**GitHub:** https://github.com/Dextobust33/Phantasia-Revival

**Creating a Release:**
```bash
# 1. Update version
echo "0.3" > VERSION.txt

# 2. Export client
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --export-release "Phantasia-Revival" "builds/PhantasiaClient.exe"

# 3. Create ZIP
powershell -Command "Compress-Archive -Path 'builds/PhantasiaClient.exe', 'builds/PhantasiaClient.pck', 'builds/libgdsqlite.windows.template_debug.x86_64.dll', 'VERSION.txt' -DestinationPath 'releases/phantasia-client-v0.3.zip' -Force"

# 4. Upload to GitHub
"/c/Program Files/GitHub CLI/gh.exe" release create v0.3 releases/phantasia-client-v0.3.zip --title "v0.3" --notes "Description"

# 5. Push code
git push
```

## Maintenance Reminders

- **Update Help Page:** After mechanics change, update `client/client.gd` `show_help()` (~line 5024)
- **After significant changes:** Remind user to create a release for players

## Code Conventions

- GDScript follows Godot conventions: `class_name` for types, `@onready` for node refs
- TCP polling in `_process()` for networking
- UI uses RichTextLabel with BBCode
- Three-panel layout: GameOutput, ChatOutput, MapDisplay

## Action Bar Critical Rules

**See `docs/action-bar-states.md` for full state machine.**

Key rules:
1. **Always call `update_action_bar()` after state changes**
2. State priority: settings > trade > combat > merchant > inventory > trading_post > movement
3. Action bar slots 5-9 share keys with item selection (1-5)
4. When adding sub-menus using buttons, exclude from item selection at ~line 1451
5. **CRITICAL: Mark hotkeys as pressed when exiting modes via key press** (see Pitfall #7)

## Monster HP Knowledge System (IMPORTANT)

Players discover monster HP through combat experience, NOT by seeing actual HP values.

**How it works:**
1. **First encounter** - Player doesn't know monster HP (shows "???" on HP bar)
2. **After killing** - "Known HP" = total damage dealt in that fight (may be higher than actual HP due to overkill)
3. **Future encounters** - If player has killed same monster type at same or higher level, HP is "known"
4. **Estimation** - If player killed monster type at higher level, can estimate HP for lower levels

**Key points:**
- Known HP is based on DAMAGE DEALT, not actual monster HP
- If player kills same monster more efficiently later, known HP drops to the new lower value
- This creates a discovery system where players gradually learn true HP values
- Magic Bolt suggestions use client's `known_enemy_hp` tracking, NOT server's actual HP

**Implementation:**
- Server: `character.knows_monster()` tracks highest level killed per type
- Server: Sends `monster_hp = -1` if player doesn't know monster
- Client: `known_enemy_hp` dictionary tracks damage dealt per monster/level
- Client: `estimate_enemy_hp()` scales known HP to estimate for other levels

**Files:** `shared/character.gd` (knows_monster), `client/client.gd` (known_enemy_hp, estimate_enemy_hp)

## Common Pitfalls

### 1. Duplicate Constants
**Error:** `Constant "X" has the same name as a previously declared constant`
**Fix:** Grep file for constant name before adding

### 2. Variable Name Mismatches
**Error:** `Identifier "X" not declared`
**Fix:** Check file's variable declarations (e.g., `monster_db` vs `monster_database`)

### 3. Slash Commands Go to Chat
**Cause:** Command matching didn't strip leading `/`
**Location:** `client/client.gd` in `handle_input_submitted()` and `process_command()`

### 4. BBCode Breaks Padding
BBCode tags add to string length but don't display. Use separate lines instead of `%-30s` format specifiers.

### 5. Static Functions and Constants
GDScript 4 static functions CAN access class constants. If errors occur, check for typos.

### 6. New Commands Need Whitelist Entry
**Symptom:** New `/command` goes to chat instead of being processed
**Cause:** Commands must be added to TWO places in `client/client.gd`:
1. `command_keywords` array (~line 8993) - whitelist that routes input to `process_command()` instead of chat
2. `process_command()` match statement (~line 9421) - actual command handler

**Also for server-side commands:** Add to `server/server.gd`:
1. `handle_message()` match statement (~line 470)
2. Create the handler function

### 7. Mode Exit Hotkey Double-Trigger (CRITICAL)
**Symptom:** When exiting a mode via hotkey (Space, Q, number keys), the action bar also triggers
**Cause:** `_input()` handles the key and sets `mode = false`, but `_process()` polls `Input.is_physical_key_pressed()` which still sees the key as held, so action bar triggers too

**Fix:** When exiting a mode via key press in `_input()`, mark the corresponding hotkey as pressed:
```gdscript
# Before setting mode = false:
set_meta("hotkey_0_pressed", true)  # For Space/action_0
set_meta("hotkey_1_pressed", true)  # For Q/action_1
# etc.

# For number keys 1-5 (item selection keys):
var action_slot = item_index + 5  # KEY_1 = action_5, KEY_2 = action_6, etc.
set_meta("hotkey_%d_pressed" % action_slot, true)
```

**When to apply:**
- Any mode that handles keys in `_input()` and is NOT in the `should_process_action_bar` exclusion list
- Currently excluded: `settings_mode`, `combat_item_mode`, `monster_select_mode`, `title_mode`
- Modes that need this fix when exiting: `ability_mode`, any new custom modes

**Location:** `client/client.gd` ~line 1755 for exclusion list, ~line 1780 for hotkey processing
