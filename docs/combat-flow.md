# Combat System Flow

## Combat Lifecycle

```mermaid
flowchart TB
    subgraph Init["Combat Initialization"]
        ENC[Monster Encounter] --> INIT[start_combat]
        INIT --> AMBUSH{Ambusher<br/>Ability?}
        AMBUSH -->|Yes| AMB_BONUS[+15% Initiative]
        AMBUSH -->|No| SPEED_CHECK
        AMB_BONUS --> SPEED_CHECK
        SPEED_CHECK{Monster Speed ><br/>Player DEX?}
        SPEED_CHECK -->|Yes| INIT_ROLL[Roll Initiative<br/>max 40% chance]
        SPEED_CHECK -->|No| PLAYER_FIRST[Player Acts First]
        INIT_ROLL --> MONSTER_FIRST{Roll Success?}
        MONSTER_FIRST -->|Yes| MON_STRIKE[Monster First Strike]
        MONSTER_FIRST -->|No| PLAYER_FIRST
        MON_STRIKE --> PLAYER_DIED{Player HP = 0?}
        PLAYER_DIED -->|Yes| DEFEAT[Combat End: Defeat]
        PLAYER_DIED -->|No| PLAYER_FIRST
    end

    subgraph Combat["Combat Loop"]
        PLAYER_FIRST --> PLAYER_TURN[Player Turn]
        PLAYER_TURN --> PLAYER_ACTION{Action?}
        PLAYER_ACTION -->|Attack| ATTACK
        PLAYER_ACTION -->|Flee| FLEE
        PLAYER_ACTION -->|Outsmart| OUTSMART
        PLAYER_ACTION -->|Ability| ABILITY
        PLAYER_ACTION -->|Defend| DEFEND
        PLAYER_ACTION -->|Use Item| ITEM

        ATTACK --> CALC_DMG[Calculate Damage]
        FLEE --> FLEE_CHECK{Flee Success?}
        OUTSMART --> OUTSMART_CHECK{WITS Check?}
        ABILITY --> ABILITY_EFFECT[Apply Ability Effect]
        DEFEND --> DEF_BUFF[+50% Defense This Round]
        ITEM --> ITEM_EFFECT[Apply Item Effect]

        CALC_DMG --> ETHEREAL{Ethereal<br/>Monster?}
        ETHEREAL -->|Yes, 50%| MISS[Attack Misses]
        ETHEREAL -->|No| APPLY_DMG[Apply Damage]
        MISS --> CHECK_MON_HP

        APPLY_DMG --> REFLECT{Damage<br/>Reflect?}
        REFLECT -->|Yes| REFLECT_DMG[Player Takes 25%]
        REFLECT -->|No| CHECK_MON_HP
        REFLECT_DMG --> CHECK_MON_HP

        FLEE_CHECK -->|Yes| ESCAPED[Combat End: Escaped]
        FLEE_CHECK -->|No| FLEE_FAIL[Flee Failed]
        FLEE_FAIL --> MONSTER_TURN

        OUTSMART_CHECK -->|Yes| VICTORY[Combat End: Victory]
        OUTSMART_CHECK -->|No| OUT_FAIL[Outsmart Failed<br/>Cannot retry]
        OUT_FAIL --> MONSTER_TURN

        ABILITY_EFFECT --> CHECK_MON_HP
        DEF_BUFF --> MONSTER_TURN
        ITEM_EFFECT --> CHECK_MON_HP

        CHECK_MON_HP{Monster HP = 0?}
        CHECK_MON_HP -->|Yes| VICTORY
        CHECK_MON_HP -->|No| MONSTER_TURN

        MONSTER_TURN[Monster Turn] --> MON_ABILITIES[Process Abilities]
        MON_ABILITIES --> MON_ATTACK[Monster Attack]
        MON_ATTACK --> DODGE_CHECK{Player Dodges?}
        DODGE_CHECK -->|Yes| MON_MISS[Monster Misses]
        DODGE_CHECK -->|No| MON_DAMAGE[Apply Damage]
        MON_MISS --> CHECK_PLAYER_HP
        MON_DAMAGE --> CHECK_PLAYER_HP

        CHECK_PLAYER_HP{Player HP = 0?}
        CHECK_PLAYER_HP -->|Yes| LAST_STAND{Dwarf<br/>Last Stand?}
        LAST_STAND -->|Yes, 25%| SURVIVE[Survive with 1 HP]
        LAST_STAND -->|No| DEFEAT
        SURVIVE --> NEW_ROUND
        CHECK_PLAYER_HP -->|No| NEW_ROUND[New Round]
        NEW_ROUND --> PLAYER_TURN
    end

    subgraph End["Combat Resolution"]
        VICTORY --> LOOT[Roll Loot]
        LOOT --> XP[Award XP]
        XP --> GOLD[Award Gold]
        GOLD --> GEMS{Gem Drop?}
        GEMS -->|Yes| AWARD_GEMS[Award Gems]
        GEMS -->|No| WISH_CHECK
        AWARD_GEMS --> WISH_CHECK
        WISH_CHECK{Wish Granter?}
        WISH_CHECK -->|Yes| WISH[Show Wish Selection]
        WISH_CHECK -->|No| SUMMONER{Summoner?}
        WISH --> DONE[Combat Complete]
        SUMMONER -->|Yes| REINFORCE[Force New Combat]
        SUMMONER -->|No| FLOCK{Flock<br/>Encounter?}
        FLOCK -->|Yes| FLOCK_COMBAT[Continue to Next Monster]
        FLOCK -->|No| DONE
        REINFORCE --> Init
        FLOCK_COMBAT --> Init

        DEFEAT --> PERMADEATH[Character Deleted]
        ESCAPED --> DONE
    end
```

