# Item 11 variety + the dungeon card power pass - owner decisions (2026-10-22) and build plan

Two Wave 1 power inputs that each needed an owner conversation. Both change player or monster power, so both land BEFORE the one calibration chain.

## 1. DECIDED (owner, 2026-10-22)

| # | question | answer |
|---|---|---|
| D1 | How should two monsters of one species differ (11b)? | **Named traits.** Visible, in the name and the combat log, askable on a board. The mean stays on the curve. |
| D2 | How common? | **About 1 in 3 monsters carries one**; elites and bosses carry more. |
| D3 | What does a trait change? | **Mostly stats, a few behaviours.** |
| D4 | Do companions inherit their monster's rolls (11c)? | **Inherit one, roll one.** One perk comes from the monster's trait, one is rolled at hatch. |
| D5 | What does a quest board offer (11a)? | **Trait hunts** and **rotating themed boards**; and **at least 3-4 DIFFERENT species per board** (today a board sends you at the same couple of types). |
| D6 | Dungeon card bar | **Every class has 2+ dungeon cards worth swapping in** (measured, tuned per class). |
| D7 | Dungeon cards and triggers | **All 53 are tagged** (strike / spell / finisher / setup / guard / buff / control / debuff), so trigger gear and the Ascendant nodes work with them. |

## 2. What this commits us to

1. **Mean-preserving traits.** The monster curve is calibrated to the average monster of a level. A trait that makes monsters stronger on average silently shifts the whole calibration. So traits are built in
   COMPLEMENTARY pairs (a stronger stat bought with a weaker one) and an audit (`traitmean`) samples spawns per level and fails unless the average power index is 1.00 +- 1%. The chain then does not need to move.
2. **Companion traits are a second table**, not a copy: a companion perk is what a trait MEANS for something fighting beside you (Thick-hided monster -> Sturdy companion). The mapping is data, so "inherit one" is a lookup.
3. **Boards need a species generator, not a bigger list.** Measure first (count distinct species across a few hundred generated boards - never assume), then force >= 3-4 distinct species per board and add trait hunts as a quest KIND.
4. **Dungeon cards: a new audit** (`dungeoncardswap`): for each class, swap each dungeon card for the weakest deck slot and measure the win rate (paired seeds, like `pathvalue`). Output is the per-class list of cards that clear the bar, and
   the buffs the rest need. Tags come first because the trigger gear changes what "weakest slot" and "worth swapping" mean.

## 3. DRAFT for the owner to react to: the first trait table

Each trait shifts stats by a fixed vector chosen so that the SPAWN-WEIGHTED mean of every stat is 1.00 (the weights below are per trait among trait-bearing monsters). Names are placeholders.

| trait | effect (stats) | behaviour | pairs with |
|---|---|---|---|
| Thick-hided | HP x1.30, speed x0.85 | - | Frail |
| Frail | HP x0.75 | - | Thick-hided |
| Frenzied | strength x1.25, defence x0.80 | - | Stalwart |
| Stalwart | defence x1.25, strength x0.85 | - | Frenzied |
| Swift | speed x1.25, HP x0.90 | acts first more often | Ponderous |
| Ponderous | speed x0.75, strength x1.15 | - | Swift |
| Skittish | HP x1.10 | flees at 20% HP (you lose the kill unless you finish it) | - |
| Thorned | defence x1.10 | reflects a share of melee damage | - |
| Venomous | strength x0.90 | its hits can poison | - |
| Regenerating | HP x0.90 | heals a little each round | - |
| Gilded | - | pays extra loot reveals (already exists as an Empowered mod; kept as the board-askable one) | - |
| Giant / Runt | HP, strength both scale together | - | each other |

Behavioural traits (Skittish, Thorned, Venomous, Regenerating) carry a small stat discount, so their power cost is paid, not free.

## 4. SECOND ROUND, ANSWERED (owner, 2026-10-22)
- **Traits that ship first:** the stat pairs (Thick-hided/Frail, Frenzied/Stalwart, Swift/Ponderous, Giant/Runt), **Skittish, Thorned, Venomous and Regenerating** - all of the draft except the already-existing Gilded.
- **Board rotation:** **a fixed theme per post PLUS a rotating bounty slot, rotating HOURLY** (owner: "4. but rotates hourly").
- **Board themes built from:** **species families, dungeon types and terrain.** (Not traits-as-themes: traits come in through the rotating bounty slot and trait hunts instead.)
- **Trait reveal:** **at the start of the fight.** The owner pointed out that monsters are not visible on the overworld at all (true: an encounter fires as you move and the fight opens naming the monster), so
  there is no pre-fight reveal. The encounter opens as "Frenzied Wolf" with a trait line, and you can still flee. Hunting a trait therefore means moving through ground where it lives, which is what the terrain and
  dungeon-type board themes are for.
- **Companion perks:** **companion-sized versions of the trait** (Thick-hided -> Sturdy, Frenzied -> Fierce, Swift -> Quick). A lookup table, so "inherit one" is a mapping; behaviour traits get an ally-sized meaning
  (Thorned -> the companion's hits reflect a little to you as a guard bonus, Regenerating -> it recovers between rounds) or are left unmapped and the hatch rolls the second perk instead.

Still small and open: the exact stat vectors (they are fixed by the `traitmean` audit, not by taste), the theme lists per post, and the ally meaning of Skittish/Venomous.

## 5. Build order (after the answers above)
1. Tag the 53 dungeon cards (data) and build `dungeoncardswap`; run it; buff per class. (Independent of the rest, and the longest measurement.)
2. `shared/monster_traits.gd` + spawn integration + `traitmean`; trait on the log and name.
3. Quest generator: species spread first (measured), then trait hunts, then themed boards.
4. Companion perks and inheritance.
5. Everything above lands, THEN the Wave 2 chain.
