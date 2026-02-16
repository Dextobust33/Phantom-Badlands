# Phantom Badlands v0.9.126 -- Quick Reference

**Use this as context primer for new Claude sessions.**

## Project Summary

Text-based multiplayer RPG built with **Godot 4.6** / GDScript. Client-server architecture over TCP:9080. Procedural 4000x4000 tile world, 9 character classes, 8 races, turn-based combat, permadeath, and a persistent account-level Sanctuary (house) system.

---

## File Map

### Core Files

| File | Lines | Purpose |
|------|------:|---------|
| `client/client.gd` | 26300 | All client UI, networking, action bar state machine, market, gathering, crafting, dungeon, party, house screens |
| `server/server.gd` | 21550 | Message routing, game logic, combat dispatch, market, crafting, gathering, party, dungeon, persistence orchestration |
| `shared/combat_manager.gd` | 6135 | Turn-based combat engine, damage formulas, ability processing, party combat, companion combat |
| `shared/drop_tables.gd` | 4527 | Item generation, fishing/mining/logging/foraging catch tables, salvage values, valor calculation, egg definitions, companion abilities |
| `shared/crafting_database.gd` | 3472 | 5 crafting skills, recipes, materials dictionary, quality system, upgrade/enchantment caps, crafting challenge questions |
| `shared/character.gd` | 3653 | Player stats, inventory, equipment, jobs, companions, eggs, quests, titles, racial passives, dungeon/house state |
| `shared/world_system.gd` | 2136 | Procedural terrain generation, tile types, LOS raycasting, tier zones, NPC post layout building |
| `shared/dungeon_database.gd` | 1991 | Dungeon definitions (T1-T9), floor layouts, boss data, sub-tier level ranges, egg drops |
| `shared/monster_database.gd` | 1728 | 50+ monsters across 9 tiers, monster abilities, stat scaling, lethality calculation |
| `shared/quest_database.gd` | 1261 | Dynamic daily quest generation (seeded per-post per-day), quest types, reward scaling |
| `shared/trading_post_database.gd` | 1054 | Static trading post definitions (core zone through frontier), coordinates, quest givers |
| `shared/quest_manager.gd` | 563 | Quest acceptance validation, progress tracking, turn-in logic, party quest sync |
| `shared/titles.gd` | 444 | Title hierarchy (Jarl, High King, Elder, Eternal), abuse tracking, pilgrimage stages |
| `shared/chunk_manager.gd` | 438 | 32x32 chunk system, delta JSON persistence, depleted node tracking, geological events |
| `shared/npc_post_database.gd` | 224 | Procedural NPC post placement (~18 posts from seed), naming, category assignment |

### Client Art & UI

| File | Lines | Purpose |
|------|------:|---------|
| `client/monster_art.gd` | 5651 | ASCII art for all monsters, egg art templates with patterns/colors, companion display names |
| `client/trader_art.gd` | 2130 | ASCII art for wandering traders (blacksmith, healer, tax collector) |
| `client/trading_post_art.gd` | 316 | Trading post ASCII art by category (haven, market, shrine, farm, etc.) |

### Server Infrastructure

| File | Lines | Purpose |
|------|------:|---------|
| `server/persistence_manager.gd` | 1679 | SQLite/JSON persistence: accounts, characters, houses, market listings, player posts, corpses, guards |
| `server/balance_config.json` | 108 | Lethality weights, ability modifiers, combat tuning knobs |

### Shared Utilities

| File | Lines | Purpose |
|------|------:|---------|
| `shared/constants.gd` | ~220 | Network config, class/race enums, ability definitions, UI color constants |

### Tools

| File | Lines | Purpose |
|------|------:|---------|
| `tools/combat_simulator/simulator.gd` | 582 | Main entry point for headless balance simulation |
| `tools/combat_simulator/combat_engine.gd` | 2055 | Ports damage formulas from combat_manager.gd for simulation |
| `tools/combat_simulator/simulated_character.gd` | 546 | Lightweight character for simulation (stats, equipment, racial passives) |
| `tools/combat_simulator/gear_generator.gd` | 395 | Generates level-appropriate equipment sets (poor/average/good) |
| `tools/combat_simulator/results_writer.gd` | 525 | JSON and Markdown output generation |

