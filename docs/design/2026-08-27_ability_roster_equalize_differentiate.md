# Ability Roster — Equalize + Differentiate (Design Proposal)

**Date:** 2026-08-27
**Task:** #36 (reframed by user) — "All classes should ideally have the same number of
starting cards. Fine to differentiate, but carefully — fit each class's vision/identity,
don't break balance or cause abusable loops. Optionally, different class CHOICES within an
archetype could have slightly different cards to strengthen identity + balance."

## Current state (combat-deckable cards)

| Archetype | Count | Cards |
|---|---|---|
| **Warrior** (Momentum) | 9 | power_strike, cleave, devastate, shield_bash, **war_cry**, **berserk**, fortify, iron_skin, rally |
| **Mage** (Focus) | 7 | magic_bolt, blast, meteor, forcefield, haste (Arcane Surge), paralyze, banish |
| **Trickster** (Combo/Read) | 9 | ambush, gambit, exploit, perfect_heist, pickpocket, vanish (Phantom Strike), analyze, distract, sabotage |

(Universal non-combat: cloak, teleport. Companion cards are separate.)

## Findings (from full mechanics audit)

The engines (Momentum/Focus/Combo, shipped #33–35) already differentiate what looked like
redundant "tiers":
- **Warrior damage:** power_strike (cheap builder, +1 Momentum) → cleave (builder + bleed DoT)
  → devastate (spends Momentum, gated ≥1). A build→payoff loop, not a tier ladder.
- **Mage damage:** magic_bolt (burst nuke, Focus+1) → blast (efficient sustain + burn, Focus+1)
  → meteor (discharges Focus ×1.25/stack). Differentiated by Focus.
- **Trickster damage:** ambush (reliable 50% crit builder) / gambit (high-variance 4.5×) /
  exploit (%max-HP, gear-independent tank-killer) / perfect_heist (instant-win %). Distinct.

**Real issues, narrow:**
1. **war_cry ⟂ berserk conflict.** Both write the `damage` buff type; `add_buff` keeps MAX
   value → running both is pointless. ONLY genuine redundancy.
2. **Count mismatch.** Mage has 7 vs 9/9.

**Non-issues (keep as-is):** fortify (`defense` layer) + iron_skin (`damage_reduction` layer)
stack multiplicatively — complementary, not redundant (both capped by the 85% MITIGATION floor).
distract (`enemy_distracted` accuracy) + sabotage (`monster_sabotaged` STR/DEF) are different
debuff slots — stack, both justified.

## Proposal: target **9 cards per archetype**, via a shared role framework

Honors both asks: "differentiate, don't delete" (nothing is cut) AND "equal counts" (all → 9).
Only Warrior gets a re-role (fix the conflict) and Mage gains 2 identity-fit cards.

### Shared 9-slot role framework

| Slot | Role | Warrior | Mage | Trickster |
|---|---|---|---|---|
| 1 | Cheap builder (engine +1) | power_strike | magic_bolt | ambush |
| 2 | Rider builder (engine +1 + DoT/effect) | cleave (bleed) | blast (burn) | gambit |
| 3 | Engine finisher | devastate | meteor | perfect_heist |
| 4 | Offense buff | **berserk** (risk dmg) | haste (Arcane Surge) | analyze (+dmg, reveal) |
| 5 | Defensive layer A | fortify | forcefield | vanish (evade→auto-crit) |
| 6 | Defensive/tempo layer B | iron_skin | **NEW: Frost Nova** (control) | distract (accuracy −) |
| 7 | Control | shield_bash (stun) | paralyze (stun) | sabotage (STR/DEF −) |
| 8 | Signature gamble/removal | **war_cry → re-role** | banish (removal) | exploit (%HP) |
| 9 | Sustain/utility | rally (heal) | **NEW: Ember** (cheap filler nuke) | pickpocket (steal) |

### Warrior change (fix conflict, no deletion)
- **berserk** stays the damage buff (risk/reward, −40% def).
- **war_cry → "Rallying Cry":** stop it writing the `damage` slot. New role = **tempo/Momentum
  jump-start**: instantly +2 Momentum and +small accuracy (or +10% crit) for 3 rounds. Fits
  "Warrior = safest in long fights, builds toward big hits." No longer overlaps berserk; both
  have a clear place. (Alternative: make war_cry a *team* damage buff — only useful in party;
  but party combat is currently solo per #64, so tempo is the better pick now.)

### Mage additions (7 → 9), reinforce "burst but can't sustain" — NO resource restore
Hard rule: neither new card restores mana (avoids the Forethought/Recharge abuse we just removed).
- **Ember** (slot 9): very cheap Focus-builder / filler nuke. Mages currently lack a *cheap* spam
  option (magic_bolt dumps up to 60 mana). Low fixed cost, low damage, +1 Focus. Lets a
  low-mana mage keep *doing something* without healing — extends the "sustain" phase slightly but
  capped so it can't out-DPS the real nukes.
- **Frost Nova** (slot 6): control/defense. Reduces enemy accuracy AND applies a short
  action-slow (chance to skip), giving mages a survival lever that is NOT healing. Fits the glass
  cannon: buys time, doesn't refill the tank.

### Trickster
Already 9 and well-differentiated. No structural change. Optional micro-polish only.

## Balance / abuse guards (must verify on the sim)
- war_cry re-role must NOT let Momentum → instant devastate spam. Cap the +2, keep devastate's
  ≥1 gate, and confirm Momentum DR (5%/stack) + 85% mitigation floor still bound survivability.
- Ember must sit BELOW magic_bolt on damage-per-mana so it's a filler, not the optimal spam.
- Frost Nova control must share the cc_resistance / consec_stun falloff so it can't perma-lock.
- No new card restores a resource. No new turn-skip.
- Re-baseline all 3 classes in `real_combat_sim.gd` (trash / elite / boss, under- and well-geared)
  after changes; keep the tight band from #55 (under-geared L200 boss: War/Mag/Trk within ~10%).

## Per-subclass variation (the optional 3rd ask) — PHASE 2
9 archetype cards × 3 subclasses each (Fighter/Barbarian/Paladin, Wizard/Sorcerer/Sage,
Thief/Ranger/Ninja). Recommend deferring: land the equalized 9-card baseline first, then give
each subclass ONE swapped card (e.g., Paladin swaps rally→a group-ward; Barbarian swaps
fortify→a rage-lifesteal; Ninja swaps pickpocket→a shadow-clone). Big surface area; do it as a
follow-up slice once the baseline is proven on the sim.

## Rollout
1. Warrior war_cry re-role (smallest, isolated) → sim-verify.
2. Mage +2 cards (Ember, Frost Nova) → sim-verify Mage sustain/burst band.
3. Full 3-class re-baseline pass.
4. (Phase 2) per-subclass single-card swaps.

## STATUS — IMPLEMENTED (local, UNRELEASED) 2026-08-27
Decision (user): target **9 cards each** (least destructive — don't delete the two good
9-rosters, lift Mage to parity). Per-subclass = Phase 2. Chosen Mage pair = **Frost Nova +
Overload** (not Ember — Overload reinforces "can't sustain" harder than a cheap filler would).

- **Warrior war_cry → tempo/intimidate** (combat_manager.gd ~4181): +1 bonus Momentum (net +2
  with the shared build) + `enemy_distracted` chill (−25%, capped 40%). No longer writes the
  `damage` slot → Berserk conflict gone. Removed from DURATION_CAPABLE_ABILITIES. Sim: Warrior
  stays in-band (L200 boss under-geared 87%, was ~84%).
- **Mage Frost Nova** (control): chip frost dmg (30×INT, below Blast) + one-attack accuracy chill
  + Focus +1. In VARIABLE_COST_TABLE (mana, ceiling 24 / 5%). Distinct from Paralyze (soft vs hard).
- **Mage Overload** (glass-cannon burst): costs **20% max HP** (not mana), grants a strong `damage`
  buff (+120% base, rank-scaled) to the next spell. Blocked below 25% HP → no loop/suicide. MAX buff
  semantics → does NOT stack over Haste. Excluded from Focus building.
- NOTE: `enemy_distracted` is CONSUMED after one monster attack (combat_manager.gd:5743), so both the
  War Cry intimidate and Frost Nova chill affect the enemy's NEXT attack only — same as Distract.
  Wording corrected to match.
- Sim: functional check passes (Overload −20% HP → +96% buff at rank 0, blocked at 10% HP; Frost Nova
  dmg + Focus). Mage balance unchanged (L200 boss under-geared 84%). Files: combat_manager.gd,
  character.gd, client/client.gd, tools/combat_simulator/real_combat_sim.gd (added mage rotation +
  `_verify_new_mage_cards`).
- **Needs a FULL client+server release** to reach players (new cards need client display + server
  logic + the shared character.gd deck-pool change). Not yet released/committed at time of writing.
- Trickster: unchanged (already 9 + differentiated).
