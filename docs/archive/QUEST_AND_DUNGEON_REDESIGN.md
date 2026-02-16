# Quest & Dungeon System Redesign

**Status:** ALL PHASES COMPLETE (2026-02-08, v0.9.100)
**Scope:** Quest system overhaul, dungeon expansion, companion tier/fusion system, sanctuary upgrades

**Implementation Status:**
- Phase 1: Dynamic quest generation — COMPLETE (v0.9.96)
- Phase 2: New quest types (KILL_TIER, BOSS_HUNT, RESCUE) — COMPLETE (v0.9.96)
- Phase 3: Dungeon sub-tier system + companion tier scaling — COMPLETE (v0.9.97)
- Phase 4: Companion kennel + fusion station — COMPLETE (v0.9.98)
- Phase 5: (Merged into Phase 3)
- Phase 6: Trading post visual variety — COMPLETE (v0.9.99)
- Hotfix: Combat serialization + bug fix pass — COMPLETE (v0.9.100)

---

## 1. Quest System Overhaul

### 1.1 Eliminate Static Quests

Remove all hardcoded static quest definitions from `quest_database.gd`. Replace entirely with dynamic quest generation.

**Dynamic Generation Rules:**
- Quests seeded per post per day (date + post ID) for consistency across players
- Quest pool size scales with post level (starter: 3-4, mid: 5-6, endgame: 6-8)
- Quest type distribution weighted by nearby features (dungeons, hotzones, etc.)
- Progression quests remain as the exception (guided travel between posts)

### 1.2 Quest Type Changes

| Type | Status | Notes |
|------|--------|-------|
| KILL_ANY | **Keep** | Simple filler quests, "Kill X monsters" |
| KILL_TYPE | **Replace -> KILL_TIER** | "Kill X Tier N+ monsters" -- player controls this by traveling to appropriate areas |
| KILL_LEVEL | **Remove** | Redundant with KILL_TIER |
| HOTZONE_KILL | **Keep + Improve** | Add directional data, entry confirmation |
| EXPLORATION | **Keep + Improve** | Add direction + distance hints in quest log |
| BOSS_HUNT | **Rework** | Named bounty targets, spawned at specific location |
| DUNGEON_CLEAR | **Keep + Expand** | Core quest type, more dungeon variety |
| RESCUE | **New** | Rescue NPC from dungeon (see Section 4) |

### 1.3 KILL_TIER (Replacing KILL_TYPE + KILL_LEVEL)

- "Kill X Tier N+ monsters"
- Player can influence this by traveling to areas where that tier spawns
- Quest log shows: "Tier 3 monsters are commonly found 16-30 tiles from the origin"
- Simpler than KILL_TYPE (no specific monster to hunt) but more directed than KILL_ANY

### 1.4 Boss Hunt -- Named Bounty Targets

Reworked as a mini-dungeon experience on the overworld:

1. Quest provides a **named monster** with flavor: "Hunt the **Ironhide Ogre** -- last spotted near (X, Y)"
2. Named target is a **guaranteed elite/rare variant** with boosted stats
3. Target appears as a **map marker** (special symbol) at the given location -- player walks to it to engage
4. **Can spawn on trading posts** -- making some bounties easily accessible from known locations
5. Single kill to complete
6. Named monster templates per type for variety ("Ironhide", "Bloodfang", "Shadowmane", etc.)

Combines clear target + clear location (like dungeon quests).

### 1.5 Hotzone Quest Improvements

**Directional Data:**
- Quest log shows: "Hotzones have been reported X tiles to the [direction] of this post"
- Could show approximate coordinates or compass direction

**Entry Confirmation:**
- Prompt before entering a hotzone tile: "You're approaching a **Danger Zone** (Lv ~150-200). Enter? [Yes] [No]"
- Level estimate derived from distance to origin
- Flee from hotzone combat pushes player back to entry tile (prevents re-engage loop)

### 1.6 Exploration Quest Improvements

- Quest log shows direction + distance: "Frostgate lies far to the south (~100 tiles)"
- Trading post database already has coordinates -- straightforward to calculate

### 1.7 Daily Rotating Featured Quest

