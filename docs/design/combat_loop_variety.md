# Making the combat loop less repetitive (ARPG / survivor elements) — DESIGN PROPOSAL

Status: **proposal, nothing built.** Owner direction 2026-10-22: *"The whole loop overall. While the cards present some interesting options and choices
especially once the player has an opportunity to upgrade them, it often becomes overly repetitive. I'd really like to find a way to incorporate what we
already have (not losing all the work we put in) into a Survivor like or ARPG style of combat."*

## 1. Diagnosis: why it repeats

Every fight is the same SHAPE: one player, one monster, a 3-card hand from a fixed 5-card deck, resolved until one HP bar empties. The decisions inside a fight
are real (engines, Brace/Ward/Slip, card upgrades) but the DECK AND THE BUILD ARE FIXED BEFORE THE FIGHT STARTS, so fight 400 poses the same question as fight 40.

What the games you named do differently, reduced to four mechanisms:

| mechanism | survivor-likes | ARPGs | what we have today |
|---|---|---|---|
| **the build is decided DURING the run** | level-up pick 1 of 3, every minute | skill/gem swaps, loot | picks happen between fights (paths, gear), never inside one |
| **many things at once, pressure from numbers** | hordes, waves | packs, elites | one monster (flocks exist; elites/bosses are still one body) |
| **loot changes how you play, not just how hard you hit** | weapon evolutions | proc/trigger uniques, links | gear is mostly numbers; card-specific gear and uniques exist |
| **moment-to-moment answers** | dodge, positioning | telegraphs, dodge-roll | 5 telegraphed bursts + Brace/Ward/Slip; 24 bursts still land blind |

## 2. What must NOT be thrown away (the build layer)

Decks, the nine engines (Momentum/Focus/Read), card upgrades, the Paths revamp (ranks, Signature branches), gear/affixes/uniques, companions, the monster curve and
the simulator. The proposal changes the ENCOUNTER layer and adds a thin RUN layer on top. The build layer stays the source of every number.

## 3. Proposal: three additions, each reusing what exists

