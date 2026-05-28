# CLAUDE.md

Guidance for Claude Code when working with this repository.

## Quick Start

**Detailed diagrams in `/docs/`:**
- `QUICK_REFERENCE.md` — Condensed overview, file map, common tasks
- `SYSTEM_OVERVIEW.md` — Dense AI context reference (mode flags, message types, conventions)
- `CODE_GUIDE.md` — Walkthrough for modifying the game (templates, patterns, debugging, ASCII art)
- `architecture.md` — System architecture, data flow, class hierarchy
- `action-bar-states.md` — Complete action bar state machine (CRITICAL for UI work)
- `combat-flow.md` — Combat lifecycle, damage formulas, monster abilities
- `networking-protocol.md` — All message types, sequence diagrams
- `quest-system.md` — Quest flow, trading posts
- `game-systems.md` — Feature documentation: companion, market, party, sanctuary, dungeon, gathering, monster HP knowledge, player posts, etc.

## Project Overview

Phantom Badlands is a text-based multiplayer RPG built with **Godot 4.6** and GDScript. Client-server architecture with turn-based combat, procedural world generation, and 9 class archetypes.

**Godot Version:** 4.6.stable.steam (godot.windows.opt.tools.64.exe)
**Important:** Some Godot 4.x API methods differ from 4.3/4.4 docs. Example: RichTextLabel uses `pop()` not `pop_meta()`.

## UI Design Principle: Action Bar First

**IMPORTANT: Always prefer Action Bar over chat commands when implementing new features.**

- New features should be accessible via the Action Bar, not `/commands`
- The Action Bar has 10 slots (Space, Q, W, E, R, 1-5) with contextual buttons
- Slot 4 (R key) is the "contextual location action" — shows different buttons based on location:
  - At water (~): Fish
  - At ore deposit (mountains): Mine
  - At dense forest: Chop
  - At dungeon entrance (D): Dungeon
  - At Infernal Forge: Forge
  - Otherwise: Quests
- Chat commands can exist as fallbacks but shouldn't be the primary interface
- See `docs/action-bar-states.md` for the full state machine

## UI Buttons over Keyboard Shortcuts

**IMPORTANT: Prefer visible/clickable UI controls over keyboard shortcuts when adding a new entry point to a feature.**

- New entry points for features (open this panel, enter this mode, toggle this option) should be a visible button somewhere accessible, NOT a global hotkey.
- Keyboard shortcuts can exist as a power-user supplement to an existing button, never as the sole way in.
- A button is discoverable; a hotkey isn't.
- If the entry point needs to be available from many surfaces (combat, dungeon, overworld, settings), put a small persistent button somewhere unobtrusive (corner anchor, right-panel row, etc) rather than reaching for a global hotkey.
- This generalizes the existing **Action Bar First** + **UI control over chat controls** principles to keyboard shortcuts as well.

## Admin Commands: /admin UI, Not Chat

**IMPORTANT: All NEW admin/dev/testing tools go through the visual `/admin` panel — not new `/command` chat shorthands.**

- Visual panel: `client/admin_panel.gd`. Pages are `root` / `test_b2` / `items` / `combat` / `misc` / `world` (see `_current_page`).
- Pattern: each button emits `action_triggered(action_id)` → client.gd's `_on_admin_panel_action()` dispatches a `gm_*` server message → `handle_gm_*` server handler gated by `_is_admin(peer_id)`.
- Do NOT extend the `command_keywords` array or `process_command()` match statement with new top-level admin commands. The `/gmhelp` chat list and existing `/setlevel`, `/tp`, `/giveconsumable`, etc. are legacy.
- Existing chat admin commands stay as fallbacks — don't migrate in a cleanup pass without explicit ask (muscle memory).
- Same principle generalizes: **UI control over chat controls** for all new features (player or admin). Chat is a legacy fallback surface, never the primary interface for new mechanics.

## Player-Visible Output Rule

**CRITICAL: All feature results MUST be visible to the player.**

