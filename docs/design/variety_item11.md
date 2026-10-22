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

## 6. BUILD STATUS (2026-10-22, unreleased)

Owner's third-round answers: **extend the Empowered list** with the new traits (one mechanism), and **everything is a step up** (no weakening traits). Reading the code showed the trait system already existed as Empowered
modifiers (25% of monsters from L5, named prefixes, XP and loot per modifier), and that `coward` (flees at low health) and `regeneration` already existed as abilities - so the trait work was mostly data.

| piece | state |
|---|---|
| **Traits (11b)** | BUILT. Six new modifiers join the nine: Thick-hided, Stalwart, Giant, Ponderous (stat trades, each a step up), Skittish (the existing `coward`: finish it before it runs), Regenerating (the existing `regeneration`: burst it). The roll is now **one in three** (`EMPOWERED_ROLL_CHANCE` 0.33, was 0.25). Frail/Runt were dropped (they would have made a monster easier). Wording, colour and the hover come from the same tables as the old modifiers. Probe `new_traits_are_empowered_mods`. The role calibration (`rolecal`) sizes the empowered tier, so the chain re-fits the higher rate. |
| **Reveal** | BUILT by construction: a trait is in the monster's name and the opening line, which is when a monster becomes visible at all. |
| **Boards, species variety (11a)** | BUILT. A board drew from TWO dungeons per tier; it now draws from every dungeon of the area's tier and the two below, walked in one seeded shuffle, so a board names at least four different dungeons (measured before: worst board 3, mean 5.7 distinct names; after: worst 5, mean 7.3). Rescued NPCs and fabled bosses are distinct inside a board too. Probe `quest_board_variety`. |
| **Boards, themes** | BUILT for species families: all 53 dungeons belong to one of eight families, each post has a fixed theme, and its board's first three quests lean to that family when the tier range has one. **Terrain is NOT built** (it needs the world's biome at the post's tile). |
| **Boards, trait hunts + hourly bounty** | BUILT. A new quest kind `TRAIT_HUNT`; the **first slot on every board is an hourly bounty** (same for every player, rotates each real-time hour): defeat 3-6 monsters carrying any trait of a GROUP (Bulky / Vicious / Cunning, five traits each). It counts a GROUP and not one trait because one trait is about 2% of monsters, which would make "kill four" a hundred fights; a group is roughly one in ten. Kills count wherever met. Probe `trait_hunt_bounty`. |
| **Companion perks (11c)** | BUILT. An egg carries up to two perks: one inherited from its monster's trait (companion-sized: Thick-hided -> Sturdy, Frenzied -> Fierce, Swift -> Quick...), one rolled and different. A plain monster's egg has just the rolled one. Baked into the egg's `bonuses`, so combat, the team and the stable see it with no code change; shown on the active companion card. Existing companions are untouched. Probe `companion_perks`. Dungeon-boss and floor eggs get the rolled perk only. |
| **Dungeon cards (D6, D7)** | Tags BUILT (all 53, from each card's `kind`; probe `dungeon_cards_tagged`). The swap audit `dungeoncardswap` is BUILT and running; its result decides the per-class buffs. First reads (Fighter, Barbarian): the guard / heal cards (Bulwark of Bone, Trollish Regrowth, Stonewatch, Shieldwall Drill) are worth swapping in; the attack-type dungeon cards mostly trail the class's own weakest card. |

**Known follow-ups:** terrain themes; a board "theme" label shown to the player; trait hunts for one specific trait (needs a way to find one); a trait glyph on the combat nameplate beyond the name.
**Release note to write:** boards reshuffle when this deploys, so a dungeon quest accepted before it can point at a different dungeon than the board now shows (accepted quests keep their stored data, so turn-in is unaffected).
