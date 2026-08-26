# Resource-economy audit — BASELINE (2026-08-25, pre-fix)

Run: `real_combat_sim.gd` → `run_resource_audit()`, 80 fights/cell, full starting resources.
**MinRes%** = avg lowest pool% reached during a fight (the headline: high = pool never pressured = management dead).
**Pool** = avg absolute max resource. **Casts/t** = ability casts per turn.

## The smoking gun
| Stage | MinRes% (War) | MinRes% (Trk) | MinRes% (Mag) | Pool grows |
|---|---|---|---|---|
| **L10 under/avg** (early) | 69–94% | 50–93% | 72–93% | 89–390 |
| **L50 any gear** | **94–96%** | **94–97%** | **89–92%** | 350–2130 |
| **L80 bis** | **94%** | **94%** | **90%** | 1650–3650 |

- **Early game (L10, under gear): the pool DOES get pressured** — War dips to ~69%, Trk to ~50%, Mag to ~72% in elite/boss fights. Matches user "starting out it seems okay."
- **By L50+ the pool NEVER drops below ~90-94%** for any class/gear/enemy. You spend at most ~6-10% of your pool across an entire fight. `EndRes% ≈ MinRes%` (both ~94%) confirms the pool sits pegged near full the whole time.
- Cause: pool balloons ~20× (89→1820 War, 189→3652 Mag) while flat costs (ceilings ≤32) become a rounding error AND 16%-of-max regen refills faster than you can spend. Investing in max resource is worthless — the pool already never binds.

## Fix target (for A: decouple regen from max)
Tune regen down (flat/low, not %-of-max) until:
- **Plain/trash:** MinRes% stays high (~70%+) — fine, tension belongs in fights that matter.
- **Elite:** MinRes% dips to ~40–60% (must pace, real decision).
- **Boss:** MinRes% dips to ~20–40% (real pressure; overspend → bottom out).
- **More max-resource investment RAISES the MinRes% floor** in a given fight (weather it better) — the investment payoff (B). Verify by sweeping a max-pool multiplier once A is in.
- D (overcharge sink into Devastate/Outsmart) then gives big pools an active dump payoff.

Re-run this audit after each tuning change; ship only when the bands above are hit without wrecking win-rate.
