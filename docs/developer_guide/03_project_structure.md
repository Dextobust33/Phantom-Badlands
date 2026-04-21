# 03 — Project Structure

This guide walks through every folder and file in the Phantom Badlands codebase, explains how the client-server architecture fits together, and tells you exactly which file to open when you need to change something.

Phantom Badlands is built with **Godot 4.6** and **GDScript**. It is a text-based multiplayer RPG with a client-server architecture. The client and server run as separate Godot instances communicating over raw TCP.

---

## 1. Folder Layout

```
phantasia-revival/
│
├── client/                         — Client-side code (what players run)
│   ├── client.gd                    — Main client script (~27,900 lines)
│   │                                  UI rendering, networking, action bar,
│   │                                  all game modes, input handling
│   ├── client.tscn                  — Client scene file (UI layout, panels, buttons)
│   ├── monster_art.gd               — ASCII art for 50+ monsters and eggs (~5,650 lines)
│   ├── trader_art.gd                — ASCII art for trader NPCs (~2,130 lines)
│   ├── trading_post_art.gd          — ASCII art for trading post buildings (~316 lines)
│   └── shaders/
│       └── low_hp_vignette.gdshader — Screen-edge red glow when HP is low
│
├── server/                         — Server-side code (runs on host machine)
│   ├── server.gd                    — Main server script (~23,700 lines)
│   │                                  Game logic, combat resolution, message routing,
│   │                                  movement validation, item generation
│   ├── server.tscn                  — Server scene (admin control panel UI)
│   ├── persistence_manager.gd       — Database layer: accounts, saves, market (~1,760 lines)
│   └── balance_config.json          — Combat tuning numbers (lethality weights,
│                                      damage formulas, ability modifiers)
│
├── shared/                         — Code used by BOTH client and server
│   ├── character.gd                 — Player stats, inventory, equipment, companions (~3,710 lines)
│   ├── combat_manager.gd            — Turn-based combat engine, damage formulas (~6,180 lines)
│   ├── world_system.gd              — Procedural terrain, tile detection, A* pathfinding (~2,450 lines)
│   ├── chunk_manager.gd             — 32x32 chunk streaming system (~525 lines)
│   ├── monster_database.gd          — Monster definitions, 50+ types, 9 tiers (~1,730 lines)
│   ├── drop_tables.gd               — Item generation, loot tables, salvage values (~4,530 lines)
│   ├── crafting_database.gd         — Crafting recipes, materials, quality tiers (~3,590 lines)
│   ├── dungeon_database.gd          — Dungeon types, floors, bosses (~2,120 lines)
│   ├── quest_database.gd            — Quest definitions, daily generation (~1,280 lines)
│   ├── quest_manager.gd             — Quest tracking, turn-in, party sync (~600 lines)
│   ├── trading_post_database.gd     — Trading post categories, shapes, colors (~1,050 lines)
│   ├── npc_post_database.gd         — NPC post placement, station layouts (~480 lines)
│   ├── titles.gd                    — Title/rank system (~440 lines)
│   ├── constants.gd                 — Shared constants: message types, class names (~225 lines)
│   └── network_protocol.gd          — Protocol stub (mostly unused; protocol is inline)
│
├── tools/                          — Development and testing utilities
│   ├── combat_simulator/            — Headless combat balance testing tool
│   │   ├── simulator.gd              — Entry point, orchestrates simulations (~580 lines)
│   │   ├── combat_engine.gd          — Simulated damage formulas and abilities (~2,050 lines)
│   │   ├── simulated_character.gd    — Lightweight character for simulation (~550 lines)
│   │   ├── gear_generator.gd         — Equipment generation for sims (~395 lines)
│   │   ├── results_writer.gd         — JSON and Markdown output (~525 lines)
│   │   ├── quick_simulation.gd       — Quick-run script (~260 lines)
│   │   ├── test_simulation.gd        — Test harness (~125 lines)
│   │   ├── run_simulation.bat        — Windows batch launcher
│   │   └── run_quick_simulation.bat  — Quick simulation launcher
│   └── test_setup_commands.txt      — Manual test setup commands
│
├── launcher/                       — Auto-update launcher (separate Godot project)
│   ├── launcher.gd                  — Checks GitHub Releases API, downloads updates
│   ├── launcher.tscn                — Launcher UI (progress bar, play button)
│   ├── project.godot                — Launcher's own Godot project file
│   └── export_presets.cfg           — Launcher export configuration
│
├── addons/                         — Third-party Godot plugins
│   └── godot-sqlite/               — SQLite plugin for database access
│       ├── bin/                      — Compiled native libraries (.dll, .so)
│       ├── gdsqlite.gdextension     — GDExtension descriptor
│       ├── godot-sqlite.gd          — GDScript wrapper
│       └── plugin.cfg               — Plugin metadata
│
├── audio/                          — Sound effects
│   ├── Damage01.wav                 — Combat hit sounds
│   ├── Death.wav                    — Player death
│   ├── EggFound.wav                 — Companion egg discovery
│   ├── Hit.wav, Slash01.wav         — Melee combat
│   ├── Fire01.wav, Fire02.wav       — Fire/magic effects
│   ├── Explosion1.wav               — Area damage
│   ├── GemGain.wav                  — Currency/gem pickup
│   ├── LootVanish.wav               — Item despawn
│   ├── PlayerBuffed.wav             — Buff applied
│   ├── PlayerHealed.wav             — Healing
│   ├── PowerUp01.wav                — Level up / power gain
│   ├── SciFi01.wav, SciFi02.wav     — Special ability sounds
│   ├── UI01.wav, UI03.wav, UI06.wav — Menu/button click sounds
│   └── Out of my dreams NES.wav     — Background music track
│
├── font/
│   └── Consolas/
│       └── consolas.ttf             — Monospace font used everywhere in the UI
│
├── docs/                           — Documentation
│   ├── developer_guide/             — This guide series
│   ├── simulation_results/          — Combat simulator output (JSON + Markdown)
│   ├── archive/                     — Historical docs
│   ├── QUICK_REFERENCE.md           — Condensed overview and file map
│   ├── SYSTEM_OVERVIEW.md           — Dense AI context reference
│   ├── CODE_GUIDE.md                — Walkthrough for modifying the game
│   ├── architecture.md              — System architecture and data flow
│   ├── action-bar-states.md         — Action bar state machine (critical for UI work)
│   ├── combat-flow.md               — Combat lifecycle and damage formulas
│   ├── networking-protocol.md       — All message types and sequence diagrams
│   ├── quest-system.md              — Quest flow and trading posts
│   └── game-systems.md              — Feature documentation for all systems
│
├── scripts/
│   └── create_release.ps1           — PowerShell script for building releases
│
├── builds/                         — Exported game builds (not committed to git)
├── releases/                       — Release ZIP files (not committed to git)
│
├── project.godot                   — Godot project configuration
├── export_presets.cfg              — Export profiles (client, server)
├── VERSION.txt                     — Current version string (e.g., "0.9.144")
├── admin_tool.gd                   — Standalone admin tool script
├── icon.svg                        — Application icon
└── CLAUDE.md                       — AI assistant development instructions
```

