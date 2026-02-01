# Phantasia Revival: Feature Roadmap

## Completed Features (v0.9.11+)

### 5-Phase Interconnected Feature System ✅

All five phases have been implemented and are live:

```
DUNGEONS ──drops──> COMPANION EGGS ──hatch──> COMPANIONS
    │                                              │
    │ drops materials                              │ bonuses
    v                                              v
CRAFTING <────────── materials ─────────── FISHING
    │
    │ requires
    v
KILL TYPE QUESTS (track specific monsters for rewards)
```

---

## Phase 1: Kill Type Quests ✅

**Status:** Complete (v0.9.11)

Track specific monster kills for quest progress:
- New `KILL_TYPE` quest type in `quest_database.gd`
- `monster_type` field specifies which monster to kill
- Only exact monster name matches count toward progress

**Files Modified:**
- `shared/quest_database.gd` - Added KILL_TYPE enum and example quests
- `shared/quest_manager.gd` - Added KILL_TYPE case in check_kill_progress()
- `server/server.gd` - Pass monster name to quest progress check

---

## Phase 2: Companions & Eggs ✅

**Status:** Complete (v0.9.11)

Tiered companion system with eggs that hatch via gameplay:
- Every monster has a corresponding companion variant
- Companions provide stat bonuses (scale by tier T1-T9)
- Eggs hatch after walking a certain number of steps
- Companions attack alongside player in combat

**Files Modified:**
- `shared/drop_tables.gd` - Companion data, egg drops, hatching logic
- `shared/character.gd` - Companion/egg properties, hatching functions
- `server/server.gd` - Egg hatching on movement, companion combat
- `client/client.gd` - Companion display, `/companion` command

---

## Phase 3: Crafting System ✅

**Status:** Complete (v0.9.11)

Skill-based crafting with quality tiers:
- Three skills: Blacksmithing, Alchemy, Enchanting
- Quality system: Failed → Poor → Standard → Fine → Masterwork
- Trading post specialization bonuses
- Access via Action Bar at trading posts

**New Files:**
- `shared/crafting_database.gd` - Recipes, materials, skills, quality system

**Files Modified:**
- `shared/character.gd` - Crafting skill properties
- `shared/drop_tables.gd` - Crafting material drops from monsters
- `server/server.gd` - craft_list, craft_item handlers
- `client/client.gd` - Crafting UI and action bar states

---

## Phase 4: Fishing Minigame ✅

**Status:** Complete (v0.9.11)

Reaction-based fishing at water tiles:
- Wait for bite, then press correct button quickly
- Skill progression improves reaction windows and catch quality
- Catch fish, materials, and rare eggs
- Access via Action Bar "Fish" button at water tiles

**Files Modified:**
- `shared/world_system.gd` - Water tile detection
- `shared/character.gd` - Fishing skill properties
- `server/server.gd` - fish_start, fish_catch handlers
- `client/client.gd` - Fishing mode UI and timers

---

## Phase 5: Dungeon System ✅

**Status:** Complete (v0.9.12)

Procedural dungeons with exploration and boss fights:
- 6 dungeon types (T3-T8): Goblin Cave, Spider Nest, Undead Crypt, Dragon Lair, Demon Fortress, Void Sanctum
- Dungeons spawn at random world locations
- Multi-floor exploration with grid-based movement
- Encounters (monsters), Treasures (loot), Boss fights
- Dungeon-specific material and egg drops
- Access via Action Bar "Dungeon" button at entrance

**New Files:**
- `shared/dungeon_database.gd` - Dungeon definitions, floor generation, rewards

**Files Modified:**
- `shared/character.gd` - Dungeon state properties
- `server/server.gd` - Dungeon handlers, spawning, combat integration
- `client/client.gd` - Dungeon UI, floor display, action bar

---

## Future Considerations

Potential enhancements (not yet planned):
- Multiplayer co-op dungeons (party system)
- More dungeon types for higher tiers
- Crafting recipe discovery system
- Fishing tournaments
- Companion abilities/skills
- Dungeon leaderboards

---

## UI Design Principle

**Action Bar First** - All new features should be accessible via the Action Bar, not chat commands.

Slot 4 (R key) is contextual:
- At water: Fish
- At dungeon entrance: Dungeon
- At Infernal Forge: Forge
- Otherwise: Quests
