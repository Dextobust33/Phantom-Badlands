# Phantom Badlands — Developer Guide

A comprehensive guide to understanding and modifying the Phantom Badlands codebase. Written for developers with programming experience who want to learn Godot and this project from the ground up.

---

## Recommended Reading Order

If you're new to the project, read these in order. Each builds on the previous:

| # | Document | Lines | What You'll Learn |
|---|----------|-------|-------------------|
| 1 | [GDScript Fundamentals](01_gdscript_fundamentals.md) | ~1,900 | The GDScript language: variables, scope, functions, classes, collections, patterns |
| 2 | [Godot Engine Basics](02_godot_engine_basics.md) | ~1,400 | Scenes, nodes, lifecycle (_ready, _process, _input), signals, RichTextLabel |
| 3 | [Project Structure](03_project_structure.md) | ~770 | File map, folder layout, what each file does, which file to edit for common tasks |
| 4 | [Networking](04_networking.md) | ~1,160 | Client-server TCP, JSON messages, send/receive patterns, the full message lifecycle |
| 5 | [Client Architecture](05_client_architecture.md) | ~1,430 | client.gd deep dive: state machine, action bar, input handling, display functions |
| 6 | [Server Architecture](06_server_architecture.md) | ~1,870 | server.gd deep dive: message routing, player management, persistence, security |
| 7 | [Combat System](07_combat_system.md) | ~1,390 | Combat flow, damage formulas, abilities, classes, party combat, balance tuning |
| 8 | [World and Map](08_world_and_map.md) | ~1,150 | Procedural world, terrain, chunks, dungeons, NPC posts, tile detection |
| 9 | [Game Systems](09_game_systems.md) | ~1,710 | All game features: inventory, quests, companions, gathering, crafting, market, parties |
| 10 | [How-To Guides](10_how_to_guides.md) | ~780 | Step-by-step recipes: add monsters, items, commands, UI screens, and more |

**Total: ~13,500 lines of documentation**

---

## Quick Links by Task

### "I want to understand..."
- How GDScript works → [01_gdscript_fundamentals.md](01_gdscript_fundamentals.md)
- How Godot's scene tree and lifecycle work → [02_godot_engine_basics.md](02_godot_engine_basics.md)
- What each file in the project does → [03_project_structure.md](03_project_structure.md)
- How client and server communicate → [04_networking.md](04_networking.md)
- How the client UI and state machine work → [05_client_architecture.md](05_client_architecture.md)
- How the server processes messages → [06_server_architecture.md](06_server_architecture.md)
- How combat works (damage, abilities, classes) → [07_combat_system.md](07_combat_system.md)
- How the procedural world generates → [08_world_and_map.md](08_world_and_map.md)
- How a specific game system works → [09_game_systems.md](09_game_systems.md)

### "I want to add/change..."
- A new monster → [How-To #1](10_how_to_guides.md#1-add-a-new-monster)
- Monster ASCII art → [How-To #2](10_how_to_guides.md#2-add-monster-ascii-art)
- A new item → [How-To #3](10_how_to_guides.md#3-add-a-new-item-to-loot-tables)
- A chat command → [How-To #4](10_how_to_guides.md#4-add-a-new-chat-command)
- An action bar button → [How-To #5](10_how_to_guides.md#5-add-a-new-action-bar-button)
- A new UI screen → [How-To #6](10_how_to_guides.md#6-add-a-new-ui-screenmode)
- A new network message → [How-To #7](10_how_to_guides.md#7-add-a-new-server-message-type)
- A dungeon → [How-To #9](10_how_to_guides.md#9-add-a-new-dungeon)
- A crafting recipe → [How-To #10](10_how_to_guides.md#10-add-a-new-crafting-recipe)
- Combat balance → [How-To #11](10_how_to_guides.md#11-modify-combat-balance)
- A consumable item → [How-To #14](10_how_to_guides.md#14-add-a-new-consumable-item)
- Create a release → [How-To #15](10_how_to_guides.md#15-create-a-release)

### "Something is broken..."
- Output disappears after 1-2 seconds → [Client Architecture: The "Output Disappears" Problem](05_client_architecture.md#9-the-output-disappears-problem--most-important-section)
- Number keys trigger two things at once → [Client Architecture: Number Key Conflict](05_client_architecture.md#10-the-number-key-conflict)
- Button click does nothing (keyboard works) → [How-To: Action Bar Both Paths](10_how_to_guides.md#5-add-a-new-action-bar-button)
- Command goes to chat instead of executing → [How-To: Command Whitelist](10_how_to_guides.md#4-add-a-new-chat-command)
- Dictionary key lookup fails → [GDScript: JSON Float vs Int Keys](01_gdscript_fundamentals.md#4-collections-arrays-and-dictionaries)
- Common Godot errors → [Godot Basics: Common Errors](02_godot_engine_basics.md#14-common-godot-errors-and-what-they-mean)

---

## Key Files Quick Reference

| File | Lines | Purpose |
|------|-------|---------|
| `client/client.gd` | ~27,000 | All client code: UI, input, networking, display |
| `server/server.gd` | ~21,500 | All server code: game logic, message routing |
| `shared/character.gd` | ~3,650 | Player stats, inventory, equipment, companions |
| `shared/combat_manager.gd` | ~6,100 | Turn-based combat engine, damage formulas |
| `shared/world_system.gd` | ~2,400 | Procedural terrain, tile detection, pathfinding |
| `shared/drop_tables.gd` | ~4,500 | Item generation, loot tables, gathering catches |
| `shared/monster_database.gd` | ~1,700 | Monster definitions (50+ types, 9 tiers) |
| `shared/crafting_database.gd` | ~3,400 | Crafting recipes, materials, quality system |
| `shared/dungeon_database.gd` | ~2,000 | Dungeon types, floors, bosses |
| `server/persistence_manager.gd` | ~1,700 | Database layer, save/load, accounts |
| `server/balance_config.json` | ~50 | Combat tuning numbers |
| `client/monster_art.gd` | ~5,600 | ASCII art for 50+ monsters |

---

## Critical Rules (The Short Version)

These are the rules that will save you the most debugging time:

1. **Always use `.get("key", default)`** for dictionaries from JSON/network — never dot access
2. **Cast JSON numbers to int** before using as dictionary keys: `int(item.get("tier", 0))`
3. **Call `update_action_bar()`** after every state change
4. **Implement BOTH input paths** for action bar buttons (keyboard AND mouse click)
5. **Call `_consume_item_select_key(i)`** in every number key handler
6. **Add pending flag + bypass** for any action that shows output the player needs to read
7. **Server validates everything** — never trust client data
8. **Add new commands to `command_keywords`** array, not just `process_command()`

---

## Project Info

- **Game:** Phantom Badlands — text-based multiplayer RPG
- **Engine:** Godot 4.6.stable.steam
- **Language:** GDScript
- **Architecture:** Client-server over raw TCP, JSON messages
- **Version:** v0.9.144 (as of February 2026)
- **GitHub:** https://github.com/Dextobust33/Phantom-Badlands
