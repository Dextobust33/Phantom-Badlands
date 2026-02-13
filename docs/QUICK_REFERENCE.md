# Phantom Badlands - Quick Reference

**Use this as context primer for new Claude sessions.**

## Project Summary

Text-based multiplayer RPG in Godot 4.5/GDScript. Client-server architecture over TCP:9080.

## File Map (by size/importance)

| File | ~Lines | What It Does |
|------|--------|--------------|
| `client/client.gd` | 8000 | UI, networking, action bar, all client logic |
| `server/server.gd` | 4000 | Message routing, persistence, game logic |
| `shared/combat_manager.gd` | 3500 | Turn-based combat, damage calc, abilities |
| `shared/monster_database.gd` | 1400 | 40+ monsters across 9 tiers |
| `client/monster_art.gd` | 1200 | ASCII art for combat |
| `shared/world_system.gd` | 1000 | Terrain, hotspots, coordinates |
| `shared/character.gd` | 1000 | Player stats, inventory, equipment |
| `shared/quest_database.gd` | 900 | Quest definitions |
| `shared/drop_tables.gd` | 600 | Item generation |

## Running the Game

```bash
# Server (run first)
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" server/server.tscn &

# Client (run second)
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" client/client.tscn &
```

## Critical Patterns

### Action Bar State Machine

The action bar (`update_action_bar()` at line ~2550 in client.gd) checks states in this priority order:

1. `settings_mode`
2. `pending_trade_request`
3. `pending_summon` (summon consent)
4. `in_trade`
5. `wish_selection_mode`
6. `monster_select_mode`
7. `target_farm_mode`
8. `ability_mode`
9. `title_stat_selection_mode` (Bless stat choice)
10. `title_mode`
11. `combat_item_mode`
12. `in_combat`
13. `flock_pending`
14. `pending_continue`
15. `at_merchant` + `pending_merchant_action`
16. `inventory_mode` + `pending_inventory_action`
17. `at_trading_post`
18. `has_character` (normal mode)
19. No character

**RULE:** After changing ANY state variable, call `update_action_bar()`.

### Account Limits

- **Max characters:** 6 per account
- **Permadeath:** Characters deleted on death

### Classes & Paths

| Path | Resource | Classes |
|------|----------|---------|
| Warrior | Stamina | Fighter, Barbarian, Paladin |
| Mage | Mana | Wizard, Sorcerer, Sage |
| Trickster | Energy | Thief, Ranger, Ninja |

**Universal Resource Bonuses:** Equipment resource stats convert to your class's primary resource (with scaling: mana affixes are 2× larger, so mana→stamina/energy is 0.5×).

### Key Locations

- **Spawn:** Haven (0, 10)
- **Throne:** (0, 0) - Crossroads
- **World bounds:** -1000 to +1000

### Combat Flow

```
Encounter → Initiative Check → [Monster First?] → Player Turn → Monster Turn → Loop
                                    ↓
                              Check Victory/Defeat
```

**Initiative:** If monster speed > player DEX, up to 40% chance monster strikes first.

### Message Protocol

JSON over TCP, newline-delimited. Key types:
- `move`, `combat_action`, `chat` (client→server)
- `location_update`, `combat_start/update/end`, `character_update` (server→client)

## High-Tier Drops (Tier 6+)

| Category | Items | Effect |
|----------|-------|--------|
| **Scrolls** | Time Stop, Monster Bane, Resurrect | Combat buffs |
| **Mystery** | Box, Cursed Coin | Gambling items |
| **Stat Tomes** | Tome of STR/INT/etc. | +1 permanent stat |
| **Skill Tomes** | Various | -10% cost or +15% dmg |
| **Proc Gear** | Vampire, Thunder, Reflect, Slayer | Equipment effects |
| **Trophies** | Dragon Scale, etc. | 5% from bosses (T8+) |
| **Soul Gems** | Wolf, Phoenix, Shadow, etc. | Summon companions |

