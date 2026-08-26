# Resource Economy Overhaul — v0.9.722 (balance reference)

**Shipped 2026-08-25.** Large combat change — expect follow-up tuning. This doc is the
single place to find WHAT changed, the exact knobs, and HOW to re-balance.

## The problem it fixes
Resource pools + regen scaled with level/gear/stats, but card costs were flat & capped, so
by mid-game (L50+) the pool never dropped below ~90% in a fight — resource management was
dead and investing in more resource did nothing. Proven with the sim (see
`docs/simulation_results/2026-08-25_resource_audit_baseline.md`). Regen alone wasn't the
lever (even 0% regen left martials at 94% MinRes — flat costs are trivial vs a big pool),
and flat cost multipliers vanish at L1000. Fix = per-class mechanics that are %/pool-based
so they hold at any level.

## What changed (per class)
- **Capped regen (all classes)** — base in-combat regen = `min(16%-of-max, cap)`, `cap = 25 + level·0.5`, floor 4. Early game the % applies (unchanged); late game the cap binds so regen stops ballooning with the pool. Sustain beyond the cap comes from resource-regen GEAR affixes (the sustain build axis).
- **Warrior — Devastate = DUMP.** Consumes `DEVASTATE_DUMP_PCT = 0.60` of CURRENT stamina (not a flat ceiling); power scales `0.5×..1.5×` with how full the bar was. Build → dump → rebuild. Bigger pool / fuller bar = harder hit.
- **Trickster — Outsmart = energy dump.** Spends `OUTSMART_DUMP_PCT = 0.60` of current energy; bar fullness adds up to `OUTSMART_DUMP_MAX_BONUS = 30`% outsmart chance (clamped to 95). Was free+spammable; now a deep energy pool makes the outwit reliable.
- **Mage — cost_percent raised** so mana cost scales with the mana pool (holds to L1000). Bolt remains the mage's big dump. `magic_bolt` unchanged.
- **Net-cost card display** — the card cost pip shows `planned_cost − this-turn regen`.

## Exact knobs (where to tune)
| Knob | Value | File |
|---|---|---|
| `BASE_COMBAT_REGEN_PCT` | 16.0 | `shared/combat_manager.gd` |
| `BASE_COMBAT_REGEN_CAP_FLAT` / `_PER_LVL` | 25 / 0.5 | `shared/combat_manager.gd` |
| `DEVASTATE_DUMP_PCT` | 0.60 | `shared/combat_manager.gd` (also mirror in `client.gd _get_ability_planned_spend`) |
| `OUTSMART_DUMP_PCT` / `_MAX_BONUS` | 0.60 / 30 | `shared/combat_manager.gd` |
| mage `cost_percent` (VARIABLE_COST_TABLE) | blast 6, meteor 8, haste 5, paralyze 7, banish 9, forcefield 3 | `shared/combat_manager.gd` |
| net-cost regen mirror | `_estimate_turn_regen()` | `client/combat_scene_panel.gd` |

## How to re-balance (sim-first)
`godot --headless --path . --script res://tools/combat_simulator/real_combat_sim.gd` →
`run_proposal_read()` prints MinRes% (lowest pool% in a fight) across level×gear×enemy to
L1000. Also `run_flock_audit()` (safety floor across 5-fight chains) and `run_cost_solve()`.
Change a knob in `combat_manager.gd`, re-run, read MinRes%. Targets: plain unpressured,
elite ~40–60%, boss ~20–40%; **more gear/pool should RAISE MinRes** (the investment gradient).

## Validated behavior (2026-08-25)
- Single fight: gear-investment gradient works (avg gear tense, BiS comfortable), holds to L1000.
- Flock chains (5 back-to-back, no refill): ChainMin% 11–46%, never 0 → **no resource death-spiral**; covers partial-start / "jumped before you recover."

## ⚠ Known soft spots + gotchas (likely next tuning)
- **Warrior Devastate dump has a SHARP CLIFF between 0.60 and 0.65** (L50 avg boss MinRes 46% → 2%): repeated deep dumps outrun the capped regen. Do NOT raise `DEVASTATE_DUMP_PCT` past 0.60 without also raising the regen cap. 0.60 is intentionally a touch comfortable (avg boss ~46%) to stay off the cliff.
- **Mage flock/boss softness is NOT a mana problem** — easing cost_percent barely moved the clear-rate (~53%). It's pre-existing mage low-DPS/fragility on long fights. Fix in a separate combat-power pass; don't over-ease mana chasing it (that just makes mana irrelevant).
- **Outsmart turn-1 wins in even-level matchups** (pre-existing): with a full-bar dump bonus the outwit can land immediately when the enemy isn't higher-level. Worth a separate look at Outsmart's base chance curve.
- **Monster difficulty at extreme level:** at L1000 average gear the fights end too fast to stress the pool — a monster-scaling axis, separate from resources.
- Sim caveat: the trickster sim AI uses even-level matchups so it can't show the trickster energy ARC (lives in higher-level content). Devastate damage in the sim is held at base for the cost-emulation paths (conservative).

See also memory `project_resource_economy_scaling.md` for the full decision history.