### Line count summary

The codebase totals roughly **90,000 lines** of GDScript across the main source files:

| Area | Lines | Notes |
|------|------:|-------|
| `client/client.gd` | 27,900 | Largest file in the project |
| `server/server.gd` | 23,700 | Second largest |
| `shared/` (all files) | 28,900 | 15 files of shared game logic |
| `client/` (art files) | 8,100 | ASCII art data |
| `server/persistence_manager.gd` | 1,760 | Database layer |
| `tools/combat_simulator/` | 4,490 | Balance testing |
| **Total** | **~94,850** | |

---

## 2. The Client-Server Split

Phantom Badlands uses a strict client-server architecture. The client and server are separate Godot scenes that run in separate OS windows (or on separate machines). They communicate over raw TCP sockets.

### What the client handles

The client (`client/client.gd`) is responsible for everything the player sees and touches:

- **UI rendering** -- RichTextLabel panels with BBCode for styled text output
- **User input** -- keyboard polling, action bar hotkeys, chat input, mouse clicks
- **Action bar** -- 10 contextual button slots (Space, Q, W, E, R, 1-5) that change based on game state
- **ASCII art display** -- monster art, trader art, trading post art, egg art
- **Map rendering** -- colored tile grid showing the world around the player
- **Sound effects** -- loading and playing `.wav` files on game events
- **Local state tracking** -- which menu is open, what mode is active, pending confirmations

The client never makes authoritative game decisions. It sends requests to the server and displays whatever the server sends back.

### What the server handles

The server (`server/server.gd`) is the authority for all game state:

- **Game logic** -- combat resolution, damage calculation, hit/miss determination
- **Item generation** -- loot drops, crafting results, salvage output
- **Movement validation** -- confirming the player can move to a tile
- **World state** -- dungeon instances, NPC positions, trading post inventories
- **Persistence** -- saving and loading accounts, characters, market listings, houses
- **Message routing** -- receiving client messages, processing them, sending responses
- **Party management** -- forming parties, syncing movement, scaling combat
- **Security** -- rate limiting, brute-force protection, IP bans

### Shared code