Each post gets a highlighted "Today's Bounty" with bonus rewards:
- Seeded by date for consistency
- Bonus multiplier on rewards (1.5x)
- Breaks the "same list every login" feeling

---

## 2. Trading Post Improvements

### 2.1 More Posts in Distant Areas

Distant posts currently have few/no quests. With fully dynamic generation this is solved -- every post auto-generates level-appropriate quests.

### 2.2 Visual Variety

- Different ASCII shapes for posts on the world map (not all identical)
- Regional themes: frost, desert, swamp, mountain, etc.
- No NPCs unless they serve a gameplay purpose

---

## 3. Dungeon Overhaul

### 3.1 Larger, Grid-Based Dungeons

Replace linear floor-by-floor with explorable grid floors:
- **Grid-based floors (20x20)** per floor
- **Rooms and corridors** with procedural layout
- **Multiple encounters per floor** -- player navigates around or through
- **Treasure rooms, dead ends** for exploration rewards
- **Stairs down** found by exploring, not automatic after a fight
- More floors than current dungeons (scaling with dungeon tier)

### 3.2 Moving Monster Encounters

Monsters are visible entities on the dungeon map that move each player turn:
- Visible on map (colored symbol or first letter of name)
- **Turn-based movement**: monsters move 1 tile when player moves 1 tile
- **Spawn rules**: No monster within 3+ tiles of floor entrance or stairs
- **Detection AI**: Wander randomly; chase player if within **3 tiles AND line of sight** (walls/corridors block detection -- monsters in the next room don't know you're there)
- **Tactical gameplay**: Player can see monsters, plan routes, avoid or engage
- Preserves player agency -- sneak past to conserve HP for boss, or clear for XP
- **Monsters move during Rest/Meditate** -- resting is not free; a wandering monster could detect you

### 3.3 Dungeon Tier System (Two-Layer)

Dungeons use a **two-layer tier system**: Overarching Tier (monster type) + Sub-tier (difficulty/companion quality).

#### Overarching Tiers (1-9): Monster Type

These match the existing 9 monster tiers and determine WHICH monsters appear in the dungeon:

| Overarching Tier | Monster Types | Distance from Origin |
|---|---|---|
| 1 | Goblin, Giant Rat, Kobold, Skeleton, Wolf | Near origin |
| 2 | Orc, Hobgoblin, Gnoll, Zombie, Giant Spider, etc. | Close |
| 3 | Ogre, Troll, Wraith, Wyvern, Minotaur, etc. | Moderate |
| 4 | Giant, Dragon Wyrmling, Demon, Vampire, etc. | Moderate-far |
| 5 | Ancient Dragon, Demon Lord, Lich, Titan, etc. | Far |
| 6 | Elemental, Iron Golem, Sphinx, Hydra, etc. | Far |
| 7 | Void Walker, World Serpent, Elder Lich, etc. | Very far |
| 8 | Cosmic Horror, Time Weaver, Death Incarnate | Near edge |
| 9 | Avatar of Chaos, The Nameless One, God Slayer, Entropy | Map edge |

- Lower overarching tiers are more frequent near (0,0)
- Higher overarching tiers are more common further from origin
- Each dungeon is themed around ONE monster type (e.g., "Goblin Stronghold", "Void Walker Rift")

#### Sub-tiers (1-8): Difficulty & Companion Egg Quality

Each dungeon instance spawns with a sub-tier (1-8) that determines:
- **Monster level range** within that overarching tier (sub-tier 1 = lowest, sub-tier 8 = highest)
- **Difficulty** of encounters
- **Rewards** (XP, gold, gems scale with sub-tier)
- **Companion egg quality** -- the egg dropped matches the sub-tier number

The sub-tier divides the overarching tier's level range into 8 segments. Example for Overarching Tier 6 (levels 101-500):
- Sub-tier 1: Levels 101-150
- Sub-tier 2: Levels 151-200
- Sub-tier 3: Levels 201-250
- Sub-tier 4: Levels 251-300
- Sub-tier 5: Levels 301-350
- Sub-tier 6: Levels 351-400
- Sub-tier 7: Levels 401-450
- Sub-tier 8: Levels 451-500