### A. Fight Boons — the survivor "level-up pick", built from Path effects (biggest reuse)
Kills inside a fight (and the fight's length) fill a Surge meter; each time it fills, the player picks 1 of 3 **boons that last until the fight ends**.
A boon is exactly a path node at a temporary rank: same effect keys, same readers, same card faces, same probes. The pool is filtered by class and by cards in the
current hand/deck, so offers are always relevant ("Sucker Punch +20%", "Double Cross leaves 2 Read", "first crit each round refunds a card").
- Fixes: build decided mid-fight; every fight ends with a different build than it began.
- Cost: a pick UI in the combat scene, a boon pool (data, ~10 per class drawn from existing effect keys), a pacing rule (picks must not slow trash fights: only fights
  of 3+ enemies or elites+ offer them).

### B. Encounter shapes — waves, packs, objectives
Add fight shapes beside the classic duel: **Wave** (3-5 monsters arriving in sequence, HP carried over, boons accumulating), **Pack** (2-4 at once, each with its own
countdown), **Elite + adds**, **Objective** (break the totem / outlast the timer). Flocks and persistent buffs already carry state between fights; the dungeon
revamp already has floors. Pilot in dungeons (where fights are curated), not the overworld.
- Cost: the largest. Multi-target combat state, a target pick, UI for several enemies, and the monster curve needs a wave calibration (own preflight; do NOT fold into
  the duel chain).

### C. Gear and paths as triggers (the ARPG build-identity layer)
Tag every card (fire, bleed, burst, guard, finisher...). Gear affixes, uniques and path nodes gain trigger forms: "when you crit, refund 1 Read", "every 4th burn tick
explodes", "guard cards also heal". The Signature branches already do this per class; this extends it to loot so a drop can change how a deck plays.
- Cost: tags are data; triggers need a small event bus in the combat manager (on_cast / on_crit / on_kill / on_hit_taken). The paths-wired probe pattern proves each.

### D. Close the telegraph queue (small, already planned)
The 24 blind cyclical bursts. Convert the ones that are single big moments; answers already exist (Brace/Ward/Slip).

## 4. Recommended order

1. **A (Fight Boons) first, in the duel.** Smallest cost, largest reuse, and it attacks the stated problem (build never changes mid-run). Offer picks on a
   Surge meter filled by turns survived and damage dealt so it works WITHOUT waves, then waves later make it richer.
2. **D** alongside (data work).
3. **C** (event bus + tags) once A shows which triggers players reach for.
4. **B** (waves) last and only in dungeons, because it needs its own calibration.

## 5. Measurement before building (so it is not another guess)
- `boonfires`: every boon changes its card/fight (same pattern as `path_nodes_are_wired`).
- Variety metric: distinct boon sets per 100 fights; fraction of fights whose final build differs.
- Power: boons must be a transfer, not a buff. The monster chain would cancel a global buff, so offered boons are valued at X% of a path node and the chain is run ONCE
  after, with boons in the reference player.
- Pace: picks per fight and seconds spent choosing (target: <= 2 picks in a normal fight, none in trash).

## 6. Decisions for the owner
1. Pilot with A (boons in the duel) first — or wave-shaped dungeon fights first?
2. Should boon picks happen in every fight or only in longer ones (elites, bosses, dungeons)?
3. Real-time elements (dodge timing) are out of scope here: they would replace the turn structure rather than build on it. Confirm you want turn-based kept.

## 7. OWNER ANSWERS 2026-10-22 (these override the recommendations above)

1. **Pilot: Gear triggers first** (section 3C), not boons. Card tags + a combat event bus (on_cast / on_crit / on_kill / on_hit_taken / on_round) come first; loot,
   uniques and path nodes gain trigger forms on top.
2. **Boons must PERSIST between fights.** *"The enjoyment of boons in survivor games comes from building a character and not losing your progress between them.
   Enemies who are difficult enough could have a guarantee and normal fights could have a chance."* So section 3A changes from "lasts until the fight ends" to a
   **run build**: boons are kept from fight to fight until a run ends (candidate end points: resting at a post, leaving a dungeon, or death), and are OFFERED by
   chance after normal fights and with a guarantee after difficult ones (elites, bosses, dungeon bosses, modified monsters).
   - Consequence for balance: the monster curve assumes a fresh player each fight. A run build compounds power across fights, so it needs a RUN MODEL in the
     simulator (fights in sequence with boons carried) and an explicit cap or decay, or the chain will cancel it. Decide the run's end point before building.
   - It composes with 3C: triggers are the natural thing for a boon to GRANT (a boon = a temporary trigger or path-rank), which is why gear triggers go first.
3. **Explore real-time elements** (not decided; exploration below).

## 8. Exploring real-time elements (analysis only)

Three levels, cheapest first. All three have to survive that the server is authoritative over TCP, that co-op shares one fight, and that the simulator cannot measure
player skill (it would measure the no-skill baseline, so the monster curve must stay calibrated to that baseline and skill must be pure upside).

| level | what it is | reuses | risk |
|---|---|---|---|
| **R1 timing window on telegraphs** | a telegraphed burst opens a short real-time window; a well-timed Brace/Ward/Slip press gets a bigger reduction (parry) | the 5 (soon ~29) telegraphs, Brace/Ward/Slip, auto-skip pace | latency makes the window feel unfair online; needs a generous window and a no-skill fallback so the sim stays valid |
| **R2 active-time turns** | the monster's countdown runs in real time while the player chooses; waiting is a decision | the whole card system unchanged | rushes the strategy players like; pause/accessibility option needed; co-op sync |
| **R3 action combat** | positioning, dodging, real-time attacks | almost nothing of combat; keeps build layer | a different game; invalidates the sim and the chain; very large |

**Recommendation:** R1 is the only one that adds a survivor/ARPG-style moment-to-moment skill without discarding the card system, and it rides on work already
planned (the telegraph queue). R2/R3 are not recommended before R1 has been played. R1 would be an OPTIONAL skill bonus (no input = the current answer), so it cannot
make the game harder for anyone and the sim stays valid.

## 9. Revised order

1. Card tags + combat event bus + first trigger gear/path nodes (3C), with `triggerfires` probe in the `path_nodes_are_wired` style.
2. Close the telegraph queue (3D), then R1 timing window on top of it (owner to confirm after seeing the telegraphs play).
3. Run build with persistent boons (3A, per section 7.2) once triggers exist to hand out; needs the run model in the sim first.
4. Waves (3B) last, dungeons only.

## 10. RUN-END RULE — SETTLED 2026-10-22

Owner answers: boons last **the entire time the character is alive**; **no slot cap, but boons weaken as you stack**; **lost with the character on death** (permadeath
unchanged, no Sanctuary remnant). Plus: *"Dungeons could also have even better things that only last for the dungeon."*

So there are TWO tiers:
| tier | lifetime | offered by | strength |
|---|---|---|---|
| **Life boons** | the whole life of the character; lost on death | chance after normal fights, guaranteed after hard ones (elites, bosses, modified monsters) | modest each, diminishing as the count grows |
| **Dungeon boons** | until you leave the dungeon (exit, clear, death) | dungeon fights and floor rewards | stronger than life boons (they are temporary), which is what makes a dungeon feel like a survivor run |

### What this commits us to (the balance consequences, so nobody discovers them later)
1. **Life boons are a second progression layer beside Paths**, so they need the same discipline: a **power budget by level**. The expected number of boons a character
   holds at level L must be a known function (offers per fight x fights per level), and total boon power must be bounded.
2. **"Weaken as you stack" is the budget.** Each effect key follows a diminishing curve over the number of boons contributing to it, e.g. the n-th stack contributes
   `base x d^(n-1)` (d ~ 0.85), so the total approaches `base / (1-d)` and can never run away. Stacking the SAME boon is weakest; spreading across keys is strongest,
   which rewards build variety (the survivor feel) instead of one best pick. This reuses the `NON_SCALING_KEYS` / `rank_effect` machinery: a boon is a node effect at
   a rank, with the diminishing factor applied in `get_path_effect_total`.
3. **Dungeon boons live in a separate bucket** that is cleared on dungeon exit, with their own (looser) curve, so a dungeon spike can never leak into overworld power.
4. **The simulator needs a life-build model**: `make_char` gains "expected boons at this level" the way it already gains path spec, and `pathcurve`/`pathspread` extend to
   include boons. The monster chain then runs ONCE with boons in the reference player. A global boon buff will be cancelled by the refit, so boons that matter for
   balance must be per-class (class-filtered pools), same as paths.
5. **Permadeath makes boons a stake**: a long-lived character is worth more, which interacts with the "death risk must fall with progression" target. Keep boon power
   modest enough that it never becomes the main reason a high-level character survives.
6. **Fix the offer rate with data, not taste**: measure fights per level from live `[ENCOUNTER]` telemetry before choosing the chance, so the expected boon count at L100 / L1000 /
   L10000 is a decision, not an accident.

### Still open (smaller, can be decided while building triggers)
- Offer UI: a pick 1-of-3 after the fight on the victory screen vs mid-fight. Recommendation: on the victory screen (zero pace cost).
- Reroll or banish tokens, and whether boons can be seen/managed in the Paths panel (recommendation: a "Boons" strip there).
- Pool size per class (suggest 12-15, filtered by the cards in the current deck).