---

## Running the Game

```bash
# Server (run first, background)
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" server/server.tscn &

# Client (run second)
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "C:\Users\Dexto\Documents\phantasia-revival" client/client.tscn &
```

**Validate GDScript:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --check-only --script "res://shared/character.gd" 2>&1
```

---

## All Current Systems

### Classes (9)

Three paths, three classes each. Each path uses a different resource.

| Path | Resource | Classes | Stat Focus |
|------|----------|---------|------------|
| Warrior | Stamina (STR*4 + CON*4) | Fighter, Barbarian, Paladin | STR, CON |
| Mage | Mana (INT-based) | Wizard, Sorcerer, Sage | INT, WIS |
| Trickster | Energy (WITS*4 + DEX*4) | Thief, Ranger, Ninja | WITS, DEX |

**Class Passives:**

| Class | Passive |
|-------|---------|
| Fighter | Tactical Discipline: -20% stamina costs, +15% defense |
| Barbarian | Blood Rage: +3% damage per 10% HP missing (max +30%), abilities cost 25% more |
| Paladin | Divine Favor: Heal 3% max HP/round, +25% damage vs undead/demons |
| Wizard | Arcane Precision: +15% spell damage, +10% spell crit |
| Sorcerer | Chaos Magic: 25% chance double spell damage, 5% backfire |
| Sage | Mana Mastery: -25% mana costs, Meditate restores 50% more |
| Thief | Backstab: +50% crit damage, +15% base crit chance |
| Ranger | Hunter's Mark: +25% damage vs beasts, +30% Valor/XP from kills |
| Ninja | Shadow Step: +40% flee success, take no damage when fleeing |

**Note:** Paladin, Sorcerer, and Ninja are legacy classes -- no longer available for new characters but existing characters keep them.

**Universal Resource Bonuses:** Equipment resource stats convert to your class's primary resource. Mana affixes are 2x larger, so mana-to-stamina/energy converts at 0.5x.

### Races (8)

| Race | Passive |
|------|---------|
| Human | +10% XP from all sources |
| Elf | 50% reduced poison damage, +20% magic resistance, +25% mana pool |
| Dwarf | 34% chance to survive lethal damage with 1 HP (once per combat) |
| Ogre | All healing effects doubled |
| Halfling | +10% dodge chance, +15% Valor from market listings |
| Orc | +20% damage when below 50% HP |
| Gnome | All ability costs reduced by 15% |
| Undead | Immune to death curses, poison heals instead of damaging |

### Combat

Turn-based. Encounter triggered by moving through the world. Initiative: if monster speed > player DEX, up to 40% chance monster strikes first.

**Flow:** Encounter -> Initiative Check -> [Monster First?] -> Player Turn -> Monster Turn -> Repeat until victory/defeat/flee.

**Abilities per path:**

| Warrior (Stamina) | Mage (Mana) | Trickster (Energy) |
|--------------------|-------------|---------------------|
| Power Strike (Lv1) | Magic Bolt (Lv1) | Analyze (Lv1) |
| War Cry (Lv10) | Shield (Lv10) | Distract (Lv10) |
| Shield Bash (Lv25) | Cloak (Lv25) | Pickpocket (Lv25) |
| Cleave (Lv40) | Blast (Lv40) | Ambush (Lv40) |
| Berserk (Lv60) | Forcefield (Lv60) | Gambit (Lv50) |
| Iron Skin (Lv80) | Teleport (Lv80) | Vanish (Lv60) |
| Devastate (Lv100) | Meteor (Lv100) | Exploit (Lv80) |
| | | Perfect Heist (Lv100) |

**Universal ability:** All or Nothing (escalating success chance with uses).

**Equipment slots:** weapon, armor, helm, shield, boots, ring, amulet (7 slots). Each class sees themed names (e.g., Ranger sees "Bow" for weapon, "Quiver" for shield).

**Consumables:** Health potions, resource potions, scrolls (forcefield, rage, stone skin, haste, vampirism, thorns, precision, time stop, resurrect), bane potions. 9 tiers of consumable power.

**Companion combat:** Active companion fights alongside player with passive bonuses, active abilities (chance-based), and threshold triggers (activate below HP%).

### Gathering (4 types + fishing)

All gathering uses a unified 3-choice minigame. Walk to a resource node, press contextual action button, pick correctly to receive materials.

| Type | Node Tiles | Tiers | Key Resource Examples |
|------|-----------|-------|----------------------|
| Fishing | Water (~) | shallow/deep | Fish, seaweed, pearls |
| Mining | Ore vein (*) | 1-9 (by distance) | Copper through Primordial Ore |
| Logging | Tree (T) | 1-6 (by distance) | Pine through Darkwood |
| Foraging | Herb/flower/mushroom/bush/reed | 1-6 (by distance) | Clover through Voidpetal |

**Momentum:** Logging has a momentum system -- consecutive correct picks grant bonus materials at milestones (3, 5, 7 correct). At momentum 7, chance for next-tier material.

**Gathering Tools:** Equipped per subtype (pickaxe, axe, sickle, rod). Crafted via construction skill. Provide bonus success, durability, and yield.

**Gathering Skills:** Each gathering type has a skill level (1-100) that improves catch quality and success rates.

### Jobs (10)

Two categories, each allows one committed specialization:

| Gathering Jobs (pick 1) | Specialty Jobs (pick 1) |
|--------------------------|-------------------------|
| Mining | Blacksmith |
| Logging | Builder (construction) |
| Foraging | Alchemist |
| Soldier (harvest monster parts) | Scribe |
| Fishing | Enchanter |

Jobs level from 1-100. Trial cap of 5 levels before commitment required. Each job has a corresponding skill that provides bonuses when actively using that profession.

**Soldier job:** Post-combat harvest minigame. After killing a monster, press Harvest to extract bonus monster parts (3-choice minigame). Harvest mastery improves per monster type.

### Crafting (5 skills)

| Skill | Station | Products |
|-------|---------|----------|
| Blacksmithing | Forge (F) | Weapons, armor, equipment upgrades |
| Alchemy | Apothecary (A) | Potions, consumables, elixirs |
| Enchanting | Enchanting Table (E) | Runes, enchantments, affixes, proc effects |
| Scribing | Writing Desk (S) | Scrolls, maps, tomes, bestiary pages |
| Construction | Workbench (W) | Gathering tools, structures, player posts |

**Quality system:** Failed (lost materials) -> Poor (50% stats) -> Standard (100%) -> Fine (125%) -> Masterwork (150%).

**Crafting challenge minigame:** 3-choice knowledge questions per craft. Score (0-3 correct) influences quality roll. Auto-skip if skill exceeds difficulty by 30+.

**Specialist-only recipes:** Committed blacksmiths, alchemists, enchanters, scribes get exclusive high-tier recipes.

**Caps:** Max +50 upgrade levels per item. Max 3 enchantment types per item. Per-stat enchantment caps (ATK/DEF: 60, HP: 200, mana: 150, speed: 15, stats: 20).

### Monsters (9 Tiers, 50+ Types)

| Tier | Level Range | Example Monsters |
|------|-------------|-----------------|
| 1 | 1-5 | Goblin, Giant Rat, Kobold, Skeleton, Wolf |
| 2 | 6-15 | Orc, Hobgoblin, Gnoll, Zombie, Giant Spider, Wight, Siren, Kelpie, Mimic |
| 3 | 16-30 | Ogre, Troll, Wraith, Wyvern, Minotaur, Gargoyle, Harpy, Shrieker |
| 4 | 31-50 | Giant, Dragon Wyrmling, Demon, Vampire, Gryphon, Chimaera, Succubus |
| 5 | 51-100 | Ancient Dragon, Demon Lord, Lich, Titan, Balrog, Cerberus, Jabberwock |
| 6 | 101-500 | Elemental, Iron Golem, Sphinx, Hydra, Phoenix, Nazgul |
| 7 | 501-2000 | Void Walker, World Serpent, Elder Lich, Primordial Dragon |
| 8 | 2001-5000 | Cosmic Horror, Time Weaver, Death Incarnate |
| 9 | 5001-10000 | Avatar of Chaos, The Nameless One, God Slayer, Entropy |

**Monster abilities (30+):** glass_cannon, multi_strike, poison, mana_drain, regeneration, damage_reflect, ethereal, armored, summoner, pack_leader, enrage, berserker, life_steal, corrosive, sunder, blind, bleed, charm, disguise, xp_steal, item_steal, and more.

**Class affinity:** Monsters have NEUTRAL, PHYSICAL (weak to warriors), MAGICAL (weak to mages), or CUNNING (weak to tricksters) affinities.

**Variants:** Monsters spawn with rarity variants (2% rare variant chance). Rare variants have enhanced stats.

**Monster HP Knowledge:** Players learn monster HP through combat. First encounter shows "???". After killing, known HP = total damage dealt. Future encounters reveal HP if type killed at same or higher level.

### Dungeons

Grid-based dungeon exploration with multiple floors, encounters, treasures, and a boss on the final floor.

**Sub-tier system:** Each overarching tier (1-9) has 8 sub-tiers that subdivide the level range. Dungeons scale within their tier's range.

**Key mechanics:**
- Enter via Action Bar "Dungeon" button at D tile on world map
- Navigate with directional keys (Q=N, W=S, E=W, R=E)
- Encounter tiles (?), Treasure tiles ($), Boss tile (B)
- Boss kill guarantees a companion egg of the boss monster type
- Cooldown per dungeon type (4-24 hours depending on tier)
- Party dungeons: all members enter shared instance with snake movement

**Dungeon examples:** Goblin Caves (T1), Wolf Den (T1), and many more through T9.

### Companions

Egg-based companion system. Companions fight alongside the player in combat.

**Lifecycle:** Monster drop/dungeon boss/fishing -> Egg (incubate via walking) -> Hatch -> Companion (level via combat XP).

**Key mechanics:**
- Max 3 incubating eggs at a time (upgradeable via Sanctuary)
- One active companion at a time
- Companion level cap: 10000 (XP formula: `pow(level+1, 2.0) * 15`)
- Egg variants: color, pattern, rarity -- affect companion stat multipliers
- Egg freezing: pause hatching progress for trading/saving
- Companion sorting: by level, tier, variant, estimated damage, name, type
- Companion trading: trade companions and eggs with other players

**Companion bonuses per monster type:** Each monster type has unique passive/active/threshold abilities (defined in `drop_tables.gd` `COMPANION_MONSTER_ABILITIES`). Examples:
- Wolf: +Attack (passive), Ambush Strike crit (active), Alpha Howl attack buff (threshold)
- Dragon: +Major attack/defense (passive), Flame Breath (active), Ancient Fury (threshold)

**Sanctuary companion features:**
- Registered companions survive character permadeath (via Home Stone)
- Companion Kennel: bulk storage (30-500 slots, upgradeable)
- Fusion Station: 3 same-type companions -> 1 higher sub-tier; 8 mixed sub-tier 8 -> random T9

### Quests

All quests are dynamically generated per-post per-day (seeded). Max 5 active quests.

| Quest Type | Description |
|------------|-------------|
| KILL_ANY | Kill X monsters of any type |
| HOTZONE_KILL | Kill X monsters near a location |
| EXPLORATION | Visit specific coordinates or another trading post |
| BOSS_HUNT | Defeat a named high-level monster |
| DUNGEON_CLEAR | Clear a specific dungeon type |
| KILL_TIER | Kill X monsters of tier N or higher |
| RESCUE | Rescue NPC from a dungeon |

**Progression quests:** Special quests that guide players between trading posts.

**Party quest sync:** Leader turn-in triggers automatic turn-in for qualifying party members. Follower exploration credit awarded when following the leader.

**Rewards:** XP, gems (crafting material), scaled by area level and player level.

### Sanctuary (House System)

Account-level persistent home that survives character permadeath. Accessible after login, before character select.

**Baddie Points (BP):** Meta-currency earned on character death. Formula:
- 1 BP per 100 XP earned, 1 BP per 500 gold, 5 BP per gem
- 1 BP per 10 monsters killed, 10 BP per completed quest
- Level milestones: +50 (Lv10), +150 (Lv25), +400 (Lv50), +1000 (Lv100)

**House upgrades (purchased with BP):**

| Upgrade | Effect | Max Level |
|---------|--------|-----------|
| House Size | Expands layout | 3 |
| Storage Slots | +10 per level | 8 |
| Companion Slots | +1 per level | 8 |
| Egg Slots | +1 per level | 9 |
| Flee Chance | +2% per level | 5 |
| Starting Valor | +50 per level | 10 |
| XP Bonus | +1% per level | 10 |
| Gathering Bonus | +5% per level | 4 |
| Kennel Capacity | 30-500 slots | 9 |
| HP Bonus | +5% max HP per level | 5 |
| Resource Max | +5% max resource per level | 5 |
| Resource Regen | +5% regen per level | 5 |
| STR/CON/DEX/INT/WIS/WITS | +1 per level | 10 each |
| Post Slots | +1 player post per level | 5 |

**Home Stones:** Found in T5-T7 loot. Types: Egg (send egg to house), Supplies (send consumables), Equipment (send equipped item), Companion (register companion to survive death).

### Valor (Currency)

Valor is the game's economy currency. Earned from monster kills (base amount scaled by tier/level), market sales, and Sanctuary starting bonus.

**Uses:**
- Listing and purchasing items on the Open Market
- Hiring guards for player posts
- Various NPC post services (blacksmith repair, healer, inn rest)

### Market (Open Market)

Player-to-player trading at NPC post market stations ($).

**Features:**
- List equipment, consumables, materials, tools, companions, eggs
- Markup pricing (seller sets price as multiplier of base valor)
- Categories: Equipment, Consumables, Materials, Tools, Companions, Eggs
- Bulk listing support (stack items)
- Buyer can browse by category, search, purchase
- Halfling racial: +15% Valor from listings

### Parties (up to 4 players)

**Formation:** Bump into another player to invite. Accept/decline. Choose lead or follow.

**Movement:** Snake movement -- leader moves, followers trail behind in join order.

**Party combat:** Monster HP scales by party size. Weighted targeting with halving redistribution. Full XP/gold/loot duplicated per survivor. Death -> spectate. Flee -> spectate.

**Party dungeons:** All members enter shared dungeon instance. Snake movement inside. Party combat for encounters/bosses. Guaranteed boss egg for each surviving member.

### Player Posts (Named Enclosures)

Player-built safe zones in the world. Other players can visit. Compass hints guide nearby players.

**Requirements:** Construction skill, post_slots house upgrade, materials.

### Titles & Trophies

**Title hierarchy (lowest to highest):** Jarl -> High King -> Elder -> Eternal.

| Title | Requirement | Notes |
|-------|-------------|-------|
| Jarl | Lv50-500, Jarl's Ring at Crossroads | Unique, tax immune, can be abused/lost |
| High King | Lv200-1000, Crown of the North at Crossroads | Unique, replaces Jarl, can knight players |
| Elder | Lv1000+, auto-granted | Multiple allowed, can mentor players |
| Eternal | Elder + Pilgrimage completion | Max 3, has 3 lives, can grant guardian death saves |

**Knight** (+15% damage, +10% market bonus) granted by High King. **Mentee** (+30% XP, +20% extra XP, max Lv500) granted by Elder.

**Trophies:** Rare drops from T8+ boss monsters (5% chance). Prestige collectibles.

### Trading Posts (NPC)

Two types of NPC posts exist in the world:

1. **Static trading posts** (defined in `trading_post_database.gd`): Haven, Crossroads, South Gate, East Market, West Shrine, and more through frontier zones.
2. **Procedural NPC posts** (generated from world seed via `npc_post_database.gd`): ~18 posts within 450 tiles of origin, minimum 100 tiles apart.

**Visual variety:** 10 post categories (haven, market, shrine, farm, mine, tower, camp, exotic, fortress, default) with distinct ASCII art and map colors.

**Standard NPC post facilities:** Crafting stations (Forge, Apothecary, Enchanting Table, Writing Desk, Workbench), Market ($), Inn (I), Quest Board (Q), Blacksmith (B), Healer (H).

### World

Procedural 4000x4000 tile world (-2000 to +2000 on each axis). Chunk-based (32x32 tiles per chunk).

**Tile types:** empty, stone, tree, ore_vein, herb, flower, mushroom, bush, reed, dense_brush, water, deep_water, wall, door, floor, path, forge, apothecary, workbench, enchant_table, writing_desk, market, inn, quest_board, blacksmith, healer, tower, storage, guard, post_marker, void.

**Vision:** Bresenham LOS raycasting, radius 11 (radius 2 when blind). Stones, trees, ore veins, and walls block line of sight.

**Resource tiers by distance from origin:** Higher tiers spawn further out. Tier colors shift for resources (e.g., ore goes copper -> silver -> gold -> blue -> purple).

**Geological events:** Random world events every 30-60 minutes that affect resource availability.

**Key locations:**
- Spawn: Haven (0, 10)
- Crossroads / High Seat: (0, 0)

### Permadeath

Characters are permanently deleted on death. No recovery (unless Dwarf Last Stand triggers, or Guardian death save is active). Earned Baddie Points go to account Sanctuary.

---

## Action Bar State Machine

The action bar (`update_action_bar()`) checks states in priority order:

1. `settings_mode`
2. `pending_trade_request`
3. `pending_summon`
4. `in_trade` (with trade tabs: Items, Companions, Eggs)
5. `wish_selection_mode`
6. `monster_select_mode`
7. `target_farm_mode`
8. `ability_mode`
9. `title_stat_selection_mode`
10. `title_mode`
11. `combat_item_mode`
12. `in_combat`
13. `flock_pending`
14. `pending_continue`
15. `at_merchant` + `pending_merchant_action`
16. `inventory_mode` + `pending_inventory_action`
17. `at_trading_post`
18. `dungeon_mode` (only when not in combat)
19. `companions_mode` / `eggs_mode`
20. `house_mode` + `pending_house_action`
21. `has_character` (normal overworld)
22. No character (login/select)

**RULE:** After changing ANY state variable, always call `update_action_bar()`.

**Slot 4 (R key) is contextual by location:**
- At water: Fish
- At ore deposit: Mine
- At dense forest: Chop
- At forageable node: Forage
- At dungeon entrance: Dungeon
- At Infernal Forge: Forge
- Otherwise: Quests

---

## Theme Colors

| Element | Color |
|---------|-------|
| Background | `#000000` |
| Default text | `#33FF33` |
| Player damage | `#FFFF00` |
| Monster damage | `#FF8800` |
| Gold / Valor | `#FFD700` |
| Gems | `#00FFFF` |
| Success | `#00FF00` |
| Error | `#FF0000` |
| XP | `#FF00FF` |
| Crafting quality: Poor | `#FFFFFF` |
| Crafting quality: Standard | `#00FF00` |
| Crafting quality: Fine | `#0070DD` |
| Crafting quality: Masterwork | `#A335EE` |