Server messages (`character_update`, `location`, `text`, `combat_update`, `inventory_update`) frequently trigger UI refreshes that call `display_xxx()` and wipe `game_output`, clearing any result message the player was trying to read. Every mode is affected (inventory, merchant, trading post, crafting, ability, settings, etc.). The classic symptom: player sees the result for a split second, then it's gone.

**Mandatory checklist when adding an action whose result the player needs to read:**

1. **Set a pending/state flag** — `pending_inventory_action = "my_new_action"` (or `pending_merchant_action`, `pending_trading_post_action`, `pending_ability_action`, `rebinding_action`, etc. — match the mode).
2. **Add action bar state** in `update_action_bar()` for the new view (typically a Back button + whatever else).
3. **Add bypass in message handlers** — find the `if inventory_mode:` (or equivalent) branch in `"character_update"` handler and add `elif pending_xxx_action == "my_new_action": pass` so the refresh doesn't redisplay.
4. **Add handler to exit** — set `pending_xxx_action = ""`, call `display_xxx()`, `update_action_bar()`.
5. **Add to item-selection exclusion list** (~line 1866 in client.gd) — otherwise number keys fire as item selections AND action bar presses simultaneously.

**Existing state flags worth knowing:** `awaiting_item_use_result`, `awaiting_salvage_result`, `viewing_materials`, `sort_select`, `salvage_select`, `equip_confirm`, `unequip_item`.

**To verify your fix:** trigger the action, wait 1–2 seconds for server messages to arrive, confirm output is still visible.

**Features are useless if players can't see what happened.**

## Running the Project

**Godot executable:** `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`

**IMPORTANT — open game/test windows on the secondary monitor.** Always pass `--screen 1` when launching a Godot window so it opens on the user's secondary monitor (index 1), not the primary (index 0). The editor + project manager are already pinned to screen 1 via editor settings; `--screen 1` does the same for CLI-launched game windows. (`--headless` exports take no `--screen`.)

