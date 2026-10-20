# Economy design - DRAFT 2026-10-20 (Wave 1, step 1)

One document for the four items that are the same question - *what do players spend on, and where does it come from*:
the economy half of companion item 14 S5 (Role Swap price, companion upkeep), **Real sinks for excess eggs and
companions**, **The Valor economy, realm-wide**, and **The world consumes material surplus**. Gold prices (Temper, Role
Swap) are first guesses and are set HERE, once.

Status: facts and findings are from the code as of v0.9.846. **Nothing in this file was measured against live play** -
there is no per-hour income data - so every number marked (G) is a guess to be replaced by the telemetry in section 6.
Sections 4-5 end in questions only the owner can answer.

---

## 1. The two currencies (as built)

| | **Valor** | **Gold** |
|---|---|---|
| Belongs to | the ACCOUNT (survives death) | one CHARACTER (mostly dies with it; a random 10-50% can be recovered from the corpse) |
| Spent on | market, healer, repairs/recharge, Sanctuary, guard, titles, charters, cartographer, wits training, crafting fees | gear POWER: Temper (blacksmith), Rework (enchanter), Role Swap (stable), affix reroll |
| Rule (owner 2026-10-14) | "market / services" | "gear power" |

That split is a good one and this document keeps it. Everything below is about the *rates*, not the split.

## 2. Gold: faucet and sink, at the shipped numbers (`shared/gold_economy.gd`)

Faucets: kill `5 + 1.5 x monster level` (boss x4, +50% per empowered modifier); quest `20 + 6 x level`; floor gold
`8 + 3 x loot level`; dungeon clear `120 x tier x (1 + 0.25 x (floors-1))`; salvage `level x (0.5..16 by rarity)`; gems 1,000
each (owner-fixed).
Sinks: Temper tier `10 x item level x 1.8^(tier-1)`, 5 tiers per item; Rework `4 x level x (1 + 0.6 x reworks)`; Role Swap
`1,000 x tier`; affix reroll (gold cost per call).

Computed from those formulas (no play data):

| level | gold / kill | quest | Temper tier 1 | all 5 tiers on ONE item | kills to afford those 5 | Role Swap tier 6 = kills |
|---|---|---|---|---|---|---|
| 10 | 20 | 80 | 100 | 2,237 | 112 | 300 |
| 50 | 80 | 320 | 500 | 11,185 | 140 | 75 |
| 100 | 155 | 620 | 1,000 | 22,370 | 144 | 39 |
| 500 | 755 | 3,020 | 5,000 | 111,848 | 148 | 8 |