The `shared/` folder contains code loaded by **both** the client and the server. This is necessary because both sides need access to the same formulas, constants, and data definitions:

- **`character.gd`** -- Both sides need to understand character stats, inventory structure, and level-up formulas. The server creates `Character` instances for each connected player. The client uses the `CharacterScript` constant to access class definitions and item display helpers.
- **`combat_manager.gd`** -- The server runs combat logic. The client references combat data for display purposes (showing damage numbers, ability descriptions).
- **`world_system.gd`** -- Both sides need procedural terrain generation. The server uses it for movement validation and tile detection. The client uses it to render the map.
- **`monster_database.gd`**, **`drop_tables.gd`**, **`dungeon_database.gd`**, etc. -- The server uses these to generate monsters, items, and dungeons. The client references them for display names, descriptions, and UI hints.

The key principle: **the server is authoritative, but the client needs the same data definitions to render the game correctly.**

### Communication protocol

Client and server communicate via raw TCP sockets using **newline-delimited JSON**:

```
{"type": "move", "direction": "north"}\n
{"type": "combat_action", "action": "attack"}\n
```

Each message is a JSON object with a `"type"` field that identifies the message kind. The server reads messages line by line (splitting on `\n`), parses each as JSON, and dispatches based on the type.

Large messages (above a threshold) are compressed with gzip. The receiver detects compressed data by checking if the first bytes match the gzip magic number.

There is no HTTP, no WebSocket, no Godot high-level multiplayer. It is a simple TCP stream with hand-rolled message framing.

### Message flow example

Here is what happens when a player presses the "Attack" button during combat:

```
1. Client: User presses Space (action bar slot 0)
2. Client: Looks up current_actions[0] -> {action_type: "server", action_data: "attack"}
3. Client: Sends JSON -> {"type": "combat_action", "action": "attack"}
4. Server: handle_message() receives it, dispatches to handle_combat_action()
5. Server: combat_mgr.process_player_turn(peer_id, "attack") runs damage formulas
6. Server: Sends back -> {"type": "combat_update", "result": {...}, "monster_hp": 45, ...}
7. Client: Receives "combat_update", updates game_output with damage text and HP bars
```

---

## 3. How Files Connect to Each Other

### Dependency graph

```
                    ┌──────────────────────────────────────────────┐
                    │              client/client.gd                │
                    │  (UI, input, networking, display)            │
                    │                                              │
                    │  Loads lazily:                               │
                    │    client/monster_art.gd                     │
                    │    client/trader_art.gd                      │
                    │    client/trading_post_art.gd                │
                    │                                              │
                    │  Preloads:                                   │
                    │    shared/character.gd                       │
                    └──────────────┬───────────────────────────────┘
                                   │ TCP messages
                                   │ (JSON over socket)
                    ┌──────────────┴───────────────────────────────┐
                    │              server/server.gd                │
                    │  (game logic, message routing, authority)    │
                    │                                              │
                    │  Preloads and instantiates:                  │
                    │    server/persistence_manager.gd             │
                    │    shared/character.gd                       │
                    │    shared/combat_manager.gd                  │
                    │    shared/world_system.gd                    │
                    │    shared/chunk_manager.gd                   │
                    │    shared/drop_tables.gd                     │
                    │    shared/monster_database.gd                │
                    │    shared/quest_database.gd                  │
                    │    shared/quest_manager.gd                   │
                    │    shared/crafting_database.gd               │
                    │    shared/dungeon_database.gd                │
                    │    shared/trading_post_database.gd           │
                    │    shared/npc_post_database.gd               │
                    │    shared/titles.gd                          │
                    │                                              │
                    │  Reads at runtime:                           │
                    │    server/balance_config.json                │
                    └──────────────────────────────────────────────┘
```

Key rules:
- **`persistence_manager.gd`** is used ONLY by `server.gd` -- the client never touches it.
- **Art files** (`monster_art.gd`, `trader_art.gd`, `trading_post_art.gd`) are used ONLY by `client.gd` -- the server has no concept of ASCII art.
- **All `shared/` files** are available to both sides, but in practice the client only preloads `character.gd` and lazily loads a few others for display data.

### How the server loads shared code

In `server.gd`, shared scripts are loaded at the top of the file using `preload()` and instantiated in `_ready()`:

```gdscript
# At top of server.gd -- preload script references
const PersistenceManagerScript = preload("res://server/persistence_manager.gd")
const DropTablesScript = preload("res://shared/drop_tables.gd")
const QuestDatabaseScript = preload("res://shared/quest_database.gd")
const QuestManagerScript = preload("res://shared/quest_manager.gd")
const TradingPostDatabaseScript = preload("res://shared/trading_post_database.gd")
const TitlesScript = preload("res://shared/titles.gd")
const CraftingDatabaseScript = preload("res://shared/crafting_database.gd")
const DungeonDatabaseScript = preload("res://shared/dungeon_database.gd")
const NpcPostDatabaseScript = preload("res://shared/npc_post_database.gd")
const ChunkManagerScript = preload("res://shared/chunk_manager.gd")
```

