# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Quick Start

**Detailed diagrams in `/docs/`:**
- `QUICK_REFERENCE.md` - Condensed overview, file map, common tasks
- `SYSTEM_OVERVIEW.md` - Dense AI context reference (mode flags, message types, conventions)
- `CODE_GUIDE.md` - Walkthrough for modifying the game (templates, patterns, debugging)
- `architecture.md` - System architecture, data flow, class hierarchy
- `action-bar-states.md` - Complete action bar state machine (CRITICAL for UI work)
- `combat-flow.md` - Combat lifecycle, damage formulas, monster abilities
- `networking-protocol.md` - All message types, sequence diagrams
- `quest-system.md` - Quest flow, trading posts
- `game-systems.md` - Feature documentation (all game systems)

## Project Overview

Phantom Badlands is a text-based multiplayer RPG built with **Godot 4.6** and GDScript. Client-server architecture with turn-based combat, procedural world generation, and 9 class archetypes.

**Godot Version:** 4.6.stable.steam (godot.windows.opt.tools.64.exe)
**Important:** Some Godot 4.x API methods differ from 4.3/4.4 docs. Example: RichTextLabel uses `pop()` not `pop_meta()`.

## UI Design Principle: Action Bar First

**IMPORTANT: Always prefer Action Bar over chat commands when implementing new features.**

- New features should be accessible via the Action Bar, not `/commands`
- The Action Bar has 10 slots (Space, Q, W, E, R, 1-5) with contextual buttons
- Slot 4 (R key) is the "contextual location action" - shows different buttons based on location:
  - At water (~): Fish
  - At ore deposit (mountains): Mine
  - At dense forest: Chop
  - At dungeon entrance (D): Dungeon
  - At Infernal Forge: Forge
  - Otherwise: Quests
- Chat commands can exist as fallbacks but shouldn't be the primary interface
- See `docs/action-bar-states.md` for the full state machine

## Admin Commands: /admin UI, Not Chat

**IMPORTANT: All NEW admin/dev/testing tools go through the visual `/admin` panel — not new `/command` chat shorthands.**

- Visual panel: `client/admin_panel.gd`. Pages are `root` / `test_b2` / `items` / `combat` / `misc` / `world` (see `_current_page`).
- Pattern: each button emits `action_triggered(action_id)` → client.gd's `_on_admin_panel_action()` dispatches a `gm_*` server message → `handle_gm_*` server handler gated by `_is_admin(peer_id)`.
- Do NOT extend the `command_keywords` array or `process_command()` match statement with new top-level admin commands. The `/gmhelp` chat list and existing `/setlevel`, `/tp`, `/giveconsumable`, etc. are legacy.
- Existing chat admin commands stay as fallbacks — don't migrate in a cleanup pass without explicit ask (muscle memory).
- Same principle generalizes: **UI control over chat controls** for all new features (player or admin). Chat is a legacy fallback surface, never the primary interface for new mechanics.

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
Find the appropriate mode's action bar section in `update_action_bar()` (~line 4348+) and add:
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
# In "character_update" handler (~line 14523+):
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

**Step 5: CRITICAL - Add to item selection exclusion list** (~line 1866 in client.gd)
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

### How to Verify Your Implementation
1. Trigger your new action
2. Confirm the output displays
3. Wait 1-2 seconds (server messages arrive)
4. Output should STILL be visible
5. Test pressing Back - should return to parent view correctly

