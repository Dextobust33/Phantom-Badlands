# Resource-economy fix — PROPOSAL read (2026-08-25)

Config: martial **dump** = 80% of current pool on the finisher (Devastate/Gambit), damage
scales with spend; **mage cost** = 2× (attrition); **capped regen** = min(16%-of-max, 25+level·0.5).
Metric = MinRes% (lowest pool% reached). All via `run_proposal_read()`.

## The design works — and gear investment now visibly matters
| L50 boss | MinRes% avg gear | MinRes% BiS gear |
|---|---|---|
| Warrior | **5%** (tight) | **36%** (comfortable) |
| Trickster | **12%** | **51%** |
| Mage | 27% | 35% |

| L80 boss | avg | BiS |
|---|---|---|
| Warrior | 15% | 53% |
| Trickster | 24% | 70% |
| Mage | 25% | 31% |

- **Martials (dump):** average gear now bottoms out at 5–24% on bosses (real pressure), while BiS floors at 36–70% (comfortable). **The gap IS the investment payoff** — stacking pool/gear visibly buys resource comfort, which is exactly what was missing. Elite sits a band above boss (avg ~12–53%, bis ~56–80%). Trash unpressured.
- **Mages (cost+capped regen):** steady 25–39% across gear on elite/boss — classic mana attrition, in the target band.

## Caveats / still to tune
- **Warrior L50 avg boss = 5% MinRes @ 59% win** — a touch too tight; likely dial dump 80%→~70% or ease the regen cap so average gear isn't nearly bottoming out.
- **Mage boss WIN-RATE is low (36–54%)** — but mages were already grindy on bosses (16–39 turn fights) *before* this; the 2× mana tax compounds it. Consider mage cost 1.5× and treat mage boss damage/length as a separate issue.
- **Not yet re-checked:** flock safety floor + partial-start (between-battle) recovery under these settings. Do before locking.

## Provisional numbers to implement
- Martial dump: **~70–80%** of current pool on Devastate/Outsmart, damage ∝ spend.
- Mage cost tier: **~1.5–2×** by end game (level-gated tiers).
- Regen cap: **min(16%, 25 + level·0.5)** — early game unchanged, late-game capped.
- Companion + Dungeon cards: same tier treatment.
- Net-cost card display (cost − turn regen) ships with it.