Key files: `drop_tables.gd` (definitions), `character.gd` (storage), `combat_manager.gd` (effects)

## Common Tasks

### Adding a Monster Ability
1. Add constant in `combat_manager.gd` (~line 46-92)
2. Add to monster definition in `monster_database.gd`
3. Process in `process_monster_turn()` or `process_player_turn()`
4. Handle in client if visual/UI effect needed

### Adding an Action Bar Button
1. Find correct state block in `update_action_bar()`
2. Add to `current_actions` array (10 slots max)
3. Add handler in `execute_local_action()` or appropriate handler
4. If new state, add check to the priority chain

### Adding a New Inventory Action
1. Add button in `inventory_mode` block of `update_action_bar()`
2. Set `pending_inventory_action` to new value
3. Add exclusion in item selection code (~line 1451) if action uses buttons not numbers
4. Handle in `execute_local_action()`

### Adding ASCII Art
Location: `client/monster_art.gd` in `get_art_map()`

- **Wide art (>50 chars):** Copy exactly, preserve whitespace
- **Small art (≤50 chars):** Just the art, auto-centered with border

### Title System Commands

| Command | Description |
|---------|-------------|
| `/donate <amount>` | Donate gold at Shrine of Wealth (pilgrimage) |
| `/crucible` | Start the Crucible gauntlet (pilgrimage final) |

**Access:** "High Seat" action bar button at (0,0) trading post, or "Title" button if title holder

## Theme Colors

| Element | Color |
|---------|-------|
| Background | `#000000` |
| Default text | `#33FF33` |
| Player damage | `#FFFF00` |
| Monster damage | `#FF4444` |
| Gold | `#FFD700` |
| Gems | `#00FFFF` |
| Success | `#00FF00` |
| Error | `#FF0000` |
| XP | `#FF00FF` |

## Diagrams

See `/docs/` for detailed mermaid diagrams:
- `architecture.md` - System overview, data flow
- `action-bar-states.md` - Full state machine
- `combat-flow.md` - Combat system
- `networking-protocol.md` - Message types
- `quest-system.md` - Quest flow

## New Feature Systems (v0.9.11+)

### Dungeons
- Spawn at random world locations (higher tier = further from origin)
- Enter via Action Bar "Dungeon" button (R key) at entrance
- Grid-based exploration: Q=N, W=S, E=W, R=E
- Files: `dungeon_database.gd` (definitions), `character.gd` (state), `server.gd` (handlers)

### Crafting
- Available at Trading Posts via Action Bar
- Three skills: Blacksmithing, Alchemy, Enchanting
- Quality system: Failed → Poor → Standard → Fine → Masterwork
- Files: `crafting_database.gd` (recipes), `character.gd` (skills), `server.gd` (handlers)

### Fishing
- Available at water tiles via Action Bar "Fish" button (R key)
- Reaction minigame: wait for bite, press correct button quickly
- Files: `world_system.gd` (water detection), `server.gd` (handlers), `client.gd` (UI)

### Companions
- Eggs drop from dungeons, fishing, monster kills
- Hatch by walking (steps decrement counter)
- Fight alongside player in combat
- Files: `drop_tables.gd` (eggs), `character.gd` (companion data)

**See `docs/ROADMAP.md` for full implementation details.**

## Gotchas

1. **Key conflicts:** Action bar slots 5-9 share keys with item selection (1-5). Exclude new modes from item selection at ~line 1451.

2. **State leaks:** Always reset page variables (`sort_menu_page`, `inventory_page`, etc.) when exiting menus.

3. **Backward compat:** Server may have old clients. Keep message format stable.

4. **SQLite:** Persistence uses `addons/godot-sqlite`. Character saves on logout and periodic auto-save.

5. **Action Bar First:** New features should use Action Bar, not chat commands. Slot 4 (R key) is contextual by location.

5. **Permadeath:** Characters are deleted on death. No recovery.