### Quick Reference - Where Refreshes Happen
Search client.gd for these to find where to add bypasses:
- `if inventory_mode:` in character_update handler (~line 14540)
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
| `client/client.gd` | Client UI, networking, action bar (~21000+ lines) |
| `client/monster_art.gd` | ASCII art rendering for monsters and eggs |
| `client/trader_art.gd` | Trader ASCII art (persistent per-post) |
| `client/trading_post_art.gd` | Trading post ASCII art by category |
| `server/server.gd` | Server logic, message routing (~14000+ lines) |
| `server/persistence_manager.gd` | SQLite persistence, houses, kennel, market, valor |
| `server/balance_config.json` | Combat tuning, lethality weights, ability modifiers |
| `shared/character.gd` | Player stats, inventory, equipment, companions |
| `shared/combat_manager.gd` | Turn-based combat engine (solo + party) |
| `shared/world_system.gd` | Terrain, hotspots, procedural world, tile detection |
| `shared/chunk_manager.gd` | 32x32 chunk system for world streaming (delta JSON) |
| `shared/monster_database.gd` | Monster definitions (9 tiers), variant generation |
| `shared/quest_database.gd` | Quest definitions, dynamic daily generation |
| `shared/quest_manager.gd` | Quest tracking, turn-in logic, party sync |
| `shared/dungeon_database.gd` | Dungeon types, floors, bosses, sub-tier system |
| `shared/drop_tables.gd` | Item gen, gathering catches, salvage, tools, eggs |
| `shared/crafting_database.gd` | Crafting recipes, materials, specialty job gating |
| `shared/npc_post_database.gd` | NPC post definitions, station layouts |
| `shared/trading_post_database.gd` | Trading post categories, shapes, colors |
| `shared/titles.gd` | Title/rank system |
| `tools/combat_simulator/` | Combat simulation tool for balance testing |

## Combat Simulator Tool

**Location:** `tools/combat_simulator/`

The combat simulator tests monster lethality against all 9 character classes to calibrate XP rewards. It runs headless simulations of thousands of fights and outputs analysis comparing empirical danger vs formula predictions.

**Run the simulator:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --script "res://tools/combat_simulator/simulator.gd" 2>&1
```

**Output files:**
- `docs/simulation_results/YYYY-MM-DD_results.json` - Raw simulation data
- `docs/simulation_results/YYYY-MM-DD_summary.md` - Human-readable analysis

**Key files:** `simulator.gd` (entry point), `combat_engine.gd` (damage formulas + abilities), `simulated_character.gd`, `gear_generator.gd`, `results_writer.gd`

**Expanding the simulator:**
1. Add new abilities in `combat_engine.gd` — see `WARRIOR_ABILITIES`, `MAGE_ABILITIES`, `TRICKSTER_ABILITIES` constants
2. Update `simulate_single_combat()` AI to use new abilities strategically
3. Adjust lethality weights in `server/balance_config.json` based on results
4. Empirical lethality: `(1 / win_rate) × (1 + damage_ratio) × 100`
5. Formula: `lethality = (HP×hp_w + STR×str_w + DEF×def_w + Speed×spd_w) × (1 + ability_modifiers)`

**Latest results:** `docs/simulation_results/2026-02-06_summary.md` — All classes 89-96% win rate, balance good at Lv5-5000.

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

**GitHub:** https://github.com/Dextobust33/Phantom-Badlands
**Website:** https://phantombadlands.com (GitHub Pages from `docs/`)
**Game Server:** Hetzner Cloud CPX11 at `5.78.217.135:9080` (Hillsboro, OR — migrated from Oracle 2026-05-12 for ~16× compute, $6.99/mo)

### Creating a Client Release:
```bash
# 1. Bump version (NEVER reuse a version number)
echo "X.Y.Z" > VERSION.txt

# 2. Commit and push
git add VERSION.txt && git commit -m "vX.Y.Z: description" && git push

# 3. Export client
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --export-release "Phantom-Badlands" "builds/PhantomBadlandsClient.exe"

# 4. Create ZIPs (client + launcher — BOTH must be in every release)
cp VERSION.txt builds/VERSION.txt
cp CREDITS.md builds/CREDITS.md
powershell -Command "Compress-Archive -Path 'builds/PhantomBadlandsClient.exe', 'builds/PhantomBadlandsClient.pck', 'builds/libgdsqlite.windows.template_debug.x86_64.dll', 'builds/VERSION.txt', 'builds/CREDITS.md' -DestinationPath 'releases/phantom-badlands-client-vX.Y.Z.zip' -Force"
powershell -Command "Compress-Archive -Path 'builds/PhantomBadlandsLauncher.exe' -DestinationPath 'releases/phantom-badlands-launcher.zip' -Force"

