# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Phantasia Revival is a text-based multiplayer RPG built with Godot 4.5 and GDScript. It features a client-server architecture with turn-based combat, procedural world generation, and character progression across 9 class archetypes.

## Running the Project

Open the project in Godot 4.5 editor, then:
- **Run client:** Execute `client/client.tscn` as main scene
- **Run server:** Execute `server/server.tscn` for dedicated server
- **Combined testing:** Execute `test_combined.tscn` to run server and client together in one scene for development testing

Export is configured for Windows Desktop via `export_presets.cfg`.

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
