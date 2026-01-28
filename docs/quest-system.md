# Quest System

## Quest Types

```mermaid
graph TB
    subgraph Types["Quest Types"]
        KILL_ANY[KILL_ANY<br/>Kill X monsters of any type]
        KILL_LEVEL[KILL_LEVEL<br/>Kill monster of level X+]
        HOTZONE[HOTZONE_KILL<br/>Kill X in hotzone near post]
        EXPLORE[EXPLORATION<br/>Visit specific location]
        BOSS[BOSS_HUNT<br/>Defeat level X+ monster]
    end
```

| Type | Target Field | Description |
|------|--------------|-------------|
| `KILL_ANY` | `target` = count | Kill any monsters |
| `KILL_LEVEL` | `target` = min level, `kill_count` = count | Kill monsters above level |
| `HOTZONE_KILL` | `target` = count, `max_distance` = range | Kill in nearby hotzones |
| `EXPLORATION` | `destination_post` = trading post ID | Visit a location |
| `BOSS_HUNT` | `target` = min level | Single powerful kill |

## Quest Flow

```mermaid
sequenceDiagram
    participant P as Player
    participant TP as Trading Post
    participant S as Server
    participant Q as Quest Manager

    P->>TP: Enter Trading Post
    TP->>S: Get available quests
    S->>Q: Filter by prerequisites
    Q->>S: Available quest list
    S->>P: Display quests

    P->>S: Accept quest
    S->>Q: Add to active_quests
    Q->>S: Quest started
    S->>P: Quest accepted message

    loop Gameplay
        P->>S: Kill monster / Move
        S->>Q: check_kill_progress() / check_exploration_progress()
        Q->>S: Progress update
        S->>P: quest_progress message
    end

    Note over P,Q: Quest objectives complete

    P->>TP: Return to origin post
    TP->>S: Turn in quest
    S->>Q: Complete quest
    Q->>S: Calculate rewards
    S->>P: XP, Gold, Gems awarded
```

## Quest Data Structure

```json
{
  "id": "haven_first_steps",
  "name": "First Steps",
  "description": "Defeat your first monster.",
  "type": 0,
  "trading_post": "haven",
  "target": 1,
  "rewards": {
    "xp": 25,
    "gold": 15,
    "gems": 0
  },
  "is_daily": false,
  "prerequisite": ""
}
```

## Active Quest Tracking

```json
{
  "quest_id": "haven_first_steps",
  "progress": 0,
  "target": 1,
  "started_at": 1706000000
}
```

## Trading Posts & Their Quests

```mermaid
graph TB
    subgraph Posts["Trading Posts"]
        HAVEN["Haven (0,10)<br/>Beginner Hub"]
        CROSS["Crossroads (0,0)<br/>Central Hub"]
        FROST["Frostgate (0,-100)<br/>Northern Outpost"]
        EAST["Eastwatch (150,0)<br/>Eastern Guard"]
        WEST["Westhold (-150,0)<br/>Western Fort"]
        SOUTH["Southport (0,-150)<br/>Southern Port"]
        SHADOW["Shadowmere (300,300)<br/>High-Level Hub"]
        INFERNO["Inferno (-350,0)<br/>Fire Mountain"]
        VOID["Void's Edge (350,0)<br/>Dark Circle"]
        FROZEN["Frozen Reach (0,-400)<br/>Extreme North"]
    end

    HAVEN -->|"First Steps<br/>First Blood<br/>Pest Control"| BEGINNER[Beginner Quests]
    CROSS -->|"Hotzone challenges<br/>Daily quests"| MID[Mid-Level]
    FROST -->|"Boss hunts<br/>Exploration"| ADVANCED[Advanced]
    SHADOW -->|"High-level kills<br/>Rare rewards"| ENDGAME[Endgame]
```

## Quest Prerequisites

```mermaid
graph LR
    subgraph Haven["Haven Quest Chain"]
        FS[First Steps] --> FB[First Blood]
        FB --> GS[Getting Started]
        GS --> PC[Pest Control]
        PC --> SF[Stronger Foes]
        SF --> LH[Local Hero]
    end
```

## Quest Scaling System

Quests dynamically scale to player level to maintain appropriate challenge.