**Low-tier sub-tier splitting (RESOLVED):** All overarching tiers get all 8 sub-tiers, even when the level range is narrow. Duplicate monster levels across sub-tiers are acceptable at low tiers. The sub-tier still determines companion egg quality regardless of monster level overlap.

Example for Overarching Tier 1 (levels 1-5):
- Sub-tier 1: Level 1
- Sub-tier 2: Level 1
- Sub-tier 3: Level 2
- Sub-tier 4: Level 2-3
- Sub-tier 5: Level 3
- Sub-tier 6: Level 4
- Sub-tier 7: Level 5
- Sub-tier 8: Level 5

Even at the same monster level, higher sub-tier dungeons may have stat modifiers making encounters tougher, and the egg quality (sub-tier) is always distinct.

#### Companion Power Model

**Companion power is determined by BOTH layers:**
- **Overarching tier (monster type)** is the PRIMARY power factor -- a Void Walker (Tier 7 monster) has inherently stronger base stats and abilities than a Goblin (Tier 1 monster)
- **Sub-tier** is a SECONDARY multiplier on top of the monster's base power

**Power hierarchy examples (strongest to weakest):**

Same monster type, different sub-tiers:
```
T8 Void Walker > T7 Void Walker > ... > T1 Void Walker
```

Different monster types, same sub-tier:
```
T3 Void Walker (Tier 7) > T3 Hydra (Tier 6) > T3 Ogre (Tier 3) > T3 Goblin (Tier 1)
```

Cross-tier comparison:
```
T3 Void Walker (Tier 7) > ALL Tier 6 monsters at sub-tier 3
T1 Void Walker (Tier 7) > T8 Goblin (Tier 1)
```

**Ultimate companion:** T9 sub-tier of a Tier 9 monster (e.g., T9 Avatar of Chaos) -- only achievable through fusion of T8 Avatars of Chaos from the hardest dungeons at the highest sub-tier.

**Design implication:** Players are incentivized to push into harder overarching dungeon tiers for better monster types, not just farm high sub-tiers on easy dungeons. A T8 Goblin is still just a Goblin.

#### Sub-tier Assignment (RESOLVED: Mixed)

When a dungeon spawns in the world:
- **Base sub-tier** determined by distance within the overarching tier's zone (closer to inner edge = lower sub-tier, closer to outer edge = higher sub-tier)
- **Random variance** of +/- 1-2 sub-tiers applied on top
- Clamped to 1-8 range

This means players can roughly predict sub-tier by location, but there's variance that rewards exploration.

#### Sub-tier Visibility (RESOLVED: Visible)

Players can see both the overarching tier and sub-tier BEFORE entering a dungeon. Permadeath makes blind gambles unacceptable.

Display format: **"Goblin Stronghold (Tier 1, Sub-tier 5)"** or similar shorthand like **"Goblin Stronghold [1-5]"**

### 3.4 Dungeon Modifiers (Future)

Potential variety mechanics for repeat runs:
- "Cursed" (no healing between floors)
- "Flooded" (reduced dodge)
- "Dark" (miss chance)
- Branching paths on some floors

### 3.5 Rest/Meditate in Dungeons

- Action bar button on non-combat dungeon tiles: "Rest" / "Meditate"
- Restores some HP/mana (50% of normal regen to keep dungeons challenging)
- **Costs materials** -- consumes gathered resources (fishing/mining/logging materials) that aren't heavily used elsewhere
- **Unlimited uses** but each rest costs materials and advances monster movement
- Monsters move when player rests -- a monster could wander into detection range or stumble onto the player
- Creates risk/reward: rest to recover, but risk being found

### 3.6 Dungeon Density & Spawning

- **Many more dungeons** than current system -- players need variety to find specific monster types and sub-tiers
- **Dynamic spawn/despawn** based on player proximity (large radius)
- **Despawn grace period**: Dungeons persist for at least 5+ minutes after a player leaves the area, so they can return
- Dungeons that are actively being explored never despawn

---

## 4. Rescue Quests (New Quest Type)

Dungeon-based quests with NPC rescue objectives. Each rescue quest spawns a **separate dungeon instance** (not placed inside existing dungeons).

### 4.1 Rescue Quest Flow

