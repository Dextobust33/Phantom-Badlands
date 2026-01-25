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

## Adding ASCII Art to Combat

**Location:** `shared/combat_manager.gd` in the `get_monster_ascii_art()` function (~line 1500)

**Format:** ASCII art is stored as an array of strings in the `art_map` dictionary:
```gdscript
"Monster Name": ["[color=#HEXCOLOR]",
"line 1 of art",
"line 2 of art",
"line 3 of art","[/color]"],
```

**CRITICAL - Two Art Size Categories:**

The display system handles art differently based on width:

1. **Wide Art (>50 chars)** - Pre-formatted, displayed AS-IS
   - Used for detailed art like the Goblin (75 chars wide)
   - Leading/trailing whitespace is PRESERVED
   - No border is added, no centering applied
   - Each line must include its own spacing for alignment
   - Copy lines EXACTLY from source file

2. **Small Art (≤50 chars)** - Auto-centered with border
   - Used for simple art like Giant Rat, Skeleton
   - Whitespace is stripped and art is centered
   - A decorative border is added around the art
   - 25-space left padding applied automatically

**Adding Wide Art (like Goblin):**
- Read the source file with the Read tool
- Copy each line EXACTLY as-is, preserving ALL whitespace
- Lines should be ~75 chars wide with embedded spacing
- Do NOT strip or trim any whitespace
- The art relies on leading spaces for proper alignment

**Adding Small Art:**
- Just include the art characters, no padding needed
- The system will auto-center and add borders
- Keep lines under 50 characters wide

**ASCII Art Source Files:** `C:\Users\Dexto\Desktop\Phantasia_Project\ASCII\`

**Display Constraints:**
- Wide art max: 75 characters (no border added)
- Small art max: 50 characters (border adds ~4 chars)
- Height: Unlimited (scrolls vertically)
- Font: Consolas 14pt monospace

**Color Suggestions by Monster Type:**
- Green `#00FF00` - Goblins, nature creatures
- Brown `#8B4513` - Rats, animals
- Gray `#808080` or `#FFFFFF` - Undead, golems
- Red `#FF0000` - Demons, fire creatures
- Blue `#0070DD` - Water/ice creatures
- Purple `#A335EE` - Magical beings

## Releases & Distribution

**GitHub Repository:** https://github.com/Dextobust33/Phantasia-Revival

The game uses an auto-updating launcher. When code changes are committed and ready for players, create a new release:

**Creating a Release:**
```bash
# 1. Update version number
echo "0.3" > VERSION.txt

# 2. Export client via command line (preset name is "Phantasia-Revival")
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" --export-release "Phantasia-Revival" "builds/PhantasiaClient.exe"

# 3. Create release ZIP (PowerShell)
powershell -Command "Compress-Archive -Path 'builds/PhantasiaClient.exe', 'builds/PhantasiaClient.pck', 'builds/libgdsqlite.windows.template_debug.x86_64.dll', 'VERSION.txt' -DestinationPath 'releases/phantasia-client-v0.3.zip' -Force"

# 4. Upload to GitHub (requires gh CLI)
"/c/Program Files/GitHub CLI/gh.exe" release create v0.3 releases/phantasia-client-v0.3.zip --title "v0.3" --notes "Description of changes"

# 5. Push code changes
git push
```

**Important:** After significant changes, remind user to create a new release so players get updates!

**Launcher:** `builds/PhantasiaLauncher.exe` - Share with friends (only needed once)
**Client:** Auto-downloaded by launcher from GitHub releases

## Maintenance Tasks

**Update Help Page After Changes:**
When game mechanics, formulas, or features change, update the in-game help:
- **Location:** `client/client.gd` in `show_help()` function (~line 5024)
- **Sections to keep current:**
  - Combat formulas (Outsmart, damage, flee chance)
  - Trading Posts and their locations
  - Quest system info
  - Gambling mechanics
  - Class abilities and resource costs
  - Race passives
- Always verify help text matches actual game behavior before releases

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

## Monster Ability & Class Affinity System (COMPLETE)