```gdscript
# In server.gd _ready() -- create instances and add as child nodes
func _ready():
    persistence = PersistenceManagerScript.new()
    add_child(persistence)

    chunk_manager = ChunkManagerScript.new()
    add_child(chunk_manager)

    world_system = WorldSystem.new()
    add_child(world_system)

    monster_db = MonsterDatabase.new()
    add_child(monster_db)

    combat_mgr = CombatManager.new()
    add_child(combat_mgr)

    drop_tables = DropTablesScript.new()
    add_child(drop_tables)
    combat_mgr.set_drop_tables(drop_tables)
    combat_mgr.set_monster_database(monster_db)

    quest_db = QuestDatabaseScript.new()
    add_child(quest_db)

    quest_mgr = QuestManagerScript.new()
    add_child(quest_mgr)

    trading_post_db = TradingPostDatabaseScript.new()
    add_child(trading_post_db)
```

Each shared script is instantiated with `.new()` and then added as a child node of the server via `add_child()`. This is a Godot pattern -- nodes must be in the scene tree to participate in the engine lifecycle (`_process()`, `_ready()`, etc.).

### How the client loads shared code

The client is lighter. It preloads only what it needs for display:

```gdscript
# At top of client.gd
const CharacterScript = preload("res://shared/character.gd")

# Art scripts are loaded lazily (on first use)
var _monster_art_script = null
func _get_monster_art():
    if _monster_art_script == null:
        _monster_art_script = load("res://client/monster_art.gd")
    return _monster_art_script
```

The client uses `CharacterScript` to access class constants, item color definitions, and display helpers. Monster art, trader art, and trading post art are loaded lazily (on first access) to avoid slowing down initial startup.

### Cross-references within shared code

Some shared scripts reference each other:

- `combat_manager.gd` uses `drop_tables.gd` and `monster_database.gd` (injected via setter methods)
- `world_system.gd` and `chunk_manager.gd` reference each other (bidirectional: `world_system.chunk_manager` and `chunk_manager.terrain_generator`)
- `quest_manager.gd` references quest definitions from `quest_database.gd`

These connections are wired up in `server.gd`'s `_ready()` function, not through `preload()`.

---

## 4. Scene Hierarchy -- Client

The client scene (`client/client.tscn`) defines the entire UI layout. The root node has `client.gd` attached as its script. Here is the full node tree with explanations:

