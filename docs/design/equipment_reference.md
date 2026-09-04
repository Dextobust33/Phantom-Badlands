# Equipment reference - what gear can ACTUALLY do

**Generated. Do not hand-edit.** Regenerate with:

```bash
godot --headless --path . --script res://tools/combat_simulator/real_combat_sim.gd -- gearsources
```

## Why this file exists

Claims about equipment kept being made from memory and kept being wrong - "gear is worth nothing"
(an unsound comparison), "there is no mana regen on gear" (there is `mana_on_hit`, epic+). Owner,
2026-09-04: *"You continually get that wrong. You need to take a deeper look at equipment that's
possible to get in the game because you keep failing and leaving things out or having a bad idea
of what's actually possible or there."*

**Read this before making any statement about what a player can wear, chase, or build toward.**
If the question is not answered here, run the audit rather than reasoning from memory - it walks
the game's own tables, so it cannot drift the way a hand-written summary would.

## The five things worth knowing before you theorise

1. **Affix count is fixed by rarity** - common 1, uncommon 2, rare 3, epic 4, legendary 5,
   artifact 6. Rarity buys BREADTH, not bigger individual rolls.
2. **The CHASE pool is epic-and-above only**, and even then it is a 25-50% chance per bonus roll.
   Everything interesting - crit, `damage_mult`, `extra_turn_chance`, resource-on-hit, +ability
   ranks - lives there. Below epic, gear is plain stats.
3. **Drops are NOT class-aware.** Nothing in `drop_tables.gd` looks at the player's class. There
   are no "mage drops"; a mage reaches mage-shaped affixes by farming epic+ and rolling well.
4. **Uniques and sets are the only class-SHAPED gear** (15 uniques, 3 sets, fixed stat blocks).
5. **Five declared gear stats have no source at all** - see below. They are read by combat and
   granted by nothing.

## The unimplemented five

`character.gd`'s equipment aggregator declares `mana_regen`, `meditate_bonus`, `energy_regen`,
`flee_bonus` and `stamina_regen`, commented as "Mage gear" / "Trickster gear" / "Warrior gear".
`combat_manager.gd` reads them. **No affix, chase roll, proc, rune, unique or set grants any of
them.** Only COMPANIONS provide `mana_regen` / `energy_regen`.

They were designed as the class-resource-sustain lever and never implemented, which is why "a
mage who focuses MP-regen gear" is not a build that exists in the game today.

## Generated inventory

```
===== EQUIPMENT: EVERY STAT AND WHERE IT COMES FROM =====

-- by stat --
   ability_rank_ambush          CHASE (epic+ only), enchanter rune
   ability_rank_blast           CHASE (epic+ only), enchanter rune
   ability_rank_cleave          CHASE (epic+ only), enchanter rune
   ability_rank_devastate       CHASE (epic+ only), enchanter rune
   ability_rank_exploit         CHASE (epic+ only), enchanter rune
   ability_rank_mage_dmg        CHASE (epic+ only), enchanter rune
   ability_rank_magic_bolt      CHASE (epic+ only), enchanter rune
   ability_rank_meteor          CHASE (epic+ only), enchanter rune
   ability_rank_power_strike    CHASE (epic+ only), enchanter rune
   ability_rank_shield_bash     CHASE (epic+ only), enchanter rune
   ability_rank_trickster_dmg   CHASE (epic+ only), enchanter rune
   ability_rank_warrior_dmg     CHASE (epic+ only), enchanter rune
   attack_bonus                 prefix (any rarity), suffix (any rarity), enchanter rune
   con_bonus                    suffix (any rarity), enchanter rune
   crit_chance_bonus            CHASE (epic+ only), enchanter rune
   crit_damage_bonus            CHASE (epic+ only), enchanter rune
   damage_mult                  CHASE (epic+ only), enchanter rune
   defense_bonus                prefix (any rarity), suffix (any rarity), enchanter rune
   dex_bonus                    suffix (any rarity), enchanter rune
   energy_bonus                 prefix (any rarity), suffix (any rarity), enchanter rune
   energy_on_hit                CHASE (epic+ only), enchanter rune
   extra_turn_chance            CHASE (epic+ only), enchanter rune
   hp_bonus                     prefix (any rarity), suffix (any rarity), enchanter rune
   hp_on_kill                   CHASE (epic+ only), enchanter rune
   int_bonus                    suffix (any rarity), enchanter rune
   mana_bonus                   prefix (any rarity), suffix (any rarity), enchanter rune
   mana_on_hit                  CHASE (epic+ only), enchanter rune
   proc:damage_reflect          proc suffix (tier 6+)
   proc:execute                 proc suffix (tier 6+)
   proc:lifesteal               proc suffix (tier 6+)
   proc:shocking                proc suffix (tier 6+)
   speed_bonus                  prefix (any rarity), enchanter rune
   stamina_bonus                prefix (any rarity), suffix (any rarity), enchanter rune
   stamina_on_hit               CHASE (epic+ only), enchanter rune
   str_bonus                    suffix (any rarity), enchanter rune
   wis_bonus                    suffix (any rarity), enchanter rune
   wits_bonus                   suffix (any rarity), enchanter rune

-- rarity gates --
   affixes per rarity: { "common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5, "artifact": 6 }
   chase-roll chance:  { "epic": 25, "legendary": 35, "artifact": 50 }
   drop weights:       { 1: { "common": 70, "uncommon": 20, "rare": 7, "epic": 2.5, "legendary": 0.45, "artifact": 0.05 }, 2: { "common": 65, "uncommon": 22, "rare": 8.5, "epic": 3, "legendary": 1.2, "artifact": 0.3 }, 3: { "common": 60, "uncommon": 23, "rare": 10, "epic": 4.5, "legendary": 2, "artifact": 0.5 }, 4: { "common": 58, "uncommon": 24, "rare": 10, "epic": 5, "legendary": 2.5, "artifact": 0.5 }, 5: { "common": 55, "uncommon": 25, "rare": 12, "epic": 5, "legendary": 2.5, "artifact": 0.5 }, 6: { "common": 50, "uncommon": 25, "rare": 14, "epic": 7, "legendary": 3.5, "artifact": 0.5 }, 7: { "common": 45, "uncommon": 25, "rare": 16, "epic": 8, "legendary": 5, "artifact": 1 }, 8: { "common": 40, "uncommon": 25, "rare": 17, "epic": 10, "legendary": 6, "artifact": 2 }, 9: { "common": 35, "uncommon": 25, "rare": 18, "epic": 12, "legendary": 7, "artifact": 3 } }

-- stat fields the AGGREGATOR reads that NOTHING can roll --
   mana_regen
   meditate_bonus
   energy_regen
   flee_bonus
   stamina_regen
   ^ read by combat, granted by NO random roll.
     mana_regen         NOT covered by uniques or sets either
     meditate_bonus     NOT covered by uniques or sets either
     energy_regen       NOT covered by uniques or sets either
     flee_bonus         NOT covered by uniques or sets either
     stamina_regen      NOT covered by uniques or sets either

-- uniques and sets --
   uniques: 15, sets: 3  (FIXED rolls, not from the pools above -
   see shared/unique_database.gd; these are the only class-shaped gear in the game)
=====================================================================
```