**Class Affinity System:**
Monsters have a class affinity that determines which player class is strong/weak against them:
- **Neutral (White)** - No advantage/disadvantage. Majority of monsters (~60%)
- **Physical (Yellow)** - Weak to Warriors (+50% damage), resistant to Mages (-25% damage)
- **Magical (Blue)** - Weak to Mages (+50% damage), resistant to Warriors (-25% damage)
- **Cunning (Green)** - Weak to Tricksters (+50% damage), resistant to other paths (-25% damage)

Monster names are color-coded in combat based on affinity. The encounter message shows which class has advantage.

**Monster Unique Abilities:**
Each monster can have one or more special abilities:

| Ability | Effect |
|---------|--------|
| `glass_cannon` | 3x damage but 50% HP |
| `multi_strike` | Attacks 2-3 times per turn |
| `poison` | 40% chance to poison player (-X HP/round) |
| `mana_drain` | Steals player mana on hit |
| `stamina_drain` | Drains stamina on hit |
| `energy_drain` | Drains energy on hit |
| `regeneration` | Heals 10% HP per turn |
| `damage_reflect` | Reflects 25% of damage taken |
| `ethereal` | 50% chance to dodge player attacks |
| `armored` | +50% defense |
| `summoner` | 20% chance to call reinforcements (forced follow-up fight) |
| `pack_leader` | +25% flock chance, stronger pack encounters |
| `gold_hoarder` | Drops 3x gold |
| `gem_bearer` | Always drops gems (2x normal amount) |
| `curse` | 30% chance to reduce player defense by 25% for combat |
| `disarm` | 25% chance to reduce player damage by 30% for 3 rounds |
| `unpredictable` | Damage varies wildly (0.5x to 2.5x) |
| `wish_granter` | Grants a random powerful buff (10 battles) on death |
| `death_curse` | Deals 25% of its max HP as damage when killed |
| `berserker` | +50% damage when below 50% HP |
| `coward` | Flees at 20% HP (no loot) |
| `life_steal` | Heals for 50% of damage dealt |
| `enrage` | +10% damage per round (stacking) |
| `ambusher` | First attack always crits (2x damage) |
| `easy_prey` | Low stats, 50% reduced rewards |
| `thorns` | Reflects 25% melee damage back to attacker |

**Custom Death Messages:**
Many monsters have unique death messages that display when defeated, adding flavor to combat.

**Notable Monster Highlights:**
- **Titan** (Tier 5) - Wish granter + glass cannon + gem bearer
- **Phoenix** (Tier 6) - Death curse + gem bearer + wish granter
- **Hydra** (Tier 6) - Regeneration + multi-strike + enrage
- **Primordial Dragon** (Tier 7) - Multi-strike + berserker + armored + gem bearer + wish granter
- **Entropy** (Tier 9) - Armored + regeneration + death curse + curse + gem bearer + wish granter

**Files Modified:**
- `shared/monster_database.gd` - Added ClassAffinity enum, ability constants, monster definitions with abilities/affinity/death_message
- `shared/combat_manager.gd` - Class advantage damage multipliers, monster ability processing, death message display
- `client/client.gd` - Monster name color coding in HP bar based on affinity
- `server/server.gd` - Summoner follow-up fights, monster fled handling

## Quest System & Trading Posts (COMPLETE)

**Trading Posts:**
10 safe zone hubs spread across the world providing quest givers, shops, and services:

| Name | Coordinates | Size | Quest Focus |
|------|-------------|------|-------------|
| Haven | (0, 10) | 5x5 | Beginner quests (spawn point) |
| Crossroads | (0, 0) | 3x3 | Hotzone quests, dailies |
| Frostgate | (0, -100) | 3x3 | Boss hunts, exploration |
| Eastwatch | (150, 0) | 3x3 | Mid-level kill quests |
| Westhold | (-150, 0) | 3x3 | Survival quests |
| Southport | (0, -150) | 3x3 | Collection quests |
| Shadowmere | (300, 300) | 5x5 | High-level challenges |
| Inferno Outpost | (-350, 0) | 3x3 | Near Fire Mountain |
| Void's Edge | (350, 0) | 3x3 | Near Dark Circle |
| Frozen Reach | (0, -400) | 3x3 | Extreme cold zone |

