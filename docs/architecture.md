# Phantom Badlands - Architecture Overview

## System Architecture

```mermaid
graph TB
    subgraph Client["CLIENT (client/)"]
        UI[UI Layer<br/>RichTextLabel + BBCode]
        AB[Action Bar System]
        NET_C[StreamPeerTCP]
        MA[Monster Art<br/>monster_art.gd]
    end

    subgraph Server["SERVER (server/)"]
        NET_S[TCPServer<br/>Port 9080]
        PM[Peer Manager]
        MH[Message Handler]
        PERSIST[Persistence Manager<br/>SQLite]
    end

    subgraph Shared["SHARED (shared/)"]
        CHAR[Character<br/>Stats, Inventory, Buffs]
        CM[CombatManager<br/>Turn-based Combat]
        WS[WorldSystem<br/>Terrain, Hotspots]
        MDB[MonsterDatabase<br/>40+ Monster Types]
        QDB[QuestDatabase<br/>Quest Definitions]
        TP[TradingPostDatabase<br/>10 Trading Posts]
        DT[DropTables<br/>Item Generation]
        CONST[Constants<br/>Message Types, Classes]
    end

    UI --> AB
    AB --> NET_C
    NET_C <-->|JSON over TCP| NET_S
    NET_S --> PM
    PM --> MH
    MH --> PERSIST

    MH --> CHAR
    MH --> CM
    MH --> WS
    MH --> MDB
    MH --> QDB
    MH --> TP
    CM --> DT

    Client -.->|Uses| MA
    Client -.->|Uses| CONST
    Server -.->|Uses| CONST
```

## Key Files Reference

| File | Lines | Purpose |
|------|-------|---------|
| `client/client.gd` | ~24000 | Main client, UI, networking, action bar, market |
| `client/monster_art.gd` | ~1200 | ASCII art rendering |
| `server/server.gd` | ~15000 | Server logic, message routing, market, crafting |
| `server/persistence_manager.gd` | ~1500 | SQLite persistence, houses, market listings |
| `shared/character.gd` | ~1200 | Player data, stats, inventory, companions |
| `shared/combat_manager.gd` | ~5000 | Turn-based combat engine, party combat |
| `shared/world_system.gd` | ~1200 | Terrain, chunks, gathering nodes |
| `shared/monster_database.gd` | ~1400 | Monster definitions (9 tiers) |
| `shared/quest_database.gd` | ~900 | Quest definitions |
| `shared/drop_tables.gd` | ~4000 | Item generation, crafting materials, valor calc |
| `shared/crafting_database.gd` | ~2000 | Crafting recipes, materials, stations |
| `shared/chunk_manager.gd` | ~500 | 32x32 chunk system, delta updates |

## Data Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant S as Server
    participant DB as SQLite

    Note over C,S: Connection Flow
    C->>S: connect
    S->>C: welcome
    C->>S: login (username, password)
    S->>DB: Verify credentials
    DB->>S: Account data
    S->>C: login_success / login_failed

    Note over C,S: Character Selection
    C->>S: list_characters
    S->>C: character_list
    C->>S: select_character
    S->>DB: Load character
    S->>C: character_loaded + location_update

    Note over C,S: Gameplay Loop
    C->>S: move (direction)
    S->>S: Check terrain, encounters
    alt Monster Encounter
        S->>C: combat_start
        loop Combat Rounds
            C->>S: combat_action
            S->>C: combat_update
        end
        S->>C: combat_end
    else Safe Movement
        S->>C: location_update
    end
```

## Class Hierarchy

```mermaid
classDiagram
    class Character {
        +String name
        +String class_type
        +int level
        +Dictionary stats
        +Array inventory
        +Dictionary equipped
        +Array active_quests
        +bool in_combat
        +get_effective_stat()
        +calculate_damage()
        +apply_equipment_bonuses()
    }

    class CombatManager {
        +Dictionary active_combats
        +start_combat()
        +process_combat_command()
        +process_player_turn()
        +process_monster_turn()
        +end_combat()
    }

    class WorldSystem {
        +Dictionary hotspots
        +generate_terrain()
        +get_location_info()
        +calculate_monster_level()
        +is_in_hotspot()
    }

    class MonsterDatabase {
        +Dictionary MONSTERS
        +generate_monster()
        +get_monster_by_level()
        +get_abilities()
    }

    CombatManager --> Character : uses
    CombatManager --> MonsterDatabase : spawns from
    WorldSystem --> MonsterDatabase : determines level
```

## Trading Posts Map

```
                    Frozen Reach (0, -400)
                          |
                          |
                    Frostgate (0, -100)
                          |
    Inferno (-350, 0) --- Westhold (-150, 0) --- Crossroads (0, 0) --- Eastwatch (150, 0) --- Void's Edge (350, 0)
                                                      |
                                                 Haven (0, 10) [SPAWN]
                                                      |
                                                Southport (0, -150)

                    Shadowmere (300, 300) [High-level hub]
```
