# 09 -- Game Systems

This guide covers every game system in Phantom Badlands that is not already documented in its own dedicated chapter (combat is in `07_combat.md`, world/map is in `08_world_map.md`). For each system you will find: what it does, where its code lives, the data structures it uses, and how to modify it.

---

## Table of Contents

1. [Character System](#1-character-system)
2. [Inventory and Equipment](#2-inventory-and-equipment)
3. [Loot and Drop Tables](#3-loot-and-drop-tables)
4. [Gathering System](#4-gathering-system)
5. [Job System](#5-job-system)
6. [Crafting System](#6-crafting-system)
7. [Salvage System](#7-salvage-system)
8. [Quest System](#8-quest-system)
9. [Dungeon System](#9-dungeon-system)
10. [Companion System](#10-companion-system)
11. [Sanctuary (House) System](#11-sanctuary-house-system)
12. [Market System (Valor Economy)](#12-market-system-valor-economy)
13. [Party System](#13-party-system)
14. [Title and Rank System](#14-title-and-rank-system)
15. [NPC Encounters](#15-npc-encounters)
16. [NPC Post System](#16-npc-post-system)
17. [Building System (Player Posts)](#17-building-system-player-posts)
18. [ASCII Art System](#18-ascii-art-system)
19. [Persistence and Accounts](#19-persistence-and-accounts)

---

## 1. Character System

**Key file:** `shared/character.gd`

The `Character` class extends `Resource` and holds all player data. Every stat, item, companion, quest, and status flag lives here.

### 1.1 Primary Stats

Six base stats, set at character creation and increased on every level-up:

| Stat | Abbreviation | Role |
|------|-------------|------|
| Strength | STR | Melee damage, Warrior HP bonus, stamina pool |
| Constitution | CON | HP pool, stamina pool |
| Dexterity | DEX | Speed, energy pool, Trickster gear bonuses |
| Intelligence | INT | Spell damage, Mage HP bonus, mana pool |
| Wisdom | WIS | Mana pool, meditate effectiveness |
| Wits | WITS | Outsmarting, energy pool, Trickster HP bonus |

### 1.2 Derived Stats

Calculated by `calculate_derived_stats()`:

```gdscript
# HP: Base 50 + CON*5 + class primary bonus
max_hp = 50 + (constitution * 5) + _get_primary_stat_for_hp()

# Mana (Mage resource): INT*3 + WIS*1.5, with Elf racial +25%
max_mana = int((intelligence * 3 + wisdom * 1.5) * get_mana_multiplier())

# Stamina (Warrior resource): STR + CON
max_stamina = strength + constitution

# Energy (Trickster resource): (WITS + DEX) * 0.75
max_energy = int((wits + dexterity) * 0.75)
```

The `_get_primary_stat_for_hp()` function returns different values per class path:
- **Warriors** (Fighter, Barbarian, Paladin): `strength`
- **Mages** (Wizard, Sorcerer, Sage): `int(intelligence * 0.5)`
- **Tricksters** (Thief, Ranger, Ninja): `int(wits * 0.5)`

### 1.3 Level System

- **Level cap:** 10,000
- **XP formula:** `experience_to_next_level = int(pow(level + 1, 2.2) * 50)`
- **Stats per level:** 2.5 total, distributed by class (uses fractional accumulator)
- Level-up is handled by `gain_experience()` which loops, granting multiple levels if enough XP

```gdscript
# Fractional stat accumulator example (Fighter):
# Per level: STR +1.25, CON +0.75, DEX +0.25, WITS +0.25 = 2.5 total
stat_accumulator[stat_name] += gains.get(stat_name, 0.0)
var whole_gain = int(stat_accumulator[stat_name])
if whole_gain >= 1:
    stat_accumulator[stat_name] -= whole_gain
    # Apply whole_gain to the actual stat
```

### 1.4 Races

Nine playable races. Currently only Elf has a mechanical bonus (`+25%` mana via `get_mana_multiplier()`). The other races are cosmetic. Race names: Human, Elf, Dwarf, Orc, Halfling, Gnome, Tiefling, Dragonborn, Undead.

### 1.5 Classes

Three paths, three classes each. Each class has unique starting stats, stat growth per level, a passive ability, and an attack verb.

| Path | Classes | Primary Stat | Resource |
|------|---------|-------------|----------|
| Warrior | Fighter, Barbarian, Paladin | STR | Stamina |
| Mage | Wizard, Sorcerer, Sage | INT | Mana |
| Trickster | Thief, Ranger, Ninja | WITS | Energy |

Class passives are returned by `get_class_passive()`:

| Class | Passive | Effect |
|-------|---------|--------|
| Fighter | Tactical Discipline | -20% stamina cost, +15% defense |
| Barbarian | Blood Rage | +3% dmg per 10% HP missing (max +30%), +25% stamina cost |
| Paladin | Divine Favor | 3% max HP regen/round, +25% vs undead/demons |
| Wizard | Arcane Precision | +15% spell damage, +10% spell crit |
| Sorcerer | Chaos Magic | 25% chance double spell damage, 5% backfire |
| Sage | Mana Mastery | -25% mana cost, +50% meditate bonus |
| Thief | Backstab | +35% crit damage, +10% base crit chance |
| Ranger | Hunter's Mark | +25% vs beasts, +30% XP, +15% gathering |
| Ninja | Shadow Step | +40% flee success, no damage on flee |

### 1.6 Stat Gains Per Level

Each class gains 2.5 stat points per level, distributed as follows:

| Class | STR | CON | DEX | INT | WIS | WITS |
|-------|-----|-----|-----|-----|-----|------|
| Fighter | 1.25 | 0.75 | 0.25 | 0.0 | 0.0 | 0.25 |
| Barbarian | 1.50 | 0.75 | 0.25 | 0.0 | 0.0 | 0.0 |
| Paladin | 0.75 | 1.00 | 0.25 | 0.0 | 0.25 | 0.25 |
| Wizard | 0.0 | 0.40 | 0.25 | 1.10 | 0.75 | 0.0 |
| Sage | 0.0 | 0.50 | 0.25 | 0.75 | 1.00 | 0.0 |
| Sorcerer | 0.0 | 0.35 | 0.25 | 1.40 | 0.50 | 0.0 |
| Thief | 0.0 | 0.25 | 0.75 | 0.0 | 0.0 | 1.50 |
| Ranger | 0.25 | 0.50 | 0.75 | 0.0 | 0.0 | 1.00 |
| Ninja | 0.0 | 0.25 | 1.25 | 0.0 | 0.0 | 1.00 |

### 1.7 Status Effects

Persistent effects tracked on the character (survive between combats):

```gdscript
# Poison (ticks each combat turn)
@export var poison_active: bool = false
@export var poison_damage: int = 0
@export var poison_turns_remaining: int = 0

# Blindness (reduces vision, hides monster HP)
@export var blind_active: bool = false
@export var blind_turns_remaining: int = 0

# Cloak (universal stealth, costs 8% of max resource per movement)
@export var cloak_active: bool = false
```

### 1.8 Buffs

Two types of combat buffs:

- `active_buffs` -- array of `{type, value, duration}`, applied within a single combat
- `persistent_buffs` -- array of `{type, value, battles_remaining}`, lasts across multiple battles

### 1.9 Serialization

- `to_dict()` -- converts the full Character object to a JSON-safe dictionary for network transmission and saving
- `from_dict(data)` -- restores a Character object from a dictionary (used by save/load and server-to-client sync)

**How to add a new character field:**

1. Add the `@export var` declaration to `character.gd`
2. Add it to `to_dict()` (search for the return dictionary near line 1233)
3. Add it to `from_dict()` (search for the deserialization block near line 1370)
4. If it needs to be sent to the client, add it to the server's `_build_character_update()` in `server.gd`

### 1.10 Themed Equipment Names

Each class has a themed equipment vocabulary. An item generated as "Iron Weapon" becomes "Iron Sword" for a Fighter, "Iron Staff" for a Wizard, "Iron Bow" for a Ranger, etc. This is handled by `get_themed_item_name()` using the `CLASS_EQUIPMENT_THEMES` and `GENERIC_SLOT_NAMES` constants.

---

## 2. Inventory and Equipment

**Key files:** `shared/character.gd` (data), `client/client.gd` (display), `server/server.gd` (validation)

### 2.1 Inventory Structure

```gdscript
@export var inventory: Array = []     # Array of item dictionaries, max 40 slots
const MAX_INVENTORY_SIZE = 40
const MAX_STACK_SIZE = 99             # Consumables stack up to 99
```

Each item is a dictionary. Typical fields:

```gdscript
{
    "name": "Iron Sword",
    "type": "weapon_iron",             # Base type (determines slot + stats)
    "item_type": "weapon_iron",        # Specific subtype (may differ from type)
    "level": 15,
    "rarity": "uncommon",              # common/uncommon/rare/epic/legendary/artifact
    "tier": 2,
    "affixes": {                       # Random stat bonuses from generation
        "attack_bonus": 5,
        "prefix_name": "Sharp",
        "suffix_name": "of Might",
        "roll_quality": 0.85
    },
    "enchantments": {},                # From crafting enchantments
    "upgrades_applied": 0,             # +N from blacksmith
    "locked": false,                   # Player lock (prevents salvage/discard)
    "wear": 0,                         # Durability (0-100, higher = more worn)
    # Consumable-specific:
    "is_consumable": true,
    "quantity": 5,                     # Stack count
}
```

### 2.2 Equipment Slots

Seven equipment slots:

```gdscript
@export var equipped: Dictionary = {
    "weapon": null,    # Attack-focused: attack, strength
    "armor": null,     # Defense-focused: defense, constitution, HP
    "helm": null,      # Defense + wisdom
    "shield": null,    # HP + defense + constitution
    "boots": null,     # Speed + dexterity + defense
    "ring": null,      # Attack + dexterity + intelligence
    "amulet": null     # Mana + wisdom + wits
}
```

### 2.3 Equipment Bonus Calculation

`get_equipment_bonuses()` iterates all equipped items and calculates total bonuses. The pipeline for each item:

1. Get `effective_level` (diminishing returns above level 100 via `_get_effective_item_level()`)
2. Multiply by `rarity_mult` (from `_get_rarity_multiplier()`)
3. Apply `wear_penalty` (100% at 0 wear, 0% at 100 wear)
4. Apply slot-type multipliers (weapon gets 1.5x attack, armor gets 1.0x defense, etc.)
5. Add class-specific gear bonuses (arcane rings, warlord weapons, etc.)
6. Add affix bonuses (randomized stats from drop generation)
7. Add enchantment bonuses (from crafting table)
8. Add proc effects (from rune application)

### 2.4 Rarity Tiers

| Rarity | Color | Multiplier |
|--------|-------|------------|
| Common | White `#FFFFFF` | 1.0 |
| Uncommon | Green `#00FF00` | 1.3 |
| Rare | Blue `#0070DD` | 1.7 |
| Epic | Purple `#A335EE` | 2.2 |
| Legendary | Orange `#FF8000` | 3.0 |
| Artifact | Red `#FF0000` | 4.0 |

### 2.5 Inventory Actions

All handled in `client.gd` (display) and validated on `server.gd`:

- **Equip** -- swap item from inventory to equipped slot
- **Unequip** -- move equipped item to inventory (needs free slot)
- **Use** -- consume a consumable (potions, scrolls, tomes, home stones)
- **Inspect** -- show detailed item stats with comparison to equipped
- **Sort** -- reorder inventory by rarity, level, type, or name
- **Salvage** -- convert item to crafting materials (see Salvage System)
- **Lock/Unlock** -- toggle protection against accidental salvage/discard
- **Discard** -- permanently destroy an item

### 2.6 Item Locking

```gdscript
# On item dictionary:
item["locked"] = true   # Prevents salvage and discard
```

Locked items display a lock icon in inventory. The server rejects salvage/discard requests for locked items.

### 2.7 How to Add a New Equipment Slot

1. Add the slot key to `equipped` dictionary in `character.gd`
2. Add to `get_equipment_bonuses()` with appropriate stat multipliers
3. Add to `CLASS_EQUIPMENT_THEMES` and `GENERIC_SLOT_NAMES`
4. Update `get_item_slot_from_type()` to map new item types to the slot
5. Update `client.gd` display functions (`display_inventory()`, `display_item_details()`)
6. Update `server.gd` equip/unequip handlers
7. Add items to drop tables in `drop_tables.gd`

---

## 3. Loot and Drop Tables

**Key file:** `shared/drop_tables.gd`

### 3.1 Rarity Distribution

Per-tier rarity weights determine how likely each rarity is. Higher monster tiers skew toward rarer drops.

```gdscript
const RARITY_WEIGHTS = {
    1: {"common": 70, "uncommon": 20, "rare": 7, "epic": 2.5, "legendary": 0.45, "artifact": 0.05},
    ...
    9: {"common": 35, "uncommon": 25, "rare": 18, "epic": 12, "legendary": 7, "artifact": 3},
}
```

### 3.2 Equipment vs Consumable Split

Each tier has a percentage chance that a drop is equipment vs consumable:

```gdscript
const EQUIPMENT_DROP_CHANCE = {
    1: 55, 2: 60, 3: 55, 4: 50, 5: 50, 6: 45, 7: 45, 8: 40, 9: 35
}
```

### 3.3 Equipment Base Types

Per tier, weighted lists of equipment base types (e.g., `weapon_iron`, `armor_chain`). Defined in `EQUIPMENT_BASES`.

### 3.4 Consumable Drops

Per tier, weighted lists of consumables with fixed rarity. Includes potions, scrolls, home stones, stat tomes, mystery items. Defined in `CONSUMABLE_DROPS`.

### 3.5 Consumable Tier System

Nine consumable tiers with scaling values:

```gdscript
const CONSUMABLE_TIERS = {
    1: {"name": "Minor",      "healing": 25,  "heal_pct": 10, ...},
    2: {"name": "Lesser",     "healing": 50,  "heal_pct": 15, ...},
    ...
    9: {"name": "Primordial", "healing": 500, "heal_pct": 50, ...}
}
```

Each tier defines: healing amount, heal percentage, resource restore, buff value, forcefield value, scroll stat percentage, debuff percentages, and the level range that generates this tier.

### 3.6 How to Add a New Drop

1. Add the item to the appropriate `CONSUMABLE_DROPS` or `EQUIPMENT_BASES` tier entry
2. If it is a new consumable type, add handling in `server.gd` `_use_item()` or `_apply_consumable()`
3. Add display info in `client.gd` `_get_item_effect_description()`
4. If it is equipment, add stat bonuses in `character.gd` `get_equipment_bonuses()`

---

## 4. Gathering System

**Key files:** `shared/drop_tables.gd` (catch tables), `shared/world_system.gd` (terrain detection), `server/server.gd` (gathering handlers), `client/client.gd` (minigame UI)

### 4.1 Overview

Four gathering skills, each tied to a terrain type:

| Skill | Terrain | Detection Function | Action Bar Label |
|-------|---------|-------------------|-----------------|
| Fishing | Water tiles (`~`) | `is_water_tile()` | Fish |
| Mining | Ore deposits (mountains) | `is_ore_deposit()` | Mine |
| Logging | Dense forest | `is_dense_forest()` | Chop |
| Foraging | Any non-water, non-mountain | N/A (forage anywhere) | Forage |

### 4.2 Gathering Minigame Flow

1. Player arrives at valid terrain -- action bar slot 4 (R key) shows the gathering button
2. Player presses the button -- client enters gathering mode (`fishing_mode`, `mining_mode`, etc.)
3. **Wait phase** -- a timer counts down (random duration)
4. **Reaction phase** -- three key options appear; player must press the correct one
5. Higher tiers require more successful reactions:
   - **T1-T2:** 1 correct choice
   - **T3-T5:** 2 correct choices
   - **T6+:** 3 correct choices
6. Server validates the timing and choice, rolls on the catch table, returns the result
7. Materials are added to `character.crafting_materials`

### 4.3 Tier Scaling by Distance

- **Mining:** 9 tiers, determined by distance from origin in `world_system.gd`
- **Logging:** 6 tiers, determined by distance from origin
- **Fishing:** tier based on water type (shallow, deep, ocean)
- **Foraging:** 6 tiers, determined by distance from origin

### 4.4 Catch Tables

Defined as constants in `drop_tables.gd`:

- `FISHING_CATCHES` -- keyed by water type (`"shallow"`, `"deep"`, `"ocean"`)
- `MINING_CATCHES` -- keyed by tier (1-9)
- `LOGGING_CATCHES` -- keyed by tier (1-6)
- `FORAGING_CATCHES` -- keyed by tier (1-6)

Each entry is an array of weighted catch dictionaries:

```gdscript
{"weight": 35, "item": "copper_ore", "name": "Copper Ore", "type": "ore", "value": 8}
```

Higher skill levels give `+0.5%` weight to rare/valuable items per skill level.

### 4.5 Gathering Tools

Equipped tools improve gathering results. One tool per subtype:

```gdscript
@export var equipped_tools: Dictionary = {
    "pickaxe": {},    # Mining
    "axe": {},        # Logging
    "sickle": {},     # Foraging
    "rod": {}         # Fishing
}
```

Tools have durability (`durability`, `max_durability`) and `tool_bonuses` that modify catch quality/speed.

### 4.6 Skill Levels

Each gathering skill has its own level (1-100) and XP:

```gdscript
@export var fishing_skill: int = 1
@export var fishing_xp: int = 0
@export var mining_skill: int = 1
@export var mining_xp: int = 0
@export var logging_skill: int = 1
@export var logging_xp: int = 0
```

### 4.7 How to Add a New Gathering Type

1. Add a new catch table constant to `drop_tables.gd` (e.g., `HERBALISM_CATCHES`)
2. Add a terrain detection function to `world_system.gd`
3. Add client flag (e.g., `herbalism_mode`) and minigame handling to `client.gd`
4. Add server handler in `server.gd`
5. Add skill/XP fields to `character.gd` (and update `to_dict()`/`from_dict()`)
6. Add action bar button for the new terrain type

---

## 5. Job System

**Key file:** `shared/character.gd`

### 5.1 Overview

Players can specialize in one gathering job and one specialty job. Jobs provide bonuses and gate access to certain recipes/features.

### 5.2 Job Categories

**Gathering Jobs** (5): `mining`, `logging`, `foraging`, `soldier`, `fishing`

**Specialty Jobs** (5): `blacksmith`, `builder`, `alchemist`, `scribe`, `enchanter`

### 5.3 Job Progression

```gdscript
@export var job_levels: Dictionary = {
    "mining": 1, "logging": 1, "foraging": 1, "soldier": 1, "fishing": 1,
    "blacksmith": 1, "builder": 1, "alchemist": 1, "scribe": 1, "enchanter": 1
}
@export var job_xp: Dictionary = { ... }
const JOB_LEVEL_CAP = 100
const JOB_TRIAL_CAP = 5   # Max level without committing
```

### 5.4 Commitment System

1. All jobs start at level 1. Players can level any job to the **trial cap** (level 5) without committing.
2. At level 5, the player must **commit** to one gathering job and one specialty job.
3. After committing, only the committed job can be leveled further (up to 100).
4. Character XP tapers off at high job levels: Lv1-20 = 1.0x, Lv20-50 = 0.5x, Lv50+ = 0.2x.

```gdscript
@export var gathering_job: String = ""            # "" = uncommitted
@export var specialty_job: String = ""            # "" = uncommitted
@export var gathering_job_committed: bool = false
@export var specialty_job_committed: bool = false
```

### 5.5 Specialty Job to Crafting Link

Each specialty job maps to a crafting skill:

| Specialty Job | Crafting Skill | Station |
|--------------|---------------|---------|
| blacksmith | blacksmithing | Forge |
| alchemist | alchemy | Apothecary |
| enchanter | enchanting | Enchanting Table |
| scribe | scribing | Writing Desk |
| builder | construction | Workbench |

Defined in `character.gd` `JOB_TO_CRAFT_SKILL` and `crafting_database.gd` `STATION_SKILL_MAP`.

---

## 6. Crafting System

**Key file:** `shared/crafting_database.gd`

### 6.1 Crafting Skills

Five crafting skills, each requiring a specific station tile at an NPC post:

```gdscript
enum CraftingSkill { BLACKSMITHING, ALCHEMY, ENCHANTING, SCRIBING, CONSTRUCTION }

const SKILL_STATION_NAMES = {
    "blacksmithing": "Forge",
    "alchemy": "Apothecary",
    "enchanting": "Enchanting Table",
    "scribing": "Writing Desk",
    "construction": "Workbench"
}
```

### 6.2 Recipe Structure

Recipes are defined in the `RECIPES` constant dictionary:

```gdscript
"copper_sword": {
    "name": "Copper Sword",
    "skill": CraftingSkill.BLACKSMITHING,
    "skill_required": 1,        # Minimum crafting skill level
    "difficulty": 5,             # Affects quality roll
    "materials": {"copper_ore": 3},
    "output_type": "weapon",
    "output_slot": "weapon",
    "base_stats": {"attack": 5, "level": 5},
    "craft_time": 2.0
}
```

Recipes span all five skills and nine tiers, from Copper (T1) to Primordial (T9) equipment, plus consumables, scrolls, runes, structures, and more.

### 6.3 Quality System

Crafted item quality depends on skill level vs recipe difficulty:

```gdscript
enum CraftingQuality { FAILED, POOR, STANDARD, FINE, MASTERWORK }

const QUALITY_MULTIPLIERS = {
    CraftingQuality.FAILED: 0.0,       # Materials lost
    CraftingQuality.POOR: 0.5,         # 50% stats
    CraftingQuality.STANDARD: 1.0,     # 100% stats
    CraftingQuality.FINE: 1.25,        # 125% stats
    CraftingQuality.MASTERWORK: 1.5    # 150% stats
}
```

Quality colors: Failed (gray), Poor (white), Standard (green), Fine (blue), Masterwork (purple).

### 6.4 Crafting Challenge

An optional minigame during crafting. Each skill has 10 themed questions with 3 answer options (index 0 is always correct). Answering correctly provides a quality bonus.

```gdscript
const CRAFT_CHALLENGE_QUESTIONS = {
    "blacksmithing": [
        {"q": "The metal is cooling. What do you do?",
         "opts": ["Reheat to orange glow", "Hammer faster", "Quench it now"]},
        ...
    ],
    "alchemy": [...],
    "enchanting": [...],
    "scribing": [...],
    "construction": [...]
}
```

Auto-skip threshold: if `skill_level - difficulty >= 30`, the minigame is skipped automatically.

### 6.5 Materials System

Materials are stored in the character's `crafting_materials` dictionary:

```gdscript
@export var crafting_materials: Dictionary = {}  # {material_id: quantity}
```

All material definitions live in `crafting_database.gd` `MATERIALS` constant. Categories include:

| Category | Examples | Tiers |
|----------|---------|-------|
| Fish | Small Fish, Legendary Fish | 1-6 |
| Ore | Copper Ore through Primordial Ore | 1-9 |
| Wood | Common Wood through Worldtree Branch | 1-6 |
| Leather | Ragged Leather through Astral Weave | 1-9 |
| Herbs | Healing Herb, Phoenix Petal, Dragon Blood | 1-7 |
| Enchanting | Magic Dust through Primordial Spark | 1-8 |
| Gems | Rough Gem through Primordial Gem | 1-7 |
| Writing | Parchment, Ink, Binding Thread | 1-5 |
| Construction | Wooden Plank, Rope, Stone Block | 1 |
| Monster Parts | Various (per monster type) | 1-9 |
| Foraging | Clover through Creation Seed | 1-6 |
| Dungeon Crystals | Void Crystal, Abyssal Shard, Primordial Essence | 7-9 |

### 6.6 Upgrade and Enchantment Caps

```gdscript
const MAX_UPGRADE_LEVELS = 50           # Max +N from blacksmith
const MAX_ENCHANTMENT_TYPES = 3         # Max different enchant stats per item
const ENCHANTMENT_STAT_CAPS = {
    "attack": 60, "defense": 60, "max_hp": 200,
    "max_mana": 150, "speed": 15,
    "stamina": 50, "energy": 50,
    "strength": 20, "constitution": 20, "dexterity": 20,
    "intelligence": 20, "wisdom": 20, "wits": 20,
}
```

### 6.7 Monster Part Group System

Rune recipes use monster parts grouped by the stat they provide:

```gdscript
const PART_SUFFIX_GROUPS = {
    "attack": ["_fang", "_tooth", "_claw", "_horn", "_mandible"],
    "defense": ["_hide", "_scale", "_plate", "_chitin"],
    "hp": ["_heart"],
    "speed": ["_fin", "_gear"],
    ...
}
```

Rune tier ranges map monster tiers to rune tiers:

```gdscript
const RUNE_TIER_RANGES = {
    "minor": [1, 2],
    "greater": [3, 6],
    "supreme": [7, 9],
}
```

### 6.8 How to Add a New Recipe

1. Add the recipe to `RECIPES` in `crafting_database.gd`
2. Ensure all required materials exist in `MATERIALS`
3. If it produces a new item type, add handling in `server.gd` `_craft_item()`
4. If the output is consumable, add a use handler in `server.gd`
5. Update `client.gd` crafting display if needed

---

## 7. Salvage System

**Key files:** `shared/drop_tables.gd` (salvage logic), `shared/character.gd` (auto-salvage settings)

### 7.1 Overview

Salvaging converts unwanted items into crafting materials. The system tries to give back approximately 30-70% of what it would cost to craft the item.

### 7.2 Salvage Calculation

`get_salvage_value(item)` in `drop_tables.gd`:

1. **Recipe match** -- if the item name matches a recipe, use that recipe's materials
2. **Equipment template** -- if no recipe match, estimate based on slot + tier
3. **Affix materials** -- add materials for each stat bonus (affixes, enchantments, proc effects)
4. **Upgrade materials** -- add materials for applied upgrades
5. **Rarity multiplier** -- scale by rarity (Common 0.5x to Artifact 2.0x)
6. **Return rate** -- return 30-70% of the pool (randomized)

### 7.3 Tier-Based Material Resolution

The system maps item tier to specific materials:

```gdscript
const SALVAGE_ORE_TIERS = [
    "copper_ore", "iron_ore", "steel_ore", "mithril_ore",
    "adamantine_ore", "orichalcum_ore", "void_ore", "celestial_ore", "primordial_ore"
]
const SALVAGE_LEATHER_TIERS = [
    "ragged_leather", "leather_scraps", "thick_leather", "enchanted_leather",
    "wyvern_leather", "dragonhide", "void_silk", "celestial_hide", "astral_weave"
]
```

### 7.4 Auto-Salvage

Players can configure automatic salvage:

```gdscript
@export var auto_salvage_enabled: bool = false
@export var auto_salvage_max_rarity: int = 0   # 0=off, 1=common, 2=uncommon, 3=rare
@export var auto_salvage_affixes: Array = []    # Up to 2 affix names to auto-salvage regardless of rarity
```

When enabled, items at or below the configured rarity are automatically salvaged on pickup. Items matching specified affix names are also auto-salvaged regardless of rarity.

---

## 8. Quest System

**Key files:** `shared/quest_database.gd` (generation), `shared/quest_manager.gd` (tracking), `shared/trading_post_database.gd` (post locations)

### 8.1 Quest Types

```gdscript
enum QuestType {
    KILL_ANY,        # Kill X monsters of any type
    KILL_TYPE,       # Kill X of a specific monster type (legacy)
    KILL_LEVEL,      # Kill X monsters at or above a level (legacy)
    HOTZONE_KILL,    # Kill X monsters in a hotzone
    EXPLORATION,     # Visit specific coordinates
    BOSS_HUNT,       # Defeat a named bounty target
    DUNGEON_CLEAR,   # Clear a specific dungeon type
    KILL_TIER,       # Kill X monsters of tier N or higher
    RESCUE,          # Rescue NPC from dungeon
    GATHER           # Gather X materials via gathering skills
}
```

### 8.2 Dynamic Daily Generation

All quests are now dynamically generated per trading post per day (seeded by date). No static quest definitions remain. The system generates quests using the trading post's location, the date seed, and the player's level.

Quest IDs follow the format: `postid_daily_YYYYMMDD_index`

### 8.3 Quest Flow

1. Visit a trading post -- see quest board with available quests
2. Accept a quest (max 5 active quests, configurable via `MAX_ACTIVE_QUESTS`)
3. Complete the objective (kill monsters, explore, clear dungeon, etc.)
4. Return to a trading post -- turn in for rewards (XP, Valor)

### 8.4 Quest Data Structure

Active quests stored on the character:

```gdscript
@export var active_quests: Array = []
# Each entry:
{
    "quest_id": "haven_daily_20260223_0",
    "progress": 3,
    "target": 10,
    "started_at": 1740268800,
    "origin_x": 0, "origin_y": 10,
    "accumulated_intensity": 0.0,
    "kills_in_hotzone": 0,
    # Extra data stored at accept time:
    "stored_rewards": {"xp": 500, "valor": 5},
    "quest_name": "Kill 10 Goblins",
    "quest_type": 0,
    "character_name": "Hero",
    "player_level_at_accept": 15,
    "completed_at_post": 2
}
```

### 8.5 Reward Scaling

Quest rewards scale based on the trading post's area level using `pow()` scaling:

```gdscript
var base_factor = pow(BASE_LEVEL + 1, 2.2)
var area_factor = pow(area_level + 1, 2.2)
var scale_factor = area_factor / base_factor
```

This ensures quest XP keeps pace with monster XP at higher levels.

### 8.6 Progress Tracking

`quest_manager.gd` `check_kill_progress()` is called after every monster kill. It iterates all active quests and checks if the kill counts toward any of them:

- **KILL_ANY** -- always counts
- **KILL_TYPE** -- must match specific monster type (and optionally minimum level)
- **KILL_TIER** -- monster tier must be >= required tier
- **BOSS_HUNT** -- killed monster name must match bounty name
- **HOTZONE_KILL** -- must be in a hotzone within max distance of quest origin

### 8.7 Party Quest Sync

All party members progress together on kill quests. When one member kills a monster, progress updates for the entire party.

### 8.8 How to Add a New Quest Type

1. Add a new value to `QuestType` enum in `quest_database.gd`
2. Add generation logic for the new type in `_generate_quest_for_tier_scaled()`
3. Add progress tracking in `quest_manager.gd` `check_kill_progress()` or create a new progress function
4. Add turn-in validation in `quest_manager.gd` `validate_turn_in()`
5. Update `client.gd` quest display to show the new quest type properly

---

## 9. Dungeon System

**Key file:** `shared/dungeon_database.gd`

### 9.1 Overview

Dungeons are instanced PvE experiences. They appear as `D` tiles on the world map. When a player enters, they get a personal instance with multiple floors, encounters, treasure chests, and a boss.

### 9.2 Dungeon Definition

```gdscript
"goblin_caves": {
    "name": "Goblin Caves",
    "description": "A network of crude tunnels...",
    "tier": 1,
    "min_level": 1, "max_level": 10,
    "monster_pool": ["Goblin", "Giant Rat", "Kobold"],
    "boss": {
        "name": "Goblin King",
        "monster_type": "Goblin",
        "level_mult": 1.1,
        "hp_mult": 2.0,
        "attack_mult": 1.3,
        "abilities": ["Rally Minions", "Dirty Fighting"]
    },
    "boss_egg": "Goblin",
    "floors": 3,
    "grid_size": 4,
    "encounters_per_floor": 2,
    "monsters_per_floor": 3,
    "treasures_per_floor": 1,
    "egg_drops": ["Goblin", "Kobold"],
    "cooldown_hours": 4,
    "spawn_weight": 50,
    "color": "#32CD32"
}
```

### 9.3 Tile Types

```gdscript
enum TileType {
    EMPTY,      # . Walkable
    WALL,       # # Impassable
    ENTRANCE,   # E Start position
    EXIT,       # > Next floor (or escape)
    ENCOUNTER,  # ? Monster encounter
    TREASURE,   # $ Treasure chest
    BOSS,       # B Boss encounter (final floor)
    CLEARED,    # . (cleared encounter)
    RESOURCE    # & Gathering node
}
```

### 9.4 Sub-Tier Level Ranges

Each of the 9 overarching tiers spans a level range. Sub-tiers (1-8) subdivide that range for more granular difficulty:

```gdscript
const TIER_LEVEL_RANGES = {
    1: {"min": 1, "max": 12},
    2: {"min": 6, "max": 22},
    ...
    9: {"min": 5001, "max": 10000}
}
```

### 9.5 Step Pressure System

Each floor has a step limit. If the player takes too many steps, the dungeon starts collapsing:

```gdscript
const DUNGEON_STEP_LIMITS = {1: 100, 2: 95, 3: 90, 4: 85, 5: 80, 6: 75, 7: 70, 8: 65, 9: 60}
```

Boss floors get `+50%` more steps. Tracked per floor via `character.dungeon_floor_steps`.

### 9.6 Trap System

Hidden traps are placed on EMPTY tiles. Count scales with tier:

```gdscript
const TRAPS_PER_FLOOR = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3, 7: 4, 8: 4, 9: 4}
const TRAP_TYPES = ["rust", "thief", "teleport"]
```

- **Rust** -- damages equipped weapon durability
- **Thief** -- steals a random item from inventory
- **Teleport** -- teleports player to a random location on the floor

### 9.7 World Dungeons vs Player Instances

This distinction is critical:

- **World dungeons** (`_create_world_dungeon()`) are map markers (`D` tiles). They exist in `active_dungeons` with NO `owner_peer_id`. They do NOT contain actual dungeon content.
- **Player instances** (`_create_player_dungeon_instance()`) are created when a player enters a `D` tile. They have `owner_peer_id` set. Each player gets their own instance.
- When entering, `handle_dungeon_enter()` marks the world dungeon as completed and creates a personal instance.

### 9.8 Boss and Egg Drops

- Boss monsters are generated from the dungeon's `boss` definition with `hp_mult`, `attack_mult`, and special abilities
- Defeating the boss **guarantees** an egg drop of the `boss_egg` monster type
- Additional eggs can drop from treasure chests with tier-based chances

### 9.9 Cooldowns

Each dungeon type has a cooldown (`cooldown_hours`). Tracked per character:

```gdscript
@export var dungeon_cooldowns: Dictionary = {}  # {dungeon_type: timestamp_when_available}
```

### 9.10 How to Add a New Dungeon

1. Add a new entry to `DUNGEON_TYPES` in `dungeon_database.gd`
2. Set `tier`, `min_level`, `max_level`, `monster_pool`, `boss`, `floors`, `grid_size`
3. Ensure all referenced monster types exist in `monster_database.gd`
4. Set `boss_egg` and `egg_drops` for companion egg rewards
5. Set `spawn_weight` (higher = more likely to spawn on the world map)
6. The floor generation, encounter placement, and boss fight are all handled automatically

---

## 10. Companion System

**Key files:** `shared/drop_tables.gd` (abilities, eggs), `shared/character.gd` (data), `client/client.gd` (display), `client/monster_art.gd` (egg art)

### 10.1 Overview

Players collect monster companions from eggs. Companions have their own levels, abilities, and variants. One companion can be active at a time (provides combat bonuses).

### 10.2 Incubating Eggs

```gdscript
@export var incubating_eggs: Array = []
const MAX_INCUBATING_EGGS = 3

# Each egg:
{
    "egg_id": "egg_abc123",
    "monster_type": "Wolf",
    "companion_name": "Azure Wolf",
    "tier": 1,
    "steps_remaining": 500,
    "hatch_steps": 500,
    "bonuses": {},
    "obtained_at": 1740268800,
    "frozen": false,         # If true, won't hatch; can still be traded
    "variant": "Azure",
    "color": "#007FFF",
    "color2": "#FFFFFF",
    "pattern": "solid"
}
```

Eggs hatch by movement (steps). `process_egg_steps()` in `character.gd` decrements `steps_remaining` for all non-frozen eggs.

### 10.3 Egg Variants

Variants are cosmetic + stat bonuses. Defined in `drop_tables.gd` `EGG_VARIANTS`:

```gdscript
const EGG_VARIANTS = [
    # Common solids (rarity 8-10, no stat bonus)
    {"name": "Crimson", "color": "#DC143C", "pattern": "solid", "rarity": 10},
    ...
    # Rare special (+10% stats)
    {"name": "Shiny", ..., "rarity": 2},
    # Very rare (+25% stats)
    {"name": "Spectral", ..., "rarity": 1},
    # Legendary (+50% stats)
    {"name": "Prismatic", ..., "rarity": 0.5}
]
```

Stat multipliers in `character.gd` `VARIANT_STAT_MULTIPLIERS`:
- Normal/Common variants: `1.0x`
- Shiny/Radiant/Blessed/Starfall: `1.10x` (+10%)
- Spectral/Ethereal/Celestial/Bifrost: `1.25x` (+25%)
- Prismatic/Void/Cosmic: `1.50x` (+50%)

### 10.4 Collected Companions

```gdscript
@export var collected_companions: Array = []

# Each companion:
{
    "id": "comp_xyz",
    "monster_type": "Wolf",
    "name": "Shiny Wolf",
    "tier": 1,
    "bonuses": {},
    "obtained_at": 1740268800,
    "battles_fought": 42,
    "variant": "Shiny",
    "variant_color": "#FFD700",
    "level": 25,
    "xp": 1500
}
```

### 10.5 Companion Leveling

```gdscript
const COMPANION_MAX_LEVEL = 10000   # Same as player max
const COMPANION_XP_BASE = 15        # XP formula: (level+1)^2.0 * 15
```

Companions gain XP from combat. Their effective level cap matches the player's level.

### 10.6 Companion Abilities

Each monster type has three abilities defined in `COMPANION_MONSTER_ABILITIES`:

```gdscript
"Wolf": {
    "passive": {"name": "Pack Instinct", "effect": "attack", "base": 2, "scaling": 0.04, ...},
    "active": {"name": "Ambush Strike", "type": "chance", "base_chance": 12, ...},
    "threshold": {"name": "Alpha Howl", "hp_percent": 35, "effect": "attack_buff", ...}
}
```

- **Passive** -- always active, scales with level (`base + level * scaling`)
- **Active** -- chance-based, triggers in combat (unlocks at companion level 5)
- **Threshold** -- activates when player HP drops below a percentage (unlocks at companion level 15)

### 10.7 Companion Sorting

In the companions UI, players can sort by:
- Level, tier, variant (rarity value), estimated damage, name, type

Handled by `_sort_companions()` in `client.gd`.

### 10.8 Kennel and Fusion (Sanctuary)

- **Kennel (K tile):** bulk companion storage, capacity 30-500 based on upgrades
- **Fusion (F tile):** combine 3 same-type companions to get 1 higher sub-tier
  - Sub-tiers go from 1 to 8 per monster type
  - Special Tier 9 fusion: 8 mixed sub-tier-8 companions produce a random T9 companion

```gdscript
const KENNEL_CAPACITY_TABLE = [30, 50, 80, 120, 175, 250, 325, 400, 450, 500]
```

### 10.9 Companion Registration

Players can use a Home Stone (Companion) to register an active companion to their house. Registered companions survive character permadeath:

```gdscript
@export var using_registered_companion: bool = false
@export var registered_companion_slot: int = -1
```

On death, `_award_baddie_points_on_death()` calls `persistence.return_companion_to_house()`.

### 10.10 Egg Art

`monster_art.gd` `get_egg_art()` renders eggs with colored patterns. The egg art template (`EGG_ART_TEMPLATE`) is a fixed ASCII outline, filled with color based on the egg's `color`, `color2`, and `pattern` values.

Patterns include: solid, gradient, striped, middle, edge, diagonal, vertical split, checker, radial, column, band, corner, cross, wave, scatter, ring, fade.

### 10.11 How to Add a New Companion Monster

1. Add the monster type to `COMPANION_MONSTER_ABILITIES` in `drop_tables.gd`
2. Add the monster's data to `COMPANION_DATA` in `drop_tables.gd`
3. Add ASCII art for the monster in `monster_art.gd` `get_art_map()`
4. Add the monster to a dungeon's `boss_egg` or `egg_drops`
5. The egg variant system, hatching, and leveling are all automatic

---

## 11. Sanctuary (House) System

**Key files:** `server/persistence_manager.gd` (data + upgrades), `server/server.gd` (handlers), `client/client.gd` (display)

### 11.1 Overview

The Sanctuary is an account-level persistent home that survives character permadeath. Players see it after login, before character select. It serves as the roguelite progression layer.

### 11.2 Game State Flow

```
Login -> HOUSE_SCREEN (Sanctuary) -> Character Select -> Playing
```

### 11.3 Map

The Sanctuary is a 29x19 tile map with a viewport camera showing 21x9 tiles. Features include:

- **Storage** -- items stored across characters
- **Companion Kennel (K tile)** -- bulk companion storage
- **Fusion Station (F tile)** -- companion combining
- **Companion Display (C tiles)** -- registered companions visible in the house
- Dynamic tile placement from upgrades

### 11.4 Baddie Points

The meta-currency earned when a character dies. Encourages the roguelite loop: die, earn points, upgrade, new character starts stronger.

Formula in `persistence_manager.gd`:

```gdscript
func calculate_baddie_points(character: Character) -> int:
    var points = 0
    points += int(character.experience / 100)                  # 1 BP per 100 XP
    points += character.crafting_materials.get("monster_gem", 0) * 5  # 5 BP per gem
    points += int(character.monsters_killed / 10)              # 1 BP per 10 kills
    points += character.completed_quests.size() * 10           # 10 BP per quest
    # Level milestones:
    if character.level >= 10:  points += 50
    if character.level >= 25:  points += 150
    if character.level >= 50:  points += 400
    if character.level >= 100: points += 1000
    return points
```

### 11.5 House Upgrades

Defined in `HOUSE_UPGRADES` constant. Each upgrade has a max level and escalating Baddie Point costs:

| Upgrade | Effect Per Level | Max Level | Example Cost Curve |
|---------|-----------------|-----------|-------------------|
| house_size | +1 layout tier | 3 | 5K, 15K, 50K |
| storage_slots | +10 item slots | 8 | 500 to 64K |
| companion_slots | +1 companion slot | 8 | 2K to 80K |
| egg_slots | +1 egg slot | 9 | 500 to 60K |
| flee_chance | +2% flee | 5 | 1K to 20K |
| starting_valor | +50 valor | 10 | 250 to 8K |
| xp_bonus | +1% XP | 10 | 1.5K to 100K |
| gathering_bonus | +5% gathering | 4 | 800 to 12K |
| kennel_capacity | Varies (30-500) | 9 | 1K to 100K |
| hp_bonus | +5% max HP | 5 | 2K to 75K |
| resource_max | +5% max resource | 5 | 2K to 75K |
| resource_regen | +5% resource regen | 5 | 3K to 120K |
| str/con/dex/int/wis/wits_bonus | +1 stat | 10 each | 1K to 50K each |
| post_slots | +1 player post | 5 | 5K to 60K |

### 11.6 Home Stone Items

Found in tier 4-7 loot. Allow sending items from the adventure to the house:

| Home Stone | Effect |
|-----------|--------|
| `home_stone_egg` | Send one incubating egg to house storage |
| `home_stone_supplies` | Send up to 10 consumables to house storage |
| `home_stone_equipment` | Send one equipped item to house storage |
| `home_stone_companion` | Register active companion to house (survives death) |

### 11.7 House Bonuses Applied to Characters

```gdscript
@export var house_bonuses: Dictionary = {}
# Example: {flee_chance: 6, starting_valor: 200, xp_bonus: 5, gathering_bonus: 15,
#           hp_bonus: 10, str_bonus: 3, ...}
```

These bonuses are read from the house data at character creation/login and applied to the character.

### 11.8 Data Storage

Houses are stored in `user://data/houses.json` as a dictionary keyed by `account_id`. The `persistence_manager.gd` handles CRUD operations with `_safe_save()` / `_safe_load()` (includes `.bak` backup protection).

---

## 12. Market System (Valor Economy)

**Key files:** `server/persistence_manager.gd` (storage, markup), `server/server.gd` (handlers), `client/client.gd` (display)

### 12.1 Overview

Players list items at trading posts to earn Valor (the universal currency). Other players buy listed items using Valor. This creates a player-driven economy.

### 12.2 How It Works

1. Player at a trading post selects "Market"
2. Can **browse** other players' listings or **list** their own items
3. **Listing:** server calculates `base_valor` (seller receives immediately) and `markup_price` (buyer pays)
4. **Markup** is based on supply/demand at that specific trading post for that category
5. More supply at a post = higher markup for buyers

### 12.3 Categories

Equipment, Companion Eggs, Consumables, Tools, Runes, Materials, Monster Parts.

### 12.4 Bulk Operations

Players can list items in bulk:
- List all equipment at once
- List all consumables/tools at once
- List all materials at once

### 12.5 Client Variables

```gdscript
var market_mode: bool = false
var pending_market_action: String = ""  # "browse", "list_select", "list_material", "buy_confirm", "my_listings"
var market_category: String = "all"     # "all", "equipment", "egg", "consumable", "tool", "rune", "material", "monster_part"
var market_sort: String = "category"    # "category", "price_asc", "price_desc", "name", "level"
var account_valor: int = 0              # Player's current valor balance
```

### 12.6 Data Storage

Market listings stored in `user://data/market_data.json`:

```gdscript
var market_data: Dictionary = {}
# Structure: {"listings": {post_id: [listing_array]}, "next_id": 1}
```

### 12.7 How to Add a New Market Category

1. Add the category string to the market category list in `client.gd`
2. Update `_is_consumable_type()` or similar type-checking functions if needed
3. Update the market browse display to handle the new category
4. Update server-side `handle_market_list_item()` to categorize the new type

---

## 13. Party System

**Key files:** `server/server.gd` (party logic), `client/client.gd` (party display)

### 13.1 Formation

- Walk into another player to send an invite
- Both players choose Lead or Follow roles
- **Maximum 4 players per party**

### 13.2 Server-Side Data

```gdscript
var active_parties: Dictionary = {}       # party_id -> {leader, members[], created_at}
var party_membership: Dictionary = {}     # peer_id -> party_id
var pending_party_invites: Dictionary = {} # peer_id -> {from, to, timestamp}
```

### 13.3 Movement

**Snake formation:** The leader moves normally. Followers occupy the previous positions in join order. Only the leader controls movement; followers see the same map.

### 13.4 Combat Scaling

- Monster HP scales by party size (more members = tougher monsters)
- All members take turns in party combat
- Weighted targeting: monster attacks are distributed using halving redistribution
- Full XP, gold, and loot are duplicated per surviving member
- **Death in party combat:** the dead player spectates
- **Flee in party combat:** the fleeing player spectates

### 13.5 Party Dungeons

- All members enter a shared dungeon instance
- Snake movement inside the dungeon
- Party combat for encounters and boss
- **Guaranteed boss egg for each surviving member**

### 13.6 Client-Side Data

```gdscript
var in_party: bool = false
var is_party_leader: bool = false
var party_members: Array = []
var party_combat_active: bool = false
var party_waiting_for_turn: bool = false
var party_combat_spectating: bool = false
```

### 13.7 Restrictions

- Items are disabled during party combat
- Only the party leader can initiate movement
- Max 4 players per party

---

## 14. Title and Rank System

**Key file:** `shared/titles.gd`

### 14.1 Title Hierarchy

Four titles in ascending order of power:

| Title | Color | Min Level | Max Level | Requirements |
|-------|-------|-----------|-----------|-------------|
| Jarl | Silver `#C0C0C0` | 50 | 500 | Jarl's Ring + at High Seat (0,0) |
| High King | Gold `#FFD700` | 200 | 1000 | Crown of the North + at High Seat |
| Elder | Purple `#9400D3` | 1000 | -- | Auto-granted at level 1000 |
| Eternal | Cyan `#00FFFF` | 1000 | -- | Complete Eternal Pilgrimage as Elder |

### 14.2 Title Items

- **Jarl's Ring** -- 0.5% drop from level 50+ monsters
- **Unforged Crown** -- 0.2% drop from level 200+ monsters; must be taken to the Infernal Forge at Fire Mountain (-400, 0)
- **Crown of the North** -- crafted from Unforged Crown at the Infernal Forge

### 14.3 Title Abilities

Each title grants special abilities that cost Valor to use:

**Jarl Abilities:**

| Ability | Valor Cost | Effect |
|---------|-----------|--------|
| Summon | 10 | Teleport a willing player to your location |
| Tax | 20 | Take 5% of target's Valor (max 500) |
| Gift of Valor | 5% of yours | Target receives 8% of your Valor |
| Collect Tribute | 0 (1hr CD) | Collect 15% of realm treasury |

**High King Abilities:**

| Ability | Valor Cost | Effect |
|---------|-----------|--------|
| Knight | 500 + 5 gems | Grant permanent Knight status (+15% dmg, +10% market) |
| Cure | 50 | Remove all debuffs from a player |
| Exile | 100 | Teleport player 100 tiles in random direction |
| Royal Treasury | 0 (2hr CD) | Collect 30% of realm treasury |

**Elder Abilities:**

| Ability | Valor Cost | Effect |
|---------|-----------|--------|
| Heal | 100 | Restore 50% HP to another player |
| Mentor | 5,000 + 25 gems | Grant permanent Mentee status (+50% XP) to player below Lv500 |
| Seek Flame | 25 | Check Eternal Pilgrimage progress |

**Eternal Abilities:**

| Ability | Valor Cost | Effect |
|---------|-----------|--------|
| Restore | 500 | Fully heal and cure all ailments |
| Bless | 50,000 + 100 gems | Grant permanent +5 to a chosen stat |
| Smite | 1,000 + 10 gems | Curse target (25 poison, -25% damage for 10 rounds) |
| Guardian | 20,000 + 50 gems | Grant 1 permanent death save |

### 14.4 Granted Statuses

- **Knight** -- granted by High King. +15% damage, +10% market listing bonus. Permanent until King dies or knights another.
- **Mentee** -- granted by Elder. +30% XP, additional +20% XP. Can only mentor players below Lv500.

### 14.5 Abuse System

Jarl and High King titles track abuse points. Excessive use of negative abilities (targeting same player repeatedly, punching down on lower-level players, combat interference) accumulates points. Exceeding the threshold loses the title.

```gdscript
const ABUSE_SETTINGS = {
    "same_target_window": 1800,       # 30 minutes
    "same_target_points": 3,
    "level_diff_threshold": 20,
    "level_diff_points": 2,
    "combat_interference_points": 3,
    "spam_window": 600,               # 10 minutes
    "spam_threshold": 3,
    "spam_points": 2,
    "decay_rate": 1,                  # 1 point per hour
    "decay_interval": 3600
}
```

### 14.6 Eternal Pilgrimage

The path from Elder to Eternal. Six stages, completed in order:

| Stage | Name | Requirement |
|-------|------|------------|
| 1 | The Awakening | Kill 5,000 monsters |
| 2 | Trial of Blood | Defeat 1,000 Tier 8+ monsters |
| 3 | Trial of Mind | Outsmart 200 monsters |
| 4 | Trial of Wealth | Donate 50,000 Valor to the Shrine of Wealth |
| 5 | The Ember Hunt | Collect 500 Flame Embers |
| 6 | The Crucible | Complete 10 consecutive Tier 9 boss fights |

Flame Ember drop rates:

```gdscript
const EMBER_DROP_RATES = {
    "tier8": {"chance": 0.10, "min": 1, "max": 1},
    "tier9": {"chance": 0.25, "min": 1, "max": 3},
    "rare": {"chance": 1.0, "min": 2, "max": 2},
    "boss": {"chance": 1.0, "min": 5, "max": 5}
}
```

### 14.7 How to Add a New Title

1. Add entry to `TITLE_DATA` in `titles.gd` with name, color, level requirements, etc.
2. Add to `TITLE_HIERARCHY` array in order of power
3. Define abilities as a new constant (e.g., `NEW_TITLE_ABILITIES`)
4. Add case to `get_title_abilities()` match statement
5. Add server handler for claiming the title in `server.gd`
6. Update client display in `client.gd`

---

## 15. NPC Encounters

### 15.1 Merchants (Trader NPCs)

Found at NPC posts or patrolling roads. Each merchant:
- Has persistent ASCII art (hash-based via `trader_art.gd` `get_trader_art_for_id()`)
- Generates inventory based on area level
- Buys and sells items

### 15.2 Blacksmiths (B tile at NPC posts)

Located at the `B` station tile inside NPC posts:
- **Upgrade** equipment (+1, +2, ... up to +50)
- **Enchant** equipment (add stat bonuses, up to 3 types, with per-stat caps)
- Requires gold and/or materials

### 15.3 Healers (H tile at NPC posts)

Located at the `H` station tile inside NPC posts:
- Restore HP to full
- Cure debuffs (poison, blind)
- Costs gold (scales with level)

### 15.4 Legendary Adventurer (1% encounter chance)

Random overworld encounter:
- Training encounter -- teaches a random ability or gives bonus XP
- Very rare, memorable moment for the player

### 15.5 Loot Find (3% encounter chance)

Random overworld encounter:
- Treasure chest -- contains multiple items
- Loot quality based on area level

---

## 16. NPC Post System

**Key file:** `shared/npc_post_database.gd`

### 16.1 Overview

NPC posts are procedurally generated trading post compounds. They serve as safe zones with crafting stations, merchants, quest boards, and markets.

### 16.2 Generation Parameters

```gdscript
const POST_COUNT_TARGET = 18          # Total posts to generate
const POST_PLACEMENT_RADIUS = 450     # Max distance from origin
const MIN_POST_SPACING = 100          # Minimum distance between posts
```

Generation uses the world seed for deterministic placement. The first post is always "Crossroads" at (0, 0).

### 16.3 Post Structure

Each post has a main room (11-15 tiles) plus 0-3 wing rooms (5-7 tiles). Wings attach to random sides of the main room, creating varied compound shapes.

```gdscript
# Wing count distribution:
# 10% none, 30% one, 40% two, 20% three
```

### 16.4 Post Contents

Posts contain:
- **Crafting stations** -- Forge, Apothecary, Enchanting Table, Writing Desk, Workbench
- **Market** -- player listing/buying
- **Inn** -- rest and heal
- **Quest Board** -- daily quest display
- **Healer (H)** -- HP restoration
- **Blacksmith (B)** -- upgrades/enchantments

### 16.5 Post Categories

Ten visual categories for variety: haven, market, shrine, farm, mine, tower, camp, exotic, fortress, default. Category affects the ASCII art displayed (from `trading_post_art.gd`).

### 16.6 Trading Posts

In addition to NPC posts, the game has pre-defined trading posts in `trading_post_database.gd`. These define the quest board, zone levels, and progression structure:

- **Core Zone** (0-30 distance): Haven, Crossroads, South Gate, East Market, West Shrine
- **Inner Zone** (30-75 distance): Farms, mills, mines, towers, inns, bridges, temples
- **Mid Zone** (75-200 distance): Frostgate, Highland Post, and more
- **Outer Zone** (200+ distance): High-level frontier posts

---

## 17. Building System (Player Posts)

**Key files:** `server/persistence_manager.gd` (tile/post data), `server/server.gd` (building handlers)

### 17.1 Overview

Players can construct structures in the world. This requires the `post_slots` house upgrade.

### 17.2 Structure Types

- **Walls** -- block movement, create enclosures
- **Towers** -- defensive, provide vision
- **Storage** -- item storage chests
- **Inns** -- rest points for travelers

### 17.3 Player Posts (Enclosures)

Named enclosures built on the world map that function as safe zones:

- Built via building mode at valid locations
- Require `post_slots` house upgrade (max 5 posts)
- Compass hints point other players toward posts
- Posts are visible on the map as colored tiles
- All visitors can use post features

### 17.4 Data Storage

Player tiles are stored in `user://data/player_tiles.json`:

```gdscript
var player_tiles_data: Dictionary = {}  # {"tiles": {username: [{x, y, type}]}}
```

Player posts are stored in `user://data/player_posts.json`:

```gdscript
var player_posts_data: Dictionary = {}  # {"posts": {username: [{name, center_x, center_y, created_at}]}}
```

---

## 18. ASCII Art System

**Key files:** `client/monster_art.gd`, `client/trader_art.gd`, `client/trading_post_art.gd`

### 18.1 Monster Art

`monster_art.gd` contains 50+ monster designs as string arrays with BBCode color tags.

**Format:**

```gdscript
"Monster Name": ["[color=#HEXCOLOR]",
"line 1 of art",
"line 2 of art",
"[/color]"],
```

**Two size categories:**
1. **Wide art** (>50 chars per line) -- copied exactly as-is, preserve all whitespace
2. **Small art** (<=50 chars per line) -- auto-centered with border

**Font size calibration:**
All monsters target approximately 330 vertical units of screen space. The formula is `lines x font_size ~ 330`. Per-monster overrides in `FONT_SIZE_OVERRIDES`:

```gdscript
const FONT_SIZE_OVERRIDES = {
    "Cerberus": 8,      # ~42 lines x 8 = 336
    "Goblin": 6,        # ~57 lines x 6 = 342
    "Giant Rat": 5,     # ~65 lines x 5 = 325
    "Kobold": 4,        # ~78 lines x 4 = 312
    "Water Elemental": 3, # ~100 lines x 3 = 300
}
```

Default font size is 4 (`ASCII_ART_FONT_SIZE`).

**Colors by monster type:**
- Green `#00FF00` -- goblins, nature
- Brown `#8B4513` -- animals
- Gray `#808080` -- undead, golems
- Red `#FF0000` -- demons, fire
- Blue `#0070DD` -- water/ice
- Purple `#A335EE` -- magical beings

### 18.2 Egg Art

`get_egg_art()` in `monster_art.gd` renders eggs using a template system:

1. The `EGG_ART_TEMPLATE` defines the egg outline as a fixed ASCII shape
2. Each egg has `color`, `color2`, and `pattern` from its variant
3. The pattern function fills the template with the appropriate colors

Supported patterns: solid, gradient, striped, middle, edge, diagonal, vertical_split, checker, radial, column, band, corner, cross, wave, scatter, ring, fade.

### 18.3 Trader Art

`trader_art.gd` provides 21 trader designs plus a tax collector. Art is persistent per trader via a hash function:

```gdscript
# get_trader_art_for_id(hash) -- same merchant always shows same art
# get_random_trader_art() -- for one-off encounters
```

Seven color variants for variety.

### 18.4 Trading Post Art

`trading_post_art.gd` provides category-based art (haven, market, shrine, farm, mine, etc.). Uses smaller font than monsters for compact display.

### 18.5 Rendering Pipeline

Art defined as string arrays -> wrapped in BBCode color tags -> displayed in `RichTextLabel` with the appropriate font size. The client sets `game_output.add_text()` with the art content.

### 18.6 How to Add New Monster Art

1. Add the art to `get_art_map()` in `monster_art.gd`
2. Use the format: `"Name": ["[color=#HEX]", "line1", "line2", ..., "[/color]"]`
3. Add a font size override to `FONT_SIZE_OVERRIDES` targeting ~330 vertical units
4. For wide art (>50 chars): preserve exact whitespace
5. For small art (<=50 chars): the system auto-centers it

---

## 19. Persistence and Accounts

**Key file:** `server/persistence_manager.gd`

### 19.1 File-Based Storage

All server data is stored as JSON files in `user://data/`:

| File | Purpose |
|------|---------|
| `accounts.json` | Account credentials, character slots |
| `characters/` | Per-character save files |
| `leaderboard.json` | Top 100 leaderboard |
| `realm_state.json` | Global server state |
| `corpses.json` | Dead character corpses on the map |
| `houses.json` | Sanctuary data per account |
| `player_tiles.json` | Player-built tiles |
| `player_posts.json` | Player-built enclosures |
| `market_data.json` | Market listings |
| `guards.json` | NPC guard data |
| `ban_list.json` | IP ban list |

### 19.2 Safe Save/Load

All persistence uses `_safe_save()` and `_safe_load()`:

- **Save:** creates a `.bak` backup of the current file before writing the new data
- **Load:** if the main file is corrupt or missing, falls back to the `.bak` backup

### 19.3 Account System

```gdscript
# Account structure:
{
    "username": "Player1",
    "password_hash": "sha256hex...",
    "password_salt": "randomhex...",
    "created_at": 1740268800,
    "character_slots": ["Hero", "Alt"],
    "max_characters": 6,
    "is_admin": false
}
```

Password security:
- SHA-256 hash with random 32-byte salt
- Minimum 6 characters, maximum 128
- Usernames: 3-20 characters, alphanumeric + underscore only

### 19.4 Character Persistence

Characters are saved as individual JSON files:

```
user://data/characters/acc_1_hero.json
```

File path: `CHARACTERS_DIR + account_id + "_" + safe_name + ".json"`

The `save_character()` function calls `character.to_dict()` and writes the result. `load_character()` reads the file and returns the dictionary (which is later passed to `from_dict()`).

### 19.5 Security Features (v0.9.144)

Server-side protections:

| Feature | Details |
|---------|---------|
| Buffer limits | 64KB buffer cap, 32KB message cap, 10 msgs/frame per peer |
| Login brute-force | 5 attempts in 5min -> 15min lockout per IP |
| Rate limiting | Token bucket: 20 msg/s sustained, burst 30 |
| Chat limits | 500 chars max, control char stripping |
| Connection cap | 200 max total connections |
| Password policy | Min 6, max 128 characters |
| Auth requirements | Leaderboards need authentication, player list needs character |
| IP banning | `/banip <ip>` and `/unbanip <ip>` GM commands |
| Security logging | All events logged with "Security:" prefix |

### 19.6 How to Add a New Persistent Data Type

1. Add the data file constant to `persistence_manager.gd` (e.g., `const NEW_FILE = "user://data/new.json"`)
2. Add a cached data variable (e.g., `var new_data: Dictionary = {}`)
3. Add `load_new()` and `save_new()` functions using `_safe_load()` / `_safe_save()`
4. Call `load_new()` in `_ready()`
5. Add any CRUD functions needed by `server.gd`

---

## Appendix: Quick Reference -- Where to Find Things

| Want to change... | File | Location |
|-------------------|------|----------|
| A character stat | `shared/character.gd` | Export vars at top |
| Class passive abilities | `shared/character.gd` | `get_class_passive()` |
| Stat gains per level | `shared/character.gd` | `get_stat_gains_for_class()` |
| XP curve | `shared/character.gd` | `gain_experience()` -- line with `pow(level + 1, 2.2) * 50` |
| Equipment stat bonuses | `shared/character.gd` | `get_equipment_bonuses()` |
| Drop rarity weights | `shared/drop_tables.gd` | `RARITY_WEIGHTS` |
| Consumable tier values | `shared/drop_tables.gd` | `CONSUMABLE_TIERS` |
| Catch tables | `shared/drop_tables.gd` | `FISHING/MINING/LOGGING/FORAGING_CATCHES` |
| Salvage returns | `shared/drop_tables.gd` | `get_salvage_value()` |
| Crafting recipes | `shared/crafting_database.gd` | `RECIPES` |
| Enchantment caps | `shared/crafting_database.gd` | `ENCHANTMENT_STAT_CAPS`, `MAX_ENCHANTMENT_TYPES` |
| Quest generation | `shared/quest_database.gd` | `_generate_quest_for_tier_scaled()` |
| Quest progress | `shared/quest_manager.gd` | `check_kill_progress()` |
| Dungeon definitions | `shared/dungeon_database.gd` | `DUNGEON_TYPES` |
| Companion abilities | `shared/drop_tables.gd` | `COMPANION_MONSTER_ABILITIES` |
| Egg variants | `shared/drop_tables.gd` | `EGG_VARIANTS` |
| Title definitions | `shared/titles.gd` | `TITLE_DATA` |
| Title abilities | `shared/titles.gd` | `JARL/HIGH_KING/ELDER/ETERNAL_ABILITIES` |
| House upgrades | `server/persistence_manager.gd` | `HOUSE_UPGRADES` |
| Baddie Points formula | `server/persistence_manager.gd` | `calculate_baddie_points()` |
| Monster art | `client/monster_art.gd` | `get_art_map()` |
| Egg art | `client/monster_art.gd` | `get_egg_art()` |
| Trader art | `client/trader_art.gd` | `get_trader_art_for_id()` |
| NPC post generation | `shared/npc_post_database.gd` | `generate_posts()` |
| Trading post locations | `shared/trading_post_database.gd` | `TRADING_POSTS` |
| Market markup | `server/persistence_manager.gd` | `calculate_markup()` |
