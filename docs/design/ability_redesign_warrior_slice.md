# Ability Redesign — Warrior Vertical Slice (design for review)

Status: **DESIGN, not built.** Prototype on Warrior first; if it lands, extend to Mage + Trickster.

## The three problems this solves
1. **Costs dump the whole bar** — cards auto-spend `min(current, ceiling)`, no player input.
2. **Shallow choices** — players spam damage; buffs / odd abilities go unused.
3. **Leveling an ability isn't exciting** — mastery just adds a quiet damage %.

## Two core ideas

### A. Tiered abilities (start cheap → upgrade via mastery)
- Each ability has an internal **tier 1→3**. You start at **T1: cheap + weak**. Higher tiers cost more, hit harder, and gain a rider.
- The **mastery rank-up popup** gains a 3rd option — **"Upgrade Tier"** — alongside the existing *Stronger Effect* and *Imprint*. So ranking an ability up is a real choice: raw power vs. tier upgrade vs. companion imprint.
- The card **name + the mastery fill visual** already show your progress toward that next tier — the fill we just shipped becomes "progress to your next upgrade."
- Kills deck bloat: you carry ONE card per role; it grows with you (no separate "Jab" and "Devastate" cluttering the deck).

### B. Momentum — the "choices that matter" engine (Warrior flavor)
- A small combat meter **Momentum 0→3**. **Strikes BUILD it; Finishers SPEND it.**
- This creates a per-turn rhythm: *build up, then unleash* — and it makes cheap attacks meaningful (they're not "filler," they're setup). Each class gets its own flavor later (Mage = Focus/overload, Trickster = Combo points).

## Consolidated Warrior kit (9 abilities → 5 roles)

| Role | Card (T1 → T3) | Cost | Momentum | Notes |
|------|----------------|------|----------|-------|
| **Striker** | Jab → Power Strike → Devastate | low | **+1** (T3 +2) | Reliable single-target; your bread-and-butter builder |
| **Sweep** (AoE) | Sweep → Cleave → Whirlwind | mid | +1 | Hits the whole flock — shines vs packs |
| **Finisher** | Crushing Blow → Sunder → Execute | mid | **spends all** | Damage scales with Momentum spent; T2+ adds stun/armor-break at high Momentum |
| **Guard** | Brace → Iron Skin → Aegis | low | — | Cuts the next incoming hit; T2 retaliates, T3 shields the party. Rewards reading a telegraphed big hit |
| **Rally** (buff, tension) | War Cry → Berserk | mid | — | War Cry = +dmg for N turns; Berserk = bigger +dmg but you also take more damage. Worth a turn only in longer fights → situational |

Retired/merged: fortify (into Guard), rally-heal (into War Cry or companion), shield_bash stun (into Finisher's high-Momentum rider).

## Why this fixes the three problems
1. **Costs:** T1 cards are cheap → castable every turn; you spend up as your pool grows. No more one-and-done.
2. **Choices:** every turn is *build Momentum vs. spend it*, *attack vs. Guard the incoming hit*, *is Berserk's risk worth it here?* — real decisions, not "pick highest damage."
3. **Leveling:** rank-up now offers a visible **tier upgrade** (new name, new rider) — exciting, and the card-fill already telegraphs it.

## Open design questions (for the user)
- **Momentum**: good as the Warrior engine? Show it as pips on the player card?
- **Finisher scaling**: linear with Momentum, or thresholds (1 pip = small, 3 pips = stun + big)?
- **Roster size**: 5 roles feel right, or trim to 4 (drop the AoE into the Striker's high tier)?
- **Tier count**: 3 tiers per ability, or 2?
- **Migration**: existing characters' current abilities map onto the new roles + inherit a tier from their mastery rank.

## Build order (once approved)
1. Data model: per-ability `tier`, Momentum meter on combat state.
2. Rank-up popup: add "Upgrade Tier" option.
3. Warrior kit values + Momentum build/spend hooks in `combat_manager`.
4. Card UI: tier name + Momentum pips.
5. Playtest Warrior → then Mage (Focus) + Trickster (Combo) with the same framework.