# 5. Create GitHub release (MUST include both ZIPs)
"/c/Program Files/GitHub CLI/gh.exe" release create vX.Y.Z releases/phantom-badlands-client-vX.Y.Z.zip releases/phantom-badlands-launcher.zip --title "vX.Y.Z" --notes "Description"
```

**CRITICAL:** The launcher ZIP must be included in EVERY release because the website download link points to `releases/latest/download/phantom-badlands-launcher.zip`. If missing, new players can't download.

### Creating a Linux Client Release:
The Linux client + launcher are exported by a dedicated script. Run it AFTER the Windows ZIPs are staged so the same `vX.Y.Z` GitHub release carries all four assets.
```bash
# Builds Linux client (single binary, PCK embedded) + Linux launcher, then ZIPs both.
bash build_linux_release.sh
# Produces:
#   releases/phantom-badlands-client-linux-vX.Y.Z.zip  (binary + libgdsqlite .so + VERSION + CREDITS)
#   releases/phantom-badlands-launcher-linux.zip        (launcher binary)
```
- **Presets:** `Phantom-Badlands-Linux` (preset.2 in `export_presets.cfg`) and `Linux` (preset.1 in `launcher/export_presets.cfg`).
- **sqlite .so:** the Linux client ships `libgdsqlite.linux.template_release.x86_64.so` flat next to the binary — same layout the production server uses (`~/phantom-badlands/`).
- **Launcher cross-platform:** `launcher/launcher.gd` detects OS — `.x86_64` exe name on Linux, picks the `*-linux-*` client zip, and `chmod +x`'s the extracted client (ZIP drops the exec bit). The launcher binary itself the user chmods once (documented on the website).
- **Single release, four assets:** include the Linux client/launcher ZIPs alongside the Windows ones in the same `gh release create` call:
```bash
"/c/Program Files/GitHub CLI/gh.exe" release create vX.Y.Z \
  releases/phantom-badlands-client-vX.Y.Z.zip releases/phantom-badlands-launcher.zip \
  releases/phantom-badlands-client-linux-vX.Y.Z.zip releases/phantom-badlands-launcher-linux.zip \
  --title "vX.Y.Z" --notes "Description"
```

### Deploying Server Updates:
```bash
# One-command deploy (exports, uploads, restarts):
bash deploy_server.sh

# Or manually:
# 1. Export Linux server
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --export-release "Phantom-Badlands-Server-Linux" "builds/server/PhantomBadlandsServer.x86_64"

# 2. Upload and restart
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
scp -i "$SSH_KEY" builds/server/PhantomBadlandsServer.x86_64 ubuntu@5.78.217.135:~/phantom-badlands/
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "chmod +x ~/phantom-badlands/PhantomBadlandsServer.x86_64 && sudo systemctl restart phantom-badlands"
```

### Server Management:
```bash
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
# Check status
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "sudo systemctl status phantom-badlands --no-pager"
# View logs
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "sudo journalctl -u phantom-badlands -n 50 --no-pager"
# Restart
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "sudo systemctl restart phantom-badlands"
# Stop
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "sudo systemctl stop phantom-badlands"
```

## Maintenance Reminders

- **Update Help Page:** After mechanics change, update `client/client.gd` `show_help()` (~line 21639)
- **Update Changelog:** When creating a release, update `display_changelog()` in `client/client.gd` (~line 19938) with new version's changes. Keep 5 most recent versions visible, remove oldest when adding new.
- **Include launcher ZIP:** Every GitHub release MUST include `phantom-badlands-launcher.zip` alongside the client ZIP.
- **Deploy server:** After server-side changes, run `bash deploy_server.sh` to update the cloud server.
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
4. When adding sub-menus using buttons, exclude from item selection at ~line 1866
5. **CRITICAL: Mark hotkeys as pressed when exiting modes via key press** (see Pitfall #7)
6. **GOLDEN RULE: A single hotkey press must NEVER trigger actions in two different menus.** When a hotkey opens a new menu/mode, any item selection keys that are currently held must be pre-marked as pressed in the new mode so they don't immediately trigger a selection. Pattern:
```gdscript
# When entering a mode that uses item selection keys (1-9):
for i in range(9):
    if is_item_select_key_pressed(i):
        set_meta("itemkey_%d_pressed" % i, true)
