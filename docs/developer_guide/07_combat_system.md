# 07 -- Combat System

This guide covers the full combat system in Phantom Badlands: how fights start, how damage is calculated, how monster abilities work, how party combat scales, and how to modify any part of it. All combat logic runs on the server; the client renders results.

---

## Table of Contents

1. [Combat Overview](#1-combat-overview)
2. [How Combat Starts](#2-how-combat-starts)
3. [Monster Generation](#3-monster-generation)
4. [The Combat State](#4-the-combat-state)
5. [Turn Flow](#5-turn-flow)
6. [Player Actions](#6-player-actions)
7. [Damage Formulas](#7-damage-formulas)
8. [Class System and Resources](#8-class-system-and-resources)
9. [Class Abilities](#9-class-abilities)
10. [Monster Abilities](#10-monster-abilities)
11. [Party Combat](#11-party-combat)
12. [Flock Encounters](#12-flock-encounters)
13. [Dungeon Combat](#13-dungeon-combat)
14. [Combat Serialization](#14-combat-serialization)
15. [Rewards and Loot](#15-rewards-and-loot)
16. [The Known HP System](#16-the-known-hp-system)
17. [Lethality and Balance](#17-lethality-and-balance)
18. [Modifying Combat](#18-modifying-combat)

---

## 1. Combat Overview

Combat in Phantom Badlands is **turn-based** and **server-authoritative**. The client sends action choices; the server resolves every calculation and returns results.

**Key properties:**

- Each round, the player chooses an action, then the monster acts (unless stunned, charmed, or the player fled).
- Speed/initiative determines whether the monster gets a free first strike *before* the player's first turn.
- Solo combat: 1 player vs 1 monster.
- Party combat: up to 4 players vs 1 monster (HP scaled by party size).
- Dungeon combat: encounters and boss fights inside instanced dungeons.
- Flock encounters: a chain of back-to-back fights against the same monster type.

**Key source files:**

| File | Role |
|------|------|
| `shared/combat_manager.gd` | All combat logic (~6100 lines) |
| `shared/character.gd` | Player stats, equipment, class passives |
| `shared/monster_database.gd` | Monster definitions, generation, scaling |
| `shared/drop_tables.gd` | Item drops, consumable effects, salvage |
| `server/server.gd` | Encounter triggers, message routing, rewards |
| `server/balance_config.json` | Tunable weights for damage, lethality, abilities |
| `client/client.gd` | Combat display, HP bars, action bar |

---

## 2. How Combat Starts

### 2a. Movement Encounters

When a player moves, the server calls `world_system.check_encounter(x, y)`. Each terrain type has a fixed encounter rate:

| Terrain | Encounter Rate |
|---------|---------------|
| Plains | 10% |
| Forest | 20% |
| Deep Forest | 35% |
| Mountains | 30% |
| Swamp | 40% |
| Desert | 35% |
| Volcano | 60% |
| Dark Circle | 80% |
| Void | 50% |
| Water | 10% |
| Deep Water | 20% |
| Safe zones (City, Throne, Trading Post) | 0% |

Roads (path tiles) halve the encounter rate. Cloaked players skip encounter checks entirely. New players (level < 10) near the origin (distance <= 20 tiles) have encounters suppressed 50% of the time.

### 2b. Hunting

The **Hunt** action (`handle_hunt()` in `server.gd`) uses a 60% base encounter chance (80% in hotspots). If the roll fails, the player sees "You search the area but are unable to locate any monsters."

### 2c. Encounter Resolution

When an encounter triggers, `server.gd` calls `trigger_encounter(peer_id)`:

```
trigger_encounter(peer_id):
    1. Get monster level range from world_system for player's location
    2. Roll rare_roll (0-999):
       - 0-9   (1%):   Legendary Adventurer training encounter
       - 10-39 (3%):   Loot Find (free item, no combat)
       - 40+   (96%):  Normal monster combat
    3. If forced_next_monster is set (from Monster Selection Scroll), use that instead
    4. Apply pending_monster_debuffs from scrolls (weakness, vulnerability, slow, doom)
    5. Apply target_farm_ability from Scroll of Finding
    6. If party leader -> _start_party_combat_encounter()
    7. Otherwise -> combat_mgr.start_combat(peer_id, character, monster)
    8. Send "combat_start" message to client with full combat state
```

### 2d. The combat_start Message

The server sends the client:

```gdscript
{
    "type": "combat_start",
    "message": "A Level 15 Orc appears!",
    "combat_state": { ... },        # HP, stats, abilities for display
    "combat_bg_color": "#1A1A2E",   # Background color contrasting monster art
    "use_client_art": true,          # Client renders ASCII art locally
    "extra_combat_text": ""          # Scroll debuff messages, etc.
}
```

---

## 3. Monster Generation

### 3a. Monster Definitions

`monster_database.gd` defines 50+ monster types across 9 tiers via the `MonsterType` enum:

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

Each monster definition in `get_monster_base_stats()` includes:

```gdscript
{
    "name": "Goblin",
    "base_level": 2,
    "base_hp": 15,
    "base_strength": 8,
    "base_defense": 5,
    "base_speed": 22,
    "base_experience": 25,
    "flock_chance": 35,             # % chance of flock encounter
    "drop_table_id": "tier1",
    "drop_chance": 5,
    "description": "A small, green-skinned creature with sharp teeth",
    "class_affinity": ClassAffinity.CUNNING,
    "abilities": [ABILITY_PACK_LEADER, ABILITY_CUNNING_PREY],
    "death_message": "The goblin squeaks 'Not the face!' as it falls."
}
```

### 3b. The Generation Pipeline

`generate_monster(min_level, max_level)` works in three steps:

**Step 1 -- Select monster type:** `select_monster_type(level)` uses a weighted pool. The current tier has weight 100; each tier below decays exponentially (`100 / 3^tiers_below`). There is also a configurable "tier bleed" chance (default 7%) where a monster from one tier higher can appear.

**Step 2 -- Get base stats:** `get_monster_base_stats(type)` returns the template dictionary.

**Step 3 -- Scale to level:** `scale_monster_to_level(base_stats, target_level)` applies tiered scaling:

```
Stat scaling rate per level:
    Levels 1-100:    +12% per level
    Levels 101-500:  +5% per level
    Levels 501-2000: +2% per level
    Levels 2000+:    +0.5% per level
```

The function also:
- Estimates expected player equipment at this level and adjusts HP upward (hyperbolic saturation approaching 7x)
- Applies a minimum HP floor of `level * 3`
- Adds a strength bonus to account for ~30% of expected player defense
- Applies a defense bonus of `level / 10`
- Calculates intelligence for the Outsmart mechanic (tier-based, 5-65 range)
- Applies Glass Cannon (3x STR, 0.5x HP) and Armored (1.5x DEF) ability modifiers

### 3c. Variant System

After scaling, the generator rolls for rare variants:

- **4% chance: Good variant** (level >= 5) -- either "Weapon Master" (+25% STR, guarantees weapon drop) or "Shield Guardian" (+25% HP/DEF, guarantees shield drop)
- **2% chance: Dangerous variant** (level >= 10) -- either "Corrosive" (+15% HP, chance to damage equipment) or "Sundering" (+15% STR, damages weapons/shields)

### 3d. Final Monster Dictionary

The `scale_monster_to_level()` function returns:

```gdscript
{
    "name": "Corrosive Orc",         # Display name (may include variant prefix/suffix)
    "base_name": "Orc",              # Original name for art lookup
    "level": 15,
    "max_hp": 250,
    "current_hp": 250,
    "strength": 30,
    "defense": 12,
    "speed": 18,                      # Does NOT scale with level
    "intelligence": 15,               # For Outsmart mechanic
    "experience_reward": 180,
    "flock_chance": 0,
    "drop_table_id": "tier2",
    "drop_chance": 5,
    "description": "...",
    "class_affinity": 1,              # 0=Neutral, 1=Physical, 2=Magical, 3=Cunning
    "abilities": ["corrosive"],
    "death_message": "...",
    "is_rare_variant": true,
    "lethality": 425                  # Calculated by calculate_lethality()
}
```

---

## 4. The Combat State

When `start_combat()` is called, it builds a combat state dictionary stored in `active_combats[peer_id]`:

```gdscript
var combat_state = {
    # Core references
    "peer_id": peer_id,
    "character": character,         # Reference to Character object
    "monster": monster,             # The generated monster dictionary

    # Turn tracking
    "round": 1,
    "player_can_act": true,         # false if monster goes first
    "combat_log": [],
    "started_at": Time.get_ticks_msec(),
    "outsmart_failed": false,       # Can only attempt Outsmart once per fight

    # Monster ability state
    "ambusher_active": false,       # Monster's first attack crits
    "monster_went_first": false,    # For display purposes
    "cc_resistance": 0,             # Increases each time CC lands
    "enrage_stacks": 0,             # +10% damage per round (Enrage)
    "thorns_damage": 0,
    "curse_applied": false,
    "disarm_applied": false,
    "summoner_triggered": false,

    # Disguise tracking
    "disguise_active": false,
    "disguise_true_stats": {},
    "disguise_revealed": false,

    # Damage tracking (for death screen stats)
    "total_damage_dealt": 0,
    "total_damage_taken": 0,
    "player_hp_at_start": character.current_hp,

    # Trickster mechanic
    "pickpocket_count": 0,
    "pickpocket_max": randi_range(1, 3),

    # Scroll/potion buffs applied at start
    "forcefield_shield": 0,         # From Forcefield scrolls
    "lifesteal_percent": 0,         # From Lifesteal scrolls
    "player_thorns": 0,             # From Thorns scrolls
    "crit_bonus": 0,                # From Precision scrolls

    # Companion data
    "companion_abilities": {},       # Passive/active/threshold abilities
    "companion_threshold_triggered": false,
    "companion_hp_boost_applied": 0,
    "companion_resource_boost_applied": 0,
}
```

### Initiative

Initiative determines whether the monster gets a free first strike. The calculation:

```
base_initiative = 5% + (monster_speed / 50, clamped 0-1) * 20%

Bonuses:
  + Beyond-optimal zone: up to +15% if monster level far exceeds player's XP sweet spot
  + Cross-tier: +10% per tier the monster is above the player
  + Ambusher ability: +8%

Penalties:
  - DEX penalty: 2 * log2(effective_DEX / 10)

Final initiative = clamp(base - penalty, 5%, 55%)
```

If `randi() % 100 < monster_initiative_chance`, the monster goes first and `player_can_act` starts as `false`.

---

## 5. Turn Flow

### 5a. Player Turn

`process_combat_action(peer_id, action)` handles the player's turn:

```
1. Validate combat exists and player_can_act == true
2. Record monster HP and player HP before action
3. Execute the chosen action (Attack, Flee, Outsmart, or Ability)
4. Track damage dealt/taken
5. If combat ended (victory/flee) -> end_combat() and return
6. Monster's turn (if alive and didn't already act):
   a. process_monster_turn(combat)
   b. Track damage taken from monster
   c. Check if monster fled (Coward, Flee Attack, Shrieker summon)
   d. Check if player died
7. Increment round counter
8. Disguise reveal check (round >= 3)
9. Tick buff durations, report expired buffs
10. Return result dictionary with all messages
```

### 5b. Monster Turn

`process_monster_turn(combat)` handles the monster's attack:

```
1. Check stun/paralyze -> skip turn
2. Check Time Stop buff -> skip turn
3. Check companion charm -> skip turn
4. Pre-attack abilities:
   - Coward: flee at 20% HP (no loot)
   - Burn DoT tick (from Blast)
   - Bleed DoT tick (from Cleave/companions)
   - Regeneration: heal 10% HP
   - Enrage: +10% damage per round (stacks to 10)
5. Calculate monster hit chance:
   Base: 85% + level_diff
   - DEX dodge: -1% per 5 DEX (max -30%)
   - Trickster WITS dodge: -1% per 50 WITS (max -15%)
   - Speed buff: -(buff / 2)%
   - Equipment speed: -(speed / 3)%
   - Halfling racial: -10%
   - Armor rarity dodge bonuses
   - Clamp: 40% min, 95% max
6. Check protection effects (Ninja flee protection, Cloak, Distract, etc.)
7. Roll hit -> if miss, return miss message
8. Calculate damage via calculate_monster_damage()
9. Apply damage modifiers:
   - Ambusher: first hit is guaranteed crit (1.75x)
   - Berserker: +50% below 50% HP
   - Enrage stacks: +10% per stack
   - Glass Cannon: 3x damage
   - Unpredictable: wild variance (0.2x to 3x)
   - Multi-strike: 2-3 attacks
   - Forcefield absorption
   - Iron Skin reduction
   - Fortify reduction
   - Damage reflect / thorns
10. Apply special effects:
    - Poison, Bleed, Mana/Stamina/Energy drain
    - Blind, Curse, Disarm, Weakness
    - Charm, Buff Destroy, Shield Shatter
    - Corrosive/Sunder (equipment damage)
    - XP Steal, Item Steal
    - Life Steal (monster heals)
11. Check if player died
```

---

## 6. Player Actions

Each turn, the player picks one action. The `CombatAction` enum defines:

```gdscript
enum CombatAction {
    ATTACK,     # Basic attack
    FLEE,       # Attempt to escape
    SPECIAL,    # Reserved (unused)
    OUTSMART,   # WITS-based instant win attempt
    ABILITY     # Class ability (processed separately)
}
```

### Attack

`process_attack(combat)` is the most common action:

1. Apply gear-based resource regeneration
2. Mage base mana regen (2% per round, 3% for Sage)
3. Companion resource regen
4. Process monster DoTs on monster (burn, bleed from companions)
5. Process status ticks on player (poison, blind)
6. Process bleed ticks on player
7. Check charm effect (player attacks self, turn wasted)
8. Calculate hit chance: `75% + (player_DEX - monster_speed/2)`, clamped 30-95%
9. Check ethereal dodge (50% miss chance)
10. Roll hit, apply class passives (Paladin regen, companion regen)
11. On hit: calculate damage, apply analyze/vanish bonuses, proc effects
12. Trickster 25% chance for bonus attack at 50% damage
13. Apply lifesteal (scrolls, equipment, companions)
14. Apply equipment proc effects (shocking, execute, damage reflect)
15. Check if monster died -> victory processing

### Flee

`process_flee(combat)` attempts escape:

```
flee_chance = 40%
  + player DEX
  + equipment speed (boots)
  + speed buffs
  + flee bonus from gear
  + Ninja Shadow Step: +40%
  + companion bonuses
  + flock fatigue: +15% per flock member fought
  - level difference (monster above player)
  - slow aura: -25%
Clamped to 10-95%
```

On success: combat ends (no rewards). On failure: monster gets a free attack (unless Ninja, who takes no damage).

### Outsmart

`process_outsmart(combat)` is a high-risk, high-reward action:

- Can only attempt **once per combat**. If it fails, `outsmart_failed` is set.
- On success: **instant win with full rewards** (XP, loot, everything).
- On failure: monster gets a free attack, no second chance.

```
outsmart_chance = 5% base
  + WITS bonus: 18 * log2(WITS / 10)  (diminishing returns)
  + Trickster class bonus: +20%
  + Dumb monster bonus: +3% per INT below 10
  - Smart monster penalty: -1% per INT above 10
  - INT vs WITS penalty: -2% per point monster INT exceeds player WITS
  - Level difference penalty:
      1-10 levels above: -2% per level
      11-50 levels above: -20% + -1% per level
      51+ levels above: -60% + -0.5% per level
  + Level bonus for weaker monsters: up to +15%

Max cap: 85% (Tricksters) or 70% (others), reduced by monster INT/3
Final clamp: 2% to max_cap
```

### Item Use

`process_use_item(peer_id, item_index)` allows using consumables during combat:

- **Item use is a FREE ACTION** -- the player can still attack on the same turn.
- Supports health potions, resource potions, buff scrolls, elixirs, and bane potions.
- Healing scales with tier data (flat + % max HP hybrid).
- Buff scrolls apply round-based or battle-based buffs.

### Ability Use

Abilities are processed by `process_ability_command(peer_id, ability_name, arg)` and routed to path-specific handlers. See [Section 9: Class Abilities](#9-class-abilities).

---

## 7. Damage Formulas

All formula constants are configurable via `server/balance_config.json` under the `"combat"` key.

### 7a. Player -> Monster Damage

`calculate_damage(character, monster, combat)` in `combat_manager.gd`:

```
Step 1: Base damage
    base_damage = character.get_total_attack()
    # get_total_attack() = base STR + equipment STR bonus + equipment attack bonus

    For mages: base_damage = max(base_damage, INT / 5)
    base_damage += strength buff value

Step 2: STR multiplier
    str_multiplier = 1.0 + (effective_STR * 0.02)    # player_str_multiplier from config
    base_damage *= str_multiplier

Step 3: Variance
    damage = base_damage + (1d6)   # Add 1-6 random damage

Step 4: Buff multipliers
    If damage buff (War Cry, Berserk): damage *= (1 + buff_value / 100)
    If companion attack bonus: damage *= (1 + bonus / 100)

Step 5: Class passives
    Barbarian Blood Rage: +3% per 10% HP missing (max +30%)
    Orc racial: +20% when below 50% HP
    Wizard Arcane Precision: +15%
    Sorcerer Chaos Magic: 25% chance double, 5% chance backfire (halved + self-damage)

Step 6: Critical hits
    crit_chance = 5 + (DEX * 0.5) + scroll_bonus + equipment_bonus + companion_bonus
    Thief Backstab passive: +10%
    Cap: 75% (even with all bonuses)

    If critical:
        crit_multiplier = 1.5 (base)
        + Thief Backstab: +0.35
        + weapon rarity bonus
        + companion crit damage bonus
        damage *= final_crit_multiplier

Step 7: Monster defense reduction
    defense_ratio = monster_DEF / (monster_DEF + 100)    # defense_formula_constant
    damage_reduction = defense_ratio * 0.6               # defense_max_reduction (60% cap)
    damage *= (1 - damage_reduction)

Step 8: Class affinity
    Advantage (e.g., Warrior vs Physical): x1.25
    Disadvantage (e.g., Mage vs Physical): x0.85
    Neutral: x1.0

Step 9: Level penalty
    If monster level > player level:
        penalty = min(25%, level_diff * 1.5%)
        damage *= (1 - penalty)

Step 10: Conditional bonuses
    Paladin Divine Favor: +25% vs undead/demons
    Ranger Hunter's Mark: +25% vs beasts
    Monster Bane potions: +X% vs matching type
```

### 7b. Monster -> Player Damage

`calculate_monster_damage(monster, character, combat)`:

```
Step 1: Base damage
    raw_damage = monster.strength + (1d6)

Step 2: Equipment defense reduction (BEFORE defense formula)
    equipment_reduction = min(40%, equipment_defense / 400)    # equipment_defense_cap / divisor
    raw_damage *= (1 - equipment_reduction)

Step 3: Player defense formula (same formula as player->monster)
    player_defense = get_total_defense() + defense_buff + companion_defense
    Fighter passive: +15% defense bonus
    defense_ratio = player_defense / (player_defense + 100)
    damage_reduction = defense_ratio * 0.6
    damage *= (1 - damage_reduction)

Step 4: Level difference bonus (monster higher = more damage)
    If monster_level > player_level:
        multiplier = 1.035 ^ min(level_diff, 100)    # Exponential scaling
        damage *= multiplier

Step 5: Minimum damage floor
    min_damage = max(1, monster_level / 5)
    return max(min_damage, damage)
```

### 7c. Class Affinity System

Monsters have a `class_affinity` field (from the `ClassAffinity` enum):

| Affinity | Strong Against | Weak Against | Name Color |
|----------|---------------|-------------|------------|
| `NEUTRAL` (0) | Nobody | Nobody | White/Gray |
| `PHYSICAL` (1) | Mages (-15%) | Warriors (+25%) | Yellow |
| `MAGICAL` (2) | Warriors (-15%) | Mages (+25%) | Blue |
| `CUNNING` (3) | Warriors & Mages (-15%) | Tricksters (+25%) | Green |

The multiplier is applied in `_get_class_advantage_multiplier()`. Player class is mapped to a path:
- **Warrior path:** Fighter, Barbarian, Paladin
- **Mage path:** Wizard, Sorcerer, Sage
- **Trickster path:** Thief, Ranger, Ninja

---

## 8. Class System and Resources

### 8a. Three Paths, Nine Classes

Each class has a unique passive ability (defined in `character.gd` `get_class_passive()`):

**Warrior Path (Stamina):**

| Class | Passive | Effect |
|-------|---------|--------|
| Fighter | Tactical Discipline | -20% stamina costs, +15% defense |
| Barbarian | Blood Rage | +3% damage per 10% HP missing (max +30%), +25% stamina cost |
| Paladin | Divine Favor | Heal 3% max HP per round, +25% damage vs undead/demons |

**Mage Path (Mana):**

| Class | Passive | Effect |
|-------|---------|--------|
| Wizard | Arcane Precision | +15% spell damage, +10% spell crit |
| Sorcerer | Chaos Magic | 25% chance double damage, 5% chance backfire |
| Sage | Mana Mastery | -25% mana costs, Meditate restores 50% more |

**Trickster Path (Energy):**

| Class | Passive | Effect |
|-------|---------|--------|
| Thief | Backstab | +35% crit damage, +10% base crit chance |
| Ranger | Hunter's Mark | +25% vs beasts, +30% XP, +15% gathering |
| Ninja | Shadow Step | +40% flee success, no damage on failed flee |

### 8b. Resource Mechanics

- **Stamina** (Warriors): Regenerates from gear (Warlord items), rest, or consumables.
- **Mana** (Mages): Base regen of 2% per combat round (3% for Sage). Also from gear (Mystic items).
- **Energy** (Tricksters): Regenerates from gear (Shadow items) or consumables.

Resources do NOT auto-regenerate in combat (except mage base regen and gear regen). Out of combat, the Rest action restores HP and resources.

### 8c. Shared Mechanics

All trickster classes get a **25% chance for Double Strike** on basic attacks -- a bonus hit dealing 50% of the original damage.

---

## 9. Class Abilities

Abilities are defined in `_get_ability_info()` and processed by path-specific handlers. Each has a level requirement and a resource cost.

### 9a. Universal Abilities

Available to all classes:

| Ability | Level | Cost | Effect |
|---------|-------|------|--------|
| Cloak | 20 | 8% max resource | 75% chance to escape combat |
| All or Nothing | 1 | 1 resource | 3-34% chance to instant-kill, failure doubles monster STR/SPD |

### 9b. Mage Abilities (Mana)

| Ability | Level | Cost | Effect |
|---------|-------|------|--------|
| Magic Bolt | 1 | Variable | Deals `mana_spent * (1 + max(sqrt(INT)/5, INT/75))` damage |
| Forcefield | 10 | 20 / 2% max | Creates damage-absorbing shield |
| Haste | 30 | 35 / 3% max | Speed buff (reduces monster hit chance, boosts flee) |
| Blast | 40 | 50 / 5% max | AoE damage + burn DoT on monster |
| Paralyze | 50 | 60 / 6% max | Stuns monster for 1-2 turns (CC resistance applies) |
| Banish | 70 | 80 / 10% max | Instant kill attempt based on level difference |
| Teleport | 80 | Distance-based | Escape combat + teleport to location |
| Meteor | 100 | 100 / 8% max | Massive damage (highest single-hit mage ability) |

Mage abilities use percentage-based costs (`cost_percent` of max mana) OR the flat `cost`, whichever is higher. This ensures costs scale with late-game mana pools.

### 9c. Warrior Abilities (Stamina)

| Ability | Level | Cost | Effect |
|---------|-------|------|--------|
| Power Strike | 1 | 10 | STR-scaled heavy attack |
| War Cry | 10 | 15 | Damage buff for several rounds |
| Shield Bash | 25 | 20 | Stuns monster for 1 turn + deals damage |
| Fortify | 35 | 25 | Defense buff for several rounds |
| Cleave | 40 | 30 | Damage + bleed DoT on monster |
| Rally | 55 | 35 | Combined offense/defense buff |
| Berserk | 60 | 40 | Large damage buff, reduces defense |
| Iron Skin | 80 | 35 | Massive damage reduction for several rounds |
| Devastate | 100 | 50 | Highest single-hit warrior attack |

### 9d. Trickster Abilities (Energy)

| Ability | Level | Cost | Effect |
|---------|-------|------|--------|
| Analyze | 1 | 5 | +10% damage for rest of fight (stacks), free action |
| Distract | 10 | 15 | -50% monster accuracy on next attack |
| Pickpocket | 25 | 20 | Steal materials (1-3 per fight), free action |
| Sabotage | 30 | 25 | Reduces monster stats permanently |
| Ambush | 40 | 30 | Heavy damage + DoT effect |
| Gambit | 50 | 35 | Risk/reward: big damage or big miss, +1 gem on kill |
| Vanish | 60 | 40 | Go invisible, next attack guaranteed crit at 1.5x |
| Exploit | 80 | 35 | Damage based on monster's remaining HP% |
| Perfect Heist | 100 | 50 | Instant win with bonus loot (WITS-based success) |

### 9e. Buff Abilities and Monster Response

Buff abilities (War Cry, Fortify, Berserk, Iron Skin, Rally, Forcefield, Haste) only give the monster a **25% chance to attack** on that turn (the player is being defensive/cautious).

Free-action abilities (Analyze, Pickpocket) skip the monster's turn entirely.

### 9f. Ability Cost Reductions

Multiple sources can reduce ability costs:
- **Gnome racial:** -15% ability costs (`get_ability_cost_multiplier()`)
- **Fighter passive:** -20% stamina costs
- **Sage passive:** -25% mana costs
- **Barbarian passive:** +25% stamina costs (penalty)
- **Skill Enhancement system:** Variable reduction per ability

---

## 10. Monster Abilities

Monster abilities are defined as string constants in both `monster_database.gd` and `combat_manager.gd`. Each monster definition includes an `abilities` array. The monster turn processes these abilities in a specific order.

### 10a. Offensive Abilities

| Ability | Effect | Config Key |
|---------|--------|-----------|
| `glass_cannon` | 3x damage, 0.5x HP (applied at generation) | `glass_cannon_damage_mult`, `glass_cannon_hp_mult` |
| `multi_strike` | Attacks 2-3 times per turn | `multi_strike_min`, `multi_strike_max` |
| `berserker` | +50% damage when below 50% HP | `berserker_bonus` |
| `enrage` | +10% damage per round (stacks to 100%) | `enrage_per_round` |
| `ambusher` | First attack is guaranteed crit (1.75x) | `ambusher_multiplier` |
| `unpredictable` | Wild damage variance (0.2x to 3x) | -- |
| `weapon_master` | Increased damage, guaranteed weapon drop | -- |

### 10b. Defensive Abilities

| Ability | Effect | Config Key |
|---------|--------|-----------|
| `ethereal` | 50% chance to dodge player attacks, -10% own accuracy | `ethereal_dodge_chance` |
| `armored` | 1.5x defense (applied at generation) | -- |
| `regeneration` | Heals 10% max HP per turn | `regeneration_percent` |
| `life_steal` | Heals 50% of damage dealt | `life_steal_percent` |
| `damage_reflect` | Reflects 25% of damage taken | `damage_reflect_percent` |
| `thorns` | Damages attacker on melee (25%) | `thorns_percent` |

### 10c. Debuff Abilities

| Ability | Effect | Config Key |
|---------|--------|-----------|
| `poison` | Deals 20% of monster STR per turn as DoT | `poison_damage_percent` |
| `bleed` | Stacking bleed DoT (40% chance, 15% STR per stack) | `bleed_damage_percent`, `bleed_chance` |
| `blind` | -30% player hit chance | `blind_hit_reduction` |
| `curse` | -25% player defense | `curse_defense_reduction` |
| `disarm` | -30% weapon damage for 3 turns | `disarm_damage_reduction`, `disarm_duration` |
| `weakness` | -25% attack debuff for 20 rounds | -- |
| `slow_aura` | -25% player flee chance | `slow_aura_flee_reduction` |
| `mana_drain` | Steals player mana on hit | -- |
| `stamina_drain` | Drains player stamina on hit | -- |
| `energy_drain` | Drains player energy on hit | -- |

### 10d. Special Abilities

| Ability | Effect |
|---------|--------|
| `summoner` | 20% chance to call another monster (Shrieker triggers a new fight) |
| `pack_leader` | +25% flock chance (up to 75%) |
| `coward` | Flees at 20% HP (no loot for player) |
| `death_curse` | Deals 10% max HP on death (reduced by WIS, max 50% reduction) |
| `wish_granter` | Grants a special wish/buff on death |
| `disguise` | Appears at 50% stats, reveals true form after 2 rounds |
| `charm` | Player attacks themselves for 1 turn (50% of own attack) |
| `buff_destroy` | Removes one random active buff from player |
| `shield_shatter` | Destroys forcefield/shield buffs instantly |
| `flee_attack` | Deals damage then flees (no loot) |
| `xp_steal` | Steals 1-3% of player XP on hit |
| `item_steal` | 5% chance to steal random equipped item |

### 10e. Loot-Affecting Abilities

| Ability | Effect |
|---------|--------|
| `weapon_master` | Guaranteed weapon drop on death |
| `shield_bearer` | Guaranteed shield drop on death |
| `gem_bearer` | Always drops gems |
| `arcane_hoarder` | 35% chance to drop mage gear |
| `cunning_prey` | 35% chance to drop trickster gear |
| `warrior_hoarder` | 35% chance to drop warrior gear |
| `easy_prey` | Low stats, reduced XP (-50%) |

### 10f. Monster Ability Config

All numeric tuning values for abilities live in `server/balance_config.json` under `"monster_abilities"`:

```json
{
    "monster_abilities": {
        "corrosive_chance": 15,
        "sunder_chance": 20,
        "poison_damage_percent": 20,
        "life_steal_percent": 50,
        "regeneration_percent": 10,
        "damage_reflect_percent": 25,
        "thorns_percent": 25,
        "ethereal_dodge_chance": 50,
        "curse_defense_reduction": 25,
        "disarm_damage_reduction": 30,
        "disarm_duration": 3,
        "summoner_chance": 20,
        "ambusher_multiplier": 1.75,
        "enrage_per_round": 10,
        "berserker_bonus": 50,
        "death_curse_percent": 25,
        "glass_cannon_damage_mult": 3.0,
        "glass_cannon_hp_mult": 0.5,
        "multi_strike_min": 2,
        "multi_strike_max": 3,
        "blind_hit_reduction": 30,
        "bleed_damage_percent": 15,
        "bleed_chance": 40,
        "slow_aura_flee_reduction": 25
    }
}
```

---

## 11. Party Combat

### 11a. How It Starts

When a party leader triggers an encounter (movement or hunt), `_start_party_combat_encounter()` is called instead of solo combat. This calls `combat_mgr.start_party_combat()`.

### 11b. Monster HP Scaling

```gdscript
# In start_party_combat():
monster.max_hp = int(monster.max_hp * party_size)
monster.current_hp = monster.max_hp
```

This means:
- 2 players: 2x HP
- 3 players: 3x HP
- 4 players: 4x HP

The original max HP is stored as `original_max_hp` for reference.

### 11c. Turn Order

All party members take turns each round. The party combat state tracks:

```gdscript
var party_combat_state = {
    "leader_id": leader_peer_id,
    "party_members": [peer_id_1, peer_id_2, ...],
    "member_states": {
        peer_id: {
            "character": character_ref,
            "alive": true,
            "fled": false,
            "spectating": false
        }
    },
    "monster": monster,
    "current_turn": 0,     # Index into party_members
    "round": 1
}
```

### 11d. Weighted Targeting

When the monster attacks, targets are distributed across party members using a weighted system. This prevents the monster from always hitting the same player.

### 11e. Death and Fleeing

- **Death:** Player becomes a spectator. They can watch but cannot act.
- **Fleeing:** Player becomes a spectator (they escaped but the fight continues).
- **Total party wipe or flee:** Combat ends in defeat.
- **Victory:** Full XP, loot, and quest progress are **duplicated for each surviving member**.

---

## 12. Flock Encounters

Some monsters have a `flock_chance` (Goblins: 35%, monsters with `pack_leader`: up to 75%). After killing a monster with a flock chance, the server rolls for a continuation:

1. Victory result includes `flock_chance` value
2. Server rolls -- if flock triggers, a new monster of the same base type is generated
3. The new fight starts immediately with `flock_count` incremented
4. **Flock flee bonus:** Each previous flock fight adds +15% flee chance
5. Flock encounters use **varied colors** for visual distinction between pack members
6. Analyze bonus carries over between flock fights

---

## 13. Dungeon Combat

Dungeon encounters use the same combat system with these differences:

- Monsters are set to the dungeon boss's `monster_type` (all encounters in an Orc Stronghold are Orcs)
- Combat state includes `is_dungeon_combat: true` and `dungeon_monster_id`
- Boss fights have `is_boss_fight: true`
- The boss is a named variant (e.g., "Orc Warlord") with boosted stats
- Guaranteed boss egg drop for each party member
- Fleeing a dungeon encounter does not leave the dungeon -- the encounter is just skipped

Dungeon combat is serialized with `is_dungeon_combat` and `is_boss_fight` flags for disconnect recovery.

---

## 14. Combat Serialization

Combat state can be saved when a player disconnects and restored when they reconnect.

### 14a. Serialization

`serialize_combat_state(peer_id)` extracts the minimal data needed to restore:

```gdscript
func serialize_combat_state(peer_id: int) -> Dictionary:
    var combat = active_combats[peer_id]
    var monster = combat.monster
    return {
        "monster": {
            "name": monster.get("name", ""),
            "base_name": monster.get("base_name", monster.get("name", "")),
            "level": monster.get("level", 1),
            "current_hp": monster.get("current_hp", 1),
            "max_hp": monster.get("max_hp", 1),
            "strength": monster.get("strength", 10),
            "defense": monster.get("defense", 0),
            "speed": monster.get("speed", 10),
            "abilities": monster.get("abilities", []),
            "is_rare_variant": monster.get("is_rare_variant", false),
            "variant_name": monster.get("variant_name", ""),
            "experience_reward": monster.get("experience_reward", 10),
            "class_affinity": monster.get("class_affinity", 0),
            "is_dungeon_monster": monster.get("is_dungeon_monster", false),
            "is_boss": monster.get("is_boss", false)
        },
        "round": combat.get("round", 1),
        "player_can_act": combat.get("player_can_act", true),
        "outsmart_failed": combat.get("outsmart_failed", false),
        "analyze_bonus": combat.get("analyze_bonus", 0),
        "ambusher_active": combat.get("ambusher_active", false),
        "is_dungeon_combat": combat.get("is_dungeon_combat", false),
        "is_boss_fight": combat.get("is_boss_fight", false),
        "dungeon_monster_id": combat.get("dungeon_monster_id", -1),
        "flock_remaining": combat.get("flock_remaining", 0),
        "cc_resistance": combat.get("cc_resistance", 0)
    }
```

### 14b. Deserialization

`restore_combat(peer_id, character, saved_state)` rebuilds the combat state:

- Always sets `player_can_act = true` on restore (they may have disconnected during monster's turn)
- Migrates old key names (`xp_reward` -> `experience_reward`)
- Re-applies companion passive abilities
- Returns a `combat_start`-like result for the client

### 14c. Critical Pitfall

**Serialization keys MUST match what consumers expect.** If you serialize as `"xp_reward"` but the victory processing reads `"experience_reward"`, it will crash or default to 10. Always use `.get("key", default)` when reading deserialized dictionaries, never dot access.

The `restore_combat()` function includes explicit migration logic:

```gdscript
if not monster.has("experience_reward") and monster.has("xp_reward"):
    monster["experience_reward"] = monster["xp_reward"]
```

---

## 15. Rewards and Loot

### 15a. XP Calculation

On victory, `_process_victory_with_abilities()` calculates XP:

```
base_xp = monster.experience_reward
    (calculated at generation: pow(level + 1, 2.2) * 1.11, adjusted by lethality)

Level difference scaling:
    If monster_level > player_level:
        reference_gap = 10 + player_level * 0.05
        gap_ratio = level_diff / reference_gap
        xp_multiplier = 1.0 + sqrt(gap_ratio) * 0.7   (diminishing returns)

    If monster_level < player_level:
        Grace zone: 5 + player_level * 0.03 levels with no penalty
        Beyond grace: -3% per level, floor at 40% XP

final_xp = base_xp * xp_multiplier * 1.10   (flat +10% boost)
```

XP modifiers applied after:
- Easy Prey ability: -50%
- Ranger Hunter's Mark: +30%
- Companion receives 10% of base XP

### 15b. Gems

Monster gems are a rare currency. The chance is based on monster lethality:

```
gem_chance based on lethality / gem_lethality_divisor (from balance_config)
gem_bearer ability: always drops gems
gambit_kill: +1 bonus gem
```

### 15c. Item Drops

`roll_combat_drops(monster, character)` uses the monster's `drop_table_id` and `drop_chance` to generate loot via `drop_tables.gd`.

Special drop abilities:
- `weapon_master`: Guarantees a weapon drop
- `shield_bearer`: Guarantees a shield drop
- `arcane_hoarder` / `cunning_prey` / `warrior_hoarder`: 35% chance for path-specific gear

### 15d. Companion Egg Chance

Certain monster types can drop companion eggs. The chance is handled by `drop_tables.get_egg_for_monster()`.

### 15e. Quest Progress

The server checks if the defeated monster matches any active quest targets and updates progress accordingly.

### 15f. Equipment Wear

After each fight (~30% chance), one random equipped item takes 1-3 wear points. This is handled by `_apply_combat_wear()`.

---

## 16. The Known HP System

Players do NOT see actual monster HP values on their first encounter. This creates a discovery mechanic.

### How It Works

1. **First encounter with a monster type:** HP bar shows "???"
2. **Server sends `monster_hp = -1`** if the player has never killed this monster type at this level or higher
3. **After killing:** The client records "known HP" = **total damage dealt** in that fight (may exceed actual HP due to overkill)
4. **Future encounters** of the same base name at equal or lower level: HP is "known" and displayed
5. **Estimation:** If the player killed the same type at a different level, `estimate_enemy_hp()` scales the known value

### Implementation

- **Server:** `character.knows_monster()` tracks the highest level killed per monster base name
- **Server:** Sends `monster_hp = -1` when the player has no knowledge
- **Client:** `known_enemy_hp` dictionary maps `"MonsterName_Level"` -> total damage dealt
- **Client:** `estimate_enemy_hp()` uses known data from other levels to estimate
- **Client:** Magic Bolt mana suggestions use client-side known HP, NOT server actual HP

### Key Insight

Known HP is based on **damage dealt**, not actual monster HP. If a player one-shots a monster with a 500-damage crit when it had 200 HP, the known HP is recorded as 500. If they kill the same monster type more efficiently later with only 210 total damage, the known HP drops to 210. Over time, players converge on the true value.

---

## 17. Lethality and Balance

### 17a. The Lethality Formula

Lethality quantifies how dangerous a monster is. It determines XP rewards and is used by the combat simulator for balance testing.

```gdscript
func calculate_lethality(monster: Dictionary) -> int:
    var base = monster.max_hp * hp_weight          # 2.5
              + monster.strength * str_weight       # 7.5
              + monster.defense * def_weight        # 2.5
              + monster.speed * speed_weight         # 5.0

    var ability_multiplier = 1.0
    for ability in monster.abilities:
        ability_multiplier += ability_modifiers.get(ability, 0.0)

    return max(1, int(base * ability_multiplier))
```

### 17b. Lethality Weights (from `balance_config.json`)

| Stat | Weight | Rationale |
|------|--------|-----------|
| HP | 2.5 | HP makes fights longer but doesn't directly threaten |
| STR | 7.5 | Damage is the primary danger factor |
| DEF | 2.5 | Defense extends fights, increasing cumulative damage |
| Speed | 5.0 | Speed affects initiative and dodge mechanics |

### 17c. Ability Modifiers (lethality multipliers)

High-impact abilities:
- `weapon_master`: +1.50 (powerful loot = more risk)
- `multi_strike`: +1.00 (2-3x attacks per turn)
- `shield_bearer`: +1.00
- `death_curse`: +0.75
- `life_steal`: +0.75
- `glass_cannon`: +0.60
- `ethereal`: +0.60
- `berserker`: +0.60

Low-impact or negative:
- `easy_prey`: -0.50
- `coward`: -0.40
- `wish_granter`: +0.10
- `gem_bearer`: +0.15

### 17d. The Combat Simulator

The `tools/combat_simulator/` directory contains a headless simulation tool that tests all 9 classes against all monster types at various levels.

**Run it:**
```bash
"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "C:\Users\Dexto\Documents\phantasia-revival" --script "res://tools/combat_simulator/simulator.gd" 2>&1
```

**Key files:**
- `simulator.gd` -- Entry point, orchestrates simulations
- `combat_engine.gd` -- Damage formulas and ability processing (mirrors combat_manager.gd)
- `simulated_character.gd` -- Simplified character for simulation
- `gear_generator.gd` -- Generates equipment for simulated characters
- `results_writer.gd` -- Outputs JSON results and markdown summaries

**Empirical lethality formula:**
```
empirical_lethality = (1 / win_rate) * (1 + damage_ratio) * 100
```

Latest results show all classes achieving 89-96% same-level win rates with a 6.9% spread -- indicating good balance.

---

## 18. Modifying Combat

### 18a. Changing Damage Formulas

**File:** `shared/combat_manager.gd`

**Player damage:** Edit `calculate_damage()` (line ~4301). The function is extensively commented. Modify individual steps (STR multiplier, crit calculation, defense formula, etc.) without restructuring the entire pipeline.

**Monster damage:** Edit `calculate_monster_damage()` (line ~4585). Same structure but simpler (no class passives, no equipment procs).

**Config-driven changes:** Many values are read from `balance_config.json`:
```json
{
    "combat": {
        "player_str_multiplier": 0.02,
        "player_crit_base": 5,
        "player_crit_per_dex": 0.5,
        "player_crit_max": 25,
        "player_crit_damage": 1.5,
        "defense_formula_constant": 100,
        "defense_max_reduction": 0.6,
        "equipment_defense_cap": 0.4,
        "equipment_defense_divisor": 400
    }
}
```

Change these values to adjust balance without touching code.

### 18b. Adding a New Monster Ability

**Step 1:** Add the constant to both files:
```gdscript
# In monster_database.gd:
const ABILITY_MY_ABILITY = "my_ability"

# In combat_manager.gd:
const ABILITY_MY_ABILITY = "my_ability"
```

**Step 2:** Add it to a monster definition in `monster_database.gd`:
```gdscript
MonsterType.MY_MONSTER:
    return {
        ...
        "abilities": [ABILITY_MY_ABILITY, ...],
        ...
    }
```

**Step 3:** Add processing logic in `combat_manager.gd`. Most abilities are processed in `process_monster_turn()` (line ~3530):
```gdscript
# In process_monster_turn():
if ABILITY_MY_ABILITY in abilities:
    # Apply the effect
    var effect_damage = int(monster.strength * 0.3)
    character.current_hp -= effect_damage
    messages.append("[color=#FF4444]My ability deals %d damage![/color]" % effect_damage)
```

**Step 4:** Add the ability modifier to `balance_config.json`:
```json
"ability_modifiers": {
    "my_ability": 0.35
}
```

**Step 5:** Test with the combat simulator. Add the ability to `combat_engine.gd` if the simulator should model it.

### 18c. Adding a New Class Ability

**Step 1:** Add the ability info in `_get_ability_info()` (line ~3271):
```gdscript
"warrior":
    match ability_name:
        ...
        "my_ability": return {"level": 45, "cost": 25, "name": "My Ability"}
```

**Step 2:** Add the ability name to the command list:
```gdscript
# At the top of combat_manager.gd:
const WARRIOR_ABILITY_COMMANDS = [..., "my_ability"]
```

**Step 3:** Add processing in the path handler. For warriors, edit `_process_warrior_ability()` (line ~2780):
```gdscript
"my_ability":
    var cost = apply_skill_cost_reduction(character, "my_ability", ability_info.cost)
    if character.current_stamina < cost:
        return {"success": false, "messages": ["Not enough stamina!"], "combat_ended": false}
    character.current_stamina -= cost

    # Your ability logic here
    var damage = int(character.get_total_attack() * 2.0)
    damage = apply_skill_damage_bonus(character, "my_ability", damage)
    monster.current_hp -= damage
    messages.append("[color=#FFD700]My Ability hits for %d![/color]" % damage)

    if monster.current_hp <= 0:
        return _process_victory(combat, messages)

    return {"success": true, "messages": messages, "combat_ended": false}
```

**Step 4:** Add to server routing. In `server.gd`, the `"combat_ability"` message handler passes the ability name to `combat_mgr.process_ability_command()`. If your ability name is already in the path's ability list (Step 1), routing works automatically.

**Step 5:** Add client display. In `client.gd`, add the ability to the combat action bar and the ability mapping system. Update the help page at `show_help()`.

### 18d. Adding a New Monster Type

**Step 1:** Add to the `MonsterType` enum in `monster_database.gd`:
```gdscript
enum MonsterType {
    ...
    MY_MONSTER,
}
```

**Step 2:** Add to the appropriate tier list in `_get_tier_monsters()`:
```gdscript
5:
    return [
        ...
        MonsterType.MY_MONSTER,
    ]
```

**Step 3:** Define base stats in `get_monster_base_stats()`:
```gdscript
MonsterType.MY_MONSTER:
    return {
        "name": "Shadow Beast",
        "base_level": 60,
        "base_hp": 50,
        "base_strength": 30,
        "base_defense": 15,
        "base_speed": 25,
        "base_experience": 100,
        "base_gold": 0,
        "flock_chance": 0,
        "drop_table_id": "tier5",
        "drop_chance": 8,
        "description": "A creature born of pure shadow",
        "class_affinity": ClassAffinity.MAGICAL,
        "abilities": [ABILITY_ETHEREAL, ABILITY_LIFE_STEAL],
        "death_message": "The shadow dissolves into nothingness."
    }
```

**Step 4:** Add ASCII art in `client/monster_art.gd` `get_art_map()`.

**Step 5:** Run the combat simulator to verify balance.

### 18e. Adjusting Balance Without Code Changes

The `server/balance_config.json` file controls most combat numbers. Edit it and restart the server:

- **`combat` section:** STR multiplier, crit rates, defense formula constants
- **`lethality` section:** Stat weights and ability modifiers for XP scaling
- **`monster_abilities` section:** Specific ability percentages (poison damage, ethereal dodge, etc.)
- **`rewards` section:** XP scaling, gem rates
- **`monster_spawning` section:** Tier bleed chance

### 18f. Common Modification Checklist

When modifying combat, verify these:

1. **Serialization:** If you add new combat state fields, update `serialize_combat_state()` and `restore_combat()` to handle them. Use the EXACT same key names.
2. **Party combat:** If your change affects solo combat, check if it also needs to work in `start_party_combat()` and the party turn processing.
3. **Combat simulator:** Update `tools/combat_simulator/combat_engine.gd` if the change affects damage calculations or class abilities.
4. **Client display:** The client receives combat state updates and renders them. If you add new status effects or ability results, ensure the client shows them (combat messages are returned as BBCode strings).
5. **Balance config:** Prefer putting tunable values in `balance_config.json` rather than hardcoding them.
6. **Known HP:** The client tracks damage dealt for the known HP system. Changes to damage calculations will affect what players "learn" about monster HP.
7. **Equipment wear:** The `_apply_combat_wear()` function runs after each fight. New abilities that affect equipment should integrate with the wear system.

---

## Appendix A: Combat State Reference

Full list of keys that may appear in a combat state dictionary:

| Key | Type | Set By | Purpose |
|-----|------|--------|---------|
| `peer_id` | int | start_combat | Owning player |
| `character` | Character | start_combat | Player reference |
| `monster` | Dictionary | start_combat | Monster data |
| `round` | int | start_combat | Current round number |
| `player_can_act` | bool | turn processing | Whether player can choose an action |
| `combat_log` | Array | start_combat | Messages generated during combat |
| `started_at` | int | start_combat | Timestamp (msec) |
| `outsmart_failed` | bool | process_outsmart | Whether outsmart was already attempted |
| `ambusher_active` | bool | start_combat | Monster's first hit crits |
| `monster_went_first` | bool | start_combat | Display flag |
| `cc_resistance` | int | CC abilities | Increases per CC application |
| `enrage_stacks` | int | process_monster_turn | Enrage damage bonus counter |
| `thorns_damage` | int | start_combat | Thorns reflection amount |
| `curse_applied` | bool | process_monster_turn | Whether curse debuff is active |
| `disarm_applied` | bool | process_monster_turn | Whether disarm debuff is active |
| `summoner_triggered` | bool | process_monster_turn | Whether summoner already called |
| `disguise_active` | bool | start_combat | Whether monster is disguised |
| `disguise_true_stats` | Dictionary | start_combat | Real stats before disguise |
| `disguise_revealed` | bool | turn processing | Whether disguise was dropped |
| `total_damage_dealt` | int | turn processing | Cumulative player damage |
| `total_damage_taken` | int | turn processing | Cumulative monster damage |
| `player_hp_at_start` | int | start_combat | For death screen stats |
| `pickpocket_count` | int | process_trickster_ability | Times pickpocketed this fight |
| `pickpocket_max` | int | start_combat | Max pickpocket attempts (1-3) |
| `forcefield_shield` | int | start_combat | Forcefield HP remaining |
| `lifesteal_percent` | int | start_combat | Lifesteal % from scrolls |
| `player_thorns` | int | start_combat | Thorns % from scrolls |
| `crit_bonus` | int | start_combat | Crit chance bonus from scrolls |
| `analyze_bonus` | int | process_trickster_ability | Stacking +10% damage from Analyze |
| `vanished` | bool | process_trickster_ability | Next attack is auto-crit |
| `cloak_active` | bool | _process_universal_ability | 50% monster miss chance |
| `enemy_distracted` | bool | process_trickster_ability | -50% monster accuracy |
| `monster_stunned` | int | CC abilities | Turns of stun remaining |
| `monster_burn` | int | _process_mage_ability | Burn DoT damage per tick |
| `monster_burn_duration` | int | _process_mage_ability | Burn rounds remaining |
| `monster_bleed` | int | _process_warrior_ability | Bleed DoT damage per tick |
| `monster_bleed_duration` | int | _process_warrior_ability | Bleed rounds remaining |
| `player_bleed_stacks` | int | process_monster_turn | Player bleed stacks |
| `player_bleed_damage` | int | process_monster_turn | Damage per bleed stack |
| `player_charmed` | bool | process_monster_turn | Player attacks self next turn |
| `player_slow` | int | process_monster_turn | Flee chance reduction |
| `ninja_flee_protection` | bool | process_flee | Ninja takes no damage after failed flee |
| `gambit_kill` | bool | process_trickster_ability | Gambit bonus gem on kill |
| `companion_abilities` | Dictionary | start_combat | Companion passive/active/threshold |
| `companion_threshold_triggered` | bool | start_combat | Whether threshold fired |
| `companion_hp_boost_applied` | int | start_combat | Temporary HP from companion |
| `companion_resource_boost_applied` | int | start_combat | Temporary resource from companion |
| `companion_attack_bonus` | int | companion passive | Companion damage % bonus |
| `companion_defense_bonus` | int | companion passive | Companion defense bonus |
| `companion_crit_bonus` | int | companion passive | Companion crit chance bonus |
| `companion_speed_bonus` | int | companion passive | Companion speed bonus |
| `companion_lifesteal_bonus` | int | companion passive | Companion lifesteal % |
| `is_dungeon_combat` | bool | dungeon handler | Whether this is a dungeon fight |
| `is_boss_fight` | bool | dungeon handler | Whether this is a boss fight |
| `dungeon_monster_id` | int | dungeon handler | Dungeon encounter index |
| `flock_remaining` | int | server flock handling | Remaining flock members |
| `flock_count` | int | server flock handling | Flock members fought so far |

## Appendix B: Key Function Index

| Function | File | Line | Purpose |
|----------|------|------|---------|
| `start_combat()` | combat_manager.gd | ~727 | Initialize solo combat |
| `process_combat_action()` | combat_manager.gd | ~1025 | Route player action |
| `process_attack()` | combat_manager.gd | ~1129 | Basic attack logic |
| `process_flee()` | combat_manager.gd | ~1742 | Flee attempt |
| `process_outsmart()` | combat_manager.gd | ~1860 | Outsmart attempt |
| `process_ability_command()` | combat_manager.gd | ~2234 | Route ability to handler |
| `_process_mage_ability()` | combat_manager.gd | ~2459 | Mage ability handler |
| `_process_warrior_ability()` | combat_manager.gd | ~2780 | Warrior ability handler |
| `_process_trickster_ability()` | combat_manager.gd | ~2949 | Trickster ability handler |
| `_get_ability_info()` | combat_manager.gd | ~3271 | Ability definitions |
| `_process_victory()` | combat_manager.gd | ~3315 | Victory processing |
| `process_monster_turn()` | combat_manager.gd | ~3530 | Monster attack logic |
| `calculate_damage()` | combat_manager.gd | ~4301 | Player -> monster damage |
| `_get_class_advantage_multiplier()` | combat_manager.gd | ~4512 | Affinity multiplier |
| `_get_tier_for_level()` | combat_manager.gd | ~4564 | Level -> tier mapping |
| `calculate_monster_damage()` | combat_manager.gd | ~4585 | Monster -> player damage |
| `end_combat()` | combat_manager.gd | ~4659 | Cleanup and state removal |
| `serialize_combat_state()` | combat_manager.gd | ~5187 | Save for disconnect |
| `restore_combat()` | combat_manager.gd | ~5227 | Restore from disconnect |
| `start_party_combat()` | combat_manager.gd | ~5308 | Initialize party combat |
| `process_use_item()` | combat_manager.gd | ~3346 | Use item in combat |
| `trigger_encounter()` | server.gd | ~4739 | Roll and start encounter |
| `handle_hunt()` | server.gd | ~2628 | Hunt action handler |
| `generate_monster()` | monster_database.gd | ~172 | Monster generation entry |
| `scale_monster_to_level()` | monster_database.gd | ~1366 | Stat scaling |
| `calculate_lethality()` | monster_database.gd | ~71 | Lethality score |
| `get_class_passive()` | character.gd | ~503 | Class passive definitions |
| `get_total_attack()` | character.gd | ~939 | Total attack with equipment |
| `get_total_defense()` | character.gd | ~944 | Total defense with equipment |
| `get_equipment_bonuses()` | character.gd | ~725 | All equipment stat bonuses |
