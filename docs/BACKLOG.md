# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Keep it current: when work finishes, move it to *Recently
shipped*; when a new direction is agreed, add it in the position its dependencies allow.

Ordering rule: **each item is placed so its inputs are settled first** — measurement before
tuning, data model before UI, combat numbers before anything sized against them. Working out of
order is what forces revisits.

> Detailed design and history live in `docs/design/` and in the assistant project memory.
> This file is the ordering and the status.

---

## In progress

**Item 6 — the progression & difficulty curve — is the active arc**, with 6b (companion power)
as its twin. Items 1-5 are done. The simulator (5) was finished on 2026-09-02 and immediately
produced the finding that defines 6: swept across the real level range (L1 → L10000), the
difficulty curve **does not hold** — it humps around L50-500 and then gets *easier* again.

Before tuning anything, note what 5 proved about trusting measurements here: four separate
modelling bugs in the sim each produced confident, wrong balance conclusions (six classes never
simulated; a tier-2 Orc used as the enemy at every level; an invented companion; a gear model
fitted to naked test accounts). **Two conclusions were reversed by verification alone.** Check
what the sim is actually modelling before believing any number it prints.

### 1. Party mechanics — server pass ✅ COMPLETE (shipped v0.9.740)
- [x] Leader **rotation** after each combat (default) + alternate **control modes** (fixed / rotate)
      — `Lead: Rotate / Lead: Fixed` toggle in the Party menu. Rotation walks a stable
      `rotation_order`, not `party.members` (which `_transfer_leadership` reorders new-leader-first,
      so rotating over it would ping-pong between two players). Verified fair for 3 members
- [x] Reward policy: **DUPLICATE** — gathering materials and job XP are copied in full to every
      member. Wrapping `_add_gathering_reward` covers every gathering path at once instead of
      changing ten call sites. **Crafting shares XP only** — duplicating the crafted item would
      mint N items from one set of materials
- [x] Rotation survives membership **churn** — leavers are dropped from the order, joiners are
      added, and rotation skips anyone dead/offline/departed. Verified: leavers never lead again,
      joiners get turns, no stale ids
- [x] **Leadership transfer verified** — with 3 members, the leader dying hands leadership to a
      survivor instead of disbanding. Needed a scenario where ONLY the leader is at 1 HP: in a
      lethal zone the others die first, the party drops to two, and it disbands instead
- [x] **Party max size is 5** (leader + four). The constant counts the leader, so the old 4 meant
      leader + 3. Raising it exposed `MAX_CONNECTIONS_PER_IP = 3`, which silently dropped the
      4th/5th local test clients — loopback is now exempt in DEV builds only
- [x] Live-tested with 3 clients: rotation, control modes, duplicated rewards, leadership
      transfer, follower control and post formation all confirmed on screen

- [x] **Follower control rule** — out in the world one player leads and the rest follow, so a
      follower cannot move, hunt, rest or gather; **inside a post everyone acts independently**
      (shopping, crafting, quests, walking between stations). Crafting needed no gate — it
      already requires being at a post or station
- [x] **Post formation** — inside a post nobody is dragged along and everyone moves freely; the
      party may only leave TOGETHER: the leader cannot step out while anyone is still wandering
      the post, and a follower cannot step out alone. Party members can share a tile, so
      gathering up to leave is always possible

*Rotation and rewards ship together: both edit party state and `_end_party_combat_all`, so
splitting them means editing and re-testing the same code twice.*

---

## Next

### 2. Party UI  ← targeting + pacing shipped v0.9.740; invite window + watch-a-minigame remain

**Decided (user 2026-09-01):** targets include **companions** (so companion-affecting loot can
be added later without redoing the picker). **All buffs** are teammate-targetable EXCEPT
Vanish / Cloak / Teleport (escape+stealth tied to the caster's own presence — on an ally they
would pull them out of the fight) and Overload (burns caster HP to boost *the caster's* next
spells). Analyze stays self-only: it reveals monster info and the log is already shared.
Quick self-cast: the picker opens with **Yourself pre-selected**, so pressing the ability key
again self-casts — no new binding — plus a visible Self button.

- [x] Server: separate WHO CASTS from WHO RECEIVES. Items take a `target`; extended to
      `"pid:N"` / `"comp:N"` — a teammate or their companion. `process_use_item` gained a
      `recipient` (effects) while inventory + cost stay on the caster
