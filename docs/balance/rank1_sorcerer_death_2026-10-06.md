# The rank-1 Sorcerer's death (2026-10-06) - what it tells the balance work

Owner, 2026-10-14: *"When it comes to balance make sure to get any info you can about my high level
character that died at rank 1. I put a good amount of time into that character."*

This is everything recoverable about that character. **Read it before the balance batch.** Raw data is
beside it in `docs/balance/data/` (the full death record, and 467 damage traces from his last four
hours). Both were pulled read-only from the live server on 2026-10-14; nothing on the server was touched.

## The character

| | |
|---|---|
| Name / class | **Dexto, Dwarf Sorcerer** - Level **91**, leaderboard **rank 1** |
| Created / died | 2026-09-22 01:25 UTC / **2026-10-06 00:25 UTC** (about 14 days; most of the levelling was one ~4 hour session on 10-05) |
| Kills | **486** monster kills in 91 levels - levelling was NOT kill-driven (dungeon-clear XP and auto-resolved fights) |
| XP / valor | 1,042,674 XP; 864,630 Valor on the account |
| Stats (base) | **INT 205, CON 57, WIS 57, DEX 32, WITS 11, STR 8** |
| Max HP | **2,242** |
| Gear | amulet L71 uncommon, armor L56 rare, boots L97 uncommon, **helm L70 ARTIFACT (Warbringer's Crown, unique)**, ring L105 legendary, shield L101 rare, weapon L55 epic. Mixed levels, **avg ~79 on a L91 character**, two slots 35 levels behind. All worn (wear 2-6) |
| Companion | Hydra Sprout L53 (aggro 50, **registered**), a Dragon Whelp L60 (registered), a bench of L1-L5 spares. This is the character that held the L53 hydra |
| Account | **flagged [ADMIN]**. The journal shows **no GM command** on this character (searched `[GM]`, `gm_`, `/setlevel`, `/give`, `admin_`), but not every GM handler logs, so *admin use cannot be ruled out from here* - ask the owner |

## The death

Killed in **one round, from full health, having dealt 0 damage.**

> You encounter a ★ Nazgul Champion (Lvl 101)! ... Traits: Life Stealer, Cunning Prey, XP Drainer,
> Ambusher, Berserker, Ethereal, Causes Bleeding, Curse, Weakening, Disarming, Slowing Aura.
> ⚠ TIER +1 - Extreme danger!  ⚔ strikes first.  AMBUSH!
> drains **2,020** life / hits you for **4,040** damage / aura slows you.

* **6,060 damage in one round against 2,242 max HP - 2.7x his whole bar.** The 4,040 hit alone was 1.8x it.
* The monster's *base* hit is ~2,300 (4,040 / the 1.75x ambush): **one ordinary hit from this champion
  is his entire health bar at L91.** The fight was lost at the initiative roll; there was no decision.
* Level gap **+10** (L101 vs L91). 11 traits on one monster. HP 36,561.
* This is the shape `death_log_audit` calls *"I never got to play"*; **5 of the 13 current-era deaths
  are of this kind**. It is in section 3 of that audit as an at-or-near-parity death only if you read
  the gap as <=10.

## How the game's own curve rates that fight

From `shared/reference_*_curve.json` (interpolated on a log scale):

| | reference at that level | this fight |
|---|---|---|
| Monster HP, L101 | anchor 9,655 x Nazgul 2.05 x elite 1.8 = **~35,700** | **36,561** - *on the curve* |
| Player EHP, L91 | **1,282** | **2,242** (Dexto had **1.75x** the reference) |
| Player damage / turn, L91 | **2,483** | his **killing blows: median 2.3x the monster's whole HP, up to 65,748 in one hit** (467 traces; 369 kills) |

So the monster was exactly as strong as designed and the player was *tankier than the reference* -
and still died with no turn. **The curve is calibrated on average damage taken per turn
(`taken_ps`); this was a burst of ~4.7x the reference player's bar. Monster traits (Ambusher,
first-strike, Life Stealer) stack on top of the calibrated strength and are a tail the chain does
not see.** He also one-shot almost everything else (killing blow median 2.3x HP; an L70 Nazgul's
18k HP fell to a 28k cast). *Glass cannon, one initiative roll from death* - a Sorcerer shape, and
the audit already shows Sorcerer, Wizard, Paladin and Barbarian among the 13.

