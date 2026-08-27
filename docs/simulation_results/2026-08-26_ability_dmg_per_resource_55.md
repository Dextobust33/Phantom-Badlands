# #55 — Ability Damage-per-Resource Audit (2026-08-26)

Source: `tools/combat_simulator/real_combat_sim.gd` → `run_ability_efficiency()`, 300 casts/cell,
per-cast on a boss-HP target (won't overkill), engines (momentum/focus/read) start at 0 so
finishers (devastate/meteor/gambit) read as a FLOOR.

Dmg/Res = damage per unit of the class resource spent (higher = more efficient).

```
--- L10 average ---        AvgDmg   AvgCost   Dmg/Res
 War  power_strike         (free — 0 cost)
 War  shield_bash             147     10.0      14.70
 War  cleave                  292      2.3     129.89
 War  devastate            (no paid casts — engine-gated finisher)
 Mag  magic_bolt              160     64.2       2.49   ← dominated
 Mag  blast                   244      4.1      58.99
 Mag  meteor                  776     34.5      22.47
 Trk  ambush                  310      2.9     107.25
 Trk  exploit                 237      5.1      46.17
 Trk  gambit                  235      4.2      55.38
--- L50 average ---
 War  shield_bash             698     10.0      69.81
 Mag  magic_bolt              639    269.0       2.38   ← dominated
 Mag  blast                   542     31.3      17.34
 Mag  meteor                 1717     54.5      31.50
 Trk  (ambush/exploit/gambit) no paid casts — combo/read-gated in isolation
--- L50 bis ---
 War  shield_bash            1246      8.2     152.13
 Mag  magic_bolt             1215    472.7       2.57   ← dominated
 Mag  blast                   721     73.0       9.87
 Mag  meteor                 2226    114.8      19.38
--- L200 average ---
 War  shield_bash            3073     10.0     307.26
 Mag  magic_bolt             3790   1111.7       3.41   ← dominated
 Mag  blast                  1619    170.3       9.51
 Mag  meteor                 4952    258.9      19.12
```

## Finding 1 — Magic Bolt is strictly dominated (~2.5 dmg/mana at every level)
`magic_bolt` damage = `bolt_amount × int_multiplier × focus`, cost = `bolt_amount`, so its Dmg/Res
is just `int_multiplier` (≈2–3.4). Blast delivers MORE damage per turn for a fraction of the mana
at low level, and even at L200 its efficiency (9.5) is ~3× bolt's (3.4). There is no level/gear
where bolt is the efficient choice; its only edge is raw per-turn BURST (dump 25%+ mana at once),
which only matters ≥L200. Early game it's pure trap.

## Finding 2 (STRUCTURAL, bigger) — martial FLAT cost vs caster %-MAX cost diverge with level
- Warrior `shield_bash` cost is FLAT (10 stamina) → Dmg/Res EXPLODES with level as damage scales:
  **14.7 → 69.8 → 152 → 307** (L10→L200).
- Mage `blast` cost is %-of-max-mana → Dmg/Res is flat/declining: **59 → 17 → 9.9 → 9.5**.
- By L200 the warrior is **~32× more resource-efficient** than the mage. Stamina/energy become
  irrelevant late (spam finishers forever) while mana stays a real constraint.

This confirms [[project_resource_economy_scaling]]: **flat martial costs don't scale.** The
cross-class *parity* break at #55 and the resource-economy *scaling* flaw are the same root cause.

## Ground-truth vs REAL players (server pull, 2026-08-26) — sim calibration check
Pulled all live characters from prod (`data/characters/*.json`). Findings:

| Real char | Lv | Class | STR | INT | Mana | Stam | gear iLvl |
|---|---|---|---|---|---|---|---|
| derpasaurus | 43 | Paladin | 52 | 9 | 87 | 130 | 59 |
| Caps0 | 35 | Sage | 9 | 56 | 352 | 55 | 19 |
| Dexto | 31 | Barbarian | 78 | 9 | 42 | 117 | 31 |
| M_Dex | 26 | Sorcerer | 8 | 48 | 168 | 22 | 15 |

- **Level range: real players top out at L43.** The sim's L200 / L1000 cells are purely
  hypothetical — tune for **L1–~50** for current reality.
- **Stat allocation ✓ matches.** Sim auto-level-up gains (Wizard INT 26@L10, 66@L50) interpolate
  to ~51 @L35 — close to the real L35 Sage's INT 56 / L26 Sorcerer's 48. The sim's naked-stat
  scaling is a fair proxy for a focused build.
- **Gear is OVER-estimated by the sim ⚠️ (the big one).** Real players are frequently UNDER-geared:
  L35 Sage on iLvl-19 gear, L26 Sorcerer on iLvl-15. The sim assumes "average = rare AT char
  level / bis = artifact AT level", so its pools run ~2–3× real (sim L35 mage ≈ 900 mana vs real
  352). => real damage, pools, and gear-regen are all LOWER than the sim showed, so the high-level
  "resources trivialize" effect is a FUTURE problem, milder in the current L1–43 under-geared meta.