---

## Message Protocol

JSON over TCP, newline-delimited. Key message types:

| Direction | Examples |
|-----------|---------|
| Client -> Server | `move`, `combat_action`, `chat`, `market_list_item`, `crafting_request`, `house_request`, `party_invite` |
| Server -> Client | `location_update`, `combat_start`, `combat_update`, `combat_end`, `character_update`, `text`, `market_data`, `house_data` |

---

## Common Task Patterns

### Adding a New Action Bar Button

1. Find the correct state block in `update_action_bar()` (client.gd ~line 2550+).
2. Add entry to `current_actions` array (10 slots max: Space, Q, W, E, R, 1-5).
3. Add handler in `execute_local_action()` or the appropriate handler function.
4. If the button creates a new sub-state, set a `pending_*_action` variable and add the sub-state to the priority chain.
5. **CRITICAL:** If the new state uses number keys (1-5), add it to the exclusion list at ~line 1451 to prevent double-triggers with item selection.
6. **CRITICAL:** Add bypass in `character_update` handler so incoming server messages do not clear the displayed output.

### Adding a New Crafting Recipe

1. Open `shared/crafting_database.gd`.
2. Add the recipe to the appropriate `RECIPES` section with fields: `id`, `name`, `skill`, `difficulty`, `station`, `materials` (dict of material_id: quantity), `output` (item definition), and optionally `specialist_only: true`.
3. If recipe uses new materials, add them to the `MATERIALS` dictionary in `shared/crafting_database.gd`.
4. If specialist-only, the recipe will only be craftable by committed specialists of that skill.
5. Quality is determined by skill level vs difficulty + crafting challenge minigame score.

