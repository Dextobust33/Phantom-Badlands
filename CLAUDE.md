# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Phantasia Revival is a text-based multiplayer RPG built with Godot 4.5 and GDScript. It features a client-server architecture with turn-based combat, procedural world generation, and character progression across 9 class archetypes.

## Running the Project

Open the project in Godot 4.5 editor, then:
- **Run client:** Execute `client/client.tscn` as main scene
- **Run server:** Execute `server/server.tscn` for dedicated server

Export is configured for Windows Desktop via `export_presets.cfg`.

## Quick Launch (Command Line)

Godot executable location: `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`

**Launch server:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" server/server.tscn &
```

**Launch client (after server is running):**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" client/client.tscn &
```

Run server first, then client. Both commands run in background (`&`).

## Architecture

```
┌─────────────────────────────────────────────┐
│         CLIENT (client/)                    │
│  StreamPeerTCP connection, UI rendering,    │
│  input handling (chat, commands, movement)  │
└───────────────────┬─────────────────────────┘
                    │ JSON messages over TCP
┌───────────────────┴─────────────────────────┐
│         SERVER (server/)                    │
│  TCPServer listener, player sessions,       │
│  combat orchestration, world sync           │
└───────────────────┬─────────────────────────┘
                    │ Uses shared interfaces
┌───────────────────┴─────────────────────────┐
│         SHARED (shared/)                    │
│  Character, CombatManager, WorldSystem,     │
│  MonsterDatabase, Constants                 │
└─────────────────────────────────────────────┘
```

**Key Files:**
- `client/client.gd` - Client networking and UI (connects to localhost:9080)
- `server/server.gd` - Server main loop, peer management, message routing
- `shared/character.gd` - Character class with stats, inventory, combat data
- `shared/combat_manager.gd` - Turn-based combat engine
- `shared/world_system.gd` - Procedural terrain generation, coordinate system (-1000 to +1000)
- `shared/monster_database.gd` - 40 monster types across 5 difficulty tiers
- `shared/constants.gd` - Message types, class definitions, game constants

## Networking Protocol

- **Transport:** TCP on port 9080 (localhost for testing)
- **Format:** Newline-delimited JSON messages
- **Client→Server:** connect, login, create_character, move, chat, combat, heartbeat
- **Server→Client:** welcome, login_success/failed, character_created, location, chat, combat_start/update/end, error

## Game Systems

**Character Stats:** STR, CON, DEX, INT, WIS, CHA with derived HP and Mana
**Combat:** Turn-based with attack, defend, flee, special actions
**World:** Coordinate-based grid with 11 terrain types, special fixed locations (Sanctuary at 0,10, Throne at 0,0)
**Classes:** Fighter, Barbarian, Paladin, Wizard, Sorcerer, Sage, Thief, Ranger, Ninja

## Code Conventions

- GDScript follows Godot conventions: `class_name` for custom types, `@onready` for node references
- Connection polling must happen in `_process()` for TCP networking
- UI uses RichTextLabel with BBCode for colored text output
- Three-panel client layout: GameOutput, ChatOutput, MapDisplay

## Zone Difficulty Overhaul (COMPLETE)

**All phases implemented:**
- [x] Phase 1: Distance-based monster levels (0-1414 distance -> 1-10000 level)
- [x] Phase 2: Hot spot danger zones (clusters of 1-20 tiles, 50-150% level bonus)
- [x] Phase 3: Stat scaling rebalance (tiered 12%/5%/2%/0.5% per level)
- [x] Phase 4: New monster types (tiers 6-9, 16 new monsters)
- [x] Phase 5: XP/gold reward scaling formulas
- [x] Phase 6: Item system stubs (inventory, drop_tables.gd, combat hooks)

**Hotspot Visual Indicators:**
- Hotspots now appear as clusters (1-20 connected tiles)
- Display as `!` character in red/orange on the map
- Intensity-based colors (orange at edge, bright red at center)

**Action Bar Refactored:**
- [Space] = Primary action (Status in movement, Attack in combat)
- [Q][W][E][R] = Quick actions
- [1][2][3][4] = Additional actions (removed #5)

**Inventory System:**
- [Q] Inventory to open inventory view
- [Q] Use, [W] Equip, [E] Unequip, [R] Discard in inventory mode
- [Space] Back to return to movement mode
- Commands: `inventory`, `inv`, `i`

**Files Modified:**
- `shared/world_system.gd` - distance formula, clustered hotspot system with visual indicators
- `shared/monster_database.gd` - 16 new monsters (tiers 6-9), tiered stat scaling, drop fields
- `shared/character.gd` - inventory/equipped arrays, item helper functions
- `shared/combat_manager.gd` - item drop hooks on combat victory
- `shared/drop_tables.gd` - NEW file with drop table structure and roll functions
- `client/client.gd` - action bar refactor, inventory UI, hotkey changes
- `server/server.gd` - inventory handlers (use, equip, unequip, discard)

## Gem System & Merchant Enhancement (COMPLETE)

**Gem Currency:**
- Gems are a premium currency dropped by high-level monsters
- Only drops when monster level > player level by 5+
- Drop chance scales with level difference (2% at 5+, up to 50% at 100+)
- Gem quantity: max(1, lethality/1000 + level/100)
- Displayed in UI alongside gold (cyan color)

**Gem Drop Chance by Level Difference:**
- 5+ levels: 2%
- 10+ levels: 5%
- 15+ levels: 8%
- 20+ levels: 12%
- 30+ levels: 18%
- 50+ levels: 25%
- 75+ levels: 35%
- 100+ levels: 50%

**Merchant Enhancements:**
- **Buy Items [R]**: Merchants now sell equipment scaled to player level
  - Standard tier: player level -5 to +5
  - Premium tier: player level +5 to +20
  - Legendary tier: player level +20 to +50
  - Prices at 2.5x item base value
- **Sell Gems [1]**: Convert gems to gold at 1000g per gem
- **Multi-Upgrade**: Upgrade handler supports `count` parameter for bulk upgrades
- **Gem Payment**: Can pay for upgrades with gems (1 gem = 1000g equivalent)

**Merchant Action Bar:**
- [Space] Leave
- [Q] Sell items
- [W] Upgrade equipment
- [E] Gamble
- [R] Buy items (shows count)
- [1] Sell gems (shows count)

**Files Modified:**
- `shared/character.gd` - Added `gems` field, persistence in to_dict/from_dict
- `shared/combat_manager.gd` - Added roll_gem_drops() function, integrated with victory
- `client/client.tscn` - Added CurrencyDisplay panel (GoldLabel, GemLabel)
- `client/client.gd` - Currency display, shop buy UI, gem selling UI
- `server/server.gd` - Shop inventory generation, buy/sell_gems handlers, multi-upgrade
