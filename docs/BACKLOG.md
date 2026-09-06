# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Keep it current: when work finishes, move it to *Recently
shipped*; when a new direction is agreed, add it in the position its dependencies allow.

Ordering rule: **each item is placed so its inputs are settled first** — measurement before
tuning, data model before UI, combat numbers before anything sized against them. Working out of
order is what forces revisits.

> Detailed design and history live in `docs/design/` and in the assistant project memory.
> This file is the ordering and the status.

---

## ⚑ v0.9.741 SHIPPED — the balance day reached players (2026-09-03)

The 103 commits of 2026-09-02 are live: **client, launcher (both platforms) and server**,
under tag `v0.9.741`. Runtime was byte-identical to r1 (sha256 compared, not assumed), so
launcher users pulled a **14.7 MB content-only update** rather than 38 MB of runtime.

Shipped: the reference-player monster model at every level, apex species, role calibration,
the regeneration cap, the Forcefield anchor, companion durability and scaling, server-authoritative
ability costs, the mage kit re-pricing, the escape ratio fix, the per-encounter flock budget, and
the solo playback fix.

**Found while writing the changelog:** the apex feature was only half built. `is_apex` was
stamped on the monster with the comment *"so the client can mark one in the UI"* — and nothing
ever read it. The entire premise of apex species is that a player learns which ones to fear,
which cannot happen if the game never says which they are. Now carried through the combat state
and rendered as a red **☠ [APEX]** on the enemy health bar, stacking with ELITE rather than
replacing it, plus a help page section and a searchable help topic.

**Release-process notes worth keeping:**
- The `--editor --quit` recompile was done on the main project AND `launcher/` (separate cache)
- Build freshness was verified **by running the packaged exe** with a temp `[BUILDVERIFY]` print,
  as the rule requires. It reported `shared_apex_species=false` on the first pass — which was
  **the probe being wrong** (it named `get_combat_state`, a method that does not exist), not a
  stale build. Corrected probe confirmed client var, `MonsterDatabase.is_apex_species("Hydra")`
  and `CombatManager.FORCEFIELD_SHARE_OF_BAR=0.25` all live in the pck. Five instrument defects
  yesterday, one more today: **check the instrument first** applies to the release process too
- The reference curve is a `.json`; confirmed it loads in production by the ABSENCE of the
  fail-loud `push_error` in the deployed server's journal
- Nobody was connected at swap time (checked `ss` for established connections on 9080), so no
  in-game countdown was needed

**Known-open at ship time, and accepted:**
- Post-combat HP staleness — HP appears to drop BEFORE combat ends and the end-of-fight number
  is the stale one. Needs the HP ledger (instrument `process_monster_turn`), not a fourth guess
- Buff effects (Forcefield) take a beat to appear on the HP bar — same playback-gating family
- High-level fight LENGTH still swings; danger is calibrated, turns are not
- Boss win rate 18-46% — **a user DECISION, not a defect**: *"I'm okay with the bosses currently
  as I think companions and gear will make up the difference"*
- **Forcefield's 3-6x nerf wants a feel check in live play.** It was immunity before, so the
  direction is not in doubt, but 0.25x of the bar is an anchor picked by measurement, not by feel

---

## ⚑ LIVE BUG FIXED — deleting a character stranded its registered companion (2026-09-04)

Owner, from live: *"if a character is deleted while they have a companion in use it doesn't go
back to sanctuary and free up."*

**Cause:** `_award_baddie_points_on_death` returns every registered companion to its Sanctuary
slot — and it was the ONLY place that did. `handle_delete_character` removed the character file
and the account entry and touched nothing else, so the registered slot kept `checked_out_by`
pointing at a character that no longer existed.

**Why it was unrecoverable by hand, which is what makes it worse than it sounds:** that slot
could not be checked out again (*"already checked out"*) and could not be unregistered
(`handle_unregister_companion` refuses with *"currently checked out by <name>"*). From the
player's side the companion, and the registered slot it occupied, were simply gone.

Fixed in two halves:
- **Prevent:** the return logic is now `_return_registered_companions(account_id, character)`,
  called from BOTH the death path and deletion. Extracted rather than copied — a character
  leaving play is a character leaving play, however it happens
- **Repair:** `_heal_orphaned_companion_checkouts` frees any registered slot whose holder is not
  in the account's living character list, keyed on name so a real checkout is never touched. It
  runs at the Companion Stable and at character-select, so an already-broken account fixes
  itself on next login without a migration or an admin. Same repair-on-read shape as the
  threat-quest zero-reward self-heal

Verified against a constructed three-slot case: held-by-living untouched, held-by-deleted freed,
already-free untouched.

- [x] **SHIPPED AND VERIFIED ON LIVE 2026-09-04.** Owner: *"The corrupted goblin sprite is now
      freed up."* Both halves confirmed working — the prevention and the self-heal.

      **A second bug was found by the owner within minutes of the first fix**, and it is the more
      interesting one: the heal originally asked whether a character of that NAME existed, which
      is not the same question as whether that character HOLDS the companion. With permadeath,
      reusing a name is completely normal — the replacement character was also called Dexto, so
      the orphaned checkout looked legitimate and stayed locked.

      The heal now tests **possession**: the recorded holder must actually reference that
      registered slot (by `house_slot`) or the companion id, in their active companion or their
      collected list. A deleted holder fails because it cannot be loaded; a same-named
      replacement fails because it never checked the companion out. Prefers a logged-in
      character's in-memory state over the saved file, since a player mid-session is ahead of
      disk — which is the reported case exactly.

      Worth remembering generally: **a character name is not an identity in a permadeath game.**
      Anything keyed on name across a delete boundary has this bug latent in it

## ⚑ COMBAT VISIBILITY — two things the player cannot see (owner, 2026-09-04)

### An upgraded card should LOOK upgraded (owner 2026-09-04, NOT started)

Owner: *"Upgrading a card and then the card looking exactly the same and the description being
exactly the same sucks."* Listing the upgrades in the description (shipped) is the floor, not the
answer. The ask, in the owner's own sequence:

- [ ] **Preview on the pick screen.** Hovering an upgrade shows YOUR card with that upgrade
      applied — *"if I'm upgrading Analyze and I hover over a Mending upgrade it should show my
      Analyze card with the Mending effect"* — and hovering that preview shows what the card
      would then do. All before committing
- [ ] **The card itself changes.** Once chosen, the upgraded Analyze is visibly a different card
      in the deck screen AND in the combat hand, not the same art with a line of text appended
- [ ] The estimate must follow: `_card_damage_multiplier` still counts only `power` picks, so an
      upgraded card can show an unupgraded number

**Groundwork that already exists:** `card_upgrades.gd` carries `name` + `desc` per upgrade;
`_ability_desc_bbcode` is the single description builder every surface now inherits from; the
hand cell and deck card are both built from one `build_deck_card` path. So a preview is a matter
of composing a card with a hypothetical pick applied, not new plumbing.

### DONE 2026-09-04 — "memorise their positions" was asking the impossible

The rank-up reveal told the player to *"Memorise their positions — they are about to be
shuffled."* The shuffle is `_ms_order.shuffle()` followed by an instant grid rebuild: the cards
TELEPORT. There is no motion to follow, so no player could ever have tracked one. Reported as
confusing, correctly.

The preview exists to show what is IN THE POOL — which is what the original design asked for,
*"shown for a moment, then hidden and placed in a random spot"* — so the header says that now
rather than promising a shell game the code does not implement.

- [ ] Optional follow-up: implement a REAL animated shuffle, which would make the original
      instruction honest and turn the reveal into an actual game of skill. Bigger job; the text
      fix is the correct floor

### DONE 2026-09-04 — five upgrade descriptions said "class resource" for two different things

Owner: *"some of the upgrades need reviewed as they don't make sense like get more of your class
resource if used with a full bar?"* Exactly right, and the cause is wording rather than design.
There are TWO things a card gives back and both were called "your class resource":

- the **spendable bar** — mana / stamina / energy (`_restore_primary_resource`)
- the **class engine** — Momentum / Read / Focus (`_feed_class_engine`)

So Kindling reads as "gain resource while your resource is full", when what it does is convert a
cast that would waste a full bar into engine progress — one of the better picks in the pool. All
five now name what they actually give, and a rule at the top of `card_upgrades.gd` says which
term to use so the next one written does not repeat it.

### Buffs and debuffs need a panel (NOT started)

Owner: *"Buff and debuff info needs a panel in solo and party combat to show what buffs or
debuffs are effecting your characters, party members, or enemies and how long those are going to
last."*

Today a buff announces itself once in the log and then vanishes from view. Nothing shows what is
currently ACTIVE or how many rounds remain — on you, on a teammate, or on the monster. That
makes every duration-based card a guess, and it is most of why buffs are ignored in favour of
damage (the shallow-choice problem in `project_ability_redesign`).

- [ ] One panel serving solo AND party: self, each party member, and the enemy
- [ ] Show remaining DURATION, its current MAGNITUDE, and whether it is STACKING — owner
      2026-09-04, restated with detail after multiple players raised it: *"it would be nice to
      see what buffs and debuffs they have going on and how long they last and how high they
      currently are, if they are stacking, etc."* Presence alone is not enough; the magnitude is
      what tells a player whether re-casting is worth a turn
- [ ] The data already exists: `character.active_buffs` carries `{type, value, duration}` and the
      monster carries its own debuff state (`monster_bleed`, `monster_burn`, stun counters,
      Sabotage stacks). The combat scene already renders per-member status CHIPS
      (`_format_status_chip`) — this is a surfacing job, not a modelling one
- [ ] Interacts with the Duration upgrade family: several card upgrades extend durations, and
      none of that is visible either

### DONE 2026-09-04 — card upgrades were invisible after you picked them

Owner: *"The card upgrades are we sure those are working? I don't see the upgraded information on
my cards in my deck or in combat, they look like the original ones."*

**They were working.** All 48 upgrade ids in `card_upgrades.gd` are read by `combat_manager` —
`executioner`, `bulwark`, `leeching`, `relentless` and the rest all fire. What did not exist was
any way to SEE it: both client reads of `ability_milestone_picks` sat inside the rank-up popup,
the moment of choosing. Afterwards the card rendered identically to a fresh one, so there was no
way to tell an upgraded card apart or to recall what had been taken.

The card description now lists them — stackables collapsed with a count, each name carrying its
effect on hover — and it is added in `_ability_desc_bbcode`, which feeds both the in-combat hover
box and the tooltip, so it reaches the card wherever it appears.

- [ ] **Still open: the card's damage ESTIMATE only accounts for `power`.** `_card_damage_multiplier`
      counts `picks.count("power")` and nothing else, so a card carrying `concentrated` or
      `keen` shows the same number as an unupgraded one. Conditional upgrades arguably should not
      move a flat estimate, but the unconditional ones should

## ⚑ GEAR — the cause was item LEVEL, not drop rate (2026-09-05)

Owner, from live: *"Most fights are a struggle because gear is scarce"*, and the proposed fix was
richer HP/defense affixes with a drop rate to support them. The measurement says the affixes and
the rate were never the problem.

`growref` before: all seven slots FULL, rarity healthy (38% rare-or-better on the Thief), and yet
`itemLv/lv` — average equipped item level as a fraction of character level — sat at **0.24-0.36**
for four of five classes. A level-15 Thief in level-2 gear.

**Cause:** `_generate_item(base, monster_level, ...)` generates loot at the MONSTER's level, and
characters hunt below their own level to survive. Everything they can safely kill drops gear
beneath them. With the down-level XP penalty on top, that is a closed loop — too weak to fight at
level → weaker loot and slower levelling → still too weak.

**Fix:** combat drops generate at `max(monster_level, 75% of the KILLER's level)`
(`DROP_LEVEL_FLOOR_RATIO`, applied in `roll_combat_drops` so every combat path inherits it). It
changes item LEVEL only — not drop chance, rarity, or affix magnitude — and the floor never binds
when you punch above your weight, so killing something bigger still pays better.

| class | itemLv/lv | HP@15 | epic+ |
|---|---|---|---|
| Fighter | 0.26 → **0.59** | 360 → 380 | 14% → **19%** |
| Thief | 0.25 → **0.50** | 341 → **582** | 10% → **33%** |
| Ranger | 0.36 → **0.53** | 328 → **660** | 10% → **29%** |
| Ninja | 0.24 → **0.54** | 300 → **569** | 5% → **24%** |
| Wizard | 0.60 → 0.58 | 399 → 332 | 24% → 10% |

Effective gear level roughly doubled for the four starved classes. The Wizard is flat because it
was never starved — it already hunted near its own level, which supports the diagnosis rather
than contradicting it.

- [x] **No durability inversion — checked, and the ordering holds.** `durability` at n=8:

      | level | 5 | 10 | 15 |
      |---|---|---|---|
      | Fighter | 9.7 | 11.0 | 10.4 |
      | Wizard | 7.0 | 11.1 | 10.1 |
      | Thief | 3.3 | 7.3 | 6.3 |

      Fighter ≥ Wizard > Thief throughout. **This is exactly why `turns_live` exists rather than
      an HP comparison:** the Thief carries MORE total HP than the Fighter at L15 (545 vs 426)
      and still dies in 6.3 turns to the Fighter's 10.4, because the Fighter has 60% damage
      reduction from the stance. Raw HP would have reported an inversion that is not there.
      **RETRACTED — "turn-denial costs survival" was a broken metric.** Owner: *"I'm unsure how a
      stall that builds read, increasing chance of outsmarts success, is causing lower success,
      that doesn't track for me."* It does not, and the mechanism should have been trusted over
      the number. The durability probe gives the monster 200x HP to make the fight unwinnable —
      but **Outsmart ignores monster HP**, so a Grifter could WIN it, and a win ends the combat,
      which the loop scored as a SHORT survival. It was measuring how fast a strategy ENDS a
      fight, not how long it survives. Fixed to discard any fight not ending in the player's
      death. Re-measured:

      | level | Grifter (deny) | Grifter (no deny) |
      |---|---|---|
      | 5 | 4.5 | 4.9 |
      | 10 | 11.5 | 11.9 |
      | 15 | **13.0** | 8.2 |

      Denial is better at L15 and level at L10 — the opposite of the retracted claim, and it
      agrees with the win-rate measurement, which had said so all along (`deny_first` beat
      `assassin` 73% vs 66% at L10 and 68% vs 60% at L20). The Grifter also out-survives the
      Fighter at L15 (13.0 vs 10.1), but by NOT BEING HIT rather than by toughness — its base HP
      is 89 against the Fighter's 210. That is the design working, not an inversion
- [ ] `fights`-to-level readings swung wildly (Wizard L15 460 → 9039). At n=3 that is variance,
      not signal — do not tune progression against it

## ⚑ THE FIGHTER IS FIXED — closed 2026-09-05

Went from the worst number on the board to on-target, by two changes and no guesswork.

**Diagnosis** (`tempo` — cumulative share of the monster's bar by end of turn): the Fighter
removed **6% of a health bar on turn one** against the Thief's 38%, stayed flat until Devastate
cashed at t4, and needed **6.1 turns to kill** against the Wizard's 5.0 and the Thief's 2.1 —
absorbing roughly three times as many monster turns. Its five-turn damage TOTAL already matched
the Mage's (~1.68 bars vs ~1.66), so the fault was timing, never damage. That ruled out raising
`ABILITY_WEIGHTS`, which would have inflated a ceiling that was already correct.

**The trap:** the dead opening was the two buff turns, but `polytest` showed `buff_first` beats
`damage_first`. The Fighter had to buff to survive AND lost the fight by doing it — so the cost
was tempo, and tempo is what got refunded.

**Fix:** warriors open combat with Iron Skin and Fortify already active. Tried at the floor-spend
value first; that failed to resolve it (with floor protection, spending two turns for full
buffs *still* won), so the stance opens at full strength.

| | L1 | L5 | L10 | L20 |
|---|---|---|---|---|
| before | — | 22% | 22% | 8% |
| after | 71% | 55% | 81% | 83% |

**Policy confirmed, not assumed.** `buff_first` won two tournaments against five alternatives —
`damage_first`, `defensive`, `momentum_hold`, and `no_opener` (which drops War Cry to buy back the
last turn the Fighter still spends). It takes L1/L10/L20 and loses L5 to `defensive` by 15pp,
inside the run-to-run variance seen elsewhere. War Cry earns its turn; no further change.

**Knock-on, already applied:** the L20 difficulty anchor had been fitted against the 8% Fighter
and was left over-correcting once the stance landed. Refitted 0.65 → 0.80. **The ordering rule
this makes concrete: monster sizing is DOWNSTREAM of class fixes and must be done last.**

## ⚑ THE WIZARD FALLS OFF AT L20 — the Fighter problem with the classes swapped (2026-09-05)

With the Warrior stance in and the L20 anchor refitted to 0.80, `growtune` at the live settings:

| class | L1 | L5 | L10 | L20 |
|---|---|---|---|---|
| Fighter | 71% | 55% | 81% | 83% |
| Wizard | 85% | 68% | 76% | **41%** |
| Thief | 66% | 71% | 83% | 61% |
| **average** | 74% | 65% | 80% | **62%** |

**The curve is now on target on average at every level** (62% at L20 against the 60% design
target; the rest sit above it deliberately, since flocks, carried damage and failed retreats all
compound on top of a single full-health fight).

What remains is spread. At L20 the Fighter reads 83% and the Wizard 41% — and a single monster
multiplier cannot serve that gap any more than it could serve the 36%-vs-91% spread at L1 earlier
today. Nerfing far enough to rescue the Wizard puts the Fighter at 96%.

- [ ] **Wizard L20 falloff is a CLASS item, not a curve item.** Unaided (scale 1.00) it measures
      **13%** at L20 against the Fighter's 41% and the Thief's 75%. Diagnose it the way the
      Fighter was: `tempo` for when its damage arrives, `durability` for how long it lives,
      `polytest` for whether a better policy exists — before touching any number
- Suspicion worth testing first: the Forcefield recast falloff landed today, and the Mage's
  survival at L20 was the most shield-dependent of any cell (`durability`: 6.0 with the card
  against 3.0 without, pre-fix). The falloff may have cost the Wizard more at L20 than anywhere
  else. If so this is a cost of that fix rather than a pre-existing fault, and the falloff
  constant is the lever

**Measurement caution recorded with it:** the Thief read 75% at scale 1.00 and 61% at 0.80 — a
nerf apparently making a class WORSE, which is impossible. At n=4 characters the run-to-run
variance is real even with the fixed seed, because a code change shifts RNG consumption and
therefore which characters get grown. Treat cell values as ±10pp and trust the row averages.

## ⚑ ALL NINE CLASSES MEASURED — warriors are the weakest archetype (2026-09-05)

First complete table. Grown characters, x1.00 (no monster nerf), tournament policies:

| archetype | class | L1 | L5 | L10 | L20 |
|---|---|---|---|---|---|
| **Warrior** | Fighter | 61% | 55% | 81% | 70% |
| | Barbarian | 53% | **50%** | 85% | 66% |
| | Paladin | 60% | **53%** | 86% | 73% |
| | *average* | *58%* | ***53%*** | *84%* | *70%* |
| **Mage** | Wizard | 76% | 73% | 85% | 78% |
| | Sorcerer | 76% | 68% | 85% | 76% |
| | Sage | 65% | 66% | 91% | 85% |
| | *average* | *72%* | *69%* | *87%* | *80%* |
| **Trickster** | Grifter | 75% | 80% | 98% | 88% |
| | Ninja | **41%** | 66% | 93% | 93% |
| | Ranger | 76% | 73% | 100% | 98% |
| | *average* | *64%* | *73%* | *97%* | *93%* |

**Warriors are last at every level**, and the L5 dip (50-55%) is ARCHETYPE-WIDE — it survived the
opening stance, which lifted all three. It was never a Fighter problem.

### RETRACTED — the "one card until level 10" cause was invented

Owner: *"This doesn't sound correct at all. I think you're confused with some old systems that
need retired/archived. Abilities work off of a deck system with no level gating."* Correct.

Measured directly — a level-1 character's actual `combat_deck_collection`:

```
Fighter  L1  5 cards: cleave, devastate, power_strike, shield_bash, war_cry
Wizard   L1  5 cards: blast, forcefield, haste, magic_bolt, meteor
Grifter  L1  5 cards: ambush, analyze, distract, perfect_heist, sabotage
```

**Every class holds five cards at level 1.** `initialize_deck_collection_if_needed` adds every
available ability with no level check, and nothing anywhere compares an ability's `level` field
against the character's. I read the `level` values in `get_all_available_abilities`, assumed they
gated something, and built a whole causal story on a field nothing consumes.

- [ ] **Retire the vestigial `level` fields on abilities.** They are pre-deck-system leftovers
      that govern nothing, and they actively produced a wrong diagnosis today. Either delete them
      or comment them as unused. A dead field that reads like a live one is worse than no field —
      the same argument as `player_crit_max`, which was a config knob wired to nothing

### The warrior weakness is real; the cause is still open

Warriors measure 58/53/84/70 against mages 72/69/87/80 and tricksters 64/73/97/93, and the L5 dip
is archetype-wide across all three warrior classes. What is known about the mechanism, from
`tempo` (cumulative share of the monster's bar by turn):

- warriors need **~6 turns to kill** where mages take 5.0 and tricksters 2.1
- their five-turn damage TOTAL already matches the mage's, so it is timing, not output
- the opening stance fixed the dead first two turns and lifted all three warrior classes, but
  they are still the slowest to finish

- [ ] Diagnose the residual gap with `tempo` per warrior class rather than guessing again.
      Candidate: Momentum still needs several turns to reach a Devastate worth casting, so the
      class's payoff lands late in a fight that is decided early

### Secondary finding: passives differentiate identity, not power

Within each archetype the three classes track closely (warriors 53-61 at L1, mages 65-76, and
tricksters 75/76 excluding the Ninja's known ramp problem). Since they share all nine cards, the
passives are shaping how a class FEELS without fragmenting balance into nine separate problems —
three archetype curves, nine flavours. That is the desired outcome of the identity pass.

The Ninja at L1 (41%) remains the one genuine outlier, and is already filed.

## ⚑ THE BOOTSTRAP — high-level balance cannot be validated until the early game works

Owner, 2026-09-05: *"We don't have anyone high level until we get the balance right and our to do
list done we probably won't."*

The live population is **L1-L19 apart from a single L45 character**. So every question of the form
"how do high-level players actually behave?" is a question about people the current balance
prevents from existing. That is a circular dependency, and it changes what "get it right" can
mean at different levels:

| range | evidence available | can it be verified? |
|---|---|---|
| L1-L25 | grown characters, real saves, owner's live reports | **yes, now** |
| L25-L100 | `lootsim` (calibrated at L10), fitted gear curve | partly — model, not observation |
| L100+ | extrapolation from the same model | **not until players get there** |

**Consequences for how to work:**

- Do NOT keep deferring on "we should measure high level first". The measurement that would
  settle it does not exist yet and cannot be manufactured — `lootsim` is the best available
  substitute precisely because no real high-level character exists to check it against
- The early game is the gate on everything, INCLUDING the project's own ability to measure. Every
  high-level question stays unanswerable until players can climb
- So high-level work should be *plausible and cheap to revise*, not *perfected*. Anything tuned
  hard against an unvalidated model is likely to be re-tuned once real characters arrive — the
  same lesson the difficulty scale taught three times in one day, one level up
- Conversely, the L1-L25 work IS verifiable today, and that is where every reported live problem
  actually sits: new characters dying, gear scarce, progress stalling

- [x] **SHIPPED as v0.9.751 "Mercy for the bitches..."** (2026-09-05) — client, launcher and
      server, all four platform assets plus the pck split. Runtime byte-identical to r1, so
      launcher users pulled ~15 MB. Owner: *"This game is still very early so we can take risks."*

- [ ] **RE-CHECK PLAYER PROGRESSION PERIODICALLY** — run `bash tools/check_player_progress.sh`.
      It reports the live level distribution and says explicitly whether there is anything new to
      act on. Thresholds it applies:
      - highest **< L25** → still inside the range already measured; nothing to re-open
      - highest **≥ L25** → past what grown characters can reach; re-run `calibrate` to check
        `make_char` against real characters
      - highest **≥ L50** → the high-level balance work can be validated against real data
        instead of the `lootsim` extrapolation; re-open the class table and the difficulty fit

      **Snapshot at ship time (2026-09-05):** 18 characters, 16 at L1-9, 2 at L10-24, highest 19.

      **The L45 Ninja is GONE** — it died to permadeath, and it was the single high-level data
      point `calibrate` used. So make_char's cold end (0.38x a real character's attack at L45) is
      now anchored to nothing at all. Treat every high-level number as model-only until the
      population climbs.



## ⚑ SCOPE WARNING — every class number here covers L1-L20, and the game runs to L10000

Owner, 2026-09-05: *"L20 is nowhere near end game. Not sure such a small level scope is anywhere
near correct."* Correct, and it qualifies everything in the sections below.

**All grown-character measurements taken today span levels 1-20** — roughly the first 0.2% of the
level range. Statements like "the Ninja is strong later (93% at L10-20)" describe the EARLY game
while sounding like they describe the late one. Class balance above L20 is **unmeasured**, not
verified.

**Why the range is what it is, and why that is a real constraint rather than an oversight:**
grown characters have to earn their levels by playing. `growref` needed 1,200-9,000 fights per
character to reach L15, and the requirement curve is `level^2.2` — so L50 costs several times
that and L100 is impractical. The tool that made today's findings trustworthy is also what caps
their reach.

**The way out is the task that was already blocked, and now has its input.** The reason
high-level numbers could not be trusted was `make_char`'s invented gear model, measured at
**2.09x** a real character's attack at L6 and **0.45x** at L45. `growref` now supplies the real
curve — `itemLv/lv` around 0.50-0.60 with a measured rarity mix — which is exactly the reference
needed to fit that model properly. Fit it, and high-level measurement becomes possible again
without growing a character to L1000.

- [ ] **Fit `make_char`'s gear model to the `growref` profile**, then re-run the class table at
      L50 / L200 / L1000 / L5000. Until that happens, treat every class conclusion in this file
      as an EARLY-GAME conclusion
- [ ] Specifically re-open: "the Ninja ramps late" (measured only to L20, where a ramp has barely
      started), "the Grifter's advantage grows with level" (two data points), and the Wizard L20
      falloff (which may be the start of a trend or a single bad cell)
- [ ] The ordering still holds — monster sizing goes last — but the FINAL difficulty fit must
      cover the real level range, not L1-L20

## ⚑ ALL FIVE MEASURED CLASSES, AFTER THE IDENTITY PASS (2026-09-05)

At x1.00 — no monster nerf, grown characters, tournament policies:

| class | L1 | L5 | L10 | L20 |
|---|---|---|---|---|
| Fighter | 61% | 55% | 81% | 70% |
| Wizard | 76% | 73% | 85% | 78% |
| Grifter | 75% | 80% | 98% | 88% |
| **Ninja** | **41%** | 66% | 93% | 93% |
| **Ranger** | 76% | 73% | **100%** | **98%** |

### Ranger — Steady Hand needs LESS, not more

Owner: *"I'm fine with the never glancing but I feel it may need more than just that, you can
measure to find out."* Measured: no-glance **alone** makes the Ranger the strongest class at L10
(100%) and L20 (98%).

That is the mechanism behaving as expected — removing the downside roll is worth more the more
casts a fight takes, so it compounds hardest where fights are longest. Shipping it as no-glance
alone is what made this readable; a second effect stacked on top would have hidden it.

- [ ] Bring Steady Hand down rather than adding to it. Options: glance chance REDUCED rather than
      removed (e.g. halved), or no-glance only below some Read/turn count, or trade it against a
      downside that fits "reliable but unspectacular" — lower crit, or no crit at all

### Ninja — the right shape, a harsh floor

41% at L1 climbing to 93% by L10. Killing Edge escalates from crits, and at level 1 with low DEX
and short fights it never ramps — so the class is genuinely "builds toward crit", which is the
identity asked for, but **41% is the worst cell on the board and it lands on brand-new players**.

- [ ] Raise the floor without flattening the ramp. Options: higher base `crit_chance_bonus` with
      smaller `crit_escalation`, escalation that also triggers on a NON-crit (bad-luck
      protection, which makes the ramp reliable rather than lucky), or a low-level grace
- [ ] Do NOT fix this by nerfing monsters at L1 — that is the mistake the retired difficulty
      scale documents three times over

### Spread

L1 runs 41% (Ninja) to 76% (Wizard/Ranger) — a 35pp gap. L10 runs 81% to 100%. The classes are
distinct now, which was the goal, but distinctness has arrived as a power spread rather than as
different routes to a similar outcome.

## ⚑ THE GRIFTER IS THE STRONGEST CLASS, AND READ IS NOT WHY (2026-09-05)

Current standing at x1.00, grown characters, tournament policies:

| class | L1 | L5 | L10 | L20 |
|---|---|---|---|---|
| Fighter | 61% | 55% | 81% | 70% |
| Wizard | 76% | 73% | 85% | 78% |
| **Grifter** | **75%** | **80%** | **98%** | **88%** |

**A failed nerf, recorded because the null result is the finding.** Long Con's double Read was
changed from guaranteed to a 50% chance specifically to bring the Grifter down. It did nothing —
L1 78→75, L5 78→80, L10 91→98, L20 91→88, all inside the ±10pp run-to-run variance at n=4.

**Read was never the binding constraint.** The Grifter wins through Assassinate ending fights
outright and Outsmart bypassing HP entirely; how fast Read accrues barely matters when the win
condition fires regardless. The nerf was aimed at the lever that was easiest to reach rather than
the one doing the work.

- [x] **A/B DONE — Assassinate carries the class, and Outsmart is nearly redundant.** Four
      policies on the same grown cohort, each removing one piece:

      | lv | deny_first (full) | no_outsmart | no_heist | damage_only |
      |---|---|---|---|---|
      | 1 | 90% | 80% | **51%** | 46% |
      | 5 | 76% | 80% | 75% | 56% |
      | 10 | 98% | 96% | **61%** | 61% |
      | 20 | 85% | 86% | **60%** | 60% |

      Removing **Outsmart costs ~0-10pp**. Removing **Assassinate costs 25-39pp**. And
      `damage_only` (keeps Assassinate, drops the denial cards) falls to 46/56/61/60, so the
      **denial engine is worth ~30pp** in its own right.

      So the class runs on **Assassinate + the stall**, with Outsmart contributing almost nothing.

- [x] **RESOLVED 2026-09-05 — Outsmart retired, Assassinate is the finisher.** Owner chose to
      re-point the pilgrimage first, then pull the ability from all nine classes. Read now feeds
      Assassinate (`READ_HEIST_PER`), which is what the ramp should have been building toward.
      Removed: the ability-bar slot in all four action-bar branches, the `swap_attack_outsmart`
      setting (Game settings renumbered 2-7), `_style_outsmart_button`, the chat command,
      `process_outsmart` / `_party_outsmart` / `_outsmart_chance`, the flavour tables and five
      tuning constants. `outsmart_pct` (Silver Tongue, The Long Con) became `assassinate_pct` so
      the node and the unique keep doing what their text promises. Trial of Mind still credits —
      Assassinate returns `victory_type: "outsmart"`.
- [ ] **The lever to bring the Grifter down is Assassinate's rate, not Read** — halving Read
      already measured as no change at all. Not yet acted on; re-measure now that Outsmart is
      gone, since the A/B above priced a kit that no longer exists
- [ ] Note the Grifter's advantage GROWS with level (75 → 98 at L10) while the Fighter's does
      not. Bypass-HP win conditions scale better than damage against monsters whose HP scales
- [ ] **The Fighter is now the weakest class** (61/55/81/70), and L5 at 55% is under target. It
      was fixed today from 22%, so this is not a regression — but the spread between best and
      worst class is ~25pp and worth watching

## ⚑⚑ THE SIMULATOR WAS DOUBLE-TURNING MONSTERS — ALL PRIOR BALANCE NUMBERS ARE SUSPECT

**Fixed 2026-09-05. Read this before trusting any measurement taken before that date.**

Every fight loop in `real_combat_sim.gd` called the player's action and then
`process_monster_turn` unconditionally. But `process_ability_command` runs the monster's turn
**itself** (`combat_manager.gd:4388`); `process_attack` does not, because that belongs to
`process_combat_action`, which the sim bypasses by calling `process_attack` directly.

Measured, n=200:

| player action | monster turns inside the call | sim then added | total |
|---|---|---|---|
| ability (power_strike) | 1.00 | 1.00 | **2.00** |
| basic attack | 0.00 | 1.00 | 1.00 |

So a cast carried **double** the incoming damage of a swing, purely as an artefact — and under
every policy in the sim the player casts nearly every turn.

**What this taints:** the nine-class table, the archetype comparisons, `refcal` / `rolecal` /
`speciescal` (both `_fight_stats_at` and `run_fight` have the shape), and every difficulty
conclusion drawn from them. It leans against ability play, so the more a class or policy relies
on cards, the harder it measured.

- [x] **Reference player validated (2026-09-05), and the FIRST answer was wrong.** New
      `-- realcheck` audit loads live saves through the game's own Character code and compares
      them to what `make_char` builds at the same level/class/race.

      The first pass reported x1.60 attack / x2.01 defence / +3.6 gear slots and concluded the
      model was 2-3x too strong at low level because "every L1 character has seven empty slots".
      **That was legacy data.** Owner: *"Real characters on the live server have starter
      equipment. Your info looks wrong."* Correct — character creation has granted one common
      piece per slot since 2026-09-03, and EVERY 0/7 character in the saves predates that grant.
      The same legacy-character trap the owner had already flagged for the progression report,
      which is where era-partitioning was added and then not applied here. `realcheck` now skips
      pre-grant saves and reports a MEDIAN alongside the mean, because the population is small
      and contains twinked characters (one L4 wearing item-level 24 gear, 211 attack against a
      model 35) that drag a mean on their own.

      Corrected, current-era characters only (n=6, median):

      | | model vs real |
      |---|---|
      | max HP | x0.99 |
      | resource pool | x1.07 |
      | defence | x1.29 |
      | **attack** | **x0.64** |

      So the reference player is broadly HONEST on durability and resources, somewhat over-armoured,
      and materially UNDER-armed. It was never 2-3x too strong.

- [x] **DEATH LOGS, READ PROPERLY: low-level monster HP is far too high for real player output.**
      Owner challenged a bad reading of mine — I quoted "a L3 player hits for 29", which was a
      single BASIC ATTACK line I generalised from after reading only the first 26 lines of each
      log. *"Players mainly do abilities and should be doing much more than that? Did you look at
      the numbers from the logs?"* Correct on both counts. Parsed in full, players ARE using
      abilities and hitting hard: Cleave 83-130, a "catastrophic blow" of 257, Exploit Weakness
      66, smites of 133-203.

      The real numbers, post-grant deaths, killers AT OR BELOW the player's level:

      | | |
      |---|---|
      | player output | 18-161 damage per round |
      | same-level normal monster HP | 624 (Kobold L2) to 1743 (Mimic L3) |
      | rounds needed to KILL | 8.8 to 47.7 |
      | rounds they actually survived | 1 to 14 |
      | **median** | **the fight needed 4.3x more rounds than the player lived** |

      The sim assumes a same-level normal dies in ~6.5 turns, so it never sees this: its policy
      achieves the ~114+ damage a round that L1 requires, where real players manage 10-80. The
      closest real case (a L2 Ninja at 137/round against an Orc's 1208 hp) needed 8.8 rounds and
      survived 8 — it nearly worked. The worst needed 47x.

      Monsters and the sim agree exactly (Kobold L2 = 624hp/22str in both), and the reference
      player's stats are close (HP x0.99, pool x1.07). The gap is **damage per round**, and it is
      a factor of 2-7 at the levels where new characters live and die.

- [x] **"2-7x damage gap" RETRACTED — measured directly, output is comparable.** Owner's guesses
      were the Read/Assassinate combo and that most players run only 5 cards. Both checked:

      - **Deck size matches.** Every real character carries exactly 5 cards, and so does a sim
        character — `start_combat` initialises the same collection and deals **3-card hands**.
        Casting is genuinely draw-gated in the sim too (`ambush` came up once in 12 turns). Not
        the cause.
      - **Damage per round is comparable**, measured playing whatever is actually in hand:
        Fighter L3 sim 92 vs real 80; Wizard/Sage L2 sim 148 vs real 27-82.

      The "4.3x" figure was time-to-kill divided by rounds-survived, which conflates output,
      survivability and ENTRY HP. The L3 Fighter cited as needing "4.4x longer" had entered at
      **46/204 HP (23%)** — that death was the loop, not the fight.

      **Owner's Read/Assassinate hypothesis is the live one.** For a Trickster, damage per round
      is the wrong metric at all: Assassinate bypasses the health bar, so the class wins by
      stalling to a coin-flip rather than by damage. A stall that fails has spent the whole fight
      producing almost nothing — which is exactly what the L3 Thief and L5 Ninja death logs show.

- [x] **MEASURED: Assassinate is not *a* Trickster win condition, it is the ONLY one.** Owner's
      hypothesis — *"my guess would be read assassinate combo vs straight damage cards"* — is
      correct, and more strongly than expected. Same-level fights, real 5-card deck, 3-card hands,
      n=120 per cell:

      | level | stall -> Assassinate | damage cards only |
      |---|---|---|
      | 2 | **88%** | **0%** |
      | 5 | **88%** | **0%** |
      | 10 | **73%** | **0%** |

      A Trickster playing straight damage never wins a same-level fight — zero of 120 at every
      level. They die around round 3-4 with the monster near full health. Monster HP at these
      levels is simply out of reach of Trickster damage output.

      Draw rates, measured properly (an earlier "ambush once in 12 turns" was a probe artefact —
      forcing a card that is not in hand fails without consuming or refilling, so the hand froze):
      **ambush is in hand on 60% of turns** — about every other draw, as the owner said — but is
      only CAST once per 5 turns, because after playing it sits in the discard until the 5-card
      deck cycles. So **80% of a Trickster's turns are utility or basic attacks**.

      This is what the death logs show: the L3 Thief and L5 Ninja both stalled correctly, whiffed
      the finisher, and had nothing to fall back on — because there is nothing to fall back on.

- [x] **MEASURED: two of three Trickster passives are INERT on the winning line.** Owner's worry:
      *"if Rangers and Ninjas will still be able to play into their passives effectively"*.
      Justified, and stronger than "less effective". A Ninja on the stall line, 100 fights at L10,
      6.7 turns each, casts: analyze 3.07, perfect_heist 1.83, distract 1.28, sabotage 0.49 —
      and **ambush 0.00, basic attack 0.00**. It never makes a damage roll.

      | passive | fires? | why |
      |---|---|---|
      | **Long Con** (Grifter) | ~4.8 casts/fight | analyze/distract/sabotage ARE the denial cards |
      | **Killing Edge** (Ninja) | **never** | crit needs a damage roll; there are none |
      | **Steady Hand** (Ranger) | **never** | nothing to glance |

      This PREDATES the Read-DR change — Assassinate was already the sole win condition — but the
      DR makes the stall stronger, so it widens the gap rather than closing it.

- [x] **Per-class Trickster starter decks + Read pips on the card (2026-09-06).** Ninja now starts
      `analyze, sabotage, ambush x2, vanish, perfect_heist` (vanish is a GUARANTEED crit, so it
      starts Killing Edge's ramp instead of waiting on a 12% roll); Ranger starts
      `analyze, sabotage, exploit x2, ambush, perfect_heist` (exploit is a flat share of enemy max
      HP — no damage roll to fumble — and deliberately no `gambit`, whose failure roll Steady Hand
      cannot protect against). Grifter unchanged and listed explicitly.

      A card granting more than one Read now shows one pip per Read on its face, computed
      SERVER-side and sent with the card. Verified: Grifter denial cards `+◉◉`, ambush `+◉`, Ninja
      `+◉` throughout, and a Grifter with Desperation below a third health shows `+◉◉◉◉` on
      analyze (1 base + 1 Long Con + 2 Desperation) — passive, upgrade and conditional stacking.

- [ ] **WARRIOR AND MAGE DECKS get the same treatment** (owner, 2026-09-06: *"Keep this in mind
      for when we do the warriors and mages as well they each have more cards available in their
      decks that we can swap around to help give them more identity and play towards their
      passives strengths."*). Same method that worked here: measure which cards the winning line
      actually plays, check whether each class's passive can fire on those cards, then swap the
      starter deck rather than changing the passive. Pools available —
      warrior: power_strike, war_cry, shield_bash, cleave, berserk, iron_skin, devastate, fortify,
      rally; mage: magic_bolt, forcefield, blast, meteor, haste, paralyze, banish, frost_nova,
      overload. Passives to serve: Fighter (Tactical Discipline, cost reduction + defence),
      Barbarian (Blood Rage, damage as HP drops), Paladin (Divine Favor, regen + anti-undead),
      Wizard (Arcane Precision, spell damage + spell crit), Sorcerer (Chaos Magic, double damage
      / backfire), Sage (Mana Mastery, cheaper spells + Meditate).

## ⚑⚑ AGREED DIRECTION (2026-09-06): ONE ENGINE SHAPE PER CLASS, NOT PER ARCHETYPE

**Approved by the owner. This supersedes the "make the passives reach the line" question below.**

### The problem, measured

- The three Trickster decks are **80% identical** — `analyze, sabotage, ambush, perfect_heist` are
  in all three; one card per class differs. `gambit` and `pickpocket` are dealt to nobody.
- On the line that actually wins, a Ninja makes **zero damage rolls**, so **Killing Edge and
  Steady Hand fire zero times**. Only Long Con does anything, because the denial cards it keys
  off are what the line plays.
- Giving them damage cards fixed AVAILABILITY and exposed the real issue: playing to your passive
  is a **trap**. Ninja's crit line wins 45%/39% and Ranger's 32%/18% against the Grifter's stall
  at 93%/90%.

### Why the obvious fix was rejected

Making crit and reliability feed Assassinate was proposed and **turned down by the owner**:
*"What you're suggesting makes all three classes feel the same again."* Correct — it would make
three passives into three paint jobs on one button.

### The design

The three engines are not archetype flavour, they are three **shapes**:

| shape | loop |
|---|---|
| **Momentum** | build stacks -> passive defence, spend for a burst |
| **Focus** | build stacks -> passive damage ramp, discharge for a nuke |
| **Read** | build stacks -> raise the odds of a bypass-HP kill |

Nine classes / three shapes = **each archetype gets one of each**, so no two classes inside an
archetype play alike. Owner's own idea (*"interchanging read to 1 class in each archetype... and
the same for momentum, and focus"*). It works because the shapes already exist and are tuned; the
re-theming is what stops it being a reskin.

| | Momentum-shaped | Focus-shaped | Read-shaped |
|---|---|---|---|
| **Warrior** | Fighter — *Momentum* | Barbarian — *Rage* | Paladin — *Conviction* |
| **Mage** | Sorcerer — *Volatility* | Wizard — *Focus* | Sage — *Insight* |
| **Trickster** | Grifter — *The Long Con* | Ranger — *Steady Aim* | Ninja — *Read* |

**Passives may be REDESIGNED, not just re-pointed** — owner, 2026-09-06: *"We can also redesign
class passives as needed to support the new direction."* That removes the main constraint: a
passive that cannot be made to feed its class's engine can be replaced outright rather than
bent. Current passives and how they land:
- **Killing Edge** (Ninja, crit) -> crits grant Read, so the crit build IS the route to the kill.
- **Long Con** (Grifter, double stacks on denial) -> already a build-and-cash loop; the Read DR
  added 2026-09-05 is Momentum's shape exactly.
- **Steady Hand** (Ranger, never fumbles) -> a damage RAMP is the one engine where reliability
  compounds, and it finally has something to act on.

The six warrior/mage passives are NOT yet checked against their proposed engines, and some will
not fit — Divine Favor (regen + anti-undead) has nothing to do with a build-to-execute loop, and
Mana Mastery (cheaper spells) does not obviously feed a bypass-HP finisher. Those are the ones to
redesign rather than force. Do that per archetype, as part of its slice, not up front.

### Trickster slice — needs NO new cards

| class | deck | notes |
|---|---|---|
| **Ninja** | vanish, ambush, gambit, sabotage, **assassinate** | Assassinate becomes Ninja-ONLY and keeps the name; owner: *"assassinate ... fits ninjas better than the grifters"* |
| **Grifter** | analyze, distract, sabotage, **pickpocket**, cash-out | `pickpocket` becomes the cash-out (steal + damage scaling with stacks) — already the theft card, currently dealt to nobody |
| **Ranger** | **exploit**, ambush, analyze, sabotage, aimed shot | `exploit` becomes the discharge — already a flat share of enemy max HP, so scaling it with Aim stays deterministic, which is what Steady Hand is for |

### Warrior slice — SHIPPED to master 2026-09-06 (not released)

The same treatment the Tricksters got: `devastate` is now ONE CARD WITH THREE MECHANICS and the
three Warriors start with different decks, so no two of them play alike.

| class | shape | stack | finisher | deck |
|---|---|---|---|---|
| **Fighter** | Momentum — bank -> passive DR -> burst | Momentum | **Devastate** (spend all, 0.14/stack) | cleave, shield_bash, iron_skin, power_strike, devastate |
| **Barbarian** | Focus — ramp -> discharge | Rage | **Rampage** (0.13/stack) | power_strike, cleave, shield_bash, berserk, devastate |
| **Paladin** | Read — build -> execute | Conviction | **Judgement** (0.10/stack + 2%+3%/stack lethal) | power_strike, war_cry, fortify, rally, devastate |

- The **Momentum damage reduction was narrowed to the Fighter alone**, exactly as the Read
  mitigation was narrowed to the Grifter. Handing all three Warriors the mitigation on top of
  their own payoff is how they ended up playing identically.
- **Barbarian Rage is a passive damage ramp** (+11%/stack to every ability, +55% at cap), applied
  in the shared ability funnel beside the Ranger's Steady Aim.
- **Paladin's Divine Favor is retired.** A 3%-max-HP-a-round regen has nothing to do with a
  build-to-execute loop, and over a long fight it was most of a health bar — which is also why
  the Paladin measured as the strongest Warrior. Replaced with **Retribution**: every blow that
  lands on you builds +1 Conviction, so the Paladin is the one Warrior whose engine keeps turning
  while it is losing. That is what pays for having neither mitigation nor a ramp.

**Measured (60/cell, per-cell seed):**

| class | before | after |
|---|---|---|
| Fighter | 90 / 53 / 65 | **93 / 66 / 68** |
| Barbarian | 81 / 30 / 43 | **98 / 68 / 75** |
| Paladin | 83 / 53 / 65 | **91 / 80 / 80** |

Two iterations were needed and both were the same fault — **sizing a Warrior mechanic by mirroring
a Trickster's totals**, which ignores that the Warrior finisher is multiplied by the stamina dump
(up to 1.5x) and that MOMENTUM_MAX is 5 against COMBO_MAX 8, so a Warrior reaches its cap in about
half the turns. First pass read 95/81/85, 98/68/75, 98/96/91 — the Paladin killing an L80 elite in
8.7 turns where the baseline took 33.8, dominant on BOTH axes at once.

**Paladin is still ~+10pp over the ~70% elite target.** Left alone deliberately: it is inside the
+/-10pp judging band, and the Grifter sits at 88% untouched, so the Paladin is not the outlier.
Revisit after calibration, not before.

### INSTRUMENT FIX (2026-09-06): the class audit now re-seeds PER CELL

`real_combat_sim.gd` seeds once at load, and all nine classes then drew from that one stream in
table order — so changing how the FIRST class plays shifted the stream for the eight after it.
Measured: the Warrior slice moved **Sage L10 51%->70% and Ranger L10 83%->68%** without touching a
line of mage or trickster code. Those are 15-19pp swings against a ~6.4pp sampling error, and they
would have been read as real effects and "fixed".

Same shape as the calibration-orthogonality fault: two things that should be independent were
sharing a quantity. `run_class_audit` now seeds from `hash(class|level|role)`, so a cell depends
only on WHICH cell it is. Verified: untouched classes are now byte-identical across runs, and the
table is stable even across edits to the simulator itself.

**This invalidates cross-run comparisons made before today.** Any earlier "class X moved" reading
where X was not the class being changed is suspect.

### Mage slice — NEXT

Mapping already agreed: **Sorcerer/Volatility** (Momentum-shaped bank-and-burst), **Wizard/Focus**
(unchanged shape, it already IS Focus), **Sage/Insight** (Read-shaped build-to-execute). `meteor`
forks by class the way `devastate` and `perfect_heist` now do.

Open decisions carried from the warrior slice:
- **Mana Mastery (Sage) must be replaced**, same reasoning as Divine Favor: cheaper spells and a
  better Meditate have nothing to do with a bypass-HP finisher. Owner is open to a **class rename**
  too — "Sage" reads as wisdom/sustain, which is the passive being retired.
- **Chaos Magic (Sorcerer)** is thematically right for a Volatility bank but is currently a
  per-cast gamble rather than something that accumulates. Re-point rather than replace.
- Sage is now the clear worst cell in the game (**30% at L30 elite**) and Wizard casts only
  **0.52 c/t at L80** — it is auto-attacking half its turns, which is a POLICY or resource-economy
  fault, not necessarily a class one. Check the instrument before concluding the class is weak.

### Hard constraints

- **A deck is 5 cards + the companion loaner.** Owner: *"any cards over the 5 are a waste as it
  just makes them be drawn less."* Note duplicates DO NOT WORK — the seeding loop assigns
  `collection[name] = 1`, so a repeated name collapses to one copy.
- **Exclusivity is the tuning lever.** A card only one class starts with can be tuned freely; a
  card in all three cannot be tuned for one without moving the other two. That is the answer to
  the owner's *"balance what the cards do that doesn't also break balance on the other 2"* — the
  current 4-of-5 overlap is why there is no headroom today.

### Step 1 DONE (2026-09-06): the nine-class table on the FIXED instrument

60 fights per cell, average gear, zero script errors.

| class | path | L10 normal | L30 elite | L80 elite | turns/fight |
|---|---|---|---|---|---|
| Fighter | warrior | 85% | 56% | 70% | 10-18 |
| Barbarian | warrior | 83% | **33%** | **36%** | 10-17 |
| Paladin | warrior | 86% | 55% | 46% | 14-29 |
| Wizard | mage | **35%** | **15%** | **16%** | 8-19 |
| Sorcerer | mage | 46% | 33% | **10%** | 8-14 |
| Sage | mage | **33%** | **8%** | **15%** | 8-17 |
| Grifter | trickster | **100%** | **98%** | **98%** | **2.8-3.1** |
| Ranger | trickster | 96% | 98% | **100%** | 3.0-3.4 |
| Ninja | trickster | **100%** | **100%** | 98% | 2.9-3.8 |

**Tricksters are not "strongest", they are unbeatable** — 96-100% everywhere, ending fights in
under 4 turns where warriors take 10-29. That is Assassinate: not merely the Trickster's only
line, but the best line in the game by a wide margin. The Read DR added 2026-09-05 widened it.

**Mages are broken** — 8-46%, and casting 0.20-0.33 times a turn against the Trickster's
0.48-0.69, so they are barely acting at all. Worth finding out WHY before tuning numbers:
resource starvation, cost, or hand draw.

**Warriors are closest to sane**, with Barbarian falling off hard at elite (33/36%).

This vindicates doing step 1 first. The OLD (double-turn) numbers had Mages looking healthy
(72-87%) and Tricksters middling — building the engine redistribution on those would have tuned
in exactly the wrong direction.

**What it means for the plan:** making Assassinate Ninja-only removes the dominant line from two
of three Tricksters, which this table says is needed anyway. But the Ninja keeps a ~99% line
unless the finisher itself is toned down, so the slice must re-price Assassinate, not just move
it. Mages need work independent of the engine redistribution.

### The mage "problem" was the simulator, not the mages (2026-09-06)

Owner asked me to diagnose and fix mages after they measured 8-46%, worst of every archetype.
**There was nothing to fix.** The audit's mage policy was playing them badly:

- every branch was gated (magic_bolt needs >25% mana, meteor needs Focus 3, forcefield needs
  HP <70%), and **`haste` — Arcane Surge, in the mage STARTER DECK — appeared nowhere at all**;
- so a hand of {haste, forcefield, meteor} at full health with low Focus cast NOTHING and threw
  a basic attack, which is not what any player does.

A gate should express a preference, not a refusal. The rotation now casts Arcane Surge before the
nukes it multiplies, and ends with a catch-all that plays anything still castable before swinging
a staff.

| class | before | after |
|---|---|---|
| Wizard | 36 / 20 / 23 | **85 / 71 / 75** |
| Sorcerer | 35 / 20 / 10 | **86 / 75 / 76** |
| Sage | 28 / 11 / 8 | **95 / 60 / 76** |

Casts per turn went 0.28-0.47 -> 0.72-0.91.

**The casts-per-turn column was also lying**, separately: it inferred a cast from "did the class
resource fall", which cannot see one whose cost is covered by regen. Mages regenerate mana every
round. Counted in the engine now (`_cards_played`), on the shared path every class reaches.

**A mage opening ward was added and then REMOVED.** It was designed off the false diagnosis that
mages had no mitigation layer. A/B'd once the policy was fixed: with 85/71/75, 86/75/76, 95/60/76;
without 95/70/80, 88/71/66, 83/58/60 — differences swinging both ways inside the +/-10pp noise at
n=60. It measured nothing, so it is gone rather than left in as an unjustified buff.

**The corrected nine-class table** (and note this restores "warriors are weakest", now for real):

| class | L10 | L30 elite | L80 elite |
|---|---|---|---|
| Fighter | 85% | 56% | 70% |
| Barbarian | 83% | **33%** | **36%** |
| Paladin | 86% | 55% | 46% |
| Wizard | 95% | 70% | 80% |
| Sorcerer | 88% | 71% | 66% |
| Sage | 83% | 58% | 60% |
| Grifter | 100% | 100% | 100% |
| Ranger | 93% | 98% | 100% |
| Ninja | 98% | 98% | 100% |

- [ ] **Tricksters at 93-100% are the outstanding balance problem.** Fights end in ~3 turns
      against everyone else's 7-28. That is the finisher, and the Trickster slice must re-price it.
- [ ] **Barbarian 33/36 at elite is the weakest cell in the game** and wants its own look.

### ⚠ STOP TUNING RELATIVE STANDING — it is a treadmill (owner, 2026-09-06)

Owner: *"you added mitigation to the warriors and the tricksters... but since it seems warriors
are back towards the bottom it seems like we are working in circles a bit."* Correct, and worth
naming as a rule.

What happened: Warriors got an opening stance (60 DR) to fix the Fighter at 22%. Tricksters got
Read DR to fix "a whiff is a funeral". Mages got a ward, since removed. Each was individually
justified by a real measurement — and each moved the RELATIVE standing, so whoever was left
became "the weakest" and invited the next buff. That is a treadmill, not convergence.

**The rule from here: tune every class against the ABSOLUTE targets, never against each other.**
`ROLE_TARGETS` already states them — a normal fight should cost ~40% of a health bar, an elite
~65%, a boss ~80%. A class is "fine" when it hits the target, not when it beats its siblings.

Applied to the corrected table, this says something quite different from "warriors are weakest":

| | vs an absolute target |
|---|---|
| Tricksters 93-100%, fights over in ~3 turns | **massively OVER** — the one real problem |
| Mages 58-95% | roughly in band |
| Warriors 33-86%, Barbarian 33/36 at elite | **UNDER at elite**, worst cell in the game |

So the answer is not another warrior buff. It is re-pricing the Trickster finisher (which the
slice was already going to do) and looking at Barbarian/Paladin at elite on their own merits.

**Read DR was A/B'd against this standard and KEPT, narrowly.** Without it Tricksters measure
98/100/100, 91/98/100, 96/95/100; with it 100/100/100, 93/98/100, 98/98/100 — a 2-3pp difference,
inside noise. So it is NOT the cause of Trickster dominance. It stays because the case it fixes
is the UNGEARED early player the death logs describe (whiff survival 83%, still-won 62%), which a
geared sim character never encounters. Worth re-testing once the finisher is re-priced.

### DIAGNOSIS: "warriors are weakest" decomposed (2026-09-06)

Owner: *"when you say weakest do you mean they can survive the least number of hits or their
ability damages are too low... we should ensure we're examining the problems from multiple
possible angles instead of just applying bandaids."* Right — a win rate is a SYMPTOM, and it
falls for opposite reasons that want opposite fixes.

The class table now reports **k** (turns needed to KILL) and **d** (turns it can SURVIVE)
alongside win%. A win is k < d, so the two numbers say which side of the fight is failing.

| class | L10 k/d | L30 elite k/d | L80 elite k/d |
|---|---|---|---|
| Fighter | 10.1 / 20.1 | 17.7 / 20.8 | 20.1 / 29.6 |
| Barbarian | 10.6 / 17.8 | **21.6 / 20.8** | **23.6 / 22.9** |
| Paladin | 14.3 / 24.2 | **29.2 / 27.7** | **37.3 / 31.7** |
| Wizard | 7.4 / 21.2 | 11.8 / 21.1 | 20.5 / 42.2 |
| Sorcerer | 7.7 / 16.9 | 12.4 / 20.6 | 12.3 / 22.8 |
| Sage | 8.8 / 17.6 | 15.2 / 19.1 | 14.2 / 23.5 |
| Grifter | 3.3 / 18.4 | 2.8 / 31.7 | 2.7 / 38.4 |
| Ranger | 3.5 / 17.2 | 3.6 / 22.0 | 3.2 / 41.0 |
| Ninja | 3.2 / 21.7 | 2.7 / 36.8 | 3.3 / 29.3 |

**Findings:**

1. **Survivability is broadly EQUAL** — d is 17-42 turns for every class. Warriors are mid-pack,
   not fragile. "Warriors are weakest" is not a durability problem.
2. **Time-to-kill is what diverges** — Tricksters 2.7-3.6, Mages 7.4-20.5, Warriors 10.1-**37.3**.
3. **Every losing cell is k > d** (Barbarian 21.6>20.8, Paladin 29.2>27.7 and 37.3>31.7).
4. **Warriors are not over-buffing.** Measured turn allocation at L30: warriors spend **80-82%**
   of turns on damage cards, mages **37-42%** — and the mages still kill faster. So the warrior's
   long TTK is low damage PER CAST, not wasted tempo.

**Consequence, and it matters:** the warrior opening stance (a SURVIVABILITY buff) treated the
wrong side of the equation. It worked — Fighter 22% -> 85% — by stretching d, when the root cause
is k. That is the bandaid pattern, confirmed by measurement rather than suspected.

**STRUCTURAL: monster-HP tuning cannot touch Tricksters.** Their finisher bypasses the health bar,
so their k is not "turns of damage", it is "turns until the coin flip lands". Any global
difficulty change — the whole refcal chain — moves warriors and mages and leaves Tricksters at
93-100%. The finisher has to be re-priced DIRECTLY; there is no curve setting that fixes it.

### Angles NOT yet verified — the honest gaps in the picture above

- **Variance.** k and d are means. Fighter L30 has k17.7 < d20.8, which predicts a win, yet it
  wins only 56% — so spread decides nearly half those fights. The k/d model is mean-field and
  says nothing about the tails.
- **Healing and regen are not in d.** Paladin's Divine Favor regenerates 3% a round, so its real
  durability exceeds HP/damage-taken. Probably why Paladin at k37.3 > d31.7 still wins 46%.
- **Monster ability escalation over long fights is not modelled.** Enrage stacks, DoTs and
  specials compound with fight length, so a 30-turn fight is worse than three 10-turn fights.
  This penalises slow classes SUPERLINEARLY and would make the warrior picture worse than k/d
  suggests. Worth measuring next.
- **Companion damage share is UNMEASURED.** An attempt failed twice (the message parse matched
  nothing, and Assassinate zeroing a dummy monster produced 2.5 billion "damage"). If companions
  contribute a large fraction, class damage differences are muted and the TTK gap is smaller than
  it looks.
- **Resource sustainability across 20-37 turn fights** is untested; `min_res_pct` exists in
  run_fight and is not being reported.
- **Trickster k is not comparable in kind** to the other two archetypes, per the structural point
  above. Do not read 2.7 as "six times better damage".

### TODO: Magic Bolt — damage vs investment is opaque and punishing (owner, 2026-09-06)

Owner: *"Seems like investing a small amount gets a pretty high amount of damage proportionally
to a large amount. It's very hard for a player to have any idea how much mana they should invest
before it isn't worth it... Does magic bolt even still compete with the other options? It should
have the highest top end of the mage's options but not make players ignore other options."*

Measured, L30 Wizard, mana pool 232, ceiling (`MAGIC_BOLT_FULL_SPEND_PCT` 0.20) = 46:

| mana | % of pool | damage | dmg per mana |
|---|---|---|---|
| 4 | 2% | 70 | 17.6 |
| 11 | 5% | 251 | 22.8 |
| 23 | 10% | 496 | 21.6 |
| **46** | **20%** | **1091** | **23.7 <- peak** |
| 92 | 40% | 1432 | 15.6 |
| 174 | 75% | 1502 | 8.6 |
| 232 | 100% | 1765 | 7.6 |

Alternatives on the same turn: **Blast 568**, **Meteor 1161**.

**Three separate problems, and they want different fixes:**

1. **The efficiency cliff is invisible.** Value per mana peaks exactly at the ceiling and falls
   **3.1x** beyond it. Nothing in the game says 46 is the number. The card now names the spend
   ("at N mana", added 2026-09-06) but not that spending more is progressively wasted.
2. **Below the ceiling the curve is nearly FLAT** (17.6-23.7 dmg/mana from 2% to 20%). A 4-mana
   poke is ~74% as mana-efficient as the ideal cast, so the "commit your bar for a nuke" identity
   does not actually exist — chip casting is fine, which is the owner's observation exactly.
3. **It loses to Meteor at sensible spends.** Meteor 1161 > Bolt's efficient 1091. Bolt only wins
   by dumping 40%+ of the pool INTO the efficiency penalty. So the honest ranking today is
   "cast Meteor, unless you are emptying the bar" — the opposite of a flexible signature spell.

**Design target to hit:** highest top end of the mage kit (it has that: 1765) WITHOUT making the
other options pointless, and with a spend the player can reason about.

- [ ] Decide the shape first, then tune: should overspend be flat-value (no penalty, no bonus),
      mildly rewarding, or keep a soft cliff that the UI actually communicates?
- [ ] Whatever the shape, the card must show the **efficient spend**, not just the chosen one —
      the sweet spot is a number the player currently has no way to discover.
- [ ] Re-check against Blast and Meteor after any change: the test is that all three stay worth
      casting, not that Bolt wins.
- [ ] Note `MAGIC_BOLT_MIN_EFF` is 0.80, which is why the sub-ceiling curve is so flat. That
      constant is the main lever for problem 2.

### Finisher re-pricing CANNOT come first — measured 2026-09-06

I started the Trickster slice by re-pricing the finisher, on the grounds that Tricksters measure
93-100%. That ordering was wrong, and the measurement says why.

**Change made and KEPT: a missed finisher now spends the Read it was built on.** A miss used to
cost only the turn, so the player retried at identical odds — at ~2.9 attempts a fight a 75%
gamble compounds into a near-certainty, which is how a "high-risk, high-reward" card ended up
with no risk in it. The old Outsmart spent the stacks on a miss ("it has seen that one before")
and that risk was dropped when Assassinate replaced it. Restoring it re-prices the card WITHOUT
touching the odds, so a landed finisher is exactly as good as it was. Attempts per fight fell
from ~2.9 to ~1.0.

**But it barely moved the table** (Grifter 98/100/100 -> 95/98/100), and here is the reason:

| class | lvl | win% | by finisher | by damage | attempts | odds when cast |
|---|---|---|---|---|---|---|
| Ninja | 10 | 67% | **100%** | **0%** | 1.38 | 48% |
| Ninja | 30 | 34% | **100%** | **0%** | 0.82 | 47% |
| Grifter | 10 | 77% | **100%** | **0%** | 1.38 | 50% |
| Grifter | 30 | 49% | **100%** | **0%** | 0.98 | 50% |

(Ungeared characters, so lower than the geared audit — but the SPLIT is the point.)

**Every win comes from the finisher. None from damage.** So the finisher's odds ARE the class win
rate, and there is no correct value for them: price it low and all three Tricksters become
unplayable, price it high and the fight is decided by one roll. Nudging it can only trade one
failure for the other.

**Therefore the engine redistribution is a PREREQUISITE, not a follow-up.** Grifter and Ranger
need a different way to win — the Momentum-shaped and Focus-shaped loops already agreed — before
the finisher can be priced as what it is meant to be: the Ninja's genuine gamble. Build the
engines first, then price the finisher against a class that has an alternative.

- [ ] Re-price the finisher AFTER the Grifter and Ranger engines exist, not before.
- [ ] Re-test the Read DR at that point too — it was kept on probation and its justification
      (surviving a whiff) changes once a whiff is no longer the whole fight.

### TRICKSTER SLICE — engines built and measured (2026-09-06)

**One card, three MECHANICS.** The finisher's name and lines already forked by class; now what it
DOES forks too, which is what actually makes them play differently. No new cards were needed.

| class | shape | the finisher does | stacks also give |
|---|---|---|---|
| **Ninja** | Read | gamble that bypasses the health bar (unchanged) | odds |
| **Grifter** | Momentum | guaranteed burst, magnitude scales with the Read it SPENDS | passive DR |
| **Ranger** | Focus | discharges the aim, deterministic, never fumbles | +7% damage per Read to EVERYTHING |

Constants: `GRIFTER_CASHOUT_PER_READ` 0.16, `RANGER_AIM_DMG_PER` 0.07, `RANGER_SHOT_PER_READ` 0.11.

**The headline is not the win rate, it is the fight.** Trickster fights went from **2.8-3.2 turns
to 6.3-32.8**. They now build and cash instead of instant-winning, and their kill times (6.5-34.8)
sit in the same range as the warriors' (10.1-37.3) rather than a fifth of it.

**Read DR is now GRIFTER-ONLY.** Giving it to all three handed every class a second engine's
payoff on top of its own, and it showed once fights got long: Tricksters were surviving 41-98
turns against the warriors' 18-32. The Grifter is the Momentum-shaped one, so the defence is its
payoff; the Ranger has the damage ramp and the Ninja has the odds.

**A policy fault was found and fixed on the way,** the same shape as the mage one: the simulator
cast the finisher the instant it appeared in hand, with no Read check. Fine for a gamble, ruinous
for a banked-stack payoff — it threw the whole con away at one stack, and the classes measured
23%/13%. With `_finisher_is_ready` gating the spend they read 95%/91%. **Audit how the simulated
player plays a class before believing the class is broken** — twice in one day now.

Current table:

| class | L10 | L30 elite | L80 elite |
|---|---|---|---|
| Fighter | 85% | 56% | 70% |
| Barbarian | 83% | **33%** | **36%** |
| Paladin | 86% | 55% | 46% |
| Wizard | 90% | 73% | 78% |
| Sorcerer | 83% | 73% | 73% |
| Sage | 78% | 58% | 78% |
| Grifter | 95% | 90% | 96% |
| Ranger | 91% | 81% | 86% |
| Ninja | 96% | 96% | 100% |

- [ ] **Judge these against ROLE_TARGETS, not each other** (see the treadmill rule). At an elite
      target of ~65%: Tricksters 81-100% are OVER, mages 58-78% are about right, warriors 33-56%
      are UNDER. Both ends need work, independently.
- [ ] **The Ninja is still the outlier** at 96/96/100 in 6-9 turns. Its gamble is now the only
      bypass-HP effect in the game, so it can finally be priced as one without taking two other
      classes down with it — which was the whole point of doing the engines first.
- [ ] Barbarian 33/36 at elite remains the weakest cell in the game.

## ⚑⚑ ROOT CAUSE FOUND: the game pays you 75% of a monster turn for NOT attacking

**This is the piece the class table kept pointing at and none of the per-class fixes could reach.
Found 2026-09-06 while pricing the Ninja. Needs an owner decision — do not tune around it.**

`process_ability_command`: any ability returning `buff_ability: true` gives the monster only a
**25% chance to act**. Eleven abilities carry that flag, and `analyze` denies the turn outright.
Damage cards never deny anything. So a non-damage cast buys, on average, **0.75 of a free monster
turn** — and that is worth far more than any mitigation in the game.

Measured, monster turns actually taken per player turn (L30, playing the real hand):

| class | damage cards cast | monster ACTS | monster DENIED | elite win% |
|---|---|---|---|---|
| Fighter | 82% | 75% | 26% | 56% |
| Ranger | — | 67% | 33% | 81% |
| Grifter | — | 54% | 47% | 90% |
| Wizard | 37% | 47% | 53% | 73% |
| Ninja | 23% | 34% | **66%** | 96% |

**Win rate tracks denial rate almost perfectly.** The Fighter eats 2.2x as many monster turns as
the Ninja, which is a durability multiplier that has nothing to do with HP, defence or mitigation
and does not appear anywhere in the k/d decomposition.

**This explains every symptom we have chased:**
- "Warriors are weakest" — they cast 82% damage cards, so they eat 75% of monster turns.
- Why the warrior opening stance helped: it is a free buff, i.e. free denial, not just DR.
- Why lowering the Ninja's finisher odds did nothing: it survives long enough to keep retrying.
- The `polytest` note already in the warrior stance comment — *"buff_first BEATS damage_first
  (88% vs 71% at L20)"* — was this effect, seen from one class and never generalised.

**Why it cannot be tuned around:** every per-class fix so far has been buying back tempo the
system takes from damage-heavy kits. That is the treadmill the owner identified, and this is the
engine driving it.

- [x] **DONE 2026-09-06 — owner chose "2 plus a reduced 1".**
      - **Per-ability**: only cards that do NOTHING BUT defend earn a reprieve —
        `forcefield, fortify, iron_skin, cloak, paralyze`. Offensive buffs (`war_cry`, `haste`,
        `overload`, `rally`) now buy no tempo at all: they are damage with extra steps.
      - `distract` and `sabotage` were removed too. Reducing the incoming hit (-43% accuracy,
        -16% strength) is already their whole effect, so also skipping the turn paid them twice —
        and those two are exactly what the Trickster kit spams.
      - **Reduced**: the reprieve is an EDGE, not the game. 75% -> **40%**
        (`DEFENSIVE_REPRIEVE_CHANCE`).

- [x] **NINJA ASSASSINATE REDESIGNED — owner's proposal, and it breaks the trap.** Owner: *"would
      lowering the chance further but it still dealing damage be a valid option. Read could
      increase the damage it does with each point and also increase the chance it's a lethal
      attack at a low enough chance that falls into balance."*

      While the card was a pure coin flip its odds WERE the class win rate, so no value for them
      was correct: 96% at elite when high, an unplayable class when low, and lowering them only
      lengthened fights because the Ninja survived to keep retrying. Now the strike ALWAYS lands
      (`NINJA_STRIKE_PER_READ` 0.11, so a full stall is ~0.9 of a health bar) and Read also buys
      a LOW lethal chance (`NINJA_LETHAL_BASE` 2 + 3 a stack, ~26% at full). Read is spent either
      way. The gamble is finally an upside rather than the whole outcome.

      Ninja went 75/93/95 -> **61/78/78**, with fights 8.6-12.8 turns -> 13.7-20.4.

### The table after both changes

| class | L10 | L30 elite | L80 elite |
|---|---|---|---|
| Fighter | 88% | 51% | 55% |
| Barbarian | 78% | **35%** | 43% |
| Paladin | 90% | 51% | 55% |
| Wizard | 78% | 63% | 61% |
| Sorcerer | 68% | 53% | 75% |
| Sage | 51% | **31%** | 51% |
| Grifter | 71% | 56% | 78% |
| Ranger | 83% | 50% | 60% |
| Ninja | 61% | **78%** | 78% |

**Elite spread went from 33-100 (67pp, with three classes at 90-100) to 31-78 (47pp).** No class
now wins by bypassing the game. Against a ~65% elite target the remaining outliers are Sage 31
and Barbarian 35 at the bottom, Ninja 78 at the top.

- [ ] Sage 31% and Barbarian 35% at elite are now the weakest cells — take them on their own
      merits, not relative to each other (see the treadmill rule).
- [ ] Mages lost ground when `haste` stopped buying tempo (Sage 78 -> 51 at L10). Check whether
      that is correct — Arcane Surge is an offensive buff, so losing the reprieve is principled,
      but the Sage may need something back elsewhere.

### Sequencing (agreed)

1. **Re-measure the nine-class table on the FIXED instrument** first. Everything currently
   committed (double-turn fix, Read DR, decks, poison, crit consolidation) is unvalidated, and
   tuning an engine redistribution against stale numbers repeats the mistake that produced them.
2. **Build the Trickster slice**, measure, iterate. It is where the death logs, a baseline, and
   three known-broken passives are.
3. **Then warriors and mages**, using whatever the slice teaches.

Do NOT do all nine at once: nine untested classes with no way to attribute what broke.

- [ ] **Chase the x0.64 attack gap before fitting the curve.** It biases in a direction that
      matters: a model player who kills more slowly makes every fight measure longer and costlier,
      so refcal would weaken monsters to hit its targets and the live game would come out easier
      than designed. n=6, so confirm it against more characters before acting.
- [ ] **A high single-fight win rate at L1 is not by itself evidence of a problem.** With the
      reference player no longer suspect, the corrected instrument's easy L1 fights sit fine
      beside the owner's report that the early game feels about right — because the difficulty
      players actually meet lives in the LOOP (flocks, ambushes, no healing between fights,
      permadeath), not in one same-level fight. Any curve fit that targets single-fight cost
      should be checked against a grown-character run before it is trusted.
- [ ] **Re-measure the nine-class table.** The standing "warriors are the weakest archetype"
      (58/53/84/70) is the prime suspect: warriors are ability-heavy, so they absorbed the
      artefact hardest. Do not act on that finding until it is re-measured.
- [ ] Re-check the difficulty conclusions that drove the early-game work. The player-side fixes
      (escape scaling, the gear-level floor, the warrior opening stance) were validated against
      grown characters and live reports as well, so they are not automatically wrong — but the
      MAGNITUDES were sized against this instrument.

**The fix is at the source, not in the loops:** the engine sets `monster_turn_resolved` when an
action has settled the monster's turn (taken, or deliberately skipped), and the sim has one
guard, `_monster_turn_if_owed`, that advances the monster only when it has not. A convention
kept in the sim alone would drift again the next time an engine path changes.

## ⚑ Death replay / shareable combat log (owner direction 2026-09-05)

When a player dies, the broadcast chat message should carry a **clickable link** that lets
anyone open the combat log for that fight — and better still, a **replay** of the battle, so
the death can be watched rather than guessed at.

Owner: *"when a player dies, the chat message should have a clickable item that allows everyone
to view the combatlog or even better yet a replay of the battle to see what happened and how
they died."*

Notes for whoever picks this up:
- The log is already structured per-beat (actor / target / damage metadata rides beside each
  line for the floating numbers), so a replay has real data to work from rather than prose.
- Chat already renders clickable `[url=...]` payloads — see `_bbcode_meta_safe`, which exists
  because an unescaped payload once turned the whole log into raw markup.
- Death is permadeath, so this is also the only chance anyone gets to see that character fight.
- Scope question to settle first: store the log server-side keyed by a death id (shareable to
  everyone, survives logout) versus shipping it to the client in the broadcast (cheap, but only
  players online at the time can open it).

## ⚑ LIVE BUGS FIXED 2026-09-05 (in tree, NOT yet deployed)

**Assassinated dungeon monsters never died.** Reported live: *"a spider attacked them from
seemingly out of nowhere when they rested"* and *"the spiders seem to be spawning right next to
them, in the spaces they were just standing."* Owner's hypothesis was exactly right. Clearing a
dungeon entity depended on the VICTORY DICTIONARY carrying `dungeon_monster_id` back to the
server, and only the ordinary-kill dict did. Assassinate builds its own return and omitted it, so
the server fell through to the legacy `_clear_dungeon_tile` branch, `m.alive` stayed true, and the
"dead" spider was still standing on the grid beside the player — walking back onto them on the
next move or rest tick (`handle_dungeon_rest` calls `_move_dungeon_monsters`). Both symptoms, one
cause. Fixed structurally: the server now remembers the entity id from combat START
(`dungeon_combat_monster_id`) instead of trusting each return shape, so any victory path present
or future clears the monster. Verified: 73/73 assassinations now carry the id.

**Three parallel crit systems.** Screenshot showed the same Ambush printing "Ambush (critical) —
243" one round and "★ CRITICAL! ★ · Ambush — 198" the next. There were three: the general ability
crit, a hardcoded 50%/1.5x roll inside Ambush, and the Wizard's `spell_crit_bonus` rolled inline
in three spell branches — silently, printing no line at all. They stacked multiplicatively and
the private ones ignored crit escalation and the Ranger's no-crit rule. Consolidated into one
roll: `ABILITY_CRIT_BONUS` expresses a card's crit affinity as a bonus to the player's OWN chance
(so crit gear finally matters on Ambush, which is the Ninja's whole build), and `spell_crit_bonus`
is folded into `player_crit_chance`. Ambush's weight 0.20 → 0.23 to hold its average output.
Measured after: old-style labels 0 everywhere, Ranger 0 crit and 0 glance, Ninja 39% vs Grifter
27% on Ambush, Wizard 14% on Bolt.

**The client kept a stale copy of the class passive table.** `_get_class_passive` was a hand-copied
"mirror" and had drifted badly: it advertised the Grifter as *Backstab* (+15% crit, retired), the
Ranger as *Hunter's Mark* (retired), and the Ninja as *Shadow Step* (+40% flee) — which is the
GRIFTER's effect. Two classes shown swapped on the character-creation screen. `character.gd` grew
a static `class_passive_for()` and the mirror now calls it. There is no longer a mirror.

**Long Con was invisible.** Reported: *"I'm testing a Grifter and it's not getting extra read."*
It was firing; the log printed the same `◉ Read n/m` either way, so a 50% passive could not be
observed. Now prints **LONG CON!** with `(+2)`.

**Analyze reported odds the game never rolled.** It carried its own copy of the chance maths with
18.0*log WITS scaling against the real 9.0, a flat +20 Trickster bonus against +10, double the
level penalty and a cap of 85/70 against 48. Now calls the single source and reports Assassinate.

## ⚑ CRIT AND GLANCE — SHIPPED to the tree 2026-09-05

Abilities were deterministic: they always hit and could never crit. Now they are bracketed on
both sides, and the pair is close to power-neutral by construction.

- **Crit on abilities** at full chance with a smaller multiplier (`ABILITY_CRIT_DAMAGE` 1.25 vs
  the basic attack's 1.5), because `ABILITY_WEIGHTS` are anchored and were tuned with no crit in
  them. Crit chance is now ONE definition — `player_crit_chance()`, extracted from ~60 inline
  lines in `calculate_damage` so the ability path cannot drift from the attack path
- **Glancing blows** rather than misses. A true miss costs the resource AND the turn, and under
  permadeath a whiffed Meteor at low HP is a death rather than a setback. A glance deals 60%
  instead of 0%, keeps the "abilities can fail" logic, and pairs with crit as a band around the
  expected value. Chance is `20 − (DEX − monster_speed/2)`, clamped 5–35, so accuracy reduces it
- Mutually exclusive: a cast is sharp, ordinary, or fumbled
- Companion strikes route through the same funnel and are excluded — that is the companion's hit

**Measured across the curve** (grown characters, tournament policies):

| | L1 | L5 | L10 | L20 |
|---|---|---|---|---|
| before | 75% | 71% | 93% | 94% |
| after | 72% | 69% | 86% | **80%** |

The L20 fall is larger than the −1.8% headline because glance COMPOUNDS over a long fight and
L20 fights run longest — a fumble costs more in a drawn-out fight than a short one. That is the
intended shape, and it pulled the curve toward target without touching a monster stat.

**Two things this unblocks:**
- The **Ninja crit identity** is now buildable at all. Crit reaching 1% of actions was why it had
  nothing to stand on
- **DEX finally does something for casters** — it reduces glance chance, so the stat 6k found
  feeds nothing for tricksters now matters on every cast. Narrow enough not to breach the owner's
  third-stat caution: it is accuracy, not a second damage stat

## ⚑ STAT DESIGN — abilities are the game, and the stats do not say so (owner, 2026-09-05)

Owner: *"each class or archetype should have a main stat they focus (wit for tricksters) and a
secondary that is good for their particular class... This should also be apparent to the players
so they know what to focus. What we want to be careful of is not making it where classes get too
much from a third stat... Abilities should be the primary focus with attack being a slightly
worse or situational fallback."*

And the fact that drives all of it: *"players mainly use abilities every turn they can instead of
just attacking. Players are rarely using attack unless they are out of resources or drew a bad
hand."*

### What is already right

Archetype main stats match the intent: ability damage scales on **strength** (5 warrior cards),
**intelligence + 0.5×wisdom** (4 mage cards) and **wits** (2 trickster cards), via
`_ability_stat_ratio`. Gear that grants +STR/+INT/+WITS feeds this correctly —
`get_effective_stat` includes equipment bonuses.

### What is broken by the same fact

- **`attack` gear affixes are near-dead.** `get_total_attack()` = `strength + bonuses.strength +
  bonuses.attack`, and it feeds **basic attacks only**. The `attack` affix is separate from
  `+strength` and never touches ability damage. A player casting every turn gets nothing from it
- **Every crit affix is near-dead** for the same reason — crit is rolled only in
  `calculate_damage`, the basic-attack path. That includes the whole epic+ crit chase pool
  (`crit_chance_bonus`, `crit_damage_bonus`), which is the rarest loot in the game
- **Secondary stats do not exist per class.** Mages share WIS (half-weight toward INT for every
  mage class); tricksters nominally have DEX, which feeds NO damage at all; warriors have nothing
  secondary. So the "secondary that helps whichever class you picked" is not implemented anywhere
- **Ability coverage is thin for tricksters** — only `ambush` and `gambit` scale on WITS. The rest
  of the kit routes WITS through other channels (Outsmart chance `min(22, 9*log2(WIT/10))`,
  debuff magnitude `15 + WITS/3`), which is fine mechanically but invisible as a build direction

### The design to build toward

- [ ] **Main stat per archetype, secondary per class, and both stated in the UI.** The Character
      Stats page already had to be corrected once today for describing stats that do not do what
      it claimed — this is the same failure at design level rather than text level
- [ ] **Guard the third stat.** Owner's explicit caution: a class drawing meaningfully from three
      stats outscales one drawing from two. Any secondary should be narrow (a class mechanic)
      rather than a second damage stat
- [ ] **Re-price attack as the fallback it is.** Either reduce its effectiveness or fold it into
      the same scaling as abilities, so it reads as "slightly worse or situational" rather than a
      separate and largely irrelevant axis
- [ ] **Decide crit-on-abilities** (see the crit section). Owner is open to it if solo and party
      can both be balanced. Recommended shape: full crit chance on abilities with a SMALLER
      multiplier than basic attacks (one constant, halves the inflation, trivially revertible),
      measure, and fall back to re-fitting `ABILITY_WEIGHTS` only if the inflation persists
- [ ] **Sequencing:** all of this is player-power change, so it lands BEFORE the final difficulty
      fit. Doing it after would invalidate that fit a fourth time — see the retired difficulty
      scale for the three times it already happened today

## ⚑ NINE CLASSES, THREE CARD POOLS — the identity gap is structural (owner, 2026-09-05)

Owner: *"we will want each class in each archetype to have their own identity. All three warrior,
mage, and trickster identities should feel different enough that you know you're playing them."*

**Card access is keyed to `get_class_path()` — the ARCHETYPE — not to the class.**
`get_all_available_abilities` matches on the path and appends one of three fixed lists, and
`grep -c 'class_type ==' shared/character.gd` returns **0**: there is not a single
class-specific ability grant anywhere in the file.

| archetype | the 9 cards ALL three classes draw |
|---|---|
| warrior | power_strike, war_cry, shield_bash, cleave, berserk, iron_skin, devastate, fortify, rally |
| mage | magic_bolt, forcefield, blast, meteor, haste, paralyze, banish, frost_nova, overload |
| trickster | analyze, distract, pickpocket, ambush, vanish, exploit, assassinate, sabotage, gambit |

So the nine classes are three classes with three stat-curve variants each. Everything that
distinguishes them is one passive plus per-level gains:

| class | passive | per-level gains |
|---|---|---|
| Fighter | −20% stamina cost, +15% defense | STR 1.25 / CON .75 / DEX .25 / WIT .25 |
| Barbarian | +3% dmg per 10% HP missing (max +30%), +25% stamina cost | STR 1.5 / CON .75 / DEX .25 |
| Paladin | +3% combat regen, +25% vs undead | STR .75 / CON 1.0 / DEX .25 / WIS .25 / WIT .25 |
| Wizard | +15% spell damage, +10% spell crit | INT 1.10 / WIS .75 / CON .40 / DEX .25 |
| Sorcerer | 25% double damage, 5% backfire | INT 1.40 / WIS .50 / CON .35 / DEX .25 |
| Sage | −25% mana cost, +50% meditate | WIS 1.0 / INT .75 / CON .5 / DEX .25 |
| Thief | +35% crit damage, +10% crit chance | WITS 1.5 / DEX .75 / CON .25 |
| Ranger | +25% vs beasts, +30% XP, +15% gathering | WITS 1.0 / DEX .75 / STR .25 / CON .5 |
| Ninja | +40% flee, no damage on a failed flee | DEX 1.25 / WITS 1.0 / CON .25 |

### And TWO of the trickster passives do nothing in a normal fight

- **Thief — Backstab is inert.** Its whole passive is crit, and crit does not apply to abilities
  (see the section above); a Trickster casts nearly every turn. The class's entire identity fires
  only on basic attacks it rarely makes
- **Ranger — Hunter's Mark is not a combat passive.** +25% vs beasts is situational and +30% XP /
  +15% gathering are out-of-combat. Against a non-beast the Ranger has no passive at all
- **Ninja — Shadow Step works**, and is the only trickster identity that functions as intended

So of three trickster classes, one has a working combat identity, one has a situational one, and
one has an identity that cannot fire. That is the concrete form of "they don't feel different".

### Shape of the fix (design pass — NOT before the Fighter and the gear curve)

- [ ] **Class-exclusive cards are the lever with the most identity per unit of work.** Two or
      three per class, replacing shared slots rather than adding to them, so decks stay the same
      size and the roster does not inflate. The architecture already supports per-card gating —
      dungeon and companion cards are appended the same way
- [ ] **Fix the two dead passives first** — they are cheaper than new cards and the Thief cannot
      have a crit identity until the crit-on-abilities decision is made
- [ ] Owner's specific direction: Thief flees easier, Ninja builds crit, Ranger takes the middle
      ground — note this SWAPS the current Thief and Ninja passives (see below)
- [ ] Warriors and mages are better differentiated than tricksters but still share every card;
      the same question applies to Barbarian / Paladin / Sorcerer / Sage

## ⚑ CLASS IDENTITY WITHIN AN ARCHETYPE — the three tricksters are nearly one class (owner, 2026-09-05)

Owner: *"the thief should be the one that can flee easier, ninja should be able to build towards
crit which needs actual viability and ability support, ranger should have its own place or be the
middle ground in this. Same type of thing for the other classes."*

**The passives that exist today are INVERTED against that intent:**

| class | passive | effects |
|---|---|---|
| **Thief** | Backstab | **+35% crit damage, +10% crit chance** |
| Ranger | Hunter's Mark | +25% vs beasts, +30% XP, +15% gathering |
| **Ninja** | Shadow Step | **+40% flee, no damage on a failed flee** |

The Ninja owns escape and the Thief owns crit — the exact swap of what is wanted. Ranger's
passive is utility (XP / gathering / beasts): *a* place, but not a combat identity, and the only
one of the three that does nothing in a fight against a non-beast.

The other two archetypes are better differentiated already — Fighter (−20% stamina cost, +15%
defense) / Barbarian (+3% damage per 10% HP missing, +25% stamina cost) / Paladin (+3% combat
regen, +25% vs undead); Wizard (+15% spell damage, +10% spell crit) / Sorcerer (25% double
damage, 5% backfire) / Sage (−25% mana cost, +50% meditate).

**Crit viability — WORSE than "unsupported": crit does not apply to abilities at all.**

Owner 2026-09-05: *"Regarding crit it doesn't work with abilities I don't believe so it's uses
are limited."* Correct, and it is the root of the problem rather than a side note.

`calculate_damage` rolls the full crit calculation — DEX-based chance, the 75% cap, Backstab's
+10%/+35%, weapon rarity crit, companion crit, and every epic+ `crit_chance_bonus` /
`crit_damage_bonus` chase affix — and it runs on **basic attacks only**. Ability damage rolls
crit through exactly one path, `spell_crit_bonus`, which is the **Wizard's** passive (Arcane
Precision, +10%), at three sites, all mage cards.

So for a Trickster — who spends nearly every turn casting — DEX crit, the Backstab passive and
the entire epic+ crit chase pool are close to dead weight. "Ninja builds toward crit" is not
short of support; the stat does not function on the actions the class takes.

**MEASURED 2026-09-05: basic attacks are 1% of player actions — 10 out of 973.** Owner said
players *"rarely use attack unless they are out of resources or drew a bad hand"*, and the number
is starker than that: with resources and a hand available, the policies essentially never attack.

So crit reaches **1%** of what a player does. DEX crit, the class passives built on it, and the
entire epic+ crit chase pool (`crit_chance_bonus`, `crit_damage_bonus` — the rarest loot in the
game) are ~99% inert. `attack` gear affixes are in the same position, being basic-attack-only.

*(An earlier version of this measurement read 59% and was wrong: the counter was global while its
denominator was local, so basic attacks from hundreds of character-GROWTH fights were divided by
the actions of twelve measured ones.)*

- [ ] **Decide crit-on-abilities — now the highest-leverage itemization fix available**, not a
      nice-to-have. At 1% coverage the alternative is to stop selling crit as a build direction
      at all, which also means the Ninja cannot have a crit identity
      - Recommended shape: full crit CHANCE on abilities with a smaller multiplier than basic
        attacks (one constant, halves the damage inflation, trivially revertible). Measure, and
        fall back to re-fitting `ABILITY_WEIGHTS` only if inflation persists
      - Ability weights are anchored and were tuned with NO crit in them, so expect roughly
        `crit_chance x (multiplier - 1)` of uniform damage inflation — ~12% at 25% crit
      - Solo and party share the damage paths so the average is identical; party differs in
        VARIANCE, where several crits in one round can delete a monster and disturb the pacing
        work already done
- [ ] Either way this gates the Ninja crit identity above — there is no point adding crit support
      cards to a stat that does not fire

**"Double cast" buffs — they are not double casts.** Owner: *"Buffs that provide a chance to
double cast and such don't really specify what that entails, can it double any ability?"*

- `extra_turn_chance` (*of Frenzy*, *of Haste*, Swift rank-up) sets `skip_monster_turn`: the
  monster does not act, so you move again first. The extra turn can be spent on ANY ability, but
  it never re-casts the triggering one. It **only rolls on damage-dealing hits**, and never on
  actions that already skip the monster's turn (Analyze, Pickpocket) so they cannot double up.
  Bounded — per-cast roll, not recursive
- Sorcerer's Chaos Magic `double_damage_chance` is double DAMAGE on that cast against a 5%
  backfire, on two mage cards. Not a second cast
- [ ] **Player-facing text fix.** Neither the affix names nor their descriptions say any of this:
      not that it is a turn rather than a cast, not the damage-only condition, not the
      no-double-up rule. Same class of defect as the card upgrades that showed no upgrade text

**Do not start before the Fighter and the gear curve** — it is a design pass, and it wants the
combat numbers settled underneath it. Ideas for when it does start:

- swap Backstab and Shadow Step so the identities match intent, or rebuild both
- give the Ninja crit *support* (a card that guarantees or escalates crit, crit-on-kill chains,
  crit-triggered riders) so the stat has somewhere to go
- give the Ranger a combat identity, or deliberately make "reliable middle" the identity and
  price it as one
- **ask the same question of warriors and mages** — "the same type of thing for the other
  classes" was the ask, and Barbarian / Paladin / Sorcerer / Sage were not audited here

## ⚑ TWO MITIGATION LOOPS, ONE REAL — test the ECONOMICS, not the shape (2026-09-05)

Both looked identical from the outside: a card recast every turn that stops the player being
hurt. One needed bounding and one did not, and the difference is the resource maths.

### Forcefield — renewable, and it WAS the problem

`durability` measures monster turns survived in an unwinnable fight (monster HP x200), which
counts defense, Iron Skin, the Warrior stance and shields — none of which show in a max-HP
comparison. Identical Wizard build, with the card and without:

| level | 5 | 10 | 15 |
|---|---|---|---|
| Fighter | 8.1 | 6.9 | 5.7 |
| Wizard **with** Forcefield | 10.5 | 7.0 | 6.0 |
| Wizard **without** | 5.1 | 4.6 | 3.0 |

Stripping it halved the Mage's survival, and without it the archetype ordering was already
correct. **So the Fighter's durability was never the fault — the card was.** Base HP is Fighter
210 > Wizard 148 > Thief 89 at L15, exactly right; the Mage was out-tanking the bruiser on 30%
less HP. Owner: *"Fighter should be more durable than the Mage typically."*

Fixed on **renewability, not magnitude** — the per-cast value is anchored to a share of the
health bar and was already rebuilt once for being oversized, so cutting it again would only make
the panic button weak. Each recast within a fight now absorbs 55% of the previous
(100/55/30/17%), resetting between fights.

**Verified at n=8** (the n=3 figures were kept only until a better sample existed):

| level | 5 | 10 | 15 |
|---|---|---|---|
| Fighter | 7.5 | 6.6 | 5.8 |
| Wizard (fixed) | 6.5 | 6.7 | 4.3 |
| Wizard, no Forcefield | 4.2 | 4.5 | 3.1 |

Fighter ahead at L5 and L15 and level at L10, with the shield still buying ~50% more survival
than going without. The archetype ordering the owner asked for, and the card is still worth
casting.

### The Trickster stall — bounded already, and a change would have broken the class

Owner: *"Before the only chance they had was to stall via monster turn skips (which also built
read) and then attempt to outsmart once it was built. If it failed they had a very hard time
with most other tactics aside from assassinate success. Gambits risk of self damage on an
already squishy character was death back then as well."*

The 16-turn stall was pencilled in as a second loop. **It does not exist.** At n=3 the Thief L15
cell read 16.0; re-measured at n=8 it reads **4.1**. The whole thing was one lucky character.

**And the explanation I gave for it was numerology.** I wrote that `analyze` costs a flat 5
energy against a L15 pool of ~81, so 81/5 ≈ 16 casts "landing exactly" on the measurement. That
arithmetic is real but it was fitted to a single outlier after the fact — presenting coincidence
as mechanism, which is the same error this file catches everywhere else. Recorded rather than
quietly deleted, because a confident wrong explanation is more dangerous than a wrong number.

What the larger sample actually shows: denial is **worse or equal to plain damage at every
level** — 3.0 / 4.0 / 4.1 against `damage_only`'s 4.7 / 6.9 / 4.9. There is no lock to bound, and
the reason not to touch the Trickster is simply that there was never anything there.

The design point still stands on the owner's account alone: stall-to-build-Read-then-Outsmart is
the class's intended and only survival path, and cutting it without a replacement would return
the Trickster to "a failed Outsmart is death".

**The transferable rule: Forcefield costs a PERCENTAGE of a pool that regenerates, so it renews;
Analyze costs a FLAT amount against a pool that does not, so it depletes. Same surface shape,
opposite economics.** A sweep for "renewable mitigation" must test the resource maths, not the
pattern — and must ask what a class would do instead before removing its only survival path.

## ⚑ THE FIGHTER IS THE WEAK CLASS — and the Thief never was (2026-09-05)

Measured with `growtune` at x1.00 (no monster nerf), grown characters, tournament-winning
policies, 4 characters x 15 fights per cell:

| class | L1 | L5 | L10 | L20 |
|---|---|---|---|---|
| **Fighter** | **36%** | **15%** | **31%** | **8%** |
| Wizard | 91% | 65% | 83% | 25% |
| Thief | 75% | 81% | 76% | 55% |

**Through level 10 the Wizard and Thief are at or above the 60% target with no help at all, and
the Fighter is 2-5x weaker at every level.** That is a class-balance fault, not a monster-curve
fault, and a single difficulty multiplier cannot serve a 36%-vs-91% spread: nerfing enough to
rescue the Fighter puts the other two above 90%.

The Fighter's worst cell is **L5 at 15%**, against Wizard 65% and Thief 81% at the same level.

- [ ] **Fighter class-side fix — belongs to 6c.** Do NOT hide it by weakening every monster in
      the game.

      **What has been ruled OUT already:**
      - *Strategy* — `buff_first` won its own tournament against three alternatives at every
        level, so the Fighter is being played as well as we know how
      - *Gear starvation* — `growref` at L15 gives the Fighter ATK 79 / HP 289 against the
        Wizard's ATK 43 / HP 325. It out-attacks the Wizard comfortably
      - *Raw per-cast damage* — `ABILITY_WEIGHTS` as shares of a health bar: Warrior cleave 0.28
        / power_strike 0.22 / shield_bash 0.16, with Devastate at 0.14 PER MOMENTUM (0.56 at
        Momentum 4, matching the Mage's 0.55 Magic Bolt). Over five turns the Warrior totals
        ~1.68 bars against the Mage's ~1.66. On paper these are equal

      **So the loss is not in the numbers, it is in WHEN they arrive.** The documented design is
      "reliable and sustained, with the highest ceiling in the game behind the longest setup" —
      but a normal fight is ~5 turns, and the Warrior spends two of them on Iron Skin / Fortify
      and several more building Momentum, so its ceiling lands about when the fight is already
      decided. The Mage's ceiling is available on turn one. Front-loaded beats back-loaded when
      fights are short, and short fights are what trash monsters are.

      Note the Wizard also ends up with MORE total HP than the Fighter at L15 (325 vs 289),
      which inverts the archetype: the bruiser is not the tanky one.

      - [x] **MEASURED — hypothesis confirmed.** `tempo` records the cumulative share of the
            monster's bar removed by the end of each turn (3 grown characters x 12 fights,
            tournament-winning policies):

            | level 5 | t1 | t2 | t3 | t4 | t5 | kill_t | win% |
            |---|---|---|---|---|---|---|---|
            | **Fighter** | **6%** | 12% | 24% | 52% | 66% | **6.1** | 22% |
            | Wizard | 14% | 34% | 62% | 77% | 88% | 5.0 | 83% |
            | Thief | 38% | 50% | 63% | 69% | 72% | **2.1** | 75% |

            The Fighter removes **6% of a bar on turn one** against the Thief's 38%, stays flat
            until Devastate cashes at t4 (24%→52%), and needs **6.1 turns to kill** against the
            Wizard's 5.0 and the Thief's 2.1. It absorbs roughly three times as many monster
            turns as anyone else, and that is the whole 22%-vs-83% gap. Same shape at L10.

      - [ ] **THE TRAP, and why the fix is not "fewer buffs".** The dead opening IS the two buff
            turns — but `polytest` proved `buff_first` beats `damage_first` (88% vs 71% at L20),
            so the Fighter must buff to survive AND loses the fight by doing it. Both are true.
            The fix is therefore to make the buffs cheap in TEMPO rather than to remove them:
            enter combat with them already up, extend the duration so they are not recast, or
            make them free actions. Raising `ABILITY_WEIGHTS` is the wrong lever — the totals are
            already equal (~1.68 bars vs the Mage's ~1.66) and it would inflate a ceiling that
            is correct
      - [x] **The HP "inversion" was mine, not the game's.** By formula a L15 Fighter has 196
            base HP against a Wizard's 141 — correct for the archetype. The measured 289-vs-325
            came from the sim's equip rule, `ATK*2 + DEF + HP*0.1`, applied class-blind: a Mage's
            attack is nearly irrelevant to its damage, and HP at 0.1 scored a +20 HP item level
            with +1 attack. Now scored on each class's real damage stat (INT+WIS/2 for mages,
            WITS for tricksters per 6k, attack for warriors) with HP at 0.25. **Gear-curve
            numbers taken before this used the old rule.**
- [x] Difficulty scale retargeted accordingly: **1.00 through level 10** (the curve is not at
      fault there), **0.65 at level 20** (the collapse IS universal — Fighter 8%, Wizard 25%,
      Thief 55%). Reads roughly Fighter 55% / Wizard 70% / Thief 66% after

### The correction underneath this

An earlier version of this fit produced 0.80/0.55 anchors and was **committed**. It was measured
with AI policies that never raised the Mage's shield and never cast the Trickster's kill card, so
it would have shipped monsters far weaker than the game needs. It also produced the claim that
the **Thief was "structurally broken"** and beyond help from any nerf — the Thief wins 55-81%
once played properly, healthier than the Fighter at every level.

**Fifth instrument defect of the day, and the only one that reached a committed balance change.**
The lesson that generalises: a balance number measured through an agent that plays badly is a
measurement of the agent. Tournament the policy BEFORE fitting anything to it.

## ⚑ THE PERMADEATH ARITHMETIC — why no monster tuning could ever have worked (2026-09-05)

**If losing a fight means dying, a 60% win-rate target IS a 40% death rate per fight** — death
every 2.5 fights. Levelling costs several hundred fights, so survival is not unlikely, it is
arithmetically impossible; even a **95%** win rate dies around fight 20. To survive the fights a
level costs, the death rate has to be near **0.2%**, which no win-rate target reaches.

**Therefore escape, not win rate, is the load-bearing survivability mechanic.** Monster tuning
changes how OFTEN you are in a losing fight; it can never change what happens when you are.
That is why the recovery fix, the XP fix and the monster nerf each measured as real improvements
and none of them moved survival.

Owner, from live: *"It's difficult to flee too as it is chance based"* and *"the only current
survival is clever use of cards and abilities"* — which in practice largely means knowing when
to leave.

**SHIPPED (committed, NOT deployed — owner asked to hold until the pass is coherent):**
- **Desperation flee** — +40 points scaling with health lost, floor 25→35. At 25% HP escape goes
  51%→81%. A fight you are winning is unaffected
- **Difficulty scale** on monster HP and strength — 0.80 to L10, 0.55 at L20, flat beyond. Fitted
  with `growtune` against grown characters; Fighter L1 36%→70%, L20 5%→81%
- **Rest ambush 15%→5%** (one named `REST_AMBUSH_CHANCE`, was two inline literals)
- **Level-2 XP cliff** 5.6x→2.4x, identical from level 9 up
- **Over-level XP bonus 0.7→2.0** — five levels up now pays +141% instead of +49%
- **XP computed from PRE-nerf monster stats**, so a difficulty nerf cannot quietly slow progression

## ⚑ THE SIM WAS NOT PLAYING THE GAME — four AI defects (2026-09-05)

Owner: *"I'd like to know your strategies on each character type to ensure the problem isn't our
strategy or ability and outsmart use."* It was. Cast-site count across every policy:

| card | cast sites | what it is |
|---|---|---|
| `perfect_heist` (Assassinate) | **0** | the Trickster's win condition |
| `analyze` | **0** | in its curated deck; skips the enemy turn |
| `forcefield` | **0** | the Mage's damage shield |
| `pickpocket` / `phantom_strike` / `vanish` | 0 | |

The curated trickster deck is Analyze / Distract / Sabotage / Ambush / Assassinate / Sabotage and
the policy played four of them. **Every Thief/Ranger/Ninja number produced before this was
invalid.** Fixing it, with nothing in the game changed:

| class | before | after |
|---|---|---|
| Thief | 4 encounters, 26% win | **15 encounters, 40% win** |
| Wizard | 3 encounters, 40% win | **6 encounters, 54% win** |
| Fighter | 5 encounters, 39% win | unchanged (policy already complete) |

- [x] **Warrior tournament DONE — null result, and a useful one.** Four strategies on the same
      grown cohort (3 characters x 20 fights per cell, difficulty scale applied):

      | lv | buff_first | damage_first | defensive | momentum_hold |
      |---|---|---|---|---|
      | 1 | 61% | 45% | **65%** | 56% |
      | 5 | **56%** | 46% | 53% | 46% |
      | 10 | **75%** | 51% | 50% | 51% |
      | 20 | **88%** | 71% | 55% | 61% |

      The default wins everywhere but L1, where `defensive` leads by 4pp — inside noise at n=60.
      No change to the Warrior. Three lessons that generalise: buff uptime PAYS for its tempo
      (`damage_first` loses everywhere); reacting defensively mid-fight is a TRAP (`defensive`
      collapses to 55% at L20 — once you are losing the answer is to leave, not to turtle, which
      is the same conclusion the permadeath arithmetic reached); and banking Momentum to 6 is
      worse than spending at 4.
- [ ] Extend `polytest` to Mage and Trickster. Their policies were just fixed by hand and gained
      a lot (Thief 4→15 encounters), which is exactly the situation where a tournament finds more
- Note: there is **no player `wait`/defend action** (attack / ability / flee / outsmart /
  special), and `process_special` is a stub returning `success:false`

## ⚑ GEAR DOES NOT KEEP PACE WITH LEVEL — measured (2026-09-05)

Owner: *"gear is scarce"*, and *"making HP or Defense more effective or common on equipment along
with a drop rate that supports it"*. `growref` grows characters and reports what they actually
earned. `itemLv/lv` is average equipped item level as a fraction of character level:

| class | lv | slots | itemLv/lv | rarity c/u/r/e+ | ATK | HP | fights to get there |
|---|---|---|---|---|---|---|---|
| Fighter | 15 | 7.0 | 0.30 | 52/33/5/10% | 79 | 289 | 1682 |
| Wizard | 15 | 7.0 | 0.44 | 48/14/33/5% | 43 | 325 | 680 |
| Thief | 15 | 7.0 | 0.14 | 38/29/19/14% | 41 | 140 | **6088** |
| Ranger | 15 | 7.0 | 0.18 | 33/52/10/5% | 43 | 203 | 6550 |
| Ninja | 15 | 7.0 | 0.16 | 38/19/38/5% | 34 | 152 | **8942** |

- **Equipped items sit at 14-44% of character level.** A level-15 Thief wears level-2 gear. Gear
  does not lag progression, it barely moves
- **Epic+ is 0-14%**, and the CHASE pool (crit, `damage_mult`, resource-on-hit, +ability ranks) is
  epic-and-above ONLY — so those affixes are effectively unobtainable in normal play
- **Fights to reach level 15 range from 680 (Wizard) to 8942 (Ninja)** — a 13x spread between
  classes for the same level. Measured with the broken trickster AI, so it will narrow, but not
  by 13x
- [ ] Owner's proposal — HP/defense more effective and more common, with a drop rate that
      delivers — is the change this data indicts. Measure with `growref` before and after

## ⚑ THE EARLY GAME IS LETHAL, MEASURED BY GROWING A CHARACTER (2026-09-05)

Owner: *"the game is very difficult right now. Most fights are a struggle because gear is
scarce... you need to do it from the creation with starter gear and level it up like a player
would have to. Maybe by doing this you'll see how difficult it currently is."*

**Why no previous audit saw this.** Every gear model in the simulator INVENTED a loadout.
`calibrate` measures the cost: the invented L6 player hits **2.09x** a real character's attack,
the invented L45 player **0.45x**. The sim has been flattering the early game and starving the
late one. `newplayer` reported 48% at L1 because it measures a FRESH, FULL-HP character against
ONE monster — no carried damage, no flock, no failed retreat.

### The `grow` audit — nothing invented

`grow` builds a character the way `handle_create_character` does (one common piece per slot with
the upward tier search, curated starter deck, Home Stone companion) and plays it forward using
only real code: `roll_drops` off the monster's own table, items worn only if EQUIPPING them
raises power through the real aggregators, chance-based `process_flee`, flock chains with no rest
between links, the real rest loop (10-25% max HP per tick, 15% ambush per tick), the real
down-level XP penalty, real stat-point spending, and the game's own gathering catch rollers.

**Result at L1, full starter kit, competent card play:**

| class | lived | died at | win% | worst HP on a win | heals interrupted |
|---|---|---|---|---|---|
| Fighter | 0/8 | 1.1 | 33% | 39% | 56% |
| Wizard | 0/8 | 1.1 | 43% | 45% | 30% |
| Thief | 0/8 | 1.3 | 24% | 58% | 29% |

**24/24 die before level 2**, against a 60% design target for a normal fight. This is not a
naive-AI artifact: the harness runs this file's class policies, which hold Iron Skin and Fortify
uptime, hold Devastate until Momentum is high, and cycle builders by affordability.

### The starter companion carries ONE class

| class | with companion | without | delta |
|---|---|---|---|
| Fighter | 22% | **5%** | +17pp |
| Wizard | 22% | 22% | 0pp |
| Thief | 13% | 13% | 0pp |

The Fighter is unplayable without it. Wizard and Thief get nothing measurable from the same
tier-1 pool. Companion aggro IS modelled (real `process_monster_turn`; `base_aggro` default 25,
clamped 0-80, **-45 for evasive**) — so the likely cause is that an evasive companion soaks
almost nothing, which is worth checking before any companion tuning.

### Owner corrections, applied

- **XP was wrong: 13 fights to L2, not 29.** `experience_to_next_level` starts at the default
  100; `pow(level+1,2.2)*50` only takes over after the first level-up. The real cliff is
  **L2->L3, which jumps to 560** (~70 fights). Measured, not read
- **Gathering XP was missing.** Job XP converts to character XP at taper 1.0 under job level 20,
  so one-for-one for a new player, and a tier-1 catch pays 3-15 against 8 for a kill. Modelled at
  the owner's 20%-of-movement figure for L1-2, decaying to 5% by L10 — and it carries the same
  ambush risk, because *"to gather they still have to be in danger"*
- **Retreating to a post is a gamble, not a free heal.** *"Real players can't make it back to the
  post very often without getting ambushed."* Five moves in the open at 15% each = 44% success

### Still unmodelled

- [ ] **Ability rank-ups — the simulator has NEVER applied them.** `ability_effect_ranks` appears
      in `real_combat_sim.gd` only as a gear affix name; neither `make_char` nor the grow loop
      ranks a card up, so every measurement it has ever produced omits what a levelling player
      upgrades. Owner thinks it unlikely to close the gap; still the largest known omission
- [ ] The harness cannot yet reproduce a survivor, and live has characters at L16, L19 and L45.
      Owner: *"The only current survival is clever use of cards and abilities."* So the residual
      gap is play skill above the fixed policy — which means **this harness measures the FLOOR**:
      what happens to a competent-but-not-expert player. That floor is death before level 2

### Consequence for the plan

Owner chose "fix the player model first" for the curve, then recovery and early XP. Growing
reference characters is blocked on survivability — a reference fitted to characters that could
not have survived is not worth having. **So the order inverts: make the early game survivable
first, then grow the reference at every level, then normalise `species_power` and run the chain.**

## ⚑ RESOLVED IN PART — the 47pp gap was not what it looked like (2026-09-04, evening)

The prescribed test was run: *"measure normal win rate with a fresh independent probe and see
which audit is right, rather than assuming `roles` is."* The `adjudicate` audit runs BOTH
measurement paths in ONE process on ONE curve, 90 fights per cell.

| level | `_fight_stats_at` (refcal's path) | `run_fight` (roles' path) | gap |
|---|---|---|---|
| L10 | 68% | 57% | 11pp |
| L50 | 39% | 38% | 1pp |
| L250 | 13% | 12% | 1pp |
| L1000 | 10% | 17% | 7pp |
| L5000 | 11% | 18% | 7pp |

**The two measurement functions AGREE** — every gap is at or below the audit's own ~15pp
systematic threshold. So the 47pp disagreement was never between the two methods, and the
hypothesis as originally written ("one of these audits is measuring wrong") is **disproven**.
The two audits were run at different times against DIFFERENT curve files; the curve was
rewritten at `8727054` (20:05) after the 47pp note was recorded at `24b0212` (18:55).

### CONFIRMED defect 1 — `species_power` is not normalised, and it worsens with level

The orthogonality half of the hypothesis is real and now quantified. `speciescal` is supposed to
own RATIOS between species, leaving the absolute to `refcal`, which requires its mean to be
**1.0 at every level**. It is not:

| level | n | mean | median | min | max |
|---|---|---|---|---|---|
| 10 | 14 | 1.059 | 1.000 | 0.350 | 1.693 |
| 50 | 25 | 1.202 | 1.171 | 0.586 | 2.062 |
| 100 | 24 | 1.213 | 1.189 | 0.594 | 2.171 |
| 250 | 19 | 1.275 | 1.278 | 0.609 | 2.500 |
| 1000 | 16 | 1.341 | 1.374 | 0.628 | 1.979 |
| 5000 | 14 | **1.566** | 1.493 | 1.000 | 2.346 |

Every monster at L5000 is on average **57% stronger than the anchor `refcal` set**. The species
layer is moving the absolute — the exact two-layers-one-quantity failure the orthogonality rule
exists to prevent — and because the drift grows with level, it bends the whole curve rather than
shifting it. (It was WORSE before `8727054`: L5000 mean 2.27, L1000 1.70.)

- [ ] Normalise `species_power` to mean 1.0 **per level** after calibrating it — but NOT yet;
      see defect 2, which blocks it

### CONFIRMED defect 2 — the sim's PLAYER is wrong at high level, and it blocks the fix

**This is the deeper blocker and it must be settled first.** `calibrate` (make_char vs real
saved characters) fires its own slope warning:

```
Band      vs tier        HP      ATK     POOL     n
naked     -           1.54x    1.96x    2.46x     2
partial   under       1.23x    1.10x    2.18x     3
geared    average     1.38x    1.58x    1.62x     5
chase     bis         0.42x    0.20x    0.73x     1
Level trend (ATK ratio): L6 2.09x  ->  L45 0.45x
*** SLOPE WARNING: the model does not hold across levels — it is hot at L6 and
    cold at L45. ... balance numbers taken from the far end of that range are
    NOT trustworthy.
```

At L6 the sim player hits **2.09x** as hard as a real character; at L45, **0.45x**. Every
measurement above is taken at L50-L5000 — the far end of exactly that range, extrapolated well
past the last real character we have to fit against.

**So the 7-18% win rates at L250+ are most likely an instrument artifact, not a live difficulty
crisis.** Do not act on them. Specifically:

- [ ] **Do NOT re-run the calibration chain yet.** `refcal` sizes monsters to hit a target win
      rate FOR THE SIM PLAYER. Feed it a player that is less than half as strong as a real one
      at high level and it will size monsters far too weak for the people actually playing —
      shipping the inverse of the problem
- [ ] Fix the **level-dependent gear model** first. The audit says what it needs: more real
      characters to fit against. Only one real character exists above L14 (a L45 Ninja), and one
      point cannot define a slope
- [ ] Note the interaction with **6k**: that L45 real character is a Ninja, whose attack comes
      almost entirely from gear because the class gains 0 STR/level. A gear model that undershoots
      at high level will understate tricksters worst of all

**Order:** defect 2 (player model) → re-measure → defect 1 (normalise `species_power`) → chain
ONCE → re-check `mcheck`. Doing defect 1 first fits the species layer against a broken player.

**Method note worth keeping:** the resolution came from running the two disputed measurements
*in the same process against the same file*. Two numbers produced at different times against a
file that changed in between are not a disagreement — they are two different questions. Record
the curve's git hash alongside any win rate quoted in future.

## ⚑ 2026-09-04 — FOUR MORE instrument defects, and what they had in common

A second day of the same lesson, worth recording separately because the tell was different each
time and the same question would have caught all four: **would a player actually do this?**

1. **The gear model discarded upgrades.** `_apply_class_kit` equipped the class piece
   unconditionally, so an ordinary roll that produced a rare or epic in that slot was thrown
   away for an uncommon Warlord Blade. The reference player came out erratically WEAKER by
   level, and a whole calibration chain was fitted to it before the verification audit caught it
2. **The focus model discarded attack and defence.** Scoring candidates on the target affix
   ALONE measured every class as worse with better gear. Not a finding — the signature of a
   model that optimises one number
3. **The equipment audit enumerated the wrong table.** Written specifically to stop wrong claims
   about gear, it walked affix pools and `EQUIPMENT_BASES` and concluded five stats were
   unobtainable. The class bases are in neither: they come only from Hoarder drops
4. **The class table measured a player who had never farmed their class.** Same root as 3

**The shared tell, and the one to look for next time:** a fault that is UNIFORM points at the
target; a fault that is PATCHY points at the instrument. `refcal` landing L1 at 66% and L10 at
58% but L250 at 20% is not a curve that is too hard — a curve cannot be wrong in patches like
that. The same signature appeared as "gear made this class worse", which was written off as
sample noise once before it was believed.

**And the practical rule:** before trusting a model of a player, ask whether a player would
actually behave that way. Wearing a worse item, ignoring attack to chase mana, and never farming
your own archetype are all things the model did and no player does.

## ⚑ MEASUREMENT DISCIPLINE — five instrument defects found in ONE day

Every one of these produced confident, wrong numbers, and several were reported to the user as
fact before being caught. Read this before trusting any historical figure in this file.

1. **Win counted twice** — the same `if` written twice in a row in `_fight_stats_at`. Every win
   rate that function ever printed was **2x the truth**
2. **`refcal` printed the pass BEFORE the value it wrote** — the table described a state one
   correction out of date
3. **Smoothing/clamping run AFTER the per-anchor print loop** — so the printed table described
   numbers that no longer existed by the time the file was written
4. **`refcal` silently wiped `rolecal`'s output** — it wrote only `anchors`, so a measured and
   reported boss danger fix was destroyed by the next calibration run with no warning
5. **Victory cost measured BEFORE post-defeat effects** — a flock that took the player to 1 HP
   logged as costing **0%** of the bar. Mine, written an hour earlier

**The rule that came out of it:** when the player's account disagrees with an instrument, check
the instrument first. In this session the player was right every single time — the missing
Forcefield shield, the one-shot companion, the vanished HP bar, the unwinnable regenerator, and
the 1 HP demon flock were all real, and in several cases the tooling actively denied them.

**The corollary that cost the most time:** a simulator cannot find a defect that depends on
playing well. Forcefield granting effective immunity was invisible to every audit because the
sim's mage AI does not maintain it. One sentence from the player — *"as long as I maintain it I
don't really get hurt"* — found what a day of calibration could not.

---

## In progress

**Item 6 (progression & difficulty curve) is the active arc.** Items 1-5 are done. On 2026-09-02
item 6 was split — it had grown to 21 open tasks covering two different jobs — into:
**6** the monster model and difficulty curve, **6b** companion power, **6c** class balance
(blocked, see below), **6d** risk/reward incentives.

### ✅ Sequencing: the unshipped balance body is now SHIPPED (v0.9.741, 2026-09-03)

This section used to warn that four significant balance changes sat in the tree, sim-validated
and unplayed. They are live as of v0.9.741 — the reference-player monster model, the role
targets, the escape fix, and the per-encounter flock budget. The player-post suppression floor
is the one deliberate exception: it remains behind `PLAYER_POST_TIER_FLOOR_ENABLED = false`
until 12b (the Phantom) gives a new character an on-ramp, and should be flipped in that same
change.

The sequencing consequence that still stands: **6c (class balance) was blocked because every
class number on record had been measured against the OLD monster model.** That re-measurement
is DONE (see 6c) — so 6c is unblocked, and its figures are the ones to trust.

**Status 2026-09-02:** (a) re-measurement DONE — see 6c. (b) **Playtest DONE and passed.**
A live L5 session confirmed the model on screen: flocks are survivable again after the
per-encounter danger fix (the same fight killed the character before it), an empowered
Broodcalling Orc read as a longer fight as designed, and combat timing now tracks the log.
User verdict: "seemed good from what I seen."

Three real bugs were found only by playing it, none of which the simulator can see:
- **Solo never got the party playback pass** — the gate was co-op-only, so in solo every
  result landed on message arrival while the text was still draining
- **The companion HP bar DISCARDED updates instead of deferring them** — the log said
  "knocked out" while the card still read 24/65
- Two harness faults that both presented as "my character is gone": a stale second server
  (the guard matched truncated `tasklist` output), and a rebuilt character that was never
  re-registered on the account after permadeath cleared its slot

**Next (as of 2026-09-03, post-release):** the measured-defect half of **6b** shipped in
v0.9.741 — companion HP by aggro, and damage/defense/resource-regen unflattened. What remains
under 6b is the *design* question (what a companion is FOR), which gates 12b, the Phantom loop.

So the live choice for the next session is between:
1. **A feel playtest of v0.9.741** — the largest balance change the game has had, and the one
   number picked by measurement rather than feel is Forcefield's 3-6x nerf. Cheap, and the last
   playtest found three bugs no simulator could see
2. **6c class balance** — now unblocked, with the mage roster the clearest remaining outlier
3. **6b's design half** — what a companion is for, which unblocks the 12b Phantom arc

Ask the owner rather than assuming; (1) is the cheapest and most likely to change what (2) and
(3) should say.

### What this session proved about trusting measurements

Item 5 found four modelling bugs in the simulator, each of which produced a confident, wrong
balance conclusion, and **three conclusions were reversed by verification alone** — including
two that had already been written up. Later work added more of the same: an "Exploit hits for
46000% of a health bar" reading that was a harness artifact, a "1 fight per level" XP reading
caused by the sim being unable to observe XP grants at all, and an "optimal strategy is to fight
things you lose to" headline that came from pricing a permadeath loss at zero.

**Check what a number is actually measuring before believing it, and re-check it before acting
on it.** Every finding in this file states how it was measured for that reason.

### 1. Party mechanics — server pass ✅ COMPLETE (shipped v0.9.740)
- [x] Leader **rotation** after each combat (default) + alternate **control modes** (fixed / rotate)
      — `Lead: Rotate / Lead: Fixed` toggle in the Party menu. Rotation walks a stable
      `rotation_order`, not `party.members` (which `_transfer_leadership` reorders new-leader-first,
      so rotating over it would ping-pong between two players). Verified fair for 3 members
- [x] Reward policy: **DUPLICATE** — gathering materials and job XP are copied in full to every
      member. Wrapping `_add_gathering_reward` covers every gathering path at once instead of
      changing ten call sites. **Crafting shares XP only** — duplicating the crafted item would
      mint N items from one set of materials
- [x] Rotation survives membership **churn** — leavers are dropped from the order, joiners are
      added, and rotation skips anyone dead/offline/departed. Verified: leavers never lead again,
      joiners get turns, no stale ids
- [x] **Leadership transfer verified** — with 3 members, the leader dying hands leadership to a
      survivor instead of disbanding. Needed a scenario where ONLY the leader is at 1 HP: in a
      lethal zone the others die first, the party drops to two, and it disbands instead
- [x] **Party max size is 5** (leader + four). The constant counts the leader, so the old 4 meant
      leader + 3. Raising it exposed `MAX_CONNECTIONS_PER_IP = 3`, which silently dropped the
      4th/5th local test clients — loopback is now exempt in DEV builds only
- [x] Live-tested with 3 clients: rotation, control modes, duplicated rewards, leadership
      transfer, follower control and post formation all confirmed on screen

- [x] **Follower control rule** — out in the world one player leads and the rest follow, so a
      follower cannot move, hunt, rest or gather; **inside a post everyone acts independently**
      (shopping, crafting, quests, walking between stations). Crafting needed no gate — it
      already requires being at a post or station
- [x] **Post formation** — inside a post nobody is dragged along and everyone moves freely; the
      party may only leave TOGETHER: the leader cannot step out while anyone is still wandering
      the post, and a follower cannot step out alone. Party members can share a tile, so
      gathering up to leave is always possible

*Rotation and rewards ship together: both edit party state and `_end_party_combat_all`, so
splitting them means editing and re-testing the same code twice.*

---

## ⚑ OPEN FROM 2026-09-03 — the handling order

Nine detailed sections were appended to this file during the 2026-09-03 session (they sit
between item 7b and the Dungeon arc). This is the ORDER to work them in and why. Detail stays
in the sections named; this block is the sequence.

**Ordering principle, as always: settle the inputs first.** The single most important
consequence below is that **almost every remaining balance number is measured through a metric
that saturates on death**, so tuning any of them before fixing the metric means tuning against a
broken instrument. That is step 2, and it gates most of what follows.

### 1. SHIP — ✅ DONE. v0.9.742, then v0.9.743 (client, both launchers, server)
Live XP bug plus the whole balance pass. Runtime byte-identical to r1 again (sha256 compared),
so launcher users pulled a ~14.8 MB content-only update. Server deployed and verified (reference
curve loads, no script errors). See *Recently shipped*.

### 2. Fix the calibration METRIC ← **the gate** — ✅ DONE 2026-09-03 (see STEP 2 DONE below)
*Detail: "CORRECTION — elite/boss fights are too short was an INSTRUMENT ARTIFACT" and
"DOES A WIN RATE MEAN THE SAME THING FOR EVERY CLASS?"*

- [ ] **Calibrate role multipliers against a WIN-RATE target instead of a cost target.** Cost is
      measured across all fights and a dead player has spent 100% of their bar, so at a 7% boss
      win rate the metric is pinned near 100% by definition — "cost 97%" and "win 7%" are the
      same fact twice, which is why `rolecal` cannot converge at L1-L50. Win rate neither
      truncates nor saturates, and is the language these decisions are actually made in
- [ ] Measure the outcome under a player who **disengages**, not one who fights to the death.
      `roles`/`classes` never flee, so death rates are overstated 3-6x for every class
- [ ] Do **NOT** split onto two axes — documented failure (hp_mult ran away to 305x), and the
      length problem it was meant to solve does not exist

### 3. Cheap cleanups that need no decision — one pass, any time
- [x] **DONE 2026-09-03 — the three dead party functions are deleted**
      (`process_party_combat_action`, `_party_process_attack`, `_party_process_outsmart`), with a
      comment left in their place explaining why. Removed while implementing party Outsmart,
      because leaving a stale duplicate beside the real thing is exactly what produced the lying
      damage cards.
- [x] **DONE 2026-09-04 — it WAS a species/spawn artifact, exactly as suspected.** Not a curve
      fault: the species mix at that level contained outliers whose lethality comes from
      ABILITIES rather than stats, which the curve does not size. Fixed at the cause by
      restoring `species_power` (see *THE ABILITY GAP*), after which L50 reads 63% win against
      the 60% target. Worth noting the instinct recorded here — "check whether it is a
      species/spawn artifact before treating it as a curve fault" — was right, and two attempts
      to treat it as a curve fault were measured and rejected before the note was re-read

### 4. Owner decisions — ANSWERED 2026-09-03
- [x] **Outsmart works in a party — DONE.** Owner: *"Outsmart should work in a party but ideally
      be balanced in the same way that mages and warriors are. They should have to invest around
      the same amount of extra to accomplish it just like the mages and warrior do to kill the
      monster with their abilities."*

      Implemented with **no party-specific pricing**, because that parity is what the solo design
      already encodes: the investment is the Read ramp plus the optional energy commitment, and
      the odds come from the same `_outsmart_chance` (class, Wits, level gap, role penalty,
      attempt falloff). A second balance model for the same button is the defect this codebase
      keeps producing.

      **Measured — cost to remove one full health bar, as a share of your own pool:**

      | route | to clear 1 bar |
      |---|---|
      | Mage: Magic Bolt | **36%** |
      | Warrior: Power Strike | 86% |
      | Mage: Blast | 95% |
      | Warrior: Cleave | 96% |
      | Trickster: Ambush | 110% |
      | **Trickster: Outsmart (the 8-stack Read ramp)** | **~128%, over 8 turns** |

      So Outsmart sits at the **expensive end** of the band, not below it — and a failure forfeits
      the whole ramp. Parity is met, arguably over-met.
- [x] **APEX now starts at tier 2 — DONE.** Owner: *"Apex should wait until Tier 2 at a minimum."*
      Skeleton (T1, 18.5% of the L5 spawn table) removed; Mimic (T2) is now the first apex a
      player can meet. Help page, searchable help topic and changelog lists updated with it
- [x] **Pathfinder chain RETIRED — DONE 2026-09-03.** Owner chose to take the gap rather than
      wait for item 7: *"Remove it."* The GRANT at character creation is gone; the quest
      DEFINITIONS and every turn-in/display path are untouched, so a character partway through
      the chain can still finish it. Nothing offers it to a new character any more (the quest
      board has been dungeon-only since v0.9.727).

      **The starter EGG is deliberately still granted** — it is also slated for removal with
      item 7, but taking it out before the tutorial Phantom exists would leave a new character
      with nothing at all. Same code site; it goes in the change that replaces it
- [x] **L1-5 gearless survivability — DECLINED 2026-09-03.** Owner: *"L1-5 is fine, the tutorial
      we are adding will fill that gap or existing equipment and companions will."* So option (b)
      stands alone: the curve is anchored to a geared player, and onboarding (item 7) is what
      makes a new character meet it. A returning player skipping the tutorial arrives with stored
      gear and registered companions, which is the same thing by another route.

      **Consequence to keep visible:** the only case left uncovered is a brand-new player who
      SKIPS onboarding for the challenge. That is now an accepted, informed difficulty choice
      rather than a defect — which makes item 7's Stage 0 skip prompt load-bearing. It has to
      state plainly what is being given up

### 5. Balance work that DEPENDS on step 2

**RE-MEASURED 2026-09-04** (`roles`, `classes` — read-only). Every number below this heading was
taken BEFORE the calibration day, so the owner's question — *"are we identifying if things are
still needed or stale"* — was the right one to ask here. Three of the six are stale, two are
live, and one is **worse than recorded**. Judged at ±10pp; 60 fights/cell.

- [x] **STALE — boss/elite at L1-L50 was 7-23%, now 35-56%.** Elite reads 35 / 38 / 56% at
      L1 / L10 / L50 and boss 35% at both L10 and L50. The band as written is gone.
      **One cell survives and is worth its own line:** boss at L1 is **12%**, against 35%+ every
      row above it. A brand-new character meeting a boss is the outlier now, not the range
- [x] **STALE — the post-L1000 length slide is gone.** Turns were 3.9 → 2.6 against a 5.0
      target; they now read **5.3 at L1000 and 4.5 at L5000**. Within noise of target
- [x] **DONE 2026-09-04 — it was a BUG, not a tuning problem, and the owner called it.**
      *"For Paladin I'm not really sure why it's not better considering it gets healed on
      attacks, is that not being accounted for?"* It was accounted for in the code and not on
      the turns that mattered: `combat_regen_percent` (Divine Favor, "heal 3% max HP per round")
      was implemented inline in `process_attack` only, so **casting a card skipped it entirely**.
      Paladin casts on a third to a half of its turns at elite, so a third to a half of its
      healing never happened.

      Same `process_attack` / `process_ability_command` split that had already been found
      skipping actor and damage metadata for casts — third defect from one cause. Per-round
      effects now live in `_apply_round_passives`, called from both and stamped by round so it
      cannot double-heal. The companion's `hp_regen` was in the same block and had the same bug.

      **Measured before and after** (60 fights/cell, same audit):

      | cell | before | after |
      |---|---|---|
      | L10 normal | 48% | 55% |
      | L30 elite | **8%** | **25%** |
      | L80 elite | 41% | 51% |

      +17pp at the cell that was the worst in the whole table, well beyond the ~6.4pp noise.
      **A Paladin buff is no longer indicated** — at L30 elite it now sits mid-pack among
      warriors (Fighter 28%, Paladin 25%, Barbarian 18%). Owner had said *"Paladin heal may need
      a buff"*; on this evidence the heal was fine and simply was not running
- [ ] **THE REAL ARCHETYPE PROBLEM IS WARRIORS AT ELITE, visible once Paladin's bug was fixed.**
      L30 elite by path: tricksters **58 / 58 / 66%**, mages 33 / 40 / 33%, warriors **28 / 25 /
      18%**. That is a path-shaped gap, not a class-shaped one, so it wants a path-level answer
      rather than three separate class tunes. Note the turn counts alongside it — warriors take
      13-29 turns at L80 elite against a trickster's 8-9, so they are not merely losing, they
      are grinding
- [ ] **WORSE THAN RECORDED — the Trickster elite gap is ~45pp, not ~20pp.** At L80 elite:
      Thief 80%, Ranger 83%, Ninja 85% against warriors at 60 / 43 / 41 and mages at 38 / 35 /
      31. This is now the largest single distortion in the class table and it is not a tuning
      nudge — three archetypes are playing different games. Merged with the old "L80 elite
      Trickster gap" line, which measured the same thing
- [ ] **THE CLASS-RESOURCE SUSTAIN LEVER WAS DESIGNED AND NEVER BUILT.** `character.gd`'s
      equipment aggregator declares `mana_regen`, `meditate_bonus`, `energy_regen`, `flee_bonus`
      and `stamina_regen`, commented in the source as "Mage gear" / "Trickster gear" / "Warrior
      gear". `combat_manager.gd` reads all five. **No affix, chase roll, proc, rune, unique or
      set grants any of them** — verified by enumerating every table (`-- gearsources`). Only
      COMPANIONS give mana/energy regen.

      So the obvious answer to "mages run dry" — *wear regen gear* — is not a build that exists.
      Found by the owner asking the right question: *"I'd be suspicious of if your data on mages
      is accounting for them focusing getting equipment with high MP and mp regen items."* It
      was not accounting for it, because there is nothing to account for.

      Decide deliberately: implement the five as affixes (they are already read, so it is a drop-
      table change, not a combat one), or delete the fields and admit resource sustain comes from
      companions and the economy alone. Either is fine; the current state — read by combat,
      produced by nothing — is the one that must not stand
- [ ] **NEW, found by the same run: mages RUN DRY in long fights.** Casts per turn collapses to
      **0.22-0.26 at L80 elite** for all three mage classes (against 0.77-0.78 for tricksters),
      i.e. by L80 a mage is auto-attacking through most of a long fight. That is the resource
      economy showing up as a win-rate problem, and it makes the mage row above a symptom rather
      than the cause — fix the economy before tuning mage numbers
- [ ] Trickster health bars are inconsistent **with each other**, not just with other archetypes
      (L80: Ranger 720, Thief 714, Ninja 1186). **Not re-measured** — needs a different probe
      than `classes`, so its status is unknown rather than confirmed
- [ ] **Magic Bolt is 2.4-2.7x more resource-efficient than every other route in the game** —
      36% of the pool to clear a health bar against 86-110% for everything else (measured
      2026-09-03, `tools/probe/kill_investment.gd`). That is the clearest remaining class
      outlier and it is the same "mage is too efficient" thread that has come back repeatedly.
      Either Magic Bolt's cost rises or its weight falls; do it after step 2
- [x] **MERGED upward** into the re-measured Trickster line — same measurement, and the gap has
      grown from ~20pp to ~45pp rather than closing

### 6. Item 7 — new player experience
Already placed and sliced. Slice 1 depends on the gear decisions in step 4.

### 7. Input gating + player-set combat speed + COMBAT LOG READABILITY
*Detail: DESIGN PROPOSAL (owner 2026-09-03) and COMBAT LOG READABILITY (owner 2026-09-03)*
The log being "a wall of text" is the same surface: gating gives the reader time, the speed
control sets the rate, and grouping-by-actor sets the density. Doing them separately means
touching the combat log three times.
Retires a whole bug class rather than adding a feature — post-combat HP staleness, the stale
companion bar, late buff visuals, the victory card over unsettled bars and the stale Continue
button all come from the player outrunning the playback queue. Scoped after the balance pass
because it touches every combat input path. Party rule: the **slowest member's setting wins**,
leader may override.

### 8. Passive — waiting on a recurrence
- [x] **DONE 2026-09-04 — it recurred, and the instrumentation paid off.** A player reported a
      Spider with no art on v0.9.743. Rather than fix the one name for a third time, an art
      COVERAGE audit was written: it walks every species with every variant prefix plus every
      dungeon boss and lists what cannot be resolved. It found **33 missing names, of which 21
      were every dungeon boss in the game** — a boss is named independently of its species
      ("Spider Queen" is a Giant Spider), so prefix-stripping could never reach the art and
      every boss fight showed an empty battlefield. Bosses now fall back to their species art
      through a mapping DERIVED from dungeon_database. Shipped v0.9.744.
- [x] **DONE 2026-09-04 — and this entry was WRONG.** It said the art needed drawing and that
      "aliasing them to another creature would show players the wrong monster". Both halves were
      false: the art has existed all along, as **`Fire Elemental` / `Water Elemental`** and
      **`Siren A` / `Siren B`**. Nothing needed drawing and nothing was aliased to a different
      creature — these ARE those creatures.

      The real cause was the pattern this codebase keeps producing: **two paths reading the same
      field.** `resolve_art_key` consults `ART_NAME_ALIASES`; `get_monster_ascii_art` carried its
      own inline copy — a random Elemental/Siren pick plus a duplicate of the Wolf / Orc / Young
      Dragon mappings — and only one of the two knew about variant prefixes. So bare `Elemental`
      drew fine while `Venomous Elemental` and the boss `Primeval Elemental` drew nothing, and
      the audit (which uses the other path) reported all 14 as missing.

      One table now serves both, and an alias may name several looks. The pick is by name HASH,
      not `randi()`: the old inline version re-rolled on every call, so one monster could change
      appearance between two redraws of the same fight. **Coverage audit: 371 names, 0 missing.**

      Worth keeping visible — the audit was right that something was broken and wrong about what.
      A coverage check tells you a name does not resolve; it cannot tell you whether the asset is
      absent or merely unreachable, and the write-up assumed the first without checking the map.
- [ ] Quest direction/distance mismatch and multi-quest dungeon routing — deliberately deferred
      to the dungeon arc. *Detail: QUESTS — owner observations*


## Next

### 2. Party UI  ← targeting + pacing shipped v0.9.740; invite window + watch-a-minigame remain

**Decided (user 2026-09-01):** targets include **companions** (so companion-affecting loot can
be added later without redoing the picker). **All buffs** are teammate-targetable EXCEPT
Vanish / Cloak / Teleport (escape+stealth tied to the caster's own presence — on an ally they
would pull them out of the fight) and Overload (burns caster HP to boost *the caster's* next
spells). Analyze stays self-only: it reveals monster info and the log is already shared.
Quick self-cast: the picker opens with **Yourself pre-selected**, so pressing the ability key
again self-casts — no new binding — plus a visible Self button.

- [x] Server: separate WHO CASTS from WHO RECEIVES. Items take a `target`; extended to
      `"pid:N"` / `"comp:N"` — a teammate or their companion. `process_use_item` gained a
      `recipient` (effects) while inventory + cost stay on the caster
- [x] Server: same for buff abilities. Done as a **before/after diff**, not a per-ability
      table: the ability runs unchanged on the caster (their cost, their stats, their
      rank-ups) and only the RESULT is moved — Character buffs, view-side state
      (Forcefield's shield, Arcane Surge) and Rally's heal. A new buff becomes
      redirectable just by being added to `PARTY_TARGETABLE_BUFFS`.
      Excluded: `war_cry` (debuffs the MONSTER now, not a self-buff), `overload`,
      `vanish`/`cloak`/`teleport`, `analyze`
- [x] Client: target picker over the party cards, Yourself first and pre-selected. One
      picker serves items (companions listed) and buffs (players only — the server refuses
      a companion target for an ability). Quick self-cast = `[1]`, the leading entry, or a
      **Cast/Use on Self** button on the action bar for click-only players
- [x] Found + fixed on the way: **Arcane Surge (Haste) was silently dropped in co-op** — the
      double-cast chance was seeded nowhere in the member view and synced back nowhere, so a
      mage paid for it every round and never got it. Also collapsed the ability-alias map
      from two inline copies into one `ABILITY_ALIASES` table
- [x] **Co-op playback pacing** (found during the 3-client pass). Three separate faults, all
      reading as "the fight froze":
      1. A co-op round is ~28 beats against ~8 solo (one head + body per member, plus one
         monster action per member). At the solo per-beat delay that is a **12.6-second**
         round. Rounds now play to a total budget (~6s), recomputed each beat so the round
         starts brisk and eases to full speed for the killing blow. Solo unchanged
      2. Playback could fall behind **without limit** — the server resolves the next round as
         soon as everyone clicks, so the queue grew a whole round each time. The monster's
         death, the victory card and the end-state settle ALL run only when the queue empties,
         so none ever fired. Now: while a newer round waits, drain at frame rate until caught
         up. Input is deliberately NOT blocked (that would make everyone wait out the
         animation and let one slow client hold up the party — user's call 2026-09-01)
      3. **Continue destroyed the victory card** — `acknowledge_continue` nulls the pending
         payload, so an impatient player threw away the card they were pressing toward. It now
         means "hurry up" while the round plays, "wait" while the reveal timer is in flight,
         and "dismiss" only once the card is up
- [x] Also fixed: co-op start never cleared `pending_continue` (solo always has), leaving a dead
      Continue button over the next fight; and `get_meta(name, null)` is not a safe read in
      Godot — a null default reads as *no* default and pushes an error (54 per fight from
      `_set_cell_dim`, which buried the real signal while diagnosing the above)
- Regression: `tools/combat_simulator/coop_buff_target_test.gd` (15 assertions), scenario
  `party_support`; `tools/test_setup/run.py` now captures per-process stdout to
  `tools/test_setup/logs/` (Godot's `user://` log does not capture `print()`)
- [ ] Quests-style **invite/accept window** (the current chat/action-bar flow is clunky)
- [ ] **Watch a teammate's minigame.** Gathering (scratch-off) and crafting (reveal panel) are
      single-player panels driven by a payload sent to the actor alone; the rest of the party
      only sees the result line. Since rewards now DUPLICATE, everyone is receiving what is being
      revealed, so watching it is meaningful. Needs the server to broadcast the payload plus each
      reveal to party members, and a read-only mode on both panels

### 3. Identity & theming ✅ COMPLETE — `docs/design/setting_bible.md`
**Agreed 2026-09-01.** A *phantom* is something the land has kept and pushed back up. It keeps
**places** (dungeons surface, take root, and bleed monsters toward the nearest holdout) and it
keeps **people** (delvers don't come back all the way). The two are one phenomenon: **going
into a phantom place is what makes you one** — permadeath is the bill, not bad luck. The only
thing that moves cleanly between lives is what you brought out **alive**, which is why
companions are the emotional spine: they outlive their delvers.

- [x] Name tied to the world — "Phantom" and "Badlands" both carry meaning, and every line of
      it is a reading of a mechanic the game already runs (dungeon spawn timer, threat cones,
      post-anchored levels, permadeath, Sanctuary, kennel, corpses, fusion, border tier)
- [x] Companions in the fiction: eggs are the one living thing a dead place produces
- [x] Dungeons in the fiction: why they appear, why they threaten posts, why they return
- [x] Setting bible written, with a voice guide (use/avoid word lists) so the Atlas, quests,
      NPC flavour and website can be written against one register
- [ ] **Full in-game copy pass** — tutorial intro, help framing, dungeon entry text,
      egg/companion flavour, post + NPC descriptions rewritten against the bible. **Wanted
      (user 2026-09-01), deliberately deferred**: it touches a large number of player-facing
      strings, and doing it before the dungeon arc (8-12) means rewriting dungeon text twice.
      Do the non-dungeon surfaces any time; save dungeon copy for 11

### 4. Website refresh ✅ COMPLETE (live at phantombadlands.com)
- [x] **Accuracy pass.** Fixed real errors, not just tone: the FAQ said **Windows only** when
      Linux has shipped for months; party size said 4 (now 5, with co-op explained); combat was
      described as ability slots rather than a deck. Added the systems that were missing
      entirely — Paths, uniques and sets, rank-ups, the card market, the Atlas, Apex Frontier —
      and gave **equipment and decks** their own coverage, which they had none of
- [x] Rewritten around the setting rather than a spec sheet, and the **name is now explained in
      the copy** (wording chosen by the user from drafted options). The hero carries the threat,
      and a separate line carries the lure: gear, cards found nowhere else, and *eggs*
- [x] **Real in-game screenshots** replace the hand-written mock-ups: combat (monster ASCII,
      battler sprite, companion, card hand), a companion art montage of eight types and
      variants, the deck screen, and a fully equipped inventory
- [x] Screenshots on the **Features page too**, not just the landing page — it was still a wall
      of bullet lists, which was the original "less boring" complaint. Four figures now break up
      the combat, party, companion and progression sections
- [x] Built `tools/test_setup/shots.py` + a dev-only `--shots` client mode so these can be
      **regenerated** rather than re-shot by hand — the presentation pass (11) will invalidate
      every one of them
- [ ] **Dungeon pages + dungeon screenshots deliberately deferred to 11** (user 2026-09-02):
      the dungeon view is mid-rework, so anything shot now is out of date on arrival. The
      landing page carries a visible placeholder in the meantime
- [ ] Follow-ups, none blocking: a **party co-op** screenshot for the "Fighting together"
      section (needs 2-3 clients, so the single-client capture harness can't do it yet);
      gathering / crafting / market shots; and carrying the Keeper's voice further into
      Features and the FAQ (one line each today)

### 5. Simulator upgrade ✅ COMPLETE (2026-09-02) — **unblocks all balance work**
- [x] Teach the sim to spend **abilities and resources**. It already drove three archetypes;
      the finding was worse than the line suggested — `run_fight` dispatched the per-turn AI by
      exact class string, so **six of the nine classes were never simulated at all**. Sorcerer,
      Sage, Ranger, Ninja (and Barbarian/Paladin partially) were handed the Warrior AI holding
      mage/trickster cards, matched nothing, and auto-attacked: 0 casts/turn and a 0% win rate
      that read as a balance result. The three resource helpers re-derived the archetype the
      same way, so a Sorcerer's spend was measured against its **stamina** bar. All four now
      ask `Character.get_class_path()` — the one place the game itself decides
- [x] Calibrate `make_char` against **real saved characters**. Done, but the important part was
      *classifying the cohort first*: 5 of the 11 local characters are **naked test accounts**
      (0 equipped slots) and 1 is an admin-boosted all-epic build. Fitting to them pointed the
      model the wrong way entirely (it wanted gear 10 levels *below* character level; the
      geared characters want it at ~0.85x). Only characters with 5+ slots calibrate the
      "average" tier now
- [x] Three further model errors found on the way, each fixed at the cause:
      **the enemy was hardcoded to "Orc" at every level** (a tier-2 monster, so past ~L500 the
      sim measured a stretched low-tier creature instead of real content — this alone produced
      a false "the game trivializes at high level" result); **the companion was invented**
      (a hand-written bonus block 2-4x anything the game can produce — now drawn from
      `COMPANION_DATA`); and the gear model forced one **uniform rarity** across all seven
      slots with a **fixed level subtraction**, which is the wrong *shape* — real item level
      tracks character level proportionally and often sits *above* it
- [x] Audits are now selectable (`-- classes races calibrate gear_solve progression companion`,
      `-- n=200` for sample size) instead of by editing `_init`
- [ ] **Known limitation, carried into 6:** the gear model has a **slope error** — hot at L6
      (1.57x attack), cold at L45 (0.35x). One item-level ratio cannot fit both ends, and there
      are only **2 genuinely geared real characters** to fit against. The audit prints a SLOPE
      WARNING rather than hiding it in a median. High-level balance numbers inherit this
      uncertainty until more real characters exist

### 6. Progression & difficulty curve — **the central balance goal** (user direction 2026-09-02)
*"Balance must hold throughout the game and not trivialize any of it."* The intended loop:
**grind gear + companions → level companions → reach bigger challenges → better gear and
companions.* Progression should get **harder**, never easier. The user is explicitly open to
changing **itemization, gear, companion levelling and companion power** to hit this.

**Measured 2026-09-02 (`-- progression`, L1 → L10000, the real max):** the curve does *not*
hold. It is not a smooth ramp — it is a **hump**:
- Difficulty peaks around **L50–L500** (same-level boss: Fighter 37% @L50, 32% @L100, 30% @L500;
  Wizard 17-32% across that band), then **gets easier again** past L1000 (Fighter 65-82%,
  Thief 95-97%). The late game is currently *safer* than the mid game
- **Wizard is the worst class almost everywhere past L100** and fights are absurdly long —
  **155 turns** at a L250 elite, 91 at L500. Turn count itself is a balance failure
- **Thief massively outclasses the other two at high level** (L1000 boss: Thief 95% vs Fighter
  65% / Wizard 60%) — the class gap widens with progression instead of closing
- The curve is **jagged**, not monotonic (Fighter boss: 37→32→55→30→65→77% across L50-2500),
  which points at monster-selection variance between tiers rather than a designed ramp

**Measured `-- ability_hp`** — one cast's damage as % of a same-level NORMAL monster's bar
(>=100% one-shots trash). This is the unit balance should be tuned in; raw damage is
meaningless when monster HP scales on a different curve:

| Ability | L1 | L5 | L10 | L50 | L100 | L500 | L1000 | L10000 |
|---------|----|----|-----|-----|------|------|-------|--------|
| power_strike | 263% | 102% | 67% | 35% | 23% | 10% | 42% | 45% |
| magic_bolt | 1203% | 385% | 210% | 73% | 43% | 84% | 238% | 365% |
| blast | 1009% | 341% | 142% | 25% | 14% | 8% | 14% | 20% |
| exploit (%-HP) | 10% | 10% | 11% | 16% | 18% | 17% | 20% | 23% |

- **The early game is a formality.** At L1 every damage card is 2.6x-35x overkill on a normal
  monster; Magic Bolt is **12x**. This is the user's "Magic Bolt is extremely powerful early
  game" observation, confirmed and quantified
- **It does fall off — and then comes back.** Magic Bolt bottoms at 43% around L100 (can no
  longer one-shot) and recovers to 238-365% past L1000. The U matches the difficulty hump
  exactly: monster HP outgrows player damage to ~L500, then player damage outgrows it
- **Blast never recovers** (down to 8-14%) — the mage's *sustain* card dies while its burst
  card returns, which is why Wizard fights run 40-155 turns in the mid-late game
- **Exploit is the only ability with a flat, rising curve — because it is %-max-HP.** Every
  other ability deals absolute damage into a bar that scales on a different curve. That single
  structural difference is the likeliest driver of Thief pulling away at high level, and it is
  the *shape* the balance model should learn from

**Encounter level vs fight math — a gap the sim deliberately does not model** (user question
2026-09-02: "is there a formula weakening monsters near the starter post?"). Yes, two:
1. `world_system.get_post_anchored_level()` — posts pull the encounter level **down** near them
   and *by construction can never raise it* ("posts are settlements, not difficulty elevators").
   The starter post sits at origin where the radial curve is already lowest
2. `monster_database._calculate_tiered_stat_scale()` — a monster spawning below its natural base
   level has its stats collapse linearly, so a clamped high-tier monster is a runt rather than an
   apex predator wearing a low level tag (the v0.9.481 fix for the 350-HP "Lv 1" Chimaera)

The sim models neither: it fights **same-level, tier-natural** monsters, which is the correct
unit for tuning abilities against each other. The consequence for the sweeps above is that they
are an **upper bound on difficulty** — real players can meet monsters at or below their level, so
the game is at least as easy as measured, never harder.

**The structural point is bigger than either formula:** `get_area_level_range` is a pure function
of `(x, y)` and never reads the player's level. Difficulty is chosen by **where you stand**, not
by how strong you are — so "progression gets harder" is entirely opt-in and nothing enforces it.
Measured (`-- underlevel`): against a monster at 25% of their level, every class at every level
wins **100% of fights at 96-100% health**. Not an XP exploit (the downlevel penalty floors at 40%
and a weak monster's base XP is small anyway) — but it means the pressure to move outward has to
come from the **reward gradient**, since the difficulty model will never apply it.

- [x] **Player-post safe pockets now scale with tier** (user approved 2026-09-02).
      **DO NOT DEPLOY before item 12b exists** — spawn-at-post already ships, so this change
      strands a fresh level-1 character outside a frontier post with no way to survive or gear
      up. Safe to sit in the tree today only because no player has built a post yet. NPC trading
      posts already scaled — their anchor is `_distance_to_level(post's own distance)` and post
      tier comes from `_tier_from_distance`, so a frontier post already anchors high. The hole
      was **player-built posts**: every one is created with `DEFAULT_PLAYER_POST_TIER = 1` and
      nothing ever assigns a distance-based tier, so the suppression floor in
      `_compute_effective_post_tier` was **1 everywhere**. A player could raise a post deep in
      the frontier, buy guards, and suppress a level-5000 zone to level ~1-2 permanently. The
      floor is now `max(post tier, wilderness_tier - MAX_PLAYER_POST_SUPPRESSION)` with the cap
      at 2 tiers, so a pocket is easier than its surroundings but never starter-grade. Guard
      investment keeps the same range; near the core (wilderness tier 1-3) the floor stays 1 and
      the early game is untouched
- [ ] **Decide whether progression pressure is a reward-gradient problem, not a monster-stat
      problem.** Neither formula should simply be removed — the stat downscale fixes a real bug,
      and safe settlements are good design. The lever is making the gear and companions players
      need obtainable only further out

**Root cause of the late-game slide, found 2026-09-02 by auditing the monster tables:**
`get_monster_base_stats` hand-authors `base_level` / `base_hp` / `base_strength` per monster
type, and the ratios **de-scale badly** as tiers rise:

| Monster | base Lv | HP/lvl | STR/lvl |
|---------|---------|--------|---------|
| Goblin (T1) | 2 | 7.50 | **4.00** |
| Ogre (T3) | 18 | 5.56 | 1.39 |
| Ancient Dragon (T5) | 70 | 7.14 | 0.86 |
| Hydra (T7) | 350 | 4.29 | 0.31 |
| Avatar of Chaos (T9) | 6000 | 2.50 | **0.07** |

HP per level falls ~3x from T1 to T9; **strength per level falls ~57x**. Meanwhile player
damage grows roughly with L² (`get_total_attack()` × `(1 + 0.02·STR)`, both terms linear in
level).

**CORRECTION (same day, after the user challenged it).** These base ratios do NOT by themselves
explain the late-game slide, and the first reading of them — that a scaled-up low-tier monster
might out-damage a native high-tier one — was **wrong**. Checking what the generator actually
produces reverses it: at L5000 a scaled Goblin has 15,000 HP against a Void Walker's 677,173,
and high-tier monsters carry far richer ability sets (multi_strike, regeneration, armored,
enrage, ethereal, mana_drain) that the base table does not show. Full numbers under 12b. Base
per-level ratios are a **misleading metric read alone** — always check the generated monster.

What survives is still decision-relevant: the tables have no consistent relationship to level
(hand-authored `base_level` per type, a tiered percentage scale, an HP cap that low-tier monsters
hit when scaled up, and a linear downscale for monsters generated below their own base level).
That is why the first task is a **target curve** and why the reference-player model below is the
leading fix — not because high-tier monsters are individually weak.

- [x] **MEASURED 2026-09-02 — this is the cause of the late-game slide AND the jaggedness.**
      `select_monster_type` picks a TIER from the level, then a monster from that tier. But a
      tier's level BAND and the base levels of the monsters inside it **do not line up**:

      | Tier | monster base levels | level band it covers |
      |------|--------------------|----------------------|
      | T6 | 150–400 | ~L150–1000 |
      | T7 | 700–1500 | ~L1000–2500 |
      | T8 | 2500–4500 | ~L2500–5000 |
      | T9 | 6000–9500 | ~L7500–10000 |

      `scale_monster_to_level` scales **up** from base on a tiered percentage curve, but scales
      **down** on a bare **linear** ratio (`target/base`). So near the **start** of a band most
      picks sit *above* the target level and generate as downscaled **runts**, while near the
      **end** of the same band every pick is scaled up and generates at full strength.

      The result is a **sawtooth**, not a curve (`-- selection`, 400 picks/level):

      | Level | tier | runt% | median HP |
      |-------|------|-------|-----------|
      | L500 | 6 | 6% | 93,271 |
      | **L800** | **7** | **39%** | **46,777** ← halved while the player got stronger |
      | L1500 | 7 | 5% | 205,343 |
      | L2000 | 7 | 4% | 428,668 |
      | **L2500** | **8** | **38%** | **63,765** ← **6.7x collapse** at the band boundary |
      | L5000 | 8 | 7% | 411,141 |
      | **L7500** | **9** | **34%** | **192,057** ← halved again |
      | L10000 | 9 | 0% | 1,160,125 |

      Difficulty **collapses at every tier boundary** and climbs back to the end of the band.
      That is the late-game slide measured in the progression sweep, and it is a *selection*
      problem, not a monster-strength problem.

      It also produces enormous **same-level variance**: the HP spread between the weakest and
      strongest monster a player can meet at one level grows to **85x** (L2500: ~7.5k to ~656k).
      Two players at the same level in the same place can have completely different fights.

- [ ] **Do not fix this by re-authoring `base_level` values — that only moves the teeth.** As
      long as level→difficulty is routed through each monster's hand-authored base level and an
      asymmetric up/down scale, some band will always start with runts. The mapping has to stop
      going through base_level at all. **Same conclusion as the reference-player model above,
      reached from a completely different direction — which is the strongest argument yet for
      building it.** It also serves the Phantom (12b), which needs any species to scale by depth.
- [ ] Whatever replaces it must also **bound same-level variance** deliberately (a designed
      range, e.g. 2-3x, rather than today's emergent 85x)

- [x] **Anchor monster stats to a reference player — BUILT 2026-09-02, behind `USE_REFERENCE_MODEL`
      in `monster_database.gd`.** Monster magnitude no longer comes from each species'
      hand-authored `base_level` run through an asymmetric up/down scale. It comes from a
      calibrated curve of what a real player at that level can actually do.

      **It is SELF-CALIBRATING, and that turned out to be the essential design decision.** The
      analytic route — measure player damage-per-turn, set `monster.hp = dpt × target_turns` —
      does not converge, because it is self-referential: a player bursts with abilities and then
      runs dry, so damage-per-turn depends on how long the fight lasts, which is exactly the
      number being set. Two failures made that concrete:
      - Averaging player output over a 12-turn window while designing 5-turn fights produced
        fights **2x too long at L1 and 16x too long at L5000** — a level-dependent error, because
        high-level fights ran longest and amortised the opening burst furthest
      - Matching the window to the target instead made **percentage-of-max-HP abilities blow up**
        against the oversized probe dummy (measured player damage-per-turn at L10000 leapt from
        1.9M to 39M)

      So the model stops predicting the fixed point and **finds** it: set stats, run real fights,
      correct toward target, repeat. It converges in 2-3 passes and is robust to every subtlety
      that broke the analytic version — ability rotations, resource drain, percentage damage,
      mitigation, monster abilities — because it never models any of them, only the outcome they
      jointly produce.

      **Results.** Same-level normal fights now land at 3.4-6.4 turns against a target of 5, with
      the player spending 25-66% of their health bar (target 40%) and winning 50-83%. And the
      structural defects are gone:

      | | before | after |
      |---|---|---|
      | median monster HP L2000→L2500 | **6.7x collapse** | strictly monotonic |
      | same-level HP variance | **85x** | **2-3x** (designed band) |
      | difficulty at tier boundaries | collapses every band | no discontinuity |

      **What it preserves.** Only magnitude is anchored. Species keep their abilities
      (multi_strike, regeneration, armored, ethereal…), their variants, glass_cannon, the
      elite/boss multipliers and XP — all still ride on top. Species also keep a bounded stat
      SHAPE derived from their own base-stat *ratios within their tier*, so a Hydra is still
      beefier than a Goblin, inside a designed ~2x band instead of an emergent 85x.

      **Difficulty is now an explicit knob**, which was the original goal and was previously not
      expressible anywhere: `TARGET_TURNS_NORMAL`, `DANGER_NORMAL`, and
      `PROGRESSION_DANGER_SLOPE` (danger × (1 + slope·log10(level)) — L1 ×1.00, L10000 ×1.24), so
      "the game gets harder as you progress" is a number someone chose rather than an accident of
      54 stat blocks.

      Sim audits: `-- refcurve` (player curve), `-- refcal` (calibrate against real fights),
      `-- refval` (validate), `-- selection` (sawtooth + variance regression test).

- [x] **Elite / boss / variant re-tuned against the corrected baseline (2026-09-02).** They had
      been sized against the old, too-weak baseline and inflated to compensate (Champion HP was
      raised 1.5 -> 3.5 in v0.9.700). Stacked on a correct baseline they made elites unwinnable
      — **0% win at L1**. Roles now state a target fight length and cost and the multipliers are
      derived: `hp_mult = turns_role/turns_normal`, `str_mult = (danger_role/danger_normal) *
      (turns_normal/turns_role)`. The strength term is the one that is easy to get wrong by
      hand and is why the old numbers compounded: damage taken is strength x turns, so making a
      monster tankier **already** makes it more dangerous — the old x3.5 HP with x1.3 STR came
      to ~4.5x a normal fight's cost rather than the intended 1.75x. `ROLE_TARGETS`: normal
      5t/40%, empowered 7t/55%, elite 9t/70%, boss 14t/85%. **Measured after: elites 46-80% win
      (was 0%), bosses 33-83%.** The sim reads `role_multipliers()` from the game rather than
      mirroring constants, so the two cannot drift apart again. Regression test: `-- roles`

**XP economy — measured 2026-09-02 (`-- xp`). Headline: the XP curve is HEALTHY. The
problem is what it incentivises.**

Fights needed to gain one level, same-level monsters, across the whole range:

| Level | XP needed | normal | empowered | elite | boss |
|-------|-----------|--------|-----------|-------|------|
| L1 | 230 | 42 | 45 | 60 | 51 |
| L50 | 285,512 | 39 | 54 | 61 | 70 |
| L1000 | 199,491,766 | 31 | 33 | 34 | 37 |
| L5000 | 6,869,024,800 | 34 | 36 | 38 | 49 |

**30-70 fights per level, flat from L1 to L5000.** That is close to the documented ~45
target and, more importantly, it does not drift with level. XP scaling needs no work.

**But the level-gap incentive is inverted, and permadeath makes it dangerous.** XP per
fight against monsters at a multiple of the player's level (losses counted as zero XP):

| Player | monster | win% | XP/fight | fights/level |
|--------|---------|------|----------|--------------|
| L50 | x0.25 | 91% | 222 | **1285** |
| L50 | x0.50 | 100% | 1,056 | 270 |
| L50 | x1.00 | 75% | 7,808 | 37 |
| L50 | x2.00 | 8% | 10,094 | 28 |
| L50 | **x3.00** | **12%** | 39,601 | **7** |
| L1000 | x1.00 | 91% | 6,678,136 | 30 |
| L1000 | **x3.00** | **12%** | 62,551,522 | **3** |

Two conclusions, pulling in opposite directions:
- **Under-level farming is already well punished** — fighting things at a quarter of your
  level takes ~1300 fights per level against ~35. This is the reward gradient that item 6
  wanted, and it means the safe-pocket concern near posts is NOT an XP exploit. Good news
  that did not need designing
- **Over-level fighting is wildly over-rewarded.** The optimal strategy by raw throughput
  is to attack monsters **3x your level at a 12% win rate** — 10x faster levelling than
  fighting fair. The sqrt over-level bonus compounds with the monster's own level-scaled
  base XP, so the reward outruns the falling win rate

**That is only optimal if losing is cheap, and under permadeath it is the opposite of
cheap.** An 88% loss rate is character suicide. So the game is currently telling an
optimising player to do the single most destructive thing available. Either:
- the over-level XP bonus is flattened so fair fights are competitive, or
- losing is made survivable (reliable flee), making the gamble a real choice, or
- both, deliberately — the gamble is a fine *option*, it just should not be the best one

- [ ] Decide which, then re-run `-- xp`. This interacts with the Trickster's Outsmart
      identity (its whole design is the over-level gamble) and with 12b's loop, where
      pushing out "as far as you can survive" is the intended pressure

**CORRECTION to the XP finding above (2026-09-02, `-- risk`).** The line "the optimal
strategy is to fight things you lose to" was based on a **throughput** metric — XP per
attempt with losses counted as zero — which is the wrong lens for a permadeath game and
produced a misleading headline. Two things it got wrong:

- **A successful over-level kill is NOT worth 1/7th of a level.** The "7 fights per level"
  figure averaged in the ~88% of attempts that fail. A single successful kill at **3x your
  level pays 1.24-1.93 LEVELS**, and at 5x it pays **4.3-7.9 levels**. The heroic reward is
  already large; the earlier presentation obscured it
- **Over-levelling is not "optimal" at all.** Pricing a loss at zero ignores that a loss
  costs the character. Netted properly it is heavily negative

Measured with a player who fights and then tries to **flee** below 35% HP (real
`process_flee`), so failure is three-way — kill, escape, or permadeath:

| Player | monster | kill% | escape% | death% | reward (levels) | levels per death |
|--------|---------|-------|---------|--------|-----------------|------------------|
| L50 | x1.0 | 58% | 25% | 16% | 0.04 | 0.13 |
| L50 | x1.5 | 19% | 8% | **72%** | 0.19 | 0.05 |
| L50 | x3.0 | 13% | **0%** | 86% | **1.24** | 0.20 |
| L250 | x3.0 | 13% | **0%** | 86% | **1.74** | 0.28 |
| L1000 | x3.0 | 25% | **0%** | 75% | **1.93** | 0.64 |
| L1000 | x5.0 | 8% | **0%** | 91% | **7.91** | 0.72 |

**Killing something 3x your level is already hard** — 13-25%, with 75-86% ending in
permadeath. The user's "it shouldn't be easy" is satisfied by the current numbers.

**The real defect is that you cannot escape.** Escape drops to **0%** against anything
1.5x your level or above. `process_flee` subtracts the full level gap from the chance and
floors it at 10%, so against a monster 100+ levels up it is a 10% roll per turn while
something that outclasses you is killing you in 2-3 turns. So an over-level fight is not a
gamble a player can *play* — it is a coin flip on the character with no skill expression
and no way to bail once it turns.

**And `levels per death` is below 1.0 almost everywhere** (0.01-0.72), meaning the gamble
destroys more progress than it creates. So no rational player takes it, and the whole
over-level reward curve — including the big 1.2-7.9 level payouts — is **dead content that
is never claimed**.

- [x] **Escape fixed (2026-09-02).** `process_flee` subtracted the RAW level gap in
      percentage points, which is meaningless across a 1-10000 range — 100 levels up is a 10x
      monster at L10 and a 10% one at L1000, yet both cost 100 points. Anything meaningfully
      above the player pinned flee to its 10% floor. Same shape of bug as the gear model's
      fixed level-lag: an **absolute** difference used where only a **ratio** has meaning.
      Now the penalty is 30 points per doubling (2x = -30, 3x = -48, 5x = -70) and the floor
      is raised 10 -> 25. **Measured per attempt: 45% at even level, 24-27% at 1.5-5x** (was
      pinned at 10%). Running from something far above you is now always possible, never
      certain, and a decision the player can actually play
- [ ] **Open follow-up: should escaping COST something?** Right now a successful flee is
      free. Dropping carried loot, taking a lasting wound or burning a consumable would make
      disengaging a real trade rather than a pure out. Deliberately not added unilaterally —
      it is a design call, not a bug fix
- [ ] Re-measure the risk/reward table now that escape works, and only then decide whether
      the 1.2-9.3 level payouts need raising. The `-- risk` audit models a player who attacks
      first and flees once hurt; against something far above you that first exchange is often
      fatal, so its escape column understates a player who runs immediately. Worth adding a
      "flees on sight" mode before drawing conclusions from it
- [ ] Only after that, revisit whether the payout curve itself needs raising — with a
      survivable failure mode the same numbers may already be right
- [ ] Sample-size caveat: 36 fights per cell, and the kill% column is visibly noisy
      (L50 shows 2% at x2.0 but 13% at x3.0, which is monster-selection variance rather
      than a real inversion). Widen before tuning against these numbers

**Two code-level notes found on the way, neither fixed yet:**
- [x] **Dead `check_level_up()` removed (2026-09-02).** It computed the requirement as
      `pow(level+1, 2.5) * 100` while the live path uses `pow(level+1, 2.2) * 50` — a ~30x
      divergence by L1000 that any future caller would have silently inherited.
- [ ] **The simulator cannot observe XP grants.** Neither the killing blow nor `end_combat`
      moves `character.experience` in the solo path — combat_manager returns the reward and
      `server.gd` applies it. An earlier version of this audit read XP as a delta on the
      character and reported ~1 fight per level at every level, which was pure measurement
      error. The audit now computes XP from the monster's own `experience_reward` plus
      combat_manager's level-gap arithmetic. Worth remembering for any future reward work:
      **rewards live server-side and the sim is blind to them**
- [ ] **Widen calibration sample size.** 24 fights per level per pass leaves visible noise (one
      L1000 pass read 20 turns against a converged 3-5). Raise it before treating the numbers as
      final
- [ ] **Re-run every balance measurement against the new baseline** — the ability-power table,
      the class comparison and the companion audit were all measured against the old monster
      model and their absolute numbers are now stale
- [ ] **The curve inherits the gear model's known slope error** (item 5): calibrated against a
      `make_char` that is hot at L6 and cold at L45, with only 2 genuinely geared real characters
      to fit against. The shape is now right; the absolute level carries that uncertainty

- [x] **Danger budget is per ENCOUNTER, not per monster (found in playtest, 2026-09-02).**
      First live L5 fight: beat an Orc Weapon Master, then died to the second of its flock. A
      flock chains more monsters into the same encounter with **no healing in between**, so a
      species with a 35% flock chance really presents ~1.5 monsters and a calibrated 40% cost
      per monster becomes 60%+ overall — with the tail (two or three chained, plus a rare
      variant) simply lethal. Each monster's DAMAGE is now divided by the expected chain length
      `1/(1-p)`; HP is untouched so each still takes its target number of turns, and a species
      that never flocks is unaffected
- [ ] Re-run `-- progression` and `-- roles` after the flock change — every danger number above
      was measured before it
- [ ] Decide the target curve first (what *should* win% and danger look like at L10, L100,
      L1000, L10000?), then tune to it. Without a target the sweep has nothing to fail against
- [ ] Fix the **mid-game hump** and the **late-game slide** — the two ends of the same problem

### 6e. Solo combat presentation — port the party pass back (user 2026-09-02)
*Found in the first live playtest of the monster model: "solo combat is missing a lot of the
fixes/improvements we made on party combat — the timing on when healthbars drop, when combat
numbers and animations are played, and anything else that will improve solo combat."*

- [x] **Root cause found and fixed: the playback gate was co-op-only.**
      `_coop_playback_pending()` returned `_in_coop_combat() and queue non-empty`, so in SOLO it
      was **always false** — every result landed the instant the server message arrived while
      the combat text was still draining through the queue. Health bars dropped before the line
      explaining the hit, and damage numbers played out of step with the log. The docstring's
      own reasoning ("anything that shows the RESULT of the round must wait, or it lands before
      the player has seen what happened") never had anything to do with co-op. It now delegates
      to `_combat_playback_active()`, which already computed exactly this — one condition
      instead of two copies to drift apart
- [x] **Added the SOLO settle on queue-drain.** Holding results back requires something to
      apply them when the beats finish. The party paths did that from their own authoritative
      payloads; solo had none, so gating alone would have frozen its bars mid-fight
- [ ] **Verify in a live fight** — this is a timing change and the simulator cannot see it
- [ ] Audit the rest of the v0.9.740 party pass for solo-applicable pieces: the round-budget
      pacing (a co-op round plays to ~6s total, recomputed each beat so it starts brisk and
      eases into the killing blow), the catch-up drain when a newer round is waiting, and the
      Continue-button semantics (hurry / wait / dismiss). Solo has its own per-beat delay and
      may want the same total-budget shape
- [ ] Check whether attack FX still fire at submit rather than on the beat in solo — that was
      one of the five co-op bugs and the same code path serves both

**HIGH-SAMPLE RE-MEASUREMENT (`-- n=90`, 2026-09-02).** Supersedes every balance number taken
before it. Calibration convergence raised from sqrt to `CAL_CORRECTION_EXP = 0.75` over 6 passes
— justified by the sample budget going from 8 to 30 fights per class, which is what the heavy
damping had been protecting against.

**Roles — the danger axis converged for NORMAL, partially for elite, not for boss:**

| Role | turns (target) | HP cost (target) | win% |
|------|----------------|------------------|------|
| normal | 5.6 / 5.2 / 5.1 / 3.3 / 3.0 / **2.6** (5) | 40 / 30 / 41 / 48 / 44 / 43% (**40%**) | 65-82% |
| elite | 6.0 / 7.3 / 5.9 / 3.7 / 12.7 / 3.5 (9) | 39 / 52 / **65** / **68** / 44 / 44% (70%) | 47-78% |
| boss | 9.6 / 9.5 / 8.4 / 23.1 / 8.9 / 15.5 (14) | 48 / 50 / 57 / 57 / 58 / 35% (85%) | 55-76% |

*(levels L1 / L10 / L50 / L250 / L1000 / L5000)*

- **Normal fights now cost exactly their 40% target**, up from 33%. The convergence fix worked
- **Elite reaches 65-68% at L50-250** (target 70%) but sags at both ends
- **Boss is still well short** — ~50-58% against 85%. Bosses are a real fight but not frightening
- [ ] **The remaining structural gap: high-level fights are too SHORT.** Normal turns fall to
      3.3 / 3.0 / **2.6** at L250 / L1000 / L5000 against a target of 5. Monster HP is
      under-converging at the top end while the danger axis is on target, so the top of the game
      is quick rather than easy — a different fault from the old sawtooth and a smaller one
- [x] **Roles are now CALIBRATED, not derived (2026-09-02, `-- rolecal`).** The derivation
      assumed a fight really lasts `turns_role`, which it does not, so damage never accumulated
      to the intended cost. Measured multipliers replace it: empowered hp x1.31 / str x1.48,
      elite hp x2.35 / str x1.72, boss hp x3.32 / str x1.72. `monster_database` prefers these
      over the algebra whenever the curve file carries them.

      **The danger targets are now HIT — and that is the problem.** Verified at n=90:

      | Role | target cost | measured cost | measured WIN% |
      |------|-------------|---------------|---------------|
      | normal | 40% | 43% | **74%** |
      | empowered | 55% | 57% | **60%** |
      | elite | 65% | 67% | **46%** |
      | boss | 80% | 75% | **34%** |

- [x] **DECIDED (user, 2026-09-02): the measured costs are the intent** — normal 43%,
      empowered 57%, elite 67%, boss 75% of the player's health bar. The coupled win rates
      (74 / 60 / 46 / 34%) were put to the user explicitly, including that a 34% boss win rate
      under permadeath is roughly three characters lost per boss killed, and accepted.
      **`ROLE_TARGETS` is deliberately left UNCHANGED at 40/55/65/80** — those are the *inputs*
      that produced the approved *outputs*; retargeting to the measured values would aim the
      calibrator lower and undershoot what was agreed
- [x] **Level unevenness largely CLOSED (2026-09-02) by single-axis, per-level role
      calibration.** Four approaches were measured against each other:

      | approach | elite cost (t65) | elite win spread | boss win |
      |----------|------------------|------------------|----------|
      | one derived pair | 57-77% | 28 pts | 23-47% |
      | per-level, 2-axis | 37-67% | 23 pts | 30-47% |
      | win-only turns | 63-81% | 24 pts | **15-33%** (worse) |
      | **single-axis, per-level** | **54-68%** | **12 pts** | 30-48% |

      Final: elite cost 54-68% against a 65% target with win rate in a **12-point band**
      (48-60%), down from 28. Boss cost 65-81% against 80%, win 30-48%. Normal 35-55%
      against 40%, win 64-82%.

      **Two failed attempts are recorded because both looked obviously right:**
      - *Measuring fight length on WINS ONLY* — reasonable-sounding (a "14-turn boss fight"
        describes a fight you win) and **actively harmful**: conditioning on wins SELECTS the
        favourable, SHORT fights, so it reads short exactly when win rate is low, the
        calibrator raises HP, win rate drops, and the next pass selects even more lopsided
        wins. Boss win fell to 15-33%
      - *Correcting turns AND cost together* — they are coupled through the win rate (raising
        HP raises cost, which kills the player sooner, which shortens the fight), so two knobs
        chasing two coupled targets oscillate instead of converging

      **Turn count is now an OUTPUT, not a target.** `hp_mult` is fixed at the role's design
      length ratio with no feedback; only cost is corrected. Measured turns range widely
      (2.9-32.2) and that is accepted: the danger numbers were signed off, fight length was
      not. Tunable directly via `ROLE_TARGETS.turns` with no loop to destabilise
- [ ] Remaining, and smaller: boss cost averages 71% against its 80% target, and empowered has
      one outlier at L1 (32% against 55%). Worth one more pass some time, not now
- [ ] **Superseded note — the original statement of this problem:** With
      the targets settled, this is what is left, and it is the old hump in miniature:

      | Level | elite win | boss win |
      |-------|-----------|----------|
      | L1 | 63% | 40% |
      | **L10** | **38%** | **24%** |
      | **L50** | **35%** | **23%** |
      | **L250** | 38% | 35% |
      | L1000 | 45% | 47% |
      | L5000 | 62% | 37% |

      Elite spans 35-63% and boss 23-47% against targets of one number each. **L10-L250 is the
      punishing band** — a boss there is won 23-24% of the time against 47% at L1000, so the
      same nominal encounter is twice as lethal in the mid game. The role multipliers are a
      single pair applied at every level, so they cannot correct a level-dependent gap
- [ ] Candidate fix: make the role multipliers **per-anchor** (calibrated per level like the
      baseline already is) rather than one pair for the whole game. Same change also addresses
      the turn-count drift below, since both come from one multiplier serving four orders of
      magnitude
- [ ] Turn counts are still off target for the big roles (boss 6.4-17.7 against 14, elite
      5.5-14.6 against 9) even with calibrated multipliers — a single multiplier cannot hold
      both length and cost across the level range. Secondary to the decision above
- [ ] The 40 / 70 / 85% danger targets are a **proposal, not a measurement** — worth the owner's
      eye before more work is spent hitting them exactly

**Ability power (`-- ability_hp`), one cast as % of a same-level normal monster's bar:**

| Ability | L1 | L10 | L100 | L1000 | L5000 | L10000 |
|---------|----|-----|------|-------|-------|--------|
| power_strike | 16% | 16% | 16% | 33% | 61% | 123% |
| cleave | 21% | 19% | 19% | 41% | 108% | 126% |
| ambush | 14% | 14% | 16% | 24% | 35% | 67% |
| gambit | 14% | 15% | 21% | 34% | 47% | 57% |
| exploit | 10% | 11% | 26% | 48% | 33% | 18% |
| **magic_bolt** | 61% | 42% | 53% | **170%** | **481%** | **379%** |
| **blast** | 51% | 27% | 19% | 16% | 15% | 25% |
| meteor | 196% | 87% | 28% | 47% | 52% | 73% |

- **Magic Bolt is confirmed as the outlier, and it is worse than first measured** — 42% of a
  health bar at L10 rising to **481%** at L5000, an ~11x drift. Every other ability moves by
  ~4x across the same span. Its `mana x (1 + 4.3*sqrt(INT))` shape rides a mana pool that grows
  faster than level, and nothing else in the game does that
- **Blast has stabilised** at 13-27% rather than dying to 5% as it did against the old baseline —
  it is weak and flat, not collapsing. A smaller problem than it looked
- **The warrior/trickster rise at the top end (power_strike 123%, cleave 126%) is NOT an ability
  problem** — it tracks the too-short high-level fights above. Fix the HP convergence and these
  should settle back; do not tune them first

### 6g. **DONE — ability anchor decoupled; curve smoothed** (2026-09-02)

*Was: "`refcal` cannot steer fight length". User approved the frozen-bar fix.*

**The defect.** Ability damage was `reference_monster_hp(level) * weight * stat_ratio` — a share
of the SAME curve `refcal` rewrites. Raising monster HP to lengthen a fight raised every
ability's damage by the identical factor, so fight length never moved and the calibrator kept
raising HP: **2-5x inflation across every anchor** over repeated runs, while abilities kept pace
and BASIC ATTACKS (which do not scale with it) silently fell behind. Companion damage had the
same coupling and was fixed alongside.

**The fix.** `shared/ability_reference_bar.json` — a frozen snapshot of the curve the
`ABILITY_WEIGHTS` were authored against, which `refcal` must never rewrite. Ability and
companion damage read it; monster HP is an independent lever again. **Consequence worth
stating: "a power strike is worth a fifth of a monster" is now a claim about the FROZEN bar, not
about whatever monsters currently have.** If calibration decides monsters need 1.5x HP, a power
strike becomes a seventh of one. That is what makes fight length steerable at all, but it means
`ABILITY_WEIGHTS` wants re-reading against `-- ability_hp` once the curve settles.

**A second defect the fix exposed.** The monotonic clamp stops dips, but turns a single noisy
SPIKE into a permanent plateau: L250 spiked to 35351 and L500 — which had calibrated itself to
16106 — was clamped UP to 35351, inflating every level above it. The curve stepped 5.04x from
L100 to L250 then 1.00x to L500, and the role audit landed exactly on those anchors (L250 normal
16.4 turns, L1000 boss 3.1). Now smoothed in log space BEFORE clamping, two light passes.

| | before | after |
|---|--------|-------|
| step between anchors | 1.00x - 5.37x | **1.07x - 2.31x** |
| monotonic | 3 clamps needed | **True, no clamps fired** |

**THREE measurement bugs in the simulator were found and fixed today.** Every one made the game
look different from how it actually plays, so treat historical numbers in this file with care:
- `_fight_stats_at` counted every win TWICE (the same `if` appeared twice in a row) — every win
  rate that function ever printed was **2x the truth**. Display only; calibration corrects on
  turns and cost, so written curves were unaffected
- `refcal` printed the measurement from one correction BEFORE the value it wrote
- smoothing and clamping run AFTER the per-anchor loop, so the printed table described numbers
  that no longer existed. Rows are now labelled `raw / pre-smoothing` and a verification table is
  measured against the final written curve — **that is the only table to trust**

**Where the curve landed** (roles audit, n=60, post-smoothing):

| role | HP cost before | HP cost now | target | win% |
|------|----------------|-------------|--------|------|
| normal | 28-56% | 44-57% | 40% | 61-78% |
| empowered | 23-54% | 46-59% | 55% | 58-71% |
| elite | 24-58% | 51-71% | 65% | 43-63% |
| boss | 32-70% | 54-73% | 80% | 43-66% |

Danger converged and win rates now descend correctly by role — empowered used to be EASIER than
normal. L1-L100 lands at 4.5-6.5 turns against a 5-turn target.

**ROLE CALIBRATION landed — bosses are dangerous again.** `-- rolecal`, per anchor level:

| role | HP cost | target | win% |
|------|---------|--------|------|
| empowered | 39-73% | 55% | 50-80% |
| elite | 49-72% | 65% | 53-73% |
| **boss** | **69-85%** | **80%** | **27-50%** |

A boss now costs ~three quarters of the bar and is lost more often than won. Before this session
it cost half a bar at a 60-73% win rate.

**A FOURTH tooling bug, and this one destroyed committed work rather than misreporting it.**
`refcal` wrote the curve file with only `anchors`, so running it after `rolecal` silently wiped
`role_multipliers` — the boss fix above was measured, reported, and then overwritten by the very
next `refcal` run. The documented workflow at the top of CLAUDE.md is `refcal` then `roles`, and
`roles` is a READ-ONLY audit, so following it exactly was safe — the trap is that `rolecal` (the
writer) is not in that workflow, so any later `refcal` silently discarded it with no warning and
no visible symptom until a role audit was re-run. `refcal` now carries the block forward
and prints a note when it does. Only caught because a manual file restore happened to print
"no role_multipliers in current file".

**A correction attempt that FAILED, recorded so it is not retried.** Correcting monster HP
against EFFECTIVE turns (fight length extrapolated to completion from damage dealt, to escape
death-truncation) made the low game worse: L1-L100 fell from 4.5-6.5 turns to 2.5-3.0 against a
5-turn target, L50 HP 6296 -> 3612. For a WON fight eff_turns equals observed turns; for a lost
one it extrapolates upward, so the mean is always >= observed, and the calibrator concluded
fights ran long. The premise was wrong: a player who dies on turn 4 experienced a 4-turn fight
against a monster that is too STRONG, which the danger axis already handles. `eff_turns` is
still measured and reported — the truncation it describes is real — but it is not the correction
signal. Reverted.

**EMPOWERED INVERSION FIXED (2026-09-02).** `rolecal` had the same measure-then-correct lag
`refcal` did — the written multiplier was one correction past the last measurement — so
empowered was pushed to 59-74% HP cost against a 55% target, ABOVE elite in the middle band.
With a verification pass and 8 passes instead of 5, `str_mult` fell from 1.46/2.07/1.27 to
0.96/1.63/0.78 and the tier order is correct again:

| role | HP cost | target |
|------|---------|--------|
| normal | 39-54% | 40% |
| empowered | 49-74% | 55% |
| elite | 65-80% | 65% |
| boss | 71-89% | 80% |

**Boss danger CONFIRMED as intended (user 2026-09-02):** *"I think I'm okay with the bosses
currently as I think companions and gear will make up the difference."* Boss win rate sits at
18-46%. Do not re-open this as a defect — it is a decision.

- [ ] **UNRESOLVED: the calibrators and the `roles` audit disagree by ~6-8 points on the same
      quantity, consistently in one direction.** `rolecal` measures empowered at 49-65%; the
      audit measures the same written multipliers at 59-74%. It is not confined to one role —
      `normal`, tuned by a completely different calibrator (`refcal`/`_fight_stats_at`), also
      reads 46% mean against its 40% target. So two independent calibrators each hit their
      target by their own measurement while the audit says all four run hot. Both paths build
      characters the same way (`make_char(lvl, "average", klass)`, same three classes); the
      audit uses 20 samples/class against the calibrators' 10, which explains noise but not a
      one-directional bias. **Find which of the two is lying before trusting either number.**
      Given four measurement bugs in this tool today, assume it is a real defect, not variance

- [ ] **Turn counts still swing** and this is now the LAST big open item on the curve (boss
      L5000 43.7 turns, empowered L10000 48.1). Danger converged because `str` is a clean
      independent lever; turns did not. Note `rolecal` deliberately does NOT calibrate
      `hp_mult` — it is fixed at the role's design length ratio (1.40/1.80/2.80) with no
      feedback, so **role fight length inherits the base curve's turn error and multiplies it**.
      Boss L250 is 30 turns because normal L250 runs long. Fix the base curve, not the roles.
      Two failed approaches so far: feeding both axes back (oscillates) and effective turns
      (above). A joint two-variable solve is the untried option
- [ ] Re-read `ABILITY_WEIGHTS` against `-- ability_hp` now the bar is frozen and the curve moved
- [ ] Re-run `-- classes`, `-- species` — both were measured against the stale curve

### 6b-ii. Companion DAMAGE follows the same rule — and the inspect page is 6-7x wrong

Owner, following the HP fix: *"were other stats of it being done this way as well? If so they
should follow the same reasoning as the HP and not be nerfed based on player stats."*

**They were.** Combat read the reference bar at the **player's** level and multiplied by
`sqrt(companion_level / player_level)` clamped to `[0.60, 2.50]`. Two consequences, both the
same fault as the HP one:

- a companion levelled far past its owner **stopped gaining anything above 2.5x** — investment
  thrown away
- every companion's output moved when its **owner** levelled rather than when **it** did

Now the companion's own level picks the bar it is measured against and nothing about the owner
enters. Measured (T1, attack 5):

| player | companion | before | after | |
|---|---|---|---|---|
| 50 | 50 | 305 | 305 | level-matched: **unchanged** |
| 1000 | 1000 | 5854 | 5854 | level-matched: **unchanged** |
| 50 | 200 | 609 | **1198** | over-levelled: cap removed, investment kept |
| 1000 | 50 | 3512 | **305** | under-levelled: worth its own level |

- [ ] **Consequence to feel-check, and it is sharp:** a L50 companion beside a L1000 player drops
      3512 → 305 damage, an 11x cut. That is the principle applied honestly — it is worth what it
      has been levelled to — but it makes walking an unlevelled companion at high level nearly
      pointless where it used to coast on the owner's level. Deliberate, and worth confirming it
      feels right rather than punishing. Interacts with 6b's note that a matched companion
      already survives only ~3 rounds at L1000

**SEPARATE BUG, found while checking: the companion inspect page understates damage by 6-7x.**

`client._estimate_companion_damage` implements the LEGACY linear formula
(`tier*5 + player_level*0.3 + companion_level*0.5`) while combat uses the anchored one. Measured
displayed-vs-actual: 13 vs 74 at L10, 47 vs 305 at L50, 845 vs 5854 at L1000. Three copies of
this formula exist — `drop_tables.get_companion_attack_damage`, the client's mirror of it, and
the real one inline in `combat_manager`.

This is the direct answer to the owner's other question, *"is the companion inspect page and
stats being accurate and able to be seen at a glance still on our to do list?"* — it is on the
list (buried inside item 7 as a tutorial step), and the answer to "is it accurate" is **no**.

- [ ] **One source of truth for companion damage.** The anchored formula needs `ability_reference_hp`,
      which the client has no access to, so the SERVER should compute the estimate and send it
      with the companion payload. Deleting the two legacy copies is the point — a third copy is
      how this drifted in the first place
- [ ] **Pull the companion stat/compare surface out of item 7.** It is gated behind an unbuilt
      tutorial arc while players cannot currently answer basic questions about their own
      companions. It is independent work

### 6b-i. Companion HP now comes from the COMPANION'S level, not the owner's (2026-09-04)

Owner: *"It's kind of odd that the companions HP changes based on the HP of the person who's
using it rather than a value based on the companions level. Makes companions lose some of their
value as players stats change. Kind of goes against the concept of the companion being able to
carry lower level players."*

Found from live play — a player equipping and unequipping gear watched the companion's health
move with it, then **gained a level and watched it fall**. Both reproduced exactly:

| change | companion HP |
|---|---|
| owner equips +HP gear, 250 → 400 max HP | 395 → **633** |
| owner gains ONE level, same 300 max HP | 671 → **474** |

The second is the damning one: levelling up made your companion weaker, because the owner-share
ratio falls as you outlevel it (1.000 → 0.707 → 0.600).

`calculate_companion_max_hp` took `max(owner_share, own_level)`, and at low companion levels the
owner term won every time. The own-level anchor already existed and already carried the right
intent in its comment — *"a level 250 companion should work like a level 250 companion if the
player is underleveled"* — it was simply being outvoted. It is the whole basis now.

**After:** the bar is invariant to owner gear and owner level (295 HP in every row above), and
moves only when the COMPANION does — 295 at L1, 450 at L10, 702 at L25, 1474 at L50. That is
what makes levelling one an investment rather than a reflection.

- [ ] **Player-side power change — needs the calibration chain re-run before it ships**, and
      that is currently blocked on the refcal/roles discrepancy. Held on master with the rest of
      the balance work
- [ ] Re-run `-- companion` and `-- comp_unlock` afterwards; they are the regression tests for
      this item
- [ ] **Consequence to decide:** a low-level companion beside a high-level player is now
      genuinely weak, where before it inherited their bar. That is the intended direction — it
      is what makes levelling the companion matter — but it does mean a fresh companion is no
      longer a free ride at high level. Worth a feel check
- [ ] While here: the three multipliers COMPOUND (aggro share 1.25 x defence 1.20 x variant 1.49
      = **2.24x** for a Nexus Bone Servant). Each is individually defensible; nobody checked them
      stacking. The spread across companions of the same tier and level is ~2.2x, driven mostly
      by variant and aggro rather than by level — which partly works against this same item

### 6b. Companion power & levelling — **the emotional spine, currently thin**
*User 2026-09-02: "if companions don't get stronger and players have no way of improving them
it makes the crucial point of the game pointless."*

> The companion's **card** is audited separately in **6h** — it is deck power competing against
> class abilities, so it is measured against those, not against companion stats.

**Measured `-- companion n=200`** (same-level elite, Fighter, win% by companion state):

| Level | none | comp L1 | comp L=char | comp x10 |
|-------|------|---------|-------------|----------|
| L10   | 85%  | 84%     | 91%         | 95%      |
| L50   | 25%  | 32%     | 53%         | 71%      |
| L500  | 10%  | 14%     | 31%         | 53%      |
| L2500 | 67%  | 65%     | 81%         | 86%      |
| L10000| 48%  | 45%     | 75%         | 79%      |

Three things fall out of this, and the first is the headline:
- **A level-1 companion is statistically indistinguishable from having NO companion**, at every
  level in the game. The two columns track each other within noise the whole way down. So the
  flat stat bonuses are effectively **decorative** — all of a companion's real value comes from
  ability scaling with level
- Companion **level** therefore does pay, and pays a lot (L500: 10% → 31% → 53%). An earlier
  claim that companions had become inert at high level came from the Orc bug in item 5 and was
  **wrong** — corrected here deliberately so it doesn't get re-derived
- But the payoff **saturates**: at L5000-10000 a 10x over-levelled companion is no better than a
  level-matched one (82/81%, 75/79%). Something caps out up there — worth finding before tuning

**CORRECTION 2026-09-02 (traced the consumption paths).** An earlier version of this item
claimed "companion passive stat bonuses do not scale with level at all — a L1 Ogre and a
L10000 Ogre grant the identical `{attack 5, hp_bonus 3}`". That was read off
`get_companion_effective_bonuses` alone and is **wrong in its implication**. The table values
are **percentages**, and every consumer applies them to a base that already scales:
- `attack` multiplies companion damage: `(tier*5 + player_level*0.3 + companion_level*0.5)
  * (1 + attack/100)` (`drop_tables.get_companion_attack_damage`)
- `hp_bonus` / `mana_bonus` are `% of the player's own max`
  (`get_total_max_hp() * comp_hp_bonus / 100.0`)
So a +5% companion is +5% at every level, like a gear affix. Nothing is "decorative".

**What actually explains `comp L1` ≈ `none`** is almost certainly **ability unlocks**, not stat
bonuses: `get_companion_unlocked_abilities` grants the passive always, the **active at
companion level 5**, and the **threshold at level 15**. A level-1 companion has *one third of
its kit*, which matches the measurement far better than a percentage that never changed.

**SHIPPED 2026-09-02 — two companion durability defects found in live play (L50 Wizard).**

1. **Aggro was rolled once per ROUND but applied the whole round's damage.** A `multi_strike`
   monster put its entire burst on whichever target won a single coin flip, so a Gryphon's
   3-hit round — ~45% of the player's bar — took ~90% of a companion's smaller pool at once
   ("it nearly killed my Succubus in one hit"). Aggro is now rolled **per hit** and a round can
   split across both targets. Expected soak is *unchanged* (25% aggro takes 25% of hits instead
   of 25% of rounds); only the burst spike is gone. This is not a companion buff.

2. **HP share was a flat 0.5 regardless of how many hits the companion is asked to take**, which
   made relative durability the **inverse of the design intent**. Lifetime vs the owner is
   `share*(1-a)/a`, so at a flat 0.5:

   | companion | aggro | lifetime vs owner |
   |-----------|-------|-------------------|
   | Iron Golem | 65% | **0.27x** — the tank died ~4x FASTER than its owner |
   | Wolf | 25% | 1.50x |
   | Succubus | 12% | **3.67x** — the glass caster was the survivor |

   A 21x spread with the designated soakers at the fragile end. Share is now solved from aggro
   (`COMPANION_LIFETIME_TARGET = 1.25`), clamped **below by the old 0.5** so no existing
   companion can be weakened — the standing rule that player investment is never downscaled.
   Spread 21x → 5x; an Iron Golem goes 0.5 → 2.0 share.

**The share is NOT a share of the player's HP** — a recurring misreading, recorded here so it
is not re-derived. It multiplies `max(owner_side, own_side)`, and for any invested companion the
**own-level anchor wins outright**:

| case | owner HP | owner_side | own_side | compHP |
|------|----------|-----------|----------|--------|
| L50 owner, L50 Succubus | 659 | 659 | 659 | 330 |
| L50 owner, L50 Iron Golem | 659 | 659 | 659 | 1318 |
| **L10 owner, L250 Succubus** | 120 | 120 | **2260** | **1130** |
| **L10 owner, L250 Iron Golem** | 120 | 120 | **2260** | **4521** |

A L250 companion on a L10 character has ~9.4x that character's HP. The owner's level never
enters the result once the companion out-levels them. `tools/probe/comp_hp_probe.gd` prints this
table on demand.

- [ ] **Still open: a matched companion survives only ~3 rounds at L1000** (`-- comp_unlock`,
      soaking 0.6 hits/fight) even after both fixes. Win% with one is 63% against 6% without, so
      companions carry enormous weight up there — but they are being knocked out early in the
      long fights. Re-measure after the curve re-calibration below before tuning further
- [ ] **Re-run `-- refcal` + `-- roles`.** Companion durability is a PLAYER-SIDE power change, so
      per the top-of-CLAUDE.md rule the monster curve is now stale. This already bit once when
      the companion HP rework pushed elite-at-L1 to 90% against a 70% target

**MEASURED 2026-09-02 (`-- comp_unlock`) — it is companion HP, not unlocks, not bonuses.**

The user's read was right and both of the assistant's hypotheses were wrong. Same-level ELITE,
Fighter, average gear, 24 fights/cell. `survived` = rounds up before KO, `soaked` = hits the
monster spent on the companion instead of the player:

| Player | comp level | comp HP | survived | soaked | win% |
|--------|-----------|---------|----------|--------|------|
| L5 | none | 0 | – | – | 50% |
| L5 | 1 | 45 | 18.3 | 2.7 | 54% |
| L5 | matched | 65 | 12.2 | 1.8 | 79% |
| L50 | 1 | 45 | **2.6** | 0.5 | 20% |
| L50 | matched | 290 | 5.9 | 1.2 | 41% |
| L250 | matched | 1,290 | **4.0** | 1.0 | 58% |
| L1000 | 1 | 45 | **1.3** | 0.3 | 50% |
| L1000 | matched | 5,040 | 20.9 | 7.5 | 79% |
| L10000 | none | 0 | – | – | 16% |
| L10000 | 1 | 45 | **2.6** | **0.1** | 12% |
| L10000 | matched | 50,040 | 27.3 | 6.1 | 50% |

- **`calculate_companion_max_hp` is `30 + level*5 + sub_tier*10 + hp_bonus` — linear**, while
  monster damage is now anchored to a player curve that is not. A level-1 companion has **45 HP
  at every level in the game**: at L10000 it survives 2.6 rounds, soaks **0.1 hits**, and wins
  12% against 16% for no companion at all. It is not a sponge and not an attacker; it is a
  casualty. That is the real explanation for "comp L1 == none"
- **The ability-unlock hypothesis is DISCONFIRMED.** There is no step at companion level 5 or
  15 — L1000 reads 50% / 66% / 41% for comp levels 1 / 5 / 15, which is noise. Only `matched`
  separates, and it separates by HP
- **Even a level-MATCHED companion dies mid-fight through the mid game** — 5.9 rounds at L50,
  **4.0 rounds at L250** against a fight designed to last 9. This is the user's reported
  frustration measured directly: *"companion HP always seems rather low, they die frequently
  and players have to go back to a post to bring them back to life"*
- Note also a genuine units inconsistency: `hp_bonus` is added **flat** here but consumed as a
  **percentage** of the player's max HP in `combat_manager` (`get_total_max_hp() * bonus/100`).
  The same table field means two different things in two places

**Proposed fix — anchor companion HP to the player, the way monsters now are:**

    companion_max_hp = player_max_hp * share(tier, sub_tier) * f(comp_level / player_level)

with `share` around 0.35-0.60 and `f` clamped (say 0.25-1.25) so an under-levelled companion is
weaker but never a one-hit casualty, and an over-levelled one saturates. Consequences:
survivability holds at every level by construction; levelling a companion pays visibly; and the
constant trek back to a post to revive largely goes away.

- [x] **IMPLEMENTED 2026-09-02** with `COMPANION_HP_SHARE = 0.5` (user's number): companion HP
      is now `owner_max_hp * 0.5 * g(comp_level/owner_level) * sub_tier_mult * hp_bonus_mult`.
      `g` is deliberately **asymmetric** — floored at **0.60** so an under-levelled companion
      stays a real body rather than a one-hit casualty, and rising to **2.5** so an
      over-levelled one genuinely **carries** rather than being clamped to parity. That second
      half is the mechanical form of the design premise that a registered companion pulls a
      fresh character forward, and of the setting's line that companions outlive their delvers.

      **Measured after (`-- comp_unlock`), win% at same-level elite:**

      | Player | none | comp L1 | matched | carry (10x level) |
      |--------|------|---------|---------|-------------------|
      | L5 | 50% | 50% | 54% | **83%** |
      | L50 | 25% | 33% | 45% | **75%** |
      | L250 | 45% | 20% | 62% | **75%** |
      | L1000 | 41% | 54% | 75% | 66% |
      | L10000 | 8% | 16% | 50% | 37% |

      Under-levelled companions went from useless to useful (L50 comp-L1: 20% -> 33-41%, with
      HP 45 -> ~178). The carry case lands hardest exactly where it should — at L5-L250, where
      a fresh character is being pulled through. At L1000+ "carry" converges on "matched"
      because companion level is capped at 10000, so there is nothing left to carry with.
- [x] Reconciled the `hp_bonus` units bug in the same pass — it is a **percentage** everywhere
      now, matching how `combat_manager` already consumed it
- [x] Both client-side mirrors of the formula updated. `client.gd` now calls the real static
      function instead of re-deriving it; the combat panel keeps a placeholder only for the
      frame before the authoritative `combat_update` lands
- [x] **Live playtest at L250 PASSED (2026-09-02).** User: *"Companion did survive the fight
      but was taking adequate damage. Companion HP bar timing seemed right."* That is precisely
      the target — a companion that survives a fair fight while still being at risk, rather
      than either a one-hit casualty or an invulnerable pet. `COMPANION_HP_SHARE = 0.5` is
      confirmed by feel, not just by simulation
- [x] **No-downscaling requirement verified** — a L250 companion measures 1130 HP beside owners
      at L10 / L50 / L250 / L1000 alike. Beside a fresh character that is eight times their own
      health bar
- [ ] **The companion buff moved the whole difficulty curve** and the monster curve was
      calibrated BEFORE it. The reference player is now meaningfully stronger, so monsters are
      undersized: measured after the change, elite at L1 reads **90% win at 28% HP cost against
      a 70% target** (it was 56% before). Re-calibration is running; **any balance number taken
      between the companion change and that re-calibration is stale**
- [ ] Sample noise: 24 fights/cell, and some rows invert (L250 comp-L1 reads 20% against 45%
      for no companion). Widen before treating any single row as real
- [ ] `calculate_companion_max_hp` is **static and takes only the companion dict**, so it has no
      access to the player. Threading the owner through is the main implementation cost; check
      every caller, including any client-side mirror
- [ ] Reconcile the `hp_bonus` flat-vs-percentage inconsistency in the same pass
- [ ] Re-run `-- comp_unlock` after the change; it is the regression test for this item
- [ ] Companion **damage** also scales linearly (`player_level*0.3 + companion_level*0.5`)
      against content that no longer does. Same class of problem as the HP; fix together

- [ ] Make companion **stat bonuses scale with companion level**, not just variant/sub-tier —
      this is what makes a fresh companion feel like nothing at all today
- [ ] Find and fix the **high-level saturation** (x10 stops beating level-matched past ~L5000)
- [ ] Re-shape ability scaling so it keeps pace with content rather than falling behind
- [ ] Give levelling a companion a **visible, worthwhile payoff curve**; make the ways to
      improve one (levels, fusion, sub-tier, variants) legible and reachable
- [ ] Re-run `-- companion` after each change; it is the regression test for this item

### 6c. Class balance & the resource economy — ability shapes FIXED; class tuning remains
*Split out of item 6 on 2026-09-02: item 6 had grown to 21 open tasks covering two different
jobs — sizing the MONSTERS and sizing the CLASSES. They are separate, and the second depends on
the first being settled.*

**Prerequisite DONE (2026-09-02): re-measured against the new baseline.** The numbers below
are current; anything quoted from before the reference-player model landed is superseded.

**RE-MEASURED against the reference-player baseline, 2026-09-02.** These supersede every
class/race number taken before the monster model changed.

**Classes** (`-- classes`, 60 fights/cell, average gear, win% / turns / casts-per-turn):

| Class | path | L10 normal | L30 elite | L80 elite |
|-------|------|-----------|-----------|-----------|
| Fighter | warrior | 81% | 45% | 50% |
| Barbarian | warrior | 65% | 41% | 48% |
| **Paladin** | warrior | 50% | **31%** | **36%** |
| Wizard | mage | 80% | 40% | 38% |
| Sorcerer | mage | 66% | 53% | 45% |
| **Sage** | mage | 66% | **20%** | **18%** |
| Thief | trickster | 56% | 56% | **80%** |
| Ranger | trickster | 45% | 45% | 63% |
| Ninja | trickster | 51% | **75%** | 71% |

- Elites are now genuinely hard, which is the ROLE_TARGETS design (9 turns, 70% of the bar)
  rather than a regression
- **Sage is the worst class in the game by a wide margin** — 20% and 18% where its own
  archetype siblings sit at 40-53%. Its passive is 25% cheaper mana, which is worth least
  in exactly the fights that matter. First thing to look at
- **Paladin is second-worst** (31/36 against Fighter's 45/50) and the slowest (17 turns at
  L80 elite)
- **The trickster lead persists** and widens with level (Thief 80%, Ninja 71% at L80 elite).
  Likely mechanism already identified: Exploit is the only ability whose damage is a
  percentage of target max HP

**Races** (`-- races`, L30 elite) — a real ~20-25 point spread, previously invisible because
`make_char` hardcoded Human:

| Race | Fighter | Wizard | Thief |
|------|---------|--------|-------|
| Human | 50% | **58%** | 75% |
| Elf | 48% | 53% | 63% |
| Dwarf | 41% | 50% | **76%** |
| **Ogre** | 41% | **33%** | **51%** |
| Halfling | 51% | 51% | 75% |
| Orc | 38% | 48% | 68% |
| Gnome | 45% | 36% | 66% |
| **Undead** | **28%** | 50% | 66% |

- **Human is at or near the top for every archetype**, which is backwards: its trait is +10%
  XP, an out-of-combat bonus. A race with no combat trait leading combat means the other
  races' traits are underpowered or not firing
- **Undead (28% Fighter) and Ogre (33% Wizard) are the weak ends.** Ogre's trait is doubled
  healing received and Undead's is curse immunity + poison healing — both situational, and
  worth nothing in a fight that contains neither
- [ ] Check whether the situational racial traits ever actually trigger in combat before
      re-balancing their numbers — a trait that never fires is a UI problem, not a tuning one

**Companions** (`-- companion`, same-level elite, Fighter) — the gap is now large and holds
at every level, which it did not appear to under the old model:

| Level | none | comp L1 | comp L=char | comp x10 |
|-------|------|---------|-------------|----------|
| L50 | 7% | 40% | 30% | 72% |
| L1000 | 37% | 45% | 75% | 82% |
| L2500 | 12% | 17% | 50% | 45% |
| L10000 | 10% | 15% | **50%** | 50% |

- **A levelled companion is worth ~35-40 points of win rate** at high level (10% -> 50% at
  L10000). Companions are now clearly load-bearing, which makes 6b more urgent, not less
- **`comp L1` is still statistically indistinguishable from `none`** at the top end (10 vs 15,
  12 vs 17) — the flat-stat-bonus finding survives re-measurement
- **The x10 saturation also survives** (L10000: matched 50%, x10 50%; L2500: 50 vs 45) —
  over-levelling a companion past your own level stops paying

**Ability power** (`-- ability_hp`, one cast as % of a same-level normal monster's health
bar). **The monster model fixed the early game on its own, without touching a single
ability:**

| Ability | L1 | L5 | L50 | L100 | L1000 | L10000 |
|---------|----|----|-----|------|-------|--------|
| power_strike | **15%** (was 263%) | 10% | 15% | 18% | 25% | 16% |
| cleave | **20%** (was 337%) | 14% | 17% | 20% | 33% | 18% |
| ambush | **18%** (was 261%) | 11% | 13% | 15% | 22% | 15% |
| exploit | 9% | 10% | 17% | 17% | 17% | 16% |
| gambit | 13% | 9% | 16% | 28% | 24% | 12% |
| **magic_bolt** | **60%** (was 1203%) | 36% | 37% | 43% | **123%** | **269%** |
| **blast** | 63% | 32% | 10% | 44% | 13% | **5%** |
| meteor | **193%** (was 3463%) | 87% | 30% | 27% | 36% | 18% |

- **The early-game trivialisation is gone.** Every damage card used to be 2.6x-35x overkill on
  a same-level monster at L1; nothing one-shots now. That was the reported "Magic Bolt is
  extremely powerful early game" problem and it is **fixed as a side effect of anchoring
  monsters to the player** — no ability was touched
- **Warrior and trickster kits are now flat across four orders of magnitude** (10-40% of a
  health bar from L1 to L10000). That is what "balance holds throughout the game" looks like
- **The mage roster is now the isolated problem**, and it is two opposite failures in one kit:
  - [ ] **Magic Bolt is the only ability that outscales** — 36% at L5 rising to **269%** at
        L10000. Its `mana x (1 + 4.3*sqrt(INT))` shape rides a mana pool that grows faster
        than level
  - [ ] **Blast dies** — 63% down to **5%**, so mage sustain evaporates while its burst
        inflates. This is the mechanism behind Wizard's 40-155 turn fights
  - [ ] Meteor decays from 193% to 18% and needs re-siting against the other two
- **Correction to an earlier hypothesis:** the trickster lead was attributed to Exploit being
  the only %-max-HP ability. Against anchored monsters Exploit is now **flat at 9-25%**, yet
  tricksters still lead the class table (Thief 80%, Ninja 71% at L80 elite). So Exploit is not
  the driver — look at Outsmart's instant-win and the dodge/speed advantage instead

- [ ] **Mage roster rework — the clearest class problem, now measured on a clean baseline.**
      Final n=90 run, after the stale-curve and monotonic-ramp fixes, one cast as % of a
      same-level normal monster's health bar:

      | Ability | L10 | L100 | L1000 | L10000 | drift |
      |---------|-----|------|-------|--------|-------|
      | **magic_bolt** | 39% | 80% | 114% | **467%** | **~12x** |
      | power_strike | 13% | 33% | 16% | 128% | ~9x |
      | cleave | 15% | 39% | 23% | 123% | ~8x |
      | gambit | 10% | 49% | 17% | 47% | ~4x |
      | ambush | 10% | 33% | 17% | 31% | ~3x |
      | exploit | 10% | 17% | 28% | 24% | ~2x |
      | blast | 24% | 19% | 10% | 27% | flat, low |
      | meteor | 73% | 51% | 24% | 38% | flat (but 175% at L1) |

      - **Magic Bolt is unambiguous.** It has now measured 269 / 481 / 505 / 467% at the top end
        across four different baselines — the number moves, the verdict does not. Its
        `mana x (1 + 4.3*sqrt(INT))` shape rides a pool that grows faster than level, and
        nothing else in the game does
      - **Warrior burst is a secondary riser** — power_strike 128% and cleave 123% at L10000,
        ~8-9x drift. Not as severe, but the same shape and worth fixing in the same pass
      - **Tricksters are the best-behaved kit** (2-4x drift, flat 10-31%) — the shape to aim for
      - **Blast is weak but stable** (10-27%), not collapsing as it appeared against the old
        baseline. A smaller problem than first reported
      - **Meteor is 175% at L1** — the last remaining early-game one-shot Burst inflates while
      sustain evaporates, which is the mechanism behind Wizard's very long fights. **Sage is
      the worst class in the game** (20%/18% at L30/L80 elite) — its 25%-cheaper-mana passive
      is worth least in exactly the fights that decide things
- [ ] **Trickster lead** (Thief 80%, Ninja 71% at L80 elite against Paladin's 36%). The
      earlier hypothesis — that Exploit's %-max-HP damage was the driver — is **disconfirmed**
      by the re-measurement: against anchored monsters Exploit is flat at 9-25% like everything
      else, yet tricksters still lead. Look at Outsmart's instant-win and the dodge/speed
      advantage instead
- [ ] **Paladin is second-worst and slowest** (31%/36%, 17 turns at L80 elite)
- [ ] **Magic Bolt flat curve** — damage-per-mana has to scale on the same curve as monster HP
**RESOURCE ECONOMY DISSOLVES WITH LEVEL — measured 2026-09-02 (`-- economy`).**
Reported from live play: *"Blast shows it costs 0 but did 1900 damage... this may be a problem
for warriors and tricksters as well."* It is, and it is all three archetypes.

Costs ARE charged — the "0" on screen is regen refilling the spend within the same turn — but
they are trivial relative to the pool:

| Level | Ability | cost | pool | cost% | **casts per full bar** |
|-------|---------|------|------|-------|------------------------|
| L10 | blast | 34 | 130 | 26% | **4** |
| L10 | ambush | 20 | 114 | 18% | **6** |
| L1000 | power_strike | 66 | 3,192 | 2.1% | **48** |
| L1000 | cleave | 100 | 6,093 | 1.6% | **61** |
| L1000 | blast | 185 | 16,363 | 1.1% | **88** |
| L1000 | ambush | 104 | 7,057 | 1.5% | **68** |
| L1000 | magic_bolt | 3,171 | 15,858 | 20% | **5** |

**The resource system works at low level and evaporates by mid-game.** At L10 a mage gets 4
casts of Blast and has to think; at L1000 they get **88** and cannot run out. Every archetype is
affected — warriors 48-61 casts, tricksters 68 — so this is not a mage problem.

**Cause, and it was a deliberate decision rather than an oversight.** Ability cost scales with
the **naked pool** (base + primary stat, excluding gear), by design: the #55 comment states the
intent as *"gear +max pool no longer inflates cost, so a high-cap/high-regen build gets MORE
casts + better sustain."* That intent is reasonable. The magnitude is not: at L1000 a Wizard's
naked pool is ~800 against a total of 16,363, so **gear multiplies the pool ~20x while costs
stay fixed to the naked value** — and 20x more casts is the whole resource economy gone.

Magic Bolt is the only ability that still costs anything (20% of pool, 5 casts) because its cost
is the player's explicit spend rather than a table lookup. That is why it felt so expensive
next to everything else — it was the only card actually paying.

- [ ] **DECISION NEEDED: how much should gear inflate casts-per-bar?** Options:
      1. Cost as a % of the **total** pool — removes the gear reward entirely, simplest, and
         makes casts-per-bar constant at every level
      2. Cost as a % of a **blend** (naked + a capped share of the gear bonus) — preserves the
         intent that gear improves sustain, but bounds it to something like 1.5-2x rather than
         20x. **Recommended**
      3. Cap the gear pool bonus itself — touches more systems
- [ ] Whatever is chosen, target a **casts-per-bar band** (something like 5-10) and hold it
      across levels, rather than targeting a cost percentage. Casts-per-bar is the number a
      player actually experiences
- [ ] `devastate` reads cost 0 at every level — it is a Momentum dump and pays in Momentum
      rather than stamina. Worth confirming that is intended and not a second free-cast path
- [ ] Once costs are real again, **re-check every damage number in 6c**: ability weights were
      tuned assuming a cost that is not currently being paid
- [ ] Anti-abuse items that **never landed**: Forethought and Recharge still exist, no mitigation
      cap, no stun DR. Related user direction: remove blue "skip the enemy turn / refund
      resources" utility cards
- [ ] Equipment vs race vs class, compared **against each other** rather than in isolation
      (`-- races` and `-- classes` now exist for this)

**6c ABILITY WORK COMPLETE (2026-09-02).** Every damage ability now reads off ONE anchor —
a share of the health bar it is fighting — instead of inventing its own scaling curve.

| Ability | before | after |
|---------|--------|-------|
| power_strike | 13% → 128% (9.8x drift) | **~20% flat L1-L1000** |
| cleave | → **213%** at L10000 | **~25% flat L1-L2500** |
| magic_bolt | 39% → **467%** (12x drift) | **~50% flat** (full dump) |
| meteor | **175%** at L1 → 38% | **~50% flat** |
| blast | 49% → 10% (decaying) | **~27% flat** |

`ABILITY_WEIGHTS` is now the design statement AND the measurement: a weight of 0.22 means
"this takes a fifth of a normal monster", which is exactly what `-- ability_hp` reports.

**Three faults were found by measuring after each change rather than at the end:**
- *cleave and blast were given weights but their damage code was never converted.*
  `ABILITY_WEIGHTS` is inert until the ability reads it. Both sat drifting while their
  converted siblings went flat — the contrast is what exposed them
- *Magic Bolt read 5-6%* — the AUDIT casting a timid 25% chip, not the ability being broken
- *Sage collapsed to 8-10% win* — a REGRESSION the anchoring introduced (below)

**Magic Bolt's spend curve was redesigned on user direction.** The old efficiency floor (0.15)
made a quarter-spend only 36% as mana-efficient as a full dump, so partial investment was
punished twice and dumping was 2.8x better. But *mages fight flocks*, so committing the whole
bar is often wrong — the curve answered the question instead of posing it, and then the flock
punished the answer. At 0.80 a quarter-spend lands 21% of a full dump rather than 9%, so
"how much do I hold back for the next one" is a real risk judgement. The old floor existed to
stop cheap chips one-shotting monsters (#70); anchoring solves that directly, so the tax was
redundant and only its side effect remained.

**A REGRESSION the anchoring caused, and nearly the wrong fix.** Wisdom's combat value arrived
through the mana pool (`base_mana = 30 + INT*3 + WIS*1.5`) because old Magic Bolt scaled with
mana SPENT. Anchoring scaled damage by the FRACTION of pool committed, silently deleting that
pathway. Sage — 1.0 Wisdom/level against 0.75 Intelligence — absorbed the whole cost and fell
to 8-10% win at elite. Sage was *already* on record as "the worst class in the game" from
measurements taken BEFORE the anchoring, so the obvious move was to buff it. **An existing
known problem is perfect camouflage for a regression you just caused.** Casters now count
Wisdom at half weight; Sage recovered to 18-23%.

**Class table after 6c** (win% — L10 normal / L30 elite / L80 elite):

| Class | L10 | L30 elite | L80 elite |
|-------|-----|-----------|-----------|
| Fighter | 88% | 45% | 61% |
| Barbarian | 90% | 45% | 38% |
| Paladin | 73% | 33% | 48% |
| Wizard | 81% | 43% | 41% |
| Sorcerer | 85% | 35% | 31% |
| **Sage** | 71% | **23%** | **18%** |
| Thief | 68% | 53% | 60% |
| Ranger | 55% | 51% | **73%** |
| Ninja | 61% | 55% | 60% |

- [ ] **Sage is still last, and it is now a real class-design issue rather than a bug.** Its
      effective caster stat growth is **1.25/level** against Wizard 1.62 and Sorcerer 1.65
      (INT + WIS×0.5), a 24% deficit that its "25% cheaper mana" passive does not repay —
      cost reduction buys more casts, but each cast is anchored, so it cannot close a damage
      gap. Either raise its INT growth, or give the passive a damage-relevant clause
- [ ] **Tricksters still lead** (51-55% at L30 elite, 60-73% at L80 against 31-48% for the
      others). Exploit was disconfirmed as the cause earlier; Outsmart's instant-win and the
      dodge advantage remain the open suspects and are still unexamined
- [ ] **L10000 spike across ALL abilities, including unconverted trickster ones** (ambush 81%).
      A spike that hits converted and unconverted alike is the final CURVE anchor being low,
      not an ability fault. Fix in the curve; do not tune abilities against it
- [ ] The `ABILITY_WEIGHTS` values are proposals. "A power strike takes a fifth of a normal
      monster" is a design opinion that wants the owner's eye, and it is now a single readable
      table rather than five formulas

**PER-SPECIES SPREAD — the same level is NOT the same fight (user challenge, 2026-09-02).**

Every audit until now reported the AGGREGATE across monster types. That hides the thing a
player actually experiences, because a player meets one monster at a time, not an average.
Measured (`-- species`, same level, same gear, 45 fights per species):

| L50 species | win% | turns | spawn% |
|-------------|------|-------|--------|
| **Titan** | **31%** | 3.0 | 2% |
| Lich | 40% | 10.9 | 2% |
| Chimaera | 48% | 4.0 | 5% |
| Young Dragon | 62% | 4.6 | 10% |
| Gryphon | 73% | 3.7 | 7% |
| Demon | 86% | 6.3 | 8% |
| Vampire | 93% | 6.6 | 8% |
| **Shrieker** | **100%** | 3.8 | 3% |

**SPREAD: 69 points.** At L1000 it is 64 points — **Hydra 22%** (40.4 turns!) to
**Demon Lord 86%**.

**This makes the aggregate numbers nearly meaningless as a description of play.** "L50 elite is
45%" is the average of a 31% fight and a 100% fight. A player who draws a Titan and a player
who draws a Shrieker are playing different games at the same level in the same gear.

**Cause: the reference model anchors STATS but not ABILITIES.** `compute_anchored_stats`
normalises HP, strength and defense, and the species `shape` multiplier is deliberately bounded
to ~2x. But monster ABILITIES are untouched by any of it, and they dominate:
- **Hydra: 22% win over 40.4 turns** — `regeneration` heals faster than the player can chew
  through, turning the fight into an endurance failure rather than a hard fight
- **Sphinx 22.8 turns, Lich 10.9** — the same pattern, milder
- **Shrieker 100%** — a monster whose kit does nothing threatening
- multi_strike, armored, ethereal, life_steal all sit outside the anchor as well

So the model made the *numbers* consistent and left the *abilities* to swing the outcome by 60+
points. That is also a likely source of the residual noise in every per-level audit: each cell
sampled a random species, so run-to-run variance was partly which monsters showed up.

- [x] **FIXED 2026-09-02 by per-species power calibration (`-- speciescal`).** Rather than
      model a dozen interacting abilities by hand, the sim measures each species' real win rate
      across three levels and all three archetypes and writes back one power multiplier.
      Targets a BAND (48-72%) not equality, and only corrects species outside it — variety is
      the point, a Hydra should still be harder than a Harpy.

      | | before | after |
      |---|--------|-------|
      | L50 spread | 69 pts (31%-100%) | **38 pts (57%-95%)** |
      | L1000 spread | 64 pts (22%-86%) | **24 pts (64%-88%)** |

      **Hydra went from 22% win over 40 turns to 64%** — the regeneration-outpaces-damage case
      that made a fight an endurance failure rather than a hard one. 29 species corrected; the
      largest were Harpy x1.70, Shrieker x1.65 and Wraith x1.64 (too easy, made harder) against
      Hydra x0.60 and Primordial Dragon x0.61 (too hard, softened).
- [ ] Residual 38-point spread at L50 is worth one more pass — the calibration ran 3 passes and
      several species were still moving. Note the verification audit measures **Fighter only**
      while the calibration used all three archetypes, so its absolute win rates read high; the
      SPREAD is the comparable number, not the level
- [ ] `regeneration` may still deserve a direct cap rather than being counterweighted by a
      blunt power multiplier — a monster that heals faster than you damage it is a bad
      experience even when the win rate says it is fair
- [ ] **`regeneration` is the standout and may deserve a direct fix first** — it converts a
      stat problem into a time problem, and a 40-turn fight is a bad experience even when won
- [ ] Re-check the residual noise in the per-level audits once species are anchored; some of
      what was blamed on sample size may be species selection
- [ ] **Playtest instructions must name real species.** `/spawnmonster Orc 50` was used for
      several manual tests and Orc has a **0% spawn rate at L50** — a tier-2 monster stretched
      up, exactly the bug that was fixed in the sim and then reproduced by hand in the manual
      test. Use the actual spawn table: at L50 that is Gryphon, Succubus, Vampire, Giant,
      Demon, Young Dragon, Chimaera

**STATE AFTER THE RESOURCE FIX (2026-09-02, n=90).** Costs are real again and the mage kit
was re-priced, and both landed harder than expected:

| Class | L30 elite before | after | L80 elite before | after |
|-------|------------------|-------|------------------|-------|
| Wizard | 43% | **66%** | 41% | **58%** |
| Sage | 23% | **45%** | 18% | **31%** |
| Sorcerer | 35% | 51% | 31% | 51% |
| Fighter | 45% | 43% | 61% | 63% |
| **Paladin** | 33% | **21%** | 48% | 40% |
| Thief | 53% | 60% | 60% | **75%** |

The mage recovery is mostly the **Magic Bolt ceiling** (`MAGIC_BOLT_FULL_SPEND_PCT = 0.20`):
the sim's mage AI spends 25% of its pool per cast, which under the old whole-pool scaling
delivered a quarter of the ability's weight. It now delivers the full weight. So a large part
of "the mage roster is weak" was the ability's spend curve, not the roster.

Roles held through the change: normal costs 32-50% against a 40% target, empowered 34-58%
against 55%.

- [ ] **Paladin is the new worst at L30 elite (21%)** and the slowest (13.3 turns at L80).
      Different class from the one that was worst an hour ago, which is a reminder that these
      rankings move whenever a shared system changes — do not tune a class until the systems
      under it have settled
- [ ] **Class spread is still 44 points** at L80 elite (Sage 31% to Thief 75%). Narrower than
      the 55 it was, still too wide
- [ ] **Turn drift at L250-L1000** (normal 12.7 and 9.2 against a 5 target; empowered 17.7).
      The HP axis is not holding in the mid-upper band even though cost is
- [ ] Re-run `-- ability_hp`: the weights were set when casts were effectively free, and a
      fight now has a real cast budget

**GEAR VARIANCE — the player-side mirror of the species spread (user question, 2026-09-02).**
Prompted by finding a *Guardian's Magical Orb of the Troll* (+60 DEF, +432 HP, +79 MP) that was
"way bigger than anything I was wearing" — +432 HP on a 652-HP character.

The simulator DOES account for items like it: `make_char` rolls gear through the real
`_generate_item` with rarity drawn from the game's own `RARITY_WEIGHTS`, fresh for every fight,
so across 90 fights it samples the whole distribution. What it does not do is *report* the
distribution. Measured, 200 builds of the same class at the same level:

| Level | min HP | median | max HP | spread |
|-------|--------|--------|--------|--------|
| L50 | 363 | 463 | 1,265 | **3.5x** |
| L250 | 1,113 | 2,017 | 5,878 | **5.3x** |

**Gear luck alone moves a character's health bar by 3.5-5x at a fixed level** — a wider swing
than the 69-point species spread, and the two multiply. A lucky player meeting a weak species
and an unlucky one meeting a Hydra are not playing the same game at the same level.

**This is probably correct for an ARPG and should not simply be "fixed".** Finding an item that
doubles your health bar is the chase, and flattening it would remove the reason to hunt loot at
all. The honest consequence is about how the balance numbers are *read*:

- [ ] **Every difficulty figure in this file describes a MEDIAN player in MEDIAN gear against a
      MEDIAN monster.** Very few real fights are all three. State that wherever the numbers are
      used to make a decision
- [ ] **Measure the tails, not just the mean.** A 10th-percentile-gear player against a
      high-difficulty species is the combination that actually generates complaints, and nothing
      currently measures it. Worth an audit that reports p10 / p50 / p90 rather than an average
- [ ] Decide whether the tails need *bounding* or merely *communicating*. Bounding item variance
      is an ARPG design change; communicating it (e.g. difficulty telegraphed per encounter) may
      be the better answer
- [ ] Note the interaction with 12b: the Phantom's whole premise is that gear and companions
      carry a player forward, so wide gear variance is the loop working — provided the floor is
      survivable

### 6h. Companion & dungeon cards have never been audited (owner ask, 2026-09-04)

*Placed after 6c because these cards compete for a deck slot against CLASS abilities, so they
can only be judged once class card power is settled. Everything in 6c's ability work — the
naked-pool cost model, the anchor decoupling, the milestone upgrade pool — was applied to the
class roster and never to these.*

Owner: *"companion cards need an audit to make sure their power is appropriate, see if they have
good upgrade options like the other abilities, ensure buffs are usable on other party members,
etc."* Covers both families, since `_process_companion_ability` already serves
`companion_card_*` and `dungeon_card_*` through one processor.

**Two defects are confirmed by reading the code — no probe needed:**

- [ ] **A companion buff cannot be aimed at a teammate.** `PARTY_TARGETABLE_BUFFS` is a
      hardcoded list of six CLASS abilities (`forcefield / haste / iron_skin / fortify / rally /
      berserk`) in both `combat_manager.gd` and `client.gd`. No companion or dungeon card is in
      it, so the picker never opens for one and the server would refuse the target anyway. Every
      `kind` that grants a buff or shield is therefore self-only, which is exactly the ask.
      Note the shape: a hardcoded ability list that a new card silently falls outside of — the
      same failure that left War Cry in the damage-buff slot for months. Prefer deriving
      targetability from the card's `kind` over adding names to a second list
- [ ] **The cost is a flat 10.** `apply_skill_cost_reduction(character, ability_name, 10)` in
      `_process_companion_ability` — a constant, before reduction, for every companion card at
      every level. The whole point of #55's naked-pool model is that a flat cost stops mattering
      as pools grow; these cards were left on the old shape. At high level they are effectively
      free, which is most of the "is their power appropriate" question on its own

**Open questions — measure, do not guess:**

- [ ] **Do they even rank up?** `card_upgrades.eligible()` picks from a kind-based pool, so
      nothing there excludes a companion card — but that only matters if the mastery/milestone
      path fires for `companion_card_*` ids at all. Verify with a probe before concluding either
      way; assuming it works and assuming it doesn't are equally cheap mistakes here
- [ ] **Are the offered upgrades meaningful for these kinds?** The pool was written against
      damage / buff / control class cards. Kinds like `loot` and `resource` may map onto nothing
      worth offering, which would show up as a rank-up that hands the player three dead choices
- [ ] **Where does their power sit against a class card of the same tier?** Damage scales
      through the shared mastery path, but secondary values scale by the card's own usage tier —
      two different curves in one card. Compare like-for-like at several levels
- [ ] **Is a dungeon card's rarity reflected in its power?** They are the scarcest cards in the
      game (#38) and should read that way

Prerequisite: 6c's class tuning, so there is a stable yardstick to measure against.

### 6f. Open after the 2026-09-02 balance session — untested and unresolved

Everything in 6/6b/6c is committed but **NOTHING is deployed**, and most client changes have
only had partial playtesting. Read this before touching combat again.

- [x] **RESOLVED: the "missing damage" fight.** A Chimaera logged 298 damage against an 82 HP
      drop. Reproduced in the sim with empowered rolls enabled and a lifesteal companion, and
      the arithmetic reconciles exactly every time (355 + 308 heal - 270 damage = 393;
      288 + 250 - 285 = 253). The player was healed by the companion's Kiss of Death mid-round.
      Damage application was correct throughout — **the LOG was wrong**, reporting the intended
      heal (428) rather than the amount actually restored (~216, clamped by missing HP), and
      never saying the heal was for the player. Fixed; the message now reads "drains N HP for
      you" with the real figure.
      **Two separate reports were being conflated**: this one (never resolved by waiting) and a
      different fight where HP updated ~4 seconds late (which did catch up). Only the second is
      a display-timing issue
- [ ] **My regression, not yet fixed: post-combat settle timing.** Gating result display on the
      beat queue means HP and resources land *after* the victory screen instead of before it.
      User: *"my health and everything dropped around 4 seconds after combat was over."* They
      later confirmed waiting for all animations still showed no drop, so there may be a second
      cause. Start here — it undermines the trust of every screenshot taken during a playtest
- [ ] **Companion durability against apex monsters.** A Chimaera dealt 298 in a round to a
      companion with 330 HP and only `sub_tier x 3%` damage reduction, so an apex monster
      one-shots a level-matched companion. `COMPANION_HP_SHARE = 0.5` is the owner's number and
      tested well at L250 against normal monsters. Whether companions should share some of the
      player's mitigation, or simply have a larger pool, is a design call and was deliberately
      NOT guessed at
- [ ] **Build the HP ledger properly.** Instrument `process_monster_turn` to accumulate every HP
      change with its cause and assert it against the actual delta. The message-parsing version
      was removed after producing confident wrong answers three times
- [ ] **Apex species still average 53% win against their 38% target.** Wraith hit the x2.50
      correction cap (it was 75% as an apex species); World Serpent and Phoenix are part-way.
      Another `-- speciescal` pass, and look at why Wraith is so easy for its tier
- [ ] Companion **ASCII art** takes a beat to reappear after combat — likely the same playback
      gating as the settle bug
- [ ] Re-run `-- ability_hp` and `-- classes`: ability weights were tuned when casts were
      effectively free, and costs are now real
- [ ] **Sage remains last** (24% caster-stat deficit its passive cannot repay) and **tricksters
      still lead**. Both are genuine class design, untouched

### 6j. **EVERY class measurement so far modelled a player with NO class kit** (2026-09-04)

Owner: *"Ensure when looking at the sim it's accounting for ALL equipment properly now from your
audit as well as players being able to somewhat focus on farming certain stats on their
equipment."*

`make_char` drew gear from `EQUIPMENT_BASES`, which does not contain the Hoarder bases at all.
So every class/balance number the simulator has ever produced is a player who **never farmed
their own archetype's gear** — and the monster curve was calibrated against that player.

The sim now has three rungs, all built from the game's own generators (nothing invented):
`average` (no kit, the historical model), `kit` (average plus the archetype's Hoarder kit,
affixes unsorted) and `focus` (the same kit, sifting several real drops per slot for the stats
that class wants — at the MARGIN, never at the cost of overall item power).

**Measured, 60 fights/cell, elite:**

| path | L30 avg → kit | L80 avg → kit |
|---|---|---|
| warrior | 18% → 33% (+15) | 51% → 65% (+14) |
| mage | 36% → 45% (+9) | 33% → 58% (+25) |
| trickster | 58% → 82% (+24) | 82% → 90% (+8) |

Three conclusions, in order of how much they change:

- [ ] **The curve is calibrated against a player who cannot get their class kit.** The kit is
      worth +8 to +25pp. Spreading it (6i) without re-calibrating would make the game markedly
      easier than target wherever a source now exists. **6i and a `refcal` re-run are one piece
      of work, not two** — and the calibration must decide WHICH rung is the reference player
- [ ] **The kit does not explain the path gap.** Tricksters lead by 40pp at L30 without it and
      49pp with it; at L80, 48pp without and 31pp with. It narrows the endgame gap and widens
      the mid-game one, so it is a real lever but not the answer on its own. The warrior/elite
      item stands
- [ ] **Focusing is worth roughly another +10pp on top of the kit** where it helps (Fighter
      53% vs 40% at L30, Wizard 65% vs 56% at L80), but several cells move the other way by
      less than the ~6.4pp noise of a 60-fight sample. Do not tune on the focus column until it
      is re-run at a larger n

### 6k. **A Ninja's biggest growth stat buys no damage, and stops paying at ~L24** (owner ask, 2026-09-04)

Owner: *"Tricksters seem like they scale on Dex and Wit. Does that make sense? What does Dex
actually do for Tricksters, what does Wit actually do, should they be reassessed?"*

Audited by reading the real consumers. **Both stats do real work, and tricksters DO have a
damage stat — it is WITS, not DEX.**

**Two separate damage paths, and they use different stats.**

*Basic attacks* (`calculate_damage`): `base = STR + gear_STR + gear_attack`, then
`base * (1 + STR*0.02) + 1d6`. Mages get `base = max(base, INT/5)`. **Tricksters get no such
branch, and gain 0.0 STR/level (Thief, Ninja) — so their basic attack never scales at all
except through gear.**

*Ability damage* (`_ability_anchored_damage(character, stat_name, weight)`) scales on a stat
passed per card, damped `sqrt(stat / (level + 13))`:

| stat passed | cards |
|---|---|
| `strength` | 5 (warrior) |
| `intelligence` | 4 (mage; WIS counts at half weight — `ABILITY_SECONDARY_STAT_WEIGHT`) |
| **`wits`** | **2 — ambush, gambit** |
| `dexterity` | **none** |

**So WITS is the trickster damage stat and DEX is not a damage stat for anyone.**

**What DEX actually does** (all classes): hit chance `75 + (DEX - monster_speed/2)`; crit chance
`5 + DEX*0.5` **capped at 25**; dodge `min(30, DEX/5)`; initiative / ambush avoidance; flee
`+1%/DEX`; energy pool.

**What WITS actually does**: trickster ability damage; Outsmart `min(22, 9*log2(WIT/10))` plus
modifiers; trickster HP primary (`WITS*0.5`); debuff magnitude `15 + WITS/3`; flee
`(WITS - monster_speed)*0.5`; energy pool.

**The actual defect is the allocation, not the stats.** Per-level gains
(`shared/character.gd:1633-1643`):

| class | DEX/lvl | WITS/lvl | STR/lvl |
|---|---|---|---|
| Thief | 0.75 | **1.5** | 0.0 |
| Ranger | 0.75 | 1.0 | 0.25 |
| **Ninja** | **1.25** | 1.0 | 0.0 |

Thief is fine — its growth is majority WITS, its damage stat. **Ninja pours its largest share
(1.25/level, half of all growth) into DEX.**

**CORRECTED 2026-09-05 — the crit cap is 75%, not 25%.** This section originally said DEX went
inert around level 24 because crit capped at 25%. That was wrong: `player_crit_max` (25) in
`balance_config.json` is read into a local at `combat_manager.gd:9238` and **never used**. The
real cap is a hardcoded `min(crit_chance, 75)` at the roll, reached near DEX 140 — about level
100 at 1.25 DEX/level. So DEX keeps buying crit for a long time and the "inert past L24" claim
does not hold.

What still stands: dodge caps at 30% (DEX 150), and neither DEX nor WITS appears in the
basic-attack formula, so the Fighter-style "levelling buys damage" path is closed for tricksters
— their damage growth is ability weights, gear, and crit.

- [ ] **`player_crit_max` is a dead config knob.** Anyone tuning it sees no effect. Wire it to
      the cap or delete it; a knob that silently does nothing is worse than no knob

**Questions to settle** (design decision, not made):
- is Ninja's DEX-heavy allocation intended, given DEX feeds no damage directly? With the cap at
  75% it at least buys crit for ~100 levels, so this is less urgent than first written
- should tricksters get a basic-attack floor mirroring the mage `INT/5` (e.g. `max(base, WITS/5)`)
  so their auto-attacks are not frozen at creation-time STR?
- only 2 of the trickster roster's cards are WITS-scaled — check whether the rest should be

**Prerequisite:** any of these changes player power, so re-run the full calibration chain after.
Worth auditing all six stats the same way — CON feeds HP and defense but no damage, and that may
well be correct.

**Player-facing text FIXED already (commit 1f9dcdf)**: the Character Stats page said DEX gave
"Trickster damage" (false) and WIS gave "mana efficiency" (no such mechanic exists); the help
block had a stale Outsmart coefficient and four wrong per-level gain rows.

### 6i. Themed class drops belong IN the drop table, and their coverage has holes
*Owner direction 2026-09-04, out of the equipment enumeration. Placed before 6d because it is
the thing 6d's reward gradient would be built on: "the difficult ones worth the effort" needs
something worth chasing to point at.*

Owner: *"It seems like themed drops should instead be in the drop table but their type or tier
of loot should only be dropped by certain enemies. We also likely need to take a look at
ensuring some enemies throughout the tiers have them so players can chase them, possibly even
make them part of APEX monster drops."*

**How it works today** (measured, `-- gearsources`): three monster ABILITIES each own a
hardcoded 35% branch in `combat_manager.gd` that calls a bespoke generator —
`generate_warrior_gear` / `generate_mage_gear` / `generate_trickster_gear`. Those generators are
the ONLY source of seven base types (`weapon_warlord`, `shield_bulwark`, `ring_arcane`,
`amulet_mystic`, `ring_shadow`, `boots_swift`, `amulet_evasion`), which are what actually carry
`stamina_regen` / `mana_regen` / `energy_regen` / `meditate_bonus` / `flee_bonus`. They are not
in `EQUIPMENT_BASES`, so no ordinary drop, chest or shop can produce them.

**The coverage, by monster level** — this is the part that needs fixing first:

| kit | monsters | levels |
|---|---|---|
| warrior | Minotaur, Iron Golem, Death Incarnate | 23, 200, **4500** |
| mage | Wraith, Lich, Elemental, Sphinx, Elder Lich, Time Weaver | 22, 80, 150, 250, 1200, 3500 |
| trickster | Goblin, Giant Spider, Hobgoblin, Void Walker | 2, 7, 10, **700** |

- **A trickster has NO source of their class gear between L11 and L699.** Three of their four
  sources are starter monsters; then a ~690-level dead zone.
- **A warrior has one source between L24 and L199, and then nothing until L4500.**
- Mage is the only kit with a real ladder, and even it jumps 250 → 1200.

So the chase exists on paper and is unreachable for most of the game for two archetypes out of
three. That alone probably explains part of the mage/warrior/trickster divergence in 6c — worth
checking before tuning class numbers against it.

- [ ] **Move themed drops into the drop table**, gated by monster rather than branched in
      combat. Today each is a hand-written `if ABILITY_X in abilities` block with its own rarity
      floor and its own +15% level boost, so rarity rules, affix rules, tier scaling, market
      pricing and salvage all have to be re-derived per branch instead of inherited. A
      `themed_drop` field on the monster naming a kit, resolved through `roll_drops`, gets all
      of that for free and makes adding a new themed kit data rather than code
- [ ] **Fill the tier holes** so every archetype can chase its kit at any point in the curve.
      The table above is the gap list
- [ ] **Consider APEX monsters as themed-drop carriers.** They are already the "formidable foe"
      tier by name and by `APEX_SPECIES`, and giving them the kit ties the reward gradient to
      the thing players already read as dangerous. Ties directly to 6d
- [ ] While there: `generate_*_gear` boosts item level 15% and floors rarity at uncommon. Decide
      whether that stays the themed-drop rule or becomes a property of the monster's tier

### 6d. Risk, reward & progression incentives
*Also split out of item 6. This is the economy around fights rather than the fights themselves.*

- [ ] **Re-measure the risk/reward table now that escape works**, then decide whether the
      1.2-9.3 level over-level payouts need raising. The `-- risk` audit models a player who
      attacks first and flees once hurt; against something far above you that first exchange is
      often fatal, so its escape column understates a player who runs on sight. Add a
      "flees immediately" mode before drawing conclusions from it
- [ ] **Should escaping COST something?** A successful flee is currently free. Dropping carried
      loot, taking a lasting wound or burning a consumable would make disengaging a real trade
      rather than a pure out. A design call, deliberately not made unilaterally
- [ ] Sample-size caveat before tuning on these numbers: 36 fights per cell, and the kill%
      column is visibly noisy (L50 read 2% at x2.0 but 13% at x3.0 — monster-selection
      variance, not a real inversion)
- [ ] **Gear acquisition must actually exist** at every level band — the loop depends on players
      having a real way to get better gear, not just on the gear existing in a table.
      **Largely owned by 12b (the Phantom)**, which is the designed answer; this line stays as
      the check that the answer covers every band

### 7. New player experience — the way the game should actually START
*User direction 2026-09-03, and MOVED UP from the bottom of the unordered "Independent" bucket
at the owner's request: "it seems like it's time to move it up."*

**Why it is placed HERE, immediately after item 6, rather than in the dungeon arc: it is the
resolution of an open balance decision, not just a UX arc.** The playtest on 2026-09-03 found
that `refcal` anchors the entire monster curve to `make_char(level, "average")` — **average gear
PLUS a companion** — while a brand-new character has neither. Measured: the reference-player
Fighter spent ~10% of its health bar per fight against a 40% target, and a gearless L5 Ranger
needs 6.2 turns to kill what kills it in 8.1. That gap is what killed four starter characters.

The output of this item is *"basic equipment, one registered companion, and a firm understanding
of the game loop"* — which is precisely **option (b) of that decision: make every new character
BE the reference player.** So building this makes item 6's low-level band correct by
construction, and no separate low-level curve is needed. The owner chose this by describing it.

**Not to be confused with 12b (The Phantom).** 12b is the *endgame outward* loop — player-built,
egg-stocked, scaling Phantoms at the edge of survivable territory. This item is the player's
FIRST Phantom, bespoke and controlled. They share vocabulary deliberately: the tutorial teaches
the loop that 12b eventually scales.

#### What already exists to build on (do not rebuild these)
- `TUTORIAL_STEPS` (client.gd ~1625) — a 7-step guided tour with `wait_for` gates
  (`continue` / `move` / `inventory_open` / `inventory_close` / `done`). This IS the "current
  guided tour" the owner refers to
- `pending_tutorial_prompt` → **Tutorial / Skip** action-bar buttons, plus
  `_toggle_disable_tutorial()`. **Skipping already exists** for the main tour — the owner's ask
  is that it exist for the NEW sanctuary tour too, and be togglable throughout
- `tutorial_hint_panel` + `_drain_new_player_modals` — first-touch hints per system, queued
- The **party system** (v0.9.738-740), which is why an NPC party member "shouldn't be that big
  of a lift" — correct, it is a party member with a server-driven action each round
- The **dungeon system**, for a bespoke short Phantom
- **Soul gems** (`character.soul_gems`) — the existing companion-registration currency, i.e.
  the "stones" the tutorial must explain how to get more of
- The **Kennel** (`persistence_manager`, 30-500 slots) — where registered companions live

#### What this REPLACES (must be removed in the same arc)
- [ ] **The free Goblin egg auto-granted on character creation** (`server.gd` ~2867). The owner:
      *"eliminate/disable the free egg/companion that new characters currently get as this
      system will replace that."* The tutorial Phantom's egg + guaranteed registration item is
      the replacement
- [ ] **The `pathfinder_1` → `pathfinder_2` → ... starter chain**, also auto-added at character
      creation (same code site). This is the current "starter quest" and the thing being
      replaced. DECISION: retire it entirely, or keep it as post-tutorial content? It is a
      gathering chain, so it teaches a different system than this arc does

#### The stages, as specified

**Stage 1 — Account creation / first login: the Sanctuary tour**
- [ ] On **account** creation (before any character exists), a guided tour of the Sanctuary,
      in the same style as the existing character tutorial
- [ ] **Skippable**, and the skip must persist. Note the Sanctuary is account-level while the
      existing tutorial is character-level, so this needs an account-level "seen/skipped" flag

**Stage 2 — First character login: the existing guided tour**
- [ ] After the Sanctuary tour and character creation, the existing `TUTORIAL_STEPS` tour plays
      on login, unless skipped or toggled off. Mostly wiring + ordering, since it exists

**Stage 3 — Tutorial quest, NPC interaction, and the inventory lesson**
- [ ] A tutorial quest with **NPC interaction and theming** (the Keeper's voice is the natural
      fit — see `docs/design/setting_bible.md`)
- [ ] Grant **a piece of gear or two**, then teach, in order: open the inventory → view an item
      → **what the stats mean** → equip it
- [ ] The "what the stats mean" step is the one with no existing surface to reuse; item
      inspection exists, a stat *explainer* does not

**Stage 4 — The first Phantom (tutorial dungeon)**
- [ ] Guided into it by quest or NPC
- [ ] **CONTROLLED: no random encounters during this stretch.** The owner is explicit — a new
      player must not be killed by a wandering spawn before finishing. Needs an encounter
      suppression flag on the character/route, which is a *new* mechanic (the player-post
      suppression floor is a different thing and is gated off)
- [ ] **Short** — "only a few monsters to speak of"
- [ ] Contains **all of their starter equipment**
- [ ] Contains **one egg**
- [ ] A **boss**, which an **NPC party member** helps kill. Reuses the party system; the NPC
      needs a simple server-side action policy each round
- [ ] The NPC ally may also have a companion (demonstrates companions in combat before the
      player owns one)

**Stage 5 — Eggs, companions, and registration (the payoff)**
- [ ] Teach **what eggs are and how to hatch them**
- [ ] A **guaranteed companion-registration item in the final Phantom chest** — or handed over
      by the NPC
- [ ] Walk through **equipping the companion**
- [ ] Walk through **checking companion stats and info** — and the owner flags this surface as
      inadequate: *"I don't think we can currently see much regarding companion stats or ways to
      compare them quickly and easily to other companions (like we can our equipment from our
      inventory at a glance)."* **This is a real sub-project, not a tooltip** — a companion
      stat/compare view with at-a-glance comparison, matching what equipment already offers
- [ ] Walk through **registering** the companion, and say plainly **what registration means**
- [ ] Explain **how a registered companion carries to a FUTURE character if this one dies** —
      this is the permadeath consolation and arguably the single most important thing a new
      player can be told about the game's shape
- [ ] Explain **how to get more soul gems** to register more companions later

**End state:** basic equipment, one registered companion, and a firm grasp of the loop.

**Stage 0 — EVERYTHING IS SKIPPABLE, including the rewards** *(owner clarification 2026-09-03)*
- [ ] The **tutorial starter quest that grants the equipment and the companion must be
      skippable too**, not just the tours. Two reasons given, and they want different handling:
      1. **A returning player bringing their own gear and registered companions.** They do not
         need the starter kit and should not be walked through equipping their first item
      2. **A player who just wants the challenge**, skipping the quest AND its rewards
- [ ] So the skip is offered per-stage, and skipping the Phantom stage forfeits its rewards
      (gear, egg, registration item) as an accepted consequence rather than a bug

**⚠ CONSEQUENCE — this partly re-opens the gear-anchor decision, and the note above it should
be read with this.** Item 7 was placed after item 6 because its output makes every new character
equal the reference player the monster curve is anchored to. **A player who skips lands back in
the gearless hole** — the one that measured 6.2 turns to kill against 8.1 to live, and killed
four starter characters. Who actually skips:

| skipper | are they geared? | verdict |
|---|---|---|
| returning player with stored gear + registered companions | **yes** | fine — they ARE the reference player by another route |
| player choosing the challenge | **no** | fine ONLY if it is an informed choice, not a hidden difficulty spike |

So the honest form of the earlier claim is: **the curve is correct by construction for players
who COMPLETE onboarding, and skipping is an explicit difficulty choice.** That is defensible,
but it means:
- [ ] The skip prompt must say plainly what is being given up — "you will start with no gear and
      no companion, and the world is sized for a character who has both". Not a bare Yes/No
- [ ] Worth deciding whether a gearless character should still be *survivable* at L1-5 (so
      skipping is hard rather than fatal), which is option (a) of the original decision. Doing
      BOTH (a) and (b) is coherent: onboarding gives you the kit, and the first few levels do
      not assume it

#### Open decisions inside this item
- [ ] Retire the Pathfinder chain, or keep it as follow-on content? (see above)
- [ ] Scope of the companion stat/compare rework — a read-only compare view, or does it also
      absorb the 6b companion-power work already open?
- [ ] Does the guaranteed starter gear come from the Phantom only, or partly at Stage 3? The
      spec says gear at Stage 3 AND "all of their starter equipment" in the Phantom

### 7b. Monster packs (a party of N meets ~N monsters)
*Renumbered from 7 on 2026-09-03 when the new-player experience took that slot. Nothing
else in this file referenced it by number.*
Last of the core combat work: packs multiply monsters per fight, so sizing them before 6 fixes
per-monster numbers guarantees a redo.

---

## ⚑ PLAYTEST 2026-09-03 (post-v0.9.741) — six findings, three of them one root cause

Owner played Warrior, Mage and Trickster out of the starter post. **Two Warriors and two
Tricksters died to gnolls.** Findings, in the order they should be fixed:

### A. The combat cards LIE about damage — one cause, most of the report

`client.gd::_estimate_ability_card_effect` is a hand-copied mirror of the server's damage
formulas. The **#6c anchoring pass converted 5 abilities** (power_strike, cleave, magic_bolt,
blast, meteor) to `bar x weight x stat_ratio` **and the mirror was never updated**, so every
converted ability's card is now wrong. Measured on a fresh gearless character
(`tools/probe/card_vs_server.gd`):

| ability | card says | server does | card/real |
|---|---|---|---|
| forcefield (L5 Wizard) | 252 | 27 | **6.0x over** |
| meteor (L5 Wizard) | 644 | 314 | **2.1x over** |
| magic_bolt (L5 Wizard) | 57 | 383 | **0.15x — 6.7x UNDER** |
| power_strike (L5 Fighter) | 51 | 125 | 0.41x under |
| cleave (L5 Fighter) | 64 | 159 | 0.40x under |
| devastate (any) | flat 5x | 3x at 1 Momentum, 7x at 5 | wrong both ways |
| shield_bash / ambush / gambit | — | — | 1.00x (still legacy, so still correct) |

The owner's exact reports reproduce: *"Field said 252 shield on the front of the card and only
gave 28"*, *"used the meteor and it only did 264 even though it said 554"*, *"did a mana bolt
for 17 and it did over 200 even though the card only showed like 20 some"*.

Note the signature: the mirror is **exactly right for every ability that was NOT converted**.
That is a partial migration, not random drift.

- [x] **DONE 2026-09-03 — the mirror no longer decides.** `combat_manager.preview_ability_effect()`
      ships in combat_state as `ability_effects` beside `ability_costs`; the client renders what
      it is told. The preview runs the REAL modifier chain rather than mirroring it again.
- [x] **DONE — Forcefield card front** corrected (it was the last surface still on `100 + INT*8`).
- [x] **DONE — drift guard.** `tools/probe/preview_drift.gd` drives the real resolve path and
      compares. Run it after touching ANY damage formula. It immediately caught three things a
      review would not have: the preview was 20% high everywhere (rank-0 mastery), Devastate's
      stamina dump makes a full bar 1.5x, and **both** mirrors still carried pre-#55 constants —
      Ambush at 3.0 against the code's 2.2, and Exploit advertising 35% of a health bar when it
      removes 22%. Those two had been lying to Tricksters since #55 with nothing to catch them.
      22 checks, 0 drift

### B. Only 5 abilities were anchored, so the CLASSES are now unbalanced against each other

The anchored model scales with the monster health bar (509 at L3, 986 at L10). The legacy model
scales with `attack` (16-23 at those levels, gearless). So a converted ability is worth **5-10x**
an unconverted one at low level. Which abilities got converted decides which class works:

| class | converted | left on legacy |
|---|---|---|
| Mage | magic_bolt, blast, meteor — **its whole damage kit** | — |
| Warrior | power_strike, cleave | shield_bash, **devastate (its finisher)** |
| Trickster | **none** | ambush, gambit, exploit(%HP), vanish |

Measured vs a same-level Gnoll, gearless (`tools/probe/starter_fight.gd`):

| L5 vs Gnoll (860 HP) | best hit | turns to kill | turns you survive |
|---|---|---|---|
| Wizard | 372 | **2.3** | 11.3 |
| Fighter | 174 (Devastate at 5 Momentum — 5 turns to build) | 4.9 | 13.6 |
| Ranger | 75 | **11.5** | **8.1** |

**The Trickster mathematically cannot win a straight fight** — it needs 11.5 turns and survives
8.1, and it gets worse with level (L8: 16.4 turns to kill, 5.9 to live). That is precisely the
owner's report: *"I attempted to take down the gnoll with just abilities and not using the
Outsmart but ultimately didn't have the damage to do so and died."*

Also note a **basic attack does 8-21 against a 631-1239 HP monster** — 40-150 turns. Basic
attacks are no longer a way to kill anything; the monster curve is calibrated against a player
who uses anchored abilities.

- [ ] **Decide the model, then convert every damage ability to it** (owner direction needed).
      Half-converted is the current state and it is the worst one

### C. Read (Trickster) is dead past ~2 stacks

`READ_OUTSMART_PER = 15` per stack, `COMBO_MAX = 5`, so the code comments promise "+75%". But
`max_chance = 48 - monster_int/3` — **~46 for a gnoll**. From a ~27% base, stack 1 takes you to
42%, stack 2 hits the cap, and **stacks 3-5 do literally nothing**. Owner: *"it seemed to cap at
around 46% making me wonder why I should even continue building stacks."* He is exactly right.

Two passes are fighting: the v0.9.698 Read engine (+15/stack, "Read is what makes Outsmart
reliable") and the #55 anti-abuse cap (48%, "Outsmart must stay a coinflip"). Both cannot be true.

- [ ] Needs a design decision, not a number tweak: either Read raises the CAP, or stacks past
      the cap buy something else (damage, a guaranteed retry, cost reduction)

### D. Outsmart spends 60% of your energy without asking

`OUTSMART_DUMP_PCT = 0.6` auto-spends 60% of current energy for up to +15% chance, and only
tells you *after* it happened. Owner: *"If we are going to have a cost on outsmart or allow
energy to be used to increase the chance the player should have a say in that or it should be
clear, not just a hidden thing that happens."*

- [ ] Make it a choice (a spend prompt like the other variable-cost cards) or at minimum put it
      on the card face. Note the card currently shows Outsmart's cost as nothing

### E. Phantom Strike does not crit

Card: *"your next attack is a **guaranteed critical hit**."* Code (`combat_manager` ~1859-1875):
`vanished` makes the attack **bypass the hit roll** and multiply damage by **1.5**, but it never
sets `is_crit`, so nothing reports a crit — matching the owner's report. Numerically 1.5x is a
crit's multiplier, so this may be only a labelling defect, but the card promises a mechanic the
code does not implement (and a natural crit would stack to 2.25x, which may be unintended).

- [ ] Decide: make it a real crit (flag it, let crit-damage bonuses apply) or reword the card

### F. Gambit is dominated

Owner: *"Gambit seems like a poor choice vs other options since it doesn't do enough damage to
risk hurting myself."* Measured: Gambit 4.5x attack = **107 at L5**, against Exploit's ~15% of
enemy max HP = **~130** with no self-damage risk. Gambit is strictly worse before the downside
is even counted.

- [ ] Falls out of B — if Trickster damage is anchored, re-weight Gambit as the high-variance
      option it is meant to be

---

## ⚑ POST-COMBAT HP STALENESS — root cause FOUND (2026-09-03)

Reported again, with the detail that cracks it: *"If combat actions are performed too fast it's
possible for a player to finish the combat before HP bars are properly updated. They typically
move or take an action pretty quickly after combat and this results in their HP bar going down."*

**Cause.** Combat results are deliberately HELD behind the playback queue so they land in step
with the log. The code that APPLIES them is the empty-branch of `_drain_combat_queue`. But
`combat_msg_queue.clear()` is called from **five** places (dismiss, dungeon dismiss,
`acknowledge_continue`, death, permadeath) and every one of them **skips that settle**. Each
carries the identical comment:

> *"Clearing the queue skips `_drain_combat_queue`'s empty handler, which is what applies
> deferred bar updates — drop the pending companion value with it..."*

They drop `_pending_companion_hp` and **never apply the deferred player HP at all**. So the bar
keeps the pre-fight number until the next unrelated `character_update` — which arrives when the
player moves. Hence "it drops after I walk."

Five copies of a comment explaining that clearing skips the settle is the tell. This is the same
"HOLD means discard" defect fixed for the companion bar in v0.9.741 (89c3960) — fixed there,
missed here.

- [x] **DONE 2026-09-03 — `_settle_combat_bars()`**, called by the drain-empty branch AND all
      five clear sites. Not a sixth guard. NEEDS A LIVE CONFIRMATION from the owner: the symptom
      is timing-dependent and the previous three attempts at this each looked right in code

---

## ⚑ QUESTS — owner observations 2026-09-03 (NOT to be worked now; slot into the dungeon arc)

Recorded at the owner's request, to be picked up when the ordering reaches quests (items 9-12).

1. **Direction/distance changes after accepting.** Very likely by design and badly communicated:
   the quest board shows a hint for an EXISTING dungeon, but accepting **creates a personal
   instance** (`player_dungeon_instances[peer][quest_id]`, server.gd ~18722-18762) at a new
   location — the description even says *"A personal dungeon will be created for you nearby when
   you accept."* So the pre-accept direction cannot be the dungeon you actually get. Confirm,
   then either show no direction until accept, or show the instance's.
2. **"Walk into any dungeon and you'll be routed to the right one" — with several such quests
   active, which one wins?** Instances are keyed per quest so the DATA does not collide, but the
   entry-time selection rule needs checking. Owner: *"Are some quests overwriting or breaking
   others?"* Answer this before touching quest content.

## ⚑ POST-CONVERSION RE-CALIBRATION — 2026-09-03 (refcal then rolecal, in that order)

Every damage ability is now on the anchored model, which made the player materially stronger and
invalidated the monster curve by the standing rule. `refcal` + `rolecal` re-run. Read-only
audits (`roles`, `classes`) below. **Everything measured before this point is stale.**

### Normals landed on target

| level | turns (target 5.0) | HP cost (target 40%) | win |
|---|---|---|---|
| 1 | 5.8 | 40% | 79% |
| 10 | 5.1 | 46% | 71% |
| 50 | 5.2 | 42% | 82% |
| 250 | 4.7 | 44% | 76% |
| 1000 | 3.9 | 35% | 84% |
| 5000 | 2.6 | 42% | 82% |

Good through L250. The old **post-L1000 slide is still visible** in turns (3.9 then 2.6 against a
target of 5.0) even though the cost axis holds — the fight gets shorter, not easier.

### Elites and bosses hit their DANGER target by getting sharper, not longer

| role | turns | target | HP cost | target | win |
|---|---|---|---|---|---|
| empowered L10 | 5.6 | 7.0 | 76% | 55% | 35% |
| elite L10 | 5.3 | 9.0 | 86% | 65% | **23%** |
| elite L50 | 3.7 | 9.0 | 85% | 65% | 30% |
| boss L1 | 6.0 | 14.0 | 89% | 80% | **12%** |
| boss L10 | 5.3 | 14.0 | 91% | 80% | **10%** |
| boss L50 | 4.8 | 14.0 | 85% | 80% | 20% |

**This is the open "length is not calibrated" item biting.** The calibrator converges on ONE
axis (a deliberate choice — see 6g, where two axes fought each other), and it reaches its cost
target by making elites and bosses *hit harder in a five-turn fight* rather than *last fourteen
turns*. Player damage just went up across the board, so fights got shorter still, and the danger
had to arrive faster to hit the same cost.

Consequence: **boss win rate at L1-L10 is 10-12%.** The owner previously accepted 18-46% with
*"companions and gear will make up the difference"* — 10% is below what was accepted, and it is
a burst-damage problem, not a difficulty preference.

- [x] ~~**DECISION NEEDED: split the role multipliers onto two axes**~~ **RETRACTED — see the
      CORRECTION section below. The length problem was an instrument artifact and this fix has
      a documented failure mode.** Original text kept for the record:
- [ ] ~~split the role multipliers onto two axes~~ — HP for length, STR for
      danger — so an elite is a LONGER fight at its target cost rather than a shorter, sharper
      one. This is the honest fix and it is what the target table has always said it wanted
      (9 turns for an elite, 14 for a boss). Do NOT tune win rates directly; that is the symptom

### Tricksters now dominate elites, by design and possibly too well

`classes` audit (60 fights/cell, average gear):

| class | L10 normal | L30 elite | L80 elite |
|---|---|---|---|
| Fighter / Barbarian / Paladin | 76 / 76 / 66% | 21 / 15 / 11% | 28 / 16 / 21% |
| Wizard / Sorcerer / Sage | 78 / 80 / 80% | 20 / 23 / 15% | 20 / 23 / 25% |
| Thief / Ranger / Ninja | 58 / 58 / 55% | **50 / 28 / 41%** | **53 / 55 / 50%** |

Tricksters are now the WEAKEST against normals (55-58%) and the STRONGEST against elites by a
wide margin (50-55% against 11-28%). That is the stated identity working — *"kill enemies BIGGER
than the warrior or mage can"* — and it is a direct, expected consequence of Read raising the
Outsmart cap, because Outsmart bypasses the health bar entirely and elite HP is what makes
elites hard.

- [ ] **DECISION: is the reach supposed to cross ROLE or only LEVEL?** The identity as written
      is about fighting things *above your level*. Outsmart currently ignores the elite/boss HP
      multiplier as well, which is a second, unstated kind of reach. Narrowing it (an Outsmart
      penalty per role tier, so an elite is genuinely harder to trick) would keep the level
      reach and remove the role reach. Recommend this over nerfing Read, which was just fixed
- [ ] **Paladin is the worst class at every row measured** (66% normal, 11% L30 elite) — was
      already flagged as "the new worst" after the resource pass. Its own item under 6c

### What is NOT stale

The card previews: `preview_ability_effect` reads the live curve, and the drift guard was
re-run after the calibration. 22 checks, 0 drift.

## ⚑ CORRECTION — "elite/boss fights are too short" was an INSTRUMENT ARTIFACT (2026-09-03)

**Retracted, and worth reading before anyone acts on a fight-length number again.**

Earlier this session I reported that elites and bosses hit their danger target "by getting
sharper, not longer" — a 5.3-turn elite against a 9-turn target — and recommended splitting the
role multipliers onto two axes to fix it. The owner approved conditionally: *"as long as this is
well documented and isn't likely to cause us more future problems."*

That condition is what saved it. Checking the history first (a9e3545) showed two-axis
calibration had already been tried and reverted, because **turns and cost are coupled through
the win rate**: raise HP to lengthen a fight, cost rises, the player dies sooner, the measured
fight shortens. `hp_mult` ran away to 305x from 11.6x. So the recommended fix had a documented
failure mode — and then the measurement turned out not to need fixing at all.

`_fight_stats_at` already had an unbiased length metric, `eff_turns` (turns extrapolated to
completion at the rate the player was actually chewing through the monster — every fight
contributes, none is selected for). The role audit simply never printed it. Now it does:

| role | turns(obs) | **eff** | target |
|---|---|---|---|
| normal L10 | 4.9 | **6.1** | 5.0 |
| elite L10 | 4.8 | **12.0** | 9.0 |
| elite L50 | 3.7 | **10.5** | 9.0 |
| boss L10 | 4.6 | **21.4** | 14.0 |
| boss L50 | 5.3 | **19.1** | 14.0 |

**Fight length is on target or ABOVE it.** An elite at L10 is a ~12-turn fight, not a 5-turn
one; a boss is ~21 against a target of 14. The `turns(obs)` column is truncated by death — at a
17% elite win rate the mean is dominated by short losses — so it reads short exactly where the
monster is strong. Acting on it would have made monsters even beefier: the runaway again.

### What the real problem is

The COST axis, and it has the same disease.

| role | HP cost | target | win |
|---|---|---|---|
| elite L10 | 91% | 65% | 17% |
| boss L10 | 97% | 80% | **7%** |
| boss L50 | 96% | 80% | 15% |

Cost is measured across all fights, and **a dead player has spent 100% of their bar**. So at a
7% win rate the measured cost is pinned near 100% almost by definition — "cost 97%" and "win 7%"
are the same fact stated twice. The calibrator cannot drive cost to 80% while the win rate is
low, because deaths peg the metric. That is why `rolecal` does not converge at L1-L50.

- [ ] **RECOMMENDED (replaces the two-axis proposal): calibrate the role multipliers against a
      WIN-RATE target instead of a cost target.** Win rate is not truncated, not saturated, and
      is the language the design decisions are actually made in — the owner's own sign-off was
      *"I'm okay with the bosses currently"* about win rates, not about cost percentages. Still
      SINGLE-AXIS, so it cannot oscillate; it just replaces a saturating metric with a
      well-behaved one. Low risk, and it directly addresses the 7% boss
- [ ] Do NOT split onto two axes. Documented failure, and the problem it was meant to solve
      does not exist
- [ ] `normal` L50 is an outlier: 59% cost against a 40% target, 64% win. Worth a look after
      the metric change

### A second instrument defect found on the way

`make_monster` in the simulator applied role MULTIPLIERS but never set the role FLAGS
(`is_elite` / `is_boss` / `is_empowered`). Every audit was fighting a monster with elite numbers
and normal flags, so anything the game keys off the flag rather than the stat line was invisible:
the new Outsmart role penalty measured as having no effect whatsoever, and boss-only damage
bonuses, empowered-mod handling and role-gated loot were all being measured against the wrong
monster. Fixed.

That makes **seven** instrument defects in two days. The rule holds: check what a number is
measuring before believing it, and check it again before acting on it.

## ⚑ Outsmart role penalty — landed, partially (owner direction 2026-09-03)

Owner's call: the Trickster's reach should cross **level, not role**. `OUTSMART_ROLE_PENALTY`
(empowered 10 / elite 22 / boss 35) now comes off the odds, sized to the share of a role's
difficulty that lives in the health bar Outsmart would otherwise skip.

It had to be taken off the **ceiling** as well as the raw chance — subtracting it from the raw
alone did nothing at high Read, because the cap was what actually bound (Ninja vs an L80 elite
did not move, and drifted UP to 66%). Same shape as the Read-cap bug fixed an hour earlier: a
term that only touches a value the cap overrides is a term with no effect.

Measured (60 fights/cell): L30 elite tricksters 50/28/41% → **38/26/31%** against 11-23% for
everyone else. L80 elite 53/55/50% → **53/53/50%**, against 20-28%.

- [x] ~~L80 elite gap is caused by RETRIES~~ **WRONG — measured at 0.5-0.8 Outsmart attempts
      per fight, so retry-spam never happens; the low health bar already prevents it. See the
      fallback-audit section below. The real mechanism is that ONE Outsmart is worth a whole
      fight of damage, and the fix was the RAMP (owner's proposal), not the falloff.**
## ⚑ "DOES A WIN RATE MEAN THE SAME THING FOR EVERY CLASS?" — no. (owner, 2026-09-03)

Three questions from the owner, all of them about the instrument rather than the balance, and
all three were right to ask. New audit: `-- fallback`.

### 1. Trickster HP was already reduced, so does that self-limit the retries? YES

Durability at **average gear** (the divisor behind every `cost%` figure ever quoted):

| class | L30 maxHP | L80 maxHP | vs Fighter (L30) |
|---|---|---|---|
| Fighter | 596 | 1020 | 100% |
| Paladin | 481 | 1274 | 103% |
| Wizard | 279 | 1625 | 60% |
| Thief | 264 | 714 | 51% |
| **Ranger** | **229** | **720** | **26%** |
| Ninja | 224 | 1186 | 69% |

And the measured **Outsmart attempts per fight: 0.5-0.8.** Less than one.

**So my earlier "cumulative retries over a long fight" theory was WRONG.** Retry-spam is not
happening and the low health bar is exactly why — the Trickster does not live long enough to
take a second and third shot. The owner's instinct was correct and mine was a guess.

The real mechanism is simpler: **ONE Outsmart at ~45% is worth an entire fight of damage.**
That is what made tricksters dominate elites, not stacking attempts. Which means the retry
falloff was the wrong lever and the RAMP is the right one.

### 2. The owner's fix — Read to 8 stacks instead of 5 — is the correct lever. DONE

`COMBO_MAX` 5 → 8, with `READ_OUTSMART_PER` 15 → 9 and `READ_CAP_PER` 5.0 → 3.125 so **eight
stacks reach exactly the ceiling five used to** (measured 72% against 71%). The Trickster now
spends more turns earning its shot, and on half a Fighter's health bar it may not survive to
get there — which is the intended tension rather than an imposed nerf.

Measured effect on elite win rate (60 fights/cell):

| | before Read fix | after cap raise | after role penalty | **after 8-stack ramp** |
|---|---|---|---|---|
| L30 elite (Thief/Ranger/Ninja) | 50/28/41% | 50/28/41% | 38/26/31% | **26/25/26%** |
| L80 elite | 53/55/50% | 53/55/50% | 53/53/50% | **48/38/51%** |
| others, for comparison | 11-23% | 11-23% | 11-23% | 11-28% |

**L30 elite is now in band.** L80 elite is still a ~20-point gap for Thief and Ninja. Stopping
here rather than tuning a fourth time against a 60-fight sample — the trend is right and this
wants a playtest, not another pass.

### 3. "Do other classes have the same problem, and are win rates / HP costs accounting for it?"

**They all have the same fallback, they all lean on it heavily, and NO, none of the numbers
account for it.** `roles` and `classes` fight to the death — nobody ever disengages — so every
non-win is recorded as if the player died. L30 elite:

| | fight to death | | | may flee below 45% | | |
|---|---|---|---|---|---|---|
| class | win | died | cost | win | **escaped** | died |
| Fighter | 23% | 76% | 89% | 10% | **76%** | 13% |
| Wizard | 29% | 71% | 84% | 15% | **59%** | 25% |
| Ranger | 28% | 72% | 82% | 21% | **52%** | 26% |

L30 **boss**: Fighter fight-to-death is 7% win / 93% died / 97% cost. Let it run and it is
**1% win / 85% escaped / 13% died / 75% cost.**

Three consequences, all of which affect how every earlier figure should be read:

1. **Death rates are overstated 3-6x for every class.** The alarming "7% boss win rate" I
   reported is a fight-to-the-death artifact; a player who disengages escapes 85% of those.
2. **`cost%` is not comparable across archetypes.** A death registers as 100%, so the column
   saturates for whichever class dies most; and a Trickster's health bar is a quarter to a half
   of a Fighter's, so the same absolute hit is a far larger percentage. Two different things
   are being printed in one column. The survivors' cost is the honest figure.
3. **Allowing flee LOWERS the win rate** (Fighter 23% → 10%) because the player bails instead
   of grinding out a marginal win. So "win rate" under fight-to-death is really "win rate if
   you refuse to ever run", which no real player does.

The Trickster is *not* uniquely disadvantaged by having only flee as a fallback — everyone has
it. It is, however, **worse at using it**: at L30 elite it dies 26% of the time when trying to
disengage against the Fighter's 13%, because it hits the flee threshold sooner and has less
health to survive the failed attempts.

- [ ] **This is the strongest remaining argument for the win-rate-target calibration** proposed
      in the CORRECTION section: measure and target the outcome under a player who disengages,
      because that is the player. Fight-to-the-death is a strategy nobody uses
- [ ] Paladin remains the worst class at every row (66% / 11% / 21%) despite the highest health
      bar — its own item under 6c
- [ ] Ranger's L80 maxHP (720) is far below Ninja's (1186) and Thief's (714) is too — the
      trickster health bars are inconsistent with each other, not just with other archetypes
## ⚑ PLAYTEST 2026-09-03 (second session, L5 Fighter) — three findings

### A. XP requirement was frozen at 100 — a LIVE bug, worse than it looked

Owner: *"This character started Level 5 needing 100 total xp to level is that right?"* No. It
should be ~2576.

`experience_to_next_level` was set **only** inside `add_experience()`'s level-up loop.
`level_up()` — the function that actually increments `level` — never touched it, and the field
defaults to 100 (the L1 requirement). So every route to a new level that does not go through
`add_experience` left the requirement frozen.

Three routes did, and **one is live gameplay**:

| route | consequence |
|---|---|
| **PARTY COMBAT XP** (`combat_manager` ~11045) | hand-rolls its own level-up loop calling `level_up()`, so **partying freezes your XP requirement at whatever it last was, permanently** |
| `/setlevel` (`server.gd` ~37279) | admin-levelled characters need 100/level |
| the balance fixture | how it was spotted |

Party play is the headline feature of v0.9.738-740, so this has been shipped and live. Visible
in the playtest log: the fixture went L5 → L6 after **two** Gnoll kills, then took ~15 fights
for the next level once `add_experience` had corrected the field.

The comment above `level_up()` asserted *"the live requirement is set in level_up()"* — it was
not, and that wrong comment is presumably why nobody looked there.

- [x] **FIXED at the source.** `level_up()` now maintains the field, and both paths call one
      shared `xp_required_for_next_level()`. Same two-paths-one-field shape as
      [[feedback-two-paths-read-same-field]]; a dead third formula was removed for this exact
      reason on 2026-09-02

### B. The difficulty curve assumes GEAR AND A COMPANION a new character does not have

**This is what killed the four starter characters, and it is the most important thing in the
session.** From the owner's own playtest log, an L5-6 Fighter built as the *reference player*
(6/7 gear, tier-appropriate companion) against the Gnolls it actually met:

| fights | mean HP cost | target | turns |
|---|---|---|---|
| 16 | **~10%** | 40% | 4-8 |

Four times cheaper than designed. But `refcal` anchors the whole monster curve to
`make_char(level, "average", klass)` — **average gear plus a companion**. A brand-new character
has neither, and the gearless measurement from earlier the same day showed the other end of it:

| L5 gearless vs same-level Gnoll | turns to kill | turns survived |
|---|---|---|
| Fighter | 5.6 | 13.6 |
| Wizard | 5.8 | 11.3 |
| Ranger | 6.2 | **8.1** |

So the same monster is trivial for the reference player and lethal for a fresh one. The owner
predicted exactly this shape: *"likely gear after abilities are properly balanced."*

- [x] **DECIDED 2026-09-03 — option (b), via item 7.** The owner's new-player-experience design
      ends with the player holding *"basic equipment, one registered companion, and a firm
      understanding of the game loop"* — i.e. every new character finishes onboarding AS the
      reference player the curve is anchored to. So the low-level band becomes correct by
      construction and no separate curve is needed. **Item 7 is therefore a balance dependency,
      not only a UX arc**, which is why it now sits directly after item 6.
- [ ] **QUALIFIED 2026-09-03 (same day):** the owner then specified that the gear/companion
      quest must be **skippable**, so "correct by construction" holds only for players who
      COMPLETE onboarding. A skipper is back in the gearless case. Either the skip prompt makes
      that an informed difficulty choice, or the L1-5 band is also made survivable gearless
      (original option (a)) — the two are compatible and doing both is the safer answer. See
      Stage 0 under item 7.
- [ ] Related: the L5 spawn table lists **Skeleton at 18.5% and it is an APEX species** —
      deliberately tuned to a 28-48% win band. Nearly one in five of a new player's first
      fights is a monster designed to beat them. Apex at tier 1 may be too early; the design
      intent ("a recognisable careful-of-that-one at every stage") does not obviously apply
      before the player has gear, knowledge, or a reliable escape
- [ ] Monsters near the starter post spawn at L1-L2 against a L5 player (post-anchored level
      pockets), which softens the above but was not the condition the deaths happened in

### C. Monster ASCII art missing on one Gnoll fight — NOT diagnosed, do not guess again

Owner: *"I had a fight with a gnoll where the ASCII art didn't display at all. It still said I
was fighting a gnoll but I couldn't see the monster."*

Ruled out so far:
- **Not missing art data.** `art_map["Gnoll"]` exists, and the lookup has an exact match, a
  VARIANT match, and a partial-match fallback before it can return ""
- **Not the empowered prefix.** The log shows "Frenzied Gnoll" that session, but `base_name` is
  stamped as the unprefixed species (`monster_database` ~1759) and the client looks art up by
  `monster_base_name`
- **Not a missing `use_client_art` flag.** All ten `combat_start` senders set it, as do the
  party and watcher paths

That exhausts the cheap theories, which by the standing rule means the next step is a
diagnostic, not a fourth guess: log the resolved art name and the returned art LENGTH at the
render site, then reproduce. Intermittent, so it wants the instrument in place first.

## ⚑ DESIGN PROPOSAL (owner 2026-09-03): gate input on animation, with a player-set speed

Owner: *"we shouldn't allow players next actions to go through until the prior one completes all
the animations and health bar adjustments... add a little arrow that can be clicked to speed up
how fast those animations and adjustments go (and one to slow them down)... remember it and stay
there until they adjust again. It should work for party play as well (maybe a vote before
increase or slowing down)."*

**This is the structural retirement of an entire bug class and should be treated as such.**
Every one of these came from the player being allowed to outrun the playback queue: the
post-combat HP staleness (three failed fixes, five code paths discarding held state), the
companion HP bar showing a stale number, buff effects appearing a beat late, the victory card
landing over unsettled bars, and a stale Continue button over a live battle. The current design
races the animation and then patches each place the race is lost. Gating input removes the race.

It also directly answers the reason the current pacing exists at all: results are held back so
they land in step with the log, which is only coherent if the player cannot act in the meantime.

Design notes for when it is built:
- The speed control is what makes gating acceptable — without it, gating is just "the game is
  slower now". With it, an impatient player sets 3x and a new player sets 0.5x
- Persist per account, not per character
- Party: the pacing is shared, so the setting has to be too. A vote is one answer; simplest
  correct alternative is that the SLOWEST member's setting wins (nobody is ever rushed past
  something they cannot read), with the leader able to override
- The existing `_combat_ui_busy()` / `_combat_playback_active()` state is already the "is
  playback running" predicate, so the gate has a natural home
- `_settle_combat_bars()` (2026-09-03) stays regardless — it is the correctness backstop for
  paths that end playback early, e.g. death

- [ ] Sits naturally with backlog item 6e (solo combat presentation). Should be scoped after
      the current balance pass lands, since it touches every combat input path
## ⚑ PARTY-PARITY AUDIT of every fix from this session (owner ask, 2026-09-03)

Owner: *"It might be worth making sure our prior fixes over this session and the last few are
fixed for party play as well if need be."* Correct instinct — three of them were solo-only.

### Already covered — the live party path reuses the shared code
No action needed on these, and the reason is architectural: the live co-op path builds a
combat-shaped *view* from `member_states` and calls the SAME functions solo does
(`process_attack(view)` at ~10193, `_process_*_ability(adapter, ...)` at ~10560).

| fix | why it already applies |
|---|---|
| Anchored ability damage (all 10 abilities), Devastate×Momentum, Forcefield anchor | shared `_process_*_ability` via the adapter |
| Phantom Strike reports a crit | shared `process_attack(view)`; the view carries `vanished` |
| `_settle_combat_bars()` HP staleness | it was extracted from code that already handled `_pending_party_end_character` / `_pending_party_my_state` / `_pending_party_final_state` |
| **XP requirement frozen at 100** | the party XP loop was the *cause*; fixing `level_up()` fixed party first |
| Hunter's Mark bracket escape | `combat_scene_panel`, shared by both |
| `last_ability_amounts` prefill | shared client popup |
| Missing-art diagnostic | shared `monster_art` |

### Was solo-only — FIXED
- [x] **Authoritative card numbers.** `ability_costs` (v0.9.741), `ability_effects` and
      `turn_regen` were added to the solo `get_combat_state()` only, so **a player in a party
      still saw the client's own estimates** — the ones measured wrong by 0.15x to 6.0x. Co-op
      is the headline feature, so "we fixed the lying cards" was true for half the game. Now
      built per-member in `_party_member_hand_payload` (which is per-recipient, the right
      channel) from a member view, and read by `_apply_party_hand_from_message`
- [x] **Role flags.** `is_apex_species` / `is_elite` / `is_empowered` reached the solo state
      only, so a party fight never showed the red apex tag. Added to `_party_combat_snapshot`
- [x] **Chain engine carry is now ONE definition.** `chain_engine_carry()` holds the rule
      (Momentum and Focus full, Read halved) and both `end_combat` and `_end_party_combat` call
      it. Party combat does **not** chain flocks today, so nothing consumes the party snapshot
      yet — it is written so that when party flocks are wired the carry is already correct
      instead of silently defaulting to a full, un-decayed Read

### Found: Outsmart does not exist in party combat, so Read is INERT in co-op
The live party command handler accepts only `attack`, `flee` and `ability` — "outsmart" falls
through to *"Unknown combat command."* And `_party_member_hand_payload` hardcodes
`outsmart_chance = 0` with the comment *"charge viz not wired for co-op yet"*.

So a Trickster in a party builds Read and **it does nothing at all** — its entire class engine
has no payoff in co-op. Everything done to Read today (the cap raise, the 8-stack ramp, the role
penalty, the halved chain carry) applies only to solo play.

- [ ] **DECISION: should Outsmart work in a party?** It is an instant win on a shared monster,
      so it is not a straight port — one member could end a fight the whole party is in, which
      raises reward-splitting and consent questions the solo version never had. Options: enable
      it as-is, enable at reduced odds, or give the Trickster a different co-op payoff for Read.
      Until then a Trickster is playing a party fight with one third of its kit switched off

### Hazard: three `_party_*` fossils are DEAD CODE carrying stale formulas
`process_party_combat_action()` has **no callers**, which makes `_party_process_attack()` and
`_party_process_outsmart()` unreachable too. They are dangerous because they read as
authoritative and are badly out of date — `_party_process_outsmart` computes
`clamp(30 + (wits - monster_int) * 2, 5, 75)`, which ignores Read, class, level difference, the
attempt falloff and the role penalty, and caps at **75%** against solo's 48%. I nearly reported
that as a live balance hole before checking whether anything called it.

- [ ] Delete all three, or rewrite them to delegate to the shared path if the intent was to keep
      a second entry point. Leaving a stale duplicate of a formula next to the real one is the
      exact shape that produced the lying cards
## ⚑ COMBAT LOG READABILITY — "a wall of text" (owner 2026-09-03, SOLO AND CO-OP)

Owner, after the co-op Outsmart test:

> *"The combat damage summary/window needs to be updated soon. It reads too much like a wall of
> text and is hard to parse out what you did, what the companion did, and what the enemy did.
> This stands true for solo combat as well."*

**This is a presentation problem, not a content problem.** Every line is individually fine; the
failure is that a round arrives as an undifferentiated block with no visual grouping by ACTOR.
From the co-op screenshots, a single round produced ~12 lines mixing the player's card, its
damage, a Focus tick, the companion's attack, the monster's turn, a forcefield absorption and a
poison tick — all the same shape, same indentation, same weight.

Note that co-op already learned half of this lesson: the per-actor HEADER is played (spotlight +
animation) rather than printed, *"leaving ONE summary line per action"*, precisely because
printing both made a 4-actor round unreadable. Solo never got that pass, and even in co-op the
body lines are still a flat list.

Directions worth considering (not decided):
- **Group by actor**, with the actor's colour as a left gutter or prefix, so the eye can find
  "what did I do / what did my companion do / what did it do to me" without reading every line
- **Collapse the incidentals** — DoT ticks, Focus/Read/Momentum gain, buff-absorption lines are
  bookkeeping, not events. A compact status strip would carry them better than log lines
- **One line per actor per round** as the default, expandable for detail. ~~The condensed-log
  path already exists and is the natural home~~ — **CORRECTED 2026-09-04: it does not.**
  `condensed_combat_log` was REMOVED in v0.9.417 ("condensed mode removed; always firehose") and
  the variable survives only so dead branches still compile; it is never set true. Resurrecting a
  feature that was deliberately deleted needs the reason it was deleted first

**Where the real foundation is (2026-09-04).** Party combat ALREADY tags every message with who
acted — `{"actor": "member"|"companion"|"monster"|"neutral", "actor_pid", "target_pid"}` — and the
client reads it, but only to spotlight the right card. The log line itself is rendered identically
whoever acted, which is precisely the complaint. Solo has no tagging at all.

So the shared foundation for BOTH halves of item 7 is per-message actor tagging: the log needs it
to group by actor, and input gating needs the same beat boundaries to know when a beat is done.
Building it once serves both, which is the reason the two were bundled in the first place.

Do NOT tag at the 58 `result.messages.append` sites in `combat_manager.gd`. Tag at the PHASE
funnel — record the message count before and after each phase (player action / companion /
monster turn) and tag the slice — which is one change covering all of them, the same funnel
pattern that fixed the cost tables and the rank-up delivery. And do NOT infer the actor from the
line text: party already half-does this (`String(rm).contains(comp_name)`), and a text heuristic
for pacing is what v0.9.739 had to remove.
- The **damage summary card** ("You: 3319  Pet: 234  Foe: 0") is the readable part — it works
  because it is grouped by actor. That is the model the log should follow

- [ ] Belongs with **item 7 (input gating + player-set combat speed)** in the ordered plan, and
      with backlog **6e (solo combat presentation — port the party pass back)**. All three are
      the same surface: gating gives the reader time, pacing controls the rate, and this
      controls the density. Doing them separately means touching the combat log three times

## ⚑ Outsmart flavour text (owner idea 2026-09-03, small)

> *"It might be cool to do different randomized messages of what the character tried to do to
> outsmart it (example: rolled between its legs, tried to stab it in the back while it's
> distracted, etc.)"*

- [ ] A small pool of randomised attempt descriptions on Outsmart, chosen per attempt. Cheap,
      and it turns the game's most distinctive mechanic from a dice roll into a moment. Worth
      varying by OUTCOME too — a described near-miss reads better than a flat "sees through it"
- [ ] Fits the Keeper's voice; see `docs/design/setting_bible.md` before writing the lines

## ⚑ STEP 2 DONE — role calibration steers by WIN RATE, not cost (2026-09-03)

The gate on the whole balance list. `rolecal` corrected `str_mult` toward a **cost** target, and
cost is measured across all fights while **a dead player has spent 100% of their bar**. So at a
7% boss win rate the metric was pinned near its ceiling — *"cost 97%"* and *"win 7%"* were the
same fact stated twice — and the correction had nothing left to push against. That is why the
loop could not converge at L1-L50 and left bosses at 7-12%.

### The change
`ROLE_TARGETS` gains a `win` value, and that is what corrections chase. `danger` and `turns` are
kept as design intent and still reported, but no longer steered by.

| role | win target | rationale |
|---|---|---|
| normal | 60% | matches the normal-species band (48-72%) |
| empowered | 50% | a coin flip you are favoured in |
| elite | 40% | a real risk |
| boss | 30% | inside the 18-46% the owner already accepted |

Measured under **fight-to-the-death deliberately** — that is a policy-free measure of monster
strength. What a real player experiences when they disengage is reported separately by the
`fallback` audit, because folding a flee policy into the target would mean steering by an
arbitrary "flee at N%" constant.

### The part that was easy to miss, and nearly shipped wrong
**Changing the metric forced a change in SAMPLE SIZE, and the first run did not have it.**
`danger` was a mean over a continuous variable, so `n=6` gave a usable estimate. A win rate is a
**proportion**: at n=6 its standard error is about **20 percentage points**. The loop was then
applying corrections of up to 4x off that noise, compounded over eight passes.

The result looked like this — low levels converged, top levels ran away:

| | first run (n=6, clamp 0.3-4.0) | after (n=30+, clamp 0.75-1.35) |
|---|---|---|
| boss L10 | 22% win, str_mult 0.54 | on target |
| elite L10000 | 78% win, **str_mult 30.22** | — |
| empowered L10000 | 50% win, **str_mult 20.96** | — |

Fixed by raising samples (SE ~9pp at n=30) and tightening the per-pass clamp to 0.75-1.35, which
still spans ~6x over six passes but stops any single noisy reading whipsawing a multiplier.

**Generalises:** any calibration target that is a PROPORTION needs an order of magnitude more
samples than one that is a mean. Worth checking before switching any other metric.

### Result — the full run, and it converges where cost could not

**15 of 21 rows on target, and every miss is at L5000/L10000.** The whole L1-L1000 band lands
for all three roles, and the ladder reads correctly: empowered ~50% > elite ~40% > boss ~30%.

| role (target) | L1 | L10 | L50 | L250 | L1000 | L5000 | L10000 |
|---|---|---|---|---|---|---|---|
| empowered (50%) | 47 | 48 | 52 | 56 | 54 | 63 | 73 |
| elite (40%) | 38 | 47 | 40 | 38 | 46 | 51 | 73 |
| boss (30%) | 26 | **18** | 33 | 35 | 27 | 53 | 77 |

Against the cost-targeted run this replaces, where boss sat at **7-12% at L1-L50** and could not
be moved. `str_mult` is sane again too — the whole table spans 0.78 to 3.79, against 20-30 in
the noisy first attempt.

- [ ] **L5000/L10000 are far too EASY for every role** (63-77% win against 30-50% targets, and a
      L10000 boss costs **8%** of the health bar). Same band as the known post-L1000 slide;
      treat them together as one high-level problem rather than three role faults
- [ ] Boss L10 at 18% is the one mid-band miss worth a look after the above

- [ ] L5000/L10000 still off target for all three roles. Same band as the known post-L1000
      length slide; treat them together rather than as a calibration fault
- [ ] `normal` has a win target now but `refcal` still steers the base curve by cost. Same
      argument applies — worth converting once the role side is settled and verified

## ⚑ CARD RANK-UP REDESIGN — COMPLETE (2026-09-03)

Owner: *"I don't care for the current options and they are uninteresting and the same thing over
and over. There should be a good variety of interesting choices."*

**The old system** offered the SAME menu at every rank-up of every card: `power` (+12% effect),
`efficiency` (-10% cost), plus `rider` on damage cards or `duration` on buffs. Two of the three
were plain scalars and the menu never changed, so there was no decision in it.

**Now:** `shared/card_upgrades.gd` holds **33 upgrades**, all with real effects. A rank-up deals
**nine**, the player previews them, they are hidden and shuffled, the player turns over **three**,
and picks **one**. Trade-offs are gated to milestone 3+ so early picks are pure upside while you
are learning a card.

| card kind | offered at milestone 1 | at milestone 5 |
|---|---|---|
| damage | 10 | 21 |
| buff | 8 | 16 |
| control | 5 | 10 |

Menu repeat rate across four rank-ups: **0.2%**.

### Rules that were enforced structurally, not by memory
- **Nothing unwired can be offered.** Every entry carries a `wired` flag that `eligible()`
  filters on. Offering a choice that silently does nothing is the defect this replaced, so the
  gate lives in code rather than in a reviewer's head
- **The offer is drawn ONCE and persisted** on the queued rank-up. Drawing on request would let
  a player re-roll the menu by reconnecting; re-drawing on replay would show them a different
  set than the one they were studying. Verified: two draws of the same rank-up differ
- **The server validates the pick against the offer that character was SHOWN**, not against a
  static allow-list — stronger, and it cannot go stale as the pool grows
- **A card's KIND is derived from what the ability does**, not from a list in the upgrade file.
  Such a list drifts the moment a card is re-roled, which is how War Cry sat in the wrong slot
  for months
- **Effects live at existing funnels** — damage in `apply_skill_damage_bonus`, cost in
  `apply_skill_cost_reduction`, buff magnitude in `_apply_buff_value_modifiers`, duration in a
  new `_buff_duration()`. Nineteen scattered checks would have drifted apart like the cost tables

### Three upgrades were CUT rather than faked
- **Overkill** (excess damage carries to the next flock member) — every ability body clamps
  monster HP at zero, so the excess is discarded before any hook can see it
- **Lingering** / **Overreach** (debuff lasts a round longer / shorter) — debuffs here are not
  round-based at all: `monster_sabotaged` is a persistent value and `enemy_distracted` is
  consumed by the next attack

All three described mechanics the game does not have. Adding one purely so an upgrade could
exist would be inventing a mechanic to justify a name.

### Party play was checked, not assumed
Co-op resolves through the same damage funnel on a member view, so upgrades apply there for
free — measured at 1120 with Executioner against 800 without, on a member view. **Provoking**
was deliberately built as an aggro pull rather than a flat penalty so it works in SOLO with a
companion too, and will extend to NPC teammates without change, because it modifies the
targeting roll rather than special-casing who is present.

### Also fixed on the way
The **mitigation clamp is two-sided** now. Trade-off downsides were briefly applied AFTER the
floor so a defensive deck could not launder them away; the owner rejected that — *"if we have a
mitigation floor we should find a way to respect it"* — and was right, since a rule some code
steps around is not a rule and the post-clamp multipliers were unbounded. Vulnerabilities
compose into the same multiplier, `MITIGATION_BUFF_FLOOR` still guarantees you can get tanky,
and `MITIGATION_VULN_CEIL` guarantees a reckless build cannot be deleted in one hit.

- [ ] **NOT PLAYTESTED.** Compile-clean and unit-verified, but the reveal's timing and whether
      the choices actually feel hard are things only play can answer. Scenario `milestone` puts
      a Fighter one use from three thresholds at once (Power Strike and Shield Bash at 9 uses
      for the upside-only pool, Cleave at 199 for the trade-off pool)
- [ ] The pool is deliberately shallow for CONTROL cards (5 → 10). More control-flavoured
      upgrades would help, but only ones that map to mechanics that exist

## ⚑ THE ABILITY GAP — the fix existed and was being deleted every run (2026-09-04)

L100 sat at 43% win against a 60% target and would not respond to tuning. Forensics on what
spawns there found the cause is not stats at all: **Jabberwock wins 16% and Demon Lord 82% on
near-identical stat lines** (str 1869 / hp 19470 against 1645 / 16606). Lethality is dominated
by ABILITIES, which the reference model does not size — it tunes HP and strength only. The
spread is systemic, not an L100 quirk: L50 runs 13%-100%, L250 runs 9%-100%.

Two attempts to fix it by rebalancing the calibration axes were measured and REJECTED — each
fixed L100 and broke several other levels (13/14 rows on target became 10/14, then 8/14). Both
are recorded in `real_combat_sim.gd` so they are not retried.

**The actual fix already existed.** `species_power` measures each species' REAL win rate and
corrects it toward a band, and `monster_database._species_shape` reads it. It was absent from
the curve file because **refcal rewrote the file carrying forward only an allow-list of keys**,
so every refcal run silently destroyed it. That is the same defect twice: refcal once emitted
only `anchors` and destroyed a rolecal calibration, was fixed by naming `role_multipliers`, and
then wiped `species_power` from the day that key was added. refcal now preserves the whole
document and overwrites only its own three fields, so a future key survives by construction.

Result with it live — **every anchor within 6 points of target, 13 of 14 within 5**, and L100
at 65% without touching the axes:

    L1 57  L2 60  L3 57  L5 64  L10 63  L25 57  L50 63  L100 65
    L250 66  L500 63  L1000 58  L2500 60  L5000 61  L10000 62

**The design it restores is the one the owner asked for**: variety kept, difficulty rewarded.
Normal species calibrate to a 48-72% band; APEX species are held to a deliberately HARDER
28-48% band and paid 2.0x XP and 3x drop chance for it. Owner 2026-09-04: *"That proportion
seems fair."* What it removes is the arbitrary case — Cerberus (39%), Ancient Dragon (41%) and
Gryphon (32%) were as punishing as apex monsters while receiving none of the apex reward — and
the opposite failure, species sitting at 92% win.

- [ ] Coverage check: speciescal calibrated 29 species "that actually spawn at L50/L250/L1000".
      Confirm nothing that spawns only at other levels is missed
- [ ] Re-run `speciescal` after any player-power change, like refcal and rolecal. It is now part
      of the calibration chain, not a one-off

---

## ⚑ THE COMPANION SPINE — one arc, ordered so nothing gets built twice (owner 2026-09-04)

Owner direction: rewards from dangerous monsters should **build on the theme** rather than being
generic loot, and the theme is *companions* — *"whatever drops we introduce go towards building
on our theme, having something to do with our companions"* — heading toward a world that feels
lived in: **NPCs, wandering travelers, recruitable party members, and companions living around
the posts trying to survive.**

Four separate places were already circling this (6b companion power, 12b the Phantom's outward
loop, 16's sinks and living world, and the apex reward question raised on 2026-09-04). They are
listed here as ONE ordered arc because they share machinery, and building them out of order is
how the Dungeon Atlas became three tasks in three places.

**The ordering, and why each step has to come before the next:**

1. **6b — companion power & levelling** *(already numbered; do it first)*. Everything below
   grants, spends or trades companion strength. Design a drop that strengthens a companion
   before the companion power model is settled and the drop gets re-tuned the day 6b lands.
   The 2026-09-04 companion work (sqrt growth, the variant multiplier passing through exactly)
   settled the SHAPE of companion power; 6b is what it should feel like to grow one.
2. **Companion-themed drops from dangerous monsters** ← NEW, the thing that prompted this.
   Needs 6b (what a companion upgrade IS) and the apex/species calibration (which monsters are
   genuinely dangerous — done 2026-09-04). Ideas to design then, not now: reagents that feed a
   companion, imprint-bearing remains from an apex kill, egg variants only that species drops.
3. **16's sinks** — shops, breeders, trainers, fusers, companion tasks. These SPEND what step 2
   grants, so the currency has to exist first or the sinks are designed against a guess.
4. **Living world: NPCs and companions around the posts** ← expanded. Post-dwelling companions
   and the people who tend them are the natural home for step 3's shops and trainers. Doing 3
   first means the NPC is a shopfront for a system that already works, rather than two systems
   invented at once.
5. **Wandering travelers** ← NEW. The same NPC representation as step 4, given movement and an
   encounter. Cheap AFTER 4, a second system if built before it.
6. **Recruitable party members** ← NEW, and deliberately LAST of the arc. It needs the party
   machinery (items 1 and 2), an NPC representation (4), and combat AI able to choose actions.
   The party server pass is done and the AI already exists in a form — `real_combat_sim.gd`
   drives real characters through real combat with per-class policies, which is the same problem.
   Built before 4, it invents its own NPC; built after, it borrows one.

**What this arc must NOT do:** invent a second companion progression alongside 6b, or a second
NPC type alongside the trading-post traders that already exist. Both already have a home.

- [ ] Fold into the arc rather than tracking separately: 12b's *"egg/companion investment"*
      strand, and 16's *"sinks"* and *"living world"* bullets (left in place below, cross-marked)
- [ ] The drops do NOT need designing now. Owner: *"they just need added to the to do list so we
      can do them when appropriate."*

---

## Dungeon arc

*`docs/design/dungeon_revamp.md` is the master design. Hard constraint throughout: every dungeon
stays **solo-possible**; a party is a force multiplier, never a requirement.*

### 8. Dungeon F — party in dungeons (north star, most architectural)
- [ ] Party **movement** in a shared instance
- [ ] Party combat inside dungeons on the deck system
- [ ] Follower-finishes-boss reward case; per-player equipment/chest loot

*Placed here because it builds on 1 and 2. Doing it earlier means touching party code a third time.*

### 9. Dungeon B — loot / progression / discovery
- [ ] **Dungeon Atlas / Codex** — hub, quest board, what-drops-where, uniques page.
      This is ONE item; it was previously tracked in three separate memos as three tasks.
      Reveal is **hint-based discovery with progression**, not show-all: entering or clearing
      gives full detail, spotting a D tile gives partial, a rumour gives a hint. Hooks into the
      existing rumour, threat and discovery tracking
- [ ] Signature drop per dungeon
- [ ] Broader scattered loot (runes / gear / scrolls, tier-scaled)
- [ ] Companion **Tier-RANK** variety

### 10. Dungeon A — themes (slices 2-4)
- [ ] Theme roll / stamp / display; theme to guaranteed themed egg or companion
- [ ] "Sigil" opt-in modifier consumable
- [ ] **Preserve** both random special-trait dungeons AND the Catalyst/Sigil opt-in — the Atlas
      and meta work must not delete either

### 11. Presentation pass — dungeons, world map, minimap, GUI
*Widened from "Dungeon E" on 2026-09-01 (user): the same pass should look at **how everything is
drawn**, not just dungeons. Kept as ONE item rather than split, because the map, minimap and
dungeon view share rendering code and techniques — doing them separately means solving the same
problem three times. Also owns the website's DUNGEON pages + screenshots (deferred from 4):
dungeons are about to look different, so shooting them first means shooting them twice.*

**Dungeons**
- [ ] Zoom the dungeon view in
- [ ] **Sprites** for chests, traps and floor drops instead of ASCII glyphs (unused sheets in
      `client/sprites/battlers/tf_svbattle/singleframes/`)
- [ ] Stop drawing **walls as tiles** — render non-traversable space as void (Azure Dreams style)
- [ ] Rooms **farther apart**, longer corridors (still too cramped after C3a)

**World map, minimap and GUI** *(user 2026-09-01)*
- [ ] **Explore other ways to draw the ASCII map** — this is exploratory, not a fix list. Try
      alternatives (denser/sparser glyph sets, colour by biome vs by feature, shading for
      elevation or danger, spacing and aspect ratio) and compare them side by side before
      committing
- [ ] Same for the **minimap** — it is currently a shrunken copy of the same view
- [ ] **GUI** — look for cheap wins in the overall frame: panel borders, spacing, headers,
      colour discipline, the empty-panel look (the left panel reads as a black void when there
      is nothing to say)
- [ ] Bias to **easy wins first** — the ask was explicitly "see if there are easy ways to make
      things look better", so time-box the exploration before any large restructure
- [ ] **Overlaps to fold in here, not track separately:** the 1080p default combat layout
      (monster art overlapping the cards) and the remaining UI-scale registrations, both
      currently in *Independent*

### 12. Dungeon D — bosses (after 6, so boss damage is sized against corrected numbers)
- [ ] Real phases, telegraphs and adds. **Telegraph counterplay is mandatory** — no unavoidable
      damage

### 12b. The Phantom — the outward loop (player posts, egg/companion investment)
*User direction 2026-09-02, expanded the same day into a full game loop. Placed here because it
reuses dungeon generation and level scaling (8-12), and because it is the **hard gate on the
player-post suppression floor** in item 6 — that change must not reach players before this exists.*

**THE HOOK — the core loop the game has been missing:**
1. Players push out into the wilderness **as far as they can survive**
2. They found a post there and **stock it with eggs and companions they no longer need**
   (consumed, permanently)
3. They descend into that post's **Phantom** to gear up and win better equipment and companions
4. Once strong enough, they push **further out** and do it again
5. **The farther out, the deeper the Phantom can go, and the better what is inside it** — given
   the right investment

This is the outward pull item 6 concluded the game needs. The difficulty model can never enforce
progression (encounter level is a pure function of position), so the pressure has to come from
the **reward gradient** — and here the player builds that gradient themselves, at the edge of
what they can survive. **The loop IS the answer to item 6's open question.**

**Egg investment — a sink that pays forward across lives**
- Each egg is **consumed** and makes that monster type **more likely to spawn** on the Phantom's
  floors (more harpy eggs than goblin means harpies roam more, goblins remain but rarer)
- Each egg also **buffs the eggs of that type found inside** — stats enhanced *beyond* the normal
  tier/sub-tier ceiling. A goblin egg pulled from a heavily-invested player Phantom is far
  stronger than an identical-tier goblin egg from an overworld one
- Eggs inside are **MUCH rarer — at least 10x** the normal rate. They are the thing a player
  hunts long and hard for; getting one **out alive** and hatching it is the payoff for everything
  invested
- This is what makes surplus eggs valuable instead of clutter, and what a player **carries
  forward onto new characters**

**Companion investment — the gearing axis**
- Companions the player no longer wants are **consumed** to make the **equipment** found in the
  Phantom stronger — the gear a fresh character needs to survive the wilderness outside
- Gives retired companions a dignified use and a second sink for the same oversupply

**Post creation — Valor-purchased prefabs**
- Building a post piece by piece is too slow to support this loop. Add: spend a **large amount of
  Valor** to place a **randomized pre-built post** in a valid area
- Random design/shape, but guaranteed the necessities — **a Phantom and a market**
- **More expensive tiers** include crafting stations and other stations
- Valor's current sinks are bounties, PvP payouts and repairs, so this becomes its major sink —
  size it against those

**Theming (needed — user asked for it).** Draft to write against the setting bible's two voices:
a phantom is a dead place the ground refuses to keep down, which comes back **in the shape it
died in**, and *eggs are the one living thing a dead place produces*. So: the ground under a new
post is already remembering something. **Feeding it eggs teaches it which shapes to wear** — give
it goblins and it comes back up goblin. **Giving it companions** — things that lived alongside
you — is why it returns *possessions*: gear is what the place kept of them. The 10x egg rarity is
the fiction too: a place only rarely produces something still living, and you have to carry it
out past everything else it remembers.

**Open questions and risks, in the order they should be settled:**
- [ ] **6b (companion levelling) is a PREREQUISITE, not a parallel track.** The payoff of this
      entire loop is companions — and today a level-1 companion is statistically identical to no
      companion (measured, n=200). A hard-won 10x-rare buffed egg would hatch into something that
      changes nothing until levelled. Fix companion scaling first or the reward rings hollow
- [ ] **Does investment raise the egg RATE, or only egg QUALITY?** Quality-only is cleaner, but
      10x rarity plus pure RNG means a dry run reads as theft after a heavy investment. Prefer a
      **deterministic floor** (a guaranteed egg at certain depths) so effort always pays, with
      quality as the variable part
- [ ] **Account vs character ownership.** Permadeath means the character who built and stocked
      the post can die. The post and its investment must survive at the **account** level or the
      loop punishes far beyond intent — but what is carried *out* of a run must still be lost on
      death, since "what you brought out alive" is the setting's whole point
- [ ] **Guard against a laundering pump.** Invest cheap eggs, extract better eggs, hatch, invest
      those companions, get better gear, repeat. The exchange must be lossy and gated by **depth
      and survival risk**, never by volume
- [ ] **Phantom-specific monster tiering/scaling** (user 2026-09-02). Seeding a species and
      scaling it by depth needs a model that holds for ANY species at ANY depth. See the
      measurement below — the existing model does not provide one
- [ ] **Scaling shape.** `level(depth) = lerp(1, local_wilderness_level, depth / max_depth)` with
      `max_depth` scaling to how far out the post is. A frontier Phantom is automatically longer
      because it has further to bridge — "near endless" is really "as long as the gap it closes"
- [ ] **Reward gating.** Must gear a fresh character enough to survive locally without becoming
      the best farm in the game for established players
- [ ] Define a **valid area** for placement (min distance from existing posts, terrain rules)
- [ ] Decide whether a Phantom is per-post, per-account or shared, and who else may enter

**MEASURED 2026-09-02 — the species-scaling question, and a correction.** An earlier claim in
item 6 that a scaled-up low-tier monster might be *deadlier* than a native high-tier one was
**wrong**, and the user was right to challenge it. It was inferred from base-table ratios
(HP/STR/DEF per base level all fall steeply from T1 to T9) without checking what the generator
actually produces. Generated at the same level, the picture reverses:

| Generated at L5000 | HP | STR | DEF | abilities |
|---|---|---|---|---|
| Goblin (T1, base lv2) | 15,000 | 712 | 888 | 2 |
| Wolf (T1, base lv3) | 15,000 | 1,021 | 965 | 3 |
| Ancient Dragon (T5) | 280,543 | 4,266 | 5,968 | multi_strike, armored, … |
| Hydra (T7) | 646,942 | 5,975 | 4,780 | regeneration, multi_strike, enrage, … |
| Void Walker (T7) | 677,173 | 6,390 | 5,960 | ethereal, mana_drain, … |

A scaled Goblin is **43x weaker in HP** than a Void Walker at the same level, not stronger — and
high-tier monsters carry far richer ability sets (multi_strike, regeneration, armored, enrage,
ethereal, mana_drain), which is exactly the "other redeeming stats" the user suspected. Base
per-level ratios were a misleading metric on their own.

Two real findings survive, and both bear directly on the Phantom:
- **Low-tier monsters hit an HP CAP when scaled up.** Goblin and Wolf both land on *exactly*
  15,000 HP at L5000 — a ceiling, not a curve. So seeding a Phantom with cheap low-tier eggs and
  descending would produce monsters that stop getting harder with depth while the player keeps
  levelling. That is the actual exploit, and it is the opposite of the one first suspected
- **Avatar of Chaos (base level 6000) generated at L5000 is a runt** — 161,230 HP against Void
  Walker's 677,173 — because it sits below its own base level and takes the linear downscale
  path. Whether `select_monster_type` routinely picks below-base monsters at high level is a live
  candidate for the late-game difficulty slide in item 6, and is **not yet measured**

Conclusion: the Phantom needs its **own scaling model** rather than reusing the overworld one.
Depth must set difficulty for **any** seeded species, so the model has to be anchored to depth
(and through it to a reference player) rather than to each monster's hand-authored base_level.
This is the same conclusion item 6 reached for the overworld, which is a good sign: **one
reference-player-anchored monster model serves both.**

---

## Then

### 13. Roguelike loop — why progress doesn't FEEL like progress
*User direction 2026-09-01: "I don't much like the options available. It's hard for players to
feel like they are making much progress." Placed BEFORE the Sanctuary redesign (14) and the
realm meta-loop (15), because both of those build the vehicles for whatever this decides —
building sinks and rooms before deciding what a run should leave behind is how you get
features nobody feels.*

- [ ] Name what actually carries between lives today, and be honest about how thin it is:
      account level? Sanctuary contents? kennel companions? titles/Valor? mastery? — then say
      which of those a player can *perceive* after a death
- [ ] The core question: **what should a single run leave behind?** The setting bible already
      answers it thematically — *what you brought out alive* — so the mechanics should make
      companions and the Sanctuary the felt progression, not a stat number
- [ ] Audit the current between-lives options; the user finds them uncompelling. Say why
      (too few? too slow? invisible? not chosen by the player?) before designing replacements
- [ ] Look at how the genre solves this (persistent unlocks, meta-currency, run modifiers,
      collection completion) and pick deliberately. **Candidate already on the table: player
      phantoms (14)** — your dead characters persisting as things in the world — permadeath without felt accumulation is
      the retention risk here
- [ ] **Watch for overlap:** the egg/companion *sinks* live in 15; this item decides what
      progression should feel like, 15 spends it

### 14. Player phantoms — the dead don't leave
*User direction 2026-09-02. This fell straight out of the theming rather than being invented
for it: if what is down there makes delvers into phantoms, then a dead character IS one, and
phantoms roam. Placed immediately after 13 because 13 decides what a run should leave behind
and this is the strongest candidate answer on the table — a character who dies becomes
something other players meet.*

- [ ] Design what a player phantom **is**: a permadead character returning with their build,
      class, gear and battler sprite, roaming near where they fell. Meeting a former top-ranked
      player as a thing in the world is the whole appeal — keep the identity legible
- [ ] Decide what an encounter with one **does**: hunts the living, wanders a territory, or
      guards the corpse it came from
- [ ] What killing one yields, and — the part that matters for 13 — **what the dead player
      gets**. If your past characters persist as marks on the world, permadeath starts adding
      something instead of only taking it away
- [ ] **Constraint, performance:** "visible roaming entities" sits in *Hard-deferred* over
      exactly this cost. Revisit that gate deliberately rather than by accident. A phantom that
      exists only near its own death site, and only while a player is in range, may sidestep the
      original objection — confirm before designing around it
- [ ] **Constraint, balance and griefing:** a level 200 phantom parked near a starter post is a
      wall a new player cannot pass. Needs level-banding, scaling, or placement rules
- [ ] **Consent question:** do players want their dead hunting other people? Decide whether it
      is opt-in, opt-out, or unconditional — and note that unconditional is the most thematically
      honest and the most likely to annoy someone
- [ ] Hooks that already exist: corpses spawn where a character fell, the leaderboard remembers
      names, and battler sprites already reflect equipment
- [ ] Overlaps to fold in, not track twice: the *living world* strand of 16, and the
      *Hard-deferred* roaming-entities line

### 15. Sanctuary redesign — put the house in the world
*User direction 2026-09-01. After 13 so it implements a decided progression, and adjacent to 15
so the companion activities are designed once, not twice.*

- [ ] **Root it in the world.** Today the Sanctuary is a menu between login and character
      select (`HOUSE_SCREEN`). The user wants it to be a real place — near the starting post
      is the suggested anchor — so going home is travel, not a screen
- [ ] **Do it responsibly at scale.** Prior art exists: player posts already claim real tiles
      (`add_player_tile` / `get_player_tiles` / enclosure checks), so the sparse-tile storage
      pattern is proven. Decide early between a shared world district, an instanced interior on
      a world doorway, or true claimed land — the choice drives chunk cost, griefing and what
      happens when thousands of accounts each own ground
- [ ] **Customisation** — the user wants the house to be personal, not a fixed room
- [ ] **More to DO with companions there.** Coordinate with 15's breeders / trainers / tasks
      rather than inventing a parallel set; the Sanctuary is the natural home for several
- [ ] Keep what already works: account-level persistence through permadeath, the kennel
      (30-500 slots) and the Fusion Station

### 16. Realm meta-loop
- [ ] Reorient **questing onto dungeons** (clear / rescue / boss-hunt / gather). The quest types
      already exist; the work is generation and surfacing, not new types
- [ ] Real **sinks for excess eggs and companions** *(design these WITH 14 — the Sanctuary is
      the natural home for several, and 13 decides what they should feel like)*: shops that buy and sell, breeders, trainers,
      fusers (fusion exists — expand), companion **tasks**
      — **ordered as step 3 of THE COMPANION SPINE**; see that section for why it follows the drops
- [ ] Living world: rework posts, companions around posts, threats woven in
      — **step 4 of THE COMPANION SPINE**, and expanded there with NPCs, wandering travelers and
      recruitable party members, which were not tracked anywhere before 2026-09-04

### 17. Engagement / minigame variety
- [ ] Prize Shuffle redesign: gathering and crafting slices (combat slice shipped)
- [ ] Port the Chain / Mystery / Trap mechanics to gathering and crafting
- [ ] Trap chests, Mimic chest variant, 2 remaining dungeon-exclusive consumables

---

### 18. Craft review — the game against industry standards
*User direction 2026-09-01. Placed LAST of the numbered items because a best-practices pass run
while combat numbers (6) and the whole dungeon arc (8-12) are mid-rework would produce findings
that expire before they can be acted on. The parts that DON'T depend on in-flight work —
onboarding, accessibility, input conventions, save/data safety, performance, settings coverage
— are stable today and can be pulled forward at any time.*

- [ ] Audit the game as a game: onboarding and first-session experience, moment-to-moment
      feedback, difficulty curve, session shape, retention loops, readability/accessibility,
      settings and input conventions, save/data safety, performance
- [ ] Name concretely where it falls short rather than listing generic best practice, and rank
      the gaps by player impact against cost to fix
- [ ] Turn the ranked gaps into backlog items in the right order, rather than one sprawling
      "polish" task
- [ ] Existing threads this will likely absorb or supersede: the UX revamp arc and the
      unspent-stat-point nudge. **NOT the tutorial/starter-quest thread — that became item 7
      (new player experience) on 2026-09-03 and is being built, not audited.** An onboarding
      audit run after item 7 lands is still worth having

## Independent — slot in any time (no dependencies)
- [ ] Card market live list-to-buy smoke test (built, never exercised end to end)
- [ ] Launcher revamp + in-game feedback inbox
- [ ] UI-scale registration for remaining elements (action bar, inventory, market, crafting...)
- [ ] Unspent stat-point "+" badge (players forget they have points)
- [ ] Combat default layout at 1080p (cards overlap the monster art)
- [ ] Companion cosmetics: ASCII border + shadow layer (data layer already shipped)
- [ ] Merchant/market **baseline NPC stock** — merchants only equalise player listings, so
      off-circuit posts stay bare
- [x] ~~Tutorial + starter quest chains for a zero-gear character~~ — **promoted to item 7**
      (new player experience) on 2026-09-03. Do not track it here as well; that is how the
      Dungeon Atlas ended up as three tasks in three places
- [ ] Patreon + Founder title (implementation planned, awaiting greenlight)
- [ ] Item variety — duplicates should be rare
- [ ] Ability-card level-up progress fill, draggable action bar, plain-language skill text
- [ ] Salvage preview: tell the player what they get before salvaging
- [ ] Variant Imprint Atlas page (Sanctuary)
- [ ] Bug-reporting system: end-to-end test on production (shipped, never verified live)
- [ ] ARPG pillar 5: endgame rift runs

## Hard-deferred (documented reason — revisit only if the reason changes)
- Visible roaming entities (performance gate) — **now has a design reason to revisit: see 14,
  player phantoms.** Do not un-defer casually; the gate was cost, and that cost has not changed
- Full ability mastery as a progression vector (multi-session arc)
- Group raids
- Full mentor matching
- Biome-specific mechanics (movement, weather, biome-locked monsters and resources)
- Multiple saved decks, swap-on-the-fly, true drag-and-drop (needs server work)

## Watch items (not tasks — things that must not regress)
- **The from-source client remembers the last host** and all clients share one settings file, so
  a single manual connect to production silently sends later local test runs to the LIVE server.
  The harness forces `--server=localhost` and the client prints its target; don't remove that
- **Permadeath may change** — do not harden "death is permanent" into copy or design pillars
- **Archive with discussion** — removing game elements is allowed, but discuss first; improving
  beats removing. Crafting was flagged as "not in a good spot at all"
- **Early-game survivability** — resource cost scaling still open; starter weapon at creation
  deferred pending playtest
- **⚑ RE-CALIBRATE AFTER ANY PLAYER-SIDE CHANGE.** Monster stats are derived from a REFERENCE
  PLAYER (`shared/reference_monster_curve.json`, built by the sim's `-- refcal`). Anything that
  makes the player stronger or weaker — gear, companions, abilities, resources, classes, races,
  the `make_char` model itself — silently invalidates that curve, because the monsters were
  sized against the old player. This has already happened twice: the gear calibration, and the
  companion HP rework (which pushed elite-at-L1 to 90% win against a 70% target). It is not a
  bug in the design; it is the cost of anchoring monsters to the player, and it is the right
  trade. **The rule: after a player-side balance change, run `-- refcal` (2-3 passes), then
  `-- roles` to confirm, and treat every number measured in between as stale.**

---

## Recently shipped
- **v0.9.746** — the per-species correction that had been DEAD since it shipped is finally live.
  `species_power` measures each species' real win rate and pulls the outliers toward a band, and
  `monster_database` reads it — but refcal rewrote the curve file carrying forward only an
  allow-list of keys, so every calibration run silently deleted it. Fixed at the cause: refcal
  now preserves the whole document and overwrites only its own three fields. Also an APEX roster
  rebuilt around what the NAMES promise (an Ancient Dragon was being tuned as an ordinary fight
  while a Jabberwock held the hardest band), per-level species anchors instead of one scalar, and
  the calibration made CONVERGENT — see *the ability gap* and *orthogonal calibration* below

- **v0.9.745** — the early game was too hard for two measurable reasons, both in the tooling.
  Smoothing used a MEAN in log space, which biases upward on a convex curve and was inflating
  the freshly-calibrated numbers 25-37% at L5/L10/L50 — eighteen correction passes could never
  land because nothing they produced survived to be written (median filter now). And the
  calibrator measured a monster that never spawns: `_cal_override` forced hp/str onto a creature
  AFTER its species shape was applied, so real spawns were 0.64x the written strength at L1 and
  1.22x at L100. L1-L50 went 42-47% win to 57-64%

- **v0.9.744** — every DUNGEON BOSS was invisible (all 21: a boss is named independently of its
  species, so prefix-stripping could never reach the art — found by writing a coverage audit
  instead of fixing a third single name), chrome buttons were EATING THE SPACEBAR (a focused
  Godot Button activates on ui_accept, so the report dialog re-opened on every action, the
  screenshot button saved silently on every Space, and the volume slider ate the arrow keys),
  the companion/monster REBALANCE (companion passives were unbounded: +1127% max HP, +2275%
  damage, effectively immunity at high companion level — sqrt growth now, with rarity still
  paying exactly 1.60x at every level), gear affixes 0/1/2/3/4 -> 1/2/3/4/5 because common gear
  carried NO affixes and affixes are the only part of an item that scales past L50 (a full
  common kit won 0% of fights at L1000), the nine-card rank-up reveal actually reaching players,
  and the party fight that never ended

- **2026-09-02 (site + docs, no client build)** — website refresh live: setting-led copy that
  explains the name, real in-game screenshots, accuracy fixes (Linux support, party of 5,
  deck-driven combat). Setting bible revised to a single cause. Screenshot capture harness added

- **v0.9.743** — invisible monsters fixed (every Orc/Wolf/Young Dragon VARIANT rendered no art
  at all: their art is filed under an aliased name and the prefix broke the match), Outsmart
  works in co-op at solo odds and cost (it was rejected outright, so a Trickster's Read had no
  payoff in a party and the odds meter read a flat 0%), apex species start at TIER 2 (Skeleton
  was ~1 in 5 of a new character's encounters), party fights get the authoritative card
  damage/cost/regen and the APEX tag that v0.9.742 only gave solo, Outsmart pre-fills and
  remembers its spend and accepts 0, the Pathfinder starter chain retired, three dead party
  functions deleted

- **v0.9.742** — the cards stop lying (server-authoritative per-card damage/shield/cost/regen,
  solo AND party), every damage ability converted to the anchored model (turns-to-kill 2.3/4.9/11.5
  -> 5.8/5.6/6.2 for Mage/Warrior/Trickster), Devastate scales per point of Momentum, the frozen
  XP requirement fixed at `level_up()` (party levelling had pinned it at 100 permanently), Read
  raises its own cap and ramps over 8 stacks with a per-role Outsmart penalty and half-carry
  across a flock, Outsmart asks before spending energy, Phantom Strike reports its crit,
  post-combat HP settles via one `_settle_combat_bars()` instead of five paths discarding it,
  Hunter's Mark stops leaking BBCode, missing monster art fails loudly

- **v0.9.741** — THE BALANCE PASS: every monster resized against a reference player at every
  level (the mid-game hump and the post-L1000 slide are gone), apex species (15 deliberately
  dangerous species, 2x XP / 3x drops, tagged ☠ [APEX] in combat), elite/boss/empowered roles
  calibrated (empowered was harder than elite), regeneration capped (a regenerating boss was
  mathematically unwinnable), Forcefield anchored to the health bar (it was absorbing >1 full
  bar per cast — immunity with a mana cost) + its lying description fixed, companion HP scaled
  by aggro and companion damage/defense/regen unflattened, per-hit aggro rolls, server-authoritative
  ability costs shown on cards, mage kit anchored to the health bar (Bolt/Blast/Cleave) + Wisdom's
  caster damage restored, escape priced by level RATIO with a 25% floor, flocks budgeted per
  encounter, solo combat given the co-op playback pass, XP-remaining label fix

- **v0.9.740** — party leadership rotation + duplicated rewards, follower/post rules, party of 5,
  buff + item targeting (teammates and their companions), co-op playback pacing (rounds play fast
  but complete; Continue skips *to* the rewards), Forcefield/Haste co-op fixes
- **v0.9.739** — co-op combat you can follow (one animation clock), party items, party permadeath,
  login sprite offset, relog full-heal fix, 2-client test harness (`tools/test_setup/`)
- **v0.9.738** — real co-op party combat (shared fight, party cards, per-actor playback)
- **v0.9.735** — card arc: dungeon-exclusive cards, card market, class roster pass, FPS cap

---

## ⚑ COMBAT LOG — the wall of text, resolved (2026-09-04)

Owner reported it twice, then through five rounds of screenshots. Final shape: **one line per
actor per round**, folded by the SERVER'S actor tag; each member has their own gutter colour
with their companion indented in the same colour; the monster carries a heavier marker plus its
TARGET'S colour; and the damage number is hoverable for the modifier breakdown that used to be
its own lines.

    one Magic Bolt   9 lines -> 1
    a Blast round   13 lines -> ~5
    poison tick     "Poison deals 12 damage! (28 turns remaining)" -> "poison 12 (28t)"

**Research that shaped it** (owner asked for it explicitly): ADOM's community identified this
exact failure — "in the end game, every time you attack the user is flooded with a huge number
of messages" — and concluded the answer is FILTERING routine messages, not colouring them
better. Sil moves damage onto the monster so the log carries events, not numbers. This game
already had a damage summary card doing that job, so the log was duplicating it.

**The defects found on the way were nearly all WIRING, not mechanism** — worth remembering,
because each one looked like "the feature doesn't work":
- the hoverable number was wired to `_log_label`, which is allocated but never rendered; the
  visible label is `_battle_log_band`, and it was MOUSE_FILTER_IGNORE
- gutter colours were looked up with `.find(actor_pid)` on an array of member DICTIONARIES, so
  every member drew the same first colour
- actor tagging was verified against `process_attack` when the server calls
  `process_combat_action`, which WRAPS it and appends the monster's lines afterwards
- the keyword enhancer rewrote text inside BBCode tags, corrupting the tooltip payload
- `[url]` renders in the theme's link colour, silently overriding the colour the line had set
- the mouse card path never checked affordability despite a docstring claiming it mirrored the
  hotkey path, so an unaffordable click was refused by the SERVER after the click was spent

**The fold switched the floating damage numbers off** — "I'm no longer seeing damage numbers show
up over the enemy when the player hits them." They were recovered by REGEX from the line text
(`deals N damage` / `for N damage`), so rewording the lines silently disabled them. Re-wording the
prose to satisfy the parser would only re-arm the trap, so the number now rides on the same
per-beat metadata channel that already carries actor / target / hp, and `parse_damage_dealt` is
demoted to the fallback for lines that have no metadata yet (basic attacks, companion swings, DoT
ticks). Migrating those is the remaining half.

That work uncovered a second, older gap: **`process_ability_command` never attached its per-line
metadata at all.** `process_combat_action` brackets every basic attack with
`_begin_actor_marks` / `_attach_actors`, but a CAST returned the class processor's dictionary
straight through — so `message_actors` came back empty for every ability, which is why the actor
gutter only ever coloured attacks. Both are bracketed the same way now. Verified by a new
`dmgtag` probe: 29 damage lines across all ten damaging abilities, every number on its own line,
zero drift.

- [x] **DONE 2026-09-04 — the remaining damage lines are migrated; the parser is retired as a
      MECHANISM.** 20 more sites now record through `_note_dmg(combat, messages, amount)`, the
      form of `_damage_with_detail` for lines that build their own text: basic attacks (via the
      class attack description), companion swings and their ability procs, Quick Strike /
      Shocking / Execute, the three Arcane-Surge double-casts, poison / burn / bleed on the
      monster, and the thorns / Retribution / Path reflect family. `parse_damage_dealt` stays
      only as the fallback for anything not yet tagged.

      **The probe caught a flaw in the mechanism itself, which is the reason it exists.** A mark
      recorded only an INDEX, and the monster turn builds its OWN messages array — so its DoT
      ticks were recording "index 0" into the same bag as the player's action and landing their
      numbers on whatever the player's line 0 happened to be (`dmg=19 not in: Blast — 1286
      damage`, 17 such lines). Marks now name the array as well as the index and are matched
      with `is_same()` at attach time. 98/98 on the right line, zero drift.

      Verified by execution: basic attacks for all three class wordings, companion attacks,
      companion ability procs, Quick Strike. **NOT yet exercised by the probe** (same one-line
      mechanism, but unproven): poison / burn / bleed, thorns / Retribution / Path reflect,
      Shocking, Execute, and the double-casts — they need the gear or procs that trigger them
- [x] **STALE — the Trickster kit was already folded.** Ambush / Exploit / Gambit all route
      through `_damage_with_detail` and read as one line each (`Ambush — 302 damage`,
      `Exploit Weakness — 654480 damage`, `Gambit (it pays off) — 771 damage`). Listed as open
      after the work that closed it
**The MONSTER'S block was still a wall, and for a structural reason** (owner, 2026-09-04: *"the
forcefield line absorbing damage seems like it goes multiple lines still (when the monster
attacks)"*). `process_monster_turn` returns its narration joined with a newline — it has a dozen
return paths of two different shapes, so the join is its lowest common denominator — and the
caller appended that whole string as ONE message wrapped in two divider rules. So only its first
visual line could take an actor gutter, the client's fold could not group it at all, and the
dividers cost two more lines every round. No amount of folding on the player's side could reach
it.

Three changes, cause-first:
- the monster's turn is appended **one message per line**, so every line gets its own gutter and
  folds like anything else. The dividers are gone with it — the gutter is the frame now, and it
  marks every line rather than bracketing the group
- **mitigation rides on the hit it softened.** A fully absorbed blow read as three lines (the
  absorb, then "attacks and deals 0 damage!", then whatever followed); the Forcefield note is now
  a hover detail on the monster's own damage number. `_note_mitigation` is a DIFFERENT buffer
  from `_note_modifier` on purpose: that one collects what made your blow bigger, this one what
  made theirs smaller, and one shared bag would let your cast's modifier ride the monster's line
  as a lie
- the burn's last tick says *(the flames die out)* on the burn line instead of taking its own

Measured on the `actortag` probe: a round went from 6 lines to 4, with all 4 attributed.

- [x] **DONE 2026-09-04 — the cycle is visible now.** The old hand drops away (shrink, tilt,
      fade, staggered) and the new one deals back in from the deck. It is the ANSWER to the
      report rather than decoration: the redraw was always genuine, so when a small deck returns
      the same cards to the same slots the CONTENTS cannot show a cycle happened — only motion
      can.

      Triggered on a real cycle only, since a `combat_update` can arrive several times a round:
      the hand differing **or the discard count growing**, the second of which is what survives
      an identical-looking hand. The first hand of a fight deals in rather than snapping on.

      Two properties worth keeping if this is ever touched: it animates `scale` / `rotation` /
      `modulate` and never `position`, because the cells live in an HBoxContainer that owns
      position and size; and every render path passes through `_reset_hand_transforms()` with
      the previous tween killed, so an interrupted animation can never leave a card shrunk or
      invisible. Runs on the player's combat-speed setting like everything else.
- [x] **DONE 2026-09-04 — and the owner was right to ask whether it was stale.** It had already
      been half-fixed: `c9ec57d` moved the bar from an end-of-ROUND snapshot to an end-of-BEAT
      one (`_mhp_after_player`), which is the gross case that was reported. So the question was
      fair — but the line as written was still true, just narrower than it read.

      **Measured before acting: 13 of 16 attack actions produce MORE THAN ONE damage line**
      (your blow, your companion's, plus Quick Strike / Shocking / Execute procs). The snapshot
      attaches to the LAST line of the beat, so in 13 cases out of 16 the earlier numbers popped
      with the bar still frozen. Not stale, and not rare.

      Closed by the mechanism the damage work had just built rather than a third snapshot: the
      `_dmg_marks` entry now carries the monster's HP after that hit, so it travels beside the
      number as one event — `message_monster_hp` parallel to `message_damage`, forwarded per
      line in solo and attached per line in the party path. The end-of-beat snapshot still runs
      and still settles the bar; it simply no longer has to catch up.

      Solo gains a second thing from it: the bar was driven by `damage_dealt_to_current_enemy`,
      an ACCUMULATION of parsed numbers that drifts whenever a line is missed or the monster
      heals. Where the server sends a figure, it is now used directly.