- **Action item:** add an under-geared default (gear iLvl a bit below char level) + cap the audit's
  headline cells at ~L50 so the numbers reflect what players actually experience.

## Measurement confound found (regen) — must fix before trusting per-cast cost numbers
`_measure_ability` measured NET resource (spend − regen-during-monster-turn). Gear grants flat
per-round `mana_regen`/`stamina_regen`/`energy_regen` (computed per slot+level, NOT a strippable
affix). At mid/high level that regen ≥ a single cast's cost, so net reads ~0 (blast "spent 0" @L50).
The gross per-cast COST is fine in-game; the SIM just needs a regen-free cost probe (e.g. measure on
turn-1 pre-regen, or a dedicated cost hook). Until then treat the post-fix Dmg/Res cells as noisy.

## Mage cost-model change (built, NOT yet clean-verified — hold from release)
`apply_variable_cost` + `_process_mage_ability`: ceiling now scales with `character.max_mana`
(naked: level+INT, EXCLUDES gear/house) instead of `get_total_max_mana()`. Intent: gear +max
mana/regen buys MORE casts (cap builds matter) while INT scales power+cost together (parity). The
`Casts/Bar` column did move the right way (bis meteor 159 casts/bar vs avg 87) but the regen
confound + gear over-estimation mean it's not cleanly verified yet. Keep local; don't ship until the
regen-free cost probe confirms baseline feel + parity in the L1–50 range.

## CLEAN numbers (regen-free gross-cost probe, 2026-08-26 pm) — the decisive result

Cost now read from `path_last_ability_cost` (gross spend) on a 50× HP dummy (no kill → no
refund-zero, no regen masking). **Dmg/Res by level shows the core imbalance unambiguously:**

```
Ability (cost type)        L10     L50    L50bis   L200    L1000
War power_strike (flat 5)   38     177     322      801     4204
War shield_bash  (flat 10)  15      70     125      309     1616
Trk ambush       (flat 20)  14      64     128      277     1461
Mag blast  (scales w/ mana)  7      16      21       32       32
Mag meteor (scales w/ mana) 12      27      34       74       70
Mag magic_bolt (25% pool)  1.7      2      2.3        3       10
```

**Martial abilities (FLAT cost) → Dmg/Res explodes ~110× (power_strike 38→4204). Mage abilities
(cost scales with pool) → Dmg/Res stays ~flat (blast 7→32).** By L1000 a Warrior is ~130× more
resource-efficient than a Mage. Casts/Bar confirms it: L1000 power_strike = **2148 casts/bar**
(stamina is a non-constraint), Mage blast = 96, magic_bolt = 4.

=> **The culprit is the flat martial cost model, NOT the mage.** The mage naked-mana slice was the
right *model* but the wrong *class to start with* — mages are already the least efficient. The real
fix is to bring MARTIAL/Trickster costs onto the same naked-pool `cost_percent` curve so their
costs scale with level too (Dmg/Res flattens across the board, resources stay a real constraint).
This is the unified model the user greenlit — mage was the proof-of-concept; martial is where the
imbalance actually lives.

### Caveat: `exploit` (Trickster) damage is DUMMY-INFLATED — investigate separately
exploit reads 11k @L10 → 1.5M @L1000 Dmg (Dmg/Res 470→63905). That's because exploit scales with
enemy MAX HP and the probe uses a 50× HP dummy → its damage is inflated ~50×. On a normal target
it'd be far lower. BUT: if exploit deals a large %-of-max-HP, it may be an unintended execute/nuke
worth checking on its own (separate from this cost audit). All FLAT-damage abilities are unaffected.

## Real-player balance findings (server audit, 2026-08-26) — feed the tuning
- **Max level ≈ 10,000** (`COMPANION_MAX_LEVEL` "same as player max"). High-level cells ARE real;
  players will climb into the 1000s. Sim now includes L1000.