1. Quest: "A [merchant/healer/blacksmith] was lost in [Dungeon Name]"
2. Quest spawns a dedicated rescue dungeon at a marked location
3. NPC is placed on a specific floor (not necessarily the last)
4. Player fights through to reach the NPC
5. On rescue, NPC offers their service as reward:
   - **Merchant**: Class-appropriate gear, high quality roll
   - **Healer**: Free full heal + cure all
   - **Blacksmith**: Free repair all + enhancement
   - **Scholar**: Bonus XP or quest unlock
   - **Companion Breeder**: Free egg or companion XP boost
6. Player can continue deeper or exit with the NPC

### 4.2 Rescue Quest Rewards

The merchant rescue is the most interesting -- a curated gear piece:
- Class-appropriate (warrior/mage/trickster gear based on player class)
- Level-scaled to player
- Higher quality floor than normal drops (guaranteed rare+ or similar)

---

## 5. Companion Tier & Fusion System

### 5.1 Companion Tiers (Sub-tier T1-T9)

Companion sub-tier determines a power multiplier applied ON TOP of the monster's inherent base stats and abilities.

- **T1-T8** obtainable from dungeons (sub-tier of the dungeon = companion sub-tier)
- **T9** is **fusion-only** -- the ultimate power level
- The monster's overarching tier determines base stats and abilities
- The companion sub-tier multiplies/enhances those base stats

**What sub-tier affects (CONFIRMED):**
- **Stat multipliers** -- significant scaling per sub-tier (attack, defense, HP, etc.)
- **Ability enhancements** -- higher sub-tiers get stronger/upgraded versions of abilities

The bonuses should be **significant enough** to drive endgame investment. Some imbalance is intentional -- rewarding player time and effort with real power, then providing harder content to challenge that power.

**OPEN QUESTION:** Exact multiplier values and ability enhancement specifics (to be determined during implementation/balancing)

### 5.2 Fusion System

**Location:** Sanctuary -- new Fusion Station interactable

**Same-Type Fusion (all tiers, T1 -> T9):**
- **3:1 ratio** -- 3 same-type, same-sub-tier companions = 1 egg of next sub-tier
- Works for ALL tier transitions including T8 -> T9
- Companion levels don't matter, only type + sub-tier
- Output egg is a **random variant**
- **Variant inheritance:** If all 3 inputs share the same variant, output guaranteed that variant

**Mixed-Type T9 Fusion (fallback path):**
- **8:1 ratio** -- 8 T8 companions of **any mix of types** = 1 **random type** T9 egg
- Variant inheritance: if all 8 share a variant, inherit it
- Provides a path to T9 for players who can't collect 3 of the same T8 type

**Fusion Math:**
- 3:1 ratio for all same-type fusions (T1->T2, T2->T3, ... T8->T9)
- Pure T1 fusion to T9: 3^8 = 6,561 T1 companions (not realistic via pure fusion)
- **Realistic path:** Farm T8 sub-tier dungeons directly, collect 3 T8 eggs of same type, fuse to T9
- **Intermediate path:** Farm T6/T7 dungeons, fuse up to T8, then 3 T8s -> T9
- **Fallback path:** Collect 8 T8 companions of any types -> random T9

### 5.3 Fusion UI Flow

1. Player walks to Fusion Station in Sanctuary
2. Select 3 companions of same type and sub-tier (or 8 mixed T8s for random T9)
3. Confirmation screen showing input companions and expected output
4. Fusion produces an egg (goes to egg storage or incubation)
5. Egg hatches into companion of next sub-tier with random (or inherited) variant

---

## 6. Sanctuary Upgrades

### 6.1 Split Storage: Items vs Companions

**Current:** Single storage chest for items + registered companions (2 slots default)

**Proposed:**
- **Storage Chest (S):** Items only (existing system, keep as-is)
- **Companion Kennel (C):** Companion storage only, much higher capacity
- **Fusion Station (F):** New interactable for companion fusion

### 6.2 Companion Kennel Capacity

Players farming for T9 companions need to store potentially hundreds of companions.

**Starting capacity:** 20 companion slots
**Upgrade cost:** Baddie Points (scales per level)
**Max capacity:** TBD -- needs to be high enough for serious fusion farming (hundreds)

