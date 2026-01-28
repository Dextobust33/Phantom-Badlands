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