```
This applies to ALL mode transitions triggered by shared keys (action bar slots 5-9 / keys 1-5). The key must be released and re-pressed to trigger an action in the new menu.

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

## Gathering & Crafting System

**Gathering modes** (Fishing, Mining, Logging) follow the same pattern:
1. Player arrives at location (water/ore/forest) → `at_water`, `at_ore_deposit`, `at_dense_forest` flags set
2. Action bar slot 4 shows contextual button (Fish/Mine/Chop)
3. Player starts gathering → client enters `fishing_mode`/`mining_mode`/`logging_mode`
4. Minigame: Wait phase → Reaction phase (press correct key)
5. Server validates and returns catch → client displays result

**Terrain detection:** `world_system.gd` has `is_water_tile()`, `is_ore_deposit()`, `is_dense_forest()` using hash-based procedural placement.

**Tier scaling:** Mining (9 tiers) and Logging (6 tiers) scale by distance from origin. Higher tiers require more successful reactions (T1-2: 1, T3-5: 2, T6+: 3).

**Salvage system:** Inventory → Salvage → select item. Converts items to Salvage Essence (ESS) with bonus material chance. Values in `drop_tables.gd` `SALVAGE_VALUES`.

**Materials viewing:** Inventory → Materials shows gathered resources grouped by type.

**Key files:**
- `shared/drop_tables.gd` - `FISHING_CATCHES`, `MINING_CATCHES`, `LOGGING_CATCHES`, `SALVAGE_VALUES`
- `shared/world_system.gd` - Terrain detection functions
- `shared/character.gd` - `fishing_skill`, `mining_skill`, `logging_skill`, `salvage_essence`

## Dungeon System

**Monster consistency:** All encounters in a dungeon use the same monster type as the boss. The boss's `monster_type` field in `dungeon_database.gd` determines what spawns (e.g., Orc Stronghold = all Orcs).

**Level requirements:** Dungeons have a recommended level (`min_level`) but don't block entry. Instead:
1. If player level < min_level, server sends `dungeon_level_warning` message
2. Client shows warning with "Enter Anyway" / "Cancel" buttons
3. Player can confirm to enter despite the warning
4. `pending_dungeon_warning` dictionary tracks pending confirmation

**Boss generation:** `get_boss_for_dungeon()` returns both `name` (display name like "Orc Warlord") and `monster_type` (base monster like "Orc"). Server uses `monster_type` to generate the monster, then renames it to the display name.

**World Dungeons vs Player Instances (IMPORTANT):**
- **World dungeons** (`_create_world_dungeon()`) are map markers showing 'D' tiles. They exist in `active_dungeons` with NO `owner_peer_id`. They are NOT the dungeon a player actually enters.
- **Player instances** (`_create_player_dungeon_instance()`) are created when a player enters a 'D' tile. They have `owner_peer_id` set. Each player gets their own instance.
- When a player enters a world dungeon 'D' tile, `handle_dungeon_enter()` calls `_mark_world_dungeon_completed()` to set `completed_at` on the world marker, then creates a personal instance.
- `_check_dungeon_spawns()` removes completed world dungeons after `DUNGEON_DESPAWN_DELAY` (60s) and spawns replacements.
- **CRITICAL:** `_create_world_dungeon()` MUST check `existing_coords` to prevent stacking multiple dungeons on the same tile. `_create_player_dungeon_instance()` already does this.
- `get_visible_dungeons()` and `_get_dungeon_at_location()` both skip `completed_at > 0` entries.

**Key files:**
- `shared/dungeon_database.gd` - Dungeon definitions, `get_monster_for_encounter()`, `get_boss_for_dungeon()`
- `server/server.gd` - `handle_dungeon_enter()`, `_start_dungeon_encounter()`, `_create_world_dungeon()`, `_mark_world_dungeon_completed()`

## Companion System

**Structure:**
- `companions_mode` - Main companions page (More → Companions)
- `eggs_mode` - Separate eggs page with ASCII art (More → Eggs)
- `pending_companion_action` - States: "", "release_select", "release_confirm", "inspect_select", "inspect"

**Eggs display:** Eggs have variant info (color, color2, pattern) set at creation. `display_eggs()` shows ASCII art using `MonsterArt.get_egg_art()` with patterns like solid, gradient, striped, etc.

**Egg Freezing:** Players can freeze eggs to pause hatching progress (via More → Eggs action bar). Frozen eggs:
- Have `frozen: true` field in egg dictionary
- Are skipped by `process_egg_steps()` in character.gd
- Display "[FROZEN]" and "PAUSED" status in eggs UI
- Can still be traded with other players
- Perfect for saving eggs until player finds a Home Stone

**Companion Sorting:** Players can sort companions on the companions page:
- Sort options: level, tier, variant (rarity), damage (estimated), name, type
- Variables: `companion_sort_option`, `companion_sort_ascending`
- Functions: `_sort_companions()`, `_get_variant_sort_value()`, `_get_companion_sort_damage_value()`

**Companion Trading:** Players can trade companions and eggs:
- Trade window has tabs: Items, Companions, Eggs (trade_tab variable)
- Server messages: `trade_add_companion`, `trade_remove_companion`, `trade_add_egg`, `trade_remove_egg`
- Active companions cannot be traded (must dismiss first)
- Registered house companions cannot be traded

**Companion inspection:** Select companion → `display_companion_inspection()` shows:
- Level, XP progress, variant bonuses
- All abilities (passive/active/threshold) with unlock levels and descriptions
- Each monster type has unique abilities defined in `drop_tables.gd` `COMPANION_MONSTER_ABILITIES`

**Key files:**
- `client/client.gd` - `display_companions()`, `display_eggs()`, `display_companion_inspection()`, `_sort_companions()`
- `client/monster_art.gd` - `get_egg_art()`, `EGG_ART_TEMPLATE`
- `shared/drop_tables.gd` - `get_egg_for_monster()`, `EGG_VARIANTS`, `COMPANION_MONSTER_ABILITIES`
- `shared/character.gd` - Companion level cap (10000), XP formula `pow(level+1, 2.0)*15`, `process_egg_steps()` (frozen egg logic)
- `server/persistence_manager.gd` - `KENNEL_CAPACITY_TABLE`, kennel/fusion house data

## Sanctuary (House) System

**Overview:** Account-level persistent home that survives character permadeath. Players see their Sanctuary after login, before character select.

**Data Storage:** `user://data/houses.json` - managed by `persistence_manager.gd`. See code for full data structure.