**Finding G1 - Temper is a constant ~6 kills a tier at every level.** Faucet and sink both scale with level, so the price
never matters more or less as you progress. That is a defensible design (gold always buys the same slice of effort), but
it means gold can never become scarce or abundant - it is a flat tax on playing, and a character who has tempered what
it wears has NOTHING to spend gold on until it changes gear (which resets the item's tiers). Decide whether that is the
intent (section 5, Q1).
**Finding G2 - Role Swap is flat 1,000/tier, so it scales away.** 300 kills at level 10, 8 kills at level 500. Tier and
character level are correlated, so it may be fine in practice, but nothing ties them. Either price it in kills (scale with
level like Temper) or accept that it is a mid-game sink only.
**Finding G3 - there is no gold sink for companions at all.** Eggs and spare companions have the fusions (4 modes + Role
Swap) and the kennel, but the only ones that cost anything are Role Swap (gold) and the Healer NPC (valor, for resting
the team). That is why "excess eggs" feels unsinkable: the sinks are free or optional.

## 3. Valor: what the code actually does

**Sources** (mint = creates valor): quest turn-ins (`3.5 x level` per task + base, tier and threat multipliers); combat
loot slots; dungeon floor coins / jewels / trinkets / the Ancient Dragon hoard / final chest; treasure chests; floor items;
fishing scratch-off; party quest sync; starting valor from Sanctuary upgrades; a one-off conversion of retired character
gold on login. **Transfers** (no net mint): market sales and orders, merchant seller bonus, duel stakes, PvP sacks,
bounties, title tax/gift/vault. **Refunds**: bounty cancel, market cancel, summon refund.
**Sinks**: blacksmith repair-all (encounter cost), healer cure/cleanse, merchant recharge, trading-post recharge (cost/10),
home stones (price, capped per type), Cartographer locate (15), guard hire (50 + food), wits training (`5 + 10 x bonus`),
crafting commission fees and listing pulls, prefab post charters, title abilities, shrine pilgrimage, the merchant gamble
(net zero in expectation unless the odds are not fair - unaudited).

**Finding V1 (FIXED this session) - two sinks were written as `add_valor(-price)`**: home stones and guard hire.
`add_valor` also bumps `total_valor_earned`, so each purchase REDUCED the "earned" statistic, and `add_valor` has no
overdraft check. Both now use `spend_valor`. (Both were guarded by an earlier balance check, so no account went negative.)
**Finding V2 - `total_valor_earned` cannot tell a mint from a transfer.** Market sales, duel winnings and bounty
payouts all go through `add_valor`, so the one statistic that could answer "how much valor entered the world" counts
players paying each other. **Prerequisite for any valor tuning: a ledger** - every valor change logged with a `kind`
(mint / sink / transfer / refund) and a `reason`, so the faucets-per-hour and sinks-per-hour the old plan asked for are a
query instead of a code read. Cost: one function wrapping the two persistence calls plus ~70 call-site labels; no
behaviour change.
**Finding V3 - the interim anchor.** `QUEST_VALOR_PER_LEVEL := 3.5` was calibrated against the sinks that existed
(cheapest Sanctuary upgrade 250, ladder to 8,000), which the owner then called unbalanced. It stays until V2's ledger gives
a measured income per hour. The owner's account sat at 62.4K valor at level 10: faucets outrun sinks for an
established player, so **do not raise prices first** (inflating against a 62K balance changes nothing for them and prices a
new player out).

## 4. The design (proposed; all numbers (G))

### 4.1 Principles - taken from owner statements, not invented
1. **Gold = gear power, valor = services and the market** (kept).
2. **Tune to a stated target, never to each other**: a price is "N minutes of play", not "a bit more than the last one".
3. **"Most of the economy should come from the players"** (owner 2026-09-18): NPC stock should be made from player surplus,
   not generated from nothing.
4. **Every sink needs a reason to be used.** A sink nobody uses is either mispriced or unreachable.
5. **Permadeath stays**: gold is run-bound and loses 50-90% at death by design; do not add sinks that assume gold persists.

### 4.2 Targets (a place to start the argument)
| Item | Target | Why |
|---|---|---|
| Temper tier 1 | ~5 kills (today 4-7: keep) | cheap enough to feel; already constant |
| Temper tiers 4-5 | 25-40 kills each (today ~36 / ~66 at every level) | the last tiers should feel like a goal; tier 5 is steeper than that |
| Role Swap | ~100 kills of the player's CURRENT level, any tier | so it is a real decision at every level |
| Egg / companion sinks | 1 per 30 minutes of play, optional | see 4.3 |

### 4.3 Companion and egg sinks (one proposal, decide together with item 11(c) rolled stats)
Companions currently cost nothing to keep and nothing to dispose of. Proposed, cheapest first:
1. **Feed / train**: a spare companion or egg can be consumed to grant a companion XP or a small stat roll (rolls are
   11(c)). A *use* for the surplus, no new currency. This is the "sink with a reason".
2. **Role Swap priced in kills** (G2) so it stays a decision.
3. **No upkeep.** A daily/per-fight fee on a team punishes the team feature that just shipped and the rest recovery is
   already free; the Healer NPC valor cost for reviving the team is the existing soft sink. (Q2)
4. **Egg market stays player-to-player.** Do NOT add an NPC egg buyer; it would be a faucet.

### 4.4 Material surplus -> area gear ("the world consumes surplus")
Keep the owner's design: per-region surplus ABOVE a per-material threshold converts into area-appropriate gear listed by
the post, carried by couriers. Decisions proposed (all (G)): it is a **relief valve only** (converts only above the
threshold, never the main supply); the NPC **pays the original listers** a floor price (a price floor for materials, a
bigger lever - Q3); it needs **V2's ledger first** because it moves valor and must not become a faucet. Build after the
ledger and after the living-world work it pairs with (Wave 3).

### 4.5 Valor
Order of work: (1) ledger (V2); (2) read a week of live income and spend; (3) set Sanctuary / service prices against
"hours of play per upgrade" (target stated by the owner, Q4); (4) only then change `QUEST_VALOR_PER_LEVEL`. Audit the
merchant gamble's odds for a hidden faucet.

## 5. Questions only the owner can answer
- **Q1.** Is "gold is a flat ~6-kills-a-tier tax and runs out of uses once your kit is tempered" what you want, or should
  gold keep a sink at high investment (more tiers, a second tier-set, or enchant-style rerolls)?
- **Q2.** Companion upkeep: none (my proposal), or a real recurring cost to make a large team a trade-off?
- **Q3.** Should the surplus-converting NPC pay listers a floor price, or only absorb the leftover for free?
- **Q4.** How many hours of play should one Sanctuary upgrade cost - for a first upgrade and for the top of the ladder?

## 6. What I can build now without waiting on any answer
1. The valor **ledger** (kind + reason on every change; no behaviour change; makes sections 3 and 4.5 measurable).
2. Gold telemetry: log gold in/out per reason per character, so kills-per-tier is measured, not computed.
3. A probe that every valor change goes through the ledger, so a new sink cannot bypass it (the V1 shape).

Not built yet; these are the next step once the owner has read this.