### Adding a New Monster

1. Add the enum entry to `MonsterType` in `shared/monster_database.gd` under the appropriate tier comment.
2. Add the monster to the correct tier array in `_get_tier_monsters()`.
3. Add base stats in `get_monster_base_stats()` with: name, base_hp, base_strength, base_defense, base_speed, base_intelligence, abilities array, class_affinity.
4. Add ASCII art in `client/monster_art.gd` in `get_art_map()`. Wide art (>50 chars) copy exactly; small art (<=50 chars) is auto-centered.
5. If the monster should be a companion, add companion abilities in `drop_tables.gd` `COMPANION_MONSTER_ABILITIES`.
6. If used in dungeons, add to dungeon definitions in `dungeon_database.gd`.

### Adding a New Gathering Catch

1. Open `shared/drop_tables.gd`.
2. Find the appropriate catch table: `FISHING_CATCHES`, `MINING_CATCHES`, `LOGGING_CATCHES`, or `FORAGING_CATCHES`.
3. Add an entry to the desired tier array: `{"weight": N, "item": "item_id", "name": "Display Name", "type": "category", "value": V}`.
4. Weight determines relative drop frequency within the tier. Higher weight = more common.
5. If the item is a new crafting material, also add it to `MATERIALS` in `crafting_database.gd`.
6. Tiers scale by distance from origin: T1 is closest, T6/T9 is furthest.