```
ClientScene (Control)                          — Root node, client.gd attached
│
├── RootContainer (VBoxContainer)              — Main gameplay layout (visible during play)
│   │
│   ├── StatsBar (VBoxContainer)               — Top bar: health, XP, currency
│   │   ├── LevelRow (HBoxContainer)
│   │   │   ├── PlayerLevel (Label)            — "Level 42" text
│   │   │   └── MusicToggle (Button)           — Music on/off button
│   │   │
│   │   ├── PlayerHealthBar (Control)          — Layered HP bar
│   │   │   ├── Background (Panel)             — Dark background
│   │   │   ├── Fill (Panel)                   — Green fill (width = HP %)
│   │   │   └── HPLabel (Label)                — "HP: 350/500" centered text
│   │   │
│   │   ├── ResourceBar (Control)              — Class resource bar (Stamina/Mana/etc.)
│   │   │   ├── Background (Panel)
│   │   │   ├── Fill (Panel)                   — Yellow fill
│   │   │   └── ResourceLabel (Label)          — "Stamina: 80/100"
│   │   │
│   │   ├── PlayerXPBar (Control)              — Experience progress bar
│   │   │   ├── Background (Panel)
│   │   │   ├── Fill (Panel)                   — Brown/gold fill
│   │   │   └── XPLabel (Label)                — "XP: 1,250 / 5,000"
│   │   │
│   │   └── CurrencyDisplay (HBoxContainer)    — Gold and rank display
│   │       ├── GoldContainer (HBoxContainer)
│   │       │   ├── GoldIcon (Label)           — "Valor:" in gold color
│   │       │   └── GoldLabel (Label)          — "1,500"
│   │       └── RankContainer (HBoxContainer)
│   │           ├── RankIcon (Label)           — "Rank:" in cyan
│   │           └── RankLabel (Label)          — "Veteran"
│   │
│   ├── TopSection (HBoxContainer)             — Main content area (left 2/3 + right 1/3)
│   │   │
│   │   ├── GameOutputContainer (Control)      — Left panel: game text output
│   │   │   ├── GameOutput (RichTextLabel)     — Main text area (BBCode enabled)
│   │   │   │                                    All game messages render here
│   │   │   ├── BuffDisplayLabel (RichTextLabel)     — Buff icons overlay (bottom-right)
│   │   │   ├── CompanionArtOverlay (RichTextLabel)  — Companion ASCII art (bottom-right)
│   │   │   └── ResourceBarsOverlay (RichTextLabel)  — Persistent HP/resource bars overlay
│   │   │
│   │   └── MapPanel (VBoxContainer)           — Right panel: world map
│   │       └── MapDisplay (RichTextLabel)     — Colored ASCII tile grid
│   │
│   ├── EnemyHealthBar (HBoxContainer)         — Appears during combat only
│   │   ├── Label                              — "Enemy:" prefix
│   │   └── BarContainer (Control)             — Red HP bar with label
│   │       ├── Background (Panel)
│   │       ├── Fill (Panel)                   — Red fill
│   │       └── HPLabel (Label)                — "??? " or "HP: 120/200"
│   │
│   └── BottomStrip (HBoxContainer)            — Bottom area: action bar + chat
│       │
│       ├── CenterPanel (VBoxContainer)        — Left side: action bar
│       │   └── ActionBar (HBoxContainer)      — 10 action button slots
│       │       ├── Action1  (Button + "Space" label)
│       │       ├── Action2  (Button + "Q" label)
│       │       ├── Action3  (Button + "W" label)
│       │       ├── Action4  (Button + "E" label)
│       │       ├── Action5  (Button + "R" label)
│       │       ├── Action6  (Button + "1" label)
│       │       ├── Action7  (Button + "2" label)
│       │       ├── Action8  (Button + "3" label)
│       │       ├── Action9  (Button + "4" label)
│       │       └── Action10 (Button + "5" label)
│       │
│       └── ChatPanel (VBoxContainer)          — Right side: chat + input
│           ├── ChatTabBar (HBoxContainer)     — Tab buttons
│           │   ├── ChatTab (Button)           — "Chat" tab
│           │   └── PlayersTab (Button)        — "Players" tab
│           ├── ChatOutput (RichTextLabel)     — Chat message display
│           ├── OnlinePlayersList (RichTextLabel) — Player list (hidden by default)
│           └── InputRow (HBoxContainer)
│               ├── InputField (LineEdit)      — Text input for commands/chat
│               └── SendButton (Button)        — "Send" button
│
├── LoginPanel (Panel)                         — Shown at startup (visible=false initially)
│   └── VBox
│       ├── Title (Label)                      — "Phantom Badlands"
│       ├── Subtitle (Label)                   — "Login or Register"
│       ├── UsernameField (LineEdit)
│       ├── PasswordField (LineEdit)           — secret=true (dots instead of text)
│       ├── ConfirmPasswordField (LineEdit)    — For registration only
│       ├── ButtonContainer
│       │   ├── LoginButton (Button)
│       │   └── RegisterButton (Button)
│       └── StatusLabel (RichTextLabel)        — Error/success messages
│
├── CharacterSelectPanel (Panel)               — Shown after login
│   └── VBox
│       ├── Title (Label)                      — "Select Character"
│       ├── CharacterList (VBoxContainer)      — Dynamically populated with character buttons
│       ├── ButtonContainer
│       │   ├── CreateButton (Button)          — "Create New Character"
│       │   └── LeaderboardButton (Button)
│       ├── AccountContainer
│       │   ├── SanctuaryButton (Button)       — Opens house/sanctuary screen
│       │   ├── ChangePasswordButton (Button)
│       │   └── LogoutButton (Button)
│       └── StatusLabel (RichTextLabel)
│
├── CharacterCreatePanel (Panel)               — New character form
│   └── VBox
│       ├── Title, NameField
│       ├── RaceOption (OptionButton)          — Dropdown: Human, Elf, Dwarf, etc.
│       ├── RaceDescription (Label)            — Updates as race is selected
│       ├── ClassOption (OptionButton)         — Dropdown: Fighter, Mage, Ranger, etc.
│       ├── ClassDescription (RichTextLabel)   — Updates as class is selected
│       ├── Warning (Label)                    — "WARNING: Permadeath is enabled!"
│       ├── ConfirmButton, CancelButton
│       └── StatusLabel (RichTextLabel)
│
├── DeathPanel (Panel)                         — Shown on permadeath (red-tinted border)
│   └── VBox
│       ├── DeathMessage (RichTextLabel)       — "CHARACTER NAME HAS FALLEN"
│       ├── DeathStats (RichTextLabel)         — Level, XP, leaderboard rank
│       └── ContinueButton (Button)           — Returns to character select
│
├── LeaderboardPanel (Panel)                   — High scores
│   └── VBox
│       ├── LeaderboardList (RichTextLabel)    — "HALL OF FALLEN HEROES"
│       ├── ToggleButton (Button)              — Switch between heroes / deadliest monsters
│       └── CloseButton (Button)
│
└── PlayerInfoPanel (Panel)                    — Examining another player
    └── VBox
        ├── Title (Label)                      — "Player Info"
        ├── PlayerInfoContent (RichTextLabel)  — Stats, equipment, companions
        └── CloseButton (Button)
```