## THE INSTRUMENT DEFECT THIS EXPOSED (fixed 2026-10-14, v0.9.840)

His stats looked wrong for the simulator's L91 Sorcerer: **sim INT 107 / CON 9 vs his INT 205 / CON 57.**
Cause: `Character.level_up()` - which the reference player (`make_char`) is built with - added each
class's *fractional* per-level gains straight into integer stats (anything under 1.0 truncates to
**zero**) and granted **no stat point**. `add_experience()`, the path every real player levels by,
accumulates the fractions and grants a point. Two paths, one field.

Measured at L60 (same class, same race), XP path vs the old `level_up()`:

| class | XP path (live) | old `level_up()` (reference player) |
|---|---|---|
| Fighter | STR 146, CON 57, DEX 25 | STR **73**, CON **13**, DEX 11 |
| Ranger | STR 12, CON 55, DEX 115 | DEX **12**, CON **11** |
| Sorcerer | INT 158, CON 29, DEX 24 | INT **76**, CON **9**, DEX 10 |

**The reference player the whole monster curve is calibrated against has had roughly half of a real
player's stats at L60, and under a tenth for some.** (It explains the handoff's "live base CON 17-19
vs sim 12-13" at L6+, which was a symptom.) Fixed by one shared `_apply_level_stat_gains()`; probe
`tools/probe/level_up_paths_agree.gd` fails on the old code. After the fix the simulator's L91 Dwarf
Sorcerer reads **INT 232 / CON 40 / WIS 56 / DEX 32 / WITS 11 / STR 8** against his
**205 / 57 / 57 / 32 / 11 / 8** - DEX, WITS and STR identical.

**Still different, and now the real remaining gap:** best single cast 14.9k (sim) vs 28k-65k (live);
max HP 2,884 (sim, full gear at level) vs 2,242 (live, four slots 15-35 levels behind). That is gear,
paths, card upgrades and companions, not stats. Measure it with `-- refval`/`-- spread` after the
chain, not before.

## Two smaller things the same record found

* **Auto-resolved fights that level you showed a NEGATIVE XP number and no "+XP" line**
  (`Corrosive Balrog (Lv 68) +-865071 XP`): `resolve_without_fight` reported the change in the XP *bar*,
  which wraps on a level-up. Fixed; probe `trivial_xp_survives_a_level_up.gd`. He levelled this way
  through the whole last session, so the player was shown none of that XP.
* **Levelling pace is not what the curve assumes:** 486 kills for 91 levels, ~600k XP in a single
  second-long batch of 21 auto-resolved L56-76 monsters. A player 15-35 levels above the ground earns
  10-60k XP per "trivial" kill. Worth its own look in the batch (is the XP curve past the trivial gap
  too generous?).

## What to do with this in the BALANCE BATCH (item 9)

1. **Run the chain on the corrected reference player** - the previous curve is calibrated against the
   wrong character. Expect the monster base to rise; judge it against the absolute targets, not against
   the old numbers (CLAUDE.md: ONE pass each, +/-10pp).
2. **Add the burst tail to the instrument's questions:** `taken_ps` is an average. Count how often a
   first-strike + ambush + drain round exceeds the player's whole bar, by role and level gap, from the
   `[ENCOUNTER]` journal lines as they accumulate. (At zero encounters logged today, this document and
   the 13 deaths are the evidence.)
3. **Per-class, not global:** a Sorcerer with 1.75x the reference EHP still died in one round, so a
   global HP buff would not have helped him and would wash out at the next refit anyway.
4. **Ask the owner** whether admin tools touched this character - it decides whether his gear and
   levelling pace are a representative "careful player" or an outlier.