**Trading Post Services:**
- Shop (50% discount on recharge)
- Quest givers with location-specific quests
- Safe zone (no monster encounters)
- Map symbols: `P` (center), `+`, `-`, `|` (walls)

**Quest Types:**
1. **KILL_ANY** - Kill X monsters of any type
2. **KILL_LEVEL** - Kill a monster of level X or higher
3. **HOTZONE_KILL** - Kill X monsters in a hotzone within Y distance (1.5x-2.5x reward multiplier)
4. **EXPLORATION** - Visit specific Trading Posts
5. **BOSS_HUNT** - Defeat a monster of level X or higher

**Quest Tracking:**
- `character.active_quests` - Array of active quest progress
- `character.completed_quests` - Array of completed quest IDs
- `character.daily_quest_cooldowns` - Dictionary of daily quest reset times
- `Character.MAX_ACTIVE_QUESTS = 5`

**Quest Progress Flow:**
1. Player accepts quest at Trading Post
2. Server tracks progress via `quest_mgr.check_kill_progress()` or `check_exploration_progress()`
3. Progress updates sent to client as `quest_progress` messages
4. Quest complete sound plays when objectives met
5. Player returns to quest giver Trading Post to turn in

**Key Files:**
- `shared/quest_database.gd` - Quest definitions, QuestType enum
- `shared/quest_manager.gd` - Progress tracking, reward calculation
- `shared/trading_post_database.gd` - Trading Post definitions, tile checks

**Variable Cost Ability Popup:**
For abilities with variable resource costs (like Bolt), a popup window prompts for input:
- Created dynamically in `_create_ability_popup()`
- Shows ability name, description, current resource
- Input field for amount with validation
- Confirm/Cancel buttons
- Triggered when ability has `cost: 0` and `resource_type` set

**Sound Effects:**
- `quest_complete_player` - Short chime (G5 → C6) when quest objectives complete
- Sound generated procedurally in `_generate_quest_complete_sound()`
- Played when `quest_progress` message has `completed: true`

**Preloading Classes:**
When using `class_name` types across files, use `preload()` to avoid loading order issues:
```gdscript
const QuestDatabaseScript = preload("res://shared/quest_database.gd")
var quest_db: Node = null
quest_db = QuestDatabaseScript.new()
```

## MUD Terminal Theme (Aardwolf/Alter Aeon Style)

**Theme Overview:**
The client uses a classic MUD terminal aesthetic with black backgrounds and colorful text. This style is inspired by Aardwolf MUD and Alter Aeon.

**Color Palette:**
| Element | Color | Hex Code |
|---------|-------|----------|
| Background | Black | `#000000` |
| Default Text | Terminal Green | `#33FF33` |
| Headers/Important | Bright Yellow | `#FFFF00` |
| Gold/Rewards | Gold | `#FFD700` |
| Success/Bonuses | Bright Green | `#00FF00` |
| Errors/Danger | Bright Red | `#FF0000` |
| Combat Damage (Player) | Bright Yellow | `#FFFF00` |
| Combat Damage (Enemy) | Bright Red | `#FF4444` |
| XP/Magical | Magenta | `#FF00FF` |
| Info/Cyan Elements | Cyan | `#00FFFF` |
| Muted/Hints | Gray | `#808080` |
| Disabled | Dark Gray | `#555555` |
| Gems | Cyan | `#00FFFF` |
| Orange Elements | Orange | `#FFA500` |