### Key Godot concepts for the client scene

If you are new to Godot:

- **Control nodes** are the base for all UI elements. They define rectangular regions on screen.
- **VBoxContainer / HBoxContainer** automatically arrange their children vertically or horizontally.
- **RichTextLabel** displays styled text using BBCode (`[color=#FF0000]red text[/color]`, `[b]bold[/b]`). This is the primary display mechanism -- the game is text-based, so almost everything renders into RichTextLabels.
- **Panel** is a Control with a background style. Used for overlay panels (login, death, etc.) that cover the main gameplay area.
- **`@onready`** variables in GDScript reference these scene nodes. For example:
  ```gdscript
  @onready var game_output = $RootContainer/TopSection/GameOutputContainer/GameOutput
  ```
  This grabs the GameOutput node from the scene tree when the script is ready. The `$` syntax is shorthand for `get_node()`.

### Panel visibility

Only one major panel is visible at a time. The client manages this through a `GameState` enum and shows/hides panels accordingly:

- **Login** -- LoginPanel visible, everything else hidden
- **Character Select** -- CharacterSelectPanel visible
- **House Screen** -- RootContainer visible but showing house content
- **Playing** -- RootContainer visible with game content
- **Death** -- DeathPanel overlays everything

---

## 5. Scene Hierarchy -- Server

The server scene (`server/server.tscn`) provides an admin control panel. It is a simple tools UI, not a game display:

```
Server (Control)                               — Root node, server.gd attached
│
└── VBox (VBoxContainer)                       — Main vertical layout (20px padding)
    │
    ├── Title (Label)                          — "Phantom Badlands Server" (blue, 24pt)
    │
    ├── StatusRow (HBoxContainer)
    │   ├── StatusIndicator (Label)            — "ONLINE" (green dot)
    │   ├── PortLabel (Label)                  — "Port: 9080"
    │   └── PlayerCountLabel (Label)           — "Players: 3" (gold, right-aligned)
    │
    ├── Separator (HSeparator)
    │
    ├── PlayersTitle (Label)                   — "Connected Players:"
    ├── PlayerList (RichTextLabel)             — Scrollable list of connected players
    │                                            Shows names, levels, locations
    │
    ├── LogTitle (Label)                       — "Server Log:"
    ├── ServerLog (RichTextLabel)              — Scrollable server log (2x height)
    │                                            Connection events, errors, game events
    │
    ├── BroadcastRow (HBoxContainer)           — Send messages to all players
    │   ├── BroadcastLabel (Label)             — "Broadcast:"
    │   ├── BroadcastInput (LineEdit)          — Message text field
    │   └── BroadcastButton (Button)           — "Send"
    │
    ├── ButtonRow (HBoxContainer)              — Server control buttons
    │   ├── RestartButton (Button)             — "Restart Server"
    │   ├── PendingUpdateButton (Button)       — "Pending Update" (countdown + kick)
    │   ├── CancelUpdateButton (Button)        — "Cancel Update" (hidden by default)
    │   └── Spacer (Control)
    │
    ├── WipeLabel (Label)                      — "Wipe Options:"
    ├── WipeRow (HBoxContainer)                — Data wipe buttons
    │   ├── RespawnButton (Button)             — "Respawn Gatherables"
    │   ├── MapSeedKeepMarketButton (Button)   — "Map (Keep Seed+Market)"
    │   ├── MapSeedWipeMarketButton (Button)   — "Map (Keep Seed)"
    │   ├── MapNewSeedButton (Button)          — "Map (New Seed)"
    │   ├── FullWipeButton (Button)            — "FULL WIPE" (red text)
    │   └── WipeSpacer (Control)
    │
    ├── ConfirmDialog (ConfirmationDialog)     — "Confirm Server Restart" popup
    ├── WipeConfirmDialog (ConfirmationDialog) — First wipe confirmation
    └── WipeFinalDialog (ConfirmationDialog)   — Second wipe confirmation ("FINAL CONFIRMATION")
```