**Proposed upgrade tiers:**

| Level | Capacity | Cumulative BP Cost |
|---|---|---|
| 0 (base) | 20 | 0 |
| 1 | 40 | 500 |
| 2 | 60 | 1,500 |
| 3 | 80 | 3,000 |
| 4 | 100 | 5,000 |
| 5 | 150 | 8,000 |
| 6 | 200 | 12,000 |
| 7 | 300 | 18,000 |
| 8 | 400 | 25,000 |
| 9 | 500 | 35,000 |

(Numbers are placeholder -- need balancing against actual BP earn rates)

### 6.3 Sanctuary Layout Update

Need to add Fusion Station to the house map. Current interactables:
- C = Companion Slot
- S = Storage Chest
- U = Upgrades
- D = Door

Add: F = Fusion Station

---

## 7. Implementation Priority

Rough ordering by impact and dependency:

### Phase 1: Quest System Rework
- Replace static quests with fully dynamic generation
- Replace KILL_TYPE/KILL_LEVEL with KILL_TIER
- Add direction/distance hints to quest log
- Add daily rotating featured quest
- Hotzone entry confirmation + flee-to-safety

### Phase 2: Dungeon Grid System
- Grid-based dungeon floors with rooms/corridors
- Moving monster encounters (turn-based)
- Spawn rules (no monsters near entrance)
- Larger floor counts
- Rest/Meditate action

### Phase 3: Dungeon Tier System + Companion Tiers
- Define dungeon tier level ranges (overarching + sub-tier)
- Companion sub-tier attribute system (what sub-tiers affect)
- Sub-tier-appropriate egg drops from dungeons
- Dungeon placement (lower tiers near origin, higher tiers at edges)

### Phase 4: Companion Fusion + Sanctuary
- Split sanctuary storage (items vs companions)
- Companion kennel with large capacity + BP upgrades
- Fusion Station interactable
- Fusion logic (3:1 same-type all tiers, 8:1 mixed-type for T2-9)
- Variant inheritance mechanics

### Phase 5: Rescue Quests + Boss Bounties
- Named bounty target system for Boss Hunt
- Rescue quest type with NPC on dungeon floor
- Merchant rescue gear rewards

### Phase 6: Trading Post Visual Variety
- Different ASCII shapes for posts on world map
- Regional theming

---

## Resolved Questions

1. **Low-tier sub-tier splitting** -- All 8 sub-tiers for every overarching tier. Duplicate monster levels OK at low tiers.
2. **Sub-tier assignment** -- Mixed: base from distance within zone + random variance of +/- 1-2.
3. **Sub-tier visibility** -- Visible before entering. Permadeath demands informed decisions.
4. **Companion sub-tier effects** -- Stat multipliers + ability enhancements. Should be significant to drive endgame investment. Some imbalance is intentional.
5. **Dungeon floor sizes** -- Large (20x20).
6. **Monster detection range** -- 3 tiles + line of sight (walls block detection).
7. **Rest/Meditate** -- Unlimited uses, costs gathered materials. Monsters move during rest (risk of detection).
8. **Boss Hunt spawning** -- Map marker at given location. Can spawn on trading posts.
9. **Rescue quest dungeon** -- Separate dungeon instance per quest.
10. **T8->T9 fusion** -- 3:1 same-type (consistent with all other tiers). 8:1 mixed-type fallback for random T9.
11. **Dungeon density** -- Many more dungeons. Dynamic spawn/despawn based on player proximity with 5+ minute grace period.

## Open Questions

1. **Companion kennel max capacity** -- How many slots at max upgrade?
2. **Baddie Point costs for kennel upgrades** -- Need to balance against actual BP earn rates
3. **Exact companion sub-tier multiplier values** -- How much stronger is T9 vs T1? (Implementation detail)
4. **Companion ability enhancement specifics** -- Do abilities get new effects at higher sub-tiers, or just stronger numbers?
5. **Rest/Meditate material costs** -- Which materials? How much per rest?
6. **Dungeon floor count per overarching tier** -- How many floors for T1 vs T9 dungeons?
7. **Named bounty monster templates** -- Prefix list per monster type for flavor names