- [x] Server: same for buff abilities. Done as a **before/after diff**, not a per-ability
      table: the ability runs unchanged on the caster (their cost, their stats, their
      rank-ups) and only the RESULT is moved — Character buffs, view-side state
      (Forcefield's shield, Arcane Surge) and Rally's heal. A new buff becomes
      redirectable just by being added to `PARTY_TARGETABLE_BUFFS`.
      Excluded: `war_cry` (debuffs the MONSTER now, not a self-buff), `overload`,
      `vanish`/`cloak`/`teleport`, `analyze`
- [x] Client: target picker over the party cards, Yourself first and pre-selected. One
      picker serves items (companions listed) and buffs (players only — the server refuses
      a companion target for an ability). Quick self-cast = `[1]`, the leading entry, or a
      **Cast/Use on Self** button on the action bar for click-only players
- [x] Found + fixed on the way: **Arcane Surge (Haste) was silently dropped in co-op** — the
      double-cast chance was seeded nowhere in the member view and synced back nowhere, so a
      mage paid for it every round and never got it. Also collapsed the ability-alias map
      from two inline copies into one `ABILITY_ALIASES` table
- [x] **Co-op playback pacing** (found during the 3-client pass). Three separate faults, all
      reading as "the fight froze":
      1. A co-op round is ~28 beats against ~8 solo (one head + body per member, plus one
         monster action per member). At the solo per-beat delay that is a **12.6-second**
         round. Rounds now play to a total budget (~6s), recomputed each beat so the round
         starts brisk and eases to full speed for the killing blow. Solo unchanged
      2. Playback could fall behind **without limit** — the server resolves the next round as
         soon as everyone clicks, so the queue grew a whole round each time. The monster's
         death, the victory card and the end-state settle ALL run only when the queue empties,
         so none ever fired. Now: while a newer round waits, drain at frame rate until caught
         up. Input is deliberately NOT blocked (that would make everyone wait out the
         animation and let one slow client hold up the party — user's call 2026-09-01)
      3. **Continue destroyed the victory card** — `acknowledge_continue` nulls the pending
         payload, so an impatient player threw away the card they were pressing toward. It now
         means "hurry up" while the round plays, "wait" while the reveal timer is in flight,
         and "dismiss" only once the card is up
- [x] Also fixed: co-op start never cleared `pending_continue` (solo always has), leaving a dead
      Continue button over the next fight; and `get_meta(name, null)` is not a safe read in
      Godot — a null default reads as *no* default and pushes an error (54 per fight from
      `_set_cell_dim`, which buried the real signal while diagnosing the above)
- Regression: `tools/combat_simulator/coop_buff_target_test.gd` (15 assertions), scenario
  `party_support`; `tools/test_setup/run.py` now captures per-process stdout to
  `tools/test_setup/logs/` (Godot's `user://` log does not capture `print()`)
- [ ] Quests-style **invite/accept window** (the current chat/action-bar flow is clunky)
- [ ] **Watch a teammate's minigame.** Gathering (scratch-off) and crafting (reveal panel) are
      single-player panels driven by a payload sent to the actor alone; the rest of the party
      only sees the result line. Since rewards now DUPLICATE, everyone is receiving what is being
      revealed, so watching it is meaningful. Needs the server to broadcast the payload plus each
      reveal to party members, and a read-only mode on both panels

### 3. Identity & theming ✅ COMPLETE — `docs/design/setting_bible.md`
**Agreed 2026-09-01.** A *phantom* is something the land has kept and pushed back up. It keeps
**places** (dungeons surface, take root, and bleed monsters toward the nearest holdout) and it
keeps **people** (delvers don't come back all the way). The two are one phenomenon: **going
into a phantom place is what makes you one** — permadeath is the bill, not bad luck. The only
thing that moves cleanly between lives is what you brought out **alive**, which is why
companions are the emotional spine: they outlive their delvers.

- [x] Name tied to the world — "Phantom" and "Badlands" both carry meaning, and every line of
      it is a reading of a mechanic the game already runs (dungeon spawn timer, threat cones,
      post-anchored levels, permadeath, Sanctuary, kennel, corpses, fusion, border tier)
- [x] Companions in the fiction: eggs are the one living thing a dead place produces
- [x] Dungeons in the fiction: why they appear, why they threaten posts, why they return
- [x] Setting bible written, with a voice guide (use/avoid word lists) so the Atlas, quests,
      NPC flavour and website can be written against one register
- [ ] **Full in-game copy pass** — tutorial intro, help framing, dungeon entry text,
      egg/companion flavour, post + NPC descriptions rewritten against the bible. **Wanted
      (user 2026-09-01), deliberately deferred**: it touches a large number of player-facing
      strings, and doing it before the dungeon arc (8-12) means rewriting dungeon text twice.
      Do the non-dungeon surfaces any time; save dungeon copy for 11

### 4. Website refresh ✅ COMPLETE (live at phantombadlands.com)
- [x] **Accuracy pass.** Fixed real errors, not just tone: the FAQ said **Windows only** when
      Linux has shipped for months; party size said 4 (now 5, with co-op explained); combat was
      described as ability slots rather than a deck. Added the systems that were missing
      entirely — Paths, uniques and sets, rank-ups, the card market, the Atlas, Apex Frontier —
      and gave **equipment and decks** their own coverage, which they had none of
- [x] Rewritten around the setting rather than a spec sheet, and the **name is now explained in
      the copy** (wording chosen by the user from drafted options). The hero carries the threat,
      and a separate line carries the lure: gear, cards found nowhere else, and *eggs*
- [x] **Real in-game screenshots** replace the hand-written mock-ups: combat (monster ASCII,
      battler sprite, companion, card hand), a companion art montage of eight types and
      variants, the deck screen, and a fully equipped inventory
- [x] Screenshots on the **Features page too**, not just the landing page — it was still a wall
      of bullet lists, which was the original "less boring" complaint. Four figures now break up
      the combat, party, companion and progression sections
- [x] Built `tools/test_setup/shots.py` + a dev-only `--shots` client mode so these can be
      **regenerated** rather than re-shot by hand — the presentation pass (11) will invalidate
      every one of them
- [ ] **Dungeon pages + dungeon screenshots deliberately deferred to 11** (user 2026-09-02):
      the dungeon view is mid-rework, so anything shot now is out of date on arrival. The
      landing page carries a visible placeholder in the meantime
- [ ] Follow-ups, none blocking: a **party co-op** screenshot for the "Fighting together"
      section (needs 2-3 clients, so the single-client capture harness can't do it yet);
      gathering / crafting / market shots; and carrying the Keeper's voice further into
      Features and the FAQ (one line each today)

### 5. Simulator upgrade ✅ COMPLETE (2026-09-02) — **unblocks all balance work**
- [x] Teach the sim to spend **abilities and resources**. It already drove three archetypes;
      the finding was worse than the line suggested — `run_fight` dispatched the per-turn AI by
      exact class string, so **six of the nine classes were never simulated at all**. Sorcerer,
      Sage, Ranger, Ninja (and Barbarian/Paladin partially) were handed the Warrior AI holding
      mage/trickster cards, matched nothing, and auto-attacked: 0 casts/turn and a 0% win rate
      that read as a balance result. The three resource helpers re-derived the archetype the
      same way, so a Sorcerer's spend was measured against its **stamina** bar. All four now
      ask `Character.get_class_path()` — the one place the game itself decides
- [x] Calibrate `make_char` against **real saved characters**. Done, but the important part was
      *classifying the cohort first*: 5 of the 11 local characters are **naked test accounts**
      (0 equipped slots) and 1 is an admin-boosted all-epic build. Fitting to them pointed the
      model the wrong way entirely (it wanted gear 10 levels *below* character level; the
      geared characters want it at ~0.85x). Only characters with 5+ slots calibrate the
      "average" tier now
- [x] Three further model errors found on the way, each fixed at the cause:
      **the enemy was hardcoded to "Orc" at every level** (a tier-2 monster, so past ~L500 the
      sim measured a stretched low-tier creature instead of real content — this alone produced
      a false "the game trivializes at high level" result); **the companion was invented**
      (a hand-written bonus block 2-4x anything the game can produce — now drawn from
      `COMPANION_DATA`); and the gear model forced one **uniform rarity** across all seven
      slots with a **fixed level subtraction**, which is the wrong *shape* — real item level
      tracks character level proportionally and often sits *above* it
- [x] Audits are now selectable (`-- classes races calibrate gear_solve progression companion`,
      `-- n=200` for sample size) instead of by editing `_init`
- [ ] **Known limitation, carried into 6:** the gear model has a **slope error** — hot at L6
      (1.57x attack), cold at L45 (0.35x). One item-level ratio cannot fit both ends, and there
      are only **2 genuinely geared real characters** to fit against. The audit prints a SLOPE
      WARNING rather than hiding it in a median. High-level balance numbers inherit this
      uncertainty until more real characters exist

### 6. Progression & difficulty curve — **the central balance goal** (user direction 2026-09-02)
*"Balance must hold throughout the game and not trivialize any of it."* The intended loop:
**grind gear + companions → level companions → reach bigger challenges → better gear and
companions.* Progression should get **harder**, never easier. The user is explicitly open to
changing **itemization, gear, companion levelling and companion power** to hit this.

**Measured 2026-09-02 (`-- progression`, L1 → L10000, the real max):** the curve does *not*
hold. It is not a smooth ramp — it is a **hump**:
- Difficulty peaks around **L50–L500** (same-level boss: Fighter 37% @L50, 32% @L100, 30% @L500;
  Wizard 17-32% across that band), then **gets easier again** past L1000 (Fighter 65-82%,
  Thief 95-97%). The late game is currently *safer* than the mid game
- **Wizard is the worst class almost everywhere past L100** and fights are absurdly long —
  **155 turns** at a L250 elite, 91 at L500. Turn count itself is a balance failure
- **Thief massively outclasses the other two at high level** (L1000 boss: Thief 95% vs Fighter
  65% / Wizard 60%) — the class gap widens with progression instead of closing
- The curve is **jagged**, not monotonic (Fighter boss: 37→32→55→30→65→77% across L50-2500),
  which points at monster-selection variance between tiers rather than a designed ramp

**Measured `-- ability_hp`** — one cast's damage as % of a same-level NORMAL monster's bar
(>=100% one-shots trash). This is the unit balance should be tuned in; raw damage is
meaningless when monster HP scales on a different curve:

| Ability | L1 | L5 | L10 | L50 | L100 | L500 | L1000 | L10000 |
|---------|----|----|-----|-----|------|------|-------|--------|
| power_strike | 263% | 102% | 67% | 35% | 23% | 10% | 42% | 45% |
| magic_bolt | 1203% | 385% | 210% | 73% | 43% | 84% | 238% | 365% |
| blast | 1009% | 341% | 142% | 25% | 14% | 8% | 14% | 20% |
| exploit (%-HP) | 10% | 10% | 11% | 16% | 18% | 17% | 20% | 23% |

- **The early game is a formality.** At L1 every damage card is 2.6x-35x overkill on a normal
  monster; Magic Bolt is **12x**. This is the user's "Magic Bolt is extremely powerful early
  game" observation, confirmed and quantified
- **It does fall off — and then comes back.** Magic Bolt bottoms at 43% around L100 (can no
  longer one-shot) and recovers to 238-365% past L1000. The U matches the difficulty hump
  exactly: monster HP outgrows player damage to ~L500, then player damage outgrows it
- **Blast never recovers** (down to 8-14%) — the mage's *sustain* card dies while its burst
  card returns, which is why Wizard fights run 40-155 turns in the mid-late game
- **Exploit is the only ability with a flat, rising curve — because it is %-max-HP.** Every
  other ability deals absolute damage into a bar that scales on a different curve. That single
  structural difference is the likeliest driver of Thief pulling away at high level, and it is
  the *shape* the balance model should learn from

**Encounter level vs fight math — a gap the sim deliberately does not model** (user question
2026-09-02: "is there a formula weakening monsters near the starter post?"). Yes, two:
1. `world_system.get_post_anchored_level()` — posts pull the encounter level **down** near them
   and *by construction can never raise it* ("posts are settlements, not difficulty elevators").
   The starter post sits at origin where the radial curve is already lowest
2. `monster_database._calculate_tiered_stat_scale()` — a monster spawning below its natural base
   level has its stats collapse linearly, so a clamped high-tier monster is a runt rather than an
   apex predator wearing a low level tag (the v0.9.481 fix for the 350-HP "Lv 1" Chimaera)

The sim models neither: it fights **same-level, tier-natural** monsters, which is the correct
unit for tuning abilities against each other. The consequence for the sweeps above is that they
are an **upper bound on difficulty** — real players can meet monsters at or below their level, so
the game is at least as easy as measured, never harder.

**The structural point is bigger than either formula:** `get_area_level_range` is a pure function
of `(x, y)` and never reads the player's level. Difficulty is chosen by **where you stand**, not
by how strong you are — so "progression gets harder" is entirely opt-in and nothing enforces it.
Measured (`-- underlevel`): against a monster at 25% of their level, every class at every level
wins **100% of fights at 96-100% health**. Not an XP exploit (the downlevel penalty floors at 40%
and a weak monster's base XP is small anyway) — but it means the pressure to move outward has to
come from the **reward gradient**, since the difficulty model will never apply it.

- [x] **Player-post safe pockets now scale with tier** (user approved 2026-09-02).
      **DO NOT DEPLOY before item 12b exists** — spawn-at-post already ships, so this change
      strands a fresh level-1 character outside a frontier post with no way to survive or gear
      up. Safe to sit in the tree today only because no player has built a post yet. NPC trading
      posts already scaled — their anchor is `_distance_to_level(post's own distance)` and post
      tier comes from `_tier_from_distance`, so a frontier post already anchors high. The hole
      was **player-built posts**: every one is created with `DEFAULT_PLAYER_POST_TIER = 1` and
      nothing ever assigns a distance-based tier, so the suppression floor in
      `_compute_effective_post_tier` was **1 everywhere**. A player could raise a post deep in
      the frontier, buy guards, and suppress a level-5000 zone to level ~1-2 permanently. The
      floor is now `max(post tier, wilderness_tier - MAX_PLAYER_POST_SUPPRESSION)` with the cap
      at 2 tiers, so a pocket is easier than its surroundings but never starter-grade. Guard
      investment keeps the same range; near the core (wilderness tier 1-3) the floor stays 1 and
      the early game is untouched
- [ ] **Decide whether progression pressure is a reward-gradient problem, not a monster-stat
      problem.** Neither formula should simply be removed — the stat downscale fixes a real bug,
      and safe settlements are good design. The lever is making the gear and companions players
      need obtainable only further out

**Root cause of the late-game slide, found 2026-09-02 by auditing the monster tables:**
`get_monster_base_stats` hand-authors `base_level` / `base_hp` / `base_strength` per monster
type, and the ratios **de-scale badly** as tiers rise:

| Monster | base Lv | HP/lvl | STR/lvl |
|---------|---------|--------|---------|
| Goblin (T1) | 2 | 7.50 | **4.00** |
| Ogre (T3) | 18 | 5.56 | 1.39 |
| Ancient Dragon (T5) | 70 | 7.14 | 0.86 |
| Hydra (T7) | 350 | 4.29 | 0.31 |
| Avatar of Chaos (T9) | 6000 | 2.50 | **0.07** |

HP per level falls ~3x from T1 to T9; **strength per level falls ~57x**. Meanwhile player
damage grows roughly with L² (`get_total_attack()` × `(1 + 0.02·STR)`, both terms linear in
level).

**CORRECTION (same day, after the user challenged it).** These base ratios do NOT by themselves
explain the late-game slide, and the first reading of them — that a scaled-up low-tier monster
might out-damage a native high-tier one — was **wrong**. Checking what the generator actually
produces reverses it: at L5000 a scaled Goblin has 15,000 HP against a Void Walker's 677,173,
and high-tier monsters carry far richer ability sets (multi_strike, regeneration, armored,
enrage, ethereal, mana_drain) that the base table does not show. Full numbers under 12b. Base
per-level ratios are a **misleading metric read alone** — always check the generated monster.

What survives is still decision-relevant: the tables have no consistent relationship to level
(hand-authored `base_level` per type, a tiered percentage scale, an HP cap that low-tier monsters
hit when scaled up, and a linear downscale for monsters generated below their own base level).
That is why the first task is a **target curve** and why the reference-player model below is the
leading fix — not because high-tier monsters are individually weak.

- [x] **MEASURED 2026-09-02 — this is the cause of the late-game slide AND the jaggedness.**
      `select_monster_type` picks a TIER from the level, then a monster from that tier. But a
      tier's level BAND and the base levels of the monsters inside it **do not line up**:

      | Tier | monster base levels | level band it covers |
      |------|--------------------|----------------------|
      | T6 | 150–400 | ~L150–1000 |
      | T7 | 700–1500 | ~L1000–2500 |
      | T8 | 2500–4500 | ~L2500–5000 |
      | T9 | 6000–9500 | ~L7500–10000 |

      `scale_monster_to_level` scales **up** from base on a tiered percentage curve, but scales
      **down** on a bare **linear** ratio (`target/base`). So near the **start** of a band most
      picks sit *above* the target level and generate as downscaled **runts**, while near the
      **end** of the same band every pick is scaled up and generates at full strength.

      The result is a **sawtooth**, not a curve (`-- selection`, 400 picks/level):

      | Level | tier | runt% | median HP |
      |-------|------|-------|-----------|
      | L500 | 6 | 6% | 93,271 |
      | **L800** | **7** | **39%** | **46,777** ← halved while the player got stronger |
      | L1500 | 7 | 5% | 205,343 |
      | L2000 | 7 | 4% | 428,668 |
      | **L2500** | **8** | **38%** | **63,765** ← **6.7x collapse** at the band boundary |
      | L5000 | 8 | 7% | 411,141 |
      | **L7500** | **9** | **34%** | **192,057** ← halved again |
      | L10000 | 9 | 0% | 1,160,125 |

      Difficulty **collapses at every tier boundary** and climbs back to the end of the band.
      That is the late-game slide measured in the progression sweep, and it is a *selection*
      problem, not a monster-strength problem.

      It also produces enormous **same-level variance**: the HP spread between the weakest and
      strongest monster a player can meet at one level grows to **85x** (L2500: ~7.5k to ~656k).
      Two players at the same level in the same place can have completely different fights.

- [ ] **Do not fix this by re-authoring `base_level` values — that only moves the teeth.** As
      long as level→difficulty is routed through each monster's hand-authored base level and an
      asymmetric up/down scale, some band will always start with runts. The mapping has to stop
      going through base_level at all. **Same conclusion as the reference-player model above,
      reached from a completely different direction — which is the strongest argument yet for
      building it.** It also serves the Phantom (12b), which needs any species to scale by depth.
- [ ] Whatever replaces it must also **bound same-level variance** deliberately (a designed
      range, e.g. 2-3x, rather than today's emergent 85x)

- [ ] **Anchor monster stats to a reference player at the same level** rather than to
      hand-authored per-tier tables: `monster.hp = reference_damage_per_turn(L) × target_turns
      (tier)`, and similarly for its damage against reference mitigation. Difficulty becomes flat
      *by construction* and "gets harder with level" becomes an explicit knob instead of an
      emergent accident of 54 hand-written stat blocks. The sim now has the machinery to build
      that reference (`make_char` is calibrated; `-- ability_hp` measures output per level)

- [ ] Decide the target curve first (what *should* win% and danger look like at L10, L100,
      L1000, L10000?), then tune to it. Without a target the sweep has nothing to fail against
- [ ] Fix the **mid-game hump** and the **late-game slide** — the two ends of the same problem
- [ ] **Wizard** rework: worst win rate + longest fights past L100
- [ ] **Class gap widening with level** (Thief vs Fighter/Wizard at L1000+)
- [ ] **Magic Bolt flat curve** — ~21x per mana at L5 vs ~27x at L20 while monster HP scales far
      faster. Damage-per-mana has to scale on the same curve as monster HP
- [ ] Ability cost model / resource economy (costs flat while pools scale).
      **Measured 2026-09-01:** a level-20 Wizard's Forcefield (`cost_percent: 3`) has a NET
      cost of **zero** — the same turn's regen refills the spend before the player ever sees
      it, so a 310-point absorb shield is free every round. Reproduced in SOLO combat, so it
      is not co-op specific. Regen (~16%/turn) outrunning cost is the whole flaw in one case
- [ ] Anti-abuse items that **never landed**: Forethought and Recharge still exist, no mitigation
      cap, no stun DR. Related user direction: remove blue "skip the enemy turn / refund
      resources" utility cards
- [ ] Equipment vs race vs class, compared **against each other** rather than in isolation
      (`-- races` and `-- classes` now exist for this)
- [ ] **Gear acquisition must actually exist** at every level band — the loop depends on players
      having a real way to get better gear, not just on the gear existing in a table

### 6b. Companion power & levelling — **the emotional spine, currently thin**
*User 2026-09-02: "if companions don't get stronger and players have no way of improving them
it makes the crucial point of the game pointless."*

**Measured `-- companion n=200`** (same-level elite, Fighter, win% by companion state):

| Level | none | comp L1 | comp L=char | comp x10 |
|-------|------|---------|-------------|----------|
| L10   | 85%  | 84%     | 91%         | 95%      |
| L50   | 25%  | 32%     | 53%         | 71%      |
| L500  | 10%  | 14%     | 31%         | 53%      |
| L2500 | 67%  | 65%     | 81%         | 86%      |
| L10000| 48%  | 45%     | 75%         | 79%      |

Three things fall out of this, and the first is the headline:
- **A level-1 companion is statistically indistinguishable from having NO companion**, at every
  level in the game. The two columns track each other within noise the whole way down. So the
  flat stat bonuses are effectively **decorative** — all of a companion's real value comes from
  ability scaling with level
- Companion **level** therefore does pay, and pays a lot (L500: 10% → 31% → 53%). An earlier
  claim that companions had become inert at high level came from the Orc bug in item 5 and was
  **wrong** — corrected here deliberately so it doesn't get re-derived
- But the payoff **saturates**: at L5000-10000 a 10x over-levelled companion is no better than a
  level-matched one (82/81%, 75/79%). Something caps out up there — worth finding before tuning

Confirmed in code, and it explains the first point exactly:
- **Companion passive stat bonuses do not scale with level at all.** `get_companion_effective_
  bonuses` applies only variant × sub-tier multipliers to a flat table value. A L1 Ogre and a
  L10000 Ogre grant the identical `{attack 5, hp_bonus 3}`
- Only companion **abilities** scale, and only **linearly** (`base + scaling × level`) against
  content that scales far faster
- Real companions are tiny in absolute terms (Dexto's L45 Ogre: attack 5, hp_bonus 3)

- [ ] Make companion **stat bonuses scale with companion level**, not just variant/sub-tier —
      this is what makes a fresh companion feel like nothing at all today
- [ ] Find and fix the **high-level saturation** (x10 stops beating level-matched past ~L5000)
- [ ] Re-shape ability scaling so it keeps pace with content rather than falling behind
- [ ] Give levelling a companion a **visible, worthwhile payoff curve**; make the ways to
      improve one (levels, fusion, sub-tier, variants) legible and reachable
- [ ] Re-run `-- companion` after each change; it is the regression test for this item

### 7. Monster packs (a party of N meets ~N monsters)
Last of the core combat work: packs multiply monsters per fight, so sizing them before 6 fixes
per-monster numbers guarantees a redo.

---

## Dungeon arc

*`docs/design/dungeon_revamp.md` is the master design. Hard constraint throughout: every dungeon
stays **solo-possible**; a party is a force multiplier, never a requirement.*

### 8. Dungeon F — party in dungeons (north star, most architectural)
- [ ] Party **movement** in a shared instance
- [ ] Party combat inside dungeons on the deck system
- [ ] Follower-finishes-boss reward case; per-player equipment/chest loot

*Placed here because it builds on 1 and 2. Doing it earlier means touching party code a third time.*

### 9. Dungeon B — loot / progression / discovery
- [ ] **Dungeon Atlas / Codex** — hub, quest board, what-drops-where, uniques page.
      This is ONE item; it was previously tracked in three separate memos as three tasks.
      Reveal is **hint-based discovery with progression**, not show-all: entering or clearing
      gives full detail, spotting a D tile gives partial, a rumour gives a hint. Hooks into the
      existing rumour, threat and discovery tracking
- [ ] Signature drop per dungeon
- [ ] Broader scattered loot (runes / gear / scrolls, tier-scaled)
- [ ] Companion **Tier-RANK** variety

### 10. Dungeon A — themes (slices 2-4)
- [ ] Theme roll / stamp / display; theme to guaranteed themed egg or companion
- [ ] "Sigil" opt-in modifier consumable
- [ ] **Preserve** both random special-trait dungeons AND the Catalyst/Sigil opt-in — the Atlas
      and meta work must not delete either

### 11. Presentation pass — dungeons, world map, minimap, GUI
*Widened from "Dungeon E" on 2026-09-01 (user): the same pass should look at **how everything is
drawn**, not just dungeons. Kept as ONE item rather than split, because the map, minimap and
dungeon view share rendering code and techniques — doing them separately means solving the same
problem three times. Also owns the website's DUNGEON pages + screenshots (deferred from 4):
dungeons are about to look different, so shooting them first means shooting them twice.*

**Dungeons**
- [ ] Zoom the dungeon view in
- [ ] **Sprites** for chests, traps and floor drops instead of ASCII glyphs (unused sheets in
      `client/sprites/battlers/tf_svbattle/singleframes/`)
- [ ] Stop drawing **walls as tiles** — render non-traversable space as void (Azure Dreams style)
- [ ] Rooms **farther apart**, longer corridors (still too cramped after C3a)

**World map, minimap and GUI** *(user 2026-09-01)*
- [ ] **Explore other ways to draw the ASCII map** — this is exploratory, not a fix list. Try
      alternatives (denser/sparser glyph sets, colour by biome vs by feature, shading for
      elevation or danger, spacing and aspect ratio) and compare them side by side before
      committing
- [ ] Same for the **minimap** — it is currently a shrunken copy of the same view
- [ ] **GUI** — look for cheap wins in the overall frame: panel borders, spacing, headers,
      colour discipline, the empty-panel look (the left panel reads as a black void when there
      is nothing to say)
- [ ] Bias to **easy wins first** — the ask was explicitly "see if there are easy ways to make
      things look better", so time-box the exploration before any large restructure
- [ ] **Overlaps to fold in here, not track separately:** the 1080p default combat layout
      (monster art overlapping the cards) and the remaining UI-scale registrations, both
      currently in *Independent*

### 12. Dungeon D — bosses (after 6, so boss damage is sized against corrected numbers)
- [ ] Real phases, telegraphs and adds. **Telegraph counterplay is mandatory** — no unavoidable
      damage

### 12b. The Phantom — the outward loop (player posts, egg/companion investment)
*User direction 2026-09-02, expanded the same day into a full game loop. Placed here because it
reuses dungeon generation and level scaling (8-12), and because it is the **hard gate on the
player-post suppression floor** in item 6 — that change must not reach players before this exists.*

**THE HOOK — the core loop the game has been missing:**
1. Players push out into the wilderness **as far as they can survive**
2. They found a post there and **stock it with eggs and companions they no longer need**
   (consumed, permanently)
3. They descend into that post's **Phantom** to gear up and win better equipment and companions
4. Once strong enough, they push **further out** and do it again
5. **The farther out, the deeper the Phantom can go, and the better what is inside it** — given
   the right investment

This is the outward pull item 6 concluded the game needs. The difficulty model can never enforce
progression (encounter level is a pure function of position), so the pressure has to come from
the **reward gradient** — and here the player builds that gradient themselves, at the edge of
what they can survive. **The loop IS the answer to item 6's open question.**

**Egg investment — a sink that pays forward across lives**
- Each egg is **consumed** and makes that monster type **more likely to spawn** on the Phantom's
  floors (more harpy eggs than goblin means harpies roam more, goblins remain but rarer)
- Each egg also **buffs the eggs of that type found inside** — stats enhanced *beyond* the normal
  tier/sub-tier ceiling. A goblin egg pulled from a heavily-invested player Phantom is far
  stronger than an identical-tier goblin egg from an overworld one
- Eggs inside are **MUCH rarer — at least 10x** the normal rate. They are the thing a player
  hunts long and hard for; getting one **out alive** and hatching it is the payoff for everything
  invested
- This is what makes surplus eggs valuable instead of clutter, and what a player **carries
  forward onto new characters**

**Companion investment — the gearing axis**
- Companions the player no longer wants are **consumed** to make the **equipment** found in the
  Phantom stronger — the gear a fresh character needs to survive the wilderness outside
- Gives retired companions a dignified use and a second sink for the same oversupply

**Post creation — Valor-purchased prefabs**
- Building a post piece by piece is too slow to support this loop. Add: spend a **large amount of
  Valor** to place a **randomized pre-built post** in a valid area
- Random design/shape, but guaranteed the necessities — **a Phantom and a market**
- **More expensive tiers** include crafting stations and other stations
- Valor's current sinks are bounties, PvP payouts and repairs, so this becomes its major sink —
  size it against those

**Theming (needed — user asked for it).** Draft to write against the setting bible's two voices:
a phantom is a dead place the ground refuses to keep down, which comes back **in the shape it
died in**, and *eggs are the one living thing a dead place produces*. So: the ground under a new
post is already remembering something. **Feeding it eggs teaches it which shapes to wear** — give
it goblins and it comes back up goblin. **Giving it companions** — things that lived alongside
you — is why it returns *possessions*: gear is what the place kept of them. The 10x egg rarity is
the fiction too: a place only rarely produces something still living, and you have to carry it
out past everything else it remembers.

**Open questions and risks, in the order they should be settled:**
- [ ] **6b (companion levelling) is a PREREQUISITE, not a parallel track.** The payoff of this
      entire loop is companions — and today a level-1 companion is statistically identical to no
      companion (measured, n=200). A hard-won 10x-rare buffed egg would hatch into something that
      changes nothing until levelled. Fix companion scaling first or the reward rings hollow
- [ ] **Does investment raise the egg RATE, or only egg QUALITY?** Quality-only is cleaner, but
      10x rarity plus pure RNG means a dry run reads as theft after a heavy investment. Prefer a
      **deterministic floor** (a guaranteed egg at certain depths) so effort always pays, with
      quality as the variable part
- [ ] **Account vs character ownership.** Permadeath means the character who built and stocked
      the post can die. The post and its investment must survive at the **account** level or the
      loop punishes far beyond intent — but what is carried *out* of a run must still be lost on
      death, since "what you brought out alive" is the setting's whole point
- [ ] **Guard against a laundering pump.** Invest cheap eggs, extract better eggs, hatch, invest
      those companions, get better gear, repeat. The exchange must be lossy and gated by **depth
      and survival risk**, never by volume
- [ ] **Phantom-specific monster tiering/scaling** (user 2026-09-02). Seeding a species and
      scaling it by depth needs a model that holds for ANY species at ANY depth. See the
      measurement below — the existing model does not provide one
- [ ] **Scaling shape.** `level(depth) = lerp(1, local_wilderness_level, depth / max_depth)` with
      `max_depth` scaling to how far out the post is. A frontier Phantom is automatically longer
      because it has further to bridge — "near endless" is really "as long as the gap it closes"
- [ ] **Reward gating.** Must gear a fresh character enough to survive locally without becoming
      the best farm in the game for established players
- [ ] Define a **valid area** for placement (min distance from existing posts, terrain rules)
- [ ] Decide whether a Phantom is per-post, per-account or shared, and who else may enter

**MEASURED 2026-09-02 — the species-scaling question, and a correction.** An earlier claim in
item 6 that a scaled-up low-tier monster might be *deadlier* than a native high-tier one was
**wrong**, and the user was right to challenge it. It was inferred from base-table ratios
(HP/STR/DEF per base level all fall steeply from T1 to T9) without checking what the generator
actually produces. Generated at the same level, the picture reverses:

| Generated at L5000 | HP | STR | DEF | abilities |
|---|---|---|---|---|
| Goblin (T1, base lv2) | 15,000 | 712 | 888 | 2 |
| Wolf (T1, base lv3) | 15,000 | 1,021 | 965 | 3 |
| Ancient Dragon (T5) | 280,543 | 4,266 | 5,968 | multi_strike, armored, … |
| Hydra (T7) | 646,942 | 5,975 | 4,780 | regeneration, multi_strike, enrage, … |
| Void Walker (T7) | 677,173 | 6,390 | 5,960 | ethereal, mana_drain, … |

A scaled Goblin is **43x weaker in HP** than a Void Walker at the same level, not stronger — and
high-tier monsters carry far richer ability sets (multi_strike, regeneration, armored, enrage,
ethereal, mana_drain), which is exactly the "other redeeming stats" the user suspected. Base
per-level ratios were a misleading metric on their own.

Two real findings survive, and both bear directly on the Phantom:
- **Low-tier monsters hit an HP CAP when scaled up.** Goblin and Wolf both land on *exactly*
  15,000 HP at L5000 — a ceiling, not a curve. So seeding a Phantom with cheap low-tier eggs and
  descending would produce monsters that stop getting harder with depth while the player keeps
  levelling. That is the actual exploit, and it is the opposite of the one first suspected
- **Avatar of Chaos (base level 6000) generated at L5000 is a runt** — 161,230 HP against Void
  Walker's 677,173 — because it sits below its own base level and takes the linear downscale
  path. Whether `select_monster_type` routinely picks below-base monsters at high level is a live
  candidate for the late-game difficulty slide in item 6, and is **not yet measured**

Conclusion: the Phantom needs its **own scaling model** rather than reusing the overworld one.
Depth must set difficulty for **any** seeded species, so the model has to be anchored to depth
(and through it to a reference player) rather than to each monster's hand-authored base_level.
This is the same conclusion item 6 reached for the overworld, which is a good sign: **one
reference-player-anchored monster model serves both.**

---

## Then

### 13. Roguelike loop — why progress doesn't FEEL like progress
*User direction 2026-09-01: "I don't much like the options available. It's hard for players to
feel like they are making much progress." Placed BEFORE the Sanctuary redesign (14) and the
realm meta-loop (15), because both of those build the vehicles for whatever this decides —
building sinks and rooms before deciding what a run should leave behind is how you get
features nobody feels.*

- [ ] Name what actually carries between lives today, and be honest about how thin it is:
      account level? Sanctuary contents? kennel companions? titles/Valor? mastery? — then say
      which of those a player can *perceive* after a death
- [ ] The core question: **what should a single run leave behind?** The setting bible already
      answers it thematically — *what you brought out alive* — so the mechanics should make
      companions and the Sanctuary the felt progression, not a stat number
- [ ] Audit the current between-lives options; the user finds them uncompelling. Say why
      (too few? too slow? invisible? not chosen by the player?) before designing replacements
- [ ] Look at how the genre solves this (persistent unlocks, meta-currency, run modifiers,
      collection completion) and pick deliberately. **Candidate already on the table: player
      phantoms (14)** — your dead characters persisting as things in the world — permadeath without felt accumulation is
      the retention risk here
- [ ] **Watch for overlap:** the egg/companion *sinks* live in 15; this item decides what
      progression should feel like, 15 spends it

### 14. Player phantoms — the dead don't leave
*User direction 2026-09-02. This fell straight out of the theming rather than being invented
for it: if what is down there makes delvers into phantoms, then a dead character IS one, and
phantoms roam. Placed immediately after 13 because 13 decides what a run should leave behind
and this is the strongest candidate answer on the table — a character who dies becomes
something other players meet.*

- [ ] Design what a player phantom **is**: a permadead character returning with their build,
      class, gear and battler sprite, roaming near where they fell. Meeting a former top-ranked
      player as a thing in the world is the whole appeal — keep the identity legible
- [ ] Decide what an encounter with one **does**: hunts the living, wanders a territory, or
      guards the corpse it came from
- [ ] What killing one yields, and — the part that matters for 13 — **what the dead player
      gets**. If your past characters persist as marks on the world, permadeath starts adding
      something instead of only taking it away
- [ ] **Constraint, performance:** "visible roaming entities" sits in *Hard-deferred* over
      exactly this cost. Revisit that gate deliberately rather than by accident. A phantom that
      exists only near its own death site, and only while a player is in range, may sidestep the
      original objection — confirm before designing around it
- [ ] **Constraint, balance and griefing:** a level 200 phantom parked near a starter post is a
      wall a new player cannot pass. Needs level-banding, scaling, or placement rules
- [ ] **Consent question:** do players want their dead hunting other people? Decide whether it
      is opt-in, opt-out, or unconditional — and note that unconditional is the most thematically
      honest and the most likely to annoy someone
- [ ] Hooks that already exist: corpses spawn where a character fell, the leaderboard remembers
      names, and battler sprites already reflect equipment
- [ ] Overlaps to fold in, not track twice: the *living world* strand of 16, and the
      *Hard-deferred* roaming-entities line

### 15. Sanctuary redesign — put the house in the world
*User direction 2026-09-01. After 13 so it implements a decided progression, and adjacent to 15
so the companion activities are designed once, not twice.*

- [ ] **Root it in the world.** Today the Sanctuary is a menu between login and character
      select (`HOUSE_SCREEN`). The user wants it to be a real place — near the starting post
      is the suggested anchor — so going home is travel, not a screen
- [ ] **Do it responsibly at scale.** Prior art exists: player posts already claim real tiles
      (`add_player_tile` / `get_player_tiles` / enclosure checks), so the sparse-tile storage
      pattern is proven. Decide early between a shared world district, an instanced interior on
      a world doorway, or true claimed land — the choice drives chunk cost, griefing and what
      happens when thousands of accounts each own ground
- [ ] **Customisation** — the user wants the house to be personal, not a fixed room
- [ ] **More to DO with companions there.** Coordinate with 15's breeders / trainers / tasks
      rather than inventing a parallel set; the Sanctuary is the natural home for several
- [ ] Keep what already works: account-level persistence through permadeath, the kennel
      (30-500 slots) and the Fusion Station

### 16. Realm meta-loop
- [ ] Reorient **questing onto dungeons** (clear / rescue / boss-hunt / gather). The quest types
      already exist; the work is generation and surfacing, not new types
- [ ] Real **sinks for excess eggs and companions** *(design these WITH 14 — the Sanctuary is
      the natural home for several, and 13 decides what they should feel like)*: shops that buy and sell, breeders, trainers,
      fusers (fusion exists — expand), companion **tasks**
- [ ] Living world: rework posts, companions around posts, threats woven in

### 17. Engagement / minigame variety
- [ ] Prize Shuffle redesign: gathering and crafting slices (combat slice shipped)
- [ ] Port the Chain / Mystery / Trap mechanics to gathering and crafting
- [ ] Trap chests, Mimic chest variant, 2 remaining dungeon-exclusive consumables

---

### 18. Craft review — the game against industry standards
*User direction 2026-09-01. Placed LAST of the numbered items because a best-practices pass run
while combat numbers (6) and the whole dungeon arc (8-12) are mid-rework would produce findings
that expire before they can be acted on. The parts that DON'T depend on in-flight work —
onboarding, accessibility, input conventions, save/data safety, performance, settings coverage
— are stable today and can be pulled forward at any time.*

- [ ] Audit the game as a game: onboarding and first-session experience, moment-to-moment
      feedback, difficulty curve, session shape, retention loops, readability/accessibility,
      settings and input conventions, save/data safety, performance
- [ ] Name concretely where it falls short rather than listing generic best practice, and rank
      the gaps by player impact against cost to fix
- [ ] Turn the ranked gaps into backlog items in the right order, rather than one sprawling
      "polish" task
- [ ] Existing threads this will likely absorb or supersede: the UX revamp arc, the tutorial +
      starter-quest item, and the unspent-stat-point nudge

## Independent — slot in any time (no dependencies)
- [ ] Card market live list-to-buy smoke test (built, never exercised end to end)
- [ ] Launcher revamp + in-game feedback inbox
- [ ] UI-scale registration for remaining elements (action bar, inventory, market, crafting...)
- [ ] Unspent stat-point "+" badge (players forget they have points)
- [ ] Combat default layout at 1080p (cards overlap the monster art)
- [ ] Companion cosmetics: ASCII border + shadow layer (data layer already shipped)
- [ ] Merchant/market **baseline NPC stock** — merchants only equalise player listings, so
      off-circuit posts stay bare
- [ ] Tutorial + starter quest chains for a zero-gear character
- [ ] Patreon + Founder title (implementation planned, awaiting greenlight)
- [ ] Item variety — duplicates should be rare
- [ ] Ability-card level-up progress fill, draggable action bar, plain-language skill text
- [ ] Salvage preview: tell the player what they get before salvaging
- [ ] Variant Imprint Atlas page (Sanctuary)
- [ ] Bug-reporting system: end-to-end test on production (shipped, never verified live)
- [ ] ARPG pillar 5: endgame rift runs

## Hard-deferred (documented reason — revisit only if the reason changes)
- Visible roaming entities (performance gate) — **now has a design reason to revisit: see 14,
  player phantoms.** Do not un-defer casually; the gate was cost, and that cost has not changed
- Full ability mastery as a progression vector (multi-session arc)
- Group raids
- Full mentor matching
- Biome-specific mechanics (movement, weather, biome-locked monsters and resources)
- Multiple saved decks, swap-on-the-fly, true drag-and-drop (needs server work)

## Watch items (not tasks — things that must not regress)
- **The from-source client remembers the last host** and all clients share one settings file, so
  a single manual connect to production silently sends later local test runs to the LIVE server.
  The harness forces `--server=localhost` and the client prints its target; don't remove that
- **Permadeath may change** — do not harden "death is permanent" into copy or design pillars
- **Archive with discussion** — removing game elements is allowed, but discuss first; improving
  beats removing. Crafting was flagged as "not in a good spot at all"
- **Early-game survivability** — resource cost scaling still open; starter weapon at creation
  deferred pending playtest

---

## Recently shipped
- **2026-09-02 (site + docs, no client build)** — website refresh live: setting-led copy that
  explains the name, real in-game screenshots, accuracy fixes (Linux support, party of 5,
  deck-driven combat). Setting bible revised to a single cause. Screenshot capture harness added

- **v0.9.740** — party leadership rotation + duplicated rewards, follower/post rules, party of 5,
  buff + item targeting (teammates and their companions), co-op playback pacing (rounds play fast
  but complete; Continue skips *to* the rewards), Forcefield/Haste co-op fixes
- **v0.9.739** — co-op combat you can follow (one animation clock), party items, party permadeath,
  login sprite offset, relog full-heal fix, 2-client test harness (`tools/test_setup/`)
- **v0.9.738** — real co-op party combat (shared fight, party cards, per-actor playback)
- **v0.9.735** — card arc: dungeon-exclusive cards, card market, class roster pass, FPS cap