**Companion Kennel:** Bulk companion storage (30-500 slots) for the Fusion Station. Walk onto K tile.
**Fusion Station:** Walk onto F tile. 3 same-type → 1 higher sub-tier. 8 mixed sub-tier 8 → random T9.

**Game State Flow:** Login → HOUSE_SCREEN → Character Select → Playing

**Baddie Points:** Meta-currency earned on character death. Formula in `persistence.calculate_baddie_points()`.

**Registered Companions:** Companions registered to house survive character death:
- Use Home Stone (Companion) to register active companion
- `character.using_registered_companion` and `character.registered_companion_slot` track checkout
- On death, `_award_baddie_points_on_death()` calls `persistence.return_companion_to_house()`

**Home Stone Items:** Found in tier 5-7 loot. Types:
- `home_stone_egg` - Send one incubating egg to house storage
- `home_stone_supplies` - Send up to 10 consumables to house storage
- `home_stone_equipment` - Send one equipped item to house storage
- `home_stone_companion` - Register active companion to house

**Key Files:**
- `server/persistence_manager.gd` - House CRUD, `HOUSE_UPGRADES` constants, `calculate_baddie_points()`
- `server/server.gd` - `handle_house_request()`, `handle_house_upgrade()`, `_award_baddie_points_on_death()`
- `client/client.gd` - `GameState.HOUSE_SCREEN`, `display_house_main()`, `display_house_storage()`, etc.
- `shared/character.gd` - `house_bonuses`, `using_registered_companion`, `registered_companion_slot`
- `shared/drop_tables.gd` - Home Stone item definitions in tier 5-7 tables

**Client Variables:**
- `house_data` - Current house data from server
- `house_mode` - Current house tab: "", "main", "storage", "companions", "upgrades", "kennel", "fusion"
- `pending_house_action` - Action state within house mode

## Market System