```mermaid
flowchart TB
    subgraph Scaling["Quest Difficulty Scaling"]
        PLAYER[Player Level] --> BASE[Base Requirements<br/>70-80% of player level]
        BASE --> PROG{Quests completed<br/>at this post?}
        PROG -->|0-2 quests| EASY[Tier 1-3<br/>Standard difficulty]
        PROG -->|3-5 quests| MED[Tier 4-6<br/>+15-30% difficulty]
        PROG -->|6+ quests| HARD[Tier 7+<br/>+45-50% difficulty]
        HARD --> PUSH[Pushes toward<br/>next Trading Post]
    end

    subgraph Progression["Progression Quests"]
        LEVEL{Player level >=<br/>next post level?} -->|Yes| GEN[Generate exploration<br/>quest to next post]
        GEN --> REWARD[Higher rewards<br/>for progression]
    end
```

### Scaling Formula

| Component | Calculation |
|-----------|-------------|
| Kill count | `5 + (tier × 2) + (level / 20)` |
| Min monster level | `player_level × 0.7 × tier_mult` |
| Hotzone distance | `30 + (tier × 20) + (level / 5)` |
| Boss level | `player_level × (1.1 + progression_mod)` |

### Tier Multipliers

| Tier | Multiplier | Description |
|------|------------|-------------|
| 1-3 | 0.8 - 1.0 | Introductory |
| 4-7 | 1.0 - 1.45 | Standard to Veteran |
| 8+ | 1.45+ | Elite challenges |

## Trading Post Progression

```mermaid
graph LR
    subgraph Progression["Recommended Level Progression"]
        H["Haven<br/>L1-10"] --> C["Crossroads<br/>L5-20"]
        C --> E["Eastwatch<br/>L15-35"]
        C --> W["Westhold<br/>L15-35"]
        C --> F["Frostgate<br/>L20-40"]
        E --> V["Void's Edge<br/>L50-80"]
        W --> I["Inferno<br/>L50-80"]
        F --> FR["Frozen Reach<br/>L70-100"]
        F --> S["Southport<br/>L30-50"]
        S --> SH["Shadowmere<br/>L80+"]
    end
```

## Reward Multipliers

| Condition | Multiplier |
|-----------|------------|
| Base | 1.0x |
| Hotzone Quest | 1.5x - 2.5x |
| Daily Quest | 1.2x |
| High-level target | Scales with level |
| Player level scaling | +2% per level |

## Character Quest Limits

```gdscript
const MAX_ACTIVE_QUESTS = 5

# Character fields
active_quests: Array        # Currently tracking
completed_quests: Array     # Permanently done (one-time)
daily_quest_cooldowns: Dict # Timestamps for daily reset
```

## Quest Progress Checking

### Kill Progress
```gdscript
func check_kill_progress(character, monster_level, location):
    for quest in character.active_quests:
        match quest.type:
            KILL_ANY:
                quest.progress += 1
            KILL_LEVEL:
                if monster_level >= quest.target:
                    quest.progress += 1
            HOTZONE_KILL:
                if is_in_hotzone(location) and within_distance(quest):
                    quest.progress += 1
```

### Exploration Progress
```gdscript
func check_exploration_progress(character, current_location, trading_post_id):
    for quest in character.active_quests:
        if quest.type == EXPLORATION:
            if quest.destination_post == trading_post_id:
                quest.progress = quest.target  # Complete
```

## UI Integration

### Quest Display Colors
- **Available:** Green `#00FF00`
- **In Progress:** Yellow `#FFFF00`
- **Complete (turn in):** Cyan `#00FFFF`
- **Daily (on cooldown):** Gray `#808080`

### Sound Effects
- Quest accepted: None (silent)
- Quest progress: None (silent)
- Quest complete: `quest_complete_player` sound (G5 → C6 chime)
- Quest turned in: Gold sound + completion message

### Action Bar at Trading Post
```
[Status] [Shop] [Quests] [Heal(Ng)] [---] [---] [---] [---] [---] [---]
```

When in quest view:
```
[Back] [---] [---] [---] [---] [---] [---] [---] [---] [---]
(Number keys 1-9 to select quests)
```