**Preferred Launch (with output capture):**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --screen 1 server/server.tscn 2>&1 &
sleep 3
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --screen 1 client/client.tscn 2>&1
```
Use `run_in_background: true` and 600000ms timeout. Read output file to see console messages.

**Simple Launch:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --screen 1 server/server.tscn &
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --screen 1 client/client.tscn &
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
| `tools/combat_simulator/` | Combat simulation tool — see `tools/combat_simulator/README.md` |

## Releases & Distribution

**GitHub:** https://github.com/Dextobust33/Phantom-Badlands
**Website:** https://phantombadlands.com (GitHub Pages from `docs/`)
**Game Server:** Hetzner Cloud CPX11 at `5.78.217.135:9080` (Hillsboro, OR — migrated from Oracle 2026-05-12 for ~16× compute, $6.99/mo)

### Creating a release

Every release ships **FOUR assets under ONE `vX.Y.Z` tag**: Windows client + Windows launcher + Linux client + Linux launcher. NEVER ship a Windows-only release — the website serves both platforms, and a missing launcher ZIP breaks new-player downloads.

1. **Bump VERSION.txt** — never reuse a version number. The launcher compares local VERSION.txt against the GitHub release `tag_name`; matching versions skip the update.
2. **Commit and push** the version bump.
3. **Build Windows pair** — export `Phantom-Badlands` (client) + `Windows Desktop` (launcher) via Godot CLI, then `Compress-Archive` into `releases/phantom-badlands-client-vX.Y.Z.zip` and `releases/phantom-badlands-launcher.zip`. Client ZIP includes `PhantomBadlandsClient.exe`, `.pck`, `libgdsqlite.windows.template_debug.x86_64.dll`, VERSION.txt, CREDITS.md.
4. **Build Linux pair** — `bash build_linux_release.sh` produces both Linux ZIPs (reads VERSION.txt automatically).
5. **Send 1-minute in-game warning** via the production server's pending-shutdown countdown — same UI as "detecting remains". Players need time to finish combat / trades / dungeons.
6. **`scp` the new server binary as `.new` first** so it's staged before the countdown elapses; swap into place during the window. If you miss the window, swap + `systemctl restart` again (players already disconnected).
7. **Create the GitHub release** with all four ZIPs attached in one `gh release create` call. Asset naming: Linux zips carry `linux`, Windows zips don't — that's how the launcher disambiguates platforms.

**Launcher download targets** (must always exist at these URLs):
- `releases/latest/download/phantom-badlands-launcher.zip` (Windows)
- `releases/latest/download/phantom-badlands-launcher-linux.zip` (Linux)

**Cross-platform launcher details:** `launcher/launcher.gd` detects OS — `.x86_64` exe name on Linux, picks the `*-linux-*` client zip, `chmod +x`'s the extracted client (ZIP drops the exec bit). Linux client ships as a single binary (PCK embedded); sqlite `.so` sits flat next to the binary.

### Deploying server updates

```bash
bash deploy_server.sh   # exports, uploads, restarts
```

Manual fallback (when the script can't be used):

```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --export-release "Phantom-Badlands-Server-Linux" "builds/server/PhantomBadlandsServer.x86_64"
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
scp -i "$SSH_KEY" builds/server/PhantomBadlandsServer.x86_64 ubuntu@5.78.217.135:~/phantom-badlands/
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "chmod +x ~/phantom-badlands/PhantomBadlandsServer.x86_64 && sudo systemctl restart phantom-badlands"
```

### Server management

```bash
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "sudo systemctl status phantom-badlands --no-pager"
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "sudo journalctl -u phantom-badlands -n 50 --no-pager"
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "sudo systemctl restart phantom-badlands"
ssh -i "$SSH_KEY" ubuntu@5.78.217.135 "sudo systemctl stop phantom-badlands"
```

## Maintenance Reminders

- **Update Help Page:** After mechanics change, update `client/client.gd` `show_help()` (~line 21639)
- **Update Changelog:** When creating a release, update `display_changelog()` in `client/client.gd` (~line 19938) with new version's changes. Keep 5 most recent versions visible, remove oldest when adding new.
- **Ship all FOUR release assets** (see Releases section).
- **Deploy server:** After server-side changes, run `bash deploy_server.sh` to update the cloud server.
- **After significant changes:** Remind user to create a release for players.

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
**Fix:** Commands must be registered in TWO places in `client/client.gd`: the `command_keywords` whitelist (~line 15835) that routes to `process_command()`, AND the `process_command()` match statement (~line 16505) that handles it. For server-side commands, also add to `server/server.gd`'s `handle_message()` match (~line 755) plus the handler function.

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
var tier = int(item.get("tier", 0))
if TIER_DATA.has(tier):
    ...
```

**Common locations:** Item tier lookups in `server/server.gd` and `shared/combat_manager.gd`

### 9. Serialization Key Mismatches
**Symptom:** SCRIPT ERROR accessing a Dictionary key that should exist
**Cause:** `serialize_combat_state()` (or similar) saves data under a DIFFERENT key name than the code that reads it. Example: saved as `xp_reward` but read as `experience_reward`.

**Fix:** Grep for the key name in ALL consumer functions before choosing the serialization key. Use `.get("key", default)` instead of dot access on any Dictionary that may have been deserialized — both sides of the pipe must agree on the name.

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

**All places that must handle BOTH fields:** `_is_consumable_type()` (check `item_type == "consumable"` plus specific subtypes), inventory "Use" filter (accept `type == "consumable"`, not just `is_consumable` flag), `display_item_details()` / inspect (resolve to specific subtype), `_get_item_effect_description()` (specific subtypes checked BEFORE generic catch-alls), drop table generation (treasure/chest drops must include `"is_consumable": true`), market categorization.

**Pattern:** When an item has both fields, always resolve to the more specific one:
```gdscript
var resolved_type = item.get("item_type", item.get("type", ""))
```