**Overview:** Players list items at trading posts to earn Valor (the universal currency). Other players can buy listed items using Valor.

**Categories:** Equipment, Companion Eggs, Consumables, Tools, Runes, Materials, Monster Parts

**Key concepts:**
- `base_valor` - Seller receives this immediately on listing
- `markup_price` - Buyer pays this (includes supply/demand markup)
- Markup based on supply at each trading post per category
- Bulk listing: list all equipment, all consumables/tools, or all materials at once
- Items stack in browse view (except equipment, eggs, tools which are unique)

**Key files:**
- `server/persistence_manager.gd` - `get_market_listings()`, `add_market_listing()`, `buy_market_listing()`, `calculate_markup()`
- `server/server.gd` - `handle_market_browse()`, `handle_market_list_item()`, `handle_market_buy()`
- `client/client.gd` - `display_market_main()`, `display_market_browse()`, `display_market_my_listings()`

**Client Variables:**
- `market_mode` - Boolean, at market
- `pending_market_action` - Sub-state: "browse", "list_select", "list_material", "buy_confirm", "my_listings"
- `market_category` - Filter: "all", "equipment", "egg", "consumable", "tool", "rune", "material", "monster_part"
- `market_sort` - Sort mode: "category", "price_asc", "price_desc", "name", "level"
- `account_valor` - Player's current valor balance

## Party System

**Overview:** Up to 4 players form a party. Leader moves, followers trail in snake formation. Combat scales monster HP by party size.

**Formation:** Walk into another player → invite sent. Both choose Lead/Follow.

**Movement:** Snake pattern — leader moves, followers occupy previous positions in join order.

**Combat:** Monster HP scales by party size. Weighted targeting (halving redistribution). Full XP/gold/loot duplicated per survivor. Death → spectate. Flee → spectate.

**Party Dungeons:** All members enter shared instance. Snake movement in dungeon. Party combat for encounters/bosses. Guaranteed boss egg for each member.

**Key data (server):**
- `active_parties` - party_id → {leader, members[], created_at}
- `party_membership` - peer_id → party_id
- `pending_party_invites` - peer_id → {from, to, timestamp}

**Key data (client):**
- `in_party`, `is_party_leader`, `party_members` array
- `party_combat_active`, `party_waiting_for_turn`, `party_combat_spectating`

**Max 4 players per party. Items disabled in party combat.**

## Player Posts (Enclosures)

**Overview:** Players can build named enclosures on the world map as safe zones. All visitors can use them.

**Mechanics:**
- Built via building mode at valid locations
- Require `post_slots` house upgrade for additional posts
- Compass hints point other players toward posts
- Posts are visible on the map as colored tiles

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
1. `command_keywords` array (~line 15835) - whitelist that routes input to `process_command()` instead of chat
2. `process_command()` match statement (~line 16505) - actual command handler

**Also for server-side commands:** Add to `server/server.gd`:
1. `handle_message()` match statement (~line 755)
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

**Location:** `client/client.gd` ~line 1866 for exclusion list, ~line 2547 for hotkey processing

### 8. JSON Float vs Integer Dictionary Keys
**Symptom:** Dictionary lookup with `.has()` returns false even though key appears to exist
**Cause:** JSON stores all numbers as floats (e.g., `1.0`), but GDScript const dictionaries use integer keys. `{1: "data"}.has(1.0)` returns `false` because int `1` != float `1.0`.

**Fix:** Always cast to int when reading numeric values from JSON that will be used as dictionary keys:
```gdscript
var tier = int(item.get("tier", 0))  # Not just item.get("tier", 0)
if TIER_DATA.has(tier):  # Now works correctly
    ...
```

**Common locations:** Item tier lookups in `server/server.gd` and `shared/combat_manager.gd`

### 9. Serialization Key Mismatches
**Symptom:** SCRIPT ERROR accessing Dictionary key that should exist
**Cause:** `serialize_combat_state()` (or similar) saves data under a DIFFERENT key name than the code that reads it. Example: saved as `xp_reward` but read as `experience_reward`.

**Fix:** Always grep for the key name in ALL consumer functions before choosing the serialization key name. Use `.get("key", default)` instead of dot access (`dict.key`) for any Dictionary that may have been deserialized.