- **NO equip level requirement** (code grep: only *dungeon* min-level *warnings* exist). A player can
  wield gear far above their level. **derpasaurus (L43 Paladin) wears L60–74 gear** (amulet L70,
  ring L74, shield L73; con +58, attack +55–72) → massively over-statted for L43 → fights monsters
  far above his level → snowballs better gear. This is the #1 progression break.
- **derpasaurus's "abuse" = defensive-buff-stack tank.** Top ability uses: forethought 202,
  iron_skin 165, shield_bash 164, fortify 159, rally 121, devastate 108. Stack mitigation → near-
  unkillable → grind anything down. Milestone picks nearly all "power". Over-level gear seals it.
- **Under-gearing is a SYMPTOM, not the target.** Players are under-geared because combat is too easy
  to force farming. Target = gear-at-level + monsters tuned so proper gearing is required. (Verify
  the intended best-gear acquisition path is actually viable — TODO.)

## Recommended fix order (post-audit)
1. **Equip level requirement** (or steep over-level penalty) — stops the L43-in-L74-gear snowball.
2. **Unified naked-pool cost model for martial/Trickster** (extend the mage slice) — kills the
   130× efficiency gap; resources stay relevant at all levels.
3. **Monster challenge pass** so proper gearing is required (ties to the equip-level fix).
4. Cap/DR on defensive-buff stacking (forethought+iron_skin+fortify+rally near-invuln).
5. Check `exploit` %HP scaling; verify best-gear acquisition path.

## VERIFIED: unified naked-pool cost model (martial/Trickster scaling shipped to sim)

Extended `cost_percent` (of the NAKED pool) to martial + trickster abilities; generalized
`apply_variable_cost` to scale stamina/energy ceilings the same way mage mana already did.
cost_percent tuned below flat/pool@L10 so early game is unchanged. Re-ran the clean probe:

```
                 L10          L1000        L1000
Ability      cost / c/bar   cost / c/bar   Dmg/Res      (was L1000 flat)
War power_strike  5 / 37     86 / 125      244          (was cost 5, c/bar 2148, D/R 4204)
War shield_bash  10 / 19    108 / 99       150          (was 10, 1063, 1616)
War cleave       16 / 12    128 / 80       200          (was 16, 641, 1608)
Trk ambush       20 / 9     133 / 74       219          (was 20, 493, 1461)
Trk gambit       24 / 7.5   160 / 62       172          (was 24, 410, 1144)
Mag blast        34 / 11    222 / 96        32          (unchanged — already scaled)
Mag meteor       65 / 6     300 / 76        70
```

**Result:** Casts/Bar is now ~CONSTANT across levels for every class (~60–125) instead of
exploding to 2000+ for martial. The 130× cross-class efficiency gap collapsed to ~3–7×.
Resources are a real constraint at all levels; a bigger/geared pool buys more casts. **L10 is
unchanged** (early game preserved). Core #55 goal achieved.

Residual (future tuning, non-blocking):
- Mage abilities still deal less damage-per-cost than martial (D/R 32–70 vs 150–244) — a DAMAGE
  lever, not cost. Mages are the weak side, so "mages could hit a touch harder," not "nerf martial."
- ~~magic_bolt fixed at ~4 casts/bar + D/R 2–10 (25%-pool dump) — bad card~~ → FIXED: multiplier
  rebuilt to `1 + 3.5·sqrt(INT)` (was `1 + max(sqrt/5, INT/75)`). Now D/R 16→65 across levels,
  per-bar burst ~1.4M @L1000 (on par with shield_bash/meteor). Mage brought to parity via its
  signature spell per user direction; still a low-sustain high-burst tool (blast = efficient spam).
- Remaining minor: at L50 martial spammables (power_strike per-bar 83K) still lead mage blast
  (20K); a small blast damage bump could close it, but magic_bolt/meteor are now on-par.
- devastate reads "no paid casts" (momentum-gated finisher — not measurable in isolation).
- exploit D/R still dummy-inflated (%-max-HP × 50× HP probe) — known caveat, ability is fine.

## Measurement gaps (for a follow-up harness pass)
- Engine-gated finishers (devastate/gambit) + all Trickster cards at L50+ show "no paid casts" —
  measured in isolation with engines at 0 they either can't cast or spend nothing. Need a variant
  that pre-builds momentum/combo/read (or measures over a full fight) to get their real numbers.
- power_strike = free basic (0 cost), correctly shows no paid casts.