**Key Design Decisions:**
- Damage numbers use bright, contrasting colors for visibility
- Player damage dealt: Yellow (#FFFF00) for standout
- Monster damage received: Bright red (#FF4444) for threat visibility
- Success messages in bright green stand out against terminal green text
- Panel borders use dark green (#008000) for MUD aesthetic

**Files Modified for Theme:**
- `client/client.tscn` - Panel backgrounds to black, default text to green, border colors
- `client/client.gd` - BBCode color replacements throughout
- `server/server.gd` - Chat and system message colors
- `shared/combat_manager.gd` - Combat message colors
- `shared/quest_manager.gd` - Quest display colors
- `shared/world_system.gd` - Map and location description colors

## Code Refactoring Plan (In Progress)

**Backup Branch:** `refactor-cleanup-backup` at commit 748c221

**Current File Sizes (lines):**
| File | Lines | Status |
|------|-------|--------|
| client/client.gd | 7873 | Needs cleanup |
| server/server.gd | 3909 | Needs cleanup |
| shared/combat_manager.gd | 3479 | ASCII art to move to client |
| shared/monster_database.gd | 1387 | OK |
| shared/world_system.gd | 999 | OK |
| shared/character.gd | 981 | OK |
| shared/quest_database.gd | 892 | OK |
| shared/drop_tables.gd | 591 | OK |

**Refactoring Goals:**
1. Remove unused/dead functions
2. Move ASCII art to client-side (reduce server load)
3. Split large files into purpose-specific modules if beneficial
4. Maintain backward compatibility (server running with players)

**ASCII Art Migration Plan:**
- Move `get_monster_ascii_art()` and art data from `combat_manager.gd` to `client/client.gd`
- Server sends monster name only, client renders the art
- This reduces server memory usage and network payload

**Safe Refactoring Rules:**
- Test each change before committing
- Keep server message format unchanged for backward compatibility
- Document any function removals with reason

**Progress Tracking:**
- [x] Analyze client/client.gd for unused functions
- [x] Analyze server/server.gd for unused functions
- [x] Analyze combat_manager.gd for unused functions
- [ ] Move ASCII art to client-side (see detailed plan below)
- [x] Remove confirmed dead code
- [ ] Test all core systems after changes

**Completed Cleanup (Session 2025-01-25):**
| File | Function Removed | Line | Reason |
|------|-----------------|------|--------|
| client/client.gd | `get_combat_animation_display()` | ~7298 | Never called |
| server/server.gd | `send_game_text()` | ~3879 | Never called |
| combat_manager.gd | `to_dict()` | ~3270 | Never called |

**Analysis Results:**
- **client/client.gd**: Very clean - only 1 unused function found out of 180+
- **server/server.gd**: Very clean - only 1 unused function found
- **combat_manager.gd**: Very clean - only 1 unused function found

**ASCII Art Migration Plan (Next Session):**

The ASCII art data spans lines ~1944-3055 in `combat_manager.gd` (~1100 lines, 35% of file).

**Proposed Architecture:**
1. Create new file: `client/monster_art.gd`
2. Move to client:
   - `get_monster_ascii_art()` function
   - `add_border_to_ascii_art()` function
   - All `art_map` data (the large dictionary of ASCII art)
3. Keep on server:
   - `_get_raw_monster_ascii_art()` (just color lookup, ~40 lines)
   - `get_monster_combat_bg_color()` (uses colors for background)

**Client-Side Changes:**
```gdscript
# In client.gd, when handling "combat_start" message:
var monster_name = message.combat_state.get("monster_name", "")
var local_art = MonsterArt.get_monster_ascii_art(monster_name)
var bordered_art = MonsterArt.add_border_to_ascii_art(local_art, monster_name)
# Display bordered_art instead of using server's message
```

**Backward Compatibility:**
- Server still sends `message` field with art (for old clients)
- New clients ignore server art, render locally
- After all clients update, server can stop sending art (reduces bandwidth)

**Display Preservation:**
- Copy functions exactly to maintain formatting
- Keep same ASCII_ART_FONT_SIZE constant (11)
- Wide art (>50 chars) displayed as-is
- Small art auto-centered with border
- Color tags preserved exactly

**Files to Create/Modify:**
- NEW: `client/monster_art.gd` - ASCII art data and rendering
- MODIFY: `client/client.gd` - Load MonsterArt, use local rendering
- MODIFY: `shared/combat_manager.gd` - Remove art data (keep colors only)

**Testing Checklist:**
- [ ] Combat start displays art correctly
- [ ] Wide art (Goblin, Wolf, etc.) aligned properly
- [ ] Small art centered with border
- [ ] Elemental variants display randomly
- [ ] Colors match original
- [ ] Font size correct
