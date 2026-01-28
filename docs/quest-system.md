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

## Reward Multipliers

| Condition | Multiplier |
|-----------|------------|
| Base | 1.0x |
| Hotzone Quest | 1.5x - 2.5x |
| Daily Quest | 1.2x |
| High-level target | Scales with level |

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