## Damage Calculation

```mermaid
flowchart LR
    subgraph Player["Player Damage"]
        BASE_P[Base: STR + Weapon ATK]
        CRIT_P{Critical Hit?}
        BASE_P --> CRIT_P
        CRIT_P -->|Yes| CRIT_DMG[x2 Damage]
        CRIT_P -->|No| BUFF_P
        CRIT_DMG --> BUFF_P[Apply Buffs<br/>War Cry, Berserk]
        BUFF_P --> AFFINITY_P{Class Affinity?}
        AFFINITY_P -->|Advantage| PLUS_50[+50% Damage]
        AFFINITY_P -->|Disadvantage| MINUS_25[-25% Damage]
        AFFINITY_P -->|Neutral| DEF_P
        PLUS_50 --> DEF_P
        MINUS_25 --> DEF_P
        DEF_P[Reduce by Monster DEF]
        DEF_P --> FINAL_P[Final Damage]
    end

    subgraph Monster["Monster Damage"]
        BASE_M[Base: Monster STR]
        ENRAGE{Enrage<br/>Stacks?}
        BASE_M --> ENRAGE
        ENRAGE -->|Yes| ENRAGE_DMG[+10% per stack]
        ENRAGE -->|No| BERSERK_M
        ENRAGE_DMG --> BERSERK_M
        BERSERK_M{Below 50% HP?<br/>Berserker ability}
        BERSERK_M -->|Yes| BERSERK_DMG[+50% Damage]
        BERSERK_M -->|No| PLAYER_DEF
        BERSERK_DMG --> PLAYER_DEF
        PLAYER_DEF[Reduce by Player DEF]
        PLAYER_DEF --> SHIELD{Forcefield?}
        SHIELD -->|Yes| ABSORB[Absorb Damage]
        SHIELD -->|No| FINAL_M
        ABSORB --> FINAL_M[Final Damage]
    end
```

## Rare Monster Variants

Some monsters spawn as rare variants with enhanced stats and rewards.