The server UI is a management dashboard. You can watch players connect, read log messages, broadcast announcements, restart the server, or wipe data. During normal gameplay, you just leave this window running.

---

## 6. Data Storage -- Where Things Are Saved

All game data is stored as **JSON files** in Godot's user data directory:

```
user://data/
```

On Windows, this resolves to:
```
%APPDATA%\Godot\app_userdata\PhantomBadlands\data\
```

Which typically expands to something like:
```
C:\Users\YourName\AppData\Roaming\Godot\app_userdata\PhantomBadlands\data\
```

### File inventory

| File | Purpose |
|------|---------|
| `accounts.json` | All user accounts with hashed passwords and character slot metadata |
| `characters/{account_id}_{name}.json` | Individual character save files (stats, inventory, position, quests) |
| `houses.json` | Sanctuary (account-level house) data -- upgrades, stored items, kennel, companions |
| `market_data.json` | Active market listings at all trading posts |
| `leaderboard.json` | Top 100 dead characters (permadeath hall of fame) |
| `monster_kills_leaderboard.json` | Deadliest monsters (most player kills) |
| `realm_state.json` | Shared world state (treasury, realm-wide events) |
| `ban_list.json` | Banned IP addresses with reasons and timestamps |
| `player_tiles.json` | Player-placed tiles (walls, floors, roads) |
| `player_posts.json` | Player-built enclosures (named safe zones on the map) |
| `guards.json` | Guard NPCs placed by players |
| `corpses.json` | Dead player corpses visible on the map |
| `player_storage.json` | Player personal storage data |

### Important notes about data storage

- **No SQL database for game data.** Everything is JSON files on disk. The SQLite plugin is available but the game uses flat files for persistence.
- **Saving is synchronous.** The server writes files during gameplay. This works fine for the expected player counts (dozens, not thousands).
- **The `persistence_manager.gd` caches everything in memory.** On startup, it loads all JSON files into dictionaries. Changes are made to the in-memory dictionaries and then flushed to disk.
- **Character saves happen periodically** and on disconnect. If the server crashes, some recent progress may be lost.
- **Chunk data** (terrain modifications, depleted resource nodes) is stored separately by the `chunk_manager.gd` in `user://data/chunks/`.

### Godot user data directory

Godot's `user://` path is different from the project directory. It is where runtime data lives:

- On Windows: `%APPDATA%\Godot\app_userdata\<ProjectName>\`
- On Linux: `~/.local/share/godot/app_userdata/<ProjectName>/`
- On macOS: `~/Library/Application Support/Godot/app_userdata/<ProjectName>/`

The project name comes from `project.godot` -> `config/name`, which is `"PhantomBadlands"`.

---

## 7. Configuration Files

### project.godot

The main Godot project configuration file. Key settings:

```ini
config/name="PhantomBadlands"
run/main_scene="uid://dbwq54oox3iif"   # client.tscn (launched by default)

[display]
window/size/viewport_width=1280
window/size/viewport_height=720