### Adding ASCII Art

Location: `client/monster_art.gd` in `get_art_map()`.

Format:
```gdscript
"Monster Name": ["[color=#HEXCOLOR]",
"line 1 of art",
"line 2 of art","[/color]"],
```

- **Wide art (>50 chars):** Copy exactly, preserve all whitespace.
- **Small art (<=50 chars):** Auto-centered with border, no padding needed.

---

## Gotchas

1. **Key conflicts:** Action bar slots 5-9 share keys with item selection (1-5). Every `is_item_select_key_pressed()` handler MUST call `_consume_item_select_key(i)`. See CLAUDE.md Pitfall #10.

2. **State leaks:** Always reset page variables (`sort_menu_page`, `inventory_page`, etc.) when exiting menus.

3. **Player-visible output rule:** Server messages (especially `character_update`) trigger UI refreshes that can wipe displayed results. Every new action that shows output needs a state flag and bypass in the message handler. See CLAUDE.md for full checklist.

4. **Mode exit double-trigger:** When exiting a mode via hotkey in `_input()`, mark the hotkey as pressed with `set_meta()` to prevent the action bar from also firing. See CLAUDE.md Pitfall #7.

5. **JSON float keys:** JSON stores all numbers as floats. Cast to `int()` when using numeric values from JSON as dictionary keys: `var tier = int(item.get("tier", 0))`.

6. **Serialization key names:** Always grep for key names in ALL consumer functions before choosing serialization keys. Use `.get("key", default)` instead of dot access.

7. **New commands need whitelist:** Commands must be added to BOTH `command_keywords` array (~line 8993 in client.gd) AND the `process_command()` match statement. Server commands need entries in `handle_message()`.

8. **SQLite persistence:** Uses `addons/godot-sqlite`. Character saves on logout and periodic auto-save.

9. **Action Bar First:** New features should use the Action Bar, not `/commands`. Commands can exist as fallbacks.

10. **Permadeath:** Characters are permanently deleted on death. Sanctuary (account-level) persists.

---

## Detailed Docs

See `/docs/` for in-depth documentation:
- `architecture.md` -- System overview, data flow
- `action-bar-states.md` -- Full action bar state machine
- `combat-flow.md` -- Combat system, damage formulas
- `networking-protocol.md` -- All message types, sequence diagrams
- `quest-system.md` -- Quest flow, trading posts
- `game-systems.md` -- Feature documentation (gems, trading, abilities, etc.)
