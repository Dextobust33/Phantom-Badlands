# Strategic companion combat - S0 design (backlog item 14)

Status 2026-10-15: owner answered the three open questions (below); rulings 1-7 are proposals awaiting a yes. No code. Facts below were read from the code today.

## Facts the design starts from

- **53 species** have companion data (`COMPANION_DATA`), not 136; each has an `aggro` 8-65, tier 1-6 and 1-3 stat bonuses, and three abilities (passive / chance / HP-threshold) in `COMPANION_MONSTER_ABILITIES`.
- Today a companion's only "role" is its aggro %, and its HP pool is solved from it (`companion_hp_share`: lifetime target 1.25x, share 0.5-2.0 of the owner's bar). Only the single `active_companion` has an HP pool and KO state.
- Variants (111) are mostly cosmetic (x1.00); the stat ones multiply bonuses 1.10-1.50.
- Aggro histogram: 18 species at 10-19, 5 at 20s, 11 at 30s, 3 at 40s, 12 at 50s, 3 at 60s.

## A first derivation (probe run today, tunable)

Rule: aggro >=45 -> Tank; heal-type effect + low aggro -> Healer; aggro <=18 with mana/control/gather effects -> Utility; attack >=7 -> DPS; else Jack.

| role | species | examples |
|---|---|---|
| Tank | 16 | Skeleton, Zombie, Ogre, Troll, Minotaur, Gargoyle, Giant, Titan, Iron Golem, Hydra |
| DPS | 14 | Dragon Wyrmling, Demon, Chimaera, Balrog, Cerberus, Phoenix, God Slayer |
| Utility | 13 | Goblin, Kobold, Siren, Kelpie, Wraith, Lich, Sphinx |
| Jack-of-all-trades | 7 | Wolf, Orc, Hobgoblin, Gnoll, Wyvern, Gryphon |
| Healer | **3** | Wight, Vampire, Succubus |

**Finding: the roster has almost no healers.** Healing exists only as thresholds (Zombie "Risen Again") and regen stats. A strategic game needs healing as a chosen ACTION, so the Healer role needs NEW content: a role action, and a species-to-healer mapping chosen by theme (Phoenix, Wight, Siren, Sphinx, Lich-apprentice, Succubus, Vampire, Troll). The derivation table maps species -> role in one place (like `species_power`), with a small override list for these.

## Proposed rulings for owner sign-off

1. **Roles (5):** Tank, Healer, DPS, Utility, Jack. Role = one table keyed by species. A VARIANT may tilt, not replace: it can add a secondary tag (e.g. Blessed = heals 10% stronger), never change the primary role. Player can't re-role a companion (keeps species meaning; revisit if a gap shows).
2. **Role actions (one per role, used on the companion's own turn by its AI):** Tank = Taunt (aggro up for N turns); Healer = Heal lowest ally (also Revive an ally at a cost); DPS = Strike (bonus damage); Utility = Buff or Debuff (haste/attack up, enemy miss/slow); Jack = does whichever of the above is most needed, at 60% strength.
3. **Tactics (per companion, button on its card):** Balanced / All-out (DPS-leaning) / Protect (guard the weakest, heal first) / Support (buff first). Each role reads the focus differently; unused actions fall back to its basic attack.
4. **HP pools:** every fielded companion gets its own pool and KO state, sized by the existing aggro formula (so tanks are tough, healers fragile). KO is recoverable by: Revive Potion (item cost), a Healer's Revive action (costs the healer its next turn and a resource), the wandering healer NPC and trading-post healer (gold, scaling with level). None free, none mandatory.
5. **Targeting:** monsters pick a target by weighted aggro across ALL fielded actors (player, humans, companions) as today's per-hit roll does, with Taunt adding to it. No AoE in S1; revisit after S3.
6. **Magnitudes and caps:** heal <= 15% of the target's max HP per action at equal level; buffs <= +20% and don't stack with themselves (refresh); total of any one buff type capped at +40%. Written down now so the blacksmith-upgrade mistake isn't repeated.
7. **Companions help human party members:** yes. Heal/buff/taunt target any ally.
8. **THE CORE BALANCE QUESTION - recommended answer:** do NOT scale monsters up for companions. Each companion is individually weaker than today's single companion (a 5-companion team ~= 1.6x one companion's output, not 5x), and the extra slots are earned (slot unlocks by progression, beyond the first two). This is how the "add player power back" goal stays controlled: the chain is then re-run once with the reference player fielding a typical team.

## Slices

S1 roles on the one companion (shippable alone) -> S2 data model (`companion_party`, `active_companion` alias) -> S3 combat engine + simulator models the team first -> S4 UI (needs screenshots) -> S5 acquisition/economy -> S6 calibration chain.

## Owner decisions 2026-10-15

- **Healers:** theme-pick about 8 species through one override table (Phoenix, Wight, Siren, Sphinx, Troll, Vampire, Succubus, a Lich-type); they gain the Heal/Revive action.
- **Slots:** unlocked by progression (slot 1 now, further slots at set levels/ranks).
- **Team strength:** a full team is about **2.5x** one companion today in total output. NOTE: this supersedes the 1.6x in ruling 8 and means monsters WILL need to scale up at the next chain run, and S3's simulator must model the team before any curve is measured. Consequence for the death-risk goal: the extra power is large enough to pay for a candidate-curve ship, but only after the chain is re-run with the team in the reference player.