[rendering]
renderer/rendering_method="gl_compatibility"   # Maximum compatibility, no Vulkan needed
```

- **Window size** is 1280x720 -- the UI is designed for this resolution.
- **Renderer** is GL Compatibility (OpenGL), not Vulkan. This ensures the game runs on older hardware and integrated GPUs.
- **Main scene** is the client. The server is launched separately with a command-line argument: `--scene server/server.tscn` (or via direct path).

### balance_config.json

Combat tuning parameters loaded by the server at startup. This is the single place to adjust combat feel without changing code:

```json
{
  "profile": "default",
  "version": "1.1",
  "combat": {
    "player_str_multiplier": 0.02,
    "player_crit_base": 5,
    "player_crit_per_dex": 0.5,
    "player_crit_max": 25,
    "player_crit_damage": 1.5,
    "defense_formula_constant": 100,
    "defense_max_reduction": 0.6
  },
  "lethality": {
    "hp_weight": 2.5,
    "str_weight": 7.5,
    "def_weight": 2.5,
    "speed_weight": 5.0,
    "ability_modifiers": {
      "sunder": 0.30,
      "multi_strike": 1.00,
      "death_curse": 0.75
    }
  }
}
```

The server loads this file in `_ready()` via `load_balance_config()` and passes it to the combat manager and monster database. Changing these values adjusts how hard monsters hit, how effective player defense is, and how dangerous monster abilities are.

### VERSION.txt

A plain text file containing the current version string (e.g., `0.9.144`). Used by:

- The **launcher** to compare local vs remote version and trigger auto-updates
- The **release process** to tag GitHub releases
- The **client** to display version info

---

## 8. Which File to Edit for Common Tasks

This is the most important reference for day-to-day development. When you want to change something, start here:

| Want to... | Edit this file |
|------------|---------------|
| **UI & Display** | |
| Change what appears in the game output | `client/client.gd` |
| Add or change an action bar button | `client/client.gd` (`update_action_bar()` + `execute_local_action()`) |
| Change the map display | `client/client.gd` (map rendering functions) |
| Change the stats bar or HP display | `client/client.gd` (update functions) + `client/client.tscn` (layout) |
| Change UI panel layout or add a panel | `client/client.tscn` (scene editor) |
| | |
| **Server Logic** | |
| Add a new server command | `server/server.gd` (`handle_message()` match + handler function) |
| Add a new chat `/command` | `client/client.gd` (`command_keywords` array + `process_command()`) AND `server/server.gd` (handler) |
| Change movement or validation logic | `server/server.gd` (movement handler) |
| Change save/load behavior | `server/persistence_manager.gd` |
| Add a new data file to persist | `server/persistence_manager.gd` (add file path + load/save functions) |
| | |
| **Combat** | |
| Change damage formulas | `shared/combat_manager.gd` |
| Adjust combat balance numbers | `server/balance_config.json` |
| Add a new player ability | `shared/combat_manager.gd` (ability logic) + `shared/character.gd` (class ability list) |
| Add a new monster ability | `shared/combat_manager.gd` + `shared/monster_database.gd` |
| Run combat simulations | `tools/combat_simulator/simulator.gd` (adjust params, then run headless) |
| | |
| **Content** | |
| Add a new monster type | `shared/monster_database.gd` |
| Add ASCII art for a monster | `client/monster_art.gd` (`get_art_map()`) |
| Add a new item or change loot drops | `shared/drop_tables.gd` |
| Add a crafting recipe | `shared/crafting_database.gd` |
| Add a new dungeon | `shared/dungeon_database.gd` |
| Add a new quest type | `shared/quest_database.gd` |
| Change world generation or terrain | `shared/world_system.gd` |
| Add a new trading post category | `shared/trading_post_database.gd` |
| Change NPC post layouts | `shared/npc_post_database.gd` |
| | |
| **Character** | |
| Change character stats or formulas | `shared/character.gd` |
| Change level-up XP requirements | `shared/character.gd` |
| Change inventory behavior | `shared/character.gd` |
| Add a new class | `shared/character.gd` (stats) + `shared/constants.gd` (name) + `shared/combat_manager.gd` (abilities) |
| Change titles or ranks | `shared/titles.gd` |
| | |
| **Infrastructure** | |
| Change the network port | `shared/constants.gd` (`SERVER_PORT`) or command line `--port=XXXX` |
| Change the launcher update behavior | `launcher/launcher.gd` |
| Change the Godot project settings | `project.godot` (or use Godot editor) |
| Add a sound effect | `audio/` folder + `client/client.gd` (play trigger) |

### Common multi-file changes

Most features touch more than one file. Here are typical patterns:

**Adding a new game feature (e.g., a new gathering type):**
1. `shared/drop_tables.gd` -- define the new catches/rewards
2. `shared/world_system.gd` -- add terrain detection for the new resource
3. `server/server.gd` -- add message handler and game logic
4. `client/client.gd` -- add action bar button, display mode, and UI
5. `shared/character.gd` -- add skill tracking variable if needed

**Adding a new monster:**
1. `shared/monster_database.gd` -- define monster stats, tier, abilities
2. `client/monster_art.gd` -- add ASCII art in `get_art_map()`
3. (Optional) `shared/dungeon_database.gd` -- if it is a dungeon boss
4. (Optional) `shared/drop_tables.gd` -- if it drops unique items or eggs

**Adding a new item type:**
1. `shared/drop_tables.gd` -- define the item, its properties, drop conditions
2. `server/server.gd` -- handle item usage on the server
3. `client/client.gd` -- display the item, handle "Use" button
4. `shared/character.gd` -- if the item modifies character state

---

## Summary

The project has a clear three-part structure:

1. **`client/`** -- What players see. One massive script (`client.gd`) handles all UI, input, and display. Art files provide ASCII visuals.
2. **`server/`** -- What runs the game. One massive script (`server.gd`) handles all game logic. `persistence_manager.gd` handles saving. `balance_config.json` tunes numbers.
3. **`shared/`** -- The rulebook. Fifteen scripts define the game's data and formulas. Both client and server load these.

When you are unsure where something lives, start with the table in Section 8. When you are unsure how something works, read the relevant `shared/` file first (it has the data definitions), then trace into `server.gd` (logic) or `client.gd` (display).