**Pattern:** When adding serialization/deserialization, verify key names match:
```gdscript
# SERIALIZATION - check what key consumers expect
monster_data["experience_reward"] = monster.get("experience_reward", 10)  # NOT "xp_reward"!

# DESERIALIZATION - use .get() with defaults for safety
var base_xp = monster.get("experience_reward", 10)  # NOT monster.experience_reward
```

### 10. Number Key Double-Trigger (Item Selection + Action Bar) — CRITICAL
**Symptom:** Pressing a number key (1-5) to select an item ALSO triggers an action bar button (e.g., opens settings)
**Cause:** While in item selection mode, the action bar resets `hotkey_N_pressed = false` for conflicting keys. When item selection exits the mode (e.g., discard sets `inventory_mode = false`), the action bar sees the still-held key as a NEW press on the next frame and fires.

**Fix:** `_consume_item_select_key(i)` does two things:
1. Appends keycode to `item_selection_consumed_this_frame` (same-frame protection)
2. Marks the corresponding action bar `hotkey_N_pressed = true` (cross-frame protection — key won't re-trigger until released)

**MANDATORY pattern for ALL number-key selection handlers:**
```gdscript
if not get_meta("mykey_%d_pressed" % i, false):
    set_meta("mykey_%d_pressed" % i, true)
    _consume_item_select_key(i)  # <-- ALWAYS ADD THIS
    do_the_actual_action(i)
```

**When to apply:** EVERY place in `_process()` that calls `is_item_select_key_pressed(i)` and triggers an action. No exceptions.

**Files:** `client/client.gd` — `_consume_item_select_key()` (~line 16960), `item_selection_consumed_this_frame` var (~line 724), checked in action bar loop (~line 2550+)

### 11. Action Bar Buttons Need BOTH Input Paths
**Symptom:** Clicking an action bar button does nothing, even though the hotkey works
**Cause:** Action bar buttons use TWO input paths that must BOTH be implemented:
1. **Keyboard:** Handled by `_input()` (for modes excluded from `should_process_action_bar` like `settings_mode`) or by `_process()` hotkey polling
2. **Click:** `_on_action_button_pressed()` → `trigger_action()` → `execute_local_action(action_data)` — requires a matching case in `execute_local_action()`

**Fix:** When adding a new action bar button with `action_type: "local"`, ALWAYS add a matching handler in `execute_local_action()`. Even if `_input()` handles the keyboard path, the click path goes through `execute_local_action()`.

**Modes affected:** Any mode in the `should_process_action_bar` exclusion list (`settings_mode`, `combat_item_mode`, `monster_select_mode`, `target_farm_mode`, `title_mode`) handles keyboard via `_input()` and clicks via `execute_local_action()`. Both must work.

### 12. Dual-Type Items (type vs item_type) — Consumables
**Symptom:** Item doesn't appear as usable, shows under wrong market category, inspect shows wrong effect
**Cause:** Some items have BOTH `type` (broad category) and `item_type` (specific subtype). Example: Escape Scroll has `type: "consumable"` AND `item_type: "escape_scroll"`. Code that only checks one field misses the other.

**All places that must handle BOTH fields:**
1. **`_is_consumable_type()`** — must check `item_type == "consumable"` as well as specific subtypes
2. **Inventory "Use" filter** — must accept `type == "consumable"` items, not just `is_consumable` flag
3. **`display_item_details()` / inspect** — must resolve `item.get("item_type", item_type)` to get the specific subtype for effect descriptions
4. **`_get_item_effect_description()`** — specific subtypes (e.g., `"escape_scroll"`) must be checked BEFORE generic catch-alls (e.g., `"scroll" in item_type`)
5. **Drop table generation** — treasure/chest drops must include `"is_consumable": true` if the item should be usable (crafted items get this automatically, drops may not)
6. **Market categorization** — `_is_consumable_type()` determines market category; items with `type: "consumable"` that aren't recognized end up under "Equipment"

**Pattern:** When an item has both `type` and `item_type`, always resolve to the more specific one:
```gdscript
var resolved_type = item.get("item_type", item.get("type", ""))
```

