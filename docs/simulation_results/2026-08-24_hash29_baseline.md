# #29 Resource + Monster-HP rebalance — BASELINE (2026-08-24)

Sim: `tools/combat_simulator/real_combat_sim.gd::run_baseline()`, 60 fights/cell, real code.
Columns: Win% / AvgTurns / Casts-per-fight. Classes: War(rior), Trk(=Thief), Mag(=Wizard).

## Headline findings
1. **Fights are far too short.** BiS: War boss L50 2.9t / L80 2.5t; Trk boss L50 2.1t / L80 1.7t; trash 1.5-2t. Target for "real" fights is ~8-12t → monsters need MUCH more effective HP.
2. **Players barely cast.** Casts-per-fight collapses at average/BiS (often 0.0-0.5) — fights end before you can act, so the build-up engines never function. Early/under-geared casts more only because those fights limp longer (attrition).
3. **Win-rate has headroom.** BiS ~88-100%; under-geared appropriately low. So monster HP can rise a lot WITHOUT hurting prepared players — as long as monster DAMAGE is NOT raised (the user's guardrail).

## Interlock
Short fights + thin early resources = ~1 cast/fight. Fixing needs BOTH: longer fights (monster HP) AND enough resource/regen to cast most turns.

## Raw (excerpt)
```
Cls Lvl  Gear     Enemy    Win%   Turns   Casts
War 50   bis      boss     100%    2.9     0.4
War 80   bis      boss     100%    2.5     0.3
Trk 50   bis      boss     100%    2.1     0.0
Trk 80   bis      boss     100%    1.7     0.0
Mag 50   average  boss      82%    9.3     1.1   (mage runs longer — sim gives it physical gear, understating spell dmg)
```
Note: sim equips physical *_artifact gear, so Mage spell damage is understated (real mages stack INT). Treat Mage turn/cast numbers as a loose lower bound.

## Plan (levers to sim-tune)
- **Monster HP ↑** (primary length lever): ~2.5-4× effective HP for real enemies (elite/boss); keep trash short. Do NOT raise monster damage.
- **Resource pools**: add an early flat floor (+ modest ×) so low-level pools hold ~3 casts; normalize energy (×0.75 → ≥ stamina scale).
- **Regen**: 12% → ~18% and/or a small flat floor so early-game % isn't negligible.
- Re-run baseline after each change; target trash ~2-3t, real fights ~8-12t, BiS win ~85-95%, ~1 cast most turns.
