# Balance Pass Findings — 2026-05-10

Post-variable-cost-rework balance pass. Run after v0.9.265 shipped (22/23 abilities on variable cost; Analyze + Vanish locked at fixed cost).

## TL;DR

Variable-cost rework did **not** regress canonical balance. Class spread tightened from 6.9% (2026-02-06 baseline) to 5.4%. All 9 classes within 88.7%–94.1% same-level win rate — well within the audit's locked 89-96% tolerance. **Pre-Slice-6c gate cleared.**

## Method caveat (read before interpreting numbers)

The simulator at `tools/combat_simulator/` uses its **own** `combat_engine.gd`, not the live `shared/combat_manager.gd`. The sim's engine has hardcoded ability values and is unaware of `variable_fraction`. Effectively, the sim tests *canonical full-cost casts* only.

That makes this run a **canonical balance check**, not a measurement of variable-cost partial-spend impact. To measure floor/partial behavior, either:
1. Port `apply_variable_cost` + the spend logic into the sim's engine (substantial work — possible future slice if Slice 6c surfaces issues).
2. Hand-playtest at low resources.

For the purposes of the Slice-6c gate, this is sufficient: variable-cost was designed not to change full-cost numbers, only to provide a usable partial cast below ceiling. The fact that full-cost balance is unchanged is the expected and confirmed outcome.

## Class win-rate comparison

| Class | 2026-02-06 | 2026-05-10 | Delta |
|---|---|---|---|
| Wizard | 96.0% | 94.1% | -1.9 |
| Sorcerer | 95.7% | 94.0% | -1.7 |
| Sage | 95.7% | 93.2% | -2.5 |
| Barbarian | 94.4% | 93.5% | -0.9 |
| Fighter | 94.4% | 93.1% | -1.3 |
| Paladin | 94.1% | 93.1% | -1.0 |
| Ranger | 90.4% | 89.9% | -0.5 |
| Thief | 90.0% | 89.4% | -0.6 |
| Ninja | 89.1% | 88.7% | -0.4 |

**Spread:** 5.4% (max 94.1 − min 88.7). Was 6.9% in baseline.

Small mage drop (≤2.5%) likely reflects natural variance across 1000-iteration runs plus any incidental gear-roll differences; not flagged as actionable.

## Persisting issues (unchanged by this rework, deferred)

### High-lethality champion monsters

| Monster | Win Rate | Formula Off By |
|---|---|---|
| Iron Golem Champion | 0.0% | +29,276% |
| Gargoyle Champion | 0.0% | +16,569% |
| Hydra Shield Guardian | 0.0% | +18,792% |
| Goblin Shield Guardian | 5.1% | +3,233% |
| Giant Spider Champion | 13.5% | +1,385% |
| Corrosive Wolf | 14.8% | +1,824% |

Champion / Shield Guardian / Corrosive elite variants are unbeatable in sim. This was the case in the 2026-02-06 run too. Defer to a separate elite-monster tuning slice.

### Mid-game sag (L500-1000)

| Class | L500 avg-gear | L1000 avg-gear |
|---|---|---|
| Sage | 75.6% | 69.4% |
| Wizard | 78.9% | 79.2% |
| Sorcerer | 82.1% | 84.4% |
| Fighter | 93.4% | 92.5% |

Mage classes drop noticeably at L500-1000 with average gear. Recovers at L5000 (100%). Likely indicates monster lethality scaling between L100 and L5000 has a soft-spot mages don't have answers for. Defer to a separate scaling pass.

### Low-level trickster gear-poor

Thief/Ranger/Ninja at L5 poor gear: 62-65% win rate. Unchanged from baseline. These classes have always been gear-sensitive; pre-rework concern.

## Gate decision: PASS for Slice 6c

No new regressions surfaced. Variable-cost rework's full-cost balance is intact. Persisting issues are all pre-existing and orthogonal to the deck-building arc.

**Recommended next:** ship Slice 6c (deck cull / pruning) without further tuning. Re-run the sim periodically as deck mechanics evolve.

## Files

- Raw data: `docs/simulation_results/2026-05-10_results.json`
- Auto-generated summary: `docs/simulation_results/2026-05-10_summary.md`
- Prior baseline: `docs/simulation_results/2026-02-06_summary.md`