```mermaid
flowchart LR
    subgraph Spawn["Monster Spawn"]
        GEN[Generate Monster] --> ROLL{Variant Roll}
        ROLL -->|~10% Chance| RARE[Rare Variant]
        ROLL -->|~90%| NORMAL[Normal Monster]
    end

    subgraph RareBonus["Rare Variant Bonuses"]
        RARE --> HP["+50% HP"]
        RARE --> DMG["+25% Damage"]
        RARE --> XP["+50% XP"]
        RARE --> GOLD["+50% Gold"]
        RARE --> LOOT["Better Loot"]
    end

    subgraph Display["Combat Display"]
        RARE --> STAR["★ Monster Name"]
        NORMAL --> PLAIN["Monster Name"]
    end

    style RARE fill:#FFD700
    style STAR fill:#FFD700
```

**Visual Indicator:** Rare variants show a **★** before their name:
```
★ Goblin Warrior (Lvl 12): [████████░░] 85/170
```

| Bonus | Amount |
|-------|--------|
| HP | +50% |
| Damage | +25% |
| XP Reward | +50% |
| Gold Reward | +50% |
| Loot Quality | Improved |

**Flock Encounters:** Rare variants can appear in flock encounters - each monster rolls independently.

---

## Monster Ability Effects

| Ability | When | Effect |
|---------|------|--------|
| `glass_cannon` | Spawn | 3x damage, 50% HP |
| `multi_strike` | Attack | 2-3 attacks per turn |
| `poison` | Hit | 40% chance poison player |
| `mana_drain` | Hit | Steal player mana |
| `regeneration` | Turn Start | Heal 10% HP |
| `damage_reflect` | Player Attack | Reflect 25% damage |
| `ethereal` | Player Attack | 50% dodge chance |
| `armored` | Always | +50% defense |
| `berserker` | Below 50% HP | +50% damage |
| `enrage` | Each Round | +10% damage (stacking) |
| `ambusher` | First Attack | Guaranteed crit (2x) |
| `summoner` | 20% per turn | Call reinforcement |
| `wish_granter` | Death | Grant powerful buff |
| `death_curse` | Death | Deal 25% max HP damage |
| `coward` | Below 20% HP | Flee (no loot) |
| `life_steal` | Hit | Heal 50% of damage |
| `thorns` | Player Attack | Reflect 25% melee |
| `charm` | Hit | Player attacks self |
| `gold_steal` | Hit | Steal 5-15% gold |
| `buff_destroy` | Hit | Remove random buff |

## Class Affinity System

```mermaid
graph LR
    subgraph Affinities
        N[Neutral<br/>White]
        P[Physical<br/>Yellow]
        M[Magical<br/>Blue]
        C[Cunning<br/>Green]
    end

    subgraph Classes
        W[Warriors<br/>Fighter, Barbarian, Paladin]
        MA[Mages<br/>Wizard, Sorcerer, Sage]
        T[Tricksters<br/>Thief, Ranger, Ninja]
    end

    W -->|+50% vs| P
    W -->|Normal| N
    W -->|-25% vs| M
    W -->|-25% vs| C

    MA -->|+50% vs| M
    MA -->|Normal| N
    MA -->|-25% vs| P
    MA -->|-25% vs| C

    T -->|+50% vs| C
    T -->|Normal| N
    T -->|-25% vs| P
    T -->|-25% vs| M
```

## Outsmart Formula

```
Success Chance = 30% + (Player_WITS - Monster_INT) * 0.5%

Minimum: 5%
Maximum: 75%

Rewards on Success:
- Full XP (no penalty)
- Full Gold (no penalty)
- 50% chance to skip negative ability effects
```

## Flee Formula

```
Base Chance = 40%
+ DEX Bonus: +(DEX - 10) * 0.5%
+ Speed Bonus: +Equipment_Speed * 0.3%
- Level Penalty: -(Monster_Level - Player_Level) * 2% (if higher)
+ Trickster Bonus: +10% (Thief, Ranger, Ninja)

Minimum: 10%
Maximum: 90%

Slow Aura: -20% flee chance
```
